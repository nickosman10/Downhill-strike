shader_type sky;

// Photographed night sky (lights the scene and shows in reflections) with a
// crisp star field and moon drawn on top, since stars in a photo this size blur away.
uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform float energy = 0.9;
uniform vec3 moon_dir = vec3(-0.35, 0.55, 0.75);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float stars(vec3 d, float scale, float density, float size) {
	vec2 uv = vec2(atan(d.x, d.z) * scale, asin(clamp(d.y, -1.0, 1.0)) * scale);
	vec2 cell = floor(uv);
	float r = hash(cell);
	vec2 off = vec2(hash(cell + 3.1), hash(cell + 9.7)) - 0.5;
	vec2 f = fract(uv) - 0.5 - off * 0.6;
	return step(1.0 - density, r) * smoothstep(size, 0.0, length(f)) * (0.4 + 0.9 * hash(cell + 7.0));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec2 uv = vec2(atan(d.x, -d.z) / TAU + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
	vec3 col = texture(pano, uv).rgb * energy;
	if (!AT_CUBEMAP_PASS) {
		float vis = smoothstep(0.0, 0.12, d.y);
		vec3 band_n = normalize(vec3(0.35, 0.55, -0.75));
		float band = exp(-pow(dot(d, band_n) * 4.0, 2.0));
		float s = stars(d, 140.0, 0.035 + band * 0.05, 0.16) * 1.3
			+ stars(d, 320.0, 0.06 + band * 0.12, 0.2) * 0.6
			+ stars(d, 60.0, 0.012, 0.12) * 2.2;
		col += mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.92, 0.8), hash(floor(d.xy * 300.0))) * s * vis * 1.4;
		col += vec3(0.05, 0.065, 0.1) * band * vis;
	}
	float m = dot(d, normalize(moon_dir));
	col += vec3(1.0, 0.98, 0.9) * smoothstep(0.9993, 0.9996, m) * 6.0;
	col += vec3(0.4, 0.55, 0.9) * pow(max(m, 0.0), 300.0) * 0.8;
	col += vec3(0.12, 0.2, 0.4) * pow(max(m, 0.0), 12.0) * 0.2;
	COLOR = col;
}
