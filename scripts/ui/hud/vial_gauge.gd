class_name VialGauge
extends Control
## Flat-drawn potion-vial gauge standing in for the Resolve meter until the
## hand-drawn vial art lands (three aligned PNGs → a TextureProgressBar, per the
## plan's art-swap step). Draws a stoppered glass vial that fills bottom-to-top
## with mauve — the palette's reserved "magic" color, apt for Resolve. When
## strained, the outline turns to the warning amber and thickens.

const STOPPER_H := 8.0
const NECK_H := 6.0

var _fraction := 1.0
var _strained := false


func set_values(fraction: float, strained: bool) -> void:
	_fraction = clampf(fraction, 0.0, 1.0)
	_strained = strained
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# Body of the vial (below the neck/stopper).
	var body_top := STOPPER_H + NECK_H
	var body_rect := Rect2(w * 0.18, body_top, w * 0.64, h - body_top - 2.0)

	var outline := UiPalette.WARNING if _strained else UiPalette.WARM_WALNUT
	var outline_w := 2.5 if _strained else 1.5

	# Glass back.
	draw_rect(body_rect, Color(UiPalette.DRIFTWOOD_TAN.r, UiPalette.DRIFTWOOD_TAN.g, UiPalette.DRIFTWOOD_TAN.b, 0.5), true)
	# Mauve liquid, filling from the bottom.
	var fill_h := body_rect.size.y * _fraction
	var fill_rect := Rect2(body_rect.position.x, body_rect.position.y + body_rect.size.y - fill_h, body_rect.size.x, fill_h)
	draw_rect(fill_rect, UiPalette.MAUVE_POTION, true)
	# A lighter meniscus line at the top of the liquid.
	if _fraction > 0.02 and _fraction < 0.99:
		var y := fill_rect.position.y
		draw_line(Vector2(fill_rect.position.x, y), Vector2(fill_rect.position.x + fill_rect.size.x, y), UiPalette.LAVENDER_MIST, 1.5, true)
	# Glass outline.
	draw_rect(body_rect, outline, false, outline_w)

	# Neck + stopper.
	var neck_rect := Rect2(w * 0.34, STOPPER_H, w * 0.32, NECK_H + 1.0)
	draw_rect(neck_rect, outline, false, outline_w)
	var stopper_rect := Rect2(w * 0.30, 0.0, w * 0.40, STOPPER_H)
	draw_rect(stopper_rect, UiPalette.HONEY_OAK, true)
	draw_rect(stopper_rect, outline, false, outline_w)
