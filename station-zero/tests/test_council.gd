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


func test_t01b_mars_born_is_a_voice_from_forty_sols(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var n := 100
	var young = _voice(w, {}, 0, float(n) - 39.9)
	var edge = _voice(w, {}, 0, float(n) - 40.0)
	var old = _voice(w, {}, 0, float(n) - 41.0)
	_bnd(w, n)
	t.check(not w.council.is_voice(w, young.id), "a Mars-born being of 39.9 sols is not a voice")
	t.check(w.council.is_voice(w, edge.id), "one of exactly 40 sols is (the slack of SimWorld.STEP_EPS covers float noise)")
	t.check(w.council.is_voice(w, old.id), "and one of 41 sols")
	t.eq(int(_cs(w).voices), 2, "voices reading 2")
	_end(t)


func test_t01c_min_age_is_read_from_the_world_cfg(t) -> void:
	if not _api(t):
		return
	var w = _world()
	var n := 100
	var b = _voice(w, {}, 0, float(n) - 30.0)
	_bnd(w, n)
	t.check(not w.council.is_voice(w, b.id), "30 sols old is no voice at the shipped 40")
	_ccfg(w).voice.min_age_sols = 25
	_bnd(w, n)
	t.check(w.council.is_voice(w, b.id), "voice.min_age_sols 25 in the world's cfg makes it one")
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
	var low := _prefill(20, 0.0, 0.9)
	low = []
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
	t.check(not _try(w, 59, low, low) and str(w.stats.age) == "council", "19 sols after the entry: no split")
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
	t.check(not _try(w, 60, _prefill(20, 0.9), zero) and str(w.stats.age) == "council", "all chosen readings 0.0 with a healthy web: no split")
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
