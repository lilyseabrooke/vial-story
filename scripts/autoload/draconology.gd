extends Node
## Gathering draconic ingredients from a Dragon's Stash. Autoloaded as
## "Draconology". See docs/design/systems.md, the Draconology / Dragon's
## Stash System section.
##
## Player-tethered like Demonology's writs (DragonStashInteractable's
## player_exited, wired in RoomBuilder._wire_interactable(), drives this) --
## but with no pause/resume: a writ keeps its accumulated progress when the
## player steps away, while a stash's whole job is erased by cancel_stash(),
## forcing a fresh start (and a freshly rolled hidden quality) next time. A
## job existing in _jobs at all means it's actively being dug -- there is no
## separate is_working flag to track, since RoomBuilder guarantees a job is
## cancelled the instant the player leaves. A stash is also single-use:
## _resolve() grants ingredients and marks the stash collected forever, and
## DragonStashInteractable/RoomBuilder destroy its node in response.

signal stash_started(stash_id: String)
signal stash_progress(stash_id: String)
signal stash_cancelled(stash_id: String)
signal stash_resolved(stash_id: String, roll: Dictionary, ingredients: Dictionary)
## Fired after an overnight spawn roll adds one or more new stashes to a
## given spawner's population. Each DragonStashSpawnerNode listens for its
## own spawner_id and hands the new ids to RoomBuilder to place -- Draconology
## only tracks ids/counts so it can reason about population limits without
## knowing anything about world geometry.
signal ground_stashes_spawned(spawner_id: String, stash_ids: Array)

const STASH_MINUTES := 5

## Each stash's hidden quality is rolled independently of the player's
## Draconology skill -- some stashes are just better than others -- the same
## "per-instance hidden quality" shape as Inventory.scrap's per-unit quality.
## Rerolled fresh on every start_stash(), including a restart after a cancel.
const QUALITY_MIN := 20.0
const QUALITY_MAX := 120.0

const ROLL_DC := 11.0
const CRIT_QUALITY_SWING := 15.0

const BASE_INGREDIENT_COUNT := 1
const QUALITY_INGREDIENT_DIVISOR := 20.0

const DRACONIC_INGREDIENT_IDS := ["dragon_scale", "ember_dust"]

const XP_PER_STASH := 20

var _jobs: Dictionary = {}   # stash_id -> DragonStashJob, actively being dug only

## One entry per DragonStashSpawnerNode that has called register_spawner(),
## keyed by that node's spawner_id -- {"max": int, "avg_days_to_max": float}.
## Config lives here only in memory (re-supplied by the spawner node's own
## exported values every time its room loads), not in save data.
var _spawner_configs: Dictionary = {}

## Ids of stashes currently scattered per spawner, distinct from any
## hand-placed stash a room might define directly. Spawner nodes mirror
## their own share of this into actual Interactable nodes via RoomBuilder;
## Draconology only tracks the ids so it can reason about each spawner's
## population limit without knowing anything about world geometry.
var _spawner_stash_ids: Dictionary = {}   # spawner_id -> Array[String]
var _spawner_counters: Dictionary = {}    # spawner_id -> int, next id to hand out

## DragonStashInteractable nodes are hand-placed in room scenes, not
## runtime-instanced like grow plots -- so unlike a BrewStation/ContractBook
## (permanent fixtures), a resolved stash needs to stay gone across a save/
## load, or the pre-placed node would just reappear next time its room loads.
## RoomBuilder checks this on wiring and queue_frees the node on sight instead
## of registering it.
var _collected_stash_ids: Dictionary = {}   # stash_id -> true


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)
	Clock.day_started.connect(_on_day_started)


func get_job(stash_id: String) -> DragonStashJob:
	return _jobs.get(stash_id)


func is_collected(stash_id: String) -> bool:
	return _collected_stash_ids.has(stash_id)


## Called once by each DragonStashSpawnerNode's _ready() to declare its
## population/rate tuning and get back whichever of its ids are already
## scattered (from a loaded save, or a prior room visit this session).
## Safe to call again with updated config (e.g. a scene reload) -- only the
## config dict is overwritten, the id list/counter are left alone.
func register_spawner(spawner_id: String, max_stashes: int, avg_days_to_max: float) -> Array[String]:
	_spawner_configs[spawner_id] = {"max": max_stashes, "avg_days_to_max": avg_days_to_max}
	if not _spawner_stash_ids.has(spawner_id):
		_spawner_stash_ids[spawner_id] = [] as Array[String]
	if not _spawner_counters.has(spawner_id):
		_spawner_counters[spawner_id] = 0
	return (_spawner_stash_ids[spawner_id] as Array[String]).duplicate()


## For each registered spawner, rolls one attempt per empty-or-filled slot
## up to its max_stashes, each attempt's odds shrinking as that spawner's
## population fills (linearly to 0 at its cap) -- so the count approaches
## max_stashes asymptotically across many nights, at a pace set by
## avg_days_to_max, rather than the ground going from empty to packed in one
## sleep. Emits ground_stashes_spawned once per spawner with every id rolled
## this night (possibly none), rather than once per id, so the spawner node
## only has to place them once.
func _on_day_started(_day_number: int, _day_type: int) -> void:
	for spawner_id in _spawner_configs.keys():
		var config: Dictionary = _spawner_configs[spawner_id]
		var max_stashes: int = config["max"]
		var avg_days_to_max: float = config["avg_days_to_max"]
		var base_chance := 1.0 / maxf(avg_days_to_max, 0.01)
		var existing_ids: Array[String] = _spawner_stash_ids[spawner_id]

		var new_ids: Array[String] = []
		for i in max_stashes:
			var current_count := existing_ids.size() + new_ids.size()
			if current_count >= max_stashes:
				break
			var fullness := float(current_count) / float(max_stashes)
			if Rng.range_f(0.0, 1.0) < base_chance * (1.0 - fullness):
				_spawner_counters[spawner_id] += 1
				new_ids.append("%s_stash_%d" % [spawner_id, _spawner_counters[spawner_id]])
		if new_ids.is_empty():
			continue
		existing_ids.append_array(new_ids)
		ground_stashes_spawned.emit(spawner_id, new_ids)


## No-op if this stash already has a job running -- interact() only calls
## this when there's none, and a resolved stash never gets here again since
## its Interactable is gone by then.
func start_stash(stash_id: String) -> void:
	if _jobs.has(stash_id):
		return
	var job := DragonStashJob.new()
	job.stash_id = stash_id
	job.minutes_required = STASH_MINUTES
	job.quality = Rng.range_f(QUALITY_MIN, QUALITY_MAX)
	_jobs[stash_id] = job
	stash_started.emit(stash_id)


## The player stepping away (or the Escape menu, via Clock.is_paused halting
## every minute_tick along with it) -- unlike Demonology.pause_writ(), this
## throws the whole job away rather than freezing it, so the next interact()
## starts over from zero with a freshly rolled quality. No-op if there's
## nothing to cancel.
func cancel_stash(stash_id: String) -> void:
	if not _jobs.has(stash_id):
		return
	_jobs.erase(stash_id)
	stash_cancelled.emit(stash_id)


func _on_minute_tick(_timestamp: int) -> void:
	for stash_id in _jobs.keys():
		var job: DragonStashJob = _jobs[stash_id]
		job.minutes_elapsed += 1
		if job.minutes_elapsed >= job.minutes_required:
			_resolve(stash_id, job)
		else:
			stash_progress.emit(stash_id)


## Rolls a 2d10 Draconology check (modifier = draconic_safety, a steady hand
## at the stash) against the job's hidden quality, shifts quality by
## +/-CRIT_QUALITY_SWING on a crit -- same "crit only nudges quality" rule
## Demonology/Transmutation use -- grants ingredients scaled to the result,
## then erases the job. The stash itself is single-use; the Interactable node
## is destroyed by RoomBuilder in response to stash_resolved.
func _resolve(stash_id: String, job: DragonStashJob) -> void:
	var modifier := Skills.get_bonus("draconic_safety")
	var roll := Rng.roll_2d10(modifier, ROLL_DC)

	var final_quality := job.quality
	if roll.critical_success:
		final_quality += CRIT_QUALITY_SWING
	elif roll.critical_failure:
		final_quality -= CRIT_QUALITY_SWING
	final_quality = maxf(final_quality, 0.0)

	var ingredients := _grant_ingredients(final_quality)
	_jobs.erase(stash_id)
	_collected_stash_ids[stash_id] = true
	# Freeing the slot back up (rather than leaving it permanently occupied)
	# is what lets that spawner's next overnight spawn roll approach its cap
	# again instead of the population only ever draining.
	for spawner_id in _spawner_stash_ids:
		var ids: Array[String] = _spawner_stash_ids[spawner_id]
		if ids.has(stash_id):
			ids.erase(stash_id)
			break
	Skills.add_xp("draconology", XP_PER_STASH)
	stash_resolved.emit(stash_id, roll, ingredients)


func _grant_ingredients(quality: float) -> Dictionary:
	var yield_bonus := Skills.get_bonus("draconic_yield")
	var count := int(BASE_INGREDIENT_COUNT + floor(quality / QUALITY_INGREDIENT_DIVISOR) + yield_bonus)
	count = maxi(count, 1)
	var granted: Dictionary = {}
	for i in count:
		var id: String = DRACONIC_INGREDIENT_IDS[Rng.range_i(0, DRACONIC_INGREDIENT_IDS.size() - 1)]
		Inventory.add_ingredient(id, 1)
		granted[id] = granted.get(id, 0) + 1
	return granted


## Active jobs are deliberately not persisted -- the player is never standing
## at the stash at the instant a save loads, and unlike a writ there's no
## paused state to restore into, so a save/load is just treated as another
## walk-away. Only which stashes are permanently collected needs to survive.
func get_save_data() -> Dictionary:
	var ground_stash_ids := {}
	for spawner_id in _spawner_stash_ids:
		ground_stash_ids[spawner_id] = _spawner_stash_ids[spawner_id]
	return {
		"collected_stash_ids": _collected_stash_ids.keys(),
		"spawner_stash_ids": ground_stash_ids,
		"spawner_counters": _spawner_counters,
	}


## Deliberately does not touch _spawner_configs -- that's re-supplied by each
## DragonStashSpawnerNode's own register_spawner() call once its room loads,
## same as every other exported-tunable-vs-persisted-state split in this
## codebase (e.g. Rng never reseeds on load).
func load_save_data(data: Dictionary) -> void:
	_jobs.clear()
	_collected_stash_ids.clear()
	for stash_id in (data.get("collected_stash_ids", []) as Array):
		_collected_stash_ids[stash_id] = true

	_spawner_stash_ids.clear()
	var saved_ids: Dictionary = data.get("spawner_stash_ids", {})
	for spawner_id in saved_ids:
		var ids: Array[String] = []
		for stash_id in (saved_ids[spawner_id] as Array):
			ids.append(stash_id as String)
		_spawner_stash_ids[spawner_id] = ids

	_spawner_counters.clear()
	var saved_counters: Dictionary = data.get("spawner_counters", {})
	for spawner_id in saved_counters:
		_spawner_counters[spawner_id] = int(saved_counters[spawner_id])
