extends Node
## Brewing stations and active jobs. Autoloaded as "Brewing".
## See docs/design/systems.md, system 4.

signal brew_started(station_id: String, recipe_id: String)
signal brew_ready(station_id: String, recipe_id: String)
signal brew_collected(station_id: String, recipe_id: String, potency: float, ease_value: float)
signal brew_botched(station_id: String, recipe_id: String)

const XP_PER_BREW := 20
const BOTCH_CHANCE := 0.1
const BOTCH_RESOLVE_COST := 15

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
	job.rolled_potency = _roll_stat(recipe.potency_range, potency_modifier)
	job.rolled_ease = _roll_stat(recipe.ease_range, ease_modifier)
	job.botched = randf() < BOTCH_CHANCE
	job.status = BrewJob.Status.BREWING

	station.current_job = job
	brew_started.emit(station.id, recipe.id)
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

	Inventory.add_potion(job.recipe.output_potion_id, job.rolled_potency, job.rolled_ease)
	Skills.add_xp("brewing", XP_PER_BREW)
	brew_collected.emit(station.id, job.recipe.id, job.rolled_potency, job.rolled_ease)
	return true


func _roll_stat(stat_range: Vector2, modifier: float) -> float:
	var value := randf_range(stat_range.x, stat_range.y) + modifier
	return clampf(value, 0.0, 100.0)


func _on_minute_tick(timestamp: int) -> void:
	for station in stations:
		var job := station.current_job
		if job and job.status == BrewJob.Status.BREWING and timestamp >= job.ready_timestamp:
			job.status = BrewJob.Status.READY
			brew_ready.emit(station.id, job.recipe.id)
