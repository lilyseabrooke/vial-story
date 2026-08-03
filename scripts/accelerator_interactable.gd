class_name AcceleratorInteractable
extends InteractableBase
## Purchasable zone component that boosts every orthogonally-adjacent Alembic's
## brew speed (Placement.adjacency_bonus(), see docs/design/systems.md, system
## 4). Has no active use of its own -- interact() is flavor-only -- it exists
## purely to occupy a grid cell and be visually present; the actual bonus is
## computed live by Placement from grid adjacency, never stored on this node.


func interact(main: MainScene) -> void:
	main.hud.log_message("Boosts adjacent Alembics' brew speed.")
