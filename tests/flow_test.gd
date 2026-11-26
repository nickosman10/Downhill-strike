extends Node
## Walks the real game flow end to end: menu -> loading card -> race ->
## restart on the same course -> back to the menu, and checks each step arrives.
## Run: godot --rendering-driver vulkan tests/flow_test.tscn

func _ready() -> void:
	get_window().size = Vector2i(480, 270)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var fails := 0
	await _until(func() -> bool: return main.current is Menu)
	print("[flow] menu up: ", main.current is Menu)
	Game.mode = Game.Mode.BATTLE
	Game.course_index = 1
	main.current.start_race.emit()
	await get_tree().process_frame
	var card_seen := false
	for c in main.get_children():
		if c is CanvasLayer and c.layer == 90:
			card_seen = true
	print("[flow] loading card shown: ", card_seen)
	await _until(func() -> bool: return main.current is Race)
	var race: Race = main.current
	var track_id := race.track.get_instance_id()
	print("[flow] race up: ", race.course.name, ", rival ", race.rival != null, ", crowd ", Mats.crowd)
	for i in 30:
		await get_tree().physics_frame
	var old_car := race.car.get_instance_id()
	race.state = Race.State.FINISHED
	race._respawn()
	for i in 10:
		await get_tree().physics_frame
	var same_world := race.track.get_instance_id() == track_id
	var fresh := race.car.get_instance_id() != old_car and race.state == Race.State.COUNTDOWN and race.race_time == 0.0
	print("[flow] restart kept the course: ", same_world, ", fresh cars and countdown: ", fresh)
	race.exit_to_menu.emit()
	await _until(func() -> bool: return main.current is Menu)
	print("[flow] back at the menu: ", main.current is Menu)
	for ok: bool in [card_seen, same_world, fresh, main.current is Menu]:
		if not ok:
			fails += 1
	print("[flow] failures: ", fails)
	get_tree().quit(fails)


func _until(done: Callable) -> void:
	for i in 600:
		await get_tree().process_frame
		if done.call():
			return
