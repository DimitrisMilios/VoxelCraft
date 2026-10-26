class_name RetroSfxPlayer
extends Node
## Comprehensive Minecraft-style audio manager using high-quality OGG sound effects.
## Provides material-aware footsteps, continuous mining crunches, block breaks & placement,
## 3D spatial mob vocalisations, player vitals (eating, hurt, jumping, swimming), explosions,
## containers, tool breaks, and item pickup cues.

const SOUND_DIR: String = "res://assets/audio/sounds/"
const POOL_2D_SIZE: int = 8
const POOL_3D_SIZE: int = 8

static var _stream_cache: Dictionary = {}

var _players_2d: Array[AudioStreamPlayer] = []
var _next_2d_idx: int = 0

var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_3d_idx: int = 0

var _world_manager: WorldManager = null
var _player: PlayerController = null
var _interactor: BlockInteractor = null

var _last_mining_stage: int = -1

# Sound groups mapping actions to array of audio files
var _sound_groups: Dictionary = {
	# Material Footsteps
	"step_grass": ["sounds_node_step_grass.1.ogg", "sounds_node_step_grass.2.ogg", "sounds_node_step_grass.3.ogg"],
	"step_dirt": ["sounds_node_step_dirt.1.ogg", "sounds_node_step_dirt.2.ogg"],
	"step_stone": ["sounds_node_step_hard.1.ogg", "sounds_node_step_hard.2.ogg", "sounds_node_step_hard.3.ogg"],
	"step_wood": ["sounds_node_step_wood.1.ogg", "sounds_node_step_wood.2.ogg"],
	"step_sand": ["sounds_node_step_sand.1.ogg", "sounds_node_step_sand.2.ogg", "sounds_node_step_sand.3.ogg"],
	"step_snow": ["sounds_node_step_snow.1.ogg", "sounds_node_step_snow.2.ogg", "sounds_node_step_snow.3.ogg", "sounds_node_step_snow.4.ogg", "sounds_node_step_snow.5.ogg"],
	"step_gravel": ["sounds_node_step_gravel.1.ogg", "sounds_node_step_gravel.2.ogg", "sounds_node_step_gravel.3.ogg", "sounds_node_step_gravel.4.ogg"],
	"step_water": ["sounds_node_step_water.1.ogg", "sounds_node_step_water.2.ogg", "sounds_node_step_water.3.ogg", "sounds_node_step_water.4.ogg"],

	# Mining / Digging crunches while hitting a block
	"dig_stone": ["sounds_node_dig_cracky.1.ogg", "sounds_node_dig_cracky.2.ogg", "sounds_node_dig_cracky.3.ogg"],
	"dig_wood": ["sounds_node_dig_choppy.1.ogg", "sounds_node_dig_choppy.2.ogg"],
	"dig_dirt": ["sounds_node_dig_crumbly.ogg"],
	"dig_gravel": ["sounds_node_dig_gravel.1.ogg", "sounds_node_dig_gravel.2.ogg"],
	"dig_leaves": ["sounds_leaves_01.ogg", "sounds_leaves_02.ogg"],

	# Block Broken
	"break_stone": ["sounds_node_dug.1.ogg", "sounds_node_dug.2.ogg"],
	"break_wood": ["sounds_node_dig_choppy.1.ogg", "sounds_node_dug.1.ogg"],
	"break_glass": ["sounds_node_dug_glass.1.ogg", "sounds_node_dug_glass.2.ogg", "sounds_node_dug_glass.3.ogg"],
	"break_gravel": ["sounds_node_dug_gravel.1.ogg", "sounds_node_dug_gravel.2.ogg"],
	"break_general": ["sounds_node_dug.1.ogg", "sounds_node_dug.2.ogg"],

	# Block Placed
	"place_hard": ["sounds_node_place.1.ogg", "sounds_node_place.2.ogg"],
	"place_soft": ["sounds_node_place_soft.1.ogg", "sounds_node_place_soft.2.ogg"],

	# Player Movement & Actions
	"jump": ["sounds_woosh_01.ogg"],
	"splash": ["sounds_node_step_water.1.ogg", "sounds_node_step_water.2.ogg"],
	"hurt": ["sounds_entity_hit.ogg", "sounds_melee_hit_01.ogg", "sounds_melee_hit_02.ogg"],
	"eat": ["sounds_apple_bite.ogg"],
	"slot_tick": ["sounds_node_step_hard.1.ogg"],
	"item_pickup": ["sounds_balloon_pop.ogg", "sounds_coin.ogg"],
	"tool_break": ["sounds_tool_break.1.ogg", "sounds_tool_break.2.ogg"],

	# Containers & Environment
	"door_open": ["sounds_door_open.ogg", "sounds_door_creak.ogg"],
	"door_close": ["sounds_door_close_01.ogg", "sounds_door_close_02.ogg"],
	"explosion": ["sounds_explosion_01.ogg", "sounds_explosion_02.ogg", "sounds_explosion_03.ogg"],
	"fuse": ["sounds_fuse.ogg", "sounds_fuse_short.ogg"],
	"fire_crackle": ["sounds_fire_crackle.ogg"],

	# Mobs
	"zombie_ambient": ["sounds_zombie_growl_01.ogg", "sounds_zombie_growl_02.ogg", "sounds_undead_moan_01.ogg"],
	"zombie_hurt": ["sounds_zombie_damage.ogg"],
	"zombie_death": ["sounds_zombie_death.ogg"],

	"skeleton_ambient": ["sounds_skeleton_bones.ogg"],
	"skeleton_hurt": ["sounds_ghost_damage.ogg"],
	"skeleton_death": ["sounds_ghost_death.ogg"],

	"creeper_fuse": ["sounds_fuse.ogg"],
	"creeper_explode": ["sounds_explosion_01.ogg", "sounds_explosion_02.ogg"],

	"cow_ambient": ["sounds_cow_moo_01.ogg", "sounds_cow_moo_02.ogg"],
	"cow_hurt": ["sounds_cow_moo_01.ogg"],

	"pig_ambient": ["sounds_pig_snort.ogg"],
	"pig_hurt": ["sounds_pig_squeal.ogg"],

	"spider_ambient": ["sounds_cricket.ogg"],
	"spider_hurt": ["sounds_entity_hit.ogg"],

	"sheep_ambient": ["sounds_sheep_baa.ogg"],
	"sheep_hurt": ["sounds_sheep_baa.ogg"],

	"villager_ambient": ["sounds_giraffe_hum.ogg"],
	"villager_hurt": ["sounds_giraffe_hum.ogg"],

	"shears": ["sounds_shears_01.ogg", "sounds_shears_02.ogg"],
	"lava_cool": ["sounds_lava_cool.1.ogg", "sounds_lava_cool.2.ogg", "sounds_lava_cool.3.ogg"],
}


func _ready() -> void:
	add_to_group("sfx_player")

	# Initialize 2D stereo players pool
	for i in range(POOL_2D_SIZE):
		var p2 := AudioStreamPlayer.new()
		p2.volume_db = -4.0
		add_child(p2)
		_players_2d.append(p2)

	# Initialize 3D positional players pool
	for i in range(POOL_3D_SIZE):
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 2.0
		p3.max_distance = 42.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_players_3d.append(p3)

	call_deferred("_bind_signals")


func _exit_tree() -> void:
	for p in _players_2d:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	for p in _players_3d:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_stream_cache.clear()


func _bind_signals() -> void:
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	if _world_manager != null:
		_world_manager.world_saved.connect(_on_world_saved)

	_player = get_tree().get_first_node_in_group("player") as PlayerController
	if _player != null:
		_player.step_taken.connect(_on_step_taken)
		_player.jumped.connect(_on_player_jumped)
		_player.water_state_changed.connect(_on_water_state_changed)
		_player.player_damaged.connect(_on_player_damaged)

		_interactor = _player.get_node_or_null("BlockInteractor") as BlockInteractor
		if _interactor != null:
			_interactor.block_broken.connect(_on_block_broken)
			_interactor.block_placed.connect(_on_block_placed)
			_interactor.hotbar_slot_changed.connect(_on_hotbar_slot_changed)
			_interactor.mob_interacted.connect(_on_mob_interacted)
			_interactor.mining_progress_changed.connect(_on_mining_progress_changed)
			_interactor.station_opened.connect(_on_station_opened)


## Plays a non-positional stereo sound effect.
func play_sfx(group_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var stream: AudioStream = _get_random_stream(group_name)
	if stream == null or _players_2d.is_empty():
		return

	var player: AudioStreamPlayer = _players_2d[_next_2d_idx]
	_next_2d_idx = (_next_2d_idx + 1) % _players_2d.size()

	if not player.is_inside_tree():
		return

	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale * randf_range(0.94, 1.06)
	player.play()


## Plays a 3D positioned sound effect in the world.
func play_sfx_at_pos(group_name: String, world_pos: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0, max_dist: float = 42.0) -> void:
	if not is_inside_tree():
		return
	var stream: AudioStream = _get_random_stream(group_name)
	if stream == null or _players_3d.is_empty():
		return

	var player: AudioStreamPlayer3D = _players_3d[_next_3d_idx]
	_next_3d_idx = (_next_3d_idx + 1) % _players_3d.size()

	if not player.is_inside_tree():
		return

	player.stream = stream
	player.global_position = world_pos
	player.volume_db = volume_db
	player.max_distance = max_dist
	player.pitch_scale = pitch_scale * randf_range(0.94, 1.06)
	player.play()


func _get_random_stream(group_name: String) -> AudioStream:
	if not _sound_groups.has(group_name):
		return null
	var files: Array = _sound_groups[group_name]
	if files.is_empty():
		return null
	var file_name: String = str(files[randi() % files.size()])
	return _load_cached_stream(file_name)


func _load_cached_stream(file_name: String) -> AudioStream:
	if _stream_cache.has(file_name):
		return _stream_cache[file_name]

	var full_path: String = SOUND_DIR + file_name
	if not FileAccess.file_exists(full_path):
		return null

	var stream: AudioStreamOggVorbis = AudioStreamOggVorbis.load_from_file(full_path)
	if stream != null:
		_stream_cache[file_name] = stream
	return stream


# ==============================================================================
# BLOCK MATERIAL AUDIO SELECTORS
# ==============================================================================

func get_step_sfx_for_block(block_id: int) -> String:
	match block_id:
		BlockRegistry.BlockId.GRASS, BlockRegistry.BlockId.LEAVES, BlockRegistry.BlockId.CACTUS:
			return "step_grass"
		BlockRegistry.BlockId.DIRT:
			return "step_dirt"
		BlockRegistry.BlockId.STONE, BlockRegistry.BlockId.COBBLESTONE, \
		BlockRegistry.BlockId.COAL_ORE, BlockRegistry.BlockId.IRON_ORE, \
		BlockRegistry.BlockId.GOLD_ORE, BlockRegistry.BlockId.DIAMOND_ORE, \
		BlockRegistry.BlockId.FURNACE, BlockRegistry.BlockId.GLOWSTONE:
			return "step_stone"
		BlockRegistry.BlockId.WOOD_LOG, BlockRegistry.BlockId.WOOD_PLANKS, \
		BlockRegistry.BlockId.CRAFTING_TABLE, BlockRegistry.BlockId.CHEST, \
		BlockRegistry.BlockId.DOOR_CLOSED, BlockRegistry.BlockId.DOOR_OPEN, BlockRegistry.BlockId.LADDER:
			return "step_wood"
		BlockRegistry.BlockId.SAND, BlockRegistry.BlockId.SANDSTONE:
			return "step_sand"
		BlockRegistry.BlockId.SNOW:
			return "step_snow"
		_:
			return "step_stone"


func get_dig_sfx_for_block(block_id: int) -> String:
	match block_id:
		BlockRegistry.BlockId.STONE, BlockRegistry.BlockId.COBBLESTONE, \
		BlockRegistry.BlockId.COAL_ORE, BlockRegistry.BlockId.IRON_ORE, \
		BlockRegistry.BlockId.GOLD_ORE, BlockRegistry.BlockId.DIAMOND_ORE, \
		BlockRegistry.BlockId.FURNACE:
			return "dig_stone"
		BlockRegistry.BlockId.WOOD_LOG, BlockRegistry.BlockId.WOOD_PLANKS, \
		BlockRegistry.BlockId.CRAFTING_TABLE, BlockRegistry.BlockId.CHEST, \
		BlockRegistry.BlockId.DOOR_CLOSED, BlockRegistry.BlockId.DOOR_OPEN:
			return "dig_wood"
		BlockRegistry.BlockId.DIRT, BlockRegistry.BlockId.GRASS:
			return "dig_dirt"
		BlockRegistry.BlockId.SAND, BlockRegistry.BlockId.SANDSTONE:
			return "dig_gravel"
		BlockRegistry.BlockId.LEAVES, BlockRegistry.BlockId.CACTUS:
			return "dig_leaves"
		_:
			return "dig_stone"


func get_break_sfx_for_block(block_id: int) -> String:
	match block_id:
		BlockRegistry.BlockId.STONE, BlockRegistry.BlockId.COBBLESTONE, \
		BlockRegistry.BlockId.COAL_ORE, BlockRegistry.BlockId.IRON_ORE, \
		BlockRegistry.BlockId.GOLD_ORE, BlockRegistry.BlockId.DIAMOND_ORE, \
		BlockRegistry.BlockId.FURNACE:
			return "break_stone"
		BlockRegistry.BlockId.WOOD_LOG, BlockRegistry.BlockId.WOOD_PLANKS, \
		BlockRegistry.BlockId.CRAFTING_TABLE, BlockRegistry.BlockId.CHEST, \
		BlockRegistry.BlockId.DOOR_CLOSED, BlockRegistry.BlockId.DOOR_OPEN, BlockRegistry.BlockId.LADDER:
			return "break_wood"
		BlockRegistry.BlockId.SAND, BlockRegistry.BlockId.SANDSTONE, BlockRegistry.BlockId.DIRT, BlockRegistry.BlockId.GRASS:
			return "break_gravel"
		_:
			return "break_general"


func get_place_sfx_for_block(block_id: int) -> String:
	match block_id:
		BlockRegistry.BlockId.DIRT, BlockRegistry.BlockId.GRASS, BlockRegistry.BlockId.SAND, \
		BlockRegistry.BlockId.LEAVES, BlockRegistry.BlockId.SNOW, BlockRegistry.BlockId.CACTUS:
			return "place_soft"
		_:
			return "place_hard"


# ==============================================================================
# SIGNAL CALLBACKS
# ==============================================================================

func _on_step_taken(in_water: bool) -> void:
	if in_water:
		play_sfx("step_water", -6.0)
		return

	var ground_id: int = BlockRegistry.BlockId.GRASS
	if _player != null and _world_manager != null:
		var feet_y: int = floori(_player.global_position.y - 0.2)
		var wx: int = floori(_player.global_position.x)
		var wz: int = floori(_player.global_position.z)
		ground_id = _world_manager.get_block_world(Vector3i(wx, feet_y, wz))
		if ground_id == BlockRegistry.BlockId.AIR:
			ground_id = _world_manager.get_block_world(Vector3i(wx, feet_y - 1, wz))

	var step_group: String = get_step_sfx_for_block(ground_id)
	play_sfx(step_group, -8.0)


func _on_player_jumped() -> void:
	play_sfx("jump", -8.0)


func _on_water_state_changed(in_water: bool) -> void:
	if in_water:
		play_sfx("splash", -4.0)


func _on_player_damaged(_amount: int) -> void:
	play_sfx("hurt", -2.0)


func _on_block_broken(world_pos: Vector3i, block_id: int) -> void:
	var sfx: String = get_break_sfx_for_block(block_id)
	play_sfx_at_pos(sfx, Vector3(world_pos) + Vector3(0.5, 0.5, 0.5), -2.0)


func _on_block_placed(world_pos: Vector3i, block_id: int) -> void:
	var sfx: String = get_place_sfx_for_block(block_id)
	play_sfx_at_pos(sfx, Vector3(world_pos) + Vector3(0.5, 0.5, 0.5), -3.0)


func _on_mining_progress_changed(progress: float, _target_name: String, _can_harvest: bool) -> void:
	if progress <= 0.0:
		_last_mining_stage = -1
		return
	var stage: int = int(progress * 5.0)
	if stage != _last_mining_stage and stage > 0:
		_last_mining_stage = stage
		if _interactor != null and _world_manager != null:
			var target_pos: Vector3i = _interactor.get_targeted_block_pos() if _interactor.has_method("get_targeted_block_pos") else _interactor.target_block_pos
			var target_id: int = _world_manager.get_block_world(target_pos)
			var dig_sfx: String = get_dig_sfx_for_block(target_id)
			play_sfx_at_pos(dig_sfx, Vector3(target_pos) + Vector3(0.5, 0.5, 0.5), -5.0)


func _on_hotbar_slot_changed(_slot_index: int, _block_id: int) -> void:
	play_sfx("slot_tick", -10.0)


func _on_station_opened(station_id: int) -> void:
	if station_id == BlockRegistry.BlockId.CHEST:
		play_sfx("door_open", -2.0)
	elif station_id == BlockRegistry.BlockId.DOOR_OPEN:
		play_sfx("door_open", -2.0)
	elif station_id == BlockRegistry.BlockId.DOOR_CLOSED:
		play_sfx("door_close", -3.0)
	else:
		play_sfx("door_close", -4.0)


func _on_mob_interacted(is_hit: bool, mob_variant: int) -> void:
	if is_hit:
		play_sfx("hurt", -2.0)
	else:
		match mob_variant:
			0:
				play_sfx("pig_ambient", -3.0)
			1:
				play_sfx("cow_ambient", -3.0)


func _on_world_saved(_saved_chunk_count: int) -> void:
	play_sfx("item_pickup", -4.0, 1.25)
