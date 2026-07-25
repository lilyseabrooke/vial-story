extends Node
## Picks and plays the right conversation when the player talks to an NPC.
## Autoloaded as "NPCDialogue". See docs/design/systems.md, system 13
## ("NPC interaction").
##
## Reuses SceneDirector's shared DialogueBox/one-shot-flag machinery rather
## than owning its own -- talk_to() just picks which already-compiled scene
## to hand to SceneDirector.play_external(), same selection rule (highest
## satisfied priority, ties by registration order, non-repeatable entries
## skipped once played) that SceneDirector.recheck() uses for its own
## triggers.

## Explicit path list, same "no directory scanning" convention as
## Characters.CHARACTER_PATHS / SceneDirector.TRIGGER_PATHS.
const NPC_LINE_PATHS: Array[String] = [
	"res://data/npc_dialogue/mira/default.tres",
	"res://data/npc_dialogue/mira/evening.tres",
]

var _entries_by_npc: Dictionary = {}   # npc_id -> Array[{"def", "condition_ast", "compiled"}]


func _ready() -> void:
	for path in NPC_LINE_PATHS:
		_register(load(path) as NPCLineSetDef)


## Parses the entry's condition and compiles its script once, up front, so
## talk_to() never touches the filesystem or a parser mid-game. Skips (with
## a push_error) an entry whose condition or script fails to compile.
func _register(entry_def: NPCLineSetDef) -> void:
	var condition_parser := VNExpressionParser.new()
	var condition_ast = condition_parser.parse(entry_def.condition)
	if condition_ast == null:
		push_error("NPCDialogue: entry '%s' has an invalid condition" % entry_def.id)
		return

	var source := FileAccess.get_file_as_string(entry_def.script_path)
	var compiled := VNScriptCompiler.compile(source)
	if compiled.is_empty():
		push_error("NPCDialogue: entry '%s' references a script that failed to compile ('%s')" % [entry_def.id, entry_def.script_path])
		return

	if not _entries_by_npc.has(entry_def.npc_id):
		_entries_by_npc[entry_def.npc_id] = []
	_entries_by_npc[entry_def.npc_id].append({"def": entry_def, "condition_ast": condition_ast, "compiled": compiled})


## Picks the highest-priority satisfied, not-yet-played conversation
## registered for npc_id and plays it. No-op if a scene is already playing
## (an auto-triggered scene, or another NPC conversation). If nothing
## matches, warns -- every NPC should have at least one condition = "true",
## priority = LOW fallback entry authored.
func talk_to(npc_id: String) -> void:
	if SceneDirector.is_scene_playing():
		return

	var candidates: Array = _entries_by_npc.get(npc_id, [])
	var best: Dictionary = {}
	for entry in candidates:
		var entry_def: NPCLineSetDef = entry.def
		if not entry_def.repeatable and Story.has_flag(SceneDirector.played_flag(entry.compiled.scene_id)):
			continue
		if not VNExpressionEvaluator.evaluate(entry.condition_ast):
			continue
		if best.is_empty() or entry_def.priority > best.def.priority:
			best = entry

	if best.is_empty():
		push_warning("NPCDialogue: no satisfied conversation found for npc_id '%s'" % npc_id)
		return

	SceneDirector.play_external(best.compiled, best.def.repeatable)
