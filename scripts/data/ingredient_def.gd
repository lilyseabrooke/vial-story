class_name IngredientDef
extends Resource
## Static definition of an ingredient. See docs/design/systems.md, system 2.

enum Category { NATURAL, ARTIFICIAL, SPECTRAL, DEMONIC, DRACONIC, EXTRAPLANAR }
enum SourceMethod { BUY, GROW, CRAFT, SUMMON, FORAGE }

@export var id: String
@export var display_name: String
@export var icon: Texture2D
@export var category: Category = Category.NATURAL
@export var tier: int = 1
@export var source_methods: Array[SourceMethod] = [SourceMethod.BUY]
@export var buy_price: int = 0
