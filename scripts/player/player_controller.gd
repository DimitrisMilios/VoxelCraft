class_name PlayerController
extends CharacterBody3D
## First-person player controller for VoxelCraft.
## Handles mouse-look camera rotation, WASD + sprint movement, jumping, gravity,
## swimming buoyancy in water, survival health & fall damage, and Creative Fly Mode (F key).

signal fly_mode_changed(is_flying: bool)
signal water_state_changed(is_in_water: bool)
signal jumped()
signal step_taken(is_in_water: bool)
signal health_changed(current_hp: int, max_hp: int)
signal hunger_changed(current_hunger: int, max_hunger: int)
signal oxygen_changed(current_oxygen: int, max_oxygen: int)
signal player_damaged(amount: int)

# --- Exported Movement Tuning ---
@export_group("Movement")
@export var walk_speed: float = 5.5
@export var sprint_speed: float = 8.0
@export var swim_speed: float = 3.9
@export var swim_up_speed: float = 4.8
@export var fly_speed: float = 13.0
@export var fly_sprint_speed: float = 22.0
@export var fly_vertical_speed: float = 9.5
@export var acceleration: float = 14.0
@export var air_acceleration: float = 4.5
@export var fly_acceleration: float = 10.0
@export var friction: float = 12.0
@export var jump_velocity: float = 7.2
@export var gravity_multiplier: float = 1.8

# --- Exported Survival Tuning ---
@export_group("Survival")
@export var max_health: int = 20
@export var max_hunger: int = 20
@export var max_oxygen: int = 10
@export var fall_damage_threshold_speed: float = 12.2
@export var regen_interval_seconds: float = 3.6

# --- Exported Camera Tuning ---
@export_group("Camera")
@export var mouse_sensitivity: float = 0.0022
@export var min_pitch_deg: float = -89.0
@export var max_pitch_deg: float = 89.0
@export var base_fov: float = 75.0
@export var sprint_fov_multiplier: float = 1.10
@export var fly_fov_multiplier: float = 1.14
@export var fov_lerp_speed: float = 8.0

# --- State ---
var is_flying: bool = false
var is_in_water: bool = false
var is_on_ladder: bool = false
var is_head_underwater: bool = false
var water_submersion_depth: float = 0.0
var water_flow_vector: Vector3 = Vector3.ZERO
var current_health: int = 20
var current_hunger: int = 20
var current_oxygen: int = 10
var custom_respawn_pos: Vector3 = Vector3.ZERO
var has_custom_respawn: bool = false

# --- Node References ---
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_ray: RayCast3D = $Head/Camera3D/InteractionRay

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _world_manager: WorldManager = null
var _step_distance_accum: float = 0.0
var _max_fall_speed: float = 0.0
var _was_on_floor: bool = true
var _regen_timer: float = 0.0
var _exhaustion: float = 0.0
var _starve_timer: float = 0.0
var _oxygen_timer: float = 0.0
var _hurt_roll: float = 0.0


func _ready() -> void:
	current_health = max_health
	current_hunger = max_hunger
	current_oxygen = max_oxygen
	_register_default_inputs()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if camera:
		camera.fov = base_fov
	call_deferred("_resolve_world_manager")


func _resolve_world_manager() -> void:
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	health_changed.emit(current_health, max_health)
	hunger_changed.emit(current_hunger, max_hunger)
	oxygen_changed.emit(current_oxygen, max_oxygen)


func _unhandled_input(event: InputEvent) -> void:
	# Toggle mouse capture (Pause Menu) with Escape
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	# Toggle Creative Fly Mode with F
	if event.is_action_pressed("toggle_fly"):
		is_flying = not is_flying
		velocity.y = 0.0
		_max_fall_speed = 0.0
		fly_mode_changed.emit(is_flying)
		health_changed.emit(current_health, max_health)
		return

	# Smooth first-person mouse look
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)


func _physics_process(delta: float) -> void:
	_update_water_submersion()

	if is_flying:
		_max_fall_speed = 0.0
		_handle_fly_movement(delta)
	elif is_in_water:
		_max_fall_speed = 0.0
		_handle_swim_movement(delta)
	elif is_on_ladder:
		_max_fall_speed = 0.0
		_handle_horizontal_movement(delta)
		if Input.is_action_pressed("jump") or Input.is_action_pressed("move_forward"):
			velocity.y = move_toward(velocity.y, 4.6, 22.0 * delta)
		elif Input.is_action_pressed("fly_down"):
			velocity.y = move_toward(velocity.y, 0.0, 22.0 * delta)
		else:
			velocity.y = move_toward(velocity.y, -2.4, 18.0 * delta)
	else:
		if not is_on_floor() and velocity.y < 0.0:
			_max_fall_speed = maxf(_max_fall_speed, -velocity.y)
		_apply_gravity(delta)
		_handle_jump()
		_handle_horizontal_movement(delta)

	move_and_slide()

	# Check landing impact for survival fall damage
	var now_on_floor: bool = is_on_floor()
	if now_on_floor and not _was_on_floor:
		if not is_flying and not is_in_water and _max_fall_speed > fall_damage_threshold_speed:
			var dmg: int = maxi(1, int(round((_max_fall_speed - (fall_damage_threshold_speed - 1.0)) * 1.4)))
			take_damage(dmg)
		_max_fall_speed = 0.0
	elif now_on_floor:
		_max_fall_speed = 0.0
	_was_on_floor = now_on_floor

	# Check void fall recovery
	if global_position.y < -25.0:
		take_damage(max_health)

	_update_hunger_and_oxygen(delta)
	_update_health_regen(delta)
	_update_camera_fov_and_tilt(delta)
	_track_footsteps(delta)


func eat_food(nutrition: int) -> bool:
	if nutrition <= 0:
		return false
	if current_hunger >= max_hunger and current_health >= max_health:
		return false
	current_hunger = mini(max_hunger, current_hunger + nutrition)
	current_health = mini(max_health, current_health + 2)
	hunger_changed.emit(current_hunger, max_hunger)
	health_changed.emit(current_health, max_health)
	return true


func set_respawn_bed_position(bed_world_pos: Vector3) -> void:
	custom_respawn_pos = bed_world_pos
	has_custom_respawn = true


func take_damage(amount: int) -> void:
	if is_flying or amount <= 0:
		return
	current_health = maxi(0, current_health - amount)
	_hurt_roll = deg_to_rad(6.5)
	_regen_timer = 0.0
	player_damaged.emit(amount)
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		_respawn_player()


func _respawn_player() -> void:
	current_health = max_health
	current_hunger = max_hunger
	current_oxygen = max_oxygen
	velocity = Vector3.ZERO
	_max_fall_speed = 0.0
	if has_custom_respawn:
		global_position = custom_respawn_pos + Vector3(0.5, 1.5, 0.5)
	else:
		var spawn_x: int = 8
		var spawn_z: int = 8
		var surface_y: int = 56
		if _world_manager != null:
			surface_y = _world_manager.get_surface_height_at(spawn_x, spawn_z)
		global_position = Vector3(float(spawn_x) + 0.5, float(surface_y) + 2.5, float(spawn_z) + 0.5)
	health_changed.emit(current_health, max_health)
	hunger_changed.emit(current_hunger, max_hunger)
	oxygen_changed.emit(current_oxygen, max_oxygen)


func _update_hunger_and_oxygen(delta: float) -> void:
	if is_flying:
		return

	# 1. Underwater Oxygen Bubbles & Drowning
	if is_head_underwater:
		_oxygen_timer += delta
		if current_oxygen > 0 and _oxygen_timer >= 1.5:
			_oxygen_timer = 0.0
			current_oxygen = maxi(0, current_oxygen - 1)
			oxygen_changed.emit(current_oxygen, max_oxygen)
		elif current_oxygen <= 0 and _oxygen_timer >= 1.2:
			_oxygen_timer = 0.0
			take_damage(2)
	elif current_oxygen < max_oxygen:
		_oxygen_timer += delta
		if _oxygen_timer >= 0.25:
			_oxygen_timer = 0.0
			current_oxygen = mini(max_oxygen, current_oxygen + 1)
			oxygen_changed.emit(current_oxygen, max_oxygen)
	else:
		_oxygen_timer = 0.0

	# 2. Hunger Exhaustion Drain
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if horiz_speed > 0.5:
		if is_in_water:
			_exhaustion += delta * 0.18
		elif Input.is_action_pressed("sprint"):
			_exhaustion += delta * 0.36
		else:
			_exhaustion += delta * 0.06

	if _exhaustion >= 4.0:
		_exhaustion -= 4.0
		if current_hunger > 0:
			current_hunger = maxi(0, current_hunger - 1)
			hunger_changed.emit(current_hunger, max_hunger)

	# 3. Starvation when Hunger == 0
	if current_hunger <= 0:
		_starve_timer += delta
		if _starve_timer >= 4.5:
			_starve_timer = 0.0
			if current_health > 1:
				take_damage(1)
	else:
		_starve_timer = 0.0


func _update_health_regen(delta: float) -> void:
	if current_health >= max_health or current_hunger < 16:
		_regen_timer = 0.0
		return
	_regen_timer += delta
	if _regen_timer >= regen_interval_seconds:
		_regen_timer = 0.0
		current_health = mini(max_health, current_health + 1)
		_exhaustion += 1.2
		health_changed.emit(current_health, max_health)


func _update_water_submersion() -> void:
	if _world_manager == null:
		return
	water_submersion_depth = _world_manager.get_water_submersion_depth(global_position)
	water_flow_vector = _world_manager.get_water_flow_vector(global_position)

	var feet_b := Vector3i(floori(global_position.x), floori(global_position.y + 0.15), floori(global_position.z))
	var waist_b := Vector3i(floori(global_position.x), floori(global_position.y + 0.95), floori(global_position.z))
	is_on_ladder = (
		_world_manager.get_block_world(feet_b) == BlockRegistry.BlockId.LADDER
		or _world_manager.get_block_world(waist_b) == BlockRegistry.BlockId.LADDER
	)

	var eye_pos := Vector3i(
		floori(head.global_position.x),
		floori(head.global_position.y + 0.12),
		floori(head.global_position.z)
	)
	var now_in_water: bool = water_submersion_depth > 0.36
	if water_submersion_depth > 0.08:
		_max_fall_speed = 0.0
	is_head_underwater = BlockRegistry.is_liquid(_world_manager.get_block_world(eye_pos))

	if now_in_water != is_in_water:
		is_in_water = now_in_water
		if is_in_water:
			_max_fall_speed = 0.0
		water_state_changed.emit(is_in_water)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * gravity_multiplier * delta


func _handle_jump() -> void:
	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		jumped.emit()


func _handle_horizontal_movement(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	var move_direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var is_sprinting: bool = Input.is_action_pressed("sprint") and input_dir.y < 0.0
	var wade_mult: float = 0.80 if water_submersion_depth > 0.02 else 1.0
	var target_speed: float = (sprint_speed if is_sprinting else walk_speed) * wade_mult
	var current_accel: float = acceleration if is_on_floor() else air_acceleration

	if move_direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, move_direction.x * target_speed, current_accel * delta * target_speed)
		velocity.z = move_toward(velocity.z, move_direction.z * target_speed, current_accel * delta * target_speed)
	else:
		var decel: float = friction if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, 0.0, decel * delta * target_speed)
		velocity.z = move_toward(velocity.z, 0.0, decel * delta * target_speed)

	# Apply gentle current drift when wading in shallow flowing water
	if water_submersion_depth > 0.02 and water_flow_vector != Vector3.ZERO:
		velocity.x += water_flow_vector.x * 2.15 * delta
		velocity.z += water_flow_vector.z * 2.15 * delta


func _handle_swim_movement(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	var move_direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_speed: float = swim_speed * (1.3 if Input.is_action_pressed("sprint") else 1.0)

	if move_direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, move_direction.x * target_speed, 6.0 * delta * target_speed)
		velocity.z = move_toward(velocity.z, move_direction.z * target_speed, 6.0 * delta * target_speed)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 5.0 * delta * target_speed)
		velocity.z = move_toward(velocity.z, 0.0, 5.0 * delta * target_speed)

	# Apply water current push in deep/flowing water
	if water_flow_vector != Vector3.ZERO:
		velocity.x += water_flow_vector.x * 2.4 * delta
		velocity.z += water_flow_vector.z * 2.4 * delta

	var buoyancy_factor: float = clampf((water_submersion_depth - 0.36) / 0.85, 0.0, 1.35)

	if Input.is_action_pressed("jump"):
		# If near the water surface or pressing against a shoreline ledge, give a strong hop out of water
		if is_on_wall() or (not is_head_underwater and water_submersion_depth < 0.92):
			velocity.y = move_toward(velocity.y, jump_velocity * 0.96, 26.0 * delta)
		else:
			velocity.y = move_toward(velocity.y, swim_up_speed * maxf(0.85, buoyancy_factor), 16.0 * delta)
	elif is_on_wall() and move_direction != Vector3.ZERO and not is_head_underwater:
		# Auto-climb shoreline ledge when swimming into a same-level bank
		velocity.y = move_toward(velocity.y, jump_velocity * 0.92, 24.0 * delta)
	elif Input.is_action_pressed("fly_down"):
		velocity.y = move_toward(velocity.y, -swim_up_speed, 14.0 * delta)
	else:
		# Proportional Archimedes buoyancy: gently sink to neutral equilibrium or get pulled down in waterfalls
		var sink_target: float = lerpf(-2.1, -0.85, clampf(buoyancy_factor, 0.0, 1.0)) + (water_flow_vector.y * 1.4)
		velocity.y = move_toward(velocity.y, sink_target, 6.0 * delta)


func _handle_fly_movement(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)
	var move_direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var is_sprinting: bool = Input.is_action_pressed("sprint")
	var target_speed: float = fly_sprint_speed if is_sprinting else fly_speed

	if move_direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, move_direction.x * target_speed, fly_acceleration * delta * target_speed)
		velocity.z = move_toward(velocity.z, move_direction.z * target_speed, fly_acceleration * delta * target_speed)
	else:
		velocity.x = move_toward(velocity.x, 0.0, fly_acceleration * delta * target_speed)
		velocity.z = move_toward(velocity.z, 0.0, fly_acceleration * delta * target_speed)

	var vertical_dir: float = 0.0
	if Input.is_action_pressed("jump"):
		vertical_dir += 1.0
	if Input.is_action_pressed("fly_down"):
		vertical_dir -= 1.0

	var v_speed: float = fly_vertical_speed * (1.5 if is_sprinting else 1.0)
	velocity.y = move_toward(velocity.y, vertical_dir * v_speed, fly_acceleration * delta * v_speed)


func _track_footsteps(delta: float) -> void:
	if is_flying:
		return
	if not is_on_floor() and not is_in_water:
		return
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if horiz_speed < 0.8:
		return
	_step_distance_accum += horiz_speed * delta
	var stride: float = 2.4 if is_in_water else 2.1
	if _step_distance_accum >= stride:
		_step_distance_accum = 0.0
		step_taken.emit(is_in_water)


func _update_camera_fov_and_tilt(delta: float) -> void:
	if not camera:
		return
	var is_moving_forward: bool = Input.is_action_pressed("move_forward")
	var is_sprinting: bool = Input.is_action_pressed("sprint") and is_moving_forward
	var target_fov: float = base_fov
	if is_head_underwater:
		target_fov = base_fov * 0.92
	elif is_flying and is_sprinting:
		target_fov = base_fov * fly_fov_multiplier
	elif is_sprinting:
		target_fov = base_fov * sprint_fov_multiplier
	camera.fov = lerpf(camera.fov, target_fov, fov_lerp_speed * delta)

	if _hurt_roll > 0.001:
		_hurt_roll = lerpf(_hurt_roll, 0.0, 10.0 * delta)
		camera.rotation.z = _hurt_roll
	else:
		camera.rotation.z = 0.0


func _register_default_inputs() -> void:
	_bind_key_action("move_forward", KEY_W)
	_bind_key_action("move_backward", KEY_S)
	_bind_key_action("move_left", KEY_A)
	_bind_key_action("move_right", KEY_D)
	_bind_key_action("jump", KEY_SPACE)
	_bind_key_action("sprint", KEY_SHIFT)
	_bind_key_action("toggle_fly", KEY_F)
	_bind_key_action("fly_down", KEY_CTRL)
	_bind_key_action("fly_down", KEY_C)


func _bind_key_action(action_name: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == keycode:
			return
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action_name, key_event)
