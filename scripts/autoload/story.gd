extends Node
## Global story flags. Autoloaded as "Story". See docs/design/systems.md, system 13.
##
## Deliberately just a flat flag store — no scoping/namespacing — since
## anything more structured can be built on top once real content exists.

signal flag_changed(flag_id: String, value: bool)

var _flags: Dictionary = {}   # flag_id -> bool


func has_flag(flag_id: String) -> bool:
	return _flags.get(flag_id, false)


func set_flag(flag_id: String, value: bool = true) -> void:
	if has_flag(flag_id) == value:
		return
	_flags[flag_id] = value
	flag_changed.emit(flag_id, value)


func get_save_data() -> Dictionary:
	return {"flags": _flags.duplicate()}


func load_save_data(data: Dictionary) -> void:
	_flags = (data.get("flags", {}) as Dictionary).duplicate()
