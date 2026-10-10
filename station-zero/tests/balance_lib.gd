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
	# An override must keep the data's type (int and float are interchangeable); a value that failed to
	# parse as JSON arrives as a String and would otherwise run a silently broken experiment.
	var old_t := typeof(node[leaf])
	var new_t := typeof(value)
	var numeric := (old_t == TYPE_INT or old_t == TYPE_FLOAT) and (new_t == TYPE_INT or new_t == TYPE_FLOAT)
	if old_t != new_t and not numeric:
		return "type mismatch for %s: data has %s, override is %s (%s)" % [path, type_string(old_t), type_string(new_t), str(value)]
	saved.append([node, leaf, node[leaf]])
	node[leaf] = value
	return ""


static func parse_value(text: String) -> Variant:
	var v: Variant = JSON.parse_string(text)
	return text if v == null and text != "null" else v


static func data_hash() -> String:
	var parts: Array[String] = []
	for f in ["calendar", "signs", "persona", "sim", "colony", "buildings", "beings", "resources", "suits", "ages", "relationships", "council"]:
		parts.append(JSON.stringify(SimData.load_json(f + ".json"), "", true))
	return "\n".join(parts).sha256_text()


## Council helpers (spec council.md 9.1). The `age` column is a projection: L for landing, S for any other age.
static func age_column(w: SimWorld) -> String:
	return "L" if str(w.ages.age) == Ages.LANDING else "S"


## The trailing `cn` column: P after the pledge (any age), else C in Council, else -.
static func cn_column(w: SimWorld) -> String:
	var pledged: bool = w.stats.has("council") and w.stats.council.pledge_sol != null
	if w.council != null and not w.council.pledged.is_empty():
		pledged = true
	if pledged:
		return "P"
	return "C" if str(w.ages.age) == "council" else "-"


## The age_history entries that survive the Landing / not-Landing projection (consecutive equal letters collapse; the
## first of a run is kept). Shared by T10, T12 and tools/age_probe.gd.
static func projected_history(history: Array) -> Array:
	var out: Array = []
	var prev := ""
	for e in history:
		var letter := "L" if str(e.age) == Ages.LANDING else "S"
		if letter != prev:
			out.append(e)
			prev = letter
	return out


## An Array of "L" / "S", one per surviving entry of projected_history().
static func project_ages(history: Array) -> Array:
	var out: Array = []
	for e in projected_history(history):
		out.append("L" if str(e.age) == Ages.LANDING else "S")
	return out


static func projected_changes(history: Array) -> int:
	return maxi(0, project_ages(history).size() - 1)


static func _pct(a: float, b: float) -> float:
	return 100.0 * a / b if b > 0.0 else 0.0


static func _fmt_min(v: Variant) -> String:
	return "-" if v == null else "%.1f" % float(v)


## player: optional scripted player (tools/attentive_player.gd) called after every step; null = unattended.
static func run(seed_in: int, sols: int, params: Dictionary = {}, row_every: int = 30, tier: String = "",
		player: RefCounted = null) -> Dictionary:
	var saved: Array = []
	var lines: Array[String] = []
	for k in params:
		var err := apply_param(str(k), params[k], saved)
		if err != "":
			lines.append("PARAM ERROR: %s" % err)
	var w := SimWorld.new(seed_in)
	var pstr := " ".join(PackedStringArray(params.keys().map(func(k): return "%s=%s" % [k, str(params[k])])))
	lines.append("# station zero balance run: seed=%d sols=%d overrides=[%s] fixed_step=%s data_hash=%s%s" % [
			seed_in, sols, pstr, str(w.fixed_step), data_hash().substr(0, 16),
			"" if player == null else " player=%s" % player.call("label")])
	lines.append("# deaths and births are cumulative; shorts, trips, energy, asleep, wait, min_* are for the 30-sol window")
	var body: Array[String] = []
	var head := "%4s %4s %4s %5s %-23s %7s %7s %7s %7s %6s %6s %5s %-17s %5s %5s %5s %6s %6s %6s %6s %s %s %s" % [
			"sol", "pop", "min", "birth", "dead a/t/h/o/x", "oxygen", "food", "ice", "regol",
			"dmnd", "supp", "short", "bldg R/H/W/G/A/C", "reach", "trips", "avgE", "asleep%", "waitH", "minIce", "minO2", "age", "web", "cn"]
	body.append(head)
	var prev := {"shorts": 0, "trips": 0}
	var rows: Array[Dictionary] = []
	var sol_h: float = w.clock.sol_h
	var total_steps := 0
	# Read-only observer for T10 (report only): not-ok sols per cause group, from the sample the hook just appended.
	var notok := {"sols": 0}
	for g in Ages.GROUPS:
		notok[g] = 0
	# Standard tier (spec lifecycle-calibration.md): a read-only observer; null at Smoke so that path is unchanged.
	var obs: RefCounted = null
	if tier == "std":
		obs = load("res://tests/lifecycle_lib.gd").new()
		obs.begin(w, row_every)
	while w.sol() < sols:
		w.step()
		total_steps += 1
		if player != null:
			player.call("after_step", w)
		if obs != null:
			obs.after_step(w)
		if w._sol_started and w.ages_enabled and w.sol() >= int(SimData.ages().sample.from_sol) \
				and w.colony.pop() > 0 and not w.ages.window.is_empty():
			var last: Dictionary = w.ages.window.back()
			if not last.ok:
				notok.sols += 1
				for g in last.failed:
					notok[g] += 1
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
		body.append("%4d %4d %4s %5d %-23s %7.1f %7.1f %7.1f %7.1f %6.1f %6.1f %5d %-17s %5d %5d %5.1f %6.1f %6.1f %6s %6s %s %.2f %s" % [
				s, w.colony.pop(), _fmt_min(win.min_pop).replace(".0", ""), st.births,
				"%d/%d/%d/%d/%d" % [d.air, d.thirst, d.hunger, d.suffocated_outside, d.other],
				w.colony.oxygen, w.colony.food, w.colony.ice, w.colony.regolith,
				w.buildings.demand(), w.buildings.supply(), int(st.shorts) - int(prev.shorts),
				"/".join(counts), w.resources.reachable_ice_count(), int(st.mining_trips) - int(prev.trips),
				avg_e, asleep, float(win.hours_waiting_regolith) + float(win.hours_site_no_crew),
				_fmt_min(win.min_ice), _fmt_min(win.min_oxygen),
				age_column(w), float(st.relationships.web_share), cn_column(w)])
		prev.shorts = st.shorts
		prev.trips = st.mining_trips
		w.reset_window()
	var table_text := "\n".join(body)
	var thash := table_text.sha256_text()
	lines.append_array(body)
	var verdicts := _targets(w, rows, sols, notok)
	lines.append("")
	lines.append("targets for seed %d (%d sols):" % [seed_in, sols])
	for v in verdicts:
		lines.append("  T%d %-4s %s" % [v.n, v.verdict, v.detail])
	var all_pass := true
	for v in verdicts:
		if v.verdict == "FAIL":
			all_pass = false
	lines.append("RESULT %s (target 9 determinism: table sha256 %s)" % ["PASS" if all_pass else "FAIL", thash.substr(0, 16)])
	var std := {}
	if obs != null:
		std = obs.finish(w, sols, verdicts)
		lines.append_array(std.lines)
		var std_text := "\n".join(PackedStringArray(std.lines))
		lines.append("STD-RESULT (restated targets; exit code follows L1 and L4 only, spec section 8) std_text sha256 %s" % std_text.sha256_text().substr(0, 16))
		lines.append_array(std.wall_lines)
	for e in saved:
		e[0][e[1]] = e[2]
	return {"lines": lines, "table_hash": thash, "verdicts": verdicts, "steps": total_steps, "world": w, "std": std}


static func _v(n: int, ok: bool, detail: String) -> Dictionary:
	return {"n": n, "verdict": "PASS" if ok else "FAIL", "detail": detail}


## Per-seed verdicts for the nine targets (spec section 13). Target 9 is checked by repeat runs, not here.
static func _targets(w: SimWorld, rows: Array[Dictionary], sols: int, notok: Dictionary = {}) -> Array[Dictionary]:
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
	out.append(_t10(w, sols, notok))
	out.append(_t11(w))
	out.append(_t12(w))
	return out


## Target 10, ages (spec ages.md sections 12 and 19.2), from stats only. Judged: (1) first settlement sol in
## balance.settle_sol_min..settle_sol_max (judged only when the run reaches settle_sol_max sols, else N/A when not
## yet settled), (2) age_changes <= balance.max_age_changes, (3) every gap between consecutive age_history sols >=
## min_dwell_sols, (4) len(age_history) == age_changes + 1 and every entry has how and text. Reported: first
## settlement sol, changes, sols in each age, age at the end, sol and cause of each change, the cause of each fall
## back and the not-ok sols per cause group (observed by run() at each boundary, read only).
static func _t10(w: SimWorld, sols: int, notok: Dictionary) -> Dictionary:
	var st: Dictionary = w.stats
	var cfg: Dictionary = SimData.ages()
	var lo := int(cfg.balance.settle_sol_min)
	var hi := int(cfg.balance.settle_sol_max)
	var dwell := int(cfg.min_dwell_sols)
	var live: Array = st.age_history
	var hist: Array = projected_history(live)  # spec council.md 12: Council changes only relabel Settlement
	var first = st.first_settlement_sol
	var judged1 := first != null or sols >= hi
	var ok1 := first != null and int(first) >= lo and int(first) <= hi
	var changes_n := projected_changes(live)
	var ok2 := changes_n <= int(cfg.balance.max_age_changes)
	var ok3 := true
	var min_gap := -1
	for i in range(1, hist.size()):
		var gap := int(hist[i].sol) - int(hist[i - 1].sol)
		min_gap = gap if min_gap < 0 else mini(min_gap, gap)
		if gap < dwell:
			ok3 = false
	var ok4 := live.size() == int(st.age_changes) + 1
	for e in live:
		if not e.has("how") or str(e.get("text", "")) == "":
			ok4 = false
	var changes: Array[String] = []
	var falls: Array[String] = []
	for i in range(1, live.size()):
		var e: Dictionary = live[i]
		changes.append("sol %d %s%s" % [int(e.sol), str(e.how), (" (cause %s)" % str(e.cause)) if e.cause != null else ""])
		if str(e.how) == "fell_back":
			falls.append("sol %d %s" % [int(e.sol), str(e.cause)])
	var groups: Array[String] = []
	for g in Ages.GROUPS:
		groups.append("%s %d" % [g, int(notok.get(g, 0))])
	var detail := "first settlement sol %s (%d..%d), age_changes %d (<=%d), min gap between consecutive history entries %s (>=%d), history %d entries (changes+1 = %d); " % [
			str(first), lo, hi, changes_n, int(cfg.balance.max_age_changes),
			"-" if min_gap < 0 else str(min_gap), dwell, live.size(), int(st.age_changes) + 1]
	detail += "report: sols_in_age landing %d settlement %d council %d, age at end %s, changes [%s], fall back causes [%s], not-ok sols %d (by group, a sol can fail several: %s)" % [
			int(st.sols_in_age.get("landing", 0)), int(st.sols_in_age.get("settlement", 0)),
			int(st.sols_in_age.get("council", 0)), str(w.ages.age),
			"; ".join(PackedStringArray(changes)), "; ".join(PackedStringArray(falls)) if not falls.is_empty() else "none",
			int(notok.get("sols", 0)), ", ".join(PackedStringArray(groups))]
	if not judged1 and ok2 and ok3 and ok4:
		return {"n": 10, "verdict": "N/A", "detail": "run shorter than %d sols and not settled yet; " % hi + detail}
	return _v(10, ok1 and ok2 and ok3 and ok4, detail)


## Target 11, relationships (spec relationships.md sections 13 and 14, Balance), from `stats.relationships` only. Judged:
## (1) the web, second, lonely and pop lists have the same length; (2) the mean of the last balance.lonely_window_sols
## readings of lonely_by_sol (all of them if fewer) <= balance.lonely_share_max; (3) friends_mean in
## balance.friends_mean_min..friends_mean_max; (4) first_friendship_sol is not null; (5) no dropped friend events
## (lines_dropped_by_type.friend when that key exists, else the total lines_dropped, which is stricter). Reported:
## web, second and lonely shares, friends_mean, friends as a share of the colony (friends_mean / (pop - 1), D2).
static func _t11(w: SimWorld) -> Dictionary:
	var rs: Dictionary = w.stats.relationships
	var bal: Dictionary = SimData.relationships().balance
	var n_pop: int = w.stats.pop_by_sol.size()
	var ok1: bool = rs.web_by_sol.size() == rs.second_by_sol.size() and rs.web_by_sol.size() == rs.lonely_by_sol.size() \
			and rs.web_by_sol.size() == n_pop
	var lby: Array = rs.lonely_by_sol
	var win: Array = lby.slice(maxi(0, lby.size() - int(bal.lonely_window_sols)))
	var wmean := 0.0
	for v in win:
		wmean += float(v)
	wmean /= maxf(1.0, float(win.size()))
	var ok2 := wmean <= float(bal.lonely_share_max)
	var fm := float(rs.friends_mean)
	var ok3 := fm >= float(bal.friends_mean_min) and fm <= float(bal.friends_mean_max)
	var ok4: bool = rs.first_friendship_sol != null
	var dropped_friend := 0
	var dropped_txt := "lines_dropped (total)"
	if rs.has("lines_dropped_by_type"):
		dropped_friend = int(rs.lines_dropped_by_type.get("friend", 0))
		dropped_txt = "lines_dropped_by_type.friend"
	else:
		dropped_friend = int(rs.lines_dropped)
	var ok5 := dropped_friend == 0
	var pop := w.colony.pop()
	var share := fm / float(pop - 1) if pop > 1 else 0.0
	var detail := "(1) list lengths %d/%d/%d/%d %s; (2) lonely mean of last %d readings %.3f (max %.2f) %s; (3) friends_mean %.2f (%.1f..%.1f) %s; (4) first_friendship_sol %s %s; (5) %s %d %s; report: web %.2f second %.2f lonely %.2f friends_mean %.2f friends share of colony %.3f (pop %d)" % [
			rs.web_by_sol.size(), rs.second_by_sol.size(), rs.lonely_by_sol.size(), n_pop, "ok" if ok1 else "BAD",
			win.size(), wmean, float(bal.lonely_share_max), "ok" if ok2 else "BAD",
			fm, float(bal.friends_mean_min), float(bal.friends_mean_max), "ok" if ok3 else "BAD",
			str(rs.first_friendship_sol), "ok" if ok4 else "BAD", dropped_txt, dropped_friend, "ok" if ok5 else "BAD",
			float(rs.web_share), float(rs.second_share), float(rs.lonely_share), fm, share, pop]
	return _v(11, ok1 and ok2 and ok3 and ok4 and ok5, detail)


## Target 12, the Council (spec council.md section 12), per seed from `stats` and the log. Judged: (1) trust_by_sol,
## chosen_by_sol and pop_by_sol have one length; (2) C2: every Council entry is at least settled_sols after the Settlement
## entry before it, and every Council change is at least min_dwell_sols after the previous age_history entry; (3) C3: at
## most balance.max_council_changes Council changes (entries plus splits); (4) every proposal has an outcome or is the open
## one, and a pledged one took at least 2 x session.interval_sols; (5) no sol boundary carries two Council-kind lines.
## Reported: first Council sol, meetings, proposals and outcomes, pledge sol and reason, lines, lines dropped, and the
## council_min_seeds / pledge_min_seeds counts the cross-seed targets C1 and C4 need.
static func _t12(w: SimWorld) -> Dictionary:
	var st: Dictionary = w.stats
	var cs: Dictionary = st.council
	var cfg: Dictionary = SimData.council()
	var ok1: bool = cs.trust_by_sol.size() == cs.chosen_by_sol.size() and cs.trust_by_sol.size() == st.pop_by_sol.size()
	var hist: Array = st.age_history
	var ok2 := true
	var changes := 0
	var last_settle := -1
	for i in hist.size():
		var e: Dictionary = hist[i]
		var is_council_change := str(e.age) == "council" or str(e.how) == "council_split"
		if str(e.age) == "council":
			if last_settle < 0 or int(e.sol) - last_settle < int(cfg.entry.settled_sols):
				ok2 = false
		if is_council_change:
			changes += 1
			if i > 0 and int(e.sol) - int(hist[i - 1].sol) < int(cfg.min_dwell_sols):
				ok2 = false
		if str(e.age) == "settlement":
			last_settle = int(e.sol)
	var ok3 := changes <= int(cfg.balance.max_council_changes)
	var ok4 := true
	var props: Array = cs.proposals
	var pledged_reason := "-"
	for i in props.size():
		var p: Dictionary = props[i]
		if p.outcome == null:
			if i != props.size() - 1:
				ok4 = false
		elif str(p.outcome) == "pledged":
			pledged_reason = str(p.reason)
			if int(p.outcome_sol) - int(p.raised_sol) < 2 * int(cfg.session.interval_sols):
				ok4 = false
	var ok5 := true
	var seen := {}
	for e in w.log:
		if str(e.kind).begins_with("council_"):
			var sol := int(e.get("sol", -1))
			if sol < 0:
				sol = int(w.clock.sol_index(float(e.t))) if e.has("t") else -1
			if seen.has(sol):
				ok5 = false
			seen[sol] = true
	var outcomes: Array[String] = []
	for p in props:
		outcomes.append("%s@%d %s" % [str(p.topic), int(p.raised_sol), str(p.outcome)])
	var detail := "(1) list lengths %d/%d/%d %s; (2) C2 %s; (3) council changes %d (<=%d) %s; (4) proposals %d %s; (5) one Council line per boundary %s; " % [
			cs.trust_by_sol.size(), cs.chosen_by_sol.size(), st.pop_by_sol.size(), "ok" if ok1 else "BAD",
			"ok" if ok2 else "BAD", changes, int(cfg.balance.max_council_changes), "ok" if ok3 else "BAD",
			props.size(), "ok" if ok4 else "BAD", "ok" if ok5 else "BAD"]
	detail += "report: first Council sol %s, meetings %d, proposals [%s], pledge sol %s reason %s, lines %s, dropped %d; council_min_seeds %d pledge_min_seeds %d" % [
			str(cs.first_council_sol), int(cs.sessions), "; ".join(PackedStringArray(outcomes)), str(cs.pledge_sol),
			pledged_reason, JSON.stringify(cs.lines), int(cs.lines_dropped),
			int(cfg.balance.council_min_seeds), int(cfg.balance.pledge_min_seeds)]
	return _v(12, ok1 and ok2 and ok3 and ok4 and ok5, detail)
