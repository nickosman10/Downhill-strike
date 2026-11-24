class_name Scenery
extends RefCounted
## Roadside dressing in the style of the First Stage night backgrounds:
## painted foliage, concrete retaining walls with chain-link fences on the
## hillside, wooden utility poles with sagging wires, red/white delineators at
## hairpins, red rumble stripes before corners, distant ridges.

var t: Track
var rng := RandomNumberGenerator.new()
var foliage_mat: ShaderMaterial
var leaf_mat: ShaderMaterial
var cedar_mat: ShaderMaterial
var trunk_mat: StandardMaterial3D
var caps := PackedVector3Array()   # (x, max terrain height, z) under walls and frames
var wall_sides := {}
# every placed object's footprint, so nothing ends up inside anything else
var _ko_pos := PackedVector3Array()
var _ko_r := PackedFloat32Array()
var _ko_grid := {}
const KO_CELL := 10.0
var _pending: Array = []       # trees and bushes, planted last around everything else      # Vector2i(i, side) -> true where a wall stands


func build(track: Track) -> void:
	t = track
	rng.seed = hash(t.course.get("id", "x"))
	foliage_mat = ShaderMaterial.new()
	foliage_mat.shader = load("res://shaders/foliage.gdshader")
	leaf_mat = ShaderMaterial.new()
	leaf_mat.shader = load("res://shaders/foliage_card.gdshader")
	leaf_mat.set_shader_parameter("leaves", load("res://assets/textures/leaves.png"))
	cedar_mat = ShaderMaterial.new()
	cedar_mat.shader = load("res://shaders/foliage_card.gdshader")
	cedar_mat.set_shader_parameter("leaves", load("res://assets/textures/cedar.png"))
	cedar_mat.set_shader_parameter("brightness", 0.9)
	trunk_mat = Mats.pbr("bark", 1.0, Color(0.75, 0.7, 0.65))
	_walls()
	t.walls = wall_sides
	_tunnels()
	_slope_protection()
	# keep the mountain behind the walls and frames, then plant on the result
	t.cap_terrain(caps)
	_trees()
	_bushes()
	_poles()
	_delineators()
	_ridges()
	_city()
	if t.features.is_empty():
		_street_lamps()
		_summit_area()
		_village()
	else:
		_real_features()
	_curbs()
	_curve_signs_and_mirrors()
	_skid_marks()
	if t.style.get("red_pavement", false):
		_red_pavement()
	if t.style.get("chevron_boards", false):
		_chevron_rows()
	_plant_pending()


## Register an object's footprint (centre, radius on the ground plane).
func _keep_out(p: Vector3, r: float) -> void:
	if r <= 0.0 or r > 25.0:
		return
	var k := Vector2i(floori(p.x / KO_CELL), floori(p.z / KO_CELL))
	if not _ko_grid.has(k):
		_ko_grid[k] = PackedInt32Array()
	_ko_grid[k].append(_ko_pos.size())
	_ko_pos.append(p)
	_ko_r.append(r)


## True if a circle at p with radius r overlaps anything already placed.
func _blocked(p: Vector3, r: float) -> bool:
	var cx := floori(p.x / KO_CELL)
	var cz := floori(p.z / KO_CELL)
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var k := Vector2i(cx + dx, cz + dz)
			if not _ko_grid.has(k):
				continue
			for idx in _ko_grid[k]:
				var q := _ko_pos[idx]
				var d := Vector2(p.x - q.x, p.z - q.z).length()
				if d < r + _ko_r[idx]:
					return true
	return false


## True if the hillside rises over this spot: anything standing here would be
## half swallowed by the mountain.
func _buried(p: Vector3, r: float) -> bool:
	for off in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		if t.terrain_height(p.x + off.x, p.z + off.y) > p.y + 0.45:
			return true
	return false


func _register_mesh(mesh: Mesh, xf: Transform3D) -> void:
	if mesh == null:
		return
	var ab: AABB = xf * mesh.get_aabb()
	_keep_out(ab.get_center(), 0.5 * maxf(ab.size.x, ab.size.z))


## Plant the trees and bushes, skipping every spot that would put a trunk or
## a bush through a sign, pole, lamp, mirror, building or anything else.
func _plant_pending() -> void:
	for job in _pending:
		var mesh: Mesh = job[0]
		var xfs: Array = job[1]
		var cols: Array = job[2]
		var clear: float = job[5]
		var own: float = job[6]          # space this plant takes once planted
		var keep_x: Array = []
		var keep_c: Array = []
		for k in xfs.size():
			var o0: Vector3 = xfs[k].origin
			var ti := t.nearest_index(o0)
			if t.in_tunnel(ti) and o0.y < t.P[ti].y + 9.0 and t.dist_to_road(o0) < t.rail + (7.0 if clear > 1.0 else 3.0):
				continue      # nothing grows inside a tunnel
			var o: Vector3 = xfs[k].origin
			var sc: float = xfs[k].basis.get_scale().x
			if _blocked(o, clear * clampf(sc, 0.8, 1.6)):
				continue
			keep_x.append(xfs[k])
			keep_c.append(cols[k] if cols.size() > k else Color.WHITE)
			# later trunks and bushes keep clear of this one
			_keep_out(o, own * sc)
		if job.size() > 7:
			# detail levels: [mesh, from, to, casts shadow] per level, in small chunks so
			# each patch of forest switches level by its own distance from the camera
			for lod in job[7]:
				_mm_lod(lod[0], keep_x, keep_c, 48.0, lod[1], lod[2], lod[3])
			continue
		_cast_shadows = (Mats.hq() or Mats.toon()) and clear > 1.0      # trees cast real shadows
		_mm_chunked(mesh, keep_x, null, keep_c, job[3], job[4])
		_cast_shadows = false


func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _add(n: Node) -> void:
	t.add_child(n)


func _mm(mesh: Mesh, xf: Array, mat: Material, colors: Array = [], vis_end := 0.0, register := true) -> void:
	if register and mat != null:
		for x in xf:
			_register_mesh(mesh, x)
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
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
	_add(mmi)


## Chunked multimesh so far-away parts are culled.
## Chunked multimesh for one detail level, visible between `from` and `to`
## metres. Each chunk node sits at its own centre so its distance is measured there.
func _mm_lod(mesh: Mesh, xf: Array, colors: Array, chunk: float, from: float, to: float, shadow: int) -> void:
	var buckets := {}
	for k in xf.size():
		var o: Vector3 = xf[k].origin
		var key := Vector2i(floori(o.x / chunk), floori(o.z / chunk))
		if not buckets.has(key):
			buckets[key] = [[], []]
		buckets[key][0].append(xf[k])
		buckets[key][1].append(colors[k] if colors.size() > k else Color.WHITE)
	for key in buckets:
		var list: Array = buckets[key][0]
		var centre := Vector3.ZERO
		for x: Transform3D in list:
			centre += x.origin
		centre /= list.size()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for k in list.size():
			var x: Transform3D = list[k]
			mm.set_instance_transform(k, Transform3D(x.basis, x.origin - centre))
			mm.set_instance_color(k, buckets[key][1][k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = centre
		mmi.cast_shadow = [GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY][shadow]
		mmi.visibility_range_begin = from
		mmi.visibility_range_end = to
		if shadow != 2:
			mmi.visibility_range_begin_margin = 5.0 if from > 0.0 else 0.0
			mmi.visibility_range_end_margin = 5.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_add(mmi)


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
		_mm(mesh, buckets[key][0], mat, buckets[key][1], vis_end, false)


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


var _toon_noise: FastNoiseLite
var _toon_leaf := {}


func _toon_leaf_mat(c: Color) -> ShaderMaterial:
	if not _toon_leaf.has(c):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/foliage_toon.gdshader")
		m.set_shader_parameter("paint", Mats.paint_tex())
		m.set_shader_parameter("base", c)
		_toon_leaf[c] = m
	return _toon_leaf[c]


## One sculpted mass of leaves: a lumpy rounded volume (cartoon trees are
## built from these, so they are solid from every side).
func _puff(st: SurfaceTool, c: Vector3, rad: Vector3, seed_v: float, shade: float, rings := 7, segs := 11) -> void:
	if _toon_noise == null:
		_toon_noise = FastNoiseLite.new()
		_toon_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_toon_noise.frequency = 0.01
	var pts: Array = []
	for r in rings + 1:
		var phi := PI * r / rings
		for sg in segs + 1:
			var th := TAU * sg / segs
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var bump := 1.0 + 0.26 * _toon_noise.get_noise_3d(d.x * 130.0 + seed_v, d.y * 130.0, d.z * 130.0 - seed_v)
			# darker underneath, where the leaves shade each other
			var sh := shade * lerpf(0.72, 1.05, clampf(d.y * 0.6 + 0.5, 0.0, 1.0))
			pts.append([c + Vector3(d.x * rad.x, d.y * rad.y, d.z * rad.z) * bump, d, sh])
	for r in rings:
		for sg in segs:
			var a := r * (segs + 1) + sg
			for k: int in [a, a + 1, a + segs + 2, a, a + segs + 2, a + segs + 1]:
				st.set_normal(pts[k][1])
				st.set_color(Color(pts[k][2], pts[k][2], pts[k][2]))
				st.add_vertex(pts[k][0])


## Cartoon broadleaf tree: bent trunk, forked boughs, a crown of leaf masses.
## detail 0 = beside the road, 1 = middle distance, 2 = far hillside.
func _toon_tree(seed_v: int, leaf: Color, detail := 0) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var mesh := ArrayMesh.new()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crown := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: int = [7, 4, 3][detail]
	var segs: int = [11, 7, 5][detail]
	var sides: int = [8, 5, 3][detail]
	var fork := Vector3(r.randf_range(-0.3, 0.3), 4.2, r.randf_range(-0.3, 0.3))
	if detail == 0:
		_limb(bark, Vector3(0, -0.5, 0), fork * 0.5 + Vector3(0.12, 0, 0.08), 0.34, 0.26, sides)
		_limb(bark, fork * 0.5 + Vector3(0.12, 0, 0.08), fork, 0.26, 0.2, sides, 1.2)
	else:
		_limb(bark, Vector3(0, -0.5, 0), fork, 0.34, 0.2, sides)
	var n := 4
	for k in n:
		var ang := TAU * k / n + r.randf_range(-0.3, 0.3)
		var reach := r.randf_range(1.8, 2.8)
		var tip := fork + Vector3(cos(ang) * reach, r.randf_range(1.6, 2.8), sin(ang) * reach)
		var mid := fork.lerp(tip, 0.5) + Vector3(0, 0.3, 0)
		var s := r.randf_range(1.7, 2.3)
		var sh1 := r.randf_range(0.9, 1.05)
		var sh2 := r.randf_range(0.8, 0.95)
		if detail == 0:
			_limb(bark, fork, mid, 0.17, 0.11, 6)
			_limb(bark, mid, tip, 0.11, 0.05, 5)
		elif detail == 1:
			_limb(bark, fork, tip, 0.15, 0.05, 3)
		if detail < 2:
			_puff(crown, tip + Vector3(0, 0.5, 0), Vector3(s, s * 0.72, s), seed_v * 10.0 + k, sh1, rings, segs)
		if detail == 0:
			# a smaller mass hanging off the side of each bough
			var side := Vector3(cos(ang + 0.9), 0, sin(ang + 0.9)) * s * 0.85
			_puff(crown, tip + side + Vector3(0, -0.5, 0), Vector3(s, s * 0.7, s) * 0.62, seed_v * 10.0 + k + 40.0, sh2, 6, 9)
	# the top of the crown
	var off := Vector3(r.randf_range(-1.0, 1.0), 3.0, r.randf_range(-1.0, 1.0))
	if detail < 2:
		_puff(crown, fork + Vector3(0, 4.4, 0), Vector3(2.5, 1.9, 2.5), seed_v * 10.0 + 99.0, 1.08, rings, segs)
		_puff(crown, fork + off, Vector3(2.9, 1.7, 2.9), seed_v * 10.0 + 77.0, 0.9, rings, segs)
	else:
		# far away the whole crown is one mass
		_puff(crown, fork + Vector3(0, 3.2, 0), Vector3(4.6, 3.1, 4.6), seed_v * 10.0 + 99.0, 1.0, 4, 7)
	bark.set_material(trunk_mat)
	bark.commit(mesh)
	crown.set_material(_toon_leaf_mat(leaf))
	crown.commit(mesh)
	return mesh


## Cartoon cedar: a tall straight trunk carrying stacked skirts of foliage.
func _toon_cedar(seed_v: int, detail := 0) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var mesh := ArrayMesh.new()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crown := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 15.0
	if detail == 0:
		_limb(bark, Vector3(0, -0.5, 0), Vector3(0, h * 0.5, 0), 0.32, 0.2, 8)
		_limb(bark, Vector3(0, h * 0.5, 0), Vector3(0, h - 0.5, 0), 0.2, 0.05, 6, 3.0)
	else:
		_limb(bark, Vector3(0, -0.5, 0), Vector3(0, h * 0.6, 0), 0.32, 0.15, 4 if detail == 1 else 3)
	var tiers: int = [6, 4, 2][detail]
	var segs: int = [12, 7, 5][detail]
	for k in tiers:
		var f := float(k) / (tiers - 1)
		var y0 := lerpf(4.2, h - 2.6 - (0.0 if detail == 0 else 6.0 / tiers), f)
		var rad := lerpf(2.7, 0.9 if detail == 0 else 1.5, f)
		var th := (h - 4.2) / tiers * 1.75
		var apex := Vector3(0, y0 + th, 0)
		var shade := lerpf(0.85, 1.08, f)
		var ring: Array = []
		for sg in segs + 1:
			var a := TAU * sg / segs
			var wave := 1.0 + (0.2 * sin(a * 5.0 + k * 1.7) + 0.1 * sin(a * 3.0 + seed_v) if detail == 0 else 0.0)
			var d := Vector3(cos(a), 0, sin(a))
			ring.append([d * rad * wave + Vector3(0, y0 - (0.35 * absf(sin(a * 2.5 + k)) if detail == 0 else 0.0), 0), (d * th + Vector3.UP * rad).normalized()])
		for sg in segs:
			var q := [[ring[sg][0], ring[sg][1], shade * 0.8], [ring[sg + 1][0], ring[sg + 1][1], shade * 0.8], [apex, Vector3.UP, shade * 1.05]]
			for v in q:
				crown.set_normal(v[1])
				crown.set_color(Color(v[2], v[2], v[2]))
				crown.add_vertex(v[0])
			if detail == 0:
				# dark underside closing the skirt
				var under := [[ring[sg + 1][0], Vector3.DOWN, 0.5], [ring[sg][0], Vector3.DOWN, 0.5], [Vector3(0, y0 + 0.5, 0), Vector3.DOWN, 0.5]]
				for v in under:
					crown.set_normal(v[1])
					crown.set_color(Color(v[2], v[2], v[2]))
					crown.add_vertex(v[0])
	bark.set_material(trunk_mat)
	bark.commit(mesh)
	crown.set_material(_toon_leaf_mat(Color(0.09, 0.3, 0.2)))
	crown.commit(mesh)
	return mesh


## Cartoon bush: a few low leaf masses.
func _toon_bush(seed_v: int, size: float, leaf: Color) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var s := size * r.randf_range(0.75, 1.1)
		var off := Vector3(r.randf_range(-0.8, 0.8), 0, r.randf_range(-0.8, 0.8)) * size * (0.0 if k == 0 else 1.0)
		_puff(st, off + Vector3(0, s * 0.55, 0), Vector3(s, s * 0.75, s), seed_v * 7.0 + k, r.randf_range(0.85, 1.05), 4, 7)
	st.set_material(_toon_leaf_mat(leaf))
	st.commit(mesh)
	return mesh


## Canopy of crossed leaf cards around a centre (textured, alpha cut).
func _cards(st: SurfaceTool, center: Vector3, radius: float, cards: int, seed_v: int, stretch := 1.0) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	for k in cards:
		var c := center
		if k > 0:
			c += Vector3(r.randf_range(-0.55, 0.55) * radius, r.randf_range(-0.35, 0.45) * radius, r.randf_range(-0.55, 0.55) * radius)
		var yaw := r.randf() * TAU
		var size := radius * r.randf_range(1.35, 1.8)
		var right := Vector3(cos(yaw), 0, sin(yaw)) * size * 0.5
		var up := (Vector3.UP * size * 0.5 * stretch).rotated(right.normalized(), r.randf_range(-0.3, 0.3))
		st.set_normal(right.cross(up).normalized())
		var v := [c - right - up, c + right - up, c + right + up, c - right + up]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])


func _trunk_surface(mesh: ArrayMesh, height: float, r0: float, r1: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = r1
	trunk.bottom_radius = r0
	trunk.height = height
	trunk.radial_segments = 5
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, height * 0.5, 0)))
	st.set_material(trunk_mat)
	st.commit(mesh)


func _card_tree(seed_v: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_trunk_surface(mesh, 5.5, 0.26, 0.14)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cards(st, Vector3(0, 6.3, 0), 2.6, 10, seed_v)
	st.set_material(leaf_mat)
	st.commit(mesh)
	return mesh


func _card_cedar() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_trunk_surface(mesh, 3.0, 0.24, 0.16)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# three crossed needle cards, like a sugi seen from any side
	for k in 3:
		var yaw := PI * k / 3.0
		var right := Vector3(cos(yaw), 0, sin(yaw)) * 2.4
		var lo := Vector3(0, 1.6, 0)
		var hi := Vector3(0, 12.0, 0)
		st.set_normal(right.cross(Vector3.UP).normalized())
		var v := [lo - right, lo + right, hi + right, hi - right]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
	st.set_material(cedar_mat)
	st.commit(mesh)
	return mesh


func _card_bush(seed_v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cards(st, Vector3(0, 0.7, 0), 1.0, 6, seed_v, 0.8)
	st.set_material(leaf_mat)
	return st.commit()


var _tree_meta := {}
var _ph_mats := {}


func _ph_pbr(prefix: String) -> StandardMaterial3D:
	if not _ph_mats.has(prefix):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/trees/ph/%s_diff.jpg" % prefix)
		m.normal_enabled = true
		m.normal_texture = load("res://assets/trees/ph/%s_nor.jpg" % prefix)
		m.roughness_texture = load("res://assets/trees/ph/%s_rough.jpg" % prefix)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_ph_mats[prefix] = m
	return _ph_mats[prefix]


func _ph_leaf(tex: String, center_y: float) -> ShaderMaterial:
	var key := "%s_%d" % [tex, int(center_y)]
	if not _ph_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/foliage_real.gdshader")
		m.set_shader_parameter("leaves", load("res://assets/trees/ph/%s.png" % tex))
		m.set_shader_parameter("leaves_nor", load("res://assets/trees/ph/%s_nor.jpg" % tex))
		m.set_shader_parameter("center_y", center_y)
		m.set_shader_parameter("tint", Vector3(0.44, 0.56, 0.34) if tex == "jac_leaves" else Vector3(0.6, 0.86, 0.6))
		_ph_mats[key] = m
	return _ph_mats[key]


## A scanned tree assembled for the game (tools/blender_ph_tree.py): the real
## trunk and branches with the package's own twig and leaf cards.
func _ph_tree(file: String, center_y: float) -> ArrayMesh:
	var scene: PackedScene = load("res://assets/trees/ph/%s.glb" % file)
	var inst := scene.instantiate()
	var out := ArrayMesh.new()
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var src := mi.mesh
		for i in src.get_surface_count():
			var mat_name := ""
			var sm := src.surface_get_material(i)
			if sm:
				mat_name = sm.resource_name
			# copy the surface without the importer's automatic detail reduction,
			# which wrecks meshes made of separate leaf cards
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(i))
			var m: Material
			if mat_name.contains("twig"):
				m = _ph_leaf("fir_twig", center_y)
			elif mat_name.contains("leaves"):
				m = _ph_leaf("jac_leaves", center_y)
			elif mat_name.contains("trunk_c"):
				m = _ph_pbr("fir_trunk_c")
			elif mat_name.contains("trunk_b"):
				m = _ph_pbr("fir_trunk_b")
			elif mat_name.contains("trunk_a"):
				m = _ph_pbr("fir_trunk_a")
			elif mat_name.contains("fir_tree"):
				m = _ph_pbr("fir_bark")
			elif mat_name.contains("branches"):
				m = _ph_pbr("jac_branches")
			else:
				m = _ph_pbr("jac_trunk")
			out.surface_set_material(out.get_surface_count() - 1, m)
	inst.free()
	return out
var _leaf_mats := {}
var _near_trees: Array = []
var _far_trees: Array = []
var _cast_shadows := false


func _leaf_material(tex_name: String, center_y: float) -> ShaderMaterial:
	var key := "%s_%d" % [tex_name, int(center_y)]
	if not _leaf_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/foliage_card.gdshader")
		m.set_shader_parameter("leaves", load("res://assets/trees/%s.png" % tex_name))
		m.set_shader_parameter("tint", Vector3(1.0, 1.0, 1.0))
		m.set_shader_parameter("brightness", 0.9)
		m.set_shader_parameter("center_y", center_y)
		_leaf_mats[key] = m
	return _leaf_mats[key]


## Tapered round limb from a to b (trunk or branch), with bark UVs.
func _limb(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sides := 7, v0 := 0.0) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var u := axis.cross(ref).normalized()
	var w := axis.cross(u)
	var len := a.distance_to(b)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var n0 := u * cos(a0) + w * sin(a0)
		var n1 := u * cos(a1) + w * sin(a1)
		var quad := [[a + n0 * r0, n0, Vector2(float(k) / sides * 2.0, v0)], [a + n1 * r0, n1, Vector2(float(k + 1) / sides * 2.0, v0)],
			[b + n1 * r1, n1, Vector2(float(k + 1) / sides * 2.0, v0 + len * 0.5)], [b + n0 * r1, n0, Vector2(float(k) / sides * 2.0, v0 + len * 0.5)]]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(quad[idx][1])
			st.set_tangent(Plane(axis, 1.0))
			st.set_uv(quad[idx][2])
			st.add_vertex(quad[idx][0])


## One foliage card: a quad with its base at `root`, growing along `along`, facing `face`.
func _leaf_quad(st: SurfaceTool, root: Vector3, along: Vector3, side: Vector3, length: float, width: float) -> void:
	var v := [root - side * width * 0.5, root + side * width * 0.5, root + side * width * 0.5 + along * length, root - side * width * 0.5 + along * length]
	var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	st.set_normal(side.cross(along).normalized())
	for idx in [0, 2, 1, 0, 3, 2]:
		st.set_uv(uv[idx])
		st.add_vertex(v[idx])


## A real 3D tree: modelled trunk and branches in scanned bark, carrying many
## foliage clusters cut from scanned trees, spread through the crown in depth.
func _tree3d(kind: String, seed_v: int) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var mesh := ArrayMesh.new()
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf_st := {}
	var add_leaf := func(tex: String, root: Vector3, along: Vector3, side: Vector3, length: float, width: float) -> void:
		if not leaf_st.has(tex):
			var lt := SurfaceTool.new()
			lt.begin(Mesh.PRIMITIVE_TRIANGLES)
			leaf_st[tex] = lt
		_leaf_quad(leaf_st[tex], root, along, side, length, width)
	var center_y := 5.0
	if kind == "fir":
		var h := 14.5
		center_y = 7.5
		# straight tapering trunk in three pieces
		var p0 := Vector3.ZERO
		for k in 3:
			var p1 := Vector3(r.randf_range(-0.05, 0.05), h * (k + 1) / 3.0, r.randf_range(-0.05, 0.05))
			_limb(bark, p0, p1, lerpf(0.3, 0.03, k / 3.0), lerpf(0.3, 0.03, (k + 1) / 3.0), 8, p0.y * 0.5)
			p0 = p1
		# whorls of drooping boughs, long at the bottom, short at the top
		var y := 2.4
		while y < h - 0.3:
			var t := (y - 2.4) / (h - 2.4)
			var length := lerpf(3.4, 0.5, pow(t, 0.8)) * r.randf_range(0.85, 1.1)
			var count := 8 if t < 0.7 else 5
			var twist := r.randf() * TAU
			for k in count:
				var ang := twist + TAU * k / count + r.randf_range(-0.2, 0.2)
				var out := Vector3(cos(ang), 0, sin(ang))
				var along := (out + Vector3.DOWN * r.randf_range(0.12, 0.35)).normalized()
				var side := along.cross(Vector3.UP).normalized()
				var root := Vector3(0, y + r.randf_range(-0.2, 0.2), 0)
				var tex := "bough_%d" % r.randi_range(0, 1)
				# a flat bough plus an upright one through it, so it has body from every angle
				add_leaf.call(tex, root, along, side, length, length * 0.75)
				add_leaf.call(tex, root, along, side.cross(along).normalized(), length, length * 0.5)
			y += lerpf(0.6, 0.4, t)
		# leader at the very top
		add_leaf.call("bough_0", Vector3(0, h - 1.4, 0), Vector3.UP, Vector3.RIGHT, 1.6, 1.0)
		add_leaf.call("bough_0", Vector3(0, h - 1.4, 0), Vector3.UP, Vector3.BACK, 1.6, 1.0)
	else:
		var slender := kind == "slender"
		var trunk_h := 6.5 if slender else 4.8
		var crown := 2.0 if slender else 4.4
		center_y = trunk_h + 1.0
		# trunk that wanders a little as it climbs
		var pts: Array[Vector3] = [Vector3.ZERO]
		for k in range(1, 5):
			pts.append(Vector3(r.randf_range(-0.25, 0.25) * k * 0.4, trunk_h * k / 4.0, r.randf_range(-0.25, 0.25) * k * 0.4))
		for k in 4:
			_limb(bark, pts[k], pts[k + 1], lerpf(0.3, 0.15, k / 4.0), lerpf(0.3, 0.15, (k + 1) / 4.0), 8, pts[k].y * 0.5)
		var tips: Array[Vector3] = []
		var n_branch := 5 if slender else 7
		for k in n_branch:
			var t := r.randf_range(0.5, 1.0)
			var base := pts[2].lerp(pts[4], (t - 0.5) * 2.0)
			var ang := TAU * k / n_branch + r.randf_range(-0.4, 0.4)
			var dir := (Vector3(cos(ang), 0, sin(ang)) + Vector3.UP * r.randf_range(0.35, 0.9)).normalized()
			var length := crown * r.randf_range(0.7, 1.1)
			var mid := base + dir * length * 0.55 + Vector3.UP * 0.15
			var tip := mid + (dir + Vector3.UP * 0.25).normalized() * length * 0.45
			_limb(bark, base, mid, 0.11, 0.07, 5)
			_limb(bark, mid, tip, 0.07, 0.025, 5)
			tips.append(mid)
			tips.append(tip)
			# secondary twigs
			for j in 2:
				var sd := (dir.cross(Vector3.UP) * (1.0 if j == 0 else -1.0) + dir * 0.6 + Vector3.UP * 0.3).normalized()
				var tw := mid + sd * length * 0.4
				_limb(bark, mid, tw, 0.045, 0.015, 4)
				tips.append(tw)
		tips.append(pts[4] + Vector3.UP * crown * 0.5)
		tips.append(pts[4] + Vector3.UP * crown * 0.15)
		# a foliage cluster at every twig end: two or three crossed cards, each a different scan
		for tip in tips:
			var size := (2.0 if slender else 2.6) * r.randf_range(0.8, 1.25)
			var cards := 3
			for j in cards:
				var yaw := r.randf() * TAU
				var side := Vector3(cos(yaw), 0, sin(yaw))
				var up := (Vector3.UP + Vector3(r.randf_range(-0.35, 0.35), 0, r.randf_range(-0.35, 0.35))).normalized()
				if j == 2:
					# one card lying flatter fills the crown seen from below and above
					up = (side.cross(Vector3.UP) + Vector3.UP * 0.35).normalized()
				add_leaf.call("cluster_%d" % r.randi_range(0, 3), tip - up * size * 0.45, up, side, size * 0.9, size)
	bark.set_material(trunk_mat)
	bark.commit(mesh)
	for tex in leaf_st:
		var lt: SurfaceTool = leaf_st[tex]
		lt.set_material(_leaf_material(tex, center_y))
		lt.commit(mesh)
	return mesh


## A tree built from photo-real cut-outs of a scanned tree (baked from Poly
## Haven's CC0 scans): two crossed cards that meet on the trunk, lit by the scene.
func _photo_tree(kind: String, height: float) -> ArrayMesh:
	if _tree_meta.is_empty():
		_tree_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/trees/trees.json"))
	var mesh := ArrayMesh.new()
	for k in 2:
		var info: Dictionary = _tree_meta["%s_%d" % [kind, k]]
		var w: float = height * float(info.aspect)
		var tx: float = float(info.trunk)
		var yaw := PI * 0.5 * k
		var right := Vector3(cos(yaw), 0, sin(yaw))
		var left := -right * w * tx
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(right.cross(Vector3.UP).normalized())
		var v := [left, left + right * w, left + right * w + Vector3.UP * height, left + Vector3.UP * height]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_uv(uv[idx])
			st.add_vertex(v[idx])
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/foliage_card.gdshader")
		m.set_shader_parameter("leaves", load("res://assets/trees/%s_%d.png" % [kind, k]))
		m.set_shader_parameter("tint", Vector3(1.0, 1.0, 1.0))
		m.set_shader_parameter("brightness", 0.9)
		st.set_material(m)
		st.commit(mesh)
	return mesh


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
	# like the anime's mountain passes: a tall stone-masonry wall rising
	# straight from the road edge (plain concrete where the real road has it)
	var concrete := Mats.pbr("concrete" if t.style.get("concrete_walls", false) else "masonry", 1.0)
	concrete.cull_mode = BaseMaterial3D.CULL_DISABLED
	var fence_mat := _mat(Color(0.55, 0.6, 0.7), 0.6)
	fence_mat.albedo_texture = _fence_texture()
	fence_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fence_mat.alpha_scissor_threshold = 0.5
	fence_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fence_mat.uv1_scale = Vector3(1, 1, 1)
	var wst := SurfaceTool.new()
	wst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sst := SurfaceTool.new()       # asphalt shoulder between the road edge and the wall
	sst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shoulder := Mats.pbr("asphalt", 2.0, Color(0.55, 0.55, 0.57), 0.7)
	shoulder.cull_mode = BaseMaterial3D.CULL_DISABLED
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := t.P.size()
	var post_xf: Array = []
	for side: float in [-1.0, 1.0]:
		var heights := PackedFloat32Array()
		heights.resize(n)
		for i in n:
			var probe := t.P[i] + t.R[i] * side * (t.rail + 5.0)
			heights[i] = clampf(t.terrain_height(probe.x, probe.z) - t.P[i].y, 0.0, 9.0)
		# smooth so the wall top runs cleanly
		for pass_i in 2:
			for i in range(1, n - 1):
				heights[i] = (heights[i - 1] + heights[i] * 2.0 + heights[i + 1]) * 0.25
		var lat: float = side * (t.rail + 0.9)
		for i in range(1, n):
			var h0 := heights[i - 1]
			var h1 := heights[i]
			# any rise beside the road gets a retaining wall, so the cut
			# terrain always ends against concrete
			if h0 < 0.5 and h1 < 0.5:
				continue
			if t.in_tunnel(i):
				continue
			var wall_mid: Vector3 = t.P[i] + t.R[i] * lat
			if t.dist_to_road(wall_mid) < t.rail + 0.5:
				continue
			wall_sides[Vector2i(i, int(side))] = true
			var a := t.P[i - 1] + t.R[i - 1] * lat
			var b := t.P[i] + t.R[i] * lat
			var u0 := t.S[i - 1] / 3.0
			var u1 := t.S[i] / 3.0
			# the face leans back slightly (about 1 in 8), like real masonry walls
			var top_a := a + Vector3.UP * maxf(h0, 0.3) + t.R[i - 1] * side * maxf(h0, 0.3) * 0.12
			var top_b := b + Vector3.UP * maxf(h1, 0.3) + t.R[i] * side * maxf(h1, 0.3) * 0.12
			# the hillside stays under the wall top right behind the wall,
			# then may climb away from it like a real cut slope
			for l: float in [0.9, 1.3, 2.0, 3.0, 4.2]:
				var cp: Vector3 = t.P[i] + t.R[i] * side * (t.rail + l)
				caps.append(Vector3(cp.x, top_b.y - 0.25 + maxf(0.0, l - 1.3) * 0.9, cp.z))
			var bot_a := a + Vector3.DOWN * 0.8
			var bot_b := b + Vector3.DOWN * 0.8
			# concrete side ditch along the wall foot, from the road edge to the wall
			# starts exactly at the road mesh's outer edge and sits 1.5 cm above its
			# edge strip, so the two surfaces never share a height (no flicker)
			var e_lat := t.hw + Track.GUTTER_W        # outer edge of the concrete gutter
			var ea := t.P[i - 1] + t.R[i - 1] * side * e_lat + Vector3.DOWN * 0.005
			var eb := t.P[i] + t.R[i] * side * e_lat + Vector3.DOWN * 0.005
			var fa := a + Vector3.DOWN * 0.005
			var fb := b + Vector3.DOWN * 0.005
			# the road surface carries on to the wall foot (asphalt, same tiling as the road)
			sst.set_normal(Vector3.UP)
			var r0 := (t.hw + Track.GUTTER_W) / 6.0
			var r1 := (t.rail + 0.9) / 6.0
			for tri in [[ea, Vector2(r0, t.S[i - 1] / 6.0)], [eb, Vector2(r0, t.S[i] / 6.0)], [fb, Vector2(r1, t.S[i] / 6.0)],
					[ea, Vector2(r0, t.S[i - 1] / 6.0)], [fb, Vector2(r1, t.S[i] / 6.0)], [fa, Vector2(r1, t.S[i - 1] / 6.0)]]:
				sst.set_uv(tri[1])
				sst.add_vertex(tri[0])
			var nrm: Vector3 = -t.R[i] * side
			wst.set_normal(nrm)
			_quad(wst, bot_a, bot_b, top_b, top_a, Vector2(u0, (h0 + 0.8) / 3.0), Vector2(u1, (h1 + 0.8) / 3.0), side)
			# wall cap and chain-link fence on top
			var back_a := top_a + t.R[i - 1] * side * 0.4
			var back_b := top_b + t.R[i] * side * 0.4
			wst.set_normal(Vector3.UP)
			_quad(wst, top_a, top_b, back_b, back_a, Vector2(u0, 0.1), Vector2(u1, 0.1), side)
			if t.style.get("wall_fences", false) and maxf(h0, h1) > 2.5:
				fst.set_normal(nrm)
				_quad(fst, top_a, top_b, top_b + Vector3.UP * 1.6, top_a + Vector3.UP * 1.6, Vector2(u0 * 2.0, 1), Vector2(u1 * 2.0, 1), side)
	wst.set_material(concrete)
	fst.set_material(fence_mat)
	sst.set_material(shoulder)
	var sm := MeshInstance3D.new()
	sm.mesh = sst.commit()
	_add(sm)
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


func _plain_concrete_texture() -> ImageTexture:
	# smooth cast-concrete retaining wall with form-tie dots and stains (Usui)
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var g := 0.85 + 0.06 * sin(x * 0.21) * cos(y * 0.13)
			if (x % 32 == 8 or x % 32 == 24) and (y % 32 == 8 or y % 32 == 24):
				g = 0.6
			if x % 64 < 1:
				g = 0.65
			g -= clampf((40 - y) / 200.0, 0.0, 0.15) * (0.5 + 0.5 * sin(x * 0.7))
			img.set_pixel(x, y, Color(g, g, g * 1.02))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _panel_texture() -> ImageTexture:
	# kenchi-ishi: stacked stone blocks laid diagonally, typical of Japanese
	# mountain-road retaining walls
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 5
	var tones := []
	for k in 64:
		tones.append(rng2.randf_range(0.72, 0.98))
	for y in 128:
		for x in 128:
			var u := (x + y) / 128.0 * 4.0
			var v := (x - y + 128) / 128.0 * 4.0
			var fu := u - floorf(u)
			var fv := v - floorf(v)
			var mortar := fu < 0.08 or fv < 0.08
			var tone: float = tones[(int(u) * 7 + int(v) * 13) % 64]
			var g := 0.42 if mortar else tone * (0.9 + 0.1 * sin(x * 0.9) * sin(y * 1.1))
			img.set_pixel(x, y, Color(g, g, g * 1.02))
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
	var meshes := [_card_tree(1), _card_tree(2), _card_cedar()]
	if ResourceLoader.exists("res://assets/trees/fir_0.png"):
		meshes = [_tree3d("broadleaf", 11), _tree3d("broadleaf", 12), _tree3d("fir", 13)]
	var toon_lods: Array = []
	if Mats.toon():
		var leafs := [Color(0.13, 0.36, 0.17), Color(0.2, 0.4, 0.14)]
		for d in 3:
			toon_lods.append([_toon_tree(11, leafs[0], d), _toon_tree(12, leafs[1], d), _toon_cedar(13, d)])
		meshes = toon_lods[0]
	var sets := [[], [], []]
	var cols := [[], [], []]
	for k in range(0, t.tree_data.size(), 4):
		var p := Vector3(t.tree_data[k], t.tree_data[k + 1] - 0.4, t.tree_data[k + 2])
		var dr := t.dist_to_road(p)
		if dr < t.rail + 8.0 and p.y > t.P[t.nearest_index(p)].y + 4.0:
			continue    # on the retaining-wall face
		var sc: float = t.tree_data[k + 3]
		var kind := 2 if rng.randf() < float(t.style.get("cedar", 0.1)) else rng.randi_range(0, 1)
		var b := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(sc, sc * rng.randf_range(0.85, 1.3), sc) * 1.3)
		sets[kind].append(Transform3D(b, p))
		var v := rng.randf_range(0.8, 1.15)
		cols[kind].append(Color(v, v * rng.randf_range(0.95, 1.1), v))
	# roadside broadleaf trees whose canopies arch over the road, like the
	# green tunnels along the real Route 33
	for i in range(0, t.P.size(), 4):
		for side: float in [-1.0, 1.0]:
			if wall_sides.has(Vector2i(i, int(side))) or rng.randf() > 0.55:
				continue
			var off := t.rail + rng.randf_range(2.0, 5.0)
			var p: Vector3 = t.P[i] + t.R[i] * side * off + t.D[i] * rng.randf_range(-2.0, 2.0)
			if t.dist_to_road(p) < t.rail + 1.5:
				continue
			p.y = t.terrain_height(p.x, p.z) - 0.3
			if absf(p.y - t.P[i].y) > 8.0:
				continue
			var sc := rng.randf_range(1.0, 1.5)
			var lean := Basis(t.D[i], -side * rng.randf_range(0.08, 0.2))
			var b := (lean * Basis.from_euler(Vector3(0, rng.randf() * TAU, 0))).scaled(Vector3(sc, sc * 1.2, sc) * 1.3)
			var k2 := rng.randi_range(0, 1)
			sets[k2].append(Transform3D(b, p))
			var v := rng.randf_range(0.85, 1.15)
			cols[k2].append(Color(v, v, v))
	for kind in 3:
		# planted at the end, around everything else (trunk + a little canopy room)
		if Mats.hq() and ResourceLoader.exists("res://assets/trees/ph/fir_b.glb"):
			if _near_trees.is_empty():
				# each kind: the scanned tree at full, medium and light weight, then a flat cut-out
				for spec in [["broadleaf_a", 8.0, "broadleaf", 12.0], ["fir_a", 12.0, "fir", 19.0], ["fir_b", 9.0, "fir", 14.1]]:
					_near_trees.append([_ph_tree(spec[0], spec[1]), _ph_tree(spec[0] + "_m", spec[1]), _ph_tree(spec[0] + "_l", spec[1])])
					_far_trees.append(_photo_tree(spec[2], spec[3]))
			var q := 2
			var game: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")
			if game:
				q = game.quality
			# metres at which each weight hands over to the next, by graphics quality.
			# Full detail is only for the trees right beside the car: there are
			# hundreds of trees within a hundred metres of any point on the road.
			var r0: float = [0.0, 12.0, 20.0][q]
			var r1: float = [22.0, 40.0, 55.0][q]
			var r2: float = [80.0, 110.0, 140.0][q]
			var shadow_r: float = [0.0, 45.0, 70.0][q]
			var t: Array = _near_trees[kind]
			var lods: Array = []
			if r0 > 0.0:
				lods.append([t[0], 0.0, r0, 0])
			lods.append([t[1], r0, r1, 0])
			lods.append([t[2], r1, r2, 0])
			lods.append([_far_trees[kind], r2, 900.0, 0])
			if shadow_r > 0.0:
				# shadows come from the light version, whatever is drawn: a tenth of the cost
				lods.append([t[2], 0.0, shadow_r, 2])
			_pending.append([meshes[kind], sets[kind], cols[kind], 160.0, 600.0, 1.4, 0.35, lods])
		elif Mats.toon():
			# full sculpt beside the road, simpler shapes up the hillside; shadows
			# come from the simple shape so they cost little
			var tl: Array = [[toon_lods[0][kind], 0.0, 80.0, 0], [toon_lods[1][kind], 80.0, 240.0, 0],
				[toon_lods[2][kind], 240.0, 800.0, 0], [toon_lods[2][kind], 0.0, 110.0, 2]]
			_pending.append([meshes[kind], sets[kind], cols[kind], 160.0, 600.0, 1.4, 0.35, tl])
		else:
			_pending.append([meshes[kind], sets[kind], cols[kind], 160.0, 600.0, 1.4, 0.35])


func _bushes() -> void:
	# dense painted bushes along the verge, thickest on hairpin inner islands
	var meshes := [_card_bush(11), _card_bush(12)]
	if ResourceLoader.exists("res://assets/trees/bush_0.png"):
		meshes = [_photo_tree("bush", 1.9), _photo_tree("fern", 0.75)]
	if Mats.toon():
		meshes = [_toon_bush(21, 1.0, Color(0.14, 0.38, 0.16)), _toon_bush(22, 0.55, Color(0.22, 0.42, 0.15))]
	var xf := [[], []]
	var cols := [[], []]
	var n := t.P.size()
	for i in range(0, n, 2):
		for side: float in [-1.0, 1.0]:
			if wall_sides.has(Vector2i(i, int(side))) or wall_sides.has(Vector2i(i + 1, int(side))):
				continue
			var inner: bool = signf(t.K[i]) == side and absf(t.K[i]) > 1.0 / 40.0
			var count := 6 if inner else 4
			for c in count:
				if rng.randf() > (0.9 if inner else 0.75):
					continue
				var off: float = t.rail + rng.randf_range(0.9, 14.0 if inner else 11.0)
				var p: Vector3 = t.P[i] + t.R[i] * side * off + t.D[i] * rng.randf_range(-1.0, 1.0)
				var hi := t.terrain_height(p.x, p.z)
				for o2 in [Vector2(0.8, 0), Vector2(-0.8, 0), Vector2(0, 0.8), Vector2(0, -0.8)]:
					hi = maxf(hi, t.terrain_height(p.x + o2.x, p.z + o2.y))
				p.y = hi - 0.3
				if absf(p.y - t.P[i].y) > 9.0 or t.dist_to_road(p) < t.rail + 0.9:
					continue
				var sc := rng.randf_range(0.8, 1.6) * (1.0 + (off - t.rail) * 0.05)
				var k := rng.randi_range(0, 1)
				xf[k].append(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(sc, sc, sc)), p))
				var v := rng.randf_range(0.85, 1.2)
				cols[k].append(Color(v, v, v))
	for k in 2:
		_pending.append([meshes[k], xf[k], cols[k], 120.0, 240.0 if Mats.toon() else 450.0, 0.55, 0.55])


func _poles() -> void:
	# wooden utility poles on one side, with sagging wires between them
	var wood := _mat(Color(0.5, 0.51, 0.53), 0.85)   # concrete utility poles
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
		if t.dist_to_road(base) < t.rail + 1.2:
			last_top = Vector3.INF
			continue
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
	if not t.far_info.is_empty():
		return    # real mountains from the elevation data already fill the horizon
	# layered mountain silhouettes on the horizon, fading into the night haze
	var cen := Vector3.ZERO
	for p in t.P:
		cen += p
	cen /= t.P.size()
	var top_y := t.P[0].y
	var away := Vector3(t.P[t.P.size() - 1].x - t.P[0].x, 0, t.P[t.P.size() - 1].z - t.P[0].z).normalized()
	var away_ang := atan2(away.z, away.x)
	for layer in 3:
		var radius := 6500.0 + layer * 1500.0
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
			# low hills beyond the valley, high mountains everywhere else
			var open0 := smoothstep(0.35, 0.9, cos(a0 - away_ang))
			var open1 := smoothstep(0.35, 0.9, cos(a1 - away_ang))
			var h0 := top_y + lerpf(250.0, -330.0, open0) + 500.0 * (0.5 + 0.5 * noise.get_noise_1d(a0)) * (1.0 - open0 * 0.7) + layer * 160.0
			var h1 := top_y + lerpf(250.0, -330.0, open1) + 500.0 * (0.5 + 0.5 * noise.get_noise_1d(a1)) * (1.0 - open1 * 0.7) + layer * 160.0
			var b0 := cen + Vector3(cos(a0), 0, sin(a0)) * radius
			var b1 := cen + Vector3(cos(a1), 0, sin(a1)) * radius
			b0.y = t.min_y - 280.0
			b1.y = t.min_y - 280.0
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


func _city() -> void:
	# Night lights of the towns in the valley below the pass, like the view
	# from the mountain in the anime. Placed beyond the bottom of the course.
	var start := t.P[0]
	var finish := t.P[t.P.size() - 1]
	var away := Vector3(finish.x - start.x, 0, finish.z - start.z).normalized()
	var side := away.cross(Vector3.UP)
	var floor_y := t.min_y - 260.0
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_fog = true
	m.albedo_texture = CarModel._flare_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var xf: Array = []
	var cols: Array = []
	var palette := [Color(1.0, 0.78, 0.45), Color(1.0, 0.9, 0.7), Color(0.75, 0.85, 1.0), Color(1.0, 0.55, 0.3)]
	# towns: real positions from the course data, or invented ones ahead
	var towns: Array = []
	if not t.towns_data.is_empty():
		for tw in t.towns_data:
			towns.append([Vector3(tw.x, 0, tw.z), float(tw.r), int(tw.n), true])
	else:
		towns = [[finish + away * 3400.0, 1300.0, 5200, false], [finish + away * 2600.0 + side * 2200.0, 700.0, 1800, false],
			[finish + away * 2900.0 - side * 2400.0, 800.0, 2000, false], [finish + away * 4600.0 + side * 900.0, 1100.0, 2400, false]]
	for town in towns:
		var c: Vector3 = town[0]
		var radius: float = town[1]
		var count: int = town[2]
		var real: bool = town[3]
		var ang := rng.randf() * PI
		var u := Vector3(cos(ang), 0, sin(ang))
		var v := u.cross(Vector3.UP)
		for k in count:
			# lights line up along a street grid, denser toward the centre
			var r := radius * 1.4 * pow(rng.randf(), 0.8)
			var a := rng.randf() * TAU
			var p := c + Vector3(cos(a), 0, sin(a)) * r
			var lu := snappedf(p.dot(u), 60.0)
			var lv := p.dot(v)
			if rng.randf() < 0.5:
				lu = p.dot(u)
				lv = snappedf(lv, 60.0)
			p = u * lu + v * lv
			if real:
				if t.dist_to_road(p) < 40.0:
					continue
				p.y = t.far_height(p.x, p.z) + 4.0 + rng.randf_range(0.0, 6.0)
			else:
				p.y = floor_y + rng.randf_range(0.0, 6.0)
			# big and bright enough to read from the road, not only from a lookout
			var sz := rng.randf_range(16.0, 30.0) * (1.0 + c.distance_to(finish) / 5000.0)
			# billboards ignore multimesh instance positions, so face each light at the pass instead
			var to_pass := (finish - p)
			to_pass.y = 0.0
			xf.append(Transform3D(Basis.looking_at(to_pass.normalized(), Vector3.UP).scaled(Vector3(sz, sz, sz)), p))
			var col: Color = palette[rng.randi() % palette.size()]
			cols.append(col * rng.randf_range(1.1, 2.2))
	_mm(quad, xf, m, cols, 0.0, false)
	if not t.towns_data.is_empty():
		# warm light haze hanging over each real town
		for town in towns:
			var hz := MeshInstance3D.new()
			var hq := QuadMesh.new()
			var rad: float = town[1]
			hq.size = Vector2(rad * 3.2, rad * 0.9)
			hz.mesh = hq
			var hm := StandardMaterial3D.new()
			hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			hm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			hm.disable_fog = true
			hm.albedo_texture = CarModel._shadow_texture()
			hm.albedo_color = Color(0.45, 0.28, 0.15, 0.35)
			hz.material_override = hm
			var tc: Vector3 = town[0]
			hz.position = Vector3(tc.x, t.far_height(tc.x, tc.z) + rad * 0.25, tc.z)
			_add(hz)
		return
	# warm haze over the towns
	var glow := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(5200, 900)
	glow.mesh = gq
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	gm.disable_fog = true
	gm.albedo_texture = CarModel._shadow_texture()
	gm.albedo_color = Color(0.4, 0.25, 0.14, 0.4)
	glow.material_override = gm
	glow.position = finish + away * 3400.0 + Vector3(0, floor_y - finish.y + 120.0, 0)
	_add(glow)
	# the valley floor the towns sit on
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(16000, 16000)
	plane.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(0.012, 0.02, 0.045)
	plane.material_override = fm
	plane.position = Vector3(finish.x, floor_y - 2.0, finish.z)
	_add(plane)


# ------------------------------------------------------------------ roadside life
# Touches seen in Akina / Initial Drift Online / Drift86: lamp pools on a dark
# road, a summit car park with a rest house and glowing vending machines,
# curve mirrors, yellow warning signs, skid marks, a village at the bottom.

func _emissive(c: Color, energy := 2.0) -> StandardMaterial3D:
	var m := _mat(c, 0.4)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _piece(mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	_register_mesh(mesh, xf)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	_add(mi)
	return mi


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _clear_spot(p: Vector3, need: float) -> bool:
	return t.dist_to_road(p) >= need and not _blocked(p, 0.6) and not _buried(p, 0.4)


func _lamp(base: Vector3, toward_road: Vector3, warm: bool) -> void:
	# find a free spot: slide along the road if something already stands here
	var along := toward_road.cross(Vector3.UP).normalized()
	var spot := base
	var found := false
	for off: float in [0.0, 2.0, -2.0, 4.0, -4.0, 6.0, -6.0]:
		var c := base + along * off
		# the arm reaches 1.8 m toward the road, so check the pole and the arm tip
		if not _blocked(c, 0.35) and not _blocked(c + toward_road * 1.8, 0.4) and not _buried(c, 0.3):
			spot = c
			found = true
			break
	if not found:
		return
	base = spot
	var pole_mat := _mat(Color(0.45, 0.47, 0.52), 0.5)
	var col := Color(1.0, 0.72, 0.42) if warm else Color(0.85, 0.92, 1.0)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.1
	pole.height = 7.5
	pole.radial_segments = 6
	_piece(pole, pole_mat, Transform3D(Basis(), base + Vector3.UP * 3.75))
	var arm_basis := Basis.looking_at(toward_road, Vector3.UP)
	_piece(_boxm(Vector3(0.08, 0.08, 1.8)), pole_mat, Transform3D(arm_basis, base + Vector3.UP * 7.4 + toward_road * 0.9))
	_piece(_boxm(Vector3(0.36, 0.1, 0.6)), _emissive(col, 5.0), Transform3D(arm_basis, base + Vector3.UP * 7.3 + toward_road * 1.8))
	var l := SpotLight3D.new()
	l.light_color = col
	l.light_energy = 3.5
	l.spot_range = 16.0
	l.spot_angle = 55.0
	l.spot_attenuation = 0.9
	l.transform = Transform3D(Basis.looking_at(Vector3.DOWN, toward_road), base + Vector3.UP * 7.1 + toward_road * 1.8)
	_add(l)


func _street_lamps() -> void:
	# a lamp every couple of hundred metres, plus extra at the hairpins
	var next_s := 120.0
	var n := t.P.size()
	for i in n:
		var tight := absf(t.K[i]) > 1.0 / 20.0
		if t.S[i] < next_s and not (tight and t.S[i] > next_s - 120.0):
			continue
		var side := -signf(t.K[i]) if absf(t.K[i]) > 0.002 else (1.0 if (i / 50) % 2 == 0 else -1.0)
		var base: Vector3 = t.P[i] + t.R[i] * side * (t.rail + 0.7)
		if not _clear_spot(base, t.rail + 0.5) or wall_sides.has(Vector2i(i, int(side))):
			continue
		_lamp(base, -t.R[i] * side, true)
		next_s = t.S[i] + rng.randf_range(170.0, 260.0)


func _vending(p: Vector3, facing: Vector3) -> void:
	if _blocked(p, 0.6) or _buried(p, 0.5):
		return
	var b := Basis.looking_at(-facing, Vector3.UP)
	var palette := [Color(0.85, 0.12, 0.1), Color(0.1, 0.35, 0.85), Color(0.95, 0.95, 0.95)]
	var body := _mat(palette[rng.randi() % 3], 0.4)
	_piece(_boxm(Vector3(1.0, 1.85, 0.75)), body, Transform3D(b, p + Vector3.UP * 0.92))
	# bright display window and drinks row
	_piece(_boxm(Vector3(0.8, 0.9, 0.02)), _emissive(Color(0.95, 0.97, 1.0), 2.5), Transform3D(b, p + Vector3.UP * 1.3 + facing * 0.38))
	_piece(_boxm(Vector3(0.8, 0.12, 0.02)), _emissive(Color(1.0, 0.5, 0.2), 1.5), Transform3D(b, p + Vector3.UP * 0.75 + facing * 0.38))
	var l := OmniLight3D.new()
	l.light_color = Color(0.9, 0.95, 1.0)
	l.light_energy = 1.2
	l.omni_range = 6.0
	l.position = p + Vector3.UP * 1.3 + facing * 1.0
	_add(l)


func _building(p: Vector3, facing: Vector3, size: Vector3, wall: Color, roof: Color, lit := true) -> void:
	var b := Basis.looking_at(-facing, Vector3.UP)
	_piece(_boxm(size), _mat(wall, 0.85), Transform3D(b, p + Vector3.UP * size.y * 0.5))
	# low pitched roof
	var prism := PrismMesh.new()
	prism.size = Vector3(size.x + 0.6, 1.2, size.z + 0.6)
	_piece(prism, _mat(roof, 0.7), Transform3D(b, p + Vector3.UP * (size.y + 0.6)))
	if lit:
		var win := _emissive(Color(1.0, 0.82, 0.5), 1.8)
		for k in 2:
			var off := (k - 0.5) * size.x * 0.5
			_piece(_boxm(Vector3(size.x * 0.25, 0.8, 0.02)), win,
				Transform3D(b, p + Vector3.UP * (size.y * 0.55) + facing * (size.z * 0.5 + 0.01) + b.x * off))


func _summit_area() -> void:
	# car park beside the start, like the lakeside lot at the top of the pass
	var i := t.index_at_s(t.start_s + 5.0)
	var side := 1.0 if not wall_sides.has(Vector2i(i, 1)) else -1.0
	var right: Vector3 = t.R[i] * side
	var fwd: Vector3 = t.D[i]
	var centre: Vector3 = t.P[i] + right * (t.rail + 10.0)
	centre.y = t.P[i].y - 0.04
	var lot := MeshInstance3D.new()
	lot.mesh = _boxm(Vector3(16.0, 0.1, 34.0))
	lot.material_override = _mat(Color(0.16, 0.17, 0.2), 0.8)
	lot.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), centre)
	_add(lot)
	for k in 5:
		var line_p := centre + fwd * (-12.0 + k * 6.0) + right * 3.0 + Vector3.UP * 0.06
		_piece(_boxm(Vector3(0.12, 0.01, 4.5)), _mat(Color(0.85, 0.85, 0.82)), Transform3D(Basis.looking_at(right, Vector3.UP), line_p))
	_building(centre + right * 9.0 + fwd * 6.0, -right, Vector3(7.0, 3.0, 5.0), Color(0.7, 0.68, 0.6), Color(0.25, 0.28, 0.35))
	_vending(centre + right * 6.0 - fwd * 2.0, -right)
	_vending(centre + right * 6.0 - fwd * 3.2, -right)
	_lamp(centre - right * 7.5 + fwd * 10.0, right, false)
	_lamp(centre - right * 7.5 - fwd * 10.0, right, false)
	# a couple of parked cars
	var colors := [Color(0.75, 0.1, 0.1), Color(0.15, 0.15, 0.18), Color(0.9, 0.9, 0.92)]
	for k in 3:
		var m := CarModel.create(["coupe", "sedan", "hatch"][k], colors[k], colors[k].darkened(0.4))
		m.set_lights(false, true)
		m.position = centre + right * 3.0 + fwd * (-9.0 + k * 6.0)
		m.basis = Basis.looking_at(right, Vector3.UP) * Basis().scaled(Vector3.ONE * 0.92)
		_add(m)


func _sign_texture() -> ImageTexture:
	# yellow diamond with a black curve arrow
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var inside := absf(x - 31.5) + absf(y - 31.5) < 31.0
			var border := absf(x - 31.5) + absf(y - 31.5) > 27.5
			var c := Color(0, 0, 0, 0)
			if inside:
				c = Color(0.05, 0.05, 0.05) if border else Color(0.98, 0.78, 0.05)
				var dx := x - 30.0
				var dy := y - 38.0
				var r := sqrt(dx * dx + dy * dy)
				if r > 9.0 and r < 14.0 and dy < 0.0 and dx > -14.0:
					c = Color(0.05, 0.05, 0.05)
				if y > 37 and y < 50 and x > 16 and x < 21:
					c = Color(0.05, 0.05, 0.05)
				if absf(y - 25.0) < 6.0 - absf(x - 44.0) * 0.6 and x > 38 and x < 50:
					c = Color(0.05, 0.05, 0.05)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _curve_signs_and_mirrors() -> void:
	var sign_mat := _mat(Color.WHITE, 0.5)
	sign_mat.albedo_texture = _sign_texture()
	sign_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	sign_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sign_mat.emission_enabled = true
	sign_mat.emission_texture = sign_mat.albedo_texture
	sign_mat.emission = Color(0.35, 0.35, 0.35)
	var pole_mat := _mat(Color(0.6, 0.62, 0.65), 0.4)
	var orange := _mat(Color(0.96, 0.42, 0.06), 0.35)
	var mirror_mat := _mat(Color(0.82, 0.86, 0.92), 0.03)
	mirror_mat.metallic = 1.0
	var n := t.P.size()
	var i := 1
	var corner := 0
	while i < n:
		if absf(t.K[i]) < 1.0 / 30.0 or absf(t.K[i - 1]) >= 1.0 / 30.0:
			i += 1
			continue
		# warning sign ~55 m before the corner, on the left verge
		var si := t.index_at_s(maxf(t.S[i] - 55.0, 5.0))
		var sp: Vector3 = t.P[si] + t.R[si] * -1.0 * (t.rail + 0.6)
		if _clear_spot(sp, t.rail + 0.3):
			var face: Vector3 = -t.D[si]
			var q := QuadMesh.new()
			q.size = Vector2(0.9, 0.9)
			_piece(q, sign_mat, Transform3D(Basis.looking_at(-face, Vector3.UP), sp + Vector3.UP * 2.0))
			_piece(_boxm(Vector3(0.06, 2.0, 0.06)), pole_mat, Transform3D(Basis(), sp + Vector3.UP * 1.0))
		# curve mirror on the outside of every other tight corner
		if corner % 2 == 0:
			var j := mini(i + 6, n - 1)
			var side := -signf(t.K[i])
			var mp: Vector3 = t.P[j] + t.R[j] * side * (t.rail + 0.5)
			if _clear_spot(mp, t.rail + 0.3):
				var look: Vector3 = (-t.D[j] - t.R[j] * side * 0.6).normalized()
				_curve_mirror(mp, look, orange, mirror_mat)
		corner += 1
		i += 15


## Japanese curve mirror: tall orange pole, a short bracket, and a round
## convex mirror in a deep orange housing with a dark rim.
func _curve_mirror(base: Vector3, look: Vector3, orange: Material, mirror_mat: Material) -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.045
	pole.height = 3.2
	pole.radial_segments = 10
	_piece(pole, orange, Transform3D(Basis(), base + Vector3.UP * 1.6))
	var cap := SphereMesh.new()
	cap.radius = 0.05
	cap.height = 0.1
	_piece(cap, orange, Transform3D(Basis(), base + Vector3.UP * 3.2))
	var centre := base + Vector3.UP * 2.95 + look * 0.16
	var face_b := Basis.looking_at(look, Vector3.UP) * Basis(Vector3.RIGHT, -PI / 2)   # +Y -> look
	var back_b := Basis.looking_at(-look, Vector3.UP) * Basis(Vector3.RIGHT, -PI / 2)
	# bracket from the pole to the back of the housing
	_piece(_boxm(Vector3(0.06, 0.08, 0.2)), orange, Transform3D(Basis.looking_at(look, Vector3.UP), base + Vector3.UP * 2.95 + look * 0.06))
	# deep housing behind the mirror
	var shell := SphereMesh.new()
	shell.radius = 0.43
	shell.height = 0.26
	shell.is_hemisphere = true
	shell.radial_segments = 24
	shell.rings = 6
	_piece(shell, orange, Transform3D(back_b, centre))
	# convex mirror face, slightly domed
	var face := SphereMesh.new()
	face.radius = 0.39
	face.height = 0.07
	face.is_hemisphere = true
	face.radial_segments = 24
	face.rings = 4
	_piece(face, mirror_mat, Transform3D(face_b, centre + look * 0.01))
	# rim
	var rim := TorusMesh.new()
	rim.inner_radius = 0.37
	rim.outer_radius = 0.45
	rim.rings = 24
	rim.ring_segments = 6
	var rim_mat := _mat(Color(0.06, 0.06, 0.07), 0.6)
	_piece(rim, rim_mat, Transform3D(face_b, centre + look * 0.015))


## Raised concrete curb along every stretch with no wall, guardrail or tunnel,
## with the grass bank behind it, like the night corners in the anime's
## background paintings. One continuous strip per run so it reads smooth.
func _curbs() -> void:
	var curb := Mats.pbr("concrete", 1.0, Color(0.9, 0.9, 0.88))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# section across the curb (lateral offset from the rail line, height)
	var prof := [[-0.06, -0.06], [-0.05, 0.16], [0.0, 0.19], [0.22, 0.19], [0.26, -0.08]]
	var n := t.P.size()
	for side: float in [-1.0, 1.0]:
		for i in range(1, n):
			var ok := true
			for j in [i - 1, i]:
				if t.has_rail(j, side) or t.in_tunnel(j) or wall_sides.has(Vector2i(j, int(side))):
					ok = false
			if not ok:
				continue
			var u0 := t.S[i - 1] / 2.0
			var u1 := t.S[i] / 2.0
			for k in prof.size() - 1:
				var la: float = t.rail + prof[k][0]
				var lb: float = t.rail + prof[k + 1][0]
				var ha: float = prof[k][1]
				var hb: float = prof[k + 1][1]
				var a: Vector3 = t.P[i - 1] + t.R[i - 1] * side * la + Vector3.UP * ha
				var b: Vector3 = t.P[i - 1] + t.R[i - 1] * side * lb + Vector3.UP * hb
				var c: Vector3 = t.P[i] + t.R[i] * side * la + Vector3.UP * ha
				var d: Vector3 = t.P[i] + t.R[i] * side * lb + Vector3.UP * hb
				var e := Vector2(lb - la, hb - ha)
				var nrm := (t.R[i] * side * -e.y + Vector3.UP * e.x).normalized()
				if nrm.y < -0.1:
					nrm = -nrm
				st.set_normal(nrm)
				var va := float(k) * 0.1
				var vb := float(k + 1) * 0.1
				for q in [[a, Vector2(u0, va)], [c, Vector2(u1, va)], [b, Vector2(u0, vb)], [b, Vector2(u0, vb)], [c, Vector2(u1, va)], [d, Vector2(u1, vb)]]:
					st.set_uv(q[1])
					st.add_vertex(q[0])
	st.set_material(curb)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	curb.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add(mi)


func _skid_marks() -> void:
	# black rubber laid down through the hairpins by years of drifting
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := t.P.size()
	var i := 0
	while i < n:
		if absf(t.K[i]) < 1.0 / 35.0:
			i += 1
			continue
		var j := i
		while j < n and absf(t.K[j]) >= 1.0 / 35.0:
			j += 1
		var inner := signf(t.K[i])
		for set_k in rng.randi_range(2, 4):
			var s0: float = t.S[maxi(i - 12, 0)] + rng.randf_range(-5.0, 5.0)
			var s1: float = t.S[mini(j + 10, n - 1)] + rng.randf_range(-5.0, 5.0)
			var swing := rng.randf_range(0.6, 1.0) * (t.hw - 1.0)
			for wheel in [-0.68, 0.68]:
				var prev_l := Vector3.INF
				var prev_r := Vector3.INF
				var steps := int((s1 - s0) / 2.0)
				for k in steps + 1:
					var s := s0 + (s1 - s0) * k / maxf(steps, 1.0)
					var f := float(k) / maxf(steps, 1.0)
					# outside-inside-outside arc
					var lat: float = -inner * swing * cos(f * PI) * 0.8 + inner * swing * 0.2 + wheel
					var c := t.point_at(s, clampf(lat, -t.hw + 0.2, t.hw - 0.2)) + Vector3.UP * 0.011
					var r := t.dir_at(s).cross(Vector3.UP) * 0.11
					var l := c - r
					var rr := c + r
					if prev_l != Vector3.INF:
						st.set_normal(Vector3.UP)
						st.add_vertex(prev_l); st.add_vertex(l); st.add_vertex(prev_r)
						st.add_vertex(prev_r); st.add_vertex(l); st.add_vertex(rr)
					prev_l = l
					prev_r = rr
		i = j + 1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.0, 0.0, 0.0, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	_add(mi)


func _village() -> void:
	# houses with lit windows near the bottom of the pass
	var n := t.P.size()
	var placed := 0
	var walls := [Color(0.72, 0.68, 0.6), Color(0.6, 0.62, 0.66), Color(0.75, 0.72, 0.65)]
	var roofs := [Color(0.22, 0.26, 0.34), Color(0.35, 0.18, 0.15), Color(0.2, 0.22, 0.25)]
	for i in range(n - 1, maxi(n - 260, 0), -7):
		if placed >= 9:
			break
		var side := 1.0 if placed % 2 == 0 else -1.0
		var p: Vector3 = t.P[i] + t.R[i] * side * (t.rail + rng.randf_range(9.0, 16.0))
		if not _clear_spot(p, t.rail + 7.0):
			continue
		p.y = minf(t.terrain_height(p.x, p.z), t.P[i].y) - 0.2
		var face: Vector3 = -t.R[i] * side
		_building(p, face, Vector3(rng.randf_range(6.0, 9.0), rng.randf_range(3.0, 5.5), rng.randf_range(5.0, 7.0)),
			walls[placed % 3], roofs[placed % 3], rng.randf() < 0.75)
		if placed == 2:
			_vending(t.P[i] + t.R[i] * side * (t.rail + 2.5), face)
		placed += 1


# ------------------------------------------------------------------ rock-fall protection

func _lattice_texture() -> ImageTexture:
	# concrete grid frame on a cut slope, soil and weeds in the cells
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var beam := (x % 32) < 5 or (y % 32) < 5
			var c := Color(0.5, 0.53, 0.58) if beam else Color(0.08, 0.13, 0.12).lerp(Color(0.12, 0.2, 0.14), float((x * 7 + y * 13) % 17) / 17.0)
			if beam and ((x % 32) == 4 or (y % 32) == 4):
				c = Color(0.32, 0.34, 0.38)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _net_texture() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var on := (x + y) % 16 == 0 or (x - y + 64) % 16 == 0
			img.set_pixel(x, y, Color(0.7, 0.74, 0.8, 1.0) if on else Color(0, 0, 0, 0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _slope_protection() -> void:
	# Where the real hillside rises tall and steep beside the road, cover it
	# like Japanese mountain roads do: concrete lattice frames or wire rock
	# netting, with a rock-fall catch fence along the bottom.
	# painted moonlit look so the frames read at night, like the anime BGs
	var lattice := _mat(Color(0.66, 0.68, 0.7), 0.9)
	lattice.albedo_texture = _lattice_texture()
	lattice.cull_mode = BaseMaterial3D.CULL_DISABLED
	var net := _mat(Color(0.6, 0.64, 0.7), 0.6)
	net.albedo_texture = _net_texture()
	net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	net.alpha_scissor_threshold = 0.4
	net.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lst := SurfaceTool.new()
	lst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nst := SurfaceTool.new()
	nst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fence_mat := _mat(Color.WHITE, 0.6)
	fence_mat.albedo_texture = _net_texture()
	fence_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fence_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var post_xf: Array = []
	var n := t.P.size()
	# the first row is the foot: on the wall line, down at road level, so the
	# frame meets the road edge and no bare hillside shows underneath it
	var lats := [0.9, 1.6, 4.0, 7.0, 10.5, 14.5, 19.0, 24.0]
	for side: float in [-1.0, 1.0]:
		var prev: Array = []
		var prev_ok := false
		var run_kind := 0
		for i in range(0, n, 2):
			var high := t.terrain_height(t.P[i].x + t.R[i].x * side * (t.rail + 14.0), t.P[i].z + t.R[i].z * side * (t.rail + 14.0)) - t.P[i].y
			var ok: bool = not t.style.get("rock_faces", false) and high > 18.0 and t.dist_to_road(t.P[i] + t.R[i] * side * (t.rail + 14.0)) > t.rail + 4.0
			var row: Array = []
			if ok:
				for l in lats:
					var p: Vector3 = t.P[i] + t.R[i] * side * (t.rail + l)
					var hy := t.terrain_height(p.x, p.z)
					if l < 1.0:
						p.y = t.P[i].y - 0.05
					else:
						p.y = maxf(hy, t.P[i].y + 0.2) + 0.5
					caps.append(Vector3(p.x, p.y - 0.45, p.z))
					row.append(p)
			if ok and not prev_ok:
				run_kind = int(t.S[i] / 90.0) % 2
			if ok and prev_ok:
				var st: SurfaceTool = lst if run_kind == 0 else nst
				var u0 := t.S[i - 2] / 6.0
				var u1 := t.S[i] / 6.0
				for k in lats.size() - 1:
					var a: Vector3 = prev[k]
					var b: Vector3 = row[k]
					var c: Vector3 = row[k + 1]
					var d: Vector3 = prev[k + 1]
					var v0 := float(lats[k]) / 6.0
					var v1 := float(lats[k + 1]) / 6.0
					var nrm := (b - a).cross(d - a).normalized()
					if nrm.y < 0.0:
						nrm = -nrm
					st.set_normal(nrm)
					st.set_uv(Vector2(u0, v0)); st.add_vertex(a)
					st.set_uv(Vector2(u1, v0)); st.add_vertex(b)
					st.set_uv(Vector2(u1, v1)); st.add_vertex(c)
					st.set_uv(Vector2(u0, v0)); st.add_vertex(a)
					st.set_uv(Vector2(u1, v1)); st.add_vertex(c)
					st.set_uv(Vector2(u0, v1)); st.add_vertex(d)
				# catch fence at the foot of netted slopes
				if run_kind == 1:
					var fa: Vector3 = prev[0] + Vector3.UP * 0.0
					var fb: Vector3 = row[0]
					var up := Vector3.UP * 2.6
					fst.set_normal(-t.R[i] * side)
					fst.set_uv(Vector2(u0, 1)); fst.add_vertex(fa)
					fst.set_uv(Vector2(u1, 1)); fst.add_vertex(fb)
					fst.set_uv(Vector2(u1, 0)); fst.add_vertex(fb + up)
					fst.set_uv(Vector2(u0, 1)); fst.add_vertex(fa)
					fst.set_uv(Vector2(u1, 0)); fst.add_vertex(fb + up)
					fst.set_uv(Vector2(u0, 0)); fst.add_vertex(fa + up)
					if int(t.S[i] / 4.0) != int(t.S[i - 2] / 4.0):
						post_xf.append(Transform3D(Basis(), fb + Vector3.UP * 1.3))
			prev = row
			prev_ok = ok
	for pair in [[lst, lattice], [nst, net], [fst, fence_mat]]:
		var st2: SurfaceTool = pair[0]
		st2.set_material(pair[1])
		var mi := MeshInstance3D.new()
		mi.mesh = st2.commit()
		_add(mi)
	var post := _boxm(Vector3(0.12, 2.7, 0.12))
	_mm(post, post_xf, _mat(Color(0.5, 0.52, 0.56), 0.5))


# ------------------------------------------------------------------ real-world features (OpenStreetMap)

func _poly_y(poly: Array) -> float:
	var y := INF
	for p in poly:
		y = minf(y, t.terrain_height(p[0], p[1]))
	return y


func _real_features() -> void:
	var walls := [Color(0.72, 0.7, 0.64), Color(0.62, 0.64, 0.68), Color(0.78, 0.74, 0.66), Color(0.55, 0.5, 0.45)]
	var roofs := [Color(0.22, 0.26, 0.34), Color(0.36, 0.2, 0.16), Color(0.2, 0.22, 0.25), Color(0.3, 0.32, 0.3)]
	var win := _emissive(Color(1.0, 0.82, 0.5), 1.6)
	# buildings: real footprints extruded, low hip roof, some lit windows
	for b in t.features.get("buildings", []):
		var poly: Array = b.poly
		if poly.size() < 4:
			continue
		# keep houses off the road (including the run-off past the finish)
		var on_road := false
		for p in poly:
			if t.dist_to_road(Vector3(p[0], 0.0, p[1])) < t.rail + 2.0:
				on_road = true
				break
		if on_road:
			continue
		var base := _poly_y(poly) - 0.3
		var h: float = clampf(float(b.h), 3.0, 30.0)
		var k := rng.randi() % walls.size()
		_extrude(poly, base, h, _facade_mat(walls[k]), _roof_mat(roofs[k]), win)
	# parking lots: flat asphalt on their real outline, with a lamp
	var lot_mat := _mat(Color(0.15, 0.16, 0.19), 0.8)
	for poly in t.features.get("parking", []):
		var pts := PackedVector2Array()
		for p in poly:
			pts.append(Vector2(p[0], p[1]))
		if pts.size() > 3 and pts[0] == pts[pts.size() - 1]:
			pts.remove_at(pts.size() - 1)
		var tris := Geometry2D.triangulate_polygon(pts)
		if tris.is_empty():
			continue
		var y := _poly_y(poly) + 0.05
		for p in poly:
			y = maxf(y, t.terrain_height(p[0], p[1]) - 1.5)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		for k in range(0, tris.size(), 3):
			for m in [0, 2, 1]:
				var v := pts[tris[k + m]]
				st.add_vertex(Vector3(v.x, y, v.y))
		st.set_material(lot_mat)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		_add(mi)
		var c := Vector2.ZERO
		for v in pts:
			c += v
		c /= pts.size()
		var to_road: Vector3 = t.P[t.nearest_index(Vector3(c.x, y, c.y))] - Vector3(c.x, y, c.y)
		to_road.y = 0.0
		_lamp(Vector3(c.x, y, c.y), to_road.normalized() if to_road.length() > 0.1 else Vector3.FORWARD, false)
	# roadside points
	for f in t.features.get("points", []):
		var i := int(f.i)
		var side: float = f.side
		var face: Vector3 = -t.R[i] * side
		var at: Vector3 = t.P[i] + t.R[i] * side * (t.rail + 1.5)
		at.y = t.P[i].y
		match f.kind:
			"bus_stop":
				_bus_stop(at, face)
			"toilets":
				_building(at - face * 4.0, face, Vector3(4.0, 2.8, 3.0), Color(0.75, 0.73, 0.68), Color(0.3, 0.3, 0.32))
				_lamp(at, face, false)
			"viewpoint":
				_lamp(at, face, false)
				_vending(at - face * 2.0 + t.D[i] * 3.0, face)
			"street_lamp":
				_lamp(at, face, true)
	# the blue overhead direction sign at the Ikaho end (seen on Street View)
	var si := t.index_at_s(t.finish_s - 60.0)
	var sd: Vector3 = t.D[si]
	var sr: Vector3 = t.R[si]
	var base: Vector3 = t.P[si]
	var gray := _mat(Color(0.55, 0.57, 0.6), 0.5)
	_piece(_boxm(Vector3(0.25, 6.5, 0.25)), gray, Transform3D(Basis(), base + sr * (t.rail + 0.8) + Vector3.UP * 3.25))
	_piece(_boxm(Vector3(0.15, 0.15, t.rail + 1.5)), gray, Transform3D(Basis.looking_at(-sr, Vector3.UP), base + sr * 0.7 + Vector3.UP * 6.3))
	var board := _piece(_boxm(Vector3(4.2, 2.0, 0.1)), _emissive(Color(0.05, 0.22, 0.7), 0.35), Transform3D(Basis.looking_at(sd, Vector3.UP), base + Vector3.UP * 5.4))
	var sign_lines: Array = t.sign_text if t.sign_text.size() >= 2 else ["↑", "→"]
	for line in [[sign_lines[0], 0.45], [sign_lines[1], -0.35]]:
		var lab := Label3D.new()
		lab.text = line[0]
		lab.font_size = 64
		lab.pixel_size = 0.0075
		lab.outline_size = 0
		lab.modulate = Color(0.95, 0.95, 0.95)
		lab.transform = Transform3D(Basis.looking_at(-sd, Vector3.UP), base + Vector3.UP * (5.4 + line[1]) - sd * 0.06)
		_add(lab)
	# bridges: concrete parapets instead of guardrails
	var para := _mat(Color(0.55, 0.58, 0.64), 0.8)
	for br in t.features.get("bridges", []):
		for side: float in [-1.0, 1.0]:
			for i in range(int(br[0]), int(br[1])):
				var a: Vector3 = t.P[i] + t.R[i] * side * (t.rail - 0.1)
				var b: Vector3 = t.P[i + 1] + t.R[i + 1] * side * (t.rail - 0.1)
				var mid := (a + b) * 0.5
				var len := a.distance_to(b)
				_piece(_boxm(Vector3(0.3, 0.9, len + 0.05)), para, Transform3D(Basis.looking_at(b - a, Vector3.UP), mid + Vector3.UP * 0.45))


func _bus_stop(at: Vector3, face: Vector3) -> void:
	# a small mountain bus shelter: framed back panel (timetable + poster),
	# side panels, roof and bench, with the round stop sign on its own pole
	var along := face.cross(Vector3.UP).normalized()
	var back := at - face * 1.8
	if _blocked(back, 1.7) or _blocked(at + along * 2.0, 0.4) or _buried(back, 1.5) or _buried(at, 0.5):
		return
	var fb := Basis.looking_at(face, Vector3.UP)
	var frame := _mat(Color(0.32, 0.34, 0.38), 0.5)
	# back panel with the printed board facing the road
	_piece(_boxm(Vector3(3.0, 2.3, 0.08)), frame, Transform3D(fb, back + Vector3.UP * 1.15))
	var panel := QuadMesh.new()
	panel.size = Vector2(2.7, 2.0)
	var pm := _mat(Color.WHITE, 0.7)
	pm.albedo_texture = load("res://assets/textures/shelter_panel.png")
	pm.emission_enabled = true
	pm.emission_texture = pm.albedo_texture
	pm.emission = Color(0.12, 0.12, 0.12)
	_piece(panel, pm, Transform3D(Basis.looking_at(-face, Vector3.UP), back + face * 0.05 + Vector3.UP * 1.2))
	# side panels and roof
	for sd: float in [-1.0, 1.0]:
		_piece(_boxm(Vector3(0.06, 2.3, 1.4)), frame, Transform3D(fb, back + along * sd * 1.47 + face * 0.7 + Vector3.UP * 1.15))
	_piece(_boxm(Vector3(3.3, 0.08, 1.7)), frame, Transform3D(fb, back + face * 0.75 + Vector3.UP * 2.34))
	# bench
	_piece(_boxm(Vector3(2.2, 0.06, 0.4)), _mat(Color(0.55, 0.4, 0.25), 0.7), Transform3D(fb, back + face * 0.35 + Vector3.UP * 0.45))
	for sd: float in [-0.9, 0.9]:
		_piece(_boxm(Vector3(0.06, 0.45, 0.35)), frame, Transform3D(fb, back + face * 0.35 + along * sd + Vector3.UP * 0.22))
	# stop sign beside the shelter, plate facing the road both ways
	var sp := at + along * 2.0
	var pole := CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.05
	pole.height = 2.2
	_piece(pole, _mat(Color(0.75, 0.75, 0.77), 0.4), Transform3D(Basis(), sp + Vector3.UP * 1.1))
	var plate := QuadMesh.new()
	plate.size = Vector2(0.62, 0.62)
	var sm := _mat(Color.WHITE, 0.5)
	sm.albedo_texture = load("res://assets/textures/bus_stop_sign.png")
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	sm.alpha_scissor_threshold = 0.5
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.emission_enabled = true
	sm.emission_texture = sm.albedo_texture
	sm.emission = Color(0.3, 0.3, 0.3)
	_piece(plate, sm, Transform3D(Basis.looking_at(-along, Vector3.UP), sp + Vector3.UP * 2.25))
	# lamp on the far side of the shelter, clear of the roof
	_lamp(at - along * 2.6, face, false)


func _extrude(poly: Array, base: float, h: float, wall_mat: Material, roof_mat: Material, win_mat: Material) -> void:
	var pts := PackedVector2Array()
	for p in poly:
		pts.append(Vector2(p[0], p[1]))
	if pts[0].distance_to(pts[pts.size() - 1]) < 0.01:
		pts.remove_at(pts.size() - 1)
	if pts.size() < 3:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cen := Vector2.ZERO
	for v in pts:
		cen += v
	cen /= pts.size()
	# the whole footprint is off limits to trees and props
	var reach := 0.0
	for v in pts:
		reach = maxf(reach, v.distance_to(cen))
	_keep_out(Vector3(cen.x, base, cen.y), reach + 0.5)
	for k in pts.size():
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		var e := b - a
		var nrm := Vector3(e.y, 0, -e.x).normalized()
		if nrm.dot(Vector3((a + b).x * 0.5 - cen.x, 0, (a + b).y * 0.5 - cen.y)) < 0.0:
			nrm = -nrm
		st.set_normal(nrm)
		var a0 := Vector3(a.x, base, a.y)
		var b0 := Vector3(b.x, base, b.y)
		var a1 := a0 + Vector3.UP * h
		var b1 := b0 + Vector3.UP * h
		# facade texture: one tile = 8 m wide, two storeys (6 m) tall
		var ua := 0.0
		var ub := e.length() / 8.0
		var vt := 0.0
		var vb := h / 6.0
		st.set_uv(Vector2(ua, vb)); st.add_vertex(a0)
		st.set_uv(Vector2(ub, vt)); st.add_vertex(b1)
		st.set_uv(Vector2(ub, vb)); st.add_vertex(b0)
		st.set_uv(Vector2(ua, vb)); st.add_vertex(a0)
		st.set_uv(Vector2(ua, vt)); st.add_vertex(a1)
		st.set_uv(Vector2(ub, vt)); st.add_vertex(b1)
		# windows now come from the facade texture
		if false:
			var mid := (a + b) * 0.5
			var wb := Basis.looking_at(-nrm, Vector3.UP)
			_piece(_boxm(Vector3(minf(e.length() * 0.4, 3.0), 0.9, 0.05)), win_mat,
				Transform3D(wb, Vector3(mid.x, base + minf(h * 0.55, 2.0), mid.y) + nrm * 0.04))
	var wm := MeshInstance3D.new()
	st.set_material(wall_mat)
	wm.mesh = st.commit()
	wm.material_override = wall_mat
	if wall_mat is BaseMaterial3D:
		wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add(wm)
	# flat roof slab with a slight overhang (Japanese houses vary; a slab reads well at night)
	var tris := Geometry2D.triangulate_polygon(pts)
	if tris.is_empty():
		return
	var rt := SurfaceTool.new()
	rt.begin(Mesh.PRIMITIVE_TRIANGLES)
	rt.set_normal(Vector3.UP)
	for k in range(0, tris.size(), 3):
		for m in [0, 2, 1]:
			var v := pts[tris[k + m]]
			var o := (v - cen).normalized() * 0.4
			rt.set_uv(Vector2(v.x + o.x, v.y + o.y) * 0.25)
			rt.add_vertex(Vector3(v.x + o.x, base + h + 0.05, v.y + o.y))
	var rm := MeshInstance3D.new()
	roof_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rt.set_material(roof_mat)
	rm.mesh = rt.commit()
	_add(rm)


var _facade_tex: Texture2D
var _roof_tex: Texture2D


func _facade_mat(wall: Color) -> ShaderMaterial:
	if _facade_tex == null:
		_facade_tex = load("res://assets/textures/facade.png")
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/building.gdshader")
	m.set_shader_parameter("facade", _facade_tex)
	m.set_shader_parameter("wall_tint", Vector3(wall.r, wall.g, wall.b) * 1.15)
	m.set_shader_parameter("lit_share", rng.randf_range(0.3, 0.7))
	return m


func _roof_mat(c: Color) -> StandardMaterial3D:
	if _roof_tex == null:
		_roof_tex = load("res://assets/textures/roof_tiles.png")
	var m := Mats.pbr("roof", 1.0, (c * 3.0).lerp(Color.WHITE, 0.5))
	return m


func _red_pavement() -> void:
	# coloured anti-slip surfacing on the approach to tight corners (Myogi)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := t.P.size()
	var i := 1
	while i < n:
		if absf(t.K[i]) < 1.0 / 35.0 or absf(t.K[i - 1]) >= 1.0 / 35.0:
			i += 1
			continue
		var s1: float = t.S[i]
		var s0: float = maxf(s1 - 45.0, 2.0)
		var steps := int((s1 - s0) / 2.0)
		for k in steps:
			var a := t.point_at(s0 + k * 2.0, -t.hw + 0.3) + Vector3.UP * 0.01
			var b := t.point_at(s0 + k * 2.0, t.hw - 0.3) + Vector3.UP * 0.01
			var c := t.point_at(s0 + k * 2.0 + 2.0, -t.hw + 0.3) + Vector3.UP * 0.01
			var d := t.point_at(s0 + k * 2.0 + 2.0, t.hw - 0.3) + Vector3.UP * 0.01
			st.set_normal(Vector3.UP)
			st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
			st.add_vertex(b); st.add_vertex(c); st.add_vertex(d)
		i += 25
	var m := _mat(Color(0.5, 0.16, 0.12), 0.8)
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	_add(mi)


func _chevron_rows() -> void:
	# corner arrow boards: small yellow panels on posts behind the rail on the
	# outside of tight corners, facing the driver, arrows pointing round the bend
	var tex: Texture2D = load("res://assets/textures/chevron.png")
	var mats := {}
	for dir in [1.0, -1.0]:
		var m := _mat(Color.WHITE, 0.5)
		m.albedo_texture = tex
		m.uv1_scale = Vector3(dir, 1, 1)
		m.emission_enabled = true
		m.emission_texture = tex
		m.emission = Color(0.35, 0.35, 0.35)
		mats[dir] = m
	var back_mat := _mat(Color(0.3, 0.32, 0.35), 0.6)
	var post_mat := _mat(Color(0.7, 0.72, 0.75), 0.4)
	var face_q := QuadMesh.new()
	face_q.size = Vector2(0.6, 0.75)
	var n := t.P.size()
	var i := 0
	while i < n:
		if absf(t.K[i]) < 1.0 / 30.0:
			i += 1
			continue
		var j := i
		while j < n and absf(t.K[j]) >= 1.0 / 30.0:
			j += 1
		var side := -signf(t.K[i])            # outside of the corner
		var turn_right: float = 1.0 if t.K[i] > 0.0 else -1.0
		for k in range(i, j, 4):
			var p: Vector3 = t.P[k] + t.R[k] * side * (t.rail + 0.45)
			if not _clear_spot(p, t.rail + 0.2):
				continue
			var b := Basis.looking_at(t.D[k], Vector3.UP)      # face toward oncoming cars
			_piece(face_q, mats[turn_right], Transform3D(b, p + Vector3.UP * 1.25 - t.D[k] * 0.03))
			_piece(_boxm(Vector3(0.62, 0.77, 0.03)), back_mat, Transform3D(b, p + Vector3.UP * 1.25))
			for sx: float in [-0.2, 0.2]:
				_piece(_boxm(Vector3(0.05, 1.2, 0.05)), post_mat, Transform3D(b, p + b.x * sx + Vector3.UP * 0.6 + t.D[k] * 0.04))
		i = j


# ------------------------------------------------------------------ tunnels

func _tunnels() -> void:
	# Japanese mountain tunnel: straight side walls faced with light tiles up
	# to ~1.8 m, a concrete arch above, raised walkway curbs on both sides and a
	# line of sodium lamp fixtures along one side of the arch.
	var tile_img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var grout := x % 16 == 0 or y % 16 == 0
			var v := 0.62 + 0.04 * sin(float(x * 7 + y * 13))
			tile_img.set_pixel(x, y, Color(0.38, 0.38, 0.37) if grout else Color(v, v * 0.98, v * 0.93))
	tile_img.generate_mipmaps()
	var tiles := _mat(Color(0.8, 0.8, 0.78), 0.35)
	tiles.albedo_texture = ImageTexture.create_from_image(tile_img)
	tiles.cull_mode = BaseMaterial3D.CULL_DISABLED
	var arch := Mats.pbr("concrete", 1.0, Color(0.6, 0.6, 0.6))
	arch.cull_mode = BaseMaterial3D.CULL_DISABLED
	var curb_mat := _mat(Color(0.58, 0.58, 0.56), 0.9)
	curb_mat.albedo_texture = load("res://assets/textures/concrete.png")
	curb_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var housing := _mat(Color(0.25, 0.25, 0.27), 0.6)
	var lamp := _emissive(Color(1.0, 0.62, 0.22), 7.0)
	var portal_mat := _mat(Color(0.6, 0.6, 0.58), 0.9)
	portal_mat.albedo_texture = load("res://assets/textures/concrete.png")
	for tn in t.tunnels:
		var w := t.rail + 0.3
		var spring := 1.9                     # where the walls turn into the arch
		var rise := w * 0.78                  # arch height above the springline
		# cross-section (lateral, height, surface of the segment ENDING here:
		# 0 = wall tiles, 1 = arch, 2 = walkway). The walkway is part of the
		# section, so it runs smooth and continuous along the whole tunnel.
		var walk := 0.85      # walkway width
		var kerb := 0.22      # kerb height
		var prof := [[-(w - walk), -0.05, 2], [-(w - walk), kerb, 2], [-(w - walk) - 0.06, kerb + 0.02, 2],
			[-w, kerb + 0.03, 2], [-w, spring, 0]]
		for k in range(1, 12):
			var ang := PI - PI * k / 12.0
			prof.append([w * cos(ang), spring + rise * sin(ang), 1])
		prof.append([w, spring, 1])
		prof.append([w, kerb + 0.03, 0])
		prof.append([(w - walk) + 0.06, kerb + 0.02, 2])
		prof.append([w - walk, kerb, 2])
		prof.append([w - walk, -0.05, 2])
		var sts := [SurfaceTool.new(), SurfaceTool.new(), SurfaceTool.new()]
		for st: SurfaceTool in sts:
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var i0: int = maxi(int(tn[0]), 1)
		var i1: int = mini(int(tn[1]), t.P.size() - 1)
		# running length around the profile for texture coordinates
		var plen := [0.0]
		for k in range(1, prof.size()):
			plen.append(plen[k - 1] + Vector2(prof[k][0] - prof[k - 1][0], prof[k][1] - prof[k - 1][1]).length())
		for i in range(i0, i1 + 1):
			var v0: float = t.S[i - 1] / 2.0
			var v1: float = t.S[i] / 2.0
			for k in prof.size() - 1:
				var surf: int = prof[k + 1][2]
				var st: SurfaceTool = sts[surf]
				var a: Vector3 = t.P[i - 1] + t.R[i - 1] * prof[k][0] + Vector3.UP * prof[k][1]
				var b: Vector3 = t.P[i - 1] + t.R[i - 1] * prof[k + 1][0] + Vector3.UP * prof[k + 1][1]
				var c: Vector3 = t.P[i] + t.R[i] * prof[k][0] + Vector3.UP * prof[k][1]
				var d: Vector3 = t.P[i] + t.R[i] * prof[k + 1][0] + Vector3.UP * prof[k + 1][1]
				var u0: float = plen[k] / 2.0
				var u1: float = plen[k + 1] / 2.0
				var inward: Vector3 = (t.P[i] + Vector3.UP * 2.5 - (a + d) * 0.5).normalized()
				st.set_normal(inward)
				st.set_uv(Vector2(u0, v0)); st.add_vertex(a)
				st.set_uv(Vector2(u1, v0)); st.add_vertex(b)
				st.set_uv(Vector2(u0, v1)); st.add_vertex(c)
				st.set_uv(Vector2(u1, v0)); st.add_vertex(b)
				st.set_uv(Vector2(u1, v1)); st.add_vertex(d)
				st.set_uv(Vector2(u0, v1)); st.add_vertex(c)
			# lamp fixtures in a line along the left side of the arch
			if (i - i0) % 5 == 0:
				var lp: Vector3 = t.P[i] + t.R[i] * (-w * 0.55) + Vector3.UP * (spring + rise * 0.82)
				var lb := Basis.looking_at(t.D[i], Vector3.UP) * Basis(Vector3.BACK, -0.6)
				_piece(_boxm(Vector3(0.45, 0.16, 1.3)), housing, Transform3D(lb, lp))
				_piece(_boxm(Vector3(0.34, 0.04, 1.1)), lamp, Transform3D(lb, lp + lb.y * -0.08))
				if (i - i0) % 15 == 0:
					var l := OmniLight3D.new()
					l.light_color = Color(1.0, 0.62, 0.3)
					l.light_energy = 3.0
					l.omni_range = 18.0
					l.position = lp + Vector3.DOWN * 1.0 + t.R[i] * 1.0
					_add(l)
		for k in 3:
			var st: SurfaceTool = sts[k]
			st.set_material([tiles, arch, curb_mat][k])
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			_add(mi)
		# portals: a concrete headwall with the arch opening, wing walls either side
		for end in [i0, i1]:
			var fwd: Vector3 = t.D[end] * (-1.0 if end == i0 else 1.0)
			var b := Basis.looking_at(fwd, Vector3.UP)
			var top := spring + rise
			var pc: Vector3 = t.P[end] + Vector3.UP * (top + 2.4) + fwd * 0.4
			_piece(_boxm(Vector3(w * 2.0 + 4.0, 4.4, 0.8)), portal_mat, Transform3D(b, pc))
			# arch ring around the opening
			for k in 12:
				var ang := PI * (k + 0.5) / 12.0
				var rp: Vector3 = t.P[end] + t.R[end] * (w + 0.35) * cos(ang) + Vector3.UP * (spring + (rise + 0.35) * sin(ang)) + fwd * 0.45
				_piece(_boxm(Vector3(0.6, 0.7, 0.9)), portal_mat, Transform3D(b * Basis(Vector3.BACK, -ang + PI / 2), rp))
			for sd: float in [-1.0, 1.0]:
				var side_p: Vector3 = t.P[end] + t.R[end] * sd * (w + 1.4) + Vector3.UP * (top * 0.5 + 0.8) + fwd * 0.4
				_piece(_boxm(Vector3(2.0, top + 1.6, 0.8)), portal_mat, Transform3D(b, side_p))
