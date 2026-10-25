class_name BlockInteractor
extends Node3D
## Handles raycast block targeting, wireframe block outline, breaking, placing, and hotbar state.

signal hotbar_slot_changed(slot_index: int, block_id: int)
signal block_broken(world_pos: Vector3i, broken_block_id: int)
signal block_placed(world_pos: Vector3i, placed_block_id: int)

const HOTBAR_BLOCKS: Array[int] = [
	BlockRegistry.BlockId.GRASS,
	BlockRegistry.BlockId.DIRT,
	BlockRegistry.BlockId.STONE,
	BlockRegistry.BlockId.COBBLESTONE,
	BlockRegistry.BlockId.WOOD_LOG,
	BlockRegistry.BlockId.WOOD_PLANKS,
	BlockRegistry.BlockId.LEAVES,
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

var _raycast: RayCast3D = null
var _player_body: CharacterBody3D = null
var _world_manager: WorldManager = null
var _selection_box: MeshInstance3D = null


func _ready() -> void:
	_raycast = get_node_or_null(raycast_path) as RayCast3D
	_player_body = get_node_or_null(player_body_path) as CharacterBody3D
	_create_selection_wireframe()
	call_deferred("_resolve_world_manager")


func _resolve_world_manager() -> void:
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	hotbar_slot_changed.emit(selected_slot, get_selected_block_id())


func _process(_delta: float) -> void:
	_update_raycast_target()


func _unhandled_input(event: InputEvent) -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	# Hotbar number keys 1..8
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
				_try_break_block()
			MOUSE_BUTTON_RIGHT:
				_try_place_block()
			MOUSE_BUTTON_WHEEL_UP:
				select_slot(posmod(selected_slot - 1, HOTBAR_BLOCKS.size()))
			MOUSE_BUTTON_WHEEL_DOWN:
				select_slot(posmod(selected_slot + 1, HOTBAR_BLOCKS.size()))


func select_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= HOTBAR_BLOCKS.size():
		return
	selected_slot = slot_index
	hotbar_slot_changed.emit(selected_slot, get_selected_block_id())


func get_selected_block_id() -> int:
	return HOTBAR_BLOCKS[selected_slot]


func _update_raycast_target() -> void:
	if _raycast == null:
		return

	_raycast.force_raycast_update()
	if not _raycast.is_colliding():
		has_target = false
		if _selection_box != null:
			_selection_box.visible = false
		return

	var hit_point: Vector3 = _raycast.get_collision_point()
	var hit_normal: Vector3 = _raycast.get_collision_normal()

	# Step slightly inward along the surface normal to find the targeted block
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

	has_target = true
	if _selection_box != null:
		_selection_box.visible = true
		_selection_box.global_position = Vector3(target_block_pos)
		_selection_box.global_rotation = Vector3.ZERO


func _try_break_block() -> void:
	if not has_target or _world_manager == null:
		return
	var previous_id: int = _world_manager.get_block_world(target_block_pos)
	if previous_id == BlockRegistry.BlockId.AIR:
		return
	var broken_pos: Vector3i = target_block_pos
	if _world_manager.set_block_world(broken_pos, BlockRegistry.BlockId.AIR):
		block_broken.emit(broken_pos, previous_id)
		_update_raycast_target()


func _try_place_block() -> void:
	if not has_target or _world_manager == null:
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

	var placed_id: int = get_selected_block_id()
	var placed_pos: Vector3i = place_block_pos
	if _world_manager.set_block_world(placed_pos, placed_id):
		block_placed.emit(placed_pos, placed_id)
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

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.08, 0.08, 0.08, 1.0)
	_selection_box.material_override = mat
	add_child(_selection_box)
