extends Node
## Hidden per-love-interest state -- mood, funds, and relationships with each
## other -- that NPCScheduler's schedule-block conditions can react to.
## Autoloaded as "NPCState". See docs/design/systems.md, system 13.
##
## Deliberately separate from LoveInterests (the player-facing affection
## ledger) -- this is never shown to the player, only read by schedule/
## dialogue conditions via the npc_mood()/npc_funds()/npc_relationship()
## expression functions.

signal npc_state_changed(npc_id: String)

const NPC_IDS := ["callie", "larissa", "haerin", "zara", "lyra"]

const DEFAULT_MOOD := 50
const DEFAULT_FUNDS := 50
const DEFAULT_RELATIONSHIP := 0

var _mood: Dictionary = {}            # npc_id -> int (0-100)
var _funds: Dictionary = {}           # npc_id -> int (0-100)
var _relationships: Dictionary = {}   # npc_id -> Dictionary(other_npc_id -> int, -100..100)


func _ready() -> void:
	for npc_id in NPC_IDS:
		_mood[npc_id] = DEFAULT_MOOD
		_funds[npc_id] = DEFAULT_FUNDS
		_relationships[npc_id] = {}
		for other_id in NPC_IDS:
			if other_id != npc_id:
				_relationships[npc_id][other_id] = DEFAULT_RELATIONSHIP
	Clock.day_started.connect(_on_day_started)


func get_mood(npc_id: String) -> int:
	return _mood.get(npc_id, DEFAULT_MOOD)


func get_funds(npc_id: String) -> int:
	return _funds.get(npc_id, DEFAULT_FUNDS)


func get_relationship(npc_id: String, other_id: String) -> int:
	return (_relationships.get(npc_id, {}) as Dictionary).get(other_id, DEFAULT_RELATIONSHIP)


func _on_day_started(_day_number: int, _day_type: int) -> void:
	for npc_id in NPC_IDS:
		_roll_overnight(npc_id)


## Placeholder overnight roll -- replace this body with real logic (job
## income, mood from dates/gifts, jealousy from the player dating someone
## else, etc.) later. Every caller only ever goes through get_mood()/
## get_funds()/get_relationship(), so nothing outside this function needs to
## change when the real logic lands. Funds are biased slightly negative so
## the "funds low" schedule branch is actually reachable in normal play.
func _roll_overnight(npc_id: String) -> void:
	_mood[npc_id] = clampi(get_mood(npc_id) + Rng.range_i(-10, 10), 0, 100)
	_funds[npc_id] = clampi(get_funds(npc_id) + Rng.range_i(-15, 10), 0, 100)
	for other_id in NPC_IDS:
		if other_id == npc_id:
			continue
		var relationships: Dictionary = _relationships[npc_id]
		relationships[other_id] = clampi(relationships.get(other_id, DEFAULT_RELATIONSHIP) + Rng.range_i(-3, 3), -100, 100)
	npc_state_changed.emit(npc_id)


func get_save_data() -> Dictionary:
	return {
		"mood": _mood.duplicate(true),
		"funds": _funds.duplicate(true),
		"relationships": _relationships.duplicate(true),
	}


func load_save_data(data: Dictionary) -> void:
	var saved_mood: Dictionary = data.get("mood", {})
	var saved_funds: Dictionary = data.get("funds", {})
	var saved_relationships: Dictionary = data.get("relationships", {})
	for npc_id in NPC_IDS:
		_mood[npc_id] = saved_mood.get(npc_id, DEFAULT_MOOD)
		_funds[npc_id] = saved_funds.get(npc_id, DEFAULT_FUNDS)
		_relationships[npc_id] = (saved_relationships.get(npc_id, {}) as Dictionary).duplicate()
		for other_id in NPC_IDS:
			if other_id != npc_id and not _relationships[npc_id].has(other_id):
				_relationships[npc_id][other_id] = DEFAULT_RELATIONSHIP
