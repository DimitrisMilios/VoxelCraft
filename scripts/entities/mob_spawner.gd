class_name MobSpawner
extends Node3D
## Spawns and maintains passive mobs around the player on solid voxel terrain.

@export var max_mobs: int = 8
@export var min_spawn_radius: float = 8.0
@export var max_spawn_radius: float = 28.0
@export var despawn_distance: float = 52.0
@export var spawn_interval: float = 2.0

var _world_manager: WorldManager = null
var _player: Node3D = null
var _mobs: Array[PassiveMob] = []
var _timer: float = 0.8


func _ready() -> void:
	call_deferred("_initialize_references")


func _initialize_references() -> void:
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _process(delta: float) -> void:
	if _world_manager == null or _player == null:
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = spawn_interval
		_cleanup_distant_mobs()
		if _mobs.size() < max_mobs:
			_try_spawn_mob()


func _cleanup_distant_mobs() -> void:
	var valid_mobs: Array[PassiveMob] = []
	for mob in _mobs:
		if not is_instance_valid(mob):
			continue
		if mob.global_position.distance_to(_player.global_position) > despawn_distance or mob.global_position.y < -10.0:
			mob.queue_free()
		else:
			valid_mobs.append(mob)
	_mobs = valid_mobs


func _try_spawn_mob() -> void:
	var angle: float = randf_range(0.0, TAU)
	var dist: float = randf_range(min_spawn_radius, max_spawn_radius)
	var wx: int = int(floor(_player.global_position.x + cos(angle) * dist))
	var wz: int = int(floor(_player.global_position.z + sin(angle) * dist))

	var surface_y: int = _world_manager.get_surface_height_at(wx, wz)
	var ground_block: int = _world_manager.get_block_world(Vector3i(wx, surface_y, wz))
	if ground_block != BlockRegistry.BlockId.GRASS:
		return

	var mob := PassiveMob.new()
	mob.variant = PassiveMob.MobVariant.PIG if (randf() < 0.55) else PassiveMob.MobVariant.COW
	add_child(mob)
	mob.global_position = Vector3(float(wx) + 0.5, float(surface_y) + 1.2, float(wz) + 0.5)
	_mobs.append(mob)
