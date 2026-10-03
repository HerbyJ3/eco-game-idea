extends RefCounted
## Task 1, step 4: buildings and the power budget. Spec: docs/specs/life-support-power.md sections
## 3 (comparators), 5 (order), 7.1, 7.2, 11 (A13), 16 (stats), and the "Tests (tests/test_power.gd ...)" list.
## Numbers are the spec's (not the plan's): newest-building short probability = 0.6 + 0.4/n, so
## n = 10 gives 0.64 (band 0.60..0.68) and n = 4 gives 0.70 (band 0.65..0.75).
##
## Existing API used (steps 1..3): SimWorld.new(seed, {"blank": true}), add_building(kind, tx, ty, built) -> id,
##  set_offline(id, bool), add_being(building_id, role) -> Being, step(), t, rng, log, stats, beings,
##  colony.*, buildings.list / get_building(id) / last_short_t / NEVER, Building.offline / offline_since / built.
##
## API ASSUMED beyond the existing one (extended the simplest way; each name is the spec's where it has one):
##  - Buildings.supply() -> float: finished reactors x 14, x 1.5 while world.t < powers.power_multiplier_until.
##    Buildings.draw() -> float: online finished buildings by kind (reactor 0, habitat 3, workshop 4,
##    green_room 4, archive 2, comms 3) + 2 per unfinished site; offline draws 0.
##    Buildings.margin() -> float = supply() - draw().  Buildings.demand() -> float (spec 7.2): draw as if no
##    finished building were offline, plus site draw.  All four take no arguments and read the world clock
##    themselves (SimWorld wires that); they are evaluated at the current w.t, between steps.
##  - Buildings.clear_short_hold() sets last_short_t = Buildings.NEVER (spec section 2).
##  - SimWorld.powers: a Powers instance (sim/powers.gd, class_name Powers) with the field
##    power_multiplier_until (starts at -1e9) and set_power_multiplier(until_t: float), which sets the field and
##    clears the short hold.  The multiplier applies while t < until (strict).
##  - manage_power() runs inside SimWorld.step() (phase 3); tests never call it directly.
##  - Buildings.nearest_online_habitat(from_building_id: int) -> Building (null if none): distance between building
##    centres ((tx + tw/2), (ty + th/2) in tiles), offline habitats skipped, tie goes to the lowest id.  This is the
##    seam for spec A13 "an offline habitat is not chosen by go_sleep" (go_sleep itself lands in a later step).
##  - Log entries "short" and "back_online" carry building_id (spec section 16 entry shape).
##  - Stats are top-level keys of world.stats (not stats.window): shorts, reonlines, shorts_this_sol,
##    max_shorts_per_sol, max_offline_h, demand_over_steps, step_count.  Phase 11 samples them after phase 3, and
##    the sol counter resets on the first step with t - start_hour >= n x sol_hours - STEP_EPS (step 494 for sol 1).
##  - Helper-guarded: a missing method or key fails the check with a clear message instead of aborting the test.
##  - The sleeper test places beings with direct writes (b.state = "sleep"); the floor-sleep and birth tests are parked in
##    tests/deferred/power_deferred_tests.gd.txt until steps 6 and 9.
##
## Placement: reactor is id 1, other buildings follow in the order given (ids 2, 3, ...), all far apart.

const DT := 0.05
const SOL_STEPS := 493
const SOL_H := 24.6597


## Blank world with a finished reactor (id 1) then `kinds` (ids 2..), all finished.
func _mk(seed_in: int, kinds: Array, reactors: int = 1) -> SimWorld:
	var w := SimWorld.new(seed_in, {"blank": true})
	for r in reactors:
		w.add_building("reactor", 40 * r, 60)
	for i in kinds.size():
		w.add_building(kinds[i], 20 * (i + 1), 0)
	return w


func _steps(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()


# ---- guarded access to assumed API ----

func _num(t, w, method: String) -> float:
	if not w.buildings.has_method(method):
		t.check(false, "missing Buildings.%s()" % method)
		return -999.0
	return float(w.buildings.call(method))


func _sup(t, w) -> float:
	return _num(t, w, "supply")


func _drw(t, w) -> float:
	return _num(t, w, "draw")


func _mar(t, w) -> float:
	return _num(t, w, "margin")


func _dem(t, w) -> float:
	return _num(t, w, "demand")


func _powers(t, w) -> Object:
	var p: Object = w.get("powers")
	t.check(p != null and p.has_method("set_power_multiplier"), "missing SimWorld.powers.set_power_multiplier()")
	return p


func _fortune(t, w, until_t: float) -> void:
	var p := _powers(t, w)
	if p != null and p.has_method("set_power_multiplier"):
		p.call("set_power_multiplier", until_t)


func _stat(w, key: String) -> Variant:
	return w.stats.get(key, null)


func _offline_ids(w) -> Array:
	var out: Array = []
	for b in w.buildings.list:
		if b.offline:
			out.append(b.id)
	return out


func _count_log(w, kind: String) -> int:
	var n := 0
	for e in w.log:
		if e.kind == kind:
			n += 1
	return n


## Reactor + 5 habitats (draw 15 > 14): step 1 shorts one habitat. Then two online habitats are deleted
## (direct write), so draw falls to 6 and the dark habitat may return once the 3 h hold passes.
## Returns [world, dark building id].
func _short_then_relieve(seed_in: int) -> Array:
	var w := _mk(seed_in, ["habitat", "habitat", "habitat", "habitat", "habitat"])
	w.step()
	var dark: int = -1
	var online: Array = []
	for b in w.buildings.list:
		if b.kind == "habitat":
			if b.offline:
				dark = b.id
			else:
				online.append(b)
	for i in 2:
		w.buildings.list.erase(online[i])
	return [w, dark]


# ---------------------------------------------------------------- supply and draw

func test_supply_per_reactor(t) -> void:
	for n in [0, 1, 2, 3]:
		var w := _mk(1, [], n)
		t.eq(_sup(t, w), 14.0 * n, "supply with %d reactors" % n)
		t.eq(_drw(t, w), 0.0, "reactors draw 0 (%d)" % n)
	# Only finished reactors supply.
	var w2 := _mk(1, [])
	w2.add_building("reactor", 90, 90, 0.5)
	t.eq(_sup(t, w2), 14.0, "a reactor site adds no supply")
	t.eq(_drw(t, w2), 2.0, "a reactor site draws the site draw 2")


func test_draw_per_kind(t) -> void:
	var expect := {"habitat": 3.0, "workshop": 4.0, "green_room": 4.0, "archive": 2.0, "comms": 3.0, "reactor": 0.0}
	for kind in expect.keys():
		var w := _mk(1, [])
		w.add_building(kind, 20, 0)
		t.eq(_drw(t, w), expect[kind], "draw of one %s" % kind)


func test_construction_site_draws_two_whatever_the_kind(t) -> void:
	for kind in ["habitat", "workshop", "green_room", "archive", "comms", "reactor"]:
		var w := _mk(1, [])
		w.add_building(kind, 20, 0, 0.0)
		t.eq(_drw(t, w), 2.0, "site of %s draws 2" % kind)
		w.buildings.get_building(2).built = 0.99
		t.eq(_drw(t, w), 2.0, "site of %s at 0.99 still draws 2" % kind)
		w.buildings.get_building(2).built = 1.0
		var kind_draw := {"habitat": 3.0, "workshop": 4.0, "green_room": 4.0, "archive": 2.0, "comms": 3.0, "reactor": 0.0}
		t.eq(_drw(t, w), kind_draw[kind], "finished %s draws its kind draw" % kind)
	var w2 := _mk(1, [])
	w2.add_building("habitat", 20, 0, 0.5)
	t.eq(_drw(t, w2), 2.0, "habitat site 2, not 3")
	w2.buildings.get_building(2).built = 1.0
	t.eq(_drw(t, w2), 3.0, "finished habitat 3")


func test_hand_check_founding_numbers(t) -> void:
	var w := _mk(1, ["habitat", "workshop", "green_room"])
	t.eq(_drw(t, w), 11.0, "habitat 3 + workshop 4 + green room 4")
	t.eq(_sup(t, w), 14.0, "supply")
	t.eq(_mar(t, w), 3.0, "margin 14 - 11")
	w.add_building("habitat", 90, 90, 0.0)
	t.eq(_drw(t, w), 13.0, "add a site: 13")
	t.eq(_mar(t, w), 1.0, "margin 1")
	var w2 := _mk(1, ["habitat", "workshop", "green_room", "archive", "comms"])
	# The spec text says 18 here; 11 + archive 2 + comms 3 is 16 (spec arithmetic slip). Still over 14.
	t.eq(_drw(t, w2), 16.0, "adding archive 2 and comms 3 gives 16")
	t.check(_drw(t, w2) > _sup(t, w2), "16 > 14: over limit")


func test_offline_building_draws_zero_and_demand_ignores_offline(t) -> void:
	var w := _mk(1, ["habitat", "workshop", "green_room"])
	w.add_building("habitat", 90, 90, 0.0)  # site
	t.eq(_drw(t, w), 13.0, "draw before")
	t.eq(_dem(t, w), 13.0, "demand before = draw while nothing is offline")
	w.set_offline(3, true)  # workshop
	w.buildings.last_short_t = w.t  # hold so it stays dark
	t.eq(_drw(t, w), 9.0, "offline workshop draws 0")
	t.eq(_dem(t, w), 13.0, "demand counts the dark workshop and the site")
	w.set_offline(2, true)
	t.eq(_drw(t, w), 6.0, "two dark: 4 + 2")
	t.eq(_dem(t, w), 13.0, "demand unchanged")


# ---------------------------------------------------------------- shorts

func test_no_short_at_or_below_supply(t) -> void:
	var w := _mk(1, ["habitat", "workshop", "green_room", "comms"])  # draw 14 = supply
	t.eq(_drw(t, w), 14.0, "draw equals supply")
	_steps(w, 200)
	t.eq(_offline_ids(w).size(), 0, "draw == supply is not over the limit")
	t.eq(_stat(w, "shorts"), 0, "no shorts")
	t.eq(w.buildings.last_short_t, Buildings.NEVER, "last_short_t still the sentinel")


func test_over_limit_shorts_exactly_one_per_step_until_it_fits(t) -> void:
	# Spec set: draw 16, supply 14 -> one short is enough. Heavier set: draw 21 -> two or three shorts.
	var light := ["habitat", "workshop", "green_room", "archive", "comms"]
	var heavy := ["habitat", "workshop", "green_room", "archive", "comms", "habitat", "archive", "comms"]
	for variant in [light, heavy]:
		_chain_case(t, variant)


func _chain_case(t, kinds: Array) -> void:
	for seed_in in range(1, 61):
		var w := _mk(seed_in, kinds)
		var start_draw := _drw(t, w)
		var prev := 0
		for step in range(1, 8):
			var over := _drw(t, w) > 14.0
			w.step()
			var off := _offline_ids(w).size()
			t.check(off - prev <= 1, "seed %d step %d: at most one new short" % [seed_in, step])
			t.eq(off - prev == 1, over, "seed %d step %d: one short exactly when draw was over 14" % [seed_in, step])
			prev = off
		t.check(_drw(t, w) <= 14.0, "seed %d: shorts stop once the draw fits" % seed_in)
		t.check(not w.buildings.get_building(1).offline, "seed %d: the reactor never shorts" % seed_in)
		t.eq(_stat(w, "shorts"), _offline_ids(w).size(), "seed %d: stats.shorts counts the dark ones" % seed_in)
		t.eq(_count_log(w, "short"), _offline_ids(w).size(), "seed %d: one log line per short" % seed_in)
		t.check(_offline_ids(w).size() >= 1, "seed %d: at least one short from draw %s" % [seed_in, str(start_draw)])


func test_one_short_per_step_when_far_over(t) -> void:
	var w := _mk(5, ["habitat", "habitat", "habitat", "habitat", "habitat", "habitat", "habitat", "habitat"])  # draw 24
	for k in [1, 2, 3, 4]:
		w.step()
		t.eq(_offline_ids(w).size(), k, "after step %d exactly %d dark (24 -> 12 needs 4)" % [k, k])
	_steps(w, 20)
	t.eq(_offline_ids(w).size(), 4, "stops at draw 12 <= 14")
	t.eq(_drw(t, w), 12.0, "draw 12")
	t.eq(_stat(w, "shorts"), 4, "4 shorts")


func test_short_records_time_log_and_hold(t) -> void:
	var w := _mk(3, ["habitat", "habitat", "habitat", "habitat", "habitat"])  # draw 15
	w.step()
	var dark := _offline_ids(w)
	t.eq(dark.size(), 1, "one short")
	var b = w.buildings.get_building(dark[0])
	t.near(float(b.offline_since), w.t, 1e-9, "offline_since = t of the short")
	t.near(w.buildings.last_short_t, w.t, 1e-9, "last_short_t = t of the short")
	var found := false
	for e in w.log:
		if e.kind == "short":
			found = true
			t.eq(e.get("building_id", null), dark[0], "short log names the building")
	t.check(found, "a 'short' log line exists")


func test_short_never_picks_reactor_site_or_offline_building(t) -> void:
	for seed_in in range(1, 201):
		var w := _mk(seed_in, ["workshop", "workshop", "workshop", "workshop"], 2)  # reactors 1,2; supply 28; draw 16
		# Push over 28: add a site and finished workshops.
		for i in 3:
			w.add_building("workshop", 200 + 20 * i, 0)
		w.add_building("workshop", 300, 0, 0.5)  # site, id 10
		# draw = 7 x 4 + 2 = 30 > 28
		var site_id: int = 10
		w.step()
		t.eq(_offline_ids(w).size(), 1, "seed %d: one short" % seed_in)
		var id: int = _offline_ids(w)[0]
		t.check(id != 1 and id != 2, "seed %d: not a reactor" % seed_in)
		t.check(id != site_id, "seed %d: not the site" % seed_in)
		t.check(w.buildings.get_building(site_id).built < 1.0 and not w.buildings.get_building(site_id).offline, "seed %d: site untouched" % seed_in)
		_steps(w, 10)
		t.eq(_offline_ids(w).size(), 1, "seed %d: no second short (draw 26 <= 28)" % seed_in)


func test_over_limit_with_no_candidates_does_nothing(t) -> void:
	var w := _mk(1, [])
	for i in 8:
		w.add_building("habitat", 20 * (i + 1), 0, 0.0)  # 8 sites: draw 16 > 14, none online non-reactor
	t.eq(_drw(t, w), 16.0, "draw 16")
	var rng_probe := SimRng.new(1)
	_steps(w, 50)
	t.eq(_offline_ids(w).size(), 0, "nothing goes offline")
	t.eq(_stat(w, "shorts"), 0, "no shorts counted")
	t.eq(w.buildings.last_short_t, Buildings.NEVER, "hold untouched")
	t.eq(_count_log(w, "short"), 0, "nothing logged")
	t.eq(w.rng.randf(), rng_probe.randf(), "no rng drawn without candidates")
	t.check(not w.buildings.get_building(1).offline, "reactor still online")


func test_short_draw_order_chance_then_pick_on_failure(t) -> void:
	# Replay the spec draw order: candidates ascending id; chance(0.6) -> newest; else pick(candidates).
	var kinds := ["workshop", "workshop", "workshop", "workshop", "workshop"]  # draw 20 > 14; ids 2..6
	var newest_hits := 0
	var other_hits := 0
	for seed_in in range(1, 101):
		var w := _mk(seed_in, kinds)
		w.step()
		var r := SimRng.new(seed_in)
		var cand: Array = [2, 3, 4, 5, 6]
		var want: int
		var drew_pick := false
		if r.chance(0.6):
			want = 6
		else:
			want = r.pick(cand)
			drew_pick = true
		var first_dark := -1
		for e in w.log:
			if e.kind == "short":
				first_dark = int(e.get("building_id", -1))
				break
		t.eq(first_dark, want, "seed %d: first short target matches the replayed draws" % seed_in)
		if want == 6 and not drew_pick:
			newest_hits += 1
		else:
			other_hits += 1
	t.check(newest_hits > 40 and other_hits > 10, "both branches exercised (%d newest, %d pick)" % [newest_hits, other_hits])


func test_short_rng_consumption(t) -> void:
	# A short consumes one chance draw (success) or one chance draw plus one pick (failure); nothing else.
	for seed_in in range(1, 41):
		var w := _mk(seed_in, ["workshop", "workshop", "workshop", "workshop"])  # draw 16, ids 2..5
		w.step()
		var r := SimRng.new(seed_in)
		if not r.chance(0.6):
			r.pick([2, 3, 4, 5])
		t.eq(w.rng.randf(), r.randf(), "seed %d: rng stream position after one short" % seed_in)


func _newest_fraction(t, n: int, trials: int) -> float:
	var kinds: Array = []
	for i in n:
		kinds.append("workshop")  # n x 4 > 14 for n >= 4
	var newest_id := n + 1
	var hits := 0
	var seen_other := {}
	for seed_in in range(1, trials + 1):
		var w := _mk(seed_in, kinds)
		w.step()
		var dark := _offline_ids(w)
		if dark.size() != 1:
			t.check(false, "seed %d: expected exactly one short on step 1, got %d" % [seed_in, dark.size()])
			continue
		if dark[0] == newest_id:
			hits += 1
		else:
			seen_other[dark[0]] = true
	if n == 4:
		t.eq(seen_other.size(), 3, "n=4: every non-newest candidate is picked sometimes")
	return float(hits) / float(trials)


func test_newest_building_probability_n10(t) -> void:
	var f := _newest_fraction(t, 10, 1000)
	t.between(f, 0.60, 0.68, "n=10: P(newest) = 0.6 + 0.4/10 = 0.64, measured %.3f over 1000 seeds" % f)


func test_newest_building_probability_n4(t) -> void:
	var f := _newest_fraction(t, 4, 1000)
	t.between(f, 0.65, 0.75, "n=4: P(newest) = 0.6 + 0.4/4 = 0.70, measured %.3f over 1000 seeds" % f)


# ---------------------------------------------------------------- re-online

func test_reonline_load_rule(t) -> void:
	# [online kinds besides the reactor, offline kind, comes back?] with supply 14: need draw + kind draw <= 13.3.
	var cases := [
		[["workshop", "green_room"], "habitat", true],             # 8 + 3 = 11 (spec example)
		[["workshop", "green_room", "archive"], "habitat", true],  # 10 + 3 = 13 <= 13.3
		[["workshop", "green_room", "comms"], "habitat", false],   # 11 + 3 = 14 > 13.3 (spec example)
		[["workshop", "green_room", "comms"], "archive", true],    # 11 + 2 = 13
		[["workshop", "green_room", "comms", "archive"], "archive", false],  # 13 + 2 = 15
		[["workshop", "green_room", "archive"], "comms", true],    # 10 + 3 = 13
		[["workshop", "green_room", "archive", "archive"], "comms", false],  # 12 + 3 = 15
	]
	for c in cases:
		var w := _mk(1, c[0])
		var id: int = w.add_building(c[1], 500, 0)
		w.set_offline(id, true)
		_steps(w, 200)
		var b = w.buildings.get_building(id)
		var label := "online %s, dark %s (draw %s)" % [str(c[0]), c[1], str(_drw(t, w))]
		if c[2]:
			t.check(not b.offline, "returns: " + label)
			t.eq(b.offline_since, null, "offline_since cleared: " + label)
			t.eq(_stat(w, "reonlines"), 1, "reonlines 1: " + label)
			t.eq(_count_log(w, "back_online"), 1, "back_online logged: " + label)
		else:
			t.check(b.offline, "stays dark: " + label)
			t.eq(_stat(w, "reonlines"), 0, "no reonline: " + label)


func test_reonline_is_immediate_with_no_recent_short(t) -> void:
	var w := _mk(1, ["workshop", "green_room"])
	var id: int = w.add_building("habitat", 500, 0)
	w.set_offline(id, true)
	t.eq(w.buildings.last_short_t, Buildings.NEVER, "never shorted: no hold")
	w.step()
	t.check(not w.buildings.get_building(id).offline, "back online on the first step")
	var probe := SimRng.new(1)
	t.eq(w.rng.randf(), probe.randf(), "re-online draws no rng")


func test_reonline_hold_60_steps_blocked_61_online(t) -> void:
	var w := _mk(1, ["workshop", "green_room"])  # draw 8, plenty of room
	var id: int = w.add_building("habitat", 500, 0)
	w.set_offline(id, true)
	w.buildings.last_short_t = w.t  # a short "just happened"
	_steps(w, 60)
	t.check(w.buildings.get_building(id).offline, "60 steps (3.00 h) after the short: still offline")
	w.step()
	t.check(not w.buildings.get_building(id).offline, "61st step (3.05 h): online")
	t.eq(_stat(w, "reonlines"), 1, "one reonline")


func test_reonline_hold_after_a_real_short(t) -> void:
	for seed_in in [1, 2, 3, 4, 5, 6]:
		var r := _short_then_relieve(seed_in)
		var w: SimWorld = r[0]
		var dark: int = r[1]
		t.check(dark > 0, "seed %d: setup shorted a habitat" % seed_in)
		# Step 1 was the short; 60 more steps = 60 steps after it (step 61 in total).
		_steps(w, 60)
		t.check(w.buildings.get_building(dark).offline, "seed %d: 60 steps after the short: offline" % seed_in)
		t.eq(_stat(w, "reonlines"), 0, "seed %d: no reonline yet" % seed_in)
		w.step()
		t.check(not w.buildings.get_building(dark).offline, "seed %d: 61 steps after the short (step 62): online" % seed_in)
		t.eq(_stat(w, "reonlines"), 1, "seed %d: one reonline" % seed_in)


func test_reonline_ascending_id_one_per_step(t) -> void:
	var w := _mk(1, ["workshop"])  # draw 4
	var a: int = w.add_building("habitat", 500, 0)
	var b: int = w.add_building("archive", 520, 0)
	var c: int = w.add_building("comms", 540, 0)
	for id in [c, a, b]:  # dark in a scrambled order: ordering must follow ids, not the order they went dark
		w.set_offline(id, true)
	w.step()
	t.eq(_offline_ids(w), [b, c], "step 1: only the lowest id (habitat) returns")
	w.step()
	t.eq(_offline_ids(w), [c], "step 2: archive returns")
	w.step()
	t.eq(_offline_ids(w), [], "step 3: comms returns")
	t.eq(_stat(w, "reonlines"), 3, "three reonlines")


func test_reonline_takes_first_that_fits_not_first_in_line(t) -> void:
	var w := _mk(1, ["workshop", "green_room", "comms"])  # draw 11
	var hab: int = w.add_building("habitat", 500, 0)    # 11 + 3 = 14 > 13.3: does not fit
	var arc: int = w.add_building("archive", 520, 0)    # 11 + 2 = 13 <= 13.3: fits
	w.set_offline(hab, true)
	w.set_offline(arc, true)
	w.step()
	t.eq(_offline_ids(w), [hab], "archive (higher id) returns because the habitat does not fit")
	_steps(w, 50)
	t.eq(_offline_ids(w), [hab], "habitat stays dark: 13 + 3 = 16")


func test_reonline_never_while_over_supply(t) -> void:
	# Over the limit the step shorts; it never re-onlines in the same step ("at most one short or one re-online").
	var w := _mk(1, ["habitat", "habitat", "habitat", "habitat", "habitat", "habitat"])  # draw 18
	var pre := _offline_ids(w).size()
	w.step()
	t.eq(_offline_ids(w).size(), pre + 1, "short only")
	t.eq(_stat(w, "reonlines"), 0, "no reonline while over")


# ---------------------------------------------------------------- offline_since and max_offline_h

func test_offline_since_set_on_short_and_cleared_on_return(t) -> void:
	var r := _short_then_relieve(2)
	var w: SimWorld = r[0]
	var dark: int = r[1]
	var b = w.buildings.get_building(dark)
	var t_short: float = float(b.offline_since)
	t.near(t_short, w.t, 1e-9, "offline_since = t after step 1 (the step of the short)")
	_steps(w, 40)
	t.near(float(b.offline_since), t_short, 1e-12, "offline_since does not move while offline")
	_steps(w, 21)  # step 62 in total
	t.check(not b.offline, "back online")
	t.eq(b.offline_since, null, "offline_since null once online")


func test_set_offline_sets_offline_since(t) -> void:
	var w := _mk(1, ["habitat"])
	_steps(w, 7)
	w.set_offline(2, true)
	t.near(float(w.buildings.get_building(2).offline_since), w.t, 1e-12, "set_offline stamps t")
	w.set_offline(2, false)
	t.eq(w.buildings.get_building(2).offline_since, null, "set_offline(false) clears it")


func test_max_offline_h(t) -> void:
	var r := _short_then_relieve(4)
	var w: SimWorld = r[0]
	t.near(float(_stat(w, "max_offline_h")), 0.0, 1e-9, "step 1 (the short itself): 0 h")
	_steps(w, 30)  # step 31
	t.near(float(_stat(w, "max_offline_h")), 30 * DT, 1e-6, "30 steps offline: 1.5 h")
	_steps(w, 30)  # step 61
	t.near(float(_stat(w, "max_offline_h")), 60 * DT, 1e-6, "60 steps offline: 3.0 h")
	w.step()  # step 62: online again
	t.near(float(_stat(w, "max_offline_h")), 61 * DT, 1e-6, "final value kept when it returns: 3.05 h")
	_steps(w, 200)
	t.near(float(_stat(w, "max_offline_h")), 61 * DT, 1e-6, "max does not shrink or grow with nothing offline")


func test_max_offline_h_is_the_maximum_over_buildings(t) -> void:
	var w := _mk(1, ["workshop", "green_room", "comms"])  # draw 11
	var a: int = w.add_building("habitat", 500, 0)  # stays dark (14 > 13.3)
	w.set_offline(a, true)
	_steps(w, 20)
	var b: int = w.add_building("habitat", 520, 0)
	w.set_offline(b, true)
	_steps(w, 20)
	# a has been dark 40 steps, b 20.
	t.near(float(_stat(w, "max_offline_h")), 40 * DT, 1e-6, "the longest-dark building sets the max (2.0 h)")


# ---------------------------------------------------------------- offline effects (A13)

func test_offline_green_room_stops_producing(t) -> void:
	var w := _mk(1, ["green_room"])
	for i in 7:
		w.add_being(1)
	var green: int = 2
	t.near(w.colony.o2_net(), 1.05, 1e-9, "online: 1.4 - 0.35")
	w.set_offline(green, true)
	w.buildings.last_short_t = w.t  # hold 60 steps
	t.eq(w.colony.green_rooms(), 0, "offline green room counts 0")
	t.near(w.colony.o2_net(), -0.35, 1e-9, "o2_net with 7 beings: -0.35")
	t.near(w.colony.food_net(), -0.245, 1e-9, "food_net with 7 beings: -0.245")
	var o2 := w.colony.oxygen
	var food := w.colony.food
	_steps(w, 61)  # phase 2 runs before phase 3, so steps 1..61 all see it offline
	t.near(w.colony.oxygen, o2 - 0.35 * 61 * DT, 1e-6, "oxygen fell for 61 steps")
	t.near(w.colony.food, food - 0.245 * 61 * DT, 1e-6, "food fell for 61 steps")
	t.check(not w.buildings.get_building(green).offline, "green room back online at step 61 (phase 3)")
	w.step()  # step 62 sees it online
	t.near(w.colony.oxygen, o2 - 0.35 * 61 * DT + 1.05 * DT, 1e-6, "production resumes on step 62")
	t.near(w.colony.food, food - 0.245 * 61 * DT + 0.755 * DT, 1e-6, "food resumes on step 62")


func test_nearest_online_habitat_skips_offline(t) -> void:
	var w := SimWorld.new(1, {"blank": true})
	w.add_building("reactor", 0, 0)                  # id 1, centre (6, 5)
	var near_h: int = w.add_building("habitat", 20, 0)   # id 2, centre (26, 4) at default size 10x8
	var far_h: int = w.add_building("habitat", 60, 0)    # id 3
	if not w.buildings.has_method("nearest_online_habitat"):
		t.check(false, "missing Buildings.nearest_online_habitat(from_id)")
		return
	t.eq(w.buildings.nearest_online_habitat(1).id, near_h, "nearer habitat wins")
	w.set_offline(near_h, true)
	t.eq(w.buildings.nearest_online_habitat(1).id, far_h, "offline habitat is not chosen: the farther online one is")
	w.set_offline(far_h, true)
	t.eq(w.buildings.nearest_online_habitat(1), null, "none online: null (the being sleeps on the floor)")
	# Tie: equidistant habitats, lower id wins.
	var w2 := SimWorld.new(1, {"blank": true})
	w2.add_building("reactor", 40, 0)
	var left: int = w2.add_building("habitat", 0, 0)
	var right: int = w2.add_building("habitat", 80, 0)
	t.check(left < right, "ids ascend")
	t.eq(w2.buildings.nearest_online_habitat(1).id, left, "tie goes to the lowest id")


func test_sleepers_in_a_habitat_that_shorts_keep_sleeping(t) -> void:
	for seed_in in range(1, 21):
		var w := _mk(seed_in, ["habitat", "habitat", "habitat", "habitat", "habitat"])  # draw 15: one short on step 1
		var sleepers: Array = []
		for id in [2, 3, 4, 5, 6]:
			var b := w.add_being(id, "social")
			b.state = "sleep"
			b.energy = 20.0
			b.sleep_started_t = w.t
			sleepers.append(b)
		var homes: Array = []
		for b in sleepers:
			homes.append(b.building_id)
		w.step()
		t.eq(_offline_ids(w).size(), 1, "seed %d: a habitat went dark" % seed_in)
		for b in sleepers:
			t.eq(b.state, "sleep", "seed %d: being %d still asleep" % [seed_in, b.id])
			t.eq(b.building_id, homes[sleepers.find(b)], "seed %d: being %d stays in its habitat" % [seed_in, b.id])


# ---------------------------------------------------------------- Good fortune (power multiplier)

func test_fortune_defaults(t) -> void:
	var w := _mk(1, [], 2)
	var p := _powers(t, w)
	if p != null:
		t.eq(p.get("power_multiplier_until"), -1e9, "power_multiplier_until starts at the sentinel")
	t.eq(_sup(t, w), 28.0, "2 reactors: 28")


func test_fortune_multiplier_raises_supply_for_one_sol_then_expires(t) -> void:
	var w := _mk(1, [], 2)
	var until: float = w.t + SOL_H
	_fortune(t, w, until)
	var p := _powers(t, w)
	if p != null:
		t.near(float(p.get("power_multiplier_until")), until, 1e-9, "until stored")
	t.eq(_sup(t, w), 42.0, "supply 28 x 1.5 = 42 while t < until")
	_steps(w, 493)
	t.check(w.t < until, "step 493 is still before until")
	t.eq(_sup(t, w), 42.0, "still 42 at step 493 (24.65 h)")
	w.step()
	t.check(w.t >= until, "step 494 is past until")
	t.eq(_sup(t, w), 28.0, "supply back to 28 on step 494")


func test_fortune_one_reactor_gives_21(t) -> void:
	var w := _mk(1, [])
	_fortune(t, w, w.t + SOL_H)
	t.eq(_sup(t, w), 21.0, "14 x 1.5")
	t.near(_mar(t, w), 21.0, 1e-9, "margin follows supply")


func test_fortune_brings_a_dark_building_back_on_the_next_step_and_it_may_short_again(t) -> void:
	# 2 reactors (28) and 8 workshops (32): step 1 shorts one; 28 + 4 > 26.6 so it cannot return.
	var w := _mk(1, ["workshop", "workshop", "workshop", "workshop", "workshop", "workshop", "workshop", "workshop"], 2)
	w.step()
	t.eq(_offline_ids(w).size(), 1, "one workshop dark")
	var dark: int = _offline_ids(w)[0]
	t.eq(_drw(t, w), 28.0, "draw 28 = supply")
	_steps(w, 9)  # step 10, hold not over
	t.eq(_offline_ids(w), [dark], "still dark at step 10")
	_fortune(t, w, w.t + SOL_H)
	t.eq(w.buildings.last_short_t, Buildings.NEVER, "the hook resets the 3 h hold")
	t.eq(_sup(t, w), 42.0, "supply 42")
	t.eq(_dem(t, w), 32.0, "demand 32 fits under 42")
	w.step()  # step 11: 28 + 4 = 32 <= 0.95 x 42 = 39.9, hold cleared
	t.eq(_offline_ids(w), [], "back online on the very next step, 49 steps before the plain hold would allow")
	t.eq(_stat(w, "reonlines"), 1, "one reonline")
	# Run to the end of the sol: 10 + 1 steps so far; fortune set at step 10 so it ends at step 10 + 494.
	_steps(w, 492)  # step 503: the multiplier set at step 10 ends at t(10) + 24.6597 -> expiry on step 504
	t.eq(_sup(t, w), 42.0, "still 42 one step before expiry")
	t.eq(_offline_ids(w), [], "nothing short yet")
	w.step()  # step 504
	t.eq(_sup(t, w), 28.0, "supply back to 28")
	t.eq(_offline_ids(w).size(), 1, "draw 32 > 28: a workshop shorts again on the expiry step")
	t.eq(_stat(w, "shorts"), 2, "second short counted")


func test_fortune_load_rule_uses_the_boosted_supply(t) -> void:
	# Fortune supply 21: a dark workshop (4) returns while draw + 4 <= 0.95 x 21 = 19.95.
	for sites in [7, 8]:
		var w := _mk(1, ["workshop"])
		w.set_offline(2, true)
		for i in sites:
			w.add_building("habitat", 100 + 20 * i, 0, 0.0)  # sites draw 2 each, never candidates
		_steps(w, 5)
		t.eq(_offline_ids(w), [2], "%d sites, supply 14: nothing to short or return (hold-free but 14 + 4 too much)" % sites)
		_fortune(t, w, w.t + SOL_H)
		_steps(w, 5)
		if sites == 7:
			t.eq(_offline_ids(w), [], "draw 14 + 4 = 18 <= 19.95: returns")
		else:
			t.eq(_offline_ids(w), [2], "draw 16 + 4 = 20 > 19.95: stays dark")
			t.eq(_stat(w, "reonlines"), 0, "no reonline")


# ---------------------------------------------------------------- stats: demand and shorts per sol

func test_demand_stat_counts_steps_over_supply(t) -> void:
	var w := _mk(1, ["habitat", "workshop", "green_room", "archive", "comms"])  # demand 16 > 14
	t.eq(_dem(t, w), 16.0, "demand 16")
	_steps(w, 100)
	t.eq(_stat(w, "step_count"), 100, "step_count counts every step")
	t.eq(_stat(w, "demand_over_steps"), 100, "demand stayed 16 > 14 although shorts cut the draw")
	t.check(_drw(t, w) <= 14.0, "draw is within supply after the shorts")
	t.eq(_dem(t, w), 16.0, "demand ignores the offline state")
	# Fortune: supply 21 >= demand 16, so steps stop counting.
	_fortune(t, w, w.t + SOL_H)
	_steps(w, 50)
	t.eq(_stat(w, "step_count"), 150, "150 steps")
	t.eq(_stat(w, "demand_over_steps"), 100, "no more over-demand steps while supply is 21")


func test_demand_includes_the_site(t) -> void:
	var w := _mk(1, ["habitat", "workshop", "green_room"])  # 11
	t.eq(_dem(t, w), 11.0, "11")
	w.add_building("archive", 90, 90, 0.0)
	t.eq(_dem(t, w), 13.0, "site adds 2")
	_steps(w, 20)
	t.eq(_stat(w, "demand_over_steps"), 0, "13 <= 14: never over")
	t.eq(_stat(w, "step_count"), 20, "20 steps")


func test_shorts_per_sol_stat(t) -> void:
	var w := _mk(5, ["habitat", "habitat", "habitat", "habitat", "habitat", "habitat", "habitat", "habitat"])  # 24
	_steps(w, 493)
	t.eq(_stat(w, "shorts"), 4, "4 shorts in sol 0")
	t.eq(_stat(w, "shorts_this_sol"), 4, "shorts_this_sol 4 on step 493")
	t.eq(_stat(w, "max_shorts_per_sol"), 4, "max 4")
	w.step()  # step 494: first step with t - start_hour >= sol_hours
	t.eq(_stat(w, "shorts_this_sol"), 0, "sol boundary on step 494 resets the per-sol count")
	t.eq(_stat(w, "max_shorts_per_sol"), 4, "max kept")
	t.eq(_stat(w, "shorts"), 4, "run total kept")
	# Two more habitats: draw 12 + 6 = 18 -> two shorts in sol 1.
	w.add_building("habitat", 700, 0)
	w.add_building("habitat", 720, 0)
	_steps(w, 5)
	t.eq(_stat(w, "shorts_this_sol"), 2, "2 shorts in sol 1")
	t.eq(_stat(w, "max_shorts_per_sol"), 4, "max stays 4")
	t.eq(_stat(w, "shorts"), 6, "6 in total")


# ---------------------------------------------------------------- determinism

func _power_signature(w: SimWorld) -> String:
	var bs: Array = []
	for b in w.buildings.list:
		bs.append([b.id, b.kind, b.offline, b.offline_since])
	return str(bs) + JSON.stringify(w.stats) + JSON.stringify(w.log) + str(w.buildings.last_short_t)


func _power_run(t, seed_in: int) -> String:
	var kinds: Array = []
	for i in 9:
		kinds.append("habitat")
	for i in 3:
		kinds.append("workshop")
	var w := _mk(seed_in, kinds)  # draw 39 vs supply 14
	_steps(w, 300)
	_fortune(t, w, w.t + SOL_H)
	_steps(w, 700)
	w.add_building("reactor", 900, 0)
	_steps(w, 400)
	return _power_signature(w)


func test_seeded_determinism(t) -> void:
	var a := _power_run(t, 42)
	var b := _power_run(t, 42)
	t.eq(a, b, "same seed: identical offline flags, stats and log after 1400 steps")
	var sigs := {}
	for s in [1, 2, 3, 4, 5]:
		sigs[_power_run(t, s)] = true
	t.check(sigs.size() > 1, "different seeds choose different victims")
