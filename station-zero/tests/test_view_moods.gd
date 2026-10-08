extends RefCounted
## Task 6a, step 3 (tests first, red): the view-side emotions tests. Spec: docs/specs/emotions.md revision 3, section 13 tests
## 22, 22b, 23, 24 (the being panel as a pure function, its purity, the source scan) and the panel halves of tests 13(h) and 36.
## Test 32 (selection rules: hit test, three-tap path, close rules, follow, outline, tap from the log) and test 33 (PanelHold)
## need view code whose function names the spec does not give, so they are parked in
## tests/deferred/test_view_selection.gd.txt and tests/deferred/test_view_panel_hold.gd.txt with the API they assume; they
## become tests at the view step (plan step 8) once the implementer names the functions.
##
## Method: the panel is a pure function of the world, `BeingPanel.lines(world, id)` in res://view/model/being_panel.gd (spec
## 7.1, last paragraph). The script is reached with load(), the world and beings are untyped Variants, so on a tree without the
## implementation the file parses and each test fails cleanly through `_api()` (one failed check naming the missing pieces;
## _begin/_end guard the body). Worlds are blank worlds with the mood fields written by hand (as tests/test_moods.gd).
##
## API ASSUMED (spec 7.1; the implementer should match or tell the test author):
##  - `BeingPanel.lines(world, id) -> Array` of Strings, a static function. One element per template, in the order of 7.1:
##    who; the band sentence with the why appended after one space (one element, two sentences); the nature sentence (only when
##    no why is shown); the company sentence. An even being with no why has no spirits element. Nothing else (no title key, no
##    numbers). Names are `Being.name` (the tests name beings N<id>); the description is `Being.persona.description`.
##  - The panel reads Being.mood_band, mood_why {key, id, name, t, clause, sign}, mood_base, mood_halflife, the world clock
##    (`world.t`, `world.clock.sol_h`, for "fresh" against why.fresh_sols), relationships.friends_of(id) and data/mood.json
##    text.* and nature.*; it never reads Being.mood itself.
##  - A why key `birth` (spec 5.2, 7.1) or `birth_parent` (5.4 rule 1) both map to text.why.birth.
## Where the spec leaves a detail open, extended simply (see the task report's numbered spec questions): a sentence is a run of
## text ending in a period, so the sentence count of a panel is the number of periods in its elements; names and descriptions
## contain none.

const CMP := 1e-12
const HAB1 := 2
const HAB2 := 3
const GREEN := 5


func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func _begin(t) -> void:
	t._failures.append(_abort_msg(t))


func _end(t) -> void:
	t._failures.erase(_abort_msg(t))


func _has_static(script: Variant, method: String) -> bool:
	if script == null:
		return false
	for m in script.get_script_method_list():
		if m.name == method:
			return true
	return false


func _md() -> Dictionary:
	if not FileAccess.file_exists("res://data/mood.json"):
		return {}
	var d: Variant = SimData.load_json("mood.json")
	return d if d is Dictionary else {}


func _panel() -> Variant:
	if FileAccess.file_exists("res://view/model/being_panel.gd"):
		return load("res://view/model/being_panel.gd")
	return null


func _api(t) -> bool:
	var missing: Array[String] = []
	if not FileAccess.file_exists("res://data/mood.json"):
		missing.append("data/mood.json")
	var p = _panel()
	if p == null:
		missing.append("view/model/being_panel.gd")
	elif not _has_static(p, "lines"):
		missing.append("BeingPanel.lines()")
	if FileAccess.file_exists("res://sim/moods.gd"):
		var ms = load("res://sim/moods.gd")
		if not _has_static(ms, "temperament"):
			missing.append("Moods.temperament()")
	else:
		missing.append("sim/moods.gd")
	var w = SimWorld.new(1, {"blank": true})
	var b = w.add_being(HAB1)
	for f in ["mood", "mood_base", "mood_halflife", "mood_band", "mood_why"]:
		if not (f in b):
			missing.append("Being.%s" % f)
	if not w.relationships.has_method("friends_of"):
		missing.append("world.relationships.friends_of()")
	t.check(missing.is_empty(), "missing API: " + ", ".join(PackedStringArray(missing)))
	if missing.is_empty():
		_begin(t)
	return missing.is_empty()


# ---------------------------------------------------------------- staging

func _world() -> Variant:
	var w = SimWorld.new(1, {"blank": true})
	w.add_building("reactor", 0, 0)
	w.add_building("habitat", 40, 0)
	w.add_building("habitat", 80, 0)
	w.add_building("workshop", 120, 0)
	w.add_building("green_room", 160, 0)
	return w


func _being(w, bid: int = HAB1) -> Variant:
	var b = w.add_being(bid)
	b.name = "N%d" % b.id
	b.persona.description = "warm and nurturing"
	b.state = "sleep"
	b.mood_base = 0.0
	b.mood = 0.0
	b.mood_halflife = 4.0
	b.mood_band = 2
	b.mood_why = null
	return b


const BAND_D := {0: -0.50, 1: -0.25, 2: 0.0, 3: 0.25, 4: 0.50}


func _set_band(b, band: int) -> void:
	b.mood_band = band
	b.mood = float(b.mood_base) + float(BAND_D[band])


func _why(key: String, id: int, sign: int, t_set: float, clause: String = "") -> Dictionary:
	return {"key": key, "id": id, "name": "N%d" % id, "t": t_set, "clause": clause, "sign": sign}


func _lines(w, b) -> Array:
	return _panel().call("lines", w, b.id)


func _text(lines: Array) -> String:
	return " ".join(PackedStringArray(lines.map(func(x): return str(x))))


func _sentences(lines: Array) -> int:
	var n := 0
	for l in lines:
		n += str(l).count(".")
	return n


func _tx(path: String, name: String, other: String = "") -> String:
	var node: Variant = _md()
	for k in path.split("."):
		node = node[k]
	return str(node).replace("{name}", name).replace("{other}", other).replace("{description}", "warm and nurturing")


func _friend_with(w, a, other, bond: float) -> void:
	w.relationships.debug_set_bond(a.id, other.id, bond)


# ---------------------------------------------------------------- 22. panel lines

func test_t22a_the_canonical_panels_are_exact(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w)
	_set_band(a, 1)
	a.mood_why = _why("grief", 50, -1, float(w.t))
	t.eq(_lines(w, a), ["N1 is warm and nurturing.", "N1 is out of spirits. They are mourning N50.", "N1 knows no one well yet."],
			"who, spirits with the why appended, company (K1)")
	a.mood_why = null
	a.mood_base = -0.17
	a.mood_halflife = 10.4
	t.eq(_lines(w, a), ["N1 is warm and nurturing.", "N1 is out of spirits.", "N1 takes things to heart.", "N1 knows no one well yet."],
			"who, spirits, nature (no why shown), company")
	_end(t)


func test_t22b_the_four_spirit_sentences_with_and_without_a_why(t) -> void:
	if not _api(t):
		return
	var keys := {0: "heavy", 1: "low", 3: "light", 4: "bright"}
	for band in keys:
		var w = _world()
		var a = _being(w)
		_set_band(a, band)
		var sent := _tx("text.band." + keys[band], "N1")
		var plain := _lines(w, a)
		t.check(sent in plain, "band %s: the sentence '%s' is an element of its own without a why" % [keys[band], sent])
		var sign := -1 if band < 2 else 1
		a.mood_why = _why("hard_sol" if sign < 0 else "pledge", 0, sign, float(w.t), "ice")
		var why_txt := _tx("text.why.hard" if sign < 0 else "text.why.pledge", "N1")
		t.check((sent + " " + why_txt) in _lines(w, a), "band %s: the why is appended after one space" % keys[band])
	_end(t)


func test_t22c_an_even_being_with_no_why_has_no_spirits_line(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w)
	var ls := _lines(w, a)
	t.eq(ls, ["N1 is warm and nurturing.", "N1 knows no one well yet."], "even and no why: who and company only")
	for k in ["low", "heavy", "light", "bright"]:
		t.check(not (_tx("text.band." + k, "N1") in ls), "no %s sentence" % k)
	# A stored why does not show while the band is even (d inside the band exit edge, or not yet past the entry).
	a.mood_why = _why("grief", 50, -1, float(w.t))
	a.mood = -0.17
	t.eq(_lines(w, a), ls, "a stored why with the band even is not shown")
	_end(t)


func test_t22d_the_company_sentence_k1_close_and_friend(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w)
	var x = _being(w, HAB2)
	var y = _being(w, HAB2)
	var z = _being(w, GREEN)
	t.check(_tx("text.panel.k1", "N1") in _lines(w, a), "no friend: the K1 sentence, exact")
	_friend_with(w, a, x, 0.4)
	_friend_with(w, a, y, 0.5)
	var ls := _lines(w, a)
	t.check(_tx("text.panel.friend", "N1", "N3") in ls, "a friend, no close pair: 'counts {other} as a friend', the highest bond (N3, 0.5)")
	t.check(not (_tx("text.panel.k1", "N1") in ls), "and no K1 sentence")
	_friend_with(w, a, z, 0.7)
	_friend_with(w, a, x, 0.7)
	t.check(_tx("text.panel.close", "N1", "N2") in _lines(w, a), "two close pairs at the same bond: the lowest id (N2)")
	_friend_with(w, a, z, 0.9)
	t.check(_tx("text.panel.close", "N1", "N4") in _lines(w, a), "the close friend with the highest bond (N4)")
	var all := _text(_lines(w, a))
	t.check(all.find("N3") < 0, "the other friends are not named")
	_end(t)


func test_t22e_a_newborn_with_a_held_kin_bond_is_not_lonely_and_a_lapsed_pair_is(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var p = _being(w)
	w._create_newborn(w.buildings.get_building(HAB1), p)
	var nb = w.beings.back()
	w.relationships.on_step(w, float(SimData.relationships().tick_h))
	t.check(w.relationships.are_friends(p.id, nb.id), "staging: the kin pair holds the friends flag")
	var ls := _lines(w, nb)
	t.check(not (_tx("text.panel.k1", nb.name) in ls), "a newborn whose kin bond holds shows no K1 sentence")
	t.check(_tx("text.panel.friend", nb.name, p.name) in ls or _tx("text.panel.close", nb.name, p.name) in ls, "but a friend sentence naming the parent")
	# A being whose only friend pair lapsed shows K1 and no friend why, although the why is still stored.
	var w2 = _world()
	var a = _being(w2)
	var x = _being(w2, HAB2)
	w2.relationships.debug_set_bond(a.id, x.id, 0.5)
	_set_band(a, 3)
	a.mood_why = _why("friend", x.id, 1, float(w2.t))
	t.check(_tx("text.why.friend", "N1", "N2") in _text(_lines(w2, a)), "staging: the friend why shows while the pair holds")
	w2.relationships.debug_set_bond(a.id, x.id, 0.0)
	var ls2 := _lines(w2, a)
	var txt := _text(ls2)
	t.check(_tx("text.panel.k1", "N1") in ls2, "after the pair lapsed: the K1 sentence")
	t.check(txt.find(_tx("text.why.friend", "N1", "N2")) < 0 and txt.find(_tx("text.why.friend_old", "N1", "N2")) < 0, "and no friend why next to it")
	a.mood_why = _why("close", x.id, 1, float(w2.t))
	var txt2 := _text(_lines(w2, a))
	t.check(txt2.find(_tx("text.why.close", "N1", "N2")) < 0 and txt2.find(_tx("text.why.close_old", "N1", "N2")) < 0, "a close why is suppressed the same way")
	a.mood_why = _why("lapse", x.id, -1, float(w2.t))
	_set_band(a, 1)
	t.check(_tx("text.why.lapse", "N1", "N2") in _text(_lines(w2, a)), "a lapse why names a person the being no longer holds: it shows")
	_end(t)


func test_t22f_sign_agreement_and_the_texts_of_every_why(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w)
	var x = _being(w, HAB2)
	w.relationships.debug_set_bond(a.id, x.id, 0.5)
	_set_band(a, 1)
	a.mood_why = _why("friend", x.id, 1, float(w.t))
	var txt := _text(_lines(w, a))
	t.check(txt.find("friend") < 0 or txt.find(_tx("text.why.friend", "N1", "N2")) < 0, "a why whose stored sign differs from the sign of d is not shown")
	t.check(_tx("text.band.low", "N1") in _lines(w, a), "the band sentence still shows, without the why")
	var cases := [
		["lapse", -1, 1, "text.why.lapse"], ["hard_sol", -1, 1, "text.why.hard"], ["grief", -1, 0, "text.why.grief_new"],
		["birth", 1, 3, "text.why.birth"], ["birth_parent", 1, 3, "text.why.birth"], ["pledge", 1, 3, "text.why.pledge"],
		["friend", 1, 3, "text.why.friend"], ["close", 1, 3, "text.why.close"],
	]
	for c in cases:
		var w2 = _world()
		var b = _being(w2)
		var o = _being(w2, HAB2)
		w2.relationships.debug_set_bond(b.id, o.id, 0.7)
		_set_band(b, int(c[2]))
		b.mood_why = _why(str(c[0]), o.id, int(c[1]), float(w2.t), "air")
		var want := _tx(str(c[3]), "N1", "N2")
		t.check(want in _text(_lines(w2, b)), "why %s shows '%s'" % [str(c[0]), want])
	var w3 = _world()
	var h = _being(w3)
	_set_band(h, 1)
	h.mood_why = _why("hard_sol", 0, -1, float(w3.t), "ice")
	var ht := _text(_lines(w3, h))
	for word in ["ice", "air", "food", "water", "oxygen"]:
		t.check(ht.to_lower().find(word) < 0, "a hard why names no resource (%s)" % word)
	_end(t)


func test_t22g_a_company_why_adds_no_sentence(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w)
	_set_band(a, 3)
	var plain := _lines(w, a)
	a.mood_why = _why("company", 2, 1, float(w.t))
	t.eq(_lines(w, a), plain, "a stored company why changes nothing in the panel")
	_end(t)


func test_t22h_the_panel_is_never_more_than_four_sentences_and_has_no_digit(t) -> void:
	if not _api(t):
		return
	var natures := [[-0.17, 10.4, "text.nature.heavy"], [0.15, 3.6, "text.nature.bright"], [0.03, 8.0, "text.nature.slow"],
			[-0.04, 1.6, "text.nature.quick"], [0.0, 4.0, ""]]
	var why_keys := ["", "grief", "friend", "close", "lapse", "lapse_close", "birth", "hard_sol", "pledge"]
	var digit := RegEx.new()
	digit.compile("\\d")
	var worst := 0
	var worst_desc := ""
	var checked := 0
	var nature_with_why := 0
	var bad_digit := 0
	for company in ["none", "friend", "close"]:
		for nat in natures:
			for band in [0, 1, 2, 3, 4]:
				for wk in why_keys:
					var w = _world()
					var a = _being(w)
					var x = _being(w, HAB2)
					# Digit-free names, so the digit check looks at the templates and nothing else.
					a.name = "Vana"
					x.name = "Kiro"
					if company == "friend":
						w.relationships.debug_set_bond(a.id, x.id, 0.4)
					elif company == "close":
						w.relationships.debug_set_bond(a.id, x.id, 0.7)
					a.mood_base = float(nat[0])
					a.mood_halflife = float(nat[1])
					_set_band(a, band)
					if wk != "":
						var sign := -1 if band < 2 else 1
						a.mood_why = _why(wk, x.id, sign, float(w.t), "ice")
						a.mood_why.name = "Kiro"
					var ls := _lines(w, a)
					checked += 1
					var n := _sentences(ls)
					if n > worst:
						worst = n
						worst_desc = "company %s nature %s band %d why %s" % [company, str(nat[2]), band, wk]
					var txt := _text(ls)
					if digit.search(txt) != null or txt.find("%") >= 0:
						bad_digit += 1
					if str(nat[2]) != "":
						var nat_txt := _tx(str(nat[2]), "Vana")
						var has_why := false
						for k in ["grief_new", "grief_still", "friend", "friend_old", "close", "close_old", "lapse", "birth", "hard", "pledge"]:
							if txt.find(_tx("text.why." + k, "Vana", "Kiro")) >= 0:
								has_why = true
						if has_why and txt.find(nat_txt) >= 0:
							nature_with_why += 1
	t.check(checked == 3 * 5 * 5 * 9, "staging: the sweep ran (%d panels)" % checked)
	t.check(worst <= 4, "never more than four sentences (worst %d at %s)" % [worst, worst_desc])
	t.eq(bad_digit, 0, "no digit and no percent sign in any panel")
	t.eq(nature_with_why, 0, "the nature sentence never appears together with a why sentence")
	_end(t)


func test_t22i_nature_reachability_for_twelve_signs_and_both_worlds(t) -> void:
	if not _api(t):
		return
	var ms = load("res://sim/moods.gd")
	var keys := ["text.nature.heavy", "text.nature.bright", "text.nature.slow", "text.nature.quick"]
	for wk in ["mars", "earth"]:
		var by_key := {}
		var signs_with := 0
		for i in 12:
			var chart: Dictionary = {"world": "mars", "sun": 0, "deimos": i, "phobos": 0, "rise": 0, "earth": 0} if wk == "mars" else {"world": "earth", "sun": 0, "moon": i, "rise": 0}
			var r: Dictionary = ms.call("temperament", chart)
			var w = _world()
			var a = _being(w)
			a.mood_base = float(r.base)
			a.mood_halflife = float(r.halflife)
			var txt := _text(_lines(w, a))
			var hits: Array = []
			for k in keys:
				if txt.find(_tx(k, "N1")) >= 0:
					hits.append(k)
			t.check(hits.size() <= 1, "%s sign %d: at most one nature sentence (%d)" % [wk, i, hits.size()])
			if hits.size() == 1:
				signs_with += 1
				by_key[hits[0]] = int(by_key.get(hits[0], 0)) + 1
		t.eq(signs_with, 4, "%s: exactly four of twelve signs get a nature sentence" % wk)
		for k in keys:
			t.eq(int(by_key.get(k, 0)), 1, "%s: %s is chosen by exactly one sign" % [wk, k])
	# A chart-less (neutral) being gets none.
	var w2 = _world()
	var n = _being(w2)
	var txt2 := _text(_lines(w2, n))
	for k in keys:
		t.check(txt2.find(_tx(k, "N1")) < 0, "a neutral being gets no nature sentence (%s)" % k)
	_end(t)


# ---------------------------------------------------------------- 13(h), 36. tense and the birth why on the panel

func test_t13h_tenses_fresh_and_old(t) -> void:
	if not _api(t):
		return
	var fresh := float(_md().why.fresh_sols)
	for c in [["grief", -1, 1, "text.why.grief_new", "text.why.grief_still"], ["friend", 1, 3, "text.why.friend", "text.why.friend_old"],
			["close", 1, 3, "text.why.close", "text.why.close_old"]]:
		var w = _world()
		var a = _being(w)
		var x = _being(w, HAB2)
		w.relationships.debug_set_bond(a.id, x.id, 0.7)
		_set_band(a, int(c[2]))
		a.mood_why = _why(str(c[0]), x.id, int(c[1]), float(w.t))
		var sol_h := float(w.clock.sol_h)
		var txt0 := _text(_lines(w, a))
		t.check(txt0.find(_tx(str(c[3]), "N1", "N2")) >= 0, "%s: set this sol: '%s'" % [c[0], _tx(str(c[3]), "N1", "N2")])
		w.t = float(a.mood_why.t) + (fresh * 0.5) * sol_h
		t.check(_text(_lines(w, a)).find(_tx(str(c[3]), "N1", "N2")) >= 0, "%s: half a fresh window later: still the new wording" % c[0])
		w.t = float(a.mood_why.t) + (fresh * 1.5) * sol_h
		var txt1 := _text(_lines(w, a))
		t.check(txt1.find(_tx(str(c[4]), "N1", "N2")) >= 0, "%s: past fresh_sols: '%s'" % [c[0], _tx(str(c[4]), "N1", "N2")])
	_end(t)


func test_t36_the_birth_why_shows_while_light(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w)
	_set_band(a, 3)
	a.mood_why = _why("birth", 60, 1, float(w.t))
	var ls := _lines(w, a)
	t.check((_tx("text.band.light", "N1") + " " + _tx("text.why.birth", "N1", "N60")) in ls, "light band plus 'They were there when N60 was born.'")
	_set_band(a, 2)
	t.check(_text(_lines(w, a)).find("born") < 0, "and nothing about it once the band is even")
	_end(t)


# ---------------------------------------------------------------- 23. purity

class CountRng extends SimRng:
	var calls := 0

	func randf() -> float:
		calls += 1
		return 0.5

	func randf_range(from: float, to: float) -> float:
		calls += 1
		return (from + to) / 2.0

	func randi_range(from: int, _to: int) -> int:
		calls += 1
		return from

	func chance(_p: float) -> bool:
		calls += 1
		return false

	func pick(items: Array) -> Variant:
		calls += 1
		return null if items.is_empty() else items[0]


func _world_digest(w) -> String:
	var parts: Array = []
	for b in w.beings:
		parts.append([b.id, b.energy, b.state, b.wait_h, b.mood, b.mood_band, b.mood_why])
	parts.append(w.stats)
	parts.append(w.log)
	parts.append(w.relationships.pairs)
	return JSON.stringify(parts, "", true).sha256_text()


func test_t23_calling_the_panel_changes_nothing_and_draws_nothing(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w)
	var x = _being(w, HAB2)
	w.relationships.debug_set_bond(a.id, x.id, 0.7)
	_set_band(a, 1)
	a.mood_why = _why("lapse", x.id, -1, float(w.t))
	var rng := CountRng.new(1)
	w.rng = rng
	var h0 := _world_digest(w)
	var first := _lines(w, a)
	var second := _lines(w, a)
	t.eq(second, first, "calling it twice gives the same lines")
	t.eq(_world_digest(w), h0, "stats, log, beings and pairs are unchanged")
	t.eq(rng.calls, 0, "no draw from world.rng")
	_end(t)


# ---------------------------------------------------------------- 24. isolation (source scan)

func _gd_files(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + f)
	for d in DirAccess.get_directories_at(dir):
		_gd_files(dir + d + "/", out)


func _code_only(src: String) -> Array[String]:
	var out: Array[String] = []
	for line in src.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("#"):
			continue
		var i := line.find(" #")
		out.append(line.substr(0, i) if i >= 0 else line)
	return out


func test_t24_the_view_source_reads_no_mood_number(t) -> void:
	if not _api(t):
		return
	var files: Array = []
	_gd_files("res://view/", files)
	t.check(files.size() > 10, "staging: the view sources were found (%d)" % files.size())
	var panel := "res://view/model/being_panel.gd"
	t.check(panel in files, "view/model/being_panel.gd exists")
	var num := RegEx.new()
	num.compile("\\.mood\\b(?!_)")
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		var code := "\n".join(PackedStringArray(_code_only(src)))
		t.check(code.find("stats.moods") < 0, "%s does not read stats.moods" % f)
		t.check(code.find("mood_k") < 0, "%s does not read mood_k" % f)
		t.check(num.search(code) == null, "%s does not read the mood number (.mood)" % f)
		if f != panel:
			t.check(code.to_lower().find("mood") < 0, "%s (a HUD or view file other than the panel) mentions no mood field" % f)
	_end(t)
