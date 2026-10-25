class_name PlayerController
extends CharacterBody3D
## First-person player controller for VoxelCraft.
## Handles mouse-look camera rotation, WASD + sprint movement, jumping, gravity,
## swimming buoyancy in water, and a toggleable Creative Fly Mode (F key).

signal fly_mode_changed(is_flying: bool)
signal water_state_changed(is_in_water: bool)
signal jumped()
signal step_taken(is_in_water: bool)

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
var is_head_underwater: bool = false

# --- Node References ---
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_ray: RayCast3D = $Head/Camera3D/InteractionRay

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _world_manager: WorldManager = null
var _step_distance_accum: float = 0.0


func _ready() -> void:
	_register_default_inputs()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if camera:
		camera.fov = base_fov
	call_deferred("_resolve_world_manager")


func _resolve_world_manager() -> void:
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager


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
		fly_mode_changed.emit(is_flying)
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
		_handle_fly_movement(delta)
	elif is_in_water:
		_handle_swim_movement(delta)
	else:
		_apply_gravity(delta)
		_handle_jump()
		_handle_horizontal_movement(delta)

	_update_camera_fov(delta)
	move_and_slide()
	_track_footsteps(delta)


func _update_water_submersion() -> void:
	if _world_manager == null:
		return
	var waist_pos := Vector3i(
		floori(global_position.x),
		floori(global_position.y + 0.65),
		floori(global_position.z)
	)
	var eye_pos := Vector3i(
		floori(head.global_position.x),
		floori(head.global_position.y + 0.12),
		floori(head.global_position.z)
	)
	var now_in_water: bool = BlockRegistry.is_liquid(_world_manager.get_block_world(waist_pos))
	is_head_underwater = BlockRegistry.is_liquid(_world_manager.get_block_world(eye_pos))

	if now_in_water != is_in_water:
		is_in_water = now_in_water
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
	var target_speed: float = sprint_speed if is_sprinting else walk_speed
	var current_accel: float = acceleration if is_on_floor() else air_acceleration

	if move_direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, move_direction.x * target_speed, current_accel * delta * target_speed)
		velocity.z = move_toward(velocity.z, move_direction.z * target_speed, current_accel * delta * target_speed)
	else:
		var decel: float = friction if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, 0.0, decel * delta * target_speed)
		velocity.z = move_toward(velocity.z, 0.0, decel * delta * target_speed)


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

	if Input.is_action_pressed("jump"):
		velocity.y = move_toward(velocity.y, swim_up_speed, 14.0 * delta)
	elif Input.is_action_pressed("fly_down"):
		velocity.y = move_toward(velocity.y, -swim_up_speed, 14.0 * delta)
	else:
		# Gentle sinking buoyancy in water
		velocity.y = move_toward(velocity.y, -2.2, 6.5 * delta)


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


func _update_camera_fov(delta: float) -> void:
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


## Programmatically ensures all required input actions exist even in a fresh project.godot.
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
