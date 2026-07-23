class_name MenuKeyNav
extends Node
## Shared W/S + E keyboard navigation for simple list-style menus, so every
## choice menu drives the same way the brew menu does (see BrewMenu's
## docstring and docs/design/systems.md, system 1): W/S (or arrows) move a
## highlighted cursor through the menu's controls, E activates the one under
## it, A/D nudge sliders and cycle option buttons, and Esc optionally acts as
## "back". Add an instance as a *child of the host Control* whose descendants
## are the navigable controls (buttons, sliders, OptionButtons, collected in
## tree order); it re-collects on every move, so hosts that rebuild their
## children never need to notify it.
##
## Input is handled in `_input()` and marked handled (same reasoning as
## BrewMenu: W/S/E must drive the menu, not the world, while a menu owns the
## screen). Esc is only consumed when `handle_escape` is set — otherwise it
## falls through to whoever owns closing (main.gd for MenuScene menus).
## `require_pause` gates on `Clock.is_paused` for in-game menus (guards
## against stray keypresses during MenuScene's close animation); the main
## menu turns it off since nothing pauses there.
##
## The cursor marks a Button by forcing its theme *hover* look and anything
## else (sliders) with a magic tint — the same trick as BrewMenu, whose
## highlight now routes through the statics below so there's one
## implementation. GameMenu's two-level rail/section navigation also builds on
## these statics rather than instancing this node.

signal back_requested

## Gate input on Clock.is_paused (true for MenuScene contents; the main menu
## sets this false since it never pauses).
var require_pause := true
## Consume Esc and emit `back_requested` instead of letting it fall through.
var handle_escape := false

var _host: Control = null
var _highlighted: Control = null


func _enter_tree() -> void:
	_host = get_parent() as Control
	# Deferred so a freshly built/reparented host has its children in place.
	reset.call_deferred()


func _exit_tree() -> void:
	_clear_highlight()


## Re-collects the host's controls and drops the cursor on the first one.
## Called automatically when the host (re)enters the tree; hosts that hide and
## re-show without leaving the tree (main menu layers) call this on show.
func reset() -> void:
	_clear_highlight()
	var controls := collect_nav_controls(_host) if _host != null else ([] as Array[Control])
	if not controls.is_empty():
		_set_highlighted(controls[0])


func _input(event: InputEvent) -> void:
	if not _is_active():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	# Captured up front: activating a control (or emitting back_requested) can
	# tear this node out of the tree synchronously — a load-slot button's
	# change_scene_to_file(), a freed menu layer — after which get_viewport()
	# returns null. The reference itself stays valid to mark input handled on.
	var viewport := get_viewport()
	match event.keycode:
		KEY_W, KEY_UP:
			_move(-1)
			viewport.set_input_as_handled()
		KEY_S, KEY_DOWN:
			_move(1)
			viewport.set_input_as_handled()
		KEY_A, KEY_LEFT:
			if is_instance_valid(_highlighted) and adjust(_highlighted, -1):
				viewport.set_input_as_handled()
		KEY_D, KEY_RIGHT:
			if is_instance_valid(_highlighted) and adjust(_highlighted, 1):
				viewport.set_input_as_handled()
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			if is_instance_valid(_highlighted):
				activate(_highlighted)
			# Consumed even with nothing highlighted so E never falls through
			# to main.gd's interact while a menu owns the screen.
			viewport.set_input_as_handled()
		KEY_ESCAPE:
			if handle_escape:
				back_requested.emit()
				viewport.set_input_as_handled()


## Active only while the host is actually on screen. is_visible_in_tree()
## doesn't see through CanvasLayer ancestors (they're not CanvasItems), so the
## main menu's hidden layers need the explicit walk.
func _is_active() -> bool:
	if _host == null or not _host.is_visible_in_tree():
		return false
	var node: Node = _host
	while node != null:
		if node is CanvasLayer and not node.visible:
			return false
		node = node.get_parent()
	if require_pause and not Clock.is_paused:
		return false
	return true


func _move(delta: int) -> void:
	var controls := collect_nav_controls(_host)
	if controls.is_empty():
		return
	var idx := controls.find(_highlighted)
	idx = 0 if idx == -1 else clampi(idx + delta, 0, controls.size() - 1)
	_set_highlighted(controls[idx])


func _set_highlighted(control: Control) -> void:
	_clear_highlight()
	_highlighted = control
	set_highlight(control, true)
	ensure_visible(control, _host)


func _clear_highlight() -> void:
	if is_instance_valid(_highlighted):
		set_highlight(_highlighted, false)
	_highlighted = null


# --- Shared statics (used here, by BrewMenu, and by GameMenu) -----------------

## The controls a keyboard cursor can land on, in tree (top-to-bottom) order:
## enabled buttons (incl. CheckBox/CheckButton/OptionButton) and sliders.
## Skips invisible subtrees and nodes already queued for deletion, so callers
## can re-collect mid-rebuild safely.
static func collect_nav_controls(root: Node) -> Array[Control]:
	var result: Array[Control] = []
	if root != null:
		_collect_into(root, result)
	return result


static func _collect_into(node: Node, result: Array[Control]) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Control and not child.visible:
			continue
		if (child is BaseButton and not child.disabled) or child is Slider:
			result.append(child)
		_collect_into(child, result)


## Marks/unmarks the cursor'd control. Buttons get the forced-hover treatment
## (see BrewMenu — the theme's focus outline was too subtle): the normal and
## pressed styleboxes/font colors are overridden with the hover ones until the
## cursor moves ("pressed" too so a toggled button still lights up).
## Non-buttons (sliders) get a magic tint instead — the palette's "you're
## acting on this" accent.
static func set_highlight(control: Control, on: bool) -> void:
	if control is Button:
		if on:
			control.add_theme_stylebox_override("normal", control.get_theme_stylebox("hover"))
			control.add_theme_stylebox_override("pressed", control.get_theme_stylebox("hover"))
			control.add_theme_color_override("font_color", control.get_theme_color("font_hover_color"))
			control.add_theme_color_override("font_pressed_color", control.get_theme_color("font_hover_color"))
		else:
			control.remove_theme_stylebox_override("normal")
			control.remove_theme_stylebox_override("pressed")
			control.remove_theme_color_override("font_color")
			control.remove_theme_color_override("font_pressed_color")
	else:
		control.modulate = UiPalette.MAGIC if on else Color.WHITE


## E on the cursor'd control: cycle an OptionButton to its next item, flip a
## toggle (emits `toggled`, matching a real click), or press a plain button
## (emits `pressed`). Sliders only respond to A/D.
static func activate(control: Control) -> void:
	if control is OptionButton:
		_cycle_option(control, 1)
	elif control is BaseButton:
		if control.disabled:
			return
		if control.toggle_mode:
			control.button_pressed = not control.button_pressed
		else:
			control.pressed.emit()


## A/D on the cursor'd control. Returns whether the key meant something (so
## the caller only consumes it when it did).
static func adjust(control: Control, direction: int) -> bool:
	if control is OptionButton:
		_cycle_option(control, direction)
		return true
	if control is Slider:
		var slider: Slider = control
		# A tenth of the range per press — coarse enough to feel responsive,
		# fine enough for a volume slider.
		slider.value += (slider.max_value - slider.min_value) * 0.1 * direction
		return true
	return false


## select() doesn't emit item_selected, so re-emit manually — the same signal
## path a mouse pick takes, keeping wired handlers (resolution, text speed)
## working under keyboard control.
static func _cycle_option(option: OptionButton, direction: int) -> void:
	if option.item_count == 0:
		return
	var idx := wrapi(option.selected + direction, 0, option.item_count)
	option.select(idx)
	option.item_selected.emit(idx)


## Scrolls the control into view if it lives inside a ScrollContainer
## somewhere below `within`.
static func ensure_visible(control: Control, within: Control) -> void:
	var node: Node = control.get_parent()
	while node != null and node != within:
		if node is ScrollContainer:
			node.ensure_control_visible(control)
			return
		node = node.get_parent()
