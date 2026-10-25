class_name VoxelChunk
extends StaticBody3D
## Represents a single 16 x 256 x 16 voxel chunk partitioned into sixteen 16 x 16 x 16
## vertical sub-chunks for fast localized remeshing on block break/place.

const CHUNK_SIZE_X: int = 16
const CHUNK_SIZE_Y: int = 256
const CHUNK_SIZE_Z: int = 16
const SUB_CHUNK_HEIGHT: int = 16
const SUB_CHUNK_COUNT: int = 16 # 256 / 16
const SEA_LEVEL: int = 48
const WATER_LEVEL: int = 45

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

var _sub_solid_meshes: Array[MeshInstance3D] = []
var _sub_water_meshes: Array[MeshInstance3D] = []
var _sub_colliders: Array[CollisionShape3D] = []


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_ensure_child_nodes()


func _ensure_child_nodes() -> void:
	if not _sub_solid_meshes.is_empty():
		return

	var solid_mat: StandardMaterial3D = VoxelAtlasBuilder.get_shared_voxel_material()
	var water_mat: StandardMaterial3D = VoxelAtlasBuilder.get_shared_water_material()

	for sub_idx in range(SUB_CHUNK_COUNT):
		var solid_mi := MeshInstance3D.new()
		solid_mi.name = "SubMesh_%d" % sub_idx
		solid_mi.material_override = solid_mat
		add_child(solid_mi)
		_sub_solid_meshes.append(solid_mi)

		var water_mi := MeshInstance3D.new()
		water_mi.name = "SubWater_%d" % sub_idx
		water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		water_mi.material_override = water_mat
		add_child(water_mi)
		_sub_water_meshes.append(water_mi)

		var col := CollisionShape3D.new()
		col.name = "SubCol_%d" % sub_idx
		add_child(col)
		_sub_colliders.append(col)


## Restores voxel data directly from a saved persistence buffer.
func load_from_buffer(saved_voxels: PackedByteArray, highest_y: int) -> void:
	_voxels = saved_voxels
	_highest_solid_y = clampi(maxi(highest_y, WATER_LEVEL), 0, CHUNK_SIZE_Y - 1)
	is_dirty = true


func get_voxels_buffer() -> PackedByteArray:
	return _voxels


func get_highest_solid_y() -> int:
	return _highest_solid_y


## Initializes and generates terrain for this chunk using 2D heightmap + 3D cave noise + water basins.
## Safe to execute on a background WorkerThreadPool thread.
func generate_terrain(surface_noise: FastNoiseLite, cave_noise: FastNoiseLite = null) -> void:
	_voxels.resize(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z)
	_voxels.fill(BlockRegistry.BlockId.AIR)
	_highest_solid_y = WATER_LEVEL

	var world_origin_x: int = chunk_coords.x * CHUNK_SIZE_X
	var world_origin_z: int = chunk_coords.y * CHUNK_SIZE_Z

	for lx in range(CHUNK_SIZE_X):
		var wx: int = world_origin_x + lx
		for lz in range(CHUNK_SIZE_Z):
			var wz: int = world_origin_z + lz

			var surface_y: int = sample_surface_height(surface_noise, wx, wz)
			var top_y: int = maxi(surface_y, WATER_LEVEL)

			for ly in range(top_y + 1):
				var block_id: int = sample_terrain_voxel(surface_y, wx, ly, wz, cave_noise)
				if block_id != BlockRegistry.BlockId.AIR:
					_set_voxel_raw(lx, ly, lz, block_id)

			if top_y > _highest_solid_y:
				_highest_solid_y = top_y

			# Deterministic tree placement on Grass above water level
			if surface_y > WATER_LEVEL + 1 and lx >= 3 and lx <= CHUNK_SIZE_X - 4 and lz >= 3 and lz <= CHUNK_SIZE_Z - 4:
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
	if ly < 0:
		return BlockRegistry.BlockId.AIR
	if ly > surface_y:
		if ly <= WATER_LEVEL:
			return BlockRegistry.BlockId.WATER
		return BlockRegistry.BlockId.AIR
	if ly == 0:
		return BlockRegistry.BlockId.STONE
	# Do not carve open caves directly underneath water basins to avoid draining lakes
	if cave_noise != null and surface_y > WATER_LEVEL and ly < surface_y - 3 and ly > 2:
		var cave_val: float = cave_noise.get_noise_3d(float(wx), float(ly) * 1.4, float(wz))
		if cave_val > 0.46:
			return BlockRegistry.BlockId.AIR
	# Low-lying basins and shorelines near/below water level generate sandy beaches
	if surface_y <= WATER_LEVEL + 1 and ly >= surface_y - 2:
		return BlockRegistry.BlockId.SAND
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

	for ty in range(base_y, base_y + trunk_height):
		_set_voxel_raw(lx, ty, lz, BlockRegistry.BlockId.WOOD_LOG)

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


## Thread-safe builder for all 16 vertical sub-chunks. Can be called from WorkerThreadPool.
func build_mesh_data() -> Dictionary:
	var sub_results: Array[Dictionary] = []
	var max_sub_idx: int = mini(_highest_solid_y / SUB_CHUNK_HEIGHT, SUB_CHUNK_COUNT - 1)

	for sub_idx in range(SUB_CHUNK_COUNT):
		if sub_idx <= max_sub_idx:
			sub_results.append(_build_single_sub_chunk_data(sub_idx))
		else:
			sub_results.append({"mesh": null, "water_mesh": null, "shape": null})

	return {"sub_chunks": sub_results}


## Builds solid mesh, water mesh, and trimesh collision for a single 16x16x16 vertical slice.
func _build_single_sub_chunk_data(sub_idx: int) -> Dictionary:
	var st_solid := SurfaceTool.new()
	st_solid.begin(Mesh.PRIMITIVE_TRIANGLES)

	var st_water := SurfaceTool.new()
	st_water.begin(Mesh.PRIMITIVE_TRIANGLES)

	var y_start: int = sub_idx * SUB_CHUNK_HEIGHT
	var y_end: int = mini(y_start + SUB_CHUNK_HEIGHT, CHUNK_SIZE_Y)
	var solid_faces: int = 0
	var water_faces: int = 0

	for ly in range(y_start, y_end):
		for lx in range(CHUNK_SIZE_X):
			for lz in range(CHUNK_SIZE_Z):
				var block_id: int = get_block_local(lx, ly, lz)
				if block_id == BlockRegistry.BlockId.AIR:
					continue

				if block_id == BlockRegistry.BlockId.WATER:
					if _get_neighbor_id(lx, ly + 1, lz) == BlockRegistry.BlockId.AIR:
						_emit_water_face(st_water, lx, ly, lz, BlockRegistry.FaceDir.TOP)
						water_faces += 1
					if _get_neighbor_id(lx, ly - 1, lz) == BlockRegistry.BlockId.AIR:
						_emit_water_face(st_water, lx, ly, lz, BlockRegistry.FaceDir.BOTTOM)
						water_faces += 1
					if _get_neighbor_id(lx + 1, ly, lz) == BlockRegistry.BlockId.AIR:
						_emit_water_face(st_water, lx, ly, lz, BlockRegistry.FaceDir.EAST)
						water_faces += 1
					if _get_neighbor_id(lx - 1, ly, lz) == BlockRegistry.BlockId.AIR:
						_emit_water_face(st_water, lx, ly, lz, BlockRegistry.FaceDir.WEST)
						water_faces += 1
					if _get_neighbor_id(lx, ly, lz + 1) == BlockRegistry.BlockId.AIR:
						_emit_water_face(st_water, lx, ly, lz, BlockRegistry.FaceDir.SOUTH)
						water_faces += 1
					if _get_neighbor_id(lx, ly, lz - 1) == BlockRegistry.BlockId.AIR:
						_emit_water_face(st_water, lx, ly, lz, BlockRegistry.FaceDir.NORTH)
						water_faces += 1
					continue

				if not _is_neighbor_solid(lx, ly + 1, lz):
					_emit_face(st_solid, lx, ly, lz, BlockRegistry.FaceDir.TOP, block_id)
					solid_faces += 1
				if not _is_neighbor_solid(lx, ly - 1, lz):
					_emit_face(st_solid, lx, ly, lz, BlockRegistry.FaceDir.BOTTOM, block_id)
					solid_faces += 1
				if not _is_neighbor_solid(lx + 1, ly, lz):
					_emit_face(st_solid, lx, ly, lz, BlockRegistry.FaceDir.EAST, block_id)
					solid_faces += 1
				if not _is_neighbor_solid(lx - 1, ly, lz):
					_emit_face(st_solid, lx, ly, lz, BlockRegistry.FaceDir.WEST, block_id)
					solid_faces += 1
				if not _is_neighbor_solid(lx, ly, lz + 1):
					_emit_face(st_solid, lx, ly, lz, BlockRegistry.FaceDir.SOUTH, block_id)
					solid_faces += 1
				if not _is_neighbor_solid(lx, ly, lz - 1):
					_emit_face(st_solid, lx, ly, lz, BlockRegistry.FaceDir.NORTH, block_id)
					solid_faces += 1

	var solid_mesh: ArrayMesh = st_solid.commit() if solid_faces > 0 else null
	var water_mesh: ArrayMesh = st_water.commit() if water_faces > 0 else null
	var trimesh_shape: ConcavePolygonShape3D = solid_mesh.create_trimesh_shape() if solid_mesh != null else null

	return {
		"mesh": solid_mesh,
		"water_mesh": water_mesh,
		"shape": trimesh_shape,
	}


## Applies prebuilt sub-chunk meshes and collision shapes on the main thread.
func apply_mesh_data(mesh_data: Dictionary) -> void:
	_ensure_child_nodes()
	var sub_chunks: Array = mesh_data.get("sub_chunks", [])
	for sub_idx in range(mini(sub_chunks.size(), SUB_CHUNK_COUNT)):
		_apply_single_sub_chunk(sub_idx, sub_chunks[sub_idx])


func _apply_single_sub_chunk(sub_idx: int, sub_data: Dictionary) -> void:
	_sub_solid_meshes[sub_idx].mesh = sub_data.get("mesh", null) as ArrayMesh
	_sub_water_meshes[sub_idx].mesh = sub_data.get("water_mesh", null) as ArrayMesh
	_sub_colliders[sub_idx].shape = sub_data.get("shape", null) as Shape3D


## Rebuilds only the 16x16x16 vertical sub-chunk containing `ly` (and vertical neighbor if on a 16-block seam).
func rebuild_at_local_y(ly: int) -> void:
	_ensure_child_nodes()
	var sub_idx: int = clampi(ly / SUB_CHUNK_HEIGHT, 0, SUB_CHUNK_COUNT - 1)
	_apply_single_sub_chunk(sub_idx, _build_single_sub_chunk_data(sub_idx))

	var local_sub_y: int = ly % SUB_CHUNK_HEIGHT
	if local_sub_y == 0 and sub_idx > 0:
		_apply_single_sub_chunk(sub_idx - 1, _build_single_sub_chunk_data(sub_idx - 1))
	elif local_sub_y == SUB_CHUNK_HEIGHT - 1 and sub_idx < SUB_CHUNK_COUNT - 1:
		_apply_single_sub_chunk(sub_idx + 1, _build_single_sub_chunk_data(sub_idx + 1))


## Full chunk synchronous rebuild.
func rebuild_mesh() -> void:
	var mesh_data: Dictionary = build_mesh_data()
	apply_mesh_data(mesh_data)


func _get_neighbor_id(lx: int, ly: int, lz: int) -> int:
	if ly < 0:
		return BlockRegistry.BlockId.STONE
	if ly >= CHUNK_SIZE_Y:
		return BlockRegistry.BlockId.AIR
	if lx >= 0 and lx < CHUNK_SIZE_X and lz >= 0 and lz < CHUNK_SIZE_Z:
		return get_block_local(lx, ly, lz)

	if neighbor_block_getter.is_valid():
		var wx: int = chunk_coords.x * CHUNK_SIZE_X + lx
		var wz: int = chunk_coords.y * CHUNK_SIZE_Z + lz
		return neighbor_block_getter.call(Vector3i(wx, ly, wz))

	return BlockRegistry.BlockId.AIR


func _is_neighbor_solid(lx: int, ly: int, lz: int) -> bool:
	return BlockRegistry.is_solid(_get_neighbor_id(lx, ly, lz))


func _emit_water_face(st: SurfaceTool, lx: int, ly: int, lz: int, face_dir: int) -> void:
	var origin := Vector3(float(lx), float(ly), float(lz))
	var top_h: float = 0.88
	var verts: Array[Vector3]
	var normal: Vector3
	var shade: float = 1.0

	match face_dir:
		BlockRegistry.FaceDir.TOP:
			normal = Vector3.UP
			shade = 1.0
			verts = [
				origin + Vector3(0, top_h, 0),
				origin + Vector3(1, top_h, 0),
				origin + Vector3(1, top_h, 1),
				origin + Vector3(0, top_h, 1),
			]
		BlockRegistry.FaceDir.BOTTOM:
			normal = Vector3.DOWN
			shade = 0.65
			verts = [
				origin + Vector3(0, 0, 1),
				origin + Vector3(1, 0, 1),
				origin + Vector3(1, 0, 0),
				origin + Vector3(0, 0, 0),
			]
		BlockRegistry.FaceDir.EAST:
			normal = Vector3.RIGHT
			shade = 0.85
			verts = [
				origin + Vector3(1, top_h, 1),
				origin + Vector3(1, top_h, 0),
				origin + Vector3(1, 0, 0),
				origin + Vector3(1, 0, 1),
			]
		BlockRegistry.FaceDir.WEST:
			normal = Vector3.LEFT
			shade = 0.80
			verts = [
				origin + Vector3(0, top_h, 0),
				origin + Vector3(0, top_h, 1),
				origin + Vector3(0, 0, 1),
				origin + Vector3(0, 0, 0),
			]
		BlockRegistry.FaceDir.SOUTH:
			normal = Vector3.BACK
			shade = 0.90
			verts = [
				origin + Vector3(0, top_h, 1),
				origin + Vector3(1, top_h, 1),
				origin + Vector3(1, 0, 1),
				origin + Vector3(0, 0, 1),
			]
		_: # NORTH
			normal = Vector3.FORWARD
			shade = 0.78
			verts = [
				origin + Vector3(1, top_h, 0),
				origin + Vector3(0, top_h, 0),
				origin + Vector3(0, 0, 0),
				origin + Vector3(1, 0, 0),
			]

	var color := Color(shade, shade, shade, 1.0)
	var indices: Array[int] = [0, 1, 2, 0, 2, 3]
	for idx in indices:
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(verts[idx])


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
		rebuild_at_local_y(ly)


func _set_voxel_raw(lx: int, ly: int, lz: int, block_id: int) -> void:
	_voxels[_to_index(lx, ly, lz)] = block_id


func _to_index(lx: int, ly: int, lz: int) -> int:
	return (ly * CHUNK_SIZE_Z + lz) * CHUNK_SIZE_X + lx
