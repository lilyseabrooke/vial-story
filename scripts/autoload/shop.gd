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
## Fired the instant a visit is rolled into existence (see _roll_sales()) —
## CustomerDirector listens to spawn a visible CustomerInteractable if (and
## only if) the Shop room happens to be active; the visit itself is already
## live in active_visits regardless of whether anyone's watching.
signal customer_visit_started(visit: Dictionary)
## Fired when a visit's resolve_timestamp is reached (see _on_minute_tick())
## and its purchases have actually been resolved against live shop state —
## CustomerDirector uses this to know when to animate a visible customer's
## decision/departure; purely a presentation hook, the resolution itself
## already happened by the time this fires.
signal customer_visit_resolved(visit: Dictionary, purchased: Array)
## Fired every time a persuasion roll happens against a customer — either the
## player's (via CustomerInteractable.interact() -> attempt_persuasion(),
## source "player") or Garnet's own ambient one (source "garnet", see
## _maybe_attempt_garnet_persuasion()). `result` is a Rng.roll_2d10()
## Dictionary. GameHud uses this to show the player's own rolls via
## RollDisplay and log Garnet's as flavor text.
signal persuasion_attempted(visit: Dictionary, result: Dictionary, source: String)

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
# Lowered from an old (0.55, 0.35, ..., 0.95) spread that let a great tag
# match/trait score sit right at "basically guaranteed" -- a customer wanting
# something on offer should still be a real roll, not a formality, and
# leaves room below MAX_BUY_CHANCE for persuasion_sway (see below) to matter
# either direction.
const BASE_BUY_CHANCE := 0.32
const TRAIT_BUY_BONUS := 0.28
# How strongly deal-savviness reacts to price sitting above/below a slot's
# computed "fair" value (base_price).
const DEAL_SAVVY_SCALE := 0.6
const MIN_BUY_CHANCE := 0.05
const MAX_BUY_CHANCE := 0.75
# Off-tag impulse buys: only a very good potion at a very good discount turns
# a sufficiently deal-savvy customer's head.
const OFF_TAG_TRAIT_THRESHOLD := 0.75
const OFF_TAG_DISCOUNT_THRESHOLD := 0.85  # price must be <= this fraction of base_price
const OFF_TAG_SAVVY_THRESHOLD := 0.5
const OFF_TAG_CHANCE_SCALE := 0.6

# Persuasion -- see attempt_persuasion()/_maybe_attempt_garnet_persuasion()
# and docs/design/systems.md system 5. difficulty is generated per customer
# as a Rng.roll_2d10() DC, the same DC scale (2d10, midpoint 11) every other
# system in this game rolls against (Academy.CLASS_PERFORMANCE_DC,
# Brewing.DICE_DC, etc.) -- a spread around that midpoint rather than a fixed
# 11 for every customer is what makes some customers a harder sell than
# others.
const MIN_DIFFICULTY_DC := 7.0
const MAX_DIFFICULTY_DC := 15.0
# Each degree of success/failure (Rng.roll_2d10()'s degrees_of_success/
# degrees_of_failure) nudges a customer's persuasion_sway by this much,
# additively folded into _evaluate_purchase_chance() (see
# _buy_rate_multiplier() call sites) -- capped at
# MIN_/MAX_PERSUASION_SWAY so repeated attempts (the player once, Garnet
# potentially several times over a long browse) can't push a customer to a
# guaranteed sale or a guaranteed walkout.
const PERSUASION_SWAY_PER_DEGREE := 0.08
const MIN_PERSUASION_SWAY := -0.3
const MAX_PERSUASION_SWAY := 0.3
# A strong persuasion outcome (multiple degrees of success/failure) is
# noteworthy enough to nudge the shop's standing a little either way, not
# just this one customer's odds.
const REPUTATION_PER_PERSUASION_DEGREE := 1
# Garnet's own persuasion competence -- a flat modifier (same role
# Academy._roll_class_reward() gives Skills.level("focus")) until a real
# Garnet ability/upgrade system exists (see docs/design/systems.md system 5).
const GARNET_INSIGHT_MODIFIER := 2.0
# Rolled once per minute tick while the shop's open and at least one visit is
# active -- keeps Garnet's ambient attempts occasional background flavor
# rather than a roll spamming every single minute.
const GARNET_PERSUASION_CHANCE_PER_MINUTE := 0.15

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

# How long (in Clock minutes) a visit browses before Garnet resolves it — see
# active_visits below and docs/design/systems.md system 5. Deliberately a
# real Clock-time window (not an instant roll) so a visible CustomerInteractable
# has time to walk in and idle, and so a price change or restock mid-browse can
# genuinely change the outcome (see try_purchase()).
const BROWSE_DURATION_MIN_MINUTES := 15
const BROWSE_DURATION_MAX_MINUTES := 30

var capacity: int = 8
var slots: Array[Dictionary] = []   # {potion_id, potency, ease, price, base_price}

## Drives ambient customer simulation — see _visit_chance()/_budget_range()
## below and docs/design/systems.md system 5.
var reputation: int = 0

## Additive percentage applied to every purchase-chance roll (see
## _buy_rate_multiplier()) — e.g. -20 means a customer's final buy chance is
## scaled to 80% of what it'd otherwise be. Curse penalties are the only
## thing that mutates this today (Curse._apply_penalty()); nothing decays it
## back on its own — a curse's own dispel path calls add_buy_rate_modifier()
## again with the negated amount.
var buy_rate_modifier: float = 0.0

## Sale proceeds land here instead of Inventory.materials directly — the
## player has to visit the shopfront (STOCK_BOX interactable) to collect.
var coffers: int = 0

## Newest-first log of simulated-customer visits worth showing the player —
## every purchase, plus an occasional no-sale visit (NO_PURCHASE_LOG_CHANCE)
## so the Shop tab's "Recent Customers" list still reads as a living shop
## instead of only ever reporting good news. Capped at MAX_RECENT_CUSTOMERS
## and, like the old MessageWall scrollback, not persisted across save/load —
## it's flavor/status color, not save-relevant state.
var recent_customers: Array[Dictionary] = []

## Live, in-progress visits — see _roll_sales()/_on_minute_tick() and
## docs/design/systems.md system 5. Each entry: {visit_id, customer,
## start_timestamp, resolve_timestamp}. Same "ephemeral, not save-relevant"
## treatment as recent_customers — not persisted, resets empty on load, same
## as a save simply not preserving mid-flight ambient flavor state.
var active_visits: Array[Dictionary] = []

var _next_visit_id: int = 0
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


func _on_minute_tick(timestamp: int) -> void:
	_resolve_due_visits(timestamp)

	if not is_open():
		_minutes_since_last_roll = 0
		return

	_maybe_attempt_garnet_persuasion()

	_minutes_since_last_roll += 1
	if _minutes_since_last_roll < ROLL_INTERVAL_MINUTES:
		return
	_minutes_since_last_roll = 0
	_roll_sales()


## Rolls whether a customer shows up at all this interval (see _visit_chance()
## — higher reputation makes a visit more likely) and, if so, generates one
## and starts a live visit job in active_visits rather than resolving it on
## the spot. The actual purchase decision happens later, in
## _resolve_due_visits(), against whatever the shop's stock/prices look like
## at that moment — see docs/design/systems.md system 5.
func _roll_sales() -> void:
	if slots.is_empty():
		return
	if not Rng.chance(_visit_chance()):
		return
	var customer := _generate_customer()
	var now := Clock.get_timestamp()
	var visit := {
		"visit_id": _next_visit_id,
		"customer": customer,
		"start_timestamp": now,
		"resolve_timestamp": now + Rng.range_i(BROWSE_DURATION_MIN_MINUTES, BROWSE_DURATION_MAX_MINUTES),
	}
	_next_visit_id += 1
	active_visits.append(visit)
	customer_visit_started.emit(visit)


## Resolves every active_visits entry whose browse window has elapsed —
## called every minute tick unconditionally (including inside
## Clock.skip_to()'s per-minute loop), so a visit that both starts and
## resolves during e.g. a sleep skip still resolves correctly with no visual
## and no stall.
func _resolve_due_visits(timestamp: int) -> void:
	if active_visits.is_empty():
		return
	var still_active: Array[Dictionary] = []
	for visit in active_visits:
		if timestamp < int(visit.resolve_timestamp):
			still_active.append(visit)
			continue
		var purchased := _resolve_visit(visit.customer)
		customer_visit_resolved.emit(visit, purchased)
		if not purchased.is_empty() or Rng.chance(NO_PURCHASE_LOG_CHANCE):
			log_visit(visit.customer, purchased)
	active_visits = still_active


## Player-initiated persuasion attempt against the visit identified by
## visit_id -- see CustomerInteractable.interact(). One attempt per visit
## (persuaded_by_player); returns {} if the visit no longer exists (already
## resolved, or the customer already left) or was already attempted this
## visit. Uses Skills.level("insight") as the roll modifier, the same "raw
## skill level as modifier" shape Academy._roll_class_reward() gives Focus.
func attempt_persuasion(visit_id: int) -> Dictionary:
	for visit in active_visits:
		if visit.visit_id != visit_id:
			continue
		var customer: Dictionary = visit.customer
		if customer.get("persuaded_by_player", false):
			return {}
		var result := _apply_persuasion(visit, float(Skills.level("insight")), "player")
		customer.persuaded_by_player = true
		return result
	return {}


## Garnet's own ambient persuasion attempt -- background flavor, not player-
## initiated, rolled at most once per open minute (GARNET_PERSUASION_CHANCE_
## PER_MINUTE) against a random still-browsing visit. Independent of
## persuaded_by_player: Garnet can work a customer the player already tried,
## and can attempt the same customer more than once across a long enough
## browse window -- she's the one actually running the counter the whole
## time, not a one-shot like the player's single interact().
func _maybe_attempt_garnet_persuasion() -> void:
	if active_visits.is_empty():
		return
	if not Rng.chance(GARNET_PERSUASION_CHANCE_PER_MINUTE):
		return
	var visit: Dictionary = active_visits[Rng.range_i(0, active_visits.size() - 1)]
	_apply_persuasion(visit, GARNET_INSIGHT_MODIFIER, "garnet")


## Shared roll-and-apply logic behind attempt_persuasion() (player) and
## _maybe_attempt_garnet_persuasion() (Garnet): rolls modifier against the
## customer's own difficulty DC, nudges persuasion_sway by
## PERSUASION_SWAY_PER_DEGREE per degree of success/failure (clamped to
## [MIN_/MAX_PERSUASION_SWAY]), nudges reputation the same way scaled by
## REPUTATION_PER_PERSUASION_DEGREE, and emits persuasion_attempted. Mutating
## `customer` (a reference into `visit`, itself a reference into
## active_visits) here is enough to update the real stored visit -- Godot
## Dictionaries are reference types, so no reassignment back into
## active_visits is needed, same as try_purchase()'s slot mutation above.
func _apply_persuasion(visit: Dictionary, modifier: float, source: String) -> Dictionary:
	var customer: Dictionary = visit.customer
	var result := Rng.roll_2d10(modifier, customer.difficulty)
	var degrees: int = result.degrees_of_success - result.degrees_of_failure
	customer.persuasion_sway = clampf(
		customer.get("persuasion_sway", 0.0) + degrees * PERSUASION_SWAY_PER_DEGREE,
		MIN_PERSUASION_SWAY,
		MAX_PERSUASION_SWAY
	)
	var reputation_delta := degrees * REPUTATION_PER_PERSUASION_DEGREE
	if reputation_delta != 0:
		add_reputation(reputation_delta)
	persuasion_attempted.emit(visit, result, source)
	return result


## Attempts a purchase against every candidate slot (best-matching first,
## capped at MAX_PURCHASES_PER_VISIT), using try_purchase() so each roll sees
## live shop state at resolution time. Candidate indices are captured once,
## up front, against the pre-removal slots array (same as the old inline
## _roll_sales() loop) — every remaining candidate's index is shifted down by
## one whenever an earlier-indexed slot is actually removed, so later rolls
## still hit the right slot.
func _resolve_visit(customer: Dictionary) -> Array[Dictionary]:
	var purchased: Array[Dictionary] = []
	var candidates := get_purchase_candidates(customer)
	for entry in candidates:
		if purchased.size() >= MAX_PURCHASES_PER_VISIT:
			break
		var index: int = entry.index
		var result := try_purchase(customer, index)
		if result.get("success", false):
			purchased.append({"potion_id": result.potion_id, "price": result.price})
			for other in candidates:
				if other.index > index:
					other.index -= 1
	return purchased


## Scores every currently-stocked slot against `customer`, returning
## {index, chance} entries (chance > 0 only), best-matching/best-value first.
## Pulled out of the old inline _roll_sales() loop so both the live
## resolution path and any future caller can reuse the same scoring pass.
func get_purchase_candidates(customer: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []   # {index, chance}
	for i in range(slots.size()):
		var chance := _evaluate_purchase_chance(customer, slots[i])
		if chance > 0.0:
			candidates.append({"index": i, "chance": chance})
	candidates.sort_custom(func(a, b): return a.chance > b.chance)
	return candidates


## Re-scores slot `slot_index` against *current* slots state (not a cached
## snapshot from when the visit started) and rolls it. Returns
## {"success": bool, "potion_id": String, "price": int} — potion_id/price are
## only meaningful when success is true. On success, removes the slot, adds
## its price to coffers, and emits potion_sold, same side effects the old
## inline _roll_sales() loop had.
func try_purchase(customer: Dictionary, slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= slots.size():
		return {"success": false}
	var slot: Dictionary = slots[slot_index]
	var chance := _evaluate_purchase_chance(customer, slot)
	if chance <= 0.0 or not Rng.chance(chance):
		return {"success": false}
	slots.remove_at(slot_index)
	coffers += slot.price
	potion_sold.emit(slot.potion_id, slot.price)
	return {"success": true, "potion_id": slot.potion_id, "price": slot.price}


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
## in the Shop tab's "Recent Customers" log (see log_visit()).
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
		# How hard this customer is to sell to -- a Rng.roll_2d10() DC (see
		# attempt_persuasion()), independent of deal_savvy (which is about
		# price sensitivity, not persuadability).
		"difficulty": Rng.range_f(MIN_DIFFICULTY_DC, MAX_DIFFICULTY_DC),
		# Accumulates from persuasion attempts across the visit (player and/or
		# Garnet) -- see attempt_persuasion(). Additive into
		# _evaluate_purchase_chance(), clamped to [MIN_/MAX_PERSUASION_SWAY].
		"persuasion_sway": 0.0,
		# The player gets one persuasion attempt per visit -- see
		# attempt_persuasion(). Garnet's ambient attempts aren't limited by
		# this flag.
		"persuaded_by_player": false,
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
func log_visit(customer: Dictionary, purchased: Array[Dictionary]) -> void:
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
		chance *= _buy_rate_multiplier("shop_sales")
		chance += customer.get("persuasion_sway", 0.0)
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
	chance *= _buy_rate_multiplier("customer_retention")
	chance += customer.get("persuasion_sway", 0.0)
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
	ShopEvents.emit_event("price_changed", {"slot_index": index, "price": slot.price})


func add_reputation(amount: int) -> void:
	reputation += amount
	reputation_changed.emit(reputation)
	ShopEvents.emit_event("reputation_changed", {"reputation": reputation})


func add_buy_rate_modifier(amount: float) -> void:
	buy_rate_modifier += amount


## Floored at 0 so a stack of curse penalties can zero out purchases entirely
## but never flip the multiplier negative into a nonsensical chance.
## skill_bonus_target selects which of Insight's two stubbed effect targets
## (data/skills/insight.tres: "shop_sales" for tag-matched purchases,
## "customer_retention" for off-tag impulse buys) represents Garnet's own
## handling of that particular kind of sale — see docs/design/systems.md
## system 5/6.
func _buy_rate_multiplier(skill_bonus_target: String) -> float:
	return maxf(0.0, 1.0 + (buy_rate_modifier + Skills.get_bonus(skill_bonus_target)) / 100.0)


func get_save_data() -> Dictionary:
	return {
		"capacity": capacity,
		"slots": slots.duplicate(true),
		"reputation": reputation,
		"buy_rate_modifier": buy_rate_modifier,
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
	buy_rate_modifier = data.get("buy_rate_modifier", 0.0)
	coffers = data.get("coffers", 0)
	_minutes_since_last_roll = 0
