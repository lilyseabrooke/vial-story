class_name SeedDef
extends Resource
## Static definition of a plantable seed. See docs/design/systems.md, system 7.
##
## Kept separate from IngredientDef since a seed is a distinct inventory item
## (bought/held separately) that, once grown, yields a quantity of a
## different ingredient — the relationship RecipeDef has to potions.

@export var id: String
@export var display_name: String
@export var buy_price: int = 0
@export var yields_ingredient_id: String = ""
@export var growth_minutes: int = 480
@export var base_yield: int = 3
