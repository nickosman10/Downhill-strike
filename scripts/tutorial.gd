class_name Tutorial
extends CanvasLayer
## Drift School: a solo run that teaches the controls one step at a time with
## big on-screen key prompts, like the training modes in arcade racers.

var race                     # Race node
var car: PlayerCar
var step := 0
var _t := 0.0                # time spent in the current step
var _acc := 0.0              # step-specific accumulator
var _was_drifting := false
var _was_held := false
var _spins_seen := 0
var _corner_flash := 0.0
var _flash_tw: Tween

var panel: PanelContainer
var title: Label
var body: Label
var keys: HBoxContainer
var checklist: Label
var qte: Label

# [title, instruction, keys to show]
const STEPS := [
	["GO", "Hold the throttle to get rolling.", ["W"]],
	["STEER", "Steer to stay in your lane. Gentle inputs: the car leans into the turn.", ["A", "D"]],
	["BRAKE", "Brake before a corner, not in it.", ["S"]],
	["DRIFT", "At the next bend, hold SPACE and steer into the corner.", ["SPACE", "+", "A / D"]],
	["HOLD THE ANGLE", "Keep SPACE held. Steer into the bend for more angle, away from it for less.", ["SPACE", "hold"]],
	["CATCH IT", "Let go of SPACE, then counter-steer the other way to straighten up. The car keeps sliding until you catch it.", ["release SPACE", "→", "counter-steer"]],
	["GUTTER HOOK", "On a tight hairpin, steer right to the inside edge and drop your inside wheels into the gutter. It carries you round.", ["A / D", "inside edge"]],
	["INERTIA DRIFT", "On a straight before a bend: flick the steering hard one way, then hard the other way.", ["A", "→", "D"]],
	["BLIND ATTACK", "Switch your lights off while chasing at night. Riskier, but drift points count double.", ["L"]],
	["GRADUATED", "Drift School complete. Keep practising here, or press Esc for the menu.", ["Esc"]],
]


func build(r) -> void:
	race = r
	car = r.car
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.1, 0.86)
	sb.border_color = Color(1.0, 0.72, 0.16)
	sb.set_border_width_all(0)
	sb.border_width_left = 6
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	title = _label("", 34, Color(1.0, 0.75, 0.2))
	col.add_child(title)
	body = _label("", 20, Color(0.92, 0.94, 1.0))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	col.add_child(body)
	keys = HBoxContainer.new()
	keys.add_theme_constant_override("separation", 10)
	col.add_child(keys)

	checklist = _label("", 16, Color(0.7, 0.78, 0.95))
	root.add_child(checklist)

	qte = _label("", 64, Color(1, 1, 1))
	qte.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qte.add_theme_constant_override("outline_size", 12)
	root.add_child(qte)

	_layout()
	get_viewport().size_changed.connect(_layout)
	_show_step()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	return l


func _keycap(text: String) -> Control:
	if text in ["+", "→", "hold"]:
		return _label(text, 26, Color(0.8, 0.85, 1.0))
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.95, 0.92)
	sb.set_corner_radius_all(8)
	sb.border_width_bottom = 5
	sb.border_color = Color(0.55, 0.55, 0.6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(0.08, 0.08, 0.12))
	p.add_child(l)
	return p


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	panel.position = Vector2(vs.x * 0.5 - 320, vs.y - 300)
	panel.custom_minimum_size = Vector2(640, 0)
	checklist.position = Vector2(20, 170)
	qte.size = Vector2(vs.x, 90)
	qte.position = Vector2(0, vs.y * 0.36)


func _show_step() -> void:
	var s: Array = STEPS[mini(step, STEPS.size() - 1)]
	title.text = "%d / %d   %s" % [mini(step + 1, STEPS.size()), STEPS.size(), s[0]]
	body.text = s[1]
	for c in keys.get_children():
		c.queue_free()
	for k in s[2]:
		keys.add_child(_keycap(k))
	# pulse the key row so the eye goes to it
	if _flash_tw:
		_flash_tw.kill()
	_flash_tw = create_tween().set_loops()
	_flash_tw.tween_property(keys, "modulate:a", 0.45, 0.45)
	_flash_tw.tween_property(keys, "modulate:a", 1.0, 0.45)
	var lines: Array[String] = []
	for k in STEPS.size() - 1:
		lines.append(("✔ " if k < step else ("▶ " if k == step else "   ")) + STEPS[k][0])
	checklist.text = "DRIFT SCHOOL\n" + "\n".join(lines)
	_t = 0.0
	_acc = 0.0


func _next(msg := "NICE!") -> void:
	step += 1
	race.hud.show_popup(msg, Color(0.5, 1.0, 0.6))
	_show_step()


func update(dt: float) -> void:
	_t += dt
	var kmh := car.speed * 3.6
	# a tight bend coming up?
	var k_ahead := 0.0
	for d in [25.0, 40.0, 55.0]:
		k_ahead = maxf(k_ahead, absf(car.track.curvature_at(car.s + d)))
	var bend_ahead := k_ahead > 1.0 / 45.0
	match step:
		0:
			if kmh > 40.0:
				_next()
		1:
			if absf(car.steer) > 0.25:
				_acc += dt
			if _acc > 1.5:
				_next()
		2:
			if car.brake > 0.4 and car.speed > 5.0:
				_acc += dt
			if _acc > 0.3:
				_next()
		3:
			if car.drifting and car._held:
				_next("DRIFTING!")
		4:
			if car.drifting and car._held:
				_acc += dt
			if _acc > 1.0:
				_next()
			elif not car.drifting:
				step = 3          # slide ended early: start the drift again
				_show_step()
		5:
			if car.drifting and not car._held:
				_was_held = true
			if _was_held and not car.drifting:
				if car.spins > _spins_seen:
					_spins_seen = car.spins
					race.hud.show_popup("SPUN! Counter-steer sooner. Try again", Color(1.0, 0.5, 0.3))
					step = 3
					_was_held = false
					_show_step()
				else:
					_was_held = false
					_next("CAUGHT IT!")
		6:
			if car.hooked:
				_next("HOOKED!")
			elif _t > 90.0:
				_next("Skipped: try it on a hairpin later")
		7:
			if car.drifting and not car._held and not _was_drifting:
				_next("INERTIA DRIFT!")
			elif _t > 60.0:
				_next("Skipped: practise it on your own")
		8:
			if not car.lights_on:
				_next("BLIND ATTACK!")
	_was_drifting = car.drifting
	# quick-time prompt before bends while learning to drift
	var learning := step in [3, 6]
	if learning and bend_ahead and not car.drifting and car.speed > 10.0:
		_corner_flash += dt
		var on := int(_corner_flash * 6.0) % 2 == 0
		qte.text = ("SPACE + STEER!" if step == 3 else "INSIDE EDGE!") if on else ""
		qte.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	elif step == 5 and car.drifting and not car._held:
		qte.text = "COUNTER-STEER!"
		qte.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	elif step == 4 and car.drifting:
		qte.text = "HOLD SPACE"
		qte.add_theme_color_override("font_color", Color(1, 1, 1))
	else:
		_corner_flash = 0.0
		qte.text = ""


