extends SceneTree
## Builds VoxelCraft's 64x64 HD Block Texture Atlas, Water Texture, 10-Stage Mining Crack Overlays,
## HUD Vitals/Crosshair/Armor Icons, GUI Containers/Slots, and 2D Item/Tool Icons directly from
## `c:\Users\dimit\Desktop\Faithful 64x - Release 15`.

const FAITHFUL_ROOT: String = "c:/Users/dimit/Desktop/Faithful 64x - Release 15/assets/minecraft/textures"
const TILE_SIZE: int = 64
const ATLAS_COLS: int = 36


func _initialize() -> void:
	print("[Faithful64xBuilder] Starting Faithful 64x asset integration...")
	_ensure_dirs()
	_build_block_atlas()
	_build_water_texture()
	_copy_destroy_stages()
	_build_hud_and_gui_assets()
	_copy_2d_item_icons()
	_copy_entity_and_environment_textures()
	_write_license_and_credits()
	print("[Faithful64xBuilder] Completed Faithful 64x asset generation successfully!")
	quit(0)


## Ships an unmodified copy of the Faithful License + attribution with the generated pack
## (required by the Faithful License, Requirement 5).
func _write_license_and_credits() -> void:
	var pack_dir: String = ProjectSettings.globalize_path("res://assets/packs/faithful_64x/")
	var license_src: String = "c:/Users/dimit/Desktop/Faithful 64x - Release 15/LICENSE.txt"
	if FileAccess.file_exists(license_src):
		DirAccess.copy_absolute(license_src, pack_dir + "LICENSE.txt")
	var info := FileAccess.open(pack_dir + "pack_info.txt", FileAccess.WRITE)
	if info != null:
		info.store_string(
			"Faithful 64x - Release 15\n"
			+ "Textures by the Faithful Resource Pack team - https://faithfulpack.net\n"
			+ "License: see LICENSE.txt in this folder or https://faithfulpack.net/license\n"
			+ "Used in VoxelCraft for blocks, water, mining cracks, HUD, GUI, mobs, player skin, tools, items, and environment.\n"
		)
		info.close()


func _ensure_dirs() -> void:
	var dirs: Array[String] = [
		"res://assets/packs/faithful_64x/textures",
		"res://assets/packs/faithful_64x/textures/destroy_stages",
		"res://assets/packs/faithful_64x/textures/entity",
		"res://assets/packs/faithful_64x/textures/environment",
		"res://assets/packs/faithful_64x/ui/hud_icons",
		"res://assets/packs/faithful_64x/ui/gui_panels",
		"res://assets/packs/faithful_64x/ui/item_icons",
	]
	for d in dirs:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))


func _load_faithful_image(rel_path: String) -> Image:
	var full_path: String = FAITHFUL_ROOT + "/" + rel_path
	if not FileAccess.file_exists(full_path):
		push_warning("[Faithful64xBuilder] Missing texture: " + full_path)
		var fallback := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		fallback.fill(Color(1.0, 0.0, 1.0, 1.0))
		return fallback
	var img := Image.load_from_file(full_path)
	if img == null or img.is_empty():
		var fallback := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		fallback.fill(Color(1.0, 0.0, 1.0, 1.0))
		return fallback
	img.convert(Image.FORMAT_RGBA8)
	return img


func _load_tile_64(rel_path: String) -> Image:
	var img: Image = _load_faithful_image(rel_path)
	if img.get_width() != TILE_SIZE or img.get_height() != TILE_SIZE:
		# If animated strip (height > width), crop first 64x64 frame
		if img.get_width() == TILE_SIZE and img.get_height() > TILE_SIZE:
			var frame := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
			frame.blit_rect(img, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i.ZERO)
			return frame
		img.resize(TILE_SIZE, TILE_SIZE, Image.INTERPOLATE_NEAREST)
	return img


func _tint_image(src: Image, tint: Color, bg_fill: Color = Color(0, 0, 0, 0)) -> Image:
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(src.get_height()):
		for x in range(src.get_width()):
			var c: Color = src.get_pixel(x, y)
			if c.a < 0.05 and bg_fill.a > 0.0:
				out.set_pixel(x, y, bg_fill)
			else:
				out.set_pixel(x, y, Color(
					clampf(c.r * tint.r * 1.12, 0.0, 1.0),
					clampf(c.g * tint.g * 1.12, 0.0, 1.0),
					clampf(c.b * tint.b * 1.12, 0.0, 1.0),
					c.a * tint.a
				))
	return out


func _alpha_composite(base: Image, overlay: Image) -> Image:
	var out := Image.create(base.get_width(), base.get_height(), false, Image.FORMAT_RGBA8)
	out.blit_rect(base, Rect2i(0, 0, base.get_width(), base.get_height()), Vector2i.ZERO)
	var w: int = mini(base.get_width(), overlay.get_width())
	var h: int = mini(base.get_height(), overlay.get_height())
	for y in range(h):
		for x in range(w):
			var bg: Color = out.get_pixel(x, y)
			var fg: Color = overlay.get_pixel(x, y)
			if fg.a <= 0.001:
				continue
			var a: float = fg.a + bg.a * (1.0 - fg.a)
			if a <= 0.001:
				continue
			var r: float = (fg.r * fg.a + bg.r * bg.a * (1.0 - fg.a)) / a
			var g: float = (fg.g * fg.a + bg.g * bg.a * (1.0 - fg.a)) / a
			var b: float = (fg.b * fg.a + bg.b * bg.a * (1.0 - fg.a)) / a
			out.set_pixel(x, y, Color(r, g, b, a))
	return out


func _force_opaque(src: Image, backdrop: Color) -> Image:
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(src.get_height()):
		for x in range(src.get_width()):
			var c: Color = src.get_pixel(x, y)
			if c.a < 0.99:
				var r: float = lerpf(backdrop.r, c.r, c.a)
				var g: float = lerpf(backdrop.g, c.g, c.a)
				var b: float = lerpf(backdrop.b, c.b, c.a)
				out.set_pixel(x, y, Color(r, g, b, 1.0))
			else:
				out.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	return out


func _build_chest_tile(is_front: bool) -> Image:
	var chest_entity: Image = _load_faithful_image("entity/chest/normal.png")
	var tile := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	# In 256x256 (4x of 64x64) chest entity sheet:
	# Lid front/side is at y=56..76 (height 20), Base front/side is at y=132..172 (height 40)
	if chest_entity.get_width() >= 256 and chest_entity.get_height() >= 256:
		var lid_x: int = 56 if is_front else 0
		var base_x: int = 56 if is_front else 0
		# Copy 56x20 lid and resize to 64x22
		var lid := Image.create(56, 20, false, Image.FORMAT_RGBA8)
		lid.blit_rect(chest_entity, Rect2i(lid_x, 56, 56, 20), Vector2i.ZERO)
		lid.resize(64, 22, Image.INTERPOLATE_NEAREST)
		# Copy 56x40 body and resize to 64x42
		var body := Image.create(56, 40, false, Image.FORMAT_RGBA8)
		body.blit_rect(chest_entity, Rect2i(base_x, 132, 56, 40), Vector2i.ZERO)
		body.resize(64, 42, Image.INTERPOLATE_NEAREST)

		tile.blit_rect(lid, Rect2i(0, 0, 64, 22), Vector2i(0, 0))
		tile.blit_rect(body, Rect2i(0, 0, 64, 42), Vector2i(0, 22))

		if is_front:
			# Draw Faithful silver/gold lock latch at center seam (x=28..35, y=16..29)
			for y in range(16, 30):
				for x in range(28, 36):
					var is_border: bool = (x == 28 or x == 35 or y == 16 or y == 29)
					var col := Color(0.55, 0.58, 0.62, 1.0) if is_border else Color(0.88, 0.90, 0.94, 1.0)
					tile.set_pixel(x, y, col)
		return _force_opaque(tile, Color(0.45, 0.30, 0.14, 1.0))

	# Fallback using oak planks
	return _load_tile_64("block/oak_planks.png")


func _build_torch_tile() -> Image:
	var torch_src: Image = _load_tile_64("block/torch.png")
	var planks_bg: Image = _load_tile_64("block/oak_planks.png")
	var out := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	# Sample the center 8x40 torch column of `torch.png` and stretch across the 64x64 tile
	# so the 3D Torch post mesh shows the authentic Faithful 64x wood stick + glowing flame tip
	for y in range(TILE_SIZE):
		var src_y: int = clampi(24 + int(float(y) * 40.0 / 64.0), 24, 63)
		for x in range(TILE_SIZE):
			var src_x: int = clampi(28 + int(float(x) * 8.0 / 64.0), 28, 35)
			var c: Color = torch_src.get_pixel(src_x, src_y)
			if c.a > 0.1:
				out.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
			else:
				var bg: Color = planks_bg.get_pixel(x, y)
				out.set_pixel(x, y, Color(bg.r * 0.65, bg.g * 0.55, bg.b * 0.45, 1.0))
	return out


func _build_bed_tile() -> Image:
	var white_wool: Image = _load_tile_64("block/white_wool.png")
	var red_wool: Image = _load_tile_64("block/red_wool.png")
	var planks: Image = _load_tile_64("block/oak_planks.png")
	var out := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if y >= 54:
				out.set_pixel(x, y, planks.get_pixel(x, y))
			elif y < 18:
				out.set_pixel(x, y, white_wool.get_pixel(x, y))
			else:
				out.set_pixel(x, y, red_wool.get_pixel(x, y))
	return out


func _build_door_tile() -> Image:
	var top_img: Image = _load_tile_64("block/oak_door_top.png")
	var bot_img: Image = _load_tile_64("block/oak_door_bottom.png")
	top_img.resize(64, 32, Image.INTERPOLATE_NEAREST)
	bot_img.resize(64, 32, Image.INTERPOLATE_NEAREST)
	var out := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	out.blit_rect(top_img, Rect2i(0, 0, 64, 32), Vector2i(0, 0))
	out.blit_rect(bot_img, Rect2i(0, 0, 64, 32), Vector2i(0, 32))
	return _force_opaque(out, Color(0.14, 0.18, 0.24, 1.0))


func _build_block_atlas() -> void:
	var grass_tint := Color(0.475, 0.753, 0.353, 1.0)   # Authentic Minecraft Plains/Forest Grass tint (#79C05A)
	var foliage_tint := Color(0.349, 0.682, 0.188, 1.0) # Authentic Minecraft Oak Foliage tint (#59AE30)

	var grass_top: Image = _tint_image(_load_tile_64("block/grass_block_top.png"), grass_tint)
	var grass_side_base: Image = _load_tile_64("block/grass_block_side.png")
	var grass_side_over: Image = _tint_image(_load_tile_64("block/grass_block_side_overlay.png"), grass_tint)
	var grass_side: Image = _alpha_composite(grass_side_base, grass_side_over)

	var leaves_raw: Image = _load_tile_64("block/oak_leaves.png")
	var leaves_tinted: Image = _tint_image(leaves_raw, foliage_tint, Color(0.11, 0.24, 0.07, 1.0))
	var leaves_opaque: Image = _force_opaque(leaves_tinted, Color(0.11, 0.24, 0.07, 1.0))

	var ladder_raw: Image = _load_tile_64("block/ladder.png")
	var planks_dark: Image = _tint_image(_load_tile_64("block/oak_planks.png"), Color(0.42, 0.38, 0.34, 1.0))
	var ladder_tile: Image = _alpha_composite(planks_dark, ladder_raw)

	var tiles: Array[Image] = [
		grass_top,                                           # 0: Grass Top
		grass_side,                                          # 1: Grass Side
		_load_tile_64("block/dirt.png"),                     # 2: Dirt
		_load_tile_64("block/stone.png"),                    # 3: Stone
		_load_tile_64("block/oak_log.png"),                  # 4: Wood Log Side
		_load_tile_64("block/oak_log_top.png"),              # 5: Wood Log Top
		leaves_opaque,                                       # 6: Oak Leaves
		_load_tile_64("block/sand.png"),                     # 7: Sand
		_load_tile_64("block/cobblestone.png"),              # 8: Cobblestone
		_load_tile_64("block/oak_planks.png"),               # 9: Oak Planks
		_load_tile_64("block/snow.png"),                     # 10: Snow
		_load_tile_64("block/glowstone.png"),                # 11: Glowstone
		_load_tile_64("block/coal_ore.png"),                 # 12: Coal Ore
		_load_tile_64("block/iron_ore.png"),                 # 13: Iron Ore
		_load_tile_64("block/gold_ore.png"),                 # 14: Gold Ore
		_load_tile_64("block/diamond_ore.png"),              # 15: Diamond Ore
		_load_tile_64("block/crafting_table_top.png"),       # 16: Crafting Table Top
		_load_tile_64("block/crafting_table_front.png"),     # 17: Crafting Table Front
		_load_tile_64("block/furnace_front_on.png"),         # 18: Furnace Front
		_build_chest_tile(true),                             # 19: Chest Front
		_build_chest_tile(false),                            # 20: Chest Side/Top
		_build_torch_tile(),                                 # 21: Torch
		_build_bed_tile(),                                   # 22: Bed
		_build_door_tile(),                                  # 23: Wooden Door
		ladder_tile,                                         # 24: Ladder
		_load_tile_64("block/tnt_side.png"),                 # 25: TNT Side
		_load_tile_64("block/sandstone.png"),                # 26: Sandstone Side
		_load_tile_64("block/mossy_cobblestone.png"),        # 27: Mossy Cobblestone
		_force_opaque(_load_tile_64("block/cactus_side.png"), Color(0.08, 0.28, 0.09, 1.0)), # 28: Cactus Side
		_load_tile_64("block/crafting_table_side.png"),      # 29: Crafting Table Side
		_load_tile_64("block/furnace_side.png"),             # 30: Furnace Side
		_load_tile_64("block/furnace_top.png"),              # 31: Furnace Top
		_load_tile_64("block/tnt_top.png"),                  # 32: TNT Top
		_load_tile_64("block/tnt_bottom.png"),               # 33: TNT Bottom
		_load_tile_64("block/sandstone_top.png"),            # 34: Sandstone Top
		_force_opaque(_load_tile_64("block/cactus_top.png"), Color(0.08, 0.28, 0.09, 1.0)),  # 35: Cactus Top
		_load_tile_64("block/white_wool.png"),               # 36: White Wool
		_load_tile_64("block/farmland_moist.png"),           # 37: Farmland Moist
		_load_tile_64("block/wheat_stage7.png"),             # 38: Wheat Crops
		_load_tile_64("block/potatoes_stage3.png"),          # 39: Potato Crops
		_load_tile_64("block/lava_still.png"),               # 40: Lava
		_load_tile_64("block/obsidian.png"),                 # 41: Obsidian
	]

	var atlas := Image.create(tiles.size() * TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for idx in range(tiles.size()):
		atlas.blit_rect(tiles[idx], Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(idx * TILE_SIZE, 0))

	var out_path: String = ProjectSettings.globalize_path("res://assets/packs/faithful_64x/textures/block_atlas.png")
	var fallback_path: String = ProjectSettings.globalize_path("res://assets/textures/block_atlas.png")
	atlas.save_png(out_path)
	atlas.save_png(fallback_path)
	print("[Faithful64xBuilder] Saved %d-tile 64x64 Block Atlas (%dx64) -> %s" % [tiles.size(), tiles.size() * TILE_SIZE, out_path])

	_build_normal_atlas(tiles)
	_build_roughness_atlas(tiles)
	_build_isometric_block_icons(tiles)


func _generate_normal_tile(src: Image, bump_strength: float) -> Image:
	var w: int = src.get_width()
	var h: int = src.get_height()
	var norm_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	for y in range(h):
		for x in range(w):
			var c: Color = src.get_pixel(x, y)
			lum[y * w + x] = c.r * 0.299 + c.g * 0.587 + c.b * 0.114

	for y in range(h):
		var y_prev: int = (y - 1 + h) % h
		var y_next: int = (y + 1) % h
		for x in range(w):
			var x_prev: int = (x - 1 + w) % w
			var x_next: int = (x + 1) % w

			var tl: float = lum[y_prev * w + x_prev]
			var l: float = lum[y * w + x_prev]
			var bl: float = lum[y_next * w + x_prev]
			var tr: float = lum[y_prev * w + x_next]
			var r: float = lum[y * w + x_next]
			var br: float = lum[y_next * w + x_next]
			var dx: float = ((tr + 2.0 * r + br) - (tl + 2.0 * l + bl)) * bump_strength

			var t: float = lum[y_prev * w + x]
			var b: float = lum[y_next * w + x]
			var dy: float = ((bl + 2.0 * b + br) - (tl + 2.0 * t + tr)) * bump_strength

			var n := Vector3(-dx, -dy, 1.0).normalized()
			var col := Color(
				n.x * 0.5 + 0.5,
				n.y * 0.5 + 0.5,
				n.z * 0.5 + 0.5,
				1.0
			)
			norm_img.set_pixel(x, y, col)
	return norm_img


func _build_normal_atlas(tiles: Array[Image]) -> void:
	var num_tiles: int = tiles.size()
	var normal_atlas := Image.create(num_tiles * TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for idx in range(num_tiles):
		var tile: Image = tiles[idx]
		var strength: float = 2.4
		match idx:
			3, 8, 27: # Stone, Cobblestone, Mossy Cobble (deep cracks & stone bumps)
				strength = 3.4
			12, 13, 14, 15: # Ores (pronounced facets and mineral crevices)
				strength = 3.6
			4, 5, 9, 16, 17: # Wood bark, planks, workbench
				strength = 2.6
			26: # Sandstone
				strength = 2.8
			41: # Obsidian (volcanic glass fracture ridges)
				strength = 3.2
			0, 1, 2, 37: # Grass, Dirt, Farmland
				strength = 2.0
			6: # Leaves
				strength = 1.8
			10: # Snow
				strength = 1.2
			40: # Lava
				strength = 1.4

		var norm_tile := _generate_normal_tile(tile, strength)
		normal_atlas.blit_rect(norm_tile, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(idx * TILE_SIZE, 0))

	var p1: String = ProjectSettings.globalize_path("res://assets/packs/faithful_64x/textures/block_atlas_normal.png")
	var p2: String = ProjectSettings.globalize_path("res://assets/textures/block_atlas_normal.png")
	normal_atlas.save_png(p1)
	normal_atlas.save_png(p2)
	print("[Faithful64xBuilder] Saved PBR Normal Map Atlas (stone cracks, micro-surface depth) -> ", p1)


func _generate_roughness_tile(src: Image, base_roughness: float, variation: float) -> Image:
	var w: int = src.get_width()
	var h: int = src.get_height()
	var rough_img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var c: Color = src.get_pixel(x, y)
			var lum: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			var r: float = clampf(base_roughness - (lum - 0.5) * variation, 0.05, 1.0)
			rough_img.set_pixel(x, y, Color(r, r, r, 1.0))
	return rough_img


func _build_roughness_atlas(tiles: Array[Image]) -> void:
	var num_tiles: int = tiles.size()
	var rough_atlas := Image.create(num_tiles * TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for idx in range(num_tiles):
		var tile: Image = tiles[idx]
		var base_rough: float = 0.84
		var variation: float = 0.12
		match idx:
			0, 1: # Grass
				base_rough = 0.92
				variation = 0.06
			2, 37: # Dirt, Farmland
				base_rough = 0.95
				variation = 0.05
			3, 8, 27: # Stone, Cobblestone, Mossy Cobble
				base_rough = 0.82
				variation = 0.15
			4, 5, 9, 16, 17: # Wood log, planks, workbench
				base_rough = 0.76
				variation = 0.10
			6: # Leaves
				base_rough = 0.68
				variation = 0.16
			7, 26: # Sand, Sandstone
				base_rough = 0.94
				variation = 0.06
			10: # Snow
				base_rough = 0.45
				variation = 0.12
			11: # Glowstone
				base_rough = 0.28
				variation = 0.15
			12: # Coal Ore
				base_rough = 0.76
				variation = 0.35
			13: # Iron Ore
				base_rough = 0.70
				variation = 0.40
			14: # Gold Ore
				base_rough = 0.62
				variation = 0.50
			15: # Diamond Ore
				base_rough = 0.55
				variation = 0.55
			36: # White Wool
				base_rough = 0.98
				variation = 0.02
			40: # Lava
				base_rough = 0.18
				variation = 0.08
			41: # Obsidian (glassy polish, high specular glint)
				base_rough = 0.12
				variation = 0.08

		var rough_tile := _generate_roughness_tile(tile, base_rough, variation)
		rough_atlas.blit_rect(rough_tile, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(idx * TILE_SIZE, 0))

	var p1: String = ProjectSettings.globalize_path("res://assets/packs/faithful_64x/textures/block_atlas_roughness.png")
	var p2: String = ProjectSettings.globalize_path("res://assets/textures/block_atlas_roughness.png")
	rough_atlas.save_png(p1)
	rough_atlas.save_png(p2)
	print("[Faithful64xBuilder] Saved PBR Roughness Map Atlas (tuned matte/gloss levels) -> ", p1)


func _render_iso_cube_icon(top_img: Image, left_img: Image, right_img: Image, height_scale: float = 1.0) -> Image:
	var sz: int = 64
	var icon := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	icon.fill(Color(0, 0, 0, 0))

	# Isometric projection centered at (32, 32)
	# Half-width of cube = 24 px, vertical diamond half-height = 12 px, vertical side height = 25 * height_scale
	var cx: float = 32.0
	var side_h: float = 25.0 * height_scale
	var top_cy: float = 20.0 + (25.0 - side_h) * 0.5
	var hw: float = 24.0
	var hh: float = 12.0

	for py in range(sz):
		for px in range(sz):
			var dx: float = (float(px) + 0.5) - cx
			var dy: float = (float(py) + 0.5) - top_cy

			# 1. Check Top Diamond Face:
			# u = (dx / hw + dy / hh) * 0.5, v = (dy / hh - dx / hw) * 0.5
			var u_top: float = (dx / hw + dy / hh) * 0.5
			var v_top: float = (dy / hh - dx / hw) * 0.5
			if u_top >= 0.0 and u_top < 1.0 and v_top >= 0.0 and v_top < 1.0:
				var tx: int = clampi(int(u_top * float(TILE_SIZE)), 0, TILE_SIZE - 1)
				var ty: int = clampi(int(v_top * float(TILE_SIZE)), 0, TILE_SIZE - 1)
				var c: Color = top_img.get_pixel(tx, ty)
				icon.set_pixel(px, py, Color(
					clampf(c.r * 1.04, 0.0, 1.0),
					clampf(c.g * 1.04, 0.0, 1.0),
					clampf(c.b * 1.04, 0.0, 1.0),
					c.a
				))
				continue

			# 2. Check Left Face (dx in [-hw, 0)):
			if dx >= -hw and dx < 0.0:
				var u_left: float = (dx + hw) / hw
				var top_edge_y: float = u_left * hh
				var v_left: float = (dy - top_edge_y) / side_h
				if v_left >= 0.0 and v_left < 1.0:
					var tx: int = clampi(int(u_left * float(TILE_SIZE)), 0, TILE_SIZE - 1)
					var ty: int = clampi(int(v_left * float(TILE_SIZE)), 0, TILE_SIZE - 1)
					var c: Color = left_img.get_pixel(tx, ty)
					icon.set_pixel(px, py, Color(c.r * 0.82, c.g * 0.82, c.b * 0.82, c.a))
					continue

			# 3. Check Right Face (dx in [0, hw]):
			if dx >= 0.0 and dx <= hw:
				var u_right: float = dx / hw
				var top_edge_y: float = (1.0 - u_right) * hh
				var v_right: float = (dy - top_edge_y) / side_h
				if v_right >= 0.0 and v_right < 1.0:
					var tx: int = clampi(int(u_right * float(TILE_SIZE)), 0, TILE_SIZE - 1)
					var ty: int = clampi(int(v_right * float(TILE_SIZE)), 0, TILE_SIZE - 1)
					var c: Color = right_img.get_pixel(tx, ty)
					icon.set_pixel(px, py, Color(c.r * 0.64, c.g * 0.64, c.b * 0.64, c.a))
					continue

	return icon


func _build_isometric_block_icons(tiles: Array[Image]) -> void:
	var icon_dir: String = ProjectSettings.globalize_path("res://assets/packs/faithful_64x/ui/item_icons/")
	var water_raw: Image = _load_tile_64("block/water_still.png")
	var water_tile: Image = _tint_image(water_raw, Color(0.24, 0.52, 0.96, 0.90))

	# Map of Block ID -> [top_tile_idx, left_tile_idx, right_tile_idx, height_scale]
	var block_icon_specs: Dictionary = {
		1: [0, 1, 1, 1.0],     # Grass Block
		2: [2, 2, 2, 1.0],     # Dirt
		3: [3, 3, 3, 1.0],     # Stone
		4: [5, 4, 4, 1.0],     # Wood Log
		5: [6, 6, 6, 1.0],     # Oak Leaves
		6: [7, 7, 7, 1.0],     # Sand
		7: [8, 8, 8, 1.0],     # Cobblestone
		8: [9, 9, 9, 1.0],     # Wood Planks
		10: [10, 10, 10, 1.0], # Snow
		11: [11, 11, 11, 1.0], # Glowstone
		12: [12, 12, 12, 1.0], # Coal Ore
		13: [13, 13, 13, 1.0], # Iron Ore
		14: [14, 14, 14, 1.0], # Gold Ore
		15: [15, 15, 15, 1.0], # Diamond Ore
		16: [16, 17, 29, 1.0], # Crafting Table (Top, Front, Side)
		17: [31, 18, 30, 1.0], # Furnace (Top, Lit Front, Side)
		18: [20, 19, 20, 1.0], # Chest (Top/Side, Front with Latch, Side)
		20: [22, 22, 22, 0.55],# Bed (Half-height bed block)
		24: [32, 25, 25, 1.0], # TNT (Top, Side, Side)
		25: [34, 26, 26, 1.0], # Sandstone (Top, Side, Side)
		26: [35, 28, 28, 1.0], # Cactus (Top, Side, Side)
		27: [27, 27, 27, 1.0], # Mossy Cobblestone
		28: [36, 36, 36, 1.0], # White Wool Block
		29: [37, 2, 2, 0.94],  # Farmland Block
		30: [38, 38, 38, 1.0], # Wheat Crop Block
		40: [39, 39, 39, 1.0], # Potato Crop Block
		41: [40, 40, 40, 0.88], # Lava Block
		43: [41, 41, 41, 1.0],  # Obsidian Block
	}

	var fallback_icon_dir: String = ProjectSettings.globalize_path("res://assets/ui/item_icons/")
	for block_id in block_icon_specs.keys():
		var spec: Array = block_icon_specs[block_id]
		var top_t: Image = tiles[int(spec[0])]
		var left_t: Image = tiles[int(spec[1])]
		var right_t: Image = tiles[int(spec[2])]
		var h_scale: float = float(spec[3])
		var iso_icon: Image = _render_iso_cube_icon(top_t, left_t, right_t, h_scale)
		iso_icon.save_png(icon_dir + ("item_%d.png" % int(block_id)))
		iso_icon.save_png(fallback_icon_dir + ("item_%d.png" % int(block_id)))

	# Water Block Icon (ID 9)
	var water_icon: Image = _render_iso_cube_icon(water_tile, water_tile, water_tile, 0.88)
	water_icon.save_png(icon_dir + "item_9.png")
	water_icon.save_png(fallback_icon_dir + "item_9.png")
	print("[Faithful64xBuilder] Rendered 24 Isometric 3D Block Icons from Faithful 64x tiles.")


func _build_water_texture() -> void:
	var water_raw: Image = _load_tile_64("block/water_still.png")
	var water_tinted := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var c: Color = water_raw.get_pixel(x, y)
			var lum: float = (c.r + c.g + c.b) / 3.0
			water_tinted.set_pixel(x, y, Color(
				clampf(lum * 0.26, 0.05, 1.0),
				clampf(lum * 0.56, 0.15, 1.0),
				clampf(lum * 1.05, 0.35, 1.0),
				0.78
			))
	var out_path: String = ProjectSettings.globalize_path("res://assets/packs/faithful_64x/textures/water_still_64.png")
	water_tinted.save_png(out_path)
	print("[Faithful64xBuilder] Saved Faithful 64x Water Texture -> ", out_path)


func _copy_destroy_stages() -> void:
	for stage in range(10):
		var src: Image = _load_tile_64("block/destroy_stage_%d.png" % stage)
		var out_path: String = ProjectSettings.globalize_path("res://assets/packs/faithful_64x/textures/destroy_stages/destroy_stage_%d.png" % stage)
		src.save_png(out_path)
	print("[Faithful64xBuilder] Copied 10 Faithful 64x block destroy_stage_0..9 textures.")


func _build_hud_and_gui_assets() -> void:
	var hud_dir: String = ProjectSettings.globalize_path("res://assets/packs/faithful_64x/ui/hud_icons/")
	var gui_dir: String = ProjectSettings.globalize_path("res://assets/packs/faithful_64x/ui/gui_panels/")

	# 1. Hearts (composite container + full / half)
	var heart_cont: Image = _load_faithful_image("gui/sprites/hud/heart/container.png")
	var heart_full_fg: Image = _load_faithful_image("gui/sprites/hud/heart/full.png")
	var heart_half_fg: Image = _load_faithful_image("gui/sprites/hud/heart/half.png")
	_alpha_composite(heart_cont, heart_full_fg).save_png(hud_dir + "heart_full.png")
	_alpha_composite(heart_cont, heart_half_fg).save_png(hud_dir + "heart_half.png")
	heart_cont.save_png(hud_dir + "heart_empty.png")

	# 2. Hunger Drumsticks (composite food_empty + food_full / food_half)
	var food_cont: Image = _load_faithful_image("gui/sprites/hud/food_empty.png")
	var food_full_fg: Image = _load_faithful_image("gui/sprites/hud/food_full.png")
	var food_half_fg: Image = _load_faithful_image("gui/sprites/hud/food_half.png")
	_alpha_composite(food_cont, food_full_fg).save_png(hud_dir + "hunger_full.png")
	_alpha_composite(food_cont, food_half_fg).save_png(hud_dir + "hunger_half.png")
	food_cont.save_png(hud_dir + "hunger_empty.png")

	# 3. Oxygen Bubbles & Crosshair
	_load_faithful_image("gui/sprites/hud/air.png").save_png(hud_dir + "bubble_full.png")
	_load_faithful_image("gui/sprites/hud/air_bursting.png").save_png(hud_dir + "bubble_empty.png")
	_load_faithful_image("gui/sprites/hud/crosshair.png").save_png(hud_dir + "crosshair.png")

	# 4. Armor Slot Silhouettes
	_load_faithful_image("gui/sprites/container/slot/helmet.png").save_png(hud_dir + "armor_helmet.png")
	_load_faithful_image("gui/sprites/container/slot/chestplate.png").save_png(hud_dir + "armor_chestplate.png")
	_load_faithful_image("gui/sprites/container/slot/leggings.png").save_png(hud_dir + "armor_leggings.png")
	_load_faithful_image("gui/sprites/container/slot/boots.png").save_png(hud_dir + "armor_boots.png")

	# 5. GUI Slots, Selected Frame & Container Panel
	var slot_norm: Image = _load_faithful_image("gui/sprites/container/slot.png")
	slot_norm.save_png(gui_dir + "slot_normal.png")

	# Selected slot frame: composite hotbar_selection over slot_normal
	var sel_raw: Image = _load_faithful_image("gui/sprites/hud/hotbar_selection.png")
	sel_raw.resize(72, 72, Image.INTERPOLATE_NEAREST)
	var slot_sel: Image = _alpha_composite(slot_norm, sel_raw)
	slot_sel.save_png(gui_dir + "slot_selected.png")

	# Output slot: warm golden-trimmed Faithful slot
	var slot_out: Image = _tint_image(slot_norm, Color(1.05, 0.96, 0.78, 1.0))
	slot_out.save_png(gui_dir + "slot_output.png")

	# Faithful 64x Hotbar strip
	_load_faithful_image("gui/sprites/hud/hotbar.png").save_png(gui_dir + "hotbar_bg.png")

	# Faithful 64x Stone-Grey Modal Dialog Panel (extracted from inventory.png outer 3D bevel frame)
	var inv_sheet: Image = _load_faithful_image("gui/container/inventory.png")
	var panel_bg := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	if inv_sheet.get_width() >= 704 and inv_sheet.get_height() >= 664:
		# Top-left 16x16 corner (x=0..15, y=0..15), top-right (x=688..703, y=0..15),
		# bottom-left (x=0..15, y=648..663), bottom-right (x=688..703, y=648..663)
		var fill_col: Color = inv_sheet.get_pixel(32, 32)
		panel_bg.fill(fill_col)
		# Copy 16px 3D beveled borders from `inventory.png`
		panel_bg.blit_rect(inv_sheet, Rect2i(0, 0, 64, 16), Vector2i(0, 0))
		panel_bg.blit_rect(inv_sheet, Rect2i(640, 0, 64, 16), Vector2i(64, 0))
		panel_bg.blit_rect(inv_sheet, Rect2i(0, 648, 64, 16), Vector2i(0, 112))
		panel_bg.blit_rect(inv_sheet, Rect2i(640, 648, 64, 16), Vector2i(64, 112))
		panel_bg.blit_rect(inv_sheet, Rect2i(0, 16, 16, 96), Vector2i(0, 16))
		panel_bg.blit_rect(inv_sheet, Rect2i(688, 16, 16, 96), Vector2i(112, 16))
	else:
		panel_bg.fill(Color(0.77, 0.77, 0.77, 1.0))
	panel_bg.save_png(gui_dir + "panel_bg.png")
	# 6. Authentic Container Windows
	var inv_full: Image = _load_faithful_image("gui/container/inventory.png")
	inv_full.save_png(gui_dir + "container_inventory.png")
	var craft_full: Image = _load_faithful_image("gui/container/crafting_table.png")
	craft_full.save_png(gui_dir + "container_crafting_table.png")
	var furn_full: Image = _load_faithful_image("gui/container/furnace.png")
	furn_full.save_png(gui_dir + "container_furnace.png")
	var chest_full: Image = _load_faithful_image("gui/container/generic_54.png")
	chest_full.save_png(gui_dir + "container_chest.png")
	var furn_lit: Image = _load_faithful_image("gui/sprites/container/furnace/lit_progress.png")
	furn_lit.save_png(gui_dir + "furnace_lit_progress.png")
	var furn_burn: Image = _load_faithful_image("gui/sprites/container/furnace/burn_progress.png")
	furn_burn.save_png(gui_dir + "furnace_burn_progress.png")

	# 7. Authentic Buttons & Widget Sprites
	_load_faithful_image("gui/sprites/widget/button.png").save_png(gui_dir + "button.png")
	_load_faithful_image("gui/sprites/widget/button_highlighted.png").save_png(gui_dir + "button_highlighted.png")
	_load_faithful_image("gui/sprites/widget/button_disabled.png").save_png(gui_dir + "button_disabled.png")
	_load_faithful_image("gui/sprites/widget/slider.png").save_png(gui_dir + "slider.png")
	_load_faithful_image("gui/sprites/widget/slider_handle.png").save_png(gui_dir + "slider_handle.png")
	_load_faithful_image("gui/sprites/widget/text_field.png").save_png(gui_dir + "text_field.png")

	# 8. Title Panorama Backdrop
	var panorama: Image = _load_faithful_image("gui/title/background/panorama_0.png")
	panorama.save_png(gui_dir + "title_panorama.png")

	print("[Faithful64xBuilder] Saved Faithful 64x HUD & GUI textures.")


func _copy_2d_item_icons() -> void:
	var icon_dir: String = ProjectSettings.globalize_path("res://assets/packs/faithful_64x/ui/item_icons/")
	var item_map: Dictionary = {
		# Placeable Non-Full-Block Items
		19: "block/torch.png",
		21: "item/oak_door.png",
		22: "item/oak_door.png",
		23: "block/ladder.png",

		# Resources & Food (Matching InventoryManager.ItemId exactly)
		100: "item/stick.png",
		101: "item/coal.png",
		102: "item/raw_iron.png",
		103: "item/iron_ingot.png",
		104: "item/raw_gold.png",
		105: "item/gold_ingot.png",
		106: "item/diamond.png",
		107: "item/bucket.png",
		108: "item/water_bucket.png",
		110: "item/porkchop.png",
		111: "item/cooked_porkchop.png",
		112: "item/beef.png",
		113: "item/cooked_beef.png",
		114: "item/apple.png",
		115: "item/rotten_flesh.png",
		116: "item/gunpowder.png",

		# Pickaxes (201..204)
		201: "item/wooden_pickaxe.png",
		202: "item/stone_pickaxe.png",
		203: "item/iron_pickaxe.png",
		204: "item/diamond_pickaxe.png",

		# Axes (211..214)
		211: "item/wooden_axe.png",
		212: "item/stone_axe.png",
		213: "item/iron_axe.png",
		214: "item/diamond_axe.png",

		# Shovels (221..224)
		221: "item/wooden_shovel.png",
		222: "item/stone_shovel.png",
		223: "item/iron_shovel.png",
		224: "item/diamond_shovel.png",

		# Swords (231..234)
		231: "item/wooden_sword.png",
		232: "item/stone_sword.png",
		233: "item/iron_sword.png",
		234: "item/diamond_sword.png",
	}

	for item_id in item_map.keys():
		var rel_path: String = item_map[item_id]
		var img: Image = _load_tile_64(rel_path)
		img.save_png(icon_dir + ("item_%d.png" % int(item_id)))

	print("[Faithful64xBuilder] Copied %d Faithful 64x 2D Item & Tool icons." % item_map.size())


func _copy_entity_and_environment_textures() -> void:
	var entity_dir: String = ProjectSettings.globalize_path("res://assets/packs/faithful_64x/textures/entity/")
	var env_dir: String = ProjectSettings.globalize_path("res://assets/packs/faithful_64x/textures/environment/")

	var entities: Dictionary = {
		"zombie.png": "entity/zombie/zombie.png",
		"skeleton.png": "entity/skeleton/skeleton.png",
		"creeper.png": "entity/creeper/creeper.png",
		"spider.png": "entity/spider/spider.png",
		"cow.png": "entity/cow/cow_temperate.png",
		"pig.png": "entity/pig/pig_temperate.png",
		"steve.png": "entity/player/wide/steve.png",
	}
	for out_name in entities.keys():
		var src_img: Image = _load_faithful_image(entities[out_name])
		src_img.save_png(entity_dir + out_name)

	var env: Dictionary = {
		"sun.png": "environment/celestial/sun.png",
		"moon.png": "environment/celestial/moon/full_moon.png",
	}
	for out_name in env.keys():
		var src_img: Image = _load_faithful_image(env[out_name])
		src_img.save_png(env_dir + out_name)

	print("[Faithful64xBuilder] Copied Faithful 64x Mob, Player Skin, Sun and Moon textures.")
