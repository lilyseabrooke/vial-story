extends Node
## Game-identity: the choices made at new-game creation (character name,
## pronouns, House, shop origin, player color). Autoloaded as "PlayerProfile".
## See docs/design/systems.md, system 14.
##
## Written once via SaveManager.create_new_game(), called by
## scripts/character_creator.gd. shop_origin is a ShopLocationDef id
## (resolve via ContentRegistry.get_shop_location()); house_id is a HouseDef
## id (ContentRegistry.get_house()). pronouns is a plain string
## ("she_her"/"he_him"/"they_them") rather than an enum int, so the JSON save
## stays human-readable and stable across any future reordering.
## player_color_hex round-trips a Color through Color.to_html()/Color(hex),
## since Color isn't JSON-native.

var character_name: String = ""
var pronouns: String = ""
var house_id: String = ""
var shop_origin: String = ""
var player_color_hex: String = "2199ff"


func get_save_data() -> Dictionary:
	return {
		"character_name": character_name,
		"pronouns": pronouns,
		"house_id": house_id,
		"shop_origin": shop_origin,
		"player_color_hex": player_color_hex,
	}


func load_save_data(data: Dictionary) -> void:
	character_name = data.get("character_name", "")
	pronouns = data.get("pronouns", "")
	house_id = data.get("house_id", "")
	shop_origin = data.get("shop_origin", "")
	player_color_hex = data.get("player_color_hex", "2199ff")
