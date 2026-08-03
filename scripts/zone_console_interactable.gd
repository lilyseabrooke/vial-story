class_name ZoneConsoleInteractable
extends InteractableBase
## Entry point into Build Mode for its linked PlacementZone. See
## docs/design/systems.md, system 4 (Placement System). Purchasing, upgrade
## browsing, and placement all live inside Build Mode itself now
## (BuildModeController) -- this interactable has no menu of its own,
## `zone_id` is a direct export, so there's no scene-graph lookup needed.

@export var zone_id: String


func interact(main: MainScene) -> void:
	main.hud.enter_build_mode(zone_id)
