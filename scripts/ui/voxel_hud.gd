class_name VoxelHUD
extends CanvasLayer
## Authentic Minecraft-style HUD & GUI system:
## - Bottom 9-slot Hotbar (1-9) + 10-Heart Survival Health Bar
## - Center Crosshair + Tool-Tier Mining Progress Bar
## - [E] Player Inventory (2x2 Crafting Grid + 27 Backpack Slots + 9 Hotbar Slots + Recipe Book)
## - [Right-Click Crafting Table] 3x3 Crafting Table UI (3x3 Grid -> Output + 36 Inventory Slots + Recipe Book)
## - [Right-Click Furnace] Real-Time Furnace Oven UI (Input + Flame + Fuel -> Progress Arrow -> Output + 36 Slots)
## - Floating Cursor Stack for Left-Click (Full Stack) & Right-Click (Single Item / Half Split) drag-and-drop.

const HEART_COUNT: int = 10

enum ModalMode {
	NONE = 0,
	PLAYER_INV_2X2 = 1,
	CRAFTING_TABLE_3X3 = 2,
	FURNACE_OVEN = 3,
}

var _player: PlayerController = null
var _world_manager: WorldManager = null
var _day_night: DayNightCycle = null
var _interactor: BlockInteractor = null
var _inventory: InventoryManager = null

# Bottom HUD widgets
var _hotbar_panels: Array[PanelContainer] = []
var _hotbar_swatches: Array[ColorRect] = []
var _hotbar_labels: Array[Label] = []
var _heart_rects: Array[ColorRect] = []

var _debug_label: Label = null
var _loot_label: Label = null
var _mining_bar_holder: Control = null
var _mining_fill: ColorRect = null
var _mining_label: Label = null
var _underwater_tint: ColorRect = null
var _damage_tint: ColorRect = null

# Modal Window (Inventory / Crafting Table / Furnace)
var _modal_mode: int = ModalMode.NONE
var _modal_overlay: Control = null
var _modal_title_label: Label = null
var _modal_feedback_label: Label = null

# Top Station Views (Switched by _modal_mode)
var _craft_2x2_container: Control = null
var _craft_3x3_container: Control = null
var _furnace_container: Control = null
var _recipe_book_vbox: VBoxContainer = null

# Interactive Slot UI dictionaries `{ "panel": PanelContainer, "swatch": ColorRect, "label": Label }`
var _grid_2x2_slots: Array[Dictionary] = []
var _out_2x2_slot: Dictionary = {}
var _grid_3x3_slots: Array[Dictionary] = []
var _out_3x3_slot: Dictionary = {}
var _furnace_in_slot: Dictionary = {}
var _furnace_fuel_slot: Dictionary = {}
var _furnace_out_slot: Dictionary = {}
var _furnace_flame_bar: ColorRect = null
var _furnace_progress_bar: ColorRect = null
var _inv_modal_slots: Array[Dictionary] = [] # 36 slots (9..35 backpack, 0..8 hotbar)

# Floating mouse cursor item stack
var _cursor_float: PanelContainer = null
var _cursor_swatch: ColorRect = null
var _cursor_label: Label = null

# Pause Menu
var _pause_overlay: Control = null
var _render_dist_label: Label = null
var _pause_status_label: Label = null

var _save_toast_timer: float = 0.0
var _loot_toast_timer: float = 0.0
var _damage_flash_alpha: float = 0.0


func _ready() -> void:
	_build_screen_tints()
	_build_crosshair_and_mining_bar()
	_build_bottom_hud()
	_build_debug_overlay()
	_build_minecraft_modal()
	_build_floating_cursor_item()
	_build_pause_menu()
	call_deferred("_bind_references")


func _unhandled_input(event: InputEvent) -> void:
	if _modal_mode != ModalMode.NONE and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E or event.physical_keycode == KEY_ESCAPE:
			_close_modal()
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

	if _modal_overlay != null:
		_modal_overlay.visible = (_modal_mode != ModalMode.NONE)

	if _pause_overlay != null:
		_pause_overlay.visible = (Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED) and (_modal_mode == ModalMode.NONE)

	# Update floating cursor stack position
	if _cursor_float != null and _inventory != null:
		var cid: int = int(_inventory.cursor_stack.get("id", 0))
		var ccnt: int = int(_inventory.cursor_stack.get("count", 0))
		if _modal_mode != ModalMode.NONE and cid != 0 and ccnt > 0:
			_cursor_float.visible = true
			_cursor_float.position = get_viewport().get_mouse_position() + Vector2(12, 12)
			_cursor_swatch.color = InventoryManager.get_item_color(cid)
			_cursor_label.text = "%s\nx%d" % [InventoryManager.get_item_short_label(cid), ccnt]
		else:
			_cursor_float.visible = false

	if _debug_label != null and _player != null:
		var pos: Vector3 = _player.global_position
		var chunk_coord: Vector2i = WorldManager.world_to_chunk_coords(pos)
		var fps: int = Engine.get_frames_per_second()
		var held_name: String = "Empty Hand"
		if _interactor != null:
			held_name = InventoryManager.get_item_name(_interactor.get_selected_item_id())

		var active_chunks: int = _world_manager.get_active_chunk_count() if _world_manager != null else 0
		var modified_chunks: int = _world_manager.get_modified_chunk_count() if _world_manager != null else 0
		var time_str: String = _day_night.get_formatted_time() if _day_night != null else "Day 1 09:30"
		var mode_str: String = "CREATIVE (FLY)" if _player.is_flying else ("SWIM" if _player.is_in_water else "SURVIVAL")
		var save_status: String = " | [SAVED!]" if _save_toast_timer > 0.0 else ""

		_debug_label.text = (
			"VoxelCraft 1.0 | %d FPS | %s | Mode: %s | HP: %d/%d | Chunks: %d (Saved: %d)%s\n"
			% [fps, time_str, mode_str, _player.current_health, _player.max_health, active_chunks, modified_chunks, save_status]
			+ "XYZ: %.1f, %.1f, %.1f | Chunk: (%d, %d) | Hand: %s\n"
			% [pos.x, pos.y, pos.z, chunk_coord.x, chunk_coord.y, held_name]
			+ "[Hold LMB] Mine  [RMB] Place/Use Station  [E] Inventory (2x2)  [1-9] Hotbar  [F] Fly  [F6] Save"
		)


func _bind_references() -> void:
	_player = get_tree().get_first_node_in_group("player") as PlayerController
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	_day_night = get_tree().get_first_node_in_group("day_night_cycle") as DayNightCycle
	_inventory = get_tree().get_first_node_in_group("inventory_manager") as InventoryManager

	if _world_manager != null:
		_world_manager.world_saved.connect(_on_world_saved)

	if _inventory != null:
		_inventory.inventory_updated.connect(_refresh_all_slot_visuals)
		_inventory.furnace_updated.connect(_refresh_furnace_visuals)

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

	_refresh_all_slot_visuals()


func _on_world_saved(saved_chunk_count: int) -> void:
	_save_toast_timer = 2.5
	if _pause_status_label != null:
		_pause_status_label.text = "Saved %d modified chunk(s) to disk!" % saved_chunk_count


func _on_loot_notification(message: String) -> void:
	if _loot_label != null:
		_loot_label.text = message
		_loot_label.visible = true
		_loot_toast_timer = 2.4


func _on_mining_progress_changed(progress: float, target_name: String, can_harvest: bool) -> void:
	if _mining_bar_holder == null:
		return
	if progress <= 0.001:
		_mining_bar_holder.visible = false
		return
	_mining_bar_holder.visible = true
	_mining_fill.size.x = 130.0 * clampf(progress, 0.0, 1.0)
	if can_harvest:
		_mining_fill.color = Color(0.42, 0.92, 0.36, 0.96)
		_mining_label.text = "Mining %s (%d%%)" % [target_name, int(round(progress * 100.0))]
	else:
		_mining_fill.color = Color(0.95, 0.24, 0.20, 0.96)
		_mining_label.text = "%s (Need Pickaxe! %d%%)" % [target_name, int(round(progress * 100.0))]


func _on_station_opened(station_block_id: int) -> void:
	if _modal_mode != ModalMode.NONE:
		_close_modal()
		return

	if station_block_id == BlockRegistry.BlockId.CRAFTING_TABLE:
		_modal_mode = ModalMode.CRAFTING_TABLE_3X3
		if _inventory != null:
			_inventory.set_crafting_grid_dimension(3)
		_modal_title_label.text = "CRAFTING TABLE (3x3 WORKBENCH)"
		_modal_feedback_label.text = "Left-Click to pick/place stack | Right-Click to place 1 item per cell"
	elif station_block_id == BlockRegistry.BlockId.FURNACE:
		_modal_mode = ModalMode.FURNACE_OVEN
		_modal_title_label.text = "FURNACE (OVEN SMELTING)"
		_modal_feedback_label.text = "Place Ore in Top Slot + Coal/Wood in Bottom Fuel Slot to smelt ingots!"
	else:
		_modal_mode = ModalMode.PLAYER_INV_2X2
		if _inventory != null:
			_inventory.set_crafting_grid_dimension(2)
		_modal_title_label.text = "PLAYER INVENTORY (2x2 CRAFTING)"
		_modal_feedback_label.text = "Punch Wood -> Place in 2x2 Grid -> Craft Planks, Sticks & Crafting Table!"

	_craft_2x2_container.visible = (_modal_mode == ModalMode.PLAYER_INV_2X2)
	_craft_3x3_container.visible = (_modal_mode == ModalMode.CRAFTING_TABLE_3X3)
	_furnace_container.visible = (_modal_mode == ModalMode.FURNACE_OVEN)
	_rebuild_recipe_book_buttons()
	_refresh_all_slot_visuals()
	_refresh_furnace_visuals()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_modal() -> void:
	if _inventory != null:
		_inventory.return_crafting_grid_to_inventory()
	_modal_mode = ModalMode.NONE
	if _cursor_float != null:
		_cursor_float.visible = false
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

	_mining_bar_holder = Control.new()
	_mining_bar_holder.position = Vector2(-55, 28)
	_mining_bar_holder.visible = false
	_mining_bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_holder.add_child(_mining_bar_holder)

	var bar_bg := ColorRect.new()
	bar_bg.size = Vector2(134, 10)
	bar_bg.position = Vector2(-2, -2)
	bar_bg.color = Color(0.08, 0.08, 0.10, 0.88)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_bar_holder.add_child(bar_bg)

	_mining_fill = ColorRect.new()
	_mining_fill.size = Vector2(0, 6)
	_mining_fill.color = Color(0.42, 0.92, 0.36, 0.96)
	_mining_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mining_bar_holder.add_child(_mining_fill)

	_mining_label = Label.new()
	_mining_label.position = Vector2(-30, 10)
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

	_loot_label = Label.new()
	_loot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loot_label.add_theme_font_size_override("font_size", 14)
	_loot_label.add_theme_color_override("font_color", Color(0.98, 0.92, 0.35))
	_loot_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_loot_label.add_theme_constant_override("shadow_offset_x", 1)
	_loot_label.add_theme_constant_override("shadow_offset_y", 1)
	_loot_label.visible = false
	root_vbox.add_child(_loot_label)

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

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 5)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(hbox)

	for i in range(InventoryManager.HOTBAR_SIZE):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(60, 60)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(vbox)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(24, 24)
		swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		swatch.color = InventoryManager.get_item_color(0)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(swatch)

		var label := Label.new()
		label.text = "%d:Empty" % [i + 1]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 10)
		vbox.add_child(label)

		hbox.add_child(panel)
		_hotbar_panels.append(panel)
		_hotbar_swatches.append(swatch)
		_hotbar_labels.append(label)

	_update_hotbar_visuals(0)


# ============================================================================
# AUTHENTIC MINECRAFT INVENTORY (2x2), CRAFTING TABLE (3x3), & FURNACE UI
# ============================================================================

func _build_minecraft_modal() -> void:
	_modal_overlay = ColorRect.new()
	_modal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_overlay.color = Color(0.03, 0.04, 0.06, 0.74)
	_modal_overlay.visible = false
	add_child(_modal_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_overlay.add_child(center)

	var outer_hbox := HBoxContainer.new()
	outer_hbox.add_theme_constant_override("separation", 12)
	center.add_child(outer_hbox)

	# 1. Left Sidebar: Minecraft Recipe Book Helper (Auto-places patterns into the grid)
	var book_panel := PanelContainer.new()
	book_panel.custom_minimum_size = Vector2(230, 470)
	var book_style := StyleBoxFlat.new()
	book_style.bg_color = Color(0.14, 0.17, 0.15, 0.97)
	book_style.border_color = Color(0.36, 0.74, 0.38, 1.0)
	book_style.set_border_width_all(2)
	book_style.set_corner_radius_all(6)
	book_style.set_content_margin_all(12)
	book_panel.add_theme_stylebox_override("panel", book_style)
	outer_hbox.add_child(book_panel)

	var book_outer_vbox := VBoxContainer.new()
	book_outer_vbox.add_theme_constant_override("separation", 6)
	book_panel.add_child(book_outer_vbox)

	var book_title := Label.new()
	book_title.text = "RECIPE BOOK (CLICK TO FILL)"
	book_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	book_title.add_theme_font_size_override("font_size", 13)
	book_title.add_theme_color_override("font_color", Color(0.55, 0.95, 0.58))
	book_outer_vbox.add_child(book_title)

	_recipe_book_vbox = VBoxContainer.new()
	_recipe_book_vbox.add_theme_constant_override("separation", 5)
	book_outer_vbox.add_child(_recipe_book_vbox)

	# 2. Main Minecraft Inventory & Station Window
	var main_card := PanelContainer.new()
	main_card.custom_minimum_size = Vector2(560, 470)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.20, 0.21, 0.24, 0.98)
	card_style.border_color = Color(0.68, 0.70, 0.74, 1.0)
	card_style.set_border_width_all(3)
	card_style.set_corner_radius_all(6)
	card_style.set_content_margin_all(16)
	main_card.add_theme_stylebox_override("panel", card_style)
	outer_hbox.add_child(main_card)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	main_card.add_child(main_vbox)

	_modal_title_label = Label.new()
	_modal_title_label.text = "PLAYER INVENTORY (2x2 CRAFTING)"
	_modal_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_title_label.add_theme_font_size_override("font_size", 18)
	main_vbox.add_child(_modal_title_label)

	_modal_feedback_label = Label.new()
	_modal_feedback_label.text = "Left-Click: Pick/Place Stack | Right-Click: Place 1 Item"
	_modal_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_feedback_label.add_theme_font_size_override("font_size", 12)
	_modal_feedback_label.add_theme_color_override("font_color", Color(0.96, 0.86, 0.36))
	main_vbox.add_child(_modal_feedback_label)

	# Top Station Area (Holds 2x2 Crafting, 3x3 Crafting Table, or Furnace Oven)
	var station_holder := CenterContainer.new()
	station_holder.custom_minimum_size = Vector2(0, 165)
	main_vbox.add_child(station_holder)

	_craft_2x2_container = _build_2x2_crafting_view()
	station_holder.add_child(_craft_2x2_container)

	_craft_3x3_container = _build_3x3_crafting_view()
	station_holder.add_child(_craft_3x3_container)

	_furnace_container = _build_furnace_oven_view()
	station_holder.add_child(_furnace_container)

	# Middle Area: 27-Slot Main Backpack (3 rows of 9 slots: indices 9..35)
	var bp_label := Label.new()
	bp_label.text = "Inventory Backpack (27 Slots)"
	bp_label.add_theme_font_size_override("font_size", 12)
	bp_label.add_theme_color_override("font_color", Color(0.80, 0.82, 0.86))
	main_vbox.add_child(bp_label)

	_inv_modal_slots.resize(InventoryManager.TOTAL_SLOTS)

	var bp_grid := GridContainer.new()
	bp_grid.columns = 9
	bp_grid.add_theme_constant_override("h_separation", 5)
	bp_grid.add_theme_constant_override("v_separation", 5)
	bp_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_vbox.add_child(bp_grid)

	for slot_idx in range(9, InventoryManager.TOTAL_SLOTS):
		var slot_ui: Dictionary = _create_interactive_slot_widget(50, 50, func(btn: int) -> void:
			if _inventory != null:
				_inventory.click_inventory_slot(slot_idx, btn)
		)
		bp_grid.add_child(slot_ui["panel"])
		_inv_modal_slots[slot_idx] = slot_ui

	# Bottom Area: 9-Slot Hotbar inside Modal (indices 0..8)
	var hb_label := Label.new()
	hb_label.text = "Hotbar (Slots 1-9)"
	hb_label.add_theme_font_size_override("font_size", 12)
	hb_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	main_vbox.add_child(hb_label)

	var hb_grid := GridContainer.new()
	hb_grid.columns = 9
	hb_grid.add_theme_constant_override("h_separation", 5)
	hb_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_vbox.add_child(hb_grid)

	for slot_idx in range(0, InventoryManager.HOTBAR_SIZE):
		var slot_ui: Dictionary = _create_interactive_slot_widget(50, 50, func(btn: int) -> void:
			if _inventory != null:
				_inventory.click_inventory_slot(slot_idx, btn)
		)
		hb_grid.add_child(slot_ui["panel"])
		_inv_modal_slots[slot_idx] = slot_ui


func _build_2x2_crafting_view() -> Control:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	hbox.add_child(grid)

	for i in range(4):
		var cell_idx: int = i
		var slot_ui: Dictionary = _create_interactive_slot_widget(52, 52, func(btn: int) -> void:
			if _inventory != null:
				_inventory.click_craft_grid_slot(cell_idx, btn)
		)
		grid.add_child(slot_ui["panel"])
		_grid_2x2_slots.append(slot_ui)

	var arrow := Label.new()
	arrow.text = "  ===>  "
	arrow.add_theme_font_size_override("font_size", 20)
	hbox.add_child(arrow)

	_out_2x2_slot = _create_interactive_slot_widget(62, 62, func(_btn: int) -> void:
		if _inventory != null:
			_inventory.click_craft_output_slot()
	, true)
	hbox.add_child(_out_2x2_slot["panel"])
	return hbox


func _build_3x3_crafting_view() -> Control:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	hbox.add_child(grid)

	for i in range(9):
		var cell_idx: int = i
		var slot_ui: Dictionary = _create_interactive_slot_widget(48, 48, func(btn: int) -> void:
			if _inventory != null:
				_inventory.click_craft_grid_slot(cell_idx, btn)
		)
		grid.add_child(slot_ui["panel"])
		_grid_3x3_slots.append(slot_ui)

	var arrow := Label.new()
	arrow.text = "  ===>  "
	arrow.add_theme_font_size_override("font_size", 20)
	hbox.add_child(arrow)

	_out_3x3_slot = _create_interactive_slot_widget(64, 64, func(_btn: int) -> void:
		if _inventory != null:
			_inventory.click_craft_output_slot()
	, true)
	hbox.add_child(_out_3x3_slot["panel"])
	return hbox


func _build_furnace_oven_view() -> Control:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 22)

	var left_vbox := VBoxContainer.new()
	left_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	left_vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(left_vbox)

	# Furnace Top Input Slot (Ore)
	_furnace_in_slot = _create_interactive_slot_widget(52, 52, func(btn: int) -> void:
		if _inventory != null:
			_inventory.click_furnace_slot(0, btn)
	)
	left_vbox.add_child(_furnace_in_slot["panel"])

	# Flame burn meter
	var flame_bg := PanelContainer.new()
	flame_bg.custom_minimum_size = Vector2(52, 14)
	var f_style := StyleBoxFlat.new()
	f_style.bg_color = Color(0.10, 0.10, 0.12)
	flame_bg.add_theme_stylebox_override("panel", f_style)
	left_vbox.add_child(flame_bg)

	_furnace_flame_bar = ColorRect.new()
	_furnace_flame_bar.custom_minimum_size = Vector2(0, 12)
	_furnace_flame_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_furnace_flame_bar.color = Color(1.0, 0.52, 0.12)
	flame_bg.add_child(_furnace_flame_bar)

	# Furnace Bottom Fuel Slot (Coal / Wood)
	_furnace_fuel_slot = _create_interactive_slot_widget(52, 52, func(btn: int) -> void:
		if _inventory != null:
			_inventory.click_furnace_slot(1, btn)
	)
	left_vbox.add_child(_furnace_fuel_slot["panel"])

	# Middle Smelting Progress Bar
	var mid_vbox := VBoxContainer.new()
	mid_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(mid_vbox)

	var smelt_lbl := Label.new()
	smelt_lbl.text = "SMELTING"
	smelt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	smelt_lbl.add_theme_font_size_override("font_size", 11)
	mid_vbox.add_child(smelt_lbl)

	var prog_bg := ColorRect.new()
	prog_bg.custom_minimum_size = Vector2(90, 16)
	prog_bg.color = Color(0.10, 0.10, 0.12)
	mid_vbox.add_child(prog_bg)

	_furnace_progress_bar = ColorRect.new()
	_furnace_progress_bar.size = Vector2(0, 16)
	_furnace_progress_bar.color = Color(0.98, 0.82, 0.22)
	prog_bg.add_child(_furnace_progress_bar)

	# Right Furnace Output Slot
	_furnace_out_slot = _create_interactive_slot_widget(64, 64, func(btn: int) -> void:
		if _inventory != null:
			_inventory.click_furnace_slot(2, btn)
	, true)
	hbox.add_child(_furnace_out_slot["panel"])
	return hbox


func _create_interactive_slot_widget(w: float, h: float, on_click: Callable, is_output: bool = false) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, h)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.16, 0.96)
	style.border_color = Color(0.95, 0.78, 0.25, 0.95) if is_output else Color(0.38, 0.40, 0.44, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(20, 20)
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	swatch.color = InventoryManager.get_item_color(0)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(swatch)

	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(label)

	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
				on_click.call(event.button_index)
	)

	return {
		"panel": panel,
		"swatch": swatch,
		"label": label,
	}


func _rebuild_recipe_book_buttons() -> void:
	if _recipe_book_vbox == null:
		return
	for child in _recipe_book_vbox.get_children():
		child.queue_free()

	var recipes: Array[Array] = [
		["planks", "4x Planks (1 Wood Log)"],
		["sticks", "4x Sticks (2 Planks)"],
		["crafting_table", "Crafting Table (4 Planks)"],
		["glowstone", "4x Torches (1 Coal + 1 Stick)"],
		["wood_pickaxe", "[3x3] Wood Pick (3 Plank+2 Stick)"],
		["wood_axe", "[3x3] Wood Axe (3 Plank+2 Stick)"],
		["wood_shovel", "[3x3] Wood Shovel (1 Plank+2 Stick)"],
		["furnace", "[3x3] Furnace Oven (8 Cobble)"],
		["stone_pickaxe", "[3x3] Stone Pick (3 Cobble+2 Stick)"],
		["stone_axe", "[3x3] Stone Axe (3 Cobble+2 Stick)"],
		["iron_pickaxe", "[3x3] Iron Pick (3 Iron+2 Stick)"],
		["diamond_pickaxe", "[3x3] Diamond Pick (3 Diam+2 Stick)"],
	]

	for rec in recipes:
		var r_key: String = rec[0]
		var btn := Button.new()
		btn.text = rec[1]
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(func() -> void:
			if _inventory != null:
				var msg: String = _inventory.autofill_recipe_pattern(r_key)
				_modal_feedback_label.text = msg
		)
		_recipe_book_vbox.add_child(btn)


func _build_floating_cursor_item() -> void:
	_cursor_float = PanelContainer.new()
	_cursor_float.custom_minimum_size = Vector2(46, 46)
	_cursor_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_float.visible = false
	_cursor_float.z_index = 100

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.20, 0.26, 0.92)
	style.border_color = Color(1.0, 0.90, 0.30, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	_cursor_float.add_theme_stylebox_override("panel", style)
	add_child(_cursor_float)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_float.add_child(vbox)

	_cursor_swatch = ColorRect.new()
	_cursor_swatch.custom_minimum_size = Vector2(18, 18)
	_cursor_swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cursor_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_cursor_swatch)

	_cursor_label = Label.new()
	_cursor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cursor_label.add_theme_font_size_override("font_size", 10)
	_cursor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_cursor_label)


func _refresh_all_slot_visuals() -> void:
	if _inventory == null:
		return

	# 1. Refresh bottom HUD 9-slot hotbar
	for i in range(InventoryManager.HOTBAR_SIZE):
		var slot_data: Dictionary = _inventory.slots[i]
		var id: int = int(slot_data.get("id", 0))
		var cnt: int = int(slot_data.get("count", 0))
		_hotbar_swatches[i].color = InventoryManager.get_item_color(id)
		if id == 0 or cnt <= 0:
			_hotbar_labels[i].text = "%d:---" % [i + 1]
		elif InventoryManager.is_tool(id):
			_hotbar_labels[i].text = "%d:%s" % [i + 1, InventoryManager.get_item_short_label(id)]
		else:
			_hotbar_labels[i].text = "%d:%s\nx%d" % [i + 1, InventoryManager.get_item_short_label(id), cnt]

	# 2. Refresh all 36 modal inventory slots
	for i in range(mini(_inv_modal_slots.size(), _inventory.slots.size())):
		_paint_slot_widget(_inv_modal_slots[i], _inventory.slots[i])

	# 3. Refresh active 2x2 or 3x3 crafting grid & output
	if _inventory.craft_grid_size == 2:
		for i in range(mini(4, _inventory.craft_grid.size())):
			_paint_slot_widget(_grid_2x2_slots[i], _inventory.craft_grid[i])
		_paint_slot_widget(_out_2x2_slot, _inventory.craft_output)
	else:
		for i in range(mini(9, _inventory.craft_grid.size())):
			_paint_slot_widget(_grid_3x3_slots[i], _inventory.craft_grid[i])
		_paint_slot_widget(_out_3x3_slot, _inventory.craft_output)


func _refresh_furnace_visuals() -> void:
	if _inventory == null or _furnace_in_slot.is_empty():
		return
	_paint_slot_widget(_furnace_in_slot, _inventory.furnace_input)
	_paint_slot_widget(_furnace_fuel_slot, _inventory.furnace_fuel)
	_paint_slot_widget(_furnace_out_slot, _inventory.furnace_output)

	var burn_ratio: float = 0.0
	if _inventory.furnace_burn_max > 0.0:
		burn_ratio = clampf(_inventory.furnace_burn_remaining / _inventory.furnace_burn_max, 0.0, 1.0)
	_furnace_flame_bar.custom_minimum_size.x = 50.0 * burn_ratio
	_furnace_progress_bar.size.x = 90.0 * clampf(_inventory.furnace_cook_progress, 0.0, 1.0)


func _paint_slot_widget(widget: Dictionary, slot_data: Dictionary) -> void:
	if widget.is_empty():
		return
	var id: int = int(slot_data.get("id", 0))
	var cnt: int = int(slot_data.get("count", 0))
	var swatch: ColorRect = widget["swatch"]
	var label: Label = widget["label"]
	swatch.color = InventoryManager.get_item_color(id)
	if id == 0 or cnt <= 0:
		label.text = ""
	elif InventoryManager.is_tool(id):
		label.text = InventoryManager.get_item_short_label(id)
	else:
		label.text = "%s\nx%d" % [InventoryManager.get_item_short_label(id), cnt]


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


func _update_hotbar_visuals(active_slot: int) -> void:
	for i in range(_hotbar_panels.size()):
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
		_hotbar_panels[i].add_theme_stylebox_override("panel", style)
