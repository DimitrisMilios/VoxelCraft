class_name VoxelLighting
extends RefCounted
## Dual-channel voxel lighting: 0..15 skylight and 0..15 blocklight per block, packed in one byte
## (high nibble = sky, low nibble = block).
##
## - `compute_light_buffer` lights a freshly generated chunk on a worker thread (sky columns,
##   horizontal sky spread under overhangs, and block-light flood fill from emitters).
## - `stitch_inflow` (worker) pulls light across the chunk borders from the neighbor chunks.
## - `update_light_at` (main thread) incrementally removes/re-adds light around one edited block,
##   crossing chunk borders, and reports which sub-chunks need a remesh.

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


## Returns the light emission level [0..15] of a block.
static func get_block_luminance(block_id: int) -> int:
	return BlockRegistry.get_luminance(block_id)


## Returns the light opacity [0..15] of a block (opaque cubes 15, water/ice 2, leaves 1, air 0).
static func get_block_opacity(block_id: int) -> int:
	return BlockRegistry.light_opacity_table[block_id & 0xFF]


# ============================================================================
# WHOLE-CHUNK LIGHTING (worker thread)
# ============================================================================

## Lights `chunk` from scratch using only its own voxels.
static func compute_chunk_lighting(chunk: VoxelChunk, _world_manager: Node = null) -> void:
	if chunk == null:
		return
	if chunk._voxels.is_empty():
		chunk.ensure_lighting_buffer()
		chunk._lighting.fill(0xF0)
		return
	chunk._lighting = compute_light_buffer(chunk._voxels, chunk.get_highest_solid_y())


static func compute_light_buffer(vox: PackedByteArray, highest_y: int) -> PackedByteArray:
	var opacity: PackedByteArray = BlockRegistry.light_opacity_table
	var top: int = clampi(highest_y + 2, 1, 256)

	# Everything above the tallest block is open sky.
	var light := PackedByteArray()
	light.resize(top * 256)
	var upper := PackedByteArray()
	upper.resize((256 - top) * 256)
	upper.fill(0xF0)
	light.append_array(upper)

	# 1. Direct skylight straight down each column until something blocks it.
	var heightmap := PackedInt32Array()
	heightmap.resize(256)
	for col in range(256):
		var sky: int = 15
		var y: int = top - 1
		while y >= 0:
			var idx: int = (y << 8) | col
			var op: int = opacity[vox[idx]]
			if op >= 15:
				break
			if op > 0:
				sky -= op
				if sky <= 0:
					break
			light[idx] = sky << 4
			y -= 1
		heightmap[col] = y

	# 2. Spread sideways into neighboring columns that are shaded at that height (overhangs, cave mouths).
	var queue := PackedInt32Array()
	for z in range(16):
		for x in range(16):
			var col: int = (z << 4) | x
			var h: int = heightmap[col]
			var m: int = h
			if x > 0:
				m = maxi(m, heightmap[col - 1])
			if x < 15:
				m = maxi(m, heightmap[col + 1])
			if z > 0:
				m = maxi(m, heightmap[col - 16])
			if z < 15:
				m = maxi(m, heightmap[col + 16])
			for y in range(h + 1, m + 1):
				queue.append((y << 8) | col)
	_flood_local(light, vox, queue, true)

	# 3. Block light from every emitter in the chunk.
	queue = PackedInt32Array()
	for emitter_id in [BlockRegistry.BlockId.LAVA, BlockRegistry.BlockId.GLOWSTONE, BlockRegistry.BlockId.TORCH, BlockRegistry.BlockId.REDSTONE_TORCH]:
		var lum: int = BlockRegistry.get_luminance(emitter_id)
		var idx: int = vox.find(emitter_id)
		while idx != -1:
			light[idx] = (light[idx] & 0xF0) | lum
			queue.append(idx)
			idx = vox.find(emitter_id, idx + 1)
	_flood_local(light, vox, queue, false)
	return light


## Breadth-first light spread confined to one chunk buffer.
static func _flood_local(light: PackedByteArray, vox: PackedByteArray, queue: PackedInt32Array, sky: bool) -> void:
	var opacity: PackedByteArray = BlockRegistry.light_opacity_table
	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var lv: int = light[idx]
		var val: int = (lv >> 4) if sky else (lv & 15)
		if val <= 1:
			continue
		var x: int = idx & 15
		var z: int = (idx >> 4) & 15
		var y: int = idx >> 8
		if x < 15:
			_spread_local(light, vox, opacity, queue, idx + 1, val, sky, false)
		if x > 0:
			_spread_local(light, vox, opacity, queue, idx - 1, val, sky, false)
		if z < 15:
			_spread_local(light, vox, opacity, queue, idx + 16, val, sky, false)
		if z > 0:
			_spread_local(light, vox, opacity, queue, idx - 16, val, sky, false)
		if y < 255:
			_spread_local(light, vox, opacity, queue, idx + 256, val, sky, false)
		if y > 0:
			_spread_local(light, vox, opacity, queue, idx - 256, val, sky, true)


static func _spread_local(
	light: PackedByteArray, vox: PackedByteArray, opacity: PackedByteArray,
	queue: PackedInt32Array, n_idx: int, val: int, sky: bool, downward: bool
) -> void:
	var op: int = opacity[vox[n_idx]]
	if op >= 15:
		return
	var nv: int = val - maxi(op, 1)
	if sky and downward and val == 15 and op == 0:
		nv = 15
	var cur: int = light[n_idx]
	if sky:
		if nv > (cur >> 4):
			light[n_idx] = (nv << 4) | (cur & 15)
			queue.append(n_idx)
	elif nv > (cur & 15):
		light[n_idx] = (cur & 0xF0) | nv
		queue.append(n_idx)


## Pulls sky and block light in from the four side neighbors (one hop across each border), then
## floods it through `light`. `nb_light` / `nb_vox` hold 9 arrays indexed `(dz + 1) * 3 + (dx + 1)`.
static func stitch_inflow(light: PackedByteArray, vox: PackedByteArray, nb_light: Array, top: int) -> void:
	var opacity: PackedByteArray = BlockRegistry.light_opacity_table
	var y_end: int = clampi(top, 1, 256)
	var queue_sky := PackedInt32Array()
	var queue_blk := PackedInt32Array()
	# [neighbor slot, our border coordinate, neighbor border coordinate, axis is x?]
	var sides: Array = [[3, 0, 15, true], [5, 15, 0, true], [1, 0, 15, false], [7, 15, 0, false]]
	for side in sides:
		var nl: PackedByteArray = nb_light[side[0]]
		if nl.is_empty():
			continue
		var ours: int = side[1]
		var theirs: int = side[2]
		var along_x: bool = side[3]
		for y in range(y_end):
			var yb: int = y << 8
			for t in range(16):
				var my_idx: int
				var nb_idx: int
				if along_x:
					my_idx = yb | (t << 4) | ours
					nb_idx = yb | (t << 4) | theirs
				else:
					my_idx = yb | (ours << 4) | t
					nb_idx = yb | (theirs << 4) | t
				var op: int = opacity[vox[my_idx]]
				if op >= 15:
					continue
				var dec: int = maxi(op, 1)
				var n_val: int = nl[nb_idx]
				var cur: int = light[my_idx]
				var sky_in: int = (n_val >> 4) - dec
				if sky_in > (cur >> 4):
					cur = (sky_in << 4) | (cur & 15)
					light[my_idx] = cur
					queue_sky.append(my_idx)
				var blk_in: int = (n_val & 15) - dec
				if blk_in > (cur & 15):
					light[my_idx] = (cur & 0xF0) | blk_in
					queue_blk.append(my_idx)
	_flood_local(light, vox, queue_sky, true)
	_flood_local(light, vox, queue_blk, false)


# ============================================================================
# INCREMENTAL WORLD LIGHTING (main thread)
# ============================================================================

## Per-update scratch state: chunk lookup cache and the set of sub-chunks touched.
class LightCtx:
	var wm: Node
	var chunks: Dictionary = {}
	## Vector2i chunk coord -> {sub_idx: true}
	var dirty: Dictionary = {}

	func _init(world: Node, dirty_out: Dictionary) -> void:
		wm = world
		dirty = dirty_out

	func chunk_at(cx: int, cz: int) -> VoxelChunk:
		var key := Vector2i(cx, cz)
		if chunks.has(key):
			return chunks[key]
		var c: VoxelChunk = wm.find_loaded_chunk(key)
		if c != null and c._lighting.is_empty():
			VoxelLighting.compute_chunk_lighting(c)
		chunks[key] = c
		return c

	func block_at(p: Vector3i) -> int:
		if p.y < 0:
			return BlockRegistry.BlockId.BEDROCK
		if p.y > 255:
			return BlockRegistry.BlockId.AIR
		var c: VoxelChunk = chunk_at(p.x >> 4, p.z >> 4)
		if c == null or c._voxels.is_empty():
			return BlockRegistry.BlockId.BEDROCK
		return c._voxels[(p.y << 8) | ((p.z & 15) << 4) | (p.x & 15)]

	## Returns -1 for positions that cannot hold light (outside the world or unloaded).
	func get_light(p: Vector3i, sky: bool) -> int:
		if p.y > 255:
			return 15 if sky else 0
		if p.y < 0:
			return -1
		var c: VoxelChunk = chunk_at(p.x >> 4, p.z >> 4)
		if c == null:
			return -1
		var v: int = c._lighting[(p.y << 8) | ((p.z & 15) << 4) | (p.x & 15)]
		return (v >> 4) if sky else (v & 15)

	func set_light(p: Vector3i, val: int, sky: bool) -> void:
		var c: VoxelChunk = chunk_at(p.x >> 4, p.z >> 4)
		if c == null:
			return
		var idx: int = (p.y << 8) | ((p.z & 15) << 4) | (p.x & 15)
		var cur: int = c._lighting[idx]
		var nv: int = ((val << 4) | (cur & 15)) if sky else ((cur & 0xF0) | val)
		if nv == cur:
			return
		c._lighting[idx] = nv
		mark_dirty(p)

	func mark_dirty(p: Vector3i) -> void:
		VoxelLighting.mark_remesh(dirty, p)


## Records that the block at world position `p` changed, flagging its sub-chunk and any neighbor
## sub-chunks whose padded border copy contains it.
static func mark_remesh(dirty: Dictionary, p: Vector3i) -> void:
	var cx: int = p.x >> 4
	var cz: int = p.z >> 4
	var lx: int = p.x & 15
	var lz: int = p.z & 15
	var sub: int = p.y >> 4
	var ly: int = p.y & 15
	var dxs: Array[int] = [0]
	var dzs: Array[int] = [0]
	var subs: Array[int] = [sub]
	if lx == 0:
		dxs.append(-1)
	elif lx == 15:
		dxs.append(1)
	if lz == 0:
		dzs.append(-1)
	elif lz == 15:
		dzs.append(1)
	if ly == 0 and sub > 0:
		subs.append(sub - 1)
	elif ly == 15 and sub < 15:
		subs.append(sub + 1)
	for dx in dxs:
		for dz in dzs:
			var key := Vector2i(cx + dx, cz + dz)
			if not dirty.has(key):
				dirty[key] = {}
			for s in subs:
				dirty[key][s] = true


## Re-lights around `pos` after its block changed (both channels). Touched sub-chunks are added to
## `dirty` (Vector2i -> {sub_idx: true}).
static func update_light_at(wm: Node, pos: Vector3i, dirty: Dictionary) -> void:
	var ctx := LightCtx.new(wm, dirty)
	_update_channel(ctx, pos, false)
	_update_channel(ctx, pos, true)


## Light-adding pass for many cells that just became transparent at once (explosions).
static func refill_cleared(wm: Node, cleared: Array[Vector3i], dirty: Dictionary) -> void:
	var ctx := LightCtx.new(wm, dirty)
	for sky in [false, true]:
		var add_q: Array[Vector3i] = []
		for p in cleared:
			for d in NEIGHBORS_6:
				var n: Vector3i = p + d
				if ctx.get_light(n, sky) > 0:
					add_q.append(n)
		_flood_add(ctx, add_q, sky)


static func _update_channel(ctx: LightCtx, pos: Vector3i, sky: bool) -> void:
	if pos.y < 0 or pos.y > 255:
		return
	var cur: int = ctx.get_light(pos, sky)
	if cur < 0:
		return
	var add_q: Array[Vector3i] = []

	# 1. Remove the light that flowed through this cell.
	if cur > 0:
		ctx.set_light(pos, 0, sky)
		_flood_remove(ctx, pos, cur, sky, add_q)

	# 2. Re-seed: emitters, open sky directly above, and every lit neighbor flowing back in.
	var id: int = ctx.block_at(pos)
	var op: int = get_block_opacity(id)
	if not sky:
		var emit: int = get_block_luminance(id)
		if emit > 0:
			ctx.set_light(pos, emit, false)
			add_q.append(pos)
	if op < 15:
		if sky and pos.y == 255:
			ctx.set_light(pos, 15 - op, true)
			add_q.append(pos)
		for d in NEIGHBORS_6:
			var n: Vector3i = pos + d
			if ctx.get_light(n, sky) > 0:
				add_q.append(n)
	_flood_add(ctx, add_q, sky)


static func _flood_remove(ctx: LightCtx, start: Vector3i, start_val: int, sky: bool, add_q: Array[Vector3i]) -> void:
	var q_pos: Array[Vector3i] = [start]
	var q_val: PackedInt32Array = PackedInt32Array([start_val])
	var head: int = 0
	while head < q_pos.size():
		var p: Vector3i = q_pos[head]
		var val: int = q_val[head]
		head += 1
		for i in range(6):
			var d: Vector3i = NEIGHBORS_6[i]
			var n: Vector3i = p + d
			if n.y < 0 or n.y > 255:
				continue
			var nl: int = ctx.get_light(n, sky)
			if nl <= 0:
				continue
			var dependent: bool = nl < val
			if sky and i == 1 and val == 15 and nl == 15:
				dependent = true
			if dependent:
				# Keep emitters lit; they are re-added below.
				if not sky and get_block_luminance(ctx.block_at(n)) > 0:
					add_q.append(n)
					continue
				ctx.set_light(n, 0, sky)
				q_pos.append(n)
				q_val.append(nl)
			else:
				add_q.append(n)


static func _flood_add(ctx: LightCtx, queue: Array[Vector3i], sky: bool) -> void:
	var head: int = 0
	while head < queue.size():
		var p: Vector3i = queue[head]
		head += 1
		var val: int = ctx.get_light(p, sky)
		if val <= 1:
			continue
		for i in range(6):
			var n: Vector3i = p + NEIGHBORS_6[i]
			if n.y < 0 or n.y > 255:
				continue
			var nl: int = ctx.get_light(n, sky)
			if nl < 0:
				continue
			var op: int = get_block_opacity(ctx.block_at(n))
			if op >= 15:
				continue
			var nv: int = val - maxi(op, 1)
			if sky and i == 1 and val == 15 and op == 0:
				nv = 15
			if nv > nl:
				ctx.set_light(n, nv, sky)
				queue.append(n)


# ============================================================================
# LEGACY AO HELPERS (kept for tools/tests; the mesher computes AO itself)
# ============================================================================

const FACE_NORMALS: Array[Vector3i] = [
	Vector3i(0, 1, 0),  # TOP
	Vector3i(0, -1, 0), # BOTTOM
	Vector3i(1, 0, 0),  # EAST
	Vector3i(-1, 0, 0), # WEST
	Vector3i(0, 0, 1),  # SOUTH
	Vector3i(0, 0, -1), # NORTH
]

const AO_OFFSETS: Array = [
	[[Vector3i(-1, 1, 0), Vector3i(0, 1, -1), Vector3i(-1, 1, -1)], [Vector3i(1, 1, 0), Vector3i(0, 1, -1), Vector3i(1, 1, -1)], [Vector3i(1, 1, 0), Vector3i(0, 1, 1), Vector3i(1, 1, 1)], [Vector3i(-1, 1, 0), Vector3i(0, 1, 1), Vector3i(-1, 1, 1)]],
	[[Vector3i(-1, -1, 0), Vector3i(0, -1, 1), Vector3i(-1, -1, 1)], [Vector3i(1, -1, 0), Vector3i(0, -1, 1), Vector3i(1, -1, 1)], [Vector3i(1, -1, 0), Vector3i(0, -1, -1), Vector3i(1, -1, -1)], [Vector3i(-1, -1, 0), Vector3i(0, -1, -1), Vector3i(-1, -1, -1)]],
	[[Vector3i(1, 0, 1), Vector3i(1, -1, 0), Vector3i(1, -1, 1)], [Vector3i(1, 0, -1), Vector3i(1, -1, 0), Vector3i(1, -1, -1)], [Vector3i(1, 0, -1), Vector3i(1, 1, 0), Vector3i(1, 1, -1)], [Vector3i(1, 0, 1), Vector3i(1, 1, 0), Vector3i(1, 1, 1)]],
	[[Vector3i(-1, 0, -1), Vector3i(-1, -1, 0), Vector3i(-1, -1, -1)], [Vector3i(-1, 0, 1), Vector3i(-1, -1, 0), Vector3i(-1, -1, 1)], [Vector3i(-1, 0, 1), Vector3i(-1, 1, 0), Vector3i(-1, 1, 1)], [Vector3i(-1, 0, -1), Vector3i(-1, 1, 0), Vector3i(-1, 1, -1)]],
	[[Vector3i(-1, 0, 1), Vector3i(0, -1, 1), Vector3i(-1, -1, 1)], [Vector3i(1, 0, 1), Vector3i(0, -1, 1), Vector3i(1, -1, 1)], [Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)], [Vector3i(-1, 0, 1), Vector3i(0, 1, 1), Vector3i(-1, 1, 1)]],
	[[Vector3i(1, 0, -1), Vector3i(0, -1, -1), Vector3i(1, -1, -1)], [Vector3i(-1, 0, -1), Vector3i(0, -1, -1), Vector3i(-1, -1, -1)], [Vector3i(-1, 0, -1), Vector3i(0, 1, -1), Vector3i(-1, 1, -1)], [Vector3i(1, 0, -1), Vector3i(0, 1, -1), Vector3i(1, 1, -1)]],
]

const AO_SCORES: Array[float] = [0.5, 0.65, 0.8, 1.0]


## Calculates the 4-corner ambient occlusion * light multipliers for one face of a block.
static func calculate_face_ao(
	chunk: VoxelChunk,
	lx: int,
	ly: int,
	lz: int,
	face_dir: int,
	block_id: int,
	_explicit_voxels: PackedByteArray = PackedByteArray(),
	_explicit_lighting: PackedByteArray = PackedByteArray()
) -> Plane:
	if get_block_luminance(block_id) >= 14:
		return Plane(1.0, 1.0, 1.0, 1.0)
	var fn: Vector3i = FACE_NORMALS[face_dir]
	var sky: int = chunk.get_sky_light_local(lx + fn.x, ly + fn.y, lz + fn.z)
	var blk: int = chunk.get_block_light_local(lx + fn.x, ly + fn.y, lz + fn.z)
	var light_mult: float = clampf(0.20 + 0.80 * (float(maxi(sky, blk)) / 15.0), 0.20, 1.0)
	var r: Array[float] = [1.0, 1.0, 1.0, 1.0]
	for c in range(4):
		var offs: Array = AO_OFFSETS[face_dir][c]
		var s1: bool = _is_solid_raw(chunk, lx + offs[0].x, ly + offs[0].y, lz + offs[0].z)
		var s2: bool = _is_solid_raw(chunk, lx + offs[1].x, ly + offs[1].y, lz + offs[1].z)
		var s3: bool = _is_solid_raw(chunk, lx + offs[2].x, ly + offs[2].y, lz + offs[2].z)
		var score: int = 0 if (s1 and s2) else 3 - ((1 if s1 else 0) + (1 if s2 else 0) + (1 if s3 else 0))
		r[c] = clampf(AO_SCORES[clampi(score, 0, 3)] * light_mult, 0.20, 1.0)
	return Plane(r[0], r[1], r[2], r[3])


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
	if y > 255 or x < 0 or x >= 16 or z < 0 or z >= 16:
		return false
	if chunk == null or chunk._voxels.is_empty():
		return false
	return BlockRegistry.is_occluder(chunk._voxels[(y << 8) | (z << 4) | x])


static func _is_solid(chunk: VoxelChunk, pos: Vector3i) -> bool:
	return _is_solid_raw(chunk, pos.x, pos.y, pos.z)
