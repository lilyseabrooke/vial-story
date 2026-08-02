class_name CurseInventoryWindow
extends PanelContainer
## The player's ingredient picker for a curse dispel, shown as its own small
## framed window beside the curse panel — same "detached window riding
## alongside a MenuScene panel" pattern as PantryWindow/BrewMenu. Split out
## from CursePanel because a single window holding the description,
## requirements, tray, *and* a full inventory grid ran tall enough to clip
## off the top of the screen.
##
## Unlike PantryWindow (pure display), this grid is clickable: each cell is
## an ItemSlot wrapped in a Button (same trick as GameMenu's Shop grid), and
## pressing one emits slot_pressed so CursePanel can move that ingredient
## into its tray. GameHud owns both this and CursePanel and wires the two
## together (see toggle_curse_menu()).

signal slot_pressed(ingredient_id: String)

const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")
const GRID_COLUMNS := 2
const SCROLL_HEIGHT := 480

## ItemSlot.tscn's own custom_minimum_size.x — mirrored here same as
## PantryWindow.ITEM_SLOT_WIDTH, since it's a scene property, not something
## the script exposes.
const ITEM_SLOT_WIDTH := 72

var _grid: GridContainer


func build() -> void:
	theme_type_variation = &"FramedPanel"

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var title := Label.new()
	title.theme_type_variation = &"SubheadingLabel"
	title.text = "Your Ingredients"
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, SCROLL_HEIGHT)
	vbox.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_grid)


## `tray_ids` is CursePanel's current (non-empty-slot) tray contents — an
## ingredient's available count here is its owned count minus however many
## copies are already sitting in the tray, and the whole grid disables once
## the tray is full, same rules the old single-window grid enforced.
func refresh(tray_ids: Array[String], tray_capacity: int) -> void:
	for child in _grid.get_children():
		child.queue_free()

	var tray_full := tray_ids.size() >= tray_capacity
	var any := false
	for ingredient in ContentRegistry.ingredients:
		var available := Inventory.ingredient_count(ingredient.id) - tray_ids.count(ingredient.id)
		if available <= 0:
			continue
		any = true

		var item_slot: ItemSlot = ITEM_SLOT_SCENE.instantiate()
		var type_label := "%s Ingredient" % IngredientDef.Category.keys()[ingredient.category].capitalize()
		item_slot.populate_item(ingredient.display_name, "", type_label, available,
			IngredientDef.CATEGORY_COLORS[ingredient.category], ingredient.icon, ingredient.description)

		var cell := Button.new()
		cell.custom_minimum_size = item_slot.custom_minimum_size
		cell.disabled = tray_full
		cell.add_child(item_slot)
		item_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.pressed.connect(func() -> void: slot_pressed.emit(ingredient.id))
		_grid.add_child(cell)

	if not any:
		var empty := Label.new()
		empty.theme_type_variation = &"CaptionLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.custom_minimum_size = Vector2(ITEM_SLOT_WIDTH * GRID_COLUMNS, 0)
		empty.text = "Nothing left to offer — buy or grow some ingredients first."
		_grid.add_child(empty)
