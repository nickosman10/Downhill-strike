extends Node
## Preview of the 3D trees: godot tools/_model_shot.tscn -- out.png
func _ready() -> void:
	get_window().size = Vector2i(1600, 800)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.5, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	add_child(sun)
	var sc := Scenery.new()
	sc.trunk_mat = Mats.pbr("bark", 1.0, Color(0.75, 0.7, 0.65))
	var x := 0.0
	for pair in [["broadleaf", 11], ["broadleaf", 5], ["slender", 12], ["fir", 13], ["fir", 4]]:
		var mi := MeshInstance3D.new()
		mi.mesh = sc._tree3d(pair[0], pair[1])
		mi.position = Vector3(x, 0, 0)
		mi.rotation.y = 0.6
		add_child(mi)
		x += 9.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(18, 5, 34)
	cam.look_at(Vector3(18, 6, 0))
	cam.fov = 40
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit()
