class_name PotionIcon
extends Node2D
## Composited potion icon: Back/MidComposite/Front (+ an optional Glow for the
## legendary tier) reproduce the Photoshop layer stack — Base Color, Tints
## (Add), Shades (Mul), each clipped to its own mask's alpha coverage.
## MidComposite does that blending in one shader pass (shaders/potion_icon_mid.gdshader)
## rather than as separate Sprite2Ds with native CanvasItemMaterial blend
## modes: Godot's native MUL blend ignores the source layer's alpha in its GPU
## blend factors, so any non-white RGB in a mask's "transparent" padding
## darkened the whole icon instead of just its intended region. Plain Node2D
## root, not CanvasGroup: this scene is only ever instanced offscreen inside
## ContentRegistry's dedicated bake SubViewport (see _bake_potion_icons()) and
## captured once into a flat Texture2D, never placed live in the actual UI.
## Node refs are looked up on demand rather than cached via @onready to match
## ItemSlot/IngredientChip's populate() convention.

const TIER_NAMES: Array[String] = ["basic", "standard", "advanced", "legendary"]
const LEGENDARY_LEVEL := 4


func populate(level: int, color: Color) -> void:
	var tier := TIER_NAMES[level - 1]
	var base_path := "res://assets/ui/icons/potion_icons/%s/" % tier

	var back: Sprite2D = $Back
	var mid: Sprite2D = $MidComposite
	var front: Sprite2D = $Front
	var glow: Sprite2D = $Glow

	back.texture = load(base_path + "back.png")

	mid.texture = load(base_path + "base_shape.png")
	var mid_material: ShaderMaterial = mid.material
	mid_material.set_shader_parameter("base_color", color)
	mid_material.set_shader_parameter("tint_mask", load(base_path + "tints.png"))
	mid_material.set_shader_parameter("shade_mask", load(base_path + "shades.png"))

	front.texture = load(base_path + "front.png")

	var glow_path := base_path + "legendary_glow.png"
	if level == LEGENDARY_LEVEL and ResourceLoader.exists(glow_path):
		glow.texture = load(glow_path)
		glow.modulate = color
		glow.visible = true
	else:
		glow.texture = null
		glow.visible = false
