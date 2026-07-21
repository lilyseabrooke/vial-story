class_name AttemptPuzzlePanel
extends VBoxContainer
## Drag-and-drop content hosted by MenuScene when the player tries to
## discover a recipe they haven't learned yet (Alchemy.attempt_puzzle). One
## instance owned by hud.gd, reused across attempts via show_for() the same
## way DiceRollPopup is a single reused instance rather than rebuilt per use.
##
## Three-column layout: a pinned note (top-left, the recipe's objectives,
## with a live ✓ against each one already satisfied by the current field) —
## the potion field (middle, one PotionRoleSlot per Base/Binder/Catalyst,
## visually reinforcing that Base is required via its accent border) — the
## player's ingredients (right, IngredientDragChip rows grouped by role, the
## drag source). Built as a plain code-built VBoxContainer (not a
## components/*.tscn scene) — this is a whole menu-scene content panel, not
## a repeated row, same as brew_panel/supply_panel in hud.gd.

const POTION_ROLE_SLOT_SCENE := preload("res://scenes/ui/components/PotionRoleSlot.tscn")
const INGREDIENT_DRAG_CHIP_SCENE := preload("res://scenes/ui/components/IngredientDragChip.tscn")

const ROLE_ORDER := [IngredientDef.Role.BASE, IngredientDef.Role.BINDER, IngredientDef.Role.CATALYST]

var _recipe: RecipeDef

var _note_label: Label
var _summary_label: Label
var _submit_button: Button
var _result_label: Label

var _slots_by_role: Dictionary = {}             # IngredientDef.Role -> PotionRoleSlot
var _ingredient_lists_by_role: Dictionary = {}  # IngredientDef.Role -> VBoxContainer


func build() -> void:
	custom_minimum_size = Vector2(760, 0)

	var main_row := HBoxContainer.new()
	add_child(main_row)

	main_row.add_child(_build_note_column())
	main_row.add_child(_build_field_column())
	main_row.add_child(_build_ingredients_column())

	add_child(HSeparator.new())

	_submit_button = Button.new()
	_submit_button.text = "Attempt (consumes selected ingredients)"
	_submit_button.pressed.connect(_on_submit_pressed)
	add_child(_submit_button)

	_result_label = Label.new()
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_result_label)


## Called each time the player opens this panel for a specific recipe —
## clears the field and rebuilds the ingredient lists from current
## inventory, since owned quantities can have changed since the last attempt.
func show_for(recipe: RecipeDef) -> void:
	_recipe = recipe
	_result_label.text = ""
	for role in ROLE_ORDER:
		(_slots_by_role[role] as PotionRoleSlot).clear()
	_refresh_ingredient_lists()
	_refresh_feedback()


# ---------------------------------------------------------------------------
# Column builders
# ---------------------------------------------------------------------------

func _build_note_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(200, 0)
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var note_panel := PanelContainer.new()
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = Color(0.93, 0.88, 0.7)
	stylebox.set_corner_radius_all(2)
	stylebox.set_content_margin_all(10)
	note_panel.add_theme_stylebox_override("panel", stylebox)
	note_panel.rotation_degrees = -2.0
	column.add_child(note_panel)

	_note_label = Label.new()
	_note_label.add_theme_color_override("font_color", Color(0.15, 0.1, 0.05))
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_note_label.custom_minimum_size = Vector2(180, 0)
	note_panel.add_child(_note_label)

	return column


func _build_field_column() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var field_title := Label.new()
	field_title.text = "The Potion"
	field_title.add_theme_font_size_override("font_size", 16)
	field_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(field_title)

	var hint := Label.new()
	hint.text = "Uses 2–3 ingredients and always needs a Base."
	hint.modulate = Color(0.6, 0.6, 0.6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)

	var slots_row := HBoxContainer.new()
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(slots_row)

	for role in ROLE_ORDER:
		var slot: PotionRoleSlot = POTION_ROLE_SLOT_SCENE.instantiate()
		slots_row.add_child(slot)
		slot.setup(role, role == IngredientDef.Role.BASE)
		slot.content_changed.connect(_refresh_feedback)
		_slots_by_role[role] = slot

	column.add_child(HSeparator.new())

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_summary_label)

	return column


func _build_ingredients_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(260, 0)

	var title := Label.new()
	title.text = "Your Ingredients"
	title.add_theme_font_size_override("font_size", 16)
	column.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	column.add_child(scroll)

	var scroll_body := VBoxContainer.new()
	scroll_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_body)

	for role in ROLE_ORDER:
		var role_header := Label.new()
		role_header.text = IngredientDef.Role.keys()[role].capitalize()
		role_header.add_theme_font_size_override("font_size", 13)
		scroll_body.add_child(role_header)

		var list := VBoxContainer.new()
		scroll_body.add_child(list)
		_ingredient_lists_by_role[role] = list

		scroll_body.add_child(HSeparator.new())

	return column


# ---------------------------------------------------------------------------
# Refresh / feedback
# ---------------------------------------------------------------------------

func _refresh_ingredient_lists() -> void:
	for role in ROLE_ORDER:
		var list: VBoxContainer = _ingredient_lists_by_role[role]
		for child in list.get_children():
			child.queue_free()

		var any := false
		for ingredient in ContentRegistry.ingredients:
			if ingredient.role != role:
				continue
			var owned := Inventory.ingredient_count(ingredient.id)
			if owned <= 0:
				continue
			any = true
			var chip: IngredientDragChip = INGREDIENT_DRAG_CHIP_SCENE.instantiate()
			list.add_child(chip)
			chip.populate(ingredient, owned)

		if not any:
			var empty_label := Label.new()
			empty_label.text = "(none owned)"
			empty_label.modulate = Color(0.6, 0.6, 0.6)
			list.add_child(empty_label)


## Re-derives everything that depends on the field's current contents: the
## note's per-objective ✓ markers, the weight/count summary, and whether
## Submit is enabled — called on every slot change plus once from show_for().
func _refresh_feedback() -> void:
	if _recipe == null:
		return

	var ids := _current_ingredient_ids()
	var results := Alchemy.check_constraints(_recipe, ids)

	var lines: Array[String] = []
	for i in _recipe.puzzle_constraint_types.size():
		var satisfied := i < results.size() and results[i]
		lines.append("%s %s" % ["✓" if satisfied else "•", _recipe.describe_puzzle_constraint(i)])
	_note_label.text = "%s\n\n%s" % [_recipe.display_name, "\n".join(lines)]

	_summary_label.text = _build_summary_text(ids)
	_submit_button.disabled = not _selection_is_valid(ids)


func _build_summary_text(ids: Array[String]) -> String:
	if ids.is_empty():
		return "Drag ingredients into the field to assemble a potion."

	var total_weight := 0.0
	for id in ids:
		var ingredient := ContentRegistry.get_ingredient(id)
		if ingredient != null:
			total_weight += ingredient.weight
	return "%d ingredient(s) — total weight %.1f" % [ids.size(), total_weight]


func _current_ingredient_ids() -> Array[String]:
	var ids: Array[String] = []
	for role in ROLE_ORDER:
		var slot: PotionRoleSlot = _slots_by_role[role]
		if slot.is_filled():
			ids.append(slot.get_ingredient_id())
	return ids


## A base slot is mandatory and at least one of binder/catalyst must also be
## filled — the 2-or-3-ingredients, always-a-base rule, enforced here (and
## visually via the base slot's accent border) rather than left to the
## puzzle constraints to catch.
func _selection_is_valid(ids: Array[String]) -> bool:
	var base_slot: PotionRoleSlot = _slots_by_role[IngredientDef.Role.BASE]
	var binder_slot: PotionRoleSlot = _slots_by_role[IngredientDef.Role.BINDER]
	var catalyst_slot: PotionRoleSlot = _slots_by_role[IngredientDef.Role.CATALYST]
	return base_slot.is_filled() and (binder_slot.is_filled() or catalyst_slot.is_filled()) and ids.size() >= 2


# ---------------------------------------------------------------------------
# Submit
# ---------------------------------------------------------------------------

func _on_submit_pressed() -> void:
	var ids := _current_ingredient_ids()
	if not _selection_is_valid(ids):
		_result_label.text = "Add a Base, plus a Binder and/or Catalyst."
		return

	for id in ids:
		Inventory.consume_ingredient(id, 1)

	var success := Alchemy.attempt_puzzle(_recipe, ids)
	_result_label.text = "Success! You learned %s." % _recipe.display_name if success \
		else "The mixture didn't work — %s wasn't learned. Ingredients were consumed." % _recipe.display_name

	for role in ROLE_ORDER:
		(_slots_by_role[role] as PotionRoleSlot).clear()
	_refresh_ingredient_lists()
