class_name InteractableBase
extends Area2D
## Shared proximity-interaction zone. See docs/design/systems.md, system 12.
##
## One base scene/script per behavior (BrewStationInteractable,
## StockBoxInteractable, GrowPlotInteractable, SupplyShelfInteractable,
## BedInteractable, ClassDoorInteractable, TransferInteractable) rather than one
## generic node configured by an enum, since each type's action now lives on
## the node itself (interact()) instead of a type match in MainScene. This
## base only owns what every type shares: the Area2D proximity signals and
## the visual/label chrome.

signal player_entered(interactable: InteractableBase)
signal player_exited(interactable: InteractableBase)

## Physics layer 4 -- the same layer NPCInteractable/CustomerInteractable's
## own CollisionBody already blocks the player on (see Player.tscn's
## collision_mask = 10, i.e. layers 2+4), so making an interactable solid
## needs no change to the player's collision setup, just opting this layer in.
const SOLID_PHYSICS_LAYER := 8

@export var target_id: String = ""
@export var prompt_text: String = "interact"
@export var display_name: String = ""
@export var visual_color: Color = Color(0.6, 0.6, 0.6)

@onready var _visual: ColorRect = $Visual
@onready var _animated_visual: AnimatedSprite2D = $AnimatedVisual
@onready var _static_visual: Sprite2D = $StaticVisual
@onready var _shadow: Polygon2D = $Shadow
@onready var _label: Label = $Label
@onready var _solid_body: StaticBody2D = $SolidBody

var _using_sprite: bool = false
var _facing: String = "Down"


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_visual.color = visual_color
	_label.text = display_name


func set_status_text(text: String) -> void:
	_label.text = text


## Swaps the tinted placeholder ColorRect for an animated sprite. Called by
## subclasses (e.g. NPCInteractable) once they know their CharacterDef has
## sprite_frames set -- InteractableBase itself has no notion of a
## CharacterDef, so it can't decide this on its own in _ready(). Also hides
## the floating name Label, which only exists to label an otherwise-anonymous
## placeholder box -- a real sprite makes it redundant clutter. The ground
## shadow only makes sense under a real sprite (the placeholder ColorRect
## already reads as sitting on the ground), so it's gated the same way.
func use_sprite(frames: SpriteFrames) -> void:
	_using_sprite = true
	_visual.visible = false
	_label.visible = false
	_animated_visual.visible = true
	_animated_visual.sprite_frames = frames
	_animated_visual.play("Idle" + _facing)
	_shadow.visible = true


## Swaps the tinted placeholder ColorRect for a static (non-animated) object
## sprite -- e.g. a placed component's real art (ComponentDef.icon), applied
## by RoomBuilder._spawn_component_node() whenever a def has one set. Mirrors
## use_sprite()'s placeholder-hiding/shadow-showing behavior but through a
## plain Sprite2D instead of an AnimatedSprite2D, since world objects (unlike
## NPCs) have no Idle/Walking states to animate.
##
## `offset` (ComponentDef.icon_offset) shifts the sprite relative to this
## node's origin, which RoomBuilder positions at the center of the
## component's footprint -- not the center of the sprite. Art that reaches
## up beyond its footprint (e.g. the Alembic's apparatus rising off its
## tabletop) is taller than the footprint it occupies, so its own visual
## center doesn't line up with the footprint's center; `offset` lets a def
## nudge the sprite so the part that actually sits in the footprint (not the
## overhang) is what aligns with it.
func use_texture(texture: Texture2D, offset: Vector2 = Vector2.ZERO) -> void:
	_visual.visible = false
	_label.visible = false
	_static_visual.visible = true
	_static_visual.texture = texture
	_static_visual.offset = offset
	_shadow.visible = true


## Opt-in physical blocking -- most interactables (grow plots, supply
## shelves, etc.) are still walk-through placeholders, so this stays a no-op
## unless a subclass/ComponentDef explicitly asks for it (ComponentDef.solid).
## Reuses SolidBody's CollisionShape2D, which defaults to the same shape as
## the proximity Area2D's own CollisionShape2D -- a reasonable stand-in for
## the object's footprint -- but scenes that override the proximity shape
## (e.g. BrewStationInteractable) should override SolidBody's shape to match.
func set_solid(enabled: bool) -> void:
	_solid_body.collision_layer = SOLID_PHYSICS_LAYER if enabled else 0


## Tints the animated sprite -- used to tell instances that all share one
## placeholder SpriteFrames (e.g. CustomerBase.tres) apart, the same way
## visual_color already distinguishes untextured ColorRect placeholders.
## No-op has no meaning before use_sprite() since there's no sprite to tint,
## but harmless to call in either order.
func set_sprite_tint(color: Color) -> void:
	_animated_visual.modulate = color


## Picks the Idle/Walking + facing animation to match movement, mirroring
## player.gd's _update_animation. No-op when use_sprite() was never called,
## so callers don't need to guard every call site themselves.
func play_directional_animation(is_moving: bool, direction: Vector2) -> void:
	if not _using_sprite:
		return
	if direction != Vector2.ZERO:
		if absf(direction.x) > absf(direction.y):
			_facing = "Right" if direction.x > 0.0 else "Left"
		else:
			_facing = "Down" if direction.y > 0.0 else "Up"
	_animated_visual.play(("Walking" if is_moving else "Idle") + _facing)


## Overridden per subclass to perform this interactable's action when the
## player presses the interact key. `main` gives access to GameHud/RoomBuilder
## for the systems each type needs to call.
func interact(_main: MainScene) -> void:
	pass


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_entered.emit(self)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_exited.emit(self)
