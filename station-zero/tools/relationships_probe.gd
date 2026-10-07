extends SceneTree
## Relationships calibration probe (spec docs/specs/relationships.md revision 6, section 13; plan task-4 step 5).
## Revision 6 adds: newcomer-line sol, late found_friend tail, selectivity ratio and coldest-third mean, population share of
## friends, diagnostics D1 to D3, and targets R1 to R14 (R9 and R8 are not judged here). `lines_dropped_by_type` is not built,
## so R14 is judged on the total `lines_dropped`.
## READ-ONLY: changes no data file and no sim code. Overrides (the pull runs, --param) go through the SimData cache only
## (tests/balance_lib.gd apply_param) and live for the process.
##
##   godot --headless --path station-zero --script res://tools/relationships_probe.gd -- --seed N --sols 300 --pull shipped|friend|both [--out DIR] [--param path=value ...]
##       one seed, one pull setting: prints the report, writes DIR/seed_N_<pull>.csv (per sol) and DIR/seed_N_<pull>.json (summary)
##       shipped = both pulls 0.0; friend = balance.probe_friend_pull only; both = probe_friend_pull and probe_lonely_pull
##       lonely = effects.lonely_pull only (balance.probe_lonely_pull, friend_pull stays 0.0): the Task 5 candidate (council.md section 10)
##   ... -- --hash --seed N --sols 300 --pull P
##       replay: runs tests/balance_lib.gd run() (the balance table) with the same overrides; prints the table sha256 and the
##       same end-state digest the probe printed, which proves the observer did not change the run
##   ... -- --sample60 --seed 42 [--sols 60]
##       item 6: the 1-h tick sample of togetherness against a per-step count, per pair
##   ... -- --cost --seed N --sols 300 [--pull P]
##       items 9 and 10: tick cost by population band, step cost with and without the module (world B has
##       relationships_enabled = false, stepped in lockstep), oldest log entry at the end with and without the module.
##       Run it alone on an idle machine.
##   ... -- --tables DIR
##       reads DIR/seed_N_<pull>.json for the five seeds and prints the markdown tables of docs/balance/task-4-calibration.md
##
## How it observes: after every step it reads the world (never writes). Log lines are counted by scanning the entries whose
## t equals the world's t (those were logged in that step). Togetherness uses its own grouping, written from the spec
## (section 2), not the module's.

const BL := "res://tests/balance_lib.gd"
const SEEDS: Array[int] = [42, 7, 99, 1234, 2026]
const PULLS: Array[String] = ["shipped", "friend", "both", "lonely"]
const READ_SOLS: Array[int] = [30, 60, 100, 150, 200, 300]
const CAPPED: Array[String] = ["friends", "found_friend", "close", "close_crew", "drifted"]
## Council gate numbers of docs/specs/council.md 5.1 to 5.3 (estimates E; data/council.json does not exist yet). Read-only use:
## the probe recomputes the voice readings and the gate clauses, it does not need the Council module.
const VOICE_MIN_AGE_SOLS := 40.0
const KIN_GENERATIONS := 2
const WIN_SOLS := 20
const TRUST_SHARE_MIN := 0.5
const TRUST_OK_MIN := 16
const RECENT_OK := 3
const CHOSEN_SHARE_MIN := 0.5
const CHOSEN_FRIENDS_MIN := 1
const SETTLED_SOLS := 30
const VOICES_MIN := 12
## Repeat-company measure (council.md section 10, clause 3)
const LATE_FROM_SOL := 100
const REPEAT_WINDOW_SOLS := 20


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_in := 42
	var sols := 300
	var out_dir := ""
	var pull := "shipped"
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
			"--pull":
				i += 1
				pull = args[i]
			"--param":
				i += 1
				var kv: PackedStringArray = args[i].split("=", true, 1)
				params[kv[0]] = lib.parse_value(kv[1])
			"--hash":
				mode = "hash"
			"--sample60":
				mode = "sample60"
			"--cost":
				mode = "cost"
			"--tables":
				mode = "tables"
				i += 1
				out_dir = args[i]
		i += 1
	match mode:
		"seed":
			_seed_run(seed_in, sols, pull, out_dir, params)
		"hash":
			_hash_run(seed_in, sols, pull, params)
		"sample60":
			_sample60(seed_in, sols if sols < 300 else 60, params)
		"cost":
			_cost(seed_in, sols, pull, params)
		"tables":
			_tables(out_dir)
	quit(0)


## Pull setting -> the override dictionary (data cache only). Values are read from relationships.json balance keys.
static func pull_params(pull: String) -> Dictionary:
	var bal: Dictionary = SimData.relationships().balance
	match pull:
		"friend":
			return {"relationships.effects.friend_pull": float(bal.probe_friend_pull)}
		"lonely":
			return {"relationships.effects.lonely_pull": float(bal.probe_lonely_pull)}
		"both":
			return {"relationships.effects.friend_pull": float(bal.probe_friend_pull),
					"relationships.effects.lonely_pull": float(bal.probe_lonely_pull)}
	return {}


func _apply(pull: String, params: Dictionary) -> Array:
	var lib: GDScript = load(BL)
	var saved: Array = []
	var all := pull_params(pull)
	all.merge(params, true)
	for k in all:
		var err: String = lib.apply_param(str(k), all[k], saved)
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
	var m := -1.0
	for v in a:
		m = maxf(m, float(v))
	return m


## Digest of the run end state: pop, births, deaths, the age history and the whole stats.relationships dictionary.
static func _digest(w: SimWorld) -> String:
	var d := {"pop": w.colony.pop(), "births": w.stats.births, "deaths": w.stats.deaths, "rel": w.stats.relationships,
			"age": w.stats.age_history}
	return JSON.stringify(d, "", true, true).sha256_text().substr(0, 16)


# ------------------------------------------------------------------ togetherness (spec section 2, own grouping)

## Arrays of being ids that are together at this instant: rooms (inside, awake, same building), the current
## site's crew (state work, job == site), each mining field's crew (state mining, same mine.site). Only groups of 2 or more.
func _groups(w: SimWorld) -> Array:
	var inside := {}
	var work_crew: Array = []
	var mine_groups := {}
	for b in w.beings:
		if b.is_inside():
			if b.state != "sleep":
				if not inside.has(b.building_id):
					inside[b.building_id] = []
				inside[b.building_id].append(b.id)
		elif b.state == "work":
			if b.job != null and b.job == w.buildings.site:
				work_crew.append(b.id)
		elif b.state == "mining" and b.mine != null:
			var s: Variant = b.mine.site
			if not mine_groups.has(s):
				mine_groups[s] = []
			mine_groups[s].append(b.id)
	var out: Array = []
	for bid in inside:
		if inside[bid].size() >= 2:
			out.append(inside[bid])
	if w.buildings.site != null and work_crew.size() >= 2:
		out.append(work_crew)
	for s in mine_groups:
		if mine_groups[s].size() >= 2:
			out.append(mine_groups[s])
	return out


func _count_groups(groups: Array, into: Dictionary) -> void:
	for g in groups:
		var n: int = g.size()
		for i in n:
			for j in range(i + 1, n):
				var k := Relationships.key_of(int(g[i]), int(g[j]))
				into[k] = int(into.get(k, 0)) + 1


# ------------------------------------------------------------------ one seed run

func _seed_run(seed_in: int, sols: int, pull: String, out_dir: String, params: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	var saved := _apply(pull, params)
	var lib: GDScript = load(BL)
	var w := SimWorld.new(seed_in)
	var rel: Relationships = w.relationships
	var rs: Dictionary = w.stats.relationships
	var tick_h := float(SimData.relationships().tick_h)
	# log scan
	var kind_n := {}
	var log_total := w.log.size()
	for e0 in w.log:
		kind_n[str(e0.kind)] = int(kind_n.get(str(e0.kind), 0)) + 1
	var first_line := {}
	var first_any_rel: Variant = null
	var first_capped_line: Variant = null
	var first_newcomer_sol: Variant = null
	# per-tick observers
	var seen := {}
	for b in w.beings:
		seen[b.id] = {"born_sol": 0, "kinless": false, "founder": true, "resolved": -1}
	var together := {}
	var awake := {}
	var workn := {}
	var last_ticks := 0
	var fr_since := {}
	var grown_n := {}
	var recs: Array = []
	var prev_capped := 0
	var prev_grief := 0
	var parts_at := {}
	var births_kinless := 0
	var births_kin := 0
	# repeat-company observers (council.md section 10 clause 3): late newborns, first REPEAT_WINDOW_SOLS sols of life
	var rc := {}          # id -> {born, cur_sol, cur: {other: ticks}, days: {sol: max ticks}, tot: {other: ticks}, present: {sol: true}}
	# voice readings and the Council gate clauses (5.2, 5.3), recomputed from relationships.pairs once a sol
	var parent_of := {}
	var trust_win: Array = []
	var chosen_win: Array = []
	var vrec: Array = []
	var settle_s := -1
	while w.sol() < sols:
		w.step()
		# --- log entries logged in this step
		var k := w.log.size() - 1
		while k >= 0 and float(w.log[k].t) == w.t:
			var e: Dictionary = w.log[k]
			var kd := str(e.kind)
			kind_n[kd] = int(kind_n.get(kd, 0)) + 1
			log_total += 1
			if kd.begins_with("rel_"):
				if not first_line.has(kd) or int(first_line[kd]) > int(e.sol):
					first_line[kd] = int(e.sol)
				if first_any_rel == null or int(e.sol) < int(first_any_rel):
					first_any_rel = int(e.sol)
				if kd != "rel_grief" and (first_capped_line == null or int(e.sol) < int(first_capped_line)):
					first_capped_line = int(e.sol)
			k -= 1
		# --- revision 6 (R12): first logged newcomer line, read from the run-wide counters so log eviction cannot hide it
		if first_newcomer_sol == null and int(rs.lines.friends) + int(rs.lines.found_friend) > 0:
			first_newcomer_sol = w.sol()
		# --- per-tick observers
		if rel.ticks != last_ticks:
			last_ticks = rel.ticks
			var alive := {}
			for b in w.beings:
				alive[b.id] = true
			for b in w.beings:
				if not seen.has(b.id):
					var kinless: bool = b.parent_id == 0 or not alive.has(b.parent_id)
					seen[b.id] = {"born_sol": w.sol(), "kinless": kinless, "founder": false, "resolved": -1}
					if kinless:
						births_kinless += 1
					else:
						births_kin += 1
				if b.state != "sleep":
					awake[b.id] = int(awake.get(b.id, 0)) + 1
					if b.state == "mining" or (b.state == "work" and b.job != null and b.job == w.buildings.site):
						workn[b.id] = int(workn.get(b.id, 0)) + 1
			var tick_groups := _groups(w)
			_count_groups(tick_groups, together)
			var sol_now := w.sol()
			for id in seen:
				var sr0: Dictionary = seen[id]
				if sr0.founder or int(sr0.born_sol) <= LATE_FROM_SOL or sol_now >= int(sr0.born_sol) + REPEAT_WINDOW_SOLS:
					continue
				if not rc.has(id):
					rc[id] = {"born": int(sr0.born_sol), "cur_sol": -1, "cur": {}, "days": {}, "tot": {}, "present": {}}
			for b in w.beings:
				if rc.has(b.id) and sol_now < int(rc[b.id].born) + REPEAT_WINDOW_SOLS:
					rc[b.id].present[sol_now] = true
			for g in tick_groups:
				for a in g:
					if not rc.has(a) or sol_now >= int(rc[a].born) + REPEAT_WINDOW_SOLS:
						continue
					var r1: Dictionary = rc[a]
					if int(r1.cur_sol) != sol_now:
						if int(r1.cur_sol) >= 0:
							r1.days[int(r1.cur_sol)] = int(_max(r1.cur.values())) if not r1.cur.is_empty() else 0
						r1.cur_sol = sol_now
						r1.cur = {}
					for o in g:
						if o != a:
							r1.cur[o] = int(r1.cur.get(o, 0)) + 1
							r1.tot[o] = int(r1.tot.get(o, 0)) + 1
		# --- sol boundary record
		if w._sol_started:
			var s := w.sol()
			var capped := 0
			for f in CAPPED:
				capped += int(rs.lines[f])
			var grief := int(rs.lines.grief)
			var nsince := {}
			grown_n.clear()
			for key in rel.pairs:
				var p: Dictionary = rel.pairs[key]
				if p.friends:
					nsince[key] = int(fr_since.get(key, s))
					if not p.kin and not p.crew:
						grown_n[p.lo] = int(grown_n.get(p.lo, 0)) + 1
						grown_n[p.hi] = int(grown_n.get(p.hi, 0)) + 1
			fr_since = nsince
			for id in seen:
				var sr: Dictionary = seen[id]
				if sr.resolved < 0 and not sr.founder and int(grown_n.get(id, 0)) > 0:
					sr.resolved = s - int(sr.born_sol)
			var vr := _voice_reading(w, rel, parent_of)
			trust_win.append(vr.trust)
			chosen_win.append(vr.chosen)
			if trust_win.size() > WIN_SOLS:
				trust_win.pop_front()
				chosen_win.pop_front()
			if str(w.ages.age) == Ages.SETTLEMENT:
				settle_s = int(w.stats.age_history[w.stats.age_history.size() - 1].sol)
			vr["sol"] = s
			vr["age"] = str(w.ages.age)
			vr["c1"] = str(w.ages.age) == Ages.SETTLEMENT and settle_s >= 0 and s - settle_s >= SETTLED_SOLS
			vr["c2"] = _window_ok(trust_win, TRUST_SHARE_MIN, TRUST_OK_MIN)
			vr["c3"] = _window_ok(chosen_win, CHOSEN_SHARE_MIN, TRUST_OK_MIN)
			vr["c4"] = int(vr.voices) >= VOICES_MIN
			vrec.append(vr)
			if s in READ_SOLS:
				parts_at[s] = _web_parts(rel)
			var d: Dictionary = w.stats.deaths
			var dn := 0
			for dk in d:
				dn += int(d[dk])
			recs.append({"sol": s, "age": str(w.ages.age), "pop": w.colony.pop(), "births": int(w.stats.births), "deaths": dn,
					"pairs": int(rs.pairs), "friend_pairs": int(rs.friend_pairs), "close_pairs": int(rs.close_pairs),
					"web": float(rs.web_share), "second": float(rs.second_share), "lonely": float(rs.lonely_share),
					"friends_mean": float(rs.friends_mean), "lines": capped - prev_capped, "grief": grief - prev_grief,
					"lines_cum": capped, "ff_cum": int(rs.lines.found_friend), "capped_cum": int(rs.lines_capped), "dropped_cum": int(rs.lines_dropped),
					"stale_cum": int(rs.lines_stale), "pending": rel.pending.size(), "formed_cum": int(rs.friendships_formed),
					"close_cum": int(rs.close_formed), "log_size": w.log.size()})
			prev_capped = capped
			prev_grief = grief

	# ------------------------------------------------------------ end-of-run analysis
	var alive_b: Array = []
	for b in w.beings:
		alive_b.append(b)
	var sum := {}
	sum["seed"] = seed_in
	sum["pull"] = pull
	sum["sols"] = sols
	sum["params"] = params
	sum["data_hash"] = str(lib.data_hash()).substr(0, 16)
	sum["digest"] = _digest(w)
	sum["pop_end"] = w.colony.pop()
	sum["births"] = int(w.stats.births)
	sum["first_birth_sol"] = w.stats.first_birth_sol
	sum["deaths"] = w.stats.deaths.duplicate()
	var hist: Array = []
	for h in w.stats.age_history:
		hist.append({"sol": int(h.sol), "age": str(h.age), "how": str(h.get("how", "")), "cause": "" if h.get("cause") == null else str(h.get("cause"))})
	sum["age_history"] = hist
	sum["age_end"] = str(w.ages.age)
	sum["first_settlement_sol"] = w.stats.first_settlement_sol
	# item 1
	sum["first_friendship_sol"] = rs.first_friendship_sol
	sum["first_mars_born_friendship_sol"] = rs.first_mars_born_friendship_sol
	sum["first_rel_line_sol"] = first_any_rel
	sum["first_newcomer_line_sol"] = first_newcomer_sol
	sum["first_capped_line_sol"] = first_capped_line
	sum["first_line_by_kind"] = first_line
	sum["lines"] = rs.lines.duplicate()
	sum["lines_capped"] = int(rs.lines_capped)
	sum["lines_dropped"] = int(rs.lines_dropped)
	sum["lines_stale"] = int(rs.lines_stale)
	sum["friendships_formed"] = int(rs.friendships_formed)
	sum["friendships_renewed"] = int(rs.friendships_renewed)
	sum["close_formed"] = int(rs.close_formed)
	sum["drifted"] = int(rs.drifted)
	sum["crew_drifted"] = int(rs.crew_drifted)
	var line_sols: Array = []
	var line_all: Array = []
	var cum20 := 0
	var cum_end := 0
	for r in recs:
		line_all.append(int(r.lines))
		if int(r.sol) >= 21:
			line_sols.append(int(r.lines))
		if int(r.sol) == 20:
			cum20 = int(r.lines_cum)
		if int(r.sol) == sols:
			cum_end = int(r.lines_cum)
	var span := sols - 20
	sum["lines_20_300"] = cum_end - cum20
	sum["mean_lines_per_5sols_20_300"] = 5.0 * float(cum_end - cum20) / maxf(1.0, float(span))
	sum["max_lines_per_sol"] = int(_max(line_all))
	sum["mean_lines_per_sol"] = float(cum_end - cum20) / maxf(1.0, float(span))
	var zero_blocks := 0
	var blocks := 0
	var bi := 0
	while bi + 5 <= line_sols.size():
		var tot := 0
		for q in 5:
			tot += int(line_sols[bi + q])
		blocks += 1
		if tot == 0:
			zero_blocks += 1
		bi += 5
	# R13: found_friend lines per 5 sols, sols 150..299, against the mean over sols 20..299 (cum at the sol-N record = lines before sol N)
	var ff20 := 0
	var ff150 := 0
	var ff_end := 0
	for r in recs:
		if int(r.sol) == 20:
			ff20 = int(r.ff_cum)
		if int(r.sol) == 150:
			ff150 = int(r.ff_cum)
		if int(r.sol) == sols:
			ff_end = int(r.ff_cum)
	sum["ff_tail_per5"] = 5.0 * float(ff_end - ff150) / maxf(1.0, float(sols - 150))
	sum["ff_base_per5"] = 5.0 * float(ff_end - ff20) / maxf(1.0, float(sols - 20))
	sum["ff_tail_n"] = ff_end - ff150
	# revision 7 (R13 context): births in sols 150..299 and found_friend lines per birth in that window
	var b150 := 0
	var b_end := 0
	for r in recs:
		if int(r.sol) == 150:
			b150 = int(r.births)
		if int(r.sol) == sols:
			b_end = int(r.births)
	sum["births_tail"] = b_end - b150
	sum["ff_per_birth_tail"] = float(ff_end - ff150) / float(b_end - b150) if b_end > b150 else -1.0
	sum["ff_base_n"] = ff_end - ff20
	sum["zero_5sol_blocks"] = zero_blocks
	sum["blocks_5sol"] = blocks
	# item 2
	var reads := {}
	for r in recs:
		if int(r.sol) in READ_SOLS:
			reads[str(int(r.sol))] = {"web": r.web, "second": r.second, "lonely": r.lonely, "friends_mean": r.friends_mean,
					"pop": r.pop, "friends_pop_share": (float(r.friends_mean) / float(int(r.pop) - 1)) if int(r.pop) > 1 else 0.0,
					"friend_pairs": r.friend_pairs, "parts3": parts_at.get(int(r.sol), -1)}
	sum["readings"] = reads
	# item 3 personality
	var rows: Array = []
	for b in alive_b:
		var tr: Dictionary = b.persona.traits
		var aw := int(awake.get(b.id, 0))
		rows.append({"id": b.id, "warmth": (float(tr.sociability) + float(tr.care)) / 2.0, "restless": float(tr.restless),
				"friends": int(rel.friend_count.get(b.id, 0)), "work_share": float(workn.get(b.id, 0)) / maxf(1.0, float(aw)),
				"awake_ticks": aw, "born_sol": int(seen[b.id].born_sol)})
	sum["n_alive"] = rows.size()
	sum["personality"] = _third_split(rows)
	# R3 window mean and D3 (dead lonely signal)
	var win := int(SimData.relationships().balance.lonely_window_sols)
	var lby: Array = rs.lonely_by_sol
	var tail: Array = lby.slice(maxi(0, lby.size() - win))
	sum["lonely_window_mean"] = _mean(tail)
	sum["lonely_window_n"] = tail.size()
	var dead := not tail.is_empty()
	for v in tail:
		if float(v) != 0.0:
			dead = false
	sum["d3_lonely_dead"] = dead
	# item 4 work check: split by work share, then warm vs cold third inside each half
	var by_work := rows.duplicate()
	by_work.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return x.work_share > y.work_share or (x.work_share == y.work_share and x.id < y.id))
	var half := by_work.size() / 2
	var top: Array = by_work.slice(0, half)
	var bot: Array = by_work.slice(half)
	sum["work_check"] = {"top_half": _third_split(top), "bottom_half": _third_split(bot),
			"top_share_mean": _mean(top.map(func(x: Dictionary) -> float: return x.work_share)),
			"bottom_share_mean": _mean(bot.map(func(x: Dictionary) -> float: return x.work_share))}
	# bond age by pair restless, friendships alive at the end
	var by_id := {}
	for b in alive_b:
		by_id[b.id] = b
	var prs: Array = []
	for key in fr_since:
		var p: Dictionary = rel.pairs[key]
		if not by_id.has(p.lo) or not by_id.has(p.hi):
			continue
		prs.append({"restless": (float(by_id[p.lo].persona.traits.restless) + float(by_id[p.hi].persona.traits.restless)) / 2.0,
				"age": sols - int(fr_since[key]), "grown": not p.kin and not p.crew, "key": key})
	prs.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return x.restless > y.restless or (x.restless == y.restless and x.key < y.key))
	sum["bond_age"] = _age_split(prs, false)
	sum["bond_age_grown"] = _age_split(prs, true)
	# item 5 hours together per sol
	var fh: Array = []
	var nh: Array = []
	var nh_all: Array = []
	var ids_sorted: Array = by_id.keys()
	ids_sorted.sort()
	for ai in ids_sorted.size():
		for bj in range(ai + 1, ids_sorted.size()):
			var a: int = ids_sorted[ai]
			var c: int = ids_sorted[bj]
			var key := Relationships.key_of(a, c)
			var since := maxi(int(seen[a].born_sol), int(seen[c].born_sol))
			var overlap := maxf(1.0, float(sols - since))
			var hrs := float(together.get(key, 0)) * tick_h / overlap
			if rel.are_friends(a, c):
				fh.append(hrs)
			else:
				nh_all.append(hrs)
				if together.has(key):
					nh.append(hrs)
	sum["together"] = {"friend_pairs": fh.size(), "friend_median": _median(fh), "friend_mean": _mean(fh),
			"nonfriend_pairs_co_present": nh.size(), "nonfriend_median_co_present": _median(nh),
			"nonfriend_pairs_all": nh_all.size(), "nonfriend_median_all": _median(nh_all)}
	# D1: friend pairs among the living over living pairs ever together at a tick (own set, from `together`)
	var ever := 0
	var ever_friend := 0
	for key in together:
		var lo_id: int = int(key) >> 20
		var hi_id: int = int(key) & ((1 << 20) - 1)
		if by_id.has(lo_id) and by_id.has(hi_id):
			ever += 1
			if rel.are_friends(lo_id, hi_id):
				ever_friend += 1
	var fp_alive := int(rs.friend_pairs)
	sum["d1"] = {"friend_pairs": fp_alive, "ever_together_pairs": ever, "friend_pairs_ever_together": ever_friend,
			"share": float(fp_alive) / maxf(1.0, float(ever)), "share_both": float(ever_friend) / maxf(1.0, float(ever))}
	# item 7: newborns after sol 100
	var cohort: Array = []
	for r in rows:
		if int(r.born_sol) > 100:
			cohort.append(r)
	cohort.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return x.friends < y.friends or (x.friends == y.friends and x.id < y.id))
	var third := maxi(1, cohort.size() / 3) if not cohort.is_empty() else 0
	var low: Array = cohort.slice(0, third)
	sum["newborn_after_100"] = {"n": cohort.size(), "mean_friends": _mean(cohort.map(func(x: Dictionary) -> int: return x.friends)),
			"loneliest_third_n": low.size(), "loneliest_third_mean": _mean(low.map(func(x: Dictionary) -> int: return x.friends)),
			"zero_friends": cohort.filter(func(x: Dictionary) -> bool: return x.friends == 0).size()}
	# item 8 kinless
	var rk: Array = []
	var rn: Array = []
	var unres_k := 0
	var unres_n := 0
	for id in seen:
		var sr: Dictionary = seen[id]
		if sr.founder:
			continue
		if sr.kinless:
			if sr.resolved >= 0:
				rk.append(sr.resolved)
			else:
				unres_k += 1
		else:
			if sr.resolved >= 0:
				rn.append(sr.resolved)
			else:
				unres_n += 1
	sum["kinless"] = {"births": births_kinless + births_kin, "kinless": births_kinless, "kin": births_kin,
			"kinless_share": float(births_kinless) / maxf(1.0, float(births_kinless + births_kin)),
			"kinless_median_sols": _median(rk), "kinless_resolved": rk.size(), "kinless_unresolved": unres_k,
			"kin_median_sols": _median(rn), "kin_resolved": rn.size(), "kin_unresolved": unres_n}
	# item 10 log share
	var rel_n := 0
	var rel_cap_n := 0
	for kd in kind_n:
		if str(kd).begins_with("rel_"):
			rel_n += int(kind_n[kd])
			if kd != "rel_grief":
				rel_cap_n += int(kind_n[kd])
	sum["log"] = {"total_entries": log_total, "rel_entries": rel_n, "rel_share": float(rel_n) / maxf(1.0, float(log_total)),
			"rel_capped_kinds": rel_cap_n, "by_kind": kind_n, "log_size_end": w.log.size(),
			"oldest_sol_end": int(w.log[0].sol) if not w.log.is_empty() else -1}
	_lonely_measures(sum, w, rc, seen, vrec, recs, sols, tick_h)
	sum["wall_s"] = (Time.get_ticks_msec() - t0) / 1000.0
	sum["targets"] = _targets(sum)

	# ------------------------------------------------------------ output
	var out: Array[String] = _report(sum)
	for l in out:
		print(l)
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var base := "%s/seed_%d_%s" % [out_dir, seed_in, pull]
		var jf := FileAccess.open(base + ".json", FileAccess.WRITE)
		jf.store_string(JSON.stringify(sum, "  ", true, true))
		jf.close()
		var cf := FileAccess.open(base + ".csv", FileAccess.WRITE)
		cf.store_line("sol,age,pop,births,deaths,pairs,friend_pairs,close_pairs,web,second,lonely,friends_mean,lines,grief,lines_cum,capped_cum,dropped_cum,stale_cum,pending,formed_cum,close_cum,log_size")
		for r in recs:
			cf.store_line("%d,%s,%d,%d,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
					r.sol, "L" if r.age == Ages.LANDING else "S", r.pop, r.births, r.deaths, r.pairs, r.friend_pairs, r.close_pairs,
					r.web, r.second, r.lonely, r.friends_mean, r.lines, r.grief, r.lines_cum, r.capped_cum, r.dropped_cum,
					r.stale_cum, r.pending, r.formed_cum, r.close_cum, r.log_size])
		cf.close()
	for e in saved:
		e[0][e[1]] = e[2]


## 16 of the last 20 readings at least `share`, the window full, and the last RECENT_OK all at least `share` (council.md 5.3 clauses 2, 3).
static func _window_ok(win: Array, share: float, ok_min: int) -> bool:
	if win.size() < WIN_SOLS:
		return false
	var ok := 0
	for v in win:
		if float(v) >= share - 1e-9:
			ok += 1
	if ok < ok_min:
		return false
	for i in range(win.size() - RECENT_OK, win.size()):
		if float(win[i]) < share - 1e-9:
			return false
	return true


## The voice readings of council.md 5.1 and 5.2, from the live web (read only). parent_of is the probe's own lineage record
## (never pruned). Returns {voices, trust, chosen, family_turned}.
func _voice_reading(w: SimWorld, rel: Relationships, parent_of: Dictionary) -> Dictionary:
	var sol_h: float = w.clock.sol_h
	var voice := {}
	for b in w.beings:
		if not parent_of.has(b.id):
			parent_of[b.id] = int(b.parent_id)
	for b in w.beings:
		if b.earth_born or w.t - b.born_t >= VOICE_MIN_AGE_SOLS * sol_h - SimWorld.STEP_EPS:
			var lin := {b.id: true}
			var cur: int = b.id
			for g in KIN_GENERATIONS:
				var par: int = int(parent_of.get(cur, 0))
				if par == 0:
					break
				lin[par] = true
				cur = par
			voice[b.id] = lin
	var n := voice.size()
	if n == 0:
		return {"voices": 0, "trust": 0.0, "chosen": 0.0, "family_turned": 0}
	var uf := {}
	for id in voice:
		uf[id] = id
	var chosen_n := {}
	var turned := 0
	for key in rel.pairs:
		var p: Dictionary = rel.pairs[key]
		if not p.friends or not voice.has(p.lo) or not voice.has(p.hi):
			continue
		var ra := _find(uf, int(p.lo))
		var rb := _find(uf, int(p.hi))
		if ra != rb:
			uf[maxi(ra, rb)] = mini(ra, rb)
		if not p.kin and not p.crew:
			var fam := false
			for x in voice[p.lo]:
				if voice[p.hi].has(x):
					fam = true
					break
			if fam:
				turned += 1
			else:
				chosen_n[p.lo] = int(chosen_n.get(p.lo, 0)) + 1
				chosen_n[p.hi] = int(chosen_n.get(p.hi, 0)) + 1
	var sizes := {}
	for id in voice:
		var r := _find(uf, int(id))
		sizes[r] = int(sizes.get(r, 0)) + 1
	var big := 0
	for r in sizes:
		big = maxi(big, int(sizes[r]))
	var with_chosen := 0
	for id in voice:
		if int(chosen_n.get(id, 0)) >= CHOSEN_FRIENDS_MIN:
			with_chosen += 1
	return {"voices": n, "trust": float(big) / n, "chosen": float(with_chosen) / n, "family_turned": turned}


## Adds the Task 5 lonely-run measures to the summary: zero-friend late newborns, repeat company, breadth, gate readings, F4 items.
func _lonely_measures(sum: Dictionary, w: SimWorld, rc: Dictionary, seen: Dictionary, vrec: Array, recs: Array, sols: int, tick_h: float) -> void:
	# zero-friend late newborns (K1 definition: friend_count 0, kin included; born after sol 100; alive at the end)
	var nb: Dictionary = sum.newborn_after_100
	sum["zero_friend"] = {"n": int(nb.n), "zero": int(nb.zero_friends),
			"share": (float(nb.zero_friends) / float(nb.n)) if int(nb.n) > 0 else -1.0}
	# repeat company and breadth
	var medians: Array = []
	var distinct: Array = []
	var top_share: Array = []
	var hours_total: Array = []
	for id in rc:
		var r: Dictionary = rc[id]
		if int(r.cur_sol) >= 0 and not r.days.has(int(r.cur_sol)):
			r.days[int(r.cur_sol)] = int(_max(r.cur.values())) if not r.cur.is_empty() else 0
		var born := int(r.born)
		if born + REPEAT_WINDOW_SOLS > sols:
			continue
		var full := true
		for d in REPEAT_WINDOW_SOLS:
			if not r.present.has(born + d):
				full = false
				break
		if not full:
			continue
		var daily: Array = []
		for d in REPEAT_WINDOW_SOLS:
			daily.append(float(int(r.days.get(born + d, 0))) * tick_h)
		medians.append(_median(daily))
		distinct.append(r.tot.size())
		var tot := 0
		var top := 0
		for o in r.tot:
			tot += int(r.tot[o])
			top = maxi(top, int(r.tot[o]))
		hours_total.append(float(tot) * tick_h / REPEAT_WINDOW_SOLS)
		top_share.append(float(top) / float(tot) if tot > 0 else 0.0)
	sum["repeat"] = {"n": medians.size(), "value": _median(medians),
			"mean_of_newborns": _mean(medians), "distinct_met_median": _median(distinct),
			"top_share_median": _median(top_share), "group_hours_per_sol_median": _median(hours_total),
			"tracked": rc.size()}
	# gate readings (voices, trust, chosen) and the clauses
	var first_all := -1
	var first_nochosen := -1
	var bind_sols := 0
	var min_trust := 2.0
	var min_chosen := 2.0
	var turned_max := 0
	for v in vrec:
		turned_max = maxi(turned_max, int(v.family_turned))
		if int(v.sol) >= 60:
			min_trust = minf(min_trust, float(v.trust))
			min_chosen = minf(min_chosen, float(v.chosen))
		if v.c1 and v.c2 and v.c4:
			if first_nochosen < 0:
				first_nochosen = int(v.sol)
			if not v.c3:
				bind_sols += 1
		if v.c1 and v.c2 and v.c3 and v.c4 and first_all < 0:
			first_all = int(v.sol)
	var at_all: Dictionary = {}
	var at_nc: Dictionary = {}
	for v in vrec:
		if int(v.sol) == first_all:
			at_all = {"sol": v.sol, "voices": v.voices, "trust": v.trust, "chosen": v.chosen}
		if int(v.sol) == first_nochosen:
			at_nc = {"sol": v.sol, "voices": v.voices, "trust": v.trust, "chosen": v.chosen}
	var readings_at := {}
	for v in vrec:
		if int(v.sol) in READ_SOLS:
			readings_at[str(int(v.sol))] = {"voices": v.voices, "trust": v.trust, "chosen": v.chosen}
	sum["gate"] = {"earliest_entry_sol": first_all, "at_entry": at_all, "first_open_without_chosen_sol": first_nochosen,
			"at_open_without_chosen": at_nc, "chosen_binding_sols": bind_sols,
			"chosen_binds": first_all != first_nochosen, "min_trust_from_60": min_trust if min_trust <= 1.0 else -1.0,
			"min_chosen_from_60": min_chosen if min_chosen <= 1.0 else -1.0, "family_turned_max": turned_max, "readings": readings_at}
	# F4-1: longest run of sols with no capped-kind line before the first newcomer line
	var fn = sum.first_newcomer_line_sol
	var run := 0
	var longest := 0
	for r in recs:
		if fn != null and int(r.sol) >= int(fn):
			break
		if int(r.lines) == 0:
			run += 1
			longest = maxi(longest, run)
		else:
			run = 0
	sum["f4_1_longest_no_line_run_before_newcomer"] = longest
	sum["f4"] = {"r13_over_2_5": float(sum.ff_tail_per5) > 2.5, "log_share_over_0_15": float(sum.log.rel_share) > 0.15,
			"newcomer_later_than_80": fn != null and int(fn) > 80, "newcomer_later_than_68": fn != null and int(fn) > 68,
			"newcomer_never": fn == null}
	sum["deaths_unexplained"] = int(w.stats.deaths_unexplained)


## Union-find over the friend pairs of the living: number of web parts of size 3 or more.
func _web_parts(rel: Relationships) -> int:
	var uf := {}
	for k in rel.friend_count:
		uf[k] = k
	for key in rel.pairs:
		var p: Dictionary = rel.pairs[key]
		if not p.friends or not uf.has(p.lo) or not uf.has(p.hi):
			continue
		var ra: int = _find(uf, p.lo)
		var rb: int = _find(uf, p.hi)
		if ra != rb:
			uf[maxi(ra, rb)] = mini(ra, rb)
	var sizes := {}
	for k in uf:
		var r := _find(uf, k)
		sizes[r] = int(sizes.get(r, 0)) + 1
	var n := 0
	for r in sizes:
		if int(sizes[r]) >= 3:
			n += 1
	return n


static func _find(uf: Dictionary, x: int) -> int:
	var r := x
	while int(uf[r]) != r:
		r = int(uf[r])
	return r


## Warmest third against coldest third by warmth (ties by id): mean friend counts.
func _third_split(rows: Array) -> Dictionary:
	var s := rows.duplicate()
	s.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return x.warmth > y.warmth or (x.warmth == y.warmth and x.id < y.id))
	var n := s.size()
	if n < 3:
		return {"n": n, "warm_mean": -1.0, "cold_mean": -1.0, "third": 0}
	var third := n / 3
	var warm: Array = s.slice(0, third)
	var cold: Array = s.slice(n - third)
	return {"n": n, "third": third, "warm_mean": _mean(warm.map(func(x: Dictionary) -> int: return x.friends)),
			"cold_mean": _mean(cold.map(func(x: Dictionary) -> int: return x.friends)),
			"warm_warmth": _mean(warm.map(func(x: Dictionary) -> float: return x.warmth)),
			"cold_warmth": _mean(cold.map(func(x: Dictionary) -> float: return x.warmth))}


## `prs` is sorted by pair restless, descending. Top third (most restless) against bottom third: mean friendship age in sols.
func _age_split(prs: Array, grown_only: bool) -> Dictionary:
	var s: Array = prs.filter(func(x: Dictionary) -> bool: return x.grown or not grown_only)
	var n := s.size()
	if n < 3:
		return {"n": n}
	var third := n / 3
	return {"n": n, "third": third, "restless_top_age": _mean(s.slice(0, third).map(func(x: Dictionary) -> int: return x.age)),
			"restless_bottom_age": _mean(s.slice(n - third).map(func(x: Dictionary) -> int: return x.age)),
			"restless_top": _mean(s.slice(0, third).map(func(x: Dictionary) -> float: return x.restless)),
			"restless_bottom": _mean(s.slice(n - third).map(func(x: Dictionary) -> float: return x.restless))}


# ------------------------------------------------------------------ targets (spec section 13, last paragraph)

func _targets(sum: Dictionary) -> Dictionary:
	var bal: Dictionary = SimData.relationships().balance
	var t := {}
	var ffs: Variant = sum.first_friendship_sol
	var fb: Variant = sum.first_birth_sol
	var gap: Variant = null
	if ffs != null and fb != null:
		gap = int(ffs) - int(fb)
	# revision 7: R1 is birth-relative, the kin newborns' median wait (item 8 (b)); unresolved newborns are counted and left out.
	var kn: Dictionary = sum.kinless
	var kmed := float(kn.kin_median_sols)
	t["R1_kin_newborn_median_wait"] = [int(kn.kin_resolved) > 0 and kmed <= float(bal.first_friend_gap_sols), "kin newborns median birth-to-first-friend %.1f sols (max %d), resolved %d, unresolved %d (left out); colony-first gap reported only: first birth %s, first_friendship_sol %s, gap %s" % [
			kmed, int(bal.first_friend_gap_sols), int(kn.kin_resolved), int(kn.kin_unresolved), str(fb), str(ffs), "-" if gap == null else str(gap)]]
	var fl: Variant = sum.first_capped_line_sol
	t["R2_first_line_lt_30"] = [fl != null and int(fl) < 30, "first relationship line sol %s (first non-grief %s)" % [str(sum.first_rel_line_sol), str(fl)]]
	var lw: float = float(sum.lonely_window_mean)
	t["R3_lonely_window_mean_le_max"] = [lw <= float(bal.lonely_share_max), "mean of last %d readings %.3f (max %.2f)%s" % [
			int(sum.lonely_window_n), lw, float(bal.lonely_share_max), "; D3 DEAD" if bool(sum.d3_lonely_dead) else ""]]
	var r300: Dictionary = sum.readings.get(str(int(sum.sols)), {})
	var fmn: float = float(r300.get("friends_mean", -1.0))
	t["R4_friends_mean_300_in_band"] = [fmn >= float(bal.friends_mean_min) and fmn <= float(bal.friends_mean_max), "friends_mean %.2f (band %.1f to %.1f)" % [
			fmn, float(bal.friends_mean_min), float(bal.friends_mean_max)]]
	var logged := 0
	for f in CAPPED:
		logged += int(sum.lines[f])
	var den := logged + int(sum.lines_dropped)
	var dr := float(sum.lines_dropped) / maxf(1.0, float(den))
	t["R5_dropped_lt_5pct"] = [dr < 0.05, "dropped %d of %d capped-kind events (logged %d + dropped %d) = %.2f%%" % [
			int(sum.lines_dropped), den, logged, int(sum.lines_dropped), 100.0 * dr]]
	t["R6_lines_ge_1_per_5_sols_20_300"] = [float(sum.mean_lines_per_5sols_20_300) >= 1.0, "%.2f lines per 5 sols (%d lines in sols 20 to 299); zero-line 5-sol blocks %d of %d" % [
			float(sum.mean_lines_per_5sols_20_300), int(sum.lines_20_300), int(sum.zero_5sol_blocks), int(sum.blocks_5sol)]]
	var pe: Dictionary = sum.personality
	var wm := float(pe.warm_mean)
	var cm := float(pe.cold_mean)
	t["R7_warmest_third_more_friends"] = [wm > cm, "warm %.2f vs cold %.2f" % [wm, cm]]
	var ratio_ok := true
	var ratio_txt := ""
	if cm == 0.0 and wm == 0.0:
		ratio_txt = "n/a (both means 0)"
		ratio_ok = false
	elif cm == 0.0:
		ratio_txt = "inf"
	else:
		ratio_txt = "%.2f" % (wm / cm)
		ratio_ok = wm / cm >= float(bal.selectivity_ratio_min)
	t["R10_selectivity_ratio_stop"] = [ratio_ok, "ratio %s = warm %.2f / cold %.2f (min %.1f)" % [ratio_txt, wm, cm, float(bal.selectivity_ratio_min)]]
	t["R11_coldest_third_mean_stop"] = [cm <= float(bal.cold_third_friends_stop), "coldest-third mean %.2f (max %.1f)" % [cm, float(bal.cold_third_friends_stop)]]
	var nl: Variant = sum.first_newcomer_line_sol
	var early := fb != null and int(fb) < 15
	# revision 7: the lower bound is judged, the upper bound (first_line_max_sol) is reported only.
	var nl_ok: bool = nl != null and int(nl) >= int(bal.first_line_min_sol)
	var nl_over: bool = nl != null and int(nl) > int(bal.first_line_max_sol)
	var nl_txt := "first newcomer line sol %s (judged: at or after %d; reported: by %d%s), first birth %s" % [str(nl), int(bal.first_line_min_sol), int(bal.first_line_max_sol), ", OVER" if nl_over else ", within", str(fb)]
	if not nl_ok and nl != null and int(nl) < int(bal.first_line_min_sol) and early:
		nl_txt += "; lower-bound miss on an early birth (before sol 15): read as an early birth, no key change"
	t["R12_first_newcomer_line_lower_bound"] = [nl_ok, nl_txt]
	var tail := float(sum.ff_tail_per5)
	var base := float(sum.ff_base_per5)
	t["R13_found_friend_late_tail_ceiling"] = [tail <= float(bal.found_friend_tail_per5_max), "tail (150..299) %.2f per 5 sols (%d lines; max %.1f); reported: mean (20..299) %.2f (%d lines), ratio %s, births in 150..299 %d, found_friend lines per birth %s" % [
			tail, int(sum.ff_tail_n), float(bal.found_friend_tail_per5_max), base, int(sum.ff_base_n), "inf" if base == 0.0 else "%.2f" % (tail / base),
			int(sum.births_tail), "-" if float(sum.ff_per_birth_tail) < 0.0 else "%.2f" % float(sum.ff_per_birth_tail)]]
	t["R14_no_dropped_friend_events"] = [int(sum.lines_dropped) == 0, "lines_dropped %d (total; lines_dropped_by_type not built)" % int(sum.lines_dropped)]
	return t


# ------------------------------------------------------------------ report text

func _report(sum: Dictionary) -> Array[String]:
	var o: Array[String] = []
	o.append("# relationships probe: seed=%d sols=%d pull=%s data_hash=%s digest=%s wall %.1f s" % [
			int(sum.seed), int(sum.sols), str(sum.pull), str(sum.data_hash), str(sum.digest), float(sum.wall_s)])
	o.append("pop_end %d births %d first_birth_sol %s deaths %s age_history %s" % [int(sum.pop_end), int(sum.births), str(sum.first_birth_sol), str(sum.deaths), str(sum.age_history)])
	o.append("item 1: first_friendship_sol %s, first_mars_born_friendship_sol %s, first relationship line %s (non-grief %s), first line by kind %s" % [
			str(sum.first_friendship_sol), str(sum.first_mars_born_friendship_sol), str(sum.first_rel_line_sol), str(sum.first_capped_line_sol), str(sum.first_line_by_kind)])
	o.append("  lines %s; capped %d dropped %d stale %d; formed %d renewed %d close %d drifted %d crew_drifted %d" % [
			str(sum.lines), int(sum.lines_capped), int(sum.lines_dropped), int(sum.lines_stale), int(sum.friendships_formed),
			int(sum.friendships_renewed), int(sum.close_formed), int(sum.drifted), int(sum.crew_drifted)])
	o.append("  lines per sol max %d mean(20..300) %.3f; mean per 5 sols (20..300) %.2f; zero 5-sol blocks %d of %d" % [
			int(sum.max_lines_per_sol), float(sum.mean_lines_per_sol), float(sum.mean_lines_per_5sols_20_300), int(sum.zero_5sol_blocks), int(sum.blocks_5sol)])
	o.append("  R12 first newcomer line sol %s; R13 found_friend per 5 sols: tail(150..299) %.2f, mean(20..299) %.2f; births 150..299 %d, found_friend per birth %.2f; dropped total %d (by type not built)" % [
			str(sum.first_newcomer_line_sol), float(sum.ff_tail_per5), float(sum.ff_base_per5), int(sum.births_tail), float(sum.ff_per_birth_tail), int(sum.lines_dropped)])
	o.append("item 2: readings %s" % str(sum.readings))
	o.append("item 3: personality %s" % str(sum.personality))
	o.append("  selectivity ratio %s, coldest-third mean %.2f" % [_ratio_txt(sum.personality), float(sum.personality.cold_mean)])
	o.append("item 11: D1 %s; D2 friends_pop_share at 300 %.3f (friends_mean %.2f, pop %s); D3 lonely window mean %.3f over %d readings%s" % [
			str(sum.d1), float(sum.readings.get(str(int(sum.sols)), {}).get("friends_pop_share", 0.0)), float(sum.readings.get(str(int(sum.sols)), {}).get("friends_mean", 0.0)),
			str(sum.readings.get(str(int(sum.sols)), {}).get("pop", "-")), float(sum.lonely_window_mean), int(sum.lonely_window_n), " DEAD" if bool(sum.d3_lonely_dead) else ""])
	if float(sum.d1.share) > float(SimData.relationships().balance.met_friend_share_flag):
		o.append("  D1 flag HIGH: friend share of acquaintances %.3f above %.2f" % [float(sum.d1.share), float(SimData.relationships().balance.met_friend_share_flag)])
	o.append("  bond age (all) %s; (grown only) %s" % [str(sum.bond_age), str(sum.bond_age_grown)])
	o.append("item 4: work check %s" % str(sum.work_check))
	o.append("item 5: together h/sol %s" % str(sum.together))
	o.append("item 7: newborns after sol 100 %s" % str(sum.newborn_after_100))
	o.append("item 8: kinless %s" % str(sum.kinless))
	o.append("item 10: log %s" % str(sum.log))
	for n in sum.targets:
		o.append("  target %-52s %s  %s" % [n, "PASS" if sum.targets[n][0] else "FAIL", sum.targets[n][1]])
	return o


static func _ratio_txt(pe: Dictionary) -> String:
	var wm := float(pe.warm_mean)
	var cm := float(pe.cold_mean)
	if cm == 0.0:
		return "n/a" if wm == 0.0 else "inf"
	return "%.2f" % (wm / cm)


# ------------------------------------------------------------------ replay (balance table hash)

func _hash_run(seed_in: int, sols: int, pull: String, params: Dictionary) -> void:
	var lib: GDScript = load(BL)
	var all := pull_params(pull)
	all.merge(params, true)
	var res: Dictionary = lib.run(seed_in, sols, all, 30)
	var w: SimWorld = res.world
	print("# hash run: seed=%d sols=%d pull=%s overrides=%s" % [seed_in, sols, pull, str(all)])
	print("table_sha256 %s" % str(res.table_hash).substr(0, 16))
	print("digest %s pop_end %d" % [_digest(w), w.colony.pop()])
	for v: Dictionary in res.verdicts:
		if v.n == 10:
			print("T10 %s %s" % [v.verdict, v.detail])


# ------------------------------------------------------------------ item 6: sample vs per-step

func _sample60(seed_in: int, sols: int, params: Dictionary) -> void:
	var saved := _apply("shipped", params)
	var w := SimWorld.new(seed_in)
	var rel: Relationships = w.relationships
	var tick_h := float(SimData.relationships().tick_h)
	var step_h: float = w.fixed_step
	var ps := {}
	var ts := {}
	var ps_sol := {}
	var ts_sol := {}
	var last_ticks := 0
	var pair_sol_diffs: Array = []
	while w.sol() < sols:
		w.step()
		if w._sol_started:
			_flush_sol(ps_sol, ts_sol, step_h, tick_h, pair_sol_diffs)
			ps_sol = {}
			ts_sol = {}
		var g := _groups(w)
		_count_groups(g, ps)
		_count_groups(g, ps_sol)
		if rel.ticks != last_ticks:
			last_ticks = rel.ticks
			_count_groups(g, ts)
			_count_groups(g, ts_sol)
	var diffs: Array = []
	var diffs10: Array = []
	var signed: Array = []
	var total_p := 0.0
	var total_t := 0.0
	for k in ps:
		var p := float(ps[k]) * step_h
		var s := float(ts.get(k, 0)) * tick_h
		var d := absf(s - p) / p
		diffs.append(d)
		signed.append((s - p) / p)
		total_p += p
		total_t += s
		if p >= 10.0:
			diffs10.append(d)
	print("# sample vs per-step: seed=%d sols 1..%d, tick_h %.2f, step_h %.3f" % [seed_in, w.sol(), tick_h, step_h])
	print("pairs with any per-step togetherness: %d" % ps.size())
	print("per pair over the whole window: relative difference |tick hours - step hours| / step hours: median %.4f p90 %.4f max %.4f; mean signed %.4f" % [
			_median(diffs), _pctile(diffs, 0.9), _max(diffs), _mean(signed)])
	print("  pairs with >= 10 step-hours: %d, median %.4f p90 %.4f" % [diffs10.size(), _median(diffs10), _pctile(diffs10, 0.9)])
	print("  total together hours: per-step %.1f, tick %.1f, ratio %.4f" % [total_p, total_t, total_t / maxf(1e-9, total_p)])
	print("per pair per sol (pair-sols with step-hours > 0): n %d, median %.4f p90 %.4f" % [pair_sol_diffs.size(), _median(pair_sol_diffs), _pctile(pair_sol_diffs, 0.9)])
	for e in saved:
		e[0][e[1]] = e[2]


func _flush_sol(ps_sol: Dictionary, ts_sol: Dictionary, step_h: float, tick_h: float, into: Array) -> void:
	for k in ps_sol:
		var p := float(ps_sol[k]) * step_h
		var s := float(ts_sol.get(k, 0)) * tick_h
		into.append(absf(s - p) / p)


# ------------------------------------------------------------------ items 9 and 10: cost and log pollution

func _cost(seed_in: int, sols: int, pull: String, params: Dictionary) -> void:
	var saved := _apply(pull, params)
	var a := SimWorld.new(seed_in)
	var b := SimWorld.new(seed_in)
	b.relationships_enabled = false
	var bands := {"pop<=40": [0, 40], "pop41-80": [41, 80], "pop81-120": [81, 120], "pop>120": [121, 100000]}
	var tick_us := {}
	var step_a := {}
	var step_b := {}
	var tick_pairs := {}
	var last_ticks := 0
	var max_pop := 0
	var diverged := 0
	for bn in bands:
		tick_us[bn] = []
		step_a[bn] = []
		step_b[bn] = []
		tick_pairs[bn] = []
	while a.sol() < sols:
		var u0 := Time.get_ticks_usec()
		a.step()
		var u1 := Time.get_ticks_usec()
		b.step()
		var u2 := Time.get_ticks_usec()
		var pop := a.colony.pop()
		max_pop = maxi(max_pop, pop)
		if a.colony.pop() != b.colony.pop():
			diverged += 1
		for bn in bands:
			if pop >= bands[bn][0] and pop <= bands[bn][1]:
				step_a[bn].append(u1 - u0)
				step_b[bn].append(u2 - u1)
				if a.relationships.ticks != last_ticks:
					tick_us[bn].append(a.relationships.last_tick_ms * 1000.0)
					tick_pairs[bn].append(a.relationships.pairs.size())
		last_ticks = a.relationships.ticks
	print("# cost: seed=%d sols=%d pull=%s max pop %d; A = module on, B = module off (lockstep, A timed first each step); pop diverged on %d steps" % [seed_in, sols, pull, max_pop, diverged])
	print("tick cost (Relationships.last_tick_ms x 1000, us) by population band:")
	for bn in bands:
		var tu: Array = tick_us[bn]
		if tu.is_empty():
			print("  %-10s no ticks" % bn)
			continue
		print("  %-10s ticks %5d  median %8.0f us  p95 %8.0f  max %8.0f  stored pairs median %.0f max %.0f" % [bn, tu.size(), _median(tu), _pctile(tu, 0.95), _max(tu), _median(tick_pairs[bn]), _max(tick_pairs[bn])])
	print("step cost (us per World.step), A on vs B off:")
	for bn in bands:
		var sa: Array = step_a[bn]
		if sa.is_empty():
			continue
		print("  %-10s steps %6d  on: median %7.0f mean %8.1f   off: median %7.0f mean %8.1f   mean difference %7.1f us per step (%.1f%%)" % [
				bn, sa.size(), _median(sa), _mean(sa), _median(step_b[bn]), _mean(step_b[bn]), _mean(sa) - _mean(step_b[bn]),
				100.0 * (_mean(sa) - _mean(step_b[bn])) / maxf(1.0, _mean(step_b[bn]))])
	print("log at sol %d: module on size %d oldest entry sol %d; module off size %d oldest entry sol %d (cap %d)" % [
			sols, a.log.size(), int(a.log[0].sol), b.log.size(), int(b.log[0].sol), int(SimData.colony().log_cap)])
	for e in saved:
		e[0][e[1]] = e[2]


# ------------------------------------------------------------------ markdown tables

func _load(dir: String, seed_in: int, pull: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string("%s/seed_%d_%s.json" % [dir, seed_in, pull])
	var p: Variant = JSON.parse_string(txt)
	return p if p is Dictionary else {}


static func _n(v: Variant) -> String:
	if v == null:
		return "-"
	if v is int or (v is float and float(v) == floorf(float(v))):
		return str(int(v))
	return "%.2f" % float(v)


static func _hist(h: Array) -> String:
	if h.size() <= 1:
		return "none"
	var parts: Array[String] = []
	for x in h:
		if int(x.sol) == 0:
			continue
		parts.append("%s@%d%s" % ["L" if x.age == "landing" else "S", int(x.sol), "" if str(x.cause) == "" else "(" + str(x.cause) + ")"])
	return " ".join(PackedStringArray(parts))


func _tables(dir: String) -> void:
	for pull in PULLS:
		var d := {}
		for s in SEEDS:
			d[s] = _load(dir, s, pull)
		print("\n### Run: %s\n" % pull)
		print("**Item 1: firsts and lines**\n")
		print("| seed | first birth | first_friendship_sol | first_mars_born_friendship_sol | first rel line (non-grief) | friends | found_friend | close | close_crew | drifted | grief | capped | dropped | stale | formed | max lines/sol | mean lines/sol 20-299 | lines per 5 sols 20-299 | zero 5-sol blocks |")
		print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
		for s in SEEDS:
			var r: Dictionary = d[s]
			if r.is_empty():
				continue
			var l: Dictionary = r.lines
			print("| %d | %s | %s | %s | %s (%s) | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %.3f | %.2f | %s of %s |" % [
					s, _n(r.first_birth_sol), _n(r.first_friendship_sol), _n(r.first_mars_born_friendship_sol), _n(r.first_rel_line_sol), _n(r.first_capped_line_sol),
					_n(l.friends), _n(l.found_friend), _n(l.close), _n(l.close_crew), _n(l.drifted), _n(l.grief), _n(r.lines_capped), _n(r.lines_dropped),
					_n(r.lines_stale), _n(r.friendships_formed), _n(r.max_lines_per_sol), float(r.mean_lines_per_sol), float(r.mean_lines_per_5sols_20_300),
					_n(r.zero_5sol_blocks), _n(r.blocks_5sol)])
		print("\n**Revision 6: newcomer line, late tail, dropped, D1 to D3**\n")
		print("| seed | first newcomer line sol | found_friend per 5 sols 150-299 / 20-299 | dropped (total) | selectivity ratio (warm / cold) | coldest-third mean | D1 friend pairs / ever-together pairs = share | D2 friends share of colony at 300 (friends_mean, pop) | D3 lonely window mean (DEAD?) |")
		print("|---|---|---|---|---|---|---|---|---|")
		for s in SEEDS:
			var r: Dictionary = d[s]
			if r.is_empty():
				continue
			var pe: Dictionary = r.personality
			var d1: Dictionary = r.d1
			var q3: Dictionary = r.readings.get("300", {})
			print("| %d | %s | %.2f / %.2f | %s | %s (%.2f / %.2f) | %.2f | %s / %s = %.3f%s | %.3f (%.2f, %s) | %.3f%s |" % [s, _n(r.first_newcomer_line_sol), float(r.ff_tail_per5), float(r.ff_base_per5),
					_n(r.lines_dropped), _ratio_txt(pe), float(pe.warm_mean), float(pe.cold_mean), float(pe.cold_mean), _n(d1.friend_pairs), _n(d1.ever_together_pairs), float(d1.share),
					" HIGH" if float(d1.share) > float(SimData.relationships().balance.met_friend_share_flag) else "",
					float(q3.get("friends_pop_share", 0.0)), float(q3.get("friends_mean", 0.0)), _n(q3.get("pop", 0)), float(r.lonely_window_mean), " DEAD" if bool(r.d3_lonely_dead) else ""])
		print("\n**Item 2: trust readings (web / second / lonely / friends_mean; parts of size 3+ at the last sol)**\n")
		print("| seed | " + " | ".join(PackedStringArray(READ_SOLS.map(func(x: int) -> String: return "sol %d" % x))) + " | web parts >= 3 at 300 |")
		print("|---|" + "---|".repeat(READ_SOLS.size() + 1))
		for s in SEEDS:
			var r: Dictionary = d[s]
			if r.is_empty():
				continue
			var cells: Array[String] = []
			for x in READ_SOLS:
				var q: Dictionary = r.readings.get(str(x), {})
				cells.append("%.2f / %.2f / %.2f / %.2f" % [float(q.web), float(q.second), float(q.lonely), float(q.friends_mean)] if not q.is_empty() else "-")
			print("| %d | %s | %s |" % [s, " | ".join(PackedStringArray(cells)), _n(r.readings.get("300", {}).get("parts3", -1))])
		print("\n**Items 3 and 4: personality (mean friend count at sol 300; warmest third / coldest third)**\n")
		print("| seed | alive | all: warm / cold | top-half work share: warm / cold | bottom-half work share: warm / cold | work share mean top / bottom | bond age, restless top / bottom third (all friendships) | (grown only) |")
		print("|---|---|---|---|---|---|---|---|")
		for s in SEEDS:
			var r: Dictionary = d[s]
			if r.is_empty():
				continue
			var p: Dictionary = r.personality
			var wc: Dictionary = r.work_check
			var ba: Dictionary = r.bond_age
			var bg: Dictionary = r.bond_age_grown
			print("| %d | %s | %.2f / %.2f | %.2f / %.2f | %.2f / %.2f | %.3f / %.3f | %.1f / %.1f sols (n %s) | %.1f / %.1f sols (n %s) |" % [
					s, _n(r.n_alive), float(p.warm_mean), float(p.cold_mean), float(wc.top_half.warm_mean), float(wc.top_half.cold_mean),
					float(wc.bottom_half.warm_mean), float(wc.bottom_half.cold_mean), float(wc.top_share_mean), float(wc.bottom_share_mean),
					float(ba.get("restless_top_age", -1.0)), float(ba.get("restless_bottom_age", -1.0)), _n(ba.get("n", 0)),
					float(bg.get("restless_top_age", -1.0)), float(bg.get("restless_bottom_age", -1.0)), _n(bg.get("n", 0))])
		print("\n**Item 5: hours together per sol (median over pairs alive at the end; friend pairs vs non-friend pairs)**\n")
		print("| seed | friend pairs | friend median h/sol | non-friend co-present pairs | their median | all non-friend pairs | their median |")
		print("|---|---|---|---|---|---|---|")
		for s in SEEDS:
			var r: Dictionary = d[s]
			if r.is_empty():
				continue
			var t: Dictionary = r.together
			print("| %d | %s | %.2f | %s | %.2f | %s | %.2f |" % [s, _n(t.friend_pairs), float(t.friend_median), _n(t.nonfriend_pairs_co_present),
					float(t.nonfriend_median_co_present), _n(t.nonfriend_pairs_all), float(t.nonfriend_median_all)])
		print("\n**Item 8: kinless newborns**\n")
		print("| seed | births seen | kinless | kinless share | kinless median sols to first grown friend (resolved / unresolved) | kin newborns median (resolved / unresolved) |")
		print("|---|---|---|---|---|---|")
		for s in SEEDS:
			var r: Dictionary = d[s]
			if r.is_empty():
				continue
			var k: Dictionary = r.kinless
			print("| %d | %s | %s | %.2f | %.1f (%s / %s) | %.1f (%s / %s) |" % [s, _n(k.births), _n(k.kinless), float(k.kinless_share),
					float(k.kinless_median_sols), _n(k.kinless_resolved), _n(k.kinless_unresolved), float(k.kin_median_sols), _n(k.kin_resolved), _n(k.kin_unresolved)])
		print("\n**Item 10: log share**\n")
		print("| seed | entries logged | relationship entries | share | oldest entry in log at end (sol) | log size |")
		print("|---|---|---|---|---|---|")
		for s in SEEDS:
			var r: Dictionary = d[s]
			if r.is_empty():
				continue
			var lg: Dictionary = r.log
			print("| %d | %s | %s | %.1f%% | %s | %s |" % [s, _n(lg.total_entries), _n(lg.rel_entries), 100.0 * float(lg.rel_share), _n(lg.oldest_sol_end), _n(lg.log_size_end)])
		print("\n**Ages, population, deaths, newborn cohort**\n")
		print("| seed | age history | pop at end | births | deaths (air/thirst/hunger/eva/other) | newborns after sol 100 alive (n) | their mean friends | loneliest third mean friends | zero-friend newborns |")
		print("|---|---|---|---|---|---|---|---|---|")
		for s in SEEDS:
			var r: Dictionary = d[s]
			if r.is_empty():
				continue
			var dd: Dictionary = r.deaths
			var nb: Dictionary = r.newborn_after_100
			print("| %d | %s | %s | %s | %s/%s/%s/%s/%s | %s | %.2f | %.2f | %s |" % [s, _hist(r.age_history), _n(r.pop_end), _n(r.births),
					_n(dd.get("air", 0)), _n(dd.get("thirst", 0)), _n(dd.get("hunger", 0)), _n(dd.get("suffocated_outside", 0)), _n(dd.get("other", 0)),
					_n(nb.n), float(nb.mean_friends), float(nb.loneliest_third_mean), _n(nb.zero_friends)])
		print("\n**Targets**\n")
		print("| target | " + " | ".join(PackedStringArray(SEEDS.map(func(x: int) -> String: return "seed %d" % x))) + " |")
		print("|---|" + "---|".repeat(SEEDS.size()))
		var names: Array = []
		for s in SEEDS:
			if not d[s].is_empty():
				names = d[s].targets.keys()
				break
		for nm in names:
			var cells: Array[String] = []
			for s in SEEDS:
				var r: Dictionary = d[s]
				cells.append("-" if r.is_empty() else ("PASS" if r.targets[nm][0] else "FAIL") + " (" + str(r.targets[nm][1]) + ")")
			print("| %s | %s |" % [nm, " | ".join(PackedStringArray(cells))])
