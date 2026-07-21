class_name DragonStashJob
extends RefCounted
## A Dragon's Stash dig in progress. See docs/design/systems.md, the
## Draconology / Dragon's Stash System section.
##
## Player-tethered like WritJob -- minutes_elapsed only advances while the
## player is standing at the stash -- but with no pause state: WritJob keeps
## partial progress when the player steps away and resumes later, while a
## Dragon's Stash is meant to punish walking away, so Draconology just erases
## the whole job on player_exited instead of tracking is_working. There is
## therefore no is_working field here; a job existing in Draconology._jobs at
## all means it's actively being dug.

var stash_id: String
var minutes_elapsed: int = 0
var minutes_required: int = 0
var quality: float = 0.0


func progress_fraction() -> float:
	return clampf(float(minutes_elapsed) / float(minutes_required), 0.0, 1.0) if minutes_required > 0 else 0.0
