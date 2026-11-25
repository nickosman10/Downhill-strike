shader_type sky;

// Anime night sky: deep indigo falling to a teal glow on the horizon, a big
// bright moon with a halo, crisp stars and flat painted cloud banks.
uniform vec3 top_col : source_color = vec3(0.006, 0.01, 0.05);
uniform vec3 mid_col : source_color = vec3(0.015, 0.03, 0.12);
uniform vec3 horizon_col : source_color = vec3(0.035, 0.08, 0.2);
uniform vec3 moon_dir = vec3(-0.35, 0.55, 0.75);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 + 9.1) * 0.2;
}

float stars(vec3 d, float scale, float density) {
	vec2 uv = vec2(atan(d.x, d.z) * scale, asin(clamp(d.y, -1.0, 1.0)) * scale);
	vec2 cell = floor(uv);
	float r = hash(cell);
	vec2 f = fract(uv) - 0.5 - (vec2(hash(cell + 3.1), hash(cell + 9.7)) - 0.5) * 0.6;
	float size = 0.08 + 0.12 * hash(cell + 5.0);
	// a round point with a four-point sparkle on the bright ones
	float s = smoothstep(size, size * 0.5, length(f));
	float cross = max(smoothstep(0.02, 0.0, abs(f.x)) * smoothstep(0.4, 0.0, abs(f.y)), smoothstep(0.02, 0.0, abs(f.y)) * smoothstep(0.4, 0.0, abs(f.x)));
	s += cross * step(0.8, hash(cell + 1.7)) * 0.8;
	return step(1.0 - density, r) * s;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_col, mid_col, smoothstep(0.0, 0.25, h));
	col = mix(col, top_col, smoothstep(0.2, 0.8, h));
	float vis = smoothstep(0.0, 0.1, d.y);
	col += vec3(0.9, 0.95, 1.0) * (stars(d, 55.0, 0.14) * 1.8 + stars(d, 120.0, 0.16) * 1.0) * vis;
	// moon: a clean disc, a bright ring of haze, a wide soft glow
	float m = dot(d, normalize(moon_dir));
	float disc = smoothstep(0.9968, 0.9972, m);
	col = mix(col, vec3(1.0, 0.98, 0.88) * 2.2, disc);
	col += vec3(0.5, 0.65, 1.0) * smoothstep(0.985, 0.997, m) * 0.35 * (1.0 - disc);
	col += vec3(0.2, 0.3, 0.6) * pow(max(m, 0.0), 10.0) * 0.3;
	// cloud banks: flat shapes in two tones, lit along the edge by the moon
	vec2 cuv = d.xz / max(d.y + 0.18, 0.05);
	float c = fbm(cuv * 0.9 + vec2(TIME * 0.004, 0.0));
	float cloud = smoothstep(0.56, 0.58, c) * smoothstep(0.02, 0.12, d.y) * (1.0 - smoothstep(0.45, 0.8, d.y));
	vec3 cloud_col = mix(vec3(0.025, 0.04, 0.11), vec3(0.07, 0.1, 0.22), smoothstep(0.64, 0.66, c));
	cloud_col += vec3(0.3, 0.4, 0.6) * pow(max(m, 0.0), 6.0) * 0.3;
	col = mix(col, cloud_col, cloud * 0.9);
	if (d.y < 0.0) {
		col = mix(horizon_col, vec3(0.02, 0.04, 0.1), clamp(-d.y * 4.0, 0.0, 1.0));
	}
	COLOR = col;
}
