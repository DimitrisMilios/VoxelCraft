class_name PassiveMob
extends CharacterBody3D
## Autonomous voxel mob supporting both Passive animals (Pig, Cow) and
## Hostile night/cave monsters (Zombie, Skeleton, Creeper, Spider) with
## health, weapon damage, 3D loot drops, melee/explosion combat, and water buoyancy.

enum MobState {
	IDLE,
	WANDER,
	PANIC,
	CHASE,
}

enum MobVariant {
	PIG = 0,
	COW = 1,
	ZOMBIE = 2,
	SKELETON = 3,
	CREEPER = 4,
	SPIDER = 5,
}

@export var move_speed: float = 2.1
@export var panic_speed: float = 5.2
@export var hop_velocity: float = 6.5
@export var gravity_multiplier: float = 1.8
@export var variant: MobVariant = MobVariant.PIG

var health: int = 10
var max_health: int = 10

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _state: MobState = MobState.IDLE
var _state_timer: float = 2.0
var _target_yaw: float = 0.0
var _anim_time: float = 0.0
var _hurt_flash_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _creeper_fuse: float = 0.0
var _sun_burn_timer: float = 0.0

var _visual_root: Node3D = null
var _legs: Array[Node3D] = []
var _ledge_ray: RayCast3D = null
var _step_ray: RayCast3D = null
var _body_mat: StandardMaterial3D = null
var _accent_mat: StandardMaterial3D = null
var _primary_color: Color = Color.WHITE
var _accent_color: Color = Color.WHITE
var _world_manager: WorldManager = null
var _player: PlayerController = null
var _day_night: DayNightCycle = null


func is_hostile() -> bool:
	return int(variant) >= int(MobVariant.ZOMBIE)


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	max_health = 20 if is_hostile() else 10
	if variant == MobVariant.SPIDER:
		max_health = 16
		move_speed = 3.8
	elif is_hostile():
		move_speed = 3.1
	health = max_health

	_build_collision_and_rays()
	_build_voxel_model()
	_pick_next_state()
	call_deferred("_resolve_refs")


func _resolve_refs() -> void:
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	_player = get_tree().get_first_node_in_group("player") as PlayerController
	_day_night = get_tree().get_first_node_in_group("day_night_cycle") as DayNightCycle


func _physics_process(delta: float) -> void:
	if _hurt_flash_timer > 0.0:
		_hurt_flash_timer = maxf(0.0, _hurt_flash_timer - delta)
		if _hurt_flash_timer <= 0.0 and _body_mat != null and _accent_mat != null:
			_body_mat.albedo_color = _primary_color
			_accent_mat.albedo_color = _accent_color

	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	# Water buoyancy for mobs so animals and monsters swim and drift in currents
	var in_water: bool = false
	if _world_manager != null:
		var depth: float = _world_manager.get_water_submersion_depth(global_position)
		if depth > 0.25:
			in_water = true
			velocity.y = move_toward(velocity.y, 1.8, 10.0 * delta)
			var flow: Vector3 = _world_manager.get_water_flow_vector(global_position)
			velocity.x += flow.x * 1.8 * delta
			velocity.z += flow.z * 1.8 * delta

	if not in_water and not is_on_floor():
		velocity.y -= _gravity * gravity_multiplier * delta

	if is_hostile():
		_process_hostile_ai(delta)
	else:
		_state_timer -= delta
		if _state_timer <= 0.0:
			_pick_next_state()

	if _state == MobState.WANDER or _state == MobState.PANIC or _state == MobState.CHASE:
		var active_speed: float = move_speed
		if _state == MobState.PANIC:
			active_speed = panic_speed
		elif _state == MobState.CHASE:
			active_speed = move_speed * 1.18

		var turn_rate: float = 10.0 if (_state == MobState.PANIC or _state == MobState.CHASE) else 6.0
		rotation.y = lerp_angle(rotation.y, _target_yaw, turn_rate * delta)

		var forward: Vector3 = -global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()

		# Ledge avoidance for passive wandering
		if _state == MobState.WANDER and is_on_floor() and _ledge_ray != null and not _ledge_ray.is_colliding():
			_target_yaw += PI * 0.75
		else:
			velocity.x = move_toward(velocity.x, forward.x * active_speed, 14.0 * delta)
			velocity.z = move_toward(velocity.z, forward.z * active_speed, 14.0 * delta)

		# Spiders climb walls; other mobs hop up 1-block steps
		if variant == MobVariant.SPIDER and is_on_wall():
			velocity.y = 3.8
		elif is_on_floor() and _step_ray != null and _step_ray.is_colliding():
			velocity.y = hop_velocity
	else:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)

	move_and_slide()
	_animate_legs(delta)


func _process_hostile_ai(delta: float) -> void:
	# Zombies and Skeletons burn in bright daylight
	if (variant == MobVariant.ZOMBIE or variant == MobVariant.SKELETON) and _day_night != null:
		if _day_night.time_of_day > 0.27 and _day_night.time_of_day < 0.73:
			_sun_burn_timer += delta
			if _sun_burn_timer >= 1.5:
				_sun_burn_timer = 0.0
				on_hit_by_player(global_position + Vector3(0.0, 1.0, 0.0), 3)
				if health <= 0:
					return

	if _player == null or not is_instance_valid(_player) or _player.is_flying:
		_state_timer -= delta
		if _state_timer <= 0.0:
			_pick_next_state()
		return

	var to_player: Vector3 = _player.global_position - global_position
	var dist: float = to_player.length()

	if dist <= 16.5:
		_state = MobState.CHASE
		_target_yaw = atan2(-to_player.x, -to_player.z)

		if variant == MobVariant.CREEPER:
			if dist <= 2.8:
				_creeper_fuse += delta
				var flash: bool = (int(_creeper_fuse * 10.0) % 2 == 0)
				if _body_mat != null:
					_body_mat.albedo_color = Color(1.0, 1.0, 1.0) if flash else _primary_color
				_visual_root.scale = Vector3.ONE * (1.0 + _creeper_fuse * 0.16)
				if _creeper_fuse >= 1.45:
					_trigger_creeper_explosion()
					return
			elif _creeper_fuse > 0.0:
				_creeper_fuse = maxf(0.0, _creeper_fuse - delta * 1.5)
				_visual_root.scale = Vector3.ONE
		else:
			var attack_reach: float = 2.6 if variant == MobVariant.SKELETON else 1.45
			if dist <= attack_reach and _attack_cooldown <= 0.0:
				_attack_cooldown = 1.15
				var dmg: int = 3 if variant != MobVariant.SPIDER else 2
				_player.take_damage(dmg)
				var kb: Vector3 = to_player.normalized() * 4.5 + Vector3(0.0, 2.8, 0.0)
				_player.velocity += kb
	else:
		_creeper_fuse = 0.0
		_visual_root.scale = Vector3.ONE
		_state_timer -= delta
		if _state_timer <= 0.0:
			_pick_next_state()


func _trigger_creeper_explosion() -> void:
	if _world_manager != null:
		var center := Vector3i(floori(global_position.x), floori(global_position.y + 0.5), floori(global_position.z))
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					if dx * dx + dy * dy + dz * dz <= 4:
						var bpos := center + Vector3i(dx, dy, dz)
						if bpos.y > 1:
							var bid: int = _world_manager.get_block_world(bpos)
							if BlockRegistry.is_solid(bid):
								_world_manager.set_block_world(bpos, BlockRegistry.BlockId.AIR)
								if randf() < 0.25:
									var drop_id: int = InventoryManager.get_dropped_item_for_block(bid, InventoryManager.ItemId.DIAMOND_PICKAXE)
									if drop_id > 0:
										DroppedItem.spawn_drop(_world_manager, Vector3(bpos) + Vector3(0.5, 0.5, 0.5), drop_id, 1)

	if _player != null and is_instance_valid(_player):
		var dist: float = global_position.distance_to(_player.global_position)
		if dist <= 4.5:
			var dmg: int = maxi(2, int(round((4.5 - dist) * 2.5)))
			_player.take_damage(dmg)
			var push: Vector3 = (_player.global_position - global_position).normalized() * 8.5 + Vector3(0.0, 5.0, 0.0)
			_player.velocity += push

	queue_free()


## Called when the player left-clicks this mob. Applies weapon damage, knockback, and spawns loot on death.
func on_hit_by_player(attacker_pos: Vector3, damage: int = 2) -> void:
	var away_dir: Vector3 = global_position - attacker_pos
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

	if _body_mat != null and _accent_mat != null:
		_body_mat.albedo_color = Color(1.0, 0.22, 0.22)
		_accent_mat.albedo_color = Color(1.0, 0.32, 0.32)

	if health <= 0:
		_die_and_drop_loot()


func _die_and_drop_loot() -> void:
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
				drop_id = InventoryManager.ItemId.COAL if randf() < 0.4 else InventoryManager.ItemId.STICK
			MobVariant.CREEPER:
				drop_id = InventoryManager.ItemId.GUNPOWDER
			MobVariant.SPIDER:
				drop_id = InventoryManager.ItemId.STICK

		if drop_id > 0:
			DroppedItem.spawn_drop(
				_world_manager,
				global_position + Vector3(0.0, 0.45, 0.0),
				drop_id,
				drop_cnt
			)
	queue_free()


## Called when the player right-clicks this mob. Faces the player, hops happily, and emits heart particles.
func on_fed_by_player(feeder_pos: Vector3) -> void:
	if is_hostile():
		return
	var to_player: Vector3 = feeder_pos - global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.001:
		_target_yaw = atan2(-to_player.x, -to_player.z)
		rotation.y = _target_yaw

	if is_on_floor():
		velocity.y = hop_velocity * 0.85
	_state = MobState.IDLE
	_state_timer = 2.5
	_spawn_love_particles()


func _spawn_love_particles() -> void:
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


func _animate_legs(delta: float) -> void:
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if horiz_speed > 0.15:
		var freq: float = 15.0 if (_state == MobState.PANIC or _state == MobState.CHASE) else 9.0
		_anim_time += delta * freq
		var swing: float = sin(_anim_time) * (0.72 if _state != MobState.WANDER else 0.52)
		for i in range(_legs.size()):
			var sign_dir: float = 1.0 if (i % 2 == 0) else -1.0
			_legs[i].rotation.x = swing * sign_dir
	else:
		for leg in _legs:
			leg.rotation.x = lerpf(leg.rotation.x, 0.0, 10.0 * delta)


func _build_collision_and_rays() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.72, 1.65, 0.72) if (variant == MobVariant.ZOMBIE or variant == MobVariant.SKELETON or variant == MobVariant.CREEPER) else Vector3(0.75, 0.95, 0.95)
	col.shape = box
	col.position = Vector3(0.0, box.size.y * 0.5, 0.0)
	add_child(col)

	_ledge_ray = RayCast3D.new()
	_ledge_ray.position = Vector3(0.0, 0.8, -0.85)
	_ledge_ray.target_position = Vector3(0.0, -2.6, 0.0)
	_ledge_ray.collision_mask = 1
	add_child(_ledge_ray)

	_step_ray = RayCast3D.new()
	_step_ray.position = Vector3(0.0, 0.35, -0.4)
	_step_ray.target_position = Vector3(0.0, 0.0, -0.48)
	_step_ray.collision_mask = 1
	add_child(_step_ray)


func _build_voxel_model() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualModel"
	add_child(_visual_root)

	match variant:
		MobVariant.PIG:
			_primary_color = Color(0.94, 0.64, 0.68)
			_accent_color = Color(0.85, 0.48, 0.54)
		MobVariant.COW:
			_primary_color = Color(0.38, 0.25, 0.16)
			_accent_color = Color(0.92, 0.92, 0.90)
		MobVariant.ZOMBIE:
			_primary_color = Color(0.32, 0.58, 0.30) # Green zombie skin
			_accent_color = Color(0.20, 0.48, 0.68)  # Blue tunic
		MobVariant.SKELETON:
			_primary_color = Color(0.86, 0.86, 0.82) # Bone white
			_accent_color = Color(0.68, 0.68, 0.64)
		MobVariant.CREEPER:
			_primary_color = Color(0.28, 0.72, 0.26) # Creeper green
			_accent_color = Color(0.18, 0.52, 0.18)
		MobVariant.SPIDER:
			_primary_color = Color(0.18, 0.17, 0.20) # Dark arachnid grey
			_accent_color = Color(0.88, 0.12, 0.14)  # Glowing red eyes

	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = _primary_color
	_body_mat.roughness = 0.9

	_accent_mat = StandardMaterial3D.new()
	_accent_mat.albedo_color = _accent_color
	_accent_mat.roughness = 0.9

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.95, 0.12, 0.12) if variant == MobVariant.SPIDER else Color(0.08, 0.08, 0.08)

	if variant == MobVariant.ZOMBIE or variant == MobVariant.SKELETON:
		# Upright Bipedal Monster (Zombie / Skeleton)
		var torso := _make_box_part(Vector3(0.48, 0.68, 0.26), _accent_mat)
		torso.position = Vector3(0.0, 0.96, 0.0)
		_visual_root.add_child(torso)

		var head := _make_box_part(Vector3(0.46, 0.46, 0.46), _primary_color_mat())
		head.position = Vector3(0.0, 1.54, 0.0)
		_visual_root.add_child(head)

		for side in [-1.0, 1.0]:
			var eye := _make_box_part(Vector3(0.08, 0.07, 0.05), eye_mat)
			eye.position = Vector3(side * 0.12, 1.56, -0.24)
			_visual_root.add_child(eye)

			# Outstretched zombie/skeleton arms
			var arm := _make_box_part(Vector3(0.18, 0.18, 0.58), _primary_color_mat())
			arm.position = Vector3(side * 0.34, 1.20, -0.24)
			_visual_root.add_child(arm)

			var leg_pivot := Node3D.new()
			leg_pivot.position = Vector3(side * 0.13, 0.62, 0.0)
			var leg_mesh := _make_box_part(Vector3(0.20, 0.62, 0.20), _accent_mat)
			leg_mesh.position = Vector3(0.0, -0.31, 0.0)
			leg_pivot.add_child(leg_mesh)
			_visual_root.add_child(leg_pivot)
			_legs.append(leg_pivot)
		return

	if variant == MobVariant.CREEPER:
		# Classic Tall Armless Creeper on 4 Short Feet
		var torso := _make_box_part(Vector3(0.46, 0.78, 0.28), _body_mat)
		torso.position = Vector3(0.0, 0.78, 0.0)
		_visual_root.add_child(torso)

		var head := _make_box_part(Vector3(0.48, 0.48, 0.48), _body_mat)
		head.position = Vector3(0.0, 1.42, 0.0)
		_visual_root.add_child(head)

		for side in [-1.0, 1.0]:
			var eye := _make_box_part(Vector3(0.10, 0.10, 0.05), eye_mat)
			eye.position = Vector3(side * 0.12, 1.48, -0.25)
			_visual_root.add_child(eye)
		var mouth := _make_box_part(Vector3(0.20, 0.14, 0.05), eye_mat)
		mouth.position = Vector3(0.0, 1.32, -0.25)
		_visual_root.add_child(mouth)

		var foot_offsets: Array[Vector3] = [
			Vector3(-0.16, 0.38, -0.18),
			Vector3(0.16, 0.38, -0.18),
			Vector3(-0.16, 0.38, 0.18),
			Vector3(0.16, 0.38, 0.18),
		]
		for f_off in foot_offsets:
			var pivot := Node3D.new()
			pivot.position = f_off
			var f_mesh := _make_box_part(Vector3(0.20, 0.38, 0.20), _accent_mat)
			f_mesh.position = Vector3(0.0, -0.19, 0.0)
			pivot.add_child(f_mesh)
			_visual_root.add_child(pivot)
			_legs.append(pivot)
		return

	# Quadruped / Spider Model
	var body := _make_box_part(Vector3(0.62, 0.48, 0.88), _body_mat)
	body.position = Vector3(0.0, 0.52, 0.0)
	_visual_root.add_child(body)

	var head := _make_box_part(Vector3(0.46, 0.44, 0.44), _body_mat)
	head.position = Vector3(0.0, 0.72, -0.52)
	_visual_root.add_child(head)

	var snout := _make_box_part(Vector3(0.24, 0.18, 0.12), _accent_mat)
	snout.position = Vector3(0.0, 0.66, -0.78)
	_visual_root.add_child(snout)

	var left_eye := _make_box_part(Vector3(0.08, 0.08, 0.05), eye_mat)
	left_eye.position = Vector3(-0.14, 0.78, -0.74)
	_visual_root.add_child(left_eye)

	var right_eye := _make_box_part(Vector3(0.08, 0.08, 0.05), eye_mat)
	right_eye.position = Vector3(0.14, 0.78, -0.74)
	_visual_root.add_child(right_eye)

	var leg_offsets: Array[Vector3] = [
		Vector3(-0.20, 0.28, -0.28),
		Vector3(0.20, 0.28, -0.28),
		Vector3(-0.20, 0.28, 0.28),
		Vector3(0.20, 0.28, 0.28),
	]
	for offset in leg_offsets:
		var pivot := Node3D.new()
		pivot.position = offset
		var leg_mesh := _make_box_part(Vector3(0.18, 0.28, 0.18), _accent_mat)
		leg_mesh.position = Vector3(0.0, -0.14, 0.0)
		pivot.add_child(leg_mesh)
		_visual_root.add_child(pivot)
		_legs.append(pivot)


func _primary_color_mat() -> StandardMaterial3D:
	return _body_mat


func _make_box_part(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	return mi
