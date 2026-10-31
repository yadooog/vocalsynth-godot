extends Control
## The keyframe timeline: a 4 second phrase (2 bars at 120 bpm) made of keys, each holding
## a full pose of the controls. Playing blends between keys; recording captures the controls
## live and boils them down to a few keys.
##
## A frame (the pose stored in a key) is a Dictionary:
##   px, py  pitch pad     mx, my  mouth pad     sz  size slider (y)
##   ti, td  tongue index / diameter              voiced  bool
##
## main.gd gives it `capture` (reads the controls into a frame) and listens to `frame_changed`
## (put a frame onto the controls).

signal frame_changed(frame: Dictionary)
signal playing_changed(on: bool)
signal recording_changed(on: bool)
signal scrub_ended

const INK := Color(0.133, 0.133, 0.125)
const PAPER := Color(0.969, 0.957, 0.933)
const PAD_COLOR := Color(0.925, 0.91, 0.875)

const DURATION := 4.0
const BEAT := 0.5            # 120 bpm
const SNAP := 0.125          # a 16th note
const RULER := 26.0
const KEYS_ROW := 32.0
const LANE_H := 46.0
const SIDE := 14.0           # padding so keys at 0 s and 4 s can be grabbed
const HIT := 14.0
const RECORD_STEP := 1.0 / 30.0
const SIMPLIFY_TOLERANCE := 0.05
const MAX_KEYS := 32

# id, label, frame field, min, max, flip (true: the field grows downwards on its control)
const LANES := [
	{"id": "pitch", "label": "pitch", "field": "px", "lo": 0.0, "hi": 1.0, "flip": false},
	{"id": "tense", "label": "tension", "field": "py", "lo": 0.0, "hi": 1.0, "flip": true},
	{"id": "lips", "label": "lips", "field": "mx", "lo": 0.0, "hi": 1.0, "flip": false},
	{"id": "jaw", "label": "jaw", "field": "my", "lo": 0.0, "hi": 1.0, "flip": false},
	{"id": "tfront", "label": "tongue front", "field": "ti", "lo": 12.0, "hi": 29.0, "flip": false},
	{"id": "topen", "label": "tongue open", "field": "td", "lo": 2.05, "hi": 3.5, "flip": false},
	{"id": "size", "label": "size", "field": "sz", "lo": 0.0, "hi": 1.0, "flip": true},
]
const NUMBER_FIELDS := ["px", "py", "mx", "my", "sz", "ti", "td"]

# Which lanes are showing (ids); the others are hidden to save room.
var lane_ids: Array = ["pitch", "jaw", "tfront"]
var _lanes: Array = []

var capture := Callable()    # () -> Dictionary, set by main.gd

var keys: Array = []         # [{t, ease, f}] sorted by t
var selected = null          # the selected key (a Dictionary in keys) or null
var t := 0.0                 # playhead
var playing := false
var recording := false
var looping := true
var follow_clock := false   # "loop on beat": the beat clock moves the playhead

var _samples: Array = []
var _next_sample := 0.0
var _drag := ""              # "", "scrub", "key", "value"
var _drag_lane := -1
var _grab_dx := 0.0


func _ready() -> void:
	_refresh_lanes()
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_lane(id: String, on: bool) -> void:
	if on and not lane_ids.has(id):
		lane_ids.append(id)
	elif not on:
		lane_ids.erase(id)
	_refresh_lanes()


func _refresh_lanes() -> void:
	_lanes = LANES.filter(func(l): return lane_ids.has(l["id"]))
	custom_minimum_size.y = RULER + KEYS_ROW + _lanes.size() * LANE_H + 4.0
	queue_redraw()


# ---------------------------------------------------------------- the phrase

func sample(time: float) -> Dictionary:
	if keys.is_empty():
		return {}
	if time < keys[0]["t"]:
		var f: Dictionary = keys[0]["f"].duplicate()
		f["voiced"] = false # silent before the first key
		return f
	for i in keys.size() - 1:
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		if time < b["t"]:
			var k := _ease(a["ease"], (time - a["t"]) / maxf(b["t"] - a["t"], 1e-6))
			return _blend(a["f"], b["f"], k)
	return (keys[keys.size() - 1]["f"] as Dictionary).duplicate()


func _ease(kind: String, k: float) -> float:
	if kind == "hold":
		return 0.0
	if kind == "smooth":
		return k * k * (3.0 - 2.0 * k)
	return k


func _blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := a.duplicate()
	for field in NUMBER_FIELDS:
		out[field] = lerpf(a[field], b[field], k)
	# A closure blends when both keys have it; otherwise it stays as it was until the next key.
	var ca: Array = a.get("cs", [])
	var cb: Array = b.get("cs", [])
	var cs: Array = []
	for i in ca.size():
		if i < cb.size():
			cs.append({"i": lerpf(ca[i]["i"], cb[i]["i"], k), "d": lerpf(ca[i]["d"], cb[i]["d"], k)})
		else:
			cs.append(ca[i].duplicate())
	out["cs"] = cs
	return out # voicing switches at the next key


# The runs of (fx, fy) values the controls follow between the first and last key, optionally
# only where voiced; each run is an array of Vector2 (for drawing motion lines on the pads).
func paths(fx: String, fy: String, voiced_only := false) -> Array:
	var runs: Array = []
	if keys.is_empty():
		return runs
	var t0: float = keys[0]["t"]
	var t1: float = keys[keys.size() - 1]["t"]
	var steps := maxi(1, ceili((t1 - t0) * 40.0))
	var run: Array = []
	for i in steps + 1:
		var f := sample(t0 + (t1 - t0) * i / steps)
		if voiced_only and not f["voiced"]:
			if run.size() > 1:
				runs.append(run)
			run = []
		else:
			run.append(Vector2(f[fx], f[fy]))
	if run.size() > 1:
		runs.append(run)
	return runs


# Closures (squeezes of the tract, up to two per key). Paths and key points for one slot.
func closure_paths(slot: int) -> Array:
	var runs: Array = []
	if keys.is_empty():
		return runs
	var t0: float = keys[0]["t"]
	var t1: float = keys[keys.size() - 1]["t"]
	var steps := maxi(1, ceili((t1 - t0) * 40.0))
	var run: Array = []
	for i in steps + 1:
		var cs: Array = sample(t0 + (t1 - t0) * i / steps)["cs"]
		if slot < cs.size():
			run.append(Vector2(cs[slot]["i"], cs[slot]["d"]))
		else:
			if run.size() > 1:
				runs.append(run)
			run = []
	if run.size() > 1:
		runs.append(run)
	return runs


const MAX_CLOSURES := 2
var _slot_of := {} # touch id -> closure slot being edited


# Dragging on the tract with a key selected edits that key's closures: pressing near one moves
# it, elsewhere adds one (up to two), and after that moves the nearest. Let go off the tract to remove.
func closure_press(id: int, index: float, diameter: float) -> void:
	if selected == null:
		return
	var cs: Array = selected["f"]["cs"]
	var nearest := -1
	for i in cs.size():
		if nearest < 0 or absf(cs[i]["i"] - index) < absf(cs[nearest]["i"] - index):
			nearest = i
	var near := nearest >= 0 and absf(cs[nearest]["i"] - index) < 4.0
	var slot := nearest
	if not near and cs.size() < MAX_CLOSURES:
		cs.append({"i": index, "d": diameter})
		slot = cs.size() - 1
	_slot_of[id] = slot
	closure_move(id, index, diameter)


func closure_move(id: int, index: float, diameter: float) -> void:
	if selected == null or not _slot_of.has(id):
		return
	var cs: Array = selected["f"]["cs"]
	var slot: int = _slot_of[id]
	if slot >= 0 and slot < cs.size():
		cs[slot] = {"i": snapped(index, 0.01), "d": snapped(diameter, 0.001)}
	queue_redraw()


func closure_release(id: int, on_tract: bool) -> void:
	if selected != null and _slot_of.has(id):
		var cs: Array = selected["f"]["cs"]
		var slot: int = _slot_of[id]
		if not on_tract and slot >= 0 and slot < cs.size():
			cs.remove_at(slot)
			for other in _slot_of:
				if _slot_of[other] > slot:
					_slot_of[other] -= 1
	_slot_of.erase(id)
	queue_redraw()


func clear_closures() -> void:
	if selected != null:
		selected["f"]["cs"] = []
		_slot_of.clear()
		queue_redraw()


func closures_of_selected() -> Array:
	return [] if selected == null else selected["f"]["cs"]


# The selected key takes on the controls' current values (its voicing stays as it was).
func update_selected(frame: Dictionary) -> void:
	if selected == null:
		return
	for field in NUMBER_FIELDS:
		selected["f"][field] = frame[field]
	queue_redraw()


func set_selected_ease(kind: String) -> void:
	if selected != null:
		selected["ease"] = kind
		queue_redraw()


func select_neighbour(dir: int) -> void:
	if keys.is_empty():
		return
	var i := keys.find(selected)
	i = 0 if i < 0 else clampi(i + dir, 0, keys.size() - 1)
	_select(keys[i])


func deselect() -> void:
	selected = null
	queue_redraw()


func is_scrubbing() -> bool:
	return _drag == "scrub"


func _end_drag() -> void:
	var was_scrub := _drag == "scrub"
	_drag = ""
	if was_scrub:
		scrub_ended.emit()


func set_selected_voiced(on: bool) -> void:
	if selected != null:
		selected["f"]["voiced"] = on
		queue_redraw()


func _sort_keys() -> void:
	keys.sort_custom(func(x, y): return x["t"] < y["t"])


func add_key(frame: Dictionary, at: float = -1.0) -> void:
	if at < 0.0:
		at = t
	at = snapped(clampf(at, 0.0, DURATION), 0.001)
	for k in keys:
		if absf(k["t"] - at) < 0.02: # replace the pose of a key that is already there
			k["f"] = frame.duplicate(true)
			selected = k
			queue_redraw()
			return
	var key := {"t": at, "ease": "linear", "f": frame.duplicate(true)}
	keys.append(key)
	_sort_keys()
	selected = key
	queue_redraw()


func delete_selected() -> void:
	if selected != null:
		keys.erase(selected)
		selected = null
		queue_redraw()


func clear() -> void:
	stop()
	keys.clear()
	selected = null
	t = 0.0
	queue_redraw()


# ---------------------------------------------------------------- transport

## Start playing in time with the beat clock (main.gd sets `t` every frame).
func play_on_clock(at: float) -> void:
	if keys.is_empty() or recording:
		return
	t = at
	follow_clock = true
	if not playing:
		playing = true
		playing_changed.emit(true)


func play() -> void:
	if keys.is_empty():
		return
	follow_clock = false
	recording = false
	recording_changed.emit(false)
	playing = true
	playing_changed.emit(true)


func stop() -> void:
	follow_clock = false
	if playing:
		playing = false
		playing_changed.emit(false)
	if recording:
		recording = false
		recording_changed.emit(false)
	queue_redraw()


func start_recording() -> void:
	stop()
	_samples.clear()
	_next_sample = 0.0
	t = 0.0
	recording = true
	recording_changed.emit(true)


func _process(delta: float) -> void:
	if recording:
		t += delta
		while _next_sample <= t and capture.is_valid():
			var f: Dictionary = capture.call()
			_samples.append({"t": snapped(minf(_next_sample, DURATION), 0.001), "f": f})
			_next_sample += RECORD_STEP
		if t >= DURATION:
			_finish_recording()
	elif playing and follow_clock:
		frame_changed.emit(sample(t)) # t is set from the beat clock by main.gd
	elif playing:
		t += delta
		if t >= DURATION:
			if looping:
				t = fmod(t, DURATION)
			else:
				t = 0.0
				stop()
				return
		frame_changed.emit(sample(t))
	if recording or playing:
		queue_redraw()


func _finish_recording() -> void:
	recording = false
	recording_changed.emit(false)
	t = 0.0
	selected = null
	keys = _simplify(_samples)
	_samples.clear()
	queue_redraw()


# Keeps only the samples needed to stay within a tolerance of the original when played back
# with straight lines (Ramer-Douglas-Peucker), and both sides of every voicing change.
func _simplify(samples: Array) -> Array:
	var all: Array = []
	for s in samples:
		all.append({"t": s["t"], "ease": "linear", "f": s["f"]})
	if all.size() <= 2:
		return all
	var tol := SIMPLIFY_TOLERANCE
	var kept := _rdp(all, tol)
	while kept.size() > MAX_KEYS:
		tol *= 1.4
		kept = _rdp(all, tol)
	return kept


func _rdp(all: Array, tol: float) -> Array:
	var keep := PackedByteArray()
	keep.resize(all.size())
	keep[0] = 1
	keep[all.size() - 1] = 1
	var start := 0
	for i in range(1, all.size()):
		if all[i]["f"]["voiced"] != all[i - 1]["f"]["voiced"] or all[i]["f"]["cs"].size() != all[i - 1]["f"]["cs"].size():
			keep[i - 1] = 1
			keep[i] = 1
			_mark(all, start, i - 1, tol, keep)
			start = i
	_mark(all, start, all.size() - 1, tol, keep)
	var out: Array = []
	for i in all.size():
		if keep[i] == 1:
			out.append(all[i])
	return out


func _mark(all: Array, a: int, b: int, tol: float, keep: PackedByteArray) -> void:
	if b - a < 2:
		return
	var worst := -1
	var worst_err := 0.0
	for i in range(a + 1, b):
		var k: float = (all[i]["t"] - all[a]["t"]) / maxf(all[b]["t"] - all[a]["t"], 1e-6)
		var err := _distance(_blend(all[a]["f"], all[b]["f"], k), all[i]["f"])
		if err > worst_err:
			worst_err = err
			worst = i
	if worst_err > tol:
		keep[worst] = 1
		_mark(all, a, worst, tol, keep)
		_mark(all, worst, b, tol, keep)


func _distance(a: Dictionary, b: Dictionary) -> float:
	var d := 0.0
	for lane in LANES:
		var f: String = lane["field"]
		d = maxf(d, absf(a[f] - b[f]) / (lane["hi"] - lane["lo"]))
	var ca: Array = a["cs"]
	var cb: Array = b["cs"]
	if ca.size() != cb.size():
		return 1.0
	for i in ca.size():
		d = maxf(d, maxf(absf(ca[i]["i"] - cb[i]["i"]) / 17.0, absf(ca[i]["d"] - cb[i]["d"]) / 1.5))
	return d


# ---------------------------------------------------------------- coordinates

func _x_of(time: float) -> float:
	return SIDE + time / DURATION * (size.x - 2.0 * SIDE)


func _time_at(x: float) -> float:
	return clampf((x - SIDE) / maxf(size.x - 2.0 * SIDE, 1.0) * DURATION, 0.0, DURATION)


func _lane_top(i: int) -> float:
	return RULER + KEYS_ROW + i * LANE_H


func _lane_y(i: int, f: Dictionary) -> float:
	var lane: Dictionary = _lanes[i]
	var u: float = (f[lane["field"]] - lane["lo"]) / (lane["hi"] - lane["lo"])
	if lane["flip"]:
		u = 1.0 - u
	return _lane_top(i) + 5.0 + (1.0 - clampf(u, 0.0, 1.0)) * (LANE_H - 10.0)


func _value_at(i: int, y: float) -> float:
	var lane: Dictionary = _lanes[i]
	var u := 1.0 - clampf((y - _lane_top(i) - 5.0) / (LANE_H - 10.0), 0.0, 1.0)
	if lane["flip"]:
		u = 1.0 - u
	return lerpf(lane["lo"], lane["hi"], u)


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event.position, event.double_click)
		else:
			_end_drag()
		accept_event()
	elif event is InputEventMouseMotion and _drag != "":
		_move(event.position)
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_press(event.position, false)
		else:
			_end_drag()
		accept_event()
	elif event is InputEventScreenDrag and _drag != "":
		_move(event.position)
		accept_event()


func _key_near(x: float) -> Variant:
	var best = null
	var best_d := HIT
	for k in keys:
		var d := absf(_x_of(k["t"]) - x)
		if d <= best_d:
			best_d = d
			best = k
	return best


func _press(pos: Vector2, double: bool) -> void:
	if recording:
		return
	if pos.y < RULER:
		_start_scrub(pos)
		return
	if pos.y < RULER + KEYS_ROW:
		var k = _key_near(pos.x)
		if k != null:
			_select(k)
			_drag = "key"
			_grab_dx = _x_of(k["t"]) - pos.x
		elif double and capture.is_valid():
			var fresh: Dictionary = capture.call()
			fresh["voiced"] = true
			add_key(fresh, snap_time(_time_at(pos.x)))
			frame_changed.emit(selected["f"])
		else:
			_start_scrub(pos)
		return
	var lane := int((pos.y - RULER - KEYS_ROW) / LANE_H)
	if lane >= 0 and lane < _lanes.size():
		for k in keys:
			if absf(_x_of(k["t"]) - pos.x) <= HIT and absf(_lane_y(lane, k["f"]) - pos.y) <= HIT:
				_select(k)
				_drag = "value"
				_drag_lane = lane
				return
	selected = null
	_start_scrub(pos)


func _select(k: Dictionary) -> void:
	selected = k
	stop_playing_only()
	t = k["t"]
	frame_changed.emit(k["f"])
	queue_redraw()


func stop_playing_only() -> void:
	follow_clock = false
	if playing:
		playing = false
		playing_changed.emit(false)


func _start_scrub(pos: Vector2) -> void:
	stop_playing_only()
	_drag = "scrub"
	_move(pos)


func snap_time(time: float) -> float:
	return clampf(snapped(time, SNAP), 0.0, DURATION)


func _move(pos: Vector2) -> void:
	match _drag:
		"scrub":
			t = _time_at(pos.x)
			if not keys.is_empty():
				frame_changed.emit(sample(t))
		"key":
			if selected != null:
				selected["t"] = snap_time(_time_at(pos.x + _grab_dx))
				_sort_keys()
				t = selected["t"]
		"value":
			if selected != null:
				var lane: Dictionary = _lanes[_drag_lane]
				selected["f"][lane["field"]] = _value_at(_drag_lane, pos.y)
				frame_changed.emit(selected["f"])
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var w := size.x
	var h := RULER + KEYS_ROW + _lanes.size() * LANE_H
	draw_rect(Rect2(0, 0, w, h), PAD_COLOR)

	# beat grid (a darker line each bar), and the ruler
	var beats := int(DURATION / BEAT)
	for b in beats + 1:
		var x := _x_of(b * BEAT)
		var bar := b % 4 == 0
		draw_line(Vector2(x, RULER - (10.0 if bar else 5.0)), Vector2(x, h), Color(INK, 0.28 if bar else 0.1), 1.0)
		if bar:
			draw_string(font, Vector2(x + 4, 15), "%d" % (b / 4 + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(INK, 0.6))
	draw_line(Vector2(0, RULER), Vector2(w, RULER), Color(INK, 0.5), 1.0)
	draw_line(Vector2(0, RULER + KEYS_ROW), Vector2(w, RULER + KEYS_ROW), Color(INK, 0.3), 1.0)

	# lanes: the curve playback follows, and a dot per key
	for i in _lanes.size():
		var top := _lane_top(i)
		if i > 0:
			draw_line(Vector2(0, top), Vector2(w, top), Color(INK, 0.15), 1.0)
		draw_string(font, Vector2(6, top + 12), _lanes[i]["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(INK, 0.55))
		if keys.is_empty():
			continue
		var pts := PackedVector2Array()
		var steps := 120
		for s in steps + 1:
			var time := DURATION * s / steps
			pts.append(Vector2(_x_of(time), _lane_y(i, sample(time))))
		draw_polyline(pts, Color(INK, 0.8), 2.5, true)
		for k in keys:
			var p := Vector2(_x_of(k["t"]), _lane_y(i, k["f"]))
			draw_circle(p, 6.0, INK if k == selected else PAPER)
			draw_arc(p, 6.0, 0, TAU, 16, INK, 1.8, true)

	# keys row: a diamond per key, filled when voiced
	var cy := RULER + KEYS_ROW * 0.5
	for k in keys:
		var cx := _x_of(k["t"])
		var r := 11.0 if k == selected else 9.0
		var d := PackedVector2Array([Vector2(cx, cy - r), Vector2(cx + r, cy), Vector2(cx, cy + r), Vector2(cx - r, cy)])
		draw_colored_polygon(d, INK if k["f"]["voiced"] else PAPER)
		d.append(d[0])
		draw_polyline(d, INK, 1.5)

	# playhead
	var px := _x_of(t)
	draw_line(Vector2(px, 0), Vector2(px, h), Color(0.85, 0.15, 0.15) if recording else INK, 2.0)
	draw_rect(Rect2(0, 0, w, h), INK, false, 1.0)
