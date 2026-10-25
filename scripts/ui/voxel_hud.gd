class_name VoxelHUD
extends CanvasLayer
## Retro HUD displaying center crosshair, 5-slot block hotbar, and debug status overlay.

const SLOT_COLORS: Dictionary = {
	BlockRegistry.BlockId.GRASS: Color(0.36, 0.71, 0.28),
	BlockRegistry.BlockId.DIRT: Color(0.53, 0.36, 0.21),
	BlockRegistry.BlockId.STONE: Color(0.52, 0.54, 0.56),
	BlockRegistry.BlockId.WOOD_LOG: Color(0.41, 0.27, 0.14),
	BlockRegistry.BlockId.LEAVES: Color(0.24, 0.56, 0.20),
}

var _player: Node3D = null
var _world_manager: WorldManager = null
var _interactor: BlockInteractor = null
var _slot_panels: Array[PanelContainer] = []
var _debug_label: Label = null
var _save_toast_timer: float = 0.0


func _ready() -> void:
	_build_crosshair()
	_build_hotbar()
	_build_debug_overlay()
	call_deferred("_bind_references")


func _process(delta: float) -> void:
	if _save_toast_timer > 0.0:
		_save_toast_timer = maxf(0.0, _save_toast_timer - delta)

	if _debug_label != null and _player != null:
		var pos: Vector3 = _player.global_position
		var chunk_coord: Vector2i = WorldManager.world_to_chunk_coords(pos)
		var fps: int = Engine.get_frames_per_second()
		var block_name: String = "Grass"
		if _interactor != null:
			block_name = BlockRegistry.get_block_name(_interactor.get_selected_block_id())

		var active_chunks: int = _world_manager.get_active_chunk_count() if _world_manager != null else 0
		var modified_chunks: int = _world_manager.get_modified_chunk_count() if _world_manager != null else 0
		var save_status: String = " | [SAVED TO DISK!]" if _save_toast_timer > 0.0 else ""

		_debug_label.text = (
			"VoxelCraft 0.2 | %d FPS | Chunks: %d (Edited: %d)%s\n" % [fps, active_chunks, modified_chunks, save_status]
			+ "XYZ: %.1f, %.1f, %.1f | Chunk: (%d, %d)\n" % [pos.x, pos.y, pos.z, chunk_coord.x, chunk_coord.y]
			+ "Selected: %s | [LMB] Break  [RMB] Place  [1-5/Scroll] Block  [F6] Save  [Esc] Cursor" % block_name
		)


func _bind_references() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_world_manager = get_tree().get_first_node_in_group("world_manager") as WorldManager
	if _world_manager != null:
		_world_manager.world_saved.connect(_on_world_saved)

	if _player != null:
		_interactor = _player.get_node_or_null("BlockInteractor") as BlockInteractor
		if _interactor != null:
			_interactor.hotbar_slot_changed.connect(_on_hotbar_slot_changed)
			_on_hotbar_slot_changed(_interactor.selected_slot, _interactor.get_selected_block_id())


func _on_world_saved(_saved_chunk_count: int) -> void:
	_save_toast_timer = 2.5


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


func _build_hotbar() -> void:
	var bottom_margin := MarginContainer.new()
	bottom_margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_margin.offset_top = -84
	bottom_margin.add_theme_constant_override("margin_bottom", 16)
	bottom_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_margin)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_margin.add_child(hbox)

	for i in range(BlockInteractor.HOTBAR_BLOCKS.size()):
		var block_id: int = BlockInteractor.HOTBAR_BLOCKS[i]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(64, 64)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(vbox)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(28, 28)
		swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		swatch.color = SLOT_COLORS.get(block_id, Color.GRAY)
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
