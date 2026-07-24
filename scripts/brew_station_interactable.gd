class_name BrewStationInteractable
extends InteractableBase
## See docs/design/systems.md, system 12. `target_id` is the Brewing station id.

const BREW_EMPTY_COLOR := Color(0.85, 0.2, 0.2)
const BREW_FULL_COLOR := Color(0.3, 0.85, 0.35)

## Cost to buy this station at its linked Alchemy Lab Manager (0 = already
## available). lab_manager_path is a plain NodePath (not a typed Node export)
## so scene instancing isn't restricted by Godot's typed-export checks — same
## convention as spawn_zone_path on the spawner nodes.
@export var cost: int = 0
@export var lab_manager_path: NodePath

@onready var _brew_progress_container: Panel = $BrewProgressContainer
@onready var _brew_progress: ProgressBar = $BrewProgressContainer/BrewProgress
@onready var _brew_ready_popup: Label = $BrewReadyPopup

## The fill StyleBoxFlat is shared from the scene by default -- duplicated
## per instance so recoloring one station's bar doesn't bleed into every
## other station using this scene.
var _brew_fill_style: StyleBoxFlat


func _ready() -> void:
	super._ready()
	add_to_group("alembic_interactables")
	_brew_fill_style = _brew_progress.get_theme_stylebox("fill").duplicate()
	_brew_progress.add_theme_stylebox_override("fill", _brew_fill_style)


## A station with no job open the brew menu; a finished one auto-collects
## (failing quietly if there's no potion room); a still-brewing one can't be
## interacted with at all. A not-yet-purchased station can't be interacted
## with at all — it's bought through its linked Alchemy Lab Manager instead.
func interact(main: MainScene) -> void:
	var station := Brewing.get_station(target_id)
	if station != null and not station.purchased:
		main.hud.log_message("This Alembic hasn't been purchased yet — visit the Alchemy Lab Manager.")
		return
	var job := station.current_job if station else null
	if job == null:
		main.hud.toggle_brew_menu(target_id)
	elif job.status == BrewJob.Status.READY:
		if not Brewing.collect(target_id):
			main.hud.log_message("Inventory is full — couldn't collect the potion.")
	else:
		main.hud.log_message("Still brewing — check back later.")


## A bottom-to-top fill while brewing, swapping to a "Ready!" popup once the
## job completes. The fill color lerps red -> green as it climbs, so the bar
## reads a bit like a potion vial topping off.
func set_brew_progress(fraction: float) -> void:
	_brew_ready_popup.visible = false
	_brew_progress_container.visible = true
	var f := clampf(fraction, 0.0, 1.0)
	_brew_progress.value = f
	_brew_fill_style.bg_color = BREW_EMPTY_COLOR.lerp(BREW_FULL_COLOR, f)


func show_brew_ready() -> void:
	_brew_progress_container.visible = false
	_brew_ready_popup.visible = true


func clear_brew_indicator() -> void:
	_brew_progress_container.visible = false
	_brew_ready_popup.visible = false
