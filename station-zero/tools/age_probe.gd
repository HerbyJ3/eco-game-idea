extends SceneTree
## Age calibration probe (spec docs/specs/ages.md section 14; plan task-3 step 5). READ-ONLY: changes no data, no sim code.
##
##   godot --headless --path station-zero --script res://tools/age_probe.gd -- --seed N --sols 300 [--out DIR]
##       run one seed, print the report, write DIR/seed_N.json (raw per-sol records) and DIR/seed_N.csv
##   godot --headless --path station-zero --script res://tools/age_probe.gd -- --sweeps FILE [FILE ...]
##       replay the recorded per-sol clause inputs of those seed files through Ages.decide, one parameter at a time
##   godot --headless --path station-zero --script res://tools/age_probe.gd -- --timing --seed N --sols 300 [--calls 2000]
##       time Ages.on_sol on the end state of a seed run (run it alone on an idle machine)
##
## How it observes: world A is the real thing (ages enabled, live stats.age_history). World B is the same seed with the
## sol hook switched off (SimWorld.ages_enabled = false), stepped in lockstep. At every sol boundary the probe calls
## Ages.sample(B) itself (before it refreshes B.ages.snap_*, as on_sol would) and records the raw inputs of every clause.
## Between boundaries it reads B's ice after every step. Ages never writes colony state (spec 7), so B is the same
## colony as A; the probe checks that (pop and ice at every boundary) as part of the self-replay.

const BL := "res://tests/balance_lib.gd"
const CLAUSES: Array[String] = ["oxygen", "o2_net", "food", "food_net", "power_budget", "none_offline", "no_short",
		"no_shortage_death", "ice", "calm", "rested"]
const ENTRY: Array[String] = ["full", "share", "recent", "fam_count", "fam_homes", "dwell"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_in := 42
	var sols := 300
	var out_dir := ""
	var calls := 2000
	var mode := "seed"
	var files: Array[String] = []
	var i := 0
	while i < args.size():
		match args[i]:
			"--seed":
				i += 1
				seed_in = int(args[i])
			"--sols":
				i += 1
				sols = int(args[i])
			"--out":
				i += 1
				out_dir = args[i]
			"--calls":
				i += 1
				calls = int(args[i])
			"--timing":
				mode = "timing"
			"--sweeps":
				mode = "sweeps"
			_:
				if mode == "sweeps" and not args[i].begins_with("--"):
					files.append(args[i])
		i += 1
	match mode:
		"seed":
			_seed_run(seed_in, sols, out_dir)
		"sweeps":
			_sweeps(files)
		"timing":
			_timing(seed_in, sols, calls)
	quit(0)


# ------------------------------------------------------------------ recording

func _raw(w: SimWorld, min_ice: float, min_days: float) -> Dictionary:
	var s: Dictionary = Ages.sample(w)
	var col: Colony = w.colony
	var pop := col.pop()
	var en: Dictionary = SimData.beings().energy
	var distressed := 0
	var rested := 0
	for b in w.beings:
		if b.energy < float(en.exhausted_turn_back) or (b.is_outside() and b.returning):
			distressed += 1
		if b.energy >= float(en.sleep_below):
			rested += 1
	var offline := 0
	for b in w.buildings.list:
		if b.offline:
			offline += 1
	var shortage_deaths := 0
	for k in range(w.ages.snap_deaths, w.stats.deaths_list.size()):
		if str(w.stats.deaths_list[k].cause) in SimData.ages().sample.shortage_causes:
			shortage_deaths += 1
	var use := pop * float(SimData.colony().consumption.ice_per_being) * w.clock.sol_h
	var fam := Ages.family_mars_born(w)
	var cl := {}
	for c in CLAUSES:
		cl[c] = bool(s[c])
	return {"sol": w.sol(), "pop": pop, "cl": cl,
			"o2f": col.oxygen / maxf(col.o2_cap(), 1e-9), "foodf": col.food / maxf(col.food_cap(), 1e-9),
			"o2_net": col.o2_net(), "food_net": col.food_net(),
			"demand": w.buildings.demand(), "supply": w.buildings.supply(), "offline": offline,
			"shorts": int(w.stats.shorts) - w.ages.snap_shorts, "shortage_deaths": shortage_deaths,
			"ice": col.ice, "use": use, "ice_days": col.ice / use if use > 0.0 else -1.0,
			"ice_min": min_ice, "ice_days_min": min_days,
			"distressed": distressed, "rested": rested, "fam": fam[0], "homes": fam[1]}


## Runs worlds A and B in lockstep.
func _run_world(seed_in: int, sols: int) -> Dictionary:
	var a := SimWorld.new(seed_in)
	var b := SimWorld.new(seed_in)
	b.ages_enabled = false
	var ipb := float(SimData.colony().consumption.ice_per_being)
	var recs: Array = []
	var live_samples: Array = []  # A's own last_sample per sol (its on_sol result), for a clause-by-clause cross check
	var min_ice := INF
	var min_days := INF
	var mismatch: Array[String] = []
	while a.sol() < sols:
		a.step()
		b.step()
		var pop := b.colony.pop()
		if pop > 0:
			min_ice = minf(min_ice, b.colony.ice)
			min_days = minf(min_days, b.colony.ice / (pop * ipb * b.clock.sol_h))
		if not b._sol_started:
			continue
		var r := _raw(b, min_ice if min_ice < INF else -1.0, min_days if min_days < INF else -1.0)
		recs.append(r)
		live_samples.append(a.ages.last_sample.duplicate())
		if a.colony.pop() != pop or a.colony.ice != b.colony.ice:
			mismatch.append("sol %d: A pop %d ice %.6f vs B pop %d ice %.6f" % [a.sol(), a.colony.pop(), a.colony.ice, pop, b.colony.ice])
		b.ages.snap_shorts = int(b.stats.shorts)
		b.ages.snap_deaths = b.stats.deaths_list.size()
		min_ice = INF
		min_days = INF
	return {"recs": recs, "live_history": a.stats.age_history, "live_window": a.ages.window,
			"live_samples": live_samples, "mismatch": mismatch, "world": a,
			"first_settlement_sol": a.stats.first_settlement_sol, "age_changes": a.stats.age_changes,
			"sols_in_age": a.stats.sols_in_age}


# ------------------------------------------------------------------ replay (mirrors Ages.on_sol over recorded inputs)

func _derive(r: Dictionary) -> Dictionary:
	var cfg: Dictionary = SimData.ages().sample
	var pop := int(r.pop)
	var c: Dictionary = r.cl.duplicate()
	c["ice"] = float(r.ice) >= float(cfg.ice_min_sols) * float(r.use) - Ages.CMP_EPS
	c["calm"] = float(r.distressed) <= float(cfg.distress_share_max) * pop + Ages.CMP_EPS
	c["rested"] = float(r.rested) >= float(cfg.rested_share_min) * pop - Ages.CMP_EPS
	return c


## Replays recorded per-sol inputs with the CURRENT SimData.ages(). Returns {hist, entry, ok40, ok, failed, window, first}.
## entry[n] is null on Settlement sols, else {clause: bool} for the six entry clauses at sol n (before decide).
func _replay(recs: Array) -> Dictionary:
	var cfg: Dictionary = SimData.ages()
	var size := int(cfg.sample.window_sols)
	var win: Array = []
	var age := Ages.LANDING
	var last_change := 0
	var first: Variant = null
	var hist: Array = [{"sol": 0, "age": Ages.LANDING, "how": "landing", "cause": null}]
	var entry: Dictionary = {}
	var ok40: Dictionary = {}
	var okd: Dictionary = {}
	var failed: Dictionary = {}
	for r in recs:
		var n := int(r.sol)
		var pop := int(r.pop)
		if n >= int(cfg.sample.from_sol) and pop > 0:
			var c := _derive(r)
			var f := Ages.failed_groups(c)
			win.append({"ok": f.is_empty(), "failed": f})
			while win.size() > size:
				win.pop_front()
			okd[n] = f.is_empty()
			failed[n] = f
		var okc := 0
		for e in win:
			if e.ok:
				okc += 1
		ok40[n] = okc
		if pop == 0:
			entry[n] = null
			continue
		if age == Ages.LANDING:
			var required := int(ceil(float(cfg.entry.ok_share) * size - SimWorld.STEP_EPS))
			var recent := true
			var rc := int(cfg.entry.recent_ok_sols)
			for k in range(maxi(0, win.size() - rc), win.size()):
				if not win[k].ok:
					recent = false
			entry[n] = {"full": win.size() >= size, "share": okc >= required and win.size() >= size, "recent": recent and win.size() >= rc,
					"fam_count": int(r.fam) >= int(cfg.entry.mars_born_min),
					"fam_homes": int(r.homes) >= int(cfg.entry.mars_born_homes_min),
					"dwell": n - last_change >= int(cfg.min_dwell_sols)}
		else:
			entry[n] = null
		var next := Ages.decide(win, age, n - last_change, int(r.fam), int(r.homes))
		if next == age:
			continue
		var how := "fell_back"
		var cause := ""
		if next == Ages.SETTLEMENT:
			how = "settled" if first == null else "settled_again"
			if first == null:
				first = n
		else:
			cause = Ages.dominant_cause(win)
		age = next
		last_change = n
		hist.append({"sol": n, "age": age, "how": how, "cause": cause if cause != "" else null, "pop": pop, "fam": int(r.fam)})
	return {"hist": hist, "entry": entry, "ok40": ok40, "ok": okd, "failed": failed, "window": win, "first": first}


func _hist_text(hist: Array) -> String:
	var parts: Array[String] = []
	for h in hist:
		if int(h.sol) == 0:
			continue
		var tag := "S" if h.age == Ages.SETTLEMENT else "L"
		parts.append("%s@%d%s" % [tag, int(h.sol), "" if h.cause == null else "(" + str(h.cause) + ")"])
	return "-" if parts.is_empty() else " ".join(PackedStringArray(parts))


func _min_gap(hist: Array) -> String:
	var g := 1 << 30
	for k in range(2, hist.size()):
		g = mini(g, int(hist[k].sol) - int(hist[k - 1].sol))
	return "-" if g == (1 << 30) else str(g)


# ------------------------------------------------------------------ seed run

func _seed_run(seed_in: int, sols: int, out_dir: String) -> void:
	var t0 := Time.get_ticks_msec()
	var res := _run_world(seed_in, sols)
	var recs: Array = res.recs
	var rep := _replay(recs)
	var out: Array[String] = []
	out.append("# age probe: seed=%d sols=%d data_hash=%s; wall %.1f s" % [seed_in, sols,
			(load(BL) as GDScript).data_hash().substr(0, 16), (Time.get_ticks_msec() - t0) / 1000.0])
	var cfg: Dictionary = SimData.ages()

	# ---- self-replay check
	var live: Array = res.live_history
	var problems: Array[String] = []
	if live.size() != rep.hist.size():
		problems.append("history length live %d vs replay %d" % [live.size(), rep.hist.size()])
	for k in range(mini(live.size(), rep.hist.size())):
		var l: Dictionary = live[k]
		var p: Dictionary = rep.hist[k]
		if l.age != p.age or l.how != p.how or l.cause != p.cause or int(l.sol) != int(p.sol):
			problems.append("entry %d live %s vs replay %s" % [k, str(l), str(p)])
		elif k >= 1 and (int(l.pop) != int(p.pop) or int(l.family_mars_born) != int(p.fam)):
			problems.append("entry %d pop/family live %d/%d vs replay %d/%d" % [k, l.pop, l.family_mars_born, p.pop, p.fam])
	var sample_diffs := 0
	var base_diffs := 0
	for k in range(recs.size()):
		var r: Dictionary = recs[k]
		var ls: Dictionary = res.live_samples[k]
		if int(r.sol) >= int(cfg.sample.from_sol) and int(r.pop) > 0:
			for c in CLAUSES:
				if ls.get(c) != r.cl[c]:
					sample_diffs += 1
			var d := _derive(r)
			for c in CLAUSES:
				if d[c] != r.cl[c]:
					base_diffs += 1
	var live_win: Array = res.live_window
	var win_same: bool = live_win.size() == rep.window.size()
	if win_same:
		for k in range(live_win.size()):
			if live_win[k].ok != rep.window[k].ok or live_win[k].failed != rep.window[k].failed:
				win_same = false
	var verdict := "PASS" if problems.is_empty() and sample_diffs == 0 and base_diffs == 0 and win_same and res.mismatch.is_empty() else "FAIL"
	out.append("self-replay: %s (history entries %d live / %d replayed; live-vs-probe clause diffs %d; recomputed-vs-recorded clause diffs %d; final window identical %s; world A vs B pop/ice mismatches %d)" % [
			verdict, live.size(), rep.hist.size(), sample_diffs, base_diffs, str(win_same), res.mismatch.size()])
	for pr in problems:
		out.append("  PROBLEM " + pr)
	for mm in res.mismatch.slice(0, 5):
		out.append("  PROBLEM " + mm)

	# ---- age history
	out.append("")
	out.append("age history (live stats.age_history): changes %d, first_settlement_sol %s, sols_in_age landing %d settlement %d, age at end %s" % [
			res.age_changes, str(res.first_settlement_sol), res.sols_in_age[Ages.LANDING], res.sols_in_age[Ages.SETTLEMENT], live[live.size() - 1].age])
	for h in live:
		out.append("  sol %3d  %-10s how=%-13s cause=%-7s pop=%s family_mars_born=%s" % [int(h.sol), h.age, h.how, str(h.cause), str(h.get("pop", "-")), str(h.get("family_mars_born", "-"))])
	# flaps
	var flaps := 0
	for k in range(2, live.size()):
		if int(live[k].sol) - int(live[k - 1].sol) <= int(cfg.sample.window_sols):
			flaps += 1
	out.append("flaps (a change within %d sols of the previous change): %d; changes: %d; shortest gap between changes: %s" % [
			int(cfg.sample.window_sols), flaps, maxi(0, live.size() - 1), _min_gap(rep.hist)])

	# ---- samples
	var first_ok := -1
	var ok_total := 0
	var sampled := 0
	for r in recs:
		var n := int(r.sol)
		if n >= int(cfg.sample.from_sol) and int(r.pop) > 0:
			sampled += 1
			if rep.ok.get(n, false):
				ok_total += 1
				if first_ok < 0:
					first_ok = n
	out.append("")
	out.append("samples: %d taken (sol >= %d, pop > 0); ok %d (%.1f%%); first ok sample sol %d" % [sampled, int(cfg.sample.from_sol), ok_total, 100.0 * ok_total / maxf(1, sampled), first_ok])

	# ---- entry: last clause to pass / blocking
	out.append("")
	out.append("entry clauses (Landing sols only; full = window full, share = ok share, recent = last 3 ok, fam_count/fam_homes = family Mars-born count / distinct birth habitats, dwell)")
	var entry: Dictionary = rep.entry
	for h in rep.hist:
		if h.how == "settled" or h.how == "settled_again":
			out.append("  settlement at sol %d: last clause(s) to pass %s (start sol of each clause's unbroken pass: %s)" % [
					int(h.sol), str(_last_to_pass(entry, int(h.sol))), _run_starts(entry, int(h.sol))])
	for probe_sol in [100, 150]:
		if probe_sol <= sols:
			var age_at := _age_at(rep.hist, probe_sol)
			if age_at == Ages.LANDING:
				var e: Variant = entry.get(probe_sol)
				var fl: Array[String] = []
				if e != null:
					for c in ENTRY:
						if not e[c]:
							fl.append(c)
				out.append("  sol %d: Landing; entry clauses failing: %s; ok in trailing window %d of %d; fam %d homes %d; first settlement %s" % [
						probe_sol, str(fl), int(rep.ok40[probe_sol]), int(cfg.sample.window_sols), int(recs[probe_sol - 1].fam), int(recs[probe_sol - 1].homes), str(res.first_settlement_sol)])
			else:
				out.append("  sol %d: %s (not blocked)" % [probe_sol, age_at])
	var land_sols := 0
	var fail_n := {}
	var sole_n := {}
	for c in ENTRY:
		fail_n[c] = 0
		sole_n[c] = 0
	var size := int(cfg.sample.window_sols)
	var last_block := {}
	for r in recs:
		var n := int(r.sol)
		var e: Variant = entry.get(n)
		if e == null or n < size + int(cfg.sample.from_sol) - 1:
			continue
		land_sols += 1
		var fs: Array[String] = []
		for c in ENTRY:
			if not e[c]:
				fs.append(c)
				fail_n[c] += 1
				last_block[c] = n
		if fs.size() == 1:
			sole_n[fs[0]] += 1
	out.append("  Landing sols from sol %d (earliest full window) to the end: %d; per entry clause: failing sols / sole-blocker sols / last failing sol:" % [size + int(cfg.sample.from_sol) - 1, land_sols])
	for c in ENTRY:
		out.append("    %-10s fails %3d  sole blocker %3d  last fail sol %s" % [c, fail_n[c], sole_n[c], str(last_block.get(c, "-"))])

	# ---- failure matrix
	out.append("")
	out.append("clause failure shares over sampled sols (sol >= %d, pop > 0): failing sols / %d" % [int(cfg.sample.from_sol), sampled])
	var fails := {}
	var only := {}
	for c in CLAUSES:
		fails[c] = 0
		only[c] = 0
	var fam_fail := 0
	var homes_fail := 0
	var bands: Dictionary = {}
	for r in recs:
		var n := int(r.sol)
		if n < int(cfg.sample.from_sol) or int(r.pop) == 0:
			continue
		var d := _derive(r)
		var fc: Array[String] = []
		for c in CLAUSES:
			if not d[c]:
				fc.append(c)
				fails[c] += 1
		if fc.size() == 1:
			only[fc[0]] += 1
		if int(r.fam) < int(cfg.entry.mars_born_min):
			fam_fail += 1
		if int(r.homes) < int(cfg.entry.mars_born_homes_min):
			homes_fail += 1
		var band := (n - 1) / 50
		if not bands.has(band):
			bands[band] = {"n": 0, "fail": {}, "only": {}, "notok": 0}
			for c in CLAUSES:
				bands[band].fail[c] = 0
				bands[band].only[c] = 0
		bands[band].n += 1
		if not fc.is_empty():
			bands[band].notok += 1
		for c in fc:
			bands[band].fail[c] += 1
		if fc.size() == 1:
			bands[band].only[fc[0]] += 1
	for c in CLAUSES:
		out.append("  %-18s fails %3d (%.1f%%), only failing clause on %d sols" % [c, fails[c], 100.0 * fails[c] / maxf(1, sampled), only[c]])
	out.append("  %-18s fails %3d (%.1f%%)   (entry clause, evaluated on every sampled sol, not part of ok)" % ["fam_count<min", fam_fail, 100.0 * fam_fail / maxf(1, sampled)])
	out.append("  %-18s fails %3d (%.1f%%)   (entry clause, evaluated on every sampled sol, not part of ok)" % ["fam_homes<min", homes_fail, 100.0 * homes_fail / maxf(1, sampled)])
	out.append("per 50-sol band (sols 1-50, 51-100, ...): sampled sols, not-ok sols, then per clause failing/only-failing")
	var keys := bands.keys()
	keys.sort()
	for bk in keys:
		var bd: Dictionary = bands[bk]
		var parts: Array[String] = []
		for c in CLAUSES:
			if bd.fail[c] > 0:
				parts.append("%s %d/%d" % [c, bd.fail[c], bd.only[c]])
		out.append("  band %3d-%3d: sampled %2d not-ok %2d | %s" % [bk * 50 + 1, bk * 50 + 50, bd.n, bd.notok, " ".join(PackedStringArray(parts))])

	# ---- ice dips
	var dip_sols := 0
	var dip_missed := 0
	var min_days_all := INF
	var min_days_sol := 0
	var min_ice_all := INF
	var min_ice_sol := 0
	var inst_min_days := INF
	var inst_min_sol := 0
	var thr := float(cfg.sample.ice_min_sols)
	var first_dip_missed := -1
	var ice_zero_sols := 0
	for r in recs:
		if int(r.pop) == 0:
			continue
		var n := int(r.sol)
		if float(r.ice_days_min) < min_days_all:
			min_days_all = float(r.ice_days_min)
			min_days_sol = n
		if float(r.ice_min) < min_ice_all:
			min_ice_all = float(r.ice_min)
			min_ice_sol = n
		if float(r.ice_days) < inst_min_days:
			inst_min_days = float(r.ice_days)
			inst_min_sol = n
		if float(r.ice_min) <= 0.0:
			ice_zero_sols += 1
		if n >= int(cfg.sample.from_sol) and float(r.ice_days_min) < thr - 1e-9:
			dip_sols += 1
			if float(r.ice_days) >= thr - 1e-9:
				dip_missed += 1
				if first_dip_missed < 0:
					first_dip_missed = n
	out.append("")
	out.append("ice: boundary minimum %.2f ice-days at sol %d; within-sol minimum %.2f ice-days at sol %d; min ice %.2f at sol %d; sols whose within-sol minimum reached 0 ice: %d" % [
			inst_min_days, inst_min_sol, min_days_all, min_days_sol, min_ice_all, min_ice_sol, ice_zero_sols])
	out.append("ice dips (spec open question): sols with within-sol min < %.1f ice-days: %d; of those the boundary read was ok (dip missed by the sample): %d (first at sol %d)" % [thr, dip_sols, dip_missed, first_dip_missed])

	# ---- calm / rested
	var cs := 0.0
	var rs := 0.0
	var cmax := 0.0
	var rmin := 1.0
	var n_s := 0
	for r in recs:
		if int(r.pop) == 0:
			continue
		var cshare := float(r.distressed) / int(r.pop)
		var rshare := float(r.rested) / int(r.pop)
		cs += cshare
		rs += rshare
		cmax = maxf(cmax, cshare)
		rmin = minf(rmin, rshare)
		n_s += 1
	out.append("calm: distressed share mean %.3f max %.3f (limit %.2f); rested: share mean %.3f min %.3f (limit %.2f)" % [
			cs / maxf(1, n_s), cmax, float(cfg.sample.distress_share_max), rs / maxf(1, n_s), rmin, float(cfg.sample.rested_share_min)])

	# ---- every 10th sol table
	out.append("")
	out.append("every 10th sol (age after that sol's decision; ice-d = ice in sols of use at the boundary; ice-dmin/icemin = minimum inside the sol; ok40 = ok samples in the trailing window; failed = clauses failing at this sample)")
	out.append("%4s %3s %4s %4s %5s %7s %6s %8s %7s %4s %5s %6s %6s  %s" % ["sol", "age", "pop", "fam", "homes", "ice", "ice-d", "ice-dmin", "icemin", "ok40", "ok", "calm%", "rest%", "failed"])
	for r in recs:
		var n := int(r.sol)
		if n % 10 != 0:
			continue
		var d := _derive(r)
		var fcl: Array[String] = []
		for c in CLAUSES:
			if not d[c]:
				fcl.append(c)
		var ageh := _age_at(rep.hist, n)
		out.append("%4d %3s %4d %4d %5d %7.1f %6.2f %8.2f %7.1f %4d %5s %6.1f %6.1f  %s" % [
				n, "S" if ageh == Ages.SETTLEMENT else "L", int(r.pop), int(r.fam), int(r.homes), float(r.ice), float(r.ice_days),
				float(r.ice_days_min), float(r.ice_min), int(rep.ok40[n]), "ok" if rep.ok.get(n, false) else "-",
				100.0 * float(r.distressed) / maxf(1, int(r.pop)), 100.0 * float(r.rested) / maxf(1, int(r.pop)), ",".join(PackedStringArray(fcl))])
	for l in out:
		print(l)

	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var jf := FileAccess.open("%s/seed_%d.json" % [out_dir, seed_in], FileAccess.WRITE)
		jf.store_string(JSON.stringify({"seed": seed_in, "sols": sols, "recs": recs, "live_history": live}, "", true, true))
		jf.close()
		var cf := FileAccess.open("%s/seed_%d.csv" % [out_dir, seed_in], FileAccess.WRITE)
		cf.store_line("sol,age,pop,o2_frac,food_frac,o2_net,food_net,demand,supply,offline,shorts,shortage_deaths,ice,ice_days,ice_days_min,ice_min,distressed,rested,calm_share,rested_share,fam,homes,ok,ok40,failed_clauses")
		for r in recs:
			var n := int(r.sol)
			var d := _derive(r)
			var fcl: Array[String] = []
			for c in CLAUSES:
				if not d[c]:
					fcl.append(c)
			var pop2 := maxf(1, int(r.pop))
			cf.store_line("%d,%s,%d,%.4f,%.4f,%.4f,%.4f,%.2f,%.2f,%d,%d,%d,%.2f,%.3f,%.3f,%.2f,%d,%d,%.3f,%.3f,%d,%d,%d,%d,%s" % [
					n, _age_at(rep.hist, n), int(r.pop), float(r.o2f), float(r.foodf), float(r.o2_net), float(r.food_net), float(r.demand), float(r.supply),
					int(r.offline), int(r.shorts), int(r.shortage_deaths), float(r.ice), float(r.ice_days), float(r.ice_days_min), float(r.ice_min),
					int(r.distressed), int(r.rested), float(r.distressed) / pop2, float(r.rested) / pop2, int(r.fam), int(r.homes),
					1 if rep.ok.get(n, false) else 0, int(rep.ok40[n]), "|".join(PackedStringArray(fcl))])
		cf.close()


func _age_at(hist: Array, n: int) -> String:
	var a := Ages.LANDING
	for h in hist:
		if int(h.sol) <= n:
			a = h.age
	return a


## Start sol of the unbroken run of "true" ending at sol s, per entry clause, over Landing sols.
func _run_starts(entry: Dictionary, s: int) -> String:
	var parts: Array[String] = []
	for c in ENTRY:
		parts.append("%s=%d" % [c, _run_start(entry, s, c)])
	return " ".join(PackedStringArray(parts))


func _run_start(entry: Dictionary, s: int, c: String) -> int:
	var start := s
	var n := s
	while n >= 1:
		var e: Variant = entry.get(n)
		if e == null or not e[c]:
			break
		start = n
		n -= 1
	return start


func _last_to_pass(entry: Dictionary, s: int) -> Array[String]:
	var best := -1
	var who: Array[String] = []
	for c in ENTRY:
		var st := _run_start(entry, s, c)
		if st > best:
			best = st
			who = [c]
		elif st == best:
			who.append(c)
	return who


# ------------------------------------------------------------------ sweeps

const SWEEPS := [
	["ages.sample.window_sols", [30, 40, 50], "spec 14"],
	["ages.exit.ok_share_below", [0.5, 0.6, 0.7], "spec 14"],
	["ages.min_dwell_sols", [10, 20, 30], "spec 14"],
	["ages.sample.ice_min_sols", [1, 2, 3], "spec 14"],
	["ages.sample.rested_share_min", [0.5, 0.7, 0.9], "spec 14"],
	["ages.sample.distress_share_max", [0.05, 0.1, 0.2], "extra"],
	["ages.entry.mars_born_homes_min", [1, 2, 3], "extra"],
	["ages.entry.mars_born_min", [3, 5, 8], "extra"],
	["ages.entry.ok_share", [0.8, 0.9, 0.95], "extra"],
	["ages.entry.recent_ok_sols", [1, 3, 5], "extra"],
	["ages.exit.recent_sols", [3, 5, 10], "extra"],
]


func _sweeps(files: Array[String]) -> void:
	var seeds: Array = []
	var data: Dictionary = {}
	for f in files:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		if parsed == null:
			print("cannot read %s" % f)
			continue
		seeds.append(int(parsed.seed))
		data[int(parsed.seed)] = parsed.recs
	var lib: GDScript = load(BL)
	print("# sweeps: one parameter changed per row, all else as shipped; replayed from recorded per-sol inputs; seeds %s" % str(seeds))
	var head := "| parameter = value | " + " | ".join(PackedStringArray(seeds.map(func(s): return "seed %d" % s))) + " |"
	print(head)
	print("|---|" + "---|".repeat(seeds.size()))
	for sw in SWEEPS:
		for v in sw[1]:
			var saved: Array = []
			var err: String = lib.apply_param(sw[0], v, saved)
			if err != "":
				print("PARAM ERROR %s" % err)
				continue
			var cells: Array[String] = []
			for s in seeds:
				var rep := _replay(data[s])
				cells.append("settle %s; %d chg; gap %s; %s" % [
						"never" if rep.first == null else str(rep.first), rep.hist.size() - 1, _min_gap(rep.hist), _hist_text(rep.hist)])
			for e in saved:
				e[0][e[1]] = e[2]
			print("| %s = %s%s%s | %s |" % [sw[0], str(v), " (shipped)" if _is_shipped(sw[0], v) else "", " [extra]" if sw[2] == "extra" else "", " | ".join(PackedStringArray(cells))])
	var cells2: Array[String] = []
	for s in seeds:
		var rep2 := _replay(data[s])
		cells2.append("settle %s; %d chg; gap %s; %s" % ["never" if rep2.first == null else str(rep2.first), rep2.hist.size() - 1, _min_gap(rep2.hist), _hist_text(rep2.hist)])
	print("| (control: shipped values) | " + " | ".join(PackedStringArray(cells2)) + " |")


func _is_shipped(path: String, v: Variant) -> bool:
	var parts := path.split(".")
	var node: Variant = SimData.load_json(parts[0] + ".json")
	for k in range(1, parts.size()):
		node = node[parts[k]]
	return is_equal_approx(float(node), float(v))


# ------------------------------------------------------------------ timing

func _timing(seed_in: int, sols: int, calls: int) -> void:
	var w := SimWorld.new(seed_in)
	while w.sol() < sols:
		w.step()
	var a := w.ages
	print("# on_sol timing: seed=%d, end of sol %d, pop %d, beings %d, buildings %d, age %s, %d calls, state restored before every call (restore is outside the timed region)" % [
			seed_in, w.sol(), w.colony.pop(), w.beings.size(), w.buildings.list.size(), a.age, calls])
	var saved_win := a.window.duplicate(true)
	var sv := {"age": a.age, "lc": a.last_change_sol, "ss": a.snap_shorts, "sd": a.snap_deaths,
			"sa": w.stats.age, "ac": w.stats.age_changes, "fs": w.stats.first_settlement_sol,
			"sia": w.stats.sols_in_age.duplicate(), "ah": w.stats.age_history.size(), "log": w.log.size()}
	var whole := PackedFloat64Array()
	var t_sample := PackedFloat64Array()
	var t_fam := PackedFloat64Array()
	var t_dec := PackedFloat64Array()
	for k in range(calls + 50):
		a.age = sv.age
		a.window = saved_win.duplicate(true)
		a.last_change_sol = sv.lc
		a.snap_shorts = sv.ss
		a.snap_deaths = sv.sd
		w.stats.age = sv.sa
		w.stats.age_changes = sv.ac
		w.stats.first_settlement_sol = sv.fs
		w.stats.sols_in_age = sv.sia.duplicate()
		w.stats.age_history.resize(sv.ah)
		w.log.resize(sv.log)
		var t0 := Time.get_ticks_usec()
		a.on_sol(w)
		var t1 := Time.get_ticks_usec()
		var u0 := Time.get_ticks_usec()
		var smp := Ages.sample(w)
		var u1 := Time.get_ticks_usec()
		var fam := Ages.family_mars_born(w)
		var u2 := Time.get_ticks_usec()
		var _d := Ages.decide(saved_win, Ages.LANDING, 99, fam[0], fam[1])
		var u3 := Time.get_ticks_usec()
		if k >= 50 and smp.size() > 0:
			whole.append(t1 - t0)
			t_sample.append(u1 - u0)
			t_fam.append(u2 - u1)
			t_dec.append(u3 - u2)
	print("us per call (first 50 calls discarded as warm-up):")
	print("  Ages.on_sol           %s" % _stats(whole))
	print("  Ages.sample           %s" % _stats(t_sample))
	print("  Ages.family_mars_born %s" % _stats(t_fam))
	print("  Ages.decide           %s" % _stats(t_dec))


func _stats(v: PackedFloat64Array) -> String:
	var s := Array(v)
	s.sort()
	var sum := 0.0
	for x in s:
		sum += x
	return "n %d  min %.0f  median %.0f  mean %.1f  p95 %.0f  max %.0f" % [s.size(), s[0], s[s.size() / 2], sum / s.size(), s[int(s.size() * 0.95)], s[s.size() - 1]]
