class_name RelationshipRow
extends HBoxContainer
## One character's portrait/name/hearts row in GameMenu's Relationships tab.
##
## Node refs are looked up on demand rather than cached via @onready: see
## the note in item_slot.gd — GameMenu builds its tab tree detached from the
## SceneTree, so @onready would never fire here.

func populate(display_name: String, hearts: int, max_hearts: int, tint: Color, portrait: Texture2D = null) -> void:
	var name_label: Label = $NameLabel
	name_label.text = display_name
	name_label.add_theme_color_override("font_color", tint)

	var hearts_label: Label = $HeartsLabel
	hearts_label.text = "♥".repeat(hearts) + "♡".repeat(max_hearts - hearts)
	hearts_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.4))

	var portrait_rect: TextureRect = $Portrait
	portrait_rect.texture = portrait

	var border: ColorRect = $Portrait/Border
	border.visible = portrait == null
	border.color = tint
