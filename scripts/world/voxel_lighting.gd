class_name VoxelLighting
extends RefCounted
## Authentic Minecraft Beta 1.7.3 Dual-Channel Voxel Lighting Engine.
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


const FACE_NORMALS: Array[Vector3i] = [
	Vector3i(0, 1, 0),  # TOP
	Vector3i(0, -1, 0), # BOTTOM
	Vector3i(1, 0, 0),  # EAST
	Vector3i(-1, 0, 0), # WEST
	Vector3i(0, 0, 1),  # SOUTH
	Vector3i(0, 0, -1), # NORTH
]

const AO_OFFSETS: Array = [
	# TOP (normal = (0,1,0), u=(1,0,0), v=(0,0,1))
	[
		[Vector3i(-1, 1, 0), Vector3i(0, 1, -1), Vector3i(-1, 1, -1)],
		[Vector3i(1, 1, 0), Vector3i(0, 1, -1), Vector3i(1, 1, -1)],
		[Vector3i(1, 1, 0), Vector3i(0, 1, 1), Vector3i(1, 1, 1)],
		[Vector3i(-1, 1, 0), Vector3i(0, 1, 1), Vector3i(-1, 1, 1)],
	],
	# BOTTOM (normal = (0,-1,0), u=(1,0,0), v=(0,0,-1))
	[
		[Vector3i(-1, -1, 0), Vector3i(0, -1, 1), Vector3i(-1, -1, 1)],
		[Vector3i(1, -1, 0), Vector3i(0, -1, 1), Vector3i(1, -1, 1)],
		[Vector3i(1, -1, 0), Vector3i(0, -1, -1), Vector3i(1, -1, -1)],
		[Vector3i(-1, -1, 0), Vector3i(0, -1, -1), Vector3i(-1, -1, -1)],
	],
	# EAST (normal = (1,0,0), u=(0,0,-1), v=(0,1,0))
	[
		[Vector3i(1, 0, 1), Vector3i(1, -1, 0), Vector3i(1, -1, 1)],
		[Vector3i(1, 0, -1), Vector3i(1, -1, 0), Vector3i(1, -1, -1)],
		[Vector3i(1, 0, -1), Vector3i(1, 1, 0), Vector3i(1, 1, -1)],
		[Vector3i(1, 0, 1), Vector3i(1, 1, 0), Vector3i(1, 1, 1)],
	],
	# WEST (normal = (-1,0,0), u=(0,0,1), v=(0,1,0))
	[
		[Vector3i(-1, 0, -1), Vector3i(-1, -1, 0), Vector3i(-1, -1, -1)],
		[Vector3i(-1, 0, 1), Vector3i(-1, -1, 0), Vector3i(-1, -1, 1)],
		[Vector3i(-1, 0, 1), Vector3i(-1, 1, 0), Vector3i(-1, 1, 1)],
		[Vector3i(-1, 0, -1), Vector3i(-1, 1, 0), Vector3i(-1, 1, -1)],
	],
	# SOUTH (normal = (0,0,1), u=(1,0,0), v=(0,1,0))
	[
		[Vector3i(-1, 0, 1), Vector3i(0, -1, 1), Vector3i(-1, -1, 1)],
		[Vector3i(1, 0, 1), Vector3i(0, -1, 1), Vector3i(1, -1, 1)],
		[Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)],
		[Vector3i(-1, 0, 1), Vector3i(0, 1, 1), Vector3i(-1, 1, 1)],
	],
	# NORTH (normal = (0,0,-1), u=(-1,0,0), v=(0,1,0))
	[
		[Vector3i(1, 0, -1), Vector3i(0, -1, -1), Vector3i(1, -1, -1)],
		[Vector3i(-1, 0, -1), Vector3i(0, -1, -1), Vector3i(-1, -1, -1)],
		[Vector3i(-1, 0, -1), Vector3i(0, 1, -1), Vector3i(-1, 1, -1)],
		[Vector3i(1, 0, -1), Vector3i(0, 1, -1), Vector3i(1, 1, -1)],
	],
]

const AO_SCORES: Array[float] = [0.46, 0.64, 0.82, 1.00]

static var AO_DX: PackedInt32Array = _init_ao_offsets(0)
static var AO_DY: PackedInt32Array = _init_ao_offsets(1)
static var AO_DZ: PackedInt32Array = _init_ao_offsets(2)

static func _init_ao_offsets(axis: int) -> PackedInt32Array:
	var arr := PackedInt32Array()
	arr.resize(72)
	for f in range(6):
		var dir_offsets: Array = AO_OFFSETS[f]
		for c in range(4):
			var triple: Array = dir_offsets[c]
			for t in range(3):
				var off: Vector3i = triple[t]
				var idx: int = (f * 12) + (c * 3) + t
				match axis:
					0: arr[idx] = off.x
					1: arr[idx] = off.y
					_: arr[idx] = off.z
	return arr

static var _solid_table: PackedByteArray = _init_solid_table()

static func _init_solid_table() -> PackedByteArray:
	var arr := PackedByteArray()
	arr.resize(256)
	for id in range(256):
		arr[id] = 1 if BlockRegistry.is_solid(id) else 0
	return arr


## Calculates the 4-corner ambient occlusion and smooth lighting for a quad face.
## Returns Plane(r0, r1, r2, r3) as zero-allocation value type in range [0.20..1.0].
static func calculate_face_ao(
	chunk: VoxelChunk,
	lx: int,
	ly: int,
	lz: int,
	face_dir: int,
	block_id: int,
	explicit_voxels: PackedByteArray = PackedByteArray(),
	explicit_lighting: PackedByteArray = PackedByteArray()
) -> Plane:
	if get_block_luminance(block_id) >= 14:
		return Plane(1.0, 1.0, 1.0, 1.0)

	var fn: Vector3i = FACE_NORMALS[face_dir]
	var at_x: int = lx + fn.x
	var at_y: int = ly + fn.y
	var at_z: int = lz + fn.z

	var l_buf: PackedByteArray = explicit_lighting if not explicit_lighting.is_empty() else (chunk._lighting if chunk != null else PackedByteArray())
	var sky: int = 15
	var blk: int = 0
	if not l_buf.is_empty() and at_x >= 0 and at_x < 16 and at_y >= 0 and at_y < 128 and at_z >= 0 and at_z < 16:
		var l_val: int = l_buf[(at_y << 8) | (at_z << 4) | at_x]
		sky = (l_val >> 4) & 0x0F
		blk = l_val & 0x0F
	elif chunk != null:
		sky = chunk.get_sky_light_local(at_x, at_y, at_z)
		blk = chunk.get_block_light_local(at_x, at_y, at_z)

	var light_mult: float = clampf(0.20 + 0.80 * (float(maxi(sky, blk)) / 15.0), 0.20, 1.0)

	var voxels: PackedByteArray = explicit_voxels if not explicit_voxels.is_empty() else (chunk._voxels if chunk != null else PackedByteArray())
	var has_voxels: bool = not voxels.is_empty()
	var base_f: int = face_dir * 12

	var r0: float = 1.0; var r1: float = 1.0; var r2: float = 1.0; var r3: float = 1.0

	for c in range(4):
		var b_idx: int = base_f + (c * 3)

		var x1: int = lx + AO_DX[b_idx]; var y1: int = ly + AO_DY[b_idx]; var z1: int = lz + AO_DZ[b_idx]
		var s1: bool = (has_voxels and _solid_table[voxels[(y1 << 8) | (z1 << 4) | x1]] == 1) if (x1 >= 0 and x1 < 16 and y1 >= 0 and y1 < 128 and z1 >= 0 and z1 < 16) else (y1 < 0)

		var x2: int = lx + AO_DX[b_idx + 1]; var y2: int = ly + AO_DY[b_idx + 1]; var z2: int = lz + AO_DZ[b_idx + 1]
		var s2: bool = (has_voxels and _solid_table[voxels[(y2 << 8) | (z2 << 4) | x2]] == 1) if (x2 >= 0 and x2 < 16 and y2 >= 0 and y2 < 128 and z2 >= 0 and z2 < 16) else (y2 < 0)

		var x3: int = lx + AO_DX[b_idx + 2]; var y3: int = ly + AO_DY[b_idx + 2]; var z3: int = lz + AO_DZ[b_idx + 2]
		var s3: bool = (has_voxels and _solid_table[voxels[(y3 << 8) | (z3 << 4) | x3]] == 1) if (x3 >= 0 and x3 < 16 and y3 >= 0 and y3 < 128 and z3 >= 0 and z3 < 16) else (y3 < 0)

		var ao_factor: float
		if s1 and s2:
			ao_factor = 0.46
		else:
			var score: int = 3 - ((1 if s1 else 0) + (1 if s2 else 0) + (1 if s3 else 0))
			ao_factor = AO_SCORES[clampi(score, 0, 3)]

		var final_val: float = clampf(ao_factor * light_mult, 0.20, 1.0)
		match c:
			0: r0 = final_val
			1: r1 = final_val
			2: r2 = final_val
			_: r3 = final_val

	return Plane(r0, r1, r2, r3)


## Calculates the 4-corner ambient occlusion and smooth lighting for a quad face.
## Returns Array[float] of 4 multipliers in range [0.20..1.0] for vertices [0, 1, 2, 3].
static func calculate_face_ao_and_lighting(
	chunk: VoxelChunk,
	lx: int,
	ly: int,
	lz: int,
	face_dir: int,
	block_id: int
) -> Array[float]:
	var p: Plane = calculate_face_ao(chunk, lx, ly, lz, face_dir, block_id)
	return [p.x, p.y, p.z, p.d]


static func _is_solid_raw(chunk: VoxelChunk, x: int, y: int, z: int) -> bool:
	if y < 0:
		return true
	if y >= 128 or x < 0 or x >= 16 or z < 0 or z >= 16:
		return false
	if chunk == null or chunk._voxels.is_empty():
		return false
	return _solid_table[chunk._voxels[(y << 8) | (z << 4) | x]] == 1


static func _is_solid(chunk: VoxelChunk, pos: Vector3i) -> bool:
	return _is_solid_raw(chunk, pos.x, pos.y, pos.z)
