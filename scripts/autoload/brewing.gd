extends Node
## Brewing stations and active jobs. Autoloaded as "Brewing".
## See docs/design/systems.md, system 4.

signal brew_started(station_id: String, recipe_id: String)
signal brew_ready(station_id: String, recipe_id: String)
signal brew_collected(station_id: String, recipe_id: String, potency: float, ease_value: float)
signal brew_botched(station_id: String, recipe_id: String)
signal brew_roll_resolved(station_id: String, recipe_id: String, roll: Dictionary)
signal station_purchased(station_id: String)
signal alembic_upgrade_purchased(station_id: String, upgrade_id: String)
signal alembic_upgrade_removed(station_id: String, upgrade_id: String)

const XP_PER_BREW := 20
const BOTCH_RESOLVE_COST := 15
const DICE_DC := 11.0          # 2d10 midpoint -- coinflip-ish, no per-recipe tuning needed
const STAT_VARIANCE := 5.0     # quiet +/- wobble applied to potency/ease independently

var stations: Array[StationInstance] = []


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)


func get_station(station_id: String) -> StationInstance:
	for station in stations:
		if station.id == station_id:
			return station
	return null


## Idempotent — called by RoomBuilder as each hand-placed BrewStationInteractable
## is wired, so a station exists as soon as its Alembic node loads regardless of
## whether it's purchased yet. If `id` is already registered (e.g. a save was
## already loaded before rooms wired), its *live* state (purchased/upgrade_ids/
## current_job) is left untouched, but the *scene-derived* fields below are
## always refreshed to match the current wiring -- otherwise a station saved
## before a field like lab_manager_id existed would keep it empty forever,
## since the idempotent path would never let a freshly-wired value in.
func register_station(id: String, display_name: String, station_type: String, cost: int, lab_manager_id: String = "") -> StationInstance:
	var existing := get_station(id)
	if existing != null:
		existing.display_name = display_name
		existing.station_type = station_type
		existing.cost = cost
		existing.lab_manager_id = lab_manager_id
		return existing
	var station := StationInstance.new()
	station.id = id
	station.display_name = display_name
	station.station_type = station_type
	station.cost = cost
	station.purchased = cost <= 0
	station.lab_manager_id = lab_manager_id
	stations.append(station)
	return station


## Returns "" on success, or a short reason string on failure.
func purchase_station(station_id: String) -> String:
	var station := get_station(station_id)
	if station == null:
		return "No such station."
	if station.purchased:
		return "Already purchased."
	if not Inventory.spend_materials(station.cost):
		return "Not enough Materials."
	station.purchased = true
	station_purchased.emit(station_id)
	return ""


## Returns "" on success, or a short reason string on failure. Mutual
## exclusion is checked both directions — the new upgrade's own `excludes`
## against what's owned, and each owned upgrade's `excludes` against the new
## id — so it doesn't matter which of an exclusive pair was bought first.
func purchase_alembic_upgrade(station_id: String, upgrade_id: String) -> String:
	var station := get_station(station_id)
	if station == null:
		return "No such station."
	if not station.purchased:
		return "Station hasn't been purchased yet."
	if upgrade_id in station.upgrade_ids:
		return "Already purchased."
	var upgrade := ContentRegistry.get_alembic_upgrade(upgrade_id)
	if upgrade == null:
		return "No such upgrade."
	for owned_id in station.upgrade_ids:
		if owned_id in upgrade.excludes:
			return "Conflicts with an equipped upgrade."
		var owned := ContentRegistry.get_alembic_upgrade(owned_id)
		if owned != null and upgrade_id in owned.excludes:
			return "Conflicts with an equipped upgrade."
	if not Inventory.spend_materials(upgrade.cost):
		return "Not enough Materials."
	station.upgrade_ids.append(upgrade_id)
	alembic_upgrade_purchased.emit(station_id, upgrade_id)
	return ""


## No refund — removing an upgrade is a respec, not a return.
func remove_alembic_upgrade(station_id: String, upgrade_id: String) -> void:
	var station := get_station(station_id)
	if station == null:
		return
	station.upgrade_ids.erase(upgrade_id)
	alembic_upgrade_removed.emit(station_id, upgrade_id)


func _upgrade_bonus(station: StationInstance, effect_target: String) -> float:
	var total := 0.0
	for upgrade_id in station.upgrade_ids:
		var upgrade := ContentRegistry.get_alembic_upgrade(upgrade_id)
		if upgrade != null:
			total += upgrade.effects.get(effect_target, 0.0)
	return total


func _has_tag(station: StationInstance, tag: String) -> bool:
	for upgrade_id in station.upgrade_ids:
		var upgrade := ContentRegistry.get_alembic_upgrade(upgrade_id)
		if upgrade != null and tag in upgrade.tags:
			return true
	return false


## Every purchased Pantry sharing this station's Alchemy Lab Manager -- see
## docs/design/systems.md, system 4. A station with no lab_manager_id (no
## linked manager) never has any.
func _linked_pantries(station: StationInstance) -> Array[PantryInstance]:
	var result: Array[PantryInstance] = []
	if station.lab_manager_id == "":
		return result
	for pantry in Inventory.pantries:
		if pantry.purchased and pantry.lab_manager_id == station.lab_manager_id:
			result.append(pantry)
	return result


## The player's carried count for this ingredient plus whatever's stocked in
## every Pantry linked to this station's Alchemy Lab Manager -- what the
## brew menu and start_brew() both treat as "available" at this station.
## Falls back to plain carried inventory if station_id doesn't resolve.
func available_ingredient_count(station_id: String, ingredient_id: String) -> int:
	var total := Inventory.ingredient_count(ingredient_id)
	var station := get_station(station_id)
	if station == null:
		return total
	for pantry in _linked_pantries(station):
		total += Inventory.pantry_ingredient_count(pantry.id, ingredient_id)
	return total


func has_ingredients_for(station_id: String, recipe: RecipeDef) -> bool:
	for i in recipe.ingredient_ids.size():
		if available_ingredient_count(station_id, recipe.ingredient_ids[i]) < recipe.ingredient_quantities[i]:
			return false
	return true


## Drains linked pantries first (so stocked-up Pantry supply goes before the
## player's carried buffer), then falls back to Inventory.consume_ingredient
## for any remainder. Both draws are highest-quality-first (Inventory's own
## draining order); returns the quantity-weighted average quality bonus
## across everything consumed, for start_brew() to apply to the roll.
func _consume_for_brew(station: StationInstance, recipe: RecipeDef) -> float:
	var linked := _linked_pantries(station)
	var bonus_total := 0.0
	var bonus_weight := 0
	for i in recipe.ingredient_ids.size():
		var id := recipe.ingredient_ids[i]
		var need := recipe.ingredient_quantities[i]
		for pantry in linked:
			if need <= 0:
				break
			var have := Inventory.pantry_ingredient_count(pantry.id, id)
			var take := mini(have, need)
			if take > 0:
				for record in Inventory.consume_from_pantry(pantry.id, id, take):
					bonus_total += IngredientQuality.brew_bonus(record["tier"]) * record["quantity"]
					bonus_weight += record["quantity"]
				need -= take
		if need > 0:
			for record in Inventory.consume_ingredient_records(id, need):
				bonus_total += IngredientQuality.brew_bonus(record["tier"]) * record["quantity"]
				bonus_weight += record["quantity"]
	return bonus_total / bonus_weight if bonus_weight > 0 else 0.0


## Returns "" on success, or a short reason string on failure (station busy,
## missing ingredients) so the calling UI can report why the brew didn't start.
func start_brew(station_id: String, recipe: RecipeDef) -> String:
	var station := get_station(station_id)
	if station == null:
		return "No such station."
	if station.current_job != null:
		return "Station is already brewing something."
	var potion := ContentRegistry.get_potion(recipe.output_potion_id)
	if potion.station_type != station.station_type:
		return "This recipe needs a %s." % potion.station_type
	if not Alchemy.is_learned(recipe.id):
		return "You haven't learned this recipe yet."
	if not has_ingredients_for(station_id, recipe):
		return "Not enough ingredients."

	var quality_bonus := _consume_for_brew(station, recipe)

	var potency_modifier := station.potency_modifier + Skills.get_bonus("station_potency") + _upgrade_bonus(station, "potion_potency")
	var ease_modifier := station.ease_modifier + Skills.get_bonus("station_ease") + _upgrade_bonus(station, "potion_ease")

	var modifier := (potency_modifier + ease_modifier) / 2.0
	var roll := Rng.roll_2d10(modifier, DICE_DC)
	brew_roll_resolved.emit(station.id, recipe.id, roll)

	# A critical failure never occupies the station -- it fails right away
	# instead of consuming the full brew time first. The "ignore_critical_failure"
	# upgrade tag (e.g. Reinforced Vials) downgrades a critical failure to a
	# normal result instead, so the station stays usable and Resolve is spared.
	if roll.critical_failure and not _has_tag(station, "ignore_critical_failure"):
		Resolve.spend(BOTCH_RESOLVE_COST, "botched brew: %s" % recipe.display_name)
		brew_botched.emit(station.id, recipe.id)
		return ""

	var job := BrewJob.new()
	job.recipe = recipe
	job.start_timestamp = Clock.get_timestamp()

	var speed_modifier := station.speed_modifier + Skills.get_bonus("station_speed") + _upgrade_bonus(station, "brew_speed")
	var brew_minutes := potion.brew_time_minutes
	if speed_modifier > 0.0:
		brew_minutes = int(brew_minutes / speed_modifier)
	job.ready_timestamp = job.start_timestamp + brew_minutes

	var t := clampf(inverse_lerp(2.0, 30.0, roll.total), 0.0, 1.0)
	job.rolled_potency = clampf(lerp(potion.potency_range.x, potion.potency_range.y, t) + Rng.range_f(-STAT_VARIANCE, STAT_VARIANCE) + quality_bonus, 0.0, 100.0)
	job.rolled_ease = clampf(lerp(potion.ease_range.x, potion.ease_range.y, t) + Rng.range_f(-STAT_VARIANCE, STAT_VARIANCE) + quality_bonus, 0.0, 100.0)
	job.potion_count = 2 if roll.critical_success else 1
	job.status = BrewJob.Status.BREWING

	station.current_job = job
	brew_started.emit(station.id, recipe.id)
	return ""


## Returns false without changing anything if there's nothing ready to
## collect, or if there's not enough potion inventory room -- the caller
## (interacting with a finished station) is expected to leave the job in
## place and let the player try again once they've made room.
func collect(station_id: String) -> bool:
	var station := get_station(station_id)
	if station == null or station.current_job == null:
		return false
	var job := station.current_job
	if job.status != BrewJob.Status.READY:
		return false
	if not Inventory.has_room_for_potions(job.potion_count):
		return false

	station.current_job = null
	for i in job.potion_count:
		Inventory.add_potion(job.recipe.output_potion_id, job.rolled_potency, job.rolled_ease)
	Skills.add_xp("alchemy", XP_PER_BREW)
	brew_collected.emit(station.id, job.recipe.id, job.rolled_potency, job.rolled_ease)
	return true


func _on_minute_tick(timestamp: int) -> void:
	for station in stations:
		var job := station.current_job
		if job and job.status == BrewJob.Status.BREWING and timestamp >= job.ready_timestamp:
			job.status = BrewJob.Status.READY
			brew_ready.emit(station.id, job.recipe.id)


func get_save_data() -> Dictionary:
	var station_data: Array[Dictionary] = []
	for station in stations:
		var job_data = null
		if station.current_job != null:
			var job := station.current_job
			job_data = {
				"recipe_id": job.recipe.id,
				"start_timestamp": job.start_timestamp,
				"ready_timestamp": job.ready_timestamp,
				"rolled_potency": job.rolled_potency,
				"rolled_ease": job.rolled_ease,
				"status": int(job.status),
				"potion_count": job.potion_count,
			}
		station_data.append({
			"id": station.id,
			"display_name": station.display_name,
			"station_type": station.station_type,
			"potency_modifier": station.potency_modifier,
			"ease_modifier": station.ease_modifier,
			"speed_modifier": station.speed_modifier,
			"cost": station.cost,
			"purchased": station.purchased,
			"upgrade_ids": station.upgrade_ids.duplicate(),
			"lab_manager_id": station.lab_manager_id,
			"current_job": job_data,
		})
	return {"stations": station_data}


## Rebuilds `stations` from scratch rather than patching the boot-time
## default from _setup_default_stations() — station count is itself save
## data (future upgrades can add stations), not a fixed set to mutate in place.
func load_save_data(data: Dictionary) -> void:
	stations.clear()
	var station_data: Array = data.get("stations", [])
	for entry in station_data:
		var station := StationInstance.new()
		station.id = entry.get("id", "")
		station.display_name = entry.get("display_name", "")
		station.station_type = entry.get("station_type", "")
		station.potency_modifier = entry.get("potency_modifier", 0.0)
		station.ease_modifier = entry.get("ease_modifier", 0.0)
		station.speed_modifier = entry.get("speed_modifier", 1.0)
		station.cost = entry.get("cost", 0)
		station.purchased = entry.get("purchased", true)
		var upgrade_ids: Array[String] = []
		upgrade_ids.assign(entry.get("upgrade_ids", []))
		station.upgrade_ids = upgrade_ids
		station.lab_manager_id = entry.get("lab_manager_id", "")

		var job_data = entry.get("current_job")
		if job_data != null:
			var job := BrewJob.new()
			job.recipe = Alchemy.get_learned_recipe(job_data.get("recipe_id", ""))
			job.start_timestamp = job_data.get("start_timestamp", 0)
			job.ready_timestamp = job_data.get("ready_timestamp", 0)
			job.rolled_potency = job_data.get("rolled_potency", 0.0)
			job.rolled_ease = job_data.get("rolled_ease", 0.0)
			job.status = job_data.get("status", BrewJob.Status.BREWING) as BrewJob.Status
			job.potion_count = job_data.get("potion_count", 1)
			station.current_job = job

		stations.append(station)
