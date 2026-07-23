class_name GameMenu
extends MarginContainer
## The Escape menu's content — a cozy journal/ledger with a left tab rail of
## themed sections and a scrollable content area on the right, handed to
## MenuScene by hud.gd. (Replaced the old flat 9-tab TabContainer; the class
## name and public API — build()/update_inventory()/update_skills()/... — stay
## the same so hud.gd is untouched.)
##
## Sections: Satchel (inventory) · Grimoire (recipes) · Shop (stock + coffers) ·
## Studies (skills + Academy report card, merged) · Hearts (relationships) ·
## Journal (quests) · Settings (options + Save/Return/Quit). The old disabled
## Map tab is dropped.
##
## Each section's repeated rows/cells (item slots, skill rows, relationship
## rows, recipe entries, quest entries) are scenes/ui/components/*.tscn scenes
## with a populate() method, instanced here rather than built node-by-node
## inline — see the *_SCENE consts below. Section content is built once in
## build() (detached from the SceneTree until MenuScene.open() reparents it in),
## which is why component node refs are looked up on demand, not via @onready.

const GRID_COLUMNS := 8
const GRID_ROWS := 3

const AFFECTION_PER_HEART := 20
const MAX_HEARTS := 5

const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")
const SKILL_ROW_SCENE := preload("res://scenes/ui/components/SkillRow.tscn")
const RELATIONSHIP_ROW_SCENE := preload("res://scenes/ui/components/RelationshipRow.tscn")
const RECIPE_ENTRY_SCENE := preload("res://scenes/ui/components/RecipeEntry.tscn")
const QUEST_ENTRY_SCENE := preload("res://scenes/ui/components/QuestEntry.tscn")

var _rail: VBoxContainer
var _content: Control
var _rail_group := ButtonGroup.new()
var _rail_buttons: Dictionary = {}   # section_id -> Button
var _sections: Dictionary = {}       # section_id -> ScrollContainer

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
	custom_minimum_size = Vector2(820, 480)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	add_child(hbox)

	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 5)
	_rail.custom_minimum_size = Vector2(150, 0)
	hbox.add_child(_rail)

	hbox.add_child(VSeparator.new())

	_content = Control.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.clip_contents = true
	# GRID_COLUMNS(8) * ItemSlot min width(72) + 7 * GridContainer h_separation(4) = 604;
	# this must stay >= that or the Satchel/Shop grids bleed past the panel edge.
	_content.custom_minimum_size = Vector2(620, 0)
	hbox.add_child(_content)

	_add_section("satchel", "Satchel", _build_inventory_tab())
	_add_section("grimoire", "Grimoire", _build_recipes_tab())
	_add_section("shop", "Shop", _build_shop_tab())
	_add_section("studies", "Studies", _build_studies_tab())
	_add_section("hearts", "Hearts", _build_relationships_tab())
	_add_section("journal", "Journal", _build_journal_tab())
	_add_section("settings", "Settings", _build_settings_tab())

	_show_section("satchel")

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
	Alchemy.recipe_learned.connect(func(_id: String) -> void: update_recipes())
	Alchemy.recipe_unlearned.connect(func(_id: String) -> void: update_recipes())

	update_inventory()
	update_skills()
	update_shop()
	update_relationships()
	update_recipes()
	update_report_card()
	update_journal()


# ---------------------------------------------------------------------------
# Journal-book frame: left rail + swappable scrollable sections
# ---------------------------------------------------------------------------

## Wraps a section's content in a titled, scrollable panel and registers a rail
## button that shows it. The button's toggled/pressed theme state (walnut fill)
## is what marks the active section.
func _add_section(id: String, label: String, content: Control) -> void:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.button_group = _rail_group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_show_section.bind(id))
	_rail.add_child(button)
	_rail_buttons[id] = button

	var titled := VBoxContainer.new()
	titled.add_theme_constant_override("separation", 8)
	titled.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var heading := Label.new()
	heading.text = label
	heading.theme_type_variation = &"HeadingLabel"
	titled.add_child(heading)
	titled.add_child(HSeparator.new())

	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titled.add_child(content)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.visible = false
	scroll.add_child(titled)
	_content.add_child(scroll)
	_sections[id] = scroll


func _show_section(id: String) -> void:
	for section_id in _sections:
		(_sections[section_id] as Control).visible = (section_id == id)
	if _rail_buttons.has(id):
		(_rail_buttons[id] as Button).button_pressed = true


# ---------------------------------------------------------------------------
# Satchel (Inventory)
# ---------------------------------------------------------------------------

func _build_inventory_tab() -> Control:
	var root := VBoxContainer.new()
	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = GRID_COLUMNS
	root.add_child(_inventory_grid)
	return root


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
	return Color.from_hsv(hue, 0.45, 0.85)


# ---------------------------------------------------------------------------
# Studies (Skills + Academy report card)
# ---------------------------------------------------------------------------

func _build_studies_tab() -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)

	var skills_heading := Label.new()
	skills_heading.text = "Skills"
	skills_heading.theme_type_variation = &"SubheadingLabel"
	root.add_child(skills_heading)

	_skills_list = VBoxContainer.new()
	root.add_child(_skills_list)

	root.add_child(HSeparator.new())

	var report_heading := Label.new()
	report_heading.text = "Report Card"
	report_heading.theme_type_variation = &"SubheadingLabel"
	root.add_child(report_heading)

	_report_card_label = Label.new()
	_report_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_report_card_label)

	return root


func update_skills() -> void:
	for child in _skills_list.get_children():
		child.queue_free()

	for skill_id in Skills.skill_ids():
		var def := Skills.get_def(skill_id)
		var current_xp := def.xp_per_level - Skills.xp_to_next_level(skill_id) if def.xp_per_level > 0 else 0

		var row: SkillRow = SKILL_ROW_SCENE.instantiate()
		_skills_list.add_child(row)
		row.populate(def.display_name, Skills.level(skill_id), current_xp, def.xp_per_level)


func update_report_card() -> void:
	_report_card_label.text = "Score: %.0f/100   Strikes: %d/%d   Absences: %d   Next exam in %d day(s)" % [
		Academy.running_score, Academy.strikes, Academy.STRIKE_LIMIT, Academy.absences, Academy.days_until_exam()
	]


# ---------------------------------------------------------------------------
# Shop
# ---------------------------------------------------------------------------

func _build_shop_tab() -> Control:
	var root := VBoxContainer.new()

	_shop_reputation_label = Label.new()
	root.add_child(_shop_reputation_label)

	_shop_coffers_label = Label.new()
	root.add_child(_shop_coffers_label)

	root.add_child(HSeparator.new())

	_shop_grid = GridContainer.new()
	_shop_grid.columns = GRID_COLUMNS
	root.add_child(_shop_grid)
	return root


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
# Hearts (Relationships)
# ---------------------------------------------------------------------------

func _build_relationships_tab() -> Control:
	var root := VBoxContainer.new()
	_relationships_list = VBoxContainer.new()
	root.add_child(_relationships_list)
	return root


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
# Grimoire (Recipes)
# ---------------------------------------------------------------------------

func _build_recipes_tab() -> Control:
	var root := VBoxContainer.new()
	_recipes_list = VBoxContainer.new()
	root.add_child(_recipes_list)
	return root


## One group per potion (ContentRegistry.potions), not per recipe — a potion
## can have any number of learned recipes (different ingredient combinations
## Alchemy.attempt_discovery() has synthesized for it), each shown as its own
## row beneath the potion's header; an as-yet-undiscovered potion shows a
## single "??? (unknown)" placeholder row instead.
func update_recipes() -> void:
	for child in _recipes_list.get_children():
		child.queue_free()

	for potion in ContentRegistry.potions:
		var header := Label.new()
		header.theme_type_variation = &"SubheadingLabel"
		header.text = potion.display_name
		_recipes_list.add_child(header)

		var learned_recipes: Array[RecipeDef] = []
		for recipe in Alchemy.get_learned_recipes():
			if recipe.output_potion_id == potion.id:
				learned_recipes.append(recipe)

		if learned_recipes.is_empty():
			var row: RecipeEntry = RECIPE_ENTRY_SCENE.instantiate()
			_recipes_list.add_child(row)
			row.populate(potion.display_name, false, "")
		else:
			for recipe in learned_recipes:
				var ingredient_parts: Array[String] = []
				for i in recipe.ingredient_ids.size():
					var ingredient := ContentRegistry.get_ingredient(recipe.ingredient_ids[i])
					var ingredient_name := ingredient.display_name if ingredient != null else recipe.ingredient_ids[i]
					ingredient_parts.append("%s x%d" % [ingredient_name, recipe.ingredient_quantities[i]])
				var ingredients_text := ", ".join(ingredient_parts)
				var first_ingredient := ContentRegistry.get_ingredient(recipe.ingredient_ids[0]) if not recipe.ingredient_ids.is_empty() else null
				var icon: Texture2D = potion.icon if potion.icon != null else (first_ingredient.icon if first_ingredient != null else null)

				var row: RecipeEntry = RECIPE_ENTRY_SCENE.instantiate()
				_recipes_list.add_child(row)
				row.populate(recipe.display_name, true, ingredients_text, icon)
		_recipes_list.add_child(HSeparator.new())


# ---------------------------------------------------------------------------
# Journal (Quests)
# ---------------------------------------------------------------------------

func _build_journal_tab() -> Control:
	var root := VBoxContainer.new()
	_journal_list = VBoxContainer.new()
	root.add_child(_journal_list)
	return root


func update_journal() -> void:
	for child in _journal_list.get_children():
		child.queue_free()

	_add_journal_section("Ready to Turn In", QuestManager.ready_to_turn_in_quest_ids(), UiPalette.GOLD)
	_add_journal_section("Active", QuestManager.active_quest_ids(), UiPalette.TEXT_PRIMARY)
	_add_journal_section("Completed", QuestManager.completed_quest_ids(), UiPalette.TEXT_MUTED)

	if _journal_list.get_child_count() == 0:
		var empty_label := Label.new()
		empty_label.text = "No quests yet."
		empty_label.modulate = UiPalette.TEXT_MUTED
		_journal_list.add_child(empty_label)


func _add_journal_section(section_title: String, quest_ids: Array[String], color: Color) -> void:
	if quest_ids.is_empty():
		return

	var header := Label.new()
	header.text = section_title
	header.theme_type_variation = &"SubheadingLabel"
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
# Settings (options + Save / Return / Quit)
# ---------------------------------------------------------------------------

func _build_settings_tab() -> Control:
	var root := VBoxContainer.new()

	SettingsControls.build(root)

	root.add_child(HSeparator.new())

	var save_button := Button.new()
	save_button.text = "Save Game"
	save_button.pressed.connect(_on_save_button_pressed)
	root.add_child(save_button)

	_save_status_label = Label.new()
	_save_status_label.modulate = UiPalette.TEXT_MUTED
	root.add_child(_save_status_label)

	var return_button := Button.new()
	return_button.text = "Return to Main Screen"
	return_button.pressed.connect(_on_return_button_pressed)
	root.add_child(return_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	root.add_child(quit_button)
	return root


func _on_save_button_pressed() -> void:
	var result := SaveManager.save_game(GameFlow.game_id)
	if result.ok:
		_save_status_label.text = "Saved (slot %d)." % result.slot
	else:
		_save_status_label.text = "Save failed: %s" % result.error


func _on_return_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
