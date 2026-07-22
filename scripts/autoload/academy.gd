extends Node
## Class attendance, exams, and grades — the fail state. Autoloaded as "Academy".
## See docs/design/systems.md, system 9.
##
## "Class" is a time-gated debug-HUD action for now rather than a walk-to
## trigger, since Exploration (system 12) isn't built — same scope choice
## made for Shop's open hours.

signal attended_class
signal absence_recorded(absences: int)
signal exam_graded(passed: bool, score: float, strikes: int)
signal game_over
signal class_performance_rolled(result: Dictionary)
## One per reward roll (HIGH effort rolls twice) — fired before the matching
## class_reward_granted so a dice popup can render ahead of the log line.
signal class_reward_rolled(result: Dictionary)
signal class_reward_granted(reward_type: String, description: String)

const CLASS_START_MINUTE := 8 * 60    # 8:00 AM
const CLASS_END_MINUTE := 12 * 60     # 12:00 PM
const EXAM_INTERVAL_DAYS := 7
const PASSING_SCORE := 50.0
const ATTENDANCE_BONUS := 15.0
const STRIKE_LIMIT := 3
const CLASS_XP_REWARD := 10
const CLASS_PERFORMANCE_DC := 11.0
const CLASS_PERFORMANCE_BONUS := 10.0

## Coasting/Regular/Burn It — chosen at the class door each time the player
## attends. Higher effort spends more Resolve for a better shot at rewards.
enum Effort { LOW, NORMAL, HIGH }

const EFFORT_NAMES := ["Coast", "Regular Effort", "Burn It (110%)"]

## Resolve spent immediately on attending, scaled by chosen effort — "very
## little" at LOW, a real bite at HIGH, matching Brewing's botch cost order
## of magnitude.
const EFFORT_RESOLVE_COST := {
	Effort.LOW: 3,
	Effort.NORMAL: 10,
	Effort.HIGH: 24,
}
## How many reward rolls effort buys — burning it gets a second shot at the
## table rather than a guaranteed double reward, keeping HIGH exciting
## instead of just strictly-better-and-predictable.
const EFFORT_REWARD_ROLLS := {
	Effort.LOW: 1,
	Effort.NORMAL: 1,
	Effort.HIGH: 2,
}
## Multiplies each reward's magnitude — this is the "amplified by effort"
## half of the ask; the Focus roll below is the other half.
const EFFORT_REWARD_MULTIPLIER := {
	Effort.LOW: 0.5,
	Effort.NORMAL: 1.0,
	Effort.HIGH: 1.75,
}

## The Focus roll that amplifies (or dampens) a reward's magnitude on top of
## effort — a critical success bumps it further, a failed roll shrinks it,
## same "crit nudges quality" shape Summoning/Demonology use.
const REWARD_ROLL_DC := 11.0
const REWARD_CRIT_MULTIPLIER := 1.5
const REWARD_FAIL_MULTIPLIER := 0.5

## Reward table rolled uniformly per reward. Any type whose pool is
## momentarily empty (e.g. every recipe already learned) falls back to
## "materials" rather than granting nothing.
const REWARD_TYPES := [
	"ingredient", "materials", "recipe", "summoning_sequence",
	"relationship", "skill", "reputation",
]
const BASE_INGREDIENT_QTY := 1
const BASE_MATERIAL_REWARD := 4
const BASE_SKILL_XP := 8
const BASE_AFFECTION_GAIN := 2
const BASE_REPUTATION_GAIN := 1

var running_score: float = 0.0
var strikes: int = 0
var absences: int = 0
var is_game_over: bool = false

var _attended_today: bool = false
var _last_exam_day: int = 0


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)
	Clock.day_started.connect(_on_day_started)


func days_until_exam() -> int:
	return EXAM_INTERVAL_DAYS - (Clock.day_number - _last_exam_day)


func is_class_in_session() -> bool:
	if Clock.day_type() != Clock.DayType.WEEKDAY:
		return false
	var minute := Clock.minute_of_day()
	return minute >= CLASS_START_MINUTE and minute < CLASS_END_MINUTE


## Returns "" on success, or a short reason string on failure.
func attend_class(effort: Effort = Effort.NORMAL) -> String:
	if is_game_over:
		return "The Academy has revoked your selling privileges."
	if not is_class_in_session():
		return "There's no class in session right now."
	if _attended_today:
		return "Already attended class today."

	_attended_today = true
	running_score = minf(running_score + ATTENDANCE_BONUS, 100.0)

	var modifier := Skills.get_bonus("class_performance")
	var result := Rng.roll_2d10(modifier, CLASS_PERFORMANCE_DC)
	if result.passed:
		running_score = minf(running_score + CLASS_PERFORMANCE_BONUS, 100.0)
	class_performance_rolled.emit(result)

	Skills.add_xp("focus", CLASS_XP_REWARD)
	Resolve.spend(EFFORT_RESOLVE_COST[effort], "pushing through class (%s)" % EFFORT_NAMES[effort])

	var reward_multiplier: float = EFFORT_REWARD_MULTIPLIER[effort]
	for i in EFFORT_REWARD_ROLLS[effort]:
		_roll_class_reward(reward_multiplier)

	Clock.skip_to(CLASS_END_MINUTE - Clock.DAY_START_MINUTE)
	attended_class.emit()
	return ""


## One reward pick: a Focus roll amplifies/dampens the effort-scaled
## magnitude, then a uniformly-chosen reward type is granted at that
## magnitude.
func _roll_class_reward(effort_multiplier: float) -> void:
	var modifier := float(Skills.level("focus"))
	var roll := Rng.roll_2d10(modifier, REWARD_ROLL_DC)
	class_reward_rolled.emit(roll)

	var magnitude := effort_multiplier
	if roll.critical_success:
		magnitude *= REWARD_CRIT_MULTIPLIER
	elif not roll.passed:
		magnitude *= REWARD_FAIL_MULTIPLIER

	var reward_type: String = REWARD_TYPES[Rng.range_i(0, REWARD_TYPES.size() - 1)]
	var description := _grant_reward(reward_type, magnitude)
	class_reward_granted.emit(reward_type, description)


## Grants one reward of `reward_type` scaled by `magnitude`, returning a
## short description for the log/reward-granted signal. Falls back to
## "materials" when a reward type's pool is momentarily empty (e.g. every
## recipe already learned) rather than granting nothing.
func _grant_reward(reward_type: String, magnitude: float) -> String:
	match reward_type:
		"ingredient":
			if ContentRegistry.ingredients.is_empty():
				return _grant_reward("materials", magnitude)
			var ingredient: IngredientDef = ContentRegistry.ingredients[
				Rng.range_i(0, ContentRegistry.ingredients.size() - 1)]
			var qty := maxi(1, int(round(BASE_INGREDIENT_QTY * magnitude)))
			Inventory.add_ingredient(ingredient.id, qty)
			return "%dx %s" % [qty, ingredient.display_name]

		"materials":
			var amount := maxi(1, int(round(BASE_MATERIAL_REWARD * magnitude)))
			Inventory.add_materials(amount)
			return "%d Materials" % amount

		"recipe":
			var unlearned: Array[RecipeDef] = []
			for recipe in ContentRegistry.recipes:
				if not Alchemy.is_learned(recipe.id):
					unlearned.append(recipe)
			if unlearned.is_empty():
				return _grant_reward("materials", magnitude)
			var recipe: RecipeDef = unlearned[Rng.range_i(0, unlearned.size() - 1)]
			Alchemy.learn_recipe(recipe.id)
			return "new recipe: %s" % recipe.display_name

		"summoning_sequence":
			var unknown: Array[RiftBundleDef] = []
			for bundle in ContentRegistry.rift_bundles:
				if not Summoning.knows_bundle(bundle.id):
					unknown.append(bundle)
			if unknown.is_empty():
				return _grant_reward("materials", magnitude)
			var bundle: RiftBundleDef = unknown[Rng.range_i(0, unknown.size() - 1)]
			Summoning.learn_bundle(bundle.id)
			return "new summoning sequence: %s" % bundle.display_name

		"relationship":
			var character_ids := Characters.all_character_ids()
			if character_ids.is_empty():
				return _grant_reward("materials", magnitude)
			var character_id: String = character_ids[Rng.range_i(0, character_ids.size() - 1)]
			var amount := maxi(1, int(round(BASE_AFFECTION_GAIN * magnitude)))
			LoveInterests.add_affection(character_id, amount)
			var character := Characters.get_character(character_id)
			var display_name: String = character.display_name if character else character_id
			return "+%d affection with %s" % [amount, display_name]

		"skill":
			var skill_ids := Skills.skill_ids()
			var skill_id: String = skill_ids[Rng.range_i(0, skill_ids.size() - 1)]
			var amount := maxi(1, int(round(BASE_SKILL_XP * magnitude)))
			Skills.add_xp(skill_id, amount)
			var def := Skills.get_def(skill_id)
			return "+%d XP in %s" % [amount, def.display_name if def else skill_id]

		"reputation":
			var amount := maxi(1, int(round(BASE_REPUTATION_GAIN * magnitude)))
			Shop.add_reputation(amount)
			return "+%d shop reputation" % amount

		_:
			return ""


func _on_day_started(day_number: int, _day_type: int) -> void:
	_attended_today = false
	if day_number - _last_exam_day >= EXAM_INTERVAL_DAYS:
		_run_exam(day_number)


func _run_exam(day_number: int) -> void:
	_last_exam_day = day_number
	var passed := running_score >= PASSING_SCORE
	if passed:
		strikes = maxi(strikes - 1, 0)
	else:
		strikes += 1
	exam_graded.emit(passed, running_score, strikes)
	running_score = 0.0

	if strikes >= STRIKE_LIMIT:
		is_game_over = true
		Clock.is_paused = true
		game_over.emit()


func _on_minute_tick(_timestamp: int) -> void:
	if is_game_over or _attended_today or Clock.day_type() != Clock.DayType.WEEKDAY:
		return
	if Clock.minute_of_day() == CLASS_END_MINUTE:
		absences += 1
		absence_recorded.emit(absences)


func get_save_data() -> Dictionary:
	return {
		"running_score": running_score,
		"strikes": strikes,
		"absences": absences,
		"is_game_over": is_game_over,
		"attended_today": _attended_today,
		"last_exam_day": _last_exam_day,
	}


func load_save_data(data: Dictionary) -> void:
	running_score = data.get("running_score", 0.0)
	strikes = data.get("strikes", 0)
	absences = data.get("absences", 0)
	is_game_over = data.get("is_game_over", false)
	_attended_today = data.get("attended_today", false)
	_last_exam_day = data.get("last_exam_day", 0)
