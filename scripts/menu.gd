class_name Menu
extends Control
## Title screen over a live night drive down Mt. Haruna.

signal start_race

const ACCENT := Color(1.0, 0.78, 0.22)
const PANEL := Color(0.02, 0.035, 0.09, 0.82)

var courses: Array
var course_list: ItemList
var mode_buttons: Array[Button] = []
var info: RichTextLabel
var preview: CoursePreview
var now_label: Label
var music_info: Label
var builtin_toggle: CheckButton

# backdrop
var backdrop: Node3D
var bd_track: Track
var bd_car: CarModel
var bd_cam: Camera3D
var bd_s := 400.0
var bd_angle := 0.0


class CoursePreview extends Control:
	var pts := PackedVector2Array()

	func set_course(t: Track) -> void:
		pts.clear()
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in t.P:
			mn = mn.min(Vector2(p.x, p.z))
			mx = mx.max(Vector2(p.x, p.z))
		var span := mx - mn
		var sc := minf((size.x - 20.0) / maxf(span.x, 1.0), (size.y - 20.0) / maxf(span.y, 1.0))
		var off := (size - span * sc) * 0.5 - mn * sc
		for i in range(0, t.P.size(), 3):
			pts.append(Vector2(t.P[i].x, t.P[i].z) * sc + off)
		queue_redraw()

	func _draw() -> void:
		if pts.size() < 2:
			return
		draw_polyline(pts, Color(0, 0, 0, 0.6), 7.0, true)
		draw_polyline(pts, Color(0.85, 0.9, 1.0), 3.0, true)
		draw_circle(pts[0], 6.0, Color(0.3, 0.7, 1.0))
		draw_circle(pts[pts.size() - 1], 6.0, Color(1.0, 0.3, 0.25))


func _panel_style(border := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	if border:
		sb.border_width_left = 4
		sb.border_color = ACCENT
	return sb


func _button(text: String, size_px := 18, h := 42) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", size_px)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.09, 0.18, 0.9)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.12, 0.17, 0.32, 0.95)
	var pressed := normal.duplicate()
	pressed.bg_color = ACCENT.darkened(0.25)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_pressed_color", Color(0.05, 0.05, 0.08))
	return b


func _ready() -> void:
	courses = Courses.all()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()

	# darken the left side so the panels read over the drive
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0.01, 0.04, 0.88))
	grad.set_color(1, Color(0, 0.01, 0.04, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.anchor_right = 0.7
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 22)
	margin.add_child(root)

	# ---- left column: logo, courses, modes
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(430, 0)
	left.add_theme_constant_override("separation", 12)
	root.add_child(left)
	var title := Label.new()
	title.text = "DOWNHILL STRIKE"
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.05, 0.0))
	title.add_theme_constant_override("outline_size", 10)
	left.add_child(title)
	var sub := Label.new()
	sub.text = "MIDNIGHT TOUGE  ·  DOWNHILL ONLY"
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.65, 0.75, 1.0))
	left.add_child(sub)

	var list_panel := PanelContainer.new()
	list_panel.add_theme_stylebox_override("panel", _panel_style())
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(list_panel)
	course_list = ItemList.new()
	course_list.add_theme_font_size_override("font_size", 21)
	course_list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(ACCENT, 0.25)
	sel.border_width_left = 3
	sel.border_color = ACCENT
	course_list.add_theme_stylebox_override("selected", sel)
	course_list.add_theme_stylebox_override("selected_focus", sel)
	course_list.add_theme_constant_override("v_separation", 10)
	for c in courses:
		var traced := " ★" if c.has("data") else ""
		course_list.add_item("%s%s\n   %s" % [c.name, traced, c.region])
	course_list.item_selected.connect(_on_course)
	course_list.item_activated.connect(func(_i): _go())
	list_panel.add_child(course_list)

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	left.add_child(modes)
	for i in Game.MODE_NAMES.size():
		var b := _button(Game.MODE_NAMES[i], 16, 44)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_mode.bind(i))
		modes.add_child(b)
		mode_buttons.append(b)

	# ---- right column: course card, music, race button
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	root.add_child(right)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style())
	right.add_child(card)
	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 16)
	card.add_child(card_row)
	preview = CoursePreview.new()
	preview.custom_minimum_size = Vector2(200, 230)
	card_row.add_child(preview)
	info = RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("normal_font_size", 16)
	info.add_theme_font_size_override("bold_font_size", 28)
	card_row.add_child(info)

	var music := PanelContainer.new()
	music.add_theme_stylebox_override("panel", _panel_style(false))
	right.add_child(music)
	var mv := VBoxContainer.new()
	music.add_child(mv)
	now_label = Label.new()
	now_label.add_theme_font_size_override("font_size", 18)
	now_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	mv.add_child(now_label)
	music_info = Label.new()
	music_info.add_theme_font_size_override("font_size", 13)
	music_info.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	music_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	mv.add_child(music_info)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	mv.add_child(mrow)
	var pick := _button("♪ Add my songs (choose folder)…", 15, 36)
	pick.pressed.connect(_pick_music_folder)
	mrow.add_child(pick)
	var skip := _button("Next song  (M)", 15, 36)
	skip.pressed.connect(func():
		Music.in_menu = false
		Music.next_track())
	mrow.add_child(skip)
	builtin_toggle = CheckButton.new()
	builtin_toggle.text = "Built-in Eurobeat"
	builtin_toggle.button_pressed = Music.use_builtin
	builtin_toggle.toggled.connect(func(on: bool):
		Music.set_builtin(on)
		_refresh_music())
	mrow.add_child(builtin_toggle)

	var go := _button("RACE   ▶", 30, 64)
	var gs := StyleBoxFlat.new()
	gs.bg_color = ACCENT
	gs.set_corner_radius_all(8)
	go.add_theme_stylebox_override("normal", gs)
	var gh := gs.duplicate()
	gh.bg_color = ACCENT.lightened(0.2)
	go.add_theme_stylebox_override("hover", gh)
	go.add_theme_stylebox_override("focus", gh)
	go.add_theme_color_override("font_color", Color(0.08, 0.05, 0.02))
	go.add_theme_color_override("font_hover_color", Color(0.08, 0.05, 0.02))
	go.add_theme_color_override("font_focus_color", Color(0.08, 0.05, 0.02))
	go.pressed.connect(_go)
	right.add_child(go)

	var help := Label.new()
	help.text = "W/S throttle·brake   A/D steer   Space handbrake   L lights   C camera   R reset   Esc menu   M next song   N music on/off"
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", Color(0.6, 0.66, 0.8))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(help)

	Music.now_playing.connect(func(_t): _refresh_music())
	course_list.select(Game.course_index)
	_on_mode(Game.mode)
	_refresh_music()
	course_list.grab_focus()


func _build_backdrop() -> void:
	backdrop = Node3D.new()
	add_child(backdrop)
	Race.build_environment(backdrop, false)
	bd_track = Track.new()
	backdrop.add_child(bd_track)
	bd_track.build(courses[0])
	bd_car = CarModel.create("hatch", Color(0.96, 0.96, 0.94))
	backdrop.add_child(bd_car)
	bd_cam = Camera3D.new()
	bd_cam.far = 12000.0
	bd_cam.fov = 55.0
	backdrop.add_child(bd_cam)
	bd_cam.current = true


func _process(dt: float) -> void:
	if bd_track == null:
		return
	# the car cruises down the pass; the camera swings slowly around it
	bd_s += 16.0 * dt
	if bd_s > bd_track.finish_s - 50.0:
		bd_s = 200.0
	var lat := clampf(bd_track.curvature_at(bd_s + 20.0) * 120.0, -1.0, 1.0) * 1.6
	var p := bd_track.point_at(bd_s, lat)
	var d := bd_track.dir_at(bd_s)
	var k := bd_track.curvature_at(bd_s)
	var drift := clampf(absf(k) * 14.0, 0.0, 0.5) * signf(k)
	bd_car.transform = Transform3D(Basis.looking_at(d, Vector3.UP).rotated(Vector3.UP, -drift), p)
	bd_car.update_visual(dt, -drift * 0.6, 16.0, false)
	bd_angle += dt * 0.12
	var side := d.cross(Vector3.UP)
	var offset := (-d * cos(bd_angle) * 8.0 + side * sin(bd_angle) * 8.0) + Vector3.UP * 3.0
	bd_cam.global_position = bd_cam.global_position.lerp(p + offset, 1.0 - exp(-3.0 * dt)) if bd_cam.global_position != Vector3.ZERO else p + offset
	bd_cam.look_at(p + Vector3.UP * 0.8 + d * 3.0, Vector3.UP)


func _on_course(i: int) -> void:
	Game.course_index = i
	_refresh()


func _on_mode(i: int) -> void:
	Game.mode = i
	for k in mode_buttons.size():
		mode_buttons[k].button_pressed = k == i
	_refresh()


func _refresh() -> void:
	var c: Dictionary = courses[Game.course_index]
	var t := Track.new()   # geometry only, for stats and the map preview
	t.hw = c.width * 0.5
	t.build_centerline(c)
	preview.set_course(t)
	var best := Game.best_time(c.id, Game.mode)
	var mode_text := ""
	match Game.mode:
		Game.Mode.TIME_ATTACK:
			mode_text = "Solo run against the clock. Drift for points and chain techniques for big combos."
		Game.Mode.BATTLE:
			mode_text = "Side-by-side downhill battle against the local ace, [color=#ffd36a]%s[/color]. First to the bottom wins. Kill your headlights while chasing to rattle them." % c.rival.name
		Game.Mode.DAWN_DELIVERY:
			mode_text = "The early-morning delivery run. A cup of water sits on the dash: arrive with at least half of it. Smooth is fast."
	var traced := "" if c.has("data") else "\n[color=#e8a]Layout still a placeholder: real map tracing coming.[/color]"
	info.text = "[b]%s[/b]  [color=#9ab]%s[/color]\n%s%s\n\n[color=#ffd36a]%.1f km   ·   %d m drop   ·   %d hairpins[/color]\nBest: %s   ·   Drift record: %d\n\n%s" % [
		c.name, c.region, c.blurb, traced, t.length / 1000.0, int(t.drop), t.hairpins,
		Game.format_time(best) if best > 0.0 else "--", Game.best_score(c.id), mode_text]
	t.free()


func _refresh_music() -> void:
	if now_label == null:
		return
	now_label.text = "♪  " + (Music.current.get("title", "—") if Music.enabled else "Music off")
	var own := Music.own_count()
	music_info.text = ("%d of your own songs  ·  " % own if own > 0 else "Add your own Eurobeat (.mp3/.ogg) with the button below  ·  ") + \
		("built-in CC0 racing Eurobeat by MintoDog & Fupi" if Music.use_builtin else "built-in tracks off")


func _pick_music_folder() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.title = "Choose the folder with your Eurobeat songs (.mp3 / .ogg)"
	dlg.dir_selected.connect(func(path: String):
		Music.set_folder(path)
		_refresh_music()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(900, 600))


func _go() -> void:
	start_race.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		_go()
