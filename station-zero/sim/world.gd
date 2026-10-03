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
## Next elapsed-sol boundary (n) whose first step resets shorts_this_sol.
var _next_sol_boundary := 1
## True on the step that starts a new sol (feeds the sol-boundary samples in phase 11).
var _sol_started := false
## Float slack so 0.05-hour steps add up to whole hours.
const STEP_EPS := 1e-9


## `options.blank = true` builds an empty world (no founders) for tests, which then use
## add_building, add_being and direct field writes.
func _init(seed_in: Variant = null, options: Dictionary = {}) -> void:
	var cfg := SimData.sim()
	rng = SimRng.new(int(seed_in) if seed_in != null else int(cfg.default_seed))
	max_steps_per_advance = int(cfg.max_steps_per_frame)
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
	resources = Resources.new(buildings, rng)
	_log_cap = int(SimData.colony().log_cap)
	_init_stats()
	if not options.get("blank", false):
		scouting_enabled = true
		buildings.create_layout()
		_create_founders()
		resources.spawn_founder_sites()
		_log("founders_landed", "%d founders landed." % founders.size())


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
	}


## Elapsed sols since start_hour; sol 0 is the first (spec section 3).
func sol() -> int:
	return int(floor((t - clock.start_hour + STEP_EPS) / clock.sol_h))


func _log(kind: String, text: String, extra: Dictionary = {}) -> void:
	var e := {"t": t, "sol": sol(), "kind": kind, "text": text}
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


## Test seam: a neutral-persona being placed in a building, energy drawn from the world rng.
func add_being(building_id: int, role: String = "builder") -> Being:
	var b := Being.new()
	b.id = _next_being_id
	_next_being_id += 1
	b.persona = Being.flat_persona(role)
	b.role = role
	b.name = Being.make_name(rng)
	b.born_t = t
	var e: Array = SimData.beings().energy.start
	b.energy = rng.randf_range(float(e[0]), float(e[1]))
	b.building_id = building_id
	beings.append(b)
	return b


func _kill(b: Being, cause: String) -> void:
	beings.erase(b)
	var key := cause.replace(" ", "_")
	stats.deaths[key] = int(stats.deaths.get(key, 0)) + 1
	stats.deaths_list.append({"t": t, "sol": sol(), "being_id": b.id, "name": b.name, "cause": cause})
	_log("died", "%s died (%s)." % [b.name, cause], {"being_id": b.id, "cause": cause})


func _create_founders() -> void:
	var cfg: Dictionary = SimData.persona().founders
	for i in int(cfg.count):
		var birth := sky.founder_birth(rng, cfg)
		birth["persona"] = persona.persona_from(birth.chart)
		founders.append(birth)


## Advance by `hours` of sim time using whole fixed steps. Returns steps taken.
## At most max_steps_per_advance steps per call; leftover time is dropped so a hitch can't stall.
func advance(hours: float) -> int:
	_accum += hours
	var steps := 0
	while _accum >= fixed_step - STEP_EPS:
		if steps >= max_steps_per_advance:
			_accum = 0.0
			break
		step()
		_accum -= fixed_step
		steps += 1
	return steps


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
	var death := colony.shortage_check(fixed_step)
	if not death.is_empty():
		_kill(death.victim, death.cause)
	var silent := colony.pop() == 0
	if silent and not colony.extinct:
		_log("colony_silent", "The colony has fallen silent.")
	colony.extinct = silent
	_sample_power_stats()
	if _sol_started:
		stats.sol_samples += 1
		if resources.reachable_ice_count() >= int(SimData.resources().scout.min_reachable):
			stats.reachable_ok_samples += 1


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
		stats.max_shorts_per_sol = maxi(int(stats.max_shorts_per_sol), int(stats.shorts_this_sol))
		_log("short", "%s shorted out." % label, {"building_id": b.id})
	else:
		stats.reonlines += 1
		stats.max_offline_h = maxf(float(stats.max_offline_h), float(ev.offline_h))
		_log("back_online", "%s is back online." % label, {"building_id": b.id})


## Phase 11 (power part).
func _sample_power_stats() -> void:
	stats.step_count += 1
	if buildings.demand() > buildings.supply():
		stats.demand_over_steps += 1
	for b in buildings.list:
		if b.offline and b.offline_since != null:
			stats.max_offline_h = maxf(float(stats.max_offline_h), t - float(b.offline_since))
