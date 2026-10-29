extends Control
## Draws the vocal tract and pitch strip, and turns mouse/touch drags into sound.
## Layout and maths follow the original Pink Trombone (a 600 x 600 canvas),
## scaled to fit this control. The sound itself comes from the PinkTrombone
## class, compiled from C++ in src/.

const INK := Color(0.133, 0.133, 0.125)
const PAPER := Color(0.969, 0.957, 0.933)
const FILL := Color(0.89, 0.871, 0.831)
const PAD := Color(0.925, 0.91, 0.875)

# Tract drawing (canvas units, same as the original).
const ORIGIN := Vector2(340, 449)
const RADIUS := 298.0
const SCALE := 60.0
const ANGLE_SCALE := 0.64
const ANGLE_OFFSET := -0.24
const NOSE_OFFSET := 0.8
const INNER_TONGUE_RADIUS := 2.05
const OUTER_TONGUE_RADIUS := 3.5

# Pitch strip.
const BASE_NOTE := 87.3071 # F
const SEMITONES := 20
const KEYS_TOP := 500.0
const KEYS_WIDTH := 600.0
const KEYS_HEIGHT := 100.0
const MARKS := [0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0]

const CANVAS := Vector2(600, 600)
const MOUSE_ID := 1000

var synth # PinkTrombone (untyped so this script still loads if the engine is missing)
var playback: AudioStreamGeneratorPlayback

var n := 44
var nose_start := 17
var nose_length := 28
var lip_start := 39
var tongue_lower := 12.0
var tongue_upper := 29.0
var tongue_centre := 20.5

var touches := {} # id -> canvas position
var tongue_touch := -1
var pitch_touch := -1
var pitch_marker := Vector2(240, 530)

var bar := _make_bar_style()
var view_scale := 1.0
var view_offset := Vector2.ZERO


func _ready() -> void:
	if not ClassDB.class_exists("PinkTrombone"):
		push_error("PinkTrombone engine not found. The compiled files in project/bin/ are missing for this computer; see README.")
		set_process(false)
		return

	synth = ClassDB.instantiate("PinkTrombone")
	n = _constant("TRACT_LENGTH")
	nose_start = _constant("NOSE_START")
	nose_length = _constant("NOSE_LENGTH")
	lip_start = _constant("LIP_START")
	tongue_lower = _constant("BLADE_START") + 2
	tongue_upper = _constant("TIP_START") - 3
	tongue_centre = 0.5 * (tongue_lower + tongue_upper)

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = AudioServer.get_mix_rate()
	generator.buffer_length = 0.08
	synth.setup(generator.mix_rate)

	var player := AudioStreamPlayer.new()
	player.stream = generator
	add_child(player)
	player.play()
	playback = player.get_stream_playback()


func _constant(name: String) -> int:
	return ClassDB.class_get_integer_constant("PinkTrombone", name)


func _process(_delta: float) -> void:
	synth.fill(playback)
	queue_redraw()


# ---------------------------------------------------------------- coordinates

func _update_view() -> void:
	view_scale = minf(size.x / CANVAS.x, size.y / CANVAS.y)
	view_offset = (size - CANVAS * view_scale) * 0.5


func to_canvas(p: Vector2) -> Vector2:
	return (p - view_offset) / view_scale


func polar(i: float, d: float, wobble := 0.0) -> Vector2:
	var angle := ANGLE_OFFSET + i * ANGLE_SCALE * PI / (lip_start - 1)
	var r := RADIUS - SCALE * d
	if wobble != 0.0:
		var w := wobble * sin(2.0 * i - 50.0 * Time.get_ticks_msec() / 1000.0) * i / n
		angle += w
		r += 100.0 * w
	return Vector2(ORIGIN.x - r * cos(angle), ORIGIN.y - r * sin(angle))


func tract_index(p: Vector2) -> float:
	var angle := atan2(p.y - ORIGIN.y, p.x - ORIGIN.x)
	while angle > 0:
		angle -= TAU
	return (PI + angle - ANGLE_OFFSET) * (lip_start - 1) / (ANGLE_SCALE * PI)


func tract_diameter(p: Vector2) -> float:
	return (RADIUS - p.distance_to(ORIGIN)) / SCALE


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if synth == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(MOUSE_ID, to_canvas(event.position))
		else:
			_release(MOUSE_ID)
		accept_event()
	elif event is InputEventMouseMotion and touches.has(MOUSE_ID):
		_drag(MOUSE_ID, to_canvas(event.position))
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, to_canvas(event.position))
		else:
			_release(event.index)
		accept_event()
	elif event is InputEventScreenDrag and touches.has(event.index):
		_drag(event.index, to_canvas(event.position))
		accept_event()


func _press(id: int, p: Vector2) -> void:
	touches[id] = p
	if p.y >= KEYS_TOP:
		if pitch_touch == -1:
			pitch_touch = id
			_set_pitch(p)
		return
	var index := tract_index(p)
	var diameter := tract_diameter(p)
	synth.touch_start(id, index, diameter)
	if tongue_touch == -1 \
			and index >= tongue_lower - 4 and index <= tongue_upper + 4 \
			and diameter >= INNER_TONGUE_RADIUS - 0.5 and diameter <= OUTER_TONGUE_RADIUS + 0.5:
		tongue_touch = id
		synth.set_tongue(index, diameter)


func _drag(id: int, p: Vector2) -> void:
	touches[id] = p
	if id == pitch_touch:
		_set_pitch(p)
		return
	var index := tract_index(p)
	var diameter := tract_diameter(p)
	synth.touch_move(id, index, diameter)
	if id == tongue_touch:
		synth.set_tongue(index, diameter)


func _release(id: int) -> void:
	touches.erase(id)
	synth.touch_end(id)
	if id == tongue_touch:
		tongue_touch = -1
	if id == pitch_touch:
		pitch_touch = -1
		synth.voice_held = false


func _set_pitch(p: Vector2) -> void:
	var local_y := clampf(p.y - KEYS_TOP - 10.0, 0.0, KEYS_HEIGHT - 26.0)
	var semitone := SEMITONES * p.x / KEYS_WIDTH + 0.5
	synth.frequency = BASE_NOTE * pow(2.0, semitone / 12.0)
	var t := clampf(1.0 - local_y / (KEYS_HEIGHT - 28.0), 0.0, 1.0)
	synth.tenseness = 1.0 - cos(t * PI / 2.0)
	synth.voice_held = true
	pitch_marker = Vector2(p.x, local_y + KEYS_TOP + 10.0)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	_update_view()
	draw_set_transform(view_offset, 0.0, Vector2(view_scale, view_scale))
	_draw_pitch_strip()
	if synth == null:
		return
	_draw_tongue_control()
	_draw_tract()


func _make_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAD
	style.set_corner_radius_all(8)
	return style


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([color, color, color, color]), PackedVector2Array())


func _draw_tract() -> void:
	var diam: PackedFloat32Array = synth.get_diameters()
	var nose: PackedFloat32Array = synth.get_nose_diameters()
	var amp: PackedFloat32Array = synth.get_amplitudes()
	var nose_amp: PackedFloat32Array = synth.get_nose_amplitudes()
	var wobble := (amp[n - 1] + nose_amp[nose_length - 1]) * 0.03
	var velum := nose[0]
	var velum_angle := velum * 4.0

	# fill: mouth, nose, velum
	for i in range(1, n - 1):
		_quad(polar(i, 0, wobble), polar(i + 1, 0, wobble), polar(i + 1, diam[i + 1], wobble), polar(i, diam[i], wobble), FILL)
	for i in range(1, nose_length - 1):
		_quad(polar(i + nose_start, -NOSE_OFFSET, wobble), polar(i + 1 + nose_start, -NOSE_OFFSET, wobble),
			polar(i + 1 + nose_start, -NOSE_OFFSET - nose[i + 1] * 0.9, wobble), polar(i + nose_start, -NOSE_OFFSET - nose[i] * 0.9, wobble), FILL)
	_quad(polar(nose_start - 2, 0, wobble), polar(nose_start, -NOSE_OFFSET, wobble),
		polar(nose_start + velum_angle, -NOSE_OFFSET, wobble), polar(nose_start + velum_angle - 2, 0, wobble), FILL)

	# loudness along the tract
	var faint := Color(INK, 0.3)
	for i in range(2, n - 1):
		var w := sqrt(amp[i]) * 3.0
		if w > 0.2:
			draw_line(polar(i, 0, wobble), polar(i, diam[i], wobble), faint, w)
	for i in range(1, nose_length - 1):
		var w := sqrt(nose_amp[i]) * 3.0
		if w > 0.2:
			draw_line(polar(i + nose_start, -NOSE_OFFSET, wobble), polar(i + nose_start, -NOSE_OFFSET - nose[i] * 0.9, wobble), faint, w)

	# walls
	var floor_line := PackedVector2Array([polar(1, diam[0], wobble)])
	for i in range(2, n):
		floor_line.append(polar(i, diam[i], wobble))
	draw_polyline(floor_line, INK, 2.5, true)

	var roof_back := PackedVector2Array()
	for i in range(1, nose_start - 1):
		roof_back.append(polar(i, 0, wobble))
	draw_polyline(roof_back, INK, 2.5, true)
	var roof_front := PackedVector2Array([polar(nose_start + velum_angle - 2, 0, wobble)])
	for i in range(nose_start + ceili(velum_angle) - 2, n):
		roof_front.append(polar(i, 0, wobble))
	draw_polyline(roof_front, INK, 2.5, true)

	var nose_top := PackedVector2Array([polar(nose_start, -NOSE_OFFSET, wobble)])
	for i in range(1, nose_length):
		nose_top.append(polar(i + nose_start, -NOSE_OFFSET - nose[i] * 0.9, wobble))
	draw_polyline(nose_top, INK, 2.5, true)
	var nose_floor := PackedVector2Array([polar(nose_start + velum_angle, -NOSE_OFFSET, wobble)])
	for i in range(ceili(velum_angle), nose_length):
		nose_floor.append(polar(i + nose_start, -NOSE_OFFSET, wobble))
	draw_polyline(nose_floor, INK, 2.5, true)

	# velum flap, fades out as it closes
	var velum_ink := Color(INK, clampf(velum * 5.0, 0.0, 1.0))
	draw_line(polar(nose_start - 2, 0, wobble), polar(nose_start, -NOSE_OFFSET, wobble), velum_ink, 2.5, true)
	draw_line(polar(nose_start + velum_angle - 2, 0, wobble), polar(nose_start + velum_angle, -NOSE_OFFSET, wobble), velum_ink, 2.5, true)


func _draw_tongue_control() -> void:
	var outline := PackedVector2Array()
	for i in range(int(tongue_lower), int(tongue_upper) + 1):
		outline.append(polar(i, INNER_TONGUE_RADIUS))
	outline.append(polar(tongue_centre, OUTER_TONGUE_RADIUS))
	draw_colored_polygon(outline, PAD)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, PAD, 45.0)
	for p in outline:
		draw_circle(p, 22.5, PAD)

	var a := INNER_TONGUE_RADIUS
	var c := OUTER_TONGUE_RADIUS
	var b := 0.5 * (a + c)
	var dot := Color(INK, 0.25)
	for spot in [[0, a], [-4.25, a], [-8.5, a], [4.25, a], [8.5, a], [-6.1, b], [6.1, b], [0, b], [0, c]]:
		draw_circle(polar(tongue_centre + spot[0], spot[1]), 3.0, dot)

	var marker := polar(synth.get_tongue_index(), synth.get_tongue_diameter())
	draw_circle(marker, 18.0, Color(INK, 0.08))
	draw_arc(marker, 18.0, 0, TAU, 40, INK, 2.0, true)


func _draw_pitch_strip() -> void:
	draw_style_box(bar, Rect2(0, KEYS_TOP, KEYS_WIDTH, KEYS_HEIGHT * 0.4))
	draw_style_box(bar, Rect2(0, KEYS_TOP + KEYS_HEIGHT * 0.52, KEYS_WIDTH, KEYS_HEIGHT * 0.2))

	var key_width := KEYS_WIDTH / SEMITONES
	for i in SEMITONES:
		var x := (i + 0.5) * key_width
		var marked: bool = MARKS[(i + 3) % 12] == 1
		draw_line(Vector2(x, KEYS_TOP + 9), Vector2(x, KEYS_TOP + KEYS_HEIGHT * 0.4 - 9),
			Color(INK, 0.4 if marked else 0.18), 2.0 if marked else 1.0)
		draw_line(Vector2(x, KEYS_TOP + KEYS_HEIGHT * 0.52 + 6), Vector2(x, KEYS_TOP + KEYS_HEIGHT * 0.72 - 6),
			Color(INK, 0.15), 1.0)

	var rect := Rect2(pitch_marker - Vector2(9, 15), Vector2(18, 30))
	draw_rect(rect, Color(INK, 0.08))
	draw_rect(rect, INK, false, 2.0)
