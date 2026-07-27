class_name CurseDef
extends RefCounted
## A hand-placed Curse's dispel criteria and shop penalties, loaded from
## data/curses.json rather than a .tres -- same "variable-shape, hand-authored
## catalog" reasoning as AlembicUpgradeDef/LeyLineSurgeDef. See
## docs/design/systems.md, system 11.
##
## minima/maxima are arrays of [characteristic_id: String, value: float] pairs
## -- same "array of pairs, not a Dictionary" convention as LeyLineSurgeDef's
## rewards, so ordering is stable and a single characteristic could carry more
## than one band later without collapsing entries. Bands are summed the same
## way PotionDef's "characteristic_range" puzzle constraint is (see
## Alchemy._check_constraint()) -- a curse's dispel check is that same idea,
## reused against Curse instead of Alchemy.
##
## permitted_ingredients restricts the ingredient *categories*
## (IngredientDef.Category, lowercase name, e.g. "spectral") usable in a
## dispel attempt; empty means any category is allowed.
##
## penalties are parsed from "effect_target(amount)" strings (e.g.
## "change_buy_rate(-20)") rather than a Dictionary, matching how the design
## doc described the format -- Curse._apply_penalty() is the match statement
## that resolves each target, same effect_target-string pattern as
## Economy._apply_effect().

var id: String
var minima: Array               # Array[[String, float]]
var maxima: Array               # Array[[String, float]]
var permitted_ingredients: Array[String]
var penalties: Array            # Array[{"target": String, "amount": float}]
var description: String


static func from_dict(d: Dictionary) -> CurseDef:
	var def := CurseDef.new()
	def.id = d.get("id", "")
	def.minima = _load_pairs(d.get("minima", []))
	def.maxima = _load_pairs(d.get("maxima", []))
	var permitted: Array[String] = []
	permitted.assign(d.get("permitted_ingredients", []))
	def.permitted_ingredients = permitted
	var penalty_list: Array = []
	for entry in (d.get("penalties", []) as Array):
		penalty_list.append(_parse_penalty(entry as String))
	def.penalties = penalty_list
	def.description = d.get("description", "")
	return def


static func _load_pairs(raw: Array) -> Array:
	var pairs: Array = []
	for entry in raw:
		var pair: Array = entry
		pairs.append([pair[0] as String, float(pair[1])])
	return pairs


## Parses "effect_target(amount)" (e.g. "change_buy_rate(-20)") into
## {"target": "change_buy_rate", "amount": -20.0}.
static func _parse_penalty(text: String) -> Dictionary:
	var open_paren := text.find("(")
	var close_paren := text.rfind(")")
	if open_paren == -1 or close_paren == -1:
		return {"target": text, "amount": 0.0}
	var target := text.substr(0, open_paren)
	var amount := float(text.substr(open_paren + 1, close_paren - open_paren - 1))
	return {"target": target, "amount": amount}


func describe_minimum(index: int) -> String:
	var pair: Array = minima[index]
	return "At least %s %s" % [_fmt_num(pair[1]), String(pair[0]).capitalize()]


func describe_maximum(index: int) -> String:
	var pair: Array = maxima[index]
	return "At most %s %s" % [_fmt_num(pair[1]), String(pair[0]).capitalize()]


func _fmt_num(value: float) -> String:
	return "%d" % int(value) if is_equal_approx(value, roundf(value)) else "%.1f" % value
