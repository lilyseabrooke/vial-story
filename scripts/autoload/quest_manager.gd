extends Node
## Tracks quest progress and completion. Autoloaded as "QuestManager". See
## docs/design/systems.md, system 15.
##
## No start_condition polling — start_quest() is the only way a quest becomes
## Active, called explicitly by whatever content wants to grant it (an
## interaction, a scene action-call via VNExpressionEvaluator's "start_quest"
## function). Progress/completion *is* polled, same pattern as
## SceneDirector.recheck(): every Active quest's complete_condition is
## re-evaluated on every Clock.minute_tick. Event-driven per-objective-type
## counters can replace this poll later without changing QuestDef's shape or
## the public API here — that's an open extension point, not a limitation
## baked into the data.
##
## complete_condition and reward expressions are both parsed once at _ready(),
## same "never touch the parser mid-game" discipline as SceneDirector
## registering its triggers up front.

enum Status { ACTIVE, READY_TO_TURN_IN, COMPLETED }

signal quest_started(id: String)
signal quest_ready_to_turn_in(id: String)
signal quest_completed(id: String)

var _statuses: Dictionary = {}          # quest_id -> Status
var _condition_asts: Dictionary = {}    # quest_id -> parsed AST
var _reward_asts: Dictionary = {}       # quest_id -> Array[AST]


func _ready() -> void:
	for quest in ContentRegistry.quests:
		var condition_parser := VNExpressionParser.new()
		var condition_ast = condition_parser.parse(quest.complete_condition)
		if condition_ast == null:
			push_error("QuestManager: quest '%s' has an invalid complete_condition" % quest.id)
			continue

		var reward_asts: Array = []
		var reward_failed := false
		for expr in quest.reward:
			var reward_parser := VNExpressionParser.new()
			var reward_ast = reward_parser.parse(expr)
			if reward_ast == null:
				push_error("QuestManager: quest '%s' has an invalid reward expression '%s'" % [quest.id, expr])
				reward_failed = true
				break
			reward_asts.append(reward_ast)
		if reward_failed:
			continue

		_condition_asts[quest.id] = condition_ast
		_reward_asts[quest.id] = reward_asts

	Clock.minute_tick.connect(func(_timestamp): _recheck())


func start_quest(id: String) -> void:
	if _statuses.has(id):
		return
	if not _condition_asts.has(id):
		push_error("QuestManager: start_quest() called with unknown or invalid id '%s'" % id)
		return
	_statuses[id] = Status.ACTIVE
	quest_started.emit(id)
	_recheck()


## For auto_complete == false quests only, once their complete_condition has
## flipped them to ReadyToTurnIn.
func turn_in(id: String) -> void:
	if _statuses.get(id, -1) != Status.READY_TO_TURN_IN:
		push_error("QuestManager: turn_in() called on quest '%s' that isn't ready to turn in" % id)
		return
	_complete(id)


func status(id: String) -> int:
	return _statuses.get(id, -1)


func active_quest_ids() -> Array[String]:
	return _ids_with_status(Status.ACTIVE)


func ready_to_turn_in_quest_ids() -> Array[String]:
	return _ids_with_status(Status.READY_TO_TURN_IN)


func completed_quest_ids() -> Array[String]:
	return _ids_with_status(Status.COMPLETED)


func get_save_data() -> Dictionary:
	return _statuses.duplicate()


func load_save_data(data: Dictionary) -> void:
	_statuses.clear()
	for id in data:
		_statuses[id] = int(data[id])


func _recheck() -> void:
	for id in _statuses.keys():
		if _statuses[id] != Status.ACTIVE:
			continue
		if not VNExpressionEvaluator.evaluate(_condition_asts[id]):
			continue
		if ContentRegistry.get_quest(id).auto_complete:
			_complete(id)
		else:
			_statuses[id] = Status.READY_TO_TURN_IN
			quest_ready_to_turn_in.emit(id)


func _complete(id: String) -> void:
	for ast in _reward_asts.get(id, []):
		VNExpressionEvaluator.evaluate(ast)
	_statuses[id] = Status.COMPLETED
	quest_completed.emit(id)


func _ids_with_status(target: Status) -> Array[String]:
	var result: Array[String] = []
	for id in _statuses:
		if _statuses[id] == target:
			result.append(id)
	return result
