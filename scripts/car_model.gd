class_name CarModel
extends Node3D
## Procedural cars built as ONE smooth lofted body (cross-sections along the
## car), in the spirit of late-90s anime CG: glossy paint, dark glass, glowing
## lamps. Local forward is -Z, up is +Y.
##   "hatch" : 80s two-tone 3-door hatchback with pop-up headlights (player)
##   "coupe" : low rotary-style coupe with pop-ups
##   "sedan" : boxy turbo coupe with fixed headlights and a wing

const WHEEL_R := 0.3

## Station table: [z, y_bottom, y_belt, y_top, half_width, top_half_width]
const SHAPES := {
	"hatch": {
		"stations": [
			[-2.13, 0.32, 0.60, 0.62, 0.74, 0.66], [-2.08, 0.27, 0.66, 0.69, 0.80, 0.74],
			[-1.90, 0.24, 0.70, 0.74, 0.82, 0.77], [-1.50, 0.24, 0.75, 0.79, 0.83, 0.78],
			[-1.10, 0.24, 0.79, 0.84, 0.83, 0.78], [-0.72, 0.24, 0.82, 0.88, 0.83, 0.76],
			[-0.62, 0.24, 0.83, 0.94, 0.83, 0.72], [-0.02, 0.24, 0.85, 1.27, 0.83, 0.64],
			[0.40, 0.24, 0.86, 1.30, 0.83, 0.63], [1.00, 0.24, 0.87, 1.28, 0.83, 0.62],
			[1.50, 0.25, 0.88, 1.12, 0.82, 0.62], [1.95, 0.27, 0.89, 0.95, 0.80, 0.66],
			[2.10, 0.30, 0.86, 0.90, 0.78, 0.70], [2.14, 0.34, 0.80, 0.82, 0.74, 0.66]],
		"glass": [-0.62, 1.95], "roof": [-0.02, 1.0], "side": [-0.55, 1.72],
		"b_pillar": [0.33, 0.43], "wheel_z": 1.2, "panda": 0.56, "popups": true,
		"popup_z": -1.82, "spoiler": true,
	},
	"coupe": {
		"stations": [
			[-2.20, 0.30, 0.55, 0.57, 0.80, 0.70], [-2.10, 0.26, 0.62, 0.66, 0.86, 0.80],
			[-1.80, 0.24, 0.68, 0.72, 0.88, 0.82], [-1.20, 0.24, 0.74, 0.78, 0.88, 0.80],
			[-0.62, 0.24, 0.78, 0.82, 0.88, 0.76], [-0.55, 0.24, 0.79, 0.86, 0.88, 0.72],
			[0.15, 0.24, 0.80, 1.20, 0.88, 0.62], [0.80, 0.24, 0.82, 1.21, 0.88, 0.62],
			[1.55, 0.25, 0.84, 0.95, 0.88, 0.70], [1.90, 0.27, 0.86, 0.88, 0.87, 0.78],
			[2.15, 0.30, 0.82, 0.84, 0.84, 0.76], [2.22, 0.36, 0.70, 0.72, 0.78, 0.70]],
		"glass": [-0.55, 1.55], "roof": [0.15, 0.8], "side": [-0.5, 1.4],
		"b_pillar": [9.0, 9.0], "wheel_z": 1.22, "panda": 0.3, "popups": true,
		"popup_z": -1.9, "spoiler": false,
	},
	"sedan": {
		"stations": [
			[-2.30, 0.30, 0.62, 0.64, 0.80, 0.74], [-2.24, 0.26, 0.72, 0.75, 0.86, 0.82],
			[-1.80, 0.25, 0.78, 0.82, 0.88, 0.84], [-0.80, 0.25, 0.84, 0.88, 0.88, 0.82],
			[-0.72, 0.25, 0.85, 0.92, 0.88, 0.76], [-0.05, 0.25, 0.87, 1.32, 0.88, 0.70],
			[0.95, 0.25, 0.88, 1.32, 0.88, 0.70], [1.60, 0.26, 0.90, 0.96, 0.88, 0.80],
			[2.20, 0.28, 0.90, 0.94, 0.88, 0.84], [2.32, 0.34, 0.84, 0.86, 0.86, 0.80]],
		"glass": [-0.72, 1.6], "roof": [-0.05, 0.95], "side": [-0.65, 1.5],
		"b_pillar": [0.42, 0.52], "wheel_z": 1.33, "panda": 0.3, "popups": false,
		"popup_z": 0.0, "spoiler": false,
	},
}

var template := "hatch"
var spec: Dictionary = {}
var panda_split := true
var body_color := Color(0.95, 0.95, 0.93)
var lower_color := Color(0.05, 0.05, 0.06)

var wheels: Array[Node3D] = []      # steering pivots (FL, FR, RL, RR)
var wheel_spin: Array[Node3D] = []
var wheel_base_y: Array[float] = []
var popups: Array[Node3D] = []
var headlights: Array[SpotLight3D] = []
var head_glow: Array[Node3D] = []
var tail_glow: Array[MeshInstance3D] = []
var tail_mat: StandardMaterial3D
var lens_mat: StandardMaterial3D
var body: Node3D

var _shape: Dictionary
var _popup_angle := 0.0
var _popup_hinged := false        # Blender models: exported open, close by rotating about the rear hinge
var _popup_close: Array[float] = []
var _lights_target := true
var _spin := 0.0
var _braking := false

static var _flare_tex: Texture2D
static var _shadow_tex: Texture2D


## Build any car from the garage (Cars.ROSTER) by id.
static func for_car(id: String, override_paint := Color(-1, 0, 0)) -> CarModel:
	var c: Dictionary = Cars.get_car(id)
	var glb := "res://cars/%s.glb" % c.get("model", id)
	if ResourceLoader.exists(glb):
		var gm := CarModel.new()
		gm.body_color = c.paint if override_paint.r < 0.0 else override_paint
		gm.lower_color = c.lower
		gm._build_glb(load(glb) as PackedScene)
		gm.scale = Vector3.ONE * 0.92
		return gm
	var m := CarModel.new()
	m.template = "car"
	m.spec = c.body
	m.panda_split = c.get("panda", false)
	m.body_color = c.paint if override_paint.r < 0.0 else override_paint
	m.lower_color = c.lower
	m._build()
	m.scale = Vector3.ONE * 0.92
	return m


static func create(tmpl: String, color: Color, lower := Color(0.05, 0.05, 0.06)) -> CarModel:
	var m := CarModel.new()
	m.template = tmpl
	m.body_color = color
	m.lower_color = lower
	m._build()
	m.scale = Vector3.ONE * 0.92   # sits better in a narrow touge lane
	return m


func _mat(c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent else body).add_child(mi)
	return mi


# ------------------------------------------------------------------ body loft

func _station_at(z: float) -> Array:
	var st: Array = _shape.stations
	if z <= st[0][0]:
		return st[0].duplicate()
	for i in range(1, st.size()):
		if z <= st[i][0]:
			var t: float = (z - st[i - 1][0]) / (st[i][0] - st[i - 1][0])
			var out := []
			for k in 6:
				out.append(lerpf(st[i - 1][k], st[i][k], t))
			return out
	return st[st.size() - 1].duplicate()


## Right-half cross-section ring, bottom centre to top centre.
func _ring(z: float) -> PackedVector2Array:
	var s := _station_at(z)
	var yb: float = s[1]
	var ybelt: float = s[2]
	var ytop: float = s[3]
	var w: float = s[4]
	var wt: float = s[5]
	# wheel arches: lift the body bottom over each wheel
	var tr: float = _shape.get("tire", WHEEL_R)
	var arch := tr + 0.12
	for c in _wheel_zs():
		var dz := absf(z - c)
		if dz < arch:
			yb = maxf(yb, tr + sqrt(arch * arch - dz * dz) * 0.92)
	yb = minf(yb, ybelt - 0.08)
	var r := PackedVector2Array()
	r.append(Vector2(0.0, yb))
	r.append(Vector2(w - 0.05, yb))
	r.append(Vector2(w, yb + 0.05))
	# this ring point sits exactly on the two-tone paint line so the split is clean
	var split: float = clampf(_shape.panda if _shape.panda > 0.4 else (yb + ybelt) * 0.5, yb + 0.06, ybelt - 0.06)
	r.append(Vector2(w + 0.012, split))
	r.append(Vector2(w, ybelt - 0.02))
	r.append(Vector2(w - 0.035, ybelt + 0.012))
	r.append(Vector2(lerpf(w - 0.035, wt, 0.55), lerpf(ybelt, ytop, 0.6)))
	r.append(Vector2(wt, ytop - 0.035))
	r.append(Vector2(wt - 0.1, ytop))
	r.append(Vector2(0.0, ytop + 0.005))
	return r


## Which paint a body triangle gets, from its strip index and position.
## 0 = body paint, 1 = lower paint, 2 = glass, 3 = black trim
func _region(strip: int, y: float, z: float) -> int:
	var g: Array = _shape.glass
	var roof: Array = _shape.roof
	var side: Array = _shape.side
	var bp: Array = _shape.b_pillar
	if _shape.panda > 0.4:
		if strip <= 2:
			return 1
	elif strip <= 1:
		return 1
	var ck: Array = _shape.get("cockpit", [99.0, 99.0])
	if strip >= 7 and z > ck[0] and z < ck[1]:
		return 3
	if z > g[0] and z < g[1]:
		if strip == 5 or strip == 6:
			if z > side[0] and z < side[1]:
				return 3 if (z > bp[0] and z < bp[1]) else 2
			return 0
		if strip == 7:
			return 0    # A/C pillars and roof rail keep windscreen, hatch and side glass apart
		if strip == 8:
			if z > roof[0] and z < roof[1]:
				return 0
			return 2
	return 0


func _build_body_mesh(paint: Material, lower: Material, glass: Material, trim: Material) -> MeshInstance3D:
	var st_list: Array = _shape.stations
	var z0: float = st_list[0][0]
	var z1: float = st_list[st_list.size() - 1][0]
	var zs: Array[float] = []
	var n_st := 120
	for i in n_st + 1:
		zs.append(lerpf(z0, z1, float(i) / n_st))
	# full ring = right half + mirrored left half (closed loop around the car)
	var rings: Array = []
	for z in zs:
		var half := _ring(z)
		var full := PackedVector3Array()
		for p in half:
			full.append(Vector3(p.x, p.y, z))
		for k in range(half.size() - 2, 0, -1):
			full.append(Vector3(-half[k].x, half[k].y, z))
		rings.append(full)
	var rn: int = rings[0].size()
	var half_n := _ring(zs[0]).size()
	# smooth vertex normals from the grid
	var normals: Array = []
	for i in rings.size():
		var nr := PackedVector3Array()
		for k in rn:
			var a: Vector3 = rings[mini(i + 1, rings.size() - 1)][k] - rings[maxi(i - 1, 0)][k]
			var b: Vector3 = rings[i][(k + 1) % rn] - rings[i][(k - 1 + rn) % rn]
			var n := b.cross(a).normalized()
			nr.append(n)
		normals.append(nr)
	var tools := []
	for m in [paint, lower, glass, trim]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(m)
		tools.append(st)
	for i in rings.size() - 1:
		for k in rn:
			var k2 := (k + 1) % rn
			var strip := k if k < half_n - 1 else (rn - 1 - k)
			strip = clampi(strip, 0, 8)
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][k2]
			var c: Vector3 = rings[i + 1][k]
			var d: Vector3 = rings[i + 1][k2]
			var cen := (a + b + c + d) * 0.25
			var reg := _region(strip, cen.y, cen.z)
			var st: SurfaceTool = tools[reg]
			var na: Vector3 = normals[i][k]
			var nb: Vector3 = normals[i][k2]
			var nc: Vector3 = normals[i + 1][k]
			var nd: Vector3 = normals[i + 1][k2]
			if reg == 2:
				# flat glass panels catch reflections like the anime CG
				var fn := (b - a).cross(c - a).normalized()
				na = fn; nb = fn; nc = fn; nd = fn
			_tri(st, a, b, c, na, nb, nc)
			_tri(st, b, d, c, nb, nd, nc)
	# end caps
	for cap in [[0, Vector3.FORWARD], [rings.size() - 1, Vector3.BACK]]:
		var ring: PackedVector3Array = rings[cap[0]]
		var cen := Vector3.ZERO
		for p in ring:
			cen += p
		cen /= ring.size()
		var st: SurfaceTool = tools[0]
		for k in rn:
			var p0 := ring[k]
			var p1 := ring[(k + 1) % rn]
			var reg := 1 if (p0.y + p1.y) * 0.5 < maxf(_shape.panda, 0.45) else 0
			st = tools[reg]
			var cn: Vector3 = cap[1]
			_tri(st, cen, p0, p1, cn, cn, cn)
	var mesh := ArrayMesh.new()
	for st in tools:
		st.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


## Emit a triangle so it faces outward: Godot treats clockwise-from-outside
## as the front face, and the normals must point away from the body.
func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, n0: Vector3, n1: Vector3, n2: Vector3) -> void:
	var cen := (p0 + p1 + p2) / 3.0
	var out := cen - Vector3(0.0, 0.62, clampf(cen.z, -1.6, 1.6))
	var fn := (p1 - p0).cross(p2 - p0)
	if fn.length_squared() < 1e-12:
		return
	if fn.dot(out) > 0.0:
		var t := p1; p1 = p2; p2 = t
		var tn := n1; n1 = n2; n2 = tn
	for pair in [[p0, n0], [p1, n1], [p2, n2]]:
		var n: Vector3 = pair[1]
		if n.dot(out) < 0.0:
			n = -n
		st.set_normal(n)
		st.add_vertex(pair[0])


func surface_y(z: float, x := 0.0) -> float:
	var s := _station_at(z)
	return s[3] if absf(x) < s[5] else s[2]


# ------------------------------------------------------------------ build

## Normalised side profiles per body style:
## [f along length 0..1, belt/H, top/H, half-width/W*2, top width/half-width]
const PROFILES := {
	"hatch": {"st": [[0.0, .45, .47, .92, .85], [0.02, .50, .53, .98, .92], [0.1, .53, .58, 1, .95], [0.22, .57, .63, 1, .95],
		[0.30, .60, .66, 1, .92], [0.32, .61, .70, 1, .88], [0.50, .63, .96, 1, .80], [0.75, .65, .98, 1, .78],
		[0.93, .66, .80, .99, .80], [0.98, .64, .70, .96, .85], [1.0, .60, .62, .92, .82]],
		"glass": [0.32, 0.93], "roof": [0.5, 0.75], "side": [0.34, 0.88], "b": [0.55, 0.58]},
	"notch": {"st": [[0.0, .44, .46, .92, .85], [0.02, .50, .53, .98, .93], [0.1, .53, .57, 1, .95], [0.3, .58, .63, 1, .93],
		[0.33, .59, .67, 1, .88], [0.5, .61, .97, 1, .80], [0.70, .63, .98, 1, .79], [0.80, .65, .72, 1, .88],
		[0.96, .66, .70, .99, .92], [1.0, .62, .64, .95, .88]],
		"glass": [0.33, 0.80], "roof": [0.5, 0.70], "side": [0.35, 0.76], "b": [0.55, 0.58]},
	"fastback": {"st": [[0.0, .42, .44, .92, .85], [0.02, .48, .51, .98, .92], [0.12, .52, .56, 1, .95], [0.32, .57, .62, 1, .93],
		[0.35, .58, .66, 1, .88], [0.52, .60, .97, 1, .80], [0.66, .62, .98, 1, .79], [0.93, .65, .71, 1, .88],
		[0.98, .64, .68, .97, .9], [1.0, .60, .62, .94, .88]],
		"glass": [0.35, 0.93], "roof": [0.52, 0.66], "side": [0.37, 0.80], "b": [0.6, 0.62]},
	"wedge": {"st": [[0.0, .36, .38, .9, .8], [0.03, .42, .45, .97, .9], [0.15, .48, .52, 1, .95], [0.36, .56, .60, 1, .92],
		[0.39, .57, .64, 1, .86], [0.55, .60, .97, 1, .78], [0.68, .62, .98, 1, .77], [0.88, .66, .72, 1, .88],
		[0.97, .66, .70, .98, .92], [1.0, .6, .62, .94, .88]],
		"glass": [0.39, 0.88], "roof": [0.55, 0.68], "side": [0.41, 0.80], "b": [9.0, 9.0]},
	"roadster": {"st": [[0.0, .42, .44, .92, .85], [0.02, .48, .51, .98, .92], [0.12, .52, .56, 1, .95], [0.36, .58, .62, 1, .93],
		[0.40, .59, .66, 1, .88], [0.50, .60, .90, 1, .78], [0.53, .60, .66, 1, .85], [0.75, .62, .66, 1, .88],
		[0.95, .64, .68, .99, .92], [1.0, .6, .62, .95, .88]],
		"glass": [0.40, 0.50], "roof": [0.0, 0.0], "side": [9.0, 9.0], "b": [9.0, 9.0], "cockpit": [0.52, 0.74]},
}


func _wheel_zs() -> Array:
	if _shape.has("wheel_front"):
		return [_shape.wheel_front, _shape.wheel_rear]
	return [-float(_shape.wheel_z), float(_shape.wheel_z)]


func _make_shape(sp: Dictionary) -> Dictionary:
	if sp.has("table"):
		# hand-measured profile: [m from front, belt y, top y, half width, top half width]
		var tab: Array = sp.table
		var L: float = tab[tab.size() - 1][0]
		var st: Array = []
		for row in tab:
			st.append([-L * 0.5 + row[0], 0.24, row[1], row[2], row[3], row[4]])
		var zf := func(x: float) -> float: return -L * 0.5 + x if x < 8.0 else 99.0
		var fo: float = sp.get("fo", 0.9)
		return {
			"stations": st,
			"glass": [zf.call(sp.glass[0]), zf.call(sp.glass[1])],
			"roof": [zf.call(sp.roof[0]), zf.call(sp.roof[1])],
			"side": [zf.call(sp.side[0]), zf.call(sp.side[1])],
			"b_pillar": [zf.call(sp.b[0]), zf.call(sp.b[1])],
			"cockpit": [zf.call(sp.cockpit[0]), zf.call(sp.cockpit[1])] if sp.has("cockpit") else [99.0, 99.0],
			"wheel_z": sp.get("wb", 2.4) * 0.5,
			"wheel_front": -L * 0.5 + fo,
			"wheel_rear": -L * 0.5 + fo + sp.get("wb", 2.4),
			"tire": sp.get("tire", WHEEL_R),
			"track": tab[2][3] - 0.12,
			"panda": 0.56 if panda_split else 0.3,
			"popups": sp.get("lamps", "fixed") == "popup",
			"popup_z": -L * 0.5 + 0.34,
			"spoiler": false,
		}
	if sp.get("kind", "") == "ae86":
		var d: Dictionary = SHAPES.hatch.duplicate(true)
		d.panda = 0.56 if panda_split else 0.3
		return d
	var L: float = sp.L
	var W: float = sp.W
	var H: float = sp.H
	var prof: Dictionary = PROFILES[sp.kind]
	var st: Array = []
	for row in prof.st:
		var z: float = -L * 0.5 + row[0] * L
		var w: float = W * 0.5 * row[3] - 0.02
		st.append([z, 0.24, row[1] * H, row[2] * H, w, w * row[4]])
	var zf := func(f: float) -> float: return -L * 0.5 + f * L
	return {
		"stations": st,
		"glass": [zf.call(prof.glass[0]), zf.call(prof.glass[1])],
		"roof": [zf.call(prof.roof[0]), zf.call(prof.roof[1])],
		"side": [zf.call(prof.side[0]) if prof.side[0] < 2.0 else 99.0, zf.call(prof.side[1]) if prof.side[0] < 2.0 else 99.0],
		"b_pillar": [zf.call(prof.b[0]) if prof.b[0] < 2.0 else 99.0, zf.call(prof.b[1]) if prof.b[0] < 2.0 else 99.0],
		"cockpit": [zf.call(prof.cockpit[0]), zf.call(prof.cockpit[1])] if prof.has("cockpit") else [99.0, 99.0],
		"wheel_z": L * 0.285,
		"panda": (H * 0.43) if panda_split else 0.3,
		"popups": sp.get("lamps", "fixed") == "popup",
		"popup_z": -L * 0.5 + 0.32,
		"spoiler": false,
	}


func _build() -> void:
	if template == "car":
		_shape = _make_shape(spec)
	else:
		_shape = SHAPES.get(template, SHAPES.hatch)
	body = Node3D.new()
	add_child(body)
	var paint := _mat(body_color * Color(0.88, 0.88, 0.88), 0.2, 0.1)
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.6
	paint.rim_enabled = true
	paint.rim = 0.25
	var lower := _mat(lower_color, 0.25, 0.2)
	var glass := _mat(Color(0.09, 0.11, 0.15), 0.05, 0.3)
	glass.rim_enabled = true
	glass.rim = 0.6
	glass.rim_tint = 0.2
	var trim := _mat(Color(0.02, 0.02, 0.02), 0.6)
	var black := _mat(Color(0.03, 0.03, 0.03), 0.55)
	var chrome := _mat(Color(0.8, 0.8, 0.82), 0.15, 0.9)
	var plate := _mat(Color(0.92, 0.92, 0.88), 0.5)
	tail_mat = _mat(Color(0.45, 0.0, 0.0), 0.2)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.04, 0.02)
	tail_mat.emission_energy_multiplier = 1.2
	lens_mat = _mat(Color(0.95, 0.95, 0.85), 0.1)
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(1.0, 0.97, 0.85)
	lens_mat.emission_energy_multiplier = 4.0
	var amber := _mat(Color(1.0, 0.5, 0.05), 0.2)
	amber.emission_enabled = true
	amber.emission = Color(1.0, 0.45, 0.0)
	amber.emission_energy_multiplier = 0.6

	body.add_child(_build_body_mesh(paint, lower, glass, trim))
	var st_list: Array = _shape.stations
	var front_z: float = st_list[0][0]
	var rear_z: float = st_list[st_list.size() - 1][0]
	var front_s: Array = st_list[1]
	var rear_s: Array = st_list[st_list.size() - 2]

	# bumpers, plates, lamps
	var bumper_mat: Material = paint if spec.get("bumper", "black") == "body" else black
	_box(Vector3(front_s[4] * 2.0 - 0.02, 0.17, 0.2), Vector3(0, 0.36, front_z + 0.02), bumper_mat)
	_box(Vector3(rear_s[4] * 2.0 - 0.02, 0.17, 0.2), Vector3(0, 0.38, rear_z - 0.02), bumper_mat)
	if spec.get("bumper", "black") == "body":
		# dark intake in the front bumper
		_box(Vector3(front_s[4] * 1.1, 0.08, 0.03), Vector3(0, 0.33, front_z - 0.08), black)
	_box(Vector3(0.34, 0.12, 0.02), Vector3(0, 0.33, front_z - 0.09), plate)
	_box(Vector3(0.34, 0.17, 0.02), Vector3(0, 0.58, rear_z + 0.005), plate)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.16, 0.06, 0.03), Vector3(sx * 0.62, 0.43, front_z - 0.06), amber)
		_box(Vector3(0.07, 0.09, 0.14), Vector3(sx * (front_s[4] + 0.07), front_s[2] + 0.12 + 0.05, -0.5), black)   # mirror
		_box(Vector3(0.02, 0.05, 0.05), Vector3(sx * (front_s[4] + 0.03), front_s[2] + 0.12, -0.46), black)
	var look: Dictionary = spec
	if template != "car":
		look = {"hatch": {"lamps": "popup", "wing": "roof", "tail": "bar"},
			"coupe": {"lamps": "popup", "wing": "duck", "tail": "wide"},
			"sedan": {"lamps": "fixed", "wing": "big", "tail": "round"}}.get(template, {})
	if spec.get("kind", "") == "ae86":
		look = {"lamps": "popup", "wing": "roof", "tail": "bar"}
	var belt_r: float = rear_s[2]
	var top_r: float = st_list[st_list.size() - 1][3]
	var half_r: float = rear_s[4]
	match look.get("tail", "bar"):
		"round":
			for sx in [-1.0, 1.0]:
				for k in 2:
					var cyl := CylinderMesh.new()
					cyl.top_radius = 0.085
					cyl.bottom_radius = 0.085
					cyl.height = 0.04
					var tl := MeshInstance3D.new()
					tl.mesh = cyl
					tl.material_override = tail_mat
					tl.rotation.x = PI / 2
					tl.position = Vector3(sx * (half_r - 0.2 - k * 0.24), belt_r - 0.1, rear_z + 0.015)
					body.add_child(tl)
		"wide":
			_box(Vector3(half_r * 2.0 - 0.2, 0.12, 0.03), Vector3(0, belt_r - 0.1, rear_z + 0.012), tail_mat)
		_:
			for sx in [-1.0, 1.0]:
				_box(Vector3(0.44, 0.13, 0.03), Vector3(sx * (half_r - 0.32), belt_r - 0.1, rear_z + 0.012), tail_mat)
			_box(Vector3(maxf(half_r * 2.0 - 1.4, 0.3), 0.13, 0.03), Vector3(0, belt_r - 0.1, rear_z + 0.012), black)
	if look.get("lamps", "popup") == "fixed":
		var fs: Array = st_list[1]
		for sx in [-1.0, 1.0]:
			var hl := _box(Vector3(0.36, 0.11, 0.03), Vector3(sx * (fs[4] - 0.3), fs[2] - 0.04, front_z + 0.005), lens_mat)
			head_glow.append(hl)
		_box(Vector3(maxf(fs[4] * 2.0 - 1.3, 0.3), 0.09, 0.03), Vector3(0, fs[2] - 0.05, front_z + 0.005), black)
	var roof_end_z: float = _shape.roof[1]
	match look.get("wing", "none"):
		"roof":
			_box(Vector3(_station_at(roof_end_z)[5] * 1.7, 0.035, 0.2), Vector3(0, _station_at(roof_end_z)[3] + 0.015, roof_end_z + 0.02), black)
		"lip":
			_box(Vector3(half_r * 1.6, 0.03, 0.12), Vector3(0, top_r + 0.04, rear_z - 0.12), paint)
		"duck":
			_box(Vector3(half_r * 1.7, 0.04, 0.22), Vector3(0, top_r + 0.06, rear_z - 0.15), paint)
			for sx in [-1.0, 1.0]:
				_box(Vector3(0.06, 0.1, 0.06), Vector3(sx * half_r * 0.7, top_r + 0.0, rear_z - 0.15), paint)
		"big":
			_box(Vector3(half_r * 1.85, 0.045, 0.3), Vector3(0, top_r + 0.25, rear_z - 0.2), paint)
			for sx in [-1.0, 1.0]:
				_box(Vector3(0.05, 0.24, 0.1), Vector3(sx * half_r * 0.72, top_r + 0.12, rear_z - 0.2), paint)

	# pop-up headlights: lids sit flush on the hood and flip up
	if _shape.popups:
		var pz: float = _shape.popup_z
		var hood_y: float = _station_at(pz)[3]
		for sx in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(sx * 0.5, hood_y + 0.005, pz + 0.16)
			body.add_child(pivot)
			_box(Vector3(0.4, 0.1, 0.3), Vector3(0, -0.05, -0.15), paint, pivot)
			var lens := _box(Vector3(0.34, 0.012, 0.24), Vector3(0, -0.101, -0.15), lens_mat, pivot)
			head_glow.append(lens)
			popups.append(pivot)
	# headlight beams + lens flares
	var flare_y: float = 0.98 if _shape.popups else float(st_list[1][2]) - 0.04
	var flare_z: float = (_shape.popup_z if _shape.popups else front_z) - 0.12
	for sx in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		spot.position = Vector3(sx * 0.5, 0.8, front_z - 0.1)
		spot.rotation.x = deg_to_rad(-5.0)
		spot.spot_range = 75.0
		spot.spot_angle = 30.0
		spot.spot_attenuation = 0.7
		spot.light_energy = 5.0
		spot.light_color = Color(1.0, 0.96, 0.85)
		add_child(spot)
		headlights.append(spot)
		var fl := _flare(Color(1.0, 0.97, 0.9), 1.6)
		fl.position = Vector3(sx * 0.5, flare_y, flare_z)
		add_child(fl)
		head_glow.append(fl)
		var tf := _flare(Color(1.0, 0.1, 0.05), 0.5)
		tf.position = Vector3(sx * 0.5, 0.72, rear_z + 0.08)
		add_child(tf)
		tail_glow.append(tf)
	# soft fill light so the paint reads at night, and a contact shadow
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 2.8, 0.6)
	fill.omni_range = 5.5
	fill.light_energy = 0.45
	fill.light_color = Color(0.85, 0.9, 1.0)
	add_child(fill)
	var shadow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.3, absf(rear_z - front_z) + 0.6)
	q.orientation = PlaneMesh.FACE_Y
	shadow.mesh = q
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = _shadow_texture()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0, 0, 0, 0.85)
	shadow.material_override = sm
	shadow.position = Vector3(0, 0.03, (front_z + rear_z) * 0.5)
	add_child(shadow)

	# wheels: tyre, rim with spokes, hub
	var tire := _mat(Color(0.04, 0.04, 0.04), 0.85)
	var rim := _mat(Color(0.75, 0.76, 0.78), 0.2, 0.85)
	var hub := _mat(Color(0.15, 0.15, 0.16), 0.4, 0.6)
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = WHEEL_R
	tire_mesh.bottom_radius = WHEEL_R
	tire_mesh.height = 0.2
	tire_mesh.radial_segments = 18
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.19
	rim_mesh.bottom_radius = 0.19
	rim_mesh.height = 0.205
	rim_mesh.radial_segments = 14
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.055
	hub_mesh.bottom_radius = 0.055
	hub_mesh.height = 0.215
	hub_mesh.radial_segments = 8
	var tr: float = _shape.get("tire", WHEEL_R)
	tire_mesh.top_radius = tr
	tire_mesh.bottom_radius = tr
	tire_mesh.height = 0.2 + (tr - 0.28) * 0.6
	rim_mesh.top_radius = tr * 0.64
	rim_mesh.bottom_radius = tr * 0.64
	var track: float = _shape.get("track", 0.7)
	for zz in _wheel_zs():
		for sx in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(sx * track, tr, zz)
			add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			for pair in [[tire_mesh, tire], [rim_mesh, rim], [hub_mesh, hub]]:
				var m := MeshInstance3D.new()
				m.mesh = pair[0]
				m.material_override = pair[1]
				m.rotation.z = PI / 2
				spin.add_child(m)
			for k in 5:
				var holder := Node3D.new()
				holder.rotation.x = TAU * k / 5.0
				spin.add_child(holder)
				var hole := MeshInstance3D.new()
				var hb := BoxMesh.new()
				hb.size = Vector3(0.212, 0.05, 0.06)
				hole.mesh = hb
				hole.material_override = hub
				hole.position = Vector3(0, 0.12, 0)
				holder.add_child(hole)
			wheels.append(pivot)
			wheel_spin.append(spin)
			wheel_base_y.append(tr)
	set_lights(true, true)


func _toon_paint(c: Color, gloss: float, glass: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/car_toon.gdshader")
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("gloss", gloss)
	m.set_shader_parameter("glass", 1.0 if glass else 0.0)
	m.set_shader_parameter("key_dir", Mats.moon_dir)
	return m


## High-detail model built in Blender (tools/blender_car.py).
func _build_glb(scene: PackedScene) -> void:
	var inst := scene.instantiate()
	add_child(inst)
	body = inst
	var paint := _mat(body_color * Color(0.9, 0.9, 0.9), 0.22, 0.1)
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.7
	paint.rim_enabled = true
	paint.rim = 0.2
	var lower := _mat(lower_color, 0.3, 0.15)
	lower.clearcoat_enabled = true
	lower.clearcoat = 0.5
	var glass := _mat(Color(0.05, 0.06, 0.09), 0.04, 0.5)
	glass.rim_enabled = true
	glass.rim = 0.7
	glass.rim_tint = 0.3
	tail_mat = _mat(Color(0.5, 0.02, 0.02), 0.15)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.05, 0.03)
	lens_mat = _mat(Color(1.0, 0.98, 0.9), 0.05)
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(1.0, 0.97, 0.88)
	lens_mat.emission_energy_multiplier = 6.0
	var amber := _mat(Color(1.0, 0.5, 0.05), 0.15)
	amber.emission_enabled = true
	amber.emission = Color(1.0, 0.45, 0.0)
	amber.emission_energy_multiplier = 0.8
	var by_name := {"Paint": paint, "Lower": lower, "Glass": glass, "Tail": tail_mat, "Lens": lens_mat, "Amber": amber}
	if Mats.hq():
		# showroom-grade surfaces: deep clear-coated paint, real glass, bright metal, rubber
		paint.metallic = 0.35
		paint.roughness = 0.32
		paint.clearcoat = 1.0
		paint.clearcoat_roughness = 0.04
		lower.metallic = 0.3
		lower.roughness = 0.3
		lower.clearcoat = 1.0
		lower.clearcoat_roughness = 0.06
		glass.albedo_color = Color(0.02, 0.03, 0.04, 0.62)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.roughness = 0.02
		glass.metallic = 0.0
		glass.metallic_specular = 1.0
		glass.rim_enabled = false
		var chrome := _mat(Color(0.9, 0.9, 0.92), 0.08, 1.0)
		var rim_lip := _mat(Color(0.85, 0.85, 0.87), 0.1, 1.0)
		var tire := _mat(Color(0.025, 0.025, 0.027), 0.92)
		var trim := _mat(Color(0.02, 0.02, 0.022), 0.6)
		var well := _mat(Color(0.008, 0.008, 0.01), 1.0)
		by_name.merge({"Chrome": chrome, "RimLip": rim_lip, "Tire": tire, "Trim": trim, "Well": well})
		tail_mat.emission_energy_multiplier = 2.0
	if Mats.toon():
		# cel paint: two flat tones, a hard highlight and a rim light
		by_name["Paint"] = _toon_paint(body_color, 1.0, false)
		by_name["Lower"] = _toon_paint(lower_color, 0.7, false)
		by_name["Glass"] = _toon_paint(Color(0.05, 0.08, 0.16), 1.0, true)
	var aabb := AABB()
	var first := true
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi.mesh
		for i in mesh.get_surface_count():
			var sm := mesh.surface_get_material(i)
			if sm and by_name.has(sm.resource_name):
				mi.set_surface_override_material(i, by_name[sm.resource_name])
		if mi.name.begins_with("Body") or mi.get_parent().name.begins_with("Body"):
			aabb = mi.get_aabb() if first else aabb.merge(mi.get_aabb())
			first = false
	var front_z := aabb.position.z
	var rear_z := aabb.end.z
	# wheels: pivot (steer + suspension) -> spin -> imported mesh
	for wn in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var w := inst.find_child(wn, true, false) as Node3D
		if w == null:
			continue
		var pivot := Node3D.new()
		pivot.position = w.position
		add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		w.get_parent().remove_child(w)
		spin.add_child(w)
		w.position = Vector3.ZERO
		wheels.append(pivot)
		wheel_spin.append(spin)
		wheel_base_y.append(pivot.position.y)
	# pop-up lamps: origin on the hinge, they rotate about X
	var lamp_pos: Array[Vector3] = []
	for pn in ["Popup_L", "Popup_R"]:
		var p := inst.find_child(pn, true, false) as Node3D
		if p:
			popups.append(p)
			_popup_hinged = true
			var ang := 40.0
			var lp := p.position + Vector3(0, 0.08, -0.25)
			for ch in p.get_children():
				if String(ch.name).begins_with("lens_"):
					ang = String(ch.name).substr(5).to_float() / 10.0
					lp = p.position + (ch as Node3D).position
			_popup_close.append(deg_to_rad(ang))
			lamp_pos.append(lp + Vector3(0, 0, -0.03))
	if lamp_pos.is_empty():
		for sx in [-1.0, 1.0]:
			lamp_pos.append(Vector3(sx * 0.55, 0.62, front_z + 0.05))
	for lp in lamp_pos:
		var spot := SpotLight3D.new()
		spot.position = Vector3(lp.x, 0.8, front_z - 0.1)
		spot.rotation.x = deg_to_rad(-5.0)
		spot.spot_range = 75.0
		spot.spot_angle = 30.0
		spot.spot_attenuation = 0.7
		spot.light_energy = 5.0
		spot.light_color = Color(1.0, 0.96, 0.85)
		if Mats.toon():
			# a broad even pool rather than a hot spot under the bumper
			spot.light_energy = 4.0
			spot.spot_attenuation = 0.5
		if Mats.hq():
			spot.shadow_enabled = true
			spot.light_energy = 9.0
			spot.spot_range = 90.0
			spot.light_volumetric_fog_energy = 2.5
			spot.light_specular = 1.0
		add_child(spot)
		headlights.append(spot)
		var fl := _flare(Color(1.0, 0.97, 0.9), 0.9)
		fl.position = lp + Vector3(0, 0, -0.05)
		add_child(fl)
		head_glow.append(fl)
		var tf := _flare(Color(1.0, 0.1, 0.05), 0.5)
		tf.position = Vector3(lp.x, 0.72, rear_z + 0.06)
		add_child(tf)
		tail_glow.append(tf)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 2.8, 0.6)
	fill.omni_range = 5.5
	fill.light_energy = 0.45
	fill.light_color = Color(0.85, 0.9, 1.0)
	add_child(fill)
	var shadow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.3, absf(rear_z - front_z) + 0.6)
	q.orientation = PlaneMesh.FACE_Y
	shadow.mesh = q
	var shm := StandardMaterial3D.new()
	shm.albedo_texture = _shadow_texture()
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.albedo_color = Color(0, 0, 0, 0.85)
	shadow.material_override = shm
	shadow.position = Vector3(0, 0.03, (front_z + rear_z) * 0.5)
	add_child(shadow)
	set_lights(true, true)


func _flare(col: Color, size: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _flare_texture()
	m.albedo_color = col
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = false
	m.render_priority = 2
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _flare_texture() -> Texture2D:
	if _flare_tex:
		return _flare_tex
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var dx := (x - 63.5) / 64.0
			var dy := (y - 63.5) / 64.0
			var r := sqrt(dx * dx + dy * dy)
			var core := clampf(1.0 - r * 2.2, 0.0, 1.0)
			var halo := clampf(1.0 - r, 0.0, 1.0) * 0.35
			var star := maxf(clampf(1.0 - absf(dy) * 18.0, 0.0, 1.0) * clampf(1.0 - absf(dx), 0.0, 1.0),
				clampf(1.0 - absf(dx) * 18.0, 0.0, 1.0) * clampf(1.0 - absf(dy), 0.0, 1.0) * 0.6)
			var a := clampf(core * core + halo * halo + star, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_flare_tex = ImageTexture.create_from_image(img)
	return _flare_tex


static func _shadow_texture() -> Texture2D:
	if _shadow_tex:
		return _shadow_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dx := absf(x - 31.5) / 32.0
			var dy := absf(y - 31.5) / 32.0
			var d := maxf(pow(dx, 3.0) + pow(dy, 3.0), 0.0)
			img.set_pixel(x, y, Color(0, 0, 0, clampf(1.0 - d, 0.0, 1.0) * 0.9))
	_shadow_tex = ImageTexture.create_from_image(img)
	return _shadow_tex


func set_lights(on: bool, instant := false) -> void:
	_lights_target = on
	if instant:
		_popup_angle = PI / 2 if on else 0.0
		_apply_lights()


func _apply_lights() -> void:
	var open := _popup_angle / (PI / 2) if popups.size() > 0 else (1.0 if _lights_target else 0.0)
	for i in popups.size():
		if _popup_hinged:
			popups[i].rotation.x = -_popup_close[i] * (1.0 - open)
		else:
			popups[i].rotation.x = _popup_angle
	for h in headlights:
		h.visible = open > 0.6
		h.light_energy = (9.0 if Mats.hq() else 5.0) * open
	for g in head_glow:
		g.visible = open > 0.4
	if lens_mat:
		lens_mat.emission_energy_multiplier = lerpf(0.0, 6.0, open)


var _smoke: Array[CPUParticles3D] = []
## Tyre smoke from the rear wheels while the car slides.
var smoking := false:
	set(v):
		smoking = v
		for p in _smoke:
			p.emitting = v


## Cartoon tyre smoke: solid round puffs that swell and shrink away, so the
## ink lines draw them like smoke in a comic.
func _build_smoke() -> void:
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 9
	puff.rings = 5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.94, 1.0)
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.38, 0.5)
	var swell := Curve.new()
	swell.add_point(Vector2(0.0, 0.25))
	swell.add_point(Vector2(0.3, 1.0))
	swell.add_point(Vector2(1.0, 0.0))
	for i in [2, 3]:
		var p := CPUParticles3D.new()
		p.mesh = puff
		p.material_override = mat
		p.amount = 12
		p.lifetime = 0.75
		p.local_coords = false
		p.emitting = false
		p.direction = Vector3(0, 0.5, 1)
		p.spread = 28.0
		p.initial_velocity_min = 1.2
		p.initial_velocity_max = 3.0
		p.gravity = Vector3(0, 1.6, 0)
		p.scale_amount_min = 0.45
		p.scale_amount_max = 0.95
		p.scale_amount_curve = swell
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = Vector3(wheels[i].position.x, 0.18, wheels[i].position.z + 0.25)
		add_child(p)
		_smoke.append(p)


## A burst of sparks where the car hits something (position in the car's space).
func sparks(at: Vector3) -> void:
	var chip := BoxMesh.new()
	chip.size = Vector3(0.05, 0.05, 0.3)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 3.0
	var p := CPUParticles3D.new()
	p.mesh = chip
	p.material_override = mat
	p.amount = 26
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3(0, 0.6, 0)
	p.spread = 80.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3(0, -14.0, 0)
	p.particle_flag_align_y = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func update_visual(dt: float, steer_angle: float, speed: float, braking: bool, wheel_offsets: Array = []) -> void:
	if _smoke.is_empty() and wheels.size() >= 4:
		_build_smoke()
	var target := PI / 2 if _lights_target else 0.0
	if not is_equal_approx(_popup_angle, target):
		_popup_angle = move_toward(_popup_angle, target, dt * 4.0)
		_apply_lights()
	_spin += speed / WHEEL_R * dt
	for i in wheels.size():
		if i < 2:
			wheels[i].rotation.y = -steer_angle
		wheel_spin[i].rotation.x = -_spin
		if wheel_offsets.size() == 4:
			wheels[i].position.y = wheel_base_y[i] + wheel_offsets[i]
	tail_mat.emission_energy_multiplier = 4.0 if braking else (1.4 if _lights_target else 0.3)
	for t in tail_glow:
		t.visible = braking or _lights_target
		(t.material_override as StandardMaterial3D).albedo_color.a = 1.0 if braking else 0.5
