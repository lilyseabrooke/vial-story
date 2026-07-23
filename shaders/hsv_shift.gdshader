shader_type canvas_item;
// Mirrors Photoshop's Hue/Saturation dialog: hue_shift_degrees is degrees
// around the color wheel (-180..180), saturation_shift/value_shift are
// fractions of the 0..1 S/V range (-1..1). Used by VialGauge to recolor only
// the Resolve fill layer when strained, without touching the frame/glass art.

uniform float hue_shift_degrees : hint_range(-180.0, 180.0) = 0.0;
uniform float saturation_shift : hint_range(-1.0, 1.0) = 0.0;
uniform float value_shift : hint_range(-1.0, 1.0) = 0.0;
// Flash/glow pulse on value change, and the steady strained strobe, are
// driven separately from the strain shift above and from each other so
// their tweens don't fight over one uniform. A CanvasItem's modulate can't
// be used for either: this shader overwrites COLOR outright, so a plain
// node-level modulate tween would be silently discarded. Both tints are
// multiplied in explicitly instead.
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 strobe_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	vec3 hsv = rgb_to_hsv(tex_color.rgb);
	hsv.x = fract(hsv.x + hue_shift_degrees / 360.0);
	hsv.y = clamp(hsv.y + saturation_shift, 0.0, 1.0);
	hsv.z = clamp(hsv.z + value_shift, 0.0, 1.0);
	COLOR = vec4(hsv_to_rgb(hsv), tex_color.a) * tint_color * strobe_tint;
}
