extends Node
## Brewing stations and active jobs. Autoloaded as "Brewing".
## See docs/design/systems.md, system 4.
##
## Ownership of *where* a station exists and whether it's been bought lives
## in the Placement autoload now (see system 4's Placement System
## sub-section) -- a "station" is just any ComponentInstance whose
## ComponentDef.category == "alembic". This autoload only owns *brewing*
## state: the active BrewJob and equipped upgrade ids per station id, keyed
## by component id rather than held on a StationInstance array.

signal brew_started(station_id: String, recipe_id: String)
signal brew_ready(station_id: String, recipe_id: String)
signal brew_collected(station_id: String, recipe_id: String, potency: float, ease_value: float)
signal brew_botched(station_id: String, recipe_id: String)
signal brew_roll_resolved(station_id: String, recipe_id: String, roll: Dictionary)
signal alembic_upgrade_purchased(station_id: String, upgrade_id: String)
signal alembic_upgrade_removed(station_id: String, upgrade_id: String)

const XP_PER_BREW := 20
const BOTCH_RESOLVE_COST := 15
const DICE_DC := 11.0          # 2d10 midpoint -- coinflip-ish, no per-recipe tuning needed
const STAT_VARIANCE := 5.0     # quiet +/- wobble applied to potency/ease independently

var current_jobs: Dictionary = {}          # component_id -> BrewJob
var alembic_upgrade_ids: Dictionary = {}   # component_id -> Array[String]


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)


func get_current_job(station_id: String) -> BrewJob:
	return current_jobs.get(station_id)


func _is_alembic(station_id: String) -> bool:
	var instance := Placement.get_component(station_id)
	if instance == null:
		return false
	var def := ContentRegistry.get_component_def(instance.def_id)
	return def != null and def.category == "alembic"


## Returns "" on success, or a short reason string on failure. Mutual
## exclusion is checked both directions — the new upgrade's own `excludes`
## against what's owned, and each owned upgrade's `excludes` against the new
## id — so it doesn't matter which of an exclusive pair was bought first.
func purchase_alembic_upgrade(station_id: String, upgrade_id: String) -> String:
	if not _is_alembic(station_id):
		return "No such station."
	var owned_ids: Array = alembic_upgrade_ids.get(station_id, [])
	if upgrade_id in owned_ids:
		return "Already purchased."
	var upgrade := ContentRegistry.get_alembic_upgrade(upgrade_id)
	if upgrade == null:
		return "No such upgrade."
	for owned_id in owned_ids:
		if owned_id in upgrade.excludes:
			return "Conflicts with an equipped upgrade."
		var owned := ContentRegistry.get_alembic_upgrade(owned_id)
		if owned != null and upgrade_id in owned.excludes:
			return "Conflicts with an equipped upgrade."
	var spend_err := Inventory.try_spend_materials(upgrade.cost)
	if spend_err != "":
		return spend_err
	owned_ids.append(upgrade_id)
	alembic_upgrade_ids[station_id] = owned_ids
	alembic_upgrade_purchased.emit(station_id, upgrade_id)
	return ""


## No refund — removing an upgrade is a respec, not a return.
func remove_alembic_upgrade(station_id: String, upgrade_id: String) -> void:
	var owned_ids: Array = alembic_upgrade_ids.get(station_id, [])
	owned_ids.erase(upgrade_id)
	alembic_upgrade_ids[station_id] = owned_ids
	alembic_upgrade_removed.emit(station_id, upgrade_id)


func _upgrade_bonus(station_id: String, effect_target: String) -> float:
	var total := 0.0
	for upgrade_id in alembic_upgrade_ids.get(station_id, []):
		var upgrade := ContentRegistry.get_alembic_upgrade(upgrade_id)
		if upgrade != null:
			total += upgrade.effects.get(effect_target, 0.0)
	return total


func _has_tag(station_id: String, tag: String) -> bool:
	for upgrade_id in alembic_upgrade_ids.get(station_id, []):
		var upgrade := ContentRegistry.get_alembic_upgrade(upgrade_id)
		if upgrade != null and tag in upgrade.tags:
			return true
	return false


## Every placed Pantry-category component sharing this zone -- see
## docs/design/systems.md, system 4. Confirmed design: linkage is "same zone,
## any distance," not adjacency-gated (unlike Accelerator's brew_speed bonus).
func _linked_pantries(zone_id: String) -> Array[String]:
	var result: Array[String] = []
	if zone_id == "":
		return result
	for component in Placement.get_components_in_zone(zone_id):
		if not component.placed:
			continue
		var def := ContentRegistry.get_component_def(component.def_id)
		if def != null and def.category == "pantry":
			result.append(component.id)
	return result


## The player's carried count for this ingredient plus whatever's stocked in
## every Pantry placed in this station's zone -- what the brew menu and
## start_brew() both treat as "available" at this station.
func available_ingredient_count(station_id: String, ingredient_id: String) -> int:
	var total := Inventory.ingredient_count(ingredient_id)
	var instance := Placement.get_component(station_id)
	if instance == null:
		return total
	for pantry_id in _linked_pantries(instance.zone_id):
		total += Inventory.pantry_ingredient_count(pantry_id, ingredient_id)
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
func _consume_for_brew(station_id: String, recipe: RecipeDef) -> float:
	var instance := Placement.get_component(station_id)
	var linked := _linked_pantries(instance.zone_id) if instance != null else []
	var bonus_total := 0.0
	var bonus_weight := 0
	for i in recipe.ingredient_ids.size():
		var id := recipe.ingredient_ids[i]
		var need := recipe.ingredient_quantities[i]
		for pantry_id in linked:
			if need <= 0:
				break
			var have := Inventory.pantry_ingredient_count(pantry_id, id)
			var take := mini(have, need)
			if take > 0:
				for record in Inventory.consume_from_pantry(pantry_id, id, take):
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
	if not _is_alembic(station_id):
		return "No such station."
	if current_jobs.has(station_id):
		return "Station is already brewing something."
	var potion := ContentRegistry.get_potion(recipe.output_potion_id)
	var def := ContentRegistry.get_component_def(Placement.get_component(station_id).def_id)
	if potion.station_type != def.category:
		return "This recipe needs a %s." % potion.station_type
	if not Alchemy.is_learned(recipe.id):
		return "You haven't learned this recipe yet."
	if not has_ingredients_for(station_id, recipe):
		return "Not enough ingredients."

	var quality_bonus := _consume_for_brew(station_id, recipe)

	var potency_modifier := Skills.get_bonus("station_potency") + _upgrade_bonus(station_id, "potion_potency")
	var ease_modifier := Skills.get_bonus("station_ease") + _upgrade_bonus(station_id, "potion_ease")

	var modifier := (potency_modifier + ease_modifier) / 2.0
	var roll := Rng.roll_2d10(modifier, DICE_DC)
	brew_roll_resolved.emit(station_id, recipe.id, roll)

	# A critical failure never occupies the station -- it fails right away
	# instead of consuming the full brew time first. The "ignore_critical_failure"
	# upgrade tag (e.g. Reinforced Vials) downgrades a critical failure to a
	# normal result instead, so the station stays usable and Resolve is spared.
	if roll.critical_failure and not _has_tag(station_id, "ignore_critical_failure"):
		Resolve.spend(BOTCH_RESOLVE_COST, "botched brew: %s" % recipe.display_name)
		brew_botched.emit(station_id, recipe.id)
		return ""

	var job := BrewJob.new()
	job.recipe = recipe
	job.start_timestamp = Clock.get_timestamp()

	# Base speed is 1.0 (StationInstance.speed_modifier's old default -- no
	# station type varies this on its own); Accelerator's contribution is
	# queried live from grid adjacency, never baked into a stored field, so
	# rearranging Accelerators always reflects instantly on the next brew.
	var speed_modifier := 1.0 + Skills.get_bonus("station_speed") + _upgrade_bonus(station_id, "brew_speed") + Placement.adjacency_bonus(station_id, "brew_speed")
	var brew_minutes := potion.brew_time_minutes
	if speed_modifier > 0.0:
		brew_minutes = int(brew_minutes / speed_modifier)
	job.ready_timestamp = job.start_timestamp + brew_minutes

	var t := clampf(inverse_lerp(2.0, 30.0, roll.total), 0.0, 1.0)
	job.rolled_potency = clampf(lerp(potion.potency_range.x, potion.potency_range.y, t) + Rng.range_f(-STAT_VARIANCE, STAT_VARIANCE) + quality_bonus, 0.0, 100.0)
	job.rolled_ease = clampf(lerp(potion.ease_range.x, potion.ease_range.y, t) + Rng.range_f(-STAT_VARIANCE, STAT_VARIANCE) + quality_bonus, 0.0, 100.0)
	job.potion_count = 2 if roll.critical_success else 1
	job.status = BrewJob.Status.BREWING

	current_jobs[station_id] = job
	brew_started.emit(station_id, recipe.id)
	return ""


## Returns false without changing anything if there's nothing ready to
## collect, or if there's not enough potion inventory room -- the caller
## (interacting with a finished station) is expected to leave the job in
## place and let the player try again once they've made room.
func collect(station_id: String) -> bool:
	var job: BrewJob = current_jobs.get(station_id)
	if job == null or job.status != BrewJob.Status.READY:
		return false
	if not Inventory.has_room_for_potions(job.potion_count):
		return false

	current_jobs.erase(station_id)
	for i in job.potion_count:
		Inventory.add_potion(job.recipe.output_potion_id, job.rolled_potency, job.rolled_ease)
	Skills.add_xp("alchemy", XP_PER_BREW)
	brew_collected.emit(station_id, job.recipe.id, job.rolled_potency, job.rolled_ease)
	return true


func _on_minute_tick(timestamp: int) -> void:
	for station_id in current_jobs:
		var job: BrewJob = current_jobs[station_id]
		if job.status == BrewJob.Status.BREWING and job.is_due(timestamp):
			job.status = BrewJob.Status.READY
			brew_ready.emit(station_id, job.recipe.id)


func get_save_data() -> Dictionary:
	var jobs_data: Array[Dictionary] = []
	for station_id in current_jobs:
		var job: BrewJob = current_jobs[station_id]
		jobs_data.append({
			"station_id": station_id,
			"recipe_id": job.recipe.id,
			"start_timestamp": job.start_timestamp,
			"ready_timestamp": job.ready_timestamp,
			"rolled_potency": job.rolled_potency,
			"rolled_ease": job.rolled_ease,
			"status": int(job.status),
			"potion_count": job.potion_count,
		})
	var upgrades_data: Dictionary = {}
	for station_id in alembic_upgrade_ids:
		upgrades_data[station_id] = (alembic_upgrade_ids[station_id] as Array).duplicate()
	return {"current_jobs": jobs_data, "alembic_upgrade_ids": upgrades_data}


func load_save_data(data: Dictionary) -> void:
	current_jobs.clear()
	for entry in (data.get("current_jobs", []) as Array):
		var job := BrewJob.new()
		job.recipe = Alchemy.get_learned_recipe(entry.get("recipe_id", ""))
		job.start_timestamp = entry.get("start_timestamp", 0)
		job.ready_timestamp = entry.get("ready_timestamp", 0)
		job.rolled_potency = entry.get("rolled_potency", 0.0)
		job.rolled_ease = entry.get("rolled_ease", 0.0)
		job.status = entry.get("status", BrewJob.Status.BREWING) as BrewJob.Status
		job.potion_count = entry.get("potion_count", 1)
		current_jobs[entry.get("station_id", "")] = job

	alembic_upgrade_ids.clear()
	var saved_upgrades: Dictionary = data.get("alembic_upgrade_ids", {})
	for station_id in saved_upgrades:
		var ids: Array[String] = []
		ids.assign(saved_upgrades[station_id])
		alembic_upgrade_ids[station_id] = ids
