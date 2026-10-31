class_name Phrase
## A phrase is a list of keys {t, ease, f} sorted by time, 4 s long. Each key's `f` is a frame:
## one pose of the controls (see main.gd capture_frame). These helpers play a phrase back
## without any timeline on screen, so the song's other voices can use them too.

const DURATION := 4.0
const NUMBER_FIELDS := ["px", "py", "mx", "my", "sz", "ti", "td"]


## The frame at `time` seconds into the phrase.
static func sample(keys: Array, time: float) -> Dictionary:
	if keys.is_empty():
		return {}
	if time < keys[0]["t"]:
		var f: Dictionary = keys[0]["f"].duplicate()
		f["voiced"] = false # silent before the first key
		return f
	for i in keys.size() - 1:
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		if time < b["t"]:
			var k := ease_k(a["ease"], (time - a["t"]) / maxf(b["t"] - a["t"], 1e-6))
			return blend(a["f"], b["f"], k)
	return (keys[keys.size() - 1]["f"] as Dictionary).duplicate()


static func ease_k(kind: String, k: float) -> float:
	if kind == "hold":
		return 0.0
	if kind == "smooth":
		return k * k * (3.0 - 2.0 * k)
	return k


static func blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var out := a.duplicate()
	for field in NUMBER_FIELDS:
		out[field] = lerpf(a[field], b[field], k)
	# A closure blends when both keys have it; otherwise it stays as it was until the next key.
	var ca: Array = a.get("cs", [])
	var cb: Array = b.get("cs", [])
	var cs: Array = []
	for i in ca.size():
		if i < cb.size():
			cs.append({"i": lerpf(ca[i]["i"], cb[i]["i"], k), "d": lerpf(ca[i]["d"], cb[i]["d"], k)})
		else:
			cs.append(ca[i].duplicate())
	out["cs"] = cs
	return out # voicing switches at the next key
