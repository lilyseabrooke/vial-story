class_name ArtStudioJob
extends TimedJobBase
## A session in progress at an Art Studio. See docs/design/systems.md, the
## Art Studio / Creativity System section.
##
## Two different timing models back to back, matching the two systems this
## borrows from: ROLLING is a Clock timestamp deadline exactly like BrewJob
## (inherited from TimedJobBase -- ticks whether or not the player is standing
## there), while WORKING is a tethered accumulator exactly like WritJob (only
## advances while is_working is true; kept as its own fields here rather than
## also extending TetheredJobBase since GDScript doesn't support extending
## both). CHOOSING sits between them with no timer at all -- the bar is full
## and offered_inspiration_ids is waiting on the player to call
## ArtStudio.choose_inspiration()/cancel_choice().

enum Phase { ROLLING, CHOOSING, WORKING }

var studio_id: String
var phase: Phase = Phase.ROLLING

## CHOOSING only -- the ids ArtStudio rolled and offered, in display order.
var offered_inspiration_ids: Array[String] = []

## WORKING only (also set going into it from CHOOSING).
var inspiration_id: String = ""
var is_working: bool = false
var minutes_elapsed: int = 0
var minutes_required: int = 0


func work_progress_fraction() -> float:
	return clampf(float(minutes_elapsed) / float(minutes_required), 0.0, 1.0) if minutes_required > 0 else 0.0
