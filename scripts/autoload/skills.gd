extends Node
## Skill XP, leveling, and the passive effect bonuses skills grant.
## Autoloaded as "Skills". See docs/design/systems.md, system 6.
##
## Other systems (Brewing, later Herbalism/Summoning) fire XP events here and
## read back accumulated bonuses via get_bonus(effect_target) — this system
## doesn't know what a "station" or "recipe" is, it just tracks numbers.

signal xp_gained(skill_id: String, xp: int, level: int)
signal leveled_up(skill_id: String, new_level: int)

const SKILL_PATHS := [
	"res://data/skills/brewing.tres",
	"res://data/skills/herbalism.tres",
]

var _defs: Dictionary = {}          # skill_id -> SkillDef
var _xp: Dictionary = {}            # skill_id -> int
var _levels: Dictionary = {}        # skill_id -> int
var _bonus_totals: Dictionary = {}  # effect_target -> float, summed across all skills


func _ready() -> void:
	for path in SKILL_PATHS:
		register(load(path) as SkillDef)


func register(def: SkillDef) -> void:
	_defs[def.id] = def
	_xp[def.id] = 0
	_levels[def.id] = 0


func add_xp(skill_id: String, amount: int) -> void:
	if not _defs.has(skill_id):
		push_warning("Unknown skill_id: %s" % skill_id)
		return

	_xp[skill_id] += amount
	var def: SkillDef = _defs[skill_id]

	@warning_ignore("integer_division")
	var new_level: int = _xp[skill_id] / def.xp_per_level if def.xp_per_level > 0 else 0
	xp_gained.emit(skill_id, _xp[skill_id], _levels[skill_id])

	while new_level > _levels[skill_id]:
		_levels[skill_id] += 1
		_apply_level_effects(def, _levels[skill_id])
		leveled_up.emit(skill_id, _levels[skill_id])


func _apply_level_effects(def: SkillDef, new_level: int) -> void:
	for i in def.effect_levels.size():
		if def.effect_levels[i] == new_level:
			var target: String = def.effect_targets[i]
			_bonus_totals[target] = _bonus_totals.get(target, 0.0) + def.effect_amounts[i]


## Total passive bonus granted to effect_target by all skills combined
## (e.g. "station_potency") — additive on top of station/upgrade modifiers.
## Halved while Resolve is strained (system 8) — a debuff to all skills.
func get_bonus(effect_target: String) -> float:
	var total: float = _bonus_totals.get(effect_target, 0.0)
	if Resolve.is_strained():
		total *= Resolve.STRAINED_DEBUFF_MULTIPLIER
	return total


func skill_ids() -> Array:
	return _defs.keys()


func get_def(skill_id: String) -> SkillDef:
	return _defs.get(skill_id)


func level(skill_id: String) -> int:
	return _levels.get(skill_id, 0)


func xp_for(skill_id: String) -> int:
	return _xp.get(skill_id, 0)


func xp_to_next_level(skill_id: String) -> int:
	var def: SkillDef = _defs.get(skill_id)
	if def == null or def.xp_per_level <= 0:
		return 0
	return def.xp_per_level - (xp_for(skill_id) % def.xp_per_level)


func get_save_data() -> Dictionary:
	return {"xp": _xp.duplicate()}


## _xp is the only source of truth; _levels/_bonus_totals are re-derived by
## replaying add_xp() through the same _apply_level_effects() path a live
## game would have taken, so leveling/bonus logic is never duplicated here.
func load_save_data(data: Dictionary) -> void:
	var saved_xp: Dictionary = data.get("xp", {})
	for skill_id in _defs:
		_xp[skill_id] = 0
		_levels[skill_id] = 0
	_bonus_totals.clear()
	for skill_id in saved_xp:
		if _defs.has(skill_id):
			add_xp(skill_id, saved_xp[skill_id])
