class_name PantryWindow
extends PanelContainer
## The player's pantry, shown as its own small framed window beside the brew
## menu rather than as a strip inside it (keeps the brew window from nesting yet
## another frame). GameHud owns it: shows + refreshes + positions it whenever
## the brew menu opens, and fades it out when that menu closes. Built in code
## like the other HUD panels; a narrow ItemSlot grid keeps the window
## tall-and-thin against the brew window's side.
##
## Uses the same icon-first, quantity-corner-badge ItemSlot component as the
## Satchel/Shop grids in game_menu.gd (see ItemSlot.populate_item()), so a
## pantry stock icon reads identically to the same ingredient in the player's
## inventory — name/category surfaced via hover tooltip rather than always-on
## text.
##
## Shows combined totals, not just carried inventory: once a Pantry
## interactable is linked to the same Alchemy Lab Manager as the open
## station's Alembic, its stock counts as available too (see
## docs/design/systems.md, system 4) — refresh() takes the open station's id
## and reads Brewing.available_ingredient_count() per ingredient, the same
## helper BrewMenu's detail card uses, so both stay in sync.

const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")

const GRID_COLUMNS := 2
const SCROLL_HEIGHT := 640

## ItemSlot.tscn's own custom_minimum_size.x — it's a scene property, not
## something the script exposes, so it's mirrored here (matches the same
## literal in game_menu.gd's Satchel/Shop grid sizing comment).
const ITEM_SLOT_WIDTH := 72

var _grid: GridContainer


func build() -> void:
	theme_type_variation = &"FramedPanel"

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var title := Label.new()
	title.theme_type_variation = &"SubheadingLabel"
	title.text = "Pantry"
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


func refresh(station_id: String = "") -> void:
	for child in _grid.get_children():
		child.queue_free()

	var any := false
	for ingredient in ContentRegistry.ingredients:
		var count := Brewing.available_ingredient_count(station_id, ingredient.id)
		if count <= 0:
			continue
		any = true
		var slot: ItemSlot = ITEM_SLOT_SCENE.instantiate()
		_grid.add_child(slot)
		var type_label := "%s Ingredient" % IngredientDef.Category.keys()[ingredient.category].capitalize()
		slot.populate_item(ingredient.display_name, "", type_label, count,
			IngredientDef.CATEGORY_COLORS[ingredient.category], ingredient.icon)

	if not any:
		var empty := Label.new()
		empty.theme_type_variation = &"CaptionLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.custom_minimum_size = Vector2(ITEM_SLOT_WIDTH * GRID_COLUMNS, 0)
		empty.text = "Empty — buy or grow some ingredients first."
		_grid.add_child(empty)
