class_name RollPipGauge
extends Control
## Row of pips under RollDisplay's dice/modifier/DC line -- how many degrees
## of success (green, filling left-to-right) or degrees of failure (red) a
## roll produced past its DC (see Rng.roll_2d10()'s degrees_of_success/
## degrees_of_failure). Exactly one color is ever nonzero for a given roll.
## Capped at MAX_PIPS; a roll with more degrees than that just shows MAX_PIPS.
## Only ever draws filled pips -- no dim/empty placeholders out to the cap --
## and resizes itself to exactly however many pips that is, so a small check
## doesn't leave a bunch of empty circles (or dead space) sitting next to the
## DC label it shares a line with.

const MAX_PIPS := 10
const PIP_RADIUS := 4.0
const PIP_GAP := 5.0

var _filled_count := 0
var _fill_color: Color = UiPalette.SUCCESS


func set_degrees(degrees_of_success: int, degrees_of_failure: int) -> void:
	if degrees_of_success > 0:
		_filled_count = mini(degrees_of_success, MAX_PIPS)
		_fill_color = UiPalette.SUCCESS
	else:
		_filled_count = mini(degrees_of_failure, MAX_PIPS)
		_fill_color = UiPalette.DANGER

	var width := 0.0
	if _filled_count > 0:
		width = _filled_count * (PIP_RADIUS * 2.0) + (_filled_count - 1) * PIP_GAP
	custom_minimum_size.x = width
	queue_redraw()


func _draw() -> void:
	var y := size.y * 0.5
	for i in _filled_count:
		var x := PIP_RADIUS + i * (PIP_RADIUS * 2.0 + PIP_GAP)
		draw_circle(Vector2(x, y), PIP_RADIUS, _fill_color)
