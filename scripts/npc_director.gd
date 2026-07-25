class_name NPCDirector
extends Node
## Owns the 5 love interests' live NPCInteractable nodes and moves them
## between rooms as NPCScheduler resolves their schedule. See
## docs/design/systems.md, system 13 ("NPC interaction").
##
## Not a scene -- code-instanced by RoomBuilder.build_rooms() the same way
## RoomBuilder itself is code-instanced by main.gd. Each NPC is spawned once,
## for the lifetime of the game, and reparented between rooms' Interactables
## containers on NPCScheduler.npc_room_changed rather than being
## destroyed/recreated -- player_entered/player_exited connections made once
## at spawn (via RoomBuilder.wire_interactable()) survive a reparent, so
## there's no need to re-wire on every room change.

const NPC_INTERACTABLE_SCENE := preload("res://scenes/interactables/NPCInteractable.tscn")

## Duplicated from NPCState.NPC_IDS -- same "each file hand-lists its own ids"
## precedent as Characters.CHARACTER_PATHS vs. NPCDialogue.NPC_LINE_PATHS,
## not an oversight.
const NPC_IDS := ["callie", "larissa", "haerin", "zara", "lyra"]

## Keeps the NPC's visual/collision box fully inside room_size. Movement
## speed/wait/arrive-distance constants live on NPCInteractable itself, next
## to the wander loop that uses them.
const MEANDER_MARGIN := 32.0

var room_builder: RoomBuilder

var _npc_nodes: Dictionary = {}   # npc_id -> NPCInteractable


func setup(builder: RoomBuilder) -> void:
	room_builder = builder
	NPCScheduler.resolve_all()
	for npc_id in NPC_IDS:
		_spawn_npc(npc_id, NPCScheduler.get_current_room(npc_id))
	NPCScheduler.npc_room_changed.connect(_on_npc_room_changed)


func _spawn_npc(npc_id: String, room_id: String) -> void:
	var room := room_builder.get_room(room_id)
	if room == null:
		push_warning("NPCDirector: no room '%s' to spawn npc_id '%s' into" % [room_id, npc_id])
		return

	var interactable: NPCInteractable = NPC_INTERACTABLE_SCENE.instantiate()
	interactable.npc_id = npc_id

	var character_def := Characters.get_character(npc_id)
	var display_name := character_def.display_name if character_def != null else npc_id
	interactable.display_name = display_name
	interactable.prompt_text = "talk to %s" % display_name
	if character_def != null:
		interactable.visual_color = character_def.placeholder_color

	var bounds := _meander_bounds(room)
	interactable.position = _random_point_in(bounds)

	room.get_node("Interactables").add_child(interactable)
	room_builder.wire_interactable(interactable)
	interactable.set_meander_bounds(bounds)

	_npc_nodes[npc_id] = interactable


func _on_npc_room_changed(npc_id: String, room_id: String) -> void:
	var interactable: NPCInteractable = _npc_nodes.get(npc_id)
	if interactable == null:
		return
	var room := room_builder.get_room(room_id)
	if room == null:
		push_warning("NPCDirector: no room '%s' to move npc_id '%s' into" % [room_id, npc_id])
		return

	var new_container := room.get_node("Interactables")
	var old_parent := interactable.get_parent()
	if old_parent == new_container:
		return
	if old_parent != null:
		old_parent.remove_child(interactable)
	new_container.add_child(interactable)

	var bounds := _meander_bounds(room)
	interactable.position = _random_point_in(bounds)
	interactable.set_meander_bounds(bounds)


func _meander_bounds(room: Room) -> Rect2:
	return Rect2(
		Vector2(MEANDER_MARGIN, MEANDER_MARGIN),
		room.room_size - Vector2(MEANDER_MARGIN, MEANDER_MARGIN) * 2.0
	)


func _random_point_in(bounds: Rect2) -> Vector2:
	return Vector2(
		Rng.range_f(bounds.position.x, bounds.end.x),
		Rng.range_f(bounds.position.y, bounds.end.y)
	)
