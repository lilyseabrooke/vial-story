extends Node
## Small generic broadcast bus for "something happened in the shop" flavor
## events. Autoloaded as "ShopEvents". See docs/design/systems.md, system 5.
##
## Deliberately minimal — a single untyped signal rather than one signal per
## event type — so any future system (a curse, a price change, a customer
## reaction) can broadcast without this file growing a new signal per source.
## Nothing consumes event_occurred yet beyond the two forwards Shop wires up
## at boot; this exists so CustomerInteractable and friends have somewhere to
## subscribe once they grow real reactions.

signal event_occurred(event: Dictionary)


func emit_event(type: String, payload: Dictionary = {}) -> void:
	payload["type"] = type
	event_occurred.emit(payload)
