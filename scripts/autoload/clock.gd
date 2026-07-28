extends Node
## Central ticking clock — see docs/design/systems.md, system 1.
## Autoloaded as "Clock".

signal minute_tick(timestamp: int)
signal day_started(day_number: int, day_type: int)
signal day_ended(reason: EndReason)
signal speed_level_changed(level: int)
## Bracket any large jump in time (sleeping, a collapse, attending class) so
## presentation code (see ScreenFade) can cover the jump with a fade rather
## than showing the clock/labels snap to their new values instantly.
## time_skip_started fires the moment the fade-out begins; the actual jump
## (day_ended/minute_tick/day_started) doesn't happen until TIME_SKIP_FADE_SECONDS
## later, once the screen is fully black, and time_skip_finished fires after the
## hold, as the screen starts fading back in — see end_day()/skip_to().
signal time_skip_started
signal time_skip_finished

enum DayType { WEEKDAY, WEEKEND }
enum EndReason { SLEEP, LATE_COLLAPSE, RESOLVE_COLLAPSE }

const DAY_START_MINUTE := 360      # 6:00 AM
const DAY_LENGTH_MINUTES := 1200   # forced collapse 20 hours later, i.e. 2:00 AM
const MINUTES_PER_CALENDAR_DAY := 1440
## Shared with ScreenFade so its fade-out/hold-black/fade-in animation lines up
## exactly with the window where Clock holds ticking and jump work — see
## end_day()/skip_to().
const TIME_SKIP_FADE_SECONDS := 0.35
const TIME_SKIP_HOLD_SECONDS := 1.0
const WEEKEND_DAY_INDICES := [5, 6]
# Index 0 aligns with day_number 0, and with WEEKEND_DAY_INDICES above.
const DAY_NAMES: Array[String] = [
	"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
]

# Sims-style speed buttons: index 0/1/2 = 1x/1.5x/2x, multiplying the base rate.
const SPEED_MULTIPLIERS: Array[float] = [1.0, 1.5, 2.0]
# How fast tick_rate_minutes_per_second eases toward the target speed's rate —
# higher = snappier. Tuned so a 1x<->2x swing takes a few hundred ms rather
# than snapping instantly (jerky) or crawling (feels unresponsive).
const SPEED_EASE_RATE := 6.0

@export var tick_rate_minutes_per_second: float = 2.5
var is_paused: bool = false

var day_number: int = 0
var minutes_into_day: int = 0
var speed_level: int = 0

var _accumulator: float = 0.0
var _base_tick_rate: float = 2.5
var _target_tick_rate: float = 2.5


func _ready() -> void:
	_base_tick_rate = tick_rate_minutes_per_second
	_target_tick_rate = tick_rate_minutes_per_second


func _process(delta: float) -> void:
	tick_rate_minutes_per_second = move_toward(
		tick_rate_minutes_per_second, _target_tick_rate, _target_tick_rate * SPEED_EASE_RATE * delta
	)
	if is_paused:
		return
	_accumulator += delta * tick_rate_minutes_per_second
	while _accumulator >= 1.0:
		_accumulator -= 1.0
		_tick_one_minute()


## Sims-style 1x/1.5x/2x speed buttons. Eases tick_rate_minutes_per_second
## toward the new target over time (see _process) rather than snapping, so
## time visibly speeds up/slows down instead of jerking between rates.
func set_speed_level(level: int) -> void:
	level = clampi(level, 0, SPEED_MULTIPLIERS.size() - 1)
	if level == speed_level:
		return
	speed_level = level
	_target_tick_rate = _base_tick_rate * SPEED_MULTIPLIERS[level]
	speed_level_changed.emit(speed_level)


func _tick_one_minute() -> void:
	minutes_into_day += 1
	minute_tick.emit(get_timestamp())
	if minutes_into_day >= DAY_LENGTH_MINUTES:
		end_day(EndReason.LATE_COLLAPSE)


func day_type() -> DayType:
	return DayType.WEEKEND if (day_number % 7) in WEEKEND_DAY_INDICES else DayType.WEEKDAY


func day_name() -> String:
	return DAY_NAMES[day_number % 7]


## Absolute, monotonically increasing timestamp for BrewJob/GrowPlot deadlines.
func get_timestamp() -> int:
	return day_number * MINUTES_PER_CALENDAR_DAY + DAY_START_MINUTE + minutes_into_day


## Minutes since midnight (0-1439), for comparing against fixed daily windows
## like shop open-hours, independent of when the in-game day started.
func minute_of_day() -> int:
	return (DAY_START_MINUTE + minutes_into_day) % MINUTES_PER_CALENDAR_DAY


## Displayed minute is floored to the nearest 10 (7:20 shows until 7:30, etc.)
## so the HUD clock reads like a stylized sim-game clock rather than ticking
## every in-game minute.
func get_clock_string() -> String:
	var minute_of_day_value := minute_of_day()
	@warning_ignore("integer_division")
	var hour := minute_of_day_value / 60
	@warning_ignore("integer_division")
	var minute := (minute_of_day_value % 60 / 10) * 10
	var suffix := "AM" if hour < 12 else "PM"
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%d:%02d %s" % [display_hour, minute, suffix]


func sleep() -> void:
	end_day(EndReason.SLEEP)


func resolve_collapse() -> void:
	end_day(EndReason.RESOLVE_COLLAPSE)


## Async so the actual jump (day_ended/overnight ticks/day_started) waits
## until the screen has faded fully to black — see the time_skip_* doc above.
## is_paused is forced on for the whole sequence (restored to whatever it was
## before) so nothing moves or acts while time is skipping; is_paused alone
## already halts every Clock-driven system and player input (see CLAUDE.md),
## so no separate freeze flag is needed.
func end_day(reason: EndReason) -> void:
	time_skip_started.emit()
	var was_paused := is_paused
	is_paused = true
	await get_tree().create_timer(TIME_SKIP_FADE_SECONDS).timeout
	day_ended.emit(reason)
	_skip_overnight_to_next_day_start()
	day_number += 1
	minutes_into_day = 0
	_accumulator = 0.0
	day_started.emit(day_number, day_type())
	await get_tree().create_timer(TIME_SKIP_HOLD_SECONDS).timeout
	is_paused = was_paused
	time_skip_finished.emit()


## Ticks minute-by-minute from the current time through to next day's 6 AM
## start, emitting minute_tick for each one, so anything hooked to it (shop
## sales, etc.) still gets the chance to resolve as if the overnight/collapse
## gap had been played through in real time rather than the clock silently
## jumping. Increments minutes_into_day past DAY_LENGTH_MINUTES on purpose —
## bypasses _tick_one_minute's collapse check since end_day() is already
## handling that.
func _skip_overnight_to_next_day_start() -> void:
	var minutes_remaining := MINUTES_PER_CALENDAR_DAY - minutes_into_day
	for _i in range(minutes_remaining):
		minutes_into_day += 1
		minute_tick.emit(get_timestamp())


## Generic TimeSkip utility for scheduled windows (e.g. attending class).
## Ticks minute-by-minute so minute_tick still fires for anything listening
## (brew/grow/shop resolution), rather than jumping the clock silently.
## See end_day()'s doc comment — same fade-out/jump/hold/fade-in shape and the
## same is_paused freeze for the duration.
func skip_to(target_minutes_into_day: int) -> void:
	time_skip_started.emit()
	var was_paused := is_paused
	is_paused = true
	await get_tree().create_timer(TIME_SKIP_FADE_SECONDS).timeout
	while minutes_into_day < target_minutes_into_day and minutes_into_day < DAY_LENGTH_MINUTES:
		_tick_one_minute()
	await get_tree().create_timer(TIME_SKIP_HOLD_SECONDS).timeout
	is_paused = was_paused
	time_skip_finished.emit()


func get_save_data() -> Dictionary:
	return {
		"day_number": day_number,
		"minutes_into_day": minutes_into_day,
		"is_paused": is_paused,
	}


## _accumulator is intentionally not saved — it's sub-minute tick fraction,
## resetting to 0.0 on load is imperceptible.
func load_save_data(data: Dictionary) -> void:
	day_number = data.get("day_number", 0)
	minutes_into_day = data.get("minutes_into_day", 0)
	is_paused = data.get("is_paused", false)
	_accumulator = 0.0
