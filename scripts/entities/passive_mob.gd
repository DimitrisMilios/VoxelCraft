class_name PassiveMob
extends CharacterBody3D
## Autonomous passive voxel mob (Pig / Cow variant) with wandering AI,
## gravity, 1-block step hopping, ledge avoidance, and swinging leg animation.

enum MobState {
	IDLE,
	WANDER,
}

enum MobVariant {
	PIG = 0,
	COW = 1,
}

@export var move_speed: float = 2.1
@export var hop_velocity: float = 6.5
@export var gravity_multiplier: float = 1.8
@export var variant: MobVariant = MobVariant.PIG

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _state: MobState = MobState.IDLE
var _state_timer: float = 2.0
var _move_dir: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _anim_time: float = 0.0

var _visual_root: Node3D = null
var _legs: Array[Node3D] = []
var _ledge_ray: RayCast3D = null
var _step_ray: RayCast3D = null


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	_build_collision_and_rays()
	_build_voxel_model()
	_pick_next_state()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * gravity_multiplier * delta

	_state_timer -= delta
	if _state_timer <= 0.0:
		_pick_next_state()

	if _state == MobState.WANDER:
		# Smoothly turn toward movement direction
		rotation.y = lerp_angle(rotation.y, _target_yaw, 6.0 * delta)
		var forward: Vector3 = -global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()

		# Ledge avoidance: if no floor within 2.5 blocks ahead, turn around
		if is_on_floor() and _ledge_ray != null and not _ledge_ray.is_colliding():
			_target_yaw += PI * 0.75
			_move_dir = Vector3(sin(_target_yaw), 0.0, cos(_target_yaw)).normalized()
		else:
			velocity.x = forward.x * move_speed
			velocity.z = forward.z * move_speed

		# Auto-hop up 1-block terrain steps
		if is_on_floor() and _step_ray != null and _step_ray.is_colliding():
			velocity.y = hop_velocity
	else:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)

	move_and_slide()
	_animate_legs(delta)


func _pick_next_state() -> void:
	if randf() < 0.42:
		_state = MobState.IDLE
		_state_timer = randf_range(1.5, 3.5)
		_move_dir = Vector3.ZERO
	else:
		_state = MobState.WANDER
		_state_timer = randf_range(2.5, 5.5)
		_target_yaw = randf_range(-PI, PI)
		_move_dir = Vector3(-sin(_target_yaw), 0.0, -cos(_target_yaw)).normalized()


func _animate_legs(delta: float) -> void:
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if horiz_speed > 0.15:
		_anim_time += delta * 9.0
		var swing: float = sin(_anim_time) * 0.55
		if _legs.size() == 4:
			_legs[0].rotation.x = swing
			_legs[1].rotation.x = -swing
			_legs[2].rotation.x = -swing
			_legs[3].rotation.x = swing
	else:
		for leg in _legs:
			leg.rotation.x = lerpf(leg.rotation.x, 0.0, 10.0 * delta)


func _build_collision_and_rays() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.75, 0.95, 0.95)
	col.shape = box
	col.position = Vector3(0.0, 0.48, 0.0)
	add_child(col)

	# Downward ray ahead of the mob to detect steep drops (>2 blocks)
	_ledge_ray = RayCast3D.new()
	_ledge_ray.position = Vector3(0.0, 0.8, -0.85)
	_ledge_ray.target_position = Vector3(0.0, -2.6, 0.0)
	_ledge_ray.collision_mask = 1
	add_child(_ledge_ray)

	# Forward ray at shin height to detect 1-block steps to hop onto
	_step_ray = RayCast3D.new()
	_step_ray.position = Vector3(0.0, 0.35, -0.4)
	_step_ray.target_position = Vector3(0.0, 0.0, -0.45)
	_step_ray.collision_mask = 1
	add_child(_step_ray)


func _build_voxel_model() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualModel"
	add_child(_visual_root)

	var primary_color: Color = (
		Color(0.94, 0.64, 0.68) if variant == MobVariant.PIG else Color(0.38, 0.25, 0.16)
	)
	var accent_color: Color = (
		Color(0.85, 0.48, 0.54) if variant == MobVariant.PIG else Color(0.92, 0.92, 0.90)
	)

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = primary_color
	body_mat.roughness = 0.9

	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = accent_color
	accent_mat.roughness = 0.9

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.1, 0.1, 0.1)

	# Torso
	var body := _make_box_part(Vector3(0.62, 0.48, 0.88), body_mat)
	body.position = Vector3(0.0, 0.52, 0.0)
	_visual_root.add_child(body)

	# Head
	var head := _make_box_part(Vector3(0.46, 0.44, 0.44), body_mat)
	head.position = Vector3(0.0, 0.72, -0.52)
	_visual_root.add_child(head)

	# Snout / Muzzle
	var snout := _make_box_part(Vector3(0.24, 0.18, 0.12), accent_mat)
	snout.position = Vector3(0.0, 0.66, -0.78)
	_visual_root.add_child(snout)

	# Eyes
	var left_eye := _make_box_part(Vector3(0.07, 0.07, 0.05), eye_mat)
	left_eye.position = Vector3(-0.14, 0.78, -0.74)
	_visual_root.add_child(left_eye)

	var right_eye := _make_box_part(Vector3(0.07, 0.07, 0.05), eye_mat)
	right_eye.position = Vector3(0.14, 0.78, -0.74)
	_visual_root.add_child(right_eye)

	# 4 articulated legs
	var leg_offsets: Array[Vector3] = [
		Vector3(-0.20, 0.28, -0.28),
		Vector3(0.20, 0.28, -0.28),
		Vector3(-0.20, 0.28, 0.28),
		Vector3(0.20, 0.28, 0.28),
	]
	for offset in leg_offsets:
		var pivot := Node3D.new()
		pivot.position = offset
		var leg_mesh := _make_box_part(Vector3(0.18, 0.28, 0.18), accent_mat)
		leg_mesh.position = Vector3(0.0, -0.14, 0.0)
		pivot.add_child(leg_mesh)
		_visual_root.add_child(pivot)
		_legs.append(pivot)


func _make_box_part(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	mi.mesh = mesh
	return mi
