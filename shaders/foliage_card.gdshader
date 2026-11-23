shader_type spatial;
render_mode unshaded, cull_disabled;

// Leaf / needle cards for trees and bushes: a painted leaf texture cut out by
// its alpha, graded to moonlight, lighter at the top of the canopy.
uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(0.42, 0.56, 0.86);
uniform float brightness = 0.62;

void fragment() {
	vec4 t = texture(leaves, UV);
	if (t.a < 0.45) {
		discard;
	}
	float top = mix(0.75, 1.15, 1.0 - UV.y);
	ALBEDO = t.rgb * tint * brightness * top * COLOR.rgb;
}
