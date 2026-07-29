class_name NotificationFeed
extends Control
## Top-center feed of generic notifications -- level-ups, quest completion,
## Resolve strain/collapse, and every other event that used to be
## console-only via hud.gd's log_message(). Generalizes ItemToastFeed's
## ingredient-gained-only toasts (scripts/ui/components/item_toast_feed.gd):
## each push spawns its own NotificationToast row that fades/frees on its own
## timer; unlike ItemToastFeed these never merge, since a generic text
## notification has no natural "same item" identity to stack on. See
## docs/engine_roadmap.md, Phase 8.

const FEED_SIZE := Vector2(360, 300)
const TOAST_SCENE := preload("res://scenes/ui/components/NotificationToast.tscn")


func show_notification(text: String, icon: Texture2D, tint: Color) -> void:
	var toast: NotificationToast = TOAST_SCENE.instantiate()
	toast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	$VBox.add_child(toast)
	toast.populate(text, icon, tint)
