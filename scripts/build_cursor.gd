class_name BuildCursor
extends Node2D
## Build mode's in-world cell highlight. Not an InteractableBase -- no
## proximity signals needed, it's driven entirely by BuildModeController's
## direct calls (set_cell_size()/snap to a world position). See
## docs/design/systems.md, system 4 (Build Mode).

@onready var _rect: ColorRect = $Rect


func set_cell_size(size: Vector2) -> void:
	_rect.size = size
	_rect.position = -size * 0.5
