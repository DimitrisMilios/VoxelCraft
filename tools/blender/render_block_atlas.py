"""
Headless Blender 5.2 Pipeline for VoxelCraft Phase 3:
Constructs 29 3D micro-relief block tiles side-by-side in Blender (each 1.0 x 1.0 unit)
with 3D geometry, bevels, and Principled BSDF materials, and bakes the complete
`assets/textures/block_atlas.png` (928x32, 29 tiles @ 32x32 px) + `assets/textures/water_tile.png` (64x64).

Usage:
  blender --background --python tools/blender/render_block_atlas.py
"""

import math
import os
import random
import bpy

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX_DIR = os.path.join(ROOT_DIR, "assets", "textures")
os.makedirs(TEX_DIR, exist_ok=True)

NUM_TILES = 29
TILE_PX = 32


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"

    world = bpy.data.worlds.new("AtlasWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.75, 0.78, 0.82, 1.0)
        bg.inputs[1].default_value = 0.45
    return scene


def make_mat(name, rgba, roughness=0.65, metallic=0.0, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
        if emission > 0.0 and "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = rgba
            bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def add_tile_box(name, tx, lx, ly, lz, sx, sy, sz, mat, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(tx + lx, ly, lz))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        bev = obj.modifiers.new(name="Bevel", type="BEVEL")
        bev.width = bevel
        bev.segments = 2
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)
    return obj


def build_tile_0_grass_top(tx, rng):
    m_base = make_mat("GrassBase", (0.28, 0.62, 0.20, 1.0), 0.75)
    m_hi = make_mat("GrassHi", (0.38, 0.76, 0.26, 1.0), 0.65)
    m_dk = make_mat("GrassDk", (0.20, 0.48, 0.14, 1.0), 0.80)
    add_tile_box("G0", tx, 0, 0, 0.0, 1.0, 1.0, 0.10, m_base)
    for r in range(8):
        for c in range(8):
            if (r + c) % 2 == 0 or rng.random() < 0.35:
                ox = -0.4375 + c * 0.125
                oy = -0.4375 + r * 0.125
                mat = m_hi if rng.random() < 0.55 else m_dk
                add_tile_box("Blade", tx, ox, oy, 0.06, 0.11, 0.11, 0.06, mat, 0.01)


def build_tile_1_grass_side(tx, rng):
    m_dirt = make_mat("GSDirt", (0.48, 0.32, 0.18, 1.0), 0.80)
    m_peb = make_mat("GSPeb", (0.36, 0.24, 0.13, 1.0), 0.85)
    m_grass = make_mat("GSTop", (0.34, 0.70, 0.24, 1.0), 0.65)
    add_tile_box("DirtBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.10, m_dirt)
    for _ in range(18):
        ox = rng.uniform(-0.42, 0.42)
        oy = rng.uniform(-0.42, 0.15)
        add_tile_box("Peb", tx, ox, oy, 0.05, 0.12, 0.10, 0.05, m_peb, 0.01)
    # Overhanging 3D grass skirt at the top (+Y in image space)
    skirts = [0.28, 0.36, 0.24, 0.40, 0.30, 0.22, 0.35, 0.26]
    for i, h in enumerate(skirts):
        ox = -0.4375 + i * 0.125
        add_tile_box("Skirt", tx, ox, 0.5 - h * 0.5, 0.08, 0.13, h, 0.08, m_grass, 0.015)


def build_tile_2_dirt(tx, rng):
    m_dirt = make_mat("DirtBase", (0.48, 0.32, 0.18, 1.0), 0.80)
    m_hi = make_mat("DirtHi", (0.58, 0.40, 0.24, 1.0), 0.75)
    m_dk = make_mat("DirtDk", (0.35, 0.22, 0.12, 1.0), 0.85)
    add_tile_box("Dirt", tx, 0, 0, 0.0, 1.0, 1.0, 0.10, m_dirt)
    for r in range(8):
        for c in range(8):
            if rng.random() < 0.55:
                ox = -0.4375 + c * 0.125
                oy = -0.4375 + r * 0.125
                mat = m_hi if rng.random() < 0.5 else m_dk
                add_tile_box("Clod", tx, ox, oy, 0.06, 0.12, 0.11, 0.06, mat, 0.015)


def build_tile_3_stone(tx, rng, ore_mat=None):
    m_st = make_mat(f"Stone_{tx}", (0.50, 0.52, 0.55, 1.0), 0.72)
    m_hi = make_mat(f"StoneHi_{tx}", (0.60, 0.62, 0.65, 1.0), 0.68)
    m_dk = make_mat(f"StoneDk_{tx}", (0.38, 0.40, 0.43, 1.0), 0.78)
    add_tile_box("StoneBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.10, m_st)
    # Stratified horizontal 3D rock plates
    for r in range(8):
        oy = -0.4375 + r * 0.125
        for seg in range(3):
            ox = -0.32 + seg * 0.32 + rng.uniform(-0.04, 0.04)
            mat = m_hi if (r + seg) % 2 == 0 else m_dk
            add_tile_box("Strata", tx, ox, oy, 0.05, 0.30, 0.11, 0.05, mat, 0.01)

    if ore_mat is not None:
        spots = [(-0.24, 0.22), (0.20, 0.26), (-0.05, 0.02), (-0.26, -0.22), (0.22, -0.20)]
        for ox, oy in spots:
            add_tile_box("OreVein", tx, ox, oy, 0.10, 0.18, 0.16, 0.10, ore_mat, 0.02)


def build_tile_4_wood_side(tx):
    m_bark1 = make_mat("Bark1", (0.38, 0.25, 0.13, 1.0), 0.78)
    m_bark2 = make_mat("Bark2", (0.28, 0.18, 0.09, 1.0), 0.85)
    add_tile_box("BarkBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.10, m_bark2)
    for c in range(8):
        ox = -0.4375 + c * 0.125
        h = 0.08 if c % 2 == 0 else 0.04
        mat = m_bark1 if c % 2 == 0 else m_bark2
        add_tile_box("Ridge", tx, ox, 0.0, h, 0.10, 1.0, 0.08, mat, 0.01)


def build_tile_5_wood_top(tx):
    m_bark = make_mat("TopBark", (0.34, 0.22, 0.11, 1.0), 0.80)
    m_wood1 = make_mat("Heart1", (0.72, 0.56, 0.34, 1.0), 0.60)
    m_wood2 = make_mat("Heart2", (0.58, 0.42, 0.24, 1.0), 0.65)
    add_tile_box("OuterBark", tx, 0, 0, 0.0, 1.0, 1.0, 0.10, m_bark)
    add_tile_box("Ring1", tx, 0, 0, 0.04, 0.80, 0.80, 0.10, m_wood1, 0.01)
    add_tile_box("Ring2", tx, 0, 0, 0.06, 0.56, 0.56, 0.10, m_wood2, 0.01)
    add_tile_box("Ring3", tx, 0, 0, 0.08, 0.34, 0.34, 0.10, m_wood1, 0.01)
    add_tile_box("Core", tx, 0, 0, 0.10, 0.14, 0.14, 0.10, m_wood2, 0.01)


def build_tile_6_leaves(tx, rng):
    m_dk = make_mat("LeafDk", (0.12, 0.34, 0.10, 1.0), 0.80)
    m_md = make_mat("LeafMd", (0.20, 0.54, 0.18, 1.0), 0.65)
    m_hi = make_mat("LeafHi", (0.30, 0.68, 0.24, 1.0), 0.55)
    add_tile_box("LeafBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.10, m_dk)
    for r in range(8):
        for c in range(8):
            if (r * 3 + c * 5) % 4 != 0:
                ox = -0.4375 + c * 0.125
                oy = -0.4375 + r * 0.125
                mat = m_hi if (r + c) % 2 == 0 else m_md
                add_tile_box("Leaf", tx, ox, oy, 0.07, 0.12, 0.12, 0.08, mat, 0.015)


def build_tile_7_sand(tx):
    m_s1 = make_mat("Sand1", (0.88, 0.82, 0.54, 1.0), 0.60)
    m_s2 = make_mat("Sand2", (0.80, 0.73, 0.46, 1.0), 0.65)
    add_tile_box("SandBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.10, m_s2)
    for r in range(8):
        oy = -0.4375 + r * 0.125
        if r % 2 == 0:
            add_tile_box("Ripple", tx, 0.0, oy, 0.05, 1.0, 0.10, 0.06, m_s1, 0.01)


def build_tile_8_cobble(tx, mossy=False):
    m_mortar = make_mat(f"Mortar_{tx}", (0.20, 0.46, 0.18, 1.0) if mossy else (0.24, 0.25, 0.27, 1.0), 0.85)
    m_c1 = make_mat(f"Cob1_{tx}", (0.52, 0.54, 0.57, 1.0), 0.68)
    m_c2 = make_mat(f"Cob2_{tx}", (0.42, 0.44, 0.47, 1.0), 0.72)
    add_tile_box("MortarBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.08, m_mortar)
    stones = [
        (-0.28, 0.30, 0.36, 0.30, m_c1), (0.18, 0.32, 0.46, 0.28, m_c2),
        (-0.32, 0.0, 0.30, 0.26, m_c2), (0.04, 0.02, 0.34, 0.28, m_c1), (0.36, -0.02, 0.24, 0.28, m_c1),
        (-0.24, -0.30, 0.42, 0.30, m_c1), (0.24, -0.32, 0.42, 0.28, m_c2),
    ]
    for ox, oy, sx, sy, mat in stones:
        add_tile_box("CobStone", tx, ox, oy, 0.08, sx, sy, 0.10, mat, 0.025)


def build_tile_9_planks(tx):
    m_seam = make_mat("PlankSeam", (0.36, 0.24, 0.12, 1.0), 0.80)
    m_p1 = make_mat("Plank1", (0.72, 0.54, 0.32, 1.0), 0.58)
    m_p2 = make_mat("Plank2", (0.66, 0.48, 0.28, 1.0), 0.62)
    add_tile_box("SeamBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.08, m_seam)
    for row in range(4):
        oy = -0.375 + row * 0.25
        mat = m_p1 if row % 2 == 0 else m_p2
        split = 0.10 if row % 2 == 0 else -0.15
        w1 = (split + 0.5) - 0.02
        w2 = (0.5 - split) - 0.02
        add_tile_box("BoardL", tx, -0.5 + w1 * 0.5, oy, 0.06, w1, 0.22, 0.08, mat, 0.01)
        add_tile_box("BoardR", tx, 0.5 - w2 * 0.5, oy, 0.06, w2, 0.22, 0.08, mat, 0.01)


def build_tile_10_snow(tx):
    m_s1 = make_mat("Snow1", (0.94, 0.97, 1.0, 1.0), 0.45)
    m_s2 = make_mat("Snow2", (0.84, 0.90, 0.98, 1.0), 0.50)
    add_tile_box("SnowBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.10, m_s2)
    for ox, oy in [(-0.22, 0.22), (0.22, 0.18), (-0.18, -0.22), (0.20, -0.20), (0.0, 0.0)]:
        add_tile_box("Drift", tx, ox, oy, 0.05, 0.38, 0.32, 0.06, m_s1, 0.02)


def build_tile_11_glowstone(tx):
    m_dk = make_mat("GlowDk", (0.48, 0.30, 0.10, 1.0), 0.70)
    m_gl = make_mat("GlowHi", (1.0, 0.86, 0.32, 1.0), 0.25, 0.1, 0.8)
    add_tile_box("GlowBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.08, m_dk)
    for r in range(4):
        for c in range(4):
            ox = -0.36 + c * 0.24
            oy = -0.36 + r * 0.24
            add_tile_box("Shard", tx, ox, oy, 0.08, 0.18, 0.18, 0.10, m_gl, 0.02)


def build_tile_16_craft_top(tx):
    m_rim = make_mat("CTRim", (0.42, 0.28, 0.14, 1.0), 0.65)
    m_cell = make_mat("CTCell", (0.76, 0.56, 0.32, 1.0), 0.55)
    add_tile_box("CTBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.08, m_rim)
    for r in range(3):
        for c in range(3):
            ox = -0.26 + c * 0.26
            oy = -0.26 + r * 0.26
            add_tile_box("GridCell", tx, ox, oy, 0.06, 0.21, 0.21, 0.08, m_cell, 0.01)


def build_tile_17_craft_side(tx):
    build_tile_9_planks(tx)
    m_post = make_mat("CTPost", (0.34, 0.22, 0.11, 1.0), 0.75)
    m_iron = make_mat("CTTool", (0.82, 0.84, 0.88, 1.0), 0.30, 0.85)
    add_tile_box("PostL", tx, -0.42, 0, 0.08, 0.14, 1.0, 0.08, m_post)
    add_tile_box("PostR", tx, 0.42, 0, 0.08, 0.14, 1.0, 0.08, m_post)
    add_tile_box("TopBand", tx, 0, 0.40, 0.09, 1.0, 0.18, 0.08, m_post)
    add_tile_box("Saw", tx, -0.14, 0.0, 0.11, 0.16, 0.42, 0.06, m_iron, 0.01)
    add_tile_box("Hammer", tx, 0.16, 0.05, 0.11, 0.22, 0.14, 0.06, m_iron, 0.01)


def build_tile_18_furnace_front(tx):
    build_tile_8_cobble(tx, False)
    m_hole = make_mat("FurnHole", (0.10, 0.10, 0.12, 1.0), 0.85)
    m_fire = make_mat("FurnFire", (1.0, 0.52, 0.12, 1.0), 0.30, 0.0, 0.85)
    add_tile_box("UpperHole", tx, 0.0, 0.16, 0.10, 0.56, 0.34, 0.08, m_hole)
    add_tile_box("FireCore", tx, 0.0, -0.22, 0.11, 0.52, 0.24, 0.08, m_fire)


def build_tile_19_chest_front(tx, with_latch=True):
    m_rim = make_mat(f"ChRim_{tx}", (0.24, 0.15, 0.07, 1.0), 0.75)
    m_wood = make_mat(f"ChWood_{tx}", (0.72, 0.48, 0.20, 1.0), 0.55)
    m_gold = make_mat(f"ChGold_{tx}", (0.98, 0.84, 0.22, 1.0), 0.25, 0.85)
    add_tile_box("ChBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.08, m_rim)
    add_tile_box("ChTop", tx, 0, 0.24, 0.06, 0.82, 0.34, 0.08, m_wood, 0.01)
    add_tile_box("ChBot", tx, 0, -0.20, 0.06, 0.82, 0.44, 0.08, m_wood, 0.01)
    if with_latch:
        add_tile_box("Latch", tx, 0, 0.04, 0.11, 0.16, 0.24, 0.08, m_gold, 0.01)


def build_tile_21_torch(tx):
    m_wood = make_mat("TorchWood", (0.60, 0.42, 0.20, 1.0), 0.65)
    m_fire = make_mat("TorchFire", (1.0, 0.82, 0.22, 1.0), 0.20, 0.0, 0.90)
    add_tile_box("TBase", tx, 0, -0.12, 0.0, 1.0, 0.76, 0.08, m_wood)
    add_tile_box("THead", tx, 0, 0.32, 0.06, 1.0, 0.36, 0.10, m_fire)


def build_tile_22_bed(tx):
    m_pil = make_mat("BedPil", (0.95, 0.95, 0.97, 1.0), 0.50)
    m_red = make_mat("BedRed", (0.84, 0.16, 0.18, 1.0), 0.55)
    add_tile_box("Pillow", tx, 0, 0.32, 0.06, 0.92, 0.32, 0.08, m_pil, 0.01)
    add_tile_box("Blanket", tx, 0, -0.16, 0.06, 0.96, 0.66, 0.08, m_red, 0.01)


def build_tile_23_door(tx):
    m_wood = make_mat("DoorW", (0.68, 0.48, 0.24, 1.0), 0.58)
    m_win = make_mat("DoorWin", (0.20, 0.14, 0.07, 1.0), 0.80)
    add_tile_box("DoorBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.08, m_wood)
    add_tile_box("Win1", tx, -0.18, 0.20, 0.06, 0.24, 0.36, 0.06, m_win)
    add_tile_box("Win2", tx, 0.18, 0.20, 0.06, 0.24, 0.36, 0.06, m_win)


def build_tile_24_ladder(tx):
    m_bg = make_mat("LadBg", (0.24, 0.18, 0.10, 1.0), 0.85)
    m_rung = make_mat("LadRung", (0.74, 0.54, 0.28, 1.0), 0.55)
    add_tile_box("LadBack", tx, 0, 0, 0.0, 1.0, 1.0, 0.06, m_bg)
    add_tile_box("RailL", tx, -0.34, 0, 0.06, 0.14, 1.0, 0.08, m_rung)
    add_tile_box("RailR", tx, 0.34, 0, 0.06, 0.14, 1.0, 0.08, m_rung)
    for oy in (-0.36, -0.12, 0.12, 0.36):
        add_tile_box("Rung", tx, 0, oy, 0.08, 0.82, 0.12, 0.08, m_rung, 0.01)


def build_tile_25_tnt(tx):
    m_red = make_mat("TNTRed", (0.86, 0.18, 0.14, 1.0), 0.55)
    m_wht = make_mat("TNTWht", (0.94, 0.94, 0.96, 1.0), 0.50)
    m_blk = make_mat("TNTBlk", (0.14, 0.14, 0.16, 1.0), 0.75)
    add_tile_box("TNTBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.08, m_red)
    for c in range(4):
        ox = -0.375 + c * 0.25
        add_tile_box("Stick", tx, ox, 0, 0.05, 0.22, 1.0, 0.06, m_red, 0.01)
    add_tile_box("Label", tx, 0, 0, 0.08, 1.0, 0.34, 0.06, m_wht)
    add_tile_box("Text", tx, 0, 0, 0.10, 0.64, 0.16, 0.06, m_blk)


def build_tile_26_sandstone(tx):
    m_base = make_mat("SSBase", (0.86, 0.78, 0.52, 1.0), 0.58)
    m_cap = make_mat("SSCap", (0.92, 0.86, 0.62, 1.0), 0.52)
    m_seam = make_mat("SSSeam", (0.68, 0.60, 0.38, 1.0), 0.70)
    add_tile_box("SSBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.08, m_seam)
    add_tile_box("TopCap", tx, 0, 0.34, 0.06, 0.98, 0.28, 0.08, m_cap, 0.01)
    add_tile_box("MidBlk", tx, 0, -0.02, 0.06, 0.96, 0.34, 0.08, m_base, 0.01)
    add_tile_box("BotBlk", tx, 0, -0.36, 0.06, 0.96, 0.26, 0.08, m_base, 0.01)


def build_tile_28_cactus(tx):
    m_dk = make_mat("CacDk", (0.12, 0.44, 0.16, 1.0), 0.65)
    m_rib = make_mat("CacRib", (0.20, 0.62, 0.24, 1.0), 0.55)
    m_sp = make_mat("CacSp", (0.88, 0.84, 0.62, 1.0), 0.50)
    add_tile_box("CacBg", tx, 0, 0, 0.0, 1.0, 1.0, 0.08, m_dk)
    for c in range(4):
        ox = -0.375 + c * 0.25
        add_tile_box("Rib", tx, ox, 0, 0.06, 0.16, 1.0, 0.08, m_rib, 0.01)
        for oy in (-0.32, 0.0, 0.32):
            add_tile_box("Spine", tx, ox, oy, 0.10, 0.06, 0.06, 0.06, m_sp)


def render_block_atlas():
    scene = clear_scene()
    rng = random.Random(2026)

    for idx in range(NUM_TILES):
        tx = float(idx)
        if idx == 0:
            build_tile_0_grass_top(tx, rng)
        elif idx == 1:
            build_tile_1_grass_side(tx, rng)
        elif idx == 2:
            build_tile_2_dirt(tx, rng)
        elif idx == 3:
            build_tile_3_stone(tx, rng)
        elif idx == 4:
            build_tile_4_wood_side(tx)
        elif idx == 5:
            build_tile_5_wood_top(tx)
        elif idx == 6:
            build_tile_6_leaves(tx, rng)
        elif idx == 7:
            build_tile_7_sand(tx)
        elif idx == 8:
            build_tile_8_cobble(tx, False)
        elif idx == 9:
            build_tile_9_planks(tx)
        elif idx == 10:
            build_tile_10_snow(tx)
        elif idx == 11:
            build_tile_11_glowstone(tx)
        elif idx == 12:
            build_tile_3_stone(tx, rng, make_mat("CoalOre", (0.08, 0.08, 0.10, 1.0), 0.40, 0.1))
        elif idx == 13:
            build_tile_3_stone(tx, rng, make_mat("IronOre", (0.86, 0.64, 0.46, 1.0), 0.35, 0.55))
        elif idx == 14:
            build_tile_3_stone(tx, rng, make_mat("GoldOre", (1.0, 0.82, 0.14, 1.0), 0.22, 0.88))
        elif idx == 15:
            build_tile_3_stone(tx, rng, make_mat("DiamOre", (0.18, 0.94, 0.98, 1.0), 0.15, 0.35))
        elif idx == 16:
            build_tile_16_craft_top(tx)
        elif idx == 17:
            build_tile_17_craft_side(tx)
        elif idx == 18:
            build_tile_18_furnace_front(tx)
        elif idx == 19:
            build_tile_19_chest_front(tx, True)
        elif idx == 20:
            build_tile_19_chest_front(tx, False)
        elif idx == 21:
            build_tile_21_torch(tx)
        elif idx == 22:
            build_tile_22_bed(tx)
        elif idx == 23:
            build_tile_23_door(tx)
        elif idx == 24:
            build_tile_24_ladder(tx)
        elif idx == 25:
            build_tile_25_tnt(tx)
        elif idx == 26:
            build_tile_26_sandstone(tx)
        elif idx == 27:
            build_tile_8_cobble(tx, True)
        elif idx == 28:
            build_tile_28_cactus(tx)

    # Orthographic strip camera covering x in [-0.5, NUM_TILES - 0.5], y in [-0.5, +0.5]
    scene.render.resolution_x = NUM_TILES * TILE_PX
    scene.render.resolution_y = TILE_PX
    cam_data = bpy.data.cameras.new("AtlasOrthoCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = float(NUM_TILES)
    cam_obj = bpy.data.objects.new("AtlasOrthoCam", cam_data)
    scene.collection.objects.link(cam_obj)
    cam_obj.location = ((NUM_TILES - 1) * 0.5, 0.0, 5.0)
    cam_obj.rotation_euler = (0.0, 0.0, 0.0)
    scene.camera = cam_obj

    # Directional Sun for crisp 3D micro-relief highlights and shadows
    sun_data = bpy.data.lights.new("AtlasKeySun", type="SUN")
    sun_data.energy = 2.4
    sun_data.angle = math.radians(10.0)
    sun_obj = bpy.data.objects.new("AtlasKeySun", sun_data)
    scene.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(24.0), math.radians(-22.0), math.radians(12.0))

    fill_data = bpy.data.lights.new("AtlasFillSun", type="SUN")
    fill_data.energy = 0.85
    fill_obj = bpy.data.objects.new("AtlasFillSun", fill_data)
    scene.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = (math.radians(-18.0), math.radians(18.0), 0.0)

    out_atlas = os.path.join(TEX_DIR, "block_atlas.png")
    scene.render.filepath = out_atlas
    bpy.ops.render.render(write_still=True)
    print(f"Rendered 3D Block Atlas: {out_atlas}")


if __name__ == "__main__":
    render_block_atlas()
    print("=== PHASE 3 BLENDER 3D BLOCK ATLAS RENDERED SUCCESSFULLY ===")
