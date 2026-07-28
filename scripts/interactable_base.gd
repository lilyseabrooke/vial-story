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

@export var target_id: String = ""
@export var prompt_text: String = "interact"
@export var display_name: String = ""
@export var visual_color: Color = Color(0.6, 0.6, 0.6)

@onready var _visual: ColorRect = $Visual
@onready var _animated_visual: AnimatedSprite2D = $AnimatedVisual
@onready var _shadow: Polygon2D = $Shadow
@onready var _label: Label = $Label

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
