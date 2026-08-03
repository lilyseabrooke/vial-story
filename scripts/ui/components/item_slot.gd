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

const BADGE_OUTLINE_SIZE := 6

## Matches the .tscn's custom_minimum_size, pinned here to a fixed real
## screen-pixel size the same way the inner Icon is (PixelPerfectSize) — the
## Icon lives under Overlay, a plain Control (not a Container), which doesn't
## propagate a child's growing minimum size upward the way a real Container
## would. Without also pinning the slot itself, the panel just kept shrinking
## with the window and the pinned Icon overflowed its shrunken bounds.
const NATIVE_SIZE := Vector2(72, 72)


func _ready() -> void:
	WindowScale.pin_size(self, NATIVE_SIZE)

## Shop-tab display: icon only, price as a corner badge, and the potion name
## surfaced via hover tooltip — the same icon-first pattern as populate_item()
## below (used by the Satchel), so the two grids read consistently.
func populate(item_name: String, price: int, tint: Color, icon: Texture2D = null) -> void:
	modulate = Color(1, 1, 1, 1)
	var name_label: Label = $Overlay/VBox/NameLabel
	name_label.visible = false
	name_label.text = ""
	var badge: Label = $Overlay/QuantityBadge
	badge.visible = true
	badge.text = "%d" % price
	badge.add_theme_color_override("font_color", UiPalette.CREAM_PAGE)
	badge.add_theme_color_override("font_outline_color", UiPalette.COCOA_INK)
	badge.add_theme_constant_override("outline_size", BADGE_OUTLINE_SIZE)
	tooltip_text = ItemTooltip.compose(item_name, "", "%d Materials" % price)
	_apply_icon(tint, icon)


## Inventory-tab display: icon only, quantity as a corner badge, and the rest
## (name/quality/type) surfaced via native hover tooltip instead of always-on
## text, so a full satchel grid stays readable at a glance. `zero_as_plus`
## shows "+" instead of "0" -- used by Build Mode's shelf, where a slot always
## exists for every unlocked ComponentDef even when the player owns none of
## it yet, and "+" reads as "buy one" rather than "you have zero."
func populate_item(item_name: String, quality_label: String, type_label: String, quantity: int, tint: Color, icon: Texture2D = null, description: String = "", zero_as_plus: bool = false) -> void:
	modulate = Color(1, 1, 1, 1)
	var name_label: Label = $Overlay/VBox/NameLabel
	name_label.visible = false
	name_label.text = ""
	var badge: Label = $Overlay/QuantityBadge
	badge.visible = true
	badge.text = "+" if (zero_as_plus and quantity <= 0) else "%d" % quantity
	badge.add_theme_color_override("font_color", UiPalette.CREAM_PAGE)
	badge.add_theme_color_override("font_outline_color", UiPalette.COCOA_INK)
	badge.add_theme_constant_override("outline_size", BADGE_OUTLINE_SIZE)
	tooltip_text = ItemTooltip.compose(item_name, quality_label, type_label, description)
	_apply_icon(tint, icon)


func clear() -> void:
	modulate = Color(1, 1, 1, 0.35)
	tooltip_text = ""
	var name_label: Label = $Overlay/VBox/NameLabel
	name_label.visible = true
	name_label.text = ""
	var badge: Label = $Overlay/QuantityBadge
	badge.visible = false
	_apply_icon(Color.WHITE, null)


func _apply_icon(tint: Color, icon: Texture2D) -> void:
	var icon_rect: TextureRect = $Overlay/VBox/Icon
	var fallback_dot: Label = $Overlay/VBox/FallbackDot
	if icon != null:
		icon_rect.texture = icon
		icon_rect.visible = true
		fallback_dot.visible = false
	else:
		icon_rect.texture = null
		icon_rect.visible = false
		fallback_dot.visible = true
		fallback_dot.add_theme_color_override("font_color", tint)
