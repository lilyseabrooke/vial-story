class_name ItemToastFeed
extends Control
## Bottom-left feed of received-item callouts -- the other half of the
## MessageWall replacement (see roll_display.gd for the roll half). Every
## Inventory.ingredient_gained signal spawns one ItemToast row; rows stack
## from the bottom of a fixed-size box and each fades/frees itself on its own
## timer (item_toast.gd), so several gains in quick succession (e.g. a
## multi-ingredient harvest) show as a short-lived vertical stack rather than
## replacing each other the way RollDisplay's single roll slot does.
## Materials gains are a separate, not-yet-built system -- see
## docs/design/systems.md system 16 -- this only reacts to ingredient_gained.
##
## If the same ingredient arrives again while its toast is still showing
## (e.g. two harvests of the same plot type moments apart), _active_toasts
## routes the gain into that row's add_quantity() instead of spawning a
## second one -- _active_toasts is pruned via each toast's tree_exiting
## signal so a toast that already faded out never gets mistaken for "still
## showing".
##
## Built as a .tscn for the same anchor reason RollDisplay/MessageWall were:
## a fixed-size box anchored to a screen corner is trivial to get right once
## in the scene's own anchor/offset values, fights Control's setter order
## when done in code. hud.gd owns this root's scale/pivot for the 2x
## world-camera zoom (matching RollDisplay's convention exactly, mirrored to
## the opposite corner) -- pivot_offset must be FEED_SIZE with y flipped to 0,
## i.e. this box's own bottom-left corner, so the doubled feed grows up-right
## in place instead of overshooting past the screen's left edge.

const FEED_SIZE := Vector2(300, 400)
const TOAST_SCENE := preload("res://scenes/ui/components/ItemToast.tscn")

var _active_toasts: Dictionary = {}   # ingredient_id -> ItemToast


func show_item(ingredient_id: String, quantity: int, tier: int) -> void:
	var existing: ItemToast = _active_toasts.get(ingredient_id)
	if is_instance_valid(existing):
		existing.add_quantity(quantity)
		return

	var def := ContentRegistry.get_ingredient(ingredient_id)
	var display_name := def.display_name if def != null else ingredient_id
	var icon: Texture2D = def.icon if def != null else null
	var tint: Color = IngredientDef.CATEGORY_COLORS.get(def.category, UiPalette.DRIFTWOOD_TAN) if def != null else UiPalette.DRIFTWOOD_TAN
	var quality_label := IngredientQuality.label(tier)
	var type_label := ItemTooltip.ingredient_type_label(def.category) if def != null else ""

	var toast: ItemToast = TOAST_SCENE.instantiate()
	# VBoxContainer stretches children to its own (fixed FEED_SIZE) width by
	# default -- SHRINK_BEGIN keeps each toast hugging the left edge at its
	# own content width instead of stretching every card out to 300px wide.
	toast.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	$VBox.add_child(toast)
	toast.populate(ingredient_id, display_name, quality_label, type_label, quantity, tint, icon)

	_active_toasts[ingredient_id] = toast
	toast.tree_exiting.connect(func() -> void:
		if _active_toasts.get(ingredient_id) == toast:
			_active_toasts.erase(ingredient_id)
	)
