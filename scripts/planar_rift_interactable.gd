class_name PlanarRiftInteractable
extends InteractableBase
## See docs/design/systems.md, the Summoning / Planar Rift System section.
## `target_id` is the rift id.

const RIFT_EMPTY_COLOR := Color(0.15, 0.65, 0.65)
const RIFT_FULL_COLOR := Color(0.7, 0.3, 0.9)

@onready var _rift_progress_container: Panel = $RiftProgressContainer
@onready var _rift_progress: ProgressBar = $RiftProgressContainer/RiftProgress
@onready var _rift_ready_popup: Label = $RiftReadyPopup

## The fill StyleBoxFlat is shared from the scene by default -- duplicated
## per instance so recoloring one rift's bar doesn't bleed into every other
## rift using this scene.
var _rift_fill_style: StyleBoxFlat


func _ready() -> void:
	super._ready()
	_rift_fill_style = _rift_progress.get_theme_stylebox("fill").duplicate()
	_rift_progress.add_theme_stylebox_override("fill", _rift_fill_style)


## A rift with no job open opens the summoning minigame (which, on a matched
## sequence, starts the job); a finished one collects its bundle; a still-
## summoning one can't be interacted with at all. The same three-way shape
## BrewStationInteractable uses, with the minigame standing in for "start".
func interact(main: MainScene) -> void:
	var job := Summoning.get_job(target_id)
	if job == null:
		# Ignore a re-press while the minigame is already open -- main.gd's E
		# hotkey fires alongside the panel's own E (wipe) handler, and the
		# panel freezes the player here for the whole session anyway.
		if not Summoning.is_minigame_active():
			Summoning.open_rift_minigame(target_id)
	elif job.status == PlanarRiftJob.Status.READY:
		Summoning.collect_rift(target_id)
	else:
		main.hud.log_message("The rift is still drawing something through -- check back later.")


func set_rift_progress(fraction: float) -> void:
	_rift_ready_popup.visible = false
	_rift_progress_container.visible = true
	var f := clampf(fraction, 0.0, 1.0)
	_rift_progress.value = f
	_rift_fill_style.bg_color = RIFT_EMPTY_COLOR.lerp(RIFT_FULL_COLOR, f)


func show_rift_ready() -> void:
	_rift_progress_container.visible = false
	_rift_ready_popup.visible = true


func clear_rift_indicator() -> void:
	_rift_progress_container.visible = false
	_rift_ready_popup.visible = false
