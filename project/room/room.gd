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
const GRASS := Color("#dcebc9")
const GRASS_HIGH := Color("#eef0d2")
const DIRT := Color("#eadfca")
const WATER := Color("#bfe0f2")
const ROCK := Color("#d8d4cc")
const PINE := Color("#8fcfa4")
const PINE_DARK := Color("#74b98c")
const STAGE := Color("#e9d2b4")
const SPEAKER := Color("#2b2b33")


var speakers: Array = []   # [box, cone] pairs that bounce on the kick drum
var _thump := 0.0
var booth_light: ShaderMaterial
var _into: Node3D                # where _put adds meshes (null: this node)


func _ready() -> void:
	_build()


## The kick drum just hit: make the speakers bounce.
func thump() -> void:
	_thump = 1.0


## The light over the booth door: red while someone is inside.
func set_booth_busy(on: bool) -> void:
	if booth_light:
		booth_light.set_shader_parameter("albedo", Color("#e4572e") if on else Color("#86c79a"))


func _process(delta: float) -> void:
	_thump *= exp(-delta / 0.09)
	for b in bulbs:
		b.scale = Vector3.ONE * (1.0 + 0.35 * _thump)
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
	(_into if _into else self).add_child(mi)
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
	_build_terrain()
	# The sky, all round.
	var sky := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 420.0
	dome.height = 840.0
	sky.mesh = dome
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://room/sky.gdshader")
	sky.material_override = sky_mat
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sky)

	# Rugs: sam's rug model in each rug's colour, scaled to its size, with its name on top.
	# The first rug has sam's stage on it, where sam put it in Blender.
	var models: Node3D = preload("res://models/world_props.glb").instantiate()
	var rug_mesh: Mesh = models.get_node("rug").mesh
	var stage_mesh: Mesh = models.get_node("stage").mesh
	models.free()
	for rug in World.RUGS:
		var ry := World.rug_height(rug)
		var k: float = rug["r"] / StageShape.RUG_R
		var disc := _put(rug_mesh, _mat(rug["color"], true), Vector3(rug["x"], ry, rug["z"]))
		disc.scale = Vector3.ONE * k
		if rug == World.RUGS[0]:
			var stage_mat := _mat(STAGE, true)
			stage_mat.set_shader_parameter("planks", 1.0)
			var stage := _put(stage_mesh, stage_mat, Vector3(rug["x"], ry, rug["z"]))
			stage.scale = Vector3.ONE * k
		var label := Label3D.new()
		label.text = rug["name"]
		label.modulate = INK
		label.outline_size = 0
		label.font_size = 64 if rug["r"] < 10.0 else 110
		label.pixel_size = 0.01
		label.rotation = Vector3(-PI / 2, 0, 0)
		label.position = Vector3(rug["x"], ry + StageShape.RUG_H * k + 0.03, rug["z"] + rug["r"] - (0.9 if rug["r"] < 10.0 else 2.0))
		add_child(label)
	_build_mic()
	_build_stage_lights()

	var white := _mat(WHITE)
	var wood := _mat(WOOD)
	var pot := _mat(POT, true)
	var leaf := _mat(LEAF, true)
	var leaf_dark := _mat(LEAF_DARK, true)
	var pine := _mat(PINE, true)
	var pine_dark := _mat(PINE_DARK, true)
	var trunk := _mat(WOOD, true, 0.03)
	var rock := _mat(ROCK, true)
	for o in World.obstacles():
		var x: float = o["x"]
		var z: float = o["z"]
		# Things out in the hills stand on the ground; build them at the origin of a holder.
		_into = null
		if o["kind"] in ["pine", "bush", "rock", "pond"]:
			_into = Node3D.new()
			_into.position = Vector3(x, World.height(x, z) if o["kind"] != "pond" else 0.0, z)
			add_child(_into)
			x = 0.0
			z = 0.0
		match o["kind"]:
			"pine":
				var k: float = o["s"]
				_put(_cyl(0.18 * k, 0.26 * k, 1.6 * k, 8), trunk, Vector3(0, 0.6 * k, 0))
				_put(_cone(1.7 * k, 2.8 * k), pine_dark, Vector3(0, 2.4 * k, 0))
				_put(_cone(1.3 * k, 2.4 * k), pine, Vector3(0, 3.6 * k, 0))
			"bush":
				var k: float = o["s"]
				_put(_cyl(0.14 * k, 0.2 * k, 2.4 * k, 8), trunk, Vector3(0, 1.1 * k, 0))
				_put(_ball(1.4 * k), leaf, Vector3(0, 2.8 * k, 0))
				_put(_ball(0.9 * k), leaf_dark, Vector3(0.7 * k, 2.3 * k, 0.4 * k))
			"rock":
				var k: float = o["s"]
				var r := _put(_ball(1.0 * k), rock, Vector3(0, 0.2 * k, 0))
				r.scale = Vector3(1.2, 0.7, 1.0)
			"pond":
				var wr: float = World.POND["r"] + 1.3
				_put(_cyl(wr, wr, 0.02, 64), _mat(WATER), Vector3(0, World.POND["water"], 0))
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
			"speaker":
				# Facing the crowd, bouncing on the kick drum.
				var w: float = o["w"]
				var hgt := w * 1.55
				var spk := _put(_box(Vector3(w, hgt, o["d"])), _mat(SPEAKER), Vector3(x, World.height(x, z) + hgt / 2.0, z))
				var cone := MeshInstance3D.new()
				cone.mesh = _cyl(w * 0.32, w * 0.32, 0.02, 32)
				cone.material_override = _mat(Color("#8a8a96"))
				cone.rotation.x = PI / 2
				cone.position = Vector3(0, -hgt * 0.14, o["d"] / 2.0 + 0.01)
				spk.add_child(cone)
				speakers.append([spk, cone])
			"booth":
				_put(_box(Vector3(o["w"], 1.4, o["d"])), _mat(WALL, true, 0.03), Vector3(x, 0.7, z))
			"crate":
				_put(_box(Vector3(o["w"], o["w"], o["d"])), wood, Vector3(x, o["w"] / 2.0, z))
			"table":
				var w: float = o["w"]
				var d: float = o["d"]
				_put(_box(Vector3(w, 0.15, d)), white, Vector3(x, 1.0, z))
				for sx in [-1.0, 1.0]:
					_put(_box(Vector3(0.2, 0.95, d * 0.8)), white, Vector3(x + sx * (w / 2 - 0.4), 0.47, z))

		# A soft shadow on the ground under it.
		if o["kind"] != "pond" and o["kind"] != "booth":
			var sr: float = o["r"] if o["shape"] == "circle" else maxf(o["w"], o["d"]) * 0.6
			if o.has("s"):
				sr = maxf(sr, 1.2 * float(o["s"]))
			_shadow(Vector3(x, 0.0 if _into else World.height(x, z), z), sr * 1.25)

	_into = null
	_build_flowers()

	# The booth's floor, sign and "on air" light.
	var bx: float = World.BOOTH["x"]
	var bz: float = World.BOOTH["z"]
	_put(_box(Vector3(World.BOOTH["w"] - 0.3, 0.02, World.BOOTH["d"] - 0.3)), _mat(Color("#3a3644")), Vector3(bx, 0.015, bz))
	var booth_sign := Label3D.new()
	booth_sign.text = "~/booth"
	booth_sign.modulate = INK
	booth_sign.outline_size = 0
	booth_sign.font_size = 64
	booth_sign.pixel_size = 0.01
	booth_sign.rotation = Vector3(-PI / 2, 0, 0)
	booth_sign.position = Vector3(bx, 0.03, bz + World.BOOTH["d"] / 2.0 + 0.7)
	add_child(booth_sign)
	booth_light = _mat(Color("#86c79a"), true, 0.03)
	_put(_ball(0.22), booth_light, Vector3(bx + World.BOOTH["w"] / 2.0 - 0.15, 1.65, bz - 1.55))


var bulbs: Array = []       # the lights strung over the stage: they glow brighter on the kick
var _bulb_mat: ShaderMaterial


func _shadow(at: Vector3, r: float) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.2, 0.18, 0.15, 0.13)
	var disc := _put(_cyl(r, r, 0.01, 24), m, at + Vector3(0, 0.025, 0))
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# Strings of lights over the back of the stage, on four poles.
func _build_stage_lights() -> void:
	var poles := [Vector2(-14.0, -3.5), Vector2(-8.5, -18.0), Vector2(8.5, -18.0), Vector2(14.0, -3.5)]
	var tops := []
	for p in poles:
		var base := World.height(p.x, p.y)
		var top := World.deck_y() + 6.0
		_put(_cyl(0.07, 0.09, top - base, 8), _mat(INK), Vector3(p.x, (base + top) / 2.0, p.y))
		tops.append(Vector3(p.x, top, p.y))
	_bulb_mat = ShaderMaterial.new()
	_bulb_mat.shader = toon_shader
	_bulb_mat.set_shader_parameter("albedo", Color("#ffe39a"))
	_bulb_mat.set_shader_parameter("light_dir_view", Vector3(0, 0, 1)) # glowing: lit all round
	var wire := _mat(INK)
	for i in tops.size() - 1:
		var a: Vector3 = tops[i]
		var b: Vector3 = tops[i + 1]
		var n := int(a.distance_to(b) / 1.6)
		var prev := a
		for k in range(1, n + 1):
			var t := float(k) / n
			var q := a.lerp(b, t) - Vector3(0, 1.6 * sin(t * PI), 0) # sags in the middle
			var mid := (prev + q) / 2.0
			var seg := _put(_cyl(0.025, 0.025, prev.distance_to(q), 4), wire, mid)
			seg.look_at_from_position(mid, q, Vector3.UP if absf((q - prev).normalized().y) < 0.99 else Vector3.RIGHT)
			seg.rotate_object_local(Vector3.RIGHT, PI / 2)
			if k < n:
				bulbs.append(_put(_ball(0.2), _bulb_mat, q - Vector3(0, 0.22, 0)))
			prev = q


# The mic stand at the front of the stage, where you stand for your reveal.
func _build_mic() -> void:
	var y := World.deck_y()
	_put(_cyl(0.05, 0.05, 1.9, 8), _mat(INK), Vector3(World.MIC.x, y + 0.95, World.MIC.y))
	_put(_cyl(0.35, 0.4, 0.06, 16), _mat(INK), Vector3(World.MIC.x, y + 0.03, World.MIC.y))
	_put(_ball(0.16), _mat(Color("#222222"), true, 0.02), Vector3(World.MIC.x, y + 1.95, World.MIC.y))


# The hills: one big grid mesh around the plaza, coloured by height.
func _build_terrain() -> void:
	var step := 2.0
	var nx := int(World.MAP_HX * 2.0 / step) + 1
	var nz := int(World.MAP_HZ * 2.0 / step) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := PackedFloat32Array()
	hs.resize(nx * nz)
	for j in nz:
		for i in nx:
			var x := -World.MAP_HX + i * step
			var z := -World.MAP_HZ + j * step
			var h := World.ground(x, z)
			# Tuck the ground under the plaza's floor.
			if absf(x) < World.WIDTH / 2.0 + 0.5 and absf(z) < World.DEPTH / 2.0 + 0.5:
				h = minf(h, -0.12)
			hs[j * nx + i] = h
	var pos := func(i: int, j: int) -> Vector3:
		return Vector3(-World.MAP_HX + i * step, hs[j * nx + i], -World.MAP_HZ + j * step)
	for j in nz - 1:
		for i in nx - 1:
			var quad := [pos.call(i, j), pos.call(i + 1, j), pos.call(i + 1, j + 1), pos.call(i, j + 1)]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var a: Vector3 = quad[tri[0]]
				var b: Vector3 = quad[tri[1]]
				var c: Vector3 = quad[tri[2]]
				var n := (c - a).cross(b - a).normalized()
				if n.y < 0.0:
					n = -n
				# Flat faces, so the hills read as low-poly facets.
				var mid := (a + b + c) / 3.0
				var col := GRASS.lerp(GRASS_HIGH, clampf(mid.y / 12.0, 0.0, 1.0))
				if n.y < 0.8 and mid.y > 1.5:
					col = col.lerp(DIRT, 0.6)
				for v in [a, c, b]:
					st.set_color(col)
					st.set_normal(n)
					st.add_vertex(v)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://room/terrain.gdshader")
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)


# Flowers dotted over the meadow: one multimesh, no outlines.
func _build_flowers() -> void:
	var colors := [Color("#f4a6c8"), Color("#fbe28c"), Color("#ffffff"), Color("#c6b4f2")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _ball(0.18)
	mm.instance_count = 240
	var meadow: Dictionary = World.RUGS.filter(func(r): return r["name"] == "~/meadow")[0]
	for k in mm.instance_count:
		var a := rng.randf() * TAU
		var d := lerpf(meadow["r"] + 1.0, 26.0, sqrt(rng.randf()))
		var x: float = meadow["x"] + cos(a) * d
		var z: float = meadow["z"] + sin(a) * d * 0.8
		mm.set_instance_transform(k, Transform3D(Basis(), Vector3(x, World.height(x, z) + 0.2, z)))
		mm.set_instance_color(k, colors[k % colors.size()])
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://room/flower.gdshader")
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
