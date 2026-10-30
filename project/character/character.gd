extends Node3D
## A heavy-headed little creature that speaks with the synth: a pill-shaped head on a small
## body, googly eyes, and a long floppy tongue. Ported from client/character3d.js in the
## vocalcordgame web game.
##
## Call `update_character(delta, face, time)` every frame. `face` is a Dictionary:
##   open     0..1   how far the mouth is open (the tongue comes out as it opens)
##   lips     0..1   lip spread; widens the head
##   jaw      0..1   jaw drop; heightens the head
##   shut     bool   lips closed
##   tilt     radians of head tilt (from pitch)
##   brow     -1..1.5 pitch height
##   talking  0 or 1
##   loud     0..1
##   angry    0..1    tense, loud voice
##   sad      0..1    breathy voice
## Movement comes from moving this node around (walk_to() or just set position); the head
## wobbles on its neck whenever the body speeds up, slows down or turns.

# --- Shape (the average of the ranges the web game picks from) -----------------------
const HEAD_R := 0.68
const HEAD_LEN := 1.2
const HEAD_DEPTH := 0.83
const BODY_R := 0.36
const BODY_LEN := 0.27
const LEG_R := 0.115
const LEG_LEN := 0.385
const LEG_GAP := 0.165
const ARM_R := 0.07
const ARM_LEN := 0.72
const MOUTH_W := 0.75      # mouth width, relative to the head's half-width
const MOUTH_Y := -0.22     # below the head's centre
const EYE_GAP := 0.32
const EYE_Y := 0.28
const EYE_R := 0.25

# --- Physics knobs --------------------------------------------------------------------
const NECK_STIFFNESS := 55.0     # how hard the neck pulls the head back upright
const NECK_DAMPING := 3.5        # lower = wobbles for longer
const TOPPLE := 30.0             # how much gravity tips it further once it leans
const HEAD_INERTIA := 0.09       # how much speeding up / slowing down throws the head
const HEAD_MAX_LEAN := 0.75      # radians; the neck won't let it go past this

const TONGUE_POINTS := 20
const TONGUE_MAX_LENGTH := 3.8
const TONGUE_OUT_START := 0.12   # mouth openness where the tongue starts to come out
const TONGUE_OUT_FULL := 0.65    # ... and where it is all the way out
const TONGUE_RADIUS := 0.17
const TONGUE_FLATNESS := 0.5
const TONGUE_GRAVITY := 8.0
const TONGUE_DAMPING := 0.996
const TONGUE_STIFFNESS := 0.035
const TONGUE_ROOT_STIFFNESS := 0.3
const TONGUE_FLAP := 3.0
const TONGUE_WRITHE := 1.0
const TONGUE_TWITCH := 0.0
const TONGUE_LENGTH_SPRING := 120.0
const TONGUE_LENGTH_DAMPING := 9.0
const TONGUE_BULGE := 0.35
const TONGUE_SLURP := 3.0
const TONGUE_STEP := 1.0 / 120.0

const HEAD_COLOR := Color(0.957, 0.663, 0.769)
const OUTFIT_COLOR := Color(0.435, 0.827, 0.941)
const TONGUE_COLOR := Color(1.0, 0.47, 0.6)
const LIP_COLOR := Color(1.0, 0.2, 0.275)

var toon_shader: Shader = preload("res://character/toon.gdshader")
var toon_double_shader: Shader = preload("res://character/toon_double.gdshader")
var outline_shader: Shader = preload("res://character/outline.gdshader")

# Body parts
var body: MeshInstance3D
var neck: Node3D
var head: Node3D
var skull: MeshInstance3D
var legs: Array = []      # [{hip: Node3D, side: float}]
var arms: Array = []      # [{shoulder: Node3D, side: float}]
var eyes: Array = []      # [{root: Node3D, pupil: MeshInstance3D, side: float, p: Vector2, v: Vector2, last: Vector3}]
var mouth: Node3D
var hole: MeshInstance3D
var lips_mesh: MeshInstance3D
var tongue_mesh: MeshInstance3D
var tongue_tip: MeshInstance3D
var floor_shadow: MeshInstance3D

# Layout numbers worked out from the shape
var leg_h := 0.0
var body_h := 0.0
var head_h := 0.0
var body_y := 0.0
var head_y := 0.0
var neck_y := 0.0
var shoulder_y := 0.0
var hip_y := 0.0
var top_y := 0.0

# Animation state
var walk_phase := 0.0
var hop := 0.0
var hop_vel := 0.0
var squash := 0.0
var sag := 0.0
var sag_vel := 0.0
var was_talking := false
var lean_x := 0.0
var lean_z := 0.0
var lean_vx := 0.0
var lean_vz := 0.0
var last_pos := Vector3.ZERO
var last_vel := Vector3.ZERO
var accel := Vector3.ZERO
var last_ry := 0.0
var have_last := false
var walk := 0.0                       # 0 standing .. 1 full speed
var walk_target = null                # Vector3 or null
var head_sx := 1.0                    # current head width / height factors (springy)
var head_sy := 1.0
var head_sx_v := 0.0
var last_open := 0.0
var head_sy_v := 0.0
var mouth_key := ""

# Tongue state (world space)
var points: Array = []
var prev: Array = []
var tongue_length := 0.02
var tongue_vel := 0.0
var tongue_accum := 0.0
var flap_time := 0.0
var tongue_was_talking := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_build()


# ------------------------------------------------------------------ building

func _toon(color: Color, with_outline := true, outline_width := 0.035) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = toon_shader
	m.set_shader_parameter("albedo", color)
	if with_outline:
		var o := ShaderMaterial.new()
		o.shader = outline_shader
		o.set_shader_parameter("width", outline_width)
		m.next_pass = o
	return m


func _toon_double(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = toon_double_shader
	m.set_shader_parameter("albedo", color)
	return m


func _capsule(radius: float, straight: float, mat: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = straight + 2.0 * radius
	mesh.radial_segments = 32
	mesh.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


func _sphere(radius: float, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


func _build() -> void:
	leg_h = LEG_LEN + 2.0 * LEG_R
	body_h = BODY_LEN + 2.0 * BODY_R
	head_h = HEAD_LEN + 2.0 * HEAD_R
	body_y = leg_h + body_h / 2.0 - 0.12
	head_y = body_y + body_h / 2.0 + head_h / 2.0 - HEAD_R * 0.45
	shoulder_y = body_y + body_h / 2.0 - 0.12
	hip_y = leg_h
	top_y = head_y + head_h / 2.0
	neck_y = body_y + body_h / 2.0 - 0.1

	var outfit := _toon(OUTFIT_COLOR, true, 0.025)
	var skin := _toon(HEAD_COLOR, true, 0.025)

	# Soft round shadow on the floor.
	var shadow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.01
	shadow.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0, 0, 0, 0.18)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = sm
	shadow.position.y = 0.006
	add_child(shadow)
	floor_shadow = shadow

	# Legs
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * LEG_GAP, hip_y, 0)
		var leg := _capsule(LEG_R, LEG_LEN, outfit)
		leg.position.y = -leg_h / 2.0 + LEG_R * 0.2
		hip.add_child(leg)
		add_child(hip)
		legs.append({"hip": hip, "side": side})

	# Body
	body = _capsule(BODY_R, BODY_LEN, outfit)
	body.position.y = body_y
	add_child(body)

	# Arms
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * (BODY_R + ARM_R * 0.7), shoulder_y, 0)
		var arm := _capsule(ARM_R, ARM_LEN, skin)
		arm.position.y = -(ARM_LEN / 2.0 + ARM_R) + ARM_R
		shoulder.add_child(arm)
		add_child(shoulder)
		arms.append({"shoulder": shoulder, "side": side})

	# Neck pivot and head. Everything on the face is a child of `head`, which is NOT scaled;
	# only the skull mesh is, so eyes and mouth stay round.
	neck = Node3D.new()
	neck.position.y = neck_y
	add_child(neck)
	head = Node3D.new()
	head.position.y = head_y - neck_y
	neck.add_child(head)
	skull = _capsule(HEAD_R, HEAD_LEN, _toon(HEAD_COLOR, true, 0.045))
	head.add_child(skull)

	# Googly eyes: a white dome with a loose black pupil rattling around inside.
	for side in [-1.0, 1.0]:
		var root := Node3D.new()
		head.add_child(root)
		var white := _sphere(EYE_R, _toon(Color(1, 1, 1), true, 0.03))
		white.scale = Vector3(1, 1, 0.55)
		root.add_child(white)
		var pupil := _sphere(EYE_R * 0.46, _toon(Color(0.05, 0.05, 0.05), false))
		pupil.scale = Vector3(1, 1, 0.4)
		root.add_child(pupil)
		eyes.append({"root": root, "pupil": pupil, "side": side, "p": Vector2.ZERO, "v": Vector2.ZERO, "last": Vector3.ZERO, "have_last": false})

	# Mouth: a dark hole with a red lip ring, rebuilt whenever its shape changes.
	mouth = Node3D.new()
	head.add_child(mouth)
	hole = MeshInstance3D.new()
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0, 0, 0)
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hole.material_override = hm
	lips_mesh = MeshInstance3D.new()
	lips_mesh.material_override = _toon_double(LIP_COLOR)
	mouth.add_child(hole)
	mouth.add_child(lips_mesh)

	# Tongue: lives in world space (top level) so it swings when the body moves.
	var tm := _toon_double(TONGUE_COLOR)
	tongue_mesh = MeshInstance3D.new()
	tongue_mesh.top_level = true
	tongue_mesh.material_override = tm
	tongue_mesh.visible = false
	add_child(tongue_mesh)
	tongue_tip = _sphere(TONGUE_RADIUS * 1.15, tm)
	tongue_tip.top_level = true
	tongue_tip.visible = false
	add_child(tongue_tip)

	_apply_head_shape(1.0, 1.0)


# ------------------------------------------------------------------ head shape

# How far forward the head's surface is at (x, y), in head space, for the current shape.
func surface_z(x: float, y: float) -> float:
	var a := HEAD_R * head_sx
	var c := HEAD_R * head_sy
	var dy: float = maxf(0.0, absf(y) - HEAD_LEN * head_sy / 2.0)
	var rr := 1.0 - (x * x) / (a * a) - (dy * dy) / (c * c)
	return HEAD_DEPTH * HEAD_R * sqrt(maxf(0.0, rr))


func _apply_head_shape(sx: float, sy: float) -> void:
	head_sx = sx
	head_sy = sy
	skull.scale = Vector3(sx, sy, HEAD_DEPTH)
	# Keep the chin where it was: a taller head grows upwards.
	head.position.y = (head_y - neck_y) + (head_h / 2.0) * (sy - 1.0)
	mouth.position = Vector3(0, MOUTH_Y * sy, surface_z(0, MOUTH_Y * sy))
	for e in eyes:
		var x: float = e["side"] * EYE_GAP * sx
		var y := EYE_Y * sy
		e["root"].position = Vector3(x, y, surface_z(x, y) + 0.02)
	mouth_key = ""


# Builds the lip ring and the dark inside for a mouth of half-width w and half-height h.
func _build_mouth(w: float, h: float) -> void:
	var y0: float = mouth.position.y
	var z0: float = mouth.position.z
	var ry: float = maxf(h, 0.001)
	# Lips: a thin tube round the edge of the opening (a line when closed).
	var n := 40
	var radial := 6
	var tube_r := 0.03
	var centers: Array = []
	for i in n:
		var a := float(i) / n * TAU
		var x := cos(a) * w
		var y := sin(a) * ry
		centers.append(Vector3(x, y, surface_z(x, y0 + y) - z0 + 0.025))
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in n:
		var c: Vector3 = centers[i]
		var t: Vector3 = (centers[(i + 1) % n] - centers[(i + n - 1) % n]).normalized()
		var side := t.cross(Vector3(0, 0, 1)).normalized()
		var out := side.cross(t).normalized()
		for r in radial:
			var b := float(r) / radial * TAU
			var dir := (side * cos(b) + out * sin(b)).normalized()
			verts.append(c + dir * tube_r)
			norms.append(dir)
	for i in n:
		for r in radial:
			var a0 := i * radial + r
			var a1 := i * radial + (r + 1) % radial
			var b0 := ((i + 1) % n) * radial + r
			var b1 := ((i + 1) % n) * radial + (r + 1) % radial
			_tris(idx, [a0, b0, a1, a1, b0, b1])
	lips_mesh.mesh = _array_mesh(verts, norms, idx)

	# The dark inside: a disc of rings that bends with the face.
	var RINGS := 7
	var SEGS := 32
	var hv := PackedVector3Array([Vector3(0, 0, surface_z(0, y0) - z0 + 0.02)])
	var hn := PackedVector3Array([Vector3(0, 0, 1)])
	var hi := PackedInt32Array()
	for r in range(1, RINGS + 1):
		for i in SEGS:
			var a := float(i) / SEGS * TAU
			var x := cos(a) * w * float(r) / RINGS
			var y := sin(a) * ry * float(r) / RINGS
			hv.append(Vector3(x, y, surface_z(x, y0 + y) - z0 + 0.02))
			hn.append(Vector3(0, 0, 1))
	for i in SEGS:
		_tris(hi, [0, 1 + i, 1 + (i + 1) % SEGS])
	for r in range(1, RINGS):
		for i in SEGS:
			var a0 := 1 + (r - 1) * SEGS + i
			var a1 := 1 + (r - 1) * SEGS + (i + 1) % SEGS
			var b0 := 1 + r * SEGS + i
			var b1 := 1 + r * SEGS + (i + 1) % SEGS
			_tris(hi, [a0, b0, b1, a0, b1, a1])
	hole.mesh = _array_mesh(hv, hn, hi)
	hole.visible = h > 0.015


# Adds triangles given as a flat list of vertex numbers.
func _tris(idx: PackedInt32Array, list: Array) -> void:
	for v in list:
		idx.append(v)


func _array_mesh(verts: PackedVector3Array, norms: PackedVector3Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# ------------------------------------------------------------------ walking

## Walk towards a spot on the floor (x, z). Pass null to stop.
func walk_to(target) -> void:
	walk_target = target


func _physics_process(delta: float) -> void:
	var speed := 0.0
	if walk_target != null:
		var to: Vector3 = walk_target - position
		to.y = 0
		var dist := to.length()
		if dist < 0.08:
			walk_target = null
		else:
			var want: float = minf(3.2, dist * 3.0)
			position += to / dist * minf(want * delta, dist)
			speed = want
	walk = lerpf(walk, clampf(speed / 3.2, 0.0, 1.0), 1.0 - exp(-10.0 * delta))


# ------------------------------------------------------------------ per-frame update

func update_character(dt: float, face: Dictionary, time: float) -> void:
	dt = minf(dt, 1.0 / 20.0)
	if dt <= 0.0:
		return
	var talking: float = face.get("talking", 0.0)
	var loud: float = face.get("loud", 0.0)
	var angry: float = face.get("angry", 0.0)
	var brow: float = face.get("brow", 0.0)

	# Head width follows the lips and its height follows the jaw, with a springy overshoot.
	# The base shape comes from the size slider (bigger = fatter and bigger); the mouth only
	# squashes and stretches it for a moment while it opens, closes and spreads.
	var size01 := clampf(face.get("size", 0.0) * 0.5 + 0.5, 0.0, 1.0)
	var djaw: float = face.get("jaw", 0.5) - 0.5
	var dlips: float = face.get("lips", 0.71) - 0.71
	var want_sx: float = lerpf(0.72, 1.45, size01) * (1.0 + 0.3 * dlips - 0.15 * djaw)
	var want_sy: float = lerpf(0.8, 1.3, size01) * (1.0 + 0.45 * djaw - 0.1 * dlips)
	# Opening or closing the mouth bounces the head.
	var open_now: float = face.get("open", 0.0)
	sag_vel += (open_now - last_open) * 9.0
	last_open = open_now
	head_sx_v += ((want_sx - head_sx) * 220.0 - head_sx_v * 14.0) * dt
	head_sy_v += ((want_sy - head_sy) * 220.0 - head_sy_v * 14.0) * dt
	var nsx: float = clampf(head_sx + head_sx_v * dt, 0.5, 1.7)
	var nsy: float = clampf(head_sy + head_sy_v * dt, 0.5, 1.7)
	if absf(nsx - head_sx) > 0.0005 or absf(nsy - head_sy) > 0.0005:
		_apply_head_shape(nsx, nsy)

	# A small hop when a sound starts; heavy landing squashes the body and sinks the head.
	var is_talking := talking > 0.5
	if is_talking and not was_talking:
		hop_vel = 1.8 + 1.2 * loud
	was_talking = is_talking
	hop_vel -= 22.0 * dt
	hop += hop_vel * dt
	if hop <= 0.0:
		if hop_vel < -1.0:
			squash = minf(0.35, -hop_vel * 0.08)
			sag_vel -= -hop_vel * 0.35
		hop = 0.0
		hop_vel = 0.0
	squash *= exp(-7.0 * dt)
	sag_vel += (-90.0 * sag - 7.0 * sag_vel) * dt
	sag = clampf(sag + sag_vel * dt, -0.3, 0.15)

	# How the body is moving, in its own frame, to throw the head about.
	var gp := position
	var ry := rotation.y
	if not have_last:
		last_pos = gp
		last_vel = Vector3.ZERO
		accel = Vector3.ZERO
		last_ry = ry
		have_last = true
	var vel := (gp - last_pos) / dt
	last_pos = gp
	var acc := ((vel - last_vel) / dt).limit_length(60.0)
	last_vel = vel
	accel = accel.lerp(acc, 1.0 - exp(-20.0 * dt))
	var c := cos(ry)
	var s := sin(ry)
	var acc_fwd := accel.x * s + accel.z * c
	var acc_side := accel.x * c - accel.z * s
	var turn_rate := wrapf(ry - last_ry, -PI, PI) / dt
	last_ry = ry

	# Walk: legs swing, body bobs and sways.
	walk_phase += dt * 11.0 * walk
	var step := sin(walk_phase) * walk
	for l in legs:
		l["hip"].rotation.x = 0.55 * step * l["side"]
	var bob := absf(sin(walk_phase)) * 0.1 * walk + hop
	var stretch := 1.0 + 0.06 * maxf(0.0, brow) + 0.05 * loud - squash
	body.scale = Vector3(1.0 + (1.0 - stretch) * 0.6, stretch, 1.0 + (1.0 - stretch) * 0.6)
	body.position.y = body_y * stretch + bob
	neck.position.y = neck_y + (stretch - 1.0) * 1.1 + bob + sag
	head.position.z = 0.12 * loud
	body.rotation.z = 0.06 * step - 0.25 * lean_z
	for l in legs:
		l["hip"].position.y = hip_y + bob * 0.3
	floor_shadow.scale = Vector3.ONE * clampf(1.0 - hop * 0.25, 0.6, 1.0)

	# Heavy head on a springy neck. It wants to tilt with pitch, nod when angry or loud,
	# droop while plodding, and loll slowly when idle.
	var loll := 0.05 * sin(time * 0.9 + EYE_GAP * 9.0)
	var want_z: float = face.get("tilt", 0.0) + 0.14 * step + loll
	var want_x: float = -0.08 * brow + 0.15 * angry - 0.08 * loud + 0.12 * walk + 0.4 * loll
	var push_x := -acc_fwd * HEAD_INERTIA * NECK_STIFFNESS * 0.1
	var push_z := (acc_side * HEAD_INERTIA - turn_rate * 0.03) * NECK_STIFFNESS * 0.1
	lean_vx += (-NECK_STIFFNESS * (lean_x - want_x) - NECK_DAMPING * lean_vx + TOPPLE * sin(lean_x) * 0.5 + push_x) * dt
	lean_vz += (-NECK_STIFFNESS * (lean_z - want_z) - NECK_DAMPING * lean_vz + TOPPLE * sin(lean_z) * 0.5 + push_z) * dt
	lean_x += lean_vx * dt
	lean_z += lean_vz * dt
	if absf(lean_x) > HEAD_MAX_LEAN:
		lean_x = signf(lean_x) * HEAD_MAX_LEAN
		lean_vx *= -0.3
	if absf(lean_z) > HEAD_MAX_LEAN:
		lean_z = signf(lean_z) * HEAD_MAX_LEAN
		lean_vz *= -0.3
	neck.rotation.x = lean_x
	neck.rotation.z = lean_z

	# Arms hang, swing when walking, rise with pitch and flail with loudness, and fling out
	# to balance when the head is falling over.
	for a in arms:
		var side: float = a["side"]
		var shoulder: Node3D = a["shoulder"]
		shoulder.position.y = shoulder_y + bob + (stretch - 1.0) * 0.9
		var balance: float = maxf(0.0, -side * lean_z) * 2.2 + absf(lean_x) * 0.8
		var raise := talking * (0.35 * maxf(0.0, brow) + 1.2 * loud) + balance
		var flail := talking * loud * 0.5 * sin(time * 13.0 + side * 1.7)
		shoulder.rotation.z = side * (0.12 + raise + flail)
		shoulder.rotation.x = -0.6 * step * side - 0.3 * angry

	# Mouth: wide line at rest, opens with the jaw, narrows when rounded.
	var width01: float = clampf(face.get("lips", 0.7), 0.0, 1.2)
	var w := HEAD_R * head_sx * MOUTH_W * (0.35 + 0.65 * width01)
	var shut: bool = face.get("shut", false)
	var h: float = 0.0 if shut else 0.42 * face.get("open", 0.0)
	var my: float = MOUTH_Y * head_sy - 0.08 * face.get("open", 0.0)
	mouth.position = Vector3(0, my, surface_z(0, my))
	var key := "%.2f,%.2f,%.2f,%.2f" % [w, h, head_sx, head_sy]
	if key != mouth_key:
		mouth_key = key
		_build_mouth(w, h)

	_update_eyes(dt)
	_update_tongue(dt, face)


# Googly eyes: each pupil rolls about inside the eye under gravity and whatever the eye is
# doing (shaking, swinging), and bounces off the rim.
func _update_eyes(dt: float) -> void:
	var inner := EYE_R * 0.9 - EYE_R * 0.46
	var g_local := head.global_transform.basis.inverse() * Vector3(0, -1, 0)
	for e in eyes:
		var root: Node3D = e["root"]
		var wpos := root.global_position
		var acc_w := Vector3.ZERO
		if e["have_last"]:
			var vel_now: Vector3 = (wpos - e["last"]) / dt
			acc_w = (vel_now - e.get("vel", Vector3.ZERO)) / dt
			e["vel"] = vel_now
		e["last"] = wpos
		e["have_last"] = true
		acc_w = acc_w.limit_length(120.0)
		var inertia := head.global_transform.basis.inverse() * (-acc_w)
		var p: Vector2 = e["p"]
		var v: Vector2 = e["v"]
		var force := Vector2(g_local.x * 28.0 + inertia.x * 0.9, g_local.y * 28.0 + inertia.y * 0.9)
		v += force * dt
		v *= exp(-3.2 * dt)
		p += v * dt
		var d := p.length()
		if d > inner:
			var nrm := p / d
			p = nrm * inner
			var vn := v.dot(nrm)
			if vn > 0.0:
				v -= nrm * vn * 1.6   # bounce
		e["p"] = p
		e["v"] = v
		var pupil: MeshInstance3D = e["pupil"]
		var zc := EYE_R * 0.55 * sqrt(maxf(0.0, 1.0 - (d / (EYE_R * 0.95)) ** 2)) * 0.8
		pupil.position = Vector3(p.x, p.y, zc)


# ------------------------------------------------------------------ tongue

func _update_tongue(dt: float, face: Dictionary) -> void:
	var n := TONGUE_POINTS
	var mouth_xf := mouth.global_transform
	var root := mouth_xf * Vector3(0, -0.05, -0.05)
	var out := (mouth_xf.basis * Vector3(0, -0.4, 1)).normalized()
	var loud: float = face.get("loud", 0.0)
	var talking: float = face.get("talking", 0.0)

	# Length follows how open the mouth is. Coming out it springs and overshoots like
	# elastic; going in it's slurped back.
	var k := smoothstep(TONGUE_OUT_START, TONGUE_OUT_FULL, face.get("open", 0.0))
	var target := 0.02 + TONGUE_MAX_LENGTH * k * (1.0 + 0.15 * loud)
	var sdt: float = minf(dt, 0.05)
	if target >= tongue_length - 0.05:
		tongue_vel += ((target - tongue_length) * TONGUE_LENGTH_SPRING - tongue_vel * TONGUE_LENGTH_DAMPING) * sdt
		tongue_length = maxf(0.02, tongue_length + tongue_vel * sdt)
	else:
		tongue_vel = 0.0
		tongue_length = maxf(target, tongue_length - TONGUE_SLURP * TONGUE_MAX_LENGTH * sdt / 2.6)
	var segment := tongue_length / (n - 1)
	var is_talking := talking > 0.5
	var kick := is_talking and not tongue_was_talking
	tongue_was_talking = is_talking

	if points.size() != n:
		points.clear()
		prev.clear()
		for i in n:
			points.append(root)
			prev.append(root)
		flap_time = 0.0
	var pts := points
	var prv := prev

	# Things to bump into, in world space.
	var head_a := head.to_global(Vector3(0, -HEAD_LEN * head_sy / 2.0, 0))
	var head_b := head.to_global(Vector3(0, HEAD_LEN * head_sy / 2.0, 0))
	var head_r := HEAD_R * (0.5 * head_sx + 0.5 * HEAD_DEPTH) + TONGUE_RADIUS
	var body_a := body.to_global(Vector3(0, -BODY_LEN / 2.0, 0))
	var body_b := body.to_global(Vector3(0, BODY_LEN / 2.0, 0))
	var body_r := BODY_R * body.scale.x + TONGUE_RADIUS

	var side := Vector3(out.z, 0, -out.x).normalized()
	var out01 := smoothstep(0.15, 1.0, tongue_length)
	# A sudden spasm now and then, or a flick when a sound starts.
	if kick or rng.randf() < TONGUE_TWITCH * dt * out01:
		var at := 3 + rng.randi() % (n - 3)
		var shove := Vector3(rng.randf() - 0.5, rng.randf() * 0.8 - 0.15, rng.randf() - 0.5) * 2.0 * ((0.05 if kick else 0.03) * (1.0 + loud))
		if kick:
			shove += out * 0.08
			shove.y += 0.08
		for i in range(2, n):
			var f := exp(-pow((i - at) / 3.0, 2.0))
			prv[i] = prv[i] - shove * f

	tongue_accum = minf(tongue_accum + dt, 0.1)
	while tongue_accum >= TONGUE_STEP:
		tongue_accum -= TONGUE_STEP
		flap_time += TONGUE_STEP
		var h2 := TONGUE_STEP * TONGUE_STEP
		for i in range(2, n):
			var p: Vector3 = pts[i]
			var vv: Vector3 = (p - prv[i]) * TONGUE_DAMPING
			prv[i] = p
			p += vv
			p.y -= TONGUE_GRAVITY * h2
			var tipward := float(i) / n
			var wr := TONGUE_WRITHE * out01 * (0.5 + 0.2 * talking) * tipward
			var sw := sin(flap_time * 5.3 - i * 0.55) + 0.6 * sin(flap_time * 2.1 + i * 0.3)
			var uw := sin(flap_time * 3.7 - i * 0.45 + 1.3)
			p += side * (sw * wr * h2)
			p.y += uw * wr * 0.8 * h2
			if loud > 0.2:
				var wv := sin(flap_time * 23.0 + i * 0.7) * TONGUE_FLAP * loud * tipward
				p.x += out.z * wv * h2
				p.z -= out.x * wv * h2
				p.y += cos(flap_time * 17.0 + i) * TONGUE_FLAP * 0.5 * loud * tipward * h2
			pts[i] = p
		# The mouth holds the first two points.
		pts[0] = root
		pts[1] = root + out * segment
		prv[0] = pts[0]
		prv[1] = pts[1]

		for iter in 8:
			for i in range(2, n):
				var a: Vector3 = pts[i - 1]
				var b: Vector3 = pts[i]
				var d := b - a
				var dist: float = maxf(d.length(), 1e-6)
				var diff := (dist - segment) / dist
				if i == 2:
					pts[i] = b - d * diff
				else:
					pts[i - 1] = a + d * diff * 0.5
					pts[i] = b - d * diff * 0.5
			for i in range(2, n):
				var dir: Vector3
				if i == 2:
					dir = out
				else:
					dir = (pts[i - 1] - pts[i - 2]).normalized()
				var straight: Vector3 = pts[i - 1] + dir * segment
				var amt := TONGUE_ROOT_STIFFNESS if i == 2 else TONGUE_STIFFNESS
				pts[i] = (pts[i] as Vector3).lerp(straight, amt)
			for i in range(3, n):
				var p: Vector3 = pts[i]
				var qh := _closest_on_segment(p, head_a, head_b)
				var dh := p - qh
				var lh := dh.length()
				if lh < head_r:
					p = qh + dh * (head_r / (lh if lh > 0.0 else 1.0))
				var qb := _closest_on_segment(p, body_a, body_b)
				var db := p - qb
				var lb := db.length()
				if lb < body_r:
					p = qb + db * (body_r / (lb if lb > 0.0 else 1.0))
				if p.y < TONGUE_RADIUS * 0.6:
					p.y = TONGUE_RADIUS * 0.6
					var pv: Vector3 = prv[i]
					pv.x += (p.x - pv.x) * 0.3
					pv.z += (p.z - pv.z) * 0.3
					prv[i] = pv
				pts[i] = p

	var visible_now := tongue_length > 0.12
	tongue_mesh.visible = visible_now
	tongue_tip.visible = visible_now
	if not visible_now:
		return
	_draw_tongue(pts)


func _closest_on_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return a + ab * t


func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# A flat, tapered tube along the tongue points, in world space.
func _draw_tongue(pts: Array) -> void:
	var n := pts.size()
	var sub := 2
	var rings := (n - 1) * sub + 1
	var radial := 10
	var centers := PackedVector3Array()
	for i in range(n - 1):
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, n - 1)]
		for j in sub:
			centers.append(_catmull(p0, p1, p2, p3, float(j) / sub))
	centers.append(pts[n - 1])

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var normal := Vector3.UP
	for j in rings:
		var u := float(j) / (rings - 1)
		var c: Vector3 = centers[j]
		var t: Vector3 = (centers[mini(j + 1, rings - 1)] - centers[maxi(j - 1, 0)]).normalized()
		if t.length() < 0.5:
			t = Vector3(0, 0, 1)
		normal = (normal - t * normal.dot(t))
		if normal.length() < 0.01:
			normal = t.cross(Vector3.RIGHT)
		normal = normal.normalized()
		var binormal := t.cross(normal).normalized()
		# Narrow root, fat middle, and lumps that ripple down towards the tip.
		var lump := 1.0 + TONGUE_BULGE * pow(maxf(0.0, sin(u * 14.0 - flap_time * 9.0)), 2.0) * u
		var taper := (0.45 + 0.7 * sin(PI * minf(1.0, u * 1.15))) * lump * lerpf(0.55, 1.0, smoothstep(0.0, 0.2, u))
		var r := TONGUE_RADIUS * taper
		for k in radial:
			var a := float(k) / radial * TAU
			var off := normal * (cos(a) * TONGUE_FLATNESS) + binormal * sin(a)
			verts.append(c + off * r)
			norms.append((normal * (cos(a) / TONGUE_FLATNESS) + binormal * sin(a)).normalized())
	for j in range(rings - 1):
		for k in radial:
			var a0 := j * radial + k
			var a1 := j * radial + (k + 1) % radial
			var b0 := (j + 1) * radial + k
			var b1 := (j + 1) * radial + (k + 1) % radial
			_tris(idx, [a0, a1, b0, a1, b1, b0])
	tongue_mesh.global_transform = Transform3D.IDENTITY
	tongue_mesh.mesh = _array_mesh(verts, norms, idx)
	tongue_tip.global_transform = Transform3D(Basis.from_scale(Vector3(0.75, 0.75 * TONGUE_FLATNESS, 0.75)), pts[n - 1])
