class_name GrowPlotInstance
extends RefCounted
## Runtime grow plot. See docs/design/systems.md, system 7.

enum Status { EMPTY, GROWING, READY_TO_HARVEST }

var id: String
var status: Status = Status.EMPTY
var planted_seed: SeedDef = null
var planted_timestamp: int = 0
var ready_timestamp: int = 0

## Cost to buy this plot at its linked Garden Manager (0 = already available).
## `purchased` is the Garden Manager's purchase state for this plot -- see
## Herbalism.register_plot()/purchase_plot(). `lab_manager_id` is the linked
## Garden Manager's own target_id, resolved once as RoomBuilder wires this
## plot's node -- lets Herbalism find every Water Pump sharing this plot's
## manager (Herbalism._linked_water_pumps()) without a scene-graph lookup at
## harvest time.
var display_name: String = ""
var cost: int = 0
var purchased: bool = true
var lab_manager_id: String = ""
