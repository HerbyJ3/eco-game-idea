extends SceneTree
## Headless test runner.
## godot --headless --path station-zero --script res://tests/run_tests.gd [-- --only test_clock]

const TEST_DIR := "res://tests/"

var _failures: Array[String] = []
var _checks := 0
var _current := ""


func _init() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	var i := args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1]
	var files: Array[String] = []
	for f in DirAccess.get_files_at(TEST_DIR):
		if f.begins_with("test_") and f.ends_with(".gd"):
			if only == "" or f.get_basename() == only:
				files.append(f)
	files.sort()
	var total := 0
	for f in files:
		var script: GDScript = load(TEST_DIR + f)
		if script == null or not script.can_instantiate():
			_failures.append("%s: failed to load (parse error?)" % f)
			print("FAIL %s (load error)" % f)
			continue
		var suite: Object = script.new()
		for m in suite.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			total += 1
			_current = "%s::%s" % [f.get_basename(), name]
			var before := _failures.size()
			var checks_before := _checks
			var t0 := Time.get_ticks_msec()
			suite.call(name, self)
			var ms := Time.get_ticks_msec() - t0
			# A runtime error aborts the test function silently; a test that made no checks failed.
			if _checks == checks_before:
				_fail("made no checks (runtime error?)")
			print("%s %s (%d ms)" % ["PASS" if _failures.size() == before else "FAIL", _current, ms])
	if total == 0:
		_failures.append("no tests ran")
	print("\n%d tests, %d checks, %d failures" % [total, _checks, _failures.size()])
	for msg in _failures:
		print("  " + msg)
	quit(1 if not _failures.is_empty() else 0)


func _fail(msg: String) -> void:
	_failures.append("%s: %s" % [_current, msg])


func check(cond: bool, msg: String = "expected true") -> void:
	_checks += 1
	if not cond:
		_fail(msg)


func eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	_checks += 1
	if actual != expected:
		_fail("%s expected %s, got %s" % [msg, str(expected), str(actual)])


func near(actual: float, expected: float, eps: float, msg: String = "") -> void:
	_checks += 1
	if absf(actual - expected) > eps:
		_fail("%s expected %.9f +/- %s, got %.9f" % [msg, expected, str(eps), actual])


func between(actual: float, lo: float, hi: float, msg: String = "") -> void:
	_checks += 1
	if actual < lo or actual > hi:
		_fail("%s expected in [%s, %s], got %s" % [msg, str(lo), str(hi), str(actual)])
