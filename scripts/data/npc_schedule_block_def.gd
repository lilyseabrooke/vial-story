@icon("res://assets/editor_icons/icon_character.svg")
class_name NPCScheduleBlockDef
extends Resource
## Static definition of one candidate schedule block for a love interest. See
## docs/design/systems.md, system 13 ("NPC interaction").
##
## Several of these exist per npc_id -- NPCScheduler picks the
## highest-priority satisfied one for the current time to decide which room
## that NPC is in, the same selection rule NPCDialogue uses to pick a
## conversation and SceneDirector uses for scene triggers. Duplicates
## NPCLineSetDef's condition/priority shape rather than importing it -- same
## "no shared taxonomy coupling" precedent already set between
## condition-driven resources in this codebase.
##
## start_minute/end_minute are both inclusive and compared directly against
## Clock.minute_of_day() -- there's no midnight-wrap support (a block can't
## span e.g. 1350-90), since every block authored so far fits in a single day
## and wrapping would complicate the comparison for no current benefit.

enum DayTypeFilter { ANY, WEEKDAY, WEEKEND }
enum Priority { LOW, NORMAL, HIGH, MAX }

@export var id: String
@export var npc_id: String        # must match a CharacterDef.id
@export var room_id: String       # a RoomBuilder room id, e.g. "dragons_ground"
@export var day_type_filter: DayTypeFilter = DayTypeFilter.ANY
@export var start_minute: int = 0
@export var end_minute: int = 1439
@export var condition: String = "true"
@export var priority: Priority = Priority.NORMAL
