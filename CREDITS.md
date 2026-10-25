# Credits & Third-Party Attributions

VoxelCraft uses third-party assets in accordance with their respective open licenses.

---

## 🎨 Faithful 64x Resource Pack

- **Project:** [Faithful 64x](https://faithfulpack.net)
- **Version Used:** Release 15
- **Authors:** The Faithful Resource Pack Team & Contributors
- **Official Website:** [https://faithfulpack.net](https://faithfulpack.net)
- **License:** [Faithful License Version 4 (Jul 31, 2026)](https://faithfulpack.net/license) (full text included in [`FAITHFUL_LICENSE.txt`](FAITHFUL_LICENSE.txt) and [`assets/packs/faithful_64x/LICENSE.txt`](assets/packs/faithful_64x/LICENSE.txt))

### How Faithful 64x is Used in VoxelCraft:
- **Block Textures (64×64):** Block surfaces in the world use textures from Faithful 64x composited into [`assets/packs/faithful_64x/textures/block_atlas.png`](assets/packs/faithful_64x/textures/block_atlas.png), including authentic Plains/Forest grass biome coloring, foliage-tinted leaves, multi-face workbench and furnace sides, ores, and terrain blocks.
- **Animated Water:** Water surfaces use the Faithful 64x water still texture at [`assets/packs/faithful_64x/textures/water_still_64.png`](assets/packs/faithful_64x/textures/water_still_64.png).
- **Block Mining Destruction Overlays:** 10-stage block cracking textures at [`assets/packs/faithful_64x/textures/destroy_stages/`](assets/packs/faithful_64x/textures/destroy_stages/).
- **HUD & GUI Elements:** Hearts, hunger drumsticks, oxygen bubbles, crosshair, slot frames, and container dialog styling in [`assets/packs/faithful_64x/ui/`](assets/packs/faithful_64x/ui/).
- **Item & Tool Icons:** 2D tool, weapon, ingot, and food sprites, along with 3D isometric block previews in [`assets/packs/faithful_64x/ui/item_icons/`](assets/packs/faithful_64x/ui/item_icons/).
- **First-Person Viewmodels:** In-hand 3D tools (Pickaxes, Swords, Axes, Shovels), held resource items, and the player's textured arm using the Steve skin.
- **Dropped 3D Item Entities:** Spinning double-sided textured item quads for dropped tools, weapons, and resources floating in water or on land.
- **Autonomous Mobs & Animals:** Authentic entity textures for Zombies, Skeletons, Creepers, Spiders, Cows, and Pigs at [`assets/packs/faithful_64x/textures/entity/`](assets/packs/faithful_64x/textures/entity/).
- **Celestial Sky:** Sun and Moon billboards in the dynamic day/night cycle at [`assets/packs/faithful_64x/textures/environment/`](assets/packs/faithful_64x/textures/environment/).

Asset extraction and composition is automated via [`tools/build_faithful_64x_assets.gd`](tools/build_faithful_64x_assets.gd).

---

## 🔊 Sound Pack

- **Project:** Sound Pack for Minetest
- **Author:** Jordan Irwin (AntumDeluge) & Contributors
- **License:** MIT License (full text in [`assets/audio/LICENSE.txt`](assets/audio/LICENSE.txt))
- **Audio Sources & Licensing:** Creative Commons (CC0, CC-BY 3.0, CC-BY 4.0, MIT) - detailed in [`assets/audio/sources.md`](assets/audio/sources.md)
- **Included Sounds:** Material footsteps (grass, dirt, stone, wood, sand, snow, gravel, water), block dig/break/place effects, mob sounds (zombie, skeleton, creeper, spider, cow, pig), player damage/eating/jumping, tool breaking, door/chest opening/closing, explosions, and environmental ambiance.

---

## ⚙️ Godot Engine

- **Project:** [Godot Engine](https://godotengine.org)
- **License:** MIT License
- **Copyright:** (c) 2014-present Juan Linietsky, Ariel Manzur, and contributors.
