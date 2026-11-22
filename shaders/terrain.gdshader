shader_type spatial;
render_mode unshaded;

// Painted night ground: undergrowth on gentle slopes, layered rock on cuts,
// lit by a fixed moon so it matches the painted foliage.
uniform vec3 grass_col : source_color = vec3(0.04, 0.085, 0.19);
uniform vec3 dirt_col : source_color = vec3(0.06, 0.08, 0.17);
uniform vec3 rock_col : source_color = vec3(0.13, 0.17, 0.3);
uniform vec3 moon_dir = vec3(-0.35, 0.85, 0.25);

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
	vec3 n = normalize(wnorm);
	float slope = 1.0 - n.y;
	float nz = vnoise(wpos.xz * 0.15) * 0.6 + vnoise(wpos.xz * 0.9) * 0.4;
	vec3 ground = mix(grass_col, dirt_col, smoothstep(0.4, 0.9, nz));
	float rock = smoothstep(0.25, 0.45, slope + (nz - 0.5) * 0.12);
	float strata = 0.8 + 0.2 * sin(wpos.y * 2.6 + vnoise(wpos.xz * 0.3) * 5.0);
	vec3 base = mix(ground, rock_col * strata, rock);
	float l = dot(n, normalize(moon_dir)) + (nz - 0.5) * 0.3;
	float shade = mix(0.55, 1.0, smoothstep(0.1, 0.35, l)) + smoothstep(0.75, 0.85, l) * 0.35;
	ALBEDO = base * shade;
}
