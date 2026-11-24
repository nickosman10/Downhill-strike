shader_type spatial;
render_mode cull_disabled;

// Leaves and needles of the scanned trees: real twig cards with their own
// normal maps, lit by the scene, glowing where light passes through, and
// stirring gently in the wind.
uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D leaves_nor : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(1.0);
uniform float center_y = 6.0;
uniform float sway = 1.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = dot(origin.xz, vec2(0.37, 0.23));
	float h = max(VERTEX.y, 0.0);
	// whole-crown sway grows with height; twig flutter rides on top
	float bend = sin(TIME * 0.9 + phase) * 0.012 + sin(TIME * 2.3 + phase * 1.7 + VERTEX.y * 0.35) * 0.006;
	VERTEX.x += bend * h * sway;
	VERTEX.z += bend * 0.6 * h * sway;
	VERTEX.y += sin(TIME * 3.1 + VERTEX.x * 2.1 + VERTEX.z * 1.7 + phase) * 0.012 * sway * clamp(h * 0.2, 0.0, 1.0);
	// soften card shading toward the shape of the crown
	NORMAL = normalize(mix(NORMAL, normalize(VERTEX - vec3(0.0, center_y, 0.0)), 0.45));
}

void fragment() {
	vec4 t = texture(leaves, UV);
	ALBEDO = t.rgb * tint * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	NORMAL_MAP = texture(leaves_nor, UV).rgb;
	NORMAL_MAP_DEPTH = 0.8;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.22, 0.32, 0.1);
}
