class_name PlayerController
extends CharacterBody3D
## First-person player controller for VoxelCraft.
## Handles mouse-look camera rotation, WASD + sprint movement, jumping, and custom gravity.

# --- Exported Movement Tuning ---
@export_group("Movement")
@export var walk_speed: float = 5.5
@export var sprint_speed: float = 8.0
@export var acceleration: float = 14.0
@export var air_acceleration: float = 4.5
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
@export var fov_lerp_speed: float = 8.0

# --- Node References ---
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_ray: RayCast3D = $Head/Camera3D/InteractionRay

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	_register_default_inputs()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if camera:
		camera.fov = base_fov


func _unhandled_input(event: InputEvent) -> void:
	# Toggle mouse capture with Escape
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	# Re-capture mouse when clicking inside the game window
	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return

	# Smooth first-person mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x,
			deg_to_rad(min_pitch_deg),
			deg_to_rad(max_pitch_deg)
		)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump()
	_handle_horizontal_movement(delta)
	_update_camera_fov(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * gravity_multiplier * delta


func _handle_jump() -> void:
	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity


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


func _update_camera_fov(delta: float) -> void:
	if not camera:
		return
	var is_moving_forward: bool = Input.is_action_pressed("move_forward")
	var is_sprinting: bool = Input.is_action_pressed("sprint") and is_moving_forward
	var target_fov: float = base_fov * sprint_fov_multiplier if is_sprinting else base_fov
	camera.fov = lerpf(camera.fov, target_fov, fov_lerp_speed * delta)


## Programmatically ensures all required input actions exist even in a fresh project.godot.
func _register_default_inputs() -> void:
	_bind_key_action("move_forward", KEY_W)
	_bind_key_action("move_backward", KEY_S)
	_bind_key_action("move_left", KEY_A)
	_bind_key_action("move_right", KEY_D)
	_bind_key_action("jump", KEY_SPACE)
	_bind_key_action("sprint", KEY_SHIFT)


func _bind_key_action(action_name: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == keycode:
			return
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action_name, key_event)
