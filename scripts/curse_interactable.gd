class_name CurseInteractable
extends InteractableBase
## See docs/design/systems.md, system 11. Hand-placed for the prototype (no
## random spawn location yet) — target_id (from InteractableBase) is this
## instance's unique placement id, while curse_id optionally pins which
## CurseDef it manifests as; leave curse_id blank to have Curse.activate()
## pick randomly from data/curses.json instead.
##
## Active (and its penalties applied to Shop) from the moment this node
## enters the tree, and stays that way until the player assembles a
## satisfying ingredient combination at the curse panel (see CursePanel).

@export var curse_id: String = ""


func _ready() -> void:
	super._ready()
	Curse.curse_dispelled.connect(_on_curse_dispelled)
	Curse.activate(target_id, curse_id)


func interact(main: MainScene) -> void:
	if not Curse.is_active(target_id):
		main.hud.log_message("This curse has already been dispelled.")
		return
	main.hud.toggle_curse_menu(target_id)


func _on_curse_dispelled(instance_id: String, _curse_id: String) -> void:
	if instance_id == target_id:
		set_status_text("(dispelled)")
