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
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
		if pts.size() > 1:
			draw_polyline(pts, Color(0.85, 0.85, 0.85, 0.9), 3.0, true)
			draw_circle(pts[0], 4.0, Color(0.3, 0.6, 1.0))
			draw_circle(pts[pts.size() - 1], 4.0, Color(1.0, 0.25, 0.25))
		if race and race.rival:
			draw_circle(_map(race.rival.global_position), 5.0, race.rival.info.color)
		if race and race.car:
			draw_circle(_map(race.car.global_position), 5.5, Color.WHITE)
			draw_circle(_map(race.car.global_position), 3.0, Color.BLACK)


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
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
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
		draw_polyline(cup_pts, Color.WHITE, 2.0)
		var col := Color(0.6, 1.0, 0.6) if car.cup > 60 else (Color(1.0, 0.85, 0.3) if car.cup > 30 else Color(1, 0.3, 0.3))
		draw_string(ThemeDB.fallback_font, Vector2(4, h - 3), "WATER %d%%" % int(car.cup), HORIZONTAL_ALIGNMENT_CENTER, w - 8, 13, col)


func _label(text: String, size: int, pos: Vector2, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	return l


func build(r) -> void:
	race = r
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
	add_child(rpm_bar)

	center_label = _label("", 96, Vector2.ZERO, HORIZONTAL_ALIGNMENT_CENTER)
	warn_label = _label("", 34, Vector2.ZERO, HORIZONTAL_ALIGNMENT_CENTER)
	warn_label.add_theme_color_override("font_color", Color(1, 0.3, 0.2))

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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.88)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(28)
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
	speed_label.size = Vector2(240, 70)
	speed_label.position = Vector2(vs.x - 260, vs.y - 128)
	gear_label.size = Vector2(240, 30)
	gear_label.position = Vector2(vs.x - 260, vs.y - 54)
	rpm_bar.size = Vector2(220, 10)
	rpm_bar.position = Vector2(vs.x - 240, vs.y - 140)
	center_label.size = Vector2(vs.x, 120)
	center_label.position = Vector2(0, vs.y * 0.3)
	warn_label.size = Vector2(vs.x, 40)
	warn_label.position = Vector2(0, vs.y * 0.18)
	popups.size = Vector2(vs.x, 200)
	popups.position = Vector2(0, vs.y * 0.52)
	minimap.position = Vector2(vs.x - 240, 20)
	cup.position = Vector2(vs.x - 110, 256)
	result_panel.position = Vector2(vs.x * 0.5 - 260, vs.y * 0.2)
	result_panel.custom_minimum_size = Vector2(520, 0)


func show_popup(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	popups.add_child(l)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
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
	if car.in_gutter:
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
