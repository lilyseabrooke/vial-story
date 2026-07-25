extends Node
## Transient hand-off state between the main menu and the gameplay scene.
## Autoloaded as "GameFlow". Not part of any save payload — it only carries
## "which game is active" and "did we just create it or just load it" across
## the res://scenes/MainMenu.tscn -> res://scenes/Main.tscn scene switch, so
## main.gd knows whether to grant starting ingredients (new game) or trust
## the state SaveManager.load_game()/quick_load_latest() already restored
## (loaded game). See docs/design/systems.md, system 14.

var game_id: String = ""
var is_new_game: bool = false

## Mirrors RoomBuilder.current_room_id -- RoomBuilder isn't an autoload, so
## this is how VNExpressionEvaluator's current_room() condition function
## reaches it. Not part of the save payload -- switch_room() re-sets it the
## moment a loaded game restores the player's room.
var current_room_id: String = ""


func set_current_room(room_id: String) -> void:
	current_room_id = room_id
