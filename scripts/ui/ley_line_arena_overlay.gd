class_name LeyLineArenaOverlay
extends CanvasLayer
## Chromeless popup for the Ley Line resonance minigame -- unlike every other
## minigame/menu (which goes through MenuScene's framed panel: title, Close
## button, slide-open animation), this is deliberately *just* the arena over a
## dimmed backdrop, nothing else. Owned and built once by hud.gd, holding the
## same LeyLineMinigamePanel instance across opens (same "build once, show
## per-open" shape MenuScene uses for its content).
##
## Esc is blocked outright while a LeyLines session is active (see main.gd's
## _unhandled_input, gated on LeyLines.is_active()) rather than routed through
## a close button -- there's deliberately no way to back out once a Surge's DC
## check has passed and the minigame has started; hide_panel() only ever runs
## from LeyLines.minigame_resolved, once the run has actually finished.

var _dim: ColorRect
var _panel: LeyLineMinigamePanel


func build(panel: LeyLineMinigamePanel) -> void:
	layer = 20
	visible = false

	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.75)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_panel = panel
	add_child(_panel)


func show_panel() -> void:
	visible = true
	Clock.is_paused = true
	_center_panel()


func hide_panel() -> void:
	visible = false
	Clock.is_paused = false


## The panel is a plain Control outside any container (get_effective_size()
## just reads the arena's own custom_minimum_size), so it needs to be
## positioned by hand rather than relying on layout.
func _center_panel() -> void:
	var vp_size := _panel.get_viewport_rect().size
	var panel_size := _panel.get_effective_size()
	_panel.position = ((vp_size - panel_size) * 0.5).floor()
