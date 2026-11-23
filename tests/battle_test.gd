extends SceneTree
## Battle pacing: autopilot player vs the rival side by side; logs the gap.
## Run: godot --headless -s tests/battle_test.gd

func _initialize() -> void:
	var failures := 0
	for ci in [0, 2, 4]:
		var c: Dictionary = Courses.all()[ci]
		var t := Track.new()
		root.add_child(t)
		t.build(c)
		var car := PlayerCar.new()
		root.add_child(car)
		car.setup(t, t.start_s - 6.0, -t.hw * 0.45, "ae86")
		car.control_enabled = true
		car.hold_brake = false
		car.bot = true
		var rv := RivalCar.new()
		root.add_child(rv)
		rv.setup(t, c.rival, t.start_s - 6.0, t.hw * 0.45)
		rv.player = car
		rv.go = true
		var prof := t.speed_profile(1.0, 80.0)
		var time := 0.0
		var log := []
		var ahead_at_10 := 0.0
		var max_gap := 0.0
		while car.s < t.finish_s and time < 600.0:
			var dt := 1.0 / 120.0
			time += dt
			var look := car.s + 6.0 + car.speed * 0.25
			var target := t.point_at(look, -t.hw * 0.3)
			var to := Vector2(target.x - car.pos.x, target.z - car.pos.z)
			var err := wrapf(to.angle() - car.vel.angle() if car.speed > 3.0 else to.angle() - car.yaw, -PI, PI)
			car.bot_steer = clampf(err * 3.0, -1.0, 1.0)
			var vt: float = prof[mini(t.index_at_s(car.s + 10.0), prof.size() - 1)]
			car.bot_throttle = 1.0 if car.speed < vt else 0.0
			car.bot_brake = clampf((car.speed - vt) * 0.3, 0.0, 1.0)
			car.physics_step(dt)
			rv.step(dt, time)
			var gap: float = rv.s - car.s
			if absf(time - 10.0) < dt * 0.5:
				ahead_at_10 = gap
			if time > 20.0:
				max_gap = maxf(max_gap, absf(gap))
			if int(time * 120.0) % (120 * 40) == 0:
				log.append("%d:%+.0f" % [int(time), gap])
		var line := "%-12s rival lead at 10s %+.0fm, max |gap| after 20s %.0fm | %s" % [c.name, ahead_at_10, max_gap, " ".join(log)]
		if ahead_at_10 < 3.0 or max_gap > 60.0:
			failures += 1
			line = "FAIL " + line
		print(line)
		t.queue_free(); rv.queue_free(); car.queue_free()
	print("battle test failures: %d" % failures)
	quit(1 if failures > 0 else 0)
