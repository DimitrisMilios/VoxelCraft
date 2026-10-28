# 🌟 VoxelCraft — Detailed Features Specification

This document provides a comprehensive breakdown of all gameplay systems, engineering mechanics, simulation algorithms, and interactive features implemented in **VoxelCraft**.

---

## 📑 Table of Contents

- [1. Procedural World Generation & Biomes](#1-procedural-world-generation--biomes)
- [2. Dual-Channel Voxel Lighting Engine](#2-dual-channel-voxel-lighting-engine)
- [3. Fluid Dynamics & Liquid Simulation](#3-fluid-dynamics--liquid-simulation)
- [4. Survival, Health, Hunger & Armor Systems](#4-survival-health-hunger--armor-systems)
- [5. Tool Tiers, Progressive Mining & Durability](#5-tool-tiers-progressive-mining--durability)
- [6. Agriculture, Farming & Botany](#6-agriculture-farming--botany)
- [7. Functional Multiblocks & Persistent Containers](#7-functional-multiblocks--persistent-containers)
- [8. Physics, Ballistics & Explosions](#8-physics-ballistics--explosions)
- [9. Authentic 3D Voxel A* Pathfinding & Entity AI](#9-authentic-3d-voxel-a-pathfinding--entity-ai)
- [10. Audio & Visual Systems](#10-audio--visual-systems)
- [11. Multi-World Persistence & Storage Architecture](#11-multi-world-persistence--storage-architecture)

---

## 1. Procedural World Generation & Biomes

VoxelCraft generates endless, deterministic voxel worlds driven by seed-based procedural noise.

### 🌿 Dual-Simplex Climate System
World biomes are governed by two independent 2D Simplex noise samplers:
* **Temperature Noise:** Determines thermal distribution from freezing alpine regions to arid deserts.
* **Humidity Noise:** Regulates precipitation from arid badlands to lush rainforests.

### 🗺️ The 10 Authentic Beta Biomes
| Biome | Temperature | Humidity | Dominant Flora & Surface |
| :--- | :--- | :--- | :--- |
| **Rainforest** | High | High | Dense foliage, towering trees, ferns |
| **Swampland** | Moderate | Very High | Murky waters, abundant reeds, low elevation |
| **Plains** | Moderate | Moderate | Expansive grassland, dandelions, roses |
| **Forest** | Moderate | High | Dense oak and birch tree canopies |
| **Desert** | High | Very Low | Pure sand dunes, sandstone formations, cacti |
| **Taiga** | Low | High | Conical pine/spruce trees, snowy underbrush |
| **Tundra** | Very Low | Moderate | Permafrost, deep snow blankets, ice formations |
| **Savanna** | High | Low | Dry tall grass, scattered flat-top trees |
| **Shrubland** | Moderate | Low | Rolling grass hills with sparse bushes |
| **Seasonal Forest** | Moderate | High | Mixed deciduous oak, birch, and varied flora |

### ⛏️ Stratified Subterranean Geology
* **Bedrock Layer:** Classic jagged bedrock bottom floor spanning elevations $Y=1$ to $Y=5$ using deterministic height hashing. Fully blast-proof and unbreakable in survival.
* **Cave Networks & Ravines:** Continuous 3D Perlin/Simplex noise carves natural walk-in cavern entrances, winding subterranean tunnels, and deep vertical chasms.
* **Ore Vein Distribution:**
  * **Coal Ore:** Wide distribution across all heights ($Y=1$ to $Y=128$).
  * **Iron Ore:** Abundant in mid-to-deep underground ($Y=1$ to $Y=64$).
  * **Gold Ore:** Rare veins found deep underground ($Y=1$ to $Y=32$).
  * **Diamond Ore:** Extremely rare veins near the bedrock boundary ($Y=1$ to $Y=16$).
  * **Redstone & Lapis Lazuli:** Distributed deep within cavern floors.
* **Dungeon Chambers:** Hidden underground rooms built of Cobblestone and Mossy Cobblestone, featuring functional Monster Spawners and loot-bearing Chests.

---

## 2. Dual-Channel Voxel Lighting Engine

VoxelCraft implements an authentic dual-channel voxel lighting system (`VoxelLighting`) operating at 16 discrete light levels ($0$ to $15$):

```
       [Sun / Moon Sky]                  [Torch / Lava / Glowstone]
              │                                      │
              ▼                                      ▼
      Skylight Channel (0..15)              Blocklight Channel (0..15)
              │                                      │
              └───────────────┬──────────────────────┘
                              ▼
                Combined Effective Illumination
                              │
                              ▼
            Smooth Ambient Occlusion (AO) Shading
```

* **Skylight Channel (0–15):** Propagates vertically downward through air and transparent blocks without attenuation, then radiates horizontally through a 6-direction Breadth-First Search (BFS) flood-fill.
* **Blocklight Channel (0–15):** Emitted locally by light-emitting blocks (Torches: 14, Glowstone: 15, Active Furnaces: 13, Lava: 15) and attenuates by $1$ unit per step in 6 directions.
* **Day/Night Cycle Attenuation:** The active celestial angle dynamically scales the effective intensity of the skylight channel while preserving blocklight levels.
* **Smooth Ambient Occlusion (AO):** Each voxel face evaluates the 4 corner configurations of neighboring blocks to interpolate subtle corner shadows across vertices.

---

## 3. Fluid Dynamics & Liquid Simulation

### 🌊 8-Level Sloped Water System
* **Water Source (`WATER`, Level 8):** Full-block liquid that generates infinite springs when two sources sit horizontally adjacent over a solid block.
* **Flowing Water (`WATER_FLOW_1` .. `WATER_FLOW_7`):** Spreads horizontally up to 7 blocks away from a source, decrementing height by $1$ per block step.
* **Falling Water Columns (`WATER_FALLING`):** Water encountering a cliff edge drops straight down without horizontal attenuation until striking a solid surface.
* **Sloped Corner Vertex Meshing:** Corner heights are smoothly interpolated by averaging neighboring fluid levels, creating natural directional water ramps.
* **Dynamic Fluid Push:** Flowing water applies a directional kinematic impulse to players, mobs, and dropped item entities along the current.
* **Water Drainage:** When a source block is obstructed, child flowing streams smoothly decay and evaporate.

### 🌋 Lava Dynamics
* High-viscosity spread (moves slower and over a shorter radius than water).
* Generates **Cobblestone** or **Obsidian** when contacting water surfaces.
* Ignites flammable blocks and deals severe thermal damage.

---

## 4. Survival, Health, Hunger & Armor Systems

### ❤️ Vitals & Combat
* **Health System:** 10 Hearts (20 Health Points) with damage immunity invulnerability frames, red-tint hurt flashing, and spatial hurt audio.
* **Hunger System:** 10 Drumsticks (20 Food Points) consumed through running, jumping, and mining; replenishing hunger regenerates health.
* **Oxygen Gauge:** 10 Oxygen Bubbles displayed while submerged; bubbles pop progressively before drowning damage occurs.
* **Fall Damage:** Kinematically calculated from airborne terminal velocity and impact elevation; cushioned by water blocks.

### 🛡️ Armor Mitigation Mechanics
Players can equip 4 armor pieces (Helmet, Chestplate, Leggings, Boots) crafted from Leather, Iron, Gold, or Diamond.
* Damage absorption formula:
  $$\text{Damage Reduced} = \text{Raw Damage} \times \left(1.0 - \frac{\text{Total Defense Points} \times 0.04}{1.0}\right)$$
* Visual armor status bar dynamically rendered on the HUD above the health meter.

---

## 5. Tool Tiers, Progressive Mining & Durability

### 🔨 Harvest Levels (what drops anything)
* **Any pickaxe (wood or gold):** Stone, Cobblestone, Sandstone, Coal Ore, Furnace, Spawner.
* **Stone pickaxe or better:** Iron Ore, Lapis Ore, Iron and Lapis Blocks.
* **Iron pickaxe or better:** Gold Ore, Diamond Ore, Redstone Ore, Gold and Diamond Blocks.
* **Diamond pickaxe:** Obsidian. Bedrock cannot be broken.
* Everything else (dirt, wood, sand, plants...) drops by hand. Leaves only drop themselves with shears (otherwise 5% sapling, 0.5% apple from oak).

### ⏳ Break Time
Break time in seconds = **hardness × 1.5 ÷ tool speed** when the block can be harvested, or **hardness × 5 ÷ tool speed** when it cannot (rounded up to whole game ticks of 1/20 s). The tool speed only applies if it is the right tool for the block (pickaxe for stone-type blocks, axe for wood, shovel for dirt/sand/gravel); otherwise it is 1. Mining is 5× slower with your head underwater and 5× slower while not standing on the ground.

| Tool material | Hand | Wood | Stone | Iron | Diamond | Gold |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| Speed | 1 | 2 | 4 | 6 | 8 | 12 |
| Stone (hardness 1.5) | 7.5 s | 1.15 s | 0.6 s | 0.4 s | 0.3 s | 0.2 s |
| Iron Ore (3) | 15 s* | 7.5 s* | 1.15 s | 0.75 s | 0.6 s | 1.25 s* |
| Obsidian (50) | 250 s* | 125 s* | 62.5 s* | 41.7 s* | 9.4 s | 20.85 s* |
| Oak Log (2, axe) | 3 s | 1.5 s | 0.75 s | 0.5 s | 0.4 s | 0.25 s |

\* cannot be harvested with that tool, so it drops nothing.

* A 10-stage crack overlay follows the progress; releasing the button or switching items restarts it.
* After a block breaks there is a 0.25 s pause before the next one starts; instant blocks (plants, torches, TNT) break immediately.
* Tools lose 1 durability per block that takes time to break (swords 2); instant blocks cost nothing.

---

## 6. Agriculture, Farming & Botany

### 🌾 Crop Cultivation
1. **Tilling:** Use a Hoe on Grass or Dirt to convert it into **Farmland**.
2. **Irrigation:** Farmland within a 4-block horizontal radius of water becomes hydrated (darkens visually) and boosts growth rates.
3. **Seeding:** Right-click Farmland with Wheat Seeds to plant a **Wheat Sprout**.
4. **Growth Stages:** Crops progress through 8 growth phases driven by random chunk ticks.
5. **Harvesting:** Breaking fully mature crops yields edible **Wheat** and multiple **Wheat Seeds** for replanting.

### 🌳 Tree Lifecycles & Foliage
* **Oak Trees:** Classic balloon canopies with organic leaf distribution.
* **Pine / Spruce Trees:** Conical needle foliage native to snowy taiga biomes.
* **Birch Trees:** Distinct white bark with vibrant foliage.
* Each wood type has its own bark and end-grain texture. Placed logs lie along the axis of the face you click, with the bark rotated to match.
* Felling a trunk makes natural leaves more than 4 blocks (through leaves) from any log decay over the next seconds, dropping saplings and occasionally apples. Leaves you place yourself never decay.
* **Saplings** (oak, spruce, birch) grow into trees with random ticks when they have light level 9+ and room to grow.

### 🎋 Sugar Cane & Cactus
* Sugar cane generates in clumps on sand, grass or dirt right at the water's edge, 2–4 blocks tall.
* It can only be placed on sugar cane, or on grass/dirt/sand with water directly beside that block. Removing the water (or the block under it) breaks the whole stalk, dropping each piece.
* Sugar cane and cactus grow one block every 16 random ticks (about 18 minutes) up to 3 blocks tall.

---

## 7. Functional Multiblocks & Persistent Containers

### 🚪 2-Block Swinging Doors
* A thin (3/16 block) two-block panel. It is placed facing the way you look, against the edge of the block nearest to you, and needs a solid floor and two free blocks.
* The hinge goes on the side with more solid blocks next to it; placing a door beside another door makes a double door; otherwise it follows which half of the block you clicked.
* Right-clicking either half swings both halves 90° onto the hinge side (collision follows, so open doors can be walked through).
* Breaking either half, or the block under it, removes the whole door and drops one door.

### 🛏️ 2-Block Bed Multiblock & Sleep System
* Built from paired Foot and Head blocks.
* Right-clicking at night triggers the sleeping sequence:
  * Smooth camera transition into the lying position.
  * Time accelerates forward to morning (06:00).
  * Clears stormy weather and resets hostile mob counts.
  * Anchors the player's permanent respawn coordinates.
  * Death respawn safely positions the player beside the bed on open solid ground.

### 📦 27-Slot Storage Chests
* Right-clicking opens an interactive 27-slot container overlay.
* Full item stack manipulation (Left-Click to move stacks, Right-Click to split single units).
* Items remain saved inside chunk data and persist across sessions.

### 🛠️ Crafting Bench & Smelting Furnace
* **Player Inventory:** Built-in 2×2 crafting grid for torches, wooden planks, and sticks.
* **Crafting Table (3×3 Grid):** Full shaped and shapeless recipe evaluation for tools, armor, multiblocks, and weapons.
* **Furnace Oven:** Interactive fuel slot (Coal, Charcoal, Wood) and ingredient slot. Smelts iron/gold ores into ingots and cooks raw meats into steak and porkchops.

---

## 8. Physics, Ballistics & Explosions

### ⏳ Falling Block Gravity
* **Sand & Gravel:** Voxels without support below transition into smooth `FallingBlock` kinematic entities.
* Sinks through liquids at attenuated velocity.
* Solidifies into solid blocks upon landing, or shatters into item pickups if falling onto non-solid blocks (Torches, Flowers).

### 🏹 Ballistic Arrow Kinematics
* Fired from Bows with charge velocity.
* Accurate ballistic arc modeling with downward gravitational acceleration ($14.0\text{ m/s}^2$) and air drag ($0.99$).
* Water drag deceleration ($0.65$) upon entering fluid blocks.
* Continuous collision detection embeds arrows into blocks for player retrieval, or deals damage and knockback to entities.

### 💥 Primed TNT & Radial Explosions
* 80-tick (4.0s) fuse with bouncing CharacterBody3D physics and accelerating white flash blinking.
* Detonation carves spherical blast craters through voxel terrain.
* Water blast dampening: submerged explosions protect terrain blocks while delivering knockback and damage to entities.
* Chained explosions: TNT within blast radius ignites and launches dynamically.

---

## 9. Authentic 3D Voxel A* Pathfinding & Entity AI

### 🧠 3D Voxel A* Pathfinder (`AStarPathFinder`)
Entities navigate complex voxel landscapes using a specialized 3D A* search engine:
* Explores 4 orthogonal and 4 diagonal spatial directions.
* **Corner-Cutting Prevention:** Strictly checks that diagonal transitions have clear adjacent blocks.
* **1-Block Stepping:** Automatically hops up 1-block elevation changes.
* **Safe Drop Limit:** Restricts descents to $\le 3$ blocks to prevent suicidal mob cliff falls.
* **Vertical Clearance:** Verifies 2 full blocks of vertical headroom.

### 🐄 Passive Mobs
* **Pigs, Cows, Sheep, Chickens:**
  * Autonomous wandering with obstacle avoidance.
  * Panic sprinting and vocalization when attacked.
  * Feeding mechanics: holding wheat attracts mobs and triggers breeding heart particles.
  * Sheep shearing: Right-clicking with Shears produces Wool blocks; sheep regrow wool after grazing on grass.

### 🧟 Hostile Monsters
* **Spawn Rules:** Spawn exclusively in low light levels ($\le 7$) at night or deep underground; prevented near placed torches.
* **Zombies:** Pursue players using 3D pathfinding and deliver melee attacks.
* **Skeletons:** Maintain strafing distance and fire ballistic arrows with lead prediction.
* **Spiders:** 2×2 footprint with the capability to climb vertical walls.
* **Creepers:** Stalk players silently; hiss and expand when within 3 meters before detonating.

---

## 10. Audio & Visual Systems

### 🎨 Faithful 64x High-Definition Aesthetics
* Clean 64×64 pixel-art textures across all blocks, mobs, weapons, and HUD elements.
* 3D First-Person Held Item viewmodel with organic walk-bobbing, weapon sway, and strike animations.
* Lightweight Compatibility (OpenGL 3.3) renderer with baked smooth lighting, distance fog and an automatic render scale that keeps weak GPUs at 60 FPS.

### 🎵 Dynamic Sound Design
* **Procedural Sound Synthesizer:** On-the-fly 16-bit PCM procedural audio generator.
* **Spatial 3D SFX:** Positional footstep audio matching surface materials (Grass, Stone, Wood, Gravel, Sand), mob vocals, tool impacts, and explosions.
* **Ambient Piano Music:** Intelligent background music manager playing serene ambient piano compositions during exploration and sunrise.

---

## 11. Multi-World Persistence & Storage Architecture

* **Multi-World Save Manager:** Create, select, and delete multiple independent worlds from the Main Menu.
* **Zstd Chunk Compression:** Modified chunk voxels and container inventories are serialized using high-ratio Zstd compression to `user://worlds/<world_name>/chunks/`.
* **Session Persistence:** Player health, hunger, inventory contents, hotbar selection, spatial coordinates, camera rotation, and bed respawn anchor save automatically on exit and restore seamlessly upon load.
