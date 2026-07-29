class_name ArtStudioPicker
extends VBoxContainer
## MenuScene content opened by ArtStudioInteractable once a gathering-
## inspiration roll offers one or more Inspirations — the hint/cancel chrome
## here, wrapping a shared ChoiceListMenu for the option list itself (same
## primitive GameHud.class_panel uses). See docs/design/systems.md, the Art
## Studio / Creativity System section, and docs/engine_roadmap.md, Phase 7.

signal chosen(studio_id: String, inspiration_id: String)
signal cancelled(studio_id: String)

var _studio_id: String = ""
var _list: ChoiceListMenu


func build() -> void:
	add_theme_constant_override("separation", 8)

	var hint := Label.new()
	hint.theme_type_variation = &"CaptionLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.text = "Inspiration struck — pick a piece to start, or cancel and let it pass."
	add_child(hint)
	add_child(HSeparator.new())

	_list = preload("res://scenes/ui/components/ChoiceListMenu.tscn").instantiate()
	_list.selected.connect(func(inspiration_id: String) -> void: chosen.emit(_studio_id, inspiration_id))
	add_child(_list)

	var cancel_button := Button.new()
	cancel_button.text = "Never mind"
	cancel_button.pressed.connect(func() -> void: cancelled.emit(_studio_id))
	add_child(cancel_button)

	add_child(MenuKeyNav.new())


func open_for(studio_id: String) -> void:
	_studio_id = studio_id
	var options: Array[ChoiceOption] = []
	for inspiration_id in ArtStudio.get_offered_inspirations(studio_id):
		var def := ContentRegistry.get_inspiration(inspiration_id)
		if def == null:
			continue
		options.append(ChoiceOption.make(
			inspiration_id,
			"%s (DC %d, %s)" % [def.display_name, def.dc, _duration_label(def.completion_time)],
			def.description
		))
	_list.populate(options)


func _duration_label(minutes: int) -> String:
	if minutes < 60:
		return "%d min" % minutes
	@warning_ignore("integer_division")
	var hours := minutes / 60
	var remainder := minutes % 60
	return "%dh %dm" % [hours, remainder] if remainder > 0 else "%dh" % hours
