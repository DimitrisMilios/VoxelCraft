class_name WorldManager
extends Node3D
## Manages endless procedural chunk generation, streaming, and world-space block queries.

@export_group("World Generation")
@export var world_seed: int = 2026
@export var render_distance: int = 3
@export var max_chunks_per_frame: int = 2

@export_group("References")
@export var player_path: NodePath = NodePath("../Player")

## Active chunks mapped by chunk grid coordinates `Vector2i(cx, cz) -> VoxelChunk`.
var _active_chunks: Dictionary = {}

## Queue of chunk coordinates waiting to be generated and meshed.
var _load_queue: Array[Vector2i] = []

var _surface_noise: FastNoiseLite = FastNoiseLite.new()
var _cave_noise: FastNoiseLite = FastNoiseLite.new()
var _player: Node3D = null
var _last_player_chunk: Vector2i = Vector2i(999999, 999999)


func _ready() -> void:
	add_to_group("world_manager")
	_configure_noise()
	_player = get_node_or_null(player_path)
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D

	# Generate starting chunks around origin immediately so player has solid ground
	var start_chunk := Vector2i.ZERO
	if _player != null:
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


func _process(_delta: float) -> void:
	if _player != null:
		var current_chunk: Vector2i = world_to_chunk_coords(_player.global_position)
		if current_chunk != _last_player_chunk:
			_last_player_chunk = current_chunk
			_update_chunk_targets(current_chunk)

	_process_chunk_load_queue()


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
	# 1. Unload chunks beyond render_distance + 1
	var unload_radius: int = render_distance + 1
	var chunks_to_remove: Array[Vector2i] = []
	for coord_variant in _active_chunks.keys():
		var coord: Vector2i = coord_variant
		if absi(coord.x - center_chunk.x) > unload_radius or absi(coord.y - center_chunk.y) > unload_radius:
			chunks_to_remove.append(coord)

	for coord in chunks_to_remove:
		var chunk: VoxelChunk = _active_chunks[coord]
		_active_chunks.erase(coord)
		if is_instance_valid(chunk):
			chunk.queue_free()

	# 2. Enqueue missing chunks within render_distance sorted by distance to player
	_load_queue.clear()
	for dx in range(-render_distance, render_distance + 1):
		for dz in range(-render_distance, render_distance + 1):
			var target_coord := Vector2i(center_chunk.x + dx, center_chunk.y + dz)
			if not _active_chunks.has(target_coord):
				_load_queue.append(target_coord)

	_load_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var dist_a: int = (a.x - center_chunk.x) * (a.x - center_chunk.x) + (a.y - center_chunk.y) * (a.y - center_chunk.y)
		var dist_b: int = (b.x - center_chunk.x) * (b.x - center_chunk.x) + (b.y - center_chunk.y) * (b.y - center_chunk.y)
		return dist_a < dist_b
	)


func _process_chunk_load_queue() -> void:
	var built_this_frame: int = 0
	while not _load_queue.is_empty() and built_this_frame < max_chunks_per_frame:
		var coord: Vector2i = _load_queue.pop_front()
		if not _active_chunks.has(coord):
			_spawn_chunk_immediate(coord)
			built_this_frame += 1


func _spawn_chunk_immediate(coord: Vector2i) -> VoxelChunk:
	if _active_chunks.has(coord):
		return _active_chunks[coord]

	var chunk := VoxelChunk.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk.chunk_coords = coord
	chunk.position = Vector3(
		float(coord.x * VoxelChunk.CHUNK_SIZE_X),
		0.0,
		float(coord.y * VoxelChunk.CHUNK_SIZE_Z)
	)
	add_child(chunk)
	chunk.generate_terrain(_surface_noise, _cave_noise)
	chunk.rebuild_mesh()
	_active_chunks[coord] = chunk
	return chunk


## Converts a 3D world position into 2D chunk grid coordinates.
static func world_to_chunk_coords(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / float(VoxelChunk.CHUNK_SIZE_X)),
		floori(world_pos.z / float(VoxelChunk.CHUNK_SIZE_Z))
	)


## Returns the block ID at integer world coordinates `world_block_pos`.
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


## Updates a block at integer world coordinates `world_block_pos` and rebuilds affected chunk meshes.
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
	chunk.set_block_local(lx, world_block_pos.y, lz, block_id, true)

	# If on a chunk boundary, rebuild adjacent neighbor chunk if needed
	if lx == 0 and _active_chunks.has(chunk_coord + Vector2i(-1, 0)):
		(_active_chunks[chunk_coord + Vector2i(-1, 0)] as VoxelChunk).rebuild_mesh()
	elif lx == VoxelChunk.CHUNK_SIZE_X - 1 and _active_chunks.has(chunk_coord + Vector2i(1, 0)):
		(_active_chunks[chunk_coord + Vector2i(1, 0)] as VoxelChunk).rebuild_mesh()

	if lz == 0 and _active_chunks.has(chunk_coord + Vector2i(0, -1)):
		(_active_chunks[chunk_coord + Vector2i(0, -1)] as VoxelChunk).rebuild_mesh()
	elif lz == VoxelChunk.CHUNK_SIZE_Z - 1 and _active_chunks.has(chunk_coord + Vector2i(0, 1)):
		(_active_chunks[chunk_coord + Vector2i(0, 1)] as VoxelChunk).rebuild_mesh()

	return true


## Returns the highest non-air voxel Y coordinate at `(wx, wz)`.
func get_surface_height_at(wx: int, wz: int) -> int:
	for y in range(VoxelChunk.CHUNK_SIZE_Y - 1, 0, -1):
		var id: int = get_block_world(Vector3i(wx, y, wz))
		if id != BlockRegistry.BlockId.AIR and id != BlockRegistry.BlockId.LEAVES:
			return y
	var height_sample: float = _surface_noise.get_noise_2d(float(wx), float(wz))
	return clampi(
		VoxelChunk.SEA_LEVEL + int(round(height_sample * 16.0)),
		8,
		VoxelChunk.CHUNK_SIZE_Y - 12
	)
