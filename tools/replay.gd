extends Node
## Records a gameplay video: the autopilot drives a downhill battle on Mt. Haruna.
##   godot --write-movie out.avi --fixed-fps 30 res://tools/replay.tscn -- <seconds>

var race: Race
var car: PlayerCar
var t: Track
var prof: PackedFloat32Array
var limit := 120.0
var clock := 0.0
var hb_until := -1.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		limit = float(args[0])
	get_window().size = Vector2i(1280, 720)
	Game.mode = Game.Mode.BATTLE
	Game.course_index = 0
	Game.selected_car = "ae86"
	race = Race.new()
	race.setup(Courses.all()[0], Game.Mode.BATTLE)
	add_child(race)
	car = race.car
	t = race.track
	car.bot = true
	prof = t.speed_profile(1.0, 80.0)


func _physics_process(dt: float) -> void:
	clock += dt
	if clock > limit:
		get_tree().quit()
		return
	if not car.control_enabled:
		return
	# the drifter autopilot: hold Space through the bends, catch the slide after
	var look := car.s + 6.0 + car.speed * 0.25
	var target := t.point_at(look, 0.0)
	var to := Vector2(target.x - car.pos.x, target.z - car.pos.z)
	var err := wrapf(to.angle() - car.vel.angle() if car.speed > 3.0 else to.angle() - car.yaw, -PI, PI)
	car.bot_steer = clampf(err * 3.0, -1.0, 1.0)
	var vt: float = maxf(prof[mini(t.index_at_s(car.s + 10.0), prof.size() - 1)], 16.0)
	var k_ahead := t.curvature_at(car.s + 12.0)
	var bend := absf(k_ahead) > 1.0 / 30.0
	if not car.drifting and bend and car.speed > 12.0 and clock > hb_until + 1.0:
		hb_until = clock + 0.15
		car.bot_steer = signf(k_ahead)
	car.bot_handbrake = clock < hb_until or (car.drifting and car._held and absf(k_ahead) > 1.0 / 45.0)
	if car.drifting and car._held:
		car.bot_steer = clampf(signf(k_ahead) * 0.5 + err * 2.0, -1.0, 1.0)
	elif car.drifting:
		car.bot_steer = -car.drift_dir
	car.bot_throttle = 1.0 if car.speed < vt else 0.0
	car.bot_brake = clampf((car.speed - vt) * 0.3, 0.0, 1.0)
