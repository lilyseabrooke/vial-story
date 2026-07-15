class_name RecipeEntry
extends VBoxContainer
## One recipe's header/ingredients block in GameMenu's Recipes tab.
##
## Node refs are looked up on demand rather than cached via @onready: see
## the note in item_slot.gd — GameMenu builds its tab tree detached from the
## SceneTree, so @onready would never fire here.

func populate(display_name: String, known: bool, ingredients_text: String, icon: Texture2D = null) -> void:
	modulate = Color(1, 1, 1, 1) if known else Color(0.6, 0.6, 0.6, 1)

	var header_label: Label = $HeaderRow/HeaderLabel
	header_label.text = display_name if known else "??? (unknown)"

	var ingredients_label: Label = $IngredientsLabel
	ingredients_label.visible = known
	ingredients_label.text = "Requires: %s" % ingredients_text

	var icon_rect: TextureRect = $HeaderRow/Icon
	icon_rect.texture = icon
	icon_rect.visible = icon != null
