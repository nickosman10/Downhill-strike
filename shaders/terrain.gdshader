shader_type spatial;
render_mode cull_back;

// Mountain ground, fully lit: scanned forest floor on the flats, scanned rock
// on the cuts, coloured by the real aerial photo, with tree-crown shading on
// distant forest. The road corridor is cut out so nothing shows on the road.
uniform sampler2D forest_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_rough : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D canopy_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D aerial : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 aerial_origin = vec2(0.0);
uniform vec2 aerial_size = vec2(1.0);
uniform float use_aerial = 0.0;
uniform sampler2D corridor : filter_nearest, repeat_disable;
uniform vec2 corridor_origin = vec2(0.0);
uniform vec2 corridor_size = vec2(1.0);
uniform float use_corridor = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	TANGENT = normalize(cross(NORMAL, vec3(0.0, 0.0, 1.0)));
	BINORMAL = normalize(cross(TANGENT, NORMAL));
}

void fragment() {
	if (use_corridor > 0.5) {
		vec2 cuv = (wpos.xz - corridor_origin) / corridor_size;
		if (cuv.x > 0.0 && cuv.y > 0.0 && cuv.x < 1.0 && cuv.y < 1.0 && wpos.y > texture(corridor, cuv).r) {
			discard;
		}
	}
	vec3 n = normalize(wnorm);
	float slope = 1.0 - n.y;
	float rock = smoothstep(0.28, 0.5, slope);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	// two scales of each scan hide the tiling
	vec2 guv = wpos.xz * 0.35;
	vec2 ruv = vec2(wpos.x + wpos.z, wpos.y) * 0.22;
	vec3 fd = mix(texture(forest_diff, guv).rgb, texture(forest_diff, guv * 0.23).rgb, 0.4);
	vec3 rd = mix(texture(rock_diff, ruv).rgb, texture(rock_diff, ruv * 0.21).rgb, 0.4);
	// damp, shaded forest floor: darker and less orange than the dry scan
	fd = mix(vec3(dot(fd, vec3(0.33))), fd, 0.55) * vec3(0.5, 0.56, 0.42);
	vec3 alb = mix(fd, rd * 0.8, rock);
	vec3 nm = mix(texture(forest_nor, guv).rgb, texture(rock_nor, ruv).rgb, rock);
	float rg = mix(texture(forest_rough, guv).r, texture(rock_rough, ruv).r, rock);
	vec2 auv = (wpos.xz - aerial_origin) / aerial_size;
	if (use_aerial > 0.5 && auv.x > 0.0 && auv.y > 0.0 && auv.x < 1.0 && auv.y < 1.0) {
		vec3 photo = texture(aerial, auv).rgb;
		float lum = dot(photo, vec3(0.3, 0.55, 0.15));
		// the real colours of the place tint the scanned surface
		alb = mix(alb, alb * (photo / max(lum, 0.05)) * (0.5 + lum * 1.4), 0.55 * (1.0 - rock));
		// forest seen from afar: a blanket of tree crowns
		float forest = smoothstep(0.0, 0.05, photo.g - photo.r) * (1.0 - smoothstep(0.35, 0.6, lum));
		float crowns = texture(canopy_tex, wpos.xz / 14.0).r * 0.6 + texture(canopy_tex, wpos.xz / 37.0 + 0.3).r * 0.4;
		vec3 canopy_col = mix(vec3(0.015, 0.035, 0.015), vec3(0.09, 0.16, 0.06), crowns);
		float far = smoothstep(60.0, 220.0, dist);
		alb = mix(alb, canopy_col, forest * (1.0 - rock) * far * 0.9);
	}
	ALBEDO = alb;
	ROUGHNESS = rg;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.0 - smoothstep(40.0, 160.0, dist);
	SPECULAR = 0.3;
}
