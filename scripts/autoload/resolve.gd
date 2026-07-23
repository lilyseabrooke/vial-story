extends Node
## Combined health/energy stat. Autoloaded as "Resolve".
## See docs/design/systems.md, system 8.
##
## Does not drain from normal actions or time passing — only from failure/
## mishap events elsewhere (e.g. Brewing's botched-brew outcome) calling
## spend(). Below strained_threshold, Skills.get_bonus() applies a global
## debuff to every skill-driven bonus. At zero, the day ends via
## Clock.resolve_collapse() — framed as giving up for today, not a hard fail.

signal resolve_changed(current: int, max_resolve: int)
signal strained_changed(is_strained: bool)
signal collapsed

const STRAINED_DEBUFF_MULTIPLIER := 0.5
## Starting max_resolve, and the baseline the HUD's Resolve vial sizes itself
## against (see ResolveVial._size_scale_for) — 1.0 scale at this value.
const BASE_MAX_RESOLVE := 100

var max_resolve: int = BASE_MAX_RESOLVE
var current: int = BASE_MAX_RESOLVE
var strained_threshold: int = 30

var _was_strained: bool = false


func _ready() -> void:
	Clock.day_started.connect(_on_day_started)


func is_strained() -> bool:
	return current < strained_threshold


func spend(amount: int, reason: String = "") -> void:
	if amount <= 0:
		return
	current = maxi(current - amount, 0)
	resolve_changed.emit(current, max_resolve)
	_check_strained_transition()
	if reason != "":
		print("Resolve -%d (%s): now %d/%d" % [amount, reason, current, max_resolve])
	if current <= 0:
		collapsed.emit()
		Clock.resolve_collapse()


func restore(amount: int) -> void:
	current = mini(current + amount, max_resolve)
	resolve_changed.emit(current, max_resolve)
	_check_strained_transition()


func _check_strained_transition() -> void:
	var strained_now := is_strained()
	if strained_now != _was_strained:
		_was_strained = strained_now
		strained_changed.emit(strained_now)


## Prototype default: full regen on any day rollover (sleep, late collapse,
## or resolve collapse itself). Partial regen is an open spec question.
func _on_day_started(_day_number: int, _day_type: int) -> void:
	restore(max_resolve)


func get_save_data() -> Dictionary:
	return {
		"current": current,
		"max_resolve": max_resolve,
	}


## _was_strained is intentionally not saved — it's derivable from current vs.
## strained_threshold and gets naturally recomputed on the next spend()/restore().
func load_save_data(data: Dictionary) -> void:
	max_resolve = data.get("max_resolve", max_resolve)
	current = data.get("current", max_resolve)
	_was_strained = is_strained()
