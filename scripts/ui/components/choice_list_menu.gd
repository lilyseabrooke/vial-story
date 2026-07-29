class_name ChoiceListMenu
extends VBoxContainer
## Generic "array of options -> buttons -> selected id" list, replacing the
## same shape independently built by the class-effort picker (hud.gd's
## class_panel) and ArtStudioPicker. This owns only the option buttons + a
## `selected(id)` signal -- like BrewMenu's recipe list, the host Control
## still owns its own hint text/cancel button/title and its own MenuKeyNav
## (added as the host's child per MenuKeyNav's own convention, which collects
## every descendant control including this list's buttons). See
## docs/engine_roadmap.md, Phase 7.

signal selected(id: String)


func populate(options: Array[ChoiceOption]) -> void:
	for child in get_children():
		child.queue_free()
	for option in options:
		var button := Button.new()
		button.text = option.label
		button.disabled = not option.enabled
		if not option.description.is_empty():
			button.tooltip_text = option.description
		button.pressed.connect(func() -> void: selected.emit(option.id))
		add_child(button)
