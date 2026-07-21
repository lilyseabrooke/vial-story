class_name GrowPlotInteractable
extends InteractableBase
## See docs/design/systems.md, system 12. `target_id` is the GrowPlotInstance id.


func interact(main: MainScene) -> void:
	var plot := Herbalism.get_plot(target_id)
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
