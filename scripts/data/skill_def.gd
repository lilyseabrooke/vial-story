class_name SkillDef
extends Resource
## Static definition of a skill. See docs/design/systems.md, system 6.
##
## effect_levels/effect_targets/effect_amounts are parallel arrays (same
## hand-authoring approach as RecipeDef's ingredient lists): at the given
## level, the given effect_target gains effect_amount, cumulatively.

@export var id: String
@export var display_name: String
@export var xp_per_level: int = 100
@export var effect_levels: Array[int] = []
@export var effect_targets: Array[String] = []
@export var effect_amounts: Array[float] = []
