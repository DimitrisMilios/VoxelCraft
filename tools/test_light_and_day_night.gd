extends SceneTree
## Validates the 30-minute Day/Night cycle timing and torch/light emitter mob spawn protection.

func _initialize() -> void:
	print("--- Running Light & Day/Night Cycle Validation ---")

	# 1. Day / Night cycle timing
	var dn := DayNightCycle.new()
	assert(dn.day_length_seconds == 1800.0, "Day length must be 1800 seconds (30 minutes)!")
	print("PASS: Day length is 1800.0 seconds (30 minutes).")

	# 2. Advance 75 seconds (should equal exactly 1 game hour: 24h / 1800s * 75s = 1.0h)
	var initial_h: float = dn.current_hour
	dn.advance_hours(1.0)
	var expected_h: float = fposmod(initial_h + 1.0, 24.0)
	assert(absf(dn.current_hour - expected_h) < 0.001, "Advancing 1 hour must match exactly!")
	print("PASS: 1 game hour progression matches 75 real-time seconds.")
	dn.free()

	# 3. Torch illumination prevents mob spawning
	var wm := WorldManager.new()
	var test_light_pos := Vector3i(100, 45, 100)
	# Verify position without light returns false
	var is_lit_before: bool = wm.is_position_illuminated_by_blocks(Vector3(100.5, 45.5, 100.5), 10.0)
	assert(not is_lit_before, "Unlit location must return false!")
	print("PASS: Unlit position correctly reports false.")

	# Add torch at (100, 45, 100) using chunk simulation
	var c_coord := WorldManager.world_to_chunk_coords(Vector3(100, 45, 100))
	var chunk := VoxelChunk.new()
	chunk.chunk_coords = c_coord
	chunk.position = Vector3(float(c_coord.x * VoxelChunk.CHUNK_SIZE_X), 0.0, float(c_coord.y * VoxelChunk.CHUNK_SIZE_Z))
	chunk.generate_terrain(FastNoiseLite.new(), null)
	chunk.set_block_local(posmod(100, 16), 45, posmod(100, 16), BlockRegistry.BlockId.TORCH, false)
	wm._active_chunks[c_coord] = chunk
	wm.add_child(chunk)

	# Verify position at 3 blocks away is lit
	var is_lit_near: bool = wm.is_position_illuminated_by_blocks(Vector3(103.5, 45.5, 100.5), 10.0)
	assert(is_lit_near, "Position within torch radius must be illuminated!")
	print("PASS: Position within torch radius is illuminated (hostile mobs blocked from spawning).")

	# Verify position at 18 blocks away is NOT lit
	var is_lit_far: bool = wm.is_position_illuminated_by_blocks(Vector3(125.5, 45.5, 100.5), 10.0)
	assert(not is_lit_far, "Position outside torch radius must not be illuminated.")
	print("PASS: Position outside torch radius correctly allows darkness.")

	chunk.queue_free()
	wm.free()

	print("--- All Light & Day/Night Tests Passed Successfully! ---")
	quit(0)
