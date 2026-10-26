class_name VoxelParticleSpawner
extends Node3D
## Spawns 3D retro voxel cube debris bursts when blocks are broken or placed.

var _shared_debris_mesh: BoxMesh = null


func _ready() -> void:
	add_to_group("particle_spawner")
	_shared_debris_mesh = BoxMesh.new()
	_shared_debris_mesh.size = Vector3(0.16, 0.16, 0.16)
	call_deferred("_connect_player_interactor")


func _connect_player_interactor() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var interactor := player.get_node_or_null("BlockInteractor") as BlockInteractor
	if interactor != null:
		interactor.block_broken.connect(_on_block_broken)
		interactor.block_placed.connect(_on_block_placed)


func _on_block_broken(world_pos: Vector3i, broken_block_id: int) -> void:
	_spawn_burst(
		Vector3(world_pos) + Vector3(0.5, 0.5, 0.5),
		BlockRegistry.get_block_color(broken_block_id),
		22,
		2.2,
		4.2
	)


func _on_block_placed(world_pos: Vector3i, placed_block_id: int) -> void:
	_spawn_burst(
		Vector3(world_pos) + Vector3(0.5, 0.5, 0.5),
		BlockRegistry.get_block_color(placed_block_id).lightened(0.15),
		8,
		1.2,
		2.4
	)


func _spawn_burst(
	center: Vector3,
	block_color: Color,
	amount: int,
	min_vel: float,
	max_vel: float
) -> void:
	var particles := CPUParticles3D.new()
	particles.position = center
	particles.emitting = false
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = 0.55
	particles.explosiveness = 0.95

	var mat := StandardMaterial3D.new()
	mat.albedo_color = block_color
	mat.roughness = 0.95
	mat.vertex_color_use_as_albedo = true

	var mesh_instance := _shared_debris_mesh.duplicate() as BoxMesh
	mesh_instance.material = mat
	particles.mesh = mesh_instance

	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(0.32, 0.32, 0.32)
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 180.0
	particles.gravity = Vector3(0.0, -14.0, 0.0)
	particles.initial_velocity_min = min_vel
	particles.initial_velocity_max = max_vel
	particles.scale_amount_min = 0.65
	particles.scale_amount_max = 1.15
	particles.color = Color.WHITE

	add_child(particles)
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


## Spawns explosive shockwave and smoke/fire debris particles for TNT & Creeper detonations.
func spawn_explosion_burst(center: Vector3, radius: float = 3.8) -> void:
	# 1. Fire / shockwave burst
	_spawn_burst(center, Color(1.0, 0.45, 0.12), 40, 5.0, 10.0)
	# 2. Dark smoke debris cloud
	_spawn_burst(center + Vector3(0.0, 0.4, 0.0), Color(0.25, 0.25, 0.26), 28, 2.5, 6.0)
