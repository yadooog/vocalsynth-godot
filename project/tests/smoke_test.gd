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
		# The panels are laid out like the web game and fit on screen.
		main._layout()
		var screen: Vector2 = main.size
		for card_name in ["PadCard", "ControlsCard", "TimelineCard", "TopBar"]:
			var r: Rect2 = main.get_node("%" + card_name).get_rect()
			if r.position.x < 0 or r.position.y < 0 or r.end.x > screen.x + 1 or r.end.y > screen.y + 1:
				printerr("FAIL: %s is off screen: %s in %s" % [card_name, r, screen])
				ok = false
		if main.get_node("%PadCard").get_rect().intersects(main.get_node("%TimelineCard").get_rect()):
			printerr("FAIL: control pad overlaps the timeline")
			ok = false
		print("ok: layout, control pad at %.2fx" % main.get_node("%Pad").scale.x)
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
		# The booth: walk in, make a phrase, finish, and it joins the song.
		if not World.in_booth(World.BOOTH["x"], World.BOOTH["z"]) or World.in_booth(0.0, 0.0):
			printerr("FAIL: in_booth is wrong")
			ok = false
		character.position = Vector3(World.BOOTH["x"], 0, World.BOOTH["z"])
		main._update_booth(0.1)
		if main.booth_state != "booth":
			printerr("FAIL: walking into the booth did not start a turn (%s)" % main.booth_state)
			ok = false
		var tl = main.get_node("%Timeline")
		tl.add_key(main.capture_frame(true), 0.0)
		tl.add_key(main.capture_frame(true), 2.0)
		main._finish_booth()
		if main.booth_state != "reveal_wait" or main.song.sections.size() != 1:
			printerr("FAIL: finishing in the booth did not add a section (%s, %d)" % [main.booth_state, main.song.sections.size()])
			ok = false
		for i in 20:
			await process_frame
		main.song.set_live(0)
		main.song.update(0.016, 1.0, 1.0, 1.0)
		print("ok: booth adds a section to the song")
		# Say box: words become keys.
		for w in ["hello", "banana", "squelch", "tongues"]:
			if Pronounce.pronounce(w).is_empty():
				printerr("FAIL: could not pronounce %s" % w)
				ok = false
		var said := Speak.text_to_keys("Hello there, how are YOU?", main.capture_frame())
		if said.size() < 10 or said[said.size() - 1]["t"] > Phrase.DURATION:
			printerr("FAIL: say box made %d keys" % said.size())
			ok = false
		main.get_node("%SayText").text = "mama mia!"
		main._say()
		if tl.keys.is_empty() or not tl.playing:
			printerr("FAIL: say box did not play")
			ok = false
		print("ok: say box made %d keys for a sentence" % said.size())
		# Soundboards: save a sound, use it to add a key; save a phrase, load it.
		main.sounds.clear()
		main.phrases.clear()
		main._add_sound(null)
		tl.set_keys([])
		main._use_sound(0)
		if main.sounds.size() != 1 or tl.keys.size() != 1:
			printerr("FAIL: sound board did not add a key (%d sounds, %d keys)" % [main.sounds.size(), tl.keys.size()])
			ok = false
		main._add_phrase(null)
		tl.set_keys([])
		main._use_phrase(0)
		if main.phrases.size() != 1 or tl.keys.size() != 1 or not tl.playing:
			printerr("FAIL: phrase board did not load a phrase")
			ok = false
		main._switch_board()
		main._save_board()
		main._load_board()
		if main.sounds.size() != 1 or main.phrases.size() != 1:
			printerr("FAIL: boards did not save and load")
			ok = false
		main.sounds.clear()
		main.phrases.clear()
		main._save_board()
		print("ok: soundboard")

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
