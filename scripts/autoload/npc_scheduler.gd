extends Node
## Picks which room each love interest is currently in. Autoloaded as
## "NPCScheduler". See docs/design/systems.md, system 13 ("NPC interaction").
##
## Same selection rule as NPCDialogue.talk_to()/SceneDirector.recheck():
## highest-priority satisfied candidate wins, ties by registration order.
## Conditions are parsed once up front so resolving never touches a parser
## mid-game.

signal npc_room_changed(npc_id: String, room_id: String)

## Every love interest needs at least one condition = "true", full-day,
## Priority.LOW fallback block registered here, same convention NPCDialogue
## enforces for conversations.
const NPC_SCHEDULE_PATHS: Array[String] = [
	"res://data/npc_schedules/callie/fallback.tres",
	"res://data/npc_schedules/callie/morning_shop.tres",
	"res://data/npc_schedules/callie/afternoon_garden.tres",
	"res://data/npc_schedules/larissa/fallback.tres",
	"res://data/npc_schedules/larissa/morning_orrery.tres",
	"res://data/npc_schedules/larissa/afternoon_altar.tres",
	"res://data/npc_schedules/haerin/fallback.tres",
	"res://data/npc_schedules/haerin/morning_leyline.tres",
	"res://data/npc_schedules/haerin/evening_garden.tres",
	"res://data/npc_schedules/zara/fallback.tres",
	"res://data/npc_schedules/zara/weekday_morning_training.tres",
	"res://data/npc_schedules/zara/weekday_morning_funds_low.tres",
	"res://data/npc_schedules/zara/evening_shop.tres",
	"res://data/npc_schedules/lyra/fallback.tres",
	"res://data/npc_schedules/lyra/morning_scrapyard.tres",
	"res://data/npc_schedules/lyra/afternoon_shop.tres",
]

## Schedule windows are hour-plus granularity, so re-resolving every 5
## in-game minutes instead of every 1 loses nothing visible while cutting
## redundant condition evaluation roughly 5x.
const RESOLVE_INTERVAL_MINUTES := 5

var _entries_by_npc: Dictionary = {}   # npc_id -> Array[{"def", "condition_ast"}]
var _current_room: Dictionary = {}     # npc_id -> String


func _ready() -> void:
	for path in NPC_SCHEDULE_PATHS:
		_register(load(path) as NPCScheduleBlockDef)
	Clock.day_started.connect(func(_d, _t): resolve_all())
	Clock.minute_tick.connect(_on_minute_tick)
	# Deliberately does not resolve here -- autoload _ready() runs at boot,
	# before a save is loaded/NPCState is restored. The first real resolution
	# happens from NPCDirector.setup(), which runs after Main.tscn loads and
	# every autoload's state is already correct (same reasoning
	# SceneDirector.recheck() isn't called from its own _ready() either).


## Parses the entry's condition once, up front, so resolve_all() never
## touches a parser mid-game. Skips (with a push_error) an entry whose
## condition fails to parse.
func _register(entry_def: NPCScheduleBlockDef) -> void:
	var condition_parser := VNExpressionParser.new()
	var condition_ast = condition_parser.parse(entry_def.condition)
	if condition_ast == null:
		push_error("NPCScheduler: entry '%s' has an invalid condition" % entry_def.id)
		return

	if not _entries_by_npc.has(entry_def.npc_id):
		_entries_by_npc[entry_def.npc_id] = []
	_entries_by_npc[entry_def.npc_id].append({"def": entry_def, "condition_ast": condition_ast})


func _on_minute_tick(_timestamp: int) -> void:
	if Clock.minute_of_day() % RESOLVE_INTERVAL_MINUTES == 0:
		resolve_all()


func resolve_all() -> void:
	for npc_id in _entries_by_npc:
		_resolve_one(npc_id)


## Picks the highest-priority satisfied schedule block for npc_id and, if it
## names a different room than the NPC is currently resolved to, updates
## _current_room and emits npc_room_changed. Warns if nothing matches --
## every NPC should have at least one condition = "true", priority = LOW
## fallback block authored.
func _resolve_one(npc_id: String) -> void:
	var minute := Clock.minute_of_day()
	var is_weekend := Clock.day_type() == Clock.DayType.WEEKEND

	var best: Dictionary = {}
	for entry in _entries_by_npc.get(npc_id, []):
		var entry_def: NPCScheduleBlockDef = entry.def
		if entry_def.day_type_filter != NPCScheduleBlockDef.DayTypeFilter.ANY:
			var wants_weekend := entry_def.day_type_filter == NPCScheduleBlockDef.DayTypeFilter.WEEKEND
			if wants_weekend != is_weekend:
				continue
		if minute < entry_def.start_minute or minute > entry_def.end_minute:
			continue
		if not VNExpressionEvaluator.evaluate(entry.condition_ast):
			continue
		if best.is_empty() or entry_def.priority > best.def.priority:
			best = entry

	if best.is_empty():
		push_warning("NPCScheduler: no satisfied schedule block for npc_id '%s'" % npc_id)
		return

	var new_room_id: String = best.def.room_id
	if _current_room.get(npc_id, "") != new_room_id:
		_current_room[npc_id] = new_room_id
		npc_room_changed.emit(npc_id, new_room_id)


func get_current_room(npc_id: String) -> String:
	return _current_room.get(npc_id, "")
