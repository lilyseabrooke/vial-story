class_name ClassDoorInteractable
extends InteractableBase
## See docs/design/systems.md, system 12.


func interact(main: MainScene) -> void:
	main.hud.open_class_menu()
