class_name IngredientChip
extends VBoxContainer
## Icon + count cell used by the pantry window and a recipe's required-ingredient
## chips. Frameless (just a stacked icon/count/subtitle) — the surrounding
## window supplies the only frame. Falls back to a tinted "●" glyph when the
## underlying ingredient has no icon art yet (same graceful degradation as
## ItemSlot). The count/subtitle text is tinted by an `accent` the caller passes
## so a requirement can go red when the player is short.
##
## Node refs are looked up on demand rather than cached via @onready: BrewMenu
## and PantryWindow build and populate their trees while still detached from the
## SceneTree, so @onready fields here would never fire and would stay null.

func populate(icon: Texture2D, tint: Color, count_text: String, subtitle: String = "", accent: Color = UiPalette.TEXT_PRIMARY, tooltip: String = "") -> void:
	tooltip_text = tooltip
	_apply_icon(icon, tint)

	var count_label: Label = $CountLabel
	count_label.text = count_text
	count_label.add_theme_color_override("font_color", accent)

	var subtitle_label: Label = $Subtitle
	subtitle_label.text = subtitle
	subtitle_label.visible = subtitle != ""
	subtitle_label.add_theme_color_override("font_color", accent)


func _apply_icon(icon: Texture2D, tint: Color) -> void:
	var icon_rect: TextureRect = $Icon
	var dot: Label = $FallbackDot
	if icon != null:
		icon_rect.texture = icon
		icon_rect.visible = true
		dot.visible = false
	else:
		icon_rect.texture = null
		icon_rect.visible = false
		dot.visible = true
		dot.add_theme_color_override("font_color", tint)
