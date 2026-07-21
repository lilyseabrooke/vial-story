extends Node
## Breaking down Scrap into artificial ingredients at a Workbench. Autoloaded
## as "Transmutation". See docs/design/systems.md, the Transmutation /
## Workbench System section.
##
## Unlike Demonology's writs, breaking down Scrap has no multi-minute phase to
## wait through -- one interaction at the Workbench pops one piece of Scrap
## from Inventory and resolves it immediately. Owns no persistent state of its
## own (the Scrap it consumes and the ingredients it grants both live in
## Inventory), so it isn't part of SaveManager._SAVE_ORDER.

signal scrap_broken_down(roll: Dictionary, ingredients: Dictionary)

const ARTIFICIAL_INGREDIENT_IDS := ["scrap_alloy", "refined_component"]

const BREAKDOWN_DC := 11.0
const CRIT_QUALITY_SWING := 15.0

const BASE_INGREDIENT_COUNT := 1
const QUALITY_INGREDIENT_DIVISOR := 20.0

const XP_PER_BREAKDOWN := 15


## Pops one piece of Scrap from Inventory (FIFO) and resolves it: a visible
## 2d10 Transmutation check (modifier = transmute_ease) shifts the popped
## piece's hidden quality by +/-CRIT_QUALITY_SWING on a crit, and the final
## quality drives how many artificial ingredients are granted -- same
## "quality drives yield" shape as Demonology.submit_writ(), just resolved in
## one call instead of across a writing/revising job. No-op (returns {}) if
## there's no Scrap to break down.
func break_down_scrap() -> Dictionary:
	var piece := Inventory.take_scrap()
	if piece.is_empty():
		return {}

	var modifier := Skills.get_bonus("transmute_ease")
	var roll := Rng.roll_2d10(modifier, BREAKDOWN_DC)

	var quality: float = piece.get("quality", 0.0)
	if roll.critical_success:
		quality += CRIT_QUALITY_SWING
	elif roll.critical_failure:
		quality -= CRIT_QUALITY_SWING
	quality = maxf(quality, 0.0)

	var ingredients := _grant_ingredients(quality)
	Skills.add_xp("transmutation", XP_PER_BREAKDOWN)

	scrap_broken_down.emit(roll, ingredients)
	return {"roll": roll, "ingredients": ingredients}


func _grant_ingredients(quality: float) -> Dictionary:
	var yield_bonus := Skills.get_bonus("transmute_yield")
	var count := int(BASE_INGREDIENT_COUNT + floor(quality / QUALITY_INGREDIENT_DIVISOR) + yield_bonus)
	count = maxi(count, 1)
	var granted: Dictionary = {}
	for i in count:
		var id: String = ARTIFICIAL_INGREDIENT_IDS[Rng.range_i(0, ARTIFICIAL_INGREDIENT_IDS.size() - 1)]
		Inventory.add_ingredient(id, 1)
		granted[id] = granted.get(id, 0) + 1
	return granted
