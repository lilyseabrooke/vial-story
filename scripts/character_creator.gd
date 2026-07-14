class_name CharacterCreator
extends CanvasLayer
## New-game character creation screen: name, pronouns, House, shop-location
## origin, and an HSV color for the player's placeholder rectangle. See
## docs/design/systems.md, system 14.
##
## Built ad hoc in code, same as scripts/menu_scene.gd and scripts/hud.gd (no
## .tscn, no shared content base class). Doesn't touch SaveManager/
## PlayerProfile itself — it just emits `confirmed` with the collected
## choices and lets the caller decide what to do with them, so it stays
## reusable from a future "New Game" menu button without rewiring internals.

signal confirmed(data: Dictionary)

const PRONOUN_OPTIONS := [
	{"label": "She/Her", "value": "she_her"},
	{"label": "He/Him", "value": "he_him"},
	{"label": "They/Them", "value": "they_them"},
]

var _name_edit: LineEdit
var _pronoun_option: OptionButton
var _house_option: OptionButton
var _shop_location_option: OptionButton
var _shop_location_flavor_label: Label
var _hue_slider: HSlider
var _sat_slider: HSlider
var _val_slider: HSlider
var _color_swatch: ColorRect
var _confirm_button: Button


func build() -> void:
	layer = 10

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Create Your Character"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name"
	_name_edit.text_changed.connect(_on_name_changed)
	vbox.add_child(_name_edit)

	_pronoun_option = OptionButton.new()
	for entry in PRONOUN_OPTIONS:
		_pronoun_option.add_item(entry.label)
	vbox.add_child(_pronoun_option)

	_house_option = OptionButton.new()
	for house_def in ContentRegistry.houses:
		_house_option.add_item(house_def.display_name)
	vbox.add_child(_house_option)

	_shop_location_option = OptionButton.new()
	for location_def in ContentRegistry.shop_locations:
		_shop_location_option.add_item(location_def.display_name)
	_shop_location_option.item_selected.connect(_on_shop_location_selected)
	vbox.add_child(_shop_location_option)

	_shop_location_flavor_label = Label.new()
	vbox.add_child(_shop_location_flavor_label)
	_on_shop_location_selected(0)

	vbox.add_child(HSeparator.new())

	_color_swatch = ColorRect.new()
	_color_swatch.custom_minimum_size = Vector2(48, 48)

	_hue_slider = _add_color_slider(vbox, "Hue")
	_sat_slider = _add_color_slider(vbox, "Saturation")
	_val_slider = _add_color_slider(vbox, "Value")
	_sat_slider.value = 1.0
	_val_slider.value = 1.0

	vbox.add_child(_color_swatch)
	_update_color_swatch()

	vbox.add_child(HSeparator.new())

	_confirm_button = Button.new()
	_confirm_button.text = "Confirm"
	_confirm_button.disabled = true
	_confirm_button.pressed.connect(_on_confirm_pressed)
	vbox.add_child(_confirm_button)


func _add_color_slider(parent: VBoxContainer, label_text: String) -> HSlider:
	var caption := Label.new()
	caption.text = label_text
	parent.add_child(caption)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(200, 0)
	slider.value_changed.connect(func(_value: float) -> void: _update_color_swatch())
	parent.add_child(slider)
	return slider


func _update_color_swatch() -> void:
	_color_swatch.color = _current_color()


func _current_color() -> Color:
	return Color.from_hsv(_hue_slider.value, _sat_slider.value, _val_slider.value)


func _on_shop_location_selected(index: int) -> void:
	var location_def: ShopLocationDef = ContentRegistry.shop_locations[index]
	_shop_location_flavor_label.text = location_def.flavor_text


func _on_name_changed(new_text: String) -> void:
	_confirm_button.disabled = new_text.strip_edges().is_empty()


func _on_confirm_pressed() -> void:
	var house_def: HouseDef = ContentRegistry.houses[_house_option.selected]
	var location_def: ShopLocationDef = ContentRegistry.shop_locations[_shop_location_option.selected]
	var pronoun_value: String = PRONOUN_OPTIONS[_pronoun_option.selected].value

	confirmed.emit({
		"character_name": _name_edit.text.strip_edges(),
		"pronouns": pronoun_value,
		"house_id": house_def.id,
		"shop_origin": location_def.id,
		"player_color": _current_color(),
	})
