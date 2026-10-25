class_name InventoryManager
extends Node
## Manages player inventory counts, resources, pickaxe tools, crafting recipes, and furnace smelting.

signal inventory_updated()
signal tool_upgraded(new_tool_id: int)

enum ItemId {
	# Non-block crafting & ore resources (100+)
	STICK = 100,
	COAL = 101,
	RAW_IRON = 102,
	IRON_INGOT = 103,
	RAW_GOLD = 104,
	GOLD_INGOT = 105,
	DIAMOND = 106,

	# Pickaxe Tools (200+)
	WOOD_PICKAXE = 201,
	STONE_PICKAXE = 202,
	IRON_PICKAXE = 203,
	DIAMOND_PICKAXE = 204,
}

## Maps item/block ID -> quantity owned.
var _counts: Dictionary = {}

## Currently owned highest-tier pickaxe (starts with Wooden Pickaxe in slot 0).
var equipped_pickaxe_id: int = ItemId.WOOD_PICKAXE


func _ready() -> void:
	add_to_group("inventory_manager")
	# Starter kit so the player can immediately place stations or mine and build
	_counts[ItemId.WOOD_PICKAXE] = 1
	_counts[BlockRegistry.BlockId.CRAFTING_TABLE] = 2
	_counts[BlockRegistry.BlockId.FURNACE] = 1
	_counts[BlockRegistry.BlockId.WOOD_LOG] = 8
	_counts[BlockRegistry.BlockId.WOOD_PLANKS] = 16
	_counts[BlockRegistry.BlockId.COBBLESTONE] = 16
	_counts[BlockRegistry.BlockId.GRASS] = 16
	_counts[BlockRegistry.BlockId.SAND] = 12
	_counts[BlockRegistry.BlockId.SNOW] = 12
	_counts[BlockRegistry.BlockId.GLOWSTONE] = 8
	_counts[ItemId.STICK] = 6
	_counts[ItemId.COAL] = 4


static func is_pickaxe(item_id: int) -> bool:
	return item_id >= ItemId.WOOD_PICKAXE and item_id <= ItemId.DIAMOND_PICKAXE


static func get_item_name(item_id: int) -> String:
	match item_id:
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
		ItemId.WOOD_PICKAXE:
			return "Wood Pick"
		ItemId.STONE_PICKAXE:
			return "Stone Pick"
		ItemId.IRON_PICKAXE:
			return "Iron Pick"
		ItemId.DIAMOND_PICKAXE:
			return "Diamond Pick"
		_:
			return BlockRegistry.get_block_name(item_id)


static func get_item_color(item_id: int) -> Color:
	match item_id:
		ItemId.STICK:
			return Color(0.58, 0.42, 0.22)
		ItemId.COAL:
			return Color(0.18, 0.19, 0.22)
		ItemId.RAW_IRON:
			return Color(0.82, 0.62, 0.46)
		ItemId.IRON_INGOT:
			return Color(0.86, 0.88, 0.92)
		ItemId.RAW_GOLD:
			return Color(0.95, 0.78, 0.22)
		ItemId.GOLD_INGOT:
			return Color(1.0, 0.86, 0.18)
		ItemId.DIAMOND:
			return Color(0.28, 0.94, 0.96)
		ItemId.WOOD_PICKAXE:
			return Color(0.68, 0.50, 0.28)
		ItemId.STONE_PICKAXE:
			return Color(0.56, 0.58, 0.62)
		ItemId.IRON_PICKAXE:
			return Color(0.88, 0.90, 0.95)
		ItemId.DIAMOND_PICKAXE:
			return Color(0.26, 0.94, 0.96)
		_:
			return BlockRegistry.get_block_color(item_id)


static func get_pickaxe_speed_multiplier(item_id: int, target_block_id: int) -> float:
	if not is_pickaxe(item_id):
		return 1.0
	var base_mult: float = 2.2
	match item_id:
		ItemId.WOOD_PICKAXE:
			base_mult = 2.4
		ItemId.STONE_PICKAXE:
			base_mult = 3.8
		ItemId.IRON_PICKAXE:
			base_mult = 5.8
		ItemId.DIAMOND_PICKAXE:
			base_mult = 9.5
	if BlockRegistry.is_stone_Or_ore(target_block_id):
		return base_mult
	return 1.5


func get_count(item_id: int) -> int:
	return int(_counts.get(item_id, 0))


func add_item(item_id: int, amount: int = 1) -> void:
	if amount <= 0:
		return
	_counts[item_id] = get_count(item_id) + amount
	inventory_updated.emit()


func consume_item(item_id: int, amount: int = 1) -> bool:
	var current: int = get_count(item_id)
	if current < amount:
		return false
	_counts[item_id] = current - amount
	inventory_updated.emit()
	return true


## Awards appropriate drops when a voxel block is broken in the world.
func award_block_drop(broken_block_id: int) -> String:
	match broken_block_id:
		BlockRegistry.BlockId.STONE:
			add_item(BlockRegistry.BlockId.COBBLESTONE, 1)
			return "+1 Cobblestone"
		BlockRegistry.BlockId.COAL_ORE:
			add_item(ItemId.COAL, 2)
			return "+2 Coal"
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
			return "+1 %s" % BlockRegistry.get_block_name(broken_block_id)


## Crafts a recipe at the Crafting Table. Returns status message.
func try_craft(recipe_id: String) -> Dictionary:
	match recipe_id:
		"planks":
			if not consume_item(BlockRegistry.BlockId.WOOD_LOG, 1):
				return {"ok": false, "msg": "Need 1 Wood Log"}
			add_item(BlockRegistry.BlockId.WOOD_PLANKS, 4)
			return {"ok": true, "msg": "Crafted 4 Wood Planks!"}

		"sticks":
			if not consume_item(BlockRegistry.BlockId.WOOD_PLANKS, 2):
				return {"ok": false, "msg": "Need 2 Wood Planks"}
			add_item(ItemId.STICK, 4)
			return {"ok": true, "msg": "Crafted 4 Sticks!"}

		"crafting_table":
			if not consume_item(BlockRegistry.BlockId.WOOD_PLANKS, 4):
				return {"ok": false, "msg": "Need 4 Wood Planks"}
			add_item(BlockRegistry.BlockId.CRAFTING_TABLE, 1)
			return {"ok": true, "msg": "Crafted 1 Crafting Table!"}

		"furnace":
			if not consume_item(BlockRegistry.BlockId.COBBLESTONE, 6):
				return {"ok": false, "msg": "Need 6 Cobblestone"}
			add_item(BlockRegistry.BlockId.FURNACE, 1)
			return {"ok": true, "msg": "Crafted 1 Furnace (Oven)!"}

		"glowstone":
			if get_count(ItemId.COAL) < 1 or get_count(ItemId.STICK) < 1:
				return {"ok": false, "msg": "Need 1 Coal + 1 Stick"}
			consume_item(ItemId.COAL, 1)
			consume_item(ItemId.STICK, 1)
			add_item(BlockRegistry.BlockId.GLOWSTONE, 4)
			return {"ok": true, "msg": "Crafted 4 Glowstone Lanterns!"}

		"stone_pickaxe":
			if get_count(BlockRegistry.BlockId.COBBLESTONE) < 3 or get_count(ItemId.STICK) < 2:
				return {"ok": false, "msg": "Need 3 Cobblestone + 2 Sticks"}
			consume_item(BlockRegistry.BlockId.COBBLESTONE, 3)
			consume_item(ItemId.STICK, 2)
			_upgrade_pickaxe(ItemId.STONE_PICKAXE)
			return {"ok": true, "msg": "Crafted Stone Pickaxe (3.8x Speed)!"}

		"iron_pickaxe":
			if get_count(ItemId.IRON_INGOT) < 3 or get_count(ItemId.STICK) < 2:
				return {"ok": false, "msg": "Need 3 Iron Ingots + 2 Sticks"}
			consume_item(ItemId.IRON_INGOT, 3)
			consume_item(ItemId.STICK, 2)
			_upgrade_pickaxe(ItemId.IRON_PICKAXE)
			return {"ok": true, "msg": "Crafted Iron Pickaxe (5.8x Speed)!"}

		"diamond_pickaxe":
			if get_count(ItemId.DIAMOND) < 3 or get_count(ItemId.STICK) < 2:
				return {"ok": false, "msg": "Need 3 Diamonds + 2 Sticks"}
			consume_item(ItemId.DIAMOND, 3)
			consume_item(ItemId.STICK, 2)
			_upgrade_pickaxe(ItemId.DIAMOND_PICKAXE)
			return {"ok": true, "msg": "Crafted Diamond Pickaxe (9.5x Speed)!"}

	return {"ok": false, "msg": "Unknown recipe"}


## Smelts ore in the Furnace / Oven using 1 Coal as fuel.
func try_smelt(smelt_id: String) -> Dictionary:
	match smelt_id:
		"iron_ingot":
			if get_count(ItemId.RAW_IRON) < 1 or get_count(ItemId.COAL) < 1:
				return {"ok": false, "msg": "Need 1 Raw Iron + 1 Coal"}
			consume_item(ItemId.RAW_IRON, 1)
			consume_item(ItemId.COAL, 1)
			add_item(ItemId.IRON_INGOT, 1)
			return {"ok": true, "msg": "Smelted 1 Iron Ingot in Oven!"}

		"gold_ingot":
			if get_count(ItemId.RAW_GOLD) < 1 or get_count(ItemId.COAL) < 1:
				return {"ok": false, "msg": "Need 1 Raw Gold + 1 Coal"}
			consume_item(ItemId.RAW_GOLD, 1)
			consume_item(ItemId.COAL, 1)
			add_item(ItemId.GOLD_INGOT, 1)
			return {"ok": true, "msg": "Smelted 1 Gold Ingot in Oven!"}

		"charcoal":
			if not consume_item(BlockRegistry.BlockId.WOOD_LOG, 1):
				return {"ok": false, "msg": "Need 1 Wood Log"}
			add_item(ItemId.COAL, 2)
			return {"ok": true, "msg": "Baked 1 Wood Log -> 2 Charcoal!"}

	return {"ok": false, "msg": "Unknown smelt recipe"}


func _upgrade_pickaxe(new_tool_id: int) -> void:
	_counts[new_tool_id] = 1
	equipped_pickaxe_id = new_tool_id
	tool_upgraded.emit(new_tool_id)
	inventory_updated.emit()
