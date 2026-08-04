class_name WindowScale
extends RefCounted
## Shared computation of the window's canvas_items stretch scale factor — how
## many real screen pixels one base-design-resolution (1920x1080) unit
## currently maps to. Anything that needs to counter-scale against
## window/stretch/mode="canvas_items" uses this: pinned real-pixel sizes
## (see PixelPerfectSize) and layouts that need to reflow as the design-unit
## footprint of pinned-size content changes with window size (see GameMenu's
## grid column count).

static func get_factor(node: Node) -> float:
	var win := node.get_window()
	return minf(
		win.size.x / float(win.content_scale_size.x),
		win.size.y / float(win.content_scale_size.y)
	)


## Metadata key holding a control's live pin callable, so a re-pin can drop the
## previous one instead of leaving two rival handlers on size_changed.
const PIN_META := &"window_scale_pin"


## Keeps a Control's rendered size at a fixed real screen-pixel count as the
## window resizes, by counter-scaling its design-unit custom_minimum_size
## against get_factor(). Must be called once the control is actually inside
## a live tree (get_window() needs a window to exist) — see PixelPerfectSize
## and ItemSlot for the "built detached, pin in _ready()" pattern this is for.
##
## Re-pinning the same control to a different size is supported and replaces
## the earlier pin — Build Mode's shelf re-sizes an ItemSlot to its own art
## after the scene's default pin has already been applied in _ready().
static func pin_size(control: Control, native_size: Vector2) -> void:
	var window := control.get_window()
	if control.has_meta(PIN_META):
		var previous: Callable = control.get_meta(PIN_META)
		if window.size_changed.is_connected(previous):
			window.size_changed.disconnect(previous)
	var apply := func() -> void:
		control.custom_minimum_size = native_size / get_factor(control)
	control.set_meta(PIN_META, apply)
	window.size_changed.connect(apply)
	apply.call()
