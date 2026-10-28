extends SceneTree
## Verifies block mechanics: mining times per tool, harvest tiers and drops, doors, sugar cane,
## logs and leaf decay, and incremental lighting.
##
##   Godot --headless --path . -s tools/test_mechanics.gd

const B = BlockRegistry.BlockId
const I = InventoryManager.ItemId

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	print("--- Running Block Mechanics Tests ---")
	_test_mining_times()
	_test_harvest_and_drops()
	_test_door_shapes()

	var wm: WorldManager = _make_flat_world()
	_test_door_support(wm)
	_test_sugar_cane(wm)
	_test_logs_and_leaf_decay(wm)
	_test_lighting(wm)
	_test_crops(wm)
	_test_glass_and_recipes()
	_test_generated_sugar_cane()
	wm.free()

	if _failures == 0:
		print("--- All %d block mechanics checks PASSED ---" % _checks)
	else:
		printerr("--- %d of %d block mechanics checks FAILED ---" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + what)
	else:
		_failures += 1
		printerr("  FAIL: " + what)


func _ticks(item: int, block: int, water: bool = false, ground: bool = true) -> int:
	return InventoryManager.get_break_ticks(item, block, 0, water, ground)


func _test_mining_times() -> void:
	print("[1] Mining times (game ticks, 20 per second)")
	_check(_ticks(0, B.DIRT) == 15, "Dirt by hand: 0.75 s")
	_check(_ticks(I.WOOD_SHOVEL, B.DIRT) == 8, "Dirt with a wooden shovel: 0.4 s")
	_check(_ticks(0, B.STONE) == 150, "Stone by hand: 7.5 s (and drops nothing)")
	_check(_ticks(I.WOOD_PICKAXE, B.STONE) == 23, "Stone with wooden pickaxe: 1.15 s")
	_check(_ticks(I.STONE_PICKAXE, B.STONE) == 12, "Stone with stone pickaxe: 0.6 s")
	_check(_ticks(I.IRON_PICKAXE, B.STONE) == 8, "Stone with iron pickaxe: 0.4 s")
	_check(_ticks(I.DIAMOND_PICKAXE, B.STONE) == 6, "Stone with diamond pickaxe: 0.3 s")
	_check(_ticks(I.GOLD_PICKAXE, B.STONE) == 4, "Stone with gold pickaxe: 0.2 s")
	_check(_ticks(I.WOOD_PICKAXE, B.IRON_ORE) == 150, "Iron ore with wooden pickaxe: 7.5 s (cannot harvest)")
	_check(_ticks(I.STONE_PICKAXE, B.IRON_ORE) == 23, "Iron ore with stone pickaxe: 1.15 s")
	_check(_ticks(I.IRON_PICKAXE, B.DIAMOND_ORE) == 15, "Diamond ore with iron pickaxe: 0.75 s")
	_check(_ticks(I.DIAMOND_PICKAXE, B.OBSIDIAN) == 188, "Obsidian with diamond pickaxe: 9.4 s")
	_check(_ticks(I.IRON_PICKAXE, B.OBSIDIAN) == 834, "Obsidian with iron pickaxe: 41.7 s (cannot harvest)")
	_check(_ticks(0, B.WOOD_LOG) == 60, "Oak log by hand: 3 s")
	_check(_ticks(I.DIAMOND_AXE, B.PINE_LOG) == 8, "Spruce log with diamond axe: 0.4 s")
	_check(_ticks(I.WOOD_PICKAXE, B.WOOD_LOG) == 60, "Logs ignore pickaxes: 3 s")
	_check(_ticks(I.DIAMOND_SWORD, B.LEAVES) == 4, "Leaves with a sword: 0.2 s (by hand 0.3 s)")
	_check(_ticks(0, B.LEAVES) == 6, "Leaves by hand: 0.3 s")
	_check(_ticks(I.SHEARS, B.LEAVES) == 0, "Leaves with shears: instant")
	_check(_ticks(0, B.TORCH) == 0 and _ticks(0, B.SUGAR_CANE) == 0, "Torches and sugar cane break instantly")
	_check(_ticks(I.DIAMOND_PICKAXE, B.BEDROCK) == -1, "Bedrock is unbreakable")
	_check(_ticks(I.DIAMOND_PICKAXE, B.STONE, true) == 29, "Underwater mining is 5x slower")
	_check(_ticks(I.DIAMOND_PICKAXE, B.STONE, false, false) == 29, "Mining while airborne is 5x slower")


func _test_harvest_and_drops() -> void:
	print("[2] Harvest tiers and drops")
	_check(not InventoryManager.can_harvest_block(I.GOLD_PICKAXE, B.IRON_ORE), "Gold pickaxe cannot harvest iron ore")
	_check(InventoryManager.can_harvest_block(I.GOLD_PICKAXE, B.COAL_ORE), "Gold pickaxe harvests coal ore")
	_check(not InventoryManager.can_harvest_block(I.STONE_PICKAXE, B.DIAMOND_ORE), "Stone pickaxe cannot harvest diamond ore")
	_check(not InventoryManager.can_harvest_block(I.IRON_PICKAXE, B.OBSIDIAN), "Only diamond harvests obsidian")
	_check(InventoryManager.get_dropped_item_for_block(B.STONE, I.WOOD_PICKAXE) == B.COBBLESTONE, "Stone drops cobblestone")
	_check(InventoryManager.get_dropped_item_for_block(B.STONE, 0) == 0, "Stone by hand drops nothing")
	_check(InventoryManager.get_dropped_item_for_block(B.LEAVES, 0) == 0, "Leaves by hand do not drop leaves")
	_check(InventoryManager.get_dropped_item_for_block(B.LEAVES, I.SHEARS) == B.LEAVES, "Shears collect leaves")
	_check(InventoryManager.get_dropped_item_for_block(B.DOOR_OPEN, 0) == B.DOOR_CLOSED, "Doors drop the door item")
	var clay: Array = InventoryManager.get_block_drops(B.CLAY, 0)
	_check(clay.size() == 1 and clay[0][1] == 4, "Clay drops 4 clay balls")


func _test_door_shapes() -> void:
	print("[3] Door shapes")
	var east_left: int = BlockRegistry.door_meta_from_dir(Vector3i(1, 0, 0), false)
	var closed: AABB = BlockRegistry.get_door_box(east_left, false)
	_check(is_equal_approx(closed.size.x, 0.1875) and closed.position.x == 0.0, "Closed door sits on the edge nearest the player")
	var open_left: AABB = BlockRegistry.get_door_box(east_left, true)
	_check(is_equal_approx(open_left.size.z, 0.1875) and open_left.position.z == 0.0, "Opened left-hinged door lies along the hinge side")
	var east_right: int = BlockRegistry.door_meta_from_dir(Vector3i(1, 0, 0), true)
	var open_right: AABB = BlockRegistry.get_door_box(east_right, true)
	_check(is_equal_approx(open_right.position.z, 0.8125), "Right-hinged door opens to the other side")
	_check(BlockRegistry.door_facing_dir(BlockRegistry.door_meta_from_dir(Vector3i(0, 0, -1), true)) == Vector3i(0, 0, -1), "Door facing round-trips through metadata")


## A 16x16 chunk at (0, 0): bedrock at 0, stone to y 59, dirt 60-62, grass at 63; neighbors are
## flat too so lighting and support checks see real blocks across borders.
func _make_flat_world() -> WorldManager:
	var wm := WorldManager.new()
	for cx in range(-1, 2):
		for cz in range(-1, 2):
			var chunk := VoxelChunk.new()
			chunk.chunk_coords = Vector2i(cx, cz)
			var vox := PackedByteArray()
			vox.resize(16 * 256 * 16)
			for y in range(64):
				var id: int = B.STONE
				if y == 0:
					id = B.BEDROCK
				elif y >= 60 and y < 63:
					id = B.DIRT
				elif y == 63:
					id = B.GRASS
				for i in range(256):
					vox[(y << 8) | i] = id
			chunk.load_from_buffer(vox, 63)
			VoxelLighting.compute_chunk_lighting(chunk)
			wm._active_chunks[Vector2i(cx, cz)] = chunk
			wm.add_child(chunk)
	return wm


func _drops_of(wm: WorldManager, item: int) -> int:
	var total: int = 0
	for c in wm.get_children():
		if c is DroppedItem and c.item_id == item and not c.is_queued_for_deletion():
			total += c.count
	return total


func _clear_drops(wm: WorldManager) -> void:
	for c in wm.get_children():
		if c is DroppedItem:
			wm.remove_child(c)
			c.free()


func _test_door_support(wm: WorldManager) -> void:
	print("[4] Door support and toggling")
	var meta: int = BlockRegistry.door_meta_from_dir(Vector3i(0, 0, 1), true)
	wm.set_block_world(Vector3i(4, 64, 4), B.DOOR_CLOSED, 2, meta)
	wm.set_block_world(Vector3i(4, 65, 4), B.DOOR_CLOSED, 2, meta)
	_check(wm.get_metadata_world(Vector3i(4, 64, 4)) == meta, "Door keeps its facing/hinge metadata")
	_clear_drops(wm)
	wm.set_block_world(Vector3i(4, 63, 4), B.AIR)
	_check(wm.get_block_world(Vector3i(4, 64, 4)) == B.AIR and wm.get_block_world(Vector3i(4, 65, 4)) == B.AIR, "Removing the floor pops both door halves")
	_check(_drops_of(wm, B.DOOR_CLOSED) == 1, "A popped door drops exactly one door")
	wm.set_block_world(Vector3i(4, 63, 4), B.GRASS)
	_clear_drops(wm)


func _test_sugar_cane(wm: WorldManager) -> void:
	print("[5] Sugar cane")
	var ground := Vector3i(8, 63, 8)
	var cane := Vector3i(8, 64, 8)
	_check(not wm.can_sugar_cane_stay(cane), "Sugar cane cannot stand on grass without water beside it")
	wm.set_block_world(Vector3i(9, 63, 8), B.WATER)
	_check(wm.can_sugar_cane_stay(cane), "Sugar cane can stand on grass next to water")
	wm.set_block_world(ground, B.SAND)
	_check(wm.can_sugar_cane_stay(cane), "Sugar cane can stand on sand next to water")
	wm.set_block_world(cane, B.SUGAR_CANE)
	for i in range(80):
		wm.random_tick_block(cane)
		wm.random_tick_block(cane + Vector3i(0, 1, 0))
		wm.random_tick_block(cane + Vector3i(0, 2, 0))
	_check(wm.get_block_world(cane + Vector3i(0, 2, 0)) == B.SUGAR_CANE, "Sugar cane grows with random ticks")
	_check(wm.get_block_world(cane + Vector3i(0, 3, 0)) == B.AIR, "Sugar cane stops growing at 3 blocks")
	_clear_drops(wm)
	wm.set_block_world(Vector3i(9, 63, 8), B.GRASS)
	_check(wm.get_block_world(cane) == B.AIR and wm.get_block_world(cane + Vector3i(0, 2, 0)) == B.AIR, "Removing the water breaks the whole stalk")
	_check(_drops_of(wm, B.SUGAR_CANE) == 3, "Each broken cane block drops sugar cane")
	_clear_drops(wm)


func _test_logs_and_leaf_decay(wm: WorldManager) -> void:
	print("[6] Logs and leaves")
	_check(BlockRegistry.get_tile_index(B.WOOD_LOG, BlockRegistry.FaceDir.TOP, 0) == 5, "Upright log shows rings on top")
	_check(BlockRegistry.get_tile_index(B.WOOD_LOG, BlockRegistry.FaceDir.EAST, 1) == 5, "Log lying along X shows rings on its east/west ends")
	_check(BlockRegistry.get_tile_index(B.WOOD_LOG, BlockRegistry.FaceDir.TOP, 1) == 4, "Log lying along X shows bark on top")
	_check(BlockRegistry.get_tile_index(B.BIRCH_LOG, BlockRegistry.FaceDir.NORTH, 2) == BlockRegistry.TILE_BIRCH_LOG_TOP, "Birch log has its own end texture")
	var trunk := Vector3i(3, 64, 12)
	wm.set_block_world(trunk, B.WOOD_LOG)
	wm.set_block_world(trunk + Vector3i(1, 0, 0), B.LEAVES)
	wm.set_block_world(trunk + Vector3i(-1, 0, 0), B.LEAVES, 2, 8)
	wm.set_block_world(trunk, B.AIR)
	for i in range(200):
		wm._process_leaf_decay(1.0)
	_check(wm.get_block_world(trunk + Vector3i(1, 0, 0)) == B.AIR, "Natural leaves decay once their log is gone")
	_check(wm.get_block_world(trunk + Vector3i(-1, 0, 0)) == B.LEAVES, "Player-placed leaves never decay")
	_clear_drops(wm)


func _test_lighting(wm: WorldManager) -> void:
	print("[7] Incremental lighting")
	var p := Vector3i(12, 64, 3)
	_check(wm.get_block_light_world(p + Vector3i(2, 0, 0)) == 0, "No block light before placing a torch")
	wm.set_block_world(p, B.TORCH)
	_check(wm.get_block_light_world(p) == 14 and wm.get_block_light_world(p + Vector3i(2, 0, 0)) == 12, "Torch lights 14 at its block, 12 two blocks away")
	_check(wm.get_block_light_world(Vector3i(17, 64, 3)) == 9, "Torch light crosses chunk borders")
	wm.set_block_world(p, B.AIR)
	_check(wm.get_block_light_world(p + Vector3i(2, 0, 0)) == 0, "Removing the torch removes its light")
	var cave := Vector3i(10, 55, 10)
	wm.set_block_world(cave, B.AIR)
	_check(wm.get_sky_light_world(cave) == 0, "Sealed cave cell is dark")
	for y in range(56, 64):
		wm.set_block_world(Vector3i(10, y, 10), B.AIR)
	_check(wm.get_sky_light_world(cave) == 15, "Digging a shaft lets full daylight straight down")


func _test_generated_sugar_cane() -> void:
	print("[8] Generated sugar cane only grows beside water")
	var noise := FastNoiseLite.new()
	noise.seed = 2027
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.014
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var cane_total: int = 0
	var bad: int = 0
	for cx in range(-6, 6):
		for cz in range(-6, 6):
			var chunk := VoxelChunk.new()
			chunk.chunk_coords = Vector2i(cx, cz)
			chunk.generate_terrain(noise, null)
			for lx in range(16):
				for lz in range(16):
					for y in range(VoxelChunk.WATER_LEVEL, VoxelChunk.WATER_LEVEL + 3):
						if chunk.get_block_local(lx, y, lz) == B.SUGAR_CANE and chunk.get_block_local(lx, y - 1, lz) != B.SUGAR_CANE:
							cane_total += 1
							var wx: int = cx * 16 + lx
							var wz: int = cz * 16 + lz
							var near_water: bool = false
							for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
								if VoxelChunk.sample_surface_height(noise, wx + d.x, wz + d.y) < VoxelChunk.WATER_LEVEL:
									near_water = true
							if not near_water:
								bad += 1
			chunk.free()
	print("  (found %d sugar cane stalks)" % cane_total)
	_check(bad == 0, "Every generated stalk has water beside its base")


func _test_crops(wm: WorldManager) -> void:
	print("[9] Crop growth stages")
	var soil := Vector3i(13, 63, 13)
	var crop := soil + Vector3i(0, 1, 0)
	wm.set_block_world(soil, B.FARMLAND)
	wm.set_block_world(crop, B.WHEAT_SPROUT)
	_check(BlockRegistry.get_tile_index(B.WHEAT_SPROUT, 0, 3) == BlockRegistry.TILE_WHEAT_STAGE_0 + 3, "Each wheat age has its own texture")
	_check(not wm.is_farmland_hydrated(soil), "Farmland without water nearby is dry")
	var ticks_dry: int = 0
	while wm.get_block_world(crop) == B.WHEAT_SPROUT and ticks_dry < 5000:
		wm.random_tick_block(crop)
		ticks_dry += 1
	_check(wm.get_block_world(crop) == B.WHEAT_CROPS, "Wheat ripens through random ticks")
	wm.set_block_world(soil + Vector3i(2, 0, 0), B.WATER)
	_check(wm.is_farmland_hydrated(soil), "Water within 4 blocks hydrates farmland")
	# Average over several plantings: watered farmland should ripen in far fewer ticks.
	var total_wet: int = 0
	var total_dry: int = ticks_dry
	for i in range(6):
		wm.set_block_world(crop, B.WHEAT_SPROUT)
		var t: int = 0
		while wm.get_block_world(crop) == B.WHEAT_SPROUT and t < 5000:
			wm.random_tick_block(crop)
			t += 1
		total_wet += t
	print("  (dry: %d ticks once, watered: %.1f ticks on average; 7 stages)" % [total_dry, total_wet / 6.0])
	_check(total_wet / 6.0 > 7.0 * 3.0 and total_wet / 6.0 < 7.0 * 14.0, "Watered wheat needs about 7 x 7 random ticks")
	wm.set_block_world(soil + Vector3i(2, 0, 0), B.GRASS)
	wm.set_block_world(crop, B.AIR)


func _test_glass_and_recipes() -> void:
	print("[10] Glass and recipes")
	_check(InventoryManager._get_smelt_result(B.SAND) == B.GLASS, "Sand smelts into glass")
	_check(BlockRegistry.render_type_table[B.GLASS] == BlockRegistry.RenderType.CUBE_CUTOUT and not BlockRegistry.is_occluder(B.GLASS), "Glass is see-through")
	_check(VoxelLighting.get_block_opacity(B.GLASS) == 0, "Light passes through glass")
	_check(InventoryManager.get_dropped_item_for_block(B.GLASS, I.DIAMOND_PICKAXE) == 0, "Broken glass drops nothing")
	var inv := InventoryManager.new()
	inv.set_crafting_grid_dimension(3)
	for r in range(3):
		for c in range(2):
			inv.craft_grid[r * 3 + c] = {"id": B.WOOD_PLANKS, "count": 1}
	var out: Dictionary = inv._match_crafting_grid()
	_check(int(out.get("id", 0)) == B.DOOR_CLOSED and int(out.get("count", 0)) == 3, "Six planks craft 3 doors")
	inv.free()
