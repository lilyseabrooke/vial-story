class_name BrewRecipeRow
extends Button
## One selectable recipe-variant row in BrewMenu's potion list. A toggle button
## in a shared ButtonGroup, so exactly one variant reads as selected at a time
## and the theme's pressed style *is* the selection highlight. The child Labels
## carry their own font colors (the Button's font theming only touches its own
## text), so they're re-tinted to cream on select / cocoa on deselect via the
## `toggled` signal.
##
## Node refs are looked up on demand rather than cached via @onready — see the
## note in ingredient_chip.gd; BrewMenu populates rows while still detached.

var _brewable := false


func populate(method_name: String, brewable: bool, slot_index: int) -> void:
	_brewable = brewable

	var method_label: Label = $Margin/HBox/MethodLabel
	method_label.text = method_name

	var badge: PanelContainer = $Margin/HBox/SlotBadge
	badge.visible = slot_index >= 0
	if slot_index >= 0:
		var badge_label: Label = $Margin/HBox/SlotBadge/SlotLabel
		badge_label.text = str(slot_index + 1)

	tooltip_text = "Ready to brew now." if brewable else "You're missing some ingredients."

	if not toggled.is_connected(_apply_colors):
		toggled.connect(_apply_colors)
	_apply_colors(button_pressed)


## Green "●" when brewable, hollow "○" when not; the method name dims when the
## variant can't be brewed. On a selected (pressed) row everything shifts to
## cream so it stays legible over the dark pressed stylebox.
func _apply_colors(selected: bool) -> void:
	var dot: Label = $Margin/HBox/StatusDot
	var method_label: Label = $Margin/HBox/MethodLabel

	dot.text = "●" if _brewable else "○"
	if _brewable:
		dot.add_theme_color_override("font_color", UiPalette.TEXT_ON_DARK if selected else UiPalette.SUCCESS)
	else:
		dot.add_theme_color_override("font_color", UiPalette.TEXT_ON_DARK if selected else UiPalette.TEXT_MUTED)

	method_label.add_theme_color_override("font_color", UiPalette.TEXT_ON_DARK if selected else UiPalette.TEXT_PRIMARY)
	method_label.modulate = Color(1, 1, 1, 1) if _brewable else Color(1, 1, 1, 0.65)
