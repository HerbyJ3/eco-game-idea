extends RefCounted
## Standard-tier observer and judge (docs/specs/lifecycle-calibration.md sections 3 and 3.5). READ-ONLY: it reads the
## world after every step and never writes to it or draws from its rng, so the run (and the balance table hash) is
## identical with and without it. Used by tests/balance_lib.gd run() only when a tier is requested; the 300-sol Smoke
## output does not touch this file. Loaded with load(), no class_name.
##
## Every threshold below is the spec's estimate (E) taken literally; where the spec text left a definition open the
## choice made here is stated in the output line of the target ("def:").

const COHORT_SOLS := 270
const SAMPLE_EVERY_STEPS := 20  # adult energy / sleep is sampled once per sim hour (fixed_step 0.05 h)
const STAGE_KEYS := ["baby", "toddler", "child", "teen", "adult"]
const YEAR_H := 8765.82
const LIFE_KINDS := ["pregnant", "born", "died"]

var lc: Lifecycle
var step_n := 0
var cur_sol := -1
var every_n := 20
var row_every := 30

# per-sol series (index = sol, sampled on the first step of the sol)
var pop_s: Array[int] = []
var adults_s: Array[int] = []
var stage_s := {"baby": [], "toddler": [], "child": [], "teen": [], "adult": []}
var cap_s: Array[int] = []
var pend_s: Array[int] = []
var habs_s: Array[int] = []
var ice_s: Array[float] = []
var food_s: Array[float] = []
var oxy_s: Array[float] = []
var finished_s: Array[int] = []   # cumulative builds_finished at the sol sample
var trips_s: Array[int] = []      # cumulative mining_trips at the sol sample
var exhausted_s: Array[int] = []  # cumulative turn_backs_exhausted
var zero_adults_s: Array[int] = []  # adults with friend_count 0
var zero_bonders_s: Array[int] = []  # toddler-and-up with friend_count 0
var voices_s: Array[int] = []
var fields_live_s: Array[int] = []   # ice fields with amount > 0
var fields_amt_s: Array[float] = []  # their remaining amount
var fields_reach_s: Array[int] = []  # reachable (amount > 0 and inside the trip limit)
var wall_us_s: Array[int] = []    # wall microseconds spent in the sol (whole loop incl. observer)
var steps_s: Array[int] = []
var adult_ids := {}
var being_cache := {}
var _sol_t0 := 0
var _sol_steps0 := 0

# adult energy / asleep, windowed like the table rows
var _wsum := 0.0
var _wn := 0
var _wasleep := 0
var adult_rows: Array[Dictionary] = []

# events
var conceptions: Array[Dictionary] = []   # {sol, parent, home}
var _conc_by_parent := {}
var births: Array[Dictionary] = []        # {sol, id, parent, home, conc_sol}
var deaths: Array[Dictionary] = []        # {sol, cause, founder, stage}
var _deaths_seen := 0
var life_line_sols: Array[int] = []       # sols that carried any pregnant/born/died/rel_* line
var line_kind_n := {}
var circles := {"count": 0, "few": 0, "sols": []}
var gate_hist := {}
var gate_hist_by_cohort := {}
var _prev_pend := 0

# power (T5 investigation)
var shorts_log: Array[Dictionary] = []
var offline_long: Array[Dictionary] = []   # stretches longer than one sol, filled at back_online and at the end
var _shorts_seen := 0
var max_offline_seen := 0.0
var power_samples: Array[Dictionary] = []

var l5_bad: Array[String] = []
var l5_age_checks := 0
var founders_n := 0
var sol_h := 24.6597
var steps_total := 0


func begin(w: SimWorld, row_every_in: int) -> void:
	lc = w.lifecycle
	sol_h = w.clock.sol_h
	every_n = maxi(1, int(round(1.0 / w.fixed_step)))
	row_every = row_every_in
	for b in w.beings:
		if b.earth_born:
			founders_n += 1
	_sol_t0 = Time.get_ticks_usec()
	_sol_steps0 = 0


## Called after every w.step().
func after_step(w: SimWorld) -> void:
	step_n += 1
	var s := w.sol()
	if s != cur_sol:
		_close_sol()
		cur_sol = s
		_on_sol(w, s)
	_scan_log(w)
	if w.stats.deaths_list.size() != _deaths_seen:
		_scan_deaths(w)
	if int(w.stats.shorts) != _shorts_seen:
		_scan_shorts(w)
	if w.colony.birth_timer_h == 0.0:
		_gate_check(w)
	if step_n % every_n == 0:
		_adult_sample(w)


func _close_sol() -> void:
	if cur_sol < 0:
		return
	var now := Time.get_ticks_usec()
	wall_us_s.append(now - _sol_t0)
	steps_s.append(step_n - _sol_steps0)
	_sol_t0 = now
	_sol_steps0 = step_n


func _on_sol(w: SimWorld, s: int) -> void:
	var c: Dictionary = lc.counts(w.beings, w.t)
	var pop := w.beings.size()
	var total := 0
	for k in STAGE_KEYS:
		stage_s[k].append(int(c[k]))
		total += int(c[k])
	pop_s.append(pop)
	adults_s.append(int(c.adult))
	if total != pop:
		l5_bad.append("sol %d: stage counts sum %d != pop %d" % [s, total, pop])
	cap_s.append(w.colony.birth_capacity())
	pend_s.append(lc.pregnancies.size())
	habs_s.append(w.buildings.count_online("habitat"))
	ice_s.append(w.colony.ice)
	food_s.append(w.colony.food)
	oxy_s.append(w.colony.oxygen)
	finished_s.append(int(w.stats.builds_finished))
	trips_s.append(int(w.stats.mining_trips))
	exhausted_s.append(int(w.stats.turn_backs_exhausted))
	voices_s.append(int(w.stats.council.voices))
	var fl := 0
	var fa := 0.0
	for f in w.resources.ice_fields:
		if f.amount > 0.0:
			fl += 1
			fa += f.amount
	fields_live_s.append(fl)
	fields_amt_s.append(fa)
	fields_reach_s.append(w.resources.reachable_ice_count())
	adult_ids.clear()
	being_cache.clear()
	var za := 0
	var zb := 0
	var fc: Dictionary = w.relationships.friend_count
	for b in w.beings:
		being_cache[b.id] = b
		var st := lc.stage(b, w.t)
		if st == "adult":
			adult_ids[b.id] = true
			if int(fc.get(b.id, 0)) == 0:
				za += 1
		if st != "baby" and int(fc.get(b.id, 0)) == 0:
			zb += 1
		if s % 10 == 0:
			_check_age(b, st, s, w.t)
	zero_adults_s.append(za)
	zero_bonders_s.append(zb)
	if s % row_every == 0 and s > 0:
		_close_row(s)
	if s % 10 == 0:
		_power_sample(w, s)


## L5: no being older than its stage allows (2-day tolerance around the calendar birthday, years of 8765.82 h).
func _check_age(b: Being, st: String, s: int, t: float) -> void:
	l5_age_checks += 1
	var age_y := (t - b.born_t) / YEAR_H
	var tol := 49.0 / YEAR_H
	var cfg: Dictionary = lc.cfg
	var lo := {"baby": 0.0, "toddler": float(cfg.toddler_age_years), "child": float(cfg.child_age_years),
			"teen": float(cfg.teen_age_years), "adult": float(cfg.adult_age_years)}
	var hi := {"baby": float(cfg.toddler_age_years), "toddler": float(cfg.child_age_years),
			"child": float(cfg.teen_age_years), "teen": float(cfg.adult_age_years), "adult": 1e9}
	if age_y < float(lo[st]) - tol or age_y >= float(hi[st]) + tol:
		l5_bad.append("sol %d: being %d age %.3f y labelled %s" % [s, b.id, age_y, st])


func _adult_sample(w: SimWorld) -> void:
	for b in w.beings:
		if adult_ids.has(b.id):
			_wn += 1
			_wsum += b.energy
			if b.state == "sleep":
				_wasleep += 1


func _close_row(s: int) -> void:
	adult_rows.append({"sol": s, "avg_e": _wsum / maxf(1.0, float(_wn)), "asleep": 100.0 * float(_wasleep) / maxf(1.0, float(_wn)), "n": _wn})
	_wsum = 0.0
	_wn = 0
	_wasleep = 0


func _scan_log(w: SimWorld) -> void:
	var lg: Array = w.log
	var i := lg.size() - 1
	while i >= 0:
		var e: Dictionary = lg[i]
		if float(e.t) != w.t:
			break
		var kind := str(e.kind)
		line_kind_n[kind] = int(line_kind_n.get(kind, 0)) + 1
		var s := int(e.sol)
		if kind in LIFE_KINDS or kind.begins_with("rel_"):
			if life_line_sols.is_empty() or life_line_sols.back() != s:
				life_line_sols.append(s)
		if kind == "pregnant":
			var rec := {"sol": s, "parent": int(e.being_id), "home": int(e.building_id)}
			conceptions.append(rec)
			_conc_by_parent[int(e.being_id)] = s
		elif kind == "born":
			var nb: Being = w.beings.back()
			var cs: int = int(_conc_by_parent.get(nb.parent_id, -1))
			births.append({"sol": s, "id": nb.id, "parent": nb.parent_id, "home": nb.birth_building_id, "conc_sol": cs})
		elif kind == "council_circles":
			circles.count += 1
			circles.sols.append(s)
			if str(e.text).contains("too few grown hands"):
				circles.few += 1
		i -= 1


func _scan_deaths(w: SimWorld) -> void:
	var dl: Array = w.stats.deaths_list
	for k in range(_deaths_seen, dl.size()):
		var d: Dictionary = dl[k]
		var b: Being = being_cache.get(int(d.being_id), null)
		var founder := false
		var st := "unknown"
		if b != null:
			founder = b.earth_born
			st = lc.stage(b, float(d.t))
		deaths.append({"sol": int(d.sol), "cause": str(d.cause), "founder": founder, "stage": st, "name": str(d.name)})
	_deaths_seen = dl.size()


func _scan_shorts(w: SimWorld) -> void:
	_shorts_seen = int(w.stats.shorts)
	var bd := w.buildings
	var kinds: Array[String] = []
	var offl: Array[String] = []
	for b in bd.list:
		if b.finished() and b.offline:
			offl.append("%s#%d" % [b.kind, b.id])
	var reactors := bd.count_online("reactor")
	shorts_log.append({"sol": w.sol(), "supply": bd.supply(), "draw": bd.draw(), "demand": bd.demand(), "reactors_online": reactors,
			"offline_after": offl, "sites": _sites(w), "builders_adult": _builders(w)})


func _sites(w: SimWorld) -> int:
	var n := 0
	for b in w.buildings.list:
		if not b.finished():
			n += 1
	return n


func _builders(w: SimWorld) -> int:
	var n := 0
	for b in w.beings:
		if b.role == "builder" and adult_ids.has(b.id):
			n += 1
	return n


func _power_sample(w: SimWorld, s: int) -> void:
	var longest := 0.0
	var who := ""
	for b in w.buildings.list:
		if b.finished() and b.offline and b.offline_since != null:
			var h := w.t - float(b.offline_since)
			if h > longest:
				longest = h
				who = "%s#%d" % [b.kind, b.id]
	max_offline_seen = maxf(max_offline_seen, longest)
	if longest > sol_h or (not power_samples.is_empty() and power_samples.back().longest_h > 0.0 and longest > 0.0):
		var bd := w.buildings
		var lim := float(bd.cfg.reonline.load_fraction) * bd.supply()
		power_samples.append({"sol": s, "longest_h": longest, "who": who, "supply": bd.supply(), "draw": bd.draw(),
				"reonline_limit": lim, "reactors_online": bd.count_online("reactor"), "habitats": bd.count_online("habitat"),
				"sites": _sites(w), "adult_builders": _builders(w), "pop": w.beings.size(), "reg": w.colony.regolith})


## Q5: why each birth check did or did not conceive, per online habitat, observed after the step.
func _gate_check(w: SimWorld) -> void:
	var col := w.colony
	var bc: Dictionary = col.cfg.birth
	var cohort := "pre"
	if not births.is_empty():
		cohort = str((w.sol() - int(births[0].sol)) / COHORT_SOLS)
	for hb in w.buildings.list:
		if hb.kind != "habitat" or not hb.finished() or not hb.online():
			continue
		var reason := ""
		if lc.last_conception_t.has(hb.id) and is_equal_approx(float(lc.last_conception_t[hb.id]), w.t):
			reason = "conceived"
		else:
			var here: Array = []
			for b in w.beings:
				if b.building_id == hb.id and b.is_inside() and lc.can_conceive(b, w.t):
					here.append(b)
			var need := int(bc.min_beings_small_colony) if col.pop() < int(bc.small_colony_below) else int(bc.min_beings)
			if here.is_empty():
				reason = "no_eligible_adult_inside"
			elif here.size() < need:
				reason = "too_few_beings_inside"
			elif not (col.ice > float(bc.gate_ice_above) and col.food > float(bc.gate_food_above) \
					and col.oxygen > float(bc.gate_oxygen_above) and col.o2_net() > float(bc.gate_o2_net_above) \
					and col.food_net() > float(bc.gate_food_net_above)):
				reason = "resources"
			elif col.pop() + lc.pregnancies.size() >= col.birth_capacity():
				reason = "capacity"
			elif not col.birth_cooldown_over(hb.id, w.t):
				reason = "birth_cooldown"
			elif not lc.conception_cooldown_over(hb.id, w.t, col.birth_cooldown_h()):
				reason = "conception_cooldown"
			else:
				reason = "chance_roll_failed"
		gate_hist[reason] = int(gate_hist.get(reason, 0)) + 1
		if not gate_hist_by_cohort.has(cohort):
			gate_hist_by_cohort[cohort] = {}
		var g: Dictionary = gate_hist_by_cohort[cohort]
		g[reason] = int(g.get(reason, 0)) + 1


# ------------------------------------------------------------------------------------------ judgement

static func _v(id: String, verdict: String, value: String, limit: String, note: String = "") -> Dictionary:
	return {"id": id, "verdict": verdict, "value": value, "limit": limit, "note": note}


static func _fmt_arr(a: Array) -> String:
	var parts: Array[String] = []
	for x in a:
		parts.append(str(x))
	return ",".join(PackedStringArray(parts))


func _first_birth() -> int:
	return -1 if births.is_empty() else int(births[0].sol)


## Complete 270-sol cohort windows anchored on the first birth: [{k, from, to, births}], and the incomplete tail.
func cohort_windows(sols: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var fb := _first_birth()
	if fb < 0:
		return out
	var k := 0
	while fb + k * COHORT_SOLS < sols:
		var from := fb + k * COHORT_SOLS
		var to := from + COHORT_SOLS
		var n := 0
		for b in births:
			if int(b.sol) >= from and int(b.sol) < to:
				n += 1
		out.append({"k": k + 1, "from": from, "to": to, "births": n, "complete": to <= sols})
		k += 1
	return out


func _mean_range(a: Array, from: int, to: int) -> float:
	var s := 0.0
	var n := 0
	for i in range(maxi(0, from), mini(a.size(), to)):
		s += float(a[i])
		n += 1
	return s / float(n) if n > 0 else 0.0


## Returns {verdicts: Array[Dictionary], lines: Array[String], data: Dictionary}.
func finish(w: SimWorld, sols: int, legacy: Array[Dictionary]) -> Dictionary:
	_close_sol()
	var V: Array[Dictionary] = []
	var L: Array[String] = []
	var st: Dictionary = w.stats
	var n := pop_s.size()
	var fb := _first_birth()
	var wins := cohort_windows(sols)
	var pop_end := w.colony.pop()

	# ---- L1 adult floor and T1 restated
	var amin := 1 << 30
	var amin_sol := -1
	for i in n:
		if adults_s[i] < amin:
			amin = adults_s[i]
			amin_sol = i
	V.append(_v("L1", "PASS" if amin >= 4 else "FAIL", "min adults %d (first at sol %d)" % [amin, amin_sol], ">= 4 every sol"))
	V.append(_v("T1r", "PASS" if amin >= 4 and pop_end >= 7 else "FAIL", "min adults %d, final pop %d" % [amin, pop_end], "min adults >= 4 and final pop >= 7"))

	# ---- T2 restated
	var by_cause := {}
	var by_stage_cause := {}
	var founder_deaths := 0
	for d in deaths:
		by_cause[d.cause] = int(by_cause.get(d.cause, 0)) + 1
		var key := "%s/%s" % [d.stage, d.cause]
		by_stage_cause[key] = int(by_stage_cause.get(key, 0)) + 1
		if d.founder:
			founder_deaths += 1
	var ok2 := int(st.deaths_unexplained) == 0 and founder_deaths <= 2
	V.append(_v("T2r", "PASS" if ok2 else "FAIL", "unexplained %d, founder deaths %d of %d, total deaths %d" % [
			int(st.deaths_unexplained), founder_deaths, founders_n, deaths.size()], "unexplained 0, founder deaths <= 2",
			"by cause %s; by stage/cause %s" % [JSON.stringify(by_cause), JSON.stringify(by_stage_cause)]))

	# ---- T3 restated
	var ok3 := int(st.births_at_capacity) == 0 and int(st.cooldown_violations) == 0
	V.append(_v("T3a", "PASS" if ok3 else "FAIL", "at_capacity %d, cooldown_violations %d" % [int(st.births_at_capacity), int(st.cooldown_violations)], "both 0"))
	if sols >= 1:
		var okfb := fb >= 265 and fb <= 320
		V.append(_v("T3b", "PASS" if okfb else "FAIL", "first birth sol %s" % (str(fb) if fb >= 0 else "none"), "265..320"))
	if sols >= 300:
		V.append(_v("T3c", "PASS" if pop_s[300] >= 9 else "FAIL", "pop@300 %d" % pop_s[300], ">= 9"))
	V.append(_v("T3d", "PASS" if pop_end >= 25 and pop_end <= 80 else "FAIL", "pop@%d %d" % [sols, pop_end], "25..80 at the end"))
	var cohort_txt: Array[String] = []
	var ok3e := true
	var judged3e := 0
	for c in wins:
		cohort_txt.append("c%d[%d,%d)=%d%s" % [c.k, c.from, c.to, c.births, "" if c.complete else " incomplete"])
		if c.complete:
			judged3e += 1
			if int(c.births) < 3:
				ok3e = false
	V.append(_v("T3e", "NYJ" if judged3e == 0 else ("PASS" if ok3e else "FAIL"), "births per complete window: " + " ".join(PackedStringArray(cohort_txt)),
			">= 3 per complete 270-sol window",
			"def: windows of 270 sols anchored on the first birth sol, window 1 included; incomplete tail not judged"))
	var sat := 0
	var lead_ok := 0
	var run := 0
	var run_max := 0
	var run_end := 0
	for i in n:
		var lead := cap_s[i] - (pop_s[i] + pend_s[i])
		if lead >= 0:
			lead_ok += 1
		if lead <= 0:
			sat += 1
			run += 1
			if run > run_max:
				run_max = run
				run_end = i
		else:
			run = 0
	V.append(_v("T3f", "REPORT", "saturated sols (capacity - (pop+pending) <= 0) %d of %d = %.1f%%, longest saturated run %d sols (ending sol %d)" % [
			sat, n, 100.0 * sat / maxf(1.0, float(n)), run_max, run_end], "reported"))

	# ---- T4 restated
	var o2min = st.min_oxygen
	var fmin = st.min_food
	var ok4 := (o2min == null or float(o2min) > 0.0) and (fmin == null or float(fmin) > 0.0)
	var min_ipb := 1e18
	var min_ipb_sol := -1
	for i in n:
		if pop_s[i] > 0 and ice_s[i] / float(pop_s[i]) < min_ipb:
			min_ipb = ice_s[i] / float(pop_s[i])
			min_ipb_sol = i
	var being_sols := 0
	for i in n:
		being_sols += pop_s[i]
	var thirst := int(st.deaths.thirst)
	var dry_txt: Array[String] = []
	for c in wins:
		var dry := 0
		for i in range(int(c.from), mini(int(c.to), n)):
			if ice_s[i] <= 0.0:
				dry += 1
		dry_txt.append("c%d=%d" % [c.k, dry])
	V.append(_v("T4r", "PASS" if ok4 else "FAIL", "min O2 %s, min food %s; min ice/being %.2f (sol %d); thirst deaths %d = %.3f per 1000 being-sols; ice-dry sols per cohort window %s" % [
			str(o2min), str(fmin), min_ipb, min_ipb_sol, thirst, 1000.0 * thirst / maxf(1.0, float(being_sols)), " ".join(PackedStringArray(dry_txt))],
			"O2 and food never 0 (ice reported)"))

	# ---- T5 (structure kept; judged by balance_lib T5 over the full horizon)
	for lv in legacy:
		if int(lv.n) == 5:
			V.append(_v("T5", str(lv.verdict), str(lv.detail), "kept as written"))

	# ---- T6 restated
	var ok6 := run_max <= 60
	var comp_txt: Array[String] = []
	var ok6b := true
	var bsols := 0
	var w_from := 0
	while w_from + COHORT_SOLS <= n:
		var d: int = (finished_s[w_from + COHORT_SOLS - 1] - (finished_s[w_from - 1] if w_from > 0 else 0))
		comp_txt.append(str(d))
		if d < 1:
			ok6b = false
		w_from += COHORT_SOLS
	var total_h := float(sols) * sol_h
	var limited := float(st.hours_waiting_regolith) + float(st.hours_site_no_crew)
	V.append(_v("T6a", "PASS" if ok6 else "FAIL", "longest saturated-housing run %d sols" % run_max, "<= 60 sols",
			"def: housing 'waits' = consecutive sols with capacity - (pop+pending) <= 0; the spec text does not say whether free adults must exist, so it is the plain saturation run"))
	V.append(_v("T6b", "PASS" if ok6b else "FAIL", "buildings finished per 270-sol window from sol 0: " + ",".join(PackedStringArray(comp_txt)), ">= 1 each"))
	V.append(_v("T6c", "REPORT", "crew-limited share %.2f%%" % (100.0 * limited / total_h), "reported"))

	# ---- T7 restated
	var adult_sols := 0
	for i in n:
		adult_sols += adults_s[i]
	var trips := int(st.mining_trips)
	var tpa := float(trips) / maxf(1.0, float(adult_sols))
	var exh := int(st.turn_backs_exhausted)
	var reach := 100.0 * float(st.reachable_ok_samples) / maxf(1.0, float(st.sol_samples))
	var ok7 := tpa >= 0.05 and tpa <= 0.30 and int(st.turn_backs_air) == 0 and reach >= 95.0
	V.append(_v("T7r", "PASS" if ok7 else "FAIL", "trips %d over %d adult-sols = %.4f per adult-sol; exhausted %d = %.4f per adult-sol; turn_backs_air %d; reachable>=2 %.1f%%" % [
			trips, adult_sols, tpa, exh, float(exh) / maxf(1.0, float(adult_sols)), int(st.turn_backs_air), reach], "0.05..0.30 trips per adult-sol; turn_backs_air 0; reachable >= 95%"))

	# ---- T8 restated (adults only, sampled once per sim hour)
	var emin := 1e9
	var emax := -1e9
	var amin2 := 1e9
	var amax2 := -1e9
	var ok8 := true
	for r in adult_rows:
		emin = minf(emin, r.avg_e)
		emax = maxf(emax, r.avg_e)
		amin2 = minf(amin2, r.asleep)
		amax2 = maxf(amax2, r.asleep)
		if r.avg_e < 40.0 or r.avg_e > 90.0 or r.asleep < 5.0 or r.asleep > 30.0:
			ok8 = false
	var legacy_maxsleep := float(st.max_sleep_h)
	if ok8 and legacy_maxsleep > 18.0:
		ok8 = false
	V.append(_v("T8r", "PASS" if ok8 else "FAIL", "adult row avg energy %.1f..%.1f, adult row asleep %.1f..%.1f%%, max sleep (all beings, run) %.1f h" % [emin, emax, amin2, amax2, legacy_maxsleep],
			"energy 40..90, asleep 5..30%, max sleep <= 18 h",
			"def: adults only, sampled once per sim hour (not every step), rows every %d sols as the table; max sleep is the run-wide all-beings figure (not split by stage)" % row_every))

	# ---- T10 restated
	var first = st.first_settlement_sol
	var cfg_a: Dictionary = SimData.ages()
	var hist_changes := Balance_projected_changes(st.age_history)
	var falls: Array[String] = []
	for i in range(1, st.age_history.size()):
		var e: Dictionary = st.age_history[i]
		if str(e.how) == "fell_back":
			falls.append("sol %d (%s)" % [int(e.sol), str(e.cause)])
	var ok10 := first != null and int(first) >= 265 and int(first) <= 700 and hist_changes <= 4
	V.append(_v("T10r", "PASS" if ok10 else "FAIL", "Settlement sol %s, projected age changes %d, fall-backs [%s]" % [str(first), hist_changes, ", ".join(PackedStringArray(falls))],
			"Settlement 265..700 (4 of 5 seeds), changes <= 4"))

	# ---- T11 restated
	var rs: Dictionary = st.relationships
	var last50_from := maxi(0, n - 50)
	var zmax := 0
	var zmean := 0.0
	for i in range(last50_from, n):
		zmax = maxi(zmax, zero_adults_s[i])
		zmean += float(zero_adults_s[i])
	zmean /= maxf(1.0, float(n - last50_from))
	var lby: Array = rs.lonely_by_sol
	var lmean := 0.0
	for i in range(maxi(0, lby.size() - 50), lby.size()):
		lmean += float(lby[i])
	lmean /= maxf(1.0, float(mini(50, lby.size())))
	var zbmean := 0.0
	var zbshare := 0.0
	for i in range(last50_from, n):
		zbmean += float(zero_bonders_s[i])
		var can := pop_s[i] - int(stage_s.baby[i])
		zbshare += float(zero_bonders_s[i]) / maxf(1.0, float(can))
	zbmean /= maxf(1.0, float(n - last50_from))
	zbshare /= maxf(1.0, float(n - last50_from))
	var fm := float(rs.friends_mean)
	var small := pop_end < 20
	var ok11a := (zmax <= 2) if small else (lmean <= 0.35)
	V.append(_v("T11r", "PASS" if ok11a else "FAIL",
			"final pop %d; adults with friend_count 0 over last 50 readings: max %d mean %.2f; module lonely share last 50 mean %.3f; toddler-and-up with 0 friends: mean %.2f, share of those who can bond %.3f" % [pop_end, zmax, zmean, lmean, zbmean, zbshare],
			"pop < 20: <= 2 such adults on the last 50 readings; pop >= 20: lonely share <= 0.35",
			"def: 'no more than 2 on the last 50 readings' read as the max over those readings; module share is over all beings incl. babies"))
	V.append(_v("T11b", "PASS" if fm >= 1.0 and fm <= 15.0 and rs.first_friendship_sol != null else "FAIL",
			"friends_mean %.2f, first_friendship_sol %s, lines_dropped %d" % [fm, str(rs.first_friendship_sol), int(rs.lines_dropped)], "friends_mean 1.0..15.0, first friendship not null"))

	# ---- T12 structural (+ voices invariant)
	var ok12 := true
	var council_entries: Array[String] = []
	for e in st.age_history:
		if str(e.age) == "council":
			var vs: int = voices_s[mini(int(e.sol), n - 1)]
			council_entries.append("sol %d voices %d" % [int(e.sol), vs])
			if vs < int(SimData.council().entry.voices_min):
				ok12 = false
	for lv in legacy:
		if int(lv.n) == 12 and str(lv.verdict) == "FAIL":
			ok12 = false
	var vmax := 0
	for x in voices_s:
		vmax = maxi(vmax, x)
	V.append(_v("T12r", "PASS" if ok12 else "FAIL", "council entries [%s]; max adult voices over run %d (voices_min %d)" % [", ".join(PackedStringArray(council_entries)), vmax, int(SimData.council().entry.voices_min)],
			"structure ok; no entry with voices < voices_min"))
	var circ_max := int(SimData.council().lines.circles_max)
	var circ_ok: bool
	var circ_val := "circles lines %d (circles_few %d), at sols %s" % [circles.count, circles.few, _fmt_arr(circles.sols)]
	if first == null:
		V.append(_v("Circ", "NYJ", circ_val, "no Settlement reached"))
	else:
		circ_ok = circles.few >= 1 and circles.count <= circ_max
		V.append(_v("Circ", "PASS" if circ_ok else "FAIL", circ_val, ">= 1 circles_few and <= %d circles per term" % circ_max,
				"def: circles_max read from data/council.json (lines.circles_max if present, else 2); 'per term' applied to the whole run (no Council term exists)"))

	# ---- L2 dependant ratio and trend
	var rmax := 0.0
	var rmax_sol := -1
	for i in n:
		var r := float(pop_s[i] - adults_s[i]) / maxf(1.0, float(adults_s[i]))
		if r > rmax:
			rmax = r
			rmax_sol = i
	var comp: Array[Dictionary] = []
	for c in wins:
		if c.complete:
			comp.append(c)
	var trend_txt := "fewer than 2 complete cohort windows"
	var trend_ok := true
	var trend_judged := false
	if comp.size() >= 2:
		var a: Dictionary = comp[comp.size() - 2]
		var b: Dictionary = comp[comp.size() - 1]
		var ia := _per_being(ice_s, a)
		var ib := _per_being(ice_s, b)
		var fa := _per_being(food_s, a)
		var fb2 := _per_being(food_s, b)
		trend_judged = true
		trend_ok = ib >= ia and fb2 >= fa
		trend_txt = "ice/being c%d %.2f -> c%d %.2f; food/being c%d %.2f -> c%d %.2f" % [a.k, ia, b.k, ib, a.k, fa, b.k, fb2]
	V.append(_v("L2", "PASS" if rmax <= 6.0 and (trend_ok or not trend_judged) else "FAIL",
			"max (pop-adults)/adults %.2f (sol %d); %s" % [rmax, rmax_sol, trend_txt], "ratio <= 6 every sol; ice and food per being not falling over the last 2 complete cohort windows",
			"def: 'not falling' = mean of the later window >= mean of the earlier, no tolerance"))

	# ---- L3 cohort regularity
	if wins.is_empty():
		V.append(_v("L3", "NYJ", "no births", "span <= 60, second >= 40% of first"))
	else:
		var cmin := 1 << 30
		var cmax := -1
		for b in births:
			if int(b.sol) < int(wins[0].to) and int(b.conc_sol) >= 0:
				cmin = mini(cmin, int(b.conc_sol))
				cmax = maxi(cmax, int(b.conc_sol))
		var span := cmax - cmin if cmax >= 0 else -1
		var first_n := int(wins[0].births)
		var second_n := int(wins[1].births) if wins.size() > 1 and wins[1].complete else -1
		var okspan := span >= 0 and span <= 60
		var ok2nd := second_n >= 0 and float(second_n) >= 0.4 * float(first_n)
		var verdict := "NYJ" if second_n < 0 else ("PASS" if okspan and ok2nd else "FAIL")
		V.append(_v("L3", verdict, "first-cohort conception span %d sols (sols %d..%d), births c1 %d, c2 %s" % [span, cmin, cmax, first_n, str(second_n) if second_n >= 0 else "n/a"],
				"span <= 60 sols; c2 births >= 40% of c1"))

	# ---- L4 housing lead
	V.append(_v("L4", "PASS" if float(lead_ok) >= 0.9 * float(n) else "FAIL", "capacity >= pop+pending on %d of %d sols = %.1f%%" % [lead_ok, n, 100.0 * lead_ok / maxf(1.0, float(n))], ">= 90% of sols"))

	# ---- L5 structural
	V.append(_v("L5", "PASS" if l5_bad.is_empty() else "FAIL", "stage counts summed to pop on %d sols, %d being-age checks (every 10th sol), %d violations%s" % [
			n, l5_age_checks, l5_bad.size(), (": " + l5_bad[0]) if not l5_bad.is_empty() else ""], "0 violations"))

	# ---- output lines
	L.append("")
	L.append("== STANDARD TIER (docs/specs/lifecycle-calibration.md): restated targets and L1-L5, seed-level; seed counts across seeds are applied in the report ==")
	for v in V:
		var line := "  %-4s %-6s %s  [limit: %s]" % [v.id, v.verdict, v.value, v.limit]
		if v.note != "":
			line += "  (" + v.note + ")"
		L.append(line)
	L.append("")
	L.append("cohort table (270-sol windows anchored on the first birth sol %d):" % fb)
	L.append("  window  from   to  births  complete")
	for c in wins:
		L.append("  c%-5d %5d %5d %6d  %s" % [c.k, c.from, c.to, c.births, "yes" if c.complete else "no"])
	var popat: Array[String] = []
	var mark := 300
	while mark < n:
		popat.append("sol %d: pop %d (adults %d, baby %d toddler %d child %d teen %d)" % [mark, pop_s[mark], adults_s[mark],
				stage_s.baby[mark], stage_s.toddler[mark], stage_s.child[mark], stage_s.teen[mark]])
		mark += 300
	L.append("population at each 300 sols:")
	for p in popat:
		L.append("  " + p)
	L.append("births (sol, conceived sol, home): " + "; ".join(PackedStringArray(births.map(func(b): return "%d(c%d,h%d)" % [b.sol, b.conc_sol, b.home]))))
	L.append("conception sols (%d): %s" % [conceptions.size(), _fmt_arr(conceptions.map(func(c): return c.sol))])
	L.append("settlement: first_settlement_sol %s; family_mars_born now %s" % [str(first), str(Ages.family_mars_born(w))])
	L.append("deaths: %s" % JSON.stringify(deaths))
	L.append("birth-check outcomes per habitat check (observed after the step): " + JSON.stringify(gate_hist))
	L.append("birth-check outcomes by cohort window (pre = before first birth): " + JSON.stringify(gate_hist_by_cohort))
	# silence guard
	var gap_max := 0
	var gap_at := 0
	var prev := 0
	for s2 in life_line_sols:
		if s2 - prev > gap_max:
			gap_max = s2 - prev
			gap_at = prev
		prev = s2
	if sols - prev > gap_max:
		gap_max = sols - prev
		gap_at = prev
	var alive_to := n
	for i in n:
		if pop_s[i] == 0:
			alive_to = i
			break
	var gap_alive := 0
	var gp := 0
	for s3 in life_line_sols:
		if s3 > alive_to:
			break
		gap_alive = maxi(gap_alive, s3 - gp)
		gp = s3
	gap_alive = maxi(gap_alive, alive_to - gp)
	L.append("silence guard (while the colony lives, to sol %d): longest gap %d sols" % [alive_to, gap_alive])
	L.append("silence guard: longest gap between sols carrying any pregnant/born/died/rel_* line: %d sols (from sol %d); sols with such lines %d of %d" % [gap_max, gap_at, life_line_sols.size(), sols])
	L.append("log lines by kind (scanned every step, not capped): " + JSON.stringify(line_kind_n))
	# power
	L.append("power: shorts %d, reonlines %d, max offline %.1f h (stats), sampled longest offline %.1f h" % [int(st.shorts), int(st.reonlines), float(st.max_offline_h), max_offline_seen])
	for sl in shorts_log:
		L.append("  short sol %d supply %.1f draw %.1f demand %.1f reactors online %d offline now %s sites %d adult builders %d" % [
				sl.sol, sl.supply, sl.draw, sl.demand, sl.reactors_online, JSON.stringify(sl.offline_after), sl.sites, sl.builders_adult])
	var shown := 0
	for ps in power_samples:
		if shown % 5 == 0:
			L.append("  offline sample sol %d: %s %.1f h, supply %.1f draw %.1f reonline limit %.1f, reactors %d habitats %d sites %d adult builders %d pop %d regolith %.0f" % [
					ps.sol, ps.who, ps.longest_h, ps.supply, ps.draw, ps.reonline_limit, ps.reactors_online, ps.habitats, ps.sites, ps.adult_builders, ps.pop, ps.reg])
		shown += 1
	# ice timeline (cause of thirst deaths): every 30 sols, plus the sols around each death
	var ice_tl: Array[String] = []
	var q := 0
	while q < n:
		ice_tl.append("%d:ice %.0f,pop %d,fields %d/%d reachable %d,amt %.0f" % [q, ice_s[q], pop_s[q], fields_live_s[q], int(w.stats.ice_dry) + 0, fields_reach_s[q], fields_amt_s[q]])
		q += 30
	L.append("ice timeline (sol:stock,pop,live fields/total dried so far at the end,reachable,remaining amount): " + " | ".join(PackedStringArray(ice_tl)))
	L.append("ice fields: dried %d, scouts found %d, ice_dry sols %d of %d" % [int(w.stats.ice_dry), int(w.stats.scouts_found), ice_s.filter(func(x): return x <= 0.0).size(), n])
	# friends by stage (Q8)
	var fc: Dictionary = w.relationships.friend_count
	var fs := {}
	for b in w.beings:
		var sg := lc.stage(b, w.t)
		if not fs.has(sg):
			fs[sg] = {"n": 0, "with_friend": 0, "friends_sum": 0}
		fs[sg].n += 1
		var f := int(fc.get(b.id, 0))
		fs[sg].friends_sum += f
		if f > 0:
			fs[sg].with_friend += 1
	L.append("friends by stage at the end (Q8): " + JSON.stringify(fs))
	# cost
	var band_txt := _cost_lines()
	var data := {"pop": pop_s, "adults": adults_s, "stage": stage_s, "cap": cap_s, "pending": pend_s, "habitats": habs_s,
			"ice": ice_s, "food": food_s, "oxygen": oxy_s, "builds_finished": finished_s, "trips": trips_s,
			"zero_friend_adults": zero_adults_s, "voices": voices_s, "fields_live": fields_live_s, "fields_amount": fields_amt_s, "fields_reachable": fields_reach_s, "births": births, "conceptions": conceptions, "deaths": deaths,
			"gate_hist": gate_hist, "gate_hist_by_cohort": gate_hist_by_cohort, "shorts": shorts_log, "power_samples": power_samples,
			"adult_rows": adult_rows, "life_line_sols": life_line_sols, "verdicts": V, "wall_us_per_sol": wall_us_s, "steps_per_sol": steps_s, "cost": band_txt.data}
	return {"verdicts": V, "lines": L, "wall_lines": band_txt.lines, "data": data}


func _per_being(a: Array, c: Dictionary) -> float:
	var s := 0.0
	var k := 0
	for i in range(int(c.from), mini(int(c.to), a.size())):
		s += float(a[i]) / maxf(1.0, float(pop_s[i]))
		k += 1
	return s / float(k) if k > 0 else 0.0


## Cost per step by population band: whole loop (sim step + observer), wall clock, so it is host and load dependent.
## Lines start with @wall so a determinism cmp can drop them.
func _cost_lines() -> Dictionary:
	var bands := {}
	for i in wall_us_s.size():
		var p := pop_s[i]
		var key := int(p / 10) * 10
		if not bands.has(key):
			bands[key] = {"us": 0, "steps": 0, "sols": 0}
		bands[key].us += wall_us_s[i]
		bands[key].steps += steps_s[i]
		bands[key].sols += 1
	var keys: Array = bands.keys()
	keys.sort()
	var lines: Array[String] = []
	var data := {}
	var worst := 0.0
	for k in keys:
		var b: Dictionary = bands[k]
		var per := float(b.us) / maxf(1.0, float(b.steps))
		worst = maxf(worst, per)
		lines.append("@wall cost pop %d..%d: %d sols, %d steps, %.1f us/step (mean over the band, wall clock incl. observer)" % [k, k + 9, b.sols, b.steps, per])
		data[str(k)] = per
	var maxsol_us := 0
	var maxsol_i := 0
	for i in wall_us_s.size():
		if wall_us_s[i] > maxsol_us:
			maxsol_us = wall_us_s[i]
			maxsol_i = i
	lines.append("@wall slowest sol %d: pop %d, %d us/step" % [maxsol_i, pop_s[maxsol_i], maxsol_us / maxi(1, steps_s[maxsol_i])])
	return {"lines": lines, "data": data}


static func Balance_projected_changes(history: Array) -> int:
	var lib: GDScript = load("res://tests/balance_lib.gd")
	return int(lib.projected_changes(history))
