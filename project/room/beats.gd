extends Node
## The stage's drum machine: four synthesised drums (no samples) on a 16-step pattern, two
## bars at 120 bpm, so one loop is exactly as long as a phrase (4 s). Ported from the web
## game's client/beats.js. `clock` is the beat clock in seconds; main.gd uses it to start
## phrases on the downbeat.

signal stepped(step: int, hits: Array)

const BPM := 120.0
const LOOP_SECONDS := 4.0
const STEPS := 16
const STEP_SECONDS := LOOP_SECONDS / STEPS   # 0.25 s: an eighth note
const DRUMS := ["kick", "snare", "hat", "clap"]
const HEARING_FULL := 8.0                    # world units from the stage
const HEARING_SILENT := 34.0

var pattern: Array = []          # [drum][step] -> bool
var clock := 0.0                 # seconds since the machine started
var _next_step := 0
var _sounds: Array = []          # one AudioStreamWAV per drum
var _player: AudioStreamPlayer
var _playback: AudioStreamPlaybackPolyphonic
var _rate := 44100.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	pattern = default_pattern()
	_rate = AudioServer.get_mix_rate()
	_sounds = [_kick(), _snare(), _hat(), _clap()]
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 16
	_player = AudioStreamPlayer.new()
	_player.stream = poly
	_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	set_volume(0.0)


static func default_pattern() -> Array:
	var rows: Array = []
	for steps in [[0, 4, 8, 11, 12], [2, 6, 10, 14], range(16), []]:
		var row: Array = []
		for i in STEPS:
			row.append(steps.has(i))
		rows.append(row)
	return rows


func toggle(drum: int, step: int) -> void:
	pattern[drum][step] = not pattern[drum][step]


func clear() -> void:
	for row in pattern:
		for i in STEPS:
			row[i] = false


func current_step() -> int:
	return int(clock / STEP_SECONDS) % STEPS


## How far into the 2-bar loop we are (0 .. 4 s).
func loop_position() -> float:
	return fmod(clock, LOOP_SECONDS)


## Louder the closer you are to the stage.
func set_volume(v: float) -> void:
	_player.volume_db = linear_to_db(maxf(v, 0.0001))


static func volume_at(distance: float) -> float:
	var k := clampf((distance - HEARING_FULL) / (HEARING_SILENT - HEARING_FULL), 0.0, 1.0)
	return (1.0 - k) * (1.0 - k)


func _process(delta: float) -> void:
	clock += delta
	# Play every step whose time has come (skip any we're very late for).
	while _next_step * STEP_SECONDS <= clock:
		var late := clock - _next_step * STEP_SECONDS
		var step := _next_step % STEPS
		var hits: Array = []
		for drum in DRUMS.size():
			if pattern[drum][step]:
				hits.append(drum)
				if late < 0.1 and _playback:
					_playback.play_stream(_sounds[drum])
		stepped.emit(step, hits)
		_next_step += 1


# ---------------------------------------------------------------- the drums

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(_rate)
	w.stereo = false
	w.data = data
	return w


func _noise(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = _rng.randf() * 2.0 - 1.0
	return out


# A biquad filter (RBJ cookbook), "highpass" or "bandpass", run over the samples in place.
func _filter(x: PackedFloat32Array, kind: String, freq: float, q := 0.7071) -> void:
	var w0 := TAU * freq / _rate
	var alpha := sin(w0) / (2.0 * q)
	var c := cos(w0)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	if kind == "highpass":
		b0 = (1.0 + c) / 2.0
		b1 = -(1.0 + c)
		b2 = (1.0 + c) / 2.0
	else:
		b0 = alpha
		b1 = 0.0
		b2 = -alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * c
	var a2 := 1.0 - alpha
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var y := (b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = x[i]
		y2 = y1
		y1 = y
		x[i] = y


# Exponential fade from `level` to almost nothing over `length` seconds.
func _env(i: int, level: float, length: float) -> float:
	return level * pow(0.001, (i / _rate) / length)


# A sine that drops in pitch fast: boom.
func _kick() -> AudioStreamWAV:
	var n := int(0.4 * _rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := i / _rate
		var f := 150.0 * pow(45.0 / 150.0, minf(t / 0.12, 1.0))
		phase += TAU * f / _rate
		out[i] = sin(phase) * _env(i, 0.9, 0.35)
	return _wav(out)


# Noise through a high-pass, plus a short body tone: tsh.
func _snare() -> AudioStreamWAV:
	var n := int(0.2 * _rate)
	var noise := _noise(n)
	_filter(noise, "highpass", 1500.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := i / _rate
		var tri := 2.0 * absf(2.0 * fmod(t * 190.0, 1.0) - 1.0) - 1.0
		out[i] = noise[i] * _env(i, 0.5, 0.18) + (tri * _env(i, 0.35, 0.1) if t < 0.12 else 0.0)
	return _wav(out)


# A very short, very bright tick.
func _hat() -> AudioStreamWAV:
	var n := int(0.065 * _rate)
	var noise := _noise(n)
	_filter(noise, "highpass", 7500.0)
	for i in n:
		noise[i] *= _env(i, 0.22, 0.045)
	return _wav(noise)


# Three quick bursts of band-passed noise, like hands.
func _clap() -> AudioStreamWAV:
	var n := int(0.2 * _rate)
	var noise := _noise(n)
	_filter(noise, "bandpass", 1400.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for burst in [[0.0, 0.02], [0.012, 0.02], [0.024, 0.14]]:
		var start := int(burst[0] * _rate)
		for i in range(start, n):
			out[i] += noise[i] * _env(i - start, 0.45, burst[1])
	return _wav(out)
