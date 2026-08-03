class_name PantryInteractable
extends InteractableBase
## Purchasable ingredient storage placed in a placement zone. See
## docs/design/systems.md, system 4. `target_id` is the Inventory pantry id
## (also its Placement ComponentInstance id) -- this node is only ever
## instantiated once a component exists (Placement.component_placed), so
## there's no "not yet purchased" state left to check. Every Alembic placed
## in the same zone treats this Pantry's stock as available for brewing
## (Brewing._linked_pantries()).


func interact(main: MainScene) -> void:
	main.hud.toggle_pantry_menu(target_id)
