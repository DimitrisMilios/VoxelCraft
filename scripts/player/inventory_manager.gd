class_name InventoryManager
extends Node
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
}

enum ToolCategory {
	NONE = 0,
	PICKAXE = 1,
	AXE = 2,
	SHOVEL = 3,
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


func _ready() -> void:
	add_to_group("inventory_manager")
	slots.resize(TOTAL_SLOTS)
	for i in range(TOTAL_SLOTS):
		slots[i] = {"id": 0, "count": 0}

	set_crafting_grid_dimension(2)


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

static func is_tool(item_id: int) -> bool:
	return item_id >= ItemId.WOOD_PICKAXE and item_id <= ItemId.DIAMOND_SHOVEL


static func is_placeable_block(item_id: int) -> bool:
	return item_id > 0 and item_id < 100 and item_id != BlockRegistry.BlockId.WATER


static func get_tool_category(item_id: int) -> int:
	if item_id >= ItemId.WOOD_PICKAXE and item_id <= ItemId.DIAMOND_PICKAXE:
		return ToolCategory.PICKAXE
	if item_id >= ItemId.WOOD_AXE and item_id <= ItemId.DIAMOND_AXE:
		return ToolCategory.AXE
	if item_id >= ItemId.WOOD_SHOVEL and item_id <= ItemId.DIAMOND_SHOVEL:
		return ToolCategory.SHOVEL
	return ToolCategory.NONE


## Returns tool tier: 0 = Hand/None, 1 = Wood, 2 = Stone, 3 = Iron, 4 = Diamond.
static func get_tool_tier(item_id: int) -> int:
	match item_id:
		ItemId.WOOD_PICKAXE, ItemId.WOOD_AXE, ItemId.WOOD_SHOVEL:
			return 1
		ItemId.STONE_PICKAXE, ItemId.STONE_AXE, ItemId.STONE_SHOVEL:
			return 2
		ItemId.IRON_PICKAXE, ItemId.IRON_AXE, ItemId.IRON_SHOVEL:
			return 3
		ItemId.DIAMOND_PICKAXE, ItemId.DIAMOND_AXE, ItemId.DIAMOND_SHOVEL:
			return 4
		_:
			return 0


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
		ItemId.WOOD_PICKAXE, ItemId.WOOD_AXE, ItemId.WOOD_SHOVEL:
			return Color(0.68, 0.50, 0.28)
		ItemId.STONE_PICKAXE, ItemId.STONE_AXE, ItemId.STONE_SHOVEL:
			return Color(0.56, 0.58, 0.62)
		ItemId.IRON_PICKAXE, ItemId.IRON_AXE, ItemId.IRON_SHOVEL:
			return Color(0.88, 0.90, 0.95)
		ItemId.DIAMOND_PICKAXE, ItemId.DIAMOND_AXE, ItemId.DIAMOND_SHOVEL:
			return Color(0.26, 0.94, 0.96)
		_:
			return BlockRegistry.get_block_color(item_id)


# ============================================================================
# INVENTORY SLOT & STACK OPERATIONS
# ============================================================================

func get_hotbar_slot(slot_idx: int) -> Dictionary:
	if slot_idx < 0 or slot_idx >= HOTBAR_SIZE:
		return {"id": 0, "count": 0}
	return slots[slot_idx]


func get_total_count(item_id: int) -> int:
	var total: int = 0
	for slot in slots:
		if int(slot["id"]) == item_id:
			total += int(slot["count"])
	return total


## Adds `amount` of `item_id` into hotbar/backpack (stacking existing first, then empty slots).
func add_item(item_id: int, amount: int = 1) -> bool:
	if item_id <= 0 or amount <= 0:
		return false

	var max_stack_for_item: int = 1 if is_tool(item_id) else MAX_STACK
	var remaining: int = amount

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
			slots[i] = {"id": item_id, "count": to_place}
			remaining -= to_place
			if remaining <= 0:
				inventory_updated.emit()
				return true

	inventory_updated.emit()
	return remaining < amount


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
func click_inventory_slot(slot_idx: int, mouse_button: int) -> void:
	if slot_idx < 0 or slot_idx >= TOTAL_SLOTS:
		return
	slots[slot_idx] = _interact_slot_with_cursor(slots[slot_idx], mouse_button)
	inventory_updated.emit()


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

	var cur_id: int = int(cursor_stack.get("id", 0))
	var cur_count: int = int(cursor_stack.get("count", 0))
	var max_stk: int = 1 if is_tool(out_id) else MAX_STACK

	if cur_id != 0 and (cur_id != out_id or cur_count + out_count > max_stk):
		return

	if cur_id == 0:
		cursor_stack = {"id": out_id, "count": out_count}
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


func _interact_slot_with_cursor(target_slot: Dictionary, mouse_button: int) -> Dictionary:
	var slot_id: int = int(target_slot.get("id", 0))
	var slot_cnt: int = int(target_slot.get("count", 0))
	var cur_id: int = int(cursor_stack.get("id", 0))
	var cur_cnt: int = int(cursor_stack.get("count", 0))

	if mouse_button == MOUSE_BUTTON_LEFT:
		if cur_id == 0:
			# Pick up entire slot stack onto cursor
			cursor_stack = {"id": slot_id, "count": slot_cnt}
			return {"id": 0, "count": 0}
		elif slot_id == 0:
			# Place entire cursor stack into empty slot
			var placed := {"id": cur_id, "count": cur_cnt}
			cursor_stack = {"id": 0, "count": 0}
			return placed
		elif slot_id == cur_id and not is_tool(slot_id):
			# Merge stacks up to MAX_STACK
			var space: int = MAX_STACK - slot_cnt
			var move_cnt: int = mini(cur_cnt, space)
			slot_cnt += move_cnt
			cur_cnt -= move_cnt
			if cur_cnt <= 0:
				cursor_stack = {"id": 0, "count": 0}
			else:
				cursor_stack["count"] = cur_cnt
			return {"id": slot_id, "count": slot_cnt}
		else:
			# Swap cursor and slot
			cursor_stack = {"id": slot_id, "count": slot_cnt}
			return {"id": cur_id, "count": cur_cnt}

	elif mouse_button == MOUSE_BUTTON_RIGHT:
		if cur_id == 0 and slot_id != 0:
			# Split stack: pick up half (rounded up)
			var take_half: int = int(ceil(float(slot_cnt) * 0.5))
			var leave_half: int = slot_cnt - take_half
			cursor_stack = {"id": slot_id, "count": take_half}
			if leave_half <= 0:
				return {"id": 0, "count": 0}
			return {"id": slot_id, "count": leave_half}
		elif cur_id != 0:
			# Place 1 single item from cursor into empty or matching slot
			if slot_id == 0:
				cursor_stack["count"] = cur_cnt - 1
				if int(cursor_stack["count"]) <= 0:
					cursor_stack = {"id": 0, "count": 0}
				return {"id": cur_id, "count": 1}
			elif slot_id == cur_id and not is_tool(slot_id) and slot_cnt < MAX_STACK:
				cursor_stack["count"] = cur_cnt - 1
				if int(cursor_stack["count"]) <= 0:
					cursor_stack = {"id": 0, "count": 0}
				return {"id": slot_id, "count": slot_cnt + 1}

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
		# 1 Coal over 1 Stick -> 4 Glowstone Torches/Lanterns
		if pattern == [COAL_ID, S]:
			return {"id": BlockRegistry.BlockId.GLOWSTONE, "count": 4}

	# 3. 2x2 Patterns (Works in both 2x2 and 3x3!)
	if box_w == 2 and box_h == 2:
		# 4 Wood Planks in 2x2 -> 1 Crafting Table
		if pattern == [P, P, P, P]:
			return {"id": BlockRegistry.BlockId.CRAFTING_TABLE, "count": 1}

	# 4. 3x3 Patterns (Requires 3x3 Crafting Table!)
	if box_w == 3 and box_h == 3:
		# Furnace (8 Cobblestone ring)
		if pattern == [C, C, C, C, 0, C, C, C, C]:
			return {"id": BlockRegistry.BlockId.FURNACE, "count": 1}

		# Pickaxes: [M, M, M, 0, S, 0, 0, S, 0]
		if pattern == [P, P, P, 0, S, 0, 0, S, 0]:
			return {"id": ItemId.WOOD_PICKAXE, "count": 1}
		if pattern == [C, C, C, 0, S, 0, 0, S, 0]:
			return {"id": ItemId.STONE_PICKAXE, "count": 1}
		if pattern == [FE, FE, FE, 0, S, 0, 0, S, 0]:
			return {"id": ItemId.IRON_PICKAXE, "count": 1}
		if pattern == [D, D, D, 0, S, 0, 0, S, 0]:
			return {"id": ItemId.DIAMOND_PICKAXE, "count": 1}

	# 5. Shovels: 1x3 Vertical [M, S, S]
	if box_w == 1 and box_h == 3:
		if pattern == [P, S, S]:
			return {"id": ItemId.WOOD_SHOVEL, "count": 1}
		if pattern == [C, S, S]:
			return {"id": ItemId.STONE_SHOVEL, "count": 1}
		if pattern == [FE, S, S]:
			return {"id": ItemId.IRON_SHOVEL, "count": 1}
		if pattern == [D, S, S]:
			return {"id": ItemId.DIAMOND_SHOVEL, "count": 1}

	# 6. Axes: 2x3 [M, M, M, S, 0, S] or mirrored [M, M, S, M, S, 0]
	if box_w == 2 and box_h == 3:
		if pattern == [P, P, P, S, 0, S] or pattern == [P, P, S, P, S, 0]:
			return {"id": ItemId.WOOD_AXE, "count": 1}
		if pattern == [C, C, C, S, 0, S] or pattern == [C, C, S, C, S, 0]:
			return {"id": ItemId.STONE_AXE, "count": 1}
		if pattern == [FE, FE, FE, S, 0, S] or pattern == [FE, FE, S, FE, S, 0]:
			return {"id": ItemId.IRON_AXE, "count": 1}
		if pattern == [D, D, D, S, 0, S] or pattern == [D, D, S, D, S, 0]:
			return {"id": ItemId.DIAMOND_AXE, "count": 1}

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
