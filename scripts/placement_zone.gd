class_name PlacementZone
extends Node2D
## A rectangular grid region a room can contain, used by the generic
## placement system (see docs/design/systems.md, system 4). Purely geometric
## and zone-type-agnostic -- `zone_type` is just a string Placement/
## ComponentDef.zone_types filter against, so a future Shop room adds its own
## PlacementZone with a different zone_type without touching this script.
##
## _ready() idempotently registers with Placement the same way a hand-placed
## BrewStationInteractable used to register itself with Brewing.

@export var zone_id: String
@export var zone_type: String
@export var cols: int = 3
@export var rows: int = 2
@export var cell_size: Vector2 = Vector2(64, 64)

## Drawn only while build mode has this zone active -- invisible during
## ordinary play. Toggled by BuildModeController.
var show_grid: bool = false


func _ready() -> void:
	add_to_group("placement_zones")
	Placement.register_zone(zone_id, zone_type, cols, rows, cell_size, global_position)
	# Without this, the whole zone (and every component placed inside it) is
	# one atomic unit for the room's y-sorted "Interactables" container --
	# sorted only by the zone's own static origin, not by each placed
	# component's position. That let a placed component draw in front of the
	# player regardless of where she actually stood. Enabling y-sort here too
	# lets it propagate: each component now sorts against the player
	# dynamically, by its own position, same as any other Interactable.
	y_sort_enabled = true


## `footprint` centers the returned position over the footprint's full
## bounding box (anchored at `cell`) rather than just `cell` itself -- a 2x1
## footprint's center sits one full cell to the right of a 1x1's.
func cell_to_world(cell: Vector2i, footprint: Vector2i = Vector2i(1, 1)) -> Vector2:
	return global_position + cell_to_local(cell, footprint)


## Same as cell_to_world() but relative to this zone's own position -- what a
## component node spawned as this zone's direct child (RoomBuilder) should
## set as its local `position`.
func cell_to_local(cell: Vector2i, footprint: Vector2i = Vector2i(1, 1)) -> Vector2:
	return Vector2((cell.x + footprint.x / 2.0) * cell_size.x, (cell.y + footprint.y / 2.0) * cell_size.y)


func world_to_cell(world_pos: Vector2) -> Vector2i:
	var local := (world_pos - global_position)
	return Vector2i(int(floor(local.x / cell_size.x)), int(floor(local.y / cell_size.y)))


func set_grid_visible(visible_now: bool) -> void:
	show_grid = visible_now
	queue_redraw()


func _draw() -> void:
	if not show_grid:
		return
	var outline_color := Color(1.0, 1.0, 1.0, 0.35)
	for x in cols + 1:
		draw_line(Vector2(x * cell_size.x, 0.0), Vector2(x * cell_size.x, rows * cell_size.y), outline_color, 1.0)
	for y in rows + 1:
		draw_line(Vector2(0.0, y * cell_size.y), Vector2(cols * cell_size.x, y * cell_size.y), outline_color, 1.0)
