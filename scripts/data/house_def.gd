class_name HouseDef
extends Resource
## Static display data for an academy House, chosen at character creation.
## See docs/design/systems.md, system 14.

@export var id: String
@export var display_name: String
## Placeholder tile tint until Houses have real crest art — HouseDef has no
## category to derive a tint from (unlike ShopLocationDef/IngredientDef), so
## each House is hand-authored its own color here.
@export var placeholder_color: Color = Color.WHITE
