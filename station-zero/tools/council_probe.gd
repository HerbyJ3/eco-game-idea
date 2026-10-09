extends SceneTree
## Council calibration probe (docs/specs/council.md revision 4, section 12; plan task-5 step 6). Modelled on
## tools/relationships_probe.gd.
## READ-ONLY: changes no data file and no sim code. Overrides (--param) go through the SimData cache only
## (tests/balance_lib.gd apply_param) and live for the process. The only thing the probe swaps is the world's Council for a
## subclass (TimedCouncil) that times on_step and on_sol and calls super; it copies the module's cfg and lineage, so the run is
## the same run (the --hash mode proves it against the plain balance table).
##
##   godot --headless --path station-zero --script res://tools/council_probe.gd -- --seed N --sols 300 [--tag T] [--out DIR] [--param path=value ...]
##       one seed on the shipped values (both pulls 0.0): prints the report, writes DIR/seed_N_<tag>.json (summary + per-sol rows)
##       and DIR/seed_N_<tag>.csv. --tag defaults to "base"; a lever run is tagged by the caller (e.g. lean_0.05).
##   ... -- --hash --seed N --sols 300 [--param ...]
##       replay: runs tests/balance_lib.gd run() with the same overrides; prints the table sha256 and the end-state digest the
##       probe printed, which proves the observer did not change the run
##   ... -- --judge DIR [--tag T]
##       reads DIR/seed_N_<tag>.json for the five seeds and prints the markdown tables, replays, targets C1 to C8 and flags
##
## Definitions used where the spec leaves room are listed in docs/balance/task-5-calibration.md ("Definitions").

const BL := "res://tests/balance_lib.gd"
const SEEDS: Array[int] = [42, 7, 99, 1234, 2026]
const READ_SOLS: Array[int] = [30, 60, 100, 150, 200, 250, 300]
## Task 3 projected ages (docs/balance/task-3-calibration.md; balance_lib T10): first Settlement sol and projected change count.
const T3_SETTLE := {42: 67, 7: 58, 99: 54, 1234: 65, 2026: 53}
const T3_CHANGES := {42: 2, 7: 1, 99: 2, 1234: 1, 2026: 1}
const FM := [1, 2]
const GENS := [0, 1, 2]
## --base DIR: the earlier run (same tag) whose stats.council digest the judge compares on the unchanged seeds.
var base_dir := ""


## Times the module's two hooks and calls the real ones. Copies state with the module's own fields; changes no behaviour.
class TimedCouncil extends Council:
	var sol_us: Array = []  # [pop, microseconds] per sol boundary
	var step_acc := 0
	var tick_us: Array = []

	func on_step(world: SimWorld) -> void:
		var t0 := Time.get_ticks_usec()
		super.on_step(world)
		var dt := Time.get_ticks_usec() - t0
		step_acc += dt

	func on_sol(world: SimWorld) -> void:
		var t0 := Time.get_ticks_usec()
		super.on_sol(world)
		var dt := Time.get_ticks_usec() - t0
		sol_us.append([world.colony.pop(), dt])
		step_acc += dt


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_in := 42
	var sols := 300
	var out_dir := ""
	var tag := "base"
	var mode := "seed"
	var params := {}
	var lib: GDScript = load(BL)
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
			"--tag":
				i += 1
				tag = args[i]
			"--param":
				i += 1
				var kv: PackedStringArray = args[i].split("=", true, 1)
				params[kv[0]] = lib.parse_value(kv[1])
			"--base":
				i += 1
				base_dir = args[i]
			"--hash":
				mode = "hash"
			"--judge":
				mode = "judge"
				i += 1
				out_dir = args[i]
		i += 1
	match mode:
		"seed":
			_seed_run(seed_in, sols, tag, out_dir, params)
		"hash":
			_hash_run(seed_in, sols, params)
		"judge":
			_judge(out_dir, tag)
	quit(0)


func _apply(params: Dictionary) -> Array:
	var lib: GDScript = load(BL)
	var saved: Array = []
	for k in params:
		var err: String = lib.apply_param(str(k), params[k], saved)
		if err != "":
			print("PARAM ERROR: " + err)
	return saved


static func _median(a: Array) -> float:
	if a.is_empty():
		return -1.0
	var s := a.duplicate()
	s.sort()
	var n := s.size()
	if n % 2 == 1:
		return float(s[n / 2])
	return (float(s[n / 2 - 1]) + float(s[n / 2])) / 2.0


static func _pctile(a: Array, p: float) -> float:
	if a.is_empty():
		return -1.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(floor(p * s.size())))])


static func _mean(a: Array) -> float:
	if a.is_empty():
		return -1.0
	var t := 0.0
	for v in a:
		t += float(v)
	return t / a.size()


static func _max(a: Array) -> float:
	var m := -1e18
	for v in a:
		m = maxf(m, float(v))
	return m


static func _min(a: Array) -> float:
	var m := 1e18
	for v in a:
		m = minf(m, float(v))
	return m


static func _find(uf: Dictionary, x: int) -> int:
	var r := x
	while int(uf[r]) != r:
		r = int(uf[r])
	return r


## Digest of the run end state: pop, births, deaths, the age history and the whole stats.council dictionary.
static func _digest(w: SimWorld) -> String:
	var d := {"pop": w.colony.pop(), "births": w.stats.births, "deaths": w.stats.deaths, "age": w.stats.age_history,
			"council": w.stats.council}
	return JSON.stringify(d, "", true, true).sha256_text().substr(0, 16)


# ------------------------------------------------------------------ voice readings (every age), for every variant

## Lineage set of an id: itself plus up to g ancestors through the probe's own never-pruned parent record.
static func _lin(parent_of: Dictionary, id: int, g: int) -> Array:
	var out: Array = [id]
	var cur := id
	for k in g:
		cur = int(parent_of.get(cur, 0))
		if cur == 0:
			break
		out.append(cur)
	return out


static func _meet(a: Array, b: Array) -> bool:
	for x in a:
		if x in b:
			return true
	return false


## council.md 5.1 and 5.2 from relationships.pairs: voices, trust, and the chosen share at every (friends_min f, lineage
## generations g). Also the chosen-pair leak counts at g = chosen.kin_generations (2). Read only.
func _readings(w: SimWorld, parent_of: Dictionary, vmin_sols: float) -> Dictionary:
	var rel: Relationships = w.relationships
	var sol_h: float = w.clock.sol_h
	for b in w.beings:
		if not parent_of.has(b.id):
			parent_of[b.id] = int(b.parent_id)
	var voice := {}
	for b in w.beings:
		if b.earth_born or w.t - b.born_t >= vmin_sols * sol_h - SimWorld.STEP_EPS:
			var lins: Array = []
			for g in GENS:
				lins.append(_lin(parent_of, b.id, g))
			voice[b.id] = {"lin": lins, "earth": b.earth_born}
	var nv := voice.size()
	var out := {"voices": nv, "trust": 0.0, "ch": {}, "chosen_pairs": 0, "mars_unrelated": 0, "turned": 0, "friend_pairs": 0}
	for f in FM:
		for g in GENS:
			out.ch["f%dg%d" % [f, g]] = 0.0
	if nv == 0:
		return out
	var uf := {}
	for id in voice:
		uf[id] = id
	var cnt := {}  # g -> {id: chosen friends}
	for g in GENS:
		cnt[g] = {}
	var fpairs := 0
	var chosen_pairs := 0
	var mars_unrel := 0
	var turned := 0
	for key in rel.pairs:
		var p: Dictionary = rel.pairs[key]
		if not p.friends or not voice.has(p.lo) or not voice.has(p.hi):
			continue
		fpairs += 1
		var ra := _find(uf, int(p.lo))
		var rb := _find(uf, int(p.hi))
		if ra != rb:
			uf[maxi(ra, rb)] = mini(ra, rb)
		if p.kin or p.crew:
			continue
		var vl: Dictionary = voice[p.lo]
		var vh: Dictionary = voice[p.hi]
		for g in GENS:
			if not _meet(vl.lin[g], vh.lin[g]):
				cnt[g][p.lo] = int(cnt[g].get(p.lo, 0)) + 1
				cnt[g][p.hi] = int(cnt[g].get(p.hi, 0)) + 1
		if _meet(vl.lin[2], vh.lin[2]):
			turned += 1
		else:
			chosen_pairs += 1
			if not vl.earth and not vh.earth:
				mars_unrel += 1
	var sizes := {}
	for id in voice:
		var r := _find(uf, int(id))
		sizes[r] = int(sizes.get(r, 0)) + 1
	var big := 0
	for r in sizes:
		big = maxi(big, int(sizes[r]))
	out.trust = float(big) / nv
	for f in FM:
		for g in GENS:
			var c := 0
			for id in voice:
				if int(cnt[g].get(id, 0)) >= f:
					c += 1
			out.ch["f%dg%d" % [f, g]] = float(c) / nv
	out.chosen_pairs = chosen_pairs
	out.mars_unrelated = mars_unrel
	out.turned = turned
	out.friend_pairs = fpairs
	return out


# ------------------------------------------------------------------ replay of the gate from stored readings

## 16 of the last 20 readings at least `share`, the window full, the last `recent` all at least `share` (council.md 5.3).
static func _window_ok(win: Array, share: float, ok_min: int, recent: int, wsize: int) -> bool:
	if win.size() < wsize:
		return false
	var ok := 0
	for v in win:
		if float(v) >= share - 1e-9:
			ok += 1
	if ok < ok_min:
		return false
	for i in range(win.size() - recent, win.size()):
		if float(win[i]) < share - 1e-9:
			return false
	return true


## First sol at which the Council gate (5.3) would pass for a variant, from the stored rows; -1 if never. `p` keys: trust_min,
## chosen_min, f, g, ok_min, settled, voices_min, web (bool), chosen (bool). Exact for the FIRST entry: nothing the Council
## does feeds back into the sim, the Landing / not-Landing projection and the Settlement entries are the live ones, and S is the
## latest Settlement entry that is not a Council split (a split cannot precede the first entry).
static func replay_first_entry(rows: Array, p: Dictionary) -> int:
	var tw: Array = []
	var cw: Array = []
	var key := "f%dg%d" % [int(p.f), int(p.g)]
	for r: Dictionary in rows:
		tw.append(float(r.trust))
		cw.append(float(r.ch[key]))
		if tw.size() > 20:
			tw.pop_front()
			cw.pop_front()
		if not bool(r.notland):
			continue
		var s := int(r.sol)
		var sn := int(r.sns)
		if sn < 0 or s - sn < int(p.settled):
			continue
		if bool(p.web) and not _window_ok(tw, float(p.trust_min), int(p.ok_min), 3, 20):
			continue
		if bool(p.chosen) and not _window_ok(cw, float(p.chosen_min), int(p.ok_min), 3, 20):
			continue
		if int(r.voices) < int(p.voices_min):
			continue
		return s
	return -1


static func base_variant() -> Dictionary:
	var e: Dictionary = SimData.council().entry
	return {"trust_min": float(e.trust_share_min), "chosen_min": float(e.chosen_share_min), "f": int(e.chosen_friends_min),
			"g": int(SimData.council().chosen.kin_generations), "ok_min": int(e.trust_ok_min), "settled": int(e.settled_sols),
			"voices_min": int(e.voices_min), "web": true, "chosen": true}


# ------------------------------------------------------------------ one seed

func _seed_run(seed_in: int, sols: int, tag: String, out_dir: String, params: Dictionary) -> void:
	var t_start := Time.get_ticks_msec()
	var saved := _apply(params)
	var w := SimWorld.new(seed_in)
	var oc: Council = w.council
	var tc := TimedCouncil.new()
	tc.cfg = oc.cfg
	tc.parent_of = oc.parent_of
	w.council = tc
	var cfg: Dictionary = tc.cfg
	var rel: Relationships = w.relationships
	var cst: Dictionary = w.stats.council
	var sol_h: float = w.clock.sol_h
	var vmin := float(cfg.voice.min_age_sols)
	var interval := int(cfg.session.interval_sols)
	var yes_above := float(cfg.support.yes_above)
	var no_below := float(cfg.support.no_below)
	var div_share := float(cfg.decide.divided_share)
	var parent_of := {}
	var rows: Array = []
	var votes: Array = []
	var clog: Array = []  # Council lines as logged: {sol, kind, text}
	var kind_n := {}
	var log_total := w.log.size()
	for e0 in w.log:
		kind_n[str(e0.kind)] = int(kind_n.get(str(e0.kind), 0)) + 1
	# observers
	var last_ticks := 0
	var tick_max := 0
	var prev_age := str(w.ages.age)
	var prev_last := tc.last_session_sol
	var prev_sessions := int(cst.sessions)
	var prev_open := -1
	var prop_votes_div := {}  # proposal index -> true once a divided vote was seen
	var eligible := 0
	var eligible_unheld := 0
	var eligible_unheld_sols: Array = []
	var bands := {"b70": {"steps": 0, "step_us": 0, "mod_us": 0}, "b120": {"steps": 0, "step_us": 0, "mod_us": 0},
			"all": {"steps": 0, "step_us": 0, "mod_us": 0}}
	var max_pop := 0
	var sns := -1  # latest Settlement entry that is not a Council split
	var s_all := -1  # latest Settlement entry (any how)
	var hist_seen := 0
	var bnd_us: Array = []  # [pop before, microseconds] of the whole world.step() on sol-boundary steps
	while w.sol() < sols:
		var pop_before := w.colony.pop()
		tc.step_acc = 0
		var t0 := Time.get_ticks_usec()
		w.step()
		var dt := Time.get_ticks_usec() - t0
		for bk in ["all", "b70" if pop_before >= 60 and pop_before <= 80 else "", "b120" if pop_before > 120 else ""]:
			if bk != "":
				bands[bk].steps += 1
				bands[bk].step_us += dt
				bands[bk].mod_us += tc.step_acc
		# log scan: entries logged in this step
		var k := w.log.size() - 1
		while k >= 0 and float(w.log[k].t) == w.t:
			var e: Dictionary = w.log[k]
			var kd := str(e.kind)
			kind_n[kd] = int(kind_n.get(kd, 0)) + 1
			log_total += 1
			if kd.begins_with("council_"):
				clog.append({"sol": int(e.sol), "kind": kd, "text": str(e.text)})
			k -= 1
		# gathering observer: largest number of voices awake in one building at this relationship tick
		if rel.ticks != last_ticks:
			last_ticks = rel.ticks
			var vs := {}
			for b in w.beings:
				if b.earth_born or w.t - b.born_t >= vmin * sol_h - SimWorld.STEP_EPS:
					vs[b.id] = true
			for bid in rel.present:
				var c := 0
				for id in rel.present[bid]:
					if vs.has(id):
						c += 1
				tick_max = maxi(tick_max, c)
		if not w._sol_started:
			continue
		bnd_us.append([pop_before, dt])
		# ---------------- sol boundary row
		var n := w.sol()
		var pop := w.colony.pop()
		max_pop = maxi(max_pop, pop)
		var hh: Array = w.stats.age_history
		while hist_seen < hh.size():
			var he: Dictionary = hh[hist_seen]
			if str(he.age) == Ages.SETTLEMENT:
				s_all = int(he.sol)
				if str(he.how) != "council_split":
					sns = int(he.sol)
			hist_seen += 1
		var rd := _readings(w, parent_of, vmin)
		var age := str(w.ages.age)
		var parts: Dictionary = tc._decide_entry_parts(w, n)
		var notland := age != Ages.LANDING
		var sg := int(cfg.entry.settled_sols)
		var row := {"sol": n, "pop": pop, "voices": int(rd.voices), "trust": float(rd.trust), "ch": rd.ch,
				# live readings are carried placeholders in Landing (sim/council.gd skips the read); -1 marks them as not taken
				"chosen_live": float(cst.chosen) if notland else -1.0, "trust_live": float(cst.trust) if notland else -1.0,
				"voices_live": int(cst.voices) if notland else -1,
				"age": age, "notland": notland, "cn": "P" if cst.pledge_sol != null else ("C" if age == "council" else "-"),
				"s": s_all, "sns": sns, "chosen_pairs": int(rd.chosen_pairs), "mars_unrelated": int(rd.mars_unrelated),
				"turned": int(rd.turned), "friend_pairs": int(rd.friend_pairs),
				"l1": bool(parts.settled), "l2": bool(parts.web), "l3": bool(parts.chosen), "l4": bool(parts.voices)}
		# probe's own gate clauses (projection: any age but Landing counts as settled, S = latest Settlement entry)
		row["c1"] = notland and s_all >= 0 and n - s_all >= sg
		var tw: Array = []
		var cw: Array = []
		# the module pushes no reading in Landing, so its window holds the last 19 non-Landing rows plus this one
		var ckey := "f%dg%d" % [int(cfg.entry.chosen_friends_min), int(cfg.chosen.kin_generations)]
		var j := rows.size() - 1
		while j >= 0 and tw.size() < 19:
			if bool(rows[j].notland):
				tw.push_front(float(rows[j].trust))
				cw.push_front(float(rows[j].ch[ckey]))
			j -= 1
		if notland:
			tw.append(float(rd.trust))
			cw.append(float(rd.ch[ckey]))
		row["c2"] = _window_ok(tw, float(cfg.entry.trust_share_min), int(cfg.entry.trust_ok_min), int(cfg.entry.recent_ok), 20)
		row["c3"] = _window_ok(cw, float(cfg.entry.chosen_share_min), int(cfg.entry.trust_ok_min), int(cfg.entry.recent_ok), 20)
		row["c4"] = int(rd.voices) >= int(cfg.entry.voices_min)
		# conditions and lean (read from the module's own state at this boundary)
		var means := clampf(w.colony.regolith / w.colony.regolith_target(), 0.0, 1.0)
		var size := clampf((float(pop) - float(cfg.dome.cond.size_from)) / float(cfg.dome.cond.size_span), 0.0, 1.0)
		row["means"] = means
		row["size"] = size
		row["hard_share"] = tc.hard_share()
		row["hard_clause"] = tc.hard_clause()
		var ids: Array = tc.stance.keys()
		ids.sort()
		var m := {"lean": 0.0, "stance": 0.0, "personal": 0.0, "size_t": 0.0, "means_t": 0.0, "hard_t": 0.0, "child_t": 0.0}
		var yes_ids: Array = []
		var no_ids: Array = []
		var signdiff := 0
		var pers: Array = []
		var amb := {}
		var cau := {}
		for b in w.beings:
			if tc.stance.has(b.id):
				var tr: Dictionary = b.persona.traits
				amb[b.id] = (float(tr.drive) + float(tr.curiosity) + float(tr.restless)) / 3.0
				cau[b.id] = (float(tr.steady) + float(tr.care)) / 2.0
		for id in ids:
			var sv: float = float(tc.stance[id])
			var lv: float = tc.lean_of(id)
			var tm: Dictionary = tc.lean_terms_of(id)
			m.lean += lv
			m.stance += sv
			m.personal += float(tm.get("personal", 0.0))
			m.size_t += float(tm.get("size", 0.0))
			m.means_t += float(tm.get("means", 0.0))
			m.hard_t += float(tm.get("hard", 0.0))
			m.child_t += float(tm.get("child", 0.0))
			pers.append(float(tm.get("personal", 0.0)))
			if sv > yes_above:
				yes_ids.append(id)
			elif sv < no_below:
				no_ids.append(id)
			if (sv > 0.0 and lv < 0.0) or (sv < 0.0 and lv > 0.0):
				signdiff += 1
		var ns := ids.size()
		var st_mean := 0.0
		for id in ids:
			st_mean += float(tc.stance[id])
		st_mean = st_mean / ns if ns > 0 else 0.0
		var st_var := 0.0
		for id in ids:
			st_var += (float(tc.stance[id]) - st_mean) * (float(tc.stance[id]) - st_mean)
		var pmean := _mean(pers) if not pers.is_empty() else 0.0
		var pvar := 0.0
		for x in pers:
			pvar += (float(x) - pmean) * (float(x) - pmean)
		row["stance_sd"] = sqrt(st_var / ns) if ns > 0 else 0.0
		row["personal_sd"] = sqrt(pvar / pers.size()) if pers.size() > 0 else 0.0
		row["undecided_share"] = float(ns - yes_ids.size() - no_ids.size()) / ns if ns > 0 else 0.0
		for kk in m:
			m[kk] = float(m[kk]) / ns if ns > 0 else 0.0
		row["mean_lean"] = m.lean
		row["mean_stance"] = m.stance
		row["t_personal"] = m.personal
		row["t_size"] = m.size_t
		row["t_means"] = m.means_t
		row["t_hard"] = m.hard_t
		row["t_child"] = m.child_t
		row["yes_share"] = float(yes_ids.size()) / ns if ns > 0 else 0.0
		row["no_share"] = float(no_ids.size()) / ns if ns > 0 else 0.0
		row["gather_max"] = tick_max
		row["gather_share"] = float(tick_max) / float(rd.voices) if int(rd.voices) > 0 else 0.0
		tick_max = 0
		# meeting
		var sessions := int(cst.sessions)
		var held := sessions > prev_sessions
		row["meeting"] = held
		if prev_age == "council" and age == "council" and n - prev_last >= interval:
			eligible += 1
			if not held:
				eligible_unheld += 1
				eligible_unheld_sols.append(n)
		if held:
			var sess: Dictionary = cst.session_log.back()
			var is_vote := prev_open >= 0 and prev_open != n
			var vrec := {"sol": n, "vote": is_vote, "present": int(sess.present), "voices": int(sess.voices),
					"yes": int(sess.yes), "no": int(sess.no), "hard": bool(sess.hard), "building": int(sess.building_id)}
			if is_vote:
				var v: int = maxi(1, int(sess.voices))
				var big := maxi(int(sess.yes), int(sess.no))
				vrec["lockstep"] = float(big) >= float(cfg.balance.lockstep_share) * float(v) - Ages.CMP_EPS
				vrec["divided"] = float(sess.yes) >= div_share * v - Ages.CMP_EPS and float(sess.no) >= div_share * v - Ages.CMP_EPS
				var ay := []
				var an := []
				var cy := []
				var cn_ := []
				for id in yes_ids:
					ay.append(amb[id])
					cy.append(cau[id])
				for id in no_ids:
					an.append(amb[id])
					cn_.append(cau[id])
				vrec["amb_yes"] = _mean(ay) if not ay.is_empty() else -1.0
				vrec["amb_no"] = _mean(an) if not an.is_empty() else -1.0
				vrec["cau_yes"] = _mean(cy) if not cy.is_empty() else -1.0
				vrec["cau_no"] = _mean(cn_) if not cn_.is_empty() else -1.0
				vrec["trait_ok"] = not ay.is_empty() and not an.is_empty() and _mean(ay) > _mean(an) and _mean(cn_) > _mean(cy)
				vrec["signdiff_share"] = float(signdiff) / ns if ns > 0 else 0.0
				var mp := _mean(pers) if not pers.is_empty() else 0.0
				var vv := 0.0
				for x in pers:
					vv += (float(x) - mp) * (float(x) - mp)
				vrec["personal_sd"] = sqrt(vv / pers.size()) if pers.size() > 0 else 0.0
				vrec["mean_stance"] = m.stance
				vrec["stance_sd"] = row.stance_sd
				vrec["undecided_share"] = row.undecided_share
				vrec["mean_lean"] = m.lean
				vrec["t_personal"] = m.personal
				vrec["t_size"] = m.size_t
				vrec["t_means"] = m.means_t
				vrec["t_hard"] = m.hard_t
				vrec["t_child"] = m.child_t
				vrec["proposal"] = cst.proposals.size() - 1
			votes.append(vrec)
		row["open_raised"] = (int(tc.open.raised_sol) if tc.open != null else -1)
		prev_open = int(row.open_raised)
		prev_age = age
		prev_last = tc.last_session_sol
		prev_sessions = sessions
		rows.append(row)
	# ---------------- summary
	var wall := float(Time.get_ticks_msec() - t_start) / 1000.0
	var sum := _summary(w, tc, rows, votes, clog, kind_n, log_total, eligible, eligible_unheld, eligible_unheld_sols, bands, max_pop, seed_in, sols)
	sum.cost["boundary_us"] = _bnd_dists(bnd_us)
	sum["tag"] = tag
	sum["params"] = params
	sum["wall_s"] = wall
	sum["digest"] = _digest(w)
	sum["data_hash"] = str(load(BL).data_hash()).substr(0, 16)
	for e in saved:
		e[0][e[1]] = e[2]
	var rep := _report(sum)
	for line in rep:
		print(line)
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var base := "%s/seed_%d_%s" % [out_dir, seed_in, tag]
		var f := FileAccess.open(base + ".json", FileAccess.WRITE)
		var full := sum.duplicate()
		full["rows"] = rows
		f.store_string(JSON.stringify(full, "", true, true))
		f.close()
		var fc := FileAccess.open(base + ".csv", FileAccess.WRITE)
		fc.store_line("sol,pop,voices,trust,chosen_f1g2,chosen_f1g0,chosen_f1g1,chosen_f2g0,chosen_f2g1,chosen_f2g2,age,cn,hard_share,hard_clause,means,size,mean_lean,t_personal,t_size,t_means,t_hard,t_child,mean_stance,yes_share,no_share,gather_max,gather_share,meeting,c1,c2,c3,c4")
		for r: Dictionary in rows:
			fc.store_line("%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%s,%s,%.2f,%s,%.3f,%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.3f,%.3f,%d,%.3f,%d,%d,%d,%d,%d" % [
					r.sol, r.pop, r.voices, r.trust, r.ch.f1g2, r.ch.f1g0, r.ch.f1g1, r.ch.f2g0, r.ch.f2g1, r.ch.f2g2, r.age, r.cn,
					r.hard_share, r.hard_clause, r.means, r.size, r.mean_lean, r.t_personal, r.t_size, r.t_means, r.t_hard, r.t_child,
					r.mean_stance, r.yes_share, r.no_share, r.gather_max, r.gather_share, 1 if r.meeting else 0,
					1 if r.c1 else 0, 1 if r.c2 else 0, 1 if r.c3 else 0, 1 if r.c4 else 0])
		fc.close()


func _summary(w: SimWorld, tc: TimedCouncil, rows: Array, votes: Array, clog: Array, kind_n: Dictionary, log_total: int,
		eligible: int, eligible_unheld: int, eligible_unheld_sols: Array, bands: Dictionary, max_pop: int, seed_in: int, sols: int) -> Dictionary:
	var cst: Dictionary = w.stats.council
	var cfg: Dictionary = tc.cfg
	var hist: Array = []
	for e in w.stats.age_history:
		hist.append({"sol": int(e.sol), "age": str(e.age), "how": str(e.how), "pop": int(e.pop)})
	var lib: GDScript = load(BL)
	var proj: Array = lib.project_ages(w.stats.age_history)
	var proj_hist: Array = lib.projected_history(w.stats.age_history)
	var proj_sols: Array = []
	for e in proj_hist:
		proj_sols.append(int(e.sol))
	var sum := {"seed": seed_in, "sols": sols, "pop_end": w.colony.pop(), "max_pop": max_pop, "births": int(w.stats.births),
			"deaths": w.stats.deaths, "history": hist, "proj": proj, "proj_sols": proj_sols,
			"proj_changes": maxi(0, proj.size() - 1)}
	# --- readings cross-check: probe against the module's own series
	var dmax_t := 0.0
	var dmax_c := 0.0
	var ct: Array = cst.trust_by_sol
	var cc: Array = cst.chosen_by_sol
	var key := "f%dg%d" % [int(cfg.entry.chosen_friends_min), int(cfg.chosen.kin_generations)]
	var nrows := rows.size()
	var off := ct.size() - nrows  # the founder reading sits first
	for i in nrows:
		if not bool(rows[i].notland):
			continue  # Landing rows hold carried placeholders in the module's series, not readings
		dmax_t = maxf(dmax_t, absf(float(rows[i].trust) - float(ct[i + off])))
		dmax_c = maxf(dmax_c, absf(float(rows[i].ch[key]) - float(cc[i + off])))
	var clause_mismatch := 0
	for r: Dictionary in rows:
		if bool(r.notland) and r.age == "settlement":
			if (bool(r.c1) != bool(r.l1)) or (bool(r.c2) != bool(r.l2)) or (bool(r.c3) != bool(r.l3)) or (bool(r.c4) != bool(r.l4)):
				clause_mismatch += 1
	sum["xcheck"] = {"trust_maxdiff": dmax_t, "chosen_maxdiff": dmax_c, "len_trust_by_sol": ct.size(), "len_chosen_by_sol": cc.size(),
			"len_pop_by_sol": w.stats.pop_by_sol.size(), "rows": nrows, "settlement_clause_mismatch": clause_mismatch}
	# --- milestones
	var ms := {}
	for s in READ_SOLS:
		if s <= nrows:
			var r: Dictionary = rows[s - 1]
			ms[str(s)] = {"pop": r.pop, "voices": r.voices, "trust": r.trust, "chosen": r.ch[key], "age": r.age, "cn": r.cn}
	sum["milestones"] = ms
	# --- crossings: entries, splits, fall-backs, last clause
	var entries: Array = []
	var splits: Array = []
	var fallbacks: Array = []
	var prev_age := "landing"
	for e in hist:
		if e.age == "council":
			var E: int = e.sol
			var onset := {}
			for cl in ["c1", "c2", "c3", "c4"]:
				var o := E
				var i := E - 1
				while i >= 1 and bool(rows[i - 1][cl]):
					o = i
					i -= 1
				onset[cl] = o
			var mx := -1
			for cl in onset:
				mx = maxi(mx, int(onset[cl]))
			var last: Array = []
			var names := {"c1": "settled", "c2": "web", "c3": "chosen", "c4": "voices"}
			for cl in ["c1", "c2", "c3", "c4"]:
				if int(onset[cl]) == mx:
					last.append(names[cl])
			var rr: Dictionary = rows[E - 1]
			entries.append({"sol": E, "how": e.how, "onset": onset, "last": last, "trust": rr.trust, "chosen": rr.ch[key], "voices": rr.voices,
					"pop": rr.pop, "s": rr.s, "wait_after_settled": E - (int(rr.s) + int(cfg.entry.settled_sols))})
		elif e.age == "settlement" and e.how == "council_split":
			splits.append(int(e.sol))
		elif e.age == "landing" and prev_age == "council":
			fallbacks.append(int(e.sol))
		prev_age = e.age
	sum["entries"] = entries
	sum["splits"] = splits
	sum["fallbacks_from_council"] = fallbacks
	sum["first_council_sol"] = cst.first_council_sol
	# council changes (entries plus splits), and the C2 facts
	var changes := entries.size() + splits.size()
	sum["council_changes"] = changes
	var c2_ok := true
	var min_gap := 9999
	var min_since_settle := 9999
	for i in range(1, hist.size()):
		if hist[i].age == "council" or hist[i].how == "council_split":
			min_gap = mini(min_gap, int(hist[i].sol) - int(hist[i - 1].sol))
			if hist[i].age == "council":
				# the Settlement entry before it (any how)
				var sset := -1
				for j in range(i - 1, -1, -1):
					if hist[j].age == "settlement":
						sset = int(hist[j].sol)
						break
				min_since_settle = mini(min_since_settle, int(hist[i].sol) - sset)
	sum["c2"] = {"min_gap_council_changes": min_gap, "min_entry_after_settlement": min_since_settle,
			"ok": (min_gap >= int(cfg.min_dwell_sols) or min_gap == 9999) and (min_since_settle >= 30 or min_since_settle == 9999)}
	# --- discrimination from discrim_from_sol
	var df := int(cfg.balance.discrim_from_sol)
	var tmin := 9.0
	var tmax := -1.0
	var cmin := 9.0
	var cmax := -1.0
	var leak: Array = []
	var turned_max := 0
	var min_web_settled := 9.0
	var min_ch_settled := 9.0
	var settled_rows := 0
	var after_entry_min := 9.0
	var fe: Variant = cst.first_council_sol
	# FLOOR window (12.1): the sols the gate was live, S+30 to the first Council entry (or the end of the Settlement term)
	var fl_web := 9.0
	var fl_ch := 9.0
	var fl_rows := 0
	# CEILING window (12.1): Council terms only
	var cn_web := 9.0
	var cn_rows := 0
	var cn_u50 := 0
	var cn_u30 := 0
	var run30 := 0
	var run30_max := 0
	for r: Dictionary in rows:
		if int(r.sol) >= df:
			tmin = minf(tmin, float(r.trust))
			tmax = maxf(tmax, float(r.trust))
			cmin = minf(cmin, float(r.ch[key]))
			cmax = maxf(cmax, float(r.ch[key]))
			if int(r.chosen_pairs) > 0:
				leak.append(float(r.mars_unrelated) / float(r.chosen_pairs))
			turned_max = maxi(turned_max, int(r.turned))
		if bool(r.c1) and int(r.voices) > 0:
			settled_rows += 1
			min_web_settled = minf(min_web_settled, float(r.trust))
			min_ch_settled = minf(min_ch_settled, float(r.ch[key]))
		if fe != null and int(r.sol) > int(fe):
			after_entry_min = minf(after_entry_min, float(r.trust))
		if bool(r.c1) and r.age == "settlement" and int(r.voices) > 0 and (fe == null or int(r.sol) < int(fe)):
			fl_rows += 1
			fl_web = minf(fl_web, float(r.trust))
			fl_ch = minf(fl_ch, float(r.ch[key]))
		if r.age == "council":
			cn_rows += 1
			cn_web = minf(cn_web, float(r.trust))
			if float(r.trust) < 0.5:
				cn_u50 += 1
			if float(r.trust) < 0.3:
				cn_u30 += 1
				run30 += 1
				run30_max = maxi(run30_max, run30)
			else:
				run30 = 0
		else:
			run30 = 0
	var last_r: Dictionary = rows[nrows - 1]
	sum["discrim"] = {"from_sol": df, "trust_min": tmin, "trust_max": tmax, "chosen_min": cmin, "chosen_max": cmax,
			"leak_end": float(last_r.mars_unrelated) / float(maxi(1, int(last_r.chosen_pairs))), "leak_mean": _mean(leak),
			"chosen_pairs_end": last_r.chosen_pairs, "mars_unrelated_end": last_r.mars_unrelated, "turned_end": last_r.turned,
			"turned_max": turned_max, "friend_pairs_end": last_r.friend_pairs,
			"min_web_after_settled": min_web_settled if settled_rows > 0 else -1.0,
			"min_chosen_after_settled": min_ch_settled if settled_rows > 0 else -1.0, "settled_rows": settled_rows,
			"min_web_after_entry": after_entry_min if fe != null and after_entry_min < 9.0 else -1.0,
			"floor_rows": fl_rows, "floor_web_min": fl_web if fl_rows > 0 else -1.0, "floor_chosen_min": fl_ch if fl_rows > 0 else -1.0,
			"council_rows": cn_rows, "council_web_min": cn_web if cn_rows > 0 else -1.0, "council_u50": cn_u50, "council_u30": cn_u30,
			"council_run_u30": run30_max}
	# --- proposals, votes
	var props: Array = []
	for pi in cst.proposals.size():
		var p: Dictionary = cst.proposals[pi]
		var pv: Array = []
		for v: Dictionary in votes:
			if bool(v.vote) and int(v.proposal) == pi:
				pv.append(v)
		var term := {}
		if p.outcome_sol != null and int(p.outcome_sol) >= 1 and int(p.outcome_sol) <= nrows:
			var orow: Dictionary = rows[int(p.outcome_sol) - 1]
			term = {"mean_lean": orow.mean_lean, "personal": orow.t_personal, "size": orow.t_size, "means": orow.t_means,
					"hard": orow.t_hard, "child": orow.t_child, "personal_sd": orow.personal_sd}
		props.append({"index": pi, "raised_sol": int(p.raised_sol), "proposer_id": int(p.proposer_id), "again": bool(p.again),
				"outcome": p.outcome, "outcome_sol": p.outcome_sol, "reason": p.reason, "hard": p.hard, "votes": pv.size(),
				"vote_sols": pv.map(func(v): return int(v.sol)), "terms_at_outcome": term})
	sum["proposals"] = props
	sum["votes"] = votes
	sum["pledge_sol"] = cst.pledge_sol
	sum["chapters"] = cst.chapters
	sum["sessions"] = int(cst.sessions)
	sum["session_log_n"] = cst.session_log.size()
	# --- raise timing (first raise after each Council entry)
	var rt: Array = []
	for en in entries:
		var nxt := 99999
		for h in hist:
			if int(h.sol) > int(en.sol):
				nxt = int(h.sol)
				break
		var first := -1
		for p in props:
			if int(p.raised_sol) >= int(en.sol) and int(p.raised_sol) <= nxt:
				first = int(p.raised_sol) - int(en.sol)
				break
		rt.append({"entry": en.sol, "first_raise_after": first})
	sum["raise_timing"] = rt
	# --- gatherings
	var gd_all: Array = []
	var gd_all_sh: Array = []
	var gd_council: Array = []
	var gd_council_sh: Array = []
	for r: Dictionary in rows:
		if int(r.sol) >= 60:
			gd_all.append(int(r.gather_max))
			gd_all_sh.append(float(r.gather_share))
		if r.age == "council":
			gd_council.append(int(r.gather_max))
			gd_council_sh.append(float(r.gather_share))
	sum["gather"] = {"all60": _dist(gd_all), "all60_share": _dist(gd_all_sh), "council": _dist(gd_council), "council_share": _dist(gd_council_sh),
			"eligible": eligible, "eligible_unheld": eligible_unheld, "unheld_share": float(eligible_unheld) / float(eligible) if eligible > 0 else -1.0,
			"unheld_sols": eligible_unheld_sols, "council_sols": int(w.stats.sols_in_age.get("council", 0)),
			"meetings_present": _dist(cst.session_log.map(func(s): return int(s.present)))}
	# --- lines
	var lines: Dictionary = cst.lines
	var council_lines := 0
	var council_lines_no_circles := 0
	for kk in lines:
		council_lines += int(lines[kk])
		if not str(kk).begins_with("circles"):
			council_lines_no_circles += int(lines[kk])
	var csols: int = int(w.stats.sols_in_age.get("council", 0))
	var rel_lines := 0
	for kd in kind_n:
		if str(kd).begins_with("rel_"):
			rel_lines += int(kind_n[kd])
	var cl_logged := 0
	for kd in kind_n:
		if str(kd).begins_with("council_"):
			cl_logged += int(kind_n[kd])
	sum["lines"] = {"by_key": lines, "dropped": int(cst.lines_dropped), "council_lines": council_lines,
			"council_lines_no_circles": council_lines_no_circles, "council_sols": csols,
			"per5": 5.0 * council_lines / float(csols) if csols > 0 else -1.0,
			"per5_no_circles": 5.0 * council_lines_no_circles / float(csols) if csols > 0 else -1.0,
			"log_total": log_total, "rel_logged": rel_lines, "council_logged": cl_logged,
			"share": float(rel_lines + cl_logged) / float(maxi(1, log_total)),
			"share_council": float(cl_logged) / float(maxi(1, log_total)),
			"flag": float(SimData.relationships().balance.log_share_flag), "by_kind": kind_n, "log_size_end": w.log.size()}
	sum["clog"] = clog
	sum["sols_in_age"] = w.stats.sols_in_age
	# --- cost
	var su: Array = tc.sol_us
	var cost := {"bands": bands, "max_pop": max_pop}
	var sel70: Array = []
	var sel120: Array = []
	var selpk: Array = []
	var seln: Array = []
	for e in su:
		var p0: int = e[0]
		var us: int = e[1]
		seln.append(us)
		if p0 >= 60 and p0 <= 80:
			sel70.append(us)
		if p0 > 120:
			sel120.append(us)
		if float(p0) >= 0.9 * max_pop:
			selpk.append(us)
	cost["on_sol_us"] = {"all": _dist(seln), "pop60_80": _dist(sel70), "pop_gt120": _dist(sel120), "peak90": _dist(selpk)}
	sum["cost"] = cost
	sum["version_note"] = "t3_settle %d t3_changes %d" % [int(T3_SETTLE.get(seed_in, -1)), int(T3_CHANGES.get(seed_in, -1))]
	return sum


static func _bnd_dists(b: Array) -> Dictionary:
	var all: Array = []
	var g120: Array = []
	for e in b:
		all.append(e[1])
		if int(e[0]) > 120:
			g120.append(e[1])
	return {"all": _dist(all), "pop_gt120": _dist(g120)}


static func _dist(a: Array) -> Dictionary:
	if a.is_empty():
		return {"n": 0}
	return {"n": a.size(), "min": _min(a), "p10": _pctile(a, 0.1), "p25": _pctile(a, 0.25), "median": _median(a), "mean": _mean(a),
			"p75": _pctile(a, 0.75), "p90": _pctile(a, 0.9), "p95": _pctile(a, 0.95), "max": _max(a)}


func _report(s: Dictionary) -> Array[String]:
	var o: Array[String] = []
	o.append("# council probe: seed=%d sols=%d tag=%s params=%s data_hash=%s digest=%s wall %.1f s" % [s.seed, s.sols, s.tag, str(s.params), s.data_hash, s.digest, s.wall_s])
	o.append("pop_end %d max_pop %d births %d deaths %s" % [s.pop_end, s.max_pop, s.births, str(s.deaths)])
	o.append("history %s" % str(s.history))
	o.append("projected %s at sols %s (changes %d); Task 3 first settle %d changes %d" % [str(s.proj), str(s.proj_sols), s.proj_changes, T3_SETTLE.get(s.seed, -1), T3_CHANGES.get(s.seed, -1)])
	o.append("xcheck %s" % str(s.xcheck))
	o.append("milestones %s" % str(s.milestones))
	o.append("entries %s splits %s fallbacks_from_council %s changes %d c2 %s" % [str(s.entries), str(s.splits), str(s.fallbacks_from_council), s.council_changes, str(s.c2)])
	o.append("discrim %s" % str(s.discrim))
	o.append("sessions %d proposals %d pledge_sol %s" % [s.sessions, s.proposals.size(), str(s.pledge_sol)])
	for p in s.proposals:
		o.append("  proposal %s" % str(p))
	for v in s.votes:
		o.append("  meeting %s" % str(v))
	o.append("raise_timing %s" % str(s.raise_timing))
	o.append("gather %s" % str(s.gather))
	o.append("lines %s" % str(s.lines))
	for c in s.clog:
		o.append("  line sol %d %s: %s" % [c.sol, c.kind, c.text])
	o.append("cost %s" % str(s.cost))
	return o


# ------------------------------------------------------------------ hash replay

func _hash_run(seed_in: int, sols: int, params: Dictionary) -> void:
	var lib: GDScript = load(BL)
	var res: Dictionary = lib.run(seed_in, sols, params, 30)
	var w: SimWorld = res.world
	print("# hash run: seed=%d sols=%d overrides=%s" % [seed_in, sols, str(params)])
	print("table_sha256 %s" % str(res.table_hash).substr(0, 16))
	print("digest %s pop_end %d" % [_digest(w), w.colony.pop()])
	for v: Dictionary in res.verdicts:
		if v.n == 10 or v.n == 12:
			print("T%d %s %s" % [v.n, v.verdict, v.detail])


# ------------------------------------------------------------------ judge: tables, replays, targets, flags

func _load(dir: String, seed_in: int, tag: String) -> Dictionary:
	var f := FileAccess.open("%s/seed_%d_%s.json" % [dir, seed_in, tag], FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func _n(v: Variant) -> String:
	if v == null:
		return "-"
	if v is float:
		return "%d" % int(v) if is_equal_approx(v, round(v)) and absf(v) < 1e9 else "%.3f" % v
	return str(v)


## Display copy: whole floats (JSON gives every number as a float) become ints.
static func _c(v: Variant) -> Variant:
	if v is Array:
		return v.map(func(x): return _c(x))
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _c(v[k])
		return d
	if v is float and is_equal_approx(v, round(v)) and absf(v) < 1e9:
		return int(v)
	return v


func _judge(dir: String, tag: String) -> void:
	var S := {}
	for sd in SEEDS:
		var d := _load(dir, sd, tag)
		if d.is_empty():
			print("missing seed %d tag %s" % [sd, tag])
			continue
		S[sd] = d
	var cfg: Dictionary = SimData.council()
	var bal: Dictionary = cfg.balance
	var key := "f%dg%d" % [int(cfg.entry.chosen_friends_min), int(cfg.chosen.kin_generations)]
	var o: Array[String] = []
	o.append("## Judge: tag %s, seeds %s" % [tag, str(S.keys())])
	# --- per seed overview
	o.append("\n### Voices over time (pop / voices / trust / chosen share at the sol)")
	o.append("| seed | " + " | ".join(READ_SOLS.map(func(x): return "sol %d" % x)) + " |")
	o.append("|---|" + "---|".repeat(READ_SOLS.size()))
	for sd in S:
		var cells: Array = []
		for rs in READ_SOLS:
			var m: Dictionary = S[sd].milestones.get(str(rs), {})
			cells.append("%d / %d / %.2f / %.2f %s" % [m.pop, m.voices, m.trust, m.chosen, m.age.substr(0, 1).to_upper()] if not m.is_empty() else "-")
		o.append("| %d | %s |" % [sd, " | ".join(cells)])
	o.append("(age letter: L landing, S settlement, C council)")
	# --- crossings
	o.append("\n### Crossings")
	o.append("| seed | projected sequence (sols) | Task 3 settle / changes | age_history (sol how) | Council entries (sol, how, last clause passed, onsets settled/web/chosen/voices) | splits | fall-backs from Council | changes |")
	o.append("|---|---|---|---|---|---|---|---|")
	for sd in S:
		var d: Dictionary = S[sd]
		var hs: Array = []
		for e in d.history:
			hs.append("%d %s/%s" % [e.sol, e.age, e.how])
		var es: Array = []
		for e in d.entries:
			es.append("%d %s: %s (%d/%d/%d/%d; settled-clause wait %d)" % [e.sol, e.how, "+".join(e.last), e.onset.c1, e.onset.c2, e.onset.c3, e.onset.c4, e.wait_after_settled])
		var proj_s: Array = []
		for i in d.proj.size():
			proj_s.append("%s@%d" % [d.proj[i], d.proj_sols[i]])
		o.append("| %d | %s | %d / %d (%s) | %s | %s | %s | %s | %d |" % [sd, " ".join(proj_s), T3_SETTLE.get(sd, -1), T3_CHANGES.get(sd, -1),
				"match" if d.proj_changes == T3_CHANGES.get(sd, -1) and (d.proj_sols.size() > 1 and int(d.proj_sols[1]) == int(T3_SETTLE.get(sd, -1))) else "DIFFERS",
				"; ".join(hs), "; ".join(es) if not es.is_empty() else "none", str(_c(d.splits)), str(_c(d.fallbacks_from_council)), d.council_changes])
	# --- discrimination
	o.append("\n### Trust discrimination (from sol %d) and flags FLOOR / CEILING" % int(cfg.balance.discrim_from_sol))
	o.append("| seed | trust min / max | chosen min / max | FLOOR window (gate-live sols: S+30 to first entry): sols, min web / min chosen | CEILING window (Council terms only): sols, min web, sols < 0.5, sols < 0.3, longest run < 0.3 | chosen pairs Mars-born+unrelated (end) | mean leak share | pairs turned to family (end / max) |")
	o.append("|---|---|---|---|---|---|---|---|")
	var floor_web := true
	var floor_chosen := true
	var floor_web_any := false
	var floor_chosen_any := false
	var floor_web_seen := false
	var floor_chosen_seen := false
	var ceiling_all := true
	var any_enter := false
	for sd in S:
		var d: Dictionary = S[sd]
		var x: Dictionary = d.discrim
		if float(x.floor_web_min) >= 0.0 and float(x.floor_web_min) < float(cfg.entry.trust_share_min):
			floor_web_any = true
		if float(x.floor_web_min) >= 0.0:
			floor_web_seen = true
		if float(x.floor_chosen_min) >= 0.0 and float(x.floor_chosen_min) < float(cfg.entry.chosen_share_min):
			floor_chosen_any = true
		if float(x.floor_chosen_min) >= 0.0:
			floor_chosen_seen = true
		if d.first_council_sol != null:
			any_enter = true
			if float(x.council_web_min) >= 0.0 and float(x.council_web_min) < 0.5:
				ceiling_all = false
		o.append("| %d | %.3f / %.3f | %.3f / %.3f | %d: %s / %s | %d: %s, %d, %d, %d | %d of %d (%.2f) | %.2f | %d / %d |" % [sd, x.trust_min, x.trust_max, x.chosen_min, x.chosen_max,
				int(x.floor_rows), _n(x.floor_web_min), _n(x.floor_chosen_min), int(x.council_rows), _n(x.council_web_min), int(x.council_u50), int(x.council_u30),
				int(x.council_run_u30), x.mars_unrelated_end, x.chosen_pairs_end, x.leak_end, x.leak_mean, x.turned_end, x.turned_max])
	floor_web = not floor_web_any
	floor_chosen = not floor_chosen_any
	o.append("FLOOR web (no seed's web reading ever below %.2f in its gate-live window): %s" % [float(cfg.entry.trust_share_min), ("n/a, no live window" if not floor_web_seen else ("FLAGGED" if floor_web else "clear"))])
	o.append("FLOOR chosen (no seed's chosen reading ever below %.2f in its gate-live window): %s" % [float(cfg.entry.chosen_share_min), ("n/a, no live window" if not floor_chosen_seen else ("FLAGGED (STOP RULE)" if floor_chosen else "clear"))])
	o.append("CEILING (on every seed that enters, web never below 0.5 inside Council terms): %s" % ("n/a, no seed enters" if not any_enter else ("FLAGGED" if ceiling_all else "clear")))
	# --- proposals
	o.append("\n### Proposals")
	o.append("| seed | # | raised sol | proposer | again | votes | outcome (sol) | reason | hard | vote sols | mean lean at outcome: total = personal + size + means - hard + child |")
	o.append("|---|---|---|---|---|---|---|---|---|---|---|")
	var pledges_size_dominant: Array = []  # old reading: size term above half the mean lean
	var pledges_size_sd: Array = []  # corrected reading (12.1): size term at least one sd of the personal term
	var pledge_detail: Array = []
	var pledge_n := 0
	for sd in S:
		var d: Dictionary = S[sd]
		for p in d.proposals:
			var t: Dictionary = p.terms_at_outcome
			var ts := "-"
			if not t.is_empty():
				ts = "%.3f = %.3f + %.3f + %.3f - %.3f + %.3f" % [t.mean_lean, t.personal, t.size, t.means, t.hard, t.child]
			o.append("| %d | %d | %d | %d | %s | %d | %s (%s) | %s | %s | %s | %s |" % [sd, p.index, p.raised_sol, p.proposer_id, str(p.again), p.votes,
					_n(p.outcome), _n(p.outcome_sol), _n(p.reason), _n(p.hard), str(_c(p.vote_sols)), ts])
			if p.outcome == "pledged" and not t.is_empty():
				pledge_n += 1
				pledges_size_dominant.append(float(t.size) > 0.5 * float(t.mean_lean))
				pledges_size_sd.append(float(t.size) >= float(t.personal_sd) - Ages.CMP_EPS)
				pledge_detail.append("seed %d sol %s: size %.4f, personal sd %.4f, mean lean %.4f" % [sd, _n(p.outcome_sol), t.size, t.personal_sd, t.mean_lean])
	var size_dom_old := pledge_n > 0 and not pledges_size_dominant.has(false)
	var size_dom := pledge_n > 0 and not pledges_size_sd.has(false)
	o.append("\n### Meetings (sol: present / voices, yes, no; V = vote, R = raise or quiet meeting)")
	for sd in S:
		var d: Dictionary = S[sd]
		var parts: Array = []
		for v in d.votes:
			parts.append("%d%s:%d/%d y%d n%d%s" % [v.sol, "V" if v.vote else "R", v.present, v.voices, v.yes, v.no, "H" if v.hard else ""])
		o.append("- %d (%d meetings): %s" % [sd, d.votes.size(), " ".join(parts)])
	# --- LOCKSTEP and factions
	var nv := 0
	var nlock := 0
	var ndiv := 0
	var ndiv_ok := 0
	var nfirst := 0
	var nfirst_ok := 0
	var sign_sh: Array = []
	var sd_p: Array = []
	o.append("\n### Votes: lockstep and factions")
	o.append("| seed | sol | voices | yes | no | one side >= 0.95 | divided (both >= 0.25) | amb yes / no | caution yes / no | trait_ok | stance sign differs from lean | personal sd | mean stance / stance sd | undecided share |")
	o.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for sd in S:
		var d: Dictionary = S[sd]
		var seen_div := {}
		for v in d.votes:
			if not v.vote:
				continue
			nv += 1
			if v.lockstep:
				nlock += 1
			sign_sh.append(float(v.signdiff_share))
			sd_p.append(float(v.personal_sd))
			var first_div := false
			if v.divided:
				ndiv += 1
				if v.trait_ok:
					ndiv_ok += 1
				if not seen_div.has(v.proposal):
					seen_div[v.proposal] = true
					first_div = true
					nfirst += 1
					if v.trait_ok:
						nfirst_ok += 1
			o.append("| %d | %d | %d | %d | %d | %s | %s%s | %.3f / %.3f | %.3f / %.3f | %s | %.3f | %.3f | %.3f / %.3f | %.2f |" % [sd, v.sol, v.voices, v.yes, v.no, str(v.lockstep), str(v.divided),
					" (first)" if first_div else "", v.amb_yes, v.amb_no, v.cau_yes, v.cau_no, str(v.trait_ok), v.signdiff_share, v.personal_sd,
					v.mean_stance, v.stance_sd, v.undecided_share])
	var lockstep := nv > 0 and float(nlock) > 0.5 * float(nv)
	o.append("votes pooled %d, lockstep votes %d (%.0f%%); LOCKSTEP (more than half): %s" % [nv, nlock, 100.0 * nlock / maxf(1.0, nv), "FLAGGED" if lockstep else "clear"])
	o.append("divided votes pooled %d, trait-consistent %d (%.0f%%); first-divided-vote-per-proposal %d, trait-consistent %d" % [ndiv, ndiv_ok, 100.0 * ndiv_ok / maxf(1.0, ndiv), nfirst, nfirst_ok])
	o.append("stance sign differs from lean (share of voices), median over votes %.3f; personal-term sd median over votes %.3f (spec estimate 0.15)" % [_median(sign_sh), _median(sd_p)])
	o.append("pledges %d: %s" % [pledge_n, "; ".join(pledge_detail)])
	o.append("SIZE-DOMINANT (corrected: size term >= one sd of the personal term at every pledge): %s; each pledge: %s" % ["FLAGGED" if size_dom else ("clear" if pledge_n > 0 else "n/a, no pledge"), str(pledges_size_sd)])
	o.append("SIZE-DOMINANT (old reading, size above half the mean lean at every pledge, printed for the record): %s; each pledge: %s" % ["FLAGGED" if size_dom_old else ("clear" if pledge_n > 0 else "n/a, no pledge"), str(pledges_size_dominant)])
	# --- gatherings
	o.append("\n### Gatherings (largest voice gathering at one relationship tick per sol)")
	o.append("| seed | sols >= 60: count median / p90 / max | share of voices median / p90 / max | Council sols: count median / max | eligible meeting sols | unheld | unheld share | meeting size median / max | first raise after entry (sols) |")
	o.append("|---|---|---|---|---|---|---|---|---|")
	var noroom := false
	var first_raise_low := 0
	for sd in S:
		var d: Dictionary = S[sd]
		var g: Dictionary = d.gather
		var a: Dictionary = g.all60
		var ash: Dictionary = g.all60_share
		var cs: Dictionary = g.council
		var mp: Dictionary = g.meetings_present
		var rts: Array = d.raise_timing.map(func(r): return "%d" % r.first_raise_after)
		if not d.raise_timing.is_empty() and int(d.raise_timing[0].first_raise_after) >= 0 and int(d.raise_timing[0].first_raise_after) < int(bal.first_raise_flag_sols):
			first_raise_low += 1
		if float(g.unheld_share) > float(bal.noroom_share_max):
			noroom = true
		o.append("| %d | %s / %s / %s | %s / %s / %s | %s / %s | %d | %d | %s | %s / %s | %s |" % [sd, _n(a.get("median")), _n(a.get("p90")), _n(a.get("max")),
				_n(ash.get("median")), _n(ash.get("p90")), _n(ash.get("max")), _n(cs.get("median")), _n(cs.get("max")), g.eligible, g.eligible_unheld,
				"-" if float(g.unheld_share) < 0.0 else "%.2f" % float(g.unheld_share), _n(mp.get("median")), _n(mp.get("max")), ", ".join(rts) if not rts.is_empty() else "no entry"])
	o.append("NOROOM (unheld share above %.2f on any seed): %s" % [float(bal.noroom_share_max), "FLAGGED" if noroom else "clear"])
	o.append("First-raise delay trigger: first raise under %d sols after entry on %d seeds (trigger at %d): %s" % [int(bal.first_raise_flag_sols), first_raise_low,
			int(bal.first_raise_flag_seeds), "TRIGGERED" if first_raise_low >= int(bal.first_raise_flag_seeds) else "not triggered"])
	# --- lines
	o.append("\n### Lines")
	o.append("| seed | Council sols | lines by key | council lines | per 5 Council sols (all / without circles) | dropped by cap | rel + council share of log (flag %.2f) | council share |" % float(SimData.relationships().balance.log_share_flag))
	o.append("|---|---|---|---|---|---|---|---|")
	var c7_ok := true
	var c7_ok_nc := true
	for sd in S:
		var d: Dictionary = S[sd]
		var l: Dictionary = d.lines
		if float(l.per5) > float(bal.lines_per5_max):
			c7_ok = false
		if float(l.per5_no_circles) > float(bal.lines_per5_max):
			c7_ok_nc = false
		o.append("| %d | %d | %s | %d | %s / %s | %d | %.3f | %.3f |" % [sd, l.council_sols, str(l.by_key), l.council_lines, _n(l.per5), _n(l.per5_no_circles), l.dropped, l.share, l.share_council])
	# --- cost
	o.append("\n### Cost (on_sol microseconds; the probe times the real hooks; runs in parallel are noisy, see the cost runs)")
	o.append("| seed | max pop | on_sol pop 60..80: n median / p95 / max | pop > 120: n median / p95 / max | peak (>= 0.9 max pop): n median / p95 / max | module share of mean step: pop 60..80 / pop > 120 / all |")
	o.append("|---|---|---|---|---|---|")
	for sd in S:
		var d: Dictionary = S[sd]
		var c: Dictionary = d.cost
		var os: Dictionary = c.on_sol_us
		var b: Dictionary = c.bands
		var sh := func(k): return "%.4f" % (float(b[k].mod_us) / float(b[k].step_us)) if int(b[k].step_us) > 0 else "-"
		var cell := func(k):
			var x: Dictionary = os[k]
			return "%d: %s / %s / %s" % [int(x.n), _n(x.get("median")), _n(x.get("p95")), _n(x.get("max"))]
		o.append("| %d | %d | %s | %s | %s | %s / %s / %s |" % [sd, c.max_pop, cell.call("pop60_80"), cell.call("pop_gt120"), cell.call("peak90"), sh.call("b70"), sh.call("b120"), sh.call("all")])
	o.append("\nWhole boundary step (world.step() on sol-boundary steps, microseconds): n median / p95 / max; the 16.7 ms trigger of 11.1 is %d us" % int(float(bal.on_sol_ms_peak_max) * 1000.0))
	o.append("| seed | all boundary steps | pop > 120 |")
	o.append("|---|---|---|")
	for sd in S:
		var bu: Dictionary = S[sd].cost.get("boundary_us", {})
		if bu.is_empty():
			continue
		var bc := func(k):
			var x: Dictionary = bu[k]
			return "%d: %s / %s / %s" % [int(x.n), _n(x.get("median")), _n(x.get("p95")), _n(x.get("max"))] if int(x.n) > 0 else "-"
		o.append("| %d | %s | %s |" % [sd, bc.call("all"), bc.call("pop_gt120")])
	# --- replays
	o.append("\n### Gate replays (first Council entry sol; '-' = never by sol %d; baseline = shipped values; exact for the first entry)" % int(S[S.keys()[0]].sols))
	var base := base_variant()
	var live_first: Array = []
	for sd in S:
		live_first.append(S[sd].first_council_sol)
	o.append("| variant | " + " | ".join(S.keys().map(func(x): return str(x))) + " |")
	o.append("|---|" + "---|".repeat(S.size()))
	var replay_rows := func(label: String, mod: Dictionary):
		var cells: Array = []
		for sd in S:
			var v := base.duplicate()
			v.merge(mod, true)
			var r := replay_first_entry(S[sd].rows, v)
			cells.append("-" if r < 0 else str(r))
		o.append("| %s | %s |" % [label, " | ".join(cells)])
	o.append("| live first_council_sol | " + " | ".join(live_first.map(func(x): return _n(x))) + " |")
	replay_rows.call("baseline replay (must equal live)", {})
	for tv in [0.4, 0.5, 0.6]:
		replay_rows.call("trust_share_min %.1f" % tv, {"trust_min": tv})
	for sv in [20, 30, 45]:
		replay_rows.call("settled_sols %d" % sv, {"settled": sv})
	for ov in [14, 16, 18]:
		replay_rows.call("trust_ok_min %d" % ov, {"ok_min": ov})
	replay_rows.call("web clause off (settled, chosen, voices)", {"web": false})
	replay_rows.call("chosen clause off (settled, web, voices)", {"chosen": false})
	for fv in FM:
		for gv in GENS:
			for cv in [0.3, 0.4, 0.5, 0.6]:
				replay_rows.call("chosen_share_min %.1f, friends_min %d, kin_generations %d" % [cv, fv, gv], {"chosen_min": cv, "f": fv, "g": gv})
	# --- targets
	o.append("\n### Targets")
	var enter_n := 0
	var pledge_seeds: Array = []
	var argue_seeds: Array = []
	var long_seeds: Array = []  # set_aside_long: a stalemate, reported not counted (12.1)
	var c3_ok := true
	var c2_all := true
	for sd in S:
		var d: Dictionary = S[sd]
		if d.first_council_sol != null:
			enter_n += 1
		if d.pledge_sol != null:
			pledge_seeds.append(sd)
		var by: Dictionary = d.lines.by_key
		if int(by.get("divided", 0)) > 0 or int(by.get("set_aside", 0)) > 0 or int(by.get("set_aside_hard", 0)) > 0 or int(by.get("pledge_divided", 0)) > 0:
			argue_seeds.append(sd)
		if int(by.get("set_aside_long", 0)) > 0:
			long_seeds.append(sd)
		if int(d.council_changes) > int(bal.max_council_changes):
			c3_ok = false
		if not bool(d.c2.ok):
			c2_all = false
	o.append("C1 entered by sol 300 on >= %d seeds: %d seeds (%s) -> %s" % [int(bal.council_min_seeds), enter_n, str(live_first.map(func(x): return _n(x))), "PASS" if enter_n >= int(bal.council_min_seeds) else "FAIL"])
	o.append("C2 (structural, T12): %s" % ("PASS" if c2_all else "FAIL"))
	o.append("C3 (<= %d Council changes) -> %s" % [int(bal.max_council_changes), "PASS" if c3_ok else "FAIL"])
	o.append("C4 pledge on >= %d seed(s): seeds %s -> %s" % [int(bal.pledge_min_seeds), str(pledge_seeds), "PASS" if pledge_seeds.size() >= int(bal.pledge_min_seeds) else "FAIL"])
	o.append("C5 (12.1: divided, set_aside, set_aside_hard or pledge_divided) on >= %d seeds: seeds %s -> %s (set_aside_long, reported not counted, on seeds %s)" % [int(bal.argue_min_seeds), str(argue_seeds), "PASS" if argue_seeds.size() >= int(bal.argue_min_seeds) else "FAIL", str(long_seeds)])
	o.append("C6 trait-consistent at >= %.0f%% of divided votes: %d of %d (%.0f%%); first-divided only %d of %d -> %s" % [100.0 * float(bal.faction_trait_share_min), ndiv_ok, ndiv,
			100.0 * ndiv_ok / maxf(1.0, ndiv), nfirst_ok, nfirst, ("n/a, no divided vote" if ndiv == 0 else ("PASS" if float(ndiv_ok) >= float(bal.faction_trait_share_min) * ndiv else "FAIL"))])
	o.append("C7 Council lines <= %.1f per 5 Council sols on every seed: all council_* %s; without circles %s" % [float(bal.lines_per5_max), "PASS" if c7_ok else "FAIL", "PASS" if c7_ok_nc else "FAIL"])
	o.append("Flags: FLOOR web %s; FLOOR chosen %s; CEILING %s; SIZE-DOMINANT %s; LOCKSTEP %s; NOROOM %s" % ["FLAGGED" if floor_web else "clear", "FLAGGED" if floor_chosen else "clear",
			"n/a" if not any_enter else ("FLAGGED" if ceiling_all else "clear"), "FLAGGED" if size_dom else ("n/a" if pledge_n == 0 else "clear"), "FLAGGED" if lockstep else "clear", "FLAGGED" if noroom else "clear"])
	# --- C8 (restated, 11.1), run alone
	var c8_ok := true
	var c8_rows: Array = []
	var bnd_max := 0.0
	for sd in S:
		var d: Dictionary = S[sd]
		var os2: Dictionary = d.cost.on_sol_us.pop_gt120
		var b2: Dictionary = d.cost.bands.b120
		if int(os2.n) == 0:
			c8_rows.append("seed %d: no sol above pop 120" % sd)
			continue
		var share := float(b2.mod_us) / float(b2.step_us) if int(b2.step_us) > 0 else 0.0
		var ok_med := float(os2.median) <= float(bal.on_sol_ms_max) * 1000.0
		var ok_max := float(os2.max) <= float(bal.on_sol_ms_peak_max) * 1000.0
		var ok_sh := share <= float(bal.step_share_max)
		if not (ok_med and ok_max and ok_sh):
			c8_ok = false
		c8_rows.append("seed %d: median %.0f us (limit %.0f) %s, max %.0f us (limit %.0f) %s, share %.4f (limit %.2f) %s" % [sd, float(os2.median), float(bal.on_sol_ms_max) * 1000.0,
				"ok" if ok_med else "OVER", float(os2.max), float(bal.on_sol_ms_peak_max) * 1000.0, "ok" if ok_max else "OVER", share, float(bal.step_share_max), "ok" if ok_sh else "OVER"])
		var bu2: Dictionary = d.cost.get("boundary_us", {})
		if not bu2.is_empty() and int(bu2.all.n) > 0:
			bnd_max = maxf(bnd_max, float(bu2.all.max))
	o.append("C8 (on_sol median at pop > 120 <= %.1f ms, max <= %.1f ms, share <= %.2f; valid only if the run was made alone) -> %s" % [float(bal.on_sol_ms_max), float(bal.on_sol_ms_peak_max), float(bal.step_share_max), "PASS" if c8_ok else "FAIL"])
	for r in c8_rows:
		o.append("  " + r)
	o.append("Boundary-step trigger (11.1): max whole boundary step %.0f us against %.0f us -> %s" % [bnd_max, float(bal.on_sol_ms_peak_max) * 1000.0, "REMEDIES TRIGGERED" if bnd_max > float(bal.on_sol_ms_peak_max) * 1000.0 else "not triggered"])
	# --- option A keep rule (O6): byte-identical seeds, then the rule
	if base_dir != "":
		o.append("\n### Byte-identical check against the base run (digest covers pop, births, deaths, age_history and all of stats.council)")
		var same_all := true
		for sd in [42, 7, 99]:
			var nb := _load(base_dir, sd, "base")
			if nb.is_empty() or not S.has(sd):
				o.append("- seed %d: base or new run missing" % sd)
				same_all = false
				continue
			var same := str(nb.digest) == str(S[sd].digest)
			if not same:
				same_all = false
			o.append("- seed %d: base digest %s, new digest %s -> %s" % [sd, str(nb.digest), str(S[sd].digest), "IDENTICAL" if same else "DIFFERS (a defect)"])
		o.append("Seeds 42, 7, 99 byte-identical: %s" % ("YES" if same_all else "NO"))
		var c4_ok := pledge_seeds.size() >= int(bal.pledge_min_seeds)
		var c5_ok := argue_seeds.size() >= int(bal.argue_min_seeds)
		var c6_ok := ndiv == 0 or float(ndiv_ok) >= float(bal.faction_trait_share_min) * ndiv
		o.append("Keep rule (all of): C4 %s; C5 %s; C6 %s; LOCKSTEP %s; SIZE-DOMINANT (corrected) %s; seeds 42/7/99 identical %s; T12 and hash proof run separately." % [
				"pass" if c4_ok else "FAIL", "pass" if c5_ok else "FAIL", "holds" if c6_ok else "FAIL", "FLAGGED" if lockstep else "clear",
				"FLAGGED" if size_dom else "clear", "yes" if same_all else "NO"])
		var keep := c4_ok and c5_ok and c6_ok and not lockstep and not size_dom and same_all
		o.append("Option A verdict (before T12 and the hash proof): %s" % ("KEEP" if keep else "STOP"))
	for line in o:
		print(line)
