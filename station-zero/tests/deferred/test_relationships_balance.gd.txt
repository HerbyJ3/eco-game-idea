## DEFERRED (not run): the balance half of docs/specs/relationships.md section 14, parked in Task 4 step 3.
## MOVE BACK TO tests/test_relationships_balance.gd (rename, drop .txt) IN STEP 6 (balance integration: the trailing `web`
## column after `age`, verdict T11, `relationships` in data_hash). It needs balance_lib.run to print the column and a T11
## verdict, which do not exist before step 6, so it cannot pass earlier. (balance_lib.data_hash covering relationships.json
## is already tested in tests/test_relationships.gd test_t15c and goes green in step 4/6, whichever edits balance_lib.)
##
## API ASSUMED: balance_lib.run(seed, sols, {}, every) returns {lines, verdicts, world}; a verdict is {n, verdict, detail};
## T11 is the verdict with n == 11 and reads stats.relationships only (spec 14, Balance). The `web` column is the final
## whitespace-separated field of the table header and rows, two decimals, the latest `web_share` (spec 12).
##
## Cost: one 60-sol run (about 10 s) for the column and T11 shape; the 300-sol five-seed judgement is the balance log, not
## a unit test.

extends RefCounted

const SOLS := 60


func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func test_web_column_is_last_after_age_with_two_decimals(t) -> void:
	t._failures.append(_abort_msg(t))
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var P: GDScript = load("res://tests/age_hash_proof.gd")
	var r: Dictionary = lib.run(42, SOLS, {}, 30)
	var body: Array = P.body_of(r.lines)
	t.check(body.size() >= 3, "the table has a header and rows")
	var head: PackedStringArray = str(body[0]).split(" ", false)
	t.eq(head[head.size() - 1], "web", "the last header field is web")
	t.eq(head[head.size() - 2], "age", "and the one before it is age")
	for i in range(1, body.size()):
		var f: PackedStringArray = str(body[i]).split(" ", false)
		var v := f[f.size() - 1]
		t.check(v.is_valid_float() and v.length() - v.find(".") == 3, "row %d: web %s has two decimals" % [i, v])
	t.eq(float(body[body.size() - 1].split(" ", false)[-1]), snappedf(float(r.world.stats.relationships.web_share), 0.01),
			"the last row is the latest web_share")
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
	var judged_ok: bool = rs.web_by_sol.size() == rs.second_by_sol.size() and rs.web_by_sol.size() == rs.lonely_by_sol.size() \
			and wmean <= float(bal.lonely_share_max) and int(rs.lines_dropped) == 0 \
			and float(rs.friends_mean) >= float(SimData.load_json("relationships.json").balance.friends_mean_min) \
			and float(rs.friends_mean) <= float(SimData.load_json("relationships.json").balance.friends_mean_max) \
			and rs.first_friendship_sol != null
	if str(t11.get("verdict", "")) != "N/A":
		t.eq(t11.get("verdict"), "PASS" if judged_ok else "FAIL", "T11 agrees with the five conditions read from stats.relationships")
	t._failures.erase(_abort_msg(t))
