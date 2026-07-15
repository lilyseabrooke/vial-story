extends Node
## Session-scoped device settings that need to be readable from anywhere
## without threading a return value through both Settings screens (main menu
## + in-game Escape menu, see scripts/settings_controls.gd) and whatever
## presentation code consumes them — currently DialogueBox's typewriter
## reveal rate. Autoloaded as "Settings". Not persisted to save files: these
## are OS/device-level preferences, not game state.

signal text_speed_changed(multiplier: float)

## Index -> seconds-per-character multiplier for DialogueBox's reveal timer;
## 0.0 means "reveal instantly, skip the timer".
const TEXT_SPEED_MULTIPLIERS: Array[float] = [2.0, 1.0, 0.5, 0.0]
const DEFAULT_TEXT_SPEED_INDEX := 1   # "Normal"

var text_speed_multiplier: float = TEXT_SPEED_MULTIPLIERS[DEFAULT_TEXT_SPEED_INDEX]


func set_text_speed_index(index: int) -> void:
	if index < 0 or index >= TEXT_SPEED_MULTIPLIERS.size():
		return
	text_speed_multiplier = TEXT_SPEED_MULTIPLIERS[index]
	text_speed_changed.emit(text_speed_multiplier)
