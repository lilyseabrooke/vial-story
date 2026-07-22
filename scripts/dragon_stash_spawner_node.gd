class_name DragonStashSpawnerNode
extends Node2D
## Editor-placeable spawner for Dragon's Stashes -- drop this node into any
## room scene, link `spawn_zone_path` to a Node2D whose Polygon2D children
## mark the diggable area (the inspector's "Assign..." button still gives a
## node picker), and set `max_stashes`/`avg_days_to_max`. See docs/design/
## systems.md, system 19.
##
## Unlike DragonSpawnerNode, this node does NOT instance DragonStashInteractable
## itself -- stashes are Interactables with persisted collected-state and
## proximity wiring (HUD prompts, cancel-on-walk-away, indicator syncing),
## all of which RoomBuilder already owns for every other Interactable type.
## Duplicating that here would mean two places knowing how to wire an
## Interactable into the exploration layer. Instead this node only owns
## *where* and *how often* -- it asks Draconology to register itself as a
## population/rate source keyed by `spawner_id`, then emits spawn_requested
## with a computed id+position; RoomBuilder connects to that signal (see
## RoomBuilder._load_room()) and does the actual instancing/wiring, the same
## way it already handles every hand-placed Interactable.

signal spawn_requested(stash_id: String, world_position: Vector2)

## Must be unique across every DragonStashSpawnerNode in the game -- it's
## both Draconology's bookkeeping key and the prefix for the stash ids this
## spawner hands out ("<spawner_id>_stash_<n>"), so two spawners sharing an
## id would silently merge their populations and id sequences.
@export var spawner_id: String = ""
## A plain NodePath (not a typed Node export) deliberately -- see the same
## note on DragonSpawnerNode.spawn_zone_path: Godot's typed Node export
## picker only auto-resolves paths that stay inside this node's own
## instanced sub-scene, so a path reaching out to a sibling in the parent
## room scene silently resolves to null.
@export var spawn_zone_path: NodePath
@export var max_stashes: int = 6
## Average number of in-game days for this spawner's population to climb
## from empty to max_stashes -- see Draconology._on_day_started() for how
## this becomes a nightly per-slot roll. The climb is asymptotic (each
## night's chance shrinks as the population fills), so this is an
## approximate target, not a hard deadline.
@export var avg_days_to_max: float = 3.0
@export var min_separation: float = 72.0

## Positions already handed out this session, so a fresh spawn_requested()
## doesn't land on top of one already placed -- mirrors what a re-derived
## position would collide with, since RoomBuilder doesn't report positions
## back to this node once it hands them off.
var _occupied: Array[Vector2] = []


func _ready() -> void:
	assert(spawner_id != "", "DragonStashSpawnerNode requires a unique spawner_id")
	Draconology.ground_stashes_spawned.connect(_on_ground_stashes_spawned)
	# On a fresh game there's nothing to restore yet; on a loaded save,
	# Draconology already knows which of this spawner's ids are still
	# uncollected, so re-request all of them now the same way a fresh
	# overnight spawn would.
	var existing_ids := Draconology.register_spawner(spawner_id, max_stashes, avg_days_to_max)
	for stash_id in existing_ids:
		if not Draconology.is_collected(stash_id):
			_request_spawn(stash_id)


func _on_ground_stashes_spawned(spawner: String, stash_ids: Array) -> void:
	if spawner != spawner_id:
		return
	for stash_id in stash_ids:
		_request_spawn(stash_id)


func _request_spawn(stash_id: String) -> void:
	var zone := get_node_or_null(spawn_zone_path) as Node2D
	var pos := SpawnZoneUtils.random_point(zone, min_separation, _occupied, hash(stash_id))
	_occupied.append(pos)
	spawn_requested.emit(stash_id, pos)
