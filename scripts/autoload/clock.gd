extends Node
## Central ticking clock — see docs/design/systems.md, system 1.
## Autoloaded as "Clock".

signal minute_tick(timestamp: int)
signal day_started(day_number: int, day_type: int)
signal day_ended(reason: EndReason)

enum DayType { WEEKDAY, WEEKEND }
enum EndReason { SLEEP, LATE_COLLAPSE, RESOLVE_COLLAPSE }

const DAY_START_MINUTE := 360      # 6:00 AM
const DAY_LENGTH_MINUTES := 1200   # forced collapse 20 hours later, i.e. 2:00 AM
const MINUTES_PER_CALENDAR_DAY := 1440
const WEEKEND_DAY_INDICES := [5, 6]

@export var tick_rate_minutes_per_second: float = 10.0
var is_paused: bool = false

var day_number: int = 0
var minutes_into_day: int = 0

var _accumulator: float = 0.0


func _process(delta: float) -> void:
	if is_paused:
		return
	_accumulator += delta * tick_rate_minutes_per_second
	while _accumulator >= 1.0:
		_accumulator -= 1.0
		_tick_one_minute()


func _tick_one_minute() -> void:
	minutes_into_day += 1
	minute_tick.emit(get_timestamp())
	if minutes_into_day >= DAY_LENGTH_MINUTES:
		end_day(EndReason.LATE_COLLAPSE)


func day_type() -> DayType:
	return DayType.WEEKEND if (day_number % 7) in WEEKEND_DAY_INDICES else DayType.WEEKDAY


## Absolute, monotonically increasing timestamp for BrewJob/GrowPlot deadlines.
func get_timestamp() -> int:
	return day_number * MINUTES_PER_CALENDAR_DAY + DAY_START_MINUTE + minutes_into_day


## Minutes since midnight (0-1439), for comparing against fixed daily windows
## like shop open-hours, independent of when the in-game day started.
func minute_of_day() -> int:
	return (DAY_START_MINUTE + minutes_into_day) % MINUTES_PER_CALENDAR_DAY


func get_clock_string() -> String:
	var minute_of_day_value := minute_of_day()
	@warning_ignore("integer_division")
	var hour := minute_of_day_value / 60
	var minute := minute_of_day_value % 60
	var suffix := "AM" if hour < 12 else "PM"
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%d:%02d %s" % [display_hour, minute, suffix]


func sleep() -> void:
	end_day(EndReason.SLEEP)


func resolve_collapse() -> void:
	end_day(EndReason.RESOLVE_COLLAPSE)


func end_day(reason: EndReason) -> void:
	day_ended.emit(reason)
	_resolve_overnight_skip()
	day_number += 1
	minutes_into_day = 0
	_accumulator = 0.0
	day_started.emit(day_number, day_type())


## Placeholder for brewing/growing/shop resolution overnight.
## Brewing/growing/shop systems will connect to day_ended instead of this
## being their integration point directly — kept here as a documented seam.
func _resolve_overnight_skip() -> void:
	pass


## Generic TimeSkip utility for scheduled windows (e.g. attending class).
## Ticks minute-by-minute so minute_tick still fires for anything listening
## (brew/grow/shop resolution), rather than jumping the clock silently.
func skip_to(target_minutes_into_day: int) -> void:
	while minutes_into_day < target_minutes_into_day and minutes_into_day < DAY_LENGTH_MINUTES:
		_tick_one_minute()
