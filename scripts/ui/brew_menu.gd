class_name BrewMenu
extends VBoxContainer
## The alembic's brewing menu — the bespoke content Control handed to MenuScene
## when a station with no job is interacted with. See docs/design/systems.md,
## systems 1 (menus) and 4 (brewing).
##
## Layout is master-detail: the player's pantry runs across the top, a grouped
## and filterable list of *learned* recipes sits on the left, and a detail/
## confirm card for the selected recipe on the right. Recipes that produce the
## same potion (same `output_potion_id`) are grouped under one heading, with each
## recipe shown as a "method" variant beneath it.
##
## Fully keyboard-navigable, in two modes:
##   - Browsing (default): W/S move the highlighted selection through the list,
##     E focuses it, and a bare 1/2/3 brews whatever recipe is pinned to that
##     quick slot. Esc here isn't consumed, so it falls through to main.gd and
##     closes the menu.
##   - Focused (after E on a selection): E brews the focused recipe, 1/2/3 pin it
##     to that quick slot, and Esc steps back to browsing (consumed, so the menu
##     stays open — a second Esc, now in browsing, closes it).
## The mouse still works alongside this: clicking a row selects it, the Brew
## button brews, and the slot buttons pin. Quick slots are session-only (not
## saved) and deliberately reuse the digits that drive Clock speed in the world —
## safe because the world is paused whenever this menu is open. The digit/E/Esc
## keys are handled in `_input()` (see there) so they never fall through to
## main.gd's world hotkeys while the menu owns the screen.
##
## Built in code (like GameMenu and the HUD panels), not from a .tscn, so it can
## live detached until MenuScene.open() parents it in. It reads
## Inventory/Alchemy/ContentRegistry directly for display but never mutates —
## the actual brew is emitted as `brew_confirmed` for GameHud to run, which owns
## Brewing.start_brew() and closing the menu (mirroring how the old brew_panel
## routed through hud.on_brew_button_pressed).

signal brew_confirmed(recipe: RecipeDef)
signal notice(text: String)

const INGREDIENT_CHIP_SCENE := preload("res://scenes/ui/components/IngredientChip.tscn")
const BREW_RECIPE_ROW_SCENE := preload("res://scenes/ui/components/BrewRecipeRow.tscn")

const LIST_WIDTH := 250
const DETAIL_WIDTH := 348
const COLUMN_HEIGHT := 320
const QUICK_SLOT_COUNT := 3

# Autowrap Labels report a runaway minimum height when their width is
# unconstrained (they wrap to their longest word), so every wrapping label gets
# an explicit wrap width — the interior width of the column it lives in.
const LIST_TEXT_WIDTH := LIST_WIDTH - 48
const DETAIL_TEXT_WIDTH := DETAIL_WIDTH - 48

const BROWSE_TIP := "W / S browse recipes  ·  E to focus  ·  1 / 2 / 3 brew a saved potion  ·  Esc to close"
const FOCUS_TIP := "W / S pick an action  ·  E to use it  ·  1 / 2 / 3 save this potion  ·  Esc to step back"

var _ready_only := false
var _focused := false
var _selected_recipe: RecipeDef = null
var _quick_slots: Array[RecipeDef] = [null, null, null]
var _row_group := ButtonGroup.new()
var _visible_recipes: Array[RecipeDef] = []

# While focused, W/S move a cursor through the detail card's action buttons —
# index 0 is Brew, 1..QUICK_SLOT_COUNT are the quick-slot buttons — and E
# activates the one under the cursor. `_action_buttons` is rebuilt with the card.
var _action_index := 0
var _action_buttons: Array[Button] = []
var _highlighted_button: Button = null

var _list_scroll: ScrollContainer
var _list_vbox: VBoxContainer
var _detail_panel: PanelContainer
var _detail_vbox: VBoxContainer
var _detail_focus_ring: Panel
var _tip: Label
var _rows: Dictionary = {}   # RecipeDef -> BrewRecipeRow


func build() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(LIST_WIDTH + DETAIL_WIDTH + 28, 0)

	# --- Top bar: cozy prompt + "ready only" filter -----------------------
	var top_bar := HBoxContainer.new()
	var prompt := Label.new()
	prompt.theme_type_variation = &"SubheadingLabel"
	prompt.text = "What shall we brew today?"
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(prompt)

	var ready_check := CheckButton.new()
	ready_check.text = "Ready to brew only"
	ready_check.toggled.connect(_on_ready_only_toggled)
	top_bar.add_child(ready_check)
	add_child(top_bar)

	# --- Main row: recipe list | detail card ------------------------------
	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 12)
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main_row)

	var list_panel := PanelContainer.new()
	list_panel.theme_type_variation = &"FramedPanel"
	list_panel.custom_minimum_size = Vector2(LIST_WIDTH, COLUMN_HEIGHT)
	main_row.add_child(list_panel)

	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(_list_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.custom_minimum_size = Vector2(LIST_WIDTH - 44, 0)
	_list_vbox.add_theme_constant_override("separation", 3)
	_list_scroll.add_child(_list_vbox)

	_detail_panel = PanelContainer.new()
	_detail_panel.theme_type_variation = &"FramedPanel"
	_detail_panel.custom_minimum_size = Vector2(DETAIL_WIDTH, COLUMN_HEIGHT)
	main_row.add_child(_detail_panel)

	_detail_vbox = VBoxContainer.new()
	_detail_vbox.add_theme_constant_override("separation", 8)
	_detail_panel.add_child(_detail_vbox)

	# A magic-tinted border that overlays the detail card while a recipe is
	# focused — the clearest "you're now acting on this one" signal. A sibling of
	# the content vbox (PanelContainer fits both to its interior, so they
	# overlap); mouse-transparent and border-only so it never blocks the buttons.
	_detail_focus_ring = Panel.new()
	_detail_focus_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_focus_ring.visible = false
	var ring_style := StyleBoxFlat.new()
	ring_style.draw_center = false
	ring_style.border_color = UiPalette.MAGIC
	ring_style.set_border_width_all(2)
	ring_style.set_corner_radius_all(8)
	_detail_focus_ring.add_theme_stylebox_override("panel", ring_style)
	_detail_panel.add_child(_detail_focus_ring)

	# --- Footer hint ------------------------------------------------------
	_tip = Label.new()
	_tip.theme_type_variation = &"CaptionLabel"
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tip.custom_minimum_size = Vector2(LIST_WIDTH + DETAIL_WIDTH, 0)
	_tip.text = BROWSE_TIP
	add_child(_tip)


## Rebuilds everything from current Inventory/Alchemy state — called by GameHud
## each time the menu opens, and whenever the learned-recipe set changes.
func refresh() -> void:
	_validate_quick_slots()
	_focused = false
	_rebuild_list()
	_refresh_mode_visuals()


# --- Input --------------------------------------------------------------------

## Keyboard navigation. Handled here (and mostly marked handled) rather than in
## main.gd's `_unhandled_input`, so W/S/E/digits drive the menu instead of the
## world while it owns the screen. Guarded on `Clock.is_paused` so a stray
## keypress during the close animation (menu still in-tree, already unpaused)
## does nothing. The one key deliberately *not* consumed is Esc while browsing —
## it falls through so main.gd's toggle closes the menu. See the class docstring
## for the two-mode model.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not Clock.is_paused:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	# Captured up front so a brew that closes the menu can't leave a null
	# get_viewport() before the handled-mark — MenuScene currently defers
	# content removal past close(), but don't lean on that (see the same
	# capture in MenuKeyNav._input, where scene changes made it a real crash).
	var viewport := get_viewport()
	match event.keycode:
		KEY_W, KEY_UP:
			if _focused:
				_move_action(-1)
			else:
				_move_selection(-1)
			viewport.set_input_as_handled()
		KEY_S, KEY_DOWN:
			if _focused:
				_move_action(1)
			else:
				_move_selection(1)
			viewport.set_input_as_handled()
		KEY_A, KEY_LEFT:
			# Only meaningful (and only consumed) while focused, moving the action
			# cursor along the slot row; browsing ignores it (recipes are a column).
			if _focused:
				_move_action(-1)
				viewport.set_input_as_handled()
		KEY_D, KEY_RIGHT:
			if _focused:
				_move_action(1)
				viewport.set_input_as_handled()
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			_activate()
			viewport.set_input_as_handled()
		KEY_1, KEY_KP_1:
			_press_digit(0)
			viewport.set_input_as_handled()
		KEY_2, KEY_KP_2:
			_press_digit(1)
			viewport.set_input_as_handled()
		KEY_3, KEY_KP_3:
			_press_digit(2)
			viewport.set_input_as_handled()
		KEY_ESCAPE:
			# Only consume Esc when it has something to undo (leaving focus);
			# while browsing it falls through to main.gd, which closes the menu.
			if _focused:
				_set_focused(false)
				viewport.set_input_as_handled()


## E / Enter: focus the selection when browsing; when already focused, activate
## whichever action button the cursor is on (Brew, or a quick slot).
func _activate() -> void:
	if _selected_recipe == null:
		return
	if not _focused:
		_set_focused(true)
	elif _action_index == 0:
		_brew_selected()
	else:
		_toggle_slot(_action_index - 1, _selected_recipe)


func _brew_selected() -> void:
	if Inventory.has_ingredients_for(_selected_recipe):
		_confirm_brew(_selected_recipe)
	else:
		notice.emit("Can't brew %s yet — missing ingredients." % _potion_name(_selected_recipe.output_potion_id))


## The action buttons the focus cursor can land on, skipping a disabled Brew
## (index 0) when the recipe isn't brewable. Quick-slot buttons (1..N) are
## always enabled.
func _enabled_action_indices() -> Array[int]:
	var result: Array[int] = []
	if _selected_recipe != null and Inventory.has_ingredients_for(_selected_recipe):
		result.append(0)
	for s in QUICK_SLOT_COUNT:
		result.append(1 + s)
	return result


func _move_action(delta: int) -> void:
	var enabled := _enabled_action_indices()
	if enabled.is_empty():
		return
	var pos := enabled.find(_action_index)
	pos = 0 if pos == -1 else clampi(pos + delta, 0, enabled.size() - 1)
	_action_index = enabled[pos]
	_highlight_action_button()


## Marks the cursor'd action button by forcing its *hover* look — the shared
## trick now implemented once in MenuKeyNav.set_highlight() (see there), which
## also overrides "pressed" so a pinned quick-slot button (a toggled Button
## showing its pressed style) still lights up.
func _highlight_action_button() -> void:
	_clear_action_highlight()
	if _action_index < 0 or _action_index >= _action_buttons.size():
		return
	var button := _action_buttons[_action_index]
	if not is_instance_valid(button) or button.disabled:
		return
	MenuKeyNav.set_highlight(button, true)
	_highlighted_button = button


func _clear_action_highlight() -> void:
	if not is_instance_valid(_highlighted_button):
		_highlighted_button = null
		return
	MenuKeyNav.set_highlight(_highlighted_button, false)
	_highlighted_button = null


## 1/2/3: while focused, pin the focused recipe to that slot; while browsing,
## brew whatever is already pinned there.
func _press_digit(slot: int) -> void:
	if _focused:
		if _selected_recipe != null:
			_toggle_slot(slot, _selected_recipe)
	else:
		var pinned := _quick_slots[slot]
		if pinned != null:
			_confirm_brew(pinned)
		else:
			notice.emit("No potion saved to slot %d yet — focus a recipe and press %d." % [slot + 1, slot + 1])


func _move_selection(delta: int) -> void:
	if _visible_recipes.is_empty():
		return
	var idx := _visible_recipes.find(_selected_recipe)
	idx = 0 if idx == -1 else clampi(idx + delta, 0, _visible_recipes.size() - 1)
	var recipe := _visible_recipes[idx]
	if _rows.has(recipe):
		_list_scroll.ensure_control_visible(_rows[recipe])
		# Drives selection through the row's toggled handler -> _select().
		_rows[recipe].button_pressed = true


func _set_focused(on: bool) -> void:
	if _focused == on:
		return
	_focused = on
	if on:
		# Start the cursor on Brew (or the first slot if Brew is disabled).
		var enabled := _enabled_action_indices()
		_action_index = enabled[0] if not enabled.is_empty() else 0
	_refresh_mode_visuals()


## Re-applies everything that differs between browsing and focused: the detail
## card's action copy, the focus ring, and the footer tip.
func _refresh_mode_visuals() -> void:
	_detail_focus_ring.visible = _focused and _selected_recipe != null
	_tip.text = FOCUS_TIP if _focused else BROWSE_TIP
	_rebuild_detail()


# --- Recipe list --------------------------------------------------------------

func _rebuild_list() -> void:
	for child in _list_vbox.get_children():
		child.queue_free()
	_rows.clear()
	_visible_recipes.clear()

	var first := true
	for group in _build_groups():
		var shown: Array[RecipeDef] = []
		for recipe in group.recipes:
			if _ready_only and not Inventory.has_ingredients_for(recipe):
				continue
			shown.append(recipe)
		if shown.is_empty():
			continue

		if not first:
			_list_vbox.add_child(HSeparator.new())
		first = false

		_list_vbox.add_child(_make_group_header(group.output_id))
		for recipe in shown:
			var row := BREW_RECIPE_ROW_SCENE.instantiate()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.button_group = _row_group
			_list_vbox.add_child(row)
			row.populate(_variant_label(recipe), Inventory.has_ingredients_for(recipe), _slot_of(recipe))
			row.toggled.connect(func(on: bool) -> void:
				if on:
					_select(recipe))
			_rows[recipe] = row
			_visible_recipes.append(recipe)

	if _list_vbox.get_child_count() == 0:
		var empty := Label.new()
		empty.theme_type_variation = &"CaptionLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.custom_minimum_size = Vector2(LIST_TEXT_WIDTH, 0)
		empty.text = "Nothing to brew.\n\nLearn recipes at the Potion Book — or turn off the filter above." \
			if _ready_only else "You haven't learned any recipes yet.\n\nDiscover them at the Potion Book."
		_list_vbox.add_child(empty)

	# Keep the current selection if it's still visible, otherwise fall back to
	# the first thing that can actually be brewed (or just the first entry).
	if _selected_recipe == null or not _visible_recipes.has(_selected_recipe):
		_selected_recipe = _pick_default(_visible_recipes)
	if _selected_recipe != null and _rows.has(_selected_recipe):
		# Sets the pressed/selected visual; the toggled handler re-entrantly
		# calls _select(), which no-ops since _selected_recipe already matches.
		_rows[_selected_recipe].button_pressed = true


func _make_group_header(output_id: String) -> HBoxContainer:
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 6)

	var potion := ContentRegistry.get_potion(output_id)
	var icon: Texture2D = potion.icon if potion else null
	if icon != null:
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon
		icon_rect.custom_minimum_size = Vector2(20, 20)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		header.add_child(icon_rect)
	else:
		# Degrades to a tinted placeholder dot, same convention as the
		# journal's item/recipe/relationship rows when a Def's art is unset.
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", UiPalette.MAGIC)
		dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		header.add_child(dot)

	var name_label := Label.new()
	name_label.theme_type_variation = &"SubheadingLabel"
	name_label.text = _potion_name(output_id)
	header.add_child(name_label)
	return header


## Moving the selection (keyboard W/S or a mouse click on a row) always drops
## back to browsing — you're picking a new recipe, not acting on the old one.
func _select(recipe: RecipeDef) -> void:
	if _selected_recipe == recipe:
		return
	_selected_recipe = recipe
	_focused = false
	_refresh_mode_visuals()


func _pick_default(recipes: Array[RecipeDef]) -> RecipeDef:
	for recipe in recipes:
		if Inventory.has_ingredients_for(recipe):
			return recipe
	return recipes[0] if not recipes.is_empty() else null


# --- Detail card --------------------------------------------------------------

func _rebuild_detail() -> void:
	for child in _detail_vbox.get_children():
		child.queue_free()
	# The buttons the highlight pointed at are about to be freed; forget them so
	# _clear_action_highlight() doesn't touch a dangling one.
	_highlighted_button = null

	if _selected_recipe == null:
		var placeholder := Label.new()
		placeholder.theme_type_variation = &"CaptionLabel"
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD
		placeholder.custom_minimum_size = Vector2(DETAIL_TEXT_WIDTH, 0)
		placeholder.text = "Select a potion to see what it needs."
		_detail_vbox.add_child(placeholder)
		return

	var recipe := _selected_recipe
	var brewable := Inventory.has_ingredients_for(recipe)

	var name_label := Label.new()
	name_label.theme_type_variation = &"HeadingLabel"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.custom_minimum_size = Vector2(DETAIL_TEXT_WIDTH, 0)
	name_label.text = _potion_name(recipe.output_potion_id)
	_detail_vbox.add_child(name_label)

	var via := Label.new()
	via.theme_type_variation = &"CaptionLabel"
	via.text = "via %s" % _variant_label(recipe)
	_detail_vbox.add_child(via)

	_detail_vbox.add_child(HSeparator.new())

	var ing_title := Label.new()
	ing_title.theme_type_variation = &"SubheadingLabel"
	ing_title.text = "Ingredients"
	_detail_vbox.add_child(ing_title)

	var req_flow := HFlowContainer.new()
	req_flow.add_theme_constant_override("h_separation", 6)
	req_flow.add_theme_constant_override("v_separation", 6)
	_detail_vbox.add_child(req_flow)
	for i in recipe.ingredient_ids.size():
		var ingredient := ContentRegistry.get_ingredient(recipe.ingredient_ids[i])
		var need := recipe.ingredient_quantities[i]
		var have := Inventory.ingredient_count(recipe.ingredient_ids[i])
		var enough := have >= need
		var chip := INGREDIENT_CHIP_SCENE.instantiate()
		req_flow.add_child(chip)
		var tint: Color = IngredientDef.CATEGORY_COLORS[ingredient.category] if ingredient else Color.GRAY
		var display: String = ingredient.display_name if ingredient else recipe.ingredient_ids[i]
		chip.populate(ingredient.icon if ingredient else null, tint, "×%d" % need,
			"have %d" % have, UiPalette.SUCCESS if enough else UiPalette.DANGER, display)

	_detail_vbox.add_child(HSeparator.new())

	var potion := ContentRegistry.get_potion(recipe.output_potion_id)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	_detail_vbox.add_child(grid)
	_add_stat(grid, "Potency", "%d – %d" % [int(potion.potency_range.x), int(potion.potency_range.y)])
	_add_stat(grid, "Ease", "%d – %d" % [int(potion.ease_range.x), int(potion.ease_range.y)])
	_add_stat(grid, "Brew time", _format_minutes(potion.brew_time_minutes))

	# Push the brew controls to the bottom of the card so the button sits in a
	# consistent spot regardless of ingredient count.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_vbox.add_child(spacer)

	# A single mode line carries the current instruction: how to act, or why you
	# can't (missing ingredients). Tinted magic when focused, terracotta when
	# short, muted otherwise.
	var mode_line := Label.new()
	mode_line.theme_type_variation = &"CaptionLabel"
	mode_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	mode_line.custom_minimum_size = Vector2(DETAIL_TEXT_WIDTH, 0)
	if not brewable:
		mode_line.text = "Missing ingredients — check the pantry." if not _focused \
			else "Focused, but missing ingredients. Esc to step back."
		mode_line.add_theme_color_override("font_color", UiPalette.DANGER)
	elif _focused:
		mode_line.text = "Focused — W / S pick an action, E to use it, or 1 / 2 / 3 to save."
		mode_line.add_theme_color_override("font_color", UiPalette.MAGIC)
	else:
		mode_line.text = "Press E to focus this recipe."
	_detail_vbox.add_child(mode_line)

	_action_buttons.clear()

	var brew_button := Button.new()
	brew_button.text = "Brew  (E)"
	brew_button.disabled = not brewable
	brew_button.pressed.connect(func() -> void: _confirm_brew(recipe))
	_detail_vbox.add_child(brew_button)
	_action_buttons.append(brew_button)

	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 6)
	var slot_caption := Label.new()
	slot_caption.theme_type_variation = &"CaptionLabel"
	slot_caption.text = "Quick slot:"
	slot_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_row.add_child(slot_caption)
	for s in QUICK_SLOT_COUNT:
		var slot_button := Button.new()
		slot_button.toggle_mode = true
		slot_button.text = str(s + 1)
		slot_button.custom_minimum_size = Vector2(36, 0)
		slot_button.button_pressed = _quick_slots[s] == recipe
		slot_button.tooltip_text = "Pin this potion to slot %d (or press %d while focused)" % [s + 1, s + 1]
		slot_button.pressed.connect(func() -> void: _toggle_slot(s, recipe))
		slot_row.add_child(slot_button)
		_action_buttons.append(slot_button)
	_detail_vbox.add_child(slot_row)

	# When focused, keep the action cursor on a valid button and re-apply its
	# hover highlight (the buttons were just rebuilt, so the override is gone).
	if _focused:
		var enabled := _enabled_action_indices()
		if not enabled.has(_action_index):
			_action_index = enabled[0] if not enabled.is_empty() else 0
		_highlight_action_button()


func _add_stat(grid: GridContainer, label_text: String, value_text: String) -> void:
	var key := Label.new()
	key.theme_type_variation = &"CaptionLabel"
	key.text = label_text
	grid.add_child(key)
	var value := Label.new()
	value.theme_type_variation = &"NumericLabel"
	value.text = value_text
	grid.add_child(value)


# --- Actions ------------------------------------------------------------------

func _confirm_brew(recipe: RecipeDef) -> void:
	brew_confirmed.emit(recipe)


## A recipe lives in at most one slot: pinning it elsewhere clears its old slot,
## and re-pinning it to the same slot clears it (toggle off).
func _toggle_slot(slot: int, recipe: RecipeDef) -> void:
	if _quick_slots[slot] == recipe:
		_quick_slots[slot] = null
		notice.emit("Cleared quick slot %d." % [slot + 1])
	else:
		for i in QUICK_SLOT_COUNT:
			if _quick_slots[i] == recipe:
				_quick_slots[i] = null
		_quick_slots[slot] = recipe
		notice.emit("Saved %s to quick slot %d." % [_potion_name(recipe.output_potion_id), slot + 1])
	_rebuild_list()
	_refresh_mode_visuals()


func _validate_quick_slots() -> void:
	for i in QUICK_SLOT_COUNT:
		var recipe := _quick_slots[i]
		if recipe != null and not Alchemy.is_learned(recipe.id):
			_quick_slots[i] = null


func _slot_of(recipe: RecipeDef) -> int:
	return _quick_slots.find(recipe)


func _on_ready_only_toggled(on: bool) -> void:
	_ready_only = on
	_focused = false
	_rebuild_list()
	_refresh_mode_visuals()


# --- Grouping / naming helpers ------------------------------------------------

## Ordered groups of *learned* recipes keyed by output potion, first-seen order
## preserved. Each entry: {output_id: String, recipes: Array[RecipeDef]}.
func _build_groups() -> Array:
	var order: Array[String] = []
	var by_output: Dictionary = {}
	for recipe in Alchemy.get_learned_recipes():
		if not by_output.has(recipe.output_potion_id):
			by_output[recipe.output_potion_id] = ([] as Array[RecipeDef])
			order.append(recipe.output_potion_id)
		by_output[recipe.output_potion_id].append(recipe)

	var groups: Array = []
	for output_id in order:
		groups.append({"output_id": output_id, "recipes": by_output[output_id]})
	return groups


## The potion's display name, from its PotionDef.
func _potion_name(output_id: String) -> String:
	var potion := ContentRegistry.get_potion(output_id)
	return potion.display_name if potion != null else output_id


## The method a recipe brews the potion by — RecipeDef.display_name is
## already just the method label (e.g. "Ember Dust + Rift Glass"), not the
## potion's name.
func _variant_label(recipe: RecipeDef) -> String:
	return recipe.display_name


func _format_minutes(minutes: int) -> String:
	@warning_ignore("integer_division")
	var hours := minutes / 60
	var mins := minutes % 60
	if hours > 0 and mins > 0:
		return "%dh %dm" % [hours, mins]
	if hours > 0:
		return "%dh" % hours
	return "%dm" % mins
