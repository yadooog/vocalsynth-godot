class_name World
## The rules of the hub room: its size, where things stand, and how walking slides around
## them. Ported from the web game's shared/world.js (same numbers, so the rooms match).

const WIDTH := 60.0              # world units; the room is centred on (0, 0)
const DEPTH := 44.0
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
]

const STAGE := {"x": -16.0, "z": -9.5, "r": 5.0} # the ~/stage rug: stand here to edit the beat


static func on_stage(x: float, z: float) -> bool:
	return Vector2(x - STAGE["x"], z - STAGE["z"]).length() <= STAGE["r"]


## Inside the booth (past the doorway).
static func in_booth(x: float, z: float) -> bool:
	return x < BOOTH["x"] + BOOTH["w"] / 2.0 - 0.9 and x > BOOTH["x"] - BOOTH["w"] / 2.0 \
		and absf(z - BOOTH["z"]) < BOOTH["d"] / 2.0


static func clamp_to_room(p: Vector2) -> Vector2:
	var hx := WIDTH / 2.0 - PLAYER_RADIUS
	var hz := DEPTH / 2.0 - PLAYER_RADIUS
	return Vector2(clampf(p.x, -hx, hx), clampf(p.y, -hz, hz))


## Push a floor position (x, z as a Vector2) out of anything it overlaps, and inside the walls.
static func resolve(p: Vector2) -> Vector2:
	for pass_i in 2:
		for o in OBSTACLES:
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
