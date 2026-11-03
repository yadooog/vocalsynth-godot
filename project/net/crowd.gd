extends Node
## The crowd: cheers and tomatoes thrown at whoever's on stage (a reveal, or a loop in the
## vote), and the big words across the screen when a round, your turn or the vote starts.
## main.gd makes it; net.gd passes on everyone's reactions.

const FLIGHT := 0.8                 # seconds a tomato or a cheer takes to reach the stage
const TOMATO := Color("#e4572e")
const CONFETTI := [Color("#f4c87a"), Color("#8fd3e8"), Color("#f29a8a"), Color("#a8dcb4"), Color("#b9b0f2")]

var main: Control
var net: Node
var bar: PanelContainer             # cheer / tomato, while someone's on stage
var banner: Label
var _banner_left := 0.0
var _flying: Array = []             # [{node, from, to, t, kind}]
var _splats: Array = []             # [{node, left}]
var _shown := ""


func _ready() -> void:
	bar = PanelContainer.new()
	bar.theme_type_variation = &"TopBar"
	bar.visible = false
	main.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	for r in ["cheer", "tomato"]:
		var b := Button.new()
		b.text = r
		b.name = r
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): net.react(r, stage_index()))
		row.add_child(b)
	banner = Label.new()
	banner.theme_type_variation = &"BoldLabel"
	banner.add_theme_font_size_override("font_size", 46)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	main.add_child(banner)
	net.game_changed.connect(_on_game)


## Big words across the middle of the room for a moment.
func announce(text: String) -> void:
	banner.text = text
	_banner_left = 2.2


func _on_game() -> void:
	var g: Dictionary = net.game
	var phase: String = net.phase()
	var step := "%s %s %s" % [g.get("round", 0), phase, g.get("turn")]
	if step == _shown:
		return
	_shown = step
	match phase:
		"brief":
			announce("round %d" % int(g.get("round", 1)))
		"build":
			if net.my_turn():
				announce("your turn!")
		"vote":
			announce("vote!")
		"results":
			announce("results")


## Where the act on stage is: the reveal spot, or the singer whose loop is playing.
func _stage_target() -> Node3D:
	var i := stage_index()
	if main.booth_state == "reveal" or main.booth_state == "reveal_wait":
		return main.character
	if i >= 0 and i < main.song.sections.size():
		var s: Dictionary = main.song.sections[i]
		# During a reveal the performer is in the spotlight; their singer is still hidden.
		if not s["singer"].visible and main.remote_reveal == i:
			var who = net.others.get(s["owner"])
			if who:
				return who["node"]
		return s["singer"]
	return null


## Which loop in the song is on stage now (its reveal, or its turn in the vote), or -1.
var _anyone := 0
func stage_index() -> int:
	var i: int = main.remote_reveal if main.remote_reveal >= 0 else (main.reveal_index if main.booth_state == "reveal" else -1)
	if i < 0 and main.vote_playing >= 0:
		i = main.vote_playing
	elif i < 0 and main.vote_playing == -1 and not main.song.sections.is_empty():
		_anyone = (_anyone + 1) % main.song.sections.size() # all together: anyone on stage
		i = _anyone
	return i


func on_stage_now() -> bool:
	return _stage_target() != null


## Someone (maybe us) threw something.
func react(id: String, kind: String) -> void:
	var target := _stage_target()
	if target == null:
		return
	var from: Vector3
	if id == net.you:
		from = main.character.position
	elif net.others.has(id):
		from = net.others[id]["node"].position
	else:
		return
	from.y += 2.5
	var count := 1 if kind == "tomato" else 6
	for k in count:
		var node := MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = TOMATO if kind == "tomato" else CONFETTI[randi() % CONFETTI.size()]
		if kind == "tomato":
			var ball := SphereMesh.new()
			ball.radius = 0.32
			ball.height = 0.6
			node.mesh = ball
		else:
			var bit := BoxMesh.new()
			bit.size = Vector3(0.22, 0.04, 0.14)
			node.mesh = bit
		node.material_override = m
		main.room.add_child(node)
		node.position = from
		var jitter := Vector3(randf_range(-1.2, 1.2), randf_range(0, 1), randf_range(-0.8, 0.8)) if kind == "cheer" else Vector3.ZERO
		_flying.append({"node": node, "from": from, "target": target, "off": jitter, "t": -k * 0.05, "kind": kind})


func _process(delta: float) -> void:
	# The cheer / tomato bar, while someone's on stage and it isn't you.
	var show: bool = net.connected and on_stage_now() and not (main.booth_state in ["reveal", "reveal_wait", "booth"])
	if bar.visible != show:
		bar.visible = show
	if show:
		bar.size = bar.get_combined_minimum_size()
		bar.position = Vector2((main.size.x - bar.size.x) * 0.5, main.size.y * 0.5 + 40.0)
	# The banner fades in and out.
	_banner_left -= delta
	banner.modulate.a = clampf(minf(_banner_left / 0.4, (2.2 - _banner_left) / 0.15), 0.0, 1.0)
	banner.size = Vector2(main.size.x, 60)
	banner.position = Vector2(0, main.size.y * 0.32)
	# Things in the air.
	for f in _flying.duplicate():
		f["t"] += delta / FLIGHT
		var t: float = clampf(f["t"], 0.0, 1.0)
		var to: Vector3 = f["target"].position + Vector3(0, 2.6, 0) if is_instance_valid(f["target"]) else f["from"]
		var p: Vector3 = f["from"].lerp(to + f["off"], t)
		p.y += sin(t * PI) * 4.0 # an arc
		f["node"].position = p
		f["node"].rotation += Vector3(7, 5, 3) * delta
		if f["t"] >= 1.0:
			_flying.erase(f)
			if f["kind"] == "tomato" and is_instance_valid(f["target"]):
				_splat(f["target"], f["node"])
			else:
				f["node"].queue_free()
	for s in _splats.duplicate():
		s["left"] -= delta
		s["node"].scale = Vector3(1.6, 0.25, 1.6) * clampf(s["left"] / 0.5, 0.0, 1.0)
		if s["left"] <= 0.0:
			s["node"].queue_free()
			_splats.erase(s)


# A tomato lands: squash the performer and leave a splat for a moment.
func _splat(target: Node3D, node: MeshInstance3D) -> void:
	if "squash" in target:
		target.squash = 0.35
	node.position = target.position + Vector3(0, 2.4 + randf_range(-0.4, 0.6), 0.9)
	_splats.append({"node": node, "left": 1.6})
