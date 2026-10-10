extends RefCounted
## Task 5, step 4: the Council tests, written first (red). Spec: docs/specs/council.md revision 3 with the owner rulings of
## 2026-10-07 (the lonely run is not adopted and both pulls stay 0.0, so the Task 4 baseline stands; 'family' for the chosen-
## friend clause reaches two generations; the lonely-run seed rule is a probe matter and has no test here). Section 13 tests
## 1 to 20 and 22 live here, except test 19 (the HUD), which is in tests/test_view_council.gd, and test 18's hash-proof
## and balance halves: the pure helpers of tests/council_hash_proof.gd are tested here, the helpers that do not exist yet
## (balance_lib projections, the relationships_hash_proof edit of spec 9.1) fail cleanly through `_has_static`; the parts
## that need a real balance run (the `cn` and `age` columns of a printed table) are parked in
## tests/deferred/test_council_balance.gd.txt until the balance step. Test 21 (the existing suite passes with the module on)
## is the run of tests/run_tests.gd itself and cannot be a unit test.
##
## Naming: test_tNN_* is spec test NN (letters split one spec test into several functions so a failure points at one
## sentence). Almost everything is a hand-made blank world (SimWorld.new(seed, {"blank": true}), add_building, add_being),
## driven by setting world.t to a sol boundary and calling world.council.on_sol(world) (and on_step(world) for gatherings).
## Only tests 2 (lengths), 16 and 22 step the real simulation (test 16 and 22 share three cached 160-sol worlds).
##
## Class access: nothing here names `Council`, `world.council` ... as a static type. Worlds, beings and the module are
## untyped Variants and the script is reached with load("res://sim/council.gd"), so on a tree without the implementation the
## file still parses and each test fails cleanly (every test starts with `_api()`, which records one failed check per missing
## piece and makes the test return before it can abort on a missing member; an aborted test would otherwise pass silently,
## because the runner only fails a test with zero checks). _begin/_end add the same guard to the test body. Data is read with
## SimData.load_json("council.json") (the cache the module must read at world creation); tests that need another value
## overwrite keys of the WORLD'S OWN copy `world.council.cfg` (spec section 3, the staging seam), never the shared cache.
##
## API ASSUMED beyond the spec's own names (the simplest reading; the implementer should match or tell the test author):
##  - `SimWorld.council` (res://sim/council.gd), `SimWorld.council_enabled`, `SimData.council()`, `Ages.enter_age(world,
##    age_id, how, text)` as an instance method of `world.ages`.
##  - Council: on_step(world), on_sol(world), stance_of(id) -> float, lean_of(id) -> float, lean_terms_of(id) -> Dictionary
##    {personal, size, means, hard, child} where `hard` is the POSITIVE magnitude that the formula subtracts (spec 5.6 and 7.3
##    read it as `hard_i > 0`), is_voice(world, id) -> bool, is_family(a, b) -> bool (lineage sets meet).
##  - Council fields as spec section 3 (cfg, parent_of, trust_win, chosen_win, stance, hard_win, best, seen_ticks,
##    last_session_sol, open, set_aside, raised_ever, pledged, quiet_logged, circles_count, circles_last_sol, aftermath,
##    after_pledge_logged, line_sol). Windows are Arrays of floats (hard_win: Array of {hard, ice, air, food}); `pledged`,
##    `set_aside` are Dictionaries keyed by topic; `stance` maps voice id to float. `best` is {building_id, count, ids, t}.
##    Tests write trust_win, chosen_win, hard_win, best, last_session_sol, quiet_logged and cfg keys directly (staging) and
##    read the rest.
##  - stats.council keys as spec section 8; `lines` is a Dictionary of ints (the key names are not asserted, only the sum).
##    `proposals` entries have the keys of section 8 and one is appended per raise.
##  - Log kinds as spec 7.2 (council_proposal, council_proposal_again, council_divided, council_set_aside,
##    council_set_aside_hard, council_set_aside_long, council_pledge, council_aftermath, council_after_pledge, council_quiet,
##    council_circles) with being_id, other_id, building_id and topic keys; the pledge variants share the kind council_pledge.
##    Age lines are kind age_began with age and how.
##  - Text = data text with {a} {b} {place} {ra} {rb} {why} {clause} {adj} replaced; names are `Being.name` (the tests name
##    beings N<id>). Place phrase = text.place.<building kind>; hard clause phrase = text.clause.<ice|air|food>.
##  - A newly raised proposal is `world.council.open` (a Dictionary with the keys of spec section 3) until it is closed, then null.
##  - Entry and split texts are base + " " + season sentence (the ages.md 8.1 rule that spec 7.1 repeats).
##  - Hand-made worlds drive the Council with ages.on_sol NOT called unless a test says so; the Settlement the Council reads is
##    staged by writing age, stats.age, age_changes and an age_history entry directly (`_settle`).
## Where the spec leaves a detail open, extended simply (listed in the task report as numbered spec questions):
##  - Test 8 staleness uses 4.9 and 5.1 sols, not exactly 5 (no tolerance is stated for that comparison).
##  - Test 2 lineage: the spec lists half-siblings, but a being has one parent_id, so a half-sibling pair is a sibling pair.

const CMP := 1e-12
const HAB1 := 2
const HAB2 := 3
const WORKSHOP := 4
const GREEN := 5
const SEASONS := 4

var _undo: Array = []
var _pw: Variant = null


# ---------------------------------------------------------------- guards and api

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


## The council data (the cache the module must copy at creation), {} while the file does not exist.
func _cd() -> Dictionary:
	if not FileAccess.file_exists("res://data/council.json"):
		return {}
	var d: Variant = SimData.load_json("council.json")
	return d if d is Dictionary else {}


## One failed check naming every missing piece of the API; true when every piece the tests touch exists.
func _api(t) -> bool:
	var missing: Array[String] = []
	if not FileAccess.file_exists("res://data/council.json"):
		missing.append("data/council.json")
	var cs = null
	if FileAccess.file_exists("res://sim/council.gd"):
		cs = load("res://sim/council.gd")
	if cs == null:
		missing.append("sim/council.gd")
	var sd = load("res://sim/sim_data.gd")
	if not _has_static(sd, "council"):
		missing.append("SimData.council()")
	var w = SimWorld.new(1, {"blank": true})
	if "council" in w and w.council != null:
		for m in ["on_step", "on_sol", "stance_of", "lean_of", "lean_terms_of", "is_voice", "is_family"]:
			if not w.council.has_method(m):
				missing.append("world.council.%s()" % m)
		for f in ["cfg", "parent_of", "trust_win", "chosen_win", "stance", "hard_win", "best", "seen_ticks",
				"last_session_sol", "open", "set_aside", "raised_ever", "pledged", "quiet_logged", "circles_count",
				"circles_last_sol", "aftermath", "after_pledge_logged", "line_sol"]:
			if not (f in w.council):
				missing.append("world.council.%s" % f)
	else:
		missing.append("SimWorld.council")
	if not ("council_enabled" in w):
		missing.append("SimWorld.council_enabled")
	if not w.ages.has_method("enter_age"):
		missing.append("world.ages.enter_age()")
	if not w.stats.has("council"):
		missing.append("stats.council")
	else:
		for k in ["trust", "chosen", "voices", "trust_by_sol", "chosen_by_sol", "first_council_sol", "sessions",
				"session_log", "proposals", "pledge_sol", "chapters", "lines", "lines_dropped"]:
			if not w.stats.council.has(k):
				missing.append("stats.council.%s" % k)
		if not w.stats.sols_in_age.has("council"):
			missing.append("stats.sols_in_age.council")
	t.check(missing.is_empty(), "missing API: " + ", ".join(PackedStringArray(missing)))
	if missing.is_empty():
		_begin(t)
	return missing.is_empty()


# ---------------------------------------------------------------- staging

## Blank world: reactor, two habitats, workshop, green room (ids 1 to 5), no beings.
func _world(seed_in: int = 1) -> Variant:
	var w = SimWorld.new(seed_in, {"blank": true})
	w.add_building("reactor", 0, 0)
	w.add_building("habitat", 40, 0)
	w.add_building("habitat", 80, 0)
	w.add_building("workshop", 120, 0)
	w.add_building("green_room", 160, 0)
	# The Council skips its readings in Landing (spec 11.1 remedy a), so a staged world that is read starts out as Settlement
	# would have left it. Tests of Landing itself set the age back (see _landing).
	w.ages.age = "settlement"
	w.stats.age = "settlement"
	return w


## A being named N<id>, neutral traits (all 0.5) overwritten by `traits`. `born_sol` null: Earth-born; otherwise Mars-born at
## that elapsed sol (may be negative), so at boundary n it is n - born_sol sols old.
func _voice(w, traits: Dictionary = {}, parent: int = 0, born_sol: Variant = null, bid: int = HAB1) -> Variant:
	var b = w.add_being(bid)
	b.name = "N%d" % b.id
	b.energy = 70.0
	for k in traits:
		b.persona.traits[k] = traits[k]
	b.parent_id = parent
	if born_sol == null:
		b.earth_born = true
	else:
		b.earth_born = false
		b.born_t = w.clock.start_hour + float(born_sol) * w.clock.sol_h
	return b


func _voices(w, n: int, traits: Dictionary = {}) -> Array:
	var ids: Array = []
	for i in n:
		ids.append(_voice(w, traits).id)
	return ids


## Calm stocks: nothing is hard, the means term is zero (regolith at the means centre).
func _calm(w) -> void:
	w.colony.oxygen = w.colony.o2_cap()
	w.colony.food = w.colony.food_cap()
	w.colony.ice = 1000.0
	w.colony.regolith = 0.5 * w.colony.regolith_target()


func _sol_set(w, n: int) -> void:
	w.t = w.clock.start_hour + float(n) * w.clock.sol_h
	w.buildings.now = w.t


func _bnd(w, n: int) -> void:
	_sol_set(w, n)
	w.council.on_sol(w)


## Stages Settlement as Ages would have left it at elapsed sol n (writes the fields the Council reads).
func _settle(w, n: int, how: String = "settled") -> void:
	_sol_set(w, n)
	w.ages.age = "settlement"
	w.stats.age = "settlement"
	w.stats.age_changes += 1
	if w.stats.first_settlement_sol == null:
		w.stats.first_settlement_sol = n
	w.ages.last_change_sol = n
	w.stats.age_history.append({"age": "settlement", "how": how, "cause": null, "text": "Staged.", "pop": w.colony.pop(),
			"family_mars_born": 0, "t": w.t, "sol": n, "clock_sol": w.clock.sol_index(w.t)})


## Stages a Council that began at elapsed sol n and has not met yet.
func _council(w, n: int) -> void:
	_sol_set(w, n)
	w.ages.enter_age(w, "council", "council", "Staged council.")
	if _cs(w).first_council_sol == null:
		_cs(w).first_council_sol = n
	w.council.last_session_sol = n
	w.council.best = {}
	w.council.quiet_logged = false


func _ccfg(w) -> Dictionary:
	return w.council.cfg


func _cs(w) -> Dictionary:
	return w.stats.council


func _friend(w, a: int, b: int, bond: float = 0.5, kin: bool = false, crew: bool = false) -> void:
	w.relationships.debug_set_bond(a, b, bond)
	var p: Dictionary = w.relationships.pairs[Relationships.key_of(a, b)]
	p.kin = kin
	p.crew = crew


func _chain(w, ids: Array, kin: bool = false, crew: bool = false) -> void:
	for i in range(ids.size() - 1):
		_friend(w, ids[i], ids[i + 1], 0.5, kin, crew)


func _best(w, bid: int, ids: Array, tt: float = -1.0) -> void:
	w.council.best = {"building_id": bid, "count": ids.size(), "ids": ids.duplicate(),
			"t": w.t if tt < 0.0 else tt}


## A meeting boundary: sets world.t to sol n, stages the best gathering, runs the sol hook.
func _meet(w, n: int, ids: Array, bid: int = HAB1) -> void:
	_sol_set(w, n)
	_best(w, bid, ids)
	w.council.on_sol(w)


## All Council-kind log entries, oldest first (age lines are kind age_began and not included).
func _clines(w) -> Array:
	var out: Array = []
	for e in w.log:
		if str(e.kind).begins_with("council_"):
			out.append(e)
	return out


func _kinds(w) -> Array:
	var out: Array = []
	for e in _clines(w):
		out.append(str(e.kind))
	return out


func _last_line(w) -> Dictionary:
	var l := _clines(w)
	return l.back() if not l.is_empty() else {}


func _season_phrase(w, tt: float) -> String:
	var ad: Dictionary = SimData.load_json("ages.json")
	return str(ad.season_phrases[w.clock.seasons.find(w.clock.season(tt))])


func _fmt(text: String, sub: Dictionary) -> String:
	var s := text
	for k in sub:
		s = s.replace("{%s}" % k, str(sub[k]))
	return s


func _place(kind: String) -> String:
	return str(_cd().text.place[kind])


func _clause(k: String) -> String:
	return str(_cd().text.clause[k])


func _yes_reason(k: String, adj: String = "", clause: String = "") -> String:
	return _fmt(str(_cd().dome.text.reason.yes[k]), {"adj": adj, "clause": clause})


func _no_reason(k: String, adj: String = "", clause: String = "") -> String:
	return _fmt(str(_cd().dome.text.reason.no[k]), {"adj": adj, "clause": clause})


func _dt(key: String) -> String:
	return str(_cd().dome.text[key])


func _tx(key: String) -> String:
	return str(_cd().text[key])


## Trait sets. Calm and unsized (pop 40 or less, regolith at the centre), a YES voice leans +0.4 and a NO voice -0.4.
const YES := {"drive": 0.9, "curiosity": 0.9, "restless": 0.9}
const NO := {"steady": 0.9, "care": 0.9}


## A Council world of yes + no + neutral earth-born voices (ids in that order), calm stocks, Settlement at sol 10, Council at
## sol 40 (last meeting 40). Returns {w, yes, no, neu, all}.
func _vw(yes: int, no: int, neu: int, cfg_edit: Dictionary = {}) -> Dictionary:
	var w = _world()
	var y := _voices(w, yes, YES)
	var n := _voices(w, no, NO)
	var u := _voices(w, neu)
	_calm(w)
	_settle(w, 10)
	_council(w, 40)
	for path in cfg_edit:
		_set_path(_ccfg(w), str(path), cfg_edit[path])
	return {"w": w, "yes": y, "no": n, "neu": u, "all": y + n + u}


func _set_path(d: Dictionary, path: String, v: Variant) -> void:
	var parts := path.split(".")
	var cur: Dictionary = d
	for i in range(parts.size() - 1):
		cur = cur[parts[i]]
	cur[parts[parts.size() - 1]] = v


func _get_path(d: Dictionary, path: String) -> Variant:
	var cur: Variant = d
	for p in path.split("."):
		cur = cur[p]
	return cur


func _ids_head(a: Array, n: int) -> Array:
	return a.slice(0, n)


## The yes share and no share the module would read (counts), from stance_of.
func _counts(w, ids: Array) -> Array:
	var yes := 0
	var no := 0
	var cfg: Dictionary = _ccfg(w).support
	for id in ids:
		var s := float(w.council.stance_of(id))
		if s > float(cfg.yes_above):
			yes += 1
		elif s < float(cfg.no_below):
			no += 1
	return [yes, no]


# ================================================================ 1. voices

func test_t01a_earth_born_is_a_voice_at_once(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var e = _voice(w)
	_bnd(w, 0)
	t.check(w.council.is_voice(w, e.id), "an Earth-born being is a voice at once (sol 0)")
	t.eq(int(_cs(w).voices), 1, "and the voices reading counts it")
	_end(t)


func test_t01b_mars_born_is_a_voice_from_eighteen_years(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var n := 100
	var young = _voice(w, {}, 0, 0.0)
	var edge = _voice(w, {}, 0, 0.0)
	var old = _voice(w, {}, 0, 0.0)
	var boundary: float = w.clock.start_hour + float(n) * w.clock.sol_h
	var born: float = w.lifecycle.add_months(boundary, -18 * Lifecycle.MONTHS_PER_YEAR)
	young.born_t = born + w.fixed_step
	edge.born_t = born
	old.born_t = born - w.fixed_step
	_bnd(w, n)
	t.check(not w.council.is_voice(w, young.id), "not a voice before the eighteenth birthday")
	t.check(w.council.is_voice(w, edge.id), "a voice exactly on the eighteenth birthday")
	t.check(w.council.is_voice(w, old.id), "older adults are voices")
	t.eq(int(_cs(w).voices), 2, "voices reading 2")
	_end(t)


func test_t01c_min_age_is_read_from_the_world_cfg(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var n := 100
	var b = _voice(w, {}, 0, 0.0)
	var boundary: float = w.clock.start_hour + float(n) * w.clock.sol_h
	b.born_t = w.lifecycle.add_months(boundary, -19 * Lifecycle.MONTHS_PER_YEAR)
	w.lifecycle.cfg.adult_age_years = 20
	_bnd(w, n)
	t.check(not w.council.is_voice(w, b.id), "nineteen is below a staged twenty-year threshold")
	w.lifecycle.cfg.adult_age_years = 18
	_bnd(w, n)
	t.check(w.council.is_voice(w, b.id), "the common eighteen-year threshold makes it a voice")
	_end(t)


func test_t01d_the_dead_are_not_voices(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _voice(w)
	var b = _voice(w)
	_bnd(w, 5)
	t.eq(int(_cs(w).voices), 2, "two voices before the death")
	w._kill(b, "other")
	_bnd(w, 6)
	t.check(not w.council.is_voice(w, b.id), "a dead Earth-born is not a voice")
	t.check(w.council.is_voice(w, a.id), "the living one still is")
	t.eq(int(_cs(w).voices), 1, "the voices reading falls to 1")
	_end(t)


# ================================================================ 2. readings

func test_t02a_one_part_of_six_of_ten_reads_0_6(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var ids := _voices(w, 10)
	_chain(w, _ids_head(ids, 6))
	_bnd(w, 5)
	t.near(float(_cs(w).trust), 0.6, CMP, "six of ten voices in one part")
	t.near(float(_cs(w).chosen), 0.6, CMP, "each of the six has a chosen friend: chosen share 0.6")
	t.near(float(_cs(w).trust_by_sol.back()), 0.6, CMP, "trust_by_sol carries it")
	t.near(float(_cs(w).chosen_by_sol.back()), 0.6, CMP, "chosen_by_sol carries it")
	_end(t)


func test_t02b_two_islands_read_the_larger(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var ids := _voices(w, 10)
	_chain(w, ids.slice(0, 4))
	_chain(w, ids.slice(4, 7))
	_bnd(w, 5)
	t.near(float(_cs(w).trust), 0.4, CMP, "islands of 4 and 3 of ten voices: the larger part, 0.4")
	_end(t)


func test_t02c_a_non_voice_bridge_does_not_join_voice_parts(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a1 = _voice(w)
	var a2 = _voice(w)
	var b1 = _voice(w)
	var b2 = _voice(w)
	var kid = _voice(w, {}, a1.id, 95.0)  # 5 sols old at sol 100: no voice
	_friend(w, a1.id, a2.id)
	_friend(w, b1.id, b2.id)
	_friend(w, a1.id, kid.id)
	_friend(w, kid.id, b1.id)
	_bnd(w, 100)
	t.eq(int(_cs(w).voices), 4, "four voices (the newborn is not one)")
	t.near(float(_cs(w).trust), 0.5, CMP, "the newborn does not join {a1,a2} and {b1,b2}: largest part 2 of 4")
	_end(t)


func test_t02d_kin_and_crew_pairs_count_for_the_web(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var ids := _voices(w, 6)
	_friend(w, ids[0], ids[1], 0.5, true, false)
	_friend(w, ids[1], ids[2], 0.5, false, true)
	_friend(w, ids[2], ids[3], 0.5, false, false)
	_bnd(w, 5)
	t.near(float(_cs(w).trust), 4.0 / 6.0, CMP, "kin, crew and plain pairs all join one part of 4 of 6")
	_end(t)


func test_t02e_non_friend_pairs_do_not_join(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var ids := _voices(w, 4)
	_friend(w, ids[0], ids[1], 0.2)
	_friend(w, ids[2], ids[3], 0.29)
	_bnd(w, 5)
	t.near(float(_cs(w).trust), 0.25, CMP, "bonds under the friend line join nothing: four singletons")
	_end(t)


func test_t02f_chosen_share_ignores_kin_and_crew_friends(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var ids := _voices(w, 6)
	_friend(w, ids[0], ids[1], 0.5, true, false)
	_friend(w, ids[2], ids[3], 0.5, false, true)
	_bnd(w, 5)
	t.near(float(_cs(w).chosen), 0.0, CMP, "voices whose only friends are kin or crew are not counted")
	t.near(float(_cs(w).trust), 2.0 / 6.0, CMP, "though both pairs are in the web")
	_friend(w, ids[4], ids[5], 0.5, false, false)
	_bnd(w, 6)
	t.near(float(_cs(w).chosen), 2.0 / 6.0, CMP, "a plain pair makes both ends chosen")
	_end(t)


func test_t02g_one_chosen_friend_counts_at_one_not_at_two(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var ids := _voices(w, 4)
	_friend(w, ids[0], ids[1])
	_friend(w, ids[0], ids[2])
	_bnd(w, 5)
	t.near(float(_cs(w).chosen), 0.75, CMP, "chosen_friends_min 1: voices 0, 1 and 2 have a chosen friend")
	_ccfg(w).entry.chosen_friends_min = 2
	_bnd(w, 6)
	t.near(float(_cs(w).chosen), 0.25, CMP, "chosen_friends_min 2: only voice 0 has two")
	_end(t)


## Family tree for the lineage cases (ids in creation order): GG(1) earth; G(2) child of GG; P1(3), P2(4) children of G;
## C1(5) child of P1; C2(6) child of P2; F1(7), F2(8) earth; U1(9) child of F1; U2(10) child of F2. All are voices at sol 100.
func _tree() -> Dictionary:
	var w = _world()
	var gg = _voice(w)
	var g = _voice(w, {}, gg.id, -400.0)
	var p1 = _voice(w, {}, g.id, -300.0)
	var p2 = _voice(w, {}, g.id, -300.0)
	var c1 = _voice(w, {}, p1.id, -200.0)
	var c2 = _voice(w, {}, p2.id, -200.0)
	var f1 = _voice(w)
	var f2 = _voice(w)
	var u1 = _voice(w, {}, f1.id, -100.0)
	var u2 = _voice(w, {}, f2.id, -100.0)
	# These lineage fixtures are grown voices; preserve the generation ordering in calendar years.
	for b in w.beings:
		if not b.earth_born:
			b.born_t = w.lifecycle.add_months(b.born_t, -18 * 12)
	_calm(w)
	return {"w": w, "gg": gg.id, "g": g.id, "p1": p1.id, "p2": p2.id, "c1": c1.id, "c2": c2.id, "f1": f1.id, "f2": f2.id,
			"u1": u1.id, "u2": u2.id}


## True when the only friend pair x-y (both pair flags false) makes both ends chosen (chosen share 0.2 of ten voices).
func _pair_is_chosen(tr: Dictionary, x: String, y: String, kin_gen: int = 2) -> bool:
	var w = tr.w
	_ccfg(w).chosen.kin_generations = kin_gen
	_friend(w, tr[x], tr[y])
	_bnd(w, 100)
	return float(_cs(w).chosen) > 0.0


func test_t02h_family_pairs_are_not_chosen_at_two_generations(t) -> void:
	if not _api(t):
		return
	for c in [["p1", "p2", "siblings (and half-siblings: one parent_id, so the same case)"],
			["g", "c1", "grandparent and grandchild"], ["p1", "c2", "aunt and nephew"], ["c1", "c2", "first cousins"],
			["g", "p1", "parent and child"], ["gg", "p1", "grandparent through two steps up"]]:
		var tr := _tree()
		t.check(not _pair_is_chosen(tr, c[0], c[1]), "%s are family: not chosen at kin_generations 2" % c[2])
	_end(t)


func test_t02i_distant_and_unrelated_pairs_are_chosen(t) -> void:
	if not _api(t):
		return
	for c in [["gg", "c1", "great-grandparent and great-grandchild"], ["u1", "u2", "two unrelated Mars-born"],
			["f1", "u2", "a founder with another founder's child"], ["f1", "f2", "two founders (both pair flags false)"],
			["c1", "u1", "cousins of different founder lines"]]:
		var tr := _tree()
		t.check(_pair_is_chosen(tr, c[0], c[1]), "%s are chosen at kin_generations 2" % c[2])
	_end(t)


func test_t02j_siblings_stay_family_after_the_parent_dies(t) -> void:
	if not _api(t):
		return
	var tr := _tree()
	var w = tr.w
	_friend(w, tr.p1, tr.p2)
	_bnd(w, 100)
	t.near(float(_cs(w).chosen), 0.0, CMP, "siblings are family while the parent lives")
	var g = null
	for b in w.beings:
		if b.id == tr.g:
			g = b
	w._kill(g, "other")
	t.check(not w.beings.has(g), "staging: the parent is erased from world.beings")
	_bnd(w, 101)
	t.near(float(_cs(w).chosen), 0.0, CMP, "siblings stay family after the parent is erased (the lineage record keeps it)")
	t.check(w.council.parent_of.has(tr.g), "parent_of still holds the dead parent")
	t.eq(int(w.council.parent_of[tr.p1]), tr.g, "and the child's recorded parent")
	t.check(w.council.is_family(tr.p1, tr.p2), "is_family agrees")
	_end(t)


func test_t02k_kin_generations_zero_counts_only_the_flags(t) -> void:
	if not _api(t):
		return
	var tr := _tree()
	t.check(_pair_is_chosen(tr, "p1", "p2", 0), "kin_generations 0: siblings with both flags false are chosen (revision 2)")
	var tr2 := _tree()
	_ccfg(tr2.w).chosen.kin_generations = 0
	_friend(tr2.w, tr2.g, tr2.p1, 0.5, true, false)
	_bnd(tr2.w, 100)
	t.near(float(_cs(tr2.w).chosen), 0.0, CMP, "and a kin-flagged pair is still not chosen")
	var tr3 := _tree()
	t.check(_pair_is_chosen(tr3, "gg", "p1", 1), "kin_generations 1: a grandparent two steps up is not family")
	var tr4 := _tree()
	t.check(not _pair_is_chosen(tr4, "g", "p1", 1), "kin_generations 1: a parent is family")
	_end(t)


func test_t02l_lineage_is_recorded_for_every_living_being(t) -> void:
	if not _api(t):
		return
	var tr := _tree()
	var w = tr.w
	_bnd(w, 100)
	for k in ["gg", "g", "p1", "p2", "c1", "c2", "f1", "f2", "u1", "u2"]:
		t.check(w.council.parent_of.has(tr[k]), "parent_of has %s" % k)
	t.eq(int(w.council.parent_of[tr.c1]), tr.p1, "c1's parent is p1")
	t.eq(int(w.council.parent_of[tr.gg]), 0, "a founder's parent is 0")
	t.check(w.council.is_family(tr.c1, tr.c2) and not w.council.is_family(tr.c1, tr.u1), "is_family: cousins yes, other lines no")
	_end(t)


func test_t02p_landing_skips_the_readings_and_carries_the_series_forward(t) -> void:
	if not _api(t):
		return
	var a = _world()
	var b = _world()
	for w in [a, b]:
		for i in 6:
			_voice(w, {}, 0, null)
		_chain(w, [1, 2, 3, 4, 5, 6])
		_calm(w)
	# a is staged in Landing for three boundaries, then Settlement; b is Settlement throughout (the old behaviour)
	a.ages.age = "landing"
	a.stats.age = "landing"
	for n in [10, 11, 12]:
		_bnd(a, n)
	t.eq(_cs(a).trust_by_sol.size(), 3, "Landing: one trust entry per boundary")
	t.eq(_cs(a).chosen_by_sol.size(), 3, "Landing: one chosen entry per boundary")
	t.near(float(_cs(a).trust_by_sol[2]), 0.0, CMP, "Landing: the series carry the last reading forward (blank world: 0.0)")
	t.near(float(_cs(a).trust), 0.0, CMP, "Landing: the live reading is not taken")
	t.check(a.council.trust_win.is_empty() and a.council.chosen_win.is_empty(), "Landing: the entry windows are not pushed")
	t.check(a.council.stance.is_empty(), "Landing: no stance is computed")
	t.eq(a.council.hard_win.size(), 3, "Landing: the hard window is kept")
	_settle(a, 13)
	_settle(b, 13)
	for n in range(13, 36):
		_bnd(a, n)
		_bnd(b, n)
	t.eq(_cs(a).trust_by_sol.size(), 26, "after Landing: still one entry per boundary")
	t.check(a.council.trust_win == b.council.trust_win and a.council.chosen_win == b.council.chosen_win, "20 Settlement readings: the entry windows equal those of a world that read throughout")
	t.check(a.council._decide_entry_parts(a, 35) == b.council._decide_entry_parts(b, 35), "and the gate parts are equal")
	t.check(float(_cs(a).trust) == float(_cs(b).trust) and float(_cs(a).chosen) == float(_cs(b).chosen), "and so are the live readings")
	_end(t)


func test_t02q_first_settlement_stance_after_landing_is_built_from_lean(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _voice(w, {"drive": 0.9, "curiosity": 0.9, "restless": 0.9}, 0, null)
	var b = _voice(w, {"steady": 0.9, "care": 0.9}, 0, null)
	_friend(w, a.id, b.id)
	_calm(w)
	_settle(w, 9)
	_bnd(w, 10)  # a stance from before, which the Landing stretch must not leave behind as a decayed one
	w.ages.age = "landing"
	w.stats.age = "landing"
	w.council.stance.clear()
	for n in [11, 12, 13]:
		_bnd(w, n)
	t.check(w.council.stance.is_empty(), "Landing: still no stance")
	_settle(w, 14)
	_bnd(w, 14)
	var sw := float(_cd().sway.share)
	var cw := float(_cd().sway.close_weight)
	var la := float(w.council.lean_of(a.id))
	var lb := float(w.council.lean_of(b.id))
	t.check(absf(la - lb) > 0.01, "the two leans differ (the test can tell)")
	var close: bool = w.relationships.pairs[Relationships.key_of(a.id, b.id)].close
	var wt := cw if close else 1.0
	t.near(float(w.council.stance_of(a.id)), (1.0 - sw) * la + sw * lb, CMP, "first Settlement boundary: a's stance = lean blended with b's lean (weight %.1f)" % wt)
	t.near(float(w.council.stance_of(b.id)), (1.0 - sw) * lb + sw * la, CMP, "and b's likewise")
	_end(t)


func test_t02r_landing_settlement_landing_settlement_matches_a_world_that_read_throughout(t) -> void:
	if not _api(t):
		return
	var a = _world()
	var b = _world()
	for w in [a, b]:
		for i in 6:
			_voice(w, {}, 0, null)
		_chain(w, [1, 2, 3, 4, 5, 6])
		_calm(w)
	a.ages.age = "landing"
	a.stats.age = "landing"
	for n in [10, 11]:
		_bnd(a, n)
	_settle(a, 12)
	for n in range(12, 18):
		_bnd(a, n)
	# a falls back to Landing in the middle, for four boundaries
	a.ages.age = "landing"
	a.stats.age = "landing"
	for n in range(18, 22):
		_bnd(a, n)
	_settle(a, 22)
	_settle(b, 12)
	for n in range(12, 22):
		_bnd(b, n)
	_settle(b, 22)
	for n in range(22, 45):
		_bnd(a, n)
		_bnd(b, n)
	t.eq(_cs(a).trust_by_sol.size(), 35, "a: one entry per boundary throughout")
	t.check(a.council.trust_win == b.council.trust_win and a.council.chosen_win == b.council.chosen_win, "20 Settlement readings after the fall-back: the windows equal those of a world that read throughout")
	t.check(a.council._decide_entry_parts(a, 44) == b.council._decide_entry_parts(b, 44), "and the gate parts are equal")
	_end(t)


func test_t02s_with_ages_disabled_no_reading_is_taken(t) -> void:
	if not _api(t):
		return
	var w = SimWorld.new(42)
	w.ages_enabled = false
	for i in 3 * 500:
		w.step()
	t.check(w.stats.pop_by_sol.size() >= 3, "three sols passed")
	t.eq(str(w.ages.age), "landing", "the age never leaves Landing")
	t.check(w.council.trust_win.is_empty() and w.council.chosen_win.is_empty(), "no reading was pushed to the windows")
	t.check(w.council.stance.is_empty(), "no stance")
	t.eq(_cs(w).trust_by_sol.size(), w.stats.pop_by_sol.size(), "the series still keep pace with pop_by_sol")
	t.near(float(_cs(w).trust_by_sol.back()), float(_cs(w).trust_by_sol[0]), CMP, "carrying the founder reading forward")
	_end(t)


func test_t02m_no_voices_read_zero_and_one_entry_per_boundary(t) -> void:
	if not _api(t):
		return
	var w = _world()
	_voice(w, {}, 0, 5.0)  # 5 sols old at sol 10: no voice
	for n in [10, 11, 12]:
		_bnd(w, n)
	t.near(float(_cs(w).trust), 0.0, CMP, "no voices: trust 0.0")
	t.near(float(_cs(w).chosen), 0.0, CMP, "no voices: chosen 0.0")
	t.eq(int(_cs(w).voices), 0, "no voices: 0")
	t.eq(_cs(w).trust_by_sol.size(), 3, "one trust reading per boundary")
	t.eq(_cs(w).chosen_by_sol.size(), 3, "one chosen reading per boundary")
	t.eq(w.council.trust_win.size(), 3, "and one per boundary in the window")
	var w2 = _world()
	_bnd(w2, 3)
	t.near(float(_cs(w2).trust), 0.0, CMP, "pop 0: trust 0.0")
	t.eq(_cs(w2).trust_by_sol.size(), 1, "pop 0: a reading is still appended")
	_end(t)


func test_t02n_windows_keep_the_last_twenty_readings(t) -> void:
	if not _api(t):
		return
	var w = _world()
	_voices(w, 3)
	for n in range(1, 26):
		_bnd(w, n)
	t.eq(w.council.trust_win.size(), int(_cd().trust.window_sols), "trust_win holds window_sols readings")
	t.eq(w.council.chosen_win.size(), int(_cd().trust.window_sols), "chosen_win too")
	t.eq(_cs(w).trust_by_sol.size(), 25, "while trust_by_sol keeps all of them")
	_end(t)


func test_t02o_lengths_match_pop_by_sol_on_a_founder_world(t) -> void:
	if not _api(t):
		return
	var w = SimWorld.new(42)
	t.eq(_cs(w).trust_by_sol.size(), 1, "founder world: one initial trust reading")
	t.eq(_cs(w).chosen_by_sol.size(), 1, "founder world: one initial chosen reading")
	t.near(float(_cs(w).trust_by_sol[0]), 1.0, CMP, "initial trust 1.0 (seven crew friends)")
	t.near(float(_cs(w).chosen_by_sol[0]), 0.0, CMP, "initial chosen share 0.0 (none chosen)")
	t.eq(w.stats.pop_by_sol.size(), 1, "pop_by_sol has its initial entry")
	for i in 3 * 500:
		w.step()
	t.check(w.stats.pop_by_sol.size() >= 3, "three sols passed")
	t.eq(_cs(w).trust_by_sol.size(), w.stats.pop_by_sol.size(), "trust_by_sol as long as pop_by_sol")
	t.eq(_cs(w).chosen_by_sol.size(), w.stats.pop_by_sol.size(), "chosen_by_sol as long as pop_by_sol")
	_end(t)


func test_t02p_lengths_match_pop_by_sol_on_a_blank_world(t) -> void:
	if not _api(t):
		return
	var w = _world()
	_voices(w, 4)
	_calm(w)
	t.eq(_cs(w).trust_by_sol.size(), 0, "blank world: no initial reading")
	t.eq(w.stats.pop_by_sol.size(), 0, "blank world: no initial pop entry")
	for i in 2 * 500:
		w.step()
		w.colony.oxygen = w.colony.o2_cap()
		w.colony.food = w.colony.food_cap()
		w.colony.ice = 1000.0
	t.check(w.stats.pop_by_sol.size() >= 1, "a sol boundary passed")
	t.eq(_cs(w).trust_by_sol.size(), w.stats.pop_by_sol.size(), "same length as pop_by_sol")
	t.eq(_cs(w).chosen_by_sol.size(), w.stats.pop_by_sol.size(), "chosen too")
	_end(t)


# ================================================================ 3. entry

## A world of `voices` Earth-born voices at Settlement since sol 10. kind: "both" (a chain of six voices: web 0.5 and chosen
## 0.5 of twelve), "web_only" (the same chain, crew pairs: web 0.5, chosen 0.0), "chosen_only" (three pairs: chosen 0.5, web
## 2/12) or "none" (no friends).
func _gate_world(kind: String = "both", voices: int = 12) -> Variant:
	var w = _world()
	var ids := _voices(w, voices)
	_calm(w)
	match kind:
		"both":
			_chain(w, ids.slice(0, 6))
		"web_only":
			_chain(w, ids.slice(0, 6), false, true)
		"chosen_only":
			_friend(w, ids[0], ids[1])
			_friend(w, ids[2], ids[3])
			_friend(w, ids[4], ids[5])
	_settle(w, 10)
	return w


## 19 prefilled readings such that, with the one reading the boundary appends being ok too, `ok_total` of the 20 are ok:
## the bad ones come first, so the last readings are ok.
func _prefill(ok_total: int, ok_val: float, bad_val: float = 0.0) -> Array:
	var out: Array = []
	for i in 19:
		out.append(bad_val if i < 20 - ok_total else ok_val)
	return out


## Stages both windows and runs the boundary n; true when the colony is then a Council.
func _try(w, n: int, tw: Array, cw: Array) -> bool:
	w.council.trust_win = tw.duplicate()
	w.council.chosen_win = cw.duplicate()
	_sol_set(w, n)
	w.council.on_sol(w)
	return str(w.stats.age) == "council"


func test_t03a_settlement_must_be_held_thirty_sols(t) -> void:
	if not _api(t):
		return
	var tw := _prefill(20, 0.9)
	var cw := _prefill(20, 0.9)
	var w = _gate_world()
	t.check(not _try(w, 39, tw, cw), "Settlement held 29 sols (since sol 10) blocks")
	var w2 = _gate_world()
	t.check(_try(w2, 40, tw, cw), "30 sols enters")
	var w3 = _gate_world()
	t.check(not _try(w3, 41 - 30, tw, cw), "and 1 sol does not")
	_end(t)


func test_t03b_web_sixteen_of_twenty_including_the_last_three(t) -> void:
	if not _api(t):
		return
	var cw := _prefill(20, 0.9)
	t.check(not _try(_gate_world(), 40, _prefill(15, 0.5), cw), "15 of 20 web readings at 0.5 blocks")
	t.check(_try(_gate_world(), 40, _prefill(16, 0.5), cw), "16 of 20 enters, and exactly 0.5 counts as ok")
	var near_miss := _prefill(20, 0.5)
	near_miss[17] = 0.49
	t.check(not _try(_gate_world(), 40, near_miss, cw), "a 0.49 among the last 3 readings blocks although 19 of 20 are ok")
	near_miss = _prefill(20, 0.5)
	near_miss[18] = 0.49
	t.check(not _try(_gate_world(), 40, near_miss, cw), "a 0.49 as the second to last reading blocks")
	near_miss = _prefill(20, 0.5)
	near_miss[16] = 0.49
	t.check(_try(_gate_world(), 40, near_miss, cw), "a 0.49 four readings back does not (only the last 3 must be ok)")
	t.check(not _try(_gate_world(), 40, _prefill(20, 0.5).slice(0, 18), cw.slice(0, 18)), "a window that is not full (19 readings) blocks")
	var w = _gate_world()
	_sol_set(w, 40)
	w.council.on_sol(w)
	t.check(str(w.stats.age) != "council", "a fresh window (one reading) blocks even when it is ok")
	_end(t)


func test_t03c_chosen_sixteen_of_twenty_including_the_last_three(t) -> void:
	if not _api(t):
		return
	var tw := _prefill(20, 0.9)
	t.check(not _try(_gate_world(), 40, tw, _prefill(15, 0.5)), "15 of 20 chosen readings at 0.5 blocks")
	t.check(_try(_gate_world(), 40, tw, _prefill(16, 0.5)), "16 of 20 enters, and exactly 0.5 counts as ok")
	var near_miss := _prefill(20, 0.5)
	near_miss[17] = 0.49
	t.check(not _try(_gate_world(), 40, tw, near_miss), "a 0.49 among the last 3 chosen readings blocks")
	near_miss = _prefill(20, 0.5)
	near_miss[16] = 0.49
	t.check(_try(_gate_world(), 40, tw, near_miss), "a 0.49 four readings back does not")
	_end(t)


func test_t03d_the_web_passing_alone_is_not_enough_and_nor_chosen_alone(t) -> void:
	if not _api(t):
		return
	var ok := _prefill(20, 0.9)
	var w = _gate_world("web_only")
	t.check(not _try(w, 40, ok, ok), "web ok, but the boundary's own chosen reading is 0.0 (crew friends only): the last chosen reading fails")
	var w3 = _gate_world("chosen_only")
	t.check(not _try(w3, 40, ok, ok), "chosen ok, but the boundary's own web reading (2 of 12) fails: the last web reading fails")
	var w4 = _gate_world("none")
	t.check(not _try(w4, 40, ok, ok), "no friends at all: blocked")
	var w5 = _gate_world("both")
	t.check(_try(w5, 40, ok, ok), "control: both readings ok enters")
	_end(t)


func test_t03e_twelve_voices_are_needed(t) -> void:
	if not _api(t):
		return
	var ok := _prefill(20, 0.9)
	t.check(not _try(_gate_world("both", 11), 40, ok, ok), "11 voices blocks")
	t.check(_try(_gate_world("both", 12), 40, ok, ok), "12 voices enters")
	var w = _gate_world("both", 12)
	_ccfg(w).entry.voices_min = 13
	t.check(not _try(w, 40, ok, ok), "entry.voices_min 13 in the world's cfg blocks 12")
	_end(t)


func test_t03f_landing_never_enters(t) -> void:
	if not _api(t):
		return
	var ok := _prefill(20, 0.9)
	var w = _gate_world()
	w.ages.age = "landing"
	w.stats.age = "landing"
	t.check(not _try(w, 40, ok, ok), "every clause passing at Landing does not enter")
	t.eq(w.stats.age_changes, 1, "age_changes unchanged (the staged Settlement)")
	_end(t)


func test_t03g_entry_appends_one_history_entry_and_touches_no_ages_state(t) -> void:
	if not _api(t):
		return
	var w = _gate_world()
	w.ages.window = [{"ok": true, "failed": []}, {"ok": false, "failed": ["ice"]}]
	w.ages.last_sample = {"oxygen": true, "ice": false}
	w.ages.snap_shorts = 3
	w.ages.snap_deaths = 2
	w.council.best = {"building_id": HAB1, "count": 6, "ids": [1, 2, 3, 4, 5, 6], "t": 0.0}
	w.council.quiet_logged = true
	w.council.last_session_sol = 3
	var win_before: Array = w.ages.window.duplicate(true)
	var sample_before: Dictionary = w.ages.last_sample.duplicate(true)
	var hist_before: int = w.stats.age_history.size()
	var changes_before: int = w.stats.age_changes
	var began_before := 0
	for e in w.log:
		if e.kind == "age_began":
			began_before += 1
	var ok := _prefill(20, 0.9)
	t.check(_try(w, 40, ok, ok), "staging: the colony enters at sol 40")
	t.eq(w.stats.age_history.size(), hist_before + 1, "exactly one age_history entry is appended")
	var e: Dictionary = w.stats.age_history.back()
	t.eq(e.keys().size(), 9, "the entry has the nine fields of ages.md")
	t.eq(e.age, "council", "age council")
	t.eq(e.how, "council", "how council (first in the run)")
	t.check(e.cause == null, "cause null")
	t.eq(str(e.text), _tx("enter") + " " + _season_phrase(w, w.t), "text: the enter sentence plus the season sentence")
	t.eq(int(e.pop), w.colony.pop(), "pop")
	t.eq(int(e.family_mars_born), Ages.family_mars_born(w)[0], "family_mars_born as ages counts it")
	t.eq(float(e.t), w.t, "t")
	t.eq(int(e.sol), 40, "sol")
	t.eq(int(e.clock_sol), w.clock.sol_index(w.t), "clock_sol")
	t.eq(w.stats.age_changes, changes_before + 1, "age_changes incremented")
	t.eq(w.stats.age_history.size(), int(w.stats.age_changes) + 1, "len(age_history) == age_changes + 1")
	t.eq(str(w.stats.age), "council", "stats.age")
	t.eq(str(w.ages.age), "council", "ages.age")
	t.eq(int(_cs(w).first_council_sol), 40, "first_council_sol")
	var began := 0
	var last_began: Dictionary = {}
	for le in w.log:
		if le.kind == "age_began":
			began += 1
			last_began = le
	t.eq(began, began_before + 1, "one age_began line logged")
	t.eq(str(last_began.get("age", "")), "council", "the line's age")
	t.eq(str(last_began.get("how", "")), "council", "the line's how")
	t.eq(str(last_began.get("text", "")), str(e.text), "and its text is the history text")
	t.eq(w.ages.last_change_sol, 10, "ages.last_change_sol unchanged")
	t.eq(w.ages.window, win_before, "ages.window deep-equal before and after")
	t.eq(w.ages.last_sample, sample_before, "ages.last_sample unchanged")
	t.eq(w.ages.snap_shorts, 3, "snap_shorts unchanged")
	t.eq(w.ages.snap_deaths, 2, "snap_deaths unchanged")
	t.check(w.council.best.is_empty(), "best reset on entry")
	t.check(not bool(w.council.quiet_logged), "quiet_logged reset on entry")
	t.eq(int(w.council.last_session_sol), 40, "last_session_sol is the entry sol")
	_end(t)


func test_t03h_the_second_entry_is_again_and_waits_thirty_sols_after_a_split(t) -> void:
	if not _api(t):
		return
	var w = _gate_world("none")
	_council(w, 40)
	var low: Array = []
	for i in 19:
		low.append(0.05)
	t.check(not _try(w, 60, low, low) and str(w.stats.age) == "settlement", "staging: the Council splits at sol 60")
	var split: Dictionary = w.stats.age_history.back()
	t.eq(str(split.how), "council_split", "how council_split")
	t.eq(int(split.sol), 60, "the split is at sol 60")
	# Friends now make the web and the chosen share pass.
	var ids: Array = []
	for b in w.beings:
		ids.append(b.id)
	_chain(w, ids.slice(0, 6))
	var ok := _prefill(20, 0.9)
	t.check(not _try(w, 89, ok, ok), "29 sols after the split: blocked although 79 sols after the first Settlement")
	t.check(_try(w, 90, ok, ok), "30 sols after the split: enters")
	var e: Dictionary = w.stats.age_history.back()
	t.eq(str(e.how), "council_again", "the second entry in the run is council_again")
	t.eq(str(e.text), _tx("enter_again") + " " + _season_phrase(w, w.t), "with the enter_again text")
	t.eq(w.stats.age_history.size(), int(w.stats.age_changes) + 1, "len(age_history) == age_changes + 1 after three changes")
	_end(t)


## A world like test_ages' good world: reactor, habitat A, green room, habitat B; `founders` Earth-born and `mars` Mars-born
## voices (parent a living founder, birth habitats alternating), calm stocks.
func _good_world(founders: int, mars: int) -> Variant:
	var w = SimWorld.new(1, {"blank": true})
	w.add_building("reactor", 0, 0)
	var ha: int = w.add_building("habitat", 40, 0)
	w.add_building("green_room", 80, 0)
	var hb: int = w.add_building("habitat", 120, 0)
	var fs: Array = []
	for i in founders:
		var f = _voice(w, {}, 0, null, ha)
		fs.append(f)
	for i in mars:
		var b = _voice(w, {}, fs[i % fs.size()].id, -100.0, ha)
		b.birth_building_id = ha if i % 2 == 0 else hb
	_calm(w)
	return w


func test_t03i_no_entry_on_the_boundary_where_ages_enters_settlement(t) -> void:
	if not _api(t):
		return
	var w = _good_world(12, 6)
	var ids: Array = []
	for b in w.beings:
		ids.append(b.id)
	_chain(w, ids.slice(0, 10))
	var win: Array = []
	for i in 39:
		win.append({"ok": true, "failed": []})
	w.ages.window = win
	w.council.trust_win = _prefill(20, 0.9)
	w.council.chosen_win = _prefill(20, 0.9)
	_sol_set(w, 44)
	w.ages.on_sol(w)
	t.eq(str(w.ages.age), "settlement", "staging: Ages enters Settlement at sol 44")
	w.council.on_sol(w)
	t.eq(str(w.stats.age), "settlement", "the Council does not enter on the same boundary, every other clause passing")
	t.eq(w.stats.age_changes, 1, "one age change only")
	t.eq(_cs(w).first_council_sol, null, "no first_council_sol")
	t.eq(str(w.stats.age_history.back().how), "settled", "the last history entry is Ages' own")
	_end(t)


## Stages the boundary at which Ages falls a Settlement colony back to Landing on the first failing sample: a window of 23 ok
## and 16 failed samples (the 40th failing makes 17 failed), ice 0, 50 sols into Settlement.
func _fall_world() -> Variant:
	var w = _good_world(12, 0)
	var ids: Array = []
	for b in w.beings:
		ids.append(b.id)
	_chain(w, ids.slice(0, 6))
	_settle(w, 10)
	var win: Array = []
	for i in 23:
		win.append({"ok": true, "failed": []})
	for i in 16:
		win.append({"ok": false, "failed": ["ice"]})
	w.ages.window = win
	w.colony.ice = 0.0
	return w


func test_t03j_no_entry_on_the_boundary_where_ages_falls_back(t) -> void:
	if not _api(t):
		return
	var w = _fall_world()
	w.council.trust_win = _prefill(20, 0.9)
	w.council.chosen_win = _prefill(20, 0.9)
	_sol_set(w, 60)
	w.ages.on_sol(w)
	t.eq(str(w.ages.age), "landing", "staging: Ages falls back at sol 60")
	w.council.on_sol(w)
	t.eq(str(w.stats.age), "landing", "the Council does not enter on that boundary, every other clause passing")
	t.eq(str(w.stats.age_history.back().how), "fell_back", "the last history entry is the fall-back")
	_end(t)


# ================================================================ 4. split

func _split_world(trust_kind: String = "none") -> Variant:
	var w = _gate_world(trust_kind)
	_council(w, 40)
	return w


func test_t04a_no_split_before_the_twenty_sol_dwell(t) -> void:
	if not _api(t):
		return
	var low := _prefill(20, 0.05, 0.05)
	var w = _split_world()
	t.check(_try(w, 59, low, low) and str(w.stats.age) == "council", "19 sols after the entry: no split")
	var w2 = _split_world()
	t.check(not _try(w2, 60, low, low), "20 sols after the entry: the split happens (the colony is no longer Council)")
	_end(t)


func test_t04b_sixteen_of_twenty_below_a_third_with_the_last_three(t) -> void:
	if not _api(t):
		return
	t.eq(_try_age(_mixed(16)), "settlement", "16 of 20 below 0.3 with the last 3 below splits to Settlement")
	t.eq(_try_age(_mixed(15)), "council", "15 of 20 does not split")
	var near := _mixed(20)
	for i in range(11, 16):
		near[i] = 0.3
	t.eq(_try_age(near), "council", "a reading of exactly 0.3 is not below (15 below, five at 0.3)")
	var gap := _mixed(20)
	gap[18] = 0.9
	t.eq(_try_age(gap), "council", "19 of 20 below but not the last three: no split")
	_end(t)


## 19 prefilled trust readings such that `below` of the 20 (counting the world's own, 0.083) are below 0.3, the others 0.9
## placed first.
func _mixed(below: int) -> Array:
	var out: Array = []
	for i in 19:
		out.append(0.9 if i < 20 - below else 0.05)
	return out


func _try_age(tw: Array) -> String:
	var w = _split_world()
	_try(w, 60, tw, _prefill(20, 0.9))
	return str(w.stats.age)


func test_t04c_the_split_entry_and_its_text(t) -> void:
	if not _api(t):
		return
	var w = _split_world()
	_try(w, 60, _mixed(20), _prefill(20, 0.9))
	t.eq(str(w.stats.age), "settlement", "stats.age settlement")
	t.eq(str(w.ages.age), "settlement", "ages.age settlement")
	var e: Dictionary = w.stats.age_history.back()
	t.eq(str(e.age), "settlement", "history age settlement")
	t.eq(str(e.how), "council_split", "how council_split")
	t.check(e.cause == null, "cause null")
	t.eq(int(e.sol), 60, "sol")
	t.eq(str(e.text), _tx("split") + " " + _season_phrase(w, w.t), "the split sentence plus the season sentence")
	t.eq(w.stats.age_history.size(), int(w.stats.age_changes) + 1, "len(age_history) == age_changes + 1")
	t.eq(w.ages.last_change_sol, 10, "ages.last_change_sol still unchanged")
	_end(t)


func test_t04d_a_low_chosen_share_alone_never_splits(t) -> void:
	if not _api(t):
		return
	var w = _gate_world("web_only")
	_council(w, 40)
	var zero: Array = []
	for i in 19:
		zero.append(0.0)
	t.check(_try(w, 60, _prefill(20, 0.9), zero) and str(w.stats.age) == "council", "all chosen readings 0.0 with a healthy web: no split")
	_end(t)


# ================================================================ 5. ages interplay

func test_t05a_a_council_falls_back_at_the_same_sol_as_a_settlement(t) -> void:
	if not _api(t):
		return
	var a = _fall_world()
	var b = _fall_world()
	_council(b, 55)
	b.colony.ice = 0.0
	for w in [a, b]:
		_sol_set(w, 60)
		w.ages.on_sol(w)
	t.eq(str(a.ages.age), "landing", "the Settlement colony falls back at sol 60")
	t.eq(str(b.ages.age), "landing", "so does the Council colony, at the same sol")
	var ea: Dictionary = a.stats.age_history.back()
	var eb: Dictionary = b.stats.age_history.back()
	t.eq(str(eb.how), "fell_back", "how fell_back")
	t.eq(str(eb.cause), str(ea.cause), "the same cause")
	t.eq(str(eb.cause), "ice", "the cause is ice")
	t.eq(str(eb.text), str(ea.text), "the same fell_back text and cause sentence")
	t.eq(int(eb.sol), int(ea.sol), "the same sol")
	t.eq(b.stats.age_history.size(), a.stats.age_history.size() + 1, "the Council history holds its extra entry")
	t.eq(str(b.stats.age_history[b.stats.age_history.size() - 2].age), "council", "the entry before the fall-back is the Council")
	t.eq(int(b.stats.age_changes), int(a.stats.age_changes) + 1, "age_changes counts the Council entry")
	_end(t)


func test_t05b_time_in_council_is_credited(t) -> void:
	if not _api(t):
		return
	var w = _fall_world()
	w.ages.window = []
	w.colony.ice = 1000.0
	_council(w, 30)
	for n in [31, 32, 33]:
		_sol_set(w, n)
		w.ages.on_sol(w)
	t.eq(int(w.stats.sols_in_age.council), 3, "ages.on_sol credits stats.sols_in_age.council")
	t.eq(int(w.stats.sols_in_age.settlement), 0, "and nothing to Settlement")
	var fresh = SimWorld.new(1, {"blank": true})
	t.eq(fresh.stats.sols_in_age, {"landing": 0, "settlement": 0, "council": 0}, "the dictionary has the council key from creation")
	_end(t)


func test_t05c_ages_decide_is_unchanged_for_landing_and_settlement(t) -> void:
	if not _api(t):
		return
	var all_ok: Array = []
	for i in 40:
		all_ok.append({"ok": true, "failed": []})
	var poor: Array = []
	for i in 23:
		poor.append({"ok": true, "failed": []})
	for i in 17:
		poor.append({"ok": false, "failed": ["ice"]})
	t.eq(Ages.decide(all_ok, "landing", 30, 5, 2), "settlement", "Landing with an ok window and five families in two homes settles")
	t.eq(Ages.decide(all_ok, "landing", 30, 4, 2), "landing", "four families do not")
	t.eq(Ages.decide(all_ok, "landing", 19, 5, 2), "landing", "nor before the dwell")
	t.eq(Ages.decide(poor, "settlement", 30, 5, 2), "landing", "Settlement with 23 ok of 40 falls back")
	t.eq(Ages.decide(all_ok, "settlement", 30, 5, 2), "settlement", "and holds with an ok window")
	t.eq(Ages.decide(poor, "council", 30, 5, 2), "landing", "the same exit rule sends a Council back to Landing")
	t.eq(Ages.decide(all_ok, "council", 30, 5, 2), "council", "and holds a healthy Council")
	_end(t)


# ================================================================ 6. lean

func _tr(b, k: String) -> float:
	return float(b.persona.traits[k])


func _amb(b) -> float:
	return (_tr(b, "drive") + _tr(b, "curiosity") + _tr(b, "restless")) / 3.0


func _cau(b) -> float:
	return (_tr(b, "steady") + _tr(b, "care")) / 2.0


## The five terms by the spec 5.6 formula from the world's own cfg.
func _expect(w, b, size_v: float, means_v: float, hard_v: float, child: bool) -> Dictionary:
	var l: Dictionary = _ccfg(w).dome.lean
	var c := float(l.trait_centre)
	return {
		"personal": float(l.ambition) * (_amb(b) - c) - float(l.caution) * (_cau(b) - c),
		"size": float(l.size) * size_v * (_amb(b) / c),
		"means": float(l.means) * (means_v - float(l.means_centre)) * (_amb(b) / c),
		"hard": float(l.hard) * hard_v * (_cau(b) / c),
		"child": float(l.child) if child else 0.0}


func _check_terms(t, w, b, want: Dictionary, label: String) -> void:
	var got: Dictionary = w.council.lean_terms_of(b.id)
	for k in ["personal", "size", "means", "hard", "child"]:
		t.near(float(got.get(k, 99.0)), float(want[k]), CMP, "%s: term %s" % [label, k])
	var sum := float(want.personal) + float(want.size) + float(want.means) - float(want.hard) + float(want.child) \
			+ float(_ccfg(w).dome.lean.base)
	t.near(float(w.council.lean_of(b.id)), clampf(sum, -1.0, 1.0), CMP, "%s: lean is the clamped sum" % label)


const MIXED := {"drive": 0.8, "curiosity": 0.6, "restless": 0.7, "steady": 0.3, "care": 0.5}


func test_t06a_the_personal_term_alone(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var b = _voice(w, MIXED)
	for i in 9:
		_voice(w)
	_calm(w)
	_bnd(w, 5)
	_check_terms(t, w, b, _expect(w, b, 0.0, 0.5, 0.0, false), "personal only")
	var z: Dictionary = w.council.lean_terms_of(b.id)
	t.near(float(z.size) + float(z.means) + float(z.hard) + float(z.child), 0.0, CMP, "every other term is zero")
	_end(t)


func test_t06b_the_size_term_alone_and_its_clamp(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var b = _voice(w, MIXED)
	for i in 59:
		_voice(w)
	_calm(w)
	_bnd(w, 5)
	_check_terms(t, w, b, _expect(w, b, 0.25, 0.5, 0.0, false), "pop 60: size (60 - 40) / 80 = 0.25")
	var w2 = _world()
	var b2 = _voice(w2, MIXED)
	for i in 129:
		_voice(w2)
	_calm(w2)
	_bnd(w2, 5)
	_check_terms(t, w2, b2, _expect(w2, b2, 1.0, 0.5, 0.0, false), "pop 130: size clamps to 1")
	_end(t)


func test_t06c_the_means_term_alone_and_its_clamp(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var b = _voice(w, MIXED)
	for i in 9:
		_voice(w)
	_calm(w)
	w.colony.regolith = 0.9 * w.colony.regolith_target()
	_bnd(w, 5)
	_check_terms(t, w, b, _expect(w, b, 0.0, 0.9, 0.0, false), "means 0.9")
	w.colony.regolith = 0.1 * w.colony.regolith_target()
	_bnd(w, 6)
	_check_terms(t, w, b, _expect(w, b, 0.0, 0.1, 0.0, false), "means 0.1 (a negative term)")
	w.colony.regolith = 5.0 * w.colony.regolith_target()
	_bnd(w, 7)
	_check_terms(t, w, b, _expect(w, b, 0.0, 1.0, 0.0, false), "means above the target clamps to 1")
	w.colony.regolith = 0.0
	_bnd(w, 8)
	_check_terms(t, w, b, _expect(w, b, 0.0, 0.0, 0.0, false), "no regolith: means 0")
	_end(t)


func _hard_entries(hard_n: int, calm_n: int) -> Array:
	var out: Array = []
	for i in hard_n:
		out.append({"hard": true, "ice": true, "air": false, "food": false})
	for i in calm_n:
		out.append({"hard": false, "ice": false, "air": false, "food": false})
	return out


func test_t06d_the_hard_term_alone_over_the_last_ten_sols(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var b = _voice(w, MIXED)
	for i in 9:
		_voice(w)
	_calm(w)
	w.council.hard_win = _hard_entries(2, 7)
	w.colony.ice = 0.0
	_bnd(w, 5)
	t.eq(w.council.hard_win.size(), 10, "the window holds 10 entries after this boundary's")
	_check_terms(t, w, b, _expect(w, b, 0.0, 0.5, 0.3, false), "3 hard sols of the last 10 (this boundary's is one)")
	w.colony.ice = 1000.0
	for n in range(6, 18):
		_bnd(w, n)
	t.eq(w.council.hard_win.size(), 10, "the window never holds more than hard_window_sols entries")
	_check_terms(t, w, b, _expect(w, b, 0.0, 0.5, 0.0, false), "twelve calm boundaries later the hard sols are gone")
	_end(t)


func test_t06e_the_hard_read_follows_the_ages_clauses_exactly(t) -> void:
	if not _api(t):
		return
	var w = _world()
	_voices(w, 10)
	_calm(w)
	var ac: Dictionary = SimData.load_json("ages.json").sample
	var cc: Dictionary = SimData.colony()
	var use: float = float(w.colony.pop()) * float(cc.consumption.ice_per_being) * w.clock.sol_h
	var n := 5
	# calm
	_bnd(w, n)
	var e: Dictionary = w.council.hard_win.back()
	t.check(not e.hard and not e.ice and not e.air and not e.food, "calm stocks: not hard")
	# oxygen
	n += 1
	w.colony.oxygen = float(ac.o2_min_fraction) * w.colony.o2_cap()
	_bnd(w, n)
	t.check(not w.council.hard_win.back().hard, "oxygen exactly at the minimum fraction is not hard (>=)")
	n += 1
	w.colony.oxygen = float(ac.o2_min_fraction) * w.colony.o2_cap() - 1e-6
	_bnd(w, n)
	e = w.council.hard_win.back()
	t.check(e.hard and e.air and not e.ice and not e.food, "just under it is hard, clause air")
	w.colony.oxygen = w.colony.o2_cap()
	# food
	n += 1
	w.colony.food = float(ac.food_min_fraction) * w.colony.food_cap()
	_bnd(w, n)
	t.check(not w.council.hard_win.back().hard, "food exactly at the minimum fraction is not hard")
	n += 1
	w.colony.food = float(ac.food_min_fraction) * w.colony.food_cap() - 1e-6
	_bnd(w, n)
	e = w.council.hard_win.back()
	t.check(e.hard and e.food and not e.ice and not e.air, "just under it is hard, clause food")
	w.colony.food = w.colony.food_cap()
	# ice
	n += 1
	w.colony.ice = float(ac.ice_min_sols) * use
	_bnd(w, n)
	t.check(not w.council.hard_win.back().hard, "ice exactly at ice_min_sols of consumption is not hard")
	n += 1
	w.colony.ice = float(ac.ice_min_sols) * use - 1e-6
	_bnd(w, n)
	e = w.council.hard_win.back()
	t.check(e.hard and e.ice and not e.air and not e.food, "just under it is hard, clause ice")
	# several at once
	n += 1
	w.colony.oxygen = 0.0
	w.colony.food = 0.0
	w.colony.ice = 0.0
	_bnd(w, n)
	e = w.council.hard_win.back()
	t.check(e.hard and e.ice and e.air and e.food, "all three failing: all three recorded")
	_end(t)


func test_t06f_child_stake_counts_a_living_child_under_twenty_sols(t) -> void:
	if not _api(t):
		return
	var n := 100
	var w = _world()
	var parent = _voice(w)
	for i in 9:
		_voice(w)
	_voice(w, {}, parent.id, float(n) - 19.0)
	_calm(w)
	_bnd(w, n)
	_check_terms(t, w, parent, _expect(w, parent, 0.0, 0.5, 0.0, true), "a child born 19 sols ago: the stake applies")
	var w2 = _world()
	var p2 = _voice(w2)
	for i in 9:
		_voice(w2)
	_voice(w2, {}, p2.id, float(n) - 21.0)
	_calm(w2)
	_bnd(w2, n)
	_check_terms(t, w2, p2, _expect(w2, p2, 0.0, 0.5, 0.0, false), "a child born 21 sols ago: no stake")
	var w3 = _world()
	var p3 = _voice(w3)
	for i in 9:
		_voice(w3)
	var kid = _voice(w3, {}, p3.id, float(n) - 5.0)
	_calm(w3)
	_bnd(w3, n - 1)
	w3._kill(kid, "other")
	_bnd(w3, n)
	_check_terms(t, w3, p3, _expect(w3, p3, 0.0, 0.5, 0.0, false), "a dead child gives no stake")
	_end(t)


func test_t06g_the_clamp_at_plus_and_minus_one(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var hi = _voice(w, {"drive": 1.0, "curiosity": 1.0, "restless": 1.0, "steady": 0.0, "care": 0.0})
	var lo = _voice(w, {"drive": 0.0, "curiosity": 0.0, "restless": 0.0, "steady": 1.0, "care": 1.0})
	for i in 59:
		_voice(w)
	_calm(w)
	w.colony.regolith = w.colony.regolith_target()
	w.council.hard_win = _hard_entries(9, 0)
	w.colony.ice = 0.0
	_bnd(w, 5)
	t.near(float(w.council.lean_of(hi.id)), 1.0 if _expect(w, hi, 0.25, 1.0, 1.0, false).personal \
			+ _expect(w, hi, 0.25, 1.0, 1.0, false).size - _expect(w, hi, 0.25, 1.0, 1.0, false).hard > 1.0 else \
			clampf(_expect(w, hi, 0.25, 1.0, 1.0, false).personal + _expect(w, hi, 0.25, 1.0, 1.0, false).size \
			+ _expect(w, hi, 0.25, 1.0, 1.0, false).means - _expect(w, hi, 0.25, 1.0, 1.0, false).hard, -1.0, 1.0),
			CMP, "the ambitious voice's lean is the clamped sum")
	t.near(float(w.council.lean_of(lo.id)), -1.0, CMP, "a cautious, unambitious voice in a hard season clamps at -1")
	var w2 = _world()
	var top = _voice(w2, {"drive": 1.0, "curiosity": 1.0, "restless": 1.0, "steady": 0.0, "care": 0.0})
	for i in 129:
		_voice(w2)
	_calm(w2)
	w2.colony.regolith = w2.colony.regolith_target()
	_bnd(w2, 5)
	var tt: Dictionary = w2.council.lean_terms_of(top.id)
	t.check(float(tt.personal) + float(tt.size) + float(tt.means) > 1.0, "staging: the unclamped sum exceeds 1")
	t.near(float(w2.council.lean_of(top.id)), 1.0, CMP, "and the lean clamps at +1")
	_end(t)


func test_t06h_conditions_weigh_by_temperament(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var cautious = _voice(w, {"steady": 0.9, "care": 0.9})
	var bold = _voice(w, {"steady": 0.1, "care": 0.1})
	for i in 59:
		_voice(w)
	_calm(w)
	w.council.hard_win = _hard_entries(4, 5)
	w.colony.ice = 0.0
	_bnd(w, 5)
	var hc: Dictionary = w.council.lean_terms_of(cautious.id)
	var hb: Dictionary = w.council.lean_terms_of(bold.id)
	t.check(float(hc.hard) > float(hb.hard) and float(hb.hard) > 0.0, "hardship moves a cautious voice further than a bold one")
	t.near(float(hc.hard) / float(hb.hard), 9.0, 1e-9, "in the ratio of caution over caution (0.9 / 0.1)")
	var w2 = _world()
	var driven = _voice(w2, {"drive": 0.9, "curiosity": 0.9, "restless": 0.9})
	var mild = _voice(w2, {"drive": 0.1, "curiosity": 0.1, "restless": 0.1})
	for i in 59:
		_voice(w2)
	_calm(w2)
	_bnd(w2, 5)
	var sd: Dictionary = w2.council.lean_terms_of(driven.id)
	var sm: Dictionary = w2.council.lean_terms_of(mild.id)
	t.check(float(sd.size) > float(sm.size) and float(sm.size) > 0.0, "crowding stirs the ambitious more")
	_end(t)


func test_t06i_trait_centre_is_read_from_the_cfg(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var b = _voice(w, MIXED)
	for i in 59:
		_voice(w)
	_calm(w)
	w.council.hard_win = _hard_entries(2, 7)
	w.colony.ice = 0.0
	w.colony.regolith = 0.8 * w.colony.regolith_target()
	_bnd(w, 5)
	_check_terms(t, w, b, _expect(w, b, 0.25, 0.8, 0.3, false), "centre 0.5")
	_ccfg(w).dome.lean.trait_centre = 0.25
	w.council.hard_win = _hard_entries(2, 7)
	_bnd(w, 6)
	_check_terms(t, w, b, _expect(w, b, 0.25, 0.8, 0.3, false), "centre 0.25: the personal term and the temperament factors move by the formula")
	_ccfg(w).dome.lean.means_centre = 0.7
	w.council.hard_win = _hard_entries(2, 7)
	_bnd(w, 7)
	_check_terms(t, w, b, _expect(w, b, 0.25, 0.8, 0.3, false), "means_centre 0.7 moves the means term")
	_end(t)


func test_t06j_base_is_added_to_every_lean(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var b = _voice(w, MIXED)
	for i in 9:
		_voice(w)
	_calm(w)
	_ccfg(w).dome.lean.base = 0.05
	_bnd(w, 5)
	_check_terms(t, w, b, _expect(w, b, 0.0, 0.5, 0.0, false), "lean.base 0.05 adds to the sum")
	_end(t)


# ================================================================ 7. sway

func test_t07a_an_isolated_voice_has_stance_equal_to_lean(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _voice(w, MIXED)
	var b = _voice(w, YES)
	_calm(w)
	_bnd(w, 5)
	t.near(float(w.council.stance_of(a.id)), float(w.council.lean_of(a.id)), CMP, "no friends: stance = lean")
	t.near(float(w.council.stance_of(b.id)), float(w.council.lean_of(b.id)), CMP, "for both voices")
	_bnd(w, 6)
	t.near(float(w.council.stance_of(a.id)), float(w.council.lean_of(a.id)), CMP, "and at the next boundary")
	_end(t)


func test_t07b_two_friends_move_toward_each_other_by_the_formula(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _voice(w, YES)
	var b = _voice(w, NO)
	_calm(w)
	_friend(w, a.id, b.id)
	_bnd(w, 5)
	var la := float(w.council.lean_of(a.id))
	var lb := float(w.council.lean_of(b.id))
	var s := float(_ccfg(w).sway.share)
	var sa := (1.0 - s) * la + s * lb
	var sb := (1.0 - s) * lb + s * la
	t.near(float(w.council.stance_of(a.id)), sa, CMP, "first boundary: the friend's previous stance is its lean")
	t.near(float(w.council.stance_of(b.id)), sb, CMP, "and the other way")
	var sa2 := (1.0 - s) * la + s * sb
	var sb2 := (1.0 - s) * lb + s * sa
	_bnd(w, 6)
	t.near(float(w.council.stance_of(a.id)), sa2, CMP, "second boundary: synchronous, from the old stances")
	t.near(float(w.council.stance_of(b.id)), sb2, CMP, "both new stances come from the old ones")
	_end(t)


func test_t07c_a_close_friend_weighs_close_weight(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _voice(w, MIXED)
	var j = _voice(w, YES)
	var k = _voice(w, NO)
	_calm(w)
	_friend(w, a.id, j.id, 0.7)
	_friend(w, a.id, k.id, 0.5)
	t.check(w.relationships.pairs[Relationships.key_of(a.id, j.id)].close, "staging: the first pair is close")
	t.check(not w.relationships.pairs[Relationships.key_of(a.id, k.id)].close, "staging: the second is not")
	_bnd(w, 5)
	var cw := float(_ccfg(w).sway.close_weight)
	var s := float(_ccfg(w).sway.share)
	var la := float(w.council.lean_of(a.id))
	var lj := float(w.council.lean_of(j.id))
	var lk := float(w.council.lean_of(k.id))
	var want := (1.0 - s) * la + s * (cw * lj + 1.0 * lk) / (cw + 1.0)
	t.near(float(w.council.stance_of(a.id)), want, CMP, "stance = (1 - share) lean + share x weighted mean of the friends' stances")
	_end(t)


func test_t07d_a_non_voice_friend_is_ignored(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _voice(w, MIXED)
	var kid = _voice(w, YES, a.id, 95.0)  # 5 sols old at sol 100: not a voice
	_calm(w)
	_friend(w, a.id, kid.id)
	_bnd(w, 100)
	t.near(float(w.council.stance_of(a.id)), float(w.council.lean_of(a.id)), CMP, "a voice whose only friend is a newborn keeps its lean")
	var j = _voice(w, NO)
	_friend(w, a.id, j.id)
	_bnd(w, 101)
	var s := float(_ccfg(w).sway.share)
	var want := (1.0 - s) * float(w.council.lean_of(a.id)) + s * float(w.council.lean_of(j.id))
	t.near(float(w.council.stance_of(a.id)), want, CMP, "with a voice friend as well, only the voice counts")
	t.check(not w.council.stance.has(kid.id), "the newborn has no stance entry")
	_end(t)


func test_t07e_dead_and_former_voices_are_dropped_from_stance(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var a = _voice(w)
	var b = _voice(w)
	_bnd(w, 5)
	t.check(w.council.stance.has(a.id) and w.council.stance.has(b.id), "both voices have a stance")
	w._kill(b, "other")
	_bnd(w, 6)
	t.check(w.council.stance.has(a.id) and not w.council.stance.has(b.id), "the dead one's entry is dropped at the next boundary")
	_end(t)


## Twelve voices with varied traits and a dense web of unequal bonds, as a list of pairs [a, b, bond].
func _web_pairs() -> Array:
	var out: Array = []
	for i in range(1, 13):
		for j in range(i + 1, 13):
			if (i * 7 + j * 3) % 4 != 0:
				out.append([i, j, 0.35 + float((i * j) % 7) * 0.05])
	return out


func _web_world(pairs: Array, reverse_beings: bool) -> Variant:
	var w = _world()
	for i in 12:
		var f := float(i)
		_voice(w, {"drive": 0.2 + f * 0.06, "curiosity": 0.9 - f * 0.045, "restless": 0.35 + f * 0.031,
				"steady": 0.8 - f * 0.052, "care": 0.15 + f * 0.049})
	_calm(w)
	for p in pairs:
		_friend(w, p[0], p[1], p[2], false, false)
	if reverse_beings:
		w.beings.reverse()
	return w


func test_t07f_reversing_the_order_of_beings_changes_nothing(t) -> void:
	if not _api(t):
		return
	var a = _web_world(_web_pairs(), false)
	var b = _web_world(_web_pairs(), true)
	for n in [5, 6, 7]:
		_bnd(a, n)
		_bnd(b, n)
	var same := true
	for id in range(1, 13):
		same = same and float(a.council.stance_of(id)) == float(b.council.stance_of(id))
	t.check(same, "bit-identical stances with the beings in opposite orders")
	t.check(float(_cs(a).trust) == float(_cs(b).trust) and float(_cs(a).chosen) == float(_cs(b).chosen), "and identical readings")
	var spread := 0.0
	for id in range(1, 13):
		spread = maxf(spread, absf(float(a.council.stance_of(id)) - float(a.council.lean_of(id))))
	t.check(spread > 0.01, "staging: sway moved somebody (%f)" % spread)
	_end(t)


func test_t07g_pair_insertion_order_changes_nothing(t) -> void:
	if not _api(t):
		return
	var fwd: Array = _web_pairs()
	var rev: Array = fwd.duplicate()
	rev.reverse()
	var a = _web_world(fwd, false)
	var b = _web_world(rev, false)
	t.check(a.relationships.pairs.keys() != b.relationships.pairs.keys(), "staging: the two dictionaries iterate in different orders")
	for n in [5, 6, 7]:
		_bnd(a, n)
		_bnd(b, n)
	var same := true
	for id in range(1, 13):
		same = same and float(a.council.stance_of(id)) == float(b.council.stance_of(id))
	t.check(same, "bit-identical stances")
	t.check(float(_cs(a).trust) == float(_cs(b).trust), "identical trust")
	t.check(float(_cs(a).chosen) == float(_cs(b).chosen), "identical chosen share")
	t.check(_cs(a).trust_by_sol == _cs(b).trust_by_sol and _cs(a).chosen_by_sol == _cs(b).chosen_by_sol, "and identical series")
	_end(t)


# ================================================================ 8. gatherings and meetings

func _held(w) -> int:
	return int(_cs(w).sessions)


## One relationship tick as the phase 11b hook sees it: `present` is set, `ticks` moves, the Council reads it.
func _tick(w, present: Dictionary, hours: float = 0.0) -> void:
	w.t += hours
	w.buildings.now = w.t
	w.relationships.present = present
	w.relationships.ticks += 1
	w.council.on_step(w)


func test_t08a_no_meeting_before_the_interval(t) -> void:
	if not _api(t):
		return
	var v := _vw(2, 0, 10)
	var w = v.w
	var room: Array = v.all.slice(0, 6)
	_meet(w, 44, room)
	t.eq(_held(w), 0, "the Council began at sol 40: sol 44 is 4 sols on, under the 5-sol interval")
	_meet(w, 45, room)
	t.eq(_held(w), 1, "sol 45 meets")
	_meet(w, 49, room)
	t.eq(_held(w), 1, "4 sols after a meeting: none")
	_meet(w, 50, room)
	t.eq(_held(w), 2, "5 sols after: a meeting")
	_end(t)


func test_t08b_the_room_must_be_big_enough_scaled_by_voices(t) -> void:
	if not _api(t):
		return
	var v := _vw(0, 0, 30)
	var w = v.w
	_meet(w, 45, v.all.slice(0, 4))
	t.eq(_held(w), 0, "30 voices: a best gathering of 4 does not meet (min_voices 5)")
	_meet(w, 46, v.all.slice(0, 5))
	t.eq(_held(w), 1, "5 meets (the interval had already passed, so the meeting was only waiting)")
	var v2 := _vw(0, 0, 80)
	var w2 = v2.w
	_meet(w2, 45, v2.all.slice(0, 7))
	t.eq(_held(w2), 0, "80 voices: 7 does not meet, ceil(0.1 x 80) is 8")
	_meet(w2, 46, v2.all.slice(0, 8))
	t.eq(_held(w2), 1, "8 meets")
	_end(t)


func test_t08c_gathering_read_ties_and_counting(t) -> void:
	if not _api(t):
		return
	var v := _vw(0, 0, 12)
	var w = v.w
	var base: float = w.t
	var h: float = w.clock.sol_h
	var kid = _voice(w, {}, 0, 44.0)  # 1 sol old at sol 45: no voice
	var ids: Array = v.all
	# tick 1: building 3 holds five voices and the newborn, listed in descending order
	var five: Array = ids.slice(0, 5)
	var lst: Array = five.duplicate()
	lst.append(kid.id)
	lst.reverse()
	_tick(w, {HAB2: lst}, 5.0 * h)
	t.eq(int(w.council.best.get("building_id", -1)), HAB2, "the room of tick 1 is the best")
	t.eq(int(w.council.best.get("count", -1)), 5, "the newborn is not counted")
	t.eq(w.council.best.get("ids", []), five, "ids are the voices, ascending")
	var t1: float = w.t
	t.eq(float(w.council.best.get("t", -1.0)), t1, "t is the tick time")
	# tick 2: an equal room elsewhere does not replace it (the earliest tick wins a tie)
	_tick(w, {HAB1: ids.slice(5, 10)}, 1.0)
	t.eq(int(w.council.best.building_id), HAB2, "a tie across ticks: the earliest tick stays")
	t.eq(float(w.council.best.t), t1, "and keeps its time")
	# no new tick: nothing is read, even if present changed
	w.relationships.present = {HAB1: ids.slice(0, 9)}
	w.council.on_step(w)
	t.eq(int(w.council.best.building_id), HAB2, "without a new relationship tick nothing is read")
	# tick 3: a larger room replaces it
	_tick(w, {HAB1: ids.slice(0, 6)}, 1.0)
	t.eq(int(w.council.best.building_id), HAB1, "strictly more replaces")
	t.eq(int(w.council.best.count), 6, "count 6")
	# a tie within one tick: the lower building id
	var v2 := _vw(0, 0, 12)
	var w2 = v2.w
	_tick(w2, {HAB2: v2.all.slice(0, 5), HAB1: v2.all.slice(5, 10)}, 5.0 * h)
	t.eq(int(w2.council.best.building_id), HAB1, "a tie within one tick: the lower building id")
	# a dark room counts
	var v3 := _vw(0, 0, 12)
	var w3 = v3.w
	w3.set_offline(HAB1, true)
	_tick(w3, {HAB1: v3.all.slice(0, 5)}, 5.0 * h)
	t.eq(int(w3.council.best.get("count", 0)), 5, "an offline room counts, as in Task 4")
	_end(t)


func test_t08d_only_the_council_reads_gatherings(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var ids := _voices(w, 12)
	_calm(w)
	_settle(w, 10)
	_sol_set(w, 45)
	_tick(w, {HAB1: ids.slice(0, 8)})
	t.check(w.council.best.is_empty(), "in Settlement the gathering read does nothing")
	_best(w, HAB1, ids.slice(0, 8))
	w.council.last_session_sol = 0
	w.council.on_sol(w)
	t.eq(_held(w), 0, "and no meeting is held in Settlement")
	_end(t)


func test_t08e_the_place_and_the_cleared_best(t) -> void:
	if not _api(t):
		return
	var v := _vw(0, 0, 12)
	var w = v.w
	_meet(w, 45, v.all.slice(0, 7), GREEN)
	t.eq(_held(w), 1, "a meeting")
	var rec: Dictionary = _cs(w).session_log.back()
	t.eq(int(rec.building_id), GREEN, "the place is the best building")
	t.eq(int(rec.sol), 45, "session_log sol")
	t.eq(int(rec.present), 7, "present is the best count")
	t.eq(int(rec.voices), 12, "voices")
	for k in ["yes", "no", "hard"]:
		t.check(rec.has(k), "session_log carries " + k)
	t.check(w.council.best.is_empty(), "best is cleared after a meeting")
	t.eq(int(w.council.last_session_sol), 45, "last_session_sol")
	_end(t)


func test_t08f_a_stale_best_gathering_is_cleared(t) -> void:
	if not _api(t):
		return
	var v := _vw(0, 0, 12)
	var w = v.w
	var h: float = w.clock.sol_h
	_sol_set(w, 45)
	_best(w, HAB1, v.all.slice(0, 7), w.t - 4.9 * h)
	w.council.on_sol(w)
	t.eq(_held(w), 1, "a best gathering 4.9 sols old still counts")
	var v2 := _vw(0, 0, 12)
	var w2 = v2.w
	_sol_set(w2, 45)
	_best(w2, HAB1, v2.all.slice(0, 7), w2.t - 5.1 * h)
	w2.council.on_sol(w2)
	t.eq(_held(w2), 0, "one 5.1 sols old is cleared before the meeting check: none")
	t.check(w2.council.best.is_empty(), "and best is empty")
	_end(t)


# ================================================================ 9. raise

func test_t09a_the_highest_stance_of_the_room_raises_it(t) -> void:
	if not _api(t):
		return
	var v := _vw(3, 0, 3)
	var w = v.w
	var y: Array = v.yes
	# the room: the second and third yes voices and two neutral ones (the first yes voice is outside)
	_meet(w, 45, [y[2], y[1], v.neu[0], v.neu[1], v.neu[2]], GREEN)
	t.eq(_kinds(w), ["council_proposal"], "one proposal line and nothing else")
	var e: Dictionary = _last_line(w)
	t.eq(int(e.being_id), int(y[1]), "equal stances: the lower id of the room, not the better-placed one outside it")
	t.eq(str(e.text), _fmt(_dt("proposal"), {"a": "N%d" % y[1], "place": _place("green_room")}), "the text, with the place phrase")
	t.eq(int(e.building_id), GREEN, "building_id")
	t.eq(str(e.topic), "dome", "topic")
	t.check(w.council.open != null and str(w.council.open.topic) == "dome" and int(w.council.open.proposer_id) == int(y[1]), "a proposal is open")
	t.eq(int(w.council.open.votes), 0, "the raising meeting is not a vote")
	t.eq(_cs(w).proposals.size(), 1, "one proposals entry")
	var p: Dictionary = _cs(w).proposals[0]
	t.check(int(p.raised_sol) == 45 and int(p.proposer_id) == int(y[1]) and not bool(p.again) and p.outcome == null, "its fields")
	_end(t)


func test_t09b_a_dead_voice_in_the_room_is_skipped(t) -> void:
	if not _api(t):
		return
	var v := _vw(2, 0, 8)
	var w = v.w
	var top = null
	for b in w.beings:
		if b.id == v.yes[0]:
			top = b
	top.persona.traits.drive = 1.0
	top.persona.traits.curiosity = 1.0
	top.persona.traits.restless = 1.0
	var room: Array = [v.yes[0], v.yes[1], v.neu[0], v.neu[1], v.neu[2]]
	_bnd(w, 41)
	t.check(float(w.council.stance_of(v.yes[0])) > float(w.council.stance_of(v.yes[1])), "staging: the first yes voice has the higher stance")
	w._kill(top, "other")
	_sol_set(w, 45)
	_best(w, HAB1, room)
	w.council.on_sol(w)
	t.eq(_held(w), 1, "the meeting is held on the strength of the full room")
	t.eq(int(_last_line(w).being_id), int(v.yes[1]), "the next living voice of the room is named")
	# every voice of the room dead: the meeting is held, nothing is raised, the quiet line follows
	var v2 := _vw(5, 0, 8)
	var w2 = v2.w
	var dead: Array = []
	for b in w2.beings.duplicate():
		if v2.yes.has(b.id):
			dead.append(b.id)
			w2._kill(b, "other")
	_sol_set(w2, 45)
	_best(w2, HAB1, dead)
	w2.council.on_sol(w2)
	t.eq(_held(w2), 1, "a room of the dead still counts as a meeting (its size was read when it was full)")
	t.check(w2.council.open == null, "nothing is raised")
	t.eq(_kinds(w2), ["council_quiet"], "the quiet line is logged")
	_end(t)


func test_t09c_nobody_wants_it_the_quiet_line_once_per_term(t) -> void:
	if not _api(t):
		return
	var v := _vw(0, 0, 12)
	var w = v.w
	_meet(w, 45, v.all.slice(0, 6))
	t.eq(_kinds(w), ["council_quiet"], "no one in the room is above yes_above: the quiet line")
	t.eq(str(_last_line(w).text), _tx("quiet"), "the plain text")
	t.check(w.council.open == null, "nothing is open")
	_meet(w, 50, v.all.slice(0, 6))
	t.eq(_kinds(w), ["council_quiet"], "the second silent meeting logs nothing more")
	# the hard variant at a hard share of 0.5
	var v2 := _vw(0, 0, 12)
	var w2 = v2.w
	_sol_set(w2, 45)
	_best(w2, HAB1, v2.all.slice(0, 6))
	w2.council.hard_win = _hard_entries(5, 0)  # five hard sols of the last ten: the hard share is 0.5
	w2.council.on_sol(w2)
	t.eq(_kinds(w2), ["council_quiet"], "a quiet line in a world of its own")
	t.eq(str(_last_line(w2).text), _fmt(_tx("quiet_hard"), {"clause": _clause("ice")}), "hard share 0.5: the hard variant with the clause phrase")
	# no quiet line when a proposal is open or the topic is pledged
	var v3 := _vw(2, 0, 10)
	var w3 = v3.w
	_meet(w3, 45, [v3.yes[0], v3.yes[1], v3.neu[0], v3.neu[1], v3.neu[2]])
	t.check(w3.council.open != null, "staging: a proposal is open")
	var v4 := _vw(0, 0, 12)
	var w4 = v4.w
	w4.council.pledged["dome"] = 41
	_meet(w4, 45, v4.all.slice(0, 6))
	t.check(not ("council_quiet" in _kinds(w4)), "pledged: no quiet line")
	_end(t)


func test_t09d_never_two_open_proposals(t) -> void:
	if not _api(t):
		return
	var v := _vw(6, 0, 4)
	var w = v.w
	var room: Array = v.all.slice(0, 6)
	_meet(w, 45, room)
	_meet(w, 50, room)
	_meet(w, 55, room)
	var n := 0
	for k in _kinds(w):
		if k == "council_proposal" or k == "council_proposal_again":
			n += 1
	t.eq(n, 1, "one raise only while the proposal is open (or pledged)")
	t.eq(_cs(w).proposals.size(), 1, "one proposals entry")
	_end(t)


func test_t09e_the_again_text_and_the_reraise_clock(t) -> void:
	if not _api(t):
		return
	var cfg := {"dome.lean.base": 0.6}
	for days in [29, 30]:
		var v := _vw(3, 0, 9, cfg)
		var w = v.w
		w.council.raised_ever["dome"] = true
		w.council.set_aside["dome"] = {"sol": 15, "hard": false}
		w.council.last_session_sol = 0
		var n := 15 + int(days)
		_meet(w, n, [v.yes[0], v.yes[1], v.yes[2], v.neu[0], v.neu[1]])
		if days == 29:
			t.check(w.council.open == null and not ("council_proposal_again" in _kinds(w)), "29 sols after a set-aside: not raised")
		else:
			t.eq(_kinds(w), ["council_proposal_again"], "30 sols: raised again")
			t.eq(str(_last_line(w).text), _fmt(_dt("proposal_again"), {"a": "N%d" % v.yes[0], "place": _place("habitat")}), "with the again text")
			t.check(bool(_cs(w).proposals.back().again), "and the proposals entry says again")
	# after a hard set-aside: no re-raise while the hard share is still at least 0.5, even after 30 sols
	var vh := _vw(3, 0, 9, cfg)
	var wh = vh.w
	wh.council.raised_ever["dome"] = true
	wh.council.set_aside["dome"] = {"sol": 15, "hard": true}
	wh.council.last_session_sol = 0
	wh.council.hard_win = _hard_entries(9, 0)
	_meet(wh, 60, [vh.yes[0], vh.yes[1], vh.yes[2], vh.neu[0], vh.neu[1]])
	t.check(wh.council.open == null, "a hard set-aside is not raised again in the same crisis")
	# and when the hard share has fallen below 0.5 it is
	var vc := _vw(3, 0, 9, cfg)
	var wc = vc.w
	wc.council.raised_ever["dome"] = true
	wc.council.set_aside["dome"] = {"sol": 15, "hard": true}
	wc.council.last_session_sol = 0
	wc.council.hard_win = _hard_entries(3, 6)
	_meet(wc, 60, [vc.yes[0], vc.yes[1], vc.yes[2], vc.neu[0], vc.neu[1]])
	t.check(wc.council.open != null, "with the hard share under 0.5 it is raised again")
	_end(t)


# ================================================================ 10. votes

func _being(w, id: int) -> Variant:
	for b in w.beings:
		if b.id == id:
			return b
	return null


func _set_traits(w, id: int, traits: Dictionary) -> void:
	var b = _being(w, id)
	for k in traits:
		b.persona.traits[k] = traits[k]


## The meeting that raises the dome (sol 45, the room is the first `k` ids of `room_ids`), then nothing else.
func _raise(w, room_ids: Array) -> void:
	_meet(w, 45, room_ids)


func _open(w) -> Dictionary:
	return w.council.open if w.council.open != null else {}


func test_t10a_counts_are_exact_at_the_carry_and_reject_lines(t) -> void:
	if not _api(t):
		return
	var v := _vw(6, 4, 0)
	var w = v.w
	_raise(w, v.yes)
	t.eq(_kinds(w), ["council_proposal"], "staging: raised")
	_meet(w, 50, v.yes)
	t.eq(int(_open(w).get("carry_run", -1)), 1, "6 of 10 is 0.6: the vote carries")
	t.eq(int(_open(w).get("reject_run", -1)), 0, "and does not reject")
	t.eq(int(_open(w).get("votes", -1)), 1, "one vote counted")
	var v2 := _vw(5, 5, 0)
	var w2 = v2.w
	_raise(w2, v2.yes)
	_meet(w2, 50, v2.yes)
	t.eq(int(_open(w2).get("carry_run", -1)), 0, "5 of 10 does not carry")
	t.eq(int(_open(w2).get("reject_run", -1)), 1, "and 5 no of 10 is 0.5: it rejects")
	var rec: Dictionary = _cs(w2).session_log.back()
	t.check(int(rec.yes) == 5 and int(rec.no) == 5, "session_log holds the counts")
	_end(t)


## Carry of one vote at 100 voices (yes, no, undecided = the rest): returns carry_run after the first vote.
func _carry_after_vote(t, yes: int, no: int, cfg_edit: Dictionary = {}) -> int:
	var v := _vw(maxi(yes, 1), no, 100 - maxi(yes, 1) - no, _nosize(cfg_edit))
	var w = v.w
	_raise(w, v.all)
	if yes == 0:  # nobody leaning yes at the vote: the one proposer turns neutral
		var c := float(_ccfg(w).dome.lean.trait_centre)
		_set_traits(w, v.yes[0], {"drive": c, "curiosity": c, "restless": c, "steady": c, "care": c})
	_meet(w, 50, v.all)
	return int(_open(w).get("carry_run", -1))


## 100 voices would switch the size term on; the carry cases stage the shares alone.
func _nosize(cfg_edit: Dictionary = {}) -> Dictionary:
	var e := cfg_edit.duplicate()
	e["dome.cond.size_from"] = 1000
	return e


func test_t10a2_carry_counts_those_with_a_view_and_needs_a_quorum(t) -> void:
	if not _api(t):
		return
	t.eq(_carry_after_vote(t, 36, 24), 1, "36 yes, 24 no of 100: ratio 0.6, share 0.36: carries")
	t.eq(_carry_after_vote(t, 36, 25), 0, "36 yes, 25 no: ratio 0.590 under 0.6: does not carry")
	t.eq(_carry_after_vote(t, 34, 1), 0, "34 yes, 1 no: share 0.34 under the quorum 0.35: does not carry")
	t.eq(_carry_after_vote(t, 35, 1), 1, "35 yes, 1 no: share 0.35 exactly (CMP_EPS): carries")
	t.eq(_carry_after_vote(t, 0, 0), 0, "no yes and no no: never carries, and no division by zero")
	t.eq(_carry_after_vote(t, 40, 12), 1, "40 yes, 12 no, 48 undecided: carries (the old rule would not)")
	_end(t)


func test_t10a3_an_undecided_heavy_colony_pledges_at_the_second_vote(t) -> void:
	if not _api(t):
		return
	var v := _vw(40, 12, 48, _nosize())
	var w = v.w
	var room: Array = v.yes + v.no
	_raise(w, room)
	_meet(w, 50, room)
	t.eq(int(_open(w).get("carry_run", -1)), 1, "first vote carries")
	t.check(not w.council.pledged.has("dome"), "not yet pledged")
	_meet(w, 55, room)
	t.check(w.council.pledged.has("dome") and int(w.council.pledged["dome"]) == 55, "second vote pledges at sol 55")
	_end(t)


func test_t10a4_the_reject_step_ignores_the_quorum(t) -> void:
	if not _api(t):
		return
	var v := _vw(40, 50, 10, _nosize())
	var w = v.w
	var room: Array = v.yes + v.no
	_raise(w, room)
	_meet(w, 50, room)
	t.eq(int(_open(w).get("reject_run", -1)), 1, "50 no of 100 rejects whatever the yes share")
	t.eq(int(_open(w).get("carry_run", -1)), 0, "40 yes of 90 with a view is 0.44: no carry")
	_meet(w, 55, room)
	t.check(w.council.set_aside.has("dome"), "two rejecting votes set the dome aside")
	_end(t)



func test_t10b_a_carrying_vote_then_a_failing_one_resets_the_run(t) -> void:
	if not _api(t):
		return
	var v := _vw(6, 4, 0)
	var w = v.w
	_raise(w, v.yes)
	_meet(w, 50, v.yes)
	t.eq(int(_open(w).carry_run), 1, "run 1")
	_set_traits(w, v.yes[0], {"drive": 0.5, "curiosity": 0.5, "restless": 0.5, "steady": 0.9, "care": 0.9})
	_meet(w, 55, v.yes)
	t.eq(int(_open(w).carry_run), 0, "five yes of ten: the run is reset")
	t.check(not w.council.pledged.has("dome"), "no pledge")
	_set_traits(w, v.yes[0], {"drive": 0.9, "curiosity": 0.9, "restless": 0.9, "steady": 0.5, "care": 0.5})
	_meet(w, 60, v.yes)
	t.eq(int(_open(w).carry_run), 1, "carrying again: run 1")
	t.check(not w.council.pledged.has("dome"), "still no pledge")
	_meet(w, 65, v.yes)
	t.check(w.council.pledged.has("dome") and int(w.council.pledged["dome"]) == 65, "two in a row pledge, at sol 65")
	_end(t)


func test_t10c_two_rejecting_votes_set_the_dome_aside(t) -> void:
	if not _api(t):
		return
	var v := _vw(2, 8, 0)
	var w = v.w
	_raise(w, v.all.slice(0, 5))
	_meet(w, 50, v.all.slice(0, 5))
	t.check(w.council.open != null, "one rejecting vote is not enough")
	_meet(w, 55, v.all.slice(0, 5))
	t.check(w.council.open == null, "two close it")
	t.eq(_kinds(w), ["council_proposal", "council_set_aside"], "the plain set-aside line")
	t.eq(str(_last_line(w).text), _fmt(_dt("set_aside"), {"b": "N%d" % v.no[0]}), "naming the no speaker (equal stance, no friends: the lowest id)")
	t.eq(int(_last_line(w).being_id), int(v.no[0]), "being_id is the no speaker")
	var p: Dictionary = _cs(w).proposals[0]
	t.check(str(p.outcome) == "set_aside" and int(p.outcome_sol) == 55, "proposals: outcome set_aside at 55")
	t.check(int(w.council.set_aside["dome"].sol) == 55 and not bool(w.council.set_aside["dome"].hard), "set_aside record, not hard")
	_end(t)


func _hard_set_aside(entries: Array) -> Dictionary:
	var v := _vw(2, 8, 0)
	var w = v.w
	_raise(w, v.all.slice(0, 5))
	w.council.hard_win = entries.duplicate(true)
	_meet(w, 50, v.all.slice(0, 5))
	w.council.hard_win = entries.duplicate(true)
	_meet(w, 55, v.all.slice(0, 5))
	return {"w": w, "v": v}


func test_t10d_the_hard_set_aside_names_the_clause(t) -> void:
	if not _api(t):
		return
	var r := _hard_set_aside(_hard_entries(9, 0))
	var w = r.w
	t.eq(_kinds(w), ["council_proposal", "council_set_aside_hard"], "hard share 0.9: the hard text")
	t.eq(str(_last_line(w).text), _fmt(_dt("set_aside_hard"), {"clause": _clause("ice")}), "with the ice phrase")
	t.check(bool(w.council.set_aside["dome"].hard), "the record is hard")
	t.check(bool(_cs(w).proposals[0].hard), "and so is the proposals entry")
	# a single hard sol in a calm window gives the plain text
	var r2 := _hard_set_aside(_hard_entries(1, 8))
	t.eq(_kinds(r2.w), ["council_proposal", "council_set_aside"], "one hard sol of ten: the plain text, naming the no speaker")
	# clause choice: the failing clause with the most sols; ties ice, air, food
	var air: Array = []
	for i in 5:
		air.append({"hard": true, "ice": false, "air": true, "food": false})
	var mixed: Array = _hard_entries(4, 0) + air
	t.eq(str(_last_line(_hard_set_aside(mixed).w).text), _fmt(_dt("set_aside_hard"), {"clause": _clause("air")}), "air failing on 5 sols beats ice on 4")
	var food: Array = []
	for i in 6:
		food.append({"hard": true, "ice": false, "air": false, "food": true})
	t.eq(str(_last_line(_hard_set_aside(food).w).text), _fmt(_dt("set_aside_hard"), {"clause": _clause("food")}), "food alone")
	var tie: Array = _hard_entries(3, 0) + air.slice(0, 3) + food.slice(0, 3)
	t.eq(str(_last_line(_hard_set_aside(tie).w).text), _fmt(_dt("set_aside_hard"), {"clause": _clause("ice")}), "a three-way tie: ice")
	var tie2: Array = air.slice(0, 3) + food.slice(0, 3)
	t.eq(str(_last_line(_hard_set_aside(tie2).w).text), _fmt(_dt("set_aside_hard"), {"clause": _clause("air")}), "air and food tied: air")
	_end(t)


## A divided council: 3 yes (ids 1 to 3), 3 no (4 to 6) and 4 undecided; runs the raise (45) and the first vote (50).
func _divided_world(edits: Dictionary = {}) -> Dictionary:
	var v := _vw(3, 3, 4, edits)
	v["room"] = v.yes + v.neu.slice(0, 2)
	_raise(v.w, v.room)
	return v


func test_t10e_twelve_open_votes_let_the_dome_rest(t) -> void:
	if not _api(t):
		return
	var v := _divided_world()
	var w = v.w
	for i in 11:
		_meet(w, 50 + 5 * i, v.room)
	t.check(w.council.open != null and int(w.council.open.votes) == 11, "after 11 votes the talk goes on")
	t.eq(_cs(w).proposals[0].outcome, null, "no outcome yet")
	_meet(w, 105, v.room)
	t.check(w.council.open == null, "the 12th vote closes it")
	t.eq(str(_last_line(w).kind), "council_set_aside_long", "with the rest line")
	t.eq(str(_last_line(w).text), _dt("set_aside_long"), "its text")
	t.check(int(w.council.set_aside["dome"].sol) == 105 and not bool(w.council.set_aside["dome"].hard), "set_aside record at 105, not hard")
	t.eq(str(_cs(w).proposals[0].outcome), "set_aside", "outcome set_aside")
	var nd := 0
	for k in _kinds(w):
		if k == "council_divided":
			nd += 1
	t.eq(nd, 1, "the divided line was offered once in the proposal")
	_end(t)


func test_t10f_divided_names_both_speakers_with_their_reasons(t) -> void:
	if not _api(t):
		return
	var v := _divided_world()
	var w = v.w
	_friend(w, v.yes[0], v.yes[1])
	_friend(w, v.yes[1], v.yes[2])
	_friend(w, v.no[0], v.no[1])
	_friend(w, v.no[1], v.no[2])
	_meet(w, 50, v.room)
	t.eq(_kinds(w), ["council_proposal", "council_divided"], "the divided line at the first vote")
	var e: Dictionary = _last_line(w)
	t.eq(int(e.being_id), int(v.yes[1]), "the yes speaker has the most friends inside the yes camp")
	t.eq(int(e.other_id), int(v.no[1]), "the no speaker likewise")
	var want := _fmt(_dt("divided"), {"a": "N%d" % v.yes[1], "b": "N%d" % v.no[1],
			"ra": _yes_reason("personal", "driven"), "rb": _no_reason("personal", "nurturing")})
	t.eq(str(e.text), want, "text: personal reasons with the top adjective of each camp (ties in persona.dims order)")
	_meet(w, 55, v.room)
	t.eq(_kinds(w), ["council_proposal", "council_divided"], "offered once")
	_end(t)


func _divided_names(w, v: Dictionary) -> Array:
	_meet(w, 50, v.room)
	var e := _last_line(w)
	if str(e.get("kind", "")) != "council_divided":
		return [-1, -1]
	return [int(e.being_id), int(e.other_id)]


func test_t10g_speaker_ties(t) -> void:
	if not _api(t):
		return
	var v := _divided_world()
	t.eq(_divided_names(v.w, v), [v.yes[0], v.no[0]], "all equal, no friends: the lower id in each camp")
	var v2 := _divided_world()
	_set_traits(v2.w, v2.yes[2], {"drive": 1.0, "curiosity": 1.0, "restless": 1.0})
	_set_traits(v2.w, v2.no[2], {"steady": 1.0, "care": 1.0})
	t.eq(_divided_names(v2.w, v2), [v2.yes[2], v2.no[2]], "equal friend counts: the higher yes stance, the lower no stance")
	var v3 := _divided_world()
	_set_traits(v3.w, v3.yes[2], {"drive": 1.0, "curiosity": 1.0, "restless": 1.0})
	_set_traits(v3.w, v3.no[2], {"steady": 1.0, "care": 1.0})
	_friend(v3.w, v3.yes[0], v3.yes[1])
	_friend(v3.w, v3.no[0], v3.no[1])
	t.eq(_divided_names(v3.w, v3), [v3.yes[0], v3.no[0]], "the friend count in the camp beats stance; the tie between the two friends goes to the lower id")
	_end(t)


func test_t10h_the_no_reason_is_the_hard_clause_when_hardship_dominates(t) -> void:
	if not _api(t):
		return
	var v := _divided_world({"dome.lean.base": 0.3})
	var w = v.w
	w.council.hard_win = _hard_entries(9, 0)
	_meet(w, 50, v.room)
	var e: Dictionary = _last_line(w)
	t.eq(str(e.kind), "council_divided", "staging: a divided line at the first vote")
	t.eq(int(e.other_id), int(v.no[0]), "the no speaker")
	var want := _fmt(_dt("divided"), {"a": "N%d" % v.yes[0], "b": "N%d" % v.no[0],
			"ra": _yes_reason("personal", "driven"), "rb": _no_reason("hard", "", _clause("ice"))})
	t.eq(str(e.text), want, "the no speaker's largest term is hardship: the clause phrase")
	_end(t)


func test_t10i_the_yes_reason_is_size_when_size_is_the_largest_term(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var neu := _voices(w, 89)
	var no := _voices(w, 31, NO)
	var kid = _voice(w, {}, neu[0], 40.0)  # born at sol 40: a living child of the first voice, not a voice itself
	_calm(w)
	_settle(w, 10)
	_council(w, 40)
	_raise(w, neu.slice(0, 12))
	t.eq(_kinds(w), ["council_proposal"], "staging: raised by the voice with the child (the highest stance)")
	t.eq(int(_last_line(w).being_id), int(neu[0]), "staging: the proposer")
	_meet(w, 50, neu.slice(0, 12))
	var e: Dictionary = _last_line(w)
	t.eq(str(e.kind), "council_divided", "89 yes and 31 no of 120: divided")
	t.eq(int(e.being_id), int(neu[0]), "the yes speaker")
	t.eq(int(e.other_id), int(no[0]), "the no speaker")
	t.eq(str(e.text), _fmt(_dt("divided"), {"a": "N%d" % neu[0], "b": "N%d" % no[0],
			"ra": _yes_reason("size"), "rb": _no_reason("personal", "nurturing")}),
			"size and child equal at 0.15: the tie order gives size")
	_end(t)


func _friends_world(strong_friends_lean_negative: bool) -> Dictionary:
	var w = _world()
	var s = _voice(w, {"steady": 0.8, "care": 0.8} if strong_friends_lean_negative else {})
	var f1 = _voice(w, {"drive": 1.0, "curiosity": 1.0, "restless": 1.0, "steady": 0.0, "care": 0.0} if strong_friends_lean_negative else YES)
	var f2 = _voice(w, {"drive": 1.0, "curiosity": 1.0, "restless": 1.0, "steady": 0.0, "care": 0.0} if strong_friends_lean_negative else YES)
	var no := _voices(w, 3, NO)
	var neu := _voices(w, 4)
	_calm(w)
	_settle(w, 10)
	_council(w, 40)
	_friend(w, s.id, f1.id)
	_friend(w, s.id, f2.id)
	return {"w": w, "s": s.id, "f": [f1.id, f2.id], "no": no, "neu": neu}


func test_t10j_friends_is_the_reason_inside_the_band_and_across_zero(t) -> void:
	if not _api(t):
		return
	# a lean of exactly yes_above is inside the band: stance comes from friends
	var r := _friends_world(false)
	var w = r.w
	_ccfg(w).dome.lean.base = 0.1
	var room: Array = [r.f[0], r.f[1], r.no[0], r.no[1], r.no[2]]
	_raise(w, room)
	t.eq(_kinds(w), ["council_proposal"], "staging: raised")
	_meet(w, 50, room)
	var e: Dictionary = _last_line(w)
	t.eq(str(e.kind), "council_divided", "staging: divided at the first vote")
	t.eq(int(e.being_id), int(r.s), "staging: the voice with two friends in the yes camp speaks")
	t.near(float(w.council.lean_of(r.s)), 0.1, CMP, "staging: its lean is exactly yes_above")
	t.check(float(w.council.stance_of(r.s)) > 0.1, "staging: its stance is yes")
	t.eq(str(e.text), _fmt(_dt("divided"), {"a": "N%d" % r.s, "b": "N%d" % r.no[0],
			"ra": _yes_reason("friends"), "rb": _no_reason("personal", "nurturing")}), "'as their friends do'")
	# a negative lean with a positive stance
	var r2 := _friends_world(true)
	var w2 = r2.w
	var room2: Array = [r2.f[0], r2.f[1], r2.neu[0], r2.neu[1], r2.neu[2]]
	_raise(w2, room2)
	t.eq(_kinds(w2), ["council_proposal"], "staging 2: raised")
	_meet(w2, 50, room2)
	t.check(not ("council_divided" in _kinds(w2)), "staging 2: not divided yet at 50 (the speaker's friends have not moved it past yes)")
	_meet(w2, 55, room2)
	t.check(float(w2.council.lean_of(r2.s)) < float(_ccfg(w2).support.no_below), "staging 2: lean below the band")
	t.check(float(w2.council.stance_of(r2.s)) > float(_ccfg(w2).support.yes_above), "staging 2: stance above it")
	var e2: Dictionary = _last_line(w2)
	t.eq(str(e2.kind), "council_divided", "divided at the second vote")
	t.eq(int(e2.being_id), int(r2.s), "by the voice whose friends carried it")
	t.eq(str(e2.text), _fmt(_dt("divided"), {"a": "N%d" % r2.s, "b": "N%d" % r2.no[0],
			"ra": _yes_reason("friends"), "rb": _no_reason("personal", "nurturing")}), "the sign differs: 'as their friends do'")
	_end(t)


func test_t10k_the_personal_fallback_when_no_term_is_positive(t) -> void:
	if not _api(t):
		return
	var v := _vw(0, 0, 10, {"dome.lean.base": 0.3})
	var w = v.w
	_raise(w, v.all.slice(0, 5))
	t.eq(_kinds(w), ["council_proposal"], "staging: raised")
	_meet(w, 50, v.all.slice(0, 5), GREEN)
	t.eq(int(_open(w).get("carry_run", 0)), 1, "staging: a carrying vote")
	_meet(w, 55, v.all.slice(0, 5), GREEN)
	t.check(w.council.pledged.has("dome"), "pledged")
	var e: Dictionary = _last_line(w)
	t.eq(str(e.kind), "council_pledge", "the pledge line")
	t.eq(str(e.text), _fmt(_dt("pledge"), {"a": "N%d" % v.all[0], "place": _place("green_room"), "why": _dt("pledge_why_personal")}),
			"every term is zero, the base lifts the lean: the reason is personal")
	t.eq(str(_cs(w).proposals[0].reason), "personal", "stored in the proposals entry")
	_end(t)


# ================================================================ 11. pledge and after

## Raise at 45, votes at 50 and 55 (room = `room`): a pledge at sol 55 when the shares carry.
func _to_pledge(w, room: Array) -> void:
	_raise(w, room)
	_meet(w, 50, room)
	_meet(w, 55, room)


func _means_world() -> Dictionary:
	var v := _vw(0, 0, 10, {"dome.lean.base": 0.1})
	v.w.colony.regolith = v.w.colony.regolith_target()
	return v


func test_t11a_the_pledge_sets_its_record_and_blocks_a_further_raise(t) -> void:
	if not _api(t):
		return
	var v := _means_world()
	var w = v.w
	_to_pledge(w, v.all.slice(0, 5))
	t.eq(_kinds(w), ["council_proposal", "council_pledge"], "a raise and a pledge")
	t.eq(int(w.council.pledged.get("dome", -1)), 55, "pledged at sol 55")
	t.eq(_cs(w).pledge_sol, 55, "stats pledge_sol")
	t.check(w.council.open == null, "the proposal is closed")
	var p: Dictionary = _cs(w).proposals[0]
	t.check(str(p.outcome) == "pledged" and int(p.outcome_sol) == 55, "proposals: pledged at 55")
	t.eq(str(p.reason), "means", "reason: the largest mean term over the yes voices (stone in store)")
	t.eq(_cs(w).chapters.size(), 1, "one chapter")
	var ch: Dictionary = _cs(w).chapters[0]
	t.check(str(ch.kind) == "pledge" and str(ch.topic) == "dome" and int(ch.sol) == 55, "its kind, topic and sol")
	t.check(str(ch.text).begins_with("The council has agreed to build a dome."), "its text starts with the fixed first sentence")
	t.check(ch.has("t") and ch.has("clock_sol"), "t and clock_sol")
	_meet(w, 60, v.all.slice(0, 5))
	_meet(w, 65, v.all.slice(0, 5))
	t.eq(_cs(w).proposals.size(), 1, "no further raise")
	t.check(w.council.open == null, "nothing open")
	t.eq(_cs(w).chapters.size(), 1, "still one chapter")
	_end(t)


func test_t11b_the_pledge_line_names_proposer_place_and_reason(t) -> void:
	if not _api(t):
		return
	var v := _means_world()
	var w = v.w
	_raise(w, v.all.slice(0, 5))
	_meet(w, 50, v.all.slice(0, 5))
	_meet(w, 55, v.all.slice(5, 10), GREEN)
	var e: Dictionary = _last_line(w)
	t.eq(str(e.kind), "council_pledge", "the pledge line")
	t.eq(str(e.text), _fmt(_dt("pledge"), {"a": "N%d" % v.all[0], "place": _place("green_room"), "why": _yes_reason("means")}),
			"the proposer of the first meeting, the place of the pledging meeting, the means reason")
	t.eq(int(e.being_id), int(v.all[0]), "being_id is the proposer")
	t.eq(int(e.building_id), GREEN, "building_id is the pledging room")
	t.eq(str(e.topic), "dome", "topic")
	_end(t)


func test_t11c_the_divided_pledge_text(t) -> void:
	if not _api(t):
		return
	var v := _vw(6, 3, 1)
	var w = v.w
	_to_pledge(w, v.yes)
	t.eq(_kinds(w), ["council_proposal", "council_divided", "council_pledge"], "raise, divided, pledge")
	t.eq(str(_last_line(w).text), _fmt(_dt("pledge_divided"), {"a": "N%d" % v.yes[0], "place": _place("habitat"), "why": _dt("pledge_why_personal")}),
			"the divided variant, with the personal reason (the yes voices' largest term is the personal one)")
	t.eq(int(_cs(w).lines.get("pledge_divided", 0)), 1, "counted under its own lines key")
	t.eq(int(_cs(w).lines.get("pledge", 0)), 0, "and not under the plain pledge key")
	_end(t)


func test_t11d_a_dropped_divided_line_still_marks_the_pledge(t) -> void:
	if not _api(t):
		return
	var v := _vw(7, 2, 1)
	var w = v.w
	_raise(w, v.yes)
	_meet(w, 50, v.yes)
	t.eq(_kinds(w), ["council_proposal"], "staging: 7 yes and 2 no of 10 is not divided at the first vote")
	_set_traits(w, v.neu[0], NO)
	_meet(w, 55, v.yes)
	t.eq(_kinds(w), ["council_proposal", "council_pledge"], "divided and pledge on one boundary: only the pledge is logged")
	t.eq(str(_last_line(w).text), _fmt(_dt("pledge_divided"), {"a": "N%d" % v.yes[0], "place": _place("habitat"), "why": _dt("pledge_why_personal")}),
			"and it is the divided variant")
	t.eq(int(_cs(w).lines.get("pledge_divided", 0)), 1, "the dropped-divided pledge is counted as pledge_divided")
	t.eq(int(_cs(w).lines_dropped), 1, "the dropped line is counted")
	_end(t)


func test_t11e_the_pledge_survives_a_fall_back_and_a_reentry(t) -> void:
	if not _api(t):
		return
	var v := _means_world()
	var w = v.w
	_to_pledge(w, v.all.slice(0, 5))
	w.ages.age = "landing"
	w.stats.age = "landing"
	_bnd(w, 60)
	t.check(w.council.pledged.has("dome"), "a fall-back to Landing leaves the pledge")
	_settle(w, 61, "settled_again")
	w.ages.enter_age(w, "council", "council_again", "Again.")
	w.council.last_session_sol = 61
	_meet(w, 66, v.all.slice(0, 5))
	_meet(w, 71, v.all.slice(0, 5))
	t.check(w.council.pledged.has("dome") and w.council.open == null, "and a re-entry")
	t.eq(_cs(w).proposals.size(), 1, "the dome is not raised again")
	t.eq(_cs(w).chapters.size(), 1, "no second chapter")
	_end(t)


## Pledge world with a divided council: yes 1 to 6, no 7 to 9 (the no speaker is 7), neutral 10. Pledged at sol 55.
func _aftermath_world() -> Dictionary:
	var v := _vw(6, 3, 1)
	_to_pledge(v.w, v.yes)
	return v


func test_t11f_aftermath_after_four_sols_still_or_come_round(t) -> void:
	if not _api(t):
		return
	var v := _aftermath_world()
	var w = v.w
	var d: int = v.no[0]
	t.check(w.council.aftermath != null and int(w.council.aftermath.doubter_id) == d and int(w.council.aftermath.due_sol) == 59,
			"staging: the doubter is the no speaker, due at sol 59")
	var n0 := _clines(w).size()
	_bnd(w, 58)
	t.eq(_clines(w).size(), n0, "nothing before the due sol")
	_bnd(w, 59)
	t.eq(str(_last_line(w).kind), "council_aftermath", "the aftermath line at the due sol")
	t.eq(str(_last_line(w).text), _fmt(_dt("aftermath_still"), {"b": "N%d" % d}), "the doubter still says not yet")
	t.eq(int(_last_line(w).being_id), d, "being_id is the doubter")
	t.check(w.council.aftermath == null, "evaluated once, then cleared")
	_bnd(w, 60)
	_bnd(w, 61)
	t.eq(_clines(w).size(), n0 + 1, "never repeated")
	# come round
	var v2 := _aftermath_world()
	var w2 = v2.w
	_set_traits(w2, v2.no[0], {"drive": 0.9, "curiosity": 0.9, "restless": 0.9, "steady": 0.5, "care": 0.5})
	_bnd(w2, 59)
	t.eq(str(_last_line(w2).text), _fmt(_dt("aftermath_round"), {"b": "N%d" % v2.no[0]}), "a doubter whose stance is now yes has come round")
	# evaluated at the first boundary at or after the due sol
	var v3 := _aftermath_world()
	_bnd(v3.w, 62)
	t.eq(str(_last_line(v3.w).kind), "council_aftermath", "a late boundary (62) still gives the line")
	_end(t)


func test_t11g_no_aftermath_when_the_doubter_is_gone_or_the_age_changed(t) -> void:
	if not _api(t):
		return
	var v := _aftermath_world()
	var w = v.w
	w._kill(_being(w, v.no[0]), "other")
	var n0 := _clines(w).size()
	_bnd(w, 59)
	t.eq(_clines(w).size(), n0, "the doubter is dead: no line")
	t.check(w.council.aftermath == null, "and nothing is kept")
	var v2 := _aftermath_world()
	var w2 = v2.w
	var m0 := _clines(w2).size()
	w2.ages.enter_age(w2, "settlement", "council_split", "Split.")
	_bnd(w2, 59)
	t.eq(_clines(w2).size(), m0, "the colony has left Council at the due sol: no line")
	w2.ages.enter_age(w2, "council", "council_again", "Again.")
	_bnd(w2, 61)
	_bnd(w2, 65)
	t.eq(_clines(w2).size(), m0, "and it is not retried once the Council is back")
	_end(t)


func test_t11h_the_doubter_fallback(t) -> void:
	if not _api(t):
		return
	# no divided line: no speaker was recorded, so the lowest-stance no voice at the pledging vote
	var v := _vw(7, 2, 1)
	var w = v.w
	_set_traits(w, v.no[1], {"steady": 1.0, "care": 1.0})
	_to_pledge(w, v.yes)
	t.check(w.council.aftermath != null and int(w.council.aftermath.doubter_id) == int(v.no[1]), "the lowest stance among the no voices")
	_bnd(w, 59)
	t.eq(str(_last_line(w).text), _fmt(_dt("aftermath_still"), {"b": "N%d" % v.no[1]}), "named in the line")
	# equal stances: the lower id
	var v2 := _vw(7, 2, 1)
	_to_pledge(v2.w, v2.yes)
	t.check(v2.w.council.aftermath != null and int(v2.w.council.aftermath.doubter_id) == int(v2.no[0]), "equal stances: the lower id")
	# the recorded no speaker has died before the pledge: the fallback applies
	var v3 := _vw(6, 3, 1)
	var w3 = v3.w
	_raise(w3, v3.yes)
	_meet(w3, 50, v3.yes)
	t.eq(_kinds(w3), ["council_proposal", "council_divided"], "staging: divided, no speaker is the first no voice")
	w3._kill(_being(w3, v3.no[0]), "other")
	_meet(w3, 55, v3.yes)
	t.check(w3.council.pledged.has("dome"), "staging: pledged")
	t.check(w3.council.aftermath != null and int(w3.council.aftermath.doubter_id) == int(v3.no[1]), "the next no voice by stance, then id")
	# no no voice at all: no aftermath
	var v4 := _vw(6, 0, 4)
	_to_pledge(v4.w, v4.yes)
	t.check(v4.w.council.pledged.has("dome"), "staging: pledged")
	t.check(v4.w.council.aftermath == null, "no no voice at the pledging vote: no aftermath")
	var n0 := _clines(v4.w).size()
	_bnd(v4.w, 59)
	t.eq(_clines(v4.w).size(), n0, "and no line")
	_end(t)


func test_t11i_the_after_pledge_line_comes_once(t) -> void:
	if not _api(t):
		return
	var v := _aftermath_world()
	var w = v.w
	_bnd(w, 59)
	_meet(w, 80, v.yes)
	t.check(not ("council_after_pledge" in _kinds(w)), "25 sols after the pledge: not yet")
	_meet(w, 85, v.yes)
	t.eq(str(_last_line(w).kind), "council_after_pledge", "the first meeting 30 sols after the pledge")
	t.eq(str(_last_line(w).text), _dt("after_pledge"), "its text")
	_meet(w, 90, v.yes)
	_meet(w, 95, v.yes)
	var n := 0
	for k in _kinds(w):
		if k == "council_after_pledge":
			n += 1
	t.eq(n, 1, "once in the run")
	_end(t)


# ================================================================ 12. lapse

func test_t12a_a_split_with_a_proposal_open_lapses_it(t) -> void:
	if not _api(t):
		return
	var v := _vw(6, 0, 4)
	var w = v.w
	_raise(w, v.yes)
	t.check(w.council.open != null, "staging: open")
	w.council.trust_win = []
	for i in 19:
		w.council.trust_win.append(0.1)
	_bnd(w, 60)
	t.eq(str(w.stats.age), "settlement", "staging: the Council split at sol 60")
	t.check(w.council.open == null, "the proposal is gone")
	t.eq(_cs(w).proposals[0].outcome, "lapsed", "outcome lapsed")
	t.eq(_kinds(w), ["council_proposal"], "no Council line for it")
	t.check(not w.council.set_aside.has("dome"), "set_aside is unchanged")
	# the next term raises it with the again text
	_settle(w, 61, "settled_again")
	w.ages.enter_age(w, "council", "council_again", "Again.")
	w.council.last_session_sol = 61
	w.council.quiet_logged = false
	_meet(w, 66, v.yes)
	t.eq(str(_last_line(w).kind), "council_proposal_again", "the again text at the first meeting of the next term")
	_end(t)


func test_t12b_a_fall_back_with_a_proposal_open_lapses_it(t) -> void:
	if not _api(t):
		return
	var v := _vw(6, 0, 4)
	var w = v.w
	_raise(w, v.yes)
	w.ages.age = "landing"
	w.stats.age = "landing"
	_bnd(w, 50)
	t.check(w.council.open == null, "the proposal is gone")
	t.eq(_cs(w).proposals[0].outcome, "lapsed", "outcome lapsed")
	t.eq(_kinds(w), ["council_proposal"], "no Council line")
	t.check(not w.council.set_aside.has("dome"), "set_aside is unchanged")
	_end(t)


# ================================================================ 13. circles family

func _circles_world(voices: int) -> Variant:
	var w = _world()
	_voices(w, voices)
	_calm(w)
	_settle(w, 10)
	return w


func _circle_lines(w) -> Array:
	var out: Array = []
	for e in w.log:
		if str(e.kind) == "council_circles":
			out.append(e)
	return out


func test_t13a_the_first_line_comes_fifty_sols_into_settlement(t) -> void:
	if not _api(t):
		return
	var w = _circles_world(14)
	_bnd(w, 59)
	t.eq(_circle_lines(w).size(), 0, "49 sols into Settlement: nothing")
	_bnd(w, 60)
	t.eq(_circle_lines(w).size(), 1, "50 sols: the first circles line")
	t.eq(str(_circle_lines(w)[0].text), _tx("circles"), "plain text with 12 voices or more")
	var w2 = _circles_world(5)
	_bnd(w2, 60)
	t.eq(str(_circle_lines(w2)[0].text), _tx("circles_few"), "under 12 voices: circles_few")
	_end(t)


func test_t13b_the_second_line_comes_a_hundred_sols_later_and_no_third(t) -> void:
	if not _api(t):
		return
	var w = _circles_world(14)
	_bnd(w, 60)
	_bnd(w, 159)
	t.eq(_circle_lines(w).size(), 1, "99 sols after the first: still one")
	_bnd(w, 160)
	t.eq(_circle_lines(w).size(), 2, "100 sols after: the second")
	t.eq(str(_circle_lines(w)[1].text), _tx("circles_again"), "circles_again")
	_bnd(w, 300)
	_bnd(w, 500)
	t.eq(_circle_lines(w).size(), 2, "there is no third")
	var w2 = _circles_world(5)
	_bnd(w2, 60)
	_bnd(w2, 160)
	t.eq(str(_circle_lines(w2)[1].text), _tx("circles_few"), "the second line is circles_few when voices fail")
	_end(t)


func test_t13c_both_come_again_in_a_later_settlement_term(t) -> void:
	if not _api(t):
		return
	var w = _circles_world(14)
	_bnd(w, 60)
	_bnd(w, 160)
	t.eq(_circle_lines(w).size(), 2, "staging: two lines in the first term")
	_settle(w, 200, "settled_again")
	_bnd(w, 249)
	t.eq(_circle_lines(w).size(), 2, "49 sols into the next term: nothing")
	_bnd(w, 250)
	t.eq(_circle_lines(w).size(), 3, "50 sols: a first line again")
	t.eq(str(_circle_lines(w)[2].text), _tx("circles"), "with the first text")
	_bnd(w, 350)
	t.eq(_circle_lines(w).size(), 4, "and a second 100 sols later")
	t.eq(str(_circle_lines(w)[3].text), _tx("circles_again"), "with the again text")
	_end(t)


# ================================================================ 14. line cap

func test_t14a_the_higher_line_wins_and_the_lower_is_counted(t) -> void:
	if not _api(t):
		return
	var v := _vw(6, 3, 1, {"lines.after_pledge_sols": 4})
	var w = v.w
	_to_pledge(w, v.yes)
	t.eq(int(_cs(w).lines_dropped), 0, "staging: nothing dropped so far")
	_meet(w, 60, v.yes)
	t.eq(str(_last_line(w).kind), "council_after_pledge", "after-pledge outranks the aftermath on the same boundary")
	t.eq(int(_cs(w).lines_dropped), 1, "the aftermath is counted as dropped")
	_meet(w, 65, v.yes)
	_meet(w, 70, v.yes)
	var n := 0
	for k in _kinds(w):
		if k == "council_aftermath":
			n += 1
	t.eq(n, 0, "and it is not retried")
	t.check(w.council.aftermath == null, "cleared")
	_end(t)


func test_t14a2_the_full_priority_order_of_spec_7_4(t) -> void:
	if not _api(t):
		return
	var order := ["outcome", "divided", "raise", "quiet", "after_pledge", "aftermath", "circles"]
	var prio: Dictionary = Council.PRIO
	t.eq(prio.keys(), order, "the table lists the seven families in spec order")
	for i in order.size() - 1:
		t.check(int(prio[order[i]]) > int(prio[order[i + 1]]), "%s outranks %s" % [order[i], order[i + 1]])
	# every pair, offered low first and high first, through the real flush
	for i in order.size():
		for j in range(i + 1, order.size()):
			for flip in [false, true]:
				var v := _vw(6, 3, 1)
				var w = v.w
				var c = w.council
				var pair := [order[j], order[i]] if not flip else [order[i], order[j]]
				for k in pair:
					c._offer(int(prio[k]), "council_" + str(k), str(k), "text " + str(k), {})
				c._flush(w)
				t.eq(str(_last_line(w).kind), "council_" + order[i], "%s beats %s (flip %s)" % [order[i], order[j], flip])
				t.eq(int(_cs(w).lines_dropped), 1, "the loser is counted")
	_end(t)


func test_t14b_no_boundary_logs_two_council_lines(t) -> void:
	if not _api(t):
		return
	var v := _divided_world()
	var w = v.w
	for i in 12:
		_meet(w, 50 + 5 * i, v.room)
	var seen := {}
	var dup := false
	for e in _clines(w):
		if seen.has(int(e.sol)):
			dup = true
		seen[int(e.sol)] = true
	t.check(not dup, "one Council line per sol boundary over a whole proposal")
	t.check(_clines(w).size() >= 3, "staging: raise, divided and rest lines were logged")
	_end(t)


# ================================================================ 15. texts

func _all_strings(node: Variant, out: Array, path: String = "") -> void:
	if node is Dictionary:
		for k in node:
			_all_strings(node[k], out, path + "." + str(k))
	elif node is String:
		out.append([path, node])


## Every rendering of one template: placeholders replaced by every sample.
func _renders(tpl: String, d: Dictionary) -> Array:
	var outs: Array = [tpl]
	var subs := {"a": ["Lena"], "b": ["Omar"], "place": d.places, "clause": d.clauses, "adj": d.adjs,
			"ra": d.yes_reasons, "rb": d.no_reasons, "why": d.whys}
	for key in subs:
		var tag := "{%s}" % key
		var next: Array = []
		for s in outs:
			if tag in str(s):
				for r in subs[key]:
					next.append(str(s).replace(tag, str(r)))
			else:
				next.append(s)
		outs = next
	return outs


func test_t15_texts_have_no_numbers_and_no_banned_words(t) -> void:
	if not _api(t):
		return
	var cd := _cd()
	var pd: Dictionary = SimData.load_json("persona.json")
	var ad: Dictionary = SimData.load_json("ages.json")
	var places: Array = []
	for k in cd.text.place:
		places.append(str(cd.text.place[k]))
	var clauses: Array = []
	for k in cd.text.clause:
		clauses.append(str(cd.text.clause[k]))
	var adjs: Array = []
	for k in pd.adjectives:
		adjs.append(str(pd.adjectives[k]))
	var yes_r: Array = []
	var no_r: Array = []
	var base := {"places": places, "clauses": clauses, "adjs": adjs, "yes_reasons": [], "no_reasons": [], "whys": []}
	for k in cd.dome.text.reason.yes:
		yes_r += _renders(str(cd.dome.text.reason.yes[k]), base)
	for k in cd.dome.text.reason.no:
		no_r += _renders(str(cd.dome.text.reason.no[k]), base)
	var whys: Array = yes_r.duplicate()
	whys.append(str(cd.dome.text.pledge_why_personal))
	var d := {"places": places, "clauses": clauses, "adjs": adjs, "yes_reasons": yes_r, "no_reasons": no_r, "whys": whys}
	var strings: Array = []
	_all_strings(cd.text, strings, "text")
	_all_strings(cd.dome.text, strings, "dome.text")
	_all_strings(cd.age, strings, "age")
	t.check(strings.size() >= 40, "staging: the texts were collected (%d)" % strings.size())
	var banned := ["vote", "percent", "landing", "fail", "is building", "has built"]
	var bad: Array[String] = []
	var rendered := 0
	for pair in strings:
		for r in _renders(str(pair[1]), d):
			rendered += 1
			var s: String = r
			var low := s.to_lower()
			for ch in s:
				if ch >= "0" and ch <= "9":
					bad.append("%s has a digit: %s" % [pair[0], s])
					break
			if "%" in s:
				bad.append("%s has a %%: %s" % [pair[0], s])
			if "{" in s or "}" in s:
				bad.append("%s has an unfilled placeholder: %s" % [pair[0], s])
			for w in banned:
				if w in low:
					bad.append("%s contains '%s': %s" % [pair[0], w, s])
	t.check(rendered > strings.size(), "staging: templates rendered more than once")
	t.eq(bad.slice(0, 5), [], "no digit, no percent sign, no banned word, no stray placeholder")
	var seasons: Array = ad.season_phrases
	for sp in seasons:
		var low := str(sp).to_lower()
		for ch in str(sp):
			t.check(not (ch >= "0" and ch <= "9"), "season phrase has no digit")
			break
		t.check(not ("%" in str(sp)), "season phrase has no percent sign")
	for key in ["pledge", "pledge_divided"]:
		t.check(str(cd.dome.text[key]).begins_with("The council has agreed to build a dome."), key + " starts with the fixed first sentence")
	_end(t)


func test_t15b_a_council_log_line_is_the_data_text_exactly(t) -> void:
	if not _api(t):
		return
	var v := _vw(0, 0, 12)
	var w = v.w
	_meet(w, 45, v.all.slice(0, 6))
	t.eq(str(_last_line(w).text), _tx("quiet"), "a Council line is the data text exactly")
	_end(t)


# ================================================================ 16. purity

func _run_sols(w, n: int) -> void:
	while w.sol() < n:
		w.step()


func _override_entry(w) -> void:
	# Exercise Council independently of waiting nine months for a first generation of births.
	_edit(SimData.ages().entry, "mars_born_min", 0)
	_edit(SimData.ages().entry, "mars_born_homes_min", 0)
	_ccfg(w).entry.trust_share_min = 0.0
	_ccfg(w).entry.chosen_share_min = 0.0
	_ccfg(w).entry.voices_min = 1
	# A seven-founder household has smaller gatherings than the former instant-birth colony.
	_ccfg(w).session.min_voices = 2


## Three 160-sol seed-42 worlds shared by tests 16 and 22: [module on, module on (a twin), module off from creation]. The
## staged override is applied to all three right after creation.
func _pure_worlds() -> Array:
	if _pw == null:
		var a = SimWorld.new(42)
		var b = SimWorld.new(42)
		var c = SimWorld.new(42)
		c.council_enabled = false
		for w in [a, b, c]:
			_override_entry(w)
			_run_sols(w, 160)
		_pw = [a, b, c]
	return _pw


func _snap(w) -> Dictionary:
	var be: Array = []
	for b in w.beings:
		be.append([b.id, b.building_id, b.state, b.energy])
	var draws: Array = []
	var out := {"beings": be, "stocks": [w.colony.oxygen, w.colony.food, w.colony.ice, w.colony.regolith],
			"rel": str(w.stats.relationships), "pop": str(w.stats.pop_by_sol), "births": w.stats.births,
			"deaths": str(w.stats.deaths_list)}
	for i in 1000:
		draws.append(w.rng.randf())
	out["draws"] = draws
	return out


## The age history projected onto landing / not landing: [[projected age, sol], ...] at each change of the projection.
func _projection(hist: Array) -> Array:
	var out: Array = []
	var last := ""
	for e in hist:
		var p := "L" if str(e.age) == "landing" else "S"
		if p != last:
			out.append([p, int(e.sol)])
			last = p
	return out


func test_t16a_the_guard_the_council_actually_ran(t) -> void:
	if not _api(t):
		return
	var a = _pure_worlds()[0]
	var entered := false
	for e in a.stats.age_history:
		entered = entered or str(e.age) == "council"
	t.check(entered, "the enabled world has a council entry in age_history (the override opens the gate)")
	t.check(int(_cs(a).sessions) >= 3, "at least 3 meetings (%d)" % int(_cs(a).sessions))
	var n := 0
	for k in _kinds(a):
		if k == "council_proposal" or k == "council_quiet":
			n += 1
	t.check(n >= 1, "at least one raise or quiet line")
	_end(t)


func test_t16b_the_module_changes_nothing_beings_do(t) -> void:
	if not _api(t):
		return
	var ws := _pure_worlds()
	var sa := _snap(ws[0])
	var sc := _snap(ws[2])
	t.eq(sa.beings, sc.beings, "enabled vs disabled: equal beings (id, building, state, energy)")
	t.eq(sa.stocks, sc.stocks, "equal stocks")
	t.eq(sa.rel, sc.rel, "equal relationship stats")
	t.eq(sa.pop, sc.pop, "equal pop_by_sol")
	t.eq(sa.deaths, sc.deaths, "equal deaths")
	t.eq(sa.draws, sc.draws, "equal next 1,000 rng draws")
	t.eq(_projection(ws[0].stats.age_history), _projection(ws[2].stats.age_history), "the age history projected onto landing / not landing is equal")
	_end(t)


func test_t16c_same_seed_same_override_same_council(t) -> void:
	if not _api(t):
		return
	var ws := _pure_worlds()
	t.eq(str(_cs(ws[0])), str(_cs(ws[1])), "identical stats.council")
	var la: Array = []
	var lb: Array = []
	for e in ws[0].log:
		la.append(str(e.text))
	for e in ws[1].log:
		lb.append(str(e.text))
	t.eq(la, lb, "identical logs")
	_end(t)


# ================================================================ 17. data

func _spec_keys() -> Array:
	var spec := FileAccess.get_file_as_string("res://docs/specs/council.md")
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


func test_t17a_key_path_parity_both_ways(t) -> void:
	if not _api(t):
		return
	var keys := _spec_keys()
	t.check(keys.size() >= 100, "the spec key list parses (%d keys)" % keys.size())
	var spec_council: Array = []
	var spec_rel: Array = []
	for k in keys:
		if k.begins_with("council."):
			spec_council.append(k)
		elif k.begins_with("relationships."):
			spec_rel.append(k)
		else:
			t.check(false, "unexpected key family in the spec list: %s" % k)
	var leaves: Array = []
	_leaves(_cd(), "council", leaves)
	for k in spec_council:
		t.check(k in leaves, "spec key %s exists in data/council.json" % k)
	for k in leaves:
		t.check(k in spec_council, "data/council.json leaf %s is listed in the spec" % k)
	t.eq(leaves.size(), spec_council.size(), "same number of leaves")
	t.check(_cd().get("topics", null) is Array, "council.topics is a list leaf")
	var rel_leaves: Array = []
	_leaves(SimData.load_json("relationships.json"), "relationships", rel_leaves)
	for k in spec_rel:
		t.check(k in rel_leaves, "spec key %s exists in data/relationships.json (existence only)" % k)
	var sd = load("res://sim/sim_data.gd")
	t.check(_has_static(sd, "council"), "SimData.council() exists")
	if _has_static(sd, "council"):
		t.eq(sd.call("council").hash(), _cd().hash(), "SimData.council() returns data/council.json")
	_end(t)


func test_t17b_balance_data_hash_covers_council(t) -> void:
	if not _api(t):
		return
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var h0: String = lib.data_hash()
	_edit(_cd(), "min_dwell_sols", 21)
	var h1: String = lib.data_hash()
	_restore()
	t.check(h0 != h1, "balance data_hash covers data/council.json")
	t.eq(lib.data_hash(), h0, "and returns to the old value when the data is restored")
	_end(t)


## The sanity rules of spec section 13 test 17, as a list of failed rule names for a data copy.
func _broken_rules(d: Dictionary, ages: Dictionary, bkinds: Array) -> Array:
	var f: Array = []
	if not float(d.exit.trust_share_below) < float(d.entry.trust_share_min):
		f.append("exit below entry")
	var win := int(d.trust.window_sols)
	for p in [["entry", "trust_ok_min"], ["entry", "recent_ok"], ["exit", "split_min"], ["exit", "recent_below"]]:
		if not int(d[p[0]][p[1]]) <= win:
			f.append("%s.%s within the window" % p)
	if not (float(d.support.no_below) < 0.0 and 0.0 < float(d.support.yes_above)):
		f.append("support band")
	if not float(d.decide.carry_share) > 0.5:
		f.append("carry_share")
	if not float(d.decide.divided_share) < 0.5:
		f.append("divided_share")
	if not (float(d.decide.carry_quorum) > float(d.decide.divided_share) and float(d.decide.carry_quorum) <= 0.5):
		f.append("carry_quorum")
	if not (d.topics is Array and not d.topics.is_empty()):
		f.append("topics")
	else:
		for topic in d.topics:
			if not (d.has(topic) and d[topic].has("text") and d[topic].has("lean")):
				f.append("topic block " + str(topic))
	if not int(d.entry.settled_sols) >= int(ages.min_dwell_sols):
		f.append("entry.settled_sols")
	if not int(d.entry.settled_sols) >= int(d.trust.window_sols):
		f.append("entry.settled_sols >= trust.window_sols")  # the Landing skip's safety
	if not int(d.min_dwell_sols) >= int(ages.min_dwell_sols):
		f.append("min_dwell_sols")
	if not int(d.decide.max_open_votes) >= maxi(int(d.decide.carry_sessions), int(d.decide.reject_sessions)) + 1:
		f.append("max_open_votes")
	if not int(d.lines.after_pledge_sols) >= int(d.lines.aftermath_sols):
		f.append("after_pledge_sols")
	if not int(d.session.interval_sols) >= 1:
		f.append("interval_sols")
	if not int(d.session.gathering_max_age_sols) >= 1:
		f.append("gathering_max_age_sols")
	if d.has("dome") and not float(d.dome.lean.trait_centre) > 0.0:
		f.append("trait_centre")
	if not int(d.chosen.kin_generations) >= 0:
		f.append("kin_generations")
	for kind in bkinds:
		if not d.text.place.has(kind):
			f.append("text.place." + kind)
	return f


func test_t17c_data_sanity_rules_hold_and_each_can_fail(t) -> void:
	if not _api(t):
		return
	var ages: Dictionary = SimData.load_json("ages.json")
	var bk: Array = SimData.buildings().kinds.keys()
	t.eq(_broken_rules(_cd(), ages, bk), [], "the shipped data breaks no rule")
	var cases := [
		["exit.trust_share_below", 0.5, "exit below entry"],
		["entry.trust_ok_min", 21, "entry.trust_ok_min within the window"],
		["entry.recent_ok", 21, "entry.recent_ok within the window"],
		["exit.split_min", 21, "exit.split_min within the window"],
		["exit.recent_below", 21, "exit.recent_below within the window"],
		["support.no_below", 0.0, "support band"],
		["support.yes_above", 0.0, "support band"],
		["decide.carry_share", 0.5, "carry_share"],
		["decide.divided_share", 0.5, "divided_share"],
		["decide.carry_quorum", 0.25, "carry_quorum"],
		["decide.carry_quorum", 0.55, "carry_quorum"],
		["topics", [], "topics"],
		["entry.settled_sols", 19, "entry.settled_sols"],
		["trust.window_sols", 31, "entry.settled_sols >= trust.window_sols"],
		["min_dwell_sols", 19, "min_dwell_sols"],
		["decide.max_open_votes", 2, "max_open_votes"],
		["lines.after_pledge_sols", 3, "after_pledge_sols"],
		["session.interval_sols", 0, "interval_sols"],
		["session.gathering_max_age_sols", 0, "gathering_max_age_sols"],
		["dome.lean.trait_centre", 0.0, "trait_centre"],
		["chosen.kin_generations", -1, "kin_generations"]]
	for c in cases:
		var d: Dictionary = _cd().duplicate(true)
		_set_path(d, str(c[0]), c[1])
		t.check(str(c[2]) in _broken_rules(d, ages, bk), "%s = %s breaks '%s'" % [c[0], str(c[1]), c[2]])
	var d2: Dictionary = _cd().duplicate(true)
	d2.text.place.erase("archive")
	t.check("text.place.archive" in _broken_rules(d2, ages, bk), "a building kind without a place phrase breaks the rule")
	var d3: Dictionary = _cd().duplicate(true)
	d3.erase("dome")
	t.check("topic block dome" in _broken_rules(d3, ages, bk), "a topic without its block breaks the rule")
	_end(t)


func test_t17d_no_council_key_in_ages_json(t) -> void:
	if not _api(t):
		return
	var ages: Dictionary = SimData.load_json("ages.json")
	t.check(not ages.has("council"), "ages.json has no council key")
	var leaves: Array = []
	_leaves(ages, "ages", leaves)
	var hit: Array = []
	for k in leaves:
		if "council" in str(k).to_lower():
			hit.append(k)
	t.eq(hit, [], "and no leaf mentions the Council")
	_end(t)


# ================================================================ 18. balance helpers

func _synth(header: String, rows: Array) -> Array:
	var out: Array = [header]
	out.append_array(rows)
	return out


func test_t18a_council_hash_proof_strips_cn_web_age_in_turn(t) -> void:
	if not _api(t):
		return
	var hp: GDScript = load("res://tests/council_hash_proof.gd")
	var full := _synth("sol pop x age web cn", ["30 12 a S 0.50 -", "60 15 b S 0.75 C", "90 18 c L 0.80 P"])
	var r1: Dictionary = hp.drop_cn(full)
	t.eq(r1.body, ["sol pop x age web", "30 12 a S 0.50", "60 15 b S 0.75", "90 18 c L 0.80"], "drop cn removes the last field of header and rows")
	t.check(not r1.cn_absent, "cn present")
	var r2: Dictionary = hp.drop_cn_web(full)
	t.eq(r2.body, ["sol pop x age", "30 12 a S", "60 15 b S", "90 18 c L"], "drop cn and web")
	t.check(not r2.cn_absent and not r2.web_absent, "both present")
	var r3: Dictionary = hp.drop_cn_web_age(full)
	t.eq(r3.body, ["sol pop x", "30 12 a", "60 15 b", "90 18 c"], "drop cn, web and age")
	t.check(not r3.cn_absent and not r3.web_absent and not r3.age_absent, "all three present")
	# a Task 4 table (no cn): check 1 is the identity and reports cn ABSENT; the chain goes on
	var t4 := _synth("sol pop x age web", ["30 12 a S 0.50"])
	var a1: Dictionary = hp.drop_cn(t4)
	t.eq(a1.body, t4, "no cn column: the body is unchanged")
	t.check(a1.cn_absent, "and cn is reported absent")
	var a2: Dictionary = hp.drop_cn_web(t4)
	t.eq(a2.body, ["sol pop x age", "30 12 a S"], "the web strip still works")
	t.check(a2.cn_absent and not a2.web_absent, "cn absent, web present")
	_end(t)


func test_t18b_council_hash_proof_refuses_wrong_columns(t) -> void:
	if not _api(t):
		return
	var hp: GDScript = load("res://tests/council_hash_proof.gd")
	var reordered := _synth("sol pop x age cn web", ["30 12 a S - 0.50"])
	var r: Dictionary = hp.drop_cn(reordered)
	t.eq(r.body, reordered, "cn is not last: nothing is stripped")
	t.check(r.cn_absent, "cn ABSENT")
	var r2: Dictionary = hp.drop_cn_web_age(reordered)
	t.eq(r2.body, ["sol pop x age cn", "30 12 a S -"], "only web is last, so only web goes; age is then not last")
	t.check(r2.cn_absent and r2.age_absent and not r2.web_absent, "cn and age ABSENT, web present")
	var renamed := _synth("sol pop x age web CN", ["30 12 a S 0.50 -"])
	t.check(hp.drop_cn(renamed).cn_absent, "a column called CN is not cn")
	var other := _synth("sol pop x age web cnt", ["30 12 a S 0.50 -"])
	t.check(hp.drop_cn(other).cn_absent, "nor is cnt")
	t.check(hp.drop_cn([]).cn_absent, "an empty table has no cn")
	t.check(not hp.has_last_column(_synth("a b cn", []), "cnx"), "has_last_column compares the whole name")
	_end(t)


func test_t18c_council_hash_proof_hashes_and_references(t) -> void:
	if not _api(t):
		return
	var hp: GDScript = load("res://tests/council_hash_proof.gd")
	# pre-lifecycle baseline (Tasks 1-5), docs/balance/task-4-log.md: 42 a96b8a9562fd75d0, 7 a4968e2fcc48ec36, 99 2210719cf48d8612,
	# 1234 19437e397d1dff88, 2026 6e7fe68477161196. Calendar-lifecycle baseline (docs/balance/lifecycle-rebaseline.md): 42 5cae292b785e5de7,
	# 7 257dc2bda6b29981, 99 d31bc86c094bcff4, 1234 bc78b23075c71ef4, 2026 f404077296a86f66. Current: the water-throughput baseline.
	t.eq(hp.EXPECTED_T4, {42: "6007d885aa1974ac", 7: "cadbd65b8bffdb9c", 99: "40d46838bb39aee5", 1234: "55c479815f1f47ac",
			2026: "27b48573b9aed8e2"}, "the Task 4-level hashes (docs/balance/water-rebaseline.md)")
	t.eq(hp.expected_t3(), load("res://tests/relationships_hash_proof.gd").EXPECTED_T3, "Task 3 hashes by reference")
	t.eq(hp.expected_t1(), load("res://tests/age_hash_proof.gd").EXPECTED, "Task 1 hashes by reference")
	var lines: Array = ["# header one", "# header two", "sol pop age web cn", "30 12 S 0.5 -", "60 14 S 0.6 C", "",
			"targets for seed 1 (60 sols):", "  T1 PASS x"]
	var h: Dictionary = hp.proof_hashes(lines)
	t.eq(h.check1, "sol pop age web\n30 12 S 0.5\n60 14 S 0.6".sha256_text(), "check 1 hashes the body without cn")
	t.eq(h.check2, "sol pop age\n30 12 S\n60 14 S".sha256_text(), "check 2 without cn and web")
	t.eq(h.check3, "sol pop\n30 12\n60 14".sha256_text(), "check 3 without cn, web and age")
	t.check(not h.cn_absent and not h.web_absent and not h.age_absent, "nothing absent")
	_end(t)


func test_t18d_relationships_hash_proof_strips_cn_first(t) -> void:
	if not _api(t):
		return
	var rp: GDScript = load("res://tests/relationships_hash_proof.gd")
	var full := _synth("sol pop x age web cn", ["30 12 a S 0.50 -", "60 15 b S 0.75 C"])
	var r: Dictionary = rp.drop_web_and_age(full)
	t.eq(r.body, ["sol pop x", "30 12 a", "60 15 b"], "cn, then web, then age are stripped (spec 9.1)")
	t.check(not r.web_absent and not r.age_absent, "web and age reported present")
	var r1: Dictionary = rp.drop_web(full)
	t.eq(r1.body, ["sol pop x age", "30 12 a S", "60 15 b S"], "drop_web strips cn first as well")
	var reordered := _synth("sol pop x age cn web", ["30 12 a S - 0.50"])
	var rr: Dictionary = rp.drop_web_and_age(reordered)
	t.check(rr.body != ["sol pop x", "30 12 a"], "a reordered table (cn not last) is still refused")
	t.check(bool(rr.age_absent), "and age is reported absent")
	var t4 := _synth("sol pop x age web", ["30 12 a S 0.50"])
	t.eq(rp.drop_web_and_age(t4).body, ["sol pop x", "30 12 a"], "a Task 4 table (no cn) still strips as before")
	_end(t)


func test_t18e_balance_lib_projections(t) -> void:
	if not _api(t):
		return
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var need := ["age_column", "cn_column", "project_ages", "projected_changes"]
	var missing: Array[String] = []
	for m in need:
		if not _has_static(lib, m):
			missing.append("BalanceLib." + m + "()")
	t.check(missing.is_empty(), "missing API: " + ", ".join(PackedStringArray(missing)))
	if not missing.is_empty():
		_end(t)
		return
	var w = _world()
	_voices(w, 3)
	# age column: S for any age but landing
	w.ages.age = "landing"
	t.eq(lib.age_column(w), "L", "landing prints L")
	w.ages.age = "settlement"
	t.eq(lib.age_column(w), "S", "settlement prints S")
	w.ages.age = "council"
	t.eq(lib.age_column(w), "S", "council prints S (the projected column)")
	# cn column: - before any entry or outside Council without a pledge, C in Council, P after the pledge
	w.ages.age = "landing"
	t.eq(lib.cn_column(w), "-", "landing without a pledge: -")
	w.ages.age = "settlement"
	t.eq(lib.cn_column(w), "-", "settlement without a pledge: -")
	w.ages.age = "council"
	t.eq(lib.cn_column(w), "C", "council without a pledge: C")
	w.council.pledged["dome"] = 55
	t.eq(lib.cn_column(w), "P", "council after the pledge: P")
	w.ages.age = "settlement"
	t.eq(lib.cn_column(w), "P", "after the pledge in any age: P")
	w.ages.age = "landing"
	t.eq(lib.cn_column(w), "P", "even in landing")
	# T10 projection: (S, C, L, S, C, S) is (S, L, S), two projected changes
	var hist: Array = []
	for a in ["settlement", "council", "landing", "settlement", "council", "settlement"]:
		hist.append({"age": a})
	t.eq(lib.project_ages(hist), ["S", "L", "S"], "the history projects to S, L, S")
	t.eq(int(lib.projected_changes(hist)), 2, "with two projected changes")
	var plain: Array = []
	for a in ["landing", "settlement", "landing", "settlement"]:
		plain.append({"age": a})
	t.eq(lib.project_ages(plain), ["L", "S", "L", "S"], "a Task 3 history projects to itself")
	t.eq(int(lib.projected_changes(plain)), 3, "three changes, as in Task 3")
	_end(t)


# ================================================================ 20. relationships off

func _off_world() -> Variant:
	var w = _world()
	_voices(w, 6)
	_calm(w)
	return w


func _step_a_sol(w, sols: int) -> void:
	for i in sols * 500:
		w.step()
		w.colony.oxygen = w.colony.o2_cap()
		w.colony.food = w.colony.food_cap()
		w.colony.ice = 1000.0


func test_t20a_relationships_disabled_reads_zero_and_does_nothing(t) -> void:
	if not _api(t):
		return
	var w = _off_world()
	w.relationships_enabled = false
	_settle(w, 0)
	_step_a_sol(w, 2)
	var n: int = w.stats.pop_by_sol.size()
	t.check(n >= 1, "staging: a sol boundary passed (%d)" % n)
	t.eq(_cs(w).trust_by_sol.size(), n, "trust_by_sol keeps the length of pop_by_sol")
	t.eq(_cs(w).chosen_by_sol.size(), n, "chosen_by_sol too")
	var zeros := true
	for x in _cs(w).trust_by_sol + _cs(w).chosen_by_sol:
		zeros = zeros and float(x) == 0.0
	t.check(zeros, "every reading is 0.0")
	t.check(w.council.stance.is_empty(), "the stances are empty")
	t.check(str(w.stats.age) != "council", "nothing enters")
	t.eq(_clines(w).size(), 0, "no Council line")
	t.eq(int(_cs(w).voices), 6, "voices is the live count")
	_end(t)


func test_t20b_a_null_relationships_module_does_the_same(t) -> void:
	if not _api(t):
		return
	var w = _off_world()
	w.relationships = null
	_step_a_sol(w, 2)
	var n: int = w.stats.pop_by_sol.size()
	t.check(n >= 1, "staging: a sol boundary passed (%d)" % n)
	t.eq(_cs(w).trust_by_sol.size(), n, "trust_by_sol keeps the length of pop_by_sol")
	t.eq(_cs(w).chosen_by_sol.size(), n, "chosen_by_sol too")
	t.check(w.council.stance.is_empty(), "the stances are empty")
	t.check(str(w.stats.age) != "council", "nothing enters")
	t.eq(_clines(w).size(), 0, "no Council line")
	_end(t)


# ================================================================ 22. module off

func test_t22_council_off_from_creation(t) -> void:
	if not _api(t):
		return
	var c = _pure_worlds()[2]
	t.check(c.stats.pop_by_sol.size() >= 100, "staging: a long run (%d boundaries)" % c.stats.pop_by_sol.size())
	t.eq(_cs(c).trust_by_sol.size(), 1, "trust_by_sol holds only the initial reading")
	t.eq(_cs(c).chosen_by_sol.size(), 1, "chosen_by_sol too")
	t.eq(int(c.stats.sols_in_age.council), 0, "sols_in_age.council stays 0")
	var entered := false
	for e in c.stats.age_history:
		entered = entered or str(e.age) == "council"
	t.check(not entered, "no hook ran: the staged override cannot make it enter")
	t.eq(int(_cs(c).sessions), 0, "no meeting")
	t.eq(_clines(c).size(), 0, "no Council line")
	_end(t)
