@tool
extends SceneTree
## Automated Unit & Integration Tests for Phase 2:
## - Block Metadata (4-bit nibbles, stairs orientation, wool vertex tinting, slabs)
## - Persistence of metadata via ChunkStorage
## - Authentic TrueCraft Beta 1.7.3 Recipe Catalog (burger-b1.7.json)
## - Shift-Click container and loop-crafting transfers

func _init() -> void:
	print("=== Running TrueCraft Phase 2 Verification Test Suite ===")
	var total_tests: int = 0
	var passed_tests: int = 0

	# ------------------------------------------------------------------------
	# Test 1: Block Registry & Phase 2 Definitions
	# ------------------------------------------------------------------------
	total_tests += 1
	print("\n--- Test 1: Block Registry Phase 2 Definitions ---")
	assert(BlockRegistry.BlockId.GOLD_BLOCK == 64, "GOLD_BLOCK id mismatch")
	assert(BlockRegistry.BlockId.IRON_BLOCK == 65, "IRON_BLOCK id mismatch")
	assert(BlockRegistry.BlockId.DIAMOND_BLOCK == 66, "DIAMOND_BLOCK id mismatch")
	assert(BlockRegistry.BlockId.LAPIS_BLOCK == 67, "LAPIS_BLOCK id mismatch")
	assert(BlockRegistry.BlockId.REDSTONE_TORCH == 68, "REDSTONE_TORCH id mismatch")
	assert(BlockRegistry.BlockId.LEVER == 69, "LEVER id mismatch")
	assert(BlockRegistry.BlockId.BUTTON == 70, "BUTTON id mismatch")
	assert(BlockRegistry.BlockId.WOOD_STAIRS == 71, "WOOD_STAIRS id mismatch")
	assert(BlockRegistry.BlockId.COBBLE_STAIRS == 72, "COBBLE_STAIRS id mismatch")
	assert(BlockRegistry.BlockId.SLAB == 73, "SLAB id mismatch")
	assert(BlockRegistry.WOOL_COLORS.size() == 16, "Must define 16 Beta wool colors")
	assert(BlockRegistry.is_light_emitter(BlockRegistry.BlockId.REDSTONE_TORCH), "Redstone torch must emit light")
	assert(not BlockRegistry.is_opaque_full_cube(BlockRegistry.BlockId.WOOD_STAIRS), "Stairs must not be opaque full cube")
	assert(not BlockRegistry.is_opaque_full_cube(BlockRegistry.BlockId.SLAB), "Slab must not be opaque full cube")
	
	# Slab UV metadata variations
	var uv_stone_slab: Rect2 = BlockRegistry.get_tile_uv_rect(BlockRegistry.BlockId.SLAB, BlockRegistry.FaceDir.TOP, 0)
	var uv_wood_slab: Rect2 = BlockRegistry.get_tile_uv_rect(BlockRegistry.BlockId.SLAB, BlockRegistry.FaceDir.TOP, 2)
	assert(uv_stone_slab != uv_wood_slab, "Slab metadata 0 and 2 must have distinct UVs")

	print("  PASS: Block Registry Phase 2 definitions verified.")
	passed_tests += 1

	# ------------------------------------------------------------------------
	# Test 2: Chunk 4-bit Metadata Storage & Lazy Allocation
	# ------------------------------------------------------------------------
	total_tests += 1
	print("\n--- Test 2: Chunk 4-bit Metadata Storage ---")
	var chunk := VoxelChunk.new()
	assert(chunk.get_metadata_buffer().is_empty(), "Chunk metadata buffer must initially be empty (lazy alloc)")
	assert(chunk.get_metadata_local(5, 10, 5) == 0, "Default metadata must be 0")

	# Set even and odd adjacent voxel metadata
	chunk.set_metadata_local(0, 50, 0, 9) # even index
	chunk.set_metadata_local(1, 50, 0, 14) # odd index
	assert(not chunk.get_metadata_buffer().is_empty(), "Setting metadata must allocate buffer")
	assert(chunk.get_metadata_local(0, 50, 0) == 9, "Even index metadata mismatch")
	assert(chunk.get_metadata_local(1, 50, 0) == 14, "Odd index metadata mismatch")

	# Verify overwriting one does not corrupt the adjacent nibble
	chunk.set_metadata_local(0, 50, 0, 3)
	assert(chunk.get_metadata_local(0, 50, 0) == 3, "Overwritten even index mismatch")
	assert(chunk.get_metadata_local(1, 50, 0) == 14, "Odd index corrupted by even write")

	chunk.free()
	print("  PASS: Chunk 4-bit metadata nibble storage verified.")
	passed_tests += 1

	# ------------------------------------------------------------------------
	# Test 3: Chunk Meshing with Stairs, Slabs, and Wool Colors
	# ------------------------------------------------------------------------
	total_tests += 1
	print("\n--- Test 3: Sub-chunk Meshing with Stairs, Slabs & Wool ---")
	var mesh_chunk := VoxelChunk.new()
	mesh_chunk.generate_terrain(FastNoiseLite.new())
	# Place Wood Stairs facing East (meta 0)
	mesh_chunk.set_block_local(2, 60, 2, BlockRegistry.BlockId.WOOD_STAIRS)
	mesh_chunk.set_metadata_local(2, 60, 2, 0)
	# Place Slab (Wood slab meta 2)
	mesh_chunk.set_block_local(3, 60, 2, BlockRegistry.BlockId.SLAB)
	mesh_chunk.set_metadata_local(3, 60, 2, 2)
	# Place Wool with Red color (meta 14)
	mesh_chunk.set_block_local(4, 60, 2, BlockRegistry.BlockId.WOOL)
	mesh_chunk.set_metadata_local(4, 60, 2, 14)

	var sub_data: Dictionary = mesh_chunk._build_single_sub_chunk_data(3) # ly = 60 is sub-chunk 3 (48..63)
	assert(sub_data.get("mesh") != null, "Solid mesh must be generated")
	assert(sub_data.get("shape") != null, "Trimesh collider shape must be generated")
	mesh_chunk.free()
	print("  PASS: Custom stair, slab, and wool meshing generated without error.")
	passed_tests += 1

	# ------------------------------------------------------------------------
	# Test 4: Chunk Storage Persistence with Metadata
	# ------------------------------------------------------------------------
	total_tests += 1
	print("\n--- Test 4: Chunk Storage Persistence ---")
	var temp_save_dir: String = "user://test_p2_saves"
	var storage := ChunkStorage.new(temp_save_dir)
	var test_coord := Vector2i(77, -88)
	var raw_voxels := PackedByteArray()
	raw_voxels.resize(VoxelChunk.CHUNK_SIZE_X * VoxelChunk.CHUNK_SIZE_Y * VoxelChunk.CHUNK_SIZE_Z)
	raw_voxels.fill(BlockRegistry.BlockId.AIR)
	raw_voxels[100] = BlockRegistry.BlockId.WOOD_STAIRS

	var raw_meta := PackedByteArray()
	raw_meta.resize((VoxelChunk.CHUNK_SIZE_X * VoxelChunk.CHUNK_SIZE_Y * VoxelChunk.CHUNK_SIZE_Z) / 2)
	raw_meta.fill(0)
	raw_meta[50] = 0x2A # meta values 10 and 2

	storage.store_modified_chunk(test_coord, raw_voxels, 64, raw_meta, true)
	var loaded_data: Dictionary = storage.load_chunk_data(test_coord)
	assert(not loaded_data.is_empty(), "Failed to load stored chunk")
	assert(loaded_data["voxels"].size() == raw_voxels.size(), "Voxel buffer size mismatch")
	assert((loaded_data["metadata"] as PackedByteArray)[50] == 0x2A, "Metadata buffer persistence mismatch")

	# Cleanup test file
	var test_file_path: String = "%s/chunk_%d_%d.vxc" % [temp_save_dir, test_coord.x, test_coord.y]
	if FileAccess.file_exists(test_file_path):
		DirAccess.remove_absolute(test_file_path)

	print("  PASS: Metadata persistence and round-trip load verified.")
	passed_tests += 1

	# ------------------------------------------------------------------------
	# Test 5: Authentic Beta 1.7.3 Recipe Catalog (burger-b1.7.json)
	# ------------------------------------------------------------------------
	total_tests += 1
	print("\n--- Test 5: Recipe Book Matrix ---")
	var inv := InventoryManager.new()
	inv._ready()

	# 1. Planks from Pine Log (1-cell)
	inv.set_crafting_grid_dimension(2)
	inv.craft_grid[0] = {"id": BlockRegistry.BlockId.PINE_LOG, "count": 1}
	var out: Dictionary = inv._match_crafting_grid()
	assert(out["id"] == BlockRegistry.BlockId.WOOD_PLANKS and out["count"] == 4, "Pine log -> 4 Planks failed")

	# 2. Sticks (1x2)
	inv.craft_grid[0] = {"id": BlockRegistry.BlockId.WOOD_PLANKS, "count": 1}
	inv.craft_grid[2] = {"id": BlockRegistry.BlockId.WOOD_PLANKS, "count": 1}
	inv.craft_grid[1] = {"id": 0, "count": 0}
	inv.craft_grid[3] = {"id": 0, "count": 0}
	out = inv._match_crafting_grid()
	assert(out["id"] == InventoryManager.ItemId.STICK and out["count"] == 4, "Planks 1x2 -> 4 Sticks failed")

	# 3. Torches (1x2 Coal + Stick)
	inv.craft_grid[0] = {"id": InventoryManager.ItemId.COAL, "count": 1}
	inv.craft_grid[2] = {"id": InventoryManager.ItemId.STICK, "count": 1}
	out = inv._match_crafting_grid()
	assert(out["id"] == BlockRegistry.BlockId.TORCH and out["count"] == 4, "Coal + Stick -> 4 Torches failed")

	# 4. Redstone Torch (1x2 Redstone + Stick)
	inv.craft_grid[0] = {"id": InventoryManager.ItemId.REDSTONE, "count": 1}
	inv.craft_grid[2] = {"id": InventoryManager.ItemId.STICK, "count": 1}
	out = inv._match_crafting_grid()
	assert(out["id"] == BlockRegistry.BlockId.REDSTONE_TORCH and out["count"] == 1, "Redstone Torch failed")

	# 5. Lever (1x2 Stick + Cobble)
	inv.craft_grid[0] = {"id": InventoryManager.ItemId.STICK, "count": 1}
	inv.craft_grid[2] = {"id": BlockRegistry.BlockId.COBBLESTONE, "count": 1}
	out = inv._match_crafting_grid()
	assert(out["id"] == BlockRegistry.BlockId.LEVER and out["count"] == 1, "Lever failed")

	# 6. Slabs (3x1 Horizontal: 3 Cobble -> 6 Slabs)
	inv.set_crafting_grid_dimension(3)
	inv.craft_grid[0] = {"id": BlockRegistry.BlockId.COBBLESTONE, "count": 1}
	inv.craft_grid[1] = {"id": BlockRegistry.BlockId.COBBLESTONE, "count": 1}
	inv.craft_grid[2] = {"id": BlockRegistry.BlockId.COBBLESTONE, "count": 1}
	out = inv._match_crafting_grid()
	assert(out["id"] == BlockRegistry.BlockId.SLAB and out["count"] == 6, "3 Cobble -> 6 Slabs failed")

	# 7. Stairs (3x3 Stair shape)
	inv.set_crafting_grid_dimension(3)
	var P: int = BlockRegistry.BlockId.WOOD_PLANKS
	inv.craft_grid = [
		{"id": P, "count": 1}, {"id": 0, "count": 0}, {"id": 0, "count": 0},
		{"id": P, "count": 1}, {"id": P, "count": 1}, {"id": 0, "count": 0},
		{"id": P, "count": 1}, {"id": P, "count": 1}, {"id": P, "count": 1},
	]
	out = inv._match_crafting_grid()
	assert(out["id"] == BlockRegistry.BlockId.WOOD_STAIRS and out["count"] == 4, "Wood Stairs failed")

	# 8. Gold Tools & Armor
	# Golden Pickaxe (3x3)
	var AU: int = InventoryManager.ItemId.GOLD_INGOT
	var S: int = InventoryManager.ItemId.STICK
	inv.craft_grid = [
		{"id": AU, "count": 1}, {"id": AU, "count": 1}, {"id": AU, "count": 1},
		{"id": 0, "count": 0},  {"id": S, "count": 1},  {"id": 0, "count": 0},
		{"id": 0, "count": 0},  {"id": S, "count": 1},  {"id": 0, "count": 0},
	]
	out = inv._match_crafting_grid()
	assert(out["id"] == InventoryManager.ItemId.GOLD_PICKAXE and out["count"] == 1, "Golden Pickaxe failed")

	# Diamond Chestplate (3x3)
	var D: int = InventoryManager.ItemId.DIAMOND
	inv.craft_grid = [
		{"id": D, "count": 1}, {"id": 0, "count": 0}, {"id": D, "count": 1},
		{"id": D, "count": 1}, {"id": D, "count": 1}, {"id": D, "count": 1},
		{"id": D, "count": 1}, {"id": D, "count": 1}, {"id": D, "count": 1},
	]
	out = inv._match_crafting_grid()
	assert(out["id"] == InventoryManager.ItemId.DIAMOND_CHESTPLATE and out["count"] == 1, "Diamond Chestplate failed")

	# Bow (3x3)
	var STR: int = InventoryManager.ItemId.STRING
	inv.craft_grid = [
		{"id": 0, "count": 0},   {"id": S, "count": 1},   {"id": STR, "count": 1},
		{"id": S, "count": 1},   {"id": 0, "count": 0},   {"id": STR, "count": 1},
		{"id": 0, "count": 0},   {"id": S, "count": 1},   {"id": STR, "count": 1},
	]
	out = inv._match_crafting_grid()
	assert(out["id"] == InventoryManager.ItemId.BOW and out["count"] == 1, "Bow crafting failed")

	# Arrows (1x3 Flint, Stick, Feather)
	inv.set_crafting_grid_dimension(3)
	inv.craft_grid[0] = {"id": InventoryManager.ItemId.FLINT, "count": 1}
	inv.craft_grid[3] = {"id": S, "count": 1}
	inv.craft_grid[6] = {"id": InventoryManager.ItemId.FEATHER, "count": 1}
	out = inv._match_crafting_grid()
	assert(out["id"] == InventoryManager.ItemId.ARROW and out["count"] == 4, "Arrows crafting failed")

	# Storage Blocks: 9 Iron -> 1 Iron Block, and 1 Iron Block -> 9 Iron Ingots
	var FE: int = InventoryManager.ItemId.IRON_INGOT
	inv.craft_grid = [
		{"id": FE, "count": 1}, {"id": FE, "count": 1}, {"id": FE, "count": 1},
		{"id": FE, "count": 1}, {"id": FE, "count": 1}, {"id": FE, "count": 1},
		{"id": FE, "count": 1}, {"id": FE, "count": 1}, {"id": FE, "count": 1},
	]
	out = inv._match_crafting_grid()
	assert(out["id"] == BlockRegistry.BlockId.IRON_BLOCK and out["count"] == 1, "9 Iron -> 1 Iron Block failed")

	inv.craft_grid = [
		{"id": BlockRegistry.BlockId.IRON_BLOCK, "count": 1}, {"id": 0, "count": 0}, {"id": 0, "count": 0},
		{"id": 0, "count": 0}, {"id": 0, "count": 0}, {"id": 0, "count": 0},
		{"id": 0, "count": 0}, {"id": 0, "count": 0}, {"id": 0, "count": 0},
	]
	out = inv._match_crafting_grid()
	assert(out["id"] == InventoryManager.ItemId.IRON_INGOT and out["count"] == 9, "1 Iron Block -> 9 Iron Ingots failed")

	# Shapeless: Mushroom Stew
	inv.craft_grid = [
		{"id": InventoryManager.ItemId.BOWL, "count": 1}, {"id": 0, "count": 0}, {"id": 0, "count": 0},
		{"id": 0, "count": 0}, {"id": BlockRegistry.BlockId.BROWN_MUSHROOM, "count": 1}, {"id": 0, "count": 0},
		{"id": 0, "count": 0}, {"id": 0, "count": 0}, {"id": BlockRegistry.BlockId.RED_MUSHROOM, "count": 1},
	]
	out = inv._match_crafting_grid()
	assert(out["id"] == InventoryManager.ItemId.MUSHROOM_STEW and out["count"] == 1, "Mushroom Stew failed")

	inv.free()
	print("  PASS: Recipe book matrix verified matching Beta 1.7.3 catalog.")
	passed_tests += 1

	# ------------------------------------------------------------------------
	# Test 6: Shift-Click Container Transfers & Batch Crafting
	# ------------------------------------------------------------------------
	total_tests += 1
	print("\n--- Test 6: Shift-Click Container Transfers & Batch Crafting ---")
	var shift_inv := InventoryManager.new()
	shift_inv._ready()

	# 1. Hotbar <-> Backpack transfer
	shift_inv.slots[0] = {"id": InventoryManager.ItemId.APPLE, "count": 16}
	var rem: int = shift_inv._insert_into_range(InventoryManager.ItemId.APPLE, 16, -1, InventoryManager.HOTBAR_SIZE, InventoryManager.TOTAL_SLOTS)
	assert(rem == 0, "Failed to transfer into backpack")
	assert(shift_inv.slots[9]["id"] == InventoryManager.ItemId.APPLE and shift_inv.slots[9]["count"] == 16, "Backpack slot 9 mismatch")

	# 2. Transfer into Chest when Chest is open
	var chest_pos := Vector3i(10, 20, 30)
	shift_inv.open_chest_at(chest_pos)
	assert(shift_inv.is_chest_open, "Chest must be open")
	var c_slots: Array = shift_inv.get_active_chest_slots()
	var chest_rem: int = shift_inv._insert_into_slot_list(c_slots, InventoryManager.ItemId.DIAMOND, 5, -1, 0, c_slots.size())
	assert(chest_rem == 0, "Failed to transfer into chest")
	assert(c_slots[0]["id"] == InventoryManager.ItemId.DIAMOND and c_slots[0]["count"] == 5, "Chest slot 0 mismatch")

	# 3. Shift-Click Batch Crafting Loop
	shift_inv.close_container()
	shift_inv.set_crafting_grid_dimension(2)
	# 10 Wood Logs in crafting cell 0 -> Output is 4 Wood Planks
	shift_inv.craft_grid[0] = {"id": BlockRegistry.BlockId.WOOD_LOG, "count": 10}
	shift_inv._recalculate_crafting_output()
	assert(int(shift_inv.craft_output["id"]) == BlockRegistry.BlockId.WOOD_PLANKS, "Expected planks output")

	# Execute shift-click craft output logic:
	var max_loops: int = 64
	var loop_n: int = 0
	while loop_n < max_loops:
		var c_id: int = int(shift_inv.craft_output.get("id", 0))
		var c_cnt: int = int(shift_inv.craft_output.get("count", 0))
		if c_id == 0 or c_cnt <= 0:
			break
		if not shift_inv.can_fit_item(c_id, c_cnt):
			break
		var unplaced: int = shift_inv.add_item_stack(c_id, c_cnt)
		if unplaced > 0:
			break
		for i in range(shift_inv.craft_grid.size()):
			if int(shift_inv.craft_grid[i].get("id", 0)) != 0:
				shift_inv.craft_grid[i]["count"] = int(shift_inv.craft_grid[i]["count"]) - 1
				if int(shift_inv.craft_grid[i]["count"]) <= 0:
					shift_inv.craft_grid[i] = {"id": 0, "count": 0}
		shift_inv._recalculate_crafting_output()
		loop_n += 1

	assert(loop_n == 10, "Expected all 10 logs to be converted in batch-craft loop, got: %d" % loop_n)
	assert(shift_inv.get_total_count(BlockRegistry.BlockId.WOOD_PLANKS) == 40, "Expected 40 wood planks created")
	assert(int(shift_inv.craft_grid[0]["count"]) == 0, "Craft grid should be empty after craft-all")

	shift_inv.free()
	print("  PASS: Shift-click container routing and batch-craft loop verified.")
	passed_tests += 1

	# ------------------------------------------------------------------------
	# Summary
	# ------------------------------------------------------------------------
	print("\n==================================================")
	print("TrueCraft Phase 2 Verification Suite: %d / %d PASSED" % [passed_tests, total_tests])
	print("==================================================")
	quit(0 if passed_tests == total_tests else 1)
