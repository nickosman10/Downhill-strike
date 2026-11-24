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
var tutorial: Tutorial
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
	Race.build_environment(self, dawn)
	track = Track.new()
	add_child(track)
	track.build(course)

	car = PlayerCar.new()
	add_child(car)
	var battle := Game.is_battle(mode)
	# campaign: you are the hero, in the hero's car
	var car_id := Campaign.HERO_CAR if mode == Game.Mode.CAMPAIGN else ""
	car.setup(track, track.start_s - 6.0, -track.hw * 0.45 if battle else 0.0, car_id)
	car.popup.connect(_on_popup)
	car.crashed.connect(_on_crash)
	if dawn:
		car.lights_on = true

	if battle:
		rival = RivalCar.new()
		add_child(rival)
		# the rival lines up a car length ahead: you start the chase from behind
		rival.setup(track, course.rival, track.start_s - 1.0, track.hw * 0.45)
		rival.player = car

	cam = ChaseCamera.new()
	cam.car = car
	cam.far = 20000.0
	cam.near = 0.3          # better depth precision: no flicker between close surfaces
	add_child(cam)
	cam.current = true
	cam.snap()

	hud = Hud.new()
	add_child(hud)
	hud.build(self)
	hud.cup.visible = dawn or mode == Game.Mode.TIME_ATTACK
	if mode == Game.Mode.TUTORIAL:
		tutorial = Tutorial.new()
		add_child(tutorial)
		tutorial.build(self)

	Music.now_playing.connect(func(title): hud.show_popup("♪ " + title, Color(0.7, 0.85, 1.0)))
	if Music.in_menu:
		Music.play_race()
	else:
		Music.set_climax(false)
		hud.show_popup("♪ " + Music.current.get("title", ""), Color(0.7, 0.85, 1.0))
	audio = EngineAudio.new()
	audio.car = car
	add_child(audio)


static func build_environment(parent: Node, dawn: bool) -> void:
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
		# First Stage night: everything washed in deep moonlit blue
		# moonlit night: cool but not monochrome, so greens, greys and paint still read
		env.ambient_light_color = Color(0.4, 0.46, 0.64)
		env.ambient_light_energy = 0.8
		env.fog_light_color = Color(0.05, 0.08, 0.16)
		env.fog_density = 0.0016
		light.light_color = Color(0.66, 0.74, 0.95)
		light.light_energy = 0.8
		light.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(150.0), 0)
	var sky := Sky.new()
	if dawn:
		sky.sky_material = sky_mat
	else:
		var night := ShaderMaterial.new()
		night.shader = load("res://shaders/night_sky.gdshader")
		sky.sky_material = night
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	# bloom so lamps and lenses glow like the anime CG
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.1
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05
	if Mats.hq():
		_high_quality(env, light, dawn)
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	parent.add_child(light)


## The full-fat look (desktop renderer only): real night sky lighting the
## scene, bounced light, reflections on the damp road, contact shadows and
## light shafts through the mist.
static func _high_quality(env: Environment, light: DirectionalLight3D, dawn: bool) -> void:
	if not dawn:
		var pano := ShaderMaterial.new()
		pano.shader = load("res://shaders/night_sky_hq.gdshader")
		pano.set_shader_parameter("pano", load("res://assets/pbr/night_sky.hdr"))
		var sky := Sky.new()
		sky.sky_material = pano
		sky.radiance_size = Sky.RADIANCE_SIZE_256
		env.sky = sky
		env.sky_rotation = Vector3(0, deg_to_rad(40.0), 0)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 1.0
		env.ambient_light_energy = 2.0
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		light.light_color = Color(0.62, 0.72, 1.0)
		light.light_energy = 1.0
		env.fog_light_color = Color(0.03, 0.045, 0.08)
		env.fog_density = 0.0006
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = 220.0
	light.shadow_blur = 1.5
	light.light_angular_distance = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.35
	env.tonemap_white = 6.0
	var q: int = 2
	var game: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")
	if game:
		q = game.quality
	env.ssr_enabled = q >= 1
	env.ssr_max_steps = 96
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.2
	env.ssil_enabled = q >= 2
	env.ssil_intensity = 1.2
	env.sdfgi_enabled = q >= 2
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_energy = 1.0
	env.volumetric_fog_enabled = q >= 1
	light.shadow_enabled = true
	light.directional_shadow_max_distance = [90.0, 160.0, 220.0][q]
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.55, 0.62, 0.8)
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_ambient_inject = 0.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.1


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
			if tutorial:
				tutorial.update(dt)
			if car.s > track.finish_s * 0.82:
				Music.set_climax(true)
		State.FINISHED:
			car.control_enabled = false
			car.hold_brake = false
			car.auto_stop = true
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
	var d2 := Vector2(d3.x, d3.z)
	var impact := 0.0
	if pen_l < pen_s:
		# side by side: pushed apart; the harder you lean on them the more it costs
		var sgn := signf(dl if dl != 0.0 else 1.0)
		car.pos += r3 * sgn * pen_l
		var n2 := Vector2(r3.x, r3.z) * sgn
		var vn := car.vel.dot(n2) - rival._lat_vel * sgn
		if vn < 0.0:
			car.vel -= n2 * car.vel.dot(n2) * 1.3
			impact = -vn + 1.0
		else:
			impact = 1.0
		rival.lat -= sgn * pen_l * 0.3
	else:
		car.pos += d3 * signf(ds if ds != 0.0 else -1.0) * pen_s
		var closing := car.vel.dot(d2) - rival.v
		if ds < 0.0:
			# you ran into them from behind
			if closing > 0.0:
				car.vel -= d2 * (closing + 1.0)
				impact = closing + 1.0
				if closing > 7.0 and state == State.RACING:
					_lose("YOU RAMMED %s - DISQUALIFIED" % rival.info.name.to_upper())
					return
		else:
			# they touched you from behind: their fault, they lose the time
			rival.v = minf(rival.v, car.vel.dot(d2) - 0.5)
			rival.wobble = 0.8
			return
	_contact(impact)


func _blind_attack(dt: float) -> void:
	_rattle_cooldown -= dt
	_contact_cooldown -= dt
	var gap := rival.s - car.s
	if car.blind and gap > 8.0 and gap < 40.0 and _rattle_cooldown <= 0.0 and state == State.RACING:
		_rattle_cooldown = 20.0
		rival.rattled = 3.5
		hud.show_popup("%s LOST YOU IN THE DARK!" % rival.info.name.to_upper(), Color(0.7, 0.8, 1.0))


func _check_finish() -> void:
	if car.s < track.finish_s:
		return
	state = State.FINISHED
	if tutorial:
		hud.set_center("PRACTICE DONE", Color(0.5, 1, 0.6))
		hud.show_result("Drift School: %d of %d lessons\nDrift score  %d\n\n[R] Run it again      [Enter] Menu" % [
			mini(tutorial.step, Tutorial.STEPS.size() - 1), Tutorial.STEPS.size() - 1, car.score])
		return
	var lines: Array[String] = []
	var title := "FINISH"
	var color := Color.WHITE
	match mode:
		Game.Mode.BATTLE, Game.Mode.CAMPAIGN:
			var won := not rival.finished
			title = "YOU WIN!" if won else "YOU LOSE"
			color = Color(0.4, 1, 0.4) if won else Color(1, 0.35, 0.3)
			lines.append("vs %s  (%s)" % [rival.info.name, Cars.get_car(rival.info.get("car", "")).name])
			if won:
				var margin := (track.finish_s - rival.s) / maxf(rival.v, 1.0)
				lines.append("Won by about %.2f s" % margin)
				if course.has("campaign_stage"):
					var st: int = course.campaign_stage
					Game.clear_stage(st)
					if st + 1 < Campaign.STAGES.size():
						lines.append("STAGE %d CLEAR  ·  next: %s" % [st + 1, Campaign.stage(st + 1).title])
						Game.campaign_stage = st + 1
					else:
						lines.append("CAMPAIGN COMPLETE: you are the fastest downhill driver in the region!")
				var rid: String = course.rival.get("car", "")
				if Game.unlock_car(rid):
					lines.append("NEW CAR: %s joins your garage!" % Cars.get_car(rid).name)
				var wins: int = Game.records.get_value("garage", "wins", 0) + 1
				Game.records.set_value("garage", "wins", wins)
				Game.records.save(Game.SAVE_PATH)
				for bonus in [[3, "180sx"], [6, "s2000"]]:
					if wins >= bonus[0] and Game.unlock_car(bonus[1]):
						lines.append("BONUS CAR for %d wins: %s!" % [bonus[0], Cars.get_car(bonus[1]).name])
			else:
				lines.append("Lost by %.2f s" % (race_time - rival.finish_time))
		Game.Mode.SCORE_ATTACK:
			title = "SCORE  %d" % (car.score + int(car.combo))
			color = Color(1.0, 0.5, 0.85)
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


var _contact_cooldown := 0.0


## Running into the rival from behind: you lose speed and control,
## and a hard hit gets you disqualified.
func _contact(impact: float) -> void:
	if state != State.RACING or _contact_cooldown > 0.0:
		return
	_contact_cooldown = 0.8
	car.combo = 0.0
	# every touch costs both cars: speed, a moment of lost control, a shake
	car._crash(minf(maxf(impact, 2.5) * 1.6, 12.0))
	rival.wobble = 1.2
	rival.v *= 0.94
	cam.shake(clampf(impact / 8.0, 0.35, 1.0))
	hud.show_popup("CONTACT!", Color(1.0, 0.35, 0.2))


func _on_crash(impact: float) -> void:
	if state != State.RACING:
		return
	cam.shake(clampf(impact / 12.0, 0.2, 1.0))
	if Game.is_battle(mode) and impact > 13.0:
		_lose("CRASHED OUT")
		return
	if not Game.is_battle(mode):
		var pen := snappedf(clampf(impact * 0.15, 0.3, 3.0), 0.1)
		race_time += pen
		hud.show_popup("CRASH!  +%.1f s" % pen, Color(1.0, 0.35, 0.2))
	elif impact > 4.0:
		hud.show_popup("CRASH!", Color(1.0, 0.35, 0.2))


func _lose(reason: String) -> void:
	state = State.FINISHED
	var lines: Array[String] = [reason, "", "Time  %s" % Game.format_time(race_time), "", "[R] Retry      [Enter] Menu"]
	hud.set_center("YOU LOSE", Color(1, 0.35, 0.3))
	hud.show_result("\n".join(lines))
