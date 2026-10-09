class_name Being
extends RefCounted
## One being. Spec: life-support-power.md section 4 (Being). Only the fields the colony needs are
## used so far; the rest are declared so later steps (state machine, EVA, mining) just fill them in.

var id: int
var name: String
## Persona.persona_from shape: {traits, role, description}.
var persona: Dictionary
var role: String
var earth_born := false
## Birth record (state only, set in SimWorld._create_newborn): the parent picked for the birth, 0 for
## founders and test-seam beings or when no being was picked; the habitat id of the birth.
var parent_id := 0
var birth_building_id := 0
var born_t: float
var energy: float
## idle, to_door, transit, sleep, eva, work, mining.
var state := "idle"
## The building it is in (or left from while in transit or outside). No x,y inside.
var building_id: int
var wait_h := 0.0
var sleep_intent := false
var suit_up := false
var job: Variant = null
var mine: Variant = null
var mine_intent: Variant = null
## Null unless outside.
var air_h: Variant = null
var x: Variant = null
var y: Variant = null
var heading: Variant = null
var path: Variant = null
var after: Variant = null
var returning := false
var load := 0.0
var work_left_h := 0.0
var step_acc_px := 0.0
var foot_side := 1
var corridor_id: Variant = null
var transit_t := 0.0
var from_a := false
var sleep_started_t: Variant = null
## Where a working or mining being is heading inside its area (spec 7.5).
var wander_target := Vector2.ZERO
## True from a builder's suit-up until it enters a building: the suit is kept for the walk home
## after the shift, even though `job` is already null (step 7 notes).
var construction_suit := false
## When the last `suit_low_air` line was logged for this being (guard for the repeat interval).
var _low_air_logged_t := -1e9


## What the view draws (spec section 4): none inside; construction for a builder's suit, from
## suit-up until entering; eva for any other outside state. A job alone also marks a builder
## outside.
func suit_kind() -> String:
	match state:
		"eva", "work", "mining":
			return "construction" if construction_suit or job != null else "eva"
	return "none"


## Outside means one of the suited states (spec section 4).
func is_outside() -> bool:
	return state == "eva" or state == "work" or state == "mining"


## The lamp is on only outside and at night (spec A10).
func lamp_on(w: SimWorld) -> bool:
	return is_outside() and is_night(w)


## True while the being is in a building (sleepers count). Used by shortage victims and births.
func is_inside() -> bool:
	var s := state
	return s != "transit" and s != "eva" and s != "work" and s != "mining"


## ---------------------------------------------------------------- tunables (data/beings.json)

func _cfg() -> Dictionary:
	return SimData.beings()


func _trait(trait_name: String) -> float:
	return float(persona.traits[trait_name])


## Energy drain per hour of the current state (spec 6.1). Sleep does not drain.
func drain_per_h() -> float:
	var e: Dictionary = _cfg().energy
	match state:
		"sleep":
			return 0.0
		"eva":
			return float(e.drain_eva)
		"mining":
			return float(e.drain_mining)
		"work":
			return float(e.drain_work)
	return float(e.drain_idle)


## Drive speeds up every walk: 0.75 + 0.5 drive (spec 6.6).
func _walk_factor() -> float:
	var w: Dictionary = _cfg().walk
	return float(w.drive_base) + float(w.drive_coef) * _trait("drive")


## Interior timing (spec 6.2): a walk inside a building plus a pause.
func idle_wait(rng: SimRng) -> float:
	var c := _cfg()
	var px := rng.randf_range(float(c.walk.interior_walk_px[0]), float(c.walk.interior_walk_px[1]))
	var walk := px / (float(c.walk.interior_px_h) * _walk_factor())
	var pause := rng.randf_range(float(c.pause.base_h[0]), float(c.pause.base_h[1])) \
			* (float(c.pause.steady_base) + float(c.pause.steady_coef) * _trait("steady"))
	return walk + pause


## Time to walk to a door inside a building (spec 6.2).
func door_time(rng: SimRng) -> float:
	var c := _cfg()
	var px := rng.randf_range(float(c.walk.interior_walk_px[0]), float(c.walk.interior_walk_px[1]))
	return px / (float(c.walk.door_px_h) * _walk_factor())


## Night on the Mars clock at the world's current t (spec section 3).
static func is_night(w: SimWorld) -> bool:
	var h := w.clock.mars_hour(w.t)
	var n: Dictionary = SimData.beings().night
	return h >= float(n.start_hour) or h < float(n.end_hour)


## ---------------------------------------------------------------- phase 6 (spec 6.3)

## One being's update for one step (spec 6.3): drain, exhausted check, air tick and low-air check,
## then the state arm.
func update(w: SimWorld, dt: float) -> void:
	var e: Dictionary = _cfg().energy
	if state == "sleep":
		_sleep_step(w, dt)
		return
	energy = clampf(energy - drain_per_h() * dt, 0.0, float(e.max))
	if is_outside():
		if _can_turn_back() and energy < float(e.exhausted_turn_back):
			_turn_back(w, "exhausted")
		if not _air_tick(w, dt):
			return
	match state:
		"transit":
			_transit_step(w, dt)
		"eva":
			_eva_step(w, dt)
		"work":
			_work_step(w, dt)
		"mining":
			_mining_step(w, dt)
		"idle":
			wait_h -= dt
			if wait_h <= SimWorld.STEP_EPS:
				decide(w)
		"to_door":
			wait_h -= dt
			if wait_h <= SimWorld.STEP_EPS:
				_door_action(w)


func _sleep_step(w: SimWorld, dt: float) -> void:
	var e: Dictionary = _cfg().energy
	var gain := float(e.sleep_gain_fed) if w.colony.food > 0.0 else float(e.sleep_gain_starving)
	energy = minf(float(e.max), energy + gain * dt)
	# The chance is drawn only by day above day_wake_above and below wake_at (short-circuit).
	if energy >= float(e.wake_at) or (not is_night(w) and energy > float(e.day_wake_above) \
			and w.rng.chance(float(e.day_wake_chance_per_h) * dt)):
		state = "idle"
		sleep_started_t = null
		wait_h = idle_wait(w.rng)


func _transit_step(w: SimWorld, dt: float) -> void:
	var c: Buildings.Building = w.buildings.get_building(int(corridor_id))
	transit_t += dt * float(_cfg().tunnel_speed_px_h) / maxf(1.0, float(c.corridor.len))
	if transit_t >= 1.0:
		# The "a" end is p1, the parent side: from_a walks parent to child.
		enter(w, c.id if from_a else int(c.corridor.parent_id))


## Arrival inside a building (spec 6.5b `enter`): the suit is off and everything outside resets.
## Also the end of a tunnel walk, where those fields are already clear.
func enter(w: SimWorld, to_building: int) -> void:
	returning = false
	air_h = null
	job = null
	path = null
	x = null
	y = null
	heading = null
	construction_suit = false
	building_id = to_building
	state = "idle"
	wait_h = w.fixed_step if sleep_intent else idle_wait(w.rng)


## When to_door elapses (spec 6.2 order): (a) miner suit-up at the building door, (b) builder
## suit-up at the corridor end p1, (c) enter the tunnel.
func _door_action(w: SimWorld) -> void:
	if suit_up and mine != null:
		_suit_up_miner(w)
		return
	if suit_up and job != null:
		_suit_up_builder(w)
		return
	var c: Buildings.Building = w.buildings.get_building(int(corridor_id))
	state = "transit"
	transit_t = 0.0
	from_a = int(c.corridor.parent_id) == building_id


func _enter_sleep(w: SimWorld) -> void:
	state = "sleep"
	sleep_intent = false
	sleep_started_t = w.t


## Sleep in the nearest online habitat, or on the floor (spec 6.1).
func go_sleep(w: SimWorld) -> void:
	var h := w.buildings.nearest_online_habitat(building_id)
	if h == null or h.id == building_id:
		_enter_sleep(w)
		return
	var hop := w.buildings.next_hop(building_id, h.id)
	if hop == 0:
		_enter_sleep(w)
		return
	sleep_intent = true
	corridor_id = hop
	state = "to_door"
	wait_h = door_time(w.rng)


## Spec 6.4: sleep, join construction, resume a mine intent, new mining attempt, restless travel.
func decide(w: SimWorld) -> void:
	var e: Dictionary = _cfg().energy
	var go := sleep_intent or energy < float(e.sleep_below)
	if not go and is_night(w) and energy < float(e.night_sleep_below):
		go = w.rng.chance(float(e.night_sleep_chance))
	if go:
		go_sleep(w)
		return
	if _try_join_construction(w):
		return
	if _resume_mine_intent(w):
		return
	if _try_new_mining(w):
		return
	if _restless_travel(w):
		return
	wait_h = idle_wait(w.rng)


## Neighbours of the current building over finished corridors, in corridor creation order:
## [{corridor: child building id, to: Building}].
func _neighbours(w: SimWorld) -> Array:
	var out: Array = []
	for b in w.buildings.list:
		if b.corridor == null or not b.finished():
			continue
		if b.id == building_id:
			out.append({"corridor": b.id, "to": w.buildings.get_building(int(b.corridor.parent_id))})
		elif int(b.corridor.parent_id) == building_id:
			out.append({"corridor": b.id, "to": b})
	return out


func _restless_travel(w: SimWorld) -> bool:
	var nb := _neighbours(w)
	if nb.is_empty():
		return false
	var r: Dictionary = _cfg().restless
	if not w.rng.chance(float(r.travel_base) + float(r.travel_coef) * _trait("restless")):
		return false
	var rp: Dictionary = _cfg().room_pull
	var weights: Array[float] = []
	var total := 0.0
	# Relationship pull (spec relationships.md section 8): skipped entirely at the shipped 0.0 values, so the weights
	# and the draws are those of Task 3.
	var rel: Relationships = null
	var pull_f := 0.0
	var pull_l := 0.0
	var pull_cap := 0
	if w.relationships != null and w.relationships_enabled:
		var ef: Dictionary = SimData.relationships().effects
		pull_f = float(ef.friend_pull)
		pull_l = float(ef.lonely_pull)
		if pull_f > 0.0 or pull_l > 0.0:
			rel = w.relationships
			pull_cap = int(ef.friend_pull_cap)
	for n in nb:
		var wt: Dictionary = rp.weights[n.to.kind]
		var v := float(rp.floor) + pow(_trait(wt.trait) * float(wt.mult), float(rp.exponent))
		if rel != null:
			v += rel.pull(id, n.to.id, pull_f, pull_l, pull_cap)
		weights.append(v)
		total += v
	var x := w.rng.randf() * total
	var pick: int = nb[nb.size() - 1].corridor
	for i in nb.size():
		x -= weights[i]
		if x < 0.0:
			pick = nb[i].corridor
			break
	corridor_id = pick
	state = "to_door"
	wait_h = door_time(w.rng)
	return true


## Syllable name plus number, drawn from the world rng.
static func make_name(rng: SimRng) -> String:
	var cfg: Dictionary = SimData.beings().names
	return "%s%s-%d" % [rng.pick(cfg.syllables_a), rng.pick(cfg.syllables_b),
			rng.randi_range(int(cfg.number[0]), int(cfg.number[1]))]


## A persona with every trait at `value`; used by blank-world tests.
static func flat_persona(role_in: String, value: float = 0.5) -> Dictionary:
	var traits := {}
	for d in SimData.persona().dims:
		traits[d] = value
	return {"traits": traits, "role": role_in, "description": ""}


# ---------------------------------------------------------------- construction (spec 6.4, 6.5, 6.5b, 7.5)

## Spec 6.4 branch 2. Builderish: role builder, or drive above builderish_drive, or (the site has
## had no crew for more than a sol and drive above builderish_drive_idle). The chance is drawn only
## for a builderish being. In the parent: suit up at its door; elsewhere: hop toward the parent.
func _try_join_construction(w: SimWorld) -> bool:
	var site := w.buildings.site
	if site == null:
		return false
	var bc: Dictionary = w.buildings.cfg.construction
	var drive := _trait("drive")
	var idle_h := float(w.buildings.cfg.build.waiting_site_idle_sols) * w.clock.sol_h
	var site_idle := w.t - site.last_work_t > idle_h + SimWorld.STEP_EPS
	var builderish := role == "builder" or drive > float(bc.builderish_drive) \
			or (site_idle and drive > float(bc.builderish_drive_idle))
	if not builderish or not w.rng.chance(float(bc.join_chance)):
		return false
	if building_id == site.parent_id:
		suit_up = true
		job = site
	else:
		var hop := w.buildings.next_hop(building_id, site.parent_id)
		if hop == 0:
			return false
		corridor_id = hop
	state = "to_door"
	wait_h = door_time(w.rng)
	return true


## Spec 6.5 for builders, at the corridor end p1 of the site. The suit is paid for even if the site
## has meanwhile gone, in which case the builder cancels.
func _suit_up_builder(w: SimWorld) -> void:
	var su: Dictionary = SimData.suits()
	w.colony.oxygen = maxf(0.0, w.colony.oxygen - float(su.fill_colony_o2))
	suit_up = false
	var site := w.buildings.site
	if site == null or job != site:
		job = null
		state = "idle"
		wait_h = idle_wait(w.rng)
		return
	var sb := w.buildings.get_building(site.building_id)
	var p1: Vector2 = sb.corridor.p1
	var p2: Vector2 = sb.corridor.p2
	air_h = float(su.tank_h)
	construction_suit = true
	x = p1.x
	y = p1.y
	heading = (p2 - p1).angle()
	state = "eva"
	after = "work"
	path = [p1, p2, w.buildings.work_point(sb, w.rng)]


## Walk along `path` at EVA speed (spec 6.3 item 5, `eva`), leaving footprints.
func _eva_step(w: SimWorld, dt: float) -> void:
	if path == null or path.is_empty():
		_finish_eva(w)
		return
	var su: Dictionary = SimData.suits()
	var target: Vector2 = path[0]
	var pos := Vector2(x, y)
	var d := pos.distance_to(target)
	if d < float(su.waypoint_reach_px):
		path.pop_front()
		if path.is_empty():
			_finish_eva(w)
		return
	var moved := minf(float(su.eva_speed_px_h) * dt, d)
	_step_toward(pos, target, moved)
	_leave_prints(w, moved)


func _step_toward(pos: Vector2, target: Vector2, dist: float) -> void:
	heading = (target - pos).angle()
	var np := pos + (target - pos).normalized() * dist
	x = np.x
	y = np.y


## Spec 6.5b: what happens when an EVA path ends, by `after`.
func _finish_eva(w: SimWorld) -> void:
	if after == "mine":
		var rm: Dictionary = SimData.resources().mining
		state = "mining"
		work_left_h = w.rng.randf_range(float(rm.shift_h[0]), float(rm.shift_h[1]))
		wait_h = 0.0
		wander_target = Vector2(x, y)
		return
	if after == "haul":
		var site: Resources.Site = mine.site
		if site.kind == "ice":
			w.colony.ice += load
		else:
			w.colony.regolith += load
		load = 0.0
		var home := int(mine.home_id)
		mine = null
		enter(w, home)
		return
	if after == "work":
		var site := w.buildings.site
		if site != null and job == site:
			var sh: Array = w.buildings.cfg.construction.shift_h
			state = "work"
			work_left_h = w.rng.randf_range(float(sh[0]), float(sh[1]))
			wait_h = 0.0
			wander_target = Vector2(x, y)
			return
		_leave_gone_site(w)
		return
	enter(w, building_id)


## The site is gone or is not this being's job: enter its building if finished, else the parent.
func _leave_gone_site(w: SimWorld) -> void:
	var dest := building_id
	if job != null:
		var jb := w.buildings.get_building(int(job.building_id))
		dest = jb.id if jb != null and jb.finished() else int(job.parent_id)
	enter(w, dest)


## Spec 7.5 work state: wander inside the site, pausing; at the end of the shift walk home.
func _work_step(w: SimWorld, dt: float) -> void:
	var site := w.buildings.site
	if site == null or job != site:
		_leave_gone_site(w)
		return
	var sb := w.buildings.get_building(site.building_id)
	work_left_h -= dt
	if work_left_h <= 0.0:
		state = "eva"
		after = "enter"
		path = [sb.corridor.p2, sb.corridor.p1]
		job = null
		return
	if wait_h > 0.0:
		wait_h -= dt
		return
	var su: Dictionary = SimData.suits()
	var pos := Vector2(x, y)
	var d := pos.distance_to(wander_target)
	if d < float(su.waypoint_reach_px):
		var ww: Array = w.buildings.cfg.construction.wander_wait_h
		wait_h = w.rng.randf_range(float(ww[0]), float(ww[1]))
		wander_target = w.buildings.work_point(sb, w.rng)
		return
	var moved := minf(float(su.work_speed_construction_px_h) * dt, d)
	_step_toward(pos, wander_target, moved)
	_leave_prints(w, moved)


# ---------------------------------------------------------------- air and turn-backs (spec 6.3, 8.5)

## Only a being heading out or working may turn back; one already `returning` may not.
func _can_turn_back() -> bool:
	if returning:
		return false
	return state == "mining" or state == "work" or (state == "eva" and (after == "mine" or after == "work"))


## Where a being walks home to: the door of its launch building (miners), the corridor end p1 on
## the parent side (builders).
func _home_door(w: SimWorld) -> Vector2:
	if mine != null:
		return mine.door
	return w.buildings.get_building(int(job.building_id)).corridor.p1


## Phase 6 item 4. Returns false if the being died (and was removed).
func _air_tick(w: SimWorld, dt: float) -> bool:
	air_h = float(air_h) - dt
	if float(air_h) <= 0.0:
		w._kill(self, "suffocated outside")
		return false
	if _can_turn_back():
		var su: Dictionary = SimData.suits()
		var dist := Vector2(x, y).distance_to(_home_door(w))
		if float(air_h) < dist / float(su.eva_speed_px_h) + float(su.return_margin_h):
			_turn_back(w, "low air")
	return true


## Walk straight home. A miner still digging takes a partial load (removed from the field); the
## air log has a repeat guard, though `returning` means a second turn-back cannot occur.
func _turn_back(w: SimWorld, reason: String) -> void:
	var su: Dictionary = SimData.suits()
	var home := _home_door(w)
	returning = true
	if reason == "low air":
		w.stats.turn_backs_air += 1
		if w.t - _low_air_logged_t > float(su.low_air_log_repeat_h) + SimWorld.STEP_EPS:
			_low_air_logged_t = w.t
			w._log("suit_low_air", "%s is turning back, low on air." % name, {"being_id": id})
	else:
		w.stats.turn_backs_exhausted += 1
		w._log("exhausted", "%s is exhausted and heading home." % name, {"being_id": id})
	if mine != null:
		if state == "mining":
			var pl: Array = SimData.resources().mining.partial_load
			var site: Resources.Site = mine.site
			load = w.rng.randf_range(float(pl[0]), float(pl[1]))
			if site.kind == "ice":
				load = w.take_ice(site, load)
			site.dug += load
		after = "haul" if load > 0.0 else "enter"
		if after == "enter":
			mine = null
	else:
		after = "enter"
		job = null
	path = [home]
	state = "eva"


# ---------------------------------------------------------------- footprints (spec 8.5)

## Adds the distance moved; every spacing_px the accumulator resets (not subtracts), the side
## flips and a print is left offset perpendicular to the heading. Heavy: construction suit or load.
func _leave_prints(w: SimWorld, moved: float) -> void:
	var fp: Dictionary = SimData.suits().footprint
	step_acc_px += moved
	if step_acc_px < float(fp.spacing_px) - SimWorld.STEP_EPS:
		return
	step_acc_px = 0.0
	foot_side = -foot_side
	var h := float(heading)
	var off := Vector2(-sin(h), cos(h)) * float(fp.side_offset_px) * float(foot_side)
	w.resources.add_footprint(float(x) + off.x, float(y) + off.y, h, w.t, construction_suit or load > 0.0)


# ---------------------------------------------------------------- mining (spec 6.4, 6.5, 8.3)

func start_mining(w: SimWorld, site: Resources.Site) -> void:
	mine = {"site": site, "door": w.buildings.get_building(building_id).door(float(w.buildings.cfg.tile_px)),
			"home_id": building_id}
	mine_intent = null
	suit_up = true
	state = "to_door"
	wait_h = door_time(w.rng)


## Spec 6.4 branch 3: cancel when no launch building or the field is dry; start mining if the
## launch building is here; else hop toward it (no hop: cancel).
func _resume_mine_intent(w: SimWorld) -> bool:
	if mine_intent == null:
		return false
	var site: Resources.Site = mine_intent
	var launch := w.resources.launch_for(site)
	if launch == null or (site.kind == "ice" and site.amount <= 0.0) \
			or not (w.resources.trip_time(site) < w.resources.trip_limit()):
		mine_intent = null
		return false
	return _head_for_launch(w, site, launch, true)


## Spec 6.4 branch 4. The chance is drawn only when sites exist, there is no mine, and oxygen
## is above the gate; then choose_site.
func _try_new_mining(w: SimWorld) -> bool:
	var rs: Dictionary = SimData.resources()
	if w.resources.ice_fields.is_empty() and w.resources.pits.is_empty():
		return false
	if mine != null or w.colony.oxygen <= float(rs.mine_attempt.o2_gate):
		return false
	var mw: Dictionary = rs.mine_will
	var will := float(mw.steady) * _trait("steady") + float(mw.drive) * _trait("drive") \
			+ float(mw.restless) * _trait("restless")
	var need_max := maxf(0.0, maxf(1.0 - w.colony.ice / w.colony.ice_target(),
			1.0 - w.colony.regolith / w.colony.regolith_target()))
	var ma: Dictionary = rs.mine_attempt
	if not w.rng.chance(float(ma.chance) * will * (float(ma.floor) + (1.0 - float(ma.floor)) * need_max)):
		return false
	var site := w.choose_site()
	if site == null:
		return false
	var launch := w.resources.launch_for(site)
	if launch == null:
		return false
	return _head_for_launch(w, site, launch, false)


## Mine here if this is the launch building, else set the intent and hop toward it.
func _head_for_launch(w: SimWorld, site: Resources.Site, launch: Buildings.Building, resuming: bool) -> bool:
	if launch.id == building_id:
		start_mining(w, site)
		return true
	var hop := w.buildings.next_hop(building_id, launch.id)
	if hop == 0:
		if resuming:
			mine_intent = null
		return false
	mine_intent = site
	corridor_id = hop
	state = "to_door"
	wait_h = door_time(w.rng)
	return true


## Spec 6.5 for miners, at the building door: spend colony oxygen, fill the tank, walk out.
func _suit_up_miner(w: SimWorld) -> void:
	var su: Dictionary = SimData.suits()
	var rm: Dictionary = SimData.resources().mining
	w.colony.oxygen = maxf(0.0, w.colony.oxygen - float(su.fill_colony_o2))
	suit_up = false
	construction_suit = false
	var site: Resources.Site = mine.site
	var door: Vector2 = mine.door
	air_h = float(su.tank_h)
	x = door.x
	y = door.y
	w.stats.mining_trips += 1
	var arrive := _field_point(w, site, rm.arrive_radius_frac)
	heading = (arrive - door).angle()
	state = "eva"
	after = "mine"
	path = [door, arrive]


## A point inside the field: angle, then radius fraction (y squashed), in that draw order.
func _field_point(w: SimWorld, site: Resources.Site, frac_range: Array) -> Vector2:
	var rm: Dictionary = SimData.resources().mining
	var ang := w.rng.randf_range(0.0, TAU)
	var frac := w.rng.randf_range(float(frac_range[0]), float(frac_range[1]))
	return Vector2(site.x + cos(ang) * site.r * frac,
			site.y + sin(ang) * site.r * frac * float(rm.wander_y_scale))


## Spec 8.3: wander inside the field; at the end of the shift or when the ice is gone, haul.
func _mining_step(w: SimWorld, dt: float) -> void:
	var rm: Dictionary = SimData.resources().mining
	var site: Resources.Site = mine.site
	work_left_h -= dt
	if work_left_h <= 0.0 or (site.kind == "ice" and site.amount <= 0.0):
		_end_mining(w)
		return
	if wait_h > 0.0:
		wait_h -= dt
		return
	var pos := Vector2(x, y)
	var d := pos.distance_to(wander_target)
	if d < float(rm.reach_px):
		var ww: Array = rm.wander_wait_h
		wait_h = w.rng.randf_range(float(ww[0]), float(ww[1]))
		wander_target = _field_point(w, site, rm.wander_radius_frac)
		return
	var moved := minf(float(SimData.suits().work_speed_mining_px_h) * dt, d)
	_step_toward(pos, wander_target, moved)
	_leave_prints(w, moved)


## Yield = U(range) x (0.7 + 0.6 drive) x (0.55 + energy/220), energy read after this step's drain.
func _end_mining(w: SimWorld) -> void:
	var rm: Dictionary = SimData.resources().mining
	var ef: Dictionary = _cfg().effort
	var site: Resources.Site = mine.site
	var yr: Array = rm.yield_ice if site.kind == "ice" else rm.yield_regolith
	var amount := w.rng.randf_range(float(yr[0]), float(yr[1])) \
			* (float(rm.drive_base) + float(rm.drive_coef) * _trait("drive")) \
			* (float(ef.energy_base) + energy / float(ef.energy_divisor))
	if site.kind == "ice":
		amount = w.take_ice(site, amount)
	site.dug += amount
	load = amount
	state = "eva"
	after = "haul"
	path = [Vector2(mine.door)]
