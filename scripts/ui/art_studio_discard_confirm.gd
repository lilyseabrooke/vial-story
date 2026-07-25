class_name ArtStudioDiscardConfirm
extends VBoxContainer
## MenuScene content opened by ArtStudioInteractable on a select-press mid
## WORKING — asks whether to throw away the current piece's progress, so a
## player who realizes they don't have time for it isn't stuck grinding it
## out. See docs/design/systems.md, the Art Studio / Creativity System
## section. No general-purpose ConfirmationDialog exists elsewhere in the
## codebase, so this is a small dedicated panel rather than a shared one.

signal discard_confirmed(studio_id: String)
signal kept(studio_id: String)

var _studio_id: String = ""
var _message_label: Label


func build() -> void:
	add_theme_constant_override("separation", 8)

	_message_label = Label.new()
	_message_label.theme_type_variation = &"CaptionLabel"
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_message_label.custom_minimum_size = Vector2(320, 0)
	add_child(_message_label)
	add_child(HSeparator.new())

	var discard_button := Button.new()
	discard_button.text = "Discard progress"
	discard_button.pressed.connect(func() -> void: discard_confirmed.emit(_studio_id))
	add_child(discard_button)

	var keep_button := Button.new()
	keep_button.text = "Keep working"
	keep_button.pressed.connect(func() -> void: kept.emit(_studio_id))
	add_child(keep_button)

	add_child(MenuKeyNav.new())


func open_for(studio_id: String) -> void:
	_studio_id = studio_id
	var job := ArtStudio.get_job(studio_id)
	var def := ContentRegistry.get_inspiration(job.inspiration_id) if job != null else null
	var name := def.display_name if def != null else "this piece"
	_message_label.text = "Discard your progress on %s? This can't be undone." % name
