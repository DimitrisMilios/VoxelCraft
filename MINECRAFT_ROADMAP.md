# VoxelCraft — Authentic Minecraft Overhaul Roadmap (Blender-Powered Edition)

This document defines the complete, step-by-step engineering specification to transform **VoxelCraft** into an authentic Minecraft experience across **3 Major Phases**:

1. **Phase 1: Core Minecraft Gameplay Mechanics & World Structures** — **✅ COMPLETED (`Steps 1.1 – 1.5`)**
2. **Phase 2: Blender-Rendered Minecraft UI, HUD & 3D Item Icon Overhaul** *(Next Up)*
3. **Phase 3: Blender-Baked Block & Material Texture Atlas Overhaul**

> **Blender 5.2 Automated Pipeline:** We have detected **`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`** on your system. All UI panels, recessed slots, HUD status icons (Hearts, Hunger Drumsticks, Oxygen Bubbles), 3D Isometric Block/Tool Icons, and the entire Block Texture Atlas will be generated and rendered using **headless Blender Python scripts (`tools/blender/*.py`)** with studio lighting, orthographic cameras, Cycles/EEVEE baking, and saved as crisp `res://assets/` PNG textures!

---

## Current Baseline (What We Already Have vs. What We Are Upgrading)

| Domain | Already Implemented in VoxelCraft | What Needs Upgrading for Authentic Minecraft |
| :--- | :--- | :--- |
| **Water & Physics** | Single `WATER` block ID (`0.88` flat top), cellular-automata spread that creates infinite full water blocks horizontally, basic swim & shoreline hop. | **Finite 8-level water (`Source` + `Flowing 7..1` + `Falling`)**, **smooth sloped corner vertices**, **animated flowing surface**, **water current push**, **water drainage when source is blocked**, **Iron Bucket / Water Bucket**, and **depth-aware buoyancy**. |
| **Mining & Items** | Raycast block breaking (`0–100%`), Pickaxe tier rules (`Wood`, `Stone`, `Iron`, `Diamond`), instant teleport into inventory. | **10-stage crack overlay on the 3D block**, **3D spinning/bobbing dropped item entities** on the ground (magnetic pickup + `Q` drop key + floating in water currents), and **tool durability bars**. |
| **Survival & Combat** | Sandbox immortality, passive Pigs & Cows with wander/panic/feed AI. | **10 Hearts (HP)**, **10 Hunger Drumsticks**, **10 Oxygen Bubbles underwater**, fall damage, **Raw/Cooked Meat & Bread**, **Swords**, and **Hostile Night/Cave Mobs (Zombies, Skeletons, Creepers, Spiders)**. |
| **Functional Blocks** | `Crafting Table` (`3×3`) and `Furnace` (real-time smelting + `OmniLight3D`). | **Chest (`27-slot` persistent storage)**, **Torches (floor & wall placement)**, **Doors**, **Ladders**, **Beds (sleep to skip night + set spawn)**, and **TNT explosions**. |
| **World & Structures** | Multithreaded `16×256×16` chunks, 3D caves, 4 ore tiers, Oak & Pine trees, Zstd persistence. | **Distinct Biomes (Plains, Desert with Cacti, Forest, Snowy Taiga)**, **Villages**, **Underground Dungeons/Mineshafts with Loot Chests**, and **deep Lava pools**. |
| **UI & Inventory (Blender Rendered)** | Functional dark-panel `E` inventory, `2×2`/`3×3` crafting, Furnace modal, text-badge item slots. | **Blender-rendered 3D beveled stone-grey GUI panels & slots**, **Blender-rendered 3D Hearts/Drumsticks/Bubbles**, **orthographic Blender-rendered 3D Isometric Block & Tool icons**, **Armor slots + Player preview**, and **Shift-click transfer**. |
| **Block Textures (Blender Baked)** | Procedural GDScript noise tiles in `VoxelAtlasBuilder`. | **Blender 5.2 procedural shader & micro-relief baked `res://assets/textures/block_atlas.png`** for every block face, ore crystal, wood bark, cobblestone mortar, crafting table, and lit/unlit furnace. |

---

## PHASE 1: Core Minecraft Mechanics & World Structures

### Step 1.1 — Authentic Flowing Water, Sloped Corners, Drainage & Buoyancy (FIRST PRIORITY)

#### Why Current Water Feels Wrong
Currently, `BlockRegistry.BlockType.WATER` is a single flat block that copies itself into adjacent air blocks as new full source blocks. When placed on flat ground or near a corner, it floods everything in its path instead of spreading a finite distance with a sloped surface.

#### How We Will Architect Authentic Minecraft Water
```
[Water Source (8/8)] ---> [Flow 7/8] ---> [Flow 6/8] ---> ... ---> [Flow 1/8 Edge]
       |                                                                |
       +-- Corners smoothly average neighbor heights (Sloped Mesh!) -----+
```

1. **8-Level Finite Water System (`Source`, `Flowing 1..7`, and `Falling Water`):**
   - **Water Source (`WATER`, level `8`):** Full water source (`7/8` block height = `0.875`). Never duplicates itself horizontally unless **2 or more Water Source blocks** touch orthogonally over a solid floor (Minecraft's classic `2×2` infinite spring rule).
   - **Flowing Water (`WATER_FLOW_1` .. `WATER_FLOW_7`):**
     - Spreads horizontally up to **7 blocks** away from a Source block, decreasing level by `1` per block (`0.78`, `0.67`, `0.56`, `0.45`, `0.34`, `0.23`, `0.12`).
     - At level `1`, horizontal spreading **stops completely** — it never fills the world!
   - **Downward Priority & Ledge Finding:**
     - If air or replaceable water exists directly below (`y - 1`), water flows **straight down** as a full vertical waterfall column (`WATER_FALLING`), which then resets horizontal spread distance to `7` at the bottom of the waterfall.
     - **Corner / Ledge Seeking (Path of Least Resistance):** When spreading horizontally, water scans within a **4-block radius** for the nearest drop-off/corner ledge and prioritizes flowing toward that drop-off.
   - **Automatic Water Drainage (Receding Animation):**
     - When a `Water Source` is scooped up or blocked off, any `Flowing Water` tile that is no longer supported by a strictly higher neighbor (`level + 1`) or water above (`y + 1`) decays step-by-step (`7 → 5 → 3 → 1 → AIR`) until it drains away completely.

2. **Sloped Corner Vertex Meshing (`VoxelChunk`):**
   - Instead of rendering water as flat stair-steps, `VoxelChunk` calculates the **exact height of each of the 4 top corners (`NW`, `NE`, `SE`, `SW`)** of a water cell by averaging the water heights of the **4 cells sharing that vertex**.
   - If any of the 4 cells around a corner has water directly above it (`y + 1`), that corner snaps to `1.0` so waterfalls connect seamlessly without air gaps.
   - **Result:** Water flowing toward a corner or diagonally across land forms a **smooth diagonal slope** pointing in the exact direction of flow.

3. **Animated Flowing Water Shader & Directional Current Push:**
   - **Visual Flow Animation:** Upgrade the shared water material to scroll and ripple UV coordinates continuously so water visibly animates downward on waterfalls and outward on slopes.
   - **Flow Vector & Current Push:** Each flowing water block computes a 3D horizontal flow vector from higher neighbor levels toward lower neighbor levels. Standing in flowing water gently **pushes the player (and mobs/items) along the current** toward the lower corner/drop-off.

4. **Robust Depth-Proportioned Buoyancy & Iron Buckets:**
   - **Proportional Buoyancy (`PlayerController`):**
     - Computes exact local water surface height (`y + water_level_ratio`) at the player's X/Z position.
     - Shallow ankle-deep flowing water (`level 1–2`) applies mild water drag and current drift without forcing deep-water swimming.
     - Waist/chest-deep water (`level 4–8`) applies smooth spring-damped Archimedes buoyancy, surface bobbing when holding `Space`, and effortless step-up exit onto shorelines.
   - **Craftable `Bucket` & `Water Bucket` (`InventoryManager` & `BlockInteractor`):**
     - Craft an **Empty Bucket** (`3 Iron Ingots` in a `V` shape).
     - Right-click any **Water Source** block with an Empty Bucket to pick it up into a **Water Bucket** (causing the stream to drain away!).
     - Right-click any block face with a **Water Bucket** to place a new **Water Source** block and watch it slope and cascade down corners.

---

### Step 1.2 — 3D Dropped Item Entities, 10-Stage Block Cracking & Tool Durability
1. **10-Stage Block Crack Overlay (`BlockInteractor`):**
   - Render a slightly inflated (`1.002×`) translucent cube over the targeted block with a **10-stage crack texture (`stage 0..9`)** that grows across all 6 faces as `break_progress` advances from `0%` to `100%`.
2. **3D Floating & Bobbing Dropped Items (`DroppedItemEntity`):**
   - Breaking a block (with the valid tool) or pressing **`Q`** spawns a miniature `0.28×0.28×0.28` 3D block/item mesh in the world.
   - Physics: pops upward with slight random impulse, collides with terrain, **floats and drifts inside flowing water currents**, spins slowly (`90°/sec`), bobs vertically with a sine wave, stacks with nearby identical drops, and magnetically flies into the player's inventory when within `1.75m`.
3. **Tool Durability System (`InventoryManager`):**
   - Wood (`60` uses), Stone (`132` uses), Iron (`251` uses), and Diamond (`1562` uses).
   - Displays a green-to-red durability bar at the bottom of damaged tool slots and plays a tool-break sound when reaching `0`.

---

### Step 1.3 — Survival Stats: Health, Hunger, Oxygen, Food & Combat
1. **Player Survival Vitals (`PlayerVitals`):**
   - **Health (`20 HP` / `10 Hearts`):** Takes damage from fall distance (`max(0, fall_blocks - 3)`), drowning, cactus, lava, and mob attacks. Camera tilts and flashes red on hit.
   - **Hunger (`20 Food` / `10 Drumsticks`):** Slowly drains from sprinting, jumping, mining, and natural healing. When Hunger `>= 18`, regenerates `1 HP` every `4 seconds`. When Hunger `== 0`, slowly starves down to `1 HP`.
   - **Oxygen (`10 Bubbles`):** Drains over `15 seconds` when the camera eye is submerged in water; refills on surfacing.
2. **Food & Eating Mechanics:**
   - Pigs drop **Raw Porkchop** (`1–3`); Cows drop **Raw Beef** (`1–3`); Oak Leaves have a chance to drop **Red Apples**; Wheat crafts **Bread**.
   - Smelt Raw Porkchop → **Cooked Porkchop** (`+8 Hunger`), Raw Beef → **Steak** (`+8 Hunger`) in the Furnace.
   - Hold `Right-Click` with food in hand to play a crunching animation/sound and restore Hunger.
3. **Swords & Hostile Night/Cave Mobs:**
   - Craftable **Wood, Stone, Iron, and Diamond Swords** with sweep knockback and high attack damage.
   - **Hostile Mobs (`HostileMob`):** Spawn in low light (at night or inside dark caves):
     - **Zombie:** Chases player, deals melee damage, burns in daylight.
     - **Skeleton:** Keeps distance and fires **3D Arrows**.
     - **Creeper:** Approaches silently, flashes white + hisses when within `3m`, and explodes blocks if not knocked back in time.
     - **Spider:** Fast movement and can climb vertical walls.

---

### Step 1.4 — Functional Blocks: Chests, Torches, Beds, Doors, Ladders & TNT
1. **Chest (`27-Slot` World Storage):**
   - Crafted from `8 Wood Planks` in a ring. Stores `27` persistent item stacks per world block coordinate (saved inside chunk persistence) and drops its contents if broken.
2. **Torches (Floor & Wall Mounted):**
   - Crafted from `1 Coal + 1 Stick` → `4 Torches`. Can be placed on top of blocks (straight torch) or on the 4 vertical side faces of blocks (angled wall torch), emitting warm `OmniLight3D` cave illumination.
3. **Bed (Sleep Through the Night & Respawn Point):**
   - Crafted from `3 Wool + 3 Wood Planks`. Right-clicking at night smoothly fades the screen and advances `DayNightCycle` to sunrise (`06:00`), setting the player's respawn coordinates.
4. **Wooden Door, Ladders & TNT:**
   - **Door:** 2-block tall hinged mesh that swings `90°` open/closed when right-clicked (with collision toggle and door creak SFX).
   - **Ladder:** Climbable vertical face when pressing `W` or `Space` against it.
   - **TNT:** Ignited with Flint & Steel (or adjacent explosion), flashes for `4 seconds`, and blasts a spherical crater while spawning dropped block items.

---

### Step 1.5 — Biomes & Generated World Structures
1. **Multi-Biome World Generator (`VoxelChunk`):**
   - Temperature + Humidity noise maps generating **Plains** (flat grassy fields, tall grass, flowers), **Forest** (dense Oak & Birch trees), **Desert** (Sand, Sandstone, Cacti, Dead Bushes), and **Snowy Taiga** (Snow, Ice over water, Pine trees).
2. **Procedural Structures:**
   - **Plains Villages:** Gravel road networks, cobblestone/oak houses with doors, torches, tables, wells, and crop farms.
   - **Underground Dungeons & Mineshafts:** Mossy cobblestone chambers with a central mob spawner and a **Loot Chest** containing Iron, Gold, Bread, Buckets, and Diamonds; plus timber-supported mineshaft tunnels.
   - **Desert Wells & Pyramids:** Sandstone structures with hidden treasure chambers below.

---

## PHASE 2: Blender-Rendered Minecraft UI, HUD & 3D Item Icon Overhaul

All UI elements, panels, slots, HUD icons, and item renders will be produced by our automated **Blender 5.2 script (`tools/blender/render_ui_assets.py`)** and saved into `res://assets/ui/`:

1. **Blender-Rendered 3D Beveled GUI Frames & Slots (`res://assets/ui/gui_panels/`):**
   - Model actual 3D beveled stone-grey Minecraft GUI frames, recessed item slots with true 3D top-left shadow casts, furnace progress arrows, animated 3D flame icons, and hotbar selector frames in Blender, rendered with an **orthographic camera and crisp directional lighting** into high-resolution `NinePatchRect` and slot textures.
2. **Blender-Rendered 3D HUD Status Icons (`res://assets/ui/hud_icons/`):**
   - Render 3D voxelized/sculpted **Hearts** (Full, Half, Empty, Hurt-Flash), **Armor Chestplates**, **Roasted Hunger Drumsticks**, and **Glossy Underwater Oxygen Bubbles** in Blender with studio lighting and transparent alpha backgrounds.
3. **Blender-Rendered 3D Isometric Block & Tool Icons (`res://assets/ui/item_icons/`):**
   - Every placeable 3D block in `BlockRegistry` is constructed in Blender with its real face textures and rendered through a **true `30° / 45°` isometric orthographic camera** with 3-point studio lighting into transparent `64×64` icon PNGs.
   - Every tool and item (**Wood/Stone/Iron/Diamond Pickaxes, Axes, Shovels, Swords, Sticks, Coal, Raw Ore, Ingots, Diamonds, Iron/Water Buckets, Apples, Bread, Raw/Cooked Meat**) is modeled as a 3D voxel-extruded mesh in Blender with metallic/roughness materials and rendered into crisp transparent icon PNGs.
4. **Full Survival Inventory (`E`) & Container Modals (`VoxelHUD`):**
   - **Armor Slots (`Helmet, Chestplate, Leggings, Boots`)** + **3D Player Character Preview Box** on the top-left of the `E` window.
   - **`Shift + Left-Click`** instant stack transfer between Hotbar, Backpack, Crafting Grid, Chest, and Furnace.
   - **`Right-Click Drag`** to distribute 1 item evenly across hovered crafting slots.

---

## PHASE 3: Blender-Baked Block & Material Texture Atlas Overhaul

All block textures will be generated and baked using **Blender 5.2 (`tools/blender/render_block_atlas.py`)** into `res://assets/textures/block_atlas.png`:

1. **Blender 3D Micro-Relief & Procedural Shader Baking:**
   - For each tile in the atlas, Blender builds a 3D tile scene with **true 3D micro-geometry and Cycles/EEVEE material nodes** (Voronoi stone fractures, extruded cobblestone boulders with recessed mortar, 3D layered wood bark ridges, 3D crystalline ore chunks embedded in rock, 3D wooden planks with bevel grooves, and 3D workbench tools on the Crafting Table sides) and renders them under an orthographic top-down camera into a pixel-crisp `block_atlas.png`:
     - **Natural Blocks:** Grass Top, Grass Side Skirt, Rich Dirt, Coarse Gravel, Rippled Desert Sand, Sandstone, Stratified Stone, High-Contrast 3D Cobblestone, Mossy Cobblestone, Bedrock, and Snow.
     - **Wood & Foliage:** Oak Log Bark, Oak Heartwood Rings, Birch Bark, Pine Bark, Horizontal Wooden Planks, Clay Bricks, Bookshelf, and Crisp Leaf Clusters.
     - **3D Mineral Ores:** Coal Ore, Iron Ore, Gold Ore, and Diamond Ore with metallic/crystalline highlights baked directly into the tile.
     - **Utility & Functional Blocks:** Crafting Table (top grid cloth, side tool rack with 3D saw & hammer), Furnace (stone arch, dark grate, glowing orange fire front when active), Chest (wood panels + gold latch), Glass, Torch, Door, and TNT.

---

## Execution Order Summary

1. **Step 1.1:** Authentic Flowing Water (8-level finite flow, sloped corner vertices, receding drainage, current push, depth buoyancy, and Iron/Water Buckets)
2. **Step 1.2:** 3D Dropped Items (`Q` drop + magnetic pickup + water float), 10-Stage Block Crack Overlay & Tool Durability
3. **Step 1.3:** Survival Vitals (Hearts, Hunger, Oxygen, Fall Damage), Food/Cooking & Swords + Hostile Night Mobs
4. **Step 1.4:** Functional World Blocks (Chests, Torches, Beds, Doors, Ladders, TNT)
5. **Step 1.5:** Biomes & Generated Structures (Villages, Underground Dungeons/Mineshafts, Deserts)
6. **Phase 2:** Blender-Rendered GUI Skin, 3D HUD Status Icons, 3D Isometric Item/Tool Icons & Shift-Click QoL
7. **Phase 3:** Blender-Baked Full Block & Material Texture Atlas (`res://assets/textures/block_atlas.png`)
