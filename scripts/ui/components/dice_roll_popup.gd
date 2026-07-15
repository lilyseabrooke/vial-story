class_name DiceRollPopup
extends PanelContainer
## Displays an already-rolled Rng.roll_2d10() result via a staggered Timer
## reveal (die A -> die B -> modifier -> total/result), the same Timer-driven
## sequencing convention as scripts/vn/dialogue_box.gd's typewriter reveal.
## Never rolls dice itself -- logic and UI consume the same Rng.roll_2d10()
## call, this just renders the Dictionary it returns. See docs/design/
## systems.md, system 16.
##
## Node refs are looked up on demand rather than cached via @onready, same
## reasoning as scripts/ui/components/item_slot.gd: this is only parented in
## when MenuScene.open() reparents it into its body.

signal reveal_finished

const STEP_SECONDS := 0.5

var _result: Dictionary = {}
var _step := 0


func _ready() -> void:
	var timer: Timer = $RevealTimer
	timer.wait_time = STEP_SECONDS
	timer.timeout.connect(_on_reveal_step)


## label: what the check is for (e.g. "Brewing", "Class Performance").
func show_roll(result: Dictionary, label: String) -> void:
	_result = result
	_step = 0
	var header: Label = $VBox/LabelHeader
	header.text = label
	var die_a: Label = $VBox/DiceRow/DieA
	var die_b: Label = $VBox/DiceRow/DieB
	var modifier_label: Label = $VBox/ModifierLabel
	var total_label: Label = $VBox/TotalLabel
	var result_label: Label = $VBox/ResultLabel
	die_a.text = "?"
	die_b.text = "?"
	modifier_label.text = ""
	total_label.text = ""
	result_label.text = ""
	visible = true
	($RevealTimer as Timer).start()


func _on_reveal_step() -> void:
	_step += 1
	match _step:
		1:
			var die_a: Label = $VBox/DiceRow/DieA
			die_a.text = "d10: %d" % _result.die_a
		2:
			var die_b: Label = $VBox/DiceRow/DieB
			die_b.text = "d10: %d" % _result.die_b
		3:
			var modifier_label: Label = $VBox/ModifierLabel
			modifier_label.text = "Modifier: %+.1f" % _result.modifier
		4:
			var total_label: Label = $VBox/TotalLabel
			total_label.text = "Total: %.1f vs DC %.1f" % [_result.total, _result.dc]
			_show_final_result()
			($RevealTimer as Timer).stop()
			reveal_finished.emit()


func _show_final_result() -> void:
	var result_label: Label = $VBox/ResultLabel
	if _result.get("inflection_point", false):
		result_label.text = "...an inflection point."
		result_label.modulate = Color(0.7, 0.55, 0.9)
	elif _result.get("critical_failure", false):
		result_label.text = "CRITICAL FAILURE"
		result_label.modulate = Color.CRIMSON
	elif _result.get("critical_success", false):
		result_label.text = "CRITICAL SUCCESS!"
		result_label.modulate = Color.GOLD
	elif _result.passed:
		result_label.text = "Success!"
		result_label.modulate = Color.GREEN
	else:
		result_label.text = "Failed."
		result_label.modulate = Color.INDIAN_RED
