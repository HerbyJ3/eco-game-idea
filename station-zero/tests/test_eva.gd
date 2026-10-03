extends RefCounted
## Task 1, step 8: suits, EVA, mining and footprints. Spec: docs/specs/life-support-power.md sections 3 (comparators),
## 4 (Being, Resources), 5 (phase 6 order, phase 11), 6.1 (exhausted turn-back), 6.3 (update order, air tick),
## 6.4 (decide branches 3 and 4), 6.5 and 6.5b (suit-up, EVA arrival rows mine and haul), 8.2 (choose_site), 8.3 (mining),
## 8.5 (suits, turn-back, trip filter, footprints, target 7), 13 (target 7), 16 (stats), the "Implementation notes" of steps
## 4 to 7 (esp. step 7: the suit is kept until entering) and the step 8 test lists ("Tests (tests/test_suits.gd,
## tests/test_layout.gd)", the EVA arrival table of tests/test_beings.gd). Births are step 9 and are not covered here.
##
## Already covered elsewhere and NOT repeated: trip_time numbers (196/r16 fails, 170/r24 passes), the spawn invariant,
## launch_for ties and scouting (tests/test_layout.gd); the builder suit-up, work, the work drain and the builder suit_kind
## (tests/test_construction.gd). Here the same ideas are tested for miners, and the air/exhaustion rules for both.
##
## Existing API used (steps 1..7): SimWorld.new(seed, {"blank": true}), add_building / add_being / set_offline, step(),
##  take_ice(field, amount), start_site(kind, spot), t, rng (and rng._rng.state for draw replays), clock, colony (oxygen,
##  ice, regolith, o2_net(), o2_cap(), pop(), ice_target(), regolith_target()), buildings (add, add_attached, get_building,
##  next_hop, site, last_short_t, door()), resources (add_ice_field, add_pit, ice_fields, pits, launch_for, trip_time),
##  stats (mining_trips, turn_backs_air, turn_backs_exhausted, ice_dry, deaths, deaths_list), log, Being fields (state,
##  after, mine, mine_intent, suit_up, job, air_h, x, y, heading, path, returning, load, work_left_h, wait_h, step_acc_px,
##  foot_side, wander_target, corridor_id, energy, persona), Being.decide(w), Being.enter(w, id), Being.suit_kind().
##
## API ASSUMED beyond the existing one (the simplest extension; the header of each test names what it needs):
##  - Being.lamp_on(w: SimWorld) -> bool: true when the being is outside (state eva, work or mining) and the Mars hour
##    at w.t is in [21.5, 5.5). It needs the world for the clock, so it takes `w` as Being.is_night does.
##  - SimWorld.choose_site() -> Resources.Site or null (spec 8.2; the plan puts it in Resources, but it reads the colony
##    stocks and the rng, which Resources does not hold, so it sits on SimWorld next to choose_kind). One rng.chance only
##    when ice >= 30 and live ice fields exist, then one rng.pick of the pool.
##  - Resources.footprints: Array, oldest first, newest last. Each print is an Object or a Dictionary with x, y, heading,
##    t, heavy (read with .get("x") etc., so either works). A print is added by the being that moved; the cap (2,200) and
##    the expiry (older than fade_sols x sol_h + STEP_EPS, in phase 11) are enforced by the sim.
##  - Being.mine is a Dictionary {site, door (Vector2), home_id}; Being.mine_intent is the Resources.Site (or null).
##    Both are read as in spec section 4. The kind of a site (ice or pit) is not stored by tests; a hauler whose field
##    dried up must still deposit into ice (spec 8.3 "A miner already there keeps going home with its load").
##  - Turn-back (spec 6.1, 8.5): sets returning = true, state eva; the path is [mine.door] for a miner (after "haul" or
##    "enter", the test accepts both, but mine must be null once the being is home) and [p1 of the site corridor] for a
##    builder (after "enter"); the path never contains p2. Stats: turn_backs_air for "low air" (one log line
##    "suit_low_air" with being_id), turn_backs_exhausted for "exhausted".
##  - Phase order inside one being update (spec 6.3): drain, exhausted check, air tick (air_h -= dt, then death at <= 0),
##    low-air check against the distance at the START of the step, then the state arm. All thresholds below are read AFTER
##    this step's air decrement and drain, as with every other energy read (steps 6 and 7).
##
## Spec facts the numbers rest on, and three departures from the spec's example inputs:
##  - Energy and air are compared after this step's change. Exhausted: input 12.1 in `work` (drain 0.15) reads 11.95; in
##    `mining` (drain 0.13) input 12.1 reads 11.97, input 12.14 reads 12.01; in `eva` (drain 0.1) input 12.05 reads
##    11.95. Air: a miner 160 px from the door turns back when the air after the decrement is < 12.5, so input 12.6
##    (reads 12.55) holds and input 12.54 (reads 12.49) turns back.
##  - The suit-up step leaves air_h at exactly 36 (the air tick runs before the state arm, and the being was inside when
##    the tick ran). The first EVA step then only pops the door waypoint (d < 0.8), so the first move is the third step.
##  - lamp_on at the Mars hours 21.5 and 5.5 cannot be tested exactly: t = (k + 21.5/24) x sol_h gives a clock hour of
##    21.49999999999 or 21.5 depending on k. The tests use 21.5 + 1e-6 (on) and 5.5 + 1e-6 (off) and 21.5 - 1e-6 (off),
##    5.5 - 1e-6 (on) instead, plus the spec's 23, 2, 5.4, 12, 21.4.
##  - The mining yield test uses the ratio of two runs with the same seed (energy 60.13 vs 80.13, drive 0 vs 1) as well as
##    the spec's bands, so it does not depend on which draw comes first in the step.
##  - Draw order the tests replay (all stated in the spec): decide's first draw, when sleep, join and resume do not apply,
##    is the mining chance (rng.chance, u < p); a resumed intent or a hop then draws only the door walk time U(10,56);
##    the wander draws wait, angle, radius in that order; choose_site draws the chance only when ice >= 30 and live ice
##    fields exist, then one pick; the gates "sites exist, no mine, oxygen > 10" draw nothing when they fail.
##  - Mining wander checks the distance to the target BEFORE it moves (prototype L646, as the work wander does), so a
##    target 0.7 px away is walked to, not reached, and the reach is `resources.mining.reach_px` (0.6), not the 0.8 of a
##    waypoint. An implementation that moves first would reach that target on step 1 and fail the reach test.
##  - Not asserted (open in the spec): who is "heavy" on a builder's walk home (job is already null, the suit is still
##    construction); whether a partial load removes ice from the field; the low-air log repeat (3 h) because returning
##    blocks a second turn-back; the heading at the suit-up step.
##
## Layout of the hand-made world (_world): reactor R (id 1, tile 0,0, 12x10, door (48,80)), a parked reactor (id 2, far
## away, supply 28 so nothing shorts), habitat A (id 3, right of R, door (204,80)), workshop W (id 4, below R, door (48,200)).
## Ice field F at (140,150), r 20: distance to the A door 94.8, to the W door 104.7, to the R door 115.6 (nearest A, then W,
## then R), trip time 2 x (94.8 + 20) / 16 + 6 = 20.3. Site world (_swork): R, parked reactor, workshop; habitat site right
## of R (rect (17,1,10,8), centre (176,40), corridor p1 (96,44) p2 (136,44)).

const DT := 0.05
const SOL_H := 24.6597
const R_DOOR := Vector2(48.0, 80.0)
const A_DOOR := Vector2(204.0, 80.0)
const W_DOOR := Vector2(48.0, 200.0)
const SPOT := {"parent_id": 1, "dir": "r", "tw": 10, "th": 8, "gap": 5}
const FAR := 6000.0


# ---------------------------------------------------------------- helpers

func _world(seed_in: int = 1) -> Dictionary:
	var w := SimWorld.new(seed_in, {"blank": true})
	var r := w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	w.add_building("reactor", 300, 300)
	var a := w.buildings.add_attached("habitat", r.id, "r", 13, 9, 7)
	var wk := w.buildings.add_attached("workshop", r.id, "d", 12, 9, 6)
	return {"w": w, "R": r.id, "A": a.id, "W": wk.id}


## R and the parked reactor only: the nearest online door of anything is the R door.
func _lone(seed_in: int = 1) -> Dictionary:
	var w := SimWorld.new(seed_in, {"blank": true})
	var r := w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	w.add_building("reactor", 300, 300)
	return {"w": w, "R": r.id}


## R, parked reactor, workshop and a habitat site with plenty of regolith.
func _swork(seed_in: int = 1) -> Dictionary:
	var w := SimWorld.new(seed_in, {"blank": true})
	var r := w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	w.add_building("reactor", 300, 300)
	var wk := w.buildings.add_attached("workshop", r.id, "d", 12, 9, 6)
	w.colony.regolith = 500.0
	w.start_site("habitat", SPOT)
	return {"w": w, "R": r.id, "Wk": wk.id, "site": w.buildings.site}


## Fails one check per missing piece of the assumed API (so the test stops cleanly instead of crashing).
## `needs` is any of "site" (choose_site), "fp" (Resources.footprints), "lamp" (Being.lamp_on).
func _api(t, w: SimWorld, needs: Array) -> bool:
	var ok := true
	if "site" in needs and not w.has_method("choose_site"):
		t.check(false, "missing SimWorld.choose_site()")
		ok = false
	if "fp" in needs and not (w.resources.get("footprints") is Array):
		t.check(false, "missing Resources.footprints (Array)")
		ok = false
	if "lamp" in needs and not Being.new().has_method("lamp_on"):
		t.check(false, "missing Being.lamp_on(w)")
		ok = false
	return ok


func _traits(b: Being, traits: Dictionary) -> void:
	for k in traits:
		b.persona.traits[k] = traits[k]


func _logs(w: SimWorld, kind: String) -> int:
	var n := 0
	for e in w.log:
		if e.kind == kind:
			n += 1
	return n


func _f(v: Variant) -> float:
	return float(v) if (v is float or v is int) else -999.0


func _i(v: Variant) -> int:
	return int(v) if (v is int or v is float) else -1


func _pts(b: Being) -> Array:
	return b.path if b.path is Array else []


func _fps(w: SimWorld) -> Array:
	var v: Variant = w.resources.get("footprints")
	return v if v is Array else []


func _g(p: Variant, key: String) -> Variant:
	return p.get(key)


func _pos(b: Being) -> Vector2:
	return Vector2(_f(b.x), _f(b.y))


func _run(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()


func _rng_state(w: SimWorld) -> int:
	return w.rng._rng.state


## A SimRng that continues exactly where `state` left the world rng.
func _replay(state: int) -> SimRng:
	var r := SimRng.new(0)
	r._rng.state = state
	return r


## Sets the world clock so that the Mars hour AFTER the next step is `hour`.
func _hour(w: SimWorld, hour: float) -> void:
	var k := floorf(w.t / SOL_H) + 1.0
	w.t = (k + hour / 24.0) * SOL_H - DT
	w.buildings.now = w.t


## Sets the world clock so that the Mars hour right now is `hour` (no step).
func _hour_now(w: SimWorld, hour: float) -> void:
	var k := floorf(w.t / SOL_H) + 1.0
	w.t = (k + hour / 24.0) * SOL_H
	w.buildings.now = w.t


## Oxygen after the stocks phase of the next step (before any suit fill).
func _o2_next(w: SimWorld) -> float:
	return clampf(w.colony.oxygen + w.colony.o2_net() * DT, 0.0, w.colony.o2_cap())


func _frac(f: Resources.Site, p: Vector2) -> float:
	return sqrt(pow(p.x - f.x, 2.0) + pow((p.y - f.y) / 0.7, 2.0)) / f.r


## A miner standing outside at `pos` in `st` (default mining), pausing (wait_h 1000), tank `air`, home R.
func _miner(w: SimWorld, home: int, f: Resources.Site, pos: Vector2, st: String = "mining", air: float = 36.0,
		energy: float = 100.0, door: Vector2 = R_DOOR) -> Being:
	var b := w.add_being(home, "social")
	b.energy = energy
	b.wait_h = 1000.0
	b.state = st
	b.after = "mine"
	b.mine = {"site": f, "door": door, "home_id": home}
	b.air_h = air
	b.x = pos.x
	b.y = pos.y
	b.heading = 0.0
	b.work_left_h = 1000.0
	b.wander_target = pos
	b.path = null
	return b


## A being inside R at the end of its walk to the door with the suit-up flag set: the next step suits it up.
func _at_door(w: SimWorld, home: int, f: Resources.Site, role: String = "social") -> Being:
	var b := w.add_being(home, role)
	b.energy = 100.0
	b.state = "to_door"
	b.suit_up = true
	b.wait_h = 0.0
	b.mine = {"site": f, "door": R_DOOR, "home_id": home}
	return b


## A being outside walking (state eva) on a far straight path; after "enter" so no turn-back can fire.
func _walker(w: SimWorld, home: int, pos: Vector2, dir: Vector2 = Vector2.RIGHT) -> Being:
	var b := w.add_being(home, "social")
	b.energy = 100.0
	b.wait_h = 1000.0
	b.state = "eva"
	b.after = "enter"
	b.returning = true
	b.air_h = 1000.0
	b.x = pos.x
	b.y = pos.y
	b.heading = dir.angle()
	b.path = [pos + dir * FAR]
	return b


## A builder at work on the site, wander target far to the right of the site (the site is 80 px wide, so the target
## stays inside it), standing at the left edge.
func _builder_at_work(w: SimWorld, site: Variant, energy: float = 100.0, air: float = 1000.0) -> Being:
	var b := w.add_being(int(site.parent_id), "builder")
	b.energy = energy
	b.wait_h = 0.0
	b.state = "work"
	b.after = "work"
	b.job = site
	b.construction_suit = true
	b.air_h = air
	b.x = 141.0
	b.y = 40.0
	b.heading = 0.0
	b.work_left_h = 1000.0
	b.wander_target = Vector2(211.0, 40.0)
	b.path = null
	return b


## The tunnel corridor end p1 of the site and the site centre, for the builder tests.
func _sb(w: SimWorld) -> Buildings.Building:
	return w.buildings.get_building(int(w.buildings.site.building_id))


# ---------------------------------------------------------------- suit-up of a miner (spec 6.5, 8.5)

func test_miner_suit_up_costs_one_oxygen_sets_36_h_and_starts_the_walk(t) -> void:
	var h := _world(11)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var b := _at_door(w, int(h.R), f)
	w.colony.oxygen = 100.0
	var o2 := _o2_next(w)
	var trips0: int = int(w.stats.mining_trips)
	w.step()
	t.eq(b.state, "eva", "suited up: state eva")
	t.eq(b.after, "mine", "after = mine")
	t.near(w.colony.oxygen, o2 - 1.0, 1e-9, "one colony oxygen for the fill (suits.fill_colony_o2)")
	t.near(_f(b.air_h), 36.0, 1e-9, "the tank holds 36 h (no air tick on the suit-up step)")
	t.check(not b.suit_up, "suit_up cleared")
	t.check(b.mine_intent == null, "mine_intent stays null")
	t.eq(int(w.stats.mining_trips), trips0 + 1, "mining_trips counted at suit-up")
	t.near(_pos(b).distance_to(R_DOOR), 0.0, 1e-9, "the miner stands at the door of the launch building")
	t.eq(b.suit_kind(), "eva", "a miner wears the eva suit")
	var pts := _pts(b)
	t.eq(pts.size(), 2, "path = [door, arrival point]")
	if pts.size() == 2:
		t.near((pts[0] as Vector2).distance_to(R_DOOR), 0.0, 1e-9, "first waypoint = the door")
		var arrive: Vector2 = pts[1]
		var fr := _frac(f, arrive)
		t.between(fr, 0.3 - 1e-6, 0.8 + 1e-6, "arrival point inside the field, 0.3..0.8 of the radius (y scaled 0.7)")
		# Step 2 only pops the door waypoint (d < 0.8); step 3 moves 0.8 px toward the arrival point.
		_run(w, 2)
		t.near(_f(b.heading), (arrive - R_DOOR).angle(), 1e-5, "heading toward the arrival point")
		t.near(_pos(b).distance_to(R_DOOR), 0.8, 1e-3, "one EVA step is 16 px/h x 0.05 h = 0.8 px")
		t.near(_f(b.air_h), 36.0 - 0.1, 1e-9, "air falls 0.05 per step from the second step on")


func test_suit_up_at_oxygen_below_one_clamps_to_zero_and_the_tank_is_still_full(t) -> void:
	var h := _world(12)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var b := _at_door(w, int(h.R), f)
	w.colony.oxygen = 0.4
	w.step()
	t.near(w.colony.oxygen, 0.0, 1e-12, "oxygen 0.4 clamps to 0, never negative")
	t.near(_f(b.air_h), 36.0, 1e-9, "the tank is still 36 h")
	t.eq(b.state, "eva", "suited up anyway")
	var h2 := _world(13)
	var w2: SimWorld = h2.w
	var f2 := w2.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var b2 := _at_door(w2, int(h2.R), f2)
	w2.colony.oxygen = 0.0
	w2.step()
	t.near(w2.colony.oxygen, 0.0, 1e-12, "oxygen 0 stays 0")
	t.near(_f(b2.air_h), 36.0, 1e-9, "a fill at oxygen 0 still gives a full tank")


func test_arrival_point_is_inside_the_field_over_100_seeds(t) -> void:
	var lo := 9.0
	var hi := 0.0
	for s in 100:
		var h := _world(1000 + s)
		var w: SimWorld = h.w
		var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
		var b := _at_door(w, int(h.R), f)
		w.step()
		var pts := _pts(b)
		if pts.size() != 2:
			t.check(false, "seed %d: path [door, arrival]" % s)
			return
		var fr := _frac(f, pts[1])
		lo = minf(lo, fr)
		hi = maxf(hi, fr)
	t.between(lo, 0.3 - 1e-6, 0.36, "smallest radius fraction near 0.3")
	t.between(hi, 0.74, 0.8 + 1e-6, "largest radius fraction near 0.8")


# ---------------------------------------------------------------- air ticks outside only; suffocation

func test_air_falls_one_hour_per_hour_outside_and_never_inside(t) -> void:
	var h := _world(21)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var walker := _walker(w, int(h.R), Vector2(100.0, 100.0))
	walker.air_h = 36.0
	var miner := _miner(w, int(h.R), f, Vector2(140.0, 150.0))
	var hauler := _miner(w, int(h.R), f, Vector2(100.0, 300.0), "eva")
	hauler.after = "haul"
	hauler.load = 5.0
	hauler.path = [Vector2(100.0 + FAR, 300.0)]
	var inside := w.add_being(int(h.R), "social")
	inside.energy = 100.0
	inside.wait_h = 1000.0
	var tunnel := w.add_being(int(h.R), "social")
	tunnel.energy = 100.0
	tunnel.state = "transit"
	tunnel.corridor_id = int(h.A)
	tunnel.from_a = true
	tunnel.transit_t = 0.0
	_run(w, 20)
	t.near(_f(walker.air_h), 35.0, 1e-9, "walking out: 1 h of air per hour")
	t.near(_f(miner.air_h), 35.0, 1e-9, "mining: 1 h of air per hour")
	t.near(_f(hauler.air_h), 35.0, 1e-9, "hauling: 1 h of air per hour")
	t.check(inside.air_h == null, "inside: no air_h")
	t.check(tunnel.air_h == null and tunnel.state == "transit", "a tunnel walk is inside: no air_h")


func test_builder_air_also_falls_while_working(t) -> void:
	var h := _swork(22)
	var w: SimWorld = h.w
	var b := _builder_at_work(w, h.site, 100.0, 36.0)
	_run(w, 20)
	t.eq(b.state, "work", "still working")
	t.near(_f(b.air_h), 35.0, 1e-9, "working: 1 h of air per hour")


func test_a_being_at_zero_air_outside_dies_suffocated(t) -> void:
	var h := _world(23)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var dying := _miner(w, int(h.R), f, Vector2(140.0, 150.0), "eva", 0.04)
	dying.after = "haul"
	dying.load = 6.0
	dying.path = [Vector2(2000.0, 150.0)]
	var other := _miner(w, int(h.R), f, Vector2(100.0, 300.0), "mining", 5.0)
	var bystander := w.add_being(int(h.R), "social")
	bystander.energy = 100.0
	bystander.wait_h = 1000.0
	var ice0: float = w.colony.ice
	var amount0: float = f.amount
	var pop0: int = w.colony.pop()
	w.step()
	t.check(not w.beings.has(dying), "the being is removed at once")
	t.eq(w.colony.pop(), pop0 - 1, "population dropped by one")
	t.eq(int(w.stats.deaths.suffocated_outside), 1, "stats.deaths.suffocated_outside")
	t.eq(int(w.stats.deaths.other), 0, "nothing in other")
	t.eq(w.stats.deaths_list.size(), 1, "one entry in deaths_list")
	if w.stats.deaths_list.size() == 1:
		var d: Dictionary = w.stats.deaths_list[0]
		t.eq(d.cause, "suffocated outside", "cause")
		t.eq(int(d.being_id), dying.id, "being_id")
	t.eq(_logs(w, "died"), 1, "one died line in the log")
	t.near(_f(other.air_h), 5.0 - DT, 1e-9, "the next id was still updated this step")
	t.check(w.beings.has(other) and w.beings.has(bystander), "nobody else died")
	# `other` is far from its door with 5 h of air, so it turns back and its partial load leaves the
	# field (step 8 decision); the dead hauler takes nothing.
	t.near(f.amount, amount0 - other.load, 1e-12, "the field only lost the survivor's partial load")
	# The load of a dead hauler is lost: ice only falls by the usual drain.
	t.near(w.colony.ice, ice0 - w.colony.pop() * 0.0 - 3.0 * 0.01 * DT, 2e-3, "the load is lost (no ice gained)")


func test_zero_air_exactly_and_the_step_before(t) -> void:
	var h := _world(24)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var exact := _miner(w, int(h.R), f, Vector2(140.0, 150.0), "mining", 0.05)
	var later := _miner(w, int(h.R), f, Vector2(140.0, 150.0), "mining", 0.06)
	w.step()
	t.check(not w.beings.has(exact), "air 0.05 reads 0.0 and dies (air_h <= 0)")
	t.eq(int(w.stats.turn_backs_air), 1, "only the survivor (0.01 left) turns back; the dead one does not")
	t.check(w.beings.has(later), "air 0.06 reads 0.01 and lives one more step")
	w.step()
	t.check(not w.beings.has(later), "and dies on the next step")
	t.eq(int(w.stats.deaths.suffocated_outside), 2, "two suffocated outside")


# ---------------------------------------------------------------- air turn-back (spec 6.3 item 4, 8.5)

## A miner mining 160 px from its door with `air` in the tank; one step.
func _mining_turn(air: float, seed_in: int = 30) -> Dictionary:
	var h := _world(seed_in)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(208.0, 80.0, 300.0, 20.0)
	var b := _miner(w, int(h.R), f, Vector2(208.0, 80.0), "mining", air)
	w.step()
	return {"w": w, "b": b, "f": f, "h": h}


func test_turn_back_when_air_is_below_distance_over_16_plus_2_5(t) -> void:
	var hold: Dictionary = _mining_turn(12.6)
	t.check(not hold.b.returning, "air 12.6 (reads 12.55, threshold 12.5): no turn-back")
	t.eq(hold.b.state, "mining", "still mining")
	t.eq(int(hold.w.stats.turn_backs_air), 0, "no turn-back counted")
	var go: Dictionary = _mining_turn(12.54)
	var b: Being = go.b
	t.check(b.returning, "air 12.54 (reads 12.49 < 12.5): turn-back")
	t.eq(b.state, "eva", "walking home")
	t.eq(int(go.w.stats.turn_backs_air), 1, "turn_backs_air counted once")
	t.eq(int(go.w.stats.turn_backs_exhausted), 0, "not an exhausted turn-back")
	t.eq(_logs(go.w, "suit_low_air"), 1, "one suit_low_air line")
	var pts := _pts(b)
	t.check(pts.size() >= 1 and (pts[0] as Vector2).distance_to(R_DOOR) < 1e-9, "the path goes to the mine door")
	t.check(b.after == "haul" or b.after == "enter", "after = haul or enter")
	t.eq(b.suit_kind(), "eva", "still the eva suit")


func test_turn_back_while_walking_out_sets_no_load_and_the_walk_home_keeps_2_5_hours(t) -> void:
	var h := _world(31)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(208.0, 80.0, 300.0, 20.0)
	var b := _miner(w, int(h.R), f, Vector2(208.0, 80.0), "eva", 12.54)
	b.path = [Vector2(300.0, 80.0)]
	var ice0: float = w.colony.ice
	var reg0: float = w.colony.regolith
	w.step()
	t.check(b.returning, "air 12.54 at 160 px while walking out: turn-back")
	t.near(b.load, 0.0, 1e-12, "a turn-back while still walking out sets no load")
	var last_air := _f(b.air_h)
	var steps := 0
	while b.state == "eva" and steps < 400:
		b.energy = 100.0
		last_air = _f(b.air_h)
		w.step()
		steps += 1
	t.eq(b.state, "idle", "home again")
	t.eq(b.building_id, int(h.R), "in the home building")
	t.check(b.air_h == null and b.path == null and not b.returning, "suit off, path and returning reset")
	t.check(b.mine == null, "mine cleared once home")
	t.between(float(steps) * DT, 9.9, 10.2, "160 px at 16 px/h is 10 h")
	t.between(last_air - DT, 2.35, 2.55, "arrives with about 2.5 h left (never less than the margin minus a step)")
	t.near(w.colony.ice, ice0 - w.colony.pop() * 0.01 * DT * (steps + 1), 1e-9, "no ice gained")
	t.near(w.colony.regolith, reg0, 1e-9, "no regolith gained")
	t.eq(int(w.stats.turn_backs_air), 1, "counted once, not again while returning")
	t.eq(_logs(w, "suit_low_air"), 1, "logged once")


func test_no_second_turn_back_while_returning(t) -> void:
	var go: Dictionary = _mining_turn(12.54, 32)
	var w: SimWorld = go.w
	var b: Being = go.b
	for i in 120:
		b.energy = 100.0
		w.step()
	t.check(b.returning, "still returning")
	t.eq(int(w.stats.turn_backs_air), 1, "still one turn-back after 120 steps of low air")
	t.eq(_logs(w, "suit_low_air"), 1, "still one log line")


func test_eva_with_after_haul_or_enter_never_turns_back(t) -> void:
	var h := _world(33)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(208.0, 80.0, 300.0, 20.0)
	var hauler := _miner(w, int(h.R), f, Vector2(208.0, 80.0), "eva", 5.0, 5.0)
	hauler.after = "haul"
	hauler.path = [Vector2(48.0 + 3000.0, 80.0)]
	var homeward := _miner(w, int(h.R), f, Vector2(208.0, 100.0), "eva", 5.0, 5.0)
	homeward.after = "enter"
	homeward.mine = null
	homeward.path = [Vector2(3000.0, 100.0)]
	# Controls: the same low air, and the same low energy, but on the way out (after mine): both do turn back.
	var ctrl_air := _miner(w, int(h.R), f, Vector2(208.0, 60.0), "eva", 5.0, 100.0)
	ctrl_air.path = [Vector2(3000.0, 60.0)]
	var ctrl_exh := _miner(w, int(h.R), f, Vector2(208.0, 100.0), "eva", 36.0, 5.0)
	ctrl_exh.path = [Vector2(3000.0, 100.0)]
	_run(w, 5)
	t.check(not hauler.returning and not homeward.returning, "air 5 at 160 px and energy 5: neither turns back")
	t.check(w.beings.has(hauler) and w.beings.has(homeward), "both alive")
	t.check(ctrl_air.returning, "control: low air on the way out turns back")
	t.check(ctrl_exh.returning, "control: low energy on the way out turns back")
	t.eq(int(w.stats.turn_backs_air), 1, "exactly one air turn-back (the control)")
	t.eq(int(w.stats.turn_backs_exhausted), 1, "exactly one exhausted turn-back (the control)")


func test_a_walking_out_miner_turns_back_before_it_reaches_the_field(t) -> void:
	# State eva with after = mine is covered by the turn-back rule; the distance is taken at the start of the step.
	var h := _world(34)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(208.0, 80.0, 300.0, 20.0)
	var b := _miner(w, int(h.R), f, Vector2(48.0, 80.0), "eva", 36.0)
	b.path = [Vector2(208.0, 80.0)]
	# 100 px out: the threshold is 100/16 + 2.5 = 8.75. Input 8.79 reads 8.74 (turns back), input 8.9 reads 8.85 (walks on).
	b.x = 148.0
	b.air_h = 8.79
	var b2 := _miner(w, int(h.R), f, Vector2(148.0, 80.0), "eva", 8.9)
	b2.path = [Vector2(208.0, 80.0)]
	w.step()
	t.check(b.returning, "air 8.74 < 100/16 + 2.5 = 8.75: turn-back before reaching the field")
	t.check(not b2.returning, "air 8.85: keeps walking out")
	t.near(b.load, 0.0, 1e-12, "no load")


func test_builder_turn_back_walks_straight_to_p1_not_via_p2(t) -> void:
	var h := _swork(35)
	var w: SimWorld = h.w
	var sb := _sb(w)
	var p1: Vector2 = sb.corridor.p1
	var p2: Vector2 = sb.corridor.p2
	var pos := Vector2(176.0, 40.0)
	var need := pos.distance_to(p1) / 16.0 + 2.5
	var hold := _builder_at_work(w, h.site, 100.0, need + DT + 0.1)
	hold.x = pos.x
	hold.y = pos.y
	hold.wait_h = 1000.0
	var go := _builder_at_work(w, h.site, 100.0, need + DT - 0.01)
	go.x = pos.x
	go.y = pos.y
	go.wait_h = 1000.0
	w.step()
	t.check(not hold.returning and hold.state == "work", "air just above the threshold: keeps working")
	t.check(go.returning, "air just below the threshold: turn-back")
	t.eq(go.state, "eva", "builder walks home")
	t.eq(int(w.stats.turn_backs_air), 1, "counted once")
	var pts := _pts(go)
	t.check(pts.size() >= 1 and (pts[0] as Vector2).distance_to(p1) < 1e-9, "first waypoint is p1")
	var has_p2 := false
	for p in pts:
		if (p as Vector2).distance_to(p2) < 1e-9:
			has_p2 = true
	t.check(not has_p2, "p2 is not on the way home (the prototype went via p2)")
	t.eq(go.after, "enter", "after = enter")
	t.eq(go.suit_kind(), "construction", "the construction suit is kept on the way home")
	var steps := 0
	var kind_ok := true
	while go.state == "eva" and steps < 600:
		go.energy = 100.0
		go.air_h = 100.0
		if go.suit_kind() != "construction":
			kind_ok = false
		w.step()
		steps += 1
	t.check(kind_ok, "construction suit the whole way home")
	t.eq(go.state, "idle", "entered")
	t.eq(go.building_id, int(h.R), "in the parent building")
	t.eq(go.suit_kind(), "none", "inside again: none")


func test_a_builder_walking_out_to_the_site_turns_back_too(t) -> void:
	# State eva with after = work is covered by the rule: p1 is 24 px away, threshold 24/16 + 2.5 = 4.0.
	var h := _swork(36)
	var w: SimWorld = h.w
	var site: Variant = h.site
	var mk := func(air: float) -> Being:
		var b := w.add_being(int(site.parent_id), "builder")
		b.energy = 100.0
		b.wait_h = 1000.0
		b.state = "eva"
		b.after = "work"
		b.job = site
		b.construction_suit = true
		b.air_h = air
		b.x = 120.0
		b.y = 44.0
		b.heading = 0.0
		b.path = [Vector2(176.0, 40.0)]
		return b
	var go: Being = mk.call(4.04)
	var hold: Being = mk.call(4.2)
	w.step()
	t.check(go.returning, "air 3.99 < 4.0 while walking out: turn-back")
	t.check(not hold.returning, "air 4.15: keeps walking out")
	var pts := _pts(go)
	t.check(pts.size() >= 1 and (pts[0] as Vector2).distance_to(_sb(w).corridor.p1) < 1e-9, "straight back to p1")


# ---------------------------------------------------------------- exhausted turn-back (spec 6.1, step 6 author's notes)

func test_exhausted_builder_at_12_1_reads_11_95_and_turns_back_keeping_the_air_ticking(t) -> void:
	var h := _swork(41)
	var w: SimWorld = h.w
	var b := _builder_at_work(w, h.site, 12.1, 30.0)
	b.wait_h = 1000.0
	var o2 := _o2_next(w)
	w.step()
	t.near(b.energy, 11.95, 1e-9, "input 12.1 reads 11.95 after one work step (drain 0.15)")
	t.check(b.returning, "returning is set")
	t.eq(b.state, "eva", "state eva, walking home")
	var pts := _pts(b)
	t.check(pts.size() >= 1 and (pts[0] as Vector2).distance_to(_sb(w).corridor.p1) < 1e-9, "path home starts at p1")
	t.near(_f(b.air_h), 30.0 - DT, 1e-9, "air_h keeps falling 0.05 on the same step")
	t.near(w.colony.oxygen, o2, 1e-9, "no colony oxygen is spent")
	t.eq(int(w.stats.turn_backs_exhausted), 1, "turn_backs_exhausted")
	t.eq(int(w.stats.turn_backs_air), 0, "not an air turn-back")
	w.step()
	t.near(_f(b.air_h), 30.0 - 2.0 * DT, 1e-9, "and again on the next step")
	t.eq(int(w.stats.turn_backs_exhausted), 1, "not counted twice")


func test_exhausted_threshold_is_a_strict_12_after_the_drain(t) -> void:
	var h := _swork(42)
	var w: SimWorld = h.w
	var keep := _builder_at_work(w, h.site, 12.2, 30.0)
	keep.wait_h = 1000.0
	var go := _builder_at_work(w, h.site, 12.1, 30.0)
	go.wait_h = 1000.0
	w.step()
	t.near(keep.energy, 12.05, 1e-9, "12.2 reads 12.05")
	t.check(not keep.returning and keep.state == "work", "12.05 is not below 12: keeps working")
	t.check(go.returning, "11.95 is below 12: turns back")
	# Sleeping or idle beings never take this path; an inside being at 5 energy just sleeps on its own terms.
	var h2 := _world(43)
	var w2: SimWorld = h2.w
	var f := w2.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var m_keep := _miner(w2, int(h2.R), f, Vector2(140.0, 150.0), "mining", 36.0, 12.14)
	var m_go := _miner(w2, int(h2.R), f, Vector2(140.0, 150.0), "mining", 36.0, 12.1)
	var e_go := _miner(w2, int(h2.R), f, Vector2(100.0, 100.0), "eva", 36.0, 12.05)
	e_go.path = [Vector2(3000.0, 100.0)]
	w2.step()
	t.near(m_keep.energy, 12.01, 1e-9, "mining drain 0.13: 12.14 reads 12.01")
	t.check(not m_keep.returning, "12.01 holds")
	t.near(m_go.energy, 11.97, 1e-9, "12.1 reads 11.97")
	t.check(m_go.returning, "mining at 11.97 turns back")
	t.near(e_go.energy, 11.95, 1e-9, "eva drain 0.1: 12.05 reads 11.95")
	t.check(e_go.returning, "eva with after mine at 11.95 turns back")
	t.eq(int(w2.stats.turn_backs_exhausted), 2, "two exhausted turn-backs")
	t.eq(int(w2.stats.turn_backs_air), 0, "no air turn-backs")


func test_a_turn_back_while_mining_carries_a_partial_load_home(t) -> void:
	var lo := 9.0
	var hi := 0.0
	for s in 60:
		var h := _world(2000 + s)
		var w: SimWorld = h.w
		var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
		var b := _miner(w, int(h.R), f, Vector2(100.0, 120.0), "mining", 36.0, 12.1)
		var pit := w.resources.add_pit(60.0, 120.0)
		var c := _miner(w, int(h.R), pit, Vector2(60.0, 120.0), "mining", 36.0, 12.1)
		w.step()
		if not (b.returning and c.returning):
			t.check(false, "seed %d: both turned back" % s)
			return
		lo = minf(lo, minf(b.load, c.load))
		hi = maxf(hi, maxf(b.load, c.load))
	t.between(lo, 2.0, 2.6, "partial load lower end 2")
	t.between(hi, 4.4, 5.0, "partial load upper end 5")
	# The load is deposited at home: ice for a field, regolith for a pit.
	var h := _world(2100)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(100.0, 100.0, 300.0, 20.0)
	var b := _miner(w, int(h.R), f, Vector2(100.0, 100.0), "mining", 36.0, 12.1)
	var ice0: float = w.colony.ice
	w.step()
	var load := b.load
	t.between(load, 2.0, 5.0, "load drawn 2..5")
	var steps := 1
	while b.state == "eva" and steps < 400:
		b.energy = 100.0
		w.step()
		steps += 1
	t.eq(b.state, "idle", "home")
	t.check(b.mine == null and b.load == 0.0, "mine cleared, load handed in")
	t.near(w.colony.ice, ice0 - w.colony.pop() * 0.01 * DT * steps + load, 1e-9, "the partial load went into ice")
	# Limited by what the field has left.
	var h3 := _world(2101)
	var w3: SimWorld = h3.w
	var small := w3.resources.add_ice_field(100.0, 100.0, 1.0, 20.0)
	var b3 := _miner(w3, int(h3.R), small, Vector2(100.0, 100.0), "mining", 36.0, 12.1)
	w3.step()
	t.check(b3.returning and b3.load <= 1.0 + 1e-9 and b3.load >= 0.0, "load never exceeds the ice left (%s)" % str(b3.load))


# ---------------------------------------------------------------- the trip filter at choice time (spec 8.2, 8.5)

func test_choose_site_ignores_sites_beyond_the_trip_filter(t) -> void:
	var h := _world(51)
	var w: SimWorld = h.w
	if not _api(t, w, ["site"]):
		return
	# Nearest online door of both is the R door (48,80). Far: 196 px, r 16 -> 2 x 212 / 16 + 6 = 32.5 (fails).
	# Near: 170 px, r 24 -> 2 x 194 / 16 + 6 = 30.25 (passes).
	var far := w.resources.add_ice_field(48.0 - 196.0, 80.0, 300.0, 16.0)
	var near := w.resources.add_ice_field(48.0, 80.0 - 170.0, 300.0, 24.0)
	# 190 px, r 16: 2 x 206 / 16 + 6 = 31.75, also out (a filter of 0.9 x 36 = 32.4 would let it through).
	var mid := w.resources.add_ice_field(48.0, 80.0 - 190.0, 300.0, 16.0)
	t.near(w.resources.trip_time(mid), 31.75, 1e-9, "mid field trip time")
	t.near(w.resources.trip_time(far), 32.5, 1e-9, "far field trip time")
	t.near(w.resources.trip_time(near), 30.25, 1e-9, "near field trip time")
	w.colony.ice = 10.0
	for i in 100:
		t.check(w.choose_site() == near, "only the field inside the filter is chosen")
	w.resources.ice_fields.erase(near)
	t.check(w.choose_site() == null, "only fields beyond 30.6 left: none")
	# A pit beyond the filter (r 9): 2 x (200 + 9) / 16 + 6 = 32.1.
	var far_pit := w.resources.add_pit(48.0, 80.0 + 200.0 + 400.0)
	t.check(w.resources.trip_time(far_pit) >= 30.6, "that pit is beyond the filter")
	t.check(w.choose_site() == null, "a far pit is not chosen either")
	var ok_pit := w.resources.add_pit(48.0 - 150.0, 80.0 + 0.0)
	t.check(w.resources.trip_time(ok_pit) < 30.6, "a pit at 150 px is inside")
	t.check(w.choose_site() == ok_pit, "the near pit is chosen")


func test_decide_never_launches_a_trip_to_a_field_beyond_the_filter(t) -> void:
	var h := _lone(52)
	var w: SimWorld = h.w
	if not _api(t, w, ["site"]):
		return
	w.resources.add_ice_field(48.0 + 196.0, 80.0, 300.0, 16.0)
	w.colony.ice = 0.0
	w.colony.regolith = 0.0
	var b := w.add_being(int(h.R), "social")
	_traits(b, {"steady": 1.0, "drive": 1.0, "restless": 1.0})
	_hour(w, 12.0)
	w.t += DT
	var made := 0
	for i in 400:
		b.state = "idle"
		b.energy = 90.0
		b.mine = null
		b.mine_intent = null
		b.suit_up = false
		b.decide(w)
		if b.mine != null or b.mine_intent != null:
			made += 1
	t.eq(made, 0, "no mining trip to a 196 px / r16 field in 400 decides")


# ---------------------------------------------------------------- choose_site rules (spec 8.2)

func _cs_world(seed_in: int, ice: float, regolith: float, with_ice: bool = true, with_pit: bool = true) -> Dictionary:
	var h := _world(seed_in)
	var w: SimWorld = h.w
	var f: Resources.Site = null
	var p: Resources.Site = null
	if with_ice:
		f = w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	if with_pit:
		p = w.resources.add_pit(60.0, 140.0)
	w.colony.ice = ice
	w.colony.regolith = regolith
	return {"w": w, "f": f, "p": p, "h": h}


func test_choose_site_wants_ice_below_30_without_drawing_the_chance(t) -> void:
	var c := _cs_world(61, 10.0, 200.0)
	var w: SimWorld = c.w
	if not _api(t, w, ["site"]):
		return
	for i in 200:
		t.check(w.choose_site() == c.f, "ice < 30: always the ice field")
	var c2 := _cs_world(62, 10.0, 200.0)
	var w2: SimWorld = c2.w
	var r2 := _replay(_rng_state(w2))
	var got: Variant = w2.choose_site()
	r2.pick([c2.f])
	t.check(got == c2.f, "chosen")
	t.eq(_rng_state(w2), r2._rng.state, "ice < 30 draws exactly one pick of the pool and no chance")
	# With two live ice fields the pick is a real draw: the result follows the replayed pick exactly.
	var c5 := _cs_world(80, 10.0, 200.0)
	var f2: Resources.Site = c5.w.resources.add_ice_field(100.0, 160.0, 300.0, 20.0)
	var r5 := _replay(_rng_state(c5.w))
	var seen: Dictionary = {}
	for i in 30:
		var expect5: Variant = r5.pick([c5.f, f2])
		var got5: Variant = c5.w.choose_site()
		t.check(got5 == expect5, "two fields: the pick follows the rng (trial %d)" % i)
		seen[got5] = true
	t.eq(seen.size(), 2, "both fields come up over 30 picks")
	t.eq(_rng_state(c5.w), r5._rng.state, "one pick per call")
	# Just under 30 is still urgent (no chance); just over is not (chance, then pick).
	var c3 := _cs_world(76, 29.0, 200.0)
	var r3 := _replay(_rng_state(c3.w))
	r3.pick([c3.f])
	c3.w.choose_site()
	t.eq(_rng_state(c3.w), r3._rng.state, "ice 29: urgent, one pick only")
	var c4 := _cs_world(77, 31.0, 200.0)
	var r4 := _replay(_rng_state(c4.w))
	var ice_need := 1.0 - 31.0 / 120.0
	var reg_need := 1.0 - 200.0 / 208.0
	var want := r4.chance((ice_need + 0.15) / (ice_need + reg_need + 0.3))
	var expect: Variant = r4.pick([c4.f] if want else [c4.p])
	var got4: Variant = c4.w.choose_site()
	t.check(got4 == expect, "ice 31: chance, then pick, as replayed")
	t.eq(_rng_state(c4.w), r4._rng.state, "ice 31 is not urgent: the chance is drawn")


func test_choose_site_ice_probability_follows_the_need_formula(t) -> void:
	# ice 60 of target 120: ice_need 0.5. regolith 0 of 208: reg_need 1 -> (0.5 + 0.15) / (0.5 + 1 + 0.3) = 0.3611.
	var c := _cs_world(63, 60.0, 0.0)
	var w: SimWorld = c.w
	if not _api(t, w, ["site"]):
		return
	var n := 4000
	var ice := 0
	for i in n:
		if w.choose_site() == c.f:
			ice += 1
	t.between(float(ice) / n, 0.3611 - 0.03, 0.3611 + 0.03, "ice share with reg_need 1 (0.361)")
	# regolith 150: reg_need = 1 - 150/208 = 0.2788 -> 0.65 / (0.5 + 0.2788 + 0.3) = 0.6025.
	var c2 := _cs_world(64, 60.0, 150.0)
	var w2: SimWorld = c2.w
	ice = 0
	for i in n:
		if w2.choose_site() == c2.f:
			ice += 1
	t.between(float(ice) / n, 0.6025 - 0.03, 0.6025 + 0.03, "ice share with reg_need 0.279 (0.6025)")


func test_choose_site_draw_order_is_chance_then_pick(t) -> void:
	var c := _cs_world(65, 60.0, 0.0)
	var w: SimWorld = c.w
	if not _api(t, w, ["site"]):
		return
	for i in 20:
		var s0 := _rng_state(w)
		var r2 := _replay(s0)
		var want := r2.chance((0.5 + 0.15) / (0.5 + 1.0 + 0.3))
		var pool: Array = [c.f] if want else [c.p]
		var expect: Variant = r2.pick(pool)
		var got: Variant = w.choose_site()
		t.check(got == expect, "same site as the replayed chance + pick")
		t.eq(_rng_state(w), r2._rng.state, "exactly those two draws")
	# No ice fields: no chance, one pick.
	var c2 := _cs_world(66, 60.0, 0.0, false, true)
	var w2: SimWorld = c2.w
	var r3 := _replay(_rng_state(w2))
	r3.pick([c2.p])
	t.check(w2.choose_site() == c2.p, "only a pit: the pit")
	t.eq(_rng_state(w2), r3._rng.state, "no chance is drawn without ice fields")


func test_choose_site_pool_fallbacks_and_empty(t) -> void:
	var c := _cs_world(67, 60.0, 0.0, true, false)
	var w: SimWorld = c.w
	if not _api(t, w, ["site"]):
		return
	for i in 50:
		t.check(w.choose_site() == c.f, "no pits: the ice field whatever the chance says")
	var none := _cs_world(68, 60.0, 0.0, false, false)
	t.check(none.w.choose_site() == null, "nothing to mine: none")
	# A dry field still in the list is not a live site.
	var dry := _cs_world(69, 10.0, 0.0)
	dry.f.amount = 0.0
	for i in 50:
		t.check(dry.w.choose_site() == dry.p, "a dry field is skipped: the pit")


func test_choose_site_stops_above_1_3_times_the_target(t) -> void:
	# ice target 120 (no beings), regolith target 160 + 12 x 4 buildings = 208.
	var a := _cs_world(70, 200.0, 0.0, true, false)
	var w: SimWorld = a.w
	if not _api(t, w, ["site"]):
		return
	t.check(w.choose_site() == null, "ice 200 > 1.3 x 120 = 156 and only ice fields: stop")
	var b := _cs_world(71, 155.0, 0.0, true, false)
	t.check(b.w.choose_site() == b.f, "ice 155 <= 156: still mining ice")
	var c := _cs_world(72, 60.0, 300.0, false, true)
	t.check(c.w.choose_site() == null, "regolith 300 > 1.3 x 208 = 270.4 and only a pit: stop")
	var d := _cs_world(73, 60.0, 270.0, false, true)
	t.check(d.w.choose_site() == d.p, "regolith 270 <= 270.4: still mining regolith")
	var e := _cs_world(78, 60.0, 300.0, true, false)
	t.check(e.w.choose_site() == e.f, "regolith 300 does not stop an ice trip (the stop is per pool)")
	var g := _cs_world(79, 200.0, 0.0, false, true)
	t.check(g.w.choose_site() == g.p, "ice 200 does not stop a regolith trip")
	# Mixed: ice 200, regolith 0: the pool is ice with p = 0.15 / (0 + 1 + 0.3) = 0.1154 (then none), else the pit.
	var m := _cs_world(74, 200.0, 0.0)
	var nulls := 0
	var pits := 0
	var n := 3000
	for i in n:
		var got: Variant = m.w.choose_site()
		if got == null:
			nulls += 1
		elif got == m.p:
			pits += 1
	t.between(float(nulls) / n, 0.1154 - 0.03, 0.1154 + 0.03, "stop only applies to the ice pool (0.115 none)")
	t.eq(nulls + pits, n, "otherwise always the pit, never the over-stocked ice field")


func test_choose_site_with_no_online_building_is_none(t) -> void:
	var c := _cs_world(75, 10.0, 0.0)
	var w: SimWorld = c.w
	if not _api(t, w, ["site"]):
		return
	for b in w.buildings.list:
		w.set_offline(b.id, true)
	t.check(w.choose_site() == null, "no online building: no trip time, no site")


# ---------------------------------------------------------------- mining attempt chance (spec 6.4 branch 4)

## Rate of mining intents over `n` decide calls: a being in R, only a pit near the R door, daytime, energy 90.
func _attempt_rate(seed_in: int, traits: Dictionary, regolith: float, oxygen: float, n: int) -> float:
	var h := _world(seed_in)
	var w: SimWorld = h.w
	w.resources.add_pit(60.0, 120.0)
	w.colony.ice = 120.0
	w.colony.regolith = regolith
	w.colony.oxygen = oxygen
	_hour(w, 12.0)
	w.t += DT
	var b := w.add_being(int(h.R), "social")
	_traits(b, traits)
	var made := 0
	for i in n:
		b.state = "idle"
		b.energy = 90.0
		b.mine = null
		b.mine_intent = null
		b.suit_up = false
		b.sleep_intent = false
		b.decide(w)
		if b.mine != null or b.mine_intent != null:
			made += 1
	return float(made) / n


func test_mining_attempt_chance_is_0_4_times_will_times_the_need_term(t) -> void:
	var base := {"steady": 0.5, "drive": 0.5, "restless": 0.5}
	var n := 8000
	# The spec's case: will 0.5, need 1, oxygen 100 -> 0.2.
	var r1 := _attempt_rate(81, base, 0.0, 100.0, n)
	t.between(r1, 0.18, 0.22, "will 0.5, need 1: 0.4 x 0.5 x 1 = 0.2 (got %.4f)" % r1)
	# will weights steady 0.45, drive 0.35, restless 0.2.
	var r2 := _attempt_rate(82, {"steady": 1.0, "drive": 0.0, "restless": 0.0}, 0.0, 100.0, n)
	t.between(r2, 0.16, 0.20, "steady only: will 0.45 -> 0.18 (got %.4f)" % r2)
	var r3 := _attempt_rate(83, {"steady": 0.0, "drive": 1.0, "restless": 0.0}, 0.0, 100.0, n)
	t.between(r3, 0.12, 0.16, "drive only: will 0.35 -> 0.14 (got %.4f)" % r3)
	var r4 := _attempt_rate(84, {"steady": 0.0, "drive": 0.0, "restless": 1.0}, 0.0, 100.0, n)
	t.between(r4, 0.06, 0.10, "restless only: will 0.2 -> 0.08 (got %.4f)" % r4)
	# Need term 0.15 + 0.85 need: regolith 104 of 208 -> need 0.5 -> 0.4 x 0.5 x 0.575 = 0.115; need 0 -> 0.03.
	var r5 := _attempt_rate(85, base, 104.0, 100.0, n)
	t.between(r5, 0.095, 0.135, "need 0.5: 0.115 (got %.4f)" % r5)
	var r6 := _attempt_rate(86, base, 208.0, 100.0, n)
	t.between(r6, 0.015, 0.045, "need 0: the 0.15 floor, 0.03 (got %.4f)" % r6)


func test_mining_attempt_needs_oxygen_above_10(t) -> void:
	var base := {"steady": 0.5, "drive": 0.5, "restless": 0.5}
	t.eq(_attempt_rate(87, base, 0.0, 10.0, 3000), 0.0, "oxygen exactly 10: no attempt (strictly above)")
	var r := _attempt_rate(88, base, 0.0, 10.5, 3000)
	t.between(r, 0.17, 0.23, "oxygen 10.5: attempts at 0.2 (got %.4f)" % r)


## Exact version of the chance test: decide's first draw is the mining chance (nothing before it draws), so for every
## trial the outcome must be (u < p) with u the first number of the rng stream and p = 0.4 x will x (0.15 + 0.85 need).
## Returns the number of trials whose outcome disagrees.
func _attempt_mismatches(seed_in: int, traits: Dictionary, ice: float, regolith: float, n: int) -> int:
	var h := _world(seed_in)
	var w: SimWorld = h.w
	w.resources.add_pit(60.0, 120.0)
	w.colony.ice = ice
	w.colony.regolith = regolith
	w.colony.oxygen = 100.0
	_hour(w, 12.0)
	w.t += DT
	var b := w.add_being(int(h.R), "social")
	_traits(b, traits)
	var will := 0.45 * float(traits.get("steady", 0.5)) + 0.35 * float(traits.get("drive", 0.5)) \
			+ 0.2 * float(traits.get("restless", 0.5))
	var need := maxf(0.0, maxf(1.0 - ice / 120.0, 1.0 - regolith / 208.0))
	var p := 0.4 * will * (0.15 + 0.85 * need)
	var bad := 0
	for i in n:
		b.state = "idle"
		b.energy = 90.0
		b.mine = null
		b.mine_intent = null
		b.suit_up = false
		b.sleep_intent = false
		var u := _replay(_rng_state(w)).randf()
		b.decide(w)
		var made: bool = b.mine != null or b.mine_intent != null
		if made != (u < p):
			bad += 1
	return bad


func test_mining_attempt_chance_matches_the_formula_trial_by_trial(t) -> void:
	var half := {"steady": 0.5, "drive": 0.5, "restless": 0.5}
	var cases := [
		["will 0.5, need 1", half, 120.0, 0.0],
		["steady only (0.45)", {"steady": 1.0, "drive": 0.0, "restless": 0.0}, 120.0, 0.0],
		["drive only (0.35)", {"steady": 0.0, "drive": 1.0, "restless": 0.0}, 120.0, 0.0],
		["restless only (0.2)", {"steady": 0.0, "drive": 0.0, "restless": 1.0}, 120.0, 0.0],
		["regolith need 0.5", half, 120.0, 104.0],
		["no need (floor 0.15)", half, 120.0, 208.0],
		["ice need 1 (regolith full)", half, 0.0, 208.0],
		["ice need 0.5 beats regolith need 0.25", half, 60.0, 156.0],
		["regolith need 0.5 beats ice need 0.25", half, 90.0, 104.0],
	]
	for c in cases:
		var bad := _attempt_mismatches(300 + int(cases.find(c)), c[1], c[2], c[3], 2500)
		t.eq(bad, 0, "%s: outcome equals (first draw < p) in every trial (mismatches %d)" % [c[0], bad])


func test_mining_attempt_draws_nothing_unless_every_gate_passes(t) -> void:
	# Gates in order (spec 6.4 branch 4): sites exist, no mine, oxygen > 10, then the chance. A failed gate draws no chance:
	# decide then ends with idle_wait only (walk U(10,56), pause U(1,4)); R has no tunnel so there is no travel draw.
	var gates := ["no sites", "already has a mine", "oxygen 10"]
	for gi in gates.size():
		var h := _lone(310 + gi)
		var w: SimWorld = h.w
		var f := w.resources.add_ice_field(48.0 + 100.0, 80.0, 300.0, 20.0)
		if gi == 0:
			w.resources.ice_fields.clear()
		w.colony.ice = 0.0
		w.colony.regolith = 0.0
		w.colony.oxygen = 100.0
		_hour(w, 12.0)
		w.t += DT
		var b := w.add_being(int(h.R), "social")
		_traits(b, {"steady": 1.0, "drive": 1.0, "restless": 1.0})
		b.energy = 90.0
		if gi == 1:
			b.mine = {"site": f, "door": R_DOOR, "home_id": int(h.R)}
		if gi == 2:
			w.colony.oxygen = 10.0
		var s0 := _rng_state(w)
		b.decide(w)
		var r2 := _replay(s0)
		r2.randf_range(10.0, 56.0)
		r2.randf_range(1.0, 4.0)
		t.eq(_rng_state(w), r2._rng.state, "%s: only idle_wait's two draws, no mining chance" % gates[gi])
		t.check(b.state == "idle" and b.mine_intent == null and not b.suit_up, "%s: it just waits (idle, no intent, no suit)" % gates[gi])
		if gi == 1:
			t.check(b.mine != null and b.mine.site == f and b.mine_intent == null, "%s: the mine is untouched" % gates[gi])
	# Control: every gate open draws at least the chance as well.
	var h2 := _lone(319)
	var w2: SimWorld = h2.w
	w2.resources.add_ice_field(48.0 + 100.0, 80.0, 300.0, 20.0)
	w2.colony.ice = 0.0
	w2.colony.regolith = 0.0
	_hour(w2, 12.0)
	w2.t += DT
	var b2 := w2.add_being(int(h2.R), "social")
	_traits(b2, {"steady": 1.0, "drive": 1.0, "restless": 1.0})
	b2.energy = 90.0
	var s2 := _rng_state(w2)
	b2.decide(w2)
	var r3 := _replay(s2)
	r3.randf_range(10.0, 56.0)
	r3.randf_range(1.0, 4.0)
	t.check(_rng_state(w2) != r3._rng.state, "control: with every gate open the chance is drawn")


# ---------------------------------------------------------------- mine intent, launch building (spec 6.4 branch 3, A3)

func test_intent_in_the_launch_building_starts_mining_at_once(t) -> void:
	var h := _world(91)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	_hour(w, 12.0)
	w.t += DT
	var b := w.add_being(int(h.A), "social")
	b.energy = 90.0
	b.mine_intent = f
	var o2: float = w.colony.oxygen
	var s0 := _rng_state(w)
	b.decide(w)
	var r2 := _replay(s0)
	r2.randf_range(10.0, 56.0)
	t.eq(_rng_state(w), r2._rng.state, "resuming an intent draws only the door walk time (no new mining chance first)")
	t.check(b.mine != null and b.mine.site == f, "mine.site is the field")
	if b.mine != null:
		t.near((b.mine.door as Vector2).distance_to(A_DOOR), 0.0, 1e-9, "mine.door = the A door (nearest online door)")
		t.eq(int(b.mine.home_id), int(h.A), "mine.home_id = A")
	t.check(b.suit_up, "suit_up set")
	t.check(b.mine_intent == null, "mine_intent cleared by start_mining")
	t.eq(b.state, "to_door", "walking to the door")
	t.near(w.colony.oxygen, o2, 1e-12, "nothing is paid before the suit-up")


func test_intent_elsewhere_hops_by_tunnel_to_the_nearest_online_door_then_suits_up_there(t) -> void:
	var h := _world(92)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	_hour(w, 12.0)
	w.t += DT
	var b := w.add_being(int(h.R), "social")
	b.energy = 100.0
	b.mine_intent = f
	var o2: float = w.colony.oxygen
	var s0 := _rng_state(w)
	b.decide(w)
	var r2 := _replay(s0)
	r2.randf_range(10.0, 56.0)
	t.eq(_rng_state(w), r2._rng.state, "the hop draws only the door walk time")
	t.check(b.mine == null and b.mine_intent == f, "still an intent, no mine yet")
	t.eq(b.state, "to_door", "walking to a tunnel door")
	t.eq(_i(b.corridor_id), int(h.A), "the hop is the tunnel R -> A (A is nearest to the field)")
	t.check(not b.suit_up, "no suit in the building it leaves")
	t.near(w.colony.oxygen, o2, 1e-12, "no oxygen spent")
	var seen_transit := false
	var dev_before := 0.0
	var dev_suit := 0.0
	var steps := 0
	while b.state != "eva" and steps < 900:
		w.buildings.last_short_t = w.t
		b.energy = 100.0
		var expected := _o2_next(w)
		w.step()
		steps += 1
		var dev := w.colony.oxygen - expected
		if b.state == "transit":
			seen_transit = true
		if b.state == "eva":
			dev_suit = dev
		else:
			dev_before = maxf(dev_before, absf(dev))
	t.eq(b.state, "eva", "suited up and walking out after %d steps" % steps)
	t.check(seen_transit, "it walked the tunnel")
	t.near(dev_before, 0.0, 1e-9, "no oxygen spent before the suit-up step")
	t.near(dev_suit, -1.0, 1e-9, "exactly one fill, paid on the suit-up step")
	t.check(b.mine != null, "has a mine")
	if b.mine != null:
		t.eq(int(b.mine.home_id), int(h.A), "launched from A")
		t.near((b.mine.door as Vector2).distance_to(A_DOOR), 0.0, 1e-9, "mine.door = A door")
	t.near(_pos(b).distance_to(A_DOOR), 0.0, 1e-9, "the suit-up happened at the A door")
	t.eq(int(w.stats.mining_trips), 1, "one trip")


func test_nearest_online_door_changes_when_a_building_goes_offline(t) -> void:
	var h := _world(93)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	w.set_offline(int(h.A), true)
	t.eq(w.resources.launch_for(f).id, int(h.W), "with A dark the W door (104.7) is next")
	_hour(w, 12.0)
	w.t += DT
	var b := w.add_being(int(h.R), "social")
	b.energy = 100.0
	b.mine_intent = f
	b.decide(w)
	t.eq(_i(b.corridor_id), int(h.W), "the miner heads for W (offline A is passable but not a launch)")
	var steps := 0
	while b.state != "eva" and steps < 900:
		w.buildings.last_short_t = w.t
		b.energy = 100.0
		w.step()
		steps += 1
	t.eq(b.state, "eva", "launched")
	t.check(b.mine != null and int(b.mine.home_id) == int(h.W), "from the workshop")
	if b.mine != null:
		t.near((b.mine.door as Vector2).distance_to(W_DOOR), 0.0, 1e-9, "its door")


func test_intent_with_no_online_building_or_a_dry_field_is_cancelled_without_oxygen(t) -> void:
	var h := _world(94)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	_hour(w, 12.0)
	w.t += DT
	var b := w.add_being(int(h.R), "social")
	b.energy = 90.0
	b.mine_intent = f
	for bd in w.buildings.list:
		w.set_offline(bd.id, true)
	var o2: float = w.colony.oxygen
	b.decide(w)
	t.check(b.mine_intent == null, "no launch building: the intent is cancelled")
	t.check(b.mine == null and not b.suit_up, "no mine, no suit")
	t.near(w.colony.oxygen, o2, 1e-12, "no oxygen spent")
	# A dry field.
	var h2 := _world(95)
	var w2: SimWorld = h2.w
	var f2 := w2.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	_hour(w2, 12.0)
	w2.t += DT
	var b2 := w2.add_being(int(h2.R), "social")
	b2.energy = 90.0
	b2.mine_intent = f2
	w2.take_ice(f2, 1e9)
	var o22: float = w2.colony.oxygen
	b2.decide(w2)
	t.check(b2.mine_intent == null and b2.mine == null and not b2.suit_up, "a dry field cancels the intent")
	t.near(w2.colony.oxygen, o22, 1e-12, "no oxygen spent")


func test_a_new_attempt_in_another_building_sets_an_intent_and_hops(t) -> void:
	var h := _world(96)
	var w: SimWorld = h.w
	if not _api(t, w, ["site"]):
		return
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	w.colony.ice = 60.0
	w.colony.regolith = 0.0
	_hour(w, 12.0)
	w.t += DT
	var b := w.add_being(int(h.R), "social")
	_traits(b, {"steady": 1.0, "drive": 1.0, "restless": 1.0})
	var found := false
	for i in 300:
		b.state = "idle"
		b.energy = 90.0
		b.mine = null
		b.mine_intent = null
		b.suit_up = false
		b.decide(w)
		if b.mine_intent != null:
			found = true
			break
	t.check(found, "an attempt succeeded within 300 decides (p 0.4 each)")
	if found:
		t.check(b.mine_intent == f and b.mine == null, "intent set, not yet mining")
		t.eq(b.state, "to_door", "walking to the tunnel door")
		t.eq(_i(b.corridor_id), int(h.A), "toward A, the launch building")
		t.check(not b.suit_up, "no suit yet")


# ---------------------------------------------------------------- EVA arrival rows: mine and haul (spec 6.5b)

func test_eva_arrival_mine_starts_mining_with_a_5_to_9_hour_shift(t) -> void:
	var lo := 99.0
	var hi := 0.0
	for s in 80:
		var h := _world(3000 + s)
		var w: SimWorld = h.w
		var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
		var b := _miner(w, int(h.R), f, Vector2(140.0, 150.0), "eva")
		b.path = [Vector2(140.0, 150.0)]
		b.wait_h = 7.0
		w.step()
		if b.state != "mining":
			t.check(false, "seed %d: state mining after arrival (got %s)" % [s, b.state])
			return
		if s == 0:
			t.near(b.wait_h, 0.0, 1e-12, "wait_h = 0 at the start of the shift")
			t.near(_pos(b).distance_to(b.wander_target), 0.0, 1e-9, "the first wander target is the arrival position")
			t.check(b.mine != null, "mine kept")
		lo = minf(lo, b.work_left_h)
		hi = maxf(hi, b.work_left_h)
	t.between(lo, 5.0, 5.5, "shift lower end 5 h")
	t.between(hi, 8.5, 9.0, "shift upper end 9 h")


func test_eva_arrival_haul_deposits_ice_or_regolith_and_goes_home(t) -> void:
	var h := _world(101)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var pit := w.resources.add_pit(60.0, 140.0)
	var ib := _miner(w, int(h.R), f, R_DOOR + Vector2(0.5, 0.0), "eva")
	ib.after = "haul"
	ib.load = 7.5
	ib.path = [R_DOOR]
	ib.returning = true
	var ice0: float = w.colony.ice
	var reg0: float = w.colony.regolith
	var pop: int = w.colony.pop()
	w.step()
	t.near(w.colony.ice, ice0 - pop * 0.01 * DT + 7.5, 1e-9, "a field's load goes into ice")
	t.near(w.colony.regolith, reg0, 1e-12, "regolith untouched")
	t.eq(ib.load, 0.0, "load reset")
	t.check(ib.mine == null, "mine = null")
	t.eq(ib.state, "idle", "idle")
	t.eq(ib.building_id, int(h.R), "in mine.home_id")
	t.check(ib.air_h == null and ib.path == null and not ib.returning and ib.x == null, "suit off, path and position cleared")
	t.check(ib.wait_h > 0.0, "wait_h = idle_wait")
	t.eq(ib.suit_kind(), "none", "inside: none")
	var pb := _miner(w, int(h.R), pit, R_DOOR + Vector2(0.5, 0.0), "eva")
	pb.after = "haul"
	pb.load = 11.25
	pb.path = [R_DOOR]
	var reg1: float = w.colony.regolith
	var ice1: float = w.colony.ice
	w.step()
	t.near(w.colony.regolith, reg1 + 11.25, 1e-9, "a pit's load goes into regolith")
	t.near(w.colony.ice, ice1 - w.colony.pop() * 0.01 * DT, 1e-9, "ice untouched")
	t.check(pb.mine == null and pb.state == "idle" and pb.load == 0.0, "pit hauler home and empty")


func test_haul_walk_goes_to_the_door_and_a_load_from_a_dried_field_still_goes_into_ice(t) -> void:
	var h := _world(102)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 2.5, 20.0)
	var b := _miner(w, int(h.R), f, R_DOOR + Vector2(20.0, 0.0), "mining")
	b.work_left_h = 0.01
	b.wait_h = 1000.0
	var ice0: float = w.colony.ice
	var reg0: float = w.colony.regolith
	w.step()
	t.eq(b.state, "eva", "shift over: walking home")
	t.eq(b.after, "haul", "after = haul")
	t.near(b.load, 2.5, 1e-9, "the last 2.5 of the field (the yield was larger)")
	t.near(f.amount, 0.0, 1e-12, "the field is empty at dig time")
	t.check(not w.resources.ice_fields.has(f), "and has left the list")
	var pts := _pts(b)
	t.check(pts.size() >= 1 and (pts[0] as Vector2).distance_to(R_DOOR) < 1e-9, "the path goes to mine.door")
	var steps := 1
	while b.state == "eva" and steps < 200:
		b.energy = 100.0
		w.step()
		steps += 1
	t.eq(b.state, "idle", "home")
	t.near(w.colony.ice, ice0 - w.colony.pop() * 0.01 * DT * steps + 2.5, 1e-9, "the load went into ice, not regolith, although the field is gone")
	t.near(w.colony.regolith, reg0, 1e-9, "regolith untouched")
	t.between(float(steps) * DT, 1.15, 1.35, "20 px at 16 px/h")


# ---------------------------------------------------------------- mining yields (spec 8.3)

## One digging step. Returns {w, b, f, load}. Energy is the INPUT value (the drain 0.13 is taken in the step).
func _dig(seed_in: int, kind: String, drive: float, energy_in: float, amount: float = 300.0) -> Dictionary:
	var h := _world(seed_in)
	var w: SimWorld = h.w
	var f: Resources.Site
	if kind == "ice":
		f = w.resources.add_ice_field(140.0, 150.0, amount, 20.0)
	else:
		f = w.resources.add_pit(60.0, 140.0)
	var b := _miner(w, int(h.R), f, R_DOOR + Vector2(30.0, 0.0), "mining", 36.0, energy_in)
	_traits(b, {"drive": drive})
	b.work_left_h = 0.01
	w.step()
	return {"w": w, "b": b, "f": f, "load": b.load, "h": h}


func test_ice_and_regolith_yield_bands_at_drive_half_energy_80(t) -> void:
	# Mining drains 2.6 x 0.05 = 0.13 per step: 80.13 reads exactly 80. Factor 1.0 x (0.55 + 80/220) = 0.913636.
	var k := 0.55 + 80.0 / 220.0
	var lo := 99.0
	var hi := 0.0
	var rlo := 99.0
	var rhi := 0.0
	for s in 300:
		var d := _dig(4000 + s, "ice", 0.5, 80.13)
		if d.b.state != "eva" or d.b.after != "haul":
			t.check(false, "seed %d: digging ends in a haul" % s)
			return
		lo = minf(lo, d.load)
		hi = maxf(hi, d.load)
		var r := _dig(5000 + s, "pit", 0.5, 80.13)
		rlo = minf(rlo, r.load)
		rhi = maxf(rhi, r.load)
	t.check(lo >= 6.0 * k - 1e-3, "ice yield never below 5.4818 (min %.4f)" % lo)
	t.check(hi <= 10.0 * k + 1e-3, "ice yield never above 9.1364 (max %.4f)" % hi)
	t.between(lo, 5.4818 - 1e-3, 5.4818 + 0.15, "ice minimum close to the lower end")
	t.between(hi, 9.1364 - 0.15, 9.1364 + 1e-3, "ice maximum close to the upper end")
	t.check(rlo >= 8.0 * k - 1e-3, "regolith never below 7.3091 (min %.4f)" % rlo)
	t.check(rhi <= 14.0 * k + 1e-3, "regolith never above 12.7909 (max %.4f)" % rhi)
	t.between(rlo, 7.3091 - 1e-3, 7.3091 + 0.2, "regolith minimum close to the lower end")
	t.between(rhi, 12.7909 - 0.2, 12.7909 + 1e-3, "regolith maximum close to the upper end")


func test_yield_scales_with_energy_read_after_the_drain_and_with_drive(t) -> void:
	for s in 8:
		var a := _dig(6000 + s, "ice", 0.5, 80.13)
		var b := _dig(6000 + s, "ice", 0.5, 60.13)
		var want := (0.55 + 60.0 / 220.0) / (0.55 + 80.0 / 220.0)
		t.check(a.load > 1.0 and b.load > 1.0, "seed %d: both runs dug a real load" % (6000 + s))
		t.near(b.load / maxf(a.load, 1e-9), want, 1e-9, "same draws: ratio is the energy factor of 60 vs 80 (drain taken first)")
		var d1 := _dig(6100 + s, "ice", 1.0, 80.13)
		var d0 := _dig(6100 + s, "ice", 0.0, 80.13)
		t.check(d1.load > 1.0 and d0.load > 1.0, "drive runs dug a real load")
		t.near(d1.load / maxf(d0.load, 1e-9), (0.7 + 0.6) / 0.7, 1e-9, "drive 1 vs drive 0: (0.7 + 0.6) / 0.7")
		var p1 := _dig(6200 + s, "pit", 1.0, 80.13)
		var p0 := _dig(6200 + s, "pit", 0.0, 80.13)
		t.check(p1.load > 1.0 and p0.load > 1.0, "regolith runs dug a real load")
		t.near(p1.load / maxf(p0.load, 1e-9), (0.7 + 0.6) / 0.7, 1e-9, "same for regolith")


func test_digging_takes_the_yield_from_the_field_at_once_and_ice_arrives_only_with_the_haul(t) -> void:
	var d := _dig(6300, "ice", 0.5, 80.13, 300.0)
	var w: SimWorld = d.w
	t.near(d.f.amount, 300.0 - d.load, 1e-9, "the field shrinks by exactly the load at dig time")
	t.check(d.load > 5.0, "a real load")
	t.near(w.colony.ice, 60.0 - w.colony.pop() * 0.01 * DT, 1e-9, "colony ice has not changed yet (only the drain)")
	t.check(w.resources.ice_fields.has(d.f), "a field with ice left stays in the list")
	var p := _dig(6301, "pit", 0.5, 80.13)
	t.check(is_inf(p.f.amount), "a pit is infinite")
	t.near(p.w.colony.regolith, 80.0, 1e-9, "regolith has not changed yet")


func test_a_dry_field_is_clamped_removed_logged_once_and_replaced(t) -> void:
	var d := _dig(6400, "ice", 0.5, 80.13, 2.0)
	var w: SimWorld = d.w
	t.near(d.load, 2.0, 1e-12, "load is min(yield, amount) = 2")
	t.eq(d.f.amount, 0.0, "amount 0, never negative")
	t.check(not w.resources.ice_fields.has(d.f), "removed from the list")
	t.eq(int(w.stats.ice_dry), 1, "stats.ice_dry")
	t.eq(_logs(w, "ice_dry"), 1, "logged once")
	t.eq(_logs(w, "ice_found"), 1, "fewer than 2 reachable: a new field at once")
	t.eq(w.resources.ice_fields.size(), 1, "exactly one replacement")
	t.check(w.resources.reachable_ice_count() == 1, "and it is reachable")
	# Two miners at the same field: ascending id, the second gets 0.
	var h := _world(6401)
	var w2: SimWorld = h.w
	var f := w2.resources.add_ice_field(140.0, 150.0, 2.0, 20.0)
	var first := _miner(w2, int(h.R), f, R_DOOR + Vector2(30.0, 0.0), "mining")
	var second := _miner(w2, int(h.R), f, R_DOOR + Vector2(40.0, 0.0), "mining")
	first.work_left_h = 0.01
	second.work_left_h = 0.01
	w2.step()
	t.near(first.load, 2.0, 1e-12, "the first takes the last 2")
	t.near(second.load, 0.0, 1e-12, "the second hauls 0")
	t.eq(int(w2.stats.ice_dry), 1, "dry once")
	t.eq(_logs(w2, "ice_dry"), 1, "one log line")
	t.check(f.amount >= 0.0, "no negative amount")
	# A miner in the middle of its shift when the field runs dry stops at once and hauls what it has (nothing).
	var h3 := _world(6402)
	var w3: SimWorld = h3.w
	var f3 := w3.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var mid := _miner(w3, int(h3.R), f3, R_DOOR + Vector2(30.0, 0.0), "mining")
	mid.work_left_h = 5.0
	w3.step()
	t.eq(mid.state, "mining", "still mining a live field")
	w3.take_ice(f3, 1e9)
	w3.step()
	w3.step()
	t.eq(mid.state, "eva", "the field ran dry: shift over")
	t.eq(mid.after, "haul", "heading home")
	t.near(mid.load, 0.0, 1e-12, "with nothing")


# ---------------------------------------------------------------- mining wander (spec 8.3)

func test_wander_draws_wait_then_angle_then_radius_inside_the_field(t) -> void:
	var h := _world(111)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var b := _miner(w, int(h.R), f, Vector2(140.0, 150.0), "mining")
	b.wait_h = 0.0
	b.work_left_h = 7.0
	var s0 := _rng_state(w)
	w.step()
	var r2 := _replay(s0)
	var wait := r2.randf_range(0.6, 2.0)
	var ang := r2.randf_range(0.0, TAU)
	var rad := r2.randf_range(0.2, 0.8)
	var target := Vector2(f.x + cos(ang) * f.r * rad, f.y + sin(ang) * f.r * rad * 0.7)
	t.near(b.wait_h, wait, DT + 1e-6, "wait_h = U(0.6, 2) drawn first")
	t.near(b.wander_target.distance_to(target), 0.0, 1e-3, "then the angle, then the radius (y x 0.7)")
	t.near(b.work_left_h, 7.0 - DT, 1e-9, "the shift counts down")
	# Over many draws the target stays inside the 0.2..0.8 ring of the squashed ellipse and the waits in 0.6..2.
	var fmin := 9.0
	var fmax := 0.0
	var wmin := 99.0
	var wmax := 0.0
	var h2 := _world(112)
	var w2: SimWorld = h2.w
	var f2 := w2.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var m := _miner(w2, int(h2.R), f2, Vector2(140.0, 150.0), "mining")
	m.work_left_h = 100000.0
	for i in 300:
		m.wait_h = 0.0
		m.x = m.wander_target.x
		m.y = m.wander_target.y
		w2.step()
		var fr := _frac(f2, m.wander_target)
		fmin = minf(fmin, fr)
		fmax = maxf(fmax, fr)
		wmin = minf(wmin, m.wait_h)
		wmax = maxf(wmax, m.wait_h)
	t.between(fmin, 0.2 - 1e-6, 0.26, "smallest wander radius fraction ~0.2")
	t.between(fmax, 0.74, 0.8 + 1e-6, "largest ~0.8")
	t.between(wmin, 0.6 - DT - 1e-6, 0.75, "shortest wait ~0.6")
	t.between(wmax, 1.85, 2.0 + 1e-6, "longest wait ~2")


func test_wander_moves_4_px_per_hour_only_after_the_wait(t) -> void:
	var h := _world(113)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var start := Vector2(100.0, 100.0)
	var b := _miner(w, int(h.R), f, start, "mining")
	b.wait_h = 0.3
	b.wander_target = start + Vector2(60.0, 0.0)
	_run(w, 5)
	t.near(_pos(b).distance_to(start), 0.0, 1e-9, "no movement while wait_h > 0 (5 steps of 6)")
	_run(w, 40)
	var moved := _pos(b).distance_to(start)
	t.between(moved, 0.2 * 38.0 - 1e-3, 0.2 * 40.0 + 1e-3, "then 4 px/h = 0.2 px per step (moved %.3f)" % moved)
	t.near(_pos(b).y, 100.0, 1e-3, "straight toward the target")
	t.near(b.energy, 100.0 - 2.6 * DT * 45.0, 1e-9, "mining drain 2.6 per hour")


func test_wander_reach_is_0_6_px_not_the_0_8_of_a_waypoint(t) -> void:
	# The prototype (L646) checks the distance first and then moves. A target 0.7 px away is inside a waypoint's 0.8 but
	# outside the mining reach of 0.6: step 1 must walk (to 0.5 px), step 2 must find it reached and draw a new one.
	var h := _world(114)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var target := Vector2(100.0, 100.0)
	var b := _miner(w, int(h.R), f, target - Vector2(0.7, 0.0), "mining")
	b.wait_h = 0.0
	b.wander_target = target
	w.step()
	t.near(b.wander_target.distance_to(target), 0.0, 1e-12, "step 1: 0.7 px away is not reached (reach 0.6): same target")
	t.near(b.wait_h, 0.0, 1e-12, "no new wait yet")
	t.near(_pos(b).distance_to(target), 0.5, 1e-3, "it walked 0.2 px")
	w.step()
	t.check(b.wander_target.distance_to(target) > 1e-6 and b.wait_h > 0.5, "step 2: 0.5 px away is reached: a new target and wait")
	# Starting at 0.5 px (inside 0.6): a new target at once.
	var h2 := _world(115)
	var w2: SimWorld = h2.w
	var f2 := w2.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var b2 := _miner(w2, int(h2.R), f2, target - Vector2(0.5, 0.0), "mining")
	b2.wait_h = 0.0
	b2.wander_target = target
	w2.step()
	t.check(b2.wander_target.distance_to(target) > 1e-6 and b2.wait_h > 0.5, "0.5 px away counts as reached at once")


func test_eva_waypoint_is_reached_inside_0_8_px(t) -> void:
	var h := _world(116)
	var w: SimWorld = h.w
	var near := _walker(w, int(h.R), Vector2(100.0, 100.0))
	near.path = [Vector2(100.7, 100.0)]
	var far := _walker(w, int(h.R), Vector2(100.0, 300.0))
	far.path = [Vector2(100.9, 300.0)]
	w.step()
	t.eq(near.state, "idle", "0.7 px from the last waypoint (< 0.8): the EVA ends at once")
	t.eq(far.state, "eva", "0.9 px (>= 0.8): it still walks")
	w.step()
	t.eq(far.state, "idle", "0.1 px left (< 0.8): ends on the next step")


# ---------------------------------------------------------------- footprints (spec 8.5)

## After each of `n` steps, records the print count; returns the counts and checks every new print's geometry.
func _walk_prints(t, w: SimWorld, b: Being, n: int, expect_heavy: Variant = null) -> Array:
	var counts: Array = []
	var last_side := 0.0
	for i in n:
		var before := _fps(w).size()
		w.step()
		var fps := _fps(w)
		counts.append(fps.size())
		if fps.size() == before + 1 and b.x != null:
			var p: Variant = fps[fps.size() - 1]
			var pos := Vector2(float(b.x), float(b.y))
			var off := Vector2(float(_g(p, "x")), float(_g(p, "y"))) - pos
			var hd := float(b.heading)
			var along := off.dot(Vector2(cos(hd), sin(hd)))
			var across := off.dot(Vector2(-sin(hd), cos(hd)))
			t.near(absf(across), 0.7, 1e-3, "print %d: 0.7 px to the side" % fps.size())
			t.near(along, 0.0, 1e-3, "print %d: exactly beside the path" % fps.size())
			if last_side != 0.0:
				t.check(signf(across) == -last_side, "print %d: the side alternates" % fps.size())
			last_side = signf(across)
			t.near(float(_g(p, "heading")), hd, 1e-9, "print heading = the being's heading")
			t.near(float(_g(p, "t")), w.t, 1e-9, "print t = now")
			if expect_heavy != null:
				t.eq(bool(_g(p, "heavy")), bool(expect_heavy), "print %d heavy flag" % fps.size())
	return counts


func test_eva_footprints_every_third_step_with_the_reset_rule(t) -> void:
	var h := _world(121)
	var w: SimWorld = h.w
	if not _api(t, w, ["fp"]):
		return
	var b := _walker(w, int(h.R), Vector2(100.0, 100.0))
	var counts := _walk_prints(t, w, b, 30)
	t.eq(counts[1], 0, "after 2 steps: none (0.8, 1.6)")
	t.eq(counts[2], 1, "the third step (2.4 px >= 2.2) leaves the first print")
	t.eq(counts[5], 2, "the sixth step the second")
	t.eq(counts[29], 10, "30 straight steps (24 px) leave exactly 10 prints")
	var w2: SimWorld = _world(122).w
	var b2 := _walker(w2, 1, Vector2(100.0, 100.0))
	var c2 := _walk_prints(t, w2, b2, 20)
	t.eq(c2[19], 6, "20 steps (16 px) leave 6 prints: the counter resets to 0 (carrying 0.2 would give 7)")
	var first: Variant = _fps(w2)[0]
	t.near(float(_g(first, "x")), 100.0 + 2.4, 1e-3, "the first print sits where the being stood on step 3")


func test_footprint_sides_are_perpendicular_to_a_slanted_heading(t) -> void:
	var h := _world(123)
	var w: SimWorld = h.w
	if not _api(t, w, ["fp"]):
		return
	var b := _walker(w, int(h.R), Vector2(100.0, 100.0), Vector2(1.0, 2.0).normalized())
	var counts := _walk_prints(t, w, b, 24)
	t.eq(counts[23], 8, "24 steps leave 8 prints")


func test_work_footprints_every_eighth_step(t) -> void:
	var h := _swork(124)
	var w: SimWorld = h.w
	if not _api(t, w, ["fp"]):
		return
	var b := _builder_at_work(w, h.site)
	var counts := _walk_prints(t, w, b, 40, true)
	t.eq(counts[6], 0, "7 steps of 0.3 px: 2.1 < 2.2, nothing yet")
	t.eq(counts[7], 1, "the 8th step (2.4) leaves the first print")
	t.eq(counts[39], 5, "40 steps leave exactly 5 prints")
	t.near(_pos(b).x, 141.0 + 12.0, 1e-3, "the builder walked 6 px/h x 0.05 = 0.3 px per step")


func test_mining_footprints_every_eleventh_step_which_needs_the_eps(t) -> void:
	var h := _world(125)
	var w: SimWorld = h.w
	if not _api(t, w, ["fp"]):
		return
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var b := _miner(w, int(h.R), f, Vector2(100.0, 100.0), "mining")
	b.wait_h = 0.0
	b.wander_target = Vector2(400.0, 100.0)
	var counts := _walk_prints(t, w, b, 55, false)
	t.eq(counts[9], 0, "10 steps of 0.2 px: 2.0")
	t.eq(counts[10], 1, "the 11th step reaches 2.2 (a float sum of 2.1999999999999997): STEP_EPS in the comparator")
	t.eq(counts[54], 5, "55 steps leave exactly 5 prints (a strict >= 2.2 would leave 4)")


func test_no_prints_while_standing_in_a_tunnel_or_inside(t) -> void:
	var h := _world(126)
	var w: SimWorld = h.w
	if not _api(t, w, ["fp"]):
		return
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var still := _miner(w, int(h.R), f, Vector2(100.0, 100.0), "mining")
	still.wait_h = 1000.0
	var tunnel := w.add_being(int(h.R), "social")
	tunnel.energy = 100.0
	tunnel.state = "transit"
	tunnel.corridor_id = int(h.A)
	tunnel.from_a = true
	var inside := w.add_being(int(h.R), "social")
	inside.energy = 100.0
	inside.wait_h = 1000.0
	_run(w, 100)
	t.eq(_fps(w).size(), 0, "a pausing miner, a tunnel walker and an idle being leave no prints")


func test_heavy_prints_for_builders_and_haulers_light_for_miners(t) -> void:
	# Builder with a job walking out (eva, after work).
	var hs := _swork(127)
	var ws: SimWorld = hs.w
	var site: Variant = hs.site
	var out := ws.add_being(int(hs.R), "builder")
	out.energy = 100.0
	out.wait_h = 1000.0
	out.state = "eva"
	out.after = "work"
	out.job = site
	out.construction_suit = true
	out.air_h = 1000.0
	out.x = 96.0
	out.y = 44.0
	out.heading = 0.0
	out.path = [Vector2(96.0 + 80.0, 44.0)]
	_walk_prints(t, ws, out, 6, true)
	t.eq(_fps(ws).size(), 2, "a builder with a job walking out leaves heavy prints")
	# Hauler with a load, and a miner walking out without one.
	var h := _world(128)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var hauler := _walker(w, int(h.R), Vector2(100.0, 100.0))
	hauler.mine = {"site": f, "door": R_DOOR, "home_id": int(h.R)}
	hauler.after = "haul"
	hauler.load = 6.0
	_walk_prints(t, w, hauler, 3, true)
	t.eq(_fps(w).size(), 1, "a hauler leaves a heavy print")
	var h2 := _world(129)
	var w2: SimWorld = h2.w
	var miner := _walker(w2, int(h2.R), Vector2(100.0, 100.0))
	miner.after = "enter"
	miner.job = null
	miner.load = 0.0
	_walk_prints(t, w2, miner, 3, false)
	t.eq(_fps(w2).size(), 1, "a miner without a load leaves a light print")


func test_footprints_cap_at_2200_and_the_oldest_go_first(t) -> void:
	var h := _world(131)
	var w: SimWorld = h.w
	if not _api(t, w, ["fp"]):
		return
	var walkers: Array[Being] = []
	for i in 12:
		walkers.append(_walker(w, int(h.R), Vector2(100.0, 100.0 + 20.0 * i)))
	var peak := 0
	var first_t := -1.0
	var capped_at := -1
	for i in 700:
		for b in walkers:
			b.energy = 100.0
		w.step()
		var fps := _fps(w)
		peak = maxi(peak, fps.size())
		if first_t < 0.0 and fps.size() > 0:
			first_t = float(_g(fps[0], "t"))
		if capped_at < 0 and fps.size() == 2200:
			capped_at = i
	t.eq(peak, 2200, "the list never exceeds 2,200 prints")
	t.eq(_fps(w).size(), 2200, "and stays full")
	t.check(capped_at > 0, "the cap was reached (step %d)" % capped_at)
	var min_t := 1e18
	for p in _fps(w):
		min_t = minf(min_t, float(_g(p, "t")))
	t.check(min_t > first_t + 1.0, "the oldest prints were dropped (oldest kept t %.2f vs first t %.2f)" % [min_t, first_t])


func test_footprints_expire_after_2_5_sols(t) -> void:
	var h := _world(132)
	var w: SimWorld = h.w
	if not _api(t, w, ["fp"]):
		return
	var b := _walker(w, int(h.R), Vector2(100.0, 100.0))
	_run(w, 3)
	t.eq(_fps(w).size(), 1, "one print")
	var made_t := float(_g(_fps(w)[0], "t"))
	b.enter(w, int(h.R))
	b.wait_h = 100000.0
	var limit := 2.5 * SOL_H
	var steps := 0
	var gone_at := -1
	while steps < 1260 and gone_at < 0:
		w.step()
		steps += 1
		b.energy = 100.0
		if _fps(w).size() == 0:
			gone_at = steps
		else:
			t.check(w.t - made_t <= limit + 1e-6, "a print older than 61.649 h is never kept (step %d)" % steps)
	t.check(gone_at > 0, "the print expired")
	t.eq(gone_at, 1233, "aged 61.6 h (1232 steps) it stays, 61.65 h (1233 steps, > 61.64925 + eps) it goes")


# ---------------------------------------------------------------- flags: suit_kind, lamp_on (spec section 4)

func test_suit_kind_of_a_miner_is_eva_in_every_outside_state_and_none_inside(t) -> void:
	var h := _world(141)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var out := _miner(w, int(h.R), f, Vector2(100.0, 100.0), "eva")
	out.path = [Vector2(3000.0, 100.0)]
	t.eq(out.suit_kind(), "eva", "walking out: eva")
	out.state = "mining"
	t.eq(out.suit_kind(), "eva", "mining: eva")
	out.state = "eva"
	out.after = "haul"
	out.load = 4.0
	t.eq(out.suit_kind(), "eva", "hauling: eva")
	out.returning = true
	out.after = "enter"
	t.eq(out.suit_kind(), "eva", "turned back: eva")
	# A builder-role being that mines wears the eva suit: the kind follows the activity, not the role.
	var bm := _miner(w, int(h.R), f, Vector2(100.0, 120.0), "mining")
	bm.role = "builder"
	t.eq(bm.job, null, "no job")
	t.eq(bm.suit_kind(), "eva", "a builder-role miner is eva, construction is for builders on a site")
	# Inside: none for every inside state, including the last step of the haul.
	var ins := w.add_being(int(h.R), "social")
	for st in ["idle", "to_door", "transit", "sleep"]:
		ins.state = st
		t.eq(ins.suit_kind(), "none", "inside (%s): none" % st)
	var hs := _world(142)
	var ws: SimWorld = hs.w
	var fs := ws.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var hl := _miner(ws, int(hs.R), fs, R_DOOR + Vector2(0.5, 0.0), "eva")
	hl.after = "haul"
	hl.load = 3.0
	hl.path = [R_DOOR]
	ws.step()
	t.eq(hl.state, "idle", "entered")
	t.eq(hl.suit_kind(), "none", "none once home")


func test_lamp_is_on_only_outside_and_at_night(t) -> void:
	var h := _world(143)
	var w: SimWorld = h.w
	if not _api(t, w, ["lamp"]):
		return
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var out := _walker(w, int(h.R), Vector2(100.0, 100.0))
	var mining := _miner(w, int(h.R), f, Vector2(100.0, 120.0), "mining", 1000.0)
	var ins := w.add_being(int(h.R), "social")
	ins.wait_h = 1000.0
	var on_hours := [21.5 + 1e-6, 23.0, 2.0, 5.4, 5.5 - 1e-6]
	var off_hours := [5.5 + 1e-6, 12.0, 21.4, 21.5 - 1e-6, 6.0, 20.0]
	for hr in on_hours:
		_hour_now(w, hr)
		t.check(out.call("lamp_on", w), "eva at %.6f: lamp on" % hr)
		t.check(mining.call("lamp_on", w), "mining at %.6f: lamp on" % hr)
		for st in ["idle", "to_door", "transit", "sleep"]:
			ins.state = st
			t.check(not ins.call("lamp_on", w), "inside (%s) at %.6f: lamp off" % [st, hr])
	for hr in off_hours:
		_hour_now(w, hr)
		t.check(not out.call("lamp_on", w), "eva at %.6f: lamp off" % hr)
		t.check(not mining.call("lamp_on", w), "mining at %.6f: lamp off" % hr)
	# Across a step: the hour after the step decides (the sim reads the clock after t += dt).
	_hour(w, 21.52)
	w.step()
	t.check(out.call("lamp_on", w), "21.52 after a step: on")
	_hour(w, 21.48)
	w.step()
	t.check(not out.call("lamp_on", w), "21.48 after a step: off")


# ---------------------------------------------------------------- drain per state, stepped for one hour (spec 6.1)

func test_eva_and_mining_drain_stepped_for_one_hour_from_80(t) -> void:
	var h := _world(151)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var eva := _walker(w, int(h.R), Vector2(100.0, 100.0))
	eva.energy = 80.0
	var mining := _miner(w, int(h.R), f, Vector2(100.0, 140.0), "mining", 36.0, 80.0)
	_run(w, 20)
	t.near(eva.energy, 78.0, 1e-6, "eva: 2 per hour, 20 steps")
	t.near(mining.energy, 77.4, 1e-6, "mining: 2.6 per hour, 20 steps")


# ---------------------------------------------------------------- balance target 7 (spec 8.5, 13)

const LONE_FIELD := Vector2(48.0 + 180.6, 80.0)

## One complete trip from R to a field at 180.6 px (r 16: trip time 30.575 < 30.6). Returns when the miner is home.
func _full_trip(seed_in: int) -> Dictionary:
	var h := _lone(seed_in)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(LONE_FIELD.x, LONE_FIELD.y, 300.0, 16.0)
	w.colony.ice = 60.0
	_hour(w, 6.0)
	var b := w.add_being(int(h.R), "social")
	b.energy = 100.0
	b.mine_intent = f
	b.wait_h = 0.0
	var steps := 0
	var mined := false
	while steps < 1500:
		w.buildings.last_short_t = w.t
		w.step()
		steps += 1
		if b.state == "mining":
			mined = true
		if mined and b.state == "idle" and b.mine == null:
			break
	return {"w": w, "b": b, "f": f, "steps": steps, "mined": mined, "ice0": 60.0}


func test_valid_trips_never_turn_back_for_air_over_30_seeds(t) -> void:
	var lowest := 1e9
	for s in 30:
		var r := _full_trip(7000 + s)
		var w: SimWorld = r.w
		var b: Being = r.b
		if not (r.mined and b.state == "idle" and b.mine == null):
			t.check(false, "seed %d: the trip completed (%d steps)" % [7000 + s, r.steps])
			return
		t.eq(int(w.stats.turn_backs_air), 0, "seed %d: no air turn-back" % (7000 + s))
		t.eq(int(w.stats.turn_backs_exhausted), 0, "seed %d: no exhausted turn-back" % (7000 + s))
		t.eq(int(w.stats.deaths.suffocated_outside), 0, "seed %d: nobody suffocated" % (7000 + s))
		t.check(w.colony.ice > 60.0 + 3.0, "seed %d: a load of ice came home (ice %.2f)" % [7000 + s, w.colony.ice])
		lowest = minf(lowest, r.f.amount)
	t.check(lowest < 300.0, "the field shrank")


func test_the_longest_shift_at_the_far_edge_keeps_about_a_third_of_an_hour_of_air(t) -> void:
	# Worst case of spec 8.5: field at the filter edge (d + r just under 196.8), arrival and wander pinned to the far side
	# (centre + 0.8 r away from the door), longest shift 9 h. Margin = air - (dist / 16 + 2.5) is about 0.3 h.
	var h := _lone(161)
	var w: SimWorld = h.w
	var f := w.resources.add_ice_field(LONE_FIELD.x, LONE_FIELD.y, 300.0, 16.0)
	var far := Vector2(LONE_FIELD.x + 0.8 * 16.0, 80.0)
	_hour(w, 6.0)
	var b := w.add_being(int(h.R), "social")
	b.energy = 100.0
	b.mine_intent = f
	b.wait_h = 0.0
	var steps := 0
	while b.state != "eva" and steps < 400:
		w.buildings.last_short_t = w.t
		w.step()
		steps += 1
	t.eq(b.state, "eva", "suited up")
	var pts := _pts(b)
	if pts.size() < 2:
		t.check(false, "path [door, arrival point]")
		return
	pts[pts.size() - 1] = far
	b.path = pts
	var min_margin := 99.0
	var shift_set := false
	var last_air := 0.0
	var mining_steps := 0
	steps = 0
	while steps < 1500:
		w.buildings.last_short_t = w.t
		if b.state == "eva" and b.after == "haul":
			last_air = _f(b.air_h)
		w.step()
		steps += 1
		if b.state == "mining":
			if not shift_set:
				b.work_left_h = 9.0
				shift_set = true
			b.wander_target = far
			mining_steps += 1
			var margin := _f(b.air_h) - (_pos(b).distance_to(R_DOOR) / 16.0 + 2.5)
			min_margin = minf(min_margin, margin)
		if shift_set and b.state == "idle" and b.mine == null:
			break
	t.check(shift_set and b.state == "idle" and b.mine == null, "home after the longest shift")
	t.eq(int(w.stats.turn_backs_air), 0, "no air turn-back at the worst case")
	t.between(min_margin, 0.0, 0.6, "thinnest air margin %.3f h (spec: about 0.3)" % min_margin)
	t.between(last_air, 2.5, 3.4, "arrives home with %.2f h of air (out 12.1 + shift 9 + back 12.1 of 36)" % last_air)
	t.between(float(mining_steps) * DT, 8.8, 9.2, "the shift lasted 9 h")
	t.check(w.colony.ice > 60.0 + 3.0, "and brought ice home")


# ---------------------------------------------------------------- step 8 decisions (spec "Implementation notes (step 8)")

func test_builder_walking_home_after_the_shift_leaves_heavy_prints(t) -> void:
	# Decision: heavy = construction suit on, or load > 0. The shift is over (job null, after enter), but
	# the suit stays on until the builder enters, so the walk home is heavy.
	var hs := _swork(130)
	var w: SimWorld = hs.w
	if not _api(t, w, ["fp"]):
		return
	var p1: Vector2 = _sb(w).corridor.p1
	var b := w.add_being(int(hs.R), "builder")
	b.energy = 100.0
	b.wait_h = 1000.0
	b.state = "eva"
	b.after = "enter"
	b.job = null
	b.construction_suit = true
	b.air_h = 1000.0
	b.x = p1.x + 60.0
	b.y = p1.y
	b.heading = PI
	b.path = [p1]
	t.eq(b.suit_kind(), "construction", "still the construction suit with job null")
	_walk_prints(t, w, b, 9, true)
	t.eq(_fps(w).size(), 3, "9 steps of EVA walking leave 3 prints, all heavy")
	# Control: the same walk in the plain EVA suit with no load leaves light prints.
	var w2: SimWorld = _swork(131).w
	var c := w2.add_being(int(w2.buildings.get_building(1).id), "builder")
	c.energy = 100.0
	c.wait_h = 1000.0
	c.state = "eva"
	c.after = "enter"
	c.job = null
	c.construction_suit = false
	c.air_h = 1000.0
	c.x = p1.x + 60.0
	c.y = p1.y
	c.heading = PI
	c.path = [p1]
	_walk_prints(t, w2, c, 9, false)
	t.eq(_fps(w2).size(), 3, "the control also leaves 3 prints, all light")


func test_an_exhausted_miners_partial_load_reduces_the_field_by_exactly_the_load(t) -> void:
	for s in 20:
		var h := _world(2200 + s)
		var w: SimWorld = h.w
		var f := w.resources.add_ice_field(100.0, 100.0, 300.0, 20.0)
		var b := _miner(w, int(h.R), f, Vector2(100.0, 100.0), "mining", 36.0, 12.1)
		var amount0: float = f.amount
		w.step()
		if not b.returning:
			t.check(false, "seed %d: the miner turned back" % s)
			return
		t.between(b.load, 2.0, 5.0, "seed %d: partial load in 2..5" % s)
		t.near(f.amount, amount0 - b.load, 1e-12, "seed %d: field.amount fell by exactly the load" % s)
		t.eq(int(w.stats.turn_backs_exhausted), 1, "seed %d: an exhausted turn-back" % s)
	# A load bigger than what is left is limited to it, and the field then runs dry (and is removed).
	var h2 := _world(2230)
	var w2: SimWorld = h2.w
	var small := w2.resources.add_ice_field(100.0, 100.0, 1.0, 20.0)
	var m := _miner(w2, int(h2.R), small, Vector2(100.0, 100.0), "mining", 36.0, 12.1)
	w2.step()
	t.near(m.load, 1.0, 1e-12, "the load is limited to the 1.0 left")
	t.near(small.amount, 0.0, 1e-12, "the field is empty")
	t.check(not w2.resources.ice_fields.has(small), "and it left the list (usual dry-up rule)")
	t.eq(int(w2.stats.ice_dry), 1, "ice_dry counted once")


func test_each_turn_back_kind_logs_its_own_line_once(t) -> void:
	# Air: kind suit_low_air, once, nothing for exhausted.
	var go: Dictionary = _mining_turn(12.54, 2300)
	var w: SimWorld = go.w
	var b: Being = go.b
	for i in 150:
		b.energy = 100.0
		w.step()
	t.eq(_logs(w, "suit_low_air"), 1, "air turn-back: one suit_low_air line")
	t.eq(_logs(w, "exhausted"), 0, "air turn-back: no exhausted line")
	var line := {}
	for e in w.log:
		if e.kind == "suit_low_air":
			line = e
	t.eq(int(line.get("being_id", -1)), b.id, "the air line names the being")
	# Exhausted: kind exhausted, once, nothing for suit_low_air.
	var h := _world(2301)
	var w2: SimWorld = h.w
	var f := w2.resources.add_ice_field(100.0, 100.0, 300.0, 20.0)
	var m := _miner(w2, int(h.R), f, Vector2(100.0, 100.0), "mining", 36.0, 12.1)
	for i in 150:
		m.energy = minf(m.energy, 11.0)
		w2.step()
	t.check(m.state != "mining", "the exhausted miner left the field")
	t.eq(_logs(w2, "exhausted"), 1, "exhausted turn-back: one exhausted line")
	t.eq(_logs(w2, "suit_low_air"), 0, "exhausted turn-back: no suit_low_air line")
	t.eq(int(w2.stats.turn_backs_exhausted), 1, "counted once")
	var line2 := {}
	for e in w2.log:
		if e.kind == "exhausted":
			line2 = e
	t.eq(int(line2.get("being_id", -1)), m.id, "the exhausted line names the being")


func test_founder_colony_runs_without_air_turn_backs_or_suffocation(t) -> void:
	# Balance target 7 and 2 in a real founder world: 12 sols at two seeds. Mining must actually happen.
	for seed_in in [42, 7]:
		var w := SimWorld.new(seed_in)
		var steps := int(12.0 * SOL_H / DT)
		for i in steps:
			w.step()
		t.eq(int(w.stats.turn_backs_air), 0, "seed %d: zero air turn-backs" % seed_in)
		t.eq(int(w.stats.deaths.suffocated_outside), 0, "seed %d: no EVA deaths" % seed_in)
		t.check(int(w.stats.mining_trips) >= 1, "seed %d: the colony mined (trips %d)" % [seed_in, int(w.stats.mining_trips)])
		for b in w.beings:
			if b.air_h != null:
				t.check(float(b.air_h) > 0.0, "seed %d: everybody outside has air" % seed_in)


# ---------------------------------------------------------------- final review follow-ups (step 13)

func test_resumed_intent_cancels_when_the_launch_door_moved_beyond_the_trip_limit(t) -> void:
	var h := _world(93)
	var w: SimWorld = h.w
	# Reachable from the A door, too far from the R door.
	var spot: Vector2 = A_DOOR + Vector2(0.0, 174.0)
	var f := w.resources.add_ice_field(spot.x, spot.y, 300.0, 16.0)
	var ra := w.resources.launch_for(f)
	t.check(ra != null and w.resources.trip_time(f) < w.resources.trip_limit(), "control: trip from the A door fits a tank")
	w.set_offline(int(h.A), true)
	w.set_offline(int(h.W), true)
	t.check(not (w.resources.trip_time(f) < w.resources.trip_limit()), "with A and the workshop dark the nearest door is too far")
	_hour(w, 12.0)
	w.t += DT
	var b := w.add_being(int(h.R), "social")
	b.energy = 100.0
	b.mine_intent = f
	var o2: float = w.colony.oxygen
	b.decide(w)
	t.check(b.mine_intent == null, "the intent is cancelled")
	t.check(b.mine == null and not b.suit_up, "no trip starts")
	t.near(w.colony.oxygen, o2, 1e-12, "no oxygen spent")


func test_site_dug_accumulates_what_is_dug(t) -> void:
	var w := SimWorld.new(42)
	for i in 2000:
		w.step()
	var dug := 0.0
	for s: Resources.Site in w.resources.ice_fields + w.resources.pits:
		dug += s.dug
	t.check(int(w.stats.get("mining_trips", 0)) > 0, "control: mining happened")
	t.check(dug > 0.0, "dug totals grow with mining (%.1f)" % dug)


func test_log_carries_the_clock_sol(t) -> void:
	var w := SimWorld.new(42)
	var e: Dictionary = w.log[0]
	t.eq(int(e.clock_sol), 1, "founders landed on clock sol 1")
	t.eq(int(e.sol), 0, "elapsed sol stays 0-based")
