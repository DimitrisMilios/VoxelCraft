class_name VoxelHUD
extends CanvasLayer
## Retro HUD displaying center crosshair, 10-heart survival health bar,
## 9-slot block hotbar, debug status overlay, underwater/hurt tints, and Pause Menu (Esc).

const HEART_COUNT: int = 10

var _player: PlayerController = null
var _world_manager: WorldManager = null
var _day_night: DayNightCycle = null
var _interactor: BlockInteractor = null
var _slot_panels: Array[PanelContainer] = []
var _heart_rects: Array[ColorRect] = []
var _debug_label: Label = null
var _underwater_tint: ColorRect = null
var _damage_tint: ColorRect = null
var _pause_overlay: Control = null
var _render_dist_label: Label = null
var _pause_status_label: Label = null
var _save_toast_timer: float = 0.0
var _damage_flash_alpha: float = 0.0


func _ready() -> void:
	_build_screen_tints()
	_build_crosshair()
	_build_bottom_hud()
	_build_debug_overlay()
	_build_pause_menu()
	call_deferred("_bind_references")


func _process(delta: float) -> void:
	if _save_toast_timer > 0.0:
		_save_toast_timer = maxf(0.0, _save_toast_timer - delta)

	if _damage_flash_alpha > 0.0:
		_damage_flash_alpha = maxf(0.0, _damage_flash_alpha - delta * 1.8)
		if _damage_tint != null:
			_damage_tint.color.a = _damage_flash_alpha
			_damage_tint.visible = (_damage_flash_alpha > 0.01)

	if _underwater_tint != null and _player != null:
		_underwater_tint.visible = _player.is_head_underwater

	if _pause_overlay != null:
		_pause_overlay.visible = (Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED)

	if _debug_label != null and _player != null:
		var pos: Vector3 = _player.global_position
		var chunk_coord: Vector2i = WorldManager.world_to_chunk_coords(pos)
		var fps: int = Engine.get_frames_per_second()
		var block_name: String = "Grass"
		if _interactor != null:
			block_name = BlockRegistry.get_block_name(_interactor.get_selected_block_id())

		var active_chunks: int = _world_manager.get_active_chunk_count() if _world_manager != null else 0
		var modified_chunks: int = _world_manager.get_modified_chunk_count() if _world_manager != null else 0
		var time_str: String = _day_night.get_formatted_time() if _day_night != null else "Day 1 09:30"
		var mode_str: String = "FLY (CREATIVE)" if _player.is_flying else ("SWIM" if _player.is_in_water else "SURVIVAL")
		var save_status: String = " | [SAVED TO DISK!]" if _save_toast_timer > 0.0 else ""

		_debug_label.text = (
			"VoxelCraft 0.6 | %d FPS | %s | Mode: %s | HP: %d/%d | Chunks: %d (Saved: %d)%s\n"
			% [fps, time_str, mode_str, _player.current_health, _player.max_health, active_chunks, modified_chunks, save_status]
			+ "XYZ: %.1f, %.1f, %.1f | Chunk: (%d, %d) | Block: %s\n"
			% [pos.x, pos.y, pos.z, chunk_coord.x, chunk_coord.y, block_name]
			+ "[LMB] Break  [RMB] Place  [1-9/Scroll] Block  [F] Fly  [T] +Time  [F6] Save  [Esc] Menu"
		)


func _bind_references() -> void:
	_player = get_tree().get_first_node_in_group("player") as PlayerController
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	_day_night = get_tree().get_first_node_in_group("day_night_cycle") as DayNightCycle

	if _world_manager != null:
		_world_manager.world_saved.connect(_on_world_saved)

	if _player != null:
		_player.health_changed.connect(_on_health_changed)
		_player.player_damaged.connect(_on_player_damaged)
		_on_health_changed(_player.current_health, _player.max_health)

		_interactor = _player.get_node_or_null("BlockInteractor") as BlockInteractor
		if _interactor != null:
			_interactor.hotbar_slot_changed.connect(_on_hotbar_slot_changed)
			_on_hotbar_slot_changed(_interactor.selected_slot, _interactor.get_selected_block_id())


func _on_world_saved(saved_chunk_count: int) -> void:
	_save_toast_timer = 2.5
	if _pause_status_label != null:
		_pause_status_label.text = "Saved %d modified chunk(s) to disk!" % saved_chunk_count


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


func _build_crosshair() -> void:
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


func _build_bottom_hud() -> void:
	var bottom_margin := MarginContainer.new()
	bottom_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_margin.offset_top = -112
	bottom_margin.add_theme_constant_override("margin_bottom", 14)
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.alignment = BoxContainer.ALIGNMENT_END
	root_vbox.add_theme_constant_override("separation", 6)
	root_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_margin.add_child(root_vbox)

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

	# 2. 9-Slot Block Hotbar
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(hbox)

	for i in range(BlockInteractor.HOTBAR_BLOCKS.size()):
		var block_id: int = BlockInteractor.HOTBAR_BLOCKS[i]
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
		swatch.color = BlockRegistry.get_block_color(block_id)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(swatch)

		var label := Label.new()
		label.text = "%d:%s" % [i + 1, BlockRegistry.get_block_name(block_id).substr(0, 6)]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)
		vbox.add_child(label)

		hbox.add_child(panel)
		_slot_panels.append(panel)

	_update_hotbar_visuals(0)


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


func _on_hotbar_slot_changed(slot_index: int, _block_id: int) -> void:
	_update_hotbar_visuals(slot_index)


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
