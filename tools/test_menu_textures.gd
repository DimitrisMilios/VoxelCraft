extends SceneTree

func _initialize() -> void:
	print("--- Testing Menu Texture Loading ---")
	var b_tex: Texture2D = InventoryManager.load_ui_texture("res://assets/ui/gui_panels/button.png")
	var p_tex: Texture2D = InventoryManager.load_ui_texture("res://assets/ui/gui_panels/panel_bg.png")
	var pano: Texture2D = InventoryManager.load_ui_texture("res://assets/ui/gui_panels/title_panorama.png")
	print("button.png: ", b_tex)
	print("panel_bg.png: ", p_tex)
	print("title_panorama.png: ", pano)
	assert(b_tex != null, "button.png must load!")
	assert(p_tex != null, "panel_bg.png must load!")
	assert(pano != null, "title_panorama.png must load!")
	print("ALL MENU TEXTURES LOADED SUCCESSFULLY!")
	quit(0)
