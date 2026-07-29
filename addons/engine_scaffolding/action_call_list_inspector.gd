@tool
extends EditorInspectorPlugin
## Renders action_call_list_editor.gd instead of the stock array editor for
## QuestDef.reward. See docs/engine_roadmap.md, Phase 5.

const ActionCallListEditor := preload("res://addons/engine_scaffolding/action_call_list_editor.gd")


func _can_handle(object: Object) -> bool:
	return object is QuestDef


func _parse_property(_object: Object, type: Variant.Type, name: String, _hint_type: PropertyHint, _hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if name == "reward" and type == TYPE_ARRAY:
		add_property_editor(name, ActionCallListEditor.new())
		return true
	return false
