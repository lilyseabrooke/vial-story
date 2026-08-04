class_name BuildModeController
extends Node
## In-world component placement/rearrangement mode. See docs/design/systems.md,
## system 4 (Build Mode). Entered directly by ZoneConsoleInteractable --
## purchasing, upgrade browsing, and placement all live here now, so the Zone
## Console itself is just a trigger with no menu of its own.
##
## Owned by GameHud (parallel to how it already owns _menu_scene/
## _pantry_window). Finds its target PlacementZone via the "placement_zones"
## group rather than a RoomBuilder reference -- every PlacementZone adds
## itself to that group in _ready(), so this controller needs no world-graph
## wiring beyond the zone_id it's told to enter.
##
## Four focus modes, all driven by the same six-action input schema
## (move_*/select/back) rather than Godot's Control-focus system (MenuKeyNav
## doesn't apply here -- this predates it and stays bespoke for consistency):
##   SHELF          -- browsing the always-visible component shelf (bottom bar)
##   GRID           -- cursor stepping on the zone grid
##   COMPONENT_MENU -- Upgrades/Pick Up/Return to Storage for a selected placed component
##   UPGRADES       -- browsing AlembicUpgradeDefs for that component
## Deliberately not MenuScene-hosted: MenuScene.close() unconditionally
## unpauses the Clock, which would incorrectly unpause the world while Build
## Mode is still active underneath a submenu -- everything here shares one
## continuous CanvasLayer overlay and one input dispatcher instead.

const BUILD_CURSOR_SCENE := preload("res://scenes/world/BuildCursor.tscn")
const ITEM_SLOT_SCENE := preload("res://scenes/ui/components/ItemSlot.tscn")
const SHELF_HIGHLIGHT_TINT := UiPalette.GOLD
const SHELF_NORMAL_TINT := Color(1, 1, 1, 1)
## Down-right of the cursor by default; flips to stay in-viewport.
const COMPONENT_MENU_OFFSET := Vector2(24, 24)
const PANEL_PADDING := 16
## Kept clear of the viewport edge when the detail panel's natural height
## would otherwise run off-screen (see _position_detail_panel()).
const VIEWPORT_EDGE_MARGIN := 24.0
## The shelf bar is a fixed fraction of the viewport width, centered along the
## bottom edge -- it never grows to fit its contents. Once the slots inside
## exceed that width the bar scrolls horizontally instead (see _build_overlay()).
const SHELF_WIDTH_RATIO := 2.0 / 3.0
## Gap between the shelf bar and the bottom of the viewport.
const SHELF_BOTTOM_MARGIN := 24.0
## Explicit height for the shelf's horizontal scrollbar. The shared theme
## styles the scrollbar grabber but gives it no content margins, so its natural
## minimum height is 0 -- fine for the menus that only ever scroll by keyboard,
## but here it's the one cue that the shelf runs past the edge of the bar.
const SHELF_SCROLLBAR_HEIGHT := 12.0
## Matches FramedPanel's StyleBoxTexture (assets/ui/StyleBoxTexture_WoodFrameLightInterior.tres)
## texture_margin on every side -- the 9-patch frame's own border thickness,
## added on top of PANEL_PADDING. Computed manually rather than trusted from
## _detail_panel.get_combined_minimum_size().y -- that value gets stuck at a
## stale height once anything inside the ScrollContainer/MarginContainer
## chain has been constrained smaller than its natural size at any point (a
## Godot minimum-size-caching quirk through nested Containers), so height is
## summed by hand from the still-reliable per-child minimums instead; width
## isn't affected by this and still reads correctly from the panel itself.
const FRAME_TEXTURE_MARGIN := 28.0
## Fixed wrap width for autowrap Labels in the detail panel -- an autowrap
## Label with no explicit width has a circular minimum-size dependency
## (its reported height depends on the width it's given, which depends on
## layout that hasn't happened yet), which independently produces the same
## kind of stuck/inflated height. Matches the panel's default content width
## (320 minus PANEL_PADDING on both sides).
const DETAIL_CONTENT_WIDTH := 320.0 - PANEL_PADDING * 2.0

enum Mode { SHELF, GRID, COMPONENT_MENU, UPGRADES }

var hud: GameHud
var active: bool = false
var zone_id: String = ""
var cursor_cell: Vector2i = Vector2i(0, 0)
var held_id: String = ""

var _mode: Mode = Mode.SHELF
var _shelf_index: int = 0
## Anchor cell of the most recent successful placement, or (-1, -1) before the
## first one this session. Where the cursor picks up again when the next
## component is grabbed off the shelf, so building a cluster doesn't mean
## walking back across the grid after every piece.
var _last_placed_cell: Vector2i = Vector2i(-1, -1)
## Whether the carried component came off the shelf bar (a grab/purchase) or
## off the grid ("Pick Up"). Placing a shelf-sourced one completes a "fetch a
## thing and put it down" round trip, so the cursor returns to the bar ready
## for the next fetch; placing a picked-up one is the back half of a rearrange,
## where the player is working on the grid and should stay there.
var _held_from_shelf: bool = false
## Column the cursor last stepped off the grid from, so coming back up out of
## the shelf bar resumes there instead of snapping to the left edge -- the
## vertical wrap reads as one continuous move off the top (or bottom) edge and
## back in at the other, rather than a jump sideways.
var _grid_exit_column: int = 0
var _component_menu_index: int = 0
var _upgrades_index: int = 0
var _menu_component_id: String = ""   # which placed component COMPONENT_MENU/UPGRADES act on

var _zone: PlacementZone
var _cursor: BuildCursor
var _overlay: CanvasLayer
var _shelf_panel: PanelContainer
var _shelf_scroll: ScrollContainer
var _shelf_list: HBoxContainer
var _detail_panel: PanelContainer
var _detail_scroll: ScrollContainer
var _detail_box: VBoxContainer


func setup(owner_hud: GameHud) -> void:
	hud = owner_hud


func enter(target_zone_id: String) -> void:
	if active:
		return
	var zone_node := _find_zone_node(target_zone_id)
	if zone_node == null:
		push_warning("BuildModeController: no PlacementZone found for '%s'" % target_zone_id)
		return
	active = true
	zone_id = target_zone_id
	_zone = zone_node
	_zone.set_grid_visible(true)
	_mode = Mode.SHELF
	_shelf_index = 0
	cursor_cell = Vector2i(0, 0)
	_last_placed_cell = Vector2i(-1, -1)
	held_id = ""
	_held_from_shelf = false
	_grid_exit_column = 0
	Clock.is_paused = true
	_spawn_cursor()
	_build_overlay()
	_refresh_overlay()
	_update_cursor_position()


func exit() -> void:
	if not active:
		return
	active = false
	held_id = ""
	_held_from_shelf = false
	if _zone != null:
		_zone.set_grid_visible(false)
	Clock.is_paused = false
	if _cursor != null:
		_cursor.queue_free()
		_cursor = null
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_zone = null


func _find_zone_node(target_zone_id: String) -> PlacementZone:
	for node in get_tree().get_nodes_in_group("placement_zones"):
		if node is PlacementZone and node.zone_id == target_zone_id:
			return node
	return null


func _spawn_cursor() -> void:
	_cursor = BUILD_CURSOR_SCENE.instantiate()
	_zone.add_child(_cursor)
	_cursor.set_cell_size(_zone.cell_size)


## Every ComponentDef valid for this zone's zone_type -- the shelf's fixed
## row list (today: Alembic, Pantry, Accelerator, all three valid for
## "alchemy_lab"). Order follows ContentRegistry.component_defs.
func _zone_defs() -> Array[ComponentDef]:
	var zone := Placement.get_zone(zone_id)
	var zone_type: String = zone.get("zone_type", "")
	return ContentRegistry.component_defs.filter(
		func(def: ComponentDef) -> bool: return zone_type in def.zone_types
	)


func _storage_count_for_def(def_id: String) -> int:
	var count := 0
	for instance in Placement.storage_components_for_zone(zone_id):
		if instance.def_id == def_id:
			count += 1
	return count


func _first_storage_instance_for_def(def_id: String) -> ComponentInstance:
	for instance in Placement.storage_components_for_zone(zone_id):
		if instance.def_id == def_id:
			return instance
	return null


func _component_menu_rows(def: ComponentDef) -> Array[String]:
	var rows: Array[String] = []
	if def != null and def.category == "alembic":
		rows.append("Upgrades")
	rows.append("Pick Up")
	rows.append("Return to Storage")
	return rows


# ---------------------------------------------------------------------------
# Input dispatch
# ---------------------------------------------------------------------------

func handle_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("move_up"):
		_on_move(Vector2i(0, -1))
	elif event.is_action_pressed("move_down"):
		_on_move(Vector2i(0, 1))
	elif event.is_action_pressed("move_left"):
		_on_move(Vector2i(-1, 0))
	elif event.is_action_pressed("move_right"):
		_on_move(Vector2i(1, 0))
	elif event.is_action_pressed("select"):
		_on_select()
	elif event.is_action_pressed("back"):
		_on_back()


func _on_move(delta: Vector2i) -> void:
	match _mode:
		Mode.SHELF:
			_move_shelf(delta)
		Mode.GRID:
			_move_grid(delta)
		Mode.COMPONENT_MENU:
			_move_component_menu(delta)
		Mode.UPGRADES:
			_move_upgrades(delta)
	_refresh_overlay()
	_update_cursor_position()


func _on_select() -> void:
	match _mode:
		Mode.SHELF:
			_select_shelf()
		Mode.GRID:
			_select_grid()
		Mode.COMPONENT_MENU:
			_select_component_menu()
		Mode.UPGRADES:
			_select_upgrades()
	_refresh_overlay()
	_update_cursor_position()


func _on_back() -> void:
	match _mode:
		Mode.GRID when held_id != "":
			# Cancels the carry rather than leaving Build Mode. A held
			# component is already sitting in storage (purchase_component()
			# creates it unplaced, and "Pick Up" stores it before handing the
			# id over), so dropping the id here *is* returning it to storage.
			held_id = ""
			_held_from_shelf = false
		Mode.SHELF, Mode.GRID:
			exit()
			return
		Mode.COMPONENT_MENU:
			_mode = Mode.GRID
		Mode.UPGRADES:
			_mode = Mode.COMPONENT_MENU
	_refresh_overlay()
	_update_cursor_position()


func _update_cursor_position() -> void:
	if _cursor == null:
		return
	if _mode == Mode.GRID:
		_cursor.visible = true
		var def := _held_def()
		var footprint := def.footprint if def != null else Vector2i(1, 1)
		_cursor.set_cell_size(_zone.cell_size)
		_cursor.set_footprint(footprint, _blocked_offsets())
		_cursor.global_position = _zone.cell_to_world(cursor_cell, footprint)
		# Same icon/icon_offset convention RoomBuilder feeds the real placed
		# sprite -- the cursor's origin is centered on the footprint the same
		# way a placed node's is, so the preview lines up identically with
		# where the real thing will land. null (nothing carried, or the def
		# has no art yet) just hides it, leaving the highlighted squares.
		# icon_offset is additionally nudged by sort_offset_y here (rather
		# than moving the whole cursor node, which would drag the highlighted
		# squares off the grid with it) -- RoomBuilder bakes that same nudge
		# into the real placed node's spawn *position*, so the icon alone
		# needs the equivalent shift to preview in the same spot.
		var icon_offset := (def.icon_offset + Vector2(0, def.sort_offset_y)) if def != null else Vector2.ZERO
		_cursor.set_icon(def.icon if def != null else null, icon_offset)
	else:
		_cursor.visible = false


## Which cells under the cursor would refuse the carried component, as offsets
## from its anchor cell -- asked of Placement rather than re-derived here, so
## the red squares can't disagree with what place_component() will actually
## allow. Empty while carrying nothing: an occupied cell isn't an obstacle
## then, it's the thing `select` opens a menu for.
func _blocked_offsets() -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	if held_id == "":
		return offsets
	for cell in Placement.blocking_cells(held_id, zone_id, cursor_cell):
		offsets.append(cell - cursor_cell)
	return offsets


## The ComponentDef of whatever's currently being carried, or null while
## just browsing/carrying nothing.
func _held_def() -> ComponentDef:
	if held_id == "":
		return null
	var instance := Placement.get_component(held_id)
	return ContentRegistry.get_component_def(instance.def_id) if instance != null else null


# ---------------------------------------------------------------------------
# SHELF
# ---------------------------------------------------------------------------

## The shelf runs along the bottom of the screen, so left/right walk it and
## up steps off it into the grid -- entering at the grid's bottom row, the
## edge the cursor just came from.
func _move_shelf(delta: Vector2i) -> void:
	if delta == Vector2i(0, -1):
		_mode = Mode.GRID
		cursor_cell = _grid_entry_cell()
		return
	if delta.x != 0:
		var defs := _zone_defs()
		if defs.is_empty():
			return
		_shelf_index = clampi(_shelf_index + delta.x, 0, defs.size() - 1)


## Where the cursor arrives when it steps up off the shelf bar: the bottom row
## (the edge nearest the bar), in the column it left the grid from -- so
## stepping off the top edge and pressing up again lands directly below where
## it started, completing the wrap. Clamped so whatever's being carried fits.
func _grid_entry_cell() -> Vector2i:
	return _clamp_to_grid(Vector2i(_grid_exit_column, Placement.get_zone(zone_id).get("rows", 1)))


## Where the cursor lands when a component is grabbed off the shelf: on top of
## the last thing placed this session, so placing a run of components doesn't
## restart from the corner each time. Falls back to _grid_entry_cell() before
## anything has been placed.
func _carry_entry_cell() -> Vector2i:
	if _last_placed_cell.x < 0:
		return _grid_entry_cell()
	return _clamp_to_grid(_last_placed_cell)


## Pins an anchor cell inside the range the carried footprint can legally
## occupy -- a 4x2 Alembic's anchor has to stop short of the right/bottom edges
## so its far corner stays on the grid.
func _clamp_to_grid(cell: Vector2i) -> Vector2i:
	var bound := _anchor_bound()
	return Vector2i(clampi(cell.x, 0, bound.x), clampi(cell.y, 0, bound.y))


## Largest anchor cell the carried footprint (1x1 while carrying nothing) can
## sit at without spilling off the grid.
func _anchor_bound() -> Vector2i:
	var zone_data := Placement.get_zone(zone_id)
	var carried_def := _held_def()
	var footprint := carried_def.footprint if carried_def != null else Vector2i(1, 1)
	return Vector2i(
		maxi(0, int(zone_data.get("cols", 1)) - footprint.x),
		maxi(0, int(zone_data.get("rows", 1)) - footprint.y)
	)


## Selecting a shelf entry grabs an existing stored instance if the player
## owns one, or purchases a new one if they don't -- doing nothing at all if
## they can't afford it (no error message; the spec calls for a silent no-op
## here, unlike every other failure path in this controller).
func _select_shelf() -> void:
	var defs := _zone_defs()
	if _shelf_index < 0 or _shelf_index >= defs.size():
		return
	var def := defs[_shelf_index]
	var existing := _first_storage_instance_for_def(def.id)
	if existing != null:
		held_id = existing.id
		_held_from_shelf = true
		_mode = Mode.GRID
		cursor_cell = _carry_entry_cell()
		return
	var result := Placement.purchase_component(zone_id, def.id)
	if result.error == "":
		held_id = result.id
		_held_from_shelf = true
		_mode = Mode.GRID
		cursor_cell = _carry_entry_cell()
		hud.log_message("Purchased %s." % def.display_name)


# ---------------------------------------------------------------------------
# GRID
# ---------------------------------------------------------------------------

## Movement wraps rather than stopping at the edges, always within the range
## the carried footprint can legally anchor at (a 4x2 Alembic's cursor never
## wanders with its far edge hanging off the grid -- place_component() would
## refuse that, so the cursor shouldn't be able to get there in the first
## place). Vertically the shelf bar is part of the cycle: stepping off the top
## or bottom row lands on it, since it's docked below the grid on screen. The
## exception is while carrying something, when the grid is the only place the
## cursor can usefully be -- vertical steps then wrap inside it, and `back` is
## how the player puts the component down instead.
func _move_grid(delta: Vector2i) -> void:
	var bound := _anchor_bound()
	if delta.x != 0:
		cursor_cell.x = wrapi(cursor_cell.x + delta.x, 0, bound.x + 1)
		return
	if delta.y == 0:
		return
	var next_y := cursor_cell.y + delta.y
	if next_y >= 0 and next_y <= bound.y:
		cursor_cell.y = next_y
	elif held_id != "":
		cursor_cell.y = wrapi(next_y, 0, bound.y + 1)
	else:
		_grid_exit_column = cursor_cell.x
		_mode = Mode.SHELF


## An occupied cell opens the per-component menu instead of picking up
## immediately -- Upgrades/Pick Up/Return to Storage all live there now.
func _select_grid() -> void:
	var occupant := Placement.get_component_at(zone_id, cursor_cell)
	if occupant != null and held_id == "":
		_menu_component_id = occupant.id
		_component_menu_index = 0
		_mode = Mode.COMPONENT_MENU
	elif occupant == null and held_id != "":
		var err := Placement.place_component(held_id, zone_id, cursor_cell)
		if err == "":
			held_id = ""
			# Remembered whichever way this component arrived, so the next
			# shelf grab starts its carry here rather than back at the corner
			# (see _carry_entry_cell()). Where the cursor itself goes depends
			# on where the component came from -- see _held_from_shelf.
			_last_placed_cell = cursor_cell
			if _held_from_shelf:
				_mode = Mode.SHELF
			_held_from_shelf = false
		else:
			hud.log_message(err)
	elif occupant != null and held_id != "":
		hud.log_message("That cell is occupied.")


# ---------------------------------------------------------------------------
# COMPONENT_MENU
# ---------------------------------------------------------------------------

func _move_component_menu(delta: Vector2i) -> void:
	if delta.y == 0:
		return
	var instance := Placement.get_component(_menu_component_id)
	var def := ContentRegistry.get_component_def(instance.def_id) if instance != null else null
	var rows := _component_menu_rows(def)
	_component_menu_index = clampi(_component_menu_index + delta.y, 0, rows.size() - 1)


func _select_component_menu() -> void:
	var instance := Placement.get_component(_menu_component_id)
	var def := ContentRegistry.get_component_def(instance.def_id) if instance != null else null
	var rows := _component_menu_rows(def)
	if _component_menu_index < 0 or _component_menu_index >= rows.size():
		return
	match rows[_component_menu_index]:
		"Upgrades":
			_mode = Mode.UPGRADES
			_upgrades_index = 0
		"Pick Up":
			# A mid-brew Alembic can't be picked up -- rearranging a station
			# out from under a running BrewJob would strand it with no way
			# to collect. Everything else can always be picked up.
			if def != null and def.category == "alembic" and Brewing.get_current_job(_menu_component_id) != null:
				hud.log_message("Still brewing — can't move it.")
			else:
				# Captured before store_component() clears it -- the cursor
				# snaps to the item's own top-left anchor cell (not wherever
				# within its footprint it happened to be selected from), so a
				# picked-up item visually stays put until the player actually
				# moves the cursor away.
				var anchor_cell := instance.grid_position
				Placement.store_component(_menu_component_id)
				held_id = _menu_component_id
				cursor_cell = anchor_cell
				_mode = Mode.GRID
		"Return to Storage":
			Placement.store_component(_menu_component_id)
			_mode = Mode.GRID


# ---------------------------------------------------------------------------
# UPGRADES
# ---------------------------------------------------------------------------

func _move_upgrades(delta: Vector2i) -> void:
	if delta.y == 0:
		return
	var count := ContentRegistry.alembic_upgrades.size()
	if count > 0:
		_upgrades_index = clampi(_upgrades_index + delta.y, 0, count - 1)


func _select_upgrades() -> void:
	var upgrades := ContentRegistry.alembic_upgrades
	if _upgrades_index < 0 or _upgrades_index >= upgrades.size():
		return
	var upgrade := upgrades[_upgrades_index]
	var owned_ids: Array = Brewing.alembic_upgrade_ids.get(_menu_component_id, [])
	if upgrade.id in owned_ids:
		Brewing.remove_alembic_upgrade(_menu_component_id, upgrade.id)
	else:
		var reason := Brewing.purchase_alembic_upgrade(_menu_component_id, upgrade.id)
		if reason != "":
			hud.log_message(reason)


func _conflicts_with_owned(owned_ids: Array, upgrade: AlembicUpgradeDef) -> bool:
	for owned_id in owned_ids:
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


func _describe_cost(def: ComponentDef) -> String:
	var parts: Array[String] = ["%d Materials" % def.materials_cost]
	for i in def.ingredient_ids.size():
		var ingredient := ContentRegistry.get_ingredient(def.ingredient_ids[i])
		var label := ingredient.display_name if ingredient != null else def.ingredient_ids[i]
		parts.append("%d %s" % [def.ingredient_quantities[i], label])
	return ", ".join(parts)


# ---------------------------------------------------------------------------
# Overlay
# ---------------------------------------------------------------------------

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 9
	add_child(_overlay)

	# Bottom bar, pinned to a fixed SHELF_WIDTH_RATIO of the viewport: both
	# horizontal anchors are set (so the width is purely a fraction of the
	# screen, never content-driven), while the vertical pair collapses to the
	# bottom edge and grows upward to whatever the tallest slot needs.
	_shelf_panel = PanelContainer.new()
	_shelf_panel.theme_type_variation = &"FramedPanel"
	_shelf_panel.anchor_left = (1.0 - SHELF_WIDTH_RATIO) * 0.5
	_shelf_panel.anchor_right = 1.0 - (1.0 - SHELF_WIDTH_RATIO) * 0.5
	_shelf_panel.anchor_top = 1.0
	_shelf_panel.anchor_bottom = 1.0
	_shelf_panel.offset_top = -SHELF_BOTTOM_MARGIN
	_shelf_panel.offset_bottom = -SHELF_BOTTOM_MARGIN
	_shelf_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_shelf_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_overlay.add_child(_shelf_panel)
	UiFx.add_drop_shadow(_shelf_panel)

	var shelf_margin := _make_padding_margin()
	_shelf_panel.add_child(shelf_margin)

	# A horizontally-scrolling ScrollContainer reports a near-zero minimum
	# width, which is what lets the bar keep its fixed fraction of the screen
	# instead of being widened by a shelf full of components; the vertical axis
	# is disabled so the bar still sizes itself to the tallest slot.
	_shelf_scroll = ScrollContainer.new()
	_shelf_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_shelf_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	shelf_margin.add_child(_shelf_scroll)
	_shelf_scroll.get_h_scroll_bar().custom_minimum_size.y = SHELF_SCROLLBAR_HEIGHT

	# The h-scrollbar is drawn *inside* the ScrollContainer's rect without the
	# container reserving any height for it, so it would sit on top of the
	# bottom edge of the (bottom-aligned) slot art once the shelf overflows.
	# A strip of dead space under the row keeps the two apart -- reserved
	# unconditionally so the bar doesn't change height the moment a shelf grows
	# past the width.
	var scroll_gutter := MarginContainer.new()
	scroll_gutter.add_theme_constant_override("margin_bottom", int(SHELF_SCROLLBAR_HEIGHT))
	_shelf_scroll.add_child(scroll_gutter)

	_shelf_list = HBoxContainer.new()
	scroll_gutter.add_child(_shelf_list)

	# Anchored top-left rather than centered -- once a per-component menu is
	# open, its position is recomputed every refresh to sit near the cursor
	# (see _position_detail_panel()), which needs a plain top-left origin to
	# reason about rather than fighting a centering anchor/grow combo.
	_detail_panel = PanelContainer.new()
	_detail_panel.theme_type_variation = &"FramedPanel"
	_detail_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_detail_panel.custom_minimum_size = Vector2(320, 0)
	_overlay.add_child(_detail_panel)
	UiFx.add_drop_shadow(_detail_panel)

	var detail_margin := _make_padding_margin()
	_detail_panel.add_child(detail_margin)

	# A ScrollContainer reports its own (near-zero) minimum size regardless
	# of its child's -- _position_detail_panel() sets custom_minimum_size.y
	# explicitly every refresh (content height, capped to what fits on
	# screen), which is what actually drives this panel's real height. Without
	# it, a long Upgrades list would just keep growing the whole window past
	# the bottom of the screen instead of scrolling.
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_margin.add_child(_detail_scroll)

	_detail_box = VBoxContainer.new()
	_detail_scroll.add_child(_detail_box)


func _make_padding_margin() -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, PANEL_PADDING)
	return margin


func _refresh_overlay() -> void:
	if _overlay == null:
		return
	_refresh_shelf()
	_refresh_detail()


func _refresh_shelf() -> void:
	for child in _shelf_list.get_children():
		child.free()
	var defs := _zone_defs()
	for i in defs.size():
		var def := defs[i]
		var slot: ItemSlot = ITEM_SLOT_SCENE.instantiate()
		# SHRINK_END rather than the default FILL: each slot keeps its own
		# art-derived height instead of being stretched to the tallest one, so
		# mismatched components sit on a shared baseline along the bar.
		slot.size_flags_vertical = Control.SIZE_SHRINK_END
		_shelf_list.add_child(slot)
		# Component art is shown at its real pixel size here (unlike the
		# Satchel's uniform 48x48 thumbnails) -- these are the same sprites the
		# player is about to see standing in the room. Trimmed to its opaque
		# bounds first (see IconTrim): the world texture's transparent padding
		# is positioning data, and left in it would both inflate the slot and
		# leave the art slouched against the bottom of it. Defs with no art yet
		# fall back to the default slot size and its placeholder dot.
		var art := IconTrim.trimmed(def.icon)
		if art != null:
			slot.fit_to_icon(art.get_size())
		slot.populate_item(def.display_name, "", "", _storage_count_for_def(def.id), Color.WHITE, art, def.description, true)
		slot.self_modulate = SHELF_HIGHLIGHT_TINT if (_mode == Mode.SHELF and i == _shelf_index) else SHELF_NORMAL_TINT
	_scroll_selection_into_view.call_deferred()


## Keeps the focused slot on-screen as the selection walks past either end of
## the fixed-width bar. Deferred by its caller -- the slots were only just
## added, so their rects are still stale until the next layout pass.
func _scroll_selection_into_view() -> void:
	if _shelf_scroll == null or not is_instance_valid(_shelf_scroll):
		return
	if _shelf_index < 0 or _shelf_index >= _shelf_list.get_child_count():
		return
	var slot := _shelf_list.get_child(_shelf_index)
	if slot is Control:
		_shelf_scroll.ensure_control_visible(slot)


func _refresh_detail() -> void:
	# Freed immediately rather than queue_free() -- a deferred free would
	# still be in the tree (and still counted by get_combined_minimum_size())
	# when _position_detail_panel() measures the panel a few lines down,
	# inflating it with the outgoing content's height on top of the new
	# content's.
	for child in _detail_box.get_children():
		child.free()
	_detail_panel.visible = _mode != Mode.GRID
	match _mode:
		Mode.SHELF:
			_render_shelf_detail()
		Mode.COMPONENT_MENU:
			_render_component_menu_detail()
		Mode.UPGRADES:
			_render_upgrades_detail()
	_position_detail_panel()
	# Minimum-size propagation from freshly-added children is itself deferred
	# a frame in Godot -- reposition (and recompute the scroll cap) once more
	# next frame so the popup doesn't linger at a stale size/position.
	_position_detail_panel.call_deferred()


## Sums each visible direct child's own reported minimum height, plus
## VBoxContainer separation between them -- a manual, always-fresh
## alternative to trusting the container chain's own aggregate (see
## FRAME_TEXTURE_MARGIN's docstring for why).
func _sum_visible_children_height(container: Container) -> float:
	var separation: int = container.get_theme_constant("separation")
	var total := 0.0
	var count := 0
	for child in container.get_children():
		if child is Control and child.visible and not child.is_queued_for_deletion():
			total += child.get_combined_minimum_size().y
			count += 1
	if count > 1:
		total += float(separation) * float(count - 1)
	return total


## SHELF pops the detail panel up above the bottom bar, horizontally centered
## on the focused slot. COMPONENT_MENU/UPGRADES instead pop out near the grid
## cursor -- down/right by default, flipped to stay on-screen.
func _position_detail_panel() -> void:
	if _detail_panel == null or not is_instance_valid(_detail_panel):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size

	# Cap the scroll area to whatever actually fits on screen (leaving room
	# for the panel's own frame/padding and a small edge margin) -- content
	# shorter than that sizes naturally; content taller scrolls instead of
	# pushing the panel off-screen. In SHELF mode "on screen" means the space
	# above the bar, not the whole viewport.
	# `position.y > 0` also gates on the bar having been laid out at all -- on
	# the very first refresh after _build_overlay() it hasn't, and the deferred
	# second call in _refresh_detail() is what lands it in the right place.
	var available_height := viewport_size.y
	if _mode == Mode.SHELF and _shelf_panel != null and _shelf_panel.position.y > 0.0:
		available_height = _shelf_panel.position.y - COMPONENT_MENU_OFFSET.y
	var natural_content_height := _sum_visible_children_height(_detail_box)
	var max_scroll_height := maxf(100.0, available_height - VIEWPORT_EDGE_MARGIN * 2.0 - PANEL_PADDING * 2.0 - FRAME_TEXTURE_MARGIN * 2.0)
	var content_height := minf(natural_content_height, max_scroll_height)
	_detail_scroll.custom_minimum_size.y = content_height

	# Width still reads correctly from the panel's own aggregate (it isn't
	# routed through the height-only custom_minimum_size override above), but
	# height is computed by hand -- see FRAME_TEXTURE_MARGIN's docstring.
	var panel_size := Vector2(
		_detail_panel.get_combined_minimum_size().x,
		content_height + PANEL_PADDING * 2.0 + FRAME_TEXTURE_MARGIN * 2.0
	)

	if _mode == Mode.SHELF:
		var slot_center_x := viewport_size.x * 0.5
		if _shelf_index >= 0 and _shelf_index < _shelf_list.get_child_count():
			var slot := _shelf_list.get_child(_shelf_index)
			if slot is Control:
				slot_center_x = slot.get_global_rect().get_center().x
		_detail_panel.position = Vector2(
			clampf(slot_center_x - panel_size.x * 0.5, VIEWPORT_EDGE_MARGIN, maxf(VIEWPORT_EDGE_MARGIN, viewport_size.x - panel_size.x - VIEWPORT_EDGE_MARGIN)),
			maxf(VIEWPORT_EDGE_MARGIN, available_height - panel_size.y)
		)
		return
	if _cursor == null:
		return

	var screen_pos: Vector2 = viewport.get_canvas_transform() * _cursor.global_position
	var target := screen_pos + COMPONENT_MENU_OFFSET
	if target.x + panel_size.x > viewport_size.x:
		target.x = screen_pos.x - panel_size.x - COMPONENT_MENU_OFFSET.x
	if target.y + panel_size.y > viewport_size.y:
		target.y = screen_pos.y - panel_size.y - COMPONENT_MENU_OFFSET.y
	target.x = clampf(target.x, VIEWPORT_EDGE_MARGIN, maxf(VIEWPORT_EDGE_MARGIN, viewport_size.x - panel_size.x - VIEWPORT_EDGE_MARGIN))
	target.y = clampf(target.y, VIEWPORT_EDGE_MARGIN, maxf(VIEWPORT_EDGE_MARGIN, viewport_size.y - panel_size.y - VIEWPORT_EDGE_MARGIN))
	_detail_panel.position = target


func _render_shelf_detail() -> void:
	var defs := _zone_defs()
	if _shelf_index < 0 or _shelf_index >= defs.size():
		return
	var def := defs[_shelf_index]

	var title := Label.new()
	title.theme_type_variation = &"SubheadingLabel"
	title.text = def.display_name
	_detail_box.add_child(title)

	# custom_minimum_size.x fixes the wrap width up front -- an autowrap Label
	# with no explicit width has a circular minimum-size dependency (reported
	# height depends on the width it'll eventually be given), which produces
	# the same kind of stuck/inflated height FRAME_TEXTURE_MARGIN's docstring
	# describes for the panel as a whole.
	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size.x = DETAIL_CONTENT_WIDTH
	desc.text = def.description
	_detail_box.add_child(desc)

	var owned := Label.new()
	owned.text = "Owned: %d" % _storage_count_for_def(def.id)
	_detail_box.add_child(owned)

	var cost := Label.new()
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD
	cost.custom_minimum_size.x = DETAIL_CONTENT_WIDTH
	cost.text = "Cost: %s" % _describe_cost(def)
	_detail_box.add_child(cost)


func _render_component_menu_detail() -> void:
	var instance := Placement.get_component(_menu_component_id)
	var def := ContentRegistry.get_component_def(instance.def_id) if instance != null else null

	var title := Label.new()
	title.theme_type_variation = &"SubheadingLabel"
	title.text = def.display_name if def != null else _menu_component_id
	_detail_box.add_child(title)

	var rows := _component_menu_rows(def)
	for i in rows.size():
		var button := Button.new()
		button.text = rows[i]
		button.focus_mode = Control.FOCUS_NONE
		_detail_box.add_child(button)
		MenuKeyNav.set_highlight(button, i == _component_menu_index)


func _render_upgrades_detail() -> void:
	var upgrades := ContentRegistry.alembic_upgrades
	for i in upgrades.size():
		var upgrade := upgrades[i]
		var owned_ids: Array = Brewing.alembic_upgrade_ids.get(_menu_component_id, [])
		var owned := upgrade.id in owned_ids
		var state := "Owned (select to remove)" if owned else ("Excluded" if _conflicts_with_owned(owned_ids, upgrade) else "Buy")

		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.text = "%s (%d) — %s\n%s" % [upgrade.display_name, upgrade.cost, state, _summarize_upgrade(upgrade)]
		_detail_box.add_child(button)
		MenuKeyNav.set_highlight(button, i == _upgrades_index)
