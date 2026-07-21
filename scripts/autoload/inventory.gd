extends Node
## Player ingredient stock, brewed potions, and Materials currency.
## Autoloaded as "Inventory". See docs/design/systems.md, systems 2 and 9.

signal ingredient_changed(ingredient_id: String, quantity: int)
signal potion_added(potion_id: String, potency: float, ease_value: float)
signal materials_changed(amount: int)

const MAX_POTIONS := 20

var ingredient_counts: Dictionary = {}   # ingredient_id -> int
var potions: Array[Dictionary] = []      # {potion_id, potency, ease}
var materials: int = 100


func add_ingredient(id: String, quantity: int) -> void:
	ingredient_counts[id] = ingredient_counts.get(id, 0) + quantity
	ingredient_changed.emit(id, ingredient_counts[id])


func ingredient_count(id: String) -> int:
	return ingredient_counts.get(id, 0)


func has_ingredients_for(recipe: RecipeDef) -> bool:
	for i in recipe.ingredient_ids.size():
		if ingredient_count(recipe.ingredient_ids[i]) < recipe.ingredient_quantities[i]:
			return false
	return true


func consume_ingredients_for(recipe: RecipeDef) -> void:
	for i in recipe.ingredient_ids.size():
		var id := recipe.ingredient_ids[i]
		ingredient_counts[id] = ingredient_count(id) - recipe.ingredient_quantities[i]
		ingredient_changed.emit(id, ingredient_counts[id])


## Generic single-item consume (used by seeds, and anything else that isn't
## a full recipe) — returns false without changing anything if insufficient.
func consume_ingredient(id: String, quantity: int) -> bool:
	if ingredient_count(id) < quantity:
		return false
	ingredient_counts[id] = ingredient_count(id) - quantity
	ingredient_changed.emit(id, ingredient_counts[id])
	return true


func add_potion(potion_id: String, potency: float, ease_value: float) -> void:
	potions.append({"potion_id": potion_id, "potency": potency, "ease": ease_value})
	potion_added.emit(potion_id, potency, ease_value)


func has_room_for_potions(count: int) -> bool:
	return potions.size() + count <= MAX_POTIONS


func add_materials(amount: int) -> void:
	materials += amount
	materials_changed.emit(materials)


func spend_materials(amount: int) -> bool:
	if materials < amount:
		return false
	materials -= amount
	materials_changed.emit(materials)
	return true


func get_save_data() -> Dictionary:
	return {
		"ingredient_counts": ingredient_counts.duplicate(),
		"potions": potions.duplicate(true),
		"materials": materials,
	}


func load_save_data(data: Dictionary) -> void:
	ingredient_counts = (data.get("ingredient_counts", {}) as Dictionary).duplicate()
	potions.clear()
	for potion in (data.get("potions", []) as Array):
		potions.append(potion)
	materials = data.get("materials", 0)
