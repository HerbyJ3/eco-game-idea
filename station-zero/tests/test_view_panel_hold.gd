extends RefCounted
## Task 6a view step: spec docs/specs/emotions.md section 13 test 33 (PanelHold: refresh rate, band hold, died beat, purity).
## Moved out of tests/deferred/ at plan step 8 (view).

const PanelHold = preload("res://view/model/panel_hold.gd")


func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func _cfg() -> Dictionary:
	return SimData.load_json("mood.json").selection


func test_t33a_the_shown_band_changes_at_most_once_per_hold(t) -> void:
	t._failures.append(_abort_msg(t))
	var c := _cfg()
	var h = PanelHold.new(c)
	var hold := float(c.hold_s)
	var changes := 0
	var shown := h.shown_band(0.0, 2)
	# 1000x: the sim changes band every 20 ms of real time for 3 real seconds.
	var now := 0.0
	var wanted := 2
	var last_change := -1e9
	var min_gap := 1e9
	while now < 3.0:
		wanted = 1 if wanted == 2 else 2
		var s: int = h.shown_band(now, wanted)
		if s != shown:
			changes += 1
			min_gap = minf(min_gap, now - last_change)
			last_change = now
			shown = s
		now += 0.02
	t.check(changes >= 1, "staging: the shown band did follow the sim (%d changes)" % changes)
	t.check(changes <= int(ceil(3.0 / hold)) + 1, "at most one change per hold_s (%d in 3 s)" % changes)
	if changes >= 2:
		t.check(min_gap >= hold - 1e-9, "consecutive changes at least hold_s apart (%.3f)" % min_gap)
	t._failures.erase(_abort_msg(t))


func test_t33b_refresh_is_served_at_most_refresh_hz_times_a_second(t) -> void:
	t._failures.append(_abort_msg(t))
	var c := _cfg()
	var h = PanelHold.new(c)
	var served := 0
	var now := 0.0
	while now < 4.0:
		if h.refresh_due(now):
			served += 1
		now += 1.0 / 60.0
	t.check(served <= int(float(c.refresh_hz) * 4.0) + 1, "at most refresh_hz refreshes a second (%d in 4 s)" % served)
	t.check(served >= int(float(c.refresh_hz) * 4.0) - 1, "and not starved (%d in 4 s)" % served)
	t._failures.erase(_abort_msg(t))


func test_t33c_the_died_beat_shows_then_closes(t) -> void:
	t._failures.append(_abort_msg(t))
	var c := _cfg()
	var h = PanelHold.new(c)
	h.begin_died(10.0)
	t.check(h.died_open(10.0), "open at once")
	t.check(h.died_open(10.0 + float(c.died_beat_s) - 0.01), "open until died_beat_s")
	t.check(not h.died_open(10.0 + float(c.died_beat_s) + 0.01), "closed after died_beat_s")
	t._failures.erase(_abort_msg(t))


func test_t33d_it_touches_no_sim_state(t) -> void:
	t._failures.append(_abort_msg(t))
	var src := FileAccess.get_file_as_string("res://view/model/panel_hold.gd")
	t.check(src.length() > 0, "the helper exists")
	for word in ["SimWorld", "world", "SimRng", "Time.", "OS.", "stats"]:
		t.check(src.find(word) < 0, "panel_hold.gd does not mention %s" % word)
	t._failures.erase(_abort_msg(t))
