class_name CustomerEntry
extends VBoxContainer
## One simulated customer's visit in GameMenu's Shop tab "Recent Customers"
## list. See Shop.log_visit() for where the record Dictionary this
## populate()s from is built, and docs/design/systems.md system 5.
##
## Node refs are resolved inside populate() rather than @onready: see the
## note in item_slot.gd — GameMenu builds its tab tree detached from the
## SceneTree, so _ready() would never fire here.

func populate(record: Dictionary, tint: Color) -> void:
	var name_label: Label = $HeaderRow/NameColumn/NameLabel
	name_label.text = record.full_name
	name_label.add_theme_color_override("font_color", tint)

	var subtitle_label: Label = $HeaderRow/NameColumn/SubtitleLabel
	subtitle_label.text = "%s • %s" % [record.occupation, record.magic_discipline]

	var portrait_rect: TextureRect = $HeaderRow/Portrait
	portrait_rect.texture = record.portrait
	var border: ColorRect = $HeaderRow/Portrait/Border
	border.visible = record.portrait == null
	border.color = tint

	var wanted_text := "something themed around \"%s\"" % record.wanted_tag if record.wanted_tag != "" else "nothing in particular"
	var traits_label: Label = $TraitsLabel
	traits_label.text = "Wanted %s — %s, %s haggler, cares %s about potency, %s about ease" % [
		wanted_text, record.budget_label, record.deal_savvy_label,
		record.potency_interest_label, record.ease_interest_label,
	]

	var description_label: Label = $DescriptionLabel
	if record.purchase_lines.is_empty():
		description_label.text = "Left empty-handed."
		description_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	else:
		description_label.text = "Bought %s — %d Materials total." % [
			", ".join(record.purchase_lines), record.total_spent,
		]
		description_label.add_theme_color_override("font_color", UiPalette.SUCCESS)
