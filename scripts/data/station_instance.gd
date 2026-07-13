class_name StationInstance
extends RefCounted
## Runtime brewing station. See docs/design/systems.md, system 4.

var id: String
var display_name: String
var station_type: String
var potency_modifier: float = 0.0
var ease_modifier: float = 0.0
var speed_modifier: float = 1.0
var current_job: BrewJob = null
