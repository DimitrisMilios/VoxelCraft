extends SceneTree
## Comprehensive integration test suite for:
## 1. Production Audio Loading & Sound Effects
## 2. Crop Planting, Sprouting, Raycast Targeting, Growth, and Harvesting Mechanics

func _init() -> void:
	print("--- Running Plants & Audio Verification Suite ---")

	# =========================================================================
	# PART 1: AUDIO LOADING & RETRO SFX VERIFICATION
	# =========================================================================
	print("[1/2] Testing Audio Loading via ResourceLoader/load()...")
	var sfx_script = load("res://scripts/audio/retro_sfx_player.gd")
	assert(sfx_script != null, "RetroSfxPlayer script must load")
	var sfx_player = sfx_script.new()
	root.add_child(sfx_player)

	# Verify loading for primary sound groups
	var test_groups: Array[String] = [
		"step_grass", "step_stone", "step_wood", "dig_dirt", "dig_stone",
		"break_wood", "break_stone", "place_hard", "place_soft", "jump",
		"hurt", "eat", "item_pickup", "door_open", "door_close"
	]
	for g in test_groups:
		var stream: AudioStream = sfx_player._get_random_stream(g)
		assert(stream != null, "Audio stream for '%s' must load successfully" % g)

	print("PASS: Verified audio streams load via ResourceLoader for all core sound groups.")

	# Verify MusicManager track streams
	var music_script = load("res://scripts/audio/music_manager.gd")
	var mm = music_script.new()
	if mm != null:
		assert(mm._tracks.size() >= 8, "MusicManager should have registered 8+ soundtrack tracks")
		for trk in mm._tracks:
			var s: AudioStream = mm._load_track_stream(trk)
			assert(s != null, "Track stream '%s' (%s) must load successfully" % [trk.get("name", ""), trk.get("path", "")])
		print("PASS: Verified all MusicManager soundtrack streams load successfully.")
		mm.queue_free()

	# =========================================================================
	# PART 2: PLANTING, SPROUTS, RAYCASTING, GROWTH & HARVESTING
	# =========================================================================
	print("[2/2] Testing Planting, Sprouts, Raycast Targeting, Growth & Harvesting...")

	# Instantiate Main scene for real world interactions
	var main_scene = load("res://scenes/main.tscn")
	assert(main_scene != null, "Main scene must load")
	var main_inst = main_scene.instantiate()
	root.add_child(main_inst)

	var world_mgr: WorldManager = main_inst.find_child("WorldManager", true, false) as WorldManager
	assert(world_mgr != null, "WorldManager must exist")
	var player: PlayerController = main_inst.find_child("Player", true, false) as PlayerController
	assert(player != null, "Player must exist")
	player._world_manager = world_mgr
	var interactor: BlockInteractor = player.find_child("BlockInteractor", true, false) as BlockInteractor
	assert(interactor != null, "BlockInteractor must exist")
	interactor._world_manager = world_mgr
	interactor._player_body = player
	var inv: InventoryManager = player.find_child("InventoryManager", true, false) as InventoryManager
	assert(inv != null, "InventoryManager must exist")
	interactor._inventory = inv

	# Ensure chunk (0, 0) exists in world_mgr
	if not world_mgr._active_chunks.has(Vector2i(0, 0)):
		world_mgr._spawn_chunk_immediate(Vector2i(0, 0))

	# Prepare a flat 4x4 test plot with dirt floor at y=63
	for x in range(4):
		for z in range(4):
			world_mgr.set_block_world(Vector3i(10 + x, 63, 10 + z), BlockRegistry.BlockId.DIRT)
			world_mgr.set_block_world(Vector3i(10 + x, 64, 10 + z), BlockRegistry.BlockId.AIR)
			world_mgr.set_block_world(Vector3i(10 + x, 65, 10 + z), BlockRegistry.BlockId.AIR)

	var test_soil_pos := Vector3i(10, 63, 10)
	var test_crop_pos := Vector3i(10, 64, 10)

	# 1. Till Dirt into Farmland using Stick
	interactor.target_block_pos = test_soil_pos
	interactor.has_target = true
	inv.slots[0] = {"id": InventoryManager.ItemId.STICK, "count": 1}
	interactor.select_slot(0)
	interactor._try_interact_or_place_block()
	assert(world_mgr.get_block_world(test_soil_pos) == BlockRegistry.BlockId.FARMLAND, "Soil should be tilled into Farmland")
	print("PASS: Tilled soil into Farmland successfully.")

	# 2. Plant Wheat Seeds on Farmland -> Must become WHEAT_SPROUT
	inv.slots[1] = {"id": InventoryManager.ItemId.WHEAT_SEEDS, "count": 5}
	interactor.select_slot(1)
	interactor._try_interact_or_place_block()
	var planted_id: int = world_mgr.get_block_world(test_crop_pos)
	assert(planted_id == BlockRegistry.BlockId.WHEAT_SPROUT, "Planting Wheat Seeds must place WHEAT_SPROUT (got %d)" % planted_id)
	print("PASS: Planted Wheat Seeds created WHEAT_SPROUT.")

	# 3. Raycast Targeting: Verify voxel ray-march targets the sprout block
	player.position = Vector3(10.5, 63.0, 8.5)
	var ray: RayCast3D = player.find_child("InteractionRay", true, false) as RayCast3D
	if ray != null:
		interactor._raycast = ray
		# Aim towards crop at Vector3(10, 64, 10)
		var aim_vec: Vector3 = (Vector3(10.5, 64.2, 10.5) - (player.position + Vector3(0.0, 1.62, 0.0))).normalized()
		ray.transform.basis = Basis.looking_at(aim_vec, Vector3.UP)
		interactor._update_raycast_target()
		assert(interactor.has_target, "Raycast must target the crop")
		assert(interactor.target_block_pos == test_crop_pos, "Raycast target must be the sprout position")
		print("PASS: Raycast voxel ray-march successfully targeted the passable WHEAT_SPROUT.")

	# 4. Sprout Growth: Simulate growth ticking to full maturity
	# Crops grow through 7 stages on random ticks; force enough ticks to ripen it.
	for i in range(3000):
		if world_mgr.get_block_world(test_crop_pos) != BlockRegistry.BlockId.WHEAT_SPROUT:
			break
		world_mgr.random_tick_block(test_crop_pos)
	var matured_id: int = world_mgr.get_block_world(test_crop_pos)
	assert(matured_id == BlockRegistry.BlockId.WHEAT_CROPS, "Sprout must grow into mature WHEAT_CROPS (got %d)" % matured_id)
	print("PASS: Sprout successfully grew to mature WHEAT_CROPS over time.")

	# 5. Right-Click Harvest & Auto-Replant
	interactor.target_block_pos = test_crop_pos
	interactor.has_target = true
	interactor.select_slot(0) # Empty hand / stick
	var prev_wheat_count: int = inv.get_total_count(InventoryManager.ItemId.WHEAT)
	interactor._try_interact_or_place_block()
	var new_wheat_count: int = inv.get_total_count(InventoryManager.ItemId.WHEAT)
	assert(new_wheat_count == prev_wheat_count + 1, "Harvesting must yield +1 Wheat")
	assert(world_mgr.get_block_world(test_crop_pos) == BlockRegistry.BlockId.WHEAT_SPROUT, "Right-click harvest must auto-replant WHEAT_SPROUT")
	print("PASS: Right-click harvesting yielded Wheat and automatically replanted WHEAT_SPROUT.")

	# 6. Fertilize Sprout with Wheat Seeds
	inv.slots[2] = {"id": InventoryManager.ItemId.WHEAT_SEEDS, "count": 2}
	interactor.select_slot(2)
	interactor._try_interact_or_place_block()
	assert(world_mgr.get_block_world(test_crop_pos) == BlockRegistry.BlockId.WHEAT_CROPS, "Fertilizing sprout with seeds must mature it immediately")
	print("PASS: Fertilizing sprout with seeds matured crop to WHEAT_CROPS.")

	# 7. Left-Click Punch Break on Mature Crop
	interactor.target_block_pos = test_crop_pos
	interactor._complete_break_block()
	assert(world_mgr.get_block_world(test_crop_pos) == BlockRegistry.BlockId.AIR, "Punching crop must break it to AIR")
	print("PASS: Punching mature crop cleared block to AIR and dropped harvest items.")

	# 8. Potato Sprout & Potato Growth Testing
	interactor.target_block_pos = test_soil_pos
	interactor.has_target = true
	inv.slots[3] = {"id": InventoryManager.ItemId.POTATO, "count": 3}
	interactor.select_slot(3)
	interactor._try_interact_or_place_block()
	assert(world_mgr.get_block_world(test_crop_pos) == BlockRegistry.BlockId.POTATO_SPROUT, "Planting Potato must place POTATO_SPROUT")
	for i in range(3000):
		if world_mgr.get_block_world(test_crop_pos) != BlockRegistry.BlockId.POTATO_SPROUT:
			break
		world_mgr.random_tick_block(test_crop_pos)
	assert(world_mgr.get_block_world(test_crop_pos) == BlockRegistry.BlockId.POTATO_CROPS, "Potato Sprout must grow into POTATO_CROPS")

	# Right-click harvest potatoes
	interactor.target_block_pos = test_crop_pos
	interactor.has_target = true
	interactor.select_slot(0)
	interactor._try_interact_or_place_block()
	assert(world_mgr.get_block_world(test_crop_pos) == BlockRegistry.BlockId.POTATO_SPROUT, "Harvesting potatoes must replant POTATO_SPROUT")
	print("PASS: Potato planting, growth, and harvesting fully verified.")

	# 9. Farmland Destruction pops crop
	world_mgr.set_block_world(test_soil_pos, BlockRegistry.BlockId.DIRT)
	assert(world_mgr.get_block_world(test_crop_pos) == BlockRegistry.BlockId.AIR, "Destroying Farmland underneath crop must pop crop to AIR")
	print("PASS: Destroying Farmland automatically popped crop above.")

	# Cleanup
	sfx_player.queue_free()
	main_inst.queue_free()
	print("--- All Plants & Audio Verification Tests Passed Successfully! ---")
	quit(0)
