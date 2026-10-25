class_name VoxelAtlasBuilder
extends RefCounted
## Generates a crisp 16x16 per-tile retro pixel-art texture atlas and shared chunk material.

static var _cached_material: StandardMaterial3D = null
static var _cached_water_material: StandardMaterial3D = null
static var _cached_texture: ImageTexture = null


static func get_shared_voxel_material() -> StandardMaterial3D:
	if _cached_material != null:
		return _cached_material

	var material := StandardMaterial3D.new()
	material.albedo_texture = get_atlas_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.metallic = 0.0
	_cached_material = material
	return _cached_material


static func get_shared_water_material() -> StandardMaterial3D:
	if _cached_water_material != null:
		return _cached_water_material

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0.16, 0.48, 0.88, 0.64)
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.15
	material.metallic = 0.05
	_cached_water_material = material
	return _cached_water_material


static func get_atlas_texture() -> ImageTexture:
	if _cached_texture != null:
		return _cached_texture

	var tile_size: int = BlockRegistry.TILE_PIXEL_SIZE
	var width: int = BlockRegistry.ATLAS_COLUMNS * tile_size
	var height: int = BlockRegistry.ATLAS_ROWS * tile_size
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337

	for tile_idx in range(BlockRegistry.ATLAS_COLUMNS):
		var offset_x: int = tile_idx * tile_size
		_paint_tile(img, tile_idx, offset_x, 0, tile_size, rng)

	_cached_texture = ImageTexture.create_from_image(img)
	return _cached_texture


static func _paint_tile(
	img: Image,
	tile_idx: int,
	ox: int,
	oy: int,
	size: int,
	rng: RandomNumberGenerator
) -> void:
	for y in range(size):
		for x in range(size):
			var jitter: float = rng.randf_range(-0.045, 0.045)
			var color: Color = _sample_tile_pixel(tile_idx, x, y, size, jitter, rng)
			img.set_pixel(ox + x, oy + y, color)


static func _sample_tile_pixel(
	tile_idx: int,
	x: int,
	y: int,
	size: int,
	jitter: float,
	rng: RandomNumberGenerator
) -> Color:
	var grass_base := Color(0.36, 0.71, 0.28)
	var dirt_base := Color(0.53, 0.36, 0.21)
	var stone_base := Color(0.52, 0.54, 0.56)
	var bark_base := Color(0.41, 0.27, 0.14)
	var ring_base := Color(0.68, 0.53, 0.31)
	var leaf_base := Color(0.24, 0.56, 0.20)
	var sand_base := Color(0.86, 0.80, 0.54)
	var cobble_base := Color(0.44, 0.46, 0.48)
	var plank_base := Color(0.68, 0.52, 0.30)

	match tile_idx:
		0: # Grass Top
			var blade_shift: float = -0.04 if ((x + y * 3) % 5 == 0) else 0.0
			return _tint(grass_base, jitter + blade_shift)

		1: # Grass Side (Dirt with irregular grass fringe at top)
			var fringe_depth: int = 3 + ((x * 7 + 3) % 3)
			if y < fringe_depth:
				return _tint(grass_base, jitter - 0.02)
			elif y == fringe_depth:
				return _tint(dirt_base, jitter - 0.06)
			else:
				var pebble: float = -0.05 if ((x * 5 + y * 3) % 11 == 0) else 0.0
				return _tint(dirt_base, jitter + pebble)

		2: # Dirt
			var pebble: float = -0.05 if ((x * 5 + y * 3) % 9 == 0) else 0.0
			return _tint(dirt_base, jitter + pebble)

		3: # Stone
			var strata: float = -0.05 if ((y % 4 == 0) and (x % 3 != 0)) else 0.0
			var highlight: float = 0.04 if ((x + y) % 7 == 0) else 0.0
			return _tint(stone_base, jitter + strata + highlight)

		4: # Wood Log Side (Vertical bark ridges)
			var ridge: float = -0.06 if (x % 3 == 0) else 0.02
			return _tint(bark_base, jitter + ridge)

		5: # Wood Log Top/Bottom (Concentric growth rings)
			if x == 0 or x == size - 1 or y == 0 or y == size - 1:
				return _tint(bark_base, jitter)
			var dx: int = absi(x - size / 2)
			var dy: int = absi(y - size / 2)
			var ring_dist: int = maxi(dx, dy)
			var ring_shade: float = -0.06 if (ring_dist % 2 == 0) else 0.02
			return _tint(ring_base, jitter + ring_shade)

		6: # Leaves
			var dapple: float = -0.07 if (rng.randf() < 0.28) else 0.03
			return _tint(leaf_base, jitter + dapple)

		7: # Sand (Warm beach ripples and fine grain)
			var ripple: float = 0.03 if ((x + y * 2) % 6 == 0) else -0.02
			return _tint(sand_base, jitter * 0.65 + ripple)

		8: # Cobblestone (Interlocking masonry mortar lines)
			var mortar_row: bool = (y % 4 == 0)
			var offset_col: int = (y / 4) * 2
			var mortar_col: bool = ((x + offset_col) % 4 == 0)
			var crack_shade: float = -0.12 if (mortar_row or mortar_col) else 0.04
			return _tint(cobble_base, jitter + crack_shade)

		9: # Wood Planks (Horizontal plank boards with staggered joints)
			var board_seam: bool = (y % 4 == 3)
			var joint_x: int = 7 if ((y / 4) % 2 == 0) else 13
			var vertical_joint: bool = (x == joint_x)
			var seam_shade: float = -0.10 if (board_seam or vertical_joint) else 0.02
			return _tint(plank_base, jitter * 0.6 + seam_shade)

		_:
			return _tint(stone_base, jitter)


static func _tint(base: Color, delta: float) -> Color:
	return Color(
		clampf(base.r + delta, 0.0, 1.0),
		clampf(base.g + delta, 0.0, 1.0),
		clampf(base.b + delta, 0.0, 1.0),
		1.0
	)
