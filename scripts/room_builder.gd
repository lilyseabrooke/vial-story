class_name RoomBuilder
extends Node2D
## Owns exploration-layer geometry: rooms, the shared player/camera, and the
## Interactables scattered through them. See docs/design/systems.md, system
## 12 — a couple of small interiors connected by stairs, not open-world.
## Rooms are hand-authored scenes under scenes/rooms/ (Room-scripted Node2D
## with Floor/Walls TileMapLayers, a SpawnPoint marker, and pre-placed
## Interactables); this script loads them, wires their signals, and
## (de)activates them, plus code-instances the handful of Interactables that
## spawn dynamically at runtime (Dragon's Stashes, Scrap Heaps). Grow plots
## used to be one of those runtime-instanced exceptions but are now
## hand-placed like everything else — see _wire_interactable()'s
## GrowPlotInteractable/WaterPumpInteractable branches. The camera is a
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
const SCRAP_YARD_SCENE := preload("res://scenes/rooms/ScrapYard.tscn")
const GARDEN_SCENE := preload("res://scenes/rooms/Garden.tscn")
const COMMON_GARDEN_SCENE := preload("res://scenes/rooms/CommonGarden.tscn")
const ALTAR_SCENE := preload("res://scenes/rooms/Altar.tscn")
const LEY_LINE_OUTCROPPING_SCENE := preload("res://scenes/rooms/LeyLineOutcropping.tscn")
const ORRERY_SCENE := preload("res://scenes/rooms/Orrery.tscn")
const RAVEN_CANOPY_SCENE := preload("res://scenes/rooms/RavenCanopy.tscn")
const LEY_LINE_FISSURE_SCENE := preload("res://scenes/rooms/LeyLineFissure.tscn")
const CONFLUENCE_ZONE_SCENE := preload("res://scenes/rooms/ConfluenceZone.tscn")
const FORMER_RELIQUARY_SCENE := preload("res://scenes/rooms/FormerReliquary.tscn")
const UNDERBELLY_SCENE := preload("res://scenes/rooms/Underbelly.tscn")
const DRAGON_STASH_SCENE := preload("res://scenes/interactables/DragonStashInteractable.tscn")
const SCRAP_HEAP_SCENE := preload("res://scenes/interactables/ScrapHeapInteractable.tscn")

const SHOP_ROOM_ID := "shop"
const BEDROOM_ROOM_ID := "bedroom"
const DRAGONS_GROUND_ROOM_ID := "dragons_ground"
const SCRAP_YARD_ROOM_ID := "scrap_yard"
const GARDEN_ROOM_ID := "garden"
const COMMON_GARDEN_ROOM_ID := "common_garden"
const ALTAR_ROOM_ID := "altar"
const LEY_LINE_OUTCROPPING_ROOM_ID := "ley_line_outcropping"
const ORRERY_ROOM_ID := "orrery"

## Shop Back: one door in the Shop (StairsToShopBack) whose target_room is
## resolved at build time from PlayerProfile.shop_origin rather than fixed in
## the .tscn -- see _wire_shop_back_door(). Six scenes exist (one per
## ShopLocationDef) rather than one reskinned scene, matching every other
## room's "hand-authored scene per place" shape, and each is exclusive to its
## matching origin -- the same symmetry as the other five categories, where
## an always-reachable room (Altar/LeyLineOutcropping/Orrery/ScrapYard/
## DragonsGround) is distinct from its Shop-Back-only counterpart
## (RavenCanopy/LeyLineFissure/ConfluenceZone/FormerReliquary/Underbelly).
## Garden is the same shape: GARDEN_SCENE is the magic_garden-exclusive Shop
## Back room, and COMMON_GARDEN_SCENE (below) is the always-reachable
## counterpart every other origin uses instead. Unlike the other five pairs,
## both Garden rooms carry their own hand-placed Grow Plots (Herbalism no
## longer owns a shared plot pool) -- only CommonGarden has a Garden Manager/
## Water Pump so far, but a magic_garden playthrough still gets its own
## (unmanaged) plots in Garden.tscn.
const SHOP_BACK_ROOM_BY_ORIGIN := {
	"magic_garden": GARDEN_ROOM_ID,
	"raven_canopy": "raven_canopy",
	"former_reliquary": "former_reliquary",
	"ley_line_fissure": "ley_line_fissure",
	"underbelly": "underbelly",
	"confluence_zone": "confluence_zone",
}

var player: CharacterBody2D
var current_room_id: String = ""

var _camera: Camera2D
var _rooms: Dictionary = {}             # room_id -> Room
var _spawn_points: Dictionary = {}      # room_id -> Vector2
var _plot_nodes: Dictionary = {}        # plot_id -> GrowPlotInteractable
var _station_nodes: Dictionary = {}     # station_id -> BrewStationInteractable
var _contract_nodes: Dictionary = {}    # book_id -> ContractBookInteractable
var _stash_nodes: Dictionary = {}       # stash_id -> DragonStashInteractable
var _rift_nodes: Dictionary = {}        # rift_id -> PlanarRiftInteractable
var _heap_nodes: Dictionary = {}        # heap_id -> ScrapHeapInteractable
var _ley_line_nodes: Dictionary = {}    # node_id -> LeyLineNodeInteractable


## Loads every room scene, wires their pre-placed Interactables, plus the
## shared camera and player, then activates the starting room.
func build_rooms() -> void:
	_load_room(SHOP_SCENE)
	_load_room(BEDROOM_SCENE)
	_load_room(DRAGONS_GROUND_SCENE)
	_load_room(SCRAP_YARD_SCENE)
	_load_room(GARDEN_SCENE)
	_load_room(COMMON_GARDEN_SCENE)
	_load_room(ALTAR_SCENE)
	_load_room(LEY_LINE_OUTCROPPING_SCENE)
	_load_room(ORRERY_SCENE)
	_load_room(RAVEN_CANOPY_SCENE)
	_load_room(LEY_LINE_FISSURE_SCENE)
	_load_room(CONFLUENCE_ZONE_SCENE)
	_load_room(FORMER_RELIQUARY_SCENE)
	_load_room(UNDERBELLY_SCENE)
	_wire_shop_back_door()

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
	_camera.zoom = Vector2(2.0, 2.0) # >1 magnifies; halves the visible world area at 2x scale
	player.add_child(_camera)
	_camera.make_current()

	switch_room(SHOP_ROOM_ID, _spawn_points[SHOP_ROOM_ID])

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
	for stash_id in _stash_nodes:
		_sync_stash_indicator(stash_id)

	LeyLines.meditation_started.connect(func(node_id: String) -> void: _sync_ley_line_indicator(node_id))
	LeyLines.meditation_progress.connect(func(node_id: String) -> void: _sync_ley_line_indicator(node_id))
	LeyLines.meditation_cancelled.connect(func(node_id: String) -> void: _sync_ley_line_indicator(node_id))
	# Fired the instant a bar fills, strictly before LeyLines resets or erases
	# the job -- snaps the meter to a true 1.0 with no tween so the reset (or,
	# on a passed check, minigame_started below) has something real to animate
	# away from/replace instead of racing an in-flight tween. See
	# LeyLines.meditation_bar_full's own doc comment.
	LeyLines.meditation_bar_full.connect(func(node_id: String) -> void:
		var node: LeyLineNodeInteractable = _ley_line_nodes.get(node_id)
		if node != null:
			node.snap_meditation_full()
	)
	# A passed check erases the meditation job outright rather than cancelling
	# it, so meditation_cancelled never fires for this case -- without this,
	# the meter would stay stuck at the meditation_bar_full snap above for the
	# rest of the game. _sync_ley_line_indicator() sees get_meditation_job()
	# return null and hides it via clear_meditation_indicator(), same as any
	# other "job's gone" case.
	LeyLines.minigame_started.connect(func(node_id: String, _difficulty: float, _rounds: int) -> void: _sync_ley_line_indicator(node_id))
	for node_id in _ley_line_nodes:
		_sync_ley_line_indicator(node_id)

	Summoning.rift_started.connect(func(rift_id: String, _bundle_id: String) -> void: _sync_rift_indicator(rift_id))
	Summoning.rift_ready.connect(func(rift_id: String, _bundle_id: String) -> void: _sync_rift_indicator(rift_id))
	Summoning.rift_collected.connect(func(rift_id: String, _bundle_id: String, _ingredients: Dictionary, _material_delta: int, _resolve_delta: int, _quality: float) -> void: _sync_rift_indicator(rift_id))
	Clock.minute_tick.connect(func(_timestamp: int) -> void:
		for rift_id in _rift_nodes:
			_sync_rift_indicator(rift_id)
	)
	for rift_id in _rift_nodes:
		_sync_rift_indicator(rift_id)

	Transmutation.heap_started.connect(func(heap_id: String) -> void: _sync_heap_indicator(heap_id))
	Transmutation.heap_progress.connect(func(heap_id: String) -> void: _sync_heap_indicator(heap_id))
	Transmutation.heap_cancelled.connect(func(heap_id: String) -> void: _sync_heap_indicator(heap_id))
	Transmutation.heap_resolved.connect(_on_heap_resolved)
	for heap_id in _heap_nodes:
		_sync_heap_indicator(heap_id)


## Instantiates a room scene, registers its spawn marker, connects
## every pre-placed Interactable's signals, and resolves stairs' spawn
## positions from the target room's SpawnPoint (target room must already be
## loaded — build_rooms() loads both up front, so order doesn't matter here).
func _load_room(scene: PackedScene) -> void:
	var room: Room = scene.instantiate()

	# Connected before add_child(room) below, which is what actually triggers
	# _ready() (and therefore each spawner's initial spawn_requested burst,
	# e.g. re-placing a loaded save's uncollected stashes) for the whole
	# subtree -- connecting after add_child() would miss that initial burst.
	for spawner in room.get_children():
		if spawner is DragonStashSpawnerNode:
			spawner.spawn_requested.connect(_on_stash_spawn_requested.bind(spawner))
		elif spawner is ScrapHeapSpawnerNode:
			spawner.spawn_requested.connect(_on_heap_spawn_requested.bind(spawner))

	add_child(room)
	room.visible = false
	room.process_mode = Node.PROCESS_MODE_DISABLED

	_rooms[room.room_id] = room
	_spawn_points[room.room_id] = room.get_node("SpawnPoint").position

	for interactable in room.get_node("Interactables").get_children():
		_wire_interactable(interactable)
		if interactable is StairsInteractable and _spawn_points.has(interactable.target_room):
			interactable.spawn_position = _spawn_points[interactable.target_room]


## Resolves the Shop's StairsToShopBack door to whichever room matches the
## player's chosen origin (SHOP_BACK_ROOM_BY_ORIGIN), the same
## target_room/spawn_position pair a hand-authored stairs gets, just picked
## at runtime instead of baked into the .tscn. Falls back to the Garden if
## shop_origin is empty/unrecognized (e.g. a test scene run without going
## through character creation) rather than leaving the door pointed at
## whatever placeholder target_room the .tscn happens to have.
func _wire_shop_back_door() -> void:
	var target_room_id: String = SHOP_BACK_ROOM_BY_ORIGIN.get(PlayerProfile.shop_origin, GARDEN_ROOM_ID)
	var door: StairsInteractable = _rooms[SHOP_ROOM_ID].get_node("Interactables/StairsToShopBack")
	door.target_room = target_room_id
	door.spawn_position = _spawn_points[target_room_id]


func _wire_interactable(interactable: InteractableBase) -> void:
	interactable.player_entered.connect(func(i: InteractableBase) -> void: player_entered_interactable.emit(i))
	interactable.player_exited.connect(func(i: InteractableBase) -> void: player_exited_interactable.emit(i))
	if interactable is BrewStationInteractable:
		var lab_manager := interactable.get_node_or_null(interactable.lab_manager_path)
		var lab_manager_id: String = lab_manager.target_id if lab_manager != null else ""
		Brewing.register_station(interactable.target_id, interactable.display_name, "alembic", interactable.cost, lab_manager_id)
		_station_nodes[interactable.target_id] = interactable
	elif interactable is PantryInteractable:
		var pantry_manager := interactable.get_node_or_null(interactable.lab_manager_path)
		var pantry_manager_id: String = pantry_manager.target_id if pantry_manager != null else ""
		Inventory.register_pantry(interactable.target_id, interactable.display_name, interactable.cost, pantry_manager_id)
	elif interactable is GrowPlotInteractable:
		var plot_manager := interactable.get_node_or_null(interactable.lab_manager_path)
		var plot_manager_id: String = plot_manager.target_id if plot_manager != null else ""
		Herbalism.register_plot(interactable.target_id, interactable.display_name, interactable.cost, plot_manager_id)
		_plot_nodes[interactable.target_id] = interactable
		update_plot_label(interactable.target_id)
	elif interactable is WaterPumpInteractable:
		var pump_manager := interactable.get_node_or_null(interactable.lab_manager_path)
		var pump_manager_id: String = pump_manager.target_id if pump_manager != null else ""
		Herbalism.register_water_pump(interactable.target_id, interactable.display_name, interactable.cost, pump_manager_id)
	elif interactable is ContractBookInteractable:
		_contract_nodes[interactable.target_id] = interactable
		# Walking away always pauses the writ (design: movement pauses
		# progress); resuming is deliberately only done from interact()
		# (an E-press), not just from re-entering the proximity area.
		interactable.player_exited.connect(func(_i: InteractableBase) -> void: Demonology.pause_writ(interactable.target_id))
	elif interactable is PlanarRiftInteractable:
		_rift_nodes[interactable.target_id] = interactable
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
	elif interactable is ScrapHeapInteractable:
		# A heap already collected on a prior save doesn't get re-registered
		# -- its hand-placed node is just discarded, so it stays gone across
		# a save/load the same as a live queue_free() would leave it. Same
		# pattern as the DragonStashInteractable branch above.
		if Transmutation.is_heap_collected(interactable.target_id):
			interactable.queue_free()
		else:
			_heap_nodes[interactable.target_id] = interactable
			# Unlike the Contract Book's pause-on-exit, walking away from a
			# Scrap Heap throws the whole dig away (design: same as the
			# Dragon's Stash) -- Transmutation.cancel_heap() erases the job
			# outright rather than freezing it for a later resume.
			interactable.player_exited.connect(func(_i: InteractableBase) -> void: Transmutation.cancel_heap(interactable.target_id))
	elif interactable is LeyLineNodeInteractable:
		_ley_line_nodes[interactable.target_id] = interactable
		# A ley line node is never destroyed or single-use like a Dragon's
		# Stash/Scrap Heap -- only the tether is the same: walking away throws
		# the meditation job away outright (LeyLines.cancel_meditation()),
		# forcing a restart from an empty bar next time.
		interactable.player_exited.connect(func(_i: InteractableBase) -> void: LeyLines.cancel_meditation(interactable.target_id))


## Drives a Grow Plot Interactable's status label from Herbalism's current
## state -- called once at wiring time and on interact()/planted. An
## unpurchased plot shows as inert the same way an unpurchased Alembic does.
func update_plot_label(plot_id: String) -> void:
	var interactable: GrowPlotInteractable = _plot_nodes.get(plot_id)
	if interactable == null:
		return
	var plot := Herbalism.get_plot(plot_id)
	var status_text := "empty"
	if not plot.purchased:
		status_text = "not yet purchased"
	else:
		match plot.status:
			GrowPlotInstance.Status.GROWING:
				status_text = "growing %s" % plot.planted_seed.display_name
			GrowPlotInstance.Status.READY_TO_HARVEST:
				status_text = "ready to harvest (%s)" % plot.planted_seed.display_name
	interactable.set_status_text("%s\n%s" % [plot_id, status_text])


## Instances a Dragon's Stash Interactable in response to a
## DragonStashSpawnerNode's spawn_requested signal (connected in _load_room())
## and parents it under that same spawner node -- the spawner already knows
## where (spawn_zone) and how often (max_stashes/avg_days_to_max), so this is
## purely "build the node and wire it the same way every other Interactable
## is."
func _on_stash_spawn_requested(stash_id: String, pos: Vector2, spawner: DragonStashSpawnerNode) -> void:
	var interactable: DragonStashInteractable = DRAGON_STASH_SCENE.instantiate()
	interactable.target_id = stash_id
	interactable.prompt_text = "dig through the Dragon's Stash"
	interactable.display_name = "Dragon's Stash"
	interactable.visual_color = Color(0.5, 0.08, 0.2, 1)
	interactable.position = pos
	spawner.add_child(interactable)
	_wire_interactable(interactable)


## Instances a Scrap Heap Interactable in response to a ScrapHeapSpawnerNode's
## spawn_requested signal (connected in _load_room()) and parents it under
## that same spawner node -- same "code-instanced, not hand-placed" shape as
## _on_stash_spawn_requested().
func _on_heap_spawn_requested(heap_id: String, pos: Vector2, spawner: ScrapHeapSpawnerNode) -> void:
	var interactable: ScrapHeapInteractable = SCRAP_HEAP_SCENE.instantiate()
	interactable.target_id = heap_id
	interactable.prompt_text = "dig through the Scrap Heap"
	interactable.display_name = "Scrap Heap"
	interactable.visual_color = Color(0.72, 0.55, 0.22, 1)
	interactable.position = pos
	spawner.add_child(interactable)
	_wire_interactable(interactable)


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


## Drives a Planar Rift Interactable's progress bar/ready popup from
## Summoning's current state -- same shape as _sync_station_indicator since
## a rift job is a Clock.get_timestamp() deadline too, just possibly a much
## longer one.
func _sync_rift_indicator(rift_id: String) -> void:
	var node: PlanarRiftInteractable = _rift_nodes.get(rift_id)
	if node == null:
		return
	var job := Summoning.get_job(rift_id)
	if job == null:
		node.clear_rift_indicator()
	elif job.status == PlanarRiftJob.Status.READY:
		node.show_rift_ready()
	else:
		node.set_rift_progress(job.progress_fraction(Clock.get_timestamp()))


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


## Drives a Scrap Heap Interactable's progress bar from Transmutation's
## current state -- called on heap_started/heap_progress/heap_cancelled.
## Same "no Clock.minute_tick polling needed" shape as _sync_stash_indicator().
func _sync_heap_indicator(heap_id: String) -> void:
	var node: ScrapHeapInteractable = _heap_nodes.get(heap_id)
	if node == null:
		return
	var job := Transmutation.get_heap_job(heap_id)
	if job == null:
		node.clear_heap_indicator()
	else:
		node.set_heap_progress(job.progress_fraction())


## A heap is single-use -- once Transmutation resolves it, its Interactable
## node is gone for good, not just cleared like a brew station's indicator.
## Same "disconnect player_exited before queue_free" reasoning as
## _on_stash_resolved() -- the player is guaranteed to be standing right on
## top of it when this fires, so freeing an Area2D still overlapping them
## would otherwise forward a body_exited cleanup signal into main.gd's
## close_menu() logic meant for an actual walk-away.
func _on_heap_resolved(heap_id: String, _roll: Dictionary, _scrap_granted: int, _ingredients: Dictionary) -> void:
	var node: ScrapHeapInteractable = _heap_nodes.get(heap_id)
	if node == null:
		return
	_heap_nodes.erase(heap_id)
	for connection in node.player_exited.get_connections():
		node.player_exited.disconnect(connection.callable)
	interactable_destroyed.emit(node)
	node.queue_free()


func _on_planted(plot_id: String, _seed_id: String) -> void:
	update_plot_label(plot_id)


## Drives a Ley Line Node Interactable's meditation bar from LeyLines' current
## state -- called on meditation_started/meditation_progress/meditation_cancelled.
## Same "no Clock.minute_tick polling needed" shape as _sync_stash_indicator();
## unlike a stash the node itself is never destroyed, meditation_check_rolled
## resetting the bar back to 0 (see LeyLines._resolve_meditation()) shows up
## here too since it still fires meditation_progress right after.
func _sync_ley_line_indicator(node_id: String) -> void:
	var node: LeyLineNodeInteractable = _ley_line_nodes.get(node_id)
	if node == null:
		return
	var job := LeyLines.get_meditation_job(node_id)
	if job == null:
		node.clear_meditation_indicator()
	else:
		node.set_meditation_progress(job.progress_fraction())
