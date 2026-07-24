class_name PantryInstance
extends RefCounted
## Runtime ingredient-storage container linked to an Alchemy Lab Manager. See
## docs/design/systems.md, system 4. Mirrors StationInstance's purchase shape
## (cost/purchased) so AlchemyLabMenu can treat both kinds uniformly.

var id: String
var display_name: String

## Materials to purchase at the linked Alchemy Lab Manager (0 = already owned).
var cost: int = 0
var purchased: bool = true

## The linked Alchemy Lab Manager's target_id -- resolved once as RoomBuilder
## wires this Pantry's node, so Brewing can find every Pantry sharing an
## Alembic's manager without any scene-graph lookups at brew time.
var lab_manager_id: String = ""

var stored_ingredients: Dictionary = {}   # ingredient_id -> int
