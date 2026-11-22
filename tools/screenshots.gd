extends Node
## Renders preview screenshots: xvfb-run godot --rendering-driver opengl3 res://tools/screenshots.tscn -- <course_index> <outdir>

var out_dir := "user://shots"
var course_idx := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		course_idx = int(args[0])
	if args.size() > 1:
		out_dir = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(1280, 720)
	await _run()
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _shoot_at(race: Race, at_s: float, name: String, drift: bool) -> void:
	var car: PlayerCar = race.car
	var tr := race.track
	# find the next proper corner after at_s and stop just before it
	var s := at_s
	while absf(tr.curvature_at(s)) < 1.0 / 35.0 and s < tr.length - 50.0:
		s += 2.0
	s -= 14.0
	car.place(s, 0.0)
	var d := tr.dir_at(s)
	var spd := 13.0
	car.vel = Vector2(d.x, d.z) * spd
	car.bot_throttle = 0.4
	car.bot_steer = 0.0
	if drift:
		var k := tr.curvature_at(s + 14.0)
		car.yaw += signf(k) * 0.5
		car.drifting = true
		car.bot_steer = -signf(k) * 0.3
		car.bot_throttle = 1.0
	if race.rival:
		race.rival.s = s + 22.0
		race.rival.v = spd
	race.cam.snap()
	await _frames(25)
	await _save(name)
	car.bot_handbrake = false


func _run() -> void:
	# 1. menu
	Game.course_index = course_idx
	var menu := Menu.new()
	add_child(menu)
	await _frames(40)
	await _save("01_menu")
	menu.queue_free()

	# 2. battle start grid
	var c: Dictionary = Courses.all()[course_idx]
	var race := Race.new()
	race.setup(c, Game.Mode.BATTLE)
	add_child(race)
	await _frames(20)
	await _save("02_start")

	# 3+. teleport to interesting spots (software rendering is too slow to drive there)
	var car: PlayerCar = race.car
	car.bot = true
	race.countdown = 0.6
	await _frames(3)
	race.hud.set_center("")
	race.hud.popups.visible = false   # teleporting between spots trips the crash/score popups
	var L: float = race.track.length
	var spots := [[L * 0.07, "03_lakeside", false], [L * 0.2, "04_switchbacks", false],
		[L * 0.42, "05_drift", true], [L * 0.88, "06_final_hairpins", false], [L * 0.95, "15_ikaho", false]]
	for spot in spots:
		await _shoot_at(race, spot[0], spot[1], spot[2])
	# city view: a stretch heading straight for the valley
	var tr := race.track
	var away := Vector3(tr.P[tr.P.size() - 1].x - tr.P[0].x, 0, tr.P[tr.P.size() - 1].z - tr.P[0].z).normalized()
	var best_i := 0
	var best_d := -2.0
	for i in range(200, tr.P.size() - 200, 5):
		var dd := tr.D[i].dot(away) - absf(tr.K[i]) * 30.0
		if dd > best_d:
			best_d = dd
			best_i = i
	await _shoot_at(race, tr.S[best_i] - 40.0, "11_city_view", false)
	# rock-fall protection on the cut slopes
	for spot in [[L * 0.28, -1.0, "13_rockfall_a"], [L * 0.65, 1.0, "14_rockfall_b"]]:
		var si := tr.index_at_s(spot[0])
		var sd: float = spot[1]
		var ccam := Camera3D.new()
		race.add_child(ccam)
		ccam.global_position = tr.P[si] - tr.R[si] * sd * 2.5 - tr.D[si] * 14.0 + Vector3.UP * 2.0
		ccam.look_at(tr.P[si] + tr.R[si] * sd * 9.0 + tr.D[si] * 10.0 + Vector3.UP * 4.0, Vector3.UP)
		ccam.current = true
		await _frames(4)
		await _save(spot[2])
		ccam.queue_free()
	race.cam.current = true
	# debug: high view toward the valley
	var dc := Camera3D.new()
	race.add_child(dc)
	dc.far = 12000.0
	var mid := tr.P[tr.P.size() / 2]
	dc.global_position = mid + Vector3.UP * 40.0 - away * 50.0
	dc.look_at(mid + away * 3000.0 + Vector3.DOWN * 300.0, Vector3.UP)
	dc.current = true
	await _frames(4)
	await _save("12_valley_debug")
	race.cam.current = true
	# 8. car close-ups
	race.hud.visible = false
	car.place(80.0, 0.0)
	car.vel = Vector2.ZERO
	car.bot_throttle = 0.0
	car.bot_brake = 1.0
	if race.rival:
		race.rival.s = 400.0
	await _frames(3)
	for ch in race.get_children():
		if ch is WorldEnvironment:
			ch.environment.ambient_light_energy = 2.5
	var cc := Camera3D.new()
	race.add_child(cc)
	var b := car.global_transform.basis
	var cp := car.global_position
	for view in [["08_car_front", -b.z * 4.2 + b.x * 3.0 + Vector3.UP * 1.3], ["09_car_side", b.x * 5.5 - b.z * 0.4 + Vector3.UP * 1.0],
			["10_car_rear", b.z * 4.4 - b.x * 2.6 + Vector3.UP * 1.6]]:
		cc.global_position = cp + view[1]
		cc.look_at(cp + Vector3.UP * 0.6, Vector3.UP)
		cc.fov = 50.0
		cc.current = true
		await _frames(4)
		await _save(view[0])
	race.hud.visible = true
	# 7. overhead view of the whole course
	var cam := Camera3D.new()
	race.add_child(cam)
	var mn := Vector3(INF, INF, INF)
	var mx := -mn
	for p in race.track.P:
		mn = mn.min(p)
		mx = mx.max(p)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(mx.x - mn.x, (mx.z - mn.z) * 16.0 / 9.0) * 1.05 * 9.0 / 16.0
	cam.size = maxf(mx.z - mn.z, (mx.x - mn.x) * 9.0 / 16.0) * 1.08
	cam.far = 5000.0
	cam.position = Vector3((mn.x + mx.x) * 0.5, mx.y + 1500.0, (mn.z + mx.z) * 0.5)
	cam.rotation = Vector3(-PI / 2, 0, 0)
	cam.current = true
	race.hud.visible = false
	for ch in race.get_children():
		if ch is WorldEnvironment:
			ch.environment.fog_enabled = false
			ch.environment.ambient_light_energy = 1.5
	await _frames(5)
	await _save("07_overhead")
	race.hud.visible = true
