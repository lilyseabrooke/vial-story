extends Node
## Shop stock and ambient open-hours sale simulation. Autoloaded as "Shop".
## See docs/design/systems.md, system 5.

signal potion_stocked(potion_id: String, price: int)
signal potion_sold(potion_id: String, price: int)

const OPEN_MINUTE_OF_DAY := 9 * 60    # 9:00 AM
const CLOSE_MINUTE_OF_DAY := 20 * 60  # 8:00 PM
const ROLL_INTERVAL_MINUTES := 10

# Price is auto-computed from potency/ease until player-set pricing exists.
const POTENCY_PRICE_WEIGHT := 0.6
const EASE_PRICE_WEIGHT := 0.4
const PRICE_PER_POINT := 1.5

# Sale-chance is flat/price-only for now — no reputation stat yet (system 5 open question).
const BASE_SALE_CHANCE := 0.25
const PRICE_SALE_CHANCE_FACTOR := 0.002
const MIN_SALE_CHANCE := 0.05

var capacity: int = 10
var slots: Array[Dictionary] = []   # {potion_id, potency, ease, price}

var _minutes_since_last_roll: int = 0


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)


func is_open() -> bool:
	var minute := Clock.minute_of_day()
	return minute >= OPEN_MINUTE_OF_DAY and minute < CLOSE_MINUTE_OF_DAY


## Dumps potions from Inventory into shop stock, up to capacity. Leftovers
## (if inventory has more than the shop can hold) stay in Inventory.potions.
func stock_all_potions() -> int:
	var stocked_count := 0
	while Inventory.potions.size() > 0 and slots.size() < capacity:
		var potion: Dictionary = Inventory.potions.pop_front()
		var price := _compute_price(potion.potency, potion.ease)
		slots.append({
			"potion_id": potion.potion_id,
			"potency": potion.potency,
			"ease": potion.ease,
			"price": price,
		})
		potion_stocked.emit(potion.potion_id, price)
		stocked_count += 1
	return stocked_count


func _compute_price(potency: float, ease_value: float) -> int:
	return int(round((potency * POTENCY_PRICE_WEIGHT + ease_value * EASE_PRICE_WEIGHT) * PRICE_PER_POINT))


func _on_minute_tick(_timestamp: int) -> void:
	if not is_open():
		_minutes_since_last_roll = 0
		return
	_minutes_since_last_roll += 1
	if _minutes_since_last_roll < ROLL_INTERVAL_MINUTES:
		return
	_minutes_since_last_roll = 0
	_roll_sales()


func _roll_sales() -> void:
	var i := slots.size() - 1
	while i >= 0:
		var slot: Dictionary = slots[i]
		var chance: float = clampf(
			BASE_SALE_CHANCE - slot.price * PRICE_SALE_CHANCE_FACTOR, MIN_SALE_CHANCE, BASE_SALE_CHANCE
		)
		if randf() < chance:
			slots.remove_at(i)
			Inventory.add_materials(slot.price)
			potion_sold.emit(slot.potion_id, slot.price)
		i -= 1


func get_save_data() -> Dictionary:
	return {
		"capacity": capacity,
		"slots": slots.duplicate(true),
	}


## _minutes_since_last_roll is intentionally not saved — it's a tick
## accumulator, not deadline-comparison state, so resetting to 0 is safe.
func load_save_data(data: Dictionary) -> void:
	capacity = data.get("capacity", capacity)
	slots.clear()
	for slot in (data.get("slots", []) as Array):
		slots.append(slot)
	_minutes_since_last_roll = 0
