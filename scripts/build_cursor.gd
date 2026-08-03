class_name BuildCursor
extends Node2D
## Build mode's in-world cell highlight. Not an InteractableBase -- no
## proximity signals needed, it's driven entirely by BuildModeController's
## direct calls (set_cell_size()/set_icon()/snap to a world position). See
## docs/design/systems.md, system 4 (Build Mode).

@onready var _rect: ColorRect = $Rect
@onready var _icon: Sprite2D = $Icon


func set_cell_size(size: Vector2) -> void:
	_rect.size = size
	_rect.position = -size * 0.5


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
