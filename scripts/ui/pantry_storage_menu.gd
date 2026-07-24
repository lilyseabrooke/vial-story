class_name PantryStorageMenu
extends HBoxContainer
## MenuScene content opened by PantryInteractable — two columns, "Carried"
## (the player's inventory, each row with a Store button) and "Stored here"
## (the Pantry's contents, each row with a Take button). See
## docs/design/systems.md, system 4. Built entirely in code, same
## plain-Buttons-and-IngredientChips convention as AlchemyLabMenu/supply_panel
## — no new component scenes needed.

signal notice(text: String)

const INGREDIENT_CHIP_SCENE := preload("res://scenes/ui/components/IngredientChip.tscn")

const COLUMN_WIDTH := 220
const COLUMN_HEIGHT := 360

var _pantry_id: String = ""
var _carried_list: VBoxContainer
var _stored_list: VBoxContainer


func build() -> void:
	add_theme_constant_override("separation", 16)

	var carried_panel := PanelContainer.new()
	carried_panel.theme_type_variation = &"FramedPanel"
	carried_panel.custom_minimum_size = Vector2(COLUMN_WIDTH, COLUMN_HEIGHT)
	add_child(carried_panel)
	_carried_list = _build_column(carried_panel, "Carried")

	var stored_panel := PanelContainer.new()
	stored_panel.theme_type_variation = &"FramedPanel"
	stored_panel.custom_minimum_size = Vector2(COLUMN_WIDTH, COLUMN_HEIGHT)
	add_child(stored_panel)
	_stored_list = _build_column(stored_panel, "Stored here")

	add_child(MenuKeyNav.new())


func _build_column(panel: PanelContainer, title_text: String) -> VBoxContainer:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	var title := Label.new()
	title.theme_type_variation = &"SubheadingLabel"
	title.text = title_text
	outer.add_child(title)
	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return list


func open_for(pantry_id: String) -> void:
	_pantry_id = pantry_id
	refresh()


func refresh() -> void:
	_rebuild_carried()
	_rebuild_stored()


func _rebuild_carried() -> void:
	for child in _carried_list.get_children():
		child.queue_free()
	var any := false
	for ingredient in ContentRegistry.ingredients:
		var tiers := Inventory.ingredient_tiers(ingredient.id)
		for tier in tiers:
			var count: int = tiers[tier]
			if count <= 0:
				continue
			any = true
			_carried_list.add_child(_build_row(ingredient, tier, count, "Store", _on_store_pressed.bind(ingredient.id, tier)))
	if not any:
		_carried_list.add_child(_empty_label("Nothing carried."))


func _rebuild_stored() -> void:
	for child in _stored_list.get_children():
		child.queue_free()
	var any := false
	if Inventory.get_pantry(_pantry_id) != null:
		for ingredient in ContentRegistry.ingredients:
			var tiers := Inventory.pantry_ingredient_tiers(_pantry_id, ingredient.id)
			for tier in tiers:
				var count: int = tiers[tier]
				if count <= 0:
					continue
				any = true
				_stored_list.add_child(_build_row(ingredient, tier, count, "Take", _on_take_pressed.bind(ingredient.id, tier)))
	if not any:
		_stored_list.add_child(_empty_label("Empty — store some ingredients."))


func _build_row(ingredient: IngredientDef, tier: int, count: int, action_text: String, action: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var chip := INGREDIENT_CHIP_SCENE.instantiate()
	row.add_child(chip)
	var subtitle := IngredientQuality.label(tier) if tier != IngredientQuality.Tier.NORMAL else ""
	var accent := IngredientQuality.color(tier) if tier != IngredientQuality.Tier.NORMAL else UiPalette.TEXT_PRIMARY
	chip.populate(ingredient.icon, IngredientDef.CATEGORY_COLORS[ingredient.category],
		"×%d" % count, subtitle, accent, ingredient.display_name)

	var button := Button.new()
	button.text = action_text
	button.pressed.connect(action)
	row.add_child(button)

	return row


func _empty_label(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"CaptionLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size = Vector2(COLUMN_WIDTH - 32, 0)
	label.text = text
	return label


func _on_store_pressed(ingredient_id: String, tier: int) -> void:
	if not Inventory.deposit_to_pantry(_pantry_id, ingredient_id, tier, 1):
		notice.emit("Couldn't store that.")
	refresh()


func _on_take_pressed(ingredient_id: String, tier: int) -> void:
	if not Inventory.withdraw_from_pantry(_pantry_id, ingredient_id, tier, 1):
		notice.emit("Couldn't take that.")
	refresh()
