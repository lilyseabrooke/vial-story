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
## Fired after an overnight spawn roll adds one or more new stashes to the
## Dragons' Ground. RoomBuilder is the only listener -- it owns the actual
## Interactable geometry, so this just hands it the new ids to place.
signal ground_stashes_spawned(stash_ids: Array)

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

## The Dragons' Ground never fills up outright -- each night's spawn roll
## makes GROUND_SPAWN_ATTEMPTS_PER_NIGHT attempts, and each attempt's chance
## is GROUND_SPAWN_BASE_CHANCE scaled down by how full the ground already is
## (linearly to 0 at the limit), so the count approaches GROUND_STASH_LIMIT
## asymptotically across many nights rather than the ground going from empty
## to packed in one sleep.
const GROUND_STASH_LIMIT := 6
const GROUND_SPAWN_ATTEMPTS_PER_NIGHT := 4
const GROUND_SPAWN_BASE_CHANCE := 0.5

var _jobs: Dictionary = {}   # stash_id -> DragonStashJob, actively being dug only

## Ids of stashes currently scattered on the Dragons' Ground, distinct from
## any hand-placed stash a room might define directly. RoomBuilder mirrors
## this into actual Interactable nodes; Draconology only tracks the ids so it
## can reason about the population limit without knowing anything about
## world geometry.
var _ground_stash_ids: Array[String] = []
var _ground_stash_counter: int = 0

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


func get_ground_stash_ids() -> Array[String]:
	return _ground_stash_ids.duplicate()


## Rolls GROUND_SPAWN_ATTEMPTS_PER_NIGHT independent attempts to add a new
## stash to the Dragons' Ground, each attempt's odds shrinking as the ground
## fills up -- see the GROUND_STASH_LIMIT comment above. Emits
## ground_stashes_spawned once with every id rolled this night (possibly
## none), rather than once per id, so RoomBuilder only has to place them once.
func _on_day_started(_day_number: int, _day_type: int) -> void:
	var new_ids: Array[String] = []
	for i in GROUND_SPAWN_ATTEMPTS_PER_NIGHT:
		var current_count := _ground_stash_ids.size() + new_ids.size()
		if current_count >= GROUND_STASH_LIMIT:
			break
		var fullness := float(current_count) / float(GROUND_STASH_LIMIT)
		if Rng.range_f(0.0, 1.0) < GROUND_SPAWN_BASE_CHANCE * (1.0 - fullness):
			_ground_stash_counter += 1
			new_ids.append("ground_stash_%d" % _ground_stash_counter)
	if new_ids.is_empty():
		return
	_ground_stash_ids.append_array(new_ids)
	ground_stashes_spawned.emit(new_ids)


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
	# is what lets the ground's next overnight spawn roll approach the limit
	# again instead of the population only ever draining.
	_ground_stash_ids.erase(stash_id)
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
	return {
		"collected_stash_ids": _collected_stash_ids.keys(),
		"ground_stash_ids": _ground_stash_ids,
		"ground_stash_counter": _ground_stash_counter,
	}


func load_save_data(data: Dictionary) -> void:
	_jobs.clear()
	_collected_stash_ids.clear()
	for stash_id in (data.get("collected_stash_ids", []) as Array):
		_collected_stash_ids[stash_id] = true
	_ground_stash_ids.clear()
	for stash_id in (data.get("ground_stash_ids", []) as Array):
		_ground_stash_ids.append(stash_id as String)
	_ground_stash_counter = data.get("ground_stash_counter", 0)
