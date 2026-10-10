extends "res://tests/minds_lib.gd"
## Task 6b, step 3 (tests first, red): the driver side, headless, with mocks only. Spec docs/specs/ai-minds.md revision 6,
## section 14 tests 23 to 29 (slice 1 cases; the slice 2 budget cases of test 23 are skipped at the end). No network: the only
## provider is tests/mock_provider.gd and `Driver` is handed it. Everything under minds/ is OUTSIDE sim/.
##
## API ASSUMED (the spec names the files and the behaviours, not the signatures; the implementer should match or tell the test
## author). All scripts are reached with load(); static functions are called on the script.
##   minds/budget.gd   Budget.new(budget_cfg: Dictionary)
##       check(req, ctx) -> String          "" when a call may go, else the refusal reason: prices, calls_per_sol, in_flight,
##                                          tokens_day. req {est_in: int, beings: int, max_out: int} (revision 6: the driver passes
##                                          prompt.max_out_tokens_per_being as max_out); ctx {utc_day: int, sol: int, in_flight: int}
##       reserve(req, ctx) -> int           charges the worst case exactly: est_in + beings x max_out, returns a handle
##       settle(handle, in_tokens, out_tokens)    reconciles the reservation to actuals
##       charge_tokens(utc_day, n)          test seam: books n tokens on a day
##       tokens_used(utc_day) -> int, allowance(utc_day) -> int    (the taper of section 8)
##       save() -> Dictionary, restore(Dictionary)                 persistence across a restart (user://minds_meter.json content)
##   minds/breaker.gd  Breaker.new(driver_cfg: Dictionary)
##       allow(now_s) -> bool, failure(now_s), success(now_s), status(code, now_s, retry_after_s = 0.0)
##       state: "closed" | "open" | "half_open"; disabled: bool (401/403, permanent for the session); paused_until: float
##   minds/prompt.gd   Prompt (static)
##       build(requests: Array, text: Dictionary, cfg: Dictionary) -> {static_prefix, body, est_in, trimmed: Array of field names
##                                                                    in the order they were dropped}
##       parse(reply: String, requested: Array) -> Dictionary  slot -> {ok: bool, choice: int, say: String}
##   minds/driver.gd   Driver.new(provider, cfg: Dictionary = the whole data/minds.json)
##       pump(world, now_s: float, speed_x: float) -> void     reads world.minds.outbox, sends, delivers (fake clock in tests)
##       static skip_reason(deadline_step, step_index, speed_x, latency_p50_s = 1.5) -> String   "" means send
##       static resolve_mode(requested: String, key_present: bool, prices_set: bool, adapter_present: bool) -> String
##       budget: Budget, breaker: Breaker, skipped: Dictionary reason -> count
##   Request records in world.minds.outbox: {id, k, deadline_step, facts, menu (an Array of option KEYS), priority}.

func _drv_api(t) -> bool:
	var missing: Array[String] = []
	for f in ["budget", "breaker", "prompt", "driver", "filter", "provider"]:
		if not FileAccess.file_exists("res://minds/%s.gd" % f):
			missing.append("minds/%s.gd" % f)
	if not FileAccess.file_exists("res://data/minds.json"):
		missing.append("data/minds.json")
	if not FileAccess.file_exists("res://data/minds_text.json"):
		missing.append("data/minds_text.json")
	t.check(missing.is_empty(), "missing API: " + ", ".join(PackedStringArray(missing)))
	return missing.is_empty()


func _budget_cfg(prices: bool = true) -> Dictionary:
	var c: Dictionary = _md().budget.duplicate(true)
	if prices:
		c["price_in_per_mtok"] = 1.0
		c["price_out_per_mtok"] = 4.0
	return c


# ---------------------------------------------------------------- 23. budget meter (slice 1 caps)

func test_t23a_prices_unset_refuses_everything(t) -> void:
	if not _drv_api(t):
		return
	var b = load("res://minds/budget.gd").new(_budget_cfg(false))
	t.eq(float(_md().budget.price_in_per_mtok), 0.0, "the shipped prices are 0.0 (unset)")
	t.eq(b.check(_req(100, 1), {"utc_day": 1, "sol": 1, "in_flight": 0}), "prices", "unset prices refuse every call (fail closed)")
	var half := _budget_cfg(true)
	half["price_out_per_mtok"] = 0.0
	var b2 = load("res://minds/budget.gd").new(half)
	t.eq(b2.check(_req(100, 1), {"utc_day": 1, "sol": 1, "in_flight": 0}), "prices", "either price at 0 refuses")
	var ok = load("res://minds/budget.gd").new(_budget_cfg(true))
	t.eq(ok.check(_req(100, 1), {"utc_day": 1, "sol": 1, "in_flight": 0}), "", "with both prices set a small call may go")


## A budget request as the driver passes it (spec 5.9, revision 6): {est_in, beings, max_out}; max_out is
## prompt.max_out_tokens_per_being, a key of the PROMPT section that the driver adds to every check and reserve.
func _req(est_in: int, beings: int) -> Dictionary:
	return {"est_in": est_in, "beings": beings, "max_out": int(_md().prompt.max_out_tokens_per_being)}


func test_t23b_day_tokens_reserve_and_worst_case_reconcile(t) -> void:
	if not _drv_api(t):
		return
	var cfg := _budget_cfg()
	var Budget = load("res://minds/budget.gd")
	var ctx := {"utc_day": 100, "sol": 1, "in_flight": 0}
	var req := _req(1070, 4)
	# Worst case, exactly: est_in + beings x max_out (spec 5.9: 1070 + 4 x 70 = 1350 at the shipped max_out).
	var worst: int = int(req.est_in) + int(req.beings) * int(req.max_out)
	t.eq(int(req.max_out), 70, "prompt.max_out_tokens_per_being ships at 70")
	t.eq(worst, 1350, "the worst case of the spec example is 1350")
	var b = Budget.new(cfg)
	var h: int = b.reserve(req, ctx)
	t.eq(b.tokens_used(100), worst, "the reservation charges exactly est_in + beings x max_out")
	b.settle(h, 1000, 150)
	t.eq(b.tokens_used(100), 1150, "and is reconciled to the actual tokens on response")
	# The refusal rule: tokens_day when tokens_used + worst > floor(tokens_day x (1 - reserve_frac)); 270000 at shipped values.
	var line: int = int(floor(float(cfg.tokens_day) * (1.0 - float(cfg.reserve_frac))))
	t.eq(line, 270000, "the reserve line is 270000 at the shipped values")
	# Exactly on the line goes, one token more is refused (fresh meters; the sol differs from the reservations above).
	var on_line = Budget.new(cfg)
	on_line.charge_tokens(100, line - worst)
	t.eq(on_line.tokens_used(100), line - worst, "precondition: used + worst == the line")
	t.eq(on_line.check(req, {"utc_day": 100, "sol": 2, "in_flight": 0}), "", "used + worst == 270000: the call goes")
	var over = Budget.new(cfg)
	over.charge_tokens(100, line - worst + 1)
	t.eq(over.check(req, {"utc_day": 100, "sol": 2, "in_flight": 0}), "tokens_day", "used + worst == 270001: refused with tokens_day")
	var under = Budget.new(cfg)
	under.charge_tokens(100, line - worst - 1)
	t.eq(under.check(req, {"utc_day": 100, "sol": 2, "in_flight": 0}), "", "one token below the line also goes")
	# Open reservations count as used: one reservation outstanding takes `worst` of the room.
	var held = Budget.new(cfg)
	held.reserve(req, ctx)
	held.charge_tokens(100, line - 2 * worst)  # used = reservation (worst) + this = line - worst
	t.eq(held.tokens_used(100), line - worst, "precondition: an open reservation is part of tokens_used")
	t.eq(held.check(req, {"utc_day": 100, "sol": 2, "in_flight": 0}), "", "reservation counted: on the line still goes")
	held.charge_tokens(100, 1)
	t.eq(held.check(req, {"utc_day": 100, "sol": 2, "in_flight": 0}), "tokens_day", "reservation counted: one token more is refused")
	# The worst case grows with beings and max_out (not a fixed number): a bigger batch is refused where a smaller one goes.
	var edge = Budget.new(cfg)
	edge.charge_tokens(100, line - worst)
	var small := _req(1070, 3)
	t.eq(edge.check(small, {"utc_day": 100, "sol": 2, "in_flight": 0}), "", "a smaller batch (3 beings) fits where the 4-being worst case just fits")
	var big := _req(1070, 5)
	t.eq(edge.check(big, {"utc_day": 100, "sol": 2, "in_flight": 0}), "tokens_day", "and a bigger one (5 beings) does not")
	# UTC day rollover.
	t.eq(over.tokens_used(101), 0, "a new UTC day starts at zero")
	t.eq(over.check(req, {"utc_day": 101, "sol": 2, "in_flight": 0}), "", "and calls may go again")


func test_t23c_calls_per_sol_in_flight_and_taper(t) -> void:
	if not _drv_api(t):
		return
	var cfg := _budget_cfg()
	var b = load("res://minds/budget.gd").new(cfg)
	var req := _req(100, 1)
	var calls_max: int = int(cfg.calls_per_sol_max)
	for i in calls_max:
		t.eq(b.check(req, {"utc_day": 5, "sol": 7, "in_flight": 0}), "", "call %d in the sol may go" % (i + 1))
		b.reserve(req, {"utc_day": 5, "sol": 7, "in_flight": 0})
	t.eq(b.check(req, {"utc_day": 5, "sol": 7, "in_flight": 0}), "calls_per_sol", "call %d in the same sol is refused" % (calls_max + 1))
	t.eq(b.check(req, {"utc_day": 5, "sol": 8, "in_flight": 0}), "", "the next sol resets the count")
	t.eq(b.check(req, {"utc_day": 5, "sol": 8, "in_flight": int(cfg.max_in_flight)}), "in_flight", "requests in flight at the cap are refused")
	# The taper: allowance = max(calls_per_sol_min, round(calls_per_sol_max x remaining / (taper_below_frac x tokens_day))).
	var cap: int = int(cfg.tokens_day)
	var frac: float = float(cfg.taper_below_frac)
	for remaining_share in [0.9, 0.5, 0.4, 0.3, 0.2, 0.05]:
		var b2 = load("res://minds/budget.gd").new(cfg)
		var remaining: float = float(cap) * float(remaining_share)
		b2.charge_tokens(9, int(float(cap) - remaining))
		var want: int = calls_max
		if remaining < frac * float(cap):
			want = maxi(int(cfg.calls_per_sol_min), int(round(float(calls_max) * remaining / (frac * float(cap)))))
		t.eq(b2.allowance(9), want, "taper at %.0f%% remaining: allowance %d" % [remaining_share * 100.0, want])
		t.check(b2.allowance(9) >= int(cfg.calls_per_sol_min), "never below calls_per_sol_min")


func test_t23d_meter_survives_a_restart(t) -> void:
	if not _drv_api(t):
		return
	var cfg := _budget_cfg()
	var b = load("res://minds/budget.gd").new(cfg)
	b.charge_tokens(12, 123456)
	var saved: Dictionary = b.save()
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	t.check(parsed is Dictionary, "the saved meter is plain JSON")
	var b2 = load("res://minds/budget.gd").new(cfg)
	b2.restore(parsed)
	t.eq(b2.tokens_used(12), 123456, "a restart does not reset the day's tokens")
	t.eq(b2.tokens_used(13), 0, "and a later day is still empty")


# ---------------------------------------------------------------- 24. breaker

func test_t24_breaker(t) -> void:
	if not _drv_api(t):
		return
	var dcfg: Dictionary = _md().driver
	var br = load("res://minds/breaker.gd").new(dcfg)
	var now := 1000.0
	t.check(br.allow(now), "closed at the start")
	br.failure(now)
	br.failure(now)
	t.check(br.allow(now), "two failures: still closed")
	br.failure(now)
	t.eq(str(br.state), "open", "opens at the third failure (driver.breaker_fails)")
	t.check(not br.allow(now + 1.0), "no calls while open")
	var later: float = now + float(dcfg.breaker_open_s)
	t.check(br.allow(later), "after breaker_open_s one probe call is allowed (half open)")
	t.check(not br.allow(later), "and only one probe")
	br.success(later)
	t.eq(str(br.state), "closed", "a successful probe closes it")
	t.check(br.allow(later + 1.0), "and calls go again")
	# A failed probe re-opens.
	for i in 3:
		br.failure(later + 2.0)
	t.check(br.allow(later + 2.0 + float(dcfg.breaker_open_s)), "half-open probe again")
	br.failure(later + 2.0 + float(dcfg.breaker_open_s))
	t.eq(str(br.state), "open", "a failed probe re-opens it")
	# 401 is permanent for the session.
	var b2 = load("res://minds/breaker.gd").new(dcfg)
	b2.status(401, now)
	t.check(bool(b2.disabled), "401 disables for the session")
	t.check(not b2.allow(now + 100000.0), "and never allows a call again")
	var b3 = load("res://minds/breaker.gd").new(dcfg)
	b3.status(403, now)
	t.check(bool(b3.disabled), "403 likewise")
	# 429 honours a capped Retry-After.
	var cap: float = float(dcfg.retry_after_max_s)
	var b4 = load("res://minds/breaker.gd").new(dcfg)
	b4.status(429, now, cap * 10.0)
	t.near(float(b4.paused_until), now + cap, 1e-9, "Retry-After is capped at driver.retry_after_max_s")
	t.check(not b4.allow(now + cap - 1.0), "paused until then")
	t.check(b4.allow(now + cap + 1.0), "and allowed after")
	var b5 = load("res://minds/breaker.gd").new(dcfg)
	b5.status(429, now, 30.0)
	t.near(float(b5.paused_until), now + 30.0, 1e-9, "a shorter Retry-After is honoured as given")


# ---------------------------------------------------------------- 25. failure matrix

func _voices(w) -> Array:
	var panel = load("res://view/model/being_panel.gd")
	var out: Array = []
	for b in w.beings:
		out.append([int(b.id), panel.voice(w, int(b.id)), panel.intent(w, int(b.id))])
	return out


## A cast world with moments on every being at the same tick (so requests exist), stepped through a driver on a fake clock.
func _driven(kinds: Array, opts: Dictionary = {}) -> Dictionary:
	_cfg_edit("minds.json", ["budget", "price_in_per_mtok"], 1.0)
	_cfg_edit("minds.json", ["budget", "price_out_per_mtok"], 4.0)
	var c := _cast("llm", 3)
	var w = c.w
	var mock = load("res://tests/mock_provider.gd").new()
	mock.kinds = kinds
	for k in opts:
		mock.set(k, opts[k])
	var drv = load("res://minds/driver.gd").new(mock, _md())
	_mini_to_sol(w, 3)
	_until_next_tick(w, func(sol, cell): return cell < 24)
	for b in w.beings:
		_why(b, "grief", w.t, 99, "Gone-99")
	for i in 700:
		_mini(w)
		drv.pump(w, float(w.step_index) * _real_s_per_step(1.0), 1.0)
	return {"w": w, "mock": mock, "drv": drv, "c": c}


func _until_next_tick(w, pred: Callable) -> bool:
	var guard := 0
	while guard < 100000:
		if float(w.relationships.acc_h) + w.fixed_step >= _tickh() - SimWorld.STEP_EPS:
			var tn: float = w.t + w.fixed_step
			var sol: int = int(w.clock.sol_index(tn))
			var cell := int(floor((tn - float(sol - 1) * _sol_h(w)) / _grid(w) + SimWorld.STEP_EPS))
			if pred.call(sol, cell):
				return true
		_mini(w)
		guard += 1
	return false


func test_t25_failure_matrix_ends_in_the_rule_answer(t) -> void:
	if not _drv_api(t) or not _api(t):
		return
	var rules := _cast("rules", 3)
	_mini_to_sol(rules.w, 3)
	_until_next_tick(rules.w, func(sol, cell): return cell < 24)
	for b in rules.w.beings:
		_why(b, "grief", rules.w.t, 99, "Gone-99")
	_mini(rules.w, 700)
	var base := _voices(rules.w)
	t.check(not base.is_empty(), "the rules run has beings")
	for kind in ["timeout", "500", "malformed", "empty"]:
		var r := _driven([kind, kind, kind, kind, kind, kind, kind, kind])
		t.eq(int(r.w.stats.minds.applied_model), 0, "%s: nothing applied" % kind)
		t.eq(_voices(r.w), base, "%s: the view strings equal the no-failure rules run" % kind)
		_restore()
	# A choice number outside the menu (bad choice): the entry is dropped, the rule answer stands.
	var r1 := _driven([], {"choice_number": 99})
	t.eq(int(r1.w.stats.minds.applied_model), 0, "bad choice: nothing applied")
	t.eq(_voices(r1.w), base, "bad choice: the view strings equal the rules run")
	_restore()
	# A valid choice with a remark that fails the filter: the choice is kept, the line is the intent phrase alone.
	var r2 := _driven([], {"choice_number": 1, "say_override": "Bad 7 digits here."})
	var any_intent_only := false
	for b in r2.w.beings:
		var line := str(r2.w.minds.says.get(int(b.id), {}).get("text", ""))
		if line != "" and not line.contains("Bad 7"):
			any_intent_only = true
		t.check(not line.contains("Bad 7"), "filtered remark: the digit remark is never displayed (%s)" % line)
	t.check(int(r2.w.stats.minds.say_rejected) > 0 or not any_intent_only, "filtered remark: the sim counted a dropped remark")
	_restore()
	# A partial batch: the provider answers only the first slot of a batch. The unanswered beings keep the rule answer (their
	# view strings equal the rules run), the world keeps running.
	var r3 := _driven([], {"partial": true})
	t.check(r3.mock.calls > 0, "partial batch: the provider was asked")
	var multi := 0
	var sent_slots := {}
	for body in r3.mock.sent:
		var slots: Array = (body as Dictionary).get("slots", [])
		multi += 1 if slots.size() >= 2 else 0
		for sl in slots:
			sent_slots[str(sl.slot)] = true
	t.check(multi >= 1, "partial batch: at least one call carried two or more slots, so a partial answer is possible (%d such calls)" % multi)
	var answered := {}
	for e in r3.w.minds.ledger:
		answered[int(e.id)] = true
	var unanswered := 0
	var base_by_id := {}
	for v in base:
		base_by_id[int(v[0])] = v
	for v in _voices(r3.w):
		var id := int(v[0])
		if answered.has(id):
			continue
		unanswered += 1
		t.eq(v, base_by_id.get(id, []), "partial batch: being %d has no applied answer and shows exactly the rules-run strings" % id)
		t.eq(str(r3.w.minds.says.get(id, {}).get("source", "")), "rule", "partial batch: being %d line is the rule answer" % id)
	t.check(unanswered >= 1, "partial batch: at least one being was left unanswered (%d)" % unanswered)
	t.check(answered.size() < sent_slots.size(), "partial batch: fewer beings were answered than were asked (%d of %d)" % [answered.size(), sent_slots.size()])
	t.check(int(r3.w.stats.minds.slots_opened.event) > 0, "partial batch: event slots opened and the world kept running")
	_end(t)


# ---------------------------------------------------------------- 26. prompt builder

func _facts_batch(n: int) -> Array:
	var out: Array = []
	var seed_i := 1
	while out.size() < n and seed_i < 40:
		var w = SimWorld.new(seed_i, {"minds_mode": "llm"})
		for b in w.beings:
			var f: Dictionary = w.minds.facts_for(w, b)
			out.append({"id": int(b.id), "k": 1, "facts": f, "menu": w.minds.menu_for(w, b), "priority": [2, -1.0, 0]})
		seed_i += 1
	return out.slice(0, n)


## Every chart term the built prompt must never hold (spec 5.7, 6.3, test 26): the 12 sign names, the data list
## filter.chart_terms, "moon" and "birth sign" (case-insensitive substrings; the scan is deliberately stricter than whole words).
func _chart_terms() -> Array[String]:
	var banned: Array[String] = ["deimos", "moon", "phobos", "chart", "horoscope", "zodiac", "birth sign"]
	for s in SimData.signs():
		banned.append(str(s.name).to_lower())
	var listed: Variant = _mt().get("filter", {}).get("chart_terms", [])
	for w in listed:
		var low := str(w).to_lower()
		if not (low in banned):
			banned.append(low)
	return banned


func test_t26_prompt_builder(t) -> void:
	if not _drv_api(t) or not _api(t):
		return
	var P = load("res://minds/prompt.gd")
	var text: Dictionary = _mt()
	var cfg: Dictionary = _md().duplicate(true)
	var batch1 := _facts_batch(4)
	var batch2 := _facts_batch(8).slice(4, 8)
	var a: Dictionary = P.build(batch1, text, cfg)
	var b: Dictionary = P.build(batch2, text, cfg)
	t.eq(str(a.static_prefix), str(b.static_prefix), "the static prefix is byte-equal across calls")
	t.check(str(a.static_prefix) != "", "and not empty")
	t.check(str(a.static_prefix).contains(str(int(cfg.say.max_chars))), "the character limit in the text equals say.max_chars")
	var cfg2: Dictionary = cfg.duplicate(true)
	cfg2.say.max_chars = 45
	var c2: Dictionary = P.build(batch1, text, cfg2)
	t.check(str(c2.static_prefix).contains("45") and not str(c2.static_prefix).contains(" 60 "), "change the key and the text follows")
	t.check(int(a.est_in) <= int(cfg.prompt.max_in_tokens), "the size estimate is at or under prompt.max_in_tokens (%d)" % int(a.est_in))
	var rules_text: Variant = text.prompt.output_rules
	for piece in _values_of(rules_text):
		t.check(str(a.static_prefix).contains(str(piece)) or str(a.body).contains(str(piece)), "the output-rules text is present: %s" % str(piece).substr(0, 40))
	# Slot strings are "<id>:<k>" (spec 5.9): the body names each requested slot that way, because the reply echoes it.
	for r in batch1:
		t.check(str(a.body).contains("%d:%d" % [int(r.id), int(r.k)]), "the body names the slot \"%d:%d\" (the id:k form)" % [int(r.id), int(r.k)])
	# The provider interface lives in minds/provider.gd (5.9, revision 6).
	t.check(FileAccess.file_exists("res://minds/provider.gd"), "the provider interface file is minds/provider.gd")
	# No chart term anywhere: the authored text itself (system block, output rules, being block) and the whole built prompt
	# (static prefix + body) for 200 beings. The system block was reworded in revision 6, so the banned list is kept whole.
	var banned := _chart_terms()
	var authored := ""
	for key in ["system", "output_rules", "being"]:
		authored += "\n".join(PackedStringArray(_values_of(text.prompt.get(key, "")))) + "\n"
	var low_authored := authored.to_lower()
	for word in banned:
		t.check(not low_authored.contains(word), "prompt.system / output_rules / being hold no chart term (%s)" % word)
	var all := _facts_batch(200)
	t.check(all.size() >= 200, "200 beings were built (%d)" % all.size())
	var i := 0
	var leaked: Array[String] = []
	while i < all.size():
		var p: Dictionary = P.build(all.slice(i, i + 4), text, cfg)
		var low := (str(p.static_prefix) + "\n" + str(p.body)).to_lower()
		for word in banned:
			if low.contains(word):
				leaked.append(word)
		i += 4
	t.check(leaked.is_empty(), "no chart term in any whole built prompt (static prefix included) for 200 beings; first: %s" % (leaked[0] if not leaked.is_empty() else ""))
	# Trimming: near goes first, then bonds, before any being is dropped (names pinned in 5.9: "near", "bonds", "being").
	var cfg3: Dictionary = cfg.duplicate(true)
	cfg3.prompt.max_in_tokens = int(a.est_in) - 120
	var tr: Dictionary = P.build(batch1, text, cfg3)
	var order: Array = tr.trimmed
	var rank := {"near": 0, "bonds": 1, "being": 2}
	t.check(order.size() >= 1 and str(order[0]) == "near", "batch trimming drops near first")
	var only_known := true
	var in_order := true
	for j in order.size():
		only_known = only_known and rank.has(str(order[j]))
		if j > 0 and rank.has(str(order[j])) and rank.has(str(order[j - 1])):
			in_order = in_order and int(rank[str(order[j])]) >= int(rank[str(order[j - 1])])
	t.check(only_known, "trimmed holds only the pinned names near, bonds, being")
	t.check(in_order, "and in the order of the drops: near, then bonds, then being")
	_end(t)


func _values_of(x: Variant) -> Array:
	var out: Array = []
	if x is Dictionary:
		for k in x:
			out.append_array(_values_of(x[k]))
	elif x is Array:
		for v in x:
			out.append_array(_values_of(v))
	elif x != null:
		out.append(str(x))
	return out


# ---------------------------------------------------------------- 27. parser

func test_t27_parser(t) -> void:
	if not _drv_api(t):
		return
	var P = load("res://minds/prompt.gd")
	var good := '[{"slot":"1:3","choice":1,"say":"A quiet day."},{"slot":"2:4","choice":0,"say":"Tired."}]'
	var r: Dictionary = P.parse(good, ["1:3", "2:4"])
	t.check(r.has("1:3") and bool(r["1:3"].ok) and int(r["1:3"].choice) == 1 and str(r["1:3"].say) == "A quiet day.", "strict JSON parses")
	var fenced: Dictionary = P.parse("```json\n" + good + "\n```", ["1:3", "2:4"])
	t.check(fenced.has("2:4") and bool(fenced["2:4"].ok), "a code fence around the JSON is accepted")
	var extra: Dictionary = P.parse('[{"slot":"1:3","choice":1,"say":"Hm.","mood":"x","n":4}]', ["1:3"])
	t.check(extra.has("1:3") and bool(extra["1:3"].ok), "extra fields are ignored")
	var unk: Dictionary = P.parse('[{"slot":"9:9","choice":1,"say":"Hm."},{"slot":"1:3","choice":0,"say":"Ok."}]', ["1:3"])
	t.check(not unk.has("9:9"), "an entry whose slot was not requested is ignored")
	t.check(unk.has("1:3") and bool(unk["1:3"].ok), "and its neighbour survives")
	var mixed: Dictionary = P.parse('[{"slot":"1:3","choice":"x","say":"Hm."},{"slot":"2:4","choice":2,"say":"Fine."}]', ["1:3", "2:4"])
	t.check(not (mixed.has("1:3") and bool(mixed["1:3"].ok)), "a malformed entry fails")
	t.check(mixed.has("2:4") and bool(mixed["2:4"].ok), "and one bad entry does not void its neighbour")
	for bad in ["this is not json {", "{}", '{"slot":"1:3"}', "", "[]"]:
		var rb: Dictionary = P.parse(bad, ["1:3"])
		var any_ok := false
		for k in rb:
			any_ok = any_ok or bool(rb[k].ok)
		t.check(not any_ok, "no entry is ok for %s" % JSON.stringify(bad))


# ---------------------------------------------------------------- 28. deadline skip

func test_t28_deadline_and_speed_skip(t) -> void:
	if not _drv_api(t):
		return
	var D = load("res://minds/driver.gd")
	t.check(_has_static(D, "skip_reason"), "missing API: Driver.skip_reason()")
	if not _has_static(D, "skip_reason"):
		return
	var calm: int = _steps_of(float(_md().sim.think_h))
	var event: int = _steps_of(float(_md().sim.think_event_h))
	t.eq(D.skip_reason(calm, 0, 1.0), "", "calm slot at 1x is sent (6.0 s window)")
	t.eq(D.skip_reason(calm, 0, 2.0), "", "calm slot at 2x is sent (3.0 s window)")
	t.check(D.skip_reason(calm, 0, 3.0) != "", "calm slot at 3x is skipped (2.0 s window)")
	t.eq(D.skip_reason(event, 0, 1.0), "", "event slot at 1x is sent (3.0 s window)")
	t.check(D.skip_reason(event, 0, 2.0) != "", "event slot at 2x is skipped (1.5 s window)")
	t.check(D.skip_reason(calm, 0, float(_md().driver.speed_gate_x) + 0.5) != "", "above driver.speed_gate_x nothing is sent")
	t.check(D.skip_reason(calm, calm - 1, 1.0) != "", "a request one step from its deadline is skipped")
	# End to end: at 6x nothing is sent and nothing is charged.
	if not _api(t) or not _drv_api(t):
		return
	_cfg_edit("minds.json", ["budget", "price_in_per_mtok"], 1.0)
	_cfg_edit("minds.json", ["budget", "price_out_per_mtok"], 4.0)
	var c := _cast("llm", 3)
	var mock = load("res://tests/mock_provider.gd").new()
	var drv = load("res://minds/driver.gd").new(mock, _md())
	var fresh_meter := JSON.stringify(load("res://minds/budget.gd").new(_md().budget).save())
	var speed := 6.0
	t.check(speed > float(_md().driver.speed_gate_x), "the staged speed (%sx) is above driver.speed_gate_x" % str(speed))
	_mini_to_sol(c.w, 3)
	for b in c.w.beings:
		_why(b, "grief", c.w.t, 99, "Gone-99")
	for i in 400:
		_mini(c.w)
		drv.pump(c.w, float(c.w.step_index) * _real_s_per_step(speed), speed)
	t.check(int(c.w.stats.minds.requests_built) > 0, "requests were built (%d), so there was something to skip" % int(c.w.stats.minds.requests_built))
	t.eq(mock.calls, 0, "at 6x the provider is never called")
	var skipped := 0
	for k in drv.skipped:
		skipped += int(drv.skipped[k])
	t.check(skipped > 0, "and the driver counted the requests as skipped (%d)" % skipped)
	t.eq(JSON.stringify(drv.budget.save()), fresh_meter, "and nothing is charged: the saved meter equals a fresh one")
	_end(t)


# ---------------------------------------------------------------- 29. mode resolution

func test_t29_mode_resolution(t) -> void:
	if not _drv_api(t):
		return
	var D = load("res://minds/driver.gd")
	t.check(_has_static(D, "resolve_mode"), "missing API: Driver.resolve_mode()")
	if not _has_static(D, "resolve_mode"):
		return
	t.eq(D.resolve_mode("llm", false, true, true), "rules", "llm without a key resolves to rules, silently")
	t.eq(D.resolve_mode("llm", true, false, true), "rules", "llm with a key but unset prices resolves to rules (fail closed)")
	t.eq(D.resolve_mode("llm", true, true, false), "rules", "llm with no adapter resolves to rules")
	t.eq(D.resolve_mode("llm", true, true, true), "llm", "llm with a key, prices and an adapter resolves to llm")
	t.eq(D.resolve_mode("rules", true, true, true), "rules", "rules stays rules")
	t.eq(D.resolve_mode("off", true, true, true), "off", "off stays off")
	if _api(t):
		var off = SimWorld.new(1, {"blank": true, "minds_mode": "off"})
		t.check(off.minds == null, "off builds no module")
		var rules = SimWorld.new(1, {"blank": true, "minds_mode": "rules"})
		t.check(rules.minds != null, "rules builds the module")
		t.eq(str(SimData.load_json("minds.json").mode["default"]), "rules", "the shipped default mode is rules (Q-A)")
		_end(t)


# ---------------------------------------------------------------- slice 2

func test_s2_t23_slice2_budget_caps(t) -> void:
	_skip(t, "test 23 slice-2 cases: per-colonist-sol cap, calls-per-minute rate limit, month tokens, USD day and month caps (section 8, slice 2)")
