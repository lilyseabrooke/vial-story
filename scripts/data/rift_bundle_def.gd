class_name RiftBundleDef
extends Resource
## Static definition of one Planar Rift summoning outcome. See
## docs/design/systems.md, the Summoning / Planar Rift System section.
##
## ingredient_ids/ingredient_quantities are parallel arrays, same convention
## as RecipeDef's ingredient lists, so bundles stay simple to hand-author.
## Everything here is fixed at authoring time -- the minigame (the symbol-
## sequence puzzle in PlanarRiftMinigamePanel) only chooses which bundle
## applies via `sequence`, it never rolls or scales these numbers further.

@export var id: String
@export var display_name: String
## The symbol id sequence the player must build in the Planar Rift minigame
## to summon this bundle -- each entry is a Summoning.SUMMONING_SYMBOLS id.
## Length 4-8 (Summoning.MAX_SEQUENCE_LENGTH). **Author sequences prefix-free:**
## no bundle's sequence may be a prefix of another's, or the shorter one would
## always match first and the longer could never be reached. Giving each
## bundle a distinct *first* symbol satisfies this trivially.
@export var sequence: Array[String] = []
## Relative odds this bundle used to be picked by the old random stand-in.
## The minigame chooses by matched sequence now, so this is unused by the
## live path -- kept only so the .tres files and any future weighting hook
## don't need reworking.
@export var weight: float = 1.0
@export var duration_minutes: int = 60

## --- Base rewards: always granted, quality-independent (the floor) ---
@export var ingredient_ids: Array[String] = []
@export var ingredient_quantities: Array[int] = []
## Applied to Inventory.materials on collection -- positive gains, negative
## costs. Unlike a purchase, this is never blocked by insufficient funds
## (the exchange already happened out on the plane); it's just added.
@export var material_delta: int = 0
## Applied via Resolve.spend()/restore() on collection -- positive restores,
## negative costs.
@export var resolve_delta: int = 0

## --- Quality-scaled rewards: quantity multiplied by the summon's 0..1
## quality (see Summoning), granted on top of the base. The authored number is
## the amount at quality 1.0; `round(qty * quality)` is what actually lands, so
## a sloppy summon yields little or none and a pristine one yields the full
## figure. Parallel arrays, same convention as the base lists. ---
@export var scaled_ingredient_ids: Array[String] = []
@export var scaled_ingredient_quantities: Array[int] = []
## Extra Materials worth `round(scaled_material_bonus * quality)`, added on top
## of material_delta. Always a gain (a bonus), unlike the base delta.
@export var scaled_material_bonus: int = 0

## --- Quality-gated rewards: the full quantity, but only if the summon's
## quality reaches the paired threshold (0..1). All three arrays are parallel:
## gated_ingredient_ids[i] x gated_ingredient_quantities[i] is granted iff
## quality >= gated_ingredient_min_quality[i]. Use these for the rare "only a
## flawless summon brings this through" payoffs. ---
@export var gated_ingredient_ids: Array[String] = []
@export var gated_ingredient_quantities: Array[int] = []
@export var gated_ingredient_min_quality: Array[float] = []
## Shown in the collection log message -- the "what actually happened out
## there" flavor line, since the mechanical outcome alone doesn't say much.
@export var flavor_text: String = ""
