class_name FallingBlock
extends Node3D
## Authentic Beta 1.7.3 falling gravity block entity (Sand, Gravel).
## Falls smoothly under gravity, sinks through water, solidifies upon hitting solid ground,
## or shatters into dropped items if landing on non-solid obstacles (Torches, Flowers, Sprouts),
## triggering upward cascading block collapses.

const GRAVITY: float = 19.6
const TERMINAL_VELOCITY: float = 32.0
const WATER_SINK_GRAVITY: float = 7.5
const WATER_TERMINAL_VELOCITY: float = 4.5

var block_id: int = BlockRegistry.BlockId.SAND
var metadata: int = 0
var velocity: Vector3 = Vector3.ZERO
var age: float = 0.0

var _world_manager: WorldManager = null
var _visual_mesh: MeshInstance3D = null


static func spawn_falling_block(
	parent_node: Node,
	world_pos: Vector3i,
	p_block_id: int,
	p_metadata: int = 0,
	initial_velocity: Vector3 = Vector3.ZERO
) -> FallingBlock:
	if parent_node == null:
		return null
	var fb: FallingBlock = (load("res://scripts/entities/falling_block.gd") as GDScript).new()
	fb.block_id = p_block_id
	fb.metadata = p_metadata
	fb.position = Vector3(world_pos) + Vector3(0.5, 0.0, 0.5)
	fb.velocity = initial_velocity
	parent_node.add_child(fb)
	return fb


func _ready() -> void:
	add_to_group("falling_blocks")
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	_build_block_mesh()


func _physics_process(delta: float) -> void:
	age += delta
	if _world_manager == null:
		if get_parent() is WorldManager:
			_world_manager = get_parent() as WorldManager
		elif is_inside_tree() and get_tree() != null:
			_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
		if _world_manager == null:
			global_position += velocity * delta
			return

	var current_pos: Vector3 = global_position if is_inside_tree() else position
	var current_coord := Vector3i(floori(current_pos.x), floori(current_pos.y), floori(current_pos.z))
	var current_block: int = _world_manager.get_block_world(current_coord)
	var in_liquid: bool = BlockRegistry.is_liquid(current_block)

	if in_liquid:
		velocity.y = maxf(velocity.y - WATER_SINK_GRAVITY * delta, -WATER_TERMINAL_VELOCITY)
		velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -TERMINAL_VELOCITY)

	var next_y: float = current_pos.y + velocity.y * delta
	var under_coord := Vector3i(floori(current_pos.x), floori(next_y), floori(current_pos.z))
	var block_under: int = _world_manager.get_block_world(under_coord)

	if BlockRegistry.is_solid(block_under):
		var landing_space := under_coord + Vector3i(0, 1, 0)
		var space_block: int = _world_manager.get_block_world(landing_space)

		if space_block == BlockRegistry.BlockId.AIR or BlockRegistry.is_liquid(space_block):
			# Solidify onto the voxel grid
			_world_manager.set_block_world(landing_space, block_id, 2, metadata)
			_play_landing_sound(landing_space)
			_world_manager.check_falling_block(landing_space + Vector3i(0, 1, 0))
		else:
			# Landed on a non-solid obstacle (Torch, Redstone Torch, Flower, Sprout, Lever) -> drop as item!
			DroppedItem.spawn_drop(
				_world_manager,
				Vector3(landing_space) + Vector3(0.5, 0.35, 0.5),
				block_id,
				1
			)
			_play_landing_sound(landing_space)
			_world_manager.check_falling_block(landing_space + Vector3i(0, 1, 0))

		queue_free()
		return

	if is_inside_tree():
		global_position.y = next_y
		global_position.x += velocity.x * delta
		global_position.z += velocity.z * delta
	else:
		position.y = next_y
		position.x += velocity.x * delta
		position.z += velocity.z * delta

	var end_y: float = global_position.y if is_inside_tree() else position.y
	if end_y < -15.0:
		queue_free()


func _play_landing_sound(pos: Vector3i) -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
	if sfx != null and sfx.has_method("play_sfx_at_pos"):
		var snd_name: String = "step_sand" if block_id == BlockRegistry.BlockId.SAND else "step_gravel"
		sfx.play_sfx_at_pos(snd_name, Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.0)


func _build_block_mesh() -> void:
	_visual_mesh = MeshInstance3D.new()
	_visual_mesh.name = "VisualMesh"

	var shared_mat: Material = VoxelAtlasBuilder.get_shared_voxel_material()
	if shared_mat != null:
		_visual_mesh.material_override = shared_mat
		_visual_mesh.mesh = _build_cube_array_mesh()
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE
		var mat := StandardMaterial3D.new()
		mat.albedo_color = BlockRegistry.get_block_color(block_id, metadata)
		bm.material = mat
		_visual_mesh.mesh = bm
		_visual_mesh.position = Vector3(0.0, 0.5, 0.0)

	add_child(_visual_mesh)


func _build_cube_array_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var faces: Array[int] = [
		BlockRegistry.FaceDir.TOP,
		BlockRegistry.FaceDir.BOTTOM,
		BlockRegistry.FaceDir.EAST,
		BlockRegistry.FaceDir.WEST,
		BlockRegistry.FaceDir.SOUTH,
		BlockRegistry.FaceDir.NORTH,
	]

	var h: float = 0.5
	for face_dir in faces:
		var uv_rect: Rect2 = BlockRegistry.get_tile_uv_rect(block_id, face_dir, metadata)
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
				verts = [Vector3(-h, 1.0, -h), Vector3(h, 1.0, -h), Vector3(h, 1.0, h), Vector3(-h, 1.0, h)]
			BlockRegistry.FaceDir.BOTTOM:
				normal = Vector3.DOWN
				shade = 0.55
				verts = [Vector3(-h, 0.0, h), Vector3(h, 0.0, h), Vector3(h, 0.0, -h), Vector3(-h, 0.0, -h)]
			BlockRegistry.FaceDir.EAST:
				normal = Vector3.RIGHT
				shade = 0.82
				verts = [Vector3(h, 1.0, h), Vector3(h, 1.0, -h), Vector3(h, 0.0, -h), Vector3(h, 0.0, h)]
			BlockRegistry.FaceDir.WEST:
				normal = Vector3.LEFT
				shade = 0.76
				verts = [Vector3(-h, 1.0, -h), Vector3(-h, 1.0, h), Vector3(-h, 0.0, h), Vector3(-h, 0.0, -h)]
			BlockRegistry.FaceDir.SOUTH:
				normal = Vector3.BACK
				shade = 0.90
				verts = [Vector3(-h, 1.0, h), Vector3(h, 1.0, h), Vector3(h, 0.0, h), Vector3(-h, 0.0, h)]
			_:
				normal = Vector3.FORWARD
				shade = 0.72
				verts = [Vector3(h, 1.0, -h), Vector3(-h, 1.0, -h), Vector3(-h, 0.0, -h), Vector3(h, 0.0, -h)]

		var uvs: Array[Vector2] = [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
		var col := Color(shade, shade, shade, 1.0)
		var indices: Array[int] = [0, 1, 2, 0, 2, 3]

		for idx in indices:
			st.set_normal(normal)
			st.set_color(col)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])

	return st.commit()
