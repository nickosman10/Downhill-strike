shader_type sky;

// Clear mountain night: gradient, a dense star field that reaches down to the
// ridgelines (so it shows while driving), a faint Milky Way band, and the moon.
uniform vec3 top_col : source_color = vec3(0.006, 0.012, 0.045);
uniform vec3 horizon_col : source_color = vec3(0.06, 0.1, 0.22);
uniform vec3 moon_dir = vec3(-0.35, 0.55, 0.75);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float stars(vec3 d, float scale, float density, float size) {
	vec2 uv = vec2(atan(d.x, d.z) * scale, asin(clamp(d.y, -1.0, 1.0)) * scale);
	vec2 cell = floor(uv);
	float r = hash(cell);
	vec2 off = vec2(hash(cell + 3.1), hash(cell + 9.7)) - 0.5;
	vec2 f = fract(uv) - 0.5 - off * 0.6;
	float s = step(1.0 - density, r) * smoothstep(size, 0.0, length(f));
	return s * (0.4 + 0.9 * hash(cell + 7.0));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_col, top_col, pow(h, 0.45));
	// stars fade in just above the horizon so they sit over the ridgelines
	float vis = smoothstep(-0.01, 0.08, d.y);
	// Milky Way: a soft band of extra stars and haze across the sky
	vec3 band_n = normalize(vec3(0.35, 0.55, -0.75));
	float band = exp(-pow(dot(d, band_n) * 4.0, 2.0));
	float s = stars(d, 140.0, 0.035 + band * 0.05, 0.16) * 1.3
		+ stars(d, 320.0, 0.06 + band * 0.12, 0.2) * 0.6
		+ stars(d, 60.0, 0.012, 0.12) * 2.2;
	vec3 star_col = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.92, 0.8), hash(floor(d.xy * 300.0)));
	col += star_col * s * vis;
	col += vec3(0.07, 0.09, 0.14) * band * vis * 0.6;
	// moon
	float m = dot(d, normalize(moon_dir));
	col += vec3(1.0, 0.98, 0.9) * smoothstep(0.9993, 0.9996, m) * 3.0;
	col += vec3(0.4, 0.55, 0.9) * pow(max(m, 0.0), 300.0) * 0.8;
	col += vec3(0.15, 0.25, 0.5) * pow(max(m, 0.0), 12.0) * 0.25;
	if (d.y < 0.0) col = mix(horizon_col, vec3(0.01, 0.02, 0.05), clamp(-d.y * 4.0, 0.0, 1.0));
	COLOR = col;
}
