class_name Mats
extends RefCounted
## Scanned PBR materials (Poly Haven, CC0): colour, normal, roughness and
## ambient occlusion maps. Falls back to plain colour if a map is missing.

static var _cache := {}


static func hq() -> bool:
	return RenderingServer.get_rendering_device() != null


static func tex(name: String, kind: String) -> Texture2D:
	var path := "res://assets/pbr/%s_%s.jpg" % [name, kind]
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## A full PBR material. `scale` repeats the texture across the mesh's UVs.
static func pbr(name: String, scale := 1.0, tint := Color.WHITE, rough_mul := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = tex(name, "diff")
	var n := tex(name, "nor")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = 1.0
	var r := tex(name, "rough")
	if r:
		m.roughness_texture = r
		m.roughness = rough_mul
	var ao := tex(name, "ao")
	if ao:
		m.ao_enabled = true
		m.ao_texture = ao
		m.ao_light_affect = 0.4
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
