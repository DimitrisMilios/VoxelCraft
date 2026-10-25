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
const ATLAS_COLUMNS: int = 19
const ATLAS_ROWS: int = 1
const TILE_PIXEL_SIZE: int = 16


static func is_solid(block_id: int) -> bool:
	return block_id != BlockId.AIR and block_id != BlockId.WATER


static func is_liquid(block_id: int) -> bool:
	return block_id == BlockId.WATER


static func is_light_emitter(block_id: int) -> bool:
	return block_id == BlockId.GLOWSTONE or block_id == BlockId.FURNACE


static func is_interactive_station(block_id: int) -> bool:
	return block_id == BlockId.CRAFTING_TABLE or block_id == BlockId.FURNACE


static func is_stone_Or_ore(block_id: int) -> bool:
	return (
		block_id == BlockId.STONE
		or block_id == BlockId.COBBLESTONE
		or block_id == BlockId.COAL_ORE
		or block_id == BlockId.IRON_ORE
		or block_id == BlockId.GOLD_ORE
		or block_id == BlockId.DIAMOND_ORE
		or block_id == BlockId.FURNACE
	)


## Base time in seconds to break this block by hand (reduced by equipped Pickaxe multiplier).
static func get_block_hardness(block_id: int) -> float:
	match block_id:
		BlockId.AIR, BlockId.WATER:
			return 0.0
		BlockId.LEAVES, BlockId.SNOW:
			return 0.22
		BlockId.GRASS, BlockId.DIRT, BlockId.SAND:
			return 0.38
		BlockId.WOOD_LOG, BlockId.WOOD_PLANKS, BlockId.CRAFTING_TABLE, BlockId.GLOWSTONE:
			return 0.65
		BlockId.STONE, BlockId.COBBLESTONE, BlockId.COAL_ORE, BlockId.FURNACE:
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
		BlockId.WATER:
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
			else:
				return 17
		BlockId.FURNACE:
			if face_dir == FaceDir.TOP or face_dir == FaceDir.BOTTOM:
				return 3
			elif face_dir == FaceDir.SOUTH or face_dir == FaceDir.NORTH:
				return 18
			else:
				return 8
		_:
			return 3


static func get_tile_uv_rect(block_id: int, face_dir: int) -> Rect2:
	var tile_idx: int = get_tile_index(block_id, face_dir)
	var u_step: float = 1.0 / float(ATLAS_COLUMNS)
	var uv_margin: float = 0.0012
	var u0: float = float(tile_idx) * u_step + uv_margin
	var v0: float = uv_margin
	var u_width: float = u_step - (uv_margin * 2.0)
	var v_height: float = 1.0 - (uv_margin * 2.0)
	return Rect2(u0, v0, u_width, v_height)
