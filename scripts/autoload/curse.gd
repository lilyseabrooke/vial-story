extends Node
## Tracks hand-placed Curse instances active in the shop and evaluates the
## ingredient-combination check used to dispel them. Autoloaded as "Curse".
## See docs/design/systems.md, system 11.
##
## A curse instance is identified by the interactable's own target_id (unique
## per hand-placed CurseInteractable node), not by the CurseDef id it happens
## to be running — the same CurseDef could in principle be placed more than
## once. activate() picks a CurseDef at random from the catalog if the
## interactable didn't pin a specific curse_id, excluding any CurseDef id
## already active elsewhere so every simultaneously-active curse is distinct.

signal curse_activated(instance_id: String, curse_id: String)
signal curse_dispelled(instance_id: String, curse_id: String)
signal dispel_attempted(instance_id: String, success: bool)

const MAX_DISPEL_INGREDIENTS := 3

var _active: Dictionary = {}   # instance_id -> curse_id


## No-op if this instance is already active (re-entering a placed curse's
## _ready() shouldn't re-roll or re-apply its penalties). Returns the curse_id
## that ended up active, or "" if none could be resolved (empty catalog, or
## an unknown pinned curse_id).
func activate(instance_id: String, curse_id: String = "") -> String:
	if _active.has(instance_id):
		return _active[instance_id]

	var resolved_id := curse_id
	if resolved_id.is_empty():
		resolved_id = _pick_random_curse_id()
	if resolved_id.is_empty():
		return ""

	var curse := ContentRegistry.get_curse(resolved_id)
	if curse == null:
		push_warning("Unknown curse id: %s" % resolved_id)
		return ""

	_active[instance_id] = resolved_id
	for penalty in curse.penalties:
		_apply_penalty(penalty.target, penalty.amount)
	curse_activated.emit(instance_id, resolved_id)
	return resolved_id


func is_active(instance_id: String) -> bool:
	return _active.has(instance_id)


func get_active_curse(instance_id: String) -> CurseDef:
	var curse_id: String = _active.get(instance_id, "")
	return ContentRegistry.get_curse(curse_id) if curse_id != "" else null


## Read-only check CursePanel calls after every slot change to decide whether
## to show its Dispel button — unlike Alchemy's recipe-discovery puzzle, a
## curse dispel never "fails" from the player's perspective: the UI only ever
## lets them commit a combination once this already returns true, so
## attempt_dispel() below should always succeed in practice.
func meets_requirements(instance_id: String, ingredient_ids: Array[String]) -> bool:
	var curse := get_active_curse(instance_id)
	if curse == null or ingredient_ids.is_empty() or ingredient_ids.size() > MAX_DISPEL_INGREDIENTS:
		return false

	var ingredients: Array[IngredientDef] = []
	for id in ingredient_ids:
		var def := ContentRegistry.get_ingredient(id)
		if def == null or not _is_permitted(curse, def):
			return false
		ingredients.append(def)

	return _check_bands(curse, ingredients)


## Ingredients are the caller's to consume — CursePanel only calls this once
## meets_requirements() already returned true for the same ids, so this
## returning false would indicate a caller bug, not a legitimate "wrong
## guess" (there's no consume-on-failure path here, unlike
## Alchemy.attempt_discovery()).
func attempt_dispel(instance_id: String, ingredient_ids: Array[String]) -> bool:
	var success := meets_requirements(instance_id, ingredient_ids)
	dispel_attempted.emit(instance_id, success)
	if success:
		_dispel(instance_id, get_active_curse(instance_id))
	return success


func _is_permitted(curse: CurseDef, ingredient: IngredientDef) -> bool:
	if curse.permitted_ingredients.is_empty():
		return true
	var category_name: String = IngredientDef.Category.keys()[ingredient.category].to_lower()
	return category_name in curse.permitted_ingredients


func _check_bands(curse: CurseDef, ingredients: Array[IngredientDef]) -> bool:
	for pair in curse.minima:
		var total := 0
		for ingredient in ingredients:
			total += ingredient.characteristic_value(pair[0])
		if total < pair[1]:
			return false
	for pair in curse.maxima:
		var total := 0
		for ingredient in ingredients:
			total += ingredient.characteristic_value(pair[0])
		if total > pair[1]:
			return false
	return true


func _dispel(instance_id: String, curse: CurseDef) -> void:
	for penalty in curse.penalties:
		_apply_penalty(penalty.target, -penalty.amount)
	_active.erase(instance_id)
	curse_dispelled.emit(instance_id, curse.id)


func _apply_penalty(target: String, amount: float) -> void:
	match target:
		"change_reputation":
			Shop.add_reputation(int(amount))
		"change_buy_rate":
			Shop.add_buy_rate_modifier(amount)
		_:
			push_warning("Unknown curse penalty target: %s" % target)


func _pick_random_curse_id() -> String:
	var used_ids: Dictionary = {}
	for curse_id in _active.values():
		used_ids[curse_id] = true

	var candidates: Array[String] = []
	for curse in ContentRegistry.curses:
		if not used_ids.has(curse.id):
			candidates.append(curse.id)
	if candidates.is_empty():
		return ""
	return candidates[Rng.range_i(0, candidates.size() - 1)]


func get_save_data() -> Dictionary:
	return {"active": _active.duplicate()}


## Penalties were already baked into Shop's saved reputation/buy_rate_modifier
## at save time (see Shop.get_save_data()) — this only restores which
## instances are still active so a later attempt_dispel() can find them,
## without re-applying (and double-counting) their penalties.
func load_save_data(data: Dictionary) -> void:
	_active = (data.get("active", {}) as Dictionary).duplicate()
