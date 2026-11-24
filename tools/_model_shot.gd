extends Node
## Preview of the plant models: godot tools/_model_shot.tscn -- out.png
func _ready() -> void:
	get_window().size = Vector2i(1600, 700)
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
	var x := 0.0
	for n in ["fir", "broadleaf", "shrub_a", "shrub_b", "fern"]:
		var inst: Node3D = (load("res://assets/models/%s.glb" % n) as PackedScene).instantiate()
		inst.position = Vector3(x, 0, 0)
		add_child(inst)
		x += 9.0 if n in ["fir", "broadleaf"] else 3.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(10, 6, 30)
	cam.look_at(Vector3(10, 5.5, 0))
	cam.fov = 40
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit()
