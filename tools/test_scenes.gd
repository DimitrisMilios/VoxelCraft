extends SceneTree

func _init() -> void:
	print("--- Testing Scene Instantiation and Execution ---")
	
	# Test Main Menu scene
	print("Loading main_menu.tscn...")
	var menu_scene: PackedScene = load("res://scenes/ui/main_menu.tscn")
	assert(menu_scene != null, "main_menu.tscn must load")
	var menu_inst = menu_scene.instantiate()
	root.add_child(menu_inst)
	print("main_menu.tscn instantiated successfully.")
	menu_inst.queue_free()
	
	# Test Main Game scene
	print("Loading main.tscn...")
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	assert(main_scene != null, "main.tscn must load")
	var main_inst = main_scene.instantiate()
	root.add_child(main_inst)
	print("main.tscn instantiated successfully.")
	
	# Simulate 10 frames
	print("Simulating 10 physics/process frames...")
	# Let SceneTree run for a moment
	await create_timer(0.5).timeout
	print("Scene simulation complete!")
	
	main_inst.queue_free()
	print("--- All Scene Tests Passed! ---")
	quit(0)
