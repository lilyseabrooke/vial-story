shader_type canvas_item;
// Composites the potion icon's Base Color / Tints / Shades stack in one pass,
// each blend explicitly weighted by its own mask alpha (Photoshop's clipping
// mask + layer opacity). Godot's native CanvasItemMaterial Add/Mul blend
// modes were tried first, drawing Tints/Shades as separate Sprite2D layers,
// but MUL ignores the source layer's alpha in its GPU blend factors (result =
// src.rgb * dst.rgb everywhere the sprite draws, not just where shade_mask
// has coverage) -- any non-white RGB sitting in shade_mask's nominally-
// transparent padding (e.g. from the "fix alpha border" import bleed) darkens
// the *entire* icon instead of just the shaded region, reading as a globally
// muted/desaturated result regardless of how vivid base_color is set.
// Mixing explicitly by mask alpha here reproduces the Photoshop result
// exactly and needs only one draw call, avoiding the multi-sprite render-
// order/frame-timing fragility that came with the separate-layer approach too.

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D tint_mask : hint_default_black;
uniform sampler2D shade_mask : hint_default_black;

void fragment() {
	vec4 shape = texture(TEXTURE, UV);
	vec3 color = base_color.rgb;

	vec4 tint = texture(tint_mask, UV);
	color = mix(color, color + tint.rgb, tint.a);

	vec4 shade = texture(shade_mask, UV);
	color = mix(color, color * shade.rgb, shade.a);

	COLOR = vec4(color, shape.a * base_color.a);
}
