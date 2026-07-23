class_name TimeOfDayIcon
extends Control
## Tiny self-contained sun/moon indicator for the AlmanacClock — a butter-yellow
## sun with rays during shop hours, a lavender crescent at night. Drawn in code
## (no font glyphs, no art dependency) so it reads at any resolution; a real
## hand-drawn sun/moon can replace this later by swapping to a TextureRect.

var _is_day := true


func set_day(is_day: bool) -> void:
	if is_day == _is_day:
		return
	_is_day = is_day
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.32
	if _is_day:
		draw_circle(c, r, UiPalette.BUTTER_SUN)
		draw_arc(c, r, 0.0, TAU, 24, UiPalette.GOLD, 1.5, true)
		for i in 8:
			var a := TAU * i / 8.0
			var d := Vector2(cos(a), sin(a))
			draw_line(c + d * (r + 2.0), c + d * (r + 5.0), UiPalette.GOLD, 1.5, true)
	else:
		draw_circle(c, r, UiPalette.LAVENDER_MIST)
		# Crescent bite: overdraw with the card's cream fill.
		draw_circle(c + Vector2(r * 0.55, -r * 0.35), r * 0.95, UiPalette.CREAM_PAGE)
