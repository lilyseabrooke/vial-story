shader_type canvas_item;
// Full-screen shadow/highlight color-grading pass for RoomLighting (see
// docs/design/systems.md, system 24). Splits the already-rendered world by
// per-pixel luminance and blends toward shadow_tint in the dark end and
// highlight_tint in the bright end, rather than a single CanvasModulate
// multiply that darkens/tints every pixel equally regardless of how bright
// it already is -- that's what let a flat night tint read as crushing/washing
// out everything uniformly. contrast pushes luminance away from mid-gray
// before that blend, so dark/light separation ("pop") can be dialed
// independently of the tint colors themselves and animated across the day
// (see LightingProfileDef.contrast_curve).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec4 shadow_tint : source_color = vec4(1.0);
uniform vec4 highlight_tint : source_color = vec4(1.0);
uniform float contrast : hint_range(0.5, 2.5) = 1.0;

void fragment() {
	vec4 scene_color = texture(screen_texture, SCREEN_UV);
	float luma = dot(scene_color.rgb, vec3(0.299, 0.587, 0.114));
	float graded_luma = clamp((luma - 0.5) * contrast + 0.5, 0.0, 1.0);
	vec3 tint = mix(shadow_tint.rgb, highlight_tint.rgb, graded_luma);
	COLOR = vec4(scene_color.rgb * tint, scene_color.a);
}
