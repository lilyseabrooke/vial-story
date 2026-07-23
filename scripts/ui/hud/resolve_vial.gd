class_name ResolveVial
extends Control
## Top-left HUD element: the Resolve meter as a filling potion vial peeking
## out from underneath a character profile icon (currently CircleMarker, a
## flat-color placeholder — swap for a real portrait later). No frame, no
## always-visible label; the current/max numbers only show via the native
## tooltip on hover. Node layout lives in ResolveVial.tscn/VialGauge.tscn —
## this script pushes values in and keeps the vial horizontally centered
## under the icon as it grows. update_resolve_meter() in hud.gd calls
## set_values() the same way it used to set bar.value.
##
## The vial physically grows as max_resolve climbs above Resolve.BASE_MAX_
## RESOLVE, so it visibly reflects character growth regardless of which
## system (upgrade, skill, event) raised the cap. Growth uses a sqrt curve
## rather than linear so a doubled max_resolve doesn't double the HUD
## footprint — diminishing returns, clamped so it can't outgrow the icon
## it's anchored under.

const _MAX_SIZE_SCALE := 2.0

@onready var _gauge: VialGauge = $Gauge
@onready var _icon: Control = $ProfileIcon


func set_values(current: int, max_resolve: int, strained: bool) -> void:
	var fraction := float(current) / float(max_resolve) if max_resolve > 0 else 0.0
	_gauge.set_size_scale(_size_scale_for(max_resolve))
	_gauge.position.x = (_icon.size.x - _gauge.size.x) / 2.0
	_gauge.set_values(fraction, strained)
	tooltip_text = "%d/%d%s" % [current, max_resolve, "  (strained)" if strained else ""]


func _size_scale_for(max_resolve: int) -> float:
	return clampf(sqrt(float(max_resolve) / Resolve.BASE_MAX_RESOLVE), 1.0, _MAX_SIZE_SCALE)
