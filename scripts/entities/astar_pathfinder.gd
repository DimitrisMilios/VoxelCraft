class_name AStarPathFinder
extends RefCounted
## Authentic Beta 1.7.3 3D A* Voxel Pathfinding implementation.
## 3D grid traversal with 4 orthogonal and
## 4 diagonal neighbors, corner-cutting prevention, 1-block jump stepping,
## <=3-block safe drop falls, voxel height clearance checks, and parent backtracking.

const ORTHOGONAL_NEIGHBORS: Array[Vector2i] = [
	Vector2i(0, -1), # North (-Z)
	Vector2i(1, 0),  # East  (+X)
	Vector2i(0, 1),  # South (+Z)
	Vector2i(-1, 0)  # West  (-X)
]

const DIAGONAL_NEIGHBORS: Array[Array] = [
	[Vector2i(0, -1), Vector2i(1, 0)],  # North-East
	[Vector2i(0, -1), Vector2i(-1, 0)], # North-West
	[Vector2i(0, 1), Vector2i(1, 0)],   # South-East
	[Vector2i(0, 1), Vector2i(-1, 0)]   # South-West
]


## Simple Binary Min-Heap for fast priority queue operations.
class MinHeap:
	var items: Array[Dictionary] = []

	func push(pos: Vector3i, priority: float) -> void:
		items.append({"pos": pos, "p": priority})
		_sift_up(items.size() - 1)

	func pop() -> Dictionary:
		if items.is_empty():
			return {}
		var top: Dictionary = items[0]
		var last: Dictionary = items.pop_back()
		if not items.is_empty():
			items[0] = last
			_sift_down(0)
		return top

	func is_empty() -> bool:
		return items.is_empty()

	func _sift_up(idx: int) -> void:
		while idx > 0:
			var parent_idx: int = (idx - 1) >> 1
			if items[idx]["p"] < items[parent_idx]["p"]:
				var tmp: Dictionary = items[idx]
				items[idx] = items[parent_idx]
				items[parent_idx] = tmp
				idx = parent_idx
			else:
				break

	func _sift_down(idx: int) -> void:
		var size: int = items.size()
		while true:
			var left: int = (idx << 1) + 1
			var right: int = left + 1
			var smallest: int = idx
			if left < size and items[left]["p"] < items[smallest]["p"]:
				smallest = left
			if right < size and items[right]["p"] < items[smallest]["p"]:
				smallest = right
			if smallest != idx:
				var tmp: Dictionary = items[idx]
				items[idx] = items[smallest]
				items[smallest] = tmp
				idx = smallest
			else:
				break


## Checks if a voxel coordinate is passable (air, non-solid, water, not solid block, not lava).
static func is_voxel_passable(world: WorldManager, pos: Vector3i) -> bool:
	if world == null:
		return true
	var block_id: int = world.get_block_world(pos)
	if block_id == BlockRegistry.BlockId.AIR:
		return true
	if BlockRegistry.is_water(block_id):
		return true
	if BlockRegistry.is_passable_block(block_id) and not BlockRegistry.is_lava(block_id):
		return true
	return false


## Checks if an entity with given height clearance can occupy `voxel`.
## Feet stand at `voxel.y`, floor is at `voxel.y - 1`.
static func can_occupy_voxel(world: WorldManager, voxel: Vector3i, height_clearance: int = 2) -> bool:
	if world == null:
		return true

	# Ground below must be solid or water
	var floor_pos := Vector3i(voxel.x, voxel.y - 1, voxel.z)
	var floor_id: int = world.get_block_world(floor_pos)
	var has_floor: bool = BlockRegistry.is_solid(floor_id) or BlockRegistry.is_water(floor_id)
	if not has_floor:
		return false

	# Voxel itself and clearance above must be passable
	for y in range(voxel.y, voxel.y + height_clearance):
		var check_pos := Vector3i(voxel.x, y, voxel.z)
		if not is_voxel_passable(world, check_pos):
			return false

	return true


## Finds path from start voxel to goal voxel.
## Returns Array[Vector3i] of waypoints from start to goal (inclusive).
## Returns empty Array if no valid path exists.
static func find_path(
	world: WorldManager,
	start: Vector3i,
	goal: Vector3i,
	height_clearance: int = 2,
	max_iterations: int = 350
) -> Array[Vector3i]:
	if start == goal:
		return [start]

	var open_set := MinHeap.new()
	var parents: Dictionary = {}
	var g_costs: Dictionary = {}
	var closed_set: Dictionary = {}

	g_costs[start] = 0.0
	var initial_h: float = _distance(start, goal)
	open_set.push(start, initial_h)
	parents[start] = start

	var closest_node: Vector3i = start
	var closest_dist: float = initial_h
	var iterations: int = 0

	while not open_set.is_empty() and iterations < max_iterations:
		iterations += 1
		var current_item: Dictionary = open_set.pop()
		var current: Vector3i = current_item["pos"]

		if current == goal:
			return _trace_path(start, goal, parents)

		closed_set[current] = true

		var current_h: float = _distance(current, goal)
		if current_h < closest_dist:
			closest_dist = current_h
			closest_node = current

		var neighbors: Array[Dictionary] = _get_neighbors(world, current, height_clearance)
		for n_info in neighbors:
			var next: Vector3i = n_info["pos"]
			var step_cost: float = n_info["cost"]

			if closed_set.has(next):
				continue

			var new_g: float = g_costs[current] + step_cost
			if not g_costs.has(next) or new_g < g_costs[next]:
				g_costs[next] = new_g
				var h: float = _distance(next, goal)
				var priority: float = new_g + h
				open_set.push(next, priority)
				parents[next] = current

	# If goal not reached, return best partial path to the node closest to goal
	if closest_node != start:
		return _trace_path(start, closest_node, parents)

	return []


static func _get_neighbors(world: WorldManager, current: Vector3i, height_clearance: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	# 1. Orthogonal Neighbors
	for dir in ORTHOGONAL_NEIGHBORS:
		_add_valid_transitions(world, current, dir.x, dir.y, 1.0, height_clearance, result)

	# 2. Diagonal Neighbors (ensure both orthogonal sides are passable to prevent cutting through block corners)
	for pair in DIAGONAL_NEIGHBORS:
		var d1: Vector2i = pair[0]
		var d2: Vector2i = pair[1]
		var side1 := Vector3i(current.x + d1.x, current.y, current.z + d1.y)
		var side2 := Vector3i(current.x + d2.x, current.y, current.z + d2.y)

		# At least one horizontal side or both must be passable
		if is_voxel_passable(world, side1) and is_voxel_passable(world, side2):
			_add_valid_transitions(world, current, d1.x + d2.x, d1.y + d2.y, 1.414, height_clearance, result)

	return result


static func _add_valid_transitions(
	world: WorldManager,
	current: Vector3i,
	dx: int,
	dz: int,
	base_cost: float,
	height_clearance: int,
	out_list: Array[Dictionary]
) -> void:
	var target_x: int = current.x + dx
	var target_z: int = current.z + dz

	# Elevation 0: Flat walk
	var flat_pos := Vector3i(target_x, current.y, target_z)
	if can_occupy_voxel(world, flat_pos, height_clearance):
		out_list.append({"pos": flat_pos, "cost": base_cost})
		return

	# Elevation +1: Step up 1 block (jump)
	# Target voxel at current.y must be solid (the step), and current ceiling must allow jump
	var step_block_pos := Vector3i(target_x, current.y, target_z)
	var step_floor_id: int = world.get_block_world(step_block_pos) if world != null else 0
	if BlockRegistry.is_solid(step_floor_id):
		var up_pos := Vector3i(target_x, current.y + 1, target_z)
		# Ensure current voxel has head clearance to hop up
		var jump_ceiling := Vector3i(current.x, current.y + height_clearance, current.z)
		if is_voxel_passable(world, jump_ceiling) and can_occupy_voxel(world, up_pos, height_clearance):
			out_list.append({"pos": up_pos, "cost": base_cost + 0.35})
			return

	# Elevation -1..-3: Step down / drop from ledge
	# Must be able to walk horizontally through flat_pos
	if is_voxel_passable(world, flat_pos):
		for drop in [1, 2, 3]:
			var down_pos := Vector3i(target_x, current.y - drop, target_z)
			if can_occupy_voxel(world, down_pos, height_clearance):
				out_list.append({"pos": down_pos, "cost": base_cost + 0.2 * float(drop)})
				break


static func _distance(a: Vector3i, b: Vector3i) -> float:
	var dx: float = float(a.x - b.x)
	var dy: float = float(a.y - b.y)
	var dz: float = float(a.z - b.z)
	return sqrt(dx * dx + dy * dy + dz * dz)


static func _trace_path(start: Vector3i, goal: Vector3i, parents: Dictionary) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	var curr: Vector3i = goal
	while curr != start:
		path.append(curr)
		if not parents.has(curr):
			break
		curr = parents[curr]
	path.append(start)
	path.reverse()
	return path
