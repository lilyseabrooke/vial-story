class_name PantryWindow
extends PanelContainer
## The player's pantry, shown as its own small framed window beside the brew
## menu rather than as a strip inside it (keeps the brew window from nesting yet
## another frame). GameHud owns it: shows + refreshes + positions it whenever
## the brew menu opens, and fades it out when that menu closes. Built in code
## like the other HUD panels; frameless IngredientChips wrap into a narrow
## column so the window stays tall-and-thin against the brew window's side.

const INGREDIENT_CHIP_SCENE := preload("res://scenes/ui/components/IngredientChip.tscn")

const CONTENT_WIDTH := 118
const SCROLL_HEIGHT := 420

var _flow: HFlowContainer


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
	scroll.custom_minimum_size = Vector2(CONTENT_WIDTH, SCROLL_HEIGHT)
	vbox.add_child(scroll)

	_flow = HFlowContainer.new()
	_flow.custom_minimum_size = Vector2(CONTENT_WIDTH, 0)
	_flow.add_theme_constant_override("h_separation", 6)
	_flow.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_flow)


func refresh() -> void:
	for child in _flow.get_children():
		child.queue_free()

	var any := false
	for ingredient in ContentRegistry.ingredients:
		var count := Inventory.ingredient_count(ingredient.id)
		if count <= 0:
			continue
		any = true
		var chip := INGREDIENT_CHIP_SCENE.instantiate()
		_flow.add_child(chip)
		chip.populate(ingredient.icon, IngredientDef.CATEGORY_COLORS[ingredient.category],
			"×%d" % count, "", UiPalette.TEXT_PRIMARY, ingredient.display_name)

	if not any:
		var empty := Label.new()
		empty.theme_type_variation = &"CaptionLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.custom_minimum_size = Vector2(CONTENT_WIDTH, 0)
		empty.text = "Empty — buy or grow some ingredients first."
		_flow.add_child(empty)
