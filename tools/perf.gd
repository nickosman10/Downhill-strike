extends Node
## Load-time and scene-weight measurement: godot tools/perf.tscn -- [course index]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var only := int(args[0]) if args.size() > 0 else -1
	var courses := Courses.all()
	for ci in courses.size():
		if only >= 0 and ci != only:
			continue
		Mats.crowd = true
		var t0 := Time.get_ticks_msec()
		var t := Track.new()
		add_child(t)
		t.build(courses[ci])
		var built := Time.get_ticks_msec() - t0
		await get_tree().process_frame
		await get_tree().process_frame
		var nodes := t.find_children("*", "", true, false).size()
		var lights := t.find_children("*", "Light3D", true, false).size()
		print("[perf] %-18s build %5d ms  nodes %5d  lights %3d  video mem %4d MB" % [courses[ci].name, built, nodes, lights,
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0)])
		t.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit()
