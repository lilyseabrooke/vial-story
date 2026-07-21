class_name DragonStashInteractable
extends InteractableBase
## See docs/design/systems.md, the Draconology / Dragon's Stash System
## section. `target_id` is the Draconology stash id.
##
## Player-tethered like ContractBookInteractable -- interact() only ever
## starts the dig, resolution and the ingredient grant happen automatically
## once Draconology.get_job(target_id) reaches its minutes_required -- but
## unlike the Contract Book, there's no pause/resume: RoomBuilder wires this
## node's player_exited straight to Draconology.cancel_stash(), which throws
## the whole job away, so walking away mid-dig forces a full restart (and a
## freshly rolled hidden quality) rather than freezing progress in place.
## This node is queue_free'd by RoomBuilder in response to
## Draconology.stash_resolved, not by anything called here.

const METER_EMPTY_COLOR := Color(0.75, 0.9, 0.7)
const METER_FULL_COLOR := Color(0.5, 0.08, 0.2)

@onready var _stash_progress_container: Panel = $StashProgressContainer
@onready var _stash_progress: ProgressBar = $StashProgressContainer/StashProgress

## Duplicated per instance so recoloring one stash's bar doesn't bleed into
## every other stash using this scene -- same reasoning as BrewStation/
## ContractBook's fill styles.
var _meter_fill_style: StyleBoxFlat

## STASH_MINUTES is only 5, so at the default tick rate each minute_tick is
## just ~0.4 real seconds apart -- snapping ProgressBar.value straight to the
## new fraction on every tick reads as a visible stair-step rather than a
## fill, especially on a bar this short. Tweening from the current value to
## the new one over roughly one tick's real-world duration smooths that out
## into what still looks like a continuous fill, without needing Draconology
## to know or care about real time at all -- it only ever moves in whole
## per-minute steps.
var _progress_tween: Tween


func _ready() -> void:
	super._ready()
	_meter_fill_style = _stash_progress.get_theme_stylebox("fill").duplicate()
	_stash_progress.add_theme_stylebox_override("fill", _meter_fill_style)


## No job yet -> start digging. A dig already underway can't be re-triggered
## or hurried along -- there's nothing to submit, it just has to finish while
## the player stays put (walking away cancels it entirely, see RoomBuilder).
func interact(main: MainScene) -> void:
	if Draconology.get_job(target_id) != null:
		main.hud.log_message("Something stirs in the stash -- best not to disturb it yet.")
		return
	Draconology.start_stash(target_id)
	main.hud.log_message("You start digging through the Dragon's Stash... don't wander off.")


func set_stash_progress(fraction: float) -> void:
	_stash_progress_container.visible = true
	var f := clampf(fraction, 0.0, 1.0)
	_meter_fill_style.bg_color = METER_EMPTY_COLOR.lerp(METER_FULL_COLOR, f)

	if _progress_tween:
		_progress_tween.kill()
	var duration := 1.0 / maxf(Clock.tick_rate_minutes_per_second, 0.01)
	_progress_tween = create_tween()
	_progress_tween.tween_property(_stash_progress, "value", f, duration)


func clear_stash_indicator() -> void:
	if _progress_tween:
		_progress_tween.kill()
	_stash_progress.value = 0.0
	_stash_progress_container.visible = false
