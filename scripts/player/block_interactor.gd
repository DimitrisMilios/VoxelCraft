class_name BlockInteractor
extends Node3D
## Handles raycast block targeting, progressive mining with Pickaxe speed multipliers,
## block placement, interactive Crafting Table / Furnace stations, and hotbar slots.

signal hotbar_slot_changed(slot_index: int, item_id: int)
signal block_broken(world_pos: Vector3i, broken_block_id: int)
signal block_placed(world_pos: Vector3i, placed_block_id: int)
signal mob_interacted(is_hit: bool, mob_variant: int)
signal mining_progress_changed(progress: float, target_name: String)
signal station_opened(station_block_id: int)
signal loot_notification(message: String)

var hotbar_items: Array[int] = [
	InventoryManager.ItemId.WOOD_PICKAXE,
	BlockRegistry.BlockId.CRAFTING_TABLE,
	BlockRegistry.BlockId.FURNACE,
	BlockRegistry.BlockId.COBBLESTONE,
	BlockRegistry.BlockId.WOOD_LOG,
	BlockRegistry.BlockId.WOOD_PLANKS,
	BlockRegistry.BlockId.GRASS,
	BlockRegistry.BlockId.SAND,
	BlockRegistry.BlockId.SNOW,
	BlockRegistry.BlockId.GLOWSTONE,
]

@export var raycast_path: NodePath = NodePath("../Head/Camera3D/InteractionRay")
@export var player_body_path: NodePath = NodePath("..")

var selected_slot: int = 0
var has_target: bool = false
var target_block_pos: Vector3i = Vector3i.ZERO
var place_block_pos: Vector3i = Vector3i.ZERO
var mining_progress: float = 0.0

var _raycast: RayCast3D = null
var _player_body: PlayerController = null
var _world_manager: WorldManager = null
var _inventory: InventoryManager = null
var _selection_box: MeshInstance3D = null
var _selection_mat: StandardMaterial3D = null
var _targeted_mob: PassiveMob = null
var _last_mining_pos: Vector3i = Vector3i(999999, 999999, 999999)
var _swing_repeat_timer: float = 0.0


func _ready() -> void:
	_raycast = get_node_or_null(raycast_path) as RayCast3D
	_player_body = get_node_or_null(player_body_path) as PlayerController
	_create_selection_wireframe()
	call_deferred("_resolve_dependencies")


func _resolve_dependencies() -> void:
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	_inventory = get_tree().get_first_node_in_group("inventory_manager") as InventoryManager
	if _inventory != null:
		_inventory.tool_upgraded.connect(_on_tool_upgraded)
	hotbar_slot_changed.emit(selected_slot, get_selected_item_id())


func _on_tool_upgraded(new_tool_id: int) -> void:
	hotbar_items[0] = new_tool_id
	hotbar_slot_changed.emit(selected_slot, get_selected_item_id())


func _process(delta: float) -> void:
	_update_raycast_target()
	_process_continuous_mining(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Open Crafting / Inventory screen with E
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			station_opened.emit(BlockRegistry.BlockId.CRAFTING_TABLE)
			return

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	# Hotbar number keys 1..9, 0
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
			KEY_0:
				select_slot(9)

	# Mouse buttons & scroll wheel
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_on_left_click_pressed()
			MOUSE_BUTTON_RIGHT:
				_try_interact_or_place_block()
			MOUSE_BUTTON_WHEEL_UP:
				select_slot(posmod(selected_slot - 1, hotbar_items.size()))
			MOUSE_BUTTON_WHEEL_DOWN:
				select_slot(posmod(selected_slot + 1, hotbar_items.size()))


func select_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= hotbar_items.size():
		return
	selected_slot = slot_index
	hotbar_slot_changed.emit(selected_slot, get_selected_item_id())


func get_selected_item_id() -> int:
	return hotbar_items[selected_slot]


func get_selected_block_id() -> int:
	return get_selected_item_id()


func _update_raycast_target() -> void:
	if _raycast == null:
		return

	_raycast.force_raycast_update()
	if not _raycast.is_colliding():
		has_target = false
		_targeted_mob = null
		_reset_mining_progress()
		if _selection_box != null:
			_selection_box.visible = false
		return

	var collider: Object = _raycast.get_collider()
	if collider is PassiveMob:
		_targeted_mob = collider as PassiveMob
		has_target = false
		_reset_mining_progress()
		if _selection_box != null:
			_selection_box.visible = false
		return

	_targeted_mob = null
	var hit_point: Vector3 = _raycast.get_collision_point()
	var hit_normal: Vector3 = _raycast.get_collision_normal()

	var inside_pos: Vector3 = hit_point - hit_normal * 0.02
	var outside_pos: Vector3 = hit_point + hit_normal * 0.02

	target_block_pos = Vector3i(
		floori(inside_pos.x),
		floori(inside_pos.y),
		floori(inside_pos.z)
	)
	place_block_pos = Vector3i(
		floori(outside_pos.x),
		floori(outside_pos.y),
		floori(outside_pos.z)
	)

	if target_block_pos != _last_mining_pos:
		_reset_mining_progress()
		_last_mining_pos = target_block_pos

	has_target = true
	if _selection_box != null:
		_selection_box.visible = true
		_selection_box.global_position = Vector3(target_block_pos)
		_selection_box.global_rotation = Vector3.ZERO


func _on_left_click_pressed() -> void:
	if _targeted_mob != null and is_instance_valid(_targeted_mob):
		var attacker_pos: Vector3 = _player_body.global_position if _player_body != null else global_position
		_targeted_mob.on_hit_by_player(attacker_pos)
		mob_interacted.emit(true, int(_targeted_mob.variant))
		return

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
	if target_id == BlockRegistry.BlockId.AIR or target_id == BlockRegistry.BlockId.WATER:
		_reset_mining_progress()
		return

	var hardness: float = BlockRegistry.get_block_hardness(target_id)
	var speed_mult: float = InventoryManager.get_pickaxe_speed_multiplier(get_selected_item_id(), target_id)
	var break_duration: float = maxf(0.12, hardness / speed_mult)

	mining_progress += delta / break_duration
	_swing_repeat_timer -= delta
	if _swing_repeat_timer <= 0.0:
		_swing_repeat_timer = 0.22
		mob_interacted.emit(false, 0)

	if _selection_mat != null:
		_selection_mat.albedo_color = Color(0.08, 0.08, 0.08).lerp(Color(1.0, 0.78, 0.15), clampf(mining_progress, 0.0, 1.0))

	mining_progress_changed.emit(clampf(mining_progress, 0.0, 1.0), BlockRegistry.get_block_name(target_id))

	if mining_progress >= 1.0:
		_complete_break_block()
		_reset_mining_progress()


func _reset_mining_progress() -> void:
	if mining_progress > 0.0:
		mining_progress = 0.0
		if _selection_mat != null:
			_selection_mat.albedo_color = Color(0.08, 0.08, 0.08, 1.0)
		mining_progress_changed.emit(0.0, "")


func _complete_break_block() -> void:
	if not has_target or _world_manager == null:
		return
	var previous_id: int = _world_manager.get_block_world(target_block_pos)
	if previous_id == BlockRegistry.BlockId.AIR:
		return
	var broken_pos: Vector3i = target_block_pos
	if _world_manager.set_block_world(broken_pos, BlockRegistry.BlockId.AIR):
		if _inventory != null:
			var drop_msg: String = _inventory.award_block_drop(previous_id)
			loot_notification.emit(drop_msg)
		block_broken.emit(broken_pos, previous_id)
		_update_raycast_target()


func _try_interact_or_place_block() -> void:
	if _targeted_mob != null and is_instance_valid(_targeted_mob):
		var feeder_pos: Vector3 = _player_body.global_position if _player_body != null else global_position
		_targeted_mob.on_fed_by_player(feeder_pos)
		mob_interacted.emit(false, int(_targeted_mob.variant))
		return

	if not has_target or _world_manager == null:
		return

	# Check if right-clicking a Crafting Table or Furnace (Oven) in the world
	var targeted_id: int = _world_manager.get_block_world(target_block_pos)
	if BlockRegistry.is_interactive_station(targeted_id):
		station_opened.emit(targeted_id)
		return

	var selected_item: int = get_selected_item_id()
	# Pickaxe tools cannot be placed as blocks
	if InventoryManager.is_pickaxe(selected_item):
		return

	# In survival mode, check if the player has at least 1 of this block in inventory
	var is_creative: bool = _player_body != null and _player_body.is_flying
	if not is_creative and _inventory != null:
		if _inventory.get_count(selected_item) <= 0:
			loot_notification.emit("Out of %s!" % BlockRegistry.get_block_name(selected_item))
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
	if _world_manager.set_block_world(placed_pos, selected_item):
		if not is_creative and _inventory != null:
			_inventory.consume_item(selected_item, 1)
		block_placed.emit(placed_pos, selected_item)
		_update_raycast_target()


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
