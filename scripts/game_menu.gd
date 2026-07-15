class_name GameMenu
extends TabContainer
## The Escape menu's content — a tabbed utility screen. The tab shell itself
## is still built ad hoc in code, same as scripts/hud.gd and
## scripts/menu_scene.gd, but each tab's repeated rows/cells (item slots,
## skill rows, relationship rows, recipe entries, quest entries) are
## scenes/ui/components/*.tscn scenes with a populate() method, instanced
## here rather than built node-by-node inline — see the *_SCENE consts below.
## hud.gd owns one GameMenu instance and hands it to MenuScene the same way
## it always handed over the old flat game-menu VBoxContainer.
##
## Inventory/Skills/Shop/Relationships/Classes/Journal tabs connect directly
## to the autoload signals whose only effect is refreshing their own display —
## consistent with how hud.gd wires up signals whose effect is purely a
## label update. Map is out of scope for the prototype and stays a disabled
## tab.

const GRID_COLUMNS := 8
const GRID_ROWS := 3

const AFFECTION_PER_HEART := 20
const MAX_HEARTS := 5

const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")
const SKILL_ROW_SCENE := preload("res://scenes/ui/components/SkillRow.tscn")
const RELATIONSHIP_ROW_SCENE := preload("res://scenes/ui/components/RelationshipRow.tscn")
const RECIPE_ENTRY_SCENE := preload("res://scenes/ui/components/RecipeEntry.tscn")
const QUEST_ENTRY_SCENE := preload("res://scenes/ui/components/QuestEntry.tscn")

var _inventory_grid: GridContainer
var _skills_list: VBoxContainer
var _shop_grid: GridContainer
var _shop_reputation_label: Label
var _shop_coffers_label: Label
var _relationships_list: VBoxContainer
var _recipes_list: VBoxContainer
var _report_card_label: Label
var _journal_list: VBoxContainer
var _save_status_label: Label


func build() -> void:
	custom_minimum_size = Vector2(560, 400)

	_build_inventory_tab()
	_build_skills_tab()
	_build_shop_tab()
	_build_relationships_tab()
	_build_classes_tab()
	_build_disabled_tab("Map")
	_build_recipes_tab()
	_build_journal_tab()
	_build_settings_tab()

	set_tab_disabled(5, true)  # Map

	Inventory.ingredient_changed.connect(func(_id: String, _qty: int) -> void: update_inventory())
	Inventory.potion_added.connect(func(_id: String, _potency: float, _ease: float) -> void: update_inventory())
	Skills.xp_gained.connect(func(_id: String, _xp: int, _level: int) -> void: update_skills())
	Skills.leveled_up.connect(func(_id: String, _level: int) -> void: update_skills())
	Shop.potion_stocked.connect(func(_id: String, _price: int) -> void: update_shop())
	Shop.potion_sold.connect(func(_id: String, _price: int) -> void: update_shop())
	Shop.coffers_collected.connect(func(_amount: int) -> void: update_shop())
	Economy.upgrade_purchased.connect(func(_id: String) -> void: update_shop())
	LoveInterests.affection_changed.connect(func(_id: String, _amount: int) -> void: update_relationships())
	Academy.attended_class.connect(update_report_card)
	Academy.absence_recorded.connect(func(_absences: int) -> void: update_report_card())
	Academy.exam_graded.connect(func(_passed: bool, _score: float, _strikes: int) -> void: update_report_card())
	QuestManager.quest_started.connect(func(_id: String) -> void: update_journal())
	QuestManager.quest_ready_to_turn_in.connect(func(_id: String) -> void: update_journal())
	QuestManager.quest_completed.connect(func(_id: String) -> void: update_journal())

	update_inventory()
	update_skills()
	update_shop()
	update_relationships()
	update_recipes()
	update_report_card()
	update_journal()


# ---------------------------------------------------------------------------
# Inventory
# ---------------------------------------------------------------------------

func _build_inventory_tab() -> void:
	var root := VBoxContainer.new()
	root.name = "Inventory"
	add_child(root)

	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = GRID_COLUMNS
	root.add_child(_inventory_grid)


func update_inventory() -> void:
	for child in _inventory_grid.get_children():
		child.queue_free()

	var entries: Array[Dictionary] = []
	for ingredient in ContentRegistry.ingredients:
		var count := Inventory.ingredient_count(ingredient.id)
		if count > 0:
			entries.append({"name": ingredient.display_name, "subtitle": "x%d" % count, "color": _color_for_id(ingredient.id), "icon": ingredient.icon})

	var potion_counts: Dictionary = {}
	for potion in Inventory.potions:
		var potion_id: String = potion.potion_id
		potion_counts[potion_id] = potion_counts.get(potion_id, 0) + 1
	for potion_id in potion_counts:
		entries.append({"name": String(potion_id).capitalize(), "subtitle": "x%d" % potion_counts[potion_id], "color": _color_for_id(potion_id), "icon": null})

	for i in GRID_COLUMNS * GRID_ROWS:
		var slot: ItemSlot = ITEM_SLOT_SCENE.instantiate()
		_inventory_grid.add_child(slot)
		if i < entries.size():
			var entry: Dictionary = entries[i]
			slot.populate(entry.name, entry.subtitle, entry.color, entry.icon)
		else:
			slot.clear()


func _color_for_id(id: String) -> Color:
	var hue := float(hash(id) % 360) / 360.0
	return Color.from_hsv(hue, 0.6, 0.9)


# ---------------------------------------------------------------------------
# Skills
# ---------------------------------------------------------------------------

func _build_skills_tab() -> void:
	var root := VBoxContainer.new()
	root.name = "Skills"
	add_child(root)

	_skills_list = VBoxContainer.new()
	root.add_child(_skills_list)


func update_skills() -> void:
	for child in _skills_list.get_children():
		child.queue_free()

	for skill_id in Skills.skill_ids():
		var def := Skills.get_def(skill_id)
		var current_xp := def.xp_per_level - Skills.xp_to_next_level(skill_id) if def.xp_per_level > 0 else 0

		var row: SkillRow = SKILL_ROW_SCENE.instantiate()
		_skills_list.add_child(row)
		row.populate(def.display_name, Skills.level(skill_id), current_xp, def.xp_per_level)


# ---------------------------------------------------------------------------
# Shop
# ---------------------------------------------------------------------------

func _build_shop_tab() -> void:
	var root := VBoxContainer.new()
	root.name = "Shop"
	add_child(root)

	_shop_reputation_label = Label.new()
	root.add_child(_shop_reputation_label)

	_shop_coffers_label = Label.new()
	root.add_child(_shop_coffers_label)

	root.add_child(HSeparator.new())

	_shop_grid = GridContainer.new()
	_shop_grid.columns = GRID_COLUMNS
	root.add_child(_shop_grid)


## Rebuilds the grid at Shop.capacity slots rather than a fixed size, since
## the expanded_stock_shelf upgrade grows capacity from 8 (1 row) to 16 (2
## rows) rather than the Inventory tab's fixed 8x3.
func update_shop() -> void:
	_shop_reputation_label.text = "Reputation: %d" % Shop.reputation
	_shop_coffers_label.text = "Coffers: %d Materials (collect at the shopfront)" % Shop.coffers

	for child in _shop_grid.get_children():
		child.queue_free()

	for i in Shop.capacity:
		var item_slot: ItemSlot = ITEM_SLOT_SCENE.instantiate()
		_shop_grid.add_child(item_slot)
		if i < Shop.slots.size():
			var slot: Dictionary = Shop.slots[i]
			item_slot.populate(String(slot.potion_id).capitalize(), "%d" % slot.price, _color_for_id(slot.potion_id))
		else:
			item_slot.clear()


# ---------------------------------------------------------------------------
# Relationships
# ---------------------------------------------------------------------------

func _build_relationships_tab() -> void:
	var root := VBoxContainer.new()
	root.name = "Relationships"
	add_child(root)

	_relationships_list = VBoxContainer.new()
	root.add_child(_relationships_list)


func update_relationships() -> void:
	for child in _relationships_list.get_children():
		child.queue_free()

	for character_id in Characters.all_character_ids():
		var def := Characters.get_character(character_id)
		var affection := LoveInterests.get_affection(character_id)
		@warning_ignore("integer_division")
		var hearts := clampi(affection / AFFECTION_PER_HEART, 0, MAX_HEARTS)

		var row: RelationshipRow = RELATIONSHIP_ROW_SCENE.instantiate()
		_relationships_list.add_child(row)
		row.populate(def.display_name, hearts, MAX_HEARTS, def.placeholder_color, def.portrait)


# ---------------------------------------------------------------------------
# Classes
# ---------------------------------------------------------------------------

func _build_classes_tab() -> void:
	var root := VBoxContainer.new()
	root.name = "Classes"
	add_child(root)

	_report_card_label = Label.new()
	_report_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_report_card_label)


func update_report_card() -> void:
	_report_card_label.text = "Report Card\n\nScore: %.0f/100\nStrikes: %d/%d\nAbsences: %d\nNext exam in %d day(s)" % [
		Academy.running_score, Academy.strikes, Academy.STRIKE_LIMIT, Academy.absences, Academy.days_until_exam()
	]


# ---------------------------------------------------------------------------
# Recipes
# ---------------------------------------------------------------------------

func _build_recipes_tab() -> void:
	var root := VBoxContainer.new()
	root.name = "Recipes"
	add_child(root)

	_recipes_list = VBoxContainer.new()
	root.add_child(_recipes_list)


## Recipes have no "learned" event yet (RecipeDef.known is static per-file for
## now, see docs/design/systems.md system 3), so this only needs to run once
## from build() rather than reacting to a signal like the other tabs.
func update_recipes() -> void:
	for child in _recipes_list.get_children():
		child.queue_free()

	for recipe in ContentRegistry.recipes:
		var ingredients_text := ""
		var icon: Texture2D = null
		if recipe.known:
			var ingredient_parts: Array[String] = []
			for i in recipe.ingredient_ids.size():
				var ingredient := ContentRegistry.get_ingredient(recipe.ingredient_ids[i])
				var ingredient_name := ingredient.display_name if ingredient != null else recipe.ingredient_ids[i]
				ingredient_parts.append("%s x%d" % [ingredient_name, recipe.ingredient_quantities[i]])
			ingredients_text = ", ".join(ingredient_parts)
			# TODO: use the output potion's own icon once a PotionDef resource
			# exists; for now the first required ingredient stands in for it.
			var first_ingredient := ContentRegistry.get_ingredient(recipe.ingredient_ids[0])
			icon = first_ingredient.icon if first_ingredient != null else null

		var row: RecipeEntry = RECIPE_ENTRY_SCENE.instantiate()
		_recipes_list.add_child(row)
		row.populate(recipe.display_name, recipe.known, ingredients_text, icon)
		_recipes_list.add_child(HSeparator.new())


# ---------------------------------------------------------------------------
# Journal
# ---------------------------------------------------------------------------

func _build_journal_tab() -> void:
	var root := VBoxContainer.new()
	root.name = "Journal"
	add_child(root)

	_journal_list = VBoxContainer.new()
	root.add_child(_journal_list)


func update_journal() -> void:
	for child in _journal_list.get_children():
		child.queue_free()

	_add_journal_section("Ready to Turn In", QuestManager.ready_to_turn_in_quest_ids(), Color(0.9, 0.8, 0.3))
	_add_journal_section("Active", QuestManager.active_quest_ids(), Color(1, 1, 1))
	_add_journal_section("Completed", QuestManager.completed_quest_ids(), Color(0.6, 0.6, 0.6))

	if _journal_list.get_child_count() == 0:
		var empty_label := Label.new()
		empty_label.text = "No quests yet."
		empty_label.modulate = Color(0.6, 0.6, 0.6)
		_journal_list.add_child(empty_label)


func _add_journal_section(section_title: String, quest_ids: Array[String], color: Color) -> void:
	if quest_ids.is_empty():
		return

	var header := Label.new()
	header.text = section_title
	header.add_theme_font_size_override("font_size", 14)
	_journal_list.add_child(header)

	for quest_id in quest_ids:
		var quest := ContentRegistry.get_quest(quest_id)
		var show_turn_in := QuestManager.status(quest_id) == QuestManager.Status.READY_TO_TURN_IN

		var row: QuestEntry = QUEST_ENTRY_SCENE.instantiate()
		_journal_list.add_child(row)
		row.populate(quest_id, quest.display_name, quest.description, color, show_turn_in)
		row.turn_in_pressed.connect(QuestManager.turn_in)

	_journal_list.add_child(HSeparator.new())


# ---------------------------------------------------------------------------
# Disabled (out of scope) tabs
# ---------------------------------------------------------------------------

func _build_disabled_tab(tab_name: String) -> void:
	var root := VBoxContainer.new()
	root.name = tab_name

	var label := Label.new()
	label.text = "Coming soon."
	label.modulate = Color(0.6, 0.6, 0.6)
	root.add_child(label)

	add_child(root)


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

func _build_settings_tab() -> void:
	var root := VBoxContainer.new()
	root.name = "Settings"
	add_child(root)

	SettingsControls.build(root)

	root.add_child(HSeparator.new())

	var save_button := Button.new()
	save_button.text = "Save Game"
	save_button.pressed.connect(_on_save_button_pressed)
	root.add_child(save_button)

	_save_status_label = Label.new()
	_save_status_label.modulate = Color(0.6, 0.6, 0.6)
	root.add_child(_save_status_label)

	var return_button := Button.new()
	return_button.text = "Return to Main Screen"
	return_button.pressed.connect(_on_return_button_pressed)
	root.add_child(return_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	root.add_child(quit_button)


func _on_save_button_pressed() -> void:
	var result := SaveManager.save_game(GameFlow.game_id)
	if result.ok:
		_save_status_label.text = "Saved (slot %d)." % result.slot
	else:
		_save_status_label.text = "Save failed: %s" % result.error


func _on_return_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
