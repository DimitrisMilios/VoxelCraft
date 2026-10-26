extends Node
## Central background music manager for VoxelCraft.
## Provides authentic Minecraft-style ambient soundtrack playback, smooth cross-fading,
## customizable volume, and persistent state across scene changes.

signal music_track_changed(track_name: String)
signal music_volume_changed(volume_linear: float)
signal music_toggled(is_enabled: bool)

const CONFIG_PATH: String = "user://audio_settings.cfg"
const DEFAULT_VOLUME: float = 0.65
const FADE_DURATION: float = 2.0

static var instance: MusicManager = null

var _player_a: AudioStreamPlayer = null
var _player_b: AudioStreamPlayer = null
var _active_player_idx: int = 0 # 0 for A, 1 for B
var _fade_tween: Tween = null
var _pause_timer: Timer = null

var _music_enabled: bool = true
var _music_volume: float = DEFAULT_VOLUME # Linear 0.0 to 1.0

var _tracks: Array[Dictionary] = []
var _last_track_idx: int = -1
var _is_playing: bool = false


func _init() -> void:
	_register_soundtrack_tracks()


func _enter_tree() -> void:
	if instance == null:
		instance = self


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_players()

	_load_settings()
	if _tracks.is_empty():
		_register_soundtrack_tracks()

	# Start soundtrack playback
	if _music_enabled:
		call_deferred("_start_initial_track")


func _ensure_audio_players() -> void:
	if _player_a == null:
		_player_a = AudioStreamPlayer.new()
		_player_a.name = "MusicPlayerA"
		_player_a.bus = "Master"
		add_child(_player_a)
		_player_a.finished.connect(_on_track_finished)

	if _player_b == null:
		_player_b = AudioStreamPlayer.new()
		_player_b.name = "MusicPlayerB"
		_player_b.bus = "Master"
		add_child(_player_b)
		_player_b.finished.connect(_on_track_finished)

	if _pause_timer == null:
		_pause_timer = Timer.new()
		_pause_timer.one_shot = true
		_pause_timer.timeout.connect(_play_next_scheduled_track)
		add_child(_pause_timer)


func _register_soundtrack_tracks() -> void:
	_tracks.clear()

	# 1. High-fidelity peaceful ambient piano tracks (~63 seconds each)
	for i in range(1, 4):
		var tres_path: String = "res://assets/audio/music_ambient_0%d.tres" % i
		if FileAccess.file_exists(tres_path) or ResourceLoader.exists(tres_path):
			_tracks.append({
				"name": "Subwoofer Calm %d" % i,
				"path": tres_path,
				"is_resource": true,
				"volume_offset": 0.0
			})

	# 2. Ambient choral and acoustic melodies
	for i in range(1, 6):
		var ogg_path: String = "res://assets/audio/sounds/sounds_mermaid_song_0%d.ogg" % i
		if ResourceLoader.exists(ogg_path) or FileAccess.file_exists(ogg_path):
			_tracks.append({
				"name": "Halcyon Melody %d" % i,
				"path": ogg_path,
				"is_resource": true,
				"volume_offset": -2.0
			})

	# 3. Scott Joplin / Minecraft retro piano piece
	var piano_path := "res://assets/audio/sounds/sounds_piano.ogg"
	if ResourceLoader.exists(piano_path) or FileAccess.file_exists(piano_path):
		_tracks.append({
			"name": "Dry Hands Piano",
			"path": piano_path,
			"is_resource": true,
			"volume_offset": -3.0
		})


func _start_initial_track() -> void:
	if not _music_enabled or _tracks.is_empty():
		return
	play_random_track(1.5)


func play_random_track(fade_in_time: float = FADE_DURATION) -> void:
	if not _music_enabled or _tracks.is_empty():
		return

	if _pause_timer != null and not _pause_timer.is_stopped():
		_pause_timer.stop()

	var next_idx: int = randi() % _tracks.size()
	if _tracks.size() > 1 and next_idx == _last_track_idx:
		next_idx = (next_idx + 1) % _tracks.size()
	_last_track_idx = next_idx

	var track_info: Dictionary = _tracks[next_idx]
	var stream: AudioStream = _load_track_stream(track_info)
	if stream == null:
		_play_next_scheduled_track()
		return

	_ensure_audio_players()

	var incoming_player: AudioStreamPlayer = _player_b if _active_player_idx == 0 else _player_a
	var outgoing_player: AudioStreamPlayer = _player_a if _active_player_idx == 0 else _player_b
	_active_player_idx = 1 if _active_player_idx == 0 else 0

	var target_db: float = _linear_to_db(_music_volume) + float(track_info.get("volume_offset", 0.0))

	incoming_player.stream = stream
	incoming_player.volume_db = -60.0
	if incoming_player.is_inside_tree():
		incoming_player.play()
		_is_playing = true

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if is_inside_tree():
		_fade_tween = create_tween().set_parallel(true)
		# Fade in new track
		_fade_tween.tween_property(incoming_player, "volume_db", target_db, fade_in_time)

		# Fade out old track if playing
		if outgoing_player != null and outgoing_player.is_inside_tree() and outgoing_player.playing:
			_fade_tween.tween_property(outgoing_player, "volume_db", -60.0, fade_in_time)
			_fade_tween.chain().tween_callback(outgoing_player.stop)
	else:
		incoming_player.volume_db = target_db

	music_track_changed.emit(str(track_info.get("name", "Ambient Soundtrack")))


func _load_track_stream(track_info: Dictionary) -> AudioStream:
	var path: String = str(track_info.get("path", ""))
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	elif FileAccess.file_exists(path):
		stream = AudioStreamOggVorbis.load_from_file(path)
	if stream == null:
		stream = load(path) as AudioStream
	return stream


func _on_track_finished() -> void:
	_is_playing = false
	if not _music_enabled:
		return

	# Authentic Minecraft pacing: peaceful 10-25 second interlude between tracks
	var interlude_sec: float = randf_range(10.0, 22.0)
	if _pause_timer != null:
		_pause_timer.start(interlude_sec)


func _play_next_scheduled_track() -> void:
	if _music_enabled:
		play_random_track(FADE_DURATION)


func set_music_volume(volume_linear: float) -> void:
	_music_volume = clampf(volume_linear, 0.0, 1.0)
	_apply_current_volume()
	_save_settings()
	music_volume_changed.emit(_music_volume)


func set_music_enabled(enabled: bool) -> void:
	if _music_enabled == enabled:
		return
	_music_enabled = enabled
	_save_settings()
	music_toggled.emit(_music_enabled)

	if _music_enabled:
		play_random_track(1.5)
	else:
		stop_music(1.5)


func stop_music(fade_out_time: float = 1.0) -> void:
	if _pause_timer != null and not _pause_timer.is_stopped():
		_pause_timer.stop()

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	var active_p: AudioStreamPlayer = _player_a if _active_player_idx == 0 else _player_b
	if active_p != null and active_p.playing:
		_fade_tween = create_tween()
		_fade_tween.tween_property(active_p, "volume_db", -60.0, fade_out_time)
		_fade_tween.tween_callback(active_p.stop)
	_is_playing = false


func is_music_enabled() -> bool:
	return _music_enabled


func get_music_volume() -> float:
	return _music_volume


func is_music_playing() -> bool:
	return _is_playing


func _apply_current_volume() -> void:
	var active_p: AudioStreamPlayer = _player_a if _active_player_idx == 0 else _player_b
	if active_p != null and active_p.playing:
		if _fade_tween == null or not _fade_tween.is_valid():
			var offset: float = 0.0
			if _last_track_idx >= 0 and _last_track_idx < _tracks.size():
				offset = float(_tracks[_last_track_idx].get("volume_offset", 0.0))
			active_p.volume_db = _linear_to_db(_music_volume) + offset


func _linear_to_db(linear: float) -> float:
	if linear <= 0.0001:
		return -60.0
	# Clean logarithmic volume curve from 0.0 (-60dB) to 1.0 (-8dB)
	return lerpf(-42.0, -8.0, linear)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_enabled", _music_enabled)
	cfg.set_value("audio", "music_volume", _music_volume)
	cfg.save(CONFIG_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		_music_enabled = bool(cfg.get_value("audio", "music_enabled", true))
		_music_volume = float(cfg.get_value("audio", "music_volume", DEFAULT_VOLUME))
	else:
		_music_enabled = true
		_music_volume = DEFAULT_VOLUME
