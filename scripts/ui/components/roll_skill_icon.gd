class_name RollSkillIcon
extends Control
## Placeholder "which skill is this check for" glyph for RollDisplay -- a
## colored circle with a two-letter initialism, standing in for real icon art
## per skill (swap set_skill()'s lookup for a Texture2D once that art exists,
## same upgrade path as IngredientDef.icon/CharacterDef.portrait). Replaces
## writing out the full skill name (e.g. "Transmutation") as a label.
##
## Colors are drawn one-for-one from UiPalette's eight non-reserved named
## colors (MAUVE_POTION stays reserved for magic/potion glow) so each skill
## reads as a distinct, stable color without inventing a second palette.

const SKILL_STYLE := {
	"alchemy": {"initials": "Al", "color": UiPalette.SAGE_LEAF},
	"focus": {"initials": "Fo", "color": UiPalette.HONEY_OAK},
	"demonology": {"initials": "De", "color": UiPalette.WARM_WALNUT},
	"draconology": {"initials": "Dr", "color": UiPalette.BLUSH_BLOSSOM},
	"arcane_history": {"initials": "Ar", "color": UiPalette.BUTTER_SUN},
	"summoning": {"initials": "Su", "color": UiPalette.LAVENDER_MIST},
	"transmutation": {"initials": "Tr", "color": UiPalette.MORNING_SKY},
	"creativity": {"initials": "Cr", "color": UiPalette.DRIFTWOOD_TAN},
}
const FALLBACK_STYLE := {"initials": "?", "color": UiPalette.CREAM_PAGE}

var _fill_color: Color = UiPalette.CREAM_PAGE
var _initials_label: Label


func _ready() -> void:
	_initials_label = Label.new()
	_initials_label.theme_type_variation = &"CaptionLabel"
	_initials_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initials_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_initials_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_initials_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_initials_label)


func set_skill(skill_id: String) -> void:
	var style: Dictionary = SKILL_STYLE.get(skill_id, FALLBACK_STYLE)
	_fill_color = style.color
	_initials_label.text = style.initials
	_initials_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	queue_redraw()


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5
	var center := size * 0.5
	draw_circle(center, radius, _fill_color)
	draw_arc(center, radius, 0.0, TAU, 24, UiPalette.WARM_WALNUT, 1.5, true)
