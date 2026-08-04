class_name BuildCursor
extends Node2D
## Build mode's in-world cell highlight. Not an InteractableBase -- no
## proximity signals needed, it's driven entirely by BuildModeController's
## direct calls (set_cell_size()/set_footprint()/set_icon()/snap to a world
## position). See docs/design/systems.md, system 4 (Build Mode).
##
## Highlights are drawn per grid cell rather than as one rect over the whole
## footprint, so a carried component can show *which* cells under it are the
## problem (see set_footprint()). Drawn by this node itself instead of child
## ColorRects: the cell count changes with whatever's being carried, and
## _draw() re-renders a whole new footprint without any node churn.

const FREE_COLOR := Color(0.95, 0.85, 0.2, 0.4)
## Cells that would refuse the carried component -- occupied or off the grid.
const BLOCKED_COLOR := Color(0.9, 0.24, 0.2, 0.5)

@onready var _icon: Sprite2D = $Icon

var _cell_size := Vector2(64, 64)
var _footprint := Vector2i(1, 1)
## Footprint-relative offsets (not absolute grid cells) of the blocked cells.
var _blocked: Array[Vector2i] = []


func set_cell_size(size: Vector2) -> void:
	_cell_size = size
	queue_redraw()


## `blocked_offsets` are relative to the footprint's own top-left cell, so the
## cursor needs no knowledge of where it sits on the grid. Empty (the default,
## and always the case while carrying nothing) draws the whole footprint in
## FREE_COLOR.
func set_footprint(footprint: Vector2i, blocked_offsets: Array[Vector2i] = []) -> void:
	_footprint = footprint
	_blocked = blocked_offsets
	queue_redraw()


## Shows the carried component's real art on top of the highlighted squares,
## using the same ComponentDef.icon/icon_offset convention
## InteractableBase.use_texture() applies to the actual placed sprite -- the
## cursor's own origin is already centered on the footprint the same way
## RoomBuilder positions a placed node, so the offset lines up identically
## between this preview and the real thing. `texture == null` (nothing
## carried, or the def has no art yet) just hides it.
func set_icon(texture: Texture2D, offset: Vector2 = Vector2.ZERO) -> void:
	_icon.visible = texture != null
	_icon.texture = texture
	_icon.offset = offset


## This node's origin is centered on the footprint's bounding box (that's what
## PlacementZone.cell_to_world() hands back), so cell (0,0) of the footprint
## starts half a footprint up and to the left.
func _draw() -> void:
	var origin := -Vector2(_footprint) * _cell_size * 0.5
	for dx in _footprint.x:
		for dy in _footprint.y:
			var offset := Vector2i(dx, dy)
			var color := BLOCKED_COLOR if offset in _blocked else FREE_COLOR
			draw_rect(Rect2(origin + Vector2(offset) * _cell_size, _cell_size), color)
