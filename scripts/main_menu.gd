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
var _root_nav: MenuKeyNav


func _ready() -> void:
	_build_root_menu()


func _build_root_menu() -> void:
	_root_layer = CanvasLayer.new()
	add_child(_root_layer)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"FramedPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root_layer.add_child(panel)
	UiFx.add_drop_shadow(panel)

	var vbox := VBoxContainer.new()
	# Doubled to match the 2x world-camera zoom — via real font sizes below
	# rather than Control.scale, which just stretches the already-rasterized
	# (small) glyph bitmaps and renders them blurry.
	vbox.custom_minimum_size = Vector2(560, 0)
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Vial Story"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 68)
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

	# Esc at the root screen deliberately does nothing (no back to go to, and
	# quitting on Esc would be hostile), so no on_back here.
	_root_nav = _attach_nav(vbox)


## Move/select keyboard-and-gamepad navigation for one of the menu's button
## columns (see MenuKeyNav). `require_pause` is off because nothing pauses on
## the title screen; a non-null `on_back` makes "back" act as that screen's
## Back button.
func _attach_nav(host: Control, on_back: Callable = Callable()) -> MenuKeyNav:
	var nav := MenuKeyNav.new()
	nav.require_pause = false
	if on_back.is_valid():
		nav.handle_back = true
		nav.back_requested.connect(on_back)
	host.add_child(nav)
	return nav


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
		data.character_name, data.pronouns, data.house_id, data.shop_origin,
		data.skill_allocations
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
	panel.theme_type_variation = &"FramedPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_load_layer.add_child(panel)
	UiFx.add_drop_shadow(panel)

	var vbox := VBoxContainer.new()
	# Doubled the same way as the main menu (see _build_root_menu) — real font
	# sizes, not Control.scale, so text rasterizes crisp instead of blurring.
	vbox.custom_minimum_size = Vector2(560, 0)
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Load Game"
	title.theme_type_variation = &"HeadingLabel"
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
	_load_status_label.modulate = UiPalette.DANGER
	vbox.add_child(_load_status_label)

	vbox.add_child(HSeparator.new())

	var back_button := Button.new()
	back_button.text = "Back (Esc/Q)"
	back_button.pressed.connect(_on_load_back_pressed)
	vbox.add_child(back_button)

	_attach_nav(vbox, _on_load_back_pressed)


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
	# The root layer never left the tree, so its nav must be re-armed by hand.
	_root_nav.reset()


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
	panel.theme_type_variation = &"FramedPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings_layer.add_child(panel)
	UiFx.add_drop_shadow(panel)

	var vbox := VBoxContainer.new()
	# Doubled to match the main/load menus (real font sizes via
	# SettingsControls, not Control.scale — see settings_controls.gd). The
	# settings list itself is capped in a ScrollContainer rather than left to
	# grow freely: SettingsControls' now-doubled rows add up to taller than
	# this screen used to need, and unlike GameMenu's Settings tab (already
	# scrolls per-section), this screen had no scroll wrapper at all before.
	vbox.custom_minimum_size = Vector2(560, 0)
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Settings"
	title.theme_type_variation = &"HeadingLabel"
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 700)
	vbox.add_child(scroll)

	var settings_vbox := VBoxContainer.new()
	settings_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(settings_vbox)
	SettingsControls.build(settings_vbox)

	vbox.add_child(HSeparator.new())

	var back_button := Button.new()
	back_button.text = "Back (Esc/Q)"
	back_button.pressed.connect(_on_settings_back_pressed)
	vbox.add_child(back_button)

	_attach_nav(vbox, _on_settings_back_pressed)


func _on_settings_back_pressed() -> void:
	_settings_layer.queue_free()
	_settings_layer = null
	_root_layer.visible = true
	_root_nav.reset()
