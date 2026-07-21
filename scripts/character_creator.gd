class_name CharacterCreator
extends CanvasLayer
## New-game character creation screen: name, pronouns, House, shop-location
## origin, starting skill point allocation, and an HSV color for the
## player's placeholder rectangle. See docs/design/systems.md, system 14
## (save/load) and system 6 (skills).
##
## Built ad hoc in code, same as scripts/menu_scene.gd and scripts/hud.gd (no
## .tscn, no shared content base class). Doesn't touch SaveManager/
## PlayerProfile itself — it just emits `confirmed` with the collected
## choices and lets the caller decide what to do with them, so it stays
## reusable from a future "New Game" menu button without rewiring internals.
##
## Skill allocation: STARTING_ALLOCATION_POINTS points spread freely across
## Skills.STARTING_ALLOCATABLE_SKILL_IDS (max STARTING_ALLOCATION_MAX_PER_SKILL
## each), plus a fixed STARTING_ORIGIN_SKILL_POINTS bonus in whichever
## ingredient skill the chosen shop location favors (Skills.CATEGORY_SKILL_IDS),
## e.g. Raven Canopy (DEMONIC) grants +2 Demonology. The origin bonus is
## informational only here — it isn't spent from the 5 free points and isn't
## user-editable, so it's shown as a plain label that updates alongside the
## shop-location flavor text.

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
var _origin_skill_label: Label
var _hue_slider: HSlider
var _sat_slider: HSlider
var _val_slider: HSlider
var _color_swatch: ColorRect
var _confirm_button: Button

var _skill_allocations: Dictionary = {}  # skill_id -> int, keys from Skills.STARTING_ALLOCATABLE_SKILL_IDS
var _skill_points_label: Label
var _skill_value_labels: Dictionary = {}  # skill_id -> Label
var _skill_minus_buttons: Dictionary = {}  # skill_id -> Button
var _skill_plus_buttons: Dictionary = {}  # skill_id -> Button


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

	_origin_skill_label = Label.new()
	vbox.add_child(_origin_skill_label)
	_on_shop_location_selected(0)

	vbox.add_child(HSeparator.new())

	_build_skills_section(vbox)

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

	var origin_skill_id := Skills.skill_id_for_category(location_def.ingredient_category)
	var origin_def := Skills.get_def(origin_skill_id)
	var origin_display_name: String = origin_def.display_name if origin_def != null else origin_skill_id
	_origin_skill_label.text = "Shop origin bonus: +%d %s" % [
		Skills.STARTING_ORIGIN_SKILL_POINTS, origin_display_name
	]


func _on_name_changed(new_text: String) -> void:
	_update_confirm_enabled(new_text)


func _update_confirm_enabled(name_text: String = "") -> void:
	if _confirm_button == null:
		return  # skills section builds (and refreshes) before the confirm button exists
	var effective_name := name_text if not name_text.is_empty() else _name_edit.text
	_confirm_button.disabled = (
		effective_name.strip_edges().is_empty() or _points_remaining() != 0
	)


# ---------------------------------------------------------------------------
# Skill allocation
# ---------------------------------------------------------------------------

func _build_skills_section(parent: VBoxContainer) -> void:
	var heading := Label.new()
	heading.text = "Skills"
	parent.add_child(heading)

	_skill_points_label = Label.new()
	parent.add_child(_skill_points_label)

	for skill_id in Skills.STARTING_ALLOCATABLE_SKILL_IDS:
		_skill_allocations[skill_id] = 0
		parent.add_child(_build_skill_row(skill_id))

	_refresh_skill_ui()


func _build_skill_row(skill_id: String) -> HBoxContainer:
	var def := Skills.get_def(skill_id)
	var display_name: String = def.display_name if def != null else skill_id

	var row := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = display_name
	name_label.custom_minimum_size = Vector2(120, 0)
	row.add_child(name_label)

	var minus_button := Button.new()
	minus_button.text = "-"
	minus_button.pressed.connect(_on_skill_minus_pressed.bind(skill_id))
	row.add_child(minus_button)
	_skill_minus_buttons[skill_id] = minus_button

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(24, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	_skill_value_labels[skill_id] = value_label

	var plus_button := Button.new()
	plus_button.text = "+"
	plus_button.pressed.connect(_on_skill_plus_pressed.bind(skill_id))
	row.add_child(plus_button)
	_skill_plus_buttons[skill_id] = plus_button

	return row


func _on_skill_minus_pressed(skill_id: String) -> void:
	if _skill_allocations[skill_id] <= 0:
		return
	_skill_allocations[skill_id] -= 1
	_refresh_skill_ui()


func _on_skill_plus_pressed(skill_id: String) -> void:
	if _skill_allocations[skill_id] >= Skills.STARTING_ALLOCATION_MAX_PER_SKILL:
		return
	if _points_remaining() <= 0:
		return
	_skill_allocations[skill_id] += 1
	_refresh_skill_ui()


func _points_remaining() -> int:
	var spent := 0
	for skill_id in _skill_allocations:
		spent += _skill_allocations[skill_id]
	return Skills.STARTING_ALLOCATION_POINTS - spent


func _refresh_skill_ui() -> void:
	var remaining := _points_remaining()
	_skill_points_label.text = "Points remaining: %d" % remaining

	for skill_id in _skill_allocations:
		var points: int = _skill_allocations[skill_id]
		_skill_value_labels[skill_id].text = str(points)
		_skill_minus_buttons[skill_id].disabled = points <= 0
		_skill_plus_buttons[skill_id].disabled = (
			points >= Skills.STARTING_ALLOCATION_MAX_PER_SKILL or remaining <= 0
		)

	_update_confirm_enabled()


func _on_confirm_pressed() -> void:
	var house_def: HouseDef = ContentRegistry.houses[_house_option.selected]
	var location_def: ShopLocationDef = ContentRegistry.shop_locations[_shop_location_option.selected]
	var pronoun_value: String = PRONOUN_OPTIONS[_pronoun_option.selected].value

	var skill_allocations := _skill_allocations.duplicate()
	var origin_skill_id := Skills.skill_id_for_category(location_def.ingredient_category)
	skill_allocations[origin_skill_id] = (
		skill_allocations.get(origin_skill_id, 0) + Skills.STARTING_ORIGIN_SKILL_POINTS
	)

	confirmed.emit({
		"character_name": _name_edit.text.strip_edges(),
		"pronouns": pronoun_value,
		"house_id": house_def.id,
		"shop_origin": location_def.id,
		"player_color": _current_color(),
		"skill_allocations": skill_allocations,
	})
