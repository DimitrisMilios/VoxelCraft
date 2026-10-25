"""
Headless Blender 5.2 Pipeline for VoxelCraft Phase 2:
Renders 3D beveled Minecraft GUI panels/slots, 3D HUD status icons (Hearts, Drumsticks, Bubbles),
and orthographic 3D Isometric Block & Tool icons into `assets/ui/`.

Usage:
  blender --background --python tools/blender/render_ui_assets.py
"""

import math
import os
import bpy
from mathutils import Euler, Vector

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GUI_DIR = os.path.join(ROOT_DIR, "assets", "ui", "gui_panels")
HUD_DIR = os.path.join(ROOT_DIR, "assets", "ui", "hud_icons")
ITEM_DIR = os.path.join(ROOT_DIR, "assets", "ui", "item_icons")

for d in (GUI_DIR, HUD_DIR, ITEM_DIR):
    os.makedirs(d, exist_ok=True)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = False
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"

    world = bpy.data.worlds.new("StudioWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.85, 0.87, 0.90, 1.0)
        bg.inputs[1].default_value = 0.55
    return scene


def make_mat(name, rgba, roughness=0.55, metallic=0.0, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if emission_strength > 0.0 and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = rgba
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def add_box(name, loc, scale, mat, bevel_width=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel_width > 0.0:
        bev = obj.modifiers.new(name="Bevel", type="BEVEL")
        bev.width = bevel_width
        bev.segments = 2
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)
    return obj


def setup_ortho_top_camera(scene, res_x, res_y, ortho_scale=2.0):
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    cam_data = bpy.data.cameras.new("OrthoCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale
    cam_obj = bpy.data.objects.new("OrthoCam", cam_data)
    scene.collection.objects.link(cam_obj)
    cam_obj.location = (0.0, 0.0, 5.0)
    cam_obj.rotation_euler = (0.0, 0.0, 0.0)
    scene.camera = cam_obj

    # Top-left directional sun for authentic 3D bevel highlights & shadows
    light_data = bpy.data.lights.new(name="KeySun", type="SUN")
    light_data.energy = 3.2
    light_data.angle = math.radians(8.0)
    light_obj = bpy.data.objects.new(name="KeySun", object_data=light_data)
    scene.collection.objects.link(light_obj)
    light_obj.rotation_euler = (math.radians(28), math.radians(-28), math.radians(15))

    fill_data = bpy.data.lights.new(name="FillSun", type="SUN")
    fill_data.energy = 1.1
    fill_obj = bpy.data.objects.new(name="FillSun", object_data=fill_data)
    scene.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = (math.radians(-18), math.radians(22), 0.0)


def setup_isometric_block_camera(scene, res=64):
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    cam_data = bpy.data.cameras.new("IsoCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.62
    cam_obj = bpy.data.objects.new("IsoCam", cam_data)
    scene.collection.objects.link(cam_obj)

    # Classic Minecraft 30 deg elevation, 45 deg azimuth isometric view
    rot = Euler((math.radians(60.0), 0.0, math.radians(45.0)), "XYZ")
    cam_obj.rotation_euler = rot
    forward = rot.to_matrix() @ Vector((0.0, 0.0, -1.0))
    cam_obj.location = -forward * 5.0
    scene.camera = cam_obj

    # 3-Point studio lighting so Top = brightest, Left = medium, Right = shaded
    top_sun = bpy.data.lights.new("TopKey", type="SUN")
    top_sun.energy = 2.1
    top_obj = bpy.data.objects.new("TopKey", top_sun)
    scene.collection.objects.link(top_obj)
    top_obj.rotation_euler = Euler((math.radians(18.0), math.radians(-12.0), math.radians(10.0)), "XYZ")

    left_sun = bpy.data.lights.new("LeftFill", type="SUN")
    left_sun.energy = 1.35
    left_obj = bpy.data.objects.new("LeftFill", left_sun)
    scene.collection.objects.link(left_obj)
    left_obj.rotation_euler = Euler((math.radians(68.0), 0.0, math.radians(12.0)), "XYZ")

    right_sun = bpy.data.lights.new("RightRim", type="SUN")
    right_sun.energy = 0.65
    right_obj = bpy.data.objects.new("RightRim", right_sun)
    scene.collection.objects.link(right_obj)
    right_obj.rotation_euler = Euler((math.radians(72.0), 0.0, math.radians(95.0)), "XYZ")


def render_to(scene, out_path):
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print(f"Rendered: {out_path}")


# ==============================================================================
# 1. RENDER 3D BEVELED MINECRAFT GUI PANELS & SLOTS
# ==============================================================================
def render_gui_panels():
    # A. Main Stone-Grey Beveled Panel (128x128)
    scene = clear_scene()
    setup_ortho_top_camera(scene, 128, 128, ortho_scale=2.0)
    m_border_dark = make_mat("BorderDark", (0.05, 0.05, 0.06, 1.0), 0.75)
    m_border_hi = make_mat("BorderHi", (0.52, 0.54, 0.58, 1.0), 0.45)
    m_border_sh = make_mat("BorderSh", (0.12, 0.13, 0.15, 1.0), 0.65)
    m_face = make_mat("PanelFace", (0.24, 0.25, 0.28, 1.0), 0.60)

    add_box("OuterDark", (0, 0, 0.0), (1.98, 1.98, 0.15), m_border_dark, 0.04)
    add_box("TopLeftHi", (-0.03, 0.03, 0.08), (1.88, 1.88, 0.16), m_border_hi, 0.03)
    add_box("BotRightSh", (0.03, -0.03, 0.09), (1.88, 1.88, 0.16), m_border_sh, 0.03)
    add_box("CenterFace", (0, 0, 0.14), (1.76, 1.76, 0.18), m_face, 0.02)
    render_to(scene, os.path.join(GUI_DIR, "panel_bg.png"))

    # B. Recessed Inventory Slot (64x64)
    scene = clear_scene()
    setup_ortho_top_camera(scene, 64, 64, ortho_scale=2.0)
    m_slot_tl = make_mat("SlotTL", (0.06, 0.06, 0.08, 1.0), 0.75)
    m_slot_br = make_mat("SlotBR", (0.56, 0.58, 0.62, 1.0), 0.40)
    m_slot_well = make_mat("SlotWell", (0.15, 0.16, 0.19, 1.0), 0.65)

    add_box("RimBR", (0.04, -0.04, 0.0), (1.92, 1.92, 0.15), m_slot_br, 0.02)
    add_box("RimTL", (-0.04, 0.04, 0.02), (1.92, 1.92, 0.16), m_slot_tl, 0.02)
    add_box("Well", (0.02, -0.02, 0.06), (1.70, 1.70, 0.16), m_slot_well, 0.01)
    render_to(scene, os.path.join(GUI_DIR, "slot_normal.png"))

    # C. Selected Hotbar Slot Frame (64x64)
    scene = clear_scene()
    setup_ortho_top_camera(scene, 64, 64, ortho_scale=2.0)
    m_gold_rim = make_mat("GoldRim", (0.98, 0.82, 0.22, 1.0), 0.28, 0.45)
    m_gold_dark = make_mat("GoldDark", (0.14, 0.10, 0.04, 1.0), 0.65)
    m_well_sel = make_mat("WellSel", (0.20, 0.22, 0.27, 1.0), 0.55)

    add_box("OuterBlk", (0, 0, 0.0), (1.98, 1.98, 0.14), m_gold_dark, 0.03)
    add_box("GoldBevel", (0, 0, 0.08), (1.88, 1.88, 0.18), m_gold_rim, 0.04)
    add_box("InnerWell", (0, 0, 0.14), (1.54, 1.54, 0.18), m_well_sel, 0.02)
    render_to(scene, os.path.join(GUI_DIR, "slot_selected.png"))

    # D. Output Slot (64x64)
    scene = clear_scene()
    setup_ortho_top_camera(scene, 64, 64, ortho_scale=2.0)
    m_out_rim = make_mat("OutRim", (0.88, 0.68, 0.18, 1.0), 0.32, 0.45)
    m_out_well = make_mat("OutWell", (0.16, 0.17, 0.20, 1.0), 0.60)
    add_box("OutOuter", (0, 0, 0.0), (1.94, 1.94, 0.14), m_out_rim, 0.04)
    add_box("OutInner", (0, 0, 0.08), (1.66, 1.66, 0.16), m_out_well, 0.02)
    render_to(scene, os.path.join(GUI_DIR, "slot_output.png"))


# ==============================================================================
# 2. RENDER 3D HUD STATUS ICONS (HEARTS, HUNGER DRUMSTICKS, OXYGEN BUBBLES)
# ==============================================================================
HEART_GRID = [
    " 11   11 ",
    "1221 1111",
    "121111111",
    "111111111",
    " 1111111 ",
    "  11111  ",
    "   111   ",
    "    1    ",
]

DRUMSTICK_GRID = [
    "    111  ",
    "   12211 ",
    "  121111 ",
    "  11111  ",
    "   111   ",
    "  33     ",
    " 33      ",
    "33       ",
]


def render_voxel_mask_icon(grid, mode, out_path):
    scene = clear_scene()
    setup_ortho_top_camera(scene, 48, 48, ortho_scale=2.05)

    m_rim = make_mat("Rim", (0.06, 0.06, 0.08, 1.0), 0.7)
    m_empty = make_mat("Empty", (0.20, 0.20, 0.24, 1.0), 0.65)
    m_red = make_mat("Red", (0.92, 0.12, 0.16, 1.0), 0.32)
    m_spec = make_mat("Spec", (1.0, 0.86, 0.88, 1.0), 0.18)
    m_meat = make_mat("Meat", (0.78, 0.42, 0.14, 1.0), 0.42)
    m_meat_hi = make_mat("MeatHi", (0.95, 0.66, 0.32, 1.0), 0.30)
    m_bone = make_mat("Bone", (0.94, 0.92, 0.86, 1.0), 0.35)

    cell = 0.20
    rows = len(grid)
    cols = len(grid[0])

    for r, row_str in enumerate(grid):
        for c, ch in enumerate(row_str):
            if ch == " ":
                continue
            x = (c - (cols - 1) * 0.5) * cell
            y = ((rows - 1) * 0.5 - r) * cell

            # Dark 3D backing outline
            add_box(f"Bg_{r}_{c}", (x, y, 0.0), (cell * 1.16, cell * 1.16, 0.14), m_rim, 0.01)

            is_filled = True
            if mode == "empty":
                is_filled = False
            elif mode == "half" and c >= cols // 2:
                is_filled = False

            if not is_filled:
                add_box(f"Fg_{r}_{c}", (x, y, 0.08), (cell * 0.92, cell * 0.92, 0.14), m_empty, 0.01)
            else:
                if ch == "1":
                    mat = m_red if "heart" in out_path else m_meat
                elif ch == "2":
                    mat = m_spec if "heart" in out_path else m_meat_hi
                else:
                    mat = m_bone
                add_box(f"Fg_{r}_{c}", (x, y, 0.12), (cell * 0.96, cell * 0.96, 0.22), mat, 0.02)

    render_to(scene, out_path)


def render_hud_icons():
    render_voxel_mask_icon(HEART_GRID, "full", os.path.join(HUD_DIR, "heart_full.png"))
    render_voxel_mask_icon(HEART_GRID, "half", os.path.join(HUD_DIR, "heart_half.png"))
    render_voxel_mask_icon(HEART_GRID, "empty", os.path.join(HUD_DIR, "heart_empty.png"))

    render_voxel_mask_icon(DRUMSTICK_GRID, "full", os.path.join(HUD_DIR, "hunger_full.png"))
    render_voxel_mask_icon(DRUMSTICK_GRID, "half", os.path.join(HUD_DIR, "hunger_half.png"))
    render_voxel_mask_icon(DRUMSTICK_GRID, "empty", os.path.join(HUD_DIR, "hunger_empty.png"))

    # Oxygen Bubbles (Full & Empty)
    scene = clear_scene()
    setup_ortho_top_camera(scene, 48, 48, ortho_scale=2.0)
    m_bub_rim = make_mat("BubRim", (0.06, 0.32, 0.58, 1.0), 0.3)
    m_bub_core = make_mat("BubCore", (0.24, 0.82, 0.98, 1.0), 0.15)
    m_bub_spec = make_mat("BubSpec", (0.95, 0.99, 1.0, 1.0), 0.1, 0.0, 0.5)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.82, location=(0, 0, 0.0))
    s_rim = bpy.context.active_object
    s_rim.data.materials.append(m_bub_rim)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.70, location=(0, 0, 0.15))
    s_core = bpy.context.active_object
    s_core.data.materials.append(m_bub_core)
    add_box("Spec", (-0.26, 0.28, 0.78), (0.26, 0.26, 0.18), m_bub_spec, 0.03)
    render_to(scene, os.path.join(HUD_DIR, "bubble_full.png"))

    scene = clear_scene()
    setup_ortho_top_camera(scene, 48, 48, ortho_scale=2.0)
    m_bub_empty = make_mat("BubEmpty", (0.14, 0.26, 0.38, 1.0), 0.6)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.68, minor_radius=0.12, location=(0, 0, 0.0))
    tor = bpy.context.active_object
    tor.data.materials.append(m_bub_empty)
    render_to(scene, os.path.join(HUD_DIR, "bubble_empty.png"))


# ==============================================================================
# 3. RENDER 3D ISOMETRIC BLOCKS (IDs 1..27) & 3D EXTRUDED ITEMS/TOOLS (100..234)
# ==============================================================================
def build_3d_block_model(block_id):
    # Base colors & details per block ID
    if block_id == 1:  # GRASS
        m_dirt = make_mat("Dirt", (0.52, 0.35, 0.20, 1.0), 0.75)
        m_grass = make_mat("Grass", (0.34, 0.74, 0.24, 1.0), 0.55)
        add_box("DirtBase", (0, 0, -0.12), (0.98, 0.98, 0.76), m_dirt, 0.02)
        add_box("GrassCap", (0, 0, 0.36), (1.01, 1.01, 0.28), m_grass, 0.02)
    elif block_id == 2:  # DIRT
        m_dirt = make_mat("Dirt", (0.52, 0.35, 0.20, 1.0), 0.78)
        m_peb = make_mat("Pebble", (0.40, 0.26, 0.14, 1.0), 0.8)
        add_box("Cube", (0, 0, 0), (0.98, 0.98, 0.98), m_dirt, 0.03)
        add_box("P1", (0.25, -0.25, 0.48), (0.22, 0.22, 0.06), m_peb, 0.01)
    elif block_id == 3:  # STONE
        m_stone = make_mat("Stone", (0.56, 0.58, 0.60, 1.0), 0.65)
        m_strata = make_mat("Strata", (0.46, 0.48, 0.50, 1.0), 0.7)
        add_box("Cube", (0, 0, 0), (0.98, 0.98, 0.98), m_stone, 0.03)
        add_box("Band", (0, 0, 0.12), (1.0, 1.0, 0.16), m_strata, 0.01)
    elif block_id == 4:  # WOOD_LOG
        m_bark = make_mat("Bark", (0.38, 0.25, 0.14, 1.0), 0.75)
        m_ring = make_mat("Rings", (0.76, 0.60, 0.38, 1.0), 0.55)
        add_box("BarkShell", (0, 0, 0), (0.98, 0.98, 0.96), m_bark, 0.03)
        add_box("Heartwood", (0, 0, 0.02), (0.78, 0.78, 1.00), m_ring, 0.02)
    elif block_id == 5:  # LEAVES
        m_leaf = make_mat("Leaf", (0.20, 0.58, 0.18, 1.0), 0.65)
        m_leaf_hi = make_mat("LeafHi", (0.28, 0.68, 0.24, 1.0), 0.55)
        add_box("Core", (0, 0, 0), (0.94, 0.94, 0.94), m_leaf, 0.04)
        for ox, oy, oz in [(-0.24, -0.24, 0.24), (0.24, 0.24, 0.24), (-0.24, 0.24, -0.24), (0.24, -0.24, 0.24)]:
            add_box("Cluster", (ox, oy, oz), (0.54, 0.54, 0.54), m_leaf_hi, 0.02)
    elif block_id == 6:  # SAND
        m_sand = make_mat("Sand", (0.90, 0.84, 0.56, 1.0), 0.60)
        add_box("Cube", (0, 0, 0), (0.98, 0.98, 0.98), m_sand, 0.03)
    elif block_id == 7 or block_id == 27:  # COBBLESTONE / MOSSY_COBBLE
        m_mortar = make_mat("Mortar", (0.22, 0.42, 0.18, 1.0) if block_id == 27 else (0.32, 0.33, 0.35, 1.0), 0.8)
        m_cob = make_mat("Cobble", (0.54, 0.55, 0.58, 1.0), 0.65)
        add_box("Core", (0, 0, 0), (0.94, 0.94, 0.94), m_mortar, 0.02)
        for ox in (-0.24, 0.24):
            for oy in (-0.24, 0.24):
                for oz in (-0.24, 0.24):
                    add_box("Stone", (ox, oy, oz), (0.48, 0.48, 0.48), m_cob, 0.03)
    elif block_id == 8:  # WOOD_PLANKS
        m_plank = make_mat("Plank", (0.74, 0.56, 0.34, 1.0), 0.55)
        m_seam = make_mat("Seam", (0.46, 0.32, 0.18, 1.0), 0.7)
        add_box("Core", (0, 0, 0), (0.94, 0.94, 0.94), m_seam, 0.01)
        for i, z in enumerate((-0.33, 0.0, 0.33)):
            add_box(f"Board_{i}", (0, 0, z), (0.99, 0.99, 0.28), m_plank, 0.02)
    elif block_id == 9:  # WATER
        m_water = make_mat("Water", (0.14, 0.48, 0.92, 1.0), 0.15)
        add_box("Water", (0, 0, -0.06), (0.98, 0.98, 0.86), m_water, 0.03)
    elif block_id == 10:  # SNOW
        m_snow = make_mat("Snow", (0.94, 0.97, 1.0, 1.0), 0.45)
        add_box("Snow", (0, 0, 0), (0.98, 0.98, 0.98), m_snow, 0.04)
    elif block_id == 11:  # GLOWSTONE
        m_glow = make_mat("Glow", (1.0, 0.84, 0.32, 1.0), 0.3, 0.1, 0.6)
        m_frame = make_mat("Frame", (0.62, 0.44, 0.16, 1.0), 0.6)
        add_box("Frame", (0, 0, 0), (0.96, 0.96, 0.96), m_frame, 0.03)
        add_box("GlowCore", (0, 0, 0), (0.82, 0.82, 1.02), m_glow, 0.04)
    elif block_id in (12, 13, 14, 15):  # ORES (Coal, Iron, Gold, Diamond)
        m_rock = make_mat("Rock", (0.48, 0.50, 0.52, 1.0), 0.72)
        ore_colors = {
            12: ((0.08, 0.08, 0.10, 1.0), 0.4, 0.1),
            13: ((0.88, 0.64, 0.46, 1.0), 0.32, 0.5),
            14: ((1.0, 0.80, 0.12, 1.0), 0.22, 0.85),
            15: ((0.14, 0.92, 0.96, 1.0), 0.15, 0.35),
        }
        col, rgh, met = ore_colors[block_id]
        m_ore = make_mat("Ore", col, rgh, met)
        add_box("RockCube", (0, 0, 0), (0.94, 0.94, 0.94), m_rock, 0.03)
        # Protruding mineral veins on Top (+Z), Front-Left (-Y), and Front-Right (+X)
        for ox, oy, oz in [
            (-0.18, -0.18, 0.38), (0.20, 0.15, 0.38),
            (-0.18, -0.38, 0.16), (0.18, -0.38, -0.16),
            (0.38, -0.16, 0.18), (0.38, 0.18, -0.16),
        ]:
            add_box("Nugget", (ox, oy, oz), (0.28, 0.28, 0.28), m_ore, 0.02)
    elif block_id == 16:  # CRAFTING_TABLE
        m_oak = make_mat("Oak", (0.72, 0.52, 0.30, 1.0), 0.6)
        m_dark = make_mat("DarkWood", (0.36, 0.22, 0.12, 1.0), 0.7)
        m_top = make_mat("TopGrid", (0.84, 0.62, 0.36, 1.0), 0.45)
        add_box("Body", (0, 0, -0.08), (0.96, 0.96, 0.82), m_oak, 0.02)
        add_box("Pillars", (0, 0, -0.05), (0.99, 0.99, 0.72), m_dark, 0.01)
        add_box("SidePanel", (0, 0, -0.05), (0.78, 1.01, 0.70), m_oak, 0.01)
        add_box("SidePanel2", (0, 0, -0.05), (1.01, 0.78, 0.70), m_oak, 0.01)
        add_box("Top", (0, 0, 0.38), (1.0, 1.0, 0.22), m_top, 0.02)
    elif block_id == 17:  # FURNACE
        m_stone = make_mat("FurnStone", (0.50, 0.52, 0.55, 1.0), 0.65)
        m_dark = make_mat("FurnHole", (0.12, 0.12, 0.14, 1.0), 0.8)
        m_fire = make_mat("FurnFire", (1.0, 0.54, 0.12, 1.0), 0.3, 0.0, 0.7)
        add_box("Body", (0, 0, 0), (0.98, 0.98, 0.98), m_stone, 0.03)
        add_box("Hearth", (0, -0.46, -0.10), (0.56, 0.12, 0.52), m_dark, 0.01)
        add_box("Ember", (0, -0.48, -0.22), (0.42, 0.12, 0.24), m_fire, 0.01)
    elif block_id == 18:  # CHEST
        m_wood = make_mat("ChestWood", (0.72, 0.48, 0.20, 1.0), 0.55)
        m_rim = make_mat("ChestRim", (0.24, 0.16, 0.08, 1.0), 0.7)
        m_latch = make_mat("ChestLatch", (0.98, 0.84, 0.22, 1.0), 0.25, 0.8)
        add_box("Base", (0, 0, -0.16), (0.90, 0.90, 0.56), m_wood, 0.02)
        add_box("Seam", (0, 0, 0.14), (0.92, 0.92, 0.08), m_rim, 0.01)
        add_box("Lid", (0, 0, 0.30), (0.90, 0.90, 0.28), m_wood, 0.03)
        add_box("Latch", (0, -0.46, 0.14), (0.16, 0.10, 0.26), m_latch, 0.01)
    elif block_id == 19:  # TORCH
        m_stick = make_mat("Stick", (0.58, 0.40, 0.20, 1.0), 0.65)
        m_flame = make_mat("Flame", (1.0, 0.78, 0.18, 1.0), 0.2, 0.0, 0.85)
        add_box("Post", (0, 0, -0.12), (0.24, 0.24, 0.72), m_stick, 0.02)
        add_box("Fire", (0, 0, 0.34), (0.30, 0.30, 0.30), m_flame, 0.04)
    elif block_id == 20:  # BED
        m_wood = make_mat("BedWood", (0.68, 0.48, 0.26, 1.0), 0.6)
        m_red = make_mat("Blanket", (0.86, 0.16, 0.18, 1.0), 0.55)
        m_pil = make_mat("Pillow", (0.95, 0.95, 0.97, 1.0), 0.5)
        add_box("Frame", (0, 0, -0.22), (0.98, 0.98, 0.22), m_wood, 0.02)
        add_box("Mattress", (0.12, 0, 0.02), (0.72, 0.94, 0.26), m_red, 0.03)
        add_box("Pillow", (-0.32, 0, 0.06), (0.30, 0.88, 0.28), m_pil, 0.03)
    elif block_id in (21, 22):  # DOOR
        m_door = make_mat("DoorWood", (0.70, 0.48, 0.26, 1.0), 0.55)
        m_win = make_mat("DoorWin", (0.20, 0.14, 0.08, 1.0), 0.7)
        add_box("Panel", (0, 0, 0), (0.86, 0.22, 1.08), m_door, 0.02)
        add_box("Window", (0, 0, 0.24), (0.48, 0.26, 0.36), m_win, 0.01)
    elif block_id == 23:  # LADDER
        m_lad = make_mat("Ladder", (0.72, 0.52, 0.28, 1.0), 0.6)
        add_box("RailL", (-0.34, 0, 0), (0.16, 0.16, 1.06), m_lad, 0.02)
        add_box("RailR", (0.34, 0, 0), (0.16, 0.16, 1.06), m_lad, 0.02)
        for z in (-0.34, 0.0, 0.34):
            add_box("Rung", (0, 0, z), (0.82, 0.14, 0.14), m_lad, 0.01)
    elif block_id == 24:  # TNT
        m_red = make_mat("TNTRed", (0.88, 0.18, 0.14, 1.0), 0.55)
        m_band = make_mat("TNTBand", (0.94, 0.94, 0.96, 1.0), 0.5)
        m_top = make_mat("TNTTop", (0.22, 0.22, 0.24, 1.0), 0.7)
        add_box("RedBody", (0, 0, 0), (0.96, 0.96, 0.96), m_red, 0.03)
        add_box("WhiteBand", (0, 0, 0), (0.99, 0.99, 0.32), m_band, 0.01)
        add_box("Fuse", (0, 0, 0.50), (0.18, 0.18, 0.14), m_top, 0.01)
    elif block_id == 25:  # SANDSTONE
        m_ss = make_mat("Sandstone", (0.88, 0.80, 0.54, 1.0), 0.55)
        m_top = make_mat("SSTop", (0.94, 0.88, 0.64, 1.0), 0.48)
        add_box("Body", (0, 0, -0.08), (0.98, 0.98, 0.82), m_ss, 0.02)
        add_box("Cap", (0, 0, 0.38), (1.0, 1.0, 0.22), m_top, 0.02)
    elif block_id == 26:  # CACTUS
        m_cac = make_mat("Cactus", (0.18, 0.64, 0.22, 1.0), 0.55)
        m_spine = make_mat("Spine", (0.10, 0.28, 0.10, 1.0), 0.7)
        add_box("Trunk", (0, 0, 0), (0.84, 0.84, 0.98), m_cac, 0.04)
        add_box("RibX", (0, 0, 0), (0.94, 0.26, 0.96), m_cac, 0.02)
        add_box("RibY", (0, 0, 0), (0.26, 0.94, 0.96), m_cac, 0.02)
        add_box("Spines", (0, 0, 0.15), (0.98, 0.98, 0.10), m_spine, 0.01)


# Pixel-grid templates for 3D extruded tools, swords, ores, ingots, buckets & food
GRID_PICKAXE = [
    "  22222  ",
    " 2222222 ",
    "22  1  22",
    "   11    ",
    "  11     ",
    " 11      ",
    "11       ",
    "1        ",
]

GRID_AXE = [
    "  222    ",
    " 22221   ",
    " 22211   ",
    "  2 1    ",
    "   11    ",
    "  11     ",
    " 11      ",
    "11       ",
]

GRID_SHOVEL = [
    "     222 ",
    "    22222",
    "    22222",
    "    1222 ",
    "   11    ",
    "  11     ",
    " 11      ",
    "11       ",
]

GRID_SWORD = [
    "       22",
    "      222",
    "     222 ",
    " 3  222  ",
    " 33222   ",
    "  333    ",
    " 11 33   ",
    "11       ",
]

GRID_INGOT = [
    "         ",
    "  222222 ",
    " 23333322",
    "22333322 ",
    "2222222  ",
    "         ",
]

GRID_DIAMOND = [
    "   222   ",
    "  23332  ",
    " 2333332 ",
    " 2233322 ",
    "  22222  ",
    "   222   ",
]

GRID_BUCKET = [
    " 2333332 ",
    "233333332",
    "222222222",
    " 2222222 ",
    " 2222222 ",
    "  22222  ",
]

GRID_APPLE = [
    "    1    ",
    "  22122  ",
    " 2322222 ",
    " 2222222 ",
    " 2222222 ",
    "  22222  ",
    "   222   ",
]

GRID_MEAT = [
    "  2222   ",
    " 233222  ",
    "23222222 ",
    "22222222 ",
    " 2222211 ",
    "  222 11 ",
]


def render_extruded_grid_item(grid, spec_map, out_path):
    scene = clear_scene()
    setup_ortho_top_camera(scene, 64, 64, ortho_scale=2.05)
    m_rim = make_mat("Outline", (0.07, 0.07, 0.09, 1.0), 0.75)

    mat_map = {}
    for k, spec in spec_map.items():
        col = spec[0]
        rgh = spec[1] if len(spec) > 1 else 0.5
        met = spec[2] if len(spec) > 2 else 0.0
        mat_map[k] = make_mat(f"Mat_{k}", col, rgh, met)

    rows = len(grid)
    cols = len(grid[0])
    cell = 0.21

    for r, row_str in enumerate(grid):
        for c, ch in enumerate(row_str):
            if ch == " " or ch not in mat_map:
                continue
            x = (c - (cols - 1) * 0.5) * cell
            y = ((rows - 1) * 0.5 - r) * cell
            add_box(f"Rim_{r}_{c}", (x, y, 0.0), (cell * 1.18, cell * 1.18, 0.14), m_rim, 0.01)
            add_box(f"Vox_{r}_{c}", (x, y, 0.12), (cell * 0.96, cell * 0.96, 0.24), mat_map[ch], 0.02)

    render_to(scene, out_path)


def render_all_items_and_blocks():
    # 1. Render all 3D Blocks (1..27) through true Isometric Camera
    block_ids = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 23, 24, 25, 26, 27]
    for bid in block_ids:
        scene = clear_scene()
        setup_isometric_block_camera(scene, 64)
        build_3d_block_model(bid)
        render_to(scene, os.path.join(ITEM_DIR, f"item_{bid}.png"))

    # 2. Shared Tool Handle & Tier Head Materials
    stick_spec = ((0.58, 0.40, 0.20, 1.0), 0.65, 0.0)
    tiers = {
        0: ((0.72, 0.52, 0.28, 1.0), (0.52, 0.36, 0.18, 1.0), 0.55, 0.0),  # Wood
        1: ((0.58, 0.60, 0.63, 1.0), (0.40, 0.42, 0.45, 1.0), 0.60, 0.1),  # Stone
        2: ((0.90, 0.92, 0.95, 1.0), (0.68, 0.70, 0.75, 1.0), 0.25, 0.85), # Iron
        3: ((0.20, 0.94, 0.96, 1.0), (0.12, 0.68, 0.74, 1.0), 0.15, 0.40), # Diamond
    }

    for t_idx, (head_col, guard_col, rgh, met) in tiers.items():
        t_map = {
            "1": stick_spec,
            "2": (head_col, rgh, met),
            "3": (guard_col, rgh, met),
        }

        render_extruded_grid_item(GRID_PICKAXE, t_map, os.path.join(ITEM_DIR, f"item_{201 + t_idx}.png"))
        render_extruded_grid_item(GRID_AXE, t_map, os.path.join(ITEM_DIR, f"item_{211 + t_idx}.png"))
        render_extruded_grid_item(GRID_SHOVEL, t_map, os.path.join(ITEM_DIR, f"item_{221 + t_idx}.png"))
        render_extruded_grid_item(GRID_SWORD, t_map, os.path.join(ITEM_DIR, f"item_{231 + t_idx}.png"))

    # 3. Render Resources, Ingots, Buckets & Food (100..116)
    GRID_STICK = [
        "      11",
        "     11 ",
        "    11  ",
        "   11   ",
        "  11    ",
        " 11     ",
        "11      ",
    ]
    render_extruded_grid_item(GRID_STICK, {"1": ((0.64, 0.44, 0.22, 1.0), 0.6, 0.0)}, os.path.join(ITEM_DIR, "item_100.png"))

    # 101: Coal, 102: Raw Iron, 103: Iron Ingot, 104: Raw Gold, 105: Gold Ingot, 106: Diamond
    render_extruded_grid_item(GRID_DIAMOND, {"2": ((0.14, 0.14, 0.16, 1.0), 0.5, 0.0), "3": ((0.26, 0.26, 0.30, 1.0), 0.4, 0.0)}, os.path.join(ITEM_DIR, "item_101.png"))
    render_extruded_grid_item(GRID_DIAMOND, {"2": ((0.76, 0.58, 0.44, 1.0), 0.45, 0.4), "3": ((0.90, 0.72, 0.58, 1.0), 0.35, 0.5)}, os.path.join(ITEM_DIR, "item_102.png"))
    render_extruded_grid_item(GRID_INGOT, {"2": ((0.78, 0.80, 0.84, 1.0), 0.25, 0.85), "3": ((0.95, 0.96, 0.98, 1.0), 0.18, 0.9)}, os.path.join(ITEM_DIR, "item_103.png"))
    render_extruded_grid_item(GRID_DIAMOND, {"2": ((0.88, 0.68, 0.14, 1.0), 0.3, 0.7), "3": ((1.0, 0.86, 0.24, 1.0), 0.2, 0.8)}, os.path.join(ITEM_DIR, "item_104.png"))
    render_extruded_grid_item(GRID_INGOT, {"2": ((0.92, 0.72, 0.12, 1.0), 0.22, 0.9), "3": ((1.0, 0.88, 0.28, 1.0), 0.15, 0.95)}, os.path.join(ITEM_DIR, "item_105.png"))
    render_extruded_grid_item(GRID_DIAMOND, {"2": ((0.14, 0.82, 0.88, 1.0), 0.15, 0.3), "3": ((0.55, 0.98, 1.0, 1.0), 0.1, 0.4)}, os.path.join(ITEM_DIR, "item_106.png"))

    # 107: Iron Bucket & 108: Water Bucket
    bkt_spec = ((0.78, 0.80, 0.84, 1.0), 0.28, 0.85)
    render_extruded_grid_item(GRID_BUCKET, {"2": bkt_spec, "3": ((0.34, 0.36, 0.40, 1.0), 0.5, 0.6)}, os.path.join(ITEM_DIR, "item_107.png"))
    render_extruded_grid_item(GRID_BUCKET, {"2": bkt_spec, "3": ((0.16, 0.54, 0.98, 1.0), 0.15, 0.0)}, os.path.join(ITEM_DIR, "item_108.png"))

    # 110..116: Food & Mob Drops
    bone_spec = ((0.95, 0.93, 0.88, 1.0), 0.4, 0.0)
    render_extruded_grid_item(GRID_MEAT, {"1": bone_spec, "2": ((0.94, 0.56, 0.58, 1.0), 0.45, 0.0), "3": ((0.98, 0.74, 0.76, 1.0), 0.4, 0.0)}, os.path.join(ITEM_DIR, "item_110.png"))
    render_extruded_grid_item(GRID_MEAT, {"1": bone_spec, "2": ((0.82, 0.52, 0.24, 1.0), 0.4, 0.0), "3": ((0.95, 0.70, 0.38, 1.0), 0.35, 0.0)}, os.path.join(ITEM_DIR, "item_111.png"))
    render_extruded_grid_item(GRID_MEAT, {"1": bone_spec, "2": ((0.82, 0.22, 0.24, 1.0), 0.45, 0.0), "3": ((0.95, 0.42, 0.44, 1.0), 0.4, 0.0)}, os.path.join(ITEM_DIR, "item_112.png"))
    render_extruded_grid_item(GRID_MEAT, {"1": bone_spec, "2": ((0.58, 0.30, 0.14, 1.0), 0.4, 0.0), "3": ((0.76, 0.44, 0.22, 1.0), 0.35, 0.0)}, os.path.join(ITEM_DIR, "item_113.png"))
    render_extruded_grid_item(GRID_APPLE, {"1": stick_spec, "2": ((0.92, 0.16, 0.18, 1.0), 0.25, 0.0), "3": ((1.0, 0.65, 0.65, 1.0), 0.18, 0.0)}, os.path.join(ITEM_DIR, "item_114.png"))
    render_extruded_grid_item(GRID_MEAT, {"1": ((0.34, 0.52, 0.24, 1.0), 0.6, 0.0), "2": ((0.58, 0.32, 0.22, 1.0), 0.6, 0.0), "3": ((0.42, 0.56, 0.26, 1.0), 0.6, 0.0)}, os.path.join(ITEM_DIR, "item_115.png"))
    render_extruded_grid_item(GRID_DIAMOND, {"2": ((0.38, 0.38, 0.40, 1.0), 0.7, 0.0), "3": ((0.52, 0.52, 0.55, 1.0), 0.65, 0.0)}, os.path.join(ITEM_DIR, "item_116.png"))


if __name__ == "__main__":
    render_gui_panels()
    render_hud_icons()
    render_all_items_and_blocks()
    print("=== ALL PHASE 2 BLENDER UI & 3D ICON ASSETS RENDERED SUCCESSFULLY ===")
