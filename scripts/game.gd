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
var menu_screen := "main"      # which menu screen to come back to after a race


func _ready() -> void:
	_setup_input()
	records.load(SAVE_PATH)
	selected_car = records.get_value("garage", "selected", "ae85")
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


func select_car(id: String) -> void:
	if is_unlocked(id):
		selected_car = id
		records.set_value("garage", "selected", id)
		records.save(SAVE_PATH)
