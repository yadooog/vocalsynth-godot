extends Node
## The song everyone builds together. Each section is a 2-bar phrase someone made in the booth.
## It plays on its own synth, in time with the drums, and has a singer on the stage who
## mouths along. main.gd drives it every frame with update().

const MAX_SECTIONS := 6
const SINGER_X := [-20.2, -18.8, -17.4, -14.6, -13.2, -11.8] # on the stage, either side of the mic
const SINGER_Y := 0.6                                        # the stage's top
const SINGER_Z := -14.4
const SINGER_SCALE := 0.8
const HEADS := [Color("#a8dcb4"), Color("#f4c87a"), Color("#b9b0f2"), Color("#f29a8a"), Color("#8fd3e8"), Color("#e8e08f")]
const OUTFITS := [Color("#f4a9c4"), Color("#6fb8e8"), Color("#f4eec0"), Color("#86c79a"), Color("#e9a8f0"), Color("#9a9aa6")]

var sections: Array = []   # [{keys, synth, player, touching, singer, live}]
var stage_parent: Node3D   # where singers are added (the room)
var _character_script := preload("res://character/character.gd")


func is_full() -> bool:
	return sections.size() >= MAX_SECTIONS


## Adds a phrase to the song. It stays silent (and its singer hidden) until set_live().
func add_section(keys: Array) -> int:
	if is_full() or keys.is_empty() or not ClassDB.class_exists("PinkTrombone"):
		return -1
	var i := sections.size()
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
	var singer: Node3D = _character_script.new()
	singer.head_color = HEADS[i % HEADS.size()]
	singer.outfit_color = OUTFITS[i % OUTFITS.size()]
	singer.position = Vector3(SINGER_X[i], SINGER_Y, SINGER_Z)
	singer.scale = Vector3.ONE * SINGER_SCALE
	singer.visible = false
	if stage_parent:
		stage_parent.add_child(singer)
	sections.append({"keys": keys.duplicate(true), "synth": synth, "player": player,
		"touching": [false, false], "singer": singer, "live": false})
	return i


func set_live(i: int) -> void:
	if i >= 0 and i < sections.size():
		sections[i]["live"] = true
		sections[i]["singer"].visible = true


func clear() -> void:
	for s in sections:
		s["player"].queue_free()
		s["singer"].queue_free()
	sections.clear()


## Plays every section at `loop_pos` seconds into the 2-bar loop. `volume` is 0..1 (how near
## the stage you are); `solo` plays only that section (for a reveal), -1 for all live ones.
func update(delta: float, loop_pos: float, volume: float, time: float, solo := -1) -> void:
	for i in sections.size():
		var s: Dictionary = sections[i]
		var on: bool = (i == solo) if solo >= 0 else s["live"]
		VoiceMap.apply(s["synth"], Phrase.sample(s["keys"], loop_pos), s["touching"])
		s["player"].volume_db = linear_to_db(maxf(volume if on else 0.0, 0.0001))
		if s["singer"].visible and s["singer"].is_inside_tree():
			s["singer"].update_character(delta, VoiceMap.face(s["synth"]) if on else {}, time)
