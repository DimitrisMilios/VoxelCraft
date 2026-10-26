class_name WorldManager
extends Node3D
const GameSession = preload("res://scripts/core/game_session.gd")
## Manages endless procedural chunk generation, WorkerThreadPool background streaming,
## cross-chunk border face culling, cellular-automata water flow, and ChunkStorage persistence.

signal world_saved(saved_chunk_count: int)

const WATER_TICK_INTERVAL: float = 0.25
const MAX_WATER_SPREAD_PER_TICK: int = 8

@export_group("World Generation")
@export var world_seed: int = 2027
@export var render_distance: int = 4
@export var max_concurrent_tasks: int = 4
@export var max_main_thread_applies_per_frame: int = 1

@export_group("References")
@export var player_path: NodePath = NodePath("../Player")

## Active chunk nodes in the scene tree: `Vector2i(cx, cz) -> VoxelChunk`.
var _active_chunks: Dictionary = {}

## Thread-safe mirror of active chunk voxel buffers for lock-guarded worker neighbor reads.
var _chunk_voxel_mirror: Dictionary = {}
var _mirror_mutex: Mutex = Mutex.new()

## Coordinates currently queued or running on WorkerThreadPool.
var _load_queue: Array[Vector2i] = []
var _in_flight_coords: Dictionary = {}
var _active_task_ids: Array[int] = []
var _is_shutting_down: bool = false

## Completed background chunk builds waiting to be attached on the main thread.
var _completed_builds: Array[Dictionary] = []
var _completed_mutex: Mutex = Mutex.new()

## Cellular-automata water flow queue (`Vector3i` world block coordinates).
var _water_flow_queue: Array[Vector3i] = []
var _water_flow_pending: Dictionary = {}
var _water_tick_timer: float = 0.0

var _storage: ChunkStorage = null
var _surface_noise: FastNoiseLite = FastNoiseLite.new()
var _cave_noise: FastNoiseLite = FastNoiseLite.new()
var _player: Node3D = null
var _last_player_chunk: Vector2i = Vector2i(999999, 999999)


func _ready() -> void:
	add_to_group("world_manager")
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
				var has_bed: bool = bool(p_data.get("has_bed", false))
				_player.set("has_custom_respawn", has_bed)
				if has_bed and p_data.has("bed_pos") and p_data["bed_pos"] is Array:
					var b_arr: Array = p_data["bed_pos"]
					_player.set("custom_respawn_pos", Vector3(b_arr[0], b_arr[1], b_arr[2]))
	elif _player != null:
		start_chunk = world_to_chunk_coords(_player.global_position)

	# Synchronously build the immediate 3x3 spawn area so the player starts on solid ground
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_spawn_chunk_immediate(start_chunk + Vector2i(dx, dz))

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
					var test_y: int = get_surface_height_at(test_x, test_z)
					if test_y > VoxelChunk.WATER_LEVEL + 1:
						spawn_wx = test_x
						spawn_wz = test_z
						surface_y = test_y
						found = true
						break
				if found:
					break
		_player.global_position = Vector3(float(spawn_wx) + 0.5, float(surface_y) + 2.5, float(spawn_wz) + 0.5)

	_update_chunk_targets(start_chunk)
	_last_player_chunk = start_chunk


func _exit_tree() -> void:
	_is_shutting_down = true
	for tid in _active_task_ids:
		WorkerThreadPool.wait_for_task_completion(tid)
	_active_task_ids.clear()
	save_complete_world()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_is_shutting_down = true
		save_complete_world()


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
	_process_water_flow(delta)
	VoxelAtlasBuilder.update_water_animation(delta)


## Dynamically updates chunk render distance at runtime (e.g. from the Pause Menu).
func set_render_distance(new_distance: int) -> void:
	var clamped: int = clampi(new_distance, 3, 16)
	if clamped == render_distance:
		return
	render_distance = clamped
	if _player != null:
		_last_player_chunk = world_to_chunk_coords(_player.global_position)
		_update_chunk_targets(_last_player_chunk)


## Generates a fresh world map with a new seed, clearing active chunks and respawning on the new surface.
func regenerate_world_with_new_seed() -> int:
	_is_shutting_down = true
	for tid in _active_task_ids:
		WorkerThreadPool.wait_for_task_completion(tid)
	_active_task_ids.clear()
	_in_flight_coords.clear()
	_load_queue.clear()
	_completed_mutex.lock()
	_completed_builds.clear()
	_completed_mutex.unlock()
	_water_flow_queue.clear()
	_water_flow_pending.clear()

	for coord_variant in _active_chunks.keys():
		var chunk: VoxelChunk = _active_chunks[coord_variant]
		if is_instance_valid(chunk):
			chunk.queue_free()
	_active_chunks.clear()

	_mirror_mutex.lock()
	_chunk_voxel_mirror.clear()
	_mirror_mutex.unlock()

	world_seed += 1
	_storage = ChunkStorage.new(world_seed)
	_configure_noise()
	_is_shutting_down = false

	var start_chunk := Vector2i.ZERO
	if _player != null:
		_player.global_position = Vector3(8.5, 65.0, 8.5)
		start_chunk = world_to_chunk_coords(_player.global_position)

	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_spawn_chunk_immediate(start_chunk + Vector2i(dx, dz))

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


func _update_chunk_targets(center_chunk: Vector2i) -> void:
	var unload_radius: int = render_distance + 1
	var chunks_to_remove: Array[Vector2i] = []
	for coord_variant in _active_chunks.keys():
		var coord: Vector2i = coord_variant
		if absi(coord.x - center_chunk.x) > unload_radius or absi(coord.y - center_chunk.y) > unload_radius:
			chunks_to_remove.append(coord)

	for coord in chunks_to_remove:
		var chunk: VoxelChunk = _active_chunks[coord]
		_active_chunks.erase(coord)
		_mirror_mutex.lock()
		_chunk_voxel_mirror.erase(coord)
		_mirror_mutex.unlock()

		if is_instance_valid(chunk):
			if chunk.is_dirty:
				_storage.store_modified_chunk(
					coord,
					chunk.get_voxels_buffer(),
					chunk.get_highest_solid_y(),
					true
				)
			chunk.queue_free()

	_load_queue.clear()
	for dx in range(-render_distance, render_distance + 1):
		for dz in range(-render_distance, render_distance + 1):
			var target_coord := Vector2i(center_chunk.x + dx, center_chunk.y + dz)
			if not _active_chunks.has(target_coord) and not _in_flight_coords.has(target_coord):
				_load_queue.append(target_coord)

	_load_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var dist_a: int = (a.x - center_chunk.x) * (a.x - center_chunk.x) + (a.y - center_chunk.y) * (a.y - center_chunk.y)
		var dist_b: int = (b.x - center_chunk.x) * (b.x - center_chunk.x) + (b.y - center_chunk.y) * (b.y - center_chunk.y)
		return dist_a < dist_b
	)


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

	while not _load_queue.is_empty() and _in_flight_coords.size() < max_concurrent_tasks:
		var coord: Vector2i = _load_queue.pop_front()
		if _active_chunks.has(coord) or _in_flight_coords.has(coord):
			continue
		_in_flight_coords[coord] = true
		var task_id: int = WorkerThreadPool.add_task(_worker_build_chunk.bind(coord), false, "BuildChunk_%d_%d" % [coord.x, coord.y])
		_active_task_ids.append(task_id)


func _worker_build_chunk(coord: Vector2i) -> void:
	if _is_shutting_down:
		return
	var chunk := VoxelChunk.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk.chunk_coords = coord
	chunk.neighbor_block_getter = get_block_or_procedural_world

	var saved_data: Dictionary = _storage.load_chunk_data(coord)
	if not saved_data.is_empty():
		chunk.load_from_buffer(saved_data["voxels"], int(saved_data["highest_y"]))
	else:
		chunk.generate_terrain(_surface_noise, _cave_noise)

	if _is_shutting_down:
		return

	_mirror_mutex.lock()
	_chunk_voxel_mirror[coord] = chunk.get_voxels_buffer()
	_mirror_mutex.unlock()

	var mesh_data: Dictionary = chunk.build_mesh_data()

	_completed_mutex.lock()
	_completed_builds.append({
		"coord": coord,
		"chunk": chunk,
		"mesh_data": mesh_data,
	})
	_completed_mutex.unlock()


func _apply_completed_builds() -> void:
	var applied: int = 0
	while applied < max_main_thread_applies_per_frame:
		_completed_mutex.lock()
		if _completed_builds.is_empty():
			_completed_mutex.unlock()
			break
		var item: Dictionary = _completed_builds.pop_front()
		_completed_mutex.unlock()

		var coord: Vector2i = item["coord"]
		var chunk: VoxelChunk = item["chunk"]
		var mesh_data: Dictionary = item["mesh_data"]
		_in_flight_coords.erase(coord)

		if _active_chunks.has(coord):
			chunk.free()
			continue

		chunk.position = Vector3(
			float(coord.x * VoxelChunk.CHUNK_SIZE_X),
			0.0,
			float(coord.y * VoxelChunk.CHUNK_SIZE_Z)
		)
		add_child(chunk)
		chunk.apply_mesh_data(mesh_data)
		_active_chunks[coord] = chunk
		applied += 1


func _spawn_chunk_immediate(coord: Vector2i) -> VoxelChunk:
	if _active_chunks.has(coord):
		return _active_chunks[coord]

	var chunk := VoxelChunk.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk.chunk_coords = coord
	chunk.neighbor_block_getter = get_block_or_procedural_world
	chunk.position = Vector3(
		float(coord.x * VoxelChunk.CHUNK_SIZE_X),
		0.0,
		float(coord.y * VoxelChunk.CHUNK_SIZE_Z)
	)
	add_child(chunk)

	var saved_data: Dictionary = _storage.load_chunk_data(coord)
	if not saved_data.is_empty():
		chunk.load_from_buffer(saved_data["voxels"], int(saved_data["highest_y"]))
	else:
		chunk.generate_terrain(_surface_noise, _cave_noise)

	_mirror_mutex.lock()
	_chunk_voxel_mirror[coord] = chunk.get_voxels_buffer()
	_mirror_mutex.unlock()

	chunk.rebuild_mesh()
	_active_chunks[coord] = chunk
	return chunk


## Thread-safe neighbor query used during mesh generation for cross-chunk face culling.
func get_block_or_procedural_world(world_block_pos: Vector3i) -> int:
	if world_block_pos.y < 0:
		return BlockRegistry.BlockId.STONE
	if world_block_pos.y >= VoxelChunk.CHUNK_SIZE_Y:
		return BlockRegistry.BlockId.AIR

	var cx: int = floori(float(world_block_pos.x) / float(VoxelChunk.CHUNK_SIZE_X))
	var cz: int = floori(float(world_block_pos.z) / float(VoxelChunk.CHUNK_SIZE_Z))
	var chunk_coord := Vector2i(cx, cz)
	var lx: int = posmod(world_block_pos.x, VoxelChunk.CHUNK_SIZE_X)
	var lz: int = posmod(world_block_pos.z, VoxelChunk.CHUNK_SIZE_Z)
	var flat_idx: int = (world_block_pos.y * VoxelChunk.CHUNK_SIZE_Z + lz) * VoxelChunk.CHUNK_SIZE_X + lx

	_mirror_mutex.lock()
	if _chunk_voxel_mirror.has(chunk_coord):
		var buf: PackedByteArray = _chunk_voxel_mirror[chunk_coord]
		if flat_idx >= 0 and flat_idx < buf.size():
			var val: int = buf[flat_idx]
			_mirror_mutex.unlock()
			return val
	_mirror_mutex.unlock()

	var surface_y: int = VoxelChunk.sample_surface_height(_surface_noise, world_block_pos.x, world_block_pos.z)
	return VoxelChunk.sample_terrain_voxel(
		surface_y,
		world_block_pos.x,
		world_block_pos.y,
		world_block_pos.z,
		_cave_noise
	)


static func world_to_chunk_coords(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / float(VoxelChunk.CHUNK_SIZE_X)),
		floori(world_pos.z / float(VoxelChunk.CHUNK_SIZE_Z))
	)


func get_block_world(world_block_pos: Vector3i) -> int:
	if world_block_pos.y < 0 or world_block_pos.y >= VoxelChunk.CHUNK_SIZE_Y:
		return BlockRegistry.BlockId.AIR

	var cx: int = floori(float(world_block_pos.x) / float(VoxelChunk.CHUNK_SIZE_X))
	var cz: int = floori(float(world_block_pos.z) / float(VoxelChunk.CHUNK_SIZE_Z))
	var chunk_coord := Vector2i(cx, cz)
	if not _active_chunks.has(chunk_coord):
		return BlockRegistry.BlockId.AIR

	var lx: int = posmod(world_block_pos.x, VoxelChunk.CHUNK_SIZE_X)
	var lz: int = posmod(world_block_pos.z, VoxelChunk.CHUNK_SIZE_Z)
	var chunk: VoxelChunk = _active_chunks[chunk_coord]
	return chunk.get_block_local(lx, world_block_pos.y, lz)


## Checks whether a world position is illuminated by any nearby light emitters (Torches, Glowstone, Lava, Furnaces).
## In Minecraft rules, hostile mobs cannot spawn within ~9-11 blocks of a torch or light source.
func is_position_illuminated_by_blocks(world_pos: Vector3, light_range: float = 11.0) -> bool:
	var base_chunk := world_to_chunk_coords(world_pos)

	# 1. Check OmniLight3D emitters registered in current and adjacent 8 chunks
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var c_coord := base_chunk + Vector2i(dx, dz)
			if _active_chunks.has(c_coord):
				var chunk: VoxelChunk = _active_chunks[c_coord]
				for local_pos in chunk._block_lights.keys():
					var light_node: OmniLight3D = chunk._block_lights[local_pos]
					var l_range: float = light_node.omni_range if (light_node != null and is_instance_valid(light_node)) else light_range
					var chunk_origin: Vector3 = chunk.global_position if chunk.is_inside_tree() else chunk.position
					var l_world: Vector3 = chunk_origin + Vector3(local_pos) + Vector3(0.5, 0.5, 0.5)
					if world_pos.distance_squared_to(l_world) <= (l_range * l_range):
						return true

	# 2. Check local block neighborhood around world_pos for any light-emitting blocks
	var ipos := Vector3i(floori(world_pos.x), floori(world_pos.y), floori(world_pos.z))
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


func set_block_world(world_block_pos: Vector3i, block_id: int, rebuild_mode: int = 2) -> bool:
	if world_block_pos.y <= 0 or world_block_pos.y >= VoxelChunk.CHUNK_SIZE_Y:
		return false

	var cx: int = floori(float(world_block_pos.x) / float(VoxelChunk.CHUNK_SIZE_X))
	var cz: int = floori(float(world_block_pos.z) / float(VoxelChunk.CHUNK_SIZE_Z))
	var chunk_coord := Vector2i(cx, cz)
	if not _active_chunks.has(chunk_coord):
		return false

	var lx: int = posmod(world_block_pos.x, VoxelChunk.CHUNK_SIZE_X)
	var lz: int = posmod(world_block_pos.z, VoxelChunk.CHUNK_SIZE_Z)
	var chunk: VoxelChunk = _active_chunks[chunk_coord]

	var actual_block_id: int = block_id
	if block_id == BlockRegistry.BlockId.LAVA:
		var has_water_nb: bool = false
		for d in [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
			if BlockRegistry.is_liquid(get_block_world(world_block_pos + d)):
				has_water_nb = true
				break
		if has_water_nb:
			actual_block_id = BlockRegistry.BlockId.OBSIDIAN
			var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if get_tree() != null else null
			if sfx != null and sfx.has_method("play_sfx_at_pos"):
				sfx.play_sfx_at_pos("lava_cool", Vector3(world_block_pos) + Vector3(0.5, 0.5, 0.5), 1.0)
	elif BlockRegistry.is_liquid(block_id):
		for d in [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
			var nb_pos: Vector3i = world_block_pos + d
			if get_block_world(nb_pos) == BlockRegistry.BlockId.LAVA:
				set_block_world(nb_pos, BlockRegistry.BlockId.COBBLESTONE)
				var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if get_tree() != null else null
				if sfx != null and sfx.has_method("play_sfx_at_pos"):
					sfx.play_sfx_at_pos("lava_cool", Vector3(nb_pos) + Vector3(0.5, 0.5, 0.5), 1.0)

	chunk.set_block_local(lx, world_block_pos.y, lz, actual_block_id, false)

	_mirror_mutex.lock()
	_chunk_voxel_mirror[chunk_coord] = chunk.get_voxels_buffer()
	_mirror_mutex.unlock()

	_storage.store_modified_chunk(
		chunk_coord,
		chunk.get_voxels_buffer(),
		chunk.get_highest_solid_y(),
		false
	)

	if rebuild_mode == 2:
		chunk.rebuild_at_local_y(world_block_pos.y)

		# If near a chunk boundary (within 1 block for shared water corner vertices), rebuild neighbor sub-chunk
		if lx <= 1 and _active_chunks.has(chunk_coord + Vector2i(-1, 0)):
			(_active_chunks[chunk_coord + Vector2i(-1, 0)] as VoxelChunk).rebuild_at_local_y(world_block_pos.y)
		elif lx >= VoxelChunk.CHUNK_SIZE_X - 2 and _active_chunks.has(chunk_coord + Vector2i(1, 0)):
			(_active_chunks[chunk_coord + Vector2i(1, 0)] as VoxelChunk).rebuild_at_local_y(world_block_pos.y)

		if lz <= 1 and _active_chunks.has(chunk_coord + Vector2i(0, -1)):
			(_active_chunks[chunk_coord + Vector2i(0, -1)] as VoxelChunk).rebuild_at_local_y(world_block_pos.y)
		elif lz >= VoxelChunk.CHUNK_SIZE_Z - 2 and _active_chunks.has(chunk_coord + Vector2i(0, 1)):
			(_active_chunks[chunk_coord + Vector2i(0, 1)] as VoxelChunk).rebuild_at_local_y(world_block_pos.y)
	elif rebuild_mode == 1:
		chunk.rebuild_water_at_local_y(world_block_pos.y)

	# Enqueue 6-connected neighborhood for finite 8-level water flow & drainage
	_enqueue_water_neighborhood(world_block_pos)

	return true

	# Enqueue 6-connected neighborhood for finite 8-level water flow & drainage
	_enqueue_water_neighborhood(world_block_pos)

	return true


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
			if BlockRegistry.is_liquid(get_block_world(pos + d)):
				var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if get_tree() != null else null
				if sfx != null and sfx.has_method("play_sfx_at_pos"):
					sfx.play_sfx_at_pos("lava_cool", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 1.0)
				return BlockRegistry.BlockId.OBSIDIAN
		return BlockRegistry.BlockId.LAVA

	# Check if flowing water touches adjacent lava and cools it into Cobblestone
	for d in dirs:
		var nb_pos: Vector3i = pos + d
		if get_block_world(nb_pos) == BlockRegistry.BlockId.LAVA:
			set_block_world(nb_pos, BlockRegistry.BlockId.COBBLESTONE)
			var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if get_tree() != null else null
			if sfx != null and sfx.has_method("play_sfx_at_pos"):
				sfx.play_sfx_at_pos("lava_cool", Vector3(nb_pos) + Vector3(0.5, 0.5, 0.5), 1.0)

	# 1. Minecraft 2x2 Infinite Water Spring Rule: 2+ orthogonal WATER sources over a solid/source floor -> WATER source
	var source_neighbors: int = 0
	for d in dirs:
		if get_block_world(pos + d) == BlockRegistry.BlockId.WATER:
			source_neighbors += 1
	var below_id: int = get_block_world(pos + Vector3i(0, -1, 0))
	if source_neighbors >= 2 and (BlockRegistry.is_solid(below_id) or below_id == BlockRegistry.BlockId.WATER):
		return BlockRegistry.BlockId.WATER

	# 2. Direct waterfall from liquid above
	var above_id: int = get_block_world(pos + Vector3i(0, 1, 0))
	if BlockRegistry.is_liquid(above_id):
		return BlockRegistry.BlockId.WATER_FALLING

	# 3. Horizontal spread from highest valid neighbor (decays by 1 level per horizontal step, stopping at level 1)
	var max_inflow_level: int = 0
	for d in dirs:
		var nb_pos: Vector3i = pos + d
		var nb_id: int = get_block_world(nb_pos)
		if not BlockRegistry.is_liquid(nb_id):
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
	var dirty_water_chunks: Dictionary = {}

	for _i in range(batch_size):
		if _water_flow_queue.is_empty() or updates >= MAX_WATER_SPREAD_PER_TICK:
			break
		var pos: Vector3i = _water_flow_queue.pop_front()
		_water_flow_pending.erase(pos)

		if pos.y <= 0 or pos.y >= VoxelChunk.CHUNK_SIZE_Y - 1:
			continue

		var cur_id: int = get_block_world(pos)
		if BlockRegistry.is_solid(cur_id):
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
				if set_block_world(pos, next_id, 0): # Mode 0: Batch voxel change without immediate rebuild
					updates += 1
					var cx: int = floori(float(pos.x) / float(VoxelChunk.CHUNK_SIZE_X))
					var cz: int = floori(float(pos.z) / float(VoxelChunk.CHUNK_SIZE_Z))
					var c_coord := Vector2i(cx, cz)
					if _active_chunks.has(c_coord):
						var ch: VoxelChunk = _active_chunks[c_coord]
						if not dirty_water_chunks.has(ch):
							dirty_water_chunks[ch] = {}
						dirty_water_chunks[ch][pos.y] = true

						var lx: int = posmod(pos.x, VoxelChunk.CHUNK_SIZE_X)
						var lz: int = posmod(pos.z, VoxelChunk.CHUNK_SIZE_Z)
						if lx <= 1 and _active_chunks.has(c_coord + Vector2i(-1, 0)):
							var nb_ch: VoxelChunk = _active_chunks[c_coord + Vector2i(-1, 0)]
							if not dirty_water_chunks.has(nb_ch):
								dirty_water_chunks[nb_ch] = {}
							dirty_water_chunks[nb_ch][pos.y] = true
						elif lx >= VoxelChunk.CHUNK_SIZE_X - 2 and _active_chunks.has(c_coord + Vector2i(1, 0)):
							var nb_ch: VoxelChunk = _active_chunks[c_coord + Vector2i(1, 0)]
							if not dirty_water_chunks.has(nb_ch):
								dirty_water_chunks[nb_ch] = {}
							dirty_water_chunks[nb_ch][pos.y] = true

						if lz <= 1 and _active_chunks.has(c_coord + Vector2i(0, -1)):
							var nb_ch: VoxelChunk = _active_chunks[c_coord + Vector2i(0, -1)]
							if not dirty_water_chunks.has(nb_ch):
								dirty_water_chunks[nb_ch] = {}
							dirty_water_chunks[nb_ch][pos.y] = true
						elif lz >= VoxelChunk.CHUNK_SIZE_Z - 2 and _active_chunks.has(c_coord + Vector2i(0, 1)):
							var nb_ch: VoxelChunk = _active_chunks[c_coord + Vector2i(0, 1)]
							if not dirty_water_chunks.has(nb_ch):
								dirty_water_chunks[nb_ch] = {}
							dirty_water_chunks[nb_ch][pos.y] = true

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
					BlockRegistry.is_liquid(nb_id)
					and nb_id != BlockRegistry.BlockId.WATER
					and BlockRegistry.get_water_level(nb_id) < active_lvl - 1
				):
					if _is_allowed_spread_direction(pos, d):
						_enqueue_water_pos(nb)

	# Batch-apply all dirty water subchunks in 0.05ms each without rebuilding trimesh collision
	for ch in dirty_water_chunks.keys():
		var y_dict: Dictionary = dirty_water_chunks[ch]
		for y_val in y_dict.keys():
			(ch as VoxelChunk).rebuild_water_at_local_y(int(y_val))


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


func save_all_modified_chunks() -> int:
	if _storage == null:
		return 0
	for coord_variant in _active_chunks.keys():
		var coord: Vector2i = coord_variant
		var chunk: VoxelChunk = _active_chunks[coord]
		if is_instance_valid(chunk) and chunk.is_dirty:
			_storage.store_modified_chunk(
				coord,
				chunk.get_voxels_buffer(),
				chunk.get_highest_solid_y(),
				false
			)
	return _storage.flush_all_to_disk()


func save_complete_world() -> int:
	var count: int = save_all_modified_chunks()
	var inv: Node = get_node_or_null("../InventoryManager")
	if inv == null and get_tree() != null:
		inv = get_tree().get_first_node_in_group("inventory_manager")
	var dn: Node = get_node_or_null("../DayNightCycle")
	if dn == null and get_tree() != null:
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
		if id != BlockRegistry.BlockId.AIR and id != BlockRegistry.BlockId.LEAVES and not BlockRegistry.is_liquid(id):
			return y
	return VoxelChunk.sample_surface_height(_surface_noise, wx, wz)


## Ignites a placed TNT block into a 3.0-second flashing primed entity that blasts a spherical crater.
func ignite_tnt_at(world_block_pos: Vector3i) -> void:
	if get_block_world(world_block_pos) != BlockRegistry.BlockId.TNT:
		return
	set_block_world(world_block_pos, BlockRegistry.BlockId.AIR)

	var sound_pos := Vector3(world_block_pos) + Vector3(0.5, 0.5, 0.5)
	var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if get_tree() != null else null
	if sfx != null and sfx.has_method("play_sfx_at_pos"):
		sfx.play_sfx_at_pos("fuse", sound_pos, 2.0, 1.0, 36.0)

	var tnt_mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.96, 0.96, 0.96)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.25, 0.20)
	box.material = mat
	tnt_mi.mesh = box
	tnt_mi.position = sound_pos
	add_child(tnt_mi)

	var tw: Tween = create_tween()
	for i in range(6):
		tw.tween_property(mat, "albedo_color", Color(1.0, 1.0, 1.0), 0.22)
		tw.tween_property(mat, "albedo_color", Color(0.95, 0.20, 0.16), 0.22)
	tw.tween_callback(_detonate_tnt_at.bind(world_block_pos, tnt_mi))


func _detonate_tnt_at(center: Vector3i, visual_node: Node3D) -> void:
	if is_instance_valid(visual_node):
		visual_node.queue_free()
	create_explosion(Vector3(center) + Vector3(0.5, 0.5, 0.5), 3.2, true, true)


## High-performance batched explosion that destroys voxels with minimal sub-chunk mesh rebuilds,
## pooled entity drops, chained TNT, and realistic radial falloff damage.
func create_explosion(center: Vector3, radius: float = 3.2, is_tnt: bool = true, damage_player: bool = true) -> void:
	if get_tree() != null:
		var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
		if sfx != null and sfx.has_method("play_sfx_at_pos"):
			sfx.play_sfx_at_pos("explosion", center, 5.0, 1.0, 60.0)

	var center_i := Vector3i(floori(center.x), floori(center.y), floori(center.z))
	var rad_int: int = int(ceil(radius))
	var rad_sq: float = radius * radius

	# 1. Gather all blocks to destroy and group by chunk coordinate
	var affected_chunks: Dictionary = {} # Vector2i -> Array[Dictionary]
	var tnt_to_chain: Array[Vector3i] = []
	var drop_candidates: Array[int] = []

	for dy in range(-rad_int, rad_int + 1):
		var wy: int = center_i.y + dy
		if wy <= 1 or wy >= VoxelChunk.CHUNK_SIZE_Y - 1:
			continue
		for dx in range(-rad_int, rad_int + 1):
			for dz in range(-rad_int, rad_int + 1):
				var dsq: float = float(dx * dx + dy * dy + dz * dz)
				if dsq <= rad_sq:
					var bpos := center_i + Vector3i(dx, dy, dz)
					var bid: int = get_block_world(bpos)
					if bid == BlockRegistry.BlockId.AIR:
						continue
					if bid == BlockRegistry.BlockId.TNT:
						tnt_to_chain.append(bpos)
						continue
					if BlockRegistry.is_solid(bid):
						if randf() < 0.28:
							var drop_id: int = InventoryManager.get_dropped_item_for_block(bid, InventoryManager.ItemId.DIAMOND_PICKAXE)
							if drop_id > 0:
								drop_candidates.append(drop_id)

						var cx: int = floori(float(bpos.x) / float(VoxelChunk.CHUNK_SIZE_X))
						var cz: int = floori(float(bpos.z) / float(VoxelChunk.CHUNK_SIZE_Z))
						var c_coord := Vector2i(cx, cz)
						if not affected_chunks.has(c_coord):
							affected_chunks[c_coord] = []
						var lx: int = posmod(bpos.x, VoxelChunk.CHUNK_SIZE_X)
						var lz: int = posmod(bpos.z, VoxelChunk.CHUNK_SIZE_Z)
						affected_chunks[c_coord].append({
							"lx": lx,
							"ly": wy,
							"lz": lz,
							"wx": bpos.x,
							"wz": bpos.z,
						})

	# 2. Batch apply block clearance & rebuild only unique sub-chunks
	for c_coord_var in affected_chunks:
		var c_coord: Vector2i = c_coord_var
		if not _active_chunks.has(c_coord):
			continue
		var chunk: VoxelChunk = _active_chunks[c_coord]
		var block_list: Array = affected_chunks[c_coord]
		var sub_indices: Dictionary = {}
		var neighbor_rebuild: Dictionary = {}

		for b in block_list:
			chunk.set_block_local(b["lx"], b["ly"], b["lz"], BlockRegistry.BlockId.AIR, false)
			var sub_idx: int = clampi(b["ly"] / VoxelChunk.SUB_CHUNK_HEIGHT, 0, VoxelChunk.SUB_CHUNK_COUNT - 1)
			sub_indices[sub_idx] = true

			var local_sub_y: int = b["ly"] % VoxelChunk.SUB_CHUNK_HEIGHT
			if local_sub_y == 0 and sub_idx > 0:
				sub_indices[sub_idx - 1] = true
			elif local_sub_y == VoxelChunk.SUB_CHUNK_HEIGHT - 1 and sub_idx < VoxelChunk.SUB_CHUNK_COUNT - 1:
				sub_indices[sub_idx + 1] = true

			# Neighbor chunk boundaries
			if b["lx"] <= 1:
				var n_coord: Vector2i = c_coord + Vector2i(-1, 0)
				if not neighbor_rebuild.has(n_coord): neighbor_rebuild[n_coord] = {}
				neighbor_rebuild[n_coord][sub_idx] = true
			elif b["lx"] >= VoxelChunk.CHUNK_SIZE_X - 2:
				var n_coord: Vector2i = c_coord + Vector2i(1, 0)
				if not neighbor_rebuild.has(n_coord): neighbor_rebuild[n_coord] = {}
				neighbor_rebuild[n_coord][sub_idx] = true

			if b["lz"] <= 1:
				var n_coord: Vector2i = c_coord + Vector2i(0, -1)
				if not neighbor_rebuild.has(n_coord): neighbor_rebuild[n_coord] = {}
				neighbor_rebuild[n_coord][sub_idx] = true
			elif b["lz"] >= VoxelChunk.CHUNK_SIZE_Z - 2:
				var n_coord: Vector2i = c_coord + Vector2i(0, 1)
				if not neighbor_rebuild.has(n_coord): neighbor_rebuild[n_coord] = {}
				neighbor_rebuild[n_coord][sub_idx] = true

		# Single mirror buffer & storage update per affected chunk
		var v_buf: PackedByteArray = chunk.get_voxels_buffer()
		_mirror_mutex.lock()
		_chunk_voxel_mirror[c_coord] = v_buf
		_mirror_mutex.unlock()

		_storage.store_modified_chunk(
			c_coord,
			v_buf,
			chunk.get_highest_solid_y(),
			false
		)

		# Rebuild unique sub-chunks in this chunk
		chunk._ensure_child_nodes()
		for s_idx in sub_indices.keys():
			chunk._apply_single_sub_chunk(s_idx, chunk._build_single_sub_chunk_data(s_idx))

		# Rebuild neighbor sub-chunks
		for n_coord in neighbor_rebuild:
			if _active_chunks.has(n_coord):
				var n_chunk: VoxelChunk = _active_chunks[n_coord]
				n_chunk._ensure_child_nodes()
				for s_idx in neighbor_rebuild[n_coord].keys():
					n_chunk._apply_single_sub_chunk(s_idx, n_chunk._build_single_sub_chunk_data(s_idx))

	# 3. Spawn pooled drops (capped to max 8 to prevent physics entity lag)
	var max_drops := mini(8, drop_candidates.size())
	for i in range(max_drops):
		var drop_item_id: int = drop_candidates[i]
		var spawn_pos: Vector3 = center + Vector3(randf_range(-1.2, 1.2), randf_range(0.2, 1.2), randf_range(-1.2, 1.2))
		DroppedItem.spawn_drop(self, spawn_pos, drop_item_id, 1)

	# 4. Chain TNT
	for tnt_pos in tnt_to_chain:
		ignite_tnt_at(tnt_pos)

	# 5. Entity Damage & Knockback to Player
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

	# 6. Entity Damage & Knockback to nearby Mobs
	var mobs: Array = get_tree().get_nodes_in_group("mobs") if get_tree() != null else []
	for m in mobs:
		if is_instance_valid(m) and m is PassiveMob:
			var m_mob := m as PassiveMob
			var m_pos: Vector3 = m_mob.global_position if m_mob.is_inside_tree() else m_mob.position
			var m_dist: float = m_pos.distance_to(center)
			if m_dist <= radius * 1.8:
				var m_dmg: int = maxi(2, int(round((radius * 1.8 - m_dist) * 3.0)))
				m_mob.on_hit_by_player(center, m_dmg)
