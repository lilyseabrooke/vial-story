class_name RecipeDef
extends Resource
## Static definition of a recipe. See docs/design/systems.md, system 3.
##
## ingredient_ids/ingredient_quantities are parallel arrays rather than a
## nested resource, so recipe .tres files stay simple to hand-author.

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


func requirement_for(ingredient_id: String) -> int:
	var idx := ingredient_ids.find(ingredient_id)
	return ingredient_quantities[idx] if idx != -1 else 0
