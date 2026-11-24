class_name Mats
extends RefCounted
## Scanned PBR materials (Poly Haven, CC0): colour, normal, roughness and
## ambient occlusion maps. Falls back to plain colour if a map is missing.

static var _cache := {}


## Art style. The game is drawn as a cartoon (cel shading, ink lines); the
## photo-style renderer is kept as an option in the graphics menu.
static var realistic := false


## The photo-style renderer needs its scanned textures, which the standard
## download leaves out to stay small.
static func has_realistic() -> bool:
	return ResourceLoader.exists("res://assets/pbr/asphalt_diff.jpg")


static func hq() -> bool:
	return realistic and RenderingServer.get_rendering_device() != null and has_realistic()


## Cartoon rendering with the full desktop renderer (ink lines need it).
static func toon() -> bool:
	return not hq() and RenderingServer.get_rendering_device() != null


static func tex(name: String, kind: String) -> Texture2D:
	var path := "res://assets/pbr/%s_%s.jpg" % [name, kind]
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


static var _paint: ImageTexture
static var moon_dir := Vector3(-0.35, 0.55, 0.75)


## Soft blotchy noise the cartoon shaders use to break tone edges into brush dabs.
static func paint_tex() -> ImageTexture:
	if _paint == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.035
		n.fractal_octaves = 3
		var img := n.get_seamless_image(256, 256)
		img.generate_mipmaps()
		_paint = ImageTexture.create_from_image(img)
	return _paint


## Turns a standard material into a cel-shaded one: flat colour, a hard edge
## between light and shade, no gloss.
static func toonify(m: StandardMaterial3D) -> StandardMaterial3D:
	if not toon() or m.has_meta("toon") or m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return m
	m.set_meta("toon", true)
	if m.metallic > 0.4:
		# no mirror metal in a drawing: bright flat steel instead
		m.albedo_color = m.albedo_color.lerp(Color(0.8, 0.83, 0.9), 0.35)
	m.metallic = 0.0
	# flat-sided things already shade in flat steps; a hard light edge here
	# would make low headlights flood the road at full strength
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	m.roughness_texture = null
	m.normal_enabled = false
	m.ao_enabled = false
	m.clearcoat_enabled = false
	m.rim_enabled = false
	return m


## Cel-shades every standard material on a node (run for each node that enters the scene).
static func toonify_node(n: Node) -> void:
	if not is_instance_valid(n) or not n is GeometryInstance3D:
		return
	var g := n as GeometryInstance3D
	if g.material_override is StandardMaterial3D:
		toonify(g.material_override)
	var mesh: Mesh = null
	if n is MeshInstance3D:
		mesh = (n as MeshInstance3D).mesh
		if mesh:
			for i in mesh.get_surface_count():
				var om := (n as MeshInstance3D).get_surface_override_material(i)
				if om is StandardMaterial3D:
					toonify(om)
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
		mesh = (n as MultiMeshInstance3D).multimesh.mesh
	if mesh:
		for i in mesh.get_surface_count():
			var sm := mesh.surface_get_material(i)
			if sm is StandardMaterial3D:
				toonify(sm)


## A full PBR material. `scale` repeats the texture across the mesh's UVs.
## In the cartoon style: the painted version of the surface, cel-shaded.
static func pbr(name: String, scale := 1.0, tint := Color.WHITE, rough_mul := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if toon():
		var path := "res://assets/toon/%s.png" % name
		# painted steel is plain: white guardrails read as clean flat shapes
		m.albedo_texture = load(path) if ResourceLoader.exists(path) and name != "metal" else null
		m.albedo_color = Color(minf(tint.r * 1.25, 1.0), minf(tint.g * 1.25, 1.0), minf(tint.b * 1.25, 1.0))
		m.uv1_scale = Vector3(scale, scale, scale)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return toonify(m)
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
