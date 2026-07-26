class_name TransferInteractable
extends InteractableBase
## See docs/design/systems.md, system 12. Room transitions are just another
## interactable, configured with a target_room id and a destination in that
## room -- either target_entry_point_id (an EntryPoint marker placed in that
## room, the recommended default since moving the marker updates every
## Transfer that targets it) or a fixed spawn_position for a one-off
## destination that doesn't warrant its own marker. Leaving both unset falls
## back to the target room's default SpawnPoint (see
## RoomBuilder._load_room()) -- the same thing a plain Stairs node always did
## before this generalized Stairs into Transfer.

@export var target_room: String = ""
@export var target_entry_point_id: String = ""
@export var spawn_position: Vector2 = Vector2.ZERO


func interact(main: MainScene) -> void:
	var spawn := spawn_position
	if target_entry_point_id != "":
		spawn = main.room_builder.get_entry_point_position(target_room, target_entry_point_id)
	main.switch_room(target_room, spawn)
