@icon("res://assets/editor_icons/icon_recipe.svg")
class_name PotionDef
extends Resource
## Static definition of a potion. See docs/design/systems.md, system 3.
##
## Owns everything about the potion itself — its brewing stats and its
## recipe-discovery criteria — as opposed to RecipeDef, which is just one
## learned *way* to make it (a specific ingredient combination).

@export var id: String
@export var display_name: String

## Source data for the composited PotionIcon template (see
## scenes/ui/components/PotionIcon.tscn) — which tier's layer art to use and
## what color to modulate the base layer with. ContentRegistry bakes these into
## `icon` at load time via an offscreen PotionIcon render, so every UI
## component that reads `icon` (ItemSlot, RecipeEntry, brew_menu chips, etc.)
## never needs to know PotionIcon exists.
@export_range(1, 4) var icon_level: int = 1
@export var icon_color: Color = Color.WHITE

## Baked by ContentRegistry from icon_level/icon_color — leave unset in .tres.
@export var icon: Texture2D
@export_enum("alembic") var station_type: String = "alembic"
@export var brew_time_minutes: int = 60
@export var potency_range: Vector2 = Vector2(0, 100)
@export var ease_range: Vector2 = Vector2(0, 100)

## Multiplier on the potency/ease-derived sell price (Shop._compute_price) —
## how much this potion is inherently worth for the same potency/ease stats,
## e.g. a rarer or more dangerous potion selling for more than a mundane one.
@export var value: float = 1.0

## Arbitrary labels for what the potion is "for" — e.g. "healing", "divination",
## "empowerment", "poison", "stealth", "movement", "study", "creature" — so other
## systems (quests, buyer requests) can search by intent ("a potion to help me
## prep before my practical") instead of naming a specific PotionDef. Purely
## descriptive metadata for now; nothing reads these yet.
@export var tags: Array[String] = []

## The recipe-discovery puzzle: a set of objectives an ingredient selection
## must satisfy for Alchemy.attempt_discovery() to synthesize a new learned
## recipe for this potion. Parallel arrays, same convention as
## RecipeDef's ingredient_ids/ingredient_quantities, rather than a nested
## constraint Resource per entry, so puzzles stay easy to hand-author directly
## in a .tres file.
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


func has_puzzle() -> bool:
	return not puzzle_constraint_types.is_empty()


func describe_puzzle_constraint(index: int) -> String:
	var target := puzzle_constraint_targets[index]
	var min_value := puzzle_constraint_min[index]
	var max_value := puzzle_constraint_max[index]
	match puzzle_constraint_types[index]:
		PuzzleConstraintType.CHARACTERISTIC_RANGE:
			return "%s must total between %s and %s" % [target.capitalize(), _fmt_num(min_value), _fmt_num(max_value)]
		PuzzleConstraintType.TOTAL_WEIGHT_RANGE:
			return "Total weight must be between %s and %s" % [_fmt_num(min_value), _fmt_num(max_value)]
		PuzzleConstraintType.INGREDIENT_COUNT_RANGE:
			return "Must use between %d and %d ingredient unit(s)" % [int(min_value), int(max_value)]
		PuzzleConstraintType.ROLE_LIGHTEST:
			return "The %s must be the lightest component" % target
		PuzzleConstraintType.ROLE_HEAVIEST:
			return "The %s must be the heaviest component" % target
	return ""


func _fmt_num(value: float) -> String:
	return "%d" % int(value) if is_equal_approx(value, roundf(value)) else "%.1f" % value
