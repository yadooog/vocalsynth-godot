extends Control
## The step sequencer on ~/stage: a row of 16 steps for each drum. Click a step to turn it
## on or off. The step playing now is outlined. `beats` is set by main.gd.

const INK := Color(0.149, 0.149, 0.149)
const EDGE := Color(0, 0, 0, 0.35)
const DIM := Color(0.42, 0.42, 0.42)
const RED := Color(0.894, 0.341, 0.18)
const LABEL_W := 40.0
const ROW_H := 23.0
const GAP := 3.0

var beats: Node = null


func _ready() -> void:
	custom_minimum_size.y = 4 * ROW_H
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


# Like the web grid: a little gap every beat, a bigger one every bar.
func _cell_rect(drum: int, step: int) -> Rect2:
	var gaps := 12.0
	var w := (size.x - LABEL_W - gaps) / 16.0
	var x := LABEL_W + step * w + int(step / 4.0) * 2.0 + (6.0 if step >= 8 else 0.0)
	return Rect2(x + GAP / 2, drum * ROW_H + GAP / 2, w - GAP, ROW_H - GAP)


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
	var font := get_theme_default_font()
	var now: int = beats.current_step()
	var cell := StyleBoxFlat.new()
	cell.set_corner_radius_all(3)
	cell.anti_aliasing = true
	for drum in beats.DRUMS.size():
		draw_string(font, Vector2(0, drum * ROW_H + ROW_H * 0.68), beats.DRUMS[drum], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
		for step in beats.STEPS:
			var on: bool = beats.pattern[drum][step]
			cell.bg_color = INK if on else Color(0, 0, 0, 0)
			cell.border_color = RED if step == now else (INK if on else EDGE)
			cell.set_border_width_all(2 if step == now else 1)
			draw_style_box(cell, _cell_rect(drum, step))
