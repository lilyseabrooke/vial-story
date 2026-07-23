class_name ScrapHeapInteractable
extends InteractableBase
## See docs/design/systems.md, the Transmutation / Workbench System section
## (Scrap Heap). `target_id` is the Transmutation heap id.
##
## Player-tethered exactly like DragonStashInteractable -- interact() only
## ever starts the dig, resolution and the Scrap/ingredient grant happen
## automatically once Transmutation.get_heap_job(target_id) reaches its
## minutes_required, and RoomBuilder wires this node's player_exited straight
## to Transmutation.cancel_heap(), which throws the whole job away, so
## walking away mid-dig forces a full restart (and a freshly rolled hidden
## quality) rather than freezing progress in place. This node is queue_free'd
## by RoomBuilder in response to Transmutation.heap_resolved, not by anything
## called here.

const METER_EMPTY_COLOR := Color(0.3, 0.2, 0.12)
const METER_FULL_COLOR := Color(1.0, 0.84, 0.0)

@onready var _heap_progress_container: Panel = $HeapProgressContainer
@onready var _heap_progress: ProgressBar = $HeapProgressContainer/HeapProgress

## Duplicated per instance so recoloring one heap's bar doesn't bleed into
## every other heap using this scene -- same reasoning as DragonStash's fill
## style.
var _meter_fill_style: StyleBoxFlat

## Same tween-to-smooth-a-short-bar reasoning as DragonStashInteractable's
## _progress_tween -- HEAP_MINUTES is only 5, so snapping value on every tick
## would read as a staircase rather than a fill.
var _progress_tween: Tween


func _ready() -> void:
	super._ready()
	_meter_fill_style = _heap_progress.get_theme_stylebox("fill").duplicate()
	_heap_progress.add_theme_stylebox_override("fill", _meter_fill_style)


## No job yet -> start digging. A dig already underway can't be re-triggered
## or hurried along -- there's nothing to submit, it just has to finish while
## the player stays put (walking away cancels it entirely, see RoomBuilder).
func interact(main: MainScene) -> void:
	if Transmutation.get_heap_job(target_id) != null:
		main.hud.log_message("The heap is already shifting -- best not to disturb it yet.")
		return
	Transmutation.start_heap(target_id)
	main.hud.log_message("You start picking through the Scrap Heap... don't wander off.")


func set_heap_progress(fraction: float) -> void:
	_heap_progress_container.visible = true
	var f := clampf(fraction, 0.0, 1.0)
	_meter_fill_style.bg_color = METER_EMPTY_COLOR.lerp(METER_FULL_COLOR, f)

	if _progress_tween:
		_progress_tween.kill()
	var duration := 1.0 / maxf(Clock.tick_rate_minutes_per_second, 0.01)
	_progress_tween = create_tween()
	_progress_tween.tween_property(_heap_progress, "value", f, duration)


func clear_heap_indicator() -> void:
	if _progress_tween:
		_progress_tween.kill()
	_heap_progress.value = 0.0
	_heap_progress_container.visible = false
