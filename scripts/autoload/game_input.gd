extends Node
## Defines the game's entire input action set at boot. Autoloaded as
## "GameInput", first in project.godot's [autoload] order so the actions
## exist before any other autoload or scene's _ready() could read input.
##
## The game is deliberately keyboard+gamepad-only with a tiny schema --
## movement, "select", "back", plus the mouse (see docs/design/systems.md,
## system 1) -- so every action the whole UI needs boils down to six names:
## move_up/down/left/right, select, back. Gameplay/UI scripts (player.gd,
## main.gd, GameMenu, BrewMenu, MenuKeyNav, the Planar Rift arena) check
## `Input.is_action_pressed("move_up")` / `event.is_action_pressed("select")`
## etc. and never reference a KEY_*/JOY_* constant directly -- this is the one
## place the physical bindings live, so adding a controller binding or a
## rebind screen later is a one-file change instead of hunting down every
## `match event.keycode:` in the codebase.
##
## Built here with InputMap.add_action()/action_add_event() rather than
## authored in project.godot's [input] section: hand-editing that section's
## InputEvent resource literals is fragile and error-prone, and defining the
## bindings in code is what a future rebind screen needs anyway --
## InputMap.action_erase_events() + action_add_event() at runtime, persisted
## through Settings. physical_keycode (not keycode) is used throughout so
## WASD stays positionally correct on non-QWERTY layouts.
##
## Debug/system hotkeys that aren't part of this six-action schema (Space
## pause, R resolve-drain, 1/2/3 speed/quick-slots) stay as raw keycodes at
## their call sites -- they're deliberately outside the controller-friendly
## surface for now.

const ACTIONS := {
	"move_up": {
		"keys": [KEY_W, KEY_UP],
		"joy_buttons": [JOY_BUTTON_DPAD_UP],
		"joy_axis": [[JOY_AXIS_LEFT_Y, -1.0]],
	},
	"move_down": {
		"keys": [KEY_S, KEY_DOWN],
		"joy_buttons": [JOY_BUTTON_DPAD_DOWN],
		"joy_axis": [[JOY_AXIS_LEFT_Y, 1.0]],
	},
	"move_left": {
		"keys": [KEY_A, KEY_LEFT],
		"joy_buttons": [JOY_BUTTON_DPAD_LEFT],
		"joy_axis": [[JOY_AXIS_LEFT_X, -1.0]],
	},
	"move_right": {
		"keys": [KEY_D, KEY_RIGHT],
		"joy_buttons": [JOY_BUTTON_DPAD_RIGHT],
		"joy_axis": [[JOY_AXIS_LEFT_X, 1.0]],
	},
	"select": {
		"keys": [KEY_E, KEY_ENTER, KEY_KP_ENTER],
		"joy_buttons": [JOY_BUTTON_A],
	},
	"back": {
		"keys": [KEY_ESCAPE, KEY_Q],
		"joy_buttons": [JOY_BUTTON_B],
	},
}


func _ready() -> void:
	for action_name in ACTIONS:
		_define_action(action_name, ACTIONS[action_name])


func _define_action(action_name: String, spec: Dictionary) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for keycode in spec.get("keys", []):
		var key_event := InputEventKey.new()
		key_event.physical_keycode = keycode
		InputMap.action_add_event(action_name, key_event)
	for button in spec.get("joy_buttons", []):
		var button_event := InputEventJoypadButton.new()
		button_event.button_index = button
		InputMap.action_add_event(action_name, button_event)
	for pair in spec.get("joy_axis", []):
		var motion_event := InputEventJoypadMotion.new()
		motion_event.axis = pair[0]
		motion_event.axis_value = pair[1]
		InputMap.action_add_event(action_name, motion_event)
