class_name Interactable
extends Area2D
## Generic proximity-interaction zone. See docs/design/systems.md, system 12.
##
## One reusable scene configured per instance (type/target/prompt/color)
## rather than a subclass per interaction kind, since the actions themselves
## live in the systems already built (Brewing, Shop, Herbalism, Economy,
## Clock, Academy) — this is just the spatial trigger for them.

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

@onready var _visual: ColorRect = $Visual
@onready var _label: Label = $Label


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_visual.color = visual_color
	_label.text = display_name


func set_status_text(text: String) -> void:
	_label.text = text


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_entered.emit(self)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_exited.emit(self)
