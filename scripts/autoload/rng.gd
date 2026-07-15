extends Node
## Single shared deterministic randomness source for the whole game.
## Autoloaded as "Rng". See docs/design/systems.md, system 16.
##
## Wraps one RandomNumberGenerator so every roll in the game -- quiet
## background checks and visible 2d10 checks alike -- draws from the same
## seeded stream in one consumption order. This is what makes save/load
## deterministic: only .state (the stream's draw position) needs to persist,
## not separate state per call site.
##
## Seeding happens exactly once, at new-game start (see seed_new_game()).
## Loading a save must NEVER reseed -- only restore .state -- so a player
## can't reroll a bad outcome by reloading.

const DICE_SIDES := 10

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Boot-time default so nothing crashes if a roll somehow happens before
	# seed_new_game()/load_save_data() runs. Never relied on in practice --
	# Rng loads before every gameplay autoload that could roll.
	_rng.randomize()


## Called once by main.gd on a brand-new game (GameFlow.is_new_game == true).
## Never called on a loaded game -- load_save_data() below restores state instead.
func seed_new_game() -> void:
	_rng.randomize()


# ---------------------------------------------------------------------------
# Quiet API -- direct replacements for bare randf()/randf_range() call sites.
# ---------------------------------------------------------------------------

func chance(probability: float) -> bool:
	return _rng.randf() < probability


func range_f(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func range_i(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


# ---------------------------------------------------------------------------
# Visible dice API -- 2d10 + flat modifier vs. a difficulty class.
# ---------------------------------------------------------------------------

## Rolls 2d10, adds `modifier`, compares against `dc`. Returns a plain
## Dictionary so a popup can render it without ever calling Rng itself --
## headless code calls this directly with no UI involvement.
##
## critical_failure/critical_success/inflection_point are computed from the
## natural (unmodified) die faces, not the modifier-adjusted total, so any
## caller can opt into them without Rng knowing what a "botch" or "crit" means
## to that particular system: a natural 1 on either die is a critical failure,
## a natural 10 on either die is a critical success, and a natural 1+10 pair
## overrides both into an inflection point (no mechanics attached here --
## it's on callers to decide what, if anything, that means).
func roll_2d10(modifier: float, dc: float) -> Dictionary:
	var die_a := _rng.randi_range(1, DICE_SIDES)
	var die_b := _rng.randi_range(1, DICE_SIDES)
	var total: float = die_a + die_b + modifier
	var inflection_point := (die_a == 1 and die_b == DICE_SIDES) or (die_a == DICE_SIDES and die_b == 1)
	return {
		"die_a": die_a,
		"die_b": die_b,
		"modifier": modifier,
		"total": total,
		"dc": dc,
		"passed": total >= dc,
		"inflection_point": inflection_point,
		"critical_failure": not inflection_point and (die_a == 1 or die_b == 1),
		"critical_success": not inflection_point and (die_a == DICE_SIDES or die_b == DICE_SIDES),
	}


func get_save_data() -> Dictionary:
	# Stored as a String -- SaveManager round-trips every payload through
	# JSON, whose numbers are doubles (53-bit mantissa) and would silently
	# truncate RandomNumberGenerator.state's full 64-bit range.
	return {"state": str(_rng.state)}


## Restores stream position only -- deliberately does NOT reseed. A reload
## must not let the player reroll a bad outcome.
func load_save_data(data: Dictionary) -> void:
	if data.has("state"):
		_rng.state = int(data["state"])
