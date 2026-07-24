class_name AlchemyLabManagerInteractable
extends InteractableBase
## Sells and upgrades the Alembic(s)/Pantry(ies) linked to it. See
## docs/design/systems.md, system 4. The link lives on each item's own side
## (BrewStationInteractable/PantryInteractable.lab_manager_path), so this
## discovers its items by scanning the "alembic_interactables"/
## "pantry_interactables" groups for nodes whose lab_manager_path resolves
## back to this node, rather than holding a list of its own.


func interact(main: MainScene) -> void:
	var items: Array[Dictionary] = []
	for a in get_tree().get_nodes_in_group("alembic_interactables"):
		if a.get_node_or_null(a.lab_manager_path) == self:
			items.append({"id": a.target_id, "kind": "alembic"})
	for p in get_tree().get_nodes_in_group("pantry_interactables"):
		if p.get_node_or_null(p.lab_manager_path) == self:
			items.append({"id": p.target_id, "kind": "pantry"})
	main.hud.open_alchemy_lab_menu(items)
