extends SceneTree
## Builds a small display of special blocks (doors, logs on every axis, saplings, sugar cane,
## crops, cactus, torches) on a floating platform and saves screenshots. Run with a window:
##
##   Godot --path . -s tools/showcase_blocks.gd
##
## BENCH_OUT sets the screenshot folder. Uses the sandboxed test save folder.

const GameSession = preload("res://scripts/core/game_session.gd")
const B = BlockRegistry.BlockId

var _main: Node = null
var _wm: WorldManager = null
var _player: Node3D = null
var _frame: int = 0
var _phase: int = 0
var _base := Vector3i(8, 90, 8)
var _out_dir: String = ""


func _initialize() -> void:
	_out_dir = OS.get_environment("BENCH_OUT")
	if _out_dir.is_empty():
		_out_dir = OS.get_user_data_dir()
	GameSession.create_world("Showcase", "2027")
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_wm = _main.find_child("WorldManager", true, false) as WorldManager
	_player = _main.find_child("Player", true, false) as Node3D
	var dn: Node = _main.find_child("DayNightCycle", true, false)
	dn.set("day_length_seconds", 0.0)
	dn.set("current_hour", 10.0)
	dn.call("advance_hours", 0.0)


func _put_block(pos: Vector3i, id: int, meta: int = 0) -> void:
	_wm.set_block_world(_base + pos, id, 2, meta)


func _build() -> void:
	# Platform: grass with a sand/water strip for sugar cane.
	for x in range(-1, 14):
		for z in range(-2, 6):
			_put_block(Vector3i(x, -1, z), B.STONE)
			_put_block(Vector3i(x, 0, z), B.GRASS)
	for x in range(-1, 14):
		_put_block(Vector3i(x, 0, 4), B.WATER)
		_put_block(Vector3i(x, 0, 3), B.SAND)

	# Doors facing +Z (toward the camera side): closed left hinge, closed right hinge, open left, open right.
	var f := Vector3i(0, 0, -1)
	var metas: Array[int] = [
		BlockRegistry.door_meta_from_dir(f, false),
		BlockRegistry.door_meta_from_dir(f, true),
		BlockRegistry.door_meta_from_dir(f, false),
		BlockRegistry.door_meta_from_dir(f, true),
	]
	for i in range(4):
		var id: int = B.DOOR_CLOSED if i < 2 else B.DOOR_OPEN
		_put_block(Vector3i(i * 2, 1, 0), id, metas[i])
		_put_block(Vector3i(i * 2, 2, 0), id, metas[i])

	# Logs: oak / spruce / birch, each upright, along X and along Z.
	var logs: Array[int] = [B.WOOD_LOG, B.PINE_LOG, B.BIRCH_LOG]
	for i in range(3):
		_put_block(Vector3i(8 + i * 2, 1, 0), logs[i], 0)
		_put_block(Vector3i(8 + i * 2, 2, 0), logs[i], 1)
		_put_block(Vector3i(8 + i * 2, 3, 0), logs[i], 2)

	# Plants: saplings, flowers, crops, cactus on sand, sugar cane by the water, torch.
	_put_block(Vector3i(0, 1, 2), B.SAPLING)
	_put_block(Vector3i(1, 1, 2), B.PINE_SAPLING)
	_put_block(Vector3i(2, 1, 2), B.BIRCH_SAPLING)
	_put_block(Vector3i(3, 0, 2), B.FARMLAND)
	_put_block(Vector3i(3, 1, 2), B.WHEAT_CROPS)
	_put_block(Vector3i(4, 0, 2), B.FARMLAND)
	_put_block(Vector3i(4, 1, 2), B.POTATO_SPROUT)
	_put_block(Vector3i(5, 1, 2), B.DANDELION)
	_put_block(Vector3i(6, 1, 2), B.ROSE)
	_put_block(Vector3i(7, 0, 2), B.SAND)
	_put_block(Vector3i(7, 1, 2), B.CACTUS)
	_put_block(Vector3i(7, 2, 2), B.CACTUS)
	for x in [9, 10, 12]:
		_put_block(Vector3i(x, 1, 3), B.SUGAR_CANE)
		_put_block(Vector3i(x, 2, 3), B.SUGAR_CANE)
	_put_block(Vector3i(10, 3, 3), B.SUGAR_CANE)
	_put_block(Vector3i(11, 1, 2), B.TORCH)
	# Wheat at every growth stage, then ripe; a glass window.
	for age in range(7):
		_put_block(Vector3i(age, 0, 1), B.FARMLAND)
		_put_block(Vector3i(age, 1, 1), B.WHEAT_SPROUT, age)
	_put_block(Vector3i(13, 1, 2), B.GLASS)
	_put_block(Vector3i(13, 2, 2), B.GLASS)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		0:
			if _wm.get_active_chunk_count() >= 81 or _frame > 2000:
				_build()
				_place_camera(Vector3(6.5, 3.2, 8.0), 0.0, -0.42)
				_phase = 1
				_frame = 0
		1:
			if _frame > 40:
				_shot("showcase_front.png")
				_place_camera(Vector3(-3.5, 3.4, 7.0), -0.75, -0.40)
				_phase = 2
				_frame = 0
		2:
			if _frame > 20:
				_shot("showcase_side.png")
				var dn: Node = _main.find_child("DayNightCycle", true, false)
				dn.set("current_hour", 23.0)
				dn.call("advance_hours", 0.0)
				_place_camera(Vector3(6.5, 3.2, 8.0), 0.0, -0.42)
				_phase = 3
				_frame = 0
		3:
			if _frame > 20:
				_shot("showcase_night.png")
				_main.queue_free()
				return true
	if _player != null:
		_player.set("velocity", Vector3.ZERO)
	return false


func _place_camera(offset: Vector3, yaw: float, pitch: float) -> void:
	_player.global_position = Vector3(_base) + offset - Vector3(0.0, 1.62, 0.0)
	_player.rotation.y = yaw
	var head: Node3D = _player.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation.x = pitch
	_player.set("is_flying", true)


func _shot(file_name: String) -> void:
	var path: String = _out_dir.path_join(file_name)
	root.get_texture().get_image().save_png(path)
	print("[Showcase] Saved " + path)
