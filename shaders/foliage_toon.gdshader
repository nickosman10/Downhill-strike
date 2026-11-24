shader_type spatial;
render_mode cull_disabled;
#include "toon.gdshaderinc"

// Painted leaf masses: solid sculpted volumes shaded in three flat tones,
// with the tone edges broken into leafy dabs.
uniform sampler2D paint : filter_linear_mipmap, repeat_enable;
uniform vec3 base : source_color = vec3(0.13, 0.33, 0.16);
uniform float sway = 1.0;
varying vec3 opos;
varying float wob;

void vertex() {
	opos = VERTEX;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = dot(origin.xz, vec2(0.37, 0.23));
	float h = max(VERTEX.y - 2.0, 0.0);
	VERTEX.x += sin(TIME * 0.8 + phase) * 0.012 * h * sway;
	VERTEX.z += sin(TIME * 0.65 + phase * 1.3) * 0.009 * h * sway;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float n = texture(paint, opos.xz * 0.21 + opos.y * 0.13).r * 0.6 + texture(paint, opos.xy * 0.55 + opos.z * 0.3).r * 0.4;
	wob = (n - 0.5) * 0.9;
	// painted form: light from above, in flat steps, whatever the scene lights do
	float top = wn.y + wob * 0.8;
	float tone = 0.58 + smoothstep(-0.25, -0.2, top) * 0.22 + smoothstep(0.3, 0.35, top) * 0.25 + smoothstep(0.8, 0.84, top) * 0.2;
	ALBEDO = base * COLOR.rgb * tone;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_light(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, wob * 0.5);
}
