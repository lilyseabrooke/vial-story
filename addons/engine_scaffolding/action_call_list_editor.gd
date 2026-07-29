@tool
extends EditorProperty
## Smart-field widget for QuestDef.reward -- an Array[String] of VN
## action-call syntax like `give_item("moonpetal", 3)`. Each entry gets a
## function-name dropdown (from VNExpressionEvaluator.ACTION_FUNCTION_KEYS)
## plus a free-text field for the call's argument list, instead of hand-typing
## the whole "name(args)" string blind and finding out about a typo only at
## runtime. See docs/engine_roadmap.md, Phase 5.
##
## complete_condition (a single boolean-expression String, not an array of
## action-calls) is a different shape and stays a plain text field for now --
## deferred rather than forced into this widget.

var _vbox: VBoxContainer
var _updating := false


func _init() -> void:
	_vbox = VBoxContainer.new()
	add_child(_vbox)
	add_focusable(_vbox)
	set_bottom_editor(_vbox)


func _update_property() -> void:
	_updating = true
	for child in _vbox.get_children():
		child.queue_free()

	var current: Array = get_edited_object().get(get_edited_property())
	for i in current.size():
		_vbox.add_child(_build_row(i, current[i]))

	var add_button := Button.new()
	add_button.text = "+ Add reward"
	add_button.pressed.connect(_on_add_pressed)
	_vbox.add_child(add_button)
	_updating = false


func _build_row(index: int, entry: String) -> HBoxContainer:
	var row := HBoxContainer.new()

	var func_name := entry
	var args_text := ""
	var paren := entry.find("(")
	if paren != -1 and entry.ends_with(")"):
		func_name = entry.substr(0, paren)
		args_text = entry.substr(paren + 1, entry.length() - paren - 2)

	var option := OptionButton.new()
	for key in VNExpressionEvaluator.ACTION_FUNCTION_KEYS:
		option.add_item(key)
	var idx: int = VNExpressionEvaluator.ACTION_FUNCTION_KEYS.find(func_name)
	if idx == -1:
		option.add_item("(%s)" % func_name if not func_name.is_empty() else "(choose)")
		idx = option.item_count - 1
	option.select(idx)
	option.item_selected.connect(func(_i: int) -> void: _commit())
	row.add_child(option)

	var args_edit := LineEdit.new()
	args_edit.text = args_text
	args_edit.placeholder_text = "args, e.g. \"moonpetal\", 3"
	args_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	args_edit.text_changed.connect(func(_t: String) -> void: _commit())
	row.add_child(args_edit)

	var remove_button := Button.new()
	remove_button.text = "x"
	remove_button.pressed.connect(_on_remove_pressed.bind(index))
	row.add_child(remove_button)

	row.set_meta("option", option)
	row.set_meta("args_edit", args_edit)
	return row


## Rebuilds the full Array[String] from every row's live widget state and
## commits it -- used for in-place edits (dropdown/args text) rather than
## add/remove, which mutate the array directly instead.
func _commit() -> void:
	if _updating:
		return
	var result: Array[String] = []
	for child in _vbox.get_children():
		if not child is HBoxContainer:
			continue
		var option: OptionButton = child.get_meta("option")
		var args_edit: LineEdit = child.get_meta("args_edit")
		var func_name := option.get_item_text(option.selected).trim_prefix("(").trim_suffix(")")
		result.append("%s(%s)" % [func_name, args_edit.text])
	emit_changed(get_edited_property(), result)


func _on_remove_pressed(index: int) -> void:
	var current: Array = get_edited_object().get(get_edited_property()).duplicate()
	current.remove_at(index)
	emit_changed(get_edited_property(), current)


func _on_add_pressed() -> void:
	var current: Array = get_edited_object().get(get_edited_property()).duplicate()
	current.append("%s()" % VNExpressionEvaluator.ACTION_FUNCTION_KEYS[0])
	emit_changed(get_edited_property(), current)
