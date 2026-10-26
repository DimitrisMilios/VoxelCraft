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

enum Biome {
	PLAINS = 0,
	FOREST = 1,
	DESERT = 2,
	SNOWY_TAIGA = 3,
}

## Coordinate of this chunk in chunk-grid space (e.g., Vector2i(0, 0), Vector2i(1, -2)).
var chunk_coords: Vector2i = Vector2i.ZERO

## True if the player has broken or placed at least one block in this chunk.
var is_dirty: bool = false

## World positions of any Loot Chests generated in this chunk's structures.
var generated_loot_chests: Array[Vector3i] = []

## World positions of any Villagers to spawn when this chunk is added to tree.
var generated_villager_spawns: Array[Vector3] = []

## Optional thread-safe callback `(world_pos: Vector3i) -> int` provided by WorldManager
## for seamless cross-chunk border face culling.
var neighbor_block_getter: Callable = Callable()

## Contiguous 1D byte buffer of size 16 * 256 * 16 (65,536 bytes).
var _voxels: PackedByteArray = PackedByteArray()
var _highest_solid_y: int = 0

var _sub_solid_meshes: Array[MeshInstance3D] = []
var _sub_water_meshes: Array[MeshInstance3D] = []
var _sub_colliders: Array[CollisionShape3D] = []
var _block_lights: Dictionary = {} # Vector3i(lx, ly, lz) -> OmniLight3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_ensure_child_nodes()


func _ensure_child_nodes() -> void:
	if not _sub_solid_meshes.is_empty():
		return

	var solid_mat: StandardMaterial3D = VoxelAtlasBuilder.get_shared_voxel_material()
	var water_mat: Material = VoxelAtlasBuilder.get_shared_water_material()

	for sub_idx in range(SUB_CHUNK_COUNT):
		var solid_mi := MeshInstance3D.new()
		solid_mi.name = "SubMesh_%d" % sub_idx
		solid_mi.material_override = solid_mat
		solid_mi.visible = false
		add_child(solid_mi)
		_sub_solid_meshes.append(solid_mi)

		var water_mi := MeshInstance3D.new()
		water_mi.name = "SubWater_%d" % sub_idx
		water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		water_mi.material_override = water_mat
		water_mi.visible = false
		add_child(water_mi)
		_sub_water_meshes.append(water_mi)

		var col := CollisionShape3D.new()
		col.name = "SubCol_%d" % sub_idx
		col.disabled = true
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

			# Deterministic tree, cactus, boulder, or mountain waterfall spring placement
			if surface_y > WATER_LEVEL + 1 and lx >= 3 and lx <= CHUNK_SIZE_X - 4 and lz >= 3 and lz <= CHUNK_SIZE_Z - 4:
				var surface_id: int = get_block_local(lx, surface_y, lz)
				var biome: int = sample_biome(wx, wz)
				if biome == Biome.DESERT and surface_id == BlockRegistry.BlockId.SAND:
					if _should_spawn_tree(wx, wz, biome):
						_place_cactus(lx, surface_y + 1, lz)
				elif _should_spawn_tree(wx, wz, biome) and (surface_id == BlockRegistry.BlockId.GRASS or surface_id == BlockRegistry.BlockId.SNOW):
					if biome == Biome.SNOWY_TAIGA or surface_y >= SEA_LEVEL + 10:
						_place_pine_tree(lx, surface_y + 1, lz)
					else:
						_place_tree(lx, surface_y + 1, lz)
				elif (biome == Biome.FOREST or biome == Biome.SNOWY_TAIGA) and _should_spawn_boulder(wx, wz) and surface_id != BlockRegistry.BlockId.AIR:
					_place_mossy_boulder(lx, surface_y, lz)

			# Shoreline Sugar Cane reeds along water banks (matching realistic lake shores)
			if (surface_y == WATER_LEVEL or surface_y == WATER_LEVEL + 1) and (surface_y + 3 < CHUNK_SIZE_Y):
				var surf_id: int = get_block_local(lx, surface_y, lz)
				if surf_id == BlockRegistry.BlockId.SAND or surf_id == BlockRegistry.BlockId.GRASS or surf_id == BlockRegistry.BlockId.DIRT:
					var cane_hash: int = absi((wx * 374761393) ^ (wz * 668265263)) % 100
					if cane_hash < 24:
						var cane_height: int = 3 if (cane_hash % 2 == 0) else 2
						for ch in range(1, cane_height + 1):
							_set_voxel_raw(lx, surface_y + ch, lz, BlockRegistry.BlockId.SUGAR_CANE)
						if surface_y + cane_height > _highest_solid_y:
							_highest_solid_y = surface_y + cane_height

			# Underwater Seagrass on shallow lake beds
			elif surface_y < WATER_LEVEL and surface_y >= WATER_LEVEL - 3 and (surface_y + 1 < CHUNK_SIZE_Y):
				var sea_hash: int = absi((wx * 15485863) ^ (wz * 32452843)) % 100
				if sea_hash < 32:
					_set_voxel_raw(lx, surface_y + 1, lz, BlockRegistry.BlockId.SEAGRASS)

	_generate_chunk_structures(surface_noise)


## Deterministic 2D climate biome sampler (Plains, Forest, Desert, Snowy Taiga).
static func sample_biome(wx: int, wz: int) -> int:
	var fx: float = float(wx)
	var fz: float = float(wz)
	var warp_x: float = fx + sin(fz * 0.012) * 24.0
	var warp_z: float = fz + cos(fx * 0.012) * 24.0
	var temp: float = sin(warp_x * 0.0065 + cos(warp_z * 0.0052) * 1.3) + cos(warp_z * 0.0060)
	var humid: float = cos(warp_x * 0.0058 - warp_z * 0.0068) + sin(warp_x * 0.011) * 0.35
	if temp > 0.72:
		return Biome.DESERT
	if temp < -0.70:
		return Biome.SNOWY_TAIGA
	if humid > 0.18:
		return Biome.FOREST
	return Biome.PLAINS


## Multi-Scale Continental + Ridged Mountain + Winding River Valley Heightmap.
## Shared with WorldManager for cross-chunk border culling.
static func sample_surface_height(surface_noise: FastNoiseLite, wx: int, wz: int) -> int:
	var fx: float = float(wx)
	var fz: float = float(wz)

	# 1. Continentalness (Low-frequency landmass vs ocean/lake basins: -1..+1)
	var continent: float = surface_noise.get_noise_2d(fx * 0.24, fz * 0.24)
	# 2. Medium hills & rolling terrain
	var hills: float = surface_noise.get_noise_2d(fx * 0.85 + 310.0, fz * 0.85 - 210.0)
	# 3. Fine surface detail
	var detail: float = surface_noise.get_noise_2d(fx * 2.2 - 710.0, fz * 2.2 + 540.0)

	# 4. Ridged Multifractal Mountain Ranges & Jagged Alpine Peaks
	var m_mask_raw: float = surface_noise.get_noise_2d(fx * 0.28 - 1400.0, fz * 0.28 + 1400.0)
	var mountain_mask: float = clampf((m_mask_raw + 0.12) * 1.45, 0.0, 1.0)
	var ridge_1: float = 1.0 - absf(surface_noise.get_noise_2d(fx * 0.62 + 820.0, fz * 0.62 - 640.0))
	var ridge_2: float = 1.0 - absf(surface_noise.get_noise_2d(fx * 1.35 - 420.0, fz * 1.35 + 910.0))
	var mountain_peak: float = pow(clampf(ridge_1 * 0.72 + ridge_2 * 0.28, 0.0, 1.0), 2.15)

	var base_elevation: float = float(SEA_LEVEL) + continent * 11.0 + hills * 7.5 + detail * 2.2
	var mountain_boost: float = mountain_mask * mountain_peak * 42.0
	var total_y: float = base_elevation + mountain_boost

	# 5. Winding River Channels carved across inland terrain
	var river_raw: float = absf(surface_noise.get_noise_2d(fx * 0.34 + 2500.0, fz * 0.34 - 2500.0))
	if river_raw < 0.058 and mountain_mask < 0.55:
		var river_t: float = 1.0 - (river_raw / 0.058)
		var river_bed: float = float(WATER_LEVEL - 3)
		total_y = lerpf(total_y, river_bed, smoothstep(0.0, 1.0, river_t))

	return clampi(int(round(total_y)), 8, CHUNK_SIZE_Y - 14)


## Evaluates whether `(wx, ly, wz)` is carved out by:
## 1) A Deep Surface Ravine / Canyon
## 2) A Walk-In Surface Cave Entrance / Cliff Cavern
## 3) A Winding 3D "Spaghetti" Cave Tunnel
## 4) A Vaulted Underground "Cheese" Cavern
static func _is_carved_cave_or_ravine(
	surface_y: int,
	wx: int,
	ly: int,
	wz: int,
	cave_noise: FastNoiseLite
) -> bool:
	if cave_noise == null or ly <= 2:
		return false

	# Protect ocean/river/lake floors so water basins never drain into caves
	if surface_y <= WATER_LEVEL + 2 and ly >= surface_y - 4:
		return false

	var fx: float = float(wx)
	var fy: float = float(ly)
	var fz: float = float(wz)

	# 1. Deep Surface Ravines / Canyons (narrow vertical fault trenches slicing from surface down to y=14)
	if surface_y >= WATER_LEVEL + 4 and ly >= 14 and ly <= surface_y:
		var rav_region: float = cave_noise.get_noise_2d(fx * 0.16 + 1900.0, fz * 0.16 - 1900.0)
		if rav_region > 0.38:
			var rav_line: float = absf(cave_noise.get_noise_2d(fx * 0.32 - 600.0, fz * 0.32 + 600.0))
			var ledge_wobble: float = cave_noise.get_noise_3d(fx * 0.8, fy * 1.6, fz * 0.8) * 0.008
			if rav_line + ledge_wobble < 0.026:
				return true

	# 2. Walk-In Surface Cave Entrances & Cliffside Caverns (breaches right through hills/mountains!)
	var can_breach_surface: bool = (surface_y >= WATER_LEVEL + 4)
	if not can_breach_surface and ly >= surface_y - 3:
		return false

	# 3. Winding 3D "Spaghetti" Tunnels (dual-noise intersection)
	var n1: float = cave_noise.get_noise_3d(fx * 0.78, fy * 1.05, fz * 0.78)
	var n2: float = cave_noise.get_noise_3d(fx * 0.78 + 413.0, fy * 1.05 + 719.0, fz * 0.78 - 521.0)
	var tunnel_radius: float = 0.145 if ly < surface_y - 3 else 0.125
	if absf(n1) < tunnel_radius and absf(n2) < tunnel_radius:
		if ly <= surface_y - 3:
			return true
		# Near the surface (`surface_y - 2 .. surface_y`), gate with an entrance mask so discrete walk-in cave mouths form!
		var entrance_mask: float = cave_noise.get_noise_2d(fx * 0.45 - 880.0, fz * 0.45 + 880.0)
		if entrance_mask > 0.12:
			return true

	# 4. Vaulted Underground "Cheese" Caverns (large subterranean halls below y = surface_y - 5)
	if ly <= surface_y - 5 and ly >= 6:
		var cavern_val: float = cave_noise.get_noise_3d(fx * 0.55 - 1200.0, fy * 0.85, fz * 0.55 + 1200.0)
		if cavern_val > 0.47:
			return true

	return false


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

	if _is_carved_cave_or_ravine(surface_y, wx, ly, wz, cave_noise):
		if ly <= 10:
			return BlockRegistry.BlockId.LAVA
		return BlockRegistry.BlockId.AIR

	# Rare glowing crystal clusters hanging from deep cavern ceilings
	if cave_noise != null and ly >= 10 and ly <= 30 and ly < surface_y - 7:
		if _is_carved_cave_or_ravine(surface_y, wx, ly - 1, wz, cave_noise):
			var glow_hash: int = absi((wx * 73856093) ^ (ly * 19349663) ^ (wz * 83492791)) % 1000
			if glow_hash < 6:
				return BlockRegistry.BlockId.GLOWSTONE

	# Low-lying basins and shorelines near/below water level generate sandy beaches
	if surface_y <= WATER_LEVEL + 1 and ly >= surface_y - 2:
		return BlockRegistry.BlockId.SAND

	var biome: int = sample_biome(wx, wz)
	if biome == Biome.DESERT and surface_y > WATER_LEVEL:
		if ly == surface_y or ly == surface_y - 1:
			return BlockRegistry.BlockId.SAND
		if ly >= surface_y - 5:
			return BlockRegistry.BlockId.SANDSTONE

	# High alpine mountain peaks & steep cliffs:
	# Snowline at `SEA_LEVEL + 18`, rocky crags & bare stone cliffs at `SEA_LEVEL + 11..17`
	if surface_y >= SEA_LEVEL + 18 or (biome == Biome.SNOWY_TAIGA and surface_y > WATER_LEVEL + 1):
		if ly == surface_y:
			return BlockRegistry.BlockId.SNOW
		if ly >= surface_y - 3 and surface_y >= SEA_LEVEL + 14:
			return BlockRegistry.BlockId.STONE
	elif surface_y >= SEA_LEVEL + 12:
		# Steep rocky mountain slopes expose bare Stone & Cobblestone crags
		var crag_hash: int = absi((wx * 374761) ^ (wz * 668265)) % 100
		if crag_hash < 68 or surface_y >= SEA_LEVEL + 15:
			if ly >= surface_y - 3:
				return BlockRegistry.BlockId.STONE

	if ly == surface_y:
		return BlockRegistry.BlockId.GRASS
	if ly >= surface_y - 3:
		return BlockRegistry.BlockId.DIRT
	return _sample_underground_stone_or_ore(wx, ly, wz)


## Deterministically places Coal, Iron, Gold, and Diamond ore clusters inside underground Stone strata.
static func _sample_underground_stone_or_ore(wx: int, ly: int, wz: int) -> int:
	# Group coordinates into 2x2x2 vein cells so ores spawn in natural multi-block clusters
	var vx: int = wx >> 1
	var vy: int = ly >> 1
	var vz: int = wz >> 1
	var cell_hash: int = absi((vx * 73856093) ^ (vy * 19349663) ^ (vz * 83492791)) % 1000
	var sub_hash: int = absi((wx * 374761393) + (ly * 668265263) + (wz * 2147483647)) % 100

	# Sub-block irregular shape (roughly 65% of the 2x2x2 vein cell becomes ore)
	if sub_hash >= 68:
		return BlockRegistry.BlockId.STONE

	if ly <= 16 and cell_hash < 8:
		return BlockRegistry.BlockId.DIAMOND_ORE
	if ly <= 28 and cell_hash >= 10 and cell_hash < 26:
		return BlockRegistry.BlockId.GOLD_ORE
	if ly <= 48 and cell_hash >= 30 and cell_hash < 74:
		return BlockRegistry.BlockId.IRON_ORE
	if ly <= 62 and cell_hash >= 75 and cell_hash < 142:
		return BlockRegistry.BlockId.COAL_ORE

	return BlockRegistry.BlockId.STONE


func _should_spawn_tree(wx: int, wz: int, biome: int = Biome.PLAINS) -> bool:
	var hash_val: int = absi((wx * 73428767) ^ (wz * 912931)) % 1000
	match biome:
		Biome.FOREST:
			return hash_val < 20
		Biome.SNOWY_TAIGA:
			return hash_val < 14
		Biome.DESERT:
			return hash_val < 7
		_:
			return hash_val < 5


func _should_spawn_boulder(wx: int, wz: int) -> bool:
	var hash_val: int = absi((wx * 19349663) ^ (wz * 83492791)) % 1000
	return hash_val == 1


func _place_mossy_boulder(lx: int, base_y: int, lz: int) -> void:
	if base_y + 2 >= CHUNK_SIZE_Y:
		return
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for dy in range(0, 2):
				if dy == 1 and (absi(dx) + absi(dz) > 1):
					continue
				if is_in_bounds(lx + dx, base_y + dy, lz + dz):
					var is_mossy: bool = ((dx + dy + dz) % 2 == 0)
					_set_voxel_raw(
						lx + dx,
						base_y + dy,
						lz + dz,
						BlockRegistry.BlockId.MOSSY_COBBLE if is_mossy else BlockRegistry.BlockId.COBBLESTONE
					)
	if base_y + 2 > _highest_solid_y:
		_highest_solid_y = base_y + 2


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


func _place_pine_tree(lx: int, base_y: int, lz: int) -> void:
	var trunk_height: int = 6
	if base_y + trunk_height + 2 >= CHUNK_SIZE_Y:
		return

	for ty in range(base_y, base_y + trunk_height):
		_set_voxel_raw(lx, ty, lz, BlockRegistry.BlockId.WOOD_LOG)

	# Conical tiered pine needles
	var tiers: Array[Vector2i] = [
		Vector2i(base_y + 2, 2),
		Vector2i(base_y + 3, 1),
		Vector2i(base_y + 4, 2),
		Vector2i(base_y + 5, 1),
		Vector2i(base_y + 6, 0),
	]
	for tier in tiers:
		var cy: int = tier.x
		var rad: int = tier.y
		for cx in range(lx - rad, lx + rad + 1):
			for cz in range(lz - rad, lz + rad + 1):
				if cx == lx and cz == lz and cy < base_y + trunk_height:
					continue
				if rad == 2 and absi(cx - lx) == 2 and absi(cz - lz) == 2:
					continue
				if is_in_bounds(cx, cy, cz):
					_set_voxel_raw(cx, cy, cz, BlockRegistry.BlockId.LEAVES)

	# Snow cap on top of the pine tree spire
	var spire_y: int = base_y + 7
	if is_in_bounds(lx, spire_y, lz):
		_set_voxel_raw(lx, spire_y, lz, BlockRegistry.BlockId.SNOW)
	if spire_y > _highest_solid_y:
		_highest_solid_y = spire_y


func _place_cactus(lx: int, base_y: int, lz: int) -> void:
	var cactus_height: int = 3
	if base_y + cactus_height >= CHUNK_SIZE_Y:
		return
	for cy in range(base_y, base_y + cactus_height):
		_set_voxel_raw(lx, cy, lz, BlockRegistry.BlockId.CACTUS)
	if base_y + cactus_height > _highest_solid_y:
		_highest_solid_y = base_y + cactus_height


## Deterministically builds Plains Village Houses, Desert Pyramids, and Underground Mossy Dungeons.
func _generate_chunk_structures(surface_noise: FastNoiseLite) -> void:
	var cx: int = chunk_coords.x
	var cz: int = chunk_coords.y
	var chunk_hash: int = absi((cx * 73856093) ^ (cz * 19349663))

	# 1. Underground Mossy Cobblestone Dungeon (spawns at y = 20..25 in ~14% of chunks)
	if chunk_hash % 7 == 0:
		var d_y: int = 20 + (chunk_hash % 5)
		_build_underground_dungeon(5, d_y, 5, chunk_hash)

	# 2. Surface Lava Pool (spawns in ~4% of chunks on stable terrain)
	var center_wx: int = cx * CHUNK_SIZE_X + 8
	var center_wz: int = cz * CHUNK_SIZE_Z + 8
	var center_y: int = sample_surface_height(surface_noise, center_wx, center_wz)
	if chunk_hash % 23 == 0 and center_y > WATER_LEVEL + 2 and center_y <= SEA_LEVEL + 5:
		_build_surface_lava_pool(5, center_y, 5, chunk_hash)

	# 3. Surface Structures (Plains Village House & Farm or Desert Sandstone Pyramid)
	if center_y <= WATER_LEVEL + 1 or center_y >= SEA_LEVEL + 7:
		return

	var biome: int = sample_biome(center_wx, center_wz)
	if biome == Biome.PLAINS and chunk_hash % 7 == 0:
		_build_village_house(2, center_y, 2, chunk_hash)
		_build_village_farm(9, center_y, 9, chunk_hash)
	elif biome == Biome.DESERT and chunk_hash % 8 == 0:
		_build_desert_pyramid(3, center_y, 3, chunk_hash)


func _build_underground_dungeon(ox: int, oy: int, oz: int, seed_val: int) -> void:
	var world_origin_x: int = chunk_coords.x * CHUNK_SIZE_X
	var world_origin_z: int = chunk_coords.y * CHUNK_SIZE_Z
	for dx in range(7):
		for dy in range(5):
			for dz in range(7):
				var lx: int = ox + dx
				var ly: int = oy + dy
				var lz: int = oz + dz
				if not is_in_bounds(lx, ly, lz):
					continue
				var is_shell: bool = (dx == 0 or dx == 6 or dy == 0 or dy == 4 or dz == 0 or dz == 6)
				if is_shell:
					var mossy: bool = ((dx * 17 + dy * 31 + dz * 13 + seed_val) % 3) != 0
					_set_voxel_raw(
						lx,
						ly,
						lz,
						BlockRegistry.BlockId.MOSSY_COBBLE if mossy else BlockRegistry.BlockId.COBBLESTONE
					)
				else:
					_set_voxel_raw(lx, ly, lz, BlockRegistry.BlockId.AIR)

	# Central torch & loot chest inside dungeon
	if is_in_bounds(ox + 3, oy + 1, oz + 3):
		_set_voxel_raw(ox + 3, oy + 1, oz + 3, BlockRegistry.BlockId.TORCH)
	if is_in_bounds(ox + 1, oy + 1, oz + 3):
		_set_voxel_raw(ox + 1, oy + 1, oz + 3, BlockRegistry.BlockId.CHEST)
		generated_loot_chests.append(Vector3i(world_origin_x + ox + 1, oy + 1, world_origin_z + oz + 3))


func _build_village_house(ox: int, base_y: int, oz: int, _seed_val: int) -> void:
	var world_origin_x: int = chunk_coords.x * CHUNK_SIZE_X
	var world_origin_z: int = chunk_coords.y * CHUNK_SIZE_Z
	if base_y + 7 >= CHUNK_SIZE_Y:
		return

	# Cobblestone foundation & leveling down 2 blocks
	for dx in range(7):
		for dz in range(7):
			for fy in range(base_y - 2, base_y + 1):
				if is_in_bounds(ox + dx, fy, oz + dz):
					_set_voxel_raw(ox + dx, fy, oz + dz, BlockRegistry.BlockId.COBBLESTONE)

	# Walls & interior
	for dy in range(1, 5):
		var ly: int = base_y + dy
		for dx in range(7):
			for dz in range(7):
				var lx: int = ox + dx
				var lz: int = oz + dz
				if not is_in_bounds(lx, ly, lz):
					continue
				var is_corner: bool = (dx == 0 or dx == 6) and (dz == 0 or dz == 6)
				var is_wall: bool = (dx == 0 or dx == 6 or dz == 0 or dz == 6)
				if is_corner:
					_set_voxel_raw(lx, ly, lz, BlockRegistry.BlockId.WOOD_LOG)
				elif is_wall:
					# Front door at (dx=3, dz=0, dy=1..2)
					if dx == 3 and dz == 0 and (dy == 1 or dy == 2):
						_set_voxel_raw(lx, ly, lz, BlockRegistry.BlockId.DOOR_CLOSED)
					elif dy == 4:
						_set_voxel_raw(lx, ly, lz, BlockRegistry.BlockId.WOOD_LOG)
					else:
						_set_voxel_raw(lx, ly, lz, BlockRegistry.BlockId.WOOD_PLANKS)
				else:
					_set_voxel_raw(lx, ly, lz, BlockRegistry.BlockId.AIR)

	# Stepped wooden roof
	for dx in range(7):
		for dz in range(7):
			if is_in_bounds(ox + dx, base_y + 5, oz + dz):
				_set_voxel_raw(ox + dx, base_y + 5, oz + dz, BlockRegistry.BlockId.WOOD_PLANKS)

	# Interior furnishings: Torch, Crafting Table, Bed, and Village Loot Chest
	_set_voxel_raw(ox + 3, base_y + 1, oz + 3, BlockRegistry.BlockId.TORCH)
	_set_voxel_raw(ox + 1, base_y + 1, oz + 5, BlockRegistry.BlockId.CRAFTING_TABLE)
	_set_voxel_raw(ox + 5, base_y + 1, oz + 5, BlockRegistry.BlockId.BED)
	_set_voxel_raw(ox + 1, base_y + 1, oz + 1, BlockRegistry.BlockId.CHEST)
	generated_loot_chests.append(Vector3i(world_origin_x + ox + 1, base_y + 1, world_origin_z + oz + 1))
	generated_villager_spawns.append(Vector3(float(world_origin_x + ox + 3) + 0.5, float(base_y + 1) + 0.2, float(world_origin_z + oz + 3) + 0.5))

	if base_y + 6 > _highest_solid_y:
		_highest_solid_y = base_y + 6


func _build_village_farm(ox: int, base_y: int, oz: int, _seed_val: int) -> void:
	var world_origin_x: int = chunk_coords.x * CHUNK_SIZE_X
	var world_origin_z: int = chunk_coords.y * CHUNK_SIZE_Z
	if base_y + 4 >= CHUNK_SIZE_Y:
		return

	# 6x6 fenced farm with central water canal, Farmland blocks, and Wheat & Potato crops
	for dx in range(6):
		for dz in range(6):
			var lx: int = ox + dx
			var lz: int = oz + dz
			if not is_in_bounds(lx, base_y, lz):
				continue
			var is_border: bool = (dx == 0 or dx == 5 or dz == 0 or dz == 5)
			var is_water_canal: bool = (dx == 2 and dz >= 1 and dz <= 4)

			if is_border:
				_set_voxel_raw(lx, base_y, lz, BlockRegistry.BlockId.WOOD_LOG)
				_set_voxel_raw(lx, base_y + 1, lz, BlockRegistry.BlockId.AIR)
			elif is_water_canal:
				_set_voxel_raw(lx, base_y, lz, BlockRegistry.BlockId.WATER)
				_set_voxel_raw(lx, base_y + 1, lz, BlockRegistry.BlockId.AIR)
			else:
				_set_voxel_raw(lx, base_y, lz, BlockRegistry.BlockId.FARMLAND)
				var crop_id: int = BlockRegistry.BlockId.WHEAT_CROPS if (dx % 2 == 1) else BlockRegistry.BlockId.POTATO_CROPS
				_set_voxel_raw(lx, base_y + 1, lz, crop_id)
				_set_voxel_raw(lx, base_y + 2, lz, BlockRegistry.BlockId.AIR)

	if is_in_bounds(ox, base_y + 1, oz):
		_set_voxel_raw(ox, base_y + 1, oz, BlockRegistry.BlockId.TORCH)
	if is_in_bounds(ox + 5, base_y + 1, oz + 5):
		_set_voxel_raw(ox + 5, base_y + 1, oz + 5, BlockRegistry.BlockId.TORCH)

	generated_villager_spawns.append(Vector3(float(world_origin_x + ox + 3) + 0.5, float(base_y + 1) + 0.2, float(world_origin_z + oz + 3) + 0.5))


func _build_surface_lava_pool(ox: int, base_y: int, oz: int, _seed_val: int) -> void:
	for dx in range(5):
		for dz in range(5):
			var lx: int = ox + dx
			var lz: int = oz + dz
			if not is_in_bounds(lx, base_y - 1, lz):
				continue
			var is_edge: bool = (dx == 0 or dx == 4 or dz == 0 or dz == 4)
			_set_voxel_raw(lx, base_y - 2, lz, BlockRegistry.BlockId.STONE)
			if is_edge:
				_set_voxel_raw(lx, base_y - 1, lz, BlockRegistry.BlockId.COBBLESTONE)
				_set_voxel_raw(lx, base_y, lz, BlockRegistry.BlockId.AIR)
			else:
				_set_voxel_raw(lx, base_y - 1, lz, BlockRegistry.BlockId.LAVA)
				_set_voxel_raw(lx, base_y, lz, BlockRegistry.BlockId.AIR)


func _build_desert_pyramid(ox: int, base_y: int, oz: int, _seed_val: int) -> void:
	var world_origin_x: int = chunk_coords.x * CHUNK_SIZE_X
	var world_origin_z: int = chunk_coords.y * CHUNK_SIZE_Z
	if base_y + 7 >= CHUNK_SIZE_Y:
		return

	# Sandstone base platform
	for dx in range(9):
		for dz in range(9):
			for fy in range(base_y - 2, base_y + 1):
				if is_in_bounds(ox + dx, fy, oz + dz):
					_set_voxel_raw(ox + dx, fy, oz + dz, BlockRegistry.BlockId.SANDSTONE)

	# Stepped pyramid layers (5 tiers from 9x9 down to 1x1)
	for tier in range(5):
		var ly: int = base_y + 1 + tier
		for dx in range(tier, 9 - tier):
			for dz in range(tier, 9 - tier):
				var lx: int = ox + dx
				var lz: int = oz + dz
				if not is_in_bounds(lx, ly, lz):
					continue
				var is_outer: bool = (dx == tier or dx == 8 - tier or dz == tier or dz == 8 - tier)
				if tier <= 2 and not is_outer:
					_set_voxel_raw(lx, ly, lz, BlockRegistry.BlockId.AIR)
				else:
					_set_voxel_raw(lx, ly, lz, BlockRegistry.BlockId.SANDSTONE)

	# Front entrance archway
	_set_voxel_raw(ox + 4, base_y + 1, oz, BlockRegistry.BlockId.AIR)
	_set_voxel_raw(ox + 4, base_y + 2, oz, BlockRegistry.BlockId.AIR)

	# Interior Torch, TNT trap block, and Pharaoh Loot Chest
	_set_voxel_raw(ox + 4, base_y + 1, oz + 3, BlockRegistry.BlockId.TORCH)
	_set_voxel_raw(ox + 4, base_y + 1, oz + 5, BlockRegistry.BlockId.TNT)
	_set_voxel_raw(ox + 4, base_y + 1, oz + 6, BlockRegistry.BlockId.CHEST)
	generated_loot_chests.append(Vector3i(world_origin_x + ox + 4, base_y + 1, world_origin_z + oz + 6))

	if base_y + 6 > _highest_solid_y:
		_highest_solid_y = base_y + 6


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

	var st_col := SurfaceTool.new()
	st_col.begin(Mesh.PRIMITIVE_TRIANGLES)

	var st_water := SurfaceTool.new()
	st_water.begin(Mesh.PRIMITIVE_TRIANGLES)

	var y_start: int = sub_idx * SUB_CHUNK_HEIGHT
	var y_end: int = mini(y_start + SUB_CHUNK_HEIGHT, CHUNK_SIZE_Y)
	var solid_faces: int = 0
	var col_faces: int = 0
	var water_faces: int = 0

	for ly in range(y_start, y_end):
		for lx in range(CHUNK_SIZE_X):
			for lz in range(CHUNK_SIZE_Z):
				var block_id: int = get_block_local(lx, ly, lz)
				if block_id == BlockRegistry.BlockId.AIR:
					continue

				if BlockRegistry.is_liquid(block_id):
					var h00: float = _compute_water_corner_height(lx, ly, lz, -1, -1)
					var h10: float = _compute_water_corner_height(lx, ly, lz, 1, -1)
					var h11: float = _compute_water_corner_height(lx, ly, lz, 1, 1)
					var h01: float = _compute_water_corner_height(lx, ly, lz, -1, 1)

					if not BlockRegistry.is_liquid(_get_neighbor_id(lx, ly + 1, lz)):
						_emit_sloped_water_face(st_water, lx, ly, lz, BlockRegistry.FaceDir.TOP, h00, h10, h11, h01)
						water_faces += 1
					if _get_neighbor_id(lx, ly - 1, lz) == BlockRegistry.BlockId.AIR:
						_emit_sloped_water_face(st_water, lx, ly, lz, BlockRegistry.FaceDir.BOTTOM, h00, h10, h11, h01)
						water_faces += 1
					if _get_neighbor_id(lx + 1, ly, lz) == BlockRegistry.BlockId.AIR:
						_emit_sloped_water_face(st_water, lx, ly, lz, BlockRegistry.FaceDir.EAST, h00, h10, h11, h01)
						water_faces += 1
					if _get_neighbor_id(lx - 1, ly, lz) == BlockRegistry.BlockId.AIR:
						_emit_sloped_water_face(st_water, lx, ly, lz, BlockRegistry.FaceDir.WEST, h00, h10, h11, h01)
						water_faces += 1
					if _get_neighbor_id(lx, ly, lz + 1) == BlockRegistry.BlockId.AIR:
						_emit_sloped_water_face(st_water, lx, ly, lz, BlockRegistry.FaceDir.SOUTH, h00, h10, h11, h01)
						water_faces += 1
					if _get_neighbor_id(lx, ly, lz - 1) == BlockRegistry.BlockId.AIR:
						_emit_sloped_water_face(st_water, lx, ly, lz, BlockRegistry.FaceDir.NORTH, h00, h10, h11, h01)
						water_faces += 1
					continue

				# Custom foliage blocks (Sugar Cane, Seagrass cross quads)
				if block_id == BlockRegistry.BlockId.SUGAR_CANE or block_id == BlockRegistry.BlockId.SEAGRASS:
					_emit_cross_quad(st_solid, lx, ly, lz, block_id)
					solid_faces += 4
					continue

				# Custom non-cube functional blocks (Torches, Beds, Doors, Ladders)
				if not BlockRegistry.is_opaque_full_cube(block_id):
					var min_b := Vector3(0.0, 0.0, 0.0)
					var max_b := Vector3(1.0, 1.0, 1.0)
					match block_id:
						BlockRegistry.BlockId.TORCH:
							min_b = Vector3(0.40, 0.0, 0.40)
							max_b = Vector3(0.60, 0.68, 0.60)
						BlockRegistry.BlockId.BED:
							min_b = Vector3(0.0, 0.0, 0.0)
							max_b = Vector3(1.0, 0.56, 1.0)
						BlockRegistry.BlockId.DOOR_CLOSED:
							min_b = Vector3(0.0, 0.0, 0.40)
							max_b = Vector3(1.0, 1.0, 0.60)
						BlockRegistry.BlockId.DOOR_OPEN:
							min_b = Vector3(0.0, 0.0, 0.0)
							max_b = Vector3(0.20, 1.0, 1.0)
						BlockRegistry.BlockId.LADDER:
							min_b = Vector3(0.0, 0.0, 0.42)
							max_b = Vector3(1.0, 1.0, 0.58)
						BlockRegistry.BlockId.FARMLAND:
							min_b = Vector3(0.0, 0.0, 0.0)
							max_b = Vector3(1.0, 0.9375, 1.0)
						BlockRegistry.BlockId.WHEAT_CROPS, BlockRegistry.BlockId.POTATO_CROPS:
							min_b = Vector3(0.06, 0.0, 0.06)
							max_b = Vector3(0.94, 0.88, 0.94)
					_emit_custom_box(st_solid, lx, ly, lz, min_b, max_b, block_id)
					solid_faces += 6
					if not BlockRegistry.is_passable_block(block_id):
						_emit_custom_box(st_col, lx, ly, lz, min_b, max_b, block_id)
						col_faces += 6
					continue

				if not _is_neighbor_solid(lx, ly + 1, lz):
					_emit_face(st_solid, lx, ly, lz, BlockRegistry.FaceDir.TOP, block_id)
					_emit_face(st_col, lx, ly, lz, BlockRegistry.FaceDir.TOP, block_id)
					solid_faces += 1
					col_faces += 1
				if not _is_neighbor_solid(lx, ly - 1, lz):
					_emit_face(st_solid, lx, ly, lz, BlockRegistry.FaceDir.BOTTOM, block_id)
					_emit_face(st_col, lx, ly, lz, BlockRegistry.FaceDir.BOTTOM, block_id)
					solid_faces += 1
					col_faces += 1
				if not _is_neighbor_solid(lx + 1, ly, lz):
					_emit_face(st_solid, lx, ly, lz, BlockRegistry.FaceDir.EAST, block_id)
					_emit_face(st_col, lx, ly, lz, BlockRegistry.FaceDir.EAST, block_id)
					solid_faces += 1
					col_faces += 1
				if not _is_neighbor_solid(lx - 1, ly, lz):
					_emit_face(st_solid, lx, ly, lz, BlockRegistry.FaceDir.WEST, block_id)
					_emit_face(st_col, lx, ly, lz, BlockRegistry.FaceDir.WEST, block_id)
					solid_faces += 1
					col_faces += 1
				if not _is_neighbor_solid(lx, ly, lz + 1):
					_emit_face(st_solid, lx, ly, lz, BlockRegistry.FaceDir.SOUTH, block_id)
					_emit_face(st_col, lx, ly, lz, BlockRegistry.FaceDir.SOUTH, block_id)
					solid_faces += 1
					col_faces += 1
				if not _is_neighbor_solid(lx, ly, lz - 1):
					_emit_face(st_solid, lx, ly, lz, BlockRegistry.FaceDir.NORTH, block_id)
					_emit_face(st_col, lx, ly, lz, BlockRegistry.FaceDir.NORTH, block_id)
					solid_faces += 1
					col_faces += 1

	if solid_faces > 0:
		st_solid.generate_tangents()
	var solid_mesh: ArrayMesh = st_solid.commit() if solid_faces > 0 else null
	var col_mesh: ArrayMesh = st_col.commit() if col_faces > 0 else null
	var water_mesh: ArrayMesh = st_water.commit() if water_faces > 0 else null
	var trimesh_shape: ConcavePolygonShape3D = col_mesh.create_trimesh_shape() if col_mesh != null else null

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
	_sync_all_light_emitters()
	if not generated_loot_chests.is_empty() and is_inside_tree():
		var inv := get_tree().get_first_node_in_group("inventory_manager") as InventoryManager
		if inv != null:
			for chest_pos in generated_loot_chests:
				var seed_val: int = absi((chest_pos.x * 73856093) ^ (chest_pos.y * 19349663) ^ (chest_pos.z * 83492791))
				inv.populate_loot_chest_at(chest_pos, seed_val)
			generated_loot_chests.clear()

	if not generated_villager_spawns.is_empty() and is_inside_tree():
		var parent_node: Node = get_parent()
		if parent_node != null:
			for spawn_pos in generated_villager_spawns:
				var villager := PassiveMob.new()
				villager.variant = PassiveMob.MobVariant.VILLAGER
				parent_node.add_child(villager)
				villager.global_position = spawn_pos
		generated_villager_spawns.clear()


func _apply_single_sub_chunk(sub_idx: int, sub_data: Dictionary) -> void:
	var m: ArrayMesh = sub_data.get("mesh", null) as ArrayMesh
	_sub_solid_meshes[sub_idx].mesh = m
	_sub_solid_meshes[sub_idx].visible = (m != null)

	var wm: ArrayMesh = sub_data.get("water_mesh", null) as ArrayMesh
	_sub_water_meshes[sub_idx].mesh = wm
	_sub_water_meshes[sub_idx].visible = (wm != null)

	var s: Shape3D = sub_data.get("shape", null) as Shape3D
	_sub_colliders[sub_idx].shape = s
	_sub_colliders[sub_idx].disabled = (s == null)


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
	return BlockRegistry.is_opaque_full_cube(_get_neighbor_id(lx, ly, lz))


func _emit_cross_quad(
	st: SurfaceTool,
	lx: int,
	ly: int,
	lz: int,
	block_id: int
) -> void:
	var origin := Vector3(float(lx), float(ly), float(lz))
	var uv_rect: Rect2 = BlockRegistry.get_tile_uv_rect(block_id, BlockRegistry.FaceDir.NORTH)
	var u0: float = uv_rect.position.x
	var v0: float = uv_rect.position.y
	var u1: float = uv_rect.position.x + uv_rect.size.x
	var v1: float = uv_rect.position.y + uv_rect.size.y

	# Diagonal 1: (0, 0, 0) to (1, 1, 1)
	var d1_p0 := origin + Vector3(0.0, 0.0, 0.0)
	var d1_p1 := origin + Vector3(1.0, 0.0, 1.0)
	var d1_p2 := origin + Vector3(1.0, 1.0, 1.0)
	var d1_p3 := origin + Vector3(0.0, 1.0, 0.0)

	# Diagonal 2: (0, 0, 1) to (1, 1, 0)
	var d2_p0 := origin + Vector3(0.0, 0.0, 1.0)
	var d2_p1 := origin + Vector3(1.0, 0.0, 0.0)
	var d2_p2 := origin + Vector3(1.0, 1.0, 0.0)
	var d2_p3 := origin + Vector3(0.0, 1.0, 1.0)

	var normal1 := Vector3(-0.7071, 0.0, 0.7071)
	var normal2 := Vector3(0.7071, 0.0, 0.7071)
	var col := Color(0.94, 0.94, 0.94, 1.0)

	# Diagonal 1 (Front & Back)
	for pass_idx in range(2):
		var n: Vector3 = normal1 if pass_idx == 0 else -normal1
		var a: Vector3 = d1_p0 if pass_idx == 0 else d1_p1
		var b: Vector3 = d1_p1 if pass_idx == 0 else d1_p0
		var c: Vector3 = d1_p2 if pass_idx == 0 else d1_p3
		var d: Vector3 = d1_p3 if pass_idx == 0 else d1_p2

		st.set_color(col)
		st.set_normal(n)

		st.set_uv(Vector2(u0, v1))
		st.add_vertex(a)
		st.set_uv(Vector2(u1, v1))
		st.add_vertex(b)
		st.set_uv(Vector2(u1, v0))
		st.add_vertex(c)

		st.set_uv(Vector2(u0, v1))
		st.add_vertex(a)
		st.set_uv(Vector2(u1, v0))
		st.add_vertex(c)
		st.set_uv(Vector2(u0, v0))
		st.add_vertex(d)

	# Diagonal 2 (Front & Back)
	for pass_idx in range(2):
		var n: Vector3 = normal2 if pass_idx == 0 else -normal2
		var a: Vector3 = d2_p0 if pass_idx == 0 else d2_p1
		var b: Vector3 = d2_p1 if pass_idx == 0 else d2_p0
		var c: Vector3 = d2_p2 if pass_idx == 0 else d2_p3
		var d: Vector3 = d2_p3 if pass_idx == 0 else d2_p2

		st.set_color(col)
		st.set_normal(n)

		st.set_uv(Vector2(u0, v1))
		st.add_vertex(a)
		st.set_uv(Vector2(u1, v1))
		st.add_vertex(b)
		st.set_uv(Vector2(u1, v0))
		st.add_vertex(c)

		st.set_uv(Vector2(u0, v1))
		st.add_vertex(a)
		st.set_uv(Vector2(u1, v0))
		st.add_vertex(c)
		st.set_uv(Vector2(u0, v0))
		st.add_vertex(d)


func _emit_custom_box(
	st: SurfaceTool,
	lx: int,
	ly: int,
	lz: int,
	min_b: Vector3,
	max_b: Vector3,
	block_id: int
) -> void:
	var origin := Vector3(float(lx), float(ly), float(lz))
	var p0: Vector3 = origin + min_b
	var p1: Vector3 = origin + max_b
	var faces: Array[int] = [
		BlockRegistry.FaceDir.TOP,
		BlockRegistry.FaceDir.BOTTOM,
		BlockRegistry.FaceDir.EAST,
		BlockRegistry.FaceDir.WEST,
		BlockRegistry.FaceDir.SOUTH,
		BlockRegistry.FaceDir.NORTH,
	]
	for face_dir in faces:
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
				verts = [Vector3(p0.x, p1.y, p0.z), Vector3(p1.x, p1.y, p0.z), Vector3(p1.x, p1.y, p1.z), Vector3(p0.x, p1.y, p1.z)]
			BlockRegistry.FaceDir.BOTTOM:
				normal = Vector3.DOWN
				shade = 0.55
				verts = [Vector3(p0.x, p0.y, p1.z), Vector3(p1.x, p0.y, p1.z), Vector3(p1.x, p0.y, p0.z), Vector3(p0.x, p0.y, p0.z)]
			BlockRegistry.FaceDir.EAST:
				normal = Vector3.RIGHT
				shade = 0.82
				verts = [Vector3(p1.x, p1.y, p1.z), Vector3(p1.x, p1.y, p0.z), Vector3(p1.x, p0.y, p0.z), Vector3(p1.x, p0.y, p1.z)]
			BlockRegistry.FaceDir.WEST:
				normal = Vector3.LEFT
				shade = 0.76
				verts = [Vector3(p0.x, p1.y, p0.z), Vector3(p0.x, p1.y, p1.z), Vector3(p0.x, p0.y, p1.z), Vector3(p0.x, p0.y, p0.z)]
			BlockRegistry.FaceDir.SOUTH:
				normal = Vector3.BACK
				shade = 0.90
				verts = [Vector3(p0.x, p1.y, p1.z), Vector3(p1.x, p1.y, p1.z), Vector3(p1.x, p0.y, p1.z), Vector3(p0.x, p0.y, p1.z)]
			_:
				normal = Vector3.FORWARD
				shade = 0.72
				verts = [Vector3(p1.x, p1.y, p0.z), Vector3(p0.x, p1.y, p0.z), Vector3(p0.x, p0.y, p0.z), Vector3(p1.x, p0.y, p0.z)]

		if BlockRegistry.is_light_emitter(block_id):
			shade = 1.0
		var col := Color(shade, shade, shade, 1.0)
		var uvs: Array[Vector2] = [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
		var indices: Array[int] = [0, 1, 2, 0, 2, 3]
		for idx in indices:
			st.set_normal(normal)
			st.set_color(col)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])


## Computes the smoothed water height at a corner shared by the 4 cells around (lx, ly, lz) in quadrant (dx, dz).
func _compute_water_corner_height(lx: int, ly: int, lz: int, dx: int, dz: int) -> float:
	var sum_h: float = 0.0
	var max_h: float = 0.0
	var count: int = 0
	var has_air_neighbor: bool = false

	for ox in [0, dx]:
		for oz in [0, dz]:
			var nx: int = lx + ox
			var nz: int = lz + oz
			# If any cell sharing this vertex has water directly above it, snap corner to 1.0 for seamless waterfalls
			if BlockRegistry.is_liquid(_get_neighbor_id(nx, ly + 1, nz)):
				return 1.0
			var nid: int = _get_neighbor_id(nx, ly, nz)
			if BlockRegistry.is_liquid(nid):
				var h: float = BlockRegistry.get_water_height_ratio(nid)
				sum_h += h
				max_h = maxf(max_h, h)
				count += 1
			elif nid == BlockRegistry.BlockId.AIR:
				has_air_neighbor = true

	if count == 0:
		return 0.12
	var avg_h: float = sum_h / float(count)
	# Taper down slightly when bordering open air so edges & corners form a visible downward lip
	var edge_drop: float = -0.04 if (has_air_neighbor and max_h < 0.87) else 0.0
	return clampf(avg_h * 0.72 + max_h * 0.28 + edge_drop, 0.07, 0.96)


func _emit_sloped_water_face(
	st: SurfaceTool,
	lx: int,
	ly: int,
	lz: int,
	face_dir: int,
	h00: float,
	h10: float,
	h11: float,
	h01: float
) -> void:
	var origin := Vector3(float(lx), float(ly), float(lz))
	var verts: Array[Vector3]
	var normal: Vector3
	var shade: float = 1.0

	match face_dir:
		BlockRegistry.FaceDir.TOP:
			shade = 1.0
			verts = [
				origin + Vector3(0.0, h00, 0.0),
				origin + Vector3(1.0, h10, 0.0),
				origin + Vector3(1.0, h11, 1.0),
				origin + Vector3(0.0, h01, 1.0),
			]
			var calc_norm: Vector3 = (verts[3] - verts[0]).cross(verts[1] - verts[0]).normalized()
			normal = calc_norm if calc_norm.length_squared() > 0.01 else Vector3.UP
		BlockRegistry.FaceDir.BOTTOM:
			normal = Vector3.DOWN
			shade = 0.65
			verts = [
				origin + Vector3(0.0, 0.0, 1.0),
				origin + Vector3(1.0, 0.0, 1.0),
				origin + Vector3(1.0, 0.0, 0.0),
				origin + Vector3(0.0, 0.0, 0.0),
			]
		BlockRegistry.FaceDir.EAST:
			normal = Vector3.RIGHT
			shade = 0.85
			verts = [
				origin + Vector3(1.0, h11, 1.0),
				origin + Vector3(1.0, h10, 0.0),
				origin + Vector3(1.0, 0.0, 0.0),
				origin + Vector3(1.0, 0.0, 1.0),
			]
		BlockRegistry.FaceDir.WEST:
			normal = Vector3.LEFT
			shade = 0.80
			verts = [
				origin + Vector3(0.0, h00, 0.0),
				origin + Vector3(0.0, h01, 1.0),
				origin + Vector3(0.0, 0.0, 1.0),
				origin + Vector3(0.0, 0.0, 0.0),
			]
		BlockRegistry.FaceDir.SOUTH:
			normal = Vector3.BACK
			shade = 0.90
			verts = [
				origin + Vector3(0.0, h01, 1.0),
				origin + Vector3(1.0, h11, 1.0),
				origin + Vector3(1.0, 0.0, 1.0),
				origin + Vector3(0.0, 0.0, 1.0),
			]
		_: # NORTH
			normal = Vector3.FORWARD
			shade = 0.78
			verts = [
				origin + Vector3(1.0, h10, 0.0),
				origin + Vector3(0.0, h00, 0.0),
				origin + Vector3(0.0, 0.0, 0.0),
				origin + Vector3(1.0, 0.0, 0.0),
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
	if BlockRegistry.is_light_emitter(block_id):
		shade = 1.0
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
	_update_light_emitter_at(Vector3i(lx, ly, lz), block_id)
	if immediate_rebuild:
		rebuild_at_local_y(ly)


func _update_light_emitter_at(local_pos: Vector3i, block_id: int) -> void:
	if BlockRegistry.is_light_emitter(block_id):
		if not _block_lights.has(local_pos):
			var omni := OmniLight3D.new()
			omni.position = Vector3(local_pos) + Vector3(0.5, 0.5, 0.5)
			if block_id == BlockRegistry.BlockId.LAVA:
				omni.light_color = Color(1.0, 0.40, 0.10)
				omni.light_energy = 2.4
				omni.omni_range = 14.0
			else:
				omni.light_color = Color(1.0, 0.86, 0.52)
				omni.light_energy = 1.85
				omni.omni_range = 11.0
			omni.omni_attenuation = 1.2
			add_child(omni)
			_block_lights[local_pos] = omni
	else:
		if _block_lights.has(local_pos):
			var old_light: OmniLight3D = _block_lights[local_pos]
			_block_lights.erase(local_pos)
			if is_instance_valid(old_light):
				old_light.queue_free()


func _sync_all_light_emitters() -> void:
	if _voxels.is_empty():
		return
	var max_y: int = mini(_highest_solid_y + 1, CHUNK_SIZE_Y)
	for ly in range(max_y):
		for lx in range(CHUNK_SIZE_X):
			for lz in range(CHUNK_SIZE_Z):
				var id: int = get_block_local(lx, ly, lz)
				if BlockRegistry.is_light_emitter(id):
					_update_light_emitter_at(Vector3i(lx, ly, lz), id)


func _set_voxel_raw(lx: int, ly: int, lz: int, block_id: int) -> void:
	_voxels[_to_index(lx, ly, lz)] = block_id


func _to_index(lx: int, ly: int, lz: int) -> int:
	return (ly * CHUNK_SIZE_Z + lz) * CHUNK_SIZE_X + lx
