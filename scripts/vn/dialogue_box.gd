class_name DialogueBox
extends CanvasLayer
## VN presentation layer, overlaid on top of the room rather than a
## full-screen takeover. Drives itself entirely off a DialogueRunner's
## signals; see docs/design/systems.md, system 13 ("Runtime and
## presentation"). Deliberately not built on MenuScene — the dialogue panel
## is one framed window among possible full-scene staging (backgrounds,
## character sprites), not chrome wrapping arbitrary bespoke content.
##
## Laid out in scenes/vn/DialogueBox.tscn (the panel's FramedPanel styling
## and edge padding live there) — this script only owns behavior. Dialogue
## text color/size come from theme/ui_theme.tres' RichTextLabel entry (a
## project-wide default for every RichTextLabel, since this is currently the
## only one) rather than a per-instance override on TextLabel itself — bump
## that theme entry, not this scene, to resize dialogue text. `Stage`
## (where character rectangles get added) and the
## "select"/click advance handling still assume Background covers the full
## viewport and DialoguePanel sits at the bottom with room to spare above it
## for `Stage` content, so keep that shape if you edit the scene.
##
## Placeholder art only: characters are colored rectangles + a name/expression
## label, backgrounds (when a scene sets one via `background <name>`) are a
## solid color keyed by name. Real sprites/backgrounds can replace these node
## builders later without touching the signal-driven control flow. Character
## color/name comes from a registered CharacterDef (via the Characters
## autoload) when one exists for that id, falling back to a cycled
## placeholder palette for anyone not yet authored.
##
## The background stays fully transparent unless a scene explicitly sets one
## with `background <name>` — most conversations (a quick NPC exchange) play
## out overlaid on the room the player is standing in, not a VN-style
## full backdrop; scenes that want the traditional full-screen look just
## need a `background` line, same as before.
##
## The speaker name renders in `Nameplate`, a separate dark-frame
## (`FramedPanelDark`) tag overlaid straddling DialoguePanel's top border —
## not a label inside the panel itself — so it reads as a physical tag
## clipped onto the frame. Its horizontal slot (one of five: left,
## center-left, center, center-right, right) is per-line data, set via a
## `nameplate <position>` stage direction in the .vnscript (persists across
## lines like `background` does, until changed again); scenes that never set
## one default to "center". See `_position_nameplate()`.
##
## `"Alchemist"` is a reserved speaker/character id meaning the player --
## scripts write `enter Alchemist at x,y` / `Alchemist: "text"` same as any
## other character, but wherever a name actually renders (nameplate, the
## small label over a character rectangle) `_resolve_display_name()` swaps
## it for `PlayerProfile.character_name` instead of showing the literal word
## "Alchemist". Internal matching (`_characters` dict keys, `_set_active_speaker`'s
## dimming) still keys off the raw "Alchemist" id, since that's fixed at
## script-authoring time while the player's actual name isn't.
##
## Typewriter reveal rate is `_REVEAL_SECONDS_PER_CHAR` scaled by
## `Settings.text_speed_multiplier` (the Settings screens' Text Speed
## dropdown), read fresh each time a line starts so a mid-scene change takes
## effect on the next line. A multiplier of 0.0 ("Instant") skips the timer
## and reveals the whole line immediately.

signal closed

const _REVEAL_SECONDS_PER_CHAR := 0.03
const _CHARACTER_COLORS: Array[Color] = [
	Color(0.85, 0.4, 0.4),
	Color(0.4, 0.6, 0.85),
	Color(0.5, 0.8, 0.5),
	Color(0.85, 0.75, 0.35),
]
const _DIMMED_ALPHA := 0.5
const _TRANSPARENT := Color(0, 0, 0, 0)
## Where each slot's *center* sits, as a fraction of DialoguePanel's width --
## keys match VNScriptCompiler's `nameplate <position>` grammar exactly. The
## panel is divided into five equal 20%-wide blocks (left = 0-20%, center-left
## = 20-40%, ... right = 80-100%) and the nameplate centers within its block,
## so these are the block midpoints (10%, 30%, 50%, 70%, 90%) rather than 0/1
## flush against the panel's edges.
const _NAMEPLATE_POSITIONS := {
	"left": 0.1,
	"center-left": 0.3,
	"center": 0.5,
	"center-right": 0.7,
	"right": 0.9,
}
const _DEFAULT_NAMEPLATE_POSITION := "center"
const _PLAYER_CHARACTER_ID := "Alchemist"
## Matches MenuScene's own open animation constants/feel -- see
## _begin_open_animation(). A thin strip, not zero, so the frame's 9-patch
## corners never invert.
const _OPEN_COLLAPSED_HEIGHT := 56.0
const _OPEN_ANIMATION_DURATION := 0.18

@onready var _background: ColorRect = $Background
@onready var _stage: Control = $Stage
@onready var _text_label: RichTextLabel = $DialoguePanel/Margin/VBox/TextLabel
@onready var _choice_box: VBoxContainer = $DialoguePanel/Margin/VBox/ChoiceBox
@onready var _dialogue_panel: PanelContainer = $DialoguePanel
@onready var _nameplate: PanelContainer = $Nameplate
@onready var _nameplate_label: Label = $Nameplate/Margin/NameplateLabel
@onready var _reveal_timer: Timer = $RevealTimer

var _runner: DialogueRunner
var _characters: Dictionary = {}   # character name -> {"rect": ColorRect, "label": Label}
var _next_character_color_index: int = 0
var _nameplate_position: String = _DEFAULT_NAMEPLATE_POSITION
var _panel_target_offset_top: float
var _panel_target_offset_bottom: float
var _open_tween: Tween

var _full_text: String = ""
var _revealed_chars: int = 0
var _is_revealing: bool = false
var _awaiting_choice: bool = false


func _ready() -> void:
	_background.gui_input.connect(_on_background_input)
	_reveal_timer.timeout.connect(_on_reveal_timer_timeout)
	# Captured once, before _begin_open_animation() ever touches these -- the
	# panel's authored resting rect from the scene file, read live rather
	# than duplicated as hardcoded literals so resizing the panel in the
	# editor doesn't also require updating an animation constant somewhere.
	_panel_target_offset_top = _dialogue_panel.offset_top
	_panel_target_offset_bottom = _dialogue_panel.offset_bottom
	# Hidden here, not baked into the .tscn's `visible` property -- the scene
	# file stays visible=true so it previews normally in the editor; _ready()
	# only runs once actually instantiated at runtime.
	visible = false


## Compiles and begins playing `compiled_scene` (a VNScriptCompiler.compile()
## result). Pauses Clock and makes the box visible until the scene ends.
func open(compiled_scene: Dictionary) -> void:
	_clear_characters()
	_background.color = _TRANSPARENT
	_nameplate_position = _DEFAULT_NAMEPLATE_POSITION
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
	_begin_open_animation()
	_runner.start()


func close() -> void:
	if not visible:
		return
	if _open_tween:
		_open_tween.kill()
	visible = false
	Clock.is_paused = false
	_clear_characters()
	closed.emit()


func is_open() -> bool:
	return visible


## Grows DialoguePanel from a thin strip at its top edge down to its
## authored resting rect -- top-down, matching every other window's open
## animation in this game (MenuScene._begin_open_animation()) even though
## DialoguePanel itself is bottom-docked: offset_top is pinned to its final
## value for the whole animation and only offset_bottom moves, rather than
## the reverse. Simpler than MenuScene's version either way: DialoguePanel's
## rect is fixed/known up front here (not content-driven, no dynamic
## resizing to account for), so this just tweens the real panel's
## offset_bottom directly instead of needing a decoupled ghost frame --
## Margin's clip_contents (see the scene) masks the transient overflow while
## the panel is still small, same job the ghost+clipper pairing does there.
##
## Note DialoguePanel's *live* rect isn't trustworthy for Nameplate's Y
## during this animation -- see _position_nameplate()'s comment for why --
## so nothing here needs to hide/delay/re-correct Nameplate; it just stays
## visible and pinned to the top edge the whole time, appearing to ride
## along as the panel extends downward beneath it.
func _begin_open_animation() -> void:
	if _open_tween:
		_open_tween.kill()
	_dialogue_panel.offset_top = _panel_target_offset_top
	_dialogue_panel.offset_bottom = _panel_target_offset_top + _OPEN_COLLAPSED_HEIGHT
	_open_tween = create_tween()
	_open_tween.tween_property(_dialogue_panel, "offset_bottom", _panel_target_offset_bottom, _OPEN_ANIMATION_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_line_shown(speaker: String, text: String) -> void:
	_nameplate_label.text = _resolve_display_name(speaker)
	_position_nameplate()
	_full_text = text
	_revealed_chars = 0
	_text_label.text = ""
	_set_active_speaker(speaker)

	var multiplier := Settings.text_speed_multiplier
	if multiplier <= 0.0:
		_is_revealing = false
		_finish_reveal()
		return

	_is_revealing = true
	_reveal_timer.wait_time = _REVEAL_SECONDS_PER_CHAR * multiplier
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
				char_entry.label.text = "%s (%s)" % [_resolve_display_name(instruction.character), instruction.expression]
		"STAGE_NAMEPLATE":
			# Stored, not applied immediately -- _on_line_shown() re-measures
			# the nameplate against the *new* speaker's text right before it
			# appears, so a `nameplate <pos>` line ahead of a speaker line
			# never sizes/positions against the previous line's stale text.
			_nameplate_position = instruction.position


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
	_advance_or_finish_reveal()


## Handled here (not _unhandled_input) so consuming "select" reliably stops
## it from also reaching MainScene's _unhandled_input interact handler --
## _input always runs before any _unhandled_input, regardless of node tree
## order between this CanvasLayer and the main scene. Keeps dialogue
## advance-able from keyboard/gamepad, not just mouse clicks, matching the
## project's action-based-input convention (scripts/autoload/game_input.gd).
func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("select"):
		return
	get_viewport().set_input_as_handled()
	_advance_or_finish_reveal()


func _advance_or_finish_reveal() -> void:
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
	label.text = _resolve_display_name(character_name)
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


## Snaps Nameplate to one of five horizontal slots along DialoguePanel's top
## border, straddling it -- half above, half below -- so it reads as a tag
## clipped onto the frame rather than a floating label. Re-run on every line
## (not just when the position changes) since it also re-measures against
## whatever text _nameplate_label was just given.
##
## Y is computed from _panel_target_offset_top (the panel's authored,
## never-animated top edge), not DialoguePanel's *live* rect -- during the
## opening animation's collapsed phase, DialoguePanel's grow_vertical =
## GROW_DIRECTION_BEGIN forcibly shoves its actual rect's top edge upward to
## fit content whose real minimum height exceeds the collapsed height, which
## would otherwise make Nameplate render at the wrong spot (and, briefly,
## visibly jump once the shove stops) for the whole animation. The target
## offset is authoritative and never affected by that transient shove, so
## computing straight from it keeps Nameplate correctly pinned to the top
## border from the very first frame, appearing to ride along as the panel
## extends downward beneath it rather than needing to hide/catch up. X still
## reads from the live rect (position.x/size.x) since only vertical growth
## is ever forced this way.
func _position_nameplate() -> void:
	_nameplate.reset_size()
	var nameplate_size := _nameplate.size
	var panel_rect := _dialogue_panel.get_rect()
	var fraction: float = _NAMEPLATE_POSITIONS.get(_nameplate_position, _NAMEPLATE_POSITIONS[_DEFAULT_NAMEPLATE_POSITION])
	var center_x := panel_rect.position.x + panel_rect.size.x * fraction
	var x := center_x - nameplate_size.x * 0.5
	var target_top_y := _dialogue_panel.get_viewport_rect().size.y + _panel_target_offset_top
	var y := target_top_y - nameplate_size.y * 0.5
	_nameplate.position = Vector2(x, y)


## Swaps the reserved player id for their actual chosen name; every other
## character id passes through unchanged. Falls back to the literal id if
## the player hasn't named their character yet (e.g. a scene played from a
## throwaway test scaffold with no real save loaded).
func _resolve_display_name(character_id: String) -> String:
	if character_id == _PLAYER_CHARACTER_ID and not PlayerProfile.character_name.is_empty():
		return PlayerProfile.character_name
	return character_id


func _color_for_name(label: String) -> Color:
	var hash_value := label.hash()
	return Color.from_hsv(float(hash_value % 360) / 360.0, 0.35, 0.25)
