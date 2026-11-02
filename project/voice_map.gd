class_name VoiceMap
## How a frame (one pose of the control pad) sets a synth, and how a synth's settings show on a
## character's face. Shared by your own voice (main.gd) and the song's other voices (song.gd).

const BASE_NOTE := 87.3071 # F2, left edge of the pitch pad
const BASE_MIDI := 41      # ...as a note number (C4 = 60)
const SEMITONES := 24

# The song's voices, low to high: each section in the song gets its own, so the song always
# spans a big low voice to a tiny high one. `sz` sets the size (like the size slider) and
# `shift` moves the pitch pad's range, in semitones.
const VOICES := [
	{"name": "bass", "sz": 0.05, "shift": -10},
	{"name": "baritone", "sz": 0.25, "shift": -5},
	{"name": "tenor", "sz": 0.42, "shift": -1},
	{"name": "alto", "sz": 0.58, "shift": 3},
	{"name": "soprano", "sz": 0.75, "shift": 7},
	{"name": "squeak", "sz": 0.95, "shift": 12},
]

# The song's key: pitches snap to its scale. -1 = no key, 0..11 = C..B major, 12..23 = C..B minor.
const KEY_NAMES := ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
const SCALES := [[0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 8, 10]]
static var key := 0


static func key_name(k: int) -> String:
	if k < 0:
		return "no key"
	return "%s %s" % [KEY_NAMES[k % 12], "minor" if k >= 12 else "major"]


## The pitch for the pitch pad at `px`, moved by `shift` semitones (a voice's range), snapped
## to the nearest note of the song's key.
static func frequency(px: float, shift := 0.0) -> float:
	var semis := SEMITONES * px + shift
	if key >= 0:
		semis = snap(BASE_MIDI + semis) - BASE_MIDI
	return BASE_NOTE * pow(2.0, semis / 12.0)


## The nearest note in the key to `note` (a note number, maybe between notes).
static func snap(note: float) -> float:
	var root := key % 12
	var scale: Array = SCALES[1 if key >= 12 else 0]
	var octave := floorf((note - root) / 12.0) * 12.0 + root
	var best := note
	var gap := INF
	for o in [-12.0, 0.0, 12.0]:
		for d in scale:
			var n: float = octave + o + d
			if absf(n - note) < gap:
				gap = absf(n - note)
				best = n
	return best


static func tenseness(py: float) -> float:
	return 1.0 - cos((1.0 - py) * PI / 2.0) # top = tense, bottom = breathy


static func voice_size(sz: float) -> float:
	return 0.5 * pow(4.0, 1.0 - sz) # slider up = giant (2), middle = 1, down = tiny (0.5)


## Plays one frame on a synth that has no controls on screen. `touching` remembers which of the
## two closure slots are pressed on this synth (an Array of two bools).
## `voice` (an index into VOICES) sets the size and pitch range instead of the frame's size.
static func apply(synth, f: Dictionary, touching: Array, voice := -1) -> void:
	if f.is_empty():
		synth.voice_held = false
		return
	var v: Dictionary = VOICES[voice] if voice >= 0 and voice < VOICES.size() else {}
	synth.frequency = frequency(f["px"], v.get("shift", 0.0))
	synth.tenseness = tenseness(f["py"])
	synth.lips = f["mx"] * 1.4
	synth.jaw = f["my"]
	synth.voice_size = voice_size(v.get("sz", f["sz"]))
	synth.set_tongue(f["ti"], f["td"])
	var cs: Array = f.get("cs", [])
	for slot in 2:
		var id := 3000 + slot
		if slot < cs.size():
			if touching[slot]:
				synth.touch_move(id, cs[slot]["i"], cs[slot]["d"])
			else:
				synth.touch_start(id, cs[slot]["i"], cs[slot]["d"])
				touching[slot] = true
		elif touching[slot]:
			synth.touch_end(id)
			touching[slot] = false
	synth.voice_held = f["voiced"]


## What a character's face should be doing, worked out from a synth's current settings.
static func face(synth) -> Dictionary:
	if synth == null:
		return {}
	var octaves := log(maxf(20.0, synth.frequency) / 140.0) / log(2.0)
	var tense: float = synth.tenseness
	var level: float = synth.get_level()
	var talking := 1.0 if level > 0.008 else 0.0
	var loud := clampf((level - 0.03) / 0.08, 0.0, 1.0) * talking
	var jaw: float = synth.jaw
	var lips: float = synth.lips
	var shut := lips < 0.08
	var low := clampf((synth.get_tongue_diameter() - 2.05) / (3.5 - 2.05), 0.0, 1.0)
	var open := 0.0 if shut else clampf((jaw - 0.25) * 1.6 + 0.25 * low, 0.0, 1.0)
	return {
		"open": open,
		"size": clampf(log(maxf(0.25, synth.voice_size)) / log(2.0), -1.0, 1.0),
		"lips": clampf(lips / 1.4, 0.0, 1.2),
		"jaw": jaw,
		"shut": shut,
		"tilt": clampf(octaves * 0.18, -0.35, 0.35),
		"brow": clampf(octaves * 0.9, -1.0, 1.5),
		"talking": talking,
		"loud": loud,
		"angry": clampf((tense - 0.7) / 0.25, 0.0, 1.0) * loud,
		"sad": clampf((0.45 - tense) / 0.35, 0.0, 1.0) if talking > 0.5 else 0.0,
	}
