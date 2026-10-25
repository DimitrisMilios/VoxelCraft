class_name HeldBlockView
extends Node3D
## Renders the player's first-person right-hand viewmodel:
## - Empty Right Arm/Hand when slot is empty (punching trees!)
## - 3D Voxel Pickaxe, 3D Axe, or 3D Shovel when a tool is equipped
## - 3D Textured Block Cube when holding a placeable block
## - 3D Ingot/Stick/Resource item when holding crafting materials.

const CUBE_SIZE: float = 0.26
const BASE_POS := Vector3(0.44, -0.34, -0.56)
const BASE_ROT := Vector3(deg_to_rad(12.0), deg_to_rad(-38.0), deg_to_rad(4.0))

var _player: PlayerController = null
var _interactor: BlockInteractor = null
var _mesh_instance: MeshInstance3D = null
var _hand_root: Node3D = null
var _pickaxe_root: Node3D = null
var _axe_root: Node3D = null
var _shovel_root: Node3D = null
var _item_bar_mesh: MeshInstance3D = null
var _tool_head_mat: StandardMaterial3D = null
var _item_bar_mat: StandardMaterial3D = null
var _viewmodel_material: StandardMaterial3D = null

var _bob_time: float = 0.0
var _swing_progress: float = 0.0
var _equip_dip: float = 0.0
var _current_item_id: int = -1


func _ready() -> void:
	position = BASE_POS
	rotation = BASE_ROT

	_viewmodel_material = VoxelAtlasBuilder.get_shared_voxel_material().duplicate() as StandardMaterial3D
	_viewmodel_material.no_depth_test = true
	_viewmodel_material.render_priority = 10

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "HeldCubeMesh"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.material_override = _viewmodel_material
	add_child(_mesh_instance)

	_build_all_viewmodels()
	_update_held_visual(0)
	call_deferred("_bind_player")


func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as PlayerController
	if _player == null:
		return
	_interactor = _player.get_node_or_null("BlockInteractor") as BlockInteractor
	if _interactor != null:
		_interactor.hotbar_slot_changed.connect(_on_hotbar_slot_changed)
		_interactor.block_broken.connect(_on_action_swing)
		_interactor.block_placed.connect(_on_action_swing)
		_interactor.mob_interacted.connect(func(_is_hit: bool, _variant: int) -> void: _swing_progress = 1.0)
		_update_held_visual(_interactor.get_selected_item_id())


func _process(delta: float) -> void:
	var horiz_speed: float = 0.0
	if _player != null:
		horiz_speed = Vector2(_player.velocity.x, _player.velocity.z).length()

	if horiz_speed > 0.2 and _player != null and (_player.is_on_floor() or _player.is_in_water):
		_bob_time += delta * clampf(horiz_speed * 1.4, 3.0, 11.0)
	else:
		_bob_time = lerpf(_bob_time, 0.0, 6.0 * delta)

	var bob_offset := Vector3(
		sin(_bob_time) * 0.022,
		absf(cos(_bob_time)) * 0.024,
		0.0
	)

	if _equip_dip > 0.0:
		_equip_dip = maxf(0.0, _equip_dip - delta * 5.0)

	var swing_pos_offset := Vector3.ZERO
	var swing_rot_offset := Vector3.ZERO
	if _swing_progress > 0.0:
		_swing_progress = maxf(0.0, _swing_progress - delta * 4.8)
		var arc: float = sin(_swing_progress * PI)
		swing_pos_offset = Vector3(-0.10 * arc, -0.06 * arc, -0.14 * arc)
		swing_rot_offset = Vector3(deg_to_rad(-58.0 * arc), deg_to_rad(28.0 * arc), deg_to_rad(-18.0 * arc))

	position = BASE_POS + bob_offset + swing_pos_offset + Vector3(0.0, -_equip_dip * 0.16, 0.0)
	rotation = BASE_ROT + swing_rot_offset


func _on_hotbar_slot_changed(_slot_index: int, item_id: int) -> void:
	if item_id != _current_item_id:
		_current_item_id = item_id
		_equip_dip = 1.0
		_update_held_visual(_current_item_id)


func _on_action_swing(_world_pos: Vector3i, _block_id: int) -> void:
	_swing_progress = 1.0


func _update_held_visual(item_id: int) -> void:
	_mesh_instance.visible = false
	_hand_root.visible = false
	_pickaxe_root.visible = false
	_axe_root.visible = false
	_shovel_root.visible = false
	_item_bar_mesh.visible = false

	if item_id <= 0:
		_hand_root.visible = true
		return

	var tool_cat: int = InventoryManager.get_tool_category(item_id)
	if tool_cat != InventoryManager.ToolCategory.NONE:
		_tool_head_mat.albedo_color = InventoryManager.get_item_color(item_id)
		match tool_cat:
			InventoryManager.ToolCategory.PICKAXE:
				_pickaxe_root.visible = true
			InventoryManager.ToolCategory.AXE:
				_axe_root.visible = true
			InventoryManager.ToolCategory.SHOVEL:
				_shovel_root.visible = true
		return

	if InventoryManager.is_placeable_block(item_id):
		_mesh_instance.visible = true
		_rebuild_held_cube_mesh(item_id)
		return

	# Non-block resource item (Stick, Coal, Raw Iron, Ingot, Diamond)
	_item_bar_mat.albedo_color = InventoryManager.get_item_color(item_id)
	_item_bar_mesh.visible = true


func _build_all_viewmodels() -> void:
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.55, 0.38, 0.20)
	handle_mat.no_depth_test = true
	handle_mat.render_priority = 10

	_tool_head_mat = StandardMaterial3D.new()
	_tool_head_mat.albedo_color = Color(0.68, 0.50, 0.28)
	_tool_head_mat.no_depth_test = true
	_tool_head_mat.render_priority = 10

	# 1. Empty Right Arm/Hand (Classic Minecraft blocky arm)
	_hand_root = Node3D.new()
	_hand_root.name = "RightArmModel"
	_hand_root.rotation = Vector3(deg_to_rad(52.0), deg_to_rad(18.0), deg_to_rad(-12.0))
	add_child(_hand_root)

	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.88, 0.68, 0.54)
	skin_mat.no_depth_test = true
	skin_mat.render_priority = 10

	var sleeve_mat := StandardMaterial3D.new()
	sleeve_mat.albedo_color = Color(0.22, 0.56, 0.78)
	sleeve_mat.no_depth_test = true
	sleeve_mat.render_priority = 10

	var forearm := _make_part(Vector3(0.13, 0.26, 0.13), skin_mat, Vector3(0.0, 0.04, 0.0))
	var sleeve := _make_part(Vector3(0.14, 0.16, 0.14), sleeve_mat, Vector3(0.0, -0.14, 0.0))
	_hand_root.add_child(forearm)
	_hand_root.add_child(sleeve)

	# 2. Pickaxe Viewmodel
	_pickaxe_root = Node3D.new()
	_pickaxe_root.name = "PickaxeModel"
	_pickaxe_root.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(35.0), deg_to_rad(-10.0))
	add_child(_pickaxe_root)
	_pickaxe_root.add_child(_make_part(Vector3(0.045, 0.36, 0.045), handle_mat, Vector3.ZERO))
	_pickaxe_root.add_child(_make_part(Vector3(0.28, 0.065, 0.06), _tool_head_mat, Vector3(0.0, 0.14, 0.0)))
	for side in [-1.0, 1.0]:
		_pickaxe_root.add_child(_make_part(Vector3(0.055, 0.075, 0.055), _tool_head_mat, Vector3(side * 0.12, 0.10, 0.0)))

	# 3. Axe Viewmodel
	_axe_root = Node3D.new()
	_axe_root.name = "AxeModel"
	_axe_root.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(35.0), deg_to_rad(-10.0))
	add_child(_axe_root)
	_axe_root.add_child(_make_part(Vector3(0.045, 0.36, 0.045), handle_mat, Vector3.ZERO))
	_axe_root.add_child(_make_part(Vector3(0.16, 0.14, 0.055), _tool_head_mat, Vector3(-0.06, 0.11, 0.0)))
	_axe_root.add_child(_make_part(Vector3(0.06, 0.18, 0.045), _tool_head_mat, Vector3(-0.13, 0.09, 0.0)))

	# 4. Shovel Viewmodel
	_shovel_root = Node3D.new()
	_shovel_root.name = "ShovelModel"
	_shovel_root.rotation = Vector3(deg_to_rad(-15.0), deg_to_rad(35.0), deg_to_rad(-10.0))
	add_child(_shovel_root)
	_shovel_root.add_child(_make_part(Vector3(0.045, 0.34, 0.045), handle_mat, Vector3.ZERO))
	_shovel_root.add_child(_make_part(Vector3(0.13, 0.15, 0.04), _tool_head_mat, Vector3(0.0, 0.18, 0.0)))

	# 5. Held Resource Item (Ingot / Coal / Stick / Diamond)
	_item_bar_mat = StandardMaterial3D.new()
	_item_bar_mat.no_depth_test = true
	_item_bar_mat.render_priority = 10
	_item_bar_mesh = _make_part(Vector3(0.16, 0.16, 0.08), _item_bar_mat, Vector3.ZERO)
	add_child(_item_bar_mesh)


func _make_part(size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mi.mesh = box
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _rebuild_held_cube_mesh(block_id: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var h: float = CUBE_SIZE * 0.5
	var faces: Array[int] = [
		BlockRegistry.FaceDir.TOP,
		BlockRegistry.FaceDir.BOTTOM,
		BlockRegistry.FaceDir.EAST,
		BlockRegistry.FaceDir.WEST,
		BlockRegistry.FaceDir.SOUTH,
		BlockRegistry.FaceDir.NORTH,
	]

	for face_dir in faces:
		_emit_cube_face(st, h, face_dir, block_id)

	_mesh_instance.mesh = st.commit()


func _emit_cube_face(st: SurfaceTool, h: float, face_dir: int, block_id: int) -> void:
	var uv_rect: Rect2 = BlockRegistry.get_tile_uv_rect(block_id, face_dir)
	var u0: float = uv_rect.position.x
	var v0: float = uv_rect.position.y
	var u1: float = uv_rect.position.x + uv_rect.size.x
	var v1: float = uv_rect.position.y + uv_rect.size.y

	var verts: Array[Vector3]
	var normal: Vector3
	var shade: float = 1.0

	match face_dir:
		BlockRegistry.FaceDir.TOP:
			normal = Vector3.UP
			shade = 1.0
			verts = [
				Vector3(-h, h, -h),
				Vector3(h, h, -h),
				Vector3(h, h, h),
				Vector3(-h, h, h),
			]
		BlockRegistry.FaceDir.BOTTOM:
			normal = Vector3.DOWN
			shade = 0.55
			verts = [
				Vector3(-h, -h, h),
				Vector3(h, -h, h),
				Vector3(h, -h, -h),
				Vector3(-h, -h, -h),
			]
		BlockRegistry.FaceDir.EAST:
			normal = Vector3.RIGHT
			shade = 0.82
			verts = [
				Vector3(h, h, h),
				Vector3(h, h, -h),
				Vector3(h, -h, -h),
				Vector3(h, -h, h),
			]
		BlockRegistry.FaceDir.WEST:
			normal = Vector3.LEFT
			shade = 0.76
			verts = [
				Vector3(-h, h, -h),
				Vector3(-h, h, h),
				Vector3(-h, -h, h),
				Vector3(-h, -h, -h),
			]
		BlockRegistry.FaceDir.SOUTH:
			normal = Vector3.BACK
			shade = 0.90
			verts = [
				Vector3(-h, h, h),
				Vector3(h, h, h),
				Vector3(h, -h, h),
				Vector3(-h, -h, h),
			]
		_: # NORTH
			normal = Vector3.FORWARD
			shade = 0.72
			verts = [
				Vector3(h, h, -h),
				Vector3(-h, h, -h),
				Vector3(-h, -h, -h),
				Vector3(h, -h, -h),
			]

	var uvs: Array[Vector2] = [
		Vector2(u0, v0),
		Vector2(u1, v0),
		Vector2(u1, v1),
		Vector2(u0, v1),
	]
	var color := Color(shade, shade, shade, 1.0)
	var indices: Array[int] = [0, 1, 2, 0, 2, 3]
	for idx in indices:
		st.set_normal(normal)
		st.set_color(color)
		st.set_uv(uvs[idx])
		st.add_vertex(verts[idx])
