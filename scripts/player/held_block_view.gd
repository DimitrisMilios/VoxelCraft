class_name HeldBlockView
extends Node3D
## Renders a 3D miniature block in the player's right hand (first-person viewmodel)
## with walk bobbing, slot-switch equip dip, and block break/place swing animations.

const CUBE_SIZE: float = 0.26
const BASE_POS := Vector3(0.44, -0.34, -0.56)
const BASE_ROT := Vector3(deg_to_rad(12.0), deg_to_rad(-38.0), deg_to_rad(4.0))

var _player: PlayerController = null
var _interactor: BlockInteractor = null
var _mesh_instance: MeshInstance3D = null
var _viewmodel_material: StandardMaterial3D = null

var _bob_time: float = 0.0
var _swing_progress: float = 0.0
var _equip_dip: float = 0.0
var _current_block_id: int = BlockRegistry.BlockId.GRASS


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

	_rebuild_held_cube_mesh(_current_block_id)
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
		_current_block_id = _interactor.get_selected_block_id()
		_rebuild_held_cube_mesh(_current_block_id)


func _process(delta: float) -> void:
	# 1. Walk bobbing
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

	# 2. Equip dip animation when changing hotbar slots
	if _equip_dip > 0.0:
		_equip_dip = maxf(0.0, _equip_dip - delta * 5.0)

	# 3. Swing animation when breaking or placing blocks
	var swing_pos_offset := Vector3.ZERO
	var swing_rot_offset := Vector3.ZERO
	if _swing_progress > 0.0:
		_swing_progress = maxf(0.0, _swing_progress - delta * 4.8)
		var arc: float = sin(_swing_progress * PI)
		swing_pos_offset = Vector3(-0.10 * arc, -0.06 * arc, -0.14 * arc)
		swing_rot_offset = Vector3(deg_to_rad(-52.0 * arc), deg_to_rad(28.0 * arc), deg_to_rad(-18.0 * arc))

	position = BASE_POS + bob_offset + swing_pos_offset + Vector3(0.0, -_equip_dip * 0.16, 0.0)
	rotation = BASE_ROT + swing_rot_offset


func _on_hotbar_slot_changed(_slot_index: int, block_id: int) -> void:
	if block_id != _current_block_id:
		_current_block_id = block_id
		_equip_dip = 1.0
		_rebuild_held_cube_mesh(_current_block_id)


func _on_action_swing(_world_pos: Vector3i, _block_id: int) -> void:
	_swing_progress = 1.0


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
