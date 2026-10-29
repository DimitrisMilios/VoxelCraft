class_name ChunkMesher
extends RefCounted
## Thread-safe sub-chunk mesher.
##
## Works on an 18x18x18 "padded" copy of a 16x16x16 sub-chunk (one extra block on every side,
## taken from the neighbor chunks), so face culling, smooth lighting and ambient occlusion are
## seamless across chunk borders without any cross-chunk lookups in the hot loop.
## Geometry is written straight into packed arrays (no SurfaceTool), with per-vertex light in UV2
## and the texture-array layer in COLOR.a for the unshaded terrain shader.

const P: int = 18
const PA: int = 324
const PV: int = 5832

const RT_NONE: int = 0
const RT_CUBE: int = 1
const RT_CUBE_CUTOUT: int = 2
const RT_CROSS: int = 3
const RT_WATER: int = 4
const RT_BOX: int = 5
const RT_CROP: int = 6

## Directional face shading (TOP, BOTTOM, EAST, WEST, SOUTH, NORTH).
static var FACE_SHADE: PackedFloat32Array = PackedFloat32Array([1.0, 0.5, 0.6, 0.6, 0.8, 0.8])
## Padded-index step toward the neighbor on each face.
static var FACE_STEP: PackedInt32Array = PackedInt32Array([PA, -PA, 1, -1, P, -P])
## Brightness for 0..3 occluding neighbors at a vertex.
static var AO_CURVE: PackedFloat32Array = PackedFloat32Array([1.0, 0.8, 0.65, 0.5])

## Per face, per corner: vertex offset (x, y, z) and the two tangent neighbor steps used for AO.
static var CORNER_VX: PackedInt32Array
static var CORNER_VY: PackedInt32Array
static var CORNER_VZ: PackedInt32Array
static var CORNER_S1: PackedInt32Array
static var CORNER_S2: PackedInt32Array
static var _tables_ready: bool = _init_tables()

static var _air16: PackedByteArray
static var _sky16: PackedByteArray
static var _stone16: PackedByteArray
static var _dark16: PackedByteArray


static func _step(x: int, y: int, z: int) -> int:
	return x + z * P + y * PA


static func _init_tables() -> bool:
	# [face][corner] = [vx, vy, vz, s1 (x,y,z), s2 (x,y,z)]
	var defs: Array = [
		# TOP
		[[0, 1, 0, -1, 0, 0, 0, 0, -1], [1, 1, 0, 1, 0, 0, 0, 0, -1], [1, 1, 1, 1, 0, 0, 0, 0, 1], [0, 1, 1, -1, 0, 0, 0, 0, 1]],
		# BOTTOM
		[[0, 0, 1, -1, 0, 0, 0, 0, 1], [1, 0, 1, 1, 0, 0, 0, 0, 1], [1, 0, 0, 1, 0, 0, 0, 0, -1], [0, 0, 0, -1, 0, 0, 0, 0, -1]],
		# EAST
		[[1, 1, 1, 0, 1, 0, 0, 0, 1], [1, 1, 0, 0, 1, 0, 0, 0, -1], [1, 0, 0, 0, -1, 0, 0, 0, -1], [1, 0, 1, 0, -1, 0, 0, 0, 1]],
		# WEST
		[[0, 1, 0, 0, 1, 0, 0, 0, -1], [0, 1, 1, 0, 1, 0, 0, 0, 1], [0, 0, 1, 0, -1, 0, 0, 0, 1], [0, 0, 0, 0, -1, 0, 0, 0, -1]],
		# SOUTH
		[[0, 1, 1, -1, 0, 0, 0, 1, 0], [1, 1, 1, 1, 0, 0, 0, 1, 0], [1, 0, 1, 1, 0, 0, 0, -1, 0], [0, 0, 1, -1, 0, 0, 0, -1, 0]],
		# NORTH
		[[1, 1, 0, 1, 0, 0, 0, 1, 0], [0, 1, 0, -1, 0, 0, 0, 1, 0], [0, 0, 0, -1, 0, 0, 0, -1, 0], [1, 0, 0, 1, 0, 0, 0, -1, 0]],
	]
	CORNER_VX = PackedInt32Array()
	CORNER_VY = PackedInt32Array()
	CORNER_VZ = PackedInt32Array()
	CORNER_S1 = PackedInt32Array()
	CORNER_S2 = PackedInt32Array()
	for f in range(6):
		for c in range(4):
			var d: Array = defs[f][c]
			CORNER_VX.append(d[0])
			CORNER_VY.append(d[1])
			CORNER_VZ.append(d[2])
			CORNER_S1.append(_step(d[3], d[4], d[5]))
			CORNER_S2.append(_step(d[6], d[7], d[8]))

	_air16 = PackedByteArray()
	_air16.resize(16)
	_sky16 = PackedByteArray()
	_sky16.resize(16)
	_sky16.fill(0xF0)
	_stone16 = PackedByteArray()
	_stone16.resize(16)
	_stone16.fill(BlockRegistry.BlockId.STONE)
	_dark16 = PackedByteArray()
	_dark16.resize(16)
	return true


## Growable vertex buffers for one mesh surface.
class Surf:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	func is_empty() -> bool:
		return indices.is_empty()

	func to_arrays(with_normals: bool) -> Array:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		if with_normals:
			arr[Mesh.ARRAY_NORMAL] = normals
		else:
			arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
		arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_INDEX] = indices
		return arr


# ============================================================================
# PADDED VOLUME
# ============================================================================

## Builds the 18x18x18 padded voxel + light volume around sub-chunk `sub_idx`.
## `vox` / `light` hold 9 PackedByteArrays indexed `(dz + 1) * 3 + (dx + 1)` (index 4 = this chunk);
## an empty array means that neighbor is not loaded (treated as open, sky-lit air). The arrays may be
## y-slices that start at layer `y_origin` instead of whole 256-layer chunk buffers.
static func build_padded(sub_idx: int, vox: Array, light: Array, y_origin: int = 0) -> Array:
	var pv := PackedByteArray()
	var pl := PackedByteArray()
	var y0: int = sub_idx * 16 - 1
	for py in range(P):
		var wy: int = y0 + py
		for pz in range(P):
			var lz: int = pz - 1
			var cz: int = 0 if lz < 0 else (2 if lz > 15 else 1)
			var zz: int = lz & 15
			if wy < 0:
				pv.append(BlockRegistry.BlockId.STONE)
				pv.append_array(_stone16)
				pv.append(BlockRegistry.BlockId.STONE)
				pl.append(0)
				pl.append_array(_dark16)
				pl.append(0)
				continue
			if wy > 255:
				pv.append(0)
				pv.append_array(_air16)
				pv.append(0)
				pl.append(0xF0)
				pl.append_array(_sky16)
				pl.append(0xF0)
				continue
			var row: int = ((wy - y_origin) << 8) | (zz << 4)
			var west_v: PackedByteArray = vox[cz * 3]
			var mid_v: PackedByteArray = vox[cz * 3 + 1]
			var east_v: PackedByteArray = vox[cz * 3 + 2]
			var west_l: PackedByteArray = light[cz * 3]
			var mid_l: PackedByteArray = light[cz * 3 + 1]
			var east_l: PackedByteArray = light[cz * 3 + 2]

			pv.append(west_v[row | 15] if not west_v.is_empty() else 0)
			pl.append(west_l[row | 15] if not west_l.is_empty() else 0xF0)
			if not mid_v.is_empty():
				pv.append_array(mid_v.slice(row, row + 16))
			else:
				pv.append_array(_air16)
			if not mid_l.is_empty():
				pl.append_array(mid_l.slice(row, row + 16))
			else:
				pl.append_array(_sky16)
			pv.append(east_v[row] if not east_v.is_empty() else 0)
			pl.append(east_l[row] if not east_l.is_empty() else 0xF0)
	return [pv, pl]


## Reads the 4-bit metadata nibble for a chunk-local flat index.
static func _meta_at(meta: PackedByteArray, idx: int) -> int:
	var byte_idx: int = idx >> 1
	if byte_idx >= meta.size():
		return 0
	var b: int = meta[byte_idx]
	return (b & 0x0F) if ((idx & 1) == 0) else ((b >> 4) & 0x0F)


# ============================================================================
# SUB-CHUNK MESH
# ============================================================================

## Per-block flags used in the hot loop (bit 0 = solid/has collision, bit 1 = log, bit 2 = needs metadata).
static var _flags: PackedByteArray = _init_flags()


static func _init_flags() -> PackedByteArray:
	var arr := PackedByteArray()
	arr.resize(256)
	for id in range(256):
		var f: int = 0
		if BlockRegistry.is_solid(id):
			f |= 1
		if BlockRegistry.is_log(id):
			f |= 2
		match id:
			BlockRegistry.BlockId.WOOD_LOG, BlockRegistry.BlockId.PINE_LOG, BlockRegistry.BlockId.BIRCH_LOG, BlockRegistry.BlockId.WOOL, BlockRegistry.BlockId.SLAB, BlockRegistry.BlockId.WOOD_STAIRS, BlockRegistry.BlockId.COBBLE_STAIRS, BlockRegistry.BlockId.DOOR_CLOSED, BlockRegistry.BlockId.DOOR_OPEN, BlockRegistry.BlockId.WHEAT_SPROUT, BlockRegistry.BlockId.POTATO_SPROUT, BlockRegistry.BlockId.TORCH, BlockRegistry.BlockId.REDSTONE_TORCH:
				f |= 4
		arr[id] = f
	return arr


## Builds the terrain mesh (opaque + cutout surfaces), water mesh and collision shape for one
## 16x16x16 sub-chunk. Safe to call from WorkerThreadPool threads.
static func build_sub_chunk(sub_idx: int, padded: Array, meta: PackedByteArray, water_only: bool = false) -> Dictionary:
	var pv: PackedByteArray = padded[0]
	var pl: PackedByteArray = padded[1]
	var rt_table: PackedByteArray = BlockRegistry.render_type_table
	var occ: PackedByteArray = BlockRegistry.occluder_table
	var tiles: PackedByteArray = BlockRegistry.tile_table
	var flags: PackedByteArray = _flags
	var has_meta: bool = not meta.is_empty()

	var opaque := Surf.new()
	var cutout := Surf.new()
	var water := Surf.new()
	var col := PackedVector3Array()

	var y_base: int = sub_idx * 16

	for y in range(1, 17):
		var ly: int = y_base + y - 1
		for z in range(1, 17):
			var row: int = y * PA + z * P
			for x in range(1, 17):
				var p: int = row + x
				var id: int = pv[p]
				if id == 0:
					continue
				var rt: int = rt_table[id]

				if rt == RT_CUBE:
					# Most solid blocks are buried: reject them with six table lookups.
					if occ[pv[p + PA]] == 1 and occ[pv[p - PA]] == 1 and occ[pv[p + 1]] == 1 and occ[pv[p - 1]] == 1 and occ[pv[p + P]] == 1 and occ[pv[p - P]] == 1:
						continue
				elif rt == RT_NONE:
					continue

				if rt == RT_WATER or id == BlockRegistry.BlockId.SEAGRASS:
					_emit_water(water, pv, pl, p, x - 1, ly, z - 1, id)
					if rt == RT_WATER:
						continue
				if water_only:
					continue

				var fl: int = flags[id]
				var meta_v: int = 0
				if has_meta and (fl & 4) != 0:
					meta_v = _meta_at(meta, (ly << 8) | ((z - 1) << 4) | (x - 1))

				if rt == RT_CUBE or rt == RT_CUBE_CUTOUT:
					if id == BlockRegistry.BlockId.LAVA:
						_emit_lava(cutout, pv, pl, occ, tiles, p, x - 1, ly, z - 1, id)
						continue
					var surf: Surf = opaque if rt == RT_CUBE else cutout
					var solid: bool = (fl & 1) != 0
					var is_log: bool = (fl & 2) != 0
					var tint := Color.WHITE
					if id == BlockRegistry.BlockId.WOOL and meta_v > 0:
						tint = BlockRegistry.WOOL_COLORS[meta_v]
					var tile_base: int = (id << 7) | (meta_v << 3)
					for f in range(6):
						var nb: int = pv[p + FACE_STEP[f]]
						if occ[nb] == 1:
							continue
						if rt == RT_CUBE_CUTOUT and nb == id:
							continue
						var rot: int = _log_uv_rotation(meta_v & 3, f) if is_log else 0
						_emit_cube_face(surf, pv, pl, occ, p, x - 1, ly, z - 1, f, BlockRegistry.resolve_tile(tiles[tile_base | f]), rot, tint)
						if solid:
							_emit_col_face(col, x - 1, ly, z - 1, f)
				elif rt == RT_CROSS:
					var tile_c: int = BlockRegistry.resolve_tile(tiles[(id << 7) | (meta_v << 3) | BlockRegistry.FaceDir.NORTH])
					_emit_cross(cutout, x - 1, ly, z - 1, tile_c, pl[p])
				elif rt == RT_CROP:
					var tile_k: int = BlockRegistry.resolve_tile(tiles[(id << 7) | (meta_v << 3) | BlockRegistry.FaceDir.NORTH])
					_emit_crop(cutout, x - 1, ly, z - 1, tile_k, pl[p])
				elif rt == RT_BOX:
					# Doors use the alpha-tested surface so their window panes are see-through.
					_emit_block_boxes(cutout if BlockRegistry.is_door(id) else opaque, col, pv, pl, occ, tiles, p, x - 1, ly, z - 1, id, meta_v)

	var result: Dictionary = {"mesh": null, "water_mesh": null, "shape": null}
	if not water_only:
		if not opaque.is_empty() or not cutout.is_empty():
			var mesh := ArrayMesh.new()
			if not opaque.is_empty():
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, opaque.to_arrays(false))
				mesh.surface_set_material(mesh.get_surface_count() - 1, VoxelAtlasBuilder.get_terrain_material(false))
			if not cutout.is_empty():
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cutout.to_arrays(false))
				mesh.surface_set_material(mesh.get_surface_count() - 1, VoxelAtlasBuilder.get_terrain_material(true))
			result["mesh"] = mesh
		if not col.is_empty():
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(col)
			result["shape"] = shape
	if not water.is_empty():
		var wmesh := ArrayMesh.new()
		wmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, water.to_arrays(true))
		result["water_mesh"] = wmesh
	return result


## Bark grain follows the log's axis: rotate the side texture a quarter turn on faces where the
## log runs horizontally across them.
static func _log_uv_rotation(axis: int, face: int) -> int:
	if axis == 1:
		return 1 if (face == 0 or face == 1 or face == 4 or face == 5) else 0
	if axis == 2:
		return 1 if (face == 2 or face == 3) else 0
	return 0


static var _UV_CORNERS: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)])


static func _emit_cube_face(
	s: Surf, pv: PackedByteArray, pl: PackedByteArray, occ: PackedByteArray,
	p: int, lx: int, ly: int, lz: int, f: int, tile: int, rot: int, tint: Color
) -> void:
	var verts: PackedVector3Array = s.verts
	var uvs: PackedVector2Array = s.uvs
	var uv2s: PackedVector2Array = s.uv2s
	var colors: PackedColorArray = s.colors
	var a: int = p + FACE_STEP[f]
	var la: int = pl[a]
	var base_sky: int = la >> 4
	var base_blk: int = la & 15
	var shade: float = FACE_SHADE[f]
	var layer: float = float(tile) / 255.0
	var start: int = verts.size()
	var b0: float = 0.0
	var b1: float = 0.0
	var b2: float = 0.0
	var b3: float = 0.0

	for c in range(4):
		var ci: int = f * 4 + c
		var s1: int = a + CORNER_S1[ci]
		var s2: int = a + CORNER_S2[ci]
		var sc: int = s1 + CORNER_S2[ci]
		var o1: int = occ[pv[s1]]
		var o2: int = occ[pv[s2]]
		var sky: int = base_sky
		var blk: int = base_blk
		var n: int = 1
		if o1 == 0:
			var l1: int = pl[s1]
			sky += l1 >> 4
			blk += l1 & 15
			n += 1
		if o2 == 0:
			var l2: int = pl[s2]
			sky += l2 >> 4
			blk += l2 & 15
			n += 1
		var ao_count: int = 3
		if o1 == 0 or o2 == 0:
			var oc: int = occ[pv[sc]]
			ao_count = o1 + o2 + oc
			if oc == 0:
				var l3: int = pl[sc]
				sky += l3 >> 4
				blk += l3 & 15
				n += 1
		var ao: float = AO_CURVE[ao_count] * shade
		var inv_n: float = 1.0 / (15.0 * float(n))
		var fs: float = float(sky) * inv_n
		var fb: float = float(blk) * inv_n
		var bright: float = ao * maxf(fs, fb)
		match c:
			0:
				b0 = bright
			1:
				b1 = bright
			2:
				b2 = bright
			_:
				b3 = bright
		verts.append(Vector3(lx + CORNER_VX[ci], ly + CORNER_VY[ci], lz + CORNER_VZ[ci]))
		colors.append(Color(tint.r * ao, tint.g * ao, tint.b * ao, layer))
		uv2s.append(Vector2(fs, fb))
		uvs.append(_UV_CORNERS[(c + rot) & 3])

	# Flip the quad diagonal so AO gradients interpolate without the classic anisotropy seam.
	var indices: PackedInt32Array = s.indices
	if b0 + b2 < b1 + b3:
		indices.append(start + 1)
		indices.append(start + 2)
		indices.append(start + 3)
		indices.append(start + 1)
		indices.append(start + 3)
		indices.append(start)
	else:
		indices.append(start)
		indices.append(start + 1)
		indices.append(start + 2)
		indices.append(start)
		indices.append(start + 2)
		indices.append(start + 3)


static func _emit_col_face(col: PackedVector3Array, lx: int, ly: int, lz: int, f: int) -> void:
	var b: int = f * 4
	var v0 := Vector3(lx + CORNER_VX[b], ly + CORNER_VY[b], lz + CORNER_VZ[b])
	var v2 := Vector3(lx + CORNER_VX[b + 2], ly + CORNER_VY[b + 2], lz + CORNER_VZ[b + 2])
	col.append(v0)
	col.append(Vector3(lx + CORNER_VX[b + 1], ly + CORNER_VY[b + 1], lz + CORNER_VZ[b + 1]))
	col.append(v2)
	col.append(v0)
	col.append(v2)
	col.append(Vector3(lx + CORNER_VX[b + 3], ly + CORNER_VY[b + 3], lz + CORNER_VZ[b + 3]))


static func _push_quad(
	s: Surf, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3,
	uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2,
	color: Color, light: Vector2
) -> void:
	var verts: PackedVector3Array = s.verts
	var uvs: PackedVector2Array = s.uvs
	var uv2s: PackedVector2Array = s.uv2s
	var colors: PackedColorArray = s.colors
	var indices: PackedInt32Array = s.indices
	var start: int = verts.size()
	verts.append(v0)
	verts.append(v1)
	verts.append(v2)
	verts.append(v3)
	uvs.append(uv0)
	uvs.append(uv1)
	uvs.append(uv2)
	uvs.append(uv3)
	for i in range(4):
		uv2s.append(light)
		colors.append(color)
	indices.append(start)
	indices.append(start + 1)
	indices.append(start + 2)
	indices.append(start)
	indices.append(start + 2)
	indices.append(start + 3)


static func _light_vec(packed: int) -> Vector2:
	return Vector2(float(packed >> 4) / 15.0, float(packed & 15) / 15.0)


static func _emit_cross(s: Surf, lx: int, ly: int, lz: int, tile: int, light_packed: int) -> void:
	var o := Vector3(lx, ly, lz)
	var c := Color(1.0, 1.0, 1.0, float(tile) / 255.0)
	var l: Vector2 = _light_vec(light_packed)
	var a0 := o + Vector3(0.0, 1.0, 0.0)
	var a1 := o + Vector3(1.0, 1.0, 1.0)
	var a2 := o + Vector3(1.0, 0.0, 1.0)
	var a3 := o + Vector3(0.0, 0.0, 0.0)
	var b0 := o + Vector3(0.0, 1.0, 1.0)
	var b1 := o + Vector3(1.0, 1.0, 0.0)
	var b2 := o + Vector3(1.0, 0.0, 0.0)
	var b3 := o + Vector3(0.0, 0.0, 1.0)
	var t0 := Vector2(0.0, 0.0)
	var t1 := Vector2(1.0, 0.0)
	var t2 := Vector2(1.0, 1.0)
	var t3 := Vector2(0.0, 1.0)
	_push_quad(s, a0, a1, a2, a3, t0, t1, t2, t3, c, l)
	_push_quad(s, a1, a0, a3, a2, t1, t0, t3, t2, c, l)
	_push_quad(s, b0, b1, b2, b3, t0, t1, t2, t3, c, l)
	_push_quad(s, b1, b0, b3, b2, t1, t0, t3, t2, c, l)


static func _emit_crop(s: Surf, lx: int, ly: int, lz: int, tile: int, light_packed: int) -> void:
	var o := Vector3(lx, ly, lz)
	var c := Color(1.0, 1.0, 1.0, float(tile) / 255.0)
	var l: Vector2 = _light_vec(light_packed)
	var t0 := Vector2(0.0, 0.0)
	var t1 := Vector2(1.0, 0.0)
	var t2 := Vector2(1.0, 1.0)
	var t3 := Vector2(0.0, 1.0)
	const Y0: float = -0.0625
	const Y1: float = 0.9375
	for k in [0.25, 0.75]:
		var px: float = k
		var x0 := o + Vector3(px, Y1, 0.0)
		var x1 := o + Vector3(px, Y1, 1.0)
		var x2 := o + Vector3(px, Y0, 1.0)
		var x3 := o + Vector3(px, Y0, 0.0)
		_push_quad(s, x0, x1, x2, x3, t0, t1, t2, t3, c, l)
		_push_quad(s, x1, x0, x3, x2, t1, t0, t3, t2, c, l)
		var z0 := o + Vector3(0.0, Y1, px)
		var z1 := o + Vector3(1.0, Y1, px)
		var z2 := o + Vector3(1.0, Y0, px)
		var z3 := o + Vector3(0.0, Y0, px)
		_push_quad(s, z1, z0, z3, z2, t1, t0, t3, t2, c, l)
		_push_quad(s, z0, z1, z2, z3, t0, t1, t2, t3, c, l)


static func _emit_block_boxes(
	s: Surf, col: PackedVector3Array, pv: PackedByteArray, pl: PackedByteArray, occ: PackedByteArray,
	tiles: PackedByteArray, p: int, lx: int, ly: int, lz: int, id: int, meta_v: int
) -> void:
	var boxes: Array[AABB] = BlockRegistry.get_shape_boxes(id, meta_v)
	var solid: bool = BlockRegistry.is_solid(id)
	var is_door: bool = BlockRegistry.is_door(id)
	var door_upper: bool = is_door and BlockRegistry.is_door(pv[p - PA])
	var flip_u: bool = is_door and (meta_v & 4) != 0
	var full_tile_uv: bool = (
		id == BlockRegistry.BlockId.TORCH
		or id == BlockRegistry.BlockId.REDSTONE_TORCH
		or id == BlockRegistry.BlockId.LEVER
		or id == BlockRegistry.BlockId.BUTTON
	)
	var tint := Color.WHITE
	var o := Vector3(lx, ly, lz)
	var own_light: int = pl[p]

	for box in boxes:
		var b0: Vector3 = box.position
		var b1: Vector3 = box.end
		for f in range(6):
			# Faces flush with the block boundary use the neighbor's light (and are hidden by occluders).
			var on_edge: bool = false
			match f:
				0:
					on_edge = b1.y >= 0.999
				1:
					on_edge = b0.y <= 0.001
				2:
					on_edge = b1.x >= 0.999
				3:
					on_edge = b0.x <= 0.001
				4:
					on_edge = b1.z >= 0.999
				_:
					on_edge = b0.z <= 0.001
			var light_packed: int = own_light
			if on_edge:
				var nb_p: int = p + FACE_STEP[f]
				if occ[pv[nb_p]] == 1:
					continue
				if is_door and f <= 1 and BlockRegistry.is_door(pv[nb_p]):
					continue
				if occ[pv[nb_p]] == 0:
					light_packed = pl[nb_p]
			var tile: int = BlockRegistry.resolve_tile(tiles[(id << 7) | (meta_v << 3) | f])
			if door_upper:
				tile = BlockRegistry.resolve_tile(BlockRegistry.TILE_DOOR_TOP)
			var shade: float = FACE_SHADE[f]
			var color := Color(tint.r * shade, tint.g * shade, tint.b * shade, float(tile) / 255.0)
			var l: Vector2 = _light_vec(light_packed)

			var v0: Vector3
			var v1: Vector3
			var v2: Vector3
			var v3: Vector3
			# Texture coordinates follow the box position inside the block (like the classic models).
			var u_a: float
			var u_b: float
			var v_a: float
			var v_b: float
			match f:
				0:
					v0 = Vector3(b0.x, b1.y, b0.z); v1 = Vector3(b1.x, b1.y, b0.z); v2 = Vector3(b1.x, b1.y, b1.z); v3 = Vector3(b0.x, b1.y, b1.z)
					u_a = b0.x; u_b = b1.x; v_a = b0.z; v_b = b1.z
				1:
					v0 = Vector3(b0.x, b0.y, b1.z); v1 = Vector3(b1.x, b0.y, b1.z); v2 = Vector3(b1.x, b0.y, b0.z); v3 = Vector3(b0.x, b0.y, b0.z)
					u_a = b0.x; u_b = b1.x; v_a = 1.0 - b1.z; v_b = 1.0 - b0.z
				2:
					v0 = Vector3(b1.x, b1.y, b1.z); v1 = Vector3(b1.x, b1.y, b0.z); v2 = Vector3(b1.x, b0.y, b0.z); v3 = Vector3(b1.x, b0.y, b1.z)
					u_a = 1.0 - b1.z; u_b = 1.0 - b0.z; v_a = 1.0 - b1.y; v_b = 1.0 - b0.y
				3:
					v0 = Vector3(b0.x, b1.y, b0.z); v1 = Vector3(b0.x, b1.y, b1.z); v2 = Vector3(b0.x, b0.y, b1.z); v3 = Vector3(b0.x, b0.y, b0.z)
					u_a = b0.z; u_b = b1.z; v_a = 1.0 - b1.y; v_b = 1.0 - b0.y
				4:
					v0 = Vector3(b0.x, b1.y, b1.z); v1 = Vector3(b1.x, b1.y, b1.z); v2 = Vector3(b1.x, b0.y, b1.z); v3 = Vector3(b0.x, b0.y, b1.z)
					u_a = b0.x; u_b = b1.x; v_a = 1.0 - b1.y; v_b = 1.0 - b0.y
				_:
					v0 = Vector3(b1.x, b1.y, b0.z); v1 = Vector3(b0.x, b1.y, b0.z); v2 = Vector3(b0.x, b0.y, b0.z); v3 = Vector3(b1.x, b0.y, b0.z)
					u_a = 1.0 - b1.x; u_b = 1.0 - b0.x; v_a = 1.0 - b1.y; v_b = 1.0 - b0.y
			if full_tile_uv:
				u_a = 0.0; u_b = 1.0; v_a = 0.0; v_b = 1.0
			if flip_u:
				var tmp: float = u_a
				u_a = u_b
				u_b = tmp
			_push_quad(
				s, o + v0, o + v1, o + v2, o + v3,
				Vector2(u_a, v_a), Vector2(u_b, v_a), Vector2(u_b, v_b), Vector2(u_a, v_b),
				color, l
			)
			if solid:
				col.append_array(PackedVector3Array([o + v0, o + v1, o + v2, o + v0, o + v2, o + v3]))


static func _emit_lava(s: Surf, pv: PackedByteArray, pl: PackedByteArray, occ: PackedByteArray, tiles: PackedByteArray, p: int, lx: int, ly: int, lz: int, id: int) -> void:
	var h: float = 1.0 if pv[p + PA] == BlockRegistry.BlockId.LAVA else 0.875
	var o := Vector3(lx, ly, lz)
	var tile: int = BlockRegistry.resolve_tile(tiles[(id << 7) | BlockRegistry.FaceDir.TOP])
	var layer: float = float(tile) / 255.0
	var own_l: Vector2 = _light_vec(pl[p])

	# Top face
	if pv[p + PA] != BlockRegistry.BlockId.LAVA:
		var c := Color(1.0, 1.0, 1.0, layer)
		_push_quad(s, o + Vector3(0, h, 0), o + Vector3(1, h, 0), o + Vector3(1, h, 1), o + Vector3(0, h, 1),
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), c, own_l)

	# Bottom face
	var nb_bot: int = pv[p - PA]
	if nb_bot != BlockRegistry.BlockId.LAVA and occ[nb_bot] == 0:
		var shade: float = FACE_SHADE[BlockRegistry.FaceDir.BOTTOM]
		var c := Color(shade, shade, shade, layer)
		_push_quad(s, o + Vector3(0, 0, 1), o + Vector3(1, 0, 1), o + Vector3(1, 0, 0), o + Vector3(0, 0, 0),
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), c, own_l)

	# East (+X)
	var nb_e: int = pv[p + 1]
	if nb_e != BlockRegistry.BlockId.LAVA and occ[nb_e] == 0:
		var shade: float = FACE_SHADE[BlockRegistry.FaceDir.EAST]
		var c := Color(shade, shade, shade, layer)
		_push_quad(s, o + Vector3(1, h, 1), o + Vector3(1, h, 0), o + Vector3(1, 0, 0), o + Vector3(1, 0, 1),
			Vector2(0, 1.0 - h), Vector2(1, 1.0 - h), Vector2(1, 1), Vector2(0, 1), c, own_l)

	# West (-X)
	var nb_w: int = pv[p - 1]
	if nb_w != BlockRegistry.BlockId.LAVA and occ[nb_w] == 0:
		var shade: float = FACE_SHADE[BlockRegistry.FaceDir.WEST]
		var c := Color(shade, shade, shade, layer)
		_push_quad(s, o + Vector3(0, h, 0), o + Vector3(0, h, 1), o + Vector3(0, 0, 1), o + Vector3(0, 0, 0),
			Vector2(0, 1.0 - h), Vector2(1, 1.0 - h), Vector2(1, 1), Vector2(0, 1), c, own_l)

	# South (+Z)
	var nb_s: int = pv[p + P]
	if nb_s != BlockRegistry.BlockId.LAVA and occ[nb_s] == 0:
		var shade: float = FACE_SHADE[BlockRegistry.FaceDir.SOUTH]
		var c := Color(shade, shade, shade, layer)
		_push_quad(s, o + Vector3(0, h, 1), o + Vector3(1, h, 1), o + Vector3(1, 0, 1), o + Vector3(0, 0, 1),
			Vector2(0, 1.0 - h), Vector2(1, 1.0 - h), Vector2(1, 1), Vector2(0, 1), c, own_l)

	# North (-Z)
	var nb_n: int = pv[p - P]
	if nb_n != BlockRegistry.BlockId.LAVA and occ[nb_n] == 0:
		var shade: float = FACE_SHADE[BlockRegistry.FaceDir.NORTH]
		var c := Color(shade, shade, shade, layer)
		_push_quad(s, o + Vector3(1, h, 0), o + Vector3(0, h, 0), o + Vector3(0, 0, 0), o + Vector3(1, 0, 0),
			Vector2(0, 1.0 - h), Vector2(1, 1.0 - h), Vector2(1, 1), Vector2(0, 1), c, own_l)


# ============================================================================
# WATER
# ============================================================================

static func _is_wet(id: int) -> bool:
	return BlockRegistry.is_water(id) or id == BlockRegistry.BlockId.SEAGRASS


static func _water_height(id: int) -> float:
	if id == BlockRegistry.BlockId.SEAGRASS:
		return BlockRegistry.get_water_height_ratio(BlockRegistry.BlockId.WATER)
	return BlockRegistry.get_water_height_ratio(id)


## Smoothed surface height at the corner shared by the 4 columns around padded index `p` in quadrant (dx, dz).
static func _water_corner(pv: PackedByteArray, p: int, dx: int, dz: int) -> float:
	var sum_h: float = 0.0
	var max_h: float = 0.0
	var count: int = 0
	var has_air: bool = false
	for ox in [0, dx]:
		for oz in [0, dz]:
			var q: int = p + ox + oz * P
			if BlockRegistry.is_liquid(pv[q + PA]) or pv[q + PA] == BlockRegistry.BlockId.SEAGRASS:
				return 1.0
			var nid: int = pv[q]
			if _is_wet(nid):
				var h: float = _water_height(nid)
				sum_h += h
				max_h = maxf(max_h, h)
				count += 1
			elif nid == BlockRegistry.BlockId.AIR:
				has_air = true
	if count == 0:
		return 0.12
	var avg_h: float = sum_h / float(count)
	var edge_drop: float = -0.04 if (has_air and max_h < 0.87) else 0.0
	return clampf(avg_h * 0.72 + max_h * 0.28 + edge_drop, 0.07, 0.96)


static func _emit_water(s: Surf, pv: PackedByteArray, pl: PackedByteArray, p: int, lx: int, ly: int, lz: int, id: int) -> void:
	var occ: PackedByteArray = BlockRegistry.occluder_table
	var nb_top: int = pv[p + PA]
	var has_top: bool = not _is_wet(nb_top)
	var nb_bot: int = pv[p - PA]
	var has_bot: bool = not _is_wet(nb_bot) and occ[nb_bot] == 0
	var nb_e: int = pv[p + 1]
	var has_e: bool = not _is_wet(nb_e) and occ[nb_e] == 0
	var nb_w: int = pv[p - 1]
	var has_w: bool = not _is_wet(nb_w) and occ[nb_w] == 0
	var nb_s: int = pv[p + P]
	var has_s: bool = not _is_wet(nb_s) and occ[nb_s] == 0
	var nb_n: int = pv[p - P]
	var has_n: bool = not _is_wet(nb_n) and occ[nb_n] == 0
	if not (has_top or has_bot or has_e or has_w or has_s or has_n):
		return

	var h00: float = _water_corner(pv, p, -1, -1)
	var h10: float = _water_corner(pv, p, 1, -1)
	var h11: float = _water_corner(pv, p, 1, 1)
	var h01: float = _water_corner(pv, p, -1, 1)
	var o := Vector3(lx, ly, lz)
	var l: Vector2 = _light_vec(pl[p])

	if has_top:
		var t0 := o + Vector3(0.0, h00, 0.0)
		var t1 := o + Vector3(1.0, h10, 0.0)
		var t2 := o + Vector3(1.0, h11, 1.0)
		var t3 := o + Vector3(0.0, h01, 1.0)
		var n: Vector3 = (t3 - t0).cross(t1 - t0).normalized()
		if n.length_squared() < 0.01:
			n = Vector3.UP
		_push_water_quad(s, t0, t1, t2, t3, n, 1.0, l)
	if has_bot:
		_push_water_quad(s, o + Vector3(0, 0, 1), o + Vector3(1, 0, 1), o + Vector3(1, 0, 0), o + Vector3(0, 0, 0), Vector3.DOWN, 0.65, l)
	if has_e:
		_push_water_quad(s, o + Vector3(1, h11, 1), o + Vector3(1, h10, 0), o + Vector3(1, 0, 0), o + Vector3(1, 0, 1), Vector3.RIGHT, 0.85, l)
	if has_w:
		_push_water_quad(s, o + Vector3(0, h00, 0), o + Vector3(0, h01, 1), o + Vector3(0, 0, 1), o + Vector3(0, 0, 0), Vector3.LEFT, 0.80, l)
	if has_s:
		_push_water_quad(s, o + Vector3(0, h01, 1), o + Vector3(1, h11, 1), o + Vector3(1, 0, 1), o + Vector3(0, 0, 1), Vector3.BACK, 0.90, l)
	if has_n:
		_push_water_quad(s, o + Vector3(1, h10, 0), o + Vector3(0, h00, 0), o + Vector3(0, 0, 0), o + Vector3(1, 0, 0), Vector3.FORWARD, 0.78, l)


static func _push_water_quad(s: Surf, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, n: Vector3, shade: float, l: Vector2) -> void:
	var start: int = s.verts.size()
	var c := Color(shade, shade, shade, 1.0)
	s.verts.append_array(PackedVector3Array([v0, v1, v2, v3]))
	s.normals.append_array(PackedVector3Array([n, n, n, n]))
	s.uv2s.append_array(PackedVector2Array([l, l, l, l]))
	s.colors.append_array(PackedColorArray([c, c, c, c]))
	s.indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
