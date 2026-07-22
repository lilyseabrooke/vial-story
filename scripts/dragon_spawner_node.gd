class_name DragonSpawnerNode
extends Node2D
## Editor-placeable spawner for roaming Dragons -- drop this node into any
## room scene, link `spawn_zone` to a Node2D whose Polygon2D children mark
## the roaming area (the node picker restricts to nodes already in that
## scene), and populate `roster` with weighted DragonSpawnEntry entries
## (drag a DragonDef .tres onto each entry's `dragon` field from the
## FileSystem dock). See docs/design/systems.md, system 21.
##
## Fully self-contained, unlike DragonStashSpawnerNode: dragons are ambient
## hazards with no persisted state and aren't Interactables, so this node
## instances/frees its own Dragon children directly on Clock.day_started
## instead of asking RoomBuilder to own the lifecycle.

const DRAGON_SCENE := preload("res://scenes/Dragon.tscn")

## A plain NodePath (not a typed Node export) deliberately -- Godot's typed
## Node export picker only auto-resolves paths that stay inside this node's
## own instanced sub-scene, so a path reaching out to a sibling in the
## parent room scene (e.g. "../SpawnZones") silently resolves to null. A
## NodePath resolved via get_node() in script has no such restriction, and
## the inspector still gives a node-picker "Assign..." button for it.
@export var spawn_zone_path: NodePath
@export var roster: Array[DragonSpawnEntry] = []
## Rerolled fresh (not accumulated) every morning -- see _respawn().
@export var count_min: int = 3
@export var count_max: int = 5
@export var min_separation: float = 90.0

var _dragons: Array[Dragon] = []


func _ready() -> void:
	_respawn()
	Clock.day_started.connect(func(_day_number: int, _day_type: int) -> void: _respawn())


## Clears every roaming dragon this spawner owns and scatters a fresh batch --
## a hard reset rather than an incremental top-up, since dragons have no
## state worth keeping across a night.
func _respawn() -> void:
	for dragon in _dragons:
		dragon.queue_free()
	_dragons.clear()

	if roster.is_empty():
		return

	var zone := get_node_or_null(spawn_zone_path) as Node2D
	var occupied: Array[Vector2] = []
	var count := Rng.range_i(count_min, count_max)
	for i in count:
		var def := _pick_weighted_entry()
		if def == null:
			continue
		var pos := SpawnZoneUtils.random_point(zone, min_separation, occupied)
		occupied.append(pos)
		var dragon: Dragon = DRAGON_SCENE.instantiate()
		add_child(dragon)
		dragon.setup(def, pos)
		_dragons.append(dragon)


## Weighted pick across `roster` by each entry's local weight -- same
## cumulative-weight shape DragonDef.spawn_weight uses for global rarity.
func _pick_weighted_entry() -> DragonDef:
	var total_weight := 0.0
	for entry in roster:
		total_weight += entry.weight
	if total_weight <= 0.0:
		return null

	var roll := Rng.range_f(0.0, total_weight)
	var cumulative := 0.0
	for entry in roster:
		cumulative += entry.weight
		if roll <= cumulative:
			return entry.dragon
	return roster[roster.size() - 1].dragon
