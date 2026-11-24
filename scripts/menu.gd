class_name Menu
extends Control
## Front end over a live night drive down Mt. Haruna.
##   Main:     Start · Cars · Drift School · Exit
##   Start:    choose the kind of race (Campaign, Battle, Time Attack, Score Attack, Water Cup)
##   Courses:  then choose the mountain
##   Campaign: story battles one by one
##   Cars:     3D showroom with stats; pick the car you drive

signal start_race

const ACCENT := Color(1.0, 0.78, 0.22)
const PANEL := Color(0.02, 0.035, 0.09, 0.84)
const UI_SIZE := Vector2(1600, 960)

var courses: Array
var screens := {}
var screen := ""
var _ui: Control
var _cars_return := "main"

# course screen
var course_list: ItemList
var course_info: RichTextLabel
var course_preview: CoursePreview
var course_mode_label: Label
# campaign screen
var stage_list: ItemList
var stage_info: RichTextLabel
var stage_preview: CoursePreview
var stage_go: Button
# cars screen
var car_list: ItemList
var car_name: Label
var car_note: Label
var car_status: Label
var car_bars: StatBars
var car_select: Button
var show_vp: SubViewport
var show_root: Node3D
var show_car: CarModel
var show_cam: Camera3D
var orbit_yaw := 0.7
var orbit_pitch := 0.22
var orbit_dist := 6.2
var _dragging := false
var _idle := 0.0
var garage_idx := 0
# music
var now_label: Label
var music_info: Label

# backdrop
var backdrop: Node3D
var bd_track: Track
var bd_car: CarModel
var bd_cam: Camera3D
var bd_s := 400.0
var bd_angle := 0.0


class StatBars extends Control:
	var values: Dictionary = {}

	func _draw() -> void:
		var names := values.keys()
		var row_h := size.y / maxf(names.size(), 1)
		var font := ThemeDB.fallback_font
		for i in names.size():
			var y := i * row_h
			draw_string(font, Vector2(0, y + row_h * 0.7), names[i], HORIZONTAL_ALIGNMENT_LEFT, 130, 17, Color(0.75, 0.8, 0.9))
			var x0 := 140.0
			var w := size.x - x0 - 8.0
			draw_rect(Rect2(x0, y + row_h * 0.25, w, row_h * 0.5), Color(0.1, 0.12, 0.2))
			var v: float = clampf(values[names[i]] / 10.0, 0.0, 1.0)
			draw_rect(Rect2(x0, y + row_h * 0.25, w * v, row_h * 0.5), Color(1.0, 0.78, 0.22).lerp(Color(1.0, 0.4, 0.2), v * 0.5))


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


# ------------------------------------------------------------------ widgets

func _panel_style(border := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	if border:
		sb.border_width_left = 4
		sb.border_color = ACCENT
	return sb


func _panel(border := true) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(border))
	return p


func _label(text: String, size_px: int, color := Color(0.9, 0.93, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, size_px := 18, h := 42) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", size_px)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.09, 0.18, 0.92)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(10)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.14, 0.2, 0.38, 0.96)
	hover.border_width_left = 4
	hover.border_color = ACCENT
	var pressed := normal.duplicate()
	pressed.bg_color = ACCENT.darkened(0.25)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_color_override("font_pressed_color", Color(0.05, 0.05, 0.08))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.55))
	return b


func _big_button(text: String, size_px := 30, h := 64) -> Button:
	var go := _button(text, size_px, h)
	var gs := StyleBoxFlat.new()
	gs.bg_color = ACCENT
	gs.set_corner_radius_all(8)
	go.add_theme_stylebox_override("normal", gs)
	var gh := gs.duplicate()
	gh.bg_color = ACCENT.lightened(0.2)
	go.add_theme_stylebox_override("hover", gh)
	go.add_theme_stylebox_override("focus", gh)
	var gd := gs.duplicate()
	gd.bg_color = Color(0.3, 0.3, 0.32)
	go.add_theme_stylebox_override("disabled", gd)
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		go.add_theme_color_override(k, Color(0.08, 0.05, 0.02))
	return go


func _list() -> ItemList:
	var l := ItemList.new()
	l.add_theme_font_size_override("font_size", 21)
	l.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(ACCENT, 0.25)
	sel.border_width_left = 3
	sel.border_color = ACCENT
	l.add_theme_stylebox_override("selected", sel)
	l.add_theme_stylebox_override("selected_focus", sel)
	l.add_theme_constant_override("v_separation", 10)
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return l


## Back button + title + subtitle row; returns the subtitle label.
func _header(parent: Control, title: String, sub: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	var back := _button("◀  BACK", 18, 48)
	back.custom_minimum_size.x = 150
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_back)
	row.add_child(back)
	var col := VBoxContainer.new()
	row.add_child(col)
	var t := _label(title, 40, ACCENT)
	t.add_theme_color_override("font_outline_color", Color(0.3, 0.05, 0.0))
	t.add_theme_constant_override("outline_size", 8)
	col.add_child(t)
	var s := _label(sub, 16, Color(0.65, 0.75, 1.0))
	col.add_child(s)
	return s


func _screen(name: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	_ui.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	margin.add_child(v)
	screens[name] = margin
	margin.visible = false
	return v


func _fit_ui() -> void:
	if not is_instance_valid(_ui):
		return
	var vs := get_viewport().get_visible_rect().size
	var k := minf(vs.x / UI_SIZE.x, vs.y / UI_SIZE.y)
	_ui.scale = Vector2(k, k)
	_ui.position = Vector2.ZERO
	_ui.size = vs / k


# ------------------------------------------------------------------ build

func _ready() -> void:
	courses = Courses.all()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0.01, 0.04, 0.9))
	grad.set_color(1, Color(0, 0.01, 0.04, 0.1))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_ui = Control.new()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	get_viewport().size_changed.connect(_fit_ui)
	_fit_ui.call_deferred()

	_build_main()
	_build_modes()
	_build_courses()
	_build_campaign()
	_build_cars()
	Music.now_playing.connect(func(_t): _refresh_music())
	_refresh_music()
	garage_idx = maxi(Cars.ORDER.find(Game.selected_car), 0)
	_show(Game.menu_screen if screens.has(Game.menu_screen) else "main")


func _build_main() -> void:
	var v := _screen("main")
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 90)
	v.add_child(top)
	var title := _label("DOWNHILL STRIKE", 92, ACCENT)
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.05, 0.0))
	title.add_theme_constant_override("outline_size", 14)
	v.add_child(title)
	v.add_child(_label("MIDNIGHT TOUGE  ·  DOWNHILL ONLY", 22, Color(0.65, 0.75, 1.0)))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	v.add_child(gap)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(460, 0)
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(col)
	var start := _big_button("START", 34, 74)
	start.pressed.connect(func(): _show("modes"))
	col.add_child(start)
	var cars := _button("CARS", 28, 64)
	cars.pressed.connect(func():
		_cars_return = "main"
		_show("cars"))
	col.add_child(cars)
	var school := _button("DRIFT SCHOOL", 28, 64)
	school.pressed.connect(func():
		Game.mode = Game.Mode.TUTORIAL
		Game.course_index = 0
		_go())
	col.add_child(school)
	if RenderingServer.get_rendering_device() != null:
		var gfx := _button("GRAPHICS: " + Game.QUALITY_NAMES[Game.quality], 22, 54)
		gfx.pressed.connect(func():
			Game.set_quality((Game.quality + 1) % 3)
			gfx.text = "GRAPHICS: " + Game.QUALITY_NAMES[Game.quality])
		col.add_child(gfx)
		# art style: the cartoon look, or the heavier photo-style renderer
		if Mats.has_realistic():
			var style := _button("STYLE: " + ("REALISTIC" if Mats.realistic else "ANIME"), 22, 54)
			style.pressed.connect(func():
				Game.set_realistic(not Mats.realistic)
				get_tree().reload_current_scene())
			col.add_child(style)
	if not OS.has_feature("web"):
		var quit := _button("EXIT", 28, 64)
		quit.pressed.connect(func(): get_tree().quit())
		col.add_child(quit)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	# music bar along the bottom
	var music := _panel(false)
	music.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	music.custom_minimum_size = Vector2(760, 0)
	v.add_child(music)
	var mv := VBoxContainer.new()
	music.add_child(mv)
	now_label = _label("", 18, Color(0.75, 0.88, 1.0))
	mv.add_child(now_label)
	music_info = _label("", 13, Color(0.6, 0.65, 0.75))
	music_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	mv.add_child(music_info)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	mv.add_child(mrow)
	if not OS.has_feature("web"):
		var pick := _button("♪ Add my songs (choose folder)…", 15, 36)
		pick.pressed.connect(_pick_music_folder)
		mrow.add_child(pick)
	var skip := _button("Next song  (M)", 15, 36)
	skip.pressed.connect(func():
		Music.in_menu = false
		Music.next_track())
	mrow.add_child(skip)
	var builtin := CheckButton.new()
	builtin.text = "Built-in Eurobeat"
	builtin.button_pressed = Music.use_builtin
	builtin.toggled.connect(func(on: bool):
		Music.set_builtin(on)
		_refresh_music())
	mrow.add_child(builtin)
	v.add_child(_label("Roads: © OpenStreetMap contributors (ODbL) · terrain & aerial: 国土地理院 (GSI)", 11, Color(0.5, 0.55, 0.65)))


const MODE_CARDS := [
	[Game.Mode.CAMPAIGN, "CAMPAIGN", "One-on-one battles in story order. New challengers on every mountain; beat them to win their cars."],
	[Game.Mode.BATTLE, "DOWNHILL BATTLE", "A race against the local ace of the mountain you pick. First to the bottom wins."],
	[Game.Mode.TIME_ATTACK, "TIME ATTACK", "Solo run against the clock. Every crash costs time."],
	[Game.Mode.SCORE_ATTACK, "SCORE ATTACK", "Solo run for drift points. Chain drifts, gutter hooks and blind attacks for big combos."],
	[Game.Mode.DAWN_DELIVERY, "WATER CUP", "The dawn delivery run with a cup of water on the dash. Arrive with half of it left. Smooth is fast."],
]


func _build_modes() -> void:
	var v := _screen("modes")
	_header(v, "CHOOSE YOUR RACE", "What kind of run tonight?")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	v.add_child(grid)
	for card in MODE_CARDS:
		var b := _button("", 20, 150)
		b.custom_minimum_size = Vector2(700, 150)
		var inner := VBoxContainer.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 26
		inner.offset_top = 20
		inner.offset_right = -20
		b.add_child(inner)
		var t := _label(card[1], 32, ACCENT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(t)
		var d := _label(card[2], 17, Color(0.85, 0.88, 0.95))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(d)
		var m: int = card[0]
		b.pressed.connect(func():
			Game.mode = m
			_show("campaign" if m == Game.Mode.CAMPAIGN else "courses"))
		grid.add_child(b)


func _build_courses() -> void:
	var v := _screen("courses")
	course_mode_label = _header(v, "CHOOSE THE MOUNTAIN", "")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var lp := _panel()
	lp.custom_minimum_size = Vector2(470, 0)
	row.add_child(lp)
	course_list = _list()
	for c in courses:
		var traced := " ★" if c.has("data") else ""
		course_list.add_item("%s%s\n   %s" % [c.name, traced, c.region])
	course_list.item_selected.connect(func(i: int):
		Game.course_index = i
		_refresh_course())
	course_list.item_activated.connect(func(_i): _go())
	lp.add_child(course_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 16)
	row.add_child(right)
	var card := _panel()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(card)
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 18)
	card.add_child(cr)
	course_preview = CoursePreview.new()
	course_preview.custom_minimum_size = Vector2(300, 340)
	cr.add_child(course_preview)
	course_info = RichTextLabel.new()
	course_info.bbcode_enabled = true
	course_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	course_info.add_theme_font_size_override("normal_font_size", 18)
	course_info.add_theme_font_size_override("bold_font_size", 32)
	cr.add_child(course_info)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	right.add_child(brow)
	var change := _button("CHANGE CAR", 20, 64)
	change.custom_minimum_size.x = 220
	change.pressed.connect(func():
		_cars_return = "courses"
		_show("cars"))
	brow.add_child(change)
	var go := _big_button("RACE   ▶")
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(_go)
	brow.add_child(go)


func _build_campaign() -> void:
	var v := _screen("campaign")
	_header(v, "CAMPAIGN", "Beat each challenger to unlock the next. Winning puts their car in your garage.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var lp := _panel()
	lp.custom_minimum_size = Vector2(560, 0)
	row.add_child(lp)
	stage_list = _list()
	stage_list.add_theme_font_size_override("font_size", 19)
	stage_list.item_selected.connect(func(i: int):
		Game.campaign_stage = i
		_refresh_stage())
	stage_list.item_activated.connect(func(i: int):
		if i <= Game.campaign_cleared():
			_go())
	lp.add_child(stage_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 16)
	row.add_child(right)
	var card := _panel()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(card)
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 18)
	card.add_child(cr)
	stage_preview = CoursePreview.new()
	stage_preview.custom_minimum_size = Vector2(260, 300)
	cr.add_child(stage_preview)
	stage_info = RichTextLabel.new()
	stage_info.bbcode_enabled = true
	stage_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_info.add_theme_font_size_override("normal_font_size", 18)
	stage_info.add_theme_font_size_override("bold_font_size", 30)
	cr.add_child(stage_info)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	right.add_child(brow)
	stage_go = _big_button("RACE   ▶")
	stage_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_go.pressed.connect(_go)
	brow.add_child(stage_go)


func _build_cars() -> void:
	var v := _screen("cars")
	_header(v, "GARAGE", "Drag the car to look around it · scroll to zoom")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var lp := _panel()
	lp.custom_minimum_size = Vector2(380, 0)
	row.add_child(lp)
	car_list = _list()
	car_list.add_theme_font_size_override("font_size", 19)
	car_list.item_selected.connect(func(i: int):
		garage_idx = i
		_refresh_car())
	lp.add_child(car_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	row.add_child(right)
	# the showroom: a separate little 3D world with the car on a turntable
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.custom_minimum_size = Vector2(0, 400)
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	svc.gui_input.connect(_showroom_input)
	right.add_child(svc)
	show_vp = SubViewport.new()
	show_vp.own_world_3d = true
	show_vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(show_vp)
	_build_showroom()
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 8)
	right.add_child(views)
	for pair in [["FRONT", 0.0, 0.12], ["3/4 FRONT", 0.7, 0.22], ["SIDE", 1.5708, 0.1], ["3/4 REAR", 2.4, 0.22], ["REAR", 3.1416, 0.12], ["TOP", 0.7, 1.2]]:
		var vb := _button(pair[0], 15, 38)
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var yaw: float = pair[1]
		var pitch: float = pair[2]
		vb.pressed.connect(func():
			orbit_yaw = yaw
			orbit_pitch = pitch
			_idle = -3.0)
		views.add_child(vb)
	var info := _panel()
	right.add_child(info)
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 20)
	info.add_child(ih)
	var iv := VBoxContainer.new()
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iv.add_theme_constant_override("separation", 8)
	ih.add_child(iv)
	car_name = _label("", 30, ACCENT)
	iv.add_child(car_name)
	car_note = _label("", 16, Color(0.75, 0.8, 0.9))
	car_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	iv.add_child(car_note)
	car_status = _label("", 17)
	car_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	iv.add_child(car_status)
	car_select = _big_button("DRIVE THIS CAR", 24, 56)
	car_select.pressed.connect(func():
		Game.select_car(Cars.ORDER[garage_idx])
		_refresh_car())
	iv.add_child(car_select)
	car_bars = StatBars.new()
	car_bars.custom_minimum_size = Vector2(520, 170)
	ih.add_child(car_bars)


func _build_showroom() -> void:
	show_root = Node3D.new()
	show_vp.add_child(show_root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.75)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	show_root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-45), deg_to_rad(35), 0)
	key.light_energy = 1.2
	key.shadow_enabled = true
	show_root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(200), 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.6, 0.7, 1.0)
	show_root.add_child(rim)
	# turntable floor with a glowing rim
	var floor_m := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 4.2
	disc.bottom_radius = 4.3
	disc.height = 0.08
	disc.radial_segments = 64
	floor_m.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.09, 0.1, 0.13)
	fm.roughness = 0.25
	fm.metallic = 0.4
	floor_m.material_override = fm
	floor_m.position.y = -0.04
	show_root.add_child(floor_m)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 4.15
	tor.outer_radius = 4.3
	tor.rings = 64
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.albedo_color = ACCENT
	rm.emission_enabled = true
	rm.emission = ACCENT
	rm.emission_energy_multiplier = 1.5
	ring.material_override = rm
	show_root.add_child(ring)
	show_cam = Camera3D.new()
	show_cam.fov = 40.0
	show_root.add_child(show_cam)
	show_cam.current = true


func _showroom_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			orbit_dist = maxf(3.6, orbit_dist - 0.4)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			orbit_dist = minf(11.0, orbit_dist + 0.4)
		_idle = -3.0
	elif e is InputEventMouseMotion and _dragging:
		var mm := e as InputEventMouseMotion
		orbit_yaw -= mm.relative.x * 0.008
		orbit_pitch = clampf(orbit_pitch + mm.relative.y * 0.006, 0.02, 1.35)
		_idle = -3.0
	elif e is InputEventScreenDrag:
		var sd := e as InputEventScreenDrag
		orbit_yaw -= sd.relative.x * 0.008
		orbit_pitch = clampf(orbit_pitch + sd.relative.y * 0.006, 0.02, 1.35)
		_idle = -3.0


# ------------------------------------------------------------------ screens

func _show(name: String) -> void:
	screen = name
	if name != "cars":
		Game.menu_screen = name
	for k in screens:
		screens[k].visible = k == name
	if bd_car:
		bd_car.visible = name != "cars"
	match name:
		"courses":
			course_mode_label.text = Game.MODE_NAMES[Game.mode]
			course_list.select(Game.course_index)
			_refresh_course()
			course_list.grab_focus()
		"campaign":
			_fill_stages()
			stage_list.grab_focus()
		"cars":
			_fill_cars()
			car_list.grab_focus()


func _back() -> void:
	match screen:
		"courses", "campaign":
			_show("modes")
		"cars":
			_show(_cars_return)
		_:
			_show("main")


func _refresh_course() -> void:
	var c: Dictionary = courses[Game.course_index]
	var t := Track.new()
	t.hw = c.width * 0.5
	t.build_centerline(c)
	course_preview.set_course(t)
	var best := Game.best_time(c.id, Game.mode)
	var what := ""
	match Game.mode:
		Game.Mode.BATTLE:
			what = "Rival: [color=#ffd36a]%s[/color] in the %s. Win to take the car." % [c.rival.name, Cars.get_car(c.rival.car).name]
		Game.Mode.TIME_ATTACK:
			what = "Best time: %s" % (Game.format_time(best) if best > 0.0 else "--")
		Game.Mode.SCORE_ATTACK:
			what = "Best drift score: %d" % Game.best_score(c.id)
		Game.Mode.DAWN_DELIVERY:
			what = "Keep at least half the water in the cup."
	var traced := "" if c.has("data") else "\n[color=#e8a]Layout still a placeholder: real map tracing coming.[/color]"
	course_info.text = "[b]%s[/b]  [color=#9ab]%s[/color]\n%s%s\n\n[color=#ffd36a]%.1f km   ·   %d m drop   ·   %d hairpins[/color]\n\n%s\n\nYour car: %s" % [
		c.name, c.region, c.blurb, traced, t.length / 1000.0, int(t.drop), t.hairpins, what, Cars.get_car(Game.selected_car).name]
	t.free()


func _fill_stages() -> void:
	stage_list.clear()
	var cleared := Game.campaign_cleared()
	for i in Campaign.STAGES.size():
		var st: Dictionary = Campaign.STAGES[i]
		var mark := "✔ " if i < cleared else ("▶ " if i == cleared else "✕ ")
		var crs: Dictionary = courses[st.course]
		stage_list.add_item("%s%d. %s\n     %s · %s" % [mark, i + 1, st.title, crs.name, Cars.get_car(st.rival.car).name])
		if i > cleared:
			stage_list.set_item_custom_fg_color(i, Color(0.5, 0.53, 0.6))
	Game.campaign_stage = clampi(Game.campaign_stage, 0, mini(cleared, Campaign.STAGES.size() - 1))
	stage_list.select(Game.campaign_stage)
	_refresh_stage()


func _refresh_stage() -> void:
	var i := Game.campaign_stage
	var st := Campaign.stage(i)
	var c: Dictionary = courses[st.course]
	var t := Track.new()
	t.hw = c.width * 0.5
	t.build_centerline(c)
	stage_preview.set_course(t)
	var locked := i > Game.campaign_cleared()
	var rc := Cars.get_car(st.rival.car)
	var team: String = st.rival.team
	stage_info.text = "[b]%d. %s[/b]\n[color=#9ab]%s  ·  %.1f km  ·  %d hairpins[/color]\n\n%s\n\nRival: [color=#ffd36a]%s[/color]%s\nCar: [color=#ffd36a]%s[/color]  (%d hp · %d kg · %s)\n\nYou drive: %s%s" % [
		i + 1, st.title, c.name, t.length / 1000.0, t.hairpins, st.intro, st.rival.name,
		("  ·  " + team) if team != "local" and team != "unknown" else "",
		rc.name, rc.hp, rc.kg, rc.drive, Cars.get_car(Campaign.HERO_CAR).name + "  (the hero's car, always)",
		"\n\n[color=#e88]Locked: win the stage before this one.[/color]" if locked else ""]
	stage_go.disabled = locked
	t.free()


func _fill_cars() -> void:
	car_list.clear()
	for id in Cars.ORDER:
		car_list.add_item("")
		if not Game.is_unlocked(id):
			car_list.set_item_custom_fg_color(car_list.item_count - 1, Color(0.5, 0.53, 0.6))
	garage_idx = clampi(garage_idx, 0, Cars.ORDER.size() - 1)
	car_list.select(garage_idx)
	_refresh_car()


func _refresh_car() -> void:
	var id: String = Cars.ORDER[garage_idx]
	var c := Cars.get_car(id)
	for i in Cars.ORDER.size():
		var oid: String = Cars.ORDER[i]
		var tag := "   ● driving" if oid == Game.selected_car else ""
		car_list.set_item_text(i, ("" if Game.is_unlocked(oid) else "✕  ") + Cars.get_car(oid).name + tag)
	car_name.text = c.name
	car_note.text = "%s\n%d hp  ·  %d kg  ·  %s" % [c.note, c.hp, c.kg, c.drive]
	car_bars.values = Cars.bars(id)
	car_bars.queue_redraw()
	if Game.is_unlocked(id):
		var sel := id == Game.selected_car
		car_status.text = "✔ Selected: this is the car you race" if sel else "In your garage"
		car_status.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
		car_select.disabled = sel
		car_select.text = "DRIVING THIS CAR" if sel else "DRIVE THIS CAR"
	else:
		var how := ""
		for i in Campaign.STAGES.size():
			var st: Dictionary = Campaign.STAGES[i]
			if st.rival.car == id:
				how = "Win campaign stage %d, \"%s\", to take this car." % [i + 1, st.title]
				break
		if how == "":
			for crs in courses:
				if crs.rival.get("car", "") == id:
					how = "Beat %s on %s in a Downhill Battle to win this car." % [crs.rival.name, crs.name]
		if how == "":
			how = {"180sx": "Win 3 downhill battles to unlock.", "s2000": "Win 6 downhill battles to unlock."}.get(id, "Locked.")
		car_status.text = "LOCKED. " + how
		car_status.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
		car_select.disabled = true
		car_select.text = "LOCKED"
	# the car on the turntable
	if show_car:
		show_car.queue_free()
	show_car = CarModel.for_car(id)
	show_root.add_child(show_car)
	show_car.set_lights(true, true)
	show_car.update_visual(0.1, 0.0, 0.0, false)


# ------------------------------------------------------------------ backdrop + loop

func _build_backdrop() -> void:
	backdrop = Node3D.new()
	add_child(backdrop)
	Race.build_environment(backdrop, false)
	bd_track = Track.new()
	backdrop.add_child(bd_track)
	bd_track.build(courses[0])
	bd_car = CarModel.for_car(Game.selected_car)
	backdrop.add_child(bd_car)
	bd_cam = Camera3D.new()
	bd_cam.far = 12000.0
	bd_cam.fov = 55.0
	backdrop.add_child(bd_cam)
	bd_cam.current = true


func _process(dt: float) -> void:
	# showroom orbit camera (turns slowly by itself when left alone)
	if show_cam and screen == "cars":
		_idle += dt
		if _idle > 2.0 and not _dragging:
			orbit_yaw += dt * 0.25
		var target := Vector3(0, 0.6, 0)
		var off := Vector3(sin(orbit_yaw) * cos(orbit_pitch), sin(orbit_pitch), -cos(orbit_yaw) * cos(orbit_pitch)) * orbit_dist
		show_cam.position = show_cam.position.lerp(target + off, 1.0 - exp(-10.0 * dt))
		show_cam.look_at(target, Vector3.UP)
	if bd_track == null:
		return
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


func _refresh_music() -> void:
	if now_label == null:
		return
	now_label.text = "♪  " + (Music.current.get("title", "—") if Music.enabled else "Music off")
	var own := Music.own_count()
	music_info.text = ("%d of your own songs  ·  " % own if own > 0 else "") + \
		("built-in CC0 racing Eurobeat by MintoDog & Fupi" if Music.use_builtin else "built-in tracks off") + \
		"   ·   M next song · N music on/off"


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
	if Game.mode == Game.Mode.CAMPAIGN and Game.campaign_stage > Game.campaign_cleared():
		return
	start_race.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu") or event.is_action_pressed("ui_cancel"):
		if screen != "main":
			_back()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm") and screen in ["courses", "campaign"]:
		_go()
