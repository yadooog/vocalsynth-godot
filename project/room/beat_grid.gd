extends Control
## The step sequencer on ~/stage: a row of 16 steps for each drum. Click a step to turn it
## on or off. The step playing now is outlined. `beats` is set by main.gd.

const INK := Color(0.133, 0.133, 0.125)
const PAPER := Color(0.969, 0.957, 0.933)
const PAD := Color(0.925, 0.91, 0.875)
const LABEL_W := 54.0
const ROW_H := 26.0
const GAP := 3.0

var beats: Node = null


func _ready() -> void:
	custom_minimum_size.y = 4 * ROW_H + 8.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _cell_rect(drum: int, step: int) -> Rect2:
	var w := (size.x - LABEL_W - 12.0) / 16.0
	var x := LABEL_W + step * w + (6.0 if step >= 8 else 0.0) # a gap between the two bars
	return Rect2(x + GAP / 2, 4.0 + drum * ROW_H + GAP / 2, w - GAP, ROW_H - GAP)


func _gui_input(event: InputEvent) -> void:
	if beats == null:
		return
	var pos = null
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	if pos == null:
		return
	for drum in beats.DRUMS.size():
		for step in beats.STEPS:
			if _cell_rect(drum, step).has_point(pos):
				beats.toggle(drum, step)
				accept_event()
				return


func _draw() -> void:
	if beats == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	draw_rect(Rect2(Vector2.ZERO, size), INK, false, 1.0)
	var font := ThemeDB.fallback_font
	var now: int = beats.current_step()
	for drum in beats.DRUMS.size():
		draw_string(font, Vector2(8, 4.0 + drum * ROW_H + ROW_H * 0.68), beats.DRUMS[drum], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(INK, 0.6))
		for step in beats.STEPS:
			var r := _cell_rect(drum, step)
			var on: bool = beats.pattern[drum][step]
			draw_rect(r, INK if on else (PAD if step % 4 < 2 else PAPER))
			draw_rect(r, INK, false, 2.0 if step == now else 1.0)
