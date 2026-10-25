class_name WorldManager
extends Node3D
## Manages endless procedural chunk generation, WorkerThreadPool background streaming,
## cross-chunk border face culling, cellular-automata water flow, and ChunkStorage persistence.

signal world_saved(saved_chunk_count: int)

const WATER_TICK_INTERVAL: float = 0.16
const MAX_WATER_SPREAD_PER_TICK: int = 16

@export_group("World Generation")
@export var world_seed: int = 2026
@export var render_distance: int = 5
@export var max_concurrent_tasks: int = 4
@export var max_main_thread_applies_per_frame: int = 3

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
	_storage = ChunkStorage.new(world_seed)
	_configure_noise()

	_player = get_node_or_null(player_path)
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D

	var start_chunk := Vector2i.ZERO
	if _player != null:
		start_chunk = world_to_chunk_coords(_player.global_position)

	# Synchronously build the immediate 3x3 spawn area so the player starts on solid ground
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save_all_modified_chunks()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F6:
			var count: int = save_all_modified_chunks()
			world_saved.emit(count)


func _process(delta: float) -> void:
	if _player != null:
		var current_chunk: Vector2i = world_to_chunk_coords(_player.global_position)
		if current_chunk != _last_player_chunk:
			_last_player_chunk = current_chunk
			_update_chunk_targets(current_chunk)

	_dispatch_background_tasks()
	_apply_completed_builds()
	_process_water_flow(delta)


## Dynamically updates chunk render distance at runtime (e.g. from the Pause Menu).
func set_render_distance(new_distance: int) -> void:
	var clamped: int = clampi(new_distance, 2, 8)
	if clamped == render_distance:
		return
	render_distance = clamped
	if _player != null:
		_last_player_chunk = world_to_chunk_coords(_player.global_position)
		_update_chunk_targets(_last_player_chunk)


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
	while not _load_queue.is_empty() and _in_flight_coords.size() < max_concurrent_tasks:
		var coord: Vector2i = _load_queue.pop_front()
		if _active_chunks.has(coord) or _in_flight_coords.has(coord):
			continue
		_in_flight_coords[coord] = true
		WorkerThreadPool.add_task(_worker_build_chunk.bind(coord), false, "BuildChunk_%d_%d" % [coord.x, coord.y])


func _worker_build_chunk(coord: Vector2i) -> void:
	var chunk := VoxelChunk.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk.chunk_coords = coord
	chunk.neighbor_block_getter = get_block_or_procedural_world

	var saved_data: Dictionary = _storage.load_chunk_data(coord)
	if not saved_data.is_empty():
		chunk.load_from_buffer(saved_data["voxels"], int(saved_data["highest_y"]))
	else:
		chunk.generate_terrain(_surface_noise, _cave_noise)

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


func set_block_world(world_block_pos: Vector3i, block_id: int) -> bool:
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
	chunk.set_block_local(lx, world_block_pos.y, lz, block_id, false)

	_mirror_mutex.lock()
	_chunk_voxel_mirror[chunk_coord] = chunk.get_voxels_buffer()
	_mirror_mutex.unlock()

	_storage.store_modified_chunk(
		chunk_coord,
		chunk.get_voxels_buffer(),
		chunk.get_highest_solid_y(),
		false
	)

	chunk.rebuild_at_local_y(world_block_pos.y)

	# If on a chunk boundary, rebuild only the affected vertical sub-chunk on the adjacent neighbor
	if lx == 0 and _active_chunks.has(chunk_coord + Vector2i(-1, 0)):
		(_active_chunks[chunk_coord + Vector2i(-1, 0)] as VoxelChunk).rebuild_at_local_y(world_block_pos.y)
	elif lx == VoxelChunk.CHUNK_SIZE_X - 1 and _active_chunks.has(chunk_coord + Vector2i(1, 0)):
		(_active_chunks[chunk_coord + Vector2i(1, 0)] as VoxelChunk).rebuild_at_local_y(world_block_pos.y)

	if lz == 0 and _active_chunks.has(chunk_coord + Vector2i(0, -1)):
		(_active_chunks[chunk_coord + Vector2i(0, -1)] as VoxelChunk).rebuild_at_local_y(world_block_pos.y)
	elif lz == VoxelChunk.CHUNK_SIZE_Z - 1 and _active_chunks.has(chunk_coord + Vector2i(0, 1)):
		(_active_chunks[chunk_coord + Vector2i(0, 1)] as VoxelChunk).rebuild_at_local_y(world_block_pos.y)

	# Trigger cellular-automata water flow checks when breaking a block or placing water
	if block_id == BlockRegistry.BlockId.AIR:
		_enqueue_water_check(world_block_pos)
	elif block_id == BlockRegistry.BlockId.WATER:
		_enqueue_water_neighbors(world_block_pos)

	return true


func _enqueue_water_check(pos: Vector3i) -> void:
	if pos.y <= 0 or pos.y > VoxelChunk.WATER_LEVEL:
		return
	if _water_flow_pending.has(pos):
		return
	if _has_water_source_neighbor(pos):
		_water_flow_pending[pos] = true
		_water_flow_queue.append(pos)


func _enqueue_water_neighbors(center: Vector3i) -> void:
	var candidates: Array[Vector3i] = [
		center + Vector3i(0, -1, 0),
		center + Vector3i(1, 0, 0),
		center + Vector3i(-1, 0, 0),
		center + Vector3i(0, 0, 1),
		center + Vector3i(0, 0, -1),
	]
	for next_pos in candidates:
		if get_block_world(next_pos) == BlockRegistry.BlockId.AIR:
			_enqueue_water_check(next_pos)


func _has_water_source_neighbor(pos: Vector3i) -> bool:
	if get_block_world(pos + Vector3i(0, 1, 0)) == BlockRegistry.BlockId.WATER:
		return true
	if pos.y <= VoxelChunk.WATER_LEVEL:
		if get_block_world(pos + Vector3i(1, 0, 0)) == BlockRegistry.BlockId.WATER:
			return true
		if get_block_world(pos + Vector3i(-1, 0, 0)) == BlockRegistry.BlockId.WATER:
			return true
		if get_block_world(pos + Vector3i(0, 0, 1)) == BlockRegistry.BlockId.WATER:
			return true
		if get_block_world(pos + Vector3i(0, 0, -1)) == BlockRegistry.BlockId.WATER:
			return true
	return false


func _process_water_flow(delta: float) -> void:
	if _water_flow_queue.is_empty():
		return
	_water_tick_timer += delta
	if _water_tick_timer < WATER_TICK_INTERVAL:
		return
	_water_tick_timer = 0.0

	var spread_count: int = 0
	while not _water_flow_queue.is_empty() and spread_count < MAX_WATER_SPREAD_PER_TICK:
		var pos: Vector3i = _water_flow_queue.pop_front()
		_water_flow_pending.erase(pos)

		if get_block_world(pos) != BlockRegistry.BlockId.AIR:
			continue
		if not _has_water_source_neighbor(pos):
			continue

		if set_block_world(pos, BlockRegistry.BlockId.WATER):
			spread_count += 1


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


func get_active_chunk_count() -> int:
	return _active_chunks.size()


func get_modified_chunk_count() -> int:
	return _storage.get_modified_chunk_count() if _storage != null else 0


func get_surface_height_at(wx: int, wz: int) -> int:
	for y in range(VoxelChunk.CHUNK_SIZE_Y - 1, 0, -1):
		var id: int = get_block_world(Vector3i(wx, y, wz))
		if id != BlockRegistry.BlockId.AIR and id != BlockRegistry.BlockId.LEAVES and id != BlockRegistry.BlockId.WATER:
			return y
	return VoxelChunk.sample_surface_height(_surface_noise, wx, wz)
