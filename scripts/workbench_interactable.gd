class_name WorkbenchInteractable
extends InteractableBase
## See docs/design/systems.md, the Transmutation / Workbench System section.
##
## An instant one-shot action, same shape as StockBoxInteractable -- no menu,
## no multi-phase job. Success feedback (dice popup + ingredient log) is
## driven off Transmutation.scrap_broken_down in hud.gd, same pattern as
## Demonology.writ_submitted; only the "nothing to break down" case needs
## handling here since no signal fires for it.

func interact(main: MainScene) -> void:
	var result := Transmutation.break_down_scrap()
	if result.is_empty():
		main.hud.log_message("No Scrap to break down.")
