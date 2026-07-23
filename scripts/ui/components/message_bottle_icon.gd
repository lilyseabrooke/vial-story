class_name MessageBottleIcon
extends Control
## The collapsed-state icon for the message wall — a little mauve potion flask,
## drawn in code so it needs no art and reads at any resolution. Replaces the
## old "💬" emoji Label (which the body font can't render). A hand-drawn bottle
## can replace this later by swapping in a TextureRect.

func _draw() -> void:
	var w := size.x
	var h := size.y
	var c := Vector2(w * 0.5, h * 0.64)
	var r := w * 0.26

	# Flask body full of mauve potion.
	draw_circle(c, r, UiPalette.MAUVE_POTION)
	draw_arc(c, r, 0.0, TAU, 24, UiPalette.WARM_WALNUT, 1.5, true)
	# A soft highlight.
	draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.28, Color(UiPalette.LAVENDER_MIST.r, UiPalette.LAVENDER_MIST.g, UiPalette.LAVENDER_MIST.b, 0.7))
	# Neck + cork.
	draw_rect(Rect2(w * 0.44, h * 0.30, w * 0.12, h * 0.16), UiPalette.LAVENDER_MIST)
	draw_rect(Rect2(w * 0.44, h * 0.30, w * 0.12, h * 0.16), UiPalette.WARM_WALNUT, false, 1.0)
	draw_rect(Rect2(w * 0.42, h * 0.20, w * 0.16, h * 0.11), UiPalette.HONEY_OAK)
	draw_rect(Rect2(w * 0.42, h * 0.20, w * 0.16, h * 0.11), UiPalette.WARM_WALNUT, false, 1.0)
