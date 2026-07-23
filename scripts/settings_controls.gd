class_name SettingsControls
extends RefCounted
## Shared settings controls used by both the main menu's Settings screen
## (scripts/main_menu.gd) and the in-game Escape menu's Settings tab
## (scripts/game_menu.gd), so the two can't drift out of sync.
##
## Resolution/fullscreen/V-Sync are real OS window settings (not game state),
## so they're wired directly to DisplayServer here rather than needing a
## return value the caller has to thread through. Text Speed drives
## DialogueBox's typewriter reveal rate via the Settings autoload, for the
## same reason. Volume sliders and Difficulty remain unwired placeholders —
## no audio bus or difficulty-scaling system exists yet for them to drive.

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

static func build(parent: VBoxContainer) -> void:
	_add_slider_setting(parent, "Master Volume")
	_add_slider_setting(parent, "Music Volume")
	_add_slider_setting(parent, "SFX Volume")

	_add_resolution_setting(parent)

	var fullscreen_check := CheckBox.new()
	fullscreen_check.text = "Fullscreen"
	fullscreen_check.button_pressed = (
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	parent.add_child(fullscreen_check)

	var vsync_check := CheckBox.new()
	vsync_check.text = "V-Sync"
	vsync_check.button_pressed = (
		DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	)
	vsync_check.toggled.connect(_on_vsync_toggled)
	parent.add_child(vsync_check)

	_add_text_speed_setting(parent)
	_add_option_setting(parent, "Difficulty", ["Cozy", "Standard", "Challenging"], 1)

	var note := Label.new()
	note.text = "(Volume/Difficulty not wired up yet — prototype placeholder.)"
	note.modulate = UiPalette.TEXT_MUTED
	parent.add_child(note)


static func _add_resolution_setting(parent: VBoxContainer) -> void:
	var caption := Label.new()
	caption.text = "Resolution"
	parent.add_child(caption)

	var option_button := OptionButton.new()
	var current_size := DisplayServer.window_get_size()
	var selected_index := -1
	for i in RESOLUTIONS.size():
		var res := RESOLUTIONS[i]
		option_button.add_item("%dx%d" % [res.x, res.y])
		if res == current_size:
			selected_index = i
	if selected_index == -1:
		option_button.add_item("%dx%d (Current)" % [current_size.x, current_size.y])
		selected_index = option_button.item_count - 1
	option_button.selected = selected_index
	option_button.item_selected.connect(_on_resolution_selected)
	parent.add_child(option_button)


static func _on_resolution_selected(index: int) -> void:
	if index < 0 or index >= RESOLUTIONS.size():
		return
	var res := RESOLUTIONS[index]
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(res)
	var screen_size := DisplayServer.screen_get_size()
	DisplayServer.window_set_position((screen_size - res) / 2)


static func _on_fullscreen_toggled(pressed: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	)


static func _on_vsync_toggled(pressed: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if pressed else DisplayServer.VSYNC_DISABLED
	)


static func _add_text_speed_setting(parent: VBoxContainer) -> void:
	var caption := Label.new()
	caption.text = "Text Speed"
	parent.add_child(caption)

	var option_button := OptionButton.new()
	for option_label in ["Slow", "Normal", "Fast", "Instant"]:
		option_button.add_item(option_label)
	var current_index: int = Settings.TEXT_SPEED_MULTIPLIERS.find(Settings.text_speed_multiplier)
	option_button.selected = (
		current_index if current_index != -1 else Settings.DEFAULT_TEXT_SPEED_INDEX
	)
	option_button.item_selected.connect(Settings.set_text_speed_index)
	parent.add_child(option_button)


static func _add_slider_setting(parent: VBoxContainer, label_text: String) -> void:
	var caption := Label.new()
	caption.text = label_text
	parent.add_child(caption)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 0.8
	slider.custom_minimum_size = Vector2(220, 0)
	parent.add_child(slider)


static func _add_option_setting(
	parent: VBoxContainer, label_text: String, options: Array, default_index: int
) -> void:
	var caption := Label.new()
	caption.text = label_text
	parent.add_child(caption)

	var option_button := OptionButton.new()
	for option_label in options:
		option_button.add_item(option_label)
	option_button.selected = default_index
	parent.add_child(option_button)
