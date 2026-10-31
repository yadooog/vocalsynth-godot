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
	%EaseSmooth.pressed.connect(func(): timeline.set_selected_ease("smooth"))
	%EaseLinear.pressed.connect(func(): timeline.set_selected_ease("linear"))
	%PrevKey.pressed.connect(func(): timeline.select_neighbour(-1))
	%NextKey.pressed.connect(func(): timeline.select_neighbour(1))
	%HelpButton.pressed.connect(func(): %Help.visible = true)
	%HelpClose.pressed.connect(func(): %Help.visible = false)
	%Help.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: %Help.visible = false)
	%Text.text = HELP
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
	for lane in timeline.LANES:
		var b := Button.new()
		b.text = lane["label"]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = timeline.lane_ids.has(lane["id"])
		b.toggled.connect(timeline.set_lane.bind(lane["id"]))
		%LaneToggles.add_child(b)
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
	room = preload("res://room/room.gd").new()
	character.get_parent().add_child(room)
	beats = preload("res://room/beats.gd").new()
	add_child(beats)
	beats.stepped.connect(func(_step, hits): if hits.has(0): room.thump())
	%BeatGrid.beats = beats
	%BeatClear.pressed.connect(beats.clear)
	%LoopBeat.toggled.connect(_on_loop_beat_toggled)
	character.position = Vector3(0, 0, 4)
	cam_target = character.position
	_on_mouth_moved(mouth_pad.value)
	_on_size_moved(size_slider.value)
	resized.connect(_layout)
	%ControlsCard.minimum_size_changed.connect(_layout)
	%TimelineCard.minimum_size_changed.connect(_layout)
	_layout.call_deferred()


func _process(delta: float) -> void:
	time += delta
	var sel = timeline.selected
	%EaseSmooth.set_pressed_no_signal(sel != null and sel["ease"] == "smooth")
	%EaseLinear.set_pressed_no_signal(sel != null and sel["ease"] != "smooth")
	for b in [%EaseLinear, %EaseSmooth, %DeleteKey]:
		b.disabled = sel == null
	%KeyLabel.modulate.a = 1.0 if sel != null else 0.45
	_walk(delta)
	_update_camera(delta)
	_update_stage()
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


# ---------------------------------------------------------------- the stage
# Drums play from the stage, louder the closer you are; the step sequencer shows while
# you stand on ~/stage. "Loop on beat" starts your phrase on every downbeat (a phrase is
# 4 s = exactly 2 bars at 120 bpm), so it stays in time with the drums.

func _update_stage() -> void:
	if beats == null:
		return
	var x := character.position.x
	var z := character.position.z
	beats.set_volume(0.8 * beats.volume_at(Vector2(x - World.STAGE["x"], z - World.STAGE["z"]).length()))
	%BeatPanel.visible = World.on_stage(x, z)
	var lp: float = beats.loop_position()
	if loop_beat and interacting == 0 and not timeline.recording:
		if timeline.follow_clock:
			timeline.t = lp
		elif lp < _last_loop_pos: # a new loop just started
			timeline.play_on_clock(lp)
	_last_loop_pos = lp


func _on_loop_beat_toggled(on: bool) -> void:
	loop_beat = on
	if not on and timeline.follow_clock:
		timeline.stop()


# ---------------------------------------------------------------- walking and camera
# Walk with WASD / arrow keys, or press and drag anywhere in the room (a floating joystick).
# Scroll to zoom. The camera follows from above and behind, like the web game.

const JOYSTICK_RANGE := 60.0   # px of drag for full speed
const ZOOM_MIN := 0.22         # closest: about face height
const ZOOM_MAX := 1.8          # furthest out
var stick = null               # [origin, current] while dragging in the room
var zoom := 1.0
var zoom_shown := 1.0
var cam_target := Vector3.ZERO
var room: Node3D
var beats: Node
var loop_beat := false
var _last_loop_pos := 0.0


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			stick = [event.position, event.position] if event.pressed else null
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 0.9, ZOOM_MIN, ZOOM_MAX)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom / 0.9, ZOOM_MIN, ZOOM_MAX)
	elif event is InputEventMouseMotion and stick != null:
		stick[1] = event.position
	elif event is InputEventScreenTouch:
		stick = [event.position, event.position] if event.pressed else null
	elif event is InputEventScreenDrag and stick != null:
		stick[1] = event.position
	elif event is InputEventMagnifyGesture:
		zoom = clampf(zoom / event.factor, ZOOM_MIN, ZOOM_MAX)


func _walk_input() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		d.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		d.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		d.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		d.y += 1.0
	if stick != null:
		var s: Vector2 = (stick[1] - stick[0]) / JOYSTICK_RANGE
		if s.length() > 0.15:
			d += s / s.length() * minf(1.0, s.length())
	return d.limit_length(1.0)


func _walk(delta: float) -> void:
	var input := _walk_input()
	if input.length() < 0.01:
		character.drive_speed = 0.0
		return
	var p := Vector2(character.position.x, character.position.z)
	var np := World.step(p, input, delta)
	character.position = Vector3(np.x, 0.0, np.y)
	character.drive_speed = (np - p).length() / maxf(delta, 1e-3)
	character.rotation.y = lerp_angle(character.rotation.y, atan2(input.x, input.y), 1.0 - exp(-14.0 * delta))


func _update_camera(delta: float) -> void:
	cam_target = cam_target.lerp(Vector3(character.position.x, 0, character.position.z), 1.0 - exp(-5.0 * delta))
	zoom_shown += (zoom - zoom_shown) * (1.0 - exp(-12.0 * delta))
	var z := zoom_shown
	var back := 17.0 * z
	var near := smoothstep(0.0, 1.0, (1.0 - z) / (1.0 - ZOOM_MIN))
	var up := 0.95 - 0.7 * near
	var look_y := 1.4 + 0.9 * near
	var eye := Vector3(cam_target.x, look_y * near + back * up, cam_target.z + back)
	var look := Vector3(cam_target.x, look_y, cam_target.z)
	camera.look_at_from_position(eye, look)
	# Shift the view so the character sits at `focus` on screen, not hidden behind the panels.
	var view := character_view.size
	var px_per_unit := (view.y * 0.5) / (eye.distance_to(look) * tan(deg_to_rad(camera.fov) * 0.5))
	camera.h_offset = -(focus.x - view.x * 0.5) / px_per_unit
	camera.v_offset = (focus.y - view.y * 0.5) / px_per_unit


# ---------------------------------------------------------------- layout
# Like the web game: the room fills the screen. Bottom left, the control pad above the controls
# card; bottom right, the timeline, level with the controls. The control pad is scaled to fit.

const GAP := 16.0
const ROW_GAP := 10.0
const TOP_SPACE := 64.0        # room left for the top bar
var focus := Vector2(640, 300) # where the character should appear on screen


func _layout() -> void:
	var screen := size
	var pad: Control = %Pad
	var pad_card: Control = %PadCard
	var controls: Control = %ControlsCard
	var tl: Control = %TimelineCard
	pad.size = pad.get_combined_minimum_size()
	var natural := pad.size
	var inset := Vector2(14, 18)   # space between the card's edge and the control pad
	var controls_h := controls.get_combined_minimum_size().y
	var room_h := screen.y - GAP - controls_h - ROW_GAP - TOP_SPACE - inset.y * 2.0
	var widest := minf(500.0, screen.x * 0.36) - inset.x * 2.0
	var k := clampf(minf(room_h / natural.y, widest / natural.x), 0.3, 1.0)
	var left_w := maxf(natural.x * k + inset.x * 2.0, 340.0)
	pad.scale = Vector2(k, k)
	pad.position = Vector2((left_w - natural.x * k) * 0.5, inset.y)
	%PadHolder.custom_minimum_size = Vector2(left_w, natural.y * k + inset.y * 2.0)

	var controls_top := screen.y - GAP - controls_h
	controls.position = Vector2(GAP, controls_top)
	controls.size = Vector2(left_w, controls_h)
	pad_card.size = Vector2(left_w, %PadHolder.custom_minimum_size.y)
	pad_card.position = Vector2(GAP, controls_top - ROW_GAP - pad_card.size.y)

	var right_x := GAP + left_w + ROW_GAP
	var tl_h := maxf(controls_h, tl.get_combined_minimum_size().y)
	tl.position = Vector2(right_x, screen.y - GAP - tl_h)
	tl.size = Vector2(screen.x - GAP - right_x, tl_h)

	var beat: Control = %BeatPanel
	var beat_w := minf(500.0, screen.x - right_x - GAP)
	beat.size = Vector2(beat_w, beat.get_combined_minimum_size().y)
	beat.position = Vector2(screen.x - GAP - beat_w, tl.position.y - ROW_GAP - beat.size.y)

	focus = Vector2((GAP + left_w + screen.x) * 0.5, maxf(120.0, tl.position.y * 0.55))


const HELP := """getting started: drag on the voice box to make a sound. press record and play with the control pad, or add keys with + key, then tweak them on the timeline. space plays.

walking: wasd / arrow keys, or press and drag on the room. scroll to zoom.

the control pad: drag the tongue in its slice, press along the tube to close it, use the pitch and mouth pads and the size slider. with a key selected, that edits the key.

the beat: the drums play on the stage at 120 bpm. a phrase is 4 seconds = 2 bars, so loop on beat repeats yours in time with the drums. stand on the stage to change the beat.

keys: space play · l loop · r record · h hold sound · b loop on beat · k add key · [ ] step keys · delete removes a key · esc deselect

pink trombone by neil thapen (2017), modular version by christian d'heureuse. mit license."""


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
		KEY_B:
			%LoopBeat.button_pressed = not %LoopBeat.button_pressed
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
