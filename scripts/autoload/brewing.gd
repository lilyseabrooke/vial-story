extends Node
## Brewing stations and active jobs. Autoloaded as "Brewing".
## See docs/design/systems.md, system 4.

signal brew_started(station_id: String, recipe_id: String)
signal brew_ready(station_id: String, recipe_id: String)
signal brew_collected(station_id: String, recipe_id: String, potency: float, ease_value: float)
signal brew_botched(station_id: String, recipe_id: String)
signal brew_roll_resolved(station_id: String, recipe_id: String, roll: Dictionary)

const XP_PER_BREW := 20
const BOTCH_RESOLVE_COST := 15
const DICE_DC := 11.0          # 2d10 midpoint -- coinflip-ish, no per-recipe tuning needed
const STAT_VARIANCE := 5.0     # quiet +/- wobble applied to potency/ease independently

var stations: Array[StationInstance] = []


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)
	_setup_default_stations()


func _setup_default_stations() -> void:
	var station := StationInstance.new()
	station.id = "alembic_1"
	station.display_name = "Alembic I"
	station.station_type = "alembic"
	stations.append(station)


func get_station(station_id: String) -> StationInstance:
	for station in stations:
		if station.id == station_id:
			return station
	return null


## Returns "" on success, or a short reason string on failure (station busy,
## missing ingredients) so the calling UI can report why the brew didn't start.
func start_brew(station_id: String, recipe: RecipeDef) -> String:
	var station := get_station(station_id)
	if station == null:
		return "No such station."
	if station.current_job != null:
		return "Station is already brewing something."
	if recipe.station_type != station.station_type:
		return "This recipe needs a %s." % recipe.station_type
	if not Inventory.has_ingredients_for(recipe):
		return "Not enough ingredients."

	Inventory.consume_ingredients_for(recipe)

	var job := BrewJob.new()
	job.recipe = recipe
	job.start_timestamp = Clock.get_timestamp()

	var speed_modifier := station.speed_modifier + Skills.get_bonus("station_speed")
	var brew_minutes := recipe.brew_time_minutes
	if speed_modifier > 0.0:
		brew_minutes = int(brew_minutes / speed_modifier)
	job.ready_timestamp = job.start_timestamp + brew_minutes

	var potency_modifier := station.potency_modifier + Skills.get_bonus("station_potency")
	var ease_modifier := station.ease_modifier + Skills.get_bonus("station_ease")

	var modifier := (potency_modifier + ease_modifier) / 2.0
	var roll := Rng.roll_2d10(modifier, DICE_DC)
	var t := clampf(inverse_lerp(2.0, 30.0, roll.total), 0.0, 1.0)

	job.rolled_potency = clampf(lerp(recipe.potency_range.x, recipe.potency_range.y, t) + Rng.range_f(-STAT_VARIANCE, STAT_VARIANCE), 0.0, 100.0)
	job.rolled_ease = clampf(lerp(recipe.ease_range.x, recipe.ease_range.y, t) + Rng.range_f(-STAT_VARIANCE, STAT_VARIANCE), 0.0, 100.0)
	job.botched = roll.critical_failure
	job.potion_count = 2 if roll.critical_success else 1
	job.status = BrewJob.Status.BREWING

	station.current_job = job
	brew_started.emit(station.id, recipe.id)
	brew_roll_resolved.emit(station.id, recipe.id, roll)
	return ""


func collect(station_id: String) -> bool:
	var station := get_station(station_id)
	if station == null or station.current_job == null:
		return false
	if station.current_job.status != BrewJob.Status.READY:
		return false

	var job := station.current_job
	station.current_job = null

	if job.botched:
		Resolve.spend(BOTCH_RESOLVE_COST, "botched brew: %s" % job.recipe.display_name)
		brew_botched.emit(station.id, job.recipe.id)
		return true

	for i in job.potion_count:
		Inventory.add_potion(job.recipe.output_potion_id, job.rolled_potency, job.rolled_ease)
	Skills.add_xp("brewing", XP_PER_BREW)
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
				"botched": job.botched,
				"potion_count": job.potion_count,
			}
		station_data.append({
			"id": station.id,
			"display_name": station.display_name,
			"station_type": station.station_type,
			"potency_modifier": station.potency_modifier,
			"ease_modifier": station.ease_modifier,
			"speed_modifier": station.speed_modifier,
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

		var job_data = entry.get("current_job")
		if job_data != null:
			var job := BrewJob.new()
			job.recipe = ContentRegistry.get_recipe(job_data.get("recipe_id", ""))
			job.start_timestamp = job_data.get("start_timestamp", 0)
			job.ready_timestamp = job_data.get("ready_timestamp", 0)
			job.rolled_potency = job_data.get("rolled_potency", 0.0)
			job.rolled_ease = job_data.get("rolled_ease", 0.0)
			job.status = job_data.get("status", BrewJob.Status.BREWING) as BrewJob.Status
			job.botched = job_data.get("botched", false)
			job.potion_count = job_data.get("potion_count", 1)
			station.current_job = job

		stations.append(station)
