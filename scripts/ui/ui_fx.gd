class_name UiFx
extends RefCounted
## Small static UI-effect helpers, never instanced (same convention as UiPalette).

## Adds a soft drop shadow behind `target`. StyleBoxTexture has no shadow_*
## properties (only StyleBoxFlat does), so the wood-framed windows can't draw
## their own — this places a mouse-transparent DropShadowPanel immediately
## behind the target: a StyleBoxFlat with an invisible center and only its
## shadow showing, which mirrors the target's rect/scale/visibility/alpha every
## frame (see drop_shadow_panel.gd) so window animations carry it along.
## Must be called after `target` has a parent.
##
## Defaults are sized for the big framed windows; HUD-card callers pass smaller
## values (the shadow should scale with the thing casting it).
##
## Placement depends on the parent's type:
## - Plain parent (CanvasLayer, Control): inserted as a sibling at the
##   target's index, so it draws immediately behind the target.
## - Container parent (VBoxContainer etc.): a sibling would become a layout
##   item of its own, so the target is swapped for a MarginContainer wrapper
##   holding shadow + target overlaid in the same rect — the container lays
##   out the wrapper, and the wrapper keeps the pair aligned.
static func add_drop_shadow(target: Control, shadow_alpha := 0.45, size_px := 13, offset := Vector2(0, 8)) -> void:
	var parent := target.get_parent()
	if parent == null:
		push_error("UiFx.add_drop_shadow: target must be added to a parent first.")
		return

	var shadow := DropShadowPanel.new()
	shadow.target = target
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.shadow_color = Color(UiPalette.COCOA_INK.r, UiPalette.COCOA_INK.g, UiPalette.COCOA_INK.b, shadow_alpha)
	style.shadow_size = size_px
	style.shadow_offset = offset
	style.set_corner_radius_all(10)
	shadow.add_theme_stylebox_override("panel", style)

	if parent is Container:
		var wrapper := MarginContainer.new()
		wrapper.size_flags_horizontal = target.size_flags_horizontal
		wrapper.size_flags_vertical = target.size_flags_vertical
		var index := target.get_index()
		parent.remove_child(target)
		parent.add_child(wrapper)
		parent.move_child(wrapper, index)
		wrapper.add_child(shadow)
		wrapper.add_child(target)
		return

	parent.add_child(shadow)
	# Slot the shadow into the target's index, pushing the target after it, so
	# it draws immediately behind the target and nothing else.
	parent.move_child(shadow, target.get_index())
