class_name Interactable
extends Area2D
## Generic proximity-interaction zone. See docs/design/systems.md, system 12.
##
## One reusable scene configured per instance (type/target/prompt/color)
## rather than a subclass per interaction kind, since the actions themselves
## live in the systems already built (Brewing, Shop, Herbalism, Economy,
## Clock, Academy) — this is just the spatial trigger for them.

## CAUTION: the feature/tilemap-rooms branch stores this enum's values as raw
## ordinals inside scenes/rooms/Shop.tscn and Bedroom.tscn (Godot serializes
## @export enums as int, not name). Until that branch merges, only append new
## types at the end — inserting one in the middle silently repoints every
## pre-placed Interactable in those scenes to the wrong type, with no merge
## conflict to flag it. Safe to reorder/insert freely again once merged.
enum Type { BREW_STATION, STOCK_BOX, GROW_PLOT, SUPPLY_SHELF, BED, CLASS_DOOR, STAIRS }

signal player_entered(interactable: Interactable)
signal player_exited(interactable: Interactable)

@export var interactable_type: Type
@export var target_id: String = ""
@export var prompt_text: String = "interact"
@export var display_name: String = ""
@export var visual_color: Color = Color(0.6, 0.6, 0.6)

## STAIRS only: which room to switch to and where to place the player there.
@export var target_room: String = ""
@export var spawn_position: Vector2 = Vector2.ZERO

const BREW_EMPTY_COLOR := Color(0.85, 0.2, 0.2)
const BREW_FULL_COLOR := Color(0.3, 0.85, 0.35)

@onready var _visual: ColorRect = $Visual
@onready var _label: Label = $Label
@onready var _brew_progress_container: Panel = $BrewProgressContainer
@onready var _brew_progress: ProgressBar = $BrewProgressContainer/BrewProgress
@onready var _brew_ready_popup: Label = $BrewReadyPopup

## The fill StyleBoxFlat is shared from the scene by default -- duplicated
## per instance so recoloring one station's bar doesn't bleed into every
## other Interactable using this scene.
var _brew_fill_style: StyleBoxFlat


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_visual.color = visual_color
	_label.text = display_name

	_brew_fill_style = _brew_progress.get_theme_stylebox("fill").duplicate()
	_brew_progress.add_theme_stylebox_override("fill", _brew_fill_style)


func set_status_text(text: String) -> void:
	_label.text = text


## BREW_STATION-only indicator: a bottom-to-top fill while brewing, swapping
## to a "Ready!" popup once the job completes. Both default hidden so every
## other interactable type ignores them. The fill color lerps red -> green as
## it climbs, so the bar reads a bit like a potion vial topping off.
func set_brew_progress(fraction: float) -> void:
	_brew_ready_popup.visible = false
	_brew_progress_container.visible = true
	var f := clampf(fraction, 0.0, 1.0)
	_brew_progress.value = f
	_brew_fill_style.bg_color = BREW_EMPTY_COLOR.lerp(BREW_FULL_COLOR, f)


func show_brew_ready() -> void:
	_brew_progress_container.visible = false
	_brew_ready_popup.visible = true


func clear_brew_indicator() -> void:
	_brew_progress_container.visible = false
	_brew_ready_popup.visible = false


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_entered.emit(self)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_exited.emit(self)
