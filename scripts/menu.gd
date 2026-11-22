class_name Menu
extends Control
## Title screen: pick a course and a mode.

signal start_race

var courses: Array
var course_list: ItemList
var mode_buttons: Array[Button] = []
var info: RichTextLabel


func _ready() -> void:
	courses = Courses.all()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.045, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "DOWNHILL STRIKE"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Midnight touge battles on Japan's mountain passes. Downhill only."
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.7, 0.72, 0.8))
	vb.add_child(sub)

	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 24)
	vb.add_child(hb)

	course_list = ItemList.new()
	course_list.custom_minimum_size = Vector2(320, 0)
	course_list.add_theme_font_size_override("font_size", 20)
	for c in courses:
		course_list.add_item("%s   (%s)" % [c.name, c.region])
	course_list.item_selected.connect(_on_course)
	course_list.item_activated.connect(func(_i): _go())
	hb.add_child(course_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	hb.add_child(right)

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	right.add_child(modes)
	for i in Game.MODE_NAMES.size():
		var b := Button.new()
		b.text = Game.MODE_NAMES[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(170, 44)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_on_mode.bind(i))
		modes.add_child(b)
		mode_buttons.append(b)

	info = RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = false
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("normal_font_size", 18)
	info.add_theme_font_size_override("bold_font_size", 26)
	right.add_child(info)

	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 10)
	right.add_child(music_row)
	var pick := Button.new()
	pick.text = "♪ Choose music folder…"
	pick.custom_minimum_size = Vector2(0, 40)
	pick.pressed.connect(_pick_music_folder)
	music_row.add_child(pick)
	var skip := Button.new()
	skip.text = "Next song (M)"
	skip.custom_minimum_size = Vector2(0, 40)
	skip.pressed.connect(func(): Music.next_track())
	music_row.add_child(skip)

	var go := Button.new()
	go.text = "RACE  ▶"
	go.custom_minimum_size = Vector2(0, 56)
	go.add_theme_font_size_override("font_size", 24)
	go.pressed.connect(_go)
	right.add_child(go)

	course_list.select(Game.course_index)
	_on_mode(Game.mode)
	course_list.grab_focus()


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
	var t := Track.new()   # geometry only, for stats
	t.hw = c.width * 0.5
	t.build_centerline(c)
	var best := Game.best_time(c.id, Game.mode)
	var mode_text := ""
	match Game.mode:
		Game.Mode.TIME_ATTACK:
			mode_text = "Solo run against the clock. Drift for points, and chain techniques for big combos."
		Game.Mode.BATTLE:
			mode_text = "Side-by-side downhill battle against the local ace, [b]%s[/b]. First to the bottom wins.\nKill your headlights while chasing to rattle them." % c.rival.name
		Game.Mode.DAWN_DELIVERY:
			mode_text = "The early-morning delivery run. A cup of water sits on the dash: arrive with at least half of it. Smooth is fast."
	var music_line := "Music: %d song(s) in your music folder" % Music.tracks.size() if Music.tracks.size() > 0 else "Music: none yet. Press \"Choose music folder\" and pick the folder with your Eurobeat songs (.mp3/.ogg)"
	info.text = music_line + "\n\n" + "[b]%s[/b]  ·  %s\n%s\n\nLength %.1f km   ·   Drop %d m   ·   Hairpins %d   ·   Width %.1f m\nBest (%s): %s   ·   Best drift score: %d\n\n%s\n\n[color=#9aa]Controls: W/S or ↑/↓ throttle/brake · A/D steer · Space handbrake · L headlights · C camera · R reset · Esc menu · M next song · N music on/off · Gamepad supported\nTechniques: handbrake drift · inertia drift (flick left-right) · brake drift · gutter hook (inside wheels in the hairpin ditch) · blind attack (lights off at night = x2 points)[/color]" % [
		c.name, c.region, c.blurb, t.length / 1000.0, int(t.drop), t.hairpins, c.width,
		Game.MODE_NAMES[Game.mode], Game.format_time(best) if best > 0.0 else "--",
		Game.best_score(c.id), mode_text]
	t.free()


func _pick_music_folder() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.title = "Choose the folder with your Eurobeat songs (.mp3 / .ogg)"
	dlg.dir_selected.connect(func(path: String):
		Music.set_folder(path)
		_refresh()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(900, 600))


func _go() -> void:
	start_race.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		_go()
