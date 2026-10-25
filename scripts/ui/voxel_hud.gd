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
	CHEST_27 = 4,
}

var _player: PlayerController = null
var _world_manager: WorldManager = null
var _day_night: DayNightCycle = null
var _interactor: BlockInteractor = null
var _inventory: InventoryManager = null

# Bottom HUD widgets
var _hotbar_panels: Array[PanelContainer] = []
var _hotbar_icons: Array[TextureRect] = []
var _hotbar_swatches: Array[ColorRect] = []
var _hotbar_labels: Array[Label] = []
var _hotbar_dur_bars: Array[ColorRect] = []
var _heart_icons: Array[TextureRect] = []
var _hunger_icons: Array[TextureRect] = []
var _oxygen_icons: Array[TextureRect] = []
var _oxygen_hbox: HBoxContainer = null

# Cached Blender 5.2 UI & HUD Textures
var _tex_panel_bg: Texture2D = null
var _tex_slot_normal: Texture2D = null
var _tex_slot_selected: Texture2D = null
var _tex_slot_output: Texture2D = null
var _tex_heart_full: Texture2D = null
var _tex_heart_half: Texture2D = null
var _tex_heart_empty: Texture2D = null
var _tex_hunger_full: Texture2D = null
var _tex_hunger_half: Texture2D = null
var _tex_hunger_empty: Texture2D = null
var _tex_bubble_full: Texture2D = null
var _tex_bubble_empty: Texture2D = null

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
var _chest_container: Control = null
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
var _chest_modal_slots: Array[Dictionary] = [] # 27 slots for world Chests
var _inv_modal_slots: Array[Dictionary] = [] # 36 slots (9..35 backpack, 0..8 hotbar)

# Floating mouse cursor item stack
var _cursor_float: PanelContainer = null
var _cursor_icon: TextureRect = null
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
	_load_blender_ui_textures()
	_build_screen_tints()
	_build_crosshair_and_mining_bar()
	_build_bottom_hud()
	_build_debug_overlay()
	_build_minecraft_modal()
	_build_floating_cursor_item()
	_build_pause_menu()
	call_deferred("_bind_references")


func _load_blender_ui_textures() -> void:
	_tex_panel_bg = InventoryManager.load_ui_texture("res://assets/ui/gui_panels/panel_bg.png")
	_tex_slot_normal = InventoryManager.load_ui_texture("res://assets/ui/gui_panels/slot_normal.png")
	_tex_slot_selected = InventoryManager.load_ui_texture("res://assets/ui/gui_panels/slot_selected.png")
	_tex_slot_output = InventoryManager.load_ui_texture("res://assets/ui/gui_panels/slot_output.png")
	_tex_heart_full = InventoryManager.load_ui_texture("res://assets/ui/hud_icons/heart_full.png")
	_tex_heart_half = InventoryManager.load_ui_texture("res://assets/ui/hud_icons/heart_half.png")
	_tex_heart_empty = InventoryManager.load_ui_texture("res://assets/ui/hud_icons/heart_empty.png")
	_tex_hunger_full = InventoryManager.load_ui_texture("res://assets/ui/hud_icons/hunger_full.png")
	_tex_hunger_half = InventoryManager.load_ui_texture("res://assets/ui/hud_icons/hunger_half.png")
	_tex_hunger_empty = InventoryManager.load_ui_texture("res://assets/ui/hud_icons/hunger_empty.png")
	_tex_bubble_full = InventoryManager.load_ui_texture("res://assets/ui/hud_icons/bubble_full.png")
	_tex_bubble_empty = InventoryManager.load_ui_texture("res://assets/ui/hud_icons/bubble_empty.png")


## Loads a PNG UI texture (Faithful 64x HUD/GUI assets) via the shared InventoryManager cache.
func _load_png_texture(res_path: String) -> Texture2D:
	return InventoryManager.load_ui_texture(res_path)


func _make_blender_stylebox(tex: Texture2D, margin: float = 6.0, fallback_bg := Color(0.16, 0.17, 0.20, 0.96)) -> StyleBox:
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = margin
		sb.texture_margin_right = margin
		sb.texture_margin_top = margin
		sb.texture_margin_bottom = margin
		return sb
	var flat := StyleBoxFlat.new()
	flat.bg_color = fallback_bg
	flat.border_color = Color(0.55, 0.57, 0.62, 0.95)
	flat.set_border_width_all(2)
	flat.set_corner_radius_all(4)
	return flat


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
		if _oxygen_hbox != null:
			_oxygen_hbox.visible = _player.is_head_underwater or (_player.current_oxygen < _player.max_oxygen)

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
			var icon_tex: Texture2D = InventoryManager.get_item_icon_texture(cid)
			if _cursor_icon != null and icon_tex != null:
				_cursor_icon.texture = icon_tex
				_cursor_icon.visible = true
				_cursor_swatch.visible = false
			else:
				if _cursor_icon != null:
					_cursor_icon.visible = false
				_cursor_swatch.visible = true
				_cursor_swatch.color = InventoryManager.get_item_color(cid)
			_cursor_label.text = str(ccnt) if ccnt > 1 else ""
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
		_player.hunger_changed.connect(_on_hunger_changed)
		_player.oxygen_changed.connect(_on_oxygen_changed)
		_player.player_damaged.connect(_on_player_damaged)
		if _player.has_signal("player_respawned"):
			_player.connect("player_respawned", _on_player_respawned)
		_on_health_changed(_player.current_health, _player.max_health)
		_on_hunger_changed(_player.current_hunger, _player.max_hunger)
		_on_oxygen_changed(_player.current_oxygen, _player.max_oxygen)

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


func _on_player_respawned(at_bed: bool) -> void:
	if at_bed:
		_on_loot_notification("YOU DIED! Respawned at your bed.")
	else:
		_on_loot_notification("YOU DIED! Respawned at world spawn.")


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
		_modal_feedback_label.text = "Place Ore/Meat in Top Slot + Coal/Wood in Bottom Fuel Slot to smelt/cook!"
	elif station_block_id == BlockRegistry.BlockId.CHEST:
		_modal_mode = ModalMode.CHEST_27
		_modal_title_label.text = "WOODEN CHEST (27-SLOT WORLD STORAGE)"
		_modal_feedback_label.text = "Store items in this Chest! Contents stay at this block position."
	else:
		_modal_mode = ModalMode.PLAYER_INV_2X2
		if _inventory != null:
			_inventory.set_crafting_grid_dimension(2)
		_modal_title_label.text = "PLAYER INVENTORY (2x2 CRAFTING)"
		_modal_feedback_label.text = "Punch Wood -> Place in 2x2 Grid -> Craft Planks, Sticks & Crafting Table!"

	_craft_2x2_container.visible = (_modal_mode == ModalMode.PLAYER_INV_2X2)
	_craft_3x3_container.visible = (_modal_mode == ModalMode.CRAFTING_TABLE_3X3)
	_furnace_container.visible = (_modal_mode == ModalMode.FURNACE_OVEN)
	if _chest_container != null:
		_chest_container.visible = (_modal_mode == ModalMode.CHEST_27)
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
	for i in range(_heart_icons.size()):
		var heart_hp: int = current_hp - (i * 2)
		if is_creative:
			_heart_icons[i].texture = _tex_heart_full
			_heart_icons[i].modulate = Color(0.45, 0.90, 1.0, 1.0)
		elif heart_hp >= 2:
			_heart_icons[i].texture = _tex_heart_full
			_heart_icons[i].modulate = Color(1, 1, 1, 1)
		elif heart_hp == 1:
			_heart_icons[i].texture = _tex_heart_half
			_heart_icons[i].modulate = Color(1, 1, 1, 1)
		else:
			_heart_icons[i].texture = _tex_heart_empty
			_heart_icons[i].modulate = Color(1, 1, 1, 0.92)


func _on_hunger_changed(current_hunger: int, _max_hunger: int) -> void:
	var is_creative: bool = _player != null and _player.is_flying
	for i in range(_hunger_icons.size()):
		var food_pts: int = current_hunger - (i * 2)
		if is_creative or food_pts >= 2:
			_hunger_icons[i].texture = _tex_hunger_full
			_hunger_icons[i].modulate = Color(1, 1, 1, 1)
		elif food_pts == 1:
			_hunger_icons[i].texture = _tex_hunger_half
			_hunger_icons[i].modulate = Color(1, 1, 1, 1)
		else:
			_hunger_icons[i].texture = _tex_hunger_empty
			_hunger_icons[i].modulate = Color(1, 1, 1, 0.92)


func _on_oxygen_changed(current_oxygen: int, max_oxygen: int) -> void:
	if _oxygen_hbox != null:
		_oxygen_hbox.visible = (_player != null and _player.is_head_underwater) or (current_oxygen < max_oxygen)
	for i in range(_oxygen_icons.size()):
		if i < current_oxygen:
			_oxygen_icons[i].texture = _tex_bubble_full
			_oxygen_icons[i].modulate = Color(1, 1, 1, 1)
		else:
			_oxygen_icons[i].texture = _tex_bubble_empty
			_oxygen_icons[i].modulate = Color(1, 1, 1, 0.72)


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

	var crosshair_tex: Texture2D = _load_png_texture("res://assets/ui/hud_icons/crosshair.png")
	if crosshair_tex != null:
		var ch_rect := TextureRect.new()
		ch_rect.position = Vector2(-1, -1)
		ch_rect.size = Vector2(22, 22)
		ch_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ch_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ch_rect.texture = crosshair_tex
		ch_rect.modulate = Color(1, 1, 1, 0.90)
		ch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair_holder.add_child(ch_rect)
	else:
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

	# Underwater Oxygen Bubbles Bar (10 Blender-Rendered 3D Bubbles)
	_oxygen_hbox = HBoxContainer.new()
	_oxygen_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_oxygen_hbox.add_theme_constant_override("separation", 3)
	_oxygen_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_oxygen_hbox.visible = false
	root_vbox.add_child(_oxygen_hbox)

	for i in range(10):
		var b_icon := TextureRect.new()
		b_icon.custom_minimum_size = Vector2(18, 18)
		b_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		b_icon.texture = _tex_bubble_full
		b_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_oxygen_hbox.add_child(b_icon)
		_oxygen_icons.append(b_icon)

	# Status Row: Left = 10 Blender 3D Hearts | Right = 10 Blender 3D Hunger Drumsticks
	var vitals_row := HBoxContainer.new()
	vitals_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vitals_row.add_theme_constant_override("separation", 64)
	vitals_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(vitals_row)

	var hearts_hbox := HBoxContainer.new()
	hearts_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hearts_hbox.add_theme_constant_override("separation", 2)
	hearts_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals_row.add_child(hearts_hbox)

	for i in range(HEART_COUNT):
		var h_icon := TextureRect.new()
		h_icon.custom_minimum_size = Vector2(20, 20)
		h_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		h_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h_icon.texture = _tex_heart_full
		h_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hearts_hbox.add_child(h_icon)
		_heart_icons.append(h_icon)

	var hunger_hbox := HBoxContainer.new()
	hunger_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hunger_hbox.add_theme_constant_override("separation", 2)
	hunger_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals_row.add_child(hunger_hbox)

	for i in range(HEART_COUNT):
		var f_icon := TextureRect.new()
		f_icon.custom_minimum_size = Vector2(20, 20)
		f_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		f_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		f_icon.texture = _tex_hunger_full
		f_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hunger_hbox.add_child(f_icon)
		_hunger_icons.append(f_icon)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(hbox)

	for i in range(InventoryManager.HOTBAR_SIZE):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(58, 58)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_theme_constant_override("separation", 1)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(vbox)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(34, 34)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(icon_rect)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		swatch.color = InventoryManager.get_item_color(0)
		swatch.visible = false
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(swatch)

		var label := Label.new()
		label.text = ""
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		vbox.add_child(label)

		var dur_bar := ColorRect.new()
		dur_bar.custom_minimum_size = Vector2(44, 3)
		dur_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		dur_bar.color = Color(0.2, 0.95, 0.25)
		dur_bar.visible = false
		dur_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(dur_bar)

		hbox.add_child(panel)
		_hotbar_panels.append(panel)
		_hotbar_icons.append(icon_rect)
		_hotbar_swatches.append(swatch)
		_hotbar_labels.append(label)
		_hotbar_dur_bars.append(dur_bar)

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

	# 1. Left Sidebar: Minecraft Recipe Book Helper (Blender 3D Beveled Panel)
	var book_panel := PanelContainer.new()
	book_panel.custom_minimum_size = Vector2(235, 480)
	var book_style := _make_blender_stylebox(_tex_panel_bg, 10.0)
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

	var book_scroll := ScrollContainer.new()
	book_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	book_scroll.custom_minimum_size = Vector2(205, 410)
	book_outer_vbox.add_child(book_scroll)

	_recipe_book_vbox = VBoxContainer.new()
	_recipe_book_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_book_vbox.add_theme_constant_override("separation", 5)
	book_scroll.add_child(_recipe_book_vbox)

	# 2. Main Minecraft Inventory & Station Window (Blender 3D Beveled Stone Panel)
	var main_card := PanelContainer.new()
	main_card.custom_minimum_size = Vector2(560, 480)
	var card_style := _make_blender_stylebox(_tex_panel_bg, 12.0)
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
	_modal_feedback_label.text = "Left-Click: Stack | Right-Click: 1 Item | Shift+Click: Quick Transfer"
	_modal_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal_feedback_label.add_theme_font_size_override("font_size", 12)
	_modal_feedback_label.add_theme_color_override("font_color", Color(0.96, 0.86, 0.36))
	main_vbox.add_child(_modal_feedback_label)

	# Top Station Area (Holds 2x2 Crafting + Armor/Avatar, 3x3 Crafting Table, Furnace, or Chest)
	var station_holder := CenterContainer.new()
	station_holder.custom_minimum_size = Vector2(0, 168)
	main_vbox.add_child(station_holder)

	_craft_2x2_container = _build_2x2_crafting_view()
	station_holder.add_child(_craft_2x2_container)

	_craft_3x3_container = _build_3x3_crafting_view()
	station_holder.add_child(_craft_3x3_container)

	_furnace_container = _build_furnace_oven_view()
	station_holder.add_child(_furnace_container)

	_chest_container = _build_chest_storage_view()
	station_holder.add_child(_chest_container)

	# Middle Area: 27-Slot Main Backpack (3 rows of 9 slots: indices 9..35)
	var bp_label := Label.new()
	bp_label.text = "Inventory Backpack (27 Slots) — [Shift+Click] to Quick Move"
	bp_label.add_theme_font_size_override("font_size", 12)
	bp_label.add_theme_color_override("font_color", Color(0.86, 0.88, 0.92))
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
	hbox.add_theme_constant_override("separation", 18)

	# Left: 4 Armor Slots (Helmet, Chestplate, Leggings, Boots) + Player Character Preview Box
	var armor_vbox := GridContainer.new()
	armor_vbox.columns = 2
	armor_vbox.add_theme_constant_override("h_separation", 4)
	armor_vbox.add_theme_constant_override("v_separation", 4)
	var armor_icons: Array[String] = [
		"res://assets/ui/hud_icons/armor_helmet.png",
		"res://assets/ui/hud_icons/armor_chestplate.png",
		"res://assets/ui/hud_icons/armor_leggings.png",
		"res://assets/ui/hud_icons/armor_boots.png",
	]
	for armor_path in armor_icons:
		var a_panel := PanelContainer.new()
		a_panel.custom_minimum_size = Vector2(46, 46)
		a_panel.add_theme_stylebox_override("panel", _make_blender_stylebox(_tex_slot_normal, 5.0))
		var a_icon := TextureRect.new()
		a_icon.custom_minimum_size = Vector2(30, 30)
		a_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		a_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		a_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		a_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		a_icon.texture = _load_png_texture(armor_path)
		a_icon.modulate = Color(1, 1, 1, 0.78)
		a_panel.add_child(a_icon)
		armor_vbox.add_child(a_panel)
	hbox.add_child(armor_vbox)

	# Player Avatar Preview Box
	var avatar_box := PanelContainer.new()
	avatar_box.custom_minimum_size = Vector2(74, 96)
	avatar_box.add_theme_stylebox_override("panel", _make_blender_stylebox(_tex_slot_normal, 6.0))
	var av_vbox := VBoxContainer.new()
	av_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	av_vbox.add_theme_constant_override("separation", 2)
	avatar_box.add_child(av_vbox)

	var av_head := ColorRect.new()
	av_head.custom_minimum_size = Vector2(22, 22)
	av_head.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	av_head.color = Color(0.88, 0.68, 0.52)
	av_vbox.add_child(av_head)

	var av_torso := ColorRect.new()
	av_torso.custom_minimum_size = Vector2(26, 28)
	av_torso.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	av_torso.color = Color(0.18, 0.62, 0.74)
	av_vbox.add_child(av_torso)

	var av_legs := ColorRect.new()
	av_legs.custom_minimum_size = Vector2(20, 24)
	av_legs.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	av_legs.color = Color(0.24, 0.28, 0.58)
	av_vbox.add_child(av_legs)
	hbox.add_child(avatar_box)

	# Right: 2x2 Crafting Grid -> Output Slot
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
	arrow.text = " ===> "
	arrow.add_theme_font_size_override("font_size", 18)
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


func _build_chest_storage_view() -> Control:
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.visible = false
	_chest_modal_slots.resize(InventoryManager.CHEST_SIZE)
	for i in range(InventoryManager.CHEST_SIZE):
		var slot_ui: Dictionary = _create_interactive_slot_widget(46, 46, func(btn: int) -> void:
			if _inventory != null:
				_inventory.click_chest_slot(i, btn)
		)
		grid.add_child(slot_ui["panel"])
		_chest_modal_slots[i] = slot_ui
	return grid


func _create_interactive_slot_widget(w: float, h: float, on_click: Callable, is_output: bool = false) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, h)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var slot_tex: Texture2D = _tex_slot_output if is_output else _tex_slot_normal
	var style := _make_blender_stylebox(slot_tex, 6.0)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var icon_rect := TextureRect.new()
	var icon_sz: float = clampf(w - 14.0, 26.0, 42.0)
	icon_rect.custom_minimum_size = Vector2(icon_sz, icon_sz)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_rect)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(18, 18)
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	swatch.color = InventoryManager.get_item_color(0)
	swatch.visible = false
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(swatch)

	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(label)

	var dur_bar := ColorRect.new()
	dur_bar.custom_minimum_size = Vector2(38, 3)
	dur_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dur_bar.color = Color(0.2, 0.95, 0.25)
	dur_bar.visible = false
	dur_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(dur_bar)

	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
				on_click.call(event.button_index)
	)

	return {
		"panel": panel,
		"icon": icon_rect,
		"swatch": swatch,
		"label": label,
		"dur_bar": dur_bar,
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
		["chest", "[3x3] Chest (8 Planks Ring)"],
		["bed", "[3x3] Bed (3 Leaves/Snow+3 Plank)"],
		["door", "[3x3] 2x Wood Door (6 Planks)"],
		["ladder", "[3x3] 3x Ladder (7 Sticks H)"],
		["tnt", "TNT (2 Gunpowder/Coal+2 Sand)"],
		["wood_pickaxe", "[3x3] Wood Pick (3 Plank+2 Stick)"],
		["wood_sword", "[3x3] Wood Sword (2 Plank+1 Stick)"],
		["wood_axe", "[3x3] Wood Axe (3 Plank+2 Stick)"],
		["wood_shovel", "[3x3] Wood Shovel (1 Plank+2 Stick)"],
		["furnace", "[3x3] Furnace Oven (8 Cobble)"],
		["stone_pickaxe", "[3x3] Stone Pick (3 Cobble+2 Stick)"],
		["stone_sword", "[3x3] Stone Sword (2 Cobble+1 Stick)"],
		["stone_axe", "[3x3] Stone Axe (3 Cobble+2 Stick)"],
		["iron_pickaxe", "[3x3] Iron Pick (3 Iron+2 Stick)"],
		["iron_sword", "[3x3] Iron Sword (2 Iron+1 Stick)"],
		["bucket", "[3x3] Iron Bucket (3 Iron V-Shape)"],
		["diamond_pickaxe", "[3x3] Diamond Pick (3 Diam+2 Stick)"],
		["diamond_sword", "[3x3] Diamond Sword (2 Diam+1 Stick)"],
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

	var style := StyleBoxEmpty.new()
	_cursor_float.add_theme_stylebox_override("panel", style)
	add_child(_cursor_float)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_float.add_child(vbox)

	_cursor_icon = TextureRect.new()
	_cursor_icon.custom_minimum_size = Vector2(36, 36)
	_cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cursor_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_cursor_icon)

	_cursor_swatch = ColorRect.new()
	_cursor_swatch.custom_minimum_size = Vector2(18, 18)
	_cursor_swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cursor_swatch.visible = false
	_cursor_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_cursor_swatch)

	_cursor_label = Label.new()
	_cursor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cursor_label.add_theme_font_size_override("font_size", 11)
	_cursor_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	_cursor_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_cursor_label.add_theme_constant_override("shadow_offset_x", 1)
	_cursor_label.add_theme_constant_override("shadow_offset_y", 1)
	_cursor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_cursor_label)


func _refresh_all_slot_visuals() -> void:
	if _inventory == null:
		return

	# 1. Refresh bottom HUD 9-slot hotbar with Blender 3D Isometric Item Icons
	for i in range(InventoryManager.HOTBAR_SIZE):
		var slot_data: Dictionary = _inventory.slots[i]
		var id: int = int(slot_data.get("id", 0))
		var cnt: int = int(slot_data.get("count", 0))
		var icon_tex: Texture2D = InventoryManager.get_item_icon_texture(id)
		if id == 0 or cnt <= 0:
			_hotbar_icons[i].texture = null
			_hotbar_icons[i].visible = false
			_hotbar_swatches[i].visible = false
			_hotbar_labels[i].text = ""
			_hotbar_dur_bars[i].visible = false
		else:
			if icon_tex != null:
				_hotbar_icons[i].texture = icon_tex
				_hotbar_icons[i].visible = true
				_hotbar_swatches[i].visible = false
			else:
				_hotbar_icons[i].visible = false
				_hotbar_swatches[i].visible = true
				_hotbar_swatches[i].color = InventoryManager.get_item_color(id)

			if InventoryManager.is_tool_item(id):
				_hotbar_labels[i].text = ""
				_update_durability_bar(_hotbar_dur_bars[i], id, int(slot_data.get("durability", -1)), 44.0)
			else:
				_hotbar_labels[i].text = str(cnt) if cnt > 1 else ""
				_hotbar_dur_bars[i].visible = false

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

	# 4. Refresh active 27-slot Chest Storage
	var c_slots: Array = _inventory.get_active_chest_slots()
	for i in range(mini(_chest_modal_slots.size(), c_slots.size())):
		_paint_slot_widget(_chest_modal_slots[i], c_slots[i])


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
	var panel: PanelContainer = widget.get("panel", null) as PanelContainer
	var icon_rect: TextureRect = widget.get("icon", null) as TextureRect
	var swatch: ColorRect = widget["swatch"]
	var label: Label = widget["label"]
	var dur_bar: ColorRect = widget.get("dur_bar", null) as ColorRect

	if id == 0 or cnt <= 0:
		if panel != null:
			panel.tooltip_text = ""
		if icon_rect != null:
			icon_rect.texture = null
			icon_rect.visible = false
		swatch.visible = false
		label.text = ""
		if dur_bar != null:
			dur_bar.visible = false
		return

	if panel != null:
		panel.tooltip_text = InventoryManager.get_item_name(id)

	var icon_tex: Texture2D = InventoryManager.get_item_icon_texture(id)
	if icon_rect != null and icon_tex != null:
		icon_rect.texture = icon_tex
		icon_rect.visible = true
		swatch.visible = false
	else:
		if icon_rect != null:
			icon_rect.visible = false
		swatch.visible = true
		swatch.color = InventoryManager.get_item_color(id)

	if InventoryManager.is_tool_item(id):
		label.text = ""
		if dur_bar != null:
			_update_durability_bar(dur_bar, id, int(slot_data.get("durability", -1)), 38.0)
	else:
		label.text = str(cnt) if cnt > 1 else ""
		if dur_bar != null:
			dur_bar.visible = false


func _update_durability_bar(bar: ColorRect, item_id: int, cur_dur: int, max_width: float) -> void:
	var max_dur: int = InventoryManager.get_max_durability(item_id)
	if max_dur <= 0 or cur_dur < 0 or cur_dur >= max_dur:
		bar.visible = false
		return
	var ratio: float = clampf(float(cur_dur) / float(max_dur), 0.0, 1.0)
	bar.visible = true
	bar.custom_minimum_size.x = maxf(3.0, max_width * ratio)
	bar.color = Color(1.0 - ratio, ratio * 0.95, 0.15, 1.0)


func _build_debug_overlay() -> void:
	_debug_label = Label.new()
	_debug_label.position = Vector2(14, 12)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_debug_label.add_theme_constant_override("shadow_offset_x", 1)
	_debug_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_debug_label)


func _apply_faithful_button_style(btn: Button) -> void:
	var tex_normal: Texture2D = _load_png_texture("res://assets/ui/gui_panels/button.png")
	var tex_hover: Texture2D = _load_png_texture("res://assets/ui/gui_panels/button_highlighted.png")
	var tex_disabled: Texture2D = _load_png_texture("res://assets/ui/gui_panels/button_disabled.png")

	var sb_normal := StyleBoxTexture.new()
	sb_normal.texture = tex_normal
	sb_normal.texture_margin_left = 6.0
	sb_normal.texture_margin_right = 6.0
	sb_normal.texture_margin_top = 6.0
	sb_normal.texture_margin_bottom = 6.0
	sb_normal.set_content_margin_all(8.0)

	var sb_hover := StyleBoxTexture.new()
	sb_hover.texture = tex_hover
	sb_hover.texture_margin_left = 6.0
	sb_hover.texture_margin_right = 6.0
	sb_hover.texture_margin_top = 6.0
	sb_hover.texture_margin_bottom = 6.0
	sb_hover.set_content_margin_all(8.0)

	var sb_disabled := StyleBoxTexture.new()
	sb_disabled.texture = tex_disabled
	sb_disabled.texture_margin_left = 6.0
	sb_disabled.texture_margin_right = 6.0
	sb_disabled.texture_margin_top = 6.0
	sb_disabled.texture_margin_bottom = 6.0
	sb_disabled.set_content_margin_all(8.0)

	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	btn.add_theme_stylebox_override("focus", sb_hover)
	btn.add_theme_stylebox_override("disabled", sb_disabled)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 0.65, 1))
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)


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
	card.custom_minimum_size = Vector2(380, 420)
	var card_style := _make_blender_stylebox(_tex_panel_bg, 12.0)
	card_style.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
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
	resume_btn.text = "Back to Game (Esc)"
	resume_btn.custom_minimum_size = Vector2(0, 36)
	_apply_faithful_button_style(resume_btn)
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
	fly_btn.custom_minimum_size = Vector2(0, 32)
	_apply_faithful_button_style(fly_btn)
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
	time_btn.custom_minimum_size = Vector2(0, 32)
	_apply_faithful_button_style(time_btn)
	time_btn.pressed.connect(func() -> void:
		if _day_night != null:
			_day_night.advance_hours(2.5)
			_pause_status_label.text = "Time set to %s" % _day_night.get_formatted_time()
	)
	vbox.add_child(time_btn)

	var save_btn := Button.new()
	save_btn.text = "Save World to Disk (F6)"
	save_btn.custom_minimum_size = Vector2(0, 32)
	_apply_faithful_button_style(save_btn)
	save_btn.pressed.connect(func() -> void:
		if _world_manager != null:
			var count: int = _world_manager.save_complete_world()
			_on_world_saved(count)
	)
	vbox.add_child(save_btn)

	var title_btn := Button.new()
	title_btn.text = "Save & Quit to Title"
	title_btn.custom_minimum_size = Vector2(0, 32)
	_apply_faithful_button_style(title_btn)
	title_btn.pressed.connect(func() -> void:
		if _world_manager != null:
			_world_manager.save_complete_world()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	)
	vbox.add_child(title_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Save & Quit to Desktop"
	quit_btn.custom_minimum_size = Vector2(0, 32)
	_apply_faithful_button_style(quit_btn)
	quit_btn.pressed.connect(func() -> void:
		if _world_manager != null:
			_world_manager.save_complete_world()
		get_tree().quit()
	)
	vbox.add_child(quit_btn)


func _on_hotbar_slot_changed(slot_index: int, _item_id: int) -> void:
	_update_hotbar_visuals(slot_index)


func _update_hotbar_visuals(active_slot: int) -> void:
	for i in range(_hotbar_panels.size()):
		var tex: Texture2D = _tex_slot_selected if i == active_slot else _tex_slot_normal
		var style := _make_blender_stylebox(tex, 6.0)
		_hotbar_panels[i].add_theme_stylebox_override("panel", style)
