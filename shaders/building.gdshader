shader_type spatial;

// House walls: siding with aluminium-frame windows. The facade texture's
// alpha marks window glass; roughly half the windows glow warm at night.
uniform sampler2D facade : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 wall_tint : source_color = vec3(0.8, 0.78, 0.72);
uniform vec3 lamp_col : source_color = vec3(1.0, 0.72, 0.4);
uniform float lit_share = 0.5;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 t = texture(facade, UV);
	vec2 cell = floor(UV * 2.0);
	float on = step(1.0 - lit_share, hash(cell + floor(wpos.xz * 0.05) * 7.0));
	float glass = step(0.5, t.a);
	vec3 dark_glass = vec3(0.04, 0.05, 0.07);
	ALBEDO = mix(t.rgb * wall_tint, mix(dark_glass, t.rgb * 0.3, on), glass);
	EMISSION = t.rgb * lamp_col * glass * on * 1.6;
	ROUGHNESS = mix(0.85, 0.15, glass);
}
