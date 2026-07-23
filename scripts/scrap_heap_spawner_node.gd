class_name ScrapHeapSpawnerNode
extends Node2D
## Editor-placeable spawner for Scrap Heaps -- drop this node into any room
## scene, link `spawn_zone_path` to a Node2D whose Polygon2D children mark the
## diggable area (the inspector's "Assign..." button still gives a node
## picker), and set `max_heaps`/`avg_days_to_max`. Mirrors
## DragonStashSpawnerNode exactly, just against Transmutation instead of
## Draconology -- see that script's doc comment for the full reasoning.
##
## Like DragonStashSpawnerNode, this node does NOT instance
## ScrapHeapInteractable itself -- it only owns *where* and *how often*: it
## asks Transmutation to register itself as a population/rate source keyed by
## `spawner_id`, then emits spawn_requested with a computed id+position;
## RoomBuilder connects to that signal (see RoomBuilder._load_room()) and does
## the actual instancing/wiring, the same way it already handles every
## hand-placed Interactable.

signal spawn_requested(heap_id: String, world_position: Vector2)

## Must be unique across every ScrapHeapSpawnerNode in the game -- it's both
## Transmutation's bookkeeping key and the prefix for the heap ids this
## spawner hands out ("<spawner_id>_heap_<n>"), so two spawners sharing an id
## would silently merge their populations and id sequences.
@export var spawner_id: String = ""
## A plain NodePath (not a typed Node export) deliberately -- see the same
## note on DragonStashSpawnerNode.spawn_zone_path.
@export var spawn_zone_path: NodePath
@export var max_heaps: int = 6
## Average number of in-game days for this spawner's population to climb from
## empty to max_heaps -- see Transmutation._on_day_started() for how this
## becomes a nightly per-slot roll. The climb is asymptotic, so this is an
## approximate target, not a hard deadline.
@export var avg_days_to_max: float = 3.0
@export var min_separation: float = 72.0

## Positions already handed out this session, so a fresh spawn_requested()
## doesn't land on top of one already placed -- mirrors
## DragonStashSpawnerNode._occupied.
var _occupied: Array[Vector2] = []


func _ready() -> void:
	assert(spawner_id != "", "ScrapHeapSpawnerNode requires a unique spawner_id")
	Transmutation.ground_heaps_spawned.connect(_on_ground_heaps_spawned)
	# On a fresh game there's nothing to restore yet; on a loaded save,
	# Transmutation already knows which of this spawner's ids are still
	# uncollected, so re-request all of them now the same way a fresh
	# overnight spawn would.
	var existing_ids := Transmutation.register_heap_spawner(spawner_id, max_heaps, avg_days_to_max)
	for heap_id in existing_ids:
		if not Transmutation.is_heap_collected(heap_id):
			_request_spawn(heap_id)


func _on_ground_heaps_spawned(spawner: String, heap_ids: Array) -> void:
	if spawner != spawner_id:
		return
	for heap_id in heap_ids:
		_request_spawn(heap_id)


func _request_spawn(heap_id: String) -> void:
	var zone := get_node_or_null(spawn_zone_path) as Node2D
	var pos := SpawnZoneUtils.random_point(zone, min_separation, _occupied, hash(heap_id))
	_occupied.append(pos)
	spawn_requested.emit(heap_id, pos)
