extends SceneTree

func _init() -> void:
	print("--- Running VoxelCraft Audio Integration Tests ---")

	var retro_sfx_script = load("res://scripts/audio/retro_sfx_player.gd")
	if retro_sfx_script == null:
		push_error("FAIL: Failed to load retro_sfx_player.gd")
		quit(1)
		return

	var sfx_player = retro_sfx_script.new()
	root.add_child(sfx_player)

	# 1. Verify sound groups mapping
	var groups: Dictionary = sfx_player._sound_groups
	print("Testing %d sound groups..." % groups.size())

	var missing_files: Array[String] = []
	var total_checked := 0

	for g_name in groups:
		var files: Array = groups[g_name]
		if files.is_empty():
			push_error("Group '%s' is empty!" % g_name)
		for f in files:
			total_checked += 1
			var path := "res://assets/audio/sounds/" + str(f)
			if not FileAccess.file_exists(path):
				missing_files.append(path)

	if not missing_files.is_empty():
		push_error("FAIL: Missing %d audio files in groups: %s" % [missing_files.size(), str(missing_files)])
		quit(1)
		return

	print("PASS: Verified %d audio file mappings across %d sound groups." % [total_checked, groups.size()])

	# 2. Test stream loading and caching
	var test_stream = sfx_player._get_random_stream("eat")
	if test_stream == null:
		push_error("FAIL: Failed to load stream for 'eat'")
		quit(1)
		return
	print("PASS: Successfully loaded audio stream: %s" % test_stream.resource_path)

	# 3. Test 2D playback
	for g in ["jump", "eat", "slot_tick", "item_pickup", "step_grass", "step_dirt", "step_stone", "step_wood", "step_sand"]:
		sfx_player.play_sfx(g, -6.0)

	# 4. Test 3D spatial playback
	for g in ["zombie_ambient", "zombie_hurt", "skeleton_ambient", "cow_ambient", "pig_ambient", "creeper_fuse", "creeper_explode", "explosion", "dig_stone", "break_stone"]:
		sfx_player.play_sfx_at_pos(g, Vector3(5, 10, 5), 0.0)

	print("PASS: 2D and 3D player pools triggered without error.")

	# 5. Clean up
	sfx_player.queue_free()
	print("--- All Audio Integration Tests Passed Successfully! ---")
	quit(0)
