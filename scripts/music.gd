extends Node
## Custom soundtrack player (autoload "Music").
## Plays the player's own music files in shuffled order, across menu and races.
## Put .ogg or .mp3 files in either folder:
##   <project or game folder>/music/
##   user://music/   (e.g. %APPDATA%/Godot/app_userdata/Downhill Strike/music on Windows)
## Keys: M = next song, N = music on/off.

signal now_playing(title: String)

const EXTENSIONS := ["ogg", "mp3"]

var player: AudioStreamPlayer
var tracks: Array[String] = []
var order: Array[String] = []
var enabled := true
var current := ""
var custom_folder := ""      # any folder on the PC chosen from the menu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	player.volume_db = -6.0
	add_child(player)
	player.finished.connect(next_track)
	_bind("music_next", KEY_M)
	_bind("music_toggle", KEY_N)
	DirAccess.make_dir_recursive_absolute("user://music")
	custom_folder = Game.records.get_value("music", "folder", "")
	rescan()
	next_track()


func _bind(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
		var e := InputEventKey.new()
		e.physical_keycode = key
		InputMap.action_add_event(action, e)


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
	next_track()


func rescan() -> void:
	tracks.clear()
	for dir_path in folders():
		_scan(dir_path, 0)
	order.clear()


## Scans a folder and its sub-folders (albums) for songs.
func _scan(dir_path: String, depth: int) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null or depth > 3:
		return
	for f in dir.get_files():
		if f.get_extension().to_lower() in EXTENSIONS:
			tracks.append(dir_path.path_join(f))
	for sub in dir.get_directories():
		_scan(dir_path.path_join(sub), depth + 1)


func _load(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			var s := AudioStreamMP3.new()
			s.data = FileAccess.get_file_as_bytes(path)
			return s
	return null


func next_track() -> void:
	if not enabled or tracks.is_empty():
		player.stop()
		return
	if order.is_empty():
		order = tracks.duplicate()
		order.shuffle()
		if order.size() > 1 and order[0] == current:
			order.reverse()     # never repeat the song that just played
	current = order.pop_front()
	var stream := _load(current)
	if stream == null:
		tracks.erase(current)
		next_track()
		return
	player.stream = stream
	player.play()
	now_playing.emit(current.get_file().get_basename())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("music_next"):
		next_track()
	elif event.is_action_pressed("music_toggle"):
		enabled = not enabled
		if enabled:
			next_track()
		else:
			player.stop()
			now_playing.emit("Music off")
