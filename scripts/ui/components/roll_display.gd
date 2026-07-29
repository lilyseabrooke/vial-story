class_name RollDisplay
extends Control
## Bottom-right roll callout that replaced the old MessageWall scrollback.
## Playtesting showed only two things actually landed for players: getting an
## item/material, and a dice check resolving -- and those two deserved
## different treatment (item/material toasts are a separate system, tracked
## for later; see docs/design/systems.md system 16). This is the roll half:
## a single graphical readout of the *most recent* roll only. A new roll
## replaces whatever's showing immediately (no queue, no history here -- an
## extended roll log belongs in the Escape menu later, also out of scope for
## now) and the callout auto-hides itself a few seconds after the last roll,
## same "don't linger, don't demand a click" feel MessageEntry rows had.
##
## Settled shape after three playtesting passes: which skill (an icon, see
## roll_skill_icon.gd, standing in for the full skill name) plus the two dice
## (roll_die_gem.gd, colored green/red on a natural 10/1), the modifier, and
## the total on the first line; the DC on a second line, inline with a row of
## pips (roll_pip_gauge.gd) -- green filling in for degrees of success, red
## for degrees of failure -- so the number the pips are measuring against sits
## right next to them. No pass/fail wording anywhere; the pip color already
## carries that.
##
## Built as a .tscn (scenes/ui/components/RollDisplay.tscn) for the same
## reason MessageWall was: bottom-right anchor placement fights Control's
## anchor/offset/position/size setter order when done in code, but is trivial
## to get right once in the scene's own anchor/offset values. Everything
## inside the anchored box is still built in code in _ready(), same as
## AlmanacClock/MaterialsPouch.
##
## The show/hide pop animates `_card` (a child), not this root Control --
## hud.gd permanently owns this root's own scale/pivot (matching the 2x
## world-camera zoom, same as MessageWall before it), so an internal
## animation must never touch them. hud.gd sets that pivot to CARD_SIZE
## itself (this box's own bottom-right corner) rather than half of it -- a
## previous half-size pivot bug was what let the doubled card overshoot past
## the screen's bottom-right corner despite the box itself being placed
## correctly.

const POP_IN_SECONDS := 0.22
const SETTLE_SECONDS := 0.12
const LINGER_SECONDS := 3.4
const FADE_OUT_SECONDS := 0.5
const CARD_SIZE := Vector2(340, 120)
const ICON_SIZE := Vector2(36, 36)
const PIP_GAUGE_SIZE := Vector2(60, 12)

var _card: PanelContainer
var _skill_icon: RollSkillIcon
var _die_a: RollDieGem
var _die_b: RollDieGem
var _modifier_label: Label
var _total_label: Label
var _dc_label: Label
var _pip_gauge: RollPipGauge
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0

	_card = PanelContainer.new()
	_card.theme_type_variation = &"SmallFramedPanel"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.pivot_offset = CARD_SIZE * 0.5
	add_child(_card)
	UiFx.add_drop_shadow(self, 0.4, 8, Vector2(0, 5))

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	_card.add_child(vbox)

	# Line 1: skill icon, dice, modifier, total.
	var roll_row := HBoxContainer.new()
	roll_row.alignment = BoxContainer.ALIGNMENT_CENTER
	roll_row.add_theme_constant_override("separation", 8)
	vbox.add_child(roll_row)

	_skill_icon = RollSkillIcon.new()
	_skill_icon.custom_minimum_size = ICON_SIZE
	roll_row.add_child(_skill_icon)

	_die_a = RollDieGem.new()
	_die_a.custom_minimum_size = ICON_SIZE
	roll_row.add_child(_die_a)

	_die_b = RollDieGem.new()
	_die_b.custom_minimum_size = ICON_SIZE
	roll_row.add_child(_die_b)

	_modifier_label = Label.new()
	_modifier_label.theme_type_variation = &"CaptionLabel"
	_modifier_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	roll_row.add_child(_modifier_label)

	var equals_label := Label.new()
	equals_label.text = "="
	equals_label.theme_type_variation = &"CaptionLabel"
	equals_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	roll_row.add_child(equals_label)

	_total_label = Label.new()
	_total_label.theme_type_variation = &"NumericLabel"
	_total_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	roll_row.add_child(_total_label)

	# Line 2: DC, inline with the pip gauge it's measured against.
	var dc_row := HBoxContainer.new()
	dc_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dc_row.add_theme_constant_override("separation", 8)
	vbox.add_child(dc_row)

	_dc_label = Label.new()
	_dc_label.theme_type_variation = &"CaptionLabel"
	_dc_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dc_row.add_child(_dc_label)

	_pip_gauge = RollPipGauge.new()
	_pip_gauge.custom_minimum_size = PIP_GAUGE_SIZE
	_pip_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dc_row.add_child(_pip_gauge)


## skill_id: a Skills id (e.g. "alchemy", "demonology") -- resolved to a
## placeholder icon by RollSkillIcon. Unrecognized ids fall back to "?".
func show_roll(roll: Dictionary, skill_id: String) -> void:
	_skill_icon.set_skill(skill_id)
	_die_a.set_value(roll.die_a)
	_die_b.set_value(roll.die_b)
	_modifier_label.text = "%+.1f" % roll.modifier
	_total_label.text = "%.1f" % roll.total
	_dc_label.text = "DC %.1f" % roll.dc
	_pip_gauge.set_degrees(roll.get("degrees_of_success", 0), roll.get("degrees_of_failure", 0))

	_play_show_then_hide()


func _play_show_then_hide() -> void:
	if _tween:
		_tween.kill()
	visible = true
	modulate.a = 0.0
	_card.scale = Vector2(0.85, 0.85)

	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, POP_IN_SECONDS)
	_tween.parallel().tween_property(_card, "scale", Vector2(1.05, 1.05), POP_IN_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_card, "scale", Vector2.ONE, SETTLE_SECONDS)
	_tween.tween_interval(LINGER_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_SECONDS)
	_tween.tween_callback(func() -> void: visible = false)
