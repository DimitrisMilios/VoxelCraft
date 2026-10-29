class_name GameSession
extends RefCounted
## Manages world save slots, metadata persistence (level.json), player spawn/bed coordinates,
## inventory state, time of day, and transitions between the Main Menu and active game.

const SAVE_ROOT: String = "user://worlds"
## Saves used when the engine runs a tool or test script (`-s` / `--script`), so automated runs
## can never read or overwrite real player worlds.
const TOOL_SAVE_ROOT: String = "user://test_worlds"

static var active_world_id: String = ""
static var active_world_name: String = "New World"
static var active_seed: int = 2027
static var active_world_data: Dictionary = {}


## Returns absolute path to the worlds directory.
static func get_worlds_dir() -> String:
	return ProjectSettings.globalize_path(get_save_root())


static var _is_script_run: int = -1

## `user://worlds` for the game; `user://test_worlds` when running a tool/test script.
static func get_save_root() -> String:
	if _is_script_run < 0:
		var args: PackedStringArray = OS.get_cmdline_args()
		_is_script_run = 1 if (args.has("-s") or args.has("--script")) else 0
	return TOOL_SAVE_ROOT if _is_script_run == 1 else SAVE_ROOT


## Returns absolute path to the active world's folder.
static func get_active_world_dir() -> String:
	if active_world_id.is_empty():
		var saved: Array[Dictionary] = list_saved_worlds()
		if not saved.is_empty() and str(saved[0].get("id", "")).length() > 0:
			select_world(str(saved[0]["id"]))
		else:
			active_world_id = "default_world"
	return get_worlds_dir() + "/" + active_world_id


## Returns absolute path to the active world's chunk storage folder.
static func get_active_chunk_dir() -> String:
	return get_active_world_dir() + "/chunks"


## Lists all saved worlds found in `user://worlds/`, sorted by last played (most recent first).
static func list_saved_worlds() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var root: String = get_worlds_dir()
	if not DirAccess.dir_exists_absolute(root):
		DirAccess.make_dir_recursive_absolute(root)
		return result

	var dir := DirAccess.open(root)
	if dir == null:
		return result

	dir.list_dir_begin()
	var folder: String = dir.get_next()
	while not folder.is_empty():
		if dir.current_is_dir() and not folder.begins_with("."):
			var level_path: String = root + "/" + folder + "/level.json"
			if FileAccess.file_exists(level_path):
				var data: Dictionary = _read_json_file(level_path)
				data["id"] = folder
				result.append(data)
			else:
				# Folder exists without level.json; check for seed folder
				var legacy_seed: int = 2027
				if folder.begins_with("seed_"):
					legacy_seed = folder.substr(5).to_int()
				result.append({
					"id": folder,
					"world_name": folder.capitalize(),
					"seed": legacy_seed,
					"last_played": 0,
				})
		folder = dir.get_next()
	dir.list_dir_end()

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("last_played", 0)) > int(b.get("last_played", 0))
	)
	return result


## Creates a brand new world folder with a fresh unique seed and default metadata.
static func create_world(world_name: String, custom_seed_str: String = "") -> String:
	var clean_name: String = world_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "New World"

	var chosen_seed: int = 0
	if custom_seed_str.strip_edges().is_empty():
		# Generate a fresh random seed for each new world
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		chosen_seed = absi(int(Time.get_unix_time_from_system()) ^ rng.randi()) % 100000000 + 1
	elif custom_seed_str.is_valid_int():
		chosen_seed = custom_seed_str.to_int()
	else:
		chosen_seed = absi(custom_seed_str.hash()) % 100000000 + 1

	# Generate safe folder ID
	var safe_id: String = clean_name.to_lower().replace(" ", "_").validate_filename()
	if safe_id.is_empty():
		safe_id = "world"
	var candidate: String = safe_id
	var counter: int = 1
	var root: String = get_worlds_dir()
	while DirAccess.dir_exists_absolute(root + "/" + candidate):
		candidate = "%s_%d" % [safe_id, counter]
		counter += 1

	var world_dir: String = root + "/" + candidate
	var chunk_dir: String = world_dir + "/chunks"
	DirAccess.make_dir_recursive_absolute(chunk_dir)

	var initial_data: Dictionary = {
		"world_name": clean_name,
		"seed": chosen_seed,
		"created_at": Time.get_unix_time_from_system(),
		"last_played": Time.get_unix_time_from_system(),
		"player": {
			"has_saved_pos": false,
			"health": 20,
			"hunger": 20,
			"oxygen": 10,
			"is_flying": false,
			"has_bed": false,
			"bed_pos": [0.0, 0.0, 0.0],
		},
		"inventory": {
			"slots": [],
		},
		"day_night": {
			"hour": 9.5,
			"day": 1,
		},
		"world_chests": {},
		"world_furnaces": {},
	}

	_write_json_file(world_dir + "/level.json", initial_data)

	active_world_id = candidate
	active_world_name = clean_name
	active_seed = chosen_seed
	active_world_data = initial_data
	return candidate


## Prepares the session to load an existing world.
static func select_world(world_id: String) -> bool:
	var world_dir: String = get_worlds_dir() + "/" + world_id
	var level_path: String = world_dir + "/level.json"
	if not FileAccess.file_exists(level_path):
		return false
	var data: Dictionary = _read_json_file(level_path)
	active_world_id = world_id
	active_world_name = str(data.get("world_name", world_id))
	active_seed = int(data.get("seed", 2027))
	active_world_data = data
	return true


## Deletes a world save folder and all its chunks permanently.
static func delete_world(world_id: String) -> void:
	var world_dir: String = get_worlds_dir() + "/" + world_id
	if DirAccess.dir_exists_absolute(world_dir):
		_delete_recursive(world_dir)


## Saves all current game state (player position, inventory, chests, day/night, bed) into level.json.
static func save_world_state(
	player: Node3D,
	inventory: Node,
	day_night: Node,
	world_manager: Node3D
) -> void:
	if active_world_id.is_empty():
		var saved: Array[Dictionary] = list_saved_worlds()
		if not saved.is_empty() and str(saved[0].get("id", "")).length() > 0:
			select_world(str(saved[0]["id"]))
		else:
			active_world_id = "default_world"
	var world_dir: String = get_active_world_dir()
	if not DirAccess.dir_exists_absolute(world_dir):
		DirAccess.make_dir_recursive_absolute(world_dir + "/chunks")

	var data: Dictionary = active_world_data.duplicate(true)
	data["world_name"] = active_world_name
	data["seed"] = active_seed
	data["last_played"] = Time.get_unix_time_from_system()

	# 1. Player State & Bed Respawn Position (only overwrite if valid node provided)
	if player != null and is_instance_valid(player):
		var player_dict: Dictionary = {}
		var p_pos: Vector3 = player.global_position if (player is Node3D and player.is_inside_tree()) else (player.position if player is Node3D else Vector3.ZERO)
		player_dict["has_saved_pos"] = true
		player_dict["pos"] = [p_pos.x, p_pos.y, p_pos.z]
		var head: Node3D = player.get_node_or_null("Head") as Node3D
		player_dict["yaw"] = player.rotation.y if player is Node3D else 0.0
		player_dict["pitch"] = head.rotation.x if head != null else 0.0
		player_dict["health"] = int(player.get("current_health"))
		player_dict["hunger"] = int(player.get("current_hunger"))
		player_dict["oxygen"] = int(player.get("current_oxygen"))
		player_dict["is_flying"] = bool(player.get("is_flying"))

		var has_bed: bool = bool(player.get("has_custom_respawn"))
		player_dict["has_bed"] = has_bed
		if has_bed:
			var b_pos: Vector3 = player.get("custom_respawn_pos")
			player_dict["bed_pos"] = [b_pos.x, b_pos.y, b_pos.z]
		data["player"] = player_dict

	# 2. Inventory & Furnace State (only overwrite if valid node provided)
	if inventory != null and is_instance_valid(inventory):
		# Return cursor stack and crafting grid items into main inventory first
		if inventory.has_method("return_crafting_grid_to_inventory"):
			inventory.return_crafting_grid_to_inventory()

		if inventory.has_method("serialize_state"):
			data["inventory"] = inventory.serialize_state()
		else:
			var inv_dict: Dictionary = {}
			inv_dict["slots"] = inventory.get("slots")
			inv_dict["armor_slots"] = inventory.get("armor_slots")
			inv_dict["furnace_input"] = inventory.get("furnace_input")
			inv_dict["furnace_fuel"] = inventory.get("furnace_fuel")
			inv_dict["furnace_output"] = inventory.get("furnace_output")
			inv_dict["furnace_burn_remaining"] = float(inventory.get("furnace_burn_remaining"))
			inv_dict["furnace_burn_max"] = float(inventory.get("furnace_burn_max"))
			inv_dict["furnace_cook_progress"] = float(inventory.get("furnace_cook_progress"))
			data["inventory"] = inv_dict

		# 3. Placed World Chests
		if inventory.has_method("serialize_chests"):
			data["world_chests"] = inventory.serialize_chests()
		else:
			var chests: Dictionary = inventory.get("world_chests")
			var chest_serialized: Dictionary = {}
			for c_pos in chests.keys():
				var key_str: String = "%d,%d,%d" % [c_pos.x, c_pos.y, c_pos.z]
				chest_serialized[key_str] = chests[c_pos]
			data["world_chests"] = chest_serialized

		# 3b. Placed World Furnaces
		if inventory.has_method("serialize_furnaces"):
			data["world_furnaces"] = inventory.serialize_furnaces()
		else:
			var furnaces: Dictionary = inventory.get("world_furnaces")
			var furnace_serialized: Dictionary = {}
			if furnaces is Dictionary:
				for f_pos in furnaces.keys():
					var key_str: String = "%d,%d,%d" % [f_pos.x, f_pos.y, f_pos.z]
					furnace_serialized[key_str] = furnaces[f_pos]
			data["world_furnaces"] = furnace_serialized

	# 4. Day / Night Cycle (only overwrite if valid node provided)
	if day_night != null and is_instance_valid(day_night):
		var dn_dict: Dictionary = {}
		dn_dict["hour"] = float(day_night.get("current_hour"))
		dn_dict["day"] = int(day_night.get("day_number"))
		data["day_night"] = dn_dict

	active_world_data = data
	_write_json_file(world_dir + "/level.json", data)


static func _read_json_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		return json.data as Dictionary
	return {}


static func _write_json_file(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


static func _delete_recursive(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir != null:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while not file_name.is_empty():
			if file_name != "." and file_name != "..":
				var full: String = dir_path + "/" + file_name
				if dir.current_is_dir():
					_delete_recursive(full)
				else:
					DirAccess.remove_absolute(full)
			file_name = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(dir_path)
