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
var walls := {}                # Vector2i(i, side) -> true where a retaining wall stands
const RUN_OFF := 260.0         # extra road past the finish so you can slow down


func build(c: Dictionary) -> void:
	course = c
	hw = c.get("width", 6.6) * 0.5
	rail = hw + GUTTER_W + SHOULDER
	build_centerline(c)
	_compute_grass()
	finish_s = length - RUN_OFF - 40.0
	if traced:
		# the road gets a short verge that dives into the terrain mesh
		for i in P.size():
			grass_l[i] = 1.4
			grass_r[i] = 1.4
	_build_road_mesh()
	_build_markings()
	_build_guardrails()
	_build_start_finish()
	if traced:
		_build_terrain()
		Scenery.new().build(self)
	else:
		_build_roadside()
		_build_trees()
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
	var all_segs: Array = [["S", LEAD_IN, -2.0]] + segs + [["S", 60, -2.0], ["S", RUN_OFF, -2.0]]
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
## Points are [x, y, z] with heights already integrated, lead-in included.
var traced := false
var terrain_info: Dictionary = {}
var tree_data: Array = []


func _load_traced(path: String) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	traced = true
	terrain_info = data.get("terrain", {})
	tree_data = data.get("trees", [])
	far_info = data.get("far_terrain", {})
	lake_info = data.get("lake", {}) if data.get("lake") != null else {}
	towns_data = data.get("towns", [])
	features = data.get("features", {})
	sign_text = data.get("sign", [])
	style = data.get("style", {})
	for tn in data.get("tunnels", []):
		tunnels.append([int(tn[0]), int(tn[1])])
	var rails: Array = data.get("rails", [])
	if rails.size() == 2:
		rail_l = rails[0]
		rail_r = rails[1]
	for b in features.get("bridges", []):
		for k in range(int(b[0]) - 2, int(b[1]) + 3):
			bridge_idx[k] = true
	hairpins = int(data.get("hairpins", 0))
	var pts: Array = data.points
	var raw: Array[Vector3] = []
	for p in pts:
		raw.append(Vector3(p[0], p[1], p[2]))
	# run-off road past the real end: carry on along the last heading, gently downhill
	var m := raw.size()
	var last_dir := Vector3(raw[m - 1].x - raw[m - 6].x, 0, raw[m - 1].z - raw[m - 6].z).normalized()
	var step := 2.0
	for k in range(1, int(RUN_OFF / step) + 1):
		raw.append(raw[m - 1] + last_dir * step * k + Vector3.DOWN * 0.02 * step * k)
	var n := raw.size()
	var heads: Array[float] = []
	for i in n:
		var a := raw[maxi(i - 1, 0)]
		var b := raw[mini(i + 1, n - 1)]
		heads.append(atan2(b.z - a.z, b.x - a.x))
	var curvs: Array[float] = []
	for i in n:
		var a := heads[maxi(i - 1, 0)]
		var b := heads[mini(i + 1, n - 1)]
		var ds := Vector2(raw[maxi(i - 1, 0)].x, raw[maxi(i - 1, 0)].z).distance_to(Vector2(raw[mini(i + 1, n - 1)].x, raw[mini(i + 1, n - 1)].z))
		curvs.append(wrapf(b - a, -PI, PI) / maxf(ds, 0.1))
	curvs = _smooth(curvs, 2)
	var s := 0.0
	for i in n:
		if i > 0:
			s += Vector2(raw[i].x, raw[i].z).distance_to(Vector2(raw[i - 1].x, raw[i - 1].z))
		var dir := Vector3(cos(heads[i]), 0.0, sin(heads[i]))
		P.append(raw[i])
		D.append(dir)
		R.append(dir.cross(Vector3.UP))
		S.append(s)
		K.append(curvs[i])
		G.append(0.0)
	# grade from neighbouring samples (recomputed cleanly now that S is complete)
	for i in n:
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, n - 1)
		G[i] = (P[i1].y - P[i0].y) / maxf(S[i1] - S[i0], 0.5)
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
					if dist < hw * 2.0 + 0.5 and dy < 4.0:   # road surfaces would overlap
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
		[-(rail + gl), -gl * (0.7 if traced else 0.3)],
		[-rail, -0.03],
		[-e, -0.03],
		[-(hw + GUTTER_W * 0.5), -GUTTER_DEPTH],
		[-hw, 0.0],
		[hw, 0.0],
		[hw + GUTTER_W * 0.5, -GUTTER_DEPTH],
		[e, -0.03],
		[rail, -0.03],
		[rail + gr, -gr * (0.7 if traced else 0.3)],
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
	# real tarmac: aggregate, cracks, sealed seams and repair patches (6 m tile)
	# scanned tarmac, slightly damp so headlights and lamps streak across it
	var asphalt := Mats.pbr("asphalt", 2.0, Color(0.55, 0.55, 0.57), 0.7)
	asphalt.metallic_specular = 0.7
	var concrete := Mats.pbr("concrete", 2.0, Color(0.8, 0.8, 0.78))
	var gravel := _mat(Color(0.22, 0.2, 0.17))
	# grass bank beyond the verge, with the grass/leaf-litter detail texture
	var grass := Mats.pbr("grass", 3.0)
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
	var all := func(_i: int) -> bool: return true
	var yellow := SurfaceTool.new()
	yellow.begin(Mesh.PRIMITIVE_TRIANGLES)
	# centre line as on the real road: orange no-passing line (default),
	# white dashed line, or a white dashed lane divider on one-way roads
	var cl: String = style.get("center_line", "orange")
	var dashed := func(i: int) -> bool: return fmod(S[i], 10.0) < 5.0
	if cl == "orange":
		_strip(yellow, -0.08, 0.08, 0.012, all)
	var ym := _mat(Color(0.95, 0.5, 0.08), 0.5)   # orange: Japanese no-passing centre line
	ym.cull_mode = BaseMaterial3D.CULL_DISABLED
	yellow.set_material(ym)
	var white := SurfaceTool.new()
	white.begin(Mesh.PRIMITIVE_TRIANGLES)
	if cl == "white_dashed":
		_strip(white, -0.07, 0.07, 0.012, dashed)
	_strip(white, -hw + 0.12, -hw + 0.26, 0.012, all)
	_strip(white, hw - 0.26, hw - 0.12, 0.012, all)
	var wm := _mat(Color(0.88, 0.88, 0.85), 0.5)
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	white.set_material(wm)
	for st in [yellow, white]:
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		add_child(mi)


func _build_guardrails() -> void:
	# Japanese W-beam: corrugated steel strip on round posts, painted white
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prof := [[0.0, 0.42], [0.06, 0.49], [0.02, 0.56], [0.06, 0.63], [0.0, 0.70], [-0.02, 0.70], [-0.02, 0.42]]
	for side: float in [-1.0, 1.0]:
		for i in range(1, P.size()):
			if not (has_rail(i, side) and has_rail(i - 1, side)):
				continue
			for k in prof.size():
				var k2 := (k + 1) % prof.size()
				var lat_a: float = side * (rail - prof[k][0])
				var lat_b: float = side * (rail - prof[k2][0])
				var a0: Vector3 = P[i - 1] + R[i - 1] * lat_a + Vector3.UP * prof[k][1]
				var a1: Vector3 = P[i - 1] + R[i - 1] * lat_b + Vector3.UP * prof[k2][1]
				var b0: Vector3 = P[i] + R[i] * lat_a + Vector3.UP * prof[k][1]
				var b1: Vector3 = P[i] + R[i] * lat_b + Vector3.UP * prof[k2][1]
				var e := Vector2(prof[k2][0] - prof[k][0], prof[k2][1] - prof[k][1])
				var nl := Vector2(e.y, -e.x).normalized()
				var nrm: Vector3 = (-R[i] * side * nl.x + Vector3.UP * nl.y).normalized()
				st.set_normal(nrm)
				st.add_vertex(a0); st.add_vertex(b0); st.add_vertex(a1)
				st.add_vertex(a1); st.add_vertex(b0); st.add_vertex(b1)
	var rail_mat := _mat(Color(0.82, 0.83, 0.84), 0.3)
	rail_mat.metallic = 0.5
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
		for side: float in [-1.0, 1.0]:
			if not has_rail(i, side):
				continue
			var p: Vector3 = P[i] + R[i] * (side * (rail + 0.08))
			var basis := Basis.looking_at(D[i], Vector3.UP)
			posts.append(Transform3D(basis, p + Vector3.UP * 0.2))
			if int(S[i] / 4.0) % 3 == 0:
				reflectors.append(Transform3D(basis, P[i] + R[i] * (side * (rail - 0.07)) + Vector3.UP * 0.56))
	var post := CylinderMesh.new()
	post.top_radius = 0.07
	post.bottom_radius = 0.07
	post.height = 1.1
	post.radial_segments = 6
	add_child(_multimesh(post, posts, _mat(Color(0.75, 0.75, 0.76), 0.4)))
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
		if traced:
			var paint := Label3D.new()
			paint.text = "GOAL" if data[2] else "START"
			paint.font_size = 160
			paint.pixel_size = 0.012
			paint.modulate = Color(0.9, 0.9, 0.88)
			paint.outline_size = 0
			paint.double_sided = false
			var lie := Basis.looking_at(Vector3.DOWN, dir)
			paint.transform = Transform3D(lie, center + Vector3.UP * 0.02 + dir * 3.0)
			add_child(paint)
			continue
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


# ---------------------------------------------------------------- terrain & roadside

var terrain_h := PackedFloat32Array()
var far_info: Dictionary = {}
var far_h := PackedFloat32Array()
var lake_info: Dictionary = {}
var towns_data: Array = []
var features: Dictionary = {}
var sign_text: Array = []
var style: Dictionary = {}
var tunnels: Array = []


func in_tunnel(i: int) -> bool:
	for tn in tunnels:
		if i >= tn[0] - 1 and i <= tn[1] + 1:
			return true
	return false
var rail_l := ""
var rail_r := ""
var bridge_idx := {}


## Whether a guardrail stands at sample i on this side (real data on traced
## courses; everywhere on the placeholder courses).
func has_rail(i: int, side: float) -> bool:
	if bridge_idx.has(i) or in_tunnel(i):
		return false
	var flags := rail_l if side < 0.0 else rail_r
	if flags.is_empty():
		return true
	return flags.unicode_at(clampi(i, 0, flags.length() - 1)) == 49
var _road_grid := {}
const ROAD_CELL := 16.0


## Index of the nearest centerline sample anywhere on the course.
func nearest_index(p: Vector3) -> int:
	dist_to_road(p)
	var key := Vector2i(floori(p.x / ROAD_CELL), floori(p.z / ROAD_CELL))
	var best := INF
	var bi := 0
	for gx in range(-1, 2):
		for gz in range(-1, 2):
			var k2 := key + Vector2i(gx, gz)
			if not _road_grid.has(k2):
				continue
			for i in _road_grid[k2]:
				var d := Vector2(P[i].x - p.x, P[i].z - p.z).length_squared()
				if d < best:
					best = d
					bi = i
	return bi


## Horizontal distance from a point to the nearest centerline sample anywhere
## on the course (used to keep scenery off every leg of the road).
func dist_to_road(p: Vector3) -> float:
	if _road_grid.is_empty():
		for i in P.size():
			var k := Vector2i(floori(P[i].x / ROAD_CELL), floori(P[i].z / ROAD_CELL))
			if not _road_grid.has(k):
				_road_grid[k] = PackedInt32Array()
			_road_grid[k].append(i)
	var key := Vector2i(floori(p.x / ROAD_CELL), floori(p.z / ROAD_CELL))
	var best := INF
	for gx in range(-1, 2):
		for gz in range(-1, 2):
			var k2 := key + Vector2i(gx, gz)
			if not _road_grid.has(k2):
				continue
			for i in _road_grid[k2]:
				var dx := P[i].x - p.x
				var dz := P[i].z - p.z
				best = minf(best, dx * dx + dz * dz)
	return sqrt(best)


## Bilinear terrain height (traced courses); falls back to the road height.
func terrain_height(x: float, z: float) -> float:
	if terrain_h.is_empty():
		return min_y
	var nx: int = terrain_info.nx
	var nz: int = terrain_info.nz
	var cell: float = terrain_info.cell
	var fx := clampf((x - terrain_info.origin[0]) / cell, 0.0, nx - 1.001)
	var fz := clampf((z - terrain_info.origin[1]) / cell, 0.0, nz - 1.001)
	var i := int(fx)
	var j := int(fz)
	var a := fx - i
	var b := fz - j
	var h00 := terrain_h[j * nx + i]
	var h10 := terrain_h[j * nx + i + 1]
	var h01 := terrain_h[(j + 1) * nx + i]
	var h11 := terrain_h[(j + 1) * nx + i + 1]
	# same triangle split as the rendered mesh (diagonal from (i+1,j) to
	# (i,j+1)), so walls, slope frames and trees sit exactly on what is drawn
	if a + b <= 1.0:
		return h00 + (h10 - h00) * a + (h01 - h00) * b
	return h11 + (h01 - h11) * (1.0 - a) + (h10 - h11) * (1.0 - b)


func _build_terrain() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	for pair in [["forest_diff", "forest", "diff"], ["forest_nor", "forest", "nor"], ["forest_rough", "forest", "rough"],
			["rock_diff", "rock", "diff"], ["rock_nor", "rock", "nor"], ["rock_rough", "rock", "rough"]]:
		mat.set_shader_parameter(pair[0], Mats.tex(pair[1], pair[2]))
	mat.set_shader_parameter("canopy_tex", load("res://assets/textures/canopy.png"))
	if terrain_info.has("aerial"):
		var tex: Texture2D = load("res://tracks/" + terrain_info.aerial)
		if tex:
			mat.set_shader_parameter("aerial", tex)
			mat.set_shader_parameter("aerial_origin", Vector2(terrain_info.origin[0], terrain_info.origin[1]))
			mat.set_shader_parameter("aerial_size", Vector2(terrain_info.aerial_size[0], terrain_info.aerial_size[1]))
			mat.set_shader_parameter("use_aerial", 1.0)
	terrain_h = _load_grid(terrain_info)
	_carve_corridor()
	_corridor_mask(mat)
	_terrain_mat = mat
	_grid_mesh(terrain_info, terrain_h, mat, Rect2())
	if not far_info.is_empty():
		# real mountains and valleys out to the horizon, with a hole where the
		# detailed terrain around the road sits
		far_h = _load_grid(far_info)
		var near := Rect2(terrain_info.origin[0], terrain_info.origin[1],
			(terrain_info.nx - 1) * terrain_info.cell, (terrain_info.nz - 1) * terrain_info.cell)
		_grid_mesh(far_info, far_h, mat, near.grow(-far_info.cell))
	if not lake_info.is_empty():
		var water := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(lake_info.x1 - lake_info.x0, lake_info.z1 - lake_info.z0)
		water.mesh = pm
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.02, 0.05, 0.12)
		wm.roughness = 0.03
		wm.metallic = 0.6
		wm.emission_enabled = true
		wm.emission = Color(0.02, 0.04, 0.1)
		water.material_override = wm
		water.position = Vector3((lake_info.x0 + lake_info.x1) * 0.5, lake_info.y, (lake_info.z0 + lake_info.z1) * 0.5)
		add_child(water)


## Keep the hillside out of the road corridor: every terrain vertex within a
## few metres of the road drops to just below the road, so the mountain starts
## behind the wall instead of bulging through it. Tunnels keep their mountain.
func _carve_corridor() -> void:
	var nx: int = terrain_info.nx
	var nz: int = terrain_info.nz
	var cell: float = terrain_info.cell
	var ox: float = terrain_info.origin[0]
	var oz: float = terrain_info.origin[1]
	var reach := rail + 2.6
	var rc := int(ceil(reach / cell)) + 1
	for i in range(0, P.size()):
		if in_tunnel(i):
			continue
		var p := P[i]
		var ci := int(round((p.x - ox) / cell))
		var cj := int(round((p.z - oz) / cell))
		var r2 := Vector2(R[i].x, R[i].z)
		var d2 := Vector2(D[i].x, D[i].z)
		for dj in range(-rc, rc + 1):
			var gj := cj + dj
			if gj < 0 or gj >= nz:
				continue
			for di in range(-rc, rc + 1):
				var gi := ci + di
				if gi < 0 or gi >= nx:
					continue
				var v := Vector2(ox + gi * cell - p.x, oz + gj * cell - p.z)
				if absf(v.dot(d2)) > cell * 0.75 or absf(v.dot(r2)) > reach:
					continue
				var k := gj * nx + gi
				terrain_h[k] = minf(terrain_h[k], p.y - 0.35)


## Exact road corridor for the terrain shader: a height map (1 m pixels) that
## holds the road surface height across the road, gutters and verge up to the
## wall line. Terrain above that height inside the corridor is not drawn, so
## the mountain can never show on the road or in front of a wall. Tunnels are
## left out so the mountain over them stays whole.
func _corridor_mask(mat: ShaderMaterial) -> void:
	var ox: float = terrain_info.origin[0]
	var oz: float = terrain_info.origin[1]
	var cell: float = terrain_info.cell
	var w := int((terrain_info.nx - 1) * cell)
	var h := int((terrain_info.nz - 1) * cell)
	var data := PackedFloat32Array()
	data.resize(w * h)
	data.fill(1.0e6)
	var half := rail + 0.88      # right up to the wall line
	for i in range(0, P.size() - 1):
		if in_tunnel(i) or in_tunnel(i + 1):
			continue
		var seg := S[i + 1] - S[i]
		var steps := maxi(1, int(ceil(seg / 0.4)))
		for k in steps + 1:
			var f := float(k) / steps
			var c := P[i].lerp(P[i + 1], f)
			var r := R[i].lerp(R[i + 1], f).normalized()
			var l := -half
			while l <= half:
				var q := c + r * l
				var px := int(q.x - ox)
				var pz := int(q.z - oz)
				if px >= 0 and pz >= 0 and px < w and pz < h:
					var idx := pz * w + px
					var top := c.y - 0.12   # nothing of the hillside above the road edge or ditch
					data[idx] = top if data[idx] > 1.0e5 else maxf(data[idx], top)
				l += 0.4
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RF, data.to_byte_array())
	mat.set_shader_parameter("corridor", ImageTexture.create_from_image(img))
	mat.set_shader_parameter("corridor_origin", Vector2(ox, oz))
	mat.set_shader_parameter("corridor_size", Vector2(w, h))
	mat.set_shader_parameter("use_corridor", 1.0)


var _terrain_nodes: Array[Node] = []
var _terrain_mat: Material


## Lower the hillside under walls and slope frames: each cap (x, z, max height)
## pulls down the four terrain vertices of the cell it falls in, so the drawn
## surface at that spot can't rise above it. Rebuilds the near terrain mesh.
func cap_terrain(caps: PackedVector3Array) -> void:
	if terrain_h.is_empty() or caps.is_empty():
		return
	var nx: int = terrain_info.nx
	var nz: int = terrain_info.nz
	var cell: float = terrain_info.cell
	var ox: float = terrain_info.origin[0]
	var oz: float = terrain_info.origin[1]
	for c in caps:
		var i := int(floor((c.x - ox) / cell))
		var j := int(floor((c.z - oz) / cell))
		for dj in 2:
			for di in 2:
				var gi := i + di
				var gj := j + dj
				if gi < 0 or gj < 0 or gi >= nx or gj >= nz:
					continue
				var k := gj * nx + gi
				terrain_h[k] = minf(terrain_h[k], c.y)
	for n in _terrain_nodes:
		n.queue_free()
	_terrain_nodes.clear()
	_grid_mesh(terrain_info, terrain_h, _terrain_mat, Rect2())


func _load_grid(info: Dictionary) -> PackedFloat32Array:
	var f := FileAccess.open("res://tracks/" + info.file, FileAccess.READ)
	return f.get_buffer(int(info.nx) * int(info.nz) * 4).to_float32_array()


## Height of the coarse real-world terrain (towns, horizon).
func far_height(x: float, z: float) -> float:
	if far_h.is_empty():
		return min_y - 260.0
	var cell: float = far_info.cell
	var i := clampi(int((x - far_info.origin[0]) / cell), 0, int(far_info.nx) - 1)
	var j := clampi(int((z - far_info.origin[1]) / cell), 0, int(far_info.nz) - 1)
	return far_h[j * int(far_info.nx) + i]


func _grid_mesh(info: Dictionary, h: PackedFloat32Array, mat: Material, hole: Rect2) -> void:
	var nx: int = info.nx
	var nz: int = info.nz
	var cell: float = info.cell
	var ox: float = info.origin[0]
	var oz: float = info.origin[1]
	var tile := 64
	for tz in range(0, nz - 1, tile):
		for tx in range(0, nx - 1, tile):
			var w := mini(tile, nx - 1 - tx) + 1
			var d := mini(tile, nz - 1 - tz) + 1
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			verts.resize(w * d)
			norms.resize(w * d)
			for j in d:
				var gj := tz + j
				for i in w:
					var gi := tx + i
					var k := gj * nx + gi
					verts[j * w + i] = Vector3(ox + gi * cell, h[k], oz + gj * cell)
					var hl := h[gj * nx + maxi(gi - 1, 0)]
					var hr := h[gj * nx + mini(gi + 1, nx - 1)]
					var hd := h[maxi(gj - 1, 0) * nx + gi]
					var hu := h[mini(gj + 1, nz - 1) * nx + gi]
					norms[j * w + i] = Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
			var idx := PackedInt32Array()
			for j in d - 1:
				for i in w - 1:
					if hole.has_area() and hole.has_point(Vector2(ox + (tx + i + 0.5) * cell, oz + (tz + j + 0.5) * cell)):
						continue
					var a := j * w + i
					idx.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
			if idx.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			add_child(mi)
			if not hole.has_area():
				_terrain_nodes.append(mi)


func _cone(st: SurfaceTool, base: Vector3, r: float, height: float, col: Color, sides := 7) -> void:
	var tip := base + Vector3.UP * height
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := base + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := base + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var am := (a0 + a1) * 0.5
		var n := Vector3(cos(am), r / height, sin(am)).normalized()
		st.set_color(col.darkened(0.25))
		st.set_normal(n)
		st.add_vertex(p0)
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.add_vertex(tip)
		st.set_color(col.darkened(0.25))
		st.set_normal(n)
		st.add_vertex(p1)


func _cedar_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cone(st, Vector3(0, 0, 0), 0.28, 3.5, Color(0.2, 0.13, 0.08), 5)
	_cone(st, Vector3(0, 2.0, 0), 2.3, 6.0, Color(0.07, 0.15, 0.08))
	_cone(st, Vector3(0, 4.8, 0), 1.8, 5.0, Color(0.08, 0.17, 0.09))
	_cone(st, Vector3(0, 7.6, 0), 1.2, 4.2, Color(0.09, 0.19, 0.1))
	return st.commit()


func _build_forest() -> void:
	var mesh := _cedar_mesh()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var chunk := 160.0
	var buckets := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in range(0, tree_data.size(), 4):
		var p := Vector3(tree_data[k], tree_data[k + 1] - 0.3, tree_data[k + 2])
		var sc: float = tree_data[k + 3] * 1.25
		var key := Vector2i(floori(p.x / chunk), floori(p.z / chunk))
		if not buckets.has(key):
			buckets[key] = []
		var b := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.25), sc))
		buckets[key].append(Transform3D(b, p))
	for key in buckets:
		var xf: Array[Transform3D] = []
		xf.assign(buckets[key])
		var mmi := _multimesh(mesh, xf, mat)
		mmi.visibility_range_end = 520.0
		add_child(mmi)


func _chevron_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.95, 0.75, 0.05))
	for y in 64:
		for x in 64:
			var dx := absf(y - 32.0)
			var u := x - dx * 0.8
			if fmod(u + 200.0, 32.0) < 13.0 and x > 4 and x < 60:
				img.set_pixel(x, y, Color(0.05, 0.05, 0.05))
	return ImageTexture.create_from_image(img)


func _build_roadside() -> void:
	# chevron boards on the outside of every tight corner, and sodium lamps at some hairpins
	var tex := _chevron_texture()
	var board_mat := _mat(Color.WHITE, 0.6)
	board_mat.albedo_texture = tex
	board_mat.emission_enabled = true
	board_mat.emission_texture = tex
	board_mat.emission = Color(1, 1, 1)
	board_mat.emission_energy_multiplier = 0.15
	var pole_mat := _mat(Color(0.6, 0.6, 0.62), 0.4)
	var lamp_glass := _mat(Color(1.0, 0.7, 0.35))
	lamp_glass.emission_enabled = true
	lamp_glass.emission = Color(1.0, 0.62, 0.25)
	lamp_glass.emission_energy_multiplier = 4.0
	var i := 0
	var corner := 0
	var n := P.size()
	while i < n:
		if absf(K[i]) < 1.0 / 28.0:
			i += 1
			continue
		var j := i
		while j < n and absf(K[j]) >= 1.0 / 28.0:
			j += 1
		var side := -signf(K[i])      # outside of the corner
		var count := clampi((j - i) / 6, 1, 4)
		for c in count:
			var m := i + int((j - i) * (c + 0.5) / count)
			var pos := P[m] + R[m] * side * (rail + 0.6)
			var face := (-R[m] * side + D[m] * 0.6).normalized()
			var board := MeshInstance3D.new()
			board.mesh = _box(Vector3(0.6, 0.6, 0.04))
			board.material_override = board_mat
			var basis := Basis.looking_at(face, Vector3.UP)
			if side < 0.0:
				basis = basis.scaled(Vector3(-1, 1, 1))
			board.transform = Transform3D(basis, pos + Vector3.UP * 1.25)
			add_child(board)
			var pole := MeshInstance3D.new()
			pole.mesh = _box(Vector3(0.06, 1.0, 0.06))
			pole.material_override = pole_mat
			pole.position = pos + Vector3.UP * 0.5
			add_child(pole)
		if corner % 3 == 1 and (j - i) > 8:
			var m := (i + j) / 2
			var base := P[m] + R[m] * side * (rail + 1.2)
			var post := MeshInstance3D.new()
			post.mesh = _box(Vector3(0.14, 7.0, 0.14))
			post.material_override = pole_mat
			post.position = base + Vector3.UP * 3.5
			add_child(post)
			var arm_dir := -R[m] * side
			var arm := MeshInstance3D.new()
			arm.mesh = _box(Vector3(0.08, 0.08, 2.0))
			arm.material_override = pole_mat
			arm.transform = Transform3D(Basis.looking_at(arm_dir, Vector3.UP), base + Vector3.UP * 7.0 + arm_dir * 1.0)
			add_child(arm)
			var head := MeshInstance3D.new()
			head.mesh = _box(Vector3(0.35, 0.12, 0.6))
			head.material_override = lamp_glass
			head.transform = Transform3D(Basis.looking_at(arm_dir, Vector3.UP), base + Vector3.UP * 6.9 + arm_dir * 1.9)
			add_child(head)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.65, 0.3)
			l.light_energy = 2.2
			l.omni_range = 24.0
			l.omni_attenuation = 1.4
			l.position = base + Vector3.UP * 6.4 + arm_dir * 2.0
			add_child(l)
		corner += 1
		i = j
