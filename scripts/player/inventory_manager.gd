class_name InventoryManager
extends Node
const GameSession = preload("res://scripts/core/game_session.gd")
## Authentic Minecraft-style 36-slot inventory (9 hotbar + 27 backpack),
## cursor item stack manipulation (Left-Click full stack, Right-Click single item),
## 2x2 (Player Inventory) & 3x3 (Crafting Table) shaped/shapeless pattern matching,
## and real-time ticked Furnace (Oven) smelting.

signal inventory_updated()
signal furnace_updated()

const HOTBAR_SIZE: int = 9
const BACKPACK_SIZE: int = 27
const TOTAL_SLOTS: int = 36 # 0..8 = Hotbar, 9..35 = Backpack
const MAX_STACK: int = 64

enum ItemId {
	# Crafting & Ore Resources (100+)
	STICK = 100,
	COAL = 101,
	RAW_IRON = 102,
	IRON_INGOT = 103,
	RAW_GOLD = 104,
	GOLD_INGOT = 105,
	DIAMOND = 106,
	BUCKET = 107,
	WATER_BUCKET = 108,
	RAW_PORKCHOP = 110,
	COOKED_PORKCHOP = 111,
	RAW_BEEF = 112,
	STEAK = 113,
	APPLE = 114,
	ROTTEN_FLESH = 115,
	GUNPOWDER = 116,
	WOOL = 117,
	WHEAT_SEEDS = 118,
	WHEAT = 119,
	BREAD = 120,
	POTATO = 121,
	BAKED_POTATO = 122,
	LAVA_BUCKET = 123,
	SHEARS = 124,

	# Pickaxes (201..204)
	WOOD_PICKAXE = 201,
	STONE_PICKAXE = 202,
	IRON_PICKAXE = 203,
	DIAMOND_PICKAXE = 204,

	# Axes (211..214)
	WOOD_AXE = 211,
	STONE_AXE = 212,
	IRON_AXE = 213,
	DIAMOND_AXE = 214,

	# Shovels (221..224)
	WOOD_SHOVEL = 221,
	STONE_SHOVEL = 222,
	IRON_SHOVEL = 223,
	DIAMOND_SHOVEL = 224,

	# Swords (231..234)
	WOOD_SWORD = 231,
	STONE_SWORD = 232,
	IRON_SWORD = 233,
	DIAMOND_SWORD = 234,
}

enum ToolCategory {
	NONE = 0,
	PICKAXE = 1,
	AXE = 2,
	SHOVEL = 3,
	SWORD = 4,
}

## 36 inventory slots (`0..8` hotbar, `9..35` main inventory). Each slot is `{"id": int, "count": int}`.
var slots: Array[Dictionary] = []

## Item stack currently held on the mouse cursor while inventory/crafting/furnace UI is open.
var cursor_stack: Dictionary = {"id": 0, "count": 0}

## Active crafting grid slots (`4` slots when 2x2 inventory is open, `9` slots when 3x3 Crafting Table is open).
var craft_grid_size: int = 2 # 2 for 2x2, 3 for 3x3
var craft_grid: Array[Dictionary] = []
var craft_output: Dictionary = {"id": 0, "count": 0}

## Real-time Furnace (Oven) slots & state.
var furnace_input: Dictionary = {"id": 0, "count": 0}
var furnace_fuel: Dictionary = {"id": 0, "count": 0}
var furnace_output: Dictionary = {"id": 0, "count": 0}
var furnace_burn_remaining: float = 0.0
var furnace_burn_max: float = 10.0
var furnace_cook_progress: float = 0.0
const FURNACE_COOK_TIME: float = 3.0
const CHEST_SIZE: int = 27

## World-coordinate persistent 27-slot Chest storage (`Vector3i -> Array[Dictionary]`).
var world_chests: Dictionary = {}
var active_chest_pos: Vector3i = Vector3i.ZERO
static var _icon_cache: Dictionary = {}
static var _ui_tex_cache: Dictionary = {}


static func load_ui_texture(res_path: String) -> Texture2D:
	if _ui_tex_cache.has(res_path):
		return _ui_tex_cache[res_path]
	var path: String = TexturePack.resolve_res_path(res_path)
	if ResourceLoader.exists(path):
		var r_tex := ResourceLoader.load(path) as Texture2D
		if r_tex != null:
			_ui_tex_cache[res_path] = r_tex
			return r_tex
	if path != res_path and ResourceLoader.exists(res_path):
		var r_tex := ResourceLoader.load(res_path) as Texture2D
		if r_tex != null:
			_ui_tex_cache[res_path] = r_tex
			return r_tex
	var img: Image = TexturePack.load_image(res_path)
	if img != null and not img.is_empty():
		var tex := ImageTexture.create_from_image(img)
		_ui_tex_cache[res_path] = tex
		return tex
	_ui_tex_cache[res_path] = null
	return null


static func get_item_icon_texture(item_id: int) -> Texture2D:
	if item_id <= 0:
		return null
	var lookup_id: int = item_id
	if lookup_id == BlockRegistry.BlockId.DOOR_OPEN:
		lookup_id = BlockRegistry.BlockId.DOOR_CLOSED
	elif lookup_id == BlockRegistry.BlockId.BED_HEAD:
		lookup_id = BlockRegistry.BlockId.BED
	elif BlockRegistry.is_liquid(lookup_id):
		lookup_id = BlockRegistry.BlockId.WATER
	if _icon_cache.has(lookup_id):
		return _icon_cache[lookup_id]
	var path: String = "res://assets/ui/item_icons/item_%d.png" % lookup_id
	var tex: Texture2D = load_ui_texture(path)
	_icon_cache[lookup_id] = tex
	return tex


func _init() -> void:
	slots.resize(TOTAL_SLOTS)
	for i in range(TOTAL_SLOTS):
		slots[i] = {"id": 0, "count": 0}


func _ready() -> void:
	add_to_group("inventory_manager")
	if slots.size() < TOTAL_SLOTS:
		slots.resize(TOTAL_SLOTS)
		for i in range(TOTAL_SLOTS):
			slots[i] = {"id": 0, "count": 0}

	set_crafting_grid_dimension(2)

	if not GameSession.active_world_data.is_empty():
		var inv_data: Dictionary = GameSession.active_world_data.get("inventory", {})
		if not inv_data.is_empty():
			deserialize_state(inv_data)
		var chests_data: Dictionary = GameSession.active_world_data.get("world_chests", {})
		if not chests_data.is_empty():
			deserialize_chests(chests_data)


func serialize_state() -> Dictionary:
	return {
		"slots": slots.duplicate(true),
		"furnace_input": furnace_input.duplicate(true),
		"furnace_fuel": furnace_fuel.duplicate(true),
		"furnace_output": furnace_output.duplicate(true),
		"furnace_burn_remaining": furnace_burn_remaining,
		"furnace_burn_max": furnace_burn_max,
		"furnace_cook_progress": furnace_cook_progress,
	}


func deserialize_state(data: Dictionary) -> void:
	if data.has("slots") and data["slots"] is Array:
		var loaded_slots: Array = data["slots"]
		for i in range(mini(TOTAL_SLOTS, loaded_slots.size())):
			if loaded_slots[i] is Dictionary:
				slots[i] = {
					"id": int(loaded_slots[i].get("id", 0)),
					"count": int(loaded_slots[i].get("count", 0)),
				}
	if data.has("furnace_input") and data["furnace_input"] is Dictionary:
		furnace_input = {
			"id": int(data["furnace_input"].get("id", 0)),
			"count": int(data["furnace_input"].get("count", 0)),
		}
	if data.has("furnace_fuel") and data["furnace_fuel"] is Dictionary:
		furnace_fuel = {
			"id": int(data["furnace_fuel"].get("id", 0)),
			"count": int(data["furnace_fuel"].get("count", 0)),
		}
	if data.has("furnace_output") and data["furnace_output"] is Dictionary:
		furnace_output = {
			"id": int(data["furnace_output"].get("id", 0)),
			"count": int(data["furnace_output"].get("count", 0)),
		}
	furnace_burn_remaining = float(data.get("furnace_burn_remaining", 0.0))
	furnace_burn_max = float(data.get("furnace_burn_max", 10.0))
	furnace_cook_progress = float(data.get("furnace_cook_progress", 0.0))
	inventory_updated.emit()
	furnace_updated.emit()


func serialize_chests() -> Dictionary:
	var result: Dictionary = {}
	for c_pos in world_chests.keys():
		var key_str: String = "%d,%d,%d" % [c_pos.x, c_pos.y, c_pos.z]
		result[key_str] = (world_chests[c_pos] as Array).duplicate(true)
	return result


func deserialize_chests(chests_data: Dictionary) -> void:
	world_chests.clear()
	for key_str in chests_data.keys():
		var parts: PackedStringArray = str(key_str).split(",")
		if parts.size() == 3:
			var c_pos := Vector3i(parts[0].to_int(), parts[1].to_int(), parts[2].to_int())
			var c_slots: Array = []
			var raw_slots: Array = chests_data[key_str]
			for item in raw_slots:
				if item is Dictionary:
					c_slots.append({
						"id": int(item.get("id", 0)),
						"count": int(item.get("count", 0)),
					})
			while c_slots.size() < CHEST_SIZE:
				c_slots.append({"id": 0, "count": 0})
			world_chests[c_pos] = c_slots


func _process(delta: float) -> void:
	_tick_furnace(delta)


## Sets crafting grid to 2x2 (4 slots, Player Inventory E) or 3x3 (9 slots, Crafting Table).
func set_crafting_grid_dimension(dim: int) -> void:
	# Return any items currently inside the crafting grid back to the player's inventory first
	return_crafting_grid_to_inventory()
	craft_grid_size = 3 if dim == 3 else 2
	var cell_count: int = craft_grid_size * craft_grid_size
	craft_grid.resize(cell_count)
	for i in range(cell_count):
		craft_grid[i] = {"id": 0, "count": 0}
	craft_output = {"id": 0, "count": 0}
	inventory_updated.emit()


## Returns any items left in the crafting grid or on the mouse cursor back into the inventory when closing UI.
func return_crafting_grid_to_inventory() -> void:
	for i in range(craft_grid.size()):
		var entry: Dictionary = craft_grid[i]
		if int(entry.get("id", 0)) != 0 and int(entry.get("count", 0)) > 0:
			add_item(int(entry["id"]), int(entry["count"]))
			craft_grid[i] = {"id": 0, "count": 0}

	if int(cursor_stack.get("id", 0)) != 0 and int(cursor_stack.get("count", 0)) > 0:
		add_item(int(cursor_stack["id"]), int(cursor_stack["count"]))
		cursor_stack = {"id": 0, "count": 0}

	craft_output = {"id": 0, "count": 0}
	inventory_updated.emit()


# ============================================================================
# TOOL & ITEM CLASSIFICATION HELPERS
# ============================================================================

static func is_tool_item(item_id: int) -> bool:
	return (item_id >= ItemId.WOOD_PICKAXE and item_id <= ItemId.DIAMOND_SWORD) or item_id == ItemId.WATER_BUCKET


static func is_food_item(item_id: int) -> bool:
	return (
		(item_id >= ItemId.RAW_PORKCHOP and item_id <= ItemId.ROTTEN_FLESH)
		or item_id == ItemId.BREAD
		or item_id == ItemId.POTATO
		or item_id == ItemId.BAKED_POTATO
	)


static func get_food_nutrition(item_id: int) -> int:
	match item_id:
		ItemId.COOKED_PORKCHOP, ItemId.STEAK:
			return 8
		ItemId.BREAD, ItemId.BAKED_POTATO:
			return 5
		ItemId.APPLE:
			return 4
		ItemId.RAW_PORKCHOP, ItemId.RAW_BEEF:
			return 3
		ItemId.ROTTEN_FLESH:
			return 2
		ItemId.POTATO:
			return 1
		_:
			return 0


static func get_attack_damage(item_id: int) -> int:
	var cat: int = get_tool_category(item_id)
	var tier: int = get_tool_tier(item_id)
	if cat == ToolCategory.SWORD:
		return 3 + tier # Wood=4, Stone=5, Iron=6, Diamond=7
	if cat != ToolCategory.NONE:
		return 1 + tier
	return 2 # Bare fist


static func is_placeable_block(item_id: int) -> bool:
	return item_id > 0 and item_id < 100 and not BlockRegistry.is_liquid(item_id) and item_id != BlockRegistry.BlockId.BED_HEAD


static func get_tool_category(item_id: int) -> int:
	if item_id >= ItemId.WOOD_PICKAXE and item_id <= ItemId.DIAMOND_PICKAXE:
		return ToolCategory.PICKAXE
	if item_id >= ItemId.WOOD_AXE and item_id <= ItemId.DIAMOND_AXE:
		return ToolCategory.AXE
	if item_id >= ItemId.WOOD_SHOVEL and item_id <= ItemId.DIAMOND_SHOVEL:
		return ToolCategory.SHOVEL
	if item_id >= ItemId.WOOD_SWORD and item_id <= ItemId.DIAMOND_SWORD:
		return ToolCategory.SWORD
	return ToolCategory.NONE


## Returns tool tier: 0 = Hand/None, 1 = Wood, 2 = Stone, 3 = Iron, 4 = Diamond.
static func get_tool_tier(item_id: int) -> int:
	match item_id:
		ItemId.WOOD_PICKAXE, ItemId.WOOD_AXE, ItemId.WOOD_SHOVEL, ItemId.WOOD_SWORD:
			return 1
		ItemId.STONE_PICKAXE, ItemId.STONE_AXE, ItemId.STONE_SHOVEL, ItemId.STONE_SWORD:
			return 2
		ItemId.IRON_PICKAXE, ItemId.IRON_AXE, ItemId.IRON_SHOVEL, ItemId.IRON_SWORD:
			return 3
		ItemId.DIAMOND_PICKAXE, ItemId.DIAMOND_AXE, ItemId.DIAMOND_SHOVEL, ItemId.DIAMOND_SWORD:
			return 4
		_:
			return 0


## Returns authentic Minecraft max durability for tools (Wood=60, Stone=132, Iron=251, Diamond=1562, None=0).
static func get_max_durability(item_id: int) -> int:
	match get_tool_tier(item_id):
		1:
			return 60
		2:
			return 132
		3:
			return 251
		4:
			return 1562
		_:
			return 0


## Returns the item ID dropped when `broken_block_id` is broken with `equipped_item_id` (0 if unharvestable).
static func get_dropped_item_for_block(broken_block_id: int, equipped_item_id: int) -> int:
	if not can_harvest_block(equipped_item_id, broken_block_id):
		return 0
	match broken_block_id:
		BlockRegistry.BlockId.STONE:
			return BlockRegistry.BlockId.COBBLESTONE
		BlockRegistry.BlockId.GRASS:
			return BlockRegistry.BlockId.DIRT
		BlockRegistry.BlockId.COAL_ORE:
			return ItemId.COAL
		BlockRegistry.BlockId.IRON_ORE:
			return ItemId.RAW_IRON
		BlockRegistry.BlockId.GOLD_ORE:
			return ItemId.RAW_GOLD
		BlockRegistry.BlockId.DIAMOND_ORE:
			return ItemId.DIAMOND
		BlockRegistry.BlockId.WOOL:
			return ItemId.WOOL
		BlockRegistry.BlockId.FARMLAND:
			return BlockRegistry.BlockId.DIRT
		BlockRegistry.BlockId.WHEAT_CROPS:
			return ItemId.WHEAT
		BlockRegistry.BlockId.POTATO_CROPS:
			return ItemId.POTATO
		_:
			return broken_block_id


## Checks whether the equipped item can harvest drops from `block_id` (Minecraft harvest rules).
static func can_harvest_block(equipped_item_id: int, block_id: int) -> bool:
	var cat: int = get_tool_category(equipped_item_id)
	var tier: int = get_tool_tier(equipped_item_id)

	match block_id:
		BlockRegistry.BlockId.STONE, BlockRegistry.BlockId.COBBLESTONE, BlockRegistry.BlockId.COAL_ORE, BlockRegistry.BlockId.FURNACE:
			return cat == ToolCategory.PICKAXE and tier >= 1
		BlockRegistry.BlockId.IRON_ORE:
			return cat == ToolCategory.PICKAXE and tier >= 2
		BlockRegistry.BlockId.GOLD_ORE, BlockRegistry.BlockId.DIAMOND_ORE:
			return cat == ToolCategory.PICKAXE and tier >= 3
		_:
			# Wood, dirt, grass, sand, leaves, snow, crafting table, glowstone can be harvested by hand
			return true


## Returns mining speed multiplier when breaking `target_block_id` with `equipped_item_id`.
static func get_mining_speed_multiplier(equipped_item_id: int, target_block_id: int) -> float:
	var cat: int = get_tool_category(equipped_item_id)
	var tier: int = get_tool_tier(equipped_item_id)
	var tier_speed: float = 1.0
	match tier:
		1:
			tier_speed = 2.4
		2:
			tier_speed = 4.0
		3:
			tier_speed = 6.2
		4:
			tier_speed = 9.5

	if BlockRegistry.is_stone_Or_ore(target_block_id):
		if cat == ToolCategory.PICKAXE and can_harvest_block(equipped_item_id, target_block_id):
			return tier_speed
		# Penalty when punching stone/ore without the required Pickaxe tier
		return 0.28

	if (
		target_block_id == BlockRegistry.BlockId.WOOD_LOG
		or target_block_id == BlockRegistry.BlockId.WOOD_PLANKS
		or target_block_id == BlockRegistry.BlockId.CRAFTING_TABLE
	):
		if cat == ToolCategory.AXE:
			return tier_speed
		return 1.0

	if (
		target_block_id == BlockRegistry.BlockId.DIRT
		or target_block_id == BlockRegistry.BlockId.GRASS
		or target_block_id == BlockRegistry.BlockId.SAND
		or target_block_id == BlockRegistry.BlockId.SNOW
	):
		if cat == ToolCategory.SHOVEL:
			return tier_speed
		return 1.0

	return 1.0


static func get_item_name(item_id: int) -> String:
	match item_id:
		0:
			return "Empty Hand"
		ItemId.STICK:
			return "Stick"
		ItemId.COAL:
			return "Coal"
		ItemId.RAW_IRON:
			return "Raw Iron"
		ItemId.IRON_INGOT:
			return "Iron Ingot"
		ItemId.RAW_GOLD:
			return "Raw Gold"
		ItemId.GOLD_INGOT:
			return "Gold Ingot"
		ItemId.DIAMOND:
			return "Diamond"
		ItemId.BUCKET:
			return "Iron Bucket"
		ItemId.WATER_BUCKET:
			return "Water Bucket"
		ItemId.RAW_PORKCHOP:
			return "Raw Porkchop"
		ItemId.COOKED_PORKCHOP:
			return "Cooked Porkchop"
		ItemId.RAW_BEEF:
			return "Raw Beef"
		ItemId.STEAK:
			return "Steak"
		ItemId.APPLE:
			return "Red Apple"
		ItemId.ROTTEN_FLESH:
			return "Rotten Flesh"
		ItemId.GUNPOWDER:
			return "Gunpowder"
		ItemId.WOOL:
			return "White Wool"
		ItemId.WHEAT_SEEDS:
			return "Wheat Seeds"
		ItemId.WHEAT:
			return "Wheat"
		ItemId.BREAD:
			return "Bread"
		ItemId.POTATO:
			return "Potato"
		ItemId.BAKED_POTATO:
			return "Baked Potato"
		ItemId.LAVA_BUCKET:
			return "Lava Bucket"
		ItemId.SHEARS:
			return "Shears"
		ItemId.WOOD_PICKAXE:
			return "Wooden Pickaxe"
		ItemId.STONE_PICKAXE:
			return "Stone Pickaxe"
		ItemId.IRON_PICKAXE:
			return "Iron Pickaxe"
		ItemId.DIAMOND_PICKAXE:
			return "Diamond Pickaxe"
		ItemId.WOOD_AXE:
			return "Wooden Axe"
		ItemId.STONE_AXE:
			return "Stone Axe"
		ItemId.IRON_AXE:
			return "Iron Axe"
		ItemId.DIAMOND_AXE:
			return "Diamond Axe"
		ItemId.WOOD_SHOVEL:
			return "Wooden Shovel"
		ItemId.STONE_SHOVEL:
			return "Stone Shovel"
		ItemId.IRON_SHOVEL:
			return "Iron Shovel"
		ItemId.DIAMOND_SHOVEL:
			return "Diamond Shovel"
		ItemId.WOOD_SWORD:
			return "Wooden Sword"
		ItemId.STONE_SWORD:
			return "Stone Sword"
		ItemId.IRON_SWORD:
			return "Iron Sword"
		ItemId.DIAMOND_SWORD:
			return "Diamond Sword"
		_:
			return BlockRegistry.get_block_name(item_id)


static func get_item_short_label(item_id: int) -> String:
	match item_id:
		0:
			return ""
		ItemId.STICK:
			return "Stick"
		ItemId.COAL:
			return "Coal"
		ItemId.RAW_IRON:
			return "RawFe"
		ItemId.IRON_INGOT:
			return "Iron"
		ItemId.RAW_GOLD:
			return "RawAu"
		ItemId.GOLD_INGOT:
			return "Gold"
		ItemId.DIAMOND:
			return "Diamnd"
		ItemId.BUCKET:
			return "Bucket"
		ItemId.WATER_BUCKET:
			return "WtrBkt"
		ItemId.RAW_PORKCHOP:
			return "RawPrk"
		ItemId.COOKED_PORKCHOP:
			return "Pork"
		ItemId.RAW_BEEF:
			return "RawBf"
		ItemId.STEAK:
			return "Steak"
		ItemId.APPLE:
			return "Apple"
		ItemId.ROTTEN_FLESH:
			return "Flesh"
		ItemId.GUNPOWDER:
			return "Gunpwd"
		ItemId.WOOD_PICKAXE:
			return "W-Pick"
		ItemId.STONE_PICKAXE:
			return "S-Pick"
		ItemId.IRON_PICKAXE:
			return "I-Pick"
		ItemId.DIAMOND_PICKAXE:
			return "D-Pick"
		ItemId.WOOD_AXE:
			return "W-Axe"
		ItemId.STONE_AXE:
			return "S-Axe"
		ItemId.IRON_AXE:
			return "I-Axe"
		ItemId.DIAMOND_AXE:
			return "D-Axe"
		ItemId.WOOD_SHOVEL:
			return "W-Shvl"
		ItemId.STONE_SHOVEL:
			return "S-Shvl"
		ItemId.IRON_SHOVEL:
			return "I-Shvl"
		ItemId.DIAMOND_SHOVEL:
			return "D-Shvl"
		ItemId.WOOD_SWORD:
			return "W-Swrd"
		ItemId.STONE_SWORD:
			return "S-Swrd"
		ItemId.IRON_SWORD:
			return "I-Swrd"
		ItemId.DIAMOND_SWORD:
			return "D-Swrd"
		_:
			return BlockRegistry.get_block_name(item_id).substr(0, 6)


static func get_item_color(item_id: int) -> Color:
	match item_id:
		0:
			return Color(0.15, 0.16, 0.18, 0.25)
		ItemId.STICK:
			return Color(0.58, 0.42, 0.22)
		ItemId.COAL:
			return Color(0.16, 0.17, 0.20)
		ItemId.RAW_IRON:
			return Color(0.82, 0.62, 0.46)
		ItemId.IRON_INGOT:
			return Color(0.88, 0.90, 0.95)
		ItemId.RAW_GOLD:
			return Color(0.95, 0.78, 0.22)
		ItemId.GOLD_INGOT:
			return Color(1.0, 0.86, 0.18)
		ItemId.DIAMOND:
			return Color(0.26, 0.94, 0.96)
		ItemId.BUCKET:
			return Color(0.76, 0.80, 0.86)
		ItemId.WATER_BUCKET:
			return Color(0.22, 0.56, 0.96)
		ItemId.RAW_PORKCHOP:
			return Color(0.94, 0.58, 0.60)
		ItemId.COOKED_PORKCHOP:
			return Color(0.76, 0.48, 0.26)
		ItemId.RAW_BEEF:
			return Color(0.82, 0.24, 0.24)
		ItemId.STEAK:
			return Color(0.52, 0.28, 0.16)
		ItemId.APPLE:
			return Color(0.92, 0.18, 0.20)
		ItemId.ROTTEN_FLESH:
			return Color(0.54, 0.34, 0.24)
		ItemId.GUNPOWDER:
			return Color(0.36, 0.36, 0.38)
		ItemId.WOOD_PICKAXE, ItemId.WOOD_AXE, ItemId.WOOD_SHOVEL, ItemId.WOOD_SWORD:
			return Color(0.68, 0.50, 0.28)
		ItemId.STONE_PICKAXE, ItemId.STONE_AXE, ItemId.STONE_SHOVEL, ItemId.STONE_SWORD:
			return Color(0.56, 0.58, 0.62)
		ItemId.IRON_PICKAXE, ItemId.IRON_AXE, ItemId.IRON_SHOVEL, ItemId.IRON_SWORD:
			return Color(0.88, 0.90, 0.95)
		ItemId.DIAMOND_PICKAXE, ItemId.DIAMOND_AXE, ItemId.DIAMOND_SHOVEL, ItemId.DIAMOND_SWORD:
			return Color(0.26, 0.94, 0.96)
		_:
			return BlockRegistry.get_block_color(item_id)


# ============================================================================
# INVENTORY SLOT & STACK OPERATIONS
# ============================================================================

func get_hotbar_slot(slot_idx: int) -> Dictionary:
	if slot_idx < 0 or slot_idx >= HOTBAR_SIZE or slot_idx >= slots.size():
		return {"id": 0, "count": 0}
	return slots[slot_idx]


func get_total_count(item_id: int) -> int:
	var total: int = 0
	for slot in slots:
		if int(slot["id"]) == item_id:
			total += int(slot["count"])
	return total


## Adds `amount` of `item_id` into hotbar/backpack (stacking existing first, then empty slots).
func add_item(item_id: int, amount: int = 1, custom_durability: int = -1) -> bool:
	if item_id <= 0 or amount <= 0:
		return false

	var max_stack_for_item: int = 1 if is_tool_item(item_id) else MAX_STACK
	var remaining: int = amount
	var max_dur: int = get_max_durability(item_id)
	var assign_dur: int = custom_durability if custom_durability > 0 else max_dur

	# 1. Try merging into existing non-full stacks
	if max_stack_for_item > 1:
		for i in range(TOTAL_SLOTS):
			if int(slots[i]["id"]) == item_id and int(slots[i]["count"]) < max_stack_for_item:
				var space: int = max_stack_for_item - int(slots[i]["count"])
				var to_add: int = mini(remaining, space)
				slots[i]["count"] = int(slots[i]["count"]) + to_add
				remaining -= to_add
				if remaining <= 0:
					inventory_updated.emit()
					return true

	# 2. Place into empty slots (Hotbar 0..8 first, then Backpack 9..35)
	for i in range(TOTAL_SLOTS):
		if int(slots[i]["id"]) == 0 or int(slots[i]["count"]) <= 0:
			var to_place: int = mini(remaining, max_stack_for_item)
			slots[i] = {"id": item_id, "count": to_place, "durability": assign_dur}
			remaining -= to_place
			if remaining <= 0:
				inventory_updated.emit()
				return true

	inventory_updated.emit()
	return remaining < amount


## Reduces durability of a tool in `slot_idx`. Returns true if the tool broke and was destroyed.
func damage_hotbar_tool(slot_idx: int, wear_amount: int = 1) -> bool:
	if slot_idx < 0 or slot_idx >= HOTBAR_SIZE:
		return false
	var entry: Dictionary = slots[slot_idx]
	var item_id: int = int(entry.get("id", 0))
	var max_dur: int = get_max_durability(item_id)
	if max_dur <= 0:
		return false
	var cur_dur: int = int(entry.get("durability", max_dur))
	if cur_dur <= 0:
		cur_dur = max_dur
	cur_dur -= wear_amount
	if cur_dur <= 0:
		slots[slot_idx] = {"id": 0, "count": 0}
		inventory_updated.emit()
		return true
	entry["durability"] = cur_dur
	inventory_updated.emit()
	return false


## Pops 1 item from `slot_idx` so the player can toss it into the 3D world with the Q key.
func pop_one_from_hotbar_for_drop(slot_idx: int) -> Dictionary:
	if slot_idx < 0 or slot_idx >= HOTBAR_SIZE:
		return {"id": 0, "count": 0, "durability": -1}
	var entry: Dictionary = slots[slot_idx]
	var item_id: int = int(entry.get("id", 0))
	var cur_cnt: int = int(entry.get("count", 0))
	if item_id <= 0 or cur_cnt <= 0:
		return {"id": 0, "count": 0, "durability": -1}
	var dur: int = int(entry.get("durability", get_max_durability(item_id)))
	entry["count"] = cur_cnt - 1
	if int(entry["count"]) <= 0:
		slots[slot_idx] = {"id": 0, "count": 0}
	inventory_updated.emit()
	return {"id": item_id, "count": 1, "durability": dur}


## Consumes `1` unit from a specific hotbar slot when placing a block.
func consume_from_hotbar_slot(slot_idx: int, amount: int = 1) -> bool:
	if slot_idx < 0 or slot_idx >= HOTBAR_SIZE:
		return false
	var entry: Dictionary = slots[slot_idx]
	if int(entry["id"]) == 0 or int(entry["count"]) < amount:
		return false
	entry["count"] = int(entry["count"]) - amount
	if int(entry["count"]) <= 0:
		slots[slot_idx] = {"id": 0, "count": 0}
	inventory_updated.emit()
	return true


## Converts an Empty Bucket in `slot_idx` into a Water Bucket (or vice versa).
func convert_hotbar_bucket(slot_idx: int, new_item_id: int) -> void:
	if slot_idx < 0 or slot_idx >= HOTBAR_SIZE:
		return
	var entry: Dictionary = slots[slot_idx]
	var cur_count: int = int(entry.get("count", 0))
	if cur_count <= 1:
		slots[slot_idx] = {"id": new_item_id, "count": 1}
	else:
		entry["count"] = cur_count - 1
		add_item(new_item_id, 1)
	inventory_updated.emit()


## Consumes `amount` of `item_id` from anywhere in the 36-slot inventory.
func consume_item_anywhere(item_id: int, amount: int = 1) -> bool:
	if get_total_count(item_id) < amount:
		return false
	var remaining: int = amount
	for i in range(TOTAL_SLOTS):
		if int(slots[i]["id"]) == item_id:
			var take: int = mini(remaining, int(slots[i]["count"]))
			slots[i]["count"] = int(slots[i]["count"]) - take
			remaining -= take
			if int(slots[i]["count"]) <= 0:
				slots[i] = {"id": 0, "count": 0}
			if remaining <= 0:
				break
	inventory_updated.emit()
	return true


## Awards appropriate drops when a voxel block is broken in the world.
func award_block_drop(broken_block_id: int, equipped_item_id: int) -> String:
	if not can_harvest_block(equipped_item_id, broken_block_id):
		return "Broken! (Requires proper Pickaxe tier to harvest)"

	match broken_block_id:
		BlockRegistry.BlockId.STONE:
			add_item(BlockRegistry.BlockId.COBBLESTONE, 1)
			return "+1 Cobblestone"
		BlockRegistry.BlockId.GRASS:
			add_item(BlockRegistry.BlockId.DIRT, 1)
			return "+1 Dirt"
		BlockRegistry.BlockId.COAL_ORE:
			add_item(ItemId.COAL, 1)
			return "+1 Coal"
		BlockRegistry.BlockId.IRON_ORE:
			add_item(ItemId.RAW_IRON, 1)
			return "+1 Raw Iron"
		BlockRegistry.BlockId.GOLD_ORE:
			add_item(ItemId.RAW_GOLD, 1)
			return "+1 Raw Gold"
		BlockRegistry.BlockId.DIAMOND_ORE:
			add_item(ItemId.DIAMOND, 1)
			return "+1 Diamond!"
		_:
			add_item(broken_block_id, 1)
			return "+1 %s" % get_item_name(broken_block_id)


# ============================================================================
# MINECRAFT SLOT CLICK INTERACTION (LEFT-CLICK / RIGHT-CLICK DRAG & DROP)
# ============================================================================

## Handles clicking on one of the 36 player inventory slots (`0..35`).
## Supports Shift + Left-Click instant stack transfer between Hotbar (`0..8`) and Backpack (`9..35`).
func click_inventory_slot(slot_idx: int, mouse_button: int) -> void:
	if slot_idx < 0 or slot_idx >= TOTAL_SLOTS:
		return
	if mouse_button == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SHIFT):
		var s: Dictionary = slots[slot_idx]
		var id: int = int(s.get("id", 0))
		var cnt: int = int(s.get("count", 0))
		if id > 0 and cnt > 0:
			var rem: int = 0
			if slot_idx < HOTBAR_SIZE:
				rem = _insert_into_range(id, cnt, int(s.get("durability", -1)), HOTBAR_SIZE, TOTAL_SLOTS)
			else:
				rem = _insert_into_range(id, cnt, int(s.get("durability", -1)), 0, HOTBAR_SIZE)
			if rem <= 0:
				slots[slot_idx] = {"id": 0, "count": 0}
			else:
				slots[slot_idx]["count"] = rem
			inventory_updated.emit()
		return
	slots[slot_idx] = _interact_slot_with_cursor(slots[slot_idx], mouse_button)
	inventory_updated.emit()


func _insert_into_range(item_id: int, count: int, durability: int, start_idx: int, end_idx: int) -> int:
	var rem: int = count
	var stackable: bool = not is_tool_item(item_id)
	if stackable:
		for i in range(start_idx, end_idx):
			if int(slots[i]["id"]) == item_id and int(slots[i]["count"]) < MAX_STACK:
				var space: int = MAX_STACK - int(slots[i]["count"])
				var add_n: int = mini(rem, space)
				slots[i]["count"] = int(slots[i]["count"]) + add_n
				rem -= add_n
				if rem <= 0:
					return 0
	for i in range(start_idx, end_idx):
		if int(slots[i]["id"]) == 0 or int(slots[i]["count"]) <= 0:
			var add_n: int = 1 if not stackable else mini(rem, MAX_STACK)
			var d_val: int = durability if durability >= 0 else get_max_durability(item_id)
			slots[i] = {"id": item_id, "count": add_n, "durability": d_val}
			rem -= add_n
			if rem <= 0:
				return 0
	return rem


## Handles clicking on a cell (`0..3` or `0..8`) of the active Crafting Grid.
func click_craft_grid_slot(grid_idx: int, mouse_button: int) -> void:
	if grid_idx < 0 or grid_idx >= craft_grid.size():
		return
	craft_grid[grid_idx] = _interact_slot_with_cursor(craft_grid[grid_idx], mouse_button)
	_recalculate_crafting_output()
	inventory_updated.emit()


## Handles clicking the Crafting Output slot (consumes 1 ingredient from each non-empty craft cell).
func click_craft_output_slot() -> void:
	var out_id: int = int(craft_output.get("id", 0))
	var out_count: int = int(craft_output.get("count", 0))
	if out_id == 0 or out_count <= 0:
		return

	if Input.is_key_pressed(KEY_SHIFT):
		var rem: int = add_item(out_id, out_count, get_max_durability(out_id))
		if rem < out_count:
			for i in range(craft_grid.size()):
				if int(craft_grid[i]["id"]) != 0:
					craft_grid[i]["count"] = int(craft_grid[i]["count"]) - 1
					if int(craft_grid[i]["count"]) <= 0:
						craft_grid[i] = {"id": 0, "count": 0}
			_recalculate_crafting_output()
			inventory_updated.emit()
		return

	var cur_id: int = int(cursor_stack.get("id", 0))
	var cur_count: int = int(cursor_stack.get("count", 0))
	var max_stk: int = 1 if is_tool_item(out_id) else MAX_STACK

	if cur_id != 0 and (cur_id != out_id or cur_count + out_count > max_stk):
		return

	if cur_id == 0:
		cursor_stack = {"id": out_id, "count": out_count, "durability": get_max_durability(out_id)}
	else:
		cursor_stack["count"] = cur_count + out_count

	# Consume 1 item from every occupied cell in the crafting grid
	for i in range(craft_grid.size()):
		if int(craft_grid[i]["id"]) != 0:
			craft_grid[i]["count"] = int(craft_grid[i]["count"]) - 1
			if int(craft_grid[i]["count"]) <= 0:
				craft_grid[i] = {"id": 0, "count": 0}

	_recalculate_crafting_output()
	inventory_updated.emit()


## Handles clicking Furnace Input (`0`), Furnace Fuel (`1`), or Furnace Output (`2`).
func click_furnace_slot(furnace_slot_type: int, mouse_button: int) -> void:
	match furnace_slot_type:
		0: # Input
			furnace_input = _interact_slot_with_cursor(furnace_input, mouse_button)
		1: # Fuel
			furnace_fuel = _interact_slot_with_cursor(furnace_fuel, mouse_button)
		2: # Output (take-only)
			var out_id: int = int(furnace_output.get("id", 0))
			var out_cnt: int = int(furnace_output.get("count", 0))
			if out_id != 0 and out_cnt > 0:
				if Input.is_key_pressed(KEY_SHIFT):
					var rem: int = add_item(out_id, out_cnt)
					if rem <= 0:
						furnace_output = {"id": 0, "count": 0}
					else:
						furnace_output["count"] = rem
				else:
					var cur_id: int = int(cursor_stack.get("id", 0))
					var cur_cnt: int = int(cursor_stack.get("count", 0))
					if cur_id == 0:
						cursor_stack = {"id": out_id, "count": out_cnt}
						furnace_output = {"id": 0, "count": 0}
					elif cur_id == out_id and cur_cnt + out_cnt <= MAX_STACK:
						cursor_stack["count"] = cur_cnt + out_cnt
						furnace_output = {"id": 0, "count": 0}
	furnace_updated.emit()
	inventory_updated.emit()


## Ensures a 27-slot storage array exists for `chest_pos` and sets it as the active open Chest.
func open_chest_at(chest_pos: Vector3i) -> void:
	active_chest_pos = chest_pos
	if not world_chests.has(chest_pos):
		var c_slots: Array[Dictionary] = []
		c_slots.resize(CHEST_SIZE)
		for i in range(CHEST_SIZE):
			c_slots[i] = {"id": 0, "count": 0}
		world_chests[chest_pos] = c_slots
	inventory_updated.emit()


func get_active_chest_slots() -> Array:
	if not world_chests.has(active_chest_pos):
		open_chest_at(active_chest_pos)
	return world_chests[active_chest_pos]


func click_chest_slot(slot_idx: int, mouse_button: int) -> void:
	var c_slots: Array = get_active_chest_slots()
	if slot_idx < 0 or slot_idx >= c_slots.size():
		return
	if mouse_button == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SHIFT):
		var s: Dictionary = c_slots[slot_idx]
		var id: int = int(s.get("id", 0))
		var cnt: int = int(s.get("count", 0))
		if id > 0 and cnt > 0:
			var rem: int = add_item(id, cnt, int(s.get("durability", -1)))
			if rem <= 0:
				c_slots[slot_idx] = {"id": 0, "count": 0}
			else:
				c_slots[slot_idx]["count"] = rem
			inventory_updated.emit()
		return
	c_slots[slot_idx] = _interact_slot_with_cursor(c_slots[slot_idx], mouse_button)
	inventory_updated.emit()


func drop_chest_contents_at(world_manager: Node, chest_pos: Vector3i) -> void:
	if not world_chests.has(chest_pos):
		return
	var c_slots: Array = world_chests[chest_pos]
	for entry in c_slots:
		var id: int = int(entry.get("id", 0))
		var cnt: int = int(entry.get("count", 0))
		if id > 0 and cnt > 0:
			DroppedItem.spawn_drop(
				world_manager,
				Vector3(chest_pos) + Vector3(0.5, 0.45, 0.5),
				id,
				cnt,
				Vector3.ZERO,
				0.35,
				int(entry.get("durability", -1))
			)
	world_chests.erase(chest_pos)


func populate_loot_chest_at(chest_pos: Vector3i, rng_seed: int) -> void:
	if world_chests.has(chest_pos):
		return
	var c_slots: Array[Dictionary] = []
	c_slots.resize(CHEST_SIZE)
	for i in range(CHEST_SIZE):
		c_slots[i] = {"id": 0, "count": 0}

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var loot_pool: Array[Array] = [
		[ItemId.IRON_INGOT, 3],
		[ItemId.GOLD_INGOT, 2],
		[ItemId.APPLE, 4],
		[ItemId.COAL, 6],
		[ItemId.DIAMOND, 1],
		[ItemId.BUCKET, 1],
		[BlockRegistry.BlockId.TORCH, 8],
		[BlockRegistry.BlockId.TNT, 2],
	]
	for n in range(5):
		var pick: Array = loot_pool[rng.randi_range(0, loot_pool.size() - 1)]
		var slot_i: int = rng.randi_range(0, CHEST_SIZE - 1)
		c_slots[slot_i] = {"id": int(pick[0]), "count": int(pick[1])}
	world_chests[chest_pos] = c_slots


func _interact_slot_with_cursor(target_slot: Dictionary, mouse_button: int) -> Dictionary:
	var slot_id: int = int(target_slot.get("id", 0))
	var slot_cnt: int = int(target_slot.get("count", 0))
	var slot_dur: int = int(target_slot.get("durability", get_max_durability(slot_id)))
	var cur_id: int = int(cursor_stack.get("id", 0))
	var cur_cnt: int = int(cursor_stack.get("count", 0))
	var cur_dur: int = int(cursor_stack.get("durability", get_max_durability(cur_id)))

	if mouse_button == MOUSE_BUTTON_LEFT:
		if cur_id == 0:
			# Pick up entire slot stack onto cursor
			cursor_stack = {"id": slot_id, "count": slot_cnt, "durability": slot_dur}
			return {"id": 0, "count": 0}
		elif slot_id == 0:
			# Place entire cursor stack into empty slot
			var placed := {"id": cur_id, "count": cur_cnt, "durability": cur_dur}
			cursor_stack = {"id": 0, "count": 0}
			return placed
		elif slot_id == cur_id and not is_tool_item(slot_id):
			# Merge stacks up to MAX_STACK
			var space: int = MAX_STACK - slot_cnt
			var move_cnt: int = mini(cur_cnt, space)
			slot_cnt += move_cnt
			cur_cnt -= move_cnt
			if cur_cnt <= 0:
				cursor_stack = {"id": 0, "count": 0}
			else:
				cursor_stack["count"] = cur_cnt
			return {"id": slot_id, "count": slot_cnt, "durability": slot_dur}
		else:
			# Swap cursor and slot
			cursor_stack = {"id": slot_id, "count": slot_cnt, "durability": slot_dur}
			return {"id": cur_id, "count": cur_cnt, "durability": cur_dur}

	elif mouse_button == MOUSE_BUTTON_RIGHT:
		if cur_id == 0 and slot_id != 0:
			# Split stack: pick up half (rounded up)
			var take_half: int = int(ceil(float(slot_cnt) * 0.5))
			var leave_half: int = slot_cnt - take_half
			cursor_stack = {"id": slot_id, "count": take_half, "durability": slot_dur}
			if leave_half <= 0:
				return {"id": 0, "count": 0}
			return {"id": slot_id, "count": leave_half, "durability": slot_dur}
		elif cur_id != 0:
			# Place 1 single item from cursor into empty or matching slot
			if slot_id == 0:
				cursor_stack["count"] = cur_cnt - 1
				if int(cursor_stack["count"]) <= 0:
					cursor_stack = {"id": 0, "count": 0}
				return {"id": cur_id, "count": 1, "durability": cur_dur}
			elif slot_id == cur_id and not is_tool_item(slot_id) and slot_cnt < MAX_STACK:
				cursor_stack["count"] = cur_cnt - 1
				if int(cursor_stack["count"]) <= 0:
					cursor_stack = {"id": 0, "count": 0}
				return {"id": slot_id, "count": slot_cnt + 1, "durability": slot_dur}

	return target_slot


# ============================================================================
# AUTHENTIC MINECRAFT 2x2 AND 3x3 SHAPED PATTERN MATCHER
# ============================================================================

func _recalculate_crafting_output() -> void:
	craft_output = _match_crafting_grid()


func _match_crafting_grid() -> Dictionary:
	# Normalize the occupied bounding box of the current 2x2 or 3x3 crafting grid
	var min_r: int = 99
	var max_r: int = -1
	var min_c: int = 99
	var max_c: int = -1
	var total_occupied: int = 0
	var single_item_id: int = 0

	for r in range(craft_grid_size):
		for c in range(craft_grid_size):
			var id: int = int(craft_grid[r * craft_grid_size + c].get("id", 0))
			if id != 0:
				total_occupied += 1
				single_item_id = id
				min_r = mini(min_r, r)
				max_r = maxi(max_r, r)
				min_c = mini(min_c, c)
				max_c = maxi(max_c, c)

	if total_occupied == 0:
		return {"id": 0, "count": 0}

	# 1. Single cell recipe: 1x Wood Log anywhere -> 4x Wood Planks
	if total_occupied == 1 and single_item_id == BlockRegistry.BlockId.WOOD_LOG:
		return {"id": BlockRegistry.BlockId.WOOD_PLANKS, "count": 4}

	var box_h: int = max_r - min_r + 1
	var box_w: int = max_c - min_c + 1
	var pattern: Array[int] = []
	for r in range(min_r, max_r + 1):
		for c in range(min_c, max_c + 1):
			pattern.append(int(craft_grid[r * craft_grid_size + c].get("id", 0)))

	var P: int = BlockRegistry.BlockId.WOOD_PLANKS
	var S: int = ItemId.STICK
	var C: int = BlockRegistry.BlockId.COBBLESTONE
	var FE: int = ItemId.IRON_INGOT
	var D: int = ItemId.DIAMOND
	var COAL_ID: int = ItemId.COAL

	# 2. 1x2 Vertical Patterns (Works in both 2x2 and 3x3!)
	if box_w == 1 and box_h == 2:
		# 2 Planks vertically -> 4 Sticks
		if pattern == [P, P]:
			return {"id": ItemId.STICK, "count": 4}
		# 1 Coal over 1 Stick -> 4 Torches
		if pattern == [COAL_ID, S]:
			return {"id": BlockRegistry.BlockId.TORCH, "count": 4}

	# 3. 2x2 Patterns (Works in both 2x2 and 3x3!)
	if box_w == 2 and box_h == 2:
		# 4 Wood Planks in 2x2 -> 1 Crafting Table
		if pattern == [P, P, P, P]:
			return {"id": BlockRegistry.BlockId.CRAFTING_TABLE, "count": 1}
		# Shears (2 Iron Ingot diagonal)
		if pattern == [0, FE, FE, 0] or pattern == [FE, 0, 0, FE]:
			return {"id": ItemId.SHEARS, "count": 1}
		# 2 Sand + 2 Gunpowder/Coal -> 1 TNT
		var SAND_ID: int = BlockRegistry.BlockId.SAND
		if pattern == [ItemId.GUNPOWDER, SAND_ID, SAND_ID, ItemId.GUNPOWDER] or pattern == [COAL_ID, SAND_ID, SAND_ID, COAL_ID]:
			return {"id": BlockRegistry.BlockId.TNT, "count": 1}

	# 4. 3x3 Patterns (Requires 3x3 Crafting Table!)
	if box_w == 3 and box_h == 3:
		# Furnace (8 Cobblestone ring)
		if pattern == [C, C, C, C, 0, C, C, C, C]:
			return {"id": BlockRegistry.BlockId.FURNACE, "count": 1}
		# Chest (8 Wood Planks ring)
		if pattern == [P, P, P, P, 0, P, P, P, P]:
			return {"id": BlockRegistry.BlockId.CHEST, "count": 1}
		# Ladder (7 Sticks in H-shape)
		if pattern == [S, 0, S, S, S, S, S, 0, S]:
			return {"id": BlockRegistry.BlockId.LADDER, "count": 3}

		# Pickaxes: [M, M, M, 0, S, 0, 0, S, 0]
		if pattern == [P, P, P, 0, S, 0, 0, S, 0]:
			return {"id": ItemId.WOOD_PICKAXE, "count": 1}
		if pattern == [C, C, C, 0, S, 0, 0, S, 0]:
			return {"id": ItemId.STONE_PICKAXE, "count": 1}
		if pattern == [FE, FE, FE, 0, S, 0, 0, S, 0]:
			return {"id": ItemId.IRON_PICKAXE, "count": 1}
		if pattern == [D, D, D, 0, S, 0, 0, S, 0]:
			return {"id": ItemId.DIAMOND_PICKAXE, "count": 1}

	# 5. Shovels & Swords: 1x3 Vertical [M, S, S] or [M, M, S]
	if box_w == 1 and box_h == 3:
		if pattern == [P, S, S]:
			return {"id": ItemId.WOOD_SHOVEL, "count": 1}
		if pattern == [C, S, S]:
			return {"id": ItemId.STONE_SHOVEL, "count": 1}
		if pattern == [FE, S, S]:
			return {"id": ItemId.IRON_SHOVEL, "count": 1}
		if pattern == [D, S, S]:
			return {"id": ItemId.DIAMOND_SHOVEL, "count": 1}
		if pattern == [P, P, S]:
			return {"id": ItemId.WOOD_SWORD, "count": 1}
		if pattern == [C, C, S]:
			return {"id": ItemId.STONE_SWORD, "count": 1}
		if pattern == [FE, FE, S]:
			return {"id": ItemId.IRON_SWORD, "count": 1}
		if pattern == [D, D, S]:
			return {"id": ItemId.DIAMOND_SWORD, "count": 1}

	# 6. Axes & Wooden Door: 2x3
	if box_w == 2 and box_h == 3:
		if pattern == [P, P, P, P, P, P]:
			return {"id": BlockRegistry.BlockId.DOOR_CLOSED, "count": 2}
		if pattern == [P, P, P, S, 0, S] or pattern == [P, P, S, P, S, 0]:
			return {"id": ItemId.WOOD_AXE, "count": 1}
		if pattern == [C, C, C, S, 0, S] or pattern == [C, C, S, C, S, 0]:
			return {"id": ItemId.STONE_AXE, "count": 1}
		if pattern == [FE, FE, FE, S, 0, S] or pattern == [FE, FE, S, FE, S, 0]:
			return {"id": ItemId.IRON_AXE, "count": 1}
		if pattern == [D, D, D, S, 0, S] or pattern == [D, D, S, D, S, 0]:
			return {"id": ItemId.DIAMOND_AXE, "count": 1}

	# 7. Iron Bucket & Bed: 3x2
	if box_w == 3 and box_h == 2:
		if pattern == [FE, 0, FE, 0, FE, 0]:
			return {"id": ItemId.BUCKET, "count": 1}
		var W: int = ItemId.WOOL
		var WB: int = BlockRegistry.BlockId.WOOL
		var L: int = BlockRegistry.BlockId.LEAVES
		var SN: int = BlockRegistry.BlockId.SNOW
		if (
			pattern == [W, W, W, P, P, P]
			or pattern == [WB, WB, WB, P, P, P]
			or pattern == [L, L, L, P, P, P]
			or pattern == [SN, SN, SN, P, P, P]
		):
			return {"id": BlockRegistry.BlockId.BED, "count": 1}

	# 8. Bread: 3x1 Horizontal (3 Wheat)
	if box_w == 3 and box_h == 1:
		if pattern == [ItemId.WHEAT, ItemId.WHEAT, ItemId.WHEAT]:
			return {"id": ItemId.BREAD, "count": 1}

	return {"id": 0, "count": 0}


## Auto-fills a recipe pattern into the current 2x2 or 3x3 crafting grid from the player's inventory.
func autofill_recipe_pattern(recipe_key: String) -> String:
	return_crafting_grid_to_inventory()

	var P: int = BlockRegistry.BlockId.WOOD_PLANKS
	var S: int = ItemId.STICK
	var C: int = BlockRegistry.BlockId.COBBLESTONE
	var FE: int = ItemId.IRON_INGOT
	var D: int = ItemId.DIAMOND

	var target_grid: Array[int] = []
	var requires_3x3: bool = false

	match recipe_key:
		"planks":
			target_grid = [BlockRegistry.BlockId.WOOD_LOG]
		"sticks":
			if craft_grid_size == 2:
				target_grid = [P, 0, P, 0]
			else:
				target_grid = [0, P, 0, 0, P, 0, 0, 0, 0]
		"crafting_table":
			if craft_grid_size == 2:
				target_grid = [P, P, P, P]
			else:
				target_grid = [P, P, 0, P, P, 0, 0, 0, 0]
		"glowstone":
			if craft_grid_size == 2:
				target_grid = [ItemId.COAL, 0, S, 0]
			else:
				target_grid = [0, ItemId.COAL, 0, 0, S, 0, 0, 0, 0]
		"furnace":
			requires_3x3 = true
			target_grid = [C, C, C, C, 0, C, C, C, C]
		"wood_pickaxe":
			requires_3x3 = true
			target_grid = [P, P, P, 0, S, 0, 0, S, 0]
		"stone_pickaxe":
			requires_3x3 = true
			target_grid = [C, C, C, 0, S, 0, 0, S, 0]
		"iron_pickaxe":
			requires_3x3 = true
			target_grid = [FE, FE, FE, 0, S, 0, 0, S, 0]
		"diamond_pickaxe":
			requires_3x3 = true
			target_grid = [D, D, D, 0, S, 0, 0, S, 0]
		"wood_axe":
			requires_3x3 = true
			target_grid = [P, P, 0, P, S, 0, 0, S, 0]
		"stone_axe":
			requires_3x3 = true
			target_grid = [C, C, 0, C, S, 0, 0, S, 0]
		"wood_shovel":
			requires_3x3 = true
			target_grid = [0, P, 0, 0, S, 0, 0, S, 0]
		"bucket":
			requires_3x3 = true
			target_grid = [FE, 0, FE, 0, FE, 0, 0, 0, 0]
		"wood_sword":
			requires_3x3 = true
			target_grid = [0, P, 0, 0, P, 0, 0, S, 0]
		"stone_sword":
			requires_3x3 = true
			target_grid = [0, C, 0, 0, C, 0, 0, S, 0]
		"iron_sword":
			requires_3x3 = true
			target_grid = [0, FE, 0, 0, FE, 0, 0, S, 0]
		"diamond_sword":
			requires_3x3 = true
			target_grid = [0, D, 0, 0, D, 0, 0, S, 0]
		"chest":
			requires_3x3 = true
			target_grid = [P, P, P, P, 0, P, P, P, P]
		"bed":
			requires_3x3 = true
			var wool_id: int = ItemId.WOOL if get_total_count(ItemId.WOOL) >= 3 else (BlockRegistry.BlockId.WOOL if get_total_count(BlockRegistry.BlockId.WOOL) >= 3 else BlockRegistry.BlockId.LEAVES)
			target_grid = [wool_id, wool_id, wool_id, P, P, P, 0, 0, 0]
		"bread":
			requires_3x3 = true
			target_grid = [ItemId.WHEAT, ItemId.WHEAT, ItemId.WHEAT, 0, 0, 0, 0, 0, 0]
		"shears":
			if craft_grid_size == 2:
				target_grid = [0, FE, FE, 0]
			else:
				target_grid = [0, FE, 0, FE, 0, 0, 0, 0, 0]
		"door":
			requires_3x3 = true
			target_grid = [P, P, 0, P, P, 0, P, P, 0]
		"ladder":
			requires_3x3 = true
			target_grid = [S, 0, S, S, S, S, S, 0, S]
		"tnt":
			var pwd: int = ItemId.GUNPOWDER if get_total_count(ItemId.GUNPOWDER) >= 2 else ItemId.COAL
			var snd: int = BlockRegistry.BlockId.SAND
			if craft_grid_size == 2:
				target_grid = [pwd, snd, snd, pwd]
			else:
				target_grid = [pwd, snd, 0, snd, pwd, 0, 0, 0, 0]

	if requires_3x3 and craft_grid_size < 3:
		return "Place & Right-Click a Crafting Table for 3x3 recipes!"

	# Verify player has all required ingredients
	var needed: Dictionary = {}
	for item_id in target_grid:
		if item_id != 0:
			needed[item_id] = int(needed.get(item_id, 0)) + 1

	for req_id in needed.keys():
		if get_total_count(int(req_id)) < int(needed[req_id]):
			return "Missing %s (Need %d)" % [get_item_name(int(req_id)), int(needed[req_id])]

	# Consume and place into craft_grid cells
	for i in range(mini(target_grid.size(), craft_grid.size())):
		var req_id: int = target_grid[i]
		if req_id != 0:
			consume_item_anywhere(req_id, 1)
			craft_grid[i] = {"id": req_id, "count": 1}

	_recalculate_crafting_output()
	inventory_updated.emit()
	return "Pattern placed in grid! Click Output Slot to craft."


# ============================================================================
# REAL-TIME FURNACE / OVEN SMELTING TICK
# ============================================================================

func _tick_furnace(delta: float) -> void:
	var changed: bool = false

	if furnace_burn_remaining > 0.0:
		furnace_burn_remaining = maxf(0.0, furnace_burn_remaining - delta)
		changed = true

	var smelt_result_id: int = _get_smelt_result(int(furnace_input.get("id", 0)))
	var can_smelt: bool = false
	if smelt_result_id != 0 and int(furnace_input.get("count", 0)) > 0:
		var out_id: int = int(furnace_output.get("id", 0))
		var out_cnt: int = int(furnace_output.get("count", 0))
		if out_id == 0 or (out_id == smelt_result_id and out_cnt < MAX_STACK):
			can_smelt = true

	# Ignite fuel if needed
	if can_smelt and furnace_burn_remaining <= 0.0:
		var fuel_burn: float = _get_fuel_burn_duration(int(furnace_fuel.get("id", 0)))
		if fuel_burn > 0.0 and int(furnace_fuel.get("count", 0)) > 0:
			furnace_fuel["count"] = int(furnace_fuel["count"]) - 1
			if int(furnace_fuel["count"]) <= 0:
				furnace_fuel = {"id": 0, "count": 0}
			furnace_burn_max = fuel_burn
			furnace_burn_remaining = fuel_burn
			changed = true

	# Advance cooking progress if burning and valid input
	if can_smelt and furnace_burn_remaining > 0.0:
		furnace_cook_progress += delta / FURNACE_COOK_TIME
		changed = true
		if furnace_cook_progress >= 1.0:
			furnace_cook_progress = 0.0
			furnace_input["count"] = int(furnace_input["count"]) - 1
			if int(furnace_input["count"]) <= 0:
				furnace_input = {"id": 0, "count": 0}

			if int(furnace_output.get("id", 0)) == 0:
				furnace_output = {"id": smelt_result_id, "count": 1}
			else:
				furnace_output["count"] = int(furnace_output["count"]) + 1
			inventory_updated.emit()
	else:
		if furnace_cook_progress > 0.0:
			furnace_cook_progress = maxf(0.0, furnace_cook_progress - delta * 0.5)
			changed = true

	if changed:
		furnace_updated.emit()


static func _get_smelt_result(input_id: int) -> int:
	match input_id:
		ItemId.RAW_IRON, BlockRegistry.BlockId.IRON_ORE:
			return ItemId.IRON_INGOT
		ItemId.RAW_GOLD, BlockRegistry.BlockId.GOLD_ORE:
			return ItemId.GOLD_INGOT
		ItemId.RAW_PORKCHOP:
			return ItemId.COOKED_PORKCHOP
		ItemId.RAW_BEEF:
			return ItemId.STEAK
		ItemId.POTATO:
			return ItemId.BAKED_POTATO
		BlockRegistry.BlockId.COBBLESTONE:
			return BlockRegistry.BlockId.STONE
		BlockRegistry.BlockId.WOOD_LOG:
			return ItemId.COAL # Charcoal
		BlockRegistry.BlockId.SAND:
			return BlockRegistry.BlockId.GLOWSTONE
		_:
			return 0


static func _get_fuel_burn_duration(fuel_id: int) -> float:
	match fuel_id:
		ItemId.LAVA_BUCKET:
			return 100.0 # Extreme smelting heat (100 items!)
		ItemId.COAL:
			return 16.0
		BlockRegistry.BlockId.WOOD_LOG:
			return 8.0
		BlockRegistry.BlockId.WOOD_PLANKS:
			return 4.0
		ItemId.STICK:
			return 2.0
		_:
			return 0.0
