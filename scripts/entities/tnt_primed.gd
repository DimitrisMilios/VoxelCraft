class_name TNTPrimed
extends CharacterBody3D
## TrueCraft & Beta 1.7.3 authentic primed TNT entity.
## Features authentic 80-tick (4.0s) fuse, physics with gravity & bounce,
## water buoyancy and current drift, accelerating white flash blinking,
## and realistic spherical crater detonation with bedrock/obsidian blast resistance.

const FUSE_DURATION: float = 4.0
const GRAVITY: float = 19.6
const BOUNCE_DAMPING: float = 0.45
const EXPLOSION_RADIUS: float = 3.8

var fuse: float = FUSE_DURATION
var is_detonated: bool = false

var _world_manager: WorldManager = null
var _visual_mesh: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _flash_timer: float = 0.0


static func spawn_primed_tnt(
	parent_node: Node,
	world_pos: Vector3,
	initial_vel: Vector3 = Vector3(0.0, 2.5, 0.0),
	custom_fuse: float = FUSE_DURATION
) -> TNTPrimed:
	if parent_node == null:
		return null
	var tnt: TNTPrimed = (load("res://scripts/entities/tnt_primed.gd") as GDScript).new()
	tnt.fuse = custom_fuse
	tnt.position = world_pos
	tnt.velocity = initial_vel
	parent_node.add_child(tnt)
	return tnt


func _ready() -> void:
	add_to_group("primed_tnt")
	collision_layer = 4
	collision_mask = 1

	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	_build_tnt_mesh()


func _physics_process(delta: float) -> void:
	if is_detonated:
		return

	fuse -= delta
	_update_flash_effect(delta)

	if fuse <= 0.0:
		detonate()
		return

	if _world_manager == null:
		if get_parent() is WorldManager:
			_world_manager = get_parent() as WorldManager
		elif is_inside_tree() and get_tree() != null:
			_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager

	# Water buoyancy & current drift
	var in_water: bool = false
	var cur_pos: Vector3 = global_position if is_inside_tree() else position
	if _world_manager != null:
		var depth: float = _world_manager.get_water_submersion_depth(cur_pos)
		if depth > 0.15:
			in_water = true
			velocity.y = move_toward(velocity.y, 1.8, 9.0 * delta)
			var flow: Vector3 = _world_manager.get_water_flow_vector(cur_pos)
			velocity.x += flow.x * 2.2 * delta
			velocity.z += flow.z * 2.2 * delta

	if not in_water and not (is_inside_tree() and is_on_floor()):
		velocity.y -= GRAVITY * delta

	# Horizontal friction
	velocity.x = move_toward(velocity.x, 0.0, 3.5 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 3.5 * delta)

	if is_inside_tree():
		move_and_slide()
		# Bouncing behavior on terrain collision
		if is_on_floor():
			if absf(velocity.y) > 0.8:
				velocity.y = -velocity.y * BOUNCE_DAMPING
			else:
				velocity.y = 0.0
		if is_on_wall():
			velocity.x = -velocity.x * BOUNCE_DAMPING
			velocity.z = -velocity.z * BOUNCE_DAMPING
	else:
		position += velocity * delta


func _update_flash_effect(delta: float) -> void:
	if _mat == null:
		return

	# Flash frequency accelerates as fuse reaches 0 (from 4 Hz to 18 Hz)
	var time_progress: float = clampf(1.0 - (fuse / FUSE_DURATION), 0.0, 1.0)
	var flash_rate: float = lerpf(4.0, 18.0, time_progress)
	_flash_timer += delta * flash_rate

	var flash_on: bool = sin(_flash_timer * TAU) > 0.0
	if flash_on:
		_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		_mat.emission_enabled = true
		_mat.emission = Color(0.65, 0.65, 0.65)
	else:
		_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		_mat.emission_enabled = false

	# Slight scale pulse as fuse burns down
	var scale_factor: float = 1.0 + time_progress * 0.15
	if _visual_mesh != null:
		_visual_mesh.scale = Vector3.ONE * scale_factor


func detonate() -> void:
	if is_detonated:
		return
	is_detonated = true

	var blast_center: Vector3 = global_position + Vector3(0.0, 0.45, 0.0) if is_inside_tree() else position + Vector3(0.0, 0.45, 0.0)
	if _world_manager != null:
		_world_manager.create_explosion(blast_center, EXPLOSION_RADIUS, true, true)
	elif is_inside_tree() and get_tree() != null:
		var wm := get_tree().get_first_node_in_group("world_manager") as WorldManager
		if wm != null:
			wm.create_explosion(blast_center, EXPLOSION_RADIUS, true, true)

	# Spawn explosion particles
	if is_inside_tree() and get_tree() != null:
		var particle_spawner := get_tree().get_first_node_in_group("particle_spawner") as VoxelParticleSpawner
		if particle_spawner != null and particle_spawner.has_method("spawn_explosion_burst"):
			particle_spawner.spawn_explosion_burst(blast_center, EXPLOSION_RADIUS)

	queue_free()


func _build_tnt_mesh() -> void:
	_visual_mesh = MeshInstance3D.new()
	_visual_mesh.name = "TNTMesh"

	_mat = StandardMaterial3D.new()
	_mat.roughness = 0.8
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	var atlas_tex: Texture2D = VoxelAtlasBuilder.get_atlas_texture()
	if atlas_tex != null:
		_mat.albedo_texture = atlas_tex
	else:
		_mat.albedo_color = Color(0.85, 0.22, 0.18)

	_visual_mesh.material_override = _mat
	_visual_mesh.mesh = _build_tnt_array_mesh()
	add_child(_visual_mesh)

	var coll := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(0.96, 0.96, 0.96)
	coll.shape = box_shape
	coll.position = Vector3(0.0, 0.48, 0.0)
	add_child(coll)


func _build_tnt_array_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var tnt_id: int = BlockRegistry.BlockId.TNT
	var faces: Array[int] = [
		BlockRegistry.FaceDir.TOP,
		BlockRegistry.FaceDir.BOTTOM,
		BlockRegistry.FaceDir.EAST,
		BlockRegistry.FaceDir.WEST,
		BlockRegistry.FaceDir.SOUTH,
		BlockRegistry.FaceDir.NORTH,
	]

	var h: float = 0.48
	for face_dir in faces:
		var uv_rect: Rect2 = BlockRegistry.get_tile_uv_rect(tnt_id, face_dir, 0)
		var u0: float = uv_rect.position.x
		var v0: float = uv_rect.position.y
		var u1: float = uv_rect.position.x + uv_rect.size.x
		var v1: float = uv_rect.position.y + uv_rect.size.y

		var verts: Array[Vector3]
		var normal: Vector3
		var shade: float = 1.0

		match face_dir:
			BlockRegistry.FaceDir.TOP:
				normal = Vector3.UP
				shade = 1.0
				verts = [Vector3(-h, 0.96, -h), Vector3(h, 0.96, -h), Vector3(h, 0.96, h), Vector3(-h, 0.96, h)]
			BlockRegistry.FaceDir.BOTTOM:
				normal = Vector3.DOWN
				shade = 0.55
				verts = [Vector3(-h, 0.0, h), Vector3(h, 0.0, h), Vector3(h, 0.0, -h), Vector3(-h, 0.0, -h)]
			BlockRegistry.FaceDir.EAST:
				normal = Vector3.RIGHT
				shade = 0.82
				verts = [Vector3(h, 0.96, h), Vector3(h, 0.96, -h), Vector3(h, 0.0, -h), Vector3(h, 0.0, h)]
			BlockRegistry.FaceDir.WEST:
				normal = Vector3.LEFT
				shade = 0.76
				verts = [Vector3(-h, 0.96, -h), Vector3(-h, 0.96, h), Vector3(-h, 0.0, h), Vector3(-h, 0.0, -h)]
			BlockRegistry.FaceDir.SOUTH:
				normal = Vector3.BACK
				shade = 0.90
				verts = [Vector3(-h, 0.96, h), Vector3(h, 0.96, h), Vector3(h, 0.0, h), Vector3(-h, 0.0, h)]
			_:
				normal = Vector3.FORWARD
				shade = 0.72
				verts = [Vector3(h, 0.96, -h), Vector3(-h, 0.96, -h), Vector3(-h, 0.0, -h), Vector3(h, 0.0, -h)]

		var uvs: Array[Vector2] = [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
		var col := Color(shade, shade, shade, 1.0)
		var indices: Array[int] = [0, 1, 2, 0, 2, 3]

		for idx in indices:
			st.set_normal(normal)
			st.set_color(col)
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])

	return st.commit()
