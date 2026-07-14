class_name ShopLocationDef
extends Resource
## Static definition of a shop-origin choice offered at character creation. Each
## location stubs in a favored IngredientDef.Category for later mechanical use
## (e.g. discounted/foraged supply of that category) — not yet implemented
## anywhere. See docs/design/systems.md, system 14.

@export var id: String
@export var display_name: String
@export var flavor_text: String
@export var ingredient_category: IngredientDef.Category = IngredientDef.Category.NATURAL
