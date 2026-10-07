extends RefCounted
## Task 5, step 4: the HUD half of spec docs/specs/council.md section 13 test 19 (and the HUD half of test 22). Red until the
## view step: the age word "Council" (read through SimData.council()), the merged chapters strip with the pinned pledge, and
## the source scan. The file compiles today (everything is dynamic) and fails cleanly through `_api()`.
##
## Method as tests/test_view_ages.gd: the HUD scene is instantiated and bound by hand (main.setup(sim)); nothing steps; the
## labels are read after main.refresh().
##
## API ASSUMED (spec 7.6; the nodes are those of test_view_ages.gd):
##  - the clock line ends with SimData.council().age.name when stats.age is "council" (ages.json gains no Council key);
##  - the chapters strip is the Chapters label; its entries are the union of stats.age_history and stats.council.chapters
##    ordered by `t` (a tie: the age entry first); each is `sol <clock_sol>  <first sentence>`; at most ages.hud.chapters_shown
##    (3) lines; when a pledge chapter exists and is not among the latest 3, the strip shows the latest 2 and the pledge;
##  - a chapter is {kind: "pledge", topic, text, t, sol, clock_sol} (spec 8).
## Where the spec leaves a detail open, extended simply: a tie on `t` between two age entries (impossible) is not tested.

const LABELS := ["Clock", "Colony", "Power", "Site", "Beings", "Chapters", "Log", "Controls"]


func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func _begin(t) -> void:
	t._failures.append(_abort_msg(t))


func _end(t) -> void:
	t._failures.erase(_abort_msg(t))


func _api(t) -> bool:
	var missing: Array[String] = []
	if not FileAccess.file_exists("res://data/council.json"):
		missing.append("data/council.json")
	var sd = load("res://sim/sim_data.gd")
	var has := false
	for m in sd.get_script_method_list():
		if m.name == "council":
			has = true
	if not has:
		missing.append("SimData.council()")
	var w = SimWorld.new(1, {"blank": true})
	if not w.stats.has("council") or not w.stats.council.has("chapters"):
		missing.append("stats.council.chapters")
	t.check(missing.is_empty(), "missing API: " + ", ".join(PackedStringArray(missing)))
	if missing.is_empty():
		_begin(t)
	return missing.is_empty()


class Hud extends RefCounted:
	var sim: Node
	var main: Control

	func free_all() -> void:
		main.free()
		sim.free()


func _hud(n: int = 12) -> Hud:
	var w = SimWorld.new(1, {"blank": true})
	w.add_building("reactor", 0, 0)
	var ha: int = w.add_building("habitat", 40, 0)
	w.add_building("green_room", 80, 0)
	w.add_building("habitat", 120, 0)
	for i in n:
		var b = w.add_being(ha)
		b.energy = 70.0
	w.colony.oxygen = w.colony.o2_cap()
	w.colony.food = w.colony.food_cap()
	w.colony.ice = 1000.0
	var h := Hud.new()
	h.sim = load("res://view/sim_host.gd").new()
	h.sim.world = w
	h.main = (load("res://view/main.tscn") as PackedScene).instantiate()
	h.main.setup(h.sim)
	return h


func _txt(main: Control, name: String) -> String:
	var l := main.get_node_or_null("Margin/HBox/VBox/" + name) as Label
	return l.text if l != null else ""


func _all_text(main: Control) -> String:
	var out := ""
	for n in LABELS:
		out += _txt(main, n) + "\n"
	return out


func _age(age: String, how: String, text: String, tt: float, clock_sol: int) -> Dictionary:
	return {"age": age, "how": how, "cause": null, "text": text, "pop": 12, "family_mars_born": 0,
			"t": tt, "sol": clock_sol - 1, "clock_sol": clock_sol}


func _pledge(text: String, tt: float, clock_sol: int) -> Dictionary:
	return {"kind": "pledge", "topic": "dome", "text": text, "t": tt, "sol": clock_sol - 1, "clock_sol": clock_sol}


func _lines(h: Hud) -> Array:
	var out: Array = []
	for l in _txt(h.main, "Chapters").split("\n"):
		if l.strip_edges() != "":
			out.append(l)
	return out


func test_t19a_the_age_word_is_council_from_council_data(t) -> void:
	if not _api(t):
		return
	var h := _hud()
	var w = h.sim.world
	var name := str(SimData.load_json("council.json").age.name)
	t.eq(name, "Council", "data: the age word")
	w.stats.age = "council"
	h.main.refresh()
	var parts := _txt(h.main, "Clock").split("  |  ")
	t.eq(parts[parts.size() - 1], name, "the clock line ends with the Council word")
	t.eq(parts.size(), 5, "five parts as for the other ages")
	t.check(RegEx.create_from_string("[0-9]").search(parts[parts.size() - 1]) == null, "the word alone, no digit")
	# the word is data
	var cd: Dictionary = SimData.load_json("council.json")
	var old = cd.age.name
	cd.age["name"] = "Moot"
	h.main.refresh()
	t.check(_txt(h.main, "Clock").ends_with("Moot"), "the word comes from SimData.council()")
	cd.age["name"] = old
	# the other ages keep their words
	w.stats.age = "settlement"
	h.main.refresh()
	t.check(_txt(h.main, "Clock").ends_with(str(SimData.load_json("ages.json").settlement.name)), "Settlement keeps its word")
	w.stats.age = "council"
	w.beings.clear()
	h.main.refresh()
	t.eq(_txt(h.main, "Clock").split("  |  ").size(), 4, "pop 0 hides the word, as for the other ages")
	t.check(not SimData.load_json("ages.json").has("council"), "ages.json has no Council key")
	h.free_all()
	_end(t)


func test_t19b_the_strip_shows_three_merged_chapters_in_time_order(t) -> void:
	if not _api(t):
		return
	var h := _hud()
	var w = h.sim.world
	w.stats.age_history = [
		_age("landing", "landing", "Landing text.", 0.0, 1),
		_age("settlement", "settled", "Settled text. More.", 100.0, 5),
		_age("council", "council", "Council text. More.", 200.0, 9)]
	w.stats.council.chapters = [_pledge("The council has agreed to build a dome. Lena spoke for it first.", 300.0, 14)]
	h.main.refresh()
	t.eq(_lines(h), ["sol 5  Settled text.", "sol 9  Council text.", "sol 14  The council has agreed to build a dome."],
			"the latest three of the merged four, oldest first, one first sentence each")
	t.eq(int(SimData.load_json("ages.json").hud.chapters_shown), 3, "data: three shown")
	# two entries only: both, none invented
	w.stats.age_history = [_age("landing", "landing", "Landing text.", 0.0, 1)]
	w.stats.council.chapters = []
	h.main.refresh()
	t.eq(_lines(h), ["sol 1  Landing text."], "no chapters: the age entries alone")
	# a tie on t: the age entry comes first
	w.stats.age_history = [_age("landing", "landing", "Landing text.", 0.0, 1), _age("council", "council", "Council text.", 50.0, 6)]
	w.stats.council.chapters = [_pledge("The council has agreed to build a dome.", 50.0, 6)]
	h.main.refresh()
	t.eq(_lines(h), ["sol 1  Landing text.", "sol 6  Council text.", "sol 6  The council has agreed to build a dome."], "a tie: the age entry first")
	h.free_all()
	_end(t)


func test_t19c_the_pledge_stays_pinned(t) -> void:
	if not _api(t):
		return
	var h := _hud()
	var w = h.sim.world
	w.stats.age_history = [
		_age("landing", "landing", "Landing text.", 0.0, 1),
		_age("settlement", "settled", "Settled text.", 100.0, 5),
		_age("council", "council", "Council text.", 200.0, 9),
		_age("landing", "fell_back", "Fell back text.", 400.0, 17),
		_age("settlement", "settled_again", "Settled again text.", 500.0, 21),
		_age("council", "council_again", "Council again text.", 600.0, 25)]
	w.stats.council.chapters = [_pledge("The council has agreed to build a dome. Lena spoke for it first.", 300.0, 13)]
	h.main.refresh()
	t.eq(_lines(h), ["sol 13  The council has agreed to build a dome.", "sol 21  Settled again text.", "sol 25  Council again text."],
			"three later age entries: the latest two and the pledge, in time order")
	t.eq(_lines(h).size(), 3, "the strip stays three lines")
	# with only two later entries the pledge is among the latest three and nothing is pushed
	w.stats.age_history = w.stats.age_history.slice(0, 5)
	h.main.refresh()
	t.eq(_lines(h), ["sol 13  The council has agreed to build a dome.", "sol 17  Fell back text.", "sol 21  Settled again text."],
			"the pledge among the latest three: plain rule")
	# no pledge: the plain rule
	w.stats.council.chapters = []
	h.main.refresh()
	t.eq(_lines(h).size(), 3, "no pledge: the latest three entries")
	h.free_all()
	_end(t)


func _code_only(src: String) -> String:
	var out: Array[String] = []
	for line in src.split("\n"):
		var s := line
		var i := s.find("#")
		if i >= 0:
			s = s.substr(0, i)
		out.append(s)
	return "\n".join(out)


func _view_scripts(dir: String = "res://view") -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_view_scripts(dir + "/" + d))
	return out


func test_t19d_the_hud_source_reads_no_hidden_council_state(t) -> void:
	if not _api(t):
		return
	var files := _view_scripts()
	t.check(files.has("res://view/main.gd") and files.size() > 5, "the scan covers the view folders (%d files)" % files.size())
	# world.council (the module), any stats.council key but chapters, and the words of the private readings
	var bad := RegEx.create_from_string("(?<!stats)(?<!SimData)\\.council\\b|stats\\.council\\.(?!chapters\\b)\\w+|\\bstance(_of)?\\b|\\blean_of\\b|\\bsession_log\\b|\\btrust_by_sol\\b|\\bchosen_by_sol\\b|\\bpledge_sol\\b|\\blines_dropped\\b")
	for f in files:
		var code := _code_only(FileAccess.get_file_as_string(f))
		var m := bad.search(code)
		t.check(m == null, "%s reads hidden Council state: %s" % [f, m.get_string() if m else ""])
	t.check(bad.search("var a = world.council.stance_of(3)") != null, "scan catches the module")
	t.check(bad.search("var a = w.stats.council.trust_by_sol") != null, "scan catches a reading")
	t.check(bad.search("var a = w.stats.council.sessions") != null, "scan catches another stats key")
	t.check(bad.search("var a = w.stats.council.chapters") == null, "scan allows the chapters")
	t.check(bad.search("var a = SimData.council().age") == null, "scan allows the data accessor")
	var main_src := _code_only(FileAccess.get_file_as_string("res://view/main.gd"))
	t.check(main_src.contains("SimData.council()"), "the HUD reads the Council word through SimData.council()")
	t.check(main_src.contains("council.chapters"), "and the chapters from stats.council.chapters")
	_end(t)


func test_t19e_no_number_or_bar_appears_in_a_council_hud(t) -> void:
	if not _api(t):
		return
	var h := _hud()
	var w = h.sim.world
	w.stats.age = "council"
	w.stats.council["trust"] = 0.77
	w.stats.council["chosen"] = 0.61
	w.stats.council["voices"] = 31
	w.stats.council["sessions"] = 17
	h.main.refresh()
	var all := _all_text(h.main).to_lower()
	for word in ["trust", "chosen", "support", "vote", "stance", "session", "meeting", "until", "0.77", "0.61", "77%", "61%"]:
		t.check(not all.contains(word), "the HUD never shows '%s'" % word)
	h.free_all()
	_end(t)


func test_t22a_with_the_module_off_the_hud_shows_no_council_word(t) -> void:
	if not _api(t):
		return
	var w = SimWorld.new(1, {"blank": true})
	w.council_enabled = false
	t.check(w.stats.age != "council", "the age is not council with the module off")
	var h := _hud()
	h.sim.world.council_enabled = false
	h.main.refresh()
	t.check(not _txt(h.main, "Clock").contains(str(SimData.load_json("council.json").age.name)), "no Council word on the clock line")
	h.free_all()
	_end(t)
