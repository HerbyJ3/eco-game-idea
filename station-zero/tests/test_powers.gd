extends RefCounted
## Influence powers (Task 7). Spec: docs/specs/influence-powers.md revision 2, sections 2-5.
## World: reactor R, parked reactor, habitat A right of R, workshop W below R (same layout as test_eva.gd).

const SOL_H := 24.6597


func _world(seed_in: int = 1) -> Dictionary:
	var w := SimWorld.new(seed_in, {"blank": true})
	var r := w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	w.add_building("reactor", 300, 300)
	var a := w.buildings.add_attached("habitat", r.id, "r", 13, 9, 7)
	var wk := w.buildings.add_attached("workshop", r.id, "d", 12, 9, 6)
	return {"w": w, "R": r.id, "A": a.id, "W": wk.id}


func _logs(w: SimWorld, kind: String) -> int:
	var n := 0
	for e in w.log:
		if e.kind == kind:
			n += 1
	return n


## The newest log line of this kind, or "".
func _last(w: SimWorld, kind: String) -> String:
	for i in range(w.log.size() - 1, -1, -1):
		if w.log[i].kind == kind:
			return str(w.log[i].text)
	return ""


func _with(file_key: String, path: Array, value: Variant, body: Callable) -> void:
	var node: Dictionary = SimData.load_json(file_key)
	for i in range(path.size() - 1):
		node = node[path[i]]
	var leaf: String = path[path.size() - 1]
	var old: Variant = node[leaf]
	node[leaf] = value
	body.call()
	node[leaf] = old


func _rng_state(w: SimWorld) -> int:
	return w.rng._rng.state


func test_unknown_and_recharge(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	t.eq(w.use_power("thunder").reason, "unknown_power", "unknown power refused")
	t.check(w.power_ready_in("fortune") == 0.0, "ready at start")
	t.check(w.use_power("fortune").ok, "fortune used")
	t.check(is_equal_approx(w.power_ready_in("fortune"), 4.0 * SOL_H), "fortune recharges for 4 sols")
	t.eq(w.use_power("fortune").reason, "recharging", "second use refused while recharging")
	w.t += 4.0 * SOL_H + 0.01
	t.check(w.use_power("fortune").ok, "ready again after the recharge")
	var rc: Dictionary = SimData.powers().recharge_sols
	t.check(rc.fortune == 4 and rc.inspire == 3 and rc.grace == 3 and rc.sign == 2 and rc.guide == 3,
			"recharge sols are 4/3/3/2/3 (designer-feel numbers)")


func test_every_failure_code_and_text(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	var before := _rng_state(w)
	t.eq(w.use_power("thunder").reason, "unknown_power", "unknown_power")
	t.eq(w.use_power("inspire").reason, "no_target", "inspire with nothing selected")
	t.eq(w.use_power("inspire", 9999).reason, "no_target", "inspire with a stale building id")
	t.eq(w.use_power("grace").reason, "no_target", "grace with nothing selected")
	var site_id := w.add_building("habitat", 400, 400, 0.5)
	t.eq(w.use_power("inspire", site_id).reason, "not_finished", "inspire on a site")
	t.eq(w.use_power("grace", site_id).reason, "not_finished", "grace on a site")
	t.eq(w.use_power("grace", s.R).reason, "not_habitat", "grace on a reactor")
	w.set_offline(s.A, true)
	t.eq(w.use_power("grace", s.A).reason, "habitat_dark", "grace on an offline habitat")
	t.eq(w.use_power("guide").reason, "no_ice", "guide with no ice field at all")
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	t.eq(w.use_power("guide", 5).reason, "bad_field", "guide with an index that is no field")
	var far := w.resources.add_ice_field(5000.0, 5000.0, 300.0, 20.0)
	t.eq(w.use_power("guide", w.resources.ice_fields.find(far)).reason, "bad_field", "guide with a field beyond suit range")
	f.amount = 0.0
	t.eq(w.use_power("guide", w.resources.ice_fields.find(f)).reason, "bad_field", "guide with a dry field")
	t.eq(w.use_power("guide").reason, "no_ice", "guide with only dry or far fields")
	t.check(_rng_state(w) == before, "failed uses draw nothing")
	for p in ["fortune", "inspire", "grace", "sign", "guide"]:
		t.check(w.power_ready_in(p) == 0.0, "no recharge spent by a refusal (%s)" % p)
	t.eq(w.stats.get("powers_used", 0), 0, "no use counted")
	w.use_power("sign")
	t.eq(w.use_power("sign").reason, "recharging", "recharging")
	var fails: Dictionary = SimData.powers().texts.fail
	for code in ["recharging", "unknown_power", "no_target", "not_finished", "not_habitat", "habitat_dark", "no_ice", "bad_field"]:
		t.check(fails.has(code) and str(fails[code]) != "", "world-voice text for %s" % code)
		t.eq(w.power_fail_text(code), fails[code], "power_fail_text reads the data (%s)" % code)


func test_fortune_raises_supply_for_a_sol(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	var before := w.buildings.supply()
	w.use_power("fortune")
	w.buildings.now = w.t
	t.check(is_equal_approx(w.buildings.supply(), before * 1.5), "supply x 1.5 while active")
	t.eq(_logs(w, "power_fortune"), 1, "one log line")
	t.check(is_equal_approx(w.power_active_left("fortune"), SOL_H), "active for a sol")
	w.t += SOL_H + 0.01
	w.buildings.now = w.t
	t.check(is_equal_approx(w.buildings.supply(), before), "back to normal after a sol")
	t.check(w.power_active_left("fortune") == 0.0, "inactive after a sol")


func test_fortune_reports_dark_rooms(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	t.eq(w.dark_building_count(), 0, "nothing dark at first")
	w.set_offline(s.A, true)
	w.set_offline(s.W, true)
	t.eq(w.dark_building_count(), 2, "two finished buildings are dark")
	w.add_building("habitat", 400, 400, 0.5)
	w.set_offline(w.buildings.list.back().id, true)
	t.eq(w.dark_building_count(), 2, "a site that is offline does not count")
	w.use_power("fortune")
	t.check(_last(w, "power_fortune").ends_with("2 dark rooms stir."), "use line counts the dark rooms: " + _last(w, "power_fortune"))
	w.set_offline(s.A, false)
	w.t += SOL_H + 0.01
	w._power_upkeep()
	t.eq(_last(w, "power_end"), "Good fortune ended: 1 of 2 dark rooms are lit again.", "expiry counts the rooms lit again")
	t.eq(_logs(w, "power_end"), 1, "expiry logged once")
	w._power_upkeep()
	t.eq(_logs(w, "power_end"), 1, "and not again")


func test_fortune_with_nothing_dark(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	w.use_power("fortune")
	t.eq(_last(w, "power_fortune"), "Good fortune: the reactors run hot for a sol.", "plain use line")
	w.t += SOL_H + 0.01
	w._power_upkeep()
	t.eq(_last(w, "power_end"), "Good fortune ended.", "plain expiry line")


func test_ready_again_line(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	w.use_power("sign")
	w._power_upkeep()
	t.eq(_logs(w, "power_ready"), 0, "no ready line while recharging")
	w.t += 2.0 * SOL_H + 0.01
	w._power_upkeep()
	t.eq(_last(w, "power_ready"), "Sign is ready again.", "ready line names the power")
	w._power_upkeep()
	t.eq(_logs(w, "power_ready"), 1, "once")
	w.use_power("sign")
	w.t += 2.0 * SOL_H + 0.01
	w._power_upkeep()
	t.eq(_logs(w, "power_ready"), 2, "again after the next use")


func test_inspire_steers_the_build_choice(t) -> void:
	_with("powers.json", ["inspire", "chance"], 1.0, func():
		var s := _world()
		var w: SimWorld = s.w
		w.buildings.add_attached("green_room", s.R, "u", 12, 9, 6)
		t.check(w.use_power("inspire", s.W).ok, "inspire a workshop")
		t.eq(_last(w, "power_inspire"), "Inspiration: the builders dream of another workshop.", "use line")
		w.colony.oxygen = 5000.0
		w.colony.food = 5000.0
		if w.buildings.margin() < float(w.buildings.cfg.choose.reactor_margin):
			t.check(w.choose_kind() == "reactor", "survival check (reactor) still comes first")
		else:
			t.eq(w.choose_kind(), "workshop", "builders choose the inspired kind")
		w.colony.regolith = 1000.0
		t.check(w.start_site("workshop"), "a workshop site starts")
		t.eq(w.powers.inspire_kind(w.t), "", "inspiration is spent when that kind starts"))


func test_inspire_names_the_builder_and_expires(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	var builder := w.add_being(s.W, "builder")
	w.use_power("inspire", s.W)
	w.colony.regolith = 1000.0
	t.check(w.start_site("workshop"), "a workshop site starts")
	t.eq(_last(w, "power_inspire_start"), "%s sketches another workshop." % builder.name, "the builder is named")
	w.t += 3.0 * SOL_H
	w._power_upkeep()
	t.eq(_logs(w, "power_end"), 0, "no expiry line after the kind started")
	# Expiry without a start.
	w.t += 1.0
	w.buildings.site = null
	w.use_power("inspire", s.A)
	w.t += 2.0 * SOL_H + 0.01
	w._power_upkeep()
	t.eq(_last(w, "power_end"), "The inspiration passed; no one started a habitat.", "expiry without a start")
	t.eq(w.powers.inspire_kind(w.t), "", "inspiration over")


func test_grace_names_two_adults_and_counts_lives(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	t.check(w.use_power("grace", s.A).ok, "grace on a habitat")
	t.eq(_last(w, "power_grace"), "Grace: it feels like a good time to start a family here.", "fewer than two adults")
	t.check(is_equal_approx(w.powers.grace_bonus(s.A, w.t), 0.35), "bonus in the blessed habitat")
	t.check(w.powers.grace_bonus(s.W, w.t) == 0.0, "no bonus elsewhere")
	t.check(w.powers.grace_bonus(s.A, w.t + 1.5 * SOL_H + 0.01) == 0.0, "bonus ends after 1.5 sols")
	w.powers.grace.conceptions = 2
	w.t += 1.5 * SOL_H + 0.01
	w._power_upkeep()
	t.eq(_last(w, "power_end"), "Grace ended: 2 new lives begun in the habitat.", "expiry counts conceptions")
	var s2 := _world()
	var w2: SimWorld = s2.w
	var p1 := w2.add_being(s2.A)
	var p2 := w2.add_being(s2.A)
	w2.add_being(s2.A)
	w2.use_power("grace", s2.A)
	t.eq(_last(w2, "power_grace"), "Grace: %s and %s linger together." % [p1.name, p2.name], "two adults named")


func test_guide_targets_the_richest_live_ice_field(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	var near := w.resources.add_ice_field(140.0, 150.0, 100.0, 20.0)
	var rich := w.resources.add_ice_field(-90.0, 150.0, 400.0, 20.0)
	var rich2 := w.resources.add_ice_field(-90.0, 160.0, 400.0, 20.0)
	var gone := w.resources.add_ice_field(260.0, 160.0, 900.0, 20.0)
	gone.amount = 0.0
	var far := w.resources.add_ice_field(5000.0, 5000.0, 900.0, 20.0)
	t.eq(w.richest_live_ice(), w.resources.ice_fields.find(rich), "richest live field; ties to the lowest index; dry and far skipped")
	t.check(w._site_live(near) and w._site_live(rich2) and not w._site_live(far), "setup: liveness")
	# A stale selection does not matter: Guide takes no target from the player.
	t.check(w.use_power("guide").ok, "guide with the default target")
	t.check(w.powers.guided_site(w.t) == rich, "the guided field is the richest live one")
	t.eq(_last(w, "power_guide"), "Guidance: the colony feels drawn to ice field %d (400 ice left)." % (w.resources.ice_fields.find(rich) + 1),
			"the log names the field and its ice")
	var s2 := _world()
	var w2: SimWorld = s2.w
	w2.resources.add_ice_field(140.0, 150.0, 100.0, 20.0)
	var other := w2.resources.add_ice_field(-90.0, 150.0, 400.0, 20.0)
	t.check(w2.use_power("guide", 0).ok, "an explicit index among live fields is allowed (tests and bots)")
	t.check(w2.powers.guided_site(w2.t) != other, "and it is the one asked for")


func test_guide_is_a_weight_not_an_override(t) -> void:
	for chance in [1.0, 0.0]:
		_with("powers.json", ["guide", "chance"], chance, func():
			var s := _world(5)
			var w: SimWorld = s.w
			var f1 := w.resources.add_ice_field(140.0, 150.0, 100.0, 20.0)
			var f2 := w.resources.add_ice_field(-90.0, 150.0, 400.0, 20.0)
			w.colony.ice = 10.0
			w.use_power("guide")
			var guided := 0
			for i in 60:
				if w.choose_site() == f2:
					guided += 1
			if chance == 1.0:
				t.eq(guided, 60, "chance 1: every choice is the guided field")
			else:
				t.check(guided < 60, "chance 0: the normal choice runs (both fields picked)")
				t.check(f1 != null, "setup"))
	var s := _world(6)
	var w: SimWorld = s.w
	var f1 := w.resources.add_ice_field(140.0, 150.0, 100.0, 20.0)
	var f2 := w.resources.add_ice_field(-90.0, 150.0, 400.0, 20.0)
	w.colony.ice = 10.0
	w.use_power("guide")
	var n := 400
	var hits := 0
	var other := 0
	for i in n:
		var site := w.choose_site()
		if site == f2:
			hits += 1
		elif site == f1:
			other += 1
	t.between(float(hits) / n, 0.7, 0.9, "about the guide chance plus its share of the normal pick (%d of %d)" % [hits, n])
	t.check(other > 0, "the other field still gets some choices: a weight, not an order")
	# Inactive: choose_site draws exactly what it drew before Task 7 (urgent ice: one pick, no chance).
	var s3 := _world(6)
	var w3: SimWorld = s3.w
	var only := w3.resources.add_ice_field(140.0, 150.0, 100.0, 20.0)
	w3.colony.ice = 10.0
	var ref := SimRng.new(6)
	ref.pick([only])
	t.check(w3.choose_site() == only, "setup: the only field is chosen")
	t.check(_rng_state(w3) == ref._rng.state, "no guide active: no guide chance is drawn")


func test_guide_stops_when_the_tanks_are_full(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	t.check(w.use_power("guide").ok, "guide")
	w.colony.ice = 1.4 * w.colony.ice_target()
	t.check(w.choose_site() != f, "above stop_factor x target the guided field is not chosen")
	var s2 := _world()
	var w2: SimWorld = s2.w
	w2.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	w2.colony.ice = 1.4 * w2.colony.ice_target()
	w2.choose_site()
	t.check(_rng_state(w) == _rng_state(w2), "and no guide chance is drawn (same draws as an unguided world)")
	w._power_upkeep()
	t.check(w.powers.guide.is_empty(), "the guide ends early")
	t.eq(_last(w, "power_end"), "Guidance ended: no one set out.", "and says so")


func test_guide_trip_counts_and_expiry_lines(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var other := w.resources.add_ice_field(-90.0, 150.0, 100.0, 20.0)
	var b1 := w.add_being(s.A)
	var b2 := w.add_being(s.A)
	t.check(not w.note_ice_trip(b1, f), "no guide: not a guided trip")
	t.eq(w.stats.ice_trips_total, 1, "total ice trips counted")
	w.use_power("guide")
	t.check(w.note_ice_trip(b1, f), "a trip to the guided field counts")
	t.check(not w.note_ice_trip(b2, other), "a trip to another field does not")
	t.check(w.note_ice_trip(b2, f), "second guided trip")
	t.eq(_logs(w, "power_guide_first"), 1, "first volunteer named once")
	t.eq(_last(w, "power_guide_first"), "%s sets out for ice field 1." % b1.name, "first volunteer line")
	t.eq(w.stats.guide_trips, 2, "guided trips")
	t.eq(w.stats.ice_trips_total, 4, "all ice trips")
	t.eq(w.stats.ice_trips_guided_window, 3, "ice trips begun while guidance was on")
	b1.mine = {"site": f, "guide": w.powers.guide}
	w.powers.guide.hauled = 38.4
	w.t += SOL_H + 0.01
	w._power_upkeep()
	t.eq(_last(w, "power_end"), "Guidance ended: 2 trips, 38 hauled.", "outcome line")
	var s2 := _world()
	var w2: SimWorld = s2.w
	w2.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	w2.use_power("guide")
	w2.t += SOL_H + 0.01
	w2._power_upkeep()
	t.eq(_last(w2, "power_end"), "Guidance ended: no one set out.", "ignored guidance is never silent")
	t.check(w2.power_active_left("guide") == 0.0, "inactive after expiry")


func test_guide_haul_counts_the_ice_delivered(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var b := w.add_being(s.A)
	w.use_power("guide")
	w.note_ice_trip(b, f)
	b.mine = {"site": f, "home_id": s.A, "guide": w.powers.guide}
	b.after = "haul"
	b.load = 12.0
	var ice := w.colony.ice
	b._finish_eva(w)
	t.check(is_equal_approx(w.colony.ice, ice + 12.0), "the load is delivered")
	t.check(is_equal_approx(float(w.stats.guide_hauled), 12.0), "guide_hauled counts it")
	t.check(is_equal_approx(float(w.powers.guide.hauled), 12.0), "so does the running guidance")


func test_guide_volunteer_floor(t) -> void:
	# With the ice term full, need is 0; while guided, a mining attempt treats the ice need as at least 0.6.
	var tries := 400
	var counts := []
	for guided in [false, true]:
		var s := _world(3)
		var w: SimWorld = s.w
		var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
		w.colony.ice = 1.2 * w.colony.ice_target()
		w.colony.regolith = 10000.0
		w.colony.oxygen = 1000.0
		if guided:
			w.use_power("guide")
		var b := w.add_being(s.A)
		var n := 0
		for i in tries:
			b.mine = null
			b.mine_intent = null
			if b._try_new_mining(w):
				n += 1
		counts.append(n)
		t.check(f != null, "setup")
	t.check(counts[1] > counts[0] * 2, "guidance makes volunteering much more likely (%d vs %d)" % [counts[1], counts[0]])


func test_sign_curious_go_steady_stay(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	var cur := w.add_being(s.R)
	var std := w.add_being(s.R)
	for k in cur.persona.traits:
		cur.persona.traits[k] = 0.0
		std.persona.traits[k] = 0.0
	cur.persona.traits.curiosity = 1.0
	std.persona.traits.steady = 1.0
	cur.state = "idle"
	std.state = "idle"
	var res := w.use_power("sign")
	t.check(res.ok, "sign sent")
	t.eq(cur.state, "to_door", "the curious colonist goes to look")
	t.eq(std.state, "idle", "the steady colonist stays")
	t.eq(_logs(w, "power_sign"), 1, "one log line")
	t.eq(_last(w, "power_sign"), "A light crossed the sky. %s was pulled most and %s least. 1 went to look, 1 stayed put." % [cur.name, std.name],
			"named most and least pulled")
	t.eq(res.went, 1, "result carries the split")
	t.eq(res.eligible, 2, "and the eligible count")


func test_sign_with_one_eligible_gives_counts_only(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	var only := w.add_being(s.R)
	only.state = "idle"
	w.use_power("sign")
	t.check(not _last(w, "power_sign").contains("pulled most"), "no names with fewer than two eligible: " + _last(w, "power_sign"))
	t.check(_last(w, "power_sign").begins_with("A light crossed the sky. "), "still a sign line")


## Spec 5.5: the split is never all-or-nothing on real colonies. Five seeds, signs at sols 20, 100, 300.
func test_sign_split_on_real_colonies(t) -> void:
	var asserted := 0
	for seed_in in [42, 7, 99, 1234, 2026]:
		var w := SimWorld.new(seed_in)
		for target_sol in [20, 100, 300]:
			while w.sol() < target_sol:
				w.step()
			# Sign moves idle colonists only, so a split needs at least two of them to be idle.
			var idle := 0
			for b in w.beings:
				if b.is_inside() and b.state == "idle" and w.lifecycle.stage(b, w.t) != "baby":
					idle += 1
			var res := w.use_power("sign")
			t.check(res.ok, "seed %d sol %d: sign sent" % [seed_in, target_sol])
			if int(res.get("eligible", 0)) >= 4 and idle >= 2:
				asserted += 1
				t.check(int(res.went) > 0 and int(res.went) < int(res.eligible),
						"seed %d sol %d: 0 < went < eligible (%d of %d)" % [seed_in, target_sol, int(res.went), int(res.eligible)])
	t.check(asserted >= 5, "the split was asserted on at least five casts (%d)" % asserted)


func _water_world(pop: int = 8) -> SimWorld:
	var s := _world()
	var w: SimWorld = s.w
	for i in pop:
		w.add_being(s.A)
	return w


func test_water_outlook_states(t) -> void:
	var w := _water_world(8)
	t.near(w.colony.ice_target(), 120.0, 0.001, "setup: target is the 120 floor")
	w.colony.ice = 110.0
	w.ice_at_sol_start = 110.0
	t.eq(w.water_outlook().state, "steady", "plenty of water, flat")
	w.colony.ice = 100.0
	w.ice_at_sol_start = 120.0
	t.eq(w.water_outlook().state, "steady", "above 0.8 x target: steady even if falling")
	w.colony.ice = 90.0
	w.ice_at_sol_start = 90.5
	t.eq(w.water_outlook().state, "steady", "below 0.8 but not falling by 0.01 x target")
	w.ice_at_sol_start = 92.0
	t.eq(w.water_outlook().state, "falling", "below 0.8 and down 2 since sol start (>= 1.2)")
	w.colony.ice = 61.0
	w.ice_at_sol_start = 61.0
	t.eq(w.water_outlook().state, "steady", "just above 0.5 x target and flat")
	w.colony.ice = 50.0
	t.eq(w.water_outlook().state, "low", "below 0.5 x target")
	w.colony.ice = 0.0
	t.eq(w.water_outlook().state, "dry", "no ice")
	w.colony.ice = 50.0
	var o := w.water_outlook()
	t.near(float(o.sols), 50.0 / (8.0 * 0.01 * SOL_H), 0.001, "sols = stock / (heads x drink x sol hours)")
	t.near(float(o.target), 120.0, 0.001, "outlook carries the target")
	t.near(float(o.ice), 50.0, 0.001, "and the ice")


func test_water_outlook_hysteresis_and_log(t) -> void:
	var w := _water_world(8)
	w.colony.ice = 61.0
	w.ice_at_sol_start = 61.0
	w._update_water()
	t.eq(_logs(w, "water_low"), 0, "no line above the threshold")
	w.colony.ice = 55.0
	w._update_water()
	t.eq(_logs(w, "water_low"), 1, "one line on entering low")
	t.check(_last(w, "water_low").begins_with("The water tanks are below half: about "), "world voice: " + _last(w, "water_low"))
	t.eq(w.stats.first_low_sol, w.sol(), "first low sol recorded")
	w.colony.ice = 65.0
	w._update_water()
	t.eq(w.water_outlook().state, "low", "still low between 0.5 and 0.6 x target")
	t.eq(_logs(w, "water_low") + _logs(w, "water_ok"), 1, "no new line while in the band")
	w.colony.ice = 55.0
	w._update_water()
	t.eq(_logs(w, "water_low"), 1, "dipping again inside the band is not a new crossing")
	w.colony.ice = 73.0
	w.ice_at_sol_start = 73.0
	w._update_water()
	t.eq(w.water_outlook().state, "steady", "leaves low at 0.6 x target")
	t.eq(_last(w, "water_ok"), "The water is holding again.", "quiet line when it clears")
	w.colony.ice = 50.0
	w._update_water()
	t.eq(_logs(w, "water_low"), 2, "re-armed: a second crossing logs again")
	w.colony.ice = 0.0
	w._update_water()
	t.eq(w.water_outlook().state, "dry", "dry")
	t.eq(_logs(w, "water_low"), 2, "going dry from low is not a new low")


func test_water_outlook_is_a_pure_read(t) -> void:
	var w := _water_world(8)
	w.colony.ice = 50.0
	var before := _rng_state(w)
	var logn := w.log.size()
	for i in 20:
		w.water_outlook()
		w.dark_building_count()
	t.check(_rng_state(w) == before and w.log.size() == logn, "reading the outlook changes nothing")
	w.colony.ice = 70.0
	t.eq(w.water_outlook().state, "steady", "the latch is only set by _update_water, not by reading")


func test_sol_boundary_stores_ice(t) -> void:
	var w := SimWorld.new(3)
	var steps := int(ceil(SOL_H / w.fixed_step)) + 3
	for i in steps:
		w.step()
	t.check(w.sol() >= 1, "setup: a sol has passed")
	t.check(w.ice_at_sol_start > 0.0, "ice at sol start stored")
	t.check(w.ice_at_sol_start >= w.colony.ice - 30.0, "and it is close to the current stock")


func test_active_power_timers(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	w.use_power("inspire", s.W)
	w.use_power("grace", s.A)
	t.check(is_equal_approx(w.power_active_left("inspire"), 2.0 * SOL_H), "inspire 2 sols")
	t.check(is_equal_approx(w.power_active_left("grace"), 1.5 * SOL_H), "grace 1.5 sols")
	t.check(w.power_active_left("sign") == 0.0 and w.power_active_left("guide") == 0.0, "idle powers show none")


func test_hud_texts(t) -> void:
	var main: GDScript = load("res://view/main.gd")
	var w := _water_world(8)
	w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	w.colony.ice = 110.0
	w.ice_at_sol_start = 110.0
	t.eq(main._water_text(w), "Water    steady", "Water line, steady")
	w.colony.ice = 90.0
	w.ice_at_sol_start = 95.0
	t.check(main._water_text(w).begins_with("Water    falling (about "), "Water line, falling: " + main._water_text(w))
	w.colony.ice = 50.0
	t.check(main._water_text(w).begins_with("Water    LOW (about "), "Water line, LOW: " + main._water_text(w))
	w.colony.ice = 0.0
	t.eq(main._water_text(w), "Water    DRY", "Water line, DRY")
	w.colony.ice = 110.0
	t.eq(main._button_text(w, "guide", 5), "[F5] Guide ready", "plain Guide when water is fine")
	w.colony.ice = 50.0
	t.eq(main._button_text(w, "guide", 5), "[F5] Guide - ice low", "Guide marked when ice is low")
	t.eq(main._button_text(w, "sign", 4), "[F4] Sign ready", "nothing else is marked")
	t.eq(main._button_text(w, "fortune", 1), "[F1] Fortune ready", "Fortune plain with no dark room")
	w.set_offline(w.buildings.list[2].id, true)
	t.eq(main._button_text(w, "fortune", 1), "[F1] Fortune - a room is dark", "Fortune marked when a room is dark")
	w.use_power("guide")
	t.check(main._button_text(w, "guide", 5).begins_with("[F5] Guide on: field 1 (1.0 sols)"), "active power shows time left: " + main._button_text(w, "guide", 5))
	w.t += SOL_H + 0.01
	t.eq(main._button_text(w, "guide", 5), "[F5] Guide 2.0 sols", "recharging shows sols with one decimal")
	w.t += 1.6 * SOL_H
	t.eq(main._button_text(w, "guide", 5), "[F5] Guide soon", "under half a sol: soon")


func test_unused_powers_leave_the_sim_alone(t) -> void:
	# Two identical founder worlds; one is read through the whole outlook API every step. Nothing may diverge.
	var a := SimWorld.new(9)
	var b := SimWorld.new(9)
	for i in 1500:
		a.step()
		b.step()
		b.water_outlook()
		b.dark_building_count()
		b.power_ready_in("guide")
	t.check(_rng_state(a) == _rng_state(b), "reading the outlook draws nothing")
	t.check(is_equal_approx(a.colony.ice, b.colony.ice) and a.colony.pop() == b.colony.pop(), "same colony")
	t.eq(a.stats.get("powers_used", 0), 0, "no power was used")
	var kinds := {}
	for e in a.log:
		kinds[e.kind] = true
	t.check(not kinds.has("power_end") and not kinds.has("power_ready") and not kinds.has("power_guide"), "no power lines in an unattended log")


func test_balance_run_aborts_on_a_rejected_override(t) -> void:
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var before: float = float(SimData.colony().consumption.ice_per_being)
	var res: Dictionary = lib.run(1, 5, {"colony.consumption.ice_per_being": 0.5, "colony.no.such.key": 1.0})
	t.check(res.get("error", false), "a rejected override returns an error result")
	t.eq(res.steps, 0, "nothing was simulated")
	t.check(res.world == null, "no world was built")
	t.check(str(res.lines).contains("PARAM ERROR"), "the error is reported")
	t.check(float(SimData.colony().consumption.ice_per_being) == before, "the override that was accepted is restored")
	var ok: Dictionary = lib.run(1, 1, {"colony.consumption.ice_per_being": 0.01})
	t.check(not ok.get("error", false) and ok.steps > 0, "a good override still runs")


func test_attentive_player_cadence_and_report(t) -> void:
	var player: RefCounted = load("res://tools/attentive_player.gd").new()
	player.cadence = 2.0
	player.sample_every = 2
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var res: Dictionary = lib.run(7, 6, {}, 2, "", player)
	t.check(player.checks >= 2 and player.checks <= 4, "about one glance per two sols over 6 sols (%d)" % player.checks)
	var lines: Array = player.report(res.world)
	t.check(lines.size() >= 4 and str(lines).contains("first_low_sol=") and str(lines).contains("low_share="), "report prints the section 5 metrics")
	t.eq(res.world.stats.first_low_sol, 0, "the founder colony starts below half its water target")
