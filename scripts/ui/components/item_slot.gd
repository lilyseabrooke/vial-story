class_name ItemSlot
extends PanelContainer
## Icon + name + subtitle cell, shared by GameMenu's Inventory and Shop tabs.
## Replaces the old inline _build_slot() in game_menu.gd. Falls back to a
## tinted "●" glyph when no icon art exists yet for the underlying def.
##
## Node refs are looked up on demand rather than cached via @onready: GameMenu
## builds its whole tab tree once in build(), detached from the SceneTree
## (it's only parented in later, when MenuScene.open() is called), so
## @onready fields here would never fire and would stay null.

func populate(item_name: String, subtitle: String, tint: Color, icon: Texture2D = null) -> void:
	modulate = Color(1, 1, 1, 1)
	var name_label: Label = $VBox/NameLabel
	name_label.text = "%s\n%s" % [item_name, subtitle] if subtitle != "" else item_name
	_apply_icon(tint, icon)


func clear() -> void:
	modulate = Color(1, 1, 1, 0.35)
	var name_label: Label = $VBox/NameLabel
	name_label.text = ""
	_apply_icon(Color.WHITE, null)


func _apply_icon(tint: Color, icon: Texture2D) -> void:
	var icon_rect: TextureRect = $VBox/Icon
	var fallback_dot: Label = $VBox/FallbackDot
	if icon != null:
		icon_rect.texture = icon
		icon_rect.visible = true
		fallback_dot.visible = false
	else:
		icon_rect.texture = null
		icon_rect.visible = false
		fallback_dot.visible = true
		fallback_dot.add_theme_color_override("font_color", tint)
