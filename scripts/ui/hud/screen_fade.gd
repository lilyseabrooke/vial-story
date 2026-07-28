class_name ScreenFade
extends CanvasLayer
## Full-screen black overlay for time-skip transitions (sleep, Resolve
## collapse, late-night collapse, attending class) — see Clock's
## time_skip_started/time_skip_finished signals. Fades to black, holds a
## beat, then fades back in. Layer sits above MenuScene (layer 10) so it can
## cover menu chrome too, since attending class is triggered from inside
## class_panel. Timings are read from Clock.TIME_SKIP_FADE_SECONDS/
## TIME_SKIP_HOLD_SECONDS (not owned here) so this animation lines up exactly
## with the window Clock holds ticking and the actual jump work for — the
## jump only happens once the screen is fully black, right as the fade-out
## tween below finishes.
##
## Blocks mouse input for the duration (not just visual) so a stray click
## can't reach anything mid-transition.

var _rect: ColorRect
var _tween: Tween


func build() -> void:
	layer = 50
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.modulate.a = 0.0
	add_child(_rect)


func play() -> void:
	if _tween:
		_tween.kill()
	_rect.modulate.a = 0.0
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 1.0, Clock.TIME_SKIP_FADE_SECONDS)
	_tween.tween_interval(Clock.TIME_SKIP_HOLD_SECONDS)
	_tween.tween_property(_rect, "modulate:a", 0.0, Clock.TIME_SKIP_FADE_SECONDS)
	_tween.tween_callback(func() -> void:
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)
