extends Node
## Ley Line Node meditation + minigame session + spectral-ingredient reward.
## Autoloaded as "LeyLines". See docs/design/systems.md, the Ley Line Node
## System section.
##
## Two phases, back to back. Meditation is player-tethered like Draconology's
## stash jobs -- LeyLineNodeInteractable.interact() calls start_meditation(),
## RoomBuilder wires the node's player_exited to cancel_meditation() the same
## way it wires DragonStashInteractable, and _on_minute_tick() advances
## whichever LeyLineMeditationJobs are active. Once a job's bar fills, a
## Surge is rolled from that node's own configured odds; "none" or a failed
## Arcane History check against the Surge's DC just resets the bar to keep
## meditating (see _resolve_meditation()), while a passed check erases the
## job and hands the Surge's own difficulty/size/speed/rounds/rewards to the
## minigame phase, which is unchanged from before: MenuScene already pauses
## Clock and freezes the player, so once the minigame starts there's nothing
## left to tick or tether. LeyLineNodeInteractable.interact() hands off to
## start_meditation() and otherwise does nothing further; hud.gd opens the
## minigame panel (LeyLineMinigamePanel) in response to minigame_started, and
## that panel calls back into resolve_minigame()/abort_minigame() once the
## player finishes or bails. No get_save_data()/load_save_data() -- active
## meditation and minigame sessions are deliberately not persisted, the same
## as Draconology's stash jobs and Transmutation's scrap jobs.

signal meditation_started(node_id: String)
signal meditation_progress(node_id: String)
signal meditation_cancelled(node_id: String)
## Fired the instant a job's bar reaches its minutes_required, strictly before
## _resolve_meditation() does anything else to that job -- a "none"/failed
## check resets minutes_elapsed to 0 in the same tick, and a passed check
## erases the job outright, so without this the bar's tween would either
## never actually reach full before animating back down (it'd be superseded
## by the reset tween in the same frame) or, on success, be left stuck at
## whatever it last tweened to since no further meditation_progress ever
## fires for an erased job. RoomBuilder listens for this to snap the meter
## straight to full with no tween, so the *next* signal (a reset's
## meditation_progress, or a success's minigame_started) has a true 1.0 to
## animate away from instead of racing it.
signal meditation_bar_full(node_id: String)
## Fired every time a node's bar fills and a Surge is rolled, whether or not
## it goes anywhere -- "none" (an empty Dictionary roll) or a failed DC check
## (a populated 2d10 roll Dictionary, see Rng.roll_2d10()) both reset the bar
## and are reported here so hud.gd can log/roll-popup them; a passed check is
## reported here too, immediately followed by minigame_started.
signal meditation_check_rolled(node_id: String, surge_id: String, roll: Dictionary)

signal minigame_started(node_id: String, difficulty: float, rounds: int)
signal minigame_resolved(node_id: String, performance: float, tier: String, ingredients: Dictionary)
signal minigame_aborted(node_id: String)

## Performance is a single 0.0-1.0 float the minigame reports back --
## these are the cutoffs between reward tiers, checked from the top down.
const TIER_THRESHOLDS := {
	"great": 0.85,
	"good": 0.6,
	"poor": 0.25,
}

## Bonus motes grabbed mid-arena (unrelated to a Surge's own rewards table)
## always draw from this fixed pool, same as before -- only the tier reward
## itself now comes from whichever Surge triggered the run.
const SPECTRAL_INGREDIENT_IDS := ["glimmer_dust", "echo_shard"]

const XP_PER_MINIGAME := 20

## Fallback only -- LeyLineNodeInteractable.meditation_minutes is what's
## actually used; this just keeps start_meditation() safe if ever called with
## a non-positive value.
const DEFAULT_MEDITATION_MINUTES := 10

var _meditation_jobs: Dictionary = {}   # node_id -> LeyLineMeditationJob

var _active_node_id: String = ""
var _active_difficulty: float = 0.0
var _active_rounds: int = 0
## Stubbed -- carried through from the triggering Surge for whenever the
## minigame arena reads them, but nothing consumes them yet.
var _active_size: float = 0.0
var _active_speed: float = 0.0
## The triggering Surge's own rewards table (Array of [ingredient_id, likelihood]
## pairs), consumed by resolve_minigame() via _roll_rewards() instead of the
## old fixed per-tier ingredient count.
var _active_rewards: Array = []


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)


func is_active() -> bool:
	return _active_node_id != ""


func get_active_node_id() -> String:
	return _active_node_id


func get_meditation_job(node_id: String) -> LeyLineMeditationJob:
	return _meditation_jobs.get(node_id)


## Called by LeyLineNodeInteractable.interact() when the node has no job
## running yet. No-op if a job already exists for this node, or a minigame
## session is already active anywhere (shouldn't normally happen -- MenuScene
## freezes the player for the whole minigame -- but guarded the same way
## start_minigame() used to guard itself).
func start_meditation(node_id: String, minutes_required: int, surge_ids: Array[String], surge_weights: Array[float]) -> void:
	if _meditation_jobs.has(node_id) or is_active():
		return
	var job := LeyLineMeditationJob.new()
	job.node_id = node_id
	job.minutes_required = maxi(minutes_required, 1) if minutes_required > 0 else DEFAULT_MEDITATION_MINUTES
	job.surge_ids = surge_ids.duplicate()
	job.surge_weights = surge_weights.duplicate()
	_meditation_jobs[node_id] = job
	meditation_started.emit(node_id)


## The player stepping away throws the whole meditation job away, same
## "walking away costs everything" shape as Draconology.cancel_stash() --
## unlike a Contract Book's writ, there's no paused state to resume into.
## No-op if there's nothing to cancel.
func cancel_meditation(node_id: String) -> void:
	if not _meditation_jobs.has(node_id):
		return
	_meditation_jobs.erase(node_id)
	meditation_cancelled.emit(node_id)


func _on_minute_tick(_timestamp: int) -> void:
	for node_id in _meditation_jobs.keys():
		var job: LeyLineMeditationJob = _meditation_jobs[node_id]
		job.minutes_elapsed += 1
		if job.minutes_elapsed >= job.minutes_required:
			meditation_bar_full.emit(node_id)
			_resolve_meditation(node_id, job)
		else:
			meditation_progress.emit(node_id)


## The bar just filled -- roll a Surge from this job's own configured odds
## and, unless it's "none", roll an Arcane History check against that Surge's
## DC. "none" and a failed check are handled identically: the bar resets to 0
## and meditation continues at the same node, no job lost. A passed check
## erases the meditation job outright and launches the minigame with that
## Surge's own numbers.
func _resolve_meditation(node_id: String, job: LeyLineMeditationJob) -> void:
	var surge_id := _pick_surge(job.surge_ids, job.surge_weights)
	if surge_id == "" or surge_id == "none":
		job.minutes_elapsed = 0
		meditation_check_rolled.emit(node_id, "none", {})
		meditation_progress.emit(node_id)
		return

	var surge := ContentRegistry.get_ley_line_surge(surge_id)
	if surge == null:
		# An id in this node's table that isn't in the catalog -- treat like
		# "none" rather than crash on a data-authoring mistake.
		job.minutes_elapsed = 0
		meditation_check_rolled.emit(node_id, "none", {})
		meditation_progress.emit(node_id)
		return

	var modifier := float(Skills.level("arcane_history"))
	var roll := Rng.roll_2d10(modifier, float(surge.dc))
	meditation_check_rolled.emit(node_id, surge_id, roll)
	if not roll.passed:
		job.minutes_elapsed = 0
		meditation_progress.emit(node_id)
		return

	_meditation_jobs.erase(node_id)
	_launch_minigame(node_id, surge)


## Weighted pick over a node's own surge_ids/surge_weights, drawn uniformly
## across their total (they don't need to sum to 1.0 -- any unclaimed
## fraction of the total just never gets rolled). Falls back to "none" if the
## table's empty or every weight is 0, rather than dividing by zero.
func _pick_surge(surge_ids: Array[String], surge_weights: Array[float]) -> String:
	var total := 0.0
	for weight in surge_weights:
		total += weight
	if surge_ids.is_empty() or total <= 0.0:
		return "none"
	var roll := Rng.range_f(0.0, total)
	var cumulative := 0.0
	for i in surge_ids.size():
		cumulative += surge_weights[i]
		if roll < cumulative:
			return surge_ids[i]
	return surge_ids[surge_ids.size() - 1]


## Applies leyline_ease (Arcane History) to soften the triggering Surge's own
## difficulty, then hands its rounds/size/speed/rewards to the minigame --
## size/speed are stashed for later, nothing reads them yet.
func _launch_minigame(node_id: String, surge: LeyLineSurgeDef) -> void:
	var ease_bonus := Skills.get_bonus("leyline_ease")
	_active_node_id = node_id
	_active_difficulty = maxf(surge.difficulty - ease_bonus, 0.0)
	_active_rounds = surge.rounds
	_active_size = surge.size
	_active_speed = surge.speed
	_active_rewards = surge.rewards
	minigame_started.emit(node_id, _active_difficulty, _active_rounds)


## Called by the minigame (LeyLineMinigamePanel) with a single 0.0-1.0
## performance number once it's finished, plus the count of bonus motes the
## player grabbed in-arena. A non-failure tier rolls the triggering Surge's
## own rewards table via _roll_rewards() instead of a fixed per-tier count --
## a performance below every tier's threshold grants nothing from it. Bonus
## motes are granted regardless of tier (even on a failed run, from the fixed
## SPECTRAL_INGREDIENT_IDS pool, unrelated to the Surge) since collecting one
## is its own earned reward. Both funnel into the same ingredients dict so
## hud.gd's reward summary shows them together.
func resolve_minigame(performance: float, bonus_ingredients: int = 0) -> void:
	if not is_active():
		return
	var node_id := _active_node_id
	var p := clampf(performance, 0.0, 1.0)
	var tier := _tier_for_performance(p)

	# performance is already 0..1, so it doubles directly as the quality
	# fraction -- a stronger channel yields both more AND better ingredients.
	var quality_tier := IngredientQuality.tier_for_fraction(p)

	var ingredients: Dictionary = {}
	if tier != "":
		ingredients = _roll_rewards(_active_rewards)
		for id in ingredients:
			Inventory.add_ingredient(id, ingredients[id], quality_tier)
		Skills.add_xp("arcane_history", XP_PER_MINIGAME)

	for i in maxi(bonus_ingredients, 0):
		var bonus_id: String = SPECTRAL_INGREDIENT_IDS[Rng.range_i(0, SPECTRAL_INGREDIENT_IDS.size() - 1)]
		Inventory.add_ingredient(bonus_id, 1, quality_tier)
		ingredients[bonus_id] = ingredients.get(bonus_id, 0) + 1

	_clear_active_session()
	minigame_resolved.emit(node_id, p, tier if tier != "" else "failure", ingredients)


## Bailing on the minigame mid-run -- no ingredients, no XP, session just
## thrown away. Same "walking away costs everything" shape as
## Draconology.cancel_stash(), just triggered by the player choosing to quit
## the minigame (or closing the menu) instead of leaving the node's
## proximity, since MenuScene already freezes the player in place for the
## whole session. The meditation job that led here was already erased the
## moment the DC check passed, so the player has to start meditating from
## scratch again, same as if they'd never rolled a Surge at all.
func abort_minigame() -> void:
	if not is_active():
		return
	var node_id := _active_node_id
	_clear_active_session()
	minigame_aborted.emit(node_id)


func _clear_active_session() -> void:
	_active_node_id = ""
	_active_difficulty = 0.0
	_active_rounds = 0
	_active_size = 0.0
	_active_speed = 0.0
	_active_rewards = []


func _tier_for_performance(p: float) -> String:
	if p >= TIER_THRESHOLDS["great"]:
		return "great"
	if p >= TIER_THRESHOLDS["good"]:
		return "good"
	if p >= TIER_THRESHOLDS["poor"]:
		return "poor"
	return ""


## Rolls a Surge's rewards table: each [ingredient_id, likelihood] pair grants
## one ingredient per iteration of "guaranteed while likelihood >= 1.0, then a
## probabilistic roll at the current likelihood that halves after every
## success and stops at the first failure" -- so a likelihood of 2.0 always
## grants two, then has a 50% chance of a third, 25% of a fourth, and so on.
## If a full pass over every reward grants nothing at all, the whole table is
## rolled again until something is -- guarded by bailing out up front if the
## table's empty or every likelihood is 0, so that retry can't hang forever.
func _roll_rewards(rewards: Array) -> Dictionary:
	if rewards.is_empty():
		return {}
	var total_weight := 0.0
	for reward in rewards:
		total_weight += float(reward[1])
	if total_weight <= 0.0:
		return {}

	var granted: Dictionary = {}
	while granted.is_empty():
		for reward in rewards:
			var id: String = reward[0]
			var chance: float = float(reward[1])
			while chance > 0.0:
				if chance >= 1.0 or Rng.chance(chance):
					granted[id] = granted.get(id, 0) + 1
					chance = chance / 2.0
				else:
					break
	return granted
