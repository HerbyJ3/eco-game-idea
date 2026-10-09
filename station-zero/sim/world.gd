class_name SimWorld
extends RefCounted
## Root of the headless simulation. Advances in fixed steps independent of frame rate.
## Task 0 holds only time and the sky; colony systems arrive in Task 1+.

var rng: SimRng
var clock: Clock
var sky: MarsSky
var persona: Persona
var buildings: Buildings
var powers: Powers
var beings: Array[Being] = []
var colony: Colony
var lifecycle: Lifecycle
## Age system (spec ages.md); announce only. `ages_enabled` false skips the sol hook (test seam).
var ages: Ages
var ages_enabled := true
## Relationships and trust (spec relationships.md); reads the world, writes only itself, stats.relationships and the log.
## `relationships_enabled` false skips both hooks (test seam).
var relationships: Relationships
var relationships_enabled := true
var council: Council
var council_enabled := true
var resources: Resources
## Phase 5 scouting. On for founder worlds; blank test worlds start with it off so that tests that
## count rng draws are not disturbed (spec step 5 notes).
var scouting_enabled := false
var t: float
var step_index := 0
## Event log, newest last, capped at colony.log_cap. Entries: {t, sol, kind, text, being_id?}.
var log: Array = []
## Run-wide counters (spec section 16). Never derived from the log.
var stats: Dictionary = {}
var _next_being_id := 1
var _log_cap: int
## Earth-born founders: [{born, lon, chart, persona}]. Charts stay inside the sim.
var founders: Array = []
var fixed_step: float
var max_steps_per_advance: int
var _accum := 0.0
## Wall-time budget of one advance() call, ms (data sim.json advance_budget_ms). View path only.
var advance_budget_ms: float
## Injected monotonic millisecond clock (Callable returning int); invalid means the engine tick counter. Tests inject a
## fake; it must not capture this world (no reference cycle).
var now_ms: Callable = Callable()
## Sim hours dropped by advance() when the budget or the cap stopped it. Never in stats, the log or hashed state.
var advance_dropped_h := 0.0
## Phase 8 interval accumulator (spec section 3).
var _build_acc := 0.0
## Next elapsed-sol boundary (n) whose first step resets shorts_this_sol.
var _next_sol_boundary := 1
## True on the step that starts a new sol (feeds the sol-boundary samples in phase 11).
var _sol_started := false
## Float slack so 0.05-hour steps add up to whole hours.
const STEP_EPS := 1e-9
## Fields kept in stats.window (spec section 16). Sums and maxima restart at 0, minima at null.
## Measurement definitions (spec section 16), not tunables: stock minima count from sol 5, ice from 30.
const STATS_FROM_SOL := 5
const STATS_ICE_FROM_SOL := 30
const WINDOW_ZERO_KEYS := ["max_shorts_per_sol", "max_offline_h", "max_sleep_h", "being_steps",
		"asleep_being_steps", "energy_sum", "demand_over_steps", "step_count", "sol_samples",
		"reachable_ok_samples", "hours_waiting_regolith", "hours_site_no_crew", "site_busy_h",
		"max_ice_over_target", "max_regolith_over_target"]
const WINDOW_NULL_KEYS := ["min_pop", "min_oxygen", "min_food", "min_ice", "min_ice_after30"]


## `options.blank = true` builds an empty world (no founders) for tests, which then use
## add_building, add_being and direct field writes.
func _init(seed_in: Variant = null, options: Dictionary = {}) -> void:
	var cfg := SimData.sim()
	rng = SimRng.new(int(seed_in) if seed_in != null else int(cfg.default_seed))
	max_steps_per_advance = int(cfg.max_steps_per_frame)
	advance_budget_ms = float(cfg.advance_budget_ms)
	clock = Clock.new()
	sky = MarsSky.new(clock)
	persona = Persona.new()
	fixed_step = cfg.fixed_step_hours
	t = clock.start_hour
	buildings = Buildings.new()
	buildings.now = t
	powers = Powers.new(buildings)
	buildings.powers = powers
	colony = Colony.new(beings, buildings, rng, clock.sol_h)
	lifecycle = Lifecycle.new()
	resources = Resources.new(buildings, rng)
	ages = Ages.new()
	relationships = Relationships.new()
	council = Council.new()
	_log_cap = int(SimData.colony().log_cap)
	_init_stats()
	if not options.get("blank", false):
		scouting_enabled = true
		buildings.create_layout()
		_create_founders()
		resources.spawn_founder_sites()
		_log("founders_landed", "%d founders landed." % founders.size())
		stats.pop_by_sol.append(colony.pop())
		ages.begin(self, true)
		relationships.begin(self, true)
		council.begin(self, true)
	else:
		ages.begin(self, false)
		relationships.begin(self, false)
		council.begin(self, false)


func _init_stats() -> void:
	stats = {
		"births": 0,
		"deaths": {"air": 0, "thirst": 0, "hunger": 0, "suffocated_outside": 0, "other": 0},
		"deaths_list": [],
		"deaths_unexplained": 0,
		"shorts": 0, "reonlines": 0, "mining_trips": 0, "turn_backs_air": 0,
		"turn_backs_exhausted": 0, "builds_started": 0, "builds_finished": 0,
		"need_regolith": 0, "waiting_for_builders": 0, "ice_dry": 0, "scouts_found": 0,
		"founder_role_miss": 0, "births_at_capacity": 0, "cooldown_violations": 0,
		"shorts_this_sol": 0, "max_shorts_per_sol": 0, "max_offline_h": 0.0,
		"demand_over_steps": 0, "step_count": 0,
		"sol_samples": 0, "reachable_ok_samples": 0,
		"hours_waiting_regolith": 0.0, "hours_site_no_crew": 0.0, "site_busy_h": 0.0,
		"first_new_reactor_sol": null, "first_birth_sol": null,
		"being_steps": 0, "asleep_being_steps": 0, "energy_sum": 0.0, "max_sleep_h": 0.0,
		"pop_by_sol": [], "min_pop": null,
		"min_oxygen": null, "min_food": null, "min_ice": null, "min_ice_after30": null,
		"max_ice_over_target": 0.0, "max_regolith_over_target": 0.0,
		"age": Ages.LANDING, "age_changes": 0, "sols_in_age": {Ages.LANDING: 0, Ages.SETTLEMENT: 0, "council": 0},
		"first_settlement_sol": null, "age_history": [],
		"relationships": Relationships.new_stats(),
		"council": Council.new_stats(),
	}
	reset_window()


## Starts a fresh balance window (spec section 16). `stats.window` holds the windowed measured
## fields; the run-wide copies in `stats` are never reset. A Dictionary has no methods, so this is
## SimWorld.reset_window() rather than stats.reset_window().
func reset_window() -> void:
	var win := {}
	stats["window"] = win
	for k in WINDOW_ZERO_KEYS:
		win[k] = 0.0 if stats[k] is float else 0
	for k in WINDOW_NULL_KEYS:
		win[k] = null


## Applies a measured value to the run-wide field and to the current window.
func _stat_add(key: String, delta: float) -> void:
	stats[key] += delta
	stats.window[key] += delta


func _stat_max(key: String, v: float) -> void:
	stats[key] = maxf(float(stats[key]), v)
	stats.window[key] = maxf(float(stats.window[key]), v)


func _stat_min(key: String, v: float) -> void:
	stats[key] = v if stats[key] == null else minf(float(stats[key]), v)
	stats.window[key] = v if stats.window[key] == null else minf(float(stats.window[key]), v)


## Elapsed sols since start_hour; sol 0 is the first (spec section 3).
func sol() -> int:
	return int(floor((t - clock.start_hour + STEP_EPS) / clock.sol_h))


func _log(kind: String, text: String, extra: Dictionary = {}) -> void:
	var e := {"t": t, "sol": sol(), "clock_sol": clock.sol_index(t), "kind": kind, "text": text}
	e.merge(extra)
	log.append(e)
	if log.size() > _log_cap:
		log.pop_front()


## Test seam: adds a building (finished by default) and returns its id.
func add_building(kind: String, tx: int = 0, ty: int = 0, built: float = 1.0) -> int:
	return buildings.add(kind, tx, ty, built).id


func set_offline(building_id: int, offline: bool) -> void:
	var b := buildings.get_building(building_id)
	b.offline = offline
	b.offline_since = t if offline else null


## Test seam: a neutral-persona adult placed in a building, energy drawn from the world rng.
func add_being(building_id: int, role: String = "builder") -> Being:
	var b := Being.new()
	b.id = _next_being_id
	_next_being_id += 1
	b.persona = Being.flat_persona(role)
	b.role = role
	b.name = Being.make_name(rng)
	b.born_t = lifecycle.add_months(t, -int(lifecycle.cfg.adult_age_years) * Lifecycle.MONTHS_PER_YEAR)
	var e: Array = SimData.beings().energy.start
	b.energy = rng.randf_range(float(e[0]), float(e[1]))
	b.building_id = building_id
	beings.append(b)
	return b


func _kill(b: Being, cause: String) -> void:
	beings.erase(b)
	lifecycle.remove_being(b.id)
	var key := cause.replace(" ", "_")
	stats.deaths[key] = int(stats.deaths.get(key, 0)) + 1
	var shortage := cause in ["air", "thirst", "hunger"]
	var known := shortage or cause == "suffocated outside"
	if not known or (shortage and colony.oxygen > 0.0 and colony.ice > 0.0 and colony.food > 0.0):
		stats.deaths_unexplained += 1
	stats.deaths_list.append({"t": t, "sol": sol(), "clock_sol": clock.sol_index(t), "being_id": b.id, "name": b.name, "cause": cause})
	_log("died", "%s died (%s)." % [b.name, cause], {"being_id": b.id, "cause": cause})


func _create_founders() -> void:
	var cfg: Dictionary = SimData.persona().founders
	var bc: Dictionary = SimData.beings()
	var layout: Array = bc.founders.layout
	var homes := {}
	for b in buildings.list:
		if not homes.has(b.kind):
			homes[b.kind] = b.id
	for i in int(cfg.count):
		# Redraw the whole founder birth until the persona's role matches the layout slot (A1).
		var birth := {}
		var matched := false
		for k in int(bc.founders.role_retry_tries):
			birth = sky.founder_birth(rng, cfg)
			birth["persona"] = persona.persona_from(birth.chart)
			if birth.persona.role == layout[i].role:
				matched = true
				break
		if not matched:
			stats.founder_role_miss += 1
		founders.append(birth)
		var b := Being.new()
		b.id = _next_being_id
		_next_being_id += 1
		b.persona = birth.persona
		b.role = birth.persona.role
		b.earth_born = true
		b.name = Being.make_name(rng)
		b.born_t = birth.born
		var es: Array = bc.energy.start
		b.energy = rng.randf_range(float(es[0]), float(es[1]))
		var iw: Array = bc.initial_wait_h
		b.wait_h = rng.randf_range(float(iw[0]), float(iw[1]))
		b.building_id = homes[layout[i].home]
		beings.append(b)


## Advance by `hours` of sim time using whole fixed steps. Returns steps taken.
## Wall-time budget (spec ages.md section 11): reads now_ms at entry and after each step and stops when the elapsed
## time reaches advance_budget_ms; at least one step runs whenever one is due, so a call may overshoot by one step.
## max_steps_per_advance is a hard cap. When the loop stops with a step still due, the accumulator is added to
## advance_dropped_h and zeroed (dropped, never carried). The steps themselves are unchanged.
func advance(hours: float) -> int:
	_accum += hours
	var steps := 0
	var budget_ms := float(advance_budget_ms)
	var start_ms := _read_ms()
	while _accum >= fixed_step - STEP_EPS:
		if steps >= max_steps_per_advance:
			_drop_accum()
			break
		step()
		_accum -= fixed_step
		steps += 1
		if _accum >= fixed_step - STEP_EPS and float(_read_ms() - start_ms) >= budget_ms:
			_drop_accum()
			break
	return steps


func _drop_accum() -> void:
	advance_dropped_h += _accum
	_accum = 0.0


func _read_ms() -> int:
	return now_ms.call() if now_ms.is_valid() else Time.get_ticks_msec()


## One fixed step. Phase order: spec section 5 (phases not yet built are absent).
func step() -> void:
	t += fixed_step
	buildings.now = t
	step_index += 1
	colony.step_stocks(fixed_step)
	_sol_boundary()
	_manage_power()
	for w in colony.air_food_warnings(t):
		_log(w.kind, w.text)
	for w in colony.drain_ice(t, fixed_step):
		_log(w.kind, w.text)
	if scouting_enabled and resources.scout(fixed_step) != null:
		stats.scouts_found += 1
		_log("scouts_found", "Scouts found a new ice field.")
	_update_beings()
	_birth_phase()
	_build_decision()
	_construction_progress()
	var death := colony.shortage_check(fixed_step)
	if not death.is_empty():
		_kill(death.victim, death.cause)
	var silent := colony.pop() == 0
	if silent and not colony.extinct:
		_log("colony_silent", "The colony has fallen silent.")
	colony.extinct = silent
	resources.expire_footprints(t, float(SimData.suits().footprint.fade_sols) * clock.sol_h)
	_sample_power_stats()
	_sample_being_stats()
	# Phase 11b: relationship tick, once per relationships.tick_h (spec relationships.md section 4).
	if relationships_enabled and relationships != null:
		relationships.on_step(self, fixed_step)
	if council_enabled and council != null:
		council.on_step(self)
	if _sol_started:
		stats.pop_by_sol.append(colony.pop())
		_stat_add("sol_samples", 1)
		if resources.reachable_ice_count() >= int(SimData.resources().scout.min_reachable):
			_stat_add("reachable_ok_samples", 1)
		# Phase 11 (age sample): the last thing a sol boundary does (spec ages.md 4.1).
		if ages_enabled:
			ages.on_sol(self)
		if relationships_enabled and relationships != null:
			relationships.on_sol(self)
		if council_enabled and council != null:
			council.on_sol(self)


## Removes up to `amount` ice from a field and returns what was taken. A field that runs dry leaves
## the list (once), is logged, and if fewer than two fields are reachable a new one is spawned at
## once (spec 8.3).
func take_ice(field: Resources.Site, amount: float) -> float:
	if not resources.ice_fields.has(field):
		return 0.0
	var taken := minf(amount, field.amount)
	field.amount -= taken
	if field.amount <= 0.0:
		field.amount = 0.0
		resources.ice_fields.erase(field)
		stats.ice_dry += 1
		_log("ice_dry", "An ice field has run dry.")
		if resources.respawn_if_short() != null:
			_log("ice_found", "Scouts found a new ice field.")
	return taken


## First step with t - start_hour >= n x sol_hours - STEP_EPS starts sol n (spec section 3).
## Done before phase 3 so a short on the boundary step counts in the new sol.
func _sol_boundary() -> void:
	_sol_started = false
	if t - clock.start_hour >= _next_sol_boundary * clock.sol_h - STEP_EPS:
		_next_sol_boundary += 1
		stats.shorts_this_sol = 0
		_sol_started = true


## Phase 3: apply one short or re-online, then log and count it.
func _manage_power() -> void:
	var ev := buildings.manage_power(t, rng)
	if ev.is_empty():
		return
	var b: Buildings.Building = ev.building
	var label: String = buildings.cfg.kinds[b.kind].label
	if ev.kind == "short":
		stats.shorts += 1
		stats.shorts_this_sol += 1
		_stat_max("max_shorts_per_sol", float(stats.shorts_this_sol))
		_log("short", "%s shorted out." % label, {"building_id": b.id})
	else:
		stats.reonlines += 1
		_stat_max("max_offline_h", float(ev.offline_h))
		_log("back_online", "%s is back online." % label, {"building_id": b.id})


## Phase 11 (power part).
func _sample_power_stats() -> void:
	_stat_add("step_count", 1)
	if buildings.demand() > buildings.supply():
		_stat_add("demand_over_steps", 1)
	for b in buildings.list:
		if b.offline and b.offline_since != null:
			_stat_max("max_offline_h", t - float(b.offline_since))


## Phase 6: every being alive at the start of the phase, ascending id.
func _update_beings() -> void:
	for b in beings.duplicate():
		if beings.has(b):
			b.update(self, fixed_step)


## Phase 11 (being part).
func _sample_being_stats() -> void:
	for b in beings:
		_stat_add("being_steps", 1)
		_stat_add("energy_sum", b.energy)
		if b.state == "sleep":
			_stat_add("asleep_being_steps", 1)
			_stat_max("max_sleep_h", t - float(b.sleep_started_t))
	_stat_min("min_pop", float(beings.size()))
	var elapsed := sol()
	if elapsed >= STATS_FROM_SOL:
		_stat_min("min_oxygen", colony.oxygen)
		_stat_min("min_food", colony.food)
		_stat_min("min_ice", colony.ice)
	if elapsed >= STATS_ICE_FROM_SOL:
		_stat_min("min_ice_after30", colony.ice)
	_stat_max("max_ice_over_target", colony.ice / colony.ice_target())
	_stat_max("max_regolith_over_target", colony.regolith / colony.regolith_target())


# ---------------------------------------------------------------- construction (spec 7.4, 7.5)

## Spec 7.4. What to build next, first match wins. Only the last rule draws from the rng.
func choose_kind() -> String:
	var bc: Dictionary = buildings.cfg.choose
	var cc: Dictionary = SimData.colony()
	if buildings.margin() < float(bc.reactor_margin):
		return "reactor"
	var pop := colony.pop()
	# Three sols of use at the current population (A5 floor).
	var floor_h := float(cc.stock_days_floor_sols) * clock.sol_h * pop
	if colony.o2_net() < float(bc.o2_net_floor) or colony.food_net() < float(bc.food_net_floor) \
			or colony.oxygen < floor_h * float(cc.consumption.o2_per_being) \
			or colony.food < floor_h * float(cc.consumption.food_per_being):
		return "green_room"
	var habitats := 0
	var workshops := 0
	for b in buildings.list:
		if b.finished() and b.kind == "habitat":
			habitats += 1
		elif b.finished() and b.kind == "workshop":
			workshops += 1
	if pop + int(bc.crowd_margin) > int(cc.birth.habitat_capacity) * habitats:
		return "habitat"
	var pool: Array = bc.pool.duplicate()
	if workshops < int(bc.workshop_cap):
		pool.append("workshop")
	return rng.pick(pool)


## Breaks ground: false and nothing changed if a site exists, the regolith is short, or no spot is
## found. `spot` ({parent_id, dir, tw, th, gap}) is the test seam; empty means find_spot (spec 7.3).
func start_site(kind: String, spot: Dictionary = {}) -> bool:
	if buildings.site != null:
		return false
	var cost := buildings.build_cost(kind)
	if colony.regolith < cost:
		return false
	var where := spot if not spot.is_empty() else buildings.find_spot(rng)
	if where.is_empty():
		return false
	var s := buildings.create_site(kind, where, t)
	colony.regolith -= cost
	stats.builds_started += 1
	_log("ground_broken", "Ground broken for a new %s." % buildings.cfg.kinds[kind].label.to_lower(),
			{"building_id": s.building_id})
	return true


## A builder is ready when one is inside (a sleeper counts) an online workshop.
func _builder_ready() -> bool:
	for b in beings:
		if b.role != "builder" or not b.is_inside() or not lifecycle.is_adult(b, t):
			continue
		var home := buildings.get_building(b.building_id)
		if home != null and home.kind == "workshop" and home.online():
			return true
	return false


## Phase 8: every build.check_interval_h.
func _build_decision() -> void:
	var bd: Dictionary = buildings.cfg.build
	_build_acc += fixed_step
	if _build_acc < float(bd.check_interval_h) - STEP_EPS:
		return
	_build_acc = 0.0
	if buildings.site != null or not _builder_ready():
		return
	var kind := choose_kind()
	if colony.regolith < buildings.build_cost(kind):
		_stat_add("hours_waiting_regolith", float(bd.check_interval_h))
		if colony.need_regolith_due(t):
			stats.need_regolith += 1
			_log("need_regolith", "More regolith is needed to build.")
		return
	start_site(kind)


## Phase 9: progress from the crew, completion, and the waiting warning.
func _construction_progress() -> void:
	var site := buildings.site
	if site == null:
		return
	var sb := buildings.get_building(site.building_id)
	var crew: Array[Being] = []
	for b in beings:
		if b.state == "work" and b.job == site:
			crew.append(b)
	_stat_add("site_busy_h", fixed_step)
	if crew.is_empty():
		_stat_add("hours_site_no_crew", fixed_step)
		var idle_h := float(buildings.cfg.build.waiting_site_idle_sols) * clock.sol_h
		if t - site.last_work_t > idle_h + STEP_EPS and colony.waiting_due(t):
			stats.waiting_for_builders += 1
			_log("waiting_for_builders", "The building site is waiting for builders.",
					{"building_id": sb.id})
		return
	site.last_work_t = t
	var bc: Dictionary = buildings.cfg.construction
	var ef: Dictionary = SimData.beings().effort
	var rate := 0.0
	for b in crew:
		rate += (float(bc.drive_base) + float(b.persona.traits.drive)) \
				* (float(ef.energy_base) + b.energy / float(ef.energy_divisor))
	sb.built = minf(1.0, sb.built + rate * fixed_step / float(bc.denominator_h))
	if sb.built < 1.0:
		return
	stats.builds_finished += 1
	_log("building_done", "A new %s is finished." % buildings.cfg.kinds[sb.kind].label.to_lower(),
			{"building_id": sb.id})
	if sb.kind == "reactor" and stats.first_new_reactor_sol == null:
		stats.first_new_reactor_sol = sol()
	buildings.site = null
	for b in crew:
		b.enter(self, sb.id)


# ---------------------------------------------------------------- births (spec 10.1)

## Phase 7: deliver due pregnancies, then check adult conception eligibility every check_interval_h.
## Pending pregnancies reserve population capacity. Newborn draws happen at delivery, not conception.
func _birth_phase() -> void:
	_deliver_births()
	if not colony.birth_check_due(fixed_step):
		return
	for hb in buildings.list.duplicate():
		if hb.kind != "habitat" or not hb.finished() or not hb.online():
			continue
		var here: Array = []
		for b in beings:
			if b.building_id == hb.id and b.is_inside() and lifecycle.can_conceive(b, t):
				here.append(b)
		if here.is_empty() or not colony.birth_gates_ok(hb.id, here, t, lifecycle.pregnancies.size()):
			continue
		if not lifecycle.conception_cooldown_over(hb.id, t, colony.birth_cooldown_h()):
			continue
		if not rng.chance(colony.birth_chance(here)):
			continue
		var parent: Being = rng.pick(here)
		lifecycle.conceive(parent, hb.id, t)
		# Zero gestation is an explicit fixture for tests of the independent birth gates and newborn fields.
		if int(lifecycle.cfg.pregnancy_months) == 0:
			_deliver_births()
		else:
			_log("pregnant", "%s is expecting a baby." % parent.name,
					{"being_id": parent.id, "building_id": hb.id})


func _deliver_births() -> void:
	for record in lifecycle.due(t):
		var parent: Being = null
		for b in beings:
			if b.id == int(record.parent_id):
				parent = b
				break
		var home := buildings.get_building(int(record.building_id))
		if parent == null or home == null:
			lifecycle.pregnancies.erase(record.parent_id)
			continue
		# Respect the existing per-home postpartum cooldown when several dates converge at month-end.
		if not colony.birth_cooldown_over(home.id, t):
			continue
		lifecycle.pregnancies.erase(record.parent_id)
		_create_newborn(home, parent)


func _create_newborn(hb: Buildings.Building, parent: Being = null) -> void:
	var bc: Dictionary = SimData.beings()
	var nb := Being.new()
	nb.id = _next_being_id
	_next_being_id += 1
	nb.persona = persona.persona_from(sky.mars_chart(t, clock.lon_of_tile(hb.tx + hb.tw / 2.0)))
	nb.role = nb.persona.role
	nb.earth_born = false
	nb.born_t = t
	nb.name = Being.make_name(rng)
	var es: Array = bc.energy.start
	nb.energy = rng.randf_range(float(es[0]), float(es[1]))
	var iw: Array = bc.initial_wait_h
	nb.wait_h = rng.randf_range(float(iw[0]), float(iw[1]))
	nb.building_id = hb.id
	nb.parent_id = parent.id if parent != null else 0
	nb.birth_building_id = hb.id
	# Invariant counters (must stay 0): the gates make both unreachable.
	if colony.pop() >= colony.birth_capacity():
		stats.births_at_capacity += 1
	if not colony.birth_cooldown_over(hb.id, t) and colony.last_birth_t.has(hb.id):
		stats.cooldown_violations += 1
	beings.append(nb)
	colony.last_birth_t[hb.id] = t
	stats.births += 1
	if stats.first_birth_sol == null:
		stats.first_birth_sol = sol()
	_log("born", "%s was born." % nb.name, {"being_id": nb.id, "building_id": hb.id})


# ---------------------------------------------------------------- mining (spec 8.2)

## Which site a miner heads for, or null. Lives here (not in Resources) because it reads the colony
## stocks and the rng. Draws one chance only when ice >= ice_urgent_below and live ice fields exist,
## then one pick of the pool.
func choose_site() -> Resources.Site:
	var wn: Dictionary = SimData.resources().want
	var limit := resources.trip_limit()
	var live_ice: Array[Resources.Site] = []
	for f in resources.ice_fields:
		if f.amount > 0.0 and resources.trip_time(f) < limit:
			live_ice.append(f)
	var live_pits: Array[Resources.Site] = []
	for p in resources.pits:
		if resources.trip_time(p) < limit:
			live_pits.append(p)
	var ice_target := colony.ice_target()
	var reg_target := colony.regolith_target()
	var ice_need := 1.0 - minf(1.0, colony.ice / ice_target)
	var reg_need := 1.0 - minf(1.0, colony.regolith / reg_target)
	var want_ice := colony.ice < float(wn.ice_urgent_below)
	if not want_ice and not live_ice.is_empty():
		want_ice = rng.chance((ice_need + float(wn.ice_bias)) / (ice_need + reg_need + float(wn.need_sum_bias)))
	var pool: Array[Resources.Site] = live_ice
	var is_ice := true
	if not (want_ice and not live_ice.is_empty()) and not live_pits.is_empty():
		pool = live_pits
		is_ice = false
	if pool.is_empty():
		return null
	if is_ice and colony.ice > float(wn.stop_factor) * ice_target:
		return null
	if not is_ice and colony.regolith > float(wn.stop_factor) * reg_target:
		return null
	return rng.pick(pool)
