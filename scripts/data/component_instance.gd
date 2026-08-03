class_name ComponentInstance
extends RefCounted
## Runtime record of one owned zone component. See docs/design/systems.md,
## system 4 (Placement System). Owned by the Placement autoload -- existence
## in Placement.component_instances *is* "purchased," there's no separate
## purchased/cost bool the way StationInstance/PantryInstance used to carry,
## since a ComponentInstance is only ever created by Placement.purchase_component()
## after its ComponentDef's cost has actually been spent.

var id: String
var def_id: String
var zone_id: String = ""
var grid_position: Vector2i = Vector2i(-1, -1)
var placed: bool = false
