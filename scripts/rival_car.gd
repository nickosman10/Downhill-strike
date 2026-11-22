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


func setup(t: Track, rival: Dictionary, start_s: float, start_lat: float) -> void:
	track = t
	info = rival
	model = CarModel.create(rival.get("car", "coupe"), rival.get("color", Color.RED),
		rival.get("color", Color.RED).darkened(0.35))
	add_child(model)
	var skill: float = rival.get("skill", 1.0)
	profile = track.speed_profile(0.9 * skill, 66.0 * skill)
	s = start_s
	lat = start_lat
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
	if finished:
		target = maxf(0.0, v - 8.0)
	var accel := 5.0 if target > v else -9.0
	v = move_toward(v, target, absf(accel) * dt)
	s += v * dt
	# inside line: look ahead for the next corner
	var look_k := track.curvature_at(s + 18.0 + v * 0.6)
	var want := clampf(look_k * 160.0, -1.0, 1.0) * (track.hw - 1.1)
	lat = move_toward(lat, want, dt * 2.2)
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
	var drift := clampf((lateral_g - 5.0) / 10.0, 0.0, 0.5) * signf(k)
	_yaw_offset = lerpf(_yaw_offset, drift, 1.0 - exp(-4.0 * dt)) if dt > 0.0 else drift
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
