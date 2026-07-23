extends Node
## Breaking down Scrap into artificial ingredients at a Workbench, and
## digging raw Scrap out of a Scrap Heap. Autoloaded as "Transmutation". See
## docs/design/systems.md, the Transmutation / Workbench System section.
##
## Unlike Demonology's writs, breaking down Scrap has no multi-minute phase to
## wait through -- one interaction at the Workbench pops one piece of Scrap
## from Inventory and resolves it immediately. That part owns no persistent
## state of its own (the Scrap it consumes and the ingredients it grants both
## live in Inventory). The Scrap Heap dig below is different -- a
## player-tethered job shaped exactly like Draconology's Dragon's Stash, right
## down to "walking away cancels the whole dig" -- so it's the reason this
## autoload now has its own save data (_collected_heap_ids) and is part of
## SaveManager._SAVE_ORDER after all.

signal scrap_broken_down(roll: Dictionary, ingredients: Dictionary)

## Fired on Scrap Heap job state changes -- same shape as Draconology's
## stash_started/stash_progress/stash_cancelled/stash_resolved signals.
signal heap_started(heap_id: String)
signal heap_progress(heap_id: String)
signal heap_cancelled(heap_id: String)
signal heap_resolved(heap_id: String, roll: Dictionary, scrap_granted: int, ingredients: Dictionary)
## Fired after an overnight spawn roll adds one or more new heaps to a given
## spawner's population -- same shape as Draconology's ground_stashes_spawned.
## Each ScrapHeapSpawnerNode listens for its own spawner_id and hands the new
## ids to RoomBuilder to place.
signal ground_heaps_spawned(spawner_id: String, heap_ids: Array)

const ARTIFICIAL_INGREDIENT_IDS := ["scrap_alloy", "refined_component"]

const BREAKDOWN_DC := 11.0
const CRIT_QUALITY_SWING := 15.0

const BASE_INGREDIENT_COUNT := 1
const QUALITY_INGREDIENT_DIVISOR := 20.0

const XP_PER_BREAKDOWN := 15

## Scrap Heap tuning -- deliberately mirrors Draconology's Dragon's Stash
## consts (STASH_MINUTES, QUALITY_MIN/MAX, ROLL_DC, CRIT_QUALITY_SWING,
## BASE_INGREDIENT_COUNT, QUALITY_INGREDIENT_DIVISOR, XP_PER_STASH) under
## Heap-prefixed names so both jobs read as the same shape at a glance.
const HEAP_MINUTES := 5
const HEAP_QUALITY_MIN := 20.0
const HEAP_QUALITY_MAX := 120.0
const HEAP_ROLL_DC := 11.0
const HEAP_CRIT_QUALITY_SWING := 15.0
const HEAP_BASE_SCRAP_COUNT := 1
const HEAP_QUALITY_SCRAP_DIVISOR := 20.0
const XP_PER_HEAP := 20

## Flat chance a resolved heap also hands over one artificial ingredient
## directly, on top of its Scrap -- occasionally the heap turns up something
## already refined instead of raw material.
const HEAP_ARTIFICIAL_CHANCE := 0.2

var _heap_jobs: Dictionary = {}          # heap_id -> ScrapHeapJob, actively being dug only
var _collected_heap_ids: Dictionary = {} # heap_id -> true, forever

## One entry per ScrapHeapSpawnerNode that has called register_heap_spawner(),
## keyed by that node's spawner_id -- {"max": int, "avg_days_to_max": float}.
## Same "in-memory only, re-supplied on room load" shape as Draconology's
## _spawner_configs.
var _spawner_configs: Dictionary = {}

## Ids of heaps currently scattered per spawner, distinct from any hand-placed
## heap a room might define directly (e.g. the Shop's scrap_heap_1). Mirrors
## Draconology._spawner_stash_ids exactly.
var _spawner_heap_ids: Dictionary = {}   # spawner_id -> Array[String]
var _spawner_counters: Dictionary = {}   # spawner_id -> int, next id to hand out


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)
	Clock.day_started.connect(_on_day_started)


## Pops one piece of Scrap from Inventory (FIFO) and resolves it: a visible
## 2d10 Transmutation check (modifier = transmute_ease) shifts the popped
## piece's hidden quality by +/-CRIT_QUALITY_SWING on a crit, and the final
## quality drives how many artificial ingredients are granted -- same
## "quality drives yield" shape as Demonology.submit_writ(), just resolved in
## one call instead of across a writing/revising job. No-op (returns {}) if
## there's no Scrap to break down.
func break_down_scrap() -> Dictionary:
	var piece := Inventory.take_scrap()
	if piece.is_empty():
		return {}

	var modifier := Skills.get_bonus("transmute_ease")
	var roll := Rng.roll_2d10(modifier, BREAKDOWN_DC)

	var quality: float = piece.get("quality", 0.0)
	if roll.critical_success:
		quality += CRIT_QUALITY_SWING
	elif roll.critical_failure:
		quality -= CRIT_QUALITY_SWING
	quality = maxf(quality, 0.0)

	var ingredients := _grant_ingredients(quality)
	Skills.add_xp("transmutation", XP_PER_BREAKDOWN)

	scrap_broken_down.emit(roll, ingredients)
	return {"roll": roll, "ingredients": ingredients}


func _grant_ingredients(quality: float) -> Dictionary:
	var yield_bonus := Skills.get_bonus("transmute_yield")
	var count := int(BASE_INGREDIENT_COUNT + floor(quality / QUALITY_INGREDIENT_DIVISOR) + yield_bonus)
	count = maxi(count, 1)
	var granted: Dictionary = {}
	for i in count:
		var id: String = ARTIFICIAL_INGREDIENT_IDS[Rng.range_i(0, ARTIFICIAL_INGREDIENT_IDS.size() - 1)]
		Inventory.add_ingredient(id, 1)
		granted[id] = granted.get(id, 0) + 1
	return granted


# ---------------------------------------------------------------------------
# Scrap Heap
# ---------------------------------------------------------------------------

func get_heap_job(heap_id: String) -> ScrapHeapJob:
	return _heap_jobs.get(heap_id)


func is_heap_collected(heap_id: String) -> bool:
	return _collected_heap_ids.has(heap_id)


## Called once by each ScrapHeapSpawnerNode's _ready() to declare its
## population/rate tuning and get back whichever of its ids are already
## scattered (from a loaded save, or a prior room visit this session). Same
## shape as Draconology.register_spawner().
func register_heap_spawner(spawner_id: String, max_heaps: int, avg_days_to_max: float) -> Array[String]:
	_spawner_configs[spawner_id] = {"max": max_heaps, "avg_days_to_max": avg_days_to_max}
	if not _spawner_heap_ids.has(spawner_id):
		_spawner_heap_ids[spawner_id] = [] as Array[String]
	if not _spawner_counters.has(spawner_id):
		_spawner_counters[spawner_id] = 0
	return (_spawner_heap_ids[spawner_id] as Array[String]).duplicate()


## Same asymptotic per-slot nightly roll as Draconology._on_day_started() --
## see that method's doc comment for the full reasoning.
func _on_day_started(_day_number: int, _day_type: int) -> void:
	for spawner_id in _spawner_configs.keys():
		var config: Dictionary = _spawner_configs[spawner_id]
		var max_heaps: int = config["max"]
		var avg_days_to_max: float = config["avg_days_to_max"]
		var base_chance := 1.0 / maxf(avg_days_to_max, 0.01)
		var existing_ids: Array[String] = _spawner_heap_ids[spawner_id]

		var new_ids: Array[String] = []
		for i in max_heaps:
			var current_count := existing_ids.size() + new_ids.size()
			if current_count >= max_heaps:
				break
			var fullness := float(current_count) / float(max_heaps)
			if Rng.range_f(0.0, 1.0) < base_chance * (1.0 - fullness):
				_spawner_counters[spawner_id] += 1
				new_ids.append("%s_heap_%d" % [spawner_id, _spawner_counters[spawner_id]])
		if new_ids.is_empty():
			continue
		existing_ids.append_array(new_ids)
		ground_heaps_spawned.emit(spawner_id, new_ids)


## No-op if this heap already has a job running -- interact() only calls this
## when there's none, and a resolved heap never gets here again since its
## Interactable is gone by then. Same shape as Draconology.start_stash().
func start_heap(heap_id: String) -> void:
	if _heap_jobs.has(heap_id):
		return
	var job := ScrapHeapJob.new()
	job.heap_id = heap_id
	job.minutes_required = HEAP_MINUTES
	job.quality = Rng.range_f(HEAP_QUALITY_MIN, HEAP_QUALITY_MAX)
	_heap_jobs[heap_id] = job
	heap_started.emit(heap_id)


## Walking away (or the Escape menu, via Clock.is_paused halting every
## minute_tick along with it) throws the whole dig away rather than freezing
## it -- same "punish wandering off" reasoning as Draconology.cancel_stash().
## No-op if there's nothing to cancel.
func cancel_heap(heap_id: String) -> void:
	if not _heap_jobs.has(heap_id):
		return
	_heap_jobs.erase(heap_id)
	heap_cancelled.emit(heap_id)


func _on_minute_tick(_timestamp: int) -> void:
	for heap_id in _heap_jobs.keys():
		var job: ScrapHeapJob = _heap_jobs[heap_id]
		job.minutes_elapsed += 1
		if job.minutes_elapsed >= job.minutes_required:
			_resolve_heap(heap_id, job)
		else:
			heap_progress.emit(heap_id)


## Rolls a 2d10 Transmutation check (modifier = transmute_ease) against the
## job's hidden quality, shifts quality by +/-HEAP_CRIT_QUALITY_SWING on a
## crit -- same "crit only nudges quality" rule break_down_scrap()/
## Draconology._resolve() both use. Final quality drives how much Scrap is
## granted, plus a flat HEAP_ARTIFICIAL_CHANCE roll for one artificial
## ingredient directly, then erases the job. The heap itself is single-use;
## the Interactable node is destroyed by RoomBuilder in response to
## heap_resolved.
func _resolve_heap(heap_id: String, job: ScrapHeapJob) -> void:
	var modifier := Skills.get_bonus("transmute_ease")
	var roll := Rng.roll_2d10(modifier, HEAP_ROLL_DC)

	var final_quality := job.quality
	if roll.critical_success:
		final_quality += HEAP_CRIT_QUALITY_SWING
	elif roll.critical_failure:
		final_quality -= HEAP_CRIT_QUALITY_SWING
	final_quality = maxf(final_quality, 0.0)

	var yield_bonus := Skills.get_bonus("transmute_yield")
	var scrap_count := int(HEAP_BASE_SCRAP_COUNT + floor(final_quality / HEAP_QUALITY_SCRAP_DIVISOR) + yield_bonus)
	scrap_count = maxi(scrap_count, 1)
	for i in scrap_count:
		Inventory.add_scrap(final_quality)

	var ingredients: Dictionary = {}
	if Rng.range_f(0.0, 1.0) < HEAP_ARTIFICIAL_CHANCE:
		var id: String = ARTIFICIAL_INGREDIENT_IDS[Rng.range_i(0, ARTIFICIAL_INGREDIENT_IDS.size() - 1)]
		Inventory.add_ingredient(id, 1)
		ingredients[id] = 1

	_heap_jobs.erase(heap_id)
	_collected_heap_ids[heap_id] = true
	# Freeing the slot back up (rather than leaving it permanently occupied)
	# is what lets that spawner's next overnight spawn roll approach its cap
	# again instead of the population only ever draining -- same reasoning as
	# Draconology._resolve().
	for spawner_id in _spawner_heap_ids:
		var ids: Array[String] = _spawner_heap_ids[spawner_id]
		if ids.has(heap_id):
			ids.erase(heap_id)
			break
	Skills.add_xp("transmutation", XP_PER_HEAP)
	heap_resolved.emit(heap_id, roll, scrap_count, ingredients)


## Active jobs are deliberately not persisted -- the player is never standing
## at the heap at the instant a save loads, and there's no paused state to
## restore into, so a save/load is just treated as another walk-away. Only
## which heaps are permanently collected needs to survive -- same reasoning
## as Draconology.get_save_data().
func get_save_data() -> Dictionary:
	var ground_heap_ids := {}
	for spawner_id in _spawner_heap_ids:
		ground_heap_ids[spawner_id] = _spawner_heap_ids[spawner_id]
	return {
		"collected_heap_ids": _collected_heap_ids.keys(),
		"spawner_heap_ids": ground_heap_ids,
		"spawner_counters": _spawner_counters,
	}


## Deliberately does not touch _spawner_configs -- that's re-supplied by each
## ScrapHeapSpawnerNode's own register_heap_spawner() call once its room
## loads, same as Draconology.load_save_data().
func load_save_data(data: Dictionary) -> void:
	_heap_jobs.clear()
	_collected_heap_ids.clear()
	for heap_id in (data.get("collected_heap_ids", []) as Array):
		_collected_heap_ids[heap_id] = true

	_spawner_heap_ids.clear()
	var saved_ids: Dictionary = data.get("spawner_heap_ids", {})
	for spawner_id in saved_ids:
		var ids: Array[String] = []
		for heap_id in (saved_ids[spawner_id] as Array):
			ids.append(heap_id as String)
		_spawner_heap_ids[spawner_id] = ids

	_spawner_counters.clear()
	var saved_counters: Dictionary = data.get("spawner_counters", {})
	for spawner_id in saved_counters:
		_spawner_counters[spawner_id] = int(saved_counters[spawner_id])
