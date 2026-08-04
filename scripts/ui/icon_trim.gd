class_name IconTrim
extends RefCounted
## Crops a Texture2D down to its opaque bounds for display in UI slots.
##
## World sprites are authored with their art anchored inside a larger canvas —
## a component's texture is sized/positioned for where it sits on the room's
## grid (see ComponentDef.icon_offset), so most of them carry a tall band of
## transparency above the art. That padding is load-bearing in the world and
## must not be edited out of the source asset, but in a UI slot it just reads
## as a sprite slumped against the bottom of a mostly-empty box.
##
## The crop is an AtlasTexture region over the *same* source texture rather
## than a new image: no pixels are copied, and the original is left untouched
## for every world-space consumer.

## Trimmed results keyed by source texture. Icons are shared, preloaded
## resources and the set of distinct ones is small and bounded, so this is a
## fixed-size cache in practice — worth having because the alternative is a
## get_image() readback every time a slot list repopulates (Build Mode's shelf
## rebuilds on every keypress).
static var _cache: Dictionary = {}


## The opaque sub-region of `texture`, or `texture` itself when it has no
## transparent border to strip (and `null` for `null`, so callers can pass a
## def's unset icon straight through).
static func trimmed(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	if _cache.has(texture):
		return _cache[texture]
	_cache[texture] = _crop(texture)
	return _cache[texture]


static func _crop(texture: Texture2D) -> Texture2D:
	var image := texture.get_image()
	if image == null:
		return texture
	if image.is_compressed() and image.decompress() != OK:
		return texture
	var used := image.get_used_rect()
	# Fully transparent (get_used_rect() reports an empty rect) or already
	# tight against its own edges — nothing worth wrapping in an atlas for.
	if used.size.x <= 0 or used.size.y <= 0 or used == Rect2i(Vector2i.ZERO, image.get_size()):
		return texture
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(used)
	atlas.filter_clip = true
	return atlas
