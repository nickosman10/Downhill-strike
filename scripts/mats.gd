class_name Mats
extends RefCounted
## Materials for the cartoon look: painted surfaces, cel shading, and the
## settings the scenery reads while it is built.

## Graphics level 0-2 (set by Game): how far detail is drawn, shadows, resolution.
static var quality := 1
## Whether onlookers line the bends (set by the race: battles draw a gallery).
static var crowd := false
static var _paint: ImageTexture
static var moon_dir := Vector3(-0.35, 0.55, 0.75)


## Ink outlines are drawn from the depth and normal buffers, which only the
## desktop renderer provides.
static func can_ink() -> bool:
	return RenderingServer.get_rendering_device() != null


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
	if m.has_meta("toon") or m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
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
	_shadow_budget(g)
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


## Shadows are the dearest thing to draw, since everything that casts one is
## drawn again for each shadow map. Course-long meshes (road, rails, lines)
## and big unculled batches gain nothing from casting, so they don't.
static func _shadow_budget(g: GeometryInstance3D) -> void:
	if g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		return
	if g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm and mm.instance_count > 40 and g.visibility_range_end <= 0.0:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif g is MeshInstance3D and (g as MeshInstance3D).mesh is ArrayMesh:
		var mesh := (g as MeshInstance3D).mesh as ArrayMesh
		if mesh.get_aabb().size.length() > 260.0:
			var verts := 0
			for i in mesh.get_surface_count():
				verts += mesh.surface_get_array_len(i)
			if verts > 20000:
				g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A painted surface (assets/toon/<name>.png), cel-shaded. `scale` repeats the
## texture across the mesh's UVs; `tint` colours it.
static func painted(name: String, scale := 1.0, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var path := "res://assets/toon/%s.png" % name
	# painted steel is plain: white guardrails read as clean flat shapes
	m.albedo_texture = load(path) if ResourceLoader.exists(path) and name != "metal" else null
	m.albedo_color = Color(minf(tint.r * 1.25, 1.0), minf(tint.g * 1.25, 1.0), minf(tint.b * 1.25, 1.0))
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return toonify(m)
