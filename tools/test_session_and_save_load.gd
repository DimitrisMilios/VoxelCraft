extends SceneTree

const GameSession = preload("res://scripts/core/game_session.gd")
const ChunkStorage = preload("res://scripts/world/chunk_storage.gd")

func _init() -> void:
	print("[TestSession] Starting World Save/Load and Session validation...")
	var world_id_1: String = GameSession.create_world("Test Exploration", "987654")
	assert(not world_id_1.is_empty(), "World ID 1 should not be empty")
	assert(GameSession.active_seed == 987654, "Active seed should match specified seed")
	assert(GameSession.active_world_name == "Test Exploration", "World name should match")
	print("[TestSession] PASS: World 1 created successfully with ID: " + world_id_1)

	# 2. Create another World with random seed (empty string)
	var world_id_2: String = GameSession.create_world("Random Survival", "")
	assert(not world_id_2.is_empty(), "World ID 2 should not be empty")
	assert(GameSession.active_seed > 0, "Random seed should be positive")
	assert(GameSession.active_seed != 987654, "Random seed should be different from World 1")
	print("[TestSession] PASS: World 2 created with random seed: " + str(GameSession.active_seed))

	# 3. List worlds
	var world_list: Array[Dictionary] = GameSession.list_saved_worlds()
	assert(world_list.size() >= 2, "Should list at least 2 saved worlds")
	var found_1: bool = false
	var found_2: bool = false
	for w in world_list:
		if str(w.get("id")) == world_id_1:
			found_1 = true
		if str(w.get("id")) == world_id_2:
			found_2 = true
	assert(found_1 and found_2, "Both created worlds must be listed")
	print("[TestSession] PASS: Both worlds listed in saved worlds.")

	# 4. Select World 1
	var selected: bool = GameSession.select_world(world_id_1)
	assert(selected, "Selecting World 1 should succeed")
	assert(GameSession.active_seed == 987654, "Active seed after selection should be 987654")
	assert(GameSession.active_world_id == world_id_1, "Active world ID should match")
	print("[TestSession] PASS: World 1 selected and loaded.")

	# 5. Chunk Storage persistence in World 1
	var chunk_dir: String = GameSession.get_active_chunk_dir()
	var storage := ChunkStorage.new(chunk_dir)
	var dummy_voxels := PackedByteArray()
	dummy_voxels.resize(16 * 256 * 16)
	dummy_voxels[0] = 3 # Stone
	dummy_voxels[100] = 7 # Diamond ore
	var saved: bool = storage.save_chunk_to_disk(Vector2i(5, -2), dummy_voxels, 64)
	assert(saved, "Saving chunk to custom world dir should succeed")
	assert(storage.has_saved_chunk(Vector2i(5, -2)), "Storage should confirm chunk exists")

	var loaded_chunk: Dictionary = storage.load_chunk_data(Vector2i(5, -2))
	assert(not loaded_chunk.is_empty(), "Loaded chunk data should not be empty")
	var loaded_bytes: PackedByteArray = loaded_chunk["voxels"]
	assert(loaded_bytes[0] == 3 and loaded_bytes[100] == 7, "Chunk voxel contents must match exactly")
	assert(int(loaded_chunk["highest_y"]) == 64, "Highest Y must match")
	print("[TestSession] PASS: Chunk compressed persistence in world directory verified.")

	# 6. Simulate level.json update with bed respawn coordinates
	var level_path: String = GameSession.get_active_world_dir() + "/level.json"
	var current_data: Dictionary = GameSession.active_world_data.duplicate(true)
	current_data["player"] = {
		"has_saved_pos": true,
		"pos": [12.5, 68.0, -45.2],
		"yaw": 1.57,
		"pitch": -0.2,
		"health": 18,
		"hunger": 16,
		"oxygen": 10,
		"is_flying": false,
		"has_bed": true,
		"bed_pos": [10.0, 67.0, -42.0],
	}
	current_data["inventory"] = {
		"slots": [{"id": 204, "count": 1}], # Diamond Pickaxe
	}
	current_data["day_night"] = {
		"hour": 14.5,
		"day": 3,
	}
	var f := FileAccess.open(level_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(current_data, "\t"))
	f.close()

	# Re-select and verify updated level data
	GameSession.select_world(world_id_1)
	var loaded_p: Dictionary = GameSession.active_world_data.get("player", {})
	assert(bool(loaded_p.get("has_bed")) == true, "Player has_bed must be true")
	var bed_arr: Array = loaded_p.get("bed_pos", [])
	assert(bed_arr.size() == 3 and bed_arr[0] == 10.0 and bed_arr[1] == 67.0, "Bed position matches")
	assert(int(loaded_p.get("health")) == 18, "Player health matches")

	var loaded_inv: Dictionary = GameSession.active_world_data.get("inventory", {})
	var inv_slots: Array = loaded_inv.get("slots", [])
	assert(inv_slots.size() > 0 and int(inv_slots[0].get("id")) == 204, "Diamond pickaxe persisted in inventory")

	var loaded_dn: Dictionary = GameSession.active_world_data.get("day_night", {})
	assert(is_equal_approx(float(loaded_dn.get("hour")), 14.5), "Day/night hour matches")
	assert(int(loaded_dn.get("day")) == 3, "Day 3 persisted")
	print("[TestSession] PASS: Player state, bed respawn, inventory, and day/night cycle persistence verified.")

	# 7. Clean up test worlds
	GameSession.delete_world(world_id_1)
	GameSession.delete_world(world_id_2)
	assert(not GameSession.select_world(world_id_1), "Deleted world 1 cannot be selected")
	assert(not GameSession.select_world(world_id_2), "Deleted world 2 cannot be selected")
	print("[TestSession] PASS: Test worlds deleted and cleaned up successfully.")

	print("[TestSession] ALL SESSION AND SAVE/LOAD TESTS PASSED!")
	quit(0)
