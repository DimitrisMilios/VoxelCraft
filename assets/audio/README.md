## Sound Pack for Minetest

### Description:

A [Minetest][] mod that provides a set of free sounds & methods.

What is the purpose of this mod? There are four ideas behind `sounds`:

1. It is intended as a more universal method for adding sounds to games rather than depending on [MTG & default][default] for sounds only. It is completely compatible with default sounds. The same methods called in `default` to set node sounds, like `default.node_sound_stone_defaults`, are implemented & it can be installed in parallel. *Section: [Replacement for default](#replacement-for-default)*
2. It is simply a well of sounds. Many sound files are provided & can be used with [minetest.sound_play](https://minetest.gitlab.io/minetest/minetest-namespace-reference/#sounds) just as normal. There is also a wrapper function, [sounds:play](https://antummt.github.io/mod-sounds/reference/latest/topics/api.html#sounds:play), that does its best to verify that a sound played successfully. If so, it will return a sound handle ID. Otherwise it will return `nil`. A random sound can be played from a list with [sounds:play_random](https://antummt.github.io/mod-sounds/reference/latest/topics/api.html#sounds:play_random). It also caches all loaded mod sounds after server startup in `sounds.cache` table. So sound files can easily be checked for existence. *Section: [Checking for Existing Sounds](#checking-for-existing-sounds)*
3. It adds callable sound groups that can be used to play specified individual sounds, or a random sound in the group. The benefit to this is that the file naming convention is irrelivent. The only thing that matters is that the sound file is registered with the group. *Section: [Playing Sounds Manually](#playing-sounds-manually)*
4. Adds an API for setting biome ambiance sounds.

Note that most included sounds have been set with a peak amplitude of -6.0db.


<img src="screenshot.png" alt="icon" width="200" />

### Licensing:

- Code: [MIT](LICENSE.txt)
- Icon/Screenshot: [CC0](https://openclipart.org/detail/260975)
- Media: see following table

#### Sound file sources & licensing:<a name="sources" />

See [sources.md](sources.md)

### Usage:

#### Replacement for default:

If your mod depends on *default* for node sounds only, then you can easily switch to *sounds*. Simply add *default* & *sounds* as optional dependencies in your *mod.conf*. *sounds* overrides methods used by *default* to its own. For example *default.node_sound_dirt_defaults*.

Example of overidden method:
```lua
function sounds.node_dirt(tbl)
	tbl = tbl or {}

	tbl.footstep = tbl.footstep or {name="sounds_dirt_step", gain=0.4}
	tbl.dug = tbl.dug or {name="sounds_dirt_step", gain=1.0}
	tbl.place = tbl.place or {name="sounds_node_place_soft", gain=1.0}

	sounds.node(tbl)
	return tbl
end

default.node_sound_dirt_defaults = sounds.node_dirt
```

Example of setting node sounds:
```lua
minetest.register_node("foo:bar", {
	description = "Foo Node",
	-- this is the same as calling `sounds.node_stone()`
	sounds = default.node_sound_stone_defaults()
	...
})
```

#### Playing Sounds Manually:

`SoundGroup` instances are objects for storing & playing sounds. These objects can be called to play a sound from their group. An index can be specified when called to determine which sound to play. If the index parameter is omitted, a random sound will be picked. A table of arguments can also be passed. This is compatible with [SimpleSoundSpec](https://minetest.gitlab.io/minetest/sounds/#simplesoundspec).

Creating `SoundGroup` objects:
```lua
local s_group1 = SoundGroup({"sound1", "sound2"})
local s_group2 = SoundGroup({"sound3", "sound4", "sound5"})

-- SoundGroup objects can be concatenated with the arithmetic operator
local s_group3 = s_group1 + s_group2

-- strings can also be concatenated to group with arithmetic operator
s_group3 = s_group3 + "sound6"

-- by setting the `prepend` attribute `true`, sound file names will be prepended
-- with "sounds_" when played or accessed
s_group1(2) -- plays "sound2"

s_group1.prepend = true
s_group1(2) -- plays "sounds_sound2"
```

There are many [pre-defined sound groups](https://antummt.github.io/mod-sounds/reference/latest/topics/groups.html).

Calling a `SoundGroup` object:
```lua
-- play random sound from group
sounds.horse_neigh()

-- play specific sound from group
sounds.horse_neigh(2)

-- play random sound from group with parameters
sounds.horse_neigh({gain=1.0})

-- play specific sound from group with parameters
sounds.horse_neigh(2, {gain=1.0})

-- the `play` method is the same as calling the object directly
sounds.horse_neigh:play(2, {gain=1.0})
```

#### Node Sounds:

`SoundGroup` objects can also be used in node registration:
```lua
minetest.register_node("foo:bar", {
	description = "Foo Node",
	sounds = {
		-- a random sound from the `sounds.cow_moo` group will be played when digging this node
		dig = sounds.cow_moo,
	},
	...
```

Currently using `SoundGroup` for node sounds only works for "dig", "dug", & "place".

`SoundGroup` objects are tables & are indexed by integer. But using the `get` method is more reliable as it will return the string name with "sounds_" prefix if `prepend` is set:
```lua
local s_group1 = SoundGroup({"sound1", "sound2"})
local s1 = s_group1:get(1) -- returns "sound1"
local s2 = s_group1[2] -- returns "sound2"

local s_group2 = SoundGroup({"sound3", "sound4", prepend=true})
local s3 = s_group2:get(1) -- returns "sounds_sound3"
local s4 = s_group2[2] -- returns "sound4"
```

The built-in `type` function can be used to check for a `SoundGroup` instance:
```lua
if type(s_group1) == "SoundGroup" then
	s_group1()
end
```

#### Checking for Existing Sounds:

All mod sound files are stored in the global table `sounds.cache` after server startup. Checking if a file exists for playing is simple:

```lua
if sounds.cache["default_dig_crumbly"] then
	core.sound_play("default_dig_crumbly")
end
```

#### Testing Sounds:

If setting `sounds.enable_tests` is enabled, the chat command `/sounds_tests` can be used to show a formspec for playing & testing sounds.

To test *any* sound, input the sound name in the "Manual play" field & press the corresponding "Play" button. If the sound file exists, it will play & some info will be filled in the "Last played" field.

To test sounds cached in sound groups, select a group in the left column of the "Group play" field. Then select a sound in the right column & press the corresponding "Play" button.

Sounds can be looped by checking the "Loop" box.

#### Biome Ambiance:

A sound group can be registered for playing sounds randomly in a biome with the `sounds:register_biome_sounds` method (`sounds.enable_biome_sounds` must be enabled):

```
sounds:register_biome_sounds(biome, snds, params)
- Registers a sound group to be played in a biome.
- parameters:
  - biome:  Biome name.
  - snds:   string, table, or SoundGroup of sounds registered with biome.
  - params: SimpleSoundSpec parameters (optional).
```

Example usage:
```lua
sounds:register_biome_sounds("grassland", sounds.bird, {gain=0.25})
```

#### Settings:

```
sounds.disabled_groups
- Disables individual built-in sound groups categories. "all" disables all categories.
- type:    string (comma-separated list)
- default: empty

sounds.enable_tests
- Enables sounds testing with sounds_tests chat command.
- type:    bool
- default: false

sounds.enable_biome_sounds
- Enables/Disables ambiance sounds for biomes.
- type:    bool
- default: false

sounds.biome_interval
- Interval between playing biome sounds.
- type:    int
- min:     5
- default: 30

sounds.biome_chance
- Chance that sound will be played at interval.
- type:    int
- min:     0
- max:     100
- default: 20
```

### Links:

- [![ContentDB](https://content.minetest.net/packages/AntumDeluge/sounds/shields/title/)](https://content.minetest.net/packages/AntumDeluge/sounds/)
- [Forum](https://forum.minetest.net/viewtopic.php?t=26868)
- [Git repo](https://github.com/AntumMT/mod-sounds)
- [Reference](https://antummt.github.io/mod-sounds/reference/)
- [Changelog](changelog.txt)
- [TODO](TODO.txt)


[Minetest]: http://minetest.net/
[default]: https://github.com/minetest/minetest_game/tree/master/mods/default
