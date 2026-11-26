class_name CarModel
extends Node3D
## A car as drawn in the game: the Blender model (cars/<id>.glb) with cel
## paint, working lights and pop-up lamps, turning wheels, tyre smoke and
## sparks. Local forward is -Z, up is +Y.

const WHEEL_R := 0.3

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

var _popup_angle := 0.0
var _popup_close: Array[float] = []
var _lights_target := true
var _spin := 0.0

static var _flare_tex: Texture2D
static var _shadow_tex: Texture2D


## Build any car from the garage (Cars.ROSTER) by id.
static func for_car(id: String, override_paint := Color(-1, 0, 0)) -> CarModel:
	var c: Dictionary = Cars.get_car(id)
	var m := CarModel.new()
	m.body_color = c.paint if override_paint.r < 0.0 else override_paint
	m.lower_color = c.lower
	m._build_model(load("res://cars/%s.glb" % c.get("model", id)) as PackedScene)
	m.scale = Vector3.ONE * 0.92
	return m


func _mat(c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _toon_paint(c: Color, gloss: float, glass: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/car_toon.gdshader")
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("gloss", gloss)
	m.set_shader_parameter("glass", 1.0 if glass else 0.0)
	m.set_shader_parameter("key_dir", Mats.moon_dir)
	return m


## Loads the model built in Blender (tools/blender_car.py) and wires it up.
func _build_model(scene: PackedScene) -> void:
	var inst := scene.instantiate()
	add_child(inst)
	body = inst
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
	# cel paint: two flat tones, a hard highlight and a rim light
	var by_name := {"Paint": _toon_paint(body_color, 1.0, false), "Lower": _toon_paint(lower_color, 0.7, false),
		"Glass": _toon_paint(Color(0.05, 0.08, 0.16), 1.0, true), "Tail": tail_mat, "Lens": lens_mat, "Amber": amber}
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
		spot.spot_attenuation = 0.5      # a broad even pool rather than a hot spot under the bumper
		spot.light_energy = 5.0
		spot.light_color = Color(1.0, 0.96, 0.85)
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
		# the lamps are modelled open; closing turns them back about their rear hinge
		popups[i].rotation.x = -_popup_close[i] * (1.0 - open)
	for h in headlights:
		h.visible = open > 0.6
		h.light_energy = 5.0 * open
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
	mat.albedo_color = Color(0.8, 0.83, 0.95)
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.34, 0.36, 0.44)
	var swell := Curve.new()
	swell.add_point(Vector2(0.0, 0.25))
	swell.add_point(Vector2(0.3, 1.0))
	swell.add_point(Vector2(1.0, 0.0))
	for i in [2, 3]:
		var p := CPUParticles3D.new()
		p.mesh = puff
		p.material_override = mat
		p.amount = 8
		p.lifetime = 0.6
		p.local_coords = false
		p.emitting = false
		p.direction = Vector3(0, 0.5, 1)
		p.spread = 28.0
		p.initial_velocity_min = 1.2
		p.initial_velocity_max = 3.0
		p.gravity = Vector3(0, 1.6, 0)
		p.scale_amount_min = 0.22
		p.scale_amount_max = 0.5
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
