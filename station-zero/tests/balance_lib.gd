extends RefCounted
## Balance run core (spec sections 13, 15, 16; plan section 4). Used by tests/balance_run.gd (CLI) and
## tests/test_determinism.gd. Loaded with load(), not class_name, so no class cache is needed.
## run() returns {lines, table_hash, verdicts}; it never prints. Overrides touch the SimData cache for
## the duration of the call only and are restored before returning.

const KINDS := ["reactor", "habitat", "workshop", "green_room", "archive", "comms"]
const KIND_ABBR := ["R", "H", "W", "G", "A", "C"]


## Sets `path` ("colony.birth.cooldown_sols") in the SimData cache. Returns the old value, or an
## {"error": text} dictionary wrapper via the second return slot.
static func apply_param(path: String, value: Variant, saved: Array) -> String:
	var parts := path.split(".")
	if parts.size() < 2:
		return "bad path %s" % path
	var node: Variant = SimData.load_json(parts[0] + ".json")
	if node == null:
		return "no data file %s.json" % parts[0]
	for i in range(1, parts.size() - 1):
		if not (node is Dictionary) or not node.has(parts[i]):
			return "no key %s" % path
		node = node[parts[i]]
	var leaf := parts[parts.size() - 1]
	if not (node is Dictionary) or not node.has(leaf):
		return "no key %s" % path
	saved.append([node, leaf, node[leaf]])
	node[leaf] = value
	return ""


static func parse_value(text: String) -> Variant:
	var v: Variant = JSON.parse_string(text)
	return text if v == null and text != "null" else v


static func data_hash() -> String:
	var parts: Array[String] = []
	for f in ["calendar", "signs", "persona", "sim", "colony", "buildings", "beings", "resources", "suits", "ages"]:
		parts.append(JSON.stringify(SimData.load_json(f + ".json"), "", true))
	return "\n".join(parts).sha256_text()


static func _pct(a: float, b: float) -> float:
	return 100.0 * a / b if b > 0.0 else 0.0


static func _fmt_min(v: Variant) -> String:
	return "-" if v == null else "%.1f" % float(v)


static func run(seed_in: int, sols: int, params: Dictionary = {}, row_every: int = 30) -> Dictionary:
	var saved: Array = []
	var lines: Array[String] = []
	for k in params:
		var err := apply_param(str(k), params[k], saved)
		if err != "":
			lines.append("PARAM ERROR: %s" % err)
	var w := SimWorld.new(seed_in)
	var pstr := " ".join(PackedStringArray(params.keys().map(func(k): return "%s=%s" % [k, str(params[k])])))
	lines.append("# station zero balance run: seed=%d sols=%d overrides=[%s] fixed_step=%s data_hash=%s" % [
			seed_in, sols, pstr, str(w.fixed_step), data_hash().substr(0, 16)])
	lines.append("# deaths and births are cumulative; shorts, trips, energy, asleep, wait, min_* are for the 30-sol window")
	var body: Array[String] = []
	var head := "%4s %4s %4s %5s %-23s %7s %7s %7s %7s %6s %6s %5s %-17s %5s %5s %5s %6s %6s %6s %6s" % [
			"sol", "pop", "min", "birth", "dead a/t/h/o/x", "oxygen", "food", "ice", "regol",
			"dmnd", "supp", "short", "bldg R/H/W/G/A/C", "reach", "trips", "avgE", "asleep%", "waitH", "minIce", "minO2"]
	body.append(head)
	var prev := {"shorts": 0, "trips": 0}
	var rows: Array[Dictionary] = []
	var sol_h: float = w.clock.sol_h
	var total_steps := 0
	while w.sol() < sols:
		w.step()
		total_steps += 1
		var s := w.sol()
		if s % row_every != 0 or s == 0 or not w._sol_started:
			continue
		var st: Dictionary = w.stats
		var win: Dictionary = st.window
		var d: Dictionary = st.deaths
		var counts: Array[String] = []
		for k in KINDS:
			counts.append(str(w.buildings.count_online(k)))
		var avg_e: float = float(win.energy_sum) / maxf(1.0, float(win.being_steps))
		var asleep := _pct(float(win.asleep_being_steps), float(win.being_steps))
		var row := {"sol": s, "avg_e": avg_e, "asleep": asleep, "pop": w.colony.pop(),
				"min_pop": win.min_pop, "min_ice": win.min_ice}
		rows.append(row)
		body.append("%4d %4d %4s %5d %-23s %7.1f %7.1f %7.1f %7.1f %6.1f %6.1f %5d %-17s %5d %5d %5.1f %6.1f %6.1f %6s %6s" % [
				s, w.colony.pop(), _fmt_min(win.min_pop).replace(".0", ""), st.births,
				"%d/%d/%d/%d/%d" % [d.air, d.thirst, d.hunger, d.suffocated_outside, d.other],
				w.colony.oxygen, w.colony.food, w.colony.ice, w.colony.regolith,
				w.buildings.demand(), w.buildings.supply(), int(st.shorts) - int(prev.shorts),
				"/".join(counts), w.resources.reachable_ice_count(), int(st.mining_trips) - int(prev.trips),
				avg_e, asleep, float(win.hours_waiting_regolith) + float(win.hours_site_no_crew),
				_fmt_min(win.min_ice), _fmt_min(win.min_oxygen)])
		prev.shorts = st.shorts
		prev.trips = st.mining_trips
		w.reset_window()
	var table_text := "\n".join(body)
	var thash := table_text.sha256_text()
	lines.append_array(body)
	var verdicts := _targets(w, rows, sols)
	lines.append("")
	lines.append("targets for seed %d (%d sols):" % [seed_in, sols])
	for v in verdicts:
		lines.append("  T%d %-4s %s" % [v.n, v.verdict, v.detail])
	var all_pass := true
	for v in verdicts:
		if v.verdict == "FAIL":
			all_pass = false
	lines.append("RESULT %s (target 9 determinism: table sha256 %s)" % ["PASS" if all_pass else "FAIL", thash.substr(0, 16)])
	for e in saved:
		e[0][e[1]] = e[2]
	return {"lines": lines, "table_hash": thash, "verdicts": verdicts, "steps": total_steps, "world": w}


static func _v(n: int, ok: bool, detail: String) -> Dictionary:
	return {"n": n, "verdict": "PASS" if ok else "FAIL", "detail": detail}


## Per-seed verdicts for the nine targets (spec section 13). Target 9 is checked by repeat runs, not here.
static func _targets(w: SimWorld, rows: Array[Dictionary], sols: int) -> Array[Dictionary]:
	var st: Dictionary = w.stats
	var out: Array[Dictionary] = []
	var sol_h: float = w.clock.sol_h
	# 1 survival
	var low := 1 << 30
	for r in rows:
		if r.min_pop != null:
			low = mini(low, int(r.min_pop))
	var run_min := int(st.min_pop) if st.min_pop != null else 0
	out.append(_v(1, run_min >= 5 and w.colony.pop() > 0, "run min pop %d (needs >= 5), final pop %d" % [run_min, w.colony.pop()]))
	# 2 deaths
	var d: Dictionary = st.deaths
	var ndeaths := int(d.air) + int(d.thirst) + int(d.hunger) + int(d.suffocated_outside) + int(d.other)
	out.append(_v(2, int(d.suffocated_outside) == 0 and int(d.other) == 0 and int(st.deaths_unexplained) == 0,
			"deaths %d (air %d thirst %d hunger %d eva %d other %d), unexplained %d" % [
			ndeaths, d.air, d.thirst, d.hunger, d.suffocated_outside, d.other, st.deaths_unexplained]))
	# 3 growth
	var p: Array = st.pop_by_sol
	var ok3 := int(st.births_at_capacity) == 0 and int(st.cooldown_violations) == 0
	var det3 := "births %d, first_birth_sol %s, at_capacity %d, cooldown_violations %d" % [
			st.births, str(st.first_birth_sol), st.births_at_capacity, st.cooldown_violations]
	if st.first_birth_sol != null and int(st.first_birth_sol) < 2:
		ok3 = false
	# Owner decision (2026-10-03): no population caps. Growth is the player's to influence; pop is reported only.
	for sol_mark in [30, 100, 300]:
		if sols >= sol_mark:
			det3 += ", pop@%d=%d" % [sol_mark, int(p[sol_mark])]
	out.append(_v(3, ok3, det3))
	# 4 stocks. Owner decision (2026-10-03): oxygen and food must never run out. Ice running dry is
	# colony pressure for the player to answer (influence, later a water-saving building or a council rule),
	# so it is reported, not failed. Thirst deaths still need a logged cause (target 2).
	var ok4 := true
	for k in ["min_oxygen", "min_food"]:
		if st[k] != null and float(st[k]) <= 0.0:
			ok4 = false
	if float(st.max_ice_over_target) >= 3.0 or float(st.max_regolith_over_target) >= 3.0:
		ok4 = false
	var ice_note := "ice ran dry (pressure)" if (st.min_ice != null and float(st.min_ice) <= 0.0) else "ice never ran dry"
	out.append(_v(4, ok4, "min O2 %s, food %s; %s: min ice %s, ice>30 %s, thirst deaths %d; max ice/target %.2f, regolith/target %.2f" % [
			_fmt_min(st.min_oxygen), _fmt_min(st.min_food), ice_note, _fmt_min(st.min_ice), _fmt_min(st.min_ice_after30),
			int(st.deaths.thirst), st.max_ice_over_target, st.max_regolith_over_target]))
	# 5 power
	var over := _pct(float(st.demand_over_steps), float(st.step_count))
	var rx = st.first_new_reactor_sol
	var ok5 := over <= 10.0 and int(st.max_shorts_per_sol) <= 2 and float(st.max_offline_h) <= sol_h \
			and rx != null and int(rx) <= 15
	out.append(_v(5, ok5, "demand>supply %.2f%% of steps (<=10), max shorts/sol %d (<=2), max offline %.1f h (<=%.1f), first new reactor sol %s (<=15)" % [
			over, st.max_shorts_per_sol, st.max_offline_h, sol_h, str(rx)]))
	# 6 growth limited: provisional 2% threshold (spec 13), per seed; the 4-of-5 rule is applied across seeds
	var total_h := float(sols) * sol_h
	var limited := float(st.hours_waiting_regolith) + float(st.hours_site_no_crew)
	out.append(_v(6, _pct(limited, total_h) >= 2.0, "limited %.1f h = %.2f%% (>=2%% provisional; 4 of 5 seeds), site busy %.1f%%; waiting_regolith %.1f h, site_no_crew %.1f h" % [
			limited, _pct(limited, total_h), _pct(float(st.site_busy_h), total_h), st.hours_waiting_regolith, st.hours_site_no_crew]))
	# 7 mining
	var reach := _pct(float(st.reachable_ok_samples), float(st.sol_samples))
	out.append(_v(7, int(st.turn_backs_air) == 0 and reach >= 95.0, "turn_backs_air %d, exhausted %d, reachable>=2 at %.1f%% of %d sol samples (>=95), trips %d" % [
			st.turn_backs_air, st.turn_backs_exhausted, reach, st.sol_samples, st.mining_trips]))
	# 8 energy
	var ok8 := float(st.max_sleep_h) <= 18.0
	var emin := 1e9
	var emax := -1e9
	var amin := 1e9
	var amax := -1e9
	for r in rows:
		emin = minf(emin, r.avg_e)
		emax = maxf(emax, r.avg_e)
		amin = minf(amin, r.asleep)
		amax = maxf(amax, r.asleep)
		if r.avg_e < 40.0 or r.avg_e > 90.0 or r.asleep < 5.0 or r.asleep > 30.0:
			ok8 = false
	out.append(_v(8, ok8, "row avg energy %.1f..%.1f (40..90), row asleep %.1f..%.1f%% (5..30), max sleep %.1f h (<=18)" % [
			emin, emax, amin, amax, st.max_sleep_h]))
	out.append({"n": 9, "verdict": "N/A", "detail": "checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)"})
	return out
