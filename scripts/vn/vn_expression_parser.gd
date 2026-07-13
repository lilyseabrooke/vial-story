class_name VNExpressionParser
extends RefCounted
## Parses the small boolean expression language shared by dialogue `if`
## statements and scene-trigger conditions (system 13). One grammar, reused
## in both places, evaluated by VNExpressionEvaluator.
##
## Grammar (highest to lowest precedence):
##   primary    := NUMBER | STRING | "true" | "false" | IDENT "(" args ")" | "(" expr ")"
##   comparison := primary ( ("==" | "!=" | ">=" | "<=" | ">" | "<") primary )?
##   not_expr   := "not" not_expr | comparison
##   and_expr   := not_expr ( "and" not_expr )*
##   or_expr    := and_expr ( "or" and_expr )*
##
## AST nodes are plain Dictionaries (e.g. {"type": "call", "name": ..., "args": [...]})
## rather than a class per node kind — they're transient and structurally
## varied enough that a class hierarchy would be pure overhead here.

var _tokens: Array[Dictionary] = []
var _pos: int = 0
var _had_error: bool = false


## Returns the AST root, or null if the expression failed to parse (a
## push_error is emitted with details either way).
func parse(source: String) -> Variant:
	_tokens = _tokenize(source)
	_pos = 0
	_had_error = false
	var node := _parse_or()
	if not _had_error and _peek().type != "EOF":
		_error("unexpected trailing token '%s'" % [_peek().get("value", _peek().type)])
	if _had_error:
		return null
	return node


func _is_ident_start(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")


func _is_ident_char(c: String) -> bool:
	return _is_ident_start(c) or c.is_valid_int()


func _tokenize(source: String) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	var i := 0
	var length := source.length()
	while i < length:
		var c := source[i]
		if c == " " or c == "\t" or c == "\n":
			i += 1
			continue
		if c == "\"":
			var j := i + 1
			var value := ""
			while j < length and source[j] != "\"":
				value += source[j]
				j += 1
			tokens.append({"type": "STRING", "value": value})
			i = j + 1
			continue
		if c.is_valid_int() or (c == "-" and i + 1 < length and source[i + 1].is_valid_int()):
			var j := i + 1
			while j < length and (source[j].is_valid_int() or source[j] == "."):
				j += 1
			tokens.append({"type": "NUMBER", "value": source.substr(i, j - i).to_float()})
			i = j
			continue
		if _is_ident_start(c):
			var j := i
			while j < length and _is_ident_char(source[j]):
				j += 1
			var word := source.substr(i, j - i)
			match word:
				"and":
					tokens.append({"type": "AND"})
				"or":
					tokens.append({"type": "OR"})
				"not":
					tokens.append({"type": "NOT"})
				"true":
					tokens.append({"type": "BOOL", "value": true})
				"false":
					tokens.append({"type": "BOOL", "value": false})
				_:
					tokens.append({"type": "IDENT", "value": word})
			i = j
			continue
		if c == "(":
			tokens.append({"type": "LPAREN"})
			i += 1
			continue
		if c == ")":
			tokens.append({"type": "RPAREN"})
			i += 1
			continue
		if c == ",":
			tokens.append({"type": "COMMA"})
			i += 1
			continue
		if c == "=" and i + 1 < length and source[i + 1] == "=":
			tokens.append({"type": "OP", "value": "=="})
			i += 2
			continue
		if c == "!" and i + 1 < length and source[i + 1] == "=":
			tokens.append({"type": "OP", "value": "!="})
			i += 2
			continue
		if c == ">" and i + 1 < length and source[i + 1] == "=":
			tokens.append({"type": "OP", "value": ">="})
			i += 2
			continue
		if c == "<" and i + 1 < length and source[i + 1] == "=":
			tokens.append({"type": "OP", "value": "<="})
			i += 2
			continue
		if c == ">":
			tokens.append({"type": "OP", "value": ">"})
			i += 1
			continue
		if c == "<":
			tokens.append({"type": "OP", "value": "<"})
			i += 1
			continue
		_error("unexpected character '%s'" % c)
		i += 1
	tokens.append({"type": "EOF"})
	return tokens


func _peek() -> Dictionary:
	return _tokens[_pos]


func _advance() -> Dictionary:
	var token := _tokens[_pos]
	if _pos < _tokens.size() - 1:
		_pos += 1
	return token


func _expect(type: String) -> void:
	if _peek().type != type:
		_error("expected %s, got %s" % [type, _peek().type])
		return
	_advance()


func _error(message: String) -> void:
	_had_error = true
	push_error("VNExpressionParser: %s" % message)


func _parse_or() -> Dictionary:
	var left := _parse_and()
	while _peek().type == "OR":
		_advance()
		var right := _parse_and()
		left = {"type": "logical", "op": "or", "left": left, "right": right}
	return left


func _parse_and() -> Dictionary:
	var left := _parse_not()
	while _peek().type == "AND":
		_advance()
		var right := _parse_not()
		left = {"type": "logical", "op": "and", "left": left, "right": right}
	return left


func _parse_not() -> Dictionary:
	if _peek().type == "NOT":
		_advance()
		return {"type": "not", "operand": _parse_not()}
	return _parse_comparison()


func _parse_comparison() -> Dictionary:
	var left := _parse_primary()
	if _peek().type == "OP":
		var op: String = _advance().value
		var right := _parse_primary()
		return {"type": "compare", "op": op, "left": left, "right": right}
	return left


func _parse_primary() -> Dictionary:
	var token := _peek()
	match token.type:
		"NUMBER", "STRING", "BOOL":
			_advance()
			return {"type": "literal", "value": token.value}
		"LPAREN":
			_advance()
			var inner := _parse_or()
			_expect("RPAREN")
			return inner
		"IDENT":
			_advance()
			var name: String = token.value
			_expect("LPAREN")
			var args: Array[Dictionary] = []
			if _peek().type != "RPAREN":
				args.append(_parse_or())
				while _peek().type == "COMMA":
					_advance()
					args.append(_parse_or())
			_expect("RPAREN")
			return {"type": "call", "name": name, "args": args}
		_:
			_error("unexpected token %s" % token.type)
			return {"type": "literal", "value": null}
