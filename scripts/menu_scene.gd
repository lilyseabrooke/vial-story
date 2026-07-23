class_name MenuScene
extends CanvasLayer
## Generalized modal menu shell. See docs/design/systems.md, system 1 —
## `Clock.is_paused` is spec'd to be true "during menus/dialogue/minigames";
## this is what actually sets that flag. Callers hand in their own bespoke
## content Control (built the same way the HUD panels already are) and this
## just owns the shared chrome (title, close button, pause on open/close).

signal opened
signal closed

var _panel: PanelContainer
var _ghost: PanelContainer
var _holder: Control
var _clipper: Control
var _title_label: Label
var _body: VBoxContainer
var _current_content: Control = null
var _panel_tween: Tween
var _closing := false


func _ready() -> void:
	layer = 10

	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"FramedPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	add_child(_panel)
	UiFx.add_drop_shadow(_panel)

	# Empty frame used for the open/close animation: because the 9-patch frame
	# stays crisp at any real size, this ghost can genuinely *slide* open to
	# the window's final rect (bottom edge moving, no distortion) while the
	# real panel stays hidden, which also avoids re-laying-out the content
	# every animation frame. Slotted behind the panel so the content can
	# appear over it seamlessly.
	_ghost = PanelContainer.new()
	_ghost.theme_type_variation = &"FramedPanel"
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.visible = false
	add_child(_ghost)
	move_child(_ghost, _panel.get_index())
	UiFx.add_drop_shadow(_ghost)

	# Content chain: _panel fits _holder to its interior; _clipper (the only
	# node with clip_contents) is anchored inside _holder and is what the open
	# animation's top-down wipe shrinks/grows; the vbox sits top-anchored
	# inside it. _holder mirrors the vbox's minimum size upward so the panel
	# still sizes to its content — a plain Control doesn't propagate child
	# minimums on its own.
	_holder = Control.new()
	_panel.add_child(_holder)

	_clipper = Control.new()
	_clipper.clip_contents = true
	_clipper.set_anchors_preset(Control.PRESET_FULL_RECT)
	_holder.add_child(_clipper)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_clipper.add_child(vbox)

	vbox.minimum_size_changed.connect(func() -> void:
		_holder.custom_minimum_size = vbox.get_combined_minimum_size()
	)

	_title_label = Label.new()
	_title_label.theme_type_variation = &"HeadingLabel"
	vbox.add_child(_title_label)

	vbox.add_child(HSeparator.new())

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	vbox.add_child(_body)

	vbox.add_child(HSeparator.new())

	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.pressed.connect(close)
	vbox.add_child(close_button)


func open(content: Control, title: String) -> void:
	if _current_content == content and _panel.visible and not _closing:
		return
	if _panel_tween:
		_panel_tween.kill()
	var was_hidden := not _panel.visible or _ghost.visible
	_closing = false
	if _current_content != null:
		_body.remove_child(_current_content)
	_current_content = content
	_body.add_child(content)
	content.visible = true
	_title_label.text = title
	_panel.visible = true
	Clock.is_paused = true
	opened.emit()

	# The real window stays invisible (alpha 0, still laid out and clickable)
	# while the frame-ghost slides open over its final rect. That rect isn't
	# known until the new content has gone through a layout pass, so the
	# animation itself starts one frame deferred. A content swap while already
	# fully open plays no animation.
	if was_hidden:
		_panel.modulate.a = 0.0
		_begin_open_animation.call_deferred()


func _begin_open_animation() -> void:
	if not _panel.visible or _closing:
		return
	# The target rect is computed, not read from the panel: after a content
	# swap the panel's own rect still holds the *previous* window's layout for
	# a frame or two (minimum-size propagation is deferred), and animating the
	# ghost over that stale rect made the old window's shape flash before
	# being replaced. get_combined_minimum_size() is synchronous, and the
	# centered position follows from it — the panel's anchors settle to the
	# same values a frame later.
	var target_size := _panel.get_combined_minimum_size()
	var target_position := ((_panel.get_viewport_rect().size - target_size) * 0.5).floor()
	if not _ghost.visible:
		_ghost.size = Vector2(target_size.x, minf(56.0, target_size.y))
		_ghost.modulate.a = 0.0
	else:
		# Interrupted mid-close (or a double open): resume from the ghost's
		# current height instead of snapping back to a strip.
		_ghost.size.x = target_size.x
		_ghost.size.y = minf(_ghost.size.y, target_size.y)
	_ghost.position = target_position
	_ghost.visible = true

	# Show the panel's *children* immediately but keep its own frame drawing
	# hidden (self_modulate doesn't touch children) — the ghost is the frame
	# during the animation. The clipper starts collapsed and its bottom edge
	# chases the ghost's downward (same curve, slightly delayed), with a quick
	# fade layered on so the reveal edge reads soft instead of a hard cut.
	_panel.self_modulate.a = 0.0
	_clipper.anchor_bottom = 0.0
	_clipper.offset_bottom = 0.0
	_clipper.modulate.a = 0.0
	_panel.modulate.a = 1.0

	if _panel_tween:
		_panel_tween.kill()
	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.tween_property(_ghost, "modulate:a", 1.0, 0.07)
	_panel_tween.tween_property(_ghost, "size:y", target_size.y, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(_clipper, "modulate:a", 1.0, 0.12).set_delay(0.03)
	# target_size.y (the full window height) rather than the clipper's actual
	# interior height: _holder's rect can be stale here for the same reason as
	# the panel's, and overshooting the interior bottom just means "fully
	# revealed" — clip_contents caps the visible area at the clipper's rect.
	_panel_tween.tween_property(_clipper, "offset_bottom", target_size.y, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.05)
	# Panel frame and ghost share the exact rect and stylebox, so this swap at
	# the end is pixel-seamless.
	_panel_tween.chain().tween_callback(func() -> void:
		_panel.self_modulate.a = 1.0
		_ghost.visible = false
		_clipper.set_anchors_preset(Control.PRESET_FULL_RECT)
		_clipper.modulate.a = 1.0
	)


## The menu is *logically* closed immediately — Clock unpauses, `closed` fires,
## SceneDirector rechecks — only the ghost's slide-shut exit animation runs
## past this call, with content removal deferred to its end. `_closing` guards
## re-entry until then.
func close() -> void:
	if not _panel.visible or _closing:
		return
	_closing = true
	Clock.is_paused = false
	closed.emit()
	if _panel_tween:
		_panel_tween.kill()
	if not _ghost.visible:
		_ghost.position = _panel.position
		_ghost.size = _panel.size
		_ghost.visible = true
	_ghost.modulate.a = 1.0
	_panel.modulate.a = 0.0
	_panel_tween = create_tween()
	_panel_tween.tween_property(_ghost, "size:y", minf(56.0, _panel.size.y), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_panel_tween.tween_callback(_finish_close)
	SceneDirector.recheck()


func _finish_close() -> void:
	_closing = false
	_ghost.visible = false
	if _current_content != null:
		_body.remove_child(_current_content)
		_current_content = null
	_panel.visible = false
	_panel.modulate.a = 1.0
	_panel.self_modulate.a = 1.0
	_clipper.set_anchors_preset(Control.PRESET_FULL_RECT)
	_clipper.modulate.a = 1.0


func is_open() -> bool:
	return _panel.visible and not _closing


func has_content(content: Control) -> bool:
	return _current_content == content
