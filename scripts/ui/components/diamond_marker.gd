class_name DiamondMarker
extends Control
## A diamond drawn directly via _draw() rather than a rotated ColorRect --
## Container.fit_child_in_rect() resets any child's rotation to 0 on every
## layout pass, so a rotated Control inside a GridContainer (as
## ContractBookInteractable's revision-count markers are) always renders back
## as a plain axis-aligned square no matter what rotation is set. Drawing the
## shape directly sidesteps that entirely.

@export var fill_color: Color = Color.WHITE:
	set(value):
		fill_color = value
		queue_redraw()


func _draw() -> void:
	var s := size
	var points := PackedVector2Array([
		Vector2(s.x * 0.5, 0.0),
		Vector2(s.x, s.y * 0.5),
		Vector2(s.x * 0.5, s.y),
		Vector2(0.0, s.y * 0.5),
	])
	draw_colored_polygon(points, fill_color)
