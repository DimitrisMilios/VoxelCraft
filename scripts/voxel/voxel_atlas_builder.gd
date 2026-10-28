class_name VoxelAtlasBuilder
extends RefCounted
## Builds the block texture atlas, the per-tile texture array used by terrain, and the shared
## block materials. Tiles that the shipped atlas does not contain (spruce/birch wood, saplings,
## extra ores...) are derived from existing tiles at load time.

static var _cached_material: StandardMaterial3D = null
static var _cached_water_material: Material = null
static var _cached_texture: ImageTexture = null
static var _cached_atlas_image: Image = null
static var _cached_texture_array: Texture2DArray = null
static var _terrain_opaque: ShaderMaterial = null
static var _terrain_cutout: ShaderMaterial = null


## Unshaded terrain material (baked light). `cutout` = alpha-tested variant for foliage/plants.
## Create these on the main thread before meshing starts; worker threads only read the cache.
static func get_terrain_material(cutout: bool) -> ShaderMaterial:
	if _terrain_opaque == null:
		var arr: Texture2DArray = get_atlas_texture_array()
		_terrain_opaque = ShaderMaterial.new()
		_terrain_opaque.shader = load("res://shaders/voxel_terrain.gdshader") as Shader
		_terrain_opaque.set_shader_parameter("atlas", arr)
		_terrain_cutout = ShaderMaterial.new()
		_terrain_cutout.shader = load("res://shaders/voxel_terrain_cutout.gdshader") as Shader
		_terrain_cutout.set_shader_parameter("atlas", arr)
	return _terrain_cutout if cutout else _terrain_opaque


## Lit material for block-shaped entities (held block, dropped items, falling blocks).
static func get_shared_voxel_material() -> StandardMaterial3D:
	if _cached_material != null:
		return _cached_material

	var material := StandardMaterial3D.new()
	material.albedo_texture = get_atlas_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_cached_material = material
	return _cached_material


static func get_shared_water_material() -> Material:
	if _cached_water_material != null:
		return _cached_water_material

	var shader: Shader = load("res://shaders/water.gdshader") as Shader
	var s_mat := ShaderMaterial.new()
	s_mat.shader = shader
	s_mat.set_shader_parameter("water_color", Color(0.20, 0.50, 0.88, 0.70))
	s_mat.set_shader_parameter("deep_color", Color(0.06, 0.26, 0.58, 0.88))
	s_mat.set_shader_parameter("normal_strength", 0.85)

	var wave1_img: Image = TexturePack.load_image("res://assets/textures/water_wave_normal_1.png")
	if wave1_img != null:
		s_mat.set_shader_parameter("wave_normal_1", ImageTexture.create_from_image(wave1_img))
	var wave2_img: Image = TexturePack.load_image("res://assets/textures/water_wave_normal_2.png")
	if wave2_img != null:
		s_mat.set_shader_parameter("wave_normal_2", ImageTexture.create_from_image(wave2_img))

	_cached_water_material = s_mat
	return _cached_water_material


## Water animates in its shader (TIME); nothing to update per frame.
static func update_water_animation(_delta: float) -> void:
	pass


static func get_atlas_texture() -> ImageTexture:
	if _cached_texture != null:
		return _cached_texture
	_cached_atlas_image = _build_atlas_image()
	_cached_texture = ImageTexture.create_from_image(_cached_atlas_image)
	return _cached_texture


## One mip-mapped layer per atlas tile, so distant terrain is filtered without tile bleeding.
static func get_atlas_texture_array() -> Texture2DArray:
	if _cached_texture_array != null:
		return _cached_texture_array
	get_atlas_texture()
	var img: Image = _cached_atlas_image
	var ts: int = img.get_height()
	var cols: int = img.get_width() / ts
	var layers: Array[Image] = []
	for i in range(cols):
		var layer: Image = img.get_region(Rect2i(i * ts, 0, ts, ts))
		layer.convert(Image.FORMAT_RGBA8)
		layer.generate_mipmaps()
		layers.append(layer)
	_cached_texture_array = Texture2DArray.new()
	_cached_texture_array.create_from_images(layers)
	return _cached_texture_array


static func _build_atlas_image() -> Image:
	var target_cols: int = BlockRegistry.ATLAS_TILE_COUNT
	var baked_img: Image = TexturePack.load_image("res://assets/textures/block_atlas.png")
	if baked_img == null:
		# Fallback procedural pixel-art atlas if `block_atlas.png` is missing
		var tile_size: int = BlockRegistry.TILE_PIXEL_SIZE
		var img := Image.create(target_cols * tile_size, tile_size, false, Image.FORMAT_RGBA8)
		var rng0 := RandomNumberGenerator.new()
		rng0.seed = 1337
		for tile_idx in range(target_cols):
			_paint_tile(img, tile_idx, tile_idx * tile_size, 0, tile_size, rng0)
		_add_derived_tiles(img, tile_size, 44)
		BlockRegistry.atlas_columns = target_cols
		return img

	baked_img.convert(Image.FORMAT_RGBA8)
	var ts: int = maxi(1, baked_img.get_height())
	var existing_cols: int = maxi(1, baked_img.get_width() / ts)
	if existing_cols >= target_cols:
		BlockRegistry.atlas_columns = existing_cols
		return baked_img

	var ext_img := Image.create(target_cols * ts, ts, false, Image.FORMAT_RGBA8)
	ext_img.blit_rect(baked_img, Rect2i(0, 0, existing_cols * ts, ts), Vector2i.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	# Flowers, mushrooms and the spawner cage are painted as 16x16 pixel art (the painter draws
	# them bottom-up, so flip) and scaled up crisply; everything else is derived below.
	for tile_idx in [49, 50, 51, 52, 57]:
		if tile_idx >= existing_cols:
			var small := Image.create(16, 16, false, Image.FORMAT_RGBA8)
			_paint_tile(small, tile_idx, 0, 0, 16, rng)
			if tile_idx != 57:
				small.flip_y()
			small.resize(ts, ts, Image.INTERPOLATE_NEAREST)
			ext_img.blit_rect(small, Rect2i(0, 0, ts, ts), Vector2i(tile_idx * ts, 0))
	_add_derived_tiles(ext_img, ts, existing_cols)
	BlockRegistry.atlas_columns = target_cols
	return ext_img


# ============================================================================
# DERIVED TILES
# ============================================================================

static func _tile(img: Image, idx: int, ts: int) -> Image:
	return img.get_region(Rect2i(idx * ts, 0, ts, ts))


static func _put(img: Image, idx: int, ts: int, tile: Image) -> void:
	img.blit_rect(tile, Rect2i(0, 0, ts, ts), Vector2i(idx * ts, 0))


static func _lum(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


## Replaces painted placeholder tiles with versions built from the real textures.
static func _add_derived_tiles(img: Image, ts: int, first_new: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var oak_side: Image = _tile(img, 4, ts)
	var oak_top: Image = _tile(img, 5, ts)
	var oak_leaves: Image = _tile(img, 6, ts)
	var stone: Image = _tile(img, 3, ts)
	var coal: Image = _tile(img, 12, ts)
	var oak_leaf_lum: float = _average_lum(oak_leaves)

	if first_new <= 44:
		_put(img, 44, ts, _crop_sprout(_tile(img, 38, ts), 0.42, Color(0.36, 0.72, 0.20)))
	if first_new <= 45:
		_put(img, 45, ts, _crop_sprout(_tile(img, 39, ts), 0.48, Color(0.30, 0.66, 0.22)))
	if first_new <= 46:
		_put(img, 46, ts, _pebbles(ts, rng))
	if first_new <= 47:
		_put(img, 47, ts, _noise_tile(ts, rng, Color(0.62, 0.65, 0.72), 0.035))
	if first_new <= 48:
		_put(img, 48, ts, _ice_tile(ts, rng))

	var spruce_side: Image = _tint_multiply(oak_side, Color(0.56, 0.45, 0.40))
	var birch_side: Image = _birch_bark(ts, rng)
	if first_new <= 53:
		_put(img, 53, ts, spruce_side)
	if first_new <= 54:
		_put(img, 54, ts, _recolor_foliage(oak_leaves, oak_leaf_lum, Color(0.30, 0.48, 0.30)))
	if first_new <= 55:
		_put(img, 55, ts, birch_side)
	if first_new <= 56:
		_put(img, 56, ts, _recolor_foliage(oak_leaves, oak_leaf_lum, Color(0.47, 0.62, 0.31)))
	if first_new <= 58:
		_put(img, 58, ts, _bedrock(stone, rng))
	if first_new <= 59:
		_put(img, 59, ts, _recolor_ore(stone, coal, Color(0.92, 0.10, 0.08)))
	if first_new <= 60:
		_put(img, 60, ts, _recolor_ore(stone, coal, Color(0.14, 0.30, 0.86)))

	_put(img, BlockRegistry.TILE_PINE_LOG_TOP, ts, _log_top(oak_top, spruce_side, Color(0.72, 0.58, 0.48), 0.0))
	_put(img, BlockRegistry.TILE_BIRCH_LOG_TOP, ts, _log_top(oak_top, birch_side, Color(1.12, 1.10, 0.98), 0.12))
	_put(img, BlockRegistry.TILE_OAK_SAPLING, ts, _sapling(ts, _tile(img, 6, ts), oak_side, false))
	_put(img, BlockRegistry.TILE_PINE_SAPLING, ts, _sapling(ts, _tile(img, 54, ts), spruce_side, true))
	_put(img, BlockRegistry.TILE_BIRCH_SAPLING, ts, _sapling(ts, _tile(img, 56, ts), birch_side, false))


static func _average_lum(src: Image) -> float:
	var total: float = 0.0
	var n: int = 0
	for y in range(0, src.get_height(), 2):
		for x in range(0, src.get_width(), 2):
			total += _lum(src.get_pixel(x, y))
			n += 1
	return maxf(total / float(maxi(n, 1)), 0.01)


static func _tint_multiply(src: Image, mul: Color) -> Image:
	var out: Image = src.duplicate()
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c: Color = out.get_pixel(x, y)
			out.set_pixel(x, y, Color(clampf(c.r * mul.r, 0.0, 1.0), clampf(c.g * mul.g, 0.0, 1.0), clampf(c.b * mul.b, 0.0, 1.0), c.a))
	return out


static func _recolor_foliage(src: Image, avg_lum: float, target: Color) -> Image:
	var out: Image = src.duplicate()
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c: Color = out.get_pixel(x, y)
			var k: float = _lum(c) / avg_lum
			out.set_pixel(x, y, Color(clampf(target.r * k, 0.0, 1.0), clampf(target.g * k, 0.0, 1.0), clampf(target.b * k, 0.0, 1.0), c.a))
	return out


## Log end: the outer ring is the species' bark, the inside is the oak growth rings recolored.
static func _log_top(oak_top: Image, bark: Image, ring_mul: Color, whiten: float) -> Image:
	var ts: int = oak_top.get_width()
	var border: int = maxi(1, ts / 16)
	var out: Image = oak_top.duplicate()
	for y in range(ts):
		for x in range(ts):
			if x < border or y < border or x >= ts - border or y >= ts - border:
				out.set_pixel(x, y, bark.get_pixel(x, y))
				continue
			var c: Color = oak_top.get_pixel(x, y)
			var r := Color(clampf(c.r * ring_mul.r, 0.0, 1.0), clampf(c.g * ring_mul.g, 0.0, 1.0), clampf(c.b * ring_mul.b, 0.0, 1.0), 1.0)
			out.set_pixel(x, y, r.lerp(Color(0.92, 0.88, 0.76), whiten))
	return out


## White birch bark with the characteristic dark horizontal lenticel streaks.
static func _birch_bark(ts: int, rng: RandomNumberGenerator) -> Image:
	var out := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	var px: int = maxi(1, ts / 16)
	for y in range(ts):
		for x in range(ts):
			var n: float = rng.randf_range(-0.035, 0.035)
			var stripe: float = -0.03 if ((x / px) % 5 == 0) else 0.0
			out.set_pixel(x, y, Color(0.86 + n + stripe, 0.85 + n + stripe, 0.81 + n + stripe, 1.0))
	# Dark streaks on a coarse grid so they stay crisp at any tile resolution.
	var cells: int = 16
	for row in range(cells):
		var cx: int = 0
		while cx < cells:
			var length: int = rng.randi_range(1, 4)
			if rng.randf() < 0.24:
				var dark := Color(0.16, 0.15, 0.14) if rng.randf() < 0.7 else Color(0.33, 0.31, 0.29)
				for i in range(length):
					var gx: int = (cx + i) % cells
					for yy in range(px):
						for xx in range(px):
							out.set_pixel(gx * px + xx, row * px + yy, dark)
			cx += length + rng.randi_range(1, 3)
	return out


static func _crop_sprout(src: Image, keep_frac: float, green: Color) -> Image:
	var ts: int = src.get_width()
	var out := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	var cut: int = int(float(ts) * (1.0 - keep_frac))
	for y in range(ts):
		for x in range(ts):
			var c: Color = src.get_pixel(x, y)
			if y < cut or c.a < 0.5:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var k: float = clampf(_lum(c) * 1.6, 0.35, 1.25)
			out.set_pixel(x, y, Color(clampf(green.r * k, 0.0, 1.0), clampf(green.g * k, 0.0, 1.0), clampf(green.b * k, 0.0, 1.0), 1.0))
	return out


static func _noise_tile(ts: int, rng: RandomNumberGenerator, base: Color, amount: float) -> Image:
	var out := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	var px: int = maxi(1, ts / 16)
	for gy in range(16):
		for gx in range(16):
			var n: float = rng.randf_range(-amount, amount)
			var c := Color(clampf(base.r + n, 0.0, 1.0), clampf(base.g + n, 0.0, 1.0), clampf(base.b + n, 0.0, 1.0), 1.0)
			for yy in range(px):
				for xx in range(px):
					out.set_pixel(gx * px + xx, gy * px + yy, c)
	return out


static func _pebbles(ts: int, rng: RandomNumberGenerator) -> Image:
	var out: Image = _noise_tile(ts, rng, Color(0.50, 0.48, 0.47), 0.04)
	var px: int = maxi(1, ts / 16)
	var shades: Array[Color] = [Color(0.66, 0.64, 0.62), Color(0.38, 0.36, 0.36), Color(0.56, 0.52, 0.50), Color(0.28, 0.27, 0.28)]
	for i in range(22):
		var cx: int = rng.randi_range(0, 15)
		var cy: int = rng.randi_range(0, 15)
		var w: int = rng.randi_range(1, 3)
		var h: int = rng.randi_range(1, 2)
		var shade: Color = shades[rng.randi_range(0, shades.size() - 1)]
		for gy in range(h):
			for gx in range(w):
				var tx: int = (cx + gx) % 16
				var ty: int = (cy + gy) % 16
				for yy in range(px):
					for xx in range(px):
						out.set_pixel(tx * px + xx, ty * px + yy, shade)
	return out


static func _ice_tile(ts: int, rng: RandomNumberGenerator) -> Image:
	var out := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	for y in range(ts):
		for x in range(ts):
			var n: float = rng.randf_range(-0.02, 0.02)
			var streak: bool = ((x * 3 + y) % (ts / 2)) < maxi(1, ts / 32)
			var c := Color(0.62 + n, 0.78 + n, 0.98, 0.9)
			if streak:
				c = Color(0.86, 0.93, 1.0, 0.95)
			out.set_pixel(x, y, c)
	return out


static func _bedrock(stone: Image, rng: RandomNumberGenerator) -> Image:
	var ts: int = stone.get_width()
	var out := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	var px: int = maxi(1, ts / 16)
	var blotch := PackedFloat32Array()
	blotch.resize(256)
	for i in range(256):
		blotch[i] = rng.randf_range(-0.22, 0.22)
	for y in range(ts):
		for x in range(ts):
			var g: float = _lum(stone.get_pixel(x, y))
			var v: float = clampf((g - 0.5) * 1.8 + 0.30 + blotch[(y / px) * 16 + (x / px)], 0.04, 0.75)
			out.set_pixel(x, y, Color(v, v, v, 1.0))
	return out


## Ore built from the coal-ore pattern: pixels that differ from plain stone become colored flecks.
static func _recolor_ore(stone: Image, coal: Image, ore: Color) -> Image:
	var ts: int = stone.get_width()
	var out: Image = stone.duplicate()
	for y in range(ts):
		for x in range(ts):
			var s: Color = stone.get_pixel(x, y)
			var c: Color = coal.get_pixel(x, y)
			var diff: float = absf(s.r - c.r) + absf(s.g - c.g) + absf(s.b - c.b)
			if diff > 0.18:
				var k: float = clampf(0.55 + (1.0 - _lum(c)) * 0.7, 0.5, 1.25)
				out.set_pixel(x, y, Color(clampf(ore.r * k, 0.0, 1.0), clampf(ore.g * k, 0.0, 1.0), clampf(ore.b * k, 0.0, 1.0), 1.0))
	return out


## Small sapling sprite: a thin trunk under a round (or layered, for spruce) leafy crown.
static func _sapling(ts: int, leaves: Image, bark: Image, conifer: bool) -> Image:
	var out := Image.create(ts, ts, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var u: float = float(ts) / 16.0
	# Trunk
	for y in range(int(9.0 * u), ts):
		for x in range(int(7.0 * u), int(9.0 * u)):
			out.set_pixel(x, y, bark.get_pixel(x, y).darkened(0.1))
	# Crown
	for y in range(ts):
		for x in range(ts):
			var fx: float = float(x) / u
			var fy: float = float(y) / u
			var inside: bool = false
			if conifer:
				for tier in [[3.0, 2.5], [6.0, 4.0], [9.0, 5.5]]:
					var cy: float = tier[0]
					var half_w: float = tier[1]
					if fy >= cy - 2.5 and fy <= cy + 1.0 and absf(fx - 8.0) <= half_w * (1.0 - (cy + 1.0 - fy) / 4.5):
						inside = true
			else:
				for blob in [[8.0, 5.5, 4.2], [5.0, 8.0, 3.0], [11.0, 8.0, 3.0], [8.0, 9.0, 3.2]]:
					var dx: float = fx - blob[0]
					var dy: float = fy - blob[1]
					if dx * dx + dy * dy <= blob[2] * blob[2]:
						inside = true
			if inside:
				var c: Color = leaves.get_pixel(x, y)
				out.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	return out


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

		10: # Snow (Crisp alpine snow with cool icy sparkles)
			var snow_base := Color(0.93, 0.96, 0.99)
			var sparkle: float = 0.04 if ((x * 3 + y * 5) % 7 == 0) else -0.02
			return _tint(snow_base, jitter * 0.45 + sparkle)

		11: # Glowstone (Warm golden lantern frame + glowing core crystals)
			var border: bool = (x == 0 or x == size - 1 or y == 0 or y == size - 1)
			if border:
				return _tint(Color(0.58, 0.42, 0.16), jitter * 0.5)
			var core: bool = ((x + y) % 3 == 0) or (x >= 5 and x <= 10 and y >= 5 and y <= 10)
			var glow_col: Color = Color(1.0, 0.94, 0.55) if core else Color(0.92, 0.72, 0.24)
			return _tint(glow_col, jitter * 0.5)

		12: # Coal Ore (Stone with dark anthracite coal nuggets)
			if _is_ore_fleck(x, y):
				return _tint(Color(0.12, 0.13, 0.15), jitter * 0.4)
			return _tint(stone_base, jitter)

		13: # Iron Ore (Stone with warm copper-tan metallic veins)
			if _is_ore_fleck(x, y):
				return _tint(Color(0.84, 0.62, 0.46), jitter * 0.5)
			return _tint(stone_base, jitter)

		14: # Gold Ore (Stone with bright golden nuggets)
			if _is_ore_fleck(x, y):
				return _tint(Color(0.98, 0.85, 0.20), jitter * 0.4)
			return _tint(stone_base, jitter)

		15: # Diamond Ore (Stone with glowing cyan diamond crystals)
			if _is_ore_fleck(x, y):
				return _tint(Color(0.28, 0.94, 0.96), jitter * 0.4)
			return _tint(stone_base, jitter)

		16: # Crafting Table Top (3x3 Workbench Grid on Oak)
			var border: bool = (x <= 1 or x >= size - 2 or y <= 1 or y >= size - 2)
			if border:
				return _tint(bark_base, jitter * 0.5)
			var grid_line: bool = (x == 5 or x == 10 or y == 5 or y == 10)
			if grid_line:
				return _tint(Color(0.32, 0.20, 0.10), jitter * 0.3)
			return _tint(plank_base, jitter * 0.5)

		17: # Crafting Table Side (Planks with dark top rim & tool silhouettes)
			if y < 3:
				return _tint(bark_base, jitter * 0.5)
			if (x >= 4 and x <= 6 and y >= 5 and y <= 11) or (x >= 10 and x <= 12 and y >= 6 and y <= 10):
				return _tint(Color(0.36, 0.38, 0.42), jitter * 0.4)
			return _tint(plank_base, jitter * 0.6)

		18: # Furnace / Oven Front (Cobblestone arch with dark firebox & glowing embers)
			var in_upper_opening: bool = (x >= 4 and x <= 11 and y >= 3 and y <= 7)
			var in_lower_hearth: bool = (x >= 4 and x <= 11 and y >= 10 and y <= 13)
			if in_upper_opening:
				return _tint(Color(0.12, 0.12, 0.14), jitter * 0.3)
			if in_lower_hearth:
				var ember: bool = ((x + y) % 2 == 0)
				return _tint(Color(0.98, 0.48, 0.14) if ember else Color(0.22, 0.14, 0.12), jitter * 0.4)
			return _tint(cobble_base, jitter)

		19: # Chest Front (Oak wood with black iron seam & gold lock latch)
			if x >= 7 and x <= 8 and y >= 5 and y <= 8:
				return _tint(Color(0.96, 0.84, 0.22), jitter * 0.3)
			if y == 6 or x == 0 or x == size - 1 or y == 0 or y == size - 1:
				return _tint(Color(0.18, 0.14, 0.10), jitter * 0.3)
			return _tint(Color(0.74, 0.50, 0.22), jitter * 0.5)

		20: # Chest Side / Top (Framed oak chest box)
			if y == 6 or x == 0 or x == size - 1 or y == 0 or y == size - 1:
				return _tint(Color(0.18, 0.14, 0.10), jitter * 0.3)
			return _tint(Color(0.72, 0.48, 0.20), jitter * 0.5)

		21: # Torch (Glowing orange/yellow flame tip over oak handle)
			if y <= 4:
				return _tint(Color(1.0, 0.88, 0.26), jitter * 0.3)
			return _tint(bark_base, jitter * 0.5)

		22: # Bed (White pillow at head + Crimson wool blanket)
			if y <= 4:
				return _tint(Color(0.95, 0.95, 0.96), jitter * 0.3)
			return _tint(Color(0.84, 0.18, 0.20), jitter * 0.4)

		23: # Wooden Door (Oak door frame + window panes + gold doorknob)
			if x >= 11 and x <= 13 and y >= 8 and y <= 9:
				return _tint(Color(0.95, 0.82, 0.24), jitter * 0.2)
			if (x >= 3 and x <= 6 and y >= 3 and y <= 6) or (x >= 9 and x <= 12 and y >= 3 and y <= 6):
				return _tint(Color(0.18, 0.22, 0.28), jitter * 0.2)
			return _tint(plank_base, jitter * 0.5)

		24: # Ladder (Side rails + horizontal climbing rungs)
			var on_rail: bool = (x >= 2 and x <= 3) or (x >= 12 and x <= 13)
			var on_rung: bool = (y % 4 == 1) and (x >= 2 and x <= 13)
			if on_rail or on_rung:
				return _tint(plank_base, jitter * 0.5)
			return _tint(Color(0.24, 0.18, 0.12), jitter * 0.3)

		25: # TNT (Red dynamite sticks + white label band)
			if y >= 6 and y <= 9:
				var dark_txt: bool = ((x % 3 == 1) and (y == 7 or y == 8))
				return _tint(Color(0.12, 0.12, 0.12) if dark_txt else Color(0.94, 0.94, 0.94), jitter * 0.2)
			var stick_line: bool = (x % 4 == 0)
			return _tint(Color(0.68, 0.14, 0.12) if stick_line else Color(0.90, 0.22, 0.18), jitter * 0.4)

		26: # Sandstone (Warm desert sedimentary strata)
			var band: float = -0.05 if (y == 3 or y == 8 or y == 13) else 0.02
			return _tint(Color(0.86, 0.78, 0.52), jitter * 0.5 + band)

		27: # Mossy Cobblestone (Cobble with lush green moss veins)
			var mortar: bool = (y % 4 == 0) or ((x + (y / 4) * 2) % 4 == 0)
			if mortar:
				return _tint(Color(0.22, 0.48, 0.20), jitter * 0.5)
			return _tint(cobble_base, jitter)

		37: # Farmland Moist (Tilled rich dark soil with furrow lines)
			var furrow: float = -0.06 if (y % 4 == 0) else 0.02
			return _tint(Color(0.34, 0.20, 0.10), jitter * 0.4 + furrow)

		38: # Wheat Crops (Mature golden wheat stalks with full grain heads)
			var is_stalk: bool = (x % 3 == 1)
			if y >= 8:
				# Golden wheat grain ears
				var ear_color := Color(0.92, 0.82, 0.24) if is_stalk else Color(0.84, 0.74, 0.20)
				return _tint(ear_color, jitter * 0.3)
			else:
				var stalk_color := Color(0.76, 0.68, 0.22) if is_stalk else Color(0.32, 0.20, 0.10)
				return _tint(stalk_color, jitter * 0.3)

		39: # Potato Crops (Mature green leafy foliage with potato flowers)
			if (x == 7 or x == 8) and (y == 12 or y == 13):
				return _tint(Color(0.96, 0.94, 0.88), jitter * 0.1) # Flower petal
			var is_leaf: bool = (x + y) % 3 != 0
			var leaf_col := Color(0.22, 0.54, 0.18) if is_leaf else Color(0.18, 0.42, 0.14)
			return _tint(leaf_col, jitter * 0.4)

		44: # Wheat Sprout (Young light-green sprouting shoots emerging from soil)
			var is_shoot: bool = (y <= 7) and ((x == 4 or x == 5) or (x == 10 or x == 11) or (y <= 3 and x % 4 == 2))
			if is_shoot:
				return _tint(Color(0.42, 0.84, 0.22), jitter * 0.3)
			return _tint(Color(0.30, 0.18, 0.08), jitter * 0.3)

		45: # Potato Sprout (Small twin leafy green sprouts on soil)
			var is_sprout: bool = (y <= 6) and ((x >= 3 and x <= 6) or (x >= 9 and x <= 12))
			if is_sprout:
				return _tint(Color(0.34, 0.72, 0.20), jitter * 0.3)
			return _tint(Color(0.30, 0.18, 0.08), jitter * 0.3)

		46: # Gravel (Stone pebbles with dark flint specks)
			var is_flint: bool = ((x * 7 + y * 13) % 11 == 0)
			var is_pebble: bool = ((x * 3 + y * 5) % 7 == 0)
			if is_flint:
				return _tint(Color(0.24, 0.22, 0.26), jitter * 0.2)
			elif is_pebble:
				return _tint(Color(0.72, 0.70, 0.66), jitter * 0.3)
			return _tint(Color(0.55, 0.52, 0.50), jitter)

		47: # Clay (Smooth grey-blue silt)
			var band: float = -0.03 if (y % 5 == 0) else 0.02
			return _tint(Color(0.62, 0.65, 0.72), jitter * 0.4 + band)

		48: # Ice (Translucent crystal blue with frost cracks)
			var is_crack: bool = ((x - y) % 7 == 0 or (x + y * 2) % 11 == 0)
			if is_crack:
				return Color(0.92, 0.96, 1.0, 1.0)
			return Color(0.62, 0.82, 0.96, 0.90)

		49: # Dandelion (Yellow flower head with green stalk)
			var center_x: int = size / 2
			var dx_f: int = absi(x - center_x)
			if y >= int(float(size) * 0.55) and dx_f <= 3 and y <= int(float(size) * 0.85):
				return _tint(Color(0.96, 0.88, 0.16), jitter * 0.2)
			if (dx_f == 0 or (dx_f == 1 and y % 3 == 0)) and y >= 2 and y < int(float(size) * 0.60):
				return _tint(Color(0.32, 0.68, 0.22), jitter * 0.2)
			return Color(0, 0, 0, 0)

		50: # Rose (Red blossom with dark green stalk and leaf)
			var center_x_r: int = size / 2
			var dx_r: int = absi(x - center_x_r)
			if y >= int(float(size) * 0.50) and dx_r <= 3 and y <= int(float(size) * 0.85):
				var petal_dark: bool = (dx_r == 3 or y == int(float(size) * 0.85))
				return _tint(Color(0.68, 0.10, 0.14) if petal_dark else Color(0.88, 0.16, 0.20), jitter * 0.2)
			if (dx_r == 0 or (dx_r == 1 and (y == 4 or y == 5))) and y >= 2 and y < int(float(size) * 0.55):
				return _tint(Color(0.24, 0.52, 0.18), jitter * 0.2)
			return Color(0, 0, 0, 0)

		51: # Brown Mushroom (Dark brown cap with pale stalk)
			var center_m: int = size / 2
			var dx_m: int = absi(x - center_m)
			if y >= int(float(size) * 0.45) and dx_m <= 4 and y <= int(float(size) * 0.70):
				return _tint(Color(0.54, 0.40, 0.28), jitter * 0.2)
			if dx_m <= 1 and y >= 2 and y < int(float(size) * 0.50):
				return _tint(Color(0.86, 0.82, 0.74), jitter * 0.1)
			return Color(0, 0, 0, 0)

		52: # Red Mushroom (Red spotted dome cap with pale stalk)
			var center_rm: int = size / 2
			var dx_rm: int = absi(x - center_rm)
			if y >= int(float(size) * 0.45) and dx_rm <= 4 and y <= int(float(size) * 0.75):
				var is_spot: bool = (dx_rm == 2 and (y == int(float(size) * 0.55) or y == int(float(size) * 0.68))) or (dx_rm == 0 and y == int(float(size) * 0.62))
				if is_spot:
					return Color(0.96, 0.96, 0.96, 1.0)
				return _tint(Color(0.88, 0.18, 0.20), jitter * 0.2)
			if dx_rm <= 1 and y >= 2 and y < int(float(size) * 0.50):
				return _tint(Color(0.86, 0.82, 0.74), jitter * 0.1)
			return Color(0, 0, 0, 0)

		53: # Pine Log Side (Dark reddish-brown coarse vertical bark)
			var pine_ridge: float = -0.07 if (x % 3 == 0) else 0.02
			return _tint(Color(0.28, 0.18, 0.10), jitter * 0.6 + pine_ridge)

		54: # Pine Leaves (Dark evergreen conifer needles)
			var pine_dapple: float = -0.06 if (rng.randf() < 0.32) else 0.03
			return _tint(Color(0.18, 0.36, 0.20), jitter * 0.5 + pine_dapple)

		55: # Birch Log Side (White bark with dark horizontal lenticels)
			var is_lenticel: bool = (y % 4 == 0) and ((x >= 2 and x <= 5) or (x >= 9 and x <= 13))
			if is_lenticel:
				return _tint(Color(0.20, 0.20, 0.20), jitter * 0.2)
			return _tint(Color(0.90, 0.90, 0.86), jitter * 0.3)

		56: # Birch Leaves (Bright vibrant yellow-green deciduous leaves)
			var birch_dapple: float = -0.05 if (rng.randf() < 0.28) else 0.04
			return _tint(Color(0.42, 0.68, 0.28), jitter * 0.5 + birch_dapple)

		57: # Monster Spawner (Dark charred iron cage grill)
			var is_bar: bool = (x == 0 or x == size - 1 or y == 0 or y == size - 1 or x % 4 == 0 or y % 4 == 0)
			if is_bar:
				return _tint(Color(0.22, 0.24, 0.28), jitter * 0.3)
			return Color(0.08, 0.12, 0.16, 0.85)

		58: # Bedrock (High-contrast indestructible black/grey mottled stone)
			var b_pattern: float = sin(float(x * 5) * 0.8) * cos(float(y * 7) * 0.6)
			var b_shade: float = 0.15 if b_pattern > 0.2 else (-0.12 if b_pattern < -0.2 else 0.0)
			return _tint(Color(0.18, 0.18, 0.18), jitter * 0.5 + b_shade)

		59: # Redstone Ore (Stone with glowing ruby-red flecks)
			if _is_ore_fleck(x, y):
				return _tint(Color(0.92, 0.18, 0.18), jitter * 0.2)
			return _tint(stone_base, jitter)

		60: # Lapis Ore (Stone with royal cobalt-blue flecks)
			if _is_ore_fleck(x, y):
				return _tint(Color(0.16, 0.32, 0.84), jitter * 0.2)
			return _tint(stone_base, jitter)

		_:
			return _tint(stone_base, jitter)


static func _is_ore_fleck(x: int, y: int) -> bool:
	return (
		(x >= 3 and x <= 5 and y >= 3 and y <= 4)
		or (x >= 10 and x <= 12 and y >= 4 and y <= 6)
		or (x >= 4 and x <= 6 and y >= 10 and y <= 12)
		or (x >= 9 and x <= 11 and y >= 11 and y <= 13)
		or (x >= 7 and x <= 8 and y >= 7 and y <= 8)
	)


static func _tint(base: Color, delta: float) -> Color:
	return Color(
		clampf(base.r + delta, 0.0, 1.0),
		clampf(base.g + delta, 0.0, 1.0),
		clampf(base.b + delta, 0.0, 1.0),
		1.0
	)
