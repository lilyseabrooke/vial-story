class_name IngredientDragChip
extends PanelContainer
## One draggable ingredient entry in AttemptPuzzlePanel's role-filtered
## ingredient list (scripts/ui/attempt_puzzle_panel.gd) — the drag source
## side of the puzzle's drag-and-drop.
##
## Node refs are looked up on demand rather than cached via @onready, same
## convention as item_slot.gd: AttemptPuzzlePanel builds this detached from
## the SceneTree, only reparented in later by MenuScene.open().

var ingredient_id: String = ""


func populate(ingredient: IngredientDef, owned_count: int) -> void:
	ingredient_id = ingredient.id

	var name_label: Label = $VBox/NameLabel
	name_label.text = "%s  x%d" % [ingredient.display_name, owned_count]

	var detail_label: Label = $VBox/DetailLabel
	detail_label.text = "Weight %s — %s" % [_fmt_num(ingredient.weight), _traits_text(ingredient)]


func _traits_text(ingredient: IngredientDef) -> String:
	var parts: Array[String] = []
	for i in ingredient.characteristic_ids.size():
		var value: int = ingredient.characteristic_values[i]
		if value != 0:
			parts.append("%s %s%d" % [ingredient.characteristic_ids[i].capitalize(), "+" if value > 0 else "", value])
	return ", ".join(parts) if not parts.is_empty() else "no notable traits"


func _fmt_num(value: float) -> String:
	return "%d" % int(value) if is_equal_approx(value, roundf(value)) else "%.1f" % value


## Standard Control drag-and-drop pickup: PotionRoleSlot's _can_drop_data/
## _drop_data on the receiving end reads the same {"ingredient_id": ...} shape.
func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview_label := Label.new()
	preview_label.text = $VBox/NameLabel.text
	var preview_box := PanelContainer.new()
	preview_box.modulate = Color(1, 1, 1, 0.85)
	preview_box.add_child(preview_label)
	set_drag_preview(preview_box)
	return {"ingredient_id": ingredient_id}
