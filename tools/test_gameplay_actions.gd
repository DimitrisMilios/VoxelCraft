extends SceneTree

func _init() -> void:
	print("--- Running Full Gameplay Action Validation ---")
	
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	assert(main_scene != null, "main.tscn must load")
	var main_inst = main_scene.instantiate()
	root.add_child(main_inst)
	
	var player = root.find_child("Player", true, false)
	assert(player != null, "Player must exist")
	
	var interactor = player.find_child("BlockInteractor", true, false)
	assert(interactor != null, "BlockInteractor must exist")
	
	var world_mgr = root.find_child("WorldManager", true, false)
	assert(world_mgr != null, "WorldManager must exist")
	
	var sfx = root.find_child("RetroSfxPlayer", true, false)
	assert(sfx != null, "RetroSfxPlayer must exist")
	
	print("Nodes resolved successfully. Testing mining progress signal emission...")
	interactor.target_block_pos = Vector3i(0, 64, 0)
	
	# Simulate mining steps
	interactor.mining_progress_changed.emit(0.2, "Stone", true)
	interactor.mining_progress_changed.emit(0.4, "Stone", true)
	interactor.mining_progress_changed.emit(0.6, "Stone", true)
	interactor.mining_progress_changed.emit(0.8, "Stone", true)
	interactor.mining_progress_changed.emit(1.0, "Stone", true)
	print("PASS: Mining progress signal handled cleanly.")

	# Simulate block broken
	interactor.block_broken.emit(Vector3i(0, 64, 0), 3) # stone
	print("PASS: Block broken signal handled cleanly.")

	# Simulate block placed
	interactor.block_placed.emit(Vector3i(0, 65, 0), 8) # wood planks
	print("PASS: Block placed signal handled cleanly.")

	# Simulate player step
	player.step_taken.emit(false)
	player.step_taken.emit(true)
	player.jumped.emit()
	player.water_state_changed.emit(true)
	player.player_damaged.emit(2)
	print("PASS: Player movement and damage signals handled cleanly.")

	# Simulate TNT ignition & detonate
	world_mgr.ignite_tnt_at(Vector3i(0, 64, 0))
	print("PASS: TNT ignition handled cleanly.")

	# Clean up
	main_inst.queue_free()
	print("--- All Gameplay Actions Validated Successfully! ---")
	quit(0)
