class_name PuzzleConstraintType
extends RefCounted
## Single source of truth for PotionDef.puzzle_constraint_types string ids.
## Read by both Alchemy._check_constraint() (evaluates pass/fail against a
## candidate ingredient selection) and PotionDef.describe_puzzle_constraint()
## (renders player-facing objective text) so a new constraint type only needs
## adding to ALL, not kept in sync across two separate match blocks by hand.
## See docs/engine_roadmap.md, Phase 3.

const CHARACTERISTIC_RANGE := "characteristic_range"
const TOTAL_WEIGHT_RANGE := "total_weight_range"
const INGREDIENT_COUNT_RANGE := "ingredient_count_range"
const ROLE_LIGHTEST := "role_lightest"
const ROLE_HEAVIEST := "role_heaviest"

const ALL := [
	CHARACTERISTIC_RANGE,
	TOTAL_WEIGHT_RANGE,
	INGREDIENT_COUNT_RANGE,
	ROLE_LIGHTEST,
	ROLE_HEAVIEST,
]
