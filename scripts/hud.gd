class_name GameHud
extends CanvasLayer
## Owns the debug HUD (status labels for clock/inventory/skills/Resolve),
## the Escape menu shell, and the brew/supply panels — the
## "presenting information and menu chrome" half of what used to be
## main.gd. Connects directly to every autoload signal whose only effect is
## a label/log update; signals whose effect also touches world geometry
## (e.g. Herbalism harvest signals updating a grow-plot Interactable) stay
## wired in main.gd instead, which orchestrates both this and RoomBuilder.

const DAY_TYPE_NAMES := ["Weekday", "Weekend"]
const END_REASON_NAMES := ["slept", "collapsed from staying up too late", "collapsed (Resolve hit zero)"]
const MESSAGE_WALL_SCENE := preload("res://scenes/ui/components/MessageWall.tscn")
const LEY_LINE_MINIGAME_PANEL_SCENE := preload("res://scenes/ui/LeyLineMinigamePanel.tscn")
const PLANAR_RIFT_MINIGAME_PANEL_SCENE := preload("res://scenes/ui/PlanarRiftMinigamePanel.tscn")

var brew_panel: VBoxContainer
var supply_panel: VBoxContainer

var _station_id: String = ""
var _starting_ingredients: Dictionary = {}

var _calendar_label: Label
var _time_label: Label
var _speed_buttons: Array[Button] = []
var _materials_label: Label
var _resolve_bar: ProgressBar
var _resolve_label: Label
var _game_over_label: Label
var _prompt_label: Label
var _game_menu: GameMenu
var _menu_scene: MenuScene
var _message_wall: MessageWall
var _attempt_puzzle_panel: AttemptPuzzlePanel
var _ley_line_panel: LeyLineMinigamePanel
var _rift_panel: PlanarRiftMinigamePanel

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

	# Sims-style time speed buttons — 1x/1.5x/2x, radio-selected via a shared
	# ButtonGroup so exactly one is ever pressed. Clock.set_speed_level()
	# eases the actual tick rate toward the new target rather than snapping.
	var speed_hbox := HBoxContainer.new()
	calendar_vbox.add_child(speed_hbox)
	var speed_group := ButtonGroup.new()
	var speed_labels := ["1x", "1.5x", "2x"]
	for i in speed_labels.size():
		var speed_button := Button.new()
		speed_button.text = speed_labels[i]
		speed_button.toggle_mode = true
		speed_button.button_group = speed_group
		speed_button.button_pressed = (i == Clock.speed_level)
		speed_button.pressed.connect(func() -> void:
			Clock.set_speed_level(i)
		)
		_speed_buttons.append(speed_button)
		speed_hbox.add_child(speed_button)

	calendar_vbox.add_child(HSeparator.new())

	_materials_label = Label.new()
	calendar_vbox.add_child(_materials_label)

	calendar_vbox.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "WASD: move | E: interact | Esc: menu | Space: pause | R: drain Resolve (debug) | 1/2/3: speed"
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

	_attempt_puzzle_panel = AttemptPuzzlePanel.new()
	_attempt_puzzle_panel.build()

	# Instanced from a scene (not .new()) so its minigame tunables are
	# editable in the inspector on LeyLineMinigamePanel.tscn; build() still
	# constructs the panel's children in code, same as the other HUD panels.
	_ley_line_panel = LEY_LINE_MINIGAME_PANEL_SCENE.instantiate()
	_ley_line_panel.build()

	# Instanced from a scene (not .new()) so its portal-timer tunables are
	# editable in the inspector on PlanarRiftMinigamePanel.tscn, same as the
	# ley line panel above.
	_rift_panel = PLANAR_RIFT_MINIGAME_PANEL_SCENE.instantiate()
	_rift_panel.build()

	brew_panel = VBoxContainer.new()
	_rebuild_brew_panel()

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
	# LeyLines has no walk-away tether (MenuScene already freezes the player
	# for the whole session) -- closing the menu by any route (Esc, the
	# close button, or the panel's own Abort button after it's already
	# resolved) is what stands in for "leaving mid-minigame", so a still-
	# active session here means the player bailed without finishing.
	_menu_scene.closed.connect(func() -> void:
		if LeyLines.is_active():
			LeyLines.abort_minigame()
		# Same walk-away guard for the Planar Rift minigame: closing the menu
		# by any route while a session is still open (i.e. the player hadn't
		# matched a sequence or timed out yet) counts as leaving it.
		if Summoning.is_minigame_active():
			Summoning.abort_rift_minigame()
			log_message("You step back from the rift — the portal fades without a summoning.")
	)

	_message_wall = MESSAGE_WALL_SCENE.instantiate()
	add_child(_message_wall)

	_connect_autoload_signals()

	update_clock_label()
	update_ingredients_label()
	update_materials_label()
	update_skills_label()
	update_resolve_meter()


func _connect_autoload_signals() -> void:
	Clock.minute_tick.connect(func(_timestamp: int) -> void:
		update_clock_label()
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
	Clock.speed_level_changed.connect(func(level: int) -> void:
		_speed_buttons[level].button_pressed = true
	)
	Brewing.brew_started.connect(func(station_id: String, recipe_id: String) -> void:
		var recipe := ContentRegistry.get_recipe(recipe_id)
		log_message("Started brewing %s." % (recipe.display_name if recipe else recipe_id))
		print("Brew started at %s: %s" % [station_id, recipe_id])
	)
	Brewing.brew_ready.connect(func(station_id: String, recipe_id: String) -> void:
		log_message("%s is ready at %s!" % [recipe_id, station_id])
		print("Brew ready at %s: %s" % [station_id, recipe_id])
	)
	Brewing.brew_collected.connect(func(_collected_station_id: String, recipe_id: String, potency: float, ease_value: float) -> void:
		var recipe := ContentRegistry.get_recipe(recipe_id)
		log_message("Collected %s!" % (recipe.display_name if recipe else recipe_id))
		print("Collected %s — potency %.1f, ease %.1f" % [recipe_id, potency, ease_value])
	)
	Brewing.brew_botched.connect(func(station_id: String, recipe_id: String) -> void:
		log_message("Brew botched at %s: %s! Resolve took a hit." % [station_id, recipe_id])
		print("Brew botched at %s: %s" % [station_id, recipe_id])
	)
	Brewing.brew_roll_resolved.connect(func(_brewing_station_id: String, recipe_id: String, roll: Dictionary) -> void:
		_message_wall.add_dice_result(roll, "Brewing: %s" % recipe_id)
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
		log_message("Sold %s for %d Materials — waiting in the shop coffers." % [potion_id, price])
		print("Sold %s for %d Materials." % [potion_id, price])
	)
	Shop.coffers_collected.connect(func(amount: int) -> void:
		update_materials_label()
		print("Collected %d Materials from the shop coffers." % amount)
	)
	Economy.upgrade_purchased.connect(_on_upgrade_purchased)
	Academy.attended_class.connect(func() -> void:
		print("Attended class.")
	)
	Academy.absence_recorded.connect(func(absences: int) -> void:
		log_message("Missed class today. Absences: %d" % absences)
		print("Absence recorded. Total: %d" % absences)
	)
	Academy.exam_graded.connect(func(passed: bool, score: float, strikes: int) -> void:
		log_message("Exam %s! Score: %.0f, Strikes: %d" % ["passed" if passed else "FAILED", score, strikes])
		print("Exam %s. Score: %.1f, Strikes: %d" % ["passed" if passed else "failed", score, strikes])
	)
	Academy.class_performance_rolled.connect(func(result: Dictionary) -> void:
		_message_wall.add_dice_result(result, "Class Performance")
	)
	Academy.game_over.connect(func() -> void:
		_game_over_label.text = "GAME OVER — The Academy has revoked your selling privileges."
		_game_over_label.visible = true
		print("GAME OVER: strikes reached the limit.")
	)
	Demonology.writ_started.connect(func(_book_id: String) -> void:
		log_message("A new writ takes shape at the Contract Book.")
	)
	Demonology.writ_first_draft_done.connect(func(_book_id: String, quality: float) -> void:
		log_message("First draft of the writ finished (quality %.0f) -- revising automatically." % quality)
		print("Writ first draft done: quality %.1f" % quality)
	)
	Demonology.writ_revised.connect(func(book_id: String, revisions_completed: int, quality: float) -> void:
		print("Writ revised at %s: revision %d, quality %.1f" % [book_id, revisions_completed, quality])
	)
	Demonology.writ_submitted.connect(func(book_id: String, roll: Dictionary, ingredients: Dictionary, drawback_messages: Array) -> void:
		_message_wall.add_dice_result(roll, "Demonology: %s" % book_id)
		var ingredient_summary: Array[String] = []
		for id in ingredients:
			ingredient_summary.append("%d %s" % [ingredients[id], id])
		var drawback_summary := "; ".join(drawback_messages) if not drawback_messages.is_empty() else "no immediate drawbacks"
		log_message("Writ submitted! Received: %s. %s" % [", ".join(ingredient_summary), drawback_summary])
		print("Writ submitted at %s -- ingredients: %s, drawbacks: %s" % [book_id, ingredient_summary, drawback_messages])
		update_ingredients_label()
	)
	Demonology.consequence_triggered.connect(func(message: String) -> void:
		log_message(message)
		print("Delayed demonic consequence: %s" % message)
	)
	Draconology.stash_resolved.connect(func(stash_id: String, roll: Dictionary, ingredients: Dictionary) -> void:
		_message_wall.add_dice_result(roll, "Draconology: %s" % stash_id)
		var ingredient_summary: Array[String] = []
		for id in ingredients:
			ingredient_summary.append("%d %s" % [ingredients[id], id])
		log_message("The Dragon's Stash gives up its hoard! Received: %s." % ", ".join(ingredient_summary))
		print("Dragon's Stash resolved at %s -- ingredients: %s" % [stash_id, ingredient_summary])
		update_ingredients_label()
	)
	LeyLines.minigame_started.connect(func(node_id: String, difficulty: float, rounds: int) -> void:
		_ley_line_panel.show_for(node_id, difficulty, rounds)
		open_menu(_ley_line_panel, "Ley Line Node")
		log_message("The ley line stirs, ready to resonate...")
	)
	LeyLines.minigame_resolved.connect(func(_node_id: String, _performance: float, tier: String, ingredients: Dictionary) -> void:
		close_menu()
		var ingredient_summary: Array[String] = []
		for id in ingredients:
			ingredient_summary.append("%d %s" % [ingredients[id], id])
		if ingredient_summary.is_empty():
			log_message("The ley line settles (%s) -- nothing crystallized this time." % tier)
		else:
			log_message("The ley line settles (%s)! Received: %s." % [tier, ", ".join(ingredient_summary)])
		print("Ley line minigame resolved -- tier %s, ingredients: %s" % [tier, ingredient_summary])
		update_ingredients_label()
	)
	LeyLines.minigame_aborted.connect(func(_node_id: String) -> void:
		log_message("You break away from the ley line -- no ingredients gathered.")
	)
	Summoning.rift_minigame_requested.connect(func(rift_id: String) -> void:
		_rift_panel.show_for(rift_id)
		open_menu(_rift_panel, "Planar Rift")
		log_message("The rift yawns open — trace a summoning sequence before it closes.")
	)
	Summoning.rift_quality_rolled.connect(func(_rift_id: String, _bundle_id: String, quality: float, roll: Dictionary) -> void:
		_message_wall.add_dice_result(roll, "Summoning")
		log_message("The summoning steadies at %s quality (%d%%)." % [Summoning.quality_word(quality), int(round(quality * 100.0))])
	)
	Summoning.rift_started.connect(func(rift_id: String, bundle_id: String) -> void:
		# start_rift() only fires from the minigame's success path now, so the
		# rift panel is what's open -- close it as the summon takes hold.
		if has_menu_content(_rift_panel):
			close_menu()
		var bundle := ContentRegistry.get_rift_bundle(bundle_id)
		log_message("The rift begins drawing something through: %s." % (bundle.display_name if bundle else bundle_id))
		print("Rift started at %s: %s" % [rift_id, bundle_id])
	)
	Summoning.rift_failed.connect(func(rift_id: String, resolve_cost: int) -> void:
		if has_menu_content(_rift_panel):
			close_menu()
		log_message("The Planar Rift collapses shut before the summoning takes — you lose %d Resolve." % resolve_cost)
		update_resolve_meter()
		print("Rift minigame failed at %s -- Resolve cost %d" % [rift_id, resolve_cost])
	)
	Summoning.rift_ready.connect(func(rift_id: String, bundle_id: String) -> void:
		log_message("The Planar Rift is ready to collect.")
		print("Rift ready at %s: %s" % [rift_id, bundle_id])
	)
	Summoning.rift_collected.connect(func(_rift_id: String, bundle_id: String, ingredients: Dictionary, material_delta: int, resolve_delta: int, quality: float) -> void:
		var bundle := ContentRegistry.get_rift_bundle(bundle_id)
		var ingredient_summary: Array[String] = []
		for id in ingredients:
			ingredient_summary.append("%d %s" % [ingredients[id], id])
		var outcome_parts: Array[String] = []
		if not ingredient_summary.is_empty():
			outcome_parts.append("received %s" % ", ".join(ingredient_summary))
		if material_delta != 0:
			outcome_parts.append("%s%d Materials" % ["+" if material_delta > 0 else "", material_delta])
		if resolve_delta != 0:
			outcome_parts.append("%s%d Resolve" % ["+" if resolve_delta > 0 else "", resolve_delta])
		log_message("%s [%s summon] %s" % [bundle.flavor_text if bundle else "", Summoning.quality_word(quality), "; ".join(outcome_parts)])
		print("Rift collected: %s (quality %.2f) -- %s" % [bundle_id, quality, outcome_parts])
		update_ingredients_label()
		update_materials_label()
	)
	Transmutation.scrap_broken_down.connect(func(roll: Dictionary, ingredients: Dictionary) -> void:
		_message_wall.add_dice_result(roll, "Transmutation")
		var ingredient_summary: Array[String] = []
		for id in ingredients:
			ingredient_summary.append("%d %s" % [ingredients[id], id])
		log_message("Broke down Scrap! Received: %s." % ", ".join(ingredient_summary))
		print("Scrap broken down -- ingredients: %s" % [ingredient_summary])
		update_ingredients_label()
	)
	Alchemy.recipe_learned.connect(func(recipe_id: String) -> void:
		var recipe := ContentRegistry.get_recipe(recipe_id)
		log_message("Learned recipe: %s!" % (recipe.display_name if recipe else recipe_id))
		print("Learned recipe: %s" % recipe_id)
		_rebuild_brew_panel()
	)
	Alchemy.recipe_unlearned.connect(func(_recipe_id: String) -> void:
		_rebuild_brew_panel()
	)
	Alchemy.puzzle_attempted.connect(func(recipe_id: String, success: bool) -> void:
		if not success:
			var recipe := ContentRegistry.get_recipe(recipe_id)
			log_message("That combination didn't work for %s." % (recipe.display_name if recipe else recipe_id))
		print("Puzzle attempted for %s: %s" % [recipe_id, "success" if success else "failure"])
	)


func log_message(text: String) -> void:
	_message_wall.add_notice(text)


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


## Rebuilds brew_panel's buttons in place (same container instance, since
## main.gd's _on_interact_pressed() toggles it by reference) — one "Brew"
## button per learned recipe, one "Discover" button per unlearned recipe that
## has a puzzle, called both at build() and whenever Alchemy's learned set
## changes so the buttons stay in sync. This menu only ever opens when the
## station has no job running (main.gd's _interact_brew_station()), so there's
## no collect button here — a finished brew is auto-collected on interact
## instead.
func _rebuild_brew_panel() -> void:
	for child in brew_panel.get_children():
		child.queue_free()

	for recipe in ContentRegistry.recipes:
		if Alchemy.is_learned(recipe.id):
			var button := Button.new()
			button.text = "Brew: %s" % recipe.display_name
			button.pressed.connect(on_brew_button_pressed.bind(recipe))
			brew_panel.add_child(button)
		elif recipe.has_puzzle():
			var discover_button := Button.new()
			discover_button.text = "Discover: %s" % recipe.display_name
			discover_button.pressed.connect(_on_discover_button_pressed.bind(recipe))
			brew_panel.add_child(discover_button)


func _on_discover_button_pressed(recipe: RecipeDef) -> void:
	_attempt_puzzle_panel.show_for(recipe)
	open_menu(_attempt_puzzle_panel, "Discover: %s" % recipe.display_name)


## Success feedback (started brewing / botched) comes from the brew_started
## and brew_botched signal listeners above — start_brew() emits those
## synchronously before returning, so only the failure-to-start case needs
## handling here.
func on_brew_button_pressed(recipe: RecipeDef) -> void:
	var error := Brewing.start_brew(_station_id, recipe)
	if error != "":
		log_message("Couldn't brew %s: %s" % [recipe.display_name, error])


func on_stock_button_pressed() -> void:
	var stocked_count := Shop.stock_all_potions()
	var collected := Shop.collect_coffers()

	var messages: Array[String] = []
	if stocked_count > 0:
		messages.append("Stocked %d potion(s)." % stocked_count)
	if collected > 0:
		messages.append("Collected %d Materials from the coffers." % collected)
	log_message(" ".join(messages) if not messages.is_empty() \
		else "Nothing to stock or collect.")


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
