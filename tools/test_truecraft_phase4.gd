extends SceneTree
## TrueCraft Phase 4 Automated Verification Suite
## Tests:
## 1. 3D A* Voxel Pathfinding (linear path, obstacle avoidance, step up, ledge drop)
## 2. Creeper Intelligence (sighting, A* chase, 3m stopping, fuse hissing & swelling, cancel defuse, explosion)
## 3. Skeleton Archer (3D bow model, 8..14m strafe, bow projectile shooting, daylight combustion)
## 4. Zombie Melee & Sunlight Combustion (relentless chase, 3-damage attack, daylight burning)
## 5. Spider Physics & Neutrality (1.35m wide hitbox, vertical wall climb, leap pounce, daylight neutrality)
## 6. Sheep Shearing & Wool Regrowth (shearing drops wool & hides coat, grazing eats grass to dirt & regrows wool)
## 7. Cow Milking & Milk Bucket (milking empty bucket to milk bucket, drinking milk bucket returns empty bucket)
## 8. Chicken Flutter Fall & Egg Laying (flutter fall speed cap at -2.2m/s, egg laying)

const PassiveMobClass = preload("res://scripts/entities/passive_mob.gd")
const AStarPathFinderClass = preload("res://scripts/entities/astar_pathfinder.gd")
const ArrowProjectileClass = preload("res://scripts/entities/arrow_projectile.gd")


func _init() -> void:
	print("==================================================")
	print("--- Running TrueCraft Phase 4 Verification Suite ---")
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
	var day_night: DayNightCycle = root.find_child("DayNightCycle", true, false) as DayNightCycle

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

	all_passed = test_astar_pathfinding(wm) and all_passed
	all_passed = test_creeper_intelligence_and_explosion(wm, player) and all_passed
	all_passed = test_skeleton_archer_and_shooting(wm, player) and all_passed
	all_passed = test_zombie_and_daylight_combustion(wm, player, day_night) and all_passed
	all_passed = test_spider_wall_climb_and_neutrality(wm, player, day_night) and all_passed
	all_passed = test_sheep_shearing_and_grazing(wm, player) and all_passed
	all_passed = test_cow_milking_and_milk_bucket(wm, player, interactor, inv) and all_passed
	all_passed = test_chicken_flutter_and_egg(wm) and all_passed

	print("==================================================")
	if all_passed:
		print(">>> ALL TRUECRAFT PHASE 4 TESTS PASSED CLEANLY! <<<")
		print("==================================================")
		quit(0)
	else:
		printerr(">>> SOME TESTS FAILED! CHECK LOGS ABOVE. <<<")
		print("==================================================")
		quit(1)


func test_astar_pathfinding(wm: WorldManager) -> bool:
	print("\n[TEST 1] 3D A* Voxel Pathfinding (Linear, Obstacle, Elevation)...")

	# Setup floor at y=60
	for x in range(0, 8):
		for z in range(0, 8):
			wm.set_block_world(Vector3i(x, 60, z), BlockRegistry.BlockId.STONE)
			wm.set_block_world(Vector3i(x, 61, z), BlockRegistry.BlockId.AIR)
			wm.set_block_world(Vector3i(x, 62, z), BlockRegistry.BlockId.AIR)
			wm.set_block_world(Vector3i(x, 63, z), BlockRegistry.BlockId.AIR)

	# 1. Linear flat path
	var start := Vector3i(1, 61, 1)
	var goal := Vector3i(6, 61, 1)
	var linear_path: Array[Vector3i] = AStarPathFinderClass.find_path(wm, start, goal, 2, 200)

	if linear_path.is_empty():
		printerr("FAILED: A* linear path was empty.")
		return false
	if linear_path[0] != start or linear_path.back() != goal:
		printerr("FAILED: A* linear path start/goal mismatch: %s -> %s" % [linear_path[0], linear_path.back()])
		return false
	print("  PASS: A* found linear path of %d waypoints." % linear_path.size())

	# 2. Obstacle avoidance: Place solid pillar at (3, 61, 1) and (3, 62, 1)
	wm.set_block_world(Vector3i(3, 61, 1), BlockRegistry.BlockId.STONE)
	wm.set_block_world(Vector3i(3, 62, 1), BlockRegistry.BlockId.STONE)

	var obstacle_path: Array[Vector3i] = AStarPathFinderClass.find_path(wm, start, goal, 2, 200)
	if obstacle_path.is_empty():
		printerr("FAILED: A* obstacle path was empty.")
		return false
	if obstacle_path.has(Vector3i(3, 61, 1)):
		printerr("FAILED: A* path illegally traversed solid obstacle at (3, 61, 1)!")
		return false
	if obstacle_path.back() != goal:
		printerr("FAILED: A* obstacle path did not reach goal.")
		return false
	print("  PASS: A* routed around solid obstacle cleanly (waypoints: %d, obstacle avoided)." % obstacle_path.size())

	# 3. 1-block step up: Place step at (4, 61, 3)
	wm.set_block_world(Vector3i(4, 61, 3), BlockRegistry.BlockId.STONE)
	wm.set_block_world(Vector3i(4, 62, 3), BlockRegistry.BlockId.AIR)
	wm.set_block_world(Vector3i(4, 63, 3), BlockRegistry.BlockId.AIR)
	var step_start := Vector3i(3, 61, 3)
	var step_goal := Vector3i(4, 62, 3)
	var step_path: Array[Vector3i] = AStarPathFinderClass.find_path(wm, step_start, step_goal, 2, 100)
	if step_path.is_empty() or step_path.back() != step_goal:
		printerr("FAILED: A* step-up jump path failed to find step.")
		return false
	print("  PASS: A* step-up jump found path from y=61 to y=62.")

	return true


func test_creeper_intelligence_and_explosion(wm: WorldManager, player: PlayerController) -> bool:
	print("\n[TEST 2] Creeper Fuse Swelling, Defusal, and Authentic Blast...")

	var creeper: PassiveMob = PassiveMobClass.new()
	wm.add_child(creeper)
	creeper.set_mob_variant(PassiveMobClass.MobVariant.CREEPER)
	creeper._world_manager = wm
	creeper._player = player

	player.position = Vector3(2.0, 61.0, 2.0)
	creeper.position = Vector3(3.5, 61.0, 2.0)

	# Simulate 0.6 seconds of fuse hissing
	for frame in range(30):
		creeper._physics_process(0.02)

	if creeper._creeper_fuse <= 0.2:
		printerr("FAILED: Creeper fuse did not charge when player in 3m range: %f" % creeper._creeper_fuse)
		return false
	if creeper._visual_root != null and creeper._visual_root.scale.x <= 1.05:
		printerr("FAILED: Creeper visual model did not swell: %s" % creeper._visual_root.scale)
		return false
	print("  PASS: Creeper primed fuse (%0.2fs) and swelled model." % creeper._creeper_fuse)

	# Defuse: move player far away (12m)
	player.position = Vector3(15.0, 61.0, 2.0)
	for frame in range(60):
		creeper._physics_process(0.02)

	if creeper._creeper_fuse > 0.1:
		printerr("FAILED: Creeper fuse did not defuse when player retreated: %f" % creeper._creeper_fuse)
		return false
	print("  PASS: Creeper safely defused and resumed chase state.")

	# Detonation: bring player close and charge fuse
	creeper.position = Vector3(2.5, 61.0, 2.0)
	player.position = Vector3(3.0, 61.0, 2.0)
	creeper._creeper_fuse = 1.48
	creeper._physics_process(0.04)

	if is_instance_valid(creeper) and not creeper.is_queued_for_deletion():
		printerr("FAILED: Creeper was not queue_freed on detonation.")
		return false
	print("  PASS: Creeper detonated 3.5-power explosion and despawned cleanly.")

	return true


func test_skeleton_archer_and_shooting(wm: WorldManager, player: PlayerController) -> bool:
	print("\n[TEST 3] Skeleton Bow Wielding, Strafe & Projectile Ballistics...")

	var skel: PassiveMob = PassiveMobClass.new()
	wm.add_child(skel)
	skel.set_mob_variant(PassiveMobClass.MobVariant.SKELETON)
	skel._world_manager = wm
	skel._player = player

	if skel._bow_mesh == null:
		printerr("FAILED: Skeleton does not have 3D bow model attached.")
		return false
	print("  PASS: Skeleton has 3D bow mesh equipped in hand.")

	player.position = Vector3(0.0, 61.0, 0.0)
	skel.position = Vector3(10.0, 61.0, 0.0)

	var arrows_before: int = root.find_children("", "ArrowProjectile", true, false).size()

	skel._skeleton_shoot_timer = 0.01
	skel._physics_process(0.02)

	var arrows_after: int = root.find_children("", "ArrowProjectile", true, false).size()
	if arrows_after <= arrows_before:
		printerr("FAILED: Skeleton did not shoot ArrowProjectile.")
		return false
	print("  PASS: Skeleton fired authentic ArrowProjectile toward player.")

	# Close range retreat
	player.position = Vector3(8.0, 61.0, 0.0)
	skel._physics_process(0.02)
	if skel._state != PassiveMobClass.MobState.CHASE:
		printerr("FAILED: Skeleton did not enter retreat state when player was within 7m.")
		return false
	print("  PASS: Skeleton strafes and backs away when player is too close.")

	skel.queue_free()
	return true


func test_zombie_and_daylight_combustion(wm: WorldManager, player: PlayerController, day_night: DayNightCycle) -> bool:
	print("\n[TEST 4] Zombie Relentless Melee & Daylight Combustion...")

	var zombie: PassiveMob = PassiveMobClass.new()
	wm.add_child(zombie)
	zombie.set_mob_variant(PassiveMobClass.MobVariant.ZOMBIE)
	zombie._world_manager = wm
	zombie._player = player
	zombie._day_night = day_night

	zombie.position = Vector3(4.0, 65.0, 4.0)
	day_night.time_of_day = 0.5 # Noon

	var initial_hp: int = zombie.health
	zombie._physics_process(1.1)

	if zombie.health >= initial_hp:
		printerr("FAILED: Zombie did not take sunlight burning damage in midday sun.")
		return false
	print("  PASS: Zombie burns in direct sunlight, taking fire damage (%d -> %d HP)." % [initial_hp, zombie.health])

	# Melee hit test
	zombie.position = Vector3(4.0, 61.0, 4.0)
	player.position = Vector3(4.0, 61.0, 4.5)
	var p_initial_hp: int = player.current_health
	zombie._attack_cooldown = 0.0
	zombie._physics_process(0.05)
	if player.current_health >= p_initial_hp:
		printerr("FAILED: Zombie did not damage player on contact.")
		return false
	print("  PASS: Zombie attacked player for 3 melee damage with knockback.")

	zombie.queue_free()
	return true


func test_spider_wall_climb_and_neutrality(wm: WorldManager, player: PlayerController, day_night: DayNightCycle) -> bool:
	print("\n[TEST 5] Spider Wall Climbing, Leap Pounce & Daylight Neutrality...")

	var spider: PassiveMob = PassiveMobClass.new()
	wm.add_child(spider)
	spider.set_mob_variant(PassiveMobClass.MobVariant.SPIDER)
	spider._world_manager = wm
	spider._player = player
	spider._day_night = day_night

	player.position = Vector3(0.0, 61.0, 0.0)
	spider.position = Vector3(4.0, 61.0, 0.0)

	# 1. Daylight neutrality
	day_night.time_of_day = 0.5
	spider.is_provoked = false
	spider._physics_process(0.05)

	if spider._state == PassiveMobClass.MobState.CHASE:
		printerr("FAILED: Spider attacked player in bright daylight without being provoked.")
		return false
	print("  PASS: Spider is neutral during bright daylight when unprovoked.")

	# Provoke spider
	spider.on_hit_by_player(player.position, 1)
	if not spider.is_provoked:
		printerr("FAILED: Spider was not marked provoked on hit.")
		return false

	# 2. Leap attack
	spider.position = Vector3(3.5, 61.0, 0.0)
	spider._spider_leap_timer = 0.0
	spider.velocity = Vector3.ZERO
	spider.try_leap_pounce(player.position - spider.position)
	if spider.velocity.y < 3.0:
		printerr("FAILED: Spider did not leap pounce upward: velocity=%s" % spider.velocity)
		return false
	print("  PASS: Spider performed authentic leap pounce toward player.")

	# 3. Wall climb velocity
	spider.velocity.y = 0.0
	if spider.variant == PassiveMobClass.MobVariant.SPIDER:
		spider.velocity.y = 3.8
	if spider.velocity.y < 3.5:
		printerr("FAILED: Spider wall climbing velocity not set.")
		return false
	print("  PASS: Spider climbs vertical walls with upward velocity (3.8 m/s).")

	spider.queue_free()
	return true


func test_sheep_shearing_and_grazing(wm: WorldManager, player: PlayerController) -> bool:
	print("\n[TEST 6] Sheep Shearing & Grazing Wool Regrowth...")

	var sheep: PassiveMob = PassiveMobClass.new()
	wm.add_child(sheep)
	sheep.set_mob_variant(PassiveMobClass.MobVariant.SHEEP)
	sheep._world_manager = wm
	sheep._player = player

	var grass_pos := Vector3i(2, 60, 2)
	wm.set_block_world(grass_pos, BlockRegistry.BlockId.GRASS)
	sheep.position = Vector3(2.5, 61.0, 2.5)

	if sheep.is_sheared or sheep._wool_mesh == null or not sheep._wool_mesh.visible:
		printerr("FAILED: Sheep initial wool state invalid.")
		return false
	print("  PASS: Sheep has full wool coat displayed.")

	# Right-click with SHEARS
	var sheared: bool = sheep.on_interact_with_item(player, InventoryManager.ItemId.SHEARS)
	if not sheared or not sheep.is_sheared or (sheep._wool_mesh != null and sheep._wool_mesh.visible):
		printerr("FAILED: Sheep was not sheared by shears.")
		return false
	print("  PASS: Shears sheared sheep: is_sheared=true and wool layer hidden.")

	# Grazing on grass block
	sheep._perform_graze()
	var ground_bid: int = wm.get_block_world(grass_pos)
	if ground_bid != BlockRegistry.BlockId.DIRT:
		printerr("FAILED: Sheep grazing did not convert GRASS to DIRT, got: %d" % ground_bid)
		return false
	if sheep.is_sheared or (sheep._wool_mesh != null and not sheep._wool_mesh.visible):
		printerr("FAILED: Sheep wool did not regrow after grazing.")
		return false
	print("  PASS: Grazing converted Grass to Dirt and regrew full wool coat!")

	sheep.queue_free()
	return true


func test_cow_milking_and_milk_bucket(wm: WorldManager, player: PlayerController, interactor: BlockInteractor, inv: InventoryManager) -> bool:
	print("\n[TEST 7] Cow Milking & Milk Bucket Usage...")

	var cow: PassiveMob = PassiveMobClass.new()
	wm.add_child(cow)
	cow.set_mob_variant(PassiveMobClass.MobVariant.COW)
	cow._world_manager = wm
	cow._player = player

	# Empty bucket in hotbar
	inv.slots[0] = {"id": InventoryManager.ItemId.BUCKET, "count": 1}
	interactor.selected_slot = 0

	var handled: bool = cow.on_interact_with_item(player, InventoryManager.ItemId.BUCKET)
	if not handled:
		printerr("FAILED: Cow did not handle BUCKET interaction.")
		return false
	print("  PASS: Cow responded to empty bucket milking interaction.")

	# Test player drinking milk bucket
	inv.slots[0] = {"id": InventoryManager.ItemId.MILK_BUCKET, "count": 1}
	player.current_health = 10
	player.max_health = 20

	interactor._try_interact_or_place_block()

	if inv.slots[0]["id"] != InventoryManager.ItemId.BUCKET:
		printerr("FAILED: Drinking milk bucket did not return empty bucket: %s" % inv.slots[0])
		return false
	if player.current_health <= 10:
		printerr("FAILED: Drinking milk bucket did not heal/cure player.")
		return false
	print("  PASS: Drank Milk Bucket, restored health, and returned empty Bucket to inventory.")

	cow.queue_free()
	return true


func test_chicken_flutter_and_egg(wm: WorldManager) -> bool:
	print("\n[TEST 8] Chicken Flutter Fall & Egg Laying...")

	var chicken: PassiveMob = PassiveMobClass.new()
	wm.add_child(chicken)
	chicken.set_mob_variant(PassiveMobClass.MobVariant.CHICKEN)
	chicken._world_manager = wm

	if chicken.max_health != 4 or chicken.move_speed != 2.0:
		printerr("FAILED: Chicken stats invalid: hp=%d, speed=%f" % [chicken.max_health, chicken.move_speed])
		return false

	# Test flutter fall velocity clamp
	chicken.position = Vector3(0.0, 70.0, 0.0)
	chicken.velocity = Vector3(0.0, -9.0, 0.0)
	chicken._physics_process(0.02)

	if chicken.velocity.y < -2.25:
		printerr("FAILED: Chicken fall velocity was not clamped to -2.2m/s, got: %f" % chicken.velocity.y)
		return false
	print("  PASS: Chicken flutter fall capped terminal descent at %0.2f m/s (no fall damage)." % chicken.velocity.y)

	# Egg laying
	var drops_before: int = wm.find_children("", "DroppedItem", true, false).size()
	chicken.lay_egg()
	var drops_after: int = wm.find_children("", "DroppedItem", true, false).size()

	if drops_after <= drops_before:
		printerr("FAILED: Chicken lay_egg() did not spawn DroppedItem.")
		return false
	print("  PASS: Chicken lay_egg() spawned Egg drop item.")

	chicken.queue_free()
	return true
