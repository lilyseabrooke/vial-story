class_name VialGauge
extends Control
## Resolve meter drawn as a filling potion vial: three layered nodes (Under/
## ProgressBar/Over, see VialGauge.tscn) rather than a single
## TextureProgressBar's texture_under/progress/over slots, so the strained
## HSV shift (shaders/hsv_shift.gdshader) can target the fill layer alone and
## leave the glass/frame art untouched. Under and Over fill the node via
## anchors; ProgressBar's texture_progress_offset is deliberately smaller
## than the frame (the fill shouldn't touch every pixel of the meter, or
## it'd overrun it) — adjust sizing/offset/textures in VialGauge.tscn, not
## here.

const _STRAINED_SHADER := preload("res://shaders/hsv_shift.gdshader")
const _STRAINED_HUE_SHIFT_DEGREES := 40.0
const _STRAINED_SATURATION_SHIFT := 0.2
const _STRAINED_VALUE_SHIFT := .1

# Value change polish: the fill slides to its new level instead of jumping,
# with a quick overbright flash while draining (tint_color > 1 genuinely
# brightens past the texture's own color) and a slower, gentler brighten
# while healing standing in for a soft glow. Drain reads faster than heal in
# both the slide and the pulse, on purpose -- taking damage should feel
# sharp, recovering should feel unhurried.
const _DRAIN_SLIDE_DURATION := 0.3
const _HEAL_SLIDE_DURATION := 0.7
const _DRAIN_FLASH_COLOR := Color(1.7, 1.3, 1.5, 1.0)
const _DRAIN_FLASH_DURATION := 0.2
const _HEAL_GLOW_COLOR := Color(1.3, 1.3, 1.15, 1.0)
const _HEAL_GLOW_DURATION := 0.9

# Steady warning strobe while strained: a slow, subtle amber breathe, looping
# for as long as strained stays true. Separate uniform from tint_color above
# so the two never fight over the same tween.
const _STRAIN_STROBE_PEAK_COLOR := Color(1.08, 0.98, 0.78, 1.0)
const _STRAIN_STROBE_HALF_PERIOD := 0.9

@onready var _progress_bar: TextureProgressBar = $ProgressBar

var _base_size: Vector2
var _base_progress_offset: Vector2
var _progress_material: ShaderMaterial
var _value_tween: Tween
var _flash_tween: Tween
var _strobe_tween: Tween
var _is_strained := false


func _ready() -> void:
	_base_size = size
	_base_progress_offset = _progress_bar.texture_progress_offset
	_progress_material = ShaderMaterial.new()
	_progress_material.shader = _STRAINED_SHADER
	_progress_bar.material = _progress_material
	# A shader_parameter/* path isn't tweenable until it's been explicitly
	# set once -- relying on the shader's own uniform default isn't enough
	# for Tween's property lookup to see it.
	_progress_material.set_shader_parameter("tint_color", Color.WHITE)
	_progress_material.set_shader_parameter("strobe_tint", Color.WHITE)


func set_values(fraction: float, strained: bool) -> void:
	var target := clampf(fraction, 0.0, 1.0)
	var delta := target - _progress_bar.value
	if not is_zero_approx(delta):
		var is_heal := delta > 0.0
		_slide_value_to(target, _HEAL_SLIDE_DURATION if is_heal else _DRAIN_SLIDE_DURATION)
		_play_change_flash(is_heal)
	_progress_material.set_shader_parameter("hue_shift_degrees", _STRAINED_HUE_SHIFT_DEGREES if strained else 0.0)
	_progress_material.set_shader_parameter("saturation_shift", _STRAINED_SATURATION_SHIFT if strained else 0.0)
	_progress_material.set_shader_parameter("value_shift", _STRAINED_VALUE_SHIFT if strained else 0.0)
	if strained != _is_strained:
		_is_strained = strained
		if strained:
			_start_strain_strobe()
		else:
			_stop_strain_strobe()


func _slide_value_to(target: float, duration: float) -> void:
	if _value_tween:
		_value_tween.kill()
	_value_tween = create_tween()
	_value_tween.tween_property(_progress_bar, "value", target, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _play_change_flash(is_heal: bool) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_progress_material.set_shader_parameter("tint_color", Color.WHITE)
	var peak_color := _HEAL_GLOW_COLOR if is_heal else _DRAIN_FLASH_COLOR
	var duration := _HEAL_GLOW_DURATION if is_heal else _DRAIN_FLASH_DURATION
	_flash_tween = create_tween()
	_flash_tween.tween_property(_progress_material, "shader_parameter/tint_color", peak_color, duration * 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(_progress_material, "shader_parameter/tint_color", Color.WHITE, duration * 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _start_strain_strobe() -> void:
	if _strobe_tween:
		_strobe_tween.kill()
	_strobe_tween = create_tween()
	_strobe_tween.set_loops()
	_strobe_tween.tween_property(_progress_material, "shader_parameter/strobe_tint", _STRAIN_STROBE_PEAK_COLOR, _STRAIN_STROBE_HALF_PERIOD) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_strobe_tween.tween_property(_progress_material, "shader_parameter/strobe_tint", Color.WHITE, _STRAIN_STROBE_HALF_PERIOD) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_strain_strobe() -> void:
	if _strobe_tween:
		_strobe_tween.kill()
		_strobe_tween = null
	_progress_material.set_shader_parameter("strobe_tint", Color.WHITE)


## Grows the vial around the size authored in VialGauge.tscn. Under/Over fill
## the node via anchors and rescale for free; only the fill's offset margin
## needs manual rescaling to stay proportional to the new size.
func set_size_scale(size_scale: float) -> void:
	size = _base_size * size_scale
	custom_minimum_size = _base_size * size_scale
	_progress_bar.texture_progress_offset = _base_progress_offset * size_scale
