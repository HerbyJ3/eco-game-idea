## Balance half of docs/specs/council.md section 9 ("Balance columns", 9.1) and section 12 (T10 on the projected history, T12),
## moved in from tests/deferred in Task 5 step 7. balance_lib.run(seed, sols, {}, every) returns {lines, verdicts, world}; a
## verdict is {n, verdict, detail}. One 60-sol run (about 10 s) is shared by the tests that need a printed table.
##
## The 300-sol five-seed judgement and the hash chain (drop cn -> Task 4, drop cn and web -> Task 3, drop cn, web and age ->
## Task 1) are tests/balance_run.gd and tests/council_hash_proof.gd, recorded in docs/balance/task-5-log.md; they take
## minutes and are not unit tests. Here the strip helpers of the hash proof are checked on the real printed table.

extends RefCounted

const SOLS := 60

var _run: Dictionary = {}


func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func _get_run() -> Dictionary:
	if _run.is_empty():
		_run = load("res://tests/balance_lib.gd").run(42, SOLS, {}, 30)
	return _run


func _verdict(r: Dictionary, n: int) -> Dictionary:
	for v in r.verdicts:
		if int(v.n) == n:
			return v
	return {}


func test_printed_table_ends_with_age_web_cn(t) -> void:
	t._failures.append(_abort_msg(t))
	var P: GDScript = load("res://tests/age_hash_proof.gd")
	var r := _get_run()
	# The trailing debug column `md` (emotions.md 9) follows cn; these tests judge the table without it.
	var body: Array = load("res://tests/mood_hash_proof.gd").strip_md(P.body_of(r.lines)).body
	t.eq(body.size(), 3, "header and rows at sols 30 and 60")
	var head: PackedStringArray = str(body[0]).split(" ", false)
	t.eq(" ".join(head.slice(head.size() - 3)), "age web cn", "the header ends with the fields age web cn")
	for i in range(1, body.size()):
		var f: PackedStringArray = str(body[i]).split(" ", false)
		# Two header labels hold a space ("dead a/t/h/o/x", "bldg R/H/W/G/A/C") and are one field in a row.
		t.eq(f.size(), head.size() - 2, "row %d has as many fields as the header (two labels with a space)" % i)
		t.check(f[f.size() - 3] in ["L", "S"], "row %d: age %s is L or S" % [i, f[f.size() - 3]])
		t.check(f[f.size() - 1] in ["-", "C", "P"], "row %d: cn %s is -, C or P" % [i, f[f.size() - 1]])
	# Before the first Council entry cn is "-": the run has no Council entry within 60 sols.
	var cs: Dictionary = r.world.stats.council
	t.check(cs.first_council_sol == null, "no Council entry within 60 sols on seed 42")
	t.eq(str(body[body.size() - 1]).split(" ", false)[-1], "-", "cn is - before the first Council entry")
	t._failures.erase(_abort_msg(t))


func test_cn_column_values_on_staged_worlds(t) -> void:
	t._failures.append(_abort_msg(t))
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var w := SimWorld.new(42)
	t.eq(lib.cn_column(w), "-", "a fresh world: -")
	t.eq(lib.age_column(w), "L", "a fresh world is in Landing: L")
	w.ages.age = "council"
	t.eq(lib.cn_column(w), "C", "in Council, before a pledge: C")
	t.eq(lib.age_column(w), "S", "Council projects to S")
	w.ages.age = "settlement"
	t.eq(lib.cn_column(w), "-", "Settlement without a pledge: -")
	t.eq(lib.age_column(w), "S", "Settlement projects to S")
	w.stats.council.pledge_sol = 200
	t.eq(lib.cn_column(w), "P", "after the pledge: P (in any age)")
	w.ages.age = "council"
	t.eq(lib.cn_column(w), "P", "the pledge wins over C")
	t._failures.erase(_abort_msg(t))


func test_hash_proof_strips_work_on_the_printed_table(t) -> void:
	t._failures.append(_abort_msg(t))
	var P: GDScript = load("res://tests/age_hash_proof.gd")
	var H: GDScript = load("res://tests/council_hash_proof.gd")
	var r := _get_run()
	var body: Array = load("res://tests/mood_hash_proof.gd").strip_md(P.body_of(r.lines)).body
	var c1: Dictionary = H.drop_cn(body)
	t.check(not c1.cn_absent, "drop cn: the column is present")
	t.check(not H.has_last_column(c1.body, "cn"), "and gone from the header")
	t.check(H.has_last_column(c1.body, "web"), "web is now the last field")
	var c2: Dictionary = H.drop_cn_web(body)
	t.check(not c2.cn_absent and not c2.web_absent, "drop cn and web: both present")
	t.check(H.has_last_column(c2.body, "age"), "age is now the last field")
	var c3: Dictionary = H.drop_cn_web_age(body)
	t.check(not c3.cn_absent and not c3.web_absent and not c3.age_absent, "drop cn, web and age: all three present")
	t.eq(str(c3.body[0]).split(" ", false)[-1], "minO2", "the Task 1 table ends with minO2")
	for i in body.size():
		t.eq(str(c3.body[i]).split(" ", false).size(), str(body[i]).split(" ", false).size() - 3, "row %d lost three fields" % i)
	t._failures.erase(_abort_msg(t))


func test_t10_projected_history_helper(t) -> void:
	t._failures.append(_abort_msg(t))
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var h: Array = []
	var sol := 0
	for a in ["landing", "settlement", "council", "landing", "settlement", "council", "settlement"]:
		h.append({"age": a, "how": "x", "sol": sol})
		sol += 30
	# landing, settlement, council, landing, settlement, council, settlement -> L, S, L, S
	t.eq(lib.project_ages(h), ["L", "S", "L", "S"], "Council entries and splits relabel Settlement and are dropped")
	t.eq(lib.projected_changes(h), 3, "three projected changes")
	var h2: Array = []
	for a in ["settlement", "council", "landing", "settlement", "council", "settlement"]:
		h2.append({"age": a, "how": "x", "sol": h2.size() * 30})
	t.eq(lib.project_ages(h2), ["S", "L", "S"], "S, C, L, S, C, S counts as S, L, S")
	t.eq(lib.projected_changes(h2), 2, "with 2 changes")
	t.eq(lib.project_ages([]), [], "an empty history projects to nothing")
	t._failures.erase(_abort_msg(t))


func test_t10_verdict_uses_the_projected_history_and_names_council(t) -> void:
	t._failures.append(_abort_msg(t))
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var r := _get_run()
	var t10 := _verdict(r, 10)
	t.check(not t10.is_empty(), "a T10 verdict is reported")
	var d := str(t10.get("detail", ""))
	var live: Array = r.world.stats.age_history
	t.check(d.contains("age_changes %d (<=" % lib.projected_changes(live)), "T10 age_changes is the projected count: " + d.substr(0, 120))
	t.check(d.contains("council "), "the T10 report names council among the sols_in_age keys")
	t.check(d.contains("settlement ") and d.contains("landing "), "and landing and settlement")
	t.eq(lib.projected_history(live).size(), lib.project_ages(live).size(), "project_ages is one letter per projected entry")
	t._failures.erase(_abort_msg(t))


func test_projected_helper_is_the_one_age_probe_uses(t) -> void:
	# spec 9.1 / tests 18: T10, T12 and tools/age_probe.gd share one implementation (age_probe line 241 comparison).
	var src := FileAccess.get_file_as_string("res://tools/age_probe.gd")
	t.check(src.contains('load("res://tests/balance_lib.gd").projected_history('), "tools/age_probe.gd calls balance_lib.projected_history")
	var lib_src := FileAccess.get_file_as_string("res://tests/balance_lib.gd")
	t.check(lib_src.contains("projected_history(live)"), "balance_lib T10 calls the same helper")
	var h: Array = [{"age": "landing", "sol": 0}, {"age": "settlement", "sol": 50}, {"age": "council", "sol": 90}]
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var got: Array = lib.projected_history(h)
	t.eq(got.size(), 2, "two projected entries")
	t.eq(int(got[1].sol), 50, "the first of a run of S entries is kept (the Settlement entry, not the Council one)")


func test_t12_reports_the_cross_seed_counts(t) -> void:
	t._failures.append(_abort_msg(t))
	var r := _get_run()
	var t12 := _verdict(r, 12)
	t.check(not t12.is_empty(), "a T12 verdict is reported")
	var d := str(t12.get("detail", ""))
	var cfg: Dictionary = SimData.council()
	t.check(d.contains("council_min_seeds %d" % int(cfg.balance.council_min_seeds)), "reports council_min_seeds from data/council.json")
	t.check(d.contains("pledge_min_seeds %d" % int(cfg.balance.pledge_min_seeds)), "reports pledge_min_seeds from data/council.json")
	t.check(str(t12.get("verdict", "")) in ["PASS", "FAIL"], "T12 is judged")
	var cs: Dictionary = r.world.stats.council
	t.eq(cs.trust_by_sol.size(), r.world.stats.pop_by_sol.size(), "(1) trust_by_sol has the length of pop_by_sol")
	t.eq(cs.chosen_by_sol.size(), r.world.stats.pop_by_sol.size(), "(1) chosen_by_sol has the length of pop_by_sol")
	t.eq(t12.verdict, "PASS", "no Council change, no proposal in 60 sols: every T12 condition holds")
	t.check(d.contains("(2) C2 ok") and d.contains("(3) council changes 0") and d.contains("(4) proposals 0 ok"), "details read ok: " + d.substr(0, 160))
	t._failures.erase(_abort_msg(t))
