class_name TimedJobBase
extends RefCounted
## Shared shape for a Clock-timestamp-deadline job: work that starts now and
## becomes due at a fixed future timestamp regardless of whether the player
## is present to watch it (BrewJob, GrowPlotInstance, PlanarRiftJob). See
## TetheredJobBase for the player-tethered accumulator alternative, where
## progress only advances while the player is standing at the interactable.
## Owning autoloads keep their own Status enum and roll/yield logic on top of
## this pair of fields; this base only owns the deadline arithmetic that was
## previously copy-pasted per system.

var start_timestamp: int = 0
var ready_timestamp: int = 0


## True once `timestamp` has reached the deadline. Autoloads' `_on_minute_tick`
## loops use this instead of a raw `timestamp >= job.ready_timestamp` compare.
func is_due(timestamp: int) -> bool:
	return timestamp >= ready_timestamp


func progress_fraction(now: int) -> float:
	var total := float(ready_timestamp - start_timestamp)
	return clampf(float(now - start_timestamp) / total, 0.0, 1.0) if total > 0.0 else 1.0
