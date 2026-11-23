class_name PlayerCar
extends Node3D
## Arcade drift physics for a light rear-drive hatchback, driven entirely in
## track space (no physics engine) so it is stable at any frame rate.
##
## Techniques:
##  * Handbrake drift   – Space while turning.
##  * Inertia drift     – flick the steering one way, then hard the other way.
##  * Brake drift       – brake hard while turning in at speed.
##  * Gutter hook       – put the inside wheels in the drainage gutter of a
##                        hairpin; the ditch holds the car like a rail.
##  * Blind attack      – headlights off at night doubles drift points.

signal popup(text: String, color: Color)
signal crashed(impact: float)

const G := 9.81
const WHEELBASE := 2.4
# per-car physics (set from Cars.physics in setup)
var car_id := "ae85"
var power := 80.0            # W/kg at the wheels
var traction := 5.6          # m/s^2 max drive accel
var grip := 1.0              # cornering grip multiplier
var drift_g := 1.0           # how hard the car can swing round in a drift
var drift_angle := 1.0       # how much angle it holds
var drag := 0.00045
const BRAKE := 10.0
const GEARS := [3.587, 2.022, 1.384, 1.0, 0.861]
const FINAL := 4.3

var track: Track
var model: CarModel
var control_enabled := false
var hold_brake := true

var pos := Vector3.ZERO
var vel := Vector2.ZERO          # horizontal velocity (x, z)
var yaw := 0.0                   # forward = (cos yaw, 0, sin yaw)
var yaw_rate := 0.0
var steer := 0.0
var throttle := 0.0
var brake := 0.0
var handbrake := false
var speed := 0.0
var slip := 0.0
var drifting := false
var gear := 1
var rpm := 900.0
var idx := 0
var s := 0.0
var lat := 0.0
var in_gutter := false
var lights_on := true
var accel := Vector2.ZERO        # in car frame (x = lateral, y = longitudinal)
var wrong_way := false

# scoring
var score := 0
var combo := 0.0
var combo_mult := 1.0
var drift_time := 0.0
var grip_time := 0.0
var gutter_time := 0.0
var last_gutter_s := -999.0
var blind := false

# water cup (smoothness)
var cup := 100.0
var slosh := Vector2.ZERO
var slosh_v := Vector2.ZERO

var _steer_hist: Array = []      # [time, sign] of strong steering inputs
var drift_dir := 0.0             # +1 drifting through a right-hander, -1 left
var drift_beta := 0.0            # current body angle to the direction of travel
var _drift_exit := false
var _brake_down_at := -10.0
var _brake_up_at := -10.0
var _was_braking := false
var _idle_time := 0.0
var _clock := 0.0
var _exit_timer := 0.0
var _prev_vel := Vector2.ZERO
var _roll := 0.0
var _pitch := 0.0
var _lights_pressed := false

# test/autopilot hook: when `bot` is true, inputs come from these fields
var bot := false
var bot_steer := 0.0
var bot_throttle := 0.0
var bot_brake := 0.0
var bot_handbrake := false


func setup(t: Track, start_s: float, start_lat: float, id := "") -> void:
	var game: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")
	car_id = id if id != "" else (game.selected_car if game else "ae86")
	var ph := Cars.physics(car_id)
	power = ph.power
	traction = ph.traction
	grip = ph.grip
	drift_g = ph.drift_g
	drift_angle = ph.drift_angle
	drag = ph.drag
	track = t
	model = CarModel.for_car(car_id)
	add_child(model)
	place(start_s, start_lat)


func place(at_s: float, at_lat: float) -> void:
	idx = track.index_at_s(at_s)
	pos = track.point_at(at_s, at_lat)
	var d := track.dir_at(at_s)
	yaw = atan2(d.z, d.x)
	vel = Vector2.ZERO
	yaw_rate = 0.0
	drifting = false
	s = at_s
	lat = at_lat
	_prev_vel = Vector2.ZERO
	_update_transform(0.0)


func forward2() -> Vector2:
	return Vector2(cos(yaw), sin(yaw))


func _read_input() -> void:
	if not control_enabled:
		throttle = 0.0
		brake = 1.0 if hold_brake else 0.0
		handbrake = false
		return
	if bot:
		throttle = bot_throttle
		brake = bot_brake
		handbrake = bot_handbrake
		return
	throttle = Input.get_action_strength("throttle")
	brake = Input.get_action_strength("brake")
	handbrake = Input.is_action_pressed("handbrake")
	var lights_now := Input.is_action_pressed("lights")
	if lights_now and not _lights_pressed:
		lights_on = not lights_on
		model.set_lights(lights_on)
	_lights_pressed = lights_now


func physics_step(dt: float) -> void:
	_clock += dt
	_read_input()
	var target_steer := 0.0
	if control_enabled:
		if bot:
			target_steer = bot_steer
		else:
			target_steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var rate := 5.0 if absf(target_steer) > absf(steer) else 7.0
	steer = move_toward(steer, target_steer, rate * dt)

	var fwd := forward2()
	var right := Vector2(-fwd.y, fwd.x)
	speed = vel.length()
	var v_long := vel.dot(fwd)
	var v_lat := vel.dot(right)
	slip = atan2(v_lat, absf(v_long)) if speed > 2.0 else 0.0

	# --- track surface
	var curv := track.K[idx]
	var inner := signf(curv)
	var inner_wheel_lat := lat + inner * 0.72
	in_gutter = absf(curv) > 1.0 / 90.0 and absf(inner_wheel_lat) > track.hw + 0.08 \
		and signf(lat) == inner and speed > 6.0
	var mu := grip
	if in_gutter:
		mu = 1.8
		gutter_time += dt
		if gutter_time > 0.35 and s - last_gutter_s > 50.0 and speed > 12.0:
			last_gutter_s = s
			_award("GUTTER HOOK", 300, Color(0.3, 0.9, 1.0))
	else:
		gutter_time = 0.0

	# --- drift entry: only on purpose (no surprise slides)
	var braking_now := brake > 0.5
	if braking_now and not _was_braking:
		_brake_down_at = _clock
	if not braking_now and _was_braking:
		_brake_up_at = _clock
	_was_braking = braking_now
	_detect_inertia_drift(target_steer)
	if not drifting and speed > 9.0 and absf(target_steer) > 0.35:
		if handbrake:
			_start_drift(signf(target_steer))
		else:
			# brake tap: a short stab of brake, then turn in hard
			var tapped := _brake_up_at - _brake_down_at < 0.4 and _clock - _brake_up_at < 0.55
			if tapped and absf(target_steer) > 0.6 and speed > 13.0:
				_start_drift(signf(target_steer))

	# --- yaw
	var max_steer := lerpf(0.62, 0.17, clampf(speed / 42.0, 0.0, 1.0))
	if not drifting:
		var r_t := v_long * tan(steer * max_steer) / WHEELBASE
		var r_max := mu * G / maxf(speed, 1.0)
		r_t = clampf(r_t, -r_max, r_max)
		yaw_rate = lerpf(yaw_rate, r_t, 1.0 - exp(-10.0 * dt))
	else:
		yaw_rate = 0.0
	yaw = wrapf(yaw + yaw_rate * dt, -PI, PI)
	fwd = forward2()

	# --- assisted drift: the game holds the angle, you steer the line
	if drifting:
		var into := clampf(target_steer * drift_dir, 0.0, 1.0)
		var counter := clampf(-target_steer * drift_dir, 0.0, 1.0)
		var beta_t := (0.32 + 0.3 * into - 0.28 * counter + 0.12 * throttle) * lerpf(0.75, 1.0, drift_angle)
		if _drift_exit:
			beta_t = 0.0
		drift_beta = move_toward(drift_beta, beta_t, dt * (1.6 if _drift_exit else 1.2))
		# how hard the travel direction swings round the corner
		var lat_g := G * drift_g * (0.55 + 0.5 * into - 0.35 * counter) * (1.6 if in_gutter else 1.0)
		var omega := drift_dir * lat_g / maxf(speed, 6.0)
		# follow the road a little so a held drift carries you round the bend
		var road_omega := speed * curv
		omega = lerpf(omega, road_omega, 0.6)
		# keep off the guard rails: ease the line back toward the road
		var edge := clampf((absf(lat) - (track.hw - 1.4)) / 1.6, 0.0, 1.0)
		omega -= signf(lat) * edge * 0.9
		vel = vel.rotated(omega * dt)
		var travel := vel.angle()
		var want_yaw := travel + drift_dir * drift_beta
		var dyaw := wrapf(want_yaw - yaw, -PI, PI)
		yaw_rate = dyaw * 8.0
		yaw = wrapf(yaw + dyaw * minf(1.0, 8.0 * dt), -PI, PI)
		fwd = forward2()
		# finishing the drift: counter-steer, or let go of steering and throttle
		if counter > 0.6 or (into < 0.1 and throttle < 0.2):
			_idle_time += dt
		else:
			_idle_time = 0.0
		if _idle_time > 0.35 or speed < 7.0:
			_drift_exit = true
		if _drift_exit and drift_beta < 0.04:
			drifting = false
			_drift_exit = false
			yaw = travel
			fwd = forward2()
	# --- velocity direction follows heading, limited by tyre grip
	if speed > 0.3 and not drifting:
		var travel_ang := vel.angle()
		var target_ang := yaw if vel.dot(fwd) >= 0.0 else yaw + PI
		var diff := wrapf(target_ang - travel_ang, -PI, PI)
		var mu_lat := mu * (1.0 if drifting else 1.08)
		if handbrake:
			mu_lat *= 0.75
		var max_rot := mu_lat * G / maxf(speed, 2.0) * dt
		vel = vel.rotated(clampf(diff, -max_rot, max_rot))

	# --- longitudinal
	speed = vel.length()
	var dir := vel / speed if speed > 0.01 else fwd
	v_long = vel.dot(fwd)
	var a_drive := 0.0
	if throttle > 0.0:
		a_drive = throttle * minf(traction, power / maxf(speed, 4.0))
		if drifting:
			a_drive *= 0.9
	var a_resist := drag * speed * speed + 0.12
	if brake > 0.0 and v_long > 0.5:
		a_resist += BRAKE * brake
	elif brake > 0.0 and control_enabled:
		# reverse
		if v_long > -7.0:
			vel -= fwd * 4.0 * brake * dt
	elif brake > 0.0:
		vel = vel.move_toward(Vector2.ZERO, BRAKE * dt)
	if handbrake:
		a_resist += 2.5
	if drifting:
		a_resist += absf(sin(drift_beta)) * speed * 0.05
	vel += fwd * a_drive * dt
	var dv := minf(a_resist * dt, speed)
	vel -= dir * dv
	# gravity along the slope
	var tdir := Vector2(track.D[idx].x, track.D[idx].z)
	vel += tdir * (-G * track.G[idx]) * dt
	if not control_enabled and hold_brake:
		vel = Vector2.ZERO

	# --- move & collide with guardrails
	pos.x += vel.x * dt
	pos.z += vel.y * dt
	var proj := track.project(pos, idx)
	idx = proj.i
	s = proj.s
	lat = proj.lat
	var limit := track.rail - 0.9
	if absf(lat) > limit:
		var side := signf(lat)
		var r3: Vector3 = proj.right
		var push := absf(lat) - limit
		pos -= r3 * side * push
		lat = side * limit
		var n2 := Vector2(r3.x, r3.z) * side
		var v_out := vel.dot(n2)
		if v_out > 0.0:
			vel -= n2 * v_out * 1.25
			vel *= 1.0 - clampf(v_out * 0.02, 0.0, 0.25)
			yaw_rate *= 0.5
			if v_out > 2.0:
				_crash(v_out)
		vel *= 1.0 - 0.5 * dt   # scraping along the rail
	pos.y = track.surface_height(proj)

	# --- engine
	var wheel_rpm := speed / (TAU * CarModel.WHEEL_R) * 60.0
	rpm = wheel_rpm * GEARS[gear - 1] * FINAL * (1.0 + (absf(slip) * 0.6 if drifting else 0.0))
	if rpm > 7300.0 and gear < 5:
		gear += 1
	elif rpm < 3200.0 and gear > 1:
		gear -= 1
	rpm = clampf(maxf(rpm, 900.0 + throttle * 2500.0 * (1.0 if speed < 3.0 else 0.0)), 900.0, 7800.0)

	# --- acceleration (car frame) for cup + body roll
	var a_world := (vel - _prev_vel) / dt
	_prev_vel = vel
	var a_car := Vector2(a_world.dot(Vector2(-fwd.y, fwd.x)), a_world.dot(fwd))
	accel = accel.lerp(a_car, 1.0 - exp(-12.0 * dt))
	_update_cup(dt)
	_update_score(dt)
	var tdir3: Vector3 = proj.dir
	wrong_way = speed > 5.0 and Vector2(tdir3.x, tdir3.z).dot(vel) < -0.5 * speed
	_update_transform(dt)


func _detect_inertia_drift(target_steer: float) -> void:
	if absf(target_steer) < 0.7:
		return
	var sg := signf(target_steer)
	if _steer_hist.is_empty() or _steer_hist[-1][1] != sg:
		_steer_hist.append([_clock, sg])
		if _steer_hist.size() > 3:
			_steer_hist.pop_front()
		if _steer_hist.size() >= 2:
			var prev: Array = _steer_hist[-2]
			if _clock - prev[0] < 0.45 and prev[1] == -sg and speed > 15.0 and not drifting:
				_start_drift(sg)
				_award("INERTIA DRIFT", 250, Color(1.0, 0.8, 0.2))


func _start_drift(dir: float) -> void:
	if dir == 0.0:
		return
	drifting = true
	drift_dir = dir
	drift_beta = 0.08
	_drift_exit = false
	_idle_time = 0.0
	drift_time = 0.0


func _update_score(dt: float) -> void:
	blind = not lights_on and track.course.get("time", "night") == "night" and speed > 15.0
	var mult := 2.0 if blind else 1.0
	if drifting and speed > 10.0 and absf(slip) > 0.12 and absf(slip) < 1.45:
		drift_time += dt
		grip_time = 0.0
		combo_mult = 1.0 + floorf(drift_time / 2.0) * 0.5
		combo += rad_to_deg(absf(slip)) * speed * dt * 0.12 * mult * combo_mult
	else:
		grip_time += dt
		if grip_time > 1.2 and combo > 0.0:
			var pts := int(combo)
			if pts >= 50:
				score += pts
				popup.emit("DRIFT +%d" % pts, Color(1.0, 0.45, 0.85))
			combo = 0.0
			drift_time = 0.0
			combo_mult = 1.0


func _award(text: String, pts: int, color: Color) -> void:
	var mult := 2 if blind else 1
	score += pts * mult
	popup.emit("%s +%d" % [text, pts * mult], color)


func _crash(impact: float) -> void:
	if combo > 0.0:
		popup.emit("COMBO LOST", Color(1.0, 0.3, 0.2))
	combo = 0.0
	drift_time = 0.0
	cup -= impact * 2.5
	crashed.emit(impact)


func _update_cup(dt: float) -> void:
	# water surface is a damped spring driven by the car's acceleration;
	# smooth inputs keep it calm, jerky inputs make it slosh over the rim
	var k := 40.0
	var c := 2.5
	slosh_v += (-accel - slosh * k - slosh_v * c) * dt
	slosh += slosh_v * dt
	var amp := slosh.length()
	if amp > 0.3 and cup > 0.0:
		cup = maxf(0.0, cup - (amp - 0.3) * 70.0 * dt)
	cup = maxf(cup, 0.0)


func _update_transform(dt: float) -> void:
	var fwd := forward2()
	var f3 := Vector3(fwd.x, 0, fwd.y)
	var r3 := f3.cross(Vector3.UP)
	var hf := track.height_at(pos + f3 * 1.2, idx)
	var hb := track.height_at(pos - f3 * 1.2, idx)
	var hl := track.height_at(pos - r3 * 0.7, idx)
	var hr := track.height_at(pos + r3 * 0.7, idx)
	var pitch := atan2(hf - hb, 2.4)
	var roll := atan2(hr - hl, 1.4)
	var body_roll := clampf(accel.x * 0.006, -0.08, 0.08)
	var k := 1.0 - exp(-14.0 * dt) if dt > 0.0 else 1.0
	_pitch = lerpf(_pitch, pitch - clampf(accel.y * 0.004, -0.05, 0.05), k)
	_roll = lerpf(_roll, roll, k)
	var basis := Basis.looking_at(f3, Vector3.UP)
	basis = basis.rotated(r3, _pitch).rotated(f3, -_roll)
	transform = Transform3D(basis, Vector3(pos.x, (hf + hb + hl + hr) * 0.25, pos.z))
	model.body.rotation.z = body_roll
	model.update_visual(dt, steer * lerpf(0.62, 0.17, clampf(speed / 42.0, 0.0, 1.0)) + (-slip * 0.5 if drifting else 0.0),
		vel.dot(fwd), brake > 0.1 and control_enabled)
