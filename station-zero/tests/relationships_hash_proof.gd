extends SceneTree
## Task 4 hash proof (spec docs/specs/relationships.md section 12). NOT a unit test (it does not start with test_ and is
## not run by run_tests.gd): five 300-sol balance runs take minutes.
##
##   godot --headless --path station-zero --script res://tests/relationships_hash_proof.gd [-- --seed N ...]
##
## For each seed it runs the Task 1 command (tests/balance_lib.gd run(seed, 300, {}, 30)), takes the table body exactly as
## age_hash_proof.body_of does, and computes two hashes (first 16 hex digits of sha256_text of the body joined with "\n"):
##   check 1, "drop web":          delete the final field of the header and each row when the header's last field is
##                                 `web`; compare with the Task 3 hash (EXPECTED_T3, docs/balance/task-3-log.md).
##   check 2, "drop web and age":  then delete the final field again when the header's last field is `age`; compare with
##                                 the Task 1 hash (age_hash_proof.EXPECTED, reused by reference).
## A strip never removes a field whose header name is not the expected one (`web`, then `age`): the column is reported
## ABSENT instead, so a reordered table cannot pass by accident. Before the module exists the `web` column is absent: check
## 1 then hashes the Task 3 table as it is (and must give the Task 3 values), and check 2 reduces to age_hash_proof.gd.
## Exit 0 only when every requested seed matches both. The helpers are static so tests/test_relationships.gd (test 17)
## can check them on synthetic tables.

## Task 3 table hashes (with the age column, balance run output), docs/balance/task-3-log.md line 30.
## pre-lifecycle baseline (Tasks 1-5), Task 3 table hashes, superseded by the calendar-lifecycle baseline (commit e1f2bdd; owner decision
## 2026-10-09, docs/balance/lifecycle-rebaseline.md). History only, not compared against:
##   42: "da166c4f8b202820",
##   7: "30c53f90949d979b",
##   99: "54ad1e15b934bf9a",
##   1234: "7052c92936a75157",
##   2026: "67e3dcf057200eb9",
## calendar-lifecycle baseline (commit e1f2bdd), Task 3-level table hashes, superseded by the water-throughput baseline
## (W3 commute without room pauses; owner decision 2026-10-09, docs/balance/water-rebaseline.md). History only:
##   42: "5c590177e627b03c",
##   7: "d9aead4bf953ad7e",
##   99: "6c0df749c1c1e7ec",
##   1234: "9ea6315f71b0c371",
##   2026: "798b786bae4905c1",
const EXPECTED_T3 := {
	42: "3a781ace17210e77",
	7: "d19831ca3d3a9282",
	99: "80407b975e346c1e",
	1234: "0cc6764008aed14f",
	2026: "11ff36bd5fe69349",
}
const SOLS := 300
const EVERY := 30


static func _age_proof() -> GDScript:
	return load("res://tests/age_hash_proof.gd")


## The task 1 hashes, by reference to age_hash_proof.gd.
static func expected_t1() -> Dictionary:
	return _age_proof().EXPECTED


## True when the table header's last whitespace-separated field is `name`.
static func has_last_column(body: Array, name: String) -> bool:
	if body.is_empty():
		return false
	var head: PackedStringArray = str(body[0]).split(" ", false)
	return head.size() > 0 and head[head.size() - 1] == name


## {body, stripped}: deletes the final whitespace-separated field (and the space before it) of the header and each row
## when the header's last field is `name`; otherwise returns the body unchanged with stripped false ("column absent").
static func strip_last(body: Array, name: String) -> Dictionary:
	var out: Array[String] = []
	var strip := has_last_column(body, name)
	for l in body:
		var s := str(l)
		if strip:
			var i := s.rfind(" ")
			s = s.substr(0, i) if i >= 0 else s
		out.append(s)
	return {"body": out, "stripped": strip}


## Check 1: {body, web_absent}.
static func drop_web(body: Array) -> Dictionary:
	var c := strip_last(body, "cn")  # Task 5 (spec council.md 9.1): the trailing `cn` column goes first when present
	var r := strip_last(c.body, "web")
	return {"body": r.body, "web_absent": not r.stripped}


## Check 2: {body, web_absent, age_absent}. `web` is stripped when present, then `age` when it is then the last field.
static func drop_web_and_age(body: Array) -> Dictionary:
	var c := strip_last(body, "cn")
	var w := strip_last(c.body, "web")
	var a := strip_last(w.body, "age")
	return {"body": a.body, "web_absent": not w.stripped, "age_absent": not a.stripped}


static func hash_of(body: Array) -> String:
	return "\n".join(PackedStringArray(body)).sha256_text()


## {check1, check2, web_absent, age_absent}: the two hashes (full sha256 hex) of a run's output lines.
static func proof_hashes(lines: Array) -> Dictionary:
	var body: Array[String] = _age_proof().body_of(lines)
	var c1 := drop_web(body)
	var c2 := drop_web_and_age(body)
	return {"check1": hash_of(c1.body), "check2": hash_of(c2.body), "web_absent": c1.web_absent,
			"age_absent": c2.age_absent}


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
		seeds = EXPECTED_T3.keys()
	var t1 := expected_t1()
	var all_ok := true
	for s in seeds:
		var r: Dictionary = lib.run(int(s), SOLS, {}, EVERY)
		var h := proof_hashes(r.lines)
		var want3: String = EXPECTED_T3.get(int(s), "")
		var want1: String = t1.get(int(s), "")
		var ok3 := want3 != "" and str(h.check1).begins_with(want3)
		var ok1 := want1 != "" and str(h.check2).begins_with(want1)
		all_ok = all_ok and ok3 and ok1
		print("seed %d: web %s, age %s | drop web %s expected %s %s | drop web and age %s expected %s %s" % [
				s, "ABSENT" if h.web_absent else "present", "ABSENT" if h.age_absent else "present",
				str(h.check1).substr(0, 16), want3, "MATCH" if ok3 else "DIFFERENT",
				str(h.check2).substr(0, 16), want1, "MATCH" if ok1 else "DIFFERENT"])
	quit(0 if all_ok else 1)
