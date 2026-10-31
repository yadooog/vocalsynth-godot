extends Control
## A plain drag pad. `value` runs 0..1 on each axis (y = 0 at the top).
## With `horizontal_only` it becomes a slider. Double-click resets it.

signal moved(value: Vector2)
signal held(on: bool)
## Only from the user dragging or resetting it, not when something else sets the value.
signal user_edited

const INK := Color(0.133, 0.133, 0.125)
const PAD := Color(0.925, 0.91, 0.875)

@export var caption := ""
@export var value := Vector2(0.5, 0.5)
@export var default_value := Vector2(0.5, 0.5)
@export var horizontal_only := false
@export var vertical_only := false
## Number of vertical guide lines, and which of them are drawn darker.
@export var lines := 0
@export var marked_lines := PackedInt32Array()
## The timeline to show motion lines for, and which two frame fields this control shows.
var timeline: Control = null
var field_x := ""
var field_y := ""

var _pointer := -2 # -1 = mouse, >= 0 = touch index, -2 = nobody


func _process(_delta: float) -> void:
	if timeline != null:
		queue_redraw()


func _motion(v: Vector2) -> Vector2:
	if vertical_only:
		return Vector2(size.x * 0.5, v.y * size.y)
	return v * size


func _draw_motion() -> void:
	if timeline != null:
		Motion.draw(self, timeline, field_x, field_y, _motion)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.double_click:
			set_value(default_value)
			user_edited.emit()
		elif event.pressed:
			_grab(-1, event.position)
		elif _pointer == -1:
			_let_go()
		accept_event()
	elif event is InputEventMouseMotion and _pointer == -1:
		_drag(event.position)
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed and _pointer == -2:
			_grab(event.index, event.position)
		elif not event.pressed and event.index == _pointer:
			_let_go()
		accept_event()
	elif event is InputEventScreenDrag and event.index == _pointer:
		_drag(event.position)
		accept_event()


func set_value(v: Vector2) -> void:
	value = v.clamp(Vector2.ZERO, Vector2.ONE)
	moved.emit(value)
	queue_redraw()


func _grab(pointer: int, pos: Vector2) -> void:
	_pointer = pointer
	held.emit(true)
	_drag(pos)


func _let_go() -> void:
	_pointer = -2
	held.emit(false)


func _drag(pos: Vector2) -> void:
	var v := pos / size
	if horizontal_only:
		v.y = value.y
	if vertical_only:
		v.x = value.x
	set_value(v)
	user_edited.emit()


func _draw() -> void:
	var font := get_theme_default_font()
	if vertical_only:
		var x := size.x * 0.5
		draw_line(Vector2(x, 0), Vector2(x, size.y), INK, 1.0)
		var mid := default_value.y * size.y
		draw_line(Vector2(x - 5, mid), Vector2(x + 5, mid), Color(INK, 0.4), 1.0)
		_draw_motion()
		var r := Rect2(Vector2(x - 9, value.y * size.y - 6), Vector2(18, 12))
		draw_rect(r, PAD)
		draw_rect(r, INK, false, 1.5)
		if caption != "":
			draw_set_transform(Vector2(x - 8, size.y - 4), -PI / 2.0)
			draw_string(font, Vector2.ZERO, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.5))
			draw_set_transform(Vector2.ZERO)
		return
	if horizontal_only:
		var y := size.y * 0.5
		draw_line(Vector2(0, y), Vector2(size.x, y), INK, 1.0)
		var mid := default_value.x * size.x
		draw_line(Vector2(mid, y - 5), Vector2(mid, y + 5), Color(INK, 0.4), 1.0)
		var r := Rect2(Vector2(value.x * size.x - 6, y - 9), Vector2(12, 18))
		draw_rect(r, PAD)
		draw_rect(r, INK, false, 1.5)
		if caption != "":
			draw_string(font, Vector2(0, y - 10), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.5))
		return

	draw_rect(Rect2(Vector2.ZERO, size), PAD)
	for i in lines:
		var x := (i + 0.5) / lines * size.x
		var marked := marked_lines.has(i)
		draw_line(Vector2(x, 6), Vector2(x, size.y - 6), Color(INK, 0.3 if marked else 0.1), 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), INK, false, 1.0)
	_draw_motion()
	var p := value * size
	var m := Rect2(p - Vector2(8, 8), Vector2(16, 16))
	draw_rect(m, Color(INK, 0.08 if _pointer == -2 else 0.25))
	draw_rect(m, INK, false, 1.5)
	if caption != "":
		draw_string(font, Vector2(6, size.y - 6), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.5))
