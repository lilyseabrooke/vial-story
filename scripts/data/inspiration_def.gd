class_name InspirationDef
extends RefCounted
## A single "idea for what to create" the Art Studio can offer after its
## initial gathering-inspiration roll fills, loaded from data/inspirations.json
## rather than a .tres -- same "variable-shape, hand-authored catalog"
## reasoning as LeyLineSurgeDef/AlembicUpgradeDef. See docs/design/systems.md,
## the Art Studio / Creativity System section.
##
## `conditions` is an array of VNExpressionParser-grammar bool expressions
## (the same language as QuestDef.complete_condition/SceneTriggerDef.condition)
## -- every one must evaluate true for this Inspiration to be eligible when
## ArtStudio rolls its offered set. `rewards` is an array of Dictionaries
## rather than parallel arrays, since each entry carries three independent
## pieces (an action expression, a fire chance, and an optional gating
## condition) -- awkward as three same-length parallel arrays, natural as one
## dict per entry when the source is JSON anyway. `action` reuses the same
## VNExpressionParser/VNExpressionEvaluator action-call vocabulary as a quest
## reward (give_item, add_affection, set_flag, add_materials, add_reputation,
## ...) plus degrees_of_success(), evaluator-only and only meaningful while
## ArtStudio is resolving a completion roll's rewards (see
## VNExpressionEvaluator.set_degrees_of_success()).

var id: String
var display_name: String
var description: String
var dc: int
var completion_time: int   # minutes of tethered work required
var unique: bool
var weight: float          # selection weight among the eligible pool when offered
var conditions: Array[String] = []
var rewards: Array = []    # Array[Dictionary] -- {action: String, chance: float, condition: String}


static func from_dict(d: Dictionary) -> InspirationDef:
	var def := InspirationDef.new()
	def.id = d.get("id", "")
	def.display_name = d.get("display_name", def.id)
	def.description = d.get("description", "")
	def.dc = d.get("dc", 10)
	def.completion_time = d.get("completion_time", 60)
	def.unique = d.get("unique", false)
	def.weight = d.get("weight", 1.0)
	var parsed_conditions: Array[String] = []
	for entry in (d.get("conditions", []) as Array):
		parsed_conditions.append(entry as String)
	def.conditions = parsed_conditions
	var parsed_rewards: Array = []
	for entry in (d.get("rewards", []) as Array):
		var reward: Dictionary = entry
		parsed_rewards.append({
			"action": reward.get("action", ""),
			"chance": float(reward.get("chance", 1.0)),
			"condition": reward.get("condition", "true"),
		})
	def.rewards = parsed_rewards
	return def
