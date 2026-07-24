class_name LeyLineNodeInteractable
extends InteractableBase
## See docs/design/systems.md, the Ley Line Node System section. `target_id`
## is the LeyLines node id; `meditation_minutes`/`surge_ids`/`surge_weights`
## are this particular node's per-instance meditation tuning, passed straight
## through to LeyLines.start_meditation() -- different nodes can be tuned to
## fill faster/slower or favor different Surges with no code change.
## `surge_ids`/`surge_weights` are parallel arrays (not a Dictionary) so
## they're hand-authorable in the inspector, same convention as
## IngredientDef's characteristic_ids/characteristic_values.
##
## Player-tethered like DragonStashInteractable -- interact() only ever starts
## meditating, RoomBuilder wires this node's player_exited straight to
## LeyLines.cancel_meditation(), which throws the whole bar away, so walking
## away mid-meditation forces a full restart from empty. Unlike a Dragon's
## Stash this node is never destroyed -- meditating here is repeatable
## indefinitely, only a passed Arcane History check against a rolled Surge
## ever ends the loop (by handing off to the minigame). hud.gd opens the
## minigame panel in response to LeyLines.minigame_started once that happens.

const METER_EMPTY_COLOR := Color(0.55, 0.7, 0.85)
const METER_FULL_COLOR := Color(0.6, 0.85, 0.95)

@export var meditation_minutes: int = 10
@export var surge_ids: Array[String] = []
@export var surge_weights: Array[float] = []

@onready var _meditation_progress_container: Panel = $MeditationProgressContainer
@onready var _meditation_progress: ProgressBar = $MeditationProgressContainer/MeditationProgress

## Duplicated per instance so recoloring one node's bar doesn't bleed into
## every other node using this scene -- same reasoning as DragonStash's meter.
var _meter_fill_style: StyleBoxFlat
var _progress_tween: Tween


func _ready() -> void:
	super._ready()
	_meter_fill_style = _meditation_progress.get_theme_stylebox("fill").duplicate()
	_meditation_progress.add_theme_stylebox_override("fill", _meter_fill_style)


## No job yet -> start meditating. A session already meditating can't be
## re-triggered or hurried along -- there's nothing to submit, it just has to
## fill while the player stays put (walking away cancels it entirely, see
## RoomBuilder). A minigame already running elsewhere blocks a new
## meditation too, though that shouldn't normally happen since MenuScene
## freezes the player for the whole minigame.
func interact(main: MainScene) -> void:
	if LeyLines.is_active():
		main.hud.log_message("The ley line is still resonating -- let it settle first.")
		return
	if LeyLines.get_meditation_job(target_id) != null:
		main.hud.log_message("You're already deep in meditation -- don't wander off.")
		return
	LeyLines.start_meditation(target_id, meditation_minutes, surge_ids, surge_weights)
	main.hud.log_message("You settle into meditation at the ley line... don't wander off.")


func set_meditation_progress(fraction: float) -> void:
	_meditation_progress_container.visible = true
	var f := clampf(fraction, 0.0, 1.0)
	_meter_fill_style.bg_color = METER_EMPTY_COLOR.lerp(METER_FULL_COLOR, f)

	if _progress_tween:
		_progress_tween.kill()
	var duration := 1.0 / maxf(Clock.tick_rate_minutes_per_second, 0.01)
	_progress_tween = create_tween()
	_progress_tween.tween_property(_meditation_progress, "value", f, duration)


## Called on LeyLines.meditation_bar_full, strictly before the job's own
## reset/erase -- sets the meter straight to 1.0 with no tween, so whatever
## comes next (a reset's set_meditation_progress(0.0), or the bar just being
## hidden via clear_meditation_indicator() once the minigame starts) has a
## true full value to animate away from or replace, instead of racing an
## in-flight tween that never gets a rendered frame at 1.0.
func snap_meditation_full() -> void:
	_meditation_progress_container.visible = true
	if _progress_tween:
		_progress_tween.kill()
	_meter_fill_style.bg_color = METER_FULL_COLOR
	_meditation_progress.value = 1.0


func clear_meditation_indicator() -> void:
	if _progress_tween:
		_progress_tween.kill()
	_meditation_progress.value = 0.0
	_meditation_progress_container.visible = false
