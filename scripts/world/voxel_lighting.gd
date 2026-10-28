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
#
# Edits are relit inside the 3x3 chunks around the edited block: light travels at most 15 blocks,
# so that region always contains every cell an edit can affect. Cells are addressed with a packed
# region key `(y << 12) | (rz << 6) | rx` (rx, rz in 0..47), and buffers are read directly.

const REGION: int = 48


## The 3x3 chunk buffers around an edit, plus which (chunk, sub-chunk) cells changed.
class LightRegion:
	var cx0: int
	var cz0: int
	var chunks: Array = []
	var vox: Array = []
	var light: Array = []
	## Per (chunk index * 16 + sub): bit 0 = changed, bits 1..6 = touched -x, +x, -z, +z, -y, +y edges.
	var changed := PackedByteArray()

	func _init(wm: Node, center: Vector2i) -> void:
		cx0 = center.x - 1
		cz0 = center.y - 1
		changed.resize(9 * 16)
		for dz in range(3):
			for dx in range(3):
				var c: VoxelChunk = wm.find_loaded_chunk(Vector2i(cx0 + dx, cz0 + dz))
				if c != null and not c._voxels.is_empty() and c._lighting.is_empty():
					VoxelLighting.compute_chunk_lighting(c)
				chunks.append(c)
				vox.append(c._voxels if c != null else PackedByteArray())
				light.append(c._lighting if c != null and not c._voxels.is_empty() else PackedByteArray())

	func key_of(p: Vector3i) -> int:
		return (p.y << 12) | ((p.z - cz0 * 16) << 6) | (p.x - cx0 * 16)

	## Records a light write at region key `k` for remeshing.
	func touch(k: int) -> void:
		var rx: int = k & 63
		var rz: int = (k >> 6) & 63
		var y: int = k >> 12
		var lx: int = rx & 15
		var lz: int = rz & 15
		var ly: int = y & 15
		var bits: int = 1
		if lx == 0:
			bits |= 2
		elif lx == 15:
			bits |= 4
		if lz == 0:
			bits |= 8
		elif lz == 15:
			bits |= 16
		if ly == 0:
			bits |= 32
		elif ly == 15:
			bits |= 64
		var slot: int = (((rz >> 4) * 3 + (rx >> 4)) << 4) | (y >> 4)
		changed[slot] = changed[slot] | bits

	## Converts the change flags into remesh requests (`Vector2i -> {sub: true}`) and bumps light versions.
	func flush_dirty(dirty: Dictionary) -> void:
		for slot in range(9 * 16):
			var bits: int = changed[slot]
			if bits == 0:
				continue
			var ci: int = slot >> 4
			var sub: int = slot & 15
			var cx: int = cx0 + ci % 3
			var cz: int = cz0 + ci / 3
			var c: VoxelChunk = chunks[ci]
			if c != null:
				c.light_version += 1
			var dxs: Array[int] = [0]
			var dzs: Array[int] = [0]
			var subs: Array[int] = [sub]
			if bits & 2:
				dxs.append(-1)
			if bits & 4:
				dxs.append(1)
			if bits & 8:
				dzs.append(-1)
			if bits & 16:
				dzs.append(1)
			if (bits & 32) and sub > 0:
				subs.append(sub - 1)
			if (bits & 64) and sub < 15:
				subs.append(sub + 1)
			for dx in dxs:
				for dz in dzs:
					var key := Vector2i(cx + dx, cz + dz)
					if not dirty.has(key):
						dirty[key] = {}
					for s in subs:
						dirty[key][s] = true


## Reads the light nibble at region key `k` (-1 if outside the region or unloaded).
static func _rget(r: LightRegion, k: int, sky: bool) -> int:
	var rx: int = k & 63
	var rz: int = (k >> 6) & 63
	if rx >= REGION or rz >= REGION:
		return -1
	var buf: PackedByteArray = r.light[(rz >> 4) * 3 + (rx >> 4)]
	if buf.is_empty():
		return -1
	var v: int = buf[((k >> 12) << 8) | ((rz & 15) << 4) | (rx & 15)]
	return (v >> 4) if sky else (v & 15)


static func _rset(r: LightRegion, k: int, val: int, sky: bool) -> void:
	var rx: int = k & 63
	var rz: int = (k >> 6) & 63
	var buf: PackedByteArray = r.light[(rz >> 4) * 3 + (rx >> 4)]
	var li: int = ((k >> 12) << 8) | ((rz & 15) << 4) | (rx & 15)
	var cur: int = buf[li]
	var nv: int = ((val << 4) | (cur & 15)) if sky else ((cur & 0xF0) | val)
	if nv != cur:
		buf[li] = nv
		r.touch(k)


static func _rblock(r: LightRegion, k: int) -> int:
	var rx: int = k & 63
	var rz: int = (k >> 6) & 63
	var buf: PackedByteArray = r.vox[(rz >> 4) * 3 + (rx >> 4)]
	if buf.is_empty():
		return BlockRegistry.BlockId.BEDROCK
	return buf[((k >> 12) << 8) | ((rz & 15) << 4) | (rx & 15)]


## Neighbor key in direction `dir` (0..5), or -1 if it leaves the region / world.
static func _rstep(k: int, dir: int) -> int:
	match dir:
		0:
			return k + 4096 if (k >> 12) < 255 else -1
		1:
			return k - 4096 if (k >> 12) > 0 else -1
		2:
			return k + 1 if (k & 63) < REGION - 1 else -1
		3:
			return k - 1 if (k & 63) > 0 else -1
		4:
			return k + 64 if ((k >> 6) & 63) < REGION - 1 else -1
		_:
			return k - 64 if ((k >> 6) & 63) > 0 else -1


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


## Re-lights around `pos` after its block changed from `old_id`. Touched sub-chunks are added to
## `dirty` (Vector2i -> {sub_idx: true}). Only the channels the change can affect are updated.
static func update_light_at(wm: Node, pos: Vector3i, dirty: Dictionary, old_id: int = -1) -> void:
	if pos.y < 0 or pos.y > 255:
		return
	var r := LightRegion.new(wm, Vector2i(pos.x >> 4, pos.z >> 4))
	if r.light[4].is_empty():
		return
	var k: int = r.key_of(pos)
	var new_id: int = _rblock(r, k)
	var opacity_changed: bool = old_id < 0 or get_block_opacity(old_id) != get_block_opacity(new_id)
	var emit_changed: bool = old_id < 0 or get_block_luminance(old_id) != get_block_luminance(new_id)
	if opacity_changed or emit_changed:
		_update_channel(r, k, false)
	if opacity_changed:
		_update_channel(r, k, true)
	r.flush_dirty(dirty)


## Light-adding pass for many cells that just became transparent at once (explosions).
static func refill_cleared(wm: Node, cleared: Array[Vector3i], dirty: Dictionary) -> void:
	if cleared.is_empty():
		return
	var r := LightRegion.new(wm, Vector2i(cleared[0].x >> 4, cleared[0].z >> 4))
	for sky in [false, true]:
		var add_q := PackedInt32Array()
		for p in cleared:
			if (p.x >> 4) < r.cx0 or (p.x >> 4) > r.cx0 + 2 or (p.z >> 4) < r.cz0 or (p.z >> 4) > r.cz0 + 2:
				continue
			var k: int = r.key_of(p)
			for dir in range(6):
				var n: int = _rstep(k, dir)
				if n >= 0 and _rget(r, n, sky) > 0:
					add_q.append(n)
		_flood_add(r, add_q, sky)
	r.flush_dirty(dirty)


static func _update_channel(r: LightRegion, k: int, sky: bool) -> void:
	var cur: int = _rget(r, k, sky)
	if cur < 0:
		return
	var add_q := PackedInt32Array()

	# 1. Remove the light that flowed through this cell.
	if cur > 0:
		_rset(r, k, 0, sky)
		_flood_remove(r, k, cur, sky, add_q)

	# 2. Re-seed: emitters, open sky directly above, and every lit neighbor flowing back in.
	var id: int = _rblock(r, k)
	var op: int = get_block_opacity(id)
	if not sky:
		var emit: int = get_block_luminance(id)
		if emit > 0:
			_rset(r, k, emit, false)
			add_q.append(k)
	if op < 15:
		if sky and (k >> 12) == 255:
			_rset(r, k, 15 - op, true)
			add_q.append(k)
		for dir in range(6):
			var n: int = _rstep(k, dir)
			if n >= 0 and _rget(r, n, sky) > 0:
				add_q.append(n)
	_flood_add(r, add_q, sky)


static func _flood_remove(r: LightRegion, start: int, start_val: int, sky: bool, add_q: PackedInt32Array) -> void:
	var q_key := PackedInt32Array([start])
	var q_val := PackedInt32Array([start_val])
	var head: int = 0
	while head < q_key.size():
		var k: int = q_key[head]
		var val: int = q_val[head]
		head += 1
		for dir in range(6):
			var n: int = _rstep(k, dir)
			if n < 0:
				continue
			var nl: int = _rget(r, n, sky)
			if nl <= 0:
				continue
			var dependent: bool = nl < val or (sky and dir == 1 and val == 15 and nl == 15)
			if dependent:
				# Keep emitters lit; they are re-added afterwards.
				if not sky and get_block_luminance(_rblock(r, n)) > 0:
					add_q.append(n)
					continue
				_rset(r, n, 0, sky)
				q_key.append(n)
				q_val.append(nl)
			else:
				add_q.append(n)


## Spreads light outward from every key in `queue`. This is the hot loop of every light update, so
## neighbor addressing is written out inline instead of going through the helper functions.
static func _flood_add(r: LightRegion, queue: PackedInt32Array, sky: bool) -> void:
	var opacity: PackedByteArray = BlockRegistry.light_opacity_table
	var lights: Array = r.light
	var voxes: Array = r.vox
	var shift: int = 4 if sky else 0
	var keep_mask: int = 0x0F if sky else 0xF0
	var head: int = 0
	while head < queue.size():
		var k: int = queue[head]
		head += 1
		var rx: int = k & 63
		var rz: int = (k >> 6) & 63
		var y: int = k >> 12
		var own: PackedByteArray = lights[(rz >> 4) * 3 + (rx >> 4)]
		var val: int = (own[(y << 8) | ((rz & 15) << 4) | (rx & 15)] >> shift) & 15
		if val <= 1:
			continue
		for dir in range(6):
			var nx: int = rx
			var nz: int = rz
			var ny: int = y
			match dir:
				0:
					ny += 1
					if ny > 255:
						continue
				1:
					ny -= 1
					if ny < 0:
						continue
				2:
					nx += 1
					if nx >= REGION:
						continue
				3:
					nx -= 1
					if nx < 0:
						continue
				4:
					nz += 1
					if nz >= REGION:
						continue
				_:
					nz -= 1
					if nz < 0:
						continue
			var ci: int = (nz >> 4) * 3 + (nx >> 4)
			var buf: PackedByteArray = lights[ci]
			if buf.is_empty():
				continue
			var li: int = (ny << 8) | ((nz & 15) << 4) | (nx & 15)
			var vbuf: PackedByteArray = voxes[ci]
			var op: int = opacity[vbuf[li]]
			if op >= 15:
				continue
			var nv: int = val - maxi(op, 1)
			if sky and dir == 1 and val == 15 and op == 0:
				nv = 15
			var cur: int = buf[li]
			if nv > ((cur >> shift) & 15):
				buf[li] = (cur & keep_mask) | (nv << shift)
				var nk: int = (ny << 12) | (nz << 6) | nx
				r.touch(nk)
				queue.append(nk)


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
