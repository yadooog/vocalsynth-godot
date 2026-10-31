extends Node3D
## Builds the hub room from World's layout: floor, walls, rugs with their names, and the
## furniture and plants, in the same flat toon style as the character.

var toon_shader: Shader = preload("res://character/toon.gdshader")
var outline_shader: Shader = preload("res://character/outline.gdshader")

const INK := Color(0.133, 0.133, 0.125)
const WHITE := Color("#fbf8f4")
const WOOD := Color("#e9d2b4")
const POT := Color("#f4eec0")
const LEAF := Color("#a8dcb4")
const LEAF_DARK := Color("#86c79a")
const WALL := Color("#e4dcf2")


var speakers: Array = []   # [box, cone] pairs that bounce on the kick drum
var _thump := 0.0


func _ready() -> void:
	_build()


## The kick drum just hit: make the speakers bounce.
func thump() -> void:
	_thump = 1.0


func _process(delta: float) -> void:
	_thump *= exp(-delta / 0.09)
	for s in speakers:
		s[0].scale = Vector3(1.0 + 0.06 * _thump, 1.0 - 0.04 * _thump, 1.0 + 0.06 * _thump)
		s[1].scale = Vector3.ONE * (1.0 + 0.25 * _thump)


func _mat(color: Color, outline := false, width := 0.04) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = toon_shader
	m.set_shader_parameter("albedo", color)
	if outline:
		var o := ShaderMaterial.new()
		o.shader = outline_shader
		o.set_shader_parameter("width", width)
		m.next_pass = o
	return m


func _put(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top: float, bottom: float, height: float, segments := 32) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


func _ball(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 12
	return s


func _cone(r: float, h: float) -> CylinderMesh:
	return _cyl(0.0, r, h, 10)


func _build() -> void:
	# Floor and low walls.
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = preload("res://room/floor.gdshader")
	_put(_box(Vector3(World.WIDTH, 0.1, World.DEPTH)), floor_mat, Vector3(0, -0.05, 0))
	var t := 0.4
	var h := 1.2
	var wall := _mat(WALL)
	for w in [[0.0, -World.DEPTH / 2 - t / 2, World.WIDTH + t * 2, t], [0.0, World.DEPTH / 2 + t / 2, World.WIDTH + t * 2, t],
			[-World.WIDTH / 2 - t / 2, 0.0, t, World.DEPTH], [World.WIDTH / 2 + t / 2, 0.0, t, World.DEPTH]]:
		_put(_box(Vector3(w[2], h, w[3])), wall, Vector3(w[0], h / 2, w[1]))

	# Rugs: a pastel disc on a slightly bigger ink disc (the ring), with the name on the floor.
	for rug in World.RUGS:
		_put(_cyl(rug["r"] + 0.06, rug["r"] + 0.06, 0.02, 64), _mat(INK), Vector3(rug["x"], 0.005, rug["z"]))
		_put(_cyl(rug["r"], rug["r"], 0.02, 64), _mat(rug["color"]), Vector3(rug["x"], 0.012, rug["z"]))
		if rug["name"] != "~/middle":
			var label := Label3D.new()
			label.text = rug["name"]
			label.modulate = INK
			label.outline_size = 0
			label.font_size = 64
			label.pixel_size = 0.01
			label.rotation = Vector3(-PI / 2, 0, 0)
			label.position = Vector3(rug["x"], 0.03, rug["z"] + rug["r"] - 0.9)
			add_child(label)

	var white := _mat(WHITE)
	var wood := _mat(WOOD)
	var pot := _mat(POT, true)
	var leaf := _mat(LEAF, true)
	var leaf_dark := _mat(LEAF_DARK, true)
	for o in World.OBSTACLES:
		var x: float = o["x"]
		var z: float = o["z"]
		match o["kind"]:
			"column":
				var r: float = o["r"]
				_put(_cyl(r, r, 4.0), _mat(WHITE, true), Vector3(x, 2.0, z))
				_put(_box(Vector3(r * 2.6, 0.3, r * 2.6)), white, Vector3(x, 4.15, z))
			"planter":
				var r: float = o["r"]
				_put(_cyl(r, r * 0.9, 0.8, 40), pot, Vector3(x, 0.4, z))
				for i in 7:
					var a := float(i) / 7.0 * TAU
					var rr := 0.0 if i == 0 else r * 0.55
					_put(_ball(0.55 + (i % 3) * 0.12), leaf if i % 2 else leaf_dark,
						Vector3(x + cos(a) * rr, 1.05 + (0.4 if i == 0 else 0.0), z + sin(a) * rr))
			"tree":
				var r: float = o["r"]
				_put(_cyl(r, r * 0.75, 1.0, 24), pot, Vector3(x, 0.5, z))
				_put(_cyl(0.16, 0.22, 3.0, 10), _mat(WOOD, true, 0.03), Vector3(x, 2.0, z))
				_put(_ball(1.5), leaf, Vector3(x, 4.0, z))
				_put(_ball(1.0), leaf_dark, Vector3(x + 0.8, 3.4, z + 0.5))
			"plant":
				var r: float = o["r"]
				_put(_cyl(r, r * 0.75, 0.8, 20), pot, Vector3(x, 0.4, z))
				for i in 5:
					_put(_cone(0.22, 1.6), leaf if i % 2 else leaf_dark, Vector3(x, 1.5, z),
						Vector3(((i * 7) % 3 - 1) * 0.25, 0, (i - 2) * 0.28))
			"bench":
				var w: float = o["w"]
				var d: float = o["d"]
				_put(_box(Vector3(w, 0.25, d)), wood, Vector3(x, 0.55, z))
				var along := w > d
				for sx in [-1.0, 1.0]:
					var leg := Vector3(0.2, 0.45, d * 0.8) if along else Vector3(w * 0.8, 0.45, 0.2)
					_put(_box(leg), wood, Vector3(x + (sx * (w / 2 - 0.3) if along else 0.0), 0.22, z + (0.0 if along else sx * (d / 2 - 0.3))))
			"stage":
				_put(_box(Vector3(o["w"], 0.6, o["d"])), _mat(POT), Vector3(x, 0.3, z))
				_put(_cyl(0.04, 0.04, 1.6, 8), _mat(INK), Vector3(x, 1.4, z + 0.5))
				_put(_ball(0.14), _mat(Color("#222222"), true, 0.02), Vector3(x, 2.25, z + 0.5))
				# Two speakers behind the stage.
				for sx in [-1.0, 1.0]:
					var spk := _put(_box(Vector3(1.4, 2.2, 1.2)), _mat(Color("#2b2b33")), Vector3(World.STAGE["x"] + sx * 4.2, 1.7, World.STAGE["z"] - 5.5))
					var cone := MeshInstance3D.new()
					cone.mesh = _cyl(0.45, 0.45, 0.02, 32)
					cone.material_override = _mat(Color("#8a8a96"))
					cone.rotation.x = PI / 2
					cone.position = Vector3(0, -0.3, 0.61)
					spk.add_child(cone)
					speakers.append([spk, cone])
			"crate":
				_put(_box(Vector3(o["w"], o["w"], o["d"])), wood, Vector3(x, o["w"] / 2.0, z))
			"table":
				var w: float = o["w"]
				var d: float = o["d"]
				_put(_box(Vector3(w, 0.15, d)), white, Vector3(x, 1.0, z))
				for sx in [-1.0, 1.0]:
					_put(_box(Vector3(0.2, 0.95, d * 0.8)), white, Vector3(x + sx * (w / 2 - 0.4), 0.47, z))
