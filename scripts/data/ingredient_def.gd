class_name IngredientDef
extends Resource
## Static definition of an ingredient. See docs/design/systems.md, system 2.
##
## role/weight/characteristic_ids+values don't do anything by themselves —
## they only matter to a RecipeDef's puzzle_constraint_* arrays (system 3),
## which score a chosen combination of ingredients against them when the
## player attempts to discover an unlearned recipe.

enum Category { NATURAL, ARTIFICIAL, SPECTRAL, DEMONIC, DRACONIC, EXTRAPLANAR }
enum SourceMethod { BUY, GROW, CRAFT, SUMMON, FORAGE }
enum Role { BASE, BINDER, CATALYST }

## Placeholder tint per category — used wherever a category needs a color
## before real per-item/per-location art exists (e.g. CharacterCreator's
## shop-location tiles). Hand-tuned rather than Godot's named Color constants:
## PLUM read as pink and GOLD as canary yellow at this size, and forest is
## nudged toward blue-green to read distinctly from teal.
const CATEGORY_COLORS := {
	Category.NATURAL: Color(0.1925, 0.55, 0.4309),      # blue-shifted forest
	Category.ARTIFICIAL: Color(0.831, 0.686, 0.216),    # metallic gold, not canary
	Category.SPECTRAL: Color(0.8157, 0.9412, 0.7529),   # tea green
	Category.DEMONIC: Color(0.549, 0.353, 0.706),       # deep plum-purple, not pink
	Category.DRACONIC: Color.CRIMSON,
	Category.EXTRAPLANAR: Color.TEAL,
}

@export var id: String
@export var display_name: String
@export var icon: Texture2D
@export var category: Category = Category.NATURAL
@export var tier: int = 1
@export var source_methods: Array[SourceMethod] = [SourceMethod.BUY]
@export var buy_price: int = 0

@export var role: Role = Role.BASE
@export var weight: float = 1.0
## Parallel arrays rather than a Dictionary export, same convention as
## RecipeDef's ingredient_ids/ingredient_quantities — keeps .tres files
## simple to hand-author. Characteristic ids are free-form strings (e.g.
## "astral", "necromantic", "dream") defined implicitly by whichever recipe
## puzzles reference them; an id with no entry here is just 0.
@export var characteristic_ids: Array[String] = []
@export var characteristic_values: Array[int] = []


func characteristic_value(characteristic_id: String) -> int:
	var idx := characteristic_ids.find(characteristic_id)
	return characteristic_values[idx] if idx != -1 else 0


static func role_from_name(role_name: String) -> Role:
	return Role.keys().find(role_name.to_upper()) as Role
