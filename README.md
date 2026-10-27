<div align="center">

# 🧊 VoxelCraft

**An authentic, high-performance 3D voxel sandbox & survival game engine built with Godot Engine 4**

[![Godot Engine](https://img.shields.io/badge/Godot-4.7%2B-%23478cbf?logo=godot-engine&logoColor=white)](https://godotengine.org/)
[![Renderer](https://img.shields.io/badge/Renderer-Mobile%20Vulkan%20(60%2B%20FPS)-green.svg)](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html)
[![Language](https://img.shields.io/badge/Language-GDScript%202.0-blue.svg)](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/index.html)
[![Resolution](https://img.shields.io/badge/Resolution-1080p%20Full%20HD-orange.svg)](#-graphics-audio--atmosphere)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/DimitrisMilios/VoxelCraft/pulls)

*Endless procedural worlds • Dual-channel voxel lighting • Finite 8-level sloped fluids • Authentic 3D A\* mob AI • Full survival & crafting progression*

[Overview](#-overview) • [Key Features](#-key-features) • [Controls](#-controls-cheat-sheet) • [Architecture](#-systems-architecture) • [Documentation](#-in-depth-documentation) • [Quick Start](#-quick-start) • [Verification](#-automated-testing--verification) • [Credits](#-credits--attributions) • [License](#-license)

</div>

---

## 🎮 Overview

**VoxelCraft** is an open-source, full-featured 3D voxel sandbox and survival game built from the ground up in **Godot 4**. Designed with a focus on nostalgic early-era survival mechanics, authentic voxel kinematics, and rock-solid systems engineering, it delivers a rich retro experience optimized for high framerates (60+ FPS) on modern and integrated GPUs alike.

Every subsystem—from procedural multi-biome climate samplers and dual-channel lighting propagation to 3D voxel A* pathfinding and multithreaded chunk streaming—is engineered for modularity, clean code separation, and seamless extensibility.

---

## ✨ Key Features

### 🌍 Endless Procedural Worlds & 10 Biomes
* **Dual-Simplex Climate System:** Dynamic temperature and humidity noise samplers generate 10 authentic biomes: *Rainforest, Swampland, Plains, Forest, Desert, Taiga, Tundra, Savanna, Shrubland, and Seasonal Forest*.
* **Subterranean Geology:** Walk-in cavern entrances, underground ravines, layered ore veins (*Coal, Iron, Gold, Diamond, Redstone, Lapis Lazuli*), and a jagged, unbreakable bedrock foundation ($Y=1$ to $Y=5$).
* **Dungeons & Spawners:** Underground cobblestone chambers containing monster spawners and randomized treasure chests.

### 💡 Dual-Channel Voxel Lighting & Smooth AO
* **Dual Channels (0–15):** Independent *Skylight* (attenuated by celestial time of day) and *Blocklight* (torches, glowstone, furnaces, lava).
* **Breadth-First Search (BFS):** 6-direction fast queue propagation crossing chunk boundaries with zero lighting seams.
* **Per-Vertex Ambient Occlusion (AO):** Evaluates neighboring corner voxels to compute smooth, natural corner shading across exposed faces.

### 🌊 Fluid Dynamics & 8-Level Sloped Water
* **Finite 8-Level Flow:** Water spreads horizontally up to 7 blocks with decreasing depth and drops vertically as waterfalls without flooding entire worlds.
* **Sloped Corner Meshing:** Vertex heights dynamically interpolate between neighboring fluid blocks, creating smooth diagonal liquid ramps.
* **Fluid Current Push & Buoyancy:** Flowing currents push swimming players, mobs, and dropped items toward ledges and drains.
* **Dynamic Evaporation:** Disconnected fluid streams smoothly drain away when source blocks are removed.

### ⚔️ Survival, Health, Hunger & Armor Mitigation
* **Vitals HUD:** 10 Hearts (20 HP), 10 Hunger Drumsticks (20 Food points), and 10 Oxygen Bubbles for underwater diving.
* **Fall Damage & Water Cushioning:** Terminal-velocity-based impact calculations cushioned by water bodies.
* **Tiered Armor Protection:** Helmets, Chestplates, Leggings, and Boots (Leather, Iron, Gold, Diamond) with defense formulas mitigating incoming damage.
* **Tool Durability & Harvest Tiers:** Pickaxes, Axes, Shovels, Hoes, and Swords with material-based durability bars and harvest restrictions.

### 🏹 Ballistics, Gravity Blocks & Explosions
* **Ballistic Arrow Kinematics:** Trajectory arc modeling with gravitational acceleration, air resistance, liquid drag attenuation, mob damage/knockback, and block embedding for player retrieval.
* **Falling Blocks:** Unsupported Sand and Gravel fall smoothly, sink through liquids, stack on floors, or shatter into collectible items if striking torches or flowers.
* **Primed TNT:** Authentic 80-tick (4.0s) fuse, bouncing physics, white flash blinking, spherical blast cratering, chained detonations, and water blast dampening.

### 🧠 Authentic 3D Voxel A* Pathfinding & Mob AI
* **Custom 3D Pathfinder:** Explores orthogonal and diagonal paths, enforces corner-cutting prevention, 1-block step hopping, vertical clearance checks, and safe drop limits ($\le 3$ blocks).
* **Passive Mobs (Pigs, Cows, Sheep, Chickens):** Autonomous wandering, panic sprinting when harmed, wheat feeding/breeding heart particles, and sheep wool shearing.
* **Hostile Monsters (Zombies, Skeletons, Spiders, Creepers):** Dark spawning constraints (light $\le 7$), player tracking, skeleton bow archery, spider wall climbing, and creeper fuse hissing detonations.

### 🌾 Agriculture & Botany
* **Farming Progression:** Till soil with Hoes into hydrated Farmland, plant Wheat Seeds, observe 8 distinct visual growth stages, and harvest wheat and seeds.
* **Foliage & Tree Felling:** Oak, Pine/Spruce, and Birch trees with balloon leaf canopies and gradual leaf decay upon trunk felling.

### 🪑 Functional Multiblocks & Containers
* **2-Block Swinging Doors:** Coordinated upper and lower door multiblocks with spatial opening audio and synchronized collision.
* **2-Block Beds:** Foot and head multiblocks, sleep sequence skipping the night to dawn, weather clearing, and safe un-entangled respawn positioning.
* **27-Slot Storage Chests:** Persistent item container storage with interactive stack transfer UI.
* **Crafting & Smelting:** 2×2 player inventory crafting, 3×3 Crafting Table workbench, and real-time ticked Furnace Oven for ore smelting and food cooking.

### 🎨 Graphics, Audio & Atmosphere
* **Faithful 64x High-Definition Textures:** Crisp, authentic 64×64 pixel-art surfaces across blocks, tools, weapons, and GUI elements.
* **3D Held Viewmodel:** Smooth first-person item rendering with realistic walk bobbing, inertia sway, and swing animations.
* **Audio Engineering:** Material-based 3D footstep sounds (Grass, Stone, Wood, Sand, Gravel), mob vocalizations, tool impacts, procedural 16-bit PCM sound synthesizer, and ambient piano background music.

### 💾 Multi-World Save/Load & Memory Persistence
* **Main Menu World Manager:** Create custom worlds with customizable seed strings, load saved worlds, or delete existing worlds.
* **Zstd Compression:** Player-modified chunks are saved in memory and serialized to disk using high-ratio Zstandard compression.
* **Session Persistence:** Player health, hunger, inventory, hotbar selection, spatial coordinates, camera angles, and bed respawn points persist across game restarts and window closing.

---

## 🕹️ Controls Cheat Sheet

| Input | Action |
| :--- | :--- |
| `W` `A` `S` `D` | Move Forward / Strafe Left / Backward / Strafe Right |
| `Shift` (Hold) | Sprint (with dynamic FOV boost) |
| `Space` | Jump (or Ascend during Creative Fly Mode) |
| `Ctrl` / `C` | Descend during Creative Fly Mode |
| `F` | Toggle Creative Fly Mode on/off |
| `Mouse Look` | First-Person Camera Look & Crosshair Targeting |
| `Left Click (Hold)` | Mine Targeted Block (displays 10-stage progressive cracks) |
| `Left Click` | Attack Mob / Deal Weapon Damage & Knockback |
| `Right Click` | Place Block / Interact with Chest, Door, Bed, Crafting Table, Furnace |
| `1` – `9` / `Scroll Wheel` | Select Active Hotbar Slot (1–9) |
| `E` | Open 36-Slot Inventory & 2×2 Crafting Grid |
| `Q` | Drop Held Item as a 3D Entity into the World |
| `T` | Fast-Forward Time of Day (+2.5 Hours) |
| `F6` | Quick-Save World State to Disk |
| `Esc` | Open Interactive Pause & Settings Menu |

---

## 🏗️ Systems Architecture

```
                                 [Main Scene / GameSession]
                                             │
                      ┌──────────────────────┴──────────────────────┐
                      ▼                                             ▼
              [PlayerController]                             [WorldManager]
              ├── BlockInteractor                            ├── WorkerThreadPool (Multithreaded)
              ├── HeldBlockView (3D Viewmodel)               ├── ChunkStreaming & Caching
              └── InventoryManager                           └── ChunkStorage (Zstd Persistence)
                      │                                             │
                      ▼                                             ▼
              [VoxelHUD & Menus]                              [VoxelChunk]
              ├── 36-Slot Inventory & 3x3 Bench              ├── 16 Vertical SubChunks (16x16x16)
              ├── Ticked Furnace & 27-Slot Chest             ├── Dual-Pass ArrayMesh (Opaque & Water)
              └── Vitals (Hearts, Hunger, Oxygen)            └── VoxelLighting (0-15 Dual Channel BFS)
```

### ⚡ Key Architectural Highlights
1. **Vertical Sub-Chunk Partitioning:** Chunks are sliced into 16 vertical $16 \times 16 \times 16$ sub-chunks. Modifying a block only rebuilds its local sub-chunk mesh instead of the full vertical column.
2. **Neighbor-Aware Face Culling:** Internal hidden block faces are discarded before vertex generation, culling over $85\%$ of scene geometry.
3. **Multithreaded Chunk Streaming:** Noise generation and mesh construction are offloaded to Godot's `WorkerThreadPool`, keeping frame times rock-solid during exploration.
4. **Delta-Only Chunk Persistence:** Only player-modified chunks are compressed via Zstd and stored on disk; pristine terrain is regenerated on-the-fly from the world seed.

---

## 📚 In-Depth Documentation

Detailed technical documentation and reference guides are available in the [`docs/`](docs/) directory:

* 📖 **[Features Specification](docs/FEATURES.md):** Deep-dive analysis of world generation, fluids, mob AI, lighting algorithms, and survival formulas.
* 🏛️ **[Technical Architecture](docs/ARCHITECTURE.md):** Comprehensive breakdown of sub-chunking, memory layout, multithreading pipelines, and class hierarchies.
* 🛠️ **[Controls, Recipes & Crafting](docs/CONTROLS_AND_CRAFTING.md):** Complete 2×2 and 3×3 recipe catalog, furnace smelting ratios, and tool tier matrices.

---

## 🚀 Quick Start

### Option A: Play Standalone Build (Windows)
If you have cloned the repository with pre-packaged binaries:
1. Double-click **`Play_VoxelCraft.bat`** (or **`run_game.bat`**) in the root directory.
2. The game launches immediately in 1080p Full HD!

### Option B: Run from Godot Engine 4 Editor
1. Download and install **[Godot Engine 4.x](https://godotengine.org/download/)** (Standard 64-bit edition).
2. Clone the repository:
   ```bash
   git clone https://github.com/DimitrisMilios/VoxelCraft.git
   cd VoxelCraft
   ```
3. Launch Godot, click **Import**, select `project.godot` inside the cloned folder, and click **Edit**.
4. Press **`F5`** (or click the Play button in the top-right corner) to launch the Main Menu.

### Option C: Build Production Executable
Run the automated packaging script from your terminal:
```cmd
build_game.bat
```
This generates a production `.pck` package and standalone executable in the `build/` directory.

---

## 🧪 Automated Testing & Verification

VoxelCraft features dedicated headless test suites located in [`tools/`](tools/) ensuring engine stability:

| Test Script | Verification Scope |
| :--- | :--- |
| `tools/test_terrain.gd` | Climate noise, 10 biomes, bedrock layer, ore bounds, and chunk decorators |
| `tools/test_phase2.gd` | Recipe matching, metadata transitions, and container item stack transfers |
| `tools/test_phase3.gd` | Gravity blocks, ballistic arrow trajectories, and primed TNT detonations |
| `tools/test_phase4.gd` | 3D A* pathfinder, mob obstacle clearance, and hostile combat AI |
| `tools/test_phase5.gd` | Dual-channel lighting BFS, smooth AO vertex tints, and armor damage mitigation |
| `tools/test_inventory_persistence.gd` | Multi-world save/load, player inventory persistence, and window close safety |
| `tools/test_doors_beds_music.gd` | 2-block door mechanics, bed sleeping transitions, and background music manager |

Run any test suite headlessly via Godot:
```bash
godot --headless -s tools/test_phase5.gd
```

---

## 🎨 Credits & Attributions

VoxelCraft incorporates high-resolution textures and UI elements from the **Faithful 64x Resource Pack**:
* **Project:** [Faithful 64x](https://faithfulpack.net) (Release 15)
* **Authors:** The Faithful Resource Pack Team & Contributors
* **Website:** [https://faithfulpack.net](https://faithfulpack.net)
* **License:** [Faithful License Version 4](https://faithfulpack.net/license) (full license text included in [`FAITHFUL_LICENSE.txt`](FAITHFUL_LICENSE.txt))
* Used for high-resolution 64×64 block surfaces, animated water ripples, mining destruction cracks, HUD vitals, UI slot panels, and item icons. See [`CREDITS.md`](CREDITS.md) for complete asset mapping.

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for complete details.

```
MIT License

Copyright (c) 2026 Δημήτρης Μήλιος (Dimitris Milios)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```
