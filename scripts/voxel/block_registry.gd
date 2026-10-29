class_name BlockRegistry
extends RefCounted
## Central registry for VoxelCraft block IDs, properties, hardness, colors, and texture atlas coordinates.

enum BlockId {
	AIR = 0,
	GRASS = 1,
	DIRT = 2,
	STONE = 3,
	WOOD_LOG = 4,
	LEAVES = 5,
	SAND = 6,
	COBBLESTONE = 7,
	WOOD_PLANKS = 8,
	WATER = 9,
	SNOW = 10,
	GLOWSTONE = 11,
	COAL_ORE = 12,
	IRON_ORE = 13,
	GOLD_ORE = 14,
	DIAMOND_ORE = 15,
	CRAFTING_TABLE = 16,
	FURNACE = 17,
	CHEST = 18,
	TORCH = 19,
	BED = 20,
	DOOR_CLOSED = 21,
	DOOR_OPEN = 22,
	LADDER = 23,
	TNT = 24,
	SANDSTONE = 25,
	CACTUS = 26,
	MOSSY_COBBLE = 27,
	WOOL = 28,
	FARMLAND = 29,
	WHEAT_CROPS = 30,
	WATER_FLOW_1 = 31,
	WATER_FLOW_2 = 32,
	WATER_FLOW_3 = 33,
	WATER_FLOW_4 = 34,
	WATER_FLOW_5 = 35,
	WATER_FLOW_6 = 36,
	WATER_FLOW_7 = 37,
	WATER_FALLING = 38,
	LAVA = 41,
	POTATO_CROPS = 42,
	OBSIDIAN = 43,
	SUGAR_CANE = 44,
	SEAGRASS = 45,
	BED_HEAD = 46,
	WHEAT_SPROUT = 47,
	POTATO_SPROUT = 48,
	GRAVEL = 49,
	CLAY = 50,
	ICE = 51,
	DANDELION = 52,
	ROSE = 53,
	BROWN_MUSHROOM = 54,
	RED_MUSHROOM = 55,
	PINE_LOG = 56,
	PINE_LEAVES = 57,
	BIRCH_LOG = 58,
	BIRCH_LEAVES = 59,
	MONSTER_SPAWNER = 60,
	BEDROCK = 61,
	REDSTONE_ORE = 62,
	LAPIS_ORE = 63,
	GOLD_BLOCK = 64,
	IRON_BLOCK = 65,
	DIAMOND_BLOCK = 66,
	LAPIS_BLOCK = 67,
	REDSTONE_TORCH = 68,
	LEVER = 69,
	BUTTON = 70,
	WOOD_STAIRS = 71,
	COBBLE_STAIRS = 72,
	SLAB = 73,
	SAPLING = 74,
	PINE_SAPLING = 75,
	BIRCH_SAPLING = 76,
	GLASS = 77,
}

const WOOL_COLORS: Array[Color] = [
	Color(0.95, 0.95, 0.95), # 0: White
	Color(0.89, 0.44, 0.16), # 1: Orange
	Color(0.74, 0.28, 0.72), # 2: Magenta
	Color(0.40, 0.54, 0.88), # 3: Light Blue
	Color(0.88, 0.78, 0.21), # 4: Yellow
	Color(0.47, 0.73, 0.13), # 5: Lime
	Color(0.86, 0.50, 0.62), # 6: Pink
	Color(0.30, 0.32, 0.34), # 7: Gray
	Color(0.61, 0.61, 0.58), # 8: Light Gray
	Color(0.18, 0.53, 0.60), # 9: Cyan
	Color(0.51, 0.22, 0.69), # 10: Purple
	Color(0.24, 0.31, 0.66), # 11: Blue
	Color(0.38, 0.25, 0.16), # 12: Brown
	Color(0.35, 0.47, 0.17), # 13: Green
	Color(0.67, 0.19, 0.18), # 14: Red
	Color(0.12, 0.12, 0.13), # 15: Black
]

enum FaceDir {
	TOP = 0,
	BOTTOM = 1,
	EAST = 2,   # +X
	WEST = 3,   # -X
	SOUTH = 4,  # +Z
	NORTH = 5,  # -Z
}

## How the chunk mesher draws a block.
enum RenderType {
	NONE = 0,         ## Air / not drawn
	CUBE = 1,         ## Full opaque cube (opaque surface)
	CUBE_CUTOUT = 2,  ## Full cube on the alpha-tested surface; faces between equal blocks are culled
	CROSS = 3,        ## Two diagonal quads (flowers, sugar cane, saplings)
	WATER = 4,        ## Sloped translucent water
	BOX = 5,          ## One or more custom boxes (stairs, slabs, doors, torches, beds...)
	CROP = 6,         ## Four vertical planes in a # pattern (wheat, potatoes)
}

## Tool categories that speed up mining (values match InventoryManager.ToolCategory).
const TOOL_NONE: int = 0
const TOOL_PICKAXE: int = 1
const TOOL_AXE: int = 2
const TOOL_SHOVEL: int = 3

## Atlas layout: one row of square tiles. The shipped atlas has 44 tiles; tiles past that are
## derived from existing tiles (or painted) at load time by VoxelAtlasBuilder.
const ATLAS_COLUMNS: int = 29
const ATLAS_ROWS: int = 1
const TILE_PIXEL_SIZE: int = 32
const ATLAS_TILE_COUNT: int = 79

const TILE_DOOR: int = 23
const TILE_PINE_LOG_TOP: int = 61
const TILE_BIRCH_LOG_TOP: int = 62
const TILE_OAK_SAPLING: int = 63
const TILE_PINE_SAPLING: int = 64
const TILE_BIRCH_SAPLING: int = 65
const TILE_GLASS: int = 66
const TILE_DOOR_TOP: int = 67
const TILE_DOOR_BOTTOM: int = 68
## Growth stages: wheat ages 0..6 use tiles 69..75 (age 7 is WHEAT_CROPS), potatoes 76..78.
const TILE_WHEAT_STAGE_0: int = 69
const TILE_POTATO_STAGE_0: int = 76
## Crops are sprout blocks with an age (0..6) in their metadata; one more growth step makes them mature.
const CROP_MAX_SPROUT_AGE: int = 6

## Actual column count of the loaded atlas (set by VoxelAtlasBuilder when the atlas loads).
static var atlas_columns: int = 0

## Extended per-face tiles fall back to these tiles if the atlas could not be extended.
const EXTENDED_TILE_FALLBACK: Dictionary = {
	29: 17, # Crafting Table Side -> Crafting Table Front
	30: 8,  # Furnace Side -> Cobblestone
	31: 3,  # Furnace Top -> Stone
	32: 25, # TNT Top -> TNT Side
	33: 25, # TNT Bottom -> TNT Side
	34: 26, # Sandstone Top -> Sandstone Side
	35: 28, # Cactus Top -> Cactus Side
	36: 0,  # Wool -> Grass
	37: 2,  # Farmland -> Dirt
	38: 0,  # Wheat -> Grass
	39: 0,  # Potato -> Grass
	44: 0,  # Wheat Sprout -> Grass
	45: 0,  # Potato Sprout -> Grass
	46: 8,  # Gravel -> Cobblestone
	47: 2,  # Clay -> Dirt
	48: 10, # Ice -> Snow
	49: 0,  # Dandelion -> Grass
	50: 0,  # Rose -> Grass
	51: 2,  # Brown Mushroom -> Dirt
	52: 0,  # Red Mushroom -> Grass
	53: 4,  # Pine Log Side -> Wood Log Side
	54: 6,  # Pine Leaves -> Leaves
	55: 4,  # Birch Log Side -> Wood Log Side
	56: 6,  # Birch Leaves -> Leaves
	57: 8,  # Monster Spawner -> Cobblestone
	58: 3,  # Bedrock -> Stone
	59: 13, # Redstone Ore -> Iron Ore
	60: 15, # Lapis Ore -> Diamond Ore
	61: 5,  # Pine Log Top -> Wood Log Top
	62: 5,  # Birch Log Top -> Wood Log Top
	63: 6,  # Oak Sapling -> Leaves
	64: 54, # Pine Sapling -> Pine Leaves
	65: 56, # Birch Sapling -> Birch Leaves
	66: 48, # Glass -> Ice
	67: 23, # Door Top -> combined door tile
	68: 23, # Door Bottom -> combined door tile
	69: 44, 70: 44, 71: 44, 72: 44, 73: 44, 74: 44, 75: 44, # Wheat stages -> Wheat Sprout
	76: 45, 77: 45, 78: 45, # Potato stages -> Potato Sprout
}


# ============================================================================
# FAST LOOKUP TABLES (indexed by block id, built once; used by the mesher and lighting)
# ============================================================================

static var render_type_table: PackedByteArray = _build_table(0)
## 1 if the block hides the faces of its neighbors (full opaque cubes, plus opaque-rendered leaves).
static var occluder_table: PackedByteArray = _build_table(1)
## How much light (0..15) a block removes when light passes through it.
static var light_opacity_table: PackedByteArray = _build_table(2)
## Light level (0..15) a block emits.
static var luminance_table: PackedByteArray = _build_table(3)
## (block_id << 7) | (meta << 3) | face -> atlas tile.
static var tile_table: PackedByteArray = _build_tile_table()


static func _build_table(kind: int) -> PackedByteArray:
	var arr := PackedByteArray()
	arr.resize(256)
	for id in range(256):
		match kind:
			0:
				arr[id] = _calc_render_type(id)
			1:
				arr[id] = _calc_occluder(id)
			2:
				arr[id] = _calc_light_opacity(id)
			_:
				arr[id] = _calc_luminance(id)
	return arr


static func _build_tile_table() -> PackedByteArray:
	var arr := PackedByteArray()
	arr.resize(256 * 128)
	for id in range(256):
		for meta in range(16):
			for face in range(6):
				arr[(id << 7) | (meta << 3) | face] = get_tile_index(id, face, meta)
	return arr


static func _calc_render_type(id: int) -> int:
	if id == BlockId.AIR:
		return RenderType.NONE
	if is_water(id):
		return RenderType.WATER
	match id:
		BlockId.SUGAR_CANE, BlockId.SEAGRASS, BlockId.DANDELION, BlockId.ROSE, BlockId.BROWN_MUSHROOM, BlockId.RED_MUSHROOM, BlockId.SAPLING, BlockId.PINE_SAPLING, BlockId.BIRCH_SAPLING:
			return RenderType.CROSS
		BlockId.WHEAT_CROPS, BlockId.POTATO_CROPS, BlockId.WHEAT_SPROUT, BlockId.POTATO_SPROUT:
			return RenderType.CROP
		BlockId.LAVA, BlockId.ICE, BlockId.MONSTER_SPAWNER, BlockId.GLASS:
			return RenderType.CUBE_CUTOUT
		BlockId.TORCH, BlockId.REDSTONE_TORCH, BlockId.SLAB, BlockId.LEVER, BlockId.BUTTON, BlockId.BED, BlockId.BED_HEAD, BlockId.DOOR_CLOSED, BlockId.DOOR_OPEN, BlockId.LADDER, BlockId.FARMLAND, BlockId.WOOD_STAIRS, BlockId.COBBLE_STAIRS, BlockId.CACTUS:
			return RenderType.BOX
	if id > BlockId.GLASS:
		return RenderType.NONE
	return RenderType.CUBE


static func _calc_occluder(id: int) -> int:
	if render_type_table.is_empty():
		return 0
	if render_type_table[id] == RenderType.CUBE:
		return 1
	return 0


static func _calc_light_opacity(id: int) -> int:
	if id == BlockId.AIR:
		return 0
	if is_water(id) or id == BlockId.ICE:
		return 2
	if id == BlockId.LEAVES or id == BlockId.PINE_LEAVES or id == BlockId.BIRCH_LEAVES:
		return 1
	if render_type_table.is_empty():
		return 0
	match render_type_table[id]:
		RenderType.CUBE:
			return 15
		RenderType.CUBE_CUTOUT:
			return 0 if (id == BlockId.LAVA or id == BlockId.GLASS) else 1
		_:
			return 0


static func _calc_luminance(id: int) -> int:
	match id:
		BlockId.LAVA, BlockId.GLOWSTONE:
			return 15
		BlockId.TORCH:
			return 14
		BlockId.REDSTONE_TORCH:
			return 7
		_:
			return 0


# ============================================================================
# CLASSIFICATION
# ============================================================================

static func is_solid(block_id: int) -> bool:
	return block_id != BlockId.AIR and not is_water(block_id) and not is_passable_block(block_id)


static func is_gravity_block(block_id: int) -> bool:
	return block_id == BlockId.SAND or block_id == BlockId.GRAVEL


static func is_passable_block(block_id: int) -> bool:
	return (
		block_id == BlockId.TORCH
		or block_id == BlockId.LADDER
		or block_id == BlockId.WHEAT_CROPS
		or block_id == BlockId.POTATO_CROPS
		or block_id == BlockId.WHEAT_SPROUT
		or block_id == BlockId.POTATO_SPROUT
		or block_id == BlockId.SUGAR_CANE
		or block_id == BlockId.SEAGRASS
		or block_id == BlockId.LAVA
		or block_id == BlockId.DANDELION
		or block_id == BlockId.ROSE
		or block_id == BlockId.BROWN_MUSHROOM
		or block_id == BlockId.RED_MUSHROOM
		or block_id == BlockId.REDSTONE_TORCH
		or block_id == BlockId.LEVER
		or block_id == BlockId.BUTTON
		or is_sapling(block_id)
	)


static func is_crop(block_id: int) -> bool:
	return (
		block_id == BlockId.WHEAT_CROPS
		or block_id == BlockId.POTATO_CROPS
		or block_id == BlockId.WHEAT_SPROUT
		or block_id == BlockId.POTATO_SPROUT
	)


static func is_log(block_id: int) -> bool:
	return block_id == BlockId.WOOD_LOG or block_id == BlockId.PINE_LOG or block_id == BlockId.BIRCH_LOG


static func is_leaves(block_id: int) -> bool:
	return block_id == BlockId.LEAVES or block_id == BlockId.PINE_LEAVES or block_id == BlockId.BIRCH_LEAVES


static func is_sapling(block_id: int) -> bool:
	return block_id == BlockId.SAPLING or block_id == BlockId.PINE_SAPLING or block_id == BlockId.BIRCH_SAPLING


static func is_door(block_id: int) -> bool:
	return block_id == BlockId.DOOR_CLOSED or block_id == BlockId.DOOR_OPEN


## True for blocks that pop off when the block underneath them is removed.
static func needs_support_below(block_id: int) -> bool:
	return (
		is_door(block_id)
		or is_crop(block_id)
		or is_sapling(block_id)
		or block_id == BlockId.SUGAR_CANE
		or block_id == BlockId.CACTUS
		or block_id == BlockId.TORCH
		or block_id == BlockId.REDSTONE_TORCH
		or block_id == BlockId.DANDELION
		or block_id == BlockId.ROSE
		or block_id == BlockId.BROWN_MUSHROOM
		or block_id == BlockId.RED_MUSHROOM
		or block_id == BlockId.LEVER
	)


static func is_opaque_full_cube(block_id: int) -> bool:
	return render_type_table[block_id & 0xFF] == RenderType.CUBE and not is_leaves(block_id)


## True if the block hides adjacent faces (full opaque cubes and the opaque-textured leaves).
static func is_occluder(block_id: int) -> bool:
	return occluder_table[block_id & 0xFF] == 1


static func is_liquid(block_id: int) -> bool:
	return (
		block_id == BlockId.WATER
		or (block_id >= BlockId.WATER_FLOW_1 and block_id <= BlockId.WATER_FALLING)
		or block_id == BlockId.LAVA
	)


## True for water source/flowing/falling blocks only (excludes Lava).
static func is_water(block_id: int) -> bool:
	return (
		block_id == BlockId.WATER
		or (block_id >= BlockId.WATER_FLOW_1 and block_id <= BlockId.WATER_FALLING)
	)


static func is_water_source(block_id: int) -> bool:
	return block_id == BlockId.WATER


## Returns water level from 0 (not water) to 8 (full Source or Falling waterfall).
static func get_water_level(block_id: int) -> int:
	if block_id == BlockId.WATER or block_id == BlockId.WATER_FALLING:
		return 8
	if block_id >= BlockId.WATER_FLOW_1 and block_id <= BlockId.WATER_FLOW_7:
		return block_id - BlockId.WATER_FLOW_1 + 1
	return 0


static func make_flowing_water_id(level: int) -> int:
	if level <= 0:
		return BlockId.AIR
	if level >= 8:
		return BlockId.WATER_FALLING
	return BlockId.WATER_FLOW_1 + clampi(level, 1, 7) - 1


## Returns normalized visual/physical height (0.0 to 1.0) of a water block at its center.
static func get_water_height_ratio(block_id: int) -> float:
	if block_id == BlockId.WATER_FALLING:
		return 1.0
	if block_id == BlockId.WATER or block_id == BlockId.LAVA:
		return 0.875
	if block_id >= BlockId.WATER_FLOW_1 and block_id <= BlockId.WATER_FLOW_7:
		var lvl: int = block_id - BlockId.WATER_FLOW_1 + 1
		return clampf(float(lvl) / 9.0, 0.11, 0.78)
	return 0.0


static func is_lava(block_id: int) -> bool:
	return block_id == BlockId.LAVA


static func is_light_emitter(block_id: int) -> bool:
	return luminance_table[block_id & 0xFF] > 0


static func get_luminance(block_id: int) -> int:
	return luminance_table[block_id & 0xFF]


static func is_interactive_station(block_id: int) -> bool:
	return (
		block_id == BlockId.CRAFTING_TABLE
		or block_id == BlockId.FURNACE
		or block_id == BlockId.CHEST
	)


static func is_stone_Or_ore(block_id: int) -> bool:
	return get_effective_tool(block_id) == TOOL_PICKAXE


# ============================================================================
# MINING
# ============================================================================

## Block hardness on the classic scale (stone = 1.5, obsidian = 50). 0 breaks instantly,
## -1 cannot be broken. Break time = hardness * 1.5 / tool speed (x5 without the right tool).
static func get_block_hardness(block_id: int) -> float:
	if is_liquid(block_id) or block_id == BlockId.AIR:
		return -1.0
	match block_id:
		BlockId.BEDROCK:
			return -1.0
		BlockId.TORCH, BlockId.REDSTONE_TORCH, BlockId.TNT, BlockId.WHEAT_CROPS, BlockId.POTATO_CROPS, BlockId.WHEAT_SPROUT, BlockId.POTATO_SPROUT, BlockId.SUGAR_CANE, BlockId.SEAGRASS, BlockId.DANDELION, BlockId.ROSE, BlockId.BROWN_MUSHROOM, BlockId.RED_MUSHROOM, BlockId.SAPLING, BlockId.PINE_SAPLING, BlockId.BIRCH_SAPLING:
			return 0.0
		BlockId.LEAVES, BlockId.PINE_LEAVES, BlockId.BIRCH_LEAVES, BlockId.SNOW, BlockId.BED, BlockId.BED_HEAD:
			return 0.2
		BlockId.GLOWSTONE, BlockId.GLASS:
			return 0.3
		BlockId.CACTUS, BlockId.LADDER:
			return 0.4
		BlockId.DIRT, BlockId.SAND, BlockId.ICE, BlockId.LEVER, BlockId.BUTTON:
			return 0.5
		BlockId.GRASS, BlockId.GRAVEL, BlockId.CLAY, BlockId.FARMLAND:
			return 0.6
		BlockId.SANDSTONE, BlockId.WOOL:
			return 0.8
		BlockId.STONE:
			return 1.5
		BlockId.COBBLESTONE, BlockId.MOSSY_COBBLE, BlockId.WOOD_LOG, BlockId.PINE_LOG, BlockId.BIRCH_LOG, BlockId.WOOD_PLANKS, BlockId.WOOD_STAIRS, BlockId.COBBLE_STAIRS, BlockId.SLAB:
			return 2.0
		BlockId.CRAFTING_TABLE, BlockId.CHEST:
			return 2.5
		BlockId.DOOR_CLOSED, BlockId.DOOR_OPEN, BlockId.COAL_ORE, BlockId.IRON_ORE, BlockId.GOLD_ORE, BlockId.DIAMOND_ORE, BlockId.REDSTONE_ORE, BlockId.LAPIS_ORE, BlockId.GOLD_BLOCK, BlockId.LAPIS_BLOCK:
			return 3.0
		BlockId.FURNACE:
			return 3.5
		BlockId.MONSTER_SPAWNER, BlockId.IRON_BLOCK, BlockId.DIAMOND_BLOCK:
			return 5.0
		BlockId.OBSIDIAN:
			return 50.0
		_:
			return 1.0


## Tool category that mines this block faster (TOOL_* constants).
static func get_effective_tool(block_id: int, meta: int = 0) -> int:
	match block_id:
		BlockId.STONE, BlockId.COBBLESTONE, BlockId.MOSSY_COBBLE, BlockId.SANDSTONE, BlockId.COAL_ORE, BlockId.IRON_ORE, BlockId.GOLD_ORE, BlockId.DIAMOND_ORE, BlockId.REDSTONE_ORE, BlockId.LAPIS_ORE, BlockId.FURNACE, BlockId.OBSIDIAN, BlockId.MONSTER_SPAWNER, BlockId.GOLD_BLOCK, BlockId.IRON_BLOCK, BlockId.DIAMOND_BLOCK, BlockId.LAPIS_BLOCK, BlockId.COBBLE_STAIRS, BlockId.BUTTON, BlockId.ICE, BlockId.BEDROCK:
			return TOOL_PICKAXE
		BlockId.SLAB:
			return TOOL_AXE if meta == 2 else TOOL_PICKAXE
		BlockId.WOOD_LOG, BlockId.PINE_LOG, BlockId.BIRCH_LOG, BlockId.WOOD_PLANKS, BlockId.CRAFTING_TABLE, BlockId.CHEST, BlockId.DOOR_CLOSED, BlockId.DOOR_OPEN, BlockId.LADDER, BlockId.WOOD_STAIRS:
			return TOOL_AXE
		BlockId.GRASS, BlockId.DIRT, BlockId.SAND, BlockId.GRAVEL, BlockId.CLAY, BlockId.SNOW, BlockId.FARMLAND:
			return TOOL_SHOVEL
		_:
			return TOOL_NONE


## Minimum pickaxe harvest level needed for the block to drop anything
## (-1 = no tool needed, 0 = wood/gold, 1 = stone, 2 = iron, 3 = diamond).
static func get_required_harvest_level(block_id: int, meta: int = 0) -> int:
	match block_id:
		BlockId.STONE, BlockId.COBBLESTONE, BlockId.MOSSY_COBBLE, BlockId.SANDSTONE, BlockId.COAL_ORE, BlockId.FURNACE, BlockId.MONSTER_SPAWNER, BlockId.COBBLE_STAIRS:
			return 0
		BlockId.SLAB:
			return -1 if meta == 2 else 0
		BlockId.IRON_ORE, BlockId.IRON_BLOCK, BlockId.LAPIS_ORE, BlockId.LAPIS_BLOCK:
			return 1
		BlockId.GOLD_ORE, BlockId.GOLD_BLOCK, BlockId.DIAMOND_ORE, BlockId.DIAMOND_BLOCK, BlockId.REDSTONE_ORE:
			return 2
		BlockId.OBSIDIAN:
			return 3
		_:
			return -1


# ============================================================================
# SHAPES (shared by the mesher, collision and the selection outline)
# ============================================================================

## Door metadata: bits 0-1 = facing (0 = +X, 1 = +Z, 2 = -X, 3 = -Z; the direction the player looked
## when placing it), bit 2 = hinge on the right. Open/closed is the block id; the upper half is the
## door block that has another door block below it.
static func door_facing_dir(meta: int) -> Vector3i:
	match meta & 3:
		0:
			return Vector3i(1, 0, 0)
		1:
			return Vector3i(0, 0, 1)
		2:
			return Vector3i(-1, 0, 0)
		_:
			return Vector3i(0, 0, -1)


static func door_meta_from_dir(dir: Vector3i, hinge_right: bool) -> int:
	var f: int = 0
	if dir == Vector3i(0, 0, 1):
		f = 1
	elif dir == Vector3i(-1, 0, 0):
		f = 2
	elif dir == Vector3i(0, 0, -1):
		f = 3
	return f | (4 if hinge_right else 0)


## Returns the boxes (in block-local 0..1 space) that make up a non-cube block.
static func get_shape_boxes(block_id: int, meta: int = 0) -> Array[AABB]:
	match block_id:
		BlockId.TORCH, BlockId.REDSTONE_TORCH:
			match meta:
				1: # West wall (-X): sticks flush against x=0
					return [AABB(Vector3(0.0, 0.22, 0.4375), Vector3(0.25, 0.625, 0.125))]
				2: # East wall (+X): sticks flush against x=1
					return [AABB(Vector3(0.75, 0.22, 0.4375), Vector3(0.25, 0.625, 0.125))]
				3: # North wall (-Z): sticks flush against z=0
					return [AABB(Vector3(0.4375, 0.22, 0.0), Vector3(0.125, 0.625, 0.25))]
				4: # South wall (+Z): sticks flush against z=1
					return [AABB(Vector3(0.4375, 0.22, 0.75), Vector3(0.125, 0.625, 0.25))]
				_: # Floor torch (meta 0 or 5)
					return [AABB(Vector3(0.4375, 0.0, 0.4375), Vector3(0.125, 0.625, 0.125))]
		BlockId.SLAB:
			return [AABB(Vector3.ZERO, Vector3(1.0, 0.5, 1.0))]
		BlockId.LEVER:
			return [AABB(Vector3(0.375, 0.0, 0.3125), Vector3(0.25, 0.6, 0.375))]
		BlockId.BUTTON:
			return [AABB(Vector3(0.3125, 0.375, 0.0), Vector3(0.375, 0.25, 0.125))]
		BlockId.BED, BlockId.BED_HEAD:
			return [AABB(Vector3.ZERO, Vector3(1.0, 0.5625, 1.0))]
		BlockId.LADDER:
			return [AABB(Vector3(0.0, 0.0, 0.4375), Vector3(1.0, 1.0, 0.125))]
		BlockId.FARMLAND:
			return [AABB(Vector3.ZERO, Vector3(1.0, 0.9375, 1.0))]
		BlockId.CACTUS:
			return [AABB(Vector3(0.0625, 0.0, 0.0625), Vector3(0.875, 1.0, 0.875))]
		BlockId.WOOD_STAIRS, BlockId.COBBLE_STAIRS:
			var step := AABB(Vector3(0.0, 0.5, 0.5), Vector3(1.0, 0.5, 0.5))
			match meta & 3:
				0: # Ascending toward +X
					step = AABB(Vector3(0.5, 0.5, 0.0), Vector3(0.5, 0.5, 1.0))
				1: # -X
					step = AABB(Vector3(0.0, 0.5, 0.0), Vector3(0.5, 0.5, 1.0))
				2: # +Z
					step = AABB(Vector3(0.0, 0.5, 0.5), Vector3(1.0, 0.5, 0.5))
				3: # -Z
					step = AABB(Vector3(0.0, 0.5, 0.0), Vector3(1.0, 0.5, 0.5))
			return [AABB(Vector3.ZERO, Vector3(1.0, 0.5, 1.0)), step]
		BlockId.DOOR_CLOSED, BlockId.DOOR_OPEN:
			return [get_door_box(meta, block_id == BlockId.DOOR_OPEN)]
		_:
			return [AABB(Vector3.ZERO, Vector3.ONE)]


## A closed door sits against the block edge nearest to the player who placed it; opening swings it
## 90 degrees around its hinge so it lies along the hinge-side edge.
static func get_door_box(meta: int, is_open: bool) -> AABB:
	const T: float = 3.0 / 16.0
	var f: Vector3i = door_facing_dir(meta)
	var edge: Vector3i = -f
	if is_open:
		var left := Vector3i(f.z, 0, -f.x)
		edge = -left if (meta & 4) != 0 else left
	if edge.x > 0:
		return AABB(Vector3(1.0 - T, 0.0, 0.0), Vector3(T, 1.0, 1.0))
	if edge.x < 0:
		return AABB(Vector3(0.0, 0.0, 0.0), Vector3(T, 1.0, 1.0))
	if edge.z > 0:
		return AABB(Vector3(0.0, 0.0, 1.0 - T), Vector3(1.0, 1.0, T))
	return AABB(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, T))


## Outline box used for the targeted-block highlight.
static func get_selection_box(block_id: int, meta: int = 0) -> AABB:
	match render_type_table[block_id & 0xFF]:
		RenderType.BOX:
			var boxes: Array[AABB] = get_shape_boxes(block_id, meta)
			var merged: AABB = boxes[0]
			for i in range(1, boxes.size()):
				merged = merged.merge(boxes[i])
			return merged
		RenderType.CROSS:
			if block_id == BlockId.SUGAR_CANE:
				return AABB(Vector3(0.125, 0.0, 0.125), Vector3(0.75, 1.0, 0.75))
			return AABB(Vector3(0.1875, 0.0, 0.1875), Vector3(0.625, 0.8125, 0.625))
		RenderType.CROP:
			if block_id == BlockId.WHEAT_SPROUT or block_id == BlockId.POTATO_SPROUT:
				return AABB(Vector3.ZERO, Vector3(1.0, 0.125 + 0.75 * float(mini(meta, CROP_MAX_SPROUT_AGE) + 1) / 8.0, 1.0))
			return AABB(Vector3.ZERO, Vector3(1.0, 0.875, 1.0))
		_:
			return AABB(Vector3.ZERO, Vector3.ONE)


# ============================================================================
# NAMES & COLORS
# ============================================================================

static func get_block_name(block_id: int) -> String:
	if block_id >= BlockId.WATER_FLOW_1 and block_id <= BlockId.WATER_FALLING:
		return "Flowing Water"
	match block_id:
		BlockId.AIR:
			return "Air"
		BlockId.GRASS:
			return "Grass"
		BlockId.DIRT:
			return "Dirt"
		BlockId.STONE:
			return "Stone"
		BlockId.WOOD_LOG:
			return "Oak Log"
		BlockId.LEAVES:
			return "Oak Leaves"
		BlockId.SAND:
			return "Sand"
		BlockId.COBBLESTONE:
			return "Cobble"
		BlockId.WOOD_PLANKS:
			return "Planks"
		BlockId.WATER:
			return "Water"
		BlockId.SNOW:
			return "Snow"
		BlockId.GLOWSTONE:
			return "Glowstone"
		BlockId.COAL_ORE:
			return "Coal Ore"
		BlockId.IRON_ORE:
			return "Iron Ore"
		BlockId.GOLD_ORE:
			return "Gold Ore"
		BlockId.DIAMOND_ORE:
			return "Diamond Ore"
		BlockId.CRAFTING_TABLE:
			return "Craft Table"
		BlockId.FURNACE:
			return "Furnace"
		BlockId.CHEST:
			return "Chest"
		BlockId.TORCH:
			return "Torch"
		BlockId.BED, BlockId.BED_HEAD:
			return "Bed"
		BlockId.DOOR_CLOSED, BlockId.DOOR_OPEN:
			return "Wood Door"
		BlockId.LADDER:
			return "Ladder"
		BlockId.TNT:
			return "TNT"
		BlockId.SANDSTONE:
			return "Sandstone"
		BlockId.CACTUS:
			return "Cactus"
		BlockId.MOSSY_COBBLE:
			return "Mossy Stone"
		BlockId.WOOL:
			return "White Wool"
		BlockId.FARMLAND:
			return "Farmland"
		BlockId.WHEAT_CROPS:
			return "Wheat"
		BlockId.POTATO_CROPS:
			return "Potatoes"
		BlockId.WHEAT_SPROUT:
			return "Wheat Sprout"
		BlockId.POTATO_SPROUT:
			return "Potato Sprout"
		BlockId.LAVA:
			return "Lava"
		BlockId.OBSIDIAN:
			return "Obsidian"
		BlockId.SUGAR_CANE:
			return "Sugar Cane"
		BlockId.SEAGRASS:
			return "Seagrass"
		BlockId.GRAVEL:
			return "Gravel"
		BlockId.CLAY:
			return "Clay"
		BlockId.ICE:
			return "Ice"
		BlockId.DANDELION:
			return "Dandelion"
		BlockId.ROSE:
			return "Rose"
		BlockId.BROWN_MUSHROOM:
			return "Brown Mushroom"
		BlockId.RED_MUSHROOM:
			return "Red Mushroom"
		BlockId.PINE_LOG:
			return "Spruce Log"
		BlockId.PINE_LEAVES:
			return "Spruce Leaves"
		BlockId.BIRCH_LOG:
			return "Birch Log"
		BlockId.BIRCH_LEAVES:
			return "Birch Leaves"
		BlockId.MONSTER_SPAWNER:
			return "Monster Spawner"
		BlockId.BEDROCK:
			return "Bedrock"
		BlockId.REDSTONE_ORE:
			return "Redstone Ore"
		BlockId.LAPIS_ORE:
			return "Lapis Lazuli Ore"
		BlockId.GOLD_BLOCK:
			return "Gold Block"
		BlockId.IRON_BLOCK:
			return "Iron Block"
		BlockId.DIAMOND_BLOCK:
			return "Diamond Block"
		BlockId.LAPIS_BLOCK:
			return "Lapis Lazuli Block"
		BlockId.REDSTONE_TORCH:
			return "Redstone Torch"
		BlockId.LEVER:
			return "Lever"
		BlockId.BUTTON:
			return "Stone Button"
		BlockId.WOOD_STAIRS:
			return "Wooden Stairs"
		BlockId.COBBLE_STAIRS:
			return "Cobblestone Stairs"
		BlockId.SLAB:
			return "Slab"
		BlockId.SAPLING:
			return "Oak Sapling"
		BlockId.PINE_SAPLING:
			return "Spruce Sapling"
		BlockId.BIRCH_SAPLING:
			return "Birch Sapling"
		BlockId.GLASS:
			return "Glass"
		_:
			return "Unknown"


static func get_block_color(block_id: int, meta: int = 0) -> Color:
	match block_id:
		BlockId.WOOL:
			return WOOL_COLORS[clampi(meta, 0, 15)]
		BlockId.GRASS:
			return Color(0.36, 0.71, 0.28)
		BlockId.DIRT:
			return Color(0.53, 0.36, 0.21)
		BlockId.STONE:
			return Color(0.52, 0.54, 0.56)
		BlockId.WOOD_LOG:
			return Color(0.41, 0.27, 0.14)
		BlockId.LEAVES:
			return Color(0.24, 0.56, 0.20)
		BlockId.SAND:
			return Color(0.86, 0.80, 0.54)
		BlockId.COBBLESTONE:
			return Color(0.42, 0.44, 0.46)
		BlockId.WOOD_PLANKS:
			return Color(0.68, 0.53, 0.31)
		BlockId.WATER, BlockId.WATER_FLOW_1, BlockId.WATER_FLOW_2, BlockId.WATER_FLOW_3, BlockId.WATER_FLOW_4, BlockId.WATER_FLOW_5, BlockId.WATER_FLOW_6, BlockId.WATER_FLOW_7, BlockId.WATER_FALLING:
			return Color(0.20, 0.52, 0.92)
		BlockId.SNOW:
			return Color(0.93, 0.96, 0.99)
		BlockId.GLOWSTONE:
			return Color(1.0, 0.84, 0.32)
		BlockId.COAL_ORE:
			return Color(0.24, 0.25, 0.27)
		BlockId.IRON_ORE:
			return Color(0.78, 0.58, 0.44)
		BlockId.GOLD_ORE:
			return Color(0.96, 0.82, 0.22)
		BlockId.DIAMOND_ORE:
			return Color(0.28, 0.92, 0.94)
		BlockId.CRAFTING_TABLE:
			return Color(0.62, 0.42, 0.22)
		BlockId.FURNACE:
			return Color(0.38, 0.40, 0.43)
		BlockId.CHEST:
			return Color(0.72, 0.48, 0.20)
		BlockId.TORCH:
			return Color(1.0, 0.78, 0.24)
		BlockId.BED, BlockId.BED_HEAD:
			return Color(0.86, 0.18, 0.22)
		BlockId.DOOR_CLOSED, BlockId.DOOR_OPEN:
			return Color(0.64, 0.46, 0.26)
		BlockId.LADDER:
			return Color(0.60, 0.44, 0.24)
		BlockId.TNT:
			return Color(0.90, 0.20, 0.18)
		BlockId.SANDSTONE:
			return Color(0.84, 0.76, 0.50)
		BlockId.CACTUS:
			return Color(0.18, 0.58, 0.22)
		BlockId.MOSSY_COBBLE:
			return Color(0.34, 0.52, 0.32)
		BlockId.FARMLAND:
			return Color(0.40, 0.26, 0.14)
		BlockId.WHEAT_CROPS:
			return Color(0.85, 0.78, 0.25)
		BlockId.POTATO_CROPS:
			return Color(0.35, 0.65, 0.25)
		BlockId.WHEAT_SPROUT:
			return Color(0.40, 0.78, 0.22)
		BlockId.POTATO_SPROUT:
			return Color(0.38, 0.72, 0.24)
		BlockId.LAVA:
			return Color(1.0, 0.38, 0.08)
		BlockId.OBSIDIAN:
			return Color(0.12, 0.08, 0.18)
		BlockId.SUGAR_CANE:
			return Color(0.58, 0.82, 0.35)
		BlockId.SEAGRASS:
			return Color(0.28, 0.72, 0.25)
		BlockId.GRAVEL:
			return Color(0.55, 0.52, 0.50)
		BlockId.CLAY:
			return Color(0.62, 0.65, 0.72)
		BlockId.ICE:
			return Color(0.60, 0.80, 0.95)
		BlockId.DANDELION:
			return Color(0.95, 0.88, 0.15)
		BlockId.ROSE:
			return Color(0.85, 0.12, 0.16)
		BlockId.BROWN_MUSHROOM:
			return Color(0.58, 0.44, 0.32)
		BlockId.RED_MUSHROOM:
			return Color(0.88, 0.20, 0.22)
		BlockId.PINE_LOG:
			return Color(0.28, 0.18, 0.10)
		BlockId.PINE_LEAVES:
			return Color(0.18, 0.38, 0.22)
		BlockId.BIRCH_LOG:
			return Color(0.88, 0.88, 0.84)
		BlockId.BIRCH_LEAVES:
			return Color(0.40, 0.68, 0.26)
		BlockId.MONSTER_SPAWNER:
			return Color(0.15, 0.28, 0.35)
		BlockId.BEDROCK:
			return Color(0.18, 0.18, 0.18)
		BlockId.REDSTONE_ORE:
			return Color(0.72, 0.15, 0.15)
		BlockId.LAPIS_ORE:
			return Color(0.15, 0.25, 0.70)
		BlockId.GOLD_BLOCK:
			return Color(0.96, 0.85, 0.25)
		BlockId.IRON_BLOCK:
			return Color(0.85, 0.85, 0.85)
		BlockId.DIAMOND_BLOCK:
			return Color(0.35, 0.95, 0.95)
		BlockId.LAPIS_BLOCK:
			return Color(0.12, 0.25, 0.72)
		BlockId.REDSTONE_TORCH:
			return Color(0.90, 0.15, 0.15)
		BlockId.LEVER:
			return Color(0.55, 0.45, 0.35)
		BlockId.BUTTON:
			return Color(0.52, 0.54, 0.56)
		BlockId.WOOD_STAIRS:
			return Color(0.68, 0.53, 0.31)
		BlockId.COBBLE_STAIRS:
			return Color(0.42, 0.44, 0.46)
		BlockId.SLAB:
			return Color(0.52, 0.54, 0.56)
		BlockId.SAPLING, BlockId.PINE_SAPLING, BlockId.BIRCH_SAPLING:
			return Color(0.30, 0.55, 0.20)
		BlockId.GLASS:
			return Color(0.80, 0.90, 0.95)
		_:
			return Color.GRAY


# ============================================================================
# TEXTURES
# ============================================================================

## Log metadata: bits 0-1 = axis (0 = vertical, 1 = along X, 2 = along Z).
static func log_end_faces_match(face_dir: int, axis: int) -> bool:
	match axis:
		1:
			return face_dir == FaceDir.EAST or face_dir == FaceDir.WEST
		2:
			return face_dir == FaceDir.SOUTH or face_dir == FaceDir.NORTH
		_:
			return face_dir == FaceDir.TOP or face_dir == FaceDir.BOTTOM


static func get_tile_index(block_id: int, face_dir: int, meta: int = 0) -> int:
	match block_id:
		BlockId.GRASS:
			if face_dir == FaceDir.TOP:
				return 0
			elif face_dir == FaceDir.BOTTOM:
				return 2
			else:
				return 1
		BlockId.DIRT:
			return 2
		BlockId.STONE:
			return 3
		BlockId.WOOD_LOG:
			return 5 if log_end_faces_match(face_dir, meta & 3) else 4
		BlockId.PINE_LOG:
			return TILE_PINE_LOG_TOP if log_end_faces_match(face_dir, meta & 3) else 53
		BlockId.BIRCH_LOG:
			return TILE_BIRCH_LOG_TOP if log_end_faces_match(face_dir, meta & 3) else 55
		BlockId.LEAVES:
			return 6
		BlockId.SAND:
			return 7
		BlockId.COBBLESTONE:
			return 8
		BlockId.WOOD_PLANKS:
			return 9
		BlockId.SNOW:
			return 10
		BlockId.GLOWSTONE:
			return 11
		BlockId.COAL_ORE:
			return 12
		BlockId.IRON_ORE:
			return 13
		BlockId.GOLD_ORE:
			return 14
		BlockId.DIAMOND_ORE:
			return 15
		BlockId.GOLD_BLOCK:
			return 14
		BlockId.IRON_BLOCK:
			return 13
		BlockId.DIAMOND_BLOCK:
			return 15
		BlockId.LAPIS_BLOCK:
			return 60
		BlockId.REDSTONE_TORCH:
			return 21
		BlockId.LEVER:
			return 8
		BlockId.BUTTON:
			return 3
		BlockId.WOOD_STAIRS:
			return 9
		BlockId.COBBLE_STAIRS:
			return 8
		BlockId.SLAB:
			if meta == 1:
				return 26 # Sandstone slab
			elif meta == 2:
				return 9  # Wood slab
			elif meta == 3:
				return 8  # Cobble slab
			return 3      # Stone slab
		BlockId.CRAFTING_TABLE:
			if face_dir == FaceDir.TOP:
				return 16
			elif face_dir == FaceDir.BOTTOM:
				return 9
			elif face_dir == FaceDir.EAST or face_dir == FaceDir.WEST:
				return 29
			else:
				return 17
		BlockId.FURNACE:
			if face_dir == FaceDir.TOP or face_dir == FaceDir.BOTTOM:
				return 31
			elif face_dir == FaceDir.SOUTH or face_dir == FaceDir.NORTH:
				return 18
			else:
				return 30
		BlockId.CHEST:
			if face_dir == FaceDir.SOUTH or face_dir == FaceDir.NORTH:
				return 19
			else:
				return 20
		BlockId.TORCH:
			return 21
		BlockId.BED, BlockId.BED_HEAD:
			return 22
		BlockId.DOOR_CLOSED, BlockId.DOOR_OPEN:
			return TILE_DOOR_BOTTOM # the mesher uses TILE_DOOR_TOP for the upper half
		BlockId.LADDER:
			return 24
		BlockId.TNT:
			if face_dir == FaceDir.TOP:
				return 32
			elif face_dir == FaceDir.BOTTOM:
				return 33
			else:
				return 25
		BlockId.SANDSTONE:
			if face_dir == FaceDir.TOP:
				return 34
			else:
				return 26
		BlockId.CACTUS:
			if face_dir == FaceDir.TOP or face_dir == FaceDir.BOTTOM:
				return 35
			else:
				return 28
		BlockId.MOSSY_COBBLE:
			return 27
		BlockId.WOOL:
			return 36
		BlockId.FARMLAND:
			if face_dir == FaceDir.TOP:
				return 37
			else:
				return 2
		BlockId.WHEAT_CROPS:
			return 38
		BlockId.POTATO_CROPS:
			return 39
		BlockId.WHEAT_SPROUT:
			return TILE_WHEAT_STAGE_0 + mini(meta, CROP_MAX_SPROUT_AGE)
		BlockId.POTATO_SPROUT:
			return TILE_POTATO_STAGE_0 + mini(meta, CROP_MAX_SPROUT_AGE) * 3 / 7
		BlockId.LAVA:
			return 40
		BlockId.OBSIDIAN:
			return 41
		BlockId.SUGAR_CANE:
			return 42
		BlockId.SEAGRASS:
			return 43
		BlockId.GRAVEL:
			return 46
		BlockId.CLAY:
			return 47
		BlockId.ICE:
			return 48
		BlockId.DANDELION:
			return 49
		BlockId.ROSE:
			return 50
		BlockId.BROWN_MUSHROOM:
			return 51
		BlockId.RED_MUSHROOM:
			return 52
		BlockId.PINE_LEAVES:
			return 54
		BlockId.BIRCH_LEAVES:
			return 56
		BlockId.MONSTER_SPAWNER:
			return 57
		BlockId.BEDROCK:
			return 58
		BlockId.REDSTONE_ORE:
			return 59
		BlockId.LAPIS_ORE:
			return 60
		BlockId.SAPLING:
			return TILE_OAK_SAPLING
		BlockId.PINE_SAPLING:
			return TILE_PINE_SAPLING
		BlockId.BIRCH_SAPLING:
			return TILE_BIRCH_SAPLING
		BlockId.GLASS:
			return TILE_GLASS
		_:
			return 3


## Atlas tile actually present in the loaded atlas (falls back if the atlas is narrower).
static func resolve_tile(tile_idx: int) -> int:
	var cols: int = atlas_columns if atlas_columns > 0 else ATLAS_TILE_COUNT
	var t: int = tile_idx
	var guard: int = 0
	while t >= cols and guard < 4:
		t = int(EXTENDED_TILE_FALLBACK.get(t, 3))
		guard += 1
	return t if t < cols else 3


static var _uv_rect_cache: Dictionary = {}

static func get_tile_uv_rect(block_id: int, face_dir: int, meta: int = 0) -> Rect2:
	var key: int = (block_id << 8) | (face_dir << 4) | (meta & 0x0F)
	if _uv_rect_cache.has(key):
		return _uv_rect_cache[key]

	if atlas_columns <= 0:
		VoxelAtlasBuilder.get_atlas_texture()
	var cols: int = maxi(atlas_columns, 1)
	var tile_idx: int = resolve_tile(get_tile_index(block_id, face_dir, meta))
	var u_step: float = 1.0 / float(cols)
	var uv_margin: float = u_step * 0.015
	var u0: float = float(tile_idx) * u_step + uv_margin
	var v0: float = uv_margin
	var u_width: float = u_step - (uv_margin * 2.0)
	var v_height: float = 1.0 - (uv_margin * 2.0)
	var rect := Rect2(u0, v0, u_width, v_height)
	_uv_rect_cache[key] = rect
	return rect
