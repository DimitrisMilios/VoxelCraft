extends SceneTree
## Phase 5 Verification Test: Authentic Dual-Channel Voxel Lighting & Armor Mitigation System

const VoxelLighting = preload("res://scripts/world/voxel_lighting.gd")

var _passed: int = 0
var _total: int = 0


func _init() -> void:
	print("==================================================================")
	print("   VOXELCRAFT - PHASE 5 VERIFICATION TEST                         ")
	print("   Dual-Channel Voxel Lighting & Armor Mitigation System          ")
	print("==================================================================")

	test_1_skylight_column_propagation()
	test_2_blocklight_bfs_propagation()
	test_3_smooth_ambient_occlusion()
	test_4_armor_classification_and_points()
	test_5_damage_mitigation_calculation()
	test_6_armor_durability_and_breakage()
	test_7_player_controller_armor_mitigation()
	test_8_hud_armor_bar_integration()

	print("==================================================================")
	print("   TEST RESULTS: %d / %d PASSED" % [_passed, _total])
	print("==================================================================")

	if _passed == _total:
		print(">> ALL PHASE 5 TESTS PASSED SUCCESSFULLY! <<")
		quit(0)
	else:
		printerr(">> SOME PHASE 5 TESTS FAILED! <<")
		quit(1)


func test_1_skylight_column_propagation() -> void:
	_total += 1
	print("\n[Test 1] Skylight Column Propagation (15 at sky, 0 under solid block)...")

	var chunk := VoxelChunk.new()
	chunk.chunk_coords = Vector2i(0, 0)

	# Fill column with air, then put a solid stone block at Y=64
	for y in range(VoxelChunk.CHUNK_SIZE_Y):
		chunk.set_block_local(4, y, 4, BlockRegistry.BlockId.AIR)
	chunk.set_block_local(4, 64, 4, BlockRegistry.BlockId.STONE)

	# Compute lighting
	VoxelLighting.compute_chunk_lighting(chunk)

	var sky_above: int = chunk.get_sky_light_local(4, 70, 4)
	var sky_at_stone: int = chunk.get_sky_light_local(4, 64, 4)
	var sky_below: int = chunk.get_sky_light_local(4, 50, 4)

	print("  Sky above (Y=70): %d (expected 15)" % sky_above)
	print("  Sky at stone (Y=64): %d (expected 0)" % sky_at_stone)
	print("  Sky below (Y=50): %d (expected 14: daylight spreads in sideways under a single floating block)" % sky_below)

	if sky_above == 15 and sky_at_stone == 0 and sky_below == 14:
		print("  PASS: Skylight fills columns, stops at solid blocks, and spreads sideways into shade.")
		_passed += 1
	else:
		printerr("  FAIL: Skylight propagation incorrect.")
	chunk.free()


func test_2_blocklight_bfs_propagation() -> void:
	_total += 1
	print("\n[Test 2] Blocklight BFS Flood Fill & Emission Tables...")

	# Verify luminance constants
	var torch_lum: int = VoxelLighting.get_block_luminance(BlockRegistry.BlockId.TORCH)
	var lava_lum: int = VoxelLighting.get_block_luminance(BlockRegistry.BlockId.LAVA)
	var glow_lum: int = VoxelLighting.get_block_luminance(BlockRegistry.BlockId.GLOWSTONE)
	var stone_lum: int = VoxelLighting.get_block_luminance(BlockRegistry.BlockId.STONE)

	print("  Luminance: Torch=%d, Lava=%d, Glowstone=%d, Stone=%d" % [torch_lum, lava_lum, glow_lum, stone_lum])
	if torch_lum != 14 or lava_lum != 15 or glow_lum != 15 or stone_lum != 0:
		printerr("  FAIL: Incorrect block luminance values.")
		return

	var chunk := VoxelChunk.new()
	chunk.chunk_coords = Vector2i(0, 0)

	# Clear air room
	for x in range(3, 10):
		for y in range(10, 16):
			for z in range(3, 10):
				chunk.set_block_local(x, y, z, BlockRegistry.BlockId.AIR)

	# Place torch at (6, 12, 6)
	chunk.set_block_local(6, 12, 6, BlockRegistry.BlockId.TORCH)
	VoxelLighting.compute_chunk_lighting(chunk)

	var torch_light: int = chunk.get_block_light_local(6, 12, 6)
	var neighbor_light: int = chunk.get_block_light_local(7, 12, 6)
	var dist_2_light: int = chunk.get_block_light_local(8, 12, 6)

	print("  Torch pos (6, 12, 6) light: %d (expected 14)" % torch_light)
	print("  Adjacent pos (7, 12, 6) light: %d (expected 13)" % neighbor_light)
	print("  Distance 2 pos (8, 12, 6) light: %d (expected 12)" % dist_2_light)

	if torch_light == 14 and neighbor_light == 13 and dist_2_light == 12:
		print("  PASS: Blocklight BFS correctly propagates and attenuates with distance.")
		_passed += 1
	else:
		printerr("  FAIL: Blocklight propagation values incorrect.")
	chunk.free()


func test_3_smooth_ambient_occlusion() -> void:
	_total += 1
	print("\n[Test 3] Smooth Ambient Occlusion (AO) Vertex Shading...")

	var chunk := VoxelChunk.new()
	chunk.chunk_coords = Vector2i(0, 0)

	# Make floor at Y=10
	for x in range(2, 8):
		for z in range(2, 8):
			chunk.set_block_local(x, 10, z, BlockRegistry.BlockId.DIRT)

	VoxelLighting.compute_chunk_lighting(chunk)

	# Flat open face (top face of (4, 10, 4))
	var flat_ao: Array[float] = VoxelLighting.calculate_face_ao_and_lighting(
		chunk, 4, 10, 4, BlockRegistry.FaceDir.TOP, BlockRegistry.BlockId.DIRT
	)
	print("  Flat open face AO multipliers: %s" % str(flat_ao))

	# Add a solid wall block right next to it at (4, 11, 3) to cast AO shadow
	chunk.set_block_local(4, 11, 3, BlockRegistry.BlockId.STONE)

	var shadowed_ao: Array[float] = VoxelLighting.calculate_face_ao_and_lighting(
		chunk, 4, 10, 4, BlockRegistry.FaceDir.TOP, BlockRegistry.BlockId.DIRT
	)
	print("  Shadowed face AO multipliers: %s" % str(shadowed_ao))

	var has_shadow: bool = false
	for val in shadowed_ao:
		if val < flat_ao[0]:
			has_shadow = true
			break

	if flat_ao.size() == 4 and has_shadow:
		print("  PASS: Corner ambient occlusion darkens vertices next to solid blocks.")
		_passed += 1
	else:
		printerr("  FAIL: Ambient occlusion vertex calculations incorrect.")
	chunk.free()


func test_4_armor_classification_and_points() -> void:
	_total += 1
	print("\n[Test 4] Armor Classification & Defense Points Table...")

	# Leather
	var l_helm: int = InventoryManager.get_armor_defense_points(InventoryManager.ItemId.LEATHER_HELMET)
	var l_chest: int = InventoryManager.get_armor_defense_points(InventoryManager.ItemId.LEATHER_CHESTPLATE)
	var l_legs: int = InventoryManager.get_armor_defense_points(InventoryManager.ItemId.LEATHER_LEGGINGS)
	var l_boots: int = InventoryManager.get_armor_defense_points(InventoryManager.ItemId.LEATHER_BOOTS)
	var l_total: int = l_helm + l_chest + l_legs + l_boots

	# Diamond
	var d_helm: int = InventoryManager.get_armor_defense_points(InventoryManager.ItemId.DIAMOND_HELMET)
	var d_chest: int = InventoryManager.get_armor_defense_points(InventoryManager.ItemId.DIAMOND_CHESTPLATE)
	var d_legs: int = InventoryManager.get_armor_defense_points(InventoryManager.ItemId.DIAMOND_LEGGINGS)
	var d_boots: int = InventoryManager.get_armor_defense_points(InventoryManager.ItemId.DIAMOND_BOOTS)
	var d_total: int = d_helm + d_chest + d_legs + d_boots

	print("  Leather Set points: H=%d, C=%d, L=%d, B=%d -> Total: %d (expected 7)" % [l_helm, l_chest, l_legs, l_boots, l_total])
	print("  Diamond Set points: H=%d, C=%d, L=%d, B=%d -> Total: %d (expected 20)" % [d_helm, d_chest, d_legs, d_boots, d_total])

	var inv := InventoryManager.new()
	inv.equip_armor_piece(InventoryManager.ArmorSlot.HELMET, {"id": InventoryManager.ItemId.DIAMOND_HELMET, "count": 1})
	inv.equip_armor_piece(InventoryManager.ArmorSlot.CHESTPLATE, {"id": InventoryManager.ItemId.DIAMOND_CHESTPLATE, "count": 1})
	inv.equip_armor_piece(InventoryManager.ArmorSlot.LEGGINGS, {"id": InventoryManager.ItemId.DIAMOND_LEGGINGS, "count": 1})
	inv.equip_armor_piece(InventoryManager.ArmorSlot.BOOTS, {"id": InventoryManager.ItemId.DIAMOND_BOOTS, "count": 1})

	var equipped_total: int = inv.get_total_defense_points()
	print("  Equipped Diamond Set get_total_defense_points(): %d" % equipped_total)

	if l_total == 7 and d_total == 20 and equipped_total == 20:
		print("  PASS: Armor defense points exactly match authentic Beta 1.7.3.")
		_passed += 1
	else:
		printerr("  FAIL: Defense point values mismatch.")
	inv.free()


func test_5_damage_mitigation_calculation() -> void:
	_total += 1
	print("\n[Test 5] Armor Damage Mitigation Calculation (4% per defense point)...")

	var inv := InventoryManager.new()

	# Without armor (0 points)
	var unarmored_dmg: int = inv.calculate_damage_mitigation(10)
	print("  Raw damage 10 without armor: %d (expected 10)" % unarmored_dmg)

	# Equip full diamond armor (20 points -> 80% mitigation)
	inv.equip_armor_piece(InventoryManager.ArmorSlot.HELMET, {"id": InventoryManager.ItemId.DIAMOND_HELMET, "count": 1})
	inv.equip_armor_piece(InventoryManager.ArmorSlot.CHESTPLATE, {"id": InventoryManager.ItemId.DIAMOND_CHESTPLATE, "count": 1})
	inv.equip_armor_piece(InventoryManager.ArmorSlot.LEGGINGS, {"id": InventoryManager.ItemId.DIAMOND_LEGGINGS, "count": 1})
	inv.equip_armor_piece(InventoryManager.ArmorSlot.BOOTS, {"id": InventoryManager.ItemId.DIAMOND_BOOTS, "count": 1})

	var mitigated_10: int = inv.calculate_damage_mitigation(10)
	var mitigated_5: int = inv.calculate_damage_mitigation(5)
	var mitigated_1: int = inv.calculate_damage_mitigation(1)

	print("  Raw damage 10 with 20 defense pts: %d (expected 2 [80%% absorbed])" % mitigated_10)
	print("  Raw damage 5 with 20 defense pts: %d (expected 1 [80%% absorbed])" % mitigated_5)
	print("  Raw damage 1 with 20 defense pts: %d (expected 1 [minimum damage])" % mitigated_1)

	if unarmored_dmg == 10 and mitigated_10 == 2 and mitigated_5 == 1 and mitigated_1 == 1:
		print("  PASS: Damage mitigation accurately absorbs up to 80% with min 1 damage clamp.")
		_passed += 1
	else:
		printerr("  FAIL: Damage mitigation calculation mismatch.")
	inv.free()


func test_6_armor_durability_and_breakage() -> void:
	_total += 1
	print("\n[Test 6] Armor Durability Degradation & Item Breakage...")

	var inv := InventoryManager.new()

	# Equip leather cap with custom durability 2
	inv.equip_armor_piece(InventoryManager.ArmorSlot.HELMET, {
		"id": InventoryManager.ItemId.LEATHER_HELMET,
		"count": 1,
		"durability": 2
	})

	var initial_pts: int = inv.get_total_defense_points()
	print("  Initial defense points: %d (durability 2)" % initial_pts)

	# Hit 1: Durability drops to 1
	inv.damage_equipped_armor(1)
	var dur_after_1: int = int(inv.armor_slots[InventoryManager.ArmorSlot.HELMET].get("durability", 0))
	print("  After hit 1 durability: %d (expected 1)" % dur_after_1)

	# Hit 2: Durability reaches 0 -> breaks and clears slot!
	inv.damage_equipped_armor(1)
	var id_after_break: int = int(inv.armor_slots[InventoryManager.ArmorSlot.HELMET].get("id", 0))
	var pts_after_break: int = inv.get_total_defense_points()
	print("  After hit 2: slot item ID = %d (expected 0), defense points = %d (expected 0)" % [id_after_break, pts_after_break])

	if initial_pts == 1 and dur_after_1 == 1 and id_after_break == 0 and pts_after_break == 0:
		print("  PASS: Armor absorbs durability damage and breaks cleanly at 0 HP.")
		_passed += 1
	else:
		printerr("  FAIL: Armor durability breakage incorrect.")
	inv.free()


func test_7_player_controller_armor_mitigation() -> void:
	_total += 1
	print("\n[Test 7] PlayerController Damage Mitigation Integration...")

	var player := PlayerController.new()
	player.current_health = 20
	player.is_flying = false

	var inv := InventoryManager.new()
	player.inventory = inv
	root.add_child(inv)
	root.add_child(player)

	# Equip full diamond armor (20 points -> 80% mitigation)
	inv.equip_armor_piece(InventoryManager.ArmorSlot.HELMET, {"id": InventoryManager.ItemId.DIAMOND_HELMET, "count": 1})
	inv.equip_armor_piece(InventoryManager.ArmorSlot.CHESTPLATE, {"id": InventoryManager.ItemId.DIAMOND_CHESTPLATE, "count": 1})
	inv.equip_armor_piece(InventoryManager.ArmorSlot.LEGGINGS, {"id": InventoryManager.ItemId.DIAMOND_LEGGINGS, "count": 1})
	inv.equip_armor_piece(InventoryManager.ArmorSlot.BOOTS, {"id": InventoryManager.ItemId.DIAMOND_BOOTS, "count": 1})

	# Player takes 10 raw damage -> should be mitigated to 2 damage!
	player.take_damage(10)
	print("  Player health after 10 raw damage: %d / 20 (expected 18)" % player.current_health)

	var passed_test: bool = (player.current_health == 18)
	player.queue_free()
	inv.queue_free()

	if passed_test:
		print("  PASS: PlayerController successfully absorbs mitigated damage via equipped armor.")
		_passed += 1
	else:
		printerr("  FAIL: Player health was not mitigated properly.")


func test_8_hud_armor_bar_integration() -> void:
	_total += 1
	print("\n[Test 8] HUD Armor Bar Integration & Visibility...")

	var hud := VoxelHUD.new()
	root.add_child(hud)
	hud._ready()

	hud.update_armor_bar(0)
	var hidden_at_0: bool = (hud._armor_hbox != null and not hud._armor_hbox.visible)
	print("  Armor bar visible with 0 defense points: %s (expected false)" % str(not hidden_at_0))

	hud.update_armor_bar(15)
	var shown_at_15: bool = (hud._armor_hbox != null and hud._armor_hbox.visible)
	print("  Armor bar visible with 15 defense points: %s (expected true)" % str(shown_at_15))

	var icons_configured: bool = (hud._armor_icons.size() == 10)
	print("  Armor bar icon count: %d (expected 10)" % hud._armor_icons.size())

	hud.queue_free()

	if hidden_at_0 and shown_at_15 and icons_configured:
		print("  PASS: HUD armor bar dynamically shows/hides and updates 10 icons.")
		_passed += 1
	else:
		printerr("  FAIL: HUD armor bar configuration incorrect.")
