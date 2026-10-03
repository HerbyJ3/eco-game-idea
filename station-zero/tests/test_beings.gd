extends RefCounted
## Task 1, step 6: beings, energy and sleep. Spec: docs/specs/life-support-power.md sections 3 (comparators,
## randomness), 4 (Being), 5 (phase 6, phase 11), 6.1 to 6.4 (energy, interior timing, update order, decide),
## 10.2 (founders), 16 (stats) and the "Tests (tests/test_beings.gd)" list, restricted to what exists without
## EVA, mining, construction or births (steps 7 to 9).
##
## Existing API used (steps 1..5): SimWorld.new(seed, {"blank": true}), add_building / add_being / set_offline,
##  step(), t, rng, clock (mars_hour), colony.food / death_timer_h / regolith, buildings (add, add_attached,
##  get_building, list, next_hop, nearest_online_habitat, last_short_t), beings, founders, stats, log, persona, sky,
##  Being fields (state, energy, wait_h, building_id, sleep_intent, sleep_started_t, corridor_id, transit_t,
##  from_a, persona, role, earth_born, born_t, name).  Time of day is set by writing world.t (the Mars hour is
##  clock.mars_hour(t)); beings are tuned by direct field writes, as in tests/test_power.gd.
##
## API ASSUMED beyond the existing one (extended the simplest way):
##  - SimWorld.step() runs phase 6: every living being, ascending id, is updated (spec 6.3), and phase 11 samples
##    the being stats.  The Mars hour used for "night" is the one at the world clock AFTER this step's t += dt.
##  - Being.drain_per_h() -> float: the energy drain per hour of the being's CURRENT state (idle, to_door and
##    transit 1.3, eva 2, mining 2.6, work 3; sleep 0), read from data/beings.json.  It is the only new method.
##    (Guarded with has_method; a missing method fails with a clear message.)
##  - Stats are top-level keys of world.stats (as in steps 4 and 5, not stats.window): being_steps (int),
##    asleep_being_steps (int), energy_sum (float), max_sleep_h (float); all 0 in a fresh world.  Phase 11 adds,
##    per step, the living beings, those in state sleep, the sum of their energies, and max(t - sleep_started_t)
##    over sleepers.  Average energy = energy_sum / being_steps; asleep share = asleep_being_steps / being_steps.
##  - A being with wait_h <= 0 in state idle decides in the SAME step (the countdown, then decide), as the parked
##    floor-sleep test in tests/test_power.gd already assumes.  decide() sets wait_h and nothing counts it down
##    again in that step, so wait_h read after one step is the drawn value (tests allow one step of slack).
##  - Leaving a sleep sets sleep_started_t back to null (spec section 4: "else null").
##  - Founders: world.beings[i] is founder i of beings.founders.layout (ids 1..7, ascending), placed in the first
##    building of that home kind (reactor 1, habitat 2, workshop 3), with earth_born = true, persona and role
##    equal to world.founders[i].persona, born_t = world.founders[i].born, energy U(70,100), wait_h U(0,2).
##    The founder retry redraws the whole sky.founder_birth (spec 10.2); founder 0 is drawn first, before any
##    other rng use, so a replay of SimRng(seed) reproduces founders[0].  stats.founder_role_miss counts exhausted
##    retries (0 in every tested seed).
##  - The 5-sol run needs "no EVA permitted": resources.json mine_attempt.chance is set to 0 for the run (the
##    SimData cache is edited and restored) and colony.regolith is set to 0 so no construction site is ever
##    started (steps 7 and later).  In step 6 neither is exercised yet, they keep the test valid afterwards.
##
## Spec facts the test numbers rest on, and two deliberate departures from the spec's example inputs:
##  - The sleep and wake thresholds are compared against the energy AFTER this step's drain (update_being drains
##    first, decide runs later; the spec says the same for the exhausted turn-back and for the yield).  So the
##    boundary pair is input 28.06 (reads 27.995, sleeps) and 28.07 (reads 28.005, awake), not 27.9 / 28.0, and
##    "65 at night never rolls" is input 65.1 (reads 65.035).  27.9 and 64 are also tested, as the spec lists.
##  - Starving sleep length: the spec's "77/4 = 19.25 h" cannot be observed, because in daytime a sleeper above
##    energy 75 wakes with chance 0.3 x dt per step.  The starving test starts at energy 70 inside the night
##    (6.75 h, 135 steps, ends before 5.5); the fed test is the spec's 20 to 97 in 7.0 h.
##
## NOT written here (belongs to the later steps, because it needs outside states or sites):
##  - step 7 (construction): the drain of a being in state work, stepped for one hour from energy 80 (77.0);
##    join-construction in decide; sleep before join in decide.
##  - step 8 (suits, EVA, mining): the drain of eva (78.0) and mining (77.4) stepped for one hour; the exhausted
##    turn-back (spec 6.1: outside, energy < 12, not returning, state mining/work/eva with after mine/work, input
##    12.1 reads 11.95 after one work step, gets returning and a path home, air_h keeps falling 0.05 per step, no
##    colony oxygen spent); the mine_intent and mining-attempt branches of decide; to_door with suit_up.
##    Here the three outside drains are checked through drain_per_h() only.
##  - step 9 (births): the spec's birth tests; the founder role mix is tested here, as the plan assigns founders
##    to step 6.
##
## Layout used by the world helpers (all hand-made, no find_spot):
##    R reactor (0,0,12x10)      A habitat right of R (gap 7, 13x9, corridor 56 px)
##    B habitat left of R (gap 12, 12x9, corridor 96 px)   W workshop below R (gap 6, 12x9, corridor 48 px)
##    X comms above B (gap 6).   A second reactor is parked far away so power never shorts anything.
##    Centre distances (tiles): from R: A 19.5, B 24.0; from W: A 24.6, B 28.3; from X: B 14.5, A 45.8.

const DT := 0.05
const SOL_H := 24.6597
## spec section 6.4 / beings.room_pull: [trait, multiplier] per neighbour kind.
const PULL := {
	"workshop": ["drive", 1.0], "archive": ["curiosity", 1.0], "comms": ["curiosity", 0.8],
	"habitat": ["sociability", 1.0], "green_room": ["care", 1.0], "reactor": ["steady", 0.7],
}


# ---------------------------------------------------------------- helpers

## Blank world, R (id 1) and the parked reactor (id 2); A, B, W, X as described above (ids 3..6).
func _hub(seed_in: int) -> Dictionary:
	var w := SimWorld.new(seed_in, {"blank": true})
	var r := w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	w.add_building("reactor", 300, 300)
	var a := w.buildings.add_attached("habitat", r.id, "r", 13, 9, 7)
	var b := w.buildings.add_attached("habitat", r.id, "l", 12, 9, 12)
	var wk := w.buildings.add_attached("workshop", r.id, "d", 12, 9, 6)
	var x := w.buildings.add_attached("comms", b.id, "u", 12, 8, 6)
	return {"w": w, "R": r.id, "A": a.id, "B": b.id, "W": wk.id, "X": x.id}


## Blank world with a reactor (id 1) and one isolated habitat (id 2): no tunnels anywhere.
func _iso(seed_in: int) -> SimWorld:
	var w := SimWorld.new(seed_in, {"blank": true})
	w.add_building("reactor", 0, 0)
	w.add_building("habitat", 50, 0)
	return w


## R with six neighbours (workshop, archive, comms, habitat, green_room, reactor) so every room-pull kind appears.
func _star(seed_in: int) -> Dictionary:
	var w := SimWorld.new(seed_in, {"blank": true})
	var r := w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	var dirs := ["r", "l", "u", "d", "r", "l"]
	var kinds := ["workshop", "archive", "comms", "habitat", "green_room", "reactor"]
	var ids := {}
	for i in kinds.size():
		ids[kinds[i]] = w.buildings.add_attached(kinds[i], r.id, dirs[i], 10, 8, 6).id
	return {"w": w, "R": r.id, "ids": ids}


## Sets the world clock so that the Mars hour AFTER the next step is `hour`. Uses the following sol so that
## t stays above start_hour.
func _hour(w: SimWorld, hour: float) -> void:
	var k := floorf(w.t / SOL_H) + 1.0
	w.t = (k + hour / 24.0) * SOL_H - DT
	w.buildings.now = w.t


func _put(w: SimWorld, building_id: int, energy: float, wait_h: float = 0.0) -> Being:
	var b := w.add_being(building_id, "social")
	b.energy = energy
	b.wait_h = wait_h
	return b


func _sleeper(w: SimWorld, building_id: int, energy: float) -> Being:
	var b := _put(w, building_id, energy, 100.0)
	b.state = "sleep"
	b.sleep_started_t = w.t
	return b


## n steps; with `hold` the 3 h re-online hold is refreshed first so a dark building stays dark.
func _run(w: SimWorld, n: int, hold: bool = false) -> void:
	for i in n:
		if hold:
			w.buildings.last_short_t = w.t
		w.step()


## Steps with food at 0 and the shortage death timer held, so a starving sleeper cannot die mid-test.
func _run_starving(w: SimWorld, n: int) -> void:
	for i in n:
		w.colony.food = 0.0
		w.colony.death_timer_h = 0.0
		w.step()


func _persona(b: Being, traits: Dictionary) -> void:
	for k in traits:
		b.persona.traits[k] = traits[k]


func _count_state(w: SimWorld, state: String) -> int:
	var n := 0
	for b in w.beings:
		if b.state == state:
			n += 1
	return n


func _mean(values: Array) -> float:
	var s := 0.0
	for v in values:
		s += float(v)
	return s / maxf(1.0, float(values.size()))


## Next value of the world rng; two worlds that drew the same number of times from the same seed agree.
func _rng_next(w: SimWorld) -> float:
	return w.rng.randf()


## idle_wait(): walk U(10,56) px / (10 x (0.75 + 0.5 drive)) + pause U(1,4) x (0.5 + 1.2 steady).
func _idle_wait_bounds(drive: float, steady: float) -> Array:
	var f := 10.0 * (0.75 + 0.5 * drive)
	var p := 0.5 + 1.2 * steady
	return [10.0 / f + 1.0 * p, 56.0 / f + 4.0 * p, 33.0 / f + 2.5 * p]


## Steps one being until `pred` holds or `max_steps` pass; returns {steps, seq, intents_ok, intent_at_sleep}.
## seq is the list of distinct consecutive states seen.
func _journey(w: SimWorld, b: Being, max_steps: int) -> Dictionary:
	var seq: Array = []
	var intents_ok := true
	var steps := 0
	var started := false
	while steps < max_steps:
		w.buildings.last_short_t = w.t
		w.step()
		steps += 1
		if seq.is_empty() or seq[seq.size() - 1] != b.state:
			seq.append(b.state)
		if b.state == "to_door" or b.state == "transit":
			started = true
		if started and b.state != "sleep" and not b.sleep_intent:
			intents_ok = false
		if b.state == "sleep":
			break
	return {"steps": steps, "seq": seq, "intents_ok": intents_ok, "intent_at_sleep": b.sleep_intent}


# ---------------------------------------------------------------- drain per state

func test_drain_rate_per_state(t) -> void:
	var b := Being.new()
	if not b.has_method("drain_per_h"):
		t.check(false, "missing Being.drain_per_h()")
		return
	var expected := {"idle": 1.3, "to_door": 1.3, "transit": 1.3, "eva": 2.0, "mining": 2.6, "work": 3.0, "sleep": 0.0}
	for s in expected:
		b.state = s
		t.near(float(b.call("drain_per_h")), expected[s], 1e-12, "drain per hour in state %s" % s)


func test_drain_one_hour_idle_to_door_and_transit(t) -> void:
	# From energy 80, 20 steps (1 h): 80 - 1.3 = 78.7 in each inside state (tolerance 1e-6).
	for s in ["idle", "to_door", "transit"]:
		var h := _hub(1)
		var w: SimWorld = h.w
		_hour(w, 12.0)
		var b := _put(w, h.W, 80.0, 100.0)
		b.state = s
		if s != "idle":
			b.corridor_id = h.W  # the 48 px tunnel to R: 20 steps cover only 22 px, still in transit
			b.transit_t = 0.0
			b.from_a = true
		_run(w, 20)
		t.eq(b.state, s, "%s: still in the same state after one hour" % s)
		t.near(b.energy, 78.7, 1e-6, "%s: energy after one hour from 80" % s)


func test_sleep_does_not_drain_and_gains_11_fed_4_starving(t) -> void:
	var h := _hub(2)
	var w: SimWorld = h.w
	_hour(w, 12.0)
	var b := _sleeper(w, h.A, 20.0)
	_run(w, 20)
	t.eq(b.state, "sleep", "fed sleeper still asleep after an hour (day, energy 31 is below 75)")
	t.near(b.energy, 31.0, 1e-6, "fed: 20 + 11 per hour")
	var h2 := _hub(2)
	var w2: SimWorld = h2.w
	_hour(w2, 12.0)
	var b2 := _sleeper(w2, h2.A, 20.0)
	_run_starving(w2, 20)
	t.near(b2.energy, 24.0, 1e-6, "food 0: 20 + 4 per hour")
	t.eq(b2.state, "sleep", "starving sleeper still asleep")


func test_fed_sleep_from_20_to_97_takes_7_hours(t) -> void:
	var h := _hub(3)
	var w: SimWorld = h.w
	_hour(w, 22.0)  # night: no daytime wake chance, 22:00 to 05:00 stays inside the 21.5 to 5.5 window
	var b := _sleeper(w, h.A, 20.0)
	var steps := 0
	while b.state == "sleep" and steps < 400:
		w.step()
		steps += 1
	print("    fed sleep 20 -> 97: %d steps (%.2f h); wait_h on waking %.2f" % [steps, steps * DT, b.wait_h])
	t.between(steps, 139, 141, "77/11 = 7.0 h = 140 steps (+-1)")
	t.eq(b.state, "idle", "wakes into idle")
	t.check(b.energy >= 97.0 - 1e-9, "wakes at energy >= 97 (%.3f)" % b.energy)
	t.eq(b.sleep_started_t, null, "sleep_started_t cleared on waking")
	var bounds := _idle_wait_bounds(0.5, 0.5)
	t.between(b.wait_h, bounds[0] - DT, bounds[1] + 1e-9, "wait_h = idle_wait() on waking")
	t.near(float(w.stats.max_sleep_h), steps * DT, 0.1, "max_sleep_h keeps the completed sleep (about 7 h)")


func test_starving_sleep_gains_4_per_hour_to_97(t) -> void:
	var h := _hub(4)
	var w: SimWorld = h.w
	_hour(w, 22.0)
	var b := _sleeper(w, h.A, 70.0)
	var steps := 0
	while b.state == "sleep" and steps < 400:
		_run_starving(w, 1)
		steps += 1
	print("    starving sleep 70 -> 97: %d steps (%.2f h)" % [steps, steps * DT])
	t.between(steps, 134, 136, "27/4 = 6.75 h = 135 steps (+-1)")
	t.check(b.energy >= 97.0 - 1e-9, "wakes at 97")


# ---------------------------------------------------------------- sleep triggers

func test_sleep_below_28_energy_after_drain(t) -> void:
	# Day (12:00). The being is in a habitat, so it sleeps in place.
	var cases := [[27.9, true], [28.06, true], [28.07, false], [28.1, false], [40.0, false]]
	for c in cases:
		var w := _iso(1)
		_hour(w, 12.0)
		var b := _put(w, 2, c[0])
		w.step()
		t.eq(b.state == "sleep", c[1], "energy %.2f in daytime (reads %.3f after the drain)" % [c[0], c[0] - 0.065])
		if c[1]:
			t.eq(b.building_id, 2, "sleeps in place in its habitat")
			t.near(float(b.sleep_started_t), w.t, 1e-9, "sleep_started_t = the step it fell asleep")


func test_sleep_intent_forces_sleep_and_is_cleared_on_entering_sleep(t) -> void:
	var w := _iso(1)
	_hour(w, 12.0)
	var b := _put(w, 2, 90.0)
	b.sleep_intent = true
	w.step()
	t.eq(b.state, "sleep", "sleep_intent sends a rested being to bed")
	t.eq(b.sleep_intent, false, "sleep_intent cleared on entering sleep")


func test_night_sleep_chance_is_0_6_below_65(t) -> void:
	# Per spec: 64 at night sleeps in a 0.6 fraction of 2,000 trials (0.55..0.65); 65 never rolls.
	# Hours 23 and 2 cross midnight; 21.4 and 5.6 are outside the 21.5 to 5.5 window; 21.6 and 5.4 inside.
	var rows := [[23.0, 64.0, true], [2.0, 64.0, true], [21.6, 64.0, true], [5.4, 64.0, true],
			[12.0, 64.0, false], [21.4, 64.0, false], [5.6, 64.0, false],
			[23.0, 65.1, false], [2.0, 65.1, false], [23.0, 90.0, false]]
	for r in rows:
		var w := _iso(7)
		_hour(w, r[0])
		for i in 2000:
			_put(w, 2, r[1])
		w.step()
		var frac := float(_count_state(w, "sleep")) / 2000.0
		if r[2]:
			print("    hour %.1f energy %.1f: asleep fraction %.3f" % [r[0], r[1], frac])
			t.between(frac, 0.55, 0.65, "hour %.1f energy %.1f sleeps with chance 0.6" % [r[0], r[1]])
		else:
			t.eq(frac, 0.0, "hour %.1f energy %.1f never sleeps" % [r[0], r[1]])


func test_conditional_chance_draws(t) -> void:
	# The night chance is drawn only when night and energy < 65 and energy >= 28 (spec 3, 6.1). A world that
	# skipped the draw has the same rng position as another that skipped it; a world that drew differs.
	var day_60 := _iso(11)
	_hour(day_60, 12.0)
	_put(day_60, 2, 60.0)
	day_60.step()
	var night_70 := _iso(11)
	_hour(night_70, 23.0)
	_put(night_70, 2, 70.0)
	night_70.step()
	var night_60 := _iso(11)
	_hour(night_60, 23.0)
	_put(night_60, 2, 60.0)
	night_60.step()
	t.eq(_rng_next(night_70), _rng_next(day_60), "no draw by day and none at night above 65 (same rng position)")
	var day_ref := _iso(11)
	_hour(day_ref, 12.0)
	_put(day_ref, 2, 60.0)
	day_ref.step()
	t.check(_rng_next(night_60) != _rng_next(day_ref), "night and energy 60 draws the chance")
	# Below 28 the OR short-circuits: no chance is drawn even at night, so the rng is untouched.
	var low := _iso(11)
	_hour(low, 23.0)
	var lb := _put(low, 2, 20.0)
	low.step()
	var pristine := _iso(11)
	_put(pristine, 2, 20.0)
	t.eq(lb.state, "sleep", "energy 20 at night sleeps")
	t.eq(_rng_next(low), _rng_next(pristine), "energy < 28 sleeps without drawing the night chance")
	# Sleep intent short-circuits too.
	var intent := _iso(11)
	_hour(intent, 23.0)
	var ib := _put(intent, 2, 60.0)
	ib.sleep_intent = true
	intent.step()
	var pristine2 := _iso(11)
	_put(pristine2, 2, 60.0)
	t.eq(ib.state, "sleep", "sleep_intent at night sleeps")
	t.eq(_rng_next(intent), _rng_next(pristine2), "sleep_intent sleeps without drawing the night chance")


# ---------------------------------------------------------------- wake rule

func test_wake_chance_by_day_is_0_015_per_step(t) -> void:
	# Not night, energy 80: after the gain (80.55 > 75) wakes with chance 0.3 x 0.05 = 0.015 per step.
	var w := _iso(5)
	_hour(w, 12.0)
	var sleepers: Array = []
	for i in 1000:
		sleepers.append(_sleeper(w, 2, 80.0))
	w.step()
	var woke := 1000 - _count_state(w, "sleep")
	print("    day wake, 1000 sleepers at 80, one step: %d woke (expect 15)" % woke)
	t.between(woke, 5, 30, "about 15 of 1000 wake in one step")
	for b in sleepers:
		if b.state != "sleep":
			t.eq(b.state, "idle", "a woken sleeper is idle")
			t.eq(b.sleep_started_t, null, "a woken sleeper has no sleep_started_t")
			break
	# Over a stretch the chance accumulates: from 76 a sleeper reaches 97 in 39 steps; 1 - 0.985^38 = 0.44 wake early.
	var w2 := _iso(6)
	_hour(w2, 10.0)
	var group: Array = []
	for i in 1000:
		group.append(_sleeper(w2, 2, 76.0))
	var early := 0
	var steps := 0
	while steps < 60:
		w2.step()
		steps += 1
	for b in group:
		if b.energy < 96.0:
			early += 1
	print("    day wake from 76: %d of 1000 woke below 96 (expect about 440)" % early)
	t.between(early, 350, 530, "daytime sleepers above 75 often wake before 97")


func test_no_day_wake_at_or_below_75_and_none_at_night_before_97(t) -> void:
	var w := _iso(5)
	_hour(w, 12.0)
	for i in 1000:
		_sleeper(w, 2, 74.0)
	w.step()
	t.eq(_count_state(w, "sleep"), 1000, "energy 74 by day: nobody wakes")
	var n := _iso(5)
	_hour(n, 23.0)
	for i in 1000:
		_sleeper(n, 2, 80.0)
	n.step()
	t.eq(_count_state(n, "sleep"), 1000, "night, energy 80: nobody wakes")
	var n2 := _iso(5)
	_hour(n2, 2.0)
	for i in 1000:
		_sleeper(n2, 2, 96.4)
	n2.step()
	t.eq(_count_state(n2, "sleep"), 1000, "night, energy 96.4 reads 96.95: nobody wakes")
	var n3 := _iso(5)
	_hour(n3, 2.0)
	for i in 1000:
		_sleeper(n3, 2, 96.5)
	n3.step()
	t.eq(_count_state(n3, "sleep"), 0, "night, energy 96.5 reads 97.05: everybody wakes")
	var d := _iso(5)
	_hour(d, 12.0)
	for i in 1000:
		_sleeper(d, 2, 96.5)
	d.step()
	t.eq(_count_state(d, "sleep"), 0, "day, energy 96.5 reads 97.05: everybody wakes without a roll")


func test_wake_chance_draws_only_when_day_and_energy_between_75_and_97(t) -> void:
	var day_74 := _iso(21)
	_hour(day_74, 12.0)
	_sleeper(day_74, 2, 74.0)
	day_74.step()
	var night_80 := _iso(21)
	_hour(night_80, 23.0)
	_sleeper(night_80, 2, 80.0)
	night_80.step()
	var pristine := _iso(21)
	_sleeper(pristine, 2, 74.0)
	var base := _rng_next(pristine)
	t.eq(_rng_next(day_74), base, "day, energy 74: no wake draw")
	t.eq(_rng_next(night_80), base, "night, energy 80: no wake draw")
	var day_80 := _iso(21)
	_hour(day_80, 12.0)
	_sleeper(day_80, 2, 80.0)
	day_80.step()
	t.check(_rng_next(day_80) != base, "day, energy 80: the wake chance is drawn")


# ---------------------------------------------------------------- nearest online habitat, floor sleep

## Puts one being (energy 20, day) in `from`, runs until it sleeps, returns the journey plus final building.
func _sleep_journey(w: SimWorld, from: int) -> Dictionary:
	_hour(w, 12.0)
	var b := _put(w, from, 20.0)
	var j := _journey(w, b, 900)
	j["building"] = b.building_id
	j["being"] = b
	return j


func test_nearest_online_habitat_is_measured_from_the_current_building(t) -> void:
	var h := _hub(1)
	var j := _sleep_journey(h.w, h.W)
	t.eq(j.being.state, "sleep", "from W both habitats online: ends asleep")
	t.eq(j.building, h.A, "from W the nearer habitat A (24.6 tiles, B is 28.3)")
	var h2 := _hub(1)
	var j2 := _sleep_journey(h2.w, h2.R)
	t.eq(j2.building, h2.A, "from R: A (19.5) beats B (24.0)")
	var h3 := _hub(1)
	var j3 := _sleep_journey(h3.w, h3.X)
	t.eq(j3.building, h3.B, "from X, which hangs off B, the nearest is B (14.5), not A (45.8)")
	var h4 := _hub(1)
	var j4 := _sleep_journey(h4.w, h4.B)
	t.eq(j4.building, h4.B, "a being already in a habitat sleeps there")
	t.eq(j4.steps, 1, "and at once")
	var h5 := _hub(1)
	var j5 := _sleep_journey(h5.w, h5.A)
	t.eq(j5.building, h5.A, "in habitat A, sleeps in A though B is online")


func test_offline_habitat_is_skipped_and_the_next_online_one_is_chosen(t) -> void:
	var h := _hub(2)
	var w: SimWorld = h.w
	w.set_offline(h.A, true)
	_hour(w, 12.0)
	var b := _put(w, h.W, 20.0)
	var j := _journey(w, b, 900)
	t.check(w.buildings.get_building(h.A).offline, "A stayed dark (hold refreshed)")
	t.eq(b.state, "sleep", "ends asleep")
	t.eq(b.building_id, h.B, "A is nearer but offline: the farther online B is chosen")
	t.eq(j.intent_at_sleep, false, "sleep_intent false once asleep")
	# A being whose own habitat is dark walks to the other one.
	var h2 := _hub(2)
	var w2: SimWorld = h2.w
	w2.set_offline(h2.B, true)
	_hour(w2, 12.0)
	var b2 := _put(w2, h2.B, 20.0)
	_journey(w2, b2, 900)
	t.eq(b2.building_id, h2.A, "a being inside a dark habitat goes to the online one")


func test_equidistant_habitats_tie_goes_to_the_lowest_id(t) -> void:
	for order in [0, 1]:
		var w := SimWorld.new(1, {"blank": true})
		var r := w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
		w.add_building("reactor", 300, 300)
		var first_dir := "l" if order == 0 else "r"
		var second_dir := "r" if order == 0 else "l"
		var p := w.buildings.add_attached("habitat", r.id, first_dir, 13, 9, 7)
		var q := w.buildings.add_attached("habitat", r.id, second_dir, 13, 9, 7)
		t.check(p.id < q.id, "ids ascend")
		_hour(w, 12.0)
		var b := _put(w, r.id, 20.0)
		w.step()
		t.eq(b.state, "to_door", "order %d: heads for a habitat" % order)
		t.eq(b.corridor_id, p.id, "order %d: the corridor of the lower id (both 19.5 tiles away)" % order)


func test_sleeping_on_the_floor_when_there_is_no_online_habitat_or_no_path(t) -> void:
	# No habitat at all: sleeps at once in the building it is in, at the usual gain.
	var w := SimWorld.new(1, {"blank": true})
	var r := w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	var wk := w.buildings.add_attached("workshop", r.id, "d", 12, 9, 6)
	_hour(w, 12.0)
	var b := _put(w, wk.id, 20.0)
	w.step()
	t.eq(b.state, "sleep", "no habitat: sleeps at once")
	t.eq(b.building_id, wk.id, "on the floor of the workshop")
	t.eq(b.sleep_intent, false, "no sleep_intent")
	var e0 := b.energy
	_run(w, 20)
	t.near(b.energy - e0, 11.0, 1e-6, "floor sleep gains 11 per hour like a bunk")
	# An online habitat that no corridor reaches: no hop exists, floor again.
	var w2 := SimWorld.new(1, {"blank": true})
	var r2 := w2.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	w2.add_building("habitat", 400, 400)
	_hour(w2, 12.0)
	var b2 := _put(w2, r2.id, 20.0)
	w2.step()
	t.eq(b2.state, "sleep", "habitat unreachable: sleeps on the floor")
	t.eq(b2.building_id, r2.id, "where it stood")
	# Every habitat dark: floor, and the tunnel is irrelevant.
	var h := _hub(3)
	h.w.set_offline(h.A, true)
	h.w.set_offline(h.B, true)
	_hour(h.w, 12.0)
	var b3 := _put(h.w, h.W, 20.0)
	h.w.buildings.last_short_t = h.w.t
	h.w.step()
	t.eq(b3.state, "sleep", "both habitats dark: floor sleep at once")
	t.eq(b3.building_id, h.W, "in the workshop")


func test_sleep_journey_states_intent_and_arrival_wait(t) -> void:
	var h := _hub(5)
	var w: SimWorld = h.w
	_hour(w, 12.0)
	var b := _put(w, h.W, 20.0)
	var j := _journey(w, b, 900)
	print("    journey W -> A: %d steps, states %s" % [j.steps, str(j.seq)])
	t.eq(b.state, "sleep", "ends asleep")
	t.eq(b.building_id, h.A, "in A")
	t.eq(j.seq.slice(0, 2), ["to_door", "transit"], "starts with to_door then the tunnel")
	t.check(j.seq.count("transit") == 2, "two tunnels, W to R and R to A")
	t.eq(j.intents_ok, true, "sleep_intent stays true on the way")
	t.eq(j.intent_at_sleep, false, "and is cleared on entering sleep")
	t.eq(b.corridor_id, h.A, "the last corridor used was A's")
	# Arrival with sleep_intent: wait_h is one step. Probe the first arrival.
	var h2 := _hub(5)
	var w2: SimWorld = h2.w
	_hour(w2, 12.0)
	var b2 := _put(w2, h2.W, 20.0)
	var seen := false
	for i in 600:
		w2.buildings.last_short_t = w2.t
		var before := b2.state
		w2.step()
		if before == "transit" and b2.state == "idle":
			t.between(b2.wait_h, 0.0, DT + 1e-9, "arrival with sleep_intent: wait_h is one step")
			t.eq(b2.building_id, h2.R, "first arrival is in R")
			seen = true
			break
	t.check(seen, "saw the first tunnel arrival")


func test_to_door_time_scales_with_drive(t) -> void:
	# to_door = U(10,56) px / (16 x (0.75 + 0.5 drive)): mean 33/(16 x 1.25) = 1.65 h at drive 1, 2.75 h at drive 0.
	var means := {}
	for d in [0.0, 1.0]:
		var h := _hub(8)
		var w: SimWorld = h.w
		_hour(w, 12.0)
		var waits: Array = []
		var group: Array = []
		for i in 1500:
			var b := _put(w, h.W, 20.0)
			_persona(b, {"drive": d})
			group.append(b)
		w.step()
		var f: float = 16.0 * (0.75 + 0.5 * d)
		for b in group:
			t.eq(b.state, "to_door", "tired being in W heads for a habitat")
			waits.append(b.wait_h)
		var lo: float = waits.min()
		var hi: float = waits.max()
		t.check(lo >= 10.0 / f - DT - 1e-9 and hi <= 56.0 / f + 1e-9, "drive %.0f: to_door in %.2f..%.2f h" % [d, 10.0 / f, 56.0 / f])
		means[d] = _mean(waits)
	print("    to_door mean: drive 0 %.3f h, drive 1 %.3f h, ratio %.3f (expect 2.75, 1.65, 0.6)" % [means[0.0], means[1.0], means[1.0] / means[0.0]])
	t.between(means[0.0], 2.75 * 0.95 - DT, 2.75 * 1.05, "drive 0 mean walk to the door")
	t.between(means[1.0], 1.65 * 0.95 - DT, 1.65 * 1.05, "drive 1 mean walk to the door")
	t.between(means[1.0] / means[0.0], 0.55, 0.65, "drive 1 reaches the door in 0.6 of the time")


# ---------------------------------------------------------------- idle_wait

func test_idle_wait_ranges_and_means(t) -> void:
	var cases := [[0.5, 0.5], [1.0, 0.0], [0.0, 1.0]]
	for c in cases:
		var w := _iso(9)
		_hour(w, 12.0)
		var group: Array = []
		for i in 2000:
			var b := _put(w, 2, 80.0)
			_persona(b, {"drive": c[0], "steady": c[1]})
			group.append(b)
		w.step()
		var waits: Array = []
		for b in group:
			t.eq(b.state, "idle", "a rested being in a tunnel-less building stays")
			waits.append(b.wait_h)
		var bounds := _idle_wait_bounds(c[0], c[1])
		var lo: float = waits.min()
		var hi: float = waits.max()
		var mean := _mean(waits)
		print("    idle_wait drive %.1f steady %.1f: min %.2f max %.2f mean %.3f (expect %.2f..%.2f, mean %.3f)" % [c[0], c[1], lo, hi, mean, bounds[0], bounds[1], bounds[2]])
		t.check(lo >= bounds[0] - DT - 1e-9, "minimum not below %.2f" % bounds[0])
		t.check(hi <= bounds[1] + 1e-9, "maximum not above %.2f" % bounds[1])
		t.check(lo <= bounds[0] + 0.3 and hi >= bounds[1] - 0.3, "the whole range is used")
		t.between(mean, bounds[2] * 0.95 - DT, bounds[2] * 1.05, "mean wait (steady %.1f drive %.1f)" % [c[1], c[0]])


func test_wait_h_counts_down_in_idle_and_decides_at_zero(t) -> void:
	var w := _iso(3)
	_hour(w, 12.0)
	var b := _put(w, 2, 80.0, 0.2)
	w.step()
	t.near(b.wait_h, 0.15, 1e-9, "wait_h counts down by dt")
	t.eq(b.state, "idle", "still waiting")
	_run(w, 2)
	t.near(b.wait_h, 0.05, 1e-9, "wait_h 0.05 after three steps")
	w.step()
	var bounds := _idle_wait_bounds(0.5, 0.5)
	t.check(b.wait_h >= bounds[0] - DT, "at zero the being decided and drew a new idle_wait (%.2f)" % b.wait_h)


# ---------------------------------------------------------------- restless travel and room pull

func test_restless_travel_chance(t) -> void:
	# 0.08 + 0.32 x restless (spec 6.4 step 5), only in a building with built tunnels. 12,000 beings: sd 0.004.
	for r in [0.0, 0.5, 1.0]:
		var s := _star(4)
		var w: SimWorld = s.w
		_hour(w, 12.0)
		for i in 12000:
			var b := _put(w, s.R, 80.0)
			_persona(b, {"restless": r})
		w.step()
		var frac := float(_count_state(w, "to_door")) / 12000.0
		var expect: float = 0.08 + 0.32 * r
		print("    restless %.1f: %.3f travel (expect %.2f)" % [r, frac, expect])
		t.between(frac, expect - 0.015, expect + 0.015, "travel fraction at restless %.1f" % r)
	var w2 := _iso(4)
	_hour(w2, 12.0)
	for i in 500:
		var b := _put(w2, 2, 80.0)
		_persona(b, {"restless": 1.0})
	w2.step()
	t.eq(_count_state(w2, "to_door"), 0, "no tunnels: nobody travels")
	t.eq(_count_state(w2, "idle"), 500, "they all stay idle")


func test_room_pull_follows_the_traits(t) -> void:
	# weight per neighbour = 0.15 + (trait x mult)^2; chosen with randf() x sum in corridor order.
	var personas := [
		{"drive": 1.0, "curiosity": 0.0, "sociability": 0.0, "care": 0.0, "steady": 0.0, "restless": 1.0},
		{"drive": 0.0, "curiosity": 1.0, "sociability": 0.0, "care": 0.0, "steady": 0.0, "restless": 1.0},
		{"drive": 0.0, "curiosity": 0.0, "sociability": 0.5, "care": 0.9, "steady": 1.0, "restless": 1.0},
		{"drive": 0.5, "curiosity": 0.0, "sociability": 0.0, "care": 0.0, "steady": 0.0, "restless": 1.0},
	]
	for p in personas:
		var s := _star(12)
		var w: SimWorld = s.w
		_hour(w, 12.0)
		for i in 6000:
			var b := _put(w, s.R, 80.0)
			_persona(b, p)
		w.step()
		var weights := {}
		var total := 0.0
		for kind in PULL:
			var tr: String = PULL[kind][0]
			weights[kind] = 0.15 + pow(float(p[tr]) * float(PULL[kind][1]), 2.0)
			total += weights[kind]
		var counts := {}
		var movers := 0
		for b in w.beings:
			if b.state == "to_door":
				counts[b.corridor_id] = int(counts.get(b.corridor_id, 0)) + 1
				movers += 1
		t.check(movers > 2000, "enough travellers (%d)" % movers)
		var line := ""
		for kind in PULL:
			var got := float(counts.get(s.ids[kind], 0)) / maxf(1.0, float(movers))
			var want: float = weights[kind] / total
			line += " %s %.3f/%.3f" % [kind, got, want]
			t.between(got, want - 0.035, want + 0.035, "share going to the %s (persona drive %.1f cur %.1f soc %.1f care %.1f steady %.1f)" % [kind, p.drive, p.curiosity, p.sociability, p.care, p.steady])
		print("    room pull (got/expected):" + line)


# ---------------------------------------------------------------- tunnel transit

func test_tunnel_transit_timing(t) -> void:
	# transit_t += dt x 22 / max(1, len): the 48 px tunnel W-R takes 48/22 = 2.18 h = 44 steps, the 56 px tunnel R-A 51.
	var h := _hub(6)
	var w: SimWorld = h.w
	_hour(w, 12.0)
	var short := _put(w, h.W, 80.0, 100.0)
	short.state = "transit"
	short.corridor_id = h.W
	short.transit_t = 0.0
	short.from_a = false  # in W, the child end (direction itself is covered by the sleep journey test)
	var long := _put(w, h.R, 80.0, 100.0)
	long.state = "transit"
	long.corridor_id = h.A
	long.transit_t = 0.0
	long.from_a = true
	var short_done := 0
	var long_done := 0
	for i in 70:
		w.step()
		if i == 9:
			t.near(short.transit_t, 10.0 * DT * 22.0 / 48.0, 1e-9, "transit_t after 10 steps on 48 px")
			t.near(long.transit_t, 10.0 * DT * 22.0 / 56.0, 1e-9, "transit_t after 10 steps on 56 px")
		if short_done == 0 and short.state != "transit":
			short_done = i + 1
		if long_done == 0 and long.state != "transit":
			long_done = i + 1
	print("    transit steps: 48 px %d (expect 44), 56 px %d (expect 51)" % [short_done, long_done])
	t.between(short_done, 43, 45, "48 px tunnel in about 44 steps")
	t.between(long_done, 50, 52, "56 px tunnel in about 51 steps")
	t.eq(short.state, "idle", "arrives idle")
	t.check(short.building_id == h.R or short.building_id == h.W, "arrives in one of the two buildings the tunnel joins")
	var bounds := _idle_wait_bounds(0.5, 0.5)
	t.between(short.wait_h, bounds[0] - DT, bounds[1] + 1e-9, "arrival wait_h = idle_wait()")


func test_a_being_in_transit_is_not_interrupted_by_tiredness(t) -> void:
	var h := _hub(7)
	var w: SimWorld = h.w
	_hour(w, 23.0)
	var b := _put(w, h.W, 10.0, 0.0)
	b.state = "transit"
	b.corridor_id = h.W
	b.transit_t = 0.0
	b.from_a = true
	for i in 20:
		w.step()
		t.eq(b.state, "transit", "step %d: still walking the tunnel at energy %.1f" % [i + 1, b.energy])
	t.eq(b.building_id, h.W, "building_id stays the building it left")
	t.near(b.transit_t, 20.0 * DT * 22.0 / 48.0, 1e-9, "and it kept walking: transit_t after 20 steps")


# ---------------------------------------------------------------- stats

func test_stats_start_at_zero(t) -> void:
	var w := _iso(1)
	for k in ["being_steps", "asleep_being_steps", "energy_sum", "max_sleep_h"]:
		t.check(w.stats.has(k), "stats.%s exists" % k)
		t.eq(float(w.stats.get(k, -1)), 0.0, "stats.%s starts at 0" % k)


func test_asleep_share_and_energy_average_stats(t) -> void:
	var w := _iso(2)
	_hour(w, 23.0)  # night: a sleeper cannot wake before 97
	var sl := _sleeper(w, 2, 20.0)
	var deep := _sleeper(w, 2, 90.0)
	var i1 := _put(w, 2, 80.0, 100.0)
	var i2 := _put(w, 2, 90.0, 100.0)
	var n := 10
	_run(w, n)
	var expect_sum := 0.0
	for k in range(1, n + 1):
		expect_sum += (20.0 + 0.55 * k) + (90.0 + 0.55 * k) + (80.0 - 0.065 * k) + (90.0 - 0.065 * k)
	t.eq(int(w.stats.being_steps), 4 * n, "being_steps: 4 living beings x 10 steps")
	t.eq(int(w.stats.asleep_being_steps), 2 * n, "asleep_being_steps: two sleepers x 10 steps")
	t.near(float(w.stats.energy_sum), expect_sum, 1e-6, "energy_sum is the per-step sum of energies after the step")
	t.near(float(w.stats.asleep_being_steps) / float(w.stats.being_steps), 0.5, 1e-12, "asleep share 1/2")
	t.near(float(w.stats.energy_sum) / float(w.stats.being_steps), expect_sum / 40.0, 1e-6, "average energy")
	t.eq(sl.state, "sleep", "the sleeper kept sleeping")
	t.eq(deep.state, "sleep", "the deep sleeper kept sleeping (95.5 < 97)")
	t.eq(i1.state, "idle", "idle beings stayed idle")
	t.eq(i2.state, "idle", "idle beings stayed idle")
	# A death lowers the count: being_steps follows the living.
	var before := int(w.stats.being_steps)
	w.beings.erase(i2)
	w.step()
	t.eq(int(w.stats.being_steps) - before, 3, "after one being is gone, 3 beings are sampled per step")


func test_max_sleep_h_is_the_longest_current_or_completed_sleep(t) -> void:
	var w := _iso(3)
	_hour(w, 12.0)
	var fresh := _sleeper(w, 2, 20.0)
	var old := _sleeper(w, 2, 20.0)
	old.sleep_started_t = w.t - 2.0
	w.step()
	t.near(float(w.stats.max_sleep_h), 2.05, 1e-6, "the older sleeper sets the maximum: 2 h + one step")
	_run(w, 9)
	t.near(float(w.stats.max_sleep_h), 2.5, 1e-6, "grows 0.05 per step while the longest sleeper sleeps")
	# A completed sleep stays recorded after the being wakes (night, 20 -> 97 in 7.0 h).
	var w2 := _iso(3)
	_hour(w2, 22.0)
	var b := _sleeper(w2, 2, 20.0)
	var steps := 0
	while b.state == "sleep" and steps < 400:
		w2.step()
		steps += 1
	var at_wake := float(w2.stats.max_sleep_h)
	_run(w2, 100)
	t.near(at_wake, 7.0, 0.1, "completed sleep of about 7 h recorded")
	t.eq(float(w2.stats.max_sleep_h), at_wake, "unchanged while the being is awake")
	t.check(fresh.state == "sleep", "sanity")


# ---------------------------------------------------------------- founders

func test_founders_are_seven_beings_in_the_layout_homes(t) -> void:
	var w := SimWorld.new(42)
	var layout: Array = SimData.beings().founders.layout
	t.eq(w.beings.size(), 7, "7 founders")
	t.eq(w.founders.size(), 7, "world.founders keeps 7 entries")
	t.eq(layout.size(), int(SimData.persona().founders.count), "layout length = persona.founders.count")
	var roles := {}
	for i in w.beings.size():
		var b: Being = w.beings[i]
		t.eq(b.id, i + 1, "founder %d has id %d (creation order)" % [i, i + 1])
		t.eq(w.buildings.get_building(b.building_id).kind, layout[i].home, "founder %d lives in the %s" % [i, layout[i].home])
		t.eq(b.role, layout[i].role, "founder %d role after the retry" % i)
		t.eq(b.persona.role, b.role, "persona.role = role")
		t.eq(b.persona, w.founders[i].persona, "being %d keeps world.founders[%d].persona" % [i, i])
		t.eq(b.earth_born, true, "founders are Earth-born")
		t.near(b.born_t, float(w.founders[i].born), 1e-9, "born_t is the founder birth hour")
		var age: float = (w.clock.start_hour - float(w.founders[i].born)) / w.clock.earth_year_h
		t.between(age, 24.0 - 1e-9, 45.0 + 1e-9, "founder %d age in Earth years" % i)
		t.between(b.energy, 70.0, 100.0, "founder %d start energy" % i)
		t.between(b.wait_h, 0.0, 2.0, "founder %d initial wait_h" % i)
		t.eq(b.state, "idle", "founders start idle")
		t.check(b.name.length() > 3 and "-" in b.name, "name %s has the syllable-number shape" % b.name)
		var num := int(b.name.split("-")[1])
		t.between(num, 1, 99, "name number 1..99")
		roles[b.role] = int(roles.get(b.role, 0)) + 1
	t.eq(roles.get("builder", 0), 3, "3 builders")
	t.eq(roles.get("social", 0), 2, "2 social")
	t.eq(roles.get("curious", 0), 1, "1 curious")
	t.eq(roles.get("tender", 0), 1, "1 tender")
	var homes := {}
	for b in w.beings:
		var k: String = w.buildings.get_building(b.building_id).kind
		homes[k] = int(homes.get(k, 0)) + 1
	t.eq(homes, {"habitat": 4, "reactor": 2, "workshop": 1}, "4 in the habitat, 2 in the reactor, 1 in the workshop")
	t.eq(w.log[0].kind, "founders_landed", "the log starts with founders_landed")
	var distinct := {}
	for b in w.beings:
		distinct[b.name] = true
	t.check(distinct.size() >= 6, "names are not all the same")


func test_founder_role_retry_over_200_seeds(t) -> void:
	var layout: Array = SimData.beings().founders.layout
	var bad_age := 0
	for seed_in in range(1, 201):
		var w := SimWorld.new(seed_in)
		t.eq(int(w.stats.founder_role_miss), 0, "seed %d: no exhausted retry" % seed_in)
		t.eq(w.beings.size(), 7, "seed %d: 7 founders" % seed_in)
		for i in w.beings.size():
			var b: Being = w.beings[i]
			if b.role != layout[i].role or w.founders[i].persona.role != layout[i].role:
				t.check(false, "seed %d founder %d role %s, layout wants %s" % [seed_in, i, b.role, layout[i].role])
			var age: float = (w.clock.start_hour - float(w.founders[i].born)) / w.clock.earth_year_h
			if age < 24.0 - 1e-9 or age > 45.0 + 1e-9:
				bad_age += 1
			# the kept founder is internally consistent: chart -> persona
			if b.persona != w.persona.persona_from(w.founders[i].chart):
				t.check(false, "seed %d founder %d persona does not match its chart" % [seed_in, i])
	t.eq(bad_age, 0, "every founder age stays in 24..45 across 1,400 founders")
	t.check(true, "200 seeds checked")


func test_founder_zero_is_the_first_matching_draw_of_the_seed(t) -> void:
	# Founder 0 is a builder; the first draws of the world rng are its founder_birth redraws (spec 10.2:
	# layout needs no draws, founders come before sites). Replaying the stream finds the same birth.
	var layout: Array = SimData.beings().founders.layout
	for seed_in in [42, 7, 99]:
		var w := SimWorld.new(seed_in)
		var rng := SimRng.new(seed_in)
		var clock := Clock.new()
		var sky := MarsSky.new(clock)
		var per := Persona.new()
		var cfg: Dictionary = SimData.persona().founders
		var birth := {}
		var tries := 0
		while tries < 300:
			birth = sky.founder_birth(rng, cfg)
			tries += 1
			if per.persona_from(birth.chart).role == layout[0].role:
				break
		t.near(float(w.founders[0].born), float(birth.born), 1e-9, "seed %d: founder 0 born after %d draw(s)" % [seed_in, tries])
		t.near(float(w.founders[0].lon), float(birth.lon), 1e-9, "seed %d: founder 0 longitude" % seed_in)


func test_founders_equal_for_equal_seeds(t) -> void:
	var a := SimWorld.new(42)
	var b := SimWorld.new(42)
	var c := SimWorld.new(43)
	var differs := false
	if a.beings.size() != 7 or c.beings.size() != 7:
		t.check(false, "founder worlds hold 7 beings (%d and %d)" % [a.beings.size(), c.beings.size()])
		return
	for i in 7:
		t.eq(a.founders[i].persona, b.founders[i].persona, "same seed, founder %d persona" % i)
		t.eq(a.beings[i].name, b.beings[i].name, "same seed, founder %d name" % i)
		t.eq(a.beings[i].energy, b.beings[i].energy, "same seed, founder %d energy" % i)
		if a.beings[i].name != c.beings[i].name:
			differs = true
	t.check(differs, "seed 43 gives other founders")


# ---------------------------------------------------------------- 5-sol run with no EVA

## Founders world with mining forced off (mine_attempt.chance 0) and no regolith so no site is ever started.
## Returns the world after 5 sols; fills `info` with the per-step observations.
func _five_sols(t, seed_in: int, info: Dictionary) -> SimWorld:
	var res: Dictionary = SimData.resources()
	var old_chance: Variant = res.mine_attempt.chance
	res.mine_attempt.chance = 0.0
	var w := SimWorld.new(seed_in)
	w.colony.regolith = 0.0
	var steps := int(ceil(5.0 * SOL_H / DT))
	var outside := 0
	var min_pop := 99
	for i in steps:
		w.step()
		min_pop = mini(min_pop, w.beings.size())
		for b in w.beings:
			if b.state == "eva" or b.state == "mining" or b.state == "work":
				outside += 1
	res.mine_attempt.chance = old_chance
	info["outside"] = outside
	info["min_pop"] = min_pop
	info["steps"] = steps
	return w


func test_five_sol_run_without_eva_keeps_everyone_alive_and_asleep_about_a_tenth(t) -> void:
	for seed_in in [42, 7, 99]:
		var info := {}
		var w := _five_sols(t, seed_in, info)
		var steps: int = info.steps
		t.eq(w.beings.size(), 7, "seed %d: all 7 alive after 5 sols" % seed_in)
		t.eq(int(info.min_pop), 7, "seed %d: nobody died at any step" % seed_in)
		t.eq(int(w.stats.deaths_list.size()), 0, "seed %d: no deaths recorded" % seed_in)
		t.eq(int(info.outside), 0, "seed %d: nobody was ever outside (no eva, mining or work)" % seed_in)
		t.eq(int(w.stats.being_steps), 7 * steps, "seed %d: being_steps = 7 x %d" % [seed_in, steps])
		var share := float(w.stats.asleep_being_steps) / float(w.stats.being_steps)
		var avg := float(w.stats.energy_sum) / float(w.stats.being_steps)
		print("    seed %d, 5 sols (%d steps): asleep share %.3f, average energy %.1f, max_sleep_h %.2f" % [seed_in, steps, share, avg, float(w.stats.max_sleep_h)])
		t.between(share, 0.06, 0.20, "seed %d: asleep share inside the spec's 6..20%% band" % seed_in)
		t.between(avg, 40.0, 90.0, "seed %d: average energy inside the balance band 40..90" % seed_in)
		t.check(float(w.stats.max_sleep_h) < 18.0, "seed %d: no sleep longer than 18 h" % seed_in)
		t.check(float(w.stats.max_sleep_h) > 2.0, "seed %d: somebody did sleep (max_sleep_h %.2f)" % [seed_in, float(w.stats.max_sleep_h)])


# ---------------------------------------------------------------- determinism

func _beings_signature(w: SimWorld) -> String:
	var parts: Array = []
	for b in w.beings:
		parts.append("%d:%s:%s:%d:%.9f:%.9f:%s:%s:%.9f" % [b.id, b.name, b.state, b.building_id, b.energy, b.wait_h,
				str(b.sleep_intent), str(b.corridor_id), b.transit_t])
	parts.append("being_steps=%d asleep=%d esum=%.6f maxsleep=%.6f" % [int(w.stats.being_steps),
			int(w.stats.asleep_being_steps), float(w.stats.energy_sum), float(w.stats.max_sleep_h)])
	parts.append("log=%d t=%.9f next=%.12f" % [w.log.size(), w.t, w.rng.randf()])
	return "|".join(parts)


func test_seeded_determinism_of_beings(t) -> void:
	var a := SimWorld.new(42)
	var b := SimWorld.new(42)
	var c := SimWorld.new(43)
	_run(a, 2000)
	_run(b, 2000)
	_run(c, 2000)
	var sa := _beings_signature(a)
	t.eq(sa, _beings_signature(b), "two seed-42 worlds agree after 2,000 steps (100 h)")
	t.check(sa != _beings_signature(c), "seed 43 differs")
	t.check(int(a.stats.asleep_being_steps) > 0, "the run included sleeping (so the signature means something)")
	t.eq(a.beings.size(), 7, "the signature covers all 7 beings")
