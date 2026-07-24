class_name AlchemyLabManagerInteractable
extends InteractableBase
## Sells and upgrades the Alembic(s) linked to it. See docs/design/systems.md,
## system 4. The link lives on the Alembic side (BrewStationInteractable.
## lab_manager_path), so this discovers its stations by scanning the
## "alembic_interactables" group for nodes whose lab_manager_path resolves
## back to this node, rather than holding a list of its own.


func interact(main: MainScene) -> void:
	var station_ids: Array[String] = []
	for a in get_tree().get_nodes_in_group("alembic_interactables"):
		if a.get_node_or_null(a.lab_manager_path) == self:
			station_ids.append(a.target_id)
	main.hud.open_alchemy_lab_menu(station_ids)
