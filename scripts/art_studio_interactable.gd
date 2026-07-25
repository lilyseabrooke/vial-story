class_name ArtStudioInteractable
extends InteractableBase
## See docs/design/systems.md, the Art Studio / Creativity System section.
## `target_id` is the ArtStudio studio id.

## Soft gold, dimmer -> brighter, for both the gathering-inspiration (ROLLING)
## and the working (WORKING) bars -- one shared meter, same "one bar, two
## phases" shape as ContractBookInteractable's writing/revising meter.
const METER_EMPTY_COLOR := Color(0.45, 0.38, 0.16)
const METER_FULL_COLOR := Color(0.92, 0.78, 0.35)

@onready var _progress_container: Panel = $ProgressContainer
@onready var _progress: ProgressBar = $ProgressContainer/Progress
@onready var _ready_popup: Label = $ReadyPopup

## The fill StyleBoxFlat is shared from the scene by default -- duplicated per
## instance so recoloring one studio's bar doesn't bleed into every other
## studio using this scene.
var _fill_style: StyleBoxFlat


func _ready() -> void:
	super._ready()
	_fill_style = _progress.get_theme_stylebox("fill").duplicate()
	_progress.add_theme_stylebox_override("fill", _fill_style)


## No job -> start a gathering-inspiration session. Still ROLLING -> nothing
## to do yet. CHOOSING (the bar's full and Inspirations are waiting) -> open
## the picker. WORKING -> open the discard-confirm prompt rather than
## resolving anything, so re-pressing E never silently loses progress.
func interact(main: MainScene) -> void:
	var job := ArtStudio.get_job(target_id)
	if job == null:
		ArtStudio.start_session(target_id)
		main.hud.log_message("You settle in and wait for inspiration to strike...")
	elif job.phase == ArtStudioJob.Phase.ROLLING:
		main.hud.log_message("Still waiting for inspiration to strike...")
	elif job.phase == ArtStudioJob.Phase.CHOOSING:
		main.hud.toggle_art_studio_picker(target_id)
	else:
		main.hud.toggle_art_studio_discard_confirm(target_id)


func set_progress(fraction: float) -> void:
	_ready_popup.visible = false
	_progress_container.visible = true
	var f := clampf(fraction, 0.0, 1.0)
	_progress.value = f
	_fill_style.bg_color = METER_EMPTY_COLOR.lerp(METER_FULL_COLOR, f)


func show_ready_to_choose() -> void:
	_progress_container.visible = false
	_ready_popup.visible = true


func clear_indicator() -> void:
	_progress_container.visible = false
	_ready_popup.visible = false
