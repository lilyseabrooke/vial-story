extends Node
## Game-identity: the choices made at new-game creation (character name, shop
## origin). Autoloaded as "PlayerProfile". See docs/design/systems.md, system 14.
##
## Written once via SaveManager.create_new_game() — the hook point for a
## future character-creation UI, not built yet. shop_origin is a plain string
## id rather than a ShopOriginDef lookup key, since that data-driven content
## doesn't exist yet either.

var character_name: String = ""
var shop_origin: String = ""


func get_save_data() -> Dictionary:
	return {
		"character_name": character_name,
		"shop_origin": shop_origin,
	}


func load_save_data(data: Dictionary) -> void:
	character_name = data.get("character_name", "")
	shop_origin = data.get("shop_origin", "")
