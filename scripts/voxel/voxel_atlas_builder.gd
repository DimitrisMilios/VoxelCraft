class_name VoxelAtlasBuilder
extends RefCounted
## Generates a crisp 16x16 per-tile retro pixel-art texture atlas and shared chunk material.

static var _cached_material: StandardMaterial3D = null
static var _cached_water_material: Material = null
static var _cached_texture: ImageTexture = null
static var _cached_normal_texture: ImageTexture = null
static var _cached_roughness_texture: ImageTexture = null


static func get_shared_voxel_material() -> StandardMaterial3D:
	if _cached_material != null:
		return _cached_material

	var material := StandardMaterial3D.new()
	material.albedo_texture = get_atlas_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	material.cull_mode = BaseMaterial3D.CULL_BACK

	# PBR Roughness map for tuned matte/gloss physical response
	var rough_tex: ImageTexture = get_atlas_roughness_texture()
	if rough_tex != null:
		material.roughness = 1.0
		material.roughness_texture = rough_tex
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	else:
		material.roughness = 0.85
	material.metallic = 0.0

	# PBR Normal texture for micro-surface bumps and stone cracks under dynamic lighting
	var norm_tex: ImageTexture = get_atlas_normal_texture()
	if norm_tex != null:
		material.normal_enabled = true
		material.normal_scale = 0.25
		material.normal_texture = norm_tex

	_cached_material = material
	return _cached_material


static func get_shared_water_material() -> Material:
	if _cached_water_material != null:
		return _cached_water_material

	var shader: Shader = load("res://shaders/water.gdshader") as Shader
	if shader != null:
		var s_mat := ShaderMaterial.new()
		s_mat.shader = shader

		# Set realistic shallow and deep colors (matching reference image RTX / SEUS PTGI lake water)
		s_mat.set_shader_parameter("shallow_color", Color(0.24, 0.74, 0.82, 0.40))
		s_mat.set_shader_parameter("deep_color", Color(0.04, 0.30, 0.56, 0.90))
		s_mat.set_shader_parameter("depth_distance", 5.5)
		s_mat.set_shader_parameter("beer_factor", 1.25)
		s_mat.set_shader_parameter("roughness", 0.04)
		s_mat.set_shader_parameter("metallic", 0.05)
		s_mat.set_shader_parameter("specular", 0.95)
		s_mat.set_shader_parameter("refraction_strength", 0.02)
		s_mat.set_shader_parameter("normal_strength", 0.85)

		var wave1_img: Image = TexturePack.load_image("res://assets/textures/water_wave_normal_1.png")
		if wave1_img != null:
			s_mat.set_shader_parameter("wave_normal_1", ImageTexture.create_from_image(wave1_img))
		var wave2_img: Image = TexturePack.load_image("res://assets/textures/water_wave_normal_2.png")
		if wave2_img != null:
			s_mat.set_shader_parameter("wave_normal_2", ImageTexture.create_from_image(wave2_img))

		_cached_water_material = s_mat
		return _cached_water_material

	var water_tex: ImageTexture = null
	var water_uv_scale: float = 0.32
	var loaded_water: Image = TexturePack.load_image("res://assets/textures/water_still_64.png")
	if loaded_water != null:
		water_tex = ImageTexture.create_from_image(loaded_water)
		water_uv_scale = 1.0

	if water_tex == null:
		var water_img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in range(16):
			for x in range(16):
				var wave: float = sin((float(x) * 0.9 + float(y) * 1.4) * 0.78) * 0.055
				var streak: float = 0.08 if ((x + y * 2) % 6 == 0) else 0.0
				var trough: float = -0.05 if ((x * 2 + y) % 5 == 0) else 0.0
				var col := Color(
					clampf(0.14 + wave + streak + trough, 0.0, 1.0),
					clampf(0.47 + wave + streak + trough, 0.0, 1.0),
					clampf(0.88 + wave + streak * 1.1, 0.0, 1.0),
					0.74
				)
				water_img.set_pixel(x, y, col)
		water_tex = ImageTexture.create_from_image(water_img)

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = water_tex
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.uv1_scale = Vector3(water_uv_scale, water_uv_scale, water_uv_scale)
	material.uv1_triplanar = true
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.07
	material.metallic = 0.14
	material.metallic_specular = 0.88
	_cached_water_material = material
	return _cached_water_material


## Scrolls water UV coordinates continuously so rivers, corners, and waterfalls visibly animate.
static func update_water_animation(delta: float) -> void:
	if _cached_water_material == null:
		return
	if _cached_water_material is StandardMaterial3D:
		var std_mat := _cached_water_material as StandardMaterial3D
		var offset: Vector3 = std_mat.uv1_offset
		offset.x = fmod(offset.x + delta * 0.18, 1.0)
		offset.y = fmod(offset.y - delta * 0.42, 1.0)
		offset.z = fmod(offset.z + delta * 0.22, 1.0)
		std_mat.uv1_offset = offset


static func get_atlas_texture() -> ImageTexture:
	if _cached_texture != null:
		return _cached_texture

	# 1. Load the block atlas: a local texture pack override (e.g. Faithful 64x, 36 tiles)
	#    if installed, otherwise the repo's Blender-baked atlas (29 tiles).
	var baked_img: Image = TexturePack.load_image("res://assets/textures/block_atlas.png")
	if baked_img != null:
		BlockRegistry.atlas_columns = maxi(1, baked_img.get_width() / maxi(1, baked_img.get_height()))
		_cached_texture = ImageTexture.create_from_image(baked_img)
		return _cached_texture

	# 2. Fallback procedural pixel-art atlas if `block_atlas.png` is missing
	BlockRegistry.atlas_columns = BlockRegistry.ATLAS_COLUMNS
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


static func get_atlas_normal_texture() -> ImageTexture:
	if _cached_normal_texture != null:
		return _cached_normal_texture
	var norm_img: Image = TexturePack.load_image("res://assets/textures/block_atlas_normal.png")
	if norm_img != null and not norm_img.is_empty():
		_cached_normal_texture = ImageTexture.create_from_image(norm_img)
	return _cached_normal_texture


static func get_atlas_roughness_texture() -> ImageTexture:
	if _cached_roughness_texture != null:
		return _cached_roughness_texture
	var rough_img: Image = TexturePack.load_image("res://assets/textures/block_atlas_roughness.png")
	if rough_img != null and not rough_img.is_empty():
		_cached_roughness_texture = ImageTexture.create_from_image(rough_img)
	return _cached_roughness_texture


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
