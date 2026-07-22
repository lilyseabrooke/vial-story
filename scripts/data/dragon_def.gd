class_name DragonDef
extends Resource
## Static tuning data for one dragon size tier roaming the Dragons' Ground.
## See docs/design/systems.md, the Dragons / Roaming Threats section.

@export var id: String = ""
@export var display_name: String = ""
## Relative spawn commonality -- higher spawns more often. Small dragons use
## a high weight (common), extra-large a low one (rare), same "weight, not
## percentage" shape as ShopStock's sale-chance weighting.
@export var spawn_weight: float = 1.0
@export var visual_color: Color = Color(0.6, 0.2, 0.2)
## Placeholder art radius -- also sizes the dragon's collision circle.
@export var visual_radius: float = 16.0

## Base distance (world units) at which this dragon notices an unwelcome
## player and starts chasing. Reduced by the player's Draconology skill
## level -- see Dragon.PROVOKE_RANGE_PER_DRACONOLOGY_LEVEL.
@export var provoke_range: float = 140.0
## If > 0, a player whose Draconology level is at or above this never
## provokes this dragon at all, regardless of distance -- the "small dragons
## might not even bother with a skilled player" case. 0 means always
## provokable no matter the player's skill.
@export var never_provoke_draconology_level: int = 0

@export var roam_speed: float = 45.0
@export var roam_radius: float = 150.0
@export var chase_speed: float = 95.0

## Distance at which a chasing dragon actually lands a hit.
@export var attack_range: float = 30.0
@export var resolve_damage: int = 10
@export var knockback_force: float = 260.0
## How long the dragon stands still after landing a hit before resuming its
## chase -- the window that gives the player a real chance to flee.
@export var attack_pause_seconds: float = 1.5
