class_name SupplyShelfInteractable
extends InteractableBase
## See docs/design/systems.md, system 12.


func interact(main: MainScene) -> void:
	main.hud.toggle_menu(main.hud.supply_panel, "Supplies")
