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
@onready var character: Node3D = %Character
@onready var camera: Camera3D = %Camera
@onready var character_view: Control = %CharacterView

var time := 0.0
var steering := false


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

	synth.setup(AudioServer.get_mix_rate())
	var player := AudioStreamPlayer.new()
	# The synth runs on Godot's audio thread through its own stream, so what
	# you drag is heard within one audio buffer.
	player.stream = synth.create_stream()
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM # web defaults to "sample" playback, which can't play these
	add_child(player)
	player.play()

	if "tongue_full_range" in synth:
		synth.tongue_full_range = true # the tongue can go anywhere in its slice, not just the original triangle
	voicebox.synth = synth
	camera.look_at_from_position(Vector3(0, 2.5, 9.0), Vector3(0, 2.0, 0))
	_on_mouth_moved(mouth_pad.value)
	_on_size_moved(size_slider.value)


func _process(delta: float) -> void:
	time += delta
	_keyboard_walk()
	character.update_character(delta, _face(), time)


# What the character's face should be doing, worked out from the synth's current settings.
func _face() -> Dictionary:
	if synth == null:
		return {}
	var octaves := log(maxf(20.0, synth.frequency) / 140.0) / log(2.0)
	var tense: float = synth.tenseness
	var level: float = synth.get_level()
	var talking := 1.0 if level > 0.008 else 0.0
	var loud := clampf((level - 0.03) / 0.08, 0.0, 1.0) * talking
	var jaw: float = synth.jaw
	var lips: float = synth.lips
	var shut := lips < 0.08
	var low := clampf((synth.get_tongue_diameter() - 2.05) / (3.5 - 2.05), 0.0, 1.0)
	var open := 0.0 if shut else clampf((jaw - 0.25) * 1.6 + 0.25 * low, 0.0, 1.0)
	return {
		"open": open,
		"size": clampf(log(maxf(0.25, synth.voice_size)) / log(2.0), -1.0, 1.0),
		"lips": clampf(lips / 1.4, 0.0, 1.2),
		"jaw": jaw,
		"shut": shut,
		"tilt": clampf(octaves * 0.18, -0.35, 0.35),
		"brow": clampf(octaves * 0.9, -1.0, 1.5),
		"talking": talking,
		"loud": loud,
		"angry": clampf((tense - 0.7) / 0.25, 0.0, 1.0) * loud,
		"sad": clampf((0.45 - tense) / 0.35, 0.0, 1.0) if talking > 0.5 else 0.0,
	}


# Click or drag in the character's area to make it walk there; arrow keys / WASD work too.
func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		steering = event.pressed
		if event.pressed:
			_walk_towards(event.position)
	elif event is InputEventMouseMotion and steering:
		_walk_towards(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		_walk_towards(event.position)
	elif event is InputEventScreenDrag:
		_walk_towards(event.position)


func _walk_towards(pos: Vector2) -> void:
	var from := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if hit != null:
		character.walk_to(Vector3(clampf(hit.x, -0.7, 0.7), 0.0, clampf(hit.z, -1.0, 0.8)))


func _keyboard_walk() -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.z += 1.0
	if dir != Vector3.ZERO:
		var p: Vector3 = character.position + dir.normalized() * 0.5
		character.walk_to(Vector3(clampf(p.x, -0.7, 0.7), 0.0, clampf(p.z, -1.0, 0.8)))


func _on_pitch_moved(v: Vector2) -> void:
	if not synth:
		return
	synth.frequency = BASE_NOTE * pow(2.0, SEMITONES * v.x / 12.0)
	synth.tenseness = 1.0 - cos((1.0 - v.y) * PI / 2.0) # top = tense, bottom = breathy


func _on_pitch_held(on: bool) -> void:
	if synth:
		synth.voice_held = on
	if on:
		character.hop_vel = 2.4 # a little jump when you grab the pitch pad


func _on_mouth_moved(v: Vector2) -> void:
	if synth:
		synth.lips = v.x * 1.4 # left = closed, right = spread
		synth.jaw = v.y        # top = closed, bottom = open


func _on_size_moved(v: Vector2) -> void:
	if synth:
		synth.voice_size = 0.5 * pow(4.0, 1.0 - v.y) # slider up = giant (2), middle = 1, down = tiny (0.5)


func _on_always_voice_toggled(on: bool) -> void:
	if synth:
		synth.always_voice = on


func _on_pitch_wobble_toggled(on: bool) -> void:
	if synth:
		synth.auto_wobble = on


func _on_hum_toggled(on: bool) -> void:
	if synth:
		synth.velum_open = on
