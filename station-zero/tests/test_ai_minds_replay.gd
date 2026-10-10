extends "res://tests/minds_lib.gd"
## Task 6b, step 3 (tests first, red): ledger, replay and adversarial provider tests. Spec docs/specs/ai-minds.md revision 4,
## section 14 tests 11 to 16 and 38 (slice 1; the `roam` adversary of test 16(b) is slice 2 and is skipped below).
##
## Method: a six-being colony stepped with the REAL world step (`w.step()`, so beings act and a bias can change behaviour).
## A test-local mini driver (`_drive`) plays the part of the driver outside sim/: it reads `w.minds.outbox`, asks the scripted
## mock provider (tests/mock_provider.gd, generator seeded with tests.mock_seed) and calls `w.minds.deliver` between steps. The
## scenario (`_scenario`) injects a fresh grief why on every adult every 8 sim hours, so event slots (and so requests) exist; the
## same function runs in replay worlds, which have no driver. No network anywhere.
##
## Equality is judged on `_table(w)`: a digest of every being's room, state, energy and wait, the colony stocks and the death
## counters (the headless stand-in for the printed balance table; tests 1 to 3 use the real table).

const STEPS := 1480  # three sols of 0.05 h steps


func _colony(mode: String, seed_in: int = 11, extra: Dictionary = {}) -> Variant:
	var w = _world(mode, seed_in, true, extra)
	var rooms := [HAB, WORK, GREEN, HAB, COMMS, HAB]
	for i in 6:
		var b = _being(w, rooms[i])
		b.persona.traits["restless"] = 0.3 + 0.1 * float(i)
		b.persona.traits["sociability"] = 0.4 + 0.1 * float(i % 3)
		b.energy = 95.0
	_friends(w, 1, 2)
	_friends(w, 1, 3)
	_friends(w, 4, 2)
	_friends(w, 5, 1)
	return w


func _scenario(w, i: int) -> void:
	if i % 160 != 5:
		return
	for b in w.beings:
		_why(b, "grief", w.t, 99, "Gone-99")


func _drive(w, mock, st: Dictionary) -> void:
	for r in w.minds.outbox:
		var key := "%d:%d" % [int(r.id), int(r.k)]
		if st.seen.has(key):
			continue
		st.seen[key] = true
		var req: Dictionary = (r as Dictionary).duplicate()
		req["open_step"] = w.step_index
		var a: Dictionary = mock.answer_for(req)
		if bool(a.fail) or a.entry.is_empty():
			continue
		st.count = int(st.count) + 1
		var e: Dictionary = a.entry
		if int(st.corrupt_every) > 0 and int(st.count) % int(st.corrupt_every) == 0:
			e["choice"] = "no_such_key"
		if int(st.badsay_every) > 0 and int(st.count) % int(st.badsay_every) == 0:
			e["say"] = "Bad 7 digits here."
		st.pending.append({"at": w.step_index + int(a.steps), "entry": e})
	var rest: Array = []
	for p in st.pending:
		if int(p.at) <= w.step_index:
			w.minds.deliver(w, p.entry)
		else:
			rest.append(p)
	st.pending = rest


## Steps the colony; `mock` null means no driver (rules, off, replay).
func _run(w, steps: int, mock = null, opts: Dictionary = {}) -> void:
	var st := {"seen": {}, "pending": [], "count": 0, "corrupt_every": int(opts.get("corrupt_every", 0)), "badsay_every": int(opts.get("badsay_every", 0))}
	for i in steps:
		_scenario(w, i)
		w.step()
		if mock != null and w.minds != null:
			_drive(w, mock, st)


func _table(w) -> String:
	var parts: Array = [_digest(w), w.colony.oxygen, w.colony.food, w.colony.ice, w.stats.deaths]
	return JSON.stringify(parts).sha256_text()


func _mock(behaviour: String = "scripted") -> Variant:
	var m = load("res://tests/mock_provider.gd").new()
	m.behaviour = behaviour
	return m


func _parity(w) -> Dictionary:
	var s: Dictionary = w.stats.minds
	return {"table": _table(w), "ledger_hash": w.minds.ledger_hash(), "ledger_len": int(s.ledger_len), "applied_model": int(s.applied_model),
			"applied_rule": int(s.applied_rule), "bias_applied": s.bias_applied, "bias_skipped_asleep": int(s.bias_skipped_asleep),
			"says_model": int(s.says_model), "says_rule": int(s.says_rule), "slots_opened": s.slots_opened,
			"slots_rule_only": int(s.slots_rule_only), "slot_dropped_carry": int(s.slot_dropped_carry),
			"calm_skipped_event": int(s.calm_skipped_event), "requests_built": int(s.requests_built)}


func _live_and_replay(seed_in: int = 11, opts: Dictionary = {}) -> Dictionary:
	var live = _colony("llm", seed_in)
	_run(live, STEPS, _mock(), opts)
	var ledger: Array = live.minds.ledger.duplicate(true)
	var rep = _colony("llm", seed_in, {"minds_replay": ledger})
	_run(rep, STEPS)
	return {"live": live, "rep": rep, "ledger": ledger}


# ---------------------------------------------------------------- 11. replay

func test_t11_replay_reproduces_a_live_run(t) -> void:
	if not _api(t):
		return
	t.eq(int(load("res://tests/mock_provider.gd").mock_seed()), 1013, "the mock provider is seeded with tests.mock_seed (1013)")
	var r := _live_and_replay()
	t.check(r.ledger.size() > 0, "the live run produced applied decisions (the ledger is not empty), so the test is not vacuous")
	t.check(int(r.live.stats.minds.applied_model) > 0, "at least one behaviour-changing model decision was applied")
	t.eq(_table(r.rep), _table(r.live), "table hash: replay equals the live run")
	t.eq(r.rep.minds.ledger_hash(), r.live.minds.ledger_hash(), "ledger_hash equal")
	t.eq(_rng_state(r.rep), _rng_state(r.live), "SimRng state and the next five draws equal")
	_end(t)


func test_t12_replay_twice_and_live_then_replay_are_identical(t) -> void:
	if not _api(t):
		return
	var r := _live_and_replay()
	var rep2 = _colony("llm", 11, {"minds_replay": r.ledger.duplicate(true)})
	_run(rep2, STEPS)
	var a: String = _table(r.live)
	t.eq(_table(r.rep), a, "live == replay 1")
	t.eq(_table(rep2), a, "live == replay 2")
	t.eq(_table(rep2), _table(r.rep), "replay 1 == replay 2, byte for byte")
	t.eq(JSON.stringify(r.rep.stats.minds), JSON.stringify(rep2.stats.minds), "and the stats agree")
	_end(t)


# ---------------------------------------------------------------- 13. sensitivity

func test_t13_one_changed_choice_changes_the_table(t) -> void:
	if not _api(t):
		return
	# A being that never travels under `stay` (multiplier 0.0, a 10,000 h expiry, moods off so the floor is 0.0) and travels
	# freely (restless 1.0, chance 0.4 a decision) under `carry_on`: the effect of the one early choice is certain.
	_cfg_edit("minds.json", ["bias", "stay_travel_mult"], 0.0)
	_cfg_edit("minds.json", ["bias", "ttl_h"], 10000.0)
	var tables := []
	for choice in ["stay", "carry_on"]:
		var entry := {"v": 1, "id": 1, "k": 1, "apply_step": 0, "choice": choice, "say": "", "model": "mock"}
		var w = _world("llm", 5, false, {"minds_replay": [entry]})
		var b = _being(w, HAB)
		b.persona.traits["restless"] = 1.0
		b.energy = 100.0
		_being(w, WORK)
		for i in STEPS:
			w.step()
		tables.append([_table(w), b.building_id, b.mind_bias != null])
	t.check(tables[0][2], "with the stay entry the bias was applied")
	t.eq(tables[0][1], HAB, "the stay being never left its room")
	t.check(tables[0][0] != tables[1][0], "changing the one early ledger choice changes the table hash")
	_end(t)


# ---------------------------------------------------------------- 14. text-only change

func test_t14_changing_every_say_changes_nothing_behavioural(t) -> void:
	if not _api(t):
		return
	var r := _live_and_replay()
	t.check(r.ledger.size() > 0, "the ledger is not empty")
	for variant in ["Different words entirely.", "Bad 99 shape\nwith newline", ""]:
		var altered: Array = r.ledger.duplicate(true)
		for e in altered:
			e["say"] = variant
		var w = _colony("llm", 11, {"minds_replay": altered})
		_run(w, STEPS)
		t.eq(_table(w), _table(r.rep), "say %s: the table hash is unchanged" % JSON.stringify(variant))
		t.eq(w.minds.ledger_hash(), r.rep.minds.ledger_hash(), "say %s: the ledger_hash is unchanged" % JSON.stringify(variant))
	_end(t)


# ---------------------------------------------------------------- 15. late delivery and the tie rule

func test_t15_deadline_step_minus_one_is_applied_and_the_deadline_step_is_dropped(t) -> void:
	if not _api(t):
		return
	var results := {}
	for at_offset in [-1, 0]:
		var c := _cast("llm")
		var w = c.w
		var d := _open_slot(w, c.s)
		var dl: int = int(d.deadline_step)
		var guard := 0
		while int(w.step_index) < dl + at_offset and guard < 5000:
			_mini(w)
			guard += 1
		t.eq(int(w.step_index), dl + at_offset, "stepped to deadline_step %+d" % at_offset)
		var stored = _deliver(w, c.s.id, d.k, "stay", "Steady.")
		results[at_offset] = {"stored": stored, "w": w, "c": c, "k": d.k}
	var a: Dictionary = results[-1]
	_resolve(a.w, a.c.s.id, a.k)
	t.check(bool(a.stored), "deliver at deadline_step - 1 is stored")
	t.check(a.c.s.mind_bias != null, "and applied at resolution")
	var b: Dictionary = results[0]
	_resolve(b.w, b.c.s.id, b.k)
	t.check(not bool(b.stored), "deliver at deadline_step is dropped")
	t.check(b.c.s.mind_bias == null, "and never applied, even though resolution waits for the next relationships tick")
	t.eq(b.w.minds.ledger.size(), 0, "a dropped delivery leaves no ledger line")
	# A ledger without the dropped one replays equal: the late world equals a rules world stepped the same way.
	var rules := _cast("rules")
	_open_slot(rules.w, rules.s)
	_resolve(rules.w, rules.s.id, 1)
	t.eq(_digest(b.w), _digest(rules.w), "the world with the dropped delivery equals the one that got none")
	_end(t)


func test_t15b_resolution_waits_for_the_first_relationships_tick(t) -> void:
	if not _api(t):
		return
	var c := _cast("llm")
	var w = c.w
	var d := _open_slot(w, c.s)
	_deliver(w, c.s.id, d.k, "stay", "Steady.")
	var dl: int = int(d.deadline_step)
	var resolved_at := -1
	var guard := 0
	var ticks0: int = int(w.relationships.ticks)
	while resolved_at < 0 and guard < 5000:
		_mini(w)
		guard += 1
		if _due_of(w, c.s.id).is_empty():
			resolved_at = int(w.step_index)
	t.check(resolved_at >= dl, "resolved at or after the deadline step (%d >= %d)" % [resolved_at, dl])
	t.check(int(w.relationships.ticks) > ticks0, "and on a relationships tick")
	_end(t)


# ---------------------------------------------------------------- 16. adversarial providers (slice 1: a, c, d, e, f)

func test_t16_adversarial_providers(t) -> void:
	if not _api(t):
		return
	var rules = _colony("rules")
	_run(rules, STEPS)
	var base: String = _table(rules)
	for adv in [["always_invalid", true], ["never", true], ["late", true], ["always_stay", false], ["always_first_visit", false]]:
		var w = _colony("llm")
		var m = _mock(str(adv[0]))
		_run(w, STEPS, m)
		t.check(w.step_index == STEPS, "%s: the run completed without an exception" % adv[0])
		t.check(m.calls > 0 or str(adv[0]) == "never", "%s: the provider was asked" % adv[0])
		if bool(adv[1]):
			t.eq(_table(w), base, "%s: equals the rules run exactly" % adv[0])
			t.eq(int(w.stats.minds.applied_model), 0, "%s: nothing applied" % adv[0])
		else:
			t.check(int(w.stats.minds.applied_model) > 0, "%s: decisions were applied" % adv[0])
			t.check(w.colony.pop() > 0, "%s: the colony is alive" % adv[0])
	_end(t)


# ---------------------------------------------------------------- 38. replay parity of the parity set only

func test_t38_parity_set_matches_and_live_only_counters_may_differ(t) -> void:
	if not _api(t):
		return
	_cfg_edit("minds.json", ["sim", "apply_max_per_sol"], 1)
	var r := _live_and_replay(11, {"corrupt_every": 4, "badsay_every": 3})
	var pl := _parity(r.live)
	var pr := _parity(r.rep)
	for k in pl:
		t.eq(JSON.stringify(pr[k]), JSON.stringify(pl[k]), "parity set: %s equal between live and replay" % k)
	var sl: Dictionary = r.live.stats.minds
	var sr: Dictionary = r.rep.stats.minds
	var live_rejected := 0
	for k in sl.rejected:
		live_rejected += int(sl.rejected[k])
	var rep_rejected := 0
	for k in sr.rejected:
		rep_rejected += int(sr.rejected[k])
	t.check(live_rejected + int(sl.say_rejected) + int(sl.apply_dropped_cap) > 0, "the live run really had rejections, remark drops or cap drops")
	t.eq(rep_rejected, 0, "a replay shows no rejection (the ledger holds only applied decisions)")
	t.eq(int(sr.apply_dropped_cap), 0, "and no cap drop")
	t.check(int(sr.slot_no_answer) >= int(sl.slot_no_answer), "the live rejections show up in the replay as slot_no_answer (never fewer)")
	t.check(JSON.stringify([sl.rejected, sl.say_rejected, sl.apply_dropped_cap, sl.slot_no_answer]) != JSON.stringify([sr.rejected, sr.say_rejected, sr.apply_dropped_cap, sr.slot_no_answer]),
			"the live-only counters are allowed to differ, and here they do")
	_end(t)


# ---------------------------------------------------------------- slice 2

func test_s2_t16b_always_roam_adversary(t) -> void:
	_skip(t, "test 16 / G1(b): the always-`roam` provider (roam is a slice 2 menu entry; slice 1 runs a, c, d, e, f)")
