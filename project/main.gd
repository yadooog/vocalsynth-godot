extends Control
## Owns the synth and the sound output, and connects the side controls to it.

const BASE_NOTE := 87.3071 # F2, left edge of the pitch pad
const SEMITONES := 24
const MARKS := [0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0]

var synth # PinkTrombone (untyped so this script still loads if the engine is missing)

@onready var voicebox: Control = %Voicebox
@onready var pitch_pad: Control = %PitchPad
@onready var mouth_pad: Control = %MouthPad
@onready var size_slider: Control = %SizeSlider


func _ready() -> void:
	var marks := PackedInt32Array()
	for i in SEMITONES:
		if MARKS[(i + 3) % 12] == 1:
			marks.append(i)
	pitch_pad.lines = SEMITONES
	pitch_pad.marked_lines = marks

	if not ClassDB.class_exists("PinkTrombone"):
		push_error("PinkTrombone engine not found. The compiled files in project/bin/ are missing for this computer; see README.")
		return
	synth = ClassDB.instantiate("PinkTrombone")

	# The synth runs on Godot's audio thread through its own stream, so what you
	# drag is heard within one audio buffer.
	synth.setup(AudioServer.get_mix_rate())
	var player := AudioStreamPlayer.new()
	player.stream = synth.create_stream()
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM # web defaults to "sample" playback, which can't play this
	add_child(player)
	player.play()

	voicebox.synth = synth
	if OS.has_feature("web"):
		get_tree().create_timer(3.0).timeout.connect(func():
			print("debug: synth time %.3f playing %s rate %s" % [synth.get_time(), player.playing, AudioServer.get_mix_rate()]))
	_on_mouth_moved(mouth_pad.value)
	_on_size_moved(size_slider.value)


func _on_pitch_moved(v: Vector2) -> void:
	if not synth:
		return
	synth.frequency = BASE_NOTE * pow(2.0, SEMITONES * v.x / 12.0)
	synth.tenseness = 1.0 - cos((1.0 - v.y) * PI / 2.0) # top = tense, bottom = breathy


func _on_pitch_held(on: bool) -> void:
	if synth:
		synth.voice_held = on


func _on_mouth_moved(v: Vector2) -> void:
	if synth:
		synth.lips = v.x * 1.4 # left = closed, right = spread
		synth.jaw = v.y        # top = closed, bottom = open


func _on_size_moved(v: Vector2) -> void:
	if synth:
		synth.voice_size = 0.5 * pow(4.0, v.x) # 0.5 (tiny) .. 1 (middle) .. 2 (giant)


func _on_always_voice_toggled(on: bool) -> void:
	if synth:
		synth.always_voice = on


func _on_pitch_wobble_toggled(on: bool) -> void:
	if synth:
		synth.auto_wobble = on


func _on_hum_toggled(on: bool) -> void:
	if synth:
		synth.velum_open = on
