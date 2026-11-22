class_name Scenery
extends RefCounted
## Roadside dressing in the style of the First Stage night backgrounds:
## painted foliage, concrete retaining walls with chain-link fences on the
## hillside, wooden utility poles with sagging wires, red/white delineators at
## hairpins, red rumble stripes before corners, distant ridges.

var t: Track
var rng := RandomNumberGenerator.new()
var foliage_mat: ShaderMaterial
var wall_sides := {}      # Vector2i(i, side) -> true where a wall stands


func build(track: Track) -> void:
	t = track
	rng.seed = hash(t.course.get("id", "x"))
	foliage_mat = ShaderMaterial.new()
	foliage_mat.shader = load("res://shaders/foliage.gdshader")
	_walls()
	_trees()
	_bushes()
	_poles()
	_delineators()
	_rumble_strips()
	_ridges()


func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _add(n: Node) -> void:
	t.add_child(n)


func _mm(mesh: Mesh, xf: Array, mat: Material, colors: Array = [], vis_end := 0.0) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for k in xf.size():
		mm.set_instance_transform(k, xf[k])
		if mm.use_colors:
			mm.set_instance_color(k, colors[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
	_add(mmi)


## Chunked multimesh so far-away parts are culled.
func _mm_chunked(mesh: Mesh, xf: Array, mat: Material, colors: Array, chunk: float, vis_end: float) -> void:
	var buckets := {}
	for k in xf.size():
		var o: Vector3 = xf[k].origin
		var key := Vector2i(floori(o.x / chunk), floori(o.z / chunk))
		if not buckets.has(key):
			buckets[key] = [[], []]
		buckets[key][0].append(xf[k])
		buckets[key][1].append(colors[k] if colors.size() > 0 else Color.WHITE)
	for key in buckets:
		_mm(mesh, buckets[key][0], mat, buckets[key][1], vis_end)


# ------------------------------------------------------------------ meshes

func _blob_mesh(lumps: int, spread: float, radius: float, seed_v: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var sphere := SphereMesh.new()
	sphere.radial_segments = 9
	sphere.rings = 5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in lumps:
		var s := radius * r.randf_range(0.6, 1.0)
		var off := Vector3(r.randf_range(-spread, spread), r.randf_range(-0.3, 0.6) * spread, r.randf_range(-spread, spread))
		if k == 0:
			off = Vector3.ZERO
			s = radius
		st.append_from(sphere, 0, Transform3D(Basis().scaled(Vector3(s, s * 0.85, s)), off))
	return st.commit()


func _tree_mesh(seed_v: int) -> ArrayMesh:
	# deciduous: trunk + clustered canopy
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.28
	trunk.height = 5.0
	trunk.radial_segments = 5
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 2.5, 0)))
	var canopy := _blob_mesh(6, 1.6, 2.4, seed_v)
	st.append_from(canopy, 0, Transform3D(Basis(), Vector3(0, 6.2, 0)))
	return st.commit()


func _cedar_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.25
	trunk.height = 4.0
	trunk.radial_segments = 5
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 2.0, 0)))
	for k in 4:
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 2.2 - k * 0.45
		c.height = 4.2 - k * 0.5
		c.radial_segments = 9
		st.append_from(c, 0, Transform3D(Basis(), Vector3(0, 3.6 + k * 2.3 + c.height * 0.5, 0)))
	return st.commit()


# ------------------------------------------------------------------ pieces

func _walls() -> void:
	# concrete retaining wall wherever the hillside rises above the road
	var concrete := _mat(Color(0.3, 0.34, 0.42), 0.95)
	var tex := _panel_texture()
	concrete.albedo_texture = tex
	concrete.cull_mode = BaseMaterial3D.CULL_DISABLED
	var fence_mat := _mat(Color(0.55, 0.6, 0.7), 0.6)
	fence_mat.albedo_texture = _fence_texture()
	fence_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fence_mat.alpha_scissor_threshold = 0.5
	fence_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fence_mat.uv1_scale = Vector3(1, 1, 1)
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := t.P.size()
	var post_xf: Array = []
	for side: float in [-1.0, 1.0]:
		var heights := PackedFloat32Array()
		heights.resize(n)
		for i in n:
			var probe := t.P[i] + t.R[i] * side * (t.rail + 5.0)
			heights[i] = clampf(t.terrain_height(probe.x, probe.z) - t.P[i].y, 0.0, 4.2)
		# smooth so the wall top runs cleanly
		for pass_i in 2:
			for i in range(1, n - 1):
				heights[i] = (heights[i - 1] + heights[i] * 2.0 + heights[i + 1]) * 0.25
		var lat: float = side * (t.rail + 0.9)
		for i in range(1, n):
			var h0 := heights[i - 1]
			var h1 := heights[i]
			if h0 < 1.4 and h1 < 1.4:
				continue
			wall_sides[Vector2i(i, int(side))] = true
			var a := t.P[i - 1] + t.R[i - 1] * lat
			var b := t.P[i] + t.R[i] * lat
			var u0 := t.S[i - 1] / 3.0
			var u1 := t.S[i] / 3.0
			var top_a := a + Vector3.UP * maxf(h0, 0.3)
			var top_b := b + Vector3.UP * maxf(h1, 0.3)
			var bot_a := a + Vector3.DOWN * 0.8
			var bot_b := b + Vector3.DOWN * 0.8
			var nrm: Vector3 = -t.R[i] * side
			wst.set_normal(nrm)
			_quad(wst, bot_a, bot_b, top_b, top_a, Vector2(u0, (h0 + 0.8) / 3.0), Vector2(u1, (h1 + 0.8) / 3.0), side)
			# wall cap and chain-link fence on top
			var back_a := top_a + t.R[i - 1] * side * 0.4
			var back_b := top_b + t.R[i] * side * 0.4
			wst.set_normal(Vector3.UP)
			_quad(wst, top_a, top_b, back_b, back_a, Vector2(u0, 0.1), Vector2(u1, 0.1), side)
			fst.set_normal(nrm)
			_quad(fst, top_a, top_b, top_b + Vector3.UP * 1.6, top_a + Vector3.UP * 1.6, Vector2(u0 * 2.0, 1), Vector2(u1 * 2.0, 1), side)
			if int(t.S[i] / 3.0) != int(t.S[i - 1] / 3.0):
				post_xf.append(Transform3D(Basis(), top_b + Vector3.UP * 0.8))
	wst.set_material(concrete)
	fst.set_material(fence_mat)
	var wm := MeshInstance3D.new()
	wm.mesh = wst.commit()
	_add(wm)
	var fm := MeshInstance3D.new()
	fm.mesh = fst.commit()
	_add(fm)
	var post := CylinderMesh.new()
	post.top_radius = 0.035
	post.bottom_radius = 0.035
	post.height = 1.7
	post.radial_segments = 5
	_mm(post, post_xf, _mat(Color(0.5, 0.55, 0.65), 0.5))


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv0: Vector2, uv1: Vector2, side: float) -> void:
	# a-b bottom edge along the road, c-d top edge; faces toward the road.
	# uv0/uv1 give (u, v_bottom) at a and b; the top edge is v = 0.
	var verts := [[a, Vector2(uv0.x, uv0.y)], [b, Vector2(uv1.x, uv1.y)], [c, Vector2(uv1.x, 0)], [d, Vector2(uv0.x, 0)]]
	var order := [0, 1, 2, 0, 2, 3] if side > 0.0 else [0, 2, 1, 0, 3, 2]
	for k in order:
		st.set_uv(verts[k][1])
		st.add_vertex(verts[k][0])


func _panel_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var v := 0.85 + 0.15 * sin(x * 0.7 + y * 1.3) * 0.2
			if x % 32 < 2 or y % 32 < 2:
				v = 0.55
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _fence_texture() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var a := 0.0
			if (x + y) % 8 == 0 or (x - y + 64) % 8 == 0:
				a = 1.0
			if y < 2 or y > 29:
				a = 1.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _trees() -> void:
	var meshes := [_tree_mesh(1), _tree_mesh(2), _cedar_mesh()]
	var sets := [[], [], []]
	var cols := [[], [], []]
	for k in range(0, t.tree_data.size(), 4):
		var p := Vector3(t.tree_data[k], t.tree_data[k + 1] - 0.4, t.tree_data[k + 2])
		var sc: float = t.tree_data[k + 3]
		var kind := 2 if rng.randf() < 0.3 else rng.randi_range(0, 1)
		var b := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(sc, sc * rng.randf_range(0.85, 1.3), sc) * 1.3)
		sets[kind].append(Transform3D(b, p))
		var v := rng.randf_range(0.8, 1.15)
		cols[kind].append(Color(v, v * rng.randf_range(0.95, 1.1), v))
	for kind in 3:
		_mm_chunked(meshes[kind], sets[kind], foliage_mat, cols[kind], 160.0, 600.0)


func _bushes() -> void:
	# dense painted bushes along the verge, thickest on hairpin inner islands
	var meshes := [_blob_mesh(5, 0.9, 1.0, 11), _blob_mesh(4, 0.7, 0.8, 12)]
	var xf := [[], []]
	var cols := [[], []]
	var n := t.P.size()
	for i in range(0, n, 2):
		for side: float in [-1.0, 1.0]:
			if wall_sides.has(Vector2i(i, int(side))) or wall_sides.has(Vector2i(i + 1, int(side))):
				continue
			var inner: bool = signf(t.K[i]) == side and absf(t.K[i]) > 1.0 / 40.0
			var count := 5 if inner else 3
			for c in count:
				if rng.randf() > (0.9 if inner else 0.6):
					continue
				var off: float = t.rail + rng.randf_range(0.9, 14.0 if inner else 11.0)
				var p: Vector3 = t.P[i] + t.R[i] * side * off + t.D[i] * rng.randf_range(-1.0, 1.0)
				p.y = t.terrain_height(p.x, p.z) - 0.2
				if absf(p.y - t.P[i].y) > 9.0:
					continue
				var sc := rng.randf_range(0.8, 1.6) * (1.0 + (off - t.rail) * 0.05)
				var k := rng.randi_range(0, 1)
				xf[k].append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(sc, sc, sc)), p))
				var v := rng.randf_range(0.85, 1.2)
				cols[k].append(Color(v, v, v))
	for k in 2:
		_mm_chunked(meshes[k], xf[k], foliage_mat, cols[k], 120.0, 450.0)


func _poles() -> void:
	# wooden utility poles on one side, with sagging wires between them
	var wood := _mat(Color(0.2, 0.17, 0.15), 0.9)
	var wire_mat := _mat(Color(0.05, 0.05, 0.07), 0.8)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.12
	pole.bottom_radius = 0.16
	pole.height = 9.0
	pole.radial_segments = 6
	var arm := BoxMesh.new()
	arm.size = Vector3(1.6, 0.1, 0.1)
	var pole_xf: Array = []
	var arm_xf: Array = []
	var wires := SurfaceTool.new()
	wires.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := -1.0
	var last_top := Vector3.INF
	var last_r := Vector3.ZERO
	var next_s := 20.0
	for i in t.P.size():
		if t.S[i] < next_s:
			continue
		next_s = t.S[i] + 38.0
		if wall_sides.has(Vector2i(i, int(side))) or absf(t.K[i]) > 1.0 / 30.0:
			last_top = Vector3.INF
			continue
		var base: Vector3 = t.P[i] + t.R[i] * side * (t.rail + 1.6)
		base.y = minf(t.terrain_height(base.x, base.z), t.P[i].y + 0.5) - 0.3
		pole_xf.append(Transform3D(Basis(), base + Vector3.UP * 4.5))
		var top := base + Vector3.UP * 8.6
		arm_xf.append(Transform3D(Basis.looking_at(t.D[i], Vector3.UP), top))
		if last_top != Vector3.INF and last_top.distance_to(top) < 60.0:
			for w in [-0.65, 0.0, 0.65]:
				var a: Vector3 = last_top + last_r * w
				var b: Vector3 = top + t.R[i] * w
				var segs := 6
				for k in segs:
					var f0 := float(k) / segs
					var f1 := float(k + 1) / segs
					var p0 := a.lerp(b, f0) + Vector3.DOWN * (sin(f0 * PI) * 0.9)
					var p1 := a.lerp(b, f1) + Vector3.DOWN * (sin(f1 * PI) * 0.9)
					var up := Vector3.UP * 0.025
					wires.add_vertex(p0 - up); wires.add_vertex(p1 - up); wires.add_vertex(p1 + up)
					wires.add_vertex(p0 - up); wires.add_vertex(p1 + up); wires.add_vertex(p0 + up)
		last_top = top
		last_r = t.R[i]
	_mm(pole, pole_xf, wood)
	_mm(arm, arm_xf, wood)
	wire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wires.set_material(wire_mat)
	var wm := MeshInstance3D.new()
	wm.mesh = wires.commit()
	_add(wm)


func _delineators() -> void:
	# red/white striped poles on the inside of every hairpin
	var img := Image.create(4, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 4:
			img.set_pixel(x, y, Color(0.9, 0.08, 0.06) if (y / 4) % 2 == 0 else Color(0.95, 0.95, 0.95))
	var m := _mat(Color.WHITE, 0.5)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.emission_enabled = true
	m.emission_texture = m.albedo_texture
	m.emission = Color(0.25, 0.25, 0.25)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.04
	pole.height = 1.6
	pole.radial_segments = 6
	var xf: Array = []
	var i := 0
	var n := t.P.size()
	while i < n:
		if absf(t.K[i]) < 1.0 / 25.0:
			i += 1
			continue
		var j := i
		while j < n and absf(t.K[j]) >= 1.0 / 25.0:
			j += 1
		var side := signf(t.K[i])
		for c in 3:
			var m_i := i + int((j - i) * (c + 0.5) / 3.0)
			var p: Vector3 = t.P[m_i] + t.R[m_i] * side * (t.hw + Track.GUTTER_W + 0.35)
			xf.append(Transform3D(Basis(), p + Vector3.UP * 0.8))
		i = j
	_mm(pole, xf, m)


func _rumble_strips() -> void:
	# red-orange transverse stripes painted on the approach to tight corners
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := t.P.size()
	var i := 1
	while i < n:
		if absf(t.K[i]) < 1.0 / 30.0 or absf(t.K[i - 1]) >= 1.0 / 30.0:
			i += 1
			continue
		var entry_s := t.S[i]
		for k in 7:
			var s0 := entry_s - 40.0 + k * 4.5
			if s0 < 5.0:
				continue
			var a := t.point_at(s0, -t.hw + 0.3) + Vector3.UP * 0.014
			var b := t.point_at(s0, t.hw - 0.3) + Vector3.UP * 0.014
			var c := t.point_at(s0 + 1.2, -t.hw + 0.3) + Vector3.UP * 0.014
			var d := t.point_at(s0 + 1.2, t.hw - 0.3) + Vector3.UP * 0.014
			st.set_normal(Vector3.UP)
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
			st.add_vertex(b); st.add_vertex(c); st.add_vertex(d)
		i += 20
	var m := _mat(Color(0.75, 0.16, 0.08), 0.6)
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	_add(mi)


func _ridges() -> void:
	# layered mountain silhouettes on the horizon, fading into the night haze
	var cen := Vector3.ZERO
	for p in t.P:
		cen += p
	cen /= t.P.size()
	var top_y := t.P[0].y
	for layer in 3:
		var radius := 2600.0 + layer * 1400.0
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segs := 160
		var noise := FastNoiseLite.new()
		noise.seed = 31 + layer
		noise.frequency = 2.2
		var shade := 0.07 + layer * 0.035
		var col := Color(shade * 0.55, shade * 0.75, shade * 1.6)
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var h0 := top_y + 120.0 + 260.0 * (0.5 + 0.5 * noise.get_noise_1d(a0)) + layer * 120.0
			var h1 := top_y + 120.0 + 260.0 * (0.5 + 0.5 * noise.get_noise_1d(a1)) + layer * 120.0
			var b0 := cen + Vector3(cos(a0), 0, sin(a0)) * radius
			var b1 := cen + Vector3(cos(a1), 0, sin(a1)) * radius
			b0.y = t.min_y - 300.0
			b1.y = t.min_y - 300.0
			var u0 := Vector3(b0.x, h0, b0.z)
			var u1 := Vector3(b1.x, h1, b1.z)
			st.set_color(col)
			st.add_vertex(b0); st.add_vertex(u0); st.add_vertex(b1)
			st.add_vertex(b1); st.add_vertex(u0); st.add_vertex(u1)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_fog = true
		st.set_material(m)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		_add(mi)
