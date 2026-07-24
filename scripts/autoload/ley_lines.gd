extends Node
## Ley Line Node minigame session + spectral-ingredient reward. Autoloaded
## as "LeyLines". See docs/design/systems.md, the Ley Line Node System
## section.
##
## Unlike Draconology's stash jobs, a ley-line session isn't a background
## timer -- MenuScene already pauses Clock and freezes the player for the
## whole interaction, so there's nothing to tick or tether. A
## LeyLineNodeInteractable.interact() call hands its own per-instance
## difficulty/rounds to start_minigame(), hud.gd opens the minigame panel
## (LeyLineMinigamePanel) in response to minigame_started, and that panel calls
## back into resolve_minigame()/abort_minigame() once the player finishes or
## bails. No get_save_data()/load_save_data() -- same as Transmutation,
## there's no state that outlives a single synchronous interaction.

signal minigame_started(node_id: String, difficulty: float, rounds: int)
signal minigame_resolved(node_id: String, performance: float, tier: String, ingredients: Dictionary)
signal minigame_aborted(node_id: String)

## Performance is a single 0.0-1.0 float the minigame reports back --
## these are the cutoffs between reward tiers, checked from the top down.
const TIER_THRESHOLDS := {
	"great": 0.85,
	"good": 0.6,
	"poor": 0.25,
}

## Base ingredient count per tier before Skills.get_bonus("leyline_yield") is
## added; a run that doesn't even clear the "poor" threshold gets nothing.
const TIER_BASE_COUNTS := {
	"great": 3,
	"good": 2,
	"poor": 1,
}

const SPECTRAL_INGREDIENT_IDS := ["glimmer_dust", "echo_shard"]

const XP_PER_MINIGAME := 20

var _active_node_id: String = ""
var _active_difficulty: float = 0.0
var _active_rounds: int = 0


func is_active() -> bool:
	return _active_node_id != ""


func get_active_node_id() -> String:
	return _active_node_id


## Applies leyline_ease (Arcane History) to soften the base difficulty
## LeyLineNodeInteractable was configured with before handing it to the
## minigame -- a higher-Arcane-History player gets an easier ride at the
## same node. No-op if a session is already active (shouldn't normally
## happen -- MenuScene freezes the player for the whole interaction --
## LeyLineNodeInteractable.interact() guards against it too).
func start_minigame(node_id: String, base_difficulty: float, rounds: int) -> void:
	if is_active():
		return
	var ease_bonus := Skills.get_bonus("leyline_ease")
	_active_node_id = node_id
	_active_difficulty = maxf(base_difficulty - ease_bonus, 0.0)
	_active_rounds = rounds
	minigame_started.emit(node_id, _active_difficulty, _active_rounds)


## Called by the minigame (LeyLineMinigamePanel) with a single 0.0-1.0
## performance number once it's finished, plus the count of bonus motes the
## player grabbed in-arena. Reward count is looked up by tier, then
## Skills.get_bonus("leyline_yield") is added on top -- the same "base count
## from a quality tier + a skill's flat yield bonus" shape
## Draconology._grant_ingredients() uses, just with the tier already handed
## to us instead of derived from a continuous quality float. A performance
## below every tier's threshold grants nothing from the tier reward -- but
## bonus_ingredients are granted regardless of tier (even on a failed run),
## since collecting a mote is its own earned reward and the risk was the
## resolve/position cost of chasing it. Both funnel into the same ingredients
## dict so hud.gd's reward summary shows them together.
func resolve_minigame(performance: float, bonus_ingredients: int = 0) -> void:
	if not is_active():
		return
	var node_id := _active_node_id
	var p := clampf(performance, 0.0, 1.0)
	var tier := _tier_for_performance(p)

	# performance is already 0..1, so it doubles directly as the quality
	# fraction -- a stronger channel yields both more AND better spectral
	# ingredients.
	var quality_tier := IngredientQuality.tier_for_fraction(p)

	var ingredients: Dictionary = {}
	if tier != "":
		var yield_bonus := Skills.get_bonus("leyline_yield")
		var count := maxi(int(TIER_BASE_COUNTS[tier] + yield_bonus), 0)
		for i in count:
			var id: String = SPECTRAL_INGREDIENT_IDS[Rng.range_i(0, SPECTRAL_INGREDIENT_IDS.size() - 1)]
			Inventory.add_ingredient(id, 1, quality_tier)
			ingredients[id] = ingredients.get(id, 0) + 1
		Skills.add_xp("arcane_history", XP_PER_MINIGAME)

	for i in maxi(bonus_ingredients, 0):
		var bonus_id: String = SPECTRAL_INGREDIENT_IDS[Rng.range_i(0, SPECTRAL_INGREDIENT_IDS.size() - 1)]
		Inventory.add_ingredient(bonus_id, 1, quality_tier)
		ingredients[bonus_id] = ingredients.get(bonus_id, 0) + 1

	_active_node_id = ""
	_active_difficulty = 0.0
	_active_rounds = 0
	minigame_resolved.emit(node_id, p, tier if tier != "" else "failure", ingredients)


## Bailing on the minigame mid-run -- no ingredients, no XP, session just
## thrown away. Same "walking away costs everything" shape as
## Draconology.cancel_stash(), just triggered by the player choosing to quit
## the minigame (or closing the menu) instead of leaving the node's
## proximity, since MenuScene already freezes the player in place for the
## whole session.
func abort_minigame() -> void:
	if not is_active():
		return
	var node_id := _active_node_id
	_active_node_id = ""
	_active_difficulty = 0.0
	_active_rounds = 0
	minigame_aborted.emit(node_id)


func _tier_for_performance(p: float) -> String:
	if p >= TIER_THRESHOLDS["great"]:
		return "great"
	if p >= TIER_THRESHOLDS["good"]:
		return "good"
	if p >= TIER_THRESHOLDS["poor"]:
		return "poor"
	return ""
