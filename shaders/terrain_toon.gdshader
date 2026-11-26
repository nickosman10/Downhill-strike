shader_type spatial;
render_mode cull_back;
#include "toon.gdshaderinc"

// Painted mountain: grass, forest floor and rock in flat tones with brushy
// edges, rock strata on the cuts, and a blanket of tree crowns far away.
uniform sampler2D paint : filter_linear_mipmap, repeat_enable;
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
varying float wob;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (use_corridor > 0.5) {
		vec2 cuv = (wpos.xz - corridor_origin) / corridor_size;
		if (cuv.x > 0.0 && cuv.y > 0.0 && cuv.x < 1.0 && cuv.y < 1.0) {
			vec2 gap = texture(corridor, cuv).rg;
			if (wpos.y > gap.r && wpos.y < gap.g) {
				discard;
			}
		}
	}
	vec3 n = normalize(wnorm);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float n1 = texture(paint, wpos.xz * 0.009).r;
	float n2 = texture(paint, wpos.xz * 0.031 + 0.37).r;
	float n3 = texture(paint, vec2(wpos.x + wpos.z, wpos.y * 1.6) * 0.03).r;
	wob = (n2 - 0.5) * 0.5;
	float slope = 1.0 - n.y + (n1 - 0.5) * 0.16;
	float rock = smoothstep(0.3, 0.33, slope);
	// grass in three painted greens
	vec3 grass = mix(vec3(0.1, 0.24, 0.12), vec3(0.16, 0.36, 0.15), smoothstep(0.48, 0.52, n1));
	grass = mix(grass, vec3(0.25, 0.44, 0.17), smoothstep(0.66, 0.69, n2) * 0.8);
	grass = mix(grass, vec3(0.2, 0.2, 0.12), smoothstep(0.7, 0.73, n1 * 0.6 + n2 * 0.4) * 0.5);      // bare earth
	// rock: bedded layers and darker cracks
	float beds = fract(wpos.y * 0.42 + n3 * 1.6);
	vec3 rk = mix(vec3(0.3, 0.31, 0.36), vec3(0.42, 0.42, 0.46), smoothstep(0.45, 0.5, n3));
	rk *= mix(0.72, 1.0, smoothstep(0.08, 0.14, beds));
	rk = mix(rk, vec3(0.2, 0.3, 0.16), smoothstep(0.6, 0.64, n2) * 0.45);                           // moss
	vec3 alb = mix(grass, rk, rock);
	vec2 auv = (wpos.xz - aerial_origin) / aerial_size;
	if (use_aerial > 0.5 && auv.x > 0.0 && auv.y > 0.0 && auv.x < 1.0 && auv.y < 1.0) {
		// the real colours of the place, reduced to broad washes
		vec3 photo = textureLod(aerial, auv, 1.0).rgb;      // (stored small: only the broad colours are used)
		float lum = dot(photo, vec3(0.3, 0.55, 0.15));
		alb = mix(alb, alb * (photo / max(lum, 0.05)) * (0.6 + lum * 1.2), 0.4 * (1.0 - rock));
		float forest = smoothstep(0.0, 0.05, photo.g - photo.r) * (1.0 - smoothstep(0.35, 0.6, lum));
		float crowns = texture(canopy_tex, wpos.xz / 14.0).r * 0.6 + texture(canopy_tex, wpos.xz / 37.0 + 0.3).r * 0.4;
		vec3 canopy_col = mix(vec3(0.05, 0.13, 0.09), vec3(0.13, 0.3, 0.14), smoothstep(0.45, 0.5, crowns));
		alb = mix(alb, canopy_col, forest * (1.0 - rock) * smoothstep(60.0, 220.0, dist) * 0.9);
	}
	ALBEDO = alb * 0.55;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += toon_light(NORMAL, LIGHT, ATTENUATION, LIGHT_COLOR, LIGHT_IS_DIRECTIONAL, wob);
}
