extends Node2D

const DAY_TYPE_NAMES := ["Weekday", "Weekend"]
const END_REASON_NAMES := ["slept", "collapsed from staying up too late", "collapsed (Resolve hit zero)"]

const STATION_ID := "alembic_1"
const STARTING_INGREDIENTS := {
	"moonpetal": 3,
	"iron_filings": 3,
	"ghostcap_mushroom": 3,
}

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const INTERACTABLE_SCENE := preload("res://scenes/Interactable.tscn")

const SHOP_ROOM_ID := "shop"
const BEDROOM_ROOM_ID := "bedroom"
const SHOP_SPAWN := Vector2(400, 400)
const BEDROOM_SPAWN := Vector2(400, 350)

var _calendar_label: Label
var _time_label: Label
var _materials_label: Label
var _resolve_bar: ProgressBar
var _resolve_label: Label
var _log_label: Label
var _ingredients_label: Label
var _station_label: Label
var _potions_label: Label
var _shop_label: Label
var _skills_label: Label
var _report_card_label: Label
var _game_over_label: Label
var _prompt_label: Label
var _brew_panel: VBoxContainer
var _supply_panel: VBoxContainer
var _game_menu_content: VBoxContainer
var _menu_scene: MenuScene

var _upgrade_buttons: Dictionary = {}   # upgrade_id -> Button
var _plot_nodes: Dictionary = {}        # plot_id -> Interactable

var _current_interactable: Interactable = null

var _camera: Camera2D
var _player: CharacterBody2D
var _rooms: Dictionary = {}             # room_id -> Node2D (room container)
var _room_camera_centers: Dictionary = {}  # room_id -> Vector2
var _current_room_id: String = ""


func _ready() -> void:
	print("Vial Story: main scene ready")
	_grant_starting_ingredients()
	_build_rooms()
	_build_hud()

	Clock.minute_tick.connect(_on_minute_tick)
	Clock.day_started.connect(_on_day_started)
	Clock.day_ended.connect(_on_day_ended)
	Brewing.brew_started.connect(_on_brew_started)
	Brewing.brew_ready.connect(_on_brew_ready)
	Brewing.brew_collected.connect(_on_brew_collected)
	Inventory.ingredient_changed.connect(_on_inventory_changed)
	Inventory.materials_changed.connect(_on_materials_changed)
	Shop.potion_stocked.connect(_on_potion_stocked)
	Shop.potion_sold.connect(_on_potion_sold)
	Economy.upgrade_purchased.connect(_on_upgrade_purchased)
	Skills.leveled_up.connect(_on_skill_leveled_up)
	Brewing.brew_botched.connect(_on_brew_botched)
	Resolve.resolve_changed.connect(_on_resolve_changed)
	Resolve.strained_changed.connect(_on_strained_changed)
	Herbalism.plot_added.connect(_on_plot_added)
	Herbalism.planted.connect(_on_planted)
	Herbalism.ready_to_harvest.connect(_on_ready_to_harvest)
	Herbalism.harvested.connect(_on_harvested)
	Academy.attended_class.connect(_on_attended_class)
	Academy.absence_recorded.connect(_on_absence_recorded)
	Academy.exam_graded.connect(_on_exam_graded)
	Academy.game_over.connect(_on_game_over)

	_update_clock_label()
	_update_ingredients_label()
	_update_materials_label()
	_update_station_label()
	_update_potions_label()
	_update_shop_label()
	_update_skills_label()
	_update_resolve_meter()
	_update_report_card_label()


func _grant_starting_ingredients() -> void:
	for id in STARTING_INGREDIENTS:
		Inventory.add_ingredient(id, STARTING_INGREDIENTS[id])


## Builds every room (floor + interactables) up front, plus the shared camera
## and player, then activates the starting room. See docs/design/systems.md,
## system 12 — scope is deliberately a couple of small interiors connected by
## stairs, not open-world; classes/love-interests stay VN-scene-only.
func _build_rooms() -> void:
	_build_shop_room()
	_build_bedroom_room()

	# Added after the rooms so they draw on top of each room's floor — 2D draw
	# order follows tree order, and rooms are siblings of the player/camera.
	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()

	_player = PLAYER_SCENE.instantiate()
	_player.add_to_group("player")
	add_child(_player)

	_switch_room(SHOP_ROOM_ID, SHOP_SPAWN)


func _build_shop_room() -> void:
	var room := _add_room(SHOP_ROOM_ID, Vector2(50, 50), Vector2(700, 500))

	_add_interactable(
		room, Interactable.Type.BREW_STATION, STATION_ID, "open brewing options",
		"Alembic", Color(0.8, 0.4, 0.2), Vector2(200, 150)
	)
	_add_interactable(
		room, Interactable.Type.STOCK_BOX, "", "stock the shop",
		"Stock Box", Color(0.4, 0.7, 0.4), Vector2(600, 150)
	)
	_add_interactable(
		room, Interactable.Type.SUPPLY_SHELF, "", "buy supplies",
		"Supply Shelf", Color(0.6, 0.5, 0.3), Vector2(600, 300)
	)
	_add_interactable(
		room, Interactable.Type.CLASS_DOOR, "", "attend class (if in session)",
		"Classroom Door", Color(0.7, 0.7, 0.2), Vector2(650, 450)
	)
	_add_stairs(
		room, BEDROOM_ROOM_ID, BEDROOM_SPAWN, "go upstairs to the Bedroom",
		"Stairs Up", Vector2(200, 450)
	)

	for i in Herbalism.plots.size():
		var plot: GrowPlotInstance = Herbalism.plots[i]
		_add_grow_plot_interactable(plot.id, Vector2(400, 150 + i * 120))


func _build_bedroom_room() -> void:
	var room := _add_room(BEDROOM_ROOM_ID, Vector2(50, 50), Vector2(700, 500))

	_add_interactable(
		room, Interactable.Type.BED, "", "sleep",
		"Bed", Color(0.3, 0.3, 0.7), Vector2(400, 200)
	)
	_add_stairs(
		room, SHOP_ROOM_ID, SHOP_SPAWN, "go downstairs to the Shop",
		"Stairs Down", Vector2(400, 450)
	)


## Creates a room container (floor + interactable holder), registers its
## camera center, and adds it to the scene tree, initially inactive.
func _add_room(room_id: String, floor_pos: Vector2, floor_size: Vector2) -> Node2D:
	var room := Node2D.new()
	room.name = room_id
	add_child(room)

	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.15, 0.15, 0.18)
	floor_rect.position = floor_pos
	floor_rect.size = floor_size
	room.add_child(floor_rect)

	_rooms[room_id] = room
	_room_camera_centers[room_id] = floor_pos + floor_size * 0.5
	room.visible = false
	room.process_mode = Node.PROCESS_MODE_DISABLED
	return room


func _add_interactable(
	parent: Node, type: Interactable.Type, target_id: String, prompt: String,
	display_name: String, color: Color, pos: Vector2
) -> Interactable:
	var interactable: Interactable = INTERACTABLE_SCENE.instantiate()
	interactable.interactable_type = type
	interactable.target_id = target_id
	interactable.prompt_text = prompt
	interactable.display_name = display_name
	interactable.visual_color = color
	interactable.position = pos
	parent.add_child(interactable)
	interactable.player_entered.connect(_on_player_entered_interactable)
	interactable.player_exited.connect(_on_player_exited_interactable)
	return interactable


func _add_stairs(
	parent: Node, target_room: String, spawn_position: Vector2, prompt: String,
	display_name: String, pos: Vector2
) -> Interactable:
	var interactable := _add_interactable(
		parent, Interactable.Type.STAIRS, "", prompt,
		display_name, Color(0.5, 0.5, 0.55), pos
	)
	interactable.target_room = target_room
	interactable.spawn_position = spawn_position
	return interactable


func _add_grow_plot_interactable(plot_id: String, pos: Vector2) -> void:
	var interactable := _add_interactable(
		_rooms[SHOP_ROOM_ID], Interactable.Type.GROW_PLOT, plot_id, "plant/harvest",
		plot_id, Color(0.3, 0.6, 0.3), pos
	)
	_plot_nodes[plot_id] = interactable
	_update_plot_label(plot_id)


## The one place rooms get (de)activated: toggles visibility + processing on
## the room containers, moves the shared player/camera, and clears any
## interaction state left over from the room we just left.
func _switch_room(room_id: String, spawn_position: Vector2) -> void:
	if _current_room_id != "":
		var previous_room: Node2D = _rooms[_current_room_id]
		previous_room.visible = false
		previous_room.process_mode = Node.PROCESS_MODE_DISABLED

	_current_interactable = null
	if _prompt_label:
		_prompt_label.text = ""
	if _menu_scene:
		_menu_scene.close()

	_current_room_id = room_id
	var room: Node2D = _rooms[room_id]
	room.visible = true
	room.process_mode = Node.PROCESS_MODE_INHERIT

	_player.position = spawn_position
	_camera.position = _room_camera_centers[room_id]

	SceneDirector.recheck()


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)

	# Resolve meter — top-left.
	var resolve_panel := PanelContainer.new()
	resolve_panel.position = Vector2(16, 16)
	hud.add_child(resolve_panel)

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
	hud.add_child(calendar_panel)

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

	# Game Over — stays directly on screen (terminal state), not in the menu.
	_game_over_label = Label.new()
	_game_over_label.add_theme_font_size_override("font_size", 24)
	_game_over_label.modulate = Color(1.0, 0.3, 0.3)
	_game_over_label.visible = false
	_game_over_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_game_over_label.position = Vector2(-250, 16)
	_game_over_label.custom_minimum_size = Vector2(500, 0)
	_game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(_game_over_label)

	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 20)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = Vector2(-150, -60)
	_prompt_label.custom_minimum_size = Vector2(300, 0)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(_prompt_label)

	# Everything else lives in the Escape menu instead of the HUD.
	_game_menu_content = VBoxContainer.new()

	_log_label = Label.new()
	_log_label.modulate = Color(0.8, 0.8, 0.8)
	_game_menu_content.add_child(_log_label)

	_game_menu_content.add_child(HSeparator.new())

	_ingredients_label = Label.new()
	_game_menu_content.add_child(_ingredients_label)

	_station_label = Label.new()
	_game_menu_content.add_child(_station_label)

	_potions_label = Label.new()
	_game_menu_content.add_child(_potions_label)

	_shop_label = Label.new()
	_game_menu_content.add_child(_shop_label)

	_skills_label = Label.new()
	_game_menu_content.add_child(_skills_label)

	_report_card_label = Label.new()
	_game_menu_content.add_child(_report_card_label)

	var hint := Label.new()
	hint.text = "WASD: move  |  E: interact  |  Esc: open/close menu  |  Space: pause  |  R: drain Resolve (debug)  |  Up/Down: tick rate"
	hint.modulate = Color(0.6, 0.6, 0.6)
	_game_menu_content.add_child(hint)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	_game_menu_content.add_child(quit_button)

	_brew_panel = VBoxContainer.new()
	for recipe in ContentRegistry.recipes:
		var button := Button.new()
		button.text = "Brew: %s" % recipe.display_name
		button.pressed.connect(_on_brew_button_pressed.bind(recipe))
		_brew_panel.add_child(button)
	var collect_button := Button.new()
	collect_button.text = "Collect from %s" % STATION_ID
	collect_button.pressed.connect(_on_collect_button_pressed)
	_brew_panel.add_child(collect_button)

	_supply_panel = VBoxContainer.new()
	for ingredient in ContentRegistry.ingredients:
		var ingredient_button := Button.new()
		ingredient_button.text = "Buy %s (%d)" % [ingredient.display_name, ingredient.buy_price]
		ingredient_button.pressed.connect(_on_buy_ingredient_button_pressed.bind(ingredient))
		_supply_panel.add_child(ingredient_button)
	for seed_def in ContentRegistry.seeds:
		var seed_button := Button.new()
		seed_button.text = "Buy %s (%d)" % [seed_def.display_name, seed_def.buy_price]
		seed_button.pressed.connect(_on_buy_seed_button_pressed.bind(seed_def))
		_supply_panel.add_child(seed_button)
	for upgrade in ContentRegistry.upgrades:
		var upgrade_button := Button.new()
		upgrade_button.text = "Buy upgrade: %s (%d)" % [upgrade.display_name, upgrade.cost]
		upgrade_button.pressed.connect(_on_buy_upgrade_button_pressed.bind(upgrade))
		_upgrade_buttons[upgrade.id] = upgrade_button
		_supply_panel.add_child(upgrade_button)

	_menu_scene = MenuScene.new()
	add_child(_menu_scene)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_SPACE:
			if not _menu_scene.is_open():
				Clock.is_paused = not Clock.is_paused
		KEY_ESCAPE:
			if _menu_scene.is_open():
				_menu_scene.close()
			else:
				_menu_scene.open(_game_menu_content, "Menu")
		KEY_E:
			_on_interact_pressed()
		KEY_R:
			Resolve.spend(20, "debug key")
		KEY_UP:
			Clock.tick_rate_minutes_per_second += 5.0
		KEY_DOWN:
			Clock.tick_rate_minutes_per_second = max(1.0, Clock.tick_rate_minutes_per_second - 5.0)


func _on_interact_pressed() -> void:
	if _current_interactable == null:
		return
	match _current_interactable.interactable_type:
		Interactable.Type.BREW_STATION:
			_toggle_menu(_brew_panel, "Brewing")
		Interactable.Type.SUPPLY_SHELF:
			_toggle_menu(_supply_panel, "Supplies")
		Interactable.Type.STOCK_BOX:
			_on_stock_button_pressed()
		Interactable.Type.BED:
			Clock.sleep()
		Interactable.Type.CLASS_DOOR:
			_attend_class()
		Interactable.Type.GROW_PLOT:
			_interact_grow_plot(_current_interactable.target_id)
		Interactable.Type.STAIRS:
			_switch_room(_current_interactable.target_room, _current_interactable.spawn_position)


func _toggle_menu(content: Control, title: String) -> void:
	if _menu_scene.has_content(content) and _menu_scene.is_open():
		_menu_scene.close()
	else:
		_menu_scene.open(content, title)


func _interact_grow_plot(plot_id: String) -> void:
	var plot := Herbalism.get_plot(plot_id)
	if plot.status == GrowPlotInstance.Status.READY_TO_HARVEST:
		_on_harvest_button_pressed(plot_id)
	elif plot.status == GrowPlotInstance.Status.EMPTY:
		if ContentRegistry.seeds.size() > 0:
			_on_plant_button_pressed(plot_id, ContentRegistry.seeds[0])
	else:
		_log_label.text = "%s is still growing." % plot_id


func _on_player_entered_interactable(interactable: Interactable) -> void:
	if _current_interactable != interactable:
		# Entering a different interactable always resets any menu left open
		# by the previous one — exit/enter signal order isn't guaranteed when
		# both fire on the same physics step (e.g. a large instantaneous move).
		_menu_scene.close()
	_current_interactable = interactable
	_prompt_label.text = "Press E: %s" % interactable.prompt_text


func _on_player_exited_interactable(interactable: Interactable) -> void:
	if _current_interactable != interactable:
		return
	_current_interactable = null
	_prompt_label.text = ""
	_menu_scene.close()


func _on_brew_button_pressed(recipe: RecipeDef) -> void:
	var error := Brewing.start_brew(STATION_ID, recipe)
	_log_label.text = "Couldn't brew %s: %s" % [recipe.display_name, error] if error != "" \
		else "Started brewing %s." % recipe.display_name
	_update_station_label()


func _on_collect_button_pressed() -> void:
	if not Brewing.collect(STATION_ID):
		_log_label.text = "Nothing ready to collect at %s." % STATION_ID
	_update_station_label()


func _on_stock_button_pressed() -> void:
	var stocked_count := Shop.stock_all_potions()
	_log_label.text = "Stocked %d potion(s)." % stocked_count if stocked_count > 0 \
		else "Nothing to stock (empty inventory or shop full)."
	_update_potions_label()
	_update_shop_label()


func _on_buy_ingredient_button_pressed(ingredient: IngredientDef) -> void:
	var error := Economy.buy_ingredient(ingredient)
	_log_label.text = "Couldn't buy %s: %s" % [ingredient.display_name, error] if error != "" \
		else "Bought 1 %s." % ingredient.display_name


func _on_buy_upgrade_button_pressed(upgrade: UpgradeDef) -> void:
	var error := Economy.purchase_upgrade(upgrade)
	_log_label.text = "Couldn't buy %s: %s" % [upgrade.display_name, error] if error != "" \
		else "Purchased upgrade: %s." % upgrade.display_name


func _on_buy_seed_button_pressed(seed_def: SeedDef) -> void:
	var error := Economy.buy_seed(seed_def)
	_log_label.text = "Couldn't buy %s: %s" % [seed_def.display_name, error] if error != "" \
		else "Bought 1 %s." % seed_def.display_name


func _on_plant_button_pressed(plot_id: String, seed_def: SeedDef) -> void:
	var error := Herbalism.plant(plot_id, seed_def)
	_log_label.text = "Couldn't plant in %s: %s" % [plot_id, error] if error != "" \
		else "Planted %s in %s." % [seed_def.display_name, plot_id]
	_update_plot_label(plot_id)


func _on_harvest_button_pressed(plot_id: String) -> void:
	if not Herbalism.harvest(plot_id):
		_log_label.text = "Nothing to harvest at %s." % plot_id
	_update_plot_label(plot_id)


func _attend_class() -> void:
	var error := Academy.attend_class()
	_log_label.text = "Couldn't attend class: %s" % error if error != "" \
		else "Attended class — running score up, Herbalism XP gained."
	_update_clock_label()
	_update_skills_label()
	_update_report_card_label()


func _on_minute_tick(_timestamp: int) -> void:
	_update_clock_label()
	_update_shop_label()
	_update_report_card_label()


func _on_day_started(day_number: int, day_type: int) -> void:
	_log_label.text = "Day %d (%s) begins." % [day_number, DAY_TYPE_NAMES[day_type]]
	_update_clock_label()
	print("Day %d (%s) begins." % [day_number, DAY_TYPE_NAMES[day_type]])


func _on_day_ended(reason: int) -> void:
	_log_label.text = "Day ended: %s" % END_REASON_NAMES[reason]
	print("Day ended: %s" % END_REASON_NAMES[reason])


func _on_brew_started(station_id: String, recipe_id: String) -> void:
	print("Brew started at %s: %s" % [station_id, recipe_id])


func _on_brew_ready(station_id: String, recipe_id: String) -> void:
	_log_label.text = "%s is ready at %s!" % [recipe_id, station_id]
	print("Brew ready at %s: %s" % [station_id, recipe_id])
	_update_station_label()


func _on_brew_collected(_station_id: String, recipe_id: String, potency: float, ease_value: float) -> void:
	print("Collected %s — potency %.1f, ease %.1f" % [recipe_id, potency, ease_value])
	_update_potions_label()
	_update_skills_label()


func _on_skill_leveled_up(skill_id: String, new_level: int) -> void:
	_log_label.text = "%s leveled up to %d!" % [skill_id.capitalize(), new_level]
	print("%s leveled up to %d." % [skill_id, new_level])
	_update_skills_label()


func _on_brew_botched(station_id: String, recipe_id: String) -> void:
	_log_label.text = "Brew botched at %s: %s! Resolve took a hit." % [station_id, recipe_id]
	print("Brew botched at %s: %s" % [station_id, recipe_id])
	_update_station_label()


func _on_resolve_changed(_current: int, _max_resolve: int) -> void:
	_update_resolve_meter()


func _on_strained_changed(is_strained: bool) -> void:
	if is_strained:
		_log_label.text = "Resolve is strained — all skill bonuses are halved."
	print("Strained: %s" % is_strained)
	_update_resolve_meter()


func _on_plot_added(plot_id: String) -> void:
	var index := Herbalism.plots.size() - 1
	_add_grow_plot_interactable(plot_id, Vector2(400, 150 + index * 120))


func _on_planted(plot_id: String, _seed_id: String) -> void:
	_update_plot_label(plot_id)


func _on_ready_to_harvest(plot_id: String, _seed_id: String) -> void:
	_log_label.text = "%s is ready to harvest!" % plot_id
	print("%s ready to harvest." % plot_id)
	_update_plot_label(plot_id)


func _on_harvested(plot_id: String, ingredient_id: String, quantity: int) -> void:
	_log_label.text = "Harvested %d %s from %s!" % [quantity, ingredient_id, plot_id]
	print("Harvested %d %s from %s." % [quantity, ingredient_id, plot_id])
	_update_ingredients_label()
	_update_skills_label()
	_update_plot_label(plot_id)


func _on_attended_class() -> void:
	print("Attended class.")


func _on_absence_recorded(absences: int) -> void:
	_log_label.text = "Missed class today. Absences: %d" % absences
	print("Absence recorded. Total: %d" % absences)
	_update_report_card_label()


func _on_exam_graded(passed: bool, score: float, strikes: int) -> void:
	_log_label.text = "Exam %s! Score: %.0f, Strikes: %d" % ["passed" if passed else "FAILED", score, strikes]
	print("Exam %s. Score: %.1f, Strikes: %d" % ["passed" if passed else "failed", score, strikes])
	_update_report_card_label()


func _on_game_over() -> void:
	_game_over_label.text = "GAME OVER — The Academy has revoked your selling privileges."
	_game_over_label.visible = true
	print("GAME OVER: strikes reached the limit.")
	_update_report_card_label()


func _on_inventory_changed(_ingredient_id: String, _quantity: int) -> void:
	_update_ingredients_label()


func _on_materials_changed(_amount: int) -> void:
	_update_materials_label()


func _on_upgrade_purchased(upgrade_id: String) -> void:
	var button: Button = _upgrade_buttons.get(upgrade_id)
	if button:
		button.disabled = true
		button.text += " [OWNED]"
	_update_station_label()


func _on_potion_stocked(_potion_id: String, _price: int) -> void:
	_update_shop_label()


func _on_potion_sold(potion_id: String, price: int) -> void:
	_log_label.text = "Sold %s for %d Materials!" % [potion_id, price]
	print("Sold %s for %d Materials." % [potion_id, price])
	_update_materials_label()
	_update_shop_label()


func _update_clock_label() -> void:
	var day_type_name: String = DAY_TYPE_NAMES[Clock.day_type()]
	_calendar_label.text = "Day %d (%s)" % [Clock.day_number, day_type_name]
	_time_label.text = "%s%s" % [
		Clock.get_clock_string(),
		" [PAUSED]" if Clock.is_paused else "",
	]


func _update_ingredients_label() -> void:
	var parts: Array[String] = []
	for id in STARTING_INGREDIENTS:
		parts.append("%s x%d" % [id, Inventory.ingredient_count(id)])
	_ingredients_label.text = "Inventory: %s" % ", ".join(parts)


func _update_materials_label() -> void:
	_materials_label.text = "Materials: %d" % Inventory.materials


func _update_station_label() -> void:
	var station := Brewing.get_station(STATION_ID)
	if station.current_job == null:
		_station_label.text = "%s: empty" % station.display_name
		return
	var job := station.current_job
	var status_name := "Brewing" if job.status == BrewJob.Status.BREWING else "Ready to collect"
	_station_label.text = "%s: %s (%s) — %s" % [
		station.display_name, job.recipe.display_name, status_name, Clock.get_clock_string()
	]


func _update_potions_label() -> void:
	var parts: Array[String] = []
	for potion in Inventory.potions:
		parts.append("%s (pot %.0f / ease %.0f)" % [potion.potion_id, potion.potency, potion.ease])
	_potions_label.text = "Potions: %s" % (", ".join(parts) if parts.size() > 0 else "none yet")


func _update_shop_label() -> void:
	var parts: Array[String] = []
	for slot in Shop.slots:
		parts.append("%s @ %d" % [slot.potion_id, slot.price])
	var stock_summary := ", ".join(parts) if parts.size() > 0 else "empty"
	var open_status := "OPEN" if Shop.is_open() else "closed"
	_shop_label.text = "Shop (%s) [%d/%d]: %s" % [open_status, Shop.slots.size(), Shop.capacity, stock_summary]


func _update_skills_label() -> void:
	var brewing_level := Skills.level("brewing")
	var brewing_xp := Skills.xp_for("brewing")
	var herbalism_level := Skills.level("herbalism")
	_skills_label.text = "Brewing: lvl %d (%d xp) | Herbalism: lvl %d" % [
		brewing_level, brewing_xp, herbalism_level
	]


func _update_resolve_meter() -> void:
	_resolve_bar.max_value = Resolve.max_resolve
	_resolve_bar.value = Resolve.current
	var strained_suffix := " [STRAINED]" if Resolve.is_strained() else ""
	_resolve_label.text = "Resolve: %d/%d%s" % [Resolve.current, Resolve.max_resolve, strained_suffix]


func _update_report_card_label() -> void:
	_report_card_label.text = "Report Card — score: %.0f/100 | strikes: %d/%d | absences: %d | next exam in %d day(s)" % [
		Academy.running_score, Academy.strikes, Academy.STRIKE_LIMIT, Academy.absences, Academy.days_until_exam()
	]


func _update_plot_label(plot_id: String) -> void:
	var interactable: Interactable = _plot_nodes.get(plot_id)
	if interactable == null:
		return
	var plot := Herbalism.get_plot(plot_id)
	var status_text := "empty"
	match plot.status:
		GrowPlotInstance.Status.GROWING:
			status_text = "growing %s" % plot.planted_seed.display_name
		GrowPlotInstance.Status.READY_TO_HARVEST:
			status_text = "ready to harvest (%s)" % plot.planted_seed.display_name
	interactable.set_status_text("%s\n%s" % [plot_id, status_text])
