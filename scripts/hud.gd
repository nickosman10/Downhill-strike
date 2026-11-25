class_name Hud
extends CanvasLayer

var race                       # Race node (untyped to avoid a cyclic reference)
var info_label: Label
var time_label: Label
var speed_label: Label
var gear_label: Label
var rpm_bar: ProgressBar
var score_label: Label
var combo_label: Label
var status_label: Label
var gap_label: Label
var center_label: Label
var warn_label: Label
var popups: VBoxContainer
var minimap: Minimap
var cup: CupWidget
var result_panel: PanelContainer
var result_label: Label
var speed_fx: ColorRect


class Minimap extends Control:
	var track: Track
	var race
	var pts := PackedVector2Array()
	var scale_f := 1.0
	var offset := Vector2.ZERO

	func setup(t: Track) -> void:
		track = t
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in t.P:
			mn = mn.min(Vector2(p.x, p.z))
			mx = mx.max(Vector2(p.x, p.z))
		var span := mx - mn
		scale_f = minf((size.x - 16.0) / maxf(span.x, 1.0), (size.y - 16.0) / maxf(span.y, 1.0))
		offset = (size - span * scale_f) * 0.5 - mn * scale_f
		for i in range(0, t.P.size(), 3):
			pts.append(_map(t.P[i]))

	func _map(p: Vector3) -> Vector2:
		return Vector2(p.x, p.z) * scale_f + offset

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.NAVY, 0.78))
		draw_rect(Rect2(Vector2.ZERO, size), Ui.PAPER, false, 3.0)
		if pts.size() > 1:
			draw_polyline(pts, Ui.INK, 7.0, true)
			draw_polyline(pts, Ui.PAPER, 3.0, true)
			draw_circle(pts[0], 5.5, Ui.INK)
			draw_circle(pts[0], 3.5, Ui.CYAN)
			draw_circle(pts[pts.size() - 1], 5.5, Ui.INK)
			draw_circle(pts[pts.size() - 1], 3.5, Ui.RED)
		if race and race.rival:
			draw_circle(_map(race.rival.global_position), 7.0, Ui.INK)
			draw_circle(_map(race.rival.global_position), 4.5, Cars.get_car(race.rival.info.get("car", "s13")).paint)
		if race and race.car:
			draw_circle(_map(race.car.global_position), 7.5, Ui.INK)
			draw_circle(_map(race.car.global_position), 5.0, Ui.YELLOW)


class CupWidget extends Control:
	var car: PlayerCar

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if car == null:
			return
		var w := size.x
		var h := size.y
		var top_w := w * 0.8
		var bot_w := w * 0.55
		var cx := w * 0.5
		var cup_pts := PackedVector2Array([
			Vector2(cx - top_w / 2, 8), Vector2(cx - bot_w / 2, h - 18),
			Vector2(cx + bot_w / 2, h - 18), Vector2(cx + top_w / 2, 8)])
		draw_rect(Rect2(Vector2.ZERO, size), Color(Ui.NAVY, 0.78))
		draw_rect(Rect2(Vector2.ZERO, size), Ui.PAPER, false, 3.0)
		# water: level + tilt from slosh
		var level := car.cup / 100.0
		var y := lerpf(h - 18, 14, level)
		var tilt := clampf(car.slosh.x * 120.0, -18.0, 18.0)
		var t_frac := (y - 8) / (h - 26)
		var half := lerpf(top_w, bot_w, t_frac) / 2.0
		if level > 0.01:
			var water := PackedVector2Array([
				Vector2(cx - half, y + tilt), Vector2(cx - bot_w / 2, h - 18),
				Vector2(cx + bot_w / 2, h - 18), Vector2(cx + half, y - tilt)])
			draw_colored_polygon(water, Color(0.35, 0.65, 1.0, 0.85))
		draw_polyline(cup_pts, Ui.PAPER, 3.5)
		var col := Color(0.6, 1.0, 0.6) if car.cup > 60 else (Color(1.0, 0.85, 0.3) if car.cup > 30 else Color(1, 0.3, 0.3))
		draw_string(ThemeDB.fallback_font, Vector2(4, h - 3), "WATER %d%%" % int(car.cup), HORIZONTAL_ALIGNMENT_CENTER, w - 8, 13, col)


func _label(text: String, size: int, pos: Vector2, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.horizontal_alignment = align
	if size >= 26:
		# big read-outs in the slanted display face
		Ui.title(l, size, Ui.PAPER, maxi(8, size / 6), Ui.INK)
	else:
		Ui.inked(l, size, Ui.PAPER, 7)
	add_child(l)
	return l


func build(r) -> void:
	race = r
	speed_fx = ColorRect.new()
	speed_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	speed_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/speed_lines.gdshader")
	speed_fx.material = sm
	add_child(speed_fx)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	info_label = _label("", 18, Vector2(20, 14))
	time_label = _label("0:00.000", 34, Vector2(20, 40))
	gap_label = _label("", 22, Vector2(20, 86))
	status_label = _label("", 20, Vector2(20, 118))

	score_label = _label("SCORE 0", 26, Vector2(20, 0))
	combo_label = _label("", 22, Vector2(20, 0))
	speed_label = _label("0", 64, Vector2(0, 0), HORIZONTAL_ALIGNMENT_RIGHT)
	gear_label = _label("1", 26, Vector2(0, 0), HORIZONTAL_ALIGNMENT_RIGHT)
	rpm_bar = ProgressBar.new()
	rpm_bar.max_value = 8000
	rpm_bar.show_percentage = false
	rpm_bar.add_theme_stylebox_override("background", Ui.box(Color(Ui.NAVY, 0.9), 3, 0.5, 0, Ui.INK, false))
	rpm_bar.add_theme_stylebox_override("fill", Ui.box(Ui.YELLOW, 3, 0.5, 0, Ui.INK, false))
	add_child(rpm_bar)
	Ui.title(speed_label, 54, Ui.YELLOW, 10)
	Ui.title(time_label, 40, Ui.PAPER, 9, Ui.RED)
	Ui.title(score_label, 28, Ui.YELLOW, 8)
	Ui.title(combo_label, 24, Ui.CYAN, 7, Ui.INK)
	Ui.inked(status_label, 22, Ui.CYAN, 8)

	center_label = _label("", 150, Vector2.ZERO, HORIZONTAL_ALIGNMENT_CENTER)
	Ui.title(center_label, 150, Ui.YELLOW, 24)
	warn_label = _label("", 40, Vector2.ZERO, HORIZONTAL_ALIGNMENT_CENTER)
	Ui.title(warn_label, 40, Ui.RED, 10, Ui.INK)

	popups = VBoxContainer.new()
	popups.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(popups)

	minimap = Minimap.new()
	minimap.size = Vector2(220, 220)
	minimap.race = race
	add_child(minimap)
	minimap.setup(race.track)

	cup = CupWidget.new()
	cup.size = Vector2(90, 110)
	cup.car = race.car
	add_child(cup)

	result_panel = PanelContainer.new()
	var sb := Ui.box(Color(0.045, 0.055, 0.17, 0.95), 4, 0.0, 30, Ui.PAPER)
	sb.shadow_color = Ui.RED
	sb.shadow_offset = Vector2(8, 9)
	result_panel.add_theme_stylebox_override("panel", sb)
	result_label = Label.new()
	result_label.add_theme_font_size_override("font_size", 24)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.add_child(result_label)
	result_panel.visible = false
	add_child(result_panel)
	_layout()
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	score_label.position = Vector2(20, vs.y - 92)
	combo_label.position = Vector2(20, vs.y - 54)
	speed_label.size = Vector2(560, 70)
	speed_label.position = Vector2(vs.x - 590, vs.y - 124)
	gear_label.size = Vector2(240, 30)
	gear_label.position = Vector2(vs.x - 260, vs.y - 54)
	rpm_bar.size = Vector2(230, 18)
	rpm_bar.position = Vector2(vs.x - 262, vs.y - 146)
	center_label.size = Vector2(vs.x, 200)
	center_label.position = Vector2(0, vs.y * 0.26)
	warn_label.size = Vector2(vs.x, 40)
	warn_label.position = Vector2(0, vs.y * 0.18)
	popups.size = Vector2(vs.x, 200)
	popups.position = Vector2(0, vs.y * 0.52)
	minimap.position = Vector2(vs.x - 240, 20)
	cup.position = Vector2(vs.x - 110, 256)
	result_panel.position = Vector2(vs.x * 0.5 - 260, vs.y * 0.2)
	result_panel.custom_minimum_size = Vector2(520, 0)


func show_popup(text: String, color: Color) -> void:
	# call-outs land like manga sound effects: big, tilted, popping in
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Ui.title(l, 36, color, 10, Ui.INK)
	popups.add_child(l)
	l.pivot_offset = Vector2(popups.size.x * 0.5, 24)
	l.rotation = deg_to_rad(randf_range(-4.0, 4.0))
	l.scale = Vector2(1.7, 1.7)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.1)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
	if popups.get_child_count() > 4:
		popups.get_child(0).queue_free()


func set_center(text: String, color := Color.WHITE) -> void:
	center_label.text = text
	center_label.add_theme_color_override("font_color", color)


func show_result(text: String) -> void:
	result_label.text = text
	result_panel.visible = true


func update_hud(r) -> void:
	var car: PlayerCar = r.car
	var sm := speed_fx.material as ShaderMaterial
	sm.set_shader_parameter("intensity", clampf((car.speed - 22.0) / 18.0, 0.0, 1.0))
	sm.set_shader_parameter("time_s", Time.get_ticks_msec() / 1000.0)
	info_label.text = "%s  ·  %s" % [r.course.name, Game.MODE_NAMES[r.mode]]
	time_label.text = Game.format_time(r.race_time)
	speed_label.text = "%d km/h" % int(car.speed * 3.6)
	gear_label.text = "GEAR %d" % car.gear
	rpm_bar.value = car.rpm
	score_label.text = "SCORE %d" % car.score
	if car.combo > 1.0:
		combo_label.text = "DRIFT %d  x%.1f" % [int(car.combo), car.combo_mult]
	else:
		combo_label.text = ""
	var tags: Array[String] = []
	if car.hooked:
		tags.append("GUTTER HOOK")
	elif car.in_gutter:
		tags.append("GUTTER")
	if car.blind:
		tags.append("BLIND ATTACK x2")
	if car.drifting:
		tags.append("DRIFT %d°" % int(absf(rad_to_deg(car.slip))))
	status_label.text = "   ".join(tags)
	if r.rival:
		var ds: float = r.rival.s - car.s
		var t_gap := ds / maxf(car.speed, 10.0)
		if ds > 0.0:
			gap_label.text = "%s ahead  %dm  (%.2fs)" % [r.rival.info.name, int(ds), t_gap]
			gap_label.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
		else:
			gap_label.text = "You lead  %dm  (%.2fs)" % [int(-ds), -t_gap]
			gap_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	else:
		gap_label.text = ""
	warn_label.text = "WRONG WAY" if car.wrong_way else ""
