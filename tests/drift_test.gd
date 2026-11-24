extends SceneTree
## Drift handling check: a normal driver must never slide by surprise, and a
## driver that asks for drifts (handbrake tap into corners) must get round
## without living on the guard rails.
func run(t: Track, drifter: bool) -> Dictionary:
	var car := PlayerCar.new(); root.add_child(car)
	car.setup(t, t.start_s, 0.0)
	car.control_enabled = true; car.hold_brake = false; car.bot = true
	var prof := t.speed_profile(1.0, 80.0)
	var walls := [0]
	car.crashed.connect(func(_i): walls[0] += 1)
	var time := 0.0; var drift_frames := 0; var drifts := 0; var was := false
	var hb_until := -1.0
	while car.s < t.finish_s and time < 900.0:
		var dt := 1.0 / 120.0
		time += dt
		var look := car.s + 6.0 + car.speed * 0.25
		var target := t.point_at(look, 0.0)
		var to := Vector2(target.x - car.pos.x, target.z - car.pos.z)
		var err := wrapf(to.angle() - car.vel.angle() if car.speed > 3.0 else to.angle() - car.yaw, -PI, PI)
		car.bot_steer = clampf(err * 3.0, -1.0, 1.0)
		var vt: float = prof[mini(t.index_at_s(car.s + 10.0), prof.size() - 1)]
		var k_ahead := t.curvature_at(car.s + 12.0)
		if drifter:
			vt = maxf(vt, 16.0)
			var bend := absf(k_ahead) > 1.0 / 30.0
			if not car.drifting and bend and car.speed > 12.0 and time > hb_until + 1.0:
				hb_until = time + 0.15
				car.bot_steer = signf(k_ahead)
			# hold Space through the bend, let go as it opens out
			car.bot_handbrake = time < hb_until or (car.drifting and car._held and absf(k_ahead) > 1.0 / 45.0)
			if car.drifting and car._held:
				# hold the drift: steer into the bend, more or less to follow the road
				car.bot_steer = clampf(signf(k_ahead) * 0.5 + err * 2.0, -1.0, 1.0)
			elif car.drifting:
				# released: counter-steer to catch the slide
				car.bot_steer = -car.drift_dir
		car.bot_throttle = 1.0 if car.speed < vt else 0.0
		car.bot_brake = clampf((car.speed - vt) * 0.3, 0.0, 1.0)
		car.physics_step(dt)
		if car.drifting: drift_frames += 1
		if car.drifting and not was: drifts += 1
		was = car.drifting
	car.queue_free()
	return {"time": time, "walls": walls[0], "drift_pct": 100.0 * drift_frames / (time * 120.0), "drifts": drifts}

func _initialize() -> void:
	var fails := 0
	for idx in [0, 4]:
		var c: Dictionary = Courses.all()[idx]
		var t := Track.new(); root.add_child(t); t.build(c)
		var normal := run(t, false)
		var drift := run(t, true)
		print("%-12s normal: %.0fs walls %d drifts %d | drifter: %.0fs walls %d drifts %d (%.0f%% of the time)" % [
			c.name, normal.time, normal.walls, normal.drifts, drift.time, drift.walls, drift.drifts, drift.drift_pct])
		if normal.drifts > 0 or drift.time >= 900.0 or drift.drifts < 5:
			fails += 1
		t.queue_free()
	print("drift test failures: %d" % fails)
	quit(1 if fails else 0)
