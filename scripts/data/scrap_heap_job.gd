class_name ScrapHeapJob
extends RefCounted
## A Scrap Heap dig in progress. See docs/design/systems.md, the
## Transmutation / Workbench System section (Scrap Heap).
##
## Player-tethered like DragonStashJob -- minutes_elapsed only advances while
## the player stands at the heap, and walking away erases the whole job
## rather than pausing it, so there's no is_working field.

var heap_id: String
var minutes_elapsed: int = 0
var minutes_required: int = 0
var quality: float = 0.0


func progress_fraction() -> float:
	return clampf(float(minutes_elapsed) / float(minutes_required), 0.0, 1.0) if minutes_required > 0 else 0.0
