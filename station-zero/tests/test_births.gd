extends RefCounted
## Task 1, step 9: births. Spec: docs/specs/life-support-power.md sections 3 (comparators, randomness), 4 (Colony
## birth fields), 5 (phase 7), 10.1 (birth check, cooldown, invariant counters), 16 (stats, log kinds),
## "Implementation notes", and the "Tests (tests/test_births.gd)" list. Plan step 9 and the owner decision A4
## (prototype formula plus a per-habitat cooldown of 1 sol). Founders and the role retry are tested in
## tests/test_beings.gd (step 6) and are not repeated here.
##
## Existing API used (steps 1..8): SimWorld.new(seed, {"blank": true}), add_building / add_being / set_offline,
##  step(), t, rng (SimRng, whose private _rng.state is read to count draws), sol(), clock, sky (mars_chart),
##  persona (persona_from), beings, stats, log, colony.* (pop, o2_net, food_net, o2_cap, food_cap, oxygen, food,
##  ice, last_birth_t, birth_timer_h), buildings (add, add_attached, list, get_building), Being fields and
##  Being.make_name / is_inside(), SimData.colony() (tunables are edited in the cache and restored at the end of
##  each test, which also proves the gates read data/colony.json).
##
## API ASSUMED beyond the existing one (extended the simplest way; every name is the spec's):
##  - Phase 7 lives inside SimWorld.step(); there is no public birth call.  Tests drive it by writing
##    colony.birth_timer_h (the spec section 4 name, a float accumulator in hours) to birth.check_interval_h - dt, so
##    the NEXT step is a check (spec: fires when acc >= h - STEP_EPS, then acc = 0).  One 80-step run per check is
##    used only where the 4 h grid itself is the subject (test_timer_*, test_cooldown_natural_steps).
##  - colony.last_birth_t: Dictionary habitat id (int) -> t of its last birth, absent = never.  Tests write it
##    directly (cooldown boundaries) and read it after a birth (== world t at the birth step).
##  - stats (top-level keys, as in steps 4..6, not stats.window): births (already exists), first_birth_sol
##    (null until the first birth, then the elapsed sol, w.sol(), of that birth; never changed afterwards),
##    births_at_capacity and cooldown_violations (exist, stay 0).  The two invariant counters cannot be driven above
##    0 from outside (the gates make them unreachable, spec 10.1), so they are asserted 0 after births made at the
##    edges (pop = cap - 1, elapsed just past the cooldown).
##  - A birth appends a log entry {kind: "born", t, sol, text, being_id, building_id} (the text is not asserted).
##  - The newborn is appended to world.beings (last element, id = highest id + 1) with: building_id = H,
##    state "idle" (is_inside()), earth_born false, born_t = world t at the birth step, name from Being.make_name,
##    persona == persona.persona_from(sky.mars_chart(t, clock.lon_of_tile(tx + tw / 2.0))) (t = world t after the
##    step's t += dt), role = persona.role, energy U(70,100), wait_h U(0,2) (read right after the step: phase 6
##    runs before phase 7, so nothing has touched them).  RNG order inside a check: chance(p) (only when every
##    gate holds), then pick(here), then make_name, energy, wait_h (the order the spec writes).
##  - "here" = beings of H whose state is not transit/eva/work/mining (Being.is_inside()); sleepers count.
##
## Test method (all numbers are measured by the run, see the printed lines):
##  - Worlds are blank: reactor, green room, workshop, then habitats of size 12 x 9 (or the sizes given), beings
##    social (so no builder is ever ready) and pinned (wait_h = 1e9 each step) so nobody walks, sleeps or draws.
##    Draw: reactor 0 + green room 4 + workshop 4 + 3 per online habitat = 14 with two habitats, exactly the supply,
##    so nothing shorts, and an offline habitat cannot return (14 + 3 > 13.3).
##  - Boundary values: stocks are pre-set so that they LAND on the wanted value after phases 2 and 5 of the check
##    step (the helper subtracts the step's own change); just above/below uses +-1e-6.  Exact equality (strict >) is
##    tested by moving the data threshold onto the value: stocks clamped at their cap (equal to the cap, exactly),
##    ice with ice_per_being = 0, nets by writing the net itself into the gate.
##  - Cooldown boundaries use direct writes of colony.last_birth_t to (t_check - elapsed), elapsed = 493 steps
##    (24.65 h, blocked), 24.6597 -+ 1e-6, 494 steps (24.70 h, allowed).  Float noise at 1e-9 (STEP_EPS) is not
##    probed: the world clock is ~1e5 h, one ulp is ~1.5e-11, too close to the slack to bracket honestly.
##  - Statistics use fixed seeds, so every run is repeatable.  Tolerances are 3 sigma or the spec's +-0.03.

const DT := 0.05
const SOL_H := 24.6597
const CHECK_H := 4.0
const CHECK_STEPS := 80
const COOLDOWN_STEPS := 494  # first step count with elapsed > 1 sol + STEP_EPS (493 x 0.05 = 24.65 < 24.6597)

var _undo: Array = []
var _pre_state := 0
var _draws := 0


# ---------------------------------------------------------------- helpers

## Blank world: `reactors` reactors, green room, workshop, then `online` online habitats and `offline` dark ones.
## Ids: reactors 1..R, green room R+1, workshop R+2, habitats R+3.. in creation order.
func _world(seed_in: int, online: int = 1, offline: int = 0, reactors: int = 1) -> SimWorld:
	var w := SimWorld.new(seed_in, {"blank": true})
	for r in reactors:
		w.add_building("reactor", 40 * r, 60)
	w.add_building("green_room", 20, 60)
	w.add_building("workshop", 0, 60)
	for i in online + offline:
		var b := w.buildings.add("habitat", 100 + 40 * i, 0, 1.0, 12, 9)
		if i >= online:
			w.set_offline(b.id, true)
	return w


func _habs(w: SimWorld) -> Array:
	var out: Array = []
	for b in w.buildings.list:
		if b.kind == "habitat":
			out.append(b.id)
	return out


func _ws(w: SimWorld) -> int:
	for b in w.buildings.list:
		if b.kind == "workshop":
			return b.id
	return 0


## `n` social beings in building `bid`, sociability = care = v, so a lone group has warmth 2 v.
func _put(w: SimWorld, bid: int, n: int, v: float = 0.45) -> Array:
	var out: Array = []
	for i in n:
		var b := w.add_being(bid, "social")
		b.persona.traits.sociability = v
		b.persona.traits.care = v
		out.append(b)
	return out


func _pin(w: SimWorld) -> void:
	for b in w.beings:
		if b.state == "idle":
			b.wait_h = 1e9


## Edits a data value in the SimData cache; _restore() puts everything back.
func _edit(dict: Dictionary, key: String, value: Variant) -> void:
	_undo.append([dict, key, dict[key]])
	dict[key] = value


func _restore() -> void:
	while not _undo.is_empty():
		var u: Array = _undo.pop_back()
		u[0][u[1]] = u[2]


func _bc() -> Dictionary:
	return SimData.colony().birth


## Runs exactly one birth check: the next step is a check, and the stocks land on `want` ({oxygen, food, ice}, default
## 100, 100, 60) after phases 2 and 5.  Returns the number of births made.
func _check(w: SimWorld, want: Dictionary = {}) -> int:
	_pin(w)
	var cc: Dictionary = SimData.colony()
	w.colony.birth_timer_h = float(_bc().check_interval_h) - DT
	w.colony.oxygen = float(want.get("oxygen", 100.0)) - w.colony.o2_net() * DT
	w.colony.food = float(want.get("food", 100.0)) - w.colony.food_net() * DT
	w.colony.ice = float(want.get("ice", 60.0)) + w.colony.pop() * float(cc.consumption.ice_per_being) * DT
	var before := int(w.stats.births)
	_pre_state = w.rng._rng.state
	w.step()
	return int(w.stats.births) - before


## Removes everything after the first `keep` beings and forgets all births.
func _reset(w: SimWorld, keep: int) -> void:
	while w.beings.size() > keep:
		w.beings.pop_back()
	w.colony.last_birth_t.clear()


## `n` single-step checks, each from a clean slate; returns how many checks made at least one birth.
## `_draws` counts the checks in which the world rng advanced.
func _hits(w: SimWorld, n: int, want: Dictionary = {}, prep: Callable = Callable()) -> int:
	var keep := w.beings.size()
	var hits := 0
	_draws = 0
	for i in n:
		_reset(w, keep)
		if prep.is_valid():
			prep.call()
		if _check(w, want) > 0:
			hits += 1
		if w.rng._rng.state != _pre_state:
			_draws += 1
	_reset(w, keep)
	return hits


## The standard open world: one online habitat with two warm beings (warmth 0.9, p = 0.206 per check).
func _open(seed_in: int) -> SimWorld:
	var w := _world(seed_in)
	_put(w, _habs(w)[0], 2)
	return w


func _p(warmth: float) -> float:
	return float(_bc().base_chance) + float(_bc().warmth_coef) * warmth


func _born_log(w: SimWorld) -> Array:
	var out: Array = []
	for e in w.log:
		if e.kind == "born":
			out.append(e)
	return out


# ---------------------------------------------------------------- data

func test_birth_data_matches_spec(t) -> void:
	var b: Dictionary = _bc()
	t.eq(b.check_interval_h, 4, "check interval")
	t.eq(b.base_chance, 0.08, "base chance")
	t.eq(b.warmth_coef, 0.14, "warmth coefficient")
	t.eq(b.min_beings, 2, "min beings")
	t.eq(b.min_beings_small_colony, 1, "min beings small colony")
	t.eq(b.small_colony_below, 4, "small colony below")
	t.eq(b.gate_ice_above, 5, "ice gate")
	t.eq(b.gate_food_above, 15, "food gate")
	t.eq(b.gate_oxygen_above, 20, "oxygen gate")
	t.eq(b.gate_o2_net_above, 0.1, "o2 net gate")
	t.eq(b.gate_food_net_above, 0.05, "food net gate")
	t.eq(b.habitat_capacity, 5, "habitat capacity")
	t.eq(b.capacity_bonus, 2, "capacity bonus")
	t.eq(b.cooldown_sols, 1, "cooldown sols")


# ---------------------------------------------------------------- the 4 h timer (phase 7)

## Checks sit on a 4 h grid: acc >= 4 - STEP_EPS fires on the 80th step, never the 79th or the 81st.
func test_timer_fires_on_the_80th_step(t) -> void:
	var at80 := 0
	var other := 0
	for s in range(1, 101):
		var w := _open(s)
		var first := 0
		for i in range(1, 86):
			_pin(w)
			w.step()
			if i == 79:
				t.near(float(w.colony.birth_timer_h), 3.95, 1e-6, "seed %d: timer after 79 steps" % s)
			if i == 80:
				t.eq(float(w.colony.birth_timer_h), 0.0, "seed %d: timer reset by the check" % s)
			if first == 0 and int(w.stats.births) > 0:
				first = w.step_index
		if first == 80:
			at80 += 1
		elif first != 0:
			other += 1
	print("    first check births: %d of 100 seeds at step 80, %d at another step" % [at80, other])
	t.eq(other, 0, "no birth on any step but the 80th within 85 steps")
	t.between(at80, 8, 40, "births on step 80 (expected about 21 of 100)")


## A failed gate does not hold the timer: the next check is 80 steps later, not on the first step the gate opens.
func test_timer_runs_through_a_failed_check(t) -> void:
	var at160 := 0
	var other := 0
	for s in range(1, 61):
		var w := _open(s)
		var first := 0
		for i in range(1, 166):
			_pin(w)
			if i <= 80:
				w.colony.ice = 0.0  # step 80 sees ice 0: blocked
			elif i == 81:
				w.colony.ice = 60.0
			w.step()
			if first == 0 and int(w.stats.births) > 0:
				first = w.step_index
		if first == 160:
			at160 += 1
		elif first != 0:
			other += 1
	print("    after a blocked check at step 80: %d births at step 160, %d at another step (60 seeds)" % [at160, other])
	t.eq(other, 0, "the gate opening at step 81 does not birth before step 160")
	t.check(at160 >= 5, "births at step 160 (%d)" % at160)


# ---------------------------------------------------------------- gates

func test_gate_matrix_blocks_every_broken_gate(t) -> void:
	var n := 500
	var cases: Array = []
	# 1. The habitat is offline (a second online habitat keeps capacity out of it).
	var w1 := _world(1, 1, 1)
	_put(w1, _habs(w1)[1], 2)
	cases.append(["habitat offline", w1, {}, Callable()])
	# 2. The habitat is an unfinished site.
	var w2 := _world(2)
	var site := w2.buildings.add("habitat", 300, 0, 0.5, 12, 9)
	_put(w2, site.id, 2)
	cases.append(["habitat unfinished", w2, {}, Callable()])
	# 3. |here| < need: pop 4 needs 2, one is in H.
	var w3 := _world(3)
	_put(w3, _habs(w3)[0], 1)
	_put(w3, _ws(w3), 3)
	cases.append(["|here| 1 at pop 4", w3, {}, Callable()])
	# 4. Nobody in H.
	var w4 := _world(4)
	_put(w4, _ws(w4), 2)
	cases.append(["nobody in H", w4, {}, Callable()])
	# 5..7. Stocks one micro-unit under their gates.
	cases.append(["ice 4.999999", _open(5), {"ice": 4.999999}, Callable()])
	cases.append(["food 14.999999", _open(6), {"food": 14.999999}, Callable()])
	cases.append(["oxygen 19.999999", _open(7), {"oxygen": 19.999999}, Callable()])
	# 8. Capacity: pop 7 with one online habitat.
	var w8 := _open(8)
	_put(w8, _ws(w8), 5)
	cases.append(["pop 7 = cap 7", w8, {}, Callable()])
	# 9. Cooldown: the habitat had a birth a step ago (re-armed before each check).
	var w9 := _open(9)
	cases.append(["cooldown just started", w9, {}, func(): w9.colony.last_birth_t[_habs(w9)[0]] = w9.t])
	# 10. The only beings of H are in the tunnel (state transit), so |here| = 0.
	var w10 := _world(10)
	var h10: int = _habs(w10)[0]
	var child := w10.buildings.add_attached("habitat", h10, "r", 12, 9, 12)
	var movers := _put(w10, h10, 2)
	cases.append(["both beings in transit", w10, {}, func():
		for m in movers:
			m.state = "transit"
			m.corridor_id = child.id
			m.transit_t = 0.0
			m.from_a = true])
	for c in cases:
		var hits := _hits(c[1], n, c[2], c[3])
		t.eq(hits, 0, "%s: no birth in %d checks" % [c[0], n])
		t.eq(_draws, 0, "%s: no rng draw when a gate fails (chance is drawn last)" % c[0])
	# Controls: the same worlds with the gate open birth in many checks.
	var wa := _world(21, 1, 1)
	_put(wa, _habs(wa)[0], 2)
	var wb := _open(22)
	_put(wb, _ws(wb), 2)  # pop 4, two in H
	var wc := _open(23)
	_put(wc, _ws(wc), 4)  # pop 6 < cap 7
	for c in [["online habitat beside a dark one", wa, {}], ["pop 4 with 2 in H", wb, {}],
			["pop 6 below cap 7", wc, {}], ["all stocks just above", _open(24),
			{"ice": 5.000001, "food": 15.000001, "oxygen": 20.000001}]]:
		var hits := _hits(c[1], n, c[2])
		t.between(hits, 60, 160, "control %s: births in %d checks (expected about 103)" % [c[0], n])


## The gates at the shipped numbers: 1e-6 under blocks, 1e-6 over passes (stocks), 0.001 either side for the nets.
func test_gate_boundaries_at_default_values(t) -> void:
	var n := 500
	var stock_pairs := [["ice", 5.0], ["food", 15.0], ["oxygen", 20.0]]
	for p in stock_pairs:
		var below := _hits(_open(31), n, {p[0]: p[1] - 1e-6})
		var above := _hits(_open(31), n, {p[0]: p[1] + 1e-6})
		print("    gate %s %.1f: births in %d checks: %d just below, %d just above" % [p[0], p[1], n, below, above])
		t.eq(below, 0, "%s %s - 1e-6 blocks" % [p[0], str(p[1])])
		t.between(above, 60, 160, "%s %s + 1e-6 passes" % [p[0], str(p[1])])
	# Nets with two beings and one green room: o2_net = prod - 0.1, food_net = prod - 0.07.
	var pc: Dictionary = SimData.colony().production
	for case in [["o2_per_green_room", 0.2, 0.1], ["food_per_green_room", 0.12, 0.05]]:
		_edit(pc, case[0], case[1] - 0.001)
		var below := _hits(_open(32), n)
		_restore()
		_edit(pc, case[0], case[1] + 0.001)
		var above := _hits(_open(32), n)
		_restore()
		print("    net gate %s %.2f: %d just below, %d just above" % [case[0], case[2], below, above])
		t.eq(below, 0, "%s net %.3f blocks" % [case[0], case[2] - 0.001])
		t.between(above, 60, 160, "%s net %.3f passes" % [case[0], case[2] + 0.001])


## Strict inequalities: a stock or net exactly ON the gate blocks.  The gate is moved onto the value.
func test_gate_strictness_exact(t) -> void:
	var n := 300
	var bc: Dictionary = _bc()
	# Ice: with ice_per_being = 0 the stock stays exactly at 5.0.
	_edit(SimData.colony().consumption, "ice_per_being", 0.0)
	t.eq(_hits(_open(41), n, {"ice": 5.0}), 0, "ice exactly 5 blocks (> 5)")
	t.check(_hits(_open(41), n, {"ice": 5.0000001}) > 20, "ice 5.0000001 passes")
	_restore()
	# Food and oxygen: a stock far above its cap is clamped to the cap, so it equals the cap exactly.
	var w := _open(42)
	_edit(bc, "gate_food_above", w.colony.food_cap())
	t.eq(_hits(w, n, {"food": 1e9}), 0, "food exactly on its gate blocks")
	_restore()
	_edit(bc, "gate_food_above", w.colony.food_cap() - 0.001)
	t.check(_hits(w, n, {"food": 1e9}) > 20, "food a hair above its gate passes")
	_restore()
	_edit(bc, "gate_oxygen_above", w.colony.o2_cap())
	t.eq(_hits(w, n, {"oxygen": 1e9}), 0, "oxygen exactly on its gate blocks")
	_restore()
	_edit(bc, "gate_oxygen_above", w.colony.o2_cap() - 0.001)
	t.check(_hits(w, n, {"oxygen": 1e9}) > 20, "oxygen a hair above its gate passes")
	_restore()
	# Nets: the gate is set to the net itself.
	_edit(bc, "gate_o2_net_above", w.colony.o2_net())
	t.eq(_hits(w, n), 0, "o2_net exactly on its gate blocks")
	_restore()
	_edit(bc, "gate_o2_net_above", w.colony.o2_net() - 1e-6)
	t.check(_hits(w, n) > 20, "o2_net 1e-6 above its gate passes")
	_restore()
	_edit(bc, "gate_food_net_above", w.colony.food_net())
	t.eq(_hits(w, n), 0, "food_net exactly on its gate blocks")
	_restore()
	_edit(bc, "gate_food_net_above", w.colony.food_net() - 1e-6)
	t.check(_hits(w, n) > 20, "food_net 1e-6 above its gate passes")
	_restore()
	# The gates are read from data: move the ice gate to 30 and the stock 1e-6 either side of it.
	_edit(bc, "gate_ice_above", 30.0)
	t.eq(_hits(w, n, {"ice": 29.999999}), 0, "ice gate moved to 30: 29.999999 blocks")
	t.check(_hits(w, n, {"ice": 30.000001}) > 20, "ice gate moved to 30: 30.000001 passes")
	_restore()
	t.eq(float(_bc().gate_ice_above), 5.0, "data restored: ice gate")
	t.eq(float(SimData.colony().consumption.ice_per_being), 0.01, "data restored: ice per being")


## need = 1 below 4 beings, 2 from 4: pop 3 with one in H births; pop 4 with one does not; with two it does.
func test_need_depends_on_population(t) -> void:
	var n := 500
	var cases := [["pop 1, alone", 0, 1, true], ["pop 3, one in H", 2, 1, true], ["pop 4, one in H", 3, 1, false],
			["pop 4, two in H", 2, 2, true], ["pop 8 (2 habitats), one in H", 7, 1, false]]
	for c in cases:
		var w := _world(51, 2 if c[0].begins_with("pop 8") else 1)
		_put(w, _habs(w)[0], c[2])
		_put(w, _ws(w), c[1])
		var hits := _hits(w, n)
		if c[3]:
			t.between(hits, 60, 160, "%s: births in %d checks (expected about 103)" % [c[0], n])
		else:
			t.eq(hits, 0, "%s: no births in %d checks" % [c[0], n])
	# Spread out: one in H and two in the workshop is pop 3, still need 1.
	var w3 := _world(52, 1)
	_put(w3, _habs(w3)[0], 1)
	_put(w3, _ws(w3), 2)
	t.check(_hits(w3, n) > 20, "pop 3, one in H, two in the workshop")


# ---------------------------------------------------------------- chance

## Headline: all gates passing, warmth 0.9, p = 0.08 + 0.14 x 0.9 = 0.206.  One check per seed (spec: +-0.03).
func test_birth_rate_headline_over_seeds(t) -> void:
	var n := 2000
	var hits := 0
	for s in range(1, n + 1):
		var w := _open(s)
		if _check(w) > 0:
			hits += 1
	var rate := float(hits) / n
	print("    warmth 0.9: %d births in %d seeds, rate %.4f (expected 0.206)" % [hits, n, rate])
	t.near(rate, 0.206, 0.03, "birth rate per check, warmth 0.9")


## The formula over warmth: p = 0.08 + 0.14 x warmth, warmth = mean over here of (sociability + care).
func test_birth_rate_by_warmth(t) -> void:
	var n := 1200
	var cases: Array = []
	# [label, expected warmth, beings in H (v each), beings elsewhere (v), sleepers in H]
	cases.append(["warmth 0 (cold pair)", 0.0, [0.0, 0.0], [], []])
	cases.append(["warmth 0.9", 0.9, [0.45, 0.45], [], []])
	cases.append(["warmth 1.0 (mean of 2 and 0, not the sum)", 1.0, [1.0, 0.0], [], []])
	cases.append(["warmth 2.0 (hot pair)", 2.0, [1.0, 1.0], [], []])
	cases.append(["a hot being in the workshop is not counted", 0.0, [0.0, 0.0], [1.0], []])
	cases.append(["sleepers in H count", 2.0, [], [], [1.0, 1.0]])
	for c in cases:
		var w := _world(61)
		var h: int = _habs(w)[0]
		for v in c[2]:
			_put(w, h, 1, v)
		for v in c[3]:
			_put(w, _ws(w), 1, v)
		for v in c[4]:
			var s: Being = _put(w, h, 1, v)[0]
			s.state = "sleep"
			s.sleep_started_t = w.t
			s.energy = 0.0
		var p := _p(c[1])
		var hits := _hits(w, n)
		var rate := float(hits) / n
		print("    %s: rate %.4f (expected %.4f)" % [c[0], rate, p])
		t.near(rate, p, 0.04, c[0])


## chance(p) is drawn only when every gate holds; a passing check without a birth consumed exactly that one draw;
## a birth then draws pick(here), name, energy, wait_h in that order and nothing else.
func test_birth_draw_order(t) -> void:
	var births := 0
	var misses := 0
	for s in range(1, 81):
		var w := _world(s)
		var h: int = _habs(w)[0]
		var here := _put(w, h, 2 + s % 3)  # 2, 3 or 4 beings, all in H
		var warmth := 0.0
		for b in here:
			warmth += float(b.persona.traits.sociability) + float(b.persona.traits.care)
		warmth /= here.size()
		var made := _check(w)
		var ref := SimRng.new(0)
		ref._rng.state = _pre_state
		var rolled := ref.chance(_p(warmth))
		t.eq(made > 0, rolled, "seed %d: a birth happens exactly when the first draw is under p" % s)
		if rolled:
			births += 1
			ref.pick(here)
			var name := Being.make_name(ref)
			var es: Array = SimData.beings().energy.start
			var energy := ref.randf_range(float(es[0]), float(es[1]))
			var iw: Array = SimData.beings().initial_wait_h
			var wait := ref.randf_range(float(iw[0]), float(iw[1]))
			var nb: Being = w.beings.back()
			t.eq(nb.name, name, "seed %d: newborn name from the draw after pick(here)" % s)
			t.eq(nb.energy, energy, "seed %d: newborn energy" % s)
			t.eq(nb.wait_h, wait, "seed %d: newborn wait_h" % s)
		else:
			misses += 1
		t.eq(w.rng._rng.state, ref._rng.state, "seed %d: no other rng draw in the check" % s)
	print("    draw order replayed on %d births and %d chance misses" % [births, misses])
	t.check(births >= 8 and misses >= 8, "both outcomes replayed (%d births, %d misses)" % [births, misses])


# ---------------------------------------------------------------- capacity

func test_capacity(t) -> void:
	var n := 500
	# One habitat: cap 7.
	for pop in [6, 7, 8]:
		var w := _open(71)
		_put(w, _ws(w), pop - 2)
		var hits := _hits(w, n)
		print("    1 habitat, pop %d (cap 7): %d births in %d checks" % [pop, hits, n])
		t.eq(w.stats.births_at_capacity, 0, "1 habitat, pop %d: births_at_capacity stays 0 (births at pop 6 are below cap)" % pop)
		if pop == 6:
			t.between(hits, 60, 160, "pop 6 below cap 7 births")
		else:
			t.eq(hits, 0, "pop %d at or over cap 7: no births" % pop)
	# Two habitats online: cap 12.
	for pop in [11, 12]:
		var w := _world(72, 2)
		for h in _habs(w):
			_put(w, h, 2)
		_put(w, _ws(w), pop - 4)
		var hits := _hits(w, n)
		t.eq(w.stats.births_at_capacity, 0, "2 habitats, pop %d: births_at_capacity stays 0" % pop)
		print("    2 habitats, pop %d (cap 12): %d births in %d checks" % [pop, hits, n])
		if pop == 11:
			t.check(hits > 100, "pop 11 below cap 12 births (%d)" % hits)
		else:
			t.eq(hits, 0, "pop 12 = cap 12: no births")
	# Two habitats, one offline: cap 7.
	for pop in [6, 7]:
		var w := _world(73, 1, 1)
		_put(w, _habs(w)[0], 2)
		_put(w, _ws(w), pop - 2)
		var hits := _hits(w, n)
		print("    2 habitats, one offline, pop %d (cap 7): %d births in %d checks" % [pop, hits, n])
		if pop == 6:
			t.between(hits, 60, 160, "pop 6 below cap 7 with one habitat dark births")
		else:
			t.eq(hits, 0, "pop 7 = cap 7 with one habitat dark: no births")
	# An unfinished habitat adds no capacity.
	var wu := _open(74)
	wu.buildings.add("habitat", 300, 0, 0.5, 12, 9)
	_put(wu, _ws(wu), 5)
	t.eq(_hits(wu, n), 0, "pop 7 with one finished and one unfinished habitat: cap stays 7")
	t.eq(wu.stats.births_at_capacity, 0, "births_at_capacity stays 0")
	t.eq(wu.stats.cooldown_violations, 0, "cooldown_violations stays 0")


## Each habitat re-evaluates with the live population: pop 11 allows one birth in a check (cap 12), pop 10 allows two.
func test_capacity_uses_live_population(t) -> void:
	var n := 1000
	var w := _world(75, 2)
	for h in _habs(w):
		_put(w, h, 2)
	_put(w, _ws(w), 6)  # pop 10
	var keep := w.beings.size()
	var both := 0
	var any := 0
	var max_pop := 0
	for i in n:
		_reset(w, keep)
		var made := _check(w)
		max_pop = maxi(max_pop, w.colony.pop())
		if made > 0:
			any += 1
		if made == 2:
			both += 1
		t.check(made <= 2, "never more than 2 births in a check")
	print("    2 habitats, pop 10: %d checks with a birth, %d with two, max pop %d" % [any, both, max_pop])
	t.between(max_pop, 12, 12, "pop never above the cap of 12")
	t.between(both, 5, 90, "two births in one check happen (expected about 4%% of checks)")
	_reset(w, keep)
	var w11 := _world(76, 2)
	for h in _habs(w11):
		_put(w11, h, 2)
	_put(w11, _ws(w11), 7)  # pop 11
	var k11 := w11.beings.size()
	var two := 0
	for i in n:
		_reset(w11, k11)
		if _check(w11) == 2:
			two += 1
	t.eq(two, 0, "pop 11: the second habitat sees pop 12 and cannot birth in the same check")


# ---------------------------------------------------------------- cooldown

## Elapsed since the habitat's last birth must exceed 1 sol (24.6597 h): 493 steps (24.65 h) block, 494 (24.70 h) pass.
func test_cooldown_boundaries(t) -> void:
	var n := 500
	var w := _open(81)
	var h: int = _habs(w)[0]
	var cases := [["absent (never had a birth)", null, true],
			["1 step", DT, false], ["6 h", 6.0, false], ["24 h (checks +4 to +24 are blocked)", 24.0, false],
			["493 steps = 24.65 h", 493 * DT, false],
			["24.6597 - 1e-6", SOL_H - 1e-6, false], ["24.6597 + 1e-6", SOL_H + 1e-6, true],
			["494 steps = 24.70 h", COOLDOWN_STEPS * DT, true], ["28 h (+28 is allowed)", 28.0, true],
			["100 h", 100.0, true]]
	for c in cases:
		var elapsed: Variant = c[1]
		var prep := func():
			if elapsed == null:
				w.colony.last_birth_t.erase(h)
			else:
				w.colony.last_birth_t[h] = (w.t + DT) - float(elapsed)
		var keep := w.beings.size()
		var hits := 0
		for i in n:
			_reset(w, keep)
			prep.call()
			if _check(w) > 0:
				hits += 1
		_reset(w, keep)
		print("    elapsed %s: %d births in %d checks" % [c[0], hits, n])
		if c[2]:
			t.between(hits, 60, 160, "elapsed %s: allowed (expected about 103)" % c[0])
		else:
			t.eq(hits, 0, "elapsed %s: blocked" % c[0])
	t.eq(w.stats.cooldown_violations, 0, "births made right after the cooldown are not violations")
	t.eq(w.stats.births_at_capacity, 0, "births_at_capacity stays 0")


## Real steps on the 4 h grid: gaps between births of one habitat are multiples of 80 steps and at least 560 (28 h);
## +80 .. +480 steps (4 h to 24 h) never birth, +560 can.
func test_cooldown_natural_steps(t) -> void:
	var gap_counts := {}
	var gaps := 0
	var bad := 0
	var births := 0
	var violations := 0
	var at_cap := 0
	for s in range(1, 17):
		var w := _open(s)
		var steps: Array = []
		var seen := 0
		for i in 2400:
			_pin(w)
			w.step()
			if int(w.stats.births) > seen:
				seen = int(w.stats.births)
				steps.append(w.step_index)
		births += seen
		violations += int(w.stats.cooldown_violations)
		at_cap += int(w.stats.births_at_capacity)
		t.check(w.colony.pop() <= 7, "seed %d: pop %d never above cap 7" % [s, w.colony.pop()])
		for k in range(1, steps.size()):
			var gap: int = steps[k] - steps[k - 1]
			gaps += 1
			gap_counts[gap] = int(gap_counts.get(gap, 0)) + 1
			if gap < 560 or gap % CHECK_STEPS != 0:
				bad += 1
	var keys := gap_counts.keys()
	keys.sort()
	var table := ""
	for k in keys:
		table += " %d:%d" % [k, gap_counts[k]]
	print("    16 seeds x 2400 steps: %d births, %d gaps, gap steps:count%s" % [births, gaps, table])
	t.eq(bad, 0, "every gap is a multiple of 80 steps and at least 560")
	t.check(gaps >= 12, "enough gaps to judge (%d)" % gaps)
	t.check(gap_counts.has(560), "the first allowed check, +560 steps (28 h), is used")
	t.eq(violations, 0, "cooldown_violations stays 0")
	t.eq(at_cap, 0, "births_at_capacity stays 0")


## Another habitat is unaffected by the cooldown of its neighbour.
func test_cooldown_is_per_habitat(t) -> void:
	var n := 500
	var w := _world(82, 2)
	var habs := _habs(w)
	for h in habs:
		_put(w, h, 2)
	var keep := w.beings.size()
	for cold in [0, 1]:
		var in_cold := 0
		var in_free := 0
		for i in n:
			_reset(w, keep)
			w.colony.last_birth_t[habs[cold]] = w.t
			var before := w.beings.size()
			_check(w)
			for k in range(before, w.beings.size()):
				if w.beings[k].building_id == habs[cold]:
					in_cold += 1
				else:
					in_free += 1
		print("    habitat %d in cooldown: %d births there, %d in the other" % [habs[cold], in_cold, in_free])
		t.eq(in_cold, 0, "habitat %d is in cooldown: no birth there" % habs[cold])
		t.between(in_free, 60, 160, "the other habitat births freely (expected about 103)")
	_reset(w, keep)


# ---------------------------------------------------------------- the newborn

func test_newborn_fields(t) -> void:
	var w := _world(91, 2)
	var habs := _habs(w)
	for h in habs:
		_put(w, h, 2)
	var keep := w.beings.size()
	var seen := 0
	var e_lo := 1e9
	var e_hi := -1e9
	var e_sum := 0.0
	var w_lo := 1e9
	var w_hi := -1e9
	var w_sum := 0.0
	var by_hab := {}
	var syl_a: Array = SimData.beings().names.syllables_a
	var syl_b: Array = SimData.beings().names.syllables_b
	var nm := RegEx.new()
	nm.compile("^([A-Za-z]+)-(\\d+)$")
	# Ids are never reused: removed newborns leave gaps, so the next id is one above the highest id ever seen.
	var top_id := 0
	for b in w.beings:
		top_id = maxi(top_id, b.id)
	for i in 600:
		_reset(w, keep)
		var before := w.beings.size()
		_check(w)
		for k in range(before, w.beings.size()):
			var nb: Being = w.beings[k]
			seen += 1
			by_hab[nb.building_id] = int(by_hab.get(nb.building_id, 0)) + 1
			t.check(nb.building_id in habs, "newborn is in a habitat")
			t.check(nb.is_inside(), "newborn is inside")
			t.eq(nb.state, "idle", "newborn state")
			t.eq(nb.id, top_id + 1, "newborn id is the next in sequence")
			top_id = nb.id
			t.eq(nb.earth_born, false, "newborn is Mars-born")
			t.eq(nb.born_t, w.t, "born_t is the world t of the birth step")
			t.eq(nb.role, nb.persona.role, "role is the persona's role")
			t.check(nb.x == null and nb.y == null and nb.air_h == null and nb.job == null and nb.mine == null,
					"newborn has no outside state")
			t.check(not nb.sleep_intent and not nb.suit_up and nb.sleep_started_t == null, "newborn flags clear")
			t.eq(nb.load, 0.0, "newborn load")
			var m := nm.search(nb.name)
			t.check(m != null, "name shape syllable-number: %s" % nb.name)
			if m != null:
				var num := int(m.get_string(2))
				t.check(num >= 1 and num <= 99, "name number 1..99: %s" % nb.name)
				var ok := false
				for a in syl_a:
					if m.get_string(1).begins_with(a) and m.get_string(1).substr(a.length()) in syl_b:
						ok = true
				t.check(ok, "name syllables come from the data lists: %s" % nb.name)
			t.between(nb.energy, 70.0, 100.0, "newborn energy")
			t.between(nb.wait_h, 0.0, 2.0, "newborn wait_h")
			e_lo = minf(e_lo, nb.energy)
			e_hi = maxf(e_hi, nb.energy)
			e_sum += nb.energy
			w_lo = minf(w_lo, nb.wait_h)
			w_hi = maxf(w_hi, nb.wait_h)
			w_sum += nb.wait_h
	print("    %d newborns: energy %.1f..%.1f mean %.2f, wait_h %.2f..%.2f mean %.3f, per habitat %s" % [seen, e_lo,
			e_hi, e_sum / seen, w_lo, w_hi, w_sum / seen, str(by_hab)])
	t.check(seen >= 200, "enough newborns (%d)" % seen)
	t.near(e_sum / seen, 85.0, 1.5, "mean newborn energy (U(70,100))")
	t.check(e_lo < 72.0 and e_hi > 98.0, "newborn energy spans the range")
	t.near(w_sum / seen, 1.0, 0.1, "mean newborn wait_h (U(0,2))")
	t.check(w_lo < 0.1 and w_hi > 1.9, "newborn wait_h spans the range")
	t.eq(by_hab.size(), 2, "both habitats birth")


## The persona comes from the Mars chart at the birth t and the building centre's longitude.
## Odd widths put the centre on a half tile, so a rounded or left-edge longitude is caught by the sign boundaries.
func test_newborn_persona_from_mars_chart(t) -> void:
	var w := SimWorld.new(92, {"blank": true})
	w.add_building("reactor", 0, 60)
	w.add_building("reactor", 40, 60)
	w.add_building("green_room", 20, 60)
	w.add_building("workshop", 0, 60)
	var sites := [[0, 13], [300, 11], [-250, 14], [-90, 9]]
	var habs: Array = []
	for s in sites:
		var b := w.buildings.add("habitat", s[0], 0, 1.0, s[1], 9)
		habs.append(b)
		_put(w, b.id, 2)
	var keep := w.beings.size()
	var compared := 0
	var roles := {}
	var lons := {}
	for i in 1500:
		_reset(w, keep)
		w.t += 1.0 + float((i * 37) % 53) * 0.97  # walk through the days and the years
		var before := w.beings.size()
		_check(w)
		for k in range(before, w.beings.size()):
			var nb: Being = w.beings[k]
			var hb: Buildings.Building = w.buildings.get_building(nb.building_id)
			var lon := w.clock.lon_of_tile(hb.tx + hb.tw / 2.0)
			var chart := w.sky.mars_chart(w.t, lon)
			var want := w.persona.persona_from(chart)
			compared += 1
			lons[hb.id] = lon
			roles[nb.role] = int(roles.get(nb.role, 0)) + 1
			t.eq(nb.persona, want, "persona equals persona_from(mars_chart(t, lon_of_tile(tx + tw/2)))")
			t.eq(nb.role, want.role, "role")
			t.eq(nb.born_t, w.t, "born_t")
	print("    %d newborn charts compared; roles %s; habitat longitudes %s" % [compared, str(roles), str(lons.values())])
	t.check(compared >= 600, "enough newborns compared (%d)" % compared)
	t.check(roles.size() >= 4, "all four roles occur among newborns (%s)" % str(roles))


# ---------------------------------------------------------------- stats and log

func test_births_stats_and_log(t) -> void:
	var w := _open(95)
	t.eq(w.stats.births, 0, "births starts at 0")
	t.check(w.stats.has("first_birth_sol"), "stats has first_birth_sol")
	t.eq(w.stats.get("first_birth_sol", 0), null, "first_birth_sol is null before any birth")
	t.eq(w.stats.births_at_capacity, 0, "births_at_capacity starts at 0")
	t.eq(w.stats.cooldown_violations, 0, "cooldown_violations starts at 0")
	# First birth in elapsed sol 2.
	w.t += 2.0 * SOL_H + 3.0
	var hab: int = _habs(w)[0]
	var made := 0
	var tries := 0
	while made == 0 and tries < 200:
		w.colony.last_birth_t.clear()
		made = _check(w)
		tries += 1
	t.eq(made, 1, "a birth within 200 checks (%d tries)" % tries)
	t.eq(w.stats.births, 1, "births counts it")
	t.eq(w.stats.get("first_birth_sol", null), w.sol(), "first_birth_sol is the elapsed sol of the birth")
	t.eq(w.stats.get("first_birth_sol", null), 2, "that sol is 2")
	t.eq(w.colony.last_birth_t.get(hab, null), w.t, "last_birth_t[H] is the world t of the birth")
	var logs := _born_log(w)
	t.eq(logs.size(), 1, "one born log entry")
	if logs.size() == 1:
		var e: Dictionary = logs[0]
		var nb: Being = w.beings.back()
		t.eq(e.t, w.t, "log t")
		t.eq(e.sol, w.sol(), "log sol")
		t.eq(e.get("being_id", -1), nb.id, "log being_id")
		t.eq(e.get("building_id", -1), hab, "log building_id")
		t.check(String(e.text) != "", "log text is not empty")
	# A later birth, sols after: first_birth_sol does not move, counters add up.
	w.t += 3.0 * SOL_H
	made = 0
	tries = 0
	while made == 0 and tries < 200:
		w.colony.last_birth_t.clear()
		made = _check(w)
		tries += 1
	t.eq(made, 1, "a second birth (%d tries)" % tries)
	t.eq(w.stats.births, 2, "births counts both")
	t.eq(w.stats.get("first_birth_sol", null), 2, "first_birth_sol stays at the first birth")
	t.eq(_born_log(w).size(), 2, "two born log entries")
	t.eq(w.stats.births_at_capacity, 0, "births_at_capacity stays 0")
	t.eq(w.stats.cooldown_violations, 0, "cooldown_violations stays 0")


func test_extinct_colony_has_no_births(t) -> void:
	var w := _world(96)
	for i in 400:
		w.step()
	t.eq(w.stats.births, 0, "no beings, no births")
	t.eq(w.colony.pop(), 0, "still nobody")
	t.eq(w.colony.extinct, true, "extinct")


# ---------------------------------------------------------------- determinism

func _fingerprint(w: SimWorld) -> String:
	var s := "t=%.6f births=%d" % [w.t, int(w.stats.births)]
	for b in w.beings:
		s += "|%d,%s,%.9f,%.9f,%d,%s,%s,%.6f" % [b.id, b.name, b.energy, b.wait_h, b.building_id, b.role, b.state, b.born_t]
	for k in w.colony.last_birth_t:
		s += "|L%d=%.6f" % [k, w.colony.last_birth_t[k]]
	return s


func test_births_are_deterministic_per_seed(t) -> void:
	# Pinned world: the same seed gives the same births, names, energies and times; another seed differs.
	var prints := {}
	for s in [3, 3, 4]:
		var w := _open(s)
		for i in 2400:
			_pin(w)
			w.step()
		var fp := _fingerprint(w)
		if prints.has(s):
			t.eq(fp, prints[s], "seed %d replays identically" % s)
		prints[s] = fp
		t.check(int(w.stats.births) >= 1, "seed %d: at least one birth in 2400 steps (%d)" % [s, int(w.stats.births)])
	t.check(prints[3] != prints[4], "seeds 3 and 4 differ")
	# Free-running world (beings walk, sleep, draw): same seed, same everything.
	var runs: Array = []
	for r in 2:
		var w := _world(7)
		_put(w, _habs(w)[0], 3)
		for i in 1500:
			w.step()
		runs.append(_fingerprint(w) + "|log=%d" % w.log.size())
	t.eq(runs[0], runs[1], "free-running world replays identically")
	# Founder world: the whole run, births or not, replays.
	var f: Array = []
	for r in 2:
		var w := SimWorld.new(42)
		for i in 1500:
			w.step()
		f.append("%s|log=%d|stats=%s" % [_fingerprint(w), w.log.size(), str(w.stats.births)])
	t.eq(f[0], f[1], "founder world at seed 42 replays identically over 1500 steps")
