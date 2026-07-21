class_name ContractBookInteractable
extends InteractableBase
## See docs/design/systems.md, the Demonology / Contract System section.
## `target_id` is the Demonology writ/book id.

## Deep midnight indigo rather than near-black -- stays visible against the
## meter's own dark panel background even when the fill is nearly empty.
const METER_EMPTY_COLOR := Color(0.16, 0.13, 0.4)
const METER_FULL_COLOR := Color(0.55, 0.25, 0.85)
const DIAMONDS_PER_GRID := 9

@onready var _writ_progress_container: Panel = $WritProgressContainer
@onready var _writ_progress: ProgressBar = $WritProgressContainer/WritProgress
@onready var _ones_diamonds: GridContainer = $OnesDiamonds
@onready var _tens_diamonds: GridContainer = $TensDiamonds

## The fill StyleBoxFlat is shared from the scene by default -- duplicated
## per instance so recoloring one book's meter doesn't bleed into every
## other book using this scene.
var _meter_fill_style: StyleBoxFlat


func _ready() -> void:
	super._ready()
	_meter_fill_style = _writ_progress.get_theme_stylebox("fill").duplicate()
	_writ_progress.add_theme_stylebox_override("fill", _meter_fill_style)


## No writ open -> start one. A writ that's actively being worked on and has
## finished its first draft submits on a second E-press; one still on its
## first (WRITING) pass has nothing to submit yet, so a second press just
## pauses it instead. A paused writ resumes on the next press. Walking away
## (InteractableBase.player_exited, wired to Demonology.pause_writ() in
## RoomBuilder) always pauses regardless of any of this.
func interact(main: MainScene) -> void:
	var writ := Demonology.get_writ(target_id)
	if writ == null:
		Demonology.start_writ(target_id)
		main.hud.log_message("You begin drafting a writ with the Contract Book...")
	elif writ.is_working:
		if writ.can_submit():
			Demonology.submit_writ(target_id)
		else:
			Demonology.pause_writ(target_id)
			main.hud.log_message("You set the quill down mid-draft.")
	else:
		Demonology.resume_writ(target_id)
		main.hud.log_message("You return to the writ.")


## A bottom-to-top fill while writing/revising, midnight -> violet, plus the
## diamond grids for completed revisions. Used for both phases (WRITING and
## REVISING) -- the only difference is REVISING can also be submitted. Paused
## writs just freeze the bar/diamonds at their current values -- no separate
## overlay needed, a stopped meter already reads as paused on its own.
func set_writ_progress(fraction: float, revisions_completed: int) -> void:
	_writ_progress_container.visible = true
	var f := clampf(fraction, 0.0, 1.0)
	_writ_progress.value = f
	_meter_fill_style.bg_color = METER_EMPTY_COLOR.lerp(METER_FULL_COLOR, f)
	_update_diamonds(revisions_completed)


func clear_writ_indicator() -> void:
	_writ_progress_container.visible = false
	_update_diamonds(0)


func _update_diamonds(revisions_completed: int) -> void:
	var ones := revisions_completed % 10
	@warning_ignore("integer_division")
	var tens := mini(revisions_completed / 10, DIAMONDS_PER_GRID)
	_set_diamond_row(_ones_diamonds, ones)
	# Tens sits to the left of the meter -- filled right-to-left (reversed)
	# so both grids grow outward from the meter at the center, rather than
	# the tens grid growing away from it.
	_set_diamond_row(_tens_diamonds, tens, true)


func _set_diamond_row(grid: GridContainer, filled_count: int, reversed: bool = false) -> void:
	var children := grid.get_children()
	for i in children.size():
		var index := children.size() - 1 - i if reversed else i
		children[index].visible = i < filled_count
