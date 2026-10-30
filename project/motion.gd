class_name Motion
## Draws a phrase's motion on a control: a fading line along the path the control follows
## between the keys (with an arrowhead), a dot per key, and a cross where the playhead is.
## `mapper` turns a value pair (two frame fields) into a point on the control.

const INK := Color(0.133, 0.133, 0.125)
const PAPER := Color(0.969, 0.957, 0.933)


static func draw(ci: CanvasItem, timeline: Control, fx: String, fy: String, mapper: Callable, voiced_only := false) -> void:
	if timeline == null or timeline.keys.is_empty():
		return
	for run in timeline.paths(fx, fy, voiced_only):
		var pts := PackedVector2Array()
		for v in run:
			pts.append(mapper.call(v))
		_line(ci, pts)
	for k in timeline.keys:
		if voiced_only and not k["f"]["voiced"]:
			continue
		var p: Vector2 = mapper.call(Vector2(k["f"][fx], k["f"][fy]))
		var sel: bool = k == timeline.selected
		ci.draw_circle(p, 9.0 if sel else 6.0, INK if sel else PAPER)
		ci.draw_arc(p, 9.0 if sel else 6.0, 0, TAU, 20, INK, 2.0, true)
	if timeline.playing or not timeline.recording:
		var f: Dictionary = timeline.sample(timeline.t)
		if not f.is_empty() and not (voiced_only and not f["voiced"]):
			var c: Vector2 = mapper.call(Vector2(f[fx], f[fy]))
			ci.draw_line(c - Vector2(9, 0), c + Vector2(9, 0), INK, 2.0)
			ci.draw_line(c - Vector2(0, 9), c + Vector2(0, 9), INK, 2.0)


# The tract closures: one line per slot, with its key dots and the playhead.
static func draw_closures(ci: CanvasItem, timeline: Control, mapper: Callable) -> void:
	if timeline == null or timeline.keys.is_empty():
		return
	for slot in timeline.MAX_CLOSURES:
		for run in timeline.closure_paths(slot):
			var pts := PackedVector2Array()
			for v in run:
				pts.append(mapper.call(v))
			_line(ci, pts)
		for k in timeline.keys:
			var cs: Array = k["f"]["cs"]
			if slot >= cs.size():
				continue
			var p: Vector2 = mapper.call(Vector2(cs[slot]["i"], cs[slot]["d"]))
			var sel: bool = k == timeline.selected
			ci.draw_circle(p, 9.0 if sel else 6.0, INK if sel else PAPER)
			ci.draw_arc(p, 9.0 if sel else 6.0, 0, TAU, 20, INK, 2.0, true)
		if timeline.playing or not timeline.recording:
			var now: Array = timeline.sample(timeline.t).get("cs", [])
			if slot < now.size():
				var c: Vector2 = mapper.call(Vector2(now[slot]["i"], now[slot]["d"]))
				ci.draw_line(c - Vector2(9, 0), c + Vector2(9, 0), INK, 2.0)
				ci.draw_line(c - Vector2(0, 9), c + Vector2(0, 9), INK, 2.0)


static func _line(ci: CanvasItem, pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var moved := false
	for p in pts:
		if p.distance_to(pts[0]) > 3.0:
			moved = true
			break
	if not moved:
		return
	var n := pts.size()
	for i in range(1, n):
		ci.draw_line(pts[i - 1], pts[i], Color(INK, 0.12 + 0.5 * float(i) / n), 3.0, true)
	var end := pts[n - 1]
	var j := n - 2
	while j > 0 and end.distance_to(pts[j]) < 8.0:
		j -= 1
	var a := (end - pts[j]).angle()
	var head := PackedVector2Array([
		end + Vector2.from_angle(a) * 10.0,
		end + Vector2.from_angle(a + 2.4) * 9.0,
		end + Vector2.from_angle(a - 2.4) * 9.0,
	])
	ci.draw_colored_polygon(head, Color(INK, 0.7))
