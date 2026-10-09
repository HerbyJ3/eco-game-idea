extends SceneTree
## Step profile (docs/specs/ages.md section 11, plan step 10). Timers live here, outside sim/; sim/ is untouched.
##   godot --headless --path station-zero --script res://tools/step_profile.gd -- --seed 42 --sol 300 [--steps 1500]
## Builds the seed world, steps it to --sol (the slow part, once per run), then:
##   A. times plain SimWorld.step() for --steps steps (the headline step cost, no instrumentation inside);
##   B. times the next --steps steps through a copy of step() that wraps each phase (spec section 5) in
##      Time.get_ticks_usec, and each being update (bucketed by what the being was about to do);
##   C. micro-benchmarks the sim functions the beings call, on the live world, read-only.
## The copy of step() in _timed_step must be kept in line with SimWorld.step(); it calls the same phase methods in the
## same order, so the world it produces is the world step() would have produced (checked by --check, which runs two
## equal worlds, one per path, and compares a state digest).
## Output is plain text. Absolute numbers are machine-specific; compare before/after on one idle machine.

var _phase_names: Array[String] = ["1 clock", "2 stocks", "3 sol_boundary+power", "4 warnings", "5 ice+scout",
		"6 update_beings", "7 births", "8 build_decision", "9 construction", "10 shortage",
		"11a expire_footprints", "11b sample_power", "11c sample_beings", "11d sol_samples", "11e age_hook"]
var _phase: Array = []
var _bucket_names: Array[String] = ["sleep", "idle_waiting", "idle_decide", "to_door_waiting", "to_door_action",
		"transit", "eva", "work", "mining", "outside_other"]
## bucket -> Array of per-call usec; and per-step totals per bucket.
var _bucket_calls: Dictionary = {}
var _bucket_step: Dictionary = {}
var _totals: Array = []
var _plain: Array = []
var _decide_calls := 0
var _door_calls := 0
var _steps_seen := 0


func _initialize() -> void:
	_run.call_deferred()


func _args() -> Dictionary:
	var m := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--"):
			if i + 1 < a.size() and not a[i + 1].begins_with("--"):
				m[a[i].substr(2)] = a[i + 1]
				i += 1
			else:
				m[a[i].substr(2)] = "true"
		i += 1
	return m


static func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[mini(sorted.size() - 1, int(floor(p * float(sorted.size()))))])


static func _sorted(a: Array) -> Array:
	var s := a.duplicate()
	s.sort()
	return s


static func _mean(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / maxf(1.0, float(a.size()))


static func digest(w: SimWorld) -> String:
	var parts: Array[String] = ["%d %.9f %.9f %.9f %.9f %.9f" % [w.step_index, w.t, w.colony.oxygen, w.colony.food,
			w.colony.ice, w.colony.regolith], str(w.stats.births), str(w.log.size())]
	for b in w.beings:
		parts.append("%d %s %.9f %s %s %s" % [b.id, b.state, b.energy, str(b.x), str(b.y), str(b.building_id)])
	for f in w.resources.footprints:
		parts.append("%.6f,%.6f" % [f.x, f.y])
	return "\n".join(parts).sha256_text().substr(0, 16)


func _bucket_of(b: Being, dt: float) -> String:
	match b.state:
		"sleep":
			return "sleep"
		"idle":
			return "idle_decide" if b.wait_h - dt <= SimWorld.STEP_EPS else "idle_waiting"
		"to_door":
			return "to_door_action" if b.wait_h - dt <= SimWorld.STEP_EPS else "to_door_waiting"
		"transit", "eva", "work", "mining":
			return b.state
	return "outside_other"


## A copy of SimWorld.step() with timers. Keep identical in order and content.
func _timed_step(w: SimWorld) -> void:
	var p := _phase
	var t0 := Time.get_ticks_usec()
	w.t += w.fixed_step
	w.buildings.now = w.t
	w.step_index += 1
	var t1 := Time.get_ticks_usec()
	p[0].append(t1 - t0)
	w.colony.step_stocks(w.fixed_step)
	var t2 := Time.get_ticks_usec()
	p[1].append(t2 - t1)
	w._sol_boundary()
	w._manage_power()
	var t3 := Time.get_ticks_usec()
	p[2].append(t3 - t2)
	for x in w.colony.air_food_warnings(w.t):
		w._log(x.kind, x.text)
	var t4 := Time.get_ticks_usec()
	p[3].append(t4 - t3)
	for x in w.colony.drain_ice(w.t, w.fixed_step):
		w._log(x.kind, x.text)
	if w.scouting_enabled and w.resources.scout(w.fixed_step) != null:
		w.stats.scouts_found += 1
		w._log("scouts_found", "Scouts found a new ice field.")
	var t5 := Time.get_ticks_usec()
	p[4].append(t5 - t4)
	# Phase 6, with each being timed (same loop as SimWorld._update_beings).
	var step_bucket := {}
	for k in _bucket_names:
		step_bucket[k] = 0
	for b in w.beings.duplicate():
		if w.beings.has(b):
			var k := _bucket_of(b, w.fixed_step)
			var a := Time.get_ticks_usec()
			b.update(w, w.fixed_step)
			var d := Time.get_ticks_usec() - a
			_bucket_calls[k].append(d)
			step_bucket[k] += d
			if k == "idle_decide":
				_decide_calls += 1
			elif k == "to_door_action":
				_door_calls += 1
	for k in _bucket_names:
		_bucket_step[k].append(step_bucket[k])
	var t6 := Time.get_ticks_usec()
	p[5].append(t6 - t5)
	w._birth_phase()
	var t7 := Time.get_ticks_usec()
	p[6].append(t7 - t6)
	w._build_decision()
	var t8 := Time.get_ticks_usec()
	p[7].append(t8 - t7)
	w._construction_progress()
	var t9 := Time.get_ticks_usec()
	p[8].append(t9 - t8)
	var death := w.colony.shortage_check(w.fixed_step)
	if not death.is_empty():
		w._kill(death.victim, death.cause)
	var silent := w.colony.pop() == 0
	if silent and not w.colony.extinct:
		w._log("colony_silent", "The colony has fallen silent.")
	w.colony.extinct = silent
	var t10 := Time.get_ticks_usec()
	p[9].append(t10 - t9)
	w.resources.expire_footprints(w.t, float(SimData.suits().footprint.fade_sols) * w.clock.sol_h)
	var t11 := Time.get_ticks_usec()
	p[10].append(t11 - t10)
	w._sample_power_stats()
	var t12 := Time.get_ticks_usec()
	p[11].append(t12 - t11)
	w._sample_being_stats()
	var t13 := Time.get_ticks_usec()
	p[12].append(t13 - t12)
	var t14 := t13
	if w._sol_started:
		w.stats.pop_by_sol.append(w.colony.pop())
		w._stat_add("sol_samples", 1)
		if w.resources.reachable_ice_count() >= int(SimData.resources().scout.min_reachable):
			w._stat_add("reachable_ok_samples", 1)
		t14 = Time.get_ticks_usec()
		p[13].append(t14 - t13)
		if w.ages_enabled:
			w.ages.on_sol(w)
		var t15 := Time.get_ticks_usec()
		p[14].append(t15 - t14)
		_totals.append(t15 - t0)
		return
	_totals.append(t14 - t0)


## Time of one call of `f`, median over `n` runs, usec (float, from a batch timer for sub-microsecond calls).
func _bench(f: Callable, n: int) -> float:
	var s := Time.get_ticks_usec()
	for i in n:
		f.call()
	return float(Time.get_ticks_usec() - s) / float(n)


func _micro(w: SimWorld) -> void:
	print("\nMicro-benchmarks on the live world (mean usec per call, read-only calls; Callable overhead included, about 0.15 usec):")
	var rows: Array = []
	var ids: Array[int] = []
	for b in w.buildings.list:
		ids.append(b.id)
	var far := ids[ids.size() - 1]
	var near := ids[0]
	var fields: Array = w.resources.ice_fields
	var site: Resources.Site = fields[0] if not fields.is_empty() else (w.resources.pits[0] if not w.resources.pits.is_empty() else null)
	var being: Being = w.beings[0] if not w.beings.is_empty() else null
	var n := 2000
	rows.append(["empty Callable (overhead)", _bench(func(): pass, n * 5)])
	rows.append(["SimData.beings() (cache lookup)", _bench(func(): SimData.beings(), n * 5)])
	rows.append(["Being._cfg().energy dictionary chain", _bench(func(): var e: Dictionary = SimData.beings().energy; var m := float(e.max), n * 5)])
	rows.append(["Buildings.get_building(last id)", _bench(func(): w.buildings.get_building(far), n)])
	rows.append(["Buildings.get_building(first id)", _bench(func(): w.buildings.get_building(near), n)])
	rows.append(["Buildings.count_online(habitat)", _bench(func(): w.buildings.count_online("habitat"), n)])
	rows.append(["Buildings.supply()", _bench(func(): w.buildings.supply(), n)])
	rows.append(["Buildings.draw()", _bench(func(): w.buildings.draw(), n)])
	rows.append(["Buildings.demand()", _bench(func(): w.buildings.demand(), n)])
	rows.append(["Buildings.next_hop(first, last) BFS", _bench(func(): w.buildings.next_hop(near, far), n)])
	rows.append(["Buildings.next_hop(last, first) BFS", _bench(func(): w.buildings.next_hop(far, near), n)])
	rows.append(["Buildings.nearest_online_habitat", _bench(func(): w.buildings.nearest_online_habitat(far), n)])
	if being != null:
		rows.append(["Being._neighbours (corridor scan)", _bench(func(): being._neighbours(w), n)])
		rows.append(["Being.is_night (static)", _bench(func(): Being.is_night(w), n * 5)])
		rows.append(["Being.idle_wait body w/o rng (cfg chain)", _bench(func(): being._walk_factor(), n * 5)])
	if site != null:
		rows.append(["Resources.launch_for(site)", _bench(func(): w.resources.launch_for(site), n)])
		rows.append(["Resources.trip_time(site)", _bench(func(): w.resources.trip_time(site), n)])
	rows.append(["Resources.reachable_ice_count", _bench(func(): w.resources.reachable_ice_count(), n)])
	rows.append(["Resources.expire_footprints (%d prints)" % w.resources.footprints.size(),
			_bench(func(): w.resources.expire_footprints(w.t, float(SimData.suits().footprint.fade_sols) * w.clock.sol_h), n)])
	rows.append(["SimWorld.choose_site (draws rng: advances stream; run last)", _bench(func(): w.choose_site(), 200)])
	rows.append(["beings.duplicate() (%d)" % w.beings.size(), _bench(func(): w.beings.duplicate(), n)])
	rows.append(["beings.has(b) worst (last being)", _bench(func(): w.beings.has(w.beings[w.beings.size() - 1]), n)])
	rows.append(["Ages.sample(world)", _bench(func(): Ages.sample(w), 500)])
	rows.append(["Ages.family_mars_born(world)", _bench(func(): Ages.family_mars_born(w), 500)])
	for r in rows:
		print("  %-62s %9.2f" % [r[0], r[1]])


func _run() -> void:
	var args := _args()
	var seed_n := int(args.get("seed", 42))
	var sol_target := int(args.get("sol", 300))
	var n_steps := int(args.get("steps", 1500))
	print("step_profile: seed %d, target sol %d, %d steps per pass, godot %s" % [seed_n, sol_target, n_steps,
			Engine.get_version_info().string])
	if args.has("check"):
		_check(seed_n)
		quit(0)
		return
	var w := SimWorld.new(seed_n)
	var t_build := Time.get_ticks_usec()
	while w.sol() < sol_target:
		w.step()
	print("built to sol %d (step %d) in %.1f s; pop %d, buildings %d, footprints %d, ice fields %d, pits %d" % [
			w.sol(), w.step_index, float(Time.get_ticks_usec() - t_build) / 1e6, w.colony.pop(),
			w.buildings.count(), w.resources.footprints.size(), w.resources.ice_fields.size(), w.resources.pits.size()])

	# Pass A: plain step().
	for i in 100:
		w.step()
	for i in n_steps:
		var a := Time.get_ticks_usec()
		w.step()
		_plain.append(Time.get_ticks_usec() - a)
	var ps := _sorted(_plain)
	print("\nPass A, plain SimWorld.step(): %d steps at pop %d, %d buildings: median %.0f us, mean %.0f us, p95 %.0f us, max %.0f us" % [
			n_steps, w.colony.pop(), w.buildings.count(), _pct(ps, 0.5), _mean(_plain), _pct(ps, 0.95), ps[ps.size() - 1]])

	# Pass B: phases.
	for i in _phase_names.size():
		_phase.append([])
	for k in _bucket_names:
		_bucket_calls[k] = []
		_bucket_step[k] = []
	for i in n_steps:
		_timed_step(w)
	var tsorted := _sorted(_totals)
	var total_mean := _mean(_totals)
	print("\nPass B, timed phases: %d steps, pop %d, step total median %.0f us, mean %.0f us, p95 %.0f us" % [
			n_steps, w.colony.pop(), _pct(tsorted, 0.5), total_mean, _pct(tsorted, 0.95)])
	print("%-26s %9s %9s %9s %8s %7s" % ["phase", "median_us", "p95_us", "mean_us", "calls", "share%"])
	for i in _phase_names.size():
		var s := _sorted(_phase[i])
		var calls: int = s.size()
		var sum := 0.0
		for v in s:
			sum += float(v)
		# share of the average step: sum over all steps / total of all steps
		var share := 100.0 * sum / (total_mean * float(n_steps))
		print("%-26s %9.0f %9.0f %9.2f %8d %7.1f" % [_phase_names[i], _pct(s, 0.5), _pct(s, 0.95),
				sum / float(maxi(1, calls)), calls, share])
	print("\nPhase 6 by being action (per call; per-step share counts the calls of that bucket):")
	print("%-18s %9s %9s %9s %10s %9s %7s" % ["bucket", "median_us", "p95_us", "mean_us", "calls", "calls/step", "share%"])
	for k in _bucket_names:
		var s := _sorted(_bucket_calls[k])
		var sum := 0.0
		for v in s:
			sum += float(v)
		if s.is_empty():
			print("%-18s %9s" % [k, "-"])
			continue
		print("%-18s %9.0f %9.0f %9.2f %10d %9.2f %7.1f" % [k, _pct(s, 0.5), _pct(s, 0.95), sum / float(s.size()),
				s.size(), float(s.size()) / float(n_steps), 100.0 * sum / (total_mean * float(n_steps))])
	print("decide() entered %d times (%.3f per step), _door_action %d times (%.3f per step)" % [
			_decide_calls, float(_decide_calls) / float(n_steps), _door_calls, float(_door_calls) / float(n_steps)])

	# Age hook on its own (the sol boundary step).
	var ah: Array = _phase[14]
	if not ah.is_empty():
		var s := _sorted(ah)
		print("\nAge hook (Ages.on_sol, once per sol): %d samples, median %.0f us, max %.0f us (per step amortised: %.2f us)" % [
				s.size(), _pct(s, 0.5), s[s.size() - 1], float(ah.size()) * _mean(ah) / float(n_steps)])
	_micro(w)
	quit(0)


## Equal-world check: the timed copy must produce the same world as step().
func _check(seed_n: int) -> void:
	var a := SimWorld.new(seed_n)
	var b := SimWorld.new(seed_n)
	for i in _phase_names.size():
		_phase.append([])
	for k in _bucket_names:
		_bucket_calls[k] = []
		_bucket_step[k] = []
	for i in 6000:
		a.step()
		_timed_step(b)
	var da := digest(a)
	var db := digest(b)
	print("check 6000 steps: plain %s timed %s -> %s" % [da, db, "SAME" if da == db else "DIFFERENT"])
