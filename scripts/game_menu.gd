class_name GameMenu
extends TabContainer
## The Escape menu's content — a tabbed utility screen. Built ad hoc in code,
## same "no .tscn, no shared content base class" style as scripts/hud.gd and
## scripts/menu_scene.gd. hud.gd owns one instance and hands it to MenuScene
## the same way it always handed over the old flat game-menu VBoxContainer.
##
## Inventory/Skills/Relationships/Classes/Journal tabs connect directly to the
## autoload signals whose only effect is refreshing their own display —
## consistent with how hud.gd wires up signals whose effect is purely a
## label update. Shop/Map are out of scope for the prototype and stay as
## disabled tabs.

const GRID_COLUMNS := 8
const GRID_ROWS := 3
const SLOT_SIZE := Vector2(72, 72)

const AFFECTION_PER_HEART := 20
const MAX_HEARTS := 5

var _inventory_grid: GridContainer
var _skills_list: VBoxContainer
var _relationships_list: VBoxContainer
var _recipes_list: VBoxContainer
var _report_card_label: Label
var _journal_list: VBoxContainer
var _save_status_label: Label


func build() -> void:
	custom_minimum_size = Vector2(560, 400)

	_build_inventory_tab()
	_build_skills_tab()
	_build_disabled_tab("Shop")
	_build_relationships_tab()
	_build_classes_tab()
	_build_disabled_tab("Map")
	_build_recipes_tab()
	_build_journal_tab()
	_build_settings_tab()

	set_tab_disabled(2, true)  # Shop
	set_tab_disabled(5, true)  # Map

	Inventory.ingredient_changed.connect(func(_id: String, _qty: int) -> void: update_inventory())
	Inventory.potion_added.connect(func(_id: String, _potency: float, _ease: float) -> void: update_inventory())
	Skills.xp_gained.connect(func(_id: String, _xp: int, _level: int) -> void: update_skills())
	Skills.leveled_up.connect(func(_id: String, _level: int) -> void: update_skills())
	LoveInterests.affection_changed.connect(func(_id: String, _amount: int) -> void: update_relationships())
	Academy.attended_class.connect(update_report_card)
	Academy.absence_recorded.connect(func(_absences: int) -> void: update_report_card())
	Academy.exam_graded.connect(func(_passed: bool, _score: float, _strikes: int) -> void: update_report_card())
	QuestManager.quest_started.connect(func(_id: String) -> void: update_journal())
	QuestManager.quest_ready_to_turn_in.connect(func(_id: String) -> void: update_journal())
	QuestManager.quest_completed.connect(func(_id: String) -> void: update_journal())

	update_inventory()
	update_skills()
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
			entries.append({"text": "%s x%d" % [ingredient.display_name, count], "color": _color_for_id(ingredient.id)})

	var potion_counts: Dictionary = {}
	for potion in Inventory.potions:
		var potion_id: String = potion.potion_id
		potion_counts[potion_id] = potion_counts.get(potion_id, 0) + 1
	for potion_id in potion_counts:
		entries.append({"text": "%s x%d" % [String(potion_id).capitalize(), potion_counts[potion_id]], "color": _color_for_id(potion_id)})

	for i in GRID_COLUMNS * GRID_ROWS:
		var entry: Variant = null
		if i < entries.size():
			entry = entries[i]
		_inventory_grid.add_child(_build_slot(entry))


func _build_slot(entry: Variant) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	if entry == null:
		panel.modulate = Color(1, 1, 1, 0.35)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var dot := Label.new()
	dot.text = "●" if entry != null else ""
	dot.add_theme_font_size_override("font_size", 26)
	if entry != null:
		dot.add_theme_color_override("font_color", entry.color)
	dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(dot)

	var name_label := Label.new()
	name_label.text = entry.text if entry != null else ""
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_label)

	return panel


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
		var row := HBoxContainer.new()

		var name_label := Label.new()
		name_label.text = def.display_name
		name_label.custom_minimum_size = Vector2(120, 0)
		row.add_child(name_label)

		var level_label := Label.new()
		level_label.text = "Lvl %d" % Skills.level(skill_id)
		level_label.custom_minimum_size = Vector2(60, 0)
		row.add_child(level_label)

		var progress := ProgressBar.new()
		progress.custom_minimum_size = Vector2(180, 20)
		progress.max_value = def.xp_per_level
		progress.value = def.xp_per_level - Skills.xp_to_next_level(skill_id) if def.xp_per_level > 0 else 0
		row.add_child(progress)

		var progress_label := Label.new()
		progress_label.text = "%d / %d xp" % [progress.value, def.xp_per_level]
		row.add_child(progress_label)

		_skills_list.add_child(row)


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

		var row := HBoxContainer.new()

		var name_label := Label.new()
		name_label.text = def.display_name
		name_label.custom_minimum_size = Vector2(120, 0)
		name_label.add_theme_color_override("font_color", def.placeholder_color)
		row.add_child(name_label)

		var hearts_label := Label.new()
		hearts_label.text = "♥".repeat(hearts) + "♡".repeat(MAX_HEARTS - hearts)
		hearts_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.4))
		row.add_child(hearts_label)

		_relationships_list.add_child(row)


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
		var row := VBoxContainer.new()

		var header := Label.new()
		header.text = recipe.display_name if recipe.known else "??? (unknown)"
		if not recipe.known:
			header.modulate = Color(0.6, 0.6, 0.6)
		row.add_child(header)

		if recipe.known:
			var ingredient_parts: Array[String] = []
			for i in recipe.ingredient_ids.size():
				var ingredient := ContentRegistry.get_ingredient(recipe.ingredient_ids[i])
				var ingredient_name := ingredient.display_name if ingredient != null else recipe.ingredient_ids[i]
				ingredient_parts.append("%s x%d" % [ingredient_name, recipe.ingredient_quantities[i]])

			var ingredients_label := Label.new()
			ingredients_label.text = "Requires: %s" % ", ".join(ingredient_parts)
			ingredients_label.add_theme_font_size_override("font_size", 12)
			ingredients_label.modulate = Color(0.8, 0.8, 0.8)
			row.add_child(ingredients_label)

		_recipes_list.add_child(row)
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

		var row := VBoxContainer.new()

		var header_row := HBoxContainer.new()
		row.add_child(header_row)

		var name_label := Label.new()
		name_label.text = quest.display_name
		name_label.modulate = color
		header_row.add_child(name_label)

		if QuestManager.status(quest_id) == QuestManager.Status.READY_TO_TURN_IN:
			var turn_in_button := Button.new()
			turn_in_button.text = "Turn In"
			turn_in_button.pressed.connect(func() -> void: QuestManager.turn_in(quest_id))
			header_row.add_child(turn_in_button)

		var description_label := Label.new()
		description_label.text = quest.description
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		description_label.add_theme_font_size_override("font_size", 12)
		description_label.modulate = Color(0.8, 0.8, 0.8)
		row.add_child(description_label)

		_journal_list.add_child(row)

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
