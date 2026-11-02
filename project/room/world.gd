class_name World
## The rules of the hub room: its size, where things stand, and how walking slides around
## them. Ported from the web game's shared/world.js (same numbers, so the rooms match).

const WIDTH := 60.0              # the plaza (the old hub room), centred on (0, 0)
const DEPTH := 44.0
const MAP_HX := 110.0            # the whole map: hills all round the plaza, to these half-sizes
const MAP_HZ := 90.0
const WALK_SPEED := 8.0          # units per second
const PLAYER_RADIUS := 0.8       # keeps characters off the walls

# Solid things you walk around. Circles: {shape "circle", x, z, r, kind}.
# Boxes: {shape "box", x, z, w, d, kind} (centred on x, z). `kind` only matters for drawing.
const OBSTACLES := [
	{"shape": "circle", "x": -9.0, "z": -7.0, "r": 0.9, "kind": "column"},
	{"shape": "circle", "x": 9.0, "z": -7.0, "r": 0.9, "kind": "column"},
	{"shape": "circle", "x": -9.0, "z": 7.0, "r": 0.9, "kind": "column"},
	{"shape": "circle", "x": 9.0, "z": 7.0, "r": 0.9, "kind": "column"},
	{"shape": "circle", "x": 0.0, "z": 0.0, "r": 1.6, "kind": "planter"},
	{"shape": "circle", "x": -24.0, "z": -16.0, "r": 1.1, "kind": "tree"},
	{"shape": "circle", "x": 24.0, "z": -16.0, "r": 1.1, "kind": "tree"},
	{"shape": "circle", "x": -24.0, "z": 16.0, "r": 1.1, "kind": "tree"},
	{"shape": "circle", "x": 24.0, "z": 16.0, "r": 1.1, "kind": "tree"},
	{"shape": "circle", "x": 0.0, "z": -18.0, "r": 1.1, "kind": "tree"},
	{"shape": "circle", "x": -14.0, "z": 17.0, "r": 0.8, "kind": "plant"},
	{"shape": "circle", "x": 14.0, "z": 17.0, "r": 0.8, "kind": "plant"},
	{"shape": "circle", "x": 27.0, "z": 0.0, "r": 0.8, "kind": "plant"},
	{"shape": "circle", "x": -27.0, "z": 0.0, "r": 0.8, "kind": "plant"},
	{"shape": "box", "x": -20.0, "z": -5.0, "w": 5.0, "d": 1.0, "kind": "bench"},
	{"shape": "box", "x": -12.0, "z": -5.0, "w": 5.0, "d": 1.0, "kind": "bench"},
	{"shape": "box", "x": 20.0, "z": 11.0, "w": 1.0, "d": 5.0, "kind": "bench"},
	{"shape": "box", "x": -16.0, "z": -15.0, "w": 10.0, "d": 4.0, "kind": "stage"},
	{"shape": "box", "x": 18.0, "z": -12.0, "w": 2.0, "d": 2.0, "kind": "crate"},
	{"shape": "box", "x": 20.4, "z": -12.6, "w": 2.0, "d": 2.0, "kind": "crate"},
	{"shape": "box", "x": 19.0, "z": -9.8, "w": 2.0, "d": 2.0, "kind": "crate"},
	{"shape": "box", "x": 6.0, "z": 15.0, "w": 8.0, "d": 1.6, "kind": "table"},
	# The booth, left of the stage: low walls, open on the side facing the stage.
	{"shape": "box", "x": -27.85, "z": -9.5, "w": 0.3, "d": 4.0, "kind": "booth"},
	{"shape": "box", "x": -26.0, "z": -11.35, "w": 4.0, "d": 0.3, "kind": "booth"},
	{"shape": "box", "x": -26.0, "z": -7.65, "w": 4.0, "d": 0.3, "kind": "booth"},
]

# The booth: step inside to make your section of the song in private.
const BOOTH := {"x": -26.0, "z": -9.5, "w": 4.0, "d": 4.0}
const BOOTH_EXIT := Vector2(-22.6, -9.5)   # where you're put when you walk out
const REVEAL_SPOT := Vector2(-16.0, -11.2) # where you stand for your reveal, in front of the mic

# Rugs: flat, walkable, named areas.
const RUGS := [
	{"x": 0.0, "z": 0.0, "r": 6.0, "color": Color("#f2cfee"), "name": "~/middle"},
	{"x": -16.0, "z": -9.5, "r": 5.0, "color": Color("#f4eec0"), "name": "~/stage"},
	{"x": 21.0, "z": 14.0, "r": 5.0, "color": Color("#d4f2dc"), "name": "~/quiet corner"},
	{"x": 18.0, "z": -4.0, "r": 4.0, "color": Color("#cdeff6"), "name": "~/crates"},
	{"x": -18.0, "z": 11.0, "r": 5.0, "color": Color("#e2def8"), "name": "~/lounge"},
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

const STAGE := {"x": -16.0, "z": -9.5, "r": 5.0} # the ~/stage rug: stand here to edit the beat


## Ground height at (x, z). The plaza is flat at 0; outside it the ground rolls, rises into
## the plateaus, dips at the pond and climbs steeply at the map's edge.
static func height(x: float, z: float) -> float:
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
	# Rugs sit flat.
	for r in RUGS:
		var rd := Vector2(x - r["x"], z - r["z"]).length()
		if rd < r["r"] + 2.0 and Vector2(r["x"], r["z"]).length() > 40.0:
			h = lerpf(_rug_height(r), h, smoothstep(r["r"] + 0.3, r["r"] + 2.0, rd))
	# The edge of the world: steep hills.
	var edge := maxf(absf(x) / MAP_HX, absf(z) / MAP_HZ)
	h += 16.0 * smoothstep(0.82, 1.0, edge)
	return h


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


## The height a rug is drawn at.
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


static func on_stage(x: float, z: float) -> bool:
	return Vector2(x - STAGE["x"], z - STAGE["z"]).length() <= STAGE["r"]


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
## obstacles and walls. Returns the new position.
static func step(p: Vector2, input: Vector2, dt: float) -> Vector2:
	var len := input.length()
	if len < 0.01:
		return p
	return resolve(p + input / len * minf(1.0, len) * WALK_SPEED * dt)
