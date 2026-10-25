class_name MainMenu
extends Control
## Main Menu title screen supporting Singleplayer World Management,
## Save/Load restoration, unique world seed generation, and Options.
## Styled with Faithful 64x textures.

const GameSession = preload("res://scripts/core/game_session.gd")
const InventoryManager = preload("res://scripts/player/inventory_manager.gd")

enum ViewState {
	TITLE,
	WORLD_SELECT,
	CREATE_WORLD,
	OPTIONS
}

var _current_view: ViewState = ViewState.TITLE

# UI References
var _title_view: Control = null
var _world_select_view: Control = null
var _create_world_view: Control = null
var _options_view: Control = null

# World Select UI
var _world_list_vbox: VBoxContainer = null
var _selected_world_id: String = ""

# Create World Inputs
var _world_name_input: LineEdit = null
var _world_seed_input: LineEdit = null

# Options
var _render_dist_label: Label = null
var _render_dist_slider: HSlider = null


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_ui()
	_show_view(ViewState.TITLE)


func _build_ui() -> void:
	# 1. Background Panorama
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = _load_gui_texture("title_panorama.png")
	add_child(bg)

	var vignette := ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.02, 0.04, 0.08, 0.55)
	add_child(vignette)

	# 2. Views Container
	_build_title_view()
	_build_world_select_view()
	_build_create_world_view()
	_build_options_view()


func _load_gui_texture(file_name: String) -> Texture2D:
	return InventoryManager.load_ui_texture("res://assets/ui/gui_panels/" + file_name)


func _style_faithful_button(btn: Button) -> void:
	var tex_normal: Texture2D = _load_gui_texture("button.png")
	var tex_hover: Texture2D = _load_gui_texture("button_highlighted.png")
	var tex_disabled: Texture2D = _load_gui_texture("button_disabled.png")

	var sb_norm := StyleBoxTexture.new()
	sb_norm.texture = tex_normal
	sb_norm.texture_margin_left = 6.0
	sb_norm.texture_margin_right = 6.0
	sb_norm.texture_margin_top = 6.0
	sb_norm.texture_margin_bottom = 6.0
	sb_norm.set_content_margin_all(8.0)

	var sb_hov := StyleBoxTexture.new()
	sb_hov.texture = tex_hover
	sb_hov.texture_margin_left = 6.0
	sb_hov.texture_margin_right = 6.0
	sb_hov.texture_margin_top = 6.0
	sb_hov.texture_margin_bottom = 6.0
	sb_hov.set_content_margin_all(8.0)

	var sb_dis := StyleBoxTexture.new()
	sb_dis.texture = tex_disabled
	sb_dis.texture_margin_left = 6.0
	sb_dis.texture_margin_right = 6.0
	sb_dis.texture_margin_top = 6.0
	sb_dis.texture_margin_bottom = 6.0
	sb_dis.set_content_margin_all(8.0)

	btn.add_theme_stylebox_override("normal", sb_norm)
	btn.add_theme_stylebox_override("hover", sb_hov)
	btn.add_theme_stylebox_override("pressed", sb_hov)
	btn.add_theme_stylebox_override("focus", sb_hov)
	btn.add_theme_stylebox_override("disabled", sb_dis)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 0.65, 1))
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	btn.add_theme_constant_override("shadow_offset_x", 1)
	btn.add_theme_constant_override("shadow_offset_y", 1)


func _style_panel_box(panel: PanelContainer) -> void:
	var tex_panel: Texture2D = _load_gui_texture("panel_bg.png")
	var sb := StyleBoxTexture.new()
	sb.texture = tex_panel
	sb.texture_margin_left = 12.0
	sb.texture_margin_right = 12.0
	sb.texture_margin_top = 12.0
	sb.texture_margin_bottom = 12.0
	sb.set_content_margin_all(16.0)
	panel.add_theme_stylebox_override("panel", sb)


func _style_line_edit(line_edit: LineEdit) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.10, 0.88)
	sb.border_color = Color(0.60, 0.60, 0.65, 1.0)
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.set_content_margin_all(8.0)
	line_edit.add_theme_stylebox_override("normal", sb)
	line_edit.add_theme_stylebox_override("focus", sb)
	line_edit.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	line_edit.add_theme_color_override("placeholder_color", Color(0.6, 0.6, 0.65, 0.7))


# ==============================================================================
# VIEW 1: TITLE VIEW
# ==============================================================================
func _build_title_view() -> void:
	_title_view = Control.new()
	_title_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_title_view)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_view.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var logo_label := Label.new()
	logo_label.text = "VOXELCRAFT"
	logo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo_label.add_theme_font_size_override("font_size", 48)
	logo_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.32))
	logo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	logo_label.add_theme_constant_override("shadow_offset_x", 3)
	logo_label.add_theme_constant_override("shadow_offset_y", 3)
	vbox.add_child(logo_label)

	var subtitle := Label.new()
	subtitle.text = "Faithful 64x HD Edition"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.95, 0.95, 0.75))
	subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	subtitle.add_theme_constant_override("shadow_offset_x", 1)
	subtitle.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var sp_btn := Button.new()
	sp_btn.text = "Singleplayer"
	sp_btn.custom_minimum_size = Vector2(340, 42)
	_style_faithful_button(sp_btn)
	sp_btn.pressed.connect(func() -> void:
		_show_view(ViewState.WORLD_SELECT)
	)
	vbox.add_child(sp_btn)

	var opt_btn := Button.new()
	opt_btn.text = "Options..."
	opt_btn.custom_minimum_size = Vector2(340, 42)
	_style_faithful_button(opt_btn)
	opt_btn.pressed.connect(func() -> void:
		_show_view(ViewState.OPTIONS)
	)
	vbox.add_child(opt_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit Game"
	quit_btn.custom_minimum_size = Vector2(340, 42)
	_style_faithful_button(quit_btn)
	quit_btn.pressed.connect(func() -> void:
		get_tree().quit()
	)
	vbox.add_child(quit_btn)

	var footer := Label.new()
	footer.text = "Faithful 64x Resource Pack | Faithful License v4"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
	vbox.add_child(footer)


# ==============================================================================
# VIEW 2: WORLD SELECTION (SINGLEPLAYER)
# ==============================================================================
func _build_world_select_view() -> void:
	_world_select_view = Control.new()
	_world_select_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_world_select_view)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world_select_view.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(620, 520)
	_style_panel_box(card)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "Select World"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_world_list_vbox = VBoxContainer.new()
	_world_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_world_list_vbox)

	var bottom_row := HBoxContainer.new()
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_row.add_theme_constant_override("separation", 16)
	vbox.add_child(bottom_row)

	var create_btn := Button.new()
	create_btn.text = "Create New World"
	create_btn.custom_minimum_size = Vector2(240, 38)
	_style_faithful_button(create_btn)
	create_btn.pressed.connect(func() -> void:
		_show_view(ViewState.CREATE_WORLD)
	)
	bottom_row.add_child(create_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(180, 38)
	_style_faithful_button(cancel_btn)
	cancel_btn.pressed.connect(func() -> void:
		_show_view(ViewState.TITLE)
	)
	bottom_row.add_child(cancel_btn)


func _refresh_world_list() -> void:
	for child in _world_list_vbox.get_children():
		child.queue_free()

	var worlds: Array[Dictionary] = GameSession.list_saved_worlds()
	if worlds.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No saved worlds yet.\nClick 'Create New World' to begin your adventure!"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		empty_lbl.add_theme_font_size_override("font_size", 14)
		_world_list_vbox.add_child(empty_lbl)
		return

	for w in worlds:
		var item_panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.14, 0.18, 0.85)
		sb.border_color = Color(0.35, 0.38, 0.44, 1.0)
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.set_content_margin_all(10.0)
		item_panel.add_theme_stylebox_override("panel", sb)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		item_panel.add_child(hbox)

		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info_vbox)

		var name_lbl := Label.new()
		name_lbl.text = str(w.get("world_name", "World"))
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", Color(0.98, 0.92, 0.5))
		info_vbox.add_child(name_lbl)

		var meta_lbl := Label.new()
		var seed_val: int = int(w.get("seed", 2027))
		var last_time: int = int(w.get("last_played", 0))
		var time_str: String = "Never played"
		if last_time > 0:
			var d: Dictionary = Time.get_datetime_dict_from_unix_time(last_time)
			time_str = "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]
		meta_lbl.text = "Seed: %d  |  Last Played: %s" % [seed_val, time_str]
		meta_lbl.add_theme_font_size_override("font_size", 12)
		meta_lbl.add_theme_color_override("font_color", Color(0.70, 0.72, 0.78))
		info_vbox.add_child(meta_lbl)

		var play_btn := Button.new()
		play_btn.text = "Play"
		play_btn.custom_minimum_size = Vector2(80, 32)
		_style_faithful_button(play_btn)
		var wid: String = str(w.get("id", ""))
		play_btn.pressed.connect(func() -> void:
			_launch_world(wid)
		)
		hbox.add_child(play_btn)

		var del_btn := Button.new()
		del_btn.text = "Delete"
		del_btn.custom_minimum_size = Vector2(70, 32)
		_style_faithful_button(del_btn)
		del_btn.pressed.connect(func() -> void:
			GameSession.delete_world(wid)
			_refresh_world_list()
		)
		hbox.add_child(del_btn)

		_world_list_vbox.add_child(item_panel)


func _launch_world(world_id: String) -> void:
	if GameSession.select_world(world_id):
		get_tree().change_scene_to_file("res://scenes/main.tscn")


# ==============================================================================
# VIEW 3: CREATE NEW WORLD
# ==============================================================================
func _build_create_world_view() -> void:
	_create_world_view = Control.new()
	_create_world_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_create_world_view)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_create_world_view.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(480, 380)
	_style_panel_box(card)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "Create New World"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var name_lbl := Label.new()
	name_lbl.text = "World Name:"
	vbox.add_child(name_lbl)

	_world_name_input = LineEdit.new()
	_world_name_input.text = "New World"
	_world_name_input.custom_minimum_size = Vector2(0, 36)
	_style_line_edit(_world_name_input)
	vbox.add_child(_world_name_input)

	var seed_lbl := Label.new()
	seed_lbl.text = "World Seed:"
	vbox.add_child(seed_lbl)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	vbox.add_child(seed_row)

	_world_seed_input = LineEdit.new()
	_world_seed_input.placeholder_text = "Leave blank for random seed"
	_world_seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_seed_input.custom_minimum_size = Vector2(0, 36)
	_style_line_edit(_world_seed_input)
	seed_row.add_child(_world_seed_input)

	var rand_seed_btn := Button.new()
	rand_seed_btn.text = "Random Seed"
	rand_seed_btn.custom_minimum_size = Vector2(120, 36)
	_style_faithful_button(rand_seed_btn)
	rand_seed_btn.pressed.connect(func() -> void:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_world_seed_input.text = str(rng.randi_range(100000, 99999999))
	)
	seed_row.add_child(rand_seed_btn)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)

	var create_btn := Button.new()
	create_btn.text = "Create & Play World"
	create_btn.custom_minimum_size = Vector2(0, 40)
	_style_faithful_button(create_btn)
	create_btn.pressed.connect(func() -> void:
		var w_name: String = _world_name_input.text.strip_edges()
		if w_name.is_empty():
			w_name = "New World"
		var w_seed_str: String = _world_seed_input.text.strip_edges()
		var new_id: String = GameSession.create_world(w_name, w_seed_str)
		_launch_world(new_id)
	)
	vbox.add_child(create_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 36)
	_style_faithful_button(cancel_btn)
	cancel_btn.pressed.connect(func() -> void:
		_show_view(ViewState.WORLD_SELECT)
	)
	vbox.add_child(cancel_btn)


# ==============================================================================
# VIEW 4: OPTIONS
# ==============================================================================
func _build_options_view() -> void:
	_options_view = Control.new()
	_options_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_options_view)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_view.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(440, 340)
	_style_panel_box(card)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	_render_dist_label = Label.new()
	_render_dist_label.text = "Render Distance: 5 Chunks"
	vbox.add_child(_render_dist_label)

	_render_dist_slider = HSlider.new()
	_render_dist_slider.min_value = 2
	_render_dist_slider.max_value = 8
	_render_dist_slider.step = 1
	_render_dist_slider.value = 5
	_render_dist_slider.value_changed.connect(func(val: float) -> void:
		_render_dist_label.text = "Render Distance: %d Chunks" % int(val)
	)
	vbox.add_child(_render_dist_slider)

	var fov_lbl := Label.new()
	fov_lbl.text = "Field of View: Normal (75°)"
	vbox.add_child(fov_lbl)

	var fov_slider := HSlider.new()
	fov_slider.min_value = 60
	fov_slider.max_value = 100
	fov_slider.step = 1
	fov_slider.value = 75
	fov_slider.value_changed.connect(func(val: float) -> void:
		fov_lbl.text = "Field of View: %d°" % int(val)
	)
	vbox.add_child(fov_slider)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(spacer)

	var done_btn := Button.new()
	done_btn.text = "Done"
	done_btn.custom_minimum_size = Vector2(0, 38)
	_style_faithful_button(done_btn)
	done_btn.pressed.connect(func() -> void:
		_show_view(ViewState.TITLE)
	)
	vbox.add_child(done_btn)


# ==============================================================================
# VIEW NAVIGATION
# ==============================================================================
func _show_view(view: ViewState) -> void:
	_current_view = view
	_title_view.visible = (view == ViewState.TITLE)
	_world_select_view.visible = (view == ViewState.WORLD_SELECT)
	_create_world_view.visible = (view == ViewState.CREATE_WORLD)
	_options_view.visible = (view == ViewState.OPTIONS)

	if view == ViewState.WORLD_SELECT:
		_refresh_world_list()
	elif view == ViewState.CREATE_WORLD:
		if _world_seed_input != null:
			_world_seed_input.text = ""
