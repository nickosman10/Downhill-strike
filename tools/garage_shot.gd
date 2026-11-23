extends Node
## Renders the whole garage lined up on the Haruna start straight.
func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	get_window().size = Vector2i(1920, 1080)
	var root3d := Node3D.new()
	add_child(root3d)
	Race.build_environment(root3d, false)
	var t := Track.new()
	root3d.add_child(t)
	t.build(Courses.all()[0])
	var s0 := t.start_s + 20.0
	var cars: Array = []
	for k in Cars.ORDER.size():
		var id: String = Cars.ORDER[k]
		var m := CarModel.for_car(id)
		root3d.add_child(m)
		var row := k % 2
		var s := s0 + floorf(k / 2.0) * 7.0
		var p := t.point_at(s, -1.7 if row == 0 else 1.7)
		var d := t.dir_at(s)
		m.transform = Transform3D(Basis.looking_at(-d, Vector3.UP).scaled(Vector3.ONE * 0.92), p)
		m.update_visual(0.1, 0.0, 0.0, false)
		cars.append(m)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	cam.far = 20000.0
	var mid := t.point_at(s0 + 18.0, 0.0)
	var d0 := t.dir_at(s0 + 18.0)
	var r0 := d0.cross(Vector3.UP)
	for view in [["garage_front", -d0 * 30.0 + r0 * 9.0 + Vector3.UP * 4.5, 42.0], ["garage_rear", d0 * 30.0 - r0 * 9.0 + Vector3.UP * 4.0, 42.0]]:
		cam.global_position = mid + view[1]
		cam.look_at(mid + Vector3.UP * 0.6, Vector3.UP)
		cam.fov = view[2]
		cam.current = true
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(view[0] + ".png"))
		print("saved ", view[0])
	get_tree().quit()
