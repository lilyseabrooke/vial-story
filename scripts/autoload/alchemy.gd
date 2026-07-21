extends Node
## Tracks which recipes the player has learned, and evaluates the
## ingredient-combination puzzle used to learn a recipe that isn't known yet.
## Autoloaded as "Alchemy". See docs/design/systems.md, system 3.
##
## RecipeDef.known only seeds this set at the start of a new game — every
## other system asks Alchemy.is_learned(id) at runtime instead of reading
## RecipeDef.known directly, so a recipe's learned state can change during
## play (e.g. a curse-mechanic hook unlearning one later, via unlearn_recipe).

signal recipe_learned(recipe_id: String)
signal recipe_unlearned(recipe_id: String)
signal puzzle_attempted(recipe_id: String, success: bool)

var _learned_recipe_ids: Dictionary = {}   # recipe_id -> true


func _ready() -> void:
	for recipe in ContentRegistry.recipes:
		if recipe.known:
			_learned_recipe_ids[recipe.id] = true


func is_learned(recipe_id: String) -> bool:
	return _learned_recipe_ids.has(recipe_id)


func learn_recipe(recipe_id: String) -> void:
	if is_learned(recipe_id):
		return
	_learned_recipe_ids[recipe_id] = true
	recipe_learned.emit(recipe_id)


## No UI trigger yet in the prototype — a hook for later curse/memory-loss
## mechanics (system 11) to unlearn a recipe without needing a shape change.
func unlearn_recipe(recipe_id: String) -> void:
	if not is_learned(recipe_id):
		return
	_learned_recipe_ids.erase(recipe_id)
	recipe_unlearned.emit(recipe_id)


## ingredient_ids is a multiset — one entry per unit the player selected, in
## whatever order the picker UI produced them; only the resulting counts
## matter. Learns the recipe and returns true on success; always emits
## puzzle_attempted so the UI can report a miss. Ingredients are the caller's
## to consume (win or lose) — this only judges the combination.
func attempt_puzzle(recipe: RecipeDef, ingredient_ids: Array[String]) -> bool:
	var success := not ingredient_ids.is_empty() and not check_constraints(recipe, ingredient_ids).has(false)
	puzzle_attempted.emit(recipe.id, success)
	if success:
		learn_recipe(recipe.id)
	return success


## Per-constraint pass/fail for a candidate ingredient selection — used both
## internally by attempt_puzzle() and by AttemptPuzzlePanel to show live
## checkmarks against the pinned-note objectives as the player fills in the
## potion field, before they've committed to an attempt.
func check_constraints(recipe: RecipeDef, ingredient_ids: Array[String]) -> Array[bool]:
	var ingredients: Array[IngredientDef] = []
	for id in ingredient_ids:
		var def := ContentRegistry.get_ingredient(id)
		if def != null:
			ingredients.append(def)

	var results: Array[bool] = []
	for i in recipe.puzzle_constraint_types.size():
		results.append(_check_constraint(recipe, i, ingredients))
	return results


func _check_constraint(recipe: RecipeDef, index: int, ingredients: Array[IngredientDef]) -> bool:
	var target: String = recipe.puzzle_constraint_targets[index]
	var min_value: float = recipe.puzzle_constraint_min[index]
	var max_value: float = recipe.puzzle_constraint_max[index]

	match recipe.puzzle_constraint_types[index]:
		"characteristic_range":
			var total := 0
			for ingredient in ingredients:
				total += ingredient.characteristic_value(target)
			return total >= min_value and total <= max_value
		"total_weight_range":
			var total_weight := 0.0
			for ingredient in ingredients:
				total_weight += ingredient.weight
			return total_weight >= min_value and total_weight <= max_value
		"ingredient_count_range":
			return ingredients.size() >= min_value and ingredients.size() <= max_value
		"role_lightest":
			return _role_is_extreme(IngredientDef.role_from_name(target), ingredients, true)
		"role_heaviest":
			return _role_is_extreme(IngredientDef.role_from_name(target), ingredients, false)
	return false


## Requires `role` to actually be present in the mix (and at least one other
## role alongside it) — "the catalyst must be lightest" fails if there's no
## catalyst, or if the catalyst is the only role used, not vacuously true.
func _role_is_extreme(role: IngredientDef.Role, ingredients: Array[IngredientDef], lightest: bool) -> bool:
	var target_weights: Array[float] = []
	var other_weights: Array[float] = []
	for ingredient in ingredients:
		if ingredient.role == role:
			target_weights.append(ingredient.weight)
		else:
			other_weights.append(ingredient.weight)
	if target_weights.is_empty() or other_weights.is_empty():
		return false

	for target_weight in target_weights:
		for other_weight in other_weights:
			if lightest and target_weight >= other_weight:
				return false
			if not lightest and target_weight <= other_weight:
				return false
	return true


func get_save_data() -> Dictionary:
	var ids: Array[String] = []
	for id in _learned_recipe_ids:
		ids.append(id)
	return {"learned_recipe_ids": ids}


func load_save_data(data: Dictionary) -> void:
	_learned_recipe_ids.clear()
	for id in data.get("learned_recipe_ids", []):
		_learned_recipe_ids[id] = true
