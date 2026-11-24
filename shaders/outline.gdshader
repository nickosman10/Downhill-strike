shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Ink lines over the finished picture, like a cel drawing: a line wherever
// the depth breaks (outer silhouettes) or the surface direction changes
// sharply (creases, panel edges, where one thing meets another).
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest, repeat_disable;
uniform vec3 ink : source_color = vec3(0.02, 0.025, 0.06);
uniform float width = 1.3;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

void fragment() {
	vec2 px = width * (VIEWPORT_SIZE.y / 1080.0) / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	float dc = view_depth(uv, INV_PROJECTION_MATRIX);
	float dl = view_depth(uv - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float dr = view_depth(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float du = view_depth(uv - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float dd = view_depth(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	// second difference: zero on any flat surface however steeply it recedes
	float lap = (abs(dl + dr - 2.0 * dc) + abs(du + dd - 2.0 * dc)) / max(dc, 0.1);
	float edge_d = smoothstep(0.02, 0.05, lap);
	vec3 nc = texture(normal_tex, uv).xyz * 2.0 - 1.0;
	vec3 nl = texture(normal_tex, uv - vec2(px.x, 0.0)).xyz * 2.0 - 1.0;
	vec3 nr = texture(normal_tex, uv + vec2(px.x, 0.0)).xyz * 2.0 - 1.0;
	vec3 nu = texture(normal_tex, uv - vec2(0.0, px.y)).xyz * 2.0 - 1.0;
	vec3 nd = texture(normal_tex, uv + vec2(0.0, px.y)).xyz * 2.0 - 1.0;
	float ndiff = max(max(1.0 - dot(nc, nl), 1.0 - dot(nc, nr)), max(1.0 - dot(nc, nu), 1.0 - dot(nc, nd)));
	float edge_n = smoothstep(0.25, 0.45, ndiff);
	float edge = max(edge_d, edge_n);
	// thinner, fainter lines far away so distant forest doesn't turn to scribble
	float nearest = min(min(dc, dl), min(min(dr, du), dd));
	float fade = mix(1.0, 0.0, smoothstep(40.0, 260.0, nearest));
	if (nearest > 3000.0) {
		fade = 0.0;
	}
	ALBEDO = ink;
	ALPHA = edge * fade * 0.92;
}
