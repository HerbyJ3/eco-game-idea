extends SceneTree
## Task 5 hash proof (spec docs/specs/council.md section 9). NOT a unit test (it does not start with test_ and is not run
## by run_tests.gd): five 300-sol balance runs take minutes.
##
##   godot --headless --path station-zero --script res://tests/council_hash_proof.gd [-- --seed N ...]
##
## For each seed it runs the Task 1 command (tests/balance_lib.gd run(seed, 300, {}, 30)), takes the table body exactly as
## age_hash_proof.body_of does, and computes three hashes (first 16 hex digits of sha256_text of the body joined with "\n"):
##   check 1, "drop cn":              delete the final field of the header and each row when the header's last field is
##                                    `cn`; compare with the Task 4 hash (EXPECTED_T4, docs/balance/task-4-log.md).
##   check 2, "drop cn and web":      then delete the final field again when the header's last field is `web`; compare with
##                                    the Task 3 hash (relationships_hash_proof.EXPECTED_T3, reused by reference).
##   check 3, "drop cn, web and age": then once more when the last field is `age`; compare with the Task 1 hash
##                                    (age_hash_proof.EXPECTED, reused by reference).
## A strip never removes a field whose header name is not the expected one (`cn`, then `web`, then `age`): the column is
## reported ABSENT instead, so a reordered or renamed table cannot pass by accident. Before the Council exists the `cn`
## column is absent: check 1 then hashes the Task 4 table as it is (and must give the Task 4 values), and the later checks
## reduce to relationships_hash_proof.gd. Exit 0 only when every requested seed matches all three. The helpers are static so
## tests/test_council.gd (test 18) can check them on synthetic tables.
##
## Note: the `age` column of the printed table becomes a projection (L for landing, S for any other age; spec 9.1). Stripping
## it removes that column in either form, so the Task 1 hash does not depend on the projection.

## Task 4 table hashes, docs/balance/task-4-log.md (table sha256, balance run output with the age and web columns).
## pre-lifecycle baseline (Tasks 1-5), Task 4 table hashes, superseded by the calendar-lifecycle baseline (commit e1f2bdd; owner decision
## 2026-10-09, docs/balance/lifecycle-rebaseline.md). History only, not compared against:
##   42: "a96b8a9562fd75d0",
##   7: "a4968e2fcc48ec36",
##   99: "2210719cf48d8612",
##   1234: "19437e397d1dff88",
##   2026: "6e7fe68477161196",
## calendar-lifecycle baseline (commit e1f2bdd), Task 4-level table hashes, superseded by the water-throughput baseline
## (W3 commute without room pauses; owner decision 2026-10-09, docs/balance/water-rebaseline.md). History only:
##   42: "5cae292b785e5de7",
##   7: "257dc2bda6b29981",
##   99: "d31bc86c094bcff4",
##   1234: "bc78b23075c71ef4",
##   2026: "f404077296a86f66",
## water-throughput baseline (W3), Task 4-level table hashes, superseded by the bed-walk fix (Being.sleep_target_id;
## docs/balance/water-rebaseline.md, section Bed-walk fix). History only:
##   42: "6007d885aa1974ac",
##   7: "cadbd65b8bffdb9c",
##   99: "40d46838bb39aee5",
##   1234: "55c479815f1f47ac",
##   2026: "27b48573b9aed8e2",
const EXPECTED_T4 := {
	42: "54e0b17c2b95a97e",
	7: "58c9704fa00c26fc",
	99: "5d007db82e1a61bf",
	1234: "88802cc94428993e",
	2026: "4e6b1638a49280fe",
}
const SOLS := 300
const EVERY := 30


static func _age_proof() -> GDScript:
	return load("res://tests/age_hash_proof.gd")


static func _rel_proof() -> GDScript:
	return load("res://tests/relationships_hash_proof.gd")


## The Task 3 hashes, by reference to relationships_hash_proof.gd.
static func expected_t3() -> Dictionary:
	return _rel_proof().EXPECTED_T3


## The Task 1 hashes, by reference to age_hash_proof.gd.
static func expected_t1() -> Dictionary:
	return _age_proof().EXPECTED


## True when the table header's last whitespace-separated field is `name`.
static func has_last_column(body: Array, name: String) -> bool:
	if body.is_empty():
		return false
	var head: PackedStringArray = str(body[0]).split(" ", false)
	return head.size() > 0 and head[head.size() - 1] == name


## {body, stripped}: deletes the final whitespace-separated field (and the space before it) of the header and each row when
## the header's last field is `name`; otherwise returns the body unchanged with stripped false ("column absent").
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


## Check 1: {body, cn_absent}.
static func drop_cn(body: Array) -> Dictionary:
	var r := strip_last(body, "cn")
	return {"body": r.body, "cn_absent": not r.stripped}


## Check 2: {body, cn_absent, web_absent}. `cn` is stripped when present, then `web` when it is then the last field.
static func drop_cn_web(body: Array) -> Dictionary:
	var c := strip_last(body, "cn")
	var w := strip_last(c.body, "web")
	return {"body": w.body, "cn_absent": not c.stripped, "web_absent": not w.stripped}


## Check 3: {body, cn_absent, web_absent, age_absent}. Then `age` when it is the last field.
static func drop_cn_web_age(body: Array) -> Dictionary:
	var c := strip_last(body, "cn")
	var w := strip_last(c.body, "web")
	var a := strip_last(w.body, "age")
	return {"body": a.body, "cn_absent": not c.stripped, "web_absent": not w.stripped, "age_absent": not a.stripped}


static func hash_of(body: Array) -> String:
	return "\n".join(PackedStringArray(body)).sha256_text()


## {check1, check2, check3, cn_absent, web_absent, age_absent}: the three hashes (full sha256 hex) of a run's output lines.
static func proof_hashes(lines: Array) -> Dictionary:
	var body: Array[String] = _age_proof().body_of(lines)
	var c1 := drop_cn(body)
	var c2 := drop_cn_web(body)
	var c3 := drop_cn_web_age(body)
	return {"check1": hash_of(c1.body), "check2": hash_of(c2.body), "check3": hash_of(c3.body),
			"cn_absent": c1.cn_absent, "web_absent": c2.web_absent, "age_absent": c3.age_absent}


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
		seeds = EXPECTED_T4.keys()
	var t3 := expected_t3()
	var t1 := expected_t1()
	var all_ok := true
	for s in seeds:
		var r: Dictionary = lib.run(int(s), SOLS, {}, EVERY)
		var h := proof_hashes(r.lines)
		var want4: String = EXPECTED_T4.get(int(s), "")
		var want3: String = t3.get(int(s), "")
		var want1: String = t1.get(int(s), "")
		var ok4 := want4 != "" and str(h.check1).begins_with(want4)
		var ok3 := want3 != "" and str(h.check2).begins_with(want3)
		var ok1 := want1 != "" and str(h.check3).begins_with(want1)
		all_ok = all_ok and ok4 and ok3 and ok1
		print("seed %d: cn %s, web %s, age %s | drop cn %s expected %s %s | drop cn and web %s expected %s %s | drop cn, web and age %s expected %s %s" % [
				s, "ABSENT" if h.cn_absent else "present", "ABSENT" if h.web_absent else "present",
				"ABSENT" if h.age_absent else "present",
				str(h.check1).substr(0, 16), want4, "MATCH" if ok4 else "DIFFERENT",
				str(h.check2).substr(0, 16), want3, "MATCH" if ok3 else "DIFFERENT",
				str(h.check3).substr(0, 16), want1, "MATCH" if ok1 else "DIFFERENT"])
	quit(0 if all_ok else 1)
