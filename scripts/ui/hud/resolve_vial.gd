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


## Shadows are cast from _icon/_gauge individually, not from this whole
## Control -- ResolveVial's own rect (custom_minimum_size 48x140, see
## ResolveVial.tscn) is a layout bounding box sized to fit the icon *and* the
## full vial column beneath it, well beyond the narrow bar's actual pixels.
## UiFx.add_drop_shadow mirrors whatever Control it's given, casting its
## StyleBoxFlat shadow around that Control's rect -- every other caller
## targets an actual filled panel where rect == visible shape, but here that
## produced a huge rectangular halo around mostly-empty space instead of a
## shadow hugging the circle/bar. corner_radius_px on the icon's shadow is
## half its 48px size, approximating the circle rather than the default
## square-ish rounding.
func _ready() -> void:
	# The icon's shadow is moved to index 0 -- behind the gauge as well as
	# behind the icon itself (add_drop_shadow's default placement) -- so the
	# gauge bar draws over it where they overlap instead of the shadow
	# darkening the top of the bar. Reads as the bar emerging from the icon
	# rather than the icon casting a shadow across it.
	#
	# size_px is kept small relative to offset on purpose -- StyleBoxFlat's
	# shadow blurs outward in every direction from the (offset) shape, so a
	# size_px comparable to or larger than the offset still bleeds out on the
	# top/left edges too, reading as an all-around halo instead of a shadow
	# cast in one direction. A tight blur pushed well down-right stays mostly
	# hidden behind the icon/gauge's own opaque shape on the top-left side,
	# only showing where it actually extends past the source's silhouette.
	var icon_shadow := UiFx.add_drop_shadow(_icon, 0.4, 1, Vector2(2, 2), 24)
	move_child(icon_shadow, 0)
	# corner_radius_px 0 -- the default (10) rounded the shadow's bottom
	# corners while the gauge's own texture is square-edged, so the shadow's
	# curve peeked out past the bar's straight sides.
	UiFx.add_drop_shadow(_gauge, 0.4, 1, Vector2(1, 1), 0)


func set_values(current: int, max_resolve: int, strained: bool) -> void:
	var fraction := float(current) / float(max_resolve) if max_resolve > 0 else 0.0
	_gauge.set_size_scale(_size_scale_for(max_resolve))
	_gauge.position.x = (_icon.size.x - _gauge.size.x) / 2.0
	_gauge.set_values(fraction, strained)
	tooltip_text = "%d/%d%s" % [current, max_resolve, "  (strained)" if strained else ""]


func _size_scale_for(max_resolve: int) -> float:
	return clampf(sqrt(float(max_resolve) / Resolve.BASE_MAX_RESOLVE), 1.0, _MAX_SIZE_SCALE)
