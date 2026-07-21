extends Node2D
## Wires the autoload systems to the world (RoomBuilder) and the presentation
## layer (GameHud). Most signal handling lives in those two scripts now —
## this file keeps only the bits that cross both, plus input dispatch.
##
## Reached only from scripts/main_menu.gd, which has already either run
## CharacterCreator + SaveManager.create_new_game() (new game) or
## SaveManager.load_game()/quick_load_latest() (loaded game) before switching
## to this scene. GameFlow.is_new_game is the one bit of hand-off state that
## distinguishes the two here: a new game needs its starting ingredients
## granted, a loaded game already has Inventory restored and must not get
## them twice.

const STATION_ID := "alembic_1"
const STARTING_INGREDIENTS := {
	"moonpetal": 3,
	"iron_filings": 3,
	"ghostcap_mushroom": 3,
}
const STARTING_QUESTS := ["first_brew", "stock_the_shelf"]

var _room_builder: RoomBuilder
var _hud: GameHud
var _current_interactable: Interactable = null


func _ready() -> void:
	print("Vial Story: main scene ready")
	if GameFlow.is_new_game:
		Rng.seed_new_game()
		_grant_starting_ingredients()
		_grant_starting_quests()
	_start_game(Color(PlayerProfile.player_color_hex))


func _start_game(player_color: Color) -> void:
	_room_builder = RoomBuilder.new()
	add_child(_room_builder)
	_room_builder.build_rooms()
	_room_builder.player_entered_interactable.connect(_on_player_entered_interactable)
	_room_builder.player_exited_interactable.connect(_on_player_exited_interactable)
	_room_builder.player.get_node("Visual").color = player_color

	_hud = GameHud.new()
	add_child(_hud)
	_hud.build(STATION_ID, STARTING_INGREDIENTS)

	Herbalism.ready_to_harvest.connect(_on_ready_to_harvest)
	Herbalism.harvested.connect(_on_harvested)


func _grant_starting_ingredients() -> void:
	for id in STARTING_INGREDIENTS:
		Inventory.add_ingredient(id, STARTING_INGREDIENTS[id])


func _grant_starting_quests() -> void:
	for id in STARTING_QUESTS:
		QuestManager.start_quest(id)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_SPACE:
			if not _hud.is_menu_open():
				Clock.is_paused = not Clock.is_paused
		KEY_ESCAPE:
			_hud.toggle_game_menu()
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
			_interact_brew_station(_current_interactable.target_id)
		Interactable.Type.SUPPLY_SHELF:
			_hud.toggle_menu(_hud.supply_panel, "Supplies")
		Interactable.Type.STOCK_BOX:
			_hud.on_stock_button_pressed()
		Interactable.Type.BED:
			Clock.sleep()
		Interactable.Type.CLASS_DOOR:
			_hud.attend_class()
		Interactable.Type.GROW_PLOT:
			_interact_grow_plot(_current_interactable.target_id)
		Interactable.Type.STAIRS:
			_switch_room(_current_interactable.target_room, _current_interactable.spawn_position)


## A station with no job open the brew menu; a finished one auto-collects
## (failing quietly if there's no potion room); a still-brewing one can't be
## interacted with at all.
func _interact_brew_station(station_id: String) -> void:
	var station := Brewing.get_station(station_id)
	var job := station.current_job if station else null
	if job == null:
		_hud.toggle_menu(_hud.brew_panel, "Brewing")
	elif job.status == BrewJob.Status.READY:
		if not Brewing.collect(station_id):
			_hud.log_message("Inventory is full — couldn't collect the potion.")
	else:
		_hud.log_message("Still brewing — check back later.")


func _interact_grow_plot(plot_id: String) -> void:
	var plot := Herbalism.get_plot(plot_id)
	if plot.status == GrowPlotInstance.Status.READY_TO_HARVEST:
		if not Herbalism.harvest(plot_id):
			_hud.log_message("Nothing to harvest at %s." % plot_id)
		_room_builder.update_plot_label(plot_id)
	elif plot.status == GrowPlotInstance.Status.EMPTY:
		if ContentRegistry.seeds.size() > 0:
			var seed_def: SeedDef = ContentRegistry.seeds[0]
			var error := Herbalism.plant(plot_id, seed_def)
			_hud.log_message("Couldn't plant in %s: %s" % [plot_id, error] if error != "" \
				else "Planted %s in %s." % [seed_def.display_name, plot_id])
			_room_builder.update_plot_label(plot_id)
	else:
		_hud.log_message("%s is still growing." % plot_id)


## The one place rooms get switched: resets interaction/menu state left over
## from the room we're leaving, then hands off to RoomBuilder for the actual
## room/camera/player move.
func _switch_room(room_id: String, spawn_position: Vector2) -> void:
	_current_interactable = null
	_hud.set_prompt("")
	_hud.close_menu()
	_room_builder.switch_room(room_id, spawn_position)


func _on_player_entered_interactable(interactable: Interactable) -> void:
	if _current_interactable != interactable:
		# Entering a different interactable always resets any menu left open
		# by the previous one — exit/enter signal order isn't guaranteed when
		# both fire on the same physics step (e.g. a large instantaneous move).
		_hud.close_menu()
	_current_interactable = interactable
	_hud.set_prompt("Press E: %s" % interactable.prompt_text)


func _on_player_exited_interactable(interactable: Interactable) -> void:
	if _current_interactable != interactable:
		return
	_current_interactable = null
	_hud.set_prompt("")
	_hud.close_menu()


func _on_ready_to_harvest(plot_id: String, _seed_id: String) -> void:
	_hud.log_message("%s is ready to harvest!" % plot_id)
	print("%s ready to harvest." % plot_id)
	_room_builder.update_plot_label(plot_id)


func _on_harvested(plot_id: String, ingredient_id: String, quantity: int) -> void:
	_hud.log_message("Harvested %d %s from %s!" % [quantity, ingredient_id, plot_id])
	print("Harvested %d %s from %s." % [quantity, ingredient_id, plot_id])
	_hud.update_ingredients_label()
	_hud.update_skills_label()
	_room_builder.update_plot_label(plot_id)
