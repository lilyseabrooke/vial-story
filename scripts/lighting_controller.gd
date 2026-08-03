class_name RoomLighting
extends Node
## Owns the single world-space color-grading overlay that gives every room
## its lighting. See docs/design/systems.md, system 24. All rooms share one
## origin and only one is ever visible at a time (RoomBuilder.switch_room),
## so one overlay covering the whole world is enough — no per-room node
## needed. Instanced and owned by RoomBuilder, same "plain Node child,
## setup(self)" shape as NPCDirector/CustomerDirector.
##
## The overlay is a screen-space CanvasLayer + ColorRect running
## shaders/day_night_grading.gdshader, not a CanvasModulate — CanvasModulate
## is a flat multiply over every pixel regardless of how bright it already
## is, which is what made a moody night tint read as crushing the whole
## scene uniformly. The shader instead splits by luminance so only genuinely
## dark pixels pull toward the shadow tint. Layer 1, explicitly below
## GameHud's layer 2 (see hud.gd) — see the shader header for why draw order
## has to land after the world but before any UI CanvasLayer.
const GRADING_SHADER := preload("res://shaders/day_night_grading.gdshader")

## Room-switch transitions overshoot past the target before settling, like
## eyes adapting to a sudden brightness change, rather than tweening straight
## there. This is the fast "snap past it" leg; profile.transition_seconds is
## reused as the slower "settle back" leg's duration. Ordinary minute-tick
## re-sampling within a room never overshoots -- only an actual room switch
## (set_profile) does.
const ROOM_SWITCH_OVERSHOOT_FACTOR := 1.4
const ROOM_SWITCH_OVERSHOOT_SECONDS := 0.18

var _canvas_layer: CanvasLayer
var _overlay: ColorRect
var _material: ShaderMaterial
var _active_profile: LightingProfileDef
var _tween: Tween
## Overnight/collapse jumps tick minute_tick dozens of times in one frame
## (Clock._skip_overnight_to_next_day_start) while the screen is held black —
## tweening through every one of those is wasted motion nobody sees, so
## color changes during a skip snap instantly instead.
var _in_time_skip: bool = false


func setup(room_builder: RoomBuilder) -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 1
	room_builder.add_child(_canvas_layer)

	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = GRADING_SHADER
	_overlay.material = _material
	_canvas_layer.add_child(_overlay)

	Clock.minute_tick.connect(_on_minute_tick)
	Clock.time_skip_started.connect(func() -> void: _in_time_skip = true)
	Clock.time_skip_finished.connect(func() -> void: _in_time_skip = false)


## Called by RoomBuilder.switch_room() with the newly-active room's profile.
## Overshoots past the target and settles back rather than tweening straight
## there -- see ROOM_SWITCH_OVERSHOOT_FACTOR's doc comment.
func set_profile(profile: LightingProfileDef) -> void:
	_active_profile = profile
	var values := _values_for(profile)
	var currents := {}
	var overshoots := {}
	for param in values:
		currents[param] = _current_value(param, values[param])
		overshoots[param] = _overshoot(currents[param], values[param], ROOM_SWITCH_OVERSHOOT_FACTOR)

	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	# Two explicit groups, not one loop that alternates chain() per param --
	# chain() marks a breakpoint on the Tween's own timeline (not per-key), so
	# interleaving it inside a single loop would stagger each param's legs
	# against its *neighbors'* legs instead of running all three overshoot
	# legs together, then all three settle legs together.
	for param in values:
		_tween.tween_method(_shader_setter(param), currents[param], overshoots[param], ROOM_SWITCH_OVERSHOOT_SECONDS) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.chain()
	for param in values:
		_tween.tween_method(_shader_setter(param), overshoots[param], values[param], profile.transition_seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_minute_tick(_timestamp: int) -> void:
	if _active_profile == null or _active_profile.time_of_day_strength <= 0.0:
		return
	var values := _values_for(_active_profile)
	var duration := 0.0 if _in_time_skip else _active_profile.transition_seconds
	_kill_tween()
	if duration <= 0.0:
		for param in values:
			_material.set_shader_parameter(param, values[param])
		return
	_tween = create_tween()
	_tween.set_parallel(true)
	for param in values:
		_tween.tween_method(_shader_setter(param), _current_value(param, values[param]), values[param], duration)


## Returns {shadow_tint, highlight_tint, contrast} for the profile's current
## moment: the base_* values blended toward the gradient/curve sample by
## time_of_day_strength (0 = base only, same as the old STATIC mode; 1 = pure
## time-of-day, same as the old TIME_OF_DAY mode).
func _values_for(profile: LightingProfileDef) -> Dictionary:
	var shadow_tint := profile.base_shadow_color
	var highlight_tint := profile.base_highlight_color
	var contrast := profile.base_contrast
	if profile.time_of_day_strength > 0.0:
		var day_fraction := Clock.minute_of_day() / float(Clock.MINUTES_PER_CALENDAR_DAY - 1)
		var t := profile.time_of_day_strength
		if profile.day_night_shadow_gradient != null:
			shadow_tint = shadow_tint.lerp(profile.day_night_shadow_gradient.sample(day_fraction), t)
		if profile.day_night_highlight_gradient != null:
			highlight_tint = highlight_tint.lerp(profile.day_night_highlight_gradient.sample(day_fraction), t)
		if profile.contrast_curve != null:
			contrast = lerpf(contrast, profile.contrast_curve.sample(day_fraction), t)
	return {"shadow_tint": shadow_tint, "highlight_tint": highlight_tint, "contrast": contrast}


## Shoots `factor` times past `to` (relative to `from`) for the fast leg of a
## room-switch transition -- e.g. factor 1.4 lands 40% further than the real
## target in the same direction, so the settle leg has somewhere to ease back
## from. Works for both Color and float shader params since both support the
## same +/-/* arithmetic.
func _overshoot(from, to, factor: float):
	return from + (to - from) * factor


## tween_property(_material, "shader_parameter/%s" % param, ...) looks like
## the obvious way to tween a shader uniform, but Godot compiles shaders
## asynchronously -- right after _material.shader is assigned (setup()),
## the shader_parameter/* properties aren't registered for tween_property's
## reflection yet, even though direct get/set_shader_parameter() calls work
## immediately. switch_room() -> set_profile() fires in that same frame, so
## tween_property() silently returned null there and crashed on the
## following .set_trans() call. tween_method() calls set_shader_parameter()
## directly instead of going through property reflection, sidestepping the
## whole problem.
func _shader_setter(param: String) -> Callable:
	return func(value) -> void: _material.set_shader_parameter(param, value)


## get_shader_parameter() returns null before the shader has finished its
## first (async) compile, e.g. the very first set_profile() call in the same
## frame as setup() -- tween_method() needs its "from" value to already be
## the same type as "to" (Color/float), so null has to be papered over with
## fallback before it ever reaches a tween.
func _current_value(param: String, fallback):
	var current = _material.get_shader_parameter(param)
	return fallback if current == null else current


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
