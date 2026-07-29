class_name NotificationToast
extends PanelContainer
## One row in NotificationFeed -- a generic icon+text callout with a fade-out
## timer, the same shape as ItemToast (scripts/ui/components/item_toast.gd)
## but without ingredient-specific quantity-merging, since a generic
## notification has no natural "same item" identity to stack on -- each push
## is its own one-off row. See docs/engine_roadmap.md, Phase 8.

const VISIBLE_SECONDS := 3.0
const FADE_SECONDS := 0.5

@onready var _icon_rect: TextureRect = $HBox/Icon
@onready var _label: Label = $HBox/Label


func populate(text: String, icon: Texture2D, tint: Color) -> void:
	_label.text = text
	_icon_rect.visible = icon != null
	_icon_rect.texture = icon
	if tint != Color.WHITE:
		_label.add_theme_color_override("font_color", tint)
	_fade_out_after_delay()


func _fade_out_after_delay() -> void:
	await get_tree().create_timer(VISIBLE_SECONDS).timeout
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	await tween.finished
	queue_free()
