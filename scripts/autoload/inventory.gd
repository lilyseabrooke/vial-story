extends Node
## Player ingredient stock, brewed potions, and Materials currency.
## Autoloaded as "Inventory". See docs/design/systems.md, systems 2 and 9.

signal ingredient_changed(ingredient_id: String, tier: int, quantity: int)
signal potion_added(potion_id: String, potency: float, ease_value: float)
signal materials_changed(amount: int)
signal scrap_changed
signal pantry_purchased(pantry_id: String)
signal pantry_ingredient_changed(pantry_id: String, ingredient_id: String, tier: int, quantity: int)

const MAX_POTIONS := 20

## ingredient_id -> {IngredientQuality.Tier -> int}. Each tier is tracked as
## its own stack -- same stats as any other tier of the same id, but a
## separate count that Brewing drains highest-quality-first.
var ingredient_counts: Dictionary = {}
var potions: Array[Dictionary] = []      # {potion_id, potency, ease}
var materials: int = 100
var pantries: Array[PantryInstance] = []

## Each unit of Scrap is its own {quality: float} entry rather than a stack
## count like ingredient_counts -- quality varies per piece and is never
## surfaced to the player (see Transmutation, docs/design/systems.md).
var scrap: Array[Dictionary] = []


func add_ingredient(id: String, quantity: int, tier: int = IngredientQuality.Tier.NORMAL) -> void:
	var tiers: Dictionary = ingredient_counts.get(id, {})
	tiers[tier] = tiers.get(tier, 0) + quantity
	ingredient_counts[id] = tiers
	ingredient_changed.emit(id, tier, tiers[tier])


## Total count across every quality tier.
func ingredient_count(id: String) -> int:
	var tiers: Dictionary = ingredient_counts.get(id, {})
	var total := 0
	for count in tiers.values():
		total += count
	return total


func ingredient_count_at(id: String, tier: int) -> int:
	var tiers: Dictionary = ingredient_counts.get(id, {})
	return tiers.get(tier, 0)


## tier -> count for every tier currently in stock (zero-count tiers omitted).
## Used by UI to render one row per (id, tier).
func ingredient_tiers(id: String) -> Dictionary:
	return (ingredient_counts.get(id, {}) as Dictionary).duplicate()


## Drains a nested {tier -> int} dict highest-quality-first, mutating it in
## place. Returns the consumption records actually taken (may total less than
## `quantity` if the stock ran out -- callers are expected to have already
## checked availability via ingredient_count()).
static func _drain_tiers(tiers: Dictionary, quantity: int) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var remaining := quantity
	for tier in [
		IngredientQuality.Tier.PERFECT,
		IngredientQuality.Tier.EXCELLENT,
		IngredientQuality.Tier.GOOD,
		IngredientQuality.Tier.NORMAL,
		IngredientQuality.Tier.POOR,
	]:
		if remaining <= 0:
			break
		var have: int = tiers.get(tier, 0)
		if have <= 0:
			continue
		var take := mini(have, remaining)
		tiers[tier] = have - take
		if tiers[tier] <= 0:
			tiers.erase(tier)
		records.append({"tier": tier, "quantity": take})
		remaining -= take
	return records


func has_ingredients_for(recipe: RecipeDef) -> bool:
	for i in recipe.ingredient_ids.size():
		if ingredient_count(recipe.ingredient_ids[i]) < recipe.ingredient_quantities[i]:
			return false
	return true


## Consumes highest-quality-first for every required ingredient. Returns the
## consumption records ({ingredient_id, tier, quantity}) so callers (e.g.
## Brewing) can compute a quality-weighted bonus without Inventory knowing
## about brew formulas.
func consume_ingredients_for(recipe: RecipeDef) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for i in recipe.ingredient_ids.size():
		var id := recipe.ingredient_ids[i]
		records.append_array(consume_ingredient_records(id, recipe.ingredient_quantities[i]))
	return records


## Generic single-item consume (used by seeds, and anything else that isn't
## a full recipe) — returns false without changing anything if insufficient.
func consume_ingredient(id: String, quantity: int) -> bool:
	if ingredient_count(id) < quantity:
		return false
	consume_ingredient_records(id, quantity)
	return true


## Same as consume_ingredient(), but returns the {ingredient_id, tier,
## quantity} records drained (highest-quality-first) instead of a bool --
## used by Brewing to compute a quality bonus from what was actually
## consumed. Does not check availability; callers should use
## ingredient_count()/consume_ingredient() when that matters.
func consume_ingredient_records(id: String, quantity: int) -> Array[Dictionary]:
	var tiers: Dictionary = ingredient_counts.get(id, {})
	var drained := _drain_tiers(tiers, quantity)
	ingredient_counts[id] = tiers
	var records: Array[Dictionary] = []
	for entry in drained:
		ingredient_changed.emit(id, entry["tier"], tiers.get(entry["tier"], 0))
		records.append({"ingredient_id": id, "tier": entry["tier"], "quantity": entry["quantity"]})
	return records


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


## Total count across every quality tier stored in the pantry.
func pantry_ingredient_count(pantry_id: String, ingredient_id: String) -> int:
	var pantry := get_pantry(pantry_id)
	if pantry == null:
		return 0
	var tiers: Dictionary = pantry.stored_ingredients.get(ingredient_id, {})
	var total := 0
	for count in tiers.values():
		total += count
	return total


func pantry_ingredient_tiers(pantry_id: String, ingredient_id: String) -> Dictionary:
	var pantry := get_pantry(pantry_id)
	if pantry == null:
		return {}
	return (pantry.stored_ingredients.get(ingredient_id, {}) as Dictionary).duplicate()


## Moves stock from the player's carried inventory into the pantry. Fails
## without changing anything if the pantry isn't purchased yet or the player
## doesn't have enough at that tier.
func deposit_to_pantry(pantry_id: String, ingredient_id: String, tier: int, quantity: int) -> bool:
	var pantry := get_pantry(pantry_id)
	if pantry == null or not pantry.purchased or quantity <= 0:
		return false
	if ingredient_count_at(ingredient_id, tier) < quantity:
		return false
	var carried_tiers: Dictionary = ingredient_counts.get(ingredient_id, {})
	carried_tiers[tier] = carried_tiers.get(tier, 0) - quantity
	if carried_tiers[tier] <= 0:
		carried_tiers.erase(tier)
	ingredient_counts[ingredient_id] = carried_tiers
	ingredient_changed.emit(ingredient_id, tier, carried_tiers.get(tier, 0))

	var stored_tiers: Dictionary = pantry.stored_ingredients.get(ingredient_id, {})
	stored_tiers[tier] = stored_tiers.get(tier, 0) + quantity
	pantry.stored_ingredients[ingredient_id] = stored_tiers
	pantry_ingredient_changed.emit(pantry_id, ingredient_id, tier, stored_tiers[tier])
	return true


## Reverse of deposit_to_pantry() -- moves stock back into carried inventory.
func withdraw_from_pantry(pantry_id: String, ingredient_id: String, tier: int, quantity: int) -> bool:
	var pantry := get_pantry(pantry_id)
	if pantry == null or quantity <= 0:
		return false
	var stored_tiers: Dictionary = pantry.stored_ingredients.get(ingredient_id, {})
	var have: int = stored_tiers.get(tier, 0)
	if have < quantity:
		return false
	stored_tiers[tier] = have - quantity
	if stored_tiers[tier] <= 0:
		stored_tiers.erase(tier)
	pantry.stored_ingredients[ingredient_id] = stored_tiers
	pantry_ingredient_changed.emit(pantry_id, ingredient_id, tier, stored_tiers.get(tier, 0))
	add_ingredient(ingredient_id, quantity, tier)
	return true


## Removes stock from a pantry without returning it to the player's carried
## inventory -- used when a brew at a linked Alembic draws directly from
## pantry stock (see Brewing._consume_for_brew()). Drains highest-quality-first,
## same as consume_ingredient(), and returns the consumption records so
## Brewing can factor pantry-drawn quality into its bonus too.
func consume_from_pantry(pantry_id: String, ingredient_id: String, quantity: int) -> Array[Dictionary]:
	var pantry := get_pantry(pantry_id)
	if pantry == null:
		return []
	var stored_tiers: Dictionary = pantry.stored_ingredients.get(ingredient_id, {})
	var drained := _drain_tiers(stored_tiers, quantity)
	pantry.stored_ingredients[ingredient_id] = stored_tiers
	var records: Array[Dictionary] = []
	for entry in drained:
		pantry_ingredient_changed.emit(pantry_id, ingredient_id, entry["tier"], stored_tiers.get(entry["tier"], 0))
		records.append({"ingredient_id": ingredient_id, "tier": entry["tier"], "quantity": entry["quantity"]})
	return records


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
			"stored_ingredients": pantry.stored_ingredients.duplicate(true),
		})
	return {
		"ingredient_counts": ingredient_counts.duplicate(true),
		"potions": potions.duplicate(true),
		"materials": materials,
		"scrap": scrap.duplicate(true),
		"pantries": pantry_data,
	}


## Normalizes a saved ingredient-stack dict into id -> {tier:int -> count:int}.
## Handles two shapes a save can arrive in:
##   - pre-quality saves, where the value was a plain int count (migrated to
##     the Normal tier)
##   - any tiered save round-tripped through JSON (SaveManager stores JSON),
##     where Dictionary keys always come back as String ("0", "1", ...)
##     rather than the int Tier they were saved as
static func _normalize_stacks(raw: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for id in raw:
		var value = raw[id]
		var tiers: Dictionary = {}
		if value is Dictionary:
			for tier_key in (value as Dictionary):
				var count := int((value as Dictionary)[tier_key])
				if count > 0:
					tiers[int(tier_key)] = count
		else:
			var count := int(value)
			if count > 0:
				tiers[IngredientQuality.Tier.NORMAL] = count
		if not tiers.is_empty():
			normalized[id] = tiers
	return normalized


func load_save_data(data: Dictionary) -> void:
	ingredient_counts = _normalize_stacks(data.get("ingredient_counts", {}) as Dictionary)
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
		pantry.stored_ingredients = _normalize_stacks(entry.get("stored_ingredients", {}) as Dictionary)
		pantries.append(pantry)
