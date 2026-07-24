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
##
## Fully keyboard-navigable in two levels, mirroring BrewMenu's two-mode model
## (see docs/design/systems.md, system 1) and built on MenuKeyNav's statics:
##   - Rail (default): W/S move through the sections, switching the shown page
##     as they go (the rail button's pressed fill is the cursor). E steps into
##     the current section if it has anything actionable. Esc isn't consumed,
##     so it falls through to main.gd and closes the menu.
##   - Section (after E): a hover-look cursor moves through the section's
##     buttons/sliders with W/S, A/D adjusts sliders and cycles OptionButtons,
##     E activates, and Esc steps back to the rail (consumed — a second Esc,
##     now at the rail, closes the menu). Controls are re-collected on every
##     move, so sections that rebuild themselves (Journal after a turn-in)
##     never leave the cursor on a freed node.
## The mouse works alongside this; clicking a rail button drops back to rail
## level, since you're picking a new section, not acting inside the old one.

const GRID_COLUMNS := 8
const GRID_ROWS := 3

const AFFECTION_PER_HEART := 20
const MAX_HEARTS := 5

const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")
const SKILL_ROW_SCENE := preload("res://scenes/ui/components/SkillRow.tscn")
const RELATIONSHIP_ROW_SCENE := preload("res://scenes/ui/components/RelationshipRow.tscn")
const RECIPE_ENTRY_SCENE := preload("res://scenes/ui/components/RecipeEntry.tscn")
const QUEST_ENTRY_SCENE := preload("res://scenes/ui/components/QuestEntry.tscn")

const RAIL_TIP := "W/S section\nE step in\nEsc close"
const SECTION_TIP := "W/S move\nA/D adjust\nE use\nEsc back"

var _rail: VBoxContainer
var _content: Control
var _rail_group := ButtonGroup.new()
var _rail_buttons: Dictionary = {}   # section_id -> Button
var _sections: Dictionary = {}       # section_id -> ScrollContainer
var _section_order: Array[String] = []
var _current_section_id := ""
var _in_section := false             # keyboard cursor is inside the section
var _section_highlight: Control = null
var _nav_tip: Label

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

	# Keyboard hint pinned to the bottom of the rail; swaps between the rail
	# and in-section key maps as the cursor level changes.
	var rail_spacer := Control.new()
	rail_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rail.add_child(rail_spacer)
	_nav_tip = Label.new()
	_nav_tip.theme_type_variation = &"CaptionLabel"
	_nav_tip.text = RAIL_TIP
	_rail.add_child(_nav_tip)

	_show_section("satchel")

	Inventory.ingredient_changed.connect(func(_id: String, _tier: int, _qty: int) -> void: update_inventory())
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
	_section_order.append(id)

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


## Switching sections (keyboard W/S at the rail, or a mouse click on a rail
## button) always drops back to rail level — you're picking a new section,
## not acting inside the old one.
func _show_section(id: String) -> void:
	_current_section_id = id
	_leave_section()
	for section_id in _sections:
		(_sections[section_id] as Control).visible = (section_id == id)
	if _rail_buttons.has(id):
		(_rail_buttons[id] as Button).button_pressed = true


# ---------------------------------------------------------------------------
# Keyboard navigation (rail level <-> section level)
# ---------------------------------------------------------------------------

## Re-opened via MenuScene (which reparents this in), so reset the cursor to
## rail level each time rather than resuming a stale in-section state.
func _enter_tree() -> void:
	_leave_section()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not Clock.is_paused:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	# Captured up front: activating the Settings tab's Return/Quit buttons
	# tears this menu out of the tree synchronously (change_scene_to_file),
	# after which get_viewport() returns null — same hazard as MenuKeyNav.
	var viewport := get_viewport()
	match event.keycode:
		KEY_W, KEY_UP:
			if _in_section:
				_move_section_cursor(-1)
			else:
				_move_rail(-1)
			viewport.set_input_as_handled()
		KEY_S, KEY_DOWN:
			if _in_section:
				_move_section_cursor(1)
			else:
				_move_rail(1)
			viewport.set_input_as_handled()
		KEY_A, KEY_LEFT:
			if _in_section and is_instance_valid(_section_highlight) \
					and MenuKeyNav.adjust(_section_highlight, -1):
				viewport.set_input_as_handled()
		KEY_D, KEY_RIGHT:
			if _in_section and is_instance_valid(_section_highlight) \
					and MenuKeyNav.adjust(_section_highlight, 1):
				viewport.set_input_as_handled()
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			if _in_section:
				if is_instance_valid(_section_highlight):
					MenuKeyNav.activate(_section_highlight)
			else:
				_enter_section()
			# Consumed either way so E never falls through to main.gd's
			# world interact while the journal owns the screen.
			viewport.set_input_as_handled()
		KEY_ESCAPE:
			# Only consume Esc when it has something to undo (stepping back to
			# the rail); at rail level it falls through to main.gd, which
			# closes the menu.
			if _in_section:
				_leave_section()
				viewport.set_input_as_handled()


func _move_rail(delta: int) -> void:
	var idx := _section_order.find(_current_section_id)
	idx = 0 if idx == -1 else clampi(idx + delta, 0, _section_order.size() - 1)
	_show_section(_section_order[idx])


## E at the rail: step into the current section, dropping the cursor on its
## first actionable control. A section with nothing actionable (Satchel,
## Hearts...) just stays at rail level.
func _enter_section() -> void:
	var controls := MenuKeyNav.collect_nav_controls(_sections.get(_current_section_id))
	if controls.is_empty():
		return
	_in_section = true
	_set_section_highlight(controls[0])
	_nav_tip.text = SECTION_TIP


func _leave_section() -> void:
	_in_section = false
	if is_instance_valid(_section_highlight):
		MenuKeyNav.set_highlight(_section_highlight, false)
	_section_highlight = null
	if _nav_tip != null:
		_nav_tip.text = RAIL_TIP


## Controls are re-collected on every move so a section that rebuilt itself
## since the last keypress (Journal after a turn-in) can't strand the cursor
## on a freed node — find() just misses and the cursor restarts at the top.
func _move_section_cursor(delta: int) -> void:
	var controls := MenuKeyNav.collect_nav_controls(_sections.get(_current_section_id))
	if controls.is_empty():
		_leave_section()
		return
	var idx := controls.find(_section_highlight)
	idx = 0 if idx == -1 else clampi(idx + delta, 0, controls.size() - 1)
	_set_section_highlight(controls[idx])


func _set_section_highlight(control: Control) -> void:
	if is_instance_valid(_section_highlight):
		MenuKeyNav.set_highlight(_section_highlight, false)
	_section_highlight = control
	MenuKeyNav.set_highlight(control, true)
	MenuKeyNav.ensure_visible(control, _content)


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
		var tiers := Inventory.ingredient_tiers(ingredient.id)
		for tier in tiers:
			var count: int = tiers[tier]
			if count <= 0:
				continue
			var type_label := "%s Ingredient" % IngredientDef.Category.keys()[ingredient.category].capitalize()
			entries.append({
				"name": ingredient.display_name,
				"quality": IngredientQuality.label(tier),
				"type": type_label,
				"quantity": count,
				"color": _color_for_id(ingredient.id),
				"icon": ingredient.icon,
			})

	var potion_counts: Dictionary = {}
	for potion in Inventory.potions:
		var potion_id: String = potion.potion_id
		potion_counts[potion_id] = potion_counts.get(potion_id, 0) + 1
	for potion_id in potion_counts:
		entries.append({
			"name": String(potion_id).capitalize(),
			"quality": "",
			"type": "Potion",
			"quantity": potion_counts[potion_id],
			"color": _color_for_id(potion_id),
			"icon": null,
		})

	for i in GRID_COLUMNS * GRID_ROWS:
		var slot: ItemSlot = ITEM_SLOT_SCENE.instantiate()
		_inventory_grid.add_child(slot)
		if i < entries.size():
			var entry: Dictionary = entries[i]
			slot.populate_item(entry.name, entry.quality, entry.type, entry.quantity, entry.color, entry.icon)
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
