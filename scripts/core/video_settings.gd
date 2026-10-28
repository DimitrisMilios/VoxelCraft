extends Node
## Video options (render distance, 3D render scale, VSync), saved to user://video_settings.cfg.
##
## The default "Auto" render scale keeps weak GPUs at 60 FPS: when frames stay slow for two
## seconds in a row the 3D view renders at a lower resolution (10% steps, down to 60%), and it
## creeps back up after a stretch of smooth frames. HUD and menus always stay at full resolution.

const CONFIG_PATH: String = "user://video_settings.cfg"
## Manual render-scale choices offered in the pause menu (0 = Auto).
const SCALE_CHOICES: Array[float] = [0.0, 1.0, 0.85, 0.7, 0.5]
const AUTO_MIN_SCALE: float = 0.6
const SLOW_FRAME: float = 1.0 / 54.0
const FAST_FRAME: float = 1.0 / 58.0

var render_distance: int = 4
## 0.0 = automatic, otherwise a fixed 3D render scale.
var render_scale: float = 0.0
var vsync: bool = true

var _current_scale: float = 1.0
var _window_time: float = 0.0
var _window_frames: int = 0
var _slow_seconds: int = 0
var _smooth_seconds: int = 0
var _raise_cooldown: float = 0.0
## Each drop right after a raise doubles the wait before trying a higher scale again.
var _backoff: float = 15.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply()


func is_auto_scale() -> bool:
	return render_scale <= 0.0


## Current 3D resolution scale actually in use (0.6..1.0).
func get_current_scale() -> float:
	return _current_scale


func apply() -> void:
	_current_scale = 1.0 if is_auto_scale() else clampf(render_scale, 0.25, 1.0)
	_apply_scale()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func _apply_scale() -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = _current_scale


func set_render_scale(value: float) -> void:
	render_scale = value
	apply()
	save_settings()


func set_render_distance(value: int) -> void:
	render_distance = value
	save_settings()


## Steps through Auto / 100% / 85% / 70% / 50% and returns the new choice.
func cycle_render_scale() -> float:
	var idx: int = 0
	for i in range(SCALE_CHOICES.size()):
		if is_equal_approx(SCALE_CHOICES[i], render_scale):
			idx = i
	set_render_scale(SCALE_CHOICES[(idx + 1) % SCALE_CHOICES.size()])
	return render_scale


func describe_render_scale() -> String:
	if is_auto_scale():
		return "Auto (%d%%)" % roundi(_current_scale * 100.0)
	return "%d%%" % roundi(render_scale * 100.0)


func _process(delta: float) -> void:
	if not is_auto_scale() or DisplayServer.get_name() == "headless" or get_tree().paused:
		return
	_raise_cooldown = maxf(0.0, _raise_cooldown - delta)
	_window_time += delta
	_window_frames += 1
	if _window_time < 1.0:
		return
	var avg: float = _window_time / float(_window_frames)
	_window_time = 0.0
	_window_frames = 0

	if avg > SLOW_FRAME:
		_slow_seconds += 1
		_smooth_seconds = 0
	elif avg < FAST_FRAME:
		_smooth_seconds += 1
		_slow_seconds = 0
	else:
		_slow_seconds = 0
		_smooth_seconds = 0

	if _slow_seconds >= 2 and _current_scale > AUTO_MIN_SCALE:
		_current_scale = maxf(AUTO_MIN_SCALE, snappedf(_current_scale - 0.1, 0.05))
		_apply_scale()
		_slow_seconds = 0
		_backoff = minf(_backoff * 2.0, 480.0)
		_raise_cooldown = _backoff
	elif _smooth_seconds >= 10 and _current_scale < 1.0 and _raise_cooldown <= 0.0:
		_current_scale = minf(1.0, snappedf(_current_scale + 0.1, 0.05))
		_apply_scale()
		_smooth_seconds = 0
		_raise_cooldown = 10.0


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "render_distance", render_distance)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "vsync", vsync)
	cfg.save(CONFIG_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	render_distance = clampi(int(cfg.get_value("video", "render_distance", render_distance)), 2, 16)
	render_scale = float(cfg.get_value("video", "render_scale", render_scale))
	vsync = bool(cfg.get_value("video", "vsync", vsync))
