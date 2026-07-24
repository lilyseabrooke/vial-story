extends Node
## Player ingredient stock, brewed potions, and Materials currency.
## Autoloaded as "Inventory". See docs/design/systems.md, systems 2 and 9.

signal ingredient_changed(ingredient_id: String, quantity: int)
signal potion_added(potion_id: String, potency: float, ease_value: float)
signal materials_changed(amount: int)
signal scrap_changed
signal pantry_purchased(pantry_id: String)
signal pantry_ingredient_changed(pantry_id: String, ingredient_id: String, quantity: int)

const MAX_POTIONS := 20

var ingredient_counts: Dictionary = {}   # ingredient_id -> int
var potions: Array[Dictionary] = []      # {potion_id, potency, ease}
var materials: int = 100
var pantries: Array[PantryInstance] = []

## Each unit of Scrap is its own {quality: float} entry rather than a stack
## count like ingredient_counts -- quality varies per piece and is never
## surfaced to the player (see Transmutation, docs/design/systems.md).
var scrap: Array[Dictionary] = []


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


func add_scrap(quality: float) -> void:
	scrap.append({"quality": quality})
	scrap_changed.emit()


func scrap_count() -> int:
	return scrap.size()


## FIFO -- oldest piece first. Since quality is hidden from the player, there's
## no meaningful ordering choice to expose here. Returns {} (no-op) if there's
## no Scrap to take.
func take_scrap() -> Dictionary:
	if scrap.is_empty():
		return {}
	var taken: Dictionary = scrap.pop_front()
	scrap_changed.emit()
	return taken


func get_pantry(pantry_id: String) -> PantryInstance:
	for pantry in pantries:
		if pantry.id == pantry_id:
			return pantry
	return null


## Idempotent -- called by RoomBuilder as each hand-placed PantryInteractable is
## wired, mirroring Brewing.register_station(). If `id` is already registered
## (e.g. a save was already loaded before rooms wired), its *live* state
## (purchased/stored_ingredients) is left untouched, but the scene-derived
## fields below are always refreshed to match the current wiring -- see
## Brewing.register_station()'s docstring for why (a station/pantry saved
## before a field existed must not keep it empty forever).
func register_pantry(id: String, display_name: String, cost: int, lab_manager_id: String) -> PantryInstance:
	var existing := get_pantry(id)
	if existing != null:
		existing.display_name = display_name
		existing.cost = cost
		existing.lab_manager_id = lab_manager_id
		return existing
	var pantry := PantryInstance.new()
	pantry.id = id
	pantry.display_name = display_name
	pantry.cost = cost
	pantry.purchased = cost <= 0
	pantry.lab_manager_id = lab_manager_id
	pantries.append(pantry)
	return pantry


## Returns "" on success, or a short reason string on failure -- same
## convention as Brewing.purchase_station().
func purchase_pantry(pantry_id: String) -> String:
	var pantry := get_pantry(pantry_id)
	if pantry == null:
		return "No such pantry."
	if pantry.purchased:
		return "Already purchased."
	if not spend_materials(pantry.cost):
		return "Not enough Materials."
	pantry.purchased = true
	pantry_purchased.emit(pantry_id)
	return ""


func pantry_ingredient_count(pantry_id: String, ingredient_id: String) -> int:
	var pantry := get_pantry(pantry_id)
	return pantry.stored_ingredients.get(ingredient_id, 0) if pantry != null else 0


## Moves stock from the player's carried inventory into the pantry. Fails
## without changing anything if the pantry isn't purchased yet or the player
## doesn't have enough.
func deposit_to_pantry(pantry_id: String, ingredient_id: String, quantity: int) -> bool:
	var pantry := get_pantry(pantry_id)
	if pantry == null or not pantry.purchased or quantity <= 0:
		return false
	if ingredient_count(ingredient_id) < quantity:
		return false
	ingredient_counts[ingredient_id] = ingredient_count(ingredient_id) - quantity
	ingredient_changed.emit(ingredient_id, ingredient_counts[ingredient_id])
	pantry.stored_ingredients[ingredient_id] = pantry.stored_ingredients.get(ingredient_id, 0) + quantity
	pantry_ingredient_changed.emit(pantry_id, ingredient_id, pantry.stored_ingredients[ingredient_id])
	return true


## Reverse of deposit_to_pantry() -- moves stock back into carried inventory.
func withdraw_from_pantry(pantry_id: String, ingredient_id: String, quantity: int) -> bool:
	var pantry := get_pantry(pantry_id)
	if pantry == null or quantity <= 0:
		return false
	var have: int = pantry.stored_ingredients.get(ingredient_id, 0)
	if have < quantity:
		return false
	pantry.stored_ingredients[ingredient_id] = have - quantity
	pantry_ingredient_changed.emit(pantry_id, ingredient_id, pantry.stored_ingredients[ingredient_id])
	add_ingredient(ingredient_id, quantity)
	return true


## Removes stock from a pantry without returning it to the player's carried
## inventory -- used when a brew at a linked Alembic draws directly from
## pantry stock (see Brewing._consume_for_brew()).
func consume_from_pantry(pantry_id: String, ingredient_id: String, quantity: int) -> void:
	var pantry := get_pantry(pantry_id)
	if pantry == null:
		return
	var have: int = pantry.stored_ingredients.get(ingredient_id, 0)
	pantry.stored_ingredients[ingredient_id] = maxi(0, have - quantity)
	pantry_ingredient_changed.emit(pantry_id, ingredient_id, pantry.stored_ingredients[ingredient_id])


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
	var pantry_data: Array[Dictionary] = []
	for pantry in pantries:
		pantry_data.append({
			"id": pantry.id,
			"display_name": pantry.display_name,
			"cost": pantry.cost,
			"purchased": pantry.purchased,
			"lab_manager_id": pantry.lab_manager_id,
			"stored_ingredients": pantry.stored_ingredients.duplicate(),
		})
	return {
		"ingredient_counts": ingredient_counts.duplicate(),
		"potions": potions.duplicate(true),
		"materials": materials,
		"scrap": scrap.duplicate(true),
		"pantries": pantry_data,
	}


func load_save_data(data: Dictionary) -> void:
	ingredient_counts = (data.get("ingredient_counts", {}) as Dictionary).duplicate()
	potions.clear()
	for potion in (data.get("potions", []) as Array):
		potions.append(potion)
	materials = data.get("materials", 0)
	scrap.clear()
	for piece in (data.get("scrap", []) as Array):
		scrap.append(piece)

	pantries.clear()
	for entry in (data.get("pantries", []) as Array):
		var pantry := PantryInstance.new()
		pantry.id = entry.get("id", "")
		pantry.display_name = entry.get("display_name", "")
		pantry.cost = entry.get("cost", 0)
		pantry.purchased = entry.get("purchased", true)
		pantry.lab_manager_id = entry.get("lab_manager_id", "")
		pantry.stored_ingredients = (entry.get("stored_ingredients", {}) as Dictionary).duplicate()
		pantries.append(pantry)
