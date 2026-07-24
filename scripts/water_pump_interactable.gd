class_name WaterPumpInteractable
extends InteractableBase
## See docs/design/systems.md, system 7. `target_id` is the WaterPumpInstance
## id. Unlike a Pantry, there's no routine deposit/withdraw use here -- once
## purchased, a Water Pump passively boosts every Grow Plot sharing its
## Garden Manager, so interact() is purely informational; purchasing it and
## its upgrades both happen at the Garden Manager.

## Cost to buy this pump at its linked Garden Manager (0 = already
## available). lab_manager_path is a plain NodePath (not a typed Node export)
## so scene instancing isn't restricted by Godot's typed-export checks — same
## convention as PantryInteractable.lab_manager_path.
@export var cost: int = 2000
@export var lab_manager_path: NodePath


func _ready() -> void:
	super._ready()
	add_to_group("water_pump_interactables")


func interact(main: MainScene) -> void:
	var pump := Herbalism.get_water_pump(target_id)
	if pump != null and not pump.purchased:
		main.hud.log_message("This Water Pump hasn't been purchased yet — visit the Garden Manager.")
	else:
		main.hud.log_message("The Water Pump boosts every linked plot's harvest yield.")
