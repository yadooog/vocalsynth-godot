extends Node
## Online play: one shared room over a WebSocket to the game's server (server/godot.js in the
## vocalcordgame repo). Sends where you are and the sound you're making; shows and plays
## everyone else. The booth, the song and the beat are shared. If the server can't be reached
## the game just carries on offline.

const DEFAULT_URL := "wss://vocalcordgame.onrender.com/godot-ws"
const SEND_EVERY := 1.0 / 15.0
const PING_EVERY := 2.0
const HEARING_FULL := 4.0
const HEARING_SILENT := 30.0

var main: Control
var ws := WebSocketPeer.new()
var connected := false
var you := ""                  # our id in the room
var others := {}               # id -> {name, node, synth, player, touching, target, ry, f}
var booth_owner = null         # id of who's in the booth, or null
var _send_left := 0.0
var _ping_left := 0.0
var _last_sent := {}
var _was_voiced := false
var _offset := 0.0             # server clock minus our clock
var _have_clock := false
var _tried := false
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
	ws.connect_to_url(url())
	_tried = true
	main.beats.edited.connect(_on_beat_edited)


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
			_send({"t": "ping", "c": Time.get_ticks_msec() / 1000.0})
	elif state == WebSocketPeer.STATE_CLOSED and connected:
		connected = false
		for id in others.keys():
			_remove(id)
		booth_owner = null
	if _have_clock:
		main.beats.sync(Time.get_ticks_msec() / 1000.0 + _offset)
	_update_others(delta)


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
			you = m["you"]["id"]
			for p in m["players"]:
				_add(p)
			main.song.clear()
			for s in m["song"]:
				_add_section(s, true)
			booth_owner = m["booth"]
			main.room.set_booth_busy(booth_owner != null)
			main.beats.pattern = m["pattern"]
			_offset = float(m["clock"]) - Time.get_ticks_msec() / 1000.0
			_have_clock = true
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
		"beat":
			main.beats.pattern = m["pattern"]
		"pong":
			# Half the round trip has passed since the server read its clock.
			var now := Time.get_ticks_msec() / 1000.0
			var rtt := now - float(m["c"])
			_offset = float(m["clock"]) + rtt * 0.5 - now


func _add_section(s: Dictionary, quiet: bool) -> void:
	var i: int = main.song.add_section(s["keys"])
	if i >= 0:
		main.song.set_live(i)


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


func add_section(keys: Array) -> void:
	if connected:
		_send({"t": "section", "keys": keys})


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
		node.update_character(delta, face, main.time)
