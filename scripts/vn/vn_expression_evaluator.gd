class_name VNExpressionEvaluator
extends RefCounted
## Evaluates the AST produced by VNExpressionParser. See docs/design/systems.md, system 13.
##
## One dispatch table serves both roles the expression language plays:
## condition checks (has_flag, affection, ...) that return a value, and
## action calls (set_flag, add_affection, ...) that cause a side effect and
## return null. The parser doesn't distinguish between them structurally —
## both are just "call" nodes — so neither does this.
##
## degrees_of_success() is the one function whose value isn't read from an
## autoload — it's a transient per-evaluation input, set by whichever caller
## rolled a check (currently only ArtStudio, resolving an Inspiration's
## completion roll) via set_degrees_of_success() immediately before
## evaluating that roll's reward expressions, and reset after. Zero outside
## that window, same as any unset condition would read.

static var _degrees_of_success: int = 0

## The subset of _call_function()'s dispatch table that's valid as a single
## UpgradeDef.effect_target / curse penalty target (a bare name + one numeric
## amount, as opposed to the richer VN action-call functions like give_item
## which take multiple typed args). Read by the effect_target dropdown
## EditorInspectorPlugin (addons/engine_scaffolding) instead of the plugin
## hardcoding its own copy of these names. See docs/engine_roadmap.md, Phase 4.
const EFFECT_TARGET_KEYS := [
	"shop_capacity",
	"change_reputation",
	"change_buy_rate",
]


## Called by a roll-resolving caller (e.g. ArtStudio._complete_work()) right
## before evaluating a batch of expressions that may reference
## degrees_of_success() — reset to 0 once that batch is done so a later,
## unrelated evaluation doesn't see a stale roll's result.
static func set_degrees_of_success(value: int) -> void:
	_degrees_of_success = value


## Public entry point for callers applying a single named effect + numeric
## amount without a full VN expression tree -- UpgradeDef.effect_target and
## CurseDef penalty targets both route through here instead of keeping their
## own match/dispatch blocks, so there's one registry with one list of valid
## keys shared with the VN/quest action-call language above. See
## docs/engine_roadmap.md, Phase 3.
static func call_effect(name: String, amount: float) -> void:
	_call_function(name, [amount])


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
		"add_materials":
			Inventory.add_materials(int(args[0]))
			return null
		"add_reputation":
			Shop.add_reputation(int(args[0]))
			return null
		"degrees_of_success":
			return _degrees_of_success
		"skill_level":
			return Skills.level(args[0])
		"start_quest":
			QuestManager.start_quest(args[0])
			return null
		"current_room":
			return GameFlow.current_room_id
		"minute_of_day":
			return Clock.minute_of_day()
		"day_name":
			return Clock.day_name()
		"is_weekend":
			return Clock.day_type() == Clock.DayType.WEEKEND
		"is_dating":
			return LoveInterests.is_dating(args[0])
		"set_dating":
			LoveInterests.set_dating(args[0])
			return null
		"npc_mood":
			return NPCState.get_mood(args[0])
		"npc_funds":
			return NPCState.get_funds(args[0])
		"npc_relationship":
			return NPCState.get_relationship(args[0], args[1])
		# --- UpgradeDef.effect_target / CurseDef penalty targets, routed
		# through call_effect() above rather than the VN parser. ---
		"shop_capacity":
			Shop.capacity += int(args[0])
			return null
		"change_reputation":
			Shop.add_reputation(int(args[0]))
			return null
		"change_buy_rate":
			Shop.add_buy_rate_modifier(args[0])
			return null
		_:
			push_warning("VNExpressionEvaluator: unknown function '%s'" % function_name)
			return null
