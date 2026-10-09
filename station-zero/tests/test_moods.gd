extends RefCounted
## Task 6a, step 3 (tests first, red): the sim-side emotions tests. Spec: docs/specs/emotions.md revision 3 (owner decisions
## A to D in docs/design/task-6-scoping.md and the owner answers Q1 to Q4 at the top of the spec). Section 13 tests 1 to 21,
## 25 (its pure helpers; the 300-sol half is tests/mood_hash_proof.gd), 26 to 31, 34 to 36 live here. The view tests (22, 22b,
## 23, 24, 33 and the panel half of 13h and 36) are in tests/test_view_moods.gd; test 32 (selection rules) needs view code that
## does not exist and is parked in tests/deferred/test_view_selection.gd.txt. Test 30 (the existing suite passes with the module
## on) is the run of tests/run_tests.gd itself and cannot be a unit test.
##
## Naming: test_tNN_* is spec test NN (letters split one spec test into several functions so a failure points at one sentence).
## Almost everything is a hand-made blank world (SimWorld.new(seed, {"blank": true}), add_building, add_being) with the mood
## fields overwritten (spec 13 staging line), driven by one of two seams:
##   _tick(w)    a REAL relationships tick (relationships.on_step(w, tick_h)) followed by moods.on_step(w);
##   _inject(w)  no relationships tick: it writes relationships.events / with_friend, bumps relationships.ticks and calls
##               moods.on_step(w). Used when a test needs an exact event list (the feed itself is test 29).
## Staged beings are frozen by default (mood_k 0.0, so decay is off and a push lands on the deviation the test wrote) and asleep
## (so they are never together and never grow a bond); `awake` and `frozen=false` switch that. Only tests 17, 18, 21, 25, 27,
## 31 and 34 step the real simulation.
##
## Class access: nothing here names `Moods`, `world.moods` ... as a static type. Worlds, beings and the module are untyped
## Variants and the script is reached with load("res://sim/moods.gd"), so on a tree without the implementation the file still
## parses and each test fails cleanly (every test starts with `_api()`, which records one failed check per missing piece and
## makes the test return before it can abort on a missing member; an aborted test would otherwise pass silently, because the
## runner only fails a test with zero checks. _begin/_end add the same guard to the test body). Data is read with
## SimData.load_json("mood.json"); tests that need another value overwrite keys of the WORLD'S OWN copy `world.moods.cfg`
## (the Council staging seam) or, for the gains, the cached members `world.mood_travel_gain` / `world.mood_energy_gain`.
##
## API ASSUMED beyond the spec's own names (the simplest reading; the implementer should match or tell the test author):
##  - Module res://sim/moods.gd (class Moods): static `temperament(chart) -> {base, halflife}`; instance `on_step(world)`,
##    `on_sol(world)`; fields as spec section 3 (`cfg` a deep copy of SimData.moods() made at begin, `seen_ticks`, `seen_pledge`,
##    `max_id_seen`, `pending_hard` (null or "ice"/"air"/"food"), `pending_pledge`, `lines_sol`, `lines_this_sol`, `agg`).
##    `SimData.moods()` returns data/mood.json. `SimWorld.moods`, `.moods_enabled`, `.mood_travel_gain`, `.mood_energy_gain`;
##    `SimWorld.new(seed, {"blank": true, "moods_enabled": false})` is the neutral-founder option.
##  - Being fields: mood, mood_base, mood_halflife (sols), mood_k, mood_band (0 heavy .. 4 bright), mood_why (null or
##    {key, id, name, t, clause, sign}), mood_quiet_t, mood_down_t (null or sim hour). Why keys: grief, friend, close, lapse,
##    lapse_close, hard_sol, pledge, and "birth" or "birth_parent" (spec 5.2 and test 7 say birth, 5.4 rule 1 says birth_parent:
##    both accepted, spec question 4). A hard why has clause "ice"|"air"|"food"; hard and pledge whys carry id/name of any kind.
##  - Relationships additions: `events` Array of {kind: grief|friend|close|lapse|lapse_close, a, b[, bond, name]} (spec 9.1; for
##    friend, close, lapse and lapse_close a is the lower id), `with_friend` PackedByteArray by id, `friend_pairs()` ->
##    {lo, hi, flags} (flag bits 1 close, 2 kin, 4 crew), `friends_of(id)` -> Array of {id, close, kin, crew, bond}.
##  - A pair event pushes both beings, so `stats.moods.pushes.friend` counts 2 per pair event (one push per being; spec
##    question 6). A colony push counts once per being.
##  - Log kinds `mood_quiet` / `mood_relief` with being_id, other_id (the why's id, else null), place "", building_id null;
##    text = data text.lines.<key>.<a|b> with {name} and {other} replaced; variant a when (being_id + sol) is even, b when odd
##    (spec question 7). Names of staged beings are N<id>.
##  - Idle drain is measured through Being.update(world, dt) (energy before and after on an idle being that does not decide);
##    Being.drain_per_h() keeps its zero-argument form for the states whose drain mood does not touch (spec question 8).
##  - stats.moods keys as spec section 8; `pushes` is a Dictionary with the nine push keys.
## Where the spec leaves a detail open, extended simply (listed in the task report as numbered spec questions): the hysteresis
## band checks use 0.0001 past the line, never exactly the line; a stored why is asserted only where |d| is clearly on one
## side of why.show_dev (rev 3 does not say whether it is cleared after the decay step or at step 6, spec question 3).

const SHIFT := 1048576
const CMP := 1e-12
const REACTOR := 1
const HAB1 := 2
const HAB2 := 3
const WORKSHOP := 4
const GREEN := 5

var _undo: Array = []


# ---------------------------------------------------------------- guards, data and api

func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func _begin(t) -> void:
	t._failures.append(_abort_msg(t))


func _end(t) -> void:
	_restore()
	t._failures.erase(_abort_msg(t))


func _edit(dict: Dictionary, key: String, value: Variant) -> void:
	_undo.append([dict, key, dict[key]])
	dict[key] = value


func _restore() -> void:
	while not _undo.is_empty():
		var u: Array = _undo.pop_back()
		u[0][u[1]] = u[2]


func _has_static(script: Variant, method: String) -> bool:
	if script == null:
		return false
	for m in script.get_script_method_list():
		if m.name == method:
			return true
	return false


## The mood data (the cache the module copies at creation), {} while the file does not exist.
func _md() -> Dictionary:
	if not FileAccess.file_exists("res://data/mood.json"):
		return {}
	var d: Variant = SimData.load_json("mood.json")
	return d if d is Dictionary else {}


func _rd() -> Dictionary:
	return SimData.relationships()


func _tickh() -> float:
	return float(_rd().tick_h)


func _moods_script() -> Variant:
	if FileAccess.file_exists("res://sim/moods.gd"):
		return load("res://sim/moods.gd")
	return null


## One failed check naming every missing piece of the API; true when every piece the tests touch exists.
func _api(t) -> bool:
	var missing: Array[String] = []
	if not FileAccess.file_exists("res://data/mood.json"):
		missing.append("data/mood.json")
	var ms = _moods_script()
	if ms == null:
		missing.append("sim/moods.gd")
	elif not _has_static(ms, "temperament"):
		missing.append("Moods.temperament()")
	var sd = load("res://sim/sim_data.gd")
	if not _has_static(sd, "moods"):
		missing.append("SimData.moods()")
	var w = SimWorld.new(1, {"blank": true})
	if "moods" in w and w.moods != null:
		for m in ["on_step", "on_sol"]:
			if not w.moods.has_method(m):
				missing.append("world.moods.%s()" % m)
		for f in ["cfg", "seen_ticks", "seen_pledge", "max_id_seen", "pending_hard", "pending_pledge", "lines_sol",
				"lines_this_sol", "agg"]:
			if not (f in w.moods):
				missing.append("world.moods.%s" % f)
	else:
		missing.append("SimWorld.moods")
	for f in ["moods_enabled", "mood_travel_gain", "mood_energy_gain"]:
		if not (f in w):
			missing.append("SimWorld.%s" % f)
	var rel = w.relationships
	for f in ["events", "with_friend"]:
		if not (f in rel):
			missing.append("world.relationships.%s" % f)
	for m in ["friend_pairs", "friends_of"]:
		if not rel.has_method(m):
			missing.append("world.relationships.%s()" % m)
	var b = w.add_being(HAB1)
	for f in ["mood", "mood_base", "mood_halflife", "mood_k", "mood_band", "mood_why", "mood_quiet_t", "mood_down_t"]:
		if not (f in b):
			missing.append("Being.%s" % f)
	if not w.stats.has("moods"):
		missing.append("stats.moods")
	else:
		for k in ["pushes", "bright_beings", "light_beings", "pushes_zeroed", "lines", "lines_dropped", "min_dev", "max_dev",
				"min_dev_sol", "max_dev_sol", "mean_by_sol", "sd_by_sol", "heavy_by_sol", "mean", "sd", "heavy_share"]:
			if not w.stats.moods.has(k):
				missing.append("stats.moods.%s" % k)
	t.check(missing.is_empty(), "missing API: " + ", ".join(PackedStringArray(missing)))
	if missing.is_empty():
		_begin(t)
	return missing.is_empty()


# ---------------------------------------------------------------- staging

## Blank world: reactor, two habitats, workshop, green room (ids 1 to 5, in that order).
func _world(seed_in: int = 1) -> Variant:
	var w = SimWorld.new(seed_in, {"blank": true})
	w.add_building("reactor", 0, 0)
	w.add_building("habitat", 40, 0)
	w.add_building("habitat", 80, 0)
	w.add_building("workshop", 120, 0)
	w.add_building("green_room", 160, 0)
	return w


## A being with neutral-but-explicit traits and the mood fields written (spec 13 staging): baseline `base`, deviation `d`,
## half-life `half` sols. Frozen (mood_k 0) by default; asleep (never together with anyone) unless `awake`.
func _being(w, bid: int, base: float = 0.0, d: float = 0.0, half: float = 4.0, frozen: bool = true, awake: bool = false) -> Variant:
	var b = w.add_being(bid)
	b.name = "N%d" % b.id
	b.energy = 70.0
	for k in ["sociability", "care", "restless", "steady", "curiosity"]:
		b.persona.traits[k] = 0.4
	b.persona.description = "warm and nurturing"
	b.mood_base = base
	b.mood = base + d
	b.mood_halflife = half
	b.mood_k = 0.0 if frozen else _k_of(w, half)
	b.mood_band = 2
	b.mood_why = null
	if awake:
		b.state = "idle"
	else:
		b.state = "sleep"
		b.sleep_started_t = w.t
	return b


func _k_of(w, half: float) -> float:
	return 1.0 - pow(0.5, _tickh() / (half * float(w.clock.sol_h)))


func _d(b) -> float:
	return float(b.mood) - float(b.mood_base)


## One real relationships tick, then the mood tick.
func _tick(w) -> void:
	w.relationships.on_step(w, _tickh())
	w.moods.on_step(w)


func _ticks(w, n: int) -> void:
	for i in n:
		_tick(w)


## A mood tick without a relationships tick: `events` is the list the feed would have written, `friends` the ids with a
## friend together this tick.
func _inject(w, events: Array = [], friends: Array = []) -> void:
	var rel = w.relationships
	rel.events = events
	var top := 1
	for b in w.beings:
		top = maxi(top, b.id + 1)
	var wf := PackedByteArray()
	wf.resize(top)
	wf.fill(0)
	for id in friends:
		wf[id] = 1
	rel.with_friend = wf
	rel.ticks += 1
	w.moods.on_step(w)


func _ev(kind: String, a: int, b: int, bond: float = 0.0, name: String = "") -> Dictionary:
	var e := {"kind": kind, "a": a, "b": b}
	if kind == "grief":
		e["bond"] = bond
		e["name"] = name if name != "" else "Gone%d" % b
	return e


func _sol_set(w, n: int) -> void:
	w.t = w.clock.start_hour + float(n) * w.clock.sol_h
	w.buildings.now = w.t


func _kill(w, id: int) -> void:
	for b in w.beings:
		if b.id == id:
			w._kill(b, "other")
			return


func _pair(w, a: int, b: int) -> Variant:
	return w.relationships.pairs.get(mini(a, b) * SHIFT + maxi(a, b))


func _setb(w, a: int, b: int, bond: float) -> void:
	w.relationships.debug_set_bond(a, b, bond)


func _friend_line() -> float:
	return float(_rd().lines.friend)


func _close_line() -> float:
	return float(_rd().lines.close)


func _p(key: String) -> float:
	return float(_md().push[key])


## Headroom scale of spec section 2 for a push `p` on a being at deviation `d`.
func _scale(d: float, p: float, ceil_dev: float = INF) -> float:
	var rg: Dictionary = _md().range
	if p > 0.0:
		var c: float = float(rg.ceil_dev) if ceil_dev == INF else ceil_dev
		return clampf(1.0 - d / c, 0.0, 1.0)
	return clampf(1.0 - d / float(rg.floor_dev), 0.0, 1.0)


## The nominal grief push for a bond (linear between grief_min at the friend line and grief_max at 1.0).
func _grief_nominal(bond: float) -> float:
	var pu: Dictionary = _md().push
	var lo := _friend_line()
	var f := clampf((bond - lo) / (1.0 - lo), 0.0, 1.0)
	return float(pu.grief_min) + (float(pu.grief_max) - float(pu.grief_min)) * f


func _stocks(w, ice: bool = false, air: bool = false, food: bool = false) -> void:
	w.colony.oxygen = w.colony.o2_cap() * (0.1 if air else 1.0)
	w.colony.food = w.colony.food_cap() * (0.1 if food else 1.0)
	w.colony.ice = 0.0 if ice else 1000000.0


func _stage_why(b, key: String, id: int, sign: int, d: float, t_set: Variant = null, clause: String = "") -> void:
	b.mood = float(b.mood_base) + d
	b.mood_why = {"key": key, "id": id, "name": "N%d" % id, "t": 0.0 if t_set == null else t_set, "clause": clause, "sign": sign}


func _why_key(b) -> String:
	return "" if b.mood_why == null else str(b.mood_why.key)


func _push_count(w, key: String) -> int:
	return int(w.stats.moods.pushes.get(key, 0))


## A Being-state hash for the equality tests.
func _digest_world(w) -> String:
	var parts: Array = []
	for b in w.beings:
		parts.append([b.id, b.building_id, b.state, b.energy, b.wait_h, b.mood, b.mood_band, b.mood_why])
	return JSON.stringify(parts).sha256_text()


# ---------------------------------------------------------------- 1. temperament

func _chart(world_kind: String, sign_i: int) -> Dictionary:
	if world_kind == "mars":
		return {"world": "mars", "sun": 0, "deimos": sign_i, "phobos": 0, "rise": 0, "earth": 0}
	return {"world": "earth", "sun": 0, "moon": sign_i, "rise": 0}


func _expect_temper(sign_i: int) -> Dictionary:
	var tp: Dictionary = _md().temperament
	var s: Dictionary = SimData.signs()[sign_i]
	return {"base": float(tp.element_base[s.element]) + float(tp.modality_base[s.modality]),
			"halflife": float(tp.halflife_sols[s.modality]) * float(tp.halflife_mult[s.element])}


## The twelve (base, half-life) pairs of spec 5.1 by "<modality> <element>".
const SPEC_TABLE := {
	"cardinal fire": [0.15, 3.6], "fixed fire": [0.12, 1.8], "mutable fire": [0.09, 7.2],
	"cardinal air": [0.09, 4.0], "fixed air": [0.06, 2.0], "mutable air": [0.03, 8.0],
	"cardinal earth": [-0.01, 3.2], "fixed earth": [-0.04, 1.6], "mutable earth": [-0.07, 6.4],
	"cardinal water": [-0.11, 5.2], "fixed water": [-0.14, 2.6], "mutable water": [-0.17, 10.4],
}


func test_t01a_temperament_table_for_twelve_signs_and_two_worlds(t) -> void:
	if not _api(t):
		return
	var ms = _moods_script()
	var lo_b := 1e9
	var hi_b := -1e9
	var lo_h := 1e9
	var hi_h := -1e9
	for i in 12:
		var e := _expect_temper(i)
		var s: Dictionary = SimData.signs()[i]
		for wk in ["mars", "earth"]:
			var r: Dictionary = ms.call("temperament", _chart(wk, i))
			t.near(float(r.base), e.base, CMP, "%s sign %d base" % [wk, i])
			t.near(float(r.halflife), e.halflife, CMP, "%s sign %d half-life" % [wk, i])
		var spec: Array = SPEC_TABLE["%s %s" % [s.modality, s.element]]
		t.near(float(e.base), float(spec[0]), 1e-9, "shipped base of %s %s matches spec 5.1" % [s.modality, s.element])
		t.near(float(e.halflife), float(spec[1]), 1e-9, "shipped half-life of %s %s matches spec 5.1" % [s.modality, s.element])
		lo_b = minf(lo_b, e.base)
		hi_b = maxf(hi_b, e.base)
		lo_h = minf(lo_h, e.halflife)
		hi_h = maxf(hi_h, e.halflife)
	t.near(lo_b, -0.17, 1e-9, "lowest base")
	t.near(hi_b, 0.15, 1e-9, "highest base")
	t.near(lo_h, 1.6, 1e-9, "shortest half-life")
	t.near(hi_h, 10.4, 1e-9, "longest half-life")
	var bases: Array = []
	for i in 12:
		bases.append(_expect_temper(i).base)
	var mean := 0.0
	for x in bases:
		mean += float(x)
	t.near(mean / 12.0, 0.0, 0.02, "mean base over the twelve signs is about 0 (spec 5.1)")
	_end(t)


func test_t01b_a_neutral_chartless_being_and_the_test_seam(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var b = w.add_being(HAB1)
	var neu: Dictionary = _md().temperament.neutral
	t.eq(float(b.mood), 0.0, "add_being: mood 0")
	t.eq(float(b.mood_base), float(neu.base), "add_being: neutral base")
	t.near(float(b.mood_halflife), float(neu.halflife_sols), CMP, "add_being: neutral half-life")
	t.near(float(b.mood_k), _k_of(w, float(neu.halflife_sols)), CMP, "add_being: mood_k derived from the neutral half-life")
	t.eq(int(b.mood_band), 2, "add_being: band even")
	t.check(b.mood_why == null, "add_being: no why")
	t.check(float(b.mood_quiet_t) <= -1e8, "add_being: mood_quiet_t is -1e9 at start")
	t.check(b.mood_down_t == null, "add_being: mood_down_t null")
	_end(t)


func test_t01c_earth_born_founders_use_the_moon_and_newborns_the_deimos(t) -> void:
	if not _api(t):
		return
	var w = SimWorld.new(42)
	t.check(w.founders.size() >= 7, "staging: seven founders")
	var tp: Dictionary = _md().temperament
	t.eq(str(tp.inner_key.earth), "moon", "inner placement of an Earth chart is the Moon")
	t.eq(str(tp.inner_key.mars), "deimos", "inner placement of a Mars chart is the Deimos")
	var distinct := {}
	for i in w.founders.size():
		var ch: Dictionary = w.founders[i].chart
		var e := _expect_temper(int(ch.moon))
		var b = w.beings[i]
		t.near(float(b.mood_base), e.base, CMP, "founder %d base from its Moon" % i)
		t.near(float(b.mood_halflife), e.halflife, CMP, "founder %d half-life from its Moon" % i)
		t.near(float(b.mood), float(b.mood_base), CMP, "founder %d starts at its baseline" % i)
		t.near(float(b.mood_k), _k_of(w, e.halflife), CMP, "founder %d mood_k" % i)
		distinct[snappedf(e.base, 0.001)] = true
	t.check(distinct.size() >= 2, "the founders do not all share one baseline")
	# A Mars-born newborn is tempered by the Deimos of the chart computed for the birth.
	var hb = w.buildings.get_building(2)
	var parent = w.beings[0]
	w._create_newborn(hb, parent)
	var nb = w.beings.back()
	var chart: Dictionary = w.sky.mars_chart(w.t, w.clock.lon_of_tile(hb.tx + hb.tw / 2.0))
	var en := _expect_temper(int(chart.deimos))
	t.near(float(nb.mood_base), en.base, CMP, "newborn base from its Deimos")
	t.near(float(nb.mood_halflife), en.halflife, CMP, "newborn half-life from its Deimos")
	t.near(float(nb.mood), float(nb.mood_base), CMP, "newborn starts at its baseline")
	_end(t)


# ---------------------------------------------------------------- 2. mood_k, 3. decay

func test_t02a_mood_k_is_the_closed_form_and_n_ticks_follow_it(t) -> void:
	if not _api(t):
		return
	var h := 4.0
	var sol_h := float(SimWorld.new(1, {"blank": true}).clock.sol_h)
	for n in [98, 197, 50]:
		var w = _world()
		var b = _being(w, HAB1, 0.0, 0.5, h, false)
		t.near(float(b.mood_k), 1.0 - pow(0.5, _tickh() / (h * sol_h)), CMP, "mood_k closed form")
		for i in n:
			_inject(w)
		var want := 0.5 * pow(0.5, float(n) * _tickh() / (h * sol_h))
		t.near(_d(b), want, 1e-9, "d after %d integer ticks follows 0.5 x 0.5^(n x tick_h / (H x sol_h))" % n)
		t.check(absf(_d(b)) > float(_md().rest_eps), "staying above rest_eps throughout (n %d)" % n)
	_end(t)


func test_t02b_half_life_to_the_discretisation_tolerance(t) -> void:
	if not _api(t):
		return
	var h := 4.0
	var w = _world()
	var sol_h := float(w.clock.sol_h)
	var b = _being(w, HAB1, 0.0, 0.5, h, false)
	var n := int(round(h * sol_h / _tickh()))
	for i in n:
		_inject(w)
	var k := float(b.mood_k)
	t.check(absf(_d(b) / 0.25 - 1.0) <= 0.5 * k + 1e-12, "after round(H x sol_h / tick_h) = %d ticks the deviation is half within 0.5 x k relative (got %.6f of the start)" % [n, _d(b) / 0.5])
	_end(t)


func test_t03a_decay_is_monotonic_and_snaps_to_the_baseline(t) -> void:
	if not _api(t):
		return
	var eps := float(_md().rest_eps)
	for sgn in [1.0, -1.0]:
		var w = _world()
		var b = _being(w, HAB1, 0.04, 0.3 * sgn, 2.0, false)
		var prev := absf(_d(b))
		var mono := true
		var snapped_at := -1
		for i in 700:
			_inject(w)
			var a := absf(_d(b))
			if a > prev + 1e-15:
				mono = false
			prev = a
			if snapped_at < 0 and float(b.mood) == float(b.mood_base):
				snapped_at = i
		t.check(mono, "the deviation never grows between pushes (sign %+d)" % int(sgn))
		t.check(snapped_at >= 0, "the mood reaches its baseline exactly (snap below rest_eps) in 700 ticks of H 2 (sign %+d)" % int(sgn))
		t.eq(float(b.mood), float(b.mood_base), "at rest it is exactly the baseline")
		if snapped_at >= 0:
			# Just before the snap the deviation was below rest_eps but above zero only on the snapping tick.
			t.check(eps > 0.0, "rest_eps is positive")
	_end(t)


func test_t03b_a_being_at_its_baseline_stays_exactly_there(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1, -0.14, 0.0, 10.4, false)
	var c = _being(w, HAB1, 0.15, 0.0, 3.6, false)
	for i in 100:
		_inject(w)
	t.eq(float(a.mood), -0.14, "negative baseline: no drift in 100 ticks")
	t.eq(float(c.mood), 0.15, "positive baseline: no drift in 100 ticks")
	t.eq(int(a.mood_band), 2, "band stays even")
	_end(t)


# ---------------------------------------------------------------- 4. headroom

func test_t04a_headroom_scales_a_push_by_the_distance_to_the_limit(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1, 0.0, 0.35)
	var b = _being(w, HAB1, 0.0, 0.0)
	_inject(w, [_ev("friend", a.id, b.id)])
	t.near(_d(a), 0.35 + 0.05, CMP, "a +0.10 push at d +0.35 is +0.05")
	t.near(_d(b), 0.10, CMP, "the same push at rest is the full +0.10")
	var w2 = _world()
	var m = _being(w2, HAB1, 0.0, -0.35)
	_inject(w2, [_ev("grief", m.id, 99, 0.30, "Gone")])
	t.near(_d(m), -0.35 - 0.125, CMP, "a -0.25 grief at d -0.35 is -0.125")
	# A push in the other direction is not scaled by the headroom on the far side.
	var w3 = _world()
	var q = _being(w3, HAB1, 0.0, -0.5)
	var r = _being(w3, HAB1, 0.0, 0.0)
	_inject(w3, [_ev("friend", q.id, r.id)])
	t.near(_d(q), -0.5 + 0.10, CMP, "a glad push on a low mood is not reduced")
	_end(t)


func test_t04b_no_run_of_pushes_passes_the_limits_and_saturation_is_counted(t) -> void:
	if not _api(t):
		return
	var rg: Dictionary = _md().range
	var w = _world()
	var a = _being(w, HAB1, 0.0, 0.0)
	var b = _being(w, HAB1, 0.0, 0.0)
	var evs: Array = []
	for i in 1000:
		evs.append(_ev("friend", a.id, b.id))
	_inject(w, evs)
	t.check(_d(a) <= float(rg.ceil_dev) + 1e-9, "1000 friend pushes in one tick stay at or below ceil_dev (%.6f)" % _d(a))
	t.check(_d(a) > 0.6, "and do approach it (%.6f)" % _d(a))
	var w2 = _world()
	var c = _being(w2, HAB1, 0.0, 0.0)
	for i in 1000:
		_inject(w2, [_ev("grief", c.id, 90 + i, 1.0, "G")])
	t.check(_d(c) >= float(rg.floor_dev) - 1e-9, "1000 grief pushes (one a tick) stay at or above floor_dev (%.6f)" % _d(c))
	t.check(_d(c) < -0.6, "and do approach it (%.6f)" % _d(c))
	# Exactly on the limit: scale 0, the mood does not move and the push is counted as zeroed.
	var w3 = _world()
	var hi = _being(w3, HAB1, 0.0, float(rg.ceil_dev))
	var oth = _being(w3, HAB1, 0.0, 0.0)
	var z0: int = int(w3.stats.moods.pushes_zeroed)
	_inject(w3, [_ev("friend", hi.id, oth.id)])
	t.near(_d(hi), float(rg.ceil_dev), CMP, "a push at the ceiling does not move the mood")
	t.eq(int(w3.stats.moods.pushes_zeroed) - z0, 1, "one zeroed push counted")
	var w4 = _world()
	var lo = _being(w4, HAB1, 0.0, float(rg.floor_dev))
	var z1: int = int(w4.stats.moods.pushes_zeroed)
	_inject(w4, [_ev("grief", lo.id, 99, 0.5, "Gone")])
	t.near(_d(lo), float(rg.floor_dev), CMP, "a grief at the floor does not move the mood")
	t.eq(int(w4.stats.moods.pushes_zeroed) - z1, 1, "one zeroed push counted at the floor")
	t.eq(_push_count(w4, "grief"), 1, "a zeroed push still counts as a push (spec 8)")
	_end(t)


# ---------------------------------------------------------------- 5. friend and close pushes (real feed)

func test_t05a_a_grown_friendship_pushes_both(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	var b = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	_setb(w, a.id, b.id, _friend_line() - 0.001)
	t.check(not w.relationships.are_friends(a.id, b.id), "staging: just below the friend line")
	_tick(w)
	t.check(w.relationships.are_friends(a.id, b.id), "staging: the tick grew the pair across the line")
	var company := _p("company")
	t.between(_d(a), _p("friend") - CMP, _p("friend") + company + 1e-9, "both +0.10 (company on the crossing tick is not specified, spec question 5)")
	t.between(_d(b), _p("friend") - CMP, _p("friend") + company + 1e-9, "the other end too")
	t.eq(_push_count(w, "friend"), 2, "two friend pushes counted (one per being)")
	_end(t)


func test_t05b_a_close_crossing_pushes_both(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	var b = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	_setb(w, a.id, b.id, _close_line() - 0.001)
	t.check(w.relationships.are_friends(a.id, b.id) and not _pair(w, a.id, b.id).close, "staging: friends, not yet close")
	_tick(w)
	t.check(bool(_pair(w, a.id, b.id).close), "staging: the tick made the pair close")
	t.between(_d(a), _p("close") - CMP, _p("close") + _p("company") + 1e-9, "close +0.15 (company on the crossing tick is not specified)")
	t.between(_d(b), _p("close") - CMP, _p("close") + _p("company") + 1e-9, "the other end too")
	t.eq(_push_count(w, "close"), 2, "two close pushes counted")
	t.eq(_push_count(w, "friend"), 0, "no friend push for a pair that was already friends")
	_end(t)


func test_t05c_kin_seeding_pushes_nothing_and_a_crew_lapse_pushes_nothing(t) -> void:
	if not _api(t):
		return
	# Kin: a newborn with a parent starts with a kin bond above the friend line; no friend push, no why.
	var w = _world()
	var p = _being(w, HAB1, 0.0, 0.0)
	_tick(w)
	w._create_newborn(w.buildings.get_building(HAB1), p)
	var nb = w.beings.back()
	_tick(w)
	t.check(w.relationships.are_friends(p.id, nb.id), "staging: the kin pair holds the friends flag")
	t.eq(_push_count(w, "friend"), 0, "kin seeding makes no friend push")
	t.eq(_push_count(w, "close"), 0, "kin seeding makes no close push")
	# Crew lapse: a crew pair that was never close, apart, crosses below the drop line.
	var w2 = _world()
	var a = _being(w2, HAB1)
	var b = _being(w2, HAB2)
	_setb(w2, a.id, b.id, 0.35)
	_setb(w2, a.id, b.id, float(_rd().lines.friend_drop) + 0.0001)
	_pair(w2, a.id, b.id).crew = true
	t.check(w2.relationships.are_friends(a.id, b.id), "staging: crew friends just above the drop line")
	_tick(w2)
	t.check(not w2.relationships.are_friends(a.id, b.id), "staging: the pair lapsed in the tick")
	t.eq(_push_count(w2, "lapse"), 0, "a crew lapse pushes nothing (lapse)")
	t.eq(_push_count(w2, "lapse_close"), 0, "a crew lapse that was never close pushes nothing (lapse_close)")
	t.near(_d(a), 0.0, CMP, "mood unchanged")
	_end(t)


func test_t05d_lapses_push_both_and_a_was_close_lapse_pushes_more(t) -> void:
	if not _api(t):
		return
	var drop := float(_rd().lines.friend_drop)
	for was_close in [false, true]:
		var w = _world()
		var a = _being(w, HAB1)
		var b = _being(w, HAB2)
		_setb(w, a.id, b.id, 0.35)
		_setb(w, a.id, b.id, drop + 0.0001)
		_pair(w, a.id, b.id).was_close = was_close
		_tick(w)
		t.check(not w.relationships.are_friends(a.id, b.id), "staging: lapsed (was_close %s)" % str(was_close))
		var want := _p("lapse_close") if was_close else _p("lapse")
		t.near(_d(a), want, CMP, "lapse push on the first end (was_close %s)" % str(was_close))
		t.near(_d(b), want, CMP, "lapse push on the second end")
		t.eq(_push_count(w, "lapse_close" if was_close else "lapse"), 2, "counted under its own key")
	# A kin or crew pair that WAS close and lapses does give lapse_close (5.3).
	var w3 = _world()
	var c = _being(w3, HAB1)
	var e = _being(w3, HAB2)
	_setb(w3, c.id, e.id, 0.35)
	_setb(w3, c.id, e.id, drop + 0.0001)
	_pair(w3, c.id, e.id).crew = true
	_pair(w3, c.id, e.id).was_close = true
	_tick(w3)
	t.near(_d(c), _p("lapse_close"), CMP, "a crew pair that was close gives lapse_close")
	_end(t)


# ---------------------------------------------------------------- 6. grief

func _grief_world() -> Variant:
	var w = _world()
	for i in 8:
		_being(w, HAB1 if i < 4 else HAB2)
	_tick(w)  # relationships only learns who exists at a tick; a death is only noticed for a known being
	return w


func test_t06a_grief_by_the_linear_rule_for_every_mourner(t) -> void:
	if not _api(t):
		return
	var w = _grief_world()
	var fl := _friend_line()
	_setb(w, 2, 3, fl)
	_setb(w, 2, 4, 0.65)
	_setb(w, 2, 5, 1.0)
	_setb(w, 2, 6, fl - 0.01)
	var dead_name: String = w.beings[1].name
	_kill(w, 2)
	_tick(w)
	t.near(_d(w.beings[1]), _grief_nominal(fl), 1e-9, "bond at the friend line gives grief_min")
	t.near(_grief_nominal(fl), -0.25, 1e-9, "(data check) grief_min is -0.25 at bond 0.30")
	t.near(_d(w.beings[2]), -0.425, 1e-9, "bond 0.65 gives -0.425")
	t.near(_d(w.beings[3]), -0.60, 1e-9, "bond 1.0 gives -0.60")
	t.near(_d(w.beings[4]), 0.0, CMP, "a being below the friend line gets none")
	t.near(_d(w.beings[5]), 0.0, CMP, "a being with no bond gets none")
	var named := 0
	for e in w.log:
		if str(e.kind) == "rel_grief":
			named += 1
	t.eq(named, 2, "the log names two mourners (grief_max) while three were pushed")
	t.eq(_push_count(w, "grief"), 3, "three grief pushes counted")
	var why = w.beings[3].mood_why
	t.check(why != null and str(why.key) == "grief", "the deepest mourner's why is grief")
	if why != null:
		t.eq(int(why.id), 2, "why.id is the dead")
		t.eq(str(why.name), dead_name, "why.name is the dead's name")
		t.eq(int(why.sign), -1, "why.sign -1")
	_end(t)


func test_t06b_a_mourner_that_died_in_the_same_tick_is_skipped(t) -> void:
	if not _api(t):
		return
	var w = _grief_world()
	_setb(w, 2, 3, 0.8)
	_setb(w, 2, 4, 0.8)
	_setb(w, 3, 4, 0.8)
	_kill(w, 2)
	_kill(w, 3)
	_tick(w)
	var m = null
	for b in w.beings:
		if b.id == 4:
			m = b
	t.check(m != null, "staging: id 4 survives")
	if m != null:
		var want := 0.0
		for k in 2:
			want += _grief_nominal(0.8) * _scale(want, -1.0)
		t.near(_d(m), want, 1e-9, "the survivor is pushed once for each of the two deaths, the second scaled by the headroom left")
	# An event naming a being that no longer exists is skipped without a fault.
	var w2 = _world()
	var a = _being(w2, HAB1)
	var before: int = _push_count(w2, "grief")
	_inject(w2, [_ev("grief", 777, 1, 0.8, "Nobody")])
	t.eq(_push_count(w2, "grief"), before, "an absent mourner is skipped and not counted")
	t.near(_d(a), 0.0, CMP, "and nobody else is moved")
	_end(t)


# ---------------------------------------------------------------- 7. birth

func test_t07a_the_parent_of_a_newborn_is_pushed_and_the_why_is_the_birth(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var parent = _being(w, HAB1)
	var other = _being(w, HAB2)
	w._create_newborn(w.buildings.get_building(HAB1), parent)
	var nb = w.beings.back()
	_inject(w)
	t.near(_d(parent), _p("birth_parent"), CMP, "birth_parent +0.24 at rest")
	t.near(_d(other), 0.0, CMP, "nobody else is moved")
	t.eq(_push_count(w, "birth_parent"), 1, "one birth_parent push counted")
	var why = parent.mood_why
	t.check(why != null, "a why is set")
	if why != null:
		t.check(str(why.key) in ["birth", "birth_parent"], "its key is the birth (got %s)" % str(why.key))
		t.eq(int(why.id), nb.id, "why.id is the newborn")
		t.eq(str(why.name), nb.name, "why.name is the newborn's name")
		t.eq(int(why.sign), 1, "sign +1")
	t.eq(int(parent.mood_band), 3, "+0.24 takes the parent to the light band (hysteresis margin included)")
	t.eq(int(w.moods.max_id_seen), nb.id, "max_id_seen is the newborn's id")
	_end(t)


func test_t07b_no_push_for_a_dead_parent_or_no_parent_and_all_newborns_in_a_tick(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var p1 = _being(w, HAB1)
	var p2 = _being(w, HAB1)
	var p3 = _being(w, HAB2)
	var hb = w.buildings.get_building(HAB1)
	w._create_newborn(hb, p1)
	var n1 = w.beings.back()
	w._create_newborn(hb, p2)
	w._create_newborn(hb, p3)
	var n3 = w.beings.back()
	w._create_newborn(hb, null)
	var n4 = w.beings.back()
	_inject(w)
	for p in [p1, p2, p3]:
		t.near(_d(p), _p("birth_parent"), CMP, "each parent of the several newborns of one tick is pushed (%s)" % p.name)
	t.eq(_push_count(w, "birth_parent"), 3, "three pushes, none for the newborn with parent_id 0")
	t.eq(int(w.moods.max_id_seen), n4.id, "max_id_seen is the largest id (%d)" % n4.id)
	t.near(_d(n1), 0.0, CMP, "a newborn starts at its baseline")
	# A parent that died before the tick gets nothing and the tick does not fail.
	var w2 = _world()
	var q = _being(w2, HAB1)
	var other = _being(w2, HAB1)
	w2._create_newborn(w2.buildings.get_building(HAB1), q)
	_kill(w2, q.id)
	_inject(w2)
	t.eq(_push_count(w2, "birth_parent"), 0, "a dead parent gives no push")
	t.near(_d(other), 0.0, CMP, "nor does anybody else")
	_end(t)


func test_t07c_births_land_after_decay_and_before_relationship_events(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var par = _being(w, HAB1, 0.0, 0.30, 4.0, false)
	par.mood_k = 0.02
	var oth = _being(w, HAB2)
	w._create_newborn(w.buildings.get_building(HAB1), par)
	var d := 0.30
	d += (0.0 - d) * 0.02
	d += _p("birth_parent") * _scale(d, 1.0)
	d += _p("friend") * _scale(d, 1.0)
	_inject(w, [_ev("friend", par.id, oth.id)])
	t.near(_d(par), d, 1e-12, "decay, then birth_parent, then the relationship event")
	_end(t)


# ---------------------------------------------------------------- 8. hard sol, 9. pledge and no age pushes

func test_t08a_a_hard_sol_is_recorded_at_the_boundary_and_pushed_at_the_next_tick(t) -> void:
	if not _api(t):
		return
	var hs := _p("hard_sol")
	var floor_dev := _p("hard_floor_dev")
	var w = _world()
	var a = _being(w, HAB1)
	var low = _being(w, HAB1, 0.0, floor_dev - 0.0001)
	var near_floor = _being(w, HAB2, 0.0, -0.29)
	var exact = _being(w, HAB2, 0.0, floor_dev)
	_stocks(w)
	w.moods.on_sol(w)
	t.check(w.moods.pending_hard == null, "all three stocks fine: nothing pending")
	_stocks(w, true)
	w.moods.on_sol(w)
	t.eq(str(w.moods.pending_hard), "ice", "ice short is recorded")
	t.near(_d(a), 0.0, CMP, "the sol hook itself pushes nobody")
	_inject(w)
	t.near(_d(a), hs, CMP, "the next tick pushes every being -0.02")
	t.near(_d(low), floor_dev - 0.0001, CMP, "a being at or below hard_floor_dev gets none")
	t.eq(_d(exact), floor_dev, "a being exactly at hard_floor_dev gets none (d <= floor)")
	t.near(_d(near_floor), -0.29 + hs * _scale(-0.29, -1.0), 1e-12, "a being just above the floor is pushed, scaled")
	t.check(w.moods.pending_hard == null, "pending cleared after the push")
	t.eq(_push_count(w, "hard_sol"), 2, "counted once per pushed being (a and near_floor)")
	_inject(w)
	t.near(_d(a), hs, CMP, "and not again on the following tick")
	_end(t)


func test_t08b_the_clause_is_the_first_short_of_ice_air_food(t) -> void:
	if not _api(t):
		return
	for case in [[false, true, false, "air"], [false, false, true, "food"], [true, true, true, "ice"], [false, true, true, "air"]]:
		var w = _world()
		_being(w, HAB1)
		_stocks(w, case[0], case[1], case[2])
		w.moods.on_sol(w)
		t.eq(str(w.moods.pending_hard), str(case[3]), "short (ice %s air %s food %s) gives %s" % [str(case[0]), str(case[1]), str(case[2]), case[3]])
	var w2 = _world()
	var b = _being(w2, HAB1, 0.0, -0.20)
	_stocks(w2, false, false, true)
	w2.moods.on_sol(w2)
	_inject(w2)
	var why = b.mood_why
	t.check(why != null and str(why.key) == "hard_sol", "a hard why is set on a being already off its baseline by show_dev")
	if why != null:
		t.eq(str(why.clause), "food", "the clause is carried")
		t.eq(int(why.sign), -1, "sign -1")
	_end(t)


func test_t08c_the_sol_hook_loops_over_no_beings(t) -> void:
	if not _api(t):
		return
	var src := FileAccess.get_file_as_string("res://sim/moods.gd")
	var i := src.find("func on_sol")
	t.check(i >= 0, "moods.gd defines on_sol")
	if i >= 0:
		var j := src.find("\nfunc ", i + 10)
		var body := src.substr(i, (j if j >= 0 else src.length()) - i)
		var rx := RegEx.new()
		rx.compile("for\\s+\\w+\\s+in\\s+[^\\n:]*beings")
		t.check(rx.search(body) == null, "on_sol has no loop over world.beings")
	_end(t)


func test_t09a_the_pledge_pushes_everyone_once(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1)
	var b = _being(w, HAB2)
	_stocks(w)
	w.moods.on_sol(w)
	t.check(not bool(w.moods.pending_pledge), "no pledge yet: nothing pending")
	w.stats.council.pledge_sol = 195
	w.moods.on_sol(w)
	t.check(bool(w.moods.pending_pledge), "the pledge is recorded at the sol hook")
	_inject(w)
	t.near(_d(a), _p("pledge"), CMP, "+0.10 on the first being")
	t.near(_d(b), _p("pledge"), CMP, "+0.10 on the second")
	t.check(bool(w.moods.seen_pledge), "seen_pledge set")
	t.eq(_push_count(w, "pledge"), 2, "two pledge pushes counted")
	w.moods.on_sol(w)
	_inject(w)
	t.near(_d(a), _p("pledge"), CMP, "the pledge pushes once only")
	_end(t)


func test_t09b_an_age_change_pushes_nothing(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1, 0.03, 0.0)
	_stocks(w)
	for step in [["settlement", "settled"], ["landing", "fall_back"], ["settlement", "settled_again"], ["council", "council"]]:
		w.ages.enter_age(w, step[0], step[1], "Staged.")
		w.moods.on_sol(w)
		_inject(w)
		t.eq(float(a.mood), 0.03, "entering %s pushes nothing" % step[0])
	t.check(w.moods.pending_hard == null and not bool(w.moods.pending_pledge), "and records nothing")
	_end(t)


# ---------------------------------------------------------------- 10. company

func test_t10a_two_friends_awake_together_get_the_company_push(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	var b = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	var c = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	_setb(w, a.id, b.id, 0.5)
	_tick(w)
	t.check(int(w.relationships.with_friend[a.id]) != 0, "with_friend set for the first friend")
	t.check(int(w.relationships.with_friend[b.id]) != 0, "with_friend set for the second friend")
	t.eq(int(w.relationships.with_friend[c.id]), 0, "not for the third, who has no friend there")
	t.near(_d(a), _p("company"), CMP, "+0.006 for the first")
	t.near(_d(b), _p("company"), CMP, "+0.006 for the second")
	t.near(_d(c), 0.0, CMP, "no push for the one without a friend present")
	t.eq(_push_count(w, "company"), 2, "two company pushes counted")
	_end(t)


func test_t10b_no_company_asleep_in_transit_or_between_non_friends(t) -> void:
	if not _api(t):
		return
	for case in ["sleep", "transit", "non_friends"]:
		var w = _world()
		var a = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
		var b = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
		_setb(w, a.id, b.id, 0.1 if case == "non_friends" else 0.5)
		if case == "sleep":
			a.state = "sleep"
			a.sleep_started_t = w.t
			b.state = "sleep"
			b.sleep_started_t = w.t
		elif case == "transit":
			a.state = "transit"
			b.state = "transit"
		_tick(w)
		t.near(_d(a), 0.0, CMP, "%s: no push on the first" % case)
		t.near(_d(b), 0.0, CMP, "%s: no push on the second" % case)
		t.eq(_push_count(w, "company"), 0, "%s: none counted" % case)
	_end(t)


func test_t10c_friends_on_the_same_ice_field_count(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var f = w.resources.add_ice_field(100.0, 100.0, 500.0, 20.0)
	var a = _being(w, REACTOR)
	var b = _being(w, REACTOR)
	for x in [a, b]:
		x.state = "mining"
		x.mine = {"site": f}
	_setb(w, a.id, b.id, 0.5)
	_tick(w)
	t.near(_d(a), _p("company"), CMP, "a friend on the same field: +0.006")
	t.near(_d(b), _p("company"), CMP, "and the other")
	_end(t)


func test_t10d_the_company_ceiling(t) -> void:
	if not _api(t):
		return
	var ceil_dev := _p("company_ceil_dev")
	var w = _world()
	var at = _being(w, HAB1, 0.0, ceil_dev)
	var half = _being(w, HAB1, 0.0, ceil_dev / 2.0)
	var above = _being(w, HAB1, 0.0, ceil_dev + 0.05)
	_inject(w, [], [at.id, half.id, above.id])
	t.near(_d(at), ceil_dev, CMP, "at d +0.15 the push is 0")
	t.near(_d(half), ceil_dev / 2.0 + 0.003, CMP, "at d +0.075 the push is +0.003")
	t.near(_d(above), ceil_dev + 0.05, CMP, "above the ceiling the push is 0")
	var w2 = _world()
	var a = _being(w2, HAB1)
	var worst := 0.0
	var band_ok := true
	for i in 10000:
		_inject(w2, [], [a.id])
		worst = maxf(worst, _d(a))
		if int(a.mood_band) != 2:
			band_ok = false
	t.check(worst <= ceil_dev + 1e-9, "10,000 company ticks leave d at or below +0.15 (%.9f)" % worst)
	t.check(worst > ceil_dev - 0.01, "and do approach it (%.6f)" % worst)
	t.check(band_ok, "company alone never lifts a being to the light band")
	_end(t)


# ---------------------------------------------------------------- 11. order

func _order_world() -> Dictionary:
	var w = _world()
	var a = _being(w, HAB1, 0.0, 0.05, 4.0, false)
	a.mood_k = 0.01
	var b = _being(w, HAB2)
	w.moods.pending_hard = "ice"
	w.moods.pending_pledge = true
	return {"w": w, "a": a, "b": b}


func test_t11a_decay_events_colony_company_in_that_order(t) -> void:
	if not _api(t):
		return
	var c := _order_world()
	var w = c.w
	var a = c.a
	_inject(w, [_ev("friend", a.id, c.b.id), _ev("grief", a.id, 99, _friend_line(), "Gone")], [a.id])
	var d := 0.05
	d += (0.0 - d) * 0.01
	d += _p("friend") * _scale(d, 1.0)
	d += _grief_nominal(_friend_line()) * _scale(d, -1.0)
	d += _p("hard_sol") * _scale(d, -1.0)
	d += _p("pledge") * _scale(d, 1.0)
	d += _p("company") * _scale(d, 1.0, _p("company_ceil_dev"))
	t.near(_d(a), d, 1e-12, "decay, friend, grief (list order), hard_sol, pledge, company")
	# Swapping the order of the two events changes the result (so the test can tell).
	var c2 := _order_world()
	_inject(c2.w, [_ev("grief", c2.a.id, 99, _friend_line(), "Gone"), _ev("friend", c2.a.id, c2.b.id)], [c2.a.id])
	t.check(absf(_d(c2.a) - d) > 1e-6, "events are applied in list order (a swapped list gives a different mood)")
	_end(t)


func test_t11b_two_same_seed_staged_worlds_give_identical_moods(t) -> void:
	if not _api(t):
		return
	var digests: Array = []
	for i in 2:
		var c := _order_world()
		_inject(c.w, [_ev("friend", c.a.id, c.b.id), _ev("grief", c.a.id, 99, 0.5, "Gone")], [c.a.id])
		_inject(c.w, [], [c.a.id])
		digests.append(_digest_world(c.w))
	t.eq(digests[0], digests[1], "identical moods, bands and whys")
	_end(t)


# ---------------------------------------------------------------- 12. bands and hysteresis

func test_t12a_each_line_changes_the_band_only_when_0_03_past_it(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1)
	var seq := [
		[-0.19, 2], [-0.2099, 2], [-0.2101, 1], [-0.17, 1], [-0.152, 1], [-0.148, 2],
		[-0.4299, 1], [-0.4301, 0], [-0.38, 0], [-0.3701, 0], [-0.3699, 1], [-0.20, 1], [0.0, 2],
		[0.19, 2], [0.2099, 2], [0.2101, 3], [0.17, 3], [0.152, 3], [0.148, 2],
		[0.4299, 3], [0.4301, 4], [0.38, 4], [0.3701, 4], [0.3699, 3], [0.0, 2],
	]
	for s in seq:
		a.mood = float(s[0])
		_inject(w)
		t.eq(int(a.mood_band), int(s[1]), "d %+.4f gives band %d" % [float(s[0]), int(s[1])])
	_end(t)


func test_t12b_a_push_that_crosses_two_lines_moves_two_bands_in_one_tick(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _being(w, HAB1, 0.0, -0.60)
	var b = _being(w, HAB1, 0.0, 0.60)
	_inject(w)
	t.eq(int(a.mood_band), 0, "even to heavy in one tick (d -0.60)")
	t.eq(int(b.mood_band), 4, "even to bright in one tick (d +0.60)")
	# The grief itself: a bond-0.8 grief on a being at rest is heavy at once.
	var w2 = _world()
	var m = _being(w2, HAB1)
	_inject(w2, [_ev("grief", m.id, 99, 0.8, "Gone")])
	t.eq(int(m.mood_band), 0, "a -0.50 grief is heavy in the tick it lands")
	_end(t)


func test_t12c_a_mood_hovering_on_a_line_does_not_flip_the_text(t) -> void:
	if not _api(t):
		return
	for start in [2, 1]:
		var w = _world()
		var a = _being(w, HAB1)
		if start == 1:
			a.mood = -0.25
			_inject(w)
			t.eq(int(a.mood_band), 1, "staging: low")
		var flips := 0
		var prev := int(a.mood_band)
		for i in 50:
			a.mood = -0.17 if i % 2 == 0 else -0.19
			_inject(w)
			if int(a.mood_band) != prev:
				flips += 1
				prev = int(a.mood_band)
		t.check(flips <= 1, "50 ticks between -0.17 and -0.19 flip the band at most once (start %d, flips %d)" % [start, flips])
		t.eq(flips, 0, "and in fact never (start %d)" % start)
	_end(t)


# ---------------------------------------------------------------- 13. the why

## World with A (id 1, frozen), X (id 2) a friend of A, B (id 3) a friend of A and a spare, all asleep.
func _why_world() -> Dictionary:
	var w = _world()
	var a = _being(w, HAB1)
	var x = _being(w, HAB2)
	var b = _being(w, GREEN)
	_setb(w, a.id, x.id, 0.5)
	_setb(w, a.id, b.id, 0.5)
	_stocks(w)
	return {"w": w, "a": a, "x": x, "b": b}


func test_t13a_a_grief_why_is_sticky_against_every_other_push(t) -> void:
	if not _api(t):
		return
	for kind in ["friend", "close", "lapse", "lapse_close", "birth", "hard", "pledge", "company"]:
		var c := _why_world()
		var w = c.w
		var a = c.a
		_stage_why(a, "grief", 50, -1, -0.60)
		var evs: Array = []
		var friends: Array = []
		match kind:
			"friend", "close", "lapse", "lapse_close":
				evs.append(_ev(kind, a.id, c.b.id))
			"birth":
				w._create_newborn(w.buildings.get_building(HAB1), a)
			"hard":
				_stocks(w, true)
				w.moods.on_sol(w)
			"pledge":
				w.stats.council.pledge_sol = 195
				w.moods.on_sol(w)
			"company":
				friends.append(a.id)
		_inject(w, evs, friends)
		t.check(a.mood_why != null and str(a.mood_why.key) == "grief" and int(a.mood_why.id) == 50, "the grief why survives a %s push (got %s)" % [kind, _why_key(a)])
	_end(t)


func test_t13a2_stickiness_holds_against_a_lapse_big_enough_to_qualify(t) -> void:
	if not _api(t):
		return
	# With the shipped numbers a lapse (-0.05) can never reach half of |d| >= 0.15, so rule 4 is only observable when the
	# world's own copy of the data makes the lapse large (spec question: sticky grief is unobservable at the shipped numbers).
	var c := _why_world()
	c.w.moods.cfg.push.lapse = -0.40
	_stage_why(c.a, "grief", 50, -1, -0.20)
	_inject(c.w, [_ev("lapse", c.a.id, c.b.id)])
	t.check(c.a.mood_why != null and str(c.a.mood_why.key) == "grief", "a qualifying lapse does not replace a sticky grief (got %s)" % _why_key(c.a))
	var c2 := _why_world()
	c2.w.moods.cfg.push.lapse = -0.40
	_stage_why(c2.a, "friend", c2.x.id, -1, -0.20)
	_inject(c2.w, [_ev("lapse", c2.a.id, c2.b.id)])
	t.check(c2.a.mood_why != null and str(c2.a.mood_why.key) == "lapse", "the same lapse does replace a non-sticky why (control)")
	_end(t)


func test_t13b_a_second_grief_replaces_only_when_at_least_half_the_deviation(t) -> void:
	if not _api(t):
		return
	var c := _why_world()
	_stage_why(c.a, "grief", 50, -1, -0.20)
	_inject(c.w, [_ev("grief", c.a.id, 51, 0.8, "Second")])
	t.check(c.a.mood_why != null and int(c.a.mood_why.id) == 51 and str(c.a.mood_why.key) == "grief", "a big second grief replaces the sticky why")
	if c.a.mood_why != null:
		t.eq(str(c.a.mood_why.name), "Second", "with the second dead's name")
	var c2 := _why_world()
	_stage_why(c2.a, "grief", 50, -1, -0.60)
	_inject(c2.w, [_ev("grief", c2.a.id, 51, _friend_line(), "Second")])
	t.check(c2.a.mood_why != null and int(c2.a.mood_why.id) == 50, "a small scaled second grief (below half of |d|) does not replace it")
	_end(t)


func test_t13c_a_non_sticky_why_is_replaced_by_a_major_push_of_at_least_half(t) -> void:
	if not _api(t):
		return
	var c := _why_world()
	_stage_why(c.a, "friend", c.x.id, 1, 0.08)
	_inject(c.w, [_ev("close", c.a.id, c.b.id)])
	t.check(c.a.mood_why != null and str(c.a.mood_why.key) == "close" and int(c.a.mood_why.id) == c.b.id, "a close push (0.133 scaled) replaces a friend why at d +0.08 (got %s)" % _why_key(c.a))
	var c2 := _why_world()
	_stage_why(c2.a, "friend", c2.x.id, 1, 0.30)
	_inject(c2.w, [_ev("friend", c2.a.id, c2.b.id)])
	t.check(c2.a.mood_why != null and int(c2.a.mood_why.id) == c2.x.id, "a small push (below half of |d_after|) leaves the stored friend why")
	_end(t)


func test_t13d_a_push_of_the_wrong_sign_never_sets_or_replaces_a_why(t) -> void:
	if not _api(t):
		return
	var c := _why_world()
	c.a.mood = -0.30
	_inject(c.w, [_ev("friend", c.a.id, c.b.id)])
	t.check(c.a.mood_why == null, "a glad push on a being at d -0.30 (d_after -0.20) sets no why")
	var c2 := _why_world()
	_stage_why(c2.a, "lapse", c2.x.id, -1, -0.30)
	_inject(c2.w, [_ev("friend", c2.a.id, c2.b.id)])
	t.check(c2.a.mood_why != null and str(c2.a.mood_why.key) == "lapse", "and does not replace a stored lapse why")
	var c3 := _why_world()
	_stage_why(c3.a, "friend", c3.x.id, 1, -0.30)
	_inject(c3.w, [_ev("lapse", c3.a.id, c3.b.id)])
	t.check(c3.a.mood_why != null and str(c3.a.mood_why.key) == "lapse", "a stored why of the wrong sign for the present d is replaced by an agreeing major push")
	if c3.a.mood_why != null:
		t.eq(int(c3.a.mood_why.sign), -1, "its sign is the push's")
	_end(t)


func test_t13e_the_size_test_uses_the_nominal_push(t) -> void:
	if not _api(t):
		return
	var c := _why_world()
	c.a.mood = -0.68
	_inject(c.w, [_ev("grief", c.a.id, 50, _friend_line(), "Gone")])
	t.check(c.a.mood_why != null and str(c.a.mood_why.key) == "grief", "a grief on a nearly saturated mood (scale 0.03) still sets its why")
	if c.a.mood_why != null:
		t.eq(int(c.a.mood_why.sign), -1, "sign -1")
	var c2 := _why_world()
	c2.a.mood = -0.30
	_inject(c2.w, [_ev("lapse", c2.a.id, c2.x.id)])
	t.check(c2.a.mood_why != null and str(c2.a.mood_why.key) == "lapse" and int(c2.a.mood_why.id) == c2.x.id, "a lapse of -0.05 is eligible at min_push 0.04")
	_end(t)


func test_t13f_hard_and_pledge_set_a_why_only_when_none_and_far_enough(t) -> void:
	if not _api(t):
		return
	var c := _why_world()
	c.a.mood = -0.14
	_stocks(c.w, true)
	c.w.moods.on_sol(c.w)
	_inject(c.w)
	t.check(c.a.mood_why != null and str(c.a.mood_why.key) == "hard_sol", "a hard sol on d -0.14 (d_after -0.16) sets the why although 0.02 is below min_push")
	if c.a.mood_why != null:
		t.eq(str(c.a.mood_why.clause), "ice", "with the clause ice")
		t.eq(int(c.a.mood_why.sign), -1, "sign -1")
	var c1 := _why_world()
	c1.a.mood = -0.10
	_stocks(c1.w, true)
	c1.w.moods.on_sol(c1.w)
	_inject(c1.w)
	t.check(c1.a.mood_why == null, "d_after -0.12 is under show_dev: no why")
	var c2 := _why_world()
	c2.a.mood = 0.14
	c2.w.stats.council.pledge_sol = 195
	c2.w.moods.on_sol(c2.w)
	_inject(c2.w)
	t.check(c2.a.mood_why != null and str(c2.a.mood_why.key) == "pledge", "a pledge on d +0.14 sets the pledge why")
	if c2.a.mood_why != null:
		t.eq(int(c2.a.mood_why.sign), 1, "sign +1")
	var c3 := _why_world()
	_stage_why(c3.a, "friend", c3.x.id, 1, -0.20)
	_stocks(c3.w, true)
	c3.w.moods.on_sol(c3.w)
	_inject(c3.w)
	t.check(c3.a.mood_why != null and str(c3.a.mood_why.key) == "hard_sol", "a stored why of the wrong sign does not block a hard why")
	var c4 := _why_world()
	_stage_why(c4.a, "lapse", c4.x.id, -1, -0.20)
	_stocks(c4.w, true)
	c4.w.moods.on_sol(c4.w)
	_inject(c4.w)
	t.check(c4.a.mood_why != null and str(c4.a.mood_why.key) == "lapse", "a hard sol does not replace a stored why of the right sign")
	_end(t)


func test_t13g_company_never_sets_replaces_or_clears_a_why(t) -> void:
	if not _api(t):
		return
	var c := _why_world()
	c.a.mood = -0.14
	_inject(c.w, [], [c.a.id])
	t.check(c.a.mood_why == null, "company sets no why")
	var c2 := _why_world()
	_stage_why(c2.a, "lapse", c2.x.id, -1, -0.30)
	_inject(c2.w, [], [c2.a.id])
	t.check(c2.a.mood_why != null and str(c2.a.mood_why.key) == "lapse", "company replaces no why")
	# After a pledge lifted the being past the light line, the why is still the pledge, never company.
	var c3 := _why_world()
	c3.a.mood = 0.10
	c3.w.stats.council.pledge_sol = 195
	c3.w.moods.on_sol(c3.w)
	_inject(c3.w, [], [c3.a.id])
	t.check(c3.a.mood_why != null and str(c3.a.mood_why.key) == "pledge", "the lift of a pledge is credited to the pledge, not to company (got %s)" % _why_key(c3.a))
	var c4 := _why_world()
	_stage_why(c4.a, "friend", c4.x.id, 1, 0.14)
	_inject(c4.w, [], [c4.a.id])
	t.check(c4.a.mood_why == null or str(c4.a.mood_why.key) != "company", "no why of key company exists")
	_end(t)


func test_t13h_a_why_is_cleared_when_the_deviation_falls_below_show_dev(t) -> void:
	if not _api(t):
		return
	var show := float(_md().why.show_dev)
	for sgn in [-1, 1]:
		var c := _why_world()
		var a = c.a
		a.mood_k = _k_of(c.w, 4.0)
		_stage_why(a, "grief" if sgn < 0 else "friend", 50 if sgn < 0 else c.x.id, sgn, 0.60 * sgn)
		var bad_even := 0
		var bad_clear := 0
		var seen_above := false
		var seen_below := false
		for i in 320:
			_inject(c.w)
			var ad := absf(_d(a))
			if ad >= show + 1e-9:
				seen_above = true
				if a.mood_why == null:
					bad_clear += 1
			elif ad < show - 1e-9:
				seen_below = true
				if a.mood_why != null:
					bad_clear += 1
			if int(a.mood_band) == 2 and a.mood_why != null:
				bad_even += 1
		t.check(seen_above and seen_below, "staging: the sweep crosses show_dev (sign %+d)" % sgn)
		t.eq(bad_clear, 0, "the why is stored while |d| >= 0.15 and cleared below it (sign %+d)" % sgn)
		t.eq(bad_even, 0, "on the way back no why is stored for a being whose band is even (sign %+d)" % sgn)
	_end(t)


func test_t13i_the_clause_and_sign_fields_have_the_documented_shape(t) -> void:
	if not _api(t):
		return
	var c := _why_world()
	c.a.mood = -0.20
	_stocks(c.w, false, true)
	c.w.moods.on_sol(c.w)
	_inject(c.w)
	var why = c.a.mood_why
	t.check(why != null, "a hard why exists")
	if why != null:
		for k in ["key", "id", "name", "t", "clause", "sign"]:
			t.check(why.has(k), "mood_why has %s" % k)
		t.eq(str(why.clause), "air", "air clause")
		t.check(int(why.sign) in [-1, 1], "sign is +1 or -1")
		t.near(float(why.t), float(c.w.t), 1e-9, "t is the sim hour the why was set")
	_end(t)


func test_t13j_pair_bound_whys_are_cleared_when_the_pair_no_longer_holds(t) -> void:
	if not _api(t):
		return
	var c := _why_world()
	_stage_why(c.a, "friend", c.x.id, 1, 0.30)
	_inject(c.w)
	t.check(c.a.mood_why != null, "the friend why stays while the pair holds the friends flag")
	_setb(c.w, c.a.id, c.x.id, 0.0)
	t.check(not c.w.relationships.are_friends(c.a.id, c.x.id), "staging: the pair lapsed")
	_inject(c.w)
	t.check(c.a.mood_why == null, "the friend why is cleared at the next tick when the pair lapsed")
	var c2 := _why_world()
	_stage_why(c2.a, "close", c2.x.id, 1, 0.60)
	_tick(c2.w)  # relationships learns who exists
	_stage_why(c2.a, "close", c2.x.id, 1, 0.60)
	_kill(c2.w, c2.x.id)
	_tick(c2.w)
	t.check(c2.a.mood_why == null, "a close why is cleared when the other died")
	var c3 := _why_world()
	_stage_why(c3.a, "lapse", c3.x.id, -1, -0.30)
	_setb(c3.w, c3.a.id, c3.x.id, 0.0)
	_inject(c3.w)
	t.check(c3.a.mood_why != null and str(c3.a.mood_why.key) == "lapse", "a lapse why names a person the being no longer holds: it stays")
	_end(t)


# ---------------------------------------------------------------- 14, 15. the two behaviours

class RecRng extends SimRng:
	var args: Array = []

	func chance(p: float) -> bool:
		args.append(p)
		return false

	func randf() -> float:
		return 0.5


## Subject in habitat 1 with one neighbour over a finished corridor; the world rng records every chance() argument.
func _travel_world(restless: float) -> Dictionary:
	var w = _world()
	w.buildings.add_attached("workshop", HAB1, "r", 10, 8, 5)
	var s = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	s.persona.traits["restless"] = restless
	var rng := RecRng.new(1)
	w.rng = rng
	return {"w": w, "s": s, "rng": rng}


func _task5_chance(restless: float) -> float:
	var r: Dictionary = SimData.beings().restless
	return float(r.travel_base) + float(r.travel_coef) * restless


func test_t14a_gain_zero_leaves_the_chance_exactly_task_5s(t) -> void:
	if not _api(t):
		return
	var c := _travel_world(0.5)
	c.w.mood_travel_gain = 0.0
	for m in [-0.5, 0.9, -0.9, 0.0]:
		c.s.mood = float(m)
		c.rng.args.clear()
		c.s._restless_travel(c.w)
		t.eq(c.rng.args.size(), 1, "one chance() draw (m %+.1f)" % float(m))
		if c.rng.args.size() == 1:
			t.eq(float(c.rng.args[0]), _task5_chance(0.5), "the argument is exactly Task 5's (m %+.1f)" % float(m))
	_end(t)


func test_t14b_gain_on_shifts_the_argument_inside_the_clamps(t) -> void:
	if not _api(t):
		return
	var c := _travel_world(0.5)
	c.w.mood_travel_gain = 0.15
	var base := _task5_chance(0.5)
	var cases := [[-0.5, -0.075], [0.9, 0.06], [-0.9, -0.09], [0.1, 0.015], [0.0, 0.0]]
	for k in cases:
		c.s.mood = float(k[0])
		c.s.mood_base = 0.1
		c.rng.args.clear()
		c.s._restless_travel(c.w)
		t.eq(c.rng.args.size(), 1, "exactly one chance() draw (m %+.1f)" % float(k[0]))
		if c.rng.args.size() == 1:
			t.near(float(c.rng.args[0]), base + float(k[1]), 1e-12, "m %+.1f moves the chance by %+.3f (the clamp is -0.6 .. +0.4, the baseline is not added twice)" % [float(k[0]), float(k[1])])
	_end(t)


func test_t14c_the_chance_never_falls_below_the_floor(t) -> void:
	if not _api(t):
		return
	var c := _travel_world(0.0)
	c.w.mood_travel_gain = 0.15
	c.s.mood = -0.9
	c.s._restless_travel(c.w)
	t.eq(c.rng.args.size(), 1, "one draw")
	if c.rng.args.size() == 1:
		t.near(float(c.rng.args[0]), float(_md().effects.travel_floor), 1e-12, "0.08 - 0.09 is floored at travel_floor 0.02")
	_end(t)


func _idle_drain(w, b) -> float:
	b.state = "idle"
	b.wait_h = 1000.0
	b.energy = 70.0
	var e0 := float(b.energy)
	var dt := float(w.fixed_step)
	b.update(w, dt)
	return (e0 - float(b.energy)) / dt


func test_t15a_idle_drain_gain_zero_is_task_5s(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var b = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	w.mood_energy_gain = 0.0
	var idle := float(SimData.beings().energy.drain_idle)
	for m in [-0.6, 0.4, 0.0, 0.9]:
		b.mood = float(m)
		b.state = "idle"
		b.wait_h = 1000.0
		b.energy = 70.0
		var dt := float(w.fixed_step)
		b.update(w, dt)
		t.eq(float(b.energy), clampf(70.0 - idle * dt, 0.0, float(SimData.beings().energy.max)), "gain 0: energy after one step is Task 5's (m %+.1f)" % float(m))
	_end(t)


func test_t15b_idle_drain_gain_on_is_bounded_between_0_90_and_1_15(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var b = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	w.mood_energy_gain = 0.25
	var idle := float(SimData.beings().energy.drain_idle)
	for k in [[-0.6, 1.15], [0.4, 0.90], [-0.9, 1.15], [0.9, 0.90], [0.0, 1.0], [-0.2, 1.05]]:
		b.mood = float(k[0])
		t.near(_idle_drain(w, b), idle * float(k[1]), 1e-9, "m %+.1f gives a drain factor %.2f" % [float(k[0]), float(k[1])])
	b.mood = -0.4
	b.state = "to_door"
	b.wait_h = 1000.0
	b.energy = 70.0
	var dt := float(w.fixed_step)
	b.update(w, dt)
	t.near((70.0 - float(b.energy)) / dt, idle * 1.10, 1e-9, "the to_door walk drains like idle")
	_end(t)


func test_t15c_sleep_eva_work_and_mining_drains_ignore_mood(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var b = _being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	w.mood_energy_gain = 0.25
	var en: Dictionary = SimData.beings().energy
	for k in [["sleep", 0.0], ["eva", float(en.drain_eva)], ["work", float(en.drain_work)], ["mining", float(en.drain_mining)]]:
		for m in [-0.6, 0.4]:
			b.mood = float(m)
			b.state = str(k[0])
			t.near(float(b.drain_per_h()), float(k[1]), 1e-12, "%s drain at m %+.1f is the data value" % [k[0], float(m)])
	var w2 = _world()
	var s1 = _being(w2, HAB1)
	var s2 = _being(w2, HAB1)
	w2.mood_energy_gain = 0.25
	s1.mood = -0.6
	s2.mood = 0.4
	s1.energy = 40.0
	s2.energy = 40.0
	s1.update(w2, float(w2.fixed_step))
	s2.update(w2, float(w2.fixed_step))
	t.eq(float(s1.energy), float(s2.energy), "a sleeper's energy gain does not depend on mood")
	_end(t)


# ---------------------------------------------------------------- 16. no other reader

func test_t16_no_sim_file_other_than_the_allowed_reads_mood(t) -> void:
	if not _api(t):
		return
	var allowed := ["moods.gd", "being.gd", "world.gd", "relationships.gd", "sim_data.gd"]
	var mood_fn_ok := ["_restless_travel", "drain_per_h", "update"]
	var seen_moods := false
	for f in DirAccess.get_files_at("res://sim/"):
		if not f.ends_with(".gd"):
			continue
		if f == "moods.gd":
			seen_moods = true
		var src := FileAccess.get_file_as_string("res://sim/" + f)
		if f not in allowed:
			t.check(src.to_lower().find("mood") < 0, "sim/%s does not mention mood" % f)
		elif f == "relationships.gd":
			var rx := RegEx.new()
			rx.compile("\\.mood\\w*")
			t.check(rx.search(src) == null, "relationships.gd reads no mood field (it only feeds events)")
		elif f == "being.gd":
			var fn := ""
			var bad: Array[String] = []
			for line in src.split("\n"):
				if line.begins_with("func ") or line.begins_with("static func "):
					fn = line.split("(")[0].replace("static ", "").replace("func ", "").strip_edges()
				var low := line.to_lower()
				if low.find("mood") < 0:
					continue
				var s := line.strip_edges()
				if s.begins_with("#") or line.begins_with("var ") or line.begins_with("const "):
					continue
				if fn in mood_fn_ok or fn.to_lower().find("mood") >= 0:
					continue
				bad.append("%s: %s" % [fn, s])
			t.check(bad.is_empty(), "being.gd reads mood only in the two behaviour sites: " + "; ".join(PackedStringArray(bad)))
	t.check(seen_moods, "sim/moods.gd exists")
	_end(t)


# ---------------------------------------------------------------- 17, 18. dormant purity and determinism (real runs)

func _old_stats(w) -> String:
	var st: Dictionary = w.stats.duplicate(true)
	st.erase("moods")
	return JSON.stringify(st, "", true)


func _log_wo_moods(w) -> String:
	var out: Array = []
	for e in w.log:
		if not str(e.kind).begins_with("mood_"):
			out.append(e)
	return JSON.stringify(out, "", true)


func _core_digest(w) -> String:
	var parts: Array = []
	for b in w.beings:
		parts.append([b.id, b.building_id, b.state, b.energy, b.wait_h])
	parts.append([w.colony.oxygen, w.colony.food, w.colony.ice, w.colony.regolith])
	return JSON.stringify(parts).sha256_text()


func test_t17_dormant_purity_gains_zero_changes_nothing_old(t) -> void:
	if not _api(t):
		return
	var on = SimWorld.new(42, {"moods_enabled": true})
	var off = SimWorld.new(42, {"moods_enabled": false})
	on.mood_travel_gain = 0.0
	on.mood_energy_gain = 0.0
	t.check(not bool(off.moods_enabled), "the option reaches the world")
	t.eq(float(off.mood_travel_gain) + float(off.mood_energy_gain), 0.0, "a disabled world caches gains of 0.0")
	var neu: Dictionary = _md().temperament.neutral
	for b in off.beings:
		t.eq(float(b.mood_base), float(neu.base), "disabled world: founder %d has the neutral baseline from _init" % b.id)
		t.near(float(b.mood_halflife), float(neu.halflife_sols), CMP, "and the neutral half-life")
	var any_nonzero := false
	for b in on.beings:
		if float(b.mood_base) != 0.0:
			any_nonzero = true
	t.check(any_nonzero, "enabled world: founders have chart baselines")
	for w in [on, off]:
		while w.sol() < 10:
			w.step()
	t.eq(_old_stats(on), _old_stats(off), "equal old stats (every key but moods) after 10 sols")
	t.eq(_core_digest(on), _core_digest(off), "equal beings (id, building, state, energy, wait) and stocks")
	t.eq(_log_wo_moods(on), _log_wo_moods(off), "equal log apart from mood lines")
	var da: Array = []
	var db: Array = []
	for i in 1000:
		da.append(on.rng.randf())
		db.append(off.rng.randf())
	t.eq(da, db, "the same next 1,000 draws")
	_end(t)


var _w60: Array = []


## Two gains-on seed-42 worlds stepped 60 sols (cached: tests 18, 19 and 34 share them).
func _worlds60() -> Array:
	if _w60.is_empty():
		for i in 2:
			var w = SimWorld.new(42)
			w.mood_travel_gain = 0.15
			w.mood_energy_gain = 0.25
			while w.sol() < 60:
				w.step()
			_w60.append(w)
	return _w60


var _c60: Array = []


## Two noise-floor control worlds (both gains control_gain), seed 42, 60 sols.
func _control60() -> Array:
	if _c60.is_empty():
		var g := float(_md().calibration.control_gain)
		for i in 2:
			var w = SimWorld.new(42)
			w.mood_travel_gain = g
			w.mood_energy_gain = g
			while w.sol() < 60:
				w.step()
			_c60.append(w)
	return _c60


func _mood_state(w) -> String:
	var parts: Array = []
	for b in w.beings:
		parts.append([b.id, b.mood, b.mood_base, b.mood_band, b.mood_why, b.mood_quiet_t, b.mood_down_t])
	return JSON.stringify([parts, w.stats.moods, w.log], "", true)


func test_t18_determinism_two_same_seed_worlds_agree_for_60_sols(t) -> void:
	if not _api(t):
		return
	var ws := _worlds60()
	t.eq(_mood_state(ws[0]), _mood_state(ws[1]), "moods, bands, whys, stats.moods and the log are identical")
	var total := 0
	for k in ws[0].stats.moods.pushes:
		total += int(ws[0].stats.moods.pushes[k])
	t.check(total > 0, "staging: the run made pushes (%d), so the comparison is not vacuous" % total)
	var moved := false
	for b in ws[0].beings:
		if absf(_d(b)) > 0.001:
			moved = true
	t.check(moved, "and some mood has left its baseline")
	_end(t)


# ---------------------------------------------------------------- 19. lines

func _quiet_text(key: String, variant: String, name: String, other: String) -> String:
	return str(_md().text.lines[key][variant]).replace("{name}", name).replace("{other}", other)


func _lines_of(w, kind: String) -> Array:
	var out: Array = []
	for e in w.log:
		if str(e.kind) == kind:
			out.append(e)
	return out


func _heavy_world(sol: int, d: float = -0.55) -> Dictionary:
	var w = _world()
	_sol_set(w, sol)
	var a = _being(w, HAB1, 0.0, d)
	return {"w": w, "a": a}


func test_t19a_the_quiet_line_text_follows_the_why_with_two_wordings(t) -> void:
	if not _api(t):
		return
	var cases := [
		["grief", "quiet_grief", true], ["lapse", "quiet_lapse", true], ["lapse_close", "quiet_lapse", true],
		["hard_sol", "quiet_hard", false], ["pledge", "quiet", false], ["", "quiet", false],
	]
	for k in cases:
		for sol in [0, 1]:
			var c := _heavy_world(sol)
			var w = c.w
			var a = c.a
			var other := "N50"
			if str(k[0]) != "":
				_stage_why(a, str(k[0]), 50 if bool(k[2]) else 0, -1, -0.55, null, "ice" if str(k[0]) == "hard_sol" else "")
				if not bool(k[2]):
					a.mood_why.id = null
					a.mood_why.name = ""
			_inject(w)
			var lines := _lines_of(w, "mood_quiet")
			var label := "why %s, sol %d" % [str(k[0]) if str(k[0]) != "" else "none", sol]
			t.eq(lines.size(), 1, "one quiet line (%s)" % label)
			if lines.size() == 1:
				var variant := "a" if (a.id + w.sol()) % 2 == 0 else "b"
				var want := _quiet_text(str(k[1]), variant, a.name, other if bool(k[2]) else "")
				t.eq(str(lines[0].text), want, "text %s.%s (%s)" % [str(k[1]), variant, label])
				t.eq(int(lines[0].being_id), a.id, "being_id (%s)" % label)
				if bool(k[2]):
					t.eq(int(lines[0].other_id), 50, "other_id is the why's id (%s)" % label)
				else:
					t.check(lines[0].other_id == null, "other_id null without a person (%s)" % label)
				t.eq(str(lines[0].place), "", "place empty (%s)" % label)
				t.check(lines[0].building_id == null, "building_id null (%s)" % label)
			t.eq(int(w.stats.moods.lines.quiet), 1, "stats.moods.lines.quiet (%s)" % label)
			t.near(float(a.mood_quiet_t), float(w.t), 1e-9, "mood_quiet_t set (%s)" % label)
			t.check(a.mood_down_t != null, "mood_down_t set (%s)" % label)
	_end(t)


func test_t19b_once_cooldown_and_the_relief_arc(t) -> void:
	if not _api(t):
		return
	var sol_h: float
	var c := _heavy_world(10)
	var w = c.w
	var a = c.a
	sol_h = float(w.clock.sol_h)
	var t0 := float(w.clock.start_hour)
	_inject(w)
	t.eq(_lines_of(w, "mood_quiet").size(), 1, "heavy: one quiet line")
	_inject(w)
	_sol_set(w, 11)
	_inject(w)
	t.eq(_lines_of(w, "mood_quiet").size(), 1, "staying heavy logs no second line")
	# Back to even: a relief only after relief_min_sols (3) since the quiet line.
	a.mood = 0.0
	w.t = t0 + 12.9 * sol_h
	_inject(w)
	t.eq(int(a.mood_band), 2, "staging: back to even")
	t.eq(_lines_of(w, "mood_relief").size(), 0, "2.9 sols after the quiet line: no relief yet")
	w.t = t0 + 13.1 * sol_h
	_inject(w)
	var rl := _lines_of(w, "mood_relief")
	t.eq(rl.size(), 1, "3.1 sols after: the relief line")
	if rl.size() == 1:
		var variant := "a" if (a.id + w.sol()) % 2 == 0 else "b"
		t.eq(str(rl[0].text), _quiet_text("relief", variant, a.name, ""), "relief text")
		t.eq(int(rl[0].being_id), a.id, "relief being_id")
	t.check(a.mood_down_t == null, "the relief clears mood_down_t")
	# Heavy again inside the 20-sol cooldown: no quiet line; after it: one.
	for s in [15.0, 20.0, 29.0]:
		a.mood = -0.55
		w.t = t0 + s * sol_h
		_inject(w)
		a.mood = 0.0
		_inject(w)
	t.eq(_lines_of(w, "mood_quiet").size(), 1, "inside the 20-sol cooldown no second quiet line")
	a.mood = -0.55
	w.t = t0 + 30.2 * sol_h
	_inject(w)
	t.eq(_lines_of(w, "mood_quiet").size(), 2, "after the cooldown a second quiet line")
	_t13_lines(t, w, "19b")
	_end(t)


func test_t19c_the_cap_drops_the_rest_changes_no_state_and_orders_deepest_first(t) -> void:
	if not _api(t):
		return
	var w = _world()
	_sol_set(w, 5)
	var a = _being(w, HAB1, 0.0, -0.45)
	var b = _being(w, HAB1, 0.0, -0.60)
	var c = _being(w, HAB1, 0.0, -0.50)
	var dropped0: int = int(w.stats.moods.lines_dropped)
	_inject(w)
	var l1 := _lines_of(w, "mood_quiet")
	t.eq(l1.size(), 1, "three heavy candidates, one line (cap 1 a sol)")
	if l1.size() == 1:
		t.eq(int(l1[0].being_id), b.id, "the deepest (id 2 at -0.60) goes before the founder (id 1 at -0.45)")
	t.eq(int(w.stats.moods.lines_dropped) - dropped0, 2, "two drops counted")
	t.check(float(a.mood_quiet_t) <= -1e8 and a.mood_down_t == null, "a dropped quiet changes no state (a)")
	t.check(float(c.mood_quiet_t) <= -1e8 and c.mood_down_t == null, "a dropped quiet changes no state (c)")
	_inject(w)
	t.eq(_lines_of(w, "mood_quiet").size(), 1, "still capped on the next tick of the same sol")
	t.eq(int(w.stats.moods.lines_dropped) - dropped0, 4, "offered and dropped again once per tick")
	_sol_set(w, 6)
	_inject(w)
	_sol_set(w, 7)
	_inject(w)
	var order: Array = []
	for e in _lines_of(w, "mood_quiet"):
		order.append(int(e.being_id))
	t.eq(order, [b.id, c.id, a.id], "a dropped quiet is logged at a later tick while still heavy, deepest first")
	_t13_lines(t, w, "19c")
	_end(t)


func test_t19d_ties_go_to_the_highest_bond_to_the_why_then_the_lowest_id(t) -> void:
	if not _api(t):
		return
	for case in ["bond", "id"]:
		var w = _world()
		_sol_set(w, 5)
		var x = _being(w, HAB2)
		var b = _being(w, HAB1, 0.0, -0.50)
		var c = _being(w, HAB1, 0.0, -0.50)
		_stage_why(b, "lapse_close", x.id, -1, -0.50)
		_stage_why(c, "lapse_close", x.id, -1, -0.50)
		_setb(w, b.id, x.id, 0.4)
		_setb(w, c.id, x.id, 0.7 if case == "bond" else 0.4)
		_inject(w)
		var l := _lines_of(w, "mood_quiet")
		t.eq(l.size(), 1, "one line (%s)" % case)
		if l.size() == 1:
			t.eq(int(l[0].being_id), c.id if case == "bond" else b.id, "tie broken by %s" % ("the highest bond to the why's other" if case == "bond" else "the lowest id"))
	_end(t)


func test_t19e_relief_rules(t) -> void:
	if not _api(t):
		return
	var sol_h := float(SimWorld.new(1, {"blank": true}).clock.sol_h)
	# Band below even waits.
	var w = _world()
	_sol_set(w, 20)
	var a = _being(w, HAB1, 0.0, -0.25)
	a.mood_band = 1
	a.mood_down_t = w.t - 3.5 * sol_h
	_inject(w)
	t.eq(_lines_of(w, "mood_relief").size(), 0, "a being still in the low band waits for its relief")
	# No relief without a logged quiet.
	var w2 = _world()
	_sol_set(w2, 20)
	var b = _being(w2, HAB1)
	for i in 5:
		_sol_set(w2, 21 + i)
		_inject(w2)
	t.eq(_lines_of(w2, "mood_relief").size(), 0, "no relief for a being with no logged quiet")
	# A dropped relief changes no state and is offered again at the next tick (a quiet candidate goes first).
	var w3 = _world()
	_sol_set(w3, 20)
	var p = _being(w3, HAB1, 0.0, -0.55)
	var q = _being(w3, HAB2, 0.0, 0.0)
	q.mood_down_t = w3.t - 3.5 * sol_h
	_inject(w3)
	t.eq(_lines_of(w3, "mood_quiet").size(), 1, "the heavy being's quiet line takes the slot")
	t.eq(_lines_of(w3, "mood_relief").size(), 0, "the relief is dropped for this sol")
	t.check(q.mood_down_t != null, "and the dropped relief changed no state")
	_sol_set(w3, 21)
	_inject(w3)
	t.eq(_lines_of(w3, "mood_relief").size(), 1, "it is offered again at the next tick and logged")
	t.check(q.mood_down_t == null, "and clears mood_down_t")
	_end(t)


## T13 (1) to (6) shape checks on a log: at most one mood line per elapsed sol; every relief has an earlier quiet of the same
## being at least relief_min_sols before.
func _t13_lines(t, w, label: String) -> void:
	var per_sol := {}
	var quiet: Dictionary = {}
	var ok_rel := true
	var min_sols := float(_md().lines.relief_min_sols)
	for e in w.log:
		var k := str(e.kind)
		if not k.begins_with("mood_"):
			continue
		per_sol[int(e.sol)] = int(per_sol.get(int(e.sol), 0)) + 1
		if k == "mood_quiet":
			if not quiet.has(int(e.being_id)):
				quiet[int(e.being_id)] = []
			quiet[int(e.being_id)].append(float(e.t))
		elif k == "mood_relief":
			var found := false
			for qt in quiet.get(int(e.being_id), []):
				if float(e.t) - float(qt) >= min_sols * float(w.clock.sol_h) - 1e-6:
					found = true
			if not found:
				ok_rel = false
	var worst := 0
	for s in per_sol:
		worst = maxi(worst, int(per_sol[s]))
	t.check(worst <= int(_md().lines.max_per_sol), "%s: at most %d mood line per sol (worst %d)" % [label, int(_md().lines.max_per_sol), worst])
	t.check(ok_rel, "%s: every relief has a quiet line of the same being at least relief_min_sols before" % label)


func test_t19f_the_60_sol_run_keeps_the_line_invariants(t) -> void:
	if not _api(t):
		return
	var ws := _worlds60()
	_t13_lines(t, ws[0], "60-sol seed 42")
	t.check(ws[0].stats.moods.lines.has("quiet") and ws[0].stats.moods.lines.has("relief"), "stats.moods.lines has quiet and relief")
	var n_quiet := _lines_of(ws[0], "mood_quiet").size()
	var n_relief := _lines_of(ws[0], "mood_relief").size()
	t.check(n_relief <= n_quiet, "reliefs (%d) never outnumber quiet lines (%d)" % [n_relief, n_quiet])
	_end(t)


# ---------------------------------------------------------------- 20. texts

func _strings(node: Variant, path: String, out: Dictionary) -> void:
	if node is Dictionary:
		for k in node:
			_strings(node[k], path + "." + str(k), out)
	elif node is String:
		out[path] = node


const SPEC_TEXTS := {
	"text.panel.who": "{name} is {description}.",
	"text.panel.k1": "{name} knows no one well yet.",
	"text.panel.close": "{name} is close to {other}.",
	"text.panel.friend": "{name} counts {other} as a friend.",
	"text.panel.died": "{name} has died.",
	"text.band.low": "{name} is out of spirits.",
	"text.band.heavy": "{name} is struggling.",
	"text.band.light": "{name} is in good spirits.",
	"text.band.bright": "{name} is lit up.",
	"text.why.grief_new": "They are mourning {other}.",
	"text.why.grief_still": "They are still mourning {other}.",
	"text.why.friend": "They have just found a friend in {other}.",
	"text.why.friend_old": "They have grown fond of {other}.",
	"text.why.close": "They have grown close to {other}.",
	"text.why.close_old": "They are close to {other}.",
	"text.why.lapse": "They miss {other}'s company.",
	"text.why.birth": "They were there when {other} was born.",
	"text.why.hard": "The hard days have weighed on them.",
	"text.why.pledge": "The council's promise has lifted them.",
	"text.nature.bright": "{name} usually sees the bright side.",
	"text.nature.heavy": "{name} takes things to heart.",
	"text.nature.slow": "{name} is slow to shake off a mood.",
	"text.nature.quick": "{name} soon shakes off a mood.",
	"text.lines.quiet_grief.a": "{name} has gone quiet since {other} died.",
	"text.lines.quiet_grief.b": "{name} keeps to the quiet corners since {other} died.",
	"text.lines.quiet_lapse.a": "{name} has gone quiet without {other}.",
	"text.lines.quiet_lapse.b": "{name} misses {other} and says little.",
	"text.lines.quiet_hard.a": "{name} has gone quiet. Times are hard.",
	"text.lines.quiet_hard.b": "{name} says little these hard days.",
	"text.lines.quiet.a": "{name} has gone quiet.",
	"text.lines.quiet.b": "{name} is keeping to the quiet corners.",
	"text.lines.relief.a": "{name} is smiling again.",
	"text.lines.relief.b": "{name} has found a smile again.",
}


func test_t20a_the_texts_are_the_spec_texts(t) -> void:
	if not _api(t):
		return
	var strs := {}
	_strings(_md().get("text", {}), "text", strs)
	for k in SPEC_TEXTS:
		t.check(strs.has(k), "text key %s exists" % k)
		if strs.has(k):
			t.eq(str(strs[k]), str(SPEC_TEXTS[k]), "text %s is the spec string" % k)
	for k in strs:
		t.check(SPEC_TEXTS.has(k), "data text %s is listed in the spec (no stray text)" % k)
	t.check(not strs.has("text.why.company"), "no company why text")
	t.check(not strs.has("text.clause.ice"), "no clause texts")
	_end(t)


func test_t20b_no_digit_percent_sign_trait_word_or_chart_word_in_any_text(t) -> void:
	if not _api(t):
		return
	var strs := {}
	_strings(_md().get("text", {}), "text", strs)
	var digit := RegEx.new()
	digit.compile("\\d")
	var banned: Array[String] = ["deimos", "moon", "chart"]
	for s in SimData.signs():
		banned.append(str(s.name).to_lower())
	for d in SimData.persona().dims:
		banned.append(str(d))
	for k in SimData.persona().adjectives:
		banned.append(str(SimData.persona().adjectives[k]))
	var ph := RegEx.new()
	ph.compile("\\{[^}]*\\}")
	for k in strs:
		var s := str(strs[k])
		t.check(digit.search(s) == null, "%s has no digit" % k)
		t.check(s.find("%") < 0, "%s has no percent sign" % k)
		for m in ph.search_all(s):
			t.check(m.get_string() in ["{name}", "{other}", "{description}"], "%s: placeholder %s is one the panel fills" % [k, m.get_string()])
		var filled := s.replace("{name}", "Vana").replace("{other}", "Kiro").replace("{description}", "warm and nurturing")
		t.check(filled.find("{") < 0 and filled.find("}") < 0, "%s: every placeholder is filled" % k)
		t.check(digit.search(filled) == null, "%s: no digit after filling with digit-free names" % k)
		var low := (" " + s.to_lower().replace(".", " ").replace(",", " ").replace("'s", "") + " ")
		for w in banned:
			t.check(low.find(" " + w + " ") < 0, "%s does not contain the word '%s'" % [k, w])
	_end(t)


# ---------------------------------------------------------------- 21. stats and series

func test_t21a_series_have_the_length_of_pop_by_sol_on_a_founder_world(t) -> void:
	if not _api(t):
		return
	var w = SimWorld.new(42)
	var m: Dictionary = w.stats.moods
	t.eq(w.stats.pop_by_sol.size(), 1, "staging: the initial reading")
	for k in ["mean_by_sol", "sd_by_sol", "heavy_by_sol"]:
		t.eq(m[k].size(), 1, "%s has the initial reading at creation" % k)
	var baselines: Array = []
	for b in w.beings:
		baselines.append(float(b.mood_base))
	var mean := 0.0
	for x in baselines:
		mean += float(x)
	mean /= float(baselines.size())
	var ss := 0.0
	for x in baselines:
		ss += (float(x) - mean) * (float(x) - mean)
	var sd_pop := sqrt(ss / float(baselines.size()))
	var sd_sample := sqrt(ss / float(baselines.size() - 1))
	t.near(float(m.mean_by_sol[0]), mean, 1e-12, "mean_by_sol[0] is the mean of the founders' baselines")
	t.between(float(m.sd_by_sol[0]), sd_pop - 1e-9, sd_sample + 1e-9, "sd_by_sol[0] is the sd of the baselines (population or sample)")
	t.eq(float(m.heavy_by_sol[0]), 0.0, "heavy_by_sol[0] is 0.0")
	while w.sol() < 3:
		w.step()
	for k in ["mean_by_sol", "sd_by_sol", "heavy_by_sol"]:
		t.eq(m[k].size(), w.stats.pop_by_sol.size(), "%s keeps the length of pop_by_sol after 3 sols" % k)
	t.near(float(m.mean), float(m.mean_by_sol.back()), 1e-12, "mean is the latest reading")
	_end(t)


func test_t21b_series_on_a_blank_world_and_at_pop_zero(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var m: Dictionary = w.stats.moods
	for k in ["mean_by_sol", "sd_by_sol", "heavy_by_sol"]:
		t.eq(m[k].size(), 0, "%s starts empty on a blank world" % k)
	while w.sol() < 3:
		w.step()
	t.check(w.stats.pop_by_sol.size() >= 3, "staging: sols passed with no beings")
	for k in ["mean_by_sol", "sd_by_sol", "heavy_by_sol"]:
		t.eq(m[k].size(), w.stats.pop_by_sol.size(), "%s has the length of pop_by_sol at pop 0" % k)
		var zero := true
		for x in m[k]:
			if float(x) != 0.0:
				zero = false
		t.check(zero, "%s appends 0.0 at pop 0" % k)
	var w2 = _world()
	_being(w2, HAB1, 0.05, 0.0)
	_being(w2, HAB1, -0.05, 0.0)
	while w2.sol() < 3:
		w2.step()
	t.eq(w2.stats.moods.mean_by_sol.size(), w2.stats.pop_by_sol.size(), "a blank world with beings keeps the length too")
	_end(t)


# ---------------------------------------------------------------- 25. the dormant hash proof (pure helpers; the run is a script)

func _proof() -> Variant:
	return load("res://tests/mood_hash_proof.gd")


func test_t25a_expected_t5_is_the_task_5_log(t) -> void:
	if not _api(t):
		return
	var p = _proof()
	var exp: Dictionary = p.EXPECTED_T5
	t.eq(exp.keys().size(), 5, "five seeds")
	var log_text := FileAccess.get_file_as_string("res://docs/balance/lifecycle-rebaseline.md")
	for seed_i in [42, 7, 99, 1234, 2026]:
		t.check(exp.has(seed_i), "seed %d is listed" % seed_i)
		if exp.has(seed_i):
			t.eq(str(exp[seed_i]).length(), 16, "seed %d hash has 16 hex digits" % seed_i)
			t.check(log_text.find(str(exp[seed_i])) >= 0, "seed %d: %s appears in docs/balance/lifecycle-rebaseline.md" % [seed_i, str(exp[seed_i])])
	var chain = load("res://tests/council_hash_proof.gd")
	for seed_i in [42, 7, 99, 1234, 2026]:
		t.check(str(exp.get(seed_i, "")) != str(chain.EXPECTED_T4[seed_i]), "the Task 5 and Task 4 hashes differ (seed %d): the constant is not copied from the older proof" % seed_i)
	_end(t)


func test_t25b_strip_md_removes_only_a_final_md_column(t) -> void:
	if not _api(t):
		return
	var p = _proof()
	var body := ["sol pop age web cn md", "30 5 L 0.1 - +0.01", "60 6 S 0.2 C -0.02"]
	var r: Dictionary = p.strip_md(body)
	t.eq(r.state, "last", "md is the last field")
	t.eq(r.body, ["sol pop age web cn", "30 5 L 0.1 -", "60 6 S 0.2 C"], "the final field is removed from the header and each row")
	var absent := ["sol pop age web cn", "30 5 L 0.1 -"]
	var r2: Dictionary = p.strip_md(absent)
	t.check(bool(r2.md_absent), "no md column: reported absent")
	t.eq(r2.body, absent, "and the body is unchanged")
	var mis := ["sol md pop", "30 +0.01 5"]
	var r3: Dictionary = p.strip_md(mis)
	t.eq(r3.state, "misplaced", "md in the header but not last is misplaced")
	t.eq(r3.body, mis, "and nothing is stripped")
	var lines := ["# header", "# more", "sol pop age web cn md", "30 5 L 0.1 - +0.01", ""]
	var with_md: Dictionary = p.proof_hashes(lines)
	var without := ["# header", "sol pop age web cn", "30 5 L 0.1 -", ""]
	var no_md: Dictionary = p.proof_hashes(without)
	t.eq(with_md.check0, no_md.check0, "dropping md gives the hash of the table without it")
	t.eq(with_md.check1, no_md.check1, "and the whole chain agrees")
	t.eq(with_md.md_state, "last", "state reported")
	t.eq(no_md.md_state, "absent", "state reported (absent)")
	_end(t)


# ---------------------------------------------------------------- 26. data parity and sanity

func _spec_keys() -> Array:
	var spec := FileAccess.get_file_as_string("res://docs/specs/emotions.md")
	var i0 := spec.find("### Key-path list")
	if i0 < 0:
		return []
	i0 = spec.find("```", i0)
	if i0 < 0:
		return []
	i0 = spec.find("\n", i0) + 1
	var i1 := spec.find("```", i0)
	var out: Array = []
	for l in spec.substr(i0, i1 - i0).split("\n"):
		var s := l.strip_edges()
		if s != "":
			out.append(s)
	return out


func _leaves(node: Variant, prefix: String, out: Array) -> void:
	if node is Dictionary:
		for k in node:
			_leaves(node[k], prefix + ("." if prefix != "" else "") + str(k), out)
	else:
		out.append(prefix)


func test_t26a_key_path_parity_both_ways(t) -> void:
	if not _api(t):
		return
	var keys := _spec_keys()
	t.check(keys.size() >= 100, "the spec key list parses (%d keys)" % keys.size())
	var leaves: Array = []
	_leaves(_md(), "", leaves)
	for k in keys:
		t.check(k in leaves, "spec key %s exists in data/mood.json" % k)
	for k in leaves:
		t.check(k in keys, "data/mood.json leaf %s is listed in the spec" % k)
	t.eq(leaves.size(), keys.size(), "same number of leaves")
	t.check(_md().get("selection", {}).get("outline_color", null) is Array, "selection.outline_color is a list leaf")
	var sd = load("res://sim/sim_data.gd")
	if _has_static(sd, "moods"):
		t.eq(sd.call("moods").hash(), _md().hash(), "SimData.moods() returns data/mood.json")
	_end(t)


func test_t26b_the_balance_data_hash_covers_mood(t) -> void:
	if not _api(t):
		return
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var h0: String = lib.data_hash()
	_edit(_md(), "rest_eps", 0.002)
	var h1: String = lib.data_hash()
	_restore()
	t.check(h0 != h1, "balance data_hash covers data/mood.json")
	t.eq(lib.data_hash(), h0, "and returns to the old value when the data is restored")
	_end(t)


## Every sanity rule of spec section 14 as {rule id: ok} for a data dictionary.
func _sanity(md: Dictionary) -> Dictionary:
	var r := {}
	var rg: Dictionary = md.range
	var bd: Dictionary = md.bands
	var pu: Dictionary = md.push
	var ef: Dictionary = md.effects
	var tp: Dictionary = md.temperament
	r["range_signs"] = float(rg.floor_dev) < 0.0 and 0.0 < float(rg.ceil_dev)
	r["band_order"] = float(bd.heavy) < float(bd.low) and float(bd.low) < 0.0 and 0.0 < float(bd.light) and float(bd.light) < float(bd.bright)
	var gap := minf(float(bd.low) - float(bd.heavy), minf(float(bd.light) - float(bd.low), float(bd.bright) - float(bd.light)))
	r["hyst_under_half_gap"] = float(bd.hyst) < gap / 2.0
	var halves := true
	for k in tp.halflife_sols:
		halves = halves and float(tp.halflife_sols[k]) > 0.0
	for k in tp.halflife_mult:
		halves = halves and float(tp.halflife_mult[k]) > 0.0
	halves = halves and float(tp.neutral.halflife_sols) > 0.0
	r["halflives_positive"] = halves
	r["grief_order"] = float(pu.grief_max) <= float(pu.grief_min) and float(pu.grief_min) < 0.0
	r["clamp_signs"] = float(ef.clamp_low) < 0.0 and 0.0 < float(ef.clamp_high)
	r["gains_nonneg"] = float(ef.travel_coef) >= 0.0 and float(ef.energy_coef) >= 0.0 \
			and float(ef.energy_coef) * -float(ef.clamp_low) < 1.0 \
			and float(ef.fallback_energy_coef) * -float(ef.clamp_low) < 1.0
	r["travel_floor_range"] = float(ef.travel_floor) >= 0.0 and float(ef.travel_floor) <= 1.0
	r["lines_cap"] = int(md.lines.max_per_sol) >= 1
	r["nature_signs"] = float(md.nature.base_lo) < 0.0 and 0.0 < float(md.nature.base_hi)
	var nat := _nature_sets(md)
	r["nature_margins_and_count"] = bool(nat.margins_ok) and int(nat.count) >= int(md.balance.nature_signs_min) and int(nat.count) <= int(md.balance.nature_signs_max) \
			and int(md.balance.nature_signs_min) == 3 and int(md.balance.nature_signs_max) == 5
	r["company_ceiling"] = 0.0 < float(pu.company_ceil_dev) and float(pu.company_ceil_dev) < float(bd.light)
	var majors := [absf(float(pu.friend)), absf(float(pu.close)), absf(float(pu.lapse)), absf(float(pu.lapse_close)), absf(float(pu.grief_min)), absf(float(pu.grief_max)), absf(float(pu.birth_parent))]
	r["min_push_at_most_smallest_major"] = float(md.why.min_push) <= majors.min()
	r["birth_reaches_light"] = float(pu.birth_parent) >= float(bd.light) + float(bd.hyst)
	r["show_dev_is_band_exit"] = absf(float(md.why.show_dev) - (float(bd.light) - float(bd.hyst))) < 1e-9
	# The starting gains are 0.15 and 0.25 whatever is shipped (the dormant build ships 0.0), so the two rules that name them use
	# the spec constants (spec question: both rules are vacuous or false at the dormant gains if read from effects.*).
	r["control_gains"] = float(md.calibration.control_gain) < float(md.calibration.control_gain_next) \
			and float(md.calibration.control_gain_next) <= 0.01 * 0.15
	r["fallback_is_half"] = absf(float(ef.fallback_travel_coef) - 0.15 / 2.0) < 1e-9 and absf(float(ef.fallback_energy_coef) - 0.25 / 2.0) < 1e-9
	var sel: Dictionary = md.selection
	r["selection_positive"] = float(sel.refresh_hz) > 0.0 and float(sel.hold_s) > 0.0 and float(sel.died_beat_s) > 0.0 \
			and float(sel.tap_radius_px) > 0.0 and float(sel.outline_px) > 0.0 \
			and float(sel.open_cut_min) > 0.0 and float(sel.open_cut_min) <= 1.0
	r["mean_dev_order"] = float(md.balance.mean_dev_min) < float(md.balance.mean_dev_max)
	var digit := RegEx.new()
	digit.compile("\\d")
	var strs := {}
	_strings(md.get("text", {}), "text", strs)
	var clean := not strs.is_empty()
	for k in strs:
		if digit.search(str(strs[k])) != null:
			clean = false
	r["texts_digit_free"] = clean
	var tc2: float = float(ef.travel_coef)
	r["span_under_half_trait_span"] = tc2 * (float(ef.clamp_high) - float(ef.clamp_low)) <= float(md.balance.mood_trait_span_max) * float(SimData.beings().restless.travel_coef) + 1e-12
	return r


## The nature rule on the table of 5.1: how many of the twelve signs get a sentence, and whether every threshold keeps its margin
## from every table value (balance.nature_margin_*).
func _nature_sets(md: Dictionary) -> Dictionary:
	var tp: Dictionary = md.temperament
	var nt: Dictionary = md.nature
	var bases: Array = []
	var halves: Array = []
	var chosen := {}
	for s in SimData.signs():
		var b := float(tp.element_base[s.element]) + float(tp.modality_base[s.modality])
		var h := float(tp.halflife_sols[s.modality]) * float(tp.halflife_mult[s.element])
		bases.append(b)
		halves.append(h)
		var pick := ""
		if b <= float(nt.base_lo):
			pick = "heavy"
		elif b >= float(nt.base_hi):
			pick = "bright"
		elif h >= float(nt.slow_halflife):
			pick = "slow"
		elif h <= float(nt.quick_halflife):
			pick = "quick"
		if pick != "":
			chosen[str(s.name)] = pick
	var ok := true
	for b in bases:
		for th in [float(nt.base_lo), float(nt.base_hi)]:
			if absf(float(b) - th) < float(md.balance.nature_margin_base) - 1e-12:
				ok = false
	for h in halves:
		for th in [float(nt.slow_halflife), float(nt.quick_halflife)]:
			if absf(float(h) - th) < float(md.balance.nature_margin_halflife) - 1e-12:
				ok = false
	var kinds := {}
	for k in chosen:
		kinds[chosen[k]] = int(kinds.get(chosen[k], 0)) + 1
	return {"count": chosen.size(), "margins_ok": ok, "kinds": kinds}


func test_t26c_the_sanity_rules_hold_on_the_shipped_data(t) -> void:
	if not _api(t):
		return
	var r := _sanity(_md())
	for k in r:
		t.check(bool(r[k]), "sanity rule %s holds on the shipped data" % k)
	t.check(r.size() >= 20, "all the rules are evaluated (%d)" % r.size())
	var nat := _nature_sets(_md())
	t.eq(int(nat.count), 4, "exactly four of twelve signs get a nature sentence")
	for k in ["heavy", "bright", "slow", "quick"]:
		t.eq(int(nat.kinds.get(k, 0)), 1, "nature sentence %s is chosen by exactly one sign" % k)
	_end(t)


func test_t26d_each_sanity_rule_fails_on_one_broken_copy(t) -> void:
	if not _api(t):
		return
	var breaks := [
		["range_signs", ["range", "floor_dev"], 0.1],
		["band_order", ["bands", "low"], -0.5],
		["hyst_under_half_gap", ["bands", "hyst"], 0.2],
		["halflives_positive", ["temperament", "halflife_sols", "fixed"], 0.0],
		["grief_order", ["push", "grief_max"], -0.1],
		["clamp_signs", ["effects", "clamp_low"], 0.1],
		["gains_nonneg", ["effects", "energy_coef"], 2.0],
		["travel_floor_range", ["effects", "travel_floor"], 1.5],
		["lines_cap", ["lines", "max_per_sol"], 0],
		["nature_signs", ["nature", "base_lo"], 0.1],
		["nature_margins_and_count", ["nature", "slow_halflife"], 8.0],
		["company_ceiling", ["push", "company_ceil_dev"], 0.3],
		["min_push_at_most_smallest_major", ["why", "min_push"], 0.06],
		["birth_reaches_light", ["push", "birth_parent"], 0.2],
		["show_dev_is_band_exit", ["why", "show_dev"], 0.10],
		["control_gains", ["calibration", "control_gain"], 0.01],
		["fallback_is_half", ["effects", "fallback_travel_coef"], 0.1],
		["selection_positive", ["selection", "open_cut_min"], 0.0],
		["mean_dev_order", ["balance", "mean_dev_min"], 0.5],
		["texts_digit_free", ["text", "panel", "k1"], "{name} knows 1 well."],
		["span_under_half_trait_span", ["effects", "clamp_high"], 5.0],
	]
	var base := _md()
	for b in breaks:
		var copy: Dictionary = base.duplicate(true)
		var node: Dictionary = copy
		var path: Array = b[1]
		for i in path.size() - 1:
			node = node[path[i]]
		node[path[path.size() - 1]] = b[2]
		# span rule is vacuous at travel_coef 0.0 (dormant); give it a gain so the break can show.
		if str(b[0]) == "span_under_half_trait_span":
			copy.effects.travel_coef = 0.15
		var r := _sanity(copy)
		t.check(not bool(r[b[0]]), "rule %s fails on a copy broken at %s" % [b[0], ".".join(PackedStringArray(path))])
	_end(t)


# ---------------------------------------------------------------- 27, 28, 29. relationships accessors and feed

func _acc_world() -> Dictionary:
	var w = _world()
	var ids: Array = []
	for i in 6:
		ids.append(_being(w, HAB1 if i < 3 else HAB2).id)
	_setb(w, 1, 2, 0.7)
	_setb(w, 1, 3, 0.4)
	_setb(w, 2, 3, 0.4)
	_setb(w, 4, 5, 0.1)
	_setb(w, 5, 6, 0.4)
	_pair(w, 1, 3).kin = true
	_pair(w, 2, 3).crew = true
	return {"w": w, "ids": ids}


func test_t27a_friend_pairs_returns_flags_and_copies(t) -> void:
	if not _api(t):
		return
	var c := _acc_world()
	var w = c.w
	w.relationships.on_sol(w)
	var r: Dictionary = w.relationships.friend_pairs()
	for k in ["lo", "hi", "flags"]:
		t.check(r.has(k), "friend_pairs has %s" % k)
	if not (r.has("lo") and r.has("hi") and r.has("flags")):
		_end(t)
		return
	t.eq(r.lo.size(), 4, "four friend pairs (1-2 close, 1-3 kin, 2-3 crew, 5-6)")
	t.eq(r.lo.size(), int(w.stats.relationships.friend_pairs), "the count equals stats.relationships.friend_pairs after a sol reading")
	t.eq(r.hi.size(), r.lo.size(), "parallel arrays")
	t.eq(r.flags.size(), r.lo.size(), "flags parallel")
	var want := {"1,2": 1, "1,3": 2, "2,3": 4, "5,6": 0}
	var got := {}
	for i in r.lo.size():
		got["%d,%d" % [r.lo[i], r.hi[i]]] = int(r.flags[i])
	t.eq(got, want, "flags: bit 1 close, 2 kin, 4 crew (1-2 is close because its bond is above the close line)")
	t.check(not got.has("4,5"), "a bond below the friend line is not listed")
	_end(t)


func test_t27b_the_arrays_are_copies_and_the_call_is_read_only(t) -> void:
	if not _api(t):
		return
	var c := _acc_world()
	var w = c.w
	var before := JSON.stringify(w.relationships.pairs, "", true)
	var r: Dictionary = w.relationships.friend_pairs()
	for i in r.flags.size():
		r.flags[i] = 7
		r.lo[i] = 999
	var r2: Dictionary = w.relationships.friend_pairs()
	var clean := true
	for i in r2.lo.size():
		if int(r2.lo[i]) == 999 or int(r2.flags[i]) == 7:
			clean = false
	t.check(clean, "mutating a returned array changes nothing in relationships")
	t.eq(JSON.stringify(w.relationships.pairs, "", true), before, "pairs are untouched")
	var f1: Array = w.relationships.friends_of(1)
	f1.clear()
	t.eq(w.relationships.friends_of(1).size(), 2, "friends_of returns a fresh array")
	_end(t)


func test_t27c_the_council_reads_the_same_world_through_the_accessor(t) -> void:
	if not _api(t):
		return
	var w = SimWorld.new(42)
	w.mood_travel_gain = 0.0
	w.mood_energy_gain = 0.0
	while w.sol() < 120:
		w.step()
	var st: Dictionary = w.stats.council
	var parts: Array = [st.trust, st.chosen, st.voices, st.trust_by_sol, st.chosen_by_sol, st.first_council_sol, st.sessions,
			st.pledge_sol, st.proposals.size(), st.lines, st.lines_dropped]
	var ids: Array = []
	for b in w.beings:
		ids.append([b.id, w.council.lean_of(b.id), w.council.stance_of(b.id)])
	parts.append(ids)
	var d := JSON.stringify(parts, "", true).sha256_text().substr(0, 16)
	t.eq(d, "f4375bd2df1ba9aa", "seed 42 at 120 sols: trust, chosen share, lean, stance and stats.council equal the Task 5 values (digest measured on the unmodified tree)")
	t.eq(int(st.first_council_sol), 115, "and the Council entered at sol 115 as in Task 5")
	_end(t)


func test_t28_friends_of_is_ascending_with_flags_and_a_dictionary_fallback(t) -> void:
	if not _api(t):
		return
	var c := _acc_world()
	var w = c.w
	var f: Array = w.relationships.friends_of(1)
	t.eq(f.size(), 2, "being 1 has two friends")
	if f.size() == 2:
		t.eq(int(f[0].id), 2, "ascending by other id (2)")
		t.eq(int(f[1].id), 3, "then 3")
		t.check(bool(f[0].close) and not bool(f[0].kin) and not bool(f[0].crew), "1-2 is close")
		t.check(bool(f[1].kin) and not bool(f[1].close), "1-3 is kin")
		t.near(float(f[0].bond), 0.7, 1e-9, "bond is reported (never displayed)")
	var f3: Array = w.relationships.friends_of(3)
	t.eq(f3.size(), 2, "being 3 has two friends (1 kin, 2 crew)")
	if f3.size() == 2:
		t.check(bool(f3[1].crew), "2-3 is crew")
	t.eq(w.relationships.friends_of(4).size(), 0, "a being with no friend has none")
	t.eq(w.relationships.friends_of(999).size(), 0, "a missing id returns an empty array")
	_tick(w)  # relationships learns who exists
	_kill(w, 1)
	_tick(w)
	t.eq(w.relationships.friends_of(1).size(), 0, "a dead id returns an empty array")
	# A staged world whose pair dictionary was written without the mirror: the dictionary is the fallback.
	var w2 = _world()
	for i in 3:
		_being(w2, HAB1)
	w2.relationships.pairs[1 * SHIFT + 2] = {"lo": 1, "hi": 2, "bond": 0.5, "friends": true, "close": false, "was_close": false, "kin": false, "crew": false}
	var g: Array = w2.relationships.friends_of(1)
	t.eq(g.size(), 1, "friends_of falls back to the dictionary when the mirror is out of step")
	if g.size() == 1:
		t.eq(int(g[0].id), 2, "the other id")
	var fp: Dictionary = w2.relationships.friend_pairs()
	t.eq(fp.lo.size(), 1, "so does friend_pairs")
	_end(t)


func test_t29a_events_are_cleared_each_tick_and_list_every_kind(t) -> void:
	if not _api(t):
		return
	var w = _world()
	for i in 4:
		_being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	_setb(w, 1, 2, _friend_line() - 0.001)
	_setb(w, 3, 4, _close_line() - 0.001)
	_tick(w)
	var kinds: Array = []
	for e in w.relationships.events:
		kinds.append(str(e.kind))
	kinds.sort()
	t.eq(kinds, ["close", "friend"], "one friend entry and one close entry (kin and crew excluded)")
	for e in w.relationships.events:
		if str(e.kind) == "friend":
			t.eq([int(e.a), int(e.b)], [1, 2], "friend entry {a: lo, b: hi}")
		if str(e.kind) == "close":
			t.eq([int(e.a), int(e.b)], [3, 4], "close entry {a: lo, b: hi}")
	_tick(w)
	t.eq(w.relationships.events.size(), 0, "events are empty at the start of the next tick")
	_end(t)


func test_t29b_a_death_lists_one_grief_entry_per_mourner(t) -> void:
	if not _api(t):
		return
	var w = _grief_world()
	_setb(w, 2, 3, 0.9)
	_setb(w, 2, 4, 0.5)
	_setb(w, 2, 5, 0.31)
	_setb(w, 2, 6, 0.29)
	var nm: String = w.beings[1].name
	_kill(w, 2)
	w.relationships.on_step(w, _tickh())
	var g: Array = []
	for e in w.relationships.events:
		if str(e.kind) == "grief":
			g.append(e)
	t.eq(g.size(), 3, "one grief entry per mourner at or above lines.friend (three), more than the two named in the log")
	var mourners: Array = []
	for e in g:
		mourners.append(int(e.a))
		t.eq(int(e.b), 2, "b is the dead id")
		t.eq(str(e.name), nm, "name is the dead's name")
	mourners.sort()
	t.eq(mourners, [3, 4, 5], "the mourners")
	for e in g:
		if int(e.a) == 3:
			t.near(float(e.bond), 0.9, 1e-9, "bond carried")
	_end(t)


func test_t29c_with_friend_marks_both_ends_of_grown_friend_pairs_only(t) -> void:
	if not _api(t):
		return
	var w = _world()
	for i in 4:
		_being(w, HAB1, 0.0, 0.0, 4.0, true, true)
	_setb(w, 1, 2, 0.5)
	_setb(w, 3, 4, 0.1)
	var bonds0 := JSON.stringify([_pair(w, 1, 2).bond, _pair(w, 3, 4).bond])
	w.relationships.on_step(w, _tickh())
	var wf = w.relationships.with_friend
	t.check(wf.size() > 4, "with_friend is sized by id")
	if wf.size() > 4:
		t.check(int(wf[1]) != 0 and int(wf[2]) != 0, "both ends of the grown friend pair")
		t.check(int(wf[3]) == 0 and int(wf[4]) == 0, "nobody whose only company is a non-friend")
	t.check(JSON.stringify([_pair(w, 1, 2).bond, _pair(w, 3, 4).bond]) != bonds0, "staging: the pairs did grow")
	# Everyone asleep: nothing grows, so nothing is marked.
	var w2 = _world()
	for i in 2:
		_being(w2, HAB1)
	_setb(w2, 1, 2, 0.5)
	w2.relationships.on_step(w2, _tickh())
	var all_zero := true
	for x in w2.relationships.with_friend:
		if int(x) != 0:
			all_zero = false
	t.check(all_zero, "no grown pair, no mark")
	_end(t)


# ---------------------------------------------------------------- 31. permanent hardship with the shipped gains

func test_t31a_a_colony_in_permanent_hardship_stays_inside_the_limits(t) -> void:
	if not _api(t):
		return
	var rg: Dictionary = _md().range
	var w = _world()
	w.mood_travel_gain = 0.15
	w.mood_energy_gain = 0.25
	var ids: Array = []
	for i in 60:
		ids.append(_being(w, HAB1 if i % 2 == 0 else HAB2, [-0.14, 0.0, 0.12][i % 3], 0.0, [1.6, 4.0, 10.4][(i / 3) % 3], false).id)
	for i in 60:
		for k in [1, 2, 5]:
			_setb(w, ids[i], ids[(i + k) % 60], 0.55)
	var tick_h := _tickh()
	var sol_h := float(w.clock.sol_h)
	var t0 := float(w.t)
	var lo := 0.0
	var hi := 0.0
	var worst_m := 0.0
	var killed := 0
	var n_ticks := int(round(100.0 * sol_h / tick_h))
	var next_sol := 0
	for i in n_ticks:
		w.t = t0 + float(i + 1) * tick_h
		w.buildings.now = w.t
		if w.sol() >= next_sol:
			next_sol = w.sol() + 1
			_stocks(w, true, true, true)
			w.moods.on_sol(w)
			if w.sol() % 4 == 1 and killed < 30:
				_kill(w, ids[killed])
				killed += 1
		_tick(w)
		for b in w.beings:
			lo = minf(lo, _d(b))
			hi = maxf(hi, _d(b))
			worst_m = minf(worst_m, float(b.mood))
	t.check(killed >= 20, "staging: a death every fourth sol (%d)" % killed)
	t.check(lo >= float(rg.floor_dev) - 1e-9, "no deviation below floor_dev (lowest %.4f)" % lo)
	t.check(hi <= float(rg.ceil_dev) + 1e-9, "no deviation above ceil_dev (highest %.4f)" % hi)
	t.check(lo < -0.3, "staging: the hardship did reach deep moods (%.4f)" % lo)
	t.check(float(w.stats.moods.min_dev) >= float(rg.floor_dev) - 1e-9, "stats.moods.min_dev inside the floor")
	t.check(float(w.stats.moods.max_dev) <= float(rg.ceil_dev) + 1e-9, "stats.moods.max_dev inside the ceiling")
	t.check(int(w.stats.moods.pushes_zeroed) >= 0, "pushes_zeroed is a count")
	var probe = null
	for b in w.beings:
		if probe == null or float(b.mood) < float(probe.mood):
			probe = b
	var dr := _idle_drain(w, probe)
	var idle := float(SimData.beings().energy.drain_idle)
	t.check(dr <= idle * 1.15 + 1e-9, "the drain factor of the lowest mood is at most 1.15 (%.4f)" % (dr / idle))
	var c := _travel_world(0.0)
	c.w.mood_travel_gain = 0.15
	c.s.mood = worst_m
	c.s._restless_travel(c.w)
	t.check(c.rng.args.size() == 1 and float(c.rng.args[0]) >= float(_md().effects.travel_floor) - 1e-12, "the travel chance at the lowest mood stays at or above 0.02")
	_end(t)


func test_t31b_stepped_hardship_loses_no_being_to_an_unstaged_cause(t) -> void:
	if not _api(t):
		return
	var w = _world()
	w.mood_travel_gain = 0.15
	w.mood_energy_gain = 0.25
	for i in 12:
		_being(w, HAB1 if i % 2 == 0 else HAB2, 0.0, 0.0, 4.0, false, true)
	var next_sol := 0
	while w.sol() < 8:
		if w.sol() >= next_sol:
			next_sol = w.sol() + 1
			w.colony.ice = 0.0
		w.step()
	var other: int = int(w.stats.deaths.other)
	t.eq(other, 0, "no death of cause 'other'")
	t.check(w.stats.moods.pushes.hard_sol > 0, "staging: the hard sols were felt (%d pushes)" % int(w.stats.moods.pushes.hard_sol))
	for b in w.beings:
		t.check(_d(b) >= float(_md().range.floor_dev) - 1e-9, "being %d inside the floor" % b.id)
	_end(t)


# ---------------------------------------------------------------- 34. the noise-floor control

func test_t34a_control_gain_takes_the_mood_branch_with_a_tiny_shift(t) -> void:
	if not _api(t):
		return
	var g := float(_md().calibration.control_gain)
	t.near(g, 1e-4, 1e-12, "the shipped control gain is 1e-4")
	t.near(float(_md().calibration.control_gain_next), 1e-3, 1e-12, "and the next rung 1e-3")
	var c := _travel_world(0.5)
	c.w.mood_travel_gain = g
	var base := _task5_chance(0.5)
	c.s.mood = -0.5
	c.s._restless_travel(c.w)
	t.eq(c.rng.args.size(), 1, "exactly one draw per call")
	if c.rng.args.size() == 1:
		var shift := absf(float(c.rng.args[0]) - base)
		t.check(shift > 0.0, "the argument differs from Task 5's (shift %s)" % str(shift))
		t.check(shift < g * 0.6, "by less than control_gain x 0.6 (the clamp bounds it)")
	c.rng.args.clear()
	c.s.mood = 0.0
	c.s._restless_travel(c.w)
	t.eq(float(c.rng.args[0]) if c.rng.args.size() == 1 else -1.0, base, "and equals Task 5's exactly at a mood of 0")
	_end(t)


func test_t34b_two_control_runs_of_60_sols_are_identical(t) -> void:
	if not _api(t):
		return
	var cs := _control60()
	t.eq(_mood_state(cs[0]), _mood_state(cs[1]), "a second control run on seed 42 for 60 sols is byte-identical to the first")
	_end(t)


# ---------------------------------------------------------------- 35. company ceiling, the snowball tripwire

func test_t35_twenty_friends_together_for_100_sols_never_pass_the_company_ceiling(t) -> void:
	if not _api(t):
		return
	var ceil_dev := _p("company_ceil_dev")
	var w = _world()
	var ids: Array = []
	for i in 20:
		ids.append(_being(w, HAB1, 0.0, 0.0, [2.0, 4.0, 8.0][i % 3], false, true).id)
	for i in 20:
		for j in range(i + 1, 20):
			_setb(w, ids[i], ids[j], 0.95)
	var tick_h := _tickh()
	var t0 := float(w.t)
	var n_ticks := int(round(100.0 * float(w.clock.sol_h) / tick_h))
	var hi := -1.0
	var top_band := 0
	for i in n_ticks:
		w.t = t0 + float(i + 1) * tick_h
		w.buildings.now = w.t
		_tick(w)
		for b in w.beings:
			hi = maxf(hi, _d(b))
			top_band = maxi(top_band, int(b.mood_band))
	t.check(hi <= ceil_dev + 1e-9, "no deviation above +0.15 from company (highest %.6f)" % hi)
	t.check(hi > 0.05, "staging: company did lift moods (%.4f)" % hi)
	t.check(top_band <= 2, "none entered the light band by company alone (top band %d)" % top_band)
	t.check(_push_count(w, "company") > 0, "company pushes were made")
	t.check(0.15 * clampf(hi, -0.6, 0.4) <= 0.15 * ceil_dev + 1e-12, "the travel term from company is at most travel_coef x 0.15")
	_end(t)


# ---------------------------------------------------------------- 36. birth joy

func test_t36_a_birth_push_reaches_light_and_falls_back_within_a_half_life(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var par = _being(w, HAB1, 0.0, 0.0, 4.0, false)
	w._create_newborn(w.buildings.get_building(HAB1), par)
	var nb = w.beings.back()
	_inject(w)
	t.eq(int(par.mood_band), 3, "+0.24 at the baseline reaches the light band")
	t.check(par.mood_why != null and str(par.mood_why.key) in ["birth", "birth_parent"] and int(par.mood_why.id) == nb.id, "the why names the newborn while light")
	var n := 0
	while int(par.mood_band) == 3 and n < 400:
		_inject(w)
		n += 1
	t.eq(int(par.mood_band), 2, "the band falls back to even")
	var half_ticks := 4.0 * float(w.clock.sol_h) / _tickh()
	t.check(n >= 50 and n <= int(half_ticks), "within about a half-life (%d ticks, a half-life is %.0f)" % [n, half_ticks])
	t.check(par.mood_why == null, "and the why is gone with the band")
	_end(t)
