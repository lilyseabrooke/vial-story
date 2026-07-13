class_name UpgradeDef
extends Resource
## Static definition of a purchasable upgrade. See docs/design/systems.md, system 10.
##
## effect_target is a string key the Economy autoload matches against to apply
## the effect — keeps upgrades data-driven without a resource subclass per effect.

@export var id: String
@export var display_name: String
@export var cost: int = 0
@export var effect_target: String = ""   # e.g. "shop_capacity", "station_potency", "station_ease", "station_speed"
@export var effect_amount: float = 0.0
