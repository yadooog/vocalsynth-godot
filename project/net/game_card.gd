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
		_box.add_child(_label("%d voted" % voted.size(), &"DimLabel"))

	if phase == "results":
		var tally: Array = g.get("tally", [])
		var winner := int(g.get("winner", -1))
		for s in g.get("sections", []):
			var i := int(s["i"])
			var row := _row()
			var who := _label(_section_name(s, false), &"BoldLabel" if i == winner else &"Label")
			who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(who)
			var n: int = int(tally[i]) if i < tally.size() else 0
			row.add_child(_label("%d vote%s" % [n, "" if n == 1 else "s"], &"DimLabel"))
			if i == winner:
				row.add_child(_label("stays on +%d" % int(g.get("stayBonus", 2)), &"BoldLabel"))
			_box.add_child(row)

	var scores: Array = g.get("scores", []).duplicate()
	scores.sort_custom(func(a, b): return float(a["points"]) > float(b["points"]))
	var parts := PackedStringArray()
	for sc in scores:
		parts.append("%s %d" % [net.name_of(sc["id"], str(sc["name"])), int(sc["points"])])
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


## Whose loop it is, and (in the vote) whether it stayed on from last round.
func _section_name(s: Dictionary, mark_stays := true) -> String:
	var who := "you" if s["owner"] == net.you else str(s["name"])
	return who + (" · stayed on" if mark_stays and int(s.get("stays", 0)) > 0 else "")


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
