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
	if _world_manager != null:
		var step_dist: float = 0.35
		var max_search_dist: float = minf(hit_dist, 5.2)
		while step_dist < max_search_dist:
			var sample_p: Vector3 = ray_origin + ray_dir * step_dist
			var vpos := Vector3i(floori(sample_p.x), floori(sample_p.y), floori(sample_p.z))
			var bid: int = _world_manager.get_block_world(vpos)
			if BlockRegistry.is_passable_block(bid) and bid != BlockRegistry.BlockId.AIR and not BlockRegistry.is_liquid(bid):
				found_passable = true
				passable_pos = vpos
				break
			step_dist += 0.08

	if found_passable:
		target_block_pos = passable_pos
		place_block_pos = passable_pos
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
		if _selection_box.is_inside_tree():
			_selection_box.global_position = Vector3(target_block_pos)
			_selection_box.global_rotation = Vector3.ZERO
		else:
			_selection_box.position = Vector3(target_block_pos)


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


func _process_continuous_mining(delta: float) -> void:
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
	var can_harvest: bool = InventoryManager.can_harvest_block(equipped_id, target_id)
	var hardness: float = BlockRegistry.get_block_hardness(target_id)
	var speed_mult: float = InventoryManager.get_mining_speed_multiplier(equipped_id, target_id)
	var break_duration: float = maxf(0.10, hardness / speed_mult)

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

	if _world_manager.set_block_world(broken_pos, BlockRegistry.BlockId.AIR):
		if previous_id == BlockRegistry.BlockId.CHEST and _inventory != null:
			_inventory.drop_chest_contents_at(_world_manager, broken_pos)
		# Clean up partner door block if breaking top or bottom door
		if previous_id == BlockRegistry.BlockId.DOOR_CLOSED or previous_id == BlockRegistry.BlockId.DOOR_OPEN:
			for dy in [-1, 1]:
				var adj: Vector3i = broken_pos + Vector3i(0, dy, 0)
				var adj_id: int = _world_manager.get_block_world(adj)
				if adj_id == BlockRegistry.BlockId.DOOR_CLOSED or adj_id == BlockRegistry.BlockId.DOOR_OPEN:
					_world_manager.set_block_world(adj, BlockRegistry.BlockId.AIR)
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

		var effective_tool: int = InventoryManager.ItemId.DIAMOND_PICKAXE if is_creative else equipped_id
		var drop_id: int = InventoryManager.get_dropped_item_for_block(previous_id, effective_tool)
		if drop_id == BlockRegistry.BlockId.DOOR_OPEN:
			drop_id = BlockRegistry.BlockId.DOOR_CLOSED
		elif drop_id == BlockRegistry.BlockId.BED_HEAD or previous_id == BlockRegistry.BlockId.BED_HEAD:
			drop_id = BlockRegistry.BlockId.BED
		if drop_id > 0:
			DroppedItem.spawn_drop(
				_world_manager,
				Vector3(broken_pos) + Vector3(0.5, 0.38, 0.5),
				drop_id,
				1
			)
			if previous_id == BlockRegistry.BlockId.LEAVES and randf() < 0.25:
				DroppedItem.spawn_drop(
					_world_manager,
					Vector3(broken_pos) + Vector3(0.5, 0.45, 0.5),
					InventoryManager.ItemId.APPLE,
					1
				)
			elif previous_id == BlockRegistry.BlockId.GRASS and randf() < 0.40:
				DroppedItem.spawn_drop(
					_world_manager,
					Vector3(broken_pos) + Vector3(0.5, 0.45, 0.5),
					InventoryManager.ItemId.WHEAT_SEEDS,
					1
				)
				loot_notification.emit("Found Wheat Seeds!")
			elif previous_id == BlockRegistry.BlockId.WHEAT_CROPS:
				DroppedItem.spawn_drop(
					_world_manager,
					Vector3(broken_pos) + Vector3(0.5, 0.45, 0.5),
					InventoryManager.ItemId.WHEAT_SEEDS,
					randi_range(1, 2)
				)
				loot_notification.emit("Harvested Wheat & Seeds!")
			elif previous_id == BlockRegistry.BlockId.WHEAT_SPROUT:
				loot_notification.emit("Harvested Wheat Seeds!")
			elif previous_id == BlockRegistry.BlockId.POTATO_CROPS:
				DroppedItem.spawn_drop(
					_world_manager,
					Vector3(broken_pos) + Vector3(0.5, 0.45, 0.5),
					InventoryManager.ItemId.POTATO,
					randi_range(1, 2)
				)
				loot_notification.emit("Harvested Potatoes!")
		else:
			loot_notification.emit("Broken! (Requires proper Pickaxe tier to harvest)")

		# Apply tool durability wear when mining in Survival mode
		if not is_creative and _inventory != null and InventoryManager.get_max_durability(equipped_id) > 0:
			if _inventory.damage_hotbar_tool(selected_slot, 1):
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

	# Right-clicking a Wooden Door swings it open/closed
	if targeted_id == BlockRegistry.BlockId.DOOR_CLOSED or targeted_id == BlockRegistry.BlockId.DOOR_OPEN:
		var next_door: int = BlockRegistry.BlockId.DOOR_OPEN if targeted_id == BlockRegistry.BlockId.DOOR_CLOSED else BlockRegistry.BlockId.DOOR_CLOSED
		_world_manager.set_block_world(target_block_pos, next_door)
		for dy in [-1, 1]:
			var adj: Vector3i = target_block_pos + Vector3i(0, dy, 0)
			var adj_id: int = _world_manager.get_block_world(adj)
			if adj_id == BlockRegistry.BlockId.DOOR_CLOSED or adj_id == BlockRegistry.BlockId.DOOR_OPEN:
				_world_manager.set_block_world(adj, next_door)
		if next_door == BlockRegistry.BlockId.DOOR_OPEN:
			station_opened.emit(BlockRegistry.BlockId.DOOR_OPEN)
		else:
			station_opened.emit(BlockRegistry.BlockId.DOOR_CLOSED)
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

	# Special placement: Wooden Door (2 blocks tall)
	if selected_item == BlockRegistry.BlockId.DOOR_CLOSED:
		var top_door_pos: Vector3i = place_block_pos + Vector3i(0, 1, 0)
		var top_blk: int = _world_manager.get_block_world(top_door_pos)
		if top_blk != BlockRegistry.BlockId.AIR and not BlockRegistry.is_liquid(top_blk):
			loot_notification.emit("Not enough space to place Door!")
			return
		if _player_body != null:
			var player_pos: Vector3 = _player_body.global_position
			var player_aabb := AABB(player_pos + Vector3(-0.32, 0.05, -0.32), Vector3(0.64, 1.72, 0.64))
			if AABB(Vector3(place_block_pos), Vector3.ONE).intersects(player_aabb) or AABB(Vector3(top_door_pos), Vector3.ONE).intersects(player_aabb):
				return
		if _world_manager.set_block_world(place_block_pos, BlockRegistry.BlockId.DOOR_CLOSED):
			_world_manager.set_block_world(top_door_pos, BlockRegistry.BlockId.DOOR_CLOSED)
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
