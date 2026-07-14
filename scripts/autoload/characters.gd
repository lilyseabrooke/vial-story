extends Node
## Registry of CharacterDefs, keyed by id. Autoloaded as "Characters". See
## docs/design/systems.md, system 13.
##
## Purely presentational data for DialogueBox (display name, placeholder
## color) — has no relationship to LoveInterests' affection ledger, which
## tracks any string id regardless of whether it's registered here.

const CHARACTER_PATHS := [
	"res://data/characters/kaelith.tres",
]

var _characters: Dictionary = {}   # id -> CharacterDef


func _ready() -> void:
	for path in CHARACTER_PATHS:
		var character_def := load(path) as CharacterDef
		_characters[character_def.id] = character_def


func get_character(character_id: String) -> CharacterDef:
	return _characters.get(character_id, null)
