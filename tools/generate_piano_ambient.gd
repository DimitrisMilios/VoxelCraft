extends SceneTree

func _init() -> void:
	print("--- Generating Ambient Piano Tracks ---")
	var track1_path := "res://assets/audio/music_ambient_01.wav"
	_generate_ambient_piano_track(track1_path, 1337)
	var track2_path := "res://assets/audio/music_ambient_02.wav"
	_generate_ambient_piano_track(track2_path, 4242)
	var track3_path := "res://assets/audio/music_ambient_03.wav"
	_generate_ambient_piano_track(track3_path, 9876)
	print("--- Completed Music Generation ---")
	quit(0)

func _generate_ambient_piano_track(save_path: String, seed_val: int) -> void:
	var sample_rate: int = 22050
	var bpm: float = 46.0
	var beat_sec: float = 60.0 / bpm
	var total_beats: int = 48 # ~62 seconds
	var total_samples: int = int(float(total_beats) * beat_sec * float(sample_rate))

	var buffer := PackedFloat32Array()
	buffer.resize(total_samples)
	buffer.fill(0.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Note frequencies (Hz) for C Major / A Minor pentatonic scale
	var notes: Dictionary = {
		"C3": 130.81, "E3": 164.81, "G3": 196.00, "A3": 220.00, "B3": 246.94,
		"C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.00,
		"A4": 440.00, "B4": 493.88, "C5": 523.25, "D5": 587.33, "E5": 659.25,
		"G5": 783.99, "A5": 880.00
	}

	# Chord sequences (each chord lasts 4 beats)
	var chord_progressions: Array = [
		[["C3", "G3", "C4", "E4"], ["G3", "D4", "G4", "B4"], ["A3", "E4", "A4", "C5"], ["F3", "C4", "F4", "A4"]],
		[["F3", "C4", "E4", "A4"], ["C3", "G3", "C4", "E4"], ["D3", "A3", "C4", "F4"], ["G3", "D4", "F4", "B4"]],
		[["A3", "E4", "G4", "C5"], ["E3", "B3", "E4", "G4"], ["F3", "C4", "F4", "A4"], ["C3", "G3", "D4", "G4"]]
	]
	var progression: Array = chord_progressions[rng.randi() % chord_progressions.size()]

	var lead_notes: Array[String] = ["E4", "G4", "A4", "C5", "D5", "E5", "G5"]

	for chord_idx in range(progression.size()):
		var chord: Array = progression[chord_idx]
		var chord_start_beat: float = float(chord_idx) * 4.0

		# Arpeggiate chord notes
		for n_idx in range(chord.size()):
			var note_name: String = chord[n_idx]
			var freq: float = notes.get(note_name, 261.63)
			var start_time: float = (chord_start_beat + float(n_idx) * 0.45) * beat_sec
			_render_note(buffer, sample_rate, freq, start_time, 4.5, 0.28)

		# Add a melody note
		if rng.randf() > 0.2:
			var mel_note: String = lead_notes[rng.randi() % lead_notes.size()]
			var mel_freq: float = notes.get(mel_note, 523.25)
			var mel_time: float = (chord_start_beat + 2.0 + rng.randf_range(0.0, 0.8)) * beat_sec
			_render_note(buffer, sample_rate, mel_freq, mel_time, 3.8, 0.22)

	# Repeat progression once with subtle melodic variation
	var second_prog: Array = chord_progressions[rng.randi() % chord_progressions.size()]
	for chord_idx in range(second_prog.size()):
		var chord: Array = second_prog[chord_idx]
		var chord_start_beat: float = 16.0 + float(chord_idx) * 4.0
		for n_idx in range(chord.size()):
			var note_name: String = chord[n_idx]
			var freq: float = notes.get(note_name, 261.63)
			var start_time: float = (chord_start_beat + float(n_idx) * 0.45) * beat_sec
			_render_note(buffer, sample_rate, freq, start_time, 4.5, 0.28)
		if rng.randf() > 0.15:
			var mel_note: String = lead_notes[rng.randi() % lead_notes.size()]
			var mel_freq: float = notes.get(mel_note, 523.25)
			var mel_time: float = (chord_start_beat + 1.8 + rng.randf_range(0.0, 0.6)) * beat_sec
			_render_note(buffer, sample_rate, mel_freq, mel_time, 3.5, 0.22)

	# Convert to 16-bit PCM WAV
	var byte_data := PackedByteArray()
	byte_data.resize(total_samples * 2)

	# Find peak amplitude for normalization
	var peak: float = 0.0001
	for s in buffer:
		peak = maxf(peak, absf(s))
	var norm_scale: float = 0.85 / peak

	for i in range(total_samples):
		var sample_val: float = clampf(buffer[i] * norm_scale, -0.999, 0.999)
		var val16: int = int(sample_val * 32767.0)
		if val16 < 0:
			val16 += 65536
		byte_data[i * 2] = val16 & 0xFF
		byte_data[i * 2 + 1] = (val16 >> 8) & 0xFF

	# Also save native Godot AudioStreamWAV resource (.tres) for instant zero-import loading
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = byte_data
	var tres_path: String = save_path.replace(".wav", ".tres")
	ResourceSaver.save(wav, tres_path)
	print("Saved native resource: %s" % tres_path)
	var abs_path: String = ProjectSettings.globalize_path(save_path)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	if f != null:
		var byte_rate: int = sample_rate * 1 * 2
		var block_align: int = 2
		var data_size: int = byte_data.size()
		var chunk_size: int = 36 + data_size

		f.store_string("RIFF")
		f.store_32(chunk_size)
		f.store_string("WAVE")
		f.store_string("fmt ")
		f.store_32(16)
		f.store_16(1)
		f.store_16(1)
		f.store_32(sample_rate)
		f.store_32(byte_rate)
		f.store_16(block_align)
		f.store_16(16)
		f.store_string("data")
		f.store_32(data_size)
		f.store_buffer(byte_data)
		f.close()
		print("Saved valid WAV file: %s (%.1fs)" % [abs_path, float(total_samples) / float(sample_rate)])
	else:
		push_error("Failed to open file: " + abs_path)

func _render_note(buffer: PackedFloat32Array, sample_rate: int, freq: float, start_time: float, duration: float, volume: float) -> void:
	var start_idx: int = int(start_time * float(sample_rate))
	var num_samples: int = int(duration * float(sample_rate))
	var end_idx: int = mini(start_idx + num_samples, buffer.size())
	if start_idx >= buffer.size():
		return

	var tau: float = TAU
	for i in range(start_idx, end_idx):
		var t: float = float(i - start_idx) / float(sample_rate)
		# Piano harmonic timbre: Fundamental + warm octave + 5th + octave 2
		var harm1: float = sin(tau * freq * t) * 0.60
		var harm2: float = sin(tau * freq * 2.0 * t) * 0.25
		var harm3: float = sin(tau * freq * 3.0 * t) * 0.10
		var harm4: float = sin(tau * freq * 4.0 * t) * 0.05
		# Subtle detuned chorus string for acoustic realism
		var detune: float = sin(tau * (freq + 0.35) * t) * 0.18
		var timbre: float = (harm1 + harm2 + harm3 + harm4 + detune) * 0.85

		# Natural piano attack + exponential decay envelope
		var attack: float = clampf(t / 0.008, 0.0, 1.0)
		var decay: float = exp(-t * 1.05)
		var env: float = attack * decay * volume

		buffer[i] += timbre * env
