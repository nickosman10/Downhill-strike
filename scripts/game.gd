extends Node
## Global game state: input setup, selections, saved best times.

const SAVE_PATH := "user://records.cfg"

enum Mode { TIME_ATTACK, BATTLE, DAWN_DELIVERY, TUTORIAL, SCORE_ATTACK, CAMPAIGN }
const MODE_NAMES := ["Time Attack", "Downhill Battle", "Water Cup", "Drift School", "Score Attack", "Campaign"]

var course_index := 0
var mode: int = Mode.BATTLE
var records := ConfigFile.new()
var selected_car := "ae85"
var campaign_stage := 0
var quality := 1               # graphics: 0 low, 1 medium, 2 high
var _auto := true              # lower the level by itself when the frame rate is poor
var _fps_t := 0.0
var _fps_n := 0
var _fps_label: Label
const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH"]
var menu_screen := "main"      # which menu screen to come back to after a race


func _ready() -> void:
	_setup_input()
	records.load(SAVE_PATH)
	selected_car = records.get_value("garage", "selected", "ae85")
	Ui.install(get_tree().root)
	Mats.realistic = records.get_value("video", "realistic", false)
	# cartoon style: every object that enters the scene is cel-shaded
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is GeometryInstance3D and Mats.toon():
			Mats.toonify_node.call_deferred(n))
	# (a new key: levels saved by earlier builds meant something far heavier)
	quality = records.get_value("video", "level", 1)
	_auto = not records.get_value("video", "chosen", false)
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_quality()
	if not is_unlocked(selected_car):
		selected_car = "ae85"


func _setup_input() -> void:
	_bind("throttle", [KEY_W, KEY_UP], [JOY_BUTTON_A], JOY_AXIS_TRIGGER_RIGHT, 1)
	_bind("brake", [KEY_S, KEY_DOWN], [JOY_BUTTON_X], JOY_AXIS_TRIGGER_LEFT, 1)
	_bind("steer_left", [KEY_A, KEY_LEFT], [], JOY_AXIS_LEFT_X, -1)
	_bind("steer_right", [KEY_D, KEY_RIGHT], [], JOY_AXIS_LEFT_X, 1)
	_bind("handbrake", [KEY_SPACE], [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER], -1, 0)
	_bind("lights", [KEY_L], [JOY_BUTTON_Y], -1, 0)
	_bind("camera", [KEY_C], [JOY_BUTTON_BACK], -1, 0)
	_bind("reset_car", [KEY_R], [JOY_BUTTON_LEFT_SHOULDER], -1, 0)
	_bind("pause_menu", [KEY_ESCAPE], [JOY_BUTTON_START], -1, 0)
	_bind("confirm", [KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_A], -1, 0)


func _bind(action: String, keys: Array, buttons: Array, axis: int, axis_dir: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)
	if axis >= 0:
		var ja := InputEventJoypadMotion.new()
		ja.axis = axis
		ja.axis_value = axis_dir
		InputMap.action_add_event(action, ja)


func record_key(course_id: String, m: int) -> String:
	return "%s_%d" % [course_id, m]


func best_time(course_id: String, m: int) -> float:
	return records.get_value("times", record_key(course_id, m), 0.0)


func submit_time(course_id: String, m: int, t: float) -> bool:
	var best := best_time(course_id, m)
	if best <= 0.0 or t < best:
		records.set_value("times", record_key(course_id, m), t)
		records.save(SAVE_PATH)
		return true
	return false


func best_score(course_id: String) -> int:
	return records.get_value("scores", course_id, 0)


func submit_score(course_id: String, score: int) -> bool:
	if score > best_score(course_id):
		records.set_value("scores", course_id, score)
		records.save(SAVE_PATH)
		return true
	return false


static func format_time(t: float) -> String:
	var m := int(t / 60.0)
	var s := fmod(t, 60.0)
	return "%d:%06.3f" % [m, s]


# ---------------------------------------------------------------- garage

func unlocked_cars() -> Array:
	return records.get_value("garage", "unlocked", ["ae85"])


func is_unlocked(id: String) -> bool:
	return id in unlocked_cars()


## Returns true when the car is new to the garage.
func unlock_car(id: String) -> bool:
	var u := unlocked_cars()
	if id in u:
		return false
	u.append(id)
	records.set_value("garage", "unlocked", u)
	records.save(SAVE_PATH)
	return true


# ---------------------------------------------------------------- campaign

## Number of campaign stages beaten (the next one is unlocked).
func campaign_cleared() -> int:
	return records.get_value("campaign", "cleared", 0)


func clear_stage(i: int) -> void:
	if i + 1 > campaign_cleared():
		records.set_value("campaign", "cleared", i + 1)
		records.save(SAVE_PATH)


func is_battle(m: int) -> bool:
	return m == Mode.BATTLE or m == Mode.CAMPAIGN


func set_quality(q: int, by_player := true) -> void:
	quality = clampi(q, 0, 2)
	records.set_value("video", "level", quality)
	if by_player:
		_auto = false
		records.set_value("video", "chosen", true)
	records.save(SAVE_PATH)
	apply_quality()


## Art style: cartoon (default) or the photo-style renderer.
func set_realistic(on: bool) -> void:
	Mats.realistic = on
	records.set_value("video", "realistic", on)
	records.save(SAVE_PATH)


func apply_quality() -> void:
	Mats.quality = quality
	var vp := get_viewport()
	# lower levels draw the 3D picture smaller and sharpen it back up
	vp.scaling_3d_scale = [0.6, 0.8, 1.0][quality]
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if quality == 2 else Viewport.SCALING_3D_MODE_FSR
	vp.msaa_3d = Viewport.MSAA_2X if quality == 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	if RenderingServer.get_rendering_device() != null:
		RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096][quality], true)
		var soft := RenderingServer.SHADOW_QUALITY_SOFT_HIGH if Mats.hq() else RenderingServer.SHADOW_QUALITY_SOFT_LOW
		RenderingServer.directional_soft_shadow_filter_set_quality(soft)
		RenderingServer.positional_soft_shadow_filter_set_quality(soft)
	for sun in get_tree().get_nodes_in_group("sun"):
		Race.sun_shadows(sun)


func _process(dt: float) -> void:
	_fps_t += dt
	_fps_n += 1
	if _fps_t < 4.0:
		return
	var fps := _fps_n / _fps_t
	_fps_t = 0.0
	_fps_n = 0
	if _fps_label:
		_fps_label.text = "%d fps · graphics %s" % [int(fps), QUALITY_NAMES[quality]]
	# too slow on this machine: step the graphics down (until the player picks a level)
	if _auto and quality > 0 and fps < 40.0 and not get_tree().paused and Engine.get_frames_drawn() > 400:
		set_quality(quality - 1, false)
		var scene := get_tree().current_scene
		if scene is Menu:
			get_tree().reload_current_scene.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	# F3: frame-rate read-out
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		if _fps_label:
			_fps_label.get_parent().queue_free()
			_fps_label = null
		else:
			var layer := CanvasLayer.new()
			layer.layer = 50
			add_child(layer)
			_fps_label = Label.new()
			_fps_label.position = Vector2(12, 8)
			Ui.inked(_fps_label, 16, Ui.YELLOW, 6)
			_fps_label.text = "measuring…"
			layer.add_child(_fps_label)


func select_car(id: String) -> void:
	if is_unlocked(id):
		selected_car = id
		records.set_value("garage", "selected", id)
		records.save(SAVE_PATH)
