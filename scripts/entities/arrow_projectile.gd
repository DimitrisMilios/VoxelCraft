class_name ArrowProjectile
extends Node3D
## TrueCraft & Beta 1.7.3 authentic ballistic arrow projectile entity.
## Features ballistic arc kinematics (gravity & air drag), continuous collision detection,
## water drag attenuation, mob damage & knockback, block sticking, and player arrow retrieval.

const GRAVITY: float = 14.0
const DRAG: float = 0.99
const WATER_DRAG: float = 0.65
const DAMAGE_MIN: int = 4
const DAMAGE_MAX: int = 10
const LIFETIME_STUCK: float = 60.0
const PICKUP_RADIUS: float = 1.4

var velocity: Vector3 = Vector3.ZERO
var charge: float = 1.0 # 0.15 to 1.0
var is_stuck: bool = false
var stuck_timer: float = 0.0
var shooter: Node = null
var can_pickup: bool = true

var _world_manager: WorldManager = null
var _player: PlayerController = null
var _inventory: InventoryManager = null
var _visual_mesh: Node3D = null


static func spawn_arrow(
	parent_node: Node,
	world_pos: Vector3,
	launch_vel: Vector3,
	p_charge: float = 1.0,
	p_shooter: Node = null,
	p_can_pickup: bool = true
) -> ArrowProjectile:
	if parent_node == null:
		return null
	var arrow: ArrowProjectile = (load("res://scripts/entities/arrow_projectile.gd") as GDScript).new()
	arrow.position = world_pos
	arrow.velocity = launch_vel
	arrow.charge = p_charge
	arrow.shooter = p_shooter
	arrow.can_pickup = p_can_pickup
	parent_node.add_child(arrow)
	return arrow


func _ready() -> void:
	add_to_group("arrows")
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager if is_inside_tree() and get_tree() != null else null
	_player = get_tree().get_first_node_in_group("player") as PlayerController if is_inside_tree() and get_tree() != null else null
	_inventory = get_tree().get_first_node_in_group("inventory_manager") as InventoryManager if is_inside_tree() and get_tree() != null else null
	_build_arrow_model()
	if velocity.length_squared() > 0.01:
		if is_inside_tree():
			look_at(global_position + velocity, Vector3.UP)
		else:
			transform = transform.looking_at(position + velocity, Vector3.UP)


func _physics_process(delta: float) -> void:
	if is_stuck:
		_process_stuck_state(delta)
		return

	if _world_manager == null:
		if get_parent() is WorldManager:
			_world_manager = get_parent() as WorldManager
		elif is_inside_tree() and get_tree() != null:
			_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager

	var cur_pos: Vector3 = global_position if is_inside_tree() else position

	# Check water resistance
	var in_water: bool = false
	if _world_manager != null:
		var depth: float = _world_manager.get_water_submersion_depth(cur_pos)
		if depth > 0.1:
			in_water = true

	if in_water:
		velocity.y -= (GRAVITY * 0.35) * delta
		velocity *= pow(WATER_DRAG, delta * 60.0)
	else:
		velocity.y -= GRAVITY * delta
		velocity *= pow(DRAG, delta * 60.0)

	var step_vec: Vector3 = velocity * delta
	var step_len: float = step_vec.length()
	if step_len < 0.0001:
		return

	var start_pos: Vector3 = cur_pos
	var end_pos: Vector3 = cur_pos + step_vec

	# 1. Continuous collision detection against Mobs
	if _check_mob_collision(start_pos, end_pos):
		return

	# 2. Continuous collision detection against Voxel Terrain
	if _check_terrain_collision(start_pos, end_pos, step_len):
		return

	# Update position & flight rotation
	if is_inside_tree():
		global_position = end_pos
		if velocity.length_squared() > 0.1:
			look_at(global_position + velocity, Vector3.UP)
	else:
		position = end_pos
		if velocity.length_squared() > 0.1:
			transform = transform.looking_at(position + velocity, Vector3.UP)

	var final_y: float = global_position.y if is_inside_tree() else position.y
	if final_y < -20.0:
		queue_free()


func _check_mob_collision(start_pos: Vector3, end_pos: Vector3) -> bool:
	var tree: SceneTree = get_tree() if is_inside_tree() else null
	var mobs: Array = []
	if tree != null:
		mobs = tree.get_nodes_in_group("mobs")
	elif _world_manager != null:
		for c in _world_manager.get_children():
			if c.is_in_group("mobs"):
				mobs.append(c)

	var hit_mob: PassiveMob = null
	var hit_dist: float = 999999.0
	var seg_dir: Vector3 = (end_pos - start_pos).normalized()
	var seg_len: float = start_pos.distance_to(end_pos)

	for m in mobs:
		if not is_instance_valid(m) or m == shooter:
			continue
		if m is PassiveMob:
			var mob := m as PassiveMob
			var m_pos: Vector3 = mob.global_position if mob.is_inside_tree() else mob.position
			var mob_aabb := AABB(m_pos + Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.8, 0.8))
			var isect: Variant = mob_aabb.intersects_segment(start_pos, end_pos)
			if isect != null:
				var d: float = start_pos.distance_to(isect)
				if d < hit_dist:
					hit_dist = d
					hit_mob = mob

	# Check player collision if shooter was not the player
	if _player != null and is_instance_valid(_player) and shooter != _player:
		var p_pos: Vector3 = _player.global_position if _player.is_inside_tree() else _player.position
		var p_aabb := AABB(p_pos + Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.8, 0.8))
		var p_isect: Variant = p_aabb.intersects_segment(start_pos, end_pos)
		if p_isect != null:
			var pd: float = start_pos.distance_to(p_isect)
			if pd < hit_dist:
				var p_dmg: int = int(round(lerpf(float(DAMAGE_MIN), float(DAMAGE_MAX), charge)))
				_player.take_damage(p_dmg)
				var kb: Vector3 = velocity.normalized() * 4.2 + Vector3(0.0, 2.5, 0.0)
				_player.velocity += kb
				_play_sfx("bow_hit", p_pos)
				queue_free()
				return true

	if hit_mob != null:
		var dmg: int = int(round(lerpf(float(DAMAGE_MIN), float(DAMAGE_MAX), charge)))
		if charge >= 0.9:
			dmg += 2 # Critical hit bonus
		var hit_pos: Vector3 = global_position if is_inside_tree() else position
		hit_mob.on_hit_by_player(hit_pos, dmg)
		_play_sfx("bow_hit", hit_pos)
		queue_free()
		return true

	return false


func _check_terrain_collision(start_pos: Vector3, end_pos: Vector3, step_len: float) -> bool:
	if _world_manager == null:
		return false

	var sub_steps: int = maxi(1, int(ceil(step_len / 0.15)))
	var step_delta: Vector3 = (end_pos - start_pos) / float(sub_steps)
	var current: Vector3 = start_pos

	for i in range(1, sub_steps + 1):
		var test_p: Vector3 = start_pos + step_delta * float(i)
		var vpos := Vector3i(floori(test_p.x), floori(test_p.y), floori(test_p.z))
		var bid: int = _world_manager.get_block_world(vpos)

		if BlockRegistry.is_solid(bid):
			# Embed arrow slightly into the block face
			var embed_pos: Vector3 = test_p - velocity.normalized() * 0.12
			if is_inside_tree():
				global_position = embed_pos
			else:
				position = embed_pos
			is_stuck = true
			velocity = Vector3.ZERO
			_play_sfx("bow_hit", embed_pos)
			return true

	return false


func _process_stuck_state(delta: float) -> void:
	stuck_timer += delta
	if stuck_timer >= LIFETIME_STUCK:
		queue_free()
		return

	if not can_pickup:
		return

	if _player == null and is_inside_tree() and get_tree() != null:
		_player = get_tree().get_first_node_in_group("player") as PlayerController
	if _inventory == null and is_inside_tree() and get_tree() != null:
		_inventory = get_tree().get_first_node_in_group("inventory_manager") as InventoryManager

	if _player != null and is_instance_valid(_player):
		var cur_p: Vector3 = global_position if is_inside_tree() else position
		var p_pos: Vector3 = _player.global_position if _player.is_inside_tree() else _player.position
		p_pos += Vector3(0.0, 0.8, 0.0)
		if cur_p.distance_to(p_pos) <= PICKUP_RADIUS:
			if _inventory != null and _inventory.add_item(InventoryManager.ItemId.ARROW, 1):
				_play_sfx("item_pickup", cur_p)
				if is_inside_tree() and get_tree() != null:
					var hud: VoxelHUD = get_tree().get_first_node_in_group("voxel_hud") as VoxelHUD
					if hud != null:
						hud.show_notification("+1 Arrow")
				queue_free()


func _play_sfx(sfx_name: String, pos: Vector3) -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
	if sfx != null and sfx.has_method("play_sfx_at_pos"):
		sfx.play_sfx_at_pos(sfx_name, pos, 0.0)


func _build_arrow_model() -> void:
	_visual_mesh = Node3D.new()
	_visual_mesh.name = "ArrowVisual"

	# 1. Wooden shaft (0.04m x 0.04m x 0.58m)
	var shaft := MeshInstance3D.new()
	var shaft_box := BoxMesh.new()
	shaft_box.size = Vector3(0.04, 0.04, 0.58)
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_color = Color(0.58, 0.40, 0.22)
	shaft_mat.roughness = 0.8
	shaft.mesh = shaft_box
	shaft.material_override = shaft_mat
	shaft.position = Vector3(0.0, 0.0, 0.0)
	_visual_mesh.add_child(shaft)

	# 2. Flint / Metal Arrowhead (front, -Z)
	var head := MeshInstance3D.new()
	var head_box := BoxMesh.new()
	head_box.size = Vector3(0.08, 0.08, 0.12)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.78, 0.80, 0.82)
	head_mat.metallic = 0.6
	head_mat.roughness = 0.4
	head.mesh = head_box
	head.material_override = head_mat
	head.position = Vector3(0.0, 0.0, -0.32)
	_visual_mesh.add_child(head)

	# 3. Fletchings / Feathers (tail, +Z)
	var fletch := MeshInstance3D.new()
	var fletch_box := BoxMesh.new()
	fletch_box.size = Vector3(0.12, 0.12, 0.14)
	var fletch_mat := StandardMaterial3D.new()
	fletch_mat.albedo_color = Color(0.92, 0.92, 0.95)
	fletch_mat.roughness = 0.9
	fletch.mesh = fletch_box
	fletch.material_override = fletch_mat
	fletch.position = Vector3(0.0, 0.0, 0.25)
	_visual_mesh.add_child(fletch)

	add_child(_visual_mesh)
