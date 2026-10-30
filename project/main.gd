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
@onready var timeline: Control = %Timeline

var time := 0.0
var steering := false
var interacting := 0   # fingers currently on the control pad
var hold_on := false   # keep sounding the current pose


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
	synth.auto_wobble = true
	synth.always_voice = false # sound only while touching, holding or playing
	synth.voice_held = false
	voicebox.held.connect(_on_interact)
	mouth_pad.held.connect(_on_interact)
	size_slider.held.connect(_on_interact)
	timeline.scrub_ended.connect(_update_voicing)
	%HoldButton.toggled.connect(func(on): hold_on = on; _update_voicing())
	%EaseSmooth.toggled.connect(func(on): timeline.set_selected_ease("smooth" if on else "linear"))
	voicebox.timeline = timeline
	pitch_pad.timeline = timeline
	pitch_pad.field_x = "px"
	pitch_pad.field_y = "py"
	mouth_pad.timeline = timeline
	mouth_pad.field_x = "mx"
	mouth_pad.field_y = "my"
	size_slider.timeline = timeline
	size_slider.field_x = "sz"
	size_slider.field_y = "sz"
	# Changing a control while a key is selected edits that key.
	for pad in [pitch_pad, mouth_pad, size_slider]:
		pad.user_edited.connect(_on_user_edit)
	voicebox.tongue_edited.connect(_on_user_edit)
	voicebox.closure_pressed.connect(func(id, i, d): _closure_edit(func(): timeline.closure_press(id, i, d)))
	voicebox.closure_moved.connect(func(id, i, d): _closure_edit(func(): timeline.closure_move(id, i, d)))
	voicebox.closure_released.connect(func(id, on): _closure_edit(func(): timeline.closure_release(id, on)))
	# Which lanes the timeline shows.
	var lane_bar := HFlowContainer.new()
	lane_bar.add_theme_constant_override("separation", 6)
	timeline.get_parent().add_child(lane_bar)
	timeline.get_parent().move_child(lane_bar, timeline.get_index())
	for lane in timeline.LANES:
		var b := Button.new()
		b.text = lane["label"]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = timeline.lane_ids.has(lane["id"])
		b.toggled.connect(timeline.set_lane.bind(lane["id"]))
		lane_bar.add_child(b)
	timeline.capture = Callable(self, "capture_frame")
	timeline.frame_changed.connect(apply_frame)
	timeline.playing_changed.connect(_on_playing_changed)
	timeline.recording_changed.connect(func(on): %RecButton.set_pressed_no_signal(on))
	%RecButton.toggled.connect(func(on): timeline.start_recording() if on else timeline.stop())
	%PlayButton.toggled.connect(func(on): timeline.play() if on else timeline.stop())
	%LoopButton.toggled.connect(func(on): timeline.looping = on)
	%AddKey.pressed.connect(func(): timeline.add_key(capture_frame(true)))
	%DeleteKey.pressed.connect(timeline.delete_selected)
	%ClearKeys.pressed.connect(timeline.clear)
	camera.look_at_from_position(Vector3(0, 2.5, 9.0), Vector3(0, 2.0, 0))
	_on_mouth_moved(mouth_pad.value)
	_on_size_moved(size_slider.value)


func _process(delta: float) -> void:
	time += delta
	var sel = timeline.selected
	%EaseSmooth.set_pressed_no_signal(sel != null and sel["ease"] == "smooth")
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


func _on_interact(on: bool) -> void:
	if on and timeline.playing:
		timeline.stop() # touching the pad takes over from playback
	interacting = maxi(0, interacting + (1 if on else -1))
	_update_voicing()


# Sound only while you're touching the control pad (or holding), unless a phrase is playing.
func _update_voicing() -> void:
	if synth and not timeline.playing:
		synth.voice_held = interacting > 0 or hold_on


func _on_pitch_held(on: bool) -> void:
	_on_interact(on)
	if on and timeline.selected != null and not timeline.playing:
		timeline.set_selected_voiced(true) # sounding a selected key makes it a voiced one
	if on:
		character.hop_vel = 2.4 # a little jump when you grab the pitch pad


func _on_mouth_moved(v: Vector2) -> void:
	if synth:
		synth.lips = v.x * 1.4 # left = closed, right = spread
		synth.jaw = v.y        # top = closed, bottom = open


func _on_size_moved(v: Vector2) -> void:
	if synth:
		synth.voice_size = 0.5 * pow(4.0, 1.0 - v.y) # slider up = giant (2), middle = 1, down = tiny (0.5)


# ---------------------------------------------------------------- timeline

# The controls as a frame (one pose) for the timeline to store.
func capture_frame(force_voiced := false) -> Dictionary:
	return {
		"px": pitch_pad.value.x, "py": pitch_pad.value.y,
		"mx": mouth_pad.value.x, "my": mouth_pad.value.y,
		"sz": size_slider.value.y,
		"ti": synth.get_tongue_index(), "td": synth.get_tongue_diameter(),
		"voiced": force_voiced or synth.voice_held,
		"cs": _current_closures(),
	}


# Puts a frame back onto the controls, which drives the synth and the character.
func apply_frame(f: Dictionary) -> void:
	if synth == null or f.is_empty():
		return
	pitch_pad.set_value(Vector2(f["px"], f["py"]))
	mouth_pad.set_value(Vector2(f["mx"], f["my"]))
	size_slider.set_value(Vector2(0.5, f["sz"]))
	synth.set_tongue(f["ti"], f["td"])
	voicebox.set_closures(f.get("cs", []))
	if timeline.playing or timeline.is_scrubbing():
		synth.voice_held = f["voiced"]


func _on_user_edit() -> void:
	if timeline.selected != null and not timeline.playing and not timeline.recording:
		timeline.update_selected(capture_frame())


# Closures held by fingers now, or else those the current pose is holding.
func _current_closures() -> Array:
	var held: Array = voicebox.active_closures()
	return held if not held.is_empty() else voicebox.applied_closures.duplicate(true)


# Editing closures with a key selected changes that key, and the key's closures stay held.
func _closure_edit(edit: Callable) -> void:
	if timeline.selected != null and not timeline.playing and not timeline.recording:
		edit.call()
		voicebox.set_closures(timeline.closures_of_selected())


# While a phrase plays, the key's own voicing decides when it sounds.
func _on_playing_changed(on: bool) -> void:
	%PlayButton.set_pressed_no_signal(on)
	if synth == null:
		return
	if not on:
		voicebox.set_closures([])
		synth.voice_held = false
		_update_voicing()


# Keyboard, as in the web game: space or P plays, K adds a key, H holds, L loops, R records,
# Delete removes the selected key, [ and ] step through keys, Escape lets go.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or synth == null:
		return
	match event.keycode:
		KEY_SPACE, KEY_P:
			if timeline.playing:
				timeline.stop()
			else:
				timeline.play()
		KEY_K:
			timeline.add_key(capture_frame(true))
		KEY_H:
			%HoldButton.button_pressed = not %HoldButton.button_pressed
		KEY_L:
			%LoopButton.button_pressed = not %LoopButton.button_pressed
		KEY_R:
			%RecButton.button_pressed = not %RecButton.button_pressed
		KEY_DELETE, KEY_BACKSPACE:
			timeline.delete_selected()
		KEY_BRACKETLEFT:
			timeline.select_neighbour(-1)
		KEY_BRACKETRIGHT:
			timeline.select_neighbour(1)
		KEY_ESCAPE:
			timeline.stop()
			timeline.deselect()
		_:
			return
	get_viewport().set_input_as_handled()
