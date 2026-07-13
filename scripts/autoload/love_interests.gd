extends Node
## Love interest affection tracking. Autoloaded as "LoveInterests".
## See docs/design/systems.md, system 13.
##
## Runtime affection state only — static love-interest data (display name,
## house, etc.) will live in a LoveInterestDef resource once scenes need it;
## affection itself is keyed by a plain string id so this has no dependency
## on that resource existing yet.

signal affection_changed(love_interest_id: String, affection: int)

var _affection: Dictionary = {}   # love_interest_id -> int


func get_affection(love_interest_id: String) -> int:
	return _affection.get(love_interest_id, 0)


func add_affection(love_interest_id: String, amount: int) -> void:
	var new_value := get_affection(love_interest_id) + amount
	_affection[love_interest_id] = new_value
	affection_changed.emit(love_interest_id, new_value)
