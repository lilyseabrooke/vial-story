@tool
extends PanelContainer
## Generic content-authoring dock: one registry of content types instead of a
## bespoke "New Ingredient"/"New Potion"/"New Quest"/... dialog per type.
## "New <Type>" instances the right Resource script, saves it via a save
## dialog defaulted to that type's data/ folder, and opens it for editing in
## the stock Inspector -- which already works as a form the moment the
## Resource's @export hints are tight (enums, typed arrays, ranges). Dialogue/
## VN content is explicitly out of scope; it gets its own dedicated tool
## later. See docs/engine_roadmap.md, Phase 5.

## {label, script_path, folder}. Only true Resource-backed content is listed
## here -- the JSON-catalog RefCounted types (AlembicUpgradeDef, CurseDef,
## WaterPumpUpgradeDef, LeyLineSurgeDef, InspirationDef; see
## ContentRegistry's own comments on why those are JSON, not .tres) aren't
## edited through the Inspector at all, so they don't belong in this dock.
const CONTENT_TYPES := [
	{"label": "Ingredient", "script_path": "res://scripts/data/ingredient_def.gd", "folder": "res://data/ingredients/"},
	{"label": "Recipe", "script_path": "res://scripts/data/recipe_def.gd", "folder": "res://data/recipes/"},
	{"label": "Potion", "script_path": "res://scripts/data/potion_def.gd", "folder": "res://data/potions/"},
	{"label": "Seed", "script_path": "res://scripts/data/seed_def.gd", "folder": "res://data/seeds/"},
	{"label": "Upgrade", "script_path": "res://scripts/data/upgrade_def.gd", "folder": "res://data/upgrades/"},
	{"label": "Skill", "script_path": "res://scripts/data/skill_def.gd", "folder": "res://data/skills/"},
	{"label": "Quest", "script_path": "res://scripts/data/quest_def.gd", "folder": "res://data/quests/"},
	{"label": "House", "script_path": "res://scripts/data/house_def.gd", "folder": "res://data/houses/"},
	{"label": "Shop Location", "script_path": "res://scripts/data/shop_location_def.gd", "folder": "res://data/shop_locations/"},
	{"label": "Rift Bundle", "script_path": "res://scripts/data/rift_bundle_def.gd", "folder": "res://data/planar_rifts/"},
	{"label": "Character", "script_path": "res://scripts/data/character_def.gd", "folder": "res://data/characters/"},
	{"label": "Dragon", "script_path": "res://scripts/data/dragon_def.gd", "folder": "res://data/dragons/"},
	{"label": "Scene Trigger", "script_path": "res://scripts/data/scene_trigger_def.gd", "folder": "res://data/scene_triggers/"},
]

var _editor_interface: EditorInterface
var _save_dialog: EditorFileDialog
var _pending_entry: Dictionary = {}


func setup(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	var title := Label.new()
	title.text = "New Content"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	for entry in CONTENT_TYPES:
		var button := Button.new()
		button.text = "New %s..." % entry.label
		button.pressed.connect(_on_new_pressed.bind(entry))
		vbox.add_child(button)


func _on_new_pressed(entry: Dictionary) -> void:
	_pending_entry = entry
	if _save_dialog == null:
		_save_dialog = EditorFileDialog.new()
		_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_save_dialog.add_filter("*.tres", "Resource")
		_save_dialog.file_selected.connect(_on_file_selected)
		add_child(_save_dialog)
	_save_dialog.current_dir = entry.folder
	_save_dialog.current_path = entry.folder
	_save_dialog.popup_centered_ratio(0.6)


func _on_file_selected(path: String) -> void:
	var script := load(_pending_entry.script_path) as Script
	var resource: Resource = script.new()
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("Content Authoring: failed to save %s (error %d)" % [path, err])
		return
	_editor_interface.get_resource_filesystem().scan()
	_editor_interface.edit_resource(resource)
	## Ctrl+S in the editor saves the open scene, not a standalone Resource
	## opened via edit_resource() -- without this, edits made in the
	## Inspector only ever exist in memory and silently revert to this
	## empty placeholder the moment the resource falls out of Inspector
	## history. Auto-save on every edit instead of relying on the user
	## finding the Inspector's own (easy-to-miss) resource-save icon.
	resource.changed.connect(_on_edited_resource_changed.bind(resource, path))
	print("Content Authoring: created %s" % path)


func _on_edited_resource_changed(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("Content Authoring: failed to auto-save %s (error %d)" % [path, err])
