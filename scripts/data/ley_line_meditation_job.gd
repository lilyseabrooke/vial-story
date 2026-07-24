class_name LeyLineMeditationJob
extends RefCounted
## A Ley Line Node's meditation bar in progress. See docs/design/systems.md,
## the Ley Line Node System section.
##
## Player-tethered like DragonStashJob -- minutes_elapsed only advances while
## the player is standing at the node, and RoomBuilder erases the whole job on
## player_exited rather than pausing it. Unlike a Dragon's Stash, a node isn't
## single-use: drawing "none" or failing the DC check against the rolled
## Surge just resets minutes_elapsed back to 0 (see LeyLines._on_minute_tick())
## instead of ending the job, so the player keeps meditating at the same node
## until a Surge is rolled and its check succeeds.

var node_id: String
var minutes_elapsed: int = 0
var minutes_required: int = 0
## Parallel arrays copied from LeyLineNodeInteractable at start_meditation()
## time -- this particular node's configured Surge odds, e.g. surge_ids[i] has
## a surge_weights[i] chance of being rolled once the bar fills.
var surge_ids: Array[String] = []
var surge_weights: Array[float] = []


func progress_fraction() -> float:
	return clampf(float(minutes_elapsed) / float(minutes_required), 0.0, 1.0) if minutes_required > 0 else 0.0
