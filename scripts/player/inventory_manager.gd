class_name InventoryManager
extends Node
const GameSession = preload("res://scripts/core/game_session.gd")
## Authentic Minecraft-style 36-slot inventory (9 hotbar + 27 backpack),
## cursor item stack manipulation (Left-Click full stack, Right-Click single item),
## 2x2 (Player Inventory) & 3x3 (Crafting Table) shaped/shapeless pattern matching,
## and real-time ticked Furnace (Oven) smelting.

signal inventory_updated()
signal furnace_updated()
signal armor_updated(total_defense_points: int)

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
	MILK_BUCKET = 109,
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
	FLINT = 125,
	CLAY_BALL = 126,
	REDSTONE = 127,
	LAPIS = 128,

	# Combat & Utility Items (130..142)
	BOW = 130,
	ARROW = 131,
	FLINT_AND_STEEL = 132,
	STRING = 133,
	FEATHER = 134,
	COMPASS = 135,
	CLOCK = 136,
	FISHING_ROD = 137,
	BOWL = 138,
	MUSHROOM_STEW = 139,
	LEATHER = 140,
	SUGAR = 141,
	EGG = 142,
	RAW_CHICKEN = 143,
	COOKED_CHICKEN = 144,

	# Pickaxes (201..205)
	WOOD_PICKAXE = 201,
	STONE_PICKAXE = 202,
	IRON_PICKAXE = 203,
	DIAMOND_PICKAXE = 204,
	GOLD_PICKAXE = 205,

	# Axes (211..215)
	WOOD_AXE = 211,
	STONE_AXE = 212,
	IRON_AXE = 213,
	DIAMOND_AXE = 214,
	GOLD_AXE = 215,

	# Shovels (221..225)
	WOOD_SHOVEL = 221,
	STONE_SHOVEL = 222,
	IRON_SHOVEL = 223,
	DIAMOND_SHOVEL = 224,
	GOLD_SHOVEL = 225,

	# Swords (231..235)
	WOOD_SWORD = 231,
	STONE_SWORD = 232,
	IRON_SWORD = 233,
	DIAMOND_SWORD = 234,
	GOLD_SWORD = 235,

	# Hoes (241..245)
	WOOD_HOE = 241,
	STONE_HOE = 242,
	IRON_HOE = 243,
	DIAMOND_HOE = 244,
	GOLD_HOE = 245,

	# Armor - Leather (301..304)
	LEATHER_HELMET = 301,
	LEATHER_CHESTPLATE = 302,
	LEATHER_LEGGINGS = 303,
	LEATHER_BOOTS = 304,

	# Armor - Iron (311..314)
	IRON_HELMET = 311,
	IRON_CHESTPLATE = 312,
	IRON_LEGGINGS = 313,
	IRON_BOOTS = 314,

	# Armor - Gold (321..324)
	GOLD_HELMET = 321,
	GOLD_CHESTPLATE = 322,
	GOLD_LEGGINGS = 323,
	GOLD_BOOTS = 324,

	# Armor - Diamond (331..334)
	DIAMOND_HELMET = 331,
	DIAMOND_CHESTPLATE = 332,
	DIAMOND_LEGGINGS = 333,
	DIAMOND_BOOTS = 334,
}

enum ToolCategory {
	NONE = 0,
	PICKAXE = 1,
	AXE = 2,
	SHOVEL = 3,
	SWORD = 4,
	HOE = 5,
}

enum ArmorSlot {
	HELMET = 0,
	CHESTPLATE = 1,
	LEGGINGS = 2,
	BOOTS = 3,
}

## 4 equipped armor slots (0: Helmet, 1: Chestplate, 2: Leggings, 3: Boots).
var armor_slots: Array[Dictionary] = []

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

## Container UI open tracking for Shift-Click stack routing
var is_chest_open: bool = false
var is_furnace_open: bool = false
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
	if tex == null and lookup_id < 100:
		var atlas_tex: Texture2D = VoxelAtlasBuilder.get_atlas_texture()
		if atlas_tex != null:
			var rect: Rect2 = BlockRegistry.get_tile_uv_rect(lookup_id, BlockRegistry.FaceDir.NORTH)
			var sub_tex := AtlasTexture.new()
			sub_tex.atlas = atlas_tex
			sub_tex.region = Rect2(
				rect.position.x * float(atlas_tex.get_width()),
				rect.position.y * float(atlas_tex.get_height()),
				rect.size.x * float(atlas_tex.get_width()),
				rect.size.y * float(atlas_tex.get_height())
			)
			tex = sub_tex
	_icon_cache[lookup_id] = tex
	return tex


func _init() -> void:
	add_to_group("inventory_manager")
	slots.resize(TOTAL_SLOTS)
	for i in range(TOTAL_SLOTS):
		slots[i] = {"id": 0, "count": 0}
	armor_slots.resize(4)
	for i in range(4):
		armor_slots[i] = {"id": 0, "count": 0, "durability": -1}


func _ready() -> void:
	add_to_group("inventory_manager")
	if slots.size() < TOTAL_SLOTS:
		slots.resize(TOTAL_SLOTS)
		for i in range(TOTAL_SLOTS):
			slots[i] = {"id": 0, "count": 0}
	if armor_slots.size() < 4:
		armor_slots.resize(4)
		for i in range(4):
			armor_slots[i] = {"id": 0, "count": 0, "durability": -1}

	set_crafting_grid_dimension(2)

	if GameSession.active_world_data.is_empty():
		var saved: Array[Dictionary] = GameSession.list_saved_worlds()
		if not saved.is_empty() and str(saved[0].get("id", "")).length() > 0:
			GameSession.select_world(str(saved[0]["id"]))

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
		"armor_slots": armor_slots.duplicate(true),
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
					"durability": int(loaded_slots[i].get("durability", -1)),
				}
	if data.has("armor_slots") and data["armor_slots"] is Array:
		var loaded_armor: Array = data["armor_slots"]
		for i in range(mini(4, loaded_armor.size())):
			if loaded_armor[i] is Dictionary:
				armor_slots[i] = {
					"id": int(loaded_armor[i].get("id", 0)),
					"count": int(loaded_armor[i].get("count", 0)),
					"durability": int(loaded_armor[i].get("durability", -1)),
				}
		armor_updated.emit(get_total_defense_points())
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
	is_chest_open = false
	is_furnace_open = false
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


func open_furnace() -> void:
	is_furnace_open = true
	is_chest_open = false
	furnace_updated.emit()


func close_container() -> void:
	is_chest_open = false
	is_furnace_open = false


# ============================================================================
# TOOL & ITEM CLASSIFICATION HELPERS
# ============================================================================

static func is_tool_item(item_id: int) -> bool:
	return (
		(item_id >= ItemId.WOOD_PICKAXE and item_id <= ItemId.GOLD_HOE)
		or (item_id >= ItemId.LEATHER_HELMET and item_id <= ItemId.DIAMOND_BOOTS)
		or item_id == ItemId.WATER_BUCKET
		or item_id == ItemId.MILK_BUCKET
		or item_id == ItemId.LAVA_BUCKET
		or item_id == ItemId.BUCKET
		or item_id == ItemId.BOW
		or item_id == ItemId.FISHING_ROD
		or item_id == ItemId.FLINT_AND_STEEL
		or item_id == ItemId.SHEARS
	)


static func is_food_item(item_id: int) -> bool:
	return (
		(item_id >= ItemId.RAW_PORKCHOP and item_id <= ItemId.ROTTEN_FLESH)
		or item_id == ItemId.BREAD
		or item_id == ItemId.POTATO
		or item_id == ItemId.BAKED_POTATO
		or item_id == ItemId.MUSHROOM_STEW
		or item_id == ItemId.APPLE
		or item_id == ItemId.MILK_BUCKET
		or item_id == ItemId.RAW_CHICKEN
		or item_id == ItemId.COOKED_CHICKEN
	)


static func get_food_nutrition(item_id: int) -> int:
	match item_id:
		ItemId.MUSHROOM_STEW:
			return 10
		ItemId.COOKED_PORKCHOP, ItemId.STEAK:
			return 8
		ItemId.COOKED_CHICKEN:
			return 6
		ItemId.BREAD, ItemId.BAKED_POTATO:
			return 5
		ItemId.APPLE:
			return 4
		ItemId.RAW_PORKCHOP, ItemId.RAW_BEEF:
			return 3
		ItemId.POTATO, ItemId.ROTTEN_FLESH, ItemId.RAW_CHICKEN, ItemId.MILK_BUCKET:
			return 2
		_:
			return 2


static func get_attack_damage(item_id: int) -> int:
	var cat: int = get_tool_category(item_id)
	var tier: int = get_tool_tier(item_id)
	var eff_tier: int = 1 if tier == 5 else tier
	if cat == ToolCategory.SWORD:
		return 3 + eff_tier # Wood=4, Stone=5, Iron=6, Diamond=7, Gold=4
	if cat != ToolCategory.NONE:
		return 1 + eff_tier
	return 2 # Bare fist


static func is_placeable_block(item_id: int) -> bool:
	return item_id > 0 and item_id < 100 and not BlockRegistry.is_liquid(item_id) and item_id != BlockRegistry.BlockId.BED_HEAD


static func get_tool_category(item_id: int) -> int:
	if (item_id >= ItemId.WOOD_PICKAXE and item_id <= ItemId.DIAMOND_PICKAXE) or item_id == ItemId.GOLD_PICKAXE:
		return ToolCategory.PICKAXE
	if (item_id >= ItemId.WOOD_AXE and item_id <= ItemId.DIAMOND_AXE) or item_id == ItemId.GOLD_AXE:
		return ToolCategory.AXE
	if (item_id >= ItemId.WOOD_SHOVEL and item_id <= ItemId.DIAMOND_SHOVEL) or item_id == ItemId.GOLD_SHOVEL:
		return ToolCategory.SHOVEL
	if (item_id >= ItemId.WOOD_SWORD and item_id <= ItemId.DIAMOND_SWORD) or item_id == ItemId.GOLD_SWORD:
		return ToolCategory.SWORD
	if item_id >= ItemId.WOOD_HOE and item_id <= ItemId.GOLD_HOE:
		return ToolCategory.HOE
	return ToolCategory.NONE


## Returns tool tier: 0 = Hand/None, 1 = Wood, 2 = Stone, 3 = Iron, 4 = Diamond, 5 = Gold.
static func get_tool_tier(item_id: int) -> int:
	match item_id:
		ItemId.WOOD_PICKAXE, ItemId.WOOD_AXE, ItemId.WOOD_SHOVEL, ItemId.WOOD_SWORD, ItemId.WOOD_HOE:
			return 1
		ItemId.STONE_PICKAXE, ItemId.STONE_AXE, ItemId.STONE_SHOVEL, ItemId.STONE_SWORD, ItemId.STONE_HOE:
			return 2
		ItemId.IRON_PICKAXE, ItemId.IRON_AXE, ItemId.IRON_SHOVEL, ItemId.IRON_SWORD, ItemId.IRON_HOE:
			return 3
		ItemId.DIAMOND_PICKAXE, ItemId.DIAMOND_AXE, ItemId.DIAMOND_SHOVEL, ItemId.DIAMOND_SWORD, ItemId.DIAMOND_HOE:
			return 4
		ItemId.GOLD_PICKAXE, ItemId.GOLD_AXE, ItemId.GOLD_SHOVEL, ItemId.GOLD_SWORD, ItemId.GOLD_HOE:
			return 5
		_:
			return 0


## Returns authentic Minecraft max durability for tools & armors.
static func get_max_durability(item_id: int) -> int:
	match item_id:
		ItemId.WOOD_PICKAXE, ItemId.WOOD_AXE, ItemId.WOOD_SHOVEL, ItemId.WOOD_SWORD, ItemId.WOOD_HOE:
			return 60
		ItemId.STONE_PICKAXE, ItemId.STONE_AXE, ItemId.STONE_SHOVEL, ItemId.STONE_SWORD, ItemId.STONE_HOE:
			return 132
		ItemId.IRON_PICKAXE, ItemId.IRON_AXE, ItemId.IRON_SHOVEL, ItemId.IRON_SWORD, ItemId.IRON_HOE:
			return 251
		ItemId.DIAMOND_PICKAXE, ItemId.DIAMOND_AXE, ItemId.DIAMOND_SHOVEL, ItemId.DIAMOND_SWORD, ItemId.DIAMOND_HOE:
			return 1562
		ItemId.GOLD_PICKAXE, ItemId.GOLD_AXE, ItemId.GOLD_SHOVEL, ItemId.GOLD_SWORD, ItemId.GOLD_HOE:
			return 33
		ItemId.BOW:
			return 385
		ItemId.FISHING_ROD, ItemId.FLINT_AND_STEEL:
			return 65
		ItemId.SHEARS:
			return 238
		ItemId.LEATHER_HELMET:
			return 56
		ItemId.LEATHER_CHESTPLATE:
			return 82
		ItemId.LEATHER_LEGGINGS:
			return 76
		ItemId.LEATHER_BOOTS:
			return 66
		ItemId.IRON_HELMET:
			return 166
		ItemId.IRON_CHESTPLATE:
			return 242
		ItemId.IRON_LEGGINGS:
			return 226
		ItemId.IRON_BOOTS:
			return 196
		ItemId.GOLD_HELMET:
			return 78
		ItemId.GOLD_CHESTPLATE:
			return 114
		ItemId.GOLD_LEGGINGS:
			return 106
		ItemId.GOLD_BOOTS:
			return 92
		ItemId.DIAMOND_HELMET:
			return 364
		ItemId.DIAMOND_CHESTPLATE:
			return 529
		ItemId.DIAMOND_LEGGINGS:
			return 496
		ItemId.DIAMOND_BOOTS:
			return 430
		_:
			return 0


## Returns true if the given item ID is wearable armor.
static func is_armor_item(item_id: int) -> bool:
	return get_armor_slot_type(item_id) != -1


## Returns the authentic armor slot [0..3] (Helmet, Chestplate, Leggings, Boots) or -1 if not armor.
static func get_armor_slot_type(item_id: int) -> int:
	match item_id:
		ItemId.LEATHER_HELMET, ItemId.IRON_HELMET, ItemId.GOLD_HELMET, ItemId.DIAMOND_HELMET:
			return ArmorSlot.HELMET
		ItemId.LEATHER_CHESTPLATE, ItemId.IRON_CHESTPLATE, ItemId.GOLD_CHESTPLATE, ItemId.DIAMOND_CHESTPLATE:
			return ArmorSlot.CHESTPLATE
		ItemId.LEATHER_LEGGINGS, ItemId.IRON_LEGGINGS, ItemId.GOLD_LEGGINGS, ItemId.DIAMOND_LEGGINGS:
			return ArmorSlot.LEGGINGS
		ItemId.LEATHER_BOOTS, ItemId.IRON_BOOTS, ItemId.GOLD_BOOTS, ItemId.DIAMOND_BOOTS:
			return ArmorSlot.BOOTS
		_:
			return -1


## Returns authentic Minecraft Beta 1.7.3 defense points provided by an armor piece.
static func get_armor_defense_points(item_id: int) -> int:
	match item_id:
		ItemId.LEATHER_HELMET: return 1
		ItemId.LEATHER_CHESTPLATE: return 3
		ItemId.LEATHER_LEGGINGS: return 2
		ItemId.LEATHER_BOOTS: return 1
		ItemId.GOLD_HELMET: return 2
		ItemId.GOLD_CHESTPLATE: return 5
		ItemId.GOLD_LEGGINGS: return 3
		ItemId.GOLD_BOOTS: return 1
		ItemId.IRON_HELMET: return 2
		ItemId.IRON_CHESTPLATE: return 6
		ItemId.IRON_LEGGINGS: return 5
		ItemId.IRON_BOOTS: return 2
		ItemId.DIAMOND_HELMET: return 3
		ItemId.DIAMOND_CHESTPLATE: return 8
		ItemId.DIAMOND_LEGGINGS: return 6
		ItemId.DIAMOND_BOOTS: return 3
		_: return 0


## Returns total defense points across all 4 equipped armor slots [0..20].
func get_total_defense_points() -> int:
	var total: int = 0
	for i in range(mini(4, armor_slots.size())):
		var aid: int = int(armor_slots[i].get("id", 0))
		if aid > 0:
			total += get_armor_defense_points(aid)
	return clampi(total, 0, 20)


## Calculates mitigated damage according to authentic Beta 1.7.3 4% mitigation per defense point.
func calculate_damage_mitigation(incoming_damage: int) -> int:
	if incoming_damage <= 0:
		return 0
	var points: int = get_total_defense_points()
	if points <= 0:
		return incoming_damage
	var reduction: float = float(points) * 0.04
	var mitigated: int = int(round(float(incoming_damage) * (1.0 - reduction)))
	return maxi(1, mitigated)


## Decrements durability of all equipped armor pieces when player takes damage.
## Breaks pieces that reach 0 durability with tool break SFX.
func damage_equipped_armor(damage_points: int = 1) -> void:
	var any_broken: bool = false
	for i in range(mini(4, armor_slots.size())):
		var aid: int = int(armor_slots[i].get("id", 0))
		if aid > 0:
			var max_d: int = get_max_durability(aid)
			var cur_d: int = int(armor_slots[i].get("durability", max_d))
			cur_d -= damage_points
			if cur_d <= 0:
				armor_slots[i] = {"id": 0, "count": 0, "durability": -1}
				any_broken = true
			else:
				armor_slots[i]["durability"] = cur_d
	if any_broken:
		if is_inside_tree() and get_tree() != null:
			var sfx: Node = get_tree().get_first_node_in_group("retro_sfx")
			if sfx != null and sfx.has_method("play_sfx"):
				sfx.play_sfx("tool_break", 0.0)
	armor_updated.emit(get_total_defense_points())
	inventory_updated.emit()


## Equips an armor piece into `slot_idx` [0..3], returning whatever was previously equipped in that slot.
func equip_armor_piece(slot_idx: int, item_dict: Dictionary) -> Dictionary:
	if slot_idx < 0 or slot_idx >= 4:
		return item_dict
	while armor_slots.size() < 4:
		armor_slots.append({"id": 0, "count": 0, "durability": -1})
	var prev: Dictionary = armor_slots[slot_idx].duplicate(true)
	var new_item: Dictionary = item_dict.duplicate(true)
	if new_item.get("id", 0) > 0 and int(new_item.get("durability", -1)) <= 0:
		new_item["durability"] = get_max_durability(new_item["id"])
	new_item["count"] = 1
	armor_slots[slot_idx] = new_item
	armor_updated.emit(get_total_defense_points())
	inventory_updated.emit()
	return prev


## Unequips the armor piece at `slot_idx`, returning it and clearing the slot.
func unequip_armor_piece(slot_idx: int) -> Dictionary:
	if slot_idx < 0 or slot_idx >= armor_slots.size():
		return {"id": 0, "count": 0, "durability": -1}
	var prev: Dictionary = armor_slots[slot_idx].duplicate(true)
	armor_slots[slot_idx] = {"id": 0, "count": 0, "durability": -1}
	armor_updated.emit(get_total_defense_points())
	inventory_updated.emit()
	return prev


## Handles mouse click on an armor slot widget in the inventory screen.
func handle_armor_slot_click(slot_idx: int, _is_right_click: bool = false) -> void:
	if slot_idx < 0 or slot_idx >= 4:
		return
	while armor_slots.size() < 4:
		armor_slots.append({"id": 0, "count": 0, "durability": -1})

	# Shift-Click un-equips item back to inventory/hotbar
	if Input.is_key_pressed(KEY_SHIFT):
		var cur_id: int = int(armor_slots[slot_idx].get("id", 0))
		if cur_id > 0:
			var cur_dur: int = int(armor_slots[slot_idx].get("durability", get_max_durability(cur_id)))
			var unplaced: int = add_item_stack(cur_id, 1, cur_dur)
			if unplaced == 0:
				armor_slots[slot_idx] = {"id": 0, "count": 0, "durability": -1}
				armor_updated.emit(get_total_defense_points())
				inventory_updated.emit()
		return

	var cursor_id: int = int(cursor_stack.get("id", 0))
	var slot_item: Dictionary = armor_slots[slot_idx]
	var slot_id: int = int(slot_item.get("id", 0))

	# If cursor holds an armor piece matching this slot
	if cursor_id > 0 and get_armor_slot_type(cursor_id) == slot_idx:
		var place_item: Dictionary = cursor_stack.duplicate(true)
		place_item["count"] = 1
		if slot_id > 0:
			var prev: Dictionary = slot_item.duplicate(true)
			armor_slots[slot_idx] = place_item
			cursor_stack = prev
		else:
			armor_slots[slot_idx] = place_item
			var remaining_cursor: int = int(cursor_stack.get("count", 1)) - 1
			if remaining_cursor <= 0:
				cursor_stack = {"id": 0, "count": 0, "durability": -1}
			else:
				cursor_stack["count"] = remaining_cursor
		armor_updated.emit(get_total_defense_points())
		inventory_updated.emit()
	# If cursor is empty and slot has an armor piece, pick it up
	elif cursor_id == 0 and slot_id > 0:
		cursor_stack = slot_item.duplicate(true)
		armor_slots[slot_idx] = {"id": 0, "count": 0, "durability": -1}
		armor_updated.emit(get_total_defense_points())
		inventory_updated.emit()


## Returns the main item dropped when `broken_block_id` is broken with `equipped_item_id` (0 if nothing).
## Deterministic (no random extras); see `get_block_drops` for the full randomized drop list.
static func get_dropped_item_for_block(broken_block_id: int, equipped_item_id: int) -> int:
	if not can_harvest_block(equipped_item_id, broken_block_id):
		return 0
	match broken_block_id:
		BlockRegistry.BlockId.BEDROCK, BlockRegistry.BlockId.ICE, BlockRegistry.BlockId.MONSTER_SPAWNER:
			return 0
		BlockRegistry.BlockId.STONE:
			return BlockRegistry.BlockId.COBBLESTONE
		BlockRegistry.BlockId.GRASS, BlockRegistry.BlockId.FARMLAND:
			return BlockRegistry.BlockId.DIRT
		BlockRegistry.BlockId.COAL_ORE:
			return ItemId.COAL
		BlockRegistry.BlockId.IRON_ORE:
			return ItemId.RAW_IRON
		BlockRegistry.BlockId.GOLD_ORE:
			return ItemId.RAW_GOLD
		BlockRegistry.BlockId.DIAMOND_ORE:
			return ItemId.DIAMOND
		BlockRegistry.BlockId.REDSTONE_ORE:
			return ItemId.REDSTONE
		BlockRegistry.BlockId.LAPIS_ORE:
			return ItemId.LAPIS
		BlockRegistry.BlockId.CLAY:
			return ItemId.CLAY_BALL
		BlockRegistry.BlockId.WOOL:
			return ItemId.WOOL
		BlockRegistry.BlockId.WHEAT_CROPS:
			return ItemId.WHEAT
		BlockRegistry.BlockId.POTATO_CROPS, BlockRegistry.BlockId.POTATO_SPROUT:
			return ItemId.POTATO
		BlockRegistry.BlockId.WHEAT_SPROUT:
			return ItemId.WHEAT_SEEDS
		BlockRegistry.BlockId.DOOR_OPEN:
			return BlockRegistry.BlockId.DOOR_CLOSED
		BlockRegistry.BlockId.BED_HEAD:
			return BlockRegistry.BlockId.BED
		BlockRegistry.BlockId.LEAVES, BlockRegistry.BlockId.PINE_LEAVES, BlockRegistry.BlockId.BIRCH_LEAVES, BlockRegistry.BlockId.SEAGRASS:
			# Only shears collect the block itself.
			return broken_block_id if equipped_item_id == ItemId.SHEARS else 0
		_:
			return broken_block_id


## Full drop list for breaking a block: Array of [item_id, count] pairs, including random extras
## (flint from gravel, extra redstone/lapis, wheat seeds, saplings and apples from leaves...).
static func get_block_drops(broken_block_id: int, equipped_item_id: int) -> Array:
	var drops: Array = []
	var main_id: int = get_dropped_item_for_block(broken_block_id, equipped_item_id)
	match broken_block_id:
		BlockRegistry.BlockId.REDSTONE_ORE:
			if main_id > 0:
				drops.append([main_id, randi_range(4, 5)])
		BlockRegistry.BlockId.LAPIS_ORE:
			if main_id > 0:
				drops.append([main_id, randi_range(4, 8)])
		BlockRegistry.BlockId.CLAY:
			drops.append([ItemId.CLAY_BALL, 4])
		BlockRegistry.BlockId.GRAVEL:
			drops.append([ItemId.FLINT if randf() < 0.10 else BlockRegistry.BlockId.GRAVEL, 1])
		BlockRegistry.BlockId.GRASS:
			drops.append([main_id, 1])
			if randf() < 0.125:
				drops.append([ItemId.WHEAT_SEEDS, 1])
		BlockRegistry.BlockId.WHEAT_CROPS:
			drops.append([ItemId.WHEAT, 1])
			var seeds: int = randi_range(0, 3)
			if seeds > 0:
				drops.append([ItemId.WHEAT_SEEDS, seeds])
		BlockRegistry.BlockId.POTATO_CROPS:
			drops.append([ItemId.POTATO, randi_range(2, 4)])
		BlockRegistry.BlockId.LEAVES, BlockRegistry.BlockId.PINE_LEAVES, BlockRegistry.BlockId.BIRCH_LEAVES:
			if main_id > 0:
				drops.append([main_id, 1])
			else:
				if randf() < 0.05:
					drops.append([WorldManager.sapling_for_leaves(broken_block_id), 1])
				if broken_block_id == BlockRegistry.BlockId.LEAVES and randf() < 0.005:
					drops.append([ItemId.APPLE, 1])
		_:
			if main_id > 0:
				drops.append([main_id, 1])
	return drops


## Harvest level of a tool: wood and gold 0, stone 1, iron 2, diamond 3 (-1 = hand / not a tool).
static func get_harvest_level(item_id: int) -> int:
	match get_tool_tier(item_id):
		1, 5:
			return 0
		2:
			return 1
		3:
			return 2
		4:
			return 3
		_:
			return -1


## Checks whether the equipped item can harvest drops from `block_id`. Stone-type blocks need a
## pickaxe of a high enough level: any for stone/coal, stone+ for iron/lapis, iron+ for
## gold/diamond/redstone, diamond for obsidian.
static func can_harvest_block(equipped_item_id: int, block_id: int, meta: int = 0) -> bool:
	if block_id == BlockRegistry.BlockId.BEDROCK:
		return false
	var required: int = BlockRegistry.get_required_harvest_level(block_id, meta)
	if required < 0:
		return true
	return get_tool_category(equipped_item_id) == ToolCategory.PICKAXE and get_harvest_level(equipped_item_id) >= required


## Tool material speeds: hand 1, wood 2, stone 4, iron 6, diamond 8, gold 12.
const TOOL_MATERIAL_SPEED: Array[float] = [1.0, 2.0, 4.0, 6.0, 8.0, 12.0]


## Mining speed of `equipped_item_id` against `target_block_id` (the tool's material speed when it
## is the right tool for the block, otherwise 1; swords cut leaves 1.5x, shears leaves 15x / wool 5x).
static func get_mining_speed_multiplier(equipped_item_id: int, target_block_id: int, meta: int = 0) -> float:
	var cat: int = get_tool_category(equipped_item_id)
	var effective: int = BlockRegistry.get_effective_tool(target_block_id, meta)
	if effective != BlockRegistry.TOOL_NONE and cat == effective:
		return TOOL_MATERIAL_SPEED[get_tool_tier(equipped_item_id)]
	if equipped_item_id == ItemId.SHEARS:
		if BlockRegistry.is_leaves(target_block_id):
			return 15.0
		if target_block_id == BlockRegistry.BlockId.WOOL:
			return 5.0
	if cat == ToolCategory.SWORD and BlockRegistry.is_leaves(target_block_id):
		return 1.5
	return 1.0


## Game ticks (1/20 s) needed to break a block: hardness * 30 / speed with the right tool for drops,
## hardness * 100 / speed otherwise; 5x slower underwater and 5x slower while not standing on ground.
## Returns 0 for instant breaks and -1 for unbreakable blocks.
static func get_break_ticks(
	equipped_item_id: int, block_id: int, meta: int = 0, head_in_water: bool = false, on_ground: bool = true
) -> int:
	var hardness: float = BlockRegistry.get_block_hardness(block_id)
	if hardness < 0.0:
		return -1
	if hardness == 0.0:
		return 0
	var speed: float = get_mining_speed_multiplier(equipped_item_id, block_id, meta)
	if head_in_water:
		speed /= 5.0
	if not on_ground:
		speed /= 5.0
	var divisor: float = 30.0 if can_harvest_block(equipped_item_id, block_id, meta) else 100.0
	var progress_per_tick: float = speed / hardness / divisor
	if progress_per_tick >= 1.0:
		return 0
	return int(ceil(1.0 / progress_per_tick))


## Seconds needed to break a block (see `get_break_ticks`); 0 = instant, -1 = unbreakable.
static func get_break_time(
	equipped_item_id: int, block_id: int, meta: int = 0, head_in_water: bool = false, on_ground: bool = true
) -> float:
	var ticks: int = get_break_ticks(equipped_item_id, block_id, meta, head_in_water, on_ground)
	return -1.0 if ticks < 0 else float(ticks) / 20.0


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
		ItemId.MILK_BUCKET:
			return "Milk Bucket"
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
		ItemId.FLINT:
			return "Flint"
		ItemId.CLAY_BALL:
			return "Clay Ball"
		ItemId.REDSTONE:
			return "Redstone"
		ItemId.LAPIS:
			return "Lapis Lazuli"
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
		ItemId.GOLD_PICKAXE:
			return "Golden Pickaxe"
		ItemId.GOLD_AXE:
			return "Golden Axe"
		ItemId.GOLD_SHOVEL:
			return "Golden Shovel"
		ItemId.GOLD_SWORD:
			return "Golden Sword"
		ItemId.WOOD_HOE:
			return "Wooden Hoe"
		ItemId.STONE_HOE:
			return "Stone Hoe"
		ItemId.IRON_HOE:
			return "Iron Hoe"
		ItemId.DIAMOND_HOE:
			return "Diamond Hoe"
		ItemId.GOLD_HOE:
			return "Golden Hoe"
		ItemId.BOW:
			return "Bow"
		ItemId.ARROW:
			return "Arrow"
		ItemId.FLINT_AND_STEEL:
			return "Flint and Steel"
		ItemId.STRING:
			return "String"
		ItemId.FEATHER:
			return "Feather"
		ItemId.COMPASS:
			return "Compass"
		ItemId.CLOCK:
			return "Clock"
		ItemId.FISHING_ROD:
			return "Fishing Rod"
		ItemId.BOWL:
			return "Bowl"
		ItemId.MUSHROOM_STEW:
			return "Mushroom Stew"
		ItemId.LEATHER:
			return "Leather"
		ItemId.SUGAR:
			return "Sugar"
		ItemId.EGG:
			return "Egg"
		ItemId.RAW_CHICKEN:
			return "Raw Chicken"
		ItemId.COOKED_CHICKEN:
			return "Cooked Chicken"
		ItemId.LEATHER_HELMET:
			return "Leather Cap"
		ItemId.LEATHER_CHESTPLATE:
			return "Leather Tunic"
		ItemId.LEATHER_LEGGINGS:
			return "Leather Pants"
		ItemId.LEATHER_BOOTS:
			return "Leather Boots"
		ItemId.IRON_HELMET:
			return "Iron Helmet"
		ItemId.IRON_CHESTPLATE:
			return "Iron Chestplate"
		ItemId.IRON_LEGGINGS:
			return "Iron Leggings"
		ItemId.IRON_BOOTS:
			return "Iron Boots"
		ItemId.GOLD_HELMET:
			return "Golden Helmet"
		ItemId.GOLD_CHESTPLATE:
			return "Golden Chestplate"
		ItemId.GOLD_LEGGINGS:
			return "Golden Leggings"
		ItemId.GOLD_BOOTS:
			return "Golden Boots"
		ItemId.DIAMOND_HELMET:
			return "Diamond Helmet"
		ItemId.DIAMOND_CHESTPLATE:
			return "Diamond Chestplate"
		ItemId.DIAMOND_LEGGINGS:
			return "Diamond Leggings"
		ItemId.DIAMOND_BOOTS:
			return "Diamond Boots"
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
		ItemId.MILK_BUCKET:
			return "Milk"
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
		ItemId.GOLD_PICKAXE:
			return "G-Pick"
		ItemId.GOLD_AXE:
			return "G-Axe"
		ItemId.GOLD_SHOVEL:
			return "G-Shvl"
		ItemId.GOLD_SWORD:
			return "G-Swrd"
		ItemId.WOOD_HOE:
			return "W-Hoe"
		ItemId.STONE_HOE:
			return "S-Hoe"
		ItemId.IRON_HOE:
			return "I-Hoe"
		ItemId.DIAMOND_HOE:
			return "D-Hoe"
		ItemId.GOLD_HOE:
			return "G-Hoe"
		ItemId.BOW:
			return "Bow"
		ItemId.ARROW:
			return "Arrow"
		ItemId.FLINT_AND_STEEL:
			return "FlintS"
		ItemId.STRING:
			return "String"
		ItemId.FEATHER:
			return "Feathr"
		ItemId.COMPASS:
			return "Compas"
		ItemId.CLOCK:
			return "Clock"
		ItemId.FISHING_ROD:
			return "FishRd"
		ItemId.BOWL:
			return "Bowl"
		ItemId.MUSHROOM_STEW:
			return "Stew"
		ItemId.LEATHER:
			return "Leathr"
		ItemId.SUGAR:
			return "Sugar"
		ItemId.EGG:
			return "Egg"
		ItemId.RAW_CHICKEN:
			return "RawChkn"
		ItemId.COOKED_CHICKEN:
			return "CkChkn"
		ItemId.LEATHER_HELMET:
			return "L-Cap"
		ItemId.LEATHER_CHESTPLATE:
			return "L-Tunic"
		ItemId.LEATHER_LEGGINGS:
			return "L-Pant"
		ItemId.LEATHER_BOOTS:
			return "L-Boot"
		ItemId.IRON_HELMET:
			return "I-Helm"
		ItemId.IRON_CHESTPLATE:
			return "I-Chst"
		ItemId.IRON_LEGGINGS:
			return "I-Legs"
		ItemId.IRON_BOOTS:
			return "I-Boot"
		ItemId.GOLD_HELMET:
			return "G-Helm"
		ItemId.GOLD_CHESTPLATE:
			return "G-Chst"
		ItemId.GOLD_LEGGINGS:
			return "G-Legs"
		ItemId.GOLD_BOOTS:
			return "G-Boot"
		ItemId.DIAMOND_HELMET:
			return "D-Helm"
		ItemId.DIAMOND_CHESTPLATE:
			return "D-Chst"
		ItemId.DIAMOND_LEGGINGS:
			return "D-Legs"
		ItemId.DIAMOND_BOOTS:
			return "D-Boot"
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
		ItemId.MILK_BUCKET:
			return Color(0.95, 0.95, 0.98)
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
		ItemId.STRING:
			return Color(0.92, 0.92, 0.92)
		ItemId.FEATHER:
			return Color(0.96, 0.96, 0.96)
		ItemId.BOW, ItemId.FISHING_ROD:
			return Color(0.52, 0.36, 0.20)
		ItemId.ARROW:
			return Color(0.72, 0.68, 0.60)
		ItemId.FLINT_AND_STEEL:
			return Color(0.65, 0.65, 0.70)
		ItemId.BOWL:
			return Color(0.60, 0.44, 0.25)
		ItemId.MUSHROOM_STEW:
			return Color(0.78, 0.38, 0.32)
		ItemId.LEATHER:
			return Color(0.68, 0.38, 0.24)
		ItemId.SUGAR:
			return Color(0.98, 0.98, 0.98)
		ItemId.EGG:
			return Color(0.95, 0.92, 0.82)
		ItemId.RAW_CHICKEN:
			return Color(0.92, 0.65, 0.65)
		ItemId.COOKED_CHICKEN:
			return Color(0.78, 0.52, 0.28)
		ItemId.WOOD_PICKAXE, ItemId.WOOD_AXE, ItemId.WOOD_SHOVEL, ItemId.WOOD_SWORD, ItemId.WOOD_HOE:
			return Color(0.68, 0.50, 0.28)
		ItemId.STONE_PICKAXE, ItemId.STONE_AXE, ItemId.STONE_SHOVEL, ItemId.STONE_SWORD, ItemId.STONE_HOE:
			return Color(0.56, 0.58, 0.62)
		ItemId.IRON_PICKAXE, ItemId.IRON_AXE, ItemId.IRON_SHOVEL, ItemId.IRON_SWORD, ItemId.IRON_HOE:
			return Color(0.88, 0.90, 0.95)
		ItemId.DIAMOND_PICKAXE, ItemId.DIAMOND_AXE, ItemId.DIAMOND_SHOVEL, ItemId.DIAMOND_SWORD, ItemId.DIAMOND_HOE:
			return Color(0.26, 0.94, 0.96)
		ItemId.GOLD_PICKAXE, ItemId.GOLD_AXE, ItemId.GOLD_SHOVEL, ItemId.GOLD_SWORD, ItemId.GOLD_HOE:
			return Color(1.0, 0.86, 0.18)
		ItemId.LEATHER_HELMET, ItemId.LEATHER_CHESTPLATE, ItemId.LEATHER_LEGGINGS, ItemId.LEATHER_BOOTS:
			return Color(0.65, 0.36, 0.22)
		ItemId.IRON_HELMET, ItemId.IRON_CHESTPLATE, ItemId.IRON_LEGGINGS, ItemId.IRON_BOOTS:
			return Color(0.85, 0.87, 0.92)
		ItemId.GOLD_HELMET, ItemId.GOLD_CHESTPLATE, ItemId.GOLD_LEGGINGS, ItemId.GOLD_BOOTS:
			return Color(1.0, 0.84, 0.15)
		ItemId.DIAMOND_HELMET, ItemId.DIAMOND_CHESTPLATE, ItemId.DIAMOND_LEGGINGS, ItemId.DIAMOND_BOOTS:
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
	var remaining: int = add_item_stack(item_id, amount, custom_durability)
	return remaining < amount


## Adds items into hotbar/backpack. Returns the number of unplaced items (0 if completely placed).
func add_item_stack(item_id: int, amount: int = 1, custom_durability: int = -1) -> int:
	if item_id <= 0 or amount <= 0:
		return amount

	var max_stack_for_item: int = 1 if is_tool_item(item_id) else MAX_STACK
	var remaining: int = amount
	var max_dur: int = get_max_durability(item_id)
	var assign_dur: int = custom_durability if custom_durability > 0 else max_dur

	# 1. Try merging into existing non-full stacks
	if max_stack_for_item > 1:
		for i in range(TOTAL_SLOTS):
			if int(slots[i].get("id", 0)) == item_id and int(slots[i].get("count", 0)) < max_stack_for_item:
				var space: int = max_stack_for_item - int(slots[i]["count"])
				var to_add: int = mini(remaining, space)
				slots[i]["count"] = int(slots[i]["count"]) + to_add
				remaining -= to_add
				if remaining <= 0:
					inventory_updated.emit()
					return 0

	# 2. Place into empty slots (Hotbar 0..8 first, then Backpack 9..35)
	for i in range(TOTAL_SLOTS):
		if int(slots[i].get("id", 0)) == 0 or int(slots[i].get("count", 0)) <= 0:
			var to_place: int = mini(remaining, max_stack_for_item)
			slots[i] = {"id": item_id, "count": to_place, "durability": assign_dur}
			remaining -= to_place
			if remaining <= 0:
				inventory_updated.emit()
				return 0

	inventory_updated.emit()
	return remaining


## Checks if the inventory can fit `amount` of `item_id` without modifying inventory slots.
func can_fit_item(item_id: int, amount: int = 1) -> bool:
	if item_id <= 0 or amount <= 0:
		return false
	var max_stack_for_item: int = 1 if is_tool_item(item_id) else MAX_STACK
	var needed: int = amount
	if max_stack_for_item > 1:
		for i in range(TOTAL_SLOTS):
			if int(slots[i].get("id", 0)) == item_id:
				needed -= (max_stack_for_item - int(slots[i].get("count", 0)))
				if needed <= 0:
					return true
	for i in range(TOTAL_SLOTS):
		if int(slots[i].get("id", 0)) == 0 or int(slots[i].get("count", 0)) <= 0:
			needed -= max_stack_for_item
			if needed <= 0:
				return true
	return needed <= 0


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
		BlockRegistry.BlockId.BEDROCK:
			return "Bedrock is unbreakable!"
		BlockRegistry.BlockId.MONSTER_SPAWNER:
			return "Monster Spawner destroyed!"
		BlockRegistry.BlockId.ICE:
			return "Ice shattered"
		BlockRegistry.BlockId.PINE_LEAVES, BlockRegistry.BlockId.BIRCH_LEAVES:
			return ""
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
		BlockRegistry.BlockId.REDSTONE_ORE:
			var r_cnt: int = randi_range(4, 5)
			add_item(ItemId.REDSTONE, r_cnt)
			return "+%d Redstone" % r_cnt
		BlockRegistry.BlockId.LAPIS_ORE:
			var l_cnt: int = randi_range(4, 8)
			add_item(ItemId.LAPIS, l_cnt)
			return "+%d Lapis Lazuli" % l_cnt
		BlockRegistry.BlockId.CLAY:
			add_item(ItemId.CLAY_BALL, 4)
			return "+4 Clay Balls"
		BlockRegistry.BlockId.GRAVEL:
			if randf() < 0.10:
				add_item(ItemId.FLINT, 1)
				return "+1 Flint"
			else:
				add_item(BlockRegistry.BlockId.GRAVEL, 1)
				return "+1 Gravel"
		_:
			add_item(broken_block_id, 1)
			return "+1 %s" % get_item_name(broken_block_id)


# ============================================================================
# MINECRAFT SLOT CLICK INTERACTION (LEFT-CLICK / RIGHT-CLICK DRAG & DROP)
# ============================================================================

## Handles clicking on one of the 36 player inventory slots (`0..35`).
## Supports Shift + Left-Click instant stack transfer:
## - Into open Chest if Chest UI is open
## - Into Furnace Fuel / Input if Furnace UI is open
## - Between Hotbar (`0..8`) and Backpack (`9..35`)
func click_inventory_slot(slot_idx: int, mouse_button: int) -> void:
	if slot_idx < 0 or slot_idx >= TOTAL_SLOTS:
		return
	if mouse_button == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SHIFT):
		var s: Dictionary = slots[slot_idx]
		var id: int = int(s.get("id", 0))
		var cnt: int = int(s.get("count", 0))
		if id > 0 and cnt > 0:
			var dur: int = int(s.get("durability", -1))

			# 1. If Chest is open, transfer directly into active Chest!
			if is_chest_open and world_chests.has(active_chest_pos):
				var c_slots: Array = world_chests[active_chest_pos]
				var rem: int = _insert_into_slot_list(c_slots, id, cnt, dur, 0, c_slots.size())
				if rem <= 0:
					slots[slot_idx] = {"id": 0, "count": 0}
				else:
					slots[slot_idx]["count"] = rem
				inventory_updated.emit()
				return

			# 2. If Furnace is open, transfer fuel or smeltable input
			if is_furnace_open:
				var transferred: bool = false
				if _get_fuel_burn_duration(id) > 0.0:
					var f_id: int = int(furnace_fuel.get("id", 0))
					var f_cnt: int = int(furnace_fuel.get("count", 0))
					if f_id == 0:
						furnace_fuel = {"id": id, "count": cnt}
						slots[slot_idx] = {"id": 0, "count": 0}
						transferred = true
					elif f_id == id and f_cnt < MAX_STACK:
						var space: int = MAX_STACK - f_cnt
						var move_n: int = mini(cnt, space)
						furnace_fuel["count"] = f_cnt + move_n
						if cnt - move_n <= 0:
							slots[slot_idx] = {"id": 0, "count": 0}
						else:
							slots[slot_idx]["count"] = cnt - move_n
						transferred = true
				if not transferred and _get_smelt_result(id) != 0:
					var in_id: int = int(furnace_input.get("id", 0))
					var in_cnt: int = int(furnace_input.get("count", 0))
					if in_id == 0:
						furnace_input = {"id": id, "count": cnt}
						slots[slot_idx] = {"id": 0, "count": 0}
						transferred = true
					elif in_id == id and in_cnt < MAX_STACK:
						var space: int = MAX_STACK - in_cnt
						var move_n: int = mini(cnt, space)
						furnace_input["count"] = in_cnt + move_n
						if cnt - move_n <= 0:
							slots[slot_idx] = {"id": 0, "count": 0}
						else:
							slots[slot_idx]["count"] = cnt - move_n
						transferred = true
				if transferred:
					furnace_updated.emit()
					inventory_updated.emit()
					return

			# 3. If neither Chest nor Furnace is open, and item is an Armor piece, Shift-Click equips it if the slot is empty!
			if not is_chest_open and not is_furnace_open and is_armor_item(id):
				var target_armor_slot: int = get_armor_slot_type(id)
				if target_armor_slot >= 0 and target_armor_slot < 4:
					while armor_slots.size() < 4:
						armor_slots.append({"id": 0, "count": 0, "durability": -1})
					if int(armor_slots[target_armor_slot].get("id", 0)) == 0:
						armor_slots[target_armor_slot] = {"id": id, "count": 1, "durability": dur}
						if cnt <= 1:
							slots[slot_idx] = {"id": 0, "count": 0}
						else:
							slots[slot_idx]["count"] = cnt - 1
						armor_updated.emit(get_total_defense_points())
						inventory_updated.emit()
						return

			# 4. Default Hotbar <-> Backpack transfer
			var rem: int = 0
			if slot_idx < HOTBAR_SIZE:
				rem = _insert_into_range(id, cnt, dur, HOTBAR_SIZE, TOTAL_SLOTS)
			else:
				rem = _insert_into_range(id, cnt, dur, 0, HOTBAR_SIZE)
			if rem <= 0:
				slots[slot_idx] = {"id": 0, "count": 0}
			else:
				slots[slot_idx]["count"] = rem
			inventory_updated.emit()
		return
	slots[slot_idx] = _interact_slot_with_cursor(slots[slot_idx], mouse_button)
	inventory_updated.emit()


func _insert_into_slot_list(target_list: Array, item_id: int, count: int, durability: int, start_idx: int, end_idx: int) -> int:
	var rem: int = count
	var stackable: bool = not is_tool_item(item_id)
	if stackable:
		for i in range(start_idx, end_idx):
			if i >= target_list.size():
				break
			if int(target_list[i].get("id", 0)) == item_id and int(target_list[i].get("count", 0)) < MAX_STACK:
				var space: int = MAX_STACK - int(target_list[i]["count"])
				var add_n: int = mini(rem, space)
				target_list[i]["count"] = int(target_list[i]["count"]) + add_n
				rem -= add_n
				if rem <= 0:
					return 0
	for i in range(start_idx, end_idx):
		if i >= target_list.size():
			break
		if int(target_list[i].get("id", 0)) == 0 or int(target_list[i].get("count", 0)) <= 0:
			var add_n: int = 1 if not stackable else mini(rem, MAX_STACK)
			var d_val: int = durability if durability >= 0 else get_max_durability(item_id)
			target_list[i] = {"id": item_id, "count": add_n, "durability": d_val}
			rem -= add_n
			if rem <= 0:
				return 0
	return rem


func _insert_into_range(item_id: int, count: int, durability: int, start_idx: int, end_idx: int) -> int:
	return _insert_into_slot_list(slots, item_id, count, durability, start_idx, end_idx)


## Handles clicking on a cell (`0..3` or `0..8`) of the active Crafting Grid.
func click_craft_grid_slot(grid_idx: int, mouse_button: int) -> void:
	if grid_idx < 0 or grid_idx >= craft_grid.size():
		return
	craft_grid[grid_idx] = _interact_slot_with_cursor(craft_grid[grid_idx], mouse_button)
	_recalculate_crafting_output()
	inventory_updated.emit()


## Handles clicking the Crafting Output slot (consumes 1 ingredient from each non-empty craft cell).
## Shift-clicking will batch-craft in a while-loop until ingredients are exhausted or player inventory is full.
func click_craft_output_slot() -> void:
	var out_id: int = int(craft_output.get("id", 0))
	var out_count: int = int(craft_output.get("count", 0))
	if out_id == 0 or out_count <= 0:
		return

	if Input.is_key_pressed(KEY_SHIFT):
		var max_craft_loops: int = 64
		var loop_idx: int = 0
		while loop_idx < max_craft_loops:
			out_id = int(craft_output.get("id", 0))
			out_count = int(craft_output.get("count", 0))
			if out_id == 0 or out_count <= 0:
				break
			if not can_fit_item(out_id, out_count):
				break
			var unplaced: int = add_item_stack(out_id, out_count, get_max_durability(out_id))
			if unplaced > 0:
				break
			for i in range(craft_grid.size()):
				if int(craft_grid[i].get("id", 0)) != 0:
					craft_grid[i]["count"] = int(craft_grid[i]["count"]) - 1
					if int(craft_grid[i]["count"]) <= 0:
						craft_grid[i] = {"id": 0, "count": 0}
			_recalculate_crafting_output()
			loop_idx += 1
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
					var rem: int = add_item_stack(out_id, out_cnt)
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
	is_chest_open = true
	is_furnace_open = false
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
			var rem: int = add_item_stack(id, cnt, int(s.get("durability", -1)))
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
		[ItemId.REDSTONE, 4],
		[ItemId.BREAD, 2],
		[ItemId.WHEAT, 4],
		[ItemId.GUNPOWDER, 3],
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
	var all_items: Array[int] = []

	for r in range(craft_grid_size):
		for c in range(craft_grid_size):
			var id: int = int(craft_grid[r * craft_grid_size + c].get("id", 0))
			if id != 0:
				total_occupied += 1
				single_item_id = id
				all_items.append(id)
				min_r = mini(min_r, r)
				max_r = maxi(max_r, r)
				min_c = mini(min_c, c)
				max_c = maxi(max_c, c)

	if total_occupied == 0:
		return {"id": 0, "count": 0}

	# Shapeless Recipe: Mushroom Stew (Brown Mushroom + Red Mushroom + Bowl anywhere in grid)
	if total_occupied == 3:
		all_items.sort()
		var stew_reqs: Array[int] = [
			ItemId.BOWL,
			BlockRegistry.BlockId.BROWN_MUSHROOM,
			BlockRegistry.BlockId.RED_MUSHROOM,
		]
		stew_reqs.sort()
		if all_items == stew_reqs:
			return {"id": ItemId.MUSHROOM_STEW, "count": 1}

	# 1. Single cell recipes (Works anywhere in 2x2 or 3x3)
	if total_occupied == 1:
		match single_item_id:
			BlockRegistry.BlockId.WOOD_LOG, BlockRegistry.BlockId.PINE_LOG, BlockRegistry.BlockId.BIRCH_LOG:
				return {"id": BlockRegistry.BlockId.WOOD_PLANKS, "count": 4}
			BlockRegistry.BlockId.GOLD_BLOCK:
				return {"id": ItemId.GOLD_INGOT, "count": 9}
			BlockRegistry.BlockId.IRON_BLOCK:
				return {"id": ItemId.IRON_INGOT, "count": 9}
			BlockRegistry.BlockId.DIAMOND_BLOCK:
				return {"id": ItemId.DIAMOND, "count": 9}
			BlockRegistry.BlockId.LAPIS_BLOCK:
				return {"id": ItemId.LAPIS, "count": 9}
			BlockRegistry.BlockId.SUGAR_CANE:
				return {"id": ItemId.SUGAR, "count": 1}
			BlockRegistry.BlockId.STONE:
				return {"id": BlockRegistry.BlockId.BUTTON, "count": 1}

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
	var AU: int = ItemId.GOLD_INGOT
	var D: int = ItemId.DIAMOND
	var COAL_ID: int = ItemId.COAL
	var LEA: int = ItemId.LEATHER

	# 2. 1x2 Vertical Patterns (Works in both 2x2 and 3x3)
	if box_w == 1 and box_h == 2:
		# 2 Planks vertically -> 4 Sticks
		if pattern == [P, P]:
			return {"id": ItemId.STICK, "count": 4}
		# 1 Coal over 1 Stick -> 4 Torches
		if pattern == [COAL_ID, S]:
			return {"id": BlockRegistry.BlockId.TORCH, "count": 4}
		# 1 Redstone over 1 Stick -> 1 Redstone Torch
		if pattern == [ItemId.REDSTONE, S]:
			return {"id": BlockRegistry.BlockId.REDSTONE_TORCH, "count": 1}
		# 1 Stick over 1 Cobblestone -> 1 Lever
		if pattern == [S, C]:
			return {"id": BlockRegistry.BlockId.LEVER, "count": 1}

	# 3. 2x1 Horizontal Patterns
	if box_w == 2 and box_h == 1:
		if pattern == [BlockRegistry.BlockId.STONE, BlockRegistry.BlockId.STONE]:
			return {"id": BlockRegistry.BlockId.BUTTON, "count": 1}

	# 4. 3x1 Horizontal Patterns (Bread & Slabs)
	if box_w == 3 and box_h == 1:
		if pattern == [ItemId.WHEAT, ItemId.WHEAT, ItemId.WHEAT]:
			return {"id": ItemId.BREAD, "count": 1}
		if pattern == [BlockRegistry.BlockId.STONE, BlockRegistry.BlockId.STONE, BlockRegistry.BlockId.STONE]:
			return {"id": BlockRegistry.BlockId.SLAB, "count": 6}
		if pattern == [BlockRegistry.BlockId.SANDSTONE, BlockRegistry.BlockId.SANDSTONE, BlockRegistry.BlockId.SANDSTONE]:
			return {"id": BlockRegistry.BlockId.SLAB, "count": 6}
		if pattern == [P, P, P]:
			return {"id": BlockRegistry.BlockId.SLAB, "count": 6}
		if pattern == [C, C, C]:
			return {"id": BlockRegistry.BlockId.SLAB, "count": 6}

	# 5. 1x3 Vertical Patterns (Shovels, Swords, Arrows)
	if box_w == 1 and box_h == 3:
		# Shovels: [M, S, S]
		if pattern == [P, S, S]: return {"id": ItemId.WOOD_SHOVEL, "count": 1}
		if pattern == [C, S, S]: return {"id": ItemId.STONE_SHOVEL, "count": 1}
		if pattern == [FE, S, S]: return {"id": ItemId.IRON_SHOVEL, "count": 1}
		if pattern == [D, S, S]: return {"id": ItemId.DIAMOND_SHOVEL, "count": 1}
		if pattern == [AU, S, S]: return {"id": ItemId.GOLD_SHOVEL, "count": 1}

		# Swords: [M, M, S]
		if pattern == [P, P, S]: return {"id": ItemId.WOOD_SWORD, "count": 1}
		if pattern == [C, C, S]: return {"id": ItemId.STONE_SWORD, "count": 1}
		if pattern == [FE, FE, S]: return {"id": ItemId.IRON_SWORD, "count": 1}
		if pattern == [D, D, S]: return {"id": ItemId.DIAMOND_SWORD, "count": 1}
		if pattern == [AU, AU, S]: return {"id": ItemId.GOLD_SWORD, "count": 1}

		# Arrows: Flint, Stick, Feather
		if pattern == [ItemId.FLINT, S, ItemId.FEATHER]:
			return {"id": ItemId.ARROW, "count": 4}

	# 6. 2x2 Square Patterns (Works in both 2x2 and 3x3)
	if box_w == 2 and box_h == 2:
		# 4 Wood Planks in 2x2 -> 1 Crafting Table
		if pattern == [P, P, P, P]:
			return {"id": BlockRegistry.BlockId.CRAFTING_TABLE, "count": 1}
		# 4 Sand -> 1 Sandstone
		if pattern == [BlockRegistry.BlockId.SAND, BlockRegistry.BlockId.SAND, BlockRegistry.BlockId.SAND, BlockRegistry.BlockId.SAND]:
			return {"id": BlockRegistry.BlockId.SANDSTONE, "count": 1}
		# 4 Clay Balls -> 1 Clay Block
		if pattern == [ItemId.CLAY_BALL, ItemId.CLAY_BALL, ItemId.CLAY_BALL, ItemId.CLAY_BALL]:
			return {"id": BlockRegistry.BlockId.CLAY, "count": 1}
		# Shears (2 Iron Ingot diagonal)
		if pattern == [0, FE, FE, 0] or pattern == [FE, 0, 0, FE]:
			return {"id": ItemId.SHEARS, "count": 1}
		# Flint and Steel (Iron Ingot + Flint diagonal)
		if pattern == [FE, 0, 0, ItemId.FLINT] or pattern == [0, FE, ItemId.FLINT, 0]:
			return {"id": ItemId.FLINT_AND_STEEL, "count": 1}
		# TNT (Sand + Gunpowder / Coal)
		var SAND_ID: int = BlockRegistry.BlockId.SAND
		if pattern == [ItemId.GUNPOWDER, SAND_ID, SAND_ID, ItemId.GUNPOWDER] or pattern == [COAL_ID, SAND_ID, SAND_ID, COAL_ID]:
			return {"id": BlockRegistry.BlockId.TNT, "count": 1}

	# 7. 2x3 Patterns (Axes, Hoes, Wooden Door)
	if box_w == 2 and box_h == 3:
		if pattern == [P, P, P, P, P, P]:
			return {"id": BlockRegistry.BlockId.DOOR_CLOSED, "count": 2}

		# Axes (both left and right mirror)
		var axe_mats: Array[Array] = [
			[P, ItemId.WOOD_AXE],
			[C, ItemId.STONE_AXE],
			[FE, ItemId.IRON_AXE],
			[D, ItemId.DIAMOND_AXE],
			[AU, ItemId.GOLD_AXE],
		]
		for pair in axe_mats:
			var M: int = pair[0]
			var out_item: int = pair[1]
			if pattern == [M, M, M, S, 0, S] or pattern == [M, M, S, M, S, 0]:
				return {"id": out_item, "count": 1}

		# Hoes (both left and right mirror)
		var hoe_mats: Array[Array] = [
			[P, ItemId.WOOD_HOE],
			[C, ItemId.STONE_HOE],
			[FE, ItemId.IRON_HOE],
			[D, ItemId.DIAMOND_HOE],
			[AU, ItemId.GOLD_HOE],
		]
		for pair in hoe_mats:
			var M: int = pair[0]
			var out_item: int = pair[1]
			if pattern == [M, M, 0, S, 0, S] or pattern == [M, M, S, 0, S, 0]:
				return {"id": out_item, "count": 1}

	# 8. 3x2 Patterns (Buckets, Bowls, Beds, Helmets, Boots)
	if box_w == 3 and box_h == 2:
		if pattern == [FE, 0, FE, 0, FE, 0]:
			return {"id": ItemId.BUCKET, "count": 1}
		if pattern == [P, 0, P, 0, P, 0]:
			return {"id": ItemId.BOWL, "count": 4}

		# Bed: 3 Wool over 3 Planks
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

		# Helmets: [M, M, M, M, 0, M]
		var helm_mats: Array[Array] = [
			[LEA, ItemId.LEATHER_HELMET],
			[FE, ItemId.IRON_HELMET],
			[AU, ItemId.GOLD_HELMET],
			[D, ItemId.DIAMOND_HELMET],
		]
		for pair in helm_mats:
			var M: int = pair[0]
			if pattern == [M, M, M, M, 0, M]:
				return {"id": pair[1], "count": 1}

		# Boots: [M, 0, M, M, 0, M]
		var boot_mats: Array[Array] = [
			[LEA, ItemId.LEATHER_BOOTS],
			[FE, ItemId.IRON_BOOTS],
			[AU, ItemId.GOLD_BOOTS],
			[D, ItemId.DIAMOND_BOOTS],
		]
		for pair in boot_mats:
			var M: int = pair[0]
			if pattern == [M, 0, M, M, 0, M]:
				return {"id": pair[1], "count": 1}

	# 9. 3x3 Patterns (Workbenches, Blocks, Pickaxes, Chestplates, Leggings, Stairs, Bow, Fishing Rod)
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

		# Storage Blocks (9-to-1)
		if pattern == [AU, AU, AU, AU, AU, AU, AU, AU, AU]:
			return {"id": BlockRegistry.BlockId.GOLD_BLOCK, "count": 1}
		if pattern == [FE, FE, FE, FE, FE, FE, FE, FE, FE]:
			return {"id": BlockRegistry.BlockId.IRON_BLOCK, "count": 1}
		if pattern == [D, D, D, D, D, D, D, D, D]:
			return {"id": BlockRegistry.BlockId.DIAMOND_BLOCK, "count": 1}
		var LAPIS_ID: int = ItemId.LAPIS
		if pattern == [LAPIS_ID, LAPIS_ID, LAPIS_ID, LAPIS_ID, LAPIS_ID, LAPIS_ID, LAPIS_ID, LAPIS_ID, LAPIS_ID]:
			return {"id": BlockRegistry.BlockId.LAPIS_BLOCK, "count": 1}

		# Pickaxes: [M, M, M, 0, S, 0, 0, S, 0]
		var pick_mats: Array[Array] = [
			[P, ItemId.WOOD_PICKAXE],
			[C, ItemId.STONE_PICKAXE],
			[FE, ItemId.IRON_PICKAXE],
			[D, ItemId.DIAMOND_PICKAXE],
			[AU, ItemId.GOLD_PICKAXE],
		]
		for pair in pick_mats:
			var M: int = pair[0]
			if pattern == [M, M, M, 0, S, 0, 0, S, 0]:
				return {"id": pair[1], "count": 1}

		# Chestplates: [M, 0, M, M, M, M, M, M, M]
		var chest_mats: Array[Array] = [
			[LEA, ItemId.LEATHER_CHESTPLATE],
			[FE, ItemId.IRON_CHESTPLATE],
			[AU, ItemId.GOLD_CHESTPLATE],
			[D, ItemId.DIAMOND_CHESTPLATE],
		]
		for pair in chest_mats:
			var M: int = pair[0]
			if pattern == [M, 0, M, M, M, M, M, M, M]:
				return {"id": pair[1], "count": 1}

		# Leggings: [M, M, M, M, 0, M, M, 0, M]
		var leg_mats: Array[Array] = [
			[LEA, ItemId.LEATHER_LEGGINGS],
			[FE, ItemId.IRON_LEGGINGS],
			[AU, ItemId.GOLD_LEGGINGS],
			[D, ItemId.DIAMOND_LEGGINGS],
		]
		for pair in leg_mats:
			var M: int = pair[0]
			if pattern == [M, M, M, M, 0, M, M, 0, M]:
				return {"id": pair[1], "count": 1}

		# Stairs (6 Planks or 6 Cobble, both left and right ascending)
		if (
			pattern == [P, 0, 0, P, P, 0, P, P, P]
			or pattern == [0, 0, P, 0, P, P, P, P, P]
		):
			return {"id": BlockRegistry.BlockId.WOOD_STAIRS, "count": 4}
		if (
			pattern == [C, 0, 0, C, C, 0, C, C, C]
			or pattern == [0, 0, C, 0, C, C, C, C, C]
		):
			return {"id": BlockRegistry.BlockId.COBBLE_STAIRS, "count": 4}

		# Bow: 3 Sticks + 3 Strings
		var STR: int = ItemId.STRING
		if (
			pattern == [0, S, STR, S, 0, STR, 0, S, STR]
			or pattern == [STR, S, 0, STR, 0, S, STR, S, 0]
		):
			return {"id": ItemId.BOW, "count": 1}

		# Fishing Rod: 3 Sticks diagonal + 2 Strings
		if (
			pattern == [0, 0, S, 0, S, STR, S, 0, STR]
			or pattern == [S, 0, 0, STR, S, 0, STR, 0, S]
		):
			return {"id": ItemId.FISHING_ROD, "count": 1}

	return {"id": 0, "count": 0}

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
		ItemId.RAW_CHICKEN:
			return ItemId.COOKED_CHICKEN
		ItemId.POTATO:
			return ItemId.BAKED_POTATO
		BlockRegistry.BlockId.COBBLESTONE:
			return BlockRegistry.BlockId.STONE
		BlockRegistry.BlockId.WOOD_LOG, BlockRegistry.BlockId.PINE_LOG, BlockRegistry.BlockId.BIRCH_LOG:
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
		BlockRegistry.BlockId.WOOD_LOG, BlockRegistry.BlockId.PINE_LOG, BlockRegistry.BlockId.BIRCH_LOG:
			return 8.0
		BlockRegistry.BlockId.WOOD_PLANKS, BlockRegistry.BlockId.WOOD_STAIRS, BlockRegistry.BlockId.CRAFTING_TABLE, BlockRegistry.BlockId.CHEST:
			return 4.0
		ItemId.STICK, BlockRegistry.BlockId.SAPLING, BlockRegistry.BlockId.PINE_SAPLING, BlockRegistry.BlockId.BIRCH_SAPLING:
			return 2.0
		_:
			return 0.0
