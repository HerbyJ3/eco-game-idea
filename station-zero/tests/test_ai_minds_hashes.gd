extends "res://tests/minds_lib.gd"
## Task 6b, step 3 (tests first, red): the reference-hash tests. Spec docs/specs/ai-minds.md revision 4, section 14 tests 1, 2, 3
## and 31 (the `mn` hash column and the four proof scripts).
##
## HEAVY: tests 1 to 3 run five seeds at 300 sols, mode `off` and mode `rules`, twice each (20 runs of about 25 s; the runs are
## cached between the three tests, so the file costs about 8 minutes once). Run it alone with
##   godot --headless --path station-zero --script res://tests/run_tests.gd -- --only test_ai_minds_hashes
## Everything else in the minds suite is fast.
##
## Mode is chosen through the balance parameter override `minds.mode.default` (data/minds.json `mode.default`), so the printed
## `overrides=[...]` header of every run is checked (CLAUDE.md section 4): a run whose override was refused (for example
## because data/minds.json does not exist yet) prints `PARAM ERROR` and the test fails on it.
## The strip of `mn` then `md` is done HERE (a local function) so these tests do not depend on the proof-script edits, which
## test 31 covers. The pinned values are read from tests/mood_hash_proof.gd EXPECTED_T5 (the table with `cn` last), not copied.

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
	_check_mode(t, "off")


func test_t02_mode_rules_matches_the_pinned_hashes_and_off(t) -> void:
	_check_mode(t, "rules")
	if not FileAccess.file_exists("res://data/minds.json"):
		return
	for s in SEEDS:
		var off := _strip_mn_md(_body(_run("off", s, 1).lines))
		var rules := _strip_mn_md(_body(_run("rules", s, 1).lines))
		t.eq(_hash16(rules.body), _hash16(off.body), "seed %d: rules equals off" % s)


func test_t03_rules_draws_nothing_from_simrng(t) -> void:
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


## The hash entries of a proof result: a String (age proof) or the check* keys of a Dictionary.
func _hashes(proof: GDScript, lines: Array) -> Dictionary:
	var r: Variant
	if _has_static(proof, "proof_hashes"):
		r = proof.proof_hashes(lines)
	else:
		r = proof.proof_hash(lines)
	if r is Dictionary:
		var out := {}
		for k in r:
			if str(k).begins_with("check"):
				out[k] = r[k]
		return out
	return {"hash": str(r)}


func _state_text(proof: GDScript, lines: Array) -> String:
	if _has_static(proof, "proof_hashes"):
		return JSON.stringify(proof.proof_hashes(lines)).to_lower()
	return JSON.stringify([proof.proof_hash(lines), proof.get_script_method_list().size()]).to_lower()


func test_t31a_every_proof_strips_mn_then_md_then_its_own_chain(t) -> void:
	for name in PROOFS:
		var proof: GDScript = load("res://tests/%s.gd" % name)
		var plain := _hashes(proof, WITHOUT)
		t.check(not plain.is_empty(), "%s: produces hashes for a pre-6b fixture" % name)
		t.eq(_hashes(proof, WITH_BOTH), plain, "%s: a table ending `age web cn md mn` gives the same hashes as the table without md and mn" % name)
		t.eq(_hashes(proof, WITH_MD_ONLY), plain, "%s: a table without mn (ABSENT) still passes: md alone is stripped" % name)
		t.check(_state_text(proof, WITH_MD_ONLY).contains("absent"), "%s: reports ABSENT for the missing mn" % name)


func test_t31b_misplaced_columns_are_refused(t) -> void:
	for name in PROOFS:
		var proof: GDScript = load("res://tests/%s.gd" % name)
		var plain := _hashes(proof, WITHOUT)
		for fx in [["mn before md", MN_NOT_LAST], ["md not last after mn", MD_MISPLACED]]:
			t.check(_state_text(proof, fx[1]).contains("misplaced"), "%s: %s is reported MISPLACED" % [name, fx[0]])
			t.check(_hashes(proof, fx[1]) != plain, "%s: %s is not silently stripped to the plain hash" % [name, fx[0]])


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
