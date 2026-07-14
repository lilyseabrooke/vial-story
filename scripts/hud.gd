class_name GameHud
extends CanvasLayer
## Owns the debug HUD (status labels for clock/inventory/skills/Resolve/
## report card), the Escape menu shell, and the brew/supply panels — the
## "presenting information and menu chrome" half of what used to be
## main.gd. Connects directly to every autoload signal whose only effect is
## a label/log update; signals whose effect also touches world geometry
## (e.g. Herbalism harvest signals updating a grow-plot Interactable) stay
## wired in main.gd instead, which orchestrates both this and RoomBuilder.

const DAY_TYPE_NAMES := ["Weekday", "Weekend"]
const END_REASON_NAMES := ["slept", "collapsed from staying up too late", "collapsed (Resolve hit zero)"]

var brew_panel: VBoxContainer
var supply_panel: VBoxContainer

var _station_id: String = ""
var _starting_ingredients: Dictionary = {}

var _calendar_label: Label
var _time_label: Label
var _materials_label: Label
var _resolve_bar: ProgressBar
var _resolve_label: Label
var _log_label: Label
var _report_card_label: Label
var _game_over_label: Label
var _prompt_label: Label
var _game_menu: GameMenu
var _menu_scene: MenuScene

var _upgrade_buttons: Dictionary = {}   # upgrade_id -> Button


func build(station_id: String, starting_ingredients: Dictionary) -> void:
	_station_id = station_id
	_starting_ingredients = starting_ingredients

	# Resolve meter — top-left.
	var resolve_panel := PanelContainer.new()
	resolve_panel.position = Vector2(16, 16)
	add_child(resolve_panel)

	var resolve_vbox := VBoxContainer.new()
	resolve_panel.add_child(resolve_vbox)

	_resolve_bar = ProgressBar.new()
	_resolve_bar.custom_minimum_size = Vector2(180, 20)
	_resolve_bar.min_value = 0
	resolve_vbox.add_child(_resolve_bar)

	_resolve_label = Label.new()
	resolve_vbox.add_child(_resolve_label)

	# Calendar + Materials — top-right.
	var calendar_panel := PanelContainer.new()
	calendar_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	calendar_panel.position = Vector2(-200, 16)
	add_child(calendar_panel)

	var calendar_vbox := VBoxContainer.new()
	calendar_panel.add_child(calendar_vbox)

	_calendar_label = Label.new()
	_calendar_label.add_theme_font_size_override("font_size", 24)
	calendar_vbox.add_child(_calendar_label)

	_time_label = Label.new()
	calendar_vbox.add_child(_time_label)

	calendar_vbox.add_child(HSeparator.new())

	_materials_label = Label.new()
	calendar_vbox.add_child(_materials_label)

	calendar_vbox.add_child(HSeparator.new())

	_log_label = Label.new()
	_log_label.modulate = Color(0.8, 0.8, 0.8)
	_log_label.custom_minimum_size = Vector2(200, 0)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	calendar_vbox.add_child(_log_label)

	_report_card_label = Label.new()
	_report_card_label.custom_minimum_size = Vector2(200, 0)
	_report_card_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	calendar_vbox.add_child(_report_card_label)

	calendar_vbox.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "WASD: move | E: interact | Esc: menu | Space: pause | R: drain Resolve (debug) | Up/Down: tick rate"
	hint.modulate = Color(0.6, 0.6, 0.6)
	hint.custom_minimum_size = Vector2(200, 0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	calendar_vbox.add_child(hint)

	# Game Over — stays directly on screen (terminal state), not in the menu.
	_game_over_label = Label.new()
	_game_over_label.add_theme_font_size_override("font_size", 24)
	_game_over_label.modulate = Color(1.0, 0.3, 0.3)
	_game_over_label.visible = false
	_game_over_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_game_over_label.position = Vector2(-250, 16)
	_game_over_label.custom_minimum_size = Vector2(500, 0)
	_game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_game_over_label)

	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 20)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = Vector2(-150, -60)
	_prompt_label.custom_minimum_size = Vector2(300, 0)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_prompt_label)

	# Everything else lives in the Escape menu instead of the HUD. Not added
	# as a child here — MenuScene.open() reparents it into its body on first
	# open (same as brew_panel/supply_panel), and a Control only needs to be
	# in the tree for its own logic (Save/Return button handlers) to run.
	_game_menu = GameMenu.new()
	_game_menu.build()

	brew_panel = VBoxContainer.new()
	for recipe in ContentRegistry.recipes:
		var button := Button.new()
		button.text = "Brew: %s" % recipe.display_name
		button.pressed.connect(on_brew_button_pressed.bind(recipe))
		brew_panel.add_child(button)
	var collect_button := Button.new()
	collect_button.text = "Collect from %s" % _station_id
	collect_button.pressed.connect(on_collect_button_pressed)
	brew_panel.add_child(collect_button)

	supply_panel = VBoxContainer.new()
	for ingredient in ContentRegistry.ingredients:
		var ingredient_button := Button.new()
		ingredient_button.text = "Buy %s (%d)" % [ingredient.display_name, ingredient.buy_price]
		ingredient_button.pressed.connect(on_buy_ingredient_button_pressed.bind(ingredient))
		supply_panel.add_child(ingredient_button)
	for seed_def in ContentRegistry.seeds:
		var seed_button := Button.new()
		seed_button.text = "Buy %s (%d)" % [seed_def.display_name, seed_def.buy_price]
		seed_button.pressed.connect(on_buy_seed_button_pressed.bind(seed_def))
		supply_panel.add_child(seed_button)
	for upgrade in ContentRegistry.upgrades:
		var upgrade_button := Button.new()
		upgrade_button.text = "Buy upgrade: %s (%d)" % [upgrade.display_name, upgrade.cost]
		upgrade_button.pressed.connect(on_buy_upgrade_button_pressed.bind(upgrade))
		_upgrade_buttons[upgrade.id] = upgrade_button
		supply_panel.add_child(upgrade_button)

	_menu_scene = MenuScene.new()
	add_child(_menu_scene)

	_connect_autoload_signals()

	update_clock_label()
	update_ingredients_label()
	update_materials_label()
	update_skills_label()
	update_resolve_meter()
	update_report_card_label()


func _connect_autoload_signals() -> void:
	Clock.minute_tick.connect(func(_timestamp: int) -> void:
		update_clock_label()
		update_report_card_label()
	)
	Clock.day_started.connect(func(day_number: int, day_type: int) -> void:
		log_message("Day %d (%s) begins." % [day_number, DAY_TYPE_NAMES[day_type]])
		update_clock_label()
		print("Day %d (%s) begins." % [day_number, DAY_TYPE_NAMES[day_type]])
	)
	Clock.day_ended.connect(func(reason: int) -> void:
		log_message("Day ended: %s" % END_REASON_NAMES[reason])
		print("Day ended: %s" % END_REASON_NAMES[reason])
	)
	Brewing.brew_started.connect(func(station_id: String, recipe_id: String) -> void:
		print("Brew started at %s: %s" % [station_id, recipe_id])
	)
	Brewing.brew_ready.connect(func(station_id: String, recipe_id: String) -> void:
		log_message("%s is ready at %s!" % [recipe_id, station_id])
		print("Brew ready at %s: %s" % [station_id, recipe_id])
	)
	Brewing.brew_collected.connect(func(_collected_station_id: String, recipe_id: String, potency: float, ease_value: float) -> void:
		print("Collected %s — potency %.1f, ease %.1f" % [recipe_id, potency, ease_value])
	)
	Brewing.brew_botched.connect(func(station_id: String, recipe_id: String) -> void:
		log_message("Brew botched at %s: %s! Resolve took a hit." % [station_id, recipe_id])
		print("Brew botched at %s: %s" % [station_id, recipe_id])
	)
	Skills.leveled_up.connect(func(skill_id: String, new_level: int) -> void:
		log_message("%s leveled up to %d!" % [skill_id.capitalize(), new_level])
		print("%s leveled up to %d." % [skill_id, new_level])
	)
	Resolve.resolve_changed.connect(func(_current: int, _max_resolve: int) -> void:
		update_resolve_meter()
	)
	Resolve.strained_changed.connect(func(is_strained: bool) -> void:
		if is_strained:
			log_message("Resolve is strained — all skill bonuses are halved.")
		print("Strained: %s" % is_strained)
		update_resolve_meter()
	)
	Inventory.materials_changed.connect(func(_amount: int) -> void:
		update_materials_label()
	)
	Shop.potion_sold.connect(func(potion_id: String, price: int) -> void:
		log_message("Sold %s for %d Materials!" % [potion_id, price])
		print("Sold %s for %d Materials." % [potion_id, price])
		update_materials_label()
	)
	Economy.upgrade_purchased.connect(_on_upgrade_purchased)
	Academy.attended_class.connect(func() -> void:
		print("Attended class.")
	)
	Academy.absence_recorded.connect(func(absences: int) -> void:
		log_message("Missed class today. Absences: %d" % absences)
		print("Absence recorded. Total: %d" % absences)
		update_report_card_label()
	)
	Academy.exam_graded.connect(func(passed: bool, score: float, strikes: int) -> void:
		log_message("Exam %s! Score: %.0f, Strikes: %d" % ["passed" if passed else "FAILED", score, strikes])
		print("Exam %s. Score: %.1f, Strikes: %d" % ["passed" if passed else "failed", score, strikes])
		update_report_card_label()
	)
	Academy.game_over.connect(func() -> void:
		_game_over_label.text = "GAME OVER — The Academy has revoked your selling privileges."
		_game_over_label.visible = true
		print("GAME OVER: strikes reached the limit.")
		update_report_card_label()
	)


func log_message(text: String) -> void:
	_log_label.text = text


func set_prompt(text: String) -> void:
	_prompt_label.text = text


func is_menu_open() -> bool:
	return _menu_scene.is_open()


func has_menu_content(content: Control) -> bool:
	return _menu_scene.has_content(content)


func open_menu(content: Control, title: String) -> void:
	_menu_scene.open(content, title)


func close_menu() -> void:
	_menu_scene.close()


func toggle_menu(content: Control, title: String) -> void:
	if _menu_scene.has_content(content) and _menu_scene.is_open():
		_menu_scene.close()
	else:
		_menu_scene.open(content, title)


func toggle_game_menu() -> void:
	if _menu_scene.is_open():
		_menu_scene.close()
	else:
		_menu_scene.open(_game_menu, "Menu")


func on_brew_button_pressed(recipe: RecipeDef) -> void:
	var error := Brewing.start_brew(_station_id, recipe)
	log_message("Couldn't brew %s: %s" % [recipe.display_name, error] if error != "" \
		else "Started brewing %s." % recipe.display_name)


func on_collect_button_pressed() -> void:
	if not Brewing.collect(_station_id):
		log_message("Nothing ready to collect at %s." % _station_id)


func on_stock_button_pressed() -> void:
	var stocked_count := Shop.stock_all_potions()
	log_message("Stocked %d potion(s)." % stocked_count if stocked_count > 0 \
		else "Nothing to stock (empty inventory or shop full).")


func on_buy_ingredient_button_pressed(ingredient: IngredientDef) -> void:
	var error := Economy.buy_ingredient(ingredient)
	log_message("Couldn't buy %s: %s" % [ingredient.display_name, error] if error != "" \
		else "Bought 1 %s." % ingredient.display_name)


func on_buy_upgrade_button_pressed(upgrade: UpgradeDef) -> void:
	var error := Economy.purchase_upgrade(upgrade)
	log_message("Couldn't buy %s: %s" % [upgrade.display_name, error] if error != "" \
		else "Purchased upgrade: %s." % upgrade.display_name)


func on_buy_seed_button_pressed(seed_def: SeedDef) -> void:
	var error := Economy.buy_seed(seed_def)
	log_message("Couldn't buy %s: %s" % [seed_def.display_name, error] if error != "" \
		else "Bought 1 %s." % seed_def.display_name)


func attend_class() -> void:
	var error := Academy.attend_class()
	log_message("Couldn't attend class: %s" % error if error != "" \
		else "Attended class — running score up, Herbalism XP gained.")
	update_clock_label()
	update_report_card_label()


func _on_upgrade_purchased(upgrade_id: String) -> void:
	var button: Button = _upgrade_buttons.get(upgrade_id)
	if button:
		button.disabled = true
		button.text += " [OWNED]"


func update_clock_label() -> void:
	var day_type_name: String = DAY_TYPE_NAMES[Clock.day_type()]
	_calendar_label.text = "Day %d (%s)" % [Clock.day_number, day_type_name]
	_time_label.text = "%s%s" % [
		Clock.get_clock_string(),
		" [PAUSED]" if Clock.is_paused else "",
	]


func update_ingredients_label() -> void:
	_game_menu.update_inventory()


func update_materials_label() -> void:
	_materials_label.text = "Materials: %d" % Inventory.materials


func update_skills_label() -> void:
	_game_menu.update_skills()


func update_resolve_meter() -> void:
	_resolve_bar.max_value = Resolve.max_resolve
	_resolve_bar.value = Resolve.current
	var strained_suffix := " [STRAINED]" if Resolve.is_strained() else ""
	_resolve_label.text = "Resolve: %d/%d%s" % [Resolve.current, Resolve.max_resolve, strained_suffix]


func update_report_card_label() -> void:
	_report_card_label.text = "Report Card — score: %.0f/100 | strikes: %d/%d | absences: %d | next exam in %d day(s)" % [
		Academy.running_score, Academy.strikes, Academy.STRIKE_LIMIT, Academy.absences, Academy.days_until_exam()
	]
