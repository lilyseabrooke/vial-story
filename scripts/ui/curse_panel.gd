class_name CursePanel
extends VBoxContainer
## Content hosted by MenuScene when the player interacts with an active
## CurseInteractable. The description spans the full width up top (it's
## prose, not a fixed-shape field, so it doesn't need a column of its own),
## with requirements (left) and the tray + Dispel button (right) as a second
## row below it — keeps the panel short instead of sprawling vertically,
## same reason the ingredient picker itself was split out into its own
## detached CurseInventoryWindow (GameHud shows/positions it beside this
## panel, same "window rides alongside a MenuScene panel" pattern as
## PantryWindow/BrewMenu).
##
## The tray is a fixed Curse.MAX_DISPEL_INGREDIENTS-slot column of ItemSlot
## cells (same Button-wraps-ItemSlot click-to-select trick as GameMenu's Shop
## grid). CurseInventoryWindow's slot_pressed signal feeds add_to_tray();
## clicking a filled tray slot here moves it back out. Ingredients are never
## consumed by a bad guess — Dispel only appears once the tray's contents
## already satisfy the curse (see Curse.meets_requirements()), so committing
## it always succeeds.
##
## One instance owned by hud.gd, reused across curse instances via
## open_for() the same way AttemptPuzzlePanel is reused across potions.

## Emitted whenever tray membership changes (a slot filled or cleared) so
## GameHud can refresh CurseInventoryWindow's available counts to match.
signal tray_changed

const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")

var _instance_id: String = ""
var _curse: CurseDef
var _tray_ids: Array[String] = []   # size Curse.MAX_DISPEL_INGREDIENTS, "" = empty slot

var _description_label: Label
var _requirements_label: Label
var _tray_row: VBoxContainer
var _dispel_button: Button
var _result_label: Label


## Called once right after instantiate(), same as the old build() -- NOT
## @onready, because this panel is only added to the scene tree the first
## time MenuScene.open() reparents it (see CurseInteractable's open_for()
## then open_menu() ordering), by which point open_for() has already run and
## needs these refs populated.
func setup() -> void:
	_description_label = $DescriptionLabel
	_requirements_label = $Columns/RequirementsColumn/RequirementsLabel
	_tray_row = $Columns/TrayColumn/TrayRow
	_dispel_button = $Columns/TrayColumn/DispelButton
	_result_label = $ResultLabel
	_dispel_button.pressed.connect(_on_dispel_pressed)


## Called each time the player opens this panel for a specific curse instance
## — empties the tray, since the last visit's selection shouldn't carry over.
func open_for(instance_id: String) -> void:
	_instance_id = instance_id
	_curse = Curse.get_active_curse(instance_id)
	_tray_ids.clear()
	for i in Curse.MAX_DISPEL_INGREDIENTS:
		_tray_ids.append("")
	_result_label.text = ""
	_refresh()


## Non-empty tray contents, for CurseInventoryWindow.refresh() to know how
## many copies of each ingredient are already "used" and whether the tray is
## full.
func get_tray_ids() -> Array[String]:
	return _current_tray_ids()


## CurseInventoryWindow's slot_pressed handler — moves one unit of
## ingredient_id into the first empty tray slot, if any.
func add_to_tray(ingredient_id: String) -> void:
	var empty_index := _tray_ids.find("")
	if empty_index == -1:
		return
	_tray_ids[empty_index] = ingredient_id
	_refresh()
	tray_changed.emit()


func _refresh() -> void:
	if _curse == null:
		_description_label.text = "There's nothing left to dispel here."
		_requirements_label.text = ""
		_tray_row.visible = false
		_dispel_button.visible = false
		return

	_description_label.text = _curse.description
	_requirements_label.text = _describe_requirements()
	_tray_row.visible = true
	_refresh_tray()

	var ids := _current_tray_ids()
	_dispel_button.visible = not ids.is_empty() and Curse.meets_requirements(_instance_id, ids)


func _describe_requirements() -> String:
	var lines: Array[String] = []
	for i in _curse.minima.size():
		lines.append(_curse.describe_minimum(i))
	for i in _curse.maxima.size():
		lines.append(_curse.describe_maximum(i))
	if not _curse.permitted_ingredients.is_empty():
		var names: Array[String] = []
		for category_name in _curse.permitted_ingredients:
			names.append(String(category_name).capitalize())
		lines.append("Ingredients must be: %s" % ", ".join(names))
	lines.append("Uses up to %d ingredient(s)." % Curse.MAX_DISPEL_INGREDIENTS)
	return "\n".join(lines)


## Rebuilds the fixed-size tray column: one ItemSlot-in-a-Button cell per
## Curse.MAX_DISPEL_INGREDIENTS slot. A filled cell shows that ingredient and
## clicking it clears the slot (moves it back to the inventory window); an
## empty cell is a disabled clear() placeholder, same "cleared vs.
## populated" look GameMenu's Shop grid uses for unstocked slots.
func _refresh_tray() -> void:
	for child in _tray_row.get_children():
		child.queue_free()

	for i in _tray_ids.size():
		var ingredient_id: String = _tray_ids[i]
		var item_slot: ItemSlot = ITEM_SLOT_SCENE.instantiate()
		var filled := ingredient_id != ""
		if filled:
			var ingredient := ContentRegistry.get_ingredient(ingredient_id)
			item_slot.populate_item(ingredient.display_name, "", "", 1,
				IngredientDef.CATEGORY_COLORS[ingredient.category], ingredient.icon, ingredient.description)
		else:
			item_slot.clear()

		var cell := Button.new()
		cell.custom_minimum_size = item_slot.custom_minimum_size
		# _tray_row is a VBoxContainer now (slots stack vertically) — its
		# cross axis is horizontal, so a plain Control's default SIZE_FILL
		# would stretch each cell to the column's full width, dragging the
		# Button's background out past the small ItemSlot sitting inside it.
		# SIZE_SHRINK_BEGIN keeps each cell at its natural 72x72 size instead.
		cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		cell.disabled = not filled
		cell.add_child(item_slot)
		item_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.pressed.connect(_on_tray_slot_pressed.bind(i))
		_tray_row.add_child(cell)


func _current_tray_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _tray_ids:
		if id != "":
			ids.append(id)
	return ids


func _on_tray_slot_pressed(index: int) -> void:
	if _tray_ids[index] == "":
		return
	_tray_ids[index] = ""
	_refresh()
	tray_changed.emit()


func _on_dispel_pressed() -> void:
	var ids := _current_tray_ids()
	if ids.is_empty():
		return

	for id in ids:
		Inventory.consume_ingredient(id, 1)
	var success := Curse.attempt_dispel(_instance_id, ids)
	_result_label.text = "The curse lifts!" if success \
		else "That combination no longer satisfies the curse."

	for i in _tray_ids.size():
		_tray_ids[i] = ""
	_curse = Curse.get_active_curse(_instance_id)
	_refresh()
	tray_changed.emit()
