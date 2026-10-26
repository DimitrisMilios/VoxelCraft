class_name ZeroGGlowParticles
extends Node3D
## Spawns glowing anti-gravity particle motes (GPUParticles3D) drifting in zero-g around the player.
## Pairs with golden hour volumetric light shafts and ACES tonemapped bloom.

@export var player_path: NodePath = NodePath("../Player")

var _particles: GPUParticles3D = null
var _player: Node3D = null


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	_player = get_node_or_null(player_path) as Node3D
	_create_particles()


func _create_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "ZeroGParticles"
	_particles.amount = 280
	_particles.lifetime = 7.5
	_particles.preprocess = 4.0
	_particles.explosiveness = 0.0
	_particles.randomness = 0.6
	_particles.visibility_aabb = AABB(Vector3(-35, -20, -35), Vector3(70, 40, 70))

	# Unshaded additive emission material for luminous bloom
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 0.88, 0.52, 0.90)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.045, 0.045, 0.045)
	mesh.material = mat
	_particles.draw_pass_1 = mesh

	var p_mat := ParticleProcessMaterial.new()
	p_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	p_mat.emission_box_extents = Vector3(22.0, 12.0, 22.0)

	# Anti-gravity / Zero-G floating drift
	p_mat.gravity = Vector3(0.0, 0.02, 0.0)
	p_mat.initial_velocity_min = 0.12
	p_mat.initial_velocity_max = 0.42
	p_mat.direction = Vector3(0.2, 0.5, 0.2)
	p_mat.spread = 180.0

	p_mat.angular_velocity_min = -25.0
	p_mat.angular_velocity_max = 25.0
	p_mat.linear_accel_min = -0.05
	p_mat.linear_accel_max = 0.05

	# Scale and alpha variations in zero-g
	p_mat.scale_min = 0.4
	p_mat.scale_max = 1.3
	p_mat.color = Color(1.0, 0.90, 0.60, 0.85)

	# Subtle turbulence for floating eddies in zero-g
	p_mat.turbulence_enabled = true
	p_mat.turbulence_noise_strength = 0.14
	p_mat.turbulence_noise_scale = 3.8

	_particles.process_material = p_mat
	add_child(_particles)


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player != null and is_instance_valid(_player):
		global_position = _player.global_position
