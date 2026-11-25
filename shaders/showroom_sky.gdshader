shader_type sky;

// Garage backdrop: a sunburst of flat wedges, like a manga splash page.
void sky() {
	vec3 d = normalize(EYEDIR);
	float ang = atan(d.x, d.z);
	float wedge = step(0.5, fract(ang * 14.0 / 6.28318 + TIME * 0.01));
	vec3 a = vec3(0.05, 0.08, 0.26);
	vec3 b = vec3(0.09, 0.15, 0.42);
	vec3 col = mix(a, b, wedge);
	col = mix(col, vec3(0.16, 0.3, 0.7), smoothstep(0.35, 0.0, abs(d.y)) * 0.55);
	col = mix(col, vec3(0.02, 0.03, 0.1), smoothstep(0.5, 1.0, d.y));
	COLOR = col;
}
