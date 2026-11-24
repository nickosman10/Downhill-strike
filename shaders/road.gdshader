shader_type spatial;

// Damp mountain tarmac: scanned asphalt with darker wet patches and shallow
// puddles that mirror headlights, lamps and the sky.
uniform sampler2D diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.55, 0.55, 0.57);
uniform float wetness = 0.85;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * 2.0;
	vec3 a = texture(diff, uv).rgb * tint;
	float r = texture(rough, uv).r;
	// broad damp areas, and puddles in the low spots of the scan
	float damp = smoothstep(0.35, 0.7, vnoise(wpos.xz * 0.07) * 0.6 + vnoise(wpos.xz * 0.31) * 0.4) * wetness;
	float low = 1.0 - texture(ao, uv).r;
	float puddle = smoothstep(0.48, 0.62, vnoise(wpos.xz * 0.45 + 13.0) * 0.75 + low * 0.9) * wetness;
	ALBEDO = a * mix(1.0, 0.55, max(damp, puddle));
	ROUGHNESS = mix(mix(r * 0.85, 0.3, damp), 0.04, puddle);
	NORMAL_MAP = texture(nor, uv).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.05, puddle);
	AO = texture(ao, uv).r;
	SPECULAR = mix(0.4, 0.7, max(damp, puddle));
}
