shader_type spatial;
render_mode unshaded, cull_disabled;

// Painted anime-night foliage: hard-edged bands of navy shadow, mid blue and a
// pale moonlit highlight on top, broken up with leafy noise like a BG painting.
uniform vec3 shadow_col : source_color = vec3(0.012, 0.025, 0.07);
uniform vec3 mid_col : source_color = vec3(0.035, 0.08, 0.19);
uniform vec3 light_col : source_color = vec3(0.1, 0.22, 0.45);
uniform vec3 moon_dir = vec3(-0.35, 0.85, 0.25);

varying vec3 wn;
varying vec3 wp;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float l = dot(normalize(wn), normalize(moon_dir));
	float n = vnoise(wp * 1.6) * 0.65 + vnoise(wp * 4.0) * 0.35;
	l += (n - 0.5) * 0.7;
	vec3 c = mix(shadow_col, mid_col, smoothstep(-0.15, -0.05, l));
	c = mix(c, light_col, smoothstep(0.55, 0.62, l));
	ALBEDO = c * COLOR.rgb;
}
