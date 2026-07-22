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
## Fired instead of player_exited_interactable when an Interactable is
## destroyed out from under the player (currently only a resolved Dragon's
## Stash) rather than actually walked away from -- see _on_stash_resolved().
signal interactable_destroyed(interactable: InteractableBase)

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const SHOP_SCENE := preload("res://scenes/rooms/Shop.tscn")
const BEDROOM_SCENE := preload("res://scenes/rooms/Bedroom.tscn")
const DRAGONS_GROUND_SCENE := preload("res://scenes/rooms/DragonsGround.tscn")
const GROW_PLOT_SCENE := preload("res://scenes/interactables/GrowPlotInteractable.tscn")
const DRAGON_STASH_SCENE := preload("res://scenes/interactables/DragonStashInteractable.tscn")
const DRAGON_SCENE := preload("res://scenes/Dragon.tscn")

const SHOP_ROOM_ID := "shop"
const BEDROOM_ROOM_ID := "bedroom"
const DRAGONS_GROUND_ROOM_ID := "dragons_ground"

## Two ground stashes placed the same night shouldn't visually overlap --
## _random_ground_position() rejects a candidate this close to an already-
## placed ground stash and rerolls.
const GROUND_STASH_MIN_SEPARATION := 72.0

## How many dragons roam the Dragons' Ground at once -- rerolled fresh (not
## accumulated like the ground stashes) every morning, see _respawn_dragons().
const DRAGON_COUNT_MIN := 3
const DRAGON_COUNT_MAX := 5
const DRAGON_MIN_SEPARATION := 90.0

var player: CharacterBody2D
var current_room_id: String = ""

var _camera: Camera2D
var _rooms: Dictionary = {}             # room_id -> Room
var _spawn_points: Dictionary = {}      # room_id -> Vector2
var _plot_nodes: Dictionary = {}        # plot_id -> GrowPlotInteractable
var _station_nodes: Dictionary = {}     # station_id -> BrewStationInteractable
var _contract_nodes: Dictionary = {}    # book_id -> ContractBookInteractable
var _stash_nodes: Dictionary = {}       # stash_id -> DragonStashInteractable
var _dragon_nodes: Array[Dragon] = []


## Loads every room scene, wires their pre-placed Interactables, plus the
## shared camera and player, then activates the starting room.
func build_rooms() -> void:
	_load_room(SHOP_SCENE)
	_load_room(BEDROOM_SCENE)
	_load_room(DRAGONS_GROUND_SCENE)

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

	Draconology.stash_started.connect(func(stash_id: String) -> void: _sync_stash_indicator(stash_id))
	Draconology.stash_progress.connect(func(stash_id: String) -> void: _sync_stash_indicator(stash_id))
	Draconology.stash_cancelled.connect(func(stash_id: String) -> void: _sync_stash_indicator(stash_id))
	Draconology.stash_resolved.connect(_on_stash_resolved)
	# Dragon's Stashes on the Dragons' Ground are runtime-instanced, the same
	# "not hand-placed like Contract Book/Workbench" exception grow plots are
	# -- on a fresh game there's nothing to restore yet; on a loaded save,
	# Draconology already knows which ground stash ids are still uncollected,
	# so re-place all of them now the same way a fresh overnight spawn would.
	for stash_id in Draconology.get_ground_stash_ids():
		add_dragon_stash_interactable(stash_id, _random_ground_position(stash_id))
	Draconology.ground_stashes_spawned.connect(_on_ground_stashes_spawned)
	for stash_id in _stash_nodes:
		_sync_stash_indicator(stash_id)

	# Dragons are pure roaming hazards, not persisted state -- an initial
	# spawn now covers the very first visit, then a full clear-and-respawn
	# every morning (unlike the ground stashes, which accumulate toward a
	# cap instead of resetting) keeps the Dragons' Ground feeling different
	# night to night.
	_respawn_dragons()
	Clock.day_started.connect(func(_day_number: int, _day_type: int) -> void: _respawn_dragons())


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
	elif interactable is DragonStashInteractable:
		# A stash already collected on a prior save doesn't get re-registered
		# -- its hand-placed node is just discarded, so it stays gone across
		# a save/load the same as a live queue_free() would leave it.
		if Draconology.is_collected(interactable.target_id):
			interactable.queue_free()
		else:
			_stash_nodes[interactable.target_id] = interactable
			# Unlike the Contract Book's pause-on-exit, walking away from a
			# Dragon's Stash throws the whole dig away (design: punish
			# wandering off) -- Draconology.cancel_stash() erases the job
			# outright rather than freezing it for a later resume.
			interactable.player_exited.connect(func(_i: InteractableBase) -> void: Draconology.cancel_stash(interactable.target_id))


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


## Runtime-instances a Dragon's Stash on the Dragons' Ground, the same
## "code-instanced, not hand-placed" exception add_grow_plot_interactable()
## is for grow plots. _wire_interactable() already handles everything a
## DragonStashInteractable needs (registering it into _stash_nodes, wiring
## player_exited to Draconology.cancel_stash(), and the is_collected() reload
## guard), so this only has to build the node and place it.
func add_dragon_stash_interactable(stash_id: String, pos: Vector2) -> void:
	var interactable: DragonStashInteractable = DRAGON_STASH_SCENE.instantiate()
	interactable.target_id = stash_id
	interactable.prompt_text = "dig through the Dragon's Stash"
	interactable.display_name = "Dragon's Stash"
	interactable.visual_color = Color(0.5, 0.08, 0.2, 1)
	interactable.position = pos
	_rooms[DRAGONS_GROUND_ROOM_ID].get_node("GroundStashes").add_child(interactable)
	_wire_interactable(interactable)


## Picks a spawn point for a ground stash from the Dragons' Ground room's
## SpawnZones -- a designer-drawn set of Polygon2D shapes (edit their points
## directly in the 2D editor to reshape or add spawn areas, the same way a
## CollisionPolygon2D is authored) rather than a tileset terrain parameter,
## since a Polygon2D is both simpler to author by hand and lets a ground have
## multiple disjoint dig zones. The position is derived deterministically from
## stash_id (seeded RNG) rather than stored anywhere, so a stash lands in the
## same spot whether it was just spawned this session or is being re-placed
## after a save load -- same "position is derived, not persisted" shape
## add_grow_plot_interactable()'s index-based formula uses.
func _random_ground_position(stash_id: String) -> Vector2:
	var polygons: Array[Polygon2D] = []
	for zone in _rooms[DRAGONS_GROUND_ROOM_ID].get_node("SpawnZones").get_children():
		if zone is Polygon2D:
			polygons.append(zone)
	if polygons.is_empty():
		return Vector2.ZERO

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(stash_id)
	var fallback := polygons[0]
	for attempt in 64:
		var polygon: Polygon2D = polygons[rng.randi() % polygons.size()]
		var bounds := _polygon_bounds(polygon.polygon)
		var candidate_local := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		if not Geometry2D.is_point_in_polygon(candidate_local, polygon.polygon):
			continue
		var candidate_world := polygon.position + candidate_local
		if _far_enough_from_ground_stashes(candidate_world):
			return candidate_world

	# 64 rejection samples all missing (an unusually thin polygon, or the
	# ground is nearly full) -- fall back to the first zone's bounds center
	# rather than leaving the stash at the origin.
	return fallback.position + _polygon_bounds(fallback.polygon).get_center()


func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds


func _far_enough_from_ground_stashes(candidate: Vector2) -> bool:
	var container: Node = _rooms[DRAGONS_GROUND_ROOM_ID].get_node("GroundStashes")
	for node in _stash_nodes.values():
		if node.get_parent() == container and node.position.distance_to(candidate) < GROUND_STASH_MIN_SEPARATION:
			return false
	return true


func _on_ground_stashes_spawned(stash_ids: Array) -> void:
	for stash_id in stash_ids:
		add_dragon_stash_interactable(stash_id, _random_ground_position(stash_id))


## Clears every roaming dragon and scatters a fresh batch -- unlike the
## Dragon's Stashes (which persist/accumulate), dragons are pure ambient
## hazards with no state worth keeping across a night, so this is a hard
## reset rather than an incremental top-up.
func _respawn_dragons() -> void:
	for dragon in _dragon_nodes:
		dragon.queue_free()
	_dragon_nodes.clear()

	if ContentRegistry.dragons.is_empty():
		return

	var count := Rng.range_i(DRAGON_COUNT_MIN, DRAGON_COUNT_MAX)
	for i in count:
		var def := _pick_weighted_dragon_def()
		var pos := _random_dragon_position()
		var dragon: Dragon = DRAGON_SCENE.instantiate()
		_rooms[DRAGONS_GROUND_ROOM_ID].get_node("Dragons").add_child(dragon)
		dragon.setup(def, pos)
		_dragon_nodes.append(dragon)


## Weighted pick across ContentRegistry.dragons by DragonDef.spawn_weight --
## small/common dragons roll far more often than the extra-large/rare one.
func _pick_weighted_dragon_def() -> DragonDef:
	var defs := ContentRegistry.dragons
	var total_weight := 0.0
	for def in defs:
		total_weight += def.spawn_weight
	var roll := Rng.range_f(0.0, total_weight)
	var cumulative := 0.0
	for def in defs:
		cumulative += def.spawn_weight
		if roll <= cumulative:
			return def
	return defs[defs.size() - 1]


## Same rejection-sampling shape as _random_ground_position(), but positions
## are freshly rolled every call (not seeded by id) since dragons don't need
## to land in the same spot across a save/load the way a stash does.
func _random_dragon_position() -> Vector2:
	var polygons: Array[Polygon2D] = []
	for zone in _rooms[DRAGONS_GROUND_ROOM_ID].get_node("SpawnZones").get_children():
		if zone is Polygon2D:
			polygons.append(zone)
	if polygons.is_empty():
		return Vector2.ZERO

	var fallback := polygons[0]
	for attempt in 64:
		var polygon: Polygon2D = polygons[Rng.range_i(0, polygons.size() - 1)]
		var bounds := _polygon_bounds(polygon.polygon)
		var candidate_local := Vector2(
			Rng.range_f(bounds.position.x, bounds.end.x),
			Rng.range_f(bounds.position.y, bounds.end.y)
		)
		if not Geometry2D.is_point_in_polygon(candidate_local, polygon.polygon):
			continue
		var candidate_world := polygon.position + candidate_local
		if _far_enough_from_dragons(candidate_world):
			return candidate_world

	return fallback.position + _polygon_bounds(fallback.polygon).get_center()


func _far_enough_from_dragons(candidate: Vector2) -> bool:
	for dragon in _dragon_nodes:
		if dragon.global_position.distance_to(candidate) < DRAGON_MIN_SEPARATION:
			return false
	return true


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


## Drives a Dragon's Stash Interactable's progress bar from Draconology's
## current state -- called on stash_started/stash_progress/stash_cancelled.
## Unlike brewing's indicator, no Clock.minute_tick hook is needed here:
## progress only ever changes on an engaged minute tick (same reasoning as
## _sync_contract_indicator), and a cancel clears the job (and the bar) back
## to nothing rather than freezing it like a paused writ would.
func _sync_stash_indicator(stash_id: String) -> void:
	var node: DragonStashInteractable = _stash_nodes.get(stash_id)
	if node == null:
		return
	var job := Draconology.get_job(stash_id)
	if job == null:
		node.clear_stash_indicator()
	else:
		node.set_stash_progress(job.progress_fraction())


## A stash is single-use -- once Draconology resolves it, its Interactable
## node is gone for good, not just cleared like a brew station's indicator.
## The player is guaranteed to be standing right on top of it when this
## fires (that's the whole point of the tether), so freeing an Area2D still
## overlapping them triggers a body_exited cleanup signal from the physics
## server -- disconnect player_exited first so that doesn't forward through
## player_exited_interactable into main.gd's _on_player_exited_interactable()
## and close_menu() the dice-roll popup hud.gd just opened for this very
## resolution (that handler's close_menu() is meant for an actual walk-away,
## not "the interactable just got destroyed"). interactable_destroyed is the
## non-menu-closing equivalent main.gd needs to still clear its
## _current_interactable/prompt state.
func _on_stash_resolved(stash_id: String, _roll: Dictionary, _ingredients: Dictionary) -> void:
	var node: DragonStashInteractable = _stash_nodes.get(stash_id)
	if node == null:
		return
	_stash_nodes.erase(stash_id)
	for connection in node.player_exited.get_connections():
		node.player_exited.disconnect(connection.callable)
	interactable_destroyed.emit(node)
	node.queue_free()


func _on_plot_added(plot_id: String) -> void:
	var index := Herbalism.plots.size() - 1
	add_grow_plot_interactable(plot_id, Vector2(350, 100 + index * 120))


func _on_planted(plot_id: String, _seed_id: String) -> void:
	update_plot_label(plot_id)
