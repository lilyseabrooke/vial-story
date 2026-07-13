extends Node
## Materials economy: buying ingredients and purchasing upgrades.
## Autoloaded as "Economy". See docs/design/systems.md, system 10.

signal upgrade_purchased(upgrade_id: String)
signal ingredient_bought(ingredient_id: String, quantity: int)

const STATION_ID := "alembic_1"   # only station in the prototype; upgrades target it directly

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
		"station_potency":
			Brewing.get_station(STATION_ID).potency_modifier += upgrade.effect_amount
		"station_ease":
			Brewing.get_station(STATION_ID).ease_modifier += upgrade.effect_amount
		"station_speed":
			Brewing.get_station(STATION_ID).speed_modifier += upgrade.effect_amount
		"grow_plot_count":
			Herbalism.add_plots(int(upgrade.effect_amount))
		_:
			push_warning("Unknown upgrade effect_target: %s" % upgrade.effect_target)
