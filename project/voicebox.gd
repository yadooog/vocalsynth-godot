extends Control
## Draws the vocal tract and turns mouse/touch drags on it into tract shapes.
## Layout and maths follow the original Pink Trombone (a 600 x 600 canvas),
## scaled to fit this control. `synth` (a PinkTrombone) is set by main.gd.

const INK := Color(0.133, 0.133, 0.125)
const PAPER := Color(0.969, 0.957, 0.933)
const FILL := Color(0.89, 0.871, 0.831)
const PAD := Color(0.925, 0.91, 0.875)

# Tract drawing (canvas units, same as the original).
# The tract is a quarter circle centred on the bottom-right corner: the throat is at the
# left end and the lips at the top end. Roof = outer arc, floor = inner arc.
const ORIGIN := Vector2(330, 330)
const RADIUS := 300.0
const SCALE := 60.0
const INNER_TONGUE_RADIUS := 2.05
const OUTER_TONGUE_RADIUS := 3.5

# Part of the original 600 x 600 canvas that the tract covers.
const VIEW := Rect2(10, 10, 340, 340)
const MOUSE_ID := 1000

var synth = null: # PinkTrombone, untyped so this script loads even if the engine is missing
	set(value):
		synth = value
		if synth:
			_read_layout()

var n := 44
var nose_start := 17
var nose_length := 28
var lip_start := 39
var tongue_lower := 12.0
var tongue_upper := 29.0
var tongue_centre := 20.5

var touches := {} # id -> canvas position
var tongue_touch := -1

var view_scale := 1.0
var view_offset := Vector2.ZERO


func _read_layout() -> void:
	n = _constant("TRACT_LENGTH")
	nose_start = _constant("NOSE_START")
	nose_length = _constant("NOSE_LENGTH")
	lip_start = _constant("LIP_START")
	tongue_lower = _constant("BLADE_START") + 2
	tongue_upper = _constant("TIP_START") - 3
	tongue_centre = 0.5 * (tongue_lower + tongue_upper)


func _constant(name: String) -> int:
	return ClassDB.class_get_integer_constant("PinkTrombone", name)


func _process(_delta: float) -> void:
	queue_redraw()


# ---------------------------------------------------------------- coordinates

func _update_view() -> void:
	view_scale = minf(size.x / VIEW.size.x, size.y / VIEW.size.y)
	view_offset = (size - VIEW.size * view_scale) * 0.5 - VIEW.position * view_scale


func to_canvas(p: Vector2) -> Vector2:
	return (p - view_offset) / view_scale


func polar(i: float, d: float, wobble := 0.0) -> Vector2:
	var angle := PI + (i / (n - 1)) * PI * 0.5
	var r := RADIUS - SCALE * d
	if wobble != 0.0:
		var w := wobble * sin(2.0 * i - 50.0 * Time.get_ticks_msec() / 1000.0) * i / n
		angle += w
		r += 100.0 * w
	return Vector2(ORIGIN.x + r * cos(angle), ORIGIN.y + r * sin(angle))


func tract_index(p: Vector2) -> float:
	var angle := atan2(p.y - ORIGIN.y, p.x - ORIGIN.x)
	if angle > 0:
		angle -= TAU
	return clampf((angle + PI) / (PI * 0.5) * (n - 1), 0.0, n - 1)


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


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	_update_view()
	draw_set_transform(view_offset, 0.0, Vector2(view_scale, view_scale))
	if synth == null:
		return
	_draw_tongue_control()
	_draw_tract()


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([color, color, color, color]), PackedVector2Array())


func _draw_tract() -> void:
	var diam: PackedFloat32Array = synth.get_diameters()
	var amp: PackedFloat32Array = synth.get_amplitudes()
	var nose_amp: PackedFloat32Array = synth.get_nose_amplitudes()
	var wobble := (amp[n - 1] + nose_amp[nose_length - 1]) * 0.03

	# inside of the mouth
	for i in range(1, n - 1):
		_quad(polar(i, 0, wobble), polar(i + 1, 0, wobble), polar(i + 1, diam[i + 1], wobble), polar(i, diam[i], wobble), FILL)

	# loudness along the tract
	var faint := Color(INK, 0.3)
	for i in range(2, n - 1):
		var w := sqrt(amp[i]) * 3.0
		if w > 0.2:
			draw_line(polar(i, 0, wobble), polar(i, diam[i], wobble), faint, w)

	# walls: tongue/floor, then roof
	var floor_line := PackedVector2Array([polar(1, diam[0], wobble)])
	for i in range(2, n):
		floor_line.append(polar(i, diam[i], wobble))
	draw_polyline(floor_line, INK, 2.5, true)
	var roof := PackedVector2Array()
	for i in range(1, n):
		roof.append(polar(i, 0, wobble))
	draw_polyline(roof, INK, 2.5, true)

	# the nose isn't drawn; show when it's open with a small mark on the roof
	var velum: float = synth.get_nose_diameters()[0]
	if velum > 0.05:
		draw_circle(polar(nose_start, -0.35), 3.0 + 10.0 * velum, Color(INK, clampf(velum * 2.5, 0.0, 1.0)))


func _draw_tongue_control() -> void:
	# A slice of the quarter circle: an arc at the inner radius out and back along the outer one.
	var outline := PackedVector2Array()
	var steps := 24
	var lo := tongue_lower - 1.0
	var hi := tongue_upper + 1.0
	for k in steps + 1:
		outline.append(polar(lerpf(lo, hi, float(k) / steps), INNER_TONGUE_RADIUS))
	for k in steps + 1:
		outline.append(polar(lerpf(hi, lo, float(k) / steps), OUTER_TONGUE_RADIUS))
	draw_colored_polygon(outline, PAD)

	var a := INNER_TONGUE_RADIUS
	var c := OUTER_TONGUE_RADIUS
	var b := 0.5 * (a + c)
	var dot := Color(INK, 0.25)
	for spot in [[0, a], [-4.25, a], [-8.5, a], [4.25, a], [8.5, a], [-6.1, b], [6.1, b], [0, b], [0, c]]:
		draw_circle(polar(tongue_centre + spot[0], spot[1]), 3.0, dot)

	var marker := polar(synth.get_tongue_index(), synth.get_tongue_diameter())
	draw_circle(marker, 18.0, Color(INK, 0.08))
	draw_arc(marker, 18.0, 0, TAU, 40, INK, 2.0, true)
