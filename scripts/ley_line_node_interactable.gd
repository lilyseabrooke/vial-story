class_name LeyLineNodeInteractable
extends InteractableBase
## See docs/design/systems.md, the Ley Line Node System section. `target_id`
## is the LeyLines node id; `difficulty`/`rounds` are this particular node's
## per-instance minigame modifiers, passed straight through to
## LeyLines.start_minigame() -- different nodes can be tuned harder/longer
## without any code change.
##
## No progress meter, no tether -- interact() just hands off to LeyLines and
## hud.gd opens the minigame panel in response to LeyLines.minigame_started. A session already active blocks a second
## start; that shouldn't normally happen since MenuScene freezes the player
## for the whole interaction, but re-pressing E at this very node while its
## own session is active would otherwise silently no-op start_minigame(), so
## this logs instead.

@export var difficulty: float = 1.0
@export var rounds: int = 3


func interact(main: MainScene) -> void:
	if LeyLines.is_active():
		main.hud.log_message("The ley line is still resonating -- let it settle first.")
		return
	LeyLines.start_minigame(target_id, difficulty, rounds)
