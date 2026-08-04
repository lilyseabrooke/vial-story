extends Node
## Owns zone/component-instance spatial and ownership state for the generic
## grid-placement system. Autoloaded as "Placement". See docs/design/systems.md,
## system 4 (Placement System).
##
## Deliberately zone-type-agnostic: knows nothing about "alembic"/"pantry"/
## "accelerator" as concepts, only the generic ComponentDef/ComponentInstance
## shape (category/effect_target strings) -- built this way so a future Shop
## rework can reuse this autoload without touching it, per CLAUDE.md's
## engine-building philosophy. Existence of a ComponentInstance in
## `component_instances` *is* "purchased" -- there's no separate purchased
## bool, since an instance is only ever created by purchase_component() after
## its ComponentDef's cost has actually been spent. Brewing/Inventory own
## brewing-logic/ingredient-storage state for a given component id; this
## autoload only ever answers "does it exist, where is it, is it placed."

signal zone_registered(zone_id: String)
signal component_purchased(component_id: String, zone_id: String)
signal component_placed(component_id: String, zone_id: String, grid_position: Vector2i)
signal component_stored(component_id: String)

const ADJACENT_OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

var zones: Dictionary = {}   # zone_id -> {zone_type, cols, rows, cell_size, origin}
var component_instances: Array[ComponentInstance] = []

var _id_counters: Dictionary = {}   # category -> int


## Idempotent -- called by each PlacementZone as it's wired into the tree, same
## shape as Brewing.register_station()/Inventory.register_pantry(). If
## `zone_id` is already registered (e.g. a save was already loaded before rooms
## wired), its dimensions/origin are refreshed to match the current wiring.
func register_zone(zone_id: String, zone_type: String, cols: int, rows: int, cell_size: Vector2, origin: Vector2) -> void:
	zones[zone_id] = {
		"zone_type": zone_type,
		"cols": cols,
		"rows": rows,
		"cell_size": cell_size,
		"origin": origin,
	}
	zone_registered.emit(zone_id)


func get_zone(zone_id: String) -> Dictionary:
	return zones.get(zone_id, {})


func get_component(component_id: String) -> ComponentInstance:
	for instance in component_instances:
		if instance.id == component_id:
			return instance
	return null


func get_components_in_zone(zone_id: String) -> Array[ComponentInstance]:
	var result: Array[ComponentInstance] = []
	for instance in component_instances:
		if instance.zone_id == zone_id:
			result.append(instance)
	return result


## Owned-but-unplaced components whose home zone is `zone_id` -- what a Zone
## Console/build mode's storage list shows.
func storage_components_for_zone(zone_id: String) -> Array[ComponentInstance]:
	var result: Array[ComponentInstance] = []
	for instance in component_instances:
		if instance.zone_id == zone_id and not instance.placed:
			result.append(instance)
	return result


func get_component_at(zone_id: String, cell: Vector2i) -> ComponentInstance:
	for instance in component_instances:
		if instance.zone_id != zone_id or not instance.placed:
			continue
		if cell in cells_for(instance.grid_position, _footprint_for(instance)):
			return instance
	return null


## Every grid cell a footprint occupies, anchored at its top-left cell --
## e.g. a 2x1 footprint at (0,0) occupies (0,0) and (1,0).
func cells_for(grid_position: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in footprint.x:
		for dy in footprint.y:
			cells.append(grid_position + Vector2i(dx, dy))
	return cells


func _footprint_for(instance: ComponentInstance) -> Vector2i:
	var def := ContentRegistry.get_component_def(instance.def_id)
	return def.footprint if def != null else Vector2i(1, 1)


func _generate_id(category: String) -> String:
	var n: int = _id_counters.get(category, 0) + 1
	_id_counters[category] = n
	return "%s_%d" % [category, n]


## Checks then spends a ComponentDef's materials + ingredients cost as one
## atomic operation -- mirrors RecipeDef's has_ingredients_for()/
## consume_ingredients_for() idiom (check everything first, only spend once
## every requirement is confirmed available). Returns "" on success, or a
## short reason string on failure, same convention as Inventory.try_spend_materials().
func _has_and_spend_cost(def: ComponentDef) -> String:
	if Inventory.materials < def.materials_cost:
		return "Not enough Materials."
	for i in def.ingredient_ids.size():
		if Inventory.ingredient_count(def.ingredient_ids[i]) < def.ingredient_quantities[i]:
			var ingredient := ContentRegistry.get_ingredient(def.ingredient_ids[i])
			var label := ingredient.display_name if ingredient != null else def.ingredient_ids[i]
			return "Not enough %s." % label
	Inventory.spend_materials(def.materials_cost)
	for i in def.ingredient_ids.size():
		Inventory.consume_ingredient(def.ingredient_ids[i], def.ingredient_quantities[i])
	return ""


## Spends a ComponentDef's cost and creates a new unplaced ComponentInstance
## owned by the player, homed to `zone_id` (its future placement target and
## where its storage entry shows up). Returns {id, error} -- error == "" on
## success, id == "" on failure.
func purchase_component(zone_id: String, def_id: String) -> Dictionary:
	var def := ContentRegistry.get_component_def(def_id)
	if def == null:
		return {"id": "", "error": "No such component."}
	var spend_err := _has_and_spend_cost(def)
	if spend_err != "":
		return {"id": "", "error": spend_err}
	var instance := ComponentInstance.new()
	instance.id = _generate_id(def.category)
	instance.def_id = def_id
	instance.zone_id = zone_id
	instance.placed = false
	component_instances.append(instance)
	component_purchased.emit(instance.id, zone_id)
	return {"id": instance.id, "error": ""}


func _is_outside(zone: Dictionary, cell: Vector2i) -> bool:
	return cell.x < 0 or cell.y < 0 or cell.x >= int(zone.cols) or cell.y >= int(zone.rows)


## Every cell of `component_id`'s footprint (anchored at `cell`) that would
## stop it being placed there -- off the grid, or already taken by a *different*
## component. An empty result means the placement is legal, so this is the one
## authority on that question: place_component() refuses exactly when this is
## non-empty, and Build Mode's cursor tints exactly these cells red, which
## keeps the preview from drifting away from the rule it previews. Checks the
## whole footprint, not just `cell` itself -- a 2x1 Alembic placed at (0,0)
## needs (0,0) *and* (1,0) both in-bounds and empty.
func blocking_cells(component_id: String, zone_id: String, cell: Vector2i) -> Array[Vector2i]:
	var blocked: Array[Vector2i] = []
	var instance := get_component(component_id)
	var zone: Dictionary = zones.get(zone_id, {})
	if instance == null or zone.is_empty():
		return blocked
	for target_cell in cells_for(cell, _footprint_for(instance)):
		if _is_outside(zone, target_cell):
			blocked.append(target_cell)
			continue
		var occupant := get_component_at(zone_id, target_cell)
		if occupant != null and occupant.id != component_id:
			blocked.append(target_cell)
	return blocked


## Returns "" on success, or a short reason string on failure.
func place_component(component_id: String, zone_id: String, cell: Vector2i) -> String:
	var instance := get_component(component_id)
	if instance == null:
		return "No such component."
	var zone: Dictionary = zones.get(zone_id, {})
	if zone.is_empty():
		return "No such zone."
	var blocked := blocking_cells(component_id, zone_id, cell)
	if not blocked.is_empty():
		return "Out of bounds." if _is_outside(zone, blocked[0]) else "Cell is occupied."
	instance.zone_id = zone_id
	instance.grid_position = cell
	instance.placed = true
	component_placed.emit(component_id, zone_id, cell)
	return ""


## Removes a placed component from the grid back into storage -- also how a
## component is picked up to be rearranged (BuildModeController remembers it
## as "held" locally; the underlying call is identical either way). No refund,
## same "respec, not return" precedent as Brewing.remove_alembic_upgrade().
func store_component(component_id: String) -> void:
	var instance := get_component(component_id)
	if instance == null:
		return
	instance.placed = false
	instance.grid_position = Vector2i(-1, -1)
	component_stored.emit(component_id)


## Sums effect_amount across every orthogonally-adjacent placed component in
## the same zone whose def's effect_target matches -- generic adjacency logic
## with zero knowledge of "alembic"/"accelerator." Bonuses stack additively:
## a component adjacent to N matching neighbors gets N times the bonus.
## Queried live (never cached), so rearranging reflects instantly. Multi-cell
## footprints check every occupied cell's neighbors, deduping by neighbor id
## so a neighbor touching the footprint from two sides isn't double-counted.
func adjacency_bonus(component_id: String, effect_target: String) -> float:
	var instance := get_component(component_id)
	if instance == null or not instance.placed:
		return 0.0
	var own_cells := cells_for(instance.grid_position, _footprint_for(instance))
	var counted_ids: Dictionary = {}
	var total := 0.0
	for cell in own_cells:
		for offset in ADJACENT_OFFSETS:
			var neighbor_cell := cell + offset
			if neighbor_cell in own_cells:
				continue
			var neighbor := get_component_at(instance.zone_id, neighbor_cell)
			if neighbor == null or neighbor.id == component_id or counted_ids.has(neighbor.id):
				continue
			var def := ContentRegistry.get_component_def(neighbor.def_id)
			if def != null and def.effect_target == effect_target:
				total += def.effect_amount
				counted_ids[neighbor.id] = true
	return total


func get_save_data() -> Dictionary:
	var instance_data: Array[Dictionary] = []
	for instance in component_instances:
		instance_data.append({
			"id": instance.id,
			"def_id": instance.def_id,
			"zone_id": instance.zone_id,
			"grid_x": instance.grid_position.x,
			"grid_y": instance.grid_position.y,
			"placed": instance.placed,
		})
	return {"component_instances": instance_data, "id_counters": _id_counters.duplicate()}


## Rebuilds component_instances from scratch -- zones themselves are not saved
## data, they re-derive from each PlacementZone._ready() as rooms load.
func load_save_data(data: Dictionary) -> void:
	component_instances.clear()
	for entry in (data.get("component_instances", []) as Array):
		var instance := ComponentInstance.new()
		instance.id = entry.get("id", "")
		instance.def_id = entry.get("def_id", "")
		instance.zone_id = entry.get("zone_id", "")
		instance.grid_position = Vector2i(entry.get("grid_x", -1), entry.get("grid_y", -1))
		instance.placed = entry.get("placed", false)
		component_instances.append(instance)
	_id_counters = (data.get("id_counters", {}) as Dictionary).duplicate()
