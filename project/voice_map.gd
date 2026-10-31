class_name VoiceMap
## How a frame (one pose of the control pad) sets a synth, and how a synth's settings show on a
## character's face. Shared by your own voice (main.gd) and the song's other voices (song.gd).

const BASE_NOTE := 87.3071 # F2, left edge of the pitch pad
const SEMITONES := 24


static func frequency(px: float) -> float:
	return BASE_NOTE * pow(2.0, SEMITONES * px / 12.0)


static func tenseness(py: float) -> float:
	return 1.0 - cos((1.0 - py) * PI / 2.0) # top = tense, bottom = breathy


static func voice_size(sz: float) -> float:
	return 0.5 * pow(4.0, 1.0 - sz) # slider up = giant (2), middle = 1, down = tiny (0.5)


## Plays one frame on a synth that has no controls on screen. `touching` remembers which of the
## two closure slots are pressed on this synth (an Array of two bools).
static func apply(synth, f: Dictionary, touching: Array) -> void:
	if f.is_empty():
		synth.voice_held = false
		return
	synth.frequency = frequency(f["px"])
	synth.tenseness = tenseness(f["py"])
	synth.lips = f["mx"] * 1.4
	synth.jaw = f["my"]
	synth.voice_size = voice_size(f["sz"])
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
