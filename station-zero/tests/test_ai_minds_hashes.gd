extends "res://tests/minds_lib.gd"
## Task 6b, step 3 (tests first, red): the reference-hash tests. Spec docs/specs/ai-minds.md revision 6, section 14 tests 1, 2, 3
## and 31 (the `mn` hash column and the four proof scripts).
##
## HEAVY: tests 1 to 3 run five seeds at 300 sols, mode `off` and mode `rules`, twice each (20 runs of about 25 s; the runs are
## cached between the three tests, so the file costs about 8 minutes once). Revision 6 (spec 14): they run ONLY on request,
##   godot --headless --path station-zero --script res://tests/run_tests.gd -- --only test_ai_minds_hashes
## Without those user args each of tests 1 to 3 prints `SKIP heavy: run with --only test_ai_minds_hashes` and records one check
## that the skip reason was recorded (the zero-check rule). Test 31 (fixtures and proof contracts) is cheap and always runs.
## Everything else in the minds suite is fast.
##
## Mode is chosen through the balance parameter override `minds.mode.default` (data/minds.json `mode.default`), so the printed
## `overrides=[...]` header of every run is checked (CLAUDE.md section 4): a run whose override was refused (for example
## because data/minds.json does not exist yet) prints `PARAM ERROR` and the test fails on it.
## The strip of `mn` then `md` is done HERE (a local function) so tests 1 to 3 do not depend on the proof-script edits, which
## test 31 covers (revision 5: all four proofs strip `mn` then `md` through the shared helper `strip_mn_md` in
## tests/council_hash_proof.gd, and `mood_hash_proof.strip_md` delegates to it). The pinned values are read from tests/mood_hash_proof.gd EXPECTED_T5 (the table with `cn` last), not copied.

var _runs := {}


func _lib() -> GDScript:
	return load("res://tests/balance_lib.gd")


func _pinned() -> Dictionary:
	return load("res://tests/mood_hash_proof.gd").EXPECTED_T5


## {lines, rng} of a cached 300-sol run.
func _run(mode: String, seed_in: int, rep: int) -> Dictionary:
	var key := "%s:%d:%d" % [mode, seed_in, rep]
	if not _runs.has(key):
		var r: Dictionary = _lib().run(seed_in, 300, {"minds.mode.default": mode}, 30)
		_runs[key] = {"lines": r.lines, "rng": _rng_state(r.world)}
	return _runs[key]


func _body(lines: Array) -> Array:
	return load("res://tests/age_hash_proof.gd").body_of(lines)


## Strips `mn` and then `md` from the table body; {body, ok} with ok false when the header does not end `md mn`.
func _strip_mn_md(body: Array) -> Dictionary:
	var head: PackedStringArray = str(body[0]).split(" ", false) if not body.is_empty() else PackedStringArray()
	var ok := head.size() >= 2 and head[head.size() - 1] == "mn" and head[head.size() - 2] == "md"
	if not ok:
		return {"body": body, "ok": false}
	var out: Array = []
	for l in body:
		var s := str(l)
		for i in 2:
			s = s.substr(0, s.rfind(" "))
		out.append(s)
	return {"body": out, "ok": true}


func _hash16(body: Array) -> String:
	return "\n".join(PackedStringArray(body)).sha256_text().substr(0, 16)


const SKIP_HEAVY := "SKIP heavy: run with --only test_ai_minds_hashes"
var _skip_log: Array[String] = []


## True (after printing the skip line and recording one check) when the heavy runs were not asked for.
func _skip_unless_heavy(t) -> bool:
	if _heavy_requested():
		return false
	print("%s (%s)" % [SKIP_HEAVY, t._current])
	_skip_log.append(SKIP_HEAVY)
	t.check(_skip_log.back() == SKIP_HEAVY, "heavy test skipped on purpose; reason recorded: " + SKIP_HEAVY)
	return true


func _check_mode(t, mode: String) -> void:
	if not FileAccess.file_exists("res://data/minds.json"):
		t.check(false, "missing API: data/minds.json (the mode override `minds.mode.default` has nothing to override)")
		return
	var pinned := _pinned()
	for s in SEEDS:
		var a := _run(mode, s, 1)
		var b := _run(mode, s, 2)
		t.check(str(a.lines[0]).contains("overrides=[minds.mode.default=%s]" % mode), "seed %d %s: the overrides header names the mode override" % [s, mode])
		t.check(not a.lines.any(func(l): return str(l).begins_with("PARAM ERROR")), "seed %d %s: no PARAM ERROR line" % [s, mode])
		var sa := _strip_mn_md(_body(a.lines))
		var sb := _strip_mn_md(_body(b.lines))
		t.check(bool(sa.ok), "seed %d %s: the table header ends `md mn`" % [s, mode])
		t.eq(_hash16(sa.body), str(pinned[s]), "seed %d %s: hash with mn and md stripped equals the pinned reference" % [s, mode])
		t.eq(_hash16(sb.body), _hash16(sa.body), "seed %d %s: the second run gives the same hash" % [s, mode])


func test_t01_mode_off_matches_the_pinned_hashes(t) -> void:
	if _skip_unless_heavy(t):
		return
	_check_mode(t, "off")


func test_t02_mode_rules_matches_the_pinned_hashes_and_off(t) -> void:
	if _skip_unless_heavy(t):
		return
	_check_mode(t, "rules")
	if not FileAccess.file_exists("res://data/minds.json"):
		return
	for s in SEEDS:
		var off := _strip_mn_md(_body(_run("off", s, 1).lines))
		var rules := _strip_mn_md(_body(_run("rules", s, 1).lines))
		t.eq(_hash16(rules.body), _hash16(off.body), "seed %d: rules equals off" % s)


func test_t03_rules_draws_nothing_from_simrng(t) -> void:
	if _skip_unless_heavy(t):
		return
	if not FileAccess.file_exists("res://data/minds.json"):
		t.check(false, "missing API: data/minds.json")
		return
	for s in SEEDS:
		var off := _run("off", s, 1)
		var rules := _run("rules", s, 1)
		t.check(str(off.lines[0]).contains("minds.mode.default=off") and str(rules.lines[0]).contains("minds.mode.default=rules"), "seed %d: both runs carry their override header" % s)
		t.eq(rules.rng, off.rng, "seed %d: SimRng state and the next five draws equal after 300 sols" % s)


# ---------------------------------------------------------------- 31. the mn column and the four proof scripts

const PROOFS := ["mood_hash_proof", "relationships_hash_proof", "council_hash_proof", "age_hash_proof"]
const WITH_BOTH := ["# header", "# more", "sol pop age web cn md mn", "30 5 L 0.1 - +0.01 0", "60 6 S 0.2 C -0.02 3", ""]
const WITHOUT := ["# header", "# more", "sol pop age web cn", "30 5 L 0.1 -", "60 6 S 0.2 C", ""]
const WITH_MD_ONLY := ["# header", "# more", "sol pop age web cn md", "30 5 L 0.1 - +0.01", "60 6 S 0.2 C -0.02", ""]
const MN_NOT_LAST := ["# header", "# more", "sol pop age web cn mn md", "30 5 L 0.1 - 0 +0.01", "60 6 S 0.2 C 3 -0.02", ""]
const MD_MISPLACED := ["# header", "# more", "sol md pop age web cn mn", "30 +0.01 5 L 0.1 - 0", "60 -0.02 6 S 0.2 C 3", ""]


const STATES := ["ok", "absent", "misplaced"]
const WITH_MN_ONLY := ["# header", "# more", "sol pop age web cn mn", "30 5 L 0.1 - 0", "60 6 S 0.2 C 3", ""]
## The keys each proof returned before 6b (spec 10, contract item 3: they are kept) and the ones age_hash_proof must add (item 4).
const KEPT_KEYS := {
	"mood_hash_proof": ["check0", "check1", "check2", "check3"],
	"relationships_hash_proof": ["check1", "check2", "web_absent", "age_absent"],
	"council_hash_proof": ["check1", "check2", "check3", "cn_absent", "web_absent", "age_absent"],
	"age_hash_proof": ["check1", "age_absent"],
}


## The hash entries of a proof result: the check* keys of its proof_hashes Dictionary (the contract of spec 10).
func _hashes(proof: GDScript, lines: Array) -> Dictionary:
	var out := {}
	if not _has_static(proof, "proof_hashes"):
		return out
	var r: Variant = proof.proof_hashes(lines)
	if r is Dictionary:
		for k in r:
			if str(k).begins_with("check"):
				out[k] = r[k]
	return out


## proof.proof_hashes(lines) when the contract's function exists and returns a Dictionary, else {}.
func _result(proof: GDScript, lines: Array) -> Dictionary:
	if not _has_static(proof, "proof_hashes"):
		return {}
	var r: Variant = proof.proof_hashes(lines)
	return r if r is Dictionary else {}


func _states(t, name: String, label: String, r: Dictionary, mn: String, md: String) -> void:
	t.check(r.has("mn_state") and r.has("md_state"), "%s: %s: proof_hashes carries mn_state and md_state" % [name, label])
	if r.has("mn_state"):
		t.check(str(r.mn_state) in STATES, "%s: %s: mn_state is one of ok/absent/misplaced (got %s)" % [name, label, str(r.get("mn_state"))])
		if mn != "":
			t.eq(str(r.mn_state), mn, "%s: %s: mn_state" % [name, label])
	if r.has("md_state"):
		t.check(str(r.md_state) in STATES, "%s: %s: md_state is one of ok/absent/misplaced (got %s)" % [name, label, str(r.get("md_state"))])
		if md != "":
			t.eq(str(r.md_state), md, "%s: %s: md_state" % [name, label])


func test_t31a_every_proof_strips_mn_then_md_then_its_own_chain(t) -> void:
	for name in PROOFS:
		var proof: GDScript = load("res://tests/%s.gd" % name)
		t.check(_has_static(proof, "proof_hashes"), "%s: exposes static proof_hashes(lines) -> Dictionary (spec 5.9, 10)" % name)
		if not _has_static(proof, "proof_hashes"):
			continue
		var plain := _hashes(proof, WITHOUT)
		t.check(not plain.is_empty(), "%s: produces hashes for a pre-6b fixture" % name)
		t.eq(_hashes(proof, WITH_BOTH), plain, "%s: a table ending `age web cn md mn` gives the same hashes as the table without md and mn" % name)
		t.eq(_hashes(proof, WITH_MD_ONLY), plain, "%s: a table without mn (ABSENT) still passes: md alone is stripped" % name)
		t.eq(_hashes(proof, WITH_MN_ONLY), plain, "%s: a table without md (ABSENT) still passes: mn alone is stripped" % name)
		# The uniform state contract, exact (no substring matching): ok / absent / misplaced, lowercase.
		_states(t, name, "full fixture", _result(proof, WITH_BOTH), "ok", "ok")
		_states(t, name, "pre-6b fixture", _result(proof, WITHOUT), "absent", "absent")
		_states(t, name, "no mn", _result(proof, WITH_MD_ONLY), "absent", "ok")
		_states(t, name, "no md", _result(proof, WITH_MN_ONLY), "ok", "absent")
		var full := _result(proof, WITH_BOTH)
		for k in KEPT_KEYS[name]:
			t.check(full.has(k), "%s: the existing key `%s` is kept" % [name, k])
		if name == "age_hash_proof":
			# Item 4: age_hash_proof gains proof_hashes returning {mn_state, md_state, age_absent, check1}.
			for k in ["mn_state", "md_state", "age_absent", "check1"]:
				t.check(full.has(k), "age_hash_proof.proof_hashes returns `%s`" % k)
			t.check(full.get("age_absent", null) is bool and not bool(full.get("age_absent", true)), "age_absent is a bool, false when an age column was stripped")
			t.check(str(full.get("check1", "")).length() == 64, "check1 is the full SHA-256 hex of the stripped table")
			t.check(bool(_result(proof, ["# header", "# more", "sol pop web cn", "30 5 L 0.1", ""]).get("age_absent", false)), "age_absent is true when the table has no age column")
			t.eq(str(proof.proof_hash(WITH_BOTH)), str(full.get("check1", "")), "proof_hash(lines) stays and returns proof_hashes(lines).check1")


func test_t31e_the_shared_strip_helper_and_the_delegation(t) -> void:
	var council: GDScript = load("res://tests/council_hash_proof.gd")
	var mood: GDScript = load("res://tests/mood_hash_proof.gd")
	t.check(_has_static(council, "strip_mn_md"), "missing API: council_hash_proof.strip_mn_md(body) -> {body, mn, md}")
	t.check(_has_static(mood, "strip_md"), "mood_hash_proof keeps the public name strip_md")
	if not _has_static(council, "strip_mn_md") or not _has_static(mood, "strip_md"):
		return
	var plain: Array = WITHOUT.slice(2, 5)
	var both: Array = WITH_BOTH.slice(2, 5)
	var only_md: Array = WITH_MD_ONLY.slice(2, 5)
	var only_mn: Array = WITH_MN_ONLY.slice(2, 5)
	var r: Dictionary = council.strip_mn_md(both)
	var keys: Array = r.keys()
	keys.sort()
	t.eq(keys, ["body", "md", "mn"], "strip_mn_md returns exactly {body, mn, md}")
	t.eq(r.body, plain, "strip_mn_md removes mn then md from a table ending `cn md mn`")
	t.eq([str(r.mn), str(r.md)], ["ok", "ok"], "and reports ok for both")
	var r_md: Dictionary = council.strip_mn_md(only_md)
	t.eq(r_md.body, plain, "a table without mn still has md stripped")
	t.eq([str(r_md.mn), str(r_md.md)], ["absent", "ok"], "the missing mn is reported absent, md ok")
	var r_mn: Dictionary = council.strip_mn_md(only_mn)
	t.eq(r_mn.body, plain, "a table without md still has mn stripped")
	t.eq([str(r_mn.mn), str(r_mn.md)], ["ok", "absent"], "the missing md is reported absent, mn ok")
	var r_none: Dictionary = council.strip_mn_md(plain)
	t.eq(r_none.body, plain, "a pre-6b table is returned unchanged")
	t.eq([str(r_none.mn), str(r_none.md)], ["absent", "absent"], "and reports absent for both")
	var nl: Array = MN_NOT_LAST.slice(2, 5)
	var r_nl: Dictionary = council.strip_mn_md(nl)
	t.eq(str(r_nl.mn), "misplaced", "mn before md: mn is reported misplaced")
	t.eq(r_nl.body, nl, "and nothing is stripped (the body is returned unchanged from that point)")
	t.check(str(r_nl.md) in STATES, "md_state of that table is one of the three strings (got %s)" % str(r_nl.md))
	var mm: Array = MD_MISPLACED.slice(2, 5)
	var r_mm: Dictionary = council.strip_mn_md(mm)
	t.eq([str(r_mm.mn), str(r_mm.md)], ["ok", "misplaced"], "md not last after mn: mn ok, md misplaced")
	t.check(r_mm.body != plain, "and the misplaced md is not silently stripped to the plain table")
	# Delegation: strip_md gives the same body as the shared helper, so the two balance tests need no edit; its `state`
	# carries the md state in the new spelling and `md_absent` stays.
	var s_both: Dictionary = mood.strip_md(both)
	t.eq(s_both.body, plain, "mood_hash_proof.strip_md strips mn then md (delegates)")
	t.eq(str(s_both.state), "ok", "strip_md state for a present md is `ok` (was `last`)")
	var s_md: Dictionary = mood.strip_md(only_md)
	t.eq(s_md.body, plain, "mood_hash_proof.strip_md on a table without mn still strips md")
	t.eq(str(s_md.state), "ok", "and its state is `ok`")
	var s_none: Dictionary = mood.strip_md(plain)
	t.check(s_none.get("md_absent", false) == true and str(s_none.state) == "absent", "strip_md keeps md_absent and reports `absent` for a table without md")
	t.eq(str(mood.md_state(only_md)), "ok", "mood_hash_proof.md_state spells `ok`, not `last`")
	var src := FileAccess.get_file_as_string("res://tests/mood_hash_proof.gd")
	t.check(src.contains("strip_mn_md"), "mood_hash_proof.gd calls the shared helper strip_mn_md")


func test_t31b_misplaced_columns_are_refused(t) -> void:
	for name in PROOFS:
		var proof: GDScript = load("res://tests/%s.gd" % name)
		t.check(_has_static(proof, "proof_hashes"), "%s: exposes proof_hashes" % name)
		if not _has_static(proof, "proof_hashes"):
			continue
		var plain := _hashes(proof, WITHOUT)
		# `mn` before `md`: mn is the first field stripped and is not last: misplaced (md_state is judged on the unstripped
		# body; the contract only fixes that it is one of the three strings).
		var nl := _result(proof, MN_NOT_LAST)
		_states(t, name, "mn before md", nl, "misplaced", "")
		t.check(_hashes(proof, MN_NOT_LAST) != plain, "%s: mn before md is not silently stripped to the plain hash" % name)
		# `md` not last once mn is stripped: mn ok, md misplaced.
		var mm := _result(proof, MD_MISPLACED)
		_states(t, name, "md not last after mn", mm, "ok", "misplaced")
		t.check(_hashes(proof, MD_MISPLACED) != plain, "%s: md not last after mn is not silently stripped to the plain hash" % name)


func test_t31c_the_e1f2bdd_history_is_marked_retired(t) -> void:
	for name in PROOFS:
		var src := FileAccess.get_file_as_string("res://tests/%s.gd" % name)
		t.check(src.contains("e1f2bdd") and src.contains("RETIRED"), "%s: the e1f2bdd chain comment is marked RETIRED" % name)


func test_t31d_balance_lib_prints_mn_after_md(t) -> void:
	var lib := _lib()
	for mode in ["rules", "off"]:
		var r: Dictionary = lib.run(7, 30, {"minds.mode.default": mode} if FileAccess.file_exists("res://data/minds.json") else {}, 30)
		var body := _body(r.lines)
		t.eq(body.size(), 2, "%s: header and one row at sol 30" % mode)
		var head: PackedStringArray = str(body[0]).split(" ", false)
		t.eq(" ".join(head.slice(head.size() - 5)), "age web cn md mn", "%s: the header ends `age web cn md mn`" % mode)
		var row: PackedStringArray = str(body[1]).split(" ", false)
		# Two header labels hold a space ("dead a/t/h/o/x", "bldg R/H/W/G/A/C") and are one field in a row.
		t.eq(row.size(), head.size() - 2, "%s: the row has as many fields as the header (two labels with a space)" % mode)
		var applied := 0
		if r.world.stats.has("minds"):
			applied = int(r.world.stats.minds.applied_model)
		t.eq(row[row.size() - 1], str(applied), "%s: mn is applied_model printed %%d" % mode)
		t.check(row[row.size() - 2].begins_with("+") or row[row.size() - 2].begins_with("-"), "%s: md stays before mn" % mode)
	var src := FileAccess.get_file_as_string("res://tests/balance_lib.gd")
	t.check(src.contains("\"mn\""), "balance_lib.gd names the mn column")
