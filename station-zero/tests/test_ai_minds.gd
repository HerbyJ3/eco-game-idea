extends "res://tests/minds_lib.gd"
## Task 6b, step 3 (tests first, red): sim-side AI minds tests, SLICE 1. Spec: docs/specs/ai-minds.md revision 6 (revision 4 was APPROVED by
## the code-reviewer; the revision 6 review fixes are in), section 14 tests 4 to 10, 21 (data parity), 32 to 37, 39, 40 and the perf test 30. The rest live in:
##   tests/test_ai_minds_hashes.gd   tests 1 to 3 (five 300-sol seeds, heavy) and 31 (hash columns and the four proof scripts)
##   tests/test_ai_minds_replay.gd   tests 11 to 16 and 38 (ledger, replay, adversarial providers)
##   tests/test_ai_minds_voice.gd    tests 17 to 20 and 22 (rule voice, filter, source scans, the panel doors)
##   tests/test_ai_minds_driver.gd   tests 23 to 29 (budget, breaker, failure matrix, prompt, parser, deadline, mode)
## Shared staging and the list of API names the spec does not give: tests/minds_lib.gd. Slice 2 tests are present and SKIPPED
## with a reason (functions named test_s2_*; they record one check that states why, so the runner does not call them empty).
##
## Tick seam: `_mini(w)` is one fixed step as the sibling hook sees it (time, relationships accumulator, mood tick, minds hook);
## beings do not act, so a 10-sol schedule run is cheap. Behaviour is tested by calling Being.decide / _restless_travel with a
## scripted generator (as tests/test_moods.gd does for effect 1).
##
## Spec ambiguities met while writing are collected in the step 3 report; the ones that shaped a test are marked "AMBIGUITY".


# ---------------------------------------------------------------- 4. the slot schedule is pure

## Contiguous ids 1..n spread over four rooms; returns the ids.
func _populate(w, n: int) -> Array:
	var rooms := [HAB, WORK, GREEN, COMMS]
	var ids: Array = []
	for i in n:
		ids.append(_being(w, rooms[i % 4]).id)
	return ids


## Runs the tick seam through sols first_sol..last_sol and records every relationships tick: {sol, cell, opened}, plus the
## per-sol per-being opened counts. Starts counting at the first tick of first_sol (a sol the run entered by itself, so the
## real tick-to-cell drift of the world is what is measured; the world starts 0.25 sol in, so sol 1 is never counted).
func _schedule_run(w, ids: Array, first_sol: int, last_sol: int) -> Dictionary:
	_mini_to_sol(w, first_sol)
	var ticks: Array = []
	var per_being := {}
	var seen: int = int(w.relationships.ticks)
	var prev := {}
	for id in ids:
		prev[id] = 0
	for b in w.beings:
		prev[b.id] = int(b.mind_slot_n)
	var guard := 0
	while _sol(w) <= last_sol and guard < 400000:
		_mini(w)
		guard += 1
		if int(w.relationships.ticks) == seen:
			continue
		seen = int(w.relationships.ticks)
		var sol := _sol(w)
		if sol > last_sol:
			break
		var opened := 0
		for b in w.beings:
			var d: int = int(b.mind_slot_n) - int(prev[b.id])
			prev[b.id] = int(b.mind_slot_n)
			if d != 0:
				opened += d
				if not per_being.has(sol):
					per_being[sol] = {}
				per_being[sol][b.id] = int(per_being[sol].get(b.id, 0)) + d
		ticks.append({"sol": sol, "cell": _tick_cell(w), "opened": opened})
	return {"ticks": ticks, "per_being": per_being}


func _check_schedule(t, w, ids: Array, per_sol: int, first_sol: int, last_sol: int, label: String) -> void:
	var cap: int = int(_md().sim.max_slots_per_tick)
	var r := _schedule_run(w, ids, first_sol, last_sol)
	var by_sol := {}
	for tk in r.ticks:
		if not by_sol.has(tk.sol):
			by_sol[tk.sol] = []
		by_sol[tk.sol].append(tk)
	for sol in range(first_sol, last_sol + 1):
		var list: Array = by_sol.get(sol, [])
		t.check(list.size() == 24 or list.size() == 25, "%s sol %d: 24 or 25 ticks, got %d" % [label, sol, list.size()])
		var cell_count := {}
		for tk in list:
			cell_count[tk.cell] = int(cell_count.get(tk.cell, 0)) + 1
		var once := true
		for c in 24:
			once = once and int(cell_count.get(c, 0)) == 1
		t.check(once, "%s sol %d: every cell 0 to 23 sees exactly one tick" % [label, sol])
		if list.size() == 25:
			t.eq(int(list[24].cell), 24, "%s sol %d: the 25th tick is cell 24" % [label, sol])
			t.eq(int(list[24].opened), 0, "%s sol %d: cell 24 opens no calm slot (no carry-over here)" % [label, sol])
		for tk in list:
			var want := _demand(w, ids, sol, int(tk.cell), per_sol)
			t.eq(int(tk.opened), want, "%s sol %d cell %d: opened equals the independent schedule" % [label, sol, int(tk.cell)])
			t.check(int(tk.opened) <= cap, "%s: never more than max_slots_per_tick (%d) a tick" % [label, cap])
		var pb: Dictionary = r.per_being.get(sol, {})
		var exact := true
		for id in ids:
			exact = exact and int(pb.get(id, 0)) == per_sol
		t.check(exact, "%s sol %d: every being opened exactly slot.per_sol (%d) calm slots" % [label, sol, per_sol])


func test_t04a_schedule_is_pure_within_capacity(t) -> void:
	if not _api(t):
		return
	for per_sol in [1, 2]:
		_cfg_edit("minds.json", ["slot", "per_sol"], per_sol)
		var w = _world("rules", 1, false)
		var ids := _populate(w, 48)
		_check_schedule(t, w, ids, per_sol, 3, 12, "pop 48 per_sol %d" % per_sol)
		t.check(int(_stat(w, "slots_opened").calm) >= 48 * per_sol * 10, "stats.minds.slots_opened.calm counts at least the ten counted sols")
		_restore()
	_end(t)


func test_t04b_schedule_at_pop_160_with_the_shipped_cap(t) -> void:
	if not _api(t):
		return
	var w = _world("rules", 1, false)
	var ids := _populate(w, 160)
	t.eq(int(_md().sim.max_slots_per_tick), 8, "the shipped cap is 8")
	_check_schedule(t, w, ids, 1, 3, 12, "pop 160")
	# Contiguous ids: id * 7919 steps down one cell per id, so 160 beings put 6 or 7 in a cell, never over 8.
	var per_cell := {}
	for id in ids:
		var c := _cell_of(w, int(id), 3, 0, 1)
		per_cell[c] = int(per_cell.get(c, 0)) + 1
	var worst := 0
	for c in per_cell:
		worst = maxi(worst, int(per_cell[c]))
	t.check(worst <= 8, "staged ids 1..160 never stack more than 8 beings in one cell (%d)" % worst)
	_end(t)


func test_t04c_over_capacity_drops_are_counted_and_the_books_balance(t) -> void:
	if not _api(t):
		return
	_cfg_edit("minds.json", ["sim", "max_slots_per_tick"], 4)
	var w = _world("rules", 1, false)
	var ids := _populate(w, 160)
	_mini_to_first_tick_of(w, 3)  # drops the leftovers of sol 2 and opens cell 0 of sol 3
	var o0: int = int(_stat(w, "slots_opened").calm)
	var d0: int = int(_stat(w, "slot_dropped_carry"))
	var p0: int = w.minds.pending_open.size()
	var demand := 0
	var seen: int = int(w.relationships.ticks)
	var guard := 0
	while guard < 400000:
		_mini(w)
		guard += 1
		if int(w.relationships.ticks) != seen:
			seen = int(w.relationships.ticks)
			demand += _demand(w, ids, _sol(w), _tick_cell(w), 1)
			if _sol(w) >= 13:
				break
	var opened: int = int(_stat(w, "slots_opened").calm) - o0
	var dropped: int = int(_stat(w, "slot_dropped_carry")) - d0
	var pending: int = w.minds.pending_open.size() - p0
	t.check(dropped > 0, "with the cap lowered to 4 at pop 160 some calm slots are dropped (%d)" % dropped)
	t.eq(opened + dropped + pending, demand, "books: opened + dropped + still pending = demand (%d + %d + %d)" % [opened, dropped, pending])
	_end(t)


func _next_tick_cell(w) -> Array:
	# [sol, cell] of the relationships tick the NEXT mini-step would produce, or [] when it will not be a tick.
	if float(w.relationships.acc_h) + w.fixed_step < _tickh() - SimWorld.STEP_EPS:
		return []
	var tn: float = w.t + w.fixed_step
	var sol: int = int(w.clock.sol_index(tn))
	return [sol, int(floor((tn - float(sol - 1) * _sol_h(w)) / _grid(w) + SimWorld.STEP_EPS))]


## Mini-steps until the next step is a tick whose cell satisfies `pred` (Callable [sol, cell] -> bool).
func _until_next_tick(w, pred: Callable) -> bool:
	var guard := 0
	while guard < 100000:
		var nx := _next_tick_cell(w)
		if not nx.is_empty() and pred.call(nx[0], nx[1]):
			return true
		_mini(w)
		guard += 1
	return false


func test_t04d_events_skip_the_calm_slot_and_the_skip_is_counted(t) -> void:
	if not _api(t):
		return
	var w = _world("rules", 1, true)
	var ids := _populate(w, 24)
	_mini_to_sol(w, 3)
	var x = w.beings[5]
	# A tick at which x's calm cell is due: a grief why set just before it opens an event slot and the calm slot is skipped.
	var due_cell := func(sol: int, cell: int) -> bool: return _cell_of(w, int(x.id), sol, 0, 1) == cell
	t.check(_until_next_tick(w, due_cell), "a tick at x's calm cell is reached")
	var n0: int = int(x.mind_slot_n)
	var s0: int = int(_stat(w, "calm_skipped_event"))
	var e0: int = int(_stat(w, "slots_opened").event)
	_why(x, "grief", w.t, 99, "Gone-99")
	_mini_ticks(w, 1)
	t.eq(int(x.mind_slot_n), n0 + 1, "exactly one slot opened for x on that tick (event, not event + calm)")
	t.eq(int(_stat(w, "slots_opened").event), e0 + 1, "one event slot")
	t.eq(int(_stat(w, "calm_skipped_event")), s0 + 1, "the skipped calm slot is counted")
	var ds := _due_of(w, int(x.id))
	t.check(not ds.is_empty() and str(ds[ds.size() - 1].kind) == "event", "the due entry is of kind event")
	# A tick at which y's calm cell is NOT due: the event opens and nothing is skipped.
	var y = w.beings[9]
	var not_due := func(sol: int, cell: int) -> bool: return _cell_of(w, int(y.id), sol, 0, 1) != cell and cell < 24
	t.check(_until_next_tick(w, not_due), "a tick away from y's calm cell is reached")
	var s1: int = int(_stat(w, "calm_skipped_event"))
	var e1: int = int(_stat(w, "slots_opened").event)
	_why(y, "friend", w.t, 3, "Pax-3")
	_mini_ticks(w, 1)
	t.eq(int(_stat(w, "slots_opened").event), e1 + 1, "y's event slot opens")
	t.eq(int(_stat(w, "calm_skipped_event")), s1, "no calm slot was due, so nothing is counted as skipped")
	_end(t)


func test_t04e_babies_and_the_dead_never_open_slots(t) -> void:
	if not _api(t):
		return
	var w = _world("rules", 1, false)
	var ids := _populate(w, 24)
	var baby = _young(w, HAB, true)
	var dead = _being(w, HAB)
	w._kill(dead, "other")
	t.eq(str(w.lifecycle.stage(baby, w.t)), "baby", "the staged being is a baby")
	_mini_to_sol(w, 4)
	_mini(w, _sol_steps(1.0) + 40)  # one whole sol and a little: every adult's calm cell has come round
	t.eq(int(baby.mind_slot_n), 0, "a baby opens no slot in a sol")
	t.eq(int(dead.mind_slot_n), 0, "a dead being opens no slot")
	var without_slot := 0
	for b in w.beings:
		if int(b.id) in ids and int(b.mind_slot_n) == 0:
			without_slot += 1
	t.eq(without_slot, 0, "every one of the %d adults in the same run did open a slot" % ids.size())
	t.check(int(_stat(w, "slots_opened").calm) >= ids.size(), "and stats.minds.slots_opened.calm counts at least one per adult")
	_end(t)


# ---------------------------------------------------------------- 5. facts

func test_t05a_facts_are_deterministic_and_complete(t) -> void:
	if not _api(t):
		return
	var c1 := _cast("rules", 3)
	var c2 := _cast("rules", 3)
	var f1: Dictionary = c1.w.minds.facts_for(c1.w, c1.s)
	var f2: Dictionary = c2.w.minds.facts_for(c2.w, c2.s)
	t.eq(JSON.stringify(f1), JSON.stringify(f2), "two builds of the same world give equal facts")
	for k in ["self", "dossier", "mood", "place", "near", "bonds", "clock", "need", "colony", "god", "menu"]:
		t.check(f1.has(k), "facts carry `%s`" % k)
	t.eq(str(f1.get("god", {}).get("last", "")), "none", "god.last is `none` (no god-power source exists yet)")
	var bands: Dictionary = f1.get("dossier", {}).get("bands", f1.get("dossier", {}))
	for k in ["drive", "curiosity", "sociability", "care", "restless", "steady"]:
		t.check(f1.get("dossier", {}).has(k) or bands.has(k), "dossier carries the trait band `%s`" % k)
	_end(t)


func test_t05b_no_chart_words_in_200_generated_facts(t) -> void:
	if not _api(t):
		return
	var banned: Array[String] = ["deimos", "moon", "phobos", "chart"]
	for s in SimData.signs():
		banned.append(str(s.name).to_lower())
	var count := 0
	var bad: Array[String] = []
	var seed_i := 1
	while count < 200 and seed_i < 40:
		var w = SimWorld.new(seed_i, {"minds_mode": "rules"})
		for b in w.beings:
			var f: Dictionary = w.minds.facts_for(w, b)
			var strs: Array = []
			_all_strings(f, strs)
			for s in strs:
				var low := str(s).to_lower()
				for word in banned:
					if low.contains(word):
						bad.append("%s in %s" % [word, low.substr(0, 60)])
			count += 1
		seed_i += 1
	t.check(count >= 200, "200 generated beings were examined (%d)" % count)
	t.check(bad.is_empty(), "no sign name, sign index word, deimos, moon, phobos or chart in any key or value; first: %s" % (bad[0] if not bad.is_empty() else ""))
	_end(t)


# ---------------------------------------------------------------- 6. the menu

func test_t06a_slice1_menu_order_and_contents(t) -> void:
	if not _api(t):
		return
	var c := _cast("llm")
	var w = c.w
	var f3 = _being(w, ISO, "Lio-30")
	_friends(w, c.s.id, f3.id)
	var m: Array = w.minds.menu_for(w, c.s)
	t.eq(str(m[0]), "carry_on", "carry_on is first")
	var vis: Array = []
	for k in m:
		if str(k).begins_with("visit:"):
			vis.append(int(str(k).split(":")[1]))
	t.eq(vis.size(), 2, "two visit entries (both friends in neighbouring rooms)")
	t.check(str(m[1]).begins_with("visit:") and str(m[2]).begins_with("visit:"), "visit entries come immediately after carry_on")
	t.check(c.f1.id in vis and c.f2.id in vis, "the targets are the friends in neighbouring finished buildings")
	t.check(not (f3.id in vis), "a friend in a room that is not a neighbour is not offered")
	t.check(not (c.x.id in vis), "a non-friend neighbour is not offered under `visit`")
	t.check("stay" in m, "stay is offered to a being inside a building")
	t.check(m.size() <= int(_md().menu.max), "at most menu.max entries")
	var uniq := {}
	var all_strings := true
	for k in m:
		uniq[str(k)] = true
		all_strings = all_strings and k is String
	t.eq(uniq.size(), m.size(), "no option key is listed twice")
	t.check(all_strings, "the menu is a list of option-key Strings")
	_end(t)


func test_t06b_visit_prefers_the_longest_unseen_then_the_highest_bond(t) -> void:
	if not _api(t):
		return
	var c := _cast("llm")
	var w = c.w
	var f4 = _being(w, COMMS, "Mio-31")
	# Staged so that neither a lowest-id rule nor a highest-bond-first rule can produce the expected first entry:
	# f2 (not the lowest id) is the longest unseen with the LOWEST bond; f4 has the highest bond and the highest id.
	_friends(w, c.s.id, f4.id, 0.95)
	w.relationships.debug_set_bond(c.s.id, c.f2.id, 0.5)
	w.relationships.debug_set_bond(c.s.id, c.f1.id, 0.6)
	t.check(c.f1.id < c.f2.id and c.f2.id < f4.id, "precondition: ids rise f1 < f2 < f4")
	w.minds.last_visit_t[c.s.id] = {c.f1.id: 50.0, c.f2.id: 5.0, f4.id: 60.0}
	var m: Array = w.minds.menu_for(w, c.s)
	t.eq(str(m[1]), "visit:%d" % c.f2.id, "the longest-unseen friend (smallest last_visit_t) is first, though it is neither the lowest id nor the highest bond")
	t.eq(str(m[2]), "visit:%d" % f4.id, "the second is the highest-bond other friend")
	t.eq(m.filter(func(k): return str(k).begins_with("visit:")).size(), int(_md().menu.visit_max), "menu.visit_max (2) holds with three candidates")
	# Never visited counts as the oldest: f2 has no record at all while f4 has the smallest recorded time.
	w.minds.last_visit_t[c.s.id] = {c.f1.id: 50.0, f4.id: 6.0}
	m = w.minds.menu_for(w, c.s)
	t.eq(str(m[1]), "visit:%d" % c.f2.id, "a never-visited friend counts as the oldest (older than the smallest recorded time)")
	t.eq(str(m[2]), "visit:%d" % f4.id, "and the highest-bond other friend follows")
	_end(t)


## The pure tie key of spec 5.3, written out independently of the code under test.
func _tie_key(id: int, sol: int) -> int:
	var s: Dictionary = _md().slot
	return (id * int(s.cell_mult) + sol * int(s.cell_step)) % int(s.tie_mod)


## The id with the smallest pure tie key (then the lowest id) among `ids`.
func _tie_winner(ids: Array, sol: int) -> int:
	var winner := int(ids[0])
	for id in ids:
		var ka := _tie_key(int(id), sol)
		var kw := _tie_key(winner, sol)
		if ka < kw or (ka == kw and int(id) < winner):
			winner = int(id)
	return winner


## Stages a cast and enough extra friends (all with the same last_visit_t) that the shipped tie key disagrees with plain id order;
## returns {c, ids (friend ids), winner (smallest key, then lowest id), lowest (lowest id)}.
func _tie_cast() -> Dictionary:
	var c := _cast("llm")
	var w = c.w
	var rooms := [WORK, GREEN, COMMS]
	var ids: Array = [int(c.f1.id), int(c.f2.id)]
	var sol := _sol(w)
	var winner := _tie_winner(ids, sol)
	var tries := 0
	while winner == int(ids.min()) and tries < 14:
		var extra = _being(w, rooms[tries % 3])
		_friends(w, c.s.id, extra.id)
		ids.append(int(extra.id))
		winner = _tie_winner(ids, sol)
		tries += 1
	var lv := {}
	for id in ids:
		lv[int(id)] = 10.0
	w.minds.last_visit_t[c.s.id] = lv
	return {"c": c, "ids": ids, "winner": winner, "lowest": int(ids.min())}


func test_t06c_ties_go_by_the_pure_key_then_the_lowest_id(t) -> void:
	if not _api(t):
		return
	# Ascending: the smaller pure tie key goes first, then the lower id (spec 5.3, revision 5 decision 2). The staged ids are
	# chosen (more friends are added until it holds) so that the key winner is NOT the lowest id: an id-order implementation fails.
	var r := _tie_cast()
	var w = r.c.w
	t.check(int(r.winner) != int(r.lowest), "precondition: the lowest tie key is not the lowest id (winner %d, lowest id %d)" % [int(r.winner), int(r.lowest)])
	var m: Array = w.minds.menu_for(w, r.c.s)
	t.eq(str(m[1]), "visit:%d" % int(r.winner), "equal last_visit_t: the lowest pure tie key goes first, not the lowest id")
	var n_friends: int = (r.ids as Array).size()
	var winner_shipped: int = int(r.winner)
	# The final tiebreak: with slot.tie_mod 1 every key is 0, so the order falls to the lowest id.
	_cfg_edit("minds.json", ["slot", "tie_mod"], 1)
	var c := _cast("llm")
	var rooms := [WORK, GREEN, COMMS]
	var ids: Array = [int(c.f1.id), int(c.f2.id)]
	for i in n_friends - 2:
		var extra = _being(c.w, rooms[i % 3])
		_friends(c.w, c.s.id, extra.id)
		ids.append(int(extra.id))
	var lv := {}
	for id in ids:
		lv[int(id)] = 10.0
	c.w.minds.last_visit_t[c.s.id] = lv
	var m2: Array = c.w.minds.menu_for(c.w, c.s)
	t.eq(str(m2[1]), "visit:%d" % int(ids.min()), "all keys equal (tie_mod 1): the lowest id goes first")
	t.check(int(ids.min()) != winner_shipped, "and that is not the entry the shipped key would pick")
	_end(t)


func test_t06d_validity_stay_children_dead_and_purity(t) -> void:
	if not _api(t):
		return
	var c := _cast("llm")
	var w = c.w
	var m0: Array = w.minds.menu_for(w, c.s)
	var m1: Array = w.minds.menu_for(w, c.s)
	t.eq(m0, m1, "the menu is a pure function (two calls equal)")
	t.eq(int(c.s.mind_slot_n), 0, "building a menu opens no slot")
	c.s.state = "eva"
	t.check(not ("stay" in w.minds.menu_for(w, c.s)), "stay is not offered outside a building")
	c.s.state = "idle"
	_kill_being(w, c.f1)
	var m2: Array = w.minds.menu_for(w, c.s)
	t.check(not m2.any(func(k): return str(k) == "visit:%d" % c.f1.id), "a dead friend is not offered")
	# Young beings (revision 5, 5.3): toddler, child and teen all get a carry_on-only menu, even with friends around.
	for stage in ["toddler", "child", "teen"]:
		var kid = _young(w, HAB, false, stage)
		t.eq(str(w.lifecycle.stage(kid, w.t)), stage, "staged being is a %s" % stage)
		_friends(w, kid.id, c.f2.id)
		var mk: Array = w.minds.menu_for(w, kid)
		t.eq(mk, ["carry_on"], "a %s's menu is carry_on only" % stage)
	_end(t)


func _kill_being(w, b) -> void:
	w._kill(b, "other")


# ---------------------------------------------------------------- 7. apply validation

func _rejected_total(w) -> int:
	var n := 0
	for k in w.stats.minds.rejected:
		n += int(w.stats.minds.rejected[k])
	return n


func _assert_rejected_whole(t, w, b, reason: String, label: String, before: Dictionary) -> void:
	t.eq(_rej(w, reason), int(before.get(reason, 0)) + 1, "%s: counter `%s` +1" % [label, reason])
	t.eq(_rejected_total(w), int(before.total) + 1, "%s: exactly one rejection counted" % label)
	t.check(b.mind_bias == null, "%s: no bias set" % label)
	t.eq(w.minds.ledger.size(), 0, "%s: nothing in the ledger" % label)
	t.eq(str(w.minds.says.get(int(b.id), {}).get("source", "")), "rule", "%s: the line is the rule answer" % label)
	t.eq(int(_stat(w, "applied_model")), 0, "%s: nothing applied" % label)


func _snap(w) -> Dictionary:
	return {"total": _rejected_total(w), "bad_key": _rej(w, "bad_key"), "not_in_menu": _rej(w, "not_in_menu"),
			"stale_target": _rej(w, "stale_target"), "dead": _rej(w, "dead")}


func test_t07a_whole_entry_rejections(t) -> void:
	if not _api(t):
		return
	# unknown key
	var c := _cast("llm")
	var d := _open_slot(c.w, c.s)
	var before := _snap(c.w)
	_deliver(c.w, c.s.id, d.k, "teleport")
	_resolve(c.w, c.s.id, d.k)
	_assert_rejected_whole(t, c.w, c.s, "bad_key", "unknown key", before)
	# a known key that is not in the menu stored at open (the stranger is not a friend)
	c = _cast("llm")
	d = _open_slot(c.w, c.s)
	before = _snap(c.w)
	_deliver(c.w, c.s.id, d.k, "visit:%d" % c.x.id)
	_resolve(c.w, c.s.id, d.k)
	_assert_rejected_whole(t, c.w, c.s, "not_in_menu", "key not in the stored menu", before)
	# stale target: moved away, died, unfriended (one world each)
	for how in ["moved", "died", "unfriended"]:
		c = _cast("llm")
		d = _open_slot(c.w, c.s)
		var tgt: int = d.menu[1].split(":")[1].to_int() if str(d.menu[1]).begins_with("visit:") else c.f1.id
		var tb = c.f1 if tgt == c.f1.id else c.f2
		_deliver(c.w, c.s.id, d.k, "visit:%d" % tgt)
		match how:
			"moved":
				tb.building_id = ISO
			"died":
				_kill_being(c.w, tb)
			"unfriended":
				c.w.relationships.debug_set_bond(c.s.id, tgt, 0.0)
				c.w.relationships.debug_set_bond(c.s.id, tgt, 0.0)
		before = _snap(c.w)
		_resolve(c.w, c.s.id, d.k)
		_assert_rejected_whole(t, c.w, c.s, "stale_target", "stale target (%s)" % how, before)
	# dead being: dies between open and deadline; the due entry resolves as rejected `dead`
	c = _cast("llm")
	d = _open_slot(c.w, c.s)
	_deliver(c.w, c.s.id, d.k, "stay")
	_kill_being(c.w, c.s)
	before = _snap(c.w)
	_resolve(c.w, c.s.id, d.k)
	t.eq(_rej(c.w, "dead"), int(before.dead) + 1, "dead being: counter `dead` +1")
	t.eq(c.w.minds.ledger.size(), 0, "dead being: nothing in the ledger")
	t.check(not c.w.minds.says.has(int(c.s.id)), "dead being: no line remains")
	# Young beings (revision 5, 5.4 step 2): the stored menu is carry_on only, so any other choice fails as `not_in_menu`
	# (the `child` reason no longer exists). A toddler and a teen are young beings like the child.
	for stage in ["toddler", "child", "teen"]:
		c = _cast("llm")
		var kid = _young(c.w, HAB, false, stage)
		d = _open_slot(c.w, kid)
		before = _snap(c.w)
		_deliver(c.w, kid.id, d.k, "stay")
		_resolve(c.w, kid.id, d.k)
		t.eq(_rejected_total(c.w), int(before.total) + 1, "%s: the whole entry is rejected (one counter moved)" % stage)
		t.eq(_rej(c.w, "not_in_menu"), int(before.not_in_menu) + 1, "%s: reason not_in_menu" % stage)
		t.check(not c.w.stats.minds.rejected.has("child"), "%s: there is no `child` rejection reason" % stage)
		t.check(kid.mind_bias == null and c.w.minds.ledger.size() == 0, "%s: no bias, nothing logged" % stage)
	# SLICE 2 (not tested here): `no_neighbour` is reachable only for roam/quiet; a slice-1 menu has no entry whose validity is
	# "has a neighbour", and a visit that lost its neighbours is `stale_target`. See test_s2_t07_no_neighbour below.
	_end(t)


func _remark_case(t, label: String, say: String, extra: Dictionary, expect_kept: bool) -> void:
	var c := _cast("llm")
	var w = c.w
	var d := _open_slot(w, c.s)
	var rej0: int = int(_stat(w, "say_rejected"))
	_deliver(w, c.s.id, d.k, "stay", say, extra)
	_resolve(w, c.s.id, d.k)
	var line: Dictionary = w.minds.says.get(int(c.s.id), {})
	var intents: Array = _mt().intent.stay
	t.check(c.s.mind_bias != null and str(c.s.mind_bias.kind) == "stay", "%s: the choice is applied (bias stay)" % label)
	t.eq(str(line.get("source", "")), "model", "%s: source is model (the decision was the model's)" % label)
	t.eq(w.minds.ledger.size(), 1, "%s: one ledger entry" % label)
	if expect_kept:
		t.eq(int(_stat(w, "say_rejected")), rej0, "%s: remark kept, nothing counted" % label)
		var txt := str(line.get("text", ""))
		t.check(txt.begins_with(say + " "), "%s: the line starts with the remark" % label)
		t.check(intents.any(func(i): return txt.ends_with(str(i))), "%s: and ends with the sim's intent phrase" % label)
		t.check(txt.length() <= int(_md().say.total_max_chars), "%s: within say.total_max_chars" % label)
		t.eq(str(w.minds.ledger[0].say), say, "%s: the ledger holds the remark" % label)
	else:
		t.eq(int(_stat(w, "say_rejected")), rej0 + 1, "%s: say_rejected +1" % label)
		t.check(intents.has(str(line.get("text", ""))), "%s: the displayed line is the intent phrase alone" % label)
		t.eq(str(w.minds.ledger[0].say), "", "%s: the ledger holds an empty say" % label)


func test_t07b_a_bad_remark_keeps_the_choice(t) -> void:
	if not _api(t):
		return
	_remark_case(t, "too long", "x".repeat(int(_md().say.max_chars) + 1), {}, false)
	_remark_case(t, "stray digit", "I counted 3 lights tonight.", {}, false)
	_remark_case(t, "disallowed name", "Qua-77 seems well today.", {}, false)
	_remark_case(t, "digit glued to an allowed name", "Dax-88 is kind.", {}, false)
	_remark_case(t, "newline", "Feeling fine\nreally.", {}, false)
	_remark_case(t, "filtered true", "A calm sort of evening.", {"filtered": true}, false)
	_remark_case(t, "allowed name passes", "Dax-8 has been kind to me.", {}, true)
	_end(t)


# ---------------------------------------------------------------- 8. the bias on a staged being

## Subject in habitat 2 with the four neighbours of _world(); traits 0.5; the world rng is a scripted generator.
func _bias_world(restless: float = 0.5, rng_kind: String = "script") -> Dictionary:
	var c := _cast("llm")
	var w = c.w
	c.s.persona.traits["restless"] = restless
	var rng = ScriptRng.new(1) if rng_kind == "script" else ThresholdRng.new(1)
	w.rng = rng
	w.mood_travel_gain = 0.0
	c["rng"] = rng
	return c


func _base_p(restless: float) -> float:
	var r: Dictionary = SimData.beings().restless
	return float(r.travel_base) + float(r.travel_coef) * restless


func _set_bias(w, b, kind: String, target: Variant = null) -> void:
	b.mind_bias = {"kind": kind, "target": target, "until_t": w.t + float(_md().bias.ttl_h)}


func _p_of(c: Dictionary) -> float:
	c.rng.calls.clear()
	c.s._restless_travel(c.w)
	return float(c.rng.calls[0][1]) if not c.rng.calls.is_empty() and str(c.rng.calls[0][0]) == "chance" else -1.0


func test_t08a_stay_scales_the_travel_chance(t) -> void:
	if not _api(t):
		return
	var c := _bias_world(0.5)
	var floor_v: float = float(c.w.mood_travel_floor)
	var cap: float = float(_md().bias.travel_cap)
	var mult: float = float(_md().bias.stay_travel_mult)
	t.near(_p_of(c), _base_p(0.5), 1e-12, "no bias: the baseline chance (argument unchanged)")
	_set_bias(c.w, c.s, "stay")
	t.near(_p_of(c), clampf(_base_p(0.5) * mult, floor_v, cap), 1e-12, "stay: baseline x bias.stay_travel_mult, clamped")
	# Shipped values at restless 0 (spec 5.5, revision 6): 0.08 x 0.30 = 0.024, above the floor 0.02, so the floor does NOT bind.
	c.s.persona.traits["restless"] = 0.0
	var p0 := _p_of(c)
	t.near(floor_v, float(SimData.moods().effects.travel_floor), 1e-12, "world.mood_travel_floor is mood.json effects.travel_floor (set even with moods off, moods.gd:75)")
	t.near(floor_v, 0.02, 1e-12, "and it ships at 0.02")
	t.near(p0, _base_p(0.0) * mult, 1e-12, "stay at restless 0 with the shipped multiplier: the unclamped product")
	t.near(p0, 0.024, 1e-9, "which is 0.024 at the shipped values")
	t.check(p0 > floor_v + 1e-12, "and the floor did not bind (0.024 > 0.02)")
	_restore()
	# The binding case, staged: stay_travel_mult 0.1 at restless 0 gives 0.08 x 0.1 = 0.008, clamped up to the floor 0.02.
	_cfg_edit("minds.json", ["bias", "stay_travel_mult"], 0.1)
	var c2 := _bias_world(0.0)
	_set_bias(c2.w, c2.s, "stay")
	var floor2: float = float(c2.w.mood_travel_floor)
	t.check(_base_p(0.0) * 0.1 < floor2, "precondition: the product %.4f is below the floor %.4f" % [_base_p(0.0) * 0.1, floor2])
	t.near(_p_of(c2), floor2, 1e-12, "stay_travel_mult 0.1 at restless 0: p is clamped up to world.mood_travel_floor")
	t.near(_p_of(c2), 0.02, 1e-12, "which is 0.02")
	_restore()
	# Sub-case: a multiplier of 0.0 reduces but never zeroes travel; p is the floor, not 0.
	_cfg_edit("minds.json", ["bias", "stay_travel_mult"], 0.0)
	var c3 := _bias_world(0.5)
	_set_bias(c3.w, c3.s, "stay")
	var p3 := _p_of(c3)
	t.near(p3, float(c3.w.mood_travel_floor), 1e-12, "stay_travel_mult 0.0: p equals the floor")
	t.check(p3 > 0.0, "and is not zero")
	_end(t)


func test_t08b_stay_combined_with_a_nonzero_mood_term(t) -> void:
	if not _api(t):
		return
	var c := _bias_world(0.5)
	var w = c.w
	w.mood_travel_gain = 0.15
	c.s.mood = float(c.s.mood_base) + 0.3
	var term: float = 0.15 * clampf(float(c.s.mood), float(w.mood_clamp_low), float(w.mood_clamp_high))
	var p_mood := clampf(_base_p(0.5) + term, float(w.mood_travel_floor), 1.0)
	t.near(_p_of(c), p_mood, 1e-12, "no bias: the 6a mood term moves the chance as in 6a")
	_set_bias(w, c.s, "stay")
	var mult: float = float(_md().bias.stay_travel_mult)
	var got := _p_of(c)
	# Spec 5.5 (revision 5 decision 1): mood term first, then the bias, then the final clamp [mood_travel_floor, bias.travel_cap].
	# Only this order is accepted. The upper clamp can bind only through `roam`, so that assertion is in the slice-2 test.
	var want := clampf(p_mood * mult, float(w.mood_travel_floor), float(_md().bias.travel_cap))
	t.near(got, want, 1e-12, "stay with a mood term: %.6f is clamp(p_mood x mult) = %.6f" % [got, want])
	t.check(got >= float(w.mood_travel_floor) - 1e-12, "never below world.mood_travel_floor")
	_end(t)


func test_t08c_visit_multiplies_the_target_room_after_the_pull(t) -> void:
	if not _api(t):
		return
	_cfg_edit("relationships.json", ["effects", "friend_pull"], 0.25)
	var c := _bias_world(0.5)
	var w = c.w
	_mini_ticks(w, 1)  # relationships learns who is where (`present`)
	w.rng = c.rng
	c.rng.force = true
	var rp: Dictionary = SimData.beings().room_pull
	var nb: Array = c.s._neighbours(w)
	var pull_f := 0.25
	var mult: float = float(_md().bias.visit_weight_mult)
	var right: Array[float] = []
	var wrong: Array[float] = []
	var any_pull := false
	for n in nb:
		var wt: Dictionary = rp.weights[n.to.kind]
		var base := float(rp.floor) + pow(float(c.s.persona.traits[wt.trait]) * float(wt.mult), float(rp.exponent))
		var pull: float = w.relationships.pull(c.s.id, n.to.id, pull_f, 0.0, int(SimData.relationships().effects.friend_pull_cap))
		any_pull = any_pull or pull > 0.0
		var is_t: bool = int(n.to.id) == int(c.f1.building_id)
		right.append((base + pull) * mult if is_t else base + pull)
		wrong.append(base * mult + pull if is_t else base + pull)
	t.check(any_pull, "the staged pull toward the friend's room is nonzero")
	_set_bias(w, c.s, "visit", c.f1.id)
	var picked := func(ws: Array, u: float) -> int:
		var tot := 0.0
		for v in ws:
			tot += v
		var x := u * tot
		var pick: int = nb[nb.size() - 1].corridor
		for i in nb.size():
			x -= ws[i]
			if x < 0.0:
				pick = nb[i].corridor
				break
		return pick
	var u_found := -1.0
	for k in range(1, 100):
		var u := float(k) / 100.0
		if picked.call(right, u) != picked.call(wrong, u):
			u_found = u
			break
	t.check(u_found > 0.0, "a draw exists where the two orders of multiply and pull pick different rooms")
	c.rng.u = u_found
	c.rng.calls.clear()
	c.s.state = "idle"
	var went: bool = c.s._restless_travel(w)
	t.check(went, "the forced chance succeeds")
	t.eq(int(c.s.corridor_id), int(picked.call(right, u_found)), "the pick follows (floor + trait + pull) x bias.visit_weight_mult")
	t.eq(c.rng.names(), ["chance", "randf", "randf_range"], "a successful decision consumes chance, randf, one randf_range")
	_end(t)


func test_t08d_same_outcome_same_draws_and_a_flip_switches_sequence(t) -> void:
	if not _api(t):
		return
	var seqs := {}
	for biased in [false, true]:
		for force in [false, true]:
			var c := _bias_world(0.5)
			c.rng.force = force
			if biased:
				_set_bias(c.w, c.s, "visit", c.f1.id)
			var went: bool = c.s._restless_travel(c.w)
			if not went:
				c.s.idle_wait(c.w.rng)
			seqs["%s:%s" % [biased, force]] = c.rng.names()
	t.eq(seqs["false:false"], ["chance", "randf_range", "randf_range"], "baseline fail: chance + the two randf_range of idle_wait")
	t.eq(seqs["true:false"], seqs["false:false"], "a visit bias: the same draws for the same (failed) outcome")
	t.eq(seqs["false:true"], ["chance", "randf", "randf_range"], "baseline success: chance + randf + one randf_range of door_time")
	t.eq(seqs["true:true"], seqs["false:true"], "a visit bias: the same draws for the same (successful) outcome")
	# A bias that flips the outcome switches to the other outcome's sequence (baseline 0.24 passes u = 0.2, stay 0.072 fails it).
	var run := func(biased: bool) -> Array:
		var c := _bias_world(0.5, "threshold")
		c.rng.cu = 0.2
		if biased:
			_set_bias(c.w, c.s, "stay")
		var went: bool = c.s._restless_travel(c.w)
		if not went:
			c.s.idle_wait(c.w.rng)
		return c.rng.names()
	var base_seq: Array = run.call(false)
	var stay_seq: Array = run.call(true)
	t.eq(base_seq, ["chance", "randf", "randf_range"], "unbiased, u = 0.2 < 0.24: the success sequence")
	t.eq(stay_seq, ["chance", "randf_range", "randf_range"], "stay flips it: the failure sequence follows, a different stream")
	t.check(base_seq != stay_seq, "the sequences differ after a flip")
	_end(t)


# ---------------------------------------------------------------- 9. bias scope

func test_t09a_survival_and_work_come_before_the_bias(t) -> void:
	if not _api(t):
		return
	# Sleep: a tired being with a stay bias still goes to bed (same state as without the bias).
	var outcomes := []
	for biased in [false, true]:
		var c := _bias_world(0.5)
		c.s.energy = float(SimData.beings().energy.sleep_below) - 5.0
		if biased:
			_set_bias(c.w, c.s, "stay")
		c.s.decide(c.w)
		outcomes.append([c.s.state, c.s.sleep_intent, c.rng.names()])
	t.eq(outcomes[1], outcomes[0], "sleep: the biased decision equals the unbiased one")
	t.check(str(outcomes[1][0]) == "sleep" or bool(outcomes[1][1]), "and it is a sleep decision")
	# Construction volunteer: a staged site and a forced join chance; the bias is never read (identical call logs).
	var logs := []
	for biased in [false, true]:
		var c := _bias_world(0.5)
		var site := Buildings.Site.new()
		site.building_id = c.w.add_building("workshop", 400, 400, 0.1)
		site.parent_id = HAB
		site.last_work_t = c.w.t
		c.w.buildings.site = site
		c.rng.force = true
		if biased:
			_set_bias(c.w, c.s, "stay")
		c.s.decide(c.w)
		logs.append([c.s.state, c.s.job != null, c.rng.calls])
	t.eq(logs[1], logs[0], "construction: a biased builder decides exactly as an unbiased one")
	t.check(logs[0][2].size() >= 1, "the join chance was drawn")
	t.check(bool(logs[0][1]), "and the unbiased builder joined the site (it holds a job), so the comparison is not vacuous")
	# Resuming a mine intent is checked the same way on a founder world's ice field (identical state and call logs).
	var mlogs := []
	for biased in [false, true]:
		var w = SimWorld.new(5, {"minds_mode": "llm"})
		var b = w.beings[0]
		b.state = "idle"
		b.energy = 90.0
		if not w.resources.ice_fields.is_empty():
			b.mine_intent = w.resources.ice_fields[0]
		var rng := ScriptRng.new(1)
		rng.force = true
		w.rng = rng
		if biased:
			_set_bias(w, b, "stay")
		b.decide(w)
		mlogs.append([b.state, b.mine_intent == null, rng.calls, b.mine != null or b.mine_intent != null])
	t.eq(mlogs[1], mlogs[0], "mine intent: a biased being decides exactly as an unbiased one")
	t.check(bool(mlogs[0][3]), "the pending mine intent was resumed (a trip started or the walk to the launch building began), so the comparison is not vacuous")
	t.check(bool(mlogs[1][3]), "and the biased being resumed it too")
	_end(t)


func test_t09b_expiry_never_extends_and_young_beings_hold_none(t) -> void:
	if not _api(t):
		return
	var c := _cast("llm")
	var w = c.w
	var d := _decide(w, c.s, "stay", "Quiet evening.")
	t.check(c.s.mind_bias != null, "the stay decision set a bias")
	var until: float = float(c.s.mind_bias.until_t)
	t.near(until, w.t + float(_md().bias.ttl_h), 1e-6, "until_t is the resolution time plus bias.ttl_h")
	_mini(w, 40)
	t.near(float(c.s.mind_bias.until_t), until, 1e-12, "the expiry time does not move while the bias is held")
	var guard := 0
	while w.t < until + 1.5 and guard < 5000:
		_mini(w)
		guard += 1
	t.check(c.s.mind_bias == null, "the bias is gone after ttl_h")
	var kids: Array = []
	for stage in ["toddler", "child", "teen"]:
		var kid = _young(w, HAB, false, stage)
		kids.append(kid)
		# A bias is delivered to the young being at its slot: refused (stored menu is carry_on only, reason not_in_menu).
		var refused0 := _rej(w, "not_in_menu")
		var dd := _decide(w, kid, "stay", "Quiet evening.")
		t.check(not dd.is_empty(), "a %s opened a slot to deliver to" % stage)
		t.check(kid.mind_bias == null, "a %s that is delivered `stay` holds no bias (refused)" % stage)
		t.eq(_rej(w, "not_in_menu"), refused0 + 1, "a %s: the delivery is counted as rejected not_in_menu" % stage)
	_mini_to_sol(w, _sol(w) + 1)
	_mini(w, 600)
	for i in kids.size():
		t.check(kids[i].mind_bias == null, "a %s never holds a bias" % ["toddler", "child", "teen"][i])
	_end(t)


# ---------------------------------------------------------------- 10. the per-sol cap

func test_t10_apply_max_per_sol(t) -> void:
	if not _api(t):
		return
	_cfg_edit("minds.json", ["sim", "apply_max_per_sol"], 2)
	var w = _world("llm", 1, false)
	var ids := _populate(w, 8)
	_mini_to_sol(w, 3)
	# Ids 1..6 open their calm slots in sol 3 at cells 14 down to 9 (id * 7919 is -id mod 24): stay for ids 1 to 6, carry_on 7, 8.
	var opened := {}
	var guard := 0
	while opened.size() < 8 and guard < 20000:
		_mini(w)
		guard += 1
		for b in w.beings:
			if not opened.has(b.id) and int(b.mind_slot_n) > 0:
				var d: Variant = null
				for e in w.minds.due:
					if int(e.id) == int(b.id):
						d = e
				if d != null:
					opened[b.id] = d
					_deliver(w, b.id, d.k, "stay" if int(b.id) <= 6 else "carry_on", "Steady.")
	t.eq(opened.size(), 8, "all eight beings opened a slot")
	var order: Array = opened.values()
	order = order.filter(func(e): return true)
	var stay_entries: Array = []
	for id in range(1, 7):
		stay_entries.append(opened[id])
	stay_entries.sort_custom(func(a, b): return int(a.deadline_step) < int(b.deadline_step) or (int(a.deadline_step) == int(b.deadline_step) and int(a.id) < int(b.id)))
	for e in opened.values():
		_resolve(w, int(e.id), int(e.k))
	t.eq(int(_stat(w, "applied_model")), 2, "exactly the cap (2) behaviour-changing decisions applied; carry_on does not count")
	t.eq(int(_stat(w, "apply_dropped_cap")), 4, "the other four stays are counted apply_dropped_cap")
	for i in 6:
		var id: int = int(stay_entries[i].id)
		var b = null
		for x in w.beings:
			if int(x.id) == id:
				b = x
		t.check((b.mind_bias != null) == (i < 2), "in (deadline, id) order only the first two are applied (being %d, position %d)" % [id, i])
	_end(t)


# ---------------------------------------------------------------- 21. data parity (key list, literals, sanity is test 40)

## Spec section 15 Group A: the key paths of the fenced list (the first line token of each line), for data/minds.json.
func _spec_keys() -> Array:
	var spec := FileAccess.get_file_as_string("res://docs/specs/ai-minds.md")
	var i0 := spec.find("## 15. Tunables")
	if i0 < 0:
		return []
	i0 = spec.find("```", i0)
	if i0 < 0:
		return []
	i0 = spec.find("\n", i0) + 1
	var i1 := spec.find("```", i0)
	var out: Array = []
	for l in spec.substr(i0, i1 - i0).split("\n"):
		var s := l.strip_edges()
		if s == "" or s.begins_with("("):
			continue
		out.append(s.split(" ", false)[0])
	return out


## Spec section 15 Group B: the backticked key paths of the "Group B" paragraph (parenthetical notes removed first, so the
## shipped word lists quoted inside them are not read as keys). Placeholders `<name>` and a trailing `[]` are cut, leaving a
## prefix: the data file must hold at least one leaf at or under it.
func _spec_keys_b() -> Array:
	var spec := FileAccess.get_file_as_string("res://docs/specs/ai-minds.md")
	var i0 := spec.find("**Group B:")
	if i0 < 0:
		return []
	var i1 := spec.find("\n", i0)
	var para := spec.substr(i0, i1 - i0)
	var paren := RegEx.create_from_string("\\([^()]*\\)")
	para = paren.sub(para, "", true)
	var tick := RegEx.create_from_string("`([^`]+)`")
	var out: Array = []
	for m in tick.search_all(para):
		var k: String = m.get_string(1)
		if k.contains("minds_text.json"):
			continue
		k = k.replace("[]", "")
		var lt := k.find(".<")
		if lt >= 0:
			k = k.substr(0, lt)
		out.append(k)
	return out


func _under(leaf: String, prefix: String) -> bool:
	return leaf == prefix or leaf.begins_with(prefix + ".")


func test_t21a_key_path_parity_both_ways(t) -> void:
	if not FileAccess.file_exists("res://data/minds.json"):
		t.check(false, "missing API: data/minds.json")
		return
	# Group A against data/minds.json: exact, both ways. The expected count is whatever the spec list gives (no literal).
	var keys := _spec_keys()
	t.check(not keys.is_empty(), "the spec Group A key list parses (%d keys)" % keys.size())
	var leaves: Array = []
	_leaves(_md(), "", leaves)
	var dup := {}
	for k in keys:
		t.check(not dup.has(k), "spec key %s is listed once" % k)
		dup[k] = true
		t.check(k in leaves, "spec key %s is a leaf of data/minds.json" % k)
	for l in leaves:
		t.check(l in keys, "data/minds.json leaf %s is in the spec Group A list" % l)
	t.eq(leaves.size(), keys.size(), "data/minds.json has exactly as many leaves as the Group A list has keys")
	t.eq(int(_md().get("tests", {}).get("mock_seed", -1)), 1013, "tests.mock_seed is the fixed constant 1013")
	# Group B against data/minds_text.json (a different file: the same prefix `filter.` is legal in both).
	if not FileAccess.file_exists("res://data/minds_text.json"):
		t.check(false, "missing API: data/minds_text.json")
		return
	var keys_b := _spec_keys_b()
	t.check(not keys_b.is_empty(), "the spec Group B key list parses (%d keys)" % keys_b.size())
	var leaves_b: Array = []
	_leaves(_mt(), "", leaves_b)
	for k in keys_b:
		t.check(leaves_b.any(func(l): return _under(str(l), str(k))), "spec key %s has a leaf in data/minds_text.json" % k)
	for l in leaves_b:
		t.check(keys_b.any(func(k): return _under(str(l), str(k))), "data/minds_text.json leaf %s is under a spec Group B key" % l)
	for k in ["filter.template_forbidden_words", "filter.player_terms", "filter.chart_terms"]:
		t.check(k in leaves_b, "%s is in data/minds_text.json (Group B)" % k)
		t.check(not (k in leaves), "and not in data/minds.json")
	t.check("filter.caps_min_len" in leaves and not ("filter.caps_min_len" in leaves_b), "filter.caps_min_len is in data/minds.json only (Group A)")


func _code_only(src: String) -> String:
	var out: Array[String] = []
	for line in src.split("\n"):
		var l: String = line
		var q := RegEx.create_from_string("\"[^\"]*\"|'[^']*'")
		l = q.sub(l, "\"\"", true)
		var h := l.find("#")
		if h >= 0:
			l = l.substr(0, h)
		out.append(l)
	return "\n".join(PackedStringArray(out))


func _literals(src: String) -> Array[String]:
	var num := RegEx.create_from_string("(?<![A-Za-z_0-9.])(\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)(?![A-Za-z_0-9])")
	var idx := RegEx.create_from_string("\\[\\s*\\d+\\s*\\]")
	var out: Array[String] = []
	for line in _code_only(src).split("\n"):
		var l: String = idx.sub(line, "[]", true)
		for m in num.search_all(l):
			var s := m.get_string()
			if s in ["0", "1", "2", "0.0", "1.0", "2.0"]:  # spec 14 test 21: only 0, 1, -1 (as 1) and 2 may stay literal
				continue
			out.append("%s in `%s`" % [s, line.strip_edges()])
	return out


func test_t21b_no_tunable_literal_in_sim_minds(t) -> void:
	t.eq(_literals("var a = 0.25 + 3").size(), 2, "the scanner finds 0.25 and 3")
	t.eq(_literals("var a = 0 + 1 + 2.0 + b[3] # 7 in a comment").size(), 0, "0, 1, 2, indices and comments are fine")
	# Revision 6: the last-cell key multiplier is the data key slot.cell_key_mult, so a bare 64 is a finding and the named key is not.
	t.eq(_literals("var k = sol * 64 + cell").size(), 1, "a literal 64 in the last-cell key is a finding")
	t.eq(_literals("var k = sol * cfg.slot.cell_key_mult + cell").size(), 0, "the data key slot.cell_key_mult is not")
	t.eq(_literals("var h = 0.5 * x").size(), 1, "0.5 is not on the allowlist (spec: only 0, 1, -1 and 2)")
	var scanned := 0
	for f in ["res://sim/minds.gd", "res://sim/minds_voice.gd"]:
		if not FileAccess.file_exists(f):
			t.check(false, "missing API: %s" % f)
			continue
		scanned += 1
		var found := _literals(FileAccess.get_file_as_string(f))
		t.check(found.is_empty(), "%s has hard-coded numbers (%d), first: %s" % [f, found.size(), found[0] if not found.is_empty() else ""])
	t.eq(scanned, 2, "both module files exist and were scanned")
	if FileAccess.file_exists("res://sim/minds.gd"):
		var code := _code_only(FileAccess.get_file_as_string("res://sim/minds.gd"))
		t.check(code.contains("cell_key_mult"), "sim/minds.gd builds last_cell_key from the data key slot.cell_key_mult")


# ---------------------------------------------------------------- 30. perf (the probe discipline of 6a; E)

func test_t30_minds_tick_budget_at_pop_159(t) -> void:
	if not _api(t):
		return
	var w = _world("rules", 1, true)
	_populate(w, 159)
	_mini_to_sol(w, 2)
	var samples: Array[float] = []
	var seen: int = int(w.relationships.ticks)
	var guard := 0
	while samples.size() < 60 and guard < 100000:
		w.t += w.fixed_step
		w.buildings.now = w.t
		w.step_index += 1
		w.relationships.on_step(w, w.fixed_step)
		if w.moods_enabled:
			w.moods.on_step(w)
		if int(w.relationships.ticks) != seen:
			seen = int(w.relationships.ticks)
			var t0 := Time.get_ticks_usec()
			w.minds.on_step(w)
			samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		else:
			w.minds.on_step(w)
		guard += 1
	samples.sort()
	var median := samples[samples.size() / 2]
	var worst := samples[samples.size() - 1]
	var med_max: float = float(_md().balance.minds_tick_ms_max)
	var peak_max: float = float(_md().balance.minds_tick_ms_peak_max)
	var mult: float = float(_md().balance.minds_tick_fail_mult)
	var strict := _has_user_arg("--perf")
	# Spec 14 test 30 (revision 6): record and print the measured figures every run; fail only above the generous multiple
	# (balance.minds_tick_fail_mult x each figure) unless the user arg --perf asks for the strict section-12 thresholds.
	print("minds tick at pop 159: median %.3f ms, max %.3f ms (strict limits %s / %s, fail multiple %s, mode %s)" % [median, worst,
			str(med_max), str(peak_max), str(mult), "STRICT (--perf)" if strict else "generous"])
	t.check(samples.size() >= 60, "60 ticks were sampled")
	t.check(mult >= 1.0, "balance.minds_tick_fail_mult is at least 1 (sanity rule)")
	var med_limit: float = med_max if strict else med_max * mult
	var peak_limit: float = peak_max if strict else peak_max * mult
	t.check(median <= med_limit, "median %.3f ms <= %.3f ms (%s)" % [median, med_limit, "balance.minds_tick_ms_max" if strict else "fail multiple x balance.minds_tick_ms_max"])
	t.check(worst <= peak_limit, "max %.3f ms <= %.3f ms (%s)" % [worst, peak_limit, "balance.minds_tick_ms_peak_max" if strict else "fail multiple x balance.minds_tick_ms_peak_max"])
	if not strict and (median > med_max or worst > peak_max):
		print("FINDING t30: the strict section-12 figure is breached without the fail multiple (median %.3f > %.3f or max %.3f > %.3f ms); not a red test, triggers the section 12 cut order" % [median, med_max, worst, peak_max])
	_end(t)


# ---------------------------------------------------------------- 32. event slots

func test_t32a_each_real_mood_key_opens_one_event_slot(t) -> void:
	if not _api(t):
		return
	var think_event: float = float(_md().sim.think_event_h)
	for key in ["grief", "friend", "close", "lapse", "lapse_close", "birth_parent"]:
		var c := _cast("llm")
		var w = c.w
		_mini_to_sol(w, 3)
		var e0: int = int(_stat(w, "slots_opened").event)
		var n0: int = int(c.s.mind_slot_n)
		_until_next_tick(w, func(sol, cell): return _cell_of(w, int(c.s.id), sol, 0, 1) != cell and cell < 24)
		_why(c.s, key, w.t, c.f1.id, "Dax-8")
		_mini_ticks(w, 1)
		var evs: Array = _due_of(w, int(c.s.id)).filter(func(d): return str(d.kind) == "event")
		t.eq(int(_stat(w, "slots_opened").event), e0 + 1, "%s: one event slot opened" % key)
		if not evs.is_empty():
			t.eq(int(evs[0].deadline_step) - int(evs[0].open_step), int(round(think_event / w.fixed_step)), "%s: deadline is sim.think_event_h (3.0 h) after open" % key)
	_end(t)


func test_t32b_cooldown_order_and_god_code(t) -> void:
	if not _api(t):
		return
	var c := _cast("llm")
	var w = c.w
	_mini_to_sol(w, 3)
	_until_next_tick(w, func(sol, cell): return _cell_of(w, int(c.s.id), sol, 0, 1) != cell and cell < 24)
	_why(c.s, "grief", w.t, 9, "Gone-9")
	_mini_ticks(w, 1)
	var e1: int = int(_stat(w, "slots_opened").event)
	var f: Dictionary = w.minds.facts_for(w, c.s)
	t.eq(str(f.get("god", {}).get("last", "")), "none", "god.last is `none` (the god-landing case is deferred until a source exists)")
	_until_next_tick(w, func(sol, cell): return true)
	_why(c.s, "friend", w.t, c.f1.id, "Dax-8")
	_mini_ticks(w, 1)
	t.eq(int(_stat(w, "slots_opened").event), e1, "a second moment inside sim.event_cooldown_h opens no event slot")
	# After the cooldown a new moment opens one again.
	_mini(w, int(ceil(float(_md().sim.event_cooldown_h) / w.fixed_step)) + 80)
	_why(c.s, "close", w.t, c.f1.id, "Dax-8")
	_mini_ticks(w, 1)
	t.eq(int(_stat(w, "slots_opened").event), e1 + 1, "after the cooldown the next moment opens an event slot")
	# Events go before calm slots under the per-tick cap: cap 1, one calm due and one event on the same tick.
	_restore()
	_cfg_edit("minds.json", ["sim", "max_slots_per_tick"], 1)
	var c2 := _cast("llm")
	var w2 = c2.w
	var rest := []
	for i in 23:
		rest.append(_being(w2, HAB).id)
	_mini_to_sol(w2, 3)
	# Find a tick where some calm cell has two or more beings, so that one carries over; put an event on a different being.
	var found := false
	var guard := 0
	while not found and guard < 100000:
		var nx := _next_tick_cell(w2)
		if not nx.is_empty() and _demand(w2, rest + [c2.s.id, c2.f1.id, c2.f2.id, c2.x.id], nx[0], nx[1], 1) >= 2 and nx[1] < 24:
			found = true
		else:
			_mini(w2)
		guard += 1
	t.check(found, "a tick with two calm slots due is reached")
	var ev_being = c2.x
	_why(ev_being, "grief", w2.t, 9, "Gone-9")
	var n_before: int = int(ev_being.mind_slot_n)
	_mini_ticks(w2, 1)
	t.eq(int(ev_being.mind_slot_n), n_before + 1, "with the cap at 1 the event slot is the one opened (events go before calm)")
	_end(t)


func test_t32c_event_window_arithmetic(t) -> void:
	if not FileAccess.file_exists("res://data/minds.json"):
		t.check(false, "missing API: data/minds.json")
		return
	var m := _md()
	var rs := float(SimData.sim().real_seconds_per_hour_at_1x)
	var window: float = float(m.sim.think_event_h) * rs
	var need: float = float(m.driver.latency_p50_s) * float(m.driver.deadline_margin) + float(m.driver.batch_wait_s)
	t.near(window, 3.0, 1e-9, "event window at 1x is 3.0 s")
	t.near(need, 2.75, 1e-9, "the skip threshold is 2.75 s")
	t.check(window >= need, "the event window clears the threshold at 1x")
	t.check(float(m.sim.think_event_h) * rs / 2.0 < need, "and does not at 2x (event slots are live at 1x only)")
	t.check(float(m.sim.think_h) * rs / 2.18 >= need - 0.02, "calm slots stay live up to about 2.18x")


# ---------------------------------------------------------------- 33. worth gate and fair rotation

## Steps to the next tick at which `b`'s calm cell is due (a cell below 24), clears the outbox, runs `stage` (a Callable that
## sets up the world for that one tick) and steps the tick. Returns {opened, asked, kind}: whether `b` opened exactly one slot,
## whether it was put in a request, and the kind of its due entry.
func _calm_tick(w, b, stage: Callable) -> Dictionary:
	var n0: int = int(b.mind_slot_n)
	var due_cell := func(sol: int, cell: int) -> bool: return cell < 24 and _cell_of(w, int(b.id), sol, 0, 1) == cell
	if not _until_next_tick(w, due_cell):
		return {"opened": false, "asked": false, "kind": ""}
	w.minds.outbox.clear()
	stage.call()
	_mini_ticks(w, 1)
	var ds := _due_of(w, int(b.id))
	return {"opened": int(b.mind_slot_n) == n0 + 1, "asked": _requested(w, b), "kind": str(ds[ds.size() - 1].kind) if not ds.is_empty() else ""}


## Mini-steps through the end of sol `sol - 1` (see _mini_to_sol), collecting every request seen on the outbox after each step:
## {"id:k": true}. Sampling every step means the measurement never depends on how long the outbox keeps an entry.
func _collect_requests_to_sol(w, sol: int) -> Dictionary:
	var seen := {}
	var guard := 0
	while int(w.clock.sol_index(w.t + w.fixed_step)) < sol and guard < 400000:
		_mini(w)
		guard += 1
		for r in w.minds.outbox:
			seen["%d:%d" % [int(r.id), int(r.k)]] = true
	return seen


func test_t33a_the_rare_calm_sample_and_nothing_else(t) -> void:
	if not _api(t):
		return
	var sample_every: int = int(_md().gate.calm_every_n_sols)
	# Moods are OFF for this exact count: with no mood module there is no mood_why, so no event slot, no heavy or bright
	# trigger and no company-bond `friend` event can open on a beings that is not sampled (5.2 step 3). Stocks are full, so no
	# `hard_times` hint. What is left for a calm, even-band being is the season trigger (a first-ever slot only records the
	# season, 5.6, and no season boundary falls in sol 2, 33) and the rare calm sample.
	var c := _cast("llm", 1, false)
	var w = c.w
	for i in 30:
		_being(w, HAB)
	_mini_to_sol(w, 2)  # sol 1 lacks the ticks of cells 0 to 5; sol 2 is the first whole sol
	w.minds.outbox.clear()  # before sol 2 starts, so no sol-2 request is ever deleted by the test
	var n_before := {}
	for b in w.beings:
		n_before[int(b.id)] = int(b.mind_slot_n)
	var reqs := _collect_requests_to_sol(w, 3)  # all of sol 2
	var asked := {}
	for key in reqs:
		asked[int(str(key).split(":")[0])] = true
	var checked := 0
	var wrong: Array[String] = []
	var sampled_n := 0
	for b in w.beings:
		var opened: int = int(b.mind_slot_n) - int(n_before[int(b.id)])
		if opened != 1:
			wrong.append("%d opened %d slots in sol 2" % [int(b.id), opened])
			continue
		var sampled: bool = (int(b.id) + 2) % sample_every == 0
		sampled_n += 1 if sampled else 0
		checked += 1
		if asked.has(int(b.id)) != sampled:
			wrong.append("%d sampled=%s asked=%s" % [int(b.id), str(sampled), str(asked.has(int(b.id)))])
	t.check(wrong.is_empty(), "per being: asked in sol 2 exactly when (id + 2) mod %d == 0 (rare calm sample), none other; first problem: %s" % [sample_every, wrong[0] if not wrong.is_empty() else ""])
	t.eq(checked, w.beings.size(), "every being was examined (one calm slot each in sol 2)")
	t.check(sampled_n > 0 and not asked.is_empty(), "the sol holds at least one sampled being and one request, so the test is not vacuous")
	t.eq(reqs.size(), asked.size(), "and no being has two requests")
	var seen_ok := true
	for b in w.beings:
		seen_ok = seen_ok and w.minds.season_seen.has(int(b.id))
	t.check(seen_ok, "every being that had a slot has a season_seen record (the first slot only records the season)")
	# 0 disables the sample: the same sol, nobody is asked.
	_restore()
	_cfg_edit("minds.json", ["gate", "calm_every_n_sols"], 0)
	var c0 := _cast("llm", 1, false)
	for i in 30:
		_being(c0.w, HAB)
	_mini_to_sol(c0.w, 2)
	c0.w.minds.outbox.clear()
	var n0 := int(_stat(c0.w, "slots_opened").calm)
	var reqs0 := _collect_requests_to_sol(c0.w, 3)
	t.check(int(_stat(c0.w, "slots_opened").calm) - n0 >= c0.w.beings.size(), "gate.calm_every_n_sols 0: the calm slots still open in sol 2")
	t.eq(reqs0.size(), 0, "and gate.calm_every_n_sols 0 disables the rare sample: no one is asked")
	_end(t)


func test_t33c_season_change_is_a_request_and_the_first_slot_only_records(t) -> void:
	if not _api(t):
		return
	# The sample is disabled and moods are off, so the season trigger is the only thing that can make a calm being a request.
	# There is no natural season boundary in a short run (Ls starts near 0.4 degrees; the first change is about sol 170), so
	# the change is staged through season_seen (spec 14 test 33 (a)).
	_cfg_edit("minds.json", ["gate", "calm_every_n_sols"], 0)
	var c := _cast("llm", 1, false)
	var w = c.w
	_mini_to_sol(w, 3)
	var cur := _season_index(w)
	var seasons: int = w.clock.seasons.size()
	var id := int(c.s.id)
	w.minds.season_seen[id] = (cur + 1) % seasons
	var r1 := _calm_tick(w, c.s, func(): pass)
	t.check(bool(r1.opened), "the staged being opened its calm slot")
	t.eq(str(r1.kind), "calm", "and it is a calm slot (no moment)")
	t.check(bool(r1.asked), "season change (season_seen differs from the current index): the slot is a request")
	t.eq(int(w.minds.season_seen.get(id, -1)), cur, "and season_seen then equals the current season index")
	var r2 := _calm_tick(w, c.s, func(): pass)
	t.check(bool(r2.opened), "the next calm slot opened")
	t.check(not bool(r2.asked), "a second slot in the same season is not a request (the trigger fires once per season change)")
	t.eq(int(w.minds.season_seen.get(id, -1)), cur, "and season_seen is unchanged")
	# First-ever slot: a being with no season_seen entry only records the index; no request on that account.
	var fresh = _being(w, HAB)
	w.minds.season_seen.erase(int(fresh.id))
	t.check(not w.minds.season_seen.has(int(fresh.id)), "precondition: the new being has no season_seen entry")
	var r3 := _calm_tick(w, fresh, func(): pass)
	t.check(bool(r3.opened), "the new being opened its first slot")
	t.check(not bool(r3.asked), "first-ever slot: not a request on the season account")
	t.eq(int(w.minds.season_seen.get(int(fresh.id), -1)), cur, "it only records the current season index")
	_end(t)


func test_t33d_hard_times_bright_and_the_asleep_case(t) -> void:
	if not _api(t):
		return
	# Sample disabled; each case is a calm slot (the why keys used are NOT event keys: hard_sol and pledge only feed the gate,
	# 5.2 step 3) on a being whose season_seen is current, so nothing but the case under test can make it a request.
	_cfg_edit("minds.json", ["gate", "calm_every_n_sols"], 0)
	var cases := [
		{"label": "even band, no moment (control)", "key": "", "dev": 0.0, "state": "idle", "band": 2, "asked": false},
		{"label": "hard times: heavy band with a fresh why", "key": "hard_sol", "dev": -0.5, "state": "idle", "band": 0, "asked": true},
		{"label": "bright: band 4 with a fresh why", "key": "pledge", "dev": 0.5, "state": "idle", "band": 4, "asked": true},
		{"label": "asleep: the hard-times case on a sleeping being is not a request", "key": "hard_sol", "dev": -0.5, "state": "sleep", "band": 0, "asked": false},
	]
	for cs in cases:
		var c := _cast("llm")
		var w = c.w
		_mini_to_sol(w, 3)
		w.minds.season_seen[int(c.s.id)] = _season_index(w)
		var stage := func() -> void:
			if str(cs.key) != "":
				_why(c.s, str(cs.key), w.t)
				c.s.mood = float(c.s.mood_base) + float(cs.dev)
			c.s.state = str(cs.state)
		var r := _calm_tick(w, c.s, stage)
		t.check(bool(r.opened), "%s: the slot opened" % cs.label)
		t.eq(str(r.kind), "calm", "%s: a calm slot" % cs.label)
		t.eq(int(w.minds.facts_for(w, c.s).get("mood", {}).get("band", -1)), int(cs.band), "%s: facts carry mood band %d" % [cs.label, int(cs.band)])
		t.eq(bool(r.asked), bool(cs.asked), "%s: request %s" % [cs.label, "built" if bool(cs.asked) else "not built"])
	_end(t)


func test_t33e_a_moment_is_a_request_young_beings_are_never_asked_and_rules_never_fills_the_outbox(t) -> void:
	if not _api(t):
		return
	var sample_every: int = int(_md().gate.calm_every_n_sols)
	# A moment is a request (the tick is chosen so the rare sample does not apply to the being).
	var c2 := _cast("llm")
	_mini_to_sol(c2.w, 3)
	_until_next_tick(c2.w, func(sol, cell): return (int(c2.s.id) + sol) % sample_every != 0 and cell < 24)
	_why(c2.s, "grief", c2.w.t, 9, "Gone-9")
	c2.w.minds.outbox.clear()
	_mini_ticks(c2.w, 1)
	t.check(c2.w.minds.outbox.any(func(r): return int(r.id) == int(c2.s.id)), "a grief moment is a request")
	# Young beings (toddler, child, teen) get slots but are never put in a request, even with a grief moment (5.3, 5.6).
	var c4 := _cast("llm")
	var ykids: Array = []
	for stage in ["toddler", "child", "teen"]:
		ykids.append(_young(c4.w, HAB, false, stage))
	_mini_to_sol(c4.w, 3)
	_until_next_tick(c4.w, func(sol, cell): return cell < 24)
	for k in ykids:
		_why(k, "grief", c4.w.t, 9, "Gone-9")
	c4.w.minds.outbox.clear()
	_mini_ticks(c4.w, 1)
	t.check(not c4.w.minds.outbox.any(func(r): return int(r.id) in ykids.map(func(k): return int(k.id))), "no young being is ever in a request")
	# Mode rules produces no request.
	var c3 := _cast("rules")
	_mini_to_sol(c3.w, 3)
	_until_next_tick(c3.w, func(sol, cell): return true)
	_why(c3.s, "grief", c3.w.t, 9, "Gone-9")
	_mini_ticks(c3.w, 1)
	t.eq(c3.w.minds.outbox.size(), 0, "mode rules never fills the outbox")
	_end(t)


func test_t33b_priority_order_and_rotation(t) -> void:
	if not _api(t):
		return
	var c := _cast("llm")
	var w = c.w
	_mini_to_sol(w, 3)
	_until_next_tick(w, func(sol, cell): return cell < 24)
	# Two moments on the same tick: f2 was voiced by the model recently, s never.
	w.minds.says[int(c.f2.id)] = {"text": "Hm.", "t": w.t - 1.0, "source": "model", "t_model": w.t - 1.0, "variant": {}}
	w.minds.outbox.clear()
	_why(c.s, "grief", w.t, 9, "Gone-9")
	_why(c.f2, "grief", w.t, 9, "Gone-9")
	_mini_ticks(w, 1)
	var rs: Dictionary = {}
	for r in w.minds.outbox:
		rs[int(r.id)] = r
	t.check(rs.has(int(c.s.id)) and rs.has(int(c.f2.id)), "both moments were requested")
	if rs.has(int(c.s.id)) and rs.has(int(c.f2.id)):
		var ps: Array = rs[int(c.s.id)].priority
		var pf: Array = rs[int(c.f2.id)].priority
		t.eq(int(ps[0]), 0, "grief is drama tier 0")
		t.near(float(ps[1]), -1.0, 1e-12, "a never-voiced being has t_model -1")
		t.check(float(pf[1]) > float(ps[1]), "a being voiced recently sorts after one never voiced (t_model ascending)")
		var sol := _sol(w)
		var s: Dictionary = _md().slot
		t.eq(int(ps[2]), (int(c.s.id) * int(s.cell_mult) + sol * int(s.cell_step)) % int(s.tie_mod), "tie = (id x cell_mult + sol x cell_step) mod tie_mod")
	# Over 40 sols no being among equals is always first or always last.
	var c2 := _cast("llm")
	var w2 = c2.w
	var group: Array = [c2.s, c2.f1, c2.f2, c2.x]
	for i in 4:
		group.append(_being(w2, HAB))
	_mini_to_sol(w2, 3)
	var firsts := {}
	var lasts := {}
	for k in 40:
		_until_next_tick(w2, func(sol, cell): return cell < 24)
		w2.minds.outbox.clear()
		for b in group:
			_why(b, "grief", w2.t, 9, "Gone-9")
		_mini_ticks(w2, 1)
		var list: Array = w2.minds.outbox.duplicate()
		list.sort_custom(func(a, b):
			for i in 3:
				if a.priority[i] != b.priority[i]:
					return a.priority[i] < b.priority[i]
			return int(a.id) < int(b.id))
		if list.size() >= 2:
			firsts[int(list[0].id)] = true
			lasts[int(list[list.size() - 1].id)] = true
		_mini_to_sol(w2, _sol(w2) + 1)
	t.check(firsts.size() > 1, "the first-ranked being rotates over 40 sols (%d distinct)" % firsts.size())
	t.check(lasts.size() > 1, "the last-ranked being rotates over 40 sols (%d distinct)" % lasts.size())
	_end(t)


# ---------------------------------------------------------------- 34. intent rendering and line/action agreement (slice 1)

func _fill(tpl: String, other: String) -> String:
	return tpl.replace("{other}", other)


func test_t34a_visit_line_carries_the_sims_intent_phrase(t) -> void:
	if not _api(t):
		return
	var c := _cast("llm")
	var w = c.w
	var d := _open_slot(w, c.s)
	var target: int = c.f1.id
	_deliver(w, c.s.id, d.k, "visit:%d" % target, "Kiro-12 is waiting for me.")
	_resolve(w, c.s.id, d.k)
	var line := str(w.minds.says[int(c.s.id)].text)
	var intents: Array = _mt().intent.visit
	t.check(intents.any(func(i): return line.ends_with(_fill(str(i), "Dax-8"))), "the line ends with the visit intent phrase naming Dax-8: %s" % line)
	t.check(not intents.any(func(i): return line.ends_with(_fill(str(i), "Kiro-12"))), "and not with one naming the other friend, whatever the remark says")
	t.eq(int(c.s.mind_bias.target), target, "the bias target is the chosen friend")
	var bv: Dictionary = w.minds.bias_view(int(c.s.id))
	t.eq(str(bv.get("kind", "")), "visit", "bias_view reports the kind")
	t.eq(str(bv.get("target_name", "")), "Dax-8", "bias_view reports the target's name and no number or time")
	t.check(not bv.has("until_t") and not bv.has("target"), "bias_view exposes no time and no id")
	# A remark that names a stranger to the menu is dropped by the sim re-check; the intent phrase stays.
	var c2 := _cast("llm")
	var d2 := _open_slot(c2.w, c2.s)
	_deliver(c2.w, c2.s.id, d2.k, "visit:%d" % c2.f1.id, "Qua-77 is waiting for me.")
	_resolve(c2.w, c2.s.id, d2.k)
	var l2 := str(c2.w.minds.says[int(c2.s.id)].text)
	t.check(not l2.contains("Qua-77"), "a remark naming someone outside the allowed set is dropped")
	t.check(intents.any(func(i): return l2 == _fill(str(i), "Dax-8")), "and the line is the intent phrase alone")
	_end(t)


func test_t34b_stay_line_and_the_panel_clause(t) -> void:
	if not _api(t):
		return
	var c := _cast("llm")
	var w = c.w
	_decide(w, c.s, "stay", "A heavy sort of day.")
	var line := str(w.minds.says[int(c.s.id)].text)
	t.check((_mt().intent.stay as Array).any(func(i): return line.ends_with(str(i))), "the stay line ends with a stay intent phrase")
	var panel = load("res://view/model/being_panel.gd")
	t.check(_has_static(panel, "intent"), "BeingPanel.intent exists (view door)")
	if _has_static(panel, "intent"):
		var clause: String = panel.intent(w, int(c.s.id))
		t.eq(clause, str(_mt().intent_clause.stay), "the panel clause matches the active bias kind")
		w.t += float(_md().bias.ttl_h) + 1.0
		_mini_ticks(w, 2)  # expiry runs on relationships ticks
		t.eq(panel.intent(w, int(c.s.id)), "", "and disappears on expiry")
	_end(t)


# ---------------------------------------------------------------- 35. freshness (slice 1; bubbles are slice 2)

func test_t35_lines_go_stale(t) -> void:
	if not _api(t):
		return
	var panel = load("res://view/model/being_panel.gd")
	t.check(_has_static(panel, "voice"), "BeingPanel.voice exists (view door)")
	if not _has_static(panel, "voice"):
		_end(t)
		return
	var c := _cast("rules")
	var w = c.w
	var id: int = c.s.id
	var sh := _sol_h(w)
	for src in ["model", "rule"]:
		var limit: float = float(_md().say["show_sols_" + src])
		w.minds.says[id] = {"text": "A quiet evening.", "t": w.t, "source": src, "t_model": w.t if src == "model" else -1.0, "variant": {}}
		var t_set: float = w.t
		w.t = t_set + (limit - 0.1) * sh
		t.eq(panel.voice(w, id), "A quiet evening.", "%s line: shown while younger than %s sols" % [src, str(limit)])
		w.t = t_set + (limit + 0.1) * sh
		t.eq(panel.voice(w, id), "", "%s line: stale after %s sols" % [src, str(limit)])
		w.t = t_set
	var long_text := "x".repeat(int(_md().say.total_max_chars) + 5)
	w.minds.says[id] = {"text": long_text.substr(0, int(_md().say.total_max_chars)), "t": w.t, "source": "rule", "t_model": -1.0, "variant": {}}
	t.check(panel.voice(w, id).length() <= int(_md().say.total_max_chars), "voice() is at most say.total_max_chars long")
	_end(t)


# ---------------------------------------------------------------- 36. dead-being cleanup

func test_t36_dead_being_cleanup(t) -> void:
	if not _api(t):
		return
	var c := _cast("llm")
	var w = c.w
	var id: int = c.s.id
	_mini_to_sol(w, 3)
	_until_next_tick(w, func(sol, cell): return cell < 24)
	_why(c.s, "grief", w.t, 9, "Gone-9")
	_mini_ticks(w, 1)
	w.minds.last_visit_t[id] = {c.f1.id: w.t}
	w.minds.last_visit_t[c.f2.id] = {id: w.t, c.f1.id: w.t}
	w.minds.last_visit_t[c.f1.id] = {id: w.t}
	var d_open := _due_of(w, id)
	t.check(not d_open.is_empty(), "precondition: s has a due entry")
	t.check(w.minds.says.has(id) and w.minds.last_event_t.has(id) and w.minds.seen_why_t.has(id), "precondition: says, last_event_t and seen_why_t hold s")
	t.check(w.minds.season_seen.has(id), "precondition: season_seen holds s (it recorded the season at its slot)")
	t.check(w.minds.last_visit_t[c.f2.id].has(id) and w.minds.last_visit_t[c.f1.id].has(id), "precondition: two other beings' last_visit_t hold an entry for s")
	t.check(w.minds.outbox.any(func(r): return int(r.id) == id), "precondition: s has an outbox entry")
	_kill_being(w, c.s)
	_mini_ticks(w, 1)
	t.check(not w.minds.says.has(id), "says cleared")
	t.check(not w.minds.last_visit_t.has(id), "last_visit_t of the dead cleared")
	t.check(not w.minds.last_event_t.has(id), "last_event_t cleared")
	t.check(not w.minds.seen_why_t.has(id), "seen_why_t cleared")
	t.check(not w.minds.season_seen.has(id), "season_seen cleared")
	t.check(not w.minds.pending_open.any(func(e): return int(e.id) == id), "pending_open cleared")
	t.check(not w.minds.outbox.any(func(r): return int(r.id) == id), "outbox cleared")
	t.check(not w.minds.last_visit_t.get(int(c.f2.id), {}).has(id), "another being's last_visit_t entry for the dead id is deleted")
	var still_listed := false
	for other in w.minds.last_visit_t:
		still_listed = still_listed or w.minds.last_visit_t[other].has(id)
	t.check(not still_listed, "no being's last_visit_t holds an entry [dead id] any more")
	t.check(w.minds.last_visit_t.get(int(c.f2.id), {}).has(int(c.f1.id)), "and the living entries are left alone")
	t.check(not _due_of(w, id).is_empty(), "the due entry stays until its deadline")
	var k: int = int(d_open[0].k)
	_deliver(w, id, k, "stay")
	t.check(not w.minds.inbox.has("%d:%d" % [id, k]), "a late delivery for the dead is dropped")
	var dead0 := _rej(w, "dead")
	_resolve(w, id, k)
	t.eq(_rej(w, "dead"), dead0 + 1, "the due entry resolves as rejected `dead`")
	_end(t)


# ---------------------------------------------------------------- 37. guard placement

func test_t37a_moods_disabled_calm_slots_only(t) -> void:
	if not _api(t):
		return
	var c := _cast("llm", 1, false)
	var w = c.w
	_mini_to_sol(w, 3)
	_kill_being(w, c.f1)
	_mini(w, 1300)
	t.check(c.s.mind_slot_n > 0, "calm slots open with moods disabled")
	t.eq(int(_stat(w, "slots_opened").event), 0, "and no event slot opens (mood_why is never set without the mood module)")
	t.check(c.s.mood_why == null, "a staged death leaves mood_why null")
	var f: Dictionary = w.minds.facts_for(w, c.s)
	t.eq(int(f.get("mood", {}).get("band", -1)), 2, "facts carry mood band 2 (even) when moods are disabled")
	_end(t)


func test_t37b_relationships_disabled_does_nothing(t) -> void:
	if not _api(t):
		return
	var c := _cast("llm")
	var w = c.w
	w.relationships_enabled = false
	var before := JSON.stringify(w.stats.minds)
	for i in 1300:
		w.step()
	t.eq(JSON.stringify(w.stats.minds), before, "stats.minds unchanged after a sol of steps")
	t.eq(int(c.s.mind_slot_n), 0, "no slot opened")
	t.eq(w.minds.due.size(), 0, "nothing due")
	_end(t)


# ---------------------------------------------------------------- 39. dormant policy flag

func test_t39_policy_flag_is_dormant(t) -> void:
	if not _api(t):
		return
	t.eq(float(_md().rule.policy_gain), 0.0, "rule.policy_gain ships at 0.0")
	var c := _cast("rules")
	t.check("policy_calls" in c.w.minds, "the module exposes a policy call counter `policy_calls` (spec 5.9)")
	_mini_to_sol(c.w, 30)
	if "policy_calls" in c.w.minds:
		t.eq(int(c.w.minds.policy_calls), 0, "the policy function is never called at gain 0.0 (30 sols)")
	t.check(int(_stat(c.w, "slots_opened").calm) > 0, "while slots did open")
	_end(t)


# ---------------------------------------------------------------- 40. sanity rules as tests

## The clock chain of spec section 15, one rule per link (revision 6):
## beings.night.end_hour <= calendar.dawn_hour < dawn end (dawn_hour + time.dawn_len_h) < time.dusk_h < beings.night.start_hour
## < calendar.hours_per_sol_clock.
const CLOCK_RULES := ["clock_night_end_le_dawn", "clock_dawn_lt_dawn_end", "clock_dawn_end_lt_dusk", "clock_dusk_lt_night_start",
		"clock_night_start_lt_day_end"]


## Every sanity rule of spec section 15 as {rule id: ok} for a minds data dictionary. `ext` overrides values that live in other
## data files so a link there can be broken on a copy: night_end, night_start, dawn_hour, day_end (hours_per_sol_clock).
func _sanity(m: Dictionary, ext: Dictionary = {}) -> Dictionary:
	var r := {}
	var fs: float = float(SimData.sim().fixed_step_hours)
	var rd: Dictionary = SimData.relationships()
	var be: Dictionary = SimData.beings()
	var cal: Dictionary = SimData.calendar()
	var cells := int(floor(float(cal.sol_hours) / float(m.slot.grid_h)))
	var multiple := func(x: float) -> bool: return absf(x / fs - round(x / fs)) < 1e-6
	r["grid_equals_tick"] = absf(float(m.slot.grid_h) - float(rd.tick_h)) < 1e-12
	r["cells_per_sol_24"] = cells == 24
	r["cell_key_mult"] = int(m.slot.cell_key_mult) > cells + 1
	r["think_multiples"] = multiple.call(float(m.sim.think_h)) and multiple.call(float(m.sim.think_event_h))
	var top: float = float(be.restless.travel_base) + float(be.restless.travel_coef) * 1.0
	r["travel_cap_equals_max_plus_roam"] = absf(float(m.bias.travel_cap) - (top + float(m.bias.roam_travel_add))) < 1e-9
	r["tired_above_sleep"] = float(m.facts.tired_below) > float(be.energy.sleep_below)
	r["say_total"] = int(m.say.max_chars) + int(m.say.intent_max_chars) + 1 <= int(m.say.total_max_chars)
	r["event_window"] = float(m.sim.think_event_h) * float(SimData.sim().real_seconds_per_hour_at_1x) \
			>= float(m.driver.latency_p50_s) * float(m.driver.deadline_margin) + float(m.driver.batch_wait_s)
	r["capacity"] = int(m.sim.max_slots_per_tick) * cells >= int(m.sanity.population_design)
	var n: Dictionary = be.night
	var night_end: float = float(ext.get("night_end", n.end_hour))
	var night_start: float = float(ext.get("night_start", n.start_hour))
	var dawn_hour: float = float(ext.get("dawn_hour", cal.dawn_hour))
	var day_end: float = float(ext.get("day_end", cal.hours_per_sol_clock))
	var dawn_end: float = dawn_hour + float(m.time.dawn_len_h)
	r["clock_night_end_le_dawn"] = night_end <= dawn_hour
	r["clock_dawn_lt_dawn_end"] = dawn_hour < dawn_end
	r["clock_dawn_end_lt_dusk"] = dawn_end < float(m.time.dusk_h)
	r["clock_dusk_lt_night_start"] = float(m.time.dusk_h) < night_start
	r["clock_night_start_lt_day_end"] = night_start < day_end
	r["variants"] = int(m.rule.variants_min) >= 3 and int(m.rule.variants_min_plain) >= 2
	r["reserve_frac"] = float(m.budget.reserve_frac) > 0.0 and float(m.budget.reserve_frac) < 0.5
	r["taper_frac"] = float(m.budget.taper_below_frac) > 0.0 and float(m.budget.taper_below_frac) < 1.0
	r["calls_min_max"] = int(m.budget.calls_per_sol_min) <= int(m.budget.calls_per_sol_max)
	r["tick_fail_mult"] = float(m.balance.minds_tick_fail_mult) >= 1.0
	return r


func test_t40a_sanity_rules_hold_on_the_shipped_data(t) -> void:
	if not FileAccess.file_exists("res://data/minds.json"):
		t.check(false, "missing API: data/minds.json")
		return
	var r := _sanity(_md())
	t.check(not r.is_empty(), "the sanity rules are evaluated (%d)" % r.size())
	for k in r:
		t.check(bool(r[k]), "sanity rule %s holds on the shipped data" % k)
	# The shipped clock values themselves (5.5 <= 6 < 8.0 < 18.0 < 21.5 < 24 at the shipped data; read, not copied).
	var cal: Dictionary = SimData.calendar()
	var n: Dictionary = SimData.beings().night
	t.check(float(n.end_hour) <= float(cal.dawn_hour), "shipped: beings.night.end_hour (%s) <= calendar.dawn_hour (%s)" % [str(n.end_hour), str(cal.dawn_hour)])
	# The two non-strict/strict edges of the chain: equality passes the first link, fails the second.
	t.check(bool(_sanity(_md(), {"night_end": float(cal.dawn_hour)}).clock_night_end_le_dawn), "night.end_hour equal to dawn_hour still passes (<=)")
	var eq_dawn := _md().duplicate(true)
	eq_dawn.time.dawn_len_h = 0.0
	t.check(not bool(_sanity(eq_dawn).clock_dawn_lt_dawn_end), "dawn end equal to dawn_hour fails (the second link is strict)")


func test_t40b_each_sanity_rule_fails_on_one_broken_copy(t) -> void:
	if not FileAccess.file_exists("res://data/minds.json"):
		t.check(false, "missing API: data/minds.json")
		return
	var cal: Dictionary = SimData.calendar()
	var cells := int(floor(float(cal.sol_hours) / float(_md().slot.grid_h)))
	# {rule, path in the minds data (or [] when the broken value lives in another file and is passed in `ext`), value, ext}
	var breaks := [
		{"rule": "grid_equals_tick", "path": ["slot", "grid_h"], "value": 2.0},
		{"rule": "cells_per_sol_24", "path": ["slot", "grid_h"], "value": 2.0},
		{"rule": "cell_key_mult", "path": ["slot", "cell_key_mult"], "value": cells + 1},
		{"rule": "think_multiples", "path": ["sim", "think_h"], "value": 6.03},
		{"rule": "travel_cap_equals_max_plus_roam", "path": ["bias", "travel_cap"], "value": 0.5},
		{"rule": "tired_above_sleep", "path": ["facts", "tired_below"], "value": 20.0},
		{"rule": "say_total", "path": ["say", "total_max_chars"], "value": 100},
		{"rule": "event_window", "path": ["sim", "think_event_h"], "value": 2.0},
		{"rule": "capacity", "path": ["sim", "max_slots_per_tick"], "value": 4},
		# One failing case for each link of the clock chain (revision 6):
		{"rule": "clock_night_end_le_dawn", "path": [], "value": null, "ext": {"night_end": float(cal.dawn_hour) + 0.5}},
		{"rule": "clock_dawn_lt_dawn_end", "path": ["time", "dawn_len_h"], "value": 0.0},
		{"rule": "clock_dawn_end_lt_dusk", "path": ["time", "dawn_len_h"], "value": 13.0},
		{"rule": "clock_dusk_lt_night_start", "path": ["time", "dusk_h"], "value": 22.0},
		{"rule": "clock_night_start_lt_day_end", "path": [], "value": null, "ext": {"night_start": float(cal.hours_per_sol_clock) + 0.5}},
		{"rule": "variants", "path": ["rule", "variants_min"], "value": 2},
		{"rule": "reserve_frac", "path": ["budget", "reserve_frac"], "value": 0.6},
		{"rule": "taper_frac", "path": ["budget", "taper_below_frac"], "value": 1.5},
		{"rule": "calls_min_max", "path": ["budget", "calls_per_sol_min"], "value": 9},
		{"rule": "tick_fail_mult", "path": ["balance", "minds_tick_fail_mult"], "value": 0.5},
	]
	var covered := {}
	for b in breaks:
		covered[str(b.rule)] = true
		var copy: Dictionary = _md().duplicate(true)
		var path: Array = b.path
		if not path.is_empty():
			var node: Dictionary = copy
			for i in path.size() - 1:
				node = node[path[i]]
			node[path[path.size() - 1]] = b.value
		var r := _sanity(copy, b.get("ext", {}))
		t.check(not bool(r[b.rule]), "rule %s fails on a copy broken at %s" % [b.rule, ".".join(PackedStringArray(path)) if not path.is_empty() else str(b.get("ext", {}))])
		# A clock link fails on its own: the other links of the chain still hold on that copy.
		if str(b.rule) in CLOCK_RULES:
			for other in CLOCK_RULES:
				if other != b.rule:
					t.check(bool(r[other]), "breaking %s leaves clock link %s intact" % [b.rule, other])
	for k in _sanity(_md()):
		t.check(covered.has(k), "sanity rule %s has a failing case in this test" % k)
	t.eq(covered.size(), _sanity(_md()).size(), "the failing-case table covers exactly the rules that are evaluated")


# ---------------------------------------------------------------- SLICE 2: present, skipped with a reason

func test_s2_t06_menu_roam_quiet_visit_new_and_overflow(t) -> void:
	_skip(t, "test 6 slice-2 part: roam and quiet only when valid, roam dropped first on overflow, visit_new for a met non-friend (conditional on the 5.3 'met' definition)")


func test_s2_t08_bias_roam_visit_new_quiet(t) -> void:
	_skip(t, "test 8 slice-2 part: exact p_travel and weights for roam (+0.20); the UPPER clamp at bias.travel_cap (revision 5: only reachable through roam, so asserted here: clamp(p_mood + roam_add, floor, travel_cap) with a large positive mood term), visit_new, quiet; same-outcome draw parity for them")


func test_s2_t07_no_neighbour(t) -> void:
	_skip(t, "test 7 slice-2 part: `no_neighbour` rejection for roam/quiet when the being has lost every neighbour (rejected whole, counter, nothing in the ledger)")


func test_s2_t34_intent_roam_quiet_visit_new(t) -> void:
	_skip(t, "test 34 for roam, quiet, visit_new: the displayed line contains the sim's intent phrase and the panel clause matches")


func test_s2_t35_bubbles(t) -> void:
	_skip(t, "test 35 bubble cases: none above driver.speed_gate_x, none for a lone being, at most view.bubbles_max chosen by priority")
