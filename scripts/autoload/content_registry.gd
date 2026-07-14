extends Node
## Central id -> Resource lookup for hand-authored content. Autoloaded as
## "ContentRegistry".
##
## Content path lists used to live duplicated inside main.gd; this is the
## single place that loads them, so both main.gd (building menus/buttons) and
## SaveManager (resolving a saved recipe_id/seed_id back to a RecipeDef/SeedDef
## on load) share one source of truth.

const RECIPE_PATHS := [
	"res://data/recipes/minor_healing_draught.tres",
	"res://data/recipes/clarity_tonic.tres",
]
const INGREDIENT_PATHS := [
	"res://data/ingredients/moonpetal.tres",
	"res://data/ingredients/iron_filings.tres",
	"res://data/ingredients/ghostcap_mushroom.tres",
]
const UPGRADE_PATHS := [
	"res://data/upgrades/expanded_stock_shelf.tres",
	"res://data/upgrades/alembic_tune_up.tres",
	"res://data/upgrades/quick_brew_coil.tres",
	"res://data/upgrades/extra_grow_plot.tres",
]
const SEED_PATHS := [
	"res://data/seeds/moonpetal_seed.tres",
]

var recipes: Array[RecipeDef] = []
var ingredients: Array[IngredientDef] = []
var upgrades: Array[UpgradeDef] = []
var seeds: Array[SeedDef] = []

var _recipes_by_id: Dictionary = {}      # id -> RecipeDef
var _ingredients_by_id: Dictionary = {}  # id -> IngredientDef
var _upgrades_by_id: Dictionary = {}     # id -> UpgradeDef
var _seeds_by_id: Dictionary = {}        # id -> SeedDef


func _ready() -> void:
	for path in RECIPE_PATHS:
		var def := load(path) as RecipeDef
		recipes.append(def)
		_recipes_by_id[def.id] = def
	for path in INGREDIENT_PATHS:
		var def := load(path) as IngredientDef
		ingredients.append(def)
		_ingredients_by_id[def.id] = def
	for path in UPGRADE_PATHS:
		var def := load(path) as UpgradeDef
		upgrades.append(def)
		_upgrades_by_id[def.id] = def
	for path in SEED_PATHS:
		var def := load(path) as SeedDef
		seeds.append(def)
		_seeds_by_id[def.id] = def


func get_recipe(id: String) -> RecipeDef:
	return _recipes_by_id.get(id)


func get_ingredient(id: String) -> IngredientDef:
	return _ingredients_by_id.get(id)


func get_upgrade(id: String) -> UpgradeDef:
	return _upgrades_by_id.get(id)


func get_seed(id: String) -> SeedDef:
	return _seeds_by_id.get(id)
