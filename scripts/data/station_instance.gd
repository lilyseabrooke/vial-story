class_name StationInstance
extends RefCounted
## Runtime brewing station. See docs/design/systems.md, system 4.

var id: String
var display_name: String
var station_type: String
var potency_modifier: float = 0.0
var ease_modifier: float = 0.0
var speed_modifier: float = 1.0
var current_job: BrewJob = null

## Cost to buy this station at its linked Alchemy Lab Manager (0 = already
## available). `purchased`/`upgrade_ids` are the Alchemy Lab Manager's
## purchase/upgrade state for this station — see Brewing.register_station()/
## purchase_station()/purchase_alembic_upgrade().
var cost: int = 0
var purchased: bool = true
var upgrade_ids: Array[String] = []

## The linked Alchemy Lab Manager's target_id -- resolved once as RoomBuilder
## wires this station's node. Lets Brewing find every Pantry sharing this
## station's manager (Brewing._linked_pantries()) without a scene-graph
## lookup at brew time.
var lab_manager_id: String = ""
