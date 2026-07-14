class_name VNExpressionEvaluator
extends RefCounted
## Evaluates the AST produced by VNExpressionParser. See docs/design/systems.md, system 13.
##
## One dispatch table serves both roles the expression language plays:
## condition checks (has_flag, affection, ...) that return a value, and
## action calls (set_flag, add_affection, ...) that cause a side effect and
## return null. The parser doesn't distinguish between them structurally —
## both are just "call" nodes — so neither does this.


static func evaluate(node: Dictionary) -> Variant:
	match node.type:
		"literal":
			return node.value
		"not":
			return not evaluate(node.operand)
		"logical":
			var left = evaluate(node.left)
			if node.op == "and":
				return left and evaluate(node.right)
			return left or evaluate(node.right)
		"compare":
			var left = evaluate(node.left)
			var right = evaluate(node.right)
			match node.op:
				"==":
					return left == right
				"!=":
					return left != right
				">=":
					return left >= right
				"<=":
					return left <= right
				">":
					return left > right
				"<":
					return left < right
			return null
		"call":
			var args: Array = []
			for arg in node.args:
				args.append(evaluate(arg))
			return _call_function(node.name, args)
		_:
			push_warning("VNExpressionEvaluator: unknown node type '%s'" % node.type)
			return null


static func _call_function(function_name: String, args: Array) -> Variant:
	match function_name:
		"has_flag":
			return Story.has_flag(args[0])
		"set_flag":
			Story.set_flag(args[0], true)
			return null
		"clear_flag":
			Story.set_flag(args[0], false)
			return null
		"affection":
			return LoveInterests.get_affection(args[0])
		"add_affection":
			LoveInterests.add_affection(args[0], int(args[1]))
			return null
		"has_item":
			return Inventory.ingredient_count(args[0]) > 0
		"give_item":
			var quantity := int(args[1])
			if quantity >= 0:
				Inventory.add_ingredient(args[0], quantity)
			else:
				Inventory.consume_ingredient(args[0], -quantity)
			return null
		"materials":
			return Inventory.materials
		"skill_level":
			return Skills.level(args[0])
		"start_quest":
			QuestManager.start_quest(args[0])
			return null
		_:
			push_warning("VNExpressionEvaluator: unknown function '%s'" % function_name)
			return null
