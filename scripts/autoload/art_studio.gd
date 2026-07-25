extends Node
## Art Studio / Creativity: gathering inspiration, then working a chosen
## Inspiration to completion for skill XP, materials, reputation, or
## relationship rewards. Autoloaded as "ArtStudio". See
## docs/design/systems.md, the Art Studio / Creativity System section.
##
## Each studio's job moves through three phases (ArtStudioJob.Phase):
## ROLLING is a Clock timestamp deadline exactly like BrewJob -- it fills
## whether or not the player is standing there. Once it's ready, a DC check
## (Rng.roll_2d10, modifier = Creativity level, against the ever-climbing
## _current_roll_dc) rolls one offered Inspiration per degree of success, from
## the eligible catalog pool weighted by InspirationDef.weight, picked without
## replacement so the same Inspiration never appears twice in one offer.
## CHOOSING has no timer at all -- it just waits on choose_inspiration()/
## cancel_choice(). WORKING is a tethered accumulator exactly like WritJob:
## only advances while is_working is true (ArtStudioInteractable's
## player_exited wired the same way ContractBookInteractable's is), and
## pressing the interact key mid-WORKING opens a discard-confirm prompt rather
## than resolving anything, so a player who realizes a piece is too big for
## the time they have isn't stuck.

signal session_started(studio_id: String)
signal roll_rolled(studio_id: String, roll: Dictionary)
signal inspirations_offered(studio_id: String, offered_ids: Array)
signal no_inspiration(studio_id: String)
signal session_cancelled(studio_id: String)
signal work_started(studio_id: String, inspiration_id: String)
signal work_progress(studio_id: String)
signal work_paused(studio_id: String)
signal work_resumed(studio_id: String)
signal work_discarded(studio_id: String)
signal work_completed(studio_id: String, inspiration_id: String, roll: Dictionary, xp_gained: int)

## How long the initial "gathering inspiration" bar takes to fill -- tunable,
## same spirit as a mid-length BrewJob.
const ROLL_SESSION_MINUTES := 25

## The "drain on the creative well": the gathering-inspiration DC starts here,
## climbs by ROLL_DC_STEP every time it's rolled (successful or not), and only
## comes back down (never below this floor) on an actual voluntary sleep --
## see _on_day_ended().
const BASE_ROLL_DC := 5.0
const ROLL_DC_STEP := 5.0
const ROLL_DC_SLEEP_DECAY := 1.0

## Creativity XP on completion: a flat base scaled by the piece's own size/
## difficulty, then rescaled by how close the completion roll's total landed
## to the Inspiration's own dc -- tying it exactly gives full XP, overshooting
## or undershooting both cost more per point the further off it lands (see
## _completion_xp()).
const XP_PER_COMPLETION_MINUTE := 0.05
const XP_PER_DC_POINT := 2.0
const XP_OVER_DC_PENALTY := 0.10
const XP_UNDER_DC_PENALTY := 0.20

var _studios: Dictionary = {}              # studio_id -> ArtStudioJob
var _completed_unique_ids: Dictionary = {} # inspiration_id -> true
var _current_roll_dc: float = BASE_ROLL_DC

var _condition_asts: Dictionary = {}       # inspiration_id -> Array[AST]
var _parsed_rewards: Dictionary = {}       # inspiration_id -> Array[{action_ast, condition_ast, chance}]


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)
	Clock.day_ended.connect(_on_day_ended)

	for def in ContentRegistry.inspirations:
		var condition_asts: Array = []
		var ok := true
		for expr in def.conditions:
			var parser := VNExpressionParser.new()
			var ast = parser.parse(expr)
			if ast == null:
				push_error("ArtStudio: inspiration '%s' has an invalid condition '%s'" % [def.id, expr])
				ok = false
				break
			condition_asts.append(ast)
		if not ok:
			continue

		var parsed_rewards: Array = []
		for reward in def.rewards:
			var action_parser := VNExpressionParser.new()
			var action_ast = action_parser.parse(reward.action)
			var condition_parser := VNExpressionParser.new()
			var condition_ast = condition_parser.parse(reward.condition)
			if action_ast == null or condition_ast == null:
				push_error("ArtStudio: inspiration '%s' has an invalid reward expression" % def.id)
				ok = false
				break
			parsed_rewards.append({"action_ast": action_ast, "condition_ast": condition_ast, "chance": reward.chance})
		if not ok:
			continue

		_condition_asts[def.id] = condition_asts
		_parsed_rewards[def.id] = parsed_rewards


func get_job(studio_id: String) -> ArtStudioJob:
	return _studios.get(studio_id)


func get_offered_inspirations(studio_id: String) -> Array[String]:
	var job: ArtStudioJob = _studios.get(studio_id)
	var empty: Array[String] = []
	return job.offered_inspiration_ids if job != null else empty


## No-op if this studio already has a job running.
func start_session(studio_id: String) -> void:
	if _studios.has(studio_id):
		return
	var job := ArtStudioJob.new()
	job.studio_id = studio_id
	job.phase = ArtStudioJob.Phase.ROLLING
	job.start_timestamp = Clock.get_timestamp()
	job.ready_timestamp = job.start_timestamp + ROLL_SESSION_MINUTES
	_studios[studio_id] = job
	session_started.emit(studio_id)


## Picks the offered Inspiration and starts WORKING on it immediately -- the
## player is standing at the studio to have picked it, same "is_working true
## from the moment it starts" shape as Demonology.start_writ().
func choose_inspiration(studio_id: String, inspiration_id: String) -> void:
	var job: ArtStudioJob = _studios.get(studio_id)
	if job == null or job.phase != ArtStudioJob.Phase.CHOOSING:
		return
	if not job.offered_inspiration_ids.has(inspiration_id):
		return
	var def := ContentRegistry.get_inspiration(inspiration_id)
	if def == null:
		return
	job.offered_inspiration_ids.clear()
	job.inspiration_id = inspiration_id
	job.phase = ArtStudioJob.Phase.WORKING
	job.minutes_elapsed = 0
	job.minutes_required = maxi(def.completion_time, 1)
	job.is_working = true
	work_started.emit(studio_id, inspiration_id)


## The player declines every offered Inspiration -- throws the whole session
## away, same as walking away from a Dragon's Stash throws its dig away.
func cancel_choice(studio_id: String) -> void:
	var job: ArtStudioJob = _studios.get(studio_id)
	if job == null or job.phase != ArtStudioJob.Phase.CHOOSING:
		return
	_studios.erase(studio_id)
	session_cancelled.emit(studio_id)


## Standing at the studio (or walking away) toggles this; only an engaged
## WORKING job advances on minute_tick. No-op outside the WORKING phase.
func set_working(studio_id: String, working: bool) -> void:
	var job: ArtStudioJob = _studios.get(studio_id)
	if job == null or job.phase != ArtStudioJob.Phase.WORKING or job.is_working == working:
		return
	job.is_working = working
	if working:
		work_resumed.emit(studio_id)
	else:
		work_paused.emit(studio_id)


func pause_work(studio_id: String) -> void:
	set_working(studio_id, false)


func resume_work(studio_id: String) -> void:
	set_working(studio_id, true)


## Confirmed discard (ArtStudioInteractable's confirm prompt) -- throws the
## whole WORKING job away, no partial credit. No-op outside the WORKING phase.
func discard_work(studio_id: String) -> void:
	var job: ArtStudioJob = _studios.get(studio_id)
	if job == null or job.phase != ArtStudioJob.Phase.WORKING:
		return
	_studios.erase(studio_id)
	work_discarded.emit(studio_id)


func _on_minute_tick(timestamp: int) -> void:
	for studio_id in _studios.keys():
		var job: ArtStudioJob = _studios[studio_id]
		match job.phase:
			ArtStudioJob.Phase.ROLLING:
				if timestamp >= job.ready_timestamp:
					_resolve_roll(studio_id, job)
			ArtStudioJob.Phase.WORKING:
				if job.is_working:
					job.minutes_elapsed += 1
					work_progress.emit(studio_id)
					if job.minutes_elapsed >= job.minutes_required:
						_complete_work(studio_id, job)
			ArtStudioJob.Phase.CHOOSING:
				pass


## The gathering-inspiration bar just filled -- roll the DC check (climbing
## every time, regardless of outcome) and offer one weighted-random eligible
## Inspiration per degree of success. Zero degrees, or an eligible pool that
## runs dry before offering anything, both close the session out with nothing
## to show for it rather than opening an empty picker.
func _resolve_roll(studio_id: String, job: ArtStudioJob) -> void:
	var modifier := float(Skills.level("creativity"))
	var roll := Rng.roll_2d10(modifier, _current_roll_dc)
	_current_roll_dc += ROLL_DC_STEP
	roll_rolled.emit(studio_id, roll)

	var degrees: int = roll.degrees_of_success
	if degrees <= 0:
		_studios.erase(studio_id)
		no_inspiration.emit(studio_id)
		return

	var offered := _pick_inspirations(degrees)
	if offered.is_empty():
		_studios.erase(studio_id)
		no_inspiration.emit(studio_id)
		return

	job.offered_inspiration_ids = offered
	job.phase = ArtStudioJob.Phase.CHOOSING
	inspirations_offered.emit(studio_id, offered)


func _eligible_inspiration_ids() -> Array[String]:
	var ids: Array[String] = []
	for def in ContentRegistry.inspirations:
		if def.unique and _completed_unique_ids.has(def.id):
			continue
		if not _conditions_met(def.id):
			continue
		ids.append(def.id)
	return ids


func _conditions_met(inspiration_id: String) -> bool:
	if not _condition_asts.has(inspiration_id):
		return false
	for ast in _condition_asts[inspiration_id]:
		if not VNExpressionEvaluator.evaluate(ast):
			return false
	return true


## Weighted pick over the eligible pool, without replacement -- each draw
## removes the picked id so a single roll never offers the same Inspiration
## twice. Stops early (returning fewer than `count`) if the pool runs out.
func _pick_inspirations(count: int) -> Array[String]:
	var pool := _eligible_inspiration_ids()
	var chosen: Array[String] = []
	for i in count:
		if pool.is_empty():
			break
		var total := 0.0
		for id in pool:
			total += ContentRegistry.get_inspiration(id).weight
		if total <= 0.0:
			break
		var roll := Rng.range_f(0.0, total)
		var cumulative := 0.0
		var picked_index := pool.size() - 1
		for j in pool.size():
			cumulative += ContentRegistry.get_inspiration(pool[j]).weight
			if roll < cumulative:
				picked_index = j
				break
		chosen.append(pool[picked_index])
		pool.remove_at(picked_index)
	return chosen


## The WORKING accumulator reached the Inspiration's own completion_time --
## rolls its own DC check (unrelated to the gathering-inspiration DC/roll
## above), grants rewards scaled by that roll's degrees_of_success, marks it
## completed if unique, and grants Creativity XP scaled by how close the roll
## landed to the DC. Completion always happens regardless of pass/fail -- the
## check only modulates how good the rewards/XP are, same as a botched-but-
## still-submitted Demonology writ.
func _complete_work(studio_id: String, job: ArtStudioJob) -> void:
	var def := ContentRegistry.get_inspiration(job.inspiration_id)
	_studios.erase(studio_id)
	if def == null:
		return

	var modifier := float(Skills.level("creativity"))
	var roll := Rng.roll_2d10(modifier, float(def.dc))
	_grant_rewards(def, roll.degrees_of_success)
	if def.unique:
		_completed_unique_ids[def.id] = true

	var xp := _completion_xp(def, roll.total)
	Skills.add_xp("creativity", xp)

	work_completed.emit(studio_id, def.id, roll, xp)


func _grant_rewards(def: InspirationDef, degrees_of_success: int) -> void:
	var parsed: Array = _parsed_rewards.get(def.id, [])
	VNExpressionEvaluator.set_degrees_of_success(degrees_of_success)
	for reward in parsed:
		if not VNExpressionEvaluator.evaluate(reward.condition_ast):
			continue
		if Rng.chance(reward.chance):
			VNExpressionEvaluator.evaluate(reward.action_ast)
	VNExpressionEvaluator.set_degrees_of_success(0)


## Full XP at roll_total == dc, -10% per point over, -20% per point under --
## e.g. a DC15 Inspiration: 15 gives 100%, 18 gives 70%, 13 gives 60%.
func _completion_xp(def: InspirationDef, roll_total: float) -> int:
	var base_xp := float(def.completion_time) * XP_PER_COMPLETION_MINUTE + float(def.dc) * XP_PER_DC_POINT
	var diff := roll_total - float(def.dc)
	var scale := 1.0 - XP_OVER_DC_PENALTY * diff if diff >= 0.0 else 1.0 - XP_UNDER_DC_PENALTY * (-diff)
	return int(round(base_xp * clampf(scale, 0.0, 1.0)))


## Only a voluntary sleep drains the roll DC back down -- late-night collapse
## and Resolve collapse aren't "the player sleeping," they're the day ending
## on them, so neither counts here.
func _on_day_ended(reason: int) -> void:
	if reason == Clock.EndReason.SLEEP:
		_current_roll_dc = maxf(_current_roll_dc - ROLL_DC_SLEEP_DECAY, BASE_ROLL_DC)


## is_working is deliberately never persisted as true -- same reasoning as
## Demonology's writs: the player is never standing at the studio the instant
## a save loads, so every restored WORKING job comes back paused.
func get_save_data() -> Dictionary:
	var studios_data: Dictionary = {}
	for studio_id in _studios:
		var job: ArtStudioJob = _studios[studio_id]
		studios_data[studio_id] = {
			"phase": job.phase,
			"start_timestamp": job.start_timestamp,
			"ready_timestamp": job.ready_timestamp,
			"offered_inspiration_ids": job.offered_inspiration_ids,
			"inspiration_id": job.inspiration_id,
			"minutes_elapsed": job.minutes_elapsed,
			"minutes_required": job.minutes_required,
		}
	return {
		"studios": studios_data,
		"completed_unique_ids": _completed_unique_ids.keys(),
		"current_roll_dc": _current_roll_dc,
	}


func load_save_data(data: Dictionary) -> void:
	_studios.clear()
	var studios_data: Dictionary = data.get("studios", {})
	for studio_id in studios_data:
		var d: Dictionary = studios_data[studio_id]
		var job := ArtStudioJob.new()
		job.studio_id = studio_id
		job.phase = d.get("phase", ArtStudioJob.Phase.ROLLING) as ArtStudioJob.Phase
		job.start_timestamp = d.get("start_timestamp", 0)
		job.ready_timestamp = d.get("ready_timestamp", 0)
		var offered: Array[String] = []
		for id in (d.get("offered_inspiration_ids", []) as Array):
			offered.append(id as String)
		job.offered_inspiration_ids = offered
		job.inspiration_id = d.get("inspiration_id", "")
		job.is_working = false
		job.minutes_elapsed = d.get("minutes_elapsed", 0)
		job.minutes_required = d.get("minutes_required", 0)
		_studios[studio_id] = job

	_completed_unique_ids.clear()
	for id in (data.get("completed_unique_ids", []) as Array):
		_completed_unique_ids[id] = true

	_current_roll_dc = data.get("current_roll_dc", BASE_ROLL_DC)
