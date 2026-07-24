class_name GrowPlotInteractable
extends InteractableBase
## See docs/design/systems.md, system 12. `target_id` is the GrowPlotInstance id.

## Cost to buy this plot at its linked Garden Manager (0 = already
## available). lab_manager_path is a plain NodePath (not a typed Node export)
## so scene instancing isn't restricted by Godot's typed-export checks — same
## convention as lab_manager_path on BrewStationInteractable/PantryInteractable.
@export var cost: int = 0
@export var lab_manager_path: NodePath


func _ready() -> void:
	super._ready()
	add_to_group("grow_plot_interactables")


## A not-yet-purchased plot can't be interacted with at all — it's bought
## through its linked Garden Manager instead.
func interact(main: MainScene) -> void:
	var plot := Herbalism.get_plot(target_id)
	if plot != null and not plot.purchased:
		main.hud.log_message("This plot hasn't been purchased yet — visit the Garden Manager.")
		return
	if plot.status == GrowPlotInstance.Status.READY_TO_HARVEST:
		if not Herbalism.harvest(target_id):
			main.hud.log_message("Nothing to harvest at %s." % target_id)
		main.room_builder.update_plot_label(target_id)
	elif plot.status == GrowPlotInstance.Status.EMPTY:
		if ContentRegistry.seeds.size() > 0:
			var seed_def: SeedDef = ContentRegistry.seeds[0]
			var error := Herbalism.plant(target_id, seed_def)
			main.hud.log_message("Couldn't plant in %s: %s" % [target_id, error] if error != "" \
				else "Planted %s in %s." % [seed_def.display_name, target_id])
			main.room_builder.update_plot_label(target_id)
	else:
		main.hud.log_message("%s is still growing." % target_id)
