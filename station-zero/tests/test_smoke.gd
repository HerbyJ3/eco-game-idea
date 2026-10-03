extends RefCounted


func test_data_loads(t) -> void:
	t.check(SimData.calendar() is Dictionary, "calendar.json")
	t.eq(SimData.signs().size(), 12, "signs.json")
	t.check(SimData.persona() is Dictionary, "persona.json")
	t.check(SimData.sim() is Dictionary, "sim.json")


func test_rng_is_seeded(t) -> void:
	var a := SimRng.new(42)
	var b := SimRng.new(42)
	var c := SimRng.new(43)
	var same := true
	var differs := false
	for i in 100:
		var x := a.randf()
		if x != b.randf():
			same = false
		if x != c.randf():
			differs = true
	t.check(same, "same seed gives same draws")
	t.check(differs, "different seed gives different draws")


func test_world_fixed_step(t) -> void:
	var w := SimWorld.new(1)
	var t0 := w.t
	var steps := w.advance(1.0)
	t.eq(steps, int(round(1.0 / w.fixed_step)), "steps per hour")
	t.near(w.t - t0, steps * w.fixed_step, 1e-9, "time advanced")
	# Same total hours in uneven chunks lands on the same step count.
	var w2 := SimWorld.new(1)
	var n := 0
	for i in 40:
		n += w2.advance(0.025)
	t.eq(n, steps, "chunked advance")


func test_founders_live_in_sim(t) -> void:
	var a := SimWorld.new(42)
	var b := SimWorld.new(42)
	t.eq(a.founders.size(), int(SimData.persona().founders.count), "founder count")
	for i in a.founders.size():
		t.eq(a.founders[i].persona, b.founders[i].persona, "same seed, same founder %d" % i)


func test_advance_is_capped(t) -> void:
	var w := SimWorld.new(1)
	t.eq(w.advance(1e6), w.max_steps_per_advance, "hitch is capped")
	t.eq(w.advance(0.0), 0, "leftover time dropped")
