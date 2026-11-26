extends Node
## Preview of the spectator figures: godot tools/_model_shot.tscn -- out.png
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
	var x := 0.0
	for k in 9:
		var mi := MeshInstance3D.new()
		mi.mesh = sc._person_mesh(40 + k)
		mi.position = Vector3(x, 0, 0)
		mi.rotation.y = PI + (k - 4) * 0.12
		add_child(mi)
		x += 0.9
	var ink := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	ink.mesh = quad
	var im := ShaderMaterial.new()
	im.shader = load("res://shaders/outline.gdshader")
	ink.material_override = im
	ink.extra_cull_margin = 16384.0
	add_child(ink)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(3.6, 1.3, 6.2)
	cam.look_at(Vector3(3.6, 0.95, 0))
	cam.fov = 50
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit()
