class_name VNScriptCompiler
extends RefCounted
## Compiles the line-oriented dialogue script format into a flat, linear
## instruction list with all label/jump targets resolved to concrete indices.
## See docs/design/systems.md, system 13 ("Dialogue script format").
##
## Deliberately flat rather than a tree the runtime walks recursively, so the
## eventual DialogueRunner can be a plain instruction pointer: step forward,
## jump on goto/failed if, pause on line/choice instructions for
## advance()/choose(index) to resume. Instructions are plain Dictionaries
## (same convention as VNExpressionParser's AST nodes) tagged with an "op"
## key; "condition"/"call" fields embed the exact AST Dictionary
## VNExpressionParser produces, unmodified, since VNExpressionEvaluator
## already consumes that shape directly.

const _OPTION_ARROW := "->"


## Returns {"scene_id": String, "instructions": Array[Dictionary]} on success,
## or {} on failure (push_error already emitted with details).
static func compile(source: String) -> Dictionary:
	var instructions: Array[Dictionary] = []
	var labels: Dictionary = {}          # label name -> instruction index
	var pending_gotos: Array[Dictionary] = []   # {"instr_index", "field_path", "label"}
	var if_stack: Array[Dictionary] = []        # {"jump_if_false_index", "else_jump_index"}
	var scene_id := ""
	var had_error := false

	var lines := source.split("\n")
	var line_number := 0
	var i := 0
	while i < lines.size():
		line_number = i + 1
		var raw: String = lines[i]
		var line := raw.strip_edges()
		i += 1

		if line.is_empty() or line.begins_with("#"):
			continue

		if line.begins_with("scene "):
			scene_id = line.substr(6).strip_edges()
			continue

		if line.begins_with("enter "):
			var parsed := _parse_enter(line, line_number)
			if parsed.is_empty():
				had_error = true
				continue
			instructions.append(parsed)
			continue

		if line.begins_with("exit "):
			instructions.append({"op": "STAGE_EXIT", "character": line.substr(5).strip_edges()})
			continue

		if line.begins_with("move "):
			var parsed_move := _parse_move(line, line_number)
			if parsed_move.is_empty():
				had_error = true
				continue
			instructions.append(parsed_move)
			continue

		if line.begins_with("expression "):
			var rest: String = line.substr(11).strip_edges()
			var space_idx := rest.find(" ")
			if space_idx == -1:
				push_error("VNScriptCompiler: line %d: malformed expression direction '%s'" % [line_number, line])
				had_error = true
				continue
			instructions.append({
				"op": "STAGE_EXPRESSION",
				"character": rest.substr(0, space_idx).strip_edges(),
				"expression": rest.substr(space_idx + 1).strip_edges(),
			})
			continue

		if line == "choice":
			var choice_instr := {"op": "SHOW_CHOICE", "options": []}
			var choice_index := instructions.size()
			instructions.append(choice_instr)
			while i < lines.size():
				var option_line: String = lines[i].strip_edges()
				var option := _try_parse_option(option_line)
				if option.is_empty():
					break
				i += 1
				var option_index: int = choice_instr.options.size()
				choice_instr.options.append({"text": option.text, "target": -1})
				pending_gotos.append({
					"instr_index": choice_index,
					"field_path": ["options", option_index, "target"],
					"label": option.label,
				})
			continue

		if line.begins_with("label "):
			labels[line.substr(6).strip_edges()] = instructions.size()
			continue

		if line.begins_with("goto "):
			var jump_index := instructions.size()
			instructions.append({"op": "JUMP", "target": -1})
			pending_gotos.append({
				"instr_index": jump_index,
				"field_path": ["target"],
				"label": line.substr(5).strip_edges(),
			})
			continue

		if line.begins_with("if "):
			var expr_source: String = line.substr(3).strip_edges()
			var parser := VNExpressionParser.new()
			var ast = parser.parse(expr_source)
			if ast == null:
				push_error("VNScriptCompiler: line %d: invalid if condition" % [line_number])
				had_error = true
				continue
			var jif_index := instructions.size()
			instructions.append({"op": "JUMP_IF_FALSE", "condition": ast, "target": -1})
			if_stack.append({"jump_if_false_index": jif_index, "else_jump_index": null})
			continue

		if line == "else":
			if if_stack.is_empty():
				push_error("VNScriptCompiler: line %d: 'else' with no matching 'if'" % [line_number])
				had_error = true
				continue
			var frame: Dictionary = if_stack[if_stack.size() - 1]
			var else_jump_index := instructions.size()
			instructions.append({"op": "JUMP", "target": -1})
			frame.else_jump_index = else_jump_index
			instructions[frame.jump_if_false_index].target = instructions.size()
			continue

		if line == "endif":
			if if_stack.is_empty():
				push_error("VNScriptCompiler: line %d: 'endif' with no matching 'if'" % [line_number])
				had_error = true
				continue
			var closed_frame: Dictionary = if_stack.pop_back()
			if closed_frame.else_jump_index != null:
				instructions[closed_frame.else_jump_index].target = instructions.size()
			else:
				instructions[closed_frame.jump_if_false_index].target = instructions.size()
			continue

		if line == "end_scene":
			instructions.append({"op": "END"})
			continue

		var speaker_line := _try_parse_speaker_line(line)
		if not speaker_line.is_empty():
			instructions.append({"op": "SHOW_LINE", "speaker": speaker_line.speaker, "text": speaker_line.text})
			continue

		var call_parser := VNExpressionParser.new()
		var call_ast = call_parser.parse(line)
		if call_ast == null:
			push_error("VNScriptCompiler: line %d: unrecognized line '%s'" % [line_number, line])
			had_error = true
			continue
		if call_ast.type != "call":
			push_error("VNScriptCompiler: line %d: expected an action call, got '%s'" % [line_number, line])
			had_error = true
			continue
		instructions.append({"op": "CALL", "call": call_ast})

	if not if_stack.is_empty():
		push_error("VNScriptCompiler: unterminated 'if' (missing 'endif')")
		had_error = true

	for entry in pending_gotos:
		if not labels.has(entry.label):
			push_error("VNScriptCompiler: unknown label '%s'" % [entry.label])
			had_error = true
			continue
		var target: int = labels[entry.label]
		var field_path: Array = entry.field_path
		if field_path.size() == 1:
			instructions[entry.instr_index][field_path[0]] = target
		else:
			instructions[entry.instr_index][field_path[0]][field_path[1]][field_path[2]] = target

	if had_error:
		return {}
	return {"scene_id": scene_id, "instructions": instructions}


static func _parse_enter(line: String, line_number: int) -> Dictionary:
	# enter <char> at <x>,<y>
	var rest := line.substr(6).strip_edges()
	var at_idx := rest.find(" at ")
	if at_idx == -1:
		push_error("VNScriptCompiler: line %d: malformed enter direction '%s'" % [line_number, line])
		return {}
	var character := rest.substr(0, at_idx).strip_edges()
	var pos_source := rest.substr(at_idx + 4).strip_edges()
	var pos := _parse_xy(pos_source)
	if pos.is_empty():
		push_error("VNScriptCompiler: line %d: malformed position '%s'" % [line_number, pos_source])
		return {}
	return {"op": "STAGE_ENTER", "character": character, "x": pos.x, "y": pos.y}


static func _parse_move(line: String, line_number: int) -> Dictionary:
	# move <char> to <x>,<y>
	var rest := line.substr(5).strip_edges()
	var to_idx := rest.find(" to ")
	if to_idx == -1:
		push_error("VNScriptCompiler: line %d: malformed move direction '%s'" % [line_number, line])
		return {}
	var character := rest.substr(0, to_idx).strip_edges()
	var pos_source := rest.substr(to_idx + 4).strip_edges()
	var pos := _parse_xy(pos_source)
	if pos.is_empty():
		push_error("VNScriptCompiler: line %d: malformed position '%s'" % [line_number, pos_source])
		return {}
	return {"op": "STAGE_MOVE", "character": character, "x": pos.x, "y": pos.y}


static func _parse_xy(source: String) -> Dictionary:
	var parts := source.split(",")
	if parts.size() != 2:
		return {}
	if not parts[0].strip_edges().is_valid_float() or not parts[1].strip_edges().is_valid_float():
		return {}
	return {"x": parts[0].strip_edges().to_float(), "y": parts[1].strip_edges().to_float()}


## Returns {"text": String, "label": String} if `line` matches
## `"option text" -> label_name`, or {} otherwise.
static func _try_parse_option(line: String) -> Dictionary:
	if not line.begins_with("\""):
		return {}
	var close_quote := line.find("\"", 1)
	if close_quote == -1:
		return {}
	var text := line.substr(1, close_quote - 1)
	var remainder := line.substr(close_quote + 1).strip_edges()
	if not remainder.begins_with(_OPTION_ARROW):
		return {}
	var label := remainder.substr(_OPTION_ARROW.length()).strip_edges()
	if label.is_empty():
		return {}
	return {"text": text, "label": label}


## Returns {"speaker": String, "text": String} if `line` matches
## `Speaker: "text"`, or {} otherwise.
static func _try_parse_speaker_line(line: String) -> Dictionary:
	var colon_idx := line.find(":")
	if colon_idx == -1:
		return {}
	var quote_idx := line.find("\"")
	if quote_idx != -1 and quote_idx < colon_idx:
		return {}
	var speaker := line.substr(0, colon_idx).strip_edges()
	var remainder := line.substr(colon_idx + 1).strip_edges()
	if not remainder.begins_with("\""):
		return {}
	var close_quote := remainder.find("\"", 1)
	if close_quote == -1:
		return {}
	var text := remainder.substr(1, close_quote - 1)
	return {"speaker": speaker, "text": text}
