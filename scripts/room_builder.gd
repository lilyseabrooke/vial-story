class_name RoomBuilder
extends Node2D
## Owns exploration-layer geometry: rooms, the shared player/camera, and the
## Interactables scattered through them. See docs/design/systems.md, system
## 12 — a couple of small interiors connected by stairs, not open-world.
## Rooms are hand-authored scenes under scenes/rooms/ (Room-scripted Node2D
## with Floor/Walls TileMapLayers, a SpawnPoint marker, and pre-placed
## Interactables); this script loads them, wires their signals, and
## (de)activates them, plus code-instances the one thing that can't be
## authored up front — runtime grow-plot Interactables. The camera is a
## child of the player (see build_rooms()) so it follows automatically;
## switch_room() clamps it to each room's Room.room_size.

signal player_entered_interactable(interactable: InteractableBase)
signal player_exited_interactable(interactable: InteractableBase)

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const SHOP_SCENE := preload("res://scenes/rooms/Shop.tscn")
const BEDROOM_SCENE := preload("res://scenes/rooms/Bedroom.tscn")
const GROW_PLOT_SCENE := preload("res://scenes/interactables/GrowPlotInteractable.tscn")

const SHOP_ROOM_ID := "shop"
const BEDROOM_ROOM_ID := "bedroom"

var player: CharacterBody2D
var current_room_id: String = ""

var _camera: Camera2D
var _rooms: Dictionary = {}             # room_id -> Room
var _spawn_points: Dictionary = {}      # room_id -> Vector2
var _plot_nodes: Dictionary = {}        # plot_id -> GrowPlotInteractable
var _station_nodes: Dictionary = {}     # station_id -> BrewStationInteractable
var _contract_nodes: Dictionary = {}    # book_id -> ContractBookInteractable


## Loads every room scene, wires their pre-placed Interactables, plus the
## shared camera and player, then activates the starting room.
func build_rooms() -> void:
	_load_room(SHOP_SCENE)
	_load_room(BEDROOM_SCENE)

	# Added after the rooms so they draw on top of each room's floor — 2D draw
	# order follows tree order, and rooms are siblings of the player/camera.
	player = PLAYER_SCENE.instantiate()
	player.add_to_group("player")
	add_child(player)

	# Camera is a child of the player so it follows automatically; smoothing
	# is enabled for a soft follow rather than a rigid lock-on. Per-room
	# limits (set in switch_room) keep it from showing past the walls.
	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = true
	player.add_child(_camera)
	_camera.make_current()

	switch_room(SHOP_ROOM_ID, _spawn_points[SHOP_ROOM_ID])

	for i in Herbalism.plots.size():
		var plot: GrowPlotInstance = Herbalism.plots[i]
		add_grow_plot_interactable(plot.id, Vector2(350, 100 + i * 120))

	Herbalism.plot_added.connect(_on_plot_added)
	Herbalism.planted.connect(_on_planted)

	Brewing.brew_started.connect(func(station_id: String, _recipe_id: String) -> void: _sync_station_indicator(station_id))
	Brewing.brew_ready.connect(func(station_id: String, _recipe_id: String) -> void: _sync_station_indicator(station_id))
	Brewing.brew_collected.connect(func(station_id: String, _recipe_id: String, _potency: float, _ease_value: float) -> void: _sync_station_indicator(station_id))
	Brewing.brew_botched.connect(func(station_id: String, _recipe_id: String) -> void: _sync_station_indicator(station_id))
	Clock.minute_tick.connect(func(_timestamp: int) -> void:
		for station_id in _station_nodes:
			_sync_station_indicator(station_id)
	)
	for station_id in _station_nodes:
		_sync_station_indicator(station_id)

	Demonology.writ_started.connect(func(book_id: String) -> void: _sync_contract_indicator(book_id))
	Demonology.writ_progress.connect(func(book_id: String) -> void: _sync_contract_indicator(book_id))
	Demonology.writ_first_draft_done.connect(func(book_id: String, _quality: float) -> void: _sync_contract_indicator(book_id))
	Demonology.writ_revised.connect(func(book_id: String, _revisions: int, _quality: float) -> void: _sync_contract_indicator(book_id))
	Demonology.writ_paused.connect(func(book_id: String) -> void: _sync_contract_indicator(book_id))
	Demonology.writ_resumed.connect(func(book_id: String) -> void: _sync_contract_indicator(book_id))
	Demonology.writ_submitted.connect(func(book_id: String, _roll: Dictionary, _ingredients: Dictionary, _messages: Array) -> void: _sync_contract_indicator(book_id))
	for book_id in _contract_nodes:
		_sync_contract_indicator(book_id)


## Instantiates a room scene, registers its spawn marker, connects
## every pre-placed Interactable's signals, and resolves stairs' spawn
## positions from the target room's SpawnPoint (target room must already be
## loaded — build_rooms() loads both up front, so order doesn't matter here).
func _load_room(scene: PackedScene) -> void:
	var room: Room = scene.instantiate()
	add_child(room)
	room.visible = false
	room.process_mode = Node.PROCESS_MODE_DISABLED

	_rooms[room.room_id] = room
	_spawn_points[room.room_id] = room.get_node("SpawnPoint").position

	for interactable in room.get_node("Interactables").get_children():
		_wire_interactable(interactable)
		if interactable is StairsInteractable and _spawn_points.has(interactable.target_room):
			interactable.spawn_position = _spawn_points[interactable.target_room]


func _wire_interactable(interactable: InteractableBase) -> void:
	interactable.player_entered.connect(func(i: InteractableBase) -> void: player_entered_interactable.emit(i))
	interactable.player_exited.connect(func(i: InteractableBase) -> void: player_exited_interactable.emit(i))
	if interactable is BrewStationInteractable:
		_station_nodes[interactable.target_id] = interactable
	elif interactable is ContractBookInteractable:
		_contract_nodes[interactable.target_id] = interactable
		# Walking away always pauses the writ (design: movement pauses
		# progress); resuming is deliberately only done from interact()
		# (an E-press), not just from re-entering the proximity area.
		interactable.player_exited.connect(func(_i: InteractableBase) -> void: Demonology.pause_writ(interactable.target_id))


func add_grow_plot_interactable(plot_id: String, pos: Vector2) -> void:
	var interactable: GrowPlotInteractable = GROW_PLOT_SCENE.instantiate()
	interactable.target_id = plot_id
	interactable.prompt_text = "plant/harvest"
	interactable.display_name = plot_id
	interactable.visual_color = Color(0.3, 0.6, 0.3)
	interactable.position = pos
	_rooms[SHOP_ROOM_ID].get_node("Plots").add_child(interactable)
	_wire_interactable(interactable)
	_plot_nodes[plot_id] = interactable
	update_plot_label(plot_id)


func update_plot_label(plot_id: String) -> void:
	var interactable: GrowPlotInteractable = _plot_nodes.get(plot_id)
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
		var previous_room: Room = _rooms[current_room_id]
		previous_room.visible = false
		previous_room.process_mode = Node.PROCESS_MODE_DISABLED

	current_room_id = room_id
	var room: Room = _rooms[room_id]
	room.visible = true
	room.process_mode = Node.PROCESS_MODE_INHERIT

	player.position = spawn_position

	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(room.room_size.x)
	_camera.limit_bottom = int(room.room_size.y)
	_camera.reset_smoothing()  # snap instead of gliding in from the previous room

	SceneDirector.recheck()


## Drives a station Interactable's progress bar/ready popup from Brewing's
## current state -- called on every relevant Brewing signal plus every
## minute tick (to advance the fill) and once up front (to restore state on
## a loaded save with a brew already in progress).
func _sync_station_indicator(station_id: String) -> void:
	var node: BrewStationInteractable = _station_nodes.get(station_id)
	if node == null:
		return
	var station := Brewing.get_station(station_id)
	var job := station.current_job if station else null
	if job == null:
		node.clear_brew_indicator()
	elif job.status == BrewJob.Status.READY:
		node.show_brew_ready()
	else:
		var total := float(job.ready_timestamp - job.start_timestamp)
		var elapsed := float(Clock.get_timestamp() - job.start_timestamp)
		node.set_brew_progress(elapsed / total if total > 0.0 else 1.0)


## Drives a Contract Book Interactable's meter/diamonds from Demonology's
## current state -- called on every relevant Demonology signal. Unlike
## brewing's indicator, no Clock.minute_tick hook is needed here: progress
## only ever changes on an engaged minute tick, and Demonology.writ_progress
## already fires exactly then.
func _sync_contract_indicator(book_id: String) -> void:
	var node: ContractBookInteractable = _contract_nodes.get(book_id)
	if node == null:
		return
	var writ := Demonology.get_writ(book_id)
	if writ == null:
		node.clear_writ_indicator()
	else:
		node.set_writ_progress(writ.progress_fraction(), writ.revisions_completed)


func _on_plot_added(plot_id: String) -> void:
	var index := Herbalism.plots.size() - 1
	add_grow_plot_interactable(plot_id, Vector2(350, 100 + index * 120))


func _on_planted(plot_id: String, _seed_id: String) -> void:
	update_plot_label(plot_id)
