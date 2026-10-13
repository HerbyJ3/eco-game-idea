extends RefCounted
## Task 7c step 2: per-being thirst deaths. Spec: docs/specs/per-being-thirst.md sections 2, 4, 6.
## Uses the blank world (see test_colony.gd). Edits to the SimData cache are restored by _restore().

const DT := 0.05
const CHANCE_P := 0.5

var _saved: Array = []


func _edit(key: String, value: Variant) -> void:
	var d: Dictionary = SimData.colony().death
	_saved.append([key, d[key]])
	d[key] = value


func _restore() -> void:
	var d: Dictionary = SimData.colony().death
	for i in range(_saved.size() - 1, -1, -1):
		d[_saved[i][0]] = _saved[i][1]
	_saved.clear()


func _world(seed_in: int, beings: int) -> SimWorld:
	var w := SimWorld.new(seed_in, {"blank": true})
	var reactor: int = w.add_building("reactor", 0, 0, 1.0)
	for i in beings:
		w.add_being(reactor)
	return w


func _kill_all(w: SimWorld, victims: Array) -> void:
	for v: Being in victims:
		w._kill(v, "thirst", "%s died of thirst." % v.name)


func _logs(w: SimWorld, kind: String) -> Array:
	var out: Array = []
	for e: Dictionary in w.log:
		if e.kind == kind:
			out.append(str(e.text))
	return out


func test_data_defaults(t) -> void:
	var d: Dictionary = SimData.colony().death
	t.eq(d.thirst_mode, "colony", "default mode is colony")
	t.eq(float(d.thirst_roll_h), 6.0, "roll interval")
	t.eq(float(d.thirst_being_chance), 0.002, "per-being chance")


func test_draw_count_and_id_order(t) -> void:
	_edit("thirst_mode", "per_being")
	_edit("thirst_being_chance", CHANCE_P)
	var w = _world(42, 8)
	w.beings.reverse()  # list order must not matter, ids ascending decide
	w.beings[0].state = "eva"
	w.beings[3].state = "mining"
	var inside_ids: Array = []
	for b: Being in w.beings:
		if b.is_inside():
			inside_ids.append(b.id)
	inside_ids.sort()
	w.colony.ice = 0.0
	w.rng.reseed(555)
	var ref := SimRng.new(555)
	var expect_ids: Array = []
	for id in inside_ids:
		if ref.chance(CHANCE_P):
			expect_ids.append(id)
	var r: Dictionary = w.colony.shortage_check(6.0)
	var got: Array = []
	for v: Being in r.get("victims", []):
		got.append(v.id)
	t.eq(got, expect_ids, "victims are the successful draws in ascending id order")
	t.eq(w.rng.randf(), ref.randf(), "exactly one draw per inside colonist")
	_restore()


func test_outside_colonists_are_exempt(t) -> void:
	_edit("thirst_mode", "per_being")
	_edit("thirst_being_chance", 1.0)
	var w = _world(42, 6)
	for i in 3:
		w.beings[i].state = "eva"
	var outside: Array = [w.beings[0].id, w.beings[1].id, w.beings[2].id]
	w.colony.ice = 0.0
	var r: Dictionary = w.colony.shortage_check(6.0)
	t.eq(r.victims.size(), 3, "only the three inside colonists are victims")
	for v: Being in r.victims:
		t.check(not outside.has(v.id), "no outside victim")
	# Nobody inside: no victims and no draw.
	for b: Being in w.beings:
		b.state = "work"
	w.rng.reseed(9)
	var ref := SimRng.new(9)
	t.eq(w.colony.shortage_check(6.0), {}, "nobody inside, nobody rolls")
	t.eq(w.rng.randf(), ref.randf(), "no draw when nobody is eligible")
	_restore()


func test_chance_one_and_zero_through_the_world(t) -> void:
	_edit("thirst_mode", "per_being")
	_edit("thirst_being_chance", 1.0)
	var w = _world(42, 5)
	w.colony.ice = 0.0
	for i in 119:
		w.step()
	t.eq(w.beings.size(), 5, "no roll before 6 h")
	w.step()
	t.eq(w.beings.size(), 0, "chance 1.0 kills every colonist at the first roll, 6 h after ice 0")
	t.eq(w.stats.deaths.thirst, 5, "stats.deaths.thirst counts them")
	var lines := _logs(w, "died")
	t.eq(lines.size(), 5, "one died line each")
	for l in lines:
		t.check(l.ends_with(" died of thirst."), "per-being wording: " + l)
	_edit("thirst_being_chance", 0.0)
	var w2 = _world(42, 5)
	w2.colony.ice = 0.0
	for i in 1500:
		w2.step()
	t.eq(w2.beings.size(), 5, "chance 0.0 kills nobody")
	_restore()


func test_death_chance_not_read_for_thirst(t) -> void:
	_edit("thirst_mode", "per_being")
	_edit("thirst_being_chance", 1.0)
	_edit("chance", 0.0)
	var w = _world(42, 4)
	w.colony.ice = 0.0
	t.eq(w.colony.shortage_check(6.0).victims.size(), 4, "death.chance 0 does not stop per-being thirst")
	_restore()


func test_timer_resets_when_ice_returns(t) -> void:
	_edit("thirst_mode", "per_being")
	_edit("thirst_being_chance", 1.0)
	var w = _world(42, 4)
	w.colony.ice = 0.0
	t.eq(w.colony.shortage_check(5.0), {}, "no roll before 6 h")
	t.near(w.colony.death_timer_h, 5.0, 1e-9, "timer accumulates")
	w.colony.ice = 10.0
	t.eq(w.colony.shortage_check(1.0), {}, "no roll while ice is above 0")
	t.eq(w.colony.death_timer_h, 0.0, "timer reset by the refill")
	w.colony.ice = 0.0
	t.eq(w.colony.shortage_check(5.9), {}, "fresh clock: still no roll at 5.9 h")
	t.eq(w.colony.shortage_check(0.1).victims.size(), 4, "roll at 6 h")
	t.eq(w.colony.death_timer_h, 0.0, "timer resets after a roll")
	_restore()


func test_air_priority_and_hunger_stay_on_colony_path(t) -> void:
	_edit("thirst_mode", "per_being")
	_edit("thirst_being_chance", 1.0)
	_edit("chance", 1.0)
	var w = _world(42, 4)
	w.colony.ice = 0.0
	w.colony.oxygen = 0.0
	var r: Dictionary = w.colony.shortage_check(2.0)
	t.eq(r.get("cause"), "air", "air beats thirst")
	t.check(r.has("victim") and not r.has("victims"), "air uses the colony single-victim path")
	var w2 = _world(42, 4)
	w2.colony.food = 0.0
	t.eq(w2.colony.shortage_check(5.9), {}, "hunger interval is hunger_interval_h")
	var r2: Dictionary = w2.colony.shortage_check(0.1)
	t.eq(r2.get("cause"), "hunger", "hunger cause")
	t.check(r2.has("victim"), "hunger single victim")
	_restore()


func test_expected_loss_is_a_share_of_the_colony(t) -> void:
	_edit("thirst_mode", "per_being")
	for pop in [10, 20, 35]:
		var runs := 150 if pop == 10 else 60
		var lost := 0
		for s in runs:
			var w = _world(1000 + s, pop)
			w.colony.ice = 0.0
			for roll in 205:
				_kill_all(w, w.colony.shortage_check(6.0).get("victims", []))
		# count survivors after each world below
			lost += pop - w.beings.size()
		var frac := float(lost) / float(runs * pop)
		t.near(frac, 0.337, 0.03, "pop %d loses about 33.7%% over 205 dry rolls (got %.3f)" % [pop, frac])
	_restore()


func test_run_twice_identical_and_seed_sensitive(t) -> void:
	_edit("thirst_mode", "per_being")
	_edit("thirst_being_chance", 0.02)
	var a = _world(77, 12)
	var b = _world(77, 12)
	var c = _world(78, 12)
	for w in [a, b, c]:
		w.colony.ice = 0.0
		for i in 6000:
			w.step()
	t.eq(a.stats.deaths_list, b.stats.deaths_list, "same seed, same deaths")
	t.eq(_logs(a, "died"), _logs(b, "died"), "same seed, same log")
	t.check(a.stats.deaths_list.size() > 0, "deaths happened")
	t.check(a.stats.deaths_list != c.stats.deaths_list, "another seed differs")
	_restore()


func test_unknown_mode_errors_once_and_falls_back(t) -> void:
	_edit("thirst_mode", "bogus")
	_edit("thirst_roll_h", 6.0)
	var w = _world(42, 5)
	w.colony.ice = 0.0
	t.eq(w.colony.thirst_mode(), "colony", "falls back to colony")
	t.check(w.colony._mode_error_logged, "error flagged")
	# Colony behaviour: thirst_interval_h (5 h) governs, single victim key.
	_edit("chance", 1.0)
	t.eq(w.colony.shortage_check(4.9), {}, "colony interval, not the 6 h roll")
	var r: Dictionary = w.colony.shortage_check(0.1)
	t.check(r.has("victim") and not r.has("victims"), "colony single-victim result")
	_restore()


func test_colony_mode_ignores_the_new_keys(t) -> void:
	var out: Array = []
	for variant in [false, true]:
		if variant:
			_edit("thirst_being_chance", 0.9)
			_edit("thirst_roll_h", 1.0)
		var w = _world(42, 12)
		w.colony.ice = 0.0
		for i in 6000:
			w.step()
		out.append([w.rng.randf(), w.stats.deaths_list, _logs(w, "died")])
		_restore()
	t.eq(out[0], out[1], "colony mode is byte-identical whatever the per-being keys say")
	t.check(out[0][2].size() > 0, "colony deaths happened")
	for l in out[0][2]:
		t.check(l.ends_with(" died (thirst)."), "colony wording: " + l)
