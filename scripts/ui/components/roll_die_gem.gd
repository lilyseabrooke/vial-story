class_name RollDieGem
extends Control
## One d10 face in RollDisplay's dice row -- a drawn diamond "gem" (no art
## needed, reads at any resolution, same reasoning as message_bottle_icon.gd)
## with its rolled value centered on top. Green on a natural 10, red on a
## natural 1, parchment otherwise -- one of RollDisplay's two pass/fail
## signals (the other being roll_pip_gauge.gd).
##
## The value label overrides NumericLabel's default font size down to
## VALUE_FONT_SIZE -- the diamond's usable interior (the inscribed square,
## smaller than the gem's own bounding box) is narrower than a two-digit "10"
## renders at full NumericLabel size, which bled the digits out past the
## diamond's edges (and, at the box's actual on-screen size, past the gem
## entirely).

const VALUE_FONT_SIZE := 16

var _value: int = 0
var _fill_color: Color = UiPalette.CREAM_PAGE
var _value_label: Label


func _ready() -> void:
	_value_label = Label.new()
	_value_label.theme_type_variation = &"NumericLabel"
	_value_label.add_theme_font_size_override("font_size", VALUE_FONT_SIZE)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_value_label)


func set_value(natural_value: int) -> void:
	_value = natural_value
	_value_label.text = str(natural_value)
	if natural_value >= 10:
		_fill_color = UiPalette.SUCCESS
	elif natural_value <= 1:
		_fill_color = UiPalette.DANGER
	else:
		_fill_color = UiPalette.CREAM_PAGE
	_value_label.add_theme_color_override("font_color", UiPalette.TEXT_ON_DARK if natural_value <= 1 or natural_value >= 10 else UiPalette.TEXT_PRIMARY)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var diamond := PackedVector2Array([
		Vector2(w * 0.5, 0.0),
		Vector2(w, h * 0.5),
		Vector2(w * 0.5, h),
		Vector2(0.0, h * 0.5),
	])
	draw_colored_polygon(diamond, _fill_color)
	draw_polyline(diamond + PackedVector2Array([diamond[0]]), UiPalette.WARM_WALNUT, 1.5, true)
