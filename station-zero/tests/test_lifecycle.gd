extends RefCounted
## Real default gestation and calendar-age boundaries; no accelerated gestation in these fixtures.


func _world(n: int = 2) -> SimWorld:
	var w := SimWorld.new(42, {"blank": true})
	w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	w.buildings.add("green_room", 20, 0, 1.0, 12, 9)
	var home := w.buildings.add("habitat", 40, 0, 1.0, 13, 9)
	for i in n:
		var b := w.add_being(home.id, "social")
		b.wait_h = 1e9
	return w


func _date(life: Lifecycle, text: String) -> float:
	return (float(Time.get_unix_time_from_datetime_string(text))
			- float(Time.get_unix_time_from_datetime_string(str(life.cfg.calendar_epoch)))) / Lifecycle.SECONDS_PER_HOUR


func test_default_schedule(t) -> void:
	var life := Lifecycle.new()
	t.eq(life.cfg.pregnancy_months, 9, "nine-month pregnancy")
	t.eq(life.cfg.toddler_age_years, 1, "toddler at first birthday")
	t.eq(life.cfg.child_age_years, 3, "child at third birthday")
	t.eq(life.cfg.teen_age_years, 13, "teen at thirteenth birthday")
	t.eq(life.cfg.adult_age_years, 18, "adult at eighteenth birthday")
	t.eq(SimData.sim().real_seconds_per_hour_at_1x, 1.0, "clock speed unchanged")


func test_pregnancy_uses_nine_calendar_months(t) -> void:
	var life := Lifecycle.new()
	for dates in [["2000-01-01T08:30:00", "2000-10-01T08:30:00"],
			["2000-05-31T12:00:00", "2001-02-28T12:00:00"],
			["2003-05-31T12:00:00", "2004-02-29T12:00:00"]]:
		var conception := _date(life, dates[0])
		t.near(life.add_months(conception, 9), _date(life, dates[1]), 1e-8, "due date from " + dates[0])


func test_calendar_preserves_subsecond_simulation_time(t) -> void:
	var life := Lifecycle.new()
	var fraction := 0.125 / Lifecycle.SECONDS_PER_HOUR
	t.near(life.add_months(fraction, 9) - life.add_months(0.0, 9), fraction, 1e-8, "no fraction lost at conception")


func test_life_stages_change_on_birthdays(t) -> void:
	var w := _world()
	var b := w.beings[0]
	b.born_t = _date(w.lifecycle, "2000-06-15T09:00:00")
	t.eq(w.lifecycle.stage(b, b.born_t), "baby", "starts as a baby")
	for boundary in [[1, "baby", "toddler"], [3, "toddler", "child"], [13, "child", "teen"], [18, "teen", "adult"]]:
		var when := w.lifecycle.birthday(b, boundary[0])
		t.eq(w.lifecycle.stage(b, when - w.fixed_step), boundary[1], "before birthday")
		t.eq(w.lifecycle.stage(b, when), boundary[2], "at birthday")


func test_leap_day_birthday_uses_february_end(t) -> void:
	var w := _world()
	var b := w.beings[0]
	b.born_t = _date(w.lifecycle, "2000-02-29T12:00:00")
	t.near(w.lifecycle.birthday(b, 1), _date(w.lifecycle, "2001-02-28T12:00:00"), 1e-8)
	t.near(w.lifecycle.birthday(b, 4), _date(w.lifecycle, "2004-02-29T12:00:00"), 1e-8)


func test_birth_record_change_invalidates_age_cache(t) -> void:
	var w := _world()
	var b := w.beings[0]
	t.check(w.lifecycle.is_adult(b, w.t), "adult fixture")
	b.born_t = w.t
	t.eq(w.lifecycle.stage(b, w.t), "baby", "updated birth date recalculates stage")


func test_founders_are_adults_and_mars_newborns_are_babies(t) -> void:
	var w := SimWorld.new(42)
	for b in w.beings:
		t.eq(w.lifecycle.stage(b, w.t), "adult", "founder " + b.name)
	var home: Buildings.Building = null
	for b in w.buildings.list:
		if b.kind == "habitat":
			home = b
	w._create_newborn(home, w.beings[0])
	t.eq(w.lifecycle.stage(w.beings.back(), w.t), "baby", "actual newborn")


func test_no_birth_before_due_and_one_birth_at_due(t) -> void:
	var w := _world()
	var parent := w.beings[0]
	w.lifecycle.conceive(parent, parent.building_id, w.t)
	var due: float = w.lifecycle.pregnancies[parent.id].due_t
	t.eq(w.beings.size(), 2, "pregnancy is not population")
	w.t = due - 2.0 * w.fixed_step
	w.step()
	t.eq(w.beings.size(), 2, "not born one step early")
	t.eq(w.stats.births, 0, "no early birth counter")
	w.step()
	t.eq(w.beings.size(), 3, "birth on due step")
	t.eq(w.stats.births, 1, "one counted birth")
	t.eq(w.beings.back().parent_id, parent.id, "parent retained")
	t.eq(w.beings.back().born_t, w.t, "age starts at delivery")
	t.eq(w.lifecycle.stage(w.beings.back(), w.t), "baby", "baby at birth")
	t.eq(w.lifecycle.pregnancies.size(), 0, "pregnancy completed")
	w.step()
	t.eq(w.stats.births, 1, "not delivered twice")


func test_normal_birth_check_schedules_pregnancy_not_instant_baby(t) -> void:
	var w := _world()
	var birth: Dictionary = SimData.colony().birth
	var old := float(birth.base_chance)
	birth.base_chance = 2.0
	w.colony.birth_timer_h = float(birth.check_interval_h) - w.fixed_step
	w.step()
	birth.base_chance = old
	t.eq(w.lifecycle.pregnancies.size(), 1, "default phase schedules gestation")
	t.eq(w.beings.size(), 2, "no instant baby")
	t.eq(w.stats.births, 0, "birth counter waits for delivery")
	var record: Dictionary = w.lifecycle.pregnancies.values()[0]
	t.near(float(record.due_t), w.lifecycle.add_months(w.t, 9), 1e-8, "nine-month due date")
	t.eq(w.log.back().kind, "pregnant", "player sees the pregnancy")


func test_pregnancies_reserve_population_capacity(t) -> void:
	var w := _world(6)
	w.lifecycle.conceive(w.beings[0], w.beings[0].building_id, w.t)
	var eligible: Array = []
	for b in w.beings:
		if w.lifecycle.can_conceive(b, w.t):
			eligible.append(b)
	t.check(not w.colony.birth_gates_ok(w.beings[0].building_id, eligible, w.t, w.lifecycle.pregnancies.size()),
			"six people and one expected baby fill capacity seven")
	t.check(w.colony.birth_gates_ok(w.beings[0].building_id, eligible, w.t, 0), "without reservation there is space")


func test_only_adults_can_conceive_and_not_twice(t) -> void:
	var w := _world()
	var b := w.beings[0]
	b.born_t = w.t
	for age in [0, 1, 3, 13, 17]:
		t.check(not w.lifecycle.can_conceive(b, w.lifecycle.birthday(b, age)), "age %d cannot conceive" % age)
	w.t = w.lifecycle.birthday(b, 18)
	t.check(w.lifecycle.can_conceive(b, w.t), "adult can conceive")
	w.lifecycle.conceive(b, b.building_id, w.t)
	t.check(not w.lifecycle.can_conceive(b, w.t), "already pregnant")


func test_dead_parent_releases_pregnancy_reservation(t) -> void:
	var w := _world()
	var b := w.beings[0]
	w.lifecycle.conceive(b, b.building_id, w.t)
	var due: float = w.lifecycle.pregnancies[b.id].due_t
	w._kill(b, "other")
	t.eq(w.lifecycle.pregnancies.size(), 0, "reservation released")
	w.t = due
	w._birth_phase()
	t.eq(w.stats.births, 0, "no orphaned scheduler birth")


func test_pause_does_not_advance_gestation(t) -> void:
	var w := _world()
	var b := w.beings[0]
	w.lifecycle.conceive(b, b.building_id, w.t)
	var before := w.t
	var due: float = w.lifecycle.pregnancies[b.id].due_t
	w.advance(0.0)
	t.eq(w.t, before, "paused simulation time")
	t.eq(w.lifecycle.pregnancies[b.id].due_t, due, "unchanged due date")
	t.eq(w.stats.births, 0, "no paused birth")


func test_children_do_not_enable_construction_or_take_outside_jobs(t) -> void:
	var w := _world()
	var shop := w.buildings.add("workshop", 60, 0, 1.0, 12, 9)
	var b := w.add_being(shop.id, "builder")
	b.born_t = w.t
	for age in [0, 1, 3, 13, 17]:
		w.t = w.lifecycle.birthday(b, age)
		b.state = "idle"
		b.energy = 100.0
		b.decide(w)
		t.check(not b.is_outside(), "age %d stays indoors" % age)
		t.check(not w._builder_ready(), "age %d isn't a construction-ready adult" % age)
	w.t = w.lifecycle.birthday(b, 18)
	t.check(w._builder_ready(), "adult builder can enable construction")


func test_council_uses_the_same_adult_boundary(t) -> void:
	var w := _world()
	var b := w.beings[0]
	b.born_t = w.t
	w.t = w.lifecycle.birthday(b, 18) - w.fixed_step
	t.check(not w.council.is_voice(w, b.id), "no minor voice")
	w.t += w.fixed_step
	t.check(w.council.is_voice(w, b.id), "voice at eighteenth birthday")


func test_counts_are_read_only(t) -> void:
	var w := _world()
	w.beings[0].born_t = w.t
	var state := w.rng._rng.state
	var counts := w.lifecycle.counts(w.beings, w.t)
	t.eq(counts.baby, 1, "one baby")
	t.eq(counts.adult, 1, "one adult")
	t.eq(w.rng._rng.state, state, "no visual/count RNG use")
