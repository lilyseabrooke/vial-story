class_name NPCLineSetDef
extends Resource
## Static definition of one candidate NPC conversation. See
## docs/design/systems.md, system 13 ("NPC interaction").
##
## Several of these exist per npc_id -- NPCDialogue picks the
## highest-priority satisfied one each time the player talks to that NPC,
## the same selection rule SceneDirector uses for scene triggers. Duplicates
## SceneTriggerDef's condition/priority shape rather than importing it --
## same "no shared taxonomy coupling" precedent already set between
## condition-driven resources in this codebase.

enum Priority { LOW, NORMAL, HIGH, MAX }

@export var id: String
@export var npc_id: String        # must match a CharacterDef.id
@export var script_path: String   # a .vnscript file
@export var condition: String = "true"
@export var priority: Priority = Priority.NORMAL
@export var repeatable: bool = false
