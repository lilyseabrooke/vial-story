class_name CharacterCreator
extends CanvasLayer
## New-game character creation screen, a 3-step wizard: (1) name/pronouns/
## House/block color, (2) starting skill point allocation, (3) shop-location
## origin. See docs/design/systems.md, system 14 (save/load) and system 6
## (skills).
##
## Built ad hoc in code, same as scripts/menu_scene.gd and scripts/hud.gd (no
## .tscn, no shared content base class). Doesn't touch SaveManager/
## PlayerProfile itself — it just emits `confirmed` with the collected
## choices and lets the caller decide what to do with them, so it stays
## reusable from a future "New Game" menu button without rewiring internals.
##
## Step 1 (identity) is deliberately small/sparse right now — the block-color
## picker is a stand-in for a future character-appearance step and this
## screen will grow once that lands, it isn't meant to look "finished" today.
## House is a row of placeholder tiles (HouseDef has no icon field, and no
## natural category to tint by like shop locations, so each House's tint is
## hand-authored on its own HouseDef.placeholder_color) rather than a
## dropdown, same tile convention as the shop-location grid in step 3.
##
## Step 2 (skills): Skills.STARTING_ALLOCATION_POINTS points spread freely
## across Skills.STARTING_ALLOCATABLE_SKILL_IDS (max
## Skills.STARTING_ALLOCATION_MAX_PER_SKILL each).
##
## Step 3 (shop location): a 3x2 grid of toggle buttons, one per
## ContentRegistry.shop_locations entry, each with a placeholder color-swatch
## icon (no ShopLocationDef.icon field exists yet) tinted via
## IngredientDef.CATEGORY_COLORS by the location's ingredient_category —
## standing in for real per-location art later, same "degrade to a tinted
## placeholder" convention as scenes/ui/components/*. Picking a location also
## previews the fixed Skills.STARTING_ORIGIN_SKILL_POINTS bonus it grants via
## Skills.skill_id_for_category(), e.g. Raven Canopy (DEMONIC) -> +2 Demonology.

signal confirmed(data: Dictionary)

const PRONOUN_OPTIONS := [
	{"label": "She/Her", "value": "she_her"},
	{"label": "He/Him", "value": "he_him"},
	{"label": "They/Them", "value": "they_them"},
]

const SHOP_LOCATION_GRID_COLUMNS := 3
const TILE_ICON_SIZE := 48

var _step_index: int = 0
var _steps: Array[Control] = []
var _back_button: Button
var _next_button: Button

# Step 1: identity
var _name_edit: LineEdit
var _pronoun_option: OptionButton
var _house_group := ButtonGroup.new()
var _selected_house_index: int = 0
var _hue_slider: HSlider
var _sat_slider: HSlider
var _val_slider: HSlider
var _color_swatch: ColorRect

# Step 2: skills
var _skill_allocations: Dictionary = {}  # skill_id -> int, keys from Skills.STARTING_ALLOCATABLE_SKILL_IDS
var _skill_points_label: Label
var _skill_value_labels: Dictionary = {}  # skill_id -> Label
var _skill_minus_buttons: Dictionary = {}  # skill_id -> Button
var _skill_plus_buttons: Dictionary = {}  # skill_id -> Button

# Step 3: shop location
var _shop_location_group := ButtonGroup.new()
var _shop_location_flavor_label: Label
var _origin_skill_label: Label
var _selected_shop_location_index: int = 0


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

	_steps = [_build_identity_step(), _build_skills_step(), _build_shop_location_step()]
	for step in _steps:
		vbox.add_child(step)

	vbox.add_child(HSeparator.new())

	var nav := HBoxContainer.new()
	vbox.add_child(nav)

	_back_button = Button.new()
	_back_button.text = "Back"
	_back_button.pressed.connect(_on_back_pressed)
	nav.add_child(_back_button)

	_next_button = Button.new()
	_next_button.pressed.connect(_on_next_pressed)
	nav.add_child(_next_button)

	_update_step_ui()


# ---------------------------------------------------------------------------
# Step navigation
# ---------------------------------------------------------------------------

func _on_back_pressed() -> void:
	if _step_index <= 0:
		return
	_step_index -= 1
	_update_step_ui()


func _on_next_pressed() -> void:
	if _step_index >= _steps.size() - 1:
		_on_confirm_pressed()
		return
	_step_index += 1
	_update_step_ui()


func _update_step_ui() -> void:
	for i in _steps.size():
		_steps[i].visible = i == _step_index
	_back_button.visible = _step_index > 0
	_next_button.text = "Confirm" if _step_index == _steps.size() - 1 else "Next"
	_next_button.disabled = not _step_is_valid(_step_index)


func _step_is_valid(step_index: int) -> bool:
	match step_index:
		0:
			return not _name_edit.text.strip_edges().is_empty()
		1:
			return _points_remaining() == 0
		_:
			return true


# ---------------------------------------------------------------------------
# Step 1: identity
# ---------------------------------------------------------------------------

func _build_identity_step() -> VBoxContainer:
	var step := VBoxContainer.new()

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name"
	_name_edit.text_changed.connect(_on_name_changed)
	step.add_child(_name_edit)

	_pronoun_option = OptionButton.new()
	for entry in PRONOUN_OPTIONS:
		_pronoun_option.add_item(entry.label)
	step.add_child(_pronoun_option)

	var house_row := HBoxContainer.new()
	step.add_child(house_row)
	for i in ContentRegistry.houses.size():
		house_row.add_child(_build_house_tile(i))

	step.add_child(HSeparator.new())

	var appearance_note := Label.new()
	appearance_note.text = "Full character appearance customization coming soon — pick a color for now."
	appearance_note.modulate = Color(1, 1, 1, 0.6)
	appearance_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	step.add_child(appearance_note)

	_color_swatch = ColorRect.new()
	_color_swatch.custom_minimum_size = Vector2(48, 48)

	_hue_slider = _add_color_slider(step, "Hue")
	_sat_slider = _add_color_slider(step, "Saturation")
	_val_slider = _add_color_slider(step, "Value")
	_sat_slider.value = 1.0
	_val_slider.value = 1.0

	step.add_child(_color_swatch)
	_update_color_swatch()

	return step


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


func _on_name_changed(_new_text: String) -> void:
	if _step_index == 0:
		_next_button.disabled = not _step_is_valid(0)


func _build_house_tile(index: int) -> Button:
	var house_def: HouseDef = ContentRegistry.houses[index]

	var button := Button.new()
	button.custom_minimum_size = Vector2(80, 80)
	button.toggle_mode = true
	button.button_group = _house_group
	button.button_pressed = index == 0
	button.text = house_def.display_name
	button.icon = _placeholder_icon(house_def.placeholder_color)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_selected_house_index = index
	)
	return button


# ---------------------------------------------------------------------------
# Step 2: skill allocation
# ---------------------------------------------------------------------------

func _build_skills_step() -> VBoxContainer:
	var step := VBoxContainer.new()

	var heading := Label.new()
	heading.text = "Skills"
	step.add_child(heading)

	_skill_points_label = Label.new()
	step.add_child(_skill_points_label)

	for skill_id in Skills.STARTING_ALLOCATABLE_SKILL_IDS:
		_skill_allocations[skill_id] = 0
		step.add_child(_build_skill_row(skill_id))

	_refresh_skill_ui()
	return step


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

	if _step_index == 1:
		_next_button.disabled = not _step_is_valid(1)


# ---------------------------------------------------------------------------
# Step 3: shop location
# ---------------------------------------------------------------------------

func _build_shop_location_step() -> VBoxContainer:
	var step := VBoxContainer.new()

	var heading := Label.new()
	heading.text = "Shop Location"
	step.add_child(heading)

	var grid := GridContainer.new()
	grid.columns = SHOP_LOCATION_GRID_COLUMNS
	step.add_child(grid)

	for i in ContentRegistry.shop_locations.size():
		grid.add_child(_build_shop_location_tile(i))

	_shop_location_flavor_label = Label.new()
	_shop_location_flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	step.add_child(_shop_location_flavor_label)

	_origin_skill_label = Label.new()
	step.add_child(_origin_skill_label)

	_on_shop_location_selected(0)
	return step


func _build_shop_location_tile(index: int) -> Button:
	var location_def: ShopLocationDef = ContentRegistry.shop_locations[index]

	var button := Button.new()
	button.custom_minimum_size = Vector2(96, 96)
	button.toggle_mode = true
	button.button_group = _shop_location_group
	button.button_pressed = index == 0
	button.text = location_def.display_name
	button.icon = _placeholder_icon(
		IngredientDef.CATEGORY_COLORS.get(location_def.ingredient_category, Color.GRAY)
	)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_shop_location_selected(index)
	)
	return button


func _placeholder_icon(color: Color) -> ImageTexture:
	var image := Image.create(TILE_ICON_SIZE, TILE_ICON_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _on_shop_location_selected(index: int) -> void:
	_selected_shop_location_index = index
	var location_def: ShopLocationDef = ContentRegistry.shop_locations[index]
	_shop_location_flavor_label.text = location_def.flavor_text

	var origin_skill_id := Skills.skill_id_for_category(location_def.ingredient_category)
	var origin_def := Skills.get_def(origin_skill_id)
	var origin_display_name: String = origin_def.display_name if origin_def != null else origin_skill_id
	_origin_skill_label.text = "Shop origin bonus: +%d %s" % [
		Skills.STARTING_ORIGIN_SKILL_POINTS, origin_display_name
	]


# ---------------------------------------------------------------------------
# Confirm
# ---------------------------------------------------------------------------

func _on_confirm_pressed() -> void:
	var house_def: HouseDef = ContentRegistry.houses[_selected_house_index]
	var location_def: ShopLocationDef = ContentRegistry.shop_locations[_selected_shop_location_index]
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
