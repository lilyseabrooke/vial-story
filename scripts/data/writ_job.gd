class_name WritJob
extends RefCounted
## A demonic contract writ in progress at a Contract Book. See
## docs/design/systems.md, the Demonology / Contract System section.
##
## Unlike BrewJob/GrowPlotInstance, a writ's timer is not a Clock timestamp
## deadline -- it only advances while is_working is true (the player standing
## at the book, per Demonology.set_working()), so minutes_elapsed/
## minutes_required is an accumulator Demonology increments on each engaged
## minute_tick rather than something compared against Clock.get_timestamp().

enum Status { WRITING, REVISING }

var book_id: String
var status: Status = Status.WRITING
var is_working: bool = false
var minutes_elapsed: int = 0
var minutes_required: int = 0
var quality: float = 0.0
var revisions_completed: int = 0


func progress_fraction() -> float:
	return clampf(float(minutes_elapsed) / float(minutes_required), 0.0, 1.0) if minutes_required > 0 else 0.0


func can_submit() -> bool:
	return status == Status.REVISING
