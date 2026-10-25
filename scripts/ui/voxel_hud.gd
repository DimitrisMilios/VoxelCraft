class_name VoxelHUD
extends CanvasLayer
## Retro HUD displaying center crosshair, mining progress bar, 10-heart survival health bar,
## 10-slot hotbar with live stack counts, Crafting Table & Furnace (Oven) UI (E / Right-Click),
## and Pause Menu (Esc).

const HEART_COUNT: int = 10

var _player: PlayerController = null
var _world_manager: WorldManager = null
var _day_night: DayNightCycle = null
var _interactor: BlockInteractor = null
var _inventory: InventoryManager = null

var _slot_panels: Array[PanelContainer] = []
var _slot_swatches: Array[ColorRect] = []
var _slot_labels: Array[Label] = []
var _heart_rects: Array[ColorRect] = []

var _debug_label: Label = null
var _loot_label: Label = null
var _mining_bar_holder: Control = null
var _mining_fill: ColorRect = null
var _mining_label: Label = null

var _underwater_tint: ColorRect = null
var _damage_tint: ColorRect = null
var _pause_overlay: Control = null
var _station_overlay: Control = null
var _station_title_label: Label = null
var _station_resources_label: Label = null
var _station_feedback_label: Label = null
var _render_dist_label: Label = null
var _pause_status_label: Label = null

var _is_station_open: bool = false
var _save_toast_timer: float = 0.0
var _loot_toast_timer: float = 0.0
var _damage_flash_alpha: float = 0.0


func _ready() -> void:
	_build_screen_tints()
	_build_crosshair_and_mining_bar()
	_build_bottom_hud()
	_build_debug_overlay()
	_build_station_modal()
	_build_pause_menu()
	call_deferred("_bind_references")


func _unhandled_input(event: InputEvent) -> void:
	if _is_station_open and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E or event.physical_keycode == KEY_ESCAPE:
			_close_station_modal()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _save_toast_timer > 0.0:
		_save_toast_timer = maxf(0.0, _save_toast_timer - delta)

	if _loot_toast_timer > 0.0:
		_loot_toast_timer = maxf(0.0, _loot_toast_timer - delta)
		if _loot_label != null:
			_loot_label.visible = (_loot_toast_timer > 0.0)

	if _damage_flash_alpha > 0.0:
		_damage_flash_alpha = maxf(0.0, _damage_flash_alpha - delta * 1.8)
		if _damage_tint != null:
			_damage_tint.color.a = _damage_flash_alpha
			_damage_tint.visible = (_damage_flash_alpha > 0.01)

	if _underwater_tint != null and _player != null:
		_underwater_tint.visible = _player.is_head_underwater

	if _station_overlay != null:
		_station_overlay.visible = _is_station_open

	if _pause_overlay != null:
		_pause_overlay.visible = (Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED) and not _is_station_open

	if _debug_label != null and _player != null:
		var pos: Vector3 = _player.global_position
		var chunk_coord: Vector2i = WorldManager.world_to_chunk_coords(pos)
		var fps: int = Engine.get_frames_per_second()
		var held_name: String = "Wood Pick"
		if _interactor != null:
			held_name = InventoryManager.get_item_name(_interactor.get_selected_item_id())

		var active_chunks: int = _world_manager.get_active_chunk_count() if _world_manager != null else 0
		var modified_chunks: int = _world_manager.get_modified_chunk_count() if _world_manager != null else 0
		var time_str: String = _day_night.get_formatted_time() if _day_night != null else "Day 1 09:30"
		var mode_str: String = "FLY (CREATIVE)" if _player.is_flying else ("SWIM" if _player.is_in_water else "SURVIVAL")
		var save_status: String = " | [SAVED!]" if _save_toast_timer > 0.0 else ""

		_debug_label.text = (
			"VoxelCraft 0.7 | %d FPS | %s | Mode: %s | HP: %d/%d | Chunks: %d (Saved: %d)%s\n"
			% [fps, time_str, mode_str, _player.current_health, _player.max_health, active_chunks, modified_chunks, save_status]
			+ "XYZ: %.1f, %.1f, %.1f | Chunk: (%d, %d) | Equipped: %s\n"
			% [pos.x, pos.y, pos.z, chunk_coord.x, chunk_coord.y, held_name]
			+ "[Hold LMB] Mine  [RMB] Place/Use  [E] Craft/Oven  [1-0] Slot  [F] Fly  [T] +Time  [F6] Save"
		)


func _bind_references() -> void:
	_player = get_tree().get_first_node_in_group("player") as PlayerController
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	_day_night = get_tree().get_first_node_in_group("day_night_cycle") as DayNightCycle
	_inventory = get_tree().get_first_node_in_group("inventory_manager") as InventoryManager

	if _world_manager != null:
		_world_manager.world_saved.connect(_on_world_saved)

	if _inventory != null:
		_inventory.inventory_updated.connect(_refresh_hotbar_and_station_counts)

	if _player != null:
		_player.health_changed.connect(_on_health_changed)
		_player.player_damaged.connect(_on_player_damaged)
		_on_health_changed(_player.current_health, _player.max_health)

		_interactor = _player.get_node_or_null("BlockInteractor") as BlockInteractor
		if _interactor != null:
			_interactor.hotbar_slot_changed.connect(_on_hotbar_slot_changed)
			_interactor.mining_progress_changed.connect(_on_mining_progress_changed)
			_interactor.station_opened.connect(_on_station_opened)
			_interactor.loot_notification.connect(_on_loot_notification)
			_on_hotbar_slot_changed(_interactor.selected_slot, _interactor.get_selected_item_id())

	_refresh_hotbar_and_station_counts()


func _on_world_saved(saved_chunk_count: int) -> void:
	_save_toast_timer = 2.5
	if _pause_status_label != null:
		_pause_status_label.text = "Saved %d modified chunk(s) to disk!" % saved_chunk_count


func _on_loot_notification(message: String) -> void:
	if _loot_label != null:
		_loot_label.text = message
		_loot_label.visible = true
		_loot_toast_timer = 2.0


func _on_mining_progress_changed(progress: float, target_name: String) -> void:
	if _mining_bar_holder == null:
		return
	if progress <= 0.001:
		_mining_bar_holder.visible = false
		return
	_mining_bar_holder.visible = true
	_mining_fill.size.x = 120.0 * clampf(progress, 0.0, 1.0)
	_mining_label.text = "Mining %s (%d%%)" % [target_name, int(round(progress * 100.0))]


func _on_station_opened(station_block_id: int) -> void:
	if _is_station_open:
		_close_station_modal()
		return
	_is_station_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _station_title_label != null:
		if station_block_id == BlockRegistry.BlockId.FURNACE:
			_station_title_label.text = "FURNACE OVEN & WORKBENCH"
		else:
			_station_title_label.text = "CRAFTING TABLE & FURNACE OVEN"
	_refresh_hotbar_and_station_counts()


func _close_station_modal() -> void:
	_is_station_open = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_player_damaged(_amount: int) -> void:
	_damage_flash_alpha = 0.42
	if _damage_tint != null:
		_damage_tint.visible = true
		_damage_tint.color.a = _damage_flash_alpha


func _on_health_changed(current_hp: int, _max_hp: int) -> void:
	var is_creative: bool = _player != null and _player.is_flying
	for i in range(_heart_rects.size()):
		var heart_hp: int = current_hp - (i * 2)
		if is_creative:
			_heart_rects[i].color = Color(0.28, 0.82, 0.96, 0.92)
		elif heart_hp >= 2:
			_heart_rects[i].color = Color(0.92, 0.18, 0.22, 0.96)
		elif heart_hp == 1:
			_heart_rects[i].color = Color(0.95, 0.56, 0.24, 0.96)
		else:
			_heart_rects[i].color = Color(0.18, 0.18, 0.22, 0.78)


func _build_screen_tints() -> void:
	_underwater_tint = ColorRect.new()
	_underwater_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_underwater_tint.color = Color(0.06, 0.28, 0.68, 0.42)
	_underwater_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underwater_tint.visible = false
	add_child(_underwater_tint)

	_damage_tint = ColorRect.new()
	_damage_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_tint.color = Color(0.85, 0.08, 0.08, 0.0)
	_damage_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_tint.visible = false
	add_child(_damage_tint)


func _build_crosshair_and_mining_bar() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var crosshair_holder := Control.new()
	crosshair_holder.custom_minimum_size = Vector2(20, 20)
	crosshair_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(crosshair_holder)

	var h_bar := ColorRect.new()
	h_bar.color = Color(1, 1, 1, 0.88)
	h_bar.size = Vector2(14, 2)
	h_bar.position = Vector2(3, 9)
	h_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_holder.add_child(h_bar)

	var v_bar := ColorRect.new()
	v_bar.color = Color(1, 1, 1, 0.88)
	v_bar.size = Vector2(2, 14)
	v_bar.position = Vector2(9, 3)
	v_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_holder.add_child(v_bar)

	# Mining progress bar directly below center crosshair
	_mining_bar_holder = Control.new()
	_mining_bar_holder.position = Vector2(-50, 28)
	_mining_bar_holder.visible = false
	_mining_bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_holder.add_child(_mining_bar_holder)

	var bar_bg := ColorRect.new()
	bar_bg.size = Vector2(124, 10)
	bar_bg.position = Vector2(-2, -2)
	bar_bg.color = Color(0.08, 0.08, 0.10, 0.88)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_bar_holder.add_child(bar_bg)

	_mining_fill = ColorRect.new()
	_mining_fill.size = Vector2(0, 6)
	_mining_fill.color = Color(0.98, 0.78, 0.18, 0.96)
	_mining_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_bar_holder.add_child(_mining_fill)

	_mining_label = Label.new()
	_mining_label.position = Vector2(-20, 10)
	_mining_label.add_theme_font_size_override("font_size", 12)
	_mining_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_mining_label.add_theme_constant_override("shadow_offset_x", 1)
	_mining_label.add_theme_constant_override("shadow_offset_y", 1)
	_mining_bar_holder.add_child(_mining_label)


func _build_bottom_hud() -> void:
	var bottom_margin := MarginContainer.new()
	bottom_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_margin.offset_top = -132
	bottom_margin.add_theme_constant_override("margin_bottom", 12)
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.alignment = BoxContainer.ALIGNMENT_END
	root_vbox.add_theme_constant_override("separation", 5)
	root_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_margin.add_child(root_vbox)

	# Loot pickup notification toast
	_loot_label = Label.new()
	_loot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loot_label.add_theme_font_size_override("font_size", 14)
	_loot_label.add_theme_color_override("font_color", Color(0.98, 0.92, 0.35))
	_loot_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_loot_label.add_theme_constant_override("shadow_offset_x", 1)
	_loot_label.add_theme_constant_override("shadow_offset_y", 1)
	_loot_label.visible = false
	root_vbox.add_child(_loot_label)

	# 1. 10-Heart Survival Health Bar
	var hearts_hbox := HBoxContainer.new()
	hearts_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hearts_hbox.add_theme_constant_override("separation", 5)
	hearts_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(hearts_hbox)

	for i in range(HEART_COUNT):
		var heart_frame := PanelContainer.new()
		heart_frame.custom_minimum_size = Vector2(16, 16)
		heart_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h_style := StyleBoxFlat.new()
		h_style.bg_color = Color(0.08, 0.08, 0.10, 0.85)
		h_style.border_color = Color(0.05, 0.05, 0.06, 0.95)
		h_style.set_border_width_all(1)
		h_style.set_corner_radius_all(3)
		heart_frame.add_theme_stylebox_override("panel", h_style)

		var heart_fill := ColorRect.new()
		heart_fill.custom_minimum_size = Vector2(12, 12)
		heart_fill.color = Color(0.92, 0.18, 0.22, 0.96)
		heart_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heart_frame.add_child(heart_fill)

		hearts_hbox.add_child(heart_frame)
		_heart_rects.append(heart_fill)

	# 2. 10-Slot Block & Tool Hotbar
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 5)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(hbox)

	var default_slots: Array[int] = [
		InventoryManager.ItemId.WOOD_PICKAXE,
		BlockRegistry.BlockId.CRAFTING_TABLE,
		BlockRegistry.BlockId.FURNACE,
		BlockRegistry.BlockId.COBBLESTONE,
		BlockRegistry.BlockId.WOOD_LOG,
		BlockRegistry.BlockId.WOOD_PLANKS,
		BlockRegistry.BlockId.GRASS,
		BlockRegistry.BlockId.SAND,
		BlockRegistry.BlockId.SNOW,
		BlockRegistry.BlockId.GLOWSTONE,
	]

	for i in range(default_slots.size()):
		var item_id: int = default_slots[i]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(64, 62)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(vbox)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(24, 24)
		swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		swatch.color = InventoryManager.get_item_color(item_id)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(swatch)

		var key_num: int = (i + 1) % 10
		var label := Label.new()
		label.text = "%d:%s" % [key_num, InventoryManager.get_item_name(item_id).substr(0, 6)]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 10)
		vbox.add_child(label)

		hbox.add_child(panel)
		_slot_panels.append(panel)
		_slot_swatches.append(swatch)
		_slot_labels.append(label)

	_update_hotbar_visuals(0)


func _refresh_hotbar_and_station_counts() -> void:
	if _interactor != null:
		for i in range(mini(_slot_labels.size(), _interactor.hotbar_items.size())):
			var item_id: int = _interactor.hotbar_items[i]
			var key_num: int = (i + 1) % 10
			var short_name: String = InventoryManager.get_item_name(item_id).substr(0, 6)
			_slot_swatches[i].color = InventoryManager.get_item_color(item_id)

			if InventoryManager.is_pickaxe(item_id):
				_slot_labels[i].text = "%d:%s" % [key_num, short_name]
			else:
				var qty: int = _inventory.get_count(item_id) if _inventory != null else 0
				_slot_labels[i].text = "%d:%s\nx%d" % [key_num, short_name, qty]

	if _station_resources_label != null and _inventory != null:
		_station_resources_label.text = (
			"Materials:  Wood Log: %d  |  Planks: %d  |  Sticks: %d  |  Cobble: %d  |  Coal: %d\n"
			% [
				_inventory.get_count(BlockRegistry.BlockId.WOOD_LOG),
				_inventory.get_count(BlockRegistry.BlockId.WOOD_PLANKS),
				_inventory.get_count(InventoryManager.ItemId.STICK),
				_inventory.get_count(BlockRegistry.BlockId.COBBLESTONE),
				_inventory.get_count(InventoryManager.ItemId.COAL),
			]
			+ "Ores & Ingots:  Raw Iron: %d  |  Iron Ingot: %d  |  Raw Gold: %d  |  Gold Ingot: %d  |  Diamond: %d"
			% [
				_inventory.get_count(InventoryManager.ItemId.RAW_IRON),
				_inventory.get_count(InventoryManager.ItemId.IRON_INGOT),
				_inventory.get_count(InventoryManager.ItemId.RAW_GOLD),
				_inventory.get_count(InventoryManager.ItemId.GOLD_INGOT),
				_inventory.get_count(InventoryManager.ItemId.DIAMOND),
			]
		)


func _build_station_modal() -> void:
	_station_overlay = ColorRect.new()
	_station_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_station_overlay.color = Color(0.04, 0.06, 0.09, 0.72)
	_station_overlay.visible = false
	add_child(_station_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_station_overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(680, 440)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.13, 0.15, 0.19, 0.97)
	card_style.border_color = Color(0.86, 0.62, 0.24, 1.0)
	card_style.set_border_width_all(3)
	card_style.set_corner_radius_all(8)
	card_style.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	card.add_child(root_vbox)

	_station_title_label = Label.new()
	_station_title_label.text = "CRAFTING TABLE & FURNACE OVEN"
	_station_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_station_title_label.add_theme_font_size_override("font_size", 20)
	root_vbox.add_child(_station_title_label)

	_station_resources_label = Label.new()
	_station_resources_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_station_resources_label.add_theme_font_size_override("font_size", 13)
	_station_resources_label.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	root_vbox.add_child(_station_resources_label)

	_station_feedback_label = Label.new()
	_station_feedback_label.text = "Click any recipe below to craft tools, blocks, or smelt ores in the oven!"
	_station_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_station_feedback_label.add_theme_font_size_override("font_size", 13)
	_station_feedback_label.add_theme_color_override("font_color", Color(0.98, 0.86, 0.32))
	root_vbox.add_child(_station_feedback_label)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	root_vbox.add_child(columns)

	# Left Column: Crafting Table Recipes
	var craft_col := VBoxContainer.new()
	craft_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	craft_col.add_theme_constant_override("separation", 6)
	columns.add_child(craft_col)

	var craft_header := Label.new()
	craft_header.text = "WORKBENCH CRAFTING"
	craft_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	craft_header.add_theme_color_override("font_color", Color(0.55, 0.90, 0.55))
	craft_col.add_child(craft_header)

	var craft_recipes: Array[Array] = [
		["planks", "4x Wood Planks (Cost: 1 Wood Log)"],
		["sticks", "4x Sticks (Cost: 2 Planks)"],
		["crafting_table", "1x Crafting Table (Cost: 4 Planks)"],
		["furnace", "1x Furnace Oven (Cost: 6 Cobble)"],
		["glowstone", "4x Glowstone Lantern (Cost: 1 Coal + 1 Stick)"],
		["stone_pickaxe", "Stone Pickaxe 3.8x (Cost: 3 Cobble + 2 Sticks)"],
		["iron_pickaxe", "Iron Pickaxe 5.8x (Cost: 3 Iron Ingot + 2 Sticks)"],
		["diamond_pickaxe", "Diamond Pickaxe 9.5x (Cost: 3 Diamond + 2 Sticks)"],
	]
	for rec in craft_recipes:
		var recipe_id: String = rec[0]
		var btn := Button.new()
		btn.text = rec[1]
		btn.custom_minimum_size = Vector2(0, 30)
		btn.pressed.connect(func() -> void:
			if _inventory != null:
				var res: Dictionary = _inventory.try_craft(recipe_id)
				_station_feedback_label.text = str(res.get("msg", ""))
				_refresh_hotbar_and_station_counts()
		)
		craft_col.add_child(btn)

	# Right Column: Furnace / Oven Smelting
	var smelt_col := VBoxContainer.new()
	smelt_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	smelt_col.add_theme_constant_override("separation", 8)
	columns.add_child(smelt_col)

	var smelt_header := Label.new()
	smelt_header.text = "FURNACE / OVEN SMELTING"
	smelt_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	smelt_header.add_theme_color_override("font_color", Color(1.0, 0.65, 0.30))
	smelt_col.add_child(smelt_header)

	var smelt_recipes: Array[Array] = [
		["iron_ingot", "Smelt Iron Ingot (1 Raw Iron + 1 Coal)"],
		["gold_ingot", "Smelt Gold Ingot (1 Raw Gold + 1 Coal)"],
		["charcoal", "Bake 2x Charcoal Fuel (1 Wood Log)"],
	]
	for srec in smelt_recipes:
		var smelt_id: String = srec[0]
		var sbtn := Button.new()
		sbtn.text = srec[1]
		sbtn.custom_minimum_size = Vector2(0, 34)
		sbtn.pressed.connect(func() -> void:
			if _inventory != null:
				var res: Dictionary = _inventory.try_smelt(smelt_id)
				_station_feedback_label.text = str(res.get("msg", ""))
				_refresh_hotbar_and_station_counts()
		)
		smelt_col.add_child(sbtn)

	var tip_label := Label.new()
	tip_label.text = "Tip: Dig underground in caves to mine\nCoal, Iron, Gold, and Diamond Ore veins!"
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_label.add_theme_font_size_override("font_size", 12)
	tip_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.84))
	smelt_col.add_child(tip_label)

	var close_btn := Button.new()
	close_btn.text = "Close Workbench / Oven (E or Esc)"
	close_btn.custom_minimum_size = Vector2(0, 36)
	close_btn.pressed.connect(_close_station_modal)
	root_vbox.add_child(close_btn)


func _build_debug_overlay() -> void:
	_debug_label = Label.new()
	_debug_label.position = Vector2(14, 12)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_debug_label)


func _build_pause_menu() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.color = Color(0.05, 0.07, 0.10, 0.65)
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(360, 340)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.12, 0.14, 0.18, 0.96)
	card_style.border_color = Color(0.42, 0.72, 0.36, 1.0)
	card_style.set_border_width_all(3)
	card_style.set_corner_radius_all(8)
	card_style.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "VOXELCRAFT — PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	_pause_status_label = Label.new()
	_pause_status_label.text = "Adjust settings or save your world"
	_pause_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_status_label.add_theme_font_size_override("font_size", 12)
	_pause_status_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.75))
	vbox.add_child(_pause_status_label)

	var resume_btn := Button.new()
	resume_btn.text = "Resume Game (Esc)"
	resume_btn.custom_minimum_size = Vector2(0, 36)
	resume_btn.pressed.connect(func() -> void:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	)
	vbox.add_child(resume_btn)

	_render_dist_label = Label.new()
	_render_dist_label.text = "Render Distance: 5 Chunks"
	_render_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_render_dist_label)

	var slider := HSlider.new()
	slider.min_value = 2
	slider.max_value = 8
	slider.step = 1
	slider.value = 5
	slider.value_changed.connect(func(val: float) -> void:
		var dist: int = int(val)
		_render_dist_label.text = "Render Distance: %d Chunks" % dist
		if _world_manager != null:
			_world_manager.set_render_distance(dist)
	)
	vbox.add_child(slider)

	var fly_btn := Button.new()
	fly_btn.text = "Toggle Creative Fly Mode (F)"
	fly_btn.custom_minimum_size = Vector2(0, 34)
	fly_btn.pressed.connect(func() -> void:
		if _player != null:
			_player.is_flying = not _player.is_flying
			_player.velocity.y = 0.0
			_on_health_changed(_player.current_health, _player.max_health)
			_pause_status_label.text = "Fly Mode: %s" % ("ENABLED" if _player.is_flying else "DISABLED")
	)
	vbox.add_child(fly_btn)

	var time_btn := Button.new()
	time_btn.text = "Advance Time +2.5 Hours (T)"
	time_btn.custom_minimum_size = Vector2(0, 34)
	time_btn.pressed.connect(func() -> void:
		if _day_night != null:
			_day_night.advance_hours(2.5)
			_pause_status_label.text = "Time set to %s" % _day_night.get_formatted_time()
	)
	vbox.add_child(time_btn)

	var save_btn := Button.new()
	save_btn.text = "Save World to Disk (F6)"
	save_btn.custom_minimum_size = Vector2(0, 34)
	save_btn.pressed.connect(func() -> void:
		if _world_manager != null:
			var count: int = _world_manager.save_all_modified_chunks()
			_on_world_saved(count)
	)
	vbox.add_child(save_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Save & Quit to Desktop"
	quit_btn.custom_minimum_size = Vector2(0, 34)
	quit_btn.pressed.connect(func() -> void:
		if _world_manager != null:
			_world_manager.save_all_modified_chunks()
		get_tree().quit()
	)
	vbox.add_child(quit_btn)


func _on_hotbar_slot_changed(slot_index: int, _item_id: int) -> void:
	_update_hotbar_visuals(slot_index)
	_refresh_hotbar_and_station_counts()


func _update_hotbar_visuals(active_slot: int) -> void:
	for i in range(_slot_panels.size()):
		var style := StyleBoxFlat.new()
		if i == active_slot:
			style.bg_color = Color(0.18, 0.22, 0.28, 0.92)
			style.border_color = Color(0.98, 0.84, 0.24, 1.0)
			style.set_border_width_all(3)
		else:
			style.bg_color = Color(0.10, 0.12, 0.15, 0.78)
			style.border_color = Color(0.45, 0.48, 0.52, 0.85)
			style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		_slot_panels[i].add_theme_stylebox_override("panel", style)
