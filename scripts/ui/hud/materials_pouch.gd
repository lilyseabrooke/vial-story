class_name MaterialsPouch
extends PanelContainer
## Top-right HUD card (under the almanac): the Materials currency tracker as a
## coin-pouch pill. Replaces hud.gd's plain materials label; the count pulses
## briefly when it changes. The coin is a gold "●" glyph fallback (same
## degrade-to-tint convention as the item slots) until a pouch icon is drawn.

var _count: Label
var _last_amount := -1


func build() -> void:
	theme_type_variation = &"SmallFramedPanel"
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	var caption := Label.new()
	caption.text = "Materials"
	caption.theme_type_variation = &"CaptionLabel"
	vbox.add_child(caption)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vbox.add_child(row)

	var coin := Label.new()
	coin.text = "●"
	coin.add_theme_color_override("font_color", UiPalette.GOLD)
	coin.add_theme_font_size_override("font_size", 18)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(coin)

	_count = Label.new()
	_count.theme_type_variation = &"NumericLabel"
	row.add_child(_count)


func set_amount(amount: int) -> void:
	_count.text = str(amount)
	if _last_amount != -1 and amount != _last_amount and is_inside_tree():
		_pulse()
	_last_amount = amount


func _pulse() -> void:
	_count.pivot_offset = _count.size * 0.5
	var tween := create_tween()
	tween.tween_property(_count, "scale", Vector2(1.25, 1.25), 0.08)
	tween.tween_property(_count, "scale", Vector2.ONE, 0.12)
