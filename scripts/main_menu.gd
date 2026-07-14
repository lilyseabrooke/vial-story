class_name MainMenu
extends Node2D
## Title screen: New Game / Load Game / Settings / Quit. This is the entry
## point CharacterCreator used to fire behind unconditionally (see
## docs/design/systems.md, system 14) — now it's gated behind "New Game"
## here instead. Three ad hoc CanvasLayer screens (root menu, load-game
## list, settings) swapped by hide/show, same "no .tscn, no shared content
## base class" style as scripts/character_creator.gd and scripts/hud.gd.
##
## New Game runs CharacterCreator, then calls SaveManager.create_new_game()
## and hands the result to GameFlow before switching to Main.tscn. Load Game
## lists SaveManager.list_games() and quick-loads whichever one is picked.
## Settings is a set of generic, unwired placeholder controls only — no
## persistence, no gameplay effect.

const GAME_SCENE_PATH := "res://scenes/Main.tscn"

var _root_layer: CanvasLayer
var _load_layer: CanvasLayer
var _settings_layer: CanvasLayer
var _character_creator: CharacterCreator
var _load_status_label: Label


func _ready() -> void:
	_build_root_menu()


func _build_root_menu() -> void:
	_root_layer = CanvasLayer.new()
	add_child(_root_layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Vial Story"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var new_game_button := Button.new()
	new_game_button.text = "New Game"
	new_game_button.pressed.connect(_on_new_game_pressed)
	vbox.add_child(new_game_button)

	var load_game_button := Button.new()
	load_game_button.text = "Load Game"
	load_game_button.pressed.connect(_on_load_game_pressed)
	vbox.add_child(load_game_button)

	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.pressed.connect(_on_settings_pressed)
	vbox.add_child(settings_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit_button)


# ---------------------------------------------------------------------------
# New Game
# ---------------------------------------------------------------------------

func _on_new_game_pressed() -> void:
	_root_layer.visible = false
	_character_creator = CharacterCreator.new()
	add_child(_character_creator)
	_character_creator.build()
	_character_creator.confirmed.connect(_on_character_created)


func _on_character_created(data: Dictionary) -> void:
	var game_id := SaveManager.create_new_game(
		data.character_name, data.pronouns, data.house_id, data.shop_origin, data.player_color
	)
	GameFlow.game_id = game_id
	GameFlow.is_new_game = true
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


# ---------------------------------------------------------------------------
# Load Game
# ---------------------------------------------------------------------------

func _on_load_game_pressed() -> void:
	_root_layer.visible = false
	_build_load_menu()


func _build_load_menu() -> void:
	_load_layer = CanvasLayer.new()
	add_child(_load_layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_load_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Load Game"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var games := SaveManager.list_games()
	if games.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No saved games yet."
		vbox.add_child(empty_label)
	else:
		for meta in games:
			var button := Button.new()
			var day: int = meta.get("latest_day_number", 0)
			button.text = "%s — Day %d" % [meta.get("character_name", "?"), day]
			button.pressed.connect(_on_load_slot_pressed.bind(meta.get("game_id", "")))
			vbox.add_child(button)

	_load_status_label = Label.new()
	_load_status_label.modulate = Color(1.0, 0.4, 0.4)
	vbox.add_child(_load_status_label)

	vbox.add_child(HSeparator.new())

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(_on_load_back_pressed)
	vbox.add_child(back_button)


func _on_load_slot_pressed(game_id: String) -> void:
	var result := SaveManager.quick_load_latest(game_id)
	if not result.ok:
		_load_status_label.text = "Couldn't load save: %s" % result.error
		return
	GameFlow.game_id = game_id
	GameFlow.is_new_game = false
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_load_back_pressed() -> void:
	_load_layer.queue_free()
	_load_layer = null
	_root_layer.visible = true


# ---------------------------------------------------------------------------
# Settings — generic placeholder controls, deliberately not wired to anything
# ---------------------------------------------------------------------------

func _on_settings_pressed() -> void:
	_root_layer.visible = false
	_build_settings_menu()


func _build_settings_menu() -> void:
	_settings_layer = CanvasLayer.new()
	add_child(_settings_layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	_add_slider_setting(vbox, "Master Volume")
	_add_slider_setting(vbox, "Music Volume")
	_add_slider_setting(vbox, "SFX Volume")

	var fullscreen_check := CheckBox.new()
	fullscreen_check.text = "Fullscreen"
	vbox.add_child(fullscreen_check)

	var vsync_check := CheckBox.new()
	vsync_check.text = "V-Sync"
	vsync_check.button_pressed = true
	vbox.add_child(vsync_check)

	_add_option_setting(vbox, "Text Speed", ["Slow", "Normal", "Fast", "Instant"], 1)
	_add_option_setting(vbox, "Difficulty", ["Cozy", "Standard", "Challenging"], 1)

	var note := Label.new()
	note.text = "(Not wired up yet — prototype placeholder.)"
	note.modulate = Color(0.6, 0.6, 0.6)
	vbox.add_child(note)

	vbox.add_child(HSeparator.new())

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(_on_settings_back_pressed)
	vbox.add_child(back_button)


func _add_slider_setting(parent: VBoxContainer, label_text: String) -> void:
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


func _add_option_setting(
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


func _on_settings_back_pressed() -> void:
	_settings_layer.queue_free()
	_settings_layer = null
	_root_layer.visible = true
