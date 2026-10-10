extends SceneTree
## Task 6a cost profile (docs/specs/emotions.md section 11; docs/perf/task-6a-cost.md). Timers live here, outside sim/.
##   godot --headless --path station-zero --script res://tools/mood_profile.gd -- --seed 1234 --sols 300 --moods on|off [--panel]
## Runs plain SimWorld.step() to --sols and times every step. Prints, for steps at pop > 120:
##   - all steps (median, mean), boundary steps (median, p95, max) and the mood tick (Moods.last_tick_ms on the steps where it ran);
##   - one "B sol pop total_us" line per boundary step, for pairing a run with --moods on against one with --moods off
##     (the gains are 0.0, so both runs are the same world step for step; the paired difference is the slice's cost);
## --padded [--ticks 300] [--pop 159] [--pairs 5278] instead builds the padded pop-159 world of tools/relationships_equiv.gd (the shipped
## data never reaches pop 120: peak 12 to 13 since the lifecycle rebaseline) and times, per relationships tick, the relationships tick
## (last_tick_ms), the mood tick (Moods.last_tick_ms), the sol hook (Moods.on_sol), the friend_pairs() copy, and whole SimWorld.step()
## with moods enabled and disabled, in alternating blocks.
## --panel then times the view helpers on the final world: BeingPanel.lines for ten beings, 200 calls each, and BeingHit.pick.

const PanelText = preload("res://view/model/being_panel.gd")
const BeingHit = preload("res://view/model/being_hit.gd")


static func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(floor(p * float(s.size()))))])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var seed_in := 42
	var sols := 300
	var on := true
	var panel := false
	var padded := false
	var i := 0
	while i < a.size():
		match a[i]:
			"--seed":
				i += 1
				seed_in = int(a[i])
			"--sols":
				i += 1
				sols = int(a[i])
			"--moods":
				i += 1
				on = a[i] == "on"
			"--panel":
				panel = true
			"--padded":
				padded = true
		i += 1
	if padded:
		_padded(a)
		quit(0)
		return
	var w := SimWorld.new(seed_in, {"moods_enabled": on})
	var all_hi: Array = []
	var bound_hi: Array = []
	var tick_hi: Array = []
	var total_us := 0
	var n := 0
	while w.sol() < sols:
		var pop := w.colony.pop()
		var seen: int = w.moods.seen_ticks if on else 0
		var t0 := Time.get_ticks_usec()
		w.step()
		var us := Time.get_ticks_usec() - t0
		total_us += us
		n += 1
		if pop > 120:
			all_hi.append(us)
			if w._sol_started:
				bound_hi.append(us)
				print("B %d %d %d" % [w.sol(), pop, us])
			if on and w.moods.seen_ticks != seen:
				tick_hi.append(w.moods.last_tick_ms)
	print("seed %d sols %d moods %s steps %d mean_step_us %.1f" % [seed_in, sols, on, n, float(total_us) / float(maxi(1, n))])
	print("pop>120 all steps: n %d median %.0f mean %.1f us" % [all_hi.size(), _pct(all_hi, 0.5), _mean(all_hi)])
	print("pop>120 boundary steps: n %d median %.0f p95 %.0f max %.0f us" % [bound_hi.size(), _pct(bound_hi, 0.5), _pct(bound_hi, 0.95), _pct(bound_hi, 1.0)])
	if on:
		print("pop>120 mood tick (ms): n %d median %.3f p95 %.3f max %.3f" % [tick_hi.size(), _pct(tick_hi, 0.5), _pct(tick_hi, 0.95), _pct(tick_hi, 1.0)])
	if panel:
		_panel(w)
	quit(0)


static func _mean(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(maxi(1, a.size()))


func _panel(w: SimWorld) -> void:
	var lines_us: Array = []
	var ids: Array = []
	for k in mini(10, w.beings.size()):
		ids.append(w.beings[k * w.beings.size() / mini(10, w.beings.size())].id)
	for id in ids:
		for r in 200:
			var t0 := Time.get_ticks_usec()
			PanelText.lines(w, id)
			lines_us.append(Time.get_ticks_usec() - t0)
	print("panel lines() at pop %d: n %d median %.0f p95 %.0f max %.0f us" % [w.beings.size(), lines_us.size(), _pct(lines_us, 0.5), _pct(lines_us, 0.95), _pct(lines_us, 1.0)])
	var recs := {}
	for g in w.beings:
		recs[g.id] = {"pos": Vector2(float(g.id) * 7.0, 50.0), "height_px": 20.0, "visible": true, "inside": false, "building_id": 0}
	var cfg := PanelText.selection_cfg()
	var cut := func(_b: int) -> float: return 0.0
	var hit_us: Array = []
	for r in 500:
		var t0 := Time.get_ticks_usec()
		BeingHit.pick(Vector2(float(r), 40.0), recs, cut, 2.0, cfg)
		hit_us.append(Time.get_ticks_usec() - t0)
	print("BeingHit.pick at %d records: median %.0f p95 %.0f max %.0f us" % [recs.size(), _pct(hit_us, 0.5), _pct(hit_us, 0.95), _pct(hit_us, 1.0)])


func _padded(a: PackedStringArray) -> void:
	var ticks := 300
	var pop := 159
	var pairs_n := 5278
	for k in a.size():
		if a[k] == "--ticks":
			ticks = int(a[k + 1])
		elif a[k] == "--pop":
			pop = int(a[k + 1])
		elif a[k] == "--pairs":
			pairs_n = int(a[k + 1])
	var eq: GDScript = load("res://tools/relationships_equiv.gd")
	var w: SimWorld = eq.build(pop, pairs_n)
	var r: Relationships = w.relationships
	var rel_ms: Array = []
	var mood_ms: Array = []
	var sol_us: Array = []
	var fp_us: Array = []
	for i in ticks:
		r.on_step(w, 1.0)
		rel_ms.append(r.last_tick_ms)
		w.moods.on_step(w)
		mood_ms.append(w.moods.last_tick_ms)
		var t0 := Time.get_ticks_usec()
		w.moods.on_sol(w)
		sol_us.append(Time.get_ticks_usec() - t0)
		t0 = Time.get_ticks_usec()
		r.friend_pairs()
		fp_us.append(Time.get_ticks_usec() - t0)
	print("padded world pop %d pairs %d (stored at end %d), %d ticks" % [w.beings.size(), pairs_n, r.pairs.size(), ticks])
	print("relationships tick (ms): median %.3f p95 %.3f max %.3f" % [_pct(rel_ms, 0.5), _pct(rel_ms, 0.95), _pct(rel_ms, 1.0)])
	print("mood tick (ms): median %.3f p95 %.3f max %.3f" % [_pct(mood_ms, 0.5), _pct(mood_ms, 0.95), _pct(mood_ms, 1.0)])
	print("mood on_sol (us): median %.0f p95 %.0f max %.0f" % [_pct(sol_us, 0.5), _pct(sol_us, 0.95), _pct(sol_us, 1.0)])
	print("friend_pairs() copy (us): median %.0f p95 %.0f max %.0f" % [_pct(fp_us, 0.5), _pct(fp_us, 0.95), _pct(fp_us, 1.0)])
	# Whole step, moods on and off in alternating blocks of 200 steps on two identical padded worlds.
	var wa: SimWorld = eq.build(pop, pairs_n)
	var wb: SimWorld = eq.build(pop, pairs_n)
	wb.moods_enabled = false
	var on_us := 0
	var off_us := 0
	var n_on := 0
	for blk in 10:
		for j in 200:
			var t0 := Time.get_ticks_usec()
			wa.step()
			on_us += Time.get_ticks_usec() - t0
			n_on += 1
			t0 = Time.get_ticks_usec()
			wb.step()
			off_us += Time.get_ticks_usec() - t0
	_panel(w)
	print("whole step, %d steps each, padded world: moods on %.1f us mean, off %.1f us mean, difference %.1f us (%.2f percent of the on mean)" % [
			n_on, float(on_us) / n_on, float(off_us) / n_on, float(on_us - off_us) / n_on, 100.0 * float(on_us - off_us) / float(on_us)])
