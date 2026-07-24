extends Node
## Contract Book / writ bartering with demonic entities for demonic
## ingredients. Autoloaded as "Demonology". See docs/design/systems.md, the
## Demonology / Contract System section.
##
## A writ's clock is not a Clock timestamp deadline like BrewJob/
## GrowPlotInstance -- it only advances while the player is standing at the
## book (is_working, toggled by ContractBookInteractable via set_working()),
## so minutes_elapsed/minutes_required is an accumulator this autoload
## increments on every engaged minute_tick rather than a fixed deadline
## compared against Clock.get_timestamp(). Escaping to the game menu (which
## sets Clock.is_paused) halts every writ for free, same as it halts brewing.

signal writ_started(book_id: String)
signal writ_progress(book_id: String)
signal writ_first_draft_done(book_id: String, quality: float)
signal writ_revised(book_id: String, revisions_completed: int, quality: float)
signal writ_paused(book_id: String)
signal writ_resumed(book_id: String)
signal writ_submitted(book_id: String, roll: Dictionary, ingredients: Dictionary, drawback_messages: Array)
signal consequence_triggered(message: String)

enum ConsequenceType { RESOLVE_LOSS, REPUTATION_LOSS, CLASS_PERFORMANCE_LOSS, RELATIONSHIP_LOSS, SHOP_STOCK_LOSS, INVENTORY_LOSS }
const CONSEQUENCE_TYPE_COUNT := 6

const XP_PER_WRIT := 30

# Timing -- BASE_REVISION_MINUTES is exactly half of BASE_WRITING_MINUTES per
# design (every revision costs the same, constant, reduced time; only the
# quality bonus per revision diminishes, not the time). Skill speed comes from
# a "demon barter" modifier computed continuously off the Demonology skill's
# level (DEMON_BARTER_PER_LEVEL per level, unlike every other skill effect,
# which is a flat bonus unlocked at fixed level thresholds via SkillDef) --
# so writs keep getting faster every single level rather than plateauing
# after one threshold, per direct request rather than an existing pattern
# elsewhere in the skill system.
const BASE_WRITING_MINUTES := 60
const BASE_REVISION_MINUTES := 30
const MINUTES_PER_BARTER_POINT := 10.0
const DEMON_BARTER_PER_LEVEL := 0.5
const MIN_PHASE_MINUTES := 5

## Reaching this many revisions on one writ is an edge case far past the
## expected 3-7 revisions of a normal writ -- auto-submit and file it away
## rather than let the accumulator (and diamond grid) run forever.
const MAX_REVISIONS := 100

const QUALITY_BASE_MIN := 30.0
const QUALITY_BASE_VARIANCE := 15.0
const QUALITY_PER_DEMONOLOGY_LEVEL := 3.0
const FIRST_REVISION_BONUS := 10.0
const REVISION_DECAY := 0.85

const SUBMIT_DC := 11.0
const CRIT_QUALITY_SWING := 15.0

const DEMONIC_INGREDIENT_IDS := ["imp_ash", "brimstone_shard"]
const BASE_INGREDIENT_COUNT := 1
const QUALITY_INGREDIENT_DIVISOR := 20.0

## Quality at/above this submits clean -- no drawbacks at all.
const DRAWBACK_QUALITY_THRESHOLD := 100.0
const MAX_DRAWBACKS := 4
const RESOLVE_DRAWBACK_BASE := 15
const REPUTATION_DRAWBACK_BASE := 5
const CLASS_PERFORMANCE_DRAWBACK_BASE := 10
const RELATIONSHIP_DRAWBACK_BASE := 5

## A drawback rolled as "future" instead of immediate fires this many days
## later -- represented as a pending-consequence queue checked every minute
## tick against Clock.get_timestamp(), the same deadline-comparison shape as
## BrewJob's ready_timestamp.
const FUTURE_CONSEQUENCE_CHANCE := 0.5
const FUTURE_CONSEQUENCE_MIN_DAYS := 1
const FUTURE_CONSEQUENCE_MAX_DAYS := 5

var _writs: Dictionary = {}                  # book_id -> WritJob
var _pending_consequences: Array[Dictionary] = []   # {type, severity, trigger_timestamp}


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)


func get_writ(book_id: String) -> WritJob:
	return _writs.get(book_id)


## Creates a fresh writ at `book_id` and immediately marks it as being worked
## on. No-op if a writ is already open on this book (the interactable's
## interact() should route to resume/submit instead in that case).
func start_writ(book_id: String) -> void:
	if _writs.has(book_id):
		return
	var writ := WritJob.new()
	writ.book_id = book_id
	writ.is_working = true
	writ.minutes_required = _writing_minutes()
	_writs[book_id] = writ
	writ_started.emit(book_id)


## Standing at the book (or walking away) toggles this; only an engaged writ
## advances on minute_tick. Escape/opening the game menu doesn't need to call
## this at all -- Clock.is_paused already halts every writ along with
## everything else Clock-driven.
func set_working(book_id: String, working: bool) -> void:
	var writ: WritJob = _writs.get(book_id)
	if writ == null or writ.is_working == working:
		return
	writ.is_working = working
	if working:
		writ_resumed.emit(book_id)
	else:
		writ_paused.emit(book_id)


func pause_writ(book_id: String) -> void:
	set_working(book_id, false)


func resume_writ(book_id: String) -> void:
	set_working(book_id, true)


## Rolls a 2d10 Demonology check against the writ's accumulated quality,
## grants demonic ingredients scaled to the result, applies drawbacks scaled
## inversely to quality (immediate or queued for a future day), then closes
## the writ out. No-op (returns silently) if the writ hasn't finished its
## first draft yet -- there's nothing to submit during the initial WRITING
## phase.
func submit_writ(book_id: String) -> void:
	var writ: WritJob = _writs.get(book_id)
	if writ == null or not writ.can_submit():
		return

	var modifier := _demon_barter()
	var roll := Rng.roll_2d10(modifier, SUBMIT_DC)

	var final_quality := writ.quality
	if roll.critical_success:
		final_quality += CRIT_QUALITY_SWING
	elif roll.critical_failure:
		final_quality -= CRIT_QUALITY_SWING
	final_quality = maxf(final_quality, 0.0)

	var ingredients := _grant_ingredients(final_quality)
	var drawback_messages := _apply_drawbacks(final_quality)

	_writs.erase(book_id)
	Skills.add_xp("demonology", XP_PER_WRIT)
	writ_submitted.emit(book_id, roll, ingredients, drawback_messages)


func _writing_minutes() -> int:
	var reduction := _demon_barter() * MINUTES_PER_BARTER_POINT
	return maxi(MIN_PHASE_MINUTES, int(round(BASE_WRITING_MINUTES - reduction)))


func _revision_minutes() -> int:
	var reduction := _demon_barter() * (MINUTES_PER_BARTER_POINT * 0.5)
	return maxi(MIN_PHASE_MINUTES, int(round(BASE_REVISION_MINUTES - reduction)))


## Continuous per-level scaling rather than Skills' usual flat-bonus-at-a-
## threshold shape (see SkillDef/Skills.get_bonus) -- demon_barter isn't
## tracked in Skills._bonus_totals at all, so the Resolve-strained halving
## Skills.get_bonus() applies has to be replicated here directly.
func _demon_barter() -> float:
	var value := Skills.level("demonology") * DEMON_BARTER_PER_LEVEL
	if Resolve.is_strained():
		value *= Resolve.STRAINED_DEBUFF_MULTIPLIER
	return value


func _roll_initial_quality() -> float:
	var level := Skills.level("demonology")
	var base := QUALITY_BASE_MIN + level * QUALITY_PER_DEMONOLOGY_LEVEL
	return clampf(base + Rng.range_f(-QUALITY_BASE_VARIANCE, QUALITY_BASE_VARIANCE), 0.0, 200.0)


## Diminishing per the design: each revision's bonus is REVISION_DECAY times
## the previous one's, while the time cost per revision stays constant.
func _revision_bonus(revision_number: int) -> float:
	return FIRST_REVISION_BONUS * pow(REVISION_DECAY, revision_number - 1)


func _on_minute_tick(timestamp: int) -> void:
	for book_id in _writs.keys():
		var writ: WritJob = _writs[book_id]
		if not writ.is_working:
			continue
		writ.minutes_elapsed += 1
		writ_progress.emit(book_id)
		if writ.minutes_elapsed >= writ.minutes_required:
			_complete_phase(book_id, writ)
	_resolve_pending_consequences(timestamp)


func _complete_phase(book_id: String, writ: WritJob) -> void:
	if writ.status == WritJob.Status.WRITING:
		writ.quality = _roll_initial_quality()
		writ.status = WritJob.Status.REVISING
		writ.minutes_elapsed = 0
		writ.minutes_required = _revision_minutes()
		writ_first_draft_done.emit(book_id, writ.quality)
	else:
		writ.revisions_completed += 1
		writ.quality += _revision_bonus(writ.revisions_completed)
		writ.minutes_elapsed = 0
		writ.minutes_required = _revision_minutes()
		writ_revised.emit(book_id, writ.revisions_completed, writ.quality)
		if writ.revisions_completed >= MAX_REVISIONS:
			submit_writ(book_id)


func _grant_ingredients(quality: float) -> Dictionary:
	var yield_bonus := Skills.get_bonus("demon_yield")
	var count := int(BASE_INGREDIENT_COUNT + floor(quality / QUALITY_INGREDIENT_DIVISOR) + yield_bonus)
	count = maxi(count, 1)
	# quality is clamped [0, 200] (see _roll_initial_quality) -- every unit
	# from this grant shares the tier that quality maps to.
	var tier := IngredientQuality.tier_for_fraction(quality / 200.0)
	var granted: Dictionary = {}
	for i in count:
		var id: String = DEMONIC_INGREDIENT_IDS[Rng.range_i(0, DEMONIC_INGREDIENT_IDS.size() - 1)]
		Inventory.add_ingredient(id, 1, tier)
		granted[id] = granted.get(id, 0) + 1
	return granted


func _drawback_count_for_quality(quality: float) -> int:
	if quality >= DRAWBACK_QUALITY_THRESHOLD:
		return 0
	elif quality >= 70.0:
		return 1
	elif quality >= 40.0:
		return 2
	else:
		return mini(MAX_DRAWBACKS, 3 + int((40.0 - quality) / 20.0))


## Rolls `_drawback_count_for_quality(quality)` drawbacks, each independently
## either firing immediately or queued FUTURE_CONSEQUENCE_MIN/MAX_DAYS out.
## Returns one message per drawback (immediate ones describe what happened
## now; queued ones just foreshadow that something is coming).
func _apply_drawbacks(quality: float) -> Array[String]:
	var messages: Array[String] = []
	var severity := clampf(1.0 - quality / DRAWBACK_QUALITY_THRESHOLD, 0.0, 1.0)
	for i in _drawback_count_for_quality(quality):
		var type: int = Rng.range_i(0, CONSEQUENCE_TYPE_COUNT - 1)
		if Rng.chance(FUTURE_CONSEQUENCE_CHANCE):
			_queue_future_consequence(type, severity)
			messages.append("Something is owed, but the demon hasn't come to collect yet...")
		else:
			messages.append(_apply_consequence_now(type, severity))
	return messages


func _apply_consequence_now(type: int, severity: float) -> String:
	match type:
		ConsequenceType.RESOLVE_LOSS:
			var amount := int(RESOLVE_DRAWBACK_BASE * (0.5 + severity))
			Resolve.spend(amount, "a demonic contract's fine print")
			return "The demon's fine print costs you %d Resolve." % amount
		ConsequenceType.REPUTATION_LOSS:
			var amount := int(REPUTATION_DRAWBACK_BASE * (0.5 + severity))
			Shop.reputation = maxi(Shop.reputation - amount, 0)
			return "Word spreads of the deal -- shop reputation drops by %d." % amount
		ConsequenceType.CLASS_PERFORMANCE_LOSS:
			var amount := int(CLASS_PERFORMANCE_DRAWBACK_BASE * (0.5 + severity))
			Academy.running_score = maxf(Academy.running_score - amount, 0.0)
			return "Your focus slips in class -- performance drops by %d." % amount
		ConsequenceType.RELATIONSHIP_LOSS:
			return _damage_random_relationship(severity)
		ConsequenceType.SHOP_STOCK_LOSS:
			return _consume_random_shop_stock()
		ConsequenceType.INVENTORY_LOSS:
			return _consume_random_ingredient()
		_:
			return ""


func _damage_random_relationship(severity: float) -> String:
	var character_ids := Characters.all_character_ids()
	if character_ids.is_empty():
		return "You feel a pang of guilt, though no one in particular seems to notice."
	var character_id: String = character_ids[Rng.range_i(0, character_ids.size() - 1)]
	var amount := int(RELATIONSHIP_DRAWBACK_BASE * (0.5 + severity))
	LoveInterests.add_affection(character_id, -amount)
	var character := Characters.get_character(character_id)
	var display_name := character.display_name if character else character_id
	return "%s hears about the deal and thinks less of you (-%d)." % [display_name, amount]


func _consume_random_shop_stock() -> String:
	if Shop.slots.is_empty():
		return "The demon reaches for the shop shelf, but finds nothing to take."
	var index := Rng.range_i(0, Shop.slots.size() - 1)
	var slot: Dictionary = Shop.slots[index]
	Shop.slots.remove_at(index)
	return "A %s vanishes from the shop shelf overnight." % slot.potion_id


func _consume_random_ingredient() -> String:
	var owned_ids: Array = []
	for id in Inventory.ingredient_counts:
		if Inventory.ingredient_count(id) > 0:
			owned_ids.append(id)
	if owned_ids.is_empty():
		return "The demon rifles through your stores, but finds nothing to take."
	var id: String = owned_ids[Rng.range_i(0, owned_ids.size() - 1)]
	Inventory.consume_ingredient(id, 1)
	return "A unit of %s disappears from your stores." % id


func _queue_future_consequence(type: int, severity: float) -> void:
	var delay_days := Rng.range_i(FUTURE_CONSEQUENCE_MIN_DAYS, FUTURE_CONSEQUENCE_MAX_DAYS)
	var trigger_timestamp := Clock.get_timestamp() + delay_days * Clock.MINUTES_PER_CALENDAR_DAY
	_pending_consequences.append({
		"type": type,
		"severity": severity,
		"trigger_timestamp": trigger_timestamp,
	})


func _resolve_pending_consequences(timestamp: int) -> void:
	var i := _pending_consequences.size() - 1
	while i >= 0:
		var entry: Dictionary = _pending_consequences[i]
		if timestamp >= int(entry.trigger_timestamp):
			var message := _apply_consequence_now(int(entry.type), float(entry.severity))
			consequence_triggered.emit(message)
			_pending_consequences.remove_at(i)
		i -= 1


## is_working is deliberately not persisted as true -- the player is never
## standing at the book at the moment a save is loaded, so every restored
## writ comes back paused (same call the player would make by walking away).
func get_save_data() -> Dictionary:
	var writs_data: Dictionary = {}
	for book_id in _writs:
		var writ: WritJob = _writs[book_id]
		writs_data[book_id] = {
			"status": writ.status,
			"minutes_elapsed": writ.minutes_elapsed,
			"minutes_required": writ.minutes_required,
			"quality": writ.quality,
			"revisions_completed": writ.revisions_completed,
		}
	return {
		"writs": writs_data,
		"pending_consequences": _pending_consequences.duplicate(true),
	}


func load_save_data(data: Dictionary) -> void:
	_writs.clear()
	var writs_data: Dictionary = data.get("writs", {})
	for book_id in writs_data:
		var d: Dictionary = writs_data[book_id]
		var writ := WritJob.new()
		writ.book_id = book_id
		writ.status = d.get("status", WritJob.Status.WRITING) as WritJob.Status
		writ.is_working = false
		writ.minutes_elapsed = d.get("minutes_elapsed", 0)
		writ.minutes_required = d.get("minutes_required", 0)
		writ.quality = d.get("quality", 0.0)
		writ.revisions_completed = d.get("revisions_completed", 0)
		_writs[book_id] = writ

	_pending_consequences.clear()
	for entry in (data.get("pending_consequences", []) as Array):
		_pending_consequences.append(entry)
