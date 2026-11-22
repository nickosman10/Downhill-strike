class_name CarModel
extends Node3D
## Low-poly procedural car bodies. Local forward is -Z, up is +Y.
## "hatch"  : 80s two-tone 3-door hatchback with pop-up headlights (player car)
## "coupe"  : rounded rotary-style coupe with pop-ups
## "sedan"  : boxy turbo coupe with a big wing

const WHEEL_R := 0.29

var template := "hatch"
var body_color := Color(0.95, 0.95, 0.93)
var lower_color := Color(0.06, 0.06, 0.07)

var wheels: Array[Node3D] = []      # steering pivots (FL, FR, RL, RR)
var wheel_spin: Array[Node3D] = []
var wheel_base_y: Array[float] = []
var popups: Array[Node3D] = []
var headlights: Array[SpotLight3D] = []
var head_glow: Array[MeshInstance3D] = []
var tail_mat: StandardMaterial3D
var lens_mat: StandardMaterial3D
var body: Node3D

var _popup_angle := 0.0
var _lights_target := true
var _spin := 0.0


static func create(tmpl: String, color: Color, lower := Color(0.06, 0.06, 0.07)) -> CarModel:
	var m := CarModel.new()
	m.template = tmpl
	m.body_color = color
	m.lower_color = lower
	m._build()
	return m


func _mat(c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Extrudes a side profile (points are (z, y)) across the car's width.
## half_w may be a float or an Array of per-point half widths.
func _loft(profile: Array, half_w, mat: Material) -> MeshInstance3D:
	var pts := PackedVector2Array()
	for p in profile:
		pts.append(p)
	var hws: Array = []
	for i in pts.size():
		hws.append(half_w[i] if half_w is Array else half_w)
	var centroid := Vector2.ZERO
	for p in pts:
		centroid += p
	centroid /= pts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(pts)
	for side in [-1.0, 1.0]:
		st.set_normal(Vector3(side, 0, 0))
		for t in tris:
			st.add_vertex(Vector3(side * hws[t], pts[t].y, pts[t].x))
	var n := pts.size()
	for i in n:
		var j := (i + 1) % n
		var a := pts[i]
		var b := pts[j]
		var e := b - a
		var nrm2 := Vector2(-e.y, e.x).normalized()
		if nrm2.dot((a + b) * 0.5 - centroid) < 0.0:
			nrm2 = -nrm2
		st.set_normal(Vector3(0, nrm2.y, nrm2.x))
		var a0 := Vector3(-hws[i], a.y, a.x)
		var a1 := Vector3(hws[i], a.y, a.x)
		var b0 := Vector3(-hws[j], b.y, b.x)
		var b1 := Vector3(hws[j], b.y, b.x)
		st.add_vertex(a0); st.add_vertex(a1); st.add_vertex(b0)
		st.add_vertex(a1); st.add_vertex(b1); st.add_vertex(b0)
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent else body).add_child(mi)
	return mi


func _build() -> void:
	body = Node3D.new()
	add_child(body)
	var paint := _mat(body_color, 0.3, 0.2)
	var lower := _mat(lower_color, 0.45, 0.1)
	var glass := _mat(Color(0.05, 0.07, 0.1), 0.1, 0.3)
	var black := _mat(Color(0.03, 0.03, 0.03), 0.7)
	tail_mat = _mat(Color(0.5, 0.0, 0.0), 0.3)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.05, 0.02)
	tail_mat.emission_energy_multiplier = 0.6
	lens_mat = _mat(Color(0.9, 0.9, 0.8), 0.2)
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(1.0, 0.95, 0.8)
	lens_mat.emission_energy_multiplier = 2.5

	var wheel_z := 1.2
	var front_z := -2.1
	var rear_z := 2.1
	var has_popups := true
	match template:
		"hatch":
			body.add_child(_loft([Vector2(-2.10, 0.22), Vector2(-2.15, 0.42), Vector2(-2.10, 0.56),
				Vector2(2.10, 0.56), Vector2(2.14, 0.40), Vector2(2.08, 0.22)], 0.82, lower))
			body.add_child(_loft([Vector2(-2.10, 0.56), Vector2(-2.06, 0.74), Vector2(-0.72, 0.90),
				Vector2(1.96, 0.93), Vector2(2.10, 0.80), Vector2(2.10, 0.56)], 0.83, paint))
			body.add_child(_loft([Vector2(-0.72, 0.90), Vector2(-0.02, 1.27), Vector2(1.0, 1.29),
				Vector2(1.96, 0.93)], [0.80, 0.66, 0.66, 0.78], glass))
			body.add_child(_loft([Vector2(-0.04, 1.27), Vector2(1.02, 1.29), Vector2(1.0, 1.335),
				Vector2(0.0, 1.315)], 0.665, paint))
			# B and C pillars
			for sx in [-1.0, 1.0]:
				_box(Vector3(0.03, 0.36, 0.12), Vector3(sx * 0.735, 1.1, 0.36), paint)
				_box(Vector3(0.03, 0.3, 0.32), Vector3(sx * 0.745, 1.08, 1.34), paint)
			_box(Vector3(1.2, 0.04, 0.22), Vector3(0, 1.3, 1.08), black)   # roof spoiler
		"coupe":
			front_z = -2.15
			rear_z = 2.15
			wheel_z = 1.22
			body.add_child(_loft([Vector2(-2.15, 0.24), Vector2(-2.22, 0.42), Vector2(-2.16, 0.58),
				Vector2(-1.2, 0.76), Vector2(-0.55, 0.82), Vector2(1.7, 0.86), Vector2(2.18, 0.78),
				Vector2(2.2, 0.46), Vector2(2.12, 0.24)], 0.86, paint))
			body.add_child(_loft([Vector2(-0.55, 0.82), Vector2(0.15, 1.2), Vector2(0.95, 1.22),
				Vector2(1.85, 0.87)], [0.82, 0.64, 0.64, 0.8], glass))
			body.add_child(_loft([Vector2(0.13, 1.2), Vector2(0.97, 1.22), Vector2(0.95, 1.255),
				Vector2(0.15, 1.235)], 0.645, paint))
			_box(Vector3(1.5, 0.05, 0.26), Vector3(0, 0.98, 2.0), paint)  # ducktail wing
			for sx in [-1.0, 1.0]:
				_box(Vector3(0.06, 0.12, 0.06), Vector3(sx * 0.6, 0.91, 2.0), paint)
		"sedan":
			front_z = -2.28
			rear_z = 2.28
			wheel_z = 1.33
			has_popups = false
			body.add_child(_loft([Vector2(-2.28, 0.24), Vector2(-2.32, 0.5), Vector2(-2.26, 0.76),
				Vector2(-0.75, 0.86), Vector2(1.6, 0.92), Vector2(2.3, 0.9), Vector2(2.32, 0.48),
				Vector2(2.24, 0.24)], 0.88, paint))
			body.add_child(_loft([Vector2(-0.75, 0.86), Vector2(-0.05, 1.32), Vector2(1.05, 1.32),
				Vector2(1.6, 0.92)], [0.84, 0.7, 0.7, 0.84], glass))
			body.add_child(_loft([Vector2(-0.07, 1.32), Vector2(1.07, 1.32), Vector2(1.05, 1.365),
				Vector2(-0.05, 1.36)], 0.705, paint))
			# big rear wing
			_box(Vector3(1.6, 0.05, 0.32), Vector3(0, 1.18, 2.05), paint)
			for sx in [-1.0, 1.0]:
				_box(Vector3(0.06, 0.28, 0.12), Vector3(sx * 0.65, 1.03, 2.05), paint)
				var gl := _box(Vector3(0.36, 0.14, 0.04), Vector3(sx * 0.48, 0.66, front_z - 0.02), lens_mat)
				head_glow.append(gl)

	# bumpers
	_box(Vector3(1.66, 0.18, 0.14), Vector3(0, 0.38, front_z - 0.03), black)
	_box(Vector3(1.66, 0.18, 0.14), Vector3(0, 0.38, rear_z + 0.03), black)
	# tail lights
	if template == "sedan":
		for sx in [-1.0, 1.0]:
			for k in 2:
				_box(Vector3(0.18, 0.18, 0.04), Vector3(sx * (0.45 + k * 0.24), 0.72, rear_z + 0.01), tail_mat)
	else:
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.46, 0.14, 0.04), Vector3(sx * 0.52, 0.7, rear_z + 0.005), tail_mat)
	# pop-up headlights
	if has_popups:
		for sx in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(sx * 0.5, 0.82, front_z + 0.42)
			body.add_child(pivot)
			_box(Vector3(0.4, 0.09, 0.28), Vector3(0, -0.045, -0.14), paint, pivot)
			var lens := _box(Vector3(0.34, 0.012, 0.22), Vector3(0, -0.095, -0.14), lens_mat, pivot)
			head_glow.append(lens)
			popups.append(pivot)
	# headlight beams
	for sx in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		spot.position = Vector3(sx * 0.5, 0.75, front_z - 0.2)
		spot.rotation.x = deg_to_rad(-4.0)
		spot.spot_range = 70.0
		spot.spot_angle = 28.0
		spot.spot_attenuation = 0.8
		spot.light_energy = 4.0
		spot.light_color = Color(1.0, 0.95, 0.82)
		add_child(spot)
		headlights.append(spot)
	# wheels
	var tire := _mat(Color(0.04, 0.04, 0.04), 0.9)
	var rim := _mat(Color(0.7, 0.7, 0.72), 0.3, 0.8)
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = WHEEL_R
	tire_mesh.bottom_radius = WHEEL_R
	tire_mesh.height = 0.2
	tire_mesh.radial_segments = 14
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.18
	rim_mesh.bottom_radius = 0.18
	rim_mesh.height = 0.205
	rim_mesh.radial_segments = 8
	for wz in [-wheel_z, wheel_z]:
		for sx in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(sx * 0.7, WHEEL_R, wz)
			add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			var t := MeshInstance3D.new()
			t.mesh = tire_mesh
			t.material_override = tire
			t.rotation.z = PI / 2
			spin.add_child(t)
			var r := MeshInstance3D.new()
			r.mesh = rim_mesh
			r.material_override = rim
			r.rotation.z = PI / 2
			spin.add_child(r)
			wheels.append(pivot)
			wheel_spin.append(spin)
			wheel_base_y.append(WHEEL_R)
	set_lights(true, true)


func set_lights(on: bool, instant := false) -> void:
	_lights_target = on
	if instant:
		_popup_angle = PI / 2 if on else 0.0
		_apply_lights()


func _apply_lights() -> void:
	var open := _popup_angle / (PI / 2) if popups.size() > 0 else (1.0 if _lights_target else 0.0)
	for p in popups:
		p.rotation.x = _popup_angle
	for h in headlights:
		h.visible = open > 0.6
		h.light_energy = 4.0 * open
	for g in head_glow:
		g.visible = open > 0.3


func update_visual(dt: float, steer_angle: float, speed: float, braking: bool, wheel_offsets: Array = []) -> void:
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
	tail_mat.emission_energy_multiplier = 2.5 if braking else (0.7 if _lights_target else 0.15)
