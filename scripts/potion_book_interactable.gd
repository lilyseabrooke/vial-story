class_name PotionBookInteractable
extends InteractableBase
## See docs/design/systems.md, system 3 (recipe-discovery puzzle). Opens the
## "Discover" menu — attempting the drag-and-drop puzzle for an unlearned
## recipe. Brewing itself stays at the Alembic (BrewStationInteractable).


func interact(main: MainScene) -> void:
	main.hud.toggle_menu(main.hud.discover_panel, "Potion Book")
