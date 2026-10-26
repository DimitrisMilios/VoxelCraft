class_name PassiveMob
extends CharacterBody3D
## Autonomous voxel mob supporting both Passive animals (Pig, Cow, Sheep, Chicken) and
## Hostile night/cave monsters (Zombie, Skeleton, Creeper, Spider) with
## authentic Faithful 64x UV-mapped cuboid models, 3D A* pathfinding intelligence,
## health, weapon damage, 3D loot drops, melee/ballistics/explosion combat, and water buoyancy.

const CuboidMeshBuilder = preload("res://scripts/entities/cuboid_mesh_builder.gd")
const AStarPathFinder = preload("res://scripts/entities/astar_pathfinder.gd")
const ArrowProjectile = preload("res://scripts/entities/arrow_projectile.gd")

enum MobState {
	IDLE,
	WANDER,
	PANIC,
	CHASE,
	GRAZE,
	STRAFE,
}

enum MobVariant {
	PIG = 0,
	COW = 1,
	ZOMBIE = 2,
	SKELETON = 3,
	CREEPER = 4,
	SPIDER = 5,
	SHEEP = 6,
	VILLAGER = 7,
	CHICKEN = 8,
}

@export var move_speed: float = 2.1
@export var panic_speed: float = 5.2
@export var hop_velocity: float = 6.5
@export var gravity_multiplier: float = 1.8
@export var variant: MobVariant = MobVariant.PIG:
	set(val):
		variant = val

var health: int = 10
var max_health: int = 10
var is_sheared: bool = false
var is_provoked: bool = false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _state: MobState = MobState.IDLE
var _state_timer: float = 2.0
var _target_yaw: float = 0.0
var _anim_time: float = 0.0
var _hurt_flash_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _creeper_fuse: float = 0.0
var _sun_burn_timer: float = 0.0
var _ambient_sound_timer: float = randf_range(3.0, 8.0)

var _skeleton_shoot_timer: float = randf_range(1.6, 2.4)
var _spider_leap_timer: float = 0.0
var _graze_timer: float = randf_range(12.0, 24.0)
var _graze_active_time: float = 0.0
var _egg_timer: float = randf_range(240.0, 480.0)

var _path: Array[Vector3i] = []
var _path_index: int = 0
var _repath_timer: float = 0.0

var _visual_root: Node3D = null
var _head_node: Node3D = null
var _wool_mesh: MeshInstance3D = null
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _wings: Array[Node3D] = []
var _bow_mesh: MeshInstance3D = null
var _col_shape: CollisionShape3D = null
var _ledge_ray: RayCast3D = null
var _step_ray: RayCast3D = null
var _mob_mat: StandardMaterial3D = null
var _primary_color: Color = Color.WHITE
var _world_manager: WorldManager = null
var _player: PlayerController = null
var _day_night: DayNightCycle = null


func is_hostile() -> bool:
	return (
		variant == MobVariant.ZOMBIE
		or variant == MobVariant.SKELETON
		or variant == MobVariant.CREEPER
		or variant == MobVariant.SPIDER
	)


func set_mob_variant(new_variant: MobVariant) -> void:
	variant = new_variant
	if is_hostile():
		max_health = 16 if variant == MobVariant.SPIDER else 20
		move_speed = 3.6 if variant == MobVariant.SPIDER else (3.2 if variant == MobVariant.ZOMBIE else 2.8)
	elif variant == MobVariant.CHICKEN:
		max_health = 4
		move_speed = 2.0
	else:
		max_health = 10
		move_speed = 2.1
	health = max_health

	if _visual_root != null:
		_visual_root.queue_free()
		_visual_root = null
		_legs.clear()
		_arms.clear()
		_wings.clear()
		_head_node = null
		_wool_mesh = null
		_bow_mesh = null

	_build_collision_and_rays()
	_build_voxel_model()


func _ready() -> void:
	add_to_group("mobs")
	collision_layer = 4
	collision_mask = 1

	if _visual_root == null:
		set_mob_variant(variant)

	_pick_next_state()
	call_deferred("_resolve_refs")


func _resolve_refs() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	_player = get_tree().get_first_node_in_group("player") as PlayerController
	_day_night = get_tree().get_first_node_in_group("day_night_cycle") as DayNightCycle


func _physics_process(delta: float) -> void:
	if _hurt_flash_timer > 0.0:
		_hurt_flash_timer = maxf(0.0, _hurt_flash_timer - delta)
		if _hurt_flash_timer <= 0.0 and _mob_mat != null:
			_mob_mat.albedo_color = Color.WHITE

	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	var cur_pos: Vector3 = global_position if is_inside_tree() else position

	# Water buoyancy for mobs so animals and monsters swim and drift in currents
	var in_water: bool = false
	var depth: float = 0.0
	if _world_manager != null:
		depth = _world_manager.get_water_submersion_depth(cur_pos)
		if depth > 0.25:
			in_water = true
			velocity.y = move_toward(velocity.y, 1.8, 10.0 * delta)
			var flow: Vector3 = _world_manager.get_water_flow_vector(cur_pos)
			velocity.x += flow.x * 1.8 * delta
			velocity.z += flow.z * 1.8 * delta

	# Gravity & Chicken Flutter descent
	if not in_water and not is_on_floor():
		if variant == MobVariant.CHICKEN:
			# Chicken flutters gently down to prevent fall damage
			velocity.y -= _gravity * 0.45 * delta
			velocity.y = maxf(velocity.y, -2.2)
		else:
			velocity.y -= _gravity * gravity_multiplier * delta

	# Ambient vocalizations
	_ambient_sound_timer -= delta
	if _ambient_sound_timer <= 0.0:
		_ambient_sound_timer = randf_range(5.0, 12.0)
		_play_ambient_vocal()

	if is_hostile():
		_process_hostile_ai(delta, in_water)
	else:
		_process_passive_ai(delta)

	# Movement execution
	if _state == MobState.WANDER or _state == MobState.PANIC or _state == MobState.CHASE or _state == MobState.STRAFE:
		var active_speed: float = move_speed
		if _state == MobState.PANIC:
			active_speed = panic_speed
		elif _state == MobState.CHASE:
			active_speed = move_speed * 1.15
		elif _state == MobState.STRAFE:
			active_speed = move_speed * 0.85

		# Waypoint path navigation
		var has_waypoint: bool = false
		if _path_index < _path.size():
			var wp: Vector3i = _path[_path_index]
			var wp_target := Vector3(float(wp.x) + 0.5, float(wp.y), float(wp.z) + 0.5)
			var to_wp: Vector3 = wp_target - cur_pos
			to_wp.y = 0.0

			if to_wp.length() < 0.45:
				_path_index += 1
			else:
				has_waypoint = true
				_target_yaw = atan2(-to_wp.x, -to_wp.z)
				if wp.y > floori(cur_pos.y) and is_on_floor():
					velocity.y = hop_velocity

		var turn_rate: float = 12.0 if (_state == MobState.PANIC or _state == MobState.CHASE) else 6.0
		rotation.y = lerp_angle(rotation.y, _target_yaw, turn_rate * delta)

		var fwd: Vector3 = -global_transform.basis.z if is_inside_tree() else -transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()

		# Ledge avoidance for passive wandering
		if _state == MobState.WANDER and is_on_floor() and _ledge_ray != null and not _ledge_ray.is_colliding():
			_target_yaw += PI * 0.75
		else:
			velocity.x = move_toward(velocity.x, fwd.x * active_speed, 14.0 * delta)
			velocity.z = move_toward(velocity.z, fwd.z * active_speed, 14.0 * delta)

		# Spiders climb walls; other mobs hop up 1-block steps
		if variant == MobVariant.SPIDER and is_on_wall():
			velocity.y = 3.8
		elif is_on_floor() and _step_ray != null and _step_ray.is_colliding():
			velocity.y = hop_velocity
	else:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

	if is_inside_tree():
		move_and_slide()
	else:
		position += velocity * delta

	_animate_limbs(delta)


func _process_hostile_ai(delta: float, in_water: bool) -> void:
	var my_pos: Vector3 = global_position if is_inside_tree() else position

	# Zombies and Skeletons burn in direct sunlight when exposed to daylight sky
	if (variant == MobVariant.ZOMBIE or variant == MobVariant.SKELETON) and _day_night != null and not in_water:
		if _day_night.time_of_day > 0.24 and _day_night.time_of_day < 0.76:
			var exposed: bool = true
			if _world_manager != null:
				var surface_y: int = _world_manager.get_surface_height_at(floori(my_pos.x), floori(my_pos.z))
				exposed = (my_pos.y >= float(surface_y) - 0.5)
			if exposed:
				_sun_burn_timer += delta
				if _sun_burn_timer >= 1.0:
					_sun_burn_timer = 0.0
					on_hit_by_player(my_pos + Vector3(0.0, 1.0, 0.0), 1)
					if _mob_mat != null:
						_mob_mat.albedo_color = Color(1.8, 0.8, 0.2)
					if health <= 0:
						return

	if _player == null or not is_instance_valid(_player) or _player.is_flying:
		_state_timer -= delta
		if _state_timer <= 0.0:
			_pick_next_state()
		return

	var p_pos: Vector3 = _player.global_position if _player.is_inside_tree() else _player.position
	var to_player: Vector3 = p_pos - my_pos
	var dist: float = to_player.length()

	if dist > 16.5:
		_creeper_fuse = 0.0
		if _visual_root != null:
			_visual_root.scale = Vector3.ONE
		if _mob_mat != null and _hurt_flash_timer <= 0.0:
			_mob_mat.albedo_color = Color.WHITE
		_state_timer -= delta
		if _state_timer <= 0.0:
			_pick_next_state()
		return

	# Recalculate A* path periodically
	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = randf_range(1.0, 1.5)
		if _world_manager != null and dist > 2.0:
			var start_vox := Vector3i(floori(my_pos.x), floori(my_pos.y), floori(my_pos.z))
			var goal_vox := Vector3i(floori(p_pos.x), floori(p_pos.y), floori(p_pos.z))
			var clearance: int = 1 if variant == MobVariant.SPIDER else 2
			_path = AStarPathFinder.find_path(_world_manager, start_vox, goal_vox, clearance, 200)
			_path_index = 0
			if _path.size() > 1 and _path[0] == start_vox:
				_path_index = 1

	match variant:
		MobVariant.CREEPER:
			_process_creeper_ai(delta, dist, to_player)
		MobVariant.SKELETON:
			_process_skeleton_ai(delta, dist, to_player)
		MobVariant.SPIDER:
			_process_spider_ai(delta, dist, to_player)
		MobVariant.ZOMBIE:
			_process_zombie_ai(delta, dist, to_player)


func _process_creeper_ai(delta: float, dist: float, to_player: Vector3) -> void:
	if dist <= 3.0:
		velocity.x = 0.0
		velocity.z = 0.0
		if _creeper_fuse == 0.0:
			if is_inside_tree() and get_tree() != null:
				var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
				if sfx != null and sfx.has_method("play_sfx_at_pos"):
					sfx.play_sfx_at_pos("creeper_fuse", global_position if is_inside_tree() else position, 0.0)
		_creeper_fuse += delta
		var flash: bool = (int(_creeper_fuse * 10.0) % 2 == 0)
		if _mob_mat != null:
			_mob_mat.albedo_color = Color(2.0, 2.0, 2.0) if flash else Color.WHITE
		var swell: float = 1.0 + (_creeper_fuse / 1.5) * 0.35
		if _visual_root != null:
			_visual_root.scale = Vector3(swell, swell, swell)
		if _creeper_fuse >= 1.5:
			_trigger_creeper_explosion()
			return
	else:
		if _creeper_fuse > 0.0:
			_creeper_fuse = maxf(0.0, _creeper_fuse - delta * 1.5)
			if _creeper_fuse <= 0.0:
				if _visual_root != null:
					_visual_root.scale = Vector3.ONE
				if _mob_mat != null:
					_mob_mat.albedo_color = Color.WHITE
		_target_yaw = atan2(-to_player.x, -to_player.z)
		_state = MobState.CHASE


func _process_skeleton_ai(delta: float, dist: float, to_player: Vector3) -> void:
	_skeleton_shoot_timer -= delta
	if _skeleton_shoot_timer <= 0.0 and dist <= 16.0:
		_skeleton_shoot_timer = randf_range(1.7, 2.4)
		_shoot_arrow_at_player(to_player)

	# Skeleton maintains 8..13m distance (strafes or retreats)
	if dist < 7.0:
		_target_yaw = atan2(to_player.x, to_player.z)
		_state = MobState.CHASE
	elif dist > 13.0:
		_target_yaw = atan2(-to_player.x, -to_player.z)
		_state = MobState.CHASE
	else:
		_target_yaw = atan2(-to_player.x, -to_player.z) + PI * 0.5
		_state = MobState.STRAFE


func _shoot_arrow_at_player(to_player: Vector3) -> void:
	if _player == null:
		return
	var shoot_origin: Vector3 = (global_position if is_inside_tree() else position) + Vector3(0.0, 1.25, 0.0)
	var aim_target: Vector3 = (_player.global_position if _player.is_inside_tree() else _player.position) + Vector3(0.0, 1.1, 0.0)
	var shoot_dir: Vector3 = (aim_target - shoot_origin).normalized()
	shoot_dir += Vector3(randf_range(-0.04, 0.04), randf_range(-0.02, 0.04), randf_range(-0.04, 0.04))
	shoot_dir = shoot_dir.normalized()

	var p_node: Node = get_parent() if is_inside_tree() else self
	ArrowProjectile.spawn_arrow(p_node, shoot_origin, shoot_dir * 18.0, 0.85, self, true)

	if is_inside_tree() and get_tree() != null:
		var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
		if sfx != null and sfx.has_method("play_sfx_at_pos"):
			sfx.play_sfx_at_pos("bow_shoot", shoot_origin, 1.0)


func _process_spider_ai(delta: float, dist: float, to_player: Vector3) -> void:
	# Daylight neutrality: neutral in bright daylight unless provoked
	var is_day: bool = false
	if _day_night != null:
		is_day = (_day_night.time_of_day > 0.24 and _day_night.time_of_day < 0.76)
	if is_day and not is_provoked:
		_state_timer -= delta
		if _state_timer <= 0.0:
			_pick_next_state()
		return

	_target_yaw = atan2(-to_player.x, -to_player.z)
	_state = MobState.CHASE

	# Leap attack
	if _spider_leap_timer > 0.0:
		_spider_leap_timer = maxf(0.0, _spider_leap_timer - delta)

	if dist >= 2.2 and dist <= 5.2 and (is_on_floor() or not is_inside_tree()) and _spider_leap_timer <= 0.0:
		try_leap_pounce(to_player)

	# Melee bite on contact
	if dist <= 1.5 and _attack_cooldown <= 0.0:
		_attack_cooldown = 1.0
		_player.take_damage(2)
		var kb: Vector3 = to_player.normalized() * 3.8 + Vector3(0.0, 2.4, 0.0)
		_player.velocity += kb


func try_leap_pounce(to_player: Vector3) -> bool:
	_spider_leap_timer = randf_range(3.0, 4.5)
	var pounce_dir: Vector3 = to_player.normalized()
	velocity = pounce_dir * 7.5 + Vector3(0.0, 4.8, 0.0)
	if is_inside_tree() and get_tree() != null:
		var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
		if sfx != null and sfx.has_method("play_sfx_at_pos"):
			sfx.play_sfx_at_pos("spider_ambient", global_position if is_inside_tree() else position, 1.5)
	return true


func _process_zombie_ai(delta: float, dist: float, to_player: Vector3) -> void:
	_target_yaw = atan2(-to_player.x, -to_player.z)
	_state = MobState.CHASE

	if dist <= 1.45 and _attack_cooldown <= 0.0:
		_attack_cooldown = 1.15
		_player.take_damage(3)
		var kb: Vector3 = to_player.normalized() * 4.5 + Vector3(0.0, 2.8, 0.0)
		_player.velocity += kb


func _process_passive_ai(delta: float) -> void:
	if variant == MobVariant.CHICKEN:
		_egg_timer -= delta
		if _egg_timer <= 0.0:
			_egg_timer = randf_range(240.0, 480.0)
			lay_egg()

	# Sheep grazing
	if variant == MobVariant.SHEEP:
		if _state == MobState.GRAZE:
			_graze_active_time -= delta
			if _head_node != null:
				_head_node.rotation.x = deg_to_rad(38.0)
			if _graze_active_time <= 0.0:
				_perform_graze()
				if _head_node != null:
					_head_node.rotation.x = 0.0
				_state = MobState.IDLE
				_state_timer = 2.0
			return

		_graze_timer -= delta
		if _graze_timer <= 0.0:
			_graze_timer = randf_range(14.0, 26.0)
			_state = MobState.GRAZE
			_graze_active_time = 1.6
			return

	_state_timer -= delta
	if _state_timer <= 0.0:
		_pick_next_state()


func _perform_graze() -> void:
	if _world_manager == null:
		return
	var my_pos: Vector3 = global_position if is_inside_tree() else position
	var under_pos := Vector3i(floori(my_pos.x), floori(my_pos.y - 0.2), floori(my_pos.z))
	var block_id: int = _world_manager.get_block_world(under_pos)
	if block_id == BlockRegistry.BlockId.GRASS:
		_world_manager.set_block_world(under_pos, BlockRegistry.BlockId.DIRT)
		if is_inside_tree() and get_tree() != null:
			var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
			if sfx != null and sfx.has_method("play_sfx_at_pos"):
				sfx.play_sfx_at_pos("bow_hit", my_pos, 0.5)
		if is_sheared:
			is_sheared = false
			if _wool_mesh != null:
				_wool_mesh.visible = true


func lay_egg() -> void:
	if _world_manager != null:
		DroppedItem.spawn_drop(
			_world_manager,
			(global_position if is_inside_tree() else position) + Vector3(0.0, 0.25, 0.0),
			InventoryManager.ItemId.EGG,
			1
		)
		if is_inside_tree() and get_tree() != null:
			var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
			if sfx != null and sfx.has_method("play_sfx_at_pos"):
				sfx.play_sfx_at_pos("chicken_ambient", global_position if is_inside_tree() else position, 1.0)


func _trigger_creeper_explosion() -> void:
	var boom_pos: Vector3 = global_position if is_inside_tree() else position
	if _world_manager != null and _world_manager.has_method("create_explosion"):
		_world_manager.create_explosion(boom_pos + Vector3(0.0, 0.4, 0.0), 3.5, true, true)
	else:
		if is_inside_tree() and get_tree() != null:
			var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
			if sfx != null and sfx.has_method("play_sfx_at_pos"):
				sfx.play_sfx_at_pos("creeper_explode", boom_pos, 4.0, 1.0, 48.0)
	queue_free()


## Called when the player left-clicks this mob. Applies weapon damage, knockback, and spawns loot on death.
func on_hit_by_player(attacker_pos: Vector3, damage: int = 2) -> void:
	var current_pos: Vector3 = global_position if is_inside_tree() else position
	var away_dir: Vector3 = current_pos - attacker_pos
	away_dir.y = 0.0
	if away_dir.length_squared() < 0.001:
		away_dir = Vector3.FORWARD
	away_dir = away_dir.normalized()

	health -= maxi(1, damage)
	velocity = away_dir * 6.2 + Vector3(0.0, 5.4, 0.0)
	_target_yaw = atan2(-away_dir.x, -away_dir.z)
	_state = MobState.CHASE if is_hostile() else MobState.PANIC
	_state_timer = 3.8
	_hurt_flash_timer = 0.26
	_creeper_fuse = maxf(0.0, _creeper_fuse - 0.5)
	is_provoked = true

	if _mob_mat != null:
		_mob_mat.albedo_color = Color(1.0, 0.32, 0.32)

	if is_inside_tree() and get_tree() != null:
		var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
		if sfx != null and sfx.has_method("play_sfx_at_pos"):
			var hurt_sfx := ""
			match variant:
				MobVariant.ZOMBIE: hurt_sfx = "zombie_hurt"
				MobVariant.SKELETON: hurt_sfx = "skeleton_hurt"
				MobVariant.CREEPER: hurt_sfx = "creeper_fuse"
				MobVariant.COW: hurt_sfx = "cow_hurt"
				MobVariant.PIG: hurt_sfx = "pig_hurt"
				MobVariant.SPIDER: hurt_sfx = "spider_hurt"
				MobVariant.SHEEP: hurt_sfx = "sheep_hurt"
				MobVariant.VILLAGER: hurt_sfx = "villager_hurt"
				MobVariant.CHICKEN: hurt_sfx = "chicken_hurt"
			if not hurt_sfx.is_empty():
				sfx.play_sfx_at_pos(hurt_sfx, current_pos, 1.0)

	if health <= 0:
		_die_and_drop_loot()


func _die_and_drop_loot() -> void:
	var cur_pos: Vector3 = global_position if is_inside_tree() else position
	if is_inside_tree() and get_tree() != null:
		var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
		if sfx != null and sfx.has_method("play_sfx_at_pos"):
			var death_sfx := ""
			match variant:
				MobVariant.ZOMBIE: death_sfx = "zombie_death"
				MobVariant.SKELETON: death_sfx = "skeleton_death"
				MobVariant.PIG: death_sfx = "pig_hurt"
				MobVariant.COW: death_sfx = "cow_hurt"
				MobVariant.SPIDER: death_sfx = "spider_hurt"
				MobVariant.SHEEP: death_sfx = "sheep_hurt"
				MobVariant.VILLAGER: death_sfx = "villager_hurt"
				MobVariant.CHICKEN: death_sfx = "chicken_hurt"
			if not death_sfx.is_empty():
				sfx.play_sfx_at_pos(death_sfx, cur_pos, 2.0)

	if _world_manager != null:
		var drop_id: int = 0
		var drop_cnt: int = randi_range(1, 2)
		match variant:
			MobVariant.PIG:
				drop_id = InventoryManager.ItemId.RAW_PORKCHOP
			MobVariant.COW:
				drop_id = InventoryManager.ItemId.RAW_BEEF
			MobVariant.ZOMBIE:
				drop_id = InventoryManager.ItemId.ROTTEN_FLESH
			MobVariant.SKELETON:
				drop_id = InventoryManager.ItemId.ARROW if randf() < 0.6 else InventoryManager.ItemId.STICK
			MobVariant.CREEPER:
				drop_id = InventoryManager.ItemId.GUNPOWDER
			MobVariant.SPIDER:
				drop_id = InventoryManager.ItemId.STRING
			MobVariant.SHEEP:
				drop_id = InventoryManager.ItemId.WOOL if not is_sheared else InventoryManager.ItemId.RAW_PORKCHOP
			MobVariant.CHICKEN:
				drop_id = InventoryManager.ItemId.FEATHER if randf() < 0.5 else InventoryManager.ItemId.RAW_CHICKEN
			MobVariant.VILLAGER:
				drop_id = InventoryManager.ItemId.BREAD

		if drop_id > 0:
			DroppedItem.spawn_drop(
				_world_manager,
				cur_pos + Vector3(0.0, 0.45, 0.0),
				drop_id,
				drop_cnt
			)
	queue_free()


func _play_ambient_vocal() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
	if sfx == null or not sfx.has_method("play_sfx_at_pos"):
		return
	var sfx_name := ""
	match variant:
		MobVariant.ZOMBIE: sfx_name = "zombie_ambient"
		MobVariant.SKELETON: sfx_name = "skeleton_ambient"
		MobVariant.COW: sfx_name = "cow_ambient"
		MobVariant.PIG: sfx_name = "pig_ambient"
		MobVariant.SPIDER: sfx_name = "spider_ambient"
		MobVariant.SHEEP: sfx_name = "sheep_ambient"
		MobVariant.VILLAGER: sfx_name = "villager_ambient"
		MobVariant.CHICKEN: sfx_name = "chicken_ambient"
	if not sfx_name.is_empty():
		sfx.play_sfx_at_pos(sfx_name, global_position if is_inside_tree() else position, -1.5, 1.0, 24.0)


## Called when the player right-clicks this mob. Faces the player, hops happily, and emits heart particles.
func on_fed_by_player(feeder_pos: Vector3) -> void:
	if is_hostile():
		return
	var to_player: Vector3 = feeder_pos - (global_position if is_inside_tree() else position)
	to_player.y = 0.0
	if to_player.length_squared() > 0.001:
		_target_yaw = atan2(-to_player.x, -to_player.z)
		rotation.y = _target_yaw

	if is_on_floor():
		velocity.y = hop_velocity * 0.85
	_state = MobState.IDLE
	_state_timer = 2.5
	_spawn_love_particles()


## Called when player interacts (right click) with an item on this mob.
func on_interact_with_item(player: PlayerController, item_id: int) -> bool:
	if is_hostile():
		return false

	var feeder_pos: Vector3 = player.global_position if (player != null and player.is_inside_tree()) else (global_position if is_inside_tree() else position)

	if variant == MobVariant.SHEEP:
		if item_id == InventoryManager.ItemId.SHEARS:
			if not is_sheared:
				is_sheared = true
				if _wool_mesh != null:
					_wool_mesh.visible = false
				if is_inside_tree() and get_tree() != null:
					var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
					if sfx != null and sfx.has_method("play_sfx_at_pos"):
						sfx.play_sfx_at_pos("shears", global_position if is_inside_tree() else position, 1.0)
				if _world_manager != null:
					DroppedItem.spawn_drop(
						_world_manager,
						(global_position if is_inside_tree() else position) + Vector3(0.0, 0.5, 0.0),
						InventoryManager.ItemId.WOOL,
						randi_range(1, 3)
					)
				_spawn_love_particles()
				return true
			return false
		elif item_id == InventoryManager.ItemId.WHEAT:
			if is_sheared:
				is_sheared = false
				if _wool_mesh != null:
					_wool_mesh.visible = true
			on_fed_by_player(feeder_pos)
			return true

	elif variant == MobVariant.COW:
		if item_id == InventoryManager.ItemId.BUCKET:
			if is_inside_tree() and get_tree() != null:
				var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
				if sfx != null and sfx.has_method("play_sfx_at_pos"):
					sfx.play_sfx_at_pos("cow_ambient", global_position if is_inside_tree() else position, 1.0)
			_spawn_love_particles()
			return true
		elif item_id == InventoryManager.ItemId.WHEAT:
			on_fed_by_player(feeder_pos)
			return true

	elif variant == MobVariant.CHICKEN:
		if item_id == InventoryManager.ItemId.WHEAT_SEEDS:
			on_fed_by_player(feeder_pos)
			return true

	elif variant == MobVariant.VILLAGER:
		if is_inside_tree() and get_tree() != null:
			var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
			if sfx != null and sfx.has_method("play_sfx_at_pos"):
				sfx.play_sfx_at_pos("villager_ambient", global_position if is_inside_tree() else position, 1.0)
		on_fed_by_player(feeder_pos)
		if item_id == InventoryManager.ItemId.WHEAT or item_id == InventoryManager.ItemId.POTATO:
			if _world_manager != null:
				DroppedItem.spawn_drop(
					_world_manager,
					(global_position if is_inside_tree() else position) + Vector3(0.0, 0.6, 0.0),
					InventoryManager.ItemId.BREAD,
					1
				)
		return true

	elif item_id == InventoryManager.ItemId.WHEAT or item_id == InventoryManager.ItemId.POTATO:
		on_fed_by_player(feeder_pos)
		return true

	return false


func _spawn_love_particles() -> void:
	if not is_inside_tree():
		return
	var particles := CPUParticles3D.new()
	particles.position = Vector3(0.0, 1.15, 0.0)
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 10
	particles.lifetime = 0.75
	particles.explosiveness = 0.85

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.24, 0.48)

	var box := BoxMesh.new()
	box.size = Vector3(0.14, 0.14, 0.14)
	box.material = mat
	particles.mesh = box

	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.35
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 45.0
	particles.gravity = Vector3(0.0, 1.5, 0.0)
	particles.initial_velocity_min = 0.8
	particles.initial_velocity_max = 1.6

	add_child(particles)
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


func _pick_next_state() -> void:
	if randf() < 0.38:
		_state = MobState.IDLE
		_state_timer = randf_range(1.5, 3.2)
	else:
		_state = MobState.WANDER
		_state_timer = randf_range(2.5, 5.5)
		_target_yaw = randf_range(-PI, PI)


func _animate_limbs(delta: float) -> void:
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if horiz_speed > 0.15:
		var freq: float = 14.0 if (_state == MobState.PANIC or _state == MobState.CHASE) else 8.5
		_anim_time += delta * freq
		var swing: float = sin(_anim_time) * (0.68 if _state != MobState.WANDER else 0.48)

		if variant == MobVariant.ZOMBIE or variant == MobVariant.SKELETON:
			if _legs.size() >= 2:
				_legs[0].rotation.x = swing
				_legs[1].rotation.x = -swing
			if _arms.size() >= 2:
				var arm_base: float = -PI * 0.48
				_arms[0].rotation.x = arm_base + swing * 0.15
				_arms[1].rotation.x = arm_base - swing * 0.15
		elif variant == MobVariant.CREEPER:
			if _legs.size() >= 4:
				_legs[0].rotation.x = swing
				_legs[1].rotation.x = -swing
				_legs[2].rotation.x = -swing
				_legs[3].rotation.x = swing
		elif variant == MobVariant.VILLAGER:
			if _legs.size() >= 2:
				_legs[0].rotation.x = swing
				_legs[1].rotation.x = -swing
		elif variant == MobVariant.COW or variant == MobVariant.PIG or variant == MobVariant.SHEEP:
			if _legs.size() >= 4:
				_legs[0].rotation.x = swing
				_legs[1].rotation.x = -swing
				_legs[2].rotation.x = -swing
				_legs[3].rotation.x = swing
		elif variant == MobVariant.CHICKEN:
			if _legs.size() >= 2:
				_legs[0].rotation.x = swing
				_legs[1].rotation.x = -swing
		elif variant == MobVariant.SPIDER:
			for i in range(_legs.size()):
				var phase: float = float(i) * 0.78
				_legs[i].rotation.z = sin(_anim_time + phase) * 0.22
				_legs[i].rotation.y = cos(_anim_time + phase) * 0.18
	else:
		for leg in _legs:
			leg.rotation.x = lerpf(leg.rotation.x, 0.0, 10.0 * delta)
			leg.rotation.z = lerpf(leg.rotation.z, 0.0, 10.0 * delta)
		for arm in _arms:
			arm.rotation.x = lerpf(arm.rotation.x, -PI * 0.48, 10.0 * delta)

	# Chicken wing flapping when in air
	if variant == MobVariant.CHICKEN:
		if not is_on_floor() and velocity.y < 0.0:
			for i in range(_wings.size()):
				var flap: float = sin(_anim_time * 26.0) * 0.85
				_wings[i].rotation.z = flap if i == 0 else -flap
		else:
			for w in _wings:
				w.rotation.z = lerpf(w.rotation.z, 0.0, 12.0 * delta)


func _build_collision_and_rays() -> void:
	if _col_shape == null:
		_col_shape = CollisionShape3D.new()
		add_child(_col_shape)

	var box := BoxShape3D.new()
	if variant == MobVariant.SPIDER:
		box.size = Vector3(1.35, 0.85, 1.35)
	elif variant == MobVariant.CHICKEN:
		box.size = Vector3(0.48, 0.68, 0.48)
	elif variant == MobVariant.ZOMBIE or variant == MobVariant.SKELETON or variant == MobVariant.CREEPER or variant == MobVariant.VILLAGER:
		box.size = Vector3(0.68, 1.75, 0.68)
	else:
		box.size = Vector3(0.78, 0.95, 0.95)

	_col_shape.shape = box
	_col_shape.position = Vector3(0.0, box.size.y * 0.5, 0.0)

	if _ledge_ray == null:
		_ledge_ray = RayCast3D.new()
		add_child(_ledge_ray)
	_ledge_ray.position = Vector3(0.0, box.size.y * 0.5, -box.size.z * 0.65)
	_ledge_ray.target_position = Vector3(0.0, -2.6, 0.0)
	_ledge_ray.collision_mask = 1

	if _step_ray == null:
		_step_ray = RayCast3D.new()
		add_child(_step_ray)
	_step_ray.position = Vector3(0.0, 0.35, -box.size.z * 0.5)
	_step_ray.target_position = Vector3(0.0, 0.0, -0.48)
	_step_ray.collision_mask = 1


func _build_voxel_model() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualModel"
	add_child(_visual_root)

	var mob_tex_path: String = ""
	match variant:
		MobVariant.ZOMBIE:
			mob_tex_path = "res://assets/textures/entity/zombie.png"
			_primary_color = Color(0.32, 0.58, 0.30)
		MobVariant.SKELETON:
			mob_tex_path = "res://assets/textures/entity/skeleton.png"
			_primary_color = Color(0.86, 0.86, 0.82)
		MobVariant.CREEPER:
			mob_tex_path = "res://assets/textures/entity/creeper.png"
			_primary_color = Color(0.28, 0.72, 0.26)
		MobVariant.SPIDER:
			mob_tex_path = "res://assets/textures/entity/spider.png"
			_primary_color = Color(0.18, 0.17, 0.20)
		MobVariant.COW:
			mob_tex_path = "res://assets/textures/entity/cow.png"
			_primary_color = Color(0.38, 0.25, 0.16)
		MobVariant.PIG:
			mob_tex_path = "res://assets/textures/entity/pig.png"
			_primary_color = Color(0.94, 0.64, 0.68)
		MobVariant.SHEEP:
			mob_tex_path = "res://assets/textures/entity/sheep.png"
			_primary_color = Color(0.92, 0.92, 0.92)
		MobVariant.VILLAGER:
			mob_tex_path = "res://assets/textures/entity/villager.png"
			_primary_color = Color(0.65, 0.45, 0.32)
		MobVariant.CHICKEN:
			mob_tex_path = "res://assets/textures/entity/chicken.png"
			_primary_color = Color(0.96, 0.96, 0.96)

	_mob_mat = StandardMaterial3D.new()
	_mob_mat.roughness = 1.0
	_mob_mat.metallic_specular = 0.0
	_mob_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_mob_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_mob_mat.alpha_scissor_threshold = 0.5
	_mob_mat.albedo_color = Color.WHITE

	var sheet_w: float = 64.0
	var sheet_h: float = 64.0

	var mob_img: Image = TexturePack.load_image(mob_tex_path)
	if mob_img != null and not mob_img.is_empty():
		_mob_mat.albedo_texture = ImageTexture.create_from_image(mob_img)
		if mob_img.get_width() / mob_img.get_height() == 2:
			sheet_h = 32.0
	else:
		_mob_mat.albedo_color = _primary_color

	match variant:
		MobVariant.ZOMBIE:
			_build_zombie_model(sheet_w, sheet_h)
		MobVariant.SKELETON:
			_build_skeleton_model(sheet_w, sheet_h)
		MobVariant.CREEPER:
			_build_creeper_model(sheet_w, sheet_h)
		MobVariant.COW:
			_build_cow_model(sheet_w, sheet_h)
		MobVariant.PIG:
			_build_pig_model(sheet_w, sheet_h)
		MobVariant.SPIDER:
			_build_spider_model(sheet_w, sheet_h)
		MobVariant.SHEEP:
			_build_sheep_model(sheet_w, sheet_h)
		MobVariant.VILLAGER:
			_build_villager_model(sheet_w, sheet_h)
		MobVariant.CHICKEN:
			_build_chicken_model(sheet_w, sheet_h)


func _create_part(
	size: Vector3,
	u0: float, v0: float,
	dx: float, dy: float, dz: float,
	sheet_w: float, sheet_h: float,
	mirror_x: bool = false
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = CuboidMeshBuilder.build_cuboid(size, u0, v0, dx, dy, dz, sheet_w, sheet_h, mirror_x)
	mi.material_override = _mob_mat
	return mi


# ==============================================================================
# MOB MODEL BUILDERS
# ==============================================================================

func _build_zombie_model(sheet_w: float, sheet_h: float) -> void:
	var head := _create_part(Vector3(0.50, 0.50, 0.50), 0, 0, 8, 8, 8, sheet_w, sheet_h)
	head.position = Vector3(0.0, 1.48, 0.0)
	_visual_root.add_child(head)
	_head_node = head

	var torso := _create_part(Vector3(0.50, 0.72, 0.25), 16, 16, 8, 12, 4, sheet_w, sheet_h)
	torso.position = Vector3(0.0, 0.88, 0.0)
	_visual_root.add_child(torso)

	var r_arm_pivot := Node3D.new()
	r_arm_pivot.position = Vector3(0.375, 1.18, 0.0)
	r_arm_pivot.rotation.x = -PI * 0.48
	var r_arm := _create_part(Vector3(0.24, 0.72, 0.24), 40, 16, 4, 12, 4, sheet_w, sheet_h)
	r_arm.position = Vector3(0.0, -0.32, 0.0)
	r_arm_pivot.add_child(r_arm)
	_visual_root.add_child(r_arm_pivot)
	_arms.append(r_arm_pivot)

	var l_arm_pivot := Node3D.new()
	l_arm_pivot.position = Vector3(-0.375, 1.18, 0.0)
	l_arm_pivot.rotation.x = -PI * 0.48
	var l_arm := _create_part(Vector3(0.24, 0.72, 0.24), 40, 16, 4, 12, 4, sheet_w, sheet_h, true)
	l_arm.position = Vector3(0.0, -0.32, 0.0)
	l_arm_pivot.add_child(l_arm)
	_visual_root.add_child(l_arm_pivot)
	_arms.append(l_arm_pivot)

	var r_leg_pivot := Node3D.new()
	r_leg_pivot.position = Vector3(0.125, 0.52, 0.0)
	var r_leg := _create_part(Vector3(0.24, 0.72, 0.24), 0, 16, 4, 12, 4, sheet_w, sheet_h)
	r_leg.position = Vector3(0.0, -0.32, 0.0)
	r_leg_pivot.add_child(r_leg)
	_visual_root.add_child(r_leg_pivot)
	_legs.append(r_leg_pivot)

	var l_leg_pivot := Node3D.new()
	l_leg_pivot.position = Vector3(-0.125, 0.52, 0.0)
	var l_leg := _create_part(Vector3(0.24, 0.72, 0.24), 0, 16, 4, 12, 4, sheet_w, sheet_h, true)
	l_leg.position = Vector3(0.0, -0.32, 0.0)
	l_leg_pivot.add_child(l_leg)
	_visual_root.add_child(l_leg_pivot)
	_legs.append(l_leg_pivot)


func _build_skeleton_model(sheet_w: float, sheet_h: float) -> void:
	var head := _create_part(Vector3(0.50, 0.50, 0.50), 0, 0, 8, 8, 8, sheet_w, sheet_h)
	head.position = Vector3(0.0, 1.48, 0.0)
	_visual_root.add_child(head)
	_head_node = head

	var torso := _create_part(Vector3(0.50, 0.72, 0.25), 16, 16, 8, 12, 4, sheet_w, sheet_h)
	torso.position = Vector3(0.0, 0.88, 0.0)
	_visual_root.add_child(torso)

	var r_arm_pivot := Node3D.new()
	r_arm_pivot.position = Vector3(0.31, 1.18, 0.0)
	r_arm_pivot.rotation.x = -PI * 0.48
	var r_arm := _create_part(Vector3(0.14, 0.72, 0.14), 40, 16, 2, 12, 2, sheet_w, sheet_h)
	r_arm.position = Vector3(0.0, -0.32, 0.0)
	r_arm_pivot.add_child(r_arm)
	_visual_root.add_child(r_arm_pivot)
	_arms.append(r_arm_pivot)

	var l_arm_pivot := Node3D.new()
	l_arm_pivot.position = Vector3(-0.31, 1.18, 0.0)
	l_arm_pivot.rotation.x = -PI * 0.48
	var l_arm := _create_part(Vector3(0.14, 0.72, 0.14), 40, 16, 2, 12, 2, sheet_w, sheet_h, true)
	l_arm.position = Vector3(0.0, -0.32, 0.0)
	l_arm_pivot.add_child(l_arm)

	# 3D Bow held in skeleton's hand
	_bow_mesh = _create_part(Vector3(0.08, 0.62, 0.12), 40, 0, 2, 10, 2, sheet_w, sheet_h)
	_bow_mesh.position = Vector3(0.0, -0.32, -0.16)
	_bow_mesh.rotation.y = deg_to_rad(20.0)
	l_arm_pivot.add_child(_bow_mesh)

	_visual_root.add_child(l_arm_pivot)
	_arms.append(l_arm_pivot)

	var r_leg_pivot := Node3D.new()
	r_leg_pivot.position = Vector3(0.125, 0.52, 0.0)
	var r_leg := _create_part(Vector3(0.14, 0.72, 0.14), 0, 16, 2, 12, 2, sheet_w, sheet_h)
	r_leg.position = Vector3(0.0, -0.32, 0.0)
	r_leg_pivot.add_child(r_leg)
	_visual_root.add_child(r_leg_pivot)
	_legs.append(r_leg_pivot)

	var l_leg_pivot := Node3D.new()
	l_leg_pivot.position = Vector3(-0.125, 0.52, 0.0)
	var l_leg := _create_part(Vector3(0.14, 0.72, 0.14), 0, 16, 2, 12, 2, sheet_w, sheet_h, true)
	l_leg.position = Vector3(0.0, -0.32, 0.0)
	l_leg_pivot.add_child(l_leg)
	_visual_root.add_child(l_leg_pivot)
	_legs.append(l_leg_pivot)


func _build_creeper_model(sheet_w: float, sheet_h: float) -> void:
	var head := _create_part(Vector3(0.50, 0.50, 0.50), 0, 0, 8, 8, 8, sheet_w, sheet_h)
	head.position = Vector3(0.0, 1.42, 0.0)
	_visual_root.add_child(head)
	_head_node = head

	var torso := _create_part(Vector3(0.50, 0.72, 0.25), 16, 16, 8, 12, 4, sheet_w, sheet_h)
	torso.position = Vector3(0.0, 0.82, 0.0)
	_visual_root.add_child(torso)

	var foot_coords: Array[Vector3] = [
		Vector3(-0.13, 0.36, -0.16),
		Vector3(0.13, 0.36, -0.16),
		Vector3(-0.13, 0.36, 0.16),
		Vector3(0.13, 0.36, 0.16)
	]
	for fc in foot_coords:
		var pivot := Node3D.new()
		pivot.position = fc
		var foot := _create_part(Vector3(0.24, 0.36, 0.24), 0, 16, 4, 6, 4, sheet_w, sheet_h)
		foot.position = Vector3(0.0, -0.18, 0.0)
		pivot.add_child(foot)
		_visual_root.add_child(pivot)
		_legs.append(pivot)


func _build_cow_model(sheet_w: float, sheet_h: float) -> void:
	var head := _create_part(Vector3(0.48, 0.48, 0.36), 0, 0, 8, 8, 6, sheet_w, sheet_h)
	head.position = Vector3(0.0, 0.88, -0.52)
	_visual_root.add_child(head)
	_head_node = head

	for side in [-1.0, 1.0]:
		var horn := _create_part(Vector3(0.06, 0.18, 0.06), 22, 0, 1, 3, 1, sheet_w, sheet_h)
		horn.position = Vector3(side * 0.25, 1.15, -0.48)
		_visual_root.add_child(horn)

	var body := _create_part(Vector3(0.72, 0.60, 1.08), 18, 4, 12, 18, 10, sheet_w, sheet_h)
	body.position = Vector3(0.0, 0.72, 0.0)
	_visual_root.add_child(body)

	var udders := _create_part(Vector3(0.24, 0.36, 0.12), 52, 0, 4, 6, 2, sheet_w, sheet_h)
	udders.position = Vector3(0.0, 0.44, 0.22)
	_visual_root.add_child(udders)

	var leg_coords: Array[Vector3] = [
		Vector3(-0.20, 0.60, -0.36),
		Vector3(0.20, 0.60, -0.36),
		Vector3(-0.20, 0.60, 0.36),
		Vector3(0.20, 0.60, 0.36)
	]
	for lc in leg_coords:
		var pivot := Node3D.new()
		pivot.position = lc
		var leg := _create_part(Vector3(0.22, 0.60, 0.22), 0, 16, 4, 12, 4, sheet_w, sheet_h)
		leg.position = Vector3(0.0, -0.30, 0.0)
		pivot.add_child(leg)
		_visual_root.add_child(pivot)
		_legs.append(pivot)


func _build_pig_model(sheet_w: float, sheet_h: float) -> void:
	var head := _create_part(Vector3(0.48, 0.48, 0.48), 0, 0, 8, 8, 8, sheet_w, sheet_h)
	head.position = Vector3(0.0, 0.68, -0.42)
	_visual_root.add_child(head)
	_head_node = head

	var snout := _create_part(Vector3(0.24, 0.18, 0.08), 16, 16, 4, 3, 1, sheet_w, sheet_h)
	snout.position = Vector3(0.0, 0.58, -0.68)
	_visual_root.add_child(snout)

	var body := _create_part(Vector3(0.60, 0.48, 0.96), 28, 8, 10, 16, 8, sheet_w, sheet_h)
	body.position = Vector3(0.0, 0.54, 0.0)
	_visual_root.add_child(body)

	var leg_coords: Array[Vector3] = [
		Vector3(-0.18, 0.36, -0.26),
		Vector3(0.18, 0.36, -0.26),
		Vector3(-0.18, 0.36, 0.26),
		Vector3(0.18, 0.36, 0.26)
	]
	for lc in leg_coords:
		var pivot := Node3D.new()
		pivot.position = lc
		var leg := _create_part(Vector3(0.22, 0.36, 0.22), 0, 16, 4, 6, 4, sheet_w, sheet_h)
		leg.position = Vector3(0.0, -0.18, 0.0)
		pivot.add_child(leg)
		_visual_root.add_child(pivot)
		_legs.append(pivot)


func _build_spider_model(sheet_w: float, sheet_h: float) -> void:
	var head := _create_part(Vector3(0.46, 0.46, 0.46), 32, 4, 8, 8, 8, sheet_w, sheet_h)
	head.position = Vector3(0.0, 0.44, -0.38)
	_visual_root.add_child(head)
	_head_node = head

	var neck := _create_part(Vector3(0.36, 0.36, 0.36), 0, 0, 6, 6, 6, sheet_w, sheet_h)
	neck.position = Vector3(0.0, 0.40, -0.05)
	_visual_root.add_child(neck)

	var abdomen := _create_part(Vector3(0.60, 0.48, 0.72), 0, 12, 10, 8, 12, sheet_w, sheet_h)
	abdomen.position = Vector3(0.0, 0.46, 0.42)
	_visual_root.add_child(abdomen)

	var z_positions: Array[float] = [-0.18, -0.06, 0.06, 0.18]
	for i in range(4):
		var z_pos: float = z_positions[i]
		var r_pivot := Node3D.new()
		r_pivot.position = Vector3(0.22, 0.38, z_pos)
		r_pivot.rotation.z = deg_to_rad(-24.0)
		r_pivot.rotation.y = deg_to_rad(-35.0 + float(i) * 22.0)
		var r_mesh := _create_part(Vector3(0.68, 0.10, 0.10), 18, 0, 12, 2, 2, sheet_w, sheet_h)
		r_mesh.position = Vector3(0.34, 0.0, 0.0)
		r_pivot.add_child(r_mesh)
		_visual_root.add_child(r_pivot)
		_legs.append(r_pivot)

		var l_pivot := Node3D.new()
		l_pivot.position = Vector3(-0.22, 0.38, z_pos)
		l_pivot.rotation.z = deg_to_rad(24.0)
		l_pivot.rotation.y = deg_to_rad(35.0 - float(i) * 22.0)
		var l_mesh := _create_part(Vector3(0.68, 0.10, 0.10), 18, 0, 12, 2, 2, sheet_w, sheet_h, true)
		l_mesh.position = Vector3(-0.34, 0.0, 0.0)
		l_pivot.add_child(l_mesh)
		_visual_root.add_child(l_pivot)
		_legs.append(l_pivot)


func _build_sheep_model(sheet_w: float, sheet_h: float) -> void:
	var head := _create_part(Vector3(0.40, 0.40, 0.48), 0, 0, 6, 6, 8, sheet_w, sheet_h)
	head.position = Vector3(0.0, 0.78, -0.48)
	_visual_root.add_child(head)
	_head_node = head

	var body := _create_part(Vector3(0.68, 0.58, 0.98), 28, 8, 12, 18, 8, sheet_w, sheet_h)
	body.position = Vector3(0.0, 0.62, 0.0)
	_visual_root.add_child(body)

	# Fluffy wool fleece layer covering body
	_wool_mesh = _create_part(Vector3(0.76, 0.66, 1.06), 28, 8, 12, 18, 8, sheet_w, sheet_h)
	_wool_mesh.position = Vector3(0.0, 0.62, 0.0)
	_visual_root.add_child(_wool_mesh)
	_wool_mesh.visible = not is_sheared

	var leg_coords: Array[Vector3] = [
		Vector3(-0.18, 0.52, -0.32),
		Vector3(0.18, 0.52, -0.32),
		Vector3(-0.18, 0.52, 0.32),
		Vector3(0.18, 0.52, 0.32)
	]
	for lc in leg_coords:
		var pivot := Node3D.new()
		pivot.position = lc
		var leg := _create_part(Vector3(0.20, 0.52, 0.20), 0, 16, 4, 12, 4, sheet_w, sheet_h)
		leg.position = Vector3(0.0, -0.26, 0.0)
		pivot.add_child(leg)
		_visual_root.add_child(pivot)
		_legs.append(pivot)


func _build_chicken_model(sheet_w: float, sheet_h: float) -> void:
	var head := _create_part(Vector3(0.24, 0.32, 0.24), 0, 0, 3, 4, 3, sheet_w, sheet_h)
	head.position = Vector3(0.0, 0.54, -0.22)
	_visual_root.add_child(head)
	_head_node = head

	var beak := _create_part(Vector3(0.18, 0.12, 0.14), 14, 0, 4, 2, 2, sheet_w, sheet_h)
	beak.position = Vector3(0.0, 0.50, -0.36)
	_visual_root.add_child(beak)

	var wattle := _create_part(Vector3(0.10, 0.16, 0.10), 14, 4, 2, 4, 2, sheet_w, sheet_h)
	wattle.position = Vector3(0.0, 0.38, -0.28)
	_visual_root.add_child(wattle)

	var body := _create_part(Vector3(0.36, 0.36, 0.48), 0, 9, 6, 8, 6, sheet_w, sheet_h)
	body.position = Vector3(0.0, 0.36, 0.0)
	_visual_root.add_child(body)

	var r_wing_pivot := Node3D.new()
	r_wing_pivot.position = Vector3(0.20, 0.42, 0.0)
	var r_wing := _create_part(Vector3(0.06, 0.24, 0.36), 24, 13, 1, 4, 6, sheet_w, sheet_h)
	r_wing.position = Vector3(0.0, -0.12, 0.0)
	r_wing_pivot.add_child(r_wing)
	_visual_root.add_child(r_wing_pivot)
	_wings.append(r_wing_pivot)

	var l_wing_pivot := Node3D.new()
	l_wing_pivot.position = Vector3(-0.20, 0.42, 0.0)
	var l_wing := _create_part(Vector3(0.06, 0.24, 0.36), 24, 13, 1, 4, 6, sheet_w, sheet_h, true)
	l_wing.position = Vector3(0.0, -0.12, 0.0)
	l_wing_pivot.add_child(l_wing)
	_visual_root.add_child(l_wing_pivot)
	_wings.append(l_wing_pivot)

	var r_leg_pivot := Node3D.new()
	r_leg_pivot.position = Vector3(0.10, 0.24, 0.0)
	var r_leg := _create_part(Vector3(0.08, 0.24, 0.08), 26, 0, 3, 5, 3, sheet_w, sheet_h)
	r_leg.position = Vector3(0.0, -0.12, 0.0)
	r_leg_pivot.add_child(r_leg)
	_visual_root.add_child(r_leg_pivot)
	_legs.append(r_leg_pivot)

	var l_leg_pivot := Node3D.new()
	l_leg_pivot.position = Vector3(-0.10, 0.24, 0.0)
	var l_leg := _create_part(Vector3(0.08, 0.24, 0.08), 26, 0, 3, 5, 3, sheet_w, sheet_h, true)
	l_leg.position = Vector3(0.0, -0.12, 0.0)
	l_leg_pivot.add_child(l_leg)
	_visual_root.add_child(l_leg_pivot)
	_legs.append(l_leg_pivot)


func _build_villager_model(sheet_w: float, sheet_h: float) -> void:
	var head := _create_part(Vector3(0.50, 0.58, 0.50), 0, 0, 8, 10, 8, sheet_w, sheet_h)
	head.position = Vector3(0.0, 1.45, 0.0)
	_visual_root.add_child(head)
	_head_node = head

	var nose := _create_part(Vector3(0.12, 0.24, 0.12), 24, 0, 2, 4, 2, sheet_w, sheet_h)
	nose.position = Vector3(0.0, 1.32, -0.31)
	_visual_root.add_child(nose)

	var body := _create_part(Vector3(0.52, 0.74, 0.36), 16, 20, 8, 12, 6, sheet_w, sheet_h)
	body.position = Vector3(0.0, 0.82, 0.0)
	_visual_root.add_child(body)

	var arms := _create_part(Vector3(0.60, 0.36, 0.30), 40, 38, 10, 8, 4, sheet_w, sheet_h)
	arms.position = Vector3(0.0, 0.85, -0.16)
	_visual_root.add_child(arms)

	var r_leg_pivot := Node3D.new()
	r_leg_pivot.position = Vector3(0.13, 0.45, 0.0)
	var r_leg := _create_part(Vector3(0.22, 0.65, 0.22), 0, 22, 4, 12, 4, sheet_w, sheet_h)
	r_leg.position = Vector3(0.0, -0.25, 0.0)
	r_leg_pivot.add_child(r_leg)
	_visual_root.add_child(r_leg_pivot)
	_legs.append(r_leg_pivot)

	var l_leg_pivot := Node3D.new()
	l_leg_pivot.position = Vector3(-0.13, 0.45, 0.0)
	var l_leg := _create_part(Vector3(0.22, 0.65, 0.22), 0, 22, 4, 12, 4, sheet_w, sheet_h, true)
	l_leg.position = Vector3(0.0, -0.25, 0.0)
	l_leg_pivot.add_child(l_leg)
	_visual_root.add_child(l_leg_pivot)
	_legs.append(l_leg_pivot)
