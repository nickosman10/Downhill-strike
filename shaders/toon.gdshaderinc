// Cel lighting shared by the cartoon shaders: a hard edge between light and
// shade, and light pools (headlights, lamps) that fall off in steps.
vec3 toon_light(vec3 n, vec3 l, float atten, vec3 light_col, bool directional, float wobble) {
	float nl = dot(n, l) + wobble;
	float band = smoothstep(0.0, 0.04, nl) * 0.7 + smoothstep(0.5, 0.54, nl) * 0.3;
	float a = atten;
	if (directional) {
		a = smoothstep(0.4, 0.55, a);          // crisp cast shadows
	} else {
		// lamps and headlights: light skims along the ground, so keep the angle
		// falloff and draw the pool in steps: a faint outer wash, a pool, a core
		band = smoothstep(0.0, 0.5, nl);
		a = smoothstep(0.02, 0.03, a) * 0.07 + smoothstep(0.1, 0.12, a) * 0.2 + smoothstep(0.35, 0.39, a) * 0.4;
	}
	return light_col * band * a / PI;
}
