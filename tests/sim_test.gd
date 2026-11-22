extends SceneTree
## Headless checks: course geometry sanity + an autopilot run per course.
## Run: godot --headless -s tests/sim_test.gd

func _initialize() -> void:
	var failures := 0
	for c in Courses.all():
		var t := Track.new()
		root.add_child(t)
		t.build(c)
		var minw := 99.0
		for g in t.grass_l:
			minw = minf(minw, g)
		var line := "%-18s len %5.0fm drop %4.0fm hairpins %2d overlaps %d" % [c.name, t.length, t.drop, t.hairpins, t.overlaps]
		# rival alone
		var rv := RivalCar.new()
		root.add_child(rv)
		rv.setup(t, c.rival, t.start_s - 6.0, 1.0)
		rv.go = true
		var rt := 0.0
		while not rv.finished and rt < 600.0:
			rt += 1.0 / 120.0
			rv.step(1.0 / 120.0, rt)
		# autopilot player
		var car := PlayerCar.new()
		root.add_child(car)
		car.setup(t, t.start_s - 6.0, 0.0)
		car.control_enabled = true
		car.hold_brake = false
		car.bot = true
		var prof := t.speed_profile(1.0, 80.0)
		var time := 0.0
		var walls := [0]
		car.crashed.connect(func(_i): walls[0] += 1)
		var max_slip := 0.0
		var drift_frames := 0
		var gutter_frames := 0
		while car.s < t.finish_s and time < 600.0:
			var dt := 1.0 / 120.0
			time += dt
			var look := car.s + 6.0 + car.speed * 0.25
			var target := t.point_at(look, 0.0)
			var to := Vector2(target.x - car.pos.x, target.z - car.pos.z)
			var err := wrapf(to.angle() - car.vel.angle() if car.speed > 3.0 else to.angle() - car.yaw, -PI, PI)
			car.bot_steer = clampf(err * 3.0, -1.0, 1.0)
			var vt: float = prof[mini(t.index_at_s(car.s + 10.0), prof.size() - 1)]
			car.bot_throttle = 1.0 if car.speed < vt else 0.0
			car.bot_brake = clampf((car.speed - vt) * 0.3, 0.0, 1.0)
			car.physics_step(dt)
			max_slip = maxf(max_slip, absf(car.slip))
			if car.drifting: drift_frames += 1
			if car.in_gutter: gutter_frames += 1
		line += " | rival %s | bot %s walls %d drift %.0f%% gutter %.1fs maxslip %.0f° cup %d score %d" % [
			"%.1fs" % rt, "%.1fs" % time, walls[0], 100.0 * drift_frames / (time * 120.0),
			gutter_frames / 120.0, rad_to_deg(max_slip), int(car.cup), car.score]
		if t.overlaps > 0 or time >= 600.0 or not rv.finished:
			failures += 1
			line = "FAIL " + line
		print(line)
		t.queue_free(); rv.queue_free(); car.queue_free()
	print("failures: %d" % failures)
	quit(1 if failures > 0 else 0)
