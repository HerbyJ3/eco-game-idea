extends SceneTree
## Task 6a dormant hash proof (spec docs/specs/emotions.md section 9.1 and 13 test 25; Q3 option (a)). NOT a unit test (it does
## not start with test_ and is not run by run_tests.gd): five 300-sol balance runs take minutes.
##
##   godot --headless --path station-zero --script res://tests/mood_hash_proof.gd [-- --seed N ...]
##
## For each seed it runs the Task 1 command (tests/balance_lib.gd run(seed, 300, params, 30)). When data/mood.json exists the
## run is DORMANT: the two behaviour gains are forced to 0.0 through the balance parameter overrides
## (`mood.effects.travel_coef`, `mood.effects.energy_coef`), so the proof keeps its meaning after the gains are switched on.
## It takes the table body exactly as age_hash_proof.body_of does and checks, in order:
##   check 0, "drop md":                delete the final field of the header and each row when the header's last field is `md`;
##                                      compare with EXPECTED_T5 below (the five Task 5 table hashes, copied from
##                                      docs/balance/task-5-log.md section "Task 5 table hash"; NOT read from another proof).
##   checks 1 to 3, the existing chain: council_hash_proof.proof_hashes on the stripped body: drop `cn` (Task 4, EXPECTED_T4),
##                                      then `web` (Task 3), then `age` (Task 1), each compared with the stored hash.
## A strip never removes a field whose header name is not `md`: when `md` is not the LAST field of the header the table is
## REFUSED (exit 1, "MISPLACED"). When there is no `md` column at all the report says ABSENT: today (before the module exists)
## ABSENT is the expected state and the proof then reduces to the Task 5 chain, which must pass (exit 0). Once the column
## exists it must say present, and every hash must still match. Exit 0 only when every requested seed matches all four.
## The helpers are static so tests/test_moods.gd (test 25) can check them on synthetic tables without a 300-sol run.

## Task 5 table hashes (full table with `cn` last), docs/balance/task-5-log.md lines 11 to 15 (first 16 hex digits of sha256).
const EXPECTED_T5 := {
	42: "330325504427720a",
	7: "1ceb89a7d3e87540",
	99: "7feb81cee7c86fa5",
	1234: "7c8bcf782a06f1fa",
	2026: "076e42c032a208aa",
}
const SOLS := 300
const EVERY := 30
const DORMANT_PARAMS := {"mood.effects.travel_coef": 0.0, "mood.effects.energy_coef": 0.0}


static func _chain() -> GDScript:
	return load("res://tests/council_hash_proof.gd")


static func _age_proof() -> GDScript:
	return load("res://tests/age_hash_proof.gd")


## "last" when the header's last field is `md`, "absent" when no field is named `md`, "misplaced" when `md` is in the header
## but not last (a reordered table never passes by accident).
static func md_state(body: Array) -> String:
	if body.is_empty():
		return "absent"
	var head: PackedStringArray = str(body[0]).split(" ", false)
	if head.size() > 0 and head[head.size() - 1] == "md":
		return "last"
	return "misplaced" if "md" in head else "absent"


## {body, state, md_absent}: deletes the final field (and the space before it) of the header and each row when the state is
## "last"; otherwise returns the body unchanged.
static func strip_md(body: Array) -> Dictionary:
	var state := md_state(body)
	var r: Dictionary = _chain().strip_last(body, "md") if state == "last" else {"body": body, "stripped": false}
	return {"body": r.body, "state": state, "md_absent": state == "absent"}


static func hash_of(body: Array) -> String:
	return _chain().hash_of(body)


## {md_state, check0, check1, check2, check3}: check0 is the full sha256 of the md-stripped table, checks 1 to 3 the chain
## (council_hash_proof.proof_hashes) of the same stripped table.
static func proof_hashes(lines: Array) -> Dictionary:
	var body: Array[String] = _age_proof().body_of(lines)
	var s := strip_md(body)
	var chain: Dictionary = _chain().proof_hashes(s.body)
	return {"md_state": s.state, "check0": hash_of(s.body), "check1": chain.check1, "check2": chain.check2,
			"check3": chain.check3}


func _init() -> void:
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var seeds: Array = []
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			i += 1
			seeds.append(int(args[i]))
		i += 1
	if seeds.is_empty():
		seeds = EXPECTED_T5.keys()
	var params: Dictionary = DORMANT_PARAMS.duplicate() if FileAccess.file_exists("res://data/mood.json") else {}
	var chain := _chain()
	var t4: Dictionary = chain.EXPECTED_T4
	var t3: Dictionary = chain.expected_t3()
	var t1: Dictionary = chain.expected_t1()
	var all_ok := true
	for s in seeds:
		var r: Dictionary = lib.run(int(s), SOLS, params, EVERY)
		var h := proof_hashes(r.lines)
		var want5: String = EXPECTED_T5.get(int(s), "")
		var want4: String = t4.get(int(s), "")
		var want3: String = t3.get(int(s), "")
		var want1: String = t1.get(int(s), "")
		var ok5 := want5 != "" and str(h.check0).begins_with(want5)
		var ok4 := want4 != "" and str(h.check1).begins_with(want4)
		var ok3 := want3 != "" and str(h.check2).begins_with(want3)
		var ok1 := want1 != "" and str(h.check3).begins_with(want1)
		var ok_md: bool = h.md_state != "misplaced"
		all_ok = all_ok and ok5 and ok4 and ok3 and ok1 and ok_md
		print("seed %d: md %s | drop md %s expected %s %s | drop cn %s expected %s %s | drop cn and web %s expected %s %s | drop cn, web and age %s expected %s %s" % [
				s, str(h.md_state).to_upper() if h.md_state != "last" else "present",
				str(h.check0).substr(0, 16), want5, "MATCH" if ok5 else "DIFFERENT",
				str(h.check1).substr(0, 16), want4, "MATCH" if ok4 else "DIFFERENT",
				str(h.check2).substr(0, 16), want3, "MATCH" if ok3 else "DIFFERENT",
				str(h.check3).substr(0, 16), want1, "MATCH" if ok1 else "DIFFERENT"])
	quit(0 if all_ok else 1)
