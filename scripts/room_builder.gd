class_name RoomBuilder
extends Node2D
## Owns exploration-layer geometry: rooms, the shared player/camera, and the
## Interactables scattered through them. See docs/design/systems.md, system
## 12 — a couple of small interiors connected by stairs, not open-world.
## Split out of main.gd once that file grew past just wiring; this is the
## "where things are in the world" half, HUD/menu presentation lives in
## GameHud instead.

signal player_entered_interactable(interactable: Interactable)
signal player_exited_interactable(interactable: Interactable)

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const INTERACTABLE_SCENE := preload("res://scenes/Interactable.tscn")

const SHOP_ROOM_ID := "shop"
const BEDROOM_ROOM_ID := "bedroom"
const SHOP_SPAWN := Vector2(400, 400)
const BEDROOM_SPAWN := Vector2(400, 350)

var player: CharacterBody2D
var current_room_id: String = ""

var _camera: Camera2D
var _rooms: Dictionary = {}             # room_id -> Node2D (room container)
var _room_camera_centers: Dictionary = {}  # room_id -> Vector2
var _plot_nodes: Dictionary = {}        # plot_id -> Interactable
var _station_id: String = ""


## Builds every room (floor + interactables) up front, plus the shared camera
## and player, then activates the starting room.
func build_rooms(station_id: String) -> void:
	_station_id = station_id
	_build_shop_room()
	_build_bedroom_room()

	# Added after the rooms so they draw on top of each room's floor — 2D draw
	# order follows tree order, and rooms are siblings of the player/camera.
	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()

	player = PLAYER_SCENE.instantiate()
	player.add_to_group("player")
	add_child(player)

	switch_room(SHOP_ROOM_ID, SHOP_SPAWN)

	Herbalism.plot_added.connect(_on_plot_added)
	Herbalism.planted.connect(_on_planted)


func _build_shop_room() -> void:
	var room := _add_room(SHOP_ROOM_ID, Vector2(50, 50), Vector2(700, 500))

	_add_interactable(
		room, Interactable.Type.BREW_STATION, _station_id, "open brewing options",
		"Alembic", Color(0.8, 0.4, 0.2), Vector2(200, 150)
	)
	_add_interactable(
		room, Interactable.Type.STOCK_BOX, "", "stock the shop",
		"Stock Box", Color(0.4, 0.7, 0.4), Vector2(600, 150)
	)
	_add_interactable(
		room, Interactable.Type.SUPPLY_SHELF, "", "buy supplies",
		"Supply Shelf", Color(0.6, 0.5, 0.3), Vector2(600, 300)
	)
	_add_interactable(
		room, Interactable.Type.CLASS_DOOR, "", "attend class (if in session)",
		"Classroom Door", Color(0.7, 0.7, 0.2), Vector2(650, 450)
	)
	_add_stairs(
		room, BEDROOM_ROOM_ID, BEDROOM_SPAWN, "go upstairs to the Bedroom",
		"Stairs Up", Vector2(200, 450)
	)

	for i in Herbalism.plots.size():
		var plot: GrowPlotInstance = Herbalism.plots[i]
		add_grow_plot_interactable(plot.id, Vector2(400, 150 + i * 120))


func _build_bedroom_room() -> void:
	var room := _add_room(BEDROOM_ROOM_ID, Vector2(50, 50), Vector2(700, 500))

	_add_interactable(
		room, Interactable.Type.BED, "", "sleep",
		"Bed", Color(0.3, 0.3, 0.7), Vector2(400, 200)
	)
	_add_stairs(
		room, SHOP_ROOM_ID, SHOP_SPAWN, "go downstairs to the Shop",
		"Stairs Down", Vector2(400, 450)
	)


## Creates a room container (floor + interactable holder), registers its
## camera center, and adds it to the scene tree, initially inactive.
func _add_room(room_id: String, floor_pos: Vector2, floor_size: Vector2) -> Node2D:
	var room := Node2D.new()
	room.name = room_id
	add_child(room)

	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.15, 0.15, 0.18)
	floor_rect.position = floor_pos
	floor_rect.size = floor_size
	room.add_child(floor_rect)

	_rooms[room_id] = room
	_room_camera_centers[room_id] = floor_pos + floor_size * 0.5
	room.visible = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	return room


func _add_interactable(
	parent: Node, type: Interactable.Type, target_id: String, prompt: String,
	display_name: String, color: Color, pos: Vector2
) -> Interactable:
	var interactable: Interactable = INTERACTABLE_SCENE.instantiate()
	interactable.interactable_type = type
	interactable.target_id = target_id
	interactable.prompt_text = prompt
	interactable.display_name = display_name
	interactable.visual_color = color
	interactable.position = pos
	parent.add_child(interactable)
	interactable.player_entered.connect(func(i: Interactable) -> void: player_entered_interactable.emit(i))
	interactable.player_exited.connect(func(i: Interactable) -> void: player_exited_interactable.emit(i))
	return interactable


func _add_stairs(
	parent: Node, target_room: String, spawn_position: Vector2, prompt: String,
	display_name: String, pos: Vector2
) -> Interactable:
	var interactable := _add_interactable(
		parent, Interactable.Type.STAIRS, "", prompt,
		display_name, Color(0.5, 0.5, 0.55), pos
	)
	interactable.target_room = target_room
	interactable.spawn_position = spawn_position
	return interactable


func add_grow_plot_interactable(plot_id: String, pos: Vector2) -> void:
	var interactable := _add_interactable(
		_rooms[SHOP_ROOM_ID], Interactable.Type.GROW_PLOT, plot_id, "plant/harvest",
		plot_id, Color(0.3, 0.6, 0.3), pos
	)
	_plot_nodes[plot_id] = interactable
	update_plot_label(plot_id)


func update_plot_label(plot_id: String) -> void:
	var interactable: Interactable = _plot_nodes.get(plot_id)
	if interactable == null:
		return
	var plot := Herbalism.get_plot(plot_id)
	var status_text := "empty"
	match plot.status:
		GrowPlotInstance.Status.GROWING:
			status_text = "growing %s" % plot.planted_seed.display_name
		GrowPlotInstance.Status.READY_TO_HARVEST:
			status_text = "ready to harvest (%s)" % plot.planted_seed.display_name
	interactable.set_status_text("%s\n%s" % [plot_id, status_text])


## The one place rooms get (de)activated: toggles visibility + processing on
## the room containers and moves the shared player/camera. Callers are
## responsible for resetting any interaction/menu state before calling this.
func switch_room(room_id: String, spawn_position: Vector2) -> void:
	if current_room_id != "":
		var previous_room: Node2D = _rooms[current_room_id]
		previous_room.visible = false
		previous_room.process_mode = Node.PROCESS_MODE_DISABLED

	current_room_id = room_id
	var room: Node2D = _rooms[room_id]
	room.visible = true
	room.process_mode = Node.PROCESS_MODE_INHERIT

	player.position = spawn_position
	_camera.position = _room_camera_centers[room_id]

	SceneDirector.recheck()


func _on_plot_added(plot_id: String) -> void:
	var index := Herbalism.plots.size() - 1
	add_grow_plot_interactable(plot_id, Vector2(400, 150 + index * 120))


func _on_planted(plot_id: String, _seed_id: String) -> void:
	update_plot_label(plot_id)
