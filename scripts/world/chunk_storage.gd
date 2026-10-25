class_name ChunkStorage
extends RefCounted
## Handles in-memory caching and compressed disk persistence of player-modified chunks.
## Only chunks modified by the player (dirty chunks) are written to disk to keep saves tiny.

const SAVE_ROOT_DIR: String = "user://worlds"
const FILE_MAGIC: int = 0x56584331 # "VXC1"
const VoxelChunk = preload("res://scripts/voxel/voxel_chunk.gd")

var _world_seed: int = 2026
var _custom_dir: String = ""
## In-memory cache of modified chunk buffers: `Vector2i -> Dictionary{ "voxels": PackedByteArray, "highest_y": int }`
var _modified_chunks: Dictionary = {}
var _mutex: Mutex = Mutex.new()


func _init(seed_or_path: Variant = 2026) -> void:
	if seed_or_path is String:
		_custom_dir = seed_or_path
	elif seed_or_path is int:
		_world_seed = seed_or_path
	_ensure_save_directory()


func get_world_save_dir() -> String:
	if not _custom_dir.is_empty():
		return _custom_dir
	return "%s/seed_%d" % [SAVE_ROOT_DIR, _world_seed]


func _ensure_save_directory() -> void:
	var dir_path: String = get_world_save_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


## Records a modified chunk's voxel buffer in memory and marks it ready for disk persistence.
func store_modified_chunk(coord: Vector2i, voxels: PackedByteArray, highest_y: int, flush_to_disk: bool = false) -> void:
	var copy_bytes: PackedByteArray = voxels.duplicate()
	_mutex.lock()
	_modified_chunks[coord] = {
		"voxels": copy_bytes,
		"highest_y": highest_y,
	}
	_mutex.unlock()

	if flush_to_disk:
		save_chunk_to_disk(coord, copy_bytes, highest_y)


## Checks if a chunk has saved modifications in memory or on disk.
func has_saved_chunk(coord: Vector2i) -> bool:
	_mutex.lock()
	var in_mem: bool = _modified_chunks.has(coord)
	_mutex.unlock()
	if in_mem:
		return true
	return FileAccess.file_exists(_get_chunk_file_path(coord))


## Loads a modified chunk's data from memory or disk. Returns an empty Dictionary if unmodified.
func load_chunk_data(coord: Vector2i) -> Dictionary:
	_mutex.lock()
	if _modified_chunks.has(coord):
		var cached: Dictionary = _modified_chunks[coord]
		var result := {
			"voxels": (cached["voxels"] as PackedByteArray).duplicate(),
			"highest_y": int(cached["highest_y"]),
		}
		_mutex.unlock()
		return result
	_mutex.unlock()

	var path: String = _get_chunk_file_path(coord)
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return {}

	var magic: int = file.get_32()
	if magic != FILE_MAGIC:
		file.close()
		return {}

	var highest_y: int = file.get_16()
	var byte_len: int = file.get_32()
	var voxels: PackedByteArray = file.get_buffer(byte_len)
	file.close()

	if voxels.size() != VoxelChunk.CHUNK_SIZE_X * VoxelChunk.CHUNK_SIZE_Y * VoxelChunk.CHUNK_SIZE_Z:
		return {}

	_mutex.lock()
	_modified_chunks[coord] = {
		"voxels": voxels.duplicate(),
		"highest_y": highest_y,
	}
	_mutex.unlock()

	return {
		"voxels": voxels,
		"highest_y": highest_y,
	}


## Writes a single modified chunk to disk using Zstandard compression.
func save_chunk_to_disk(coord: Vector2i, voxels: PackedByteArray, highest_y: int) -> bool:
	_ensure_save_directory()
	var path: String = _get_chunk_file_path(coord)
	var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return false

	file.store_32(FILE_MAGIC)
	file.store_16(highest_y)
	file.store_32(voxels.size())
	file.store_buffer(voxels)
	file.close()
	return true


## Flushes all modified chunks in memory to disk.
func flush_all_to_disk() -> int:
	_mutex.lock()
	var keys: Array = _modified_chunks.keys()
	_mutex.unlock()

	var saved_count: int = 0
	for coord_variant in keys:
		var coord: Vector2i = coord_variant
		_mutex.lock()
		var entry: Dictionary = _modified_chunks.get(coord, {})
		_mutex.unlock()
		if not entry.is_empty():
			if save_chunk_to_disk(coord, entry["voxels"], int(entry["highest_y"])):
				saved_count += 1
	return saved_count


func get_modified_chunk_count() -> int:
	_mutex.lock()
	var count: int = _modified_chunks.size()
	_mutex.unlock()
	return count


func _get_chunk_file_path(coord: Vector2i) -> String:
	return "%s/chunk_%d_%d.vxc" % [get_world_save_dir(), coord.x, coord.y]
