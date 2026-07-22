class_name PlanarRiftJob
extends RefCounted
## A Planar Rift summon in progress. See docs/design/systems.md, the
## Summoning / Planar Rift System section.
##
## Deadline-based like BrewJob/GrowPlotInstance rather than tethered like
## WritJob/DragonStashJob -- a summon can run for anywhere from minutes to
## multiple days, so it has to keep advancing while the player is off doing
## something else entirely, not just while they stand at the rift.

enum Status { SUMMONING, READY }

var rift_id: String
var bundle_id: String
var start_timestamp: int
var ready_timestamp: int
var status: Status = Status.SUMMONING
## 0..1 quality locked in when the minigame's sequence completed (built from
## time remaining + a Summoning roll). Scales/gates the bundle's rewards at
## collection -- see RiftBundleDef and Summoning.collect_rift().
var quality: float = 0.0


func progress_fraction(now: int) -> float:
	var total := float(ready_timestamp - start_timestamp)
	return clampf(float(now - start_timestamp) / total, 0.0, 1.0) if total > 0.0 else 1.0
