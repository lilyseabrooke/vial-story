class_name DragonStashJob
extends TetheredJobBase
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
var quality: float = 0.0
