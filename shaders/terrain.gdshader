shader_type spatial;
render_mode diffuse_lambert;

// Mountain ground: dark forest floor on gentle slopes, layered rock on cut slopes.
uniform vec3 grass_col : source_color = vec3(0.055, 0.085, 0.045);
uniform vec3 dirt_col : source_color = vec3(0.13, 0.11, 0.08);
uniform vec3 rock_col : source_color = vec3(0.26, 0.25, 0.235);

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float slope = 1.0 - wnorm.y;
	float n = vnoise(wpos.xz * 0.12) * 0.6 + vnoise(wpos.xz * 0.8) * 0.4;
	vec3 ground = mix(grass_col, dirt_col, smoothstep(0.35, 0.9, n));
	float rock = smoothstep(0.22, 0.42, slope + (n - 0.5) * 0.12);
	float strata = 0.8 + 0.2 * sin(wpos.y * 2.6 + vnoise(wpos.xz * 0.3) * 5.0);
	ALBEDO = mix(ground, rock_col * strata * (0.85 + 0.3 * n), rock);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
