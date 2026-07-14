extends Node
## Registers SceneTriggerDefs and decides when a compiled VN scene should
## play. Autoloaded as "SceneDirector". See docs/design/systems.md, system 13
## ("Scene triggering").
##
## No trigger queue: recheck() re-evaluates every registered trigger against
## current state, so a trigger that's satisfied but blocked simply doesn't
## fire yet — the very next recheck() (on the next Clock.minute_tick, or an
## explicit call from wherever wants instant-feeling triggers) picks it back
## up, or drops it naturally if its condition stopped being true meanwhile.

signal scene_started(scene_id: String)
signal scene_finished(scene_id: String)

const TRIGGER_PATHS := [
	"res://data/scene_triggers/kaelith_greeting_trigger.tres",
]

var _entries: Array[Dictionary] = []   # {"trigger", "condition_ast", "compiled"}, registration order
var _dialogue_box: DialogueBox
var _is_scene_playing: bool = false
var _current_scene_id: String = ""


func _ready() -> void:
	_dialogue_box = DialogueBox.new()
	add_child(_dialogue_box)
	_dialogue_box.closed.connect(_on_dialogue_box_closed)

	Clock.minute_tick.connect(func(_timestamp): recheck())

	for path in TRIGGER_PATHS:
		register_trigger(load(path) as SceneTriggerDef)


## Parses the trigger's condition and compiles its script once, up front, so
## recheck() never touches the filesystem or a parser mid-game. Skips (with a
## push_error) a trigger whose condition or script fails to compile.
func register_trigger(trigger: SceneTriggerDef) -> void:
	var condition_parser := VNExpressionParser.new()
	var condition_ast = condition_parser.parse(trigger.condition)
	if condition_ast == null:
		push_error("SceneDirector: trigger '%s' has an invalid condition" % trigger.id)
		return

	var source := FileAccess.get_file_as_string(trigger.script_path)
	var compiled := VNScriptCompiler.compile(source)
	if compiled.is_empty():
		push_error("SceneDirector: trigger '%s' references a script that failed to compile ('%s')" % [trigger.id, trigger.script_path])
		return

	_entries.append({"trigger": trigger, "condition_ast": condition_ast, "compiled": compiled})


## Re-evaluates every registered trigger and plays the highest-priority
## satisfied one (ties broken by registration order). No-op if a scene is
## already playing, or if the player is menu-blocked and the trigger doesn't
## have show_from_menu set.
func recheck() -> void:
	if _is_scene_playing:
		return

	var menu_blocked: bool = Clock.is_paused
	var best: Dictionary = {}
	for entry in _entries:
		var trigger: SceneTriggerDef = entry.trigger
		if not trigger.repeatable and Story.has_flag(_played_flag(entry.compiled.scene_id)):
			continue
		if menu_blocked and not trigger.show_from_menu:
			continue
		if not VNExpressionEvaluator.evaluate(entry.condition_ast):
			continue
		if best.is_empty() or trigger.priority > best.trigger.priority:
			best = entry

	if not best.is_empty():
		_fire(best)


func is_scene_playing() -> bool:
	return _is_scene_playing


func _fire(entry: Dictionary) -> void:
	var trigger: SceneTriggerDef = entry.trigger
	var compiled: Dictionary = entry.compiled
	_is_scene_playing = true
	_current_scene_id = compiled.scene_id
	if not trigger.repeatable:
		Story.set_flag(_played_flag(compiled.scene_id))
	scene_started.emit(compiled.scene_id)
	_dialogue_box.open(compiled)


func _on_dialogue_box_closed() -> void:
	var finished_scene_id := _current_scene_id
	_is_scene_playing = false
	_current_scene_id = ""
	scene_finished.emit(finished_scene_id)
	recheck()


func _played_flag(scene_id: String) -> String:
	return "scene_played_" + scene_id
