extends Node
## Grow plots: planting, growth ticks, harvesting. Also Water Pumps, the
## Garden Manager's second sellable item type -- boosts harvest yield for
## every Grow Plot sharing its manager. Autoloaded as "Herbalism". See
## docs/design/systems.md, system 7.

signal planted(plot_id: String, seed_id: String)
signal ready_to_harvest(plot_id: String, seed_id: String)
signal harvested(plot_id: String, ingredient_id: String, quantity: int)
signal plot_purchased(plot_id: String)
signal water_pump_purchased(pump_id: String)
signal water_pump_upgrade_purchased(pump_id: String, upgrade_id: String)
signal water_pump_upgrade_removed(pump_id: String, upgrade_id: String)

const XP_PER_HARVEST := 15
const WATER_PUMP_BASE_YIELD_BONUS := 0.20

var plots: Array[GrowPlotInstance] = []
var water_pumps: Array[WaterPumpInstance] = []


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)


func get_plot(plot_id: String) -> GrowPlotInstance:
	for plot in plots:
		if plot.id == plot_id:
			return plot
	return null


## Idempotent — called by RoomBuilder as each hand-placed GrowPlotInteractable
## is wired, so a plot exists as soon as its node loads regardless of whether
## it's purchased yet. If `id` is already registered (e.g. a save was already
## loaded before rooms wired), its *live* state (purchased/status/
## planted_seed/timestamps) is left untouched, but the scene-derived fields
## below are always refreshed to match the current wiring -- see
## Brewing.register_station()'s docstring for why (a plot saved before a
## field existed must not keep it empty forever).
func register_plot(id: String, display_name: String, cost: int, lab_manager_id: String) -> GrowPlotInstance:
	var existing := get_plot(id)
	if existing != null:
		existing.display_name = display_name
		existing.cost = cost
		existing.lab_manager_id = lab_manager_id
		return existing
	var plot := GrowPlotInstance.new()
	plot.id = id
	plot.display_name = display_name
	plot.cost = cost
	plot.purchased = cost <= 0
	plot.lab_manager_id = lab_manager_id
	plots.append(plot)
	return plot


## Returns "" on success, or a short reason string on failure -- same
## convention as Inventory.purchase_pantry()/Brewing.purchase_station().
func purchase_plot(plot_id: String) -> String:
	var plot := get_plot(plot_id)
	if plot == null:
		return "No such plot."
	if plot.purchased:
		return "Already purchased."
	if not Inventory.spend_materials(plot.cost):
		return "Not enough Materials."
	plot.purchased = true
	plot_purchased.emit(plot_id)
	return ""


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
	var quantity := int((seed_def.base_yield + yield_bonus) * _yield_multiplier(plot))

	Inventory.add_ingredient(seed_def.yields_ingredient_id, quantity)
	Skills.add_xp("herbalism", XP_PER_HARVEST)

	plot.status = GrowPlotInstance.Status.EMPTY
	plot.planted_seed = null
	harvested.emit(plot.id, seed_def.yields_ingredient_id, quantity)
	return true


func get_water_pump(pump_id: String) -> WaterPumpInstance:
	for pump in water_pumps:
		if pump.id == pump_id:
			return pump
	return null


## Idempotent — same refresh-scene-fields shape as register_plot()/
## Brewing.register_station().
func register_water_pump(id: String, display_name: String, cost: int, lab_manager_id: String) -> WaterPumpInstance:
	var existing := get_water_pump(id)
	if existing != null:
		existing.display_name = display_name
		existing.cost = cost
		existing.lab_manager_id = lab_manager_id
		return existing
	var pump := WaterPumpInstance.new()
	pump.id = id
	pump.display_name = display_name
	pump.cost = cost
	pump.purchased = cost <= 0
	pump.lab_manager_id = lab_manager_id
	water_pumps.append(pump)
	return pump


## Returns "" on success, or a short reason string on failure.
func purchase_water_pump(pump_id: String) -> String:
	var pump := get_water_pump(pump_id)
	if pump == null:
		return "No such pump."
	if pump.purchased:
		return "Already purchased."
	if not Inventory.spend_materials(pump.cost):
		return "Not enough Materials."
	pump.purchased = true
	water_pump_purchased.emit(pump_id)
	return ""


## Returns "" on success, or a short reason string on failure. No mutual
## exclusion — unlike Alembic upgrades, no Water Pump upgrade conflicts with
## another this pass.
func purchase_water_pump_upgrade(pump_id: String, upgrade_id: String) -> String:
	var pump := get_water_pump(pump_id)
	if pump == null:
		return "No such pump."
	if not pump.purchased:
		return "Water Pump hasn't been purchased yet."
	if upgrade_id in pump.upgrade_ids:
		return "Already purchased."
	var upgrade := ContentRegistry.get_water_pump_upgrade(upgrade_id)
	if upgrade == null:
		return "No such upgrade."
	if not Inventory.spend_materials(upgrade.cost):
		return "Not enough Materials."
	pump.upgrade_ids.append(upgrade_id)
	water_pump_upgrade_purchased.emit(pump_id, upgrade_id)
	return ""


## No refund — removing an upgrade is a respec, not a return.
func remove_water_pump_upgrade(pump_id: String, upgrade_id: String) -> void:
	var pump := get_water_pump(pump_id)
	if pump == null:
		return
	pump.upgrade_ids.erase(upgrade_id)
	water_pump_upgrade_removed.emit(pump_id, upgrade_id)


## Every purchased Water Pump sharing this plot's Garden Manager -- see
## docs/design/systems.md, system 7. A plot with no lab_manager_id (no linked
## manager) never has any.
func _linked_water_pumps(plot: GrowPlotInstance) -> Array[WaterPumpInstance]:
	var result: Array[WaterPumpInstance] = []
	if plot.lab_manager_id == "":
		return result
	for pump in water_pumps:
		if pump.purchased and pump.lab_manager_id == plot.lab_manager_id:
			result.append(pump)
	return result


## 1.0 (no bonus) plus WATER_PUMP_BASE_YIELD_BONUS per linked purchased pump,
## plus each such pump's owned upgrades' grow_yield_bonus effect.
func _yield_multiplier(plot: GrowPlotInstance) -> float:
	var multiplier := 1.0
	for pump in _linked_water_pumps(plot):
		multiplier += WATER_PUMP_BASE_YIELD_BONUS
		for upgrade_id in pump.upgrade_ids:
			var upgrade := ContentRegistry.get_water_pump_upgrade(upgrade_id)
			if upgrade != null:
				multiplier += upgrade.effects.get("grow_yield_bonus", 0.0)
	return multiplier


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
			"display_name": plot.display_name,
			"cost": plot.cost,
			"purchased": plot.purchased,
			"lab_manager_id": plot.lab_manager_id,
			"status": int(plot.status),
			"planted_seed_id": plot.planted_seed.id if plot.planted_seed != null else "",
			"planted_timestamp": plot.planted_timestamp,
			"ready_timestamp": plot.ready_timestamp,
		})
	var water_pump_data: Array[Dictionary] = []
	for pump in water_pumps:
		water_pump_data.append({
			"id": pump.id,
			"display_name": pump.display_name,
			"cost": pump.cost,
			"purchased": pump.purchased,
			"lab_manager_id": pump.lab_manager_id,
			"upgrade_ids": pump.upgrade_ids.duplicate(),
		})
	return {"plots": plot_data, "water_pumps": water_pump_data}


## Rebuilds `plots`/`water_pumps` from scratch rather than patching onto
## whatever RoomBuilder's wiring created -- RoomBuilder always wires after
## SaveManager loads, and register_plot()/register_water_pump()'s idempotent
## refresh (see their docstrings) is what reconciles this restored state with
## the current scene.
func load_save_data(data: Dictionary) -> void:
	plots.clear()
	for entry in (data.get("plots", []) as Array):
		var plot := GrowPlotInstance.new()
		plot.id = entry.get("id", "")
		plot.display_name = entry.get("display_name", "")
		plot.cost = entry.get("cost", 0)
		plot.purchased = entry.get("purchased", true)
		plot.lab_manager_id = entry.get("lab_manager_id", "")
		plot.status = entry.get("status", GrowPlotInstance.Status.EMPTY) as GrowPlotInstance.Status
		var seed_id: String = entry.get("planted_seed_id", "")
		plot.planted_seed = ContentRegistry.get_seed(seed_id) if seed_id != "" else null
		plot.planted_timestamp = entry.get("planted_timestamp", 0)
		plot.ready_timestamp = entry.get("ready_timestamp", 0)
		plots.append(plot)

	water_pumps.clear()
	for entry in (data.get("water_pumps", []) as Array):
		var pump := WaterPumpInstance.new()
		pump.id = entry.get("id", "")
		pump.display_name = entry.get("display_name", "")
		pump.cost = entry.get("cost", 0)
		pump.purchased = entry.get("purchased", true)
		pump.lab_manager_id = entry.get("lab_manager_id", "")
		var upgrade_ids: Array[String] = []
		upgrade_ids.assign(entry.get("upgrade_ids", []))
		pump.upgrade_ids = upgrade_ids
		water_pumps.append(pump)
