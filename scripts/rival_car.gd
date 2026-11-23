class_name RivalCar
extends Node3D
## AI rival: follows a precomputed speed profile along an inside racing line
## and throws the car sideways through the tight stuff.

var track: Track
var model: CarModel
var profile: PackedFloat32Array
var info: Dictionary
var s := 0.0
var lat := 0.0
var v := 0.0
var go := false
var finished := false
var finish_time := 0.0
var rattled := 0.0      # >0 while spooked by a lights-off chaser
var _yaw_offset := 0.0
var _lights := true
var _power := 4.0
var wobble := 0.0            # >0 after being hit: off line, lifting
var _start_s := 0.0
var _start_lat := 0.0
var _lat_vel := 0.0
var player: Node3D = null    # the player's car (PlayerCar), for racecraft


func setup(t: Track, rival: Dictionary, start_s: float, start_lat: float) -> void:
	track = t
	info = rival
	model = CarModel.for_car(rival.get("car", "s13"))
	add_child(model)
	var skill: float = rival.get("skill", 1.0)
	var ph := Cars.physics(rival.get("car", "s13"))
	_power = ph.power * skill
	# like the anime: rivals are strong on the straights, and the corners are
	# where a driver who drifts and hooks the gutters can catch them
	profile = track.speed_profile(1.04 * ph.grip * skill, ph.power * 1.1 * skill)
	s = start_s
	lat = start_lat
	_start_s = start_s
	_start_lat = start_lat
	_place(0.0)


func step(dt: float, race_time: float) -> void:
	if not go:
		_place(dt)
		return
	var i := track.index_at_s(s)
	var target: float = profile[mini(i + 1, profile.size() - 1)]
	if rattled > 0.0:
		rattled -= dt
		target *= 0.93
	if wobble > 0.0:
		wobble -= dt
		target *= 0.9
	var look_k := track.curvature_at(s + 18.0 + v * 0.6)
	var give_way := false
	var launching := s - _start_s < 140.0
	if player and not finished:
		var gap: float = s - player.s          # > 0: rival ahead
		# always race close: wait when it pulls away, chase hard when dropped
		if launching:
			pass
		elif gap > 28.0:
			target *= 0.88
		elif gap > 14.0:
			target *= 0.95
		elif gap < -20.0:
			target *= 1.2
		elif gap < -4.0:
			target *= 1.1
		# a car alongside on the inside of the corner gets room: take the
		# outside line and lift, so a better drift lets the player through
		var inside: bool = signf(player.lat) == signf(look_k) and absf(player.lat) > 0.6
		if absf(gap) < 7.0 and absf(look_k) > 1.0 / 70.0 and inside:
			give_way = true
			target *= 0.95
	if finished:
		target = maxf(0.0, v - 8.0)
	var accel := clampf(_power / maxf(v, 4.0), 2.5, 6.5)
	if launching:
		accel = maxf(accel, 7.5)       # rivals always get the jump at the start
	if target <= v:
		accel = 9.0
	v = move_toward(v, target, accel * dt)
	s += v * dt
	# racing line: hold the own lane off the line, then ease onto the inside
	var want := clampf(look_k * 160.0, -1.0, 1.0) * (track.hw - 1.1)
	if launching:
		want = _start_lat
	if give_way:
		want = -signf(look_k) * (track.hw - 1.1)
	# a real car can only move across the road as fast as it can turn
	var rate := minf(2.0, 0.5 + v * 0.06)
	var prev := lat
	lat = move_toward(lat, want, rate * dt)
	_lat_vel = (lat - prev) / maxf(dt, 0.001)
	if not finished and s >= track.finish_s:
		finished = true
		finish_time = race_time
	_place(dt)


func _place(dt: float) -> void:
	s = minf(s, track.length - 1.0)
	var p := track.point_at(s, lat)
	var d := track.dir_at(s)
	var k := track.curvature_at(s)
	var lateral_g := v * v * absf(k)
	# rivals throw the car sideways through the corners like the locals do
	var drift := clampf((lateral_g - 2.5) / 7.0, 0.0, 0.7) * signf(k)
	# the nose points where the car is heading when it changes lanes
	var steer_yaw := atan2(_lat_vel, maxf(v, 3.0))
	if wobble > 0.0:
		steer_yaw += sin(wobble * 18.0) * 0.12
	var want_yaw := drift - steer_yaw
	_yaw_offset = lerpf(_yaw_offset, want_yaw, 1.0 - exp(-5.0 * dt)) if dt > 0.0 else want_yaw
	var basis := Basis.looking_at(d, Vector3.UP).rotated(Vector3.UP, -_yaw_offset)
	var ahead := track.point_at(s + 1.2, lat).y
	var behind := track.point_at(maxf(0.0, s - 1.2), lat).y
	basis = basis.rotated(basis.x, atan2(ahead - behind, 2.4))
	transform = Transform3D(basis, p)
	model.update_visual(dt, -_yaw_offset * 0.6, v, v > 5.0 and dt > 0.0 and v - profile[mini(track.index_at_s(s) + 4, profile.size() - 1)] > 1.0)


func set_lights(on: bool) -> void:
	if on != _lights:
		_lights = on
		model.set_lights(on)
