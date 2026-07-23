extends Node
## Orchestrates save/load across every gameplay autoload. Autoloaded as
## "SaveManager", registered last so every system it reads/writes already
## exists. See docs/design/systems.md, system 14.
##
## File format is JSON: human-inspectable, fails cleanly on corruption (no
## risky binary deserialize), and is trivial to migrate as a dict tree. A
## "game" is one playthrough (character name + shop origin choice), keyed by
## a slugified, timestamp-suffixed game_id; each game holds any number of
## numbered save slots. Every write backs up the previous file first and
## writes via a temp file + rename, so an interrupted write never destroys
## the last-good save.

const SAVE_ROOT := "user://saves/"
const CURRENT_SAVE_VERSION := 1

## Keyed by the version a migration upgrades FROM (e.g. entry 1 migrates a v1
## payload to v2). Empty today — no format changes yet — but the seam exists
## so a future version bump doesn't require rewriting the loader.
## Example shape once needed:
##   const _MIGRATIONS := { 1: Callable(SaveManager, "_migrate_v1_to_v2") }
##   func _migrate_v1_to_v2(payload: Dictionary) -> Dictionary: ...
const _MIGRATIONS: Dictionary = {}

## Autoloads this system saves/restores, in the order load_game() must
## restore them in: PlayerProfile first (no dependencies), then Clock (every
## other system's timestamp comparisons depend on it being restored first),
## then the rest in roughly their project.godot autoload dependency order.
## Alchemy restores before Brewing because a saved in-progress brew job
## resolves its RecipeDef via Alchemy.get_learned_recipe() (dynamically
## discovered recipes only exist there, not in ContentRegistry). Brewing/
## Herbalism rebuild their station/plot arrays wholesale from saved
## data and rely on Clock already being correct so already-elapsed jobs/plots
## resolve naturally on the very next minute_tick, with no special catch-up
## logic. Economy's own load_save_data() deliberately does not replay
## purchased_upgrade_ids through _apply_effect() — see the comment there —
## since Brewing/Shop/Herbalism already restore their resulting numbers
## directly.
const _SAVE_ORDER := [
	"PlayerProfile", "Clock", "Rng", "Inventory", "Resolve", "Skills",
	"Alchemy", "Brewing", "Herbalism", "Shop", "Economy", "Academy", "Demonology", "Draconology", "Summoning", "Transmutation", "Story", "LoveInterests",
	"QuestManager",
]


func _node_for(autoload_name: String) -> Node:
	return get_node("/root/" + autoload_name)


## Creates a brand-new game (character name, pronouns, House, shop origin,
## player color, skill point allocation), sets PlayerProfile, resets Skills
## and grants the starting allocation, and writes its meta.json with no slots
## yet. Called by scripts/character_creator.gd once the player confirms.
## skill_allocations is skill_id -> starting points, built by CharacterCreator
## (the 5 freely-allocated skills plus the shop-origin ingredient-skill bonus
## from Skills.skill_id_for_category()).
func create_new_game(
	character_name: String, pronouns: String, house_id: String,
	shop_origin: String, player_color: Color, skill_allocations: Dictionary
) -> String:
	var created_at := int(Time.get_unix_time_from_system())
	var game_id := "%s_%d" % [_slugify(character_name), created_at]

	PlayerProfile.character_name = character_name
	PlayerProfile.pronouns = pronouns
	PlayerProfile.house_id = house_id
	PlayerProfile.shop_origin = shop_origin
	PlayerProfile.player_color_hex = player_color.to_html()

	Skills.load_save_data({})  # reset any leftover XP from a prior playthrough
	for skill_id in skill_allocations:
		Skills.grant_starting_points(skill_id, skill_allocations[skill_id])

	var meta := {
		"version": 1,
		"game_id": game_id,
		"character_name": character_name,
		"pronouns": pronouns,
		"house_id": house_id,
		"shop_origin": shop_origin,
		"created_at_unix": created_at,
		"next_slot": 1,
		"latest_slot": 0,
		"latest_saved_at_unix": 0,
		"latest_day_number": 0,
		"latest_materials": 0,
		"slots": [],
	}
	_write_meta(game_id, meta)
	return game_id


## slot == -1 allocates a new slot. Returns {ok, slot, error}.
func save_game(game_id: String, slot: int = -1) -> Dictionary:
	var meta := _read_meta(game_id)
	if meta.is_empty():
		return {"ok": false, "slot": -1, "error": "No such game."}

	if slot == -1:
		slot = meta.get("next_slot", 1)

	var payload := {}
	for autoload_name in _SAVE_ORDER:
		payload[autoload_name] = _node_for(autoload_name).get_save_data()

	var wrapper := {
		"version": CURRENT_SAVE_VERSION,
		"checksum": _compute_checksum(payload),
		"payload": payload,
	}

	var slot_path := _slot_path(game_id, slot)
	if not _backup_then_write(slot_path, wrapper):
		return {"ok": false, "slot": slot, "error": "Write failed."}

	_update_meta_after_save(game_id, meta, slot)
	return {"ok": true, "slot": slot, "error": ""}


## Returns {ok, used_backup, error}. On ok, every autoload has already been
## restored. Never falls through to a fresh game on corruption — if the slot
## and its backup both fail validation, returns ok = false and leaves it to
## the caller to tell the player explicitly.
func load_game(game_id: String, slot: int) -> Dictionary:
	var slot_path := _slot_path(game_id, slot)

	var wrapper = _read_slot_file(slot_path)
	var used_backup := false
	if wrapper == null:
		wrapper = _read_slot_file(slot_path + ".bak")
		if wrapper != null:
			used_backup = true
			_write_json_file_atomic(slot_path, wrapper)  # self-heal the primary file

	if wrapper == null:
		return {"ok": false, "used_backup": false, "error": "corrupt"}

	var payload: Dictionary = _migrate_to_current(wrapper)
	for autoload_name in _SAVE_ORDER:
		if payload.has(autoload_name):
			_node_for(autoload_name).load_save_data(payload[autoload_name])

	return {"ok": true, "used_backup": used_backup, "error": ""}


func quick_load_latest(game_id: String) -> Dictionary:
	var meta := _read_meta(game_id)
	if meta.is_empty():
		return {"ok": false, "used_backup": false, "error": "No such game."}
	var slot: int = meta.get("latest_slot", 0)
	if slot == 0:
		return {"ok": false, "used_backup": false, "error": "No saves yet."}
	return load_game(game_id, slot)


## Reads every game's meta.json (never opens a slot file), sorted newest-saved
## first — the data source for a game-picker screen's "one big button" per game.
func list_games() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_ROOT)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var meta := _read_meta(entry)
			if not meta.is_empty():
				result.append(meta)
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return a.get("latest_saved_at_unix", 0) > b.get("latest_saved_at_unix", 0)
	)
	return result


## Reads one game's meta.json "slots" summary only — for the secondary,
## tucked-away per-slot list UI.
func list_slots(game_id: String) -> Array[Dictionary]:
	var meta := _read_meta(game_id)
	var result: Array[Dictionary] = []
	for entry in meta.get("slots", []):
		result.append(entry)
	return result


func delete_slot(game_id: String, slot: int) -> bool:
	var meta := _read_meta(game_id)
	if meta.is_empty():
		return false

	var dir := DirAccess.open(SAVE_ROOT.path_join(game_id))
	if dir == null:
		return false
	for suffix in ["", ".bak", ".tmp"]:
		var filename := "slot_%d.json%s" % [slot, suffix]
		if dir.file_exists(filename):
			dir.remove(filename)

	var slots: Array = meta.get("slots", [])
	for i in range(slots.size() - 1, -1, -1):
		if slots[i].get("slot") == slot:
			slots.remove_at(i)
	meta["slots"] = slots

	if meta.get("latest_slot", 0) == slot:
		_recompute_latest(meta, slots)

	_write_meta(game_id, meta)
	return true


func delete_game(game_id: String) -> bool:
	var dir_path := SAVE_ROOT.path_join(game_id)
	if not DirAccess.dir_exists_absolute(dir_path):
		return false
	return _remove_dir_recursive(dir_path)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _slot_path(game_id: String, slot: int) -> String:
	return SAVE_ROOT.path_join(game_id).path_join("slot_%d.json" % slot)


func _meta_path(game_id: String) -> String:
	return SAVE_ROOT.path_join(game_id).path_join("meta.json")


func _slugify(text: String) -> String:
	var lower := text.to_lower()
	var result := ""
	for ch in lower:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			result += ch
		else:
			result += "_"
	while result.contains("__"):
		result = result.replace("__", "_")
	result = result.trim_prefix("_").trim_suffix("_")
	return result if result != "" else "game"


## JSON has no int/float distinction — parsing a stringified int back always
## yields a float, so a dict fresh from live game state (real ints) and the
## same dict after a JSON round-trip (all floats) stringify differently even
## though they're logically identical. Round-tripping through JSON once here
## before hashing canonicalizes both cases to the same shape, so a checksum
## computed at save time (from live objects) matches one recomputed at load
## time (from already-parsed JSON) for identical data.
func _compute_checksum(data: Dictionary) -> String:
	var canonical: String = JSON.stringify(JSON.parse_string(JSON.stringify(data)))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical.to_utf8_buffer())
	return ctx.finish().hex_encode()


func _read_json_raw(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return parsed


## Validates a slot wrapper {version, checksum, payload} — returns null on
## any missing file, parse failure, or checksum mismatch.
func _read_slot_file(path: String) -> Variant:
	var wrapper = _read_json_raw(path)
	if wrapper == null or not wrapper.has("payload") or not wrapper.has("checksum"):
		return null
	if _compute_checksum(wrapper["payload"]) != wrapper["checksum"]:
		return null
	return wrapper


## Validates a meta.json dict, whose checksum covers the dict minus the
## checksum field itself.
func _read_meta_file(path: String) -> Variant:
	var meta = _read_json_raw(path)
	if meta == null or not meta.has("checksum"):
		return null
	var expected = meta["checksum"]
	var copy: Dictionary = meta.duplicate()
	copy.erase("checksum")
	if _compute_checksum(copy) != expected:
		return null
	return meta


## Reads a game's meta.json, falling back to meta.json.bak (and self-healing
## the primary from it) if the primary is missing or corrupt. Returns {} if
## neither validates, so callers can treat that game as unreadable rather
## than crashing.
func _read_meta(game_id: String) -> Dictionary:
	var path := _meta_path(game_id)
	var meta = _read_meta_file(path)
	if meta == null:
		meta = _read_meta_file(path + ".bak")
		if meta != null:
			_write_json_file_atomic(path, meta)
	if meta == null:
		return {}
	return meta


func _write_meta(game_id: String, meta: Dictionary) -> void:
	var to_write: Dictionary = meta.duplicate()
	to_write.erase("checksum")
	to_write["checksum"] = _compute_checksum(to_write)
	_backup_then_write(_meta_path(game_id), to_write)


func _update_meta_after_save(game_id: String, meta: Dictionary, slot: int) -> void:
	var now := int(Time.get_unix_time_from_system())
	var day_number: int = Clock.day_number
	var materials: int = Inventory.materials

	var slots: Array = meta.get("slots", [])
	var found := false
	for entry in slots:
		if entry.get("slot") == slot:
			entry["saved_at_unix"] = now
			entry["day_number"] = day_number
			found = true
			break
	if not found:
		slots.append({"slot": slot, "saved_at_unix": now, "day_number": day_number})

	meta["slots"] = slots
	meta["latest_slot"] = slot
	meta["latest_saved_at_unix"] = now
	meta["latest_day_number"] = day_number
	meta["latest_materials"] = materials
	meta["next_slot"] = maxi(meta.get("next_slot", 1), slot + 1)

	_write_meta(game_id, meta)


func _recompute_latest(meta: Dictionary, slots: Array) -> void:
	if slots.is_empty():
		meta["latest_slot"] = 0
		meta["latest_saved_at_unix"] = 0
		meta["latest_day_number"] = 0
		return
	var latest: Dictionary = slots[0]
	for entry in slots:
		if entry.get("saved_at_unix", 0) > latest.get("saved_at_unix", 0):
			latest = entry
	meta["latest_slot"] = latest.get("slot", 0)
	meta["latest_saved_at_unix"] = latest.get("saved_at_unix", 0)
	meta["latest_day_number"] = latest.get("day_number", 0)


func _migrate_to_current(wrapper: Dictionary) -> Dictionary:
	var payload: Dictionary = wrapper.get("payload", {})
	var v: int = wrapper.get("version", 1)
	while v < CURRENT_SAVE_VERSION:
		if not _MIGRATIONS.has(v):
			push_error("No migration path from save version %d" % v)
			break
		payload = _MIGRATIONS[v].call(payload)
		v += 1
	return payload


## Writes `data` to `path` via a temp file + rename, so an interrupted write
## never leaves a truncated file at the real path.
func _write_json_file_atomic(path: String, data: Dictionary) -> bool:
	var dir_path := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false
	if dir.file_exists(path.get_file()):
		dir.remove(path.get_file())
	return dir.rename(tmp_path.get_file(), path.get_file()) == OK


## Copies the existing file to `<path>.bak` (if present) before overwriting,
## so a corrupting write still leaves a last-known-good backup on disk.
func _backup_then_write(path: String, data: Dictionary) -> bool:
	var dir_path := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)

	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + ".bak")

	return _write_json_file_atomic(path, data)


func _remove_dir_recursive(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := path.path_join(entry)
			if dir.current_is_dir():
				_remove_dir_recursive(full)
			else:
				dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(path) == OK
