class_name SettingsControls
extends RefCounted
## Shared "generic, unwired" settings controls (volume sliders, fullscreen/
## V-Sync toggles, text speed/difficulty options) used by both the main
## menu's Settings screen (scripts/main_menu.gd) and the in-game Escape
## menu's Settings tab (scripts/game_menu.gd), so the two can't drift out of
## sync. Still no persistence, no gameplay effect — prototype placeholder.

static func build(parent: VBoxContainer) -> void:
	_add_slider_setting(parent, "Master Volume")
	_add_slider_setting(parent, "Music Volume")
	_add_slider_setting(parent, "SFX Volume")

	var fullscreen_check := CheckBox.new()
	fullscreen_check.text = "Fullscreen"
	parent.add_child(fullscreen_check)

	var vsync_check := CheckBox.new()
	vsync_check.text = "V-Sync"
	vsync_check.button_pressed = true
	parent.add_child(vsync_check)

	_add_option_setting(parent, "Text Speed", ["Slow", "Normal", "Fast", "Instant"], 1)
	_add_option_setting(parent, "Difficulty", ["Cozy", "Standard", "Challenging"], 1)

	var note := Label.new()
	note.text = "(Not wired up yet — prototype placeholder.)"
	note.modulate = Color(0.6, 0.6, 0.6)
	parent.add_child(note)


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
