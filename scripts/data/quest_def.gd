class_name QuestDef
extends Resource
## Static definition of a quest. See docs/design/systems.md, system 15.
##
## complete_condition reuses the same expression grammar as VN `if` statements
## and SceneTriggerDef.condition (VNExpressionParser/VNExpressionEvaluator),
## and reward reuses the same language's action-call syntax (give_item,
## add_affection, set_flag, ...) rather than a separate quest-effect table —
## a quest reward and a scene's action-call statements are the same kind of
## thing. Quests only ever start via QuestManager.start_quest() called
## explicitly from wherever makes sense (an interaction, a scene action-call);
## there's no start_condition here.

@export var id: String
@export var display_name: String
@export var description: String
@export var complete_condition: String = "true"
@export var reward: Array[String] = []
@export var auto_complete: bool = true
