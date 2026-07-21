class_name RecipeDef
extends Resource
## Static definition of a recipe. See docs/design/systems.md, system 3.
##
## ingredient_ids/ingredient_quantities are parallel arrays rather than a
## nested resource, so recipe .tres files stay simple to hand-author.
##
## `known` only seeds Alchemy's learned-recipe set at the start of a new game
## now (which recipes the player starts already knowing) — every other
## system asks Alchemy.is_learned(id) at runtime instead of reading this
## directly, since a recipe's learned state can change during play.

@export var id: String
@export var display_name: String
@export var known: bool = true
@export var station_type: String = "alembic"
@export var brew_time_minutes: int = 60
@export var ingredient_ids: Array[String] = []
@export var ingredient_quantities: Array[int] = []
@export var potency_range: Vector2 = Vector2(0, 100)
@export var ease_range: Vector2 = Vector2(0, 100)
@export var output_potion_id: String = ""
@export var unlock_minigame_id: String = ""

## The recipe-discovery puzzle: a set of objectives an ingredient selection
## must satisfy for Alchemy.attempt_puzzle() to learn this recipe. Parallel
## arrays, same convention as ingredient_ids/ingredient_quantities, rather
## than a nested constraint Resource per entry, so puzzles stay easy to
## hand-author directly in a .tres file.
##
## puzzle_constraint_types entries (String, matched in Alchemy):
##   "characteristic_range"  — target = a characteristic id (e.g. "necromantic");
##                              summed value across chosen ingredients must fall
##                              within [min, max].
##   "total_weight_range"    — target unused; combined ingredient weight must
##                              fall within [min, max].
##   "ingredient_count_range"— target unused; total ingredient units used must
##                              fall within [min, max].
##   "role_lightest"         — target = a role name ("base"/"binder"/"catalyst");
##                              every ingredient of that role must be strictly
##                              lighter than every ingredient of any other role
##                              present. min/max unused.
##   "role_heaviest"         — same as role_lightest, but strictly heavier.
## Use a very large/small min or max (e.g. -9999/9999) to express a one-sided
## bound ("at most"/"at least").
@export var puzzle_constraint_types: Array[String] = []
@export var puzzle_constraint_targets: Array[String] = []
@export var puzzle_constraint_min: Array[float] = []
@export var puzzle_constraint_max: Array[float] = []


func requirement_for(ingredient_id: String) -> int:
	var idx := ingredient_ids.find(ingredient_id)
	return ingredient_quantities[idx] if idx != -1 else 0


func has_puzzle() -> bool:
	return not puzzle_constraint_types.is_empty()


func describe_puzzle_constraint(index: int) -> String:
	var target := puzzle_constraint_targets[index]
	var min_value := puzzle_constraint_min[index]
	var max_value := puzzle_constraint_max[index]
	match puzzle_constraint_types[index]:
		"characteristic_range":
			return "%s must total between %s and %s" % [target.capitalize(), _fmt_num(min_value), _fmt_num(max_value)]
		"total_weight_range":
			return "Total weight must be between %s and %s" % [_fmt_num(min_value), _fmt_num(max_value)]
		"ingredient_count_range":
			return "Must use between %d and %d ingredient unit(s)" % [int(min_value), int(max_value)]
		"role_lightest":
			return "The %s must be the lightest component" % target
		"role_heaviest":
			return "The %s must be the heaviest component" % target
	return ""


func _fmt_num(value: float) -> String:
	return "%d" % int(value) if is_equal_approx(value, roundf(value)) else "%.1f" % value
