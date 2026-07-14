class_name SceneTriggerDef
extends Resource
## Static definition of a VN scene trigger. See docs/design/systems.md,
## system 13 ("Scene triggering").
##
## Deliberately no trigger-*type* taxonomy — `condition` is the same
## expression-language source used by dialogue `if` statements, parsed once
## when SceneDirector registers this trigger. Priority is a bucket, not a raw
## number, so authors never have to fight arbitrary priority values against
## each other; ties within a bucket resolve by registration order.

enum Priority { LOW, NORMAL, HIGH, MAX }

@export var id: String
@export var script_path: String
@export var condition: String = "true"
@export var priority: Priority = Priority.NORMAL
@export var repeatable: bool = false
@export var show_from_menu: bool = false
