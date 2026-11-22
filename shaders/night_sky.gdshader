shader_type sky;

// Deep blue anime night: gradient, scattered stars, a bright moon with a halo.
uniform vec3 top_col : source_color = vec3(0.005, 0.01, 0.04);
uniform vec3 horizon_col : source_color = vec3(0.05, 0.1, 0.24);
uniform vec3 moon_dir = vec3(-0.35, 0.55, 0.75);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_col, top_col, pow(h, 0.45));
	// stars
	vec2 uv = vec2(atan(d.x, d.z) * 120.0, asin(clamp(d.y, -1.0, 1.0)) * 120.0);
	vec2 cell = floor(uv);
	float r = hash(cell);
	vec2 f = fract(uv) - 0.5;
	float star = step(0.985, r) * smoothstep(0.12, 0.0, length(f)) * smoothstep(0.02, 0.25, d.y);
	col += vec3(0.8, 0.9, 1.0) * star * (0.5 + 0.5 * hash(cell + 7.0));
	// moon
	float m = dot(d, normalize(moon_dir));
	col += vec3(1.0, 0.98, 0.9) * smoothstep(0.9993, 0.9996, m) * 3.0;
	col += vec3(0.4, 0.55, 0.9) * pow(max(m, 0.0), 300.0) * 0.8;
	col += vec3(0.15, 0.25, 0.5) * pow(max(m, 0.0), 12.0) * 0.25;
	if (d.y < 0.0) col = mix(horizon_col, vec3(0.01, 0.02, 0.05), clamp(-d.y * 4.0, 0.0, 1.0));
	COLOR = col;
}
