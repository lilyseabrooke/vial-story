@tool
extends EditorInspectorPlugin
## Renders an OptionButton (effect_target_option_editor.gd) instead of a raw
## text field for any "effect_target" String property -- currently
## UpgradeDef.effect_target. See docs/engine_roadmap.md, Phase 4.

const EffectTargetOptionEditor := preload("res://addons/engine_scaffolding/effect_target_option_editor.gd")


func _can_handle(_object: Object) -> bool:
	return true


func _parse_property(_object: Object, type: Variant.Type, name: String, _hint_type: PropertyHint, _hint_string: String, _usage_flags: int, _wide: bool) -> bool:
	if name == "effect_target" and type == TYPE_STRING:
		add_property_editor(name, EffectTargetOptionEditor.new())
		return true
	return false
