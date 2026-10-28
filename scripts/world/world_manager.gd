class_name WorldManager
extends Node3D
const GameSession = preload("res://scripts/core/game_session.gd")
const FallingBlockClass = preload("res://scripts/entities/falling_block.gd")
const TNTPrimedClass = preload("res://scripts/entities/tnt_primed.gd")
const VoxelLighting = preload("res://scripts/world/voxel_lighting.gd")
## Manages endless procedural chunk streaming on the WorkerThreadPool, incremental lighting,
## cellular-automata water flow, random block ticks (sugar cane, cactus, saplings), leaf decay,
## block support rules, and ChunkStorage persistence.
##
## Streaming pipeline: chunks within `render_distance + 1` are generated and lit on worker threads
## (data only). A chunk within `render_distance` is meshed once all 8 neighbors have data, so faces,
## smooth lighting and AO are seamless across chunk borders. Only meshed chunks enter the scene tree.

signal world_saved(saved_chunk_count: int)

const WATER_TICK_INTERVAL: float = 0.25
const MAX_WATER_SPREAD_PER_TICK: int = 8
## Random block ticks: 3 per 16^3 section per game tick (20 ticks/s), like the classic game.
const RANDOM_TICK_INTERVAL: float = 0.5
const RANDOM_TICK_CHANCE: float = (3.0 * 20.0 / 4096.0) * RANDOM_TICK_INTERVAL
const MAX_PLANT_HEIGHT: int = 3
const LEAF_DECAY_RANGE: int = 4
## Main-thread time budget for attaching finished chunk meshes each frame (microseconds).
const APPLY_BUDGET_USEC: int = 3000
## Chunks within this many chunks of the player get collision; adding collision shapes is the most
## expensive part of attaching a chunk, so it is done gradually on a per-frame budget.
const COLLISION_RADIUS: int = 3
const COLLISION_BUDGET_USEC: int = 1500

@export_group("World Generation")
@export var world_seed: int = 2027
@export var render_distance: int = 4
@export var max_concurrent_tasks: int = 3
@export var max_main_thread_applies_per_frame: int = 2

@export_group("References")
@export var player_path: NodePath = NodePath("../Player")

## Meshed chunks attached to the scene tree: `Vector2i(cx, cz) -> VoxelChunk`.
var _active_chunks: Dictionary = {}
## Generated (and lit) chunks that are not meshed/attached yet.
var _data_chunks: Dictionary = {}

var _gen_queue: Array[Vector2i] = []
var _mesh_targets: Array[Vector2i] = []
var _gen_in_flight: Dictionary = {}
var _mesh_in_flight: Dictionary = {}
var _active_task_ids: Array[int] = []
var _is_shutting_down: bool = false

var _completed_gen: Array[Dictionary] = []
var _completed_mesh: Array[Dictionary] = []
var _completed_mutex: Mutex = Mutex.new()

## Sub-chunk remesh requests gathered during a frame: `Vector2i -> {sub_idx: water_only}`.
var _pending_remesh: Dictionary = {}

## Chunks waiting for their collision shapes, nearest first.
var _collision_queue: Array[Vector2i] = []
var _collision_queued: Dictionary = {}
## Villagers from generated villages, spawned one per frame.
var _pending_villagers: Array[Vector3] = []

## Cellular-automata water flow queue (`Vector3i` world block coordinates).
var _water_flow_queue: Array[Vector3i] = []
var _water_flow_pending: Dictionary = {}
var _water_tick_timer: float = 0.0

## Active crop growth tracker (`Vector3i` -> seconds elapsed)
var _active_crops: Dictionary = {}
var _crop_tick_timer: float = 0.0

## Blocks that receive random ticks, per chunk: `Vector2i -> {Vector3i: true}`.
var _tickables: Dictionary = {}
var _random_tick_timer: float = 0.0

## Leaves waiting for a decay check: `Vector3i -> seconds until check`.
var _decay_candidates: Dictionary = {}

var _storage: ChunkStorage = null
var _surface_noise: FastNoiseLite = FastNoiseLite.new()
var _cave_noise: FastNoiseLite = FastNoiseLite.new()
var _player: Node3D = null
var _last_player_chunk: Vector2i = Vector2i(999999, 999999)


func _ready() -> void:
	add_to_group("world_manager")
	if get_tree() != null:
		get_tree().set_auto_accept_quit(false)

	# Build shared materials and lookup tables on the main thread before workers use them.
	VoxelAtlasBuilder.get_terrain_material(false)
	VoxelAtlasBuilder.get_shared_water_material()
	# Leave a core free for the main thread on low-end dual/quad-core CPUs.
	max_concurrent_tasks = clampi(OS.get_processor_count() - 1, 1, max_concurrent_tasks)

	if GameSession.active_world_id.is_empty():
		var saved: Array[Dictionary] = GameSession.list_saved_worlds()
		if not saved.is_empty() and str(saved[0].get("id", "")).length() > 0:
			GameSession.select_world(str(saved[0]["id"]))

	if not GameSession.active_world_id.is_empty():
		world_seed = GameSession.active_seed
		_storage = ChunkStorage.new(GameSession.get_active_chunk_dir())
	else:
		_storage = ChunkStorage.new(world_seed)
	_configure_noise()

	_player = get_node_or_null(player_path)
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D

	var start_chunk := Vector2i.ZERO
	var has_saved_pos: bool = false
	if not GameSession.active_world_data.is_empty():
		var p_data: Dictionary = GameSession.active_world_data.get("player", {})
		if _player != null:
			var has_bed: bool = bool(p_data.get("has_bed", false))
			_player.set("has_custom_respawn", has_bed)
			if has_bed and p_data.has("bed_pos") and p_data["bed_pos"] is Array:
				var b_arr: Array = p_data["bed_pos"]
				_player.set("custom_respawn_pos", Vector3(b_arr[0], b_arr[1], b_arr[2]))

		has_saved_pos = bool(p_data.get("has_saved_pos", false))
		if has_saved_pos and p_data.has("pos") and p_data["pos"] is Array:
			var p_arr: Array = p_data["pos"]
			var saved_pos := Vector3(p_arr[0], p_arr[1], p_arr[2])
			start_chunk = world_to_chunk_coords(saved_pos)
			if _player != null:
				_player.global_position = saved_pos
				_player.rotation.y = float(p_data.get("yaw", 0.0))
				var head: Node3D = _player.get_node_or_null("Head") as Node3D
				if head != null:
					head.rotation.x = float(p_data.get("pitch", 0.0))
				_player.set("current_health", int(p_data.get("health", 20)))
				_player.set("current_hunger", int(p_data.get("hunger", 20)))
				_player.set("current_oxygen", int(p_data.get("oxygen", 10)))
				_player.set("is_flying", bool(p_data.get("is_flying", false)))
	elif _player != null:
		start_chunk = world_to_chunk_coords(_player.global_position)

	# Synchronously build the immediate 3x3 spawn area so the player starts on solid ground
	_load_area_immediate(start_chunk)

	if _player != null and not has_saved_pos:
		var spawn_wx: int = 8
		var spawn_wz: int = 8
		var surface_y: int = get_surface_height_at(spawn_wx, spawn_wz)
		# If initial origin is underwater in an ocean, spiral outward to find solid dry land
		if surface_y <= VoxelChunk.WATER_LEVEL + 1:
			var found: bool = false
			for r in range(1, 8):
				for angle in range(8):
					var rad: float = float(angle) * (PI / 4.0)
					var test_x: int = int(round(8.0 + cos(rad) * float(r * 12)))
					var test_z: int = int(round(8.0 + sin(rad) * float(r * 12)))
					var test_y: int = _procedural_surface_height(test_x, test_z)
					if test_y > VoxelChunk.WATER_LEVEL + 1:
						spawn_wx = test_x
						spawn_wz = test_z
						found = true
						break
				if found:
					break
			if found:
				_load_area_immediate(world_to_chunk_coords(Vector3(spawn_wx, 0, spawn_wz)))
				start_chunk = world_to_chunk_coords(Vector3(spawn_wx, 0, spawn_wz))
				surface_y = get_surface_height_at(spawn_wx, spawn_wz)
		_player.global_position = Vector3(float(spawn_wx) + 0.5, float(surface_y) + 2.5, float(spawn_wz) + 0.5)

	_apply_fog_distance()
	_update_chunk_targets(start_chunk)
	_last_player_chunk = start_chunk


func _exit_tree() -> void:
	_is_shutting_down = true
	_wait_for_tasks()
	save_complete_world()


func _wait_for_tasks() -> void:
	for tid in _active_task_ids:
		WorkerThreadPool.wait_for_task_completion(tid)
	_active_task_ids.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_is_shutting_down = true
		save_complete_world()
		if is_inside_tree() and get_tree() != null:
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F6:
			save_complete_world()


func _process(delta: float) -> void:
	if _player != null:
		var current_chunk: Vector2i = world_to_chunk_coords(_player.global_position)
		if current_chunk != _last_player_chunk:
			_last_player_chunk = current_chunk
			_update_chunk_targets(current_chunk)

	_dispatch_background_tasks()
	_apply_completed_builds()
	_process_collision_queue()
	_process_villager_queue()
	_process_water_flow(delta)
	_process_crop_growth(delta)
	_process_random_ticks(delta)
	_process_leaf_decay(delta)
	_flush_remesh_requests()


## Dynamically updates chunk render distance at runtime (e.g. from the Pause Menu).
func set_render_distance(new_distance: int) -> void:
	var clamped: int = clampi(new_distance, 2, 16)
	if clamped == render_distance:
		return
	render_distance = clamped
	_apply_fog_distance()
	if _player != null:
		_last_player_chunk = world_to_chunk_coords(_player.global_position)
		_update_chunk_targets(_last_player_chunk)


## Generates a fresh world map with a new seed, clearing active chunks and respawning on the new surface.
func regenerate_world_with_new_seed() -> int:
	_is_shutting_down = true
	_wait_for_tasks()
	_gen_in_flight.clear()
	_mesh_in_flight.clear()
	_gen_queue.clear()
	_completed_mutex.lock()
	_completed_gen.clear()
	_completed_mesh.clear()
	_completed_mutex.unlock()
	_water_flow_queue.clear()
	_water_flow_pending.clear()
	_pending_remesh.clear()
	_tickables.clear()
	_decay_candidates.clear()

	for coord_variant in _active_chunks.keys():
		var chunk: VoxelChunk = _active_chunks[coord_variant]
		if is_instance_valid(chunk):
			chunk.queue_free()
	_active_chunks.clear()
	for coord_variant in _data_chunks.keys():
		var dchunk: VoxelChunk = _data_chunks[coord_variant]
		if is_instance_valid(dchunk):
			dchunk.free()
	_data_chunks.clear()

	world_seed += 1
	_storage = ChunkStorage.new(world_seed)
	_configure_noise()
	_is_shutting_down = false

	var start_chunk := Vector2i.ZERO
	if _player != null:
		_player.global_position = Vector3(8.5, 65.0, 8.5)
		start_chunk = world_to_chunk_coords(_player.global_position)

	_load_area_immediate(start_chunk)

	if _player != null:
		var spawn_wx: int = int(floor(_player.global_position.x))
		var spawn_wz: int = int(floor(_player.global_position.z))
		var surface_y: int = get_surface_height_at(spawn_wx, spawn_wz)
		_player.global_position = Vector3(float(spawn_wx) + 0.5, float(surface_y) + 2.5, float(spawn_wz) + 0.5)

	_update_chunk_targets(start_chunk)
	_last_player_chunk = start_chunk
	return world_seed


func _configure_noise() -> void:
	_surface_noise.seed = world_seed
	_surface_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_surface_noise.frequency = 0.014
	_surface_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_surface_noise.fractal_octaves = 3

	_cave_noise.seed = world_seed + 7919
	_cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cave_noise.frequency = 0.045
	_cave_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_cave_noise.fractal_octaves = 2


# ============================================================================
# CHUNK STREAMING
# ============================================================================

static func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _update_chunk_targets(center_chunk: Vector2i) -> void:
	# Unload meshed chunks that left the view, and data chunks beyond the generation ring.
	for coord_variant in _active_chunks.keys():
		var coord: Vector2i = coord_variant
		if _chebyshev(coord, center_chunk) > render_distance + 1:
			_unload_chunk(coord, _active_chunks[coord], true)
			_active_chunks.erase(coord)
	for coord_variant in _data_chunks.keys():
		var coord: Vector2i = coord_variant
		if _chebyshev(coord, center_chunk) > render_distance + 2 and not _mesh_in_flight.has(coord):
			_unload_chunk(coord, _data_chunks[coord], false)
			_data_chunks.erase(coord)

	var by_distance := func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = (a - center_chunk).length_squared()
		var db: int = (b - center_chunk).length_squared()
		return da < db

	_gen_queue.clear()
	_mesh_targets.clear()
	var gen_radius: int = render_distance + 1
	for dx in range(-gen_radius, gen_radius + 1):
		for dz in range(-gen_radius, gen_radius + 1):
			var target := Vector2i(center_chunk.x + dx, center_chunk.y + dz)
			if absi(dx) <= render_distance and absi(dz) <= render_distance and not _active_chunks.has(target):
				_mesh_targets.append(target)
			if not _active_chunks.has(target) and not _data_chunks.has(target) and not _gen_in_flight.has(target):
				_gen_queue.append(target)
	_gen_queue.sort_custom(by_distance)
	_mesh_targets.sort_custom(by_distance)

	for coord_variant in _active_chunks.keys():
		var ac: VoxelChunk = _active_chunks[coord_variant]
		if _chebyshev(coord_variant, center_chunk) <= COLLISION_RADIUS and (not ac.collision_enabled or ac._has_pending_shapes):
			_queue_collision(coord_variant)
	_collision_queue.sort_custom(by_distance)


func _unload_chunk(coord: Vector2i, chunk: VoxelChunk, in_tree: bool) -> void:
	_tickables.erase(coord)
	if not is_instance_valid(chunk):
		return
	if chunk.is_dirty and _storage != null:
		_storage.store_modified_chunk(coord, chunk.get_voxels_buffer(), chunk.get_highest_solid_y(), chunk.get_metadata_buffer(), true)
	if in_tree:
		chunk.queue_free()
	else:
		chunk.free()


func _dispatch_background_tasks() -> void:
	if _is_shutting_down:
		return
	var still_running: Array[int] = []
	for tid in _active_task_ids:
		if WorkerThreadPool.is_task_completed(tid):
			WorkerThreadPool.wait_for_task_completion(tid)
		else:
			still_running.append(tid)
	_active_task_ids = still_running

	var budget: int = max_concurrent_tasks - (_gen_in_flight.size() + _mesh_in_flight.size())
	if budget <= 0:
		return

	# Meshing first: it is what the player actually sees.
	var i: int = 0
	while i < _mesh_targets.size() and budget > 0:
		var coord: Vector2i = _mesh_targets[i]
		if _active_chunks.has(coord):
			_mesh_targets.remove_at(i)
			continue
		if not _mesh_in_flight.has(coord) and _data_chunks.has(coord) and _neighbors_have_data(coord):
			_dispatch_mesh(coord)
			budget -= 1
		i += 1

	while budget > 0 and not _gen_queue.is_empty():
		var gcoord: Vector2i = _gen_queue.pop_front()
		if _active_chunks.has(gcoord) or _data_chunks.has(gcoord) or _gen_in_flight.has(gcoord):
			continue
		_gen_in_flight[gcoord] = true
		var task_id: int = WorkerThreadPool.add_task(_worker_generate_chunk.bind(gcoord), false, "GenChunk")
		_active_task_ids.append(task_id)
		budget -= 1


func _neighbors_have_data(coord: Vector2i) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c := coord + Vector2i(dx, dz)
			if not _data_chunks.has(c) and not _active_chunks.has(c):
				return false
	return true


## Returns a loaded chunk (meshed or data-only) or null.
func find_loaded_chunk(coord: Vector2i) -> VoxelChunk:
	var c: VoxelChunk = _active_chunks.get(coord, null) as VoxelChunk
	if c == null:
		c = _data_chunks.get(coord, null) as VoxelChunk
	return c


func _create_chunk_data(coord: Vector2i) -> VoxelChunk:
	var chunk := VoxelChunk.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk.chunk_coords = coord
	var saved_data: Dictionary = {}
	if _storage != null:
		saved_data = _storage.load_chunk_data(coord)
	if not saved_data.is_empty():
		chunk.load_from_buffer(saved_data["voxels"], int(saved_data["highest_y"]), saved_data.get("metadata", PackedByteArray()))
	else:
		chunk.generate_terrain(_surface_noise, _cave_noise)
	VoxelLighting.compute_chunk_lighting(chunk)
	return chunk


func _worker_generate_chunk(coord: Vector2i) -> void:
	if _is_shutting_down:
		return
	var chunk: VoxelChunk = _create_chunk_data(coord)
	_completed_mutex.lock()
	_completed_gen.append({"coord": coord, "chunk": chunk})
	_completed_mutex.unlock()


## Snapshots the 3x3 neighborhood buffers for a worker (private copies, so the main thread can keep editing).
func _collect_neighborhood(coord: Vector2i) -> Dictionary:
	var vox: Array = []
	var light: Array = []
	var top: int = 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c: VoxelChunk = find_loaded_chunk(coord + Vector2i(dx, dz))
			if c == null or c._voxels.is_empty():
				vox.append(PackedByteArray())
				light.append(PackedByteArray())
				continue
			if c._lighting.is_empty():
				VoxelLighting.compute_chunk_lighting(c)
			vox.append(c._voxels.duplicate())
			light.append(c._lighting.duplicate())
			top = maxi(top, c.get_highest_solid_y() + 2)
	return {"vox": vox, "light": light, "top": top}


func _dispatch_mesh(coord: Vector2i) -> void:
	var chunk: VoxelChunk = _data_chunks[coord]
	var nb: Dictionary = _collect_neighborhood(coord)
	var job: Dictionary = {
		"coord": coord,
		"chunk": chunk,
		"vox": nb["vox"],
		"light": nb["light"],
		"top": nb["top"],
		"meta": chunk._metadata.duplicate(),
		"max_sub": chunk.get_max_sub_index(),
		"light_version": chunk.light_version,
	}
	_mesh_in_flight[coord] = true
	var task_id: int = WorkerThreadPool.add_task(_worker_mesh_chunk.bind(job), false, "MeshChunk")
	_active_task_ids.append(task_id)


func _worker_mesh_chunk(job: Dictionary) -> void:
	if _is_shutting_down:
		return
	var vox: Array = job["vox"]
	var light: Array = job["light"]
	var own_light: PackedByteArray = light[4]
	VoxelLighting.stitch_inflow(own_light, vox[4], light, int(job["top"]))
	var mesh_data: Dictionary = VoxelChunk.build_mesh_data_from(vox, light, job["meta"], int(job["max_sub"]))
	job["mesh_data"] = mesh_data
	job["stitched_light"] = own_light
	job.erase("vox")
	job.erase("light")
	_completed_mutex.lock()
	_completed_mesh.append(job)
	_completed_mutex.unlock()


func _apply_completed_builds() -> void:
	_completed_mutex.lock()
	var gens: Array[Dictionary] = _completed_gen
	_completed_gen = []
	_completed_mutex.unlock()

	var center: Vector2i = _last_player_chunk
	for item in gens:
		var coord: Vector2i = item["coord"]
		var chunk: VoxelChunk = item["chunk"]
		_gen_in_flight.erase(coord)
		if _active_chunks.has(coord) or _data_chunks.has(coord) or _chebyshev(coord, center) > render_distance + 2:
			chunk.free()
			continue
		_data_chunks[coord] = chunk

	var start_usec: int = Time.get_ticks_usec()
	var applied: int = 0
	while applied < max_main_thread_applies_per_frame:
		if applied > 0 and Time.get_ticks_usec() - start_usec > APPLY_BUDGET_USEC:
			break
		_completed_mutex.lock()
		if _completed_mesh.is_empty():
			_completed_mutex.unlock()
			break
		var job: Dictionary = _completed_mesh.pop_front()
		_completed_mutex.unlock()

		var coord: Vector2i = job["coord"]
		var chunk: VoxelChunk = job["chunk"]
		_mesh_in_flight.erase(coord)
		if not is_instance_valid(chunk) or _data_chunks.get(coord, null) != chunk:
			continue
		if _chebyshev(coord, center) > render_distance + 1:
			continue
		_attach_chunk(coord, chunk, job["mesh_data"], job["stitched_light"], int(job["light_version"]))
		applied += 1


func _attach_chunk(coord: Vector2i, chunk: VoxelChunk, mesh_data: Dictionary, stitched_light: PackedByteArray, light_version: int) -> void:
	var light_stale: bool = chunk.light_version != light_version
	if not light_stale and not stitched_light.is_empty():
		chunk._lighting = stitched_light
	_data_chunks.erase(coord)
	chunk.position = Vector3(float(coord.x * VoxelChunk.CHUNK_SIZE_X), 0.0, float(coord.y * VoxelChunk.CHUNK_SIZE_Z))
	chunk.collision_enabled = false
	add_child(chunk)
	chunk.apply_mesh_data(mesh_data)
	_active_chunks[coord] = chunk
	_register_tickables(coord, chunk)
	if _chebyshev(coord, _last_player_chunk) <= COLLISION_RADIUS:
		_queue_collision(coord)
	if light_stale:
		for sub in range(chunk.get_max_sub_index() + 1):
			request_sub_remesh(coord, sub)


func _load_area_immediate(center: Vector2i) -> void:
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var c := center + Vector2i(dx, dz)
			if find_loaded_chunk(c) == null:
				_data_chunks[c] = _create_chunk_data(c)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			_spawn_chunk_immediate(center + Vector2i(dx, dz))


func _queue_collision(coord: Vector2i) -> void:
	if _collision_queued.has(coord):
		return
	_collision_queued[coord] = true
	_collision_queue.append(coord)


func _process_collision_queue() -> void:
	if _collision_queue.is_empty():
		return
	var start: int = Time.get_ticks_usec()
	while not _collision_queue.is_empty():
		var coord: Vector2i = _collision_queue[0]
		var chunk: VoxelChunk = _active_chunks.get(coord, null) as VoxelChunk
		if chunk == null or not is_instance_valid(chunk):
			_collision_queue.pop_front()
			_collision_queued.erase(coord)
			continue
		var remaining: int = COLLISION_BUDGET_USEC - (Time.get_ticks_usec() - start)
		if remaining <= 0:
			return
		if chunk.attach_pending_collision(remaining):
			_collision_queue.pop_front()
			_collision_queued.erase(coord)
		else:
			return


## True when the ground around `world_pos` has collision (mobs freeze until it does).
func is_collision_ready_at(world_pos: Vector3) -> bool:
	var chunk: VoxelChunk = _active_chunks.get(Vector2i(floori(world_pos.x) >> 4, floori(world_pos.z) >> 4), null) as VoxelChunk
	if chunk == null:
		# Unloaded ground while streaming around a player; hand-built worlds (tools) have no player.
		return _player == null or not is_inside_tree()
	return chunk.collision_enabled and not chunk._has_pending_shapes


func queue_villager_spawn(pos: Vector3) -> void:
	_pending_villagers.append(pos)


func _process_villager_queue() -> void:
	if _pending_villagers.is_empty():
		return
	var pos: Vector3 = _pending_villagers.pop_front()
	var villager := PassiveMob.new()
	villager.variant = PassiveMob.MobVariant.VILLAGER
	add_child(villager)
	villager.global_position = pos


## Synchronously generates (if needed), meshes and attaches one chunk using whatever neighbors are loaded.
func _spawn_chunk_immediate(coord: Vector2i) -> VoxelChunk:
	if _active_chunks.has(coord):
		return _active_chunks[coord]
	if not _data_chunks.has(coord):
		_data_chunks[coord] = _create_chunk_data(coord)
	var chunk: VoxelChunk = _data_chunks[coord]
	var nb: Dictionary = _collect_neighborhood(coord)
	var light: Array = nb["light"]
	var own_light: PackedByteArray = light[4]
	VoxelLighting.stitch_inflow(own_light, nb["vox"][4], light, int(nb["top"]))
	var mesh_data: Dictionary = VoxelChunk.build_mesh_data_from(nb["vox"], light, chunk._metadata, chunk.get_max_sub_index())
	_attach_chunk(coord, chunk, mesh_data, own_light, chunk.light_version)
	chunk.attach_pending_collision(1 << 30)
	return chunk


## Ensures the 3x3 chunks surrounding a world position are immediately loaded/built with collision.
func ensure_chunks_around_pos(world_pos: Vector3) -> void:
	var center_chunk: Vector2i = world_to_chunk_coords(world_pos)
	_load_area_immediate(center_chunk)
	_last_player_chunk = center_chunk
	_update_chunk_targets(center_chunk)


## Queues a sub-chunk remesh (coalesced and dispatched at the end of the frame).
func request_sub_remesh(coord: Vector2i, sub_idx: int, water_only: bool = false) -> void:
	if not _pending_remesh.has(coord):
		_pending_remesh[coord] = {}
	var subs: Dictionary = _pending_remesh[coord]
	subs[sub_idx] = water_only and bool(subs.get(sub_idx, true))


func _queue_dirty_remesh(dirty: Dictionary, water_only: bool = false) -> void:
	for coord_variant in dirty.keys():
		var subs: Dictionary = dirty[coord_variant]
		for s in subs.keys():
			request_sub_remesh(coord_variant, int(s), water_only)


func _flush_remesh_requests() -> void:
	if _pending_remesh.is_empty():
		return
	var pending: Dictionary = _pending_remesh
	_pending_remesh = {}
	for coord_variant in pending.keys():
		var coord: Vector2i = coord_variant
		var chunk: VoxelChunk = _active_chunks.get(coord, null) as VoxelChunk
		if chunk == null or not is_instance_valid(chunk) or not chunk.is_inside_tree():
			continue
		if chunk._lighting.is_empty():
			VoxelLighting.compute_chunk_lighting(chunk)
		var subs: Dictionary = pending[coord]
		for s in subs.keys():
			var sub_idx: int = int(s)
			chunk.dispatch_sub_rebuild(sub_idx, _build_sub_job(coord, sub_idx, chunk), bool(subs[s]))


## Slices just the layers a sub-chunk rebuild needs (one extra layer above and below) from the 3x3 chunks.
func _build_sub_job(coord: Vector2i, sub_idx: int, chunk: VoxelChunk) -> Dictionary:
	var y0: int = maxi(0, sub_idx * 16 - 1)
	var y1: int = mini(256, sub_idx * 16 + 17)
	var vox: Array = []
	var light: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var c: VoxelChunk = find_loaded_chunk(coord + Vector2i(dx, dz))
			if c == null or c._voxels.is_empty():
				vox.append(PackedByteArray())
				light.append(PackedByteArray())
				continue
			vox.append(c._voxels.slice(y0 * 256, y1 * 256))
			light.append(c._lighting.slice(y0 * 256, y1 * 256) if not c._lighting.is_empty() else PackedByteArray())
	return {"vox": vox, "light": light, "meta": chunk._metadata.duplicate(), "y_origin": y0}


# ============================================================================
# BLOCK ACCESS
# ============================================================================

## Thread-safe-ish neighbor query (loaded chunks first, then procedural terrain).
func get_block_or_procedural_world(world_block_pos: Vector3i) -> int:
	if world_block_pos.y < 0:
		return BlockRegistry.BlockId.STONE
	if world_block_pos.y >= VoxelChunk.CHUNK_SIZE_Y:
		return BlockRegistry.BlockId.AIR
	var c: VoxelChunk = find_loaded_chunk(Vector2i(world_block_pos.x >> 4, world_block_pos.z >> 4))
	if c != null:
		return c.get_block_local(world_block_pos.x & 15, world_block_pos.y, world_block_pos.z & 15)
	var surface_y: int = VoxelChunk.sample_surface_height(_surface_noise, world_block_pos.x, world_block_pos.z)
	return VoxelChunk.sample_terrain_voxel(surface_y, world_block_pos.x, world_block_pos.y, world_block_pos.z, _cave_noise)


static func world_to_chunk_coords(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / float(VoxelChunk.CHUNK_SIZE_X)),
		floori(world_pos.z / float(VoxelChunk.CHUNK_SIZE_Z))
	)


func get_block_world(world_block_pos: Vector3i) -> int:
	if world_block_pos.y < 0 or world_block_pos.y >= VoxelChunk.CHUNK_SIZE_Y:
		return BlockRegistry.BlockId.AIR
	var chunk: VoxelChunk = _active_chunks.get(Vector2i(world_block_pos.x >> 4, world_block_pos.z >> 4), null) as VoxelChunk
	if chunk == null:
		return BlockRegistry.BlockId.AIR
	return chunk.get_block_local(world_block_pos.x & 15, world_block_pos.y, world_block_pos.z & 15)


func get_sky_light_world(world_block_pos: Vector3i) -> int:
	if world_block_pos.y < 0 or world_block_pos.y >= VoxelChunk.CHUNK_SIZE_Y:
		return 15
	var chunk: VoxelChunk = _active_chunks.get(Vector2i(world_block_pos.x >> 4, world_block_pos.z >> 4), null) as VoxelChunk
	if chunk == null:
		return 15
	return chunk.get_sky_light_local(world_block_pos.x & 15, world_block_pos.y, world_block_pos.z & 15)


func get_block_light_world(world_block_pos: Vector3i) -> int:
	if world_block_pos.y < 0 or world_block_pos.y >= VoxelChunk.CHUNK_SIZE_Y:
		return 0
	var chunk: VoxelChunk = _active_chunks.get(Vector2i(world_block_pos.x >> 4, world_block_pos.z >> 4), null) as VoxelChunk
	if chunk == null:
		return 0
	return chunk.get_block_light_local(world_block_pos.x & 15, world_block_pos.y, world_block_pos.z & 15)


func get_effective_light_world(world_block_pos: Vector3i) -> int:
	var sky: int = get_sky_light_world(world_block_pos)
	var blk: int = get_block_light_world(world_block_pos)
	var day_factor: float = 1.0
	var dn: DayNightCycle = get_tree().get_first_node_in_group("day_night_cycle") as DayNightCycle if is_inside_tree() and get_tree() != null else null
	if dn != null:
		var t: float = dn.time_of_day
		if t < 0.24 or t > 0.76:
			day_factor = 0.22
		else:
			day_factor = clampf(sin((t - 0.24) / 0.52 * PI), 0.22, 1.0)
	var eff_sky: int = int(round(float(sky) * day_factor))
	return maxi(blk, eff_sky)


## True when block light at `world_pos` is above 7 (hostile mobs cannot spawn there).
func is_position_illuminated_by_blocks(world_pos: Vector3, light_range: float = 11.0) -> bool:
	var ipos := Vector3i(floori(world_pos.x), floori(world_pos.y), floori(world_pos.z))
	var chunk: VoxelChunk = _active_chunks.get(Vector2i(ipos.x >> 4, ipos.z >> 4), null) as VoxelChunk
	if chunk != null and not chunk._lighting.is_empty():
		return get_block_light_world(ipos) > 7

	# No baked light yet: look for light-emitting blocks nearby.
	for dy in range(-3, 4):
		for dx in range(-8, 9):
			for dz in range(-8, 9):
				var check_p := ipos + Vector3i(dx, dy, dz)
				var bid: int = get_block_world(check_p)
				if BlockRegistry.is_light_emitter(bid):
					var b_world := Vector3(check_p) + Vector3(0.5, 0.5, 0.5)
					var eff_range: float = 14.0 if bid == BlockRegistry.BlockId.LAVA else light_range
					if world_pos.distance_squared_to(b_world) <= (eff_range * eff_range):
						return true
	return false


func set_block_world(world_block_pos: Vector3i, block_id: int, rebuild_mode: int = 2, meta: int = 0) -> bool:
	if world_block_pos.y <= 0 or world_block_pos.y >= VoxelChunk.CHUNK_SIZE_Y:
		return false

	var chunk_coord := Vector2i(world_block_pos.x >> 4, world_block_pos.z >> 4)
	var chunk: VoxelChunk = _active_chunks.get(chunk_coord, null) as VoxelChunk
	if chunk == null:
		return false
	var lx: int = world_block_pos.x & 15
	var lz: int = world_block_pos.z & 15

	var actual_block_id: int = block_id
	if block_id == BlockRegistry.BlockId.LAVA:
		var has_water_nb: bool = false
		for d in VoxelLighting.NEIGHBORS_6:
			if BlockRegistry.is_water(get_block_world(world_block_pos + d)):
				has_water_nb = true
				break
		if has_water_nb:
			actual_block_id = BlockRegistry.BlockId.OBSIDIAN
			_play_sfx_at("lava_cool", Vector3(world_block_pos) + Vector3(0.5, 0.5, 0.5))
	elif BlockRegistry.is_water(block_id):
		for d in VoxelLighting.NEIGHBORS_6:
			var nb_pos: Vector3i = world_block_pos + d
			if get_block_world(nb_pos) == BlockRegistry.BlockId.LAVA:
				set_block_world(nb_pos, BlockRegistry.BlockId.COBBLESTONE)
				_play_sfx_at("lava_cool", Vector3(nb_pos) + Vector3(0.5, 0.5, 0.5))

	var previous_id: int = chunk.get_block_local(lx, world_block_pos.y, lz)

	if actual_block_id == BlockRegistry.BlockId.WHEAT_SPROUT or actual_block_id == BlockRegistry.BlockId.POTATO_SPROUT:
		_active_crops[world_block_pos] = 0.0
	elif _active_crops.has(world_block_pos):
		_active_crops.erase(world_block_pos)

	chunk.set_block_local(lx, world_block_pos.y, lz, actual_block_id, false)
	chunk.set_metadata_local(lx, world_block_pos.y, lz, meta, false)
	_track_tickable(world_block_pos, actual_block_id)

	if rebuild_mode == 2:
		var dirty: Dictionary = {}
		if _changes_light(previous_id, actual_block_id):
			VoxelLighting.update_light_at(self, world_block_pos, dirty, previous_id)
		VoxelLighting.mark_remesh(dirty, world_block_pos)
		_queue_dirty_remesh(dirty)
	elif rebuild_mode == 1:
		var wdirty: Dictionary = {}
		VoxelLighting.mark_remesh(wdirty, world_block_pos)
		_queue_dirty_remesh(wdirty, true)

	# Enqueue 6-connected neighborhood for finite 8-level water flow & drainage
	_enqueue_water_neighborhood(world_block_pos)

	if previous_id != actual_block_id:
		_after_block_changed(world_block_pos, previous_id, actual_block_id)

	return true


static func _changes_light(old_id: int, new_id: int) -> bool:
	return (
		BlockRegistry.light_opacity_table[old_id & 0xFF] != BlockRegistry.light_opacity_table[new_id & 0xFF]
		or BlockRegistry.luminance_table[old_id & 0xFF] != BlockRegistry.luminance_table[new_id & 0xFF]
	)



func _play_sfx_at(sfx_name: String, pos: Vector3, volume_db: float = 1.0) -> void:
	var tree: SceneTree = get_tree() if is_inside_tree() else null
	if tree == null:
		return
	var sfx: Node = tree.get_first_node_in_group("sfx_player")
	if sfx != null and sfx.has_method("play_sfx_at_pos"):
		sfx.play_sfx_at_pos(sfx_name, pos, volume_db)


# ============================================================================
# BLOCK UPDATES: support, falling blocks, leaf decay
# ============================================================================

## Reacts to a block change like a neighbor update: unsupported plants/doors/torches pop off,
## gravity blocks fall, and leaves near a removed log are scheduled for decay.
func _after_block_changed(pos: Vector3i, old_id: int, new_id: int) -> void:
	# Destroying farmland pops the crop above it (as seeds).
	if old_id == BlockRegistry.BlockId.FARMLAND and new_id != BlockRegistry.BlockId.FARMLAND:
		var above_crop := pos + Vector3i(0, 1, 0)
		if BlockRegistry.is_crop(get_block_world(above_crop)):
			set_block_world(above_crop, BlockRegistry.BlockId.AIR)
			DroppedItem.spawn_drop(self, Vector3(above_crop) + Vector3(0.5, 0.3, 0.5), InventoryManager.ItemId.WHEAT_SEEDS, 1)

	_check_support(pos + Vector3i(0, 1, 0))
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var side: Vector3i = pos + d
		_check_support(side)
		# Sugar cane next to this block's ground level depends on water here.
		_check_support(side + Vector3i(0, 1, 0))

	if new_id == BlockRegistry.BlockId.AIR or BlockRegistry.is_passable_block(new_id) or BlockRegistry.is_water(new_id):
		check_falling_block(pos + Vector3i(0, 1, 0))

	if BlockRegistry.is_log(old_id) and not BlockRegistry.is_log(new_id):
		_schedule_leaf_decay(pos)


## Breaks the block at `pos` if it can no longer stay there, dropping it as an item.
func _check_support(pos: Vector3i) -> void:
	var id: int = get_block_world(pos)
	if id == BlockRegistry.BlockId.AIR or BlockRegistry.is_liquid(id):
		return
	if not BlockRegistry.needs_support_below(id):
		return
	if _is_supported(pos, id):
		return
	var drop_id: int = id
	var drop_count: int = 1
	match id:
		BlockRegistry.BlockId.DOOR_OPEN, BlockRegistry.BlockId.DOOR_CLOSED:
			# Only a lower half drops the door item; a stranded upper half just disappears.
			drop_id = 0
			var above_door := pos + Vector3i(0, 1, 0)
			if BlockRegistry.is_door(get_block_world(above_door)):
				# Lower half of a door lost its floor: take the upper half along (no second drop).
				set_block_world(pos, BlockRegistry.BlockId.AIR)
				if BlockRegistry.is_door(get_block_world(above_door)):
					set_block_world(above_door, BlockRegistry.BlockId.AIR)
				DroppedItem.spawn_drop(self, Vector3(pos) + Vector3(0.5, 0.25, 0.5), BlockRegistry.BlockId.DOOR_CLOSED, 1)
				return
		BlockRegistry.BlockId.WHEAT_CROPS:
			drop_id = InventoryManager.ItemId.WHEAT
		BlockRegistry.BlockId.WHEAT_SPROUT:
			drop_id = InventoryManager.ItemId.WHEAT_SEEDS
		BlockRegistry.BlockId.POTATO_CROPS, BlockRegistry.BlockId.POTATO_SPROUT:
			drop_id = InventoryManager.ItemId.POTATO
	set_block_world(pos, BlockRegistry.BlockId.AIR)
	if drop_id > 0:
		DroppedItem.spawn_drop(self, Vector3(pos) + Vector3(0.5, 0.25, 0.5), drop_id, drop_count)


func _is_supported(pos: Vector3i, id: int) -> bool:
	var below: int = get_block_world(pos + Vector3i(0, -1, 0))
	match id:
		BlockRegistry.BlockId.SUGAR_CANE:
			return can_sugar_cane_stay(pos)
		BlockRegistry.BlockId.CACTUS:
			if below != BlockRegistry.BlockId.CACTUS and below != BlockRegistry.BlockId.SAND:
				return false
			for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				if BlockRegistry.is_solid(get_block_world(pos + d)):
					return false
			return true
		BlockRegistry.BlockId.DOOR_CLOSED, BlockRegistry.BlockId.DOOR_OPEN:
			if BlockRegistry.is_door(below):
				return true
			return BlockRegistry.is_solid(below) and not BlockRegistry.is_door(below)
		BlockRegistry.BlockId.WHEAT_CROPS, BlockRegistry.BlockId.POTATO_CROPS, BlockRegistry.BlockId.WHEAT_SPROUT, BlockRegistry.BlockId.POTATO_SPROUT:
			return below == BlockRegistry.BlockId.FARMLAND
		BlockRegistry.BlockId.SAPLING, BlockRegistry.BlockId.PINE_SAPLING, BlockRegistry.BlockId.BIRCH_SAPLING, BlockRegistry.BlockId.DANDELION, BlockRegistry.BlockId.ROSE:
			return below == BlockRegistry.BlockId.GRASS or below == BlockRegistry.BlockId.DIRT or below == BlockRegistry.BlockId.FARMLAND
		BlockRegistry.BlockId.TORCH, BlockRegistry.BlockId.REDSTONE_TORCH, BlockRegistry.BlockId.LEVER:
			if BlockRegistry.is_solid(below):
				return true
			for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				if BlockRegistry.is_opaque_full_cube(get_block_world(pos + d)):
					return true
			return false
		_:
			return BlockRegistry.is_solid(below)


## Sugar cane stands on cane, or on grass/dirt/sand that has water right beside it.
func can_sugar_cane_stay(pos: Vector3i) -> bool:
	var ground_pos: Vector3i = pos + Vector3i(0, -1, 0)
	var ground: int = get_block_world(ground_pos)
	if ground == BlockRegistry.BlockId.SUGAR_CANE:
		return true
	if ground != BlockRegistry.BlockId.GRASS and ground != BlockRegistry.BlockId.DIRT and ground != BlockRegistry.BlockId.SAND:
		return false
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if BlockRegistry.is_water(get_block_world(ground_pos + d)):
			return true
	return false


## Checks if block at world_pos is gravity-affected (Sand, Gravel) and triggers falling block.
func check_falling_block(world_pos: Vector3i) -> bool:
	if world_pos.y <= 0 or world_pos.y >= VoxelChunk.CHUNK_SIZE_Y:
		return false
	var bid: int = get_block_world(world_pos)
	if not BlockRegistry.is_gravity_block(bid):
		return false
	var below_pos := world_pos + Vector3i(0, -1, 0)
	var below_bid: int = get_block_world(below_pos)
	if below_bid == BlockRegistry.BlockId.AIR or BlockRegistry.is_liquid(below_bid) or BlockRegistry.is_passable_block(below_bid):
		var meta: int = get_metadata_world(world_pos)
		set_block_world(world_pos, BlockRegistry.BlockId.AIR)
		FallingBlockClass.spawn_falling_block(self, world_pos, bid, meta)
		return true
	return false


func _schedule_leaf_decay(log_pos: Vector3i) -> void:
	var r: int = LEAF_DECAY_RANGE + 1
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var p := log_pos + Vector3i(dx, dy, dz)
				if BlockRegistry.is_leaves(get_block_world(p)) and not _decay_candidates.has(p):
					_decay_candidates[p] = randf_range(0.6, 12.0)


func _process_leaf_decay(delta: float) -> void:
	if _decay_candidates.is_empty():
		return
	var due: Array[Vector3i] = []
	for p_variant in _decay_candidates.keys():
		var t: float = float(_decay_candidates[p_variant]) - delta
		if t <= 0.0:
			due.append(p_variant)
		else:
			_decay_candidates[p_variant] = t
	var budget: int = 6
	for p in due:
		if budget <= 0:
			break
		_decay_candidates.erase(p)
		budget -= 1
		var id: int = get_block_world(p)
		if not BlockRegistry.is_leaves(id):
			continue
		if (get_metadata_world(p) & 8) != 0:
			continue # Placed by a player: never decays
		if _leaf_connected_to_log(p):
			continue
		set_block_world(p, BlockRegistry.BlockId.AIR)
		_spawn_leaf_drops(p, id)


## Breadth-first search through leaves for a log within LEAF_DECAY_RANGE steps.
func _leaf_connected_to_log(start: Vector3i) -> bool:
	var frontier: Array[Vector3i] = [start]
	var seen: Dictionary = {start: true}
	for _step in range(LEAF_DECAY_RANGE):
		var next: Array[Vector3i] = []
		for p in frontier:
			for d in VoxelLighting.NEIGHBORS_6:
				var n: Vector3i = p + d
				if seen.has(n):
					continue
				seen[n] = true
				var nid: int = get_block_world(n)
				if BlockRegistry.is_log(nid):
					return true
				if BlockRegistry.is_leaves(nid):
					next.append(n)
		frontier = next
		if frontier.is_empty():
			break
	return false


## Leaves that decay or are broken without shears drop a sapling 1 in 20 times (oak: apple 1 in 200).
func _spawn_leaf_drops(p: Vector3i, leaf_id: int) -> void:
	var center := Vector3(p) + Vector3(0.5, 0.4, 0.5)
	if randf() < 0.05:
		DroppedItem.spawn_drop(self, center, sapling_for_leaves(leaf_id), 1)
	if leaf_id == BlockRegistry.BlockId.LEAVES and randf() < 0.005:
		DroppedItem.spawn_drop(self, center, InventoryManager.ItemId.APPLE, 1)


static func sapling_for_leaves(leaf_id: int) -> int:
	match leaf_id:
		BlockRegistry.BlockId.PINE_LEAVES:
			return BlockRegistry.BlockId.PINE_SAPLING
		BlockRegistry.BlockId.BIRCH_LEAVES:
			return BlockRegistry.BlockId.BIRCH_SAPLING
		_:
			return BlockRegistry.BlockId.SAPLING


# ============================================================================
# RANDOM TICKS: sugar cane, cactus, saplings
# ============================================================================

static func _is_random_tick_block(id: int) -> bool:
	return id == BlockRegistry.BlockId.SUGAR_CANE or id == BlockRegistry.BlockId.CACTUS or BlockRegistry.is_sapling(id)


func _register_tickables(coord: Vector2i, chunk: VoxelChunk) -> void:
	var set_for_chunk: Dictionary = {}
	var vox: PackedByteArray = chunk._voxels
	if not vox.is_empty():
		var ox: int = coord.x * VoxelChunk.CHUNK_SIZE_X
		var oz: int = coord.y * VoxelChunk.CHUNK_SIZE_Z
		for tick_id in [BlockRegistry.BlockId.SUGAR_CANE, BlockRegistry.BlockId.CACTUS, BlockRegistry.BlockId.SAPLING, BlockRegistry.BlockId.PINE_SAPLING, BlockRegistry.BlockId.BIRCH_SAPLING]:
			var idx: int = vox.find(tick_id)
			while idx != -1:
				set_for_chunk[Vector3i(ox + (idx & 15), idx >> 8, oz + ((idx >> 4) & 15))] = true
				idx = vox.find(tick_id, idx + 1)
	_tickables[coord] = set_for_chunk


func _track_tickable(pos: Vector3i, id: int) -> void:
	var coord := Vector2i(pos.x >> 4, pos.z >> 4)
	if not _tickables.has(coord):
		if not _is_random_tick_block(id):
			return
		_tickables[coord] = {}
	var set_for_chunk: Dictionary = _tickables[coord]
	if _is_random_tick_block(id):
		set_for_chunk[pos] = true
	else:
		set_for_chunk.erase(pos)


func _process_random_ticks(delta: float) -> void:
	_random_tick_timer += delta
	if _random_tick_timer < RANDOM_TICK_INTERVAL:
		return
	_random_tick_timer -= RANDOM_TICK_INTERVAL
	var hits: Array[Vector3i] = []
	for coord_variant in _tickables.keys():
		var set_for_chunk: Dictionary = _tickables[coord_variant]
		for p_variant in set_for_chunk.keys():
			if randf() < RANDOM_TICK_CHANCE:
				hits.append(p_variant)
	for p in hits:
		random_tick_block(p)


## Advances one random tick for the block at `pos` (public so tools/tests can force growth).
func random_tick_block(pos: Vector3i) -> void:
	var id: int = get_block_world(pos)
	if id == BlockRegistry.BlockId.SUGAR_CANE or id == BlockRegistry.BlockId.CACTUS:
		_tick_stalk_plant(pos, id)
	elif BlockRegistry.is_sapling(id):
		_tick_sapling(pos, id)


## Sugar cane and cactus: age 0..15 in metadata; at 15 a new block grows on top (max 3 tall).
func _tick_stalk_plant(pos: Vector3i, id: int) -> void:
	var above := pos + Vector3i(0, 1, 0)
	if get_block_world(above) != BlockRegistry.BlockId.AIR:
		return
	var height: int = 1
	while height < MAX_PLANT_HEIGHT and get_block_world(pos - Vector3i(0, height, 0)) == id:
		height += 1
	if height >= MAX_PLANT_HEIGHT:
		return
	var age: int = get_metadata_world(pos)
	if age >= 15:
		set_metadata_world(pos, 0, false)
		set_block_world(above, id)
		if not _is_supported(above, id):
			_check_support(above)
	else:
		set_metadata_world(pos, age + 1, false)


## Saplings need light 9+; each qualifying tick has a 1-in-7 chance to advance (two stages, then a tree).
func _tick_sapling(pos: Vector3i, id: int) -> void:
	var above := pos + Vector3i(0, 1, 0)
	if get_effective_light_world(above) < 9 or randf() >= 1.0 / 7.0:
		return
	var meta: int = get_metadata_world(pos)
	if (meta & 8) == 0:
		set_metadata_world(pos, meta | 8, false)
		return
	grow_tree_at(pos, id)


## Grows a tree from the sapling at `pos`. Returns false if there is not enough room.
func grow_tree_at(pos: Vector3i, sapling_id: int) -> bool:
	var log_id: int = BlockRegistry.BlockId.WOOD_LOG
	var leaf_id: int = BlockRegistry.BlockId.LEAVES
	var height: int = 4 + randi() % 3
	if sapling_id == BlockRegistry.BlockId.BIRCH_SAPLING:
		log_id = BlockRegistry.BlockId.BIRCH_LOG
		leaf_id = BlockRegistry.BlockId.BIRCH_LEAVES
		height = 5 + randi() % 3
	elif sapling_id == BlockRegistry.BlockId.PINE_SAPLING:
		log_id = BlockRegistry.BlockId.PINE_LOG
		leaf_id = BlockRegistry.BlockId.PINE_LEAVES
		height = 6 + randi() % 3

	var ground: int = get_block_world(pos + Vector3i(0, -1, 0))
	if ground != BlockRegistry.BlockId.GRASS and ground != BlockRegistry.BlockId.DIRT:
		return false
	if pos.y + height + 2 >= VoxelChunk.CHUNK_SIZE_Y:
		return false
	for y in range(1, height + 1):
		var b: int = get_block_world(pos + Vector3i(0, y, 0))
		if b != BlockRegistry.BlockId.AIR and not BlockRegistry.is_leaves(b):
			return false

	var leaves: Array[Vector3i] = []
	if log_id == BlockRegistry.BlockId.PINE_LOG:
		# Layered cone that narrows toward the top, plus a tip.
		var top_y: int = pos.y + height
		var radius: int = 0
		for y in range(top_y, pos.y + 2, -1):
			for dx in range(-radius, radius + 1):
				for dz in range(-radius, radius + 1):
					if radius > 0 and absi(dx) == radius and absi(dz) == radius:
						continue
					leaves.append(Vector3i(pos.x + dx, y, pos.z + dz))
			radius = 1 if radius == 0 else (2 if radius == 1 and (top_y - y) > 2 else (0 if radius == 2 else 1))
		leaves.append(Vector3i(pos.x, top_y + 1, pos.z))
	else:
		# Classic blob canopy: two wide layers and two narrow layers around the top of the trunk.
		var top: int = pos.y + height
		for y in range(top - 3, top + 1):
			var r: int = 2 if y <= top - 2 else 1
			for dx in range(-r, r + 1):
				for dz in range(-r, r + 1):
					if absi(dx) == r and absi(dz) == r and (y == top or randf() < 0.5):
						continue
					leaves.append(Vector3i(pos.x + dx, y, pos.z + dz))

	set_block_world(pos, BlockRegistry.BlockId.AIR)
	for p in leaves:
		if get_block_world(p) == BlockRegistry.BlockId.AIR:
			set_block_world(p, leaf_id)
	for y in range(0, height):
		set_block_world(pos + Vector3i(0, y, 0), log_id)
	return true


func get_metadata_world(world_block_pos: Vector3i) -> int:
	if world_block_pos.y < 0 or world_block_pos.y >= VoxelChunk.CHUNK_SIZE_Y:
		return 0
	var chunk: VoxelChunk = _active_chunks.get(Vector2i(world_block_pos.x >> 4, world_block_pos.z >> 4), null) as VoxelChunk
	if chunk == null:
		return 0
	return chunk.get_metadata_local(world_block_pos.x & 15, world_block_pos.y, world_block_pos.z & 15)


func set_metadata_world(world_block_pos: Vector3i, val: int, rebuild: bool = true) -> void:
	if world_block_pos.y < 0 or world_block_pos.y >= VoxelChunk.CHUNK_SIZE_Y:
		return
	var chunk: VoxelChunk = _active_chunks.get(Vector2i(world_block_pos.x >> 4, world_block_pos.z >> 4), null) as VoxelChunk
	if chunk == null:
		return
	chunk.set_metadata_local(world_block_pos.x & 15, world_block_pos.y, world_block_pos.z & 15, val, false)
	if rebuild:
		var dirty: Dictionary = {}
		VoxelLighting.mark_remesh(dirty, world_block_pos)
		_queue_dirty_remesh(dirty)


# ============================================================================
# WATER
# ============================================================================

func _enqueue_water_pos(pos: Vector3i) -> void:
	if pos.y <= 0 or pos.y >= VoxelChunk.CHUNK_SIZE_Y - 1:
		return
	if _water_flow_pending.has(pos):
		return
	_water_flow_pending[pos] = true
	_water_flow_queue.append(pos)


func _enqueue_water_neighborhood(center: Vector3i) -> void:
	_enqueue_water_pos(center)
	_enqueue_water_pos(center + Vector3i(0, 1, 0))
	_enqueue_water_pos(center + Vector3i(0, -1, 0))
	_enqueue_water_pos(center + Vector3i(1, 0, 0))
	_enqueue_water_pos(center + Vector3i(-1, 0, 0))
	_enqueue_water_pos(center + Vector3i(0, 0, 1))
	_enqueue_water_pos(center + Vector3i(0, 0, -1))


## Returns true if the liquid at `origin` can spread horizontally (either a Source block or resting on a solid/liquid floor).
func _can_liquid_spread_horizontally(origin: Vector3i, origin_id: int) -> bool:
	if origin_id == BlockRegistry.BlockId.WATER:
		return true
	var below_id: int = get_block_world(origin + Vector3i(0, -1, 0))
	return BlockRegistry.is_solid(below_id) or BlockRegistry.is_liquid(below_id)


## Computes shortest Manhattan distance (up to 4 steps) from `start` to a drop-off edge where water can fall down.
func _distance_to_drop_off(start: Vector3i, visited: Dictionary, depth: int) -> int:
	if depth > 4:
		return 999
	var below_id: int = get_block_world(start + Vector3i(0, -1, 0))
	if below_id == BlockRegistry.BlockId.AIR or (
		BlockRegistry.is_liquid(below_id)
		and below_id != BlockRegistry.BlockId.WATER
		and below_id != BlockRegistry.BlockId.WATER_FALLING
	):
		return depth

	if depth == 4:
		return 999

	var best: int = 999
	var dirs: Array[Vector3i] = [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1),
	]
	for d in dirs:
		var np: Vector3i = start + d
		if visited.has(np):
			continue
		var nid: int = get_block_world(np)
		if BlockRegistry.is_solid(nid) or nid == BlockRegistry.BlockId.WATER:
			continue
		visited[np] = true
		var dist: int = _distance_to_drop_off(np, visited, depth + 1)
		visited.erase(np)
		if dist < best:
			best = dist
	return best


## Returns true if spreading from `origin` in horizontal direction `dir` follows the path of least resistance toward a corner/drop-off.
func _is_allowed_spread_direction(origin: Vector3i, dir: Vector3i) -> bool:
	var dirs: Array[Vector3i] = [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1),
	]
	var scores: Dictionary = {}
	var min_score: int = 999

	for d in dirs:
		var neighbor: Vector3i = origin + d
		var nid: int = get_block_world(neighbor)
		if BlockRegistry.is_solid(nid) or nid == BlockRegistry.BlockId.WATER:
			scores[d] = 9999
			continue
		var visited: Dictionary = {origin: true, neighbor: true}
		var score: int = _distance_to_drop_off(neighbor, visited, 1)
		scores[d] = score
		if score < min_score:
			min_score = score

	if not scores.has(dir) or int(scores[dir]) >= 9999:
		return false
	if min_score <= 4:
		return int(scores[dir]) == min_score
	return true


## Evaluates what liquid block ID `pos` should hold based on its current neighbors.
func _compute_target_water_id(pos: Vector3i, cur_id: int) -> int:
	if cur_id == BlockRegistry.BlockId.WATER:
		return BlockRegistry.BlockId.WATER

	var dirs: Array[Vector3i] = [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1),
	]

	# If this position is LAVA and receiving water, it cools into Obsidian!
	if cur_id == BlockRegistry.BlockId.LAVA:
		for d in dirs:
			if BlockRegistry.is_water(get_block_world(pos + d)):
				_play_sfx_at("lava_cool", Vector3(pos) + Vector3(0.5, 0.5, 0.5))
				return BlockRegistry.BlockId.OBSIDIAN
		return BlockRegistry.BlockId.LAVA

	# Check if flowing water touches adjacent lava and cools it into Cobblestone
	for d in dirs:
		var nb_pos: Vector3i = pos + d
		if get_block_world(nb_pos) == BlockRegistry.BlockId.LAVA:
			set_block_world(nb_pos, BlockRegistry.BlockId.COBBLESTONE)
			_play_sfx_at("lava_cool", Vector3(nb_pos) + Vector3(0.5, 0.5, 0.5))

	# 1. Infinite water spring rule: 2+ orthogonal WATER sources over a solid/source floor -> WATER source
	var source_neighbors: int = 0
	for d in dirs:
		if get_block_world(pos + d) == BlockRegistry.BlockId.WATER:
			source_neighbors += 1
	var below_id: int = get_block_world(pos + Vector3i(0, -1, 0))
	if source_neighbors >= 2 and (BlockRegistry.is_solid(below_id) or below_id == BlockRegistry.BlockId.WATER):
		return BlockRegistry.BlockId.WATER

	# 2. Direct waterfall from liquid above
	var above_id: int = get_block_world(pos + Vector3i(0, 1, 0))
	if BlockRegistry.is_water(above_id):
		return BlockRegistry.BlockId.WATER_FALLING

	# 3. Horizontal spread from highest valid neighbor (decays by 1 level per horizontal step, stopping at level 1)
	var max_inflow_level: int = 0
	for d in dirs:
		var nb_pos: Vector3i = pos + d
		var nb_id: int = get_block_world(nb_pos)
		if not BlockRegistry.is_water(nb_id):
			continue
		if not _can_liquid_spread_horizontally(nb_pos, nb_id):
			continue
		var nb_lvl: int = BlockRegistry.get_water_level(nb_id)
		if nb_lvl <= 1:
			continue
		# If `pos` is currently AIR, enforce corner/drop-off pathfinding from `nb_pos`
		if cur_id == BlockRegistry.BlockId.AIR and not _is_allowed_spread_direction(nb_pos, -d):
			continue
		var candidate_lvl: int = nb_lvl - 1
		if candidate_lvl > max_inflow_level:
			max_inflow_level = candidate_lvl

	return BlockRegistry.make_flowing_water_id(max_inflow_level)


func _process_water_flow(delta: float) -> void:
	if _water_flow_queue.is_empty():
		return
	_water_tick_timer += delta
	if _water_tick_timer < WATER_TICK_INTERVAL:
		return
	_water_tick_timer = 0.0

	var updates: int = 0
	var batch_size: int = mini(_water_flow_queue.size(), MAX_WATER_SPREAD_PER_TICK)
	var dirty_water: Dictionary = {}

	for _i in range(batch_size):
		if _water_flow_queue.is_empty() or updates >= MAX_WATER_SPREAD_PER_TICK:
			break
		var pos: Vector3i = _water_flow_queue.pop_front()
		_water_flow_pending.erase(pos)

		if pos.y <= 0 or pos.y >= VoxelChunk.CHUNK_SIZE_Y - 1:
			continue

		var cur_id: int = get_block_world(pos)
		if BlockRegistry.is_solid(cur_id) or (cur_id != BlockRegistry.BlockId.AIR and not BlockRegistry.is_liquid(cur_id)):
			continue

		if cur_id != BlockRegistry.BlockId.WATER:
			var target_id: int = _compute_target_water_id(pos, cur_id)
			if target_id != cur_id:
				var next_id: int = target_id
				# Smooth receding drainage when water loses its source
				var cur_lvl: int = BlockRegistry.get_water_level(cur_id)
				var tgt_lvl: int = BlockRegistry.get_water_level(target_id)
				if cur_id != BlockRegistry.BlockId.WATER_FALLING and tgt_lvl < cur_lvl and cur_lvl > 2:
					next_id = BlockRegistry.make_flowing_water_id(maxi(tgt_lvl, cur_lvl - 2))
				# Mode 0: batch voxel change; water meshes are rebuilt once per tick below.
				if set_block_world(pos, next_id, 0):
					updates += 1
					VoxelLighting.mark_remesh(dirty_water, pos)
				if next_id != target_id:
					_enqueue_water_pos(pos)
				continue

		# If `pos` currently contains liquid, check if its neighbors need to receive flow
		var active_id: int = get_block_world(pos)
		if not BlockRegistry.is_liquid(active_id):
			continue

		var below: Vector3i = pos + Vector3i(0, -1, 0)
		var below_id: int = get_block_world(below)
		if below.y > 0 and (
			below_id == BlockRegistry.BlockId.AIR
			or (BlockRegistry.is_liquid(below_id) and below_id != BlockRegistry.BlockId.WATER and below_id != BlockRegistry.BlockId.WATER_FALLING)
		):
			_enqueue_water_pos(below)

		var active_lvl: int = BlockRegistry.get_water_level(active_id)
		if active_lvl > 1 and _can_liquid_spread_horizontally(pos, active_id):
			var dirs: Array[Vector3i] = [
				Vector3i(1, 0, 0),
				Vector3i(-1, 0, 0),
				Vector3i(0, 0, 1),
				Vector3i(0, 0, -1),
			]
			for d in dirs:
				var nb: Vector3i = pos + d
				var nb_id: int = get_block_world(nb)
				if nb_id == BlockRegistry.BlockId.AIR or (
					BlockRegistry.is_water(nb_id)
					and nb_id != BlockRegistry.BlockId.WATER
					and BlockRegistry.get_water_level(nb_id) < active_lvl - 1
				):
					if _is_allowed_spread_direction(pos, d):
						_enqueue_water_pos(nb)

	_queue_dirty_remesh(dirty_water, true)


## Automatically ticks crop growth, transitioning young sprouts to mature crops over ~12 seconds.
func _process_crop_growth(delta: float) -> void:
	if _active_crops.is_empty():
		return
	_crop_tick_timer += delta
	if _crop_tick_timer < 1.0:
		return
	_crop_tick_timer = 0.0

	var matured_crops: Array[Vector3i] = []
	for c_pos in _active_crops.keys():
		var pos_i: Vector3i = c_pos as Vector3i
		var current_id: int = get_block_world(pos_i)
		if current_id != BlockRegistry.BlockId.WHEAT_SPROUT and current_id != BlockRegistry.BlockId.POTATO_SPROUT:
			matured_crops.append(pos_i)
			continue

		var progress: float = float(_active_crops[pos_i]) + 1.0
		_active_crops[pos_i] = progress
		if progress >= 12.0: # 12 seconds to fully mature
			var mature_id: int = BlockRegistry.BlockId.WHEAT_CROPS if current_id == BlockRegistry.BlockId.WHEAT_SPROUT else BlockRegistry.BlockId.POTATO_CROPS
			set_block_world(pos_i, mature_id)
			matured_crops.append(pos_i)

	for m_pos in matured_crops:
		_active_crops.erase(m_pos)


## Returns the 3D directional water current vector at `world_pos` (pointing downhill / toward corners & waterfalls).
func get_water_flow_vector(world_pos: Vector3) -> Vector3:
	var bpos := Vector3i(floori(world_pos.x), floori(world_pos.y), floori(world_pos.z))
	var bid: int = get_block_world(bpos)
	if not BlockRegistry.is_liquid(bid):
		bpos.y = floori(world_pos.y + 0.35)
		bid = get_block_world(bpos)
		if not BlockRegistry.is_liquid(bid):
			return Vector3.ZERO

	var my_lvl: int = BlockRegistry.get_water_level(bid)
	var flow := Vector3.ZERO
	var dirs: Array[Vector3i] = [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1),
	]

	for d in dirs:
		var nb_pos: Vector3i = bpos + d
		var nb_id: int = get_block_world(nb_pos)
		if BlockRegistry.is_liquid(nb_id):
			var diff: int = my_lvl - BlockRegistry.get_water_level(nb_id)
			if diff != 0:
				flow += Vector3(float(d.x), 0.0, float(d.z)) * float(diff)
		elif nb_id == BlockRegistry.BlockId.AIR:
			# Check if neighbor drops off into a waterfall
			var nb_below: int = get_block_world(nb_pos + Vector3i(0, -1, 0))
			if nb_below == BlockRegistry.BlockId.AIR or BlockRegistry.is_liquid(nb_below):
				flow += Vector3(float(d.x), 0.0, float(d.z)) * 3.0

	if bid == BlockRegistry.BlockId.WATER_FALLING:
		flow.y -= 1.25

	return flow.normalized() if flow.length_squared() > 0.001 else Vector3.ZERO


## Returns local water depth (0.0 to 1.8) above the player's feet at `world_pos`.
func get_water_submersion_depth(world_pos: Vector3) -> float:
	var bx: int = floori(world_pos.x)
	var bz: int = floori(world_pos.z)
	var feet_y: int = floori(world_pos.y + 0.05)
	var feet_id: int = get_block_world(Vector3i(bx, feet_y, bz))
	var upper_id: int = get_block_world(Vector3i(bx, feet_y + 1, bz))

	var surface_world_y: float = -9999.0
	if BlockRegistry.is_liquid(upper_id):
		surface_world_y = float(feet_y + 1) + BlockRegistry.get_water_height_ratio(upper_id)
	elif BlockRegistry.is_liquid(feet_id):
		surface_world_y = float(feet_y) + BlockRegistry.get_water_height_ratio(feet_id)
	else:
		return 0.0

	return clampf(surface_world_y - world_pos.y, 0.0, 1.8)


# ============================================================================
# PERSISTENCE
# ============================================================================

func save_all_modified_chunks() -> int:
	if _storage == null:
		return 0
	for dict in [_active_chunks, _data_chunks]:
		for coord_variant in dict.keys():
			var coord: Vector2i = coord_variant
			var chunk: VoxelChunk = dict[coord]
			if is_instance_valid(chunk) and chunk.is_dirty:
				_storage.store_modified_chunk(
					coord,
					chunk.get_voxels_buffer(),
					chunk.get_highest_solid_y(),
					chunk.get_metadata_buffer(),
					false
				)
	return _storage.flush_all_to_disk()


func save_complete_world() -> int:
	var count: int = save_all_modified_chunks()
	var inv: Node = null
	if _player != null and is_instance_valid(_player):
		inv = _player.get_node_or_null("InventoryManager")
	if (inv == null or not is_instance_valid(inv)) and is_inside_tree() and get_tree() != null:
		inv = get_tree().get_first_node_in_group("inventory_manager")
	var dn: Node = get_node_or_null("../DayNightCycle")
	if dn == null and is_inside_tree() and get_tree() != null:
		dn = get_tree().get_first_node_in_group("day_night_cycle")
	GameSession.save_world_state(_player, inv, dn, self)
	world_saved.emit(count)
	return count


func get_active_chunk_count() -> int:
	return _active_chunks.size()


func get_modified_chunk_count() -> int:
	return _storage.get_modified_chunk_count() if _storage != null else 0


func get_surface_height_at(wx: int, wz: int) -> int:
	for y in range(VoxelChunk.CHUNK_SIZE_Y - 1, 0, -1):
		var id: int = get_block_world(Vector3i(wx, y, wz))
		if id != BlockRegistry.BlockId.AIR and not BlockRegistry.is_leaves(id) and not BlockRegistry.is_liquid(id):
			return y
	return _procedural_surface_height(wx, wz)


func _procedural_surface_height(wx: int, wz: int) -> int:
	return VoxelChunk.sample_surface_height(_surface_noise, wx, wz)


# ============================================================================
# EXPLOSIONS
# ============================================================================

## Ignites a placed TNT block into a physics-driven primed TNT entity.
func ignite_tnt_at(world_block_pos: Vector3i, custom_fuse: float = 4.0, initial_vel: Vector3 = Vector3(0.0, 2.0, 0.0)) -> void:
	if get_block_world(world_block_pos) != BlockRegistry.BlockId.TNT:
		return
	set_block_world(world_block_pos, BlockRegistry.BlockId.AIR)

	var sound_pos := Vector3(world_block_pos) + Vector3(0.5, 0.05, 0.5)
	var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if get_tree() != null else null
	if sfx != null and sfx.has_method("play_sfx_at_pos"):
		sfx.play_sfx_at_pos("fuse", sound_pos, 2.5, 1.0, 36.0)

	TNTPrimedClass.spawn_primed_tnt(self, sound_pos, initial_vel, custom_fuse)


## Batched explosion: clears voxels with one relight pass and coalesced sub-chunk remeshes,
## pooled drops, chained TNT and radial falloff damage. Bedrock and obsidian resist blasts and
## explosions submerged in water protect terrain while still dealing knockback.
func create_explosion(center: Vector3, radius: float = 3.8, is_tnt: bool = true, damage_player: bool = true) -> void:
	var tree: SceneTree = get_tree() if is_inside_tree() else null
	if tree != null:
		var sfx: Node = tree.get_first_node_in_group("sfx_player")
		if sfx != null and sfx.has_method("play_sfx_at_pos"):
			sfx.play_sfx_at_pos("explosion", center, 5.0, 1.0, 60.0)

	var center_i := Vector3i(floori(center.x), floori(center.y), floori(center.z))
	var rad_int: int = int(ceil(radius))
	var rad_sq: float = radius * radius

	var center_bid: int = get_block_world(center_i)
	var submerged_in_water: bool = BlockRegistry.is_water(center_bid)

	var tnt_to_chain: Array[Vector3i] = []
	var drop_candidates: Array[int] = []
	var cleared_positions: Array[Vector3i] = []
	var cleared_emitters: Array[Vector3i] = []
	var dirty: Dictionary = {}

	if not submerged_in_water:
		for dy in range(-rad_int, rad_int + 1):
			var wy: int = center_i.y + dy
			if wy <= 1 or wy >= VoxelChunk.CHUNK_SIZE_Y - 1:
				continue
			for dx in range(-rad_int, rad_int + 1):
				for dz in range(-rad_int, rad_int + 1):
					var dsq: float = float(dx * dx + dy * dy + dz * dz)
					if dsq > rad_sq:
						continue
					var bpos := center_i + Vector3i(dx, dy, dz)
					var bid: int = get_block_world(bpos)
					if bid == BlockRegistry.BlockId.AIR or BlockRegistry.is_water(bid):
						continue
					if bid == BlockRegistry.BlockId.BEDROCK or bid == BlockRegistry.BlockId.OBSIDIAN:
						continue
					if bid == BlockRegistry.BlockId.TNT:
						tnt_to_chain.append(bpos)
						continue
					var chunk: VoxelChunk = _active_chunks.get(Vector2i(bpos.x >> 4, bpos.z >> 4), null) as VoxelChunk
					if chunk == null:
						continue
					if randf() < 0.30:
						var drop_id: int = InventoryManager.get_dropped_item_for_block(bid, InventoryManager.ItemId.DIAMOND_PICKAXE)
						if drop_id > 0:
							drop_candidates.append(drop_id)
					if BlockRegistry.is_light_emitter(bid):
						cleared_emitters.append(bpos)
					chunk.set_block_local(bpos.x & 15, wy, bpos.z & 15, BlockRegistry.BlockId.AIR, false)
					_track_tickable(bpos, BlockRegistry.BlockId.AIR)
					cleared_positions.append(bpos)
					VoxelLighting.mark_remesh(dirty, bpos)
	else:
		for dy in range(-rad_int, rad_int + 1):
			for dx in range(-rad_int, rad_int + 1):
				for dz in range(-rad_int, rad_int + 1):
					var bpos := center_i + Vector3i(dx, dy, dz)
					if get_block_world(bpos) == BlockRegistry.BlockId.TNT:
						tnt_to_chain.append(bpos)

	# One relight pass for the whole crater, then coalesced remeshes.
	if not cleared_positions.is_empty():
		for e in cleared_emitters:
			VoxelLighting.update_light_at(self, e, dirty)
		VoxelLighting.refill_cleared(self, cleared_positions, dirty)
		_queue_dirty_remesh(dirty)
		for bpos in cleared_positions:
			_enqueue_water_neighborhood(bpos)

	# Spawn pooled drops (capped to prevent physics entity lag)
	var max_drops := mini(12, drop_candidates.size())
	for i in range(max_drops):
		var drop_item_id: int = drop_candidates[i]
		var spawn_pos: Vector3 = center + Vector3(randf_range(-1.2, 1.2), randf_range(0.2, 1.2), randf_range(-1.2, 1.2))
		DroppedItem.spawn_drop(self, spawn_pos, drop_item_id, 1)

	# Chain TNT with directional physics velocity & short fuse
	for tnt_pos in tnt_to_chain:
		var tnt_center := Vector3(tnt_pos) + Vector3(0.5, 0.5, 0.5)
		var out_dir: Vector3 = (tnt_center - center).normalized()
		if out_dir.length_squared() < 0.01:
			out_dir = Vector3.UP
		var blast_vel: Vector3 = out_dir * randf_range(5.0, 9.0) + Vector3(0.0, randf_range(2.5, 4.5), 0.0)
		ignite_tnt_at(tnt_pos, randf_range(0.5, 1.4), blast_vel)

	# Knockback nearby primed TNT entities
	var primed_list: Array = tree.get_nodes_in_group("primed_tnt") if tree != null else []
	for p in primed_list:
		if is_instance_valid(p) and p is Node3D and p.is_in_group("primed_tnt"):
			var p_tnt: Node3D = p
			var t_pos: Vector3 = p_tnt.global_position
			var dist: float = t_pos.distance_to(center)
			if dist > 0.1 and dist <= radius * 2.0:
				var push: Vector3 = (t_pos - center).normalized()
				var strength: float = (1.0 - (dist / (radius * 2.0))) * 12.0
				if "velocity" in p_tnt:
					p_tnt.velocity += push * strength + Vector3(0.0, 3.0, 0.0)

	# Overhanging gravity blocks collapse; unsupported plants, torches and doors pop off.
	for bpos in cleared_positions:
		check_falling_block(bpos + Vector3i(0, 1, 0))
		_check_support(bpos + Vector3i(0, 1, 0))

	# Entity damage & knockback to the player
	if damage_player and _player != null and is_instance_valid(_player) and _player is PlayerController:
		var p_ctrl := _player as PlayerController
		var p_pos: Vector3 = p_ctrl.global_position if p_ctrl.is_inside_tree() else p_ctrl.position
		var dist: float = p_pos.distance_to(center)
		var max_dmg_dist: float = radius * 1.6
		if dist <= max_dmg_dist:
			var dmg: int = maxi(2, int(round((max_dmg_dist - dist) * 2.5)))
			p_ctrl.take_damage(dmg)
			var push_dir: Vector3 = (p_pos - center).normalized()
			if push_dir.length_squared() < 0.01:
				push_dir = Vector3.UP
			p_ctrl.velocity += push_dir * 11.0 + Vector3(0.0, 5.5, 0.0)

	# Entity damage & knockback to nearby mobs
	var mobs: Array = tree.get_nodes_in_group("mobs") if tree != null else []
	for m in mobs:
		if is_instance_valid(m) and m is PassiveMob:
			var m_mob := m as PassiveMob
			var m_pos: Vector3 = m_mob.global_position if m_mob.is_inside_tree() else m_mob.position
			var m_dist: float = m_pos.distance_to(center)
			if m_dist <= radius * 1.8:
				var m_dmg: int = maxi(2, int(round((radius * 1.8 - m_dist) * 3.0)))
				m_mob.on_hit_by_player(center, m_dmg)


## Distance fog that ends just inside the loaded area hides chunk edges, like the classic game.
func _apply_fog_distance() -> void:
	var env_node: WorldEnvironment = get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if env_node == null or env_node.environment == null:
		return
	var fog_end: float = float(render_distance * VoxelChunk.CHUNK_SIZE_X) + 4.0
	env_node.environment.fog_depth_end = fog_end
	env_node.environment.fog_depth_begin = fog_end * 0.62
