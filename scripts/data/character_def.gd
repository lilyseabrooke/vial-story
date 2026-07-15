class_name CharacterDef
extends Resource
## Static display data for anyone who can appear in a VN scene — love
## interest or not. See docs/design/systems.md, system 13.
##
## Deliberately has no romance-specific fields (no is_love_interest flag,
## no route/unlock data) — whether a character accumulates affection is
## entirely up to whether a dialogue script calls add_affection() for their
## id, not something this resource needs to declare. `id` must match the
## character name used in scene scripts' `enter`/`exit`/`move`/`expression`
## stage directions and `Speaker: "text"` lines exactly.

@export var id: String
@export var display_name: String
@export var portrait: Texture2D
@export var placeholder_color: Color = Color.WHITE
