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
	WATER_FLOW_1 = 31,
	WATER_FLOW_2 = 32,
	WATER_FLOW_3 = 33,
	WATER_FLOW_4 = 34,
	WATER_FLOW_5 = 35,
	WATER_FLOW_6 = 36,
	WATER_FLOW_7 = 37,
	WATER_FALLING = 38,
}

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
}


static func is_solid(block_id: int) -> bool:
	return block_id != BlockId.AIR and not is_liquid(block_id)


static func is_passable_block(block_id: int) -> bool:
	return (
		block_id == BlockId.TORCH
		or block_id == BlockId.DOOR_OPEN
		or block_id == BlockId.LADDER
	)


static func is_opaque_full_cube(block_id: int) -> bool:
	if not is_solid(block_id):
		return false
	if (
		block_id == BlockId.TORCH
		or block_id == BlockId.BED
		or block_id == BlockId.DOOR_CLOSED
		or block_id == BlockId.DOOR_OPEN
		or block_id == BlockId.LADDER
	):
		return false
	return true


static func is_liquid(block_id: int) -> bool:
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


static func is_light_emitter(block_id: int) -> bool:
	return block_id == BlockId.GLOWSTONE or block_id == BlockId.FURNACE or block_id == BlockId.TORCH


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
	)


## Base time in seconds to break this block by hand (reduced by equipped Pickaxe multiplier).
static func get_block_hardness(block_id: int) -> float:
	if is_liquid(block_id) or block_id == BlockId.AIR:
		return 0.0
	match block_id:
		BlockId.TORCH, BlockId.TNT:
			return 0.12
		BlockId.LEAVES, BlockId.SNOW, BlockId.CACTUS, BlockId.BED:
			return 0.24
		BlockId.GRASS, BlockId.DIRT, BlockId.SAND, BlockId.LADDER:
			return 0.38
		BlockId.WOOD_LOG, BlockId.WOOD_PLANKS, BlockId.CRAFTING_TABLE, BlockId.CHEST, BlockId.DOOR_CLOSED, BlockId.DOOR_OPEN, BlockId.GLOWSTONE:
			return 0.65
		BlockId.STONE, BlockId.COBBLESTONE, BlockId.MOSSY_COBBLE, BlockId.SANDSTONE, BlockId.COAL_ORE, BlockId.FURNACE:
			return 1.15
		BlockId.IRON_ORE:
			return 1.45
		BlockId.GOLD_ORE:
			return 1.75
		BlockId.DIAMOND_ORE:
			return 2.10
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
		BlockId.BED:
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
		_:
			return "Unknown"


static func get_block_color(block_id: int) -> Color:
	match block_id:
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
		BlockId.BED:
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
		_:
			return Color.GRAY


static func get_tile_index(block_id: int, face_dir: int) -> int:
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
			if face_dir == FaceDir.TOP or face_dir == FaceDir.BOTTOM:
				return 5
			else:
				return 4
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
		BlockId.BED:
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
		_:
			return 3


static func get_tile_uv_rect(block_id: int, face_dir: int) -> Rect2:
	if atlas_columns <= 0:
		VoxelAtlasBuilder.get_atlas_texture()
	var cols: int = maxi(atlas_columns, 1)
	var tile_idx: int = get_tile_index(block_id, face_dir)
	if tile_idx >= cols:
		tile_idx = int(EXTENDED_TILE_FALLBACK.get(tile_idx, 3))
	var u_step: float = 1.0 / float(cols)
	var uv_margin: float = u_step * 0.015
	var u0: float = float(tile_idx) * u_step + uv_margin
	var v0: float = uv_margin
	var u_width: float = u_step - (uv_margin * 2.0)
	var v_height: float = 1.0 - (uv_margin * 2.0)
	return Rect2(u0, v0, u_width, v_height)
