class_name DropShadowPanel
extends Panel
## The shadow node UiFx.add_drop_shadow() places behind a window. Mirrors its
## target's rect, scale, pivot, visibility, and alpha every frame, so any
## animation played on the target (the menus' unfurl open/close, fades, future
## bounces) carries its shadow along automatically — signal-based rect syncing
## can't see scale/modulate changes. Frees itself if the target goes away.

var target: Control


func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	position = target.position
	size = target.size
	scale = target.scale
	pivot_offset = target.pivot_offset
	visible = target.visible
	# self_modulate is included so a window whose own frame is hidden (e.g.
	# MenuScene's panel while the frame-ghost animates in its place) doesn't
	# cast a second shadow on top of the ghost's — the shadow belongs to the
	# box's own visual, not its children.
	modulate.a = target.modulate.a * target.self_modulate.a
