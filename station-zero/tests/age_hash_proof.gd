extends SceneTree
## Task 3 hash proof (spec docs/specs/ages.md section 12). NOT a unit test (it does not start with test_ and is not
## run by run_tests.gd): five 300-sol balance runs take minutes. It is the balance-step check that the age work changed
## no behaviour.
##
##   godot --headless --path station-zero --script res://tests/age_hash_proof.gd [-- --seed N ...]
##
## For each seed it runs the Task 1 command (tests/balance_lib.gd run(seed, 300, {}, 30)), takes the table body (the
## lines after the two `#` header lines, up to the first blank line), removes the trailing `age` column when the header
## has one (the final whitespace-separated field of the header and of each row, with the space before it), hashes the
## body with String.sha256_text, and compares the first 16 hex digits with the Task 1 value in
## docs/balance/task-1-log.md. Exit 0 when every requested seed matches. The helper functions are static so
## tests/test_ages.gd can test them on synthetic tables without a 300-sol run.
##
## Run once before the age work (the real tree at the time of writing: the column does not exist, the strip is a no-op,
## and the Task 1 hashes must come out), and again after the column and hook exist: a differing hash means a behaviour
## change and the step is rejected.

## pre-lifecycle baseline (Tasks 1-5), Task 1 table hashes (no age/web/cn columns), superseded by the calendar-lifecycle baseline (commit e1f2bdd; owner decision
## 2026-10-09, docs/balance/lifecycle-rebaseline.md). History only, not compared against:
##   42: "02032b2388529913",
##   7: "830c7d0c441823f5",
##   99: "0e3e83a7108140ef",
##   1234: "bca6eb2ca93ba0c1",
##   2026: "2645033a417ec400",
const EXPECTED := {
	42: "f8750bee8424a3f1",
	7: "0491abf46338c256",
	99: "2463601427badf0b",
	1234: "86b199e697f98d0a",
	2026: "12ebeb75ad29220c",
}
const SOLS := 300
const EVERY := 30


## The table body of a run's output lines: everything after the `#` header lines up to the first blank line.
static func body_of(lines: Array) -> Array[String]:
	var out: Array[String] = []
	for l in lines:
		var s := str(l)
		if s.begins_with("#"):
			continue
		if s == "":
			break
		out.append(s)
	return out


## True when the table header's last whitespace-separated field is `age`.
static func has_age_column(body: Array) -> bool:
	if body.is_empty():
		return false
	var head: PackedStringArray = str(body[0]).split(" ", false)
	return head.size() > 0 and head[head.size() - 1] == "age"


## Deletes the final whitespace-separated field of the header and of each row, with the space before it. A body
## without the column is returned unchanged.
static func strip_age_column(body: Array) -> Array[String]:
	var out: Array[String] = []
	var strip := has_age_column(body)
	for l in body:
		var s := str(l)
		if strip:
			var i := s.rfind(" ")
			s = s.substr(0, i) if i >= 0 else s
		out.append(s)
	return out


## sha256_text of the stripped body joined with newlines (what balance_lib.gd hashes for a Task 1 run).
static func proof_hash(lines: Array) -> String:
	return "\n".join(strip_age_column(body_of(lines))).sha256_text()


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
		seeds = EXPECTED.keys()
	var all_ok := true
	for s in seeds:
		var r: Dictionary = lib.run(int(s), SOLS, {}, EVERY)
		var h := proof_hash(r.lines)
		var want: String = EXPECTED.get(int(s), "")
		var ok := want != "" and h.begins_with(want)
		all_ok = all_ok and ok
		print("seed %d: body sha256 %s (column %s) expected %s  %s" % [
				s, h.substr(0, 16), "present, stripped" if has_age_column(body_of(r.lines)) else "absent",
				want, "MATCH" if ok else "DIFFERENT"])
	quit(0 if all_ok else 1)
