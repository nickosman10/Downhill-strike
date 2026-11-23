extends Node
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	get_window().size = Vector2i(int(args[1]), int(args[2]))
	var menu := Menu.new()
	add_child(menu)
	for i in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[0])
	get_tree().quit()
