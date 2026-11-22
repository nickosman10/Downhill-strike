class_name ChaseCamera
extends Camera3D
## Chase cam that swings with the car's travel direction so drift angle reads
## on screen. Modes: chase, far chase, bumper.

var car: PlayerCar
var mode := 0
var _look := Vector3.ZERO
var _dir := Vector3.FORWARD


func snap() -> void:
	var f := Vector3(cos(car.yaw), 0, sin(car.yaw))
	_dir = f
	global_position = car.global_position - f * 6.5 + Vector3.UP * 2.4
	_look = car.global_position + Vector3.UP * 0.9
	look_at(_look + f * 3.0, Vector3.UP)


func cycle() -> void:
	mode = (mode + 1) % 3
	snap()


func follow(dt: float) -> void:
	var f := Vector3(cos(car.yaw), 0, sin(car.yaw))
	var vdir := Vector3(car.vel.x, 0, car.vel.y)
	var target_dir := f
	if car.speed > 3.0:
		target_dir = f.lerp(vdir.normalized(), 0.55).normalized()
	_dir = _dir.slerp(target_dir, 1.0 - exp(-5.0 * dt)).normalized()
	var cp := car.global_position
	match mode:
		0, 1:
			var dist := 6.5 if mode == 0 else 9.5
			var height := 2.3 if mode == 0 else 3.4
			var want := cp - _dir * dist + Vector3.UP * height
			global_position = global_position.lerp(want, 1.0 - exp(-9.0 * dt))
			_look = _look.lerp(cp + Vector3.UP * 0.9 + _dir * 2.0, 1.0 - exp(-14.0 * dt))
			look_at(_look, Vector3.UP)
			fov = lerpf(fov, 68.0 + clampf(car.speed * 0.35, 0.0, 16.0), 1.0 - exp(-3.0 * dt))
		2:
			var b := car.global_transform.basis
			global_position = cp + b.y * 1.05 - b.z * 0.3
			look_at(global_position - b.z * 10.0 + b.y * 0.2, b.y)
			fov = 78.0
