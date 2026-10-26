extends SceneTree

func _init() -> void:
	print("--- Running Doors, Beds, & Music System Verification ---")

	# 1. Test MusicManager Autoload
	print("[1/3] Testing MusicManager Autoload & Audio Tracks...")
	var music_mgr: Node = root.get_node_or_null("MusicManager")
	if music_mgr == null:
		var music_script = load("res://scripts/audio/music_manager.gd")
		assert(music_script != null, "music_manager.gd must load")
		music_mgr = music_script.new()
		root.add_child(music_mgr)
	assert(music_mgr != null, "MusicManager must exist")
	assert(music_mgr.has_method("play_random_track"), "MusicManager must have play_random_track")
	assert(music_mgr.has_method("set_music_volume"), "MusicManager must have set_music_volume")
	assert(music_mgr.has_method("set_music_enabled"), "MusicManager must have set_music_enabled")
	
	music_mgr.set_music_volume(0.75)
	assert(absf(music_mgr.get_music_volume() - 0.75) < 0.01, "Music volume should update to 0.75")
	
	var tracks: Array = music_mgr.get("_tracks")
	assert(tracks.size() >= 3, "MusicManager should have registered ambient tracks (found %d)" % tracks.size())
	print("PASS: MusicManager loaded %d tracks successfully." % tracks.size())

	music_mgr.play_random_track(0.1)
	print("PASS: MusicManager play_random_track triggered cleanly.")

	# 2. Test BlockRegistry Properties for Doors & Beds
	print("[2/3] Testing BlockRegistry Door and Bed classifications...")
	assert(not BlockRegistry.is_passable_block(BlockRegistry.BlockId.DOOR_OPEN), "DOOR_OPEN must NOT be marked passable (so it generates collision for interaction)")
	assert(not BlockRegistry.is_opaque_full_cube(BlockRegistry.BlockId.BED), "BED must be non-opaque custom box")
	assert(not BlockRegistry.is_opaque_full_cube(BlockRegistry.BlockId.BED_HEAD), "BED_HEAD must be non-opaque custom box")
	assert(BlockRegistry.get_block_hardness(BlockRegistry.BlockId.BED) > 0.0, "BED must have valid hardness")
	assert(BlockRegistry.get_block_hardness(BlockRegistry.BlockId.BED_HEAD) > 0.0, "BED_HEAD must have valid hardness")
	assert(BlockRegistry.get_block_name(BlockRegistry.BlockId.BED_HEAD) == "Bed", "BED_HEAD name must be Bed")
	print("PASS: BlockRegistry definitions verified.")

	# 3. Test Gameplay Interaction with Main Scene
	print("[3/3] Testing 2-Block Bed and Door Interaction Mechanics in Main Scene...")
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	assert(main_scene != null, "main.tscn must load")
	var main_inst: Node = main_scene.instantiate()
	root.add_child(main_inst)

	var world_mgr: WorldManager = root.find_child("WorldManager", true, false) as WorldManager
	assert(world_mgr != null, "WorldManager must exist")
	var player = root.find_child("Player", true, false) as PlayerController
	assert(player != null, "Player must exist")
	player._world_manager = world_mgr
	var interactor: BlockInteractor = player.find_child("BlockInteractor", true, false) as BlockInteractor
	assert(interactor != null, "BlockInteractor must exist")
	interactor._world_manager = world_mgr
	interactor._player_body = player

	# Ensure chunk (0, 0) exists in world_mgr
	if not world_mgr._active_chunks.has(Vector2i(0, 0)):
		var chunk = VoxelChunk.new()
		chunk.chunk_coords = Vector2i(0, 0)
		chunk.name = "Chunk_0_0"
		world_mgr.add_child(chunk)
		world_mgr._active_chunks[Vector2i(0, 0)] = chunk

	# Test Door toggle logic directly at loaded chunk coordinates (0, 64, 0)
	var test_door_pos := Vector3i(0, 64, 0)
	var test_door_top := Vector3i(0, 65, 0)
	world_mgr.set_block_world(test_door_pos, BlockRegistry.BlockId.DOOR_CLOSED)
	world_mgr.set_block_world(test_door_top, BlockRegistry.BlockId.DOOR_CLOSED)

	interactor.target_block_pos = test_door_pos
	interactor.has_target = true
	# Simulate right-click toggle
	interactor._try_interact_or_place_block()
	assert(world_mgr.get_block_world(test_door_pos) == BlockRegistry.BlockId.DOOR_OPEN, "Door should open")
	assert(world_mgr.get_block_world(test_door_top) == BlockRegistry.BlockId.DOOR_OPEN, "Partner door top should open")
	print("PASS: Right-clicking closed door opened both top and bottom door blocks.")

	# Right click again to close
	interactor._try_interact_or_place_block()
	assert(world_mgr.get_block_world(test_door_pos) == BlockRegistry.BlockId.DOOR_CLOSED, "Door should close")
	assert(world_mgr.get_block_world(test_door_top) == BlockRegistry.BlockId.DOOR_CLOSED, "Partner door top should close")
	print("PASS: Right-clicking open door closed both top and bottom door blocks.")

	# Test 2-Block Bed Placement
	var bed_foot_pos := Vector3i(2, 64, 0)
	var bed_head_pos := Vector3i(2, 64, 1)
	interactor.place_block_pos = bed_foot_pos
	interactor.has_target = true
	interactor.selected_slot = 0
	# Set slot 0 to Bed item
	var inv: InventoryManager = root.find_child("InventoryManager", true, false) as InventoryManager
	if inv == null:
		inv = root.get_node_or_null("/root/Main/InventoryManager")
	if inv != null:
		interactor._inventory = inv
		inv.add_item(BlockRegistry.BlockId.BED, 5)

	# Simulate bed break partner cleanup
	world_mgr.set_block_world(bed_foot_pos, BlockRegistry.BlockId.BED)
	world_mgr.set_block_world(bed_head_pos, BlockRegistry.BlockId.BED_HEAD)
	assert(world_mgr.get_block_world(bed_foot_pos) == BlockRegistry.BlockId.BED, "Bed foot should be present")
	assert(world_mgr.get_block_world(bed_head_pos) == BlockRegistry.BlockId.BED_HEAD, "Bed head should be present")

	# Test breaking bed foot cleans up bed head
	interactor.target_block_pos = bed_foot_pos
	interactor._complete_break_block()
	assert(world_mgr.get_block_world(bed_foot_pos) == BlockRegistry.BlockId.AIR, "Broken bed foot should become AIR")
	assert(world_mgr.get_block_world(bed_head_pos) == BlockRegistry.BlockId.AIR, "Partner bed head should automatically be cleared to AIR")
	print("PASS: Breaking Bed foot cleanly removed partner Bed head.")

	# Test Sleeping and Respawning at Bed on Death
	# 1. Place a bed inside a clear 3x3 room with stone floor at y=63
	for rx in range(4):
		for rz in range(4):
			world_mgr.set_block_world(Vector3i(3 + rx, 63, 3 + rz), BlockRegistry.BlockId.STONE)
			world_mgr.set_block_world(Vector3i(3 + rx, 64, 3 + rz), BlockRegistry.BlockId.AIR)
			world_mgr.set_block_world(Vector3i(3 + rx, 65, 3 + rz), BlockRegistry.BlockId.AIR)
			world_mgr.set_block_world(Vector3i(3 + rx, 66, 3 + rz), BlockRegistry.BlockId.AIR)
	var new_bed_pos := Vector3i(4, 64, 4)
	var new_bed_head := Vector3i(4, 64, 5)
	world_mgr.set_block_world(new_bed_pos, BlockRegistry.BlockId.BED)
	world_mgr.set_block_world(new_bed_head, BlockRegistry.BlockId.BED_HEAD)

	# Set night time
	var dn: DayNightCycle = root.find_child("DayNightCycle", true, false) as DayNightCycle
	if dn != null:
		dn.current_hour = 22.0 # 10:00 PM Night
		assert(dn.is_night_time(), "Must be night time at 22:00")

	# Right-click bed to sleep and set respawn
	interactor.target_block_pos = new_bed_pos
	interactor.has_target = true
	interactor._player_body = player
	player.current_health = 10
	player.current_hunger = 10
	interactor._try_interact_or_place_block()

	assert(player.has_custom_respawn, "Player must have custom respawn enabled after clicking bed")
	assert(player.custom_respawn_pos == Vector3(new_bed_pos), "Bed respawn position must match clicked bed")
	if dn != null:
		assert(dn.current_hour == 6.0, "Time must advance to 06:00 AM Sunrise after sleeping")
		assert(not dn.is_night_time(), "Morning at 06:00 is daytime")
	assert(player.current_health == player.max_health, "Sleeping must restore full health")
	print("PASS: Sleeping at night advanced time to Sunrise, restored health, and saved bed respawn.")

	var check_result: Dictionary = player._find_safe_bed_spawn_position(new_bed_pos)
	assert(check_result["valid"], "Bed check must be valid")

	# Kill player and verify respawn at bed
	player.take_damage(100)
	assert(player.has_custom_respawn, "Player should still have bed respawn active")
	var dist_to_bed: float = player.position.distance_to(Vector3(new_bed_pos) + Vector3(0.5, 0.0, 0.5))
	assert(dist_to_bed < 3.0, "Player must respawn adjacent to or at their bed (dist: %.2f)" % dist_to_bed)
	print("PASS: Player successfully respawned at bed after death!")

	# Break the bed and verify fallback to world spawn
	interactor.target_block_pos = new_bed_pos
	interactor._complete_break_block()
	assert(not player.has_custom_respawn, "Breaking player's bed must invalidate custom respawn")
	player.take_damage(100)
	assert(not player.has_custom_respawn, "Player must now respawn at world spawn")
	print("PASS: Invalidation on bed destruction and fallback to world spawn verified.")

	# Test Door break partner cleanup
	interactor.target_block_pos = test_door_pos
	interactor._complete_break_block()
	assert(world_mgr.get_block_world(test_door_pos) == BlockRegistry.BlockId.AIR, "Broken door bottom should become AIR")
	assert(world_mgr.get_block_world(test_door_top) == BlockRegistry.BlockId.AIR, "Partner door top should automatically be cleared to AIR")
	print("PASS: Breaking Door bottom cleanly removed partner Door top.")

	# Clean up
	main_inst.queue_free()
	print("--- All Doors, Beds, & Music Tests Passed Successfully! ---")
	quit(0)
