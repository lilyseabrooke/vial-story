class_name AlembicUpgradeDef
extends RefCounted
## A purchasable Alembic upgrade, loaded from data/alembic_upgrades.json
## rather than a .tres — see docs/design/systems.md, system 4. JSON (not the
## repo's usual Resource/.tres convention) is used here specifically because
## each entry's effects/tags/excludes lists are variable-shape and painful to
## hand-author as parallel typed-array exports.

var id: String
var display_name: String
var cost: int
var effects: Dictionary  # effect_target String -> float, e.g. {"brew_speed": 0.25}
var tags: Array[String]
var excludes: Array[String]


static func from_dict(d: Dictionary) -> AlembicUpgradeDef:
	var def := AlembicUpgradeDef.new()
	def.id = d.get("id", "")
	def.display_name = d.get("display_name", "")
	def.cost = d.get("cost", 0)
	def.effects = d.get("effects", {})
	var tag_list: Array[String] = []
	tag_list.assign(d.get("tags", []))
	def.tags = tag_list
	var exclude_list: Array[String] = []
	exclude_list.assign(d.get("excludes", []))
	def.excludes = exclude_list
	return def
