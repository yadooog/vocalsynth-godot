extends PanelContainer
## The round, top right, while a game is on: the brief, whose turn it is, the vote, the results
## and the scores. It follows net.game, the server's word on the round (server/godot_game.js
## in the vocalcordgame repo). main.gd makes it and places it.

const WIDTH := 300.0

var main: Control
var net: Node
var _box: VBoxContainer
var _clock: Label            # time left in this part of the round
var _brief_edit: LineEdit    # the brief, while you type it
var _booth_go: Button        # on your turn: takes you to the booth
var _playing: Label          # in the vote: whose loop is playing now
var _my_vote := -1
var _shown := ""             # the round and phase the card was built for, e.g. "3 vote"


func _ready() -> void:
	visible = false
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	net.game_changed.connect(_rebuild)
	minimum_size_changed.connect(place)


func place() -> void:
	size = Vector2(WIDTH, get_combined_minimum_size().y)
	position = Vector2(main.size.x - main.GAP - WIDTH, main.GAP)


func _process(_delta: float) -> void:
	if not visible:
		return
	if _clock:
		var s := int(ceil(net.time_left()))
		_clock.text = "%d:%02d" % [floori(s / 60.0), s % 60]
	if _booth_go:
		_booth_go.visible = main.booth_state == "room"
	if _playing:
		var i: int = main.listen if main.listen >= 0 else main.vote_playing
		var text := "playing: everyone"
		for s in net.game.get("sections", []):
			if int(s["i"]) == i:
				text = "playing: " + _section_name(s)
		_playing.text = text


func _rebuild() -> void:
	var g: Dictionary = net.game
	var phase: String = net.phase()
	var shown := "%s %s" % [g.get("round", 0), phase]
	var fresh := shown != _shown
	if fresh:
		_shown = shown
		_my_vote = -1
		main.listen = -1
	var typed := ""
	var typing := false
	if is_instance_valid(_brief_edit):
		typed = _brief_edit.text
		typing = _brief_edit.has_focus()
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_clock = null
	_playing = null
	_brief_edit = null
	_booth_go = null
	visible = phase != "free"
	if not visible:
		return

	var head := _row()
	head.add_child(_label("round %d" % int(g.get("round", 1)), &"BoldLabel"))
	var status := _label(_status(g, phase), &"DimLabel")
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.clip_text = true
	head.add_child(status)
	_clock = _label("", &"DimLabel")
	head.add_child(_clock)
	head.add_child(_button("end", net.stop_game, &"", "end"))
	_box.add_child(head)
	var hint := _label(_hint(g, phase))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = WIDTH - 24.0
	_box.add_child(hint)

	if phase == "brief":
		if g.get("setter") == net.you:
			var row := _row()
			_brief_edit = LineEdit.new()
			_brief_edit.name = "brief"
			_brief_edit.placeholder_text = "a word, a theme or a genre"
			_brief_edit.max_length = 40
			_brief_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_brief_edit.text = typed
			_brief_edit.text_submitted.connect(_send_brief)
			row.add_child(_brief_edit)
			var go := _button("go", func(): _send_brief(_brief_edit.text), &"BigButton", "brief_go")
			go.custom_minimum_size.x = 48.0
			row.add_child(go)
			_box.add_child(row)
			var ideas := HFlowContainer.new()
			ideas.add_theme_constant_override("h_separation", 6)
			ideas.add_theme_constant_override("v_separation", 6)
			for idea in g.get("suggestions", []):
				ideas.add_child(_button(str(idea), _send_brief.bind(str(idea)), &"", "idea%d" % ideas.get_child_count()))
			_box.add_child(ideas)
			if main.can_set_key(): # a new song: pick its key too
				var key_row := _row()
				key_row.add_child(_label("key", &"DimLabel"))
				key_row.add_child(main.make_key_picker())
				_box.add_child(key_row)
			if fresh or typing:
				_focus_brief.call_deferred()
	else:
		var brief := _label("“%s”" % str(g.get("brief", "")), &"BoldLabel")
		brief.add_theme_font_size_override("font_size", 18)
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brief.custom_minimum_size.x = WIDTH - 24.0
		_box.add_child(brief)

	if phase == "build":
		if net.my_turn():
			_booth_go = _button("go to the booth", main.go_to_booth, &"BigButton", "booth_go")
			_booth_go.visible = main.booth_state == "room"
			_box.add_child(_booth_go)
		var queue: Array = g.get("queue", [])
		if not queue.is_empty():
			var names := PackedStringArray()
			for id in queue:
				names.append(net.name_of(id))
			_box.add_child(_label("next: " + ", ".join(names), &"DimLabel"))

	if phase == "vote":
		var listening := ButtonGroup.new()
		listening.allow_unpress = true
		var votes := ButtonGroup.new()
		for s in g.get("sections", []):
			if s.get("kept", false):
				continue # loops that stayed on from before aren't up for the vote
			var i := int(s["i"])
			var row := _row()
			var who := _label(_section_name(s))
			who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(who)
			var listen := _button("listen", null, &"", "listen%d" % i)
			listen.toggle_mode = true
			listen.button_group = listening
			listen.button_pressed = main.listen == i
			listen.toggled.connect(func(on): _listen(i, on))
			row.add_child(listen)
			var vote := _button("vote", null, &"", "vote%d" % i)
			vote.toggle_mode = true
			vote.button_group = votes
			vote.button_pressed = _my_vote == i
			vote.disabled = s["owner"] == net.you
			vote.pressed.connect(_vote.bind(i))
			row.add_child(vote)
			_box.add_child(row)
		var voted: Array = g.get("voted", [])
		_playing = _label("", &"BoldLabel")
		_box.add_child(_playing)
		_box.add_child(_label("%d voted" % voted.size(), &"DimLabel"))

	if phase == "results":
		var tally: Array = g.get("tally", [])
		var winner := int(g.get("winner", -1))
		var still := PackedStringArray()
		for s in g.get("sections", []):
			var i := int(s["i"])
			if s.get("kept", false) and i != winner:
				still.append(_section_name(s))
				continue
			var row := _row()
			var who := _label(_section_name(s), &"BoldLabel" if i == winner else &"Label")
			who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(who)
			var n: int = int(tally[i]) if i < tally.size() else 0
			var tomatoes := int(s.get("tomatoes", 0))
			if tomatoes > 0:
				row.add_child(_label("%d tomato%s" % [tomatoes, "" if tomatoes == 1 else "es"], &"DimLabel"))
			row.add_child(_label("%d vote%s" % [n, "" if n == 1 else "s"], &"DimLabel"))
			if i == winner:
				row.add_child(_label("stays on", &"BoldLabel"))
			_box.add_child(row)
		if not still.is_empty():
			var on := _label("still on, +%d each: %s" % [int(g.get("stayBonus", 2)), ", ".join(still)], &"DimLabel")
			on.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			on.custom_minimum_size.x = WIDTH - 24.0
			_box.add_child(on)

	var scores: Array = g.get("scores", []).duplicate()
	scores.sort_custom(func(a, b): return float(a["points"]) > float(b["points"]))
	# The top five (in a big room), and you.
	var parts := PackedStringArray()
	for k in scores.size():
		var sc: Dictionary = scores[k]
		if k < 5 or sc["id"] == net.you:
			parts.append("%s%s %d" % ["" if k < 5 else "… ", net.name_of(sc["id"], str(sc["name"])), int(sc["points"])])
	var line := _label("   ".join(parts), &"DimLabel")
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = WIDTH - 24.0
	_box.add_child(line)
	place()


func _status(g: Dictionary, phase: String) -> String:
	match phase:
		"brief":
			if g.get("setter") == net.you:
				return "you pick the brief"
			return "%s picks the brief" % net.name_of(g.get("setter"), str(g.get("setterName", "someone")))
		"build":
			if net.my_turn():
				return "your turn"
			return "%s's turn" % net.name_of(g.get("turn"), str(g.get("turnName", "someone")))
		"vote":
			return "vote"
		"results":
			return "results"
	return ""


## Whose loop it is.
func _section_name(s: Dictionary) -> String:
	return "you" if s["owner"] == net.you else str(s["name"])


## What to do now, in a line.
func _hint(g: Dictionary, phase: String) -> String:
	match phase:
		"brief":
			if g.get("setter") == net.you:
				return "pick what this round's song is about: type it or tap an idea"
			return "waiting for the brief"
		"build":
			if net.my_turn():
				return "go to the booth and make a loop that fits the brief. it joins the song when you come out"
			var queue: Array = g.get("queue", [])
			var who: String = net.name_of(g.get("turn"), str(g.get("turnName", "someone")))
			if not queue.is_empty() and queue[0] == net.you:
				return "%s is in the booth. you're next" % who
			if g.get("sections", []).any(func(x): return not x.get("kept", false) and x["owner"] == net.you):
				return "%s is in the booth. your loop's in the song" % who
			if not queue.has(net.you):
				return "%s is in the booth. the song's full this round, so you go first next round" % who
			return "%s is making a loop in the booth" % who
		"vote":
			for s in g.get("sections", []):
				if not s.get("kept", false) and s["owner"] != net.you:
					return "each new loop plays on its own, then all together. vote for your favourite (not your own). listen repeats one"
			return "the others are voting on your loop"
		"results":
			if g.get("tally", []).all(func(n): return int(n) == 0):
				return "no votes this time (it needs someone else to vote), so the first new loop stays on. the song carries on next round"
			return "the top loop stays on in the song, and the song carries on next round"
	return ""


func _focus_brief() -> void:
	if is_instance_valid(_brief_edit) and _brief_edit.is_inside_tree():
		_brief_edit.grab_focus()


func _send_brief(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	if is_instance_valid(_brief_edit):
		_brief_edit.release_focus()
	net.send_brief(text)


func _listen(i: int, on: bool) -> void:
	if on:
		main.listen = i
	elif main.listen == i:
		main.listen = -1


func _vote(i: int) -> void:
	_my_vote = i
	net.vote(i)


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	return row


func _label(text: String, variation := &"") -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	return l


func _button(text: String, on_press = null, variation := &"", id := "") -> Button:
	var b := Button.new()
	b.text = text
	if id != "":
		b.name = id
	b.focus_mode = Control.FOCUS_NONE
	if variation != &"":
		b.theme_type_variation = variation
	if on_press is Callable:
		b.pressed.connect(on_press)
	return b


## For browser tests: the middle of each named button and box, to click on.
func test_points() -> Dictionary:
	var out := {}
	if visible:
		_collect(self, out)
	return out


func _collect(n: Node, out: Dictionary) -> void:
	for c in n.get_children():
		if (c is Button or c is LineEdit) and c.is_visible_in_tree() and not str(c.name).begins_with("@"):
			var r: Rect2 = c.get_global_rect()
			out[str(c.name)] = [roundi(r.get_center().x), roundi(r.get_center().y)]
		_collect(c, out)
