extends Node
## Soundtrack (autoload "Music").
## Built-in CC0 racing Eurobeat (assets/music, see CREDITS.md) is shuffled
## together with the player's own songs from any folder they choose in the menu
## (plus <project>/music and user://music). Built-in tracks have a faster
## "Climax" version that kicks in for the last stretch of a run.
## Keys: M = next song, N = music on/off.

signal now_playing(title: String)

const EXTENSIONS := ["ogg", "mp3"]
const BUILTIN := [
	["Fever Stadium", "fever_stadium_bpm165", "fever_stadium_climax_bpm180"],
	["Darkness Road", "darkness_road_remake_bpm165", "darkness_road_climax_remake_bpm180"],
	["Hot Roadway", "hot_roadway_remake_bpm160", "hot_roadway_climax_remake_bpm175"],
	["Pure Raceway", "pure_raceway_bpm160", "pure_raceway_climax_bpm175"],
	["Sky Blue Street", "sky_blue_street_bpm165", "sky_blue_street_climax_bpm180"],
	["Neon Sign Circuit", "neon_sign_circuit_remake_bpm145", "neon_sign_circuit_climax_remake_bpm160"],
	["Blossom Mountain", "blossom_mountain_remake_bpm140", "blossom_mountain_climax_remake_bpm155"],
	["Cool Highway", "cool_highway_remake_bpm140", "cool_highway_climax_remake_bpm155"],
	["Technomania101", "technomania101_notempochange", ""],
]
const MENU_TRACK := "res://assets/music/racing_game_menu_bpm165.ogg"

var player: AudioStreamPlayer
var tracks: Array = []          # each: {title, path, climax}
var order: Array = []
var enabled := true
var use_builtin := true
var current: Dictionary = {}
var custom_folder := ""
var in_menu := true
var climax := false
var _plays := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	player.volume_db = -7.0
	add_child(player)
	player.finished.connect(_on_finished)
	_bind("music_next", KEY_M)
	_bind("music_toggle", KEY_N)
	DirAccess.make_dir_recursive_absolute("user://music")
	custom_folder = Game.records.get_value("music", "folder", "")
	use_builtin = Game.records.get_value("music", "builtin", true)
	rescan()
	play_menu()


func _bind(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		var e := InputEventKey.new()
		e.physical_keycode = key
		InputMap.action_add_event(action, e)


# ---------------------------------------------------------------- library

func folders() -> Array[String]:
	var out: Array[String] = ["user://music"]
	if custom_folder != "":
		out.append(custom_folder)
	if OS.has_feature("editor"):
		out.append(ProjectSettings.globalize_path("res://music"))
	else:
		out.append(OS.get_executable_path().get_base_dir().path_join("music"))
	return out


func set_folder(path: String) -> void:
	custom_folder = path
	Game.records.set_value("music", "folder", path)
	Game.records.save(Game.SAVE_PATH)
	rescan()


func set_builtin(on: bool) -> void:
	use_builtin = on
	Game.records.set_value("music", "builtin", on)
	Game.records.save(Game.SAVE_PATH)
	rescan()


func own_count() -> int:
	var n := 0
	for t in tracks:
		if t.climax == "" and not t.path.begins_with("res://"):
			n += 1
	return n


func rescan() -> void:
	tracks.clear()
	if use_builtin:
		for b in BUILTIN:
			tracks.append({"title": b[0], "path": "res://assets/music/%s.ogg" % b[1],
				"climax": ("res://assets/music/%s.ogg" % b[2]) if b[2] != "" else ""})
	for dir_path in folders():
		_scan(dir_path, 0)
	order.clear()


func _scan(dir_path: String, depth: int) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null or depth > 3:
		return
	for f in dir.get_files():
		if f.get_extension().to_lower() in EXTENSIONS:
			tracks.append({"title": f.get_basename(), "path": dir_path.path_join(f), "climax": ""})
	for sub in dir.get_directories():
		_scan(dir_path.path_join(sub), depth + 1)


func _load(path: String) -> AudioStream:
	if path.begins_with("res://"):
		return load(path)
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			var s := AudioStreamMP3.new()
			s.data = FileAccess.get_file_as_bytes(path)
			return s
	return null


# ---------------------------------------------------------------- playback

func play_menu() -> void:
	in_menu = true
	climax = false
	if not enabled:
		return
	current = {"title": "Racing Game Menu", "path": MENU_TRACK, "climax": ""}
	_start(MENU_TRACK, 0.0)


func play_race() -> void:
	in_menu = false
	climax = false
	next_track()


func next_track() -> void:
	if not enabled or tracks.is_empty():
		player.stop()
		return
	if in_menu:
		play_menu()
		return
	if order.is_empty():
		order = tracks.duplicate()
		order.shuffle()
		if order.size() > 1 and order[0].path == current.get("path", ""):
			order.reverse()     # never repeat the song that just played
	current = order.pop_front()
	_plays = 0
	var path: String = current.climax if (climax and current.climax != "") else current.path
	if not _start(path, 0.0):
		tracks.erase(current)
		next_track()
		return
	now_playing.emit(current.title)


func _start(path: String, from: float) -> bool:
	var stream := _load(path)
	if stream == null:
		return false
	player.stream = stream
	player.play(from)
	return true


## Final stretch of a run: swap to the track's faster climax mix.
func set_climax(on: bool) -> void:
	if on == climax:
		return
	climax = on
	if in_menu or not enabled or current.is_empty() or current.climax == "":
		return
	var tw := create_tween()
	tw.tween_property(player, "volume_db", -30.0, 0.35)
	tw.tween_callback(func():
		_start(current.climax if climax else current.path, 0.0)
		if climax:
			now_playing.emit(current.title + " — CLIMAX"))
	tw.tween_property(player, "volume_db", -7.0, 0.25)


func _on_finished() -> void:
	# built-in tracks are short loops: play each one twice before moving on
	_plays += 1
	if in_menu:
		play_menu()
	elif current.get("climax", "") != "" and _plays < 2:
		_start(current.climax if climax else current.path, 0.0)
	else:
		next_track()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("music_next"):
		if in_menu:
			in_menu = false
		next_track()
	elif event.is_action_pressed("music_toggle"):
		enabled = not enabled
		if enabled:
			if in_menu:
				play_menu()
			else:
				next_track()
		else:
			player.stop()
			now_playing.emit("Music off")
