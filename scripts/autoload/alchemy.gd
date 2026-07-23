extends Node
## Tracks which recipes the player has learned, and evaluates the
## ingredient-combination puzzle used to discover new recipes. Autoloaded as
## "Alchemy". See docs/design/systems.md, system 3.
##
## Learned recipes are no longer all pre-authored content: a handful of
## starter RecipeDef .tres files (known: true) seed this at new-game start,
## but most learned recipes are synthesized at runtime by attempt_discovery()
## whenever the player finds an ingredient combination that satisfies a
## PotionDef's puzzle criteria. _learned_recipes is therefore the *only*
## place a discovered RecipeDef instance lives — ContentRegistry never sees
## it, so get_save_data()/load_save_data() serialize full recipe fields
## rather than just an id.

signal recipe_learned(recipe_id: String)
signal recipe_unlearned(recipe_id: String)
signal puzzle_attempted(potion_id: String, success: bool)

var _learned_recipes: Dictionary = {}   # recipe_id -> RecipeDef


func _ready() -> void:
	for recipe in ContentRegistry.recipes:
		if recipe.known:
			_register(recipe)


func is_learned(recipe_id: String) -> bool:
	return _learned_recipes.has(recipe_id)


func get_learned_recipe(recipe_id: String) -> RecipeDef:
	return _learned_recipes.get(recipe_id)


func get_learned_recipes() -> Array[RecipeDef]:
	var result: Array[RecipeDef] = []
	for recipe in _learned_recipes.values():
		result.append(recipe)
	return result


func _register(recipe: RecipeDef) -> void:
	_learned_recipes[recipe.id] = recipe


## No UI trigger yet in the prototype — a hook for later curse/memory-loss
## mechanics (system 11) to unlearn a recipe without needing a shape change.
func unlearn_recipe(recipe_id: String) -> void:
	if not is_learned(recipe_id):
		return
	_learned_recipes.erase(recipe_id)
	recipe_unlearned.emit(recipe_id)


## ingredient_ids is a multiset — one entry per unit the player selected, in
## whatever order the picker UI produced them; only the resulting counts
## matter. Checks the selection against potion's puzzle criteria; on success,
## synthesizes (or reuses, if this exact combination was already found) a new
## learned RecipeDef for it. Ingredients are the caller's to consume (win or
## lose) — this only judges the combination and, on success, remembers it.
## Returns {"success": bool, "recipe": RecipeDef, "already_known": bool}.
func attempt_discovery(potion: PotionDef, ingredient_ids: Array[String]) -> Dictionary:
	var success := not ingredient_ids.is_empty() and not check_constraints(potion, ingredient_ids).has(false)
	puzzle_attempted.emit(potion.id, success)
	if not success:
		return {"success": false, "recipe": null, "already_known": false}

	var counts: Dictionary = {}   # ingredient_id -> count
	for id in ingredient_ids:
		counts[id] = counts.get(id, 0) + 1
	var sorted_ids: Array = counts.keys()
	sorted_ids.sort()

	var recipe_id := _combination_id(potion.id, sorted_ids, counts)
	if is_learned(recipe_id):
		return {"success": true, "recipe": get_learned_recipe(recipe_id), "already_known": true}

	var recipe := RecipeDef.new()
	recipe.id = recipe_id
	recipe.known = false
	recipe.output_potion_id = potion.id
	recipe.display_name = _combination_label(sorted_ids, counts)
	var recipe_ingredient_ids: Array[String] = []
	var recipe_ingredient_quantities: Array[int] = []
	for id in sorted_ids:
		recipe_ingredient_ids.append(id)
		recipe_ingredient_quantities.append(counts[id])
	recipe.ingredient_ids = recipe_ingredient_ids
	recipe.ingredient_quantities = recipe_ingredient_quantities

	_register(recipe)
	recipe_learned.emit(recipe.id)
	return {"success": true, "recipe": recipe, "already_known": false}


func _combination_id(potion_id: String, sorted_ids: Array, counts: Dictionary) -> String:
	var parts: Array[String] = []
	for id in sorted_ids:
		parts.append("%sx%d" % [id, counts[id]])
	return "%s__%s" % [potion_id, "_".join(parts)]


func _combination_label(sorted_ids: Array, counts: Dictionary) -> String:
	var parts: Array[String] = []
	for id in sorted_ids:
		var ingredient := ContentRegistry.get_ingredient(id)
		var ingredient_name: String = ingredient.display_name if ingredient != null else id
		var count: int = counts[id]
		parts.append("%s ×%d" % [ingredient_name, count] if count > 1 else ingredient_name)
	return " + ".join(parts)


## Per-constraint pass/fail for a candidate ingredient selection — used both
## internally by attempt_discovery() and by AttemptPuzzlePanel to show live
## checkmarks against the pinned-note objectives as the player fills in the
## potion field, before they've committed to an attempt.
func check_constraints(potion: PotionDef, ingredient_ids: Array[String]) -> Array[bool]:
	var ingredients: Array[IngredientDef] = []
	for id in ingredient_ids:
		var def := ContentRegistry.get_ingredient(id)
		if def != null:
			ingredients.append(def)

	var results: Array[bool] = []
	for i in potion.puzzle_constraint_types.size():
		results.append(_check_constraint(potion, i, ingredients))
	return results


func _check_constraint(potion: PotionDef, index: int, ingredients: Array[IngredientDef]) -> bool:
	var target: String = potion.puzzle_constraint_targets[index]
	var min_value: float = potion.puzzle_constraint_min[index]
	var max_value: float = potion.puzzle_constraint_max[index]

	match potion.puzzle_constraint_types[index]:
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
	var entries: Array[Dictionary] = []
	for recipe in _learned_recipes.values():
		entries.append({
			"id": recipe.id,
			"display_name": recipe.display_name,
			"known": recipe.known,
			"output_potion_id": recipe.output_potion_id,
			"ingredient_ids": recipe.ingredient_ids,
			"ingredient_quantities": recipe.ingredient_quantities,
		})
	return {"learned_recipes": entries}


func load_save_data(data: Dictionary) -> void:
	_learned_recipes.clear()
	for entry in data.get("learned_recipes", []):
		var recipe := RecipeDef.new()
		recipe.id = entry.get("id", "")
		recipe.display_name = entry.get("display_name", "")
		recipe.known = entry.get("known", false)
		recipe.output_potion_id = entry.get("output_potion_id", "")
		var ingredient_ids: Array[String] = []
		for id in entry.get("ingredient_ids", []):
			ingredient_ids.append(id)
		recipe.ingredient_ids = ingredient_ids
		var ingredient_quantities: Array[int] = []
		for qty in entry.get("ingredient_quantities", []):
			ingredient_quantities.append(int(qty))
		recipe.ingredient_quantities = ingredient_quantities
		_register(recipe)
