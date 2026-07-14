extends Node
## Grow plots: planting, growth ticks, harvesting. Autoloaded as "Herbalism".
## See docs/design/systems.md, system 7.

signal plot_added(plot_id: String)
signal planted(plot_id: String, seed_id: String)
signal ready_to_harvest(plot_id: String, seed_id: String)
signal harvested(plot_id: String, ingredient_id: String, quantity: int)

const XP_PER_HARVEST := 15
const STARTING_PLOT_COUNT := 2

var plots: Array[GrowPlotInstance] = []


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)
	add_plots(STARTING_PLOT_COUNT)


func add_plots(count: int) -> void:
	for i in count:
		var plot := GrowPlotInstance.new()
		plot.id = "plot_%d" % (plots.size() + 1)
		plots.append(plot)
		plot_added.emit(plot.id)


func get_plot(plot_id: String) -> GrowPlotInstance:
	for plot in plots:
		if plot.id == plot_id:
			return plot
	return null


## Returns "" on success, or a short reason string on failure.
func plant(plot_id: String, seed_def: SeedDef) -> String:
	var plot := get_plot(plot_id)
	if plot == null:
		return "No such plot."
	if plot.status != GrowPlotInstance.Status.EMPTY:
		return "Plot is already in use."
	if not Inventory.consume_ingredient(seed_def.id, 1):
		return "No %s to plant." % seed_def.display_name

	var speed_modifier := 1.0 + Skills.get_bonus("grow_speed")
	var growth_minutes := seed_def.growth_minutes
	if speed_modifier > 0.0:
		growth_minutes = int(growth_minutes / speed_modifier)

	plot.planted_seed = seed_def
	plot.planted_timestamp = Clock.get_timestamp()
	plot.ready_timestamp = plot.planted_timestamp + growth_minutes
	plot.status = GrowPlotInstance.Status.GROWING
	planted.emit(plot.id, seed_def.id)
	return ""


func harvest(plot_id: String) -> bool:
	var plot := get_plot(plot_id)
	if plot == null or plot.status != GrowPlotInstance.Status.READY_TO_HARVEST:
		return false

	var seed_def := plot.planted_seed
	var yield_bonus := int(Skills.get_bonus("grow_yield"))
	var quantity := seed_def.base_yield + yield_bonus

	Inventory.add_ingredient(seed_def.yields_ingredient_id, quantity)
	Skills.add_xp("herbalism", XP_PER_HARVEST)

	plot.status = GrowPlotInstance.Status.EMPTY
	plot.planted_seed = null
	harvested.emit(plot.id, seed_def.yields_ingredient_id, quantity)
	return true


func _on_minute_tick(timestamp: int) -> void:
	for plot in plots:
		if plot.status == GrowPlotInstance.Status.GROWING and timestamp >= plot.ready_timestamp:
			plot.status = GrowPlotInstance.Status.READY_TO_HARVEST
			ready_to_harvest.emit(plot.id, plot.planted_seed.id)


func get_save_data() -> Dictionary:
	var plot_data: Array[Dictionary] = []
	for plot in plots:
		plot_data.append({
			"id": plot.id,
			"status": int(plot.status),
			"planted_seed_id": plot.planted_seed.id if plot.planted_seed != null else "",
			"planted_timestamp": plot.planted_timestamp,
			"ready_timestamp": plot.ready_timestamp,
		})
	return {"plots": plot_data}


## Rebuilds `plots` from scratch rather than patching add_plots()'s boot-time
## default — plot count is itself save data (upgrades can add plots).
func load_save_data(data: Dictionary) -> void:
	plots.clear()
	var plot_data: Array = data.get("plots", [])
	for entry in plot_data:
		var plot := GrowPlotInstance.new()
		plot.id = entry.get("id", "")
		plot.status = entry.get("status", GrowPlotInstance.Status.EMPTY) as GrowPlotInstance.Status
		var seed_id: String = entry.get("planted_seed_id", "")
		plot.planted_seed = ContentRegistry.get_seed(seed_id) if seed_id != "" else null
		plot.planted_timestamp = entry.get("planted_timestamp", 0)
		plot.ready_timestamp = entry.get("ready_timestamp", 0)
		plots.append(plot)
