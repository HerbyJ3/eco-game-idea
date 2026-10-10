extends RefCounted
## Water throughput switches W1-W5. Spec: docs/specs/water-throughput.md section 2.
## Each test flips one switch in the SimData cache and restores it. Shipped defaults must reproduce the old behaviour.
## World: reactor R (door (48,80)), parked reactor, habitat A to the right of R, workshop W below R.

const DT := 0.05


func _world(seed_in: int = 1) -> Dictionary:
	var w := SimWorld.new(seed_in, {"blank": true})
	var r := w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	w.add_building("reactor", 300, 300)
	var a := w.buildings.add_attached("habitat", r.id, "r", 13, 9, 7)
	var wk := w.buildings.add_attached("workshop", r.id, "d", 12, 9, 6)
	return {"w": w, "R": r.id, "A": a.id, "W": wk.id}


func _with(file_key: String, path: Array, value: Variant, body: Callable) -> void:
	var node: Dictionary = SimData.load_json(file_key)
	for i in range(path.size() - 1):
		node = node[path[i]]
	var leaf: String = path[path.size() - 1]
	var old: Variant = node[leaf]
	node[leaf] = value
	body.call()
	node[leaf] = old


func test_defaults_are_off(t) -> void:
	var tp: Dictionary = SimData.resources().throughput
	t.check(tp.urgent_redirect == false, "W1 off by default")
	t.check(float(tp.launch_energy_min) == 0.0, "W2 off by default")
	t.check(tp.commute_pause == false, "W3 shipped on: no room pause while carrying a mine plan")
	t.check(tp.water_before_construction == false, "W5 off by default")
	var m: Dictionary = SimData.colony().consumption.ice_stage_mult
	for k in m:
		t.check(float(m[k]) == 1.0, "W4 %s multiplier is 1.0 by default" % k)
	var s := _world()
	t.check(s.w._water_heads() == -1.0, "W4 plain multipliers skip the stage lookup")


func test_w1_urgent_redirect_drops_regolith_plan(t) -> void:
	for on in [false, true]:
		_with("resources.json", ["throughput", "urgent_redirect"], on, func():
			var s := _world()
			var w: SimWorld = s.w
			var pit := w.resources.add_pit(140.0, 150.0)
			var b := w.add_being(s.A)
			b.mine_intent = pit
			w.colony.ice = 10.0
			var resumed: bool = b._resume_mine_intent(w)
			if on:
				t.check(not resumed and b.mine_intent == null and b.mine == null, "W1 on: regolith plan dropped while ice is urgent")
			else:
				t.check(resumed and (b.mine != null or b.mine_intent != null), "W1 off: regolith plan carried on"))
	# Ice above the urgent line keeps the plan even with W1 on.
	_with("resources.json", ["throughput", "urgent_redirect"], true, func():
		var s := _world()
		var w: SimWorld = s.w
		var pit := w.resources.add_pit(140.0, 150.0)
		var b := w.add_being(s.A)
		b.mine_intent = pit
		w.colony.ice = 80.0
		t.check(b._resume_mine_intent(w), "W1 on: plan kept when ice is not urgent"))


func test_w2_tired_miner_sleeps_and_keeps_plan(t) -> void:
	for on in [false, true]:
		_with("resources.json", ["throughput", "launch_energy_min"], 45 if on else 0, func():
			var s := _world()
			var w: SimWorld = s.w
			var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
			var b := w.add_being(s.R)
			b.start_mining(w, f)
			b.energy = 30.0
			b._door_action(w)
			if on:
				t.check(b.mine == null and b.mine_intent == f and not b.suit_up, "W2 on: trip turned back into a plan")
				t.check(b.state == "sleep" or b.sleep_intent, "W2 on: the tired miner heads to sleep")
			else:
				t.check(b.state == "eva" and b.after == "mine", "W2 off: the miner walks out"))


func test_w2_rested_miner_still_leaves(t) -> void:
	_with("resources.json", ["throughput", "launch_energy_min"], 45, func():
		var s := _world()
		var w: SimWorld = s.w
		var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
		var b := w.add_being(s.R)
		b.start_mining(w, f)
		b.energy = 80.0
		b._door_action(w)
		t.check(b.state == "eva" and b.after == "mine", "W2 on: a rested miner walks out"))


func test_w3_commute_without_room_pause(t) -> void:
	for pause in [true, false]:
		_with("resources.json", ["throughput", "commute_pause"], pause, func():
			var s := _world()
			var w: SimWorld = s.w
			var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
			var b := w.add_being(s.R)
			b.mine_intent = f
			b.enter(w, s.A)
			if pause:
				t.check(b.wait_h > w.fixed_step, "W3 off: a room pause on arrival")
			else:
				t.check(is_equal_approx(b.wait_h, w.fixed_step), "W3 on: one step on arrival while carrying a plan"))
	# Without a plan the pause stays even with W3 on.
	_with("resources.json", ["throughput", "commute_pause"], false, func():
		var s := _world()
		var w: SimWorld = s.w
		var b := w.add_being(s.R)
		b.enter(w, s.A)
		t.check(b.wait_h > w.fixed_step, "W3 on: no plan, normal pause"))


func test_w4_children_drink_less(t) -> void:
	var mult := {"baby": 0.3, "toddler": 0.5, "child": 0.75, "teen": 1.0, "adult": 1.0}
	_with("colony.json", ["consumption", "ice_stage_mult"], mult, func():
		var s := _world()
		var w: SimWorld = s.w
		w.add_being(s.A)
		w.add_being(s.A)
		var baby := w.add_being(s.A)
		baby.born_t = w.t
		t.check(w.lifecycle.stage(baby, w.t) == "baby", "setup: a newborn is a baby")
		t.check(is_equal_approx(w._water_heads(), 2.3), "W4: two adults and a baby drink like 2.3 adults")
		w.colony.ice = 100.0
		w.colony.drain_ice(w.t, 1.0, w._water_heads())
		t.check(is_equal_approx(w.colony.ice, 100.0 - 2.3 * float(SimData.colony().consumption.ice_per_being)),
				"W4: drain uses the weighted head count"))


func test_w5_water_before_construction(t) -> void:
	_with("resources.json", ["throughput", "water_before_construction"], true, func():
		var s := _world()
		var w: SimWorld = s.w
		w.colony.regolith = 500.0
		w.start_site("habitat", {"parent_id": s.R, "dir": "u", "tw": 10, "th": 8, "gap": 5})
		var f := w.resources.add_ice_field(140.0, 150.0, 300.0, 20.0)
		var b := w.add_being(w.resources.launch_for(f).id)
		b.mine_intent = f
		b.energy = 90.0
		w.colony.ice = 20.0
		b.decide(w)
		t.check(b.mine != null and b.job == null, "W5 on: an ice plan beats joining construction when water is short"))


## Section 9 bug fix: a colonist heading to bed keeps the habitat it chose, even when another habitat is nearer
## from a room on the way (re-picking each room could cycle forever).
func test_sleep_walk_keeps_its_habitat(t) -> void:
	var s := _world()
	var w: SimWorld = s.w
	var hb := w.buildings.add_attached("habitat", s.W, "d", 12, 9, 6)
	var b := w.add_being(s.W)
	t.check(w.buildings.nearest_online_habitat(s.W).id == hb.id, "setup: from the workshop, the new habitat is nearest")
	b.sleep_intent = true
	b.sleep_target_id = s.A
	b.go_sleep(w)
	t.eq(b.corridor_id, w.buildings.next_hop(s.W, s.A), "keeps walking toward the habitat it chose")
	w.set_offline(s.A, true)
	b.go_sleep(w)
	t.eq(b.sleep_target_id, hb.id, "re-picks only when its habitat goes dark")
	b._enter_sleep(w)
	t.eq(b.sleep_target_id, 0, "target cleared once asleep")
