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


## What the view draws (spec section 4): none inside; construction for a builder's suit, from
## suit-up until entering; eva for any other outside state. A job alone also marks a builder
## outside.
func suit_kind() -> String:
	match state:
		"eva", "work", "mining":
			return "construction" if construction_suit or job != null else "eva"
	return "none"


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

## One being's update for one step. Mining (step 8) adds an arm to the match; step 8 also adds the
## air tick and the turn-backs between the drain and the match (spec 6.3 items 3 and 4).
func update(w: SimWorld, dt: float) -> void:
	var e: Dictionary = _cfg().energy
	if state == "sleep":
		_sleep_step(w, dt)
		return
	energy = clampf(energy - drain_per_h() * dt, 0.0, float(e.max))
	match state:
		"transit":
			_transit_step(w, dt)
		"eva":
			_eva_step(w, dt)
		"work":
			_work_step(w, dt)
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


## When to_door elapses (spec 6.2 order): (a) miner suit-up (step 8), (b) builder suit-up at the
## corridor end p1, (c) enter the tunnel.
func _door_action(w: SimWorld) -> void:
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


## Spec 6.4. Branches 3 and 4 (mining) arrive in step 8, between joining and travel.
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
	for n in nb:
		var wt: Dictionary = rp.weights[n.to.kind]
		var v := float(rp.floor) + pow(_trait(wt.trait) * float(wt.mult), float(rp.exponent))
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


## Walk along `path` at EVA speed (spec 6.3 item 5, `eva`). Step 8 hangs the air tick, footprints
## and turn-backs on this same walk.
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
	_step_toward(pos, target, minf(float(su.eva_speed_px_h) * dt, d))


func _step_toward(pos: Vector2, target: Vector2, dist: float) -> void:
	heading = (target - pos).angle()
	var np := pos + (target - pos).normalized() * dist
	x = np.x
	y = np.y


## Spec 6.5b. Only the `work`, `enter` and null rows exist so far; `mine` and `haul` are step 8.
func _finish_eva(w: SimWorld) -> void:
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
	_step_toward(pos, wander_target, minf(float(su.work_speed_construction_px_h) * dt, d))
