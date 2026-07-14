class_name DialogueRunner
extends RefCounted
## Steps through a VNScriptCompiler-compiled scene. See docs/design/systems.md,
## system 13 ("Runtime and presentation").
##
## Deliberately a plain instruction pointer, not a tree walker: stage
## directions and action calls execute immediately and fall through to the
## next instruction in the same call, while SHOW_LINE/SHOW_CHOICE/END pause
## execution (return out of the loop) until the presentation layer calls
## advance()/choose(index) back in. All branching (JUMP/JUMP_IF_FALSE/choice
## targets) is just an index assignment — VNScriptCompiler already resolved
## every label reference to a concrete instruction index.

signal line_shown(speaker: String, text: String)
signal choice_requested(options: Array)
signal stage_changed(instruction: Dictionary)
signal scene_ended()

var _instructions: Array[Dictionary] = []
var _scene_id: String = ""
var _ip: int = 0
var _ended: bool = false


func load_scene(compiled: Dictionary) -> void:
	_instructions = compiled.instructions
	_scene_id = compiled.get("scene_id", "")
	_ip = 0
	_ended = false


func get_scene_id() -> String:
	return _scene_id


func is_ended() -> bool:
	return _ended


## Begins execution from the start of the loaded scene.
func start() -> void:
	_run()


## Resumes execution after a SHOW_LINE pause.
func advance() -> void:
	if _ended:
		return
	_run()


## Resumes execution after a SHOW_CHOICE pause, taking the chosen option.
func choose(index: int) -> void:
	if _ended:
		return
	var instr: Dictionary = _instructions[_ip]
	if instr.op != "SHOW_CHOICE":
		push_warning("DialogueRunner: choose() called while not awaiting a choice")
		return
	_ip = instr.options[index].target
	_run()


func _run() -> void:
	while not _ended and _ip < _instructions.size():
		var instr: Dictionary = _instructions[_ip]
		match instr.op:
			"SHOW_LINE":
				_ip += 1
				line_shown.emit(instr.speaker, instr.text)
				return
			"SHOW_CHOICE":
				choice_requested.emit(instr.options)
				return
			"JUMP":
				_ip = instr.target
			"JUMP_IF_FALSE":
				var condition_result = VNExpressionEvaluator.evaluate(instr.condition)
				_ip = _ip + 1 if condition_result else instr.target
			"CALL":
				VNExpressionEvaluator.evaluate(instr.call)
				_ip += 1
			"STAGE_BACKGROUND", "STAGE_ENTER", "STAGE_EXIT", "STAGE_MOVE", "STAGE_EXPRESSION":
				_ip += 1
				stage_changed.emit(instr)
			"END":
				_ended = true
				scene_ended.emit()
			_:
				push_warning("DialogueRunner: unknown instruction op '%s'" % instr.op)
				_ip += 1
