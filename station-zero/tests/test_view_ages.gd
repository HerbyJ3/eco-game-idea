extends RefCounted
## Task 3, step 3: the HUD half of spec docs/specs/ages.md section 10 test 19 and the speed-readout half of test 20
## (section 9). Green since steps 6 (test 19) and 11 (test 20 readout). The sim half of test 20 (budget) is in
## tests/test_ages.gd.
##
## Method as tests/test_view.gd: the HUD scene is instantiated and bound by hand (main.setup(sim)); the sim host is not in
## the tree, so nothing steps. The HUD is read through its Label nodes after main.refresh() / main._process(delta).
##
## API ASSUMED (HUD steps; the spec names the behaviour, not the nodes):
##  - the chapters strip is a Label node `Margin/HBox/VBox/Chapters`, between Site/Beings and Log, text one entry per line
##    as `sol N  text` (two spaces, N = the entry's clock_sol), the last `ages.hud.chapters_shown` entries of
##    world.stats.age_history, oldest first, newest last; no other line is needed (a heading line is tolerated: the tests
##    look for `sol N  text` substrings and count the entry texts they find, not lines).
##  - the age is the last `  |  `-separated part of the Clock label (data name of stats.age), absent at pop 0.
##  - the resource word is appended to the Oxygen / Food / Ice lines of the Colony label.
##  - the speed readout lives in the Controls label (Speed: Nx max (running about Mx)) and the throttle sentence appears in
##    the HUD text (any label; the tests search all of them). The achieved speed is measured from the world's t over the
##    sum of the _process(delta) deltas the HUD has seen (so the test drives it without a wall clock): a frame of 0.1 s in
##    which world.t advanced by H hours reads H / 0.1 hours per real second, and one hour per real second is "1x"
##    (data/sim.json real_seconds_per_hour_at_1x = 1.0). The achieved figure is rounded to a whole number in the text.
##  - HUD refresh cadence in the tests: each main._process(0.1) refreshes the labels (REFRESH_S = 0.1).

const LABELS := ["Clock", "Colony", "Power", "Site", "Beings", "Chapters", "Log", "Controls"]
const THROTTLE := "The colony is too large to run this fast."


## Abort guard. The runner only fails a test that made no checks, so a runtime error in the code under test that aborts a
## test after some checks have passed would be reported as a pass. _begin records a failure that _end (the last line of
## every test) removes again; a test that never reaches its last line stays failed.
func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func _begin(t) -> void:
	t._failures.append(_abort_msg(t))


func _end(t) -> void:
	t._failures.erase(_abort_msg(t))


func _ad() -> Dictionary:
	return SimData.load_json("ages.json")


class Hud extends RefCounted:
	var sim: Node
	var main: Control

	func free_all() -> void:
		main.free()
		sim.free()


## A blank world with a reactor, two habitats, a green room and `n` beings, shown in the HUD scene.
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


func _label(main: Control, name: String) -> Label:
	return main.get_node_or_null("Margin/HBox/VBox/" + name) as Label


func _txt(main: Control, name: String) -> String:
	var l := _label(main, name)
	return l.text if l != null else ""


func _all_text(main: Control) -> String:
	var out := ""
	for n in LABELS:
		out += _txt(main, n) + "\n"
	return out


func _line_starting(text: String, prefix: String) -> String:
	for l in text.split("\n"):
		if l.strip_edges().begins_with(prefix):
			return l
	return ""


# ---------------------------------------------------------------- 19. clock line

func test_t19_clock_line_ends_with_the_age_name(t) -> void:
	_begin(t)
	var h := _hud()
	var w = h.sim.world
	h.main.refresh()
	var parts := _txt(h.main, "Clock").split("  |  ")
	t.eq(parts.size(), 5, "clock line: site | year, sol | time | season | age (5 parts): %s" % _txt(h.main, "Clock"))
	if parts.size() == 5:
		t.eq(parts[4], _ad().landing.name, "last part is the Landing name from data")
		t.check(RegEx.create_from_string("[0-9]").search(parts[4]) == null, "the age part has no digit")
		t.eq(parts[3], w.clock.season(w.t), "the age follows the season")
	w.stats.age = "settlement"
	h.main.refresh()
	var parts2 := _txt(h.main, "Clock").split("  |  ")
	t.eq(parts2[parts2.size() - 1], _ad().settlement.name, "Settlement name after the age changes")
	t.check(RegEx.create_from_string("[0-9]").search(parts2[parts2.size() - 1]) == null, "name only, no digit (no sol count)")
	# The age part is the name alone: no count of sols, no share, no 'until'.
	var low: String = _txt(h.main, "Clock").to_lower()
	t.check(not low.contains("until") and not low.contains("%"), "no progress words in the clock line")
	# Pop 0: no age word, stats.age keeps its last value.
	w.beings.clear()
	h.main.refresh()
	var parts3 := _txt(h.main, "Clock").split("  |  ")
	t.eq(parts3.size(), 4, "pop 0: four parts, the age is hidden: %s" % _txt(h.main, "Clock"))
	t.check(not _txt(h.main, "Clock").contains(_ad().settlement.name), "pop 0: no Settlement word")
	t.check(not _txt(h.main, "Clock").contains(_ad().landing.name), "pop 0: no Landing word")
	t.eq(w.stats.age, "settlement", "the HUD did not touch stats.age")
	h.free_all()
	_end(t)


# ---------------------------------------------------------------- 19. chapters strip

func _entry(age: String, how: String, text: String, sol: int, clock_sol: int) -> Dictionary:
	return {"age": age, "how": how, "cause": null, "text": text, "pop": 12, "family_mars_born": 0,
			"t": 0.0, "sol": sol, "clock_sol": clock_sol}


## The strip shows the text up to and including the first ". " (spec ages.md section 9).
func _first(text: String) -> String:
	var i := text.find(". ")
	return text if i < 0 else text.substr(0, i + 1)


func _shown(strip: String, entries: Array) -> Array:
	var out: Array = []
	for e in entries:
		if strip.contains("sol %d  %s" % [int(e.clock_sol), e.text]):
			out.append(e.text)
	return out


func test_t19_chapters_strip(t) -> void:
	_begin(t)
	var h := _hud()
	var w = h.sim.world
	var strip_label := _label(h.main, "Chapters")
	t.check(strip_label != null, "the HUD has a Chapters label (Margin/HBox/VBox/Chapters)")
	if strip_label == null:
		h.free_all()
		_end(t)
		return
	t.eq(int(_ad().hud.chapters_shown), 3, "data: chapters_shown")
	# One entry (the landing): shown as `sol N  text` with N the 1-based clock sol, not the elapsed sol.
	var landing: Dictionary = w.stats.age_history[0] if w.stats.has("age_history") and w.stats.age_history.size() > 0 else _entry("landing", "landing", "Landing text.", 0, 1)
	w.stats.age_history = [landing]
	h.main.refresh()
	t.check(_txt(h.main, "Chapters").contains("sol %d  %s" % [int(landing.clock_sol), _first(landing.text)]), "one entry: `sol N  first sentence`")
	t.check(not _txt(h.main, "Chapters").contains(str(landing.text).substr(_first(landing.text).length())) or _first(landing.text) == landing.text, "only the first sentence of the landing text is shown")
	# Five entries: only the latest three, oldest first, using clock_sol (45), not sol (44).
	var hist := [
		_entry("landing", "landing", "Chapter one text.", 0, 1),
		_entry("settlement", "settled", "Chapter two text.", 44, 45),
		_entry("landing", "fell_back", "Chapter three text.", 64, 65),
		_entry("settlement", "settled_again", "Chapter four text.", 100, 101),
		_entry("landing", "fell_back", "Chapter five text.", 160, 161),
	]
	w.stats.age_history = hist
	h.main.refresh()
	var strip := _txt(h.main, "Chapters")
	t.eq(_shown(strip, hist), ["Chapter three text.", "Chapter four text.", "Chapter five text."], "the latest three entries, in order")
	t.check(not strip.contains("sol 44  ") and not strip.contains("sol 64  "), "the lines use clock_sol, not the elapsed sol")
	t.check(strip.find("Chapter three") < strip.find("Chapter four") and strip.find("Chapter four") < strip.find("Chapter five"), "oldest first")
	# The count is data.
	_ad().hud["chapters_shown"] = 2
	h.main.refresh()
	t.eq(_shown(_txt(h.main, "Chapters"), hist), ["Chapter four text.", "Chapter five text."], "chapters_shown 2 shows two")
	_ad().hud["chapters_shown"] = 3
	# Fewer entries than the limit: all shown, none invented.
	w.stats.age_history = hist.slice(0, 2)
	h.main.refresh()
	t.eq(_shown(_txt(h.main, "Chapters"), hist).size(), 2, "two entries: two shown")
	# The Landing entry survives 100 routine log lines (the log shows 8, the strip reads age_history).
	w.stats.age_history = [landing]
	for i in 100:
		w._log("born", "Routine line %d." % i)
	h.main.refresh()
	t.check(not _txt(h.main, "Log").contains(landing.text), "the 8-line log has scrolled the landing line away")
	t.check(_txt(h.main, "Chapters").contains(_first(landing.text)), "the strip still shows the Landing entry after 100 routine lines")
	# Age lines in the log keep appearing in the log itself (unchanged behaviour): the strip is additional.
	w._log("age_began", "An age line.", {"age": "settlement", "how": "settled"})
	h.main.refresh()
	t.check(_txt(h.main, "Log").contains("An age line."), "the log still lists age lines")
	# Eviction: even after the world log is capped at 500 lines the strip still has the entry.
	for i in 520:
		w._log("born", "More %d." % i)
	h.main.refresh()
	t.eq(w.log.size(), 500, "the world log is capped")
	t.check(_txt(h.main, "Chapters").contains(_first(landing.text)), "log eviction does not touch the strip")
	# Three chapters, one line each, first sentence only, `sol N  first sentence`.
	var multi := [
		_entry("landing", "landing", "The founders have landed at Jezero. For now, air is all.", 0, 1),
		_entry("settlement", "settled", "Nobody is only surviving now. There are families here.", 44, 45),
		_entry("landing", "fell_back", "Hard days have come back to Jezero. Water is on everyone's mind. Spring is rising.", 64, 65),
	]
	w.stats.age_history = multi
	h.main.refresh()
	t.eq(_txt(h.main, "Chapters"), "sol 1  The founders have landed at Jezero.\nsol 45  Nobody is only surviving now.\nsol 65  Hard days have come back to Jezero.", "exactly three lines, first sentences")
	h.free_all()
	_end(t)


# ---------------------------------------------------------------- 19. resource words

func test_t19_resource_words_at_the_sample_thresholds(t) -> void:
	_begin(t)
	var h := _hud()
	var w = h.sim.world
	var word: String = _ad().hud.low_word
	t.eq(word, "running low", "data: low_word")
	t.eq(w.colony.o2_cap(), 550.0, "o2 cap")
	t.eq(w.colony.food_cap(), 420.0, "food cap")
	for age_id in ["landing", "settlement"]:
		w.stats.age = age_id
		# Good stocks: no word anywhere in the colony block.
		h.main.refresh()
		t.check(not _txt(h.main, "Colony").contains(word), "%s: nothing running low" % age_id)
		# Oxygen: exactly 0.5 x cap is not low, just under is.
		w.colony.oxygen = 275.0
		h.main.refresh()
		t.check(not _line_starting(_txt(h.main, "Colony"), "Oxygen").contains(word), "%s: oxygen 275.0 of 550 is not low" % age_id)
		w.colony.oxygen = 274.9
		h.main.refresh()
		var col := _txt(h.main, "Colony")
		t.check(_line_starting(col, "Oxygen").contains(word), "%s: oxygen 274.9 is low" % age_id)
		t.check(not _line_starting(col, "Food").contains(word) and not _line_starting(col, "Ice").contains(word), "%s: only the oxygen line says it" % age_id)
		w.colony.oxygen = w.colony.o2_cap()
		# Food: 210 of 420.
		w.colony.food = 210.0
		h.main.refresh()
		t.check(not _line_starting(_txt(h.main, "Colony"), "Food").contains(word), "%s: food 210.0 of 420 is not low" % age_id)
		w.colony.food = 209.9
		h.main.refresh()
		col = _txt(h.main, "Colony")
		t.check(_line_starting(col, "Food").contains(word), "%s: food 209.9 is low" % age_id)
		t.check(not _line_starting(col, "Oxygen").contains(word), "%s: oxygen line quiet" % age_id)
		w.colony.food = w.colony.food_cap()
		# Ice: exactly 2 sols of use at the current population is not low; 1e-6 under is.
		var need: float = 2.0 * w.colony.pop() * float(SimData.colony().consumption.ice_per_being) * w.clock.sol_h
		w.colony.ice = need
		h.main.refresh()
		t.check(not _line_starting(_txt(h.main, "Colony"), "Ice").contains(word), "%s: ice at exactly 2 sols is not low" % age_id)
		w.colony.ice = need - 1e-6
		h.main.refresh()
		col = _txt(h.main, "Colony")
		t.check(_line_starting(col, "Ice").contains(word), "%s: ice 1e-6 under 2 sols is low" % age_id)
		t.check(not _line_starting(col, "Regolith").contains(word), "%s: the regolith line never says it" % age_id)
		w.colony.ice = 1000.0
	# More beings need more ice: the same ice is fine for 12 and low for 40.
	w.colony.ice = 6.0
	h.main.refresh()
	t.check(not _line_starting(_txt(h.main, "Colony"), "Ice").contains(word), "6.0 ice for 12 beings is not low")
	for i in 28:
		w.add_being(2)
	w.colony.oxygen = w.colony.o2_cap()
	w.colony.food = w.colony.food_cap()
	h.main.refresh()
	t.check(_line_starting(_txt(h.main, "Colony"), "Ice").contains(word), "6.0 ice for 40 beings is low")
	# The word is data.
	_ad().hud["low_word"] = "scarce"
	h.main.refresh()
	t.check(_line_starting(_txt(h.main, "Colony"), "Ice").contains("scarce"), "low_word comes from data")
	_ad().hud["low_word"] = "running low"
	h.free_all()
	_end(t)


# ---------------------------------------------------------------- 19. the HUD reads no hidden state

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


func test_t19_hud_source_reads_no_hidden_ages_state(t) -> void:
	_begin(t)
	var files := _view_scripts()
	t.check(files.has("res://view/main.gd"), "the scan includes view/main.gd")
	t.check(files.size() > 5, "the scan recurses into the view subfolders (%d files)" % files.size())
	var has_world := false
	var has_model := false
	for f in files:
		has_world = has_world or f.begins_with("res://view/world/")
		has_model = has_model or f.begins_with("res://view/model/")
	t.check(has_world and has_model, "the scan includes view/world and view/model")
	var bad := RegEx.create_from_string("(?<!SimData)\\.ages\\b|\\blast_sample\\b|\\bsols_in_age\\b|\\bage_changes\\b")
	for f in files:
		var code := _code_only(FileAccess.get_file_as_string(f))
		t.check(code.length() > 100, "%s readable" % f)
		var m := bad.search(code)
		t.check(m == null, "%s reads hidden ages state: %s" % [f, m.get_string() if m else ""])
	# The scanner itself sees violations and allows the data accessor and stats.age.
	t.check(bad.search("var a = world.ages.window") != null, "scan catches world.ages")
	t.check(bad.search("var a = w.stats.sols_in_age") != null, "scan catches sols_in_age")
	t.check(bad.search("var a = w.ages.last_sample") != null, "scan catches last_sample")
	t.check(bad.search("var a = w.stats.age_changes") != null, "scan catches age_changes")
	t.check(bad.search("var a = SimData.ages().hud") == null, "scan allows SimData.ages()")
	t.check(bad.search("var a = w.stats.age_history") == null, "scan allows stats.age_history")
	t.check(bad.search("var a = w.stats.age") == null, "scan allows stats.age")
	# The HUD does read the age: main.gd mentions stats.age and the data accessor (it is the one consumer).
	var main_src := _code_only(FileAccess.get_file_as_string("res://view/main.gd"))
	t.check(main_src.contains("age_history"), "the HUD reads stats.age_history (chapters strip)")
	t.check(main_src.contains("stats.age"), "the HUD reads stats.age (clock line)")
	_end(t)


# ---------------------------------------------------------------- 20. speed readout

func _frames(h: Hud, n: int, hours_per_frame: float, dt: float = 0.1) -> void:
	for i in n:
		h.sim.world.t += hours_per_frame
		h.main._process(dt)


func _achieved(text: String) -> int:
	var m := RegEx.create_from_string("running about (\\d+)x").search(text)
	return int(m.get_string(1)) if m != null else -1


func test_t20_speed_readout_and_throttle_line(t) -> void:
	_begin(t)
	var h := _hud()
	h.main.set_speed(1000.0)
	# Requested 1000 hours per real second: 100 hours in a 0.1 s frame. Warm the 1.0 s window.
	_frames(h, 15, 100.0)
	var ctl := _txt(h.main, "Controls")
	t.check(ctl.contains("1000x max"), "the speed label is a maximum: %s" % ctl)
	var got := _achieved(_all_text(h.main))
	t.check(got >= 980 and got <= 1020, "achieved about 1000x when the world keeps up (read %d)" % got)
	t.check(not _all_text(h.main).contains(THROTTLE), "no throttle line when achieved >= 0.9 of requested")
	# 95 percent of the request: still no throttle line.
	_frames(h, 20, 95.0)
	got = _achieved(_all_text(h.main))
	t.check(got >= 930 and got <= 970, "achieved about 950x (read %d)" % got)
	t.check(not _all_text(h.main).contains(THROTTLE), "95 percent: no throttle line")
	# 85 percent: throttle line, plain words, and the readout says what is really running.
	_frames(h, 20, 85.0)
	got = _achieved(_all_text(h.main))
	t.check(got >= 830 and got <= 870, "achieved about 850x (read %d)" % got)
	t.check(_all_text(h.main).contains(THROTTLE), "below 0.9: the throttle line appears")
	# The figure is averaged over the window (1.0 s), not read from the last frame: frames alternating 100 and 70 hours
	# (ending on a 100) average 850x, below 0.9 of 1000.
	for i in 20:
		_frames(h, 1, 100.0 if i % 2 == 1 else 70.0)
	got = _achieved(_all_text(h.main))
	t.check(got >= 830 and got <= 870, "alternating 700x / 1000x frames read about 850x, not the last frame (read %d)" % got)
	t.check(_all_text(h.main).contains(THROTTLE), "and the average is below 0.9: throttled")
	# 5 percent: heavy throttling, readout follows.
	_frames(h, 20, 5.0)
	got = _achieved(_all_text(h.main))
	t.check(got >= 45 and got <= 55, "achieved about 50x (read %d)" % got)
	t.check(_all_text(h.main).contains(THROTTLE), "still throttled")
	t.check(_txt(h.main, "Controls").contains("1000x max"), "the label stays the requested maximum")
	# Recovery removes the line.
	_frames(h, 25, 100.0)
	t.check(not _all_text(h.main).contains(THROTTLE), "back to full speed: the line is gone")
	# Dropped hours are never shown as lost time.
	var low := _all_text(h.main).to_lower()
	t.check(not low.contains("lost") and not low.contains("dropped"), "no 'lost time' wording")
	# Paused: no throttle line, no claim of running.
	h.main.set_speed(0.0)
	_frames(h, 15, 0.0)
	t.check(not _all_text(h.main).contains(THROTTLE), "paused: no throttle line")
	h.free_all()
	_end(t)


## What the readout shows: the Controls label (the clock line moves with the world, so it is left out) and whether the
## throttle sentence is on screen anywhere.
func _readout_state(main: Control) -> String:
	return _txt(main, "Controls") + "|" + str(_all_text(main).contains(THROTTLE))


func test_t20_readout_refreshes_at_most_every_half_second(t) -> void:
	_begin(t)
	var h := _hud()
	h.main.set_speed(1000.0)
	_frames(h, 15, 100.0)
	var refresh_s := float(SimData.sim().speed_readout_refresh_s)
	t.eq(refresh_s, 0.5, "data: speed_readout_refresh_s")
	t.eq(float(SimData.sim().speed_readout_window_s), 1.0, "data: speed_readout_window_s")
	t.eq(float(SimData.sim().speed_throttle_below), 0.9, "data: speed_throttle_below")
	# The achieved speed swings every frame; the text must not follow every swing.
	var rates := [100.0, 20.0, 80.0, 10.0, 90.0, 40.0, 100.0, 30.0]
	var times: Array = []
	var last := _readout_state(h.main)
	var now := 0.0
	for i in 60:
		h.sim.world.t += float(rates[i % rates.size()])
		h.main._process(0.1)
		now += 0.1
		var cur := _readout_state(h.main)
		if cur != last:
			times.append(now)
			last = cur
	t.check(times.size() >= 3, "the readout does change as the speed does (%d changes in 6 s)" % times.size())
	var min_gap := 99.0
	for i in range(1, times.size()):
		min_gap = minf(min_gap, float(times[i]) - float(times[i - 1]))
	t.check(times.size() < 2 or min_gap >= refresh_s - 0.06, "the text never changes twice within 0.5 s (shortest gap %.2f s)" % min_gap)
	t.check(times.size() <= 13, "at most one change per refresh interval over 6 s (%d)" % times.size())
	h.free_all()
	_end(t)
