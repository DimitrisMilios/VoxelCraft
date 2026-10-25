class_name PassiveMob
extends CharacterBody3D
## Autonomous voxel mob supporting both Passive animals (Pig, Cow) and
## Hostile night/cave monsters (Zombie, Skeleton, Creeper, Spider) with
## authentic Faithful 64x UV-mapped cuboid models, health, weapon damage,
## 3D loot drops, melee/explosion combat, and water buoyancy.

const CuboidMeshBuilder = preload("res://scripts/entities/cuboid_mesh_builder.gd")

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
var _ambient_sound_timer: float = randf_range(3.0, 8.0)

var _visual_root: Node3D = null
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _ledge_ray: RayCast3D = null
var _step_ray: RayCast3D = null
var _mob_mat: StandardMaterial3D = null
var _primary_color: Color = Color.WHITE
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
	if get_tree() == null:
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

	_ambient_sound_timer -= delta
	if _ambient_sound_timer <= 0.0:
		_ambient_sound_timer = randf_range(5.0, 12.0)
		_play_ambient_vocal()

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
	_animate_limbs(delta)


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
				if _creeper_fuse == 0.0:
					var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
					if sfx != null and sfx.has_method("play_sfx_at_pos"):
						sfx.play_sfx_at_pos("creeper_fuse", global_position, 0.0)
				_creeper_fuse += delta
				var flash: bool = (int(_creeper_fuse * 10.0) % 2 == 0)
				if _mob_mat != null:
					_mob_mat.albedo_color = Color(2.0, 2.0, 2.0) if flash else Color.WHITE
				var swell: float = 1.0 + (_creeper_fuse / 1.5) * 0.24
				_visual_root.scale = Vector3(swell, swell, swell)
				if _creeper_fuse >= 1.45:
					_trigger_creeper_explosion()
					return
			elif _creeper_fuse > 0.0:
				_creeper_fuse = maxf(0.0, _creeper_fuse - delta * 1.5)
				_visual_root.scale = Vector3.ONE
				if _mob_mat != null:
					_mob_mat.albedo_color = Color.WHITE
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
		if _mob_mat != null and _hurt_flash_timer <= 0.0:
			_mob_mat.albedo_color = Color.WHITE
		_state_timer -= delta
		if _state_timer <= 0.0:
			_pick_next_state()


func _trigger_creeper_explosion() -> void:
	if get_tree() != null:
		var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
		if sfx != null and sfx.has_method("play_sfx_at_pos"):
			sfx.play_sfx_at_pos("creeper_explode", global_position, 4.0, 1.0, 48.0)

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

	if _mob_mat != null:
		_mob_mat.albedo_color = Color(1.0, 0.32, 0.32)

	if get_tree() != null:
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
			if not hurt_sfx.is_empty():
				sfx.play_sfx_at_pos(hurt_sfx, current_pos, 1.0)

	if health <= 0:
		_die_and_drop_loot()


func _die_and_drop_loot() -> void:
	if get_tree() != null:
		var sfx: Node = get_tree().get_first_node_in_group("sfx_player")
		if sfx != null and sfx.has_method("play_sfx_at_pos"):
			var death_sfx := ""
			match variant:
				MobVariant.ZOMBIE: death_sfx = "zombie_death"
				MobVariant.SKELETON: death_sfx = "skeleton_death"
				MobVariant.PIG: death_sfx = "pig_hurt"
				MobVariant.COW: death_sfx = "cow_hurt"
				MobVariant.SPIDER: death_sfx = "spider_hurt"
			if not death_sfx.is_empty():
				sfx.play_sfx_at_pos(death_sfx, global_position if is_inside_tree() else position, 2.0)

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


func _play_ambient_vocal() -> void:
	if get_tree() == null:
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
	if not sfx_name.is_empty():
		sfx.play_sfx_at_pos(sfx_name, global_position if is_inside_tree() else position, -1.5, 1.0, 24.0)


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


func _animate_limbs(delta: float) -> void:
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if horiz_speed > 0.15:
		var freq: float = 14.0 if (_state == MobState.PANIC or _state == MobState.CHASE) else 8.5
		_anim_time += delta * freq
		var swing: float = sin(_anim_time) * (0.68 if _state != MobState.WANDER else 0.48)

		if variant == MobVariant.ZOMBIE or variant == MobVariant.SKELETON:
			# 2 Legs swing in opposite phase
			if _legs.size() >= 2:
				_legs[0].rotation.x = swing
				_legs[1].rotation.x = -swing
			# Arms sway gently while held outstretched
			if _arms.size() >= 2:
				var arm_base: float = -PI * 0.48
				_arms[0].rotation.x = arm_base + swing * 0.15
				_arms[1].rotation.x = arm_base - swing * 0.15
		elif variant == MobVariant.CREEPER:
			# Diagonal pairs swing together
			if _legs.size() >= 4:
				_legs[0].rotation.x = swing
				_legs[1].rotation.x = -swing
				_legs[2].rotation.x = -swing
				_legs[3].rotation.x = swing
		elif variant == MobVariant.COW or variant == MobVariant.PIG:
			# Quadruped walk cycle
			if _legs.size() >= 4:
				_legs[0].rotation.x = swing
				_legs[1].rotation.x = -swing
				_legs[2].rotation.x = -swing
				_legs[3].rotation.x = swing
		elif variant == MobVariant.SPIDER:
			# Spider 8-leg crawling ripple
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


func _build_collision_and_rays() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.68, 1.75, 0.68) if (variant == MobVariant.ZOMBIE or variant == MobVariant.SKELETON or variant == MobVariant.CREEPER) else Vector3(0.78, 0.95, 0.95)
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
	# Head (8x8x8 at 0, 0)
	var head := _create_part(Vector3(0.50, 0.50, 0.50), 0, 0, 8, 8, 8, sheet_w, sheet_h)
	head.position = Vector3(0.0, 1.48, 0.0)
	_visual_root.add_child(head)

	# Torso (8x12x4 at 16, 16)
	var torso := _create_part(Vector3(0.50, 0.72, 0.25), 16, 16, 8, 12, 4, sheet_w, sheet_h)
	torso.position = Vector3(0.0, 0.88, 0.0)
	_visual_root.add_child(torso)

	# Right Arm (4x12x4 at 40, 16) - Outstretched Zombie Pose
	var r_arm_pivot := Node3D.new()
	r_arm_pivot.position = Vector3(0.375, 1.18, 0.0)
	r_arm_pivot.rotation.x = -PI * 0.48
	var r_arm := _create_part(Vector3(0.24, 0.72, 0.24), 40, 16, 4, 12, 4, sheet_w, sheet_h)
	r_arm.position = Vector3(0.0, -0.32, 0.0)
	r_arm_pivot.add_child(r_arm)
	_visual_root.add_child(r_arm_pivot)
	_arms.append(r_arm_pivot)

	# Left Arm (4x12x4 at 40, 16, mirrored)
	var l_arm_pivot := Node3D.new()
	l_arm_pivot.position = Vector3(-0.375, 1.18, 0.0)
	l_arm_pivot.rotation.x = -PI * 0.48
	var l_arm := _create_part(Vector3(0.24, 0.72, 0.24), 40, 16, 4, 12, 4, sheet_w, sheet_h, true)
	l_arm.position = Vector3(0.0, -0.32, 0.0)
	l_arm_pivot.add_child(l_arm)
	_visual_root.add_child(l_arm_pivot)
	_arms.append(l_arm_pivot)

	# Right Leg (4x12x4 at 0, 16)
	var r_leg_pivot := Node3D.new()
	r_leg_pivot.position = Vector3(0.125, 0.52, 0.0)
	var r_leg := _create_part(Vector3(0.24, 0.72, 0.24), 0, 16, 4, 12, 4, sheet_w, sheet_h)
	r_leg.position = Vector3(0.0, -0.32, 0.0)
	r_leg_pivot.add_child(r_leg)
	_visual_root.add_child(r_leg_pivot)
	_legs.append(r_leg_pivot)

	# Left Leg (4x12x4 at 0, 16, mirrored)
	var l_leg_pivot := Node3D.new()
	l_leg_pivot.position = Vector3(-0.125, 0.52, 0.0)
	var l_leg := _create_part(Vector3(0.24, 0.72, 0.24), 0, 16, 4, 12, 4, sheet_w, sheet_h, true)
	l_leg.position = Vector3(0.0, -0.32, 0.0)
	l_leg_pivot.add_child(l_leg)
	_visual_root.add_child(l_leg_pivot)
	_legs.append(l_leg_pivot)


func _build_skeleton_model(sheet_w: float, sheet_h: float) -> void:
	# Head (8x8x8 at 0, 0)
	var head := _create_part(Vector3(0.50, 0.50, 0.50), 0, 0, 8, 8, 8, sheet_w, sheet_h)
	head.position = Vector3(0.0, 1.48, 0.0)
	_visual_root.add_child(head)

	# Torso (8x12x4 at 16, 16)
	var torso := _create_part(Vector3(0.50, 0.72, 0.25), 16, 16, 8, 12, 4, sheet_w, sheet_h)
	torso.position = Vector3(0.0, 0.88, 0.0)
	_visual_root.add_child(torso)

	# Right Arm (2x12x2 at 40, 16)
	var r_arm_pivot := Node3D.new()
	r_arm_pivot.position = Vector3(0.31, 1.18, 0.0)
	r_arm_pivot.rotation.x = -PI * 0.48
	var r_arm := _create_part(Vector3(0.14, 0.72, 0.14), 40, 16, 2, 12, 2, sheet_w, sheet_h)
	r_arm.position = Vector3(0.0, -0.32, 0.0)
	r_arm_pivot.add_child(r_arm)
	_visual_root.add_child(r_arm_pivot)
	_arms.append(r_arm_pivot)

	# Left Arm (2x12x2 at 40, 16, mirrored)
	var l_arm_pivot := Node3D.new()
	l_arm_pivot.position = Vector3(-0.31, 1.18, 0.0)
	l_arm_pivot.rotation.x = -PI * 0.48
	var l_arm := _create_part(Vector3(0.14, 0.72, 0.14), 40, 16, 2, 12, 2, sheet_w, sheet_h, true)
	l_arm.position = Vector3(0.0, -0.32, 0.0)
	l_arm_pivot.add_child(l_arm)
	_visual_root.add_child(l_arm_pivot)
	_arms.append(l_arm_pivot)

	# Right Leg (2x12x2 at 0, 16)
	var r_leg_pivot := Node3D.new()
	r_leg_pivot.position = Vector3(0.125, 0.52, 0.0)
	var r_leg := _create_part(Vector3(0.14, 0.72, 0.14), 0, 16, 2, 12, 2, sheet_w, sheet_h)
	r_leg.position = Vector3(0.0, -0.32, 0.0)
	r_leg_pivot.add_child(r_leg)
	_visual_root.add_child(r_leg_pivot)
	_legs.append(r_leg_pivot)

	# Left Leg (2x12x2 at 0, 16, mirrored)
	var l_leg_pivot := Node3D.new()
	l_leg_pivot.position = Vector3(-0.125, 0.52, 0.0)
	var l_leg := _create_part(Vector3(0.14, 0.72, 0.14), 0, 16, 2, 12, 2, sheet_w, sheet_h, true)
	l_leg.position = Vector3(0.0, -0.32, 0.0)
	l_leg_pivot.add_child(l_leg)
	_visual_root.add_child(l_leg_pivot)
	_legs.append(l_leg_pivot)


func _build_creeper_model(sheet_w: float, sheet_h: float) -> void:
	# Head (8x8x8 at 0, 0)
	var head := _create_part(Vector3(0.50, 0.50, 0.50), 0, 0, 8, 8, 8, sheet_w, sheet_h)
	head.position = Vector3(0.0, 1.42, 0.0)
	_visual_root.add_child(head)

	# Torso (8x12x4 at 16, 16)
	var torso := _create_part(Vector3(0.50, 0.72, 0.25), 16, 16, 8, 12, 4, sheet_w, sheet_h)
	torso.position = Vector3(0.0, 0.82, 0.0)
	_visual_root.add_child(torso)

	# 4 Feet (4x6x4 at 0, 16)
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
	# Head (8x8x6 at 0, 0)
	var head := _create_part(Vector3(0.48, 0.48, 0.36), 0, 0, 8, 8, 6, sheet_w, sheet_h)
	head.position = Vector3(0.0, 0.88, -0.52)
	_visual_root.add_child(head)

	# Horns (1x3x1 at 22, 0)
	for side in [-1.0, 1.0]:
		var horn := _create_part(Vector3(0.06, 0.18, 0.06), 22, 0, 1, 3, 1, sheet_w, sheet_h)
		horn.position = Vector3(side * 0.25, 1.15, -0.48)
		_visual_root.add_child(horn)

	# Torso (12x18x10 at 18, 4)
	var body := _create_part(Vector3(0.72, 0.60, 1.08), 18, 4, 12, 18, 10, sheet_w, sheet_h)
	body.position = Vector3(0.0, 0.72, 0.0)
	_visual_root.add_child(body)

	# Udders (4x6x2 at 52, 0)
	var udders := _create_part(Vector3(0.24, 0.36, 0.12), 52, 0, 4, 6, 2, sheet_w, sheet_h)
	udders.position = Vector3(0.0, 0.44, 0.22)
	_visual_root.add_child(udders)

	# 4 Legs (4x12x4 at 0, 16)
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
	# Head (8x8x8 at 0, 0)
	var head := _create_part(Vector3(0.48, 0.48, 0.48), 0, 0, 8, 8, 8, sheet_w, sheet_h)
	head.position = Vector3(0.0, 0.68, -0.42)
	_visual_root.add_child(head)

	# Snout (4x3x1 at 16, 16)
	var snout := _create_part(Vector3(0.24, 0.18, 0.08), 16, 16, 4, 3, 1, sheet_w, sheet_h)
	snout.position = Vector3(0.0, 0.58, -0.68)
	_visual_root.add_child(snout)

	# Torso (10x16x8 at 28, 8)
	var body := _create_part(Vector3(0.60, 0.48, 0.96), 28, 8, 10, 16, 8, sheet_w, sheet_h)
	body.position = Vector3(0.0, 0.54, 0.0)
	_visual_root.add_child(body)

	# 4 Legs (4x6x4 at 0, 16)
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
	# Head (8x8x8 at 32, 4)
	var head := _create_part(Vector3(0.46, 0.46, 0.46), 32, 4, 8, 8, 8, sheet_w, sheet_h)
	head.position = Vector3(0.0, 0.44, -0.38)
	_visual_root.add_child(head)

	# Neck / Middle (6x6x6 at 0, 0)
	var neck := _create_part(Vector3(0.36, 0.36, 0.36), 0, 0, 6, 6, 6, sheet_w, sheet_h)
	neck.position = Vector3(0.0, 0.40, -0.05)
	_visual_root.add_child(neck)

	# Abdomen (10x8x12 at 0, 12)
	var abdomen := _create_part(Vector3(0.60, 0.48, 0.72), 0, 12, 10, 8, 12, sheet_w, sheet_h)
	abdomen.position = Vector3(0.0, 0.46, 0.42)
	_visual_root.add_child(abdomen)

	# 8 Spider Legs (12x2x2 at 18, 0)
	var z_positions: Array[float] = [-0.18, -0.06, 0.06, 0.18]
	for i in range(4):
		var z_pos: float = z_positions[i]
		# Right leg (+X)
		var r_pivot := Node3D.new()
		r_pivot.position = Vector3(0.22, 0.38, z_pos)
		r_pivot.rotation.z = deg_to_rad(-24.0)
		r_pivot.rotation.y = deg_to_rad(-35.0 + float(i) * 22.0)
		var r_mesh := _create_part(Vector3(0.68, 0.10, 0.10), 18, 0, 12, 2, 2, sheet_w, sheet_h)
		r_mesh.position = Vector3(0.34, 0.0, 0.0)
		r_pivot.add_child(r_mesh)
		_visual_root.add_child(r_pivot)
		_legs.append(r_pivot)

		# Left leg (-X)
		var l_pivot := Node3D.new()
		l_pivot.position = Vector3(-0.22, 0.38, z_pos)
		l_pivot.rotation.z = deg_to_rad(24.0)
		l_pivot.rotation.y = deg_to_rad(35.0 - float(i) * 22.0)
		var l_mesh := _create_part(Vector3(0.68, 0.10, 0.10), 18, 0, 12, 2, 2, sheet_w, sheet_h, true)
		l_mesh.position = Vector3(-0.34, 0.0, 0.0)
		l_pivot.add_child(l_mesh)
		_visual_root.add_child(l_pivot)
		_legs.append(l_pivot)
