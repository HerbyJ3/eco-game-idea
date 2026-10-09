extends RefCounted
## Task 4, step 3: the relationships tests, written first (red). Spec: docs/specs/relationships.md revision 3, section 14
## tests 1 to 26 (test 16, the view, lives in tests/test_view_relationships.gd; test 27 is the whole-suite run itself, see
## the end of this header). Section 12 (hash proof) is the separate script tests/relationships_hash_proof.gd, whose pure
## helpers are tested here (test 17). The balance half (T11 and the `web` column) is in
## tests/test_relationships_balance.gd (Task 4 step 6).
##
## Naming: test_tNN_* is spec test NN (letters split one spec test into several functions so a failure points at one
## sentence). Everything is a hand-made blank world (SimWorld.new(seed, {"blank": true}), add_building, add_being) driven by
## calling world.relationships.on_step(world, tick_h) (one tick per call) and on_sol(world); only tests 13, 14, 18 (d) and the
## sol-reading length check step the real simulation.
##
## Class access: nothing here names `Relationships`, `world.relationships` ... as a static type. Worlds, beings and the module
## are untyped Variants and the script is reached with load("res://sim/relationships.gd"), so on a tree without the
## implementation the file still parses and each test fails cleanly (every test starts with `_api()`, which records one
## failed check per missing piece and makes the test return before it can abort on a missing member; an aborted test would
## otherwise pass silently, because the runner only fails a test with zero checks. _begin/_end add the same guard to the
## test body). Data is read with SimData.load_json("relationships.json") (the cache the module must read at use time or at
## world creation; tests edit the cache BEFORE building the world, like test_ages).
##
## API ASSUMED beyond the spec's own names (the simplest reading; the implementer should match or tell the test author):
##  - `SimWorld.relationships` (instance of res://sim/relationships.gd), `SimWorld.relationships_enabled` (bool).
##  - Relationships.on_step(world, dt) and on_sol(world); are_friends(a, b); debug_set_bond(a, b, bond) which creates the pair
##    when absent, sets `bond`, applies the flag rules (friends, close, was_close, friend_count) and logs / queues nothing.
##  - Fields as spec section 3: `pairs` (Dictionary key int -> {lo, hi, bond, friends, close, was_close, kin, crew}), `known`,
##    `found_friend`, `crew_drift_named` (each a set: a Dictionary id -> true or an Array; the tests only use `.has(id)`, and
##    add with a Dictionary entry or append), `friend_count` (Dictionary id -> int), `pending` (Array of {type, lo, hi, place,
##    building_id}), `acc_h`, `lines_sol`, `lines_this_sol`, `present` (Dictionary building id -> Array of being ids).
##  - stats.relationships keys as spec 10.2 (`lines` a Dictionary with the six kind keys, `first_*` null before).
##  - Log entries: kind "rel_friends" / "rel_found_friend" / "rel_close" / "rel_close_crew" / "rel_drifted" / "rel_grief" with
##    being_id = {a}, other_id = {b}, place, building_id (spec 5.6). Text = data text with {a} {b} replaced by being names
##    (+ " " + place sentence for the friends, found_friend and close forms).
##  - Pair order of {a}/{b}: friends form: lower id is {a} (spec); found_friend: the new being is {a} (spec); close,
##    close_crew and drifted: lower id is {a} (NOT stated by the spec; checked leniently, see `_names_ok`); grief: the mourner
##    is {a}, the dead is {b}.
##  - A tick that creates the kin pair (5.2) also decays it in 5.5 when the pair is not together; tests that need the exact
##    seed value set decay.per_h to 0 (the spec does not say whether the seed is decayed in its own tick).
##  - debug_set_bond sets `was_close` when it sets `close`? Not relied on: tests reach was_close by a real crossing.
##  - Bond values reach tests only through `pairs[key].bond` (the module's private data; the player never sees them).
## Test 27 (the existing suite passes with the module on) is the run of tests/run_tests.gd itself and cannot be a unit test;
## the implementer lists any test changed for log pollution in the task log.

const SHIFT := 1048576
const CMP := 1e-12

var _undo: Array = []


# ---------------------------------------------------------------- helpers

func _rd() -> Dictionary:
	if not FileAccess.file_exists("res://data/relationships.json"):
		return {}
	var d: Variant = SimData.load_json("relationships.json")
	return d if d is Dictionary else {}


func _edit(dict: Dictionary, key: String, value: Variant) -> void:
	_undo.append([dict, key, dict[key]])
	dict[key] = value


func _restore() -> void:
	while not _undo.is_empty():
		var u: Array = _undo.pop_back()
		u[0][u[1]] = u[2]


func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func _begin(t) -> void:
	t._failures.append(_abort_msg(t))


func _end(t) -> void:
	_restore()
	t._failures.erase(_abort_msg(t))


func _has_method_of(obj: Variant, m: String) -> bool:
	return obj != null and obj.has_method(m)


## One failed check naming every missing piece of the API; true when every piece the tests touch exists.
func _api(t) -> bool:
	var missing: Array[String] = []
	if not FileAccess.file_exists("res://data/relationships.json"):
		missing.append("data/relationships.json")
	var rs = null
	if FileAccess.file_exists("res://sim/relationships.gd"):
		rs = load("res://sim/relationships.gd")
	if rs == null:
		missing.append("sim/relationships.gd")
	var w = SimWorld.new(1, {"blank": true})
	if "relationships" in w and w.relationships != null:
		for m in ["on_step", "on_sol", "are_friends", "debug_set_bond"]:
			if not w.relationships.has_method(m):
				missing.append("world.relationships.%s()" % m)
		for f in ["pairs", "known", "found_friend", "crew_drift_named", "friend_count", "pending", "acc_h", "lines_sol",
				"lines_this_sol", "present"]:
			if not (f in w.relationships):
				missing.append("world.relationships.%s" % f)
	else:
		missing.append("SimWorld.relationships")
	if not ("relationships_enabled" in w):
		missing.append("SimWorld.relationships_enabled")
	if not w.stats.has("relationships"):
		missing.append("stats.relationships")
	t.check(missing.is_empty(), "missing API: " + ", ".join(PackedStringArray(missing)))
	if missing.is_empty():
		_begin(t)
	return missing.is_empty()


## Blank world: reactor, two habitats, workshop, green room (ids 1 to 5, in that order).
func _world(seed_in: int = 1) -> Variant:
	var w = SimWorld.new(seed_in, {"blank": true})
	w.add_building("reactor", 0, 0)
	w.add_building("habitat", 40, 0)
	w.add_building("habitat", 80, 0)
	w.add_building("workshop", 120, 0)
	w.add_building("green_room", 160, 0)
	return w


const REACTOR := 1
const HAB1 := 2
const HAB2 := 3
const WORKSHOP := 4
const GREEN := 5


## A being with neutral-but-explicit traits (overwritten by `traits`), a unique name N<id>, awake and idle in `bid`.
func _being(w, bid: int, traits: Dictionary = {}) -> Variant:
	var b = w.add_being(bid)
	b.name = "N%d" % b.id
	b.energy = 70.0
	for k in ["sociability", "care", "restless", "steady", "curiosity"]:
		b.persona.traits[k] = 0.4
	for k in traits:
		b.persona.traits[k] = traits[k]
	return b


func _tr(b, k: String) -> float:
	return float(b.persona.traits[k])


func _tickh() -> float:
	return float(_rd().tick_h)


func _tick(w) -> void:
	w.relationships.on_step(w, _tickh())


func _ticks(w, n: int) -> void:
	for i in n:
		_tick(w)


func _key(a: int, b: int) -> int:
	return mini(a, b) * SHIFT + maxi(a, b)


func _pair(w, a: int, b: int) -> Variant:
	return w.relationships.pairs.get(_key(a, b))


func _bond(w, a: int, b: int) -> float:
	var p = _pair(w, a, b)
	return 0.0 if p == null else float(p.bond)


func _flag(w, a: int, b: int, f: String) -> bool:
	var p = _pair(w, a, b)
	return p != null and bool(p.get(f, false))


func _setb(w, a: int, b: int, bond: float) -> void:
	w.relationships.debug_set_bond(a, b, bond)


func _sol_set(w, n: int) -> void:
	w.t = w.clock.start_hour + float(n) * w.clock.sol_h
	w.buildings.now = w.t


## Late in elapsed sol n (still sol n).
func _sol_late(w, n: int) -> void:
	w.t = w.clock.start_hour + (float(n) + 0.9) * w.clock.sol_h
	w.buildings.now = w.t


func _lines(w, kind_prefix: String = "rel_") -> Array:
	var out: Array = []
	for e in w.log:
		if str(e.kind).begins_with(kind_prefix):
			out.append(e)
	return out


func _rs(w) -> Dictionary:
	return w.stats.relationships


func _in(coll: Variant, id: int) -> bool:
	return coll.has(id)


func _add_to(coll: Variant, id: int) -> void:
	if coll is Dictionary:
		coll[id] = true
	else:
		coll.append(id)


func _fill_cap(w) -> void:
	w.relationships.lines_sol = w.sol()
	w.relationships.lines_this_sol = _cap_at(w, 0)


## The cap for population `pop` (spec 5.6): max(max_lines_per_sol, floor(pop / pop_per_line)).
func _cap_at(_w, pop: int) -> int:
	var lg: Dictionary = _rd().log
	return maxi(int(lg.max_lines_per_sol), int(floor(float(pop) / float(lg.pop_per_line))))


# ----- formulas (spec 5.3 and 5.5), from data and traits

func _warmth(b) -> float:
	return (_tr(b, "sociability") + _tr(b, "care")) / 2.0


func _affinity(a, b) -> float:
	var af: Dictionary = _rd().affinity
	var ta := _tr(a, "restless") - _tr(a, "steady")
	var tb := _tr(b, "restless") - _tr(b, "steady")
	var gap := absf(ta - tb) * (1.0 - float(af.curiosity_soften) * maxf(_tr(a, "curiosity"), _tr(b, "curiosity")))
	return clampf(1.0 - float(af.tempo_gap_coef) * gap, float(af.floor), 1.0)


func _k_room(a, b) -> float:
	var g: Dictionary = _rd().grow
	var rf := float(g.warmth_base) + (_warmth(a) + _warmth(b)) / 2.0
	return float(g.room_rate) * _tickh() * rf * _affinity(a, b)


func _k_work(a, b) -> float:
	return float(_rd().grow.work_rate) * _tickh() * _affinity(a, b)


func _decay(a, b, close: bool = false) -> float:
	var d: Dictionary = _rd().decay
	var f := float(d.restless_base) + (_tr(a, "restless") + _tr(b, "restless")) / 2.0
	return float(d.per_h) * _tickh() * f * (float(d.close_hold) if close else 1.0)


## A fresh world with two beings in habitat 1.
func _duo(ta: Dictionary = {}, tb: Dictionary = {}) -> Array:
	var w = _world()
	var a = _being(w, HAB1, ta)
	var b = _being(w, HAB1, tb)
	return [w, a, b]


func _friend_line() -> float:
	return float(_rd().lines.friend)


func _close_line() -> float:
	return float(_rd().lines.close)


## Puts the pair just under the friend line and ticks (the pair must be together): the growth crosses it.
func _cross_friend(w, a: int, b: int) -> void:
	_setb(w, a, b, _friend_line() - 1e-4)


func _cross_close(w, a: int, b: int) -> void:
	_setb(w, a, b, _close_line() - 1e-4)


func _text(key: String) -> String:
	return str(_rd().text[key])


func _place_text(place: String) -> String:
	var tp: Dictionary = _rd().text.place
	return str(tp[place] if tp.has(place) else tp["other"])


func _fmt(key: String, a: String, b: String) -> String:
	return _text(key).replace("{a}", a).replace("{b}", b)


## True when the entry's being_id / other_id are the two ids in either order (the spec leaves the order open for close,
## close_crew and drifted lines; the friends and found_friend forms are checked strictly where they are tested).
func _names_ok(e: Dictionary, x: int, y: int) -> bool:
	var ids := [int(e.get("being_id", -1)), int(e.get("other_id", -1))]
	return (ids[0] == x and ids[1] == y) or (ids[0] == y and ids[1] == x)


## Habitats 1 to n (fresh buildings beyond the first two), `pairs_n` pairs of beings (ids 1 .. 2 pairs_n, pair i in room i),
## and sleepers in the reactor up to `pop` beings. Returns the world.
func _pairs_world(pairs_n: int, pop: int) -> Variant:
	var w = SimWorld.new(1, {"blank": true})
	w.add_building("reactor", 0, 0)
	var rooms: Array = []
	for i in pairs_n:
		rooms.append(w.add_building("habitat", 40 + 40 * i, 0))
	for i in pairs_n:
		_being(w, rooms[i])
		_being(w, rooms[i])
	while w.beings.size() < pop:
		var s = _being(w, REACTOR)
		s.state = "sleep"
		s.sleep_started_t = w.t
	return w


func _room_of_pair(w, i: int) -> int:
	return int(w.beings[2 * i].building_id)


func _id_of(w, n: int) -> int:
	return int(w.beings[n].id)


# ---------------------------------------------------------------- 1. room growth recurrence

func test_t01_room_growth_recurrence(t) -> void:
	if not _api(t):
		return
	var s := _duo({"sociability": 0.7, "care": 0.3, "restless": 0.6, "steady": 0.2, "curiosity": 0.1},
			{"sociability": 0.2, "care": 0.5, "restless": 0.3, "steady": 0.4, "curiosity": 0.6})
	var w = s[0]
	var a = s[1]
	var b = s[2]
	var k := _k_room(a, b)
	t.check(k > 0.0, "the staged pair has a positive growth constant")
	var expect := 0.0
	for i in 10:
		_tick(w)
		expect = expect + k * (1.0 - expect)
		t.near(_bond(w, a.id, b.id), expect, CMP, "tick %d follows b = b + k (1 - b)" % (i + 1))
	_end(t)


# ---------------------------------------------------------------- 2. personality

func _one_tick_bond(ta: Dictionary, tb: Dictionary) -> float:
	var s := _duo(ta, tb)
	_tick(s[0])
	return _bond(s[0], s[1].id, s[2].id)


func _ten_tick_bond(ta: Dictionary, tb: Dictionary) -> float:
	var s := _duo(ta, tb)
	_ticks(s[0], 10)
	return _bond(s[0], s[1].id, s[2].id)


func test_t02a_warm_pair_outgrows_cold_pair(t) -> void:
	if not _api(t):
		return
	var warm := _ten_tick_bond({"sociability": 0.8, "care": 0.8}, {"sociability": 0.8, "care": 0.8})
	var cold := _ten_tick_bond({"sociability": 0.1, "care": 0.1}, {"sociability": 0.1, "care": 0.1})
	t.check(warm > cold, "warm pair (%s) > cold pair (%s) after 10 ticks" % [str(warm), str(cold)])
	t.check(cold > 0.0, "the cold pair still grows")
	_end(t)


func test_t02b_equal_tempo_outgrows_clashing(t) -> void:
	if not _api(t):
		return
	var same_a := {"restless": 0.5, "steady": 0.5}
	var clash_a := {"restless": 0.7, "steady": 0.3}
	var clash_b := {"restless": 0.3, "steady": 0.7}
	var same := _ten_tick_bond(same_a, same_a)
	var clash := _ten_tick_bond(clash_a, clash_b)
	t.check(same > clash, "equal-tempo pair (%s) > clashing pair (%s)" % [str(same), str(clash)])
	# And the one-tick bond is exactly k with the data affinity (gap 0.8, no curiosity: 1 - 0.6 x 0.8 at the shipped values).
	var s := _duo(clash_a, clash_b)
	_tick(s[0])
	t.near(_bond(s[0], s[1].id, s[2].id), _k_room(s[1], s[2]), CMP, "one tick of a clashing pair equals the formula")
	_end(t)


func test_t02c_curiosity_softens_the_clash_exactly(t) -> void:
	if not _api(t):
		return
	var ta := {"restless": 0.7, "steady": 0.3, "curiosity": 1.0}
	var tb := {"restless": 0.3, "steady": 0.7, "curiosity": 0.0}
	var s := _duo(ta, tb)
	_tick(s[0])
	var soft := _bond(s[0], s[1].id, s[2].id)
	t.near(soft, _k_room(s[1], s[2]), CMP, "one tick equals the formula with the softened affinity")
	var plain := _one_tick_bond({"restless": 0.7, "steady": 0.3, "curiosity": 0.0}, tb)
	t.check(soft > plain, "a curious member softens the clash (%s > %s)" % [str(soft), str(plain)])
	_end(t)


func test_t02d_full_clash_is_held_at_the_floor(t) -> void:
	if not _api(t):
		return
	var s := _duo({"restless": 1.0, "steady": 0.0, "curiosity": 0.0}, {"restless": 0.0, "steady": 1.0, "curiosity": 0.0})
	_tick(s[0])
	var g: Dictionary = _rd().grow
	var rf := float(g.warmth_base) + (_warmth(s[1]) + _warmth(s[2])) / 2.0
	var floor_k := float(g.room_rate) * _tickh() * rf * float(_rd().affinity.floor)
	t.near(_bond(s[0], s[1].id, s[2].id), floor_k, CMP, "a fully clashing pair grows at exactly affinity.floor")
	_end(t)


# ---------------------------------------------------------------- 3. not together

func _apart_case(t, label: String, mode: String) -> void:
	var w = _world()
	var a = _being(w, HAB1)
	var b = _being(w, HAB1)
	if mode == "building":
		b.building_id = HAB2
	else:
		b.state = mode
	_setb(w, a.id, b.id, 0.5)
	_tick(w)
	t.check(_pair(w, a.id, b.id) != null, "%s: the pair still exists" % label)
	t.near(_bond(w, a.id, b.id), 0.5 - _decay(a, b), CMP, "%s: no growth, decay applies" % label)


func test_t03_not_together_means_no_growth_and_decay(t) -> void:
	if not _api(t):
		return
	_apart_case(t, "different buildings", "building")
	_apart_case(t, "one asleep", "sleep")
	_apart_case(t, "one in transit", "transit")
	_apart_case(t, "one outside", "eva")
	# Sanity: the same pair left together does grow.
	var s := _duo()
	_setb(s[0], s[1].id, s[2].id, 0.5)
	_tick(s[0])
	t.check(_bond(s[0], s[1].id, s[2].id) > 0.5 - 1e-9, "together: no decay, growth")
	_end(t)


# ---------------------------------------------------------------- 4. work

const SPOT := {"parent_id": 1, "dir": "r", "tw": 10, "th": 8, "gap": 5}


func _site_world() -> Variant:
	var w = _world()
	w.colony.regolith = 500.0
	w.start_site("habitat", SPOT)
	return w


func _worker(w, traits: Dictionary = {}) -> Variant:
	var b = _being(w, REACTOR, traits)
	b.state = "work"
	b.job = w.buildings.site
	return b


func test_t04a_work_grows_at_work_rate_without_warmth(t) -> void:
	if not _api(t):
		return
	var w = _site_world()
	t.check(w.buildings.site != null, "staging: a construction site exists")
	var cold1 = _worker(w, {"sociability": 0.05, "care": 0.05})
	var cold2 = _worker(w, {"sociability": 0.05, "care": 0.05})
	var warm1 = _worker(w, {"sociability": 0.95, "care": 0.95})
	var warm2 = _worker(w, {"sociability": 0.95, "care": 0.95})
	_tick(w)
	t.near(_bond(w, cold1.id, cold2.id), _k_work(cold1, cold2), CMP, "cold pair grows at work_rate x affinity")
	t.near(_bond(w, warm1.id, warm2.id), _k_work(warm1, warm2), CMP, "warm pair grows at work_rate x affinity")
	t.near(_bond(w, cold1.id, cold2.id), _bond(w, warm1.id, warm2.id), CMP, "warmth does not enter")
	t.check(_bond(w, cold1.id, warm1.id) > 0.0, "all four on the site are one crew (cross pairs grow)")
	_end(t)


func test_t04b_miners_grow_on_the_same_field_only(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var f1 = w.resources.add_ice_field(100.0, 100.0, 500.0, 20.0)
	var f2 = w.resources.add_ice_field(300.0, 100.0, 500.0, 20.0)
	var m1 = _being(w, REACTOR)
	var m2 = _being(w, REACTOR)
	var m3 = _being(w, REACTOR)
	for pair in [[m1, f1], [m2, f1], [m3, f2]]:
		pair[0].state = "mining"
		pair[0].mine = {"site": pair[1]}
	_tick(w)
	t.near(_bond(w, m1.id, m2.id), _k_work(m1, m2), CMP, "two miners on one field grow")
	t.eq(_bond(w, m1.id, m3.id), 0.0, "miners on different fields do not grow (1, 3)")
	t.eq(_bond(w, m2.id, m3.id), 0.0, "miners on different fields do not grow (2, 3)")
	_end(t)


func test_t04c_a_pair_never_grows_twice_in_a_tick(t) -> void:
	if not _api(t):
		return
	# Workers keep a building_id (inside the reactor) and the same job: they are work-together only (is_inside is false).
	var w = _site_world()
	var a = _worker(w)
	var b = _worker(w)
	_tick(w)
	t.near(_bond(w, a.id, b.id), _k_work(a, b), CMP, "one growth step for a crew pair, not two")
	var s := _duo()
	_tick(s[0])
	t.near(_bond(s[0], s[1].id, s[2].id), _k_room(s[1], s[2]), CMP, "one growth step for a room pair, not two")
	# A pair that is room-together in a building where a site is also running still grows once.
	var w2 = _site_world()
	var c = _being(w2, HAB1)
	var d = _being(w2, HAB1)
	_tick(w2)
	t.near(_bond(w2, c.id, d.id), _k_room(c, d), CMP, "room pair next to a running site grows once")
	_end(t)


# ---------------------------------------------------------------- 5. decay and forgetting

func _decay_case(ta: Dictionary, tb: Dictionary, start: float) -> Array:
	var w = _world()
	var a = _being(w, HAB1, ta)
	var b = _being(w, HAB2, tb)
	_setb(w, a.id, b.id, start)
	_tick(w)
	return [w, a, b]


func test_t05a_restless_decays_faster_than_steady(t) -> void:
	if not _api(t):
		return
	var r := _decay_case({"restless": 0.9}, {"restless": 0.9}, 0.5)
	var s := _decay_case({"restless": 0.1}, {"restless": 0.1}, 0.5)
	t.near(_bond(r[0], r[1].id, r[2].id), 0.5 - _decay(r[1], r[2]), CMP, "restless pair follows the decay formula")
	t.near(_bond(s[0], s[1].id, s[2].id), 0.5 - _decay(s[1], s[2]), CMP, "steady pair follows the decay formula")
	t.check(_bond(r[0], r[1].id, r[2].id) < _bond(s[0], s[1].id, s[2].id), "the restless pair loses more per tick")
	_end(t)


func test_t05b_close_pair_loses_close_hold_of_the_open_rate(t) -> void:
	if not _api(t):
		return
	var c := _decay_case({}, {}, _close_line() + 0.1)
	var o := _decay_case({}, {}, _close_line() - 0.2)
	var lost_close := (_close_line() + 0.1) - _bond(c[0], c[1].id, c[2].id)
	var lost_open := (_close_line() - 0.2) - _bond(o[0], o[1].id, o[2].id)
	t.check(_flag(c[0], c[1].id, c[2].id, "close"), "staging: the pair is close")
	t.near(lost_close, _decay(c[1], c[2], true), CMP, "close pair loses close_hold x the open rate")
	t.near(lost_close, float(_rd().decay.close_hold) * lost_open, CMP, "and that is close_hold of what the open pair loses")
	_end(t)


func test_t05c_unflagged_pair_under_forget_below_is_removed(t) -> void:
	if not _api(t):
		return
	var fb := float(_rd().lines.forget_below)
	var w = _world()
	var a = _being(w, HAB1)
	var b = _being(w, HAB2)
	var c = _being(w, HAB1)
	var d = _being(w, HAB2)
	_setb(w, a.id, b.id, fb + 0.0001)
	_setb(w, c.id, d.id, fb + 0.0001)
	var drop := _decay(a, b)
	t.check(drop > 0.0001, "staging: one tick of decay takes the pair under forget_below")
	_tick(w)
	t.check(_pair(w, a.id, b.id) == null, "the pair under forget_below is removed")
	t.check(_pair(w, c.id, d.id) == null, "and so is the second one (no order dependence)")
	# A flagged pair is never forgotten by this rule.
	var w2 = _world()
	var e = _being(w2, HAB1)
	var f = _being(w2, HAB2)
	_setb(w2, e.id, f.id, _friend_line())
	_tick(w2)
	t.check(_pair(w2, e.id, f.id) != null, "a friends pair is kept")
	_end(t)


# ---------------------------------------------------------------- 6. hysteresis

func test_t06_hysteresis(t) -> void:
	if not _api(t):
		return
	var ln: Dictionary = _rd().lines
	var s := _duo()
	var w = s[0]
	var a: int = s[1].id
	var b: int = s[2].id
	_setb(w, a, b, float(ln.friend) - 1e-6)
	t.check(not w.relationships.are_friends(a, b), "just under the friend line: not friends")
	_setb(w, a, b, float(ln.friend))
	t.check(w.relationships.are_friends(a, b), "friends set at exactly lines.friend")
	t.check(w.relationships.are_friends(b, a), "are_friends is symmetric")
	_setb(w, a, b, 0.20)
	t.check(w.relationships.are_friends(a, b), "kept at 0.20")
	_setb(w, a, b, float(ln.friend_drop))
	t.check(w.relationships.are_friends(a, b), "kept at exactly friend_drop (cleared only below it)")
	_setb(w, a, b, float(ln.friend_drop) - 1e-4)
	t.check(not w.relationships.are_friends(a, b), "cleared just under friend_drop")
	_setb(w, a, b, 0.20)
	t.check(not w.relationships.are_friends(a, b), "and not set again at 0.20 (hysteresis)")
	var c := _duo()
	var w2 = c[0]
	var x: int = c[1].id
	var y: int = c[2].id
	_setb(w2, x, y, float(ln.close) - 1e-6)
	t.check(not _flag(w2, x, y, "close"), "just under the close line: not close")
	_setb(w2, x, y, float(ln.close))
	t.check(_flag(w2, x, y, "close"), "close set at exactly lines.close")
	_setb(w2, x, y, 0.45)
	t.check(_flag(w2, x, y, "close"), "kept at 0.45")
	_setb(w2, x, y, float(ln.close_drop))
	t.check(_flag(w2, x, y, "close"), "kept at exactly close_drop")
	_setb(w2, x, y, float(ln.close_drop) - 1e-4)
	t.check(not _flag(w2, x, y, "close"), "cleared just under close_drop")
	t.check(_flag(w2, x, y, "friends"), "the friends flag is independent and still set")
	_end(t)


# ---------------------------------------------------------------- 7. crew

## A founder world with every founder outside (nothing grows, everything decays) and restless 0.4.
func _crew_world(seed_in: int = 42) -> Variant:
	var w = SimWorld.new(seed_in)
	for b in w.beings:
		b.persona.traits["restless"] = 0.4
		b.state = "eva"
	return w


func test_t07a_founder_world_seeds_21_crew_pairs_and_blank_none(t) -> void:
	if not _api(t):
		return
	var w = SimWorld.new(42)
	t.eq(w.beings.size(), 7, "staging: seven founders")
	t.eq(w.relationships.pairs.size(), 21, "7 x 6 / 2 = 21 pairs at creation")
	var seed_crew := float(_rd().seed.crew)
	var ok := true
	for k in w.relationships.pairs:
		var p: Dictionary = w.relationships.pairs[k]
		ok = ok and is_equal_approx(float(p.bond), seed_crew) and bool(p.friends) and bool(p.crew) \
				and not bool(p.was_close) and not bool(p.get("kin", false))
	t.check(ok, "every crew pair is at seed.crew, friends, crew, not was_close, not kin")
	t.eq(_lines(w).size(), 0, "no relationship line at creation")
	t.eq(int(_rs(w).get("friendships_formed", -1)), 0, "seeds never count as formed")
	var blank = _world()
	t.eq(blank.relationships.pairs.size(), 0, "a blank world has no pairs")
	_end(t)


func test_t07b_crew_close_logs_close_crew_once_per_founder(t) -> void:
	if not _api(t):
		return
	var w = _crew_world()
	var ids: Array = []
	for b in w.beings:
		ids.append(b.id)
	var home: int = w.beings[0].building_id
	for i in [0, 1, 2]:
		w.beings[i].state = "idle"
		w.beings[i].building_id = home
	_cross_close(w, ids[0], ids[1])
	# The other two in the room grow too, but from 0.35 and not past close in one tick.
	_tick(w)
	var lines := _lines(w, "rel_close")
	t.eq(lines.size(), 1, "one close line")
	if lines.size() == 1:
		var e: Dictionary = lines[0]
		t.eq(e.kind, "rel_close_crew", "crew pair logs the crew form")
		t.check(_names_ok(e, ids[0], ids[1]), "names the two founders")
		var na: String = w.beings[ids.find(int(e.being_id))].name
		var nb: String = w.beings[ids.find(int(e.other_id))].name
		t.eq(str(e.text), _fmt("close_crew", na, nb), "text is the close_crew text with no place sentence")
	t.check(_flag(w, ids[0], ids[1], "was_close"), "was_close is set")
	# A second crew pair sharing founder 0 crosses close: nothing is logged (a founder already has a close pair).
	_cross_close(w, ids[0], ids[2])
	_tick(w)
	t.eq(_lines(w, "rel_close").size(), 1, "the second crew pair sharing a founder logs nothing")
	t.check(_flag(w, ids[0], ids[2], "close"), "but its close flag is set")
	_end(t)


func test_t07c_crew_drift_logs_once_per_founder_and_counts_all(t) -> void:
	if not _api(t):
		return
	var w = _crew_world()
	var ids: Array = []
	for b in w.beings:
		ids.append(b.id)
	var drop := float(_rd().lines.friend_drop) + 0.00005
	_setb(w, ids[3], ids[4], drop)
	_tick(w)
	t.check(not _flag(w, ids[3], ids[4], "friends"), "staging: the crew pair lost the friends flag")
	var d1 := _lines(w, "rel_drifted")
	t.eq(d1.size(), 1, "one drifted line for the first crew drop")
	if d1.size() == 1:
		t.check(_names_ok(d1[0], ids[3], ids[4]), "it names the two founders")
		t.eq(str(d1[0].place), "", "drift lines carry no place")
	t.check(_in(w.relationships.crew_drift_named, ids[3]) and _in(w.relationships.crew_drift_named, ids[4]),
			"both founders are in crew_drift_named")
	_setb(w, ids[3], ids[5], drop)
	_tick(w)
	t.eq(_lines(w, "rel_drifted").size(), 1, "a second drop involving a named founder is silent")
	t.eq(int(_rs(w).crew_drifted), 2, "but crew_drifted counts both")
	t.eq(int(_rs(w).lines.drifted), 1, "lines.drifted counts the one logged")
	t.eq(int(_rs(w).lines_capped) + int(_rs(w).lines_dropped) + int(_rs(w).lines_stale), 0, "silent drop is in no line counter")
	_end(t)


# ---------------------------------------------------------------- 8. kin

func _kin_world(parent_alive: bool = true, parent_id: int = -1) -> Array:
	_edit(_rd().decay, "per_h", 0.0)
	var w = _world()
	var p = _being(w, HAB1, {"sociability": 0.8, "care": 0.4})
	_tick(w)
	var n = _being(w, HAB2, {"sociability": 0.2, "care": 0.2})
	n.parent_id = int(p.id) if parent_id < 0 else parent_id
	if not parent_alive:
		w.beings.erase(p)
	_tick(w)
	return [w, p, n]


func test_t08a_kin_pair_at_the_seed_value_with_no_line(t) -> void:
	if not _api(t):
		return
	var s := _kin_world()
	var w = s[0]
	var p = s[1]
	var n = s[2]
	var sd: Dictionary = _rd().seed
	var expect := float(sd.kin_base) + float(sd.kin_warmth) * (_warmth(p) + _warmth(n)) / 2.0
	t.check(_pair(w, p.id, n.id) != null, "the kin pair exists after the next tick")
	t.near(_bond(w, p.id, n.id), expect, CMP, "bond = kin_base + kin_warmth x mean warmth")
	t.check(_flag(w, p.id, n.id, "friends") and _flag(w, p.id, n.id, "kin"), "friends and kin")
	t.eq(_lines(w).size(), 0, "no log line")
	t.check(not _in(w.relationships.found_friend, n.id), "the newborn is not in found_friend")
	_end(t)


func test_t08b_dead_parent_or_no_parent_gives_no_pair(t) -> void:
	if not _api(t):
		return
	var dead := _kin_world(false)
	t.check(_pair(dead[0], dead[1].id, dead[2].id) == null, "dead parent: no pair")
	var none := _kin_world(true, 0)
	t.check(_pair(none[0], none[1].id, none[2].id) == null, "parent_id 0: no pair")
	t.eq(_lines(none[0]).size(), 0, "and no line")
	_end(t)


# ---------------------------------------------------------------- 9. death and grief

## Ten beings (ids 1 to 10), every one outside (nothing grows), unique names, one tick done so all are known.
func _grief_world() -> Variant:
	var w = _world()
	for i in 10:
		var b = _being(w, HAB1)
		b.state = "eva"
	_tick(w)
	return w


func _kill(w, id: int) -> void:
	for b in w.beings:
		if b.id == id:
			w._kill(b, "other")
			return


func test_t09a_grief_lines_name_the_two_strongest_mourners(t) -> void:
	if not _api(t):
		return
	var w = _grief_world()
	_setb(w, 2, 7, 0.7)
	_setb(w, 2, 9, 0.5)
	_setb(w, 2, 4, 0.5)
	_setb(w, 2, 6, _friend_line() - 0.05)
	_setb(w, 3, 5, 0.9)
	_kill(w, 2)
	_tick(w)
	for id in [7, 9, 4, 6]:
		t.check(_pair(w, 2, id) == null, "pair (2, %d) of the dead is removed" % id)
	t.check(_pair(w, 3, 5) != null, "other pairs stay")
	var g := _lines(w, "rel_grief")
	t.eq(g.size(), 2, "two grief lines (grief_max)")
	if g.size() == 2:
		t.eq(int(g[0].being_id), 7, "the 0.7 mourner first")
		t.eq(int(g[1].being_id), 4, "then id 4 (tie at 0.5 goes to the lowest id, not 9)")
		t.eq(int(g[0].other_id), 2, "other_id is the dead")
		t.eq(str(g[0].text), _fmt("grief", "N7", "N2"), "text: {a} is mourning {b}.")
		t.eq(str(g[1].text), _fmt("grief", "N4", "N2"), "second line text")
	t.eq(int(_rs(w).lines.grief), 2, "stats count two grief lines")
	t.check(not _in(w.relationships.known, 2), "the dead id leaves known")
	_end(t)


func test_t09b_no_grief_when_every_bond_is_under_the_friend_line(t) -> void:
	if not _api(t):
		return
	var w = _grief_world()
	_setb(w, 2, 7, _friend_line() - 0.02)
	_setb(w, 2, 9, 0.1)
	_kill(w, 2)
	_tick(w)
	t.eq(_lines(w, "rel_grief").size(), 0, "no grief line")
	t.check(_pair(w, 2, 7) == null and _pair(w, 2, 9) == null, "the pairs are still removed")
	_end(t)


func test_t09c_grief_is_never_capped_or_queued(t) -> void:
	if not _api(t):
		return
	var w = _grief_world()
	_fill_cap(w)
	var before: int = w.relationships.lines_this_sol
	_setb(w, 2, 7, 0.7)
	_setb(w, 2, 9, 0.5)
	_kill(w, 2)
	_tick(w)
	t.eq(_lines(w, "rel_grief").size(), 2, "two grief lines logged with the cap full")
	t.eq(int(w.relationships.lines_this_sol), before, "the cap count is unchanged by grief")
	t.eq(w.relationships.pending.size(), 0, "nothing queued")
	t.eq(int(_rs(w).lines_capped), 0, "lines_capped untouched")
	_end(t)


func test_t09d_pending_event_naming_the_dead_is_dropped(t) -> void:
	if not _api(t):
		return
	var w = _grief_world()
	w.relationships.pending.append({"type": "friend", "lo": 2, "hi": 7, "place": "habitat", "building_id": HAB1})
	_kill(w, 2)
	_tick(w)
	var names_dead := false
	for e in w.relationships.pending:
		names_dead = names_dead or int(e.lo) == 2 or int(e.hi) == 2
	t.check(not names_dead, "no pending event names the dead")
	t.eq(int(_rs(w).lines_stale), 1, "the dropped event counts in lines_stale")
	_end(t)


# ---------------------------------------------------------------- 10. lines and queue

## One crossing in a fresh world; returns the single rel_ entry (or {}) and the world.
func _one_line(setup: Callable) -> Array:
	var w = _world()
	var made: Array = setup.call(w)
	var a: int = made[0]
	var b: int = made[1]
	_cross_friend(w, a, b)
	_tick(w)
	var l := _lines(w)
	return [w, l[0] if l.size() == 1 else {}, l.size()]


func _room_pair(kind: String) -> Callable:
	return func(w) -> Array:
		var bid: int = w.add_building(kind, 400, 0)
		var a = _being(w, bid)
		var b = _being(w, bid)
		return [a.id, b.id]


func test_t10a_friends_form_and_place_sentence_per_room_kind(t) -> void:
	if not _api(t):
		return
	for kind in ["habitat", "green_room", "workshop", "reactor", "archive", "comms"]:
		var r := _one_line(_room_pair(kind))
		var e: Dictionary = r[1]
		t.eq(int(r[2]), 1, "%s: exactly one line" % kind)
		if r[2] == 1:
			t.eq(str(e.kind), "rel_friends", "%s: both beings are new, the friends form" % kind)
			t.eq(str(e.text), _fmt("friends", "N1", "N2") + " " + _place_text(kind), "%s: text and place sentence" % kind)
			t.eq(int(e.being_id), 1, "%s: the lower id is {a}" % kind)
			t.eq(int(e.other_id), 2, "%s: other_id" % kind)
			t.eq(str(e.place), kind, "%s: place" % kind)
			t.check(e.building_id != null, "%s: a room place carries its building id" % kind)
	_end(t)


func test_t10b_site_ice_and_pit_places(t) -> void:
	if not _api(t):
		return
	var site := _one_line(func(w) -> Array:
		w.colony.regolith = 500.0
		w.start_site("habitat", SPOT)
		var a = _worker(w)
		var b = _worker(w)
		return [a.id, b.id])
	t.eq(int(site[2]), 1, "site: one line")
	if site[2] == 1:
		t.eq(str(site[1].text), _fmt("friends", "N1", "N2") + " " + _place_text("site"), "site sentence")
		t.eq(str(site[1].place), "site", "place is site")
		t.check(site[1].building_id == null, "a work place carries no building id")
	for kind in ["ice", "pit"]:
		var m := _one_line(func(w) -> Array:
			var f = w.resources.add_ice_field(100.0, 100.0, 500.0, 20.0) if kind == "ice" else w.resources.add_pit(100.0, 100.0)
			var a = _being(w, REACTOR)
			var b = _being(w, REACTOR)
			for x in [a, b]:
				x.state = "mining"
				x.mine = {"site": f}
			return [a.id, b.id])
		t.eq(int(m[2]), 1, "%s: one line" % kind)
		if m[2] == 1:
			t.eq(str(m[1].text), _fmt("friends", "N1", "N2") + " " + _place_text(kind), "%s sentence" % kind)
			t.eq(str(m[1].place), kind, "place is %s" % kind)
	_end(t)


func test_t10c_other_place_fallback(t) -> void:
	if not _api(t):
		return
	var tp: Dictionary = _rd().text.place
	_undo.append([tp, "archive", tp["archive"]])
	tp.erase("archive")
	var r := _one_line(_room_pair("archive"))
	t.eq(int(r[2]), 1, "one line")
	if r[2] == 1:
		t.eq(str(r[1].text), _fmt("friends", "N1", "N2") + " " + str(tp["other"]), "a kind without a place key uses text.place.other")
	_end(t)


func test_t10d_found_friend_form_names_the_new_being_first(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1)
	var b = _being(w, HAB1)
	_add_to(w.relationships.found_friend, a.id)
	_cross_friend(w, a.id, b.id)
	_tick(w)
	var l := _lines(w)
	t.eq(l.size(), 1, "one line")
	if l.size() == 1:
		t.eq(str(l[0].kind), "rel_found_friend", "one new being: the found_friend form")
		t.eq(int(l[0].being_id), b.id, "the new being is {a}")
		t.eq(str(l[0].text), _fmt("found_friend", "N2", "N1") + " " + _place_text("habitat"), "text")
	t.check(_in(w.relationships.found_friend, b.id) and _in(w.relationships.found_friend, a.id), "both end in found_friend")
	# Neither new: no line.
	var w2 = _world()
	var c = _being(w2, HAB1)
	var d = _being(w2, HAB1)
	_add_to(w2.relationships.found_friend, c.id)
	_add_to(w2.relationships.found_friend, d.id)
	_cross_friend(w2, c.id, d.id)
	_tick(w2)
	t.eq(_lines(w2).size(), 0, "neither new: no friend line")
	t.eq(int(_rs(w2).friendships_formed), 1, "but the friendship is counted")
	t.eq(int(_rs(w2).lines_stale), 0, "and no event was made, so nothing is stale (5.5: an event needs one being not in found_friend)")
	_end(t)


func test_t10e_close_only_for_the_first_close_of_both(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1)
	var b = _being(w, HAB1)
	var c = _being(w, HAB1)
	_cross_close(w, a.id, b.id)
	_tick(w)
	var l := _lines(w, "rel_close")
	t.eq(l.size(), 1, "the first close logs")
	if l.size() == 1:
		t.eq(str(l[0].kind), "rel_close", "non-crew: the close form")
		t.eq(str(l[0].text), _fmt("close", "N1", "N2") + " " + _place_text("habitat"), "text with place sentence")
	_cross_close(w, a.id, c.id)
	_tick(w)
	t.eq(_lines(w, "rel_close").size(), 1, "a being with another close pair logs nothing")
	t.eq(int(_rs(w).close_formed), 2, "but both closes are counted")
	_end(t)


func test_t10f_drifted_only_for_was_close_or_the_crew_rule(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1)
	var b = _being(w, HAB1)
	var c = _being(w, HAB1)
	var d = _being(w, HAB1)
	# (a, b): friends, never close. Moved apart and nudged under the drop line: silent.
	_setb(w, a.id, b.id, float(_rd().lines.friend_drop) + 0.00005)
	# (c, d): becomes close by a real crossing, then drifts.
	_cross_close(w, c.id, d.id)
	_tick(w)
	t.check(_flag(w, c.id, d.id, "was_close"), "staging: (c, d) was close")
	for x in [a, b, c, d]:
		x.state = "eva"
	_setb(w, c.id, d.id, float(_rd().lines.friend_drop) + 0.00005)
	_setb(w, a.id, b.id, float(_rd().lines.friend_drop) + 0.00005)
	_tick(w)
	var l := _lines(w, "rel_drifted")
	t.eq(l.size(), 1, "one drifted line: the was_close pair only")
	if l.size() == 1:
		t.check(_names_ok(l[0], c.id, d.id), "it names the was_close pair")
		t.check(str(l[0].text) in [_fmt("drifted", "N3", "N4"), _fmt("drifted", "N4", "N3")], "text is the drifted text with the two names")
	t.eq(int(_rs(w).drifted), 1, "drifted counts was_close pairs only")
	_end(t)


## Five habitats with a pair each at pop 20; every pair crossing in one tick.
func _five_events() -> Variant:
	var w = _pairs_world(5, 20)
	for i in 5:
		_cross_friend(w, _id_of(w, 2 * i), _id_of(w, 2 * i + 1))
	return w


func test_t10g_cap_queue_and_second_sol(t) -> void:
	if not _api(t):
		return
	var w = _five_events()
	t.eq(_cap_at(w, 20), 3, "staging: the cap at pop 20 is 3")
	_tick(w)
	t.eq(_lines(w, "rel_friends").size(), 3, "5 friend events in one sol at pop 20 log 3")
	t.eq(w.relationships.pending.size(), 2, "and queue 2")
	t.eq(int(_rs(w).lines_capped), 2, "lines_capped is 2")
	t.eq(int(w.relationships.lines_this_sol), 3, "the sol count is 3")
	_ticks(w, 3)
	t.eq(int(_rs(w).lines_capped), 2, "a queued event waiting through more full ticks is not counted again")
	t.eq(w.relationships.pending.size(), 2, "and stays queued")
	_sol_set(w, 1)
	_tick(w)
	t.eq(_lines(w, "rel_friends").size() + _lines(w, "rel_found_friend").size(), 5, "next sol: the 2 queued lines log")
	t.eq(w.relationships.pending.size(), 0, "queue empty")
	t.eq(int(_rs(w).lines_capped), 2, "lines_capped still 2")
	var first_two_sols := _lines(w)
	if first_two_sols.size() == 5:
		t.check(int(first_two_sols[3].being_id) == 7 or int(first_two_sols[3].being_id) == _id_of(w, 6),
				"the queued lines come out oldest first")
	_end(t)


func test_t10h_stale_queued_event_and_full_queue_drop(t) -> void:
	if not _api(t):
		return
	var w = _five_events()
	_tick(w)
	var p4a := _id_of(w, 6)
	var p4b := _id_of(w, 7)
	_setb(w, p4a, p4b, 0.05)
	t.check(not w.relationships.are_friends(p4a, p4b), "staging: the queued pair lost the friends flag")
	_sol_set(w, 1)
	_tick(w)
	t.eq(int(_rs(w).lines_stale), 1, "a queued event whose pair lost the flag is dropped as stale")
	t.eq(_lines(w, "rel_friends").size(), 4, "so only the other queued event logs")
	# Fourth queued event drops the oldest (queue_max 3).
	var w2 = _pairs_world(4, 20)
	_fill_cap(w2)
	for i in 4:
		_cross_friend(w2, _id_of(w2, 2 * i), _id_of(w2, 2 * i + 1))
	_tick(w2)
	t.eq(_lines(w2).size(), 0, "cap full: nothing logged")
	t.eq(w2.relationships.pending.size(), int(_rd().log.queue_max), "the queue holds queue_max events")
	t.eq(int(_rs(w2).lines_dropped), 1, "the fourth queued event dropped one")
	t.eq(int(_rs(w2).lines_capped), 4, "all four were counted as capped once")
	var los: Array = []
	for e in w2.relationships.pending:
		los.append(int(e.lo))
	t.check(not (_id_of(w2, 0) in los), "the oldest (lowest key) was dropped")
	_end(t)


func test_t10i_a_dropped_first_friendship_keeps_its_first(t) -> void:
	if not _api(t):
		return
	var w = _pairs_world(4, 20)
	_fill_cap(w)
	for i in 4:
		_cross_friend(w, _id_of(w, 2 * i), _id_of(w, 2 * i + 1))
	_tick(w)
	var a := _id_of(w, 0)
	var b := _id_of(w, 1)
	t.check(not _in(w.relationships.found_friend, a) and not _in(w.relationships.found_friend, b), "the dropped event named nobody")
	_sol_set(w, 1)
	_tick(w)
	_sol_set(w, 2)
	var c = _being(w, _room_of_pair(w, 0))
	_cross_friend(w, a, c.id)
	_tick(w)
	var l := _lines(w, "rel_found_friend") + _lines(w, "rel_friends")
	var mine := false
	for e in l:
		if int(e.being_id) == a or int(e.other_id) == a:
			mine = true
	t.check(mine, "the next friendship of a being whose first was dropped gets its line")
	t.check(_in(w.relationships.found_friend, a), "and now it is in found_friend")
	_end(t)


func test_t10j_cap_scales_with_population(t) -> void:
	if not _api(t):
		return
	for pop in [159, 160]:
		var w = _pairs_world(5, pop)
		for i in 5:
			_cross_friend(w, _id_of(w, 2 * i), _id_of(w, 2 * i + 1))
		_tick(w)
		var want := _cap_at(w, pop)
		t.eq(want, 4 if pop == 160 else 3, "staging: spec cap at pop %d" % pop)
		t.eq(_lines(w, "rel_friends").size(), want, "pop %d: %d lines logged" % [pop, want])
	_end(t)


func test_t10k_texts_have_no_digit_and_no_percent(t) -> void:
	if not _api(t):
		return
	var tx: Dictionary = _rd().text
	var all: Array = []
	for k in tx:
		if k == "place":
			for pk in tx.place:
				all.append(str(tx.place[pk]))
		else:
			all.append(str(tx[k]))
	t.check(all.size() >= 16, "sixteen texts found (%d)" % all.size())
	for s in all:
		var r: String = s.replace("{a}", "Kiro").replace("{b}", "Vana")
		var bad := r.contains("%")
		for d in "0123456789":
			bad = bad or r.contains(d)
		t.check(not bad, "no digit and no %% in: %s" % r)
	_end(t)


func test_t10l_log_eviction_is_kind_blind(t) -> void:
	if not _api(t):
		return
	var s := _duo()
	var w = s[0]
	_cross_friend(w, s[1].id, s[2].id)
	_tick(w)
	t.eq(_lines(w).size(), 1, "staging: one relationship line")
	var pairs_before := str(w.relationships.pairs)
	var stats_before := str(_rs(w))
	var cap := int(SimData.colony().log_cap)
	for i in cap + 20:
		w._log("filler", "f%d" % i)
	t.eq(w.log.size(), cap, "the log holds exactly the cap")
	t.eq(_lines(w).size(), 0, "the oldest entry (a relationship line) was evicted first")
	t.eq(str(w.log[0].text), "f%d" % 20, "then the oldest fillers, in order")
	t.eq(str(w.relationships.pairs), pairs_before, "bonds are unchanged by eviction")
	t.eq(str(_rs(w)), stats_before, "stats are unchanged by eviction")
	_end(t)


# ---------------------------------------------------------------- 11. sol reading

func _friends_chain(w, ids: Array) -> void:
	for i in ids.size() - 1:
		_setb(w, ids[i], ids[i + 1], 0.5)


func _people(w, n: int) -> Array:
	var out: Array = []
	for i in n:
		var b = _being(w, HAB1)
		b.state = "eva"
		out.append(b.id)
	return out


func test_t11a_chain_and_lonely_shares(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var ids := _people(w, 7)
	_friends_chain(w, ids.slice(0, 5))
	w.relationships.on_sol(w)
	var rs := _rs(w)
	t.near(float(rs.web_share), 5.0 / 7.0, CMP, "web_share = 5 / 7")
	t.near(float(rs.second_share), 0.0, CMP, "no second part of size 2 or more")
	t.near(float(rs.lonely_share), 2.0 / 7.0, CMP, "lonely_share = 2 / 7")
	t.near(float(rs.friends_mean), 2.0 * 4.0 / 7.0, CMP, "friends_mean = 2 x 4 / 7")
	t.eq(int(rs.pairs), 4, "pairs")
	t.eq(int(rs.friend_pairs), 4, "friend_pairs")
	t.eq(int(rs.close_pairs), 0, "close_pairs")
	t.eq(rs.web_by_sol.size(), 1, "one web entry per boundary")
	t.eq(rs.second_by_sol.size(), 1, "one second entry")
	t.eq(rs.lonely_by_sol.size(), 1, "one lonely entry")
	t.near(float(rs.web_by_sol[0]), 5.0 / 7.0, CMP, "the entry is the reading")
	w.relationships.on_sol(w)
	t.eq(_rs(w).web_by_sol.size(), 2, "a second boundary appends a second entry")
	_end(t)


func test_t11b_two_islands(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var ids := _people(w, 9)
	_friends_chain(w, ids.slice(0, 3))
	_friends_chain(w, ids.slice(3, 7))
	w.relationships.on_sol(w)
	var rs := _rs(w)
	t.near(float(rs.web_share), 4.0 / 9.0, CMP, "web_share is the larger island, 4 / 9")
	t.near(float(rs.second_share), 3.0 / 9.0, CMP, "second_share is the smaller island, 3 / 9")
	t.near(float(rs.lonely_share), 2.0 / 9.0, CMP, "lonely_share 2 / 9")
	t.near(float(rs.friends_mean), 2.0 * 5.0 / 9.0, CMP, "friends_mean 2 x 5 / 9")
	_end(t)


func test_t11c_pop_zero_and_one(t) -> void:
	if not _api(t):
		return
	var w = _world()
	w.relationships.on_sol(w)
	var rs := _rs(w)
	t.near(float(rs.web_share), 0.0, CMP, "pop 0: web 0.0")
	t.near(float(rs.second_share), 0.0, CMP, "pop 0: second 0.0")
	t.near(float(rs.lonely_share), 0.0, CMP, "pop 0: lonely 0.0")
	t.near(float(rs.friends_mean), 0.0, CMP, "pop 0: friends_mean 0.0")
	t.eq(rs.web_by_sol.size(), 1, "pop 0 still appends one entry")
	t.near(float(rs.web_by_sol[0]), 0.0, CMP, "which is 0.0")
	var w1 = _world()
	_being(w1, HAB1)
	w1.relationships.on_sol(w1)
	t.near(float(_rs(w1).web_share), 1.0, CMP, "pop 1: web 1.0")
	t.near(float(_rs(w1).second_share), 0.0, CMP, "pop 1: second 0.0")
	t.near(float(_rs(w1).lonely_share), 1.0, CMP, "pop 1: lonely 1.0")
	_end(t)


func test_t11d_lists_have_the_length_of_pop_by_sol_when_stepped(t) -> void:
	if not _api(t):
		return
	var w = SimWorld.new(7)
	while w.sol() < 3:
		w.step()
	var n: int = w.stats.pop_by_sol.size()
	t.check(n >= 3, "staging: at least three boundaries passed (pop_by_sol %d)" % n)
	t.eq(_rs(w).web_by_sol.size(), n, "web_by_sol has the length of pop_by_sol")
	t.eq(_rs(w).second_by_sol.size(), n, "second_by_sol has the length of pop_by_sol")
	t.eq(_rs(w).lonely_by_sol.size(), n, "lonely_by_sol has the length of pop_by_sol")
	_end(t)


# ---------------------------------------------------------------- 12. pull

class StubRng extends SimRng:
	var u := 0.5

	func chance(_p: float) -> bool:
		return true

	func randf() -> float:
		return u


## Subject S in habitat 1 with two neighbours over finished corridors: N1 (workshop, drive) and N2 (green room, care).
## Returns {w, s, n1, n2}.
func _pull_world(drive: float = 0.0) -> Dictionary:
	var w = _world()
	var n1: int = w.buildings.add_attached("workshop", HAB1, "r", 10, 8, 5).id
	var n2: int = w.buildings.add_attached("green_room", HAB1, "d", 10, 8, 5).id
	var s = _being(w, HAB1, {"drive": drive, "care": 0.0})
	w.rng = StubRng.new(1)
	return {"w": w, "s": s, "n1": n1, "n2": n2}


## Boundary u* of the weighted pick: the subject goes to N1 iff u < u* (u* = w1 / (w1 + w2)).
func _boundary(c: Dictionary) -> float:
	var lo := 0.0
	var hi := 1.0
	for i in 60:
		var mid := (lo + hi) / 2.0
		c.w.rng.u = mid
		c.s.corridor_id = null
		c.s.state = "idle"
		c.s.building_id = HAB1
		c.s._restless_travel(c.w)
		if c.s.corridor_id == c.n1:
			lo = mid
		else:
			hi = mid
	return lo


## The weight of N1 given that N2 weighs `w2`.
func _w1(c: Dictionary, w2: float) -> float:
	var r := _boundary(c)
	return r * w2 / (1.0 - r)


func _floor_w() -> float:
	return float(SimData.beings().room_pull.floor)


func _resident(c: Dictionary, bid: int, friend_of_subject: bool) -> Variant:
	var b = _being(c.w, bid)
	if friend_of_subject:
		_setb(c.w, c.s.id, b.id, 0.5)
	return b


func test_t12a_pull_off_equals_module_disabled(t) -> void:
	if not _api(t):
		return
	var rd := _rd()
	t.eq(float(rd.effects.friend_pull), 0.0, "shipped friend_pull is 0.0")
	t.eq(float(rd.effects.lonely_pull), 0.0, "shipped lonely_pull is 0.0")
	var on := _pull_world(0.8)
	var off := _pull_world(0.8)
	off.w.relationships_enabled = false
	for c in [on, off]:
		var f = _resident(c, c.n1, true)
		f.state = "idle"
		_tick(c.w)
	var expect := (_floor_w() + pow(0.8, float(SimData.beings().room_pull.exponent))) \
			/ (_floor_w() + pow(0.8, float(SimData.beings().room_pull.exponent)) + _floor_w())
	t.near(_boundary(on), expect, 1e-9, "enabled, pulls 0.0: Task 3 weights")
	t.near(_boundary(off), expect, 1e-9, "disabled: Task 3 weights")
	# Same decisions and the next 1000 draws with the real rng.
	var picks := []
	var worlds := []
	for c in [_pull_world(0.8), _pull_world(0.8)]:
		c.w.rng = SimRng.new(5)
		worlds.append(c)
	worlds[1].w.relationships_enabled = false
	for c in worlds:
		var f = _resident(c, c.n1, true)
		f.state = "idle"
		_tick(c.w)
		var seq: Array = []
		for i in 40:
			c.s.corridor_id = null
			c.s.state = "idle"
			c.s.building_id = HAB1
			c.s._restless_travel(c.w)
			seq.append(c.s.corridor_id)
		for i in 1000:
			seq.append(c.w.rng.randf())
		picks.append(seq)
	t.eq(picks[0], picks[1], "same picks and the same next 1000 draws as a world with the module disabled")
	_end(t)


func test_t12b_friend_pull_adds_per_friend_up_to_the_cap(t) -> void:
	if not _api(t):
		return
	var rd := _rd()
	_edit(rd.effects, "friend_pull", 0.25)
	_edit(rd.effects, "friend_pull_cap", 3)
	var c := _pull_world()
	var w2 := _floor_w()
	for n in [1, 2, 3, 4]:
		_resident(c, c.n1, true)
		_tick(c.w)
		var want := _floor_w() + 0.25 * float(mini(n, 3))
		t.near(_w1(c, w2), want, 1e-9, "%d friends at N1: weight %s" % [n, str(want)])
	_end(t)


func test_t12c_lonely_pull_per_person_for_beings_without_friends(t) -> void:
	if not _api(t):
		return
	var rd := _rd()
	_edit(rd.effects, "lonely_pull", 0.15)
	_edit(rd.effects, "friend_pull_cap", 3)
	var c := _pull_world()
	var w2 := _floor_w()
	for n in [1, 2, 3, 4]:
		_resident(c, c.n1, false)
		_tick(c.w)
		var want := _floor_w() + 0.15 * float(mini(n, 3))
		t.near(_w1(c, w2), want, 1e-9, "no friend, %d people at N1: weight %s" % [n, str(want)])
	# A being with one friend (somewhere else) gains nothing from the lonely term.
	var d := _pull_world()
	_resident(d, d.n2, true)
	_resident(d, d.n1, false)
	_resident(d, d.n1, false)
	_tick(d.w)
	# N2 holds the friend and the lonely term is off for this being: both weights are the floor.
	t.near(_boundary(d), 0.5, 1e-9, "a being with one friend gains nothing from the lonely pull")
	_end(t)


# ---------------------------------------------------------------- 13. purity

func _snap(w) -> Dictionary:
	var be: Array = []
	for b in w.beings:
		be.append([b.id, b.building_id, b.state, b.energy])
	var st := {}
	for k in w.stats:
		if k != "relationships":
			st[k] = str(w.stats[k])
	var draws: Array = []
	for i in 1000:
		draws.append(w.rng.randf())
	return {"beings": be, "stats": st, "stocks": [w.colony.oxygen, w.colony.food, w.colony.ice, w.colony.regolith],
			"draws": draws}


func _run_sols(w, n: int) -> void:
	while w.sol() < n:
		w.step()


func test_t13_purity_and_determinism(t) -> void:
	if not _api(t):
		return
	var a = SimWorld.new(42)
	var b = SimWorld.new(42)
	var c = SimWorld.new(42)
	c.relationships_enabled = false
	_run_sols(a, 10)
	_run_sols(b, 10)
	_run_sols(c, 10)
	t.eq(str(a.relationships.pairs), str(b.relationships.pairs), "same-seed worlds: identical pairs")
	t.eq(str(a.relationships.pending), str(b.relationships.pending), "identical pending")
	t.eq(str(_rs(a)), str(_rs(b)), "identical stats.relationships")
	var log_a: Array = []
	var log_b: Array = []
	for e in a.log:
		log_a.append(str(e.text))
	for e in b.log:
		log_b.append(str(e.text))
	t.eq(log_a, log_b, "identical log sequences")
	var sa := _snap(a)
	var sc := _snap(c)
	t.eq(sa.beings, sc.beings, "enabled vs disabled: equal beings (id, building, state, energy)")
	t.eq(sa.stocks, sc.stocks, "equal stocks")
	t.eq(sa.draws, sc.draws, "equal next 1,000 rng draws")
	for k in sc.stats:
		if k == "council":
			continue  # stats.council exists only with the Council module; test 16 of test_council.gd compares it
		t.eq(sa.stats.get(k), sc.stats[k], "old stats key %s is equal" % k)
	t.eq(sa.stats.keys().size(), sc.stats.keys().size(), "same set of old stats keys")
	_end(t)


# ---------------------------------------------------------------- 14. tick timing

func test_t14_one_tick_every_20_steps(t) -> void:
	if not _api(t):
		return
	var w = _world()
	_being(w, HAB1)
	var steps := 0
	var ticks := 0
	var tick_steps: Array = []
	var prev := float(w.relationships.acc_h)
	var per_sol := int(ceil(3.0 * w.clock.sol_h / w.fixed_step))
	while steps < per_sol:
		w.step()
		steps += 1
		var acc := float(w.relationships.acc_h)
		if acc < prev:
			ticks += 1
			if tick_steps.size() < 4:
				tick_steps.append(steps)
		prev = acc
	t.eq(tick_steps, [20, 40, 60, 80], "ticks fall on steps 20, 40, 60, 80")
	var want := int(floor(w.t - w.clock.start_hour) / _tickh())
	t.check(absi(ticks - want) <= 1, "after %d steps: %d ticks, floor(hours / tick_h) is %d (within one)" % [steps, ticks, want])
	_end(t)


# ---------------------------------------------------------------- 15. data parity and sanity

func _spec_keys() -> Array:
	var spec := FileAccess.get_file_as_string("res://docs/specs/relationships.md")
	var i0 := spec.find("```keys:")
	if i0 < 0:
		return []
	var i1 := spec.find("```", i0 + 8)
	var out: Array = []
	for l in spec.substr(i0 + 8, i1 - i0 - 8).split("\n"):
		var s := l.strip_edges()
		if s != "":
			out.append(s)
	return out


func _leaves(node: Variant, prefix: String, out: Array) -> void:
	if node is Dictionary:
		for k in node:
			_leaves(node[k], prefix + "." + str(k), out)
	else:
		out.append(prefix)


func test_t15a_key_path_parity(t) -> void:
	if not _api(t):
		return
	var keys := _spec_keys()
	t.check(keys.size() >= 40, "the spec key list parses (%d keys)" % keys.size())
	var spec_rel: Array = []
	var spec_art: Array = []
	for k in keys:
		if k.begins_with("relationships."):
			spec_rel.append(k)
		elif k.begins_with("art."):
			spec_art.append(k)
		else:
			t.check(false, "unexpected key family in the spec list: %s" % k)
	var leaves: Array = []
	_leaves(_rd(), "relationships", leaves)
	for k in spec_rel:
		t.check(k in leaves, "spec key %s exists in data/relationships.json" % k)
	for k in leaves:
		t.check(k in spec_rel, "data/relationships.json leaf %s is listed in the spec" % k)
	t.eq(leaves.size(), spec_rel.size(), "same number of leaves")
	var art_leaves: Array = []
	_leaves(SimData.load_json("art.json"), "art", art_leaves)
	for k in spec_art:
		t.check(k in art_leaves, "spec key %s exists in data/art.json (existence only)" % k)
	var sd = load("res://sim/sim_data.gd")
	var has := false
	for m in sd.get_script_method_list():
		if m.name == "relationships":
			has = true
	t.check(has, "SimData.relationships() exists")
	if has:
		t.eq(sd.call("relationships").hash(), _rd().hash(), "SimData.relationships() returns data/relationships.json")
	_end(t)


func test_t15c_balance_data_hash_covers_relationships(t) -> void:
	if not _api(t):
		return
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var h0: String = lib.data_hash()
	_edit(_rd(), "tick_h", 2.0)
	var h1: String = lib.data_hash()
	_restore()
	t.check(h0 != h1, "balance data_hash covers data/relationships.json")
	t.eq(lib.data_hash(), h0, "and returns to the old value when the data is restored")
	_end(t)


## The sanity rules of spec section 15, as a list of failed rule names for a data copy.
func _broken_rules(d: Dictionary, bkinds: Array, art_interior: Dictionary, fixed_step: float) -> Array:
	var f: Array = []
	var ln: Dictionary = d.lines
	if not (float(ln.friend_drop) < float(ln.friend) and float(ln.friend) < float(ln.close_drop) \
			and float(ln.close_drop) < float(ln.close)):
		f.append("line order")
	if not float(ln.forget_below) < float(ln.friend_drop):
		f.append("forget_below")
	if not (0.0 < float(d.affinity.floor) and float(d.affinity.floor) <= 1.0):
		f.append("affinity.floor")
	if not float(d.seed.crew) >= float(ln.friend):
		f.append("seed.crew")
	if not float(d.seed.kin_base) >= float(ln.friend):
		f.append("seed.kin_base")
	if not float(d.seed.kin_base) + float(d.seed.kin_warmth) < float(ln.close):
		f.append("kin max")
	if not int(d.log.max_lines_per_sol) >= 1:
		f.append("max_lines_per_sol")
	if not int(d.log.queue_max) >= 0:
		f.append("queue_max")
	if not int(d.log.grief_max) >= 1:
		f.append("grief_max")
	if not (float(d.tick_h) > 0.0 and float(d.tick_h) >= fixed_step):
		f.append("tick_h")
	if not int(d.log.pop_per_line) >= 1:
		f.append("pop_per_line")
	if not (0.0 <= float(d.decay.close_hold) and float(d.decay.close_hold) <= 1.0):
		f.append("close_hold")
	if not int(d.effects.friend_pull_cap) >= 0:
		f.append("friend_pull_cap")
	if not float(d.effects.friend_pull) >= 0.0:
		f.append("friend_pull")
	if not float(d.effects.lonely_pull) >= 0.0:
		f.append("lonely_pull")
	for k in ["room_rate", "warmth_base", "work_rate"]:
		if not float(d.grow[k]) >= 0.0:
			f.append("grow." + k)
	if not float(d.decay.per_h) >= 0.0:
		f.append("decay.per_h")
	for kind in bkinds:
		if not d.text.place.has(kind):
			f.append("text.place." + kind)
	if not (0.0 < float(art_interior.stranger_talk_share) and float(art_interior.stranger_talk_share) <= 1.0):
		f.append("stranger_talk_share")
	if not float(art_interior.stranger_talk_cycle_s) > 0.0:
		f.append("stranger_talk_cycle_s")
	var b: Dictionary = d.balance
	if not (int(b.lonely_window_sols) >= 1 and float(b.lonely_window_sols) == float(int(b.lonely_window_sols))):
		f.append("balance.lonely_window_sols")
	if not float(b.first_friend_gap_sols) > 0.0:
		f.append("balance.first_friend_gap_sols")
	if not float(b.friends_mean_min) <= float(b.friends_mean_max):
		f.append("balance.friends_mean_range")
	if not float(b.selectivity_ratio_min) >= 1.0:
		f.append("balance.selectivity_ratio_min")
	if not float(b.cold_third_friends_stop) > 0.0:
		f.append("balance.cold_third_friends_stop")
	if not (0.0 < float(b.met_friend_share_flag) and float(b.met_friend_share_flag) <= 1.0):
		f.append("balance.met_friend_share_flag")
	var lo_ok: bool = float(b.first_line_min_sol) == float(int(b.first_line_min_sol)) and float(b.first_line_max_sol) == float(int(b.first_line_max_sol))
	if not (lo_ok and int(b.first_line_min_sol) >= 0 and int(b.first_line_min_sol) < int(b.first_line_max_sol)):
		f.append("balance.first_line_window")
	if not float(b.found_friend_tail_per5_max) > 0.0:
		f.append("balance.found_friend_tail_per5_max")
	return f


func test_t15b_data_sanity_rules_hold_and_each_can_fail(t) -> void:
	if not _api(t):
		return
	var bkinds: Array = SimData.buildings().kinds.keys()
	var art_in: Variant = SimData.load_json("art.json").get("interior", {})
	t.check(art_in.has("stranger_talk_share") and art_in.has("stranger_talk_cycle_s"), "art.interior stranger keys exist")
	if not (art_in.has("stranger_talk_share") and art_in.has("stranger_talk_cycle_s")):
		_end(t)
		return
	var fs := float(SimData.sim().fixed_step_hours)
	t.eq(_broken_rules(_rd(), bkinds, art_in, fs), [], "the shipped data breaks no rule")
	# [group, key, broken value, rule]; group "art" edits the art copy, a value of null erases the key.
	var cases := [
		["lines", "friend_drop", 0.5, "line order"],
		["lines", "close", 0.35, "line order"],
		["lines", "forget_below", 0.2, "forget_below"],
		["affinity", "floor", 0.0, "affinity.floor"],
		["seed", "crew", 0.1, "seed.crew"],
		["seed", "kin_base", 0.1, "seed.kin_base"],
		["seed", "kin_warmth", 0.9, "kin max"],
		["log", "max_lines_per_sol", 0, "max_lines_per_sol"],
		["log", "queue_max", -1, "queue_max"],
		["log", "grief_max", 0, "grief_max"],
		["", "tick_h", 0.01, "tick_h"],
		["log", "pop_per_line", 0, "pop_per_line"],
		["decay", "close_hold", 1.5, "close_hold"],
		["effects", "friend_pull_cap", -1, "friend_pull_cap"],
		["effects", "friend_pull", -0.1, "friend_pull"],
		["effects", "lonely_pull", -0.1, "lonely_pull"],
		["grow", "room_rate", -0.1, "grow.room_rate"],
		["decay", "per_h", -0.1, "decay.per_h"],
		["text.place", "workshop", null, "text.place.workshop"],
		["balance", "lonely_window_sols", 0, "balance.lonely_window_sols"],
		["balance", "lonely_window_sols", 2.5, "balance.lonely_window_sols"],
		["balance", "first_friend_gap_sols", 0, "balance.first_friend_gap_sols"],
		["balance", "friends_mean_max", 0.5, "balance.friends_mean_range"],
		["balance", "selectivity_ratio_min", 0.9, "balance.selectivity_ratio_min"],
		["balance", "cold_third_friends_stop", 0.0, "balance.cold_third_friends_stop"],
		["balance", "met_friend_share_flag", 0.0, "balance.met_friend_share_flag"],
		["balance", "met_friend_share_flag", 1.5, "balance.met_friend_share_flag"],
		["balance", "first_line_min_sol", 55, "balance.first_line_window"],
		["balance", "first_line_min_sol", 25.5, "balance.first_line_window"],
		["balance", "first_line_max_sol", 55.5, "balance.first_line_window"],
		["balance", "found_friend_tail_per5_max", 0.0, "balance.found_friend_tail_per5_max"],
		["art", "stranger_talk_share", 0.0, "stranger_talk_share"],
		["art", "stranger_talk_cycle_s", 0.0, "stranger_talk_cycle_s"],
	]
	for c in cases:
		var d: Dictionary = _rd().duplicate(true)
		var a: Dictionary = art_in.duplicate(true)
		var node: Dictionary = d
		if c[0] == "art":
			node = a
		elif c[0] == "text.place":
			node = d.text.place
		elif c[0] != "":
			node = d[c[0]]
		if c[2] == null:
			node.erase(c[1])
		else:
			node[c[1]] = c[2]
		var failed := _broken_rules(d, bkinds, a, fs)
		t.check(c[3] in failed, "a broken copy (%s.%s) fails rule %s (got %s)" % [c[0], c[1], c[3], str(failed)])
	_end(t)


# ---------------------------------------------------------------- 17. hash proof helpers

func test_t17_hash_proof_helpers_on_synthetic_tables(t) -> void:
	_begin(t)
	var P: GDScript = load("res://tests/relationships_hash_proof.gd")
	var A: GDScript = load("res://tests/age_hash_proof.gd")
	var old_lines := ["# header one", "# header two", "sol  pop minO2", "  30    7    94.0", "  60    9    80.5", "",
			"targets for seed 1 (60 sols):", "  T1 PASS x"]
	var age_lines := ["# header one (data_hash differs)", "# header two", "sol  pop minO2 age", "  30    7    94.0 L",
			"  60    9    80.5 S", "", "targets for seed 1 (60 sols):", "  T1 PASS x", "  T11 PASS"]
	var web_lines := ["# header", "# header two", "sol  pop minO2 age web", "  30    7    94.0 L 0.57", "  60    9    80.5 S 0.71", "",
			"targets for seed 1 (60 sols):", "  T1 PASS x", "  T11 PASS"]
	var ob: Array = A.body_of(old_lines)
	var ab: Array = A.body_of(age_lines)
	var wb: Array = A.body_of(web_lines)
	# Table with `age` and `web`: drop web gives the table with age only; drop web and age gives the table with neither.
	var d1: Dictionary = P.drop_web(wb)
	t.eq(d1.body, ab, "drop web on a table with age and web equals the same table without web")
	t.check(not d1.web_absent, "web reported present")
	var d2: Dictionary = P.drop_web_and_age(wb)
	t.eq(d2.body, ob, "drop web and age equals the table with neither")
	t.check(not d2.web_absent and not d2.age_absent, "both reported present")
	t.eq(P.hash_of(d2.body), "\n".join(PackedStringArray(ob)).sha256_text(), "the hash is sha256_text of the joined body")
	t.eq(P.proof_hashes(web_lines).check2, P.proof_hashes(old_lines).check2, "same check-2 hash with the columns removed")
	t.eq(P.proof_hashes(web_lines).check1, P.proof_hashes(age_lines).check1, "same check-1 hash with web removed")
	# A table whose last field is not `web`: column absent, nothing stripped by check 1.
	var a1: Dictionary = P.drop_web(ab)
	t.check(a1.web_absent, "last field is age, not web: web column absent")
	t.eq(a1.body, ab, "and nothing is stripped")
	var a2: Dictionary = P.drop_web_and_age(ab)
	t.check(a2.web_absent and not a2.age_absent, "check 2 on an age-only table strips age only")
	t.eq(a2.body, ob, "giving the Task 1 body")
	# A table with web but no age before it: check 2 reports age absent and strips only web.
	var no_age := ["# h", "# h2", "sol  pop minO2 web", "  30    7    94.0 0.57", "  60    9    80.5 0.71", ""]
	var nb: Array = A.body_of(no_age)
	var n2: Dictionary = P.drop_web_and_age(nb)
	t.check(not n2.web_absent and n2.age_absent, "web present, age absent")
	t.eq(n2.body, ob, "only web was stripped")
	# A reordered table (web before age) is not stripped by check 1.
	var reordered := ["# h", "# h2", "sol  pop minO2 web age", "  30    7    94.0 0.57 L", ""]
	t.check(P.drop_web(A.body_of(reordered)).web_absent, "web must be the LAST field: a reordered table reports it absent")
	# Constants.
	t.eq(P.EXPECTED_T3.size(), 5, "five Task 3 hashes recorded")
	for s in [42, 7, 99, 1234, 2026]:
		t.check(P.EXPECTED_T3.has(s) and str(P.EXPECTED_T3[s]).length() == 16, "Task 3 prefix for seed %d" % s)
	t.eq(P.expected_t1(), A.EXPECTED, "the Task 1 values are the age_hash_proof ones by reference")
	_end(t)


# ---------------------------------------------------------------- 18. friend form at log time

func _room_trio(ids_n: int) -> Variant:
	var w = _world()
	for i in ids_n:
		_being(w, HAB1)
	return w


func test_t18a_queued_events_recompute_the_form(t) -> void:
	if not _api(t):
		return
	var w = _room_trio(5)
	_fill_cap(w)
	_cross_friend(w, 1, 3)
	_cross_friend(w, 1, 5)
	_tick(w)
	t.eq(w.relationships.pending.size(), 2, "both events queued")
	_sol_set(w, 1)
	_tick(w)
	var l := _lines(w)
	t.eq(l.size(), 2, "both log in sol N + 1")
	if l.size() == 2:
		t.eq(str(l[0].kind), "rel_friends", "(1,3) logs in the friends form")
		t.eq(str(l[0].text), _fmt("friends", "N1", "N3") + " " + _place_text("habitat"), "text of the first")
		t.eq(str(l[1].kind), "rel_found_friend", "(1,5) logs as found_friend")
		t.eq(str(l[1].text), _fmt("found_friend", "N5", "N1") + " " + _place_text("habitat"), "5 is new; place from emission")
	_end(t)


func test_t18b_a_queued_event_with_nobody_new_is_dropped(t) -> void:
	if not _api(t):
		return
	var w = _room_trio(5)
	_fill_cap(w)
	_cross_friend(w, 1, 3)
	_cross_friend(w, 2, 5)
	_tick(w)
	_cross_friend(w, 1, 5)
	_tick(w)
	t.eq(w.relationships.pending.size(), 3, "three queued")
	_sol_set(w, 1)
	_tick(w)
	var l := _lines(w)
	t.eq(l.size(), 2, "(1,3) and (2,5) log")
	t.eq(int(_rs(w).lines_stale), 1, "(1,5) is dropped (neither is new): lines_stale + 1")
	_end(t)


func test_t18c_same_tick_events_second_one_sees_the_first(t) -> void:
	if not _api(t):
		return
	var w = _room_trio(3)
	_cross_friend(w, 1, 2)
	_cross_friend(w, 1, 3)
	_tick(w)
	var l := _lines(w)
	t.eq(l.size(), 2, "two lines")
	if l.size() == 2:
		t.eq(str(l[0].kind), "rel_friends", "A-B: the friends form")
		t.eq(str(l[1].kind), "rel_found_friend", "A-C: found_friend")
		t.eq(str(l[1].text), _fmt("found_friend", "N3", "N1") + " " + _place_text("habitat"), "C has found a friend in A")
	_end(t)


func test_t18d_no_found_friend_line_names_a_known_being_first(t) -> void:
	if not _api(t):
		return
	# Two adults sharing a viable room generate new friendships without relying on instant newborns.
	var w = _world(42)
	_being(w, HAB1)
	_being(w, HAB1)
	w.colony.ice = 10000.0
	_run_sols(w, 60)
	var seen := {}
	var checked := 0
	for e in w.log:
		var k := str(e.kind)
		if k == "rel_found_friend":
			checked += 1
			t.check(not seen.has(int(e.being_id)), "found_friend {a} %d was not named before" % int(e.being_id))
			seen[int(e.being_id)] = true
			seen[int(e.other_id)] = true
		elif k == "rel_friends":
			checked += 1
			t.check(not seen.has(int(e.being_id)) and not seen.has(int(e.other_id)), "friends form: both new")
			seen[int(e.being_id)] = true
			seen[int(e.other_id)] = true
	t.check(checked > 0, "the 60-sol run logged friend lines to check (%d)" % checked)
	_end(t)


# ---------------------------------------------------------------- 19. crew drift at revalidation

func test_t19_crew_drift_revalidation(t) -> void:
	if not _api(t):
		return
	var w = _crew_world()
	var ids: Array = []
	for b in w.beings:
		ids.append(b.id)
	var near_drop := float(_rd().lines.friend_drop) + 0.00005
	_fill_cap(w)
	_setb(w, ids[0], ids[1], near_drop)
	_setb(w, ids[0], ids[2], near_drop)
	_tick(w)
	t.eq(w.relationships.pending.size(), 2, "two crew drift events queued under a full cap")
	t.eq(int(_rs(w).crew_drifted), 2, "crew_drifted counts both")
	_sol_set(w, 1)
	_tick(w)
	var l := _lines(w, "rel_drifted")
	t.eq(l.size(), 1, "the first logs")
	if l.size() == 1:
		t.check(_names_ok(l[0], ids[0], ids[1]), "and names founder F and the other")
	t.eq(int(_rs(w).lines_stale), 1, "the second is dropped as stale (F is named)")
	t.eq(int(_rs(w).crew_drifted), 2, "crew_drifted unchanged")
	# A drop when F is already named makes no event.
	var capped: int = int(_rs(w).lines_capped)
	_setb(w, ids[0], ids[3], near_drop)
	_tick(w)
	t.eq(int(_rs(w).crew_drifted), 3, "the silent drop moves crew_drifted")
	t.eq(int(_rs(w).lines_stale), 1, "and not lines_stale")
	t.eq(int(_rs(w).lines_capped), capped, "and not lines_capped")
	t.eq(_lines(w, "rel_drifted").size(), 1, "and logs nothing")
	# A crew pair that was close logs through drift_close and leaves crew_drift_named unchanged.
	_sol_set(w, 2)
	var home: int = w.beings[4].building_id
	w.beings[4].state = "idle"
	w.beings[5].state = "idle"
	w.beings[4].building_id = home
	w.beings[5].building_id = home
	_cross_close(w, ids[4], ids[5])
	_tick(w)
	t.check(_flag(w, ids[4], ids[5], "was_close"), "staging: the crew pair 5, 6 was close")
	w.beings[5].state = "eva"
	_setb(w, ids[4], ids[5], near_drop)
	_sol_set(w, 3)
	_tick(w)
	t.eq(_lines(w, "rel_drifted").size(), 2, "the was_close crew pair logs a drifted line")
	t.check(not _in(w.relationships.crew_drift_named, ids[4]) and not _in(w.relationships.crew_drift_named, ids[5]),
			"and leaves crew_drift_named unchanged")
	_end(t)


# ---------------------------------------------------------------- 20. grief order

func test_t20_grief_before_queued_events_and_not_counted(t) -> void:
	if not _api(t):
		return
	var w = _pairs_world(1, 20)
	_fill_cap(w)
	var a := _id_of(w, 0)
	var b := _id_of(w, 1)
	_cross_friend(w, a, b)
	_tick(w)
	t.eq(w.relationships.pending.size(), 1, "staging: one queued friend event")
	var victim := 7
	var m1 := 9
	var m2 := 11
	_setb(w, victim, m1, 0.7)
	_setb(w, victim, m2, 0.5)
	w.relationships.lines_this_sol = int(w.relationships.lines_this_sol) - 1
	var before: int = w.relationships.lines_this_sol
	_kill(w, victim)
	_tick(w)
	var l := _lines(w)
	t.eq(l.size(), 3, "two grief lines and the queued friend line")
	if l.size() == 3:
		t.eq(str(l[0].kind), "rel_grief", "grief first")
		t.eq(str(l[1].kind), "rel_grief", "grief second")
		t.eq(str(l[2].kind), "rel_friends", "then the queued event, still offered after")
	t.eq(int(w.relationships.lines_this_sol), before + 1, "the cap count rose by the one capped line only")
	_end(t)


# ---------------------------------------------------------------- 21. cap reset

func test_t21_cap_resets_at_the_first_tick_of_the_next_sol(t) -> void:
	if not _api(t):
		return
	var w = _pairs_world(4, 20)
	_sol_late(w, 0)
	for i in 4:
		_cross_friend(w, _id_of(w, 2 * i), _id_of(w, 2 * i + 1))
	_tick(w)
	t.eq(int(w.relationships.lines_this_sol), 3, "3 capped lines logged late in sol 0")
	t.eq(w.relationships.pending.size(), 1, "one queued")
	_tick(w)
	t.eq(int(w.relationships.lines_this_sol), 3, "a later tick in sol 0 with no new events leaves the count at 3")
	t.eq(w.relationships.pending.size(), 1, "and the queue waits")
	_sol_set(w, 1)
	_tick(w)
	t.eq(int(w.relationships.lines_sol), 1, "the first tick of sol 1 sets lines_sol")
	t.eq(int(w.relationships.lines_this_sol), 1, "the count was reset to 0 and the queued event logged (1)")
	t.eq(w.relationships.pending.size(), 0, "queue empty")
	_end(t)


# ---------------------------------------------------------------- 22. pull guard

func test_t22a_no_module_or_disabled_gives_task_3_weights(t) -> void:
	if not _api(t):
		return
	var rd := _rd()
	_edit(rd.effects, "friend_pull", 0.25)
	_edit(rd.effects, "lonely_pull", 0.15)
	_edit(rd.effects, "friend_pull_cap", 3)
	var exp_: Dictionary = SimData.beings().room_pull
	var base := (_floor_w() + pow(0.8, float(exp_.exponent))) / (_floor_w() + pow(0.8, float(exp_.exponent)) + _floor_w())
	var c := _pull_world(0.8)
	var f = _resident(c, c.n1, true)
	f.state = "idle"
	_resident(c, c.n1, false)
	_tick(c.w)
	var live := _boundary(c)
	t.check(absf(live - base) > 1e-6, "staging: with the module on the pull moves the weights")
	c.w.relationships_enabled = false
	t.near(_boundary(c), base, 1e-9, "relationships_enabled false: Task 3 weights exactly")
	c.w.relationships_enabled = true
	c.w.relationships = null
	t.near(_boundary(c), base, 1e-9, "world.relationships null: Task 3 weights exactly")
	_end(t)


func test_t22b_missing_present_entry_and_zero_cap_add_nothing(t) -> void:
	if not _api(t):
		return
	var rd := _rd()
	_edit(rd.effects, "friend_pull", 0.25)
	_edit(rd.effects, "lonely_pull", 0.15)
	_edit(rd.effects, "friend_pull_cap", 3)
	var c := _pull_world(0.8)
	var exp_: Dictionary = SimData.beings().room_pull
	var base := (_floor_w() + pow(0.8, float(exp_.exponent))) / (_floor_w() + pow(0.8, float(exp_.exponent)) + _floor_w())
	t.near(_boundary(c), base, 1e-9, "no tick yet, no present entries: nothing added")
	_tick(c.w)
	t.near(_boundary(c), base, 1e-9, "empty neighbours after a tick: nothing added")
	_resident(c, c.n1, true)
	_resident(c, c.n1, false)
	_tick(c.w)
	rd.effects.friend_pull_cap = 0
	t.near(_boundary(c), base, 1e-9, "friend_pull_cap 0 adds nothing")
	_end(t)


# ---------------------------------------------------------------- 23. pair key and order

func test_t23a_pair_key_arithmetic(t) -> void:
	if not _api(t):
		return
	var w = _world()
	for i in 11:
		var b = _being(w, HAB1)
		b.state = "eva"
	_setb(w, 9, 10, 0.5)
	_setb(w, 10, 11, 0.5)
	t.check(w.relationships.pairs.has(9 * SHIFT + 10), "the key of (9, 10) is 9 x 2^20 + 10")
	t.check(9 * SHIFT + 10 < 10 * SHIFT + 11, "it sorts before (10, 11)")
	t.check(w.relationships.pairs.has(10 * SHIFT + 11), "the key of (10, 11)")
	_setb(w, 10, 9, 0.6)
	t.eq(w.relationships.pairs.size(), 2, "the key is the unordered pair (10, 9) is (9, 10)")
	_end(t)


func _order_world() -> Variant:
	var w = _world()
	for i in 10:
		var b = _being(w, REACTOR)
		b.state = "sleep"
		b.sleep_started_t = w.t
	for id in [2, 9, 10]:
		for b in w.beings:
			if b.id == id:
				b.state = "idle"
				b.building_id = HAB1
	_fill_cap(w)
	_cross_friend(w, 2, 9)
	_cross_friend(w, 2, 10)
	_cross_friend(w, 9, 10)
	_tick(w)
	return w


func test_t23b_events_are_offered_in_ascending_key_order(t) -> void:
	if not _api(t):
		return
	var w = _order_world()
	var got: Array = []
	for e in w.relationships.pending:
		got.append([int(e.lo), int(e.hi)])
	t.eq(got, [[2, 9], [2, 10], [9, 10]], "queue order is (2,9), (2,10), (9,10), not insertion or string order")
	var w2 = _order_world()
	var l1: Array = []
	var l2: Array = []
	_sol_set(w, 1)
	_sol_set(w2, 1)
	_tick(w)
	_tick(w2)
	for e in w.log:
		l1.append(str(e.text))
	for e in w2.log:
		l2.append(str(e.text))
	t.eq(l1, l2, "two same-seed worlds emit identical log sequences")
	t.check(l1.size() >= 2, "and the sequence is not empty")
	_end(t)


# ---------------------------------------------------------------- 24. kin newborn line

func test_t24_kin_newborn_gets_the_found_friend_line(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var parent = _being(w, HAB1)
	var other = _being(w, HAB1)
	_add_to(w.relationships.found_friend, other.id)
	_tick(w)
	var nb = _being(w, HAB1)
	nb.parent_id = parent.id
	_tick(w)
	t.check(_flag(w, parent.id, nb.id, "kin"), "staging: the kin pair exists")
	t.eq(_lines(w).size(), 0, "the kin pair logs nothing")
	_cross_friend(w, nb.id, other.id)
	_tick(w)
	var l := _lines(w)
	t.eq(l.size(), 1, "one line")
	if l.size() == 1:
		t.eq(str(l[0].kind), "rel_found_friend", "found_friend form")
		t.eq(str(l[0].text), _fmt("found_friend", nb.name, other.name) + " " + _place_text("habitat"),
				"{newborn} has found a friend in {other}.")
	_end(t)


# ---------------------------------------------------------------- 25. renewal counts

func _renewal_check(t, w, a: int, b: int, label: String) -> void:
	_setb(w, a, b, float(_rd().lines.friend_drop) - 0.01)
	t.check(not w.relationships.are_friends(a, b), "%s: staging, the seeded friendship lapsed" % label)
	_cross_friend(w, a, b)
	_tick(w)
	t.check(w.relationships.are_friends(a, b), "%s: grown back past the friend line" % label)
	t.eq(int(_rs(w).friendships_renewed), 1, "%s: friendships_renewed + 1" % label)
	t.eq(int(_rs(w).friendships_formed), 0, "%s: not friendships_formed" % label)
	t.eq(_lines(w).size(), 0, "%s: no friend line" % label)
	t.eq(_rs(w).first_friendship_sol, null, "%s: first_friendship_sol stays null" % label)
	t.eq(_rs(w).first_mars_born_friendship_sol, null, "%s: first_mars_born_friendship_sol stays null" % label)


func test_t25_renewals_are_not_formations(t) -> void:
	if not _api(t):
		return
	var w = _crew_world()
	var home: int = w.beings[0].building_id
	w.beings[0].state = "idle"
	w.beings[1].state = "idle"
	w.beings[0].building_id = home
	w.beings[1].building_id = home
	_renewal_check(t, w, w.beings[0].id, w.beings[1].id, "crew pair")
	var k := _kin_world()
	var kw = k[0]
	k[1].state = "idle"
	k[2].state = "idle"
	k[1].building_id = HAB1
	k[2].building_id = HAB1
	_restore()
	_renewal_check(t, kw, k[1].id, k[2].id, "kin pair")
	_end(t)


# ---------------------------------------------------------------- 26. close hold arithmetic

func test_t26_close_hold_closed_form(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1, {"restless": 0.4})
	var b = _being(w, HAB2, {"restless": 0.4})
	_setb(w, a.id, b.id, _close_line())
	var d: Dictionary = _rd().decay
	var n := 1777
	_ticks(w, n)
	var closed := _close_line() - float(n) * float(d.close_hold) * float(d.per_h) * (float(d.restless_base) + 0.4)
	t.near(_bond(w, a.id, b.id), closed, 1e-9, "after 1,777 ticks the bond is the closed form (%s)" % str(closed))
	t.check(_flag(w, a.id, b.id, "close"), "and the pair is still close")
	_tick(w)
	t.check(not _flag(w, a.id, b.id, "close"), "the next tick takes it under close_drop and clears the flag")
	var after := _bond(w, a.id, b.id)
	_tick(w)
	t.near(after - _bond(w, a.id, b.id), _decay(a, b, false), 1e-12, "the tick after decays at the open rate")
	_end(t)
