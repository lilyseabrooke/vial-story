class_name MenuScene
extends CanvasLayer
## Generalized modal menu shell. See docs/design/systems.md, system 1 —
## `Clock.is_paused` is spec'd to be true "during menus/dialogue/minigames";
## this is what actually sets that flag. Callers hand in their own bespoke
## content Control (built the same way the HUD panels already are) and this
## just owns the shared chrome (title, close button, pause on open/close).

signal opened
signal closed

var _panel: PanelContainer
var _title_label: Label
var _body: VBoxContainer
var _current_content: Control = null


func _ready() -> void:
	layer = 10

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_title_label)

	vbox.add_child(HSeparator.new())

	_body = VBoxContainer.new()
	vbox.add_child(_body)

	vbox.add_child(HSeparator.new())

	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.pressed.connect(close)
	vbox.add_child(close_button)


func open(content: Control, title: String) -> void:
	if _current_content == content and _panel.visible:
		return
	if _current_content != null:
		_body.remove_child(_current_content)
	_current_content = content
	_body.add_child(content)
	content.visible = true
	_title_label.text = title
	_panel.visible = true
	Clock.is_paused = true
	opened.emit()


func close() -> void:
	if not _panel.visible:
		return
	if _current_content != null:
		_body.remove_child(_current_content)
		_current_content = null
	_panel.visible = false
	Clock.is_paused = false
	closed.emit()
	SceneDirector.recheck()


func is_open() -> bool:
	return _panel.visible


func has_content(content: Control) -> bool:
	return _current_content == content
