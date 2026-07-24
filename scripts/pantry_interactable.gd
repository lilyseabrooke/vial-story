class_name PantryInteractable
extends InteractableBase
## Purchasable ingredient storage linked to an Alchemy Lab Manager. See
## docs/design/systems.md, system 4. `target_id` is the Inventory pantry id.
## Once purchased, every Alembic linked to the same manager treats this
## Pantry's stock as available for brewing (Brewing._linked_pantries()).

## Cost to buy this Pantry at its linked Alchemy Lab Manager (0 = already
## available). lab_manager_path is a plain NodePath (not a typed Node export)
## so scene instancing isn't restricted by Godot's typed-export checks — same
## convention as BrewStationInteractable.lab_manager_path.
@export var cost: int = 0
@export var lab_manager_path: NodePath


func _ready() -> void:
	super._ready()
	add_to_group("pantry_interactables")


## A not-yet-purchased Pantry can't be opened -- it's bought through its
## linked Alchemy Lab Manager instead, same split as an unpurchased Alembic.
func interact(main: MainScene) -> void:
	var pantry := Inventory.get_pantry(target_id)
	if pantry != null and not pantry.purchased:
		main.hud.log_message("This Pantry hasn't been purchased yet — visit the Alchemy Lab Manager.")
		return
	main.hud.toggle_pantry_menu(target_id)
