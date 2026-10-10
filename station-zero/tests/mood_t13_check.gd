extends SceneTree
## Task 6a standalone 300-sol check of the T13 invariants (spec docs/specs/emotions.md section 12 "T13" and section 13 test 19's
## 300-sol sentence). NOT a unit test (it does not start with test_; run_tests.gd keeps to staged and 60-sol tests):
##
##   godot --headless --path station-zero --script res://tests/mood_t13_check.gd [-- --seed N ...]
##
## The T13 definition lives in tests/balance_lib.gd (`t13`, with `collect_mood_lines`); this script is its standalone 300-sol
## driver: it runs the real sim at the shipped gains over three seeds by default (42, 7, 1234), collecting the log as it is
## written (the 500-entry log is FIFO, so every step's new entries are collected before they can fall off), and calls it:
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
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var w := SimWorld.new(seed_in)
	if not w.stats.has("moods"):
		print("seed %d: stats.moods ABSENT FAIL" % seed_in)
		return false
	var lines: Array = []
	var seen_t := -1.0
	while w.sol() < SOLS:
		w.step()
		seen_t = lib.collect_mood_lines(w, seen_t, lines)
	var v: Dictionary = lib.t13(w.stats, lines, SimData.moods(), w.clock.sol_h)
	print("seed %d: %s | %s" % [seed_in, str(v.detail), str(v.verdict)])
	return v.verdict == "PASS"
