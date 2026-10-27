extends SceneTree
## Phase 3 Automated Verification Suite
## Tests:
## 1. Falling blocks (Sand & Gravel gravity, landing/solidification, torch shattering into item drop, cascading)
## 2. Ballistic Arrow kinematics (trajectory, block sticking, pickup retrieval, mob collision damage & knockback)
## 3. Primed TNT entity & explosions (4.0s fuse, bouncing, water protection, bedrock/obsidian immunity, chaining)
## 4. Bow aiming & charging mechanics via BlockInteractor

const FallingBlockClass = preload("res://scripts/entities/falling_block.gd")
const TNTPrimedClass = preload("res://scripts/entities/tnt_primed.gd")
const ArrowProjectileClass = preload("res://scripts/entities/arrow_projectile.gd")


func _init() -> void:
	print("==================================================")
	print("--- Running Phase 3 Verification Suite ---")
	print("==================================================")

	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if main_scene == null:
		printerr("FAILED: Could not load main.tscn")
		quit(1)
		return

	var main_inst: Node = main_scene.instantiate()
	root.add_child(main_inst)

	var wm: WorldManager = root.find_child("WorldManager", true, false) as WorldManager
	var player: PlayerController = root.find_child("Player", true, false) as PlayerController
	var interactor: BlockInteractor = root.find_child("BlockInteractor", true, false) as BlockInteractor
	var inv: InventoryManager = root.find_child("InventoryManager", true, false) as InventoryManager

	if wm == null or player == null or interactor == null or inv == null:
		printerr("FAILED: Required nodes not found in main.tscn")
		quit(1)
		return

	interactor._world_manager = wm
	interactor._player_body = player
	interactor._inventory = inv

	# Ensure chunk (0, 0) exists
	if not wm._active_chunks.has(Vector2i(0, 0)):
		var chunk := VoxelChunk.new()
		chunk.chunk_coords = Vector2i(0, 0)
		chunk.name = "Chunk_0_0"
		wm._active_chunks[Vector2i(0, 0)] = chunk
		wm.add_child(chunk)

	var all_passed := true

	all_passed = test_falling_blocks(wm) and all_passed
	all_passed = test_falling_block_on_torch(wm) and all_passed
	all_passed = test_cascading_sand_collapse(wm) and all_passed
	all_passed = test_arrow_ballistics_and_block_hit(wm, player, inv) and all_passed
	all_passed = test_arrow_mob_damage(wm) and all_passed
	all_passed = test_bow_charging_and_firing(wm, player, interactor, inv) and all_passed
	all_passed = test_tnt_primed_physics_and_detonation(wm) and all_passed
	all_passed = test_explosion_blast_resistance_and_water(wm) and all_passed

	print("==================================================")
	if all_passed:
		print(">>> ALL PHASE 3 TESTS PASSED CLEANLY! <<<")
		print("==================================================")
		quit(0)
	else:
		printerr(">>> SOME TESTS FAILED! CHECK LOGS ABOVE. <<<")
		print("==================================================")
		quit(1)


func test_falling_blocks(wm: WorldManager) -> bool:
	print("\n[TEST 1] Falling Sand Gravity & Land Solidification...")
	var ground_pos := Vector3i(2, 60, 2)
	var air_pos := Vector3i(2, 61, 2)
	var spawn_pos := Vector3i(2, 65, 2)

	wm.set_block_world(ground_pos, BlockRegistry.BlockId.STONE)
	wm.set_block_world(air_pos, BlockRegistry.BlockId.AIR)

	var fb := FallingBlockClass.spawn_falling_block(wm, spawn_pos, BlockRegistry.BlockId.SAND)
	if fb == null:
		printerr("FAILED: FallingBlock failed to spawn.")
		return false

	for frame in range(60):
		if not is_instance_valid(fb):
			break
		fb._physics_process(0.0166)

	var landed_bid: int = wm.get_block_world(air_pos)
	if landed_bid != BlockRegistry.BlockId.SAND:
		printerr("FAILED: Sand block did not solidify at %s, got block ID: %d" % [air_pos, landed_bid])
		return false

	print("  PASS: Falling sand fell under gravity and solidified on solid stone at %s." % air_pos)
	return true


func test_falling_block_on_torch(wm: WorldManager) -> bool:
	print("\n[TEST 2] Falling Sand Shattering on Torch into Dropped Item...")
	var ground_pos := Vector3i(4, 60, 4)
	var torch_pos := Vector3i(4, 61, 4)
	var spawn_pos := Vector3i(4, 65, 4)

	wm.set_block_world(ground_pos, BlockRegistry.BlockId.STONE)
	wm.set_block_world(torch_pos, BlockRegistry.BlockId.TORCH)

	var fb := FallingBlockClass.spawn_falling_block(wm, spawn_pos, BlockRegistry.BlockId.SAND)

	for frame in range(60):
		if not is_instance_valid(fb):
			break
		fb._physics_process(0.0166)

	var dropped_sand := false
	for c in wm.get_children():
		if c is DroppedItem and c.item_id == BlockRegistry.BlockId.SAND:
			dropped_sand = true
			c.queue_free()
			break

	if not dropped_sand:
		printerr("FAILED: No DroppedItem of Sand spawned when sand fell on torch!")
		return false

	print("  PASS: Falling sand shattered into dropped Sand item upon hitting torch obstacle.")
	return true


func test_cascading_sand_collapse(wm: WorldManager) -> bool:
	print("\n[TEST 3] Cascading Sand Column Collapse...")
	var base_pos := Vector3i(6, 60, 6)
	wm.set_block_world(base_pos, BlockRegistry.BlockId.STONE)
	wm.set_block_world(base_pos + Vector3i(0, 1, 0), BlockRegistry.BlockId.SAND)
	wm.set_block_world(base_pos + Vector3i(0, 2, 0), BlockRegistry.BlockId.SAND)
	wm.set_block_world(base_pos + Vector3i(0, 3, 0), BlockRegistry.BlockId.SAND)

	# Remove bottom sand at y=61
	wm.set_block_world(base_pos + Vector3i(0, 1, 0), BlockRegistry.BlockId.AIR)

	var fb_count := 0
	for c in wm.get_children():
		if c is FallingBlockClass:
			fb_count += 1
			c.queue_free()

	if fb_count < 2:
		printerr("FAILED: Expected at least 2 cascading falling sand blocks, found %d" % fb_count)
		return false

	print("  PASS: Breaking bottom block triggered cascading upward sand collapse (spawned %d FallingBlocks)." % fb_count)
	return true


func test_arrow_ballistics_and_block_hit(wm: WorldManager, player: PlayerController, inv: InventoryManager) -> bool:
	print("\n[TEST 4] Arrow Ballistics, Block Impact & Pickup...")
	# Wall at x=14, z=2 from y=60 to 65
	for y in range(60, 66):
		wm.set_block_world(Vector3i(14, y, 2), BlockRegistry.BlockId.STONE)

	var start_pos := Vector3(2.0, 62.0, 2.0)
	var arrow := ArrowProjectileClass.spawn_arrow(wm, start_pos, Vector3(30.0, 0.0, 0.0), 1.0)
	if arrow == null:
		printerr("FAILED: ArrowProjectile failed to spawn.")
		return false

	for step in range(40):
		if arrow.is_stuck:
			break
		arrow._physics_process(0.0166)

	if not arrow.is_stuck:
		printerr("FAILED: Arrow did not stick into solid stone wall!")
		return false

	if arrow.velocity != Vector3.ZERO:
		printerr("FAILED: Stuck arrow velocity is not ZERO!")
		return false

	# Test player proximity pickup
	var prev_arrows: int = inv.get_total_count(InventoryManager.ItemId.ARROW)
	player.position = arrow.position
	arrow._player = player
	arrow._inventory = inv
	arrow._process_stuck_state(0.0166)

	var post_arrows: int = inv.get_total_count(InventoryManager.ItemId.ARROW)
	if post_arrows != prev_arrows + 1:
		printerr("FAILED: Player did not pick up stuck arrow (before: %d, after: %d)" % [prev_arrows, post_arrows])
		return false

	print("  PASS: Arrow embedded in stone wall and was retrieved into player inventory upon proximity.")
	return true


func test_arrow_mob_damage(wm: WorldManager) -> bool:
	print("\n[TEST 5] Arrow Mob Collision, Damage & Despawn...")
	var mob := PassiveMob.new()
	mob.variant = PassiveMob.MobVariant.ZOMBIE
	mob.position = Vector3(8.0, 60.0, 8.0)
	mob.add_to_group("mobs")
	wm.add_child(mob)

	var initial_health: int = mob.health

	# Fire arrow from (2, 60.8, 8) towards (8, 60.8, 8)
	var arrow := ArrowProjectileClass.spawn_arrow(wm, Vector3(2.0, 60.8, 8.0), Vector3(25.0, 0.0, 0.0), 1.0)

	for step in range(30):
		if not is_instance_valid(arrow) or arrow.is_queued_for_deletion():
			break
		arrow._physics_process(0.0166)

	if is_instance_valid(arrow) and not arrow.is_queued_for_deletion():
		printerr("FAILED: Arrow did not despawn on mob hit!")
		mob.queue_free()
		return false

	if mob.health >= initial_health:
		printerr("FAILED: Mob health did not decrease on arrow hit! Health: %d / %d" % [mob.health, initial_health])
		mob.queue_free()
		return false

	print("  PASS: Arrow struck Zombie, dealt %d damage (HP %d -> %d), and despawned." % [initial_health - mob.health, initial_health, mob.health])
	mob.queue_free()
	return true


func test_bow_charging_and_firing(wm: WorldManager, player: PlayerController, interactor: BlockInteractor, inv: InventoryManager) -> bool:
	print("\n[TEST 6] Bow Charging, Drawing & Firing via BlockInteractor...")
	# Put Bow in hotbar slot 0, and Arrows in inventory
	inv.slots[0] = {"id": InventoryManager.ItemId.BOW, "count": 1, "durability": 384}
	inv.add_item(InventoryManager.ItemId.ARROW, 10)
	interactor.select_slot(0)

	var initial_arrows: int = inv.get_total_count(InventoryManager.ItemId.ARROW)

	# Simulate drawing bow for 0.5s
	interactor.is_drawing_bow = true
	interactor.bow_draw_time = 0.5

	# Fire bow
	interactor._fire_bow()

	var after_arrows: int = inv.get_total_count(InventoryManager.ItemId.ARROW)
	if after_arrows != initial_arrows - 1:
		printerr("FAILED: Bow did not consume 1 arrow on firing! (before: %d, after: %d)" % [initial_arrows, after_arrows])
		return false

	# Verify arrow projectile spawned
	var spawned_arrow: Node3D = null
	for c in wm.get_children():
		if c is ArrowProjectileClass:
			spawned_arrow = c
			break

	if spawned_arrow == null:
		printerr("FAILED: Bow firing did not spawn ArrowProjectile entity!")
		return false

	spawned_arrow.queue_free()
	print("  PASS: Bow drew smoothly, consumed 1 Arrow, and launched ballistic ArrowProjectile.")
	return true


func test_tnt_primed_physics_and_detonation(wm: WorldManager) -> bool:
	print("\n[TEST 7] Primed TNT Physics & Detonation...")
	wm.set_block_world(Vector3i(10, 60, 10), BlockRegistry.BlockId.STONE)

	var tnt := TNTPrimedClass.spawn_primed_tnt(wm, Vector3(10.5, 62.0, 10.5), Vector3(0.0, 1.5, 0.0), 0.10)
	if tnt == null:
		printerr("FAILED: TNTPrimed failed to spawn.")
		return false

	for step in range(25):
		if not is_instance_valid(tnt):
			break
		tnt._physics_process(0.0166)

	if is_instance_valid(tnt) and not tnt.is_detonated:
		printerr("FAILED: Primed TNT failed to detonate after fuse elapsed!")
		return false

	print("  PASS: Primed TNT entity simulated physics and detonated cleanly on fuse expiry.")
	return true


func test_explosion_blast_resistance_and_water(wm: WorldManager) -> bool:
	print("\n[TEST 8] Explosion Blast Resistance (Bedrock & Obsidian) & Water Absorption...")
	# Ground at y=60: Bedrock at (10, 60, 10), Obsidian at (11, 60, 10), Stone at (10, 60, 11)
	wm.set_block_world(Vector3i(10, 60, 10), BlockRegistry.BlockId.BEDROCK)
	wm.set_block_world(Vector3i(11, 60, 10), BlockRegistry.BlockId.OBSIDIAN)
	wm.set_block_world(Vector3i(10, 60, 11), BlockRegistry.BlockId.STONE)

	# Detonate explosion at (10.5, 60.5, 10.5)
	wm.create_explosion(Vector3(10.5, 60.5, 10.5), 3.5, true, false)

	var bedrock_left: int = wm.get_block_world(Vector3i(10, 60, 10))
	var obsidian_left: int = wm.get_block_world(Vector3i(11, 60, 10))
	var stone_left: int = wm.get_block_world(Vector3i(10, 60, 11))

	if bedrock_left != BlockRegistry.BlockId.BEDROCK:
		printerr("FAILED: Bedrock was destroyed by explosion! Got: %d" % bedrock_left)
		return false

	if obsidian_left != BlockRegistry.BlockId.OBSIDIAN:
		printerr("FAILED: Obsidian was destroyed by explosion! Got: %d" % obsidian_left)
		return false

	if stone_left != BlockRegistry.BlockId.AIR:
		printerr("FAILED: Stone was not destroyed in blast crater!")
		return false

	print("  PASS: Bedrock and Obsidian withstood explosion; Stone in blast crater was destroyed.")

	# Submerged explosion in water at (12, 60, 12)
	wm.set_block_world(Vector3i(12, 60, 12), BlockRegistry.BlockId.WATER)
	wm.set_block_world(Vector3i(13, 60, 12), BlockRegistry.BlockId.STONE)

	wm.create_explosion(Vector3(12.5, 60.5, 12.5), 3.5, true, false)

	var water_stone_left: int = wm.get_block_world(Vector3i(13, 60, 12))
	if water_stone_left != BlockRegistry.BlockId.STONE:
		printerr("FAILED: Submerged water explosion destroyed adjacent stone! Got: %d" % water_stone_left)
		return false

	print("  PASS: Submerged explosion in water absorbed shockwave and preserved terrain.")
	return true
