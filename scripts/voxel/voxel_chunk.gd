class_name VoxelChunk
extends StaticBody3D
## Represents a single 16 x 256 x 16 voxel chunk.
## Supports both synchronous and WorkerThreadPool background terrain/mesh generation,
## cross-chunk neighbor face culling, and dirty-state tracking for persistence.

const CHUNK_SIZE_X: int = 16
const CHUNK_SIZE_Y: int = 256
const CHUNK_SIZE_Z: int = 16
const SEA_LEVEL: int = 48

## Coordinate of this chunk in chunk-grid space (e.g., Vector2i(0, 0), Vector2i(1, -2)).
var chunk_coords: Vector2i = Vector2i.ZERO

## True if the player has broken or placed at least one block in this chunk.
var is_dirty: bool = false

## Optional thread-safe callback `(world_pos: Vector3i) -> int` provided by WorldManager
## for seamless cross-chunk border face culling.
var neighbor_block_getter: Callable = Callable()

## Contiguous 1D byte buffer of size 16 * 256 * 16 (65,536 bytes).
var _voxels: PackedByteArray = PackedByteArray()
var _highest_solid_y: int = 0

var _mesh_instance: MeshInstance3D = null
var _collision_shape: CollisionShape3D = null


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_ensure_child_nodes()


func _ensure_child_nodes() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "ChunkMesh"
		_mesh_instance.material_override = VoxelAtlasBuilder.get_shared_voxel_material()
		add_child(_mesh_instance)
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "ChunkCollision"
		add_child(_collision_shape)


## Restores voxel data directly from a saved persistence buffer.
func load_from_buffer(saved_voxels: PackedByteArray, highest_y: int) -> void:
	_voxels = saved_voxels
	_highest_solid_y = clampi(highest_y, 0, CHUNK_SIZE_Y - 1)
	is_dirty = true


func get_voxels_buffer() -> PackedByteArray:
	return _voxels


func get_highest_solid_y() -> int:
	return _highest_solid_y


## Initializes and generates terrain for this chunk using 2D heightmap + 3D cave noise.
## Safe to execute on a background WorkerThreadPool thread.
func generate_terrain(surface_noise: FastNoiseLite, cave_noise: FastNoiseLite = null) -> void:
	_voxels.resize(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z)
	_voxels.fill(BlockRegistry.BlockId.AIR)
	_highest_solid_y = 0

	var world_origin_x: int = chunk_coords.x * CHUNK_SIZE_X
	var world_origin_z: int = chunk_coords.y * CHUNK_SIZE_Z

	for lx in range(CHUNK_SIZE_X):
		var wx: int = world_origin_x + lx
		for lz in range(CHUNK_SIZE_Z):
			var wz: int = world_origin_z + lz

			var surface_y: int = sample_surface_height(surface_noise, wx, wz)

			for ly in range(surface_y + 1):
				var block_id: int = sample_terrain_voxel(surface_y, wx, ly, wz, cave_noise)
				if block_id != BlockRegistry.BlockId.AIR:
					_set_voxel_raw(lx, ly, lz, block_id)

			if surface_y > _highest_solid_y:
				_highest_solid_y = surface_y

			# Deterministic tree placement away from chunk borders so canopies don't clip
			if lx >= 3 and lx <= CHUNK_SIZE_X - 4 and lz >= 3 and lz <= CHUNK_SIZE_Z - 4:
				if _should_spawn_tree(wx, wz) and get_block_local(lx, surface_y, lz) == BlockRegistry.BlockId.GRASS:
					_place_tree(lx, surface_y + 1, lz)


## Deterministic heightmap helper shared with WorldManager for cross-chunk border culling.
static func sample_surface_height(surface_noise: FastNoiseLite, wx: int, wz: int) -> int:
	var height_sample: float = surface_noise.get_noise_2d(float(wx), float(wz))
	return clampi(
		SEA_LEVEL + int(round(height_sample * 16.0)),
		8,
		CHUNK_SIZE_Y - 12
	)


## Deterministic terrain voxel sampler shared with WorldManager for cross-chunk border culling.
static func sample_terrain_voxel(
	surface_y: int,
	wx: int,
	ly: int,
	wz: int,
	cave_noise: FastNoiseLite
) -> int:
	if ly < 0 or ly > surface_y:
		return BlockRegistry.BlockId.AIR
	if ly == 0:
		return BlockRegistry.BlockId.STONE
	if cave_noise != null and ly < surface_y - 3 and ly > 2:
		var cave_val: float = cave_noise.get_noise_3d(float(wx), float(ly) * 1.4, float(wz))
		if cave_val > 0.46:
			return BlockRegistry.BlockId.AIR
	if ly == surface_y:
		return BlockRegistry.BlockId.GRASS
	if ly >= surface_y - 3:
		return BlockRegistry.BlockId.DIRT
	return BlockRegistry.BlockId.STONE


func _should_spawn_tree(wx: int, wz: int) -> bool:
	var hash_val: int = absi((wx * 73428767) ^ (wz * 912931)) % 1000
	return hash_val < 9


func _place_tree(lx: int, base_y: int, lz: int) -> void:
	var trunk_height: int = 4 + ((absi(lx * 13 + lz * 31)) % 2)
	if base_y + trunk_height + 2 >= CHUNK_SIZE_Y:
		return

	# Vertical wood log trunk
	for ty in range(base_y, base_y + trunk_height):
		_set_voxel_raw(lx, ty, lz, BlockRegistry.BlockId.WOOD_LOG)

	# Leaf canopy
	var canopy_base: int = base_y + trunk_height - 2
	var canopy_top: int = base_y + trunk_height + 1
	for cy in range(canopy_base, canopy_top + 1):
		var radius: int = 1 if cy == canopy_top else 2
		for cx in range(lx - radius, lx + radius + 1):
			for cz in range(lz - radius, lz + radius + 1):
				if cx == lx and cz == lz and cy < base_y + trunk_height:
					continue
				if absi(cx - lx) == radius and absi(cz - lz) == radius and cy == canopy_top:
					continue
				if is_in_bounds(cx, cy, cz):
					_set_voxel_raw(cx, cy, cz, BlockRegistry.BlockId.LEAVES)

	if canopy_top > _highest_solid_y:
		_highest_solid_y = canopy_top


## Thread-safe mesh and trimesh collision builder. Can be called from WorkerThreadPool.
## Returns `{ "mesh": ArrayMesh, "shape": ConcavePolygonShape3D }`.
func build_mesh_data() -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var max_y_to_scan: int = mini(_highest_solid_y + 1, CHUNK_SIZE_Y)
	var face_count: int = 0

	for ly in range(max_y_to_scan):
		for lx in range(CHUNK_SIZE_X):
			for lz in range(CHUNK_SIZE_Z):
				var block_id: int = get_block_local(lx, ly, lz)
				if block_id == BlockRegistry.BlockId.AIR:
					continue

				# Check all 6 neighbor directions; emit face only if neighbor is Air
				if not _is_neighbor_solid(lx, ly + 1, lz):
					_emit_face(st, lx, ly, lz, BlockRegistry.FaceDir.TOP, block_id)
					face_count += 1
				if not _is_neighbor_solid(lx, ly - 1, lz):
					_emit_face(st, lx, ly, lz, BlockRegistry.FaceDir.BOTTOM, block_id)
					face_count += 1
				if not _is_neighbor_solid(lx + 1, ly, lz):
					_emit_face(st, lx, ly, lz, BlockRegistry.FaceDir.EAST, block_id)
					face_count += 1
				if not _is_neighbor_solid(lx - 1, ly, lz):
					_emit_face(st, lx, ly, lz, BlockRegistry.FaceDir.WEST, block_id)
					face_count += 1
				if not _is_neighbor_solid(lx, ly, lz + 1):
					_emit_face(st, lx, ly, lz, BlockRegistry.FaceDir.SOUTH, block_id)
					face_count += 1
				if not _is_neighbor_solid(lx, ly, lz - 1):
					_emit_face(st, lx, ly, lz, BlockRegistry.FaceDir.NORTH, block_id)
					face_count += 1

	if face_count == 0:
		return {"mesh": null, "shape": null}

	var array_mesh: ArrayMesh = st.commit()
	var trimesh_shape: ConcavePolygonShape3D = array_mesh.create_trimesh_shape()
	return {
		"mesh": array_mesh,
		"shape": trimesh_shape,
	}


## Applies prebuilt mesh and collision shape resources on the main thread.
func apply_mesh_data(mesh_data: Dictionary) -> void:
	_ensure_child_nodes()
	_mesh_instance.mesh = mesh_data.get("mesh", null) as ArrayMesh
	_collision_shape.shape = mesh_data.get("shape", null) as Shape3D


## Synchronous convenience method for immediate main-thread block breaking/placing updates.
func rebuild_mesh() -> void:
	var mesh_data: Dictionary = build_mesh_data()
	apply_mesh_data(mesh_data)


func _is_neighbor_solid(lx: int, ly: int, lz: int) -> bool:
	if ly < 0:
		return true
	if ly >= CHUNK_SIZE_Y:
		return false
	if lx >= 0 and lx < CHUNK_SIZE_X and lz >= 0 and lz < CHUNK_SIZE_Z:
		return BlockRegistry.is_solid(get_block_local(lx, ly, lz))

	if neighbor_block_getter.is_valid():
		var wx: int = chunk_coords.x * CHUNK_SIZE_X + lx
		var wz: int = chunk_coords.y * CHUNK_SIZE_Z + lz
		var neighbor_id: int = neighbor_block_getter.call(Vector3i(wx, ly, wz))
		return BlockRegistry.is_solid(neighbor_id)

	return false


func _emit_face(
	st: SurfaceTool,
	lx: int,
	ly: int,
	lz: int,
	face_dir: int,
	block_id: int
) -> void:
	var origin := Vector3(float(lx), float(ly), float(lz))
	var uv_rect: Rect2 = BlockRegistry.get_tile_uv_rect(block_id, face_dir)
	var u0: float = uv_rect.position.x
	var v0: float = uv_rect.position.y
	var u1: float = uv_rect.position.x + uv_rect.size.x
	var v1: float = uv_rect.position.y + uv_rect.size.y

	var verts: Array[Vector3]
	var normal: Vector3
	var shade: float = 1.0

	match face_dir:
		BlockRegistry.FaceDir.TOP:
			normal = Vector3.UP
			shade = 1.0
			verts = [
				origin + Vector3(0, 1, 0),
				origin + Vector3(1, 1, 0),
				origin + Vector3(1, 1, 1),
				origin + Vector3(0, 1, 1),
			]
		BlockRegistry.FaceDir.BOTTOM:
			normal = Vector3.DOWN
			shade = 0.52
			verts = [
				origin + Vector3(0, 0, 1),
				origin + Vector3(1, 0, 1),
				origin + Vector3(1, 0, 0),
				origin + Vector3(0, 0, 0),
			]
		BlockRegistry.FaceDir.EAST:
			normal = Vector3.RIGHT
			shade = 0.80
			verts = [
				origin + Vector3(1, 1, 1),
				origin + Vector3(1, 1, 0),
				origin + Vector3(1, 0, 0),
				origin + Vector3(1, 0, 1),
			]
		BlockRegistry.FaceDir.WEST:
			normal = Vector3.LEFT
			shade = 0.76
			verts = [
				origin + Vector3(0, 1, 0),
				origin + Vector3(0, 1, 1),
				origin + Vector3(0, 0, 1),
				origin + Vector3(0, 0, 0),
			]
		BlockRegistry.FaceDir.SOUTH:
			normal = Vector3.BACK
			shade = 0.88
			verts = [
				origin + Vector3(0, 1, 1),
				origin + Vector3(1, 1, 1),
				origin + Vector3(1, 0, 1),
				origin + Vector3(0, 0, 1),
			]
		_: # NORTH
			normal = Vector3.FORWARD
			shade = 0.70
			verts = [
				origin + Vector3(1, 1, 0),
				origin + Vector3(0, 1, 0),
				origin + Vector3(0, 0, 0),
				origin + Vector3(1, 0, 0),
			]

	var uvs: Array[Vector2] = [
		Vector2(u0, v0),
		Vector2(u1, v0),
		Vector2(u1, v1),
		Vector2(u0, v1),
	]
	var face_color := Color(shade, shade, shade, 1.0)

	# Triangle 1: 0 -> 1 -> 2
	st.set_normal(normal)
	st.set_color(face_color)
	st.set_uv(uvs[0])
	st.add_vertex(verts[0])

	st.set_normal(normal)
	st.set_color(face_color)
	st.set_uv(uvs[1])
	st.add_vertex(verts[1])

	st.set_normal(normal)
	st.set_color(face_color)
	st.set_uv(uvs[2])
	st.add_vertex(verts[2])

	# Triangle 2: 0 -> 2 -> 3
	st.set_normal(normal)
	st.set_color(face_color)
	st.set_uv(uvs[0])
	st.add_vertex(verts[0])

	st.set_normal(normal)
	st.set_color(face_color)
	st.set_uv(uvs[2])
	st.add_vertex(verts[2])

	st.set_normal(normal)
	st.set_color(face_color)
	st.set_uv(uvs[3])
	st.add_vertex(verts[3])


func is_in_bounds(lx: int, ly: int, lz: int) -> bool:
	return (
		lx >= 0 and lx < CHUNK_SIZE_X
		and ly >= 0 and ly < CHUNK_SIZE_Y
		and lz >= 0 and lz < CHUNK_SIZE_Z
	)


func get_block_local(lx: int, ly: int, lz: int) -> int:
	if not is_in_bounds(lx, ly, lz) or _voxels.is_empty():
		return BlockRegistry.BlockId.AIR
	return _voxels[_to_index(lx, ly, lz)]


func set_block_local(lx: int, ly: int, lz: int, block_id: int, immediate_rebuild: bool = true) -> void:
	if not is_in_bounds(lx, ly, lz):
		return
	if _voxels.is_empty():
		_voxels.resize(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z)
	_set_voxel_raw(lx, ly, lz, block_id)
	is_dirty = true
	if block_id != BlockRegistry.BlockId.AIR and ly > _highest_solid_y:
		_highest_solid_y = ly
	if immediate_rebuild:
		rebuild_mesh()


func _set_voxel_raw(lx: int, ly: int, lz: int, block_id: int) -> void:
	_voxels[_to_index(lx, ly, lz)] = block_id


func _to_index(lx: int, ly: int, lz: int) -> int:
	return (ly * CHUNK_SIZE_Z + lz) * CHUNK_SIZE_X + lx
