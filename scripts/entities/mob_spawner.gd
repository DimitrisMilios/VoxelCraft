class_name MobSpawner
extends Node3D
## Spawns and maintains passive mobs (Pig, Cow) during the day and
## hostile monsters (Zombie, Skeleton, Creeper, Spider) at night around the player.

@export var max_mobs: int = 12
@export var min_spawn_radius: float = 9.0
@export var max_spawn_radius: float = 30.0
@export var despawn_distance: float = 54.0
@export var spawn_interval: float = 1.8

var _world_manager: WorldManager = null
var _player: Node3D = null
var _day_night: DayNightCycle = null
var _mobs: Array[PassiveMob] = []
var _timer: float = 0.8


func _ready() -> void:
	call_deferred("_initialize_references")


func _initialize_references() -> void:
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_day_night = get_tree().get_first_node_in_group("day_night_cycle") as DayNightCycle


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
	if not BlockRegistry.is_solid(ground_block) or BlockRegistry.is_liquid(ground_block):
		return

	var is_night: bool = false
	if _day_night != null:
		is_night = (_day_night.time_of_day < 0.24 or _day_night.time_of_day > 0.76)

	var spawn_pos := Vector3(float(wx) + 0.5, float(surface_y) + 1.2, float(wz) + 0.5)

	var mob := PassiveMob.new()
	if is_night:
		# Minecraft spawning rule: Hostile monsters CANNOT spawn in illuminated areas!
		# Torches, glowstones, lava pools, or furnaces within ~10 blocks prevent enemy spawns.
		if _world_manager.is_position_illuminated_by_blocks(spawn_pos, 10.0):
			return

		var roll: float = randf()
		if roll < 0.34:
			mob.variant = PassiveMob.MobVariant.ZOMBIE
		elif roll < 0.60:
			mob.variant = PassiveMob.MobVariant.SKELETON
		elif roll < 0.82:
			mob.variant = PassiveMob.MobVariant.CREEPER
		else:
			mob.variant = PassiveMob.MobVariant.SPIDER
	else:
		# During daytime, monsters cannot spawn on the sunny surface; only peaceful animals on grass
		if ground_block != BlockRegistry.BlockId.GRASS:
			return
		var p_roll: float = randf()
		if p_roll < 0.28:
			mob.variant = PassiveMob.MobVariant.SHEEP
		elif p_roll < 0.54:
			mob.variant = PassiveMob.MobVariant.COW
		elif p_roll < 0.78:
			mob.variant = PassiveMob.MobVariant.PIG
		else:
			mob.variant = PassiveMob.MobVariant.CHICKEN

	add_child(mob)
	mob.global_position = spawn_pos
	_mobs.append(mob)
