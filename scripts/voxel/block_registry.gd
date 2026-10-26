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

## Atlas grid layout (19 tiles wide x 1 tile tall, each tile 16x16 pixels):
## Tile 0: Grass Top
## Tile 1: Grass Side
## Tile 2: Dirt
## Tile 3: Stone
## Tile 4: Wood Log Side
## Tile 5: Wood Log Top
## Tile 6: Leaves
## Tile 7: Sand
## Tile 8: Cobblestone
## Tile 9: Wood Planks
## Tile 10: Snow
## Tile 11: Glowstone
## Tile 12: Coal Ore
## Tile 13: Iron Ore
## Tile 14: Gold Ore
## Tile 15: Diamond Ore
## Tile 16: Crafting Table Top (Grid)
## Tile 17: Crafting Table Side (Workbench Tools)
## Tile 18: Furnace Front (Stone Oven Opening & Embers)
## Default (repo) atlas layout: 29 tiles of 32x32 px. A local texture pack may supply a wider
## atlas (e.g. Faithful 64x: 36 tiles of 64x64 px with extra per-face tiles 29..35).
const ATLAS_COLUMNS: int = 29
const ATLAS_ROWS: int = 1
const TILE_PIXEL_SIZE: int = 32

## Actual column count of the loaded atlas (set by VoxelAtlasBuilder when the atlas loads).
static var atlas_columns: int = 0

## Extended per-face tiles (29..35) fall back to these tiles when the atlas is the 29-tile default.
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
}


static func is_solid(block_id: int) -> bool:
	return block_id != BlockId.AIR and not is_water(block_id) and not is_passable_block(block_id)


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
	)


static func is_crop(block_id: int) -> bool:
	return (
		block_id == BlockId.WHEAT_CROPS
		or block_id == BlockId.POTATO_CROPS
		or block_id == BlockId.WHEAT_SPROUT
		or block_id == BlockId.POTATO_SPROUT
	)


static func is_opaque_full_cube(block_id: int) -> bool:
	if not is_solid(block_id):
		return false
	if (
		block_id == BlockId.TORCH
		or block_id == BlockId.BED
		or block_id == BlockId.BED_HEAD
		or block_id == BlockId.DOOR_CLOSED
		or block_id == BlockId.DOOR_OPEN
		or block_id == BlockId.LADDER
		or block_id == BlockId.FARMLAND
		or block_id == BlockId.WHEAT_CROPS
		or block_id == BlockId.POTATO_CROPS
		or block_id == BlockId.WHEAT_SPROUT
		or block_id == BlockId.POTATO_SPROUT
		or block_id == BlockId.SUGAR_CANE
		or block_id == BlockId.SEAGRASS
		or block_id == BlockId.DANDELION
		or block_id == BlockId.ROSE
		or block_id == BlockId.BROWN_MUSHROOM
		or block_id == BlockId.RED_MUSHROOM
		or block_id == BlockId.ICE
		or block_id == BlockId.LEAVES
		or block_id == BlockId.PINE_LEAVES
		or block_id == BlockId.BIRCH_LEAVES
		or block_id == BlockId.MONSTER_SPAWNER
		or block_id == BlockId.WOOD_STAIRS
		or block_id == BlockId.COBBLE_STAIRS
		or block_id == BlockId.SLAB
		or block_id == BlockId.REDSTONE_TORCH
		or block_id == BlockId.LEVER
		or block_id == BlockId.BUTTON
	):
		return false
	return true


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
	if block_id == BlockId.WATER:
		return 0.875
	if block_id >= BlockId.WATER_FLOW_1 and block_id <= BlockId.WATER_FLOW_7:
		var lvl: int = block_id - BlockId.WATER_FLOW_1 + 1
		return clampf(float(lvl) / 9.0, 0.11, 0.78)
	return 0.0


static func is_lava(block_id: int) -> bool:
	return block_id == BlockId.LAVA


static func is_light_emitter(block_id: int) -> bool:
	return (
		block_id == BlockId.GLOWSTONE
		or block_id == BlockId.FURNACE
		or block_id == BlockId.TORCH
		or block_id == BlockId.LAVA
		or block_id == BlockId.REDSTONE_TORCH
	)


static func is_interactive_station(block_id: int) -> bool:
	return (
		block_id == BlockId.CRAFTING_TABLE
		or block_id == BlockId.FURNACE
		or block_id == BlockId.CHEST
	)


static func is_stone_Or_ore(block_id: int) -> bool:
	return (
		block_id == BlockId.STONE
		or block_id == BlockId.COBBLESTONE
		or block_id == BlockId.MOSSY_COBBLE
		or block_id == BlockId.SANDSTONE
		or block_id == BlockId.COAL_ORE
		or block_id == BlockId.IRON_ORE
		or block_id == BlockId.GOLD_ORE
		or block_id == BlockId.DIAMOND_ORE
		or block_id == BlockId.FURNACE
		or block_id == BlockId.OBSIDIAN
		or block_id == BlockId.REDSTONE_ORE
		or block_id == BlockId.LAPIS_ORE
		or block_id == BlockId.MONSTER_SPAWNER
		or block_id == BlockId.BEDROCK
		or block_id == BlockId.GOLD_BLOCK
		or block_id == BlockId.IRON_BLOCK
		or block_id == BlockId.DIAMOND_BLOCK
		or block_id == BlockId.LAPIS_BLOCK
		or block_id == BlockId.COBBLE_STAIRS
		or block_id == BlockId.SLAB
	)


## Base time in seconds to break this block by hand (reduced by equipped Pickaxe multiplier).
static func get_block_hardness(block_id: int) -> float:
	if is_liquid(block_id) or block_id == BlockId.AIR:
		return 0.0
	match block_id:
		BlockId.BEDROCK:
			return -1.0 # Indestructible in survival
		BlockId.DANDELION, BlockId.ROSE, BlockId.BROWN_MUSHROOM, BlockId.RED_MUSHROOM:
			return 0.05
		BlockId.TORCH, BlockId.TNT, BlockId.WHEAT_CROPS, BlockId.POTATO_CROPS, BlockId.SUGAR_CANE, BlockId.SEAGRASS, BlockId.REDSTONE_TORCH, BlockId.LEVER, BlockId.BUTTON:
			return 0.10
		BlockId.WHEAT_SPROUT, BlockId.POTATO_SPROUT:
			return 0.05
		BlockId.WOOL:
			return 0.35
		BlockId.FARMLAND, BlockId.GRAVEL, BlockId.CLAY:
			return 0.38
		BlockId.ICE:
			return 0.30
		BlockId.LEAVES, BlockId.PINE_LEAVES, BlockId.BIRCH_LEAVES, BlockId.SNOW, BlockId.CACTUS, BlockId.BED, BlockId.BED_HEAD:
			return 0.24
		BlockId.GRASS, BlockId.DIRT, BlockId.SAND, BlockId.LADDER:
			return 0.38
		BlockId.WOOD_LOG, BlockId.PINE_LOG, BlockId.BIRCH_LOG, BlockId.WOOD_PLANKS, BlockId.CRAFTING_TABLE, BlockId.CHEST, BlockId.DOOR_CLOSED, BlockId.DOOR_OPEN, BlockId.GLOWSTONE, BlockId.WOOD_STAIRS:
			return 0.65
		BlockId.STONE, BlockId.COBBLESTONE, BlockId.MOSSY_COBBLE, BlockId.SANDSTONE, BlockId.COAL_ORE, BlockId.FURNACE, BlockId.COBBLE_STAIRS, BlockId.SLAB:
			return 1.15
		BlockId.IRON_ORE, BlockId.REDSTONE_ORE, BlockId.LAPIS_ORE:
			return 1.45
		BlockId.GOLD_ORE:
			return 1.75
		BlockId.DIAMOND_ORE:
			return 2.10
		BlockId.MONSTER_SPAWNER:
			return 2.50
		BlockId.GOLD_BLOCK, BlockId.IRON_BLOCK, BlockId.DIAMOND_BLOCK, BlockId.LAPIS_BLOCK:
			return 3.00
		BlockId.OBSIDIAN:
			return 4.50
		_:
			return 0.5


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
			return "Wood Log"
		BlockId.LEAVES:
			return "Leaves"
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
			return "Pine Log"
		BlockId.PINE_LEAVES:
			return "Pine Leaves"
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
		BlockId.WOOL:
			return Color(0.95, 0.95, 0.95)
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
		_:
			return Color.GRAY


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
			if meta == 1:
				return 5 if (face_dir == FaceDir.TOP or face_dir == FaceDir.BOTTOM) else 53
			elif meta == 2:
				return 5 if (face_dir == FaceDir.TOP or face_dir == FaceDir.BOTTOM) else 55
			else:
				return 5 if (face_dir == FaceDir.TOP or face_dir == FaceDir.BOTTOM) else 4
		BlockId.LEAVES:
			if meta == 1:
				return 54
			elif meta == 2:
				return 56
			else:
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
			return 23
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
			return 44
		BlockId.POTATO_SPROUT:
			return 45
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
		BlockId.PINE_LOG:
			if face_dir == FaceDir.TOP or face_dir == FaceDir.BOTTOM:
				return 5
			else:
				return 53
		BlockId.PINE_LEAVES:
			return 54
		BlockId.BIRCH_LOG:
			if face_dir == FaceDir.TOP or face_dir == FaceDir.BOTTOM:
				return 5
			else:
				return 55
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
		_:
			return 3


static func get_tile_uv_rect(block_id: int, face_dir: int, meta: int = 0) -> Rect2:
	if atlas_columns <= 0:
		VoxelAtlasBuilder.get_atlas_texture()
	var cols: int = maxi(atlas_columns, 1)
	var tile_idx: int = get_tile_index(block_id, face_dir, meta)
	if tile_idx >= cols:
		tile_idx = int(EXTENDED_TILE_FALLBACK.get(tile_idx, 3))
	var u_step: float = 1.0 / float(cols)
	var uv_margin: float = u_step * 0.015
	var u0: float = float(tile_idx) * u_step + uv_margin
	var v0: float = uv_margin
	var u_width: float = u_step - (uv_margin * 2.0)
	var v_height: float = 1.0 - (uv_margin * 2.0)
	return Rect2(u0, v0, u_width, v_height)
