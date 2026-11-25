shader_type canvas_item;

// Manga backing for the menus: an ink wash on the left that breaks up into
// halftone dots, a slanted colour band behind the title, and thin speed
// lines streaking across the picture.
uniform float band = 1.0;

void fragment() {
	vec2 uv = UV;
	vec2 px = FRAGCOORD.xy;
	// ink wash from the left, dissolving into dots
	float wash = 1.0 - smoothstep(0.12, 0.5, uv.x + uv.y * 0.12);
	vec2 cell = px / 11.0;
	vec2 rot = vec2(cell.x * 0.7071 - cell.y * 0.7071, cell.x * 0.7071 + cell.y * 0.7071);
	float dot_r = length(fract(rot) - 0.5);
	float dots = 1.0 - smoothstep(wash * 0.72 - 0.04, wash * 0.72 + 0.04, dot_r);
	float a = max(smoothstep(0.45, 1.0, wash) * 0.9, dots * 0.85);
	vec3 col = vec3(0.03, 0.04, 0.13);
	// slanted band behind the title
	float s = uv.y + uv.x * 0.22;
	float in_band = step(0.085, s) * step(s, 0.3) * step(uv.x + uv.y * 0.5, 0.92) * band;
	float edge = smoothstep(0.62, 0.92, uv.x + uv.y * 0.5);
	float band_dots = 1.0 - smoothstep((1.0 - edge) * 0.75 - 0.04, (1.0 - edge) * 0.75 + 0.04, dot_r);
	float band_a = in_band * mix(1.0, band_dots, step(0.62, uv.x + uv.y * 0.5));
	col = mix(col, vec3(0.9, 0.12, 0.22), band_a * 0.92);
	a = max(a, band_a * 0.92);
	// speed lines
	float row = floor(uv.y * 90.0);
	float h = fract(sin(row * 91.7) * 43758.5453);
	float x = fract(uv.x * (0.6 + h) - TIME * (0.25 + h * 0.6) + h * 7.0);
	float line = step(0.93, h) * smoothstep(0.0, 0.25, x) * smoothstep(0.5, 0.25, x) * step(0.35, uv.x);
	col = mix(col, vec3(1.0), line * 0.8);
	a = max(a, line * 0.5);
	COLOR = vec4(col, a);
}
