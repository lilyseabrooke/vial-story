class_name LeyLineSurgeDef
extends RefCounted
## A Ley Line Surge a meditating LeyLineNodeInteractable can roll into once
## its bar fills, loaded from data/ley_line_surges.json rather than a .tres --
## same "variable-shape, hand-authored catalog" reasoning as AlembicUpgradeDef.
## See docs/design/systems.md, the Ley Line Node System section.
##
## `size`/`speed` are stubbed -- carried through so a node's rolled Surge can
## eventually size/speed-tune the minigame arena, but nothing reads them yet.
## `rewards` is an array of [ingredient_id: String, likelihood: float] pairs
## rather than a Dictionary so ordering is stable and hand-authoring the JSON
## stays simple; likelihoods above 1.0 are intentional (see
## LeyLines._roll_rewards()) so a single entry can guarantee more than one of
## an ingredient.

var id: String
var difficulty: float
var size: float
var speed: float
var dc: int
var rounds: int
var rewards: Array   # Array[Array] -- each inner element is [String, float]


static func from_dict(d: Dictionary) -> LeyLineSurgeDef:
	var def := LeyLineSurgeDef.new()
	def.id = d.get("id", "")
	def.difficulty = d.get("difficulty", 0.0)
	def.size = d.get("size", 0.0)
	def.speed = d.get("speed", 0.0)
	def.dc = d.get("dc", 0)
	def.rounds = d.get("rounds", 0)
	var reward_list: Array = []
	for entry in (d.get("rewards", []) as Array):
		var pair: Array = entry
		reward_list.append([pair[0] as String, pair[1] as float])
	def.rewards = reward_list
	return def
