class_name StairsInteractable
extends InteractableBase
## See docs/design/systems.md, system 12. Room transitions are just another
## interactable, configured with a target_room id and a spawn_position in the
## destination room.

@export var target_room: String = ""
@export var spawn_position: Vector2 = Vector2.ZERO


func interact(main: MainScene) -> void:
	main.switch_room(target_room, spawn_position)
