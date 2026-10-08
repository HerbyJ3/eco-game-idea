extends SceneTree
## Task 6a standalone 300-sol check of the T13 invariants (spec docs/specs/emotions.md section 12 "T13" and section 13 test 19's
## 300-sol sentence). NOT a unit test (it does not start with test_; run_tests.gd keeps to staged and 60-sol tests):
##
##   godot --headless --path station-zero --script res://tests/mood_t13_check.gd [-- --seed N ...]
##
## The T13 definition itself belongs in tests/balance_lib.gd (a spec 9.1 edit for the implementation step, which this tests-first
## step does not make); this script checks the same six invariants on the real sim at the shipped gains, over three seeds by
## default (42, 7, 1234), 300 sols each, reading the log as it is written (the 500-entry log is FIFO, so every step's new
## entries are collected before they can fall off):
##   (1) mean_by_sol, sd_by_sol, heavy_by_sol have the length of pop_by_sol;
##   (2) at most one mood_* log entry per elapsed sol;
##   (3) every mood_relief has an earlier mood_quiet of the same being at least lines.relief_min_sols sols before;
##   (4) heavy_by_sol never exceeds balance.heavy_share_max after sol 30;
##   (5) min_dev not below range.floor_dev and max_dev not above range.ceil_dev;
##   (6) deaths_unexplained is 0.
## Prints one line per seed with the counts and PASS or FAIL; stats.moods missing prints ABSENT and fails. Exit 0 only when every
## requested seed passes every invariant.

const SOLS := 300


func _init() -> void:
	var seeds: Array = []
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			i += 1
			seeds.append(int(args[i]))
		i += 1
	if seeds.is_empty():
		seeds = [42, 7, 1234]
	var all_ok := true
	for s in seeds:
		all_ok = _run(int(s)) and all_ok
	quit(0 if all_ok else 1)


func _run(seed_in: int) -> bool:
	var w := SimWorld.new(seed_in)
	if not w.stats.has("moods"):
		print("seed %d: stats.moods ABSENT FAIL" % seed_in)
		return false
	var md: Dictionary = SimData.load_json("mood.json")
	var min_sols := float(md.lines.relief_min_sols)
	var per_sol := {}
	var quiet_t := {}
	var rel_bad := 0
	var n_quiet := 0
	var n_relief := 0
	var last_t := -1.0
	while w.sol() < SOLS:
		w.step()
		var k := w.log.size() - 1
		while k >= 0 and float(w.log[k].t) > last_t:
			k -= 1
		for j in range(k + 1, w.log.size()):
			var e: Dictionary = w.log[j]
			var kind := str(e.kind)
			if not kind.begins_with("mood_"):
				continue
			per_sol[int(e.sol)] = int(per_sol.get(int(e.sol), 0)) + 1
			var id := int(e.being_id)
			if kind == "mood_quiet":
				n_quiet += 1
				if not quiet_t.has(id):
					quiet_t[id] = []
				quiet_t[id].append(float(e.t))
			elif kind == "mood_relief":
				n_relief += 1
				var found := false
				for qt in quiet_t.get(id, []):
					if float(e.t) - float(qt) >= min_sols * w.clock.sol_h - 1e-6:
						found = true
				if not found:
					rel_bad += 1
		if w.log.size() > 0:
			last_t = float(w.log.back().t)
	var m: Dictionary = w.stats.moods
	var n: int = w.stats.pop_by_sol.size()
	var ok1: bool = m.mean_by_sol.size() == n and m.sd_by_sol.size() == n and m.heavy_by_sol.size() == n
	var worst := 0
	for s in per_sol:
		worst = maxi(worst, int(per_sol[s]))
	var ok2: bool = worst <= int(md.lines.max_per_sol)
	var ok3: bool = rel_bad == 0
	var heavy_max := 0.0
	for sol_i in range(31, m.heavy_by_sol.size()):
		heavy_max = maxf(heavy_max, float(m.heavy_by_sol[sol_i]))
	var ok4: bool = heavy_max <= float(md.balance.heavy_share_max)
	var ok5: bool = float(m.min_dev) >= float(md.range.floor_dev) - 1e-9 and float(m.max_dev) <= float(md.range.ceil_dev) + 1e-9
	var ok6: bool = int(w.stats.deaths_unexplained) == 0
	var ok := ok1 and ok2 and ok3 and ok4 and ok5 and ok6
	print("seed %d: series %s | lines/sol worst %d %s | quiet %d relief %d relief-without-quiet %d %s | heavy max %.3f %s | dev [%.3f, %.3f] %s | unexplained %d %s | %s" % [
			seed_in, "ok" if ok1 else "BAD", worst, "ok" if ok2 else "BAD", n_quiet, n_relief, rel_bad, "ok" if ok3 else "BAD",
			heavy_max, "ok" if ok4 else "BAD", float(m.min_dev), float(m.max_dev), "ok" if ok5 else "BAD",
			int(w.stats.deaths_unexplained), "ok" if ok6 else "BAD", "PASS" if ok else "FAIL"])
	return ok
