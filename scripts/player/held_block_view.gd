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
var _held_item_root: Node3D = null
var _held_item_mesh: MeshInstance3D = null
var _held_item_mat: StandardMaterial3D = null
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
	_held_item_root.visible = false

	if item_id <= 0:
		_hand_root.visible = true
		return

	if InventoryManager.is_placeable_block(item_id):
		_mesh_instance.visible = true
		_rebuild_held_cube_mesh(item_id)
		return

	# Held Tool, Weapon, Food, Ingot, or Resource Item (Textured with Faithful 64x)
	var icon_tex: Texture2D = InventoryManager.get_item_icon_texture(item_id)
	if icon_tex != null and _held_item_mat != null:
		_held_item_mat.albedo_texture = icon_tex
		_held_item_root.visible = true
	else:
		_mesh_instance.visible = true
		_rebuild_held_cube_mesh(item_id)


func _build_all_viewmodels() -> void:
	# 1. Empty Right Arm/Hand (Classic Minecraft Steve arm textured with Faithful 64x)
	_hand_root = Node3D.new()
	_hand_root.name = "RightArmModel"
	_hand_root.rotation = Vector3(deg_to_rad(52.0), deg_to_rad(18.0), deg_to_rad(-12.0))
	add_child(_hand_root)

	var steve_img: Image = TexturePack.load_image("res://assets/textures/entity/steve.png")
	var steve_mat := StandardMaterial3D.new()
	if steve_img != null:
		steve_mat.albedo_texture = ImageTexture.create_from_image(steve_img)
		steve_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	else:
		steve_mat.albedo_color = Color(0.88, 0.68, 0.54)
	steve_mat.no_depth_test = true
	steve_mat.render_priority = 10

	var forearm := _make_part(Vector3(0.13, 0.26, 0.13), steve_mat, Vector3(0.0, 0.04, 0.0))
	_hand_root.add_child(forearm)

	# 2. 3D Faithful 64x Held Tool / Item (Double-Sided Textured In-Hand Viewmodel)
	_held_item_root = Node3D.new()
	_held_item_root.name = "HeldItemRoot"
	_held_item_root.position = Vector3(0.04, 0.04, 0.02)
	_held_item_root.rotation = Vector3(deg_to_rad(-18.0), deg_to_rad(45.0), deg_to_rad(-24.0))
	add_child(_held_item_root)

	_held_item_mat = StandardMaterial3D.new()
	_held_item_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_held_item_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_held_item_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_held_item_mat.no_depth_test = true
	_held_item_mat.render_priority = 10

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(0.42, 0.42)
	_held_item_mesh = MeshInstance3D.new()
	_held_item_mesh.mesh = quad_mesh
	_held_item_mesh.material_override = _held_item_mat
	_held_item_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_held_item_root.add_child(_held_item_mesh)


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
