extends Node
## Cinematic screenshots for sharing.
##   xvfb-run godot --rendering-driver opengl3 res://tools/beauty.tscn -- <out_dir>

var out_dir := "user://beauty"

# [file, course index, mode, position along course (0..1), camera, show hud]
const SHOTS := [
	["02_haruna_drift", 0, 1, 0.84, "front_low", false],
	["03_haruna_battle", 0, 1, 0.55, "chase_high", true],
	["04_haruna_city", 0, 1, 0.62, "chase_high", false],
	["05_akagi_chevrons", 2, 1, 0.35, "front_low", false],
	["06_usui_walls", 3, 1, 0.5, "chase_low", false],
	["07_irohazaka_hairpins", 4, 0, 0.45, "top", false],
	["08_myogi_red", 1, 1, 0.3, "front_low", false],
	["09_tsuchisaka_tunnel", 6, 0, -1.0, "chase_low", false],
	["10_tsubaki_dawn", 9, 2, 0.4, "front_low", false],
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1920, 1080)
	await _menu_shot()
	for s in SHOTS:
		await _shot(s)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _menu_shot() -> void:
	Game.course_index = 0
	var menu := Menu.new()
	add_child(menu)
	menu.bd_s = 2900.0
	await _frames(90)
	await _save("01_title_screen")
	menu.queue_free()
	await _frames(2)


func _shot(spec: Array) -> void:
	var c: Dictionary = Courses.all()[spec[1]]
	var race := Race.new()
	race.setup(c, spec[2])
	add_child(race)
	await _frames(3)
	var tr := race.track
	var car: PlayerCar = race.car
	race.state = Race.State.RACING
	race.countdown = 0.0
	race.hud.set_center("")
	race.hud.popups.visible = false
	race.hud.visible = spec[5]
	car.control_enabled = true
	car.hold_brake = false
	car.bot = true
	# find a tight corner near the requested spot (or the first tunnel)
	var s: float
	if spec[3] < 0.0 and tr.tunnels.size() > 0:
		s = tr.S[int((tr.tunnels[0][0] + tr.tunnels[0][1]) / 2)]
	else:
		s = tr.length * spec[3]
		while absf(tr.curvature_at(s)) < 1.0 / 40.0 and s < tr.length - 80.0:
			s += 2.0
		s -= 4.0
	var k := tr.curvature_at(s + 6.0)
	var dir := signf(k) if absf(k) > 0.001 else 1.0
	var lat := -dir * (tr.hw * 0.35)
	car.place(s, lat)
	var d := tr.dir_at(s)
	car.vel = Vector2(d.x, d.z) * 17.0
	var drifting: bool = spec[4] != "top" and spec[3] >= 0.0
	if drifting:
		car._start_drift(dir)
		car.drift_beta = 0.5
		car.yaw = car.vel.angle() + dir * 0.5
		car.lights_on = true
	if race.rival:
		race.rival.go = true
		race.rival.s = s + 14.0
		race.rival.lat = dir * tr.hw * 0.3
		race.rival.v = 16.0
	# let the car settle into the drift for a moment
	for i in 18:
		car.bot_throttle = 1.0
		car.bot_steer = dir * 0.45 if drifting else 0.0
		await get_tree().physics_frame
	# freeze the moment so the camera framing holds while it renders
	race.set_physics_process(false)
	var cam := Camera3D.new()
	race.add_child(cam)
	cam.far = 20000.0
	var b := car.global_transform.basis
	var p := car.global_position
	var fwd := -b.z
	var right := b.x
	match spec[4]:
		"front_low":
			cam.global_position = p + fwd * 6.5 - right * dir * 3.2 + Vector3.UP * 0.7
			cam.look_at(p + Vector3.UP * 0.6 - fwd * 1.0, Vector3.UP)
			cam.fov = 48.0
		"chase_high":
			cam.global_position = p - fwd * 9.0 + Vector3.UP * 4.0
			cam.look_at(p + fwd * 12.0, Vector3.UP)
			cam.fov = 60.0
		"chase_low":
			cam.global_position = p - fwd * 6.0 + right * 1.2 + Vector3.UP * 1.1
			cam.look_at(p + fwd * 8.0 + Vector3.UP * 0.8, Vector3.UP)
			cam.fov = 62.0
		"side":
			cam.global_position = p + right * dir * 7.0 + Vector3.UP * 1.4 + fwd * 1.5
			cam.look_at(p + Vector3.UP * 0.6, Vector3.UP)
			cam.fov = 45.0
		"side_far":
			cam.global_position = p + right * dir * 14.0 - fwd * 6.0 + Vector3.UP * 6.0
			cam.look_at(p + fwd * 30.0 - right * dir * 20.0 + Vector3.DOWN * 25.0, Vector3.UP)
			cam.fov = 58.0
		"top":
			cam.global_position = p + Vector3.UP * 55.0 - fwd * 25.0 + right * 20.0
			cam.look_at(p + fwd * 15.0, Vector3.UP)
			cam.fov = 55.0
	cam.current = true
	if spec[5]:
		race.cam.current = true
		race.cam.snap()
	await _frames(6)
	await _save(spec[0])
	race.queue_free()
	await _frames(3)
