class_name Track
extends Node3D
## Builds a downhill touge road from a segment list and answers spatial
## queries (nearest point, lateral offset, surface height) for the cars.

const GUTTER_DEPTH := 0.17
const GUTTER_W := 0.55
const SHOULDER := 0.45
const LEAD_IN := 30.0

var course: Dictionary
var hw := 3.3          # half road width
var rail := 0.0        # lateral position of guardrails

var P := PackedVector3Array()   # centerline points
var D := PackedVector3Array()   # horizontal forward dirs
var R := PackedVector3Array()   # horizontal right dirs
var S := PackedFloat32Array()   # cumulative distance
var K := PackedFloat32Array()   # signed curvature (+ = right turn)
var G := PackedFloat32Array()   # grade (fraction, negative = downhill)
var grass_l := PackedFloat32Array()
var grass_r := PackedFloat32Array()

var length := 0.0
var start_s := LEAD_IN
var finish_s := 0.0
var drop := 0.0
var hairpins := 0
var overlaps := 0
var min_y := 0.0


func build(c: Dictionary) -> void:
	course = c
	hw = c.get("width", 6.6) * 0.5
	rail = hw + GUTTER_W + SHOULDER
	build_centerline(c)
	_compute_grass()
	finish_s = length - 25.0
	_build_road_mesh()
	_build_markings()
	_build_guardrails()
	_build_trees()
	_build_start_finish()
	_build_ground()


# ---------------------------------------------------------------- geometry

func build_centerline(c: Dictionary) -> void:
	course = c
	if c.has("data"):
		_load_traced(c.data)
	else:
		_generate_centerline(c.segments, c.get("grade", -7.0))

func _generate_centerline(segs: Array, default_grade: float) -> void:
	var heads: Array[float] = []
	var curvs: Array[float] = []
	var grades: Array[float] = []
	var dists: Array[float] = []
	var all_segs: Array = [["S", LEAD_IN, -2.0]] + segs + [["S", 60, -2.0]]
	for seg in all_segs:
		var seg_len: float
		var curv := 0.0
		var grade: float = default_grade
		if seg[0] == "S":
			seg_len = seg[1]
			if seg.size() > 2:
				grade = seg[2]
		else:
			var radius: float = seg[2]
			seg_len = radius * deg_to_rad(seg[1])
			curv = (1.0 if seg[0] == "R" else -1.0) / radius
			if seg.size() > 3:
				grade = seg[3]
			if seg[1] >= 140.0:
				hairpins += 1
		var n := maxi(1, roundi(seg_len / 2.0))
		var ds := seg_len / n
		for k in n:
			curvs.append(curv)
			grades.append(grade / 100.0)
			dists.append(ds)
	# smooth grade changes (vertical curves) and curvature (transitions)
	grades = _smooth(grades, 12)
	var curv_s := _smooth(curvs, 2)
	# integrate
	var pos := Vector3.ZERO
	var h := 0.0
	var s := 0.0
	var count := curvs.size()
	for i in count + 1:
		var dir := Vector3(cos(h), 0.0, sin(h))
		P.append(pos)
		D.append(dir)
		R.append(dir.cross(Vector3.UP))
		S.append(s)
		var j := mini(i, count - 1)
		K.append(curv_s[j])
		G.append(grades[j])
		if i == count:
			break
		var ds: float = dists[i]
		var dh: float = curvs[i] * ds
		var mid := Vector3(cos(h + dh * 0.5), 0.0, sin(h + dh * 0.5))
		pos += mid * ds
		pos.y += grades[i] * ds
		h += dh
		s += ds
	length = s
	drop = P[0].y - P[P.size() - 1].y
	min_y = P[P.size() - 1].y


## Centerline traced from a real course map (see tools/trace_course.py).
func _load_traced(path: String) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var pts: Array = data.points
	var grades: Array[float] = []
	for g in data.grade:
		grades.append(float(g) / 100.0)
	grades = _smooth(grades, 12)
	hairpins = int(data.get("hairpins", 0))
	# flat lead-in before the first traced point, along the initial heading
	var p0 := Vector3(pts[0][0], 0.0, pts[0][1])
	var p1 := Vector3(pts[1][0], 0.0, pts[1][1])
	var d0 := (p1 - p0).normalized()
	var raw: Array[Vector3] = []
	var lead := int(LEAD_IN / 2.0)
	for k in range(lead, 0, -1):
		raw.append(p0 - d0 * (k * 2.0))
	for p in pts:
		raw.append(Vector3(p[0], 0.0, p[1]))
	var n := raw.size()
	var y := 0.0
	var s := 0.0
	var heads: Array[float] = []
	for i in n:
		var a := raw[maxi(i - 1, 0)]
		var b := raw[mini(i + 1, n - 1)]
		heads.append(atan2(b.z - a.z, b.x - a.x))
	var curvs: Array[float] = []
	for i in n:
		var a := heads[maxi(i - 1, 0)]
		var b := heads[mini(i + 1, n - 1)]
		var ds := raw[maxi(i - 1, 0)].distance_to(raw[mini(i + 1, n - 1)])
		curvs.append(wrapf(b - a, -PI, PI) / maxf(ds, 0.1))
	curvs = _smooth(curvs, 2)
	for i in n:
		if i > 0:
			var ds := raw[i].distance_to(raw[i - 1])
			s += ds
			var gi := clampi(i - lead - 1, 0, grades.size() - 1)
			y += (grades[gi] if i > lead else -0.02) * ds
		var pos := Vector3(raw[i].x, y, raw[i].z)
		var dir := Vector3(cos(heads[i]), 0.0, sin(heads[i]))
		P.append(pos)
		D.append(dir)
		R.append(dir.cross(Vector3.UP))
		S.append(s)
		K.append(curvs[i])
		G.append(grades[clampi(i - lead - 1, 0, grades.size() - 1)] if i > lead else -0.02)
	length = s
	drop = P[0].y - P[n - 1].y
	min_y = P[n - 1].y


func _smooth(arr: Array[float], radius: int) -> Array[float]:
	var out: Array[float] = []
	var n := arr.size()
	for i in n:
		var sum := 0.0
		var cnt := 0
		for k in range(maxi(0, i - radius), mini(n, i + radius + 1)):
			sum += arr[k]
			cnt += 1
		out.append(sum / cnt)
	return out


func _compute_grass() -> void:
	# Grass verge width per side shrinks where another part of the road is near,
	# so stacked hairpins don't bury each other.
	var cell := 20.0
	var grid := {}
	for i in P.size():
		var key := Vector2i(floori(P[i].x / cell), floori(P[i].z / cell))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	var n := P.size()
	grass_l.resize(n)
	grass_r.resize(n)
	for i in n:
		var free_l := 40.0
		var free_r := 40.0
		var key := Vector2i(floori(P[i].x / cell), floori(P[i].z / cell))
		for gx in range(-2, 3):
			for gz in range(-2, 3):
				var k2 := key + Vector2i(gx, gz)
				if not grid.has(k2):
					continue
				for j in grid[k2]:
					if absi(j - i) < 30:
						continue
					var dv: Vector3 = P[j] - P[i]
					var dy := absf(dv.y)
					dv.y = 0.0
					var dist := dv.length()
					if dist > 40.0:
						continue
					if dist < rail * 2.0 + 1.0 and dy < 6.0:
						overlaps += 1
					if dv.dot(R[i]) > 0.0:
						free_r = minf(free_r, dist)
					else:
						free_l = minf(free_l, dist)
		# inner side of tight corners must not fold over itself
		var kmax := 0.0
		var ksign := 0.0
		for k in range(maxi(0, i - 6), mini(n, i + 7)):
			if absf(K[k]) > kmax:
				kmax = absf(K[k])
				ksign = signf(K[k])
		var inner_limit := 999.0
		if kmax > 0.0:
			inner_limit = 0.8 / kmax - rail
		var gl := clampf(free_l * 0.5 - rail, 0.6, 14.0)
		var gr := clampf(free_r * 0.5 - rail, 0.6, 14.0)
		if ksign < 0.0:
			gl = clampf(minf(gl, inner_limit), 0.4, 14.0)
		elif ksign > 0.0:
			gr = clampf(minf(gr, inner_limit), 0.4, 14.0)
		grass_l[i] = gl
		grass_r[i] = gr
	# smooth
	for pass_i in 3:
		for i in range(1, n - 1):
			grass_l[i] = minf(grass_l[i], (grass_l[i - 1] + grass_l[i] + grass_l[i + 1]) / 3.0)
			grass_r[i] = minf(grass_r[i], (grass_r[i - 1] + grass_r[i] + grass_r[i + 1]) / 3.0)


## Cross-section profile: [lateral, dy] pairs from left to right.
func _profile(i: int) -> Array:
	var gl := grass_l[i]
	var gr := grass_r[i]
	var e := hw + GUTTER_W
	return [
		[-(rail + gl), -gl * 0.3],
		[-rail, -0.03],
		[-e, -0.03],
		[-(hw + GUTTER_W * 0.5), -GUTTER_DEPTH],
		[-hw, 0.0],
		[hw, 0.0],
		[hw + GUTTER_W * 0.5, -GUTTER_DEPTH],
		[e, -0.03],
		[rail, -0.03],
		[rail + gr, -gr * 0.3],
	]


func profile_dy(lat: float) -> float:
	var a := absf(lat)
	if a <= hw:
		return 0.0
	if a <= hw + GUTTER_W * 0.5:
		return -GUTTER_DEPTH * (a - hw) / (GUTTER_W * 0.5)
	if a <= hw + GUTTER_W:
		var t := (a - hw - GUTTER_W * 0.5) / (GUTTER_W * 0.5)
		return lerpf(-GUTTER_DEPTH, -0.03, t)
	return -0.03


# ---------------------------------------------------------------- queries

## Nearest point on the centerline to a world position, searching near `hint`.
func project(pos: Vector3, hint: int) -> Dictionary:
	var n := P.size()
	var best := clampi(hint, 0, n - 1)
	var best_d := INF
	for i in range(maxi(0, hint - 14), mini(n, hint + 15)):
		var dx := pos.x - P[i].x
		var dz := pos.z - P[i].z
		var d := dx * dx + dz * dz
		if d < best_d:
			best_d = d
			best = i
	var i := best
	var local := pos - P[i]
	local.y = 0.0
	if local.dot(D[i]) < 0.0 and i > 0:
		i -= 1
	i = mini(i, n - 2)
	var seg := P[i + 1] - P[i]
	seg.y = 0.0
	var seg_len := maxf(seg.length(), 0.001)
	local = pos - P[i]
	local.y = 0.0
	var frac := clampf(local.dot(seg / seg_len), 0.0, seg_len) / seg_len
	var center := P[i].lerp(P[i + 1], frac)
	var right := R[i].lerp(R[i + 1], frac).normalized()
	var off := pos - center
	off.y = 0.0
	return {
		"i": i,
		"s": S[i] + frac * (S[i + 1] - S[i]),
		"lat": off.dot(right),
		"center": center,
		"right": right,
		"dir": D[i].lerp(D[i + 1], frac).normalized(),
	}


func surface_height(proj: Dictionary) -> float:
	return proj.center.y + profile_dy(proj.lat)


func height_at(pos: Vector3, hint: int) -> float:
	return surface_height(project(pos, hint))


func index_at_s(s: float) -> int:
	var lo := 0
	var hi := S.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if S[mid] <= s:
			lo = mid
		else:
			hi = mid
	return lo


## World position at distance s with lateral offset lat (on the surface).
func point_at(s: float, lat: float) -> Vector3:
	var i := mini(index_at_s(s), S.size() - 2)
	var frac := clampf((s - S[i]) / maxf(S[i + 1] - S[i], 0.001), 0.0, 1.0)
	var center := P[i].lerp(P[i + 1], frac)
	var right := R[i].lerp(R[i + 1], frac).normalized()
	return center + right * lat + Vector3.UP * profile_dy(lat)


func dir_at(s: float) -> Vector3:
	var i := mini(index_at_s(s), S.size() - 2)
	var frac := clampf((s - S[i]) / maxf(S[i + 1] - S[i], 0.001), 0.0, 1.0)
	return D[i].lerp(D[i + 1], frac).normalized()


func curvature_at(s: float) -> float:
	return K[index_at_s(s)]


## Ideal speed profile for AI drivers. mu = cornering grip, power = W/kg.
func speed_profile(mu: float, power: float) -> PackedFloat32Array:
	var n := P.size()
	var v := PackedFloat32Array()
	v.resize(n)
	for i in n:
		var k := 0.0
		for j in range(maxi(0, i - 3), mini(n, i + 4)):
			k = maxf(k, absf(K[j]))
		v[i] = 60.0 if k < 0.0001 else minf(60.0, sqrt(mu * 9.81 * 1.12 / k))
	v[0] = 0.0
	for i in range(1, n):
		var ds := S[i] - S[i - 1]
		var a := clampf(power / maxf(v[i - 1], 4.0), 0.0, 5.0) - 0.00045 * v[i - 1] * v[i - 1] - 9.81 * G[i]
		v[i] = minf(v[i], sqrt(maxf(0.0, v[i - 1] * v[i - 1] + 2.0 * a * ds)))
	for i in range(n - 2, -1, -1):
		var ds := S[i + 1] - S[i]
		var b := 8.0 + 9.81 * G[i]
		v[i] = minf(v[i], sqrt(v[i + 1] * v[i + 1] + 2.0 * b * ds))
	return v


# ---------------------------------------------------------------- meshes

func _mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _build_road_mesh() -> void:
	var asphalt := _mat(Color(0.16, 0.16, 0.17), 0.95)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	asphalt.albedo_texture = tex
	asphalt.albedo_color = Color(0.22, 0.22, 0.23)
	var concrete := _mat(Color(0.48, 0.48, 0.46))
	var gravel := _mat(Color(0.3, 0.27, 0.22))
	var grass := _mat(Color(0.12, 0.22, 0.1))
	# surface id per profile strip (strip k joins profile point k and k+1)
	var strip_mat := [2, 3, 1, 1, 0, 1, 1, 3, 2]
	var mats := [asphalt, concrete, gravel, grass]
	var tools := []
	for m in mats:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
	var n := P.size()
	var prev: Array = []
	for i in n:
		var prof := _profile(i)
		var row: Array = []
		for p in prof:
			row.append(P[i] + R[i] * p[0] + Vector3.UP * p[1])
		if i > 0:
			for k in strip_mat.size():
				var st: SurfaceTool = tools[strip_mat[k]]
				var v0: Vector2 = Vector2(0, S[i - 1] / 6.0)
				var v1: Vector2 = Vector2(0, S[i] / 6.0)
				var a: Vector3 = prev[k]
				var b: Vector3 = prev[k + 1]
				var c: Vector3 = row[k]
				var d: Vector3 = row[k + 1]
				var u0 := float(k) / 9.0
				var u1 := float(k + 1) / 9.0
				if k == 4:
					u0 = 0.0
					u1 = hw * 2.0 / 6.0
				# Godot front faces are clockwise when seen from the front
				st.set_uv(Vector2(u0, v0.y)); st.add_vertex(a)
				st.set_uv(Vector2(u0, v1.y)); st.add_vertex(c)
				st.set_uv(Vector2(u1, v0.y)); st.add_vertex(b)
				st.set_uv(Vector2(u1, v0.y)); st.add_vertex(b)
				st.set_uv(Vector2(u0, v1.y)); st.add_vertex(c)
				st.set_uv(Vector2(u1, v1.y)); st.add_vertex(d)
		prev = row
	var mesh := ArrayMesh.new()
	for k in tools.size():
		var st: SurfaceTool = tools[k]
		st.set_material(mats[k])
		st.generate_normals()
		st.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)


func _strip(st: SurfaceTool, lat_a: float, lat_b: float, lift: float, filter: Callable) -> void:
	for i in range(1, P.size()):
		if not filter.call(i):
			continue
		var a := P[i - 1] + R[i - 1] * lat_a + Vector3.UP * lift
		var b := P[i - 1] + R[i - 1] * lat_b + Vector3.UP * lift
		var c := P[i] + R[i] * lat_a + Vector3.UP * lift
		var d := P[i] + R[i] * lat_b + Vector3.UP * lift
		st.set_normal(Vector3.UP)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
		st.add_vertex(b); st.add_vertex(c); st.add_vertex(d)


func _build_markings() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var all := func(_i: int) -> bool: return true
	var dashed := func(i: int) -> bool: return fmod(S[i], 9.0) < 4.5
	_strip(st, -0.07, 0.07, 0.015, dashed)
	_strip(st, -hw + 0.12, -hw + 0.27, 0.015, all)
	_strip(st, hw - 0.27, hw - 0.12, 0.015, all)
	var m := _mat(Color(0.85, 0.85, 0.8), 0.7)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(m)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	add_child(mi)


func _build_guardrails() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for i in range(1, P.size()):
			var lat: float = side * rail
			var a := P[i - 1] + R[i - 1] * lat
			var b := P[i] + R[i] * lat
			var lo := Vector3.UP * 0.48
			var hi := Vector3.UP * 0.8
			var nrm: Vector3 = -R[i] * side
			st.set_normal(nrm)
			st.add_vertex(a + lo); st.add_vertex(b + lo); st.add_vertex(a + hi)
			st.add_vertex(b + lo); st.add_vertex(b + hi); st.add_vertex(a + hi)
	var rail_mat := _mat(Color(0.75, 0.76, 0.78), 0.35)
	rail_mat.metallic = 0.6
	rail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(rail_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	add_child(mi)
	# posts and reflectors
	var posts: Array[Transform3D] = []
	var reflectors: Array[Transform3D] = []
	var next_s := 0.0
	for i in P.size():
		if S[i] < next_s:
			continue
		next_s = S[i] + 4.0
		for side in [-1.0, 1.0]:
			var p: Vector3 = P[i] + R[i] * (side * (rail + 0.08))
			var basis := Basis.looking_at(D[i], Vector3.UP)
			posts.append(Transform3D(basis, p + Vector3.UP * 0.4))
			if int(S[i] / 4.0) % 3 == 0:
				reflectors.append(Transform3D(basis, P[i] + R[i] * (side * (rail - 0.03)) + Vector3.UP * 0.86))
	add_child(_multimesh(_box(Vector3(0.1, 0.8, 0.1)), posts, _mat(Color(0.6, 0.6, 0.62), 0.5)))
	var refl_mat := _mat(Color(1.0, 0.6, 0.1))
	refl_mat.emission_enabled = true
	refl_mat.emission = Color(1.0, 0.55, 0.1)
	refl_mat.emission_energy_multiplier = 1.6
	add_child(_multimesh(_box(Vector3(0.08, 0.08, 0.04)), reflectors, refl_mat))


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi


func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(course.get("id", "x"))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.6
	cone.height = 6.0
	cone.radial_segments = 6
	cone.rings = 1
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.22
	trunk.height = 1.6
	trunk.radial_segments = 5
	var tops: Array[Transform3D] = []
	var trunks: Array[Transform3D] = []
	for i in range(0, P.size(), 2):
		for side in [-1.0, 1.0]:
			var gw: float = grass_l[i] if side < 0.0 else grass_r[i]
			if gw < 3.0:
				continue
			for t in 2:
				if rng.randf() > 0.55:
					continue
				var off := rng.randf_range(1.8, gw)
				var lat: float = side * (rail + off)
				var p: Vector3 = P[i] + R[i] * lat + D[i] * rng.randf_range(-1.0, 1.0)
				p.y += -off * 0.3
				var sc := rng.randf_range(0.7, 1.5)
				var b := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.4), sc))
				tops.append(Transform3D(b, p + Vector3.UP * (1.2 + 3.0) * b.y.length()))
				trunks.append(Transform3D(b, p + Vector3.UP * 0.8 * b.y.length()))
	add_child(_multimesh(cone, tops, _mat(Color(0.06, 0.16, 0.08))))
	add_child(_multimesh(trunk, trunks, _mat(Color(0.2, 0.13, 0.08))))


func _build_start_finish() -> void:
	for data in [[start_s, "START", false], [finish_s, "FINISH", true]]:
		var s: float = data[0]
		var i := index_at_s(s)
		var center := point_at(s, 0.0)
		var dir := D[i]
		var right := R[i]
		var basis := Basis.looking_at(dir, Vector3.UP)
		# line across the road
		var line := MeshInstance3D.new()
		line.mesh = _box(Vector3(hw * 2.0, 0.02, 0.6 if data[2] else 0.35))
		line.transform = Transform3D(basis, center + Vector3.UP * 0.02)
		var lm := _mat(Color(0.95, 0.95, 0.95))
		if data[2]:
			var check := Image.create(8, 2, false, Image.FORMAT_RGB8)
			for x in 8:
				for y in 2:
					check.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color.BLACK)
			var it := ImageTexture.create_from_image(check)
			lm.albedo_texture = it
			lm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		line.material_override = lm
		add_child(line)
		# gantry
		var pole_mat := _mat(Color(0.35, 0.35, 0.38), 0.5)
		for side in [-1.0, 1.0]:
			var pole := MeshInstance3D.new()
			pole.mesh = _box(Vector3(0.25, 5.0, 0.25))
			pole.material_override = pole_mat
			pole.position = center + right * (side * (rail + 0.4)) + Vector3.UP * 2.5
			add_child(pole)
		var banner := MeshInstance3D.new()
		banner.mesh = _box(Vector3(rail * 2.0 + 1.0, 0.9, 0.15))
		var bm := _mat(Color(0.7, 0.05, 0.05) if data[2] else Color(0.1, 0.25, 0.6))
		bm.emission_enabled = true
		bm.emission = bm.albedo_color
		bm.emission_energy_multiplier = 0.6
		banner.material_override = bm
		banner.transform = Transform3D(basis, center + Vector3.UP * 4.8)
		add_child(banner)
		for face in [1.0, -1.0]:
			var label := Label3D.new()
			label.text = data[1]
			label.font_size = 96
			label.pixel_size = 0.006
			label.outline_size = 0
			label.modulate = Color(1, 1, 1)
			label.transform = Transform3D(basis.rotated(Vector3.UP, PI if face < 0.0 else 0.0), center + Vector3.UP * 4.8 - dir * 0.1 * face)
			add_child(label)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.85, 0.6)
		lamp.light_energy = 2.0
		lamp.omni_range = 22.0
		lamp.position = center + Vector3.UP * 5.5
		add_child(lamp)


func _build_ground() -> void:
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	plane.mesh = pm
	plane.material_override = _mat(Color(0.05, 0.09, 0.05))
	var c := Vector3.ZERO
	for p in P:
		c += p
	c /= P.size()
	plane.position = Vector3(c.x, min_y - 28.0, c.z)
	add_child(plane)
