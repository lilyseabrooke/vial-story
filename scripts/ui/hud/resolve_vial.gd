class_name ResolveVial
extends PanelContainer
## Top-left HUD card: the Resolve meter drawn as a filling potion vial (see
## VialGauge). Replaces hud.gd's old ProgressBar + label. update_resolve_meter()
## in hud.gd calls set_values() the same way it used to set bar.value.

var _gauge: VialGauge
var _label: Label


func build() -> void:
	theme_type_variation = &"SmallFramedPanel"
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	var caption := Label.new()
	caption.text = "Resolve"
	caption.theme_type_variation = &"CaptionLabel"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(caption)

	_gauge = VialGauge.new()
	_gauge.custom_minimum_size = Vector2(46, 74)
	_gauge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_gauge)

	_label = Label.new()
	_label.theme_type_variation = &"NumericLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_label)


func set_values(current: int, max_resolve: int, strained: bool) -> void:
	var fraction := float(current) / float(max_resolve) if max_resolve > 0 else 0.0
	_gauge.set_values(fraction, strained)
	_label.text = "%d/%d%s" % [current, max_resolve, "  (strained)" if strained else ""]
	_label.add_theme_color_override("font_color", UiPalette.WARNING if strained else UiPalette.COCOA_INK)
