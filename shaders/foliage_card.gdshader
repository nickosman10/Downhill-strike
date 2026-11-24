shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

// Leaf / needle cards, lit by the scene: moonlight, headlights and street
// lamps all catch the foliage, and light glows through the leaves.
uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(0.75, 0.9, 0.7);
uniform float brightness = 1.0;
uniform float center_y = 4.0;

void vertex() {
	// rounded normals so a tree shades like one volume, not like flat cards
	NORMAL = normalize(mix(NORMAL, normalize(VERTEX - vec3(0.0, center_y, 0.0)), 0.75));
}

void fragment() {
	vec4 t = texture(leaves, UV);
	ALBEDO = t.rgb * tint * brightness * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.25, 0.4, 0.15);
}
