class_name AlchemyLabMenu
extends HBoxContainer
## MenuScene content opened by AlchemyLabManagerInteractable — a grid of the
## stations linked to that manager, and a detail panel to either purchase the
## selected station or browse/buy/remove its upgrades. See
## docs/design/systems.md, system 4. Built entirely in code (no .tscn),
## same as brew_panel/supply_panel — plain Buttons rather than BrewMenu's
## component-scene machinery, since there's no icon/tag art for Alembics yet.

signal notice(text: String)

var _grid: GridContainer
var _detail: VBoxContainer
var _station_ids: Array[String] = []
var _selected_station_id: String = ""


func build() -> void:
	add_theme_constant_override("separation", 16)

	_grid = GridContainer.new()
	_grid.columns = 1
	_grid.custom_minimum_size = Vector2(220, 0)
	add_child(_grid)

	_detail = VBoxContainer.new()
	_detail.custom_minimum_size = Vector2(280, 0)
	add_child(_detail)


func open_for(station_ids: Array[String]) -> void:
	_station_ids = station_ids
	_rebuild_grid()
	_select_station(_station_ids[0] if not _station_ids.is_empty() else "")


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	for station_id in _station_ids:
		var station := Brewing.get_station(station_id)
		if station == null:
			continue
		var button := Button.new()
		button.toggle_mode = true
		button.button_pressed = station_id == _selected_station_id
		button.text = "%s — %s" % [station.display_name, "Owned" if station.purchased else "Cost %d" % station.cost]
		button.pressed.connect(_select_station.bind(station_id))
		_grid.add_child(button)


func _select_station(station_id: String) -> void:
	_selected_station_id = station_id
	_rebuild_grid()
	_rebuild_detail()


func _rebuild_detail() -> void:
	for child in _detail.get_children():
		child.queue_free()
	var station := Brewing.get_station(_selected_station_id)
	if station == null:
		return

	var title := Label.new()
	title.theme_type_variation = &"SubheadingLabel"
	title.text = station.display_name
	_detail.add_child(title)

	if not station.purchased:
		var cost_label := Label.new()
		cost_label.text = "Cost: %d Materials" % station.cost
		_detail.add_child(cost_label)

		var buy_button := Button.new()
		buy_button.text = "Purchase"
		buy_button.pressed.connect(_on_purchase_station_pressed)
		_detail.add_child(buy_button)
		return

	for upgrade in ContentRegistry.alembic_upgrades:
		_detail.add_child(_build_upgrade_row(station, upgrade))


func _build_upgrade_row(station: StationInstance, upgrade: AlembicUpgradeDef) -> Control:
	var row := HBoxContainer.new()

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = "%s (%d)" % [upgrade.display_name, upgrade.cost]
	info.add_child(name_label)
	var summary_label := Label.new()
	summary_label.theme_type_variation = &"CaptionLabel"
	summary_label.text = _summarize_upgrade(upgrade)
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_child(summary_label)
	row.add_child(info)

	var owned := upgrade.id in station.upgrade_ids
	var action_button := Button.new()
	if owned:
		action_button.text = "Remove"
		action_button.pressed.connect(_on_remove_upgrade_pressed.bind(upgrade.id))
	else:
		var conflict := _conflicts_with_owned(station, upgrade)
		if conflict:
			action_button.text = "Excluded"
			action_button.disabled = true
		else:
			action_button.text = "Buy"
			action_button.pressed.connect(_on_buy_upgrade_pressed.bind(upgrade.id))
	row.add_child(action_button)

	return row


func _conflicts_with_owned(station: StationInstance, upgrade: AlembicUpgradeDef) -> bool:
	for owned_id in station.upgrade_ids:
		if owned_id in upgrade.excludes:
			return true
		var owned := ContentRegistry.get_alembic_upgrade(owned_id)
		if owned != null and upgrade.id in owned.excludes:
			return true
	return false


func _summarize_upgrade(upgrade: AlembicUpgradeDef) -> String:
	var parts: Array[String] = []
	for effect_target in upgrade.effects:
		var amount: float = upgrade.effects[effect_target]
		parts.append("%s %+d%%" % [effect_target, int(amount * 100.0)])
	for tag in upgrade.tags:
		parts.append(tag)
	if not upgrade.excludes.is_empty():
		parts.append("excludes: %s" % ", ".join(upgrade.excludes))
	return "; ".join(parts) if not parts.is_empty() else "No effect."


func _on_purchase_station_pressed() -> void:
	var reason := Brewing.purchase_station(_selected_station_id)
	if reason != "":
		notice.emit(reason)
	else:
		_rebuild_grid()
		_rebuild_detail()


func _on_buy_upgrade_pressed(upgrade_id: String) -> void:
	var reason := Brewing.purchase_alembic_upgrade(_selected_station_id, upgrade_id)
	if reason != "":
		notice.emit(reason)
	else:
		_rebuild_detail()


func _on_remove_upgrade_pressed(upgrade_id: String) -> void:
	Brewing.remove_alembic_upgrade(_selected_station_id, upgrade_id)
	_rebuild_detail()
