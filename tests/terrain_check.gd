extends SceneTree
## Headless check: walks every road and reports where the drawn mountain
## would rise above the road surface or into a tunnel.
## Run: godot --headless -s tests/terrain_check.gd

func _initialize() -> void:
	var total := 0
	for c in Courses.all():
		var t := Track.new()
		root.add_child(t)
		t.build(c)
		if t.terrain_h.is_empty():
			t.queue_free()
			continue
		var bad := t.terrain_faults()
		total += bad.size()
		var where := ""
		for k in mini(bad.size(), 6):
			where += "  s=%.0f %s" % [bad[k][0], bad[k][1]]
		print("%-18s faults %4d%s" % [c.name, bad.size(), where])
		t.queue_free()
	print("TOTAL ", total)
	quit(1 if total > 0 else 0)
