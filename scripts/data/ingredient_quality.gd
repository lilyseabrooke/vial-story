class_name IngredientQuality
extends RefCounted
## Shared quality-tier constants for ingredient stacks. Quality is a property
## of an inventory stack, not of IngredientDef -- every tier has identical
## category/weight/characteristics, only the brew bonus differs. See
## docs/design/systems.md, systems 2 and 4.

enum Tier { POOR, NORMAL, GOOD, EXCELLENT, PERFECT }

const NAMES := ["Poor", "Normal", "Good", "Excellent", "Perfect"]
const COLORS := [
	Color(0.72, 0.32, 0.28),  # Poor -- muted red
	Color(0.82, 0.82, 0.82),  # Normal -- neutral grey
	Color(0.42, 0.75, 0.4),   # Good -- green
	Color(0.35, 0.55, 0.9),   # Excellent -- blue
	Color(0.92, 0.75, 0.25),  # Perfect -- gold
]

## Added directly to a brewed potion's rolled_potency/rolled_ease. Scaled
## against Brewing.STAT_VARIANCE (5.0) and typical potency/ease ranges
## (~20-25 wide) -- noticeable but not dominant.
const BREW_BONUS := [-8.0, 0.0, 4.0, 9.0, 15.0]

const _THRESHOLDS := [0.95, 0.80, 0.55, 0.25]  # Perfect, Excellent, Good, Normal cutoffs


static func label(tier: int) -> String:
	return NAMES[tier]


static func color(tier: int) -> Color:
	return COLORS[tier]


static func brew_bonus(tier: int) -> float:
	return BREW_BONUS[tier]


## Maps a 0..1 performance/quality fraction to a Tier. Shared by every
## ingredient-producing system (Herbalism, Demonology, Ley Lines) so the
## tiering curve only lives in one place.
static func tier_for_fraction(fraction: float) -> int:
	if fraction >= _THRESHOLDS[0]:
		return Tier.PERFECT
	if fraction >= _THRESHOLDS[1]:
		return Tier.EXCELLENT
	if fraction >= _THRESHOLDS[2]:
		return Tier.GOOD
	if fraction >= _THRESHOLDS[3]:
		return Tier.NORMAL
	return Tier.POOR
