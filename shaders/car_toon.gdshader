shader_type spatial;
#include "toon.gdshaderinc"

// Cel paint for the cars: two flat tones, a hard highlight streak and a cool
// rim light, the way anime draws bodywork.
uniform vec3 color : source_color = vec3(0.8, 0.1, 0.1);
uniform vec3 key_dir = vec3(-0.35, 0.8, 0.45);
uniform float gloss = 1.0;
uniform float glass = 0.0;

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 wv = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 k = normalize(key_dir);
	float nl = dot(wn, k);
	float tone = mix(0.6, 1.0, smoothstep(0.0, 0.03, nl));
	vec3 h = normalize(k + wv);
	// a narrow hard highlight, drawn as a lighter shade of the paint
	float spec = smoothstep(0.985, 0.99, dot(wn, h)) * gloss;
	float rim = smoothstep(0.7, 0.74, 1.0 - dot(wn, wv)) * smoothstep(-0.1, 0.3, wn.y);
	vec3 c = color * tone;
	c = mix(c, color * 1.35 + 0.12, spec * 0.8);
	if (glass > 0.5) {
		// windows: dark, with slanted bands of reflected sky
		float band = sin((wn.x * 2.0 + wn.y * 5.0 + wv.x * 3.0 + wv.y * 2.0) * 3.0);
		c = mix(color, vec3(0.35, 0.5, 0.75), smoothstep(0.72, 0.76, band) * 0.55);
	}
	ALBEDO = c;
	EMISSION = vec3(0.3, 0.42, 0.7) * rim * 0.18;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_light(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, 0.0);
}
