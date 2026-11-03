extends Node
## Online play: one shared room over a WebSocket to the game's server (server/godot.js in the
## vocalcordgame repo). Sends where you are and the sound you're making; shows and plays
## everyone else. The booth, the song and the beat are shared. If the server can't be reached
## the game just carries on offline. Rounds (a game) are run by the server: `game` is its
## latest word on them (server/godot_game.js), and game_card.gd shows it.

signal game_changed

const DEFAULT_URL := "wss://vocalcordgame.onrender.com/godot-ws"
const SEND_EVERY := 1.0 / 15.0
const PING_EVERY := 2.0
const HEARING_FULL := 4.0
const HEARING_SILENT := 30.0

var main: Control
var ws := WebSocketPeer.new()
var connected := false
var you := ""                  # our id in the room
var my_name := ""
var game := {"phase": "free"}  # the round: phase (free, brief, build, vote, results), brief, turn...
var others := {}               # id -> {name, node, synth, player, touching, target, ry, f}
var booth_owner = null         # id of who's in the booth, or null
var _send_left := 0.0
var _ping_left := 0.0
var _last_sent := {}
var _was_voiced := false
var _offset := 0.0             # server clock minus our clock
var _best_rtt := 1e9           # the quickest ping lately: its clock reading is the most exact
var _have_clock := false
var _tried := false
var _retry_left := 0.0
var _debug_left := 0.0
var _retry_wait := 3.0
var _character_script := preload("res://character/character.gd")


func url() -> String:
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("location.search"))
		var m := RegEx.create_from_string("server=([^&]+)").search(q)
		if m:
			return m.get_string(1).uri_decode()
		var proto := str(JavaScriptBridge.eval("location.protocol"))
		var host := str(JavaScriptBridge.eval("location.host"))
		if host.contains("onrender.com") or host.begins_with("localhost:81"):
			return ("wss://" if proto == "https:" else "ws://") + host + "/godot-ws"
	return DEFAULT_URL


func _ready() -> void:
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		return # tests run offline
	_roomy(ws)
	ws.connect_to_url(url())
	_tried = true
	main.beats.edited.connect(_on_beat_edited)


## For browser tests: a little of the game's state, readable as window.__game.
func _write_debug() -> void:
	var d := {"online": connected, "you": you, "others": others.size(), "booth": main.booth_state,
		"phase": phase(), "turn": game.get("turn"), "brief": game.get("brief", ""), "round": game.get("round", 0),
		"bar": main.booth_title.text if main.booth_bar.visible else "", "spot": main.spotlight.visible,
		"listen": main.listen, "card": main.game_card.visible if main.game_card else false,
		"booth_owner": booth_owner, "song": main.song.sections.size(),
		"live": main.song.sections.map(func(x): return x["live"]),
		"remote_reveal": main.remote_reveal, "loop": main.beats.loop_index(),
		"clock": snappedf(main.beats.clock, 0.01), "pos": [snappedf(main.character.position.x, 0.1), snappedf(main.character.position.z, 0.1)]}
	var ui: Dictionary = main.game_card.test_points() if main.game_card else {}
	if main.round_button and main.round_button.is_visible_in_tree():
		var r: Rect2 = main.round_button.get_global_rect()
		ui["round"] = [roundi(r.get_center().x), roundi(r.get_center().y)]
	d["ui"] = ui
	JavaScriptBridge.eval("window.__game = " + JSON.stringify(d) + ";")


## Room for a busy room's messages to pile up between frames (the defaults overflow with ~20
## players on a slow computer).
static func _roomy(peer: WebSocketPeer) -> void:
	peer.inbound_buffer_size = 1 << 20
	peer.outbound_buffer_size = 1 << 18
	peer.max_queued_packets = 16384


static func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func is_online() -> bool:
	return connected


func _process(delta: float) -> void:
	if not _tried:
		return
	ws.poll()
	var state := ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while ws.get_available_packet_count() > 0:
			var data = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if data is Dictionary:
				_on_message(data)
		_send_left -= delta
		if _send_left <= 0.0:
			_send_left = SEND_EVERY
			_send_state()
		_ping_left -= delta
		if _ping_left <= 0.0:
			_ping_left = PING_EVERY
			_send({"t": "ping", "c": _now()})
	elif state == WebSocketPeer.STATE_CLOSED:
		if connected:
			connected = false
			_have_clock = false
			for id in others.keys():
				_remove(id)
			booth_owner = null
			main.room.set_booth_busy(false)
			game = {"phase": "free"}
			game_changed.emit()
		# Try again now and then, waiting longer each time.
		_retry_left -= delta
		if _retry_left <= 0.0:
			_retry_left = _retry_wait
			_retry_wait = minf(_retry_wait * 2.0, 60.0)
			ws = WebSocketPeer.new()
			_roomy(ws)
			ws.connect_to_url(url())
	_update_others(delta)
	_debug_left -= delta
	if _debug_left <= 0.0 and OS.has_feature("web"):
		_debug_left = 0.5
		_write_debug()


func _send(msg: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))


func _send_state() -> void:
	var c: Node3D = main.character
	var move := {"t": "move", "x": snappedf(c.position.x, 0.01), "y": snappedf(c.position.y, 0.01),
		"z": snappedf(c.position.z, 0.01), "ry": snappedf(c.rotation.y, 0.01)}
	if move != _last_sent:
		_last_sent = move
		_send(move)
	var voiced: bool = main.synth != null and main.synth.voice_held
	if voiced:
		_send({"t": "voice", "f": main.capture_frame()})
	elif _was_voiced:
		_send({"t": "voice", "f": null})
	_was_voiced = voiced


# ---------------------------------------------------------------- messages

func _on_message(m: Dictionary) -> void:
	match m.get("t"):
		"welcome":
			connected = true
			_retry_wait = 3.0
			you = m["you"]["id"]
			my_name = m["you"]["name"]
			for p in m["players"]:
				_add(p)
			main.song.clear()
			for s in m["song"]:
				_add_section(s, true)
			booth_owner = m["booth"]
			main.room.set_booth_busy(booth_owner != null)
			main.beats.pattern = m["pattern"]
			main.show_key(int(m.get("key", VoiceMap.key)))
			_offset = float(m["clock"]) - _now()
			main.beats.sync_offset(_offset, true)
			_have_clock = true
			_best_rtt = 1e9
			_ping_left = 0.0 # measure the round trip straight away
			game = m.get("game", {"phase": "free"})
			game_changed.emit()
		"joined":
			if others.has(m["p"]["id"]):
				others[m["p"]["id"]]["name"] = m["p"]["name"]
			else:
				_add(m["p"])
		"left":
			_remove(m["id"])
		"moved":
			var o = others.get(m["id"])
			if o:
				o["target"] = Vector3(m["x"], m["y"], m["z"])
				o["ry"] = float(m["ry"])
		"moves": # everyone who moved lately, in one message: [id, x, y, z, ry] each
			for e in m["m"]:
				var o = others.get(e[0])
				if o:
					o["target"] = Vector3(e[1], e[2], e[3])
					o["ry"] = float(e[4])
		"voice":
			var o = others.get(m["id"])
			if o:
				o["f"] = m["f"] if m["f"] is Dictionary else {}
		"booth":
			booth_owner = m["id"]
			main.room.set_booth_busy(booth_owner != null)
		"section":
			if m["owner"] != you:
				_add_section(m, false)
		"song-clear":
			main.song.clear()
			main.end_remote_reveal()
		"song":
			main.replace_song(m["sections"])
		"game":
			game = m
			game_changed.emit()
		"beat":
			main.beats.pattern = m["pattern"]
		"key":
			main.show_key(int(m["k"]))
		"react":
			if main.crowd:
				main.crowd.react(str(m["id"]), str(m["r"]))
		"pong":
			# Half the round trip has passed since the server read its clock. Trust the
			# quickest round trips most (slow ones were held up somewhere).
			var now := _now()
			var rtt := now - float(m["c"])
			_best_rtt += 0.02
			if rtt <= _best_rtt:
				_best_rtt = rtt
				_offset = float(m["clock"]) + rtt * 0.5 - now
				main.beats.sync_offset(_offset)


func _add_section(s: Dictionary, quiet: bool) -> void:
	var i: int = main.song.add_section(s["keys"], str(s.get("owner", "")), str(s.get("name", "")), int(s.get("voice", -1)))
	if i < 0:
		return
	if quiet:
		main.song.set_live(i)
	else:
		main.reveal_remote(i, str(s.get("name", "someone")))


# ---------------------------------------------------------------- what we tell the room

func enter_booth() -> bool:
	if not connected:
		return true
	if booth_owner != null and booth_owner != you:
		return false
	booth_owner = you
	_send({"t": "booth-enter"})
	return true


func leave_booth() -> void:
	if connected and booth_owner == you:
		booth_owner = null
		_send({"t": "booth-leave"})


func booth_taken() -> bool:
	return connected and booth_owner != null and booth_owner != you


func booth_owner_name() -> String:
	var o = others.get(booth_owner)
	return o["name"] if o else "someone"


func add_section(keys: Array, voice: int) -> void:
	if connected:
		_send({"t": "section", "keys": keys, "voice": voice})


## Cheer or throw a tomato at whoever's on stage.
func react(kind: String, at: int) -> void:
	_send({"t": "react", "r": kind, "at": at})


## Sets the song's key for everyone (VoiceMap.key).
func set_key(k: int) -> void:
	VoiceMap.key = k
	if connected:
		_send({"t": "key", "k": k})


func clear_song() -> void:
	if connected:
		_send({"t": "song-clear"})


func _on_beat_edited(drum: int, step: int) -> void:
	if not connected:
		return
	if drum < 0:
		_send({"t": "beat-clear"})
	else:
		_send({"t": "beat-toggle", "drum": drum, "step": step})


func count() -> int:
	return others.size() + 1


# ---------------------------------------------------------------- rounds

func phase() -> String:
	return str(game.get("phase", "free")) if connected else "free"


func in_game() -> bool:
	return phase() != "free"


func my_turn() -> bool:
	return phase() == "build" and game.get("turn") == you


## "you" for us, else the name the server gave.
func name_of(id, fallback := "someone") -> String:
	if id == null:
		return fallback
	if id == you:
		return "you"
	var o = others.get(id)
	return o["name"] if o else fallback


## Why you can't go in the booth right now, or "" if you can.
func booth_refusal() -> String:
	if booth_taken():
		return "%s is in the booth" % booth_owner_name()
	match phase():
		"brief":
			return "wait for the brief"
		"build":
			return "" if my_turn() else "it's %s's turn" % name_of(game.get("turn"), str(game.get("turnName", "someone")))
		"vote":
			return "voting now"
		"results":
			return "next round soon"
	return ""


## Seconds left in this part of the round, on the room's clock.
func time_left() -> float:
	return maxf(0.0, float(game.get("ends", 0.0)) - main.beats.clock)


func start_game() -> void:
	_send({"t": "game-start"})


func stop_game() -> void:
	_send({"t": "game-stop"})


func send_brief(text: String) -> void:
	_send({"t": "brief", "text": text})


func vote(i: int) -> void:
	_send({"t": "vote", "i": i})


# ---------------------------------------------------------------- everyone else

func _add(p: Dictionary) -> void:
	var id: String = p["id"]
	if id == you or others.has(id):
		return
	var node: Node3D = _character_script.new()
	var c := int(p.get("color", 0))
	node.head_color = main.song.HEADS[c % main.song.HEADS.size()]
	node.outfit_color = main.song.OUTFITS[c % main.song.OUTFITS.size()]
	node.position = Vector3(p["x"], p["y"], p["z"])
	main.room.add_child(node)
	var o := {"name": p["name"], "node": node, "target": node.position, "ry": float(p["ry"]),
		"f": {}, "touching": [false, false], "synth": null, "player": null}
	if ClassDB.class_exists("PinkTrombone"):
		var synth = ClassDB.instantiate("PinkTrombone")
		synth.setup(AudioServer.get_mix_rate())
		if "tongue_full_range" in synth:
			synth.tongue_full_range = true
		synth.auto_wobble = true
		synth.always_voice = false
		synth.voice_held = false
		var player := AudioStreamPlayer.new()
		player.stream = synth.create_stream()
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		player.volume_db = -80.0
		add_child(player)
		player.play()
		o["synth"] = synth
		o["player"] = player
	# A name tag over their head.
	var tag := Label3D.new()
	tag.text = p["name"]
	tag.modulate = Color(0.133, 0.133, 0.125)
	tag.outline_size = 0
	tag.font_size = 40
	tag.pixel_size = 0.01
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.position.y = 3.3
	node.add_child(tag)
	o["tag"] = tag
	others[id] = o


func _remove(id: String) -> void:
	var o = others.get(id)
	if o == null:
		return
	o["node"].queue_free()
	if o["player"]:
		o["player"].queue_free()
	others.erase(id)


func _update_others(delta: float) -> void:
	var me: Vector3 = main.character.position
	for id in others:
		var o: Dictionary = others[id]
		var node: Node3D = o["node"]
		o["tag"].text = o["name"]
		var before := node.position
		node.position = node.position.lerp(o["target"], 1.0 - exp(-12.0 * delta))
		node.rotation.y = lerp_angle(node.rotation.y, o["ry"], 1.0 - exp(-12.0 * delta))
		var flat := Vector2(node.position.x - before.x, node.position.z - before.z)
		node.drive_speed = flat.length() / maxf(delta, 1e-3)
		var lift: float = node.position.y - World.height(node.position.x, node.position.z)
		node.floor_shadow.position.y = 0.006 - maxf(lift, 0.0)
		var f: Dictionary = o["f"]
		var face := {}
		if o["synth"]:
			if not f.is_empty():
				VoiceMap.apply(o["synth"], f, o["touching"])
				o["synth"].voice_held = f.get("voiced", true)
				face = VoiceMap.face(o["synth"])
			else:
				o["synth"].voice_held = false
			var d := me.distance_to(node.position)
			var k := clampf((d - HEARING_FULL) / (HEARING_SILENT - HEARING_FULL), 0.0, 1.0)
			o["player"].volume_db = linear_to_db(maxf((1.0 - k) * (1.0 - k), 0.0001))
			# Only run their voice while they make a sound you can hear: in a big room, a
			# synth for everyone at once is too much for a browser.
			var player: AudioStreamPlayer = o["player"]
			if not f.is_empty() and k < 1.0:
				o["quiet"] = 0.0
				if not player.playing:
					player.play()
			else:
				o["quiet"] = o.get("quiet", 0.0) + delta
				if player.playing and o["quiet"] > 1.5:
					player.stop()
		node.update_character(delta, face, main.time)
