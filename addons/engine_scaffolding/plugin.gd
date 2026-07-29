@tool
extends EditorPlugin
## Adds "Project > Tools > New Interactable..." and "New UI Component..."
## entries that generate the paired .gd + .tscn files for those two
## conventions (see CLAUDE.md's "Exploration layer" and scenes/ui/components
## sections) instead of relying on "copy an existing sibling exactly" tribal
## knowledge. See docs/engine_roadmap.md, Phase 2.

const INTERACTABLE_TEMPLATE := """class_name %sInteractable
extends InteractableBase
## TODO: describe what this interactable does and link its
## docs/design/systems.md section.


func interact(_main: MainScene) -> void:
	pass
"""

const INTERACTABLE_SCENE_TEMPLATE := """[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://scenes/interactables/InteractableBase.tscn" id="1"]
[ext_resource type="Script" path="res://scripts/%s_interactable.gd" id="2"]

[node name="%sInteractable" instance=ExtResource("1")]
script = ExtResource("2")
"""

const UI_COMPONENT_TEMPLATE := """class_name %s
extends PanelContainer
## TODO: describe what this row/component displays and which menu populates it.


func populate() -> void:
	pass
"""

const UI_COMPONENT_SCENE_TEMPLATE := """[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/components/%s.gd" id="1"]

[node name="%s" type="PanelContainer"]
script = ExtResource("1")
"""

var _dialog: ConfirmationDialog
var _name_edit: LineEdit
var _pending_kind: String = ""


func _enter_tree() -> void:
	add_tool_menu_item("New Interactable...", _on_new_interactable)
	add_tool_menu_item("New UI Component...", _on_new_ui_component)


func _exit_tree() -> void:
	remove_tool_menu_item("New Interactable...")
	remove_tool_menu_item("New UI Component...")


func _on_new_interactable() -> void:
	_pending_kind = "interactable"
	_open_dialog("New Interactable", "PascalCase base name, e.g. \"Cauldron\" -> CauldronInteractable")


func _on_new_ui_component() -> void:
	_pending_kind = "ui_component"
	_open_dialog("New UI Component", "PascalCase component name, e.g. \"QuestRewardRow\"")


func _open_dialog(title: String, hint: String) -> void:
	if _dialog == null:
		_dialog = ConfirmationDialog.new()
		var vbox := VBoxContainer.new()
		vbox.name = "VBoxContainer"
		var label := Label.new()
		label.name = "HintLabel"
		vbox.add_child(label)
		_name_edit = LineEdit.new()
		_name_edit.name = "NameEdit"
		_name_edit.placeholder_text = "PascalCase name"
		vbox.add_child(_name_edit)
		_dialog.add_child(vbox)
		_dialog.confirmed.connect(_on_dialog_confirmed)
		get_editor_interface().get_base_control().add_child(_dialog)
	_dialog.title = title
	(_dialog.get_node("VBoxContainer/HintLabel") as Label).text = hint
	_name_edit.text = ""
	_dialog.popup_centered(Vector2i(420, 100))
	_name_edit.grab_focus()


func _on_dialog_confirmed() -> void:
	var raw_name := _name_edit.text.strip_edges()
	if raw_name.is_empty():
		push_warning("Engine Scaffolding: no name entered, nothing generated.")
		return
	if _pending_kind == "interactable":
		_generate_interactable(raw_name)
	elif _pending_kind == "ui_component":
		_generate_ui_component(raw_name)


func _generate_interactable(base_name: String) -> void:
	var snake := _to_snake_case(base_name)
	var script_path := "res://scripts/%s_interactable.gd" % snake
	var scene_path := "res://scenes/interactables/%sInteractable.tscn" % base_name
	if FileAccess.file_exists(script_path) or FileAccess.file_exists(scene_path):
		push_error("Engine Scaffolding: %s or %s already exists." % [script_path, scene_path])
		return
	_write_file(script_path, INTERACTABLE_TEMPLATE % base_name)
	_write_file(scene_path, INTERACTABLE_SCENE_TEMPLATE % [snake, base_name])
	_rescan_and_report(script_path, scene_path)


func _generate_ui_component(base_name: String) -> void:
	var snake := _to_snake_case(base_name)
	var script_path := "res://scripts/ui/components/%s.gd" % snake
	var scene_path := "res://scenes/ui/components/%s.tscn" % base_name
	if FileAccess.file_exists(script_path) or FileAccess.file_exists(scene_path):
		push_error("Engine Scaffolding: %s or %s already exists." % [script_path, scene_path])
		return
	_write_file(script_path, UI_COMPONENT_TEMPLATE % base_name)
	_write_file(scene_path, UI_COMPONENT_SCENE_TEMPLATE % [snake, base_name])
	_rescan_and_report(script_path, scene_path)


func _write_file(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()


func _rescan_and_report(script_path: String, scene_path: String) -> void:
	get_editor_interface().get_resource_filesystem().scan()
	print("Engine Scaffolding: generated %s and %s" % [script_path, scene_path])


## "QuestRewardRow" -> "quest_reward_row"
func _to_snake_case(pascal: String) -> String:
	var result := ""
	for i in pascal.length():
		var c := pascal[i]
		if c == c.to_upper() and c != c.to_lower() and i > 0:
			result += "_"
		result += c.to_lower()
	return result
