class_name PotionRoleSlot
extends PanelContainer
## One drop target in AttemptPuzzlePanel's potion field — the Base, Binder,
## or Catalyst slot of the ingredient combination the player is assembling.
## Accepts a drag from an IngredientDragChip whose ingredient's role matches
## this slot's role; visually reinforces the "always needs a Base" rule via
## a gold accent border on the required slot (see setup()).
##
## Node refs are looked up on demand rather than cached via @onready, same
## convention as item_slot.gd — AttemptPuzzlePanel builds this detached from
## the SceneTree, only reparented in later by MenuScene.open().

signal content_changed

var role: IngredientDef.Role = IngredientDef.Role.BASE
var required: bool = false

var _ingredient_id: String = ""


func setup(slot_role: IngredientDef.Role, is_required: bool) -> void:
	role = slot_role
	required = is_required

	var role_label: Label = $VBox/RoleLabel
	role_label.text = "%s%s" % [_role_name(), " (required)" if required else " (optional)"]

	if required:
		var stylebox := StyleBoxFlat.new()
		stylebox.bg_color = UiPalette.DRIFTWOOD_TAN
		stylebox.border_width_top = 3
		stylebox.border_color = UiPalette.GOLD
		stylebox.set_corner_radius_all(8)
		stylebox.set_content_margin_all(6)
		add_theme_stylebox_override("panel", stylebox)

	clear()


func _ready() -> void:
	var clear_button: Button = $VBox/ClearButton
	clear_button.pressed.connect(clear)


func get_ingredient_id() -> String:
	return _ingredient_id


func is_filled() -> bool:
	return _ingredient_id != ""


func set_ingredient(ingredient_id: String) -> void:
	var ingredient := ContentRegistry.get_ingredient(ingredient_id)
	if ingredient == null:
		return
	_ingredient_id = ingredient_id

	var content_label: Label = $VBox/ContentLabel
	content_label.text = "%s\nWeight %.1f" % [ingredient.display_name, ingredient.weight]

	var clear_button: Button = $VBox/ClearButton
	clear_button.visible = true

	content_changed.emit()


func clear() -> void:
	_ingredient_id = ""

	var content_label: Label = $VBox/ContentLabel
	content_label.text = "— drop a %s here —" % _role_name()

	var clear_button: Button = $VBox/ClearButton
	clear_button.visible = false

	content_changed.emit()


func _role_name() -> String:
	return IngredientDef.Role.keys()[role].capitalize()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("ingredient_id"):
		return false
	var ingredient := ContentRegistry.get_ingredient(data["ingredient_id"])
	return ingredient != null and ingredient.role == role


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	set_ingredient(data["ingredient_id"])
