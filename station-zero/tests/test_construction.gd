extends RefCounted
## Task 1, step 7: construction. Spec: docs/specs/life-support-power.md sections 3 (comparators), 4 (Construction
## site, Being), 5 (phases 6, 8, 9), 6.4 (join construction), 6.5 and 6.5b (suit-up at p1, finish_eva, enter, "site
## gone"), 7.4 (build decision, choose_kind, cost), 7.5 (progress, work state, waiting_for_builders), 16 (stats), the
## "Implementation notes" of steps 4 to 6 and the construction test lists ("Tests (tests/test_power.gd,
## tests/test_construction.gd)", the EVA arrival table of tests/test_beings.gd, the suit_kind flag of test_suits).
##
## Existing API used (steps 1..6): SimWorld.new(seed, {"blank": true}), add_building / add_being / set_offline, step(),
##  t, step_index, sol(), rng, log, stats (top-level keys, as in steps 4 to 6), colony.regolith / oxygen / food /
##  o2_net() / food_net(), buildings.add / add_attached / get_building / list / next_hop / draw / supply / margin /
##  count, Building.built / online() / finished() / corridor {parent_id, p1, p2, len, rect} / door(), Being fields
##  (state, energy, wait_h, building_id, suit_up, sleep_intent, job, air_h, x, y, heading, path, after, returning,
##  work_left_h, corridor_id, persona.traits), Being.is_inside(), SimData caches (edited and restored for one test).
##
## API ASSUMED beyond the existing one (extended the simplest way; every name below is new):
##  - SimWorld.start_site(kind: String, spot: Dictionary = {}) -> bool  (the spec's "start"). If a site exists, or
##    colony.regolith < Buildings.build_cost(kind), or no spot is found, it returns false and changes NOTHING
##    (no regolith, no building, no log, no stats). Otherwise it creates the building with built = 0 (a site,
##    draw 2), with its corridor, subtracts the cost from colony.regolith, sets Buildings.site, counts
##    stats.builds_started and logs "ground_broken" (with building_id). `spot` is optional: {parent_id, dir, tw, th,
##    gap} places the site with add_attached semantics (the test seam for hand-made worlds, no rng); an empty spot
##    runs Buildings.find_spot(rng) (spec 7.3). The build decision (phase 8) is expected to go through the same
##    code, so the tests below drive it with start_site or with step().
##  - Buildings.site: null, or a record with fields building_id, parent_id, last_work_t (spec section 4). A record
##    object or a Dictionary both work for these tests (only field reads and writes are used). last_work_t starts at
##    the creation t. Tests may write `buildings.site = null` to clear the site ("site gone") and
##    `site.last_work_t` to age it. A being's `job` is that same record (job.building_id is read, spec 6.5b).
##  - Buildings.build_cost(kind: String) -> int/float = (18 if reactor or green_room else 28) + 4 x Buildings.count()
##    (every building in the list, built or not), read from data/buildings.json build.*.
##  - SimWorld.choose_kind() -> String (spec 7.4): reads margin, o2_net, food_net, stocks, pop, habitats (finished,
##    offline included) and draws from world.rng only in the last rule (one rng.pick).
##  - Being.suit_kind() -> String: "none", "construction" or "eva" (spec section 4).
##  - Being.path is an Array of Vector2 (waypoints); x and y are floats; test writes follow that.
##  - New top-level stats, all 0 (floats) in a fresh world: hours_waiting_regolith, hours_site_no_crew, site_busy_h;
##    and first_new_reactor_sol = null until a non-founding reactor is finished (then the elapsed sol, an int).
##    stats.need_regolith and stats.waiting_for_builders count LOGGED events (rate limited), while
##    hours_waiting_regolith adds the 5 h check interval at EVERY build check with a ready builder and too little
##    regolith (spec section 16). Log entries "ground_broken" and "building_done" carry building_id.
##  - The build timer is an accumulator that starts at 0 when the world is created and fires on steps 100, 200, ...
##    whether or not a builder is ready (spec section 3). It is only observed through its effects.
##  - The RNG is observed through `world.rng._rng.state` (the private RandomNumberGenerator of SimRng); tests that use
##    it park every being with wait_h = 1000 so that no decision draws.
##  - Beings that stand outside for a long run get air_h = 1000 or energy 100 written each step, so that the EVA air
##    tank and the exhausted turn-back (step 8) can never interfere ("assume the suit air does not run out").
##
## Spec facts the numbers rest on (and where they differ from a literal reading):
##  - Order inside one step: phase 6 drains energy first, so progress (phase 9) reads the energy AFTER the drain. The
##    progress test therefore writes 80.15 and expects the rate of energy 80 (the spec's 80.15 to 80 case).
##  - A being that arrives at the site in phase 6 is already crew in phase 9 of the same step, so tests measure
##    progress and the hours stats as deltas that start AFTER the arrival step.
##  - need_regolith repeats once per 2 sols: the first log is at step 100, the second at step 1100 (first check
##    with t - warn_t > 2 sols + STEP_EPS, i.e. 986.4 steps later, rounded up to the 100-step grid).
##  - waiting_for_builders: first line on step 494 after the site was created, the next 494 steps later (988).
##  - choose_kind: the food_net rule can never fire on its own with the shipped numbers (o2_net fails first for every
##    number of green rooms), so the food test lowers production.food_per_green_room to 0.5 for its worlds (the data
##    cache is edited and restored).
##  - suit_kind of a builder who has finished its shift and walks home (job = null, after = enter) is NOT asserted:
##    the spec says "construction ... eva going to or from the site" but also sets job = null at shift end.
##
## Layout of the hand-made world (_world): reactor R (id 1, tile 0,0, 12x10), a parked reactor (id 2, far away, so
## power never shorts anything: supply 28), workshop Wk (id 3) below R (gap 6, corridor 48 px). The site is placed
## right of R: SPOT = {parent_id 1, dir r, 10x8, gap 5}, rect (17,1,10,8), corridor p1 (96,44) p2 (136,44), len 40.

const DT := 0.05
const SOL_H := 24.6597
const SPOT := {"parent_id": 1, "dir": "r", "tw": 10, "th": 8, "gap": 5}
const INSET := 5.0


# ---------------------------------------------------------------- helpers

func _world(seed_in: int = 1) -> Dictionary:
	var w := SimWorld.new(seed_in, {"blank": true})
	var r := w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	w.add_building("reactor", 300, 300)
	var wk := w.buildings.add_attached("workshop", r.id, "d", 12, 9, 6)
	return {"w": w, "R": r.id, "Wk": wk.id}


## False (with one failing check) when the new API is missing, so a test stops cleanly instead of crashing.
func _api(t, w: SimWorld) -> bool:
	var ok := true
	if not w.has_method("start_site"):
		t.check(false, "missing SimWorld.start_site()")
		ok = false
	if not w.has_method("choose_kind"):
		t.check(false, "missing SimWorld.choose_kind()")
		ok = false
	if not w.buildings.has_method("build_cost"):
		t.check(false, "missing Buildings.build_cost()")
		ok = false
	if not ("site" in w.buildings):
		t.check(false, "missing Buildings.site")
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


func _stat(w: SimWorld, key: String) -> float:
	return float(w.stats.get(key, -1.0))


func _rng_state(w: SimWorld) -> int:
	return w.rng._rng.state


func _sb(w: SimWorld) -> Buildings.Building:
	return w.buildings.get_building(int(w.buildings.site.building_id))


func _rect_px(b: Buildings.Building) -> Rect2:
	return Rect2(b.tx * 8.0, b.ty * 8.0, b.tw * 8.0, b.th * 8.0)


func _centre(b: Buildings.Building) -> Vector2:
	return _rect_px(b).get_center()


func _in_inset(p: Vector2, b: Buildings.Building, slack: float = 0.0) -> bool:
	return _rect_px(b).grow(-INSET + slack).has_point(p)


## Site of `kind` at SPOT with plenty of regolith. Returns the site record.
func _start(t, w: SimWorld, kind: String = "habitat", spot: Dictionary = SPOT) -> Variant:
	w.colony.regolith = 500.0
	t.check(w.start_site(kind, spot), "start_site(%s) succeeded" % kind)
	return w.buildings.site


## A builder already outside, one waypoint from the site centre, ready to arrive and start work next step.
func _worker(w: SimWorld, drive: float = 0.7, energy: float = 80.0) -> Being:
	var site: Variant = w.buildings.site
	var b := w.add_being(int(site.parent_id), "builder")
	_traits(b, {"drive": drive})
	b.energy = energy
	b.wait_h = 1000.0
	var c := _centre(_sb(w))
	b.state = "eva"
	b.after = "work"
	b.job = site
	b.air_h = 1000.0
	b.x = c.x
	b.y = c.y
	b.heading = 0.0
	b.path = [c]
	b.returning = false
	return b


## One step: every worker arrives and starts work; shifts are made long so nobody leaves.
func _arrive(t, w: SimWorld, workers: Array) -> void:
	w.step()
	for b: Being in workers:
		t.eq(b.state, "work", "worker is in state work after arriving")
		b.work_left_h = 1000.0


## A being standing outside with a one-point path under its feet (arrives and finishes in one step).
func _walker(w: SimWorld, building_id: int, after: Variant, job: Variant) -> Being:
	var b := w.add_being(building_id, "builder")
	b.state = "eva"
	b.after = after
	b.job = job
	b.air_h = 20.0
	b.x = 60.0
	b.y = 60.0
	b.heading = 0.0
	b.path = [Vector2(60.0, 60.0)]
	b.returning = after == "enter" or after == null
	b.wait_h = 1000.0
	return b


func _rate(drive: float, energy: float) -> float:
	return (0.6 + drive) * (0.55 + energy / 220.0) * DT / 34.0


## World for choose_kind: `reactors` reactors then `kinds` (all finished), `pop` beings, stocks high.
func _cw(reactors: int, kinds: Array, pop: int) -> SimWorld:
	var w := SimWorld.new(3, {"blank": true})
	for i in reactors:
		w.add_building("reactor", 40 * i, 60)
	for i in kinds.size():
		w.add_building(kinds[i], 20 * (i + 1), 0)
	for i in pop:
		w.add_being(1, "social")
	w.colony.oxygen = 1000.0
	w.colony.food = 1000.0
	return w


func _tally(w: SimWorld, calls: int) -> Dictionary:
	var out := {}
	for i in calls:
		var k: String = w.choose_kind()
		out[k] = int(out.get(k, 0)) + 1
	return out


## A builder parked in `where` ("workshop", "reactor", ...) with every decision disabled (wait_h 1000).
func _parked(w: SimWorld, building_id: int, role: String = "builder", energy: float = 90.0) -> Being:
	var b := w.add_being(building_id, role)
	b.energy = energy
	b.wait_h = 1000.0
	return b


# ---------------------------------------------------------------- cost, regolith spend, one site

func test_cost_is_18_or_28_plus_4_per_building(t) -> void:
	var h := _world()
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	w.add_building("habitat", 600, 0)
	t.eq(w.buildings.count(), 4, "four buildings")
	for k in ["reactor", "green_room"]:
		t.eq(int(w.buildings.build_cost(k)), 34, "%s: 18 + 4 x 4" % k)
	for k in ["habitat", "workshop", "archive", "comms"]:
		t.eq(int(w.buildings.build_cost(k)), 44, "%s: 28 + 4 x 4" % k)
	w.add_building("comms", 700, 0)
	t.eq(int(w.buildings.build_cost("reactor")), 38, "reactor with five buildings: 18 + 20")
	t.eq(int(w.buildings.build_cost("habitat")), 48, "habitat with five buildings: 28 + 20 (the spec's second site)")
	# An unfinished building counts too (every building in the list).
	w.buildings.add("archive", 800, 0, 0.5)
	t.eq(int(w.buildings.build_cost("habitat")), 52, "a site counts as a building: 28 + 24")


func test_start_site_spends_the_cost_and_creates_an_unfinished_building(t) -> void:
	var h := _world()
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	t.check(w.buildings.site == null, "no site in a fresh world")
	w.colony.regolith = 100.0
	var draw0: float = w.buildings.draw()
	var n0: int = w.buildings.count()
	var cost: float = 28.0 + 4.0 * n0
	t.check(w.start_site("habitat", SPOT), "start_site succeeds")
	var site: Variant = w.buildings.site
	t.check(site != null, "a site exists")
	t.near(w.colony.regolith, 100.0 - cost, 1e-9, "regolith spent: 28 + 4 x 3 = 40")
	t.eq(w.buildings.count(), n0 + 1, "one building added")
	var sb := _sb(w)
	t.eq(sb.kind, "habitat", "site kind")
	t.eq(sb.built, 0.0, "built starts at 0")
	t.check(not sb.finished() and not sb.online(), "a site is neither finished nor online")
	t.eq(int(site.parent_id), int(h.R), "site parent is the reactor")
	t.check(sb.corridor != null and int(sb.corridor.parent_id) == int(h.R), "the site has a corridor to its parent")
	t.near(float(site.last_work_t), w.t, 1e-9, "last_work_t starts at the creation time (spec section 14)")
	t.near(w.buildings.draw(), draw0 + 2.0, 1e-9, "a site draws 2")
	t.eq(w.buildings.next_hop(int(h.R), sb.id), 0, "the unfinished corridor is not traversable")
	t.eq(int(w.stats.builds_started), 1, "builds_started")
	t.eq(_logs(w, "ground_broken"), 1, "ground_broken logged")
	for e in w.log:
		if e.kind == "ground_broken":
			t.eq(int(e.building_id), sb.id, "ground_broken carries the building id")


func test_regolith_is_the_gate_at_exactly_the_cost(t) -> void:
	var h := _world()
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	var n0: int = w.buildings.count()
	var cost: float = 18.0 + 4.0 * n0
	w.colony.regolith = cost - 0.01
	t.check(not w.start_site("green_room", SPOT), "regolith just below the cost: refused")
	t.near(w.colony.regolith, cost - 0.01, 1e-12, "nothing charged")
	t.eq(w.buildings.count(), n0, "no building added")
	t.check(w.buildings.site == null and int(w.stats.builds_started) == 0, "no site, no stat")
	t.eq(_logs(w, "ground_broken"), 0, "nothing logged")
	w.colony.regolith = cost
	t.check(w.start_site("green_room", SPOT), "regolith exactly the cost: allowed")
	t.near(w.colony.regolith, 0.0, 1e-9, "all of it spent")


func test_one_site_at_a_time(t) -> void:
	var h := _world()
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	var site: Variant = _start(t, w)
	var reg: float = w.colony.regolith
	var n: int = w.buildings.count()
	var logs: int = w.log.size()
	var started: int = int(w.stats.builds_started)
	var id0: int = int(site.building_id)
	t.check(not w.start_site("reactor", {"parent_id": 1, "dir": "u", "tw": 10, "th": 8, "gap": 5}), "a second start returns false")
	t.check(not w.start_site("comms"), "also without a spot")
	t.near(w.colony.regolith, reg, 1e-12, "regolith unchanged")
	t.eq(w.buildings.count(), n, "no building added")
	t.eq(w.log.size(), logs, "nothing logged")
	t.eq(int(w.stats.builds_started), started, "builds_started unchanged")
	t.eq(int(w.buildings.site.building_id), id0, "the site is still the first one")


func test_start_site_without_a_spot_uses_find_spot(t) -> void:
	var h := _world(9)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	w.colony.regolith = 500.0
	t.check(w.start_site("comms"), "a spot was found")
	var sb := _sb(w)
	var rect := Rect2i(sb.tx, sb.ty, sb.tw, sb.th)
	for o in w.buildings.list:
		if o.id != sb.id:
			t.check(Buildings.separation(rect, Rect2i(o.tx, o.ty, o.tw, o.th)) >= 2, "site keeps margin 2 from building %d" % o.id)
	t.check(sb.tw >= 10 and sb.tw <= 14 and sb.th >= 8 and sb.th <= 10, "size from data")
	t.check(sb.corridor != null and w.buildings.get_building(int(sb.corridor.parent_id)) != null, "has a parent corridor")


# ---------------------------------------------------------------- choose_kind

func test_choose_kind_reactor_first(t) -> void:
	# margin 4 (draw 10 on one reactor) and o2_net exactly 0.1 (1 green room, 26 beings): reactor beats green room.
	var w := _cw(1, ["green_room", "workshop", "archive"], 26)
	if not _api(t, w):
		return
	t.near(w.buildings.margin(), 4.0, 1e-9, "setup: margin 4")
	t.near(w.colony.o2_net(), 0.1, 1e-9, "setup: o2_net 0.1")
	var s0 := _rng_state(w)
	t.eq(w.choose_kind(), "reactor", "margin 4 returns reactor even when o2_net is 0.1")
	t.eq(_rng_state(w), s0, "rule 1 draws nothing")
	# And with a margin of exactly 5 the reactor rule does not fire: o2_net 0.35 returns green room.
	var w2 := _cw(1, ["green_room", "habitat", "archive"], 21)
	t.near(w2.buildings.margin(), 5.0, 1e-9, "setup: margin 5")
	t.near(w2.colony.o2_net(), 0.35, 1e-9, "setup: o2_net 0.35")
	var s1 := _rng_state(w2)
	t.eq(w2.choose_kind(), "green_room", "margin 5 and o2_net 0.35 returns green room")
	t.eq(_rng_state(w2), s1, "rule 2 draws nothing")
	# Margin 5 with healthy nets and a crowd skips the reactor: habitat.
	var w3 := _cw(1, ["green_room", "habitat", "archive"], 7)
	t.near(w3.buildings.margin(), 5.0, 1e-9, "setup: margin 5")
	t.eq(w3.choose_kind(), "habitat", "margin 5 is not below 5")
	# An unfinished site's draw counts against the margin (supply 14, green room 4 + site 2 + habitat 3 + workshop 4 = 13).
	var w4 := _cw(1, ["green_room", "habitat", "workshop"], 7)
	w4.buildings.add("archive", 900, 0, 0.3)
	t.near(w4.buildings.margin(), 1.0, 1e-9, "setup: margin 1 with the site")
	t.eq(w4.choose_kind(), "reactor", "site draw is in the margin")


func test_choose_kind_o2_net_floor_is_0_4(t) -> void:
	var low := _cw(2, ["green_room", "habitat", "workshop"], 21)
	if not _api(t, low):
		return
	t.near(low.colony.o2_net(), 0.35, 1e-9, "setup: o2_net 0.35")
	t.eq(low.choose_kind(), "green_room", "o2_net 0.35 < 0.4: green room")
	var ok := _cw(2, ["green_room", "habitat", "workshop"], 19)
	t.near(ok.colony.o2_net(), 0.45, 1e-9, "setup: o2_net 0.45")
	var s0 := _rng_state(ok)
	t.eq(ok.choose_kind(), "habitat", "o2_net 0.45 >= 0.4: falls through to the crowd rule (19 + 2 > 5)")
	t.eq(_rng_state(ok), s0, "rule 3 draws nothing")


func test_choose_kind_food_net_floor_is_0_25(t) -> void:
	var prod: Dictionary = SimData.colony().production
	var old: Variant = prod.food_per_green_room
	prod.food_per_green_room = 0.5
	var low := _cw(2, ["green_room", "habitat", "workshop"], 8)
	if not _api(t, low):
		prod.food_per_green_room = old
		return
	t.near(low.colony.food_net(), 0.22, 1e-9, "setup: food_net 0.22")
	t.check(low.colony.o2_net() >= 0.4, "setup: o2_net is fine (%.3f)" % low.colony.o2_net())
	t.eq(low.choose_kind(), "green_room", "food_net 0.22 < 0.25: green room")
	var ok := _cw(2, ["green_room", "habitat", "workshop"], 7)
	t.near(ok.colony.food_net(), 0.255, 1e-9, "setup: food_net 0.255")
	t.eq(ok.choose_kind(), "habitat", "food_net 0.255 >= 0.25: habitat (7 + 2 > 5)")
	prod.food_per_green_room = old


func test_choose_kind_stock_floor_is_three_sols_of_use(t) -> void:
	# pop 7: oxygen floor 3 x 24.6597 x 7 x 0.05 = 25.89, food floor 3 x 24.6597 x 7 x 0.035 = 18.12. Nets are fine.
	var w := _cw(2, ["green_room", "habitat", "workshop"], 7)
	if not _api(t, w):
		return
	t.check(w.colony.o2_net() >= 0.4 and w.colony.food_net() >= 0.25, "setup: nets fine")
	w.colony.oxygen = 25.4
	t.eq(w.choose_kind(), "green_room", "oxygen 25.4 < 25.89")
	w.colony.oxygen = 26.4
	t.eq(w.choose_kind(), "habitat", "oxygen 26.4 > 25.89")
	w.colony.food = 17.9
	t.eq(w.choose_kind(), "green_room", "food 17.9 < 18.12")
	w.colony.food = 18.4
	t.eq(w.choose_kind(), "habitat", "food 18.4 > 18.12")
	# The floor scales with the population: pop 14 doubles it (oxygen floor 51.8).
	for i in 7:
		w.add_being(1, "social")
	w.colony.food = 1000.0
	w.colony.oxygen = 45.0
	t.check(w.colony.o2_net() >= 0.4, "setup: o2_net still fine with 14 beings")
	t.eq(w.choose_kind(), "green_room", "oxygen 45 < 51.8 with 14 beings")


func test_choose_kind_crowd_rule_counts_finished_habitats_offline_included(t) -> void:
	var w := _cw(2, ["green_room", "habitat", "workshop"], 4)
	if not _api(t, w):
		return
	# pop 4, one habitat: 6 > 5 -> always habitat; pop 3: 5 > 5 is false -> the weighted pool.
	var s0 := _rng_state(w)
	t.eq(w.choose_kind(), "habitat", "pop 4, one habitat: habitat")
	t.eq(_rng_state(w), s0, "rule 3 draws nothing")
	var all4 := _tally(w, 200)
	t.eq(int(all4.get("habitat", 0)), 200, "pop 4: habitat every time")
	w.beings.pop_back()
	var p3 := _tally(w, 600)
	t.check(p3.size() >= 4, "pop 3, one habitat: the pool is used (kinds seen %s)" % str(p3.keys()))
	# Two habitats, one offline: still two finished habitats. pop 9: 11 > 10 -> habitat; pop 8: 10 > 10 is false.
	var w2 := _cw(2, ["green_room", "habitat", "habitat", "workshop"], 9)
	w2.set_offline(w2.buildings.list[3].id, true)
	t.eq(w2.buildings.list[3].kind, "habitat", "setup: the offline one is a habitat")
	w2.buildings.last_short_t = w2.t
	t.eq(_tally(w2, 100).get("habitat", 0), 100, "pop 9, two habitats (one offline): habitat")
	w2.beings.pop_back()
	var p8 := _tally(w2, 600)
	t.check(p8.size() >= 4, "pop 8: offline habitats still count, so the crowd rule is off (kinds %s)" % str(p8.keys()))


func test_choose_kind_pool_weights_and_workshop_cap(t) -> void:
	# pop 3, one habitat, margin 17: the weighted pool [archive, comms, green_room, habitat, habitat] + workshop below 3.
	var w := _cw(2, ["green_room", "habitat", "workshop"], 3)
	if not _api(t, w):
		return
	t.check(w.buildings.margin() >= 5.0 and w.colony.o2_net() >= 0.4, "setup: no rule fires")
	var n := 6000
	var c := _tally(w, n)
	for k in c:
		t.check(["archive", "comms", "green_room", "habitat", "workshop"].has(k), "kind %s is in the pool" % k)
	for k in ["archive", "comms", "green_room", "workshop"]:
		t.between(float(c.get(k, 0)) / n, 1.0 / 6.0 - 0.025, 1.0 / 6.0 + 0.025, "%s share with one workshop (1/6)" % k)
	t.between(float(c.get("habitat", 0)) / n, 1.0 / 3.0 - 0.03, 1.0 / 3.0 + 0.03, "habitat share (2/6)")
	# Three finished workshops: no more workshops, pool of five.
	var w3 := _cw(2, ["green_room", "habitat", "workshop", "workshop", "workshop"], 3)
	t.check(w3.buildings.margin() >= 5.0, "setup: margin %.1f" % w3.buildings.margin())
	var c3 := _tally(w3, n)
	t.eq(int(c3.get("workshop", 0)), 0, "no workshop at three workshops")
	for k in ["archive", "comms", "green_room"]:
		t.between(float(c3.get(k, 0)) / n, 0.2 - 0.03, 0.2 + 0.03, "%s share with the cap reached (1/5)" % k)
	t.between(float(c3.get("habitat", 0)) / n, 0.4 - 0.03, 0.4 + 0.03, "habitat share (2/5)")
	# Two workshops still allow a third.
	var w2 := _cw(2, ["green_room", "habitat", "workshop", "workshop"], 3)
	t.check(int(_tally(w2, 600).get("workshop", 0)) > 0, "two workshops: a third may be chosen")
	# A pool pick is exactly one rng draw.
	var s0 := _rng_state(w)
	var ref := RandomNumberGenerator.new()
	ref.state = s0
	ref.randi_range(0, 5)
	w.choose_kind()
	t.eq(_rng_state(w), ref.state, "the pool pick is a single randi_range draw")


# ---------------------------------------------------------------- the build decision (phase 8)

func test_build_check_fires_on_step_100_and_is_a_single_site(t) -> void:
	var h := _world(11)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_parked(w, int(h.Wk))
	w.colony.regolith = 500.0
	for i in 99:
		w.step()
	t.check(w.buildings.site == null, "no site after 99 steps (the check is not on the 99th)")
	t.near(w.colony.regolith, 500.0, 1e-12, "nothing spent yet")
	w.step()
	t.eq(w.step_index, 100, "this is step 100")
	t.check(w.buildings.site != null, "the 100th step (acc >= 5 h - eps) starts the site, not the 101st")
	# One pop, no green room: o2_net -0.05 < 0.4 -> green room, cost 18 + 4 x 3 buildings.
	t.eq(_sb(w).kind, "green_room", "first kind by choose_kind: green room")
	t.near(w.colony.regolith, 500.0 - 30.0, 1e-9, "cost 30 spent")
	t.eq(int(w.stats.builds_started), 1, "builds_started")
	t.eq(_logs(w, "ground_broken"), 1, "ground_broken logged")
	# While the site stands, further checks do nothing: no second site, no draws, no regolith spent.
	var s0 := _rng_state(w)
	for i in 300:
		w.step()
	t.eq(int(w.stats.builds_started), 1, "still one site after steps 200 to 400")
	t.eq(_rng_state(w), s0, "no build-check draws while a site exists (not ready)")
	t.near(_stat(w, "hours_waiting_regolith"), 0.0, 1e-12, "no regolith waiting recorded")


func test_who_is_ready_and_who_is_not(t) -> void:
	# variant -> expected site after step 100. Every being is parked, regolith plentiful.
	var cases := {
		"builder_in_workshop": true,
		"sleeping_builder_in_workshop": true,
		"social_in_workshop": false,
		"builder_in_reactor": false,
		"offline_workshop": false,
		"builder_outside": false,
		"no_beings": false,
	}
	for variant: String in cases:
		var h := _world(21)
		var w: SimWorld = h.w
		if not _api(t, w):
			return
		# A green room and a habitat so that choose_kind reaches the weighted pool (the only rule that draws).
		w.add_building("green_room", 600, 0)
		w.add_building("habitat", 700, 0)
		w.colony.regolith = 500.0
		match variant:
			"builder_in_workshop":
				_parked(w, int(h.Wk))
			"sleeping_builder_in_workshop":
				var s := _parked(w, int(h.Wk), "builder", 10.0)
				s.state = "sleep"
				s.sleep_started_t = w.t
			"social_in_workshop":
				_parked(w, int(h.Wk), "social")
			"builder_in_reactor":
				_parked(w, int(h.R))
			"offline_workshop":
				_parked(w, int(h.Wk))
				w.set_offline(int(h.Wk), true)
			"builder_outside":
				var o := _parked(w, int(h.Wk))
				o.state = "eva"
				o.after = "enter"
				o.air_h = 1000.0
				o.x = 100.0
				o.y = 100.0
				o.heading = 0.0
				o.path = [Vector2(100.0, 1100.0)]
		var s0 := _rng_state(w)
		for i in 100:
			if variant == "offline_workshop":
				w.buildings.last_short_t = w.t
			w.step()
		var site_made: bool = w.buildings.site != null
		t.eq(site_made, cases[variant], "%s: site after the 100th step" % variant)
		if cases[variant]:
			t.check(_rng_state(w) != s0, "%s: choose_kind and find_spot drew" % variant)
		else:
			t.eq(_rng_state(w), s0, "%s: a check with nobody ready draws no rng" % variant)
			t.near(w.colony.regolith, 500.0, 1e-12, "%s: nothing spent" % variant)
			t.eq(int(w.stats.builds_started), 0, "%s: builds_started" % variant)


func test_the_check_runs_on_its_own_clock_not_when_a_builder_becomes_ready(t) -> void:
	var h := _world(22)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_parked(w, int(h.Wk))
	w.colony.regolith = 500.0
	w.set_offline(int(h.Wk), true)
	for i in 150:
		w.buildings.last_short_t = w.t
		w.step()
	t.check(w.buildings.site == null, "step 100 passed with the workshop dark: nothing built")
	w.set_offline(int(h.Wk), false)
	for i in 49:
		w.step()
	t.eq(w.step_index, 199, "step 199")
	t.check(w.buildings.site == null, "back online at step 150, still no site at 199 (no check yet)")
	w.step()
	t.check(w.buildings.site != null, "the next check, step 200, starts the site")


func test_failed_find_spot_charges_nothing_and_the_check_repeats(t) -> void:
	var fs: Dictionary = SimData.buildings().find_spot
	var old: Variant = fs.tries
	fs.tries = 0
	var h := _world(23)
	var w: SimWorld = h.w
	if not _api(t, w):
		fs.tries = old
		return
	_parked(w, int(h.Wk))
	w.colony.regolith = 500.0
	for i in 100:
		w.step()
	t.check(w.buildings.site == null, "no spot: no site")
	t.near(w.colony.regolith, 500.0, 1e-12, "a failed find_spot charges nothing")
	t.eq(int(w.stats.builds_started), 0, "builds_started stays 0")
	t.eq(_logs(w, "ground_broken"), 0, "no ground_broken")
	t.eq(w.buildings.count(), 3, "no building added")
	fs.tries = old
	for i in 100:
		w.step()
	t.check(w.buildings.site != null, "5 h later the check repeats and the site starts (step 200)")
	t.near(w.colony.regolith, 500.0 - 30.0, 1e-9, "charged once, now")


func test_need_regolith_is_logged_every_two_sols_and_waited_every_check(t) -> void:
	var h := _world(24)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_parked(w, int(h.Wk))
	w.colony.regolith = 10.0
	t.near(_stat(w, "hours_waiting_regolith"), 0.0, 1e-12, "hours_waiting_regolith starts at 0")
	for i in 99:
		w.step()
	t.eq(_logs(w, "need_regolith"), 0, "nothing before the first check")
	w.step()
	t.eq(_logs(w, "need_regolith"), 1, "step 100: need_regolith logged")
	t.eq(int(w.stats.need_regolith), 1, "stats.need_regolith")
	t.near(_stat(w, "hours_waiting_regolith"), 5.0, 1e-9, "hours_waiting_regolith +5 h")
	t.check(w.buildings.site == null and absf(w.colony.regolith - 10.0) < 1e-12, "no site, nothing spent")
	for i in 100:
		w.step()
	t.eq(_logs(w, "need_regolith"), 1, "step 200: not logged again within 2 sols")
	t.near(_stat(w, "hours_waiting_regolith"), 10.0, 1e-9, "but the waiting hours still add 5 h per check")
	for i in 800:
		w.step()
	t.eq(w.step_index, 1000, "step 1000")
	t.eq(_logs(w, "need_regolith"), 1, "step 1000: only 45 h since the first line (< 2 sols)")
	t.near(_stat(w, "hours_waiting_regolith"), 50.0, 1e-9, "10 checks, 50 h")
	for i in 100:
		w.step()
	t.eq(_logs(w, "need_regolith"), 2, "step 1100: 55 h later it is logged again")
	t.eq(int(w.stats.need_regolith), 2, "stats.need_regolith 2")
	t.near(_stat(w, "hours_waiting_regolith"), 55.0, 1e-9, "11 checks, 55 h")
	# With exactly the cost (green room: 18 + 4 x 3 = 30) the next check builds instead of waiting.
	w.colony.regolith = 30.0
	for i in 100:
		w.step()
	t.check(w.buildings.site != null, "regolith exactly the cost: the site starts at step 1200")
	t.near(w.colony.regolith, 0.0, 1e-9, "all of it spent")
	t.near(_stat(w, "hours_waiting_regolith"), 55.0, 1e-9, "no more waiting hours")


func test_first_build_at_seed_42_is_a_reactor_for_34(t) -> void:
	var w := SimWorld.new(42)
	if not _api(t, w):
		return
	t.near(w.buildings.margin(), 3.0, 1e-9, "founding margin: 14 - 11 = 3")
	t.near(w.colony.regolith, 80.0, 1e-9, "regolith 80 at the start")
	var prev := w.colony.regolith
	var steps := 0
	while w.buildings.site == null and steps < 4000:
		prev = w.colony.regolith
		w.step()
		steps += 1
	t.check(w.buildings.site != null, "a site was started within 4000 steps (%d)" % steps)
	if w.buildings.site == null:
		return
	t.eq(w.step_index % 100, 0, "started on a build check (step %d)" % w.step_index)
	t.check(w.step_index >= 100, "not before the first check")
	t.eq(_sb(w).kind, "reactor", "the first build at seed 42 is a reactor")
	t.near(prev - w.colony.regolith, 34.0, 1e-6, "cost 18 + 4 x 4 = 34 (regolith 80 -> 46)")
	t.eq(int(w.stats.builds_started), 1, "builds_started")
	t.eq(_logs(w, "ground_broken"), 1, "ground_broken")
	t.near(w.buildings.margin(), 1.0, 1e-9, "the site draws 2: margin 3 -> 1")


# ---------------------------------------------------------------- crew and progress (phase 9)

func test_no_crew_means_zero_progress(t) -> void:
	var h := _world(31)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var sb := _sb(w)
	var site: Variant = w.buildings.site
	var lw0: float = float(site.last_work_t)
	# An idle builder in the parent, and a builder still walking out (far away) are not crew.
	_parked(w, int(h.R))
	var far := _worker(w)
	far.x = -600.0
	far.y = -600.0
	far.path = [_centre(sb)]
	for i in 1000:
		far.air_h = 1000.0
		w.step()
	t.eq(sb.built, 0.0, "1000 steps without a being in state work: progress exactly 0")
	t.eq(float(site.last_work_t), lw0, "last_work_t untouched without crew")
	t.eq(far.state, "eva", "the walker is still outside, not crew")
	t.check(w.buildings.site != null, "the site stands")


func test_progress_per_step_follows_the_formula_after_the_drain(t) -> void:
	var h := _world(32)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var sb := _sb(w)
	var b := _worker(w, 0.7, 90.0)
	_arrive(t, w, [b])
	# The spec's case: energy 80.15 before the step, work drains 3 x 0.05 = 0.15, phase 9 reads 80.
	b.energy = 80.15
	var before: float = sb.built
	w.step()
	var delta: float = sb.built - before
	t.near(delta, _rate(0.7, 80.0), 1e-12, "progress = (0.6 + 0.7) x (0.55 + 80/220) x 0.05 / 34 (energy read after the drain)")
	t.near(delta, 0.00174666, 2e-8, "about 0.00174666 per step (the rounded literal)")
	# A second step at energy 80 + 0.15 once more, to see it is not a fluke of the first step.
	b.energy = 80.15
	before = sb.built
	w.step()
	t.near(sb.built - before, _rate(0.7, 80.0), 1e-12, "same again")
	# The pre-drain energy would give a visibly different rate.
	t.check(absf(_rate(0.7, 80.15) - _rate(0.7, 80.0)) > 1e-9, "(the two readings differ by more than the tolerance)")


func test_progress_adds_up_over_the_crew(t) -> void:
	var h := _world(33)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var sb := _sb(w)
	var crew: Array = []
	for i in 3:
		crew.append(_worker(w, 0.7, 90.0))
	_arrive(t, w, crew)
	for b: Being in crew:
		b.energy = 80.15
	var before: float = sb.built
	w.step()
	t.near(sb.built - before, 3.0 * _rate(0.7, 80.0), 1e-12, "three such builders triple it")
	# Mixed drives and energies: sum((0.6 + drive) x (0.55 + energy / 220)).
	var w2: SimWorld = _world(34).w
	_start(t, w2)
	var sb2 := _sb(w2)
	var a := _worker(w2, 0.2, 90.0)
	var c := _worker(w2, 1.0, 90.0)
	_arrive(t, w2, [a, c])
	a.energy = 60.15
	c.energy = 90.15
	var b2: float = sb2.built
	w2.step()
	t.near(sb2.built - b2, _rate(0.2, 60.0) + _rate(1.0, 90.0), 1e-12, "mixed crew: the sum of the two rates")
	# last_work_t follows the crew every step.
	t.near(float(w2.buildings.site.last_work_t), w2.t, 1e-9, "last_work_t = t while there is crew")


func test_only_beings_in_state_work_with_this_job_are_crew(t) -> void:
	var h := _world(35)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var sb := _sb(w)
	var b := _worker(w, 0.7, 90.0)
	_arrive(t, w, [b])
	# A second being in the parent idles; a third walks. Only b counts.
	_parked(w, int(h.R))
	var walker := _worker(w, 1.0, 100.0)
	walker.x = -700.0
	walker.y = -700.0
	walker.path = [_centre(sb)]
	b.energy = 80.15
	var before: float = sb.built
	w.step()
	t.near(sb.built - before, _rate(0.7, 80.0), 1e-12, "one builder working, one idle, one walking: one rate")


func test_work_drains_three_per_hour_stepped(t) -> void:
	var h := _world(36)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var b := _worker(w, 0.5, 90.0)
	_arrive(t, w, [b])
	b.energy = 80.0
	for i in 20:
		w.step()
	t.near(b.energy, 77.0, 1e-6, "one hour (20 steps) of work from 80 gives 77.0")
	for i in 20:
		w.step()
	t.near(b.energy, 74.0, 1e-6, "a second hour: 74.0")
	t.eq(b.state, "work", "still working")


func test_work_left_counts_down_and_arrival_draws_8_to_16(t) -> void:
	var h := _world(37)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var sbl := _sb(w)
	var crew: Array = []
	for i in 120:
		crew.append(_worker(w, 0.5, 100.0))
	w.step()
	var lo := 99.0
	var hi := 0.0
	for b: Being in crew:
		t.eq(b.state, "work", "arrived")
		lo = minf(lo, b.work_left_h)
		hi = maxf(hi, b.work_left_h)
	t.check(lo >= 8.0 - 0.06 and hi <= 16.0, "work_left_h in 8..16 on arrival (saw %.2f .. %.2f)" % [lo, hi])
	t.check(lo < 9.5 and hi > 14.5, "and it is spread over the range (not constant)")
	var one: Being = crew[0]
	var w0: float = one.work_left_h
	for i in 20:
		for b: Being in crew:
			b.energy = 100.0
		sbl.built = 0.0
		w.step()
	t.near(w0 - one.work_left_h, 1.0, 0.06, "work_left_h falls 1 h per hour of work")


func test_work_wander_is_6_px_per_hour_with_pauses_inside_the_inset_site(t) -> void:
	var h := _world(38)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var sb := _sb(w)
	var ws: Array = []
	for i in 20:
		ws.append(_worker(w, 0.5, 100.0))
	_arrive(t, w, ws)
	var prev: Array = []
	var streak: Array = []
	var moved: Array = []
	for b: Being in ws:
		prev.append(Vector2(b.x, b.y))
		streak.append(0)
		moved.append(false)
	var max_d := 0.0
	var streaks: Array = []
	var total := 0.0
	var inside := true
	for i in 900:
		for b: Being in ws:
			b.energy = 100.0
			b.air_h = 1000.0
			b.work_left_h = 1000.0
		sb.built = 0.0
		w.step()
		for k in ws.size():
			var b: Being = ws[k]
			var p := Vector2(b.x, b.y)
			var d := p.distance_to(prev[k])
			max_d = maxf(max_d, d)
			total += d
			if d < 1e-9:
				streak[k] += 1
			else:
				if moved[k] and streak[k] > 0:
					streaks.append(streak[k])
				streak[k] = 0
				moved[k] = true
			if not _in_inset(p, sb, 0.01):
				inside = false
			prev[k] = p
	for b: Being in ws:
		t.eq(b.state, "work", "still working after 900 steps")
	t.check(inside, "every position of 20 workers stays inside the site rectangle inset 5 px")
	t.near(max_d, 6.0 * DT, 1e-4, "walking speed is 6 px/h = 0.3 px per step (max step %.4f)" % max_d)
	t.check(total > 400.0, "they do wander (%.1f px in total)" % total)
	t.check(streaks.size() >= 60, "many completed pauses (%d)" % streaks.size())
	var smin := 999
	var smax := 0
	var ssum := 0.0
	for s: int in streaks:
		smin = mini(smin, s)
		smax = maxi(smax, s)
		ssum += s
	var smean := ssum / maxf(1.0, float(streaks.size()))
	# Pause U(0.8, 2.4) h = 16..48 steps (mean 32); a step either side for the reach test and the count-down.
	t.check(smin >= 13 and smax <= 51, "pauses are 0.8..2.4 h (%d..%d steps)" % [smin, smax])
	t.between(smean, 29.0, 36.0, "mean pause about 1.6 h = 32 steps (%.1f)" % smean)


# ---------------------------------------------------------------- completion

func test_finishing_turns_the_site_into_a_building_and_the_crew_walks_in(t) -> void:
	var h := _world(41)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w, "habitat")
	var sb := _sb(w)
	var crew: Array = []
	for i in 3:
		crew.append(_worker(w, 0.7, 90.0))
	_arrive(t, w, crew)
	var idler := _parked(w, int(h.R))
	var draw_site: float = w.buildings.draw()
	t.near(draw_site, 4.0 + 2.0, 1e-9, "draw with the site: workshop 4 + site 2")
	sb.built = 0.99999
	t.eq(w.buildings.next_hop(int(h.R), sb.id), 0, "not traversable at 0.99999")
	var site: Variant = w.buildings.site
	w.step()
	t.eq(sb.built, 1.0, "progress is clamped at exactly 1")
	t.check(w.buildings.site == null, "the site is cleared")
	t.check(sb.finished() and sb.online(), "the building is finished and online")
	t.near(w.buildings.draw(), 4.0 + 3.0, 1e-9, "draw 2 -> habitat 3")
	t.eq(w.buildings.next_hop(int(h.R), sb.id), sb.id, "the tunnel is traversable now")
	t.eq(int(w.stats.builds_finished), 1, "builds_finished")
	t.eq(_logs(w, "building_done"), 1, "building_done logged")
	for e in w.log:
		if e.kind == "building_done":
			t.eq(int(e.building_id), sb.id, "building_done carries the building id")
	for b: Being in crew:
		t.eq(b.state, "idle", "crew member is idle")
		t.eq(b.building_id, sb.id, "and inside the new building")
		t.check(b.air_h == null, "air_h is null: the suit is off")
		t.check(b.x == null and b.y == null, "no position inside")
		t.check(b.job == null, "job cleared")
	t.eq(idler.building_id, int(h.R), "a being that was not crew stays where it was")
	t.check(site != null, "(the old site record is gone from the world)")
	# Nothing happens afterwards: no progress, no warnings, the stats stop growing.
	var busy: float = _stat(w, "site_busy_h")
	for i in 20:
		w.step()
	t.near(_stat(w, "site_busy_h"), busy, 1e-12, "site_busy_h stops when the site is gone")
	t.eq(_logs(w, "waiting_for_builders"), 0, "no waiting warning")


func test_finishing_a_reactor_adds_supply_and_sets_first_new_reactor_sol(t) -> void:
	var h := _world(42)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	t.check(w.stats.has("first_new_reactor_sol") and w.stats.first_new_reactor_sol == null, "first_new_reactor_sol starts null")
	t.near(w.buildings.supply(), 28.0, 1e-9, "supply 28 with two reactors")
	_start(t, w, "reactor")
	var sb := _sb(w)
	var b := _worker(w, 0.9, 90.0)
	_arrive(t, w, [b])
	t.near(w.buildings.supply(), 28.0, 1e-9, "an unfinished reactor supplies nothing")
	sb.built = 0.99999
	w.step()
	t.near(w.buildings.supply(), 42.0, 1e-9, "supply 42 once it is finished")
	t.near(w.buildings.draw(), 4.0, 1e-9, "a reactor draws 0: only the workshop")
	t.eq(w.stats.first_new_reactor_sol, w.sol(), "first_new_reactor_sol is the elapsed sol")
	# A habitat does not set it.
	var w2: SimWorld = _world(43).w
	_start(t, w2, "habitat")
	var sb2 := _sb(w2)
	var b2 := _worker(w2, 0.9, 90.0)
	_arrive(t, w2, [b2])
	sb2.built = 0.99999
	w2.step()
	t.check(w2.stats.first_new_reactor_sol == null, "only reactors set first_new_reactor_sol")


# ---------------------------------------------------------------- waiting for builders and the hours stats

func test_waiting_for_builders_on_step_494_and_again_494_steps_later(t) -> void:
	var h := _world(51)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	for i in 493:
		w.step()
	t.eq(_logs(w, "waiting_for_builders"), 0, "step 493 (t - last_work_t = 24.65 h): not yet")
	w.step()
	t.eq(w.step_index, 494, "step 494")
	t.eq(_logs(w, "waiting_for_builders"), 1, "step 494: t - last_work_t > 1 sol + eps")
	t.eq(int(w.stats.waiting_for_builders), 1, "stats.waiting_for_builders")
	for i in 493:
		w.step()
	t.eq(_logs(w, "waiting_for_builders"), 1, "step 987: still one")
	w.step()
	t.eq(w.step_index, 988, "step 988")
	t.eq(_logs(w, "waiting_for_builders"), 2, "step 988: repeated after another sol")
	t.eq(int(w.stats.waiting_for_builders), 2, "stats.waiting_for_builders 2")


func test_a_crewed_site_never_warns(t) -> void:
	var h := _world(52)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var sbc := _sb(w)
	var b := _worker(w, 0.5, 100.0)
	_arrive(t, w, [b])
	for i in 700:
		b.energy = 100.0
		b.work_left_h = 1000.0
		sbc.built = 0.0
		w.step()
	t.eq(_logs(w, "waiting_for_builders"), 0, "700 steps with crew: no warning")
	t.eq(int(w.stats.waiting_for_builders), 0, "stat stays 0")
	# The crew leaves: the clock runs from the last step with crew.
	var last: float = float(w.buildings.site.last_work_t)
	t.near(last, w.t, 1e-9, "last_work_t is the last step with crew")
	b.work_left_h = 0.0
	for i in 10:
		w.step()
	t.check(b.state != "work", "the builder left")
	var left_at: float = float(w.buildings.site.last_work_t)
	t.check(left_at < w.t, "last_work_t stopped moving")
	var steps := 0
	while _logs(w, "waiting_for_builders") == 0 and steps < 700:
		b.air_h = 1000.0
		w.step()
		steps += 1
	var gap: float = w.t - left_at
	t.between(gap, SOL_H, SOL_H + 0.06, "warns 1 sol (+ one step) after the last crewed step (gap %.3f h)" % gap)


func test_hours_stats_start_at_zero_and_track_site_and_crew(t) -> void:
	var h := _world(53)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	for k in ["hours_waiting_regolith", "hours_site_no_crew", "site_busy_h"]:
		t.check(w.stats.has(k), "stats.%s exists" % k)
		t.near(_stat(w, k), 0.0, 1e-12, "%s starts at 0" % k)
	for i in 100:
		w.step()
	t.near(_stat(w, "site_busy_h"), 0.0, 1e-12, "no site: site_busy_h does not grow")
	t.near(_stat(w, "hours_site_no_crew"), 0.0, 1e-12, "no site: hours_site_no_crew does not grow")
	_start(t, w)
	for i in 100:
		w.step()
	t.near(_stat(w, "site_busy_h"), 5.0, 1e-9, "100 steps with a site: 5 h busy")
	t.near(_stat(w, "hours_site_no_crew"), 5.0, 1e-9, "all of it without crew")
	var b := _worker(w, 0.5, 100.0)
	_arrive(t, w, [b])
	var busy: float = _stat(w, "site_busy_h")
	var nocrew: float = _stat(w, "hours_site_no_crew")
	for i in 40:
		b.energy = 100.0
		b.work_left_h = 1000.0
		w.step()
	t.near(_stat(w, "site_busy_h") - busy, 2.0, 1e-9, "40 crewed steps: +2 h busy")
	t.near(_stat(w, "hours_site_no_crew") - nocrew, 0.0, 1e-12, "no no-crew hours while somebody works")


# ---------------------------------------------------------------- joining construction (decide, spec 6.4)

func _joined(bs: Array) -> int:
	var n := 0
	for b: Being in bs:
		if b.state == "to_door" and b.suit_up:
			n += 1
	return n


func _crowd(w: SimWorld, n: int, building_id: int, role: String, traits: Dictionary, energy: float = 90.0) -> Array:
	var out: Array = []
	for i in n:
		var b := w.add_being(building_id, role)
		_traits(b, traits)
		b.energy = energy
		b.wait_h = 0.0
		out.append(b)
	return out


func test_builders_join_in_the_parent_with_chance_0_55(t) -> void:
	var h := _world(61)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	var site: Variant = _start(t, w)
	var n := 1000
	var bs := _crowd(w, n, int(h.R), "builder", {"drive": 0.1})
	w.step()
	var j := _joined(bs)
	t.between(float(j) / n, 0.50, 0.60, "joined fraction %.3f (chance 0.55; a low-drive builder is builderish by role)" % (float(j) / n))
	for b: Being in bs:
		if b.state == "to_door" and b.suit_up:
			t.check(b.job != null and int(b.job.building_id) == int(site.building_id), "the joiner's job is the site")
			t.check(not b.sleep_intent, "not sleeping")
			t.check(b.wait_h > 0.0 and b.wait_h < 6.0, "it walks to the door first (wait_h %.2f h)" % b.wait_h)
			break
	# Joining costs no oxygen yet: that is paid at the door.
	t.check(w.colony.oxygen > 140.0 - 3.0, "no suit-up oxygen spent at the join decision (1000 beings breathe 2.5 per step)")


func test_builderish_rules(t) -> void:
	var h := _world(62)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	var site: Variant = _start(t, w)
	var n := 600
	# Not a builder, drive 0.5 (flat persona): never.
	var a := _crowd(w, n, int(h.R), "social", {"drive": 0.5})
	# Drive exactly 0.6 is not > 0.6.
	var b := _crowd(w, n, int(h.R), "curious", {"drive": 0.6})
	# Drive 0.61 is.
	var c := _crowd(w, n, int(h.R), "tender", {"drive": 0.61})
	# 0.4 is below 0.6 and the site has crew-free time only 0 sols: not yet.
	var d := _crowd(w, n, int(h.R), "social", {"drive": 0.4})
	w.step()
	t.eq(_joined(a), 0, "role social, drive 0.5: nobody joins")
	t.eq(_joined(b), 0, "drive 0.6 (not > 0.6): nobody joins")
	t.between(float(_joined(c)) / n, 0.49, 0.61, "drive 0.61 is builderish: %.3f" % (float(_joined(c)) / n))
	t.eq(_joined(d), 0, "drive 0.4 and a fresh site: nobody joins")
	# After a sol without crew the bar drops to drive > 0.35.
	site.last_work_t = w.t - 24.0
	var e := _crowd(w, n, int(h.R), "social", {"drive": 0.4})
	site.last_work_t = w.t - 24.0
	w.step()
	t.eq(_joined(e), 0, "24 h without crew is not more than a sol")
	site.last_work_t = w.t - 25.0
	var f := _crowd(w, n, int(h.R), "social", {"drive": 0.4})
	var g := _crowd(w, n, int(h.R), "social", {"drive": 0.35})
	var k := _crowd(w, n, int(h.R), "social", {"drive": 0.34})
	w.step()
	t.between(float(_joined(f)) / n, 0.49, 0.61, "25 h without crew and drive 0.4: builderish (%.3f)" % (float(_joined(f)) / n))
	t.eq(_joined(g), 0, "drive 0.35 is not > 0.35")
	t.eq(_joined(k), 0, "drive 0.34 is below")


func test_sleep_comes_before_joining(t) -> void:
	var h := _world(63)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var bs := _crowd(w, 300, int(h.R), "builder", {"drive": 0.9}, 20.0)
	w.step()
	t.eq(_joined(bs), 0, "tired builders (energy 20 < 28) do not join")
	var asleep := 0
	for b: Being in bs:
		if b.state == "sleep":
			asleep += 1
	t.eq(asleep, 300, "they go to sleep on the floor (no habitat)")


func test_builders_elsewhere_walk_to_the_parent_without_a_suit(t) -> void:
	var h := _world(64)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var n := 1000
	var bs := _crowd(w, n, int(h.Wk), "builder", {"drive": 0.5, "restless": 0.0})
	w.step()
	var heading := 0
	for b: Being in bs:
		t.check(not b.suit_up, "no suit away from the parent")
		if b.state == "to_door":
			heading += 1
			t.eq(int(b.corridor_id), int(h.Wk), "the hop toward the parent is the workshop's corridor")
			t.check(not b.sleep_intent, "not a sleep walk")
	# join 0.55, else restless travel 0.08 (restless 0) over the only corridor: 0.55 + 0.45 x 0.08 = 0.586.
	t.between(float(heading) / n, 0.53, 0.64, "heading for the parent: %.3f (0.586 expected)" % (float(heading) / n))


func test_builders_with_no_path_to_the_parent_fall_through(t) -> void:
	var h := _world(65)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var iso: int = w.add_building("habitat", 700, 0)
	var bs := _crowd(w, 200, iso, "builder", {"drive": 0.9})
	w.step()
	var idle := 0
	for b: Being in bs:
		t.check(not b.suit_up, "no suit")
		if b.state == "idle" and b.wait_h > 0.0:
			idle += 1
	t.eq(idle, 200, "no tunnel to the parent: they stay put and pause")


# ---------------------------------------------------------------- suit-up at p1 and the walk out

func _at_door(w: SimWorld, h: Dictionary) -> Being:
	var b := w.add_being(int(h.R), "builder")
	b.energy = 90.0
	b.state = "to_door"
	b.suit_up = true
	b.job = w.buildings.site
	b.wait_h = 0.0
	return b


func test_suit_up_happens_at_the_corridor_end_p1(t) -> void:
	var h := _world(71)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var sb := _sb(w)
	var p1: Vector2 = sb.corridor.p1
	var p2: Vector2 = sb.corridor.p2
	t.eq(p1, Vector2(96.0, 44.0), "setup: p1 (96,44)")
	t.eq(p2, Vector2(136.0, 44.0), "setup: p2 (136,44)")
	w.colony.oxygen = 100.0
	var b := _at_door(w, h)
	w.step()
	t.near(w.colony.oxygen, 99.0, 0.01, "suit-up takes 1 colony oxygen (%.4f)" % w.colony.oxygen)
	t.eq(b.state, "eva", "state eva")
	t.eq(b.after, "work", "after work")
	t.near(float(b.air_h), 36.0, 0.06, "a full tank")
	t.check(not b.suit_up, "suit_up cleared")
	t.check(b.x != null and Vector2(b.x, b.y).distance_to(p1) < 1.0, "it stands at p1, not at the building door")
	t.check(b.path != null and b.path.size() >= 2 and b.path.size() <= 3, "waypoints [p1, p2, work point]")
	t.eq(b.path[b.path.size() - 2], p2, "the middle waypoint is p2")
	t.check(_in_inset(b.path[b.path.size() - 1], sb), "the last waypoint is inside the site rectangle inset 5 px")
	if b.has_method("suit_kind"):
		t.eq(b.suit_kind(), "construction", "suit_kind is construction on the way out")
	else:
		t.check(false, "missing Being.suit_kind()")
	# 100 builders at the door: every work point lies inside the rectangle inset 5 px, and they differ.
	var w3: SimWorld = _world(76).w
	_start(t, w3)
	var sb3 := _sb(w3)
	var pts: Array = []
	for i in 100:
		_at_door(w3, {"R": 1})
	w3.step()
	var all_in := true
	var minx := 1e9
	var maxx := -1e9
	for q: Being in w3.beings:
		var pt: Vector2 = q.path[q.path.size() - 1]
		all_in = all_in and _in_inset(pt, sb3)
		minx = minf(minx, pt.x)
		maxx = maxf(maxx, pt.x)
	t.check(all_in, "100 suit-ups: every work point is inside the site rectangle inset 5 px")
	t.check(maxx - minx > 40.0, "and they are spread over it (x range %.1f px)" % (maxx - minx))
	# At colony oxygen 0 the builder still suits up (spec section 14) and oxygen stays 0.
	var w2: SimWorld = _world(72).w
	_start(t, w2)
	w2.colony.oxygen = 0.4
	var b2 := _at_door(w2, {"R": 1})
	w2.step()
	t.near(w2.colony.oxygen, 0.0, 1e-9, "oxygen clamps at 0 (max(0, oxygen - 1))")
	t.eq(b2.state, "eva", "still suits up")
	t.near(float(b2.air_h), 36.0, 0.06, "and the tank is full")


func test_suit_up_with_the_site_gone_cancels_after_paying(t) -> void:
	var h := _world(73)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	w.colony.oxygen = 100.0
	var b := _at_door(w, h)
	w.buildings.site = null
	w.step()
	t.near(w.colony.oxygen, 99.0, 0.01, "the oxygen is already spent")
	t.eq(b.state, "idle", "the builder goes idle")
	t.check(b.air_h == null and b.x == null and b.job == null, "no suit, no position, no job")
	t.check(not b.suit_up, "suit_up cleared")


func test_the_walk_out_takes_corridor_plus_site_distance_at_16_px_per_hour(t) -> void:
	var h := _world(74)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var sb := _sb(w)
	var b := _at_door(w, h)
	b.energy = 100.0
	w.step()
	var target: Vector2 = b.path[b.path.size() - 1]
	var p2: Vector2 = sb.corridor.p2
	var total := (float(sb.corridor.len) + p2.distance_to(target)) / (16.0 * DT)
	var steps := 0
	var kind_ok := true
	var e0 := -1.0
	while b.state == "eva" and steps < 600:
		if steps < 10 or steps >= 30:
			b.energy = 100.0
		if steps == 10:
			e0 = b.energy
		w.step()
		steps += 1
		if steps == 30:
			t.near(e0 - b.energy, 2.0 * DT * 20.0, 1e-6, "walking out drains 2 per hour: 20 steps cost 2.0")
		if b.state == "eva" and b.has_method("suit_kind") and b.suit_kind() != "construction":
			kind_ok = false
	t.eq(b.state, "work", "it arrives and starts work")
	t.check(absf(float(steps) - total) <= 5.0, "walked %d steps, expected about %.1f (%.0f px at 0.8 px/step)" % [steps, total, total * 0.8])
	t.check(kind_ok, "construction suit the whole way")
	t.between(b.work_left_h, 7.9, 16.0, "work_left_h drawn in 8..16")
	t.check(Vector2(b.x, b.y).distance_to(target) < 1.0, "it is at the work point")
	if b.has_method("suit_kind"):
		t.eq(b.suit_kind(), "construction", "construction suit while working")
	t.check(b.job != null, "still has the job")


func test_suit_kind_flag(t) -> void:
	var h := _world(75)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var inside := _parked(w, int(h.R))
	if not inside.has_method("suit_kind"):
		t.check(false, "missing Being.suit_kind()")
		return
	t.eq(inside.suit_kind(), "none", "inside: none")
	var out := _worker(w)
	t.eq(out.suit_kind(), "construction", "outside with a job, walking: construction")
	_arrive(t, w, [out])
	t.eq(out.suit_kind(), "construction", "working: construction")
	var other := _walker(w, int(h.R), "enter", null)
	t.eq(other.suit_kind(), "eva", "outside without a job: eva")
	var sleeper := _parked(w, int(h.Wk))
	sleeper.state = "sleep"
	t.eq(sleeper.suit_kind(), "none", "asleep inside: none")


# ---------------------------------------------------------------- shift end, return and enter

func test_shift_end_walks_home_p2_then_p1_and_enters_the_parent(t) -> void:
	var h := _world(81)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var sb := _sb(w)
	var p1: Vector2 = sb.corridor.p1
	var p2: Vector2 = sb.corridor.p2
	var b := _worker(w, 0.5, 100.0)
	_arrive(t, w, [b])
	b.work_left_h = 0.12
	var steps := 0
	while b.state == "work" and steps < 20:
		b.energy = 100.0
		w.step()
		steps += 1
	t.eq(b.state, "eva", "work_left_h reached 0: back outside walking")
	t.eq(b.after, "enter", "after = enter")
	t.check(b.job == null, "job cleared at shift end")
	t.eq(b.path.size(), 2, "path [p2, p1]")
	t.check(b.path[0].distance_to(p2) < 1e-6 and b.path[1].distance_to(p1) < 1e-6, "p2 first, then p1")
	var start := Vector2(b.x, b.y)
	var total := (start.distance_to(p2) + float(sb.corridor.len)) / (16.0 * DT)
	var walk := 0
	while b.state == "eva" and walk < 600:
		b.energy = 100.0
		w.step()
		walk += 1
	t.check(absf(float(walk) - total) <= 5.0, "walked home in %d steps, expected about %.1f" % [walk, total])
	t.eq(b.state, "idle", "idle again")
	t.eq(b.building_id, int(h.R), "in the parent building")
	t.check(b.air_h == null and b.x == null and b.y == null and b.heading == null, "suit off, no position")
	t.check(b.path == null and b.job == null and not b.returning, "path, job and returning reset")
	t.check(b.wait_h > 0.0, "it pauses (idle_wait)")
	# Nobody works any more: no progress.
	var before: float = sb.built
	for i in 20:
		w.step()
	t.eq(sb.built, before, "no crew, no progress")


func test_the_construction_suit_is_kept_on_the_walk_home_until_entering(t) -> void:
	# Step 7 decision: the suit is chosen at suit-up and kept until the being enters a building, so a builder
	# walking home after its shift (job already null) still reports construction.
	var h := _world(82)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var b := _at_door(w, h)
	b.energy = 100.0
	w.step()
	t.eq(b.state, "eva", "suited up at the door")
	var steps := 0
	while b.state != "work" and steps < 600:
		b.energy = 100.0
		w.step()
		steps += 1
	t.eq(b.state, "work", "arrived and working")
	b.work_left_h = 0.1
	steps = 0
	while b.state == "work" and steps < 20:
		b.energy = 100.0
		w.step()
		steps += 1
	t.eq(b.state, "eva", "shift over, walking home")
	t.check(b.job == null, "the job is null on the return walk")
	var kind_ok := true
	steps = 0
	while b.state == "eva" and steps < 600:
		b.energy = 100.0
		if b.suit_kind() != "construction":
			kind_ok = false
		w.step()
		steps += 1
	t.check(kind_ok, "construction suit the whole way home, with a null job")
	t.eq(b.state, "idle", "entered the parent")
	t.eq(b.suit_kind(), "none", "inside again: none")


# ---------------------------------------------------------------- EVA arrival table: work, enter, null; site gone

func _entered(t, b: Being, building_id: int, what: String) -> void:
	t.eq(b.state, "idle", "%s: idle" % what)
	t.eq(b.building_id, building_id, "%s: in building %d" % [what, building_id])
	t.check(b.air_h == null, "%s: air_h null" % what)
	t.check(b.job == null, "%s: job null" % what)
	t.check(b.path == null, "%s: path null" % what)
	t.check(b.x == null and b.y == null and b.heading == null, "%s: x, y, heading null" % what)
	t.check(not b.returning, "%s: returning false" % what)
	t.check(b.wait_h > 0.0, "%s: wait_h = idle_wait" % what)


func test_eva_arrival_work_with_a_live_site_starts_work(t) -> void:
	var h := _world(91)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	var site: Variant = _start(t, w)
	var b := _walker(w, int(h.R), "work", site)
	b.returning = false
	w.step()
	t.eq(b.state, "work", "arrival with a live site: work")
	t.between(b.work_left_h, 7.9, 16.0, "work_left_h in 8..16")
	t.check(b.air_h != null and b.job != null, "still suited, still has the job")


func test_eva_arrival_work_with_the_site_cleared_enters_at_once(t) -> void:
	# Unfinished building: the parent. Finished building: the building itself.
	var h := _world(92)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	var site: Variant = _start(t, w)
	var b := _walker(w, int(h.R), "work", site)
	b.returning = false
	w.buildings.site = null
	w.step()
	_entered(t, b, int(h.R), "work, site cleared, building unfinished")
	var w2: SimWorld = _world(93).w
	var site2: Variant = _start(t, w2)
	var sb2 := _sb(w2)
	var b2 := _walker(w2, 1, "work", site2)
	b2.returning = false
	sb2.built = 1.0
	w2.buildings.site = null
	w2.step()
	_entered(t, b2, sb2.id, "work, site cleared, building finished")


func test_eva_arrival_enter_and_null_reset_everything(t) -> void:
	var h := _world(94)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	var site: Variant = _start(t, w)
	var e := _walker(w, int(h.R), "enter", site)
	var n := _walker(w, int(h.Wk), "enter", null)
	n.after = null
	w.step()
	_entered(t, e, int(h.R), "after enter")
	_entered(t, n, int(h.Wk), "after null")


func test_site_gone_while_working_enters_at_once(t) -> void:
	var h := _world(95)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w)
	var b := _worker(w, 0.5, 100.0)
	_arrive(t, w, [b])
	t.eq(b.state, "work", "working")
	w.buildings.site = null
	w.step()
	_entered(t, b, int(h.R), "site gone, building unfinished: enters the parent in the same step, no walk")
	var w2: SimWorld = _world(96).w
	_start(t, w2)
	var sb2 := _sb(w2)
	var b2 := _worker(w2, 0.5, 100.0)
	_arrive(t, w2, [b2])
	sb2.built = 1.0
	w2.buildings.site = null
	w2.step()
	_entered(t, b2, sb2.id, "site gone, building finished: enters the building")


func test_a_stale_job_is_not_the_new_sites_crew(t) -> void:
	# Site 1 finishes (building unfinished -> finished by a direct write) and site 2 starts. A being still carrying
	# job = site 1 must not work on site 2: working, it enters at once; arriving, it enters at once.
	var h := _world(97)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	var old: Variant = _start(t, w, "habitat")
	var sb1 := _sb(w)
	var worker := _worker(w, 0.9, 90.0)
	_arrive(t, w, [worker])
	var walker := _walker(w, int(h.R), "work", old)
	walker.returning = false
	sb1.built = 1.0
	w.buildings.site = null
	var site2: Variant = null
	w.colony.regolith = 500.0
	t.check(w.start_site("comms", {"parent_id": 1, "dir": "u", "tw": 10, "th": 8, "gap": 5}), "second site started")
	site2 = w.buildings.site
	var sb2 := _sb(w)
	w.step()
	_entered(t, worker, sb1.id, "working on the old site: enters the finished old building")
	_entered(t, walker, sb1.id, "arriving for the old site: enters the finished old building")
	t.eq(sb2.built, 0.0, "the new site got no progress from them")
	t.check(site2 != null and w.buildings.site == site2, "the new site stands")


# ---------------------------------------------------------------- the offline workshop

func test_offline_workshop_makes_builders_not_ready_even_when_they_are_inside(t) -> void:
	var h := _world(101)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_parked(w, int(h.Wk))
	w.colony.regolith = 10.0
	w.set_offline(int(h.Wk), true)
	for i in 200:
		w.buildings.last_short_t = w.t
		w.step()
	t.near(_stat(w, "hours_waiting_regolith"), 0.0, 1e-12, "an offline workshop: no planning, so no regolith waiting either")
	t.eq(_logs(w, "need_regolith"), 0, "no need_regolith")
	w.set_offline(int(h.Wk), false)
	for i in 100:
		w.step()
	t.near(_stat(w, "hours_waiting_regolith"), 5.0, 1e-9, "back online: the next check waits for regolith")


# ---------------------------------------------------------------- the whole cycle

func test_whole_cycle_join_suit_up_walk_work_finish_enter(t) -> void:
	var h := _world(111)
	var w: SimWorld = h.w
	if not _api(t, w):
		return
	_start(t, w, "habitat")
	var sb := _sb(w)
	sb.built = 0.9
	var crew := _crowd(w, 3, int(h.R), "builder", {"drive": 0.9})
	var saw_out := 0
	var saw_work := 0
	var steps := 0
	while w.buildings.site != null and steps < 3000:
		for b: Being in crew:
			b.air_h = b.air_h if b.air_h == null else 1000.0
		w.step()
		steps += 1
		for b: Being in crew:
			if b.state == "eva" and b.after == "work":
				saw_out += 1
			if b.state == "work":
				saw_work += 1
	t.check(w.buildings.site == null, "the site was finished (%d steps)" % steps)
	t.check(saw_out > 0 and saw_work > 0, "builders walked out and worked (%d, %d)" % [saw_out, saw_work])
	t.check(sb.online() and sb.built == 1.0, "the building is online")
	t.eq(int(w.stats.builds_finished), 1, "builds_finished")
	# Latecomers see the site gone and come home: nobody stays outside.
	for i in 800:
		w.step()
	for b: Being in crew:
		t.check(b.air_h == null and b.is_inside(), "builder is inside again (state %s)" % b.state)
	t.eq(w.beings.size(), 3, "nobody died")
