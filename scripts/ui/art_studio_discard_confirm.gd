class_name ArtStudioDiscardConfirm
extends VBoxContainer
## MenuScene content opened by ArtStudioInteractable on a select-press mid
## WORKING — asks whether to throw away the current piece's progress, so a
## player who realizes they don't have time for it isn't stuck grinding it
## out. See docs/design/systems.md, the Art Studio / Creativity System
## section. Wraps the shared ConfirmPanel component (docs/engine_roadmap.md,
## Phase 7) instead of building its own message label + two buttons.

signal discard_confirmed(studio_id: String)
signal kept(studio_id: String)

var _studio_id: String = ""
var _panel: ConfirmPanel


func build() -> void:
	_panel = preload("res://scenes/ui/components/ConfirmPanel.tscn").instantiate()
	_panel.confirm_text = "Discard progress"
	_panel.cancel_text = "Keep working"
	_panel.confirmed.connect(func() -> void: discard_confirmed.emit(_studio_id))
	_panel.cancelled.connect(func() -> void: kept.emit(_studio_id))
	add_child(_panel)


func open_for(studio_id: String) -> void:
	_studio_id = studio_id
	var job := ArtStudio.get_job(studio_id)
	var def := ContentRegistry.get_inspiration(job.inspiration_id) if job != null else null
	var name := def.display_name if def != null else "this piece"
	_panel.set_message("Discard your progress on %s? This can't be undone." % name)
