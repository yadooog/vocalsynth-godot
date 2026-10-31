class_name Speak
## Typed text to a phrase: words -> sounds (Pronounce) -> timed mouth targets -> keys.
## Ported from the web game's shared/speak.js. It's wrong but recognisable, on purpose.
## Stressed syllables are longer and higher, the pitch drifts down through a sentence,
## "?" rises at the end, "!" and CAPITALS are louder and higher, commas pause.

# Vowel targets: tongue position, plus lip rounding (a closure at the lips) for o/u sounds.
const VT := {
	"AA": {"ti": 12.9, "td": 2.43},              # father
	"AE": {"ti": 14.9, "td": 2.78},              # cat
	"AH": {"ti": 17.8, "td": 2.46},              # cup
	"AX": {"ti": 20.7, "td": 2.8},               # the unstressed "uh"
	"AO": {"ti": 14.0, "td": 2.05, "lips": 1.0}, # thought
	"EH": {"ti": 19.4, "td": 3.43},              # bed
	"ER": {"ti": 20.7, "td": 2.8, "r": true},    # bird
	"IH": {"ti": 26.1, "td": 2.87},              # bit
	"IY": {"ti": 27.2, "td": 2.2},               # bee
	"UH": {"ti": 21.0, "td": 2.4, "lips": 1.1},  # book
	"UW": {"ti": 22.8, "td": 2.05, "lips": 0.75},# boot
	"OW": {"ti": 17.7, "td": 2.05, "lips": 1.0}, # start of go
}
# Diphthongs glide from one vowel to another.
const DIPH := {"AY": ["AA", "IY"], "EY": ["EH", "IY"], "OW": ["OW", "UW"], "AW": ["AA", "UW"], "OY": ["AO", "IY"]}

# Consonants: where the tract closes (41 lips, 36 teeth ridge, 31 roof, 18 back), how much
# (0 shut, ~0.6 hiss, below 0 through the nose) and whether the voice is on.
const CT := {
	"B": {"kind": "stop", "index": 41, "d": 0.0, "voiced": true},
	"P": {"kind": "stop", "index": 41, "d": 0.0, "voiced": false},
	"D": {"kind": "stop", "index": 36, "d": 0.0, "voiced": true},
	"T": {"kind": "stop", "index": 36, "d": 0.0, "voiced": false},
	"G": {"kind": "stop", "index": 18, "d": 0.0, "voiced": true},
	"K": {"kind": "stop", "index": 18, "d": 0.0, "voiced": false},
	"M": {"kind": "nasal", "index": 41, "d": -1.0, "voiced": true},
	"N": {"kind": "nasal", "index": 36, "d": -1.0, "voiced": true},
	"NG": {"kind": "nasal", "index": 18, "d": -1.0, "voiced": true},
	"F": {"kind": "fric", "index": 41, "d": 0.5, "voiced": false},
	"V": {"kind": "fric", "index": 41, "d": 0.55, "voiced": true},
	"TH": {"kind": "fric", "index": 38.5, "d": 0.6, "voiced": false},
	"DH": {"kind": "fric", "index": 38.5, "d": 0.65, "voiced": true},
	"S": {"kind": "fric", "index": 36, "d": 0.55, "voiced": false},
	"Z": {"kind": "fric", "index": 36, "d": 0.6, "voiced": true},
	"SH": {"kind": "fric", "index": 31, "d": 0.6, "voiced": false, "lips": 1.2},
	"ZH": {"kind": "fric", "index": 31, "d": 0.65, "voiced": true, "lips": 1.2},
	"L": {"kind": "approx", "index": 35, "d": 0.85, "voiced": true},
	"R": {"kind": "approx", "index": 29, "d": 1.1, "voiced": true, "tongue": {"ti": 18.0, "td": 2.6}, "lips": 1.2},
	"W": {"kind": "approx", "index": 41, "d": 0.55, "voiced": true, "tongue": {"ti": 22.8, "td": 2.05}},
	"Y": {"kind": "approx", "index": 30, "d": 0.95, "voiced": true, "tongue": {"ti": 27.2, "td": 2.2}},
	"HH": {"kind": "breath"},
	"CH": {"kind": "affricate", "parts": ["T", "SH"]},
	"JH": {"kind": "affricate", "parts": ["D", "ZH"]},
}

# Seconds. Stressed vowels are long, unstressed ones short.
const DUR := {"stressed": 0.17, "secondary": 0.12, "unstressed": 0.08, "diphthong_extra": 0.05,
	"stop": 0.065, "aspiration": 0.045, "nasal": 0.075, "fric_voiceless": 0.11, "fric_voiced": 0.08,
	"approx": 0.065, "breath": 0.07, "comma": 0.16, "final_lengthen": 1.35}

const NEUTRAL_MX := 0.714 # lips pad: relaxed
const NEUTRAL_MY := 0.5   # jaw: half open


static func _tokens(text: String) -> Array:
	var re := RegEx.new()
	re.compile("([A-Za-z0-9']+)|([,;:]+)|([.!?]+)")
	var out: Array = []
	for m in re.search_all(text):
		var w := m.get_string(1)
		if w != "":
			out.append({"word": w, "shout": w.length() > 1 and w == w.to_upper() and w != w.to_lower()})
		elif m.get_string(2) != "":
			out.append({"pause": DUR["comma"]})
	return out


## Turns text into timeline keys [{t, ease, f}]. `base` is a frame from the controls: its
## pitch and size are kept. Returns [] if there's nothing to say.
static func text_to_keys(text: String, base: Dictionary) -> Array:
	var base_pitch := clampf(VoiceMap.frequency(base.get("px", 0.34)), 80.0, 260.0)
	var question := text.strip_edges().ends_with("?")
	var excited := text.contains("!")

	# 1. A flat list of sounds, each knowing its word and stress.
	var segs: Array = []
	var words := 0
	for tok in _tokens(text):
		if tok.has("pause"):
			segs.append({"pause": tok["pause"]})
			continue
		for ph in Pronounce.pronounce(tok["word"]):
			var stress = null
			var name: String = ph
			if Pronounce.is_vowel(ph):
				stress = int(ph.right(1))
				name = ph.left(ph.length() - 1)
			if name == "AH" and stress == 0:
				name = "AX"
			segs.append({"ph": name, "stress": stress, "word": words, "shout": tok["shout"]})
		words += 1
	if not segs.any(func(s): return s.has("ph")):
		return []

	# The last stressed vowel carries the end-of-sentence tune.
	var vowel_idx: Array = []
	for i in segs.size():
		if segs[i].get("stress") != null:
			vowel_idx.append(i)
	var last_stressed: int = vowel_idx[vowel_idx.size() - 1] if not vowel_idx.is_empty() else -1
	for i in range(vowel_idx.size() - 1, -1, -1):
		if segs[vowel_idx[i]]["stress"] == 1:
			last_stressed = vowel_idx[i]
			break

	# 2. Pitch and tension for every vowel; consonants borrow from the next vowel.
	var tail: Array = vowel_idx.filter(func(j): return j >= last_stressed)
	for i in vowel_idx:
		var s: Dictionary = segs[i]
		var k: float = float(s["word"]) / (words - 1) if words > 1 else 0.0
		var f := base_pitch * (1.08 - 0.16 * k)
		if s["stress"] == 1:
			f *= 1.12
		if i == vowel_idx[0] and s["stress"] == 1:
			f *= 1.05
		if i >= last_stressed:
			var after := tail.find(i)
			f = base_pitch * (1.25 + 0.3 * after) if question else f * (0.92 - 0.06 * after)
		if excited:
			f *= 1.18
		if s["shout"]:
			f *= 1.3
		s["pitch"] = f
		s["tense"] = 0.85 if s["shout"] or excited else 0.68
	var fill = null
	for i in range(segs.size() - 1, -1, -1):
		if segs[i].has("pitch"):
			fill = segs[i]
		elif fill != null and not segs[i].has("pause"):
			segs[i]["pitch"] = fill["pitch"]
			segs[i]["tense"] = fill["tense"]
	for s in segs:
		if not s.has("pause") and not s.has("pitch"):
			s["pitch"] = base_pitch * 0.9
			s["tense"] = 0.68

	# 3. Mouth targets and keys, in time.
	var keys: Array = []
	var t := 0.0
	var last_vowel: int = vowel_idx[vowel_idx.size() - 1] if not vowel_idx.is_empty() else -1
	var sz: float = base.get("sz", 0.5)
	for i in segs.size():
		var s: Dictionary = segs[i]
		if s.has("pause"):
			var pf := _frame(VT["AX"], [], s.get("pitch", base_pitch), 0.6, false, sz)
			keys.append({"t": t, "ease": "linear", "f": pf})
			t += s["pause"]
			continue
		var ph: String = s["ph"]
		if VT.has(ph) or DIPH.has(ph):
			var dur: float = DUR["stressed"] if s["stress"] == 1 else (DUR["secondary"] if s["stress"] == 2 else DUR["unstressed"])
			if DIPH.has(ph):
				dur += DUR["diphthong_extra"]
			if i == last_vowel:
				dur *= DUR["final_lengthen"]
			if s["shout"]:
				dur *= 1.25
			var a: String = DIPH[ph][0] if DIPH.has(ph) else ph
			var b: String = DIPH[ph][1] if DIPH.has(ph) else ph
			keys.append({"t": t, "ease": "smooth", "f": _vowel(a, s["pitch"], s["tense"], sz)})
			if a != b:
				keys.append({"t": t + dur * 0.45, "ease": "smooth", "f": _vowel(b, s["pitch"], s["tense"], sz)})
			keys.append({"t": t + dur * 0.8, "ease": "smooth", "f": _vowel(b, s["pitch"] * 0.99, s["tense"], sz)})
			t += dur
			continue
		if not CT.has(ph):
			continue
		var c: Dictionary = CT[ph]
		var tongue: Dictionary = c.get("tongue", _tongue_at(segs, i))
		var parts: Array = [c] if c["kind"] != "affricate" else c["parts"].map(func(p): return CT[p])
		for part in parts:
			if part["kind"] == "breath":
				keys.append({"t": t, "ease": "smooth", "f": _frame(_tongue_at(segs, i), [], s["pitch"], 0.02, true, sz)})
				t += DUR["breath"]
				continue
			var closure: Array = [{"i": float(part["index"]), "d": part["d"]}]
			if part.has("lips"):
				closure.append({"i": 42.0, "d": part["lips"]})
			var voiced: bool = part["voiced"]
			var frame := _frame(tongue, closure, s["pitch"], s["tense"] if voiced else 0.02, voiced, sz)
			if part["kind"] == "stop":
				keys.append({"t": t, "ease": "hold", "f": frame})
				t += 0.05 if c["kind"] == "affricate" else DUR["stop"]
				if not voiced and c["kind"] != "affricate":
					# A puff of air after p, t, k before the voice starts.
					keys.append({"t": t, "ease": "linear", "f": _frame(_tongue_at(segs, i), [], s["pitch"], 0.02, true, sz)})
					t += DUR["aspiration"]
			else:
				var dur: float
				match part["kind"]:
					"nasal":
						dur = DUR["nasal"]
					"approx":
						dur = DUR["approx"]
					_:
						dur = DUR["fric_voiced"] if voiced else DUR["fric_voiceless"]
				keys.append({"t": t, "ease": "smooth", "f": frame})
				if part["kind"] != "approx":
					keys.append({"t": t + dur * 0.75, "ease": "smooth", "f": frame.duplicate(true)})
				t += dur

	# End quietly.
	var last: Dictionary = (keys[keys.size() - 1]["f"] as Dictionary).duplicate(true)
	last["cs"] = []
	last["voiced"] = false
	keys.append({"t": t + 0.05, "ease": "linear", "f": last})

	# Too long? Squeeze it into the 4 seconds a phrase can have.
	var end: float = keys[keys.size() - 1]["t"]
	var fit := Phrase.DURATION - 0.05
	if end > fit:
		for key in keys:
			key["t"] *= fit / end
	keys.sort_custom(func(x, y): return x["t"] < y["t"])
	for key in keys:
		key["t"] = snappedf(key["t"], 0.001)
	return keys


# Consonants take the tongue shape of the nearest vowel (the next one first).
static func _tongue_at(segs: Array, i: int) -> Dictionary:
	for j in range(i + 1, segs.size()):
		if segs[j].has("pause"):
			break
		if VT.has(segs[j].get("ph", "")) or DIPH.has(segs[j].get("ph", "")):
			return _vowel_target(segs[j]["ph"], 0)
	for j in range(i - 1, -1, -1):
		if segs[j].has("pause"):
			break
		if VT.has(segs[j].get("ph", "")) or DIPH.has(segs[j].get("ph", "")):
			return _vowel_target(segs[j]["ph"], 1)
	return VT["AX"]


static func _vowel_target(ph: String, end: int) -> Dictionary:
	return VT[DIPH[ph][end]] if DIPH.has(ph) else VT.get(ph, VT["AX"])


static func _vowel(ph: String, pitch: float, tense: float, sz: float) -> Dictionary:
	var v: Dictionary = VT[ph]
	var cs: Array = []
	if v.has("lips"):
		cs.append({"i": 42.0, "d": v["lips"]})
	if v.get("r", false):
		cs.append({"i": 29.0, "d": 1.1})
	return _frame(v, cs, pitch, tense, true, sz)


# A frame in the control pad's terms.
static func _frame(v: Dictionary, cs: Array, frequency: float, tenseness: float, voiced: bool, sz: float) -> Dictionary:
	var semis := 12.0 * log(frequency / VoiceMap.BASE_NOTE) / log(2.0)
	return {
		"px": clampf(semis / VoiceMap.SEMITONES, 0.0, 1.0),
		"py": clampf(1.0 - acos(clampf(1.0 - tenseness, -1.0, 1.0)) * 2.0 / PI, 0.0, 1.0),
		"mx": NEUTRAL_MX, "my": NEUTRAL_MY, "sz": sz,
		"ti": v["ti"], "td": v["td"],
		"voiced": voiced,
		"cs": cs.slice(0, 2),
	}
