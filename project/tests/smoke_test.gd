extends SceneTree
## Run by GitHub after each build, to check the engine loads and makes sound:
##   godot --headless --path project -s res://tests/smoke_test.gd

func _initialize() -> void:
	var ok := true
	if not ClassDB.class_exists("PinkTrombone"):
		printerr("FAIL: PinkTrombone class not registered")
		quit(1)
		return

	var synth = ClassDB.instantiate("PinkTrombone")
	synth.setup(48000)
	var sound: PackedFloat32Array = synth.generate(48000)
	ok = _check("open vowel", sound, 0.02) and ok

	synth.set_tongue(14.0, 2.2)
	synth.touch_start(1, 36.0, 0.5)   # "sss" constriction near the teeth
	sound = synth.generate(24000)
	synth.touch_end(1)
	ok = _check("fricative", sound, 0.005) and ok

	synth.touch_start(2, 40.0, -1.2)  # close the lips, open the nose: "mmm"
	sound = synth.generate(24000)
	synth.touch_end(2)
	ok = _check("nasal", sound, 0.001) and ok

	synth.voice_size = 0.5
	ok = _check("tiny voice", synth.generate(24000), 0.01) and ok
	synth.voice_size = 2.0
	ok = _check("giant voice", synth.generate(24000), 0.01) and ok
	synth.voice_size = 1.3
	synth.jaw = 0.9
	synth.lips = 0.5
	ok = _check("odd size, open jaw, round lips", synth.generate(24000), 0.01) and ok
	synth.voice_size = 1.0
	synth.lips = 0.0
	synth.velum_open = true
	synth.generate(24000)
	ok = _check("hum with closed lips", synth.generate(24000), 0.002) and ok

	# The main scene should load and create its synth.
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var voicebox = main.get_node("%Voicebox")
	if main.synth == null or voicebox.synth == null:
		printerr("FAIL: main scene did not create a synth")
		ok = false
	else:
		print("ok: main scene runs")
		for pad_name in ["PitchPad", "MouthPad", "SizeSlider"]:
			if main.get_node("%" + pad_name).moved.get_connections().is_empty():
				printerr("FAIL: %s is not connected to anything" % pad_name)
				ok = false
		var character = main.get_node("%Character")
		if character == null or character.tongue_mesh == null:
			printerr("FAIL: character not built")
			ok = false
		character.walk_to(Vector3(1.0, 0, 0.5))
		# Timeline: two keys, then play across them.
		var timeline = main.get_node("%Timeline")
		timeline.add_key(main.capture_frame(), 0.0)
		var f2: Dictionary = main.capture_frame()
		f2["px"] = 0.9
		timeline.add_key(f2, 1.0)
		var mid: Dictionary = timeline.sample(0.5)
		if timeline.keys.size() != 2 or absf(mid["px"] - (main.capture_frame()["px"] + 0.9) * 0.5) > 0.2:
			printerr("FAIL: timeline keys or blending wrong")
			ok = false
		timeline.play()
		for i in 10:
			await process_frame
		timeline.stop()
		print("ok: timeline plays")
		var t0: float = main.synth.get_time()
		for i in 30:
			await process_frame
		print("info: audio thread advanced the synth by %.3f s" % (main.synth.get_time() - t0))
		print("info: character walked to x=%.2f, head width %.2f height %.2f" % [character.position.x, character.head_sx, character.head_sy])
		print("ok: character runs")

	quit(0 if ok else 1)


func _check(label: String, sound: PackedFloat32Array, min_rms: float) -> bool:
	var sum := 0.0
	for v in sound:
		if is_nan(v) or is_inf(v):
			printerr("FAIL: %s produced NaN/inf" % label)
			return false
		sum += v * v
	var rms := sqrt(sum / sound.size())
	if rms < min_rms or rms > 1.0:
		printerr("FAIL: %s rms %.4f" % [label, rms])
		return false
	print("ok: %s rms %.4f" % [label, rms])
	return true
