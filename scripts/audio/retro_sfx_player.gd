class_name RetroSfxPlayer
extends Node
## Procedural retro sound synthesizer using in-memory 16-bit PCM AudioStreamWAV buffers.
## Generates footsteps, swimming splashes, jump sweeps, block break crunches, and block place pops
## with zero external audio asset dependencies.

const MIX_RATE: int = 22050
const POOL_SIZE: int = 6

var _players: Array[AudioStreamPlayer] = []
var _next_player_idx: int = 0

var _sfx_break: AudioStreamWAV = null
var _sfx_place: AudioStreamWAV = null
var _sfx_step: AudioStreamWAV = null
var _sfx_swim: AudioStreamWAV = null
var _sfx_jump: AudioStreamWAV = null
var _sfx_tick: AudioStreamWAV = null


func _ready() -> void:
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.volume_db = -6.0
		add_child(player)
		_players.append(player)

	_synthesize_all_streams()
	call_deferred("_bind_signals")


func _bind_signals() -> void:
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		return

	player.step_taken.connect(_on_step_taken)
	player.jumped.connect(_on_player_jumped)
	player.water_state_changed.connect(_on_water_state_changed)

	var interactor := player.get_node_or_null("BlockInteractor") as BlockInteractor
	if interactor != null:
		interactor.block_broken.connect(_on_block_broken)
		interactor.block_placed.connect(_on_block_placed)
		interactor.hotbar_slot_changed.connect(_on_hotbar_slot_changed)


func _on_step_taken(in_water: bool) -> void:
	if in_water:
		_play_stream(_sfx_swim, -9.0, randf_range(0.88, 1.12))
	else:
		_play_stream(_sfx_step, -11.0, randf_range(0.90, 1.14))


func _on_player_jumped() -> void:
	_play_stream(_sfx_jump, -10.0, randf_range(0.95, 1.06))


func _on_water_state_changed(_in_water: bool) -> void:
	_play_stream(_sfx_swim, -5.5, randf_range(0.82, 1.05))


func _on_block_broken(_world_pos: Vector3i, block_id: int) -> void:
	var base_pitch: float = 1.0
	if block_id == BlockRegistry.BlockId.STONE or block_id == BlockRegistry.BlockId.COBBLESTONE:
		base_pitch = 0.82
	elif block_id == BlockRegistry.BlockId.LEAVES or block_id == BlockRegistry.BlockId.SAND:
		base_pitch = 1.22
	_play_stream(_sfx_break, -4.5, base_pitch * randf_range(0.92, 1.08))


func _on_block_placed(_world_pos: Vector3i, block_id: int) -> void:
	var base_pitch: float = 1.0
	if block_id == BlockRegistry.BlockId.WOOD_LOG or block_id == BlockRegistry.BlockId.WOOD_PLANKS:
		base_pitch = 0.90
	_play_stream(_sfx_place, -5.5, base_pitch * randf_range(0.94, 1.08))


func _on_hotbar_slot_changed(_slot_index: int, _block_id: int) -> void:
	_play_stream(_sfx_tick, -12.0, randf_range(0.96, 1.04))


func _play_stream(stream: AudioStreamWAV, volume_db: float, pitch_scale: float) -> void:
	if stream == null or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next_player_idx]
	_next_player_idx = (_next_player_idx + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch_scale
	p.play()


func _synthesize_all_streams() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	# 1. Block Break Crunch (0.14s): Low-pass filtered noise + downward bass thud
	_sfx_break = _build_wav(0.14, func(t: float, dur: float) -> float:
		var env: float = pow(1.0 - (t / dur), 1.6)
		var freq: float = lerpf(185.0, 68.0, t / dur)
		var tone: float = sin(t * freq * TAU) * 0.55
		var crackle: float = rng.randf_range(-1.0, 1.0) * (0.75 if int(t * 950.0) % 2 == 0 else 0.25)
		return (tone + crackle) * env * 0.75
	)

	# 2. Block Place Pop (0.09s): Two-step pitch pop + crisp click
	_sfx_place = _build_wav(0.09, func(t: float, dur: float) -> float:
		var env: float = pow(1.0 - (t / dur), 1.8)
		var freq: float = 210.0 if t < 0.035 else 330.0
		var tone: float = sin(t * freq * TAU) * 0.65
		var click: float = rng.randf_range(-0.4, 0.4) * (1.0 if t < 0.015 else 0.15)
		return (tone + click) * env * 0.8
	)

	# 3. Footstep Tap (0.065s): Soft muffled terrain thud
	_sfx_step = _build_wav(0.065, func(t: float, dur: float) -> float:
		var env: float = pow(1.0 - (t / dur), 2.2)
		var thud: float = sin(t * 115.0 * TAU) * 0.5
		var grit: float = rng.randf_range(-0.5, 0.5)
		return (thud + grit) * env * 0.65
	)

	# 4. Water Swim / Splash (0.16s): Bubbly FM-modulated water slosh
	_sfx_swim = _build_wav(0.16, func(t: float, dur: float) -> float:
		var env: float = sin((t / dur) * PI)
		var bubble_freq: float = 260.0 + sin(t * 48.0 * TAU) * 110.0
		var bubble: float = sin(t * bubble_freq * TAU) * 0.45
		var spray: float = rng.randf_range(-0.45, 0.45) * 0.5
		return (bubble + spray) * env * 0.7
	)

	# 5. Jump Sweep (0.085s): Subtle upward retro pitch sweep
	_sfx_jump = _build_wav(0.085, func(t: float, dur: float) -> float:
		var env: float = pow(1.0 - (t / dur), 1.4)
		var freq: float = lerpf(150.0, 275.0, t / dur)
		return sin(t * freq * TAU) * env * 0.55
	)

	# 6. Hotbar UI Tick (0.025s): Crisp high-pitched micro click
	_sfx_tick = _build_wav(0.025, func(t: float, dur: float) -> float:
		var env: float = pow(1.0 - (t / dur), 2.5)
		return sin(t * 780.0 * TAU) * env * 0.5
	)


func _build_wav(duration_sec: float, sample_fn: Callable) -> AudioStreamWAV:
	var sample_count: int = int(duration_sec * float(MIX_RATE))
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)

	for i in range(sample_count):
		var t: float = float(i) / float(MIX_RATE)
		var val: float = clampf(float(sample_fn.call(t, duration_sec)), -1.0, 1.0)
		var sample_i16: int = int(round(val * 32767.0))
		pcm.encode_s16(i * 2, sample_i16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = pcm
	return wav
