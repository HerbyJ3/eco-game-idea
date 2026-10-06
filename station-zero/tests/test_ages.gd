extends RefCounted
## Task 3, step 3: the ages tests, written first (red). Spec: docs/specs/ages.md revision 3, section 10 tests 1 to 20 (test
## 19, the HUD, and the speed-readout half of test 20 live in tests/test_view_ages.gd; they cannot pass before the HUD
## step 6 and step 11). Section 12 (hash proof) is the separate script tests/age_hash_proof.gd, whose pure helpers are
## tested here (test_proof_helper_*).
##
## Naming: test_tNN_* is spec test NN. Everything is a hand-made blank world (SimWorld.new(seed, {"blank": true}),
## add_building, add_being) driven by setting world.t to a sol boundary (start_hour + n x sol_hours) and calling
## world.ages.on_sol(world), or the pure Ages.sample / Ages.decide / Ages.dominant_cause on synthetic input. Only tests
## 17 (10 sols, 3 worlds) and the newborn tests step the real simulation.
##
## Class access: nothing here names `Ages`, `world.ages`, `Being.parent_id` ... as a static type. Worlds, beings and the
## Ages script are untyped Variants and Ages is reached with load("res://sim/ages.gd"), so on a tree without the
## implementation the file still parses and each test fails cleanly (every test starts with `_api()`, which records one
## failed check per missing piece and makes the test return before it can abort on a missing member; an aborted test would
## otherwise pass silently, because the runner only fails a test with zero checks). SimData.ages() is called through
## `.call`, and ages data is read with SimData.load_json("ages.json") (the cache that ages() must return).
##
## API ASSUMED beyond the spec's own names (the simplest reading; the implementer should match or tell the test author):
##  - Ages (res://sim/ages.gd) has STATIC `sample(world) -> Dictionary`, `decide(window, age, sols_since_change,
##    family_mars_born, homes) -> String` and `dominant_cause(window) -> String`; `world.ages` is an instance with fields
##    `age`, `window`, `last_change_sol`, `snap_shorts`, `snap_deaths`, `last_sample` and the method `on_sol(world)`.
##  - A sample / `last_sample` is a Dictionary with one bool per clause under the spec's clause names (oxygen, food,
##    o2_net, food_net, power_budget, none_offline, no_short, no_shortage_death, ice, calm, rested). The test never reads
##    an "ok" key from a sample; ok is "all eleven true". Raw values are not asserted.
##  - A window entry (world.ages.window[i], and the elements passed to decide / dominant_cause) is {"ok": bool,
##    "failed": Array of group ids (String)}. A Dictionary keyed by group would also work with every read here (`in`,
##    `size()`), but synthetic windows are built with an Array.
##  - Cause group ids are the spec's: ice, food, oxygen, power, death, unrest. dominant_cause returns the id String.
##  - decide's `homes` argument is the integer count of distinct birth habitats among the family Mars-born, and
##    `family_mars_born` the integer count (the same two numbers on_sol derives from the beings).
##  - Entry text = base + " " + (cause line + " ")? + season phrase: one space between sentences (spec 8.1 example line).
##  - A fall-back log / history entry carries `cause`; the other lines carry no `cause` or null. Log entries are
##    {kind: "age_began", age, how, cause?, text, t, sol, clock_sol} as SimWorld._log writes them. age_history entries are
##    {age, how, cause, text, pop, family_mars_born, t, sol, clock_sol}; clock_sol = clock.sol_index(t), sol = world.sol().
##  - stats.sols_in_age is credited in on_sol step 1 BEFORE decide (spec 4.1): at boundary n the sol that ended is credited
##    to the age in force, so the age changed at boundary n gets its first sol at boundary n + 1.
##  - SimWorld.ages_enabled (bool, default true), SimWorld.advance_dropped_h (float, 0.0 at creation), the injected
##    millisecond clock is a Callable field `SimWorld.now_ms` returning an int; SimWorld.advance_budget_ms is read from
##    data/sim.json (tests edit the data cache before building the world, so a field copied in _init works).
##  - Hand-made worlds: the spec's "good world" lists habitat + green room + reactor (demand 7), then "add a second
##    habitat" (demand 10; the test uses 10, still under the supply of 14). Mars-born beings in a staged world have
##    earth_born false, parent_id = a living founder's id, birth_building_id alternating between the two habitats.
##  - on_sol may be called at any boundary sequence (also with gaps; test 17 and 14 skip sols). Boundaries starting at a
##    large n (the season combinations of test 16) behave like the first 40 samples: the window fills from the first
##    sample at n >= from_sol, so entry is at (first n) + 39.
## Where the spec leaves a detail open, extended simply (listed here):
##  - Test 3 `none_offline` takes the second habitat offline (the draw stays in demand, so power_budget is unaffected).
##  - Test 3 `power_budget` 14 / 15: reactor 0 + habitats 3 + 3 + green room 4 + workshop 4 = 14; the 15 is an archive whose
##    data draw is edited to 1 (SimData cache, restored).
##  - Strictness of `>` for the nets is tested by moving ages.sample.net_above onto the net value itself (data edit,
##    restored); the knife-edge 28-being case only shows that CMP_EPS does not creep into the net clauses.
##  - The extra square-wave periods are kept as the spec lists them; `p / 2.0` decides ok, so an odd period is 2/3 or 3/5 ok.
##  - An adversarial feed (always the move that would change the age) is added to test 14: no two changes closer than 20.
##  - The 4-season x 6-cause combinations (test 16) use worlds whose clock is moved so the three change lines fall in the
##    wanted season; the text compared is rebuilt from the entry's own `t`.

const CMP_EPS := 1e-9
const GROUPS := ["ice", "food", "oxygen", "power", "death", "unrest"]
const CLAUSES := ["oxygen", "food", "o2_net", "food_net", "power_budget", "none_offline", "no_short",
		"no_shortage_death", "ice", "calm", "rested"]
const SIM_STATS_NEW := ["age", "age_changes", "sols_in_age", "first_settlement_sol", "age_history"]

var _undo: Array = []


# ---------------------------------------------------------------- helpers

func _ad() -> Dictionary:
	return SimData.load_json("ages.json")


func _edit(dict: Dictionary, key: String, value: Variant) -> void:
	_undo.append([dict, key, dict[key]])
	dict[key] = value


func _restore() -> void:
	while not _undo.is_empty():
		var u: Array = _undo.pop_back()
		u[0][u[1]] = u[2]


## Abort guard. The runner only fails a test that made no checks, so a runtime error in the code under test that aborts a
## test after some checks have passed would be reported as a pass. _begin records a failure that _end (the last line of
## every test) removes again; a test that never reaches its last line stays failed.
func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func _begin(t) -> void:
	t._failures.append(_abort_msg(t))


func _end(t) -> void:
	t._failures.erase(_abort_msg(t))


func _has_static(script: Variant, method: String) -> bool:
	if script == null:
		return false
	for m in script.get_script_method_list():
		if m.name == method:
			return true
	return false


## One failed check naming every missing piece of the API; true when every piece the tests touch exists.
func _api(t) -> bool:
	var missing: Array[String] = []
	var A = load("res://sim/ages.gd")
	for m in ["sample", "decide", "dominant_cause"]:
		if not _has_static(A, m):
			missing.append("Ages.%s (static)" % m)
	var w = SimWorld.new(1, {"blank": true})
	if "ages" in w and w.ages != null:
		for f in ["age", "window", "last_change_sol", "snap_shorts", "snap_deaths", "last_sample"]:
			if not (f in w.ages):
				missing.append("world.ages.%s" % f)
		if not w.ages.has_method("on_sol"):
			missing.append("world.ages.on_sol(world)")
	else:
		missing.append("SimWorld.ages")
	if not ("ages_enabled" in w):
		missing.append("SimWorld.ages_enabled")
	var b = Being.new()
	for f in ["parent_id", "birth_building_id"]:
		if not (f in b):
			missing.append("Being.%s" % f)
	for k in ["age", "age_changes", "sols_in_age", "first_settlement_sol", "age_history"]:
		if not w.stats.has(k):
			missing.append("stats.%s" % k)
	t.check(missing.is_empty(), "missing API: " + ", ".join(PackedStringArray(missing)))
	if missing.is_empty():
		_begin(t)
	return missing.is_empty()


## The spec's "good world" G (section 10): reactor, habitat A, green room, habitat B (draw 10, supply 14); `n` beings of
## whom `mars` are Mars-born with a living parent, birth habitats alternating between A and B; energy 70; stocks at cap,
## ice 1000 (enough for 160 beings), no shorts, no deaths. Returns the world; ids are in w.get_meta-free fields below.
func _good(n: int = 12, mars: int = 6, seed_in: int = 1) -> Variant:
	var w = SimWorld.new(seed_in, {"blank": true})
	w.add_building("reactor", 0, 0)
	var ha: int = w.add_building("habitat", 40, 0)
	w.add_building("green_room", 80, 0)
	var hb: int = w.add_building("habitat", 120, 0)
	var founders: Array = []
	for i in n - mars:
		var f = w.add_being(ha)
		f.earth_born = true
		founders.append(f)
	for i in mars:
		var b = w.add_being(ha)
		b.earth_born = false
		b.parent_id = founders[i % founders.size()].id if not founders.is_empty() else 0
		b.birth_building_id = ha if i % 2 == 0 else hb
	_reset_good(w)
	return w


func _hab_a(w) -> int:
	return _habs(w)[0]


func _hab_b(w) -> int:
	return _habs(w)[1]


func _habs(w) -> Array:
	var out: Array = []
	for b in w.buildings.list:
		if b.kind == "habitat":
			out.append(b.id)
	return out


func _reset_good(w) -> void:
	w.colony.oxygen = w.colony.o2_cap()
	w.colony.food = w.colony.food_cap()
	w.colony.ice = 1000.0
	for b in w.beings:
		b.energy = 70.0


func _set_boundary(w, n: int) -> void:
	w.t = w.clock.start_hour + float(n) * w.clock.sol_h
	w.buildings.now = w.t


func _boundary(w, n: int) -> void:
	_set_boundary(w, n)
	w.ages.on_sol(w)


func _break(w, cause: String) -> void:
	match cause:
		"ice":
			w.colony.ice = 0.0
		"food":
			w.colony.food = 0.0
		"oxygen":
			w.colony.oxygen = 0.0
		"power":
			w.stats.shorts += 1
		"death":
			w.stats.deaths_list.append({"t": w.t, "sol": w.sol(), "clock_sol": w.clock.sol_index(w.t),
					"being_id": 0, "name": "Test", "cause": "thirst"})
		"unrest":
			for b in w.beings:
				b.energy = 20.0


## Boundaries from..to (inclusive). `ok_fn(n) -> bool`; a not-ok sol breaks `cause` for that boundary only.
func _run(w, from_n: int, to_n: int, ok_fn: Callable, cause: String = "ice") -> void:
	for n in range(from_n, to_n + 1):
		_reset_good(w)
		if not ok_fn.call(n):
			_break(w, cause)
		_boundary(w, n)


func _always(_n: int) -> bool:
	return true


## ok except at the listed boundaries.
func _except(bad: Array) -> Callable:
	return func(n: int) -> bool: return not (n in bad)


func _age(w) -> String:
	return str(w.ages.age)


func _log_of(w, kind: String) -> Array:
	var out: Array = []
	for e in w.log:
		if e.kind == kind:
			out.append(e)
	return out


func _sample(w) -> Dictionary:
	var A = load("res://sim/ages.gd")
	return A.sample(w)


## Asserts every clause verdict: only `bad` (a name, or "" for none) is false.
func _only_fails(t, s: Dictionary, bad: String, msg: String) -> void:
	for c in CLAUSES:
		t.eq(s.get(c), c != bad, "%s: clause %s" % [msg, c])


## Window entries from a pattern string: o = ok, x = not ok (failed = [fail_group]).
func _win(pattern: String, fail_group: String = "ice") -> Array:
	var out: Array = []
	for ch in pattern:
		out.append({"ok": ch == "o", "failed": [] if ch == "o" else [fail_group]})
	return out


func _decide(age: String, pattern: String, since: int = 30, fam: int = 5, homes: int = 2) -> String:
	var A = load("res://sim/ages.gd")
	return A.decide(_win(pattern), age, since, fam, homes)


func _inject(w, age_id: String, pattern: String, last_change: int = 0) -> void:
	w.ages.age = age_id
	w.stats.age = age_id
	w.ages.window = _win(pattern)
	w.ages.last_change_sol = last_change


## Elapsed sol k at which clock.season(start + k x sol_h) is the wanted season and stays so for 130 sols.
func _season_start(w, season_index: int) -> int:
	for k in range(0, 700):
		var a: String = w.clock.season(w.clock.start_hour + float(k) * w.clock.sol_h)
		var b: String = w.clock.season(w.clock.start_hour + float(k + 130) * w.clock.sol_h)
		if w.clock.seasons.find(a) == season_index and a == b:
			return k
	return -1


func _season_phrase(w, t_change: float) -> String:
	return str(_ad().season_phrases[w.clock.seasons.find(w.clock.season(t_change))])


func _line(w, how: String, cause: String, t_change: float) -> String:
	var ad := _ad()
	var parts: Array = []
	match how:
		"settled":
			parts.append(ad.settlement.log_enter)
		"fell_back":
			parts.append(ad.landing.log_fall_back)
			parts.append(ad.cause_lines[cause])
		"settled_again":
			parts.append(ad.settlement.log_enter_again)
	parts.append(_season_phrase(w, t_change))
	return " ".join(PackedStringArray(parts))


## settle (ok from n0 + 1), fall back (cause), settle again (ok). Returns the last boundary run.
func _scenario(w, n0: int, cause: String) -> int:
	var n := n0
	var guard := 0
	var never := func(_k: int) -> bool: return false
	while _age(w) == "landing" and guard < 120:
		n += 1
		guard += 1
		_run(w, n, n, _always)
	guard = 0
	while _age(w) == "settlement" and guard < 80:
		n += 1
		guard += 1
		_run(w, n, n, never, cause)
	guard = 0
	while _age(w) == "landing" and guard < 150:
		n += 1
		guard += 1
		_run(w, n, n, _always)
	return n


func _snapshot(w) -> Dictionary:
	var bl: Array = []
	for b in w.buildings.list:
		bl.append([b.id, b.kind, b.offline, b.built, b.tx, b.ty])
	var be: Array = []
	for b in w.beings:
		be.append([b.id, b.building_id, b.state, b.energy, b.earth_born, b.born_t, b.role])
	return {"stocks": [w.colony.oxygen, w.colony.food, w.colony.ice, w.colony.regolith], "buildings": bl,
			"beings": be, "t": w.t, "shorts": w.stats.shorts, "deaths": w.stats.deaths_list.size()}


func _draws(w, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(w.rng.randf())
	return out


func _old_stats(w) -> Dictionary:
	var d: Dictionary = w.stats.duplicate(true)
	for k in SIM_STATS_NEW:
		d.erase(k)
	return d


func _beings_state(w) -> Array:
	var out: Array = []
	for b in w.beings:
		out.append([b.id, b.building_id, b.state, b.energy])
	return out


# ---------------------------------------------------------------- 1. oxygen, food

func test_t01_oxygen_and_food_thresholds(t) -> void:
	if not _api(t):
		return
	var w = _good()
	t.eq(w.colony.o2_cap(), 550.0, "o2 cap with one green room")
	t.eq(w.colony.food_cap(), 420.0, "food cap with one green room")
	_only_fails(t, _sample(w), "", "good world")
	w.colony.oxygen = 275.0
	_only_fails(t, _sample(w), "", "oxygen 275.0 of 550 passes")
	w.colony.oxygen = 274.9
	_only_fails(t, _sample(w), "oxygen", "oxygen 274.9 fails")
	_reset_good(w)
	w.colony.food = 210.0
	_only_fails(t, _sample(w), "", "food 210.0 of 420 passes")
	w.colony.food = 209.9
	_only_fails(t, _sample(w), "food", "food 209.9 fails")
	# The fraction is data: moving it moves the boundary.
	_reset_good(w)
	_edit(_ad().sample, "o2_min_fraction", 0.6)
	w.colony.oxygen = 300.0
	_only_fails(t, _sample(w), "oxygen", "o2_min_fraction 0.6: 300 of 550 fails")
	w.colony.oxygen = 331.0
	_only_fails(t, _sample(w), "", "o2_min_fraction 0.6: 331 passes")
	_restore()
	# The cap follows the online green rooms: a second one doubles nothing, it adds 150, so 275 now fails.
	w.add_building("green_room", 160, 0)
	_reset_good(w)
	t.eq(w.colony.o2_cap(), 700.0, "cap with two green rooms")
	w.colony.oxygen = 275.0
	_only_fails(t, _sample(w), "oxygen", "275 of 700 fails (the cap is read, not a constant)")
	w.colony.oxygen = 350.0
	_only_fails(t, _sample(w), "", "350 of 700 passes")
	_end(t)


# ---------------------------------------------------------------- 2. nets

func test_t02_o2_net_knife_edge_and_food_net(t) -> void:
	if not _api(t):
		return
	var w28 = _good(28, 0)
	var net28: float = w28.colony.o2_net()
	t.check(absf(net28) < 1e-9, "28 beings on one green room sit on the knife edge (net %s)" % str(net28))
	_only_fails(t, _sample(w28), "o2_net", "28 beings: o2_net fails (verdict only, never == 0.0)")
	var w27 = _good(27, 0)
	t.check(w27.colony.o2_net() > 0.04, "27 beings: net clearly positive")
	_only_fails(t, _sample(w27), "", "27 beings: every clause passes")
	var w29 = _good(29, 0)
	t.check(not _sample(w29).get("o2_net", true), "29 beings: o2_net fails")
	# food_net, isolated by the production override (the lever the spec names).
	var w = _good()
	_edit(SimData.colony().production, "food_per_green_room", 0.3)
	t.check(w.colony.food_net() < 0.0, "food net negative with 0.3 per green room")
	_only_fails(t, _sample(w), "food_net", "food_per_green_room 0.3: only food_net fails")
	_restore()
	_edit(SimData.colony().production, "food_per_green_room", 0.5)
	_only_fails(t, _sample(w), "", "food_per_green_room 0.5: net 0.08 passes")
	_restore()
	# A net of +0.005 is above net_above (0.0) and a net of -0.005 is not: the threshold is 0, not "small".
	_edit(SimData.colony().production, "food_per_green_room", 0.425)
	_only_fails(t, _sample(w), "", "food net +0.005 passes")
	_restore()
	_edit(SimData.colony().production, "food_per_green_room", 0.415)
	_only_fails(t, _sample(w), "food_net", "food net -0.005 fails")
	_restore()
	# Strictness: `>` is judged against ages.sample.net_above. Put net_above exactly on the net: not above, so it fails.
	var net: float = w.colony.food_net()
	_edit(_ad().sample, "net_above", net)
	_only_fails(t, _sample(w), "food_net", "net equal to net_above fails (strict >)")
	_restore()
	_edit(_ad().sample, "net_above", net - 1e-6)
	_only_fails(t, _sample(w), "", "net just above net_above passes")
	_restore()
	var onet: float = w.colony.o2_net()
	_edit(_ad().sample, "net_above", onet)
	t.eq(_sample(w).get("o2_net"), false, "o2_net equal to net_above fails (strict >)")
	_restore()
	_edit(_ad().sample, "net_above", onet - 1e-6)
	t.eq(_sample(w).get("o2_net"), true, "o2_net just above net_above passes")
	_restore()
	_end(t)


# ---------------------------------------------------------------- 3. power

func test_t03_power_budget_offline_and_short(t) -> void:
	if not _api(t):
		return
	var w = _good()
	w.add_building("workshop", 160, 0)
	t.eq(w.buildings.demand(), 14.0, "demand 14")
	t.eq(w.buildings.supply(), 14.0, "supply 14")
	_only_fails(t, _sample(w), "", "demand 14 on supply 14 passes")
	_edit(SimData.buildings().kinds.archive, "draw", 1)
	w.add_building("archive", 200, 0)
	t.eq(w.buildings.demand(), 15.0, "demand 15")
	_only_fails(t, _sample(w), "power_budget", "demand 15 on supply 14 fails")
	_restore()
	# none_offline
	var w2 = _good()
	_only_fails(t, _sample(w2), "", "all online")
	w2.set_offline(_hab_b(w2), true)
	_only_fails(t, _sample(w2), "none_offline", "one building offline fails none_offline only")
	w2.set_offline(_hab_b(w2), false)
	_only_fails(t, _sample(w2), "", "back online passes")
	# no_short: fails once for the sample after a short, then passes.
	var w3 = _good()
	_run(w3, 1, 9, _always)
	w3.stats.shorts += 1
	_boundary(w3, 10)
	t.eq(w3.ages.last_sample.get("no_short"), false, "boundary 10: a short since the previous boundary fails no_short")
	for c in CLAUSES:
		if c != "no_short":
			t.eq(w3.ages.last_sample.get(c), true, "boundary 10: last_sample %s still true" % c)
	t.eq(w3.ages.window.back().ok, false, "boundary 10: the sample is not ok")
	t.check("power" in w3.ages.window.back().failed, "boundary 10: group power failed")
	_reset_good(w3)
	_boundary(w3, 11)
	t.eq(w3.ages.last_sample.get("no_short"), true, "boundary 11: no new short, passes")
	t.eq(w3.ages.window.back().ok, true, "boundary 11: ok again")
	w3.stats.shorts += 3
	_reset_good(w3)
	_boundary(w3, 12)
	t.eq(w3.ages.last_sample.get("no_short"), false, "boundary 12: three shorts fail it again")
	_end(t)


# ---------------------------------------------------------------- 4. shortage deaths

func test_t04_shortage_death_causes(t) -> void:
	if not _api(t):
		return
	t.eq(_ad().sample.shortage_causes, ["air", "thirst", "hunger"], "data: the shortage causes")
	for cause in ["thirst", "air", "hunger"]:
		var w = _good()
		w.stats.deaths_list.append({"t": w.t, "sol": 0, "clock_sol": 1, "being_id": 99, "name": "X", "cause": cause})
		_only_fails(t, _sample(w), "no_shortage_death", "death by %s" % cause)
	for cause in ["suffocated outside", "other"]:
		var w = _good()
		w.stats.deaths_list.append({"t": w.t, "sol": 0, "clock_sol": 1, "being_id": 99, "name": "X", "cause": cause})
		_only_fails(t, _sample(w), "", "death by '%s' is not a shortage death" % cause)
	# Only entries since the previous boundary count (snap_deaths), and snapshots refresh before sol 5.
	var w2 = _good()
	w2.stats.deaths_list.append({"t": 0.0, "sol": 0, "clock_sol": 1, "being_id": 98, "name": "Old", "cause": "hunger"})
	_boundary(w2, 1)
	t.eq(w2.ages.snap_deaths, 1, "boundary 1 refreshes snap_deaths")
	_run(w2, 2, 4, _always)
	_boundary(w2, 5)
	t.eq(w2.ages.last_sample.get("no_shortage_death"), true, "an entry from before the previous boundary does not count")
	w2.stats.deaths_list.append({"t": w2.t, "sol": 5, "clock_sol": 6, "being_id": 99, "name": "New", "cause": "thirst"})
	_boundary(w2, 6)
	t.eq(w2.ages.last_sample.get("no_shortage_death"), false, "a new thirst death fails the next sample")
	t.eq(w2.ages.snap_deaths, 2, "snap_deaths follows the list length")
	_boundary(w2, 7)
	t.eq(w2.ages.last_sample.get("no_shortage_death"), true, "and the sample after it passes again")
	# Mixed: an accident then a shortage in the same sol still fails; an accident alone does not.
	w2.stats.deaths_list.append({"t": w2.t, "sol": 7, "clock_sol": 8, "being_id": 100, "name": "A", "cause": "suffocated outside"})
	_boundary(w2, 8)
	t.eq(w2.ages.last_sample.get("no_shortage_death"), true, "accident alone passes")
	w2.stats.deaths_list.append({"t": w2.t, "sol": 8, "clock_sol": 9, "being_id": 101, "name": "A", "cause": "suffocated outside"})
	w2.stats.deaths_list.append({"t": w2.t, "sol": 8, "clock_sol": 9, "being_id": 102, "name": "B", "cause": "air"})
	_boundary(w2, 9)
	t.eq(w2.ages.last_sample.get("no_shortage_death"), false, "accident plus air death fails")
	_end(t)


# ---------------------------------------------------------------- 5. ice

func test_t05_ice_two_sols_of_use(t) -> void:
	if not _api(t):
		return
	var ipb := float(SimData.colony().consumption.ice_per_being)
	for pop in [12, 100]:
		var w = _good(pop, 6 if pop == 12 else 0)
		var need: float = 2.0 * pop * ipb * w.clock.sol_h
		if pop == 12:
			t.near(need, 5.918, 0.001, "pop 12: 2 sols is 5.92")
		else:
			t.near(need, 49.32, 0.01, "pop 100: 2 sols is 49.3")
		w.colony.ice = need
		t.eq(_sample(w).get("ice"), true, "pop %d: exactly 2 sols passes (the CMP_EPS slack)" % pop)
		w.colony.ice = need - 5e-10
		t.eq(_sample(w).get("ice"), true, "pop %d: 5e-10 below is inside the slack" % pop)
		w.colony.ice = need - 1e-6
		t.eq(_sample(w).get("ice"), false, "pop %d: 1e-6 below fails" % pop)
		w.colony.ice = need + 1e-6
		t.eq(_sample(w).get("ice"), true, "pop %d: 1e-6 above passes" % pop)
		w.colony.ice = 0.0
		t.eq(_sample(w).get("ice"), false, "pop %d: dry fails" % pop)
		if pop == 12:
			w.colony.ice = need
			_only_fails(t, _sample(w), "", "pop 12 at exactly 2 sols: nothing else fails")
			w.colony.ice = need - 1e-6
			_only_fails(t, _sample(w), "ice", "pop 12 just under: only ice fails")
			# The sols of use are data.
			w.colony.ice = need
			_edit(_ad().sample, "ice_min_sols", 3.0)
			t.eq(_sample(w).get("ice"), false, "ice_min_sols 3: 2 sols is not enough")
			_restore()
	# It follows the population: the same ice that was fine for 12 is not for 100.
	var w2 = _good(100, 0)
	w2.colony.ice = 5.918
	t.eq(_sample(w2).get("ice"), false, "5.9 ice does not cover 100 beings")
	# It is never judged against ice_target (target for 12 is 120, far above 5.9).
	var w3 = _good()
	w3.colony.ice = 6.0
	t.check(w3.colony.ice_target() > 100.0, "the target is far above")
	t.eq(_sample(w3).get("ice"), true, "6.0 ice passes at pop 12 although it is under the target")
	_end(t)


# ---------------------------------------------------------------- 6. calm, rested

func _set_energy(w, from_i: int, count: int, e: float) -> void:
	for i in range(from_i, from_i + count):
		w.beings[i].energy = e


func test_t06_calm_share_and_boundaries(t) -> void:
	if not _api(t):
		return
	var w = _good(12, 6)
	# Spec section 10 test 6 at the shipped share: the boundaries below are for 0.2 (spec revision 4, section 19).
	t.eq(float(_ad().sample.distress_share_max), 0.2, "the shipped distress_share_max is 0.2 (the edge counts below assume it)")
	_set_energy(w, 0, 2, 11.9)
	_only_fails(t, _sample(w), "", "12 beings, 2 at 11.9 (share 0.167): calm passes")
	_set_energy(w, 2, 1, 11.9)
	_only_fails(t, _sample(w), "calm", "12 beings, 3 at 11.9 (0.25): calm fails")
	_reset_good(w)
	_set_energy(w, 0, 3, 12.0)
	_only_fails(t, _sample(w), "", "energy exactly 12.0 is not distress (3 of 12 at 12.0 pass)")
	_set_energy(w, 0, 3, 11.999)
	_only_fails(t, _sample(w), "calm", "energy 11.999 is distress (3 of 12 fails)")
	# Exactly 2 of 10 (0.2) passes; 3 of 10 fails.
	var w10 = _good(10, 4)
	_set_energy(w10, 0, 2, 5.0)
	_only_fails(t, _sample(w10), "", "2 of 10 distressed (exactly 0.2) passes")
	_set_energy(w10, 2, 1, 5.0)
	_only_fails(t, _sample(w10), "calm", "3 of 10 fails")
	# Pop 5 tolerates one distressed (1 <= 1.0); pop 4 does not (1 > 0.8).
	var w5 = _good(5, 2)
	_set_energy(w5, 0, 1, 5.0)
	t.eq(_sample(w5).get("calm"), true, "pop 5, one distressed passes")
	var w4 = _good(4, 2)
	_set_energy(w4, 0, 1, 5.0)
	t.eq(_sample(w4).get("calm"), false, "pop 4, one distressed fails")
	# Pop 9: one passes (1 <= 1.8), two fail (2 > 1.8).
	var w9 = _good(9, 4)
	_set_energy(w9, 0, 1, 5.0)
	t.eq(_sample(w9).get("calm"), true, "pop 9, one distressed passes")
	_set_energy(w9, 1, 1, 5.0)
	t.eq(_sample(w9).get("calm"), false, "pop 9, two distressed fail")
	# Pop 3: any single distressed being fails (1 > 0.6).
	var w3c = _good(3, 0)
	_set_energy(w3c, 0, 1, 5.0)
	t.eq(_sample(w3c).get("calm"), false, "pop 3, one distressed fails")
	# A being outside and turning back counts, whatever its energy.
	var wo = _good(12, 6)
	wo.beings[0].state = "eva"
	wo.beings[0].returning = true
	_only_fails(t, _sample(wo), "", "one turned-back being outside (energy 70): 1 of 12 passes")
	wo.beings[1].state = "mining"
	wo.beings[1].returning = true
	_only_fails(t, _sample(wo), "", "two turned back outside: 2 of 12 (0.167) passes")
	wo.beings[2].state = "eva"
	wo.beings[2].returning = true
	_only_fails(t, _sample(wo), "calm", "three turned back outside: 3 of 12 (0.25) fails")
	# Outside but not returning, and returning but inside, are not distress.
	var wn = _good(12, 6)
	for i in 3:
		wn.beings[i].state = "work"
		wn.beings[i].returning = false
	for i in range(3, 6):
		wn.beings[i].state = "idle"
		wn.beings[i].returning = true
	_only_fails(t, _sample(wn), "", "outside-not-returning and inside-returning are calm")
	# The share is data.
	var wd = _good(12, 6)
	_set_energy(wd, 0, 3, 5.0)
	_edit(_ad().sample, "distress_share_max", 0.25)
	_only_fails(t, _sample(wd), "", "distress_share_max 0.25: 3 of 12 passes")
	_restore()
	_only_fails(t, _sample(wd), "calm", "restored shipped 0.2: the same 3 of 12 fails")
	# The CMP_EPS slack, where it matters in doubles: 0.7 x 90 is 62.99999999999999, so 63 distressed of 90 would fail
	# without the slack although it is exactly the share.
	_edit(_ad().sample, "distress_share_max", 0.7)
	var w90 = _good(90, 0)
	_set_energy(w90, 0, 63, 5.0)
	t.eq(_sample(w90).get("calm"), true, "share 0.7, 63 of 90 distressed (exactly 0.7) passes through the slack")
	_set_energy(w90, 63, 1, 5.0)
	t.eq(_sample(w90).get("calm"), false, "64 of 90 fails")
	_restore()
	# Scale does not matter: 160 beings, same shares.
	var w160 = _good(160, 0)
	_set_energy(w160, 0, 32, 5.0)
	t.eq(_sample(w160).get("calm"), true, "160 beings, 32 distressed (exactly 0.2) passes")
	_set_energy(w160, 32, 1, 5.0)
	t.eq(_sample(w160).get("calm"), false, "160 beings, 33 distressed fails")
	_end(t)


func test_t06_rested_share_and_boundaries(t) -> void:
	if not _api(t):
		return
	var w = _good(12, 6)
	_set_energy(w, 0, 3, 20.0)
	_only_fails(t, _sample(w), "", "9 of 12 rested (0.75) passes")
	_set_energy(w, 3, 1, 20.0)
	_only_fails(t, _sample(w), "rested", "8 of 12 (0.667) fails")
	# Energy exactly 28.0 is rested; just under is not.
	var wb = _good(12, 6)
	_set_energy(wb, 0, 12, 28.0)
	_only_fails(t, _sample(wb), "", "all 12 at exactly 28.0 are rested")
	_set_energy(wb, 0, 3, 20.0)
	_set_energy(wb, 3, 1, 27.999)
	_only_fails(t, _sample(wb), "rested", "8 at 28.0 and one at 27.999: 8 rested, fails")
	# Exactly 7 of 10 (0.7) passes, 6 of 10 fails.
	var w10 = _good(10, 4)
	_set_energy(w10, 0, 3, 20.0)
	_only_fails(t, _sample(w10), "", "7 of 10 (exactly 0.7) passes")
	_set_energy(w10, 3, 1, 20.0)
	_only_fails(t, _sample(w10), "rested", "6 of 10 fails")
	# Pop 3 needs all 3.
	var w3 = _good(3, 0)
	_only_fails(t, _sample(w3), "", "pop 3, all rested passes")
	_set_energy(w3, 0, 1, 20.0)
	_only_fails(t, _sample(w3), "rested", "pop 3, 2 of 3 rested (0.667) fails")
	# The share is data.
	var wd = _good(10, 4)
	_set_energy(wd, 0, 4, 20.0)
	_edit(_ad().sample, "rested_share_min", 0.5)
	_only_fails(t, _sample(wd), "", "rested_share_min 0.5: 6 of 10 passes")
	_restore()
	_edit(_ad().sample, "rested_share_min", 0.9)
	_only_fails(t, _sample(wd), "rested", "rested_share_min 0.9: 6 of 10 fails")
	_restore()
	# The CMP_EPS slack, where it matters in doubles: 0.55 x 100 is 55.00000000000001, so exactly 55 of 100 rested would
	# fail without the slack.
	_edit(_ad().sample, "rested_share_min", 0.55)
	var w100 = _good(100, 0)
	_set_energy(w100, 0, 45, 20.0)
	t.eq(_sample(w100).get("rested"), true, "share 0.55, 55 of 100 rested (exactly 0.55) passes through the slack")
	_set_energy(w100, 45, 1, 20.0)
	t.eq(_sample(w100).get("rested"), false, "54 of 100 fails")
	_restore()
	# Scale: 160 beings, 112 rested (exactly 0.7) passes, 111 fails.
	var w160 = _good(160, 0)
	_set_energy(w160, 0, 48, 20.0)
	t.eq(_sample(w160).get("rested"), true, "160 beings, 112 rested passes")
	_set_energy(w160, 48, 1, 20.0)
	t.eq(_sample(w160).get("rested"), false, "160 beings, 111 rested fails")
	# Distress and rest are separate clauses: a being at 5 is neither calm nor rested.
	var ws = _good(12, 6)
	_set_energy(ws, 0, 4, 5.0)
	var s := _sample(ws)
	t.eq(s.get("calm"), false, "4 of 12 distressed (0.33): calm fails")
	t.eq(s.get("rested"), false, "and those 4 are not rested: 8 of 12 fails")
	_end(t)


# ---------------------------------------------------------------- 7. pop 0

func test_t07_pop_zero(t) -> void:
	if not _api(t):
		return
	var w = _good()
	w.beings.clear()
	t.eq(w.colony.pop(), 0, "no beings")
	w.stats.shorts = 3
	_run(w, 1, 8, _always)
	t.eq(w.ages.window.size(), 0, "pop 0: nothing appended at boundaries 5 to 8")
	t.eq(_age(w), "landing", "pop 0: the age is untouched")
	t.eq(w.stats.age, "landing", "stats.age keeps its value")
	t.eq(int(w.stats.sols_in_age.landing), 8, "sols_in_age still counts at pop 0")
	t.eq(w.ages.snap_shorts, 3, "snapshots refresh at pop 0")
	t.eq(int(w.stats.age_changes), 0, "no change")
	t.eq(w.stats.age_history.size(), 1, "no history entry")
	t.eq(_log_of(w, "age_began").size(), 0, "no age line (blank world)")
	# Pop returns: sampling resumes, and the old short does not count against the first sample.
	var g = _good()
	for b in g.beings:
		w.beings.append(b)
	_reset_good(w)
	_boundary(w, 9)
	t.eq(w.ages.window.size(), 1, "pop back: sampled again")
	t.eq(w.ages.window[0].ok, true, "the sample is ok (snapshot was refreshed at pop 0)")
	t.eq(int(w.stats.sols_in_age.landing), 9, "credit continues")
	# A long empty stretch inside Settlement keeps the age.
	var w2 = _good()
	_run(w2, 1, 44, _always)
	t.eq(_age(w2), "settlement", "settled")
	w2.beings.clear()
	_run(w2, 45, 110, _always)
	t.eq(_age(w2), "settlement", "pop 0 for 66 sols: age frozen, no fall back")
	t.eq(int(w2.stats.age_changes), 1, "still one change")
	t.eq(w2.ages.window.size(), 40, "window not touched")
	t.eq(int(w2.stats.sols_in_age.settlement), 66, "sols_in_age keeps counting (settlement credited from boundary 45)")
	# Frozen means frozen: a settled colony whose injected window says "leave" does not decide while nobody is alive.
	var w3 = _good()
	w3.beings.clear()
	_inject(w3, "settlement", "x".repeat(40), 0)
	_run(w3, 60, 70, _always)
	t.eq(_age(w3), "settlement", "pop 0 with a leaving window: no exit, the age is frozen")
	t.eq(int(w3.stats.age_changes), 0, "no change at pop 0")
	t.eq(_log_of(w3, "age_began").size(), 0, "no age line at pop 0")
	t.eq(w3.ages.window.size(), 40, "window untouched")
	t.eq(w3.ages.window[39].ok, false, "and still the injected one")
	_end(t)


# ---------------------------------------------------------------- 8. samples start at sol 5

func test_t08_samples_start_at_sol_five(t) -> void:
	if not _api(t):
		return
	var w = _good()
	t.eq(_ad().sample.from_sol, 5, "data: from_sol")
	w.stats.shorts = 2
	w.stats.deaths_list.append({"t": 0.0, "sol": 0, "clock_sol": 1, "being_id": 90, "name": "Old", "cause": "thirst"})
	for n in range(1, 5):
		_reset_good(w)
		_boundary(w, n)
		t.eq(w.ages.window.size(), 0, "boundary %d appends nothing" % n)
		t.eq(w.ages.snap_shorts, 2, "boundary %d: snap_shorts refreshed" % n)
		t.eq(w.ages.snap_deaths, 1, "boundary %d: snap_deaths refreshed" % n)
		t.eq(int(w.stats.sols_in_age.landing), n, "boundary %d: credited" % n)
	_boundary(w, 5)
	t.eq(w.ages.window.size(), 1, "boundary 5 appends the first sample")
	t.eq(w.ages.window[0].ok, true, "and, with the pre-5 shorts and deaths snapshotted, it is ok")
	_boundary(w, 6)
	t.eq(w.ages.window.size(), 2, "boundary 6: two")
	# The window is capped at window_sols, newest last.
	_run(w, 7, 60, func(n: int) -> bool: return n != 60)
	t.eq(w.ages.window.size(), 40, "the window holds window_sols samples")
	t.eq(w.ages.window.back().ok, false, "newest last")
	t.eq(w.ages.window[38].ok, true, "the one before it is ok")
	# on_sol uses the sol of the world clock: a boundary is judged by sol(), not by call count.
	var w2 = _good()
	_boundary(w2, 5)
	t.eq(w2.ages.window.size(), 1, "a first call at sol 5 already samples")
	var w3 = _good()
	_boundary(w3, 4)
	t.eq(w3.ages.window.size(), 0, "a first call at sol 4 does not")
	_end(t)


# ---------------------------------------------------------------- 9. full ok history

func test_t09_full_ok_history_enters_at_44(t) -> void:
	if not _api(t):
		return
	var w = _good()
	for n in range(1, 44):
		_reset_good(w)
		_boundary(w, n)
		t.eq(_age(w), "landing", "boundary %d: still landing" % n)
	t.eq(w.ages.window.size(), 39, "39 samples at boundary 43: not full")
	_reset_good(w)
	_boundary(w, 44)
	t.eq(_age(w), "settlement", "boundary 44: settlement")
	t.eq(w.stats.age, "settlement", "stats.age")
	t.eq(int(w.ages.last_change_sol), 44, "last_change_sol")
	var lines := _log_of(w, "age_began")
	t.eq(lines.size(), 1, "exactly one age_began (a blank world logs nothing at creation)")
	if lines.size() == 1:
		t.eq(lines[0].how, "settled", "how")
		t.eq(lines[0].age, "settlement", "age")
		t.eq(lines[0].text, _line(w, "settled", "", lines[0].t), "text: settlement.log_enter plus the season sentence")
		t.eq(int(lines[0].sol), 44, "log sol")
		t.eq(int(lines[0].clock_sol), w.clock.sol_index(w.t), "log clock_sol")
	t.eq(int(w.stats.first_settlement_sol), 44, "first_settlement_sol")
	t.eq(int(w.stats.age_changes), 1, "age_changes")
	t.eq(int(w.stats.sols_in_age.landing), 44, "landing credited for sols 1..44 (credit comes before decide)")
	t.eq(int(w.stats.sols_in_age.settlement), 0, "settlement not yet credited")
	var h: Array = w.stats.age_history
	t.eq(h.size(), 2, "history: landing then settled")
	if h.size() == 2:
		t.eq(h[1].age, "settlement", "history age")
		t.eq(h[1].how, "settled", "history how")
		t.eq(h[1].cause, null, "history cause is null for a settle")
		t.eq(h[1].text, lines[0].text if lines.size() == 1 else "", "history text equals the log text")
		t.eq(int(h[1].pop), 12, "history pop")
		t.eq(int(h[1].family_mars_born), 6, "history family_mars_born")
		t.eq(int(h[1].sol), 44, "history sol")
		t.eq(int(h[1].clock_sol), w.clock.sol_index(w.t), "history clock_sol")
		t.near(float(h[1].t), w.t, 1e-9, "history t")
	_reset_good(w)
	_boundary(w, 45)
	t.eq(int(w.stats.sols_in_age.settlement), 1, "boundary 45 credits settlement")
	t.eq(_log_of(w, "age_began").size(), 1, "no second line")
	t.eq(int(w.stats.first_settlement_sol), 44, "first_settlement_sol unchanged")
	_end(t)


# ---------------------------------------------------------------- 10. tolerance edge

func test_t10_tolerance_edge(t) -> void:
	if not _api(t):
		return
	# 36 ok / 4 not ok, none in the last 3: enters at 44.
	var w = _good()
	_run(w, 1, 44, _except([20, 21, 30, 31]))
	t.eq(_age(w), "settlement", "36 ok / 4 not ok enters at 44")
	# Four failing sols at 5 to 8 still enter at 44 (and not at 43).
	var w2 = _good()
	_run(w2, 1, 43, _except([5, 6, 7, 8]))
	t.eq(_age(w2), "landing", "43: window not full")
	_run(w2, 44, 44, _except([5, 6, 7, 8]))
	t.eq(_age(w2), "settlement", "failures at 5..8 still enter at 44")
	t.eq(int(w2.stats.first_settlement_sol), 44, "first_settlement_sol 44")
	# 35 ok / 5 not ok does not enter at 44 ...
	var w3 = _good()
	_run(w3, 1, 44, _except([5, 6, 7, 8, 9]))
	t.eq(_age(w3), "landing", "35 ok / 5 not ok does not enter at 44")
	t.eq(int(w3.stats.age_changes), 0, "no change")
	# ... but the window slides, and at 45 the oldest failure is gone: 36 ok.
	_run(w3, 45, 45, _except([5, 6, 7, 8, 9]))
	t.eq(_age(w3), "settlement", "one sol later 36 ok / 4 not ok enters")
	t.eq(int(w3.ages.last_change_sol), 45, "at 45")
	# Pure decide, both sides of 36 / 35, and the data behind them.
	t.eq(_decide("landing", "xxxx" + "o".repeat(36)), "settlement", "decide: 36 ok enters")
	t.eq(_decide("landing", "xxxxx" + "o".repeat(35)), "landing", "decide: 35 ok does not")
	t.eq(_decide("landing", "o".repeat(10) + "xxxx" + "o".repeat(26)), "settlement", "decide: 36 ok, failures in the middle")
	t.eq(_decide("landing", "o".repeat(40)), "settlement", "decide: 40 ok")
	t.eq(_decide("landing", "o".repeat(39)), "landing", "decide: a 39-sample window is not full")
	t.eq(_ad().entry.ok_share, 0.9, "data: entry.ok_share")
	t.eq(int(_ad().sample.window_sols), 40, "data: window_sols")
	# The share is data: 0.95 over 40 needs 38 ok.
	_edit(_ad().entry, "ok_share", 0.95)
	t.eq(_decide("landing", "xx" + "o".repeat(38)), "settlement", "ok_share 0.95: 38 ok enters")
	t.eq(_decide("landing", "xxx" + "o".repeat(37)), "landing", "ok_share 0.95: 37 ok does not")
	_restore()
	_end(t)


# ---------------------------------------------------------------- 11. last 3

func test_t11_last_three_block_entry(t) -> void:
	if not _api(t):
		return
	# 37 ok then 3 not ok blocks at 44; entry exactly when the third consecutive ok arrives (47).
	var w = _good()
	_run(w, 1, 44, _except([42, 43, 44]))
	t.eq(_age(w), "landing", "37 ok then 3 not ok blocks")
	_run(w, 45, 45, _always)
	t.eq(_age(w), "landing", "45: last 3 = not, not, ok")
	_run(w, 46, 46, _always)
	t.eq(_age(w), "landing", "46: last 3 = not, ok, ok")
	_run(w, 47, 47, _always)
	t.eq(_age(w), "settlement", "47: the third consecutive ok enters (37 ok in the window)")
	t.eq(int(w.ages.last_change_sol), 47, "exactly at 47")
	# 39 ok then 1 not ok blocks, although the share is 97.5 percent.
	var w2 = _good()
	_run(w2, 1, 44, _except([44]))
	t.eq(_age(w2), "landing", "39 ok then 1 not ok blocks")
	_run(w2, 45, 46, _always)
	t.eq(_age(w2), "landing", "45 and 46 still block")
	_run(w2, 47, 47, _always)
	t.eq(_age(w2), "settlement", "47 enters")
	t.eq(int(w2.ages.last_change_sol), 47, "exactly at 47")
	# A failure at the third-last position blocks too, one earlier does not.
	t.eq(_decide("landing", "o".repeat(37) + "xoo"), "landing", "decide: x at the third-last blocks")
	t.eq(_decide("landing", "o".repeat(36) + "xooo"), "settlement", "decide: x fourth-last does not")
	t.eq(_decide("landing", "o".repeat(37) + "oox"), "landing", "decide: x last blocks")
	t.eq(_decide("landing", "o".repeat(37) + "oxo"), "landing", "decide: x second-last blocks")
	t.eq(int(_ad().entry.recent_ok_sols), 3, "data: recent_ok_sols")
	_end(t)


# ---------------------------------------------------------------- 12. family Mars-born

func test_t12_family_mars_born(t) -> void:
	if not _api(t):
		return
	# 4 family Mars-born block (perfect window), the 5th enters at the next boundary.
	var w = _good(12, 4)
	_run(w, 1, 50, _always)
	t.eq(_age(w), "landing", "4 family Mars-born: blocked through 50 with a perfect window")
	var nb = w.add_being(_hab_a(w))
	nb.earth_born = false
	nb.parent_id = w.beings[0].id
	nb.birth_building_id = _hab_b(w)
	_run(w, 51, 51, _always)
	t.eq(_age(w), "settlement", "the 5th enters at the next boundary")
	t.eq(int(w.stats.first_settlement_sol), 51, "first_settlement_sol 51")
	t.eq(int(w.stats.age_history.back().family_mars_born), 5, "history records family_mars_born 5")
	# Orphans do not count: parent_id 0 and a parent id that is not alive.
	var w2 = _good(12, 6)
	var mars: Array = []
	for b in w2.beings:
		if not b.earth_born:
			mars.append(b)
	mars[0].parent_id = 0
	mars[1].parent_id = 9999
	_run(w2, 1, 46, _always)
	t.eq(_age(w2), "landing", "2 orphans of 6: only 4 count, blocked")
	# A parent who dies orphans every child of theirs (checked at the boundary): 3 children of founder 0, 3 of founder 1.
	var w4 = _good(12, 6)
	var kids: Array = []
	for b in w4.beings:
		if not b.earth_born:
			kids.append(b)
	for i in kids.size():
		kids[i].parent_id = w4.beings[0].id if i < 3 else w4.beings[1].id
	var control = _good(12, 6)
	_run(control, 1, 44, _always)
	t.eq(_age(control), "settlement", "6 family Mars-born enter (control)")
	_run(w4, 1, 44, _always)
	t.eq(_age(w4), "settlement", "3 + 3 children with both parents alive enter")
	var w4b = _good(12, 6)
	var kids_b: Array = []
	for b in w4b.beings:
		if not b.earth_born:
			kids_b.append(b)
	for i in kids_b.size():
		kids_b[i].parent_id = w4b.beings[0].id if i < 3 else w4b.beings[1].id
	w4b.beings.erase(w4b.beings[0])
	_run(w4b, 1, 50, _always)
	t.eq(_age(w4b), "landing", "founder 0 dead: its 3 children no longer count (3 left), blocked")
	# 5 in one birth habitat block until a second habitat is represented.
	var w5 = _good(12, 5)
	for b in w5.beings:
		if not b.earth_born:
			b.birth_building_id = _hab_a(w5)
	_run(w5, 1, 50, _always)
	t.eq(_age(w5), "landing", "5 family Mars-born, all born in one habitat: blocked")
	for b in w5.beings:
		if not b.earth_born:
			b.birth_building_id = _hab_b(w5)
			break
	_run(w5, 51, 51, _always)
	t.eq(_age(w5), "settlement", "a second birth habitat represented: enters at the next boundary")
	t.eq(int(w5.stats.age_history.back().family_mars_born), 5, "5 counted")
	# Earth-born founders do not count, whatever their parent_id and birth_building_id.
	var w6 = _good(12, 4)
	var n_set := 0
	for b in w6.beings:
		if b.earth_born and n_set < 3:
			b.parent_id = w6.beings[n_set + 1].id
			b.birth_building_id = _hab_b(w6) if n_set % 2 == 0 else _hab_a(w6)
			n_set += 1
	_run(w6, 1, 46, _always)
	t.eq(_age(w6), "landing", "4 Mars-born plus 3 Earth-born with parents: still 4")
	# Dead Mars-born do not count.
	var w7 = _good(12, 6)
	var dead := 0
	for b in w7.beings.duplicate():
		if not b.earth_born and dead < 2:
			w7.beings.erase(b)
			dead += 1
	_run(w7, 1, 46, _always)
	t.eq(_age(w7), "landing", "2 of 6 Mars-born dead: 4 count")
	# Pure decide: the two counts are arguments.
	var A = load("res://sim/ages.gd")
	var full := _win("o".repeat(40))
	t.eq(A.decide(full, "landing", 30, 4, 2), "landing", "decide: family 4 blocks")
	t.eq(A.decide(full, "landing", 30, 5, 2), "settlement", "decide: family 5, homes 2 enters")
	t.eq(A.decide(full, "landing", 30, 5, 1), "landing", "decide: homes 1 blocks")
	t.eq(A.decide(full, "landing", 30, 50, 1), "landing", "decide: many in one habitat blocks")
	t.eq(A.decide(full, "landing", 30, 4, 9), "landing", "decide: many habitats but 4 blocks")
	t.eq(A.decide(full, "landing", 30, 0, 0), "landing", "decide: none")
	# Entry-only clause: a settled colony whose family count falls to 0 stays.
	t.eq(A.decide(full, "settlement", 30, 0, 0), "settlement", "decide: family count is not an exit clause")
	t.eq(int(_ad().entry.mars_born_min), 5, "data: mars_born_min")
	t.eq(int(_ad().entry.mars_born_homes_min), 2, "data: mars_born_homes_min")
	_end(t)


# ---------------------------------------------------------------- 13. dead band

func test_t13_dead_band_pure(t) -> void:
	if not _api(t):
		return
	# 24 ok stays; 23 ok with one not ok in the last 5 leaves; 23 ok with the last 5 all ok stays.
	t.eq(_decide("settlement", "o".repeat(24) + "x".repeat(16)), "settlement", "24 ok stays")
	t.eq(_decide("settlement", "o".repeat(23) + "x".repeat(17)), "landing", "23 ok, last 5 not ok: leaves")
	t.eq(_decide("settlement", "x".repeat(16) + "o".repeat(19) + "xoooo"), "landing", "23 ok, one not ok in the last 5: leaves")
	t.eq(_decide("settlement", "x".repeat(17) + "o".repeat(23)), "settlement", "23 ok, last 5 all ok: stays")
	t.eq(_decide("settlement", "x".repeat(18) + "o".repeat(22)), "settlement", "22 ok, last 5 all ok: stays")
	t.eq(_decide("settlement", "x".repeat(16) + "o".repeat(19) + "ooxoo"), "landing", "23 ok, x in the middle of the last 5")
	t.eq(_decide("settlement", "x".repeat(15) + "o".repeat(20) + "ooooo"), "settlement", "25 ok stays")
	t.eq(_decide("settlement", "o".repeat(36) + "x".repeat(4)), "settlement", "36 ok stays (settled)")
	t.eq(_decide("settlement", "o".repeat(35) + "x".repeat(5)), "settlement", "35 ok stays (dead band)")
	t.eq(_decide("settlement", "o".repeat(30) + "x".repeat(10)), "settlement", "30 ok stays")
	t.eq(_decide("settlement", "x".repeat(40)), "landing", "all not ok leaves")
	t.eq(_decide("settlement", "x".repeat(39)), "settlement", "a 39-sample window is not full")
	# Dwell is part of every change.
	t.eq(_decide("settlement", "x".repeat(40), 19), "settlement", "exit blocked at dwell 19")
	t.eq(_decide("settlement", "x".repeat(40), 20), "landing", "exit allowed at dwell 20")
	t.eq(_decide("landing", "o".repeat(40), 19), "landing", "entry blocked at dwell 19")
	t.eq(_decide("landing", "o".repeat(40), 20), "settlement", "entry allowed at dwell 20")
	# In the dead band a landing colony stays too (no entry), and the last-5 clause is exit only.
	t.eq(_decide("landing", "o".repeat(30) + "x".repeat(10)), "landing", "landing with 30 ok stays")
	t.eq(_decide("landing", "o".repeat(23) + "x".repeat(17)), "landing", "landing with 23 ok stays")
	# Data behind them.
	t.eq(_ad().exit.ok_share_below, 0.6, "data: exit.ok_share_below")
	t.eq(int(_ad().exit.recent_sols), 5, "data: exit.recent_sols")
	_edit(_ad().exit, "recent_sols", 3)
	t.eq(_decide("settlement", "x".repeat(17) + "o".repeat(19) + "xooo"), "settlement", "recent_sols 3: x fourth-last is outside, stays")
	t.eq(_decide("settlement", "x".repeat(17) + "o".repeat(19) + "ooxo"), "landing", "recent_sols 3: x second-last leaves")
	_restore()
	_edit(_ad().exit, "ok_share_below", 0.7)
	t.eq(_decide("settlement", "o".repeat(27) + "x".repeat(13)), "landing", "ok_share_below 0.7: 27 ok (exit max 27) leaves")
	t.eq(_decide("settlement", "o".repeat(28) + "x".repeat(12)), "settlement", "ok_share_below 0.7: 28 ok stays")
	_restore()
	# The window passed in is never modified.
	var win := _win("x".repeat(40))
	var before := str(win)
	var A = load("res://sim/ages.gd")
	A.decide(win, "settlement", 30, 5, 2)
	t.eq(str(win), before, "decide does not modify its window")
	_end(t)


## The same edges through on_sol, so the hook feeds decide the right numbers (the injected 39 plus the boundary's own
## sample make the 40; the dwell is long over).
func test_t13_dead_band_through_on_sol(t) -> void:
	if not _api(t):
		return
	var never := func(_k: int) -> bool: return false
	var w = _good()
	_inject(w, "settlement", "x".repeat(15) + "o".repeat(24), 0)
	_run(w, 60, 60, never)
	t.eq(w.ages.window.size(), 40, "injected 39 plus the new sample")
	t.eq(_age(w), "settlement", "24 ok (24 injected + a not-ok sample), last 5 not all ok: stays")
	var w2 = _good()
	_inject(w2, "settlement", "x".repeat(16) + "o".repeat(23), 0)
	_run(w2, 60, 60, never)
	t.eq(_age(w2), "landing", "23 ok, the new sample not ok: leaves")
	t.eq(int(w2.ages.last_change_sol), 60, "at 60")
	var w3 = _good()
	_inject(w3, "settlement", "x".repeat(17) + "o".repeat(22), 0)
	_run(w3, 60, 60, _always)
	t.eq(_age(w3), "settlement", "23 ok with the last 5 all ok (the new sample ok): stays")
	# The same injected window one sol after the entry is held by the dwell (last_change_sol 55, boundary 60).
	var w4 = _good()
	_inject(w4, "settlement", "x".repeat(16) + "o".repeat(23), 55)
	_run(w4, 60, 60, never)
	t.eq(_age(w4), "settlement", "dwell 5: held")
	var w5 = _good()
	_inject(w5, "settlement", "x".repeat(16) + "o".repeat(23), 40)
	_run(w5, 60, 60, never)
	t.eq(_age(w5), "landing", "dwell 20: free to go")
	# Entry through on_sol with an injected window: 35 + the new ok sample = 36 enters; 34 + 1 does not.
	var w6 = _good()
	_inject(w6, "landing", "xxxx" + "o".repeat(35), 0)
	_run(w6, 60, 60, _always)
	t.eq(_age(w6), "settlement", "36 ok after the new sample: enters")
	var w7 = _good()
	_inject(w7, "landing", "xxxxx" + "o".repeat(34), 0)
	_run(w7, 60, 60, _always)
	t.eq(_age(w7), "landing", "35 ok after the new sample: stays")
	_end(t)


# ---------------------------------------------------------------- 14. dwell, flapping

## Fail 5..64, ok 65..100 puts the entry exactly at 100 (fails 61..64 are 4 of 40, the 99 window had 5).
func test_t14_dwell_on_exit_and_entry(t) -> void:
	if not _api(t):
		return
	var w = _good()
	var ok_fn := func(n: int) -> bool: return n >= 65
	_run(w, 1, 99, ok_fn)
	t.eq(_age(w), "landing", "99: 5 failures in the window, still landing")
	_run(w, 100, 100, ok_fn)
	t.eq(_age(w), "settlement", "entered at sol 100")
	t.eq(int(w.ages.last_change_sol), 100, "last_change_sol 100")
	# Then every sol not ok. By the window alone the exit is open at 117 (23 ok); the dwell holds it to 120.
	var never := func(_n: int) -> bool: return false
	for n in range(101, 120):
		_run(w, n, n, never)
		t.eq(_age(w), "settlement", "sol %d: no exit before the dwell is over" % n)
	t.eq(w.ages.window.size(), 40, "window full")
	_run(w, 120, 120, never)
	t.eq(_age(w), "landing", "exit at 120 (20 sols after the entry)")
	t.eq(int(w.ages.last_change_sol), 120, "last_change_sol 120")
	var falls := 0
	for e in _log_of(w, "age_began"):
		if e.how == "fell_back":
			falls += 1
	t.eq(falls, 1, "exactly one fell_back line")
	t.eq(int(w.stats.age_changes), 2, "two changes in all")
	# After the fall-back an injected perfect window: entry blocked at +19, allowed at +20.
	w.ages.window = _win("o".repeat(40))
	_run(w, 121, 139, _always)
	t.eq(_age(w), "landing", "139 = last_change_sol + 19: entry blocked by the dwell")
	_run(w, 140, 140, _always)
	t.eq(_age(w), "settlement", "140 = last_change_sol + 20: allowed")
	var hows: Array = []
	for e in w.stats.age_history:
		hows.append(e.how)
	t.eq(hows, ["landing", "settled", "fell_back", "settled_again"], "history hows")
	# And the other way round: an entry at sol 44 cannot be undone before 64 however bad the sols.
	var w2 = _good()
	_run(w2, 1, 44, _always)
	for n in range(45, 64):
		_run(w2, n, n, never)
		t.eq(_age(w2), "settlement", "sol %d (entry 44): held by the dwell" % n)
	_run(w2, 64, 64, never)
	t.eq(_age(w2), "landing", "64: out")
	t.eq(int(_ad().min_dwell_sols), 20, "data: min_dwell_sols")
	_end(t)


func _simulate(start_age: String, flags: Callable, sols: int) -> Array:
	var A = load("res://sim/ages.gd")
	var from_sol := int(_ad().sample.from_sol)
	var cap := int(_ad().sample.window_sols)
	var win: Array = []
	var age := start_age
	var last := 0
	var changes: Array = []
	var ok_entry := {"ok": true, "failed": []}
	var bad_entry := {"ok": false, "failed": ["ice"]}
	for n in range(1, sols + 1):
		if n >= from_sol:
			win.append(ok_entry if flags.call(n, age) else bad_entry)
			if win.size() > cap:
				win.pop_front()
		var next: String = A.decide(win, age, n - last, 10, 3)
		if next != age:
			changes.append([n, next])
			age = next
			last = n
	return changes


func test_t14_square_waves_and_flapping(t) -> void:
	if not _api(t):
		return
	for p in [2, 3, 5, 8, 12, 24]:
		var wave := func(n: int, _a: String) -> bool: return (n % p) < p / 2.0
		var from_landing := _simulate("landing", wave, 3000)
		t.eq(from_landing.size(), 0, "period %d from Landing: no change in 3000 sols" % p)
		var from_settle := _simulate("settlement", wave, 3000)
		t.check(from_settle.size() <= 1, "period %d from Settlement: at most one change (%d)" % [p, from_settle.size()])
		if from_settle.size() == 1:
			t.eq(from_settle[0][1], "landing", "period %d: the one change is to Landing, never back" % p)
	# 13 ok / 13 not ok repeated.
	var w1313 := func(n: int, _a: String) -> bool: return (n % 26) < 13
	for start in ["landing", "settlement"]:
		var ch := _simulate(start, w1313, 3000)
		t.check(ch.size() <= 3000 / 20, "13/13 from %s: %d changes within floor(sols / 20)" % [start, ch.size()])
		for i in range(1, ch.size()):
			t.check(ch[i][0] - ch[i - 1][0] >= 20, "13/13: gap %d" % (ch[i][0] - ch[i - 1][0]))
	# Adversary: always the move that would change the age next (ok while landing, not ok while settled).
	var adv := func(_n: int, a: String) -> bool: return a == "landing"
	var ch2 := _simulate("landing", adv, 2000)
	t.check(ch2.size() >= 5, "adversary does force changes (%d), so the gap check below means something" % ch2.size())
	t.check(ch2.size() <= 2000 / 20 + 1, "adversary: %d changes in 2000 sols" % ch2.size())
	var min_gap := 99999
	for i in range(1, ch2.size()):
		min_gap = mini(min_gap, ch2[i][0] - ch2[i - 1][0])
	t.check(ch2.size() < 2 or min_gap >= 20, "adversary: no two changes closer than 20 sols (min gap %d)" % min_gap)
	var alternates := true
	for i in ch2.size():
		if ch2[i][1] != ("settlement" if i % 2 == 0 else "landing"):
			alternates = false
	t.check(alternates, "adversary: changes alternate settlement / landing")
	# Data sanity: the dead band and dwell bounds of spec 6.2.
	var ad := _ad()
	var wsols := int(ad.sample.window_sols)
	var req_ok := int(ceil(float(ad.entry.ok_share) * wsols - 1e-9))
	var exit_max := int(ceil(float(ad.exit.ok_share_below) * wsols - 1e-9)) - 1
	t.eq(req_ok, 36, "required ok to enter")
	t.eq(exit_max, 23, "ok at or below which a settled colony may leave")
	t.check(req_ok - exit_max >= 13, "dead band: (36 - 23) >= 13")
	t.check(int(ad.min_dwell_sols) >= 13, "min_dwell_sols >= 13")
	t.check(float(ad.exit.ok_share_below) < float(ad.entry.ok_share), "exit.ok_share_below < entry.ok_share")
	_end(t)


# ---------------------------------------------------------------- 15. causes

func _groups_window(spec: Array) -> Array:
	# spec: [[groups...], count] pairs; each sample fails exactly the listed groups; 40 total padded with ok.
	var out: Array = []
	for pair in spec:
		for i in int(pair[1]):
			out.append({"ok": false, "failed": pair[0].duplicate()})
	while out.size() < 40:
		out.append({"ok": true, "failed": []})
	return out


func test_t15_dominant_cause_pure(t) -> void:
	if not _api(t):
		return
	var A = load("res://sim/ages.gd")
	t.eq(A.dominant_cause(_groups_window([[["ice"], 20], [["food"], 5]])), "ice", "20 ice vs 5 food: ice")
	t.eq(A.dominant_cause(_groups_window([[["food"], 6], [["oxygen"], 5]])), "food", "6 food vs 5 oxygen: food")
	t.eq(A.dominant_cause(_groups_window([[["food"], 5], [["oxygen"], 6]])), "oxygen", "5 food vs 6 oxygen: oxygen")
	t.eq(A.dominant_cause(_groups_window([[["unrest"], 3], [["death"], 2]])), "unrest", "3 unrest vs 2 death: unrest")
	t.eq(A.dominant_cause(_groups_window([[["death"], 3], [["power"], 2]])), "death", "death outcounts power")
	t.eq(A.dominant_cause(_groups_window([[["power"], 1]])), "power", "a lone power failure")
	# Several groups in one sample each count once: food in 3 samples (two shared with ice) beats ice in 2.
	t.eq(A.dominant_cause(_groups_window([[["ice", "food"], 2], [["food"], 1]])), "food", "food 3 vs ice 2")
	# Ties follow the fixed order ice, food, oxygen, power, death, unrest, for every pair.
	for i in GROUPS.size():
		for j in range(i + 1, GROUPS.size()):
			var win := _groups_window([[[GROUPS[j]], 4], [[GROUPS[i]], 4]])
			t.eq(A.dominant_cause(win), GROUPS[i], "tie %s vs %s: %s" % [GROUPS[i], GROUPS[j], GROUPS[i]])
			var win2 := _groups_window([[[GROUPS[i]], 4], [[GROUPS[j]], 4]])
			t.eq(A.dominant_cause(win2), GROUPS[i], "tie (reverse order in the window) %s vs %s" % [GROUPS[i], GROUPS[j]])
	t.eq(A.dominant_cause(_groups_window([[["unrest"], 2], [["death"], 2], [["power"], 2]])), "power", "three-way tie: power")
	t.eq(A.dominant_cause(_groups_window([[["unrest"], 2], [["death"], 2], [["power"], 2], [["oxygen"], 2], [["food"], 2], [["ice"], 2]])), "ice", "six-way tie: ice")
	# The window order does not matter, only the counts.
	var win3: Array = _groups_window([[["food"], 3], [["ice"], 3]])
	win3.reverse()
	t.eq(A.dominant_cause(win3), "ice", "reversed window, tie: ice")
	_end(t)


func _fixture(w, label: String) -> void:
	match label:
		"oxygen_stock":
			w.colony.oxygen = 0.0
		"food_stock":
			w.colony.food = 0.0
		"ice":
			w.colony.ice = 0.0
		"budget":
			w.add_building("workshop", 160, 0)
			w.add_building("workshop", 200, 0)
		"offline":
			w.set_offline(_hab_b(w), true)
		"short":
			w.stats.shorts += 1
		"death":
			_break(w, "death")
		"calm":
			w.beings[0].energy = 5.0
			w.beings[1].energy = 5.0
			w.beings[2].energy = 5.0
		"rested":
			_break(w, "unrest")


## Every clause belongs to the group the spec names (4.3), seen in the window entry on_sol appends.
func test_t15_clause_to_group_mapping(t) -> void:
	if not _api(t):
		return
	var cases := [
		["1a oxygen stock", "oxygen_stock", ["oxygen"]],
		["1b food stock", "food_stock", ["food"]],
		["5 ice", "ice", ["ice"]],
		["3a power budget", "budget", ["power"]],
		["3b none_offline", "offline", ["power"]],
		["3c no_short", "short", ["power"]],
		["4 death", "death", ["death"]],
		["6 calm", "calm", ["unrest"]],
		["7 rested", "rested", ["unrest"]],
	]
	for c in cases:
		var w = _good()
		_run(w, 1, 4, _always)
		_reset_good(w)
		_fixture(w, c[1])
		_boundary(w, 5)
		var e = w.ages.window.back()
		t.eq(e.ok, false, "%s: not ok" % c[0])
		var failed: Array = []
		for g in GROUPS:
			if g in e.failed:
				failed.append(g)
		t.eq(failed, c[2], "%s: failed groups" % c[0])
		t.eq(e.failed.size(), c[2].size(), "%s: nothing else in the set" % c[0])
	# 2a o2_net and 2b food_net map to oxygen and food.
	var w28 = _good(28, 0)
	_boundary(w28, 5)
	t.eq(w28.ages.window.back().failed.size(), 1, "28 beings: one group")
	t.check("oxygen" in w28.ages.window.back().failed, "2a o2_net is oxygen")
	var wf = _good()
	_edit(SimData.colony().production, "food_per_green_room", 0.3)
	_boundary(wf, 5)
	t.eq(wf.ages.window.back().failed.size(), 1, "food net: one group")
	t.check("food" in wf.ages.window.back().failed, "2b food_net is food")
	_restore()
	# Two breaks at once: both groups in one sample.
	var wm = _good()
	wm.colony.ice = 0.0
	wm.colony.food = 0.0
	_boundary(wm, 5)
	t.check("ice" in wm.ages.window.back().failed and "food" in wm.ages.window.back().failed, "ice and food together")
	t.eq(wm.ages.window.back().failed.size(), 2, "exactly the two")
	# An ok sample has an empty failed set.
	var wo = _good()
	_boundary(wo, 5)
	t.eq(wo.ages.window.back().failed.size(), 0, "ok sample: nothing failed")
	t.eq(wo.ages.window.back().ok, true, "ok sample: ok")
	t.eq(wo.ages.last_sample.get("ice"), true, "last_sample is the sample just taken")
	_end(t)


# ---------------------------------------------------------------- 16. log lines, history, stats

func test_t16_landing_line_founder_and_blank(t) -> void:
	if not _api(t):
		return
	var w = SimWorld.new(42)
	t.eq(w.log.size(), 2, "founder world: two lines at creation")
	if w.log.size() == 2:
		t.eq(w.log[0].kind, "founders_landed", "first line: founders_landed")
		t.eq(w.log[1].kind, "age_began", "second line: age_began")
		t.eq(w.log[1].how, "landing", "how landing")
		t.eq(w.log[1].age, "landing", "age landing")
		t.eq(w.log[1].text, _ad().landing.log_start, "the data text, no season sentence")
		t.check(w.log[1].text.contains("founders"), "'founders' appears in the start line")
	t.eq(w.stats.age, "landing", "stats.age")
	t.eq(int(w.stats.age_changes), 0, "age_changes 0")
	t.eq(w.stats.first_settlement_sol, null, "first_settlement_sol null")
	t.eq(w.stats.sols_in_age, {"landing": 0, "settlement": 0}, "sols_in_age zeros")
	t.eq(w.stats.age_history.size(), 1, "founder world: one history entry")
	if w.stats.age_history.size() == 1:
		var h: Dictionary = w.stats.age_history[0]
		t.eq(h.age, "landing", "entry age")
		t.eq(h.how, "landing", "entry how")
		t.eq(h.cause, null, "entry cause")
		t.eq(h.text, _ad().landing.log_start, "entry text")
		t.eq(int(h.pop), 7, "entry pop 7")
		t.eq(int(h.family_mars_born), 0, "entry family_mars_born 0")
		t.eq(int(h.sol), 0, "entry sol 0")
		t.eq(int(h.clock_sol), 1, "entry clock_sol 1")
		t.near(float(h.t), w.t, 1e-9, "entry t")
	# Blank world: nothing logged, but the same history entry.
	var b = SimWorld.new(1, {"blank": true})
	t.eq(b.log.size(), 0, "blank world logs nothing")
	t.eq(b.stats.age_history.size(), 1, "blank world: one history entry")
	if b.stats.age_history.size() == 1:
		t.eq(b.stats.age_history[0].how, "landing", "blank entry how")
		t.eq(b.stats.age_history[0].age, "landing", "blank entry age")
		t.eq(b.stats.age_history[0].text, _ad().landing.log_start, "blank entry text")
		t.eq(int(b.stats.age_history[0].pop), 0, "blank entry pop 0")
	t.eq(b.stats.age, "landing", "blank stats.age")
	t.eq(_age(b), "landing", "blank world.ages.age")
	t.eq(int(b.ages.last_change_sol), 0, "last_change_sol 0 at creation")
	t.check(b.ages_enabled, "ages_enabled defaults to true")
	_end(t)


func test_t16_staged_settle_fall_back_settle_again(t) -> void:
	if not _api(t):
		return
	var w = _good()
	var last := _scenario(w, 0, "ice")
	t.eq(_age(w), "settlement", "ended settled again")
	t.eq(last, 100, "settled again at boundary 100")
	var lines := _log_of(w, "age_began")
	t.eq(lines.size(), 3, "three age_began lines")
	var hows: Array = []
	for e in lines:
		hows.append(e.how)
	t.eq(hows, ["settled", "fell_back", "settled_again"], "hows in order")
	if lines.size() == 3:
		t.eq([int(lines[0].sol), int(lines[1].sol), int(lines[2].sol)], [44, 64, 100], "at sols 44, 64, 100")
		t.eq(lines[1].cause, "ice", "fell back for ice")
		t.eq(lines[0].get("cause"), null, "no cause on the settle")
		t.eq(lines[2].get("cause"), null, "no cause on the settle again")
		t.eq(lines[0].age, "settlement", "age 1")
		t.eq(lines[1].age, "landing", "age 2")
		t.eq(lines[2].age, "settlement", "age 3")
		t.eq(lines[0].text, _line(w, "settled", "", lines[0].t), "settled text")
		t.eq(lines[1].text, _line(w, "fell_back", "ice", lines[1].t), "fell_back text: base, ice sentence, season")
		t.eq(lines[2].text, _line(w, "settled_again", "", lines[2].t), "settled_again text")
		t.eq(lines[1].text, "%s %s %s" % [_ad().landing.log_fall_back, _ad().cause_lines.ice, _season_phrase(w, lines[1].t)], "joined by single spaces")
	var h: Array = w.stats.age_history
	t.eq(h.size(), 4, "history: Landing plus three changes")
	t.eq(int(w.stats.age_changes), 3, "age_changes 3")
	t.eq(h.size(), int(w.stats.age_changes) + 1, "len(age_history) == age_changes + 1")
	var seq: Array = []
	for e in h:
		seq.append(e.how)
		t.check(str(e.get("text", "")) != "", "history entry %s has text" % e.how)
	t.eq(seq, ["landing", "settled", "fell_back", "settled_again"], "history hows")
	if h.size() == 4 and lines.size() == 3:
		for i in 3:
			t.eq(h[i + 1].text, lines[i].text, "history text %d equals the log text" % i)
		t.eq(h[2].cause, "ice", "history cause on the fall-back")
		t.eq(int(h[2].pop), 12, "history pop")
		t.eq(int(h[3].family_mars_born), 6, "history family_mars_born")
	t.eq(int(w.stats.first_settlement_sol), 44, "first_settlement_sol stays at the first value")
	var sia: Dictionary = w.stats.sols_in_age
	t.eq(int(sia.landing) + int(sia.settlement), last, "sols_in_age sums to the boundaries seen")
	# landing credited at boundaries 1..44 and 65..100 (the age in force during the sol that ended): 44 + 36
	t.eq(int(sia.landing), 44 + 36, "landing: boundaries 1..44 and 65..100")
	t.eq(int(sia.settlement), 20, "settlement: boundaries 45..64")
	_end(t)


func test_t16_all_cause_and_season_lines(t) -> void:
	if not _api(t):
		return
	var ad := _ad()
	var banned := ["landing", "regress", "fail"]
	var combos := 0
	for s_idx in 4:
		var probe = _good()
		var n0: int = _season_start(probe, s_idx)
		t.check(n0 >= 0, "a 130-sol stretch in season %d exists" % s_idx)
		if n0 < 0:
			continue
		n0 = maxi(n0, 4)
		for cause in GROUPS:
			var w = _good()
			_scenario(w, n0, cause)
			combos += 1
			var lines := _log_of(w, "age_began")
			var ctx := "%s / %s" % [cause, w.clock.seasons[s_idx]]
			t.eq(lines.size(), 3, "%s: three lines" % ctx)
			if lines.size() != 3:
				continue
			t.eq([lines[0].how, lines[1].how, lines[2].how], ["settled", "fell_back", "settled_again"], "%s: hows" % ctx)
			t.eq(lines[1].cause, cause, "%s: cause recorded" % ctx)
			for i in 3:
				var how: String = lines[i].how
				var cs: String = cause if how == "fell_back" else ""
				var want := _line(w, how, cs, lines[i].t)
				t.eq(lines[i].text, want, "%s: %s text" % [ctx, how])
				t.eq(w.clock.seasons[s_idx], w.clock.season(lines[i].t), "%s: %s falls in the intended season" % [ctx, how])
				var txt: String = lines[i].text
				var digits := RegEx.create_from_string("[0-9%]")
				t.check(digits.search(txt) == null, "%s: %s has no digit or percent: %s" % [ctx, how, txt])
				var low := txt.to_lower()
				for word in banned:
					t.check(not low.contains(word), "%s: %s does not contain '%s'" % [ctx, how, word])
				t.check(not low.contains("founders"), "%s: %s does not say founders" % [ctx, how])
			t.eq(int(w.stats.age_history.size()), int(w.stats.age_changes) + 1, "%s: history length" % ctx)
	t.eq(combos, 24, "24 combinations ran")
	# The base texts themselves are clean, and the cause sentences differ.
	var seen := {}
	for g in GROUPS:
		t.check(not seen.has(ad.cause_lines[g]), "cause sentence for %s is its own" % g)
		seen[ad.cause_lines[g]] = true
	t.check(not str(ad.landing.log_fall_back).to_lower().contains("fail"), "fall-back base is gentle")
	_end(t)


# ---------------------------------------------------------------- 17. purity

func _run_sols(w, sols: int) -> void:
	while w.sol() < sols:
		w.step()


func test_t17_ages_off_and_on_are_the_same_world(t) -> void:
	if not _api(t):
		return
	var on = SimWorld.new(42)
	var off = SimWorld.new(42)
	off.ages_enabled = false
	var on2 = SimWorld.new(42)
	_run_sols(on, 10)
	_run_sols(off, 10)
	_run_sols(on2, 10)
	t.eq(on.step_index, off.step_index, "same step count")
	t.eq(_old_stats(on), _old_stats(off), "old stats keys equal, ages on and off")
	t.eq(_beings_state(on), _beings_state(off), "beings (id, building, state, energy) equal")
	t.eq([on.colony.oxygen, on.colony.food, on.colony.ice, on.colony.regolith],
			[off.colony.oxygen, off.colony.food, off.colony.ice, off.colony.regolith], "stocks equal")
	t.eq(_draws(on, 1000), _draws(off, 1000), "the next 1000 rng draws are equal, ages on and off")
	# The ages-on world really sampled; the ages-off world did not.
	t.eq(int(on.stats.sols_in_age.landing), 10, "ages on: 10 boundaries credited")
	t.eq(on.ages.window.size(), 6, "ages on: samples at 5..10")
	t.eq(int(off.stats.sols_in_age.landing), 0, "ages off: nothing credited")
	t.eq(off.ages.window.size(), 0, "ages off: no sample")
	t.eq(int(off.stats.age_changes), 0, "ages off: no change")
	t.eq(_log_of(off, "age_began").size(), 1, "ages off: only the creation line")
	# Two same-seed ages-on worlds are identical, history included.
	t.eq(on.stats, on2.stats, "two ages-on worlds: stats equal (age_history included)")
	t.eq(on.stats.age_history, on2.stats.age_history, "age_history equal")
	t.eq(_beings_state(on), _beings_state(on2), "beings equal")
	t.eq(on.log, on2.log, "log equal")
	# decide / dominant_cause leave their arguments alone (they are pure).
	var A = load("res://sim/ages.gd")
	var win := _win("o".repeat(20) + "x".repeat(20))
	var before := str(win)
	A.dominant_cause(win)
	A.decide(win, "landing", 30, 5, 2)
	t.eq(str(win), before, "pure functions do not change the window")
	_end(t)


func _plain_boundaries(w, from_n: int, to_n: int) -> void:
	for n in range(from_n, to_n + 1):
		_boundary(w, n)


func test_t17_on_sol_changes_nothing_but_ages(t) -> void:
	if not _api(t):
		return
	var a = _good(12, 6, 7)
	var b = _good(12, 6, 7)
	a.stats.shorts_this_sol = 2
	var before := _snapshot(a)
	var stats_before := _old_stats(a)
	_plain_boundaries(a, 1, 50)
	t.eq(_old_stats(a), stats_before, "no old stats key is touched by on_sol (shorts_this_sol included)")
	t.eq(_age(a), "settlement", "the staged world did change age (so on_sol did real work)")
	var after := _snapshot(a)
	before.t = after.t  # t moves with the boundaries; the world state otherwise stays
	t.eq(after, before, "stocks, buildings and beings untouched by on_sol")
	t.eq(_draws(a, 100), _draws(b, 100), "the next 100 draws equal those of an untouched copy")
	# A short and a death in the window: still no write to the colony.
	var c = _good(12, 6, 8)
	c.stats.shorts += 2
	c.stats.deaths_list.append({"t": 0.0, "sol": 0, "clock_sol": 1, "being_id": 77, "name": "Z", "cause": "air"})
	var snap_c := _snapshot(c)
	_plain_boundaries(c, 1, 10)
	var after_c := _snapshot(c)
	snap_c.t = after_c.t
	t.eq(after_c, snap_c, "shorts and deaths are read, never written")
	t.eq(c.stats.shorts, 2, "stats.shorts untouched")
	t.eq(c.stats.deaths_list.size(), 1, "deaths_list untouched")
	_end(t)


func _birth_world(seed_in: int, beings_n: int) -> Variant:
	var w = SimWorld.new(seed_in, {"blank": true})
	w.add_building("reactor", 0, 60)
	w.add_building("green_room", 20, 60)
	w.add_building("workshop", 0, 120)
	var h = w.buildings.add("habitat", 100, 0, 1.0, 12, 9)
	for i in beings_n:
		var b = w.add_being(h.id, "social")
		b.persona.traits.sociability = 0.45
		b.persona.traits.care = 0.45
		b.wait_h = 1e9
	return w


func _force_birth_check(w) -> void:
	w.colony.birth_timer_h = float(SimData.colony().birth.check_interval_h) - w.fixed_step
	for b in w.beings:
		if b.state == "idle":
			b.wait_h = 1e9


func test_t17_newborn_records_parent_and_habitat(t) -> void:
	if not _api(t):
		return
	_edit(SimData.colony().birth, "base_chance", 2.0)
	var parents_seen := {}
	for seed_in in range(1, 25):
		var w = _birth_world(seed_in, 3)
		var hab: int = _habs(w)[0]
		var ids: Array = []
		for b in w.beings:
			ids.append(b.id)
		_force_birth_check(w)
		# Replay the draws of the birth check from the rng state: chance, pick(here), name, energy, wait_h.
		var ref := SimRng.new(0)
		ref._rng.state = w.rng._rng.state
		var here: Array = w.beings.duplicate()
		ref.chance(w.colony.birth_chance(here))
		var picked = ref.pick(here)
		var picked_id: int = picked.id
		Being.make_name(ref)
		ref.randf_range(70.0, 100.0)
		ref.randf_range(0.0, 2.0)
		var tail := ref.randf()
		w.step()
		t.eq(w.beings.size(), 4, "seed %d: a birth happened" % seed_in)
		if w.beings.size() != 4:
			continue
		var nb = w.beings.back()
		t.check(not nb.earth_born, "seed %d: newborn is Mars-born" % seed_in)
		t.check(nb.parent_id in ids, "seed %d: parent %d was in the habitat %s" % [seed_in, nb.parent_id, str(ids)])
		t.eq(nb.parent_id, picked_id, "seed %d: parent is the being rng.pick(here) returned" % seed_in)
		t.eq(nb.birth_building_id, hab, "seed %d: birth_building_id is the habitat" % seed_in)
		t.eq(w.rng.randf(), tail, "seed %d: the draws after the birth are the old order (no extra draw)" % seed_in)
		parents_seen[nb.parent_id % 3] = true
	t.check(parents_seen.size() >= 2, "different parents are recorded across seeds (%d)" % parents_seen.size())
	# Founders and test-seam beings have parent_id 0.
	var f = SimWorld.new(42)
	for b in f.beings:
		t.eq(b.parent_id, 0, "founder %d: parent_id 0" % b.id)
		t.check(b.earth_born, "founder is Earth-born")
	var bw = _birth_world(3, 2)
	for b in bw.beings:
		t.eq(b.parent_id, 0, "add_being: parent_id 0")
	_restore()
	_end(t)


func test_t17_empty_here_guard_makes_no_extra_draw(t) -> void:
	if not _api(t):
		return
	_edit(SimData.colony().birth, "base_chance", 2.0)
	_edit(SimData.colony().birth, "min_beings_small_colony", 0)
	var w = _birth_world(5, 0)
	var hab: int = _habs(w)[0]
	t.eq(w.beings.size(), 0, "no beings: `here` is empty")
	_force_birth_check(w)
	var ref := SimRng.new(0)
	ref._rng.state = w.rng._rng.state
	ref.chance(w.colony.birth_chance([]))
	t.eq(ref.pick([]), null, "SimRng.pick on an empty array returns null")
	Being.make_name(ref)
	ref.randf_range(70.0, 100.0)
	ref.randf_range(0.0, 2.0)
	var tail := ref.randf()
	w.step()
	t.eq(w.beings.size(), 1, "a newborn arrived in the empty habitat")
	if w.beings.size() == 1:
		t.eq(w.beings[0].parent_id, 0, "empty `here`: parent_id 0 (the guard)")
		t.eq(w.beings[0].birth_building_id, hab, "birth_building_id still the habitat")
		t.eq(w.rng.randf(), tail, "and no extra draw")
	_restore()
	_end(t)


# ---------------------------------------------------------------- 18. key-path parity

func _leaves(node: Variant, path: String, out: Array) -> void:
	if node is Dictionary and not (node as Dictionary).is_empty():
		for k in node:
			_leaves(node[k], path + "." + str(k), out)
	else:
		out.append(path)


func _spec_keys() -> Array:
	var spec := FileAccess.get_file_as_string("res://docs/specs/ages.md")
	var i0 := spec.find("```keys:")
	if i0 < 0:
		return []
	var i1 := spec.find("```", i0 + 8)
	var body := spec.substr(i0 + 8, i1 - i0 - 8)
	var out: Array = []
	for l in body.split("\n"):
		var s := l.strip_edges()
		if s != "":
			out.append(s)
	return out


func _all_keys(node: Variant, out: Array) -> void:
	if node is Dictionary:
		for k in node:
			out.append(str(k))
			_all_keys(node[k], out)


func test_t18_key_path_parity(t) -> void:
	_begin(t)
	var keys := _spec_keys()
	t.check(keys.size() >= 30, "the spec key list parses (%d keys)" % keys.size())
	var spec_ages: Array = []
	var spec_sim: Array = []
	for k in keys:
		if k.begins_with("ages."):
			spec_ages.append(k)
		elif k.begins_with("sim."):
			spec_sim.append(k)
		else:
			t.check(false, "unexpected key family in the spec list: %s" % k)
	var leaves: Array = []
	_leaves(_ad(), "ages", leaves)
	for k in spec_ages:
		t.check(k in leaves, "spec key %s exists in data/ages.json" % k)
	for k in leaves:
		t.check(k in spec_ages, "data/ages.json leaf %s is listed in the spec" % k)
	t.eq(leaves.size(), spec_ages.size(), "ages.json and the spec list have the same number of leaves")
	var sim_leaves: Array = []
	_leaves(SimData.sim(), "sim", sim_leaves)
	for k in spec_sim:
		t.check(k in sim_leaves, "spec key %s exists in data/sim.json" % k)
	# Not data: no later age appears in ages.json.
	var every: Array = []
	_all_keys(_ad(), every)
	for k in every:
		var kl: String = k.to_lower()
		t.check(not (kl.contains("council") or kl.contains("dome") or kl.contains("city")), "ages.json key '%s' is not a later age" % k)
	t.eq(int(_ad().season_phrases.size()), int(SimData.calendar().seasons.size()), "season_phrases count equals the calendar seasons")
	for p in _ad().season_phrases:
		t.check(str(p) != "", "season phrase is not empty")
	# The accessor and the balance hash.
	var sd = load("res://sim/sim_data.gd")
	var has := _has_static(sd, "ages")
	t.check(has, "SimData.ages() exists")
	if has:
		t.eq(sd.call("ages").hash(), _ad().hash(), "SimData.ages() returns data/ages.json")
		t.check(sd.call("ages") is Dictionary and not sd.call("ages").is_empty(), "and it is not empty")
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var h0: String = lib.data_hash()
	_edit(_ad(), "min_dwell_sols", 21)
	var h1: String = lib.data_hash()
	_restore()
	t.check(h0 != h1, "balance data_hash covers data/ages.json")
	t.eq(lib.data_hash(), h0, "and returns to the old value when the data is restored")
	_end(t)



# ---------------------------------------------------------------- hash proof helper (spec 12)

func test_proof_helper_strips_the_age_column_and_hashes_the_body(t) -> void:
	_begin(t)
	var P: GDScript = load("res://tests/age_hash_proof.gd")
	var old_lines := ["# header one", "# header two",
			"sol  pop minO2", "  30    7    94.0", "  60    9    80.5", "", "targets for seed 1 (60 sols):", "  T1 PASS x"]
	var new_lines := ["# header one (data_hash differs)", "# header two",
			"sol  pop minO2 age", "  30    7    94.0 L", "  60    9    80.5 S", "", "targets for seed 1 (60 sols):", "  T1 PASS x", "  T10 PASS"]
	var old_body: Array = P.body_of(old_lines)
	var new_body: Array = P.body_of(new_lines)
	t.eq(old_body.size(), 3, "body: header row plus two rows, no # lines, nothing after the blank")
	t.check(not P.has_age_column(old_body), "no age column in the old table")
	t.check(P.has_age_column(new_body), "age column found in the new table")
	t.eq(P.strip_age_column(new_body), old_body, "stripping reproduces the old body byte for byte")
	t.eq(P.strip_age_column(old_body), old_body, "stripping a table without the column is a no-op")
	t.eq(P.proof_hash(new_lines), P.proof_hash(old_lines), "same hash with the column removed")
	t.eq(P.proof_hash(old_lines), "\n".join(PackedStringArray(old_body)).sha256_text(), "the hash is sha256_text of the joined body")
	var changed := new_lines.duplicate()
	changed[3] = "  30    7    94.1 L"
	t.check(P.proof_hash(changed) != P.proof_hash(old_lines), "a changed value changes the hash")
	t.eq(P.EXPECTED.size(), 5, "five Task 1 hashes recorded")
	for s in [42, 7, 99, 1234, 2026]:
		t.check(P.EXPECTED.has(s) and str(P.EXPECTED[s]).length() == 16, "expected prefix for seed %d" % s)
	_end(t)


class FakeClock extends RefCounted:
	var v := 0
	var step := 3

	func read() -> int:
		var r := v
		v += step
		return r


# ---------------------------------------------------------------- 20. advance budget (sim half)

func _budget_world(budget: float, clock: Callable = Callable()) -> Variant:
	_edit(SimData.sim(), "advance_budget_ms", budget)
	var w = _good()
	if clock.is_valid():
		w.now_ms = clock
	return w


func test_t20_budget_zero_takes_one_step(t) -> void:
	var w0 = SimWorld.new(1, {"blank": true})
	var has := "advance_dropped_h" in w0 and "now_ms" in w0
	t.check("advance_dropped_h" in w0, "missing API: SimWorld.advance_dropped_h")
	t.check("now_ms" in w0, "missing API: SimWorld.now_ms (injected millisecond clock, Callable)")
	if not has:
		return
	_begin(t)
	t.eq(float(SimData.sim().advance_budget_ms), 8.0, "data: advance_budget_ms 8.0")
	var w = _budget_world(0.0)
	t.eq(w.advance_dropped_h, 0.0, "advance_dropped_h starts at 0")
	var steps: int = w.advance(1.0)
	t.eq(steps, 1, "budget 0: one step per call although 20 are due")
	t.near(w._accum, 0.0, 1e-12, "accumulator zeroed after the stop")
	t.near(float(w.advance_dropped_h), 0.95, 1e-9, "the 19 steps left are dropped (0.95 h)")
	var steps2: int = w.advance(0.03)
	t.eq(steps2, 0, "less than a step: none runs")
	t.near(w._accum, 0.03, 1e-12, "and the remainder is kept, not dropped")
	t.near(float(w.advance_dropped_h), 0.95, 1e-9, "dropped unchanged")
	var steps3: int = w.advance(0.03)
	t.eq(steps3, 1, "the remainder 0.03 + 0.03 makes a step due: one step")
	t.near(float(w.advance_dropped_h), 0.95, 1e-9, "nothing left over, nothing dropped")
	_restore()
	_end(t)


func test_t20_fake_clock_stops_after_three_steps(t) -> void:
	var w0 = SimWorld.new(1, {"blank": true})
	if not ("advance_dropped_h" in w0 and "now_ms" in w0):
		t.check(false, "missing API: SimWorld.advance_dropped_h / now_ms")
		return
	_begin(t)
	var fc := FakeClock.new()
	var w = _budget_world(8.0, fc.read)
	var steps: int = w.advance(10.0)
	t.eq(steps, 3, "3 ms per read, budget 8: entry read 0, then 3, 6, 9 -> stops after 3 steps (overshoot by one)")
	t.eq(w.step_index, 3, "three steps ran")
	t.near(w._accum, 0.0, 1e-12, "accumulator is 0 after the stop")
	t.near(float(w.advance_dropped_h), 10.0 - 3.0 * 0.05, 1e-9, "dropped = the accumulator when zeroed (9.85)")
	# A sub-step remainder pre-loaded is part of what is dropped.
	fc.v = 0
	w._accum = 0.02
	var before: float = w.advance_dropped_h
	var steps2: int = w.advance(1.0)
	t.eq(steps2, 3, "again 3 steps")
	t.near(float(w.advance_dropped_h) - before, 1.02 - 3.0 * 0.05, 1e-9, "dropped grew by 0.87 (includes the 0.02 remainder)")
	t.near(w._accum, 0.0, 1e-12, "accumulator 0")
	# The stop is at elapsed >= budget, not >: 4 ms per read gives elapsed 4, 8 and the loop stops at 8.
	fc.v = 0
	fc.step = 4
	w._accum = 0.0
	var steps_eq: int = w.advance(10.0)
	t.eq(steps_eq, 2, "4 ms per read, budget 8: elapsed 8 >= 8 stops after 2 steps")
	fc.step = 3
	# A call that finishes inside the budget drops nothing.
	fc.v = 0
	before = w.advance_dropped_h
	var steps3: int = w.advance(0.1)
	t.eq(steps3, 2, "two steps due, two run")
	t.near(float(w.advance_dropped_h), before, 1e-12, "nothing dropped when every due step ran")
	# The counter is not in stats or the log.
	for k in w.stats.keys():
		t.check(not str(k).contains("dropped"), "stats has no dropped-hours key (%s)" % str(k))
	for e in w.log:
		t.check(not str(e.text).contains("dropped"), "log has no dropped-hours line")
	_restore()
	_end(t)


func test_t20_cap_and_unbudgeted_equivalence(t) -> void:
	var w0 = SimWorld.new(1, {"blank": true})
	if not ("advance_dropped_h" in w0 and "now_ms" in w0):
		t.check(false, "missing API: SimWorld.advance_dropped_h / now_ms")
		return
	_begin(t)
	# The hard cap is never exceeded, even when the clock never reaches the budget.
	var still := FakeClock.new()
	still.step = 0
	var w = _budget_world(8.0, still.read)
	w.max_steps_per_advance = 4
	var steps: int = w.advance(10.0)
	t.eq(steps, 4, "cap 4 with a frozen clock: exactly 4 steps")
	t.near(float(w.advance_dropped_h), 10.0 - 4.0 * 0.05, 1e-9, "the rest is dropped at the cap")
	# A clock that never reaches the budget: same steps and same state as plain stepping.
	var a = _budget_world(8.0, still.read)
	var b = _good()
	var n: int = a.advance(5.0)
	for i in n:
		b.step()
	t.eq(n, 100, "5 hours = 100 steps")
	t.eq(a.step_index, b.step_index, "same step count")
	t.near(a.t, b.t, 1e-9, "same t")
	t.eq(a.stats, b.stats, "same stats")
	t.eq(_beings_state(a), _beings_state(b), "same beings")
	t.eq(_draws(a, 200), _draws(b, 200), "same rng stream")
	t.near(float(a.advance_dropped_h), 0.0, 1e-9, "nothing dropped")
	# The default clock (engine ticks) with the default budget still takes steps.
	_restore()
	var d = _good()
	var steps_d: int = d.advance(0.2)
	t.check(steps_d >= 1 and steps_d <= 4, "default clock: at least one step, at most the four due (%d)" % steps_d)
	_end(t)

