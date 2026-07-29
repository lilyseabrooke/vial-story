class_name TetheredJobBase
extends RefCounted
## Shared shape for a player-tethered accumulator job: `minutes_elapsed` only
## advances while the player is standing at the interactable (as opposed to
## TimedJobBase's Clock-timestamp deadline, which advances regardless of
## whether anyone is watching). Owning autoloads/interactables decide what
## happens when the player walks away -- WritJob pauses and resumes,
## DragonStashJob/LeyLineMeditationJob erase the job outright, ScrapHeapJob
## doesn't apply since digging is a single uninterrupted sit -- this base only
## owns the progress arithmetic that was previously copy-pasted per system.

var minutes_elapsed: int = 0
var minutes_required: int = 0


func progress_fraction() -> float:
	return clampf(float(minutes_elapsed) / float(minutes_required), 0.0, 1.0) if minutes_required > 0 else 0.0
