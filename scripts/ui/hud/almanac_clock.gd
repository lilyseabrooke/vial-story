class_name AlmanacClock
extends PanelContainer
## Top-right HUD card: a cozy almanac day-page. Shows "Day N · Weekday/Weekend",
## the clock time with a sun/moon time-of-day icon, and the Sims-style speed
## toggle (1x/1.5x/2x). Replaces hud.gd's inline calendar/time labels + speed
## buttons; hud.gd calls update_time() on Clock ticks and sync_speed() on
## speed_level_changed.

const DAY_TYPE_NAMES := ["Weekday", "Weekend"]
# Daytime window for the sun/moon icon: 6:00 AM (360) – 6:00 PM (1080).
const DAY_START_MINUTE := 360
const DAY_END_MINUTE := 1080

var _day_label: Label
var _time_label: Label
var _tod_icon: TimeOfDayIcon
var _speed_buttons: Array[Button] = []


func build() -> void:
	theme_type_variation = &"SmallFramedPanel"
	custom_minimum_size = Vector2(200, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	add_child(vbox)

	_day_label = Label.new()
	_day_label.theme_type_variation = &"HeadingLabel"
	vbox.add_child(_day_label)

	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	vbox.add_child(time_row)

	_tod_icon = TimeOfDayIcon.new()
	_tod_icon.custom_minimum_size = Vector2(26, 26)
	_tod_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_row.add_child(_tod_icon)

	_time_label = Label.new()
	_time_label.theme_type_variation = &"NumericLabel"
	_time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_row.add_child(_time_label)

	var speed_hbox := HBoxContainer.new()
	speed_hbox.add_theme_constant_override("separation", 4)
	vbox.add_child(speed_hbox)

	var speed_group := ButtonGroup.new()
	var speed_labels := ["1x", "1.5x", "2x"]
	for i in speed_labels.size():
		var speed_button := Button.new()
		speed_button.text = speed_labels[i]
		speed_button.toggle_mode = true
		speed_button.button_group = speed_group
		speed_button.button_pressed = (i == Clock.speed_level)
		speed_button.custom_minimum_size = Vector2(46, 0)
		speed_button.pressed.connect(func() -> void:
			Clock.set_speed_level(i)
		)
		_speed_buttons.append(speed_button)
		speed_hbox.add_child(speed_button)


func update_time() -> void:
	_day_label.text = "Day %d · %s" % [Clock.day_number, DAY_TYPE_NAMES[Clock.day_type()]]
	_time_label.text = "%s%s" % [Clock.get_clock_string(), "   (paused)" if Clock.is_paused else ""]
	var minute := Clock.minute_of_day()
	_tod_icon.set_day(minute >= DAY_START_MINUTE and minute < DAY_END_MINUTE)


func sync_speed(level: int) -> void:
	if level >= 0 and level < _speed_buttons.size():
		_speed_buttons[level].button_pressed = true
