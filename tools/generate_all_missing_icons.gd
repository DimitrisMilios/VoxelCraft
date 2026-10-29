extends SceneTree
## Generates missing 64x64 Faithful-style item icons and UI silhouettes for VoxelCraft:
## - Redstone Dust (127), Flint (125), Clay Ball (126), Lapis Lazuli (128)
## - Leather Armor (301..304), Iron Armor (311..314), Gold Armor (321..324), Diamond Armor (331..334)
## - Gold Tools (205, 215, 225, 235) by recoloring existing Iron tools
## - Shield silhouette for the offhand inventory slot

const OUT_DIRS: Array[String] = [
	"res://assets/ui/item_icons/",
	"res://assets/packs/faithful_64x/ui/item_icons/"
]

func _initialize() -> void:
	print("[IconGen] Generating missing item icons and UI silhouettes...")
	_ensure_dirs()
	_generate_gold_tools()
	_generate_materials()
	_generate_armor_set(301, Color(0.52, 0.32, 0.17), Color(0.35, 0.20, 0.09), Color(0.66, 0.44, 0.24), Color(0.20, 0.12, 0.05)) # Leather
	_generate_armor_set(311, Color(0.85, 0.85, 0.85), Color(0.55, 0.55, 0.55), Color(1.0, 1.0, 1.0), Color(0.35, 0.35, 0.35))       # Iron
	_generate_armor_set(321, Color(0.98, 0.85, 0.22), Color(0.70, 0.55, 0.08), Color(1.0, 0.96, 0.65), Color(0.42, 0.35, 0.05))       # Gold
	_generate_armor_set(331, Color(0.30, 0.93, 0.95), Color(0.16, 0.66, 0.69), Color(0.75, 0.98, 1.0), Color(0.10, 0.39, 0.41))        # Diamond
	_generate_shield_silhouette()
	print("[IconGen] All missing item icons and UI silhouettes generated successfully!")
	quit(0)

func _ensure_dirs() -> void:
	for d in OUT_DIRS:
		var global_d := ProjectSettings.globalize_path(d)
		if not DirAccess.dir_exists_absolute(global_d):
			DirAccess.make_dir_recursive_absolute(global_d)

func _save_icon(img: Image, filename: String) -> void:
	for d in OUT_DIRS:
		var p := ProjectSettings.globalize_path(d + filename)
		img.save_png(p)

func _generate_gold_tools() -> void:
	var pairs: Array[Array] = [
		["item_203.png", "item_205.png"], # Iron Pickaxe -> Gold Pickaxe
		["item_213.png", "item_215.png"], # Iron Axe -> Gold Axe
		["item_223.png", "item_225.png"], # Iron Shovel -> Gold Shovel
		["item_233.png", "item_235.png"], # Iron Sword -> Gold Sword
	]
	for pair in pairs:
		var src_path := ProjectSettings.globalize_path(OUT_DIRS[0] + pair[0])
		if not FileAccess.file_exists(src_path):
			continue
		var src := Image.load_from_file(src_path)
		if src == null or src.is_empty():
			continue
		src.convert(Image.FORMAT_RGBA8)
		var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
		for y in range(src.get_height()):
			for x in range(src.get_width()):
				var c := src.get_pixel(x, y)
				if c.a < 0.05:
					out.set_pixel(x, y, Color(0, 0, 0, 0))
					continue
				# Check if pixel is gray/white (iron part) vs brown (wooden stick)
				var is_gray := absf(c.r - c.g) < 0.08 and absf(c.g - c.b) < 0.08
				if is_gray and c.r > 0.15:
					# Map luminance to rich gold palette
					var lum := c.get_luminance()
					var gold_col: Color
					if lum > 0.85:
						gold_col = Color(1.0, 0.97, 0.65, c.a)
					elif lum > 0.65:
						gold_col = Color(0.98, 0.86, 0.22, c.a)
					elif lum > 0.40:
						gold_col = Color(0.85, 0.68, 0.12, c.a)
					else:
						gold_col = Color(0.55, 0.40, 0.05, c.a)
					out.set_pixel(x, y, gold_col)
				else:
					out.set_pixel(x, y, c)
		_save_icon(out, pair[1])

func _scale_16_to_64(src16: Image) -> Image:
	var out := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			var c := src16.get_pixel(x, y)
			for dy in range(4):
				for dx in range(4):
					out.set_pixel(x * 4 + dx, y * 4 + dy, c)
	return out

func _generate_materials() -> void:
	# 1. Redstone Dust (Item 127)
	var redstone16 := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var rc_dark := Color(0.40, 0.02, 0.02, 1.0)
	var rc_mid := Color(0.82, 0.08, 0.08, 1.0)
	var rc_bright := Color(0.98, 0.18, 0.12, 1.0)
	var rc_hi := Color(1.0, 0.55, 0.45, 1.0)
	var rc_spec := Color(1.0, 0.90, 0.85, 1.0)

	var rs_pixels: Array[Array] = [
		[6, 4, rc_hi], [7, 4, rc_bright], [8, 4, rc_mid],
		[5, 5, rc_hi], [6, 5, rc_spec], [7, 5, rc_bright], [8, 5, rc_mid], [9, 5, rc_dark],
		[4, 6, rc_dark], [5, 6, rc_bright], [6, 6, rc_bright], [7, 6, rc_mid], [8, 6, rc_mid], [9, 6, rc_dark], [10, 6, rc_dark],
		[3, 7, rc_dark], [4, 7, rc_hi], [5, 7, rc_bright], [6, 7, rc_spec], [7, 7, rc_bright], [8, 7, rc_mid], [9, 7, rc_dark], [11, 7, rc_mid],
		[3, 8, rc_dark], [4, 8, rc_bright], [5, 8, rc_mid], [6, 8, rc_mid], [7, 8, rc_bright], [8, 8, rc_mid], [9, 8, rc_dark], [10, 8, rc_mid], [11, 8, rc_dark],
		[4, 9, rc_mid], [5, 9, rc_bright], [6, 9, rc_mid], [7, 9, rc_dark], [8, 9, rc_mid], [9, 9, rc_dark], [12, 9, rc_mid],
		[3, 10, rc_dark], [4, 10, rc_mid], [5, 10, rc_dark], [7, 10, rc_hi], [8, 10, rc_spec], [9, 10, rc_bright], [10, 10, rc_dark],
		[2, 11, rc_mid], [3, 11, rc_dark], [7, 11, rc_bright], [8, 11, rc_mid], [9, 11, rc_dark], [12, 11, rc_dark], [13, 11, rc_mid],
		[6, 12, rc_dark], [7, 12, rc_mid], [8, 12, rc_dark], [12, 12, rc_mid]
	]
	for p in rs_pixels:
		redstone16.set_pixel(p[0], p[1], p[2])
	_save_icon(_scale_16_to_64(redstone16), "item_127.png")

	# 2. Flint (Item 125)
	var flint16 := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var fl_dark := Color(0.12, 0.12, 0.14, 1.0)
	var fl_mid := Color(0.25, 0.25, 0.28, 1.0)
	var fl_light := Color(0.42, 0.42, 0.46, 1.0)
	var fl_hi := Color(0.60, 0.60, 0.66, 1.0)

	var fl_pixels: Array[Array] = [
		[7, 3, fl_dark], [8, 3, fl_dark],
		[6, 4, fl_dark], [7, 4, fl_hi], [8, 4, fl_mid], [9, 4, fl_dark],
		[5, 5, fl_dark], [6, 5, fl_hi], [7, 5, fl_light], [8, 5, fl_mid], [9, 5, fl_dark],
		[5, 6, fl_dark], [6, 6, fl_light], [7, 6, fl_light], [8, 6, fl_mid], [9, 6, fl_mid], [10, 6, fl_dark],
		[4, 7, fl_dark], [5, 7, fl_hi], [6, 7, fl_light], [7, 7, fl_mid], [8, 7, fl_mid], [9, 7, fl_dark],
		[4, 8, fl_dark], [5, 8, fl_light], [6, 8, fl_mid], [7, 8, fl_mid], [8, 8, fl_dark],
		[5, 9, fl_dark], [6, 9, fl_mid], [7, 9, fl_dark], [8, 9, fl_dark],
		[6, 10, fl_dark], [7, 10, fl_dark]
	]
	for p in fl_pixels:
		flint16.set_pixel(p[0], p[1], p[2])
	_save_icon(_scale_16_to_64(flint16), "item_125.png")

	# 3. Clay Ball (Item 126)
	var clay16 := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var cl_dark := Color(0.45, 0.48, 0.54, 1.0)
	var cl_mid := Color(0.62, 0.66, 0.72, 1.0)
	var cl_light := Color(0.76, 0.80, 0.86, 1.0)
	var cl_hi := Color(0.90, 0.93, 0.97, 1.0)

	for y in range(4, 12):
		for x in range(4, 12):
			var dist := Vector2(x - 7.5, y - 7.5).length()
			if dist < 3.8:
				if x < 7 and y < 7:
					clay16.set_pixel(x, y, cl_hi if dist < 2.0 else cl_light)
				elif dist > 3.0:
					clay16.set_pixel(x, y, cl_dark)
				else:
					clay16.set_pixel(x, y, cl_mid)
	_save_icon(_scale_16_to_64(clay16), "item_126.png")

	# 4. Lapis Lazuli (Item 128)
	var lapis16 := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var lp_dark := Color(0.08, 0.16, 0.42, 1.0)
	var lp_mid := Color(0.12, 0.28, 0.72, 1.0)
	var lp_light := Color(0.24, 0.48, 0.95, 1.0)
	var lp_hi := Color(0.45, 0.70, 1.0, 1.0)
	var lp_gold := Color(0.92, 0.82, 0.25, 1.0)

	var lp_pixels: Array[Array] = [
		[6, 4, lp_dark], [7, 4, lp_dark], [8, 4, lp_dark],
		[5, 5, lp_dark], [6, 5, lp_hi], [7, 5, lp_light], [8, 5, lp_mid], [9, 5, lp_dark],
		[4, 6, lp_dark], [5, 6, lp_hi], [6, 6, lp_gold], [7, 6, lp_light], [8, 6, lp_mid], [9, 6, lp_dark], [10, 6, lp_dark],
		[4, 7, lp_dark], [5, 7, lp_light], [6, 7, lp_light], [7, 7, lp_mid], [8, 7, lp_mid], [9, 7, lp_gold], [10, 7, lp_dark],
		[4, 8, lp_dark], [5, 8, lp_light], [6, 8, lp_mid], [7, 8, lp_mid], [8, 8, lp_mid], [9, 8, lp_dark],
		[5, 9, lp_dark], [6, 9, lp_mid], [7, 9, lp_mid], [8, 9, lp_dark],
		[6, 10, lp_dark], [7, 10, lp_dark]
	]
	for p in lp_pixels:
		lapis16.set_pixel(p[0], p[1], p[2])
	_save_icon(_scale_16_to_64(lapis16), "item_128.png")

func _generate_armor_set(base_id: int, col_main: Color, col_dark: Color, col_hi: Color, col_outline: Color) -> void:
	# 1. Helmet (base_id + 0)
	var h16 := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for x in range(4, 12):
		for y in range(3, 13):
			var is_border: bool = (x == 4 or x == 11 or y == 3 or (y == 8 and (x < 6 or x > 9)) or (y == 12 and (x == 4 or x == 11 or x == 7 or x == 8)))
			var is_opening: bool = (y >= 9 and y <= 11 and (x == 5 or x == 6 or x == 9 or x == 10))
			if is_opening:
				continue
			if is_border:
				h16.set_pixel(x, y, col_outline)
			elif x <= 6 and y <= 6:
				h16.set_pixel(x, y, col_hi)
			elif x >= 9 or y >= 10:
				h16.set_pixel(x, y, col_dark)
			else:
				h16.set_pixel(x, y, col_main)
	_save_icon(_scale_16_to_64(h16), "item_%d.png" % base_id)

	# 2. Chestplate (base_id + 1)
	var c16 := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(3, 14):
		for x in range(2, 14):
			# Shoulder pads and torso
			var is_neck: bool = (y <= 5 and x >= 6 and x <= 9)
			var is_arm_gap: bool = (y >= 7 and (x < 4 or x > 11))
			if is_neck or is_arm_gap:
				continue
			var is_border: bool = (y == 3 or y == 13 or x == 2 or x == 13 or (y >= 6 and (x == 4 or x == 11)))
			if is_border:
				c16.set_pixel(x, y, col_outline)
			elif x <= 6 and y <= 7:
				c16.set_pixel(x, y, col_hi)
			elif x >= 9 or y >= 11:
				c16.set_pixel(x, y, col_dark)
			else:
				c16.set_pixel(x, y, col_main)
	_save_icon(_scale_16_to_64(c16), "item_%d.png" % (base_id + 1))

	# 3. Leggings (base_id + 2)
	var l16 := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(3, 14):
		for x in range(3, 13):
			var is_crotch: bool = (y >= 6 and x >= 6 and x <= 9)
			if is_crotch:
				continue
			var is_border: bool = (y == 3 or y == 13 or x == 3 or x == 12 or (y >= 6 and (x == 6 or x == 9)))
			if is_border:
				l16.set_pixel(x, y, col_outline)
			elif (x <= 5 or (x >= 7 and x <= 8)) and y <= 6:
				l16.set_pixel(x, y, col_hi)
			elif x >= 10 or y >= 11:
				l16.set_pixel(x, y, col_dark)
			else:
				l16.set_pixel(x, y, col_main)
	_save_icon(_scale_16_to_64(l16), "item_%d.png" % (base_id + 2))

	# 4. Boots (base_id + 3)
	var b16 := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(7, 14):
		# Left boot (cols 3..6) and right boot (cols 9..12)
		for x in [3, 4, 5, 6, 9, 10, 11, 12]:
			var is_border: bool = (y == 7 or y == 13 or x == 3 or x == 6 or x == 9 or x == 12 or (y >= 11 and (x == 2 or x == 13)))
			if is_border:
				b16.set_pixel(x, y, col_outline)
			elif (x == 4 or x == 10) and y <= 9:
				b16.set_pixel(x, y, col_hi)
			elif y >= 12:
				b16.set_pixel(x, y, col_dark)
			else:
				b16.set_pixel(x, y, col_main)
	_save_icon(_scale_16_to_64(b16), "item_%d.png" % (base_id + 3))

func _generate_shield_silhouette() -> void:
	var s16 := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var col_shield := Color(0.75, 0.75, 0.80, 0.65)
	for y in range(2, 14):
		for x in range(3, 13):
			var width: int = 4
			if y >= 8:
				width = mini(4, 14 - y)
			if absi(x - 7) <= width:
				var is_edge: bool = (absi(x - 7) == width or y == 2 or y == 13)
				s16.set_pixel(x, y, Color(col_shield.r, col_shield.g, col_shield.b, 0.85 if is_edge else 0.35))
	var s64 := _scale_16_to_64(s16)
	var p := ProjectSettings.globalize_path("res://assets/ui/hud_icons/shield.png")
	s64.save_png(p)
