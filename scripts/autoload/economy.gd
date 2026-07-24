extends Node
## Materials economy: buying ingredients and purchasing upgrades.
## Autoloaded as "Economy". See docs/design/systems.md, system 10.

signal upgrade_purchased(upgrade_id: String)
signal ingredient_bought(ingredient_id: String, quantity: int)

var purchased_upgrade_ids: Array[String] = []


func is_purchased(upgrade_id: String) -> bool:
	return upgrade_id in purchased_upgrade_ids


## Returns "" on success, or a short reason string on failure.
func buy_ingredient(ingredient: IngredientDef, quantity: int = 1) -> String:
	var total_cost := ingredient.buy_price * quantity
	if not Inventory.spend_materials(total_cost):
		return "Not enough Materials."
	Inventory.add_ingredient(ingredient.id, quantity)
	ingredient_bought.emit(ingredient.id, quantity)
	return ""


## Returns "" on success, or a short reason string on failure. Seeds share
## Inventory's ingredient_counts store (distinct ids), so this mirrors
## buy_ingredient rather than needing a separate inventory.
func buy_seed(seed_def: SeedDef, quantity: int = 1) -> String:
	var total_cost := seed_def.buy_price * quantity
	if not Inventory.spend_materials(total_cost):
		return "Not enough Materials."
	Inventory.add_ingredient(seed_def.id, quantity)
	ingredient_bought.emit(seed_def.id, quantity)
	return ""


## Returns "" on success, or a short reason string on failure.
func purchase_upgrade(upgrade: UpgradeDef) -> String:
	if is_purchased(upgrade.id):
		return "Already purchased."
	if not Inventory.spend_materials(upgrade.cost):
		return "Not enough Materials."
	purchased_upgrade_ids.append(upgrade.id)
	_apply_effect(upgrade)
	upgrade_purchased.emit(upgrade.id)
	return ""


func _apply_effect(upgrade: UpgradeDef) -> void:
	match upgrade.effect_target:
		"shop_capacity":
			Shop.capacity += int(upgrade.effect_amount)
		_:
			push_warning("Unknown upgrade effect_target: %s" % upgrade.effect_target)


func get_save_data() -> Dictionary:
	return {"purchased_upgrade_ids": purchased_upgrade_ids.duplicate()}


## IMPORTANT: does NOT replay purchased_upgrade_ids through _apply_effect().
## Upgrade effects are already baked into Brewing's station modifiers, Shop's
## capacity, and Herbalism's plot array — all restored directly by their own
## load_save_data(). Replaying effects here would double-apply every
## modifier/capacity/plot on top of those already-restored values.
## purchased_upgrade_ids exists on load purely so is_purchased() gates
## "already bought" UI correctly.
func load_save_data(data: Dictionary) -> void:
	var saved: Array = data.get("purchased_upgrade_ids", [])
	purchased_upgrade_ids.assign(saved)
