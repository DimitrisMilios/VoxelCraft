class_name BlockRegistry
extends RefCounted
## Central registry for VoxelCraft block IDs, properties, colors, and texture atlas coordinates.

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
}

enum FaceDir {
	TOP = 0,
	BOTTOM = 1,
	EAST = 2,   # +X
	WEST = 3,   # -X
	SOUTH = 4,  # +Z
	NORTH = 5,  # -Z
}

## Atlas grid layout (11 tiles wide x 1 tile tall, each tile 16x16 pixels):
## Tile 0: Grass Top
## Tile 1: Grass Side (Dirt with grass top fringe)
## Tile 2: Dirt
## Tile 3: Stone
## Tile 4: Wood Log Side (Bark)
## Tile 5: Wood Log Top/Bottom (Rings)
## Tile 6: Leaves
## Tile 7: Sand
## Tile 8: Cobblestone
## Tile 9: Wood Planks
## Tile 10: Snow
const ATLAS_COLUMNS: int = 11
const ATLAS_ROWS: int = 1
const TILE_PIXEL_SIZE: int = 16


## Returns true if the block has solid collision and occludes adjacent solid block faces.
static func is_solid(block_id: int) -> bool:
	return block_id != BlockId.AIR and block_id != BlockId.WATER


## Returns true if the block is a swimmable liquid (e.g. Water).
static func is_liquid(block_id: int) -> bool:
	return block_id == BlockId.WATER


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
		_:
			return 3


static func get_tile_uv_rect(block_id: int, face_dir: int) -> Rect2:
	var tile_idx: int = get_tile_index(block_id, face_dir)
	var u_step: float = 1.0 / float(ATLAS_COLUMNS)
	# Small UV inset prevents texture bleeding across adjacent atlas tiles
	var uv_margin: float = 0.0015
	var u0: float = float(tile_idx) * u_step + uv_margin
	var v0: float = uv_margin
	var u_width: float = u_step - (uv_margin * 2.0)
	var v_height: float = 1.0 - (uv_margin * 2.0)
	return Rect2(u0, v0, u_width, v_height)
