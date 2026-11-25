shader_type spatial;
render_mode cull_disabled;
#include "toon.gdshaderinc"

// Spectators: flat-coloured figures that shift and bounce a little as they watch.
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = dot(origin.xz, vec2(1.7, 2.3));
	float up = smoothstep(0.2, 1.7, VERTEX.y);
	VERTEX.y += abs(sin(TIME * 2.4 + phase)) * 0.03 * up;
	VERTEX.x += sin(TIME * 1.3 + phase * 1.7) * 0.025 * up;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_light(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, 0.0);
}
