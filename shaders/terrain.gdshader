shader_type spatial;
render_mode unshaded;

// Painted night ground: undergrowth on gentle slopes, layered rock on cuts,
// lit by a fixed moon so it matches the painted foliage.
uniform vec3 grass_col : source_color = vec3(0.04, 0.085, 0.19);
uniform vec3 dirt_col : source_color = vec3(0.06, 0.08, 0.17);
uniform vec3 rock_col : source_color = vec3(0.13, 0.17, 0.3);
uniform vec3 moon_dir = vec3(-0.35, 0.85, 0.25);
// real aerial photo (GSI) draped over the area around the road
uniform sampler2D aerial : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 aerial_origin = vec2(0.0);
uniform vec2 aerial_size = vec2(1.0);
uniform float use_aerial = 0.0;
// close-up surface detail so the ground does not read as flat colour
uniform sampler2D ground_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// tree crowns: forested slopes read as a blanket of canopy, like the real hills
uniform sampler2D canopy_tex : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnorm);
	float slope = 1.0 - n.y;
	float nz = vnoise(wpos.xz * 0.15) * 0.6 + vnoise(wpos.xz * 0.9) * 0.4;
	vec3 ground = mix(grass_col, dirt_col, smoothstep(0.4, 0.9, nz));
	float rock = smoothstep(0.25, 0.45, slope + (nz - 0.5) * 0.12);
	float strata = 0.8 + 0.2 * sin(wpos.y * 2.6 + vnoise(wpos.xz * 0.3) * 5.0);
	vec3 base = mix(ground, rock_col * strata, rock);
	float l = dot(n, normalize(moon_dir)) + (nz - 0.5) * 0.3;
	float shade = mix(0.55, 1.0, smoothstep(0.1, 0.35, l)) + smoothstep(0.75, 0.85, l) * 0.35;
	vec2 auv = (wpos.xz - aerial_origin) / aerial_size;
	if (use_aerial > 0.5 && auv.x > 0.0 && auv.y > 0.0 && auv.x < 1.0 && auv.y < 1.0) {
		vec3 photo = texture(aerial, auv).rgb;
		// moonlit night grade of the real ground colours
		float lum = dot(photo, vec3(0.3, 0.55, 0.15));
		vec3 night = mix(vec3(lum), photo, 0.62) * vec3(0.42, 0.52, 0.85);
		// forest in the photo (greener than it is red, not bright) becomes canopy
		float forest = smoothstep(0.0, 0.05, photo.g - photo.r) * (1.0 - smoothstep(0.35, 0.6, lum));
		float crowns = texture(canopy_tex, wpos.xz / 14.0).r * 0.6 + texture(canopy_tex, wpos.xz / 37.0 + 0.3).r * 0.4;
		vec3 canopy_col = mix(vec3(0.02, 0.05, 0.04), vec3(0.12, 0.2, 0.2), crowns) * vec3(0.8, 0.95, 1.25);
		night = mix(night, canopy_col * (0.7 + photo.g * 1.2), forest * (1.0 - rock) * 0.85);
		// steep cuts read as rock even where the photo shows canopy
		night = mix(night, rock_col * strata, rock * 0.6);
		base = night * 0.8;
	}
	// detail: grass/leaf litter on the flats, layered rock on the cuts
	vec3 g = texture(ground_tex, wpos.xz * 0.22).rgb;
	vec3 rk = texture(rock_tex, vec2(wpos.x + wpos.z, wpos.y) * 0.18).rgb;
	vec3 detail = mix(g / vec3(0.32, 0.44, 0.2), rk / vec3(0.5), rock);
	detail = mix(vec3(1.0), detail, 0.55);
	// fade the detail out with distance so it does not shimmer far away
	float fade = clamp(1.0 - length(wpos - CAMERA_POSITION_WORLD) / 220.0, 0.0, 1.0);
	ALBEDO = base * shade * mix(vec3(1.0), detail, fade);
}
