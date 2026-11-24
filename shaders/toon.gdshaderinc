// Cel lighting shared by the cartoon shaders: a hard edge between light and
// shade, and light pools (headlights, lamps) that fall off in steps.
vec3 toon_light(vec3 n, vec3 l, float atten, vec3 light_col, bool directional, float wobble) {
	float nl = dot(n, l) + wobble;
	float band = smoothstep(0.0, 0.04, nl) * 0.7 + smoothstep(0.5, 0.54, nl) * 0.3;
	float a = atten;
	if (directional) {
		a = smoothstep(0.4, 0.55, a);          // crisp cast shadows
	} else {
		// light pools drawn in steps: a faint outer wash, a pool, a bright core
		a = smoothstep(0.004, 0.008, a) * 0.1 + smoothstep(0.05, 0.065, a) * 0.2 + smoothstep(0.25, 0.29, a) * 0.25;
	}
	return light_col * band * a / PI;
}
