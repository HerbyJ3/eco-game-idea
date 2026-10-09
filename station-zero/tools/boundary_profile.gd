extends SceneTree
## Boundary-step attribution (docs/perf/task-5-boundary-step.md). Timers live here, outside sim/.
##   godot --headless --path station-zero --script res://tools/boundary_profile.gd -- --seed 42 --sols 300 --council on|off [--rel on|off]
## Runs a copy of SimWorld.step() that wraps the heavy phases in Time.get_ticks_usec; the copy must stay in line with
## SimWorld.step() (checked: the end-of-run digest is printed and equals a plain-step run of the same mode, --check).
## Prints boundary-step median/p95/max (whole step and per phase) for pop > 120 and the top spikes with what ran there.

const PH := ["step_stocks_to_beings", "update_beings", "births", "build_decision_to_stats", "rel_on_step", "council_on_step",
		"ages_on_sol", "rel_on_sol", "council_on_sol"]


static func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(floor(p * float(s.size()))))])


static func _digest(w: SimWorld) -> String:
	var parts: Array[String] = ["%d %.9f %.9f %.9f" % [w.step_index, w.t, w.colony.oxygen, w.colony.food],
			str(w.stats.births), str(w.log.size()), str(w.colony.pop()), str(w.stats.age_history.size())]
	for b in w.beings:
		parts.append("%d %s %.9f" % [b.id, b.state, b.energy])
	return "\n".join(parts).sha256_text().substr(0, 16)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var seed_in := 42
	var sols := 300
	var con := true
	var ron := true
	var check := false
	var i := 0
	while i < a.size():
		match a[i]:
			"--seed":
				i += 1
				seed_in = int(a[i])
			"--sols":
				i += 1
				sols = int(a[i])
			"--council":
				i += 1
				con = a[i] == "on"
			"--rel":
				i += 1
				ron = a[i] == "on"
			"--check":
				check = true
		i += 1
	var w := SimWorld.new(seed_in)
	w.council_enabled = con
	w.relationships_enabled = ron
	var rows: Array = []
	var landing_idx: Array = []  # indices of the Council series written at a Landing boundary (masked in the gate digest)
	var all_steps := 0
	var all_us := 0
	while w.sol() < sols:
		var pop_before := w.colony.pop()
		var births_before := int(w.stats.births)
		var deaths_before := int(w.stats.deaths.get("total", 0)) if w.stats.deaths is Dictionary else 0
		var ticks_before := w.relationships.ticks
		var log_before := w.log.size()
		var age_before := str(w.ages.age)
		var ph := [0, 0, 0, 0, 0, 0, 0, 0, 0]
		var t_all := Time.get_ticks_usec()
		if check:
			w.step()
		else:
			_step(w, ph)
		var total := Time.get_ticks_usec() - t_all
		all_steps += 1
		all_us += total
		if w._sol_started and str(w.ages.age) == "landing":
			landing_idx.append(w.stats.council.trust_by_sol.size() - 1)
		if w._sol_started:
			rows.append({"sol": w.sol(), "pop": pop_before, "total": total, "ph": ph, "births": int(w.stats.births) - births_before,
					"rel_tick": w.relationships.ticks != ticks_before, "log": w.log.size() - log_before,
					"age": str(w.ages.age), "age_chg": str(w.ages.age) != age_before, "deaths": deaths_before})
	print("seed %d sols %d council %s rel %s check %s steps %d mean_step_us %.1f digest %s" % [seed_in, sols, con, ron, check, all_steps,
			float(all_us) / float(maxi(1, all_steps)), _digest(w)])
	print("gate digest (stats.council, Landing-boundary readings masked) %s, landing boundaries %d" % [_gate_digest(w, landing_idx), landing_idx.size()])
	_report(rows, "all boundary steps", func(r): return true)
	_report(rows, "pop > 120", func(r): return int(r.pop) > 120)
	var hi: Array = rows.filter(func(r): return int(r.pop) > 120)
	hi.sort_custom(func(x, y): return x.total > y.total)
	print("top spikes at pop > 120 (sol pop age total_us | phases us | births rel_tick log_lines age_changed):")
	for k in mini(8, hi.size()):
		var r: Dictionary = hi[k]
		var ps: Array[String] = []
		for j in PH.size():
			ps.append("%s=%d" % [PH[j], int(r.ph[j])])
		print("  sol %d pop %d %s %d | %s | b%d t%s l%d c%s" % [r.sol, r.pop, r.age, r.total, " ".join(ps), r.births, str(r.rel_tick), r.log, str(r.age_chg)])
	quit(0)


## Digest of what the gate and the Council term can see: pop, births, deaths, age_history and stats.council with the series entries
## written at Landing boundaries (and the live trust/chosen/voices if the run ends in Landing) set to zero. Equal before and after
## remedy (a) exactly when nothing outside Landing readings changed.
static func _gate_digest(w: SimWorld, landing_idx: Array) -> String:
	var c: Dictionary = w.stats.council.duplicate(true)
	for i in landing_idx:
		c.trust_by_sol[i] = 0.0
		c.chosen_by_sol[i] = 0.0
	if str(w.ages.age) == "landing":
		c.trust = 0.0
		c.chosen = 0.0
		c.voices = 0
	var d := {"pop": w.colony.pop(), "births": w.stats.births, "deaths": w.stats.deaths, "age": w.stats.age_history, "council": c}
	return JSON.stringify(d, "", true, true).sha256_text().substr(0, 16)


func _report(rows: Array, label: String, pred: Callable) -> void:
	var sel: Array = rows.filter(pred)
	var tot: Array = sel.map(func(r): return r.total)
	print("%s: n %d total_us median %.0f p95 %.0f max %.0f" % [label, sel.size(), _pct(tot, 0.5), _pct(tot, 0.95), _pct(tot, 1.0)])
	for j in PH.size():
		var v: Array = sel.map(func(r): return r.ph[j])
		print("    %-26s median %7.0f p95 %7.0f max %7.0f" % [PH[j], _pct(v, 0.5), _pct(v, 0.95), _pct(v, 1.0)])


## Copy of SimWorld.step() with timers; keep in line with sim/world.gd.
func _step(w: SimWorld, ph: Array) -> void:
	var t0 := Time.get_ticks_usec()
	w.t += w.fixed_step
	w.buildings.now = w.t
	w.step_index += 1
	w.colony.step_stocks(w.fixed_step)
	w._sol_boundary()
	w._manage_power()
	for x in w.colony.air_food_warnings(w.t):
		w._log(x.kind, x.text)
	for x in w.colony.drain_ice(w.t, w.fixed_step):
		w._log(x.kind, x.text)
	if w.scouting_enabled and w.resources.scout(w.fixed_step) != null:
		w.stats.scouts_found += 1
		w._log("scouts_found", "Scouts found a new ice field.")
	var t1 := Time.get_ticks_usec()
	ph[0] += t1 - t0
	w._update_beings()
	var t2 := Time.get_ticks_usec()
	ph[1] += t2 - t1
	w._birth_phase()
	var t3 := Time.get_ticks_usec()
	ph[2] += t3 - t2
	w._build_decision()
	w._construction_progress()
	var death := w.colony.shortage_check(w.fixed_step)
	if not death.is_empty():
		w._kill(death.victim, death.cause)
	var silent := w.colony.pop() == 0
	if silent and not w.colony.extinct:
		w._log("colony_silent", "The colony has fallen silent.")
	w.colony.extinct = silent
	w.resources.expire_footprints(w.t, float(SimData.suits().footprint.fade_sols) * w.clock.sol_h)
	w._sample_power_stats()
	w._sample_being_stats()
	var t4 := Time.get_ticks_usec()
	ph[3] += t4 - t3
	if w.relationships_enabled and w.relationships != null:
		w.relationships.on_step(w, w.fixed_step)
	var t5 := Time.get_ticks_usec()
	ph[4] += t5 - t4
	if w.council_enabled and w.council != null:
		w.council.on_step(w)
	var t6 := Time.get_ticks_usec()
	ph[5] += t6 - t5
	if w._sol_started:
		w.stats.pop_by_sol.append(w.colony.pop())
		w._stat_add("sol_samples", 1)
		if w.resources.reachable_ice_count() >= int(SimData.resources().scout.min_reachable):
			w._stat_add("reachable_ok_samples", 1)
		var t7 := Time.get_ticks_usec()
		if w.ages_enabled:
			w.ages.on_sol(w)
		var t8 := Time.get_ticks_usec()
		ph[6] += t8 - t7
		if w.relationships_enabled and w.relationships != null:
			w.relationships.on_sol(w)
		var t9 := Time.get_ticks_usec()
		ph[7] += t9 - t8
		if w.council_enabled and w.council != null:
			w.council.on_sol(w)
		ph[8] += Time.get_ticks_usec() - t9
