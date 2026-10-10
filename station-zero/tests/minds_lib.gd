extends RefCounted
## Task 6b, step 3 (tests first, red): shared support for the AI minds test files. Spec: docs/specs/ai-minds.md revision 5
## (section 5.9 is the API surface these tests are written against). It is not a test (no test_ prefix); the test files `extends "res://tests/minds_lib.gd"`.
##
## Method (same as tests/test_moods.gd): nothing here names `Minds`, `MindsVoice`, `world.minds` ... as a static type. Worlds,
## beings and the module are untyped Variants and scripts are reached with load(), so on a tree without the implementation
## every file parses and each test fails cleanly: every test starts with `_api(t)`, which records ONE failed check naming every
## missing piece and makes the test return before it can abort on a missing member (an aborted test would otherwise pass
## silently, because the runner only fails a test that made zero checks). _begin/_end add the same guard to the body.
##
## API ASSUMED beyond the names the spec gives (the implementer should match, or tell the test author; collected in the step 3
## report). Spec names used as written: SimWorld option `minds_mode`, members `minds`, `minds_mode`, `mind_enabled`; Being
## `mind_bias` {kind, target, until_t} and `mind_slot_n`; Minds fields `cfg`, `seen_ticks`, `last_cell_key`, `pending_open`
## ({id, sol, j, kind}), `due` ({id, k, kind, open_step, deadline_step, menu, facts_hash}), `outbox` ({id, k, deadline_step,
## facts, menu, priority}), `inbox`, `ledger`, `says` (id -> {text, t, source, t_model, variant}), `last_visit_t`,
## `last_event_t`, `seen_why_t`, `applied_sol`, `applied_this_sol`; `Minds.deliver`, `Minds.bias_view(id) -> {kind,
## target_name}`; stats.minds counters of section 10; `ledger_hash`; data `data/minds.json`, `data/minds_text.json`.
## Names the spec does NOT give, chosen here:
##   world.minds.on_step(world)                      the sibling hook (also called by the test seam `_mini`)
##   world.minds.deliver(world, entry) -> bool       entry {id, k, choice (option key), say, model, filtered}; true when stored
##   world.minds.facts_for(world, being) -> Dictionary    the facts record of 6.1
##   world.minds.menu_for(world, being) -> Array          the option keys, index 0 `carry_on`
##   world.minds.ledger_hash() -> String                  sha256 over the ledger lines without `say` and `model`
##   world.minds.bias_view(id)                             an instance method (the spec writes `Minds.bias_view`)
##   world.stats.minds                                     keys as spec section 10 (slots_opened {calm, event}, slots_rule_only,
##                                                         slot_dropped_carry, calm_skipped_event, requests_built, applied_model,
##                                                         applied_rule, bias_applied {stay, roam, visit, visit_new, quiet},
##                                                         bias_skipped_asleep, says_model, says_rule, ledger_len, slot_no_answer,
##                                                         rejected {bad_key, not_in_menu, stale_target, dead; no_neighbour is slice 2; no `child` reason since revision 5},
##                                                         apply_dropped_cap, say_rejected)
##   SimWorld.new(seed, {"minds_replay": Array of ledger entry dictionaries})   replay mode (mode llm, inbox preloaded)
##   SimData.minds() -> data/minds.json                    (tests read the file with SimData.load_json("minds.json"))
##   MindsVoice.line(facts) -> String                      static, pure (5.7)
##   BeingPanel.voice(world, id) -> String, BeingPanel.intent(world, id) -> String (7.1), static
## Data edits: tests that need another value edit the SimData cache BEFORE the world is built (`_cfg_edit`) and restore it in
## `_end`, so it does not matter whether the module copies the data at creation.

const SHIFT := 1048576
const R := 1
const HAB := 2
const WORK := 3
const GREEN := 4
const COMMS := 5
const ISO := 6
const SEEDS := [42, 7, 99, 1234, 2026]
const MINDS_PATH := "res://sim/minds.gd"
const VOICE_PATH := "res://sim/minds_voice.gd"

var _undo: Array = []


# ---------------------------------------------------------------- guards, data and api

func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func _begin(t) -> void:
	t._failures.append(_abort_msg(t))


func _end(t) -> void:
	_restore()
	t._failures.erase(_abort_msg(t))


func _restore() -> void:
	while not _undo.is_empty():
		var u: Array = _undo.pop_back()
		u[0][u[1]] = u[2]


## Overwrites `path` (an Array of keys) in the SimData cache of file `file`; undone by _end.
func _cfg_edit(file: String, path: Array, value: Variant) -> void:
	var node: Variant = SimData.load_json(file)
	for i in path.size() - 1:
		node = node[path[i]]
	var leaf: String = path[path.size() - 1]
	_undo.append([node, leaf, node[leaf]])
	node[leaf] = value


func _has_static(script: Variant, method: String) -> bool:
	if script == null:
		return false
	for m in script.get_script_method_list():
		if m.name == method:
			return true
	return false


func _md() -> Dictionary:
	if not FileAccess.file_exists("res://data/minds.json"):
		return {}
	var d: Variant = SimData.load_json("minds.json")
	return d if d is Dictionary else {}


func _mt() -> Dictionary:
	if not FileAccess.file_exists("res://data/minds_text.json"):
		return {}
	var d: Variant = SimData.load_json("minds_text.json")
	return d if d is Dictionary else {}


func _rd() -> Dictionary:
	return SimData.relationships()


func _tickh() -> float:
	return float(_rd().tick_h)


func _script(path: String) -> Variant:
	return load(path) if FileAccess.file_exists(path) else null


## One failed check naming every missing piece; true when every piece the sim tests touch exists.
func _api(t) -> bool:
	var missing: Array[String] = []
	for f in ["data/minds.json", "data/minds_text.json", "sim/minds.gd", "sim/minds_voice.gd"]:
		if not FileAccess.file_exists("res://" + f):
			missing.append(f)
	if not _has_static(load("res://sim/sim_data.gd"), "minds"):
		missing.append("SimData.minds()")
	var w = SimWorld.new(1, {"blank": true, "minds_mode": "rules"})
	if "minds" in w and w.minds != null:
		for m in ["on_step", "deliver", "facts_for", "menu_for", "ledger_hash", "bias_view"]:
			if not w.minds.has_method(m):
				missing.append("world.minds.%s()" % m)
		for f in ["cfg", "seen_ticks", "last_cell_key", "pending_open", "due", "outbox", "inbox", "ledger", "says", "last_visit_t",
				"last_event_t", "seen_why_t", "season_seen", "applied_sol", "applied_this_sol", "policy_calls"]:
			if not (f in w.minds):
				missing.append("world.minds.%s" % f)
	else:
		missing.append("SimWorld.minds (mode rules)")
	for f in ["minds_mode", "mind_enabled"]:
		if not (f in w):
			missing.append("SimWorld.%s" % f)
	var b = w.add_being(2)
	for f in ["mind_bias", "mind_slot_n"]:
		if not (f in b):
			missing.append("Being.%s" % f)
	if not w.stats.has("minds"):
		missing.append("stats.minds")
	else:
		for k in ["slots_opened", "slots_rule_only", "slot_dropped_carry", "calm_skipped_event", "requests_built", "applied_model",
				"applied_rule", "bias_applied", "bias_skipped_asleep", "says_model", "says_rule", "ledger_len", "slot_no_answer",
				"rejected", "apply_dropped_cap", "say_rejected"]:
			if not w.stats.minds.has(k):
				missing.append("stats.minds.%s" % k)
	t.check(missing.is_empty(), "missing API: " + ", ".join(PackedStringArray(missing)))
	if missing.is_empty():
		_begin(t)
	return missing.is_empty()


# ---------------------------------------------------------------- staging

## Blank world with a corridor tree: reactor 1; habitat 2 with neighbours reactor 1, workshop 3, green room 4, comms 5 (all
## finished corridors); an isolated habitat 6 with no corridor. Stocks full so nobody dies of a shortage in a short run.
func _world(mode: String = "llm", seed_in: int = 1, moods: bool = true, extra: Dictionary = {}) -> Variant:
	var opts := {"blank": true, "minds_mode": mode, "moods_enabled": moods}
	opts.merge(extra)
	var w = SimWorld.new(seed_in, opts)
	w.add_building("reactor", 0, 0)
	w.buildings.add_attached("habitat", R, "r", 8, 6, 4)
	w.buildings.add_attached("workshop", HAB, "r", 8, 6, 4)
	w.buildings.add_attached("green_room", HAB, "u", 8, 6, 4)
	w.buildings.add_attached("comms", HAB, "d", 8, 6, 4)
	w.add_building("habitat", 300, 300)
	_stocks(w)
	return w


func _stocks(w) -> void:
	w.colony.oxygen = w.colony.o2_cap()
	w.colony.food = w.colony.food_cap()
	w.colony.ice = 1000000.0


## An awake adult with plain explicit traits, named `Pax-<id>` unless `nm` is given (a Name-N token).
func _being(w, bid: int, nm: String = "") -> Variant:
	var b = w.add_being(bid)
	b.name = nm if nm != "" else "Pax-%d" % b.id
	b.energy = 70.0
	for k in ["sociability", "care", "restless", "steady", "curiosity", "drive"]:
		b.persona.traits[k] = 0.5
	b.persona.description = "warm and nurturing"
	b.state = "idle"
	return b


## A young being at the world's time. `stage`: "baby" (6 months), "toddler" (2 years), "child" (5 years, the default), "teen"
## (14 years). The `baby` flag is kept for the older callers. The ages sit inside the stage bounds of data/lifecycle.json
## (toddler 1, child 3, teen 13, adult 18 years); callers assert the stage with `w.lifecycle.stage(b, w.t)`.
const _YOUNG_MONTHS := {"baby": 6, "toddler": 24, "child": 60, "teen": 168}


func _young(w, bid: int, baby: bool = false, stage: String = "child") -> Variant:
	var b = _being(w, bid)
	var st := "baby" if baby else stage
	b.born_t = w.lifecycle.add_months(w.t, -int(_YOUNG_MONTHS[st]))
	return b


func _friends(w, a: int, b: int, bond: float = 0.8) -> void:
	w.relationships.debug_set_bond(a, b, bond)


func _sol_h(w) -> float:
	return float(w.clock.sol_h)


func _sol(w) -> int:
	return int(w.clock.sol_index(w.t))


## One fixed step of the sim as the sibling hook sees it: time, step index, the relationships accumulator, the mood tick and
## the minds hook, in the order of world.gd. Beings do not act (cheap); used wherever behaviour is not the subject.
func _mini(w, n: int = 1) -> void:
	for i in n:
		w.t += w.fixed_step
		w.buildings.now = w.t
		w.step_index += 1
		w.relationships.on_step(w, w.fixed_step)
		if w.moods_enabled and w.moods != null:
			w.moods.on_step(w)
		if "minds" in w and w.minds != null and w.relationships_enabled:
			w.minds.on_step(w)


## Mini-steps until the relationships tick counter changes `ticks` times.
func _mini_ticks(w, ticks: int = 1) -> void:
	var want: int = int(w.relationships.ticks) + ticks
	var guard := 0
	while int(w.relationships.ticks) < want and guard < 2000:
		_mini(w)
		guard += 1


## Mini-steps until the NEXT step would enter sol `sol` (stops on the last step of the sol before, so the first relationships
## tick of `sol` is still to come and a run can count from it).
func _mini_to_sol(w, sol: int) -> void:
	var guard := 0
	while int(w.clock.sol_index(w.t + w.fixed_step)) < sol and guard < 400000:
		_mini(w)
		guard += 1


## Mini-steps through the first relationships tick whose own sol is `sol` (stops right after that tick's step).
func _mini_to_first_tick_of(w, sol: int) -> void:
	var guard := 0
	var seen: int = int(w.relationships.ticks)
	while guard < 400000:
		_mini(w)
		guard += 1
		if int(w.relationships.ticks) != seen:
			seen = int(w.relationships.ticks)
			if _sol(w) >= sol:
				return


## Staged sol start: t exactly at the start of sol `sol` (x sol_h), step index advanced by the matching number of steps so a
## deadline arithmetic in steps stays consistent, accumulator cleared.
func _sol_start(w, sol: int) -> void:
	var target: float = float(sol - 1) * _sol_h(w)
	w.step_index += int(round((target - w.t) / w.fixed_step))
	w.t = target
	w.buildings.now = w.t
	w.relationships.acc_h = 0.0


## The elapsed-hours cell of a relationships tick (spec 5.2 step 4): whole sim hours since the start of the tick's own sol.
func _tick_cell(w) -> int:
	var sol := _sol(w)
	return int(floor((w.t - float(sol - 1) * _sol_h(w)) / _grid(w) + 1e-9))


func _grid(w) -> float:
	return float(_md().slot.grid_h)


func _cells(w) -> int:
	return int(floor(_sol_h(w) / _grid(w)))


## The spec cell of (id, sol, j) written out independently of the code under test (5.2 step 4).
func _cell_of(w, id: int, sol: int, j: int, per_sol: int) -> int:
	var s: Dictionary = _md().slot
	var cells := _cells(w)
	return (id * int(s.cell_mult) + sol * int(s.cell_step) + j * (cells / per_sol)) % cells


## Number of calm slots demanded on a tick at (sol, cell) by the living non-baby beings of `ids`.
func _demand(w, ids: Array, sol: int, cell: int, per_sol: int) -> int:
	if cell >= _cells(w):
		return 0
	var n := 0
	for id in ids:
		for j in per_sol:
			if _cell_of(w, int(id), sol, j, per_sol) == cell:
				n += 1
	return n


## Sets a mood why the way Moods._apply would (the six event keys are the real 6a keys).
## The deviation is staged well past the 6a show line so the mood tick does not clear the why before the minds hook reads it.
func _why(b, key: String, t_set: float, other_id: int = 0, other_name: String = "") -> void:
	b.mood = float(b.mood_base) + (-0.5 if key in ["grief", "lapse", "lapse_close"] else 0.5)
	b.mood_why = {"key": key, "id": other_id, "name": other_name, "t": t_set, "clause": "", "sign": 0}


## A slice 2 test is kept, not deleted: one passing check that states why it does not run, and a SKIP line in the output.
func _skip(t, reason: String) -> void:
	print("SKIP %s: %s" % [t._current, reason])
	t.check(true, "SKIPPED (slice 2, spec section 19): " + reason)


func _stat(w, k: String) -> Variant:
	return w.stats.minds[k]


func _due_of(w, id: int) -> Array:
	var out: Array = []
	for d in w.minds.due:
		if int(d.id) == id:
			out.append(d)
	return out


## Runs mini-steps until `b` has opened one more slot (its `mind_slot_n` grew); returns its due entry or {}.
func _open_slot(w, b, max_steps: int = 3000) -> Dictionary:
	var n0: int = int(b.mind_slot_n)
	var guard := 0
	while int(b.mind_slot_n) == n0 and guard < max_steps:
		_mini(w)
		guard += 1
	if int(b.mind_slot_n) == n0:
		return {}
	for d in w.minds.due:
		if int(d.id) == int(b.id) and int(d.k) == int(b.mind_slot_n):
			return d
	return {}


func _deliver(w, id: int, k: int, choice: String, say: String = "", extra: Dictionary = {}) -> Variant:
	var e := {"id": id, "k": k, "choice": choice, "say": say, "model": "mock", "filtered": false}
	e.merge(extra, true)
	return w.minds.deliver(w, e)


## Mini-steps until the due entry (id, k) is resolved (gone from `due`).
func _resolve(w, id: int, k: int, max_steps: int = 4000) -> bool:
	var guard := 0
	while guard < max_steps:
		var still := false
		for d in w.minds.due:
			if int(d.id) == id and int(d.k) == k:
				still = true
		if not still:
			return true
		_mini(w)
		guard += 1
	return false


## Open a slot for `b`, deliver `choice`/`say` strictly before the deadline, resolve; returns the due entry that was resolved.
func _decide(w, b, choice: String, say: String = "", extra: Dictionary = {}) -> Dictionary:
	var d := _open_slot(w, b)
	if d.is_empty():
		return d
	_deliver(w, int(b.id), int(d.k), choice, say, extra)
	_resolve(w, int(b.id), int(d.k))
	return d


func _rej(w, reason: String) -> int:
	return int(w.stats.minds.rejected.get(reason, 0))


## A Being-state digest for equality tests (positions, states, energy, mood).
func _digest(w) -> String:
	var parts: Array = []
	for b in w.beings:
		parts.append([b.id, b.building_id, b.state, b.energy, b.wait_h, b.mood, b.mood_band])
	return JSON.stringify(parts).sha256_text()


## SimRng state after a run, plus the next five draws taken from a copy of the generator.
func _rng_state(w) -> Array:
	var st: int = w.rng._rng.state
	var c := RandomNumberGenerator.new()
	c.state = st
	var next: Array = []
	for i in 5:
		next.append(c.randf())
	return [st, next]


func _all_strings(node: Variant, out: Array) -> void:
	if node is Dictionary:
		for k in node:
			out.append(str(k))
			_all_strings(node[k], out)
	elif node is Array:
		for v in node:
			_all_strings(v, out)
	elif node != null:
		out.append(str(node))


func _leaves(node: Variant, prefix: String, out: Array) -> void:
	if node is Dictionary and not (node as Dictionary).is_empty():
		for k in node:
			_leaves(node[k], prefix + ("." if prefix != "" else "") + str(k), out)
	else:
		out.append(prefix)


## Scripted generator: records every call; chance() is forced; randf() returns `u`; randf_range returns the midpoint.
class ScriptRng extends SimRng:
	var calls: Array = []
	var force := false
	var u := 0.5

	func chance(p: float) -> bool:
		calls.append(["chance", p])
		return force

	func randf() -> float:
		calls.append(["randf"])
		return u

	func randf_range(from: float, to: float) -> float:
		calls.append(["randf_range"])
		return (from + to) / 2.0

	func names() -> Array:
		var out: Array = []
		for c in calls:
			out.append(c[0])
		return out


## chance(p) is true when the fixed value `cu` is below p (as the real generator's randf() < p), so a changed argument can flip
## the outcome; the other calls are recorded as in ScriptRng.
class ThresholdRng extends SimRng:
	var calls: Array = []
	var cu := 0.2
	var u := 0.5

	func chance(p: float) -> bool:
		calls.append(["chance", p])
		return cu < p

	func randf() -> float:
		calls.append(["randf"])
		return u

	func randf_range(from: float, to: float) -> float:
		calls.append(["randf_range"])
		return (from + to) / 2.0

	func names() -> Array:
		var out: Array = []
		for c in calls:
			out.append(c[0])
		return out


# ---------------------------------------------------------------- the staged subject used by menu, apply and bias tests

## Subject S in habitat 2 (four finished neighbours), friends F1 in the workshop and F2 in the green room (both over a
## finished corridor), a stranger X in comms. Friends are real `friends` pairs (bond 0.8).
func _cast(mode: String = "llm", seed_in: int = 1, moods: bool = true) -> Dictionary:
	var w = _world(mode, seed_in, moods)
	var s = _being(w, HAB, "Vana-3")
	var f1 = _being(w, WORK, "Dax-8")
	var f2 = _being(w, GREEN, "Kiro-12")
	var x = _being(w, COMMS, "Zed-40")
	_friends(w, s.id, f1.id)
	_friends(w, s.id, f2.id)
	return {"w": w, "s": s, "f1": f1, "f2": f2, "x": x}
