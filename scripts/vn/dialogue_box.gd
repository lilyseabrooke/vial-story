class_name DialogueBox
extends CanvasLayer
## Full-screen VN presentation layer. Drives itself entirely off a
## DialogueRunner's signals; see docs/design/systems.md, system 13 ("Runtime
## and presentation"). Deliberately not built on MenuScene — VN scenes are
## full-screen, not a chrome-and-content panel.
##
## Placeholder art only: characters are colored rectangles + a name/expression
## label, backgrounds are a solid color keyed by name. Real sprites/backgrounds
## can replace these node builders later without touching the signal-driven
## control flow. Character color/name comes from a registered CharacterDef
## (via the Characters autoload) when one exists for that id, falling back to
## a cycled placeholder palette for anyone not yet authored.

signal closed

const _REVEAL_SECONDS_PER_CHAR := 0.03
const _CHARACTER_COLORS: Array[Color] = [
	Color(0.85, 0.4, 0.4),
	Color(0.4, 0.6, 0.85),
	Color(0.5, 0.8, 0.5),
	Color(0.85, 0.75, 0.35),
]
const _DIMMED_ALPHA := 0.5

var _runner: DialogueRunner
var _background: ColorRect
var _stage: Control
var _name_label: Label
var _text_label: RichTextLabel
var _choice_box: VBoxContainer

var _characters: Dictionary = {}   # character name -> {"rect": ColorRect, "label": Label}
var _next_character_color_index: int = 0

var _reveal_timer: Timer
var _full_text: String = ""
var _revealed_chars: int = 0
var _is_revealing: bool = false
var _awaiting_choice: bool = false


func _ready() -> void:
	layer = 20

	_background = ColorRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.color = Color(0.1, 0.1, 0.12)
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_background.gui_input.connect(_on_background_input)
	add_child(_background)

	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	var dialogue_panel := PanelContainer.new()
	dialogue_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue_panel.offset_top = -180
	add_child(dialogue_panel)

	var vbox := VBoxContainer.new()
	dialogue_panel.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_name_label)

	_text_label = RichTextLabel.new()
	_text_label.custom_minimum_size = Vector2(0, 100)
	_text_label.bbcode_enabled = false
	_text_label.scroll_active = false
	vbox.add_child(_text_label)

	_choice_box = VBoxContainer.new()
	vbox.add_child(_choice_box)

	_reveal_timer = Timer.new()
	_reveal_timer.wait_time = _REVEAL_SECONDS_PER_CHAR
	_reveal_timer.timeout.connect(_on_reveal_timer_timeout)
	add_child(_reveal_timer)

	visible = false


## Compiles and begins playing `compiled_scene` (a VNScriptCompiler.compile()
## result). Pauses Clock and makes the box visible until the scene ends.
func open(compiled_scene: Dictionary) -> void:
	_clear_characters()
	_next_character_color_index = 0
	_choice_box.visible = false
	for child in _choice_box.get_children():
		child.queue_free()

	_runner = DialogueRunner.new()
	_runner.load_scene(compiled_scene)
	_runner.line_shown.connect(_on_line_shown)
	_runner.choice_requested.connect(_on_choice_requested)
	_runner.stage_changed.connect(_on_stage_changed)
	_runner.scene_ended.connect(_on_scene_ended)

	visible = true
	Clock.is_paused = true
	_runner.start()


func close() -> void:
	if not visible:
		return
	visible = false
	Clock.is_paused = false
	_clear_characters()
	closed.emit()


func is_open() -> bool:
	return visible


func _on_line_shown(speaker: String, text: String) -> void:
	_name_label.text = speaker
	_full_text = text
	_revealed_chars = 0
	_text_label.text = ""
	_is_revealing = true
	_set_active_speaker(speaker)
	_reveal_timer.start()


func _on_choice_requested(options: Array) -> void:
	_awaiting_choice = true
	for child in _choice_box.get_children():
		child.queue_free()
	for i in options.size():
		var option: Dictionary = options[i]
		var button := Button.new()
		button.text = option.text
		button.pressed.connect(_on_choice_button_pressed.bind(i))
		_choice_box.add_child(button)
	_choice_box.visible = true


func _on_choice_button_pressed(index: int) -> void:
	_awaiting_choice = false
	_choice_box.visible = false
	_runner.choose(index)


func _on_stage_changed(instruction: Dictionary) -> void:
	match instruction.op:
		"STAGE_BACKGROUND":
			_background.color = _color_for_name(instruction.name)
		"STAGE_ENTER":
			_spawn_character(instruction.character, instruction.x, instruction.y)
		"STAGE_EXIT":
			_remove_character(instruction.character)
		"STAGE_MOVE":
			var entry: Dictionary = _characters.get(instruction.character, {})
			if not entry.is_empty():
				entry.rect.position = Vector2(instruction.x, instruction.y)
		"STAGE_EXPRESSION":
			var char_entry: Dictionary = _characters.get(instruction.character, {})
			if not char_entry.is_empty():
				char_entry.label.text = "%s (%s)" % [instruction.character, instruction.expression]


func _on_scene_ended() -> void:
	close()


func _on_reveal_timer_timeout() -> void:
	_revealed_chars += 1
	_text_label.text = _full_text.substr(0, _revealed_chars)
	if _revealed_chars >= _full_text.length():
		_finish_reveal()


func _finish_reveal() -> void:
	_is_revealing = false
	_reveal_timer.stop()
	_text_label.text = _full_text


func _on_background_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _awaiting_choice:
		return
	if _is_revealing:
		_finish_reveal()
	else:
		_runner.advance()


func _spawn_character(character_name: String, x: float, y: float) -> void:
	if _characters.has(character_name):
		_remove_character(character_name)

	var rect := ColorRect.new()
	rect.size = Vector2(120, 300)
	rect.position = Vector2(x, y)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var character_def := Characters.get_character(character_name)
	if character_def:
		rect.color = character_def.placeholder_color
	else:
		rect.color = _CHARACTER_COLORS[_next_character_color_index % _CHARACTER_COLORS.size()]
		_next_character_color_index += 1

	_stage.add_child(rect)

	var label := Label.new()
	label.text = character_name
	label.position = Vector2(0, -24)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 16)
	rect.add_child(label)

	_characters[character_name] = {"rect": rect, "label": label}


func _remove_character(character_name: String) -> void:
	var entry: Dictionary = _characters.get(character_name, {})
	if entry.is_empty():
		return
	entry.rect.queue_free()
	_characters.erase(character_name)


func _clear_characters() -> void:
	for character_name in _characters.keys():
		_remove_character(character_name)


func _set_active_speaker(speaker: String) -> void:
	for character_name in _characters:
		var entry: Dictionary = _characters[character_name]
		entry.rect.modulate.a = 1.0 if character_name == speaker else _DIMMED_ALPHA


func _color_for_name(label: String) -> Color:
	var hash_value := label.hash()
	return Color.from_hsv(float(hash_value % 360) / 360.0, 0.35, 0.25)
