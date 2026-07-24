class_name WaterPumpUpgradeDef
extends RefCounted
## A purchasable Water Pump upgrade, loaded from data/water_pump_upgrades.json
## rather than a .tres -- see docs/design/systems.md, system 7. Mirrors
## AlembicUpgradeDef's JSON-not-.tres reasoning, trimmed to what Water Pump
## upgrades actually need: no tags/excludes, since nothing here is mutually
## exclusive the way some Alembic upgrades are.

var id: String
var display_name: String
var cost: int
var effects: Dictionary  # effect_target String -> float, e.g. {"grow_yield_bonus": 0.10}


static func from_dict(d: Dictionary) -> WaterPumpUpgradeDef:
	var def := WaterPumpUpgradeDef.new()
	def.id = d.get("id", "")
	def.display_name = d.get("display_name", "")
	def.cost = d.get("cost", 0)
	def.effects = d.get("effects", {})
	return def
