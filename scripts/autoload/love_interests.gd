extends Node
## Love interest affection tracking. Autoloaded as "LoveInterests".
## See docs/design/systems.md, system 13.
##
## Runtime affection state only — static love-interest data (display name,
## house, etc.) will live in a LoveInterestDef resource once scenes need it;
## affection itself is keyed by a plain string id so this has no dependency
## on that resource existing yet.

signal affection_changed(love_interest_id: String, affection: int)
signal dating_changed(love_interest_id: String)

var _affection: Dictionary = {}   # love_interest_id -> int
var _dating_id: String = ""       # "" if not dating anyone


func get_affection(love_interest_id: String) -> int:
	return _affection.get(love_interest_id, 0)


func add_affection(love_interest_id: String, amount: int) -> void:
	var new_value := get_affection(love_interest_id) + amount
	_affection[love_interest_id] = new_value
	affection_changed.emit(love_interest_id, new_value)


func is_dating(love_interest_id: String) -> bool:
	return _dating_id == love_interest_id


## Pass "" to clear (break up / not dating anyone).
func set_dating(love_interest_id: String) -> void:
	_dating_id = love_interest_id
	dating_changed.emit(love_interest_id)


func get_save_data() -> Dictionary:
	return {"affection": _affection.duplicate(), "dating_id": _dating_id}


func load_save_data(data: Dictionary) -> void:
	_affection = (data.get("affection", {}) as Dictionary).duplicate()
	_dating_id = data.get("dating_id", "")
