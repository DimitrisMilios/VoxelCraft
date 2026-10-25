class_name DroppedItem
extends Node3D
## Authentic Minecraft 3D dropped item entity.
## Spins and bobs on the ground, bounces on voxel terrain, floats and drifts in flowing water,
## merges with nearby identical item drops, and flies magnetically into the player's inventory.

const GRAVITY: float = 19.5
const PICKUP_RADIUS: float = 1.95
const COLLECT_DISTANCE: float = 0.68
const MERGE_RADIUS: float = 0.85
const MAX_LIFETIME: float = 300.0
const MINI_CUBE_SIZE: float = 0.26

var item_id: int = 0
var count: int = 1
var durability: int = -1
var velocity: Vector3 = Vector3.ZERO
var pickup_delay: float = 0.42
var age: float = 0.0

var _visual_root: Node3D = null
var _world_manager: WorldManager = null
var _player: PlayerController = null
var _inventory: InventoryManager = null
var _collected: bool = false


static func spawn_drop(
	parent_node: Node,
	world_pos: Vector3,
	p_item_id: int,
	p_count: int = 1,
	initial_velocity: Vector3 = Vector3.ZERO,
	p_pickup_delay: float = 0.42,
	p_durability: int = -1
) -> DroppedItem:
	if p_item_id <= 0 or p_count <= 0 or parent_node == null:
		return null
	var drop := DroppedItem.new()
	drop.item_id = p_item_id
	drop.count = p_count
	drop.durability = p_durability
	drop.pickup_delay = p_pickup_delay
	drop.position = world_pos
	if initial_velocity == Vector3.ZERO:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		drop.velocity = Vector3(
			rng.randf_range(-1.6, 1.6),
			rng.randf_range(2.6, 3.8),
			rng.randf_range(-1.6, 1.6)
		)
	else:
		drop.velocity = initial_velocity
	parent_node.add_child(drop)
	return drop


func _ready() -> void:
	add_to_group("dropped_items")
	_build_visual_mesh()
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	_player = get_tree().get_first_node_in_group("player") as PlayerController
	_inventory = get_tree().get_first_node_in_group("inventory_manager") as InventoryManager


func _physics_process(delta: float) -> void:
	if _collected:
		return

	age += delta
	if age >= MAX_LIFETIME:
		queue_free()
		return

	if _visual_root != null:
		_visual_root.rotate_y(1.85 * delta)
		_visual_root.position.y = 0.16 + sin(age * 3.4) * 0.055

	# Magnetic pull toward player once pickup_delay has elapsed
	if age >= pickup_delay and _player != null and is_instance_valid(_player):
		var target_pos: Vector3 = _player.global_position + Vector3(0.0, 0.75, 0.0)
		var to_player: Vector3 = target_pos - global_position
		var dist: float = to_player.length()
		if dist <= COLLECT_DISTANCE:
			_collect_into_inventory()
			return
		elif dist <= PICKUP_RADIUS:
			var pull_speed: float = lerpf(12.0, 5.5, clampf(dist / PICKUP_RADIUS, 0.0, 1.0))
			global_position += to_player.normalized() * pull_speed * delta
			return

	_simulate_voxel_and_water_physics(delta)

	# Periodically try merging with nearby identical item stacks
	if int(age * 10.0) % 6 == 0 and not InventoryManager.is_tool_item(item_id):
		_try_merge_with_nearby_drops()


func _simulate_voxel_and_water_physics(delta: float) -> void:
	if _world_manager == null:
		global_position += velocity * delta
		return

	var bpos := Vector3i(floori(global_position.x), floori(global_position.y + 0.1), floori(global_position.z))
	var block_at: int = _world_manager.get_block_world(bpos)

	if BlockRegistry.is_liquid(block_at):
		# Float upward in water and drift along flowing water currents!
		var water_surf: float = float(bpos.y) + BlockRegistry.get_water_height_ratio(block_at)
		if global_position.y < water_surf - 0.12:
			velocity.y = move_toward(velocity.y, 1.65, 11.0 * delta)
		else:
			velocity.y = move_toward(velocity.y, 0.0, 8.0 * delta)

		var flow: Vector3 = _world_manager.get_water_flow_vector(global_position)
		velocity.x = move_toward(velocity.x, flow.x * 2.5, 6.5 * delta)
		velocity.z = move_toward(velocity.z, flow.z * 2.5, 6.5 * delta)
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -24.0)

	# Horizontal movement with wall check
	var next_x: float = global_position.x + velocity.x * delta
	var check_x := Vector3i(floori(next_x), floori(global_position.y + 0.15), floori(global_position.z))
	if BlockRegistry.is_solid(_world_manager.get_block_world(check_x)):
		velocity.x = -velocity.x * 0.3
	else:
		global_position.x = next_x

	var next_z: float = global_position.z + velocity.z * delta
	var check_z := Vector3i(floori(global_position.x), floori(global_position.y + 0.15), floori(next_z))
	if BlockRegistry.is_solid(_world_manager.get_block_world(check_z)):
		velocity.z = -velocity.z * 0.3
	else:
		global_position.z = next_z

	# Vertical movement & floor resting
	var next_y: float = global_position.y + velocity.y * delta
	var check_floor := Vector3i(floori(global_position.x), floori(next_y), floori(global_position.z))
	if velocity.y <= 0.0 and BlockRegistry.is_solid(_world_manager.get_block_world(check_floor)):
		global_position.y = float(check_floor.y + 1) + 0.01
		velocity.y = 0.0
		velocity.x = move_toward(velocity.x, 0.0, 9.5 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 9.5 * delta)
	else:
		global_position.y = next_y


func _try_merge_with_nearby_drops() -> void:
	if count >= InventoryManager.MAX_STACK:
		return
	for node in get_tree().get_nodes_in_group("dropped_items"):
		if node == self or not (node is DroppedItem):
			continue
		var other := node as DroppedItem
		if other._collected or other.item_id != item_id:
			continue
		if global_position.distance_squared_to(other.global_position) <= MERGE_RADIUS * MERGE_RADIUS:
			if count + other.count <= InventoryManager.MAX_STACK:
				count += other.count
				other._collected = true
				other.queue_free()
				return


func _collect_into_inventory() -> void:
	if _inventory == null:
		_inventory = get_tree().get_first_node_in_group("inventory_manager") as InventoryManager
	if _inventory != null:
		if _inventory.add_item(item_id, count, durability):
			_collected = true
			var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
			if sfx != null and sfx.has_method("play_sfx"):
				sfx.play_sfx("item_pickup", -4.0, 1.15)
			if _player != null:
				var interactor := _player.get_node_or_null("BlockInteractor") as BlockInteractor
				if interactor != null:
					interactor.loot_notification.emit("+%d %s" % [count, InventoryManager.get_item_name(item_id)])
			queue_free()


func _build_visual_mesh() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	_visual_root.position = Vector3(0.0, 0.16, 0.0)
	add_child(_visual_root)

	if InventoryManager.is_placeable_block(item_id):
		var mi := MeshInstance3D.new()
		mi.material_override = VoxelAtlasBuilder.get_shared_voxel_material()
		mi.mesh = _build_mini_block_mesh(item_id)
		_visual_root.add_child(mi)
	else:
		# Double-sided textured quad using authentic Faithful 64x tool / item sprite
		var icon_tex: Texture2D = InventoryManager.get_item_icon_texture(item_id)
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.roughness = 0.5
		if icon_tex != null:
			mat.albedo_texture = icon_tex
		else:
			mat.albedo_color = InventoryManager.get_item_color(item_id)

		var item_mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.36, 0.36)
		quad.material = mat
		item_mi.mesh = quad
		_visual_root.add_child(item_mi)


func _build_mini_block_mesh(block_id: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h: float = MINI_CUBE_SIZE * 0.5
	var faces: Array[int] = [
		BlockRegistry.FaceDir.TOP,
		BlockRegistry.FaceDir.BOTTOM,
		BlockRegistry.FaceDir.EAST,
		BlockRegistry.FaceDir.WEST,
		BlockRegistry.FaceDir.SOUTH,
		BlockRegistry.FaceDir.NORTH,
	]
	for face_dir in faces:
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
				verts = [Vector3(-h, h, -h), Vector3(h, h, -h), Vector3(h, h, h), Vector3(-h, h, h)]
			BlockRegistry.FaceDir.BOTTOM:
				normal = Vector3.DOWN
				shade = 0.55
				verts = [Vector3(-h, -h, h), Vector3(h, -h, h), Vector3(h, -h, -h), Vector3(-h, -h, -h)]
			BlockRegistry.FaceDir.EAST:
				normal = Vector3.RIGHT
				shade = 0.82
				verts = [Vector3(h, h, h), Vector3(h, h, -h), Vector3(h, -h, -h), Vector3(h, -h, h)]
			BlockRegistry.FaceDir.WEST:
				normal = Vector3.LEFT
				shade = 0.76
				verts = [Vector3(-h, h, -h), Vector3(-h, h, h), Vector3(-h, -h, h), Vector3(-h, -h, -h)]
			BlockRegistry.FaceDir.SOUTH:
				normal = Vector3.BACK
				shade = 0.90
				verts = [Vector3(-h, h, h), Vector3(h, h, h), Vector3(h, -h, h), Vector3(-h, -h, h)]
			_:
				normal = Vector3.FORWARD
				shade = 0.72
				verts = [Vector3(h, h, -h), Vector3(-h, h, -h), Vector3(-h, -h, -h), Vector3(h, -h, -h)]

		var uvs: Array[Vector2] = [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
		var col := Color(shade, shade, shade, 1.0)
		var indices: Array[int] = [0, 1, 2, 0, 2, 3]
		for idx in indices:
			st.set_normal(normal)
			st.set_color(col)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])
	return st.commit()
