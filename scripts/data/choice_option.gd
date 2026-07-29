class_name ChoiceOption
extends Resource
## One item in a ChoiceListMenu -- id to report back on selection, label/
## description/icon for display, enabled to gray out an unavailable option
## without hiding it, metadata for any extra per-item data a specific menu
## needs (e.g. an Inspiration's DC/duration) without ChoiceListMenu needing
## to know about it. See docs/engine_roadmap.md, Phase 7.

@export var id: String = ""
@export var label: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var enabled: bool = true
var metadata: Dictionary = {}


static func make(id: String, label: String, description: String = "", enabled: bool = true) -> ChoiceOption:
	var option := ChoiceOption.new()
	option.id = id
	option.label = label
	option.description = description
	option.enabled = enabled
	return option
