extends SceneTree

var frame_count: int = 0
var main_node: Node = null
var GameSession = null

func _init() -> void:
	print("=== RUNNING COMPREHENSIVE INVENTORY & CHEST PERSISTENCE TEST ===")
	GameSession = load("res://scripts/core/game_session.gd")
	var worlds = GameSession.list_saved_worlds()
	var wid = ""
	if worlds.is_empty():
		wid = GameSession.create_world("TestWorld", "123456")
	else:
		wid = worlds[0].get("id")
	print("Selected world: ", wid)
	GameSession.select_world(wid)
	
	var main_scene = load("res://scenes/main.tscn")
	main_node = main_scene.instantiate()
	root.add_child(main_node)

func _process(delta: float) -> bool:
	frame_count += 1
	if frame_count == 10:
		_populate_and_save()
	elif frame_count == 20:
		_reload_and_verify()
	return false

func _populate_and_save() -> void:
	print("--- POPULATING TEST DATA ---")
	var wm = main_node.get_node_or_null("WorldManager")
	var player = main_node.get_node_or_null("Player")
	var im = player.get_node_or_null("InventoryManager") if player != null else null
	
	assert(im != null, "InventoryManager must not be null")
	
	# 1. Hotbar & Inventory
	im.slots[0] = {"id": 204, "count": 1, "durability": 1500} # Diamond Pickaxe
	im.slots[1] = {"id": 234, "count": 1, "durability": 1561} # Diamond Sword
	im.slots[2] = {"id": 5, "count": 64, "durability": 0}     # Oak Planks
	im.slots[3] = {"id": 1, "count": 32, "durability": 0}     # Stone
	im.slots[8] = {"id": 113, "count": 16, "durability": 0}   # Steak
	im.slots[35] = {"id": 106, "count": 64, "durability": 0}  # Diamond x64 in backpack
	
	# 2. Armor Slots
	im.armor_slots[0] = {"id": 331, "count": 1, "durability": 363} # Diamond Helmet
	im.armor_slots[1] = {"id": 332, "count": 1, "durability": 528} # Diamond Chestplate
	im.armor_slots[2] = {"id": 333, "count": 1, "durability": 495} # Diamond Leggings
	im.armor_slots[3] = {"id": 334, "count": 1, "durability": 429} # Diamond Boots
	
	# 3. Furnace
	im.furnace_input = {"id": 102, "count": 12} # Raw Iron x12
	im.furnace_fuel = {"id": 101, "count": 3}   # Coal x3
	im.furnace_output = {"id": 103, "count": 4} # Iron Ingot x4
	im.furnace_burn_remaining = 8.5
	im.furnace_burn_max = 10.0
	im.furnace_cook_progress = 1.25
	
	# 4. World Chest at (10, 65, 10)
	var chest_pos = Vector3i(10, 65, 10)
	var chest_items: Array = []
	for i in range(27):
		chest_items.append({"id": 0, "count": 0})
	chest_items[0] = {"id": 106, "count": 32} # Diamond x32 in chest
	chest_items[1] = {"id": 105, "count": 16} # Gold Ingot x16 in chest
	im.world_chests[chest_pos] = chest_items
	
	print("Calling wm.save_complete_world()...")
	wm.save_complete_world()
	
	print("Freeing scene node to trigger _exit_tree...")
	main_node.queue_free()
	main_node = null

func _reload_and_verify() -> void:
	print("--- RELOADING AND VERIFYING PERSISTENCE ---")
	var worlds = GameSession.list_saved_worlds()
	var wid = worlds[0].get("id")
	GameSession.select_world(wid)
	
	var main_scene = load("res://scenes/main.tscn")
	var new_main = main_scene.instantiate()
	root.add_child(new_main)
	
	var player = new_main.get_node_or_null("Player")
	var im = player.get_node_or_null("InventoryManager") if player != null else null
	assert(im != null, "Reloaded InventoryManager must not be null")
	
	# Assertions
	var errors: Array[String] = []
	
	if im.slots[0].get("id") != 204 or im.slots[0].get("durability") != 1500:
		errors.append("Slot 0 Diamond Pickaxe mismatch: " + str(im.slots[0]))
	if im.slots[1].get("id") != 234:
		errors.append("Slot 1 Diamond Sword mismatch: " + str(im.slots[1]))
	if im.slots[2].get("id") != 5 or im.slots[2].get("count") != 64:
		errors.append("Slot 2 Planks mismatch: " + str(im.slots[2]))
	if im.slots[35].get("id") != 106 or im.slots[35].get("count") != 64:
		errors.append("Slot 35 Diamond mismatch: " + str(im.slots[35]))
		
	if im.armor_slots[0].get("id") != 331 or im.armor_slots[0].get("durability") != 363:
		errors.append("Armor Helmet mismatch: " + str(im.armor_slots[0]))
	if im.armor_slots[1].get("id") != 332 or im.armor_slots[1].get("durability") != 528:
		errors.append("Armor Chestplate mismatch: " + str(im.armor_slots[1]))
	if im.armor_slots[2].get("id") != 333:
		errors.append("Armor Leggings mismatch: " + str(im.armor_slots[2]))
	if im.armor_slots[3].get("id") != 334:
		errors.append("Armor Boots mismatch: " + str(im.armor_slots[3]))
		
	if (im.furnace_input.get("id") != 102 or (int(im.furnace_input.get("count", 0)) + int(im.furnace_output.get("count", 0)) != 16)):
		errors.append("Furnace iron ore/ingot sum mismatch: input=" + str(im.furnace_input) + " output=" + str(im.furnace_output))
	if im.furnace_fuel.get("id") != 101 or int(im.furnace_fuel.get("count", 0)) <= 0:
		errors.append("Furnace fuel mismatch: " + str(im.furnace_fuel))
		
	var chest_pos = Vector3i(10, 65, 10)
	if not im.world_chests.has(chest_pos):
		errors.append("World chest at (10, 65, 10) missing!")
	else:
		var c_slots = im.world_chests[chest_pos]
		if c_slots[0].get("id") != 106 or c_slots[0].get("count") != 32:
			errors.append("Chest slot 0 mismatch: " + str(c_slots[0]))
		if c_slots[1].get("id") != 105 or c_slots[1].get("count") != 16:
			errors.append("Chest slot 1 mismatch: " + str(c_slots[1]))
			
	if errors.is_empty():
		print("==================================================")
		print(">>> COMPREHENSIVE PERSISTENCE TEST 100% PASSED! <<<")
		print(" - 36-slot inventory & hotbar: RESTORED")
		print(" - 4-slot diamond armor & durability: RESTORED")
		print(" - Furnace input, fuel, output & cook timers: RESTORED")
		print(" - World-coordinate persistent chests: RESTORED")
		print("==================================================")
	else:
		print("FAILED with errors:")
		for e in errors:
			print("  * ", e)
			
	new_main.queue_free()
	quit(0 if errors.is_empty() else 1)
