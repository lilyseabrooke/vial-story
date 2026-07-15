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

const CLASS_START_MINUTE := 8 * 60    # 8:00 AM
const CLASS_END_MINUTE := 12 * 60     # 12:00 PM
const EXAM_INTERVAL_DAYS := 7
const PASSING_SCORE := 50.0
const ATTENDANCE_BONUS := 15.0
const STRIKE_LIMIT := 3
const CLASS_XP_REWARD := 10
const CLASS_PERFORMANCE_DC := 11.0
const CLASS_PERFORMANCE_BONUS := 10.0

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
func attend_class() -> String:
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

	Skills.add_xp("herbalism", CLASS_XP_REWARD)
	Clock.skip_to(CLASS_END_MINUTE - Clock.DAY_START_MINUTE)
	attended_class.emit()
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
