class_name GardenManagerInteractable
extends InteractableBase
## Sells and upgrades the Grow Plot(s)/Water Pump(s) linked to it. See
## docs/design/systems.md, system 7. The link lives on each item's own side
## (GrowPlotInteractable/WaterPumpInteractable.lab_manager_path), so this
## discovers its items by scanning the "grow_plot_interactables"/
## "water_pump_interactables" groups for nodes whose lab_manager_path
## resolves back to this node, rather than holding a list of its own -- same
## shape as AlchemyLabManagerInteractable.


func interact(main: MainScene) -> void:
	var items: Array[Dictionary] = []
	for p in get_tree().get_nodes_in_group("grow_plot_interactables"):
		if p.get_node_or_null(p.lab_manager_path) == self:
			items.append({"id": p.target_id, "kind": "grow_plot"})
	for w in get_tree().get_nodes_in_group("water_pump_interactables"):
		if w.get_node_or_null(w.lab_manager_path) == self:
			items.append({"id": w.target_id, "kind": "water_pump"})
	main.hud.open_garden_menu(items)
