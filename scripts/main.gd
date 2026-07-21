class_name MainScene
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
const STARTING_SCRAP_COUNT := 3
const STARTING_SCRAP_QUALITY_RANGE := Vector2(20.0, 100.0)

var room_builder: RoomBuilder
var hud: GameHud
var _current_interactable: InteractableBase = null


func _ready() -> void:
	print("Vial Story: main scene ready")
	if GameFlow.is_new_game:
		Rng.seed_new_game()
		_grant_starting_ingredients()
		_grant_starting_scrap()
		_grant_starting_quests()
	_start_game(Color(PlayerProfile.player_color_hex))


func _start_game(player_color: Color) -> void:
	room_builder = RoomBuilder.new()
	add_child(room_builder)
	room_builder.build_rooms()
	room_builder.player_entered_interactable.connect(_on_player_entered_interactable)
	room_builder.player_exited_interactable.connect(_on_player_exited_interactable)
	room_builder.player.get_node("Visual").color = player_color

	hud = GameHud.new()
	add_child(hud)
	hud.build(STATION_ID, STARTING_INGREDIENTS)

	Herbalism.ready_to_harvest.connect(_on_ready_to_harvest)
	Herbalism.harvested.connect(_on_harvested)


func _grant_starting_ingredients() -> void:
	for id in STARTING_INGREDIENTS:
		Inventory.add_ingredient(id, STARTING_INGREDIENTS[id])


## Scrap has no other sourcing method yet (see docs/design/systems.md,
## Transmutation / Workbench System) -- this is the only way to get any in
## the prototype, same stopgap role STARTING_INGREDIENTS plays for ingredients.
func _grant_starting_scrap() -> void:
	for i in STARTING_SCRAP_COUNT:
		Inventory.add_scrap(Rng.range_f(STARTING_SCRAP_QUALITY_RANGE.x, STARTING_SCRAP_QUALITY_RANGE.y))


func _grant_starting_quests() -> void:
	for id in STARTING_QUESTS:
		QuestManager.start_quest(id)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_SPACE:
			if not hud.is_menu_open():
				Clock.is_paused = not Clock.is_paused
		KEY_ESCAPE:
			hud.toggle_game_menu()
		KEY_E:
			_on_interact_pressed()
		KEY_R:
			Resolve.spend(20, "debug key")
		KEY_1:
			Clock.set_speed_level(0)
		KEY_2:
			Clock.set_speed_level(1)
		KEY_3:
			Clock.set_speed_level(2)


func _on_interact_pressed() -> void:
	if _current_interactable == null:
		return
	_current_interactable.interact(self)


## The one place rooms get switched: resets interaction/menu state left over
## from the room we're leaving, then hands off to RoomBuilder for the actual
## room/camera/player move. Called by StairsInteractable.interact().
func switch_room(room_id: String, spawn_position: Vector2) -> void:
	_current_interactable = null
	hud.set_prompt("")
	hud.close_menu()
	room_builder.switch_room(room_id, spawn_position)


func _on_player_entered_interactable(interactable: InteractableBase) -> void:
	if _current_interactable != interactable:
		# Entering a different interactable always resets any menu left open
		# by the previous one — exit/enter signal order isn't guaranteed when
		# both fire on the same physics step (e.g. a large instantaneous move).
		hud.close_menu()
	_current_interactable = interactable
	hud.set_prompt("Press E: %s" % interactable.prompt_text)


func _on_player_exited_interactable(interactable: InteractableBase) -> void:
	if _current_interactable != interactable:
		return
	_current_interactable = null
	hud.set_prompt("")
	hud.close_menu()


func _on_ready_to_harvest(plot_id: String, _seed_id: String) -> void:
	hud.log_message("%s is ready to harvest!" % plot_id)
	print("%s ready to harvest." % plot_id)
	room_builder.update_plot_label(plot_id)


func _on_harvested(plot_id: String, ingredient_id: String, quantity: int) -> void:
	hud.log_message("Harvested %d %s from %s!" % [quantity, ingredient_id, plot_id])
	print("Harvested %d %s from %s." % [quantity, ingredient_id, plot_id])
	hud.update_ingredients_label()
	hud.update_skills_label()
	room_builder.update_plot_label(plot_id)
