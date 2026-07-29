class_name ScrapHeapJob
extends TetheredJobBase
## A Scrap Heap dig in progress. See docs/design/systems.md, the
## Transmutation / Workbench System section (Scrap Heap).
##
## Player-tethered like DragonStashJob -- minutes_elapsed only advances while
## the player stands at the heap, and walking away erases the whole job
## rather than pausing it, so there's no is_working field.

var heap_id: String
var quality: float = 0.0
