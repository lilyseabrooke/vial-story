class_name MessageWall
extends Control
## Bottom-right message wall that replaces the old modal DiceRollPopup and
## the top-right log Label in scripts/hud.gd. Dice results and info notices
## both land here as MessageEntry rows.
##
## Built as a .tscn (scenes/ui/components/MessageWall.tscn), not in code --
## a code-built version hit repeated bugs from the order Control's anchor/
## offset/position/size setters interact (each assignment recomputes the
## others based on current state, so getting the bottom-right placement
## right meant fighting that order rather than just describing the end
## result). The .tscn's anchor_left/top/right/bottom = 1 with fixed
## offset_left/top/right/bottom is the literal placement Godot's own anchor
## preset UI would produce for a 260x260 box 16px off the bottom-right
## corner, and -- being genuinely anchor-based instead of a one-time
## position snapshot -- it also stays correctly placed across window resizes
## with no extra code.
##
## Entries never actually disappear once posted (only dim -- see
## message_entry.gd) so scrolling back always finds history, newest at the
## bottom. The wall itself collapses down to a small icon whenever nothing
## is recent and the mouse isn't over it, and expands back to the scrollable
## list on hover (or immediately whenever a new message arrives).

const MESSAGE_ENTRY_SCENE := preload("res://scenes/ui/components/MessageEntry.tscn")
const MAX_ENTRIES := 50
const RECENT_WINDOW_SECONDS := 5.5

var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty_icon: Control
var _entries: Array[MessageEntry] = []
var _dragging := false
var _drag_start_y := 0.0
var _drag_start_scroll := 0
var _pinned_to_bottom := true
var _wall_hovered := false
var _recent_until_msec := 0


func _ready() -> void:
	_scroll = $Scroll
	_list = $Scroll/List
	_empty_icon = $EmptyIcon

	mouse_entered.connect(func() -> void:
		_wall_hovered = true
		_update_wall_visibility()
	)
	mouse_exited.connect(func() -> void:
		_wall_hovered = false
		_update_wall_visibility()
	)

	_scroll.gui_input.connect(_on_scroll_gui_input)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_value_changed)

	var recheck := Timer.new()
	recheck.wait_time = 0.5
	recheck.autostart = true
	recheck.timeout.connect(_update_wall_visibility)
	add_child(recheck)

	_update_wall_visibility()


## label: what the check is for (e.g. "Brewing", "Class Performance").
func add_dice_result(roll: Dictionary, label: String) -> void:
	var header := "%s: %.1f vs DC %.1f" % [label, roll.total, roll.dc]
	var detail := "d10 %d + d10 %d, modifier %+.1f -- %s" % [
		roll.die_a, roll.die_b, roll.modifier, _dice_result_text(roll),
	]
	_add_entry(header, detail, _dice_accent_color(roll))


func add_notice(text: String) -> void:
	_add_entry(text, "", UiPalette.TEXT_PRIMARY)


func _dice_result_text(roll: Dictionary) -> String:
	if roll.get("inflection_point", false):
		return "...an inflection point."
	elif roll.get("critical_failure", false):
		return "CRITICAL FAILURE"
	elif roll.get("critical_success", false):
		return "CRITICAL SUCCESS!"
	elif roll.passed:
		return "Success!"
	else:
		return "Failed."


func _dice_accent_color(roll: Dictionary) -> Color:
	if roll.get("inflection_point", false):
		return UiPalette.MAGIC
	elif roll.get("critical_failure", false):
		return UiPalette.DANGER
	elif roll.get("critical_success", false):
		return UiPalette.GOLD
	elif roll.passed:
		return UiPalette.SUCCESS
	else:
		return UiPalette.WARNING


func _add_entry(header: String, detail: String, accent: Color) -> void:
	var entry: MessageEntry = MESSAGE_ENTRY_SCENE.instantiate()
	_list.add_child(entry)
	entry.populate(header, detail, accent)
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		var oldest: MessageEntry = _entries.pop_front()
		oldest.queue_free()
	_recent_until_msec = Time.get_ticks_msec() + int(RECENT_WINDOW_SECONDS * 1000)
	_update_wall_visibility()
	if _pinned_to_bottom:
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _update_wall_visibility() -> void:
	var has_entries := not _entries.is_empty()
	var show_list := has_entries and (_wall_hovered or Time.get_ticks_msec() < _recent_until_msec)
	_scroll.visible = show_list
	_empty_icon.visible = not show_list


func _on_scroll_value_changed(_value: float) -> void:
	var bar := _scroll.get_v_scroll_bar()
	_pinned_to_bottom = bar.value >= bar.max_value - bar.page - 1.0


func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var button_event := event as InputEventMouseButton
		_dragging = button_event.pressed
		_drag_start_y = button_event.position.y
		_drag_start_scroll = _scroll.scroll_vertical
	elif event is InputEventMouseMotion and _dragging:
		var motion_event := event as InputEventMouseMotion
		var delta: float = motion_event.position.y - _drag_start_y
		_scroll.scroll_vertical = int(_drag_start_scroll - delta)
