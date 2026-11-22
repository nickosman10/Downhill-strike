class_name Race
extends Node3D
## One downhill run: builds the world, runs the countdown, rules and results.

signal exit_to_menu
signal restart

enum State { COUNTDOWN, RACING, FINISHED }

var course: Dictionary
var mode: int
var track: Track
var car: PlayerCar
var rival: RivalCar
var cam: ChaseCamera
var hud: Hud
var audio: EngineAudio
var state := State.COUNTDOWN
var countdown := 3.5
var race_time := 0.0
var _rattle_cooldown := 0.0
var _last_count := -1


func setup(c: Dictionary, m: int) -> void:
	course = c
	mode = m


func _ready() -> void:
	var dawn := mode == Game.Mode.DAWN_DELIVERY
	_build_environment(dawn)
	track = Track.new()
	add_child(track)
	track.build(course)

	car = PlayerCar.new()
	add_child(car)
	var battle := mode == Game.Mode.BATTLE
	car.setup(track, track.start_s - 6.0, -track.hw * 0.45 if battle else 0.0)
	car.popup.connect(_on_popup)
	car.crashed.connect(_on_crash)
	if dawn:
		car.lights_on = true

	if battle:
		rival = RivalCar.new()
		add_child(rival)
		rival.setup(track, course.rival, track.start_s - 6.0, track.hw * 0.45)

	cam = ChaseCamera.new()
	cam.car = car
	cam.far = 900.0
	add_child(cam)
	cam.current = true
	cam.snap()

	hud = Hud.new()
	add_child(hud)
	hud.build(self)
	hud.cup.visible = dawn or mode == Game.Mode.TIME_ATTACK

	audio = EngineAudio.new()
	audio.car = car
	add_child(audio)


func _build_environment(dawn: bool) -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	var light := DirectionalLight3D.new()
	if dawn:
		sky_mat.sky_top_color = Color(0.32, 0.42, 0.65)
		sky_mat.sky_horizon_color = Color(0.98, 0.62, 0.4)
		sky_mat.ground_horizon_color = Color(0.55, 0.42, 0.38)
		sky_mat.ground_bottom_color = Color(0.1, 0.1, 0.12)
		env.ambient_light_color = Color(0.75, 0.62, 0.6)
		env.ambient_light_energy = 0.6
		env.fog_light_color = Color(0.85, 0.62, 0.55)
		env.fog_density = 0.004
		light.light_color = Color(1.0, 0.78, 0.55)
		light.light_energy = 1.0
		light.rotation = Vector3(deg_to_rad(-14.0), deg_to_rad(40.0), 0)
	else:
		sky_mat.sky_top_color = Color(0.01, 0.015, 0.04)
		sky_mat.sky_horizon_color = Color(0.05, 0.06, 0.12)
		sky_mat.ground_horizon_color = Color(0.03, 0.035, 0.06)
		sky_mat.ground_bottom_color = Color(0.0, 0.0, 0.0)
		env.ambient_light_color = Color(0.35, 0.4, 0.6)
		env.ambient_light_energy = 0.35
		env.fog_light_color = Color(0.03, 0.04, 0.08)
		env.fog_density = 0.012
		light.light_color = Color(0.55, 0.62, 0.9)
		light.light_energy = 0.22
		light.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	add_child(light)


func _physics_process(dt: float) -> void:
	match state:
		State.COUNTDOWN:
			countdown -= dt
			var n := ceili(countdown - 0.5)
			if n != _last_count:
				_last_count = n
				if n > 0 and n <= 3:
					hud.set_center(str(n), Color(1, 0.85, 0.3))
				elif n <= 0:
					hud.set_center("GO!", Color(0.4, 1, 0.4))
			if countdown <= 0.5:
				state = State.RACING
				car.control_enabled = true
				car.hold_brake = false
				if rival:
					rival.go = true
				get_tree().create_timer(0.8).timeout.connect(func(): if state == State.RACING: hud.set_center(""))
		State.RACING:
			race_time += dt
		State.FINISHED:
			car.control_enabled = false
			car.hold_brake = false
	car.physics_step(dt)
	if rival:
		rival.step(dt, race_time)
		_resolve_contact()
		_blind_attack(dt)
	if state == State.RACING:
		_check_finish()


func _process(dt: float) -> void:
	cam.follow(dt)
	hud.update_hud(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera"):
		cam.cycle()
	elif event.is_action_pressed("pause_menu"):
		exit_to_menu.emit()
	elif event.is_action_pressed("reset_car"):
		if state == State.FINISHED:
			restart.emit()
		elif state == State.RACING:
			car.place(car.s, 0.0)
			hud.show_popup("RESET", Color(0.8, 0.8, 0.8))
	elif event.is_action_pressed("confirm") and state == State.FINISHED:
		exit_to_menu.emit()


func _resolve_contact() -> void:
	var ds := car.s - rival.s
	var dl := car.lat - rival.lat
	var pen_s := 4.3 - absf(ds)
	var pen_l := 1.75 - absf(dl)
	if pen_s <= 0.0 or pen_l <= 0.0:
		return
	var d3 := track.dir_at(car.s)
	var r3 := d3.cross(Vector3.UP)
	if pen_l < pen_s:
		car.pos += r3 * signf(dl if dl != 0.0 else 1.0) * pen_l
		var n2 := Vector2(r3.x, r3.z) * signf(dl if dl != 0.0 else 1.0)
		var vn := car.vel.dot(n2)
		if vn < 0.0:
			car.vel -= n2 * vn * 1.3
	else:
		car.pos += d3 * signf(ds if ds != 0.0 else -1.0) * pen_s
		if ds < 0.0:
			var d2 := Vector2(d3.x, d3.z)
			var excess := car.vel.dot(d2) - rival.v * 0.95
			if excess > 0.0:
				car.vel -= d2 * excess
		else:
			rival.v *= 0.97
	if pen_s > 0.6 or pen_l > 0.3:
		car.combo = 0.0


func _blind_attack(dt: float) -> void:
	_rattle_cooldown -= dt
	var gap := rival.s - car.s
	if car.blind and gap > 8.0 and gap < 40.0 and _rattle_cooldown <= 0.0 and state == State.RACING:
		_rattle_cooldown = 20.0
		rival.rattled = 3.5
		hud.show_popup("%s LOST YOU IN THE DARK!" % rival.info.name.to_upper(), Color(0.7, 0.8, 1.0))


func _check_finish() -> void:
	if car.s < track.finish_s:
		return
	state = State.FINISHED
	var lines: Array[String] = []
	var title := "FINISH"
	var color := Color.WHITE
	match mode:
		Game.Mode.BATTLE:
			var won := not rival.finished
			title = "YOU WIN!" if won else "YOU LOSE"
			color = Color(0.4, 1, 0.4) if won else Color(1, 0.35, 0.3)
			lines.append("vs %s" % rival.info.name)
			if won:
				var margin := (track.finish_s - rival.s) / maxf(rival.v, 1.0)
				lines.append("Won by about %.2f s" % margin)
			else:
				lines.append("Lost by %.2f s" % (race_time - rival.finish_time))
		Game.Mode.DAWN_DELIVERY:
			var ok := car.cup >= 50.0
			title = "DELIVERED!" if ok else "SPILLED IT"
			color = Color(0.4, 1, 0.4) if ok else Color(1, 0.35, 0.3)
			lines.append("Water left: %d%%  (need 50%%)" % int(car.cup))
		_:
			title = "FINISH"
	lines.append("Time  %s" % Game.format_time(race_time))
	var valid := mode != Game.Mode.DAWN_DELIVERY or car.cup >= 50.0
	if valid and Game.submit_time(course.id, mode, race_time):
		lines.append("NEW COURSE RECORD!")
	else:
		var best := Game.best_time(course.id, mode)
		if best > 0.0:
			lines.append("Best  %s" % Game.format_time(best))
	var final_score := car.score + int(car.combo)
	lines.append("Drift score  %d" % final_score)
	if Game.submit_score(course.id, final_score):
		lines.append("NEW BEST SCORE!")
	lines.append("")
	lines.append("[R] Retry      [Enter] Menu")
	hud.set_center(title, color)
	hud.show_result("\n".join(lines))


func _on_popup(text: String, color: Color) -> void:
	hud.show_popup(text, color)


func _on_crash(impact: float) -> void:
	if impact > 7.0:
		hud.show_popup("CRASH!", Color(1.0, 0.35, 0.2))
