extends SceneTree
## Renders the real game scene in a window (run without --headless), waits for the world to
## stream in, then reports frame timings, draw calls and chunk build costs, and saves screenshots.
##
##   Godot --path . -s tools/benchmark_render.gd
##
## Optional environment variables: BENCH_OUT (folder for screenshots), BENCH_FRAMES (default 400).
## Runs in the sandboxed test save folder, so it never touches real worlds.

const GameSession = preload("res://scripts/core/game_session.gd")

var _main: Node = null
var _wm: Node = null
var _frame: int = 0
var _phase: int = 0
var _phase_start_frame: int = 0
var _load_start_usec: int = 0
var _last_usec: int = 0
var _frame_times: PackedFloat64Array = PackedFloat64Array()
var _draw_calls: int = 0
var _primitives: int = 0
var _objects: int = 0
var _out_dir: String = ""
var _measure_frames: int = 400


func _initialize() -> void:
	_out_dir = OS.get_environment("BENCH_OUT")
	if _out_dir.is_empty():
		_out_dir = OS.get_user_data_dir()
	var frames_env: String = OS.get_environment("BENCH_FRAMES")
	if not frames_env.is_empty():
		_measure_frames = frames_env.to_int()

	GameSession.create_world("Benchmark", "2027")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_load_start_usec = Time.get_ticks_usec()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_wm = _main.find_child("WorldManager", true, false)
	print("[Bench] Startup (sync spawn area) took %.0f ms" % ((Time.get_ticks_usec() - _load_start_usec) / 1000.0))
	_load_start_usec = Time.get_ticks_usec()
	_set_time(12.0)


func _set_time(hour: float) -> void:
	var dn: Node = _main.find_child("DayNightCycle", true, false)
	if dn != null:
		dn.set("day_length_seconds", 0.0)
		dn.set("current_hour", hour)
		if dn.has_method("advance_hours"):
			dn.call("advance_hours", 0.0)


func _expected_chunks() -> int:
	var r: int = int(_wm.get("render_distance")) if _wm != null else 4
	return (2 * r + 1) * (2 * r + 1)


func _process(_delta: float) -> bool:
	_frame += 1
	var player: Node3D = _main.find_child("Player", true, false) as Node3D
	if player != null:
		var head: Node3D = player.get_node_or_null("Head") as Node3D
		if head != null:
			head.rotation.x = -0.32
		player.set("velocity", Vector3.ZERO)

	match _phase:
		0:
			var loaded: int = int(_wm.call("get_active_chunk_count")) if _wm != null else 0
			if loaded >= _expected_chunks() or _frame > 3000:
				print("[Bench] World streamed in: %d chunks in %.2f s (%d frames)" % [loaded, (Time.get_ticks_usec() - _load_start_usec) / 1000000.0, _frame])
				_phase = 1
				_phase_start_frame = _frame
		1:
			# Let pending remeshes and GC settle.
			if _frame - _phase_start_frame > 60:
				_phase = 2
				_phase_start_frame = _frame
				_last_usec = Time.get_ticks_usec()
		2:
			var now: int = Time.get_ticks_usec()
			_frame_times.append((now - _last_usec) / 1000.0)
			if (now - _last_usec) > 12000:
				print("[SPIKE] frame %d: %.1f ms (scripts %.1f ms, physics %.1f ms), nodes %d" % [
					_frame, (now - _last_usec) / 1000.0,
					Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
					Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
					int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				])
			_last_usec = now
			_draw_calls = maxi(_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			_primitives = maxi(_primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
			_objects = maxi(_objects, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
			if _frame_times.size() >= _measure_frames:
				_report_frames()
				_save_shot("bench_noon.png")
				_set_time(0.0)
				_phase = 3
				_phase_start_frame = _frame
		3:
			if _frame - _phase_start_frame > 10:
				_save_shot("bench_night.png")
				_report_build_costs()
				_main.queue_free()
				return true
	return false


func _report_frames() -> void:
	var sorted_times: PackedFloat64Array = _frame_times.duplicate()
	sorted_times.sort()
	var total: float = 0.0
	for t in _frame_times:
		total += t
	var avg: float = total / float(_frame_times.size())
	var p99: float = sorted_times[int(sorted_times.size() * 0.99) - 1]
	var worst: float = sorted_times[sorted_times.size() - 1]
	print("[Bench] Frames: %d | avg %.2f ms (%.0f FPS) | 99th pct %.2f ms | worst %.2f ms" % [_frame_times.size(), avg, 1000.0 / avg, p99, worst])
	print("[Bench] Max per frame: %d draw calls, %d primitives, %d objects" % [_draw_calls, _primitives, _objects])
	print("[Bench] Static memory: %.1f MB | Video memory: %.1f MB" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	])


func _report_build_costs() -> void:
	if _wm == null or not _wm.has_method("_create_chunk_data"):
		return
	var gen_total: int = 0
	var mesh_total: int = 0
	var n: int = 4
	for i in range(n):
		var coord := Vector2i(40 + i * 3, -40)
		var t0: int = Time.get_ticks_usec()
		var chunk: VoxelChunk = _wm.call("_create_chunk_data", coord)
		var t1: int = Time.get_ticks_usec()
		chunk.build_mesh_data()
		var t2: int = Time.get_ticks_usec()
		gen_total += t1 - t0
		mesh_total += t2 - t1
		chunk.free()
	print("[Bench] Per chunk (one thread): generate+light %.1f ms | mesh %.1f ms" % [gen_total / 1000.0 / n, mesh_total / 1000.0 / n])


func _save_shot(file_name: String) -> void:
	var img: Image = root.get_texture().get_image()
	var path: String = _out_dir.path_join(file_name)
	img.save_png(path)
	print("[Bench] Saved screenshot: " + path)
