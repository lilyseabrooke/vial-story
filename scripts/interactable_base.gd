class_name InteractableBase
extends Area2D
## Shared proximity-interaction zone. See docs/design/systems.md, system 12.
##
## One base scene/script per behavior (BrewStationInteractable,
## StockBoxInteractable, GrowPlotInteractable, SupplyShelfInteractable,
## BedInteractable, ClassDoorInteractable, StairsInteractable) rather than one
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
@onready var _label: Label = $Label


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_visual.color = visual_color
	_label.text = display_name


func set_status_text(text: String) -> void:
	_label.text = text


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
