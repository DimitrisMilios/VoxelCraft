class_name VoxelChunk
extends StaticBody3D
const VoxelLighting = preload("res://scripts/world/voxel_lighting.gd")
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
	DESERT = 1,
	FOREST = 2,
	RAINFOREST = 3,
	SEASONAL_FOREST = 4,
	SAVANNA = 5,
	SHRUBLAND = 6,
	SWAMPLAND = 7,
	TAIGA = 10,
	TUNDRA = 11,
	SNOWY_TAIGA = 10, # Backward-compatibility alias
}

## Coordinate of this chunk in chunk-grid space (e.g., Vector2i(0, 0), Vector2i(1, -2)).
var chunk_coords: Vector2i = Vector2i.ZERO

## True if the player has broken or placed at least one block in this chunk.
var is_dirty: bool = false

## World positions of any Loot Chests generated in this chunk's structures.
var generated_loot_chests: Array[Vector3i] = []

## World positions of any Villagers to spawn when this chunk is added to tree.
var generated_villager_spawns: Array[Vector3] = []

## Contiguous 1D byte buffer of size 16 * 256 * 16 (65,536 bytes).
var _voxels: PackedByteArray = PackedByteArray()
var _highest_solid_y: int = 0
## 4-bit nibble buffer (32,768 bytes) for block metadata (stairs orientation, wool colors, slabs, crops).
var _metadata: PackedByteArray = PackedByteArray()
## 4-bit dual-channel lighting buffer (65,536 bytes) storing [High: Skylight 0..15 | Low: Blocklight 0..15].
var _lighting: PackedByteArray = PackedByteArray()
## Bumped whenever `_lighting` is edited on the main thread, so stale worker results are not applied.
var light_version: int = 0
## True once the chunk has been meshed and attached to the world.
var is_meshed: bool = false

## Version tracking per sub-chunk to safely discard stale async worker builds.
var _sub_versions: PackedInt32Array = PackedInt32Array()
var _water_versions: PackedInt32Array = PackedInt32Array()

## Nodes are created lazily: empty sub-chunks (mostly sky) never allocate scene nodes.
var _sub_meshes: Array[MeshInstance3D] = []
var _sub_water: Array[MeshInstance3D] = []
var _sub_cols: Array[CollisionShape3D] = []


func _init() -> void:
	_sub_versions.resize(SUB_CHUNK_COUNT)
	_water_versions.resize(SUB_CHUNK_COUNT)
	_sub_meshes.resize(SUB_CHUNK_COUNT)
	_sub_water.resize(SUB_CHUNK_COUNT)
	_sub_cols.resize(SUB_CHUNK_COUNT)


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0


## Kept for callers that expect it; sub-chunk nodes are created on demand.
func _ensure_child_nodes() -> void:
	pass


## Restores voxel data directly from a saved persistence buffer.
func load_from_buffer(saved_voxels: PackedByteArray, highest_y: int, saved_metadata: PackedByteArray = PackedByteArray()) -> void:
	_voxels = saved_voxels
	_highest_solid_y = clampi(maxi(highest_y, WATER_LEVEL), 0, CHUNK_SIZE_Y - 1)
	if not saved_metadata.is_empty():
		_metadata = saved_metadata
	else:
		_metadata.clear()
	is_dirty = true


func get_voxels_buffer() -> PackedByteArray:
	return _voxels


func get_metadata_buffer() -> PackedByteArray:
	return _metadata


func get_metadata_local(lx: int, ly: int, lz: int) -> int:
	if not is_in_bounds(lx, ly, lz) or _metadata.is_empty():
		return 0
	var i: int = _to_index(lx, ly, lz)
	var byte_idx: int = i >> 1
	if byte_idx >= _metadata.size():
		return 0
	var b: int = _metadata[byte_idx]
	return (b & 0x0F) if ((i & 1) == 0) else ((b >> 4) & 0x0F)


func set_metadata_local(lx: int, ly: int, lz: int, val: int, immediate_rebuild: bool = false) -> void:
	if not is_in_bounds(lx, ly, lz):
		return
	_ensure_metadata_buffer()
	var i: int = _to_index(lx, ly, lz)
	var byte_idx: int = i >> 1
	var b: int = _metadata[byte_idx]
	if (i & 1) == 0:
		b = (b & 0xF0) | (val & 0x0F)
	else:
		b = (b & 0x0F) | ((val & 0x0F) << 4)
	_metadata[byte_idx] = b
	is_dirty = true
	if immediate_rebuild:
		rebuild_at_local_y(ly)


func _ensure_metadata_buffer() -> void:
	var target_size: int = (CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z) / 2
	if _metadata.size() < target_size:
		_metadata.resize(target_size)
		_metadata.fill(0)


func get_highest_solid_y() -> int:
	return _highest_solid_y


## Initializes and generates terrain for this chunk using 2D heightmap + 3D cave noise + water basins.
## Safe to execute on a background WorkerThreadPool thread.
func generate_terrain(surface_noise: FastNoiseLite, cave_noise: FastNoiseLite = null) -> void:
	_voxels.resize(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z)
	_voxels.fill(BlockRegistry.BlockId.AIR)
	_metadata.clear()
	_highest_solid_y = WATER_LEVEL

	var world_origin_x: int = chunk_coords.x * CHUNK_SIZE_X
	var world_origin_z: int = chunk_coords.y * CHUNK_SIZE_Z

	for lx in range(CHUNK_SIZE_X):
		var wx: int = world_origin_x + lx
		for lz in range(CHUNK_SIZE_Z):
			var wz: int = world_origin_z + lz

			var surface_y: int = sample_surface_height(surface_noise, wx, wz)
			var top_y: int = maxi(surface_y, WATER_LEVEL)

			# Biome is per column; computing it once here instead of per block is a big generation win.
			var col_biome: int = sample_biome(wx, wz, surface_noise.seed if surface_noise != null else 0)
			var below_carved: int = 0
			for ly in range(top_y + 1):
				var block_id: int = sample_terrain_voxel(surface_y, wx, ly, wz, cave_noise, col_biome, below_carved)
				below_carved = 1 if (ly > 3 and ly <= surface_y and (block_id == BlockRegistry.BlockId.AIR or block_id == BlockRegistry.BlockId.LAVA)) else 0
				if block_id != BlockRegistry.BlockId.AIR:
					_set_voxel_raw(lx, ly, lz, block_id)

			if top_y > _highest_solid_y:
				_highest_solid_y = top_y

			# Deterministic trees, plants, flowers, cacti, and boulders
			if surface_y > WATER_LEVEL + 1 and surface_y + 1 < CHUNK_SIZE_Y:
				var surface_id: int = get_block_local(lx, surface_y, lz)
				var biome: int = col_biome

				# 1. Trees (only in safe inner margins so canopies do not clip chunk borders)
				if lx >= 3 and lx <= CHUNK_SIZE_X - 4 and lz >= 3 and lz <= CHUNK_SIZE_Z - 4:
					if biome == Biome.DESERT and surface_id == BlockRegistry.BlockId.SAND:
						if _should_spawn_tree(wx, wz, biome):
							_place_cactus(lx, surface_y + 1, lz)
					elif _should_spawn_tree(wx, wz, biome) and (surface_id == BlockRegistry.BlockId.GRASS or surface_id == BlockRegistry.BlockId.SNOW):
						if biome == Biome.TAIGA or biome == Biome.TUNDRA or surface_y >= SEA_LEVEL + 12:
							_place_pine_tree(lx, surface_y + 1, lz)
						elif biome == Biome.RAINFOREST:
							var rf_tree_type: int = absi((wx * 17) ^ (wz * 31)) % 10
							if rf_tree_type < 5:
								_place_birch_tree(lx, surface_y + 1, lz)
							else:
								_place_balloon_tree(lx, surface_y + 1, lz)
						elif biome == Biome.SEASONAL_FOREST:
							var sf_tree_type: int = absi((wx * 13) ^ (wz * 29)) % 10
							if sf_tree_type < 6:
								_place_balloon_tree(lx, surface_y + 1, lz)
							else:
								_place_tree(lx, surface_y + 1, lz)
						elif biome == Biome.FOREST:
							var f_tree_type: int = absi((wx * 19) ^ (wz * 37)) % 10
							if f_tree_type < 4:
								_place_birch_tree(lx, surface_y + 1, lz)
							else:
								_place_tree(lx, surface_y + 1, lz)
						else:
							_place_tree(lx, surface_y + 1, lz)
					elif (biome == Biome.FOREST or biome == Biome.TAIGA or biome == Biome.SEASONAL_FOREST) and _should_spawn_boulder(wx, wz) and surface_id != BlockRegistry.BlockId.AIR:
						_place_mossy_boulder(lx, surface_y, lz)

				# 2. Flowers, Wild Plants, and Mushrooms
				if get_block_local(lx, surface_y + 1, lz) == BlockRegistry.BlockId.AIR:
					var plant_hash: int = absi((wx * 48271) ^ (wz * 95083)) % 1000
					if surface_id == BlockRegistry.BlockId.GRASS:
						if biome == Biome.PLAINS and plant_hash < 85:
							var flower_id: int = BlockRegistry.BlockId.DANDELION if (plant_hash % 2 == 0) else BlockRegistry.BlockId.ROSE
							_set_voxel_raw(lx, surface_y + 1, lz, flower_id)
						elif (biome == Biome.FOREST or biome == Biome.SEASONAL_FOREST or biome == Biome.RAINFOREST) and plant_hash < 40:
							if plant_hash < 25:
								_set_voxel_raw(lx, surface_y + 1, lz, BlockRegistry.BlockId.ROSE if (plant_hash % 2 == 0) else BlockRegistry.BlockId.DANDELION)
							else:
								_set_voxel_raw(lx, surface_y + 1, lz, BlockRegistry.BlockId.BROWN_MUSHROOM)
						elif biome == Biome.SWAMPLAND and plant_hash < 65:
							var shroom_id: int = BlockRegistry.BlockId.BROWN_MUSHROOM if (plant_hash % 2 == 0) else BlockRegistry.BlockId.RED_MUSHROOM
							_set_voxel_raw(lx, surface_y + 1, lz, shroom_id)

			# Sugar cane grows in clumps on sand/grass/dirt right at the water's edge: the ground block
			# sits at water level and a horizontally adjacent block is open (unfrozen) water.
			if surface_y == WATER_LEVEL and get_block_local(lx, surface_y + 1, lz) == BlockRegistry.BlockId.AIR:
				_try_place_sugar_cane(surface_noise, lx, lz, wx, wz, surface_y)

			# Underwater Seagrass on shallow lake beds
			elif surface_y < WATER_LEVEL and surface_y >= WATER_LEVEL - 3 and (surface_y + 1 < CHUNK_SIZE_Y):
				var sea_hash: int = absi((wx * 15485863) ^ (wz * 32452843)) % 100
				if sea_hash < 32:
					_set_voxel_raw(lx, surface_y + 1, lz, BlockRegistry.BlockId.SEAGRASS)

	_generate_chunk_structures(surface_noise)


## Continuous multi-scale Temperature map [0.0..1.0] matching Minecraft Beta 1.7.3.
static func sample_temperature(wx: int, wz: int, world_seed: int = 0) -> float:
	var seed_x: float = float(int(world_seed * 1664525 + 1013904223) % 40000)
	var seed_z: float = float(int(world_seed * 214013 + 2531011) % 40000)
	var fx: float = float(wx) + seed_x
	var fz: float = float(wz) + seed_z
	var warp_x: float = fx + sin(fz * 0.008) * 32.0
	var warp_z: float = fz + cos(fx * 0.008) * 32.0
	var t1: float = sin(warp_x * 0.0045 + cos(warp_z * 0.0035) * 1.5)
	var t2: float = cos(warp_z * 0.0085 + sin(warp_x * 0.0065)) * 0.5
	return clampf((t1 + t2 + 1.5) / 3.0, 0.0, 1.0)


## Continuous multi-scale Rainfall map [0.0..1.0] matching Minecraft Beta 1.7.3.
static func sample_rainfall(wx: int, wz: int, world_seed: int = 0) -> float:
	var seed_x: float = float(int((world_seed + 98765) * 22695477 + 1) % 40000)
	var seed_z: float = float(int((world_seed + 54321) * 3141592 + 101) % 40000)
	var fx: float = float(wx) + seed_x
	var fz: float = float(wz) + seed_z
	var warp_x: float = fx + cos(fz * 0.008) * 32.0
	var warp_z: float = fz + sin(fx * 0.008) * 32.0
	var r1: float = cos(warp_x * 0.0055 - warp_z * 0.0042)
	var r2: float = sin(warp_z * 0.0092 + cos(warp_x * 0.0070)) * 0.5
	return clampf((r1 + r2 + 1.5) / 3.0, 0.0, 1.0)


## Deterministic 2D climate biome sampler mapping (T, R) onto the 10 Beta biomes.
## Seeded per world so every seed produces unique, diverse climate and biome distributions.
static func sample_biome(wx: int, wz: int, world_seed: int = 0) -> int:
	var temp: float = sample_temperature(wx, wz, world_seed)
	var rain: float = sample_rainfall(wx, wz, world_seed)

	const BIOME_CENTROIDS: Array[Dictionary] = [
		{"biome": Biome.DESERT, "t": 0.90, "r": 0.10},
		{"biome": Biome.SAVANNA, "t": 0.80, "r": 0.22},
		{"biome": Biome.SHRUBLAND, "t": 0.65, "r": 0.25},
		{"biome": Biome.PLAINS, "t": 0.55, "r": 0.40},
		{"biome": Biome.FOREST, "t": 0.65, "r": 0.65},
		{"biome": Biome.SEASONAL_FOREST, "t": 0.50, "r": 0.75},
		{"biome": Biome.SWAMPLAND, "t": 0.38, "r": 0.82},
		{"biome": Biome.RAINFOREST, "t": 0.82, "r": 0.85},
		{"biome": Biome.TAIGA, "t": 0.20, "r": 0.65},
		{"biome": Biome.TUNDRA, "t": 0.18, "r": 0.25},
	]

	var closest_biome: int = Biome.PLAINS
	var min_dist_sq: float = 999999.0
	for entry in BIOME_CENTROIDS:
		var dt: float = temp - float(entry["t"])
		var dr: float = rain - float(entry["r"])
		var dist_sq: float = dt * dt + dr * dr
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			closest_biome = int(entry["biome"])

	return closest_biome


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
	cave_noise: FastNoiseLite,
	biome_hint: int = -1,
	below_carved: int = -1
) -> int:
	if ly < 0:
		return BlockRegistry.BlockId.AIR

	# Authentic Minecraft Beta 1.7.3 Bedrock Floor at bottom of world (y = 0..3)
	if ly == 0:
		return BlockRegistry.BlockId.BEDROCK
	if ly <= 3:
		var bedrock_hash: int = absi((wx * 310561) ^ (ly * 7919) ^ (wz * 15485863)) % 100
		if (ly == 1 and bedrock_hash < 75) or (ly == 2 and bedrock_hash < 50) or (ly == 3 and bedrock_hash < 25):
			return BlockRegistry.BlockId.BEDROCK

	if ly > surface_y:
		if ly <= WATER_LEVEL:
			# Water surface in cold biomes (Taiga, Tundra) freezes into solid Ice
			if ly == WATER_LEVEL:
				var b_at_surf: int = biome_hint
				if b_at_surf < 0:
					b_at_surf = sample_biome(wx, wz, (cave_noise.seed - 7919) if cave_noise != null else 0)
				if b_at_surf == Biome.TUNDRA or b_at_surf == Biome.TAIGA:
					return BlockRegistry.BlockId.ICE
			return BlockRegistry.BlockId.WATER
		return BlockRegistry.BlockId.AIR

	# Subterranean 3D Caves (cannot breach Bedrock at ly <= 3)
	if ly > 3 and _is_carved_cave_or_ravine(surface_y, wx, ly, wz, cave_noise):
		if ly <= 10:
			return BlockRegistry.BlockId.LAVA
		return BlockRegistry.BlockId.AIR

	# Rare glowing crystal clusters hanging from deep cavern ceilings
	if cave_noise != null and ly >= 10 and ly <= 30 and ly < surface_y - 7:
		var carved_below: bool = (below_carved == 1) if below_carved >= 0 else _is_carved_cave_or_ravine(surface_y, wx, ly - 1, wz, cave_noise)
		if carved_below:
			var glow_hash: int = absi((wx * 73856093) ^ (ly * 19349663) ^ (wz * 83492791)) % 1000
			if glow_hash < 6:
				return BlockRegistry.BlockId.GLOWSTONE

	# Low-lying basins and shorelines near/below water level generate sandy beaches
	if surface_y <= WATER_LEVEL + 1 and ly >= surface_y - 2:
		return BlockRegistry.BlockId.SAND

	var biome: int = biome_hint
	if biome < 0:
		biome = sample_biome(wx, wz, (cave_noise.seed - 7919) if cave_noise != null else 0)

	# 1. Desert: Sand surface (2 blocks) + Sandstone filler (4 blocks)
	if biome == Biome.DESERT and surface_y > WATER_LEVEL:
		if ly == surface_y or ly == surface_y - 1:
			return BlockRegistry.BlockId.SAND
		if ly >= surface_y - 5:
			return BlockRegistry.BlockId.SANDSTONE

	# 2. Tundra & Taiga: Snow surface layer + Dirt filler
	elif biome == Biome.TUNDRA or (biome == Biome.TAIGA and surface_y >= SEA_LEVEL + 4):
		if ly == surface_y:
			return BlockRegistry.BlockId.SNOW
		if ly >= surface_y - 3:
			return BlockRegistry.BlockId.DIRT

	# 3. Swampland: Clay deposits in shallow water basins, muddy grass on surface
	elif biome == Biome.SWAMPLAND:
		if surface_y <= WATER_LEVEL + 1 and ly >= surface_y - 2:
			return BlockRegistry.BlockId.CLAY
		if ly == surface_y:
			return BlockRegistry.BlockId.GRASS
		if ly >= surface_y - 3:
			return BlockRegistry.BlockId.DIRT

	# 4. Shrubland: Grass with subterranean and surface gravel patches
	elif biome == Biome.SHRUBLAND:
		var gravel_surf: int = absi((wx * 19349663) ^ (wz * 83492791)) % 100
		if ly == surface_y:
			return BlockRegistry.BlockId.GRAVEL if gravel_surf < 18 else BlockRegistry.BlockId.GRASS
		if ly >= surface_y - 3:
			return BlockRegistry.BlockId.DIRT

	# 5. High alpine mountain peaks & steep cliffs
	if surface_y >= SEA_LEVEL + 18:
		if ly == surface_y:
			return BlockRegistry.BlockId.SNOW
		if ly >= surface_y - 3 and surface_y >= SEA_LEVEL + 14:
			return BlockRegistry.BlockId.STONE
	elif surface_y >= SEA_LEVEL + 12:
		var crag_hash: int = absi((wx * 374761) ^ (wz * 668265)) % 100
		if crag_hash < 68 or surface_y >= SEA_LEVEL + 15:
			if ly >= surface_y - 3:
				return BlockRegistry.BlockId.STONE

	if ly == surface_y:
		return BlockRegistry.BlockId.GRASS
	if ly >= surface_y - 3:
		return BlockRegistry.BlockId.DIRT
	return _sample_underground_stone_or_ore(wx, ly, wz)


## Deterministically places Coal, Iron, Gold, Redstone, Lapis, Diamond, and Gravel ore clusters inside Stone strata.
static func _sample_underground_stone_or_ore(wx: int, ly: int, wz: int) -> int:
	var vx: int = wx >> 1
	var vy: int = ly >> 1
	var vz: int = wz >> 1
	var cell_hash: int = absi((vx * 73856093) ^ (vy * 19349663) ^ (vz * 83492791)) % 1000
	var sub_hash: int = absi((wx * 374761393) + (ly * 668265263) + (wz * 2147483647)) % 100

	# Sub-block irregular shape (roughly 68% of the 2x2x2 vein cell becomes ore)
	if sub_hash >= 68:
		return BlockRegistry.BlockId.STONE

	# Diamond Ore (y <= 16, ~0.8% of stone cells)
	if ly <= 16 and cell_hash < 8:
		return BlockRegistry.BlockId.DIAMOND_ORE

	# Redstone Ore (y <= 16, ~2.5% of stone cells)
	if ly <= 16 and cell_hash >= 8 and cell_hash < 33:
		return BlockRegistry.BlockId.REDSTONE_ORE

	# Lapis Lazuli Ore (peaks around y=14, spans y=4..30)
	if ly >= 4 and ly <= 30:
		var lapis_dist: int = absi(ly - 14)
		if lapis_dist <= 8 and cell_hash >= 33 and cell_hash < (33 + maxi(1, 10 - lapis_dist)):
			return BlockRegistry.BlockId.LAPIS_ORE

	# Gold Ore (y <= 32, ~1.8% of stone cells)
	if ly <= 32 and cell_hash >= 45 and cell_hash < 63:
		return BlockRegistry.BlockId.GOLD_ORE

	# Subterranean Gravel deposits (y <= 80, ~2.2% of cells)
	if ly <= 80 and cell_hash >= 65 and cell_hash < 87:
		return BlockRegistry.BlockId.GRAVEL

	# Iron Ore (y <= 64, ~4.5% of stone cells)
	if ly <= 64 and cell_hash >= 90 and cell_hash < 135:
		return BlockRegistry.BlockId.IRON_ORE

	# Coal Ore (y <= 128, ~7.0% of stone cells)
	if ly <= 128 and cell_hash >= 135 and cell_hash < 205:
		return BlockRegistry.BlockId.COAL_ORE

	return BlockRegistry.BlockId.STONE


func _try_place_sugar_cane(surface_noise: FastNoiseLite, lx: int, lz: int, wx: int, wz: int, ground_y: int) -> void:
	var ground_id: int = get_block_local(lx, ground_y, lz)
	if ground_id != BlockRegistry.BlockId.SAND and ground_id != BlockRegistry.BlockId.GRASS and ground_id != BlockRegistry.BlockId.DIRT:
		return

	# Clumps: only some 8x8 patches of shoreline grow cane, and roughly half the spots inside them.
	var patch_hash: int = absi(((wx >> 3) * 73856093) ^ ((wz >> 3) * 19349663) ^ 0x5bd1e995) % 100
	if patch_hash >= 40:
		return
	var spot_hash: int = absi((wx * 374761393) ^ (wz * 668265263)) % 1000
	if spot_hash >= 520:
		return

	var world_seed: int = surface_noise.seed if surface_noise != null else 0
	var biome: int = sample_biome(wx, wz, world_seed)
	if biome == Biome.TUNDRA or biome == Biome.TAIGA:
		return # Shore water is frozen there

	var has_water: bool = false
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if sample_surface_height(surface_noise, wx + d.x, wz + d.y) < WATER_LEVEL:
			has_water = true
			break
	if not has_water:
		return

	# Height 2..4, weighted toward short stalks (2: 61%, 3: 28%, 4: 11%).
	var h_roll: int = spot_hash % 18
	var cane_height: int = 2 if h_roll < 11 else (3 if h_roll < 16 else 4)
	for ch in range(1, cane_height + 1):
		_set_voxel_raw(lx, ground_y + ch, lz, BlockRegistry.BlockId.SUGAR_CANE)
	if ground_y + cane_height > _highest_solid_y:
		_highest_solid_y = ground_y + cane_height


func _should_spawn_tree(wx: int, wz: int, biome: int = Biome.PLAINS) -> bool:
	var hash_val: int = absi((wx * 73428767) ^ (wz * 912931)) % 1000
	match biome:
		Biome.RAINFOREST:
			return hash_val < 32
		Biome.FOREST, Biome.SEASONAL_FOREST:
			return hash_val < 22
		Biome.TAIGA:
			return hash_val < 18
		Biome.SWAMPLAND:
			return hash_val < 10
		Biome.DESERT:
			return hash_val < 7
		Biome.TUNDRA:
			return hash_val < 3
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
	var trunk_height: int = 7
	if base_y + trunk_height + 2 >= CHUNK_SIZE_Y:
		return

	for ty in range(base_y, base_y + trunk_height):
		_set_voxel_raw(lx, ty, lz, BlockRegistry.BlockId.PINE_LOG)

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
					_set_voxel_raw(cx, cy, cz, BlockRegistry.BlockId.PINE_LEAVES)

	# Spire on top of the pine tree
	var spire_y: int = base_y + 7
	if is_in_bounds(lx, spire_y, lz):
		_set_voxel_raw(lx, spire_y, lz, BlockRegistry.BlockId.PINE_LEAVES)
	if spire_y > _highest_solid_y:
		_highest_solid_y = spire_y


func _place_birch_tree(lx: int, base_y: int, lz: int) -> void:
	var trunk_height: int = 5 + ((absi(lx * 7 + lz * 13)) % 2)
	if base_y + trunk_height + 2 >= CHUNK_SIZE_Y:
		return

	for ty in range(base_y, base_y + trunk_height):
		_set_voxel_raw(lx, ty, lz, BlockRegistry.BlockId.BIRCH_LOG)

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
					_set_voxel_raw(cx, cy, cz, BlockRegistry.BlockId.BIRCH_LEAVES)

	if canopy_top > _highest_solid_y:
		_highest_solid_y = canopy_top


func _place_balloon_tree(lx: int, base_y: int, lz: int) -> void:
	var trunk_height: int = 6 + ((absi(lx * 11 + lz * 23)) % 3)
	if base_y + trunk_height + 3 >= CHUNK_SIZE_Y:
		return

	for ty in range(base_y, base_y + trunk_height):
		_set_voxel_raw(lx, ty, lz, BlockRegistry.BlockId.WOOD_LOG)

	# Spherical balloon canopy of radius 2 centered at trunk top (BalloonOakTree)
	var center_cy: int = base_y + trunk_height
	for cy in range(center_cy - 2, center_cy + 3):
		for cx in range(lx - 2, lx + 3):
			for cz in range(lz - 2, lz + 3):
				var dx: float = float(cx - lx)
				var dy: float = float(cy - center_cy)
				var dz: float = float(cz - lz)
				var d_sq: float = dx * dx + dy * dy + dz * dz
				if d_sq <= 5.8:
					if cx == lx and cz == lz and cy < base_y + trunk_height:
						continue
					if is_in_bounds(cx, cy, cz):
						_set_voxel_raw(cx, cy, cz, BlockRegistry.BlockId.LEAVES)

	if center_cy + 2 > _highest_solid_y:
		_highest_solid_y = center_cy + 2


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

	var world_seed: int = surface_noise.seed if surface_noise != null else 0
	var biome: int = sample_biome(center_wx, center_wz, world_seed)
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

	# Central Monster Spawner & authentic Beta dungeon loot chests inside dungeon
	if is_in_bounds(ox + 3, oy + 1, oz + 3):
		_set_voxel_raw(ox + 3, oy + 1, oz + 3, BlockRegistry.BlockId.MONSTER_SPAWNER)
	if is_in_bounds(ox + 1, oy + 1, oz + 3):
		_set_voxel_raw(ox + 1, oy + 1, oz + 3, BlockRegistry.BlockId.CHEST)
		generated_loot_chests.append(Vector3i(world_origin_x + ox + 1, oy + 1, world_origin_z + oz + 3))
	if is_in_bounds(ox + 5, oy + 1, oz + 3) and (seed_val % 2 == 0):
		_set_voxel_raw(ox + 5, oy + 1, oz + 3, BlockRegistry.BlockId.CHEST)
		generated_loot_chests.append(Vector3i(world_origin_x + ox + 5, oy + 1, world_origin_z + oz + 3))


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
						_set_meta_raw(lx, ly, lz, BlockRegistry.door_meta_from_dir(Vector3i(0, 0, 1), false))
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
	_set_voxel_raw(ox + 5, base_y + 1, oz + 4, BlockRegistry.BlockId.BED_HEAD)
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



# ============================================================================
# MESHING
# ============================================================================

## Highest sub-chunk index that can contain geometry.
func get_max_sub_index() -> int:
	return mini((_highest_solid_y + 1) / SUB_CHUNK_HEIGHT, SUB_CHUNK_COUNT - 1)


## Builds every non-empty sub-chunk. `nb_vox` / `nb_light` are 9-entry neighborhoods indexed
## `(dz + 1) * 3 + (dx + 1)` (entry 4 = this chunk). Thread-safe when given private buffer copies.
static func build_mesh_data_from(
	nb_vox: Array, nb_light: Array, meta: PackedByteArray, max_sub: int
) -> Dictionary:
	var sub_results: Array[Dictionary] = []
	var center: PackedByteArray = nb_vox[4]
	for sub_idx in range(SUB_CHUNK_COUNT):
		if sub_idx > max_sub or center.is_empty() or _sub_slice_is_air(center, sub_idx):
			sub_results.append({"mesh": null, "water_mesh": null, "shape": null})
			continue
		var padded: Array = ChunkMesher.build_padded(sub_idx, nb_vox, nb_light)
		sub_results.append(ChunkMesher.build_sub_chunk(sub_idx, padded, meta))
	return {"sub_chunks": sub_results}


static func _sub_slice_is_air(vox: PackedByteArray, sub_idx: int) -> bool:
	var start: int = sub_idx * 4096
	return vox.slice(start, start + 4096).count(0) == 4096


## Builds all sub-chunk meshes using only this chunk's own data (no neighbors loaded).
func build_mesh_data() -> Dictionary:
	if _lighting.is_empty():
		VoxelLighting.compute_chunk_lighting(self)
	var nb_vox: Array = _empty_neighborhood()
	var nb_light: Array = _empty_neighborhood()
	nb_vox[4] = _voxels
	nb_light[4] = _lighting
	return build_mesh_data_from(nb_vox, nb_light, _metadata, get_max_sub_index())


static func _empty_neighborhood() -> Array:
	var arr: Array = []
	for i in range(9):
		arr.append(PackedByteArray())
	return arr


## Builds one sub-chunk from the chunk's own data (kept for tools/tests).
func _build_single_sub_chunk_data(sub_idx: int) -> Dictionary:
	if _lighting.is_empty():
		VoxelLighting.compute_chunk_lighting(self)
	var nb_vox: Array = _empty_neighborhood()
	var nb_light: Array = _empty_neighborhood()
	nb_vox[4] = _voxels
	nb_light[4] = _lighting
	return ChunkMesher.build_sub_chunk(sub_idx, ChunkMesher.build_padded(sub_idx, nb_vox, nb_light), _metadata)


## Applies prebuilt sub-chunk meshes on the main thread. Collision shapes are only attached when
## collision is enabled for this chunk (near the player); otherwise they wait in `_pending_shapes`.
func apply_mesh_data(mesh_data: Dictionary) -> void:
	var sub_chunks: Array = mesh_data.get("sub_chunks", [])
	for sub_idx in range(mini(sub_chunks.size(), SUB_CHUNK_COUNT)):
		_apply_single_sub_chunk(sub_idx, sub_chunks[sub_idx])
	is_meshed = true
	_spawn_generated_contents()


func _spawn_generated_contents() -> void:
	if not is_inside_tree():
		return
	if not generated_loot_chests.is_empty():
		var inv := get_tree().get_first_node_in_group("inventory_manager") as InventoryManager
		if inv != null:
			for chest_pos in generated_loot_chests:
				var seed_val: int = absi((chest_pos.x * 73856093) ^ (chest_pos.y * 19349663) ^ (chest_pos.z * 83492791))
				inv.populate_loot_chest_at(chest_pos, seed_val)
			generated_loot_chests.clear()

	if not generated_villager_spawns.is_empty():
		var parent_node: Node = get_parent()
		if parent_node != null:
			for spawn_pos in generated_villager_spawns:
				if parent_node.has_method("queue_villager_spawn"):
					parent_node.queue_villager_spawn(spawn_pos)
				else:
					var villager := PassiveMob.new()
					villager.variant = PassiveMob.MobVariant.VILLAGER
					parent_node.add_child(villager)
					villager.global_position = spawn_pos
		generated_villager_spawns.clear()


## Marker meaning "no collision change pending" for a sub-chunk.
const NO_SHAPE_CHANGE: int = 0

## Per sub-chunk collision change waiting to be attached: NO_SHAPE_CHANGE, null (remove) or a Shape3D.
var _pending_shapes: Array = []
var _has_pending_shapes: bool = false
## Collision is attached only near the player; far chunks keep their shapes pending.
var collision_enabled: bool = true


func _apply_single_sub_chunk(sub_idx: int, sub_data: Dictionary, apply_water: bool = true) -> void:
	var m: ArrayMesh = sub_data.get("mesh", null) as ArrayMesh
	var mi: MeshInstance3D = _sub_meshes[sub_idx]
	if m != null and mi == null:
		mi = MeshInstance3D.new()
		mi.name = "SubMesh_%d" % sub_idx
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mi)
		_sub_meshes[sub_idx] = mi
	if mi != null:
		mi.mesh = m
		mi.visible = m != null

	var s: Shape3D = sub_data.get("shape", null) as Shape3D
	if collision_enabled:
		_set_sub_shape(sub_idx, s)
		if not _pending_shapes.is_empty():
			_pending_shapes[sub_idx] = NO_SHAPE_CHANGE
	else:
		if _pending_shapes.is_empty():
			_pending_shapes.resize(SUB_CHUNK_COUNT)
			_pending_shapes.fill(NO_SHAPE_CHANGE)
		_pending_shapes[sub_idx] = s
		_has_pending_shapes = true

	if apply_water:
		_apply_water_mesh(sub_idx, sub_data.get("water_mesh", null) as ArrayMesh)


func _set_sub_shape(sub_idx: int, s: Shape3D) -> void:
	var col: CollisionShape3D = _sub_cols[sub_idx]
	if s != null and col == null:
		col = CollisionShape3D.new()
		col.name = "SubCol_%d" % sub_idx
		add_child(col)
		_sub_cols[sub_idx] = col
	if col != null:
		col.shape = s
		col.disabled = s == null


## Enables collision and attaches pending sub-chunk shapes until `budget_usec` is used up.
## Returns true when nothing is left pending.
func attach_pending_collision(budget_usec: int) -> bool:
	collision_enabled = true
	if not _has_pending_shapes:
		return true
	var start: int = Time.get_ticks_usec()
	for sub_idx in range(SUB_CHUNK_COUNT):
		var pending: Variant = _pending_shapes[sub_idx]
		if typeof(pending) == TYPE_INT:
			continue
		_set_sub_shape(sub_idx, pending as Shape3D)
		_pending_shapes[sub_idx] = NO_SHAPE_CHANGE
		if Time.get_ticks_usec() - start > budget_usec:
			return false
	_has_pending_shapes = false
	return true



func _apply_water_mesh(sub_idx: int, wm: ArrayMesh) -> void:
	var wi: MeshInstance3D = _sub_water[sub_idx]
	if wm != null and wi == null:
		wi = MeshInstance3D.new()
		wi.name = "SubWater_%d" % sub_idx
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		wi.material_override = VoxelAtlasBuilder.get_shared_water_material()
		add_child(wi)
		_sub_water[sub_idx] = wi
	if wi != null:
		wi.mesh = wm
		wi.visible = wm != null


## Starts an async rebuild of one sub-chunk from prepared buffer slices; stale results are dropped.
## `job` holds "vox" / "light" (9-entry neighborhoods of y-sliced copies), "meta" and "y_origin".
func dispatch_sub_rebuild(sub_idx: int, job: Dictionary, water_only: bool) -> void:
	_water_versions[sub_idx] += 1
	if not water_only:
		_sub_versions[sub_idx] += 1
	var ver: int = _sub_versions[sub_idx]
	var water_ver: int = _water_versions[sub_idx]
	WorkerThreadPool.add_task(func() -> void:
		var padded: Array = ChunkMesher.build_padded(sub_idx, job["vox"], job["light"], int(job["y_origin"]))
		var data: Dictionary = ChunkMesher.build_sub_chunk(sub_idx, padded, job["meta"], water_only)
		_apply_versioned_sub_chunk.call_deferred(sub_idx, data, ver, water_ver, water_only)
	, false, "SubChunkMesh")


func _apply_versioned_sub_chunk(sub_idx: int, data: Dictionary, ver: int, water_ver: int, water_only: bool) -> void:
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	var water_fresh: bool = water_ver == _water_versions[sub_idx]
	if water_only:
		if water_fresh:
			_apply_water_mesh(sub_idx, data.get("water_mesh", null) as ArrayMesh)
		return
	if ver != _sub_versions[sub_idx]:
		return
	_apply_single_sub_chunk(sub_idx, data, water_fresh)


## Requests a remesh of the sub-chunk containing `ly` through the world (with neighbor data);
## a chunk that is not attached to a world skips it (it gets meshed when attached).
func rebuild_at_local_y(ly: int) -> void:
	var wm: Node = get_parent()
	if wm != null and wm.has_method("request_sub_remesh"):
		wm.request_sub_remesh(chunk_coords, clampi(ly / SUB_CHUNK_HEIGHT, 0, SUB_CHUNK_COUNT - 1))


func rebuild_at_local_y_async(ly: int) -> void:
	rebuild_at_local_y(ly)


func rebuild_water_at_local_y(ly: int) -> void:
	var wm: Node = get_parent()
	if wm != null and wm.has_method("request_sub_remesh"):
		wm.request_sub_remesh(chunk_coords, clampi(ly / SUB_CHUNK_HEIGHT, 0, SUB_CHUNK_COUNT - 1), true)


## Full chunk synchronous rebuild from the chunk's own data.
func rebuild_mesh() -> void:
	apply_mesh_data(build_mesh_data())


# ============================================================================
# DATA ACCESS
# ============================================================================

func ensure_lighting_buffer() -> void:
	if _lighting.is_empty():
		_lighting.resize(CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z)


func get_lighting_buffer() -> PackedByteArray:
	return _lighting


func get_sky_light_local(lx: int, ly: int, lz: int) -> int:
	if not is_in_bounds(lx, ly, lz):
		return 15
	if _lighting.is_empty():
		return 15 if ly >= _highest_solid_y else 0
	return (_lighting[_to_index(lx, ly, lz)] >> 4) & 0x0F


func set_sky_light_local(lx: int, ly: int, lz: int, val: int) -> void:
	if not is_in_bounds(lx, ly, lz):
		return
	ensure_lighting_buffer()
	var idx := _to_index(lx, ly, lz)
	_lighting[idx] = ((clampi(val, 0, 15) << 4) | (_lighting[idx] & 0x0F)) & 0xFF


func get_block_light_local(lx: int, ly: int, lz: int) -> int:
	if not is_in_bounds(lx, ly, lz) or _lighting.is_empty():
		return 0
	return _lighting[_to_index(lx, ly, lz)] & 0x0F


func set_block_light_local(lx: int, ly: int, lz: int, val: int) -> void:
	if not is_in_bounds(lx, ly, lz):
		return
	ensure_lighting_buffer()
	var idx := _to_index(lx, ly, lz)
	_lighting[idx] = ((_lighting[idx] & 0xF0) | clampi(val, 0, 15)) & 0xFF


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


## Writes metadata during generation without marking the chunk as player-modified.
func _set_meta_raw(lx: int, ly: int, lz: int, val: int) -> void:
	if not is_in_bounds(lx, ly, lz):
		return
	_ensure_metadata_buffer()
	var i: int = _to_index(lx, ly, lz)
	var byte_idx: int = i >> 1
	var b: int = _metadata[byte_idx]
	if (i & 1) == 0:
		b = (b & 0xF0) | (val & 0x0F)
	else:
		b = (b & 0x0F) | ((val & 0x0F) << 4)
	_metadata[byte_idx] = b


func _to_index(lx: int, ly: int, lz: int) -> int:
	return (ly * CHUNK_SIZE_Z + lz) * CHUNK_SIZE_X + lx
