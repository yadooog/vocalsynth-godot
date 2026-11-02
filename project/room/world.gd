class_name World
## The rules of the hub room: its size, where things stand, and how walking slides around
## them. Ported from the web game's shared/world.js (same numbers, so the rooms match).

const WIDTH := 60.0              # the plaza (the old hub room), centred on (0, 0)
const DEPTH := 44.0
const MAP_HX := 110.0            # the whole map: hills all round the plaza, to these half-sizes
const MAP_HZ := 90.0
const WALK_SPEED := 8.0          # units per second
const PLAYER_RADIUS := 0.8       # keeps characters off the walls
const MAX_CLIMB := 1.2           # the highest step you can walk up (the stage's first stair is 1.1)
# sam's Blender models are drawn at twice the game's size: sam's character reference box is
# 7 m tall and the character is 3.5 m. StageShape (made by tools/import_models.py) holds
# their measurements in sam's units.
const MODEL_SCALE := 0.5

# Solid things you walk around. Circles: {shape "circle", x, z, r, kind}.
# Boxes: {shape "box", x, z, w, d, kind} (centred on x, z). `kind` only matters for drawing.
# The stage itself isn't here: it's too tall to step up onto except by its stairs (see step()).
const OBSTACLES := [
	{"shape": "circle", "x": -24.0, "z": -16.0, "r": 1.1, "kind": "tree"},
	{"shape": "circle", "x": 24.0, "z": -16.0, "r": 1.1, "kind": "tree"},
	{"shape": "circle", "x": -24.0, "z": 16.0, "r": 1.1, "kind": "tree"},
	{"shape": "circle", "x": 24.0, "z": 16.0, "r": 1.1, "kind": "tree"},
	{"shape": "circle", "x": -14.0, "z": 17.0, "r": 0.8, "kind": "plant"},
	{"shape": "circle", "x": 14.0, "z": 17.0, "r": 0.8, "kind": "plant"},
	{"shape": "circle", "x": 27.0, "z": 0.0, "r": 0.8, "kind": "plant"},
	{"shape": "circle", "x": -27.0, "z": 0.0, "r": 0.8, "kind": "plant"},
	{"shape": "box", "x": 20.0, "z": 11.0, "w": 1.0, "d": 5.0, "kind": "bench"},
	{"shape": "box", "x": 18.0, "z": -12.0, "w": 2.0, "d": 2.0, "kind": "crate"},
	{"shape": "box", "x": 20.4, "z": -12.6, "w": 2.0, "d": 2.0, "kind": "crate"},
	{"shape": "box", "x": 19.0, "z": -9.8, "w": 2.0, "d": 2.0, "kind": "crate"},
	# Speakers on the big rug, either side of the stage.
	{"shape": "box", "x": -16.5, "z": -1.0, "w": 1.8, "d": 1.5, "kind": "speaker"},
	{"shape": "box", "x": 16.5, "z": -1.0, "w": 1.8, "d": 1.5, "kind": "speaker"},
	# The booth, left of the stage: low walls, open on the side facing the stage.
	{"shape": "box", "x": -27.85, "z": -9.5, "w": 0.3, "d": 4.0, "kind": "booth"},
	{"shape": "box", "x": -26.0, "z": -11.35, "w": 4.0, "d": 0.3, "kind": "booth"},
	{"shape": "box", "x": -26.0, "z": -7.65, "w": 4.0, "d": 0.3, "kind": "booth"},
]

# The booth: step inside to make your section of the song in private.
const BOOTH := {"x": -26.0, "z": -9.5, "w": 4.0, "d": 4.0}
const BOOTH_EXIT := Vector2(-22.6, -9.5)   # where you're put when you walk out
const REVEAL_SPOT := Vector2(0.0, -4.6)    # where you stand for your reveal: front of the stage, at the mic
const MIC := Vector2(0.0, -3.6)
# Where the song's singers stand on the stage: an arc behind the mic.
const SINGER_SPOTS := [Vector2(-10.5, -6.5), Vector2(-7.0, -7.9), Vector2(-3.5, -8.7),
	Vector2(3.5, -8.7), Vector2(7.0, -7.9), Vector2(10.5, -6.5)]

# Rugs: named areas, each one sam's rug model (a raised disc with a bevelled edge) scaled to
# its size. The first is the big one the stage stands on, in the middle of the plaza.
const RUGS := [
	{"x": 0.0, "z": 0.0, "r": StageShape.RUG_R * MODEL_SCALE, "color": Color("#f4eec0"), "name": "~/stage"},
	{"x": 22.5, "z": 14.5, "r": 5.0, "color": Color("#d4f2dc"), "name": "~/quiet corner"},
	{"x": 25.5, "z": -3.0, "r": 4.0, "color": Color("#cdeff6"), "name": "~/crates"},
	{"x": -24.5, "z": 7.0, "r": 5.0, "color": Color("#e2def8"), "name": "~/lounge"},
	# Out in the hills.
	{"x": 0.0, "z": -64.0, "r": 5.0, "color": Color("#f6d9c4"), "name": "~/hilltop"},
	{"x": 64.0, "z": 30.0, "r": 4.5, "color": Color("#cde3f6"), "name": "~/pond"},
	{"x": -76.0, "z": 4.0, "r": 5.0, "color": Color("#d9ecc6"), "name": "~/forest"},
	{"x": 6.0, "z": 62.0, "r": 5.0, "color": Color("#f8e2ef"), "name": "~/meadow"},
	{"x": 70.0, "z": -48.0, "r": 4.0, "color": Color("#efe6c8"), "name": "~/lookout"},
]

# Raised flat-topped hills: {x, z, top (flat radius), base (radius where it meets the ground), h}.
const PLATEAUS := [
	{"x": 0.0, "z": -64.0, "top": 7.5, "base": 30.0, "h": 9.0},     # ~/hilltop
	{"x": 70.0, "z": -48.0, "top": 5.5, "base": 18.0, "h": 13.0},   # ~/lookout: small and steep
	{"x": -40.0, "z": -55.0, "top": 4.0, "base": 20.0, "h": 6.0},
	{"x": 40.0, "z": 70.0, "top": 3.0, "base": 22.0, "h": 5.0},
]
const POND := {"x": 64.0, "z": 16.0, "r": 9.0, "water": 0.4}
const FOREST := {"x": -76.0, "z": 4.0, "r": 26.0, "clearing": 8.0}

const STAGE := {"x": 0.0, "z": -9.0}        # the middle of the stage, where the drums play from


## Height of whatever you'd stand on at (x, z): the ground, a rug or the stage.
static func height(x: float, z: float) -> float:
	var h := ground(x, z)
	# Rugs are raised a little, and the stage stands on the big one.
	for r in RUGS:
		var top := rug_top(r["r"], Vector2(x - r["x"], z - r["z"]).length())
		if top >= 0.0:
			h = maxf(h, rug_height(r) + top)
	return maxf(h, stage_height(x, z))


## The ground itself at (x, z). The plaza is flat at 0; outside it the ground rolls, rises into
## the plateaus, dips at the pond and climbs steeply at the map's edge.
static func ground(x: float, z: float) -> float:
	var out_x := maxf(0.0, absf(x) - WIDTH / 2.0)
	var out_z := maxf(0.0, absf(z) - DEPTH / 2.0)
	var wild := smoothstep(1.0, 14.0, Vector2(out_x, out_z).length())
	var h := 0.0
	# Gentle rolling ground.
	h += 1.2 * sin(x * 0.07 + 1.3) * sin(z * 0.06 + 0.4) + 0.6 * sin(x * 0.13 - z * 0.05 + 2.0)
	h = (h + 1.0) * wild
	for p in PLATEAUS:
		var d := Vector2(x - p["x"], z - p["z"]).length()
		h = maxf(h, p["h"] * (1.0 - smoothstep(p["top"], p["base"], d)))
	var pd := Vector2(x - POND["x"], z - POND["z"]).length()
	h = lerpf(1.0, h, smoothstep(POND["r"], POND["r"] + 8.0, pd))
	h -= 3.0 * (1.0 - smoothstep(POND["r"] - 1.0, POND["r"] + 2.0, pd))
	# The ground is flat under rugs out in the hills.
	for r in RUGS:
		var rd := Vector2(x - r["x"], z - r["z"]).length()
		if rd < r["r"] + 2.0 and Vector2(r["x"], r["z"]).length() > 40.0:
			h = lerpf(_rug_height(r), h, smoothstep(r["r"] + 0.3, r["r"] + 2.0, rd))
	# The edge of the world: steep hills.
	var edge := maxf(absf(x) / MAP_HX, absf(z) / MAP_HZ)
	h += 16.0 * smoothstep(0.82, 1.0, edge)
	return h


## How high a rug's top is, `d` from its middle: flat, then bevelled down at the edge, like
## sam's model (a rug of radius r is the model scaled by r / RUG_R). -1 off the rug.
static func rug_top(r: float, d: float) -> float:
	if d > r:
		return -1.0
	var k := r / StageShape.RUG_R
	var top_r := StageShape.RUG_TOP_R * k
	if d <= top_r:
		return StageShape.RUG_H * k
	return lerpf(StageShape.RUG_H * k, StageShape.RUG_SIDE_H * k, (d - top_r) / (r - top_r))


## The height of the stage's top at (x, z) (its floor, stairs or rim), or -1 off the stage.
static var _stage := PackedFloat32Array()
static func stage_height(x: float, z: float) -> float:
	if _stage.is_empty():
		var raw := Marshalls.base64_to_raw(StageShape.DATA)
		_stage.resize(StageShape.NX * StageShape.NZ)
		for i in _stage.size():
			_stage[i] = raw.decode_u16(i * 2) / 1000.0 * MODEL_SCALE
	var rug: Dictionary = RUGS[0]
	var i := roundi(((x - rug["x"]) / MODEL_SCALE - StageShape.X0) / StageShape.CELL)
	var k := roundi(((z - rug["z"]) / MODEL_SCALE - StageShape.Z0) / StageShape.CELL)
	if i < 0 or k < 0 or i >= StageShape.NX or k >= StageShape.NZ or _stage[k * StageShape.NX + i] <= 0.0:
		return -1.0
	return _stage[k * StageShape.NX + i]


## The height of the stage's floor.
static func deck_y() -> float:
	return StageShape.DECK_Y * MODEL_SCALE


static var _rug_h := {}
static func _rug_height(r: Dictionary) -> float:
	var key: String = r["name"]
	if not _rug_h.has(key):
		_rug_h[key] = 0.0
		var x: float = r["x"]
		var z: float = r["z"]
		var hh := 0.0
		for p in PLATEAUS:
			var d := Vector2(x - p["x"], z - p["z"]).length()
			hh = maxf(hh, p["h"] * (1.0 - smoothstep(p["top"], p["base"], d)))
		_rug_h[key] = hh if hh > 0.5 else 0.6
	return _rug_h[key]


## The height of the ground a rug sits on.
static func rug_height(r: Dictionary) -> float:
	if Vector2(r["x"], r["z"]).length() <= 40.0:
		return 0.0
	return _rug_height(r)


## Everything solid: the plaza's furniture plus the trees and rocks out in the hills.
static var _all: Array = []
static func obstacles() -> Array:
	if _all.is_empty():
		_all = OBSTACLES.duplicate()
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var placed := 0
		var tries := 0
		while placed < 34 and tries < 2000:
			tries += 1
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * FOREST["r"]
			var x: float = FOREST["x"] + cos(a) * d
			var z: float = FOREST["z"] + sin(a) * d * 1.4
			if d < FOREST["clearing"] or not _free(x, z, 3.2):
				continue
			_all.append({"shape": "circle", "x": x, "z": z, "r": 0.7, "kind": "pine", "s": rng.randf_range(0.8, 1.35)})
			placed += 1
		# A few round trees and rocks scattered about the hills.
		placed = 0
		tries = 0
		while placed < 26 and tries < 2000:
			tries += 1
			var x := rng.randf_range(-MAP_HX * 0.8, MAP_HX * 0.8)
			var z := rng.randf_range(-MAP_HZ * 0.8, MAP_HZ * 0.8)
			if absf(x) < WIDTH / 2.0 + 6.0 and absf(z) < DEPTH / 2.0 + 6.0:
				continue
			if Vector2(x - FOREST["x"], z - FOREST["z"]).length() < FOREST["r"] + 6.0 or not _free(x, z, 7.0):
				continue
			var rock := placed % 3 == 0
			_all.append({"shape": "circle", "x": x, "z": z, "r": 1.0 if rock else 0.7, "kind": "rock" if rock else "bush", "s": rng.randf_range(0.8, 1.5)})
			placed += 1
		_all.append({"shape": "circle", "x": POND["x"], "z": POND["z"], "r": POND["r"] - 0.5, "kind": "pond"})
	return _all


## True when (x, z) is clear of rugs, the pond and other obstacles by `gap`.
static func _free(x: float, z: float, gap: float) -> bool:
	for r in RUGS:
		if Vector2(x - r["x"], z - r["z"]).length() < r["r"] + gap:
			return false
	if Vector2(x - POND["x"], z - POND["z"]).length() < POND["r"] + gap:
		return false
	for o in _all:
		if o["shape"] == "circle" and Vector2(x - o["x"], z - o["z"]).length() < gap:
			return false
	return true


## Up on the stage's floor (where you can change the beat).
static func on_stage(x: float, z: float) -> bool:
	return stage_height(x, z) >= deck_y() - 0.3


## Inside the booth (past the doorway).
static func in_booth(x: float, z: float) -> bool:
	return x < BOOTH["x"] + BOOTH["w"] / 2.0 - 0.9 and x > BOOTH["x"] - BOOTH["w"] / 2.0 \
		and absf(z - BOOTH["z"]) < BOOTH["d"] / 2.0


static func clamp_to_room(p: Vector2) -> Vector2:
	var hx := MAP_HX * 0.97
	var hz := MAP_HZ * 0.97
	return Vector2(clampf(p.x, -hx, hx), clampf(p.y, -hz, hz))


## Push a floor position (x, z as a Vector2) out of anything it overlaps, and inside the walls.
static func resolve(p: Vector2) -> Vector2:
	for pass_i in 2:
		for o in obstacles():
			if o["shape"] == "circle":
				var d := p - Vector2(o["x"], o["z"])
				var min_d: float = o["r"] + PLAYER_RADIUS
				var len := d.length()
				if len < min_d:
					p = Vector2(o["x"], o["z"]) + (d / len * min_d if len > 1e-6 else Vector2(min_d, 0))
			else:
				var hx: float = o["w"] / 2.0 + PLAYER_RADIUS
				var hz: float = o["d"] / 2.0 + PLAYER_RADIUS
				var dx: float = p.x - o["x"]
				var dz: float = p.y - o["z"]
				if absf(dx) < hx and absf(dz) < hz:
					if hx - absf(dx) < hz - absf(dz):
						p.x = o["x"] + (signf(dx) if dx != 0.0 else 1.0) * hx
					else:
						p.y = o["z"] + (signf(dz) if dz != 0.0 else 1.0) * hz
		p = clamp_to_room(p)
	return p


## One step of walking: `input` is a direction on the floor (length 0..1). Slides along
## obstacles and walls, and won't climb anything taller than MAX_CLIMB above your feet
## (`foot`: how high your feet are; leave it out to stand on the ground). Returns the new position.
static func step(p: Vector2, input: Vector2, dt: float, foot := NAN) -> Vector2:
	var len := input.length()
	if len < 0.01:
		return p
	# Small sub-steps, so a slow frame can't carry you through a thin wall.
	var move := input / len * minf(1.0, len) * WALK_SPEED * dt
	var n := maxi(1, ceili(move.length() / 0.3))
	var under := height(p.x, p.y)
	var flying := not is_nan(foot) and foot > under + 0.05
	var feet := foot if flying else under
	for i in n:
		var d := move / n
		var q := resolve(p + d)
		if height(q.x, q.y) > feet + MAX_CLIMB:
			# Too tall to step up: slide along it if either way along is clear.
			var along := [resolve(p + Vector2(d.x, 0.0)), resolve(p + Vector2(0.0, d.y))]
			if absf(d.y) > absf(d.x):
				along.reverse()
			q = p
			for a in along:
				if height(a.x, a.y) <= feet + MAX_CLIMB:
					q = a
					break
		p = q
		if not flying:
			feet = height(p.x, p.y)
	return p
