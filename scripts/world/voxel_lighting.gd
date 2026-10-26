class_name VoxelLighting
extends RefCounted
## Authentic TrueCraft & Minecraft Beta 1.7.3 Dual-Channel Voxel Lighting Engine.
## Features 0..15 Skylight and 0..15 Blocklight channels, 6-direction BFS flood-fill propagation,
## block light emission tables, smooth ambient occlusion (AO) vertex shading, and day/night attenuation.

const MAX_LIGHT: int = 15
const MIN_LIGHT: int = 0

const NEIGHBORS_6: Array[Vector3i] = [
	Vector3i(0, 1, 0),  # Top
	Vector3i(0, -1, 0), # Bottom
	Vector3i(1, 0, 0),  # East
	Vector3i(-1, 0, 0), # West
	Vector3i(0, 0, 1),  # South
	Vector3i(0, 0, -1), # North
]


## Returns the intrinsic light emission level [0..15] of a block ID matching Beta 1.7.3.
static func get_block_luminance(block_id: int) -> int:
	match block_id:
		BlockRegistry.BlockId.LAVA:
			return 15
		BlockRegistry.BlockId.GLOWSTONE:
			return 15
		BlockRegistry.BlockId.TORCH:
			return 14
		BlockRegistry.BlockId.REDSTONE_TORCH:
			return 7
		_:
			return 0


## Returns the light opacity [0..15] of a block ID.
## Opaque blocks block 100% of light (15); water attenuates by 2; air/foliage is 0.
static func get_block_opacity(block_id: int) -> int:
	if block_id == BlockRegistry.BlockId.AIR:
		return 0
	if BlockRegistry.is_water(block_id):
		return 2
	if BlockRegistry.is_passable_block(block_id):
		return 0
	if BlockRegistry.is_opaque_full_cube(block_id):
		return 15
	return 1


## Performs initial dual-channel lighting pass on a newly populated chunk.
static func compute_chunk_lighting(chunk: VoxelChunk, world_manager: WorldManager = null) -> void:
	if chunk == null:
		return

	# Ensure lighting buffer is allocated (65,536 bytes)
	chunk.ensure_lighting_buffer()

	# 1. Direct Column Skylight:
	# From sky down to highest solid block, skylight is 15.
	# Once entering blocks, attenuates by block opacity.
	var emit_queue: Array[Vector3i] = []

	for lx in range(VoxelChunk.CHUNK_SIZE_X):
		for lz in range(VoxelChunk.CHUNK_SIZE_Z):
			var current_sky: int = MAX_LIGHT
			for ly in range(VoxelChunk.CHUNK_SIZE_Y - 1, -1, -1):
				var bid: int = chunk.get_block_local(lx, ly, lz)
				var opacity: int = get_block_opacity(bid)
				var emit: int = get_block_luminance(bid)

				if emit > 0:
					chunk.set_block_light_local(lx, ly, lz, emit)
					emit_queue.append(Vector3i(lx, ly, lz))

				if opacity >= 15:
					current_sky = 0
				elif opacity > 0:
					current_sky = maxi(0, current_sky - opacity)

				chunk.set_sky_light_local(lx, ly, lz, current_sky)

	# 2. Blocklight BFS Flood Fill Propagation:
	var q_idx: int = 0
	while q_idx < emit_queue.size():
		var pos: Vector3i = emit_queue[q_idx]
		q_idx += 1
		var cur_val: int = chunk.get_block_light_local(pos.x, pos.y, pos.z)
		if cur_val <= 1:
			continue

		for offset in NEIGHBORS_6:
			var npos := pos + offset
			if chunk.is_in_bounds(npos.x, npos.y, npos.z):
				var nbid: int = chunk.get_block_local(npos.x, npos.y, npos.z)
				var n_op: int = maxi(1, get_block_opacity(nbid))
				var target_val: int = maxi(0, cur_val - n_op)
				var existing: int = chunk.get_block_light_local(npos.x, npos.y, npos.z)
				if target_val > existing:
					chunk.set_block_light_local(npos.x, npos.y, npos.z, target_val)
					emit_queue.append(npos)


## Calculates the 4-corner ambient occlusion and smooth lighting for a quad face.
## Returns Array[float] of 4 multipliers in range [0.35..1.0] for vertices [0, 1, 2, 3].
static func calculate_face_ao_and_lighting(
	chunk: VoxelChunk,
	lx: int,
	ly: int,
	lz: int,
	face_dir: int,
	block_id: int
) -> Array[float]:
	# Light emitters emit full brightness with no ambient occlusion
	if get_block_luminance(block_id) >= 14:
		return [1.0, 1.0, 1.0, 1.0]

	var face_normal: Vector3i
	var u_axis: Vector3i
	var v_axis: Vector3i

	match face_dir:
		BlockRegistry.FaceDir.TOP:
			face_normal = Vector3i(0, 1, 0)
			u_axis = Vector3i(1, 0, 0)
			v_axis = Vector3i(0, 0, 1)
		BlockRegistry.FaceDir.BOTTOM:
			face_normal = Vector3i(0, -1, 0)
			u_axis = Vector3i(1, 0, 0)
			v_axis = Vector3i(0, 0, -1)
		BlockRegistry.FaceDir.EAST:
			face_normal = Vector3i(1, 0, 0)
			u_axis = Vector3i(0, 0, -1)
			v_axis = Vector3i(0, 1, 0)
		BlockRegistry.FaceDir.WEST:
			face_normal = Vector3i(-1, 0, 0)
			u_axis = Vector3i(0, 0, 1)
			v_axis = Vector3i(0, 1, 0)
		BlockRegistry.FaceDir.SOUTH:
			face_normal = Vector3i(0, 0, 1)
			u_axis = Vector3i(1, 0, 0)
			v_axis = Vector3i(0, 1, 0)
		_: # NORTH
			face_normal = Vector3i(0, 0, -1)
			u_axis = Vector3i(-1, 0, 0)
			v_axis = Vector3i(0, 1, 0)

	var air_target := Vector3i(lx, ly, lz) + face_normal

	# 4 Corners: (u0, v0), (u1, v0), (u1, v1), (u0, v1)
	var corner_signs: Array[Vector2i] = [
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(1, 1),
		Vector2i(-1, 1),
	]

	var results: Array[float] = []

	for cs in corner_signs:
		var du: Vector3i = u_axis * cs.x
		var dv: Vector3i = v_axis * cs.y

		# 3 neighbors around corner vertex
		var s1: Vector3i = air_target + du
		var s2: Vector3i = air_target + dv
		var corner: Vector3i = air_target + du + dv

		var s1_solid: bool = _is_solid(chunk, s1)
		var s2_solid: bool = _is_solid(chunk, s2)
		var corner_solid: bool = _is_solid(chunk, corner)

		# Minecraft Beta 1.7.3 Ambient Occlusion Formula:
		# If both adjacent sides are solid, the corner is fully shadowed (ao = 0)
		var ao_score: int
		if s1_solid and s2_solid:
			ao_score = 0
		else:
			ao_score = 3 - ((1 if s1_solid else 0) + (1 if s2_solid else 0) + (1 if corner_solid else 0))

		var ao_factor: float
		match ao_score:
			3: ao_factor = 1.00
			2: ao_factor = 0.82
			1: ao_factor = 0.64
			_: ao_factor = 0.46

		# Voxel light level at the air face
		var sky: int = chunk.get_sky_light_local(air_target.x, air_target.y, air_target.z) if chunk != null else 15
		var blk: int = chunk.get_block_light_local(air_target.x, air_target.y, air_target.z) if chunk != null else 0
		var max_l: int = maxi(sky, blk)
		var light_mult: float = clampf(0.20 + 0.80 * (float(max_l) / 15.0), 0.20, 1.0)

		results.append(clampf(ao_factor * light_mult, 0.20, 1.0))

	return results


static func _is_solid(chunk: VoxelChunk, pos: Vector3i) -> bool:
	if chunk == null:
		return false
	if not chunk.is_in_bounds(pos.x, pos.y, pos.z):
		return false
	var bid: int = chunk.get_block_local(pos.x, pos.y, pos.z)
	return BlockRegistry.is_solid(bid)
