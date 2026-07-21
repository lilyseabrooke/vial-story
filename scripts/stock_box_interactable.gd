class_name StockBoxInteractable
extends InteractableBase
## See docs/design/systems.md, system 12.


func interact(main: MainScene) -> void:
	main.hud.on_stock_button_pressed()
