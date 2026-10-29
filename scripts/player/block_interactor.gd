class_name BlockInteractor
extends Node3D
const FallingBlockClass = preload("res://scripts/entities/falling_block.gd")
const ArrowProjectileClass = preload("res://scripts/entities/arrow_projectile.gd")
## Handles raycast block targeting, authentic Minecraft tool-tier mining mechanics,
## 9-slot hotbar selection (keys 1-9), block placement from inventory stacks,
## and opening the Player 2x2 Inventory (E), 3x3 Crafting Table, or Furnace Oven.

signal hotbar_slot_changed(slot_index: int, item_id: int)
signal block_broken(world_pos: Vector3i, broken_block_id: int)
signal block_placed(world_pos: Vector3i, placed_block_id: int)
signal mob_interacted(is_hit: bool, mob_variant: int)
signal mining_progress_changed(progress: float, target_name: String, can_harvest: bool)
signal station_opened(station_block_id: int) # 0 = Player 2x2 Inventory, 16 = 3x3 Crafting Table, 17 = Furnace Oven
signal loot_notification(message: String)

@export var raycast_path: NodePath = NodePath("../Head/Camera3D/InteractionRay")
@export var player_body_path: NodePath = NodePath("..")

var selected_slot: int = 0
var has_target: bool = false
var target_block_pos: Vector3i = Vector3i.ZERO
var place_block_pos: Vector3i = Vector3i.ZERO
var mining_progress: float = 0.0
var is_drawing_bow: bool = false
var bow_draw_time: float = 0.0

var _raycast: RayCast3D = null
var _player_body: PlayerController = null
var _world_manager: WorldManager = null
var _inventory: InventoryManager = null
var _selection_box: MeshInstance3D = null
var _selection_mat: StandardMaterial3D = null
var _crack_box: MeshInstance3D = null
var _crack_mat: StandardMaterial3D = null
var _crack_textures: Array[ImageTexture] = []
var _targeted_mob: PassiveMob = null
var _last_mining_pos: Vector3i = Vector3i(999999, 999999, 999999)
var _swing_repeat_timer: float = 0.0
## Pause between finishing one block and starting the next while holding attack (5 ticks).
const BREAK_DELAY: float = 0.25
var _break_cooldown: float = 0.0
var _mining_item_id: int = -1
var _last_hit_point: Vector3 = Vector3.ZERO


func _ready() -> void:
	_raycast = get_node_or_null(raycast_path) as RayCast3D
	_player_body = get_node_or_null(player_body_path) as PlayerController
	_create_selection_wireframe()
	_create_crack_overlay_mesh()
	call_deferred("_resolve_dependencies")


func _resolve_dependencies() -> void:
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	_inventory = get_tree().get_first_node_in_group("inventory_manager") as InventoryManager
	if _inventory != null:
		_inventory.inventory_updated.connect(_on_inventory_updated)
	hotbar_slot_changed.emit(selected_slot, get_selected_item_id())


func _on_inventory_updated() -> void:
	hotbar_slot_changed.emit(selected_slot, get_selected_item_id())


func _process(delta: float) -> void:
	_update_raycast_target()
	_process_continuous_mining(delta)
	_process_bow_draw(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Press E to open Player Inventory (with 2x2 Crafting Grid)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			station_opened.emit(0)
			return

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	# Hotbar number keys 1..9 (Slots 0..8)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				select_slot(0)
			KEY_2:
				select_slot(1)
			KEY_3:
				select_slot(2)
			KEY_4:
				select_slot(3)
			KEY_5:
				select_slot(4)
			KEY_6:
				select_slot(5)
			KEY_7:
				select_slot(6)
			KEY_8:
				select_slot(7)
			KEY_9:
				select_slot(8)
			KEY_Q:
				_toss_selected_item()

	# Mouse buttons & scroll wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_left_click_pressed()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				var held_item: int = get_selected_item_id()
				if held_item == InventoryManager.ItemId.BOW:
					var is_creative: bool = _player_body != null and _player_body.is_flying
					var arrow_count: int = _inventory.get_total_count(InventoryManager.ItemId.ARROW) if _inventory != null else 0
					if is_creative or arrow_count > 0:
						is_drawing_bow = true
						bow_draw_time = 0.0
						return
					else:
						loot_notification.emit("No Arrows in inventory!")
						return
				_try_interact_or_place_block()
			else:
				# Right click released: fire bow if drawn
				if is_drawing_bow:
					_fire_bow()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			select_slot(posmod(selected_slot - 1, InventoryManager.HOTBAR_SIZE))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			select_slot(posmod(selected_slot + 1, InventoryManager.HOTBAR_SIZE))


func _process_bow_draw(delta: float) -> void:
	if not is_drawing_bow:
		return
	var held_item: int = get_selected_item_id()
	if held_item != InventoryManager.ItemId.BOW or Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED or not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_fire_bow()
		return
	bow_draw_time = minf(bow_draw_time + delta, 1.0)


func _fire_bow() -> void:
	if not is_drawing_bow:
		return
	is_drawing_bow = false

	var charge: float = clampf(bow_draw_time / 0.8, 0.15, 1.0)
	bow_draw_time = 0.0

	var is_creative: bool = _player_body != null and _player_body.is_flying
	if not is_creative and _inventory != null:
		var has_arrow: bool = _inventory.consume_item_anywhere(InventoryManager.ItemId.ARROW, 1)
		if not has_arrow:
			loot_notification.emit("No Arrows in inventory!")
			return
		if _inventory.damage_hotbar_tool(selected_slot, 1):
			loot_notification.emit("Your Bow broke!")

	var eye_pos: Vector3 = Vector3.ZERO
	var look_dir := Vector3.FORWARD
	if _raycast != null and _raycast.is_inside_tree():
		eye_pos = _raycast.global_position
		look_dir = -_raycast.global_transform.basis.z.normalized()
	elif _player_body != null:
		var p_pos: Vector3 = _player_body.global_position if _player_body.is_inside_tree() else _player_body.position
		eye_pos = p_pos + Vector3(0.0, 1.62, 0.0)
		var p_basis: Basis = _player_body.global_transform.basis if _player_body.is_inside_tree() else _player_body.transform.basis
		look_dir = -p_basis.z.normalized()

	var launch_vel: Vector3 = look_dir * lerpf(14.0, 34.0, charge)
	var spawn_pos: Vector3 = eye_pos + look_dir * 0.5
	var parent_node: Node = _world_manager if _world_manager != null else self

	ArrowProjectileClass.spawn_arrow(parent_node, spawn_pos, launch_vel, charge, _player_body)

	var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if is_inside_tree() else null
	if sfx != null and sfx.has_method("play_sfx_at_pos"):
		sfx.play_sfx_at_pos("bow_shoot", eye_pos, 0.0)

	mob_interacted.emit(false, 0)


func select_slot(slot_index: int) -> void:
	if is_drawing_bow:
		is_drawing_bow = false
		bow_draw_time = 0.0
	if slot_index < 0 or slot_index >= InventoryManager.HOTBAR_SIZE:
		return
	selected_slot = slot_index
	hotbar_slot_changed.emit(selected_slot, get_selected_item_id())


func get_selected_item_id() -> int:
	if _inventory == null:
		return 0
	var slot_data: Dictionary = _inventory.get_hotbar_slot(selected_slot)
	return int(slot_data.get("id", 0))


func get_selected_block_id() -> int:
	return get_selected_item_id()


func get_targeted_block_pos() -> Vector3i:
	return target_block_pos


func _update_raycast_target() -> void:
	if _raycast == null:
		return

	if _raycast.is_inside_tree():
		_raycast.force_raycast_update()

	# 1. Check if looking directly at a mob
	if _raycast.is_inside_tree() and _raycast.is_colliding():
		var collider: Object = _raycast.get_collider()
		if collider is PassiveMob:
			_targeted_mob = collider as PassiveMob
			has_target = false
			_reset_mining_progress()
			if _selection_box != null:
				_selection_box.visible = false
			return
	_targeted_mob = null

	var ray_origin: Vector3 = Vector3.ZERO
	var ray_dir := Vector3.FORWARD
	if _raycast.is_inside_tree():
		ray_origin = _raycast.global_position
		ray_dir = -_raycast.global_transform.basis.z.normalized()
	elif _player_body != null:
		ray_origin = _player_body.position + Vector3(0.0, 1.62, 0.0)
		ray_dir = -_raycast.transform.basis.z.normalized() if not _raycast.transform.basis.z.is_zero_approx() else Vector3(0.0, -0.2, 1.0).normalized()

	var solid_hit: bool = _raycast.is_colliding() if _raycast.is_inside_tree() else false
	var hit_dist: float = 5.2
	var solid_target_pos := Vector3i.ZERO
	var solid_place_pos := Vector3i.ZERO

	if solid_hit:
		var hit_point: Vector3 = _raycast.get_collision_point()
		_last_hit_point = hit_point
		var hit_normal: Vector3 = _raycast.get_collision_normal()
		hit_dist = ray_origin.distance_to(hit_point)

		var inside_pos: Vector3 = hit_point - hit_normal * 0.02
		var outside_pos: Vector3 = hit_point + hit_normal * 0.02
		solid_target_pos = Vector3i(floori(inside_pos.x), floori(inside_pos.y), floori(inside_pos.z))
		solid_place_pos = Vector3i(floori(outside_pos.x), floori(outside_pos.y), floori(outside_pos.z))

	# 2. Ray-march through voxels from eye position up to solid hit distance (or 5.2m)
	# to check for passable blocks (Crops, Sprouts, Torches, Sugar Cane, Seagrass)
	var found_passable: bool = false
	var passable_pos := Vector3i.ZERO
	var passable_place := Vector3i.ZERO
	if _world_manager != null:
		var step_dist: float = 0.35
		var max_search_dist: float = minf(hit_dist, 5.2)
		var prev_cell := Vector3i(floori(ray_origin.x), floori(ray_origin.y), floori(ray_origin.z))
		while step_dist < max_search_dist:
			var sample_p: Vector3 = ray_origin + ray_dir * step_dist
			var vpos := Vector3i(floori(sample_p.x), floori(sample_p.y), floori(sample_p.z))
			var bid: int = _world_manager.get_block_world(vpos)
			if BlockRegistry.is_passable_block(bid) and bid != BlockRegistry.BlockId.AIR and not BlockRegistry.is_liquid(bid):
				found_passable = true
				passable_pos = vpos
				passable_place = prev_cell
				_last_hit_point = sample_p
				break
			prev_cell = vpos
			step_dist += 0.08

	if found_passable:
		target_block_pos = passable_pos
		# Placing while aiming at a plant or torch puts the block beside it, not on top of it.
		place_block_pos = passable_place
		has_target = true
	elif solid_hit:
		target_block_pos = solid_target_pos
		place_block_pos = solid_place_pos
		has_target = true
	else:
		has_target = false
		_reset_mining_progress()
		if _selection_box != null:
			_selection_box.visible = false
		return

	if target_block_pos != _last_mining_pos:
		_reset_mining_progress()
		_last_mining_pos = target_block_pos

	if _selection_box != null:
		_selection_box.visible = true
		# Outline the block's real shape (door panel, slab, plant...), not always a full cube.
		var sel_id: int = _world_manager.get_block_world(target_block_pos) if _world_manager != null else BlockRegistry.BlockId.STONE
		var sel_meta: int = _world_manager.get_metadata_world(target_block_pos) if _world_manager != null else 0
		var sel: AABB = BlockRegistry.get_selection_box(sel_id, sel_meta)
		_selection_box.scale = sel.size
		if _selection_box.is_inside_tree():
			_selection_box.global_position = Vector3(target_block_pos) + sel.position
			_selection_box.global_rotation = Vector3.ZERO
			_selection_box.scale = sel.size
		else:
			_selection_box.position = Vector3(target_block_pos) + sel.position


func _on_left_click_pressed() -> void:
	if _targeted_mob != null and is_instance_valid(_targeted_mob):
		var attacker_pos: Vector3 = _player_body.global_position if _player_body != null else global_position
		var equipped_id: int = get_selected_item_id()
		var atk_dmg: int = InventoryManager.get_attack_damage(equipped_id)
		_targeted_mob.on_hit_by_player(attacker_pos, atk_dmg)
		if _inventory != null and (_player_body == null or not _player_body.is_flying) and InventoryManager.get_max_durability(equipped_id) > 0:
			if _inventory.damage_hotbar_tool(selected_slot, 1):
				loot_notification.emit("Your %s broke!" % InventoryManager.get_item_name(equipped_id))
		mob_interacted.emit(true, int(_targeted_mob.variant))
		return

	# Swing hand immediately on click
	mob_interacted.emit(false, 0)

	# In Creative Fly mode, left click breaks immediately
	if _player_body != null and _player_body.is_flying:
		_complete_break_block()


## Breaks blocks while the attack button is held. Break time follows the classic rules
## (InventoryManager.get_break_ticks): hardness, tool type and tier, underwater and airborne
## penalties. After a block breaks there is a 5-tick (0.25 s) pause before the next one starts.
func _process_continuous_mining(delta: float) -> void:
	if _break_cooldown > 0.0:
		_break_cooldown = maxf(0.0, _break_cooldown - delta)
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		_reset_mining_progress()
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not has_target or _world_manager == null:
		_reset_mining_progress()
		return
	if _player_body != null and _player_body.is_flying:
		return

	var target_id: int = _world_manager.get_block_world(target_block_pos)
	if target_id == BlockRegistry.BlockId.AIR or BlockRegistry.is_liquid(target_id):
		_reset_mining_progress()
		return

	var equipped_id: int = get_selected_item_id()
	if equipped_id != _mining_item_id:
		# Switching items restarts the break, like the classic game.
		_reset_mining_progress()
		_mining_item_id = equipped_id
	var meta: int = _world_manager.get_metadata_world(target_block_pos)
	var can_harvest: bool = InventoryManager.can_harvest_block(equipped_id, target_id, meta)
	var in_water: bool = _player_body != null and _player_body.is_head_underwater
	var on_ground: bool = _player_body == null or _player_body.is_on_floor() or _player_body.is_in_water
	var ticks: int = InventoryManager.get_break_ticks(equipped_id, target_id, meta, in_water, on_ground)
	if ticks < 0:
		_reset_mining_progress()
		return
	if ticks == 0:
		# Instant-break blocks (plants, torches...) go on the first tick, with no extra delay.
		_complete_break_block()
		_reset_mining_progress()
		return
	if _break_cooldown > 0.0:
		return
	var break_duration: float = float(ticks) / 20.0

	mining_progress += delta / break_duration
	_swing_repeat_timer -= delta
	if _swing_repeat_timer <= 0.0:
		_swing_repeat_timer = 0.22
		mob_interacted.emit(false, 0)

	if _selection_mat != null:
		var pulse_col: Color = Color(1.0, 0.78, 0.15) if can_harvest else Color(0.95, 0.22, 0.20)
		_selection_mat.albedo_color = Color(0.08, 0.08, 0.08).lerp(pulse_col, clampf(mining_progress, 0.0, 1.0))

	if _crack_box != null and not _crack_textures.is_empty():
		var stage_idx: int = clampi(int(mining_progress * 10.0), 0, 9)
		_crack_mat.albedo_texture = _crack_textures[stage_idx]
		_crack_box.global_position = Vector3(target_block_pos) + Vector3(0.5, 0.5, 0.5)
		_crack_box.global_rotation = Vector3.ZERO
		_crack_box.visible = true

	mining_progress_changed.emit(
		clampf(mining_progress, 0.0, 1.0),
		BlockRegistry.get_block_name(target_id),
		can_harvest
	)

	if mining_progress >= 1.0:
		_complete_break_block()
		_reset_mining_progress()
		_break_cooldown = BREAK_DELAY


func _reset_mining_progress() -> void:
	if _crack_box != null:
		_crack_box.visible = false
	if mining_progress > 0.0:
		mining_progress = 0.0
		if _selection_mat != null:
			_selection_mat.albedo_color = Color(0.08, 0.08, 0.08, 1.0)
		mining_progress_changed.emit(0.0, "", true)


func _complete_break_block() -> void:
	if not has_target or _world_manager == null:
		return
	var previous_id: int = _world_manager.get_block_world(target_block_pos)
	if previous_id == BlockRegistry.BlockId.AIR:
		return
	var broken_pos: Vector3i = target_block_pos
	var equipped_id: int = get_selected_item_id()
	var is_creative: bool = _player_body != null and _player_body.is_flying

	# A door is two blocks: find the other half before anything changes.
	var door_partner := Vector3i(0, -9999, 0)
	if BlockRegistry.is_door(previous_id):
		var below := broken_pos + Vector3i(0, -1, 0)
		var above := broken_pos + Vector3i(0, 1, 0)
		if BlockRegistry.is_door(_world_manager.get_block_world(below)):
			door_partner = below
		elif BlockRegistry.is_door(_world_manager.get_block_world(above)):
			door_partner = above

	if not _world_manager.set_block_world(broken_pos, BlockRegistry.BlockId.AIR):
		return

	if previous_id == BlockRegistry.BlockId.CHEST and _inventory != null:
		_inventory.drop_chest_contents_at(_world_manager, broken_pos)
	elif previous_id == BlockRegistry.BlockId.FURNACE and _inventory != null:
		_inventory.drop_furnace_contents_at(_world_manager, broken_pos)
	if door_partner.y != -9999 and BlockRegistry.is_door(_world_manager.get_block_world(door_partner)):
		_world_manager.set_block_world(door_partner, BlockRegistry.BlockId.AIR)
	# Clean up partner bed block if breaking foot or head of bed
	elif previous_id == BlockRegistry.BlockId.BED or previous_id == BlockRegistry.BlockId.BED_HEAD:
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var adj: Vector3i = broken_pos + d
			var adj_id: int = _world_manager.get_block_world(adj)
			if adj_id == BlockRegistry.BlockId.BED or adj_id == BlockRegistry.BlockId.BED_HEAD:
				_world_manager.set_block_world(adj, BlockRegistry.BlockId.AIR)
		if _player_body != null and _player_body.has_custom_respawn:
			var b_int := Vector3i(floori(_player_body.custom_respawn_pos.x), floori(_player_body.custom_respawn_pos.y), floori(_player_body.custom_respawn_pos.z))
			if b_int == broken_pos or (absi(b_int.x - broken_pos.x) + absi(b_int.z - broken_pos.z) <= 1 and b_int.y == broken_pos.y):
				_player_body.has_custom_respawn = false
				_player_body.custom_respawn_pos = Vector3.ZERO
				loot_notification.emit("Bed broken! Respawn point removed.")

	# Broken ice leaves water behind unless there is nothing underneath it.
	if previous_id == BlockRegistry.BlockId.ICE and not is_creative:
		if _world_manager.get_block_world(broken_pos + Vector3i(0, -1, 0)) != BlockRegistry.BlockId.AIR:
			_world_manager.set_block_world(broken_pos, BlockRegistry.BlockId.WATER)

	var effective_tool: int = InventoryManager.ItemId.DIAMOND_PICKAXE if is_creative else equipped_id
	var drops: Array = InventoryManager.get_block_drops(previous_id, effective_tool)
	for drop in drops:
		DroppedItem.spawn_drop(_world_manager, Vector3(broken_pos) + Vector3(0.5, 0.38, 0.5), int(drop[0]), int(drop[1]))
	if drops.is_empty() and BlockRegistry.get_required_harvest_level(previous_id) >= 0 and not InventoryManager.can_harvest_block(equipped_id, previous_id):
		loot_notification.emit("Broken! (Requires proper Pickaxe tier to harvest)")
	elif previous_id == BlockRegistry.BlockId.WHEAT_CROPS:
		loot_notification.emit("Harvested Wheat & Seeds!")
	elif previous_id == BlockRegistry.BlockId.POTATO_CROPS:
		loot_notification.emit("Harvested Potatoes!")

	# Tools wear by 1 per block that takes time to break (swords by 2); instant blocks are free.
	if not is_creative and _inventory != null and InventoryManager.get_max_durability(equipped_id) > 0:
		if BlockRegistry.get_block_hardness(previous_id) > 0.0:
			var wear: int = 2 if InventoryManager.get_tool_category(equipped_id) == InventoryManager.ToolCategory.SWORD else 1
			if _inventory.damage_hotbar_tool(selected_slot, wear):
				loot_notification.emit("Your %s broke!" % InventoryManager.get_item_name(equipped_id))

	block_broken.emit(broken_pos, previous_id)
	_update_raycast_target()


func _toss_selected_item() -> void:
	if _inventory == null or _world_manager == null:
		return
	var popped: Dictionary = _inventory.pop_one_from_hotbar_for_drop(selected_slot)
	var item_id: int = int(popped.get("id", 0))
	if item_id <= 0:
		return
	var drop_origin: Vector3 = global_position + Vector3(0.0, 1.25, 0.0)
	var throw_dir := Vector3(0.0, 0.2, -1.0)
	if _raycast != null:
		drop_origin = _raycast.global_position - _raycast.global_transform.basis.z.normalized() * 0.35
		throw_dir = -_raycast.global_transform.basis.z.normalized()

	var throw_vel: Vector3 = throw_dir * 5.8 + Vector3(0.0, 1.85, 0.0)
	DroppedItem.spawn_drop(
		_world_manager,
		drop_origin,
		item_id,
		1,
		throw_vel,
		1.35,
		int(popped.get("durability", -1))
	)
	mob_interacted.emit(false, 0)


func _try_interact_or_place_block() -> void:
	var selected_item: int = get_selected_item_id()
	var is_creative: bool = _player_body != null and _player_body.is_flying

	if _targeted_mob != null and is_instance_valid(_targeted_mob):
		if _targeted_mob.has_method("on_interact_with_item"):
			var handled: bool = _targeted_mob.on_interact_with_item(_player_body, selected_item)
			if handled:
				if selected_item == InventoryManager.ItemId.SHEARS and _inventory != null and not is_creative:
					_inventory.damage_hotbar_tool(selected_slot, 1)
				elif selected_item == InventoryManager.ItemId.BUCKET and _targeted_mob.variant == PassiveMob.MobVariant.COW and _inventory != null:
					if not is_creative:
						_inventory.consume_from_hotbar_slot(selected_slot, 1)
						_inventory.add_item(InventoryManager.ItemId.MILK_BUCKET, 1)
					loot_notification.emit("Milked Cow (Milk Bucket)")
				elif (selected_item == InventoryManager.ItemId.WHEAT or selected_item == InventoryManager.ItemId.POTATO) and _inventory != null and not is_creative:
					_inventory.consume_from_hotbar_slot(selected_slot, 1)
				mob_interacted.emit(false, int(_targeted_mob.variant))
				return
		var feeder_pos: Vector3 = _player_body.global_position if _player_body != null else global_position
		_targeted_mob.on_fed_by_player(feeder_pos)
		mob_interacted.emit(false, int(_targeted_mob.variant))
		return

	if _world_manager == null:
		return

	# Eating Food Item on Right-Click (unless aiming at Farmland to plant crops)
	var is_planting_on_farmland: bool = (
		has_target
		and _world_manager != null
		and _world_manager.get_block_world(target_block_pos) == BlockRegistry.BlockId.FARMLAND
		and (selected_item == InventoryManager.ItemId.POTATO or selected_item == InventoryManager.ItemId.WHEAT_SEEDS)
	)
	if not is_planting_on_farmland and InventoryManager.is_food_item(selected_item) and _player_body != null and _inventory != null:
		if selected_item == InventoryManager.ItemId.MILK_BUCKET:
			_inventory.consume_from_hotbar_slot(selected_slot, 1)
			_inventory.add_item(InventoryManager.ItemId.BUCKET, 1)
			_player_body.heal_damage(2)
			loot_notification.emit("Drank Milk Bucket")
			var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if is_inside_tree() and get_tree() != null else null
			if sfx != null and sfx.has_method("play_sfx"):
				sfx.play_sfx("eat", -2.0)
			mob_interacted.emit(false, 0)
			return

		var nutrition: int = InventoryManager.get_food_nutrition(selected_item)
		if _player_body.eat_food(nutrition):
			_inventory.consume_from_hotbar_slot(selected_slot, 1)
			loot_notification.emit("Ate %s (+%d Hunger)" % [InventoryManager.get_item_name(selected_item), nutrition])
			var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if is_inside_tree() and get_tree() != null else null
			if sfx != null and sfx.has_method("play_sfx"):
				sfx.play_sfx("eat", -2.0)
			mob_interacted.emit(false, 0)
		else:
			loot_notification.emit("Hunger & Health are already full!")
		return

	# Equipping Armor Piece directly from hotbar on Right-Click
	if InventoryManager.is_armor_item(selected_item) and _inventory != null:
		var is_station: bool = false
		if has_target:
			var t_id: int = _world_manager.get_block_world(target_block_pos)
			if BlockRegistry.is_interactive_station(t_id) or t_id == BlockRegistry.BlockId.BED or t_id == BlockRegistry.BlockId.BED_HEAD or t_id == BlockRegistry.BlockId.DOOR_CLOSED or t_id == BlockRegistry.BlockId.DOOR_OPEN:
				is_station = true
		if not is_station:
			var slot_type: int = InventoryManager.get_armor_slot_type(selected_item)
			if slot_type >= 0:
				var current_item: Dictionary = _inventory.slots[selected_slot].duplicate(true)
				var prev_armor: Dictionary = _inventory.equip_armor_piece(slot_type, current_item)
				_inventory.slots[selected_slot] = prev_armor
				_inventory.inventory_updated.emit()
				mob_interacted.emit(false, 0)
				loot_notification.emit("Equipped %s!" % InventoryManager.get_item_name(selected_item))
				return

	# Empty Bucket: Ray-step along look direction to scoop up a Water or Lava Source block
	if selected_item == InventoryManager.ItemId.BUCKET and _raycast != null:
		var ray_origin: Vector3 = _raycast.global_position
		var ray_dir: Vector3 = -_raycast.global_transform.basis.z.normalized()
		for step in range(2, 24):
			var sample_p: Vector3 = ray_origin + ray_dir * (float(step) * 0.2)
			var bpos := Vector3i(floori(sample_p.x), floori(sample_p.y), floori(sample_p.z))
			var bid: int = _world_manager.get_block_world(bpos)
			if bid == BlockRegistry.BlockId.WATER:
				if _world_manager.set_block_world(bpos, BlockRegistry.BlockId.AIR):
					if _inventory != null:
						_inventory.convert_hotbar_bucket(selected_slot, InventoryManager.ItemId.WATER_BUCKET)
					loot_notification.emit("Scooped up Water Source!")
					block_placed.emit(bpos, BlockRegistry.BlockId.WATER)
				return
			elif bid == BlockRegistry.BlockId.LAVA:
				if _world_manager.set_block_world(bpos, BlockRegistry.BlockId.AIR):
					if _inventory != null:
						_inventory.convert_hotbar_bucket(selected_slot, InventoryManager.ItemId.LAVA_BUCKET)
					loot_notification.emit("Scooped up Lava Source!")
					block_placed.emit(bpos, BlockRegistry.BlockId.LAVA)
				return
			elif BlockRegistry.is_solid(bid):
				break

	if not has_target:
		return

	# Right-clicking a placed Crafting Table (16) opens the 3x3 Crafting Table UI;
	# Right-clicking a placed Furnace (17) opens the Furnace Oven UI!
	var targeted_id: int = _world_manager.get_block_world(target_block_pos)
	if BlockRegistry.is_interactive_station(targeted_id):
		if targeted_id == BlockRegistry.BlockId.CHEST and _inventory != null:
			_inventory.open_chest_at(target_block_pos)
		elif targeted_id == BlockRegistry.BlockId.FURNACE and _inventory != null:
			_inventory.open_furnace_at(target_block_pos)
		station_opened.emit(targeted_id)
		return

	# Right-clicking a Bed sets respawn point and sleeps through the night to Sunrise!
	if targeted_id == BlockRegistry.BlockId.BED or targeted_id == BlockRegistry.BlockId.BED_HEAD:
		if _player_body != null:
			_player_body.set_respawn_bed_position(Vector3(target_block_pos))

		var monsters_nearby: bool = false
		var tree: SceneTree = get_tree() if is_inside_tree() else (_world_manager.get_tree() if (_world_manager != null and _world_manager.is_inside_tree()) else null)
		var mobs: Array = tree.get_nodes_in_group("mobs") if tree != null else []
		for m in mobs:
			if is_instance_valid(m) and m is PassiveMob:
				var mob_inst := m as PassiveMob
				if mob_inst.is_hostile():
					var m_pos: Vector3 = mob_inst.global_position if mob_inst.is_inside_tree() else mob_inst.position
					if m_pos.distance_to(Vector3(target_block_pos)) <= 8.5:
						monsters_nearby = true
						break
		if monsters_nearby:
			loot_notification.emit("You may not rest now, there are monsters nearby!")
			return

		var dn: DayNightCycle = tree.get_first_node_in_group("day_night_cycle") as DayNightCycle if tree != null else null
		if dn == null and _world_manager != null and _world_manager.get_parent() != null:
			dn = _world_manager.get_parent().get_node_or_null("DayNightCycle") as DayNightCycle
		var is_night: bool = dn != null and dn.is_night_time()
		if is_night:
			dn.advance_to_morning()
			if _player_body != null:
				_player_body.eat_food(6)
				_player_body.current_health = _player_body.max_health
				_player_body.current_hunger = _player_body.max_hunger
				_player_body.health_changed.emit(_player_body.current_health, _player_body.max_health)
				_player_body.hunger_changed.emit(_player_body.current_hunger, _player_body.max_hunger)
			loot_notification.emit("Slept through the night! Good morning & Respawn saved.")
		else:
			loot_notification.emit("Respawn point set at Bed! World saved.")

		# Save world state immediately so bed respawn point is saved to disk
		if _world_manager != null and _world_manager.has_method("save_complete_world"):
			_world_manager.save_complete_world()
		return

	# Right-clicking a mature Wheat crop harvests it and automatically replants a sprout!
	if targeted_id == BlockRegistry.BlockId.WHEAT_CROPS:
		var extra_seeds: int = randi_range(1, 2)
		var added_wheat: bool = false
		if _inventory != null and not is_creative:
			added_wheat = _inventory.add_item(InventoryManager.ItemId.WHEAT, 1)
			_inventory.add_item(InventoryManager.ItemId.WHEAT_SEEDS, extra_seeds)
		if not added_wheat:
			DroppedItem.spawn_drop(_world_manager, Vector3(target_block_pos) + Vector3(0.5, 0.4, 0.5), InventoryManager.ItemId.WHEAT, 1)
			DroppedItem.spawn_drop(_world_manager, Vector3(target_block_pos) + Vector3(0.5, 0.4, 0.5), InventoryManager.ItemId.WHEAT_SEEDS, extra_seeds)
		_world_manager.set_block_world(target_block_pos, BlockRegistry.BlockId.WHEAT_SPROUT)
		loot_notification.emit("Harvested Wheat! (+1 Wheat, +%d Seeds)" % extra_seeds)
		var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if is_inside_tree() else null
		if sfx != null and sfx.has_method("play_sfx_at_pos"):
			sfx.play_sfx_at_pos("place_soft", Vector3(target_block_pos) + Vector3(0.5, 0.5, 0.5), 0.0)
		block_placed.emit(target_block_pos, BlockRegistry.BlockId.WHEAT_SPROUT)
		_update_raycast_target()
		return

	# Right-clicking a mature Potato crop harvests potatoes and replants a sprout!
	if targeted_id == BlockRegistry.BlockId.POTATO_CROPS:
		var pot_count: int = randi_range(2, 3)
		var added_pot: bool = false
		if _inventory != null and not is_creative:
			added_pot = _inventory.add_item(InventoryManager.ItemId.POTATO, pot_count)
		if not added_pot:
			DroppedItem.spawn_drop(_world_manager, Vector3(target_block_pos) + Vector3(0.5, 0.4, 0.5), InventoryManager.ItemId.POTATO, pot_count)
		_world_manager.set_block_world(target_block_pos, BlockRegistry.BlockId.POTATO_SPROUT)
		loot_notification.emit("Harvested Potatoes! (+%d Potatoes)" % pot_count)
		var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if is_inside_tree() else null
		if sfx != null and sfx.has_method("play_sfx_at_pos"):
			sfx.play_sfx_at_pos("place_soft", Vector3(target_block_pos) + Vector3(0.5, 0.5, 0.5), 0.0)
		block_placed.emit(target_block_pos, BlockRegistry.BlockId.POTATO_SPROUT)
		_update_raycast_target()
		return

	# Right-clicking a young Sprout with Seeds or Stick fertilizes it to full maturity!
	if targeted_id == BlockRegistry.BlockId.WHEAT_SPROUT or targeted_id == BlockRegistry.BlockId.POTATO_SPROUT:
		if selected_item == InventoryManager.ItemId.WHEAT_SEEDS or selected_item == InventoryManager.ItemId.STICK:
			var mature_id: int = BlockRegistry.BlockId.WHEAT_CROPS if targeted_id == BlockRegistry.BlockId.WHEAT_SPROUT else BlockRegistry.BlockId.POTATO_CROPS
			_world_manager.set_block_world(target_block_pos, mature_id)
			if not is_creative and _inventory != null and selected_item == InventoryManager.ItemId.WHEAT_SEEDS:
				_inventory.consume_from_hotbar_slot(selected_slot, 1)
			loot_notification.emit("Fertilized crop to full maturity!")
			var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if is_inside_tree() and get_tree() != null else null if is_inside_tree() else null
			if sfx != null and sfx.has_method("play_sfx_at_pos"):
				sfx.play_sfx_at_pos("place_soft", Vector3(target_block_pos) + Vector3(0.5, 0.5, 0.5), 0.0)
			block_placed.emit(target_block_pos, mature_id)
			_update_raycast_target()
			return

	# Right-clicking Grass or Dirt with a Shovel or Stick tills it into Farmland
	var is_hoe_or_shovel: bool = (
		InventoryManager.get_tool_category(selected_item) == InventoryManager.ToolCategory.SHOVEL
		or selected_item == InventoryManager.ItemId.STICK
	)
	if is_hoe_or_shovel and (targeted_id == BlockRegistry.BlockId.GRASS or targeted_id == BlockRegistry.BlockId.DIRT):
		if _world_manager.set_block_world(target_block_pos, BlockRegistry.BlockId.FARMLAND):
			if not is_creative and _inventory != null and InventoryManager.get_max_durability(selected_item) > 0:
				_inventory.damage_hotbar_tool(selected_slot, 1)
			loot_notification.emit("Tilled soil into Farmland!")
			block_placed.emit(target_block_pos, BlockRegistry.BlockId.FARMLAND)
			_update_raycast_target()
		return

	# Right-clicking Farmland with Wheat Seeds or Potato plants crops above
	if targeted_id == BlockRegistry.BlockId.FARMLAND:
		var above_crop_pos: Vector3i = target_block_pos + Vector3i(0, 1, 0)
		var above_id: int = _world_manager.get_block_world(above_crop_pos)
		if above_id == BlockRegistry.BlockId.AIR:
			if selected_item == InventoryManager.ItemId.WHEAT_SEEDS:
				if _world_manager.set_block_world(above_crop_pos, BlockRegistry.BlockId.WHEAT_SPROUT):
					if not is_creative and _inventory != null:
						_inventory.consume_from_hotbar_slot(selected_slot, 1)
					loot_notification.emit("Planted Wheat Sprout!")
					block_placed.emit(above_crop_pos, BlockRegistry.BlockId.WHEAT_SPROUT)
					_update_raycast_target()
				return
			elif selected_item == InventoryManager.ItemId.POTATO:
				if _world_manager.set_block_world(above_crop_pos, BlockRegistry.BlockId.POTATO_SPROUT):
					if not is_creative and _inventory != null:
						_inventory.consume_from_hotbar_slot(selected_slot, 1)
					loot_notification.emit("Planted Potato Sprout!")
					block_placed.emit(above_crop_pos, BlockRegistry.BlockId.POTATO_SPROUT)
					_update_raycast_target()
				return

	# Right-clicking a Wooden Door swings both halves open/closed around the hinge (sneaking is not
	# required: doors never take a block placement).
	if BlockRegistry.is_door(targeted_id):
		var next_door: int = BlockRegistry.BlockId.DOOR_OPEN if targeted_id == BlockRegistry.BlockId.DOOR_CLOSED else BlockRegistry.BlockId.DOOR_CLOSED
		var lower: Vector3i = target_block_pos
		if BlockRegistry.is_door(_world_manager.get_block_world(target_block_pos + Vector3i(0, -1, 0))):
			lower = target_block_pos + Vector3i(0, -1, 0)
		var upper: Vector3i = lower + Vector3i(0, 1, 0)
		var door_meta: int = _world_manager.get_metadata_world(lower)
		_world_manager.set_block_world(lower, next_door, 2, door_meta)
		if BlockRegistry.is_door(_world_manager.get_block_world(upper)):
			_world_manager.set_block_world(upper, next_door, 2, door_meta)
		var sfx: Node = get_tree().get_first_node_in_group("sfx_player") if is_inside_tree() and get_tree() != null else null
		if sfx != null and sfx.has_method("play_sfx"):
			sfx.play_sfx("door_open" if next_door == BlockRegistry.BlockId.DOOR_OPEN else "door_close", -1.0)
		mob_interacted.emit(false, 0)
		_update_raycast_target()
		return

	# Right-clicking TNT ignites an authentic primed TNT physics entity
	if targeted_id == BlockRegistry.BlockId.TNT:
		if not is_creative and selected_item == InventoryManager.ItemId.FLINT_AND_STEEL and _inventory != null:
			if _inventory.damage_hotbar_tool(selected_slot, 1):
				loot_notification.emit("Your Flint and Steel broke!")
		_world_manager.ignite_tnt_at(target_block_pos)
		loot_notification.emit("TNT Ignited! Stand back!")
		mob_interacted.emit(false, 0)
		return

	# Water Bucket: Pour a new Water Source block at place_block_pos
	if selected_item == InventoryManager.ItemId.WATER_BUCKET:
		if _world_manager.set_block_world(place_block_pos, BlockRegistry.BlockId.WATER):
			if not is_creative and _inventory != null:
				_inventory.convert_hotbar_bucket(selected_slot, InventoryManager.ItemId.BUCKET)
			loot_notification.emit("Placed Water Source!")
			block_placed.emit(place_block_pos, BlockRegistry.BlockId.WATER)
			_update_raycast_target()
		return

	# Lava Bucket: Pour a new Lava Source block at place_block_pos
	if selected_item == InventoryManager.ItemId.LAVA_BUCKET:
		if _world_manager.set_block_world(place_block_pos, BlockRegistry.BlockId.LAVA):
			if not is_creative and _inventory != null:
				_inventory.convert_hotbar_bucket(selected_slot, InventoryManager.ItemId.BUCKET)
			loot_notification.emit("Placed Lava Source!")
			block_placed.emit(place_block_pos, BlockRegistry.BlockId.LAVA)
			_update_raycast_target()
		return

	if not InventoryManager.is_placeable_block(selected_item):
		return
	if not is_creative and _inventory != null:
		var slot_data: Dictionary = _inventory.get_hotbar_slot(selected_slot)
		if int(slot_data.get("count", 0)) <= 0:
			return

	if not _is_replaceable(_world_manager.get_block_world(place_block_pos)):
		return

	# Special placement: Wooden Door (2 blocks tall, needs a solid floor). It faces the way the
	# player looks; the hinge goes on the side with more solid blocks (or opposite a neighboring
	# door, making a double door), falling back to which half of the block was clicked.
	if selected_item == BlockRegistry.BlockId.DOOR_CLOSED:
		var top_door_pos: Vector3i = place_block_pos + Vector3i(0, 1, 0)
		if not _is_replaceable(_world_manager.get_block_world(top_door_pos)):
			loot_notification.emit("Not enough space to place Door!")
			return
		var floor_id: int = _world_manager.get_block_world(place_block_pos + Vector3i(0, -1, 0))
		if not BlockRegistry.is_solid(floor_id) or BlockRegistry.is_door(floor_id):
			return
		var door_meta: int = _compute_door_meta(place_block_pos)
		if _player_body != null:
			var player_pos: Vector3 = _player_body.global_position
			var player_aabb := AABB(player_pos + Vector3(-0.16, 0.05, -0.16), Vector3(0.32, 1.72, 0.32))
			var door_box: AABB = BlockRegistry.get_door_box(door_meta, false)
			if AABB(Vector3(place_block_pos) + door_box.position, door_box.size + Vector3(0, 1, 0)).intersects(player_aabb):
				return
		if _world_manager.set_block_world(place_block_pos, BlockRegistry.BlockId.DOOR_CLOSED, 2, door_meta):
			_world_manager.set_block_world(top_door_pos, BlockRegistry.BlockId.DOOR_CLOSED, 2, door_meta)
			if not is_creative and _inventory != null:
				_inventory.consume_from_hotbar_slot(selected_slot, 1)
			block_placed.emit(place_block_pos, BlockRegistry.BlockId.DOOR_CLOSED)
			loot_notification.emit("Placed Wood Door!")
			_update_raycast_target()
		return

	# Special placement: Bed (2 blocks long: Foot + Head)
	if selected_item == BlockRegistry.BlockId.BED:
		var fwd: Vector3i = _get_player_horizontal_facing()
		var foot_pos: Vector3i = place_block_pos
		var head_pos: Vector3i = place_block_pos + fwd
		var head_blk: int = _world_manager.get_block_world(head_pos)
		if head_blk != BlockRegistry.BlockId.AIR and not BlockRegistry.is_liquid(head_blk):
			var found_valid: bool = false
			for alt_dir in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var alt_head: Vector3i = foot_pos + alt_dir
				var alt_blk: int = _world_manager.get_block_world(alt_head)
				if alt_blk == BlockRegistry.BlockId.AIR or BlockRegistry.is_liquid(alt_blk):
					head_pos = alt_head
					found_valid = true
					break
			if not found_valid:
				loot_notification.emit("Not enough space to place Bed!")
				return
		if _player_body != null:
			var player_pos: Vector3 = _player_body.global_position
			var player_aabb := AABB(player_pos + Vector3(-0.32, 0.05, -0.32), Vector3(0.64, 1.72, 0.64))
			if AABB(Vector3(foot_pos), Vector3.ONE).intersects(player_aabb) or AABB(Vector3(head_pos), Vector3.ONE).intersects(player_aabb):
				return
		if _world_manager.set_block_world(foot_pos, BlockRegistry.BlockId.BED):
			_world_manager.set_block_world(head_pos, BlockRegistry.BlockId.BED_HEAD)
			if not is_creative and _inventory != null:
				_inventory.consume_from_hotbar_slot(selected_slot, 1)
			block_placed.emit(foot_pos, BlockRegistry.BlockId.BED)
			loot_notification.emit("Placed Bed!")
			_update_raycast_target()
		return

	# Prevent placing a solid block directly intersecting the player's body capsule
	if _player_body != null:
		var block_aabb := AABB(Vector3(place_block_pos), Vector3.ONE)
		var player_pos: Vector3 = _player_body.global_position
		var player_aabb := AABB(
			player_pos + Vector3(-0.32, 0.05, -0.32),
			Vector3(0.64, 1.72, 0.64)
		)
		if block_aabb.intersects(player_aabb):
			return

	var placed_pos: Vector3i = place_block_pos
	var placed_meta: int = 0
	if selected_item == BlockRegistry.BlockId.TORCH or selected_item == BlockRegistry.BlockId.REDSTONE_TORCH:
		var normal: Vector3i = place_block_pos - target_block_pos
		if normal == Vector3i(1, 0, 0) and BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(target_block_pos)):
			placed_meta = 1 # West wall
		elif normal == Vector3i(-1, 0, 0) and BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(target_block_pos)):
			placed_meta = 2 # East wall
		elif normal == Vector3i(0, 0, 1) and BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(target_block_pos)):
			placed_meta = 3 # North wall
		elif normal == Vector3i(0, 0, -1) and BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(target_block_pos)):
			placed_meta = 4 # South wall
		elif normal == Vector3i(0, 1, 0) and BlockRegistry.is_solid(_world_manager.get_block_world(target_block_pos)):
			placed_meta = 5 # Floor
		else:
			var below := placed_pos + Vector3i(0, -1, 0)
			if BlockRegistry.is_solid(_world_manager.get_block_world(below)):
				placed_meta = 5
			elif BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(placed_pos + Vector3i(-1, 0, 0))):
				placed_meta = 1
			elif BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(placed_pos + Vector3i(1, 0, 0))):
				placed_meta = 2
			elif BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(placed_pos + Vector3i(0, 0, -1))):
				placed_meta = 3
			elif BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(placed_pos + Vector3i(0, 0, 1))):
				placed_meta = 4
			else:
				return
	elif BlockRegistry.is_log(selected_item):
		# Logs lie along the axis of the face they are placed against.
		var normal: Vector3i = place_block_pos - target_block_pos
		if normal.x != 0:
			placed_meta = 1
		elif normal.z != 0:
			placed_meta = 2
	elif BlockRegistry.is_leaves(selected_item):
		placed_meta = 8 # Player-placed leaves never decay
	elif BlockRegistry.needs_support_below(selected_item) and not _can_place_plant(selected_item, placed_pos):
		return
	if selected_item == BlockRegistry.BlockId.WOOD_STAIRS or selected_item == BlockRegistry.BlockId.COBBLE_STAIRS:
		var facing: Vector3i = _get_player_horizontal_facing()
		if facing == Vector3i(1, 0, 0):
			placed_meta = 0 # East
		elif facing == Vector3i(-1, 0, 0):
			placed_meta = 1 # West
		elif facing == Vector3i(0, 0, 1):
			placed_meta = 2 # South
		elif facing == Vector3i(0, 0, -1):
			placed_meta = 3 # North

	# Special placement: Gravity falling blocks (Sand, Gravel)
	if BlockRegistry.is_gravity_block(selected_item):
		var below_coord := placed_pos + Vector3i(0, -1, 0)
		var below_bid: int = _world_manager.get_block_world(below_coord)
		if below_bid == BlockRegistry.BlockId.AIR or BlockRegistry.is_liquid(below_bid) or BlockRegistry.is_passable_block(below_bid):
			if not is_creative and _inventory != null:
				_inventory.consume_from_hotbar_slot(selected_slot, 1)
			FallingBlockClass.spawn_falling_block(_world_manager, placed_pos, selected_item, placed_meta)
			loot_notification.emit("Placed %s!" % BlockRegistry.get_block_name(selected_item))
			_update_raycast_target()
			return

	if _world_manager.set_block_world(placed_pos, selected_item, 2, placed_meta):
		if not is_creative and _inventory != null:
			_inventory.consume_from_hotbar_slot(selected_slot, 1)
		block_placed.emit(placed_pos, selected_item)
		_update_raycast_target()


## Blocks that a placed block may take the place of.
static func _is_replaceable(block_id: int) -> bool:
	return block_id == BlockRegistry.BlockId.AIR or BlockRegistry.is_liquid(block_id) or block_id == BlockRegistry.BlockId.SEAGRASS


## Placement rules for plants, torches and other blocks that need something underneath.
func _can_place_plant(block_id: int, pos: Vector3i) -> bool:
	var below: int = _world_manager.get_block_world(pos + Vector3i(0, -1, 0))
	match block_id:
		BlockRegistry.BlockId.SUGAR_CANE:
			if not _world_manager.can_sugar_cane_stay(pos):
				loot_notification.emit("Sugar cane needs water right next to the block it stands on")
				return false
			return true
		BlockRegistry.BlockId.CACTUS:
			if below != BlockRegistry.BlockId.SAND and below != BlockRegistry.BlockId.CACTUS:
				return false
			for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				if BlockRegistry.is_solid(_world_manager.get_block_world(pos + d)):
					return false
			return true
		BlockRegistry.BlockId.SAPLING, BlockRegistry.BlockId.PINE_SAPLING, BlockRegistry.BlockId.BIRCH_SAPLING, BlockRegistry.BlockId.DANDELION, BlockRegistry.BlockId.ROSE:
			return below == BlockRegistry.BlockId.GRASS or below == BlockRegistry.BlockId.DIRT or below == BlockRegistry.BlockId.FARMLAND
		BlockRegistry.BlockId.BROWN_MUSHROOM, BlockRegistry.BlockId.RED_MUSHROOM:
			return BlockRegistry.is_opaque_full_cube(below)
		BlockRegistry.BlockId.TORCH, BlockRegistry.BlockId.REDSTONE_TORCH, BlockRegistry.BlockId.LEVER:
			if BlockRegistry.is_solid(below):
				return true
			for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				if BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(pos + d)):
					return true
			return false
		_:
			return BlockRegistry.is_solid(below)


## Door metadata for a new door at `pos`: detects doorways and double doors to align flush with walls;
## hinge side from neighbors (solid blocks / an existing door next to it), else from the clicked half of the block.
func _compute_door_meta(pos: Vector3i) -> int:
	var fwd_dir: Vector3i = _get_player_horizontal_facing()
	var facing: Vector3i = fwd_dir

	# 1. Double door pairing: align facing with neighboring door
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var nb_id: int = _world_manager.get_block_world(pos + d)
		if BlockRegistry.is_door(nb_id):
			var nb_meta: int = _world_manager.get_metadata_world(pos + d)
			var nb_facing: Vector3i = BlockRegistry.door_facing_dir(nb_meta)
			var dot: int = d.x * nb_facing.x + d.z * nb_facing.z
			if dot == 0:
				facing = nb_facing
				var left_dir := Vector3i(facing.z, 0, -facing.x)
				var hinge_on_right: bool = (d != left_dir)
				return BlockRegistry.door_meta_from_dir(facing, hinge_on_right)

	# 2. Doorway jamb detection: automatically span across the doorway frame
	var solid_x_pos: bool = BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(pos + Vector3i(1, 0, 0)))
	var solid_x_neg: bool = BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(pos + Vector3i(-1, 0, 0)))
	var solid_z_pos: bool = BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(pos + Vector3i(0, 0, 1)))
	var solid_z_neg: bool = BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(pos + Vector3i(0, 0, -1)))

	if solid_x_pos and solid_x_neg and not (solid_z_pos and solid_z_neg):
		facing = Vector3i(0, 0, -1) if fwd_dir.z <= 0 else Vector3i(0, 0, 1)
	elif solid_z_pos and solid_z_neg and not (solid_x_pos and solid_x_neg):
		facing = Vector3i(-1, 0, 0) if fwd_dir.x <= 0 else Vector3i(1, 0, 0)

	var left := Vector3i(facing.z, 0, -facing.x)
	var right := -left
	var up := Vector3i(0, 1, 0)
	var score: int = 0
	if BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(pos + left)):
		score -= 1
	if BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(pos + left + up)):
		score -= 1
	if BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(pos + right)):
		score += 1
	if BlockRegistry.is_opaque_full_cube(_world_manager.get_block_world(pos + right + up)):
		score += 1
	var door_left: bool = BlockRegistry.is_door(_world_manager.get_block_world(pos + left))
	var door_right: bool = BlockRegistry.is_door(_world_manager.get_block_world(pos + right))
	var hinge_right: bool
	if (door_left and not door_right) or score > 0:
		hinge_right = true
	elif (door_right and not door_left) or score < 0:
		hinge_right = false
	else:
		# Tie: hinge on the side of the block face the player clicked.
		var local: Vector3 = _last_hit_point - Vector3(pos)
		var along_right: float = local.x * float(right.x) + local.z * float(right.z)
		var offset: float = 1.0 if (right.x + right.z) < 0 else 0.0
		hinge_right = (along_right + offset) > 0.5
	return BlockRegistry.door_meta_from_dir(facing, hinge_right)


func _get_player_horizontal_facing() -> Vector3i:
	var fwd := Vector3.FORWARD
	if _raycast != null:
		fwd = -_raycast.global_transform.basis.z
	elif _player_body != null:
		fwd = -_player_body.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		return Vector3i(0, 0, 1)
	fwd = fwd.normalized()
	if absf(fwd.x) > absf(fwd.z):
		return Vector3i(1, 0, 0) if fwd.x > 0.0 else Vector3i(-1, 0, 0)
	else:
		return Vector3i(0, 0, 1) if fwd.z > 0.0 else Vector3i(0, 0, -1)


func _create_selection_wireframe() -> void:
	_selection_box = MeshInstance3D.new()
	_selection_box.name = "BlockSelectionOutline"
	_selection_box.top_level = true
	_selection_box.visible = false

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)

	var margin: float = 0.004
	var p0 := Vector3(-margin, -margin, -margin)
	var p1 := Vector3(1.0 + margin, 1.0 + margin, 1.0 + margin)

	var corners: Array[Vector3] = [
		Vector3(p0.x, p0.y, p0.z),
		Vector3(p1.x, p0.y, p0.z),
		Vector3(p1.x, p0.y, p1.z),
		Vector3(p0.x, p0.y, p1.z),
		Vector3(p0.x, p1.y, p0.z),
		Vector3(p1.x, p1.y, p0.z),
		Vector3(p1.x, p1.y, p1.z),
		Vector3(p0.x, p1.y, p1.z),
	]
	var edges: Array[int] = [
		0, 1, 1, 2, 2, 3, 3, 0,
		4, 5, 5, 6, 6, 7, 7, 4,
		0, 4, 1, 5, 2, 6, 3, 7,
	]
	for idx in edges:
		st.add_vertex(corners[idx])

	_selection_box.mesh = st.commit()

	_selection_mat = StandardMaterial3D.new()
	_selection_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_mat.albedo_color = Color(0.08, 0.08, 0.08, 1.0)
	_selection_box.material_override = _selection_mat
	add_child(_selection_box)


func _create_crack_overlay_mesh() -> void:
	_crack_textures.clear()
	for stage in range(10):
		var stage_res_path: String = "res://assets/textures/destroy_stages/destroy_stage_%d.png" % stage
		var loaded_img: Image = TexturePack.load_image(stage_res_path)
		if loaded_img != null:
			_crack_textures.append(ImageTexture.create_from_image(loaded_img))
			continue

		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.0, 0.0, 0.0, 0.0))
		var reach: int = 1 + int(ceil(float(stage + 1) * 0.72))
		for i in range(-reach, reach + 1):
			var px1: int = clampi(8 + i, 0, 15)
			var py1: int = clampi(8 + int(round(float(i) * 0.8 + sin(float(i)) * 1.3)), 0, 15)
			img.set_pixel(px1, py1, Color(0.05, 0.05, 0.06, 0.76))

			var px2: int = clampi(8 + i, 0, 15)
			var py2: int = clampi(8 - int(round(float(i) * 0.75 + cos(float(i)) * 1.2)), 0, 15)
			img.set_pixel(px2, py2, Color(0.05, 0.05, 0.06, 0.76))

			if stage >= 3:
				var px3: int = clampi(8 + int(sin(float(i)) * 2.0), 0, 15)
				var py3: int = clampi(8 + i, 0, 15)
				img.set_pixel(px3, py3, Color(0.04, 0.04, 0.05, 0.78))
			if stage >= 6:
				var px4: int = clampi(8 + i, 0, 15)
				var py4: int = clampi(8 + ((i * 3) % 5) - 2, 0, 15)
				img.set_pixel(px4, py4, Color(0.04, 0.04, 0.05, 0.82))
		_crack_textures.append(ImageTexture.create_from_image(img))

	_crack_box = MeshInstance3D.new()
	_crack_box.name = "BlockCrackOverlay"
	_crack_box.top_level = true
	_crack_box.visible = false
	_crack_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.006, 1.006, 1.006)
	_crack_box.mesh = box_mesh

	_crack_mat = StandardMaterial3D.new()
	_crack_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_crack_mat.albedo_texture = _crack_textures[0]
	_crack_mat.uv1_triplanar = true
	_crack_mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	_crack_box.material_override = _crack_mat
	add_child(_crack_box)
