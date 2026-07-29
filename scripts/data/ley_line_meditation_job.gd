class_name LeyLineMeditationJob
extends TetheredJobBase
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
## Parallel arrays copied from LeyLineNodeInteractable at start_meditation()
## time -- this particular node's configured Surge odds, e.g. surge_ids[i] has
## a surge_weights[i] chance of being rolled once the bar fills.
var surge_ids: Array[String] = []
var surge_weights: Array[float] = []
