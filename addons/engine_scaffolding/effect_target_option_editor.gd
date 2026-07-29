@tool
extends EditorProperty
## Backing widget for effect_target_inspector.gd -- an OptionButton populated
## from VNExpressionEvaluator.EFFECT_TARGET_KEYS instead of a raw text field,
## so a typo like "shop_capaciy" is impossible to enter rather than failing
## silently at runtime. See docs/engine_roadmap.md, Phase 4.

var _option_button: OptionButton
var _updating := false


func _init() -> void:
	_option_button = OptionButton.new()
	for key in VNExpressionEvaluator.EFFECT_TARGET_KEYS:
		_option_button.add_item(key)
	add_child(_option_button)
	add_focusable(_option_button)
	_option_button.item_selected.connect(_on_item_selected)


func _update_property() -> void:
	var current: String = get_edited_object().get(get_edited_property())
	var idx: int = VNExpressionEvaluator.EFFECT_TARGET_KEYS.find(current)
	_updating = true
	if idx == -1:
		# Unrecognized/legacy value -- surface it as an extra entry instead of
		# silently overwriting it with the first valid key.
		if _option_button.item_count == VNExpressionEvaluator.EFFECT_TARGET_KEYS.size():
			_option_button.add_item("(%s)" % current)
		_option_button.select(_option_button.item_count - 1)
	else:
		_option_button.select(idx)
	_updating = false


func _on_item_selected(index: int) -> void:
	if _updating:
		return
	var text := _option_button.get_item_text(index)
	if text.begins_with("(") and text.ends_with(")"):
		return
	emit_changed(get_edited_property(), text)
