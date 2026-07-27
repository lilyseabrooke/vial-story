extends Node
## Shop stock and ambient open-hours sale simulation. Autoloaded as "Shop".
## See docs/design/systems.md, system 5.

signal potion_stocked(potion_id: String, price: int)
signal potion_sold(potion_id: String, price: int)
signal coffers_collected(amount: int)
signal reputation_changed(reputation: int)
signal price_changed(slot_index: int, price: int)
## Fired once per logged visit (see MAX_RECENT_CUSTOMERS below) with the same
## Dictionary that's now sitting at the front of recent_customers — lets the
## Shop tab update its "Recent Customers" list without rebuilding from scratch.
signal customer_visited(record: Dictionary)

const OPEN_MINUTE_OF_DAY := 9 * 60    # 9:00 AM
const CLOSE_MINUTE_OF_DAY := 20 * 60  # 8:00 PM
const ROLL_INTERVAL_MINUTES := 10

# Price is auto-computed from potency/ease until player-set pricing exists.
const POTENCY_PRICE_WEIGHT := 0.6
const EASE_PRICE_WEIGHT := 0.4
const PRICE_PER_POINT := 1.5

# Simulated-customer sale roll — see docs/design/systems.md, system 5.
const MAX_PURCHASES_PER_VISIT := 6
const MIN_CUSTOMER_BUDGET := 20.0
const MAX_CUSTOMER_BUDGET := 220.0
# How far above their flat budget a customer will stretch for a potion whose
# potency/ease they happen to value highly.
const BUDGET_STRETCH_SCALE := 0.8
const BASE_BUY_CHANCE := 0.55
const TRAIT_BUY_BONUS := 0.35
# How strongly deal-savviness reacts to price sitting above/below a slot's
# computed "fair" value (base_price).
const DEAL_SAVVY_SCALE := 0.6
const MIN_BUY_CHANCE := 0.05
const MAX_BUY_CHANCE := 0.95
# Off-tag impulse buys: only a very good potion at a very good discount turns
# a sufficiently deal-savvy customer's head.
const OFF_TAG_TRAIT_THRESHOLD := 0.75
const OFF_TAG_DISCOUNT_THRESHOLD := 0.85  # price must be <= this fraction of base_price
const OFF_TAG_SAVVY_THRESHOLD := 0.5
const OFF_TAG_CHANCE_SCALE := 0.6

# Reputation influence on ambient customer simulation — see docs/design/
# systems.md system 5. Reputation makes a visit more likely each roll
# interval, and stretches the flat budget range customers are drawn from.
const BASE_CUSTOMER_VISIT_CHANCE := 0.5
const REPUTATION_VISIT_CHANCE_SCALE := 0.01
const MIN_CUSTOMER_VISIT_CHANCE := 0.1
const MAX_CUSTOMER_VISIT_CHANCE := 0.95
const REPUTATION_BUDGET_SCALE := 0.01
const MIN_BUDGET_SCALE := 0.1

# Manual pricing (Shop tab) — nudges a stocked slot's price up/down from its
# stocking-time base_price. base_price itself never changes, so deal-savvy
# customers (see _evaluate_purchase_chance()) keep reacting to the markup/
# markdown correctly no matter how many times the player adjusts price.
const PRICE_ADJUST_STEP := 5
const MIN_PRICE := 1

# Simulated-customer flavor data (name/occupation/magic pools) — see
# docs/design/systems.md, system 5, "Recent Customers".
const CUSTOMER_CATALOG_PATH := "res://data/customers.json"
const MAX_RECENT_CUSTOMERS := 20
# A customer who leaves without buying anything is still generated and rolled
# every visit, but only occasionally worth a Shop-tab entry — logging every
# single no-sale visit would flood "Recent Customers" with noise.
const NO_PURCHASE_LOG_CHANCE := 0.2

var capacity: int = 8
var slots: Array[Dictionary] = []   # {potion_id, potency, ease, price, base_price}

## Drives ambient customer simulation — see _visit_chance()/_budget_range()
## below and docs/design/systems.md system 5.
var reputation: int = 0

## Sale proceeds land here instead of Inventory.materials directly — the
## player has to visit the shopfront (STOCK_BOX interactable) to collect.
var coffers: int = 0

## Newest-first log of simulated-customer visits worth showing the player —
## every purchase, plus an occasional no-sale visit (NO_PURCHASE_LOG_CHANCE)
## so the Shop tab's "Recent Customers" list still reads as a living shop
## instead of only ever reporting good news. Capped at MAX_RECENT_CUSTOMERS
## and, like MessageWall's scrollback, not persisted across save/load — it's
## flavor/status color, not save-relevant state.
var recent_customers: Array[Dictionary] = []

var _minutes_since_last_roll: int = 0
var _first_names: Array = []
var _last_names: Array = []
var _occupations: Array = []
var _magic_disciplines: Array = []


func _ready() -> void:
	Clock.minute_tick.connect(_on_minute_tick)
	var catalog_text := FileAccess.get_file_as_string(CUSTOMER_CATALOG_PATH)
	var catalog: Dictionary = JSON.parse_string(catalog_text)
	_first_names = catalog.get("first_names", [])
	_last_names = catalog.get("last_names", [])
	_occupations = catalog.get("occupations", [])
	_magic_disciplines = catalog.get("magic_disciplines", [])


func is_open() -> bool:
	var minute := Clock.minute_of_day()
	return minute >= OPEN_MINUTE_OF_DAY and minute < CLOSE_MINUTE_OF_DAY


## Dumps potions from Inventory into shop stock, up to capacity. Leftovers
## (if inventory has more than the shop can hold) stay in Inventory.potions.
func stock_all_potions() -> int:
	var stocked_count := 0
	while Inventory.potions.size() > 0 and slots.size() < capacity:
		var potion: Dictionary = Inventory.potions.pop_front()
		var potion_def := ContentRegistry.get_potion(potion.potion_id)
		var price := _compute_price(potion.potency, potion.ease, potion_def.value)
		slots.append({
			"potion_id": potion.potion_id,
			"potency": potion.potency,
			"ease": potion.ease,
			"price": price,
			# Immutable "fair value" snapshot from stocking time, independent of
			# whatever the player later marks the price up/down to — deal-savvy
			# customers react to price relative to this, not to the raw price.
			"base_price": price,
		})
		potion_stocked.emit(potion.potion_id, price)
		stocked_count += 1
	return stocked_count


func _compute_price(potency: float, ease_value: float, value: float) -> int:
	return int(round((potency * POTENCY_PRICE_WEIGHT + ease_value * EASE_PRICE_WEIGHT) * PRICE_PER_POINT * value))


## Moves everything sale proceeds have accumulated into Inventory.materials.
## Returns the amount collected.
func collect_coffers() -> int:
	var amount := coffers
	if amount > 0:
		coffers = 0
		Inventory.add_materials(amount)
		coffers_collected.emit(amount)
	return amount


func _on_minute_tick(_timestamp: int) -> void:
	if not is_open():
		_minutes_since_last_roll = 0
		return
	_minutes_since_last_roll += 1
	if _minutes_since_last_roll < ROLL_INTERVAL_MINUTES:
		return
	_minutes_since_last_roll = 0
	_roll_sales()


## Simulates one customer's visit: they walk in wanting a tag, with a budget
## and a preference for potency vs. ease, and leave with up to
## MAX_PURCHASES_PER_VISIT potions. Nothing about the customer is ever shown
## to the player — this just replaces the old flat per-slot sale-chance roll.
## Higher reputation makes a customer more likely to show up at all this
## interval (see _visit_chance()) — a quiet shop can roll no-visit intervals.
func _roll_sales() -> void:
	if slots.is_empty():
		return
	if not Rng.chance(_visit_chance()):
		return
	var customer := _generate_customer()
	var candidates: Array[Dictionary] = []   # {index, chance}
	for i in range(slots.size()):
		var chance := _evaluate_purchase_chance(customer, slots[i])
		if chance > 0.0:
			candidates.append({"index": i, "chance": chance})
	# Best-matching, best-value potions get first crack at the customer's cart.
	candidates.sort_custom(func(a, b): return a.chance > b.chance)

	var to_remove: Array[int] = []
	for entry in candidates:
		if to_remove.size() >= MAX_PURCHASES_PER_VISIT:
			break
		if Rng.chance(entry.chance):
			to_remove.append(entry.index)

	to_remove.sort()
	to_remove.reverse()  # remove_at from the back so earlier indices stay valid
	var purchased: Array[Dictionary] = []   # {potion_id, price}, oldest-removed-index first
	for index in to_remove:
		var slot: Dictionary = slots[index]
		slots.remove_at(index)
		coffers += slot.price
		potion_sold.emit(slot.potion_id, slot.price)
		purchased.append({"potion_id": slot.potion_id, "price": slot.price})

	if not purchased.is_empty() or Rng.chance(NO_PURCHASE_LOG_CHANCE):
		_log_customer_visit(customer, purchased)


## Chance a customer shows up at all this roll interval — rises with
## reputation, clamped so a ruined or sterling reputation still leaves some
## chance either way.
func _visit_chance() -> float:
	return clampf(
		BASE_CUSTOMER_VISIT_CHANCE + reputation * REPUTATION_VISIT_CHANCE_SCALE,
		MIN_CUSTOMER_VISIT_CHANCE,
		MAX_CUSTOMER_VISIT_CHANCE
	)


## Flat-budget range customers are drawn from — reputation stretches both
## ends by the same fraction, so a well-regarded shop draws customers with
## deeper pockets on average, not just more of them.
func _budget_range() -> Vector2:
	var scale: float = maxf(MIN_BUDGET_SCALE, 1.0 + reputation * REPUTATION_BUDGET_SCALE)
	return Vector2(MIN_CUSTOMER_BUDGET * scale, MAX_CUSTOMER_BUDGET * scale)


## first_name/last_name/occupation/magic_discipline/portrait are pure flavor —
## nothing in _evaluate_purchase_chance() reads them, they only ever surface
## in the Shop tab's "Recent Customers" log (see _log_customer_visit()).
func _generate_customer() -> Dictionary:
	var budget_range := _budget_range()
	return {
		"first_name": _random_from(_first_names, "A"),
		"last_name": _random_from(_last_names, "Traveler"),
		"occupation": _random_from(_occupations, "Local"),
		"magic_discipline": _random_from(_magic_disciplines, "Unaligned Magic"),
		# Stubbed for now — no portrait art pipeline for ambient customers yet.
		# CustomerEntry (Shop tab) falls back to a tinted placeholder when null,
		# same convention as CharacterDef.portrait elsewhere.
		"portrait": null,
		"budget": Rng.range_f(budget_range.x, budget_range.y),
		"wanted_tag": _pick_wanted_tag(),
		"potency_weight": Rng.range_f(0.0, 1.0),
		"ease_weight": Rng.range_f(0.0, 1.0),
		"deal_savvy": Rng.range_f(0.0, 1.0),
	}


func _random_from(pool: Array, fallback: String) -> String:
	if pool.is_empty():
		return fallback
	return String(pool[Rng.range_i(0, pool.size() - 1)])


## Builds the Shop-tab-facing record for one visit and pushes it to the front
## of recent_customers. Numeric traits (budget/deal_savvy/potency_weight/
## ease_weight) are only ever exposed as rough qualitative labels here — see
## _rough_budget_label()/_rough_trait_label() — never the raw float, per the
## "estimate, not exact figures" spec in docs/design/systems.md system 5.
func _log_customer_visit(customer: Dictionary, purchased: Array[Dictionary]) -> void:
	var purchase_lines: Array[String] = []
	var total_spent := 0
	for item in purchased:
		var potion_def := ContentRegistry.get_potion(item.potion_id)
		var display_name: String = potion_def.display_name if potion_def else String(item.potion_id).capitalize()
		purchase_lines.append("%s (%d)" % [display_name, item.price])
		total_spent += item.price

	var record := {
		"full_name": "%s %s" % [customer.first_name, customer.last_name],
		"occupation": customer.occupation,
		"magic_discipline": customer.magic_discipline,
		"portrait": customer.portrait,
		"budget_label": _rough_budget_label(customer.budget),
		"deal_savvy_label": _rough_trait_label(customer.deal_savvy),
		"potency_interest_label": _rough_trait_label(customer.potency_weight),
		"ease_interest_label": _rough_trait_label(customer.ease_weight),
		"wanted_tag": customer.wanted_tag,
		"purchase_lines": purchase_lines,
		"total_spent": total_spent,
		"timestamp": Clock.get_timestamp(),
	}
	recent_customers.push_front(record)
	if recent_customers.size() > MAX_RECENT_CUSTOMERS:
		recent_customers.resize(MAX_RECENT_CUSTOMERS)
	customer_visited.emit(record)


## Absolute flavor tiers, deliberately not scaled by the reputation-stretched
## _budget_range() — the point is a stable vocabulary ("tight", "wealthy") the
## player can read trends in over time, not a moving target that always
## centers on "moderate" regardless of how rich the shop's customers get.
func _rough_budget_label(budget: float) -> String:
	if budget < 60.0:
		return "tight budget"
	elif budget < 120.0:
		return "modest budget"
	elif budget < 180.0:
		return "comfortable budget"
	else:
		return "wealthy"


## Shared 0-1 -> low/moderate/high bucketing for deal-savviness and
## potency/ease interest alike — same rough-estimate spirit as
## _rough_budget_label() above.
func _rough_trait_label(value: float) -> String:
	if value < 0.33:
		return "low"
	elif value < 0.66:
		return "moderate"
	else:
		return "high"


func _pick_wanted_tag() -> String:
	var tags: Array[String] = []
	for potion_def in ContentRegistry.potions:
		for tag in potion_def.tags:
			if tag not in tags:
				tags.append(tag)
	if tags.is_empty():
		return ""
	return tags[Rng.range_i(0, tags.size() - 1)]


## 0-1: how well a slot's potency/ease matches what this customer personally
## values, weighted by how much they care about each trait.
func _trait_score(customer: Dictionary, slot: Dictionary) -> float:
	var potion_def := ContentRegistry.get_potion(slot.potion_id)
	var potency_norm := 0.5
	var ease_norm := 0.5
	if potion_def:
		potency_norm = _normalize_stat(slot.potency, potion_def.potency_range)
		ease_norm = _normalize_stat(slot.ease, potion_def.ease_range)
	var weight_sum: float = customer.potency_weight + customer.ease_weight
	if weight_sum <= 0.0:
		return (potency_norm + ease_norm) * 0.5
	return (customer.potency_weight * potency_norm + customer.ease_weight * ease_norm) / weight_sum


func _normalize_stat(value: float, stat_range: Vector2) -> float:
	var span := stat_range.y - stat_range.x
	if span <= 0.0:
		return 0.5
	return clampf((value - stat_range.x) / span, 0.0, 1.0)


## Returns 0.0 if the customer would never buy this slot at all, otherwise a
## purchase chance in [MIN_BUY_CHANCE, MAX_BUY_CHANCE].
func _evaluate_purchase_chance(customer: Dictionary, slot: Dictionary) -> float:
	var potion_def := ContentRegistry.get_potion(slot.potion_id)
	var tag_match: bool = potion_def != null and customer.wanted_tag in potion_def.tags
	var trait_score := _trait_score(customer, slot)
	var base_price: float = slot.get("base_price", slot.price)
	var markup_ratio: float = float(slot.price) / max(base_price, 1.0)
	# Customers stretch their flat budget for potions strong in traits they
	# personally value — bigger stretch the more they value what's on offer.
	var effective_budget: float = customer.budget * (1.0 + trait_score * BUDGET_STRETCH_SCALE)

	if tag_match:
		if slot.price > effective_budget:
			return 0.0
		var chance: float = BASE_BUY_CHANCE + trait_score * TRAIT_BUY_BONUS
		# Deal-savvy customers are drawn to a markdown and wary of a markup;
		# less-savvy customers barely notice either way.
		chance *= 1.0 + customer.deal_savvy * (1.0 - markup_ratio) * DEAL_SAVVY_SCALE
		return clampf(chance, MIN_BUY_CHANCE, MAX_BUY_CHANCE)

	# Off-tag impulse buy: needs to be a genuinely great potion, at a genuine
	# discount, seen by a customer savvy enough to notice the deal.
	if trait_score < OFF_TAG_TRAIT_THRESHOLD:
		return 0.0
	if customer.deal_savvy < OFF_TAG_SAVVY_THRESHOLD:
		return 0.0
	if markup_ratio > OFF_TAG_DISCOUNT_THRESHOLD:
		return 0.0
	if slot.price > effective_budget:
		return 0.0
	var discount_bonus: float = (1.0 - markup_ratio) * customer.deal_savvy
	var chance: float = (trait_score - OFF_TAG_TRAIT_THRESHOLD + discount_bonus) * OFF_TAG_CHANCE_SCALE
	return clampf(chance, 0.0, MAX_BUY_CHANCE)


## Nudges slot `index`'s price by `delta` (positive or negative), floored at
## MIN_PRICE. base_price is untouched — see the const block above.
func adjust_price(index: int, delta: int) -> void:
	if index < 0 or index >= slots.size():
		return
	var slot: Dictionary = slots[index]
	slot.price = maxi(MIN_PRICE, slot.price + delta)
	slots[index] = slot
	price_changed.emit(index, slot.price)


func add_reputation(amount: int) -> void:
	reputation += amount
	reputation_changed.emit(reputation)


func get_save_data() -> Dictionary:
	return {
		"capacity": capacity,
		"slots": slots.duplicate(true),
		"reputation": reputation,
		"coffers": coffers,
	}


## _minutes_since_last_roll is intentionally not saved — it's a tick
## accumulator, not deadline-comparison state, so resetting to 0 is safe.
func load_save_data(data: Dictionary) -> void:
	capacity = data.get("capacity", capacity)
	slots.clear()
	for slot in (data.get("slots", []) as Array):
		var s: Dictionary = slot
		# Older saves predate base_price — treat their stored price as the
		# fair value (no markup/markdown had ever been possible yet).
		if not s.has("base_price"):
			s["base_price"] = s.get("price", 0)
		slots.append(s)
	reputation = data.get("reputation", 0)
	coffers = data.get("coffers", 0)
	_minutes_since_last_roll = 0
