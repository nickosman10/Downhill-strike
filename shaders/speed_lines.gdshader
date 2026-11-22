shader_type canvas_item;
// Anime-style radial speed lines that fade in with speed.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float time_s = 0.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 p = UV - vec2(0.5, 0.45);
	p.x *= 16.0 / 9.0;
	float ang = atan(p.y, p.x);
	float r = length(p);
	float slot = floor((ang + 3.14159) / 6.28318 * 180.0);
	float h = hash(slot + floor(time_s * 14.0) * 0.37);
	float line = step(0.82, h);
	float fade = smoothstep(0.32, 0.75, r);
	float a = line * fade * intensity * 0.35;
	COLOR = vec4(0.9, 0.95, 1.0, a);
}
