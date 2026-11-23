extends Node
## One lit three-quarter view per car, for comparing shapes with references.
func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	get_window().size = Vector2i(800, 450)
	var world := Node3D.new()
	add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.57, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-30), 0)
	sun.light_energy = 1.3
	world.add_child(sun)
	var floor_m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_m.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.36, 0.38)
	floor_m.material_override = fm
	world.add_child(floor_m)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 38.0
	cam.current = true
	for id in Cars.ORDER:
		var m := CarModel.for_car(id)
		world.add_child(m)
		m.set_lights(true, true)
		m.update_visual(0.1, 0.0, 0.0, false)
		cam.global_position = Vector3(-3.4, 1.35, -4.3)
		cam.look_at(Vector3(0, 0.55, 0), Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("show_" + id + ".png"))
		m.queue_free()
		await get_tree().process_frame
	get_tree().quit()
