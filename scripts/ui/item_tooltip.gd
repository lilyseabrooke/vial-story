class_name ItemTooltip
extends RefCounted
## Shared item-mouseover text builder -- the single place the "name / quality
## / type" hover tooltip shown on an inventory grid cell (ItemSlot) and a
## received-item toast (ItemToast) is assembled, so tweaking the format (or
## adding a line) in one place updates both instead of drifting out of sync
## the way two copy-pasted composers would. Static-only: no state, so callers
## use it as `ItemTooltip.compose(...)` without instancing.

## Joins whatever of name/quality/type are non-empty into the native
## Control.tooltip_text format, one per line. quality_label is optional
## (e.g. potions have none); item_name and type_label are always shown.
static func compose(item_name: String, quality_label: String, type_label: String) -> String:
	var lines: Array[String] = [item_name]
	if quality_label != "":
		lines.append(quality_label)
	lines.append(type_label)
	return "\n".join(lines)


## The "Natural Ingredient" / "Draconic Ingredient" / etc. type line shared by
## every ingredient-backed tooltip -- category is an IngredientDef.Category.
static func ingredient_type_label(category: IngredientDef.Category) -> String:
	return "%s Ingredient" % IngredientDef.Category.keys()[category].capitalize()
