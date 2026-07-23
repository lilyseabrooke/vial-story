class_name RecipeDef
extends Resource
## Static definition of a recipe — one learned *way* to make a potion. See
## docs/design/systems.md, system 3.
##
## ingredient_ids/ingredient_quantities are parallel arrays rather than a
## nested resource, so recipe .tres files stay simple to hand-author.
##
## Everything about the potion itself (brewing stats, discovery criteria)
## lives on PotionDef instead, keyed by output_potion_id — a RecipeDef is
## just one ingredient combination that satisfies it. Most RecipeDefs aren't
## hand-authored .tres files at all: Alchemy.attempt_discovery() synthesizes
## a new one at runtime whenever the player finds a fresh combination that
## passes a potion's puzzle criteria. `known` only seeds Alchemy's
## learned-recipe set at the start of a new game (which recipes the player
## starts already knowing) — every other system asks Alchemy.is_learned(id)
## at runtime instead of reading this directly, since a recipe's learned
## state can change during play.
##
## display_name here is the *method* label (e.g. "Ember Dust + Rift Glass"),
## not the potion's name — the potion's own display_name lives on its
## PotionDef (ContentRegistry.get_potion(output_potion_id)).

@export var id: String
@export var display_name: String
@export var known: bool = true
@export var output_potion_id: String = ""
@export var ingredient_ids: Array[String] = []
@export var ingredient_quantities: Array[int] = []


func requirement_for(ingredient_id: String) -> int:
	var idx := ingredient_ids.find(ingredient_id)
	return ingredient_quantities[idx] if idx != -1 else 0
