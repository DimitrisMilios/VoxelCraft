<div align="center">

# 🧊 VoxelCraft

**An open-source retro 3D voxel sandbox game built with Godot Engine 4**

[![Godot Engine](https://img.shields.io/badge/Godot-4.7%2B-%23478cbf?logo=godot-engine&logoColor=white)](https://godotengine.org/)
[![Language](https://img.shields.io/badge/Language-GDScript-blue)](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/index.html)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/DimitrisMilios/VoxelCraft/pulls)

*Classic low-poly, pixel-art voxel exploration, procedural worlds, and block building.*

[Overview](#-overview) • [Core Architecture](#-core-systems-architecture) • [Roadmap](#-development-roadmap) • [Getting Started](#-getting-started) • [Contributing](#-contributing)

</div>

---

## 🎮 Overview

**VoxelCraft** is an open-source 3D voxel sandbox prototype inspired by classic early-era block-building games. Built from the ground up in **Godot 4.x**, it focuses on a nostalgic low-poly / low-resolution pixel-art aesthetic, snappy first-person controls, and clean, modular voxel engine architecture.

### ✨ Key Features

- **🌍 Endless Procedural World:** Dynamic chunk loading and unloading around the player using 2D heightmap noise (`FastNoiseLite`) for hills and 3D noise for cave systems.
- **⚡ Optimized Voxel Rendering:** Custom `ArrayMesh` generation per chunk with neighbor-aware **face culling** (internal hidden faces are never rendered) and a single `16x16` pixel texture atlas to minimize draw calls.
- **🔨 Interactive Block Building & Mining:** Screen-center raycasting for instant block breaking, placement against targeted faces, and real-time chunk mesh regeneration.
- **🏃 Snappy First-Person Physics:** Responsive `CharacterBody3D` controller with custom gravity, jumping, smooth mouse look, and accurate voxel collision.
- **🐄 Autonomous Passive Mobs:** Simple wandering AI entities with gravity, ground detection, and ledge avoidance.

---

## 🏗️ Core Systems Architecture

### 1. Voxel Data Model & Chunking
- **Chunk Dimensions:** `16 × 256 × 16` blocks per chunk.
- **Storage Format:** Compact in-memory voxel representation (`PackedByteArray` / coordinate dictionary) per chunk.
- **Block Registry (ID Mapping):**

| Block ID | Block Type | Description |
| :---: | :--- | :--- |
| `0` | **Air** | Empty space (transparent, non-solid) |
| `1` | **Grass** | Surface terrain block |
| `2` | **Dirt** | Sub-surface soil layer |
| `3` | **Stone** | Deep underground & cavern foundation |
| `4` | **Wood Log** | Tree trunk block |
| `5` | **Leaves** | Tree foliage block |

### 2. Procedural Generation (Endless Map)
- **Terrain Noise:** `FastNoiseLite` 2D heightmaps for rolling hills combined with 3D noise for underground cave networks.
- **Chunk Streaming:** A player-centered World Manager checks the player's chunk grid coordinates and streams chunks within the active render distance (e.g., `4×4` or `6×6` chunks) while freeing distant chunks.

### 3. Mesh Generation & Face Culling
- **Face Culling:** Adjacent voxel neighbors are inspected during mesh construction; triangles are emitted **only** for block faces bordering Air (`0`).
- **Single Texture Atlas:** All block faces sample UV coordinates from a unified `16×16` pixel art atlas for crisp retro visuals and minimal GPU state changes.

### 4. Player Controller & Block Interaction
- **Movement:** `CharacterBody3D` first-person controller with WASD movement, jump velocity, and mouse capture.
- **Raycasting:** Center-screen 3D raycast detects targeted voxel coordinates and surface normals to break (`Left-Click` -> sets ID to `0`) or place (`Right-Click` -> sets adjacent voxel to active hotbar block ID).

### 5. Autonomous Mobs (AI)
- **Wandering Entities:** `CharacterBody3D`-based passive mobs that roam voxel terrain, respect gravity, detect solid floor blocks, and avoid walking off steep ledges.

---

## 🕹️ Controls

| Input | Action |
| :--- | :--- |
| `W` `A` `S` `D` | Move Forward / Left / Backward / Right |
| `Space` | Jump |
| `Mouse Movement` | First-Person Camera Look |
| `Left Mouse Button` | Break Targeted Block |
| `Right Mouse Button` | Place Selected Block |
| `1` / `2` / `3` | Select Hotbar Slot (Grass, Dirt, Stone) |
| `Esc` | Toggle Mouse Cursor Capture |

---

## 🗺️ Development Roadmap

- [ ] **Phase 1: Project Initialization & Player Controller**
  - Initialize Godot 4 3D project structure
  - Implement first-person `CharacterBody3D` with smooth mouse look, WASD movement, jumping, and gravity
  - Create sandbox test scene with reference geometry
- [ ] **Phase 2: Voxel Data & Single Chunk Generator**
  - Build `16 × 256 × 16` chunk data container and `ArrayMesh` generator
  - Implement neighbor face culling and `FastNoiseLite` heightmap hills
- [ ] **Phase 3: Endless World Manager**
  - Track player chunk coordinates and dynamically load/unload chunks within render distance
  - Offload heavy chunk generation to Godot's `WorkerThreadPool` as needed
- [ ] **Phase 4: Block Interaction & UI Hotbar**
  - Add camera raycasting for breaking and placing blocks with immediate chunk remeshing
  - Build HUD crosshair and 3-slot block selection hotbar (Grass, Dirt, Stone)
- [ ] **Phase 5: Passive Mobile Entities (Mobs)**
  - Implement wandering passive mob AI with gravity and ledge detection

---

## ⚙️ Engineering & Performance Rules

1. **Combined Chunk Meshes:** Never instantiate individual Godot nodes per block. Every chunk builds a single combined `ArrayMesh` and collision shape.
2. **Multithreaded World Gen:** Keep frame times smooth by offloading chunk data and mesh building to Godot's `WorkerThreadPool` when streaming chunks.
3. **Modular Codebase:** Maintain strict separation of concerns across player controller logic, chunk voxel storage, procedural noise generation, and mesh building.

---

## 🚀 Getting Started

### Prerequisites
- **[Godot Engine 4.x](https://godotengine.org/download/)** (Standard GDScript edition, v4.2+ / v4.7+ recommended)

### Running the Project Locally

1. **Clone the repository:**
   ```bash
   git clone https://github.com/DimitrisMilios/VoxelCraft.git
   cd VoxelCraft
   ```
2. **Open in Godot:**
   - Launch the **Godot Engine** executable.
   - In the Project Manager, click **Import** (or **Scan**), navigate to the cloned `VoxelCraft` folder, and open `project.godot`.
3. **Play:**
   - Press `F5` (or click the **Run Project** button in the top-right corner of the editor).

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! As an open-source project, **VoxelCraft** thrives on community ideas and improvements.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-voxel-feature`)
3. Commit your changes (`git commit -m 'Add amazing voxel feature'`)
4. Push to the branch (`git push origin feature/amazing-voxel-feature`)
5. Open a Pull Request

Please make sure your code follows the [Engineering & Performance Rules](#️-engineering--performance-rules) and GDScript style conventions.

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for full details.

Copyright © 2026 **Δημήτρης Μήλιος (Dimitris Milios)**
