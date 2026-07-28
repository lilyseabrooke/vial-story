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
## Overworld idle/walking sprite sheet (see AlchemistCharacter.tres for the
## expected animation names: IdleDown/Up/Right/Left, WalkingDown/Up/Right/Left).
## Left null for anyone who only ever appears via portrait, or hasn't gotten
## world art yet -- InteractableBase falls back to the tinted placeholder_color
## ColorRect in that case.
@export var sprite_frames: SpriteFrames


## Best available small icon for UI (e.g. GameMenu's Relationships tab):
## portrait if authored, else the IdleDown sprite's first frame, else null so
## the caller can fall back to its own tinted placeholder_color swatch.
func get_icon() -> Texture2D:
	if portrait != null:
		return portrait
	if sprite_frames != null and sprite_frames.has_animation("IdleDown"):
		return sprite_frames.get_frame_texture("IdleDown", 0)
	return null
