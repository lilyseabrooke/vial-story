class_name WaterPumpInstance
extends RefCounted
## Runtime Water Pump. See docs/design/systems.md, system 7.

var id: String
var display_name: String

## Cost to buy this pump at its linked Garden Manager (0 = already
## available). `purchased`/`upgrade_ids` are the Garden Manager's
## purchase/upgrade state for this pump -- see Herbalism.register_water_pump()/
## purchase_water_pump()/purchase_water_pump_upgrade().
var cost: int = 0
var purchased: bool = true
var upgrade_ids: Array[String] = []

## The linked Garden Manager's target_id -- resolved once as RoomBuilder
## wires this pump's node. Lets Herbalism find every Grow Plot sharing this
## pump's manager (Herbalism._linked_water_pumps()) without a scene-graph
## lookup at harvest time.
var lab_manager_id: String = ""
