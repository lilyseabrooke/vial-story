class_name CircleMarker
extends Control
## A flat filled circle drawn via _draw() -- placeholder for the character
## profile portrait ResolveVial's Gauge will sit under. Swap for a real
## portrait TextureRect once that art exists.

@export var fill_color: Color = Color.WHITE:
	set(value):
		fill_color = value
		queue_redraw()


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5
	draw_circle(size * 0.5, radius, fill_color)
