extends RefCounted
## Influence powers (Task 7). Spec: docs/specs/influence-powers.md sections 2-3.
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


func _with(file_key: String, path: Array, value: Variant, body: Callable) -> void:
	var node: Dictionary = SimData.load_json(file_key)
	for i in range(path.size() - 1):
		node = node[path[i]]
	var leaf: String = path[path.size() - 1]
	var old: Variant = node[leaf]
	node[leaf] = value
	body.call()
	node[leaf] = old


func test_unknown_and_recharge(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	t.eq(w.use_power("thunder").reason, "unknown_power", "unknown power refused")
	t.check(w.power_ready_in("fortune") == 0.0, "ready at start")
	t.check(w.use_power("fortune").ok, "fortune used")
	t.check(is_equal_approx(w.power_ready_in("fortune"), 3.0 * SOL_H), "fortune recharges for 3 sols")
	t.eq(w.use_power("fortune").reason, "recharging", "second use refused while recharging")
	w.t += 3.0 * SOL_H + 0.01
	t.check(w.use_power("fortune").ok, "ready again after the recharge")


func test_failed_use_spends_no_recharge(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	t.eq(w.use_power("grace", s.R).reason, "bad_target", "grace on a reactor is refused")
	t.check(w.power_ready_in("grace") == 0.0, "no recharge spent on a refusal")
	t.eq(w.use_power("guide", 99).reason, "bad_target", "guide with no such site is refused")
	t.eq(w.use_power("inspire", 999).reason, "bad_target", "inspire with no such building is refused")


func test_fortune_raises_supply_for_a_sol(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	var before := w.buildings.supply()
	w.use_power("fortune")
	w.buildings.now = w.t
	t.check(is_equal_approx(w.buildings.supply(), before * 1.5), "supply x 1.5 while active")
	t.eq(_logs(w, "power_fortune"), 1, "one log line")
	w.t += SOL_H + 0.01
	w.buildings.now = w.t
	t.check(is_equal_approx(w.buildings.supply(), before), "back to normal after a sol")


func test_inspire_steers_the_build_choice(t) -> void:
	_with("powers.json", ["inspire", "chance"], 1.0, func():
		var s := _world()
		var w: SimWorld = s.w
		w.buildings.add_attached("green_room", s.R, "u", 12, 9, 6)
		t.check(w.use_power("inspire", s.W).ok, "inspire a workshop")
		w.colony.oxygen = 5000.0
		w.colony.food = 5000.0
		if w.buildings.margin() < float(w.buildings.cfg.choose.reactor_margin):
			t.check(w.choose_kind() == "reactor", "survival check (reactor) still comes first")
		else:
			t.eq(w.choose_kind(), "workshop", "builders choose the inspired kind")
		w.colony.regolith = 1000.0
		t.check(w.start_site("workshop"), "a workshop site starts")
		t.eq(w.powers.inspire_kind(w.t), "", "inspiration is spent when that kind starts"))


func test_grace_only_in_target_habitat_and_expires(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	t.check(w.use_power("grace", s.A).ok, "grace on a habitat")
	t.check(is_equal_approx(w.powers.grace_bonus(s.A, w.t), 0.35), "bonus in the blessed habitat")
	t.check(w.powers.grace_bonus(s.W, w.t) == 0.0, "no bonus elsewhere")
	t.check(w.powers.grace_bonus(s.A, w.t + 1.5 * SOL_H + 0.01) == 0.0, "bonus ends after 1.5 sols")


func test_guide_picks_the_site_and_raises_volunteering(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	var f1 := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
	var f2 := w.resources.add_ice_field(-90.0, 150.0, 300.0, 20.0)
	t.check(w._site_live(f2), "setup: the second field is reachable")
	var idx := w.power_sites().find(f2)
	t.check(w.use_power("guide", idx).ok, "guide the second field")
	for i in 5:
		t.check(w.choose_site() == f2, "choose_site returns the guided field")
	w.t += SOL_H + 0.01
	t.check(w.powers.guided_site(w.t) == null, "guidance ends after a sol")
	w.t += SOL_H
	f1.amount = 0.0
	t.eq(w.use_power("guide", w.power_sites().find(f1)).reason, "bad_target", "a dry field cannot be guided")


func test_guide_volunteer_floor(t) -> void:
	# With full stocks, need is 0; while guided, a mining attempt treats need as at least 0.6.
	var tries := 400
	var counts := []
	for guided in [false, true]:
		var s := _world(3)
		var w: SimWorld = s.w
		var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
		w.colony.ice = 10000.0
		w.colony.regolith = 10000.0
		w.colony.oxygen = 1000.0
		if guided:
			w.use_power("guide", w.power_sites().find(f))
		var b := w.add_being(s.A)
		var n := 0
		for i in tries:
			b.mine = null
			b.mine_intent = null
			if b._try_new_mining(w):
				n += 1
		counts.append(n)
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
	t.check(w.use_power("sign").ok, "sign sent")
	t.eq(cur.state, "to_door", "the curious colonist goes to look")
	t.eq(std.state, "idle", "the steady colonist stays")
	t.eq(_logs(w, "power_sign"), 1, "one log line")


func test_hud_guide_target(t) -> void:
	var main: GDScript = load("res://view/main.gd")
	var s := _world()
	var w: SimWorld = s.w
	var near_a := w.resources.add_ice_field(260.0, 160.0, 100.0, 20.0)
	var rich := w.resources.add_ice_field(-90.0, 150.0, 400.0, 20.0)
	var sites := w.power_sites()
	t.eq(main._guide_target(w, s.A), sites.find(near_a), "with a building selected: the live site nearest its door")
	t.eq(main._guide_target(w, -1), sites.find(rich), "nothing selected: the richest reachable ice field")
	near_a.amount = 0.0
	rich.amount = 0.0
	t.eq(main._guide_target(w, -1), -1, "no live field: no target")
