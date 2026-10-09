## Balance half of docs/specs/relationships.md section 14 (moved in from tests/deferred in Task 4 step 6): the trailing
## `web` column after `age` (two decimals, the latest `web_share`, spec 12) and the T11 verdict, which reads
## stats.relationships only (spec 14, Balance). balance_lib.run(seed, sols, {}, every) returns {lines, verdicts, world}; a
## verdict is {n, verdict, detail}.
##
## Cost: two 60-sol runs (about 10 s each) for the column and T11 shape; the 300-sol five-seed judgement is the balance
## log (docs/balance/task-4-log.md), not a unit test.

extends RefCounted

const SOLS := 60


func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func test_web_column_is_last_after_age_with_two_decimals(t) -> void:
	# Task 5 (council.md 9.1): the trailing `cn` column now follows `web`; web keeps its place right after age.
	t._failures.append(_abort_msg(t))
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var P: GDScript = load("res://tests/age_hash_proof.gd")
	var r: Dictionary = lib.run(42, SOLS, {}, 30)
	var body: Array = P.body_of(r.lines)
	t.check(body.size() >= 3, "the table has a header and rows")
	var head: PackedStringArray = str(body[0]).split(" ", false)
	t.eq(head[head.size() - 1], "cn", "the last header field is cn")
	t.eq(head[head.size() - 2], "web", "web comes right before cn")
	t.eq(head[head.size() - 3], "age", "and the one before web is age")
	for i in range(1, body.size()):
		var f: PackedStringArray = str(body[i]).split(" ", false)
		var v := f[f.size() - 2]
		t.check(v.is_valid_float() and v.length() - v.find(".") == 3, "row %d: web %s has two decimals" % [i, v])
	t.eq(float(body[body.size() - 1].split(" ", false)[-2]), snappedf(float(r.world.stats.relationships.web_share), 0.01),
			"the last row's web is the latest web_share")
	t._failures.erase(_abort_msg(t))


func test_t11_is_judged_from_stats_relationships(t) -> void:
	t._failures.append(_abort_msg(t))
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var r: Dictionary = lib.run(42, SOLS, {}, 30)
	var t11 := {}
	for v in r.verdicts:
		if int(v.n) == 11:
			t11 = v
	t.check(not t11.is_empty(), "a T11 verdict is reported")
	t.check(str(t11.get("detail", "")) != "", "with a detail line")
	var rs: Dictionary = r.world.stats.relationships
	t.eq(rs.web_by_sol.size(), r.world.stats.pop_by_sol.size(), "(1) lists have the length of pop_by_sol")
	var bal: Dictionary = SimData.load_json("relationships.json").balance
	var lby: Array = rs.lonely_by_sol
	var win: Array = lby.slice(maxi(0, lby.size() - int(bal.lonely_window_sols)))
	var wmean := 0.0
	for v in win:
		wmean += float(v)
	wmean /= maxf(1.0, float(win.size()))
	# revision 6: (2) is the mean of the last lonely_window_sols readings; (5) no dropped events (total, while
	# lines_dropped_by_type is not built; then lines_dropped_by_type.friend == 0)
	t.check(not rs.has("lines_dropped_by_type"), "lines_dropped_by_type is not built, so (5) reads the total (update T11 and this test when it is)")
	var judged_ok: bool = rs.web_by_sol.size() == rs.second_by_sol.size() and rs.web_by_sol.size() == rs.lonely_by_sol.size() \
			and rs.web_by_sol.size() == r.world.stats.pop_by_sol.size() \
			and wmean <= float(bal.lonely_share_max) and int(rs.lines_dropped) == 0 \
			and float(rs.friends_mean) >= float(SimData.load_json("relationships.json").balance.friends_mean_min) \
			and float(rs.friends_mean) <= float(SimData.load_json("relationships.json").balance.friends_mean_max) \
			and rs.first_friendship_sol != null
	t.check(str(t11.get("verdict", "")) != "N/A", "T11 is judged, not N/A")
	t.eq(t11.get("verdict"), "PASS" if judged_ok else "FAIL", "T11 agrees with the five conditions read from stats.relationships")
	t._failures.erase(_abort_msg(t))
