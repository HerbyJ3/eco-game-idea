extends SceneTree
## Read-only ice-supply diagnostic. No overrides, simulation writes or RNG draws.
## godot --headless --path station-zero --script res://tools/ice_supply_probe.gd -- --seed 7 --sols 720 --out DIR
## --control skips observation and exports the same end-state/RNG digest for comparison.
## --snapshots 278,288,298 records room graphs and founder plans at selected first-sol steps.

var daily: Array = []
var trips: Array = []
var events: Array = []
var fields: Array = []
var field_ids := {}
var active := {}
var intents := {}
var bucket := {}
var current_sol := -1
var consumption := 0.0
var deposited := 0.0
var mass_error := 0.0
var sites: Dictionary = {}
var snapshots: Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_in := 7
	var sols := 720
	var out := ""
	var control := false
	var snapshot_sols: Array[int] = []
	var i := 0
	while i < args.size():
		match args[i]:
			"--seed", "--sols", "--out", "--snapshots":
				if i + 1 >= args.size():
					push_error("Missing value for %s" % args[i])
					quit(2)
					return
				var key := args[i]
				i += 1
				match key:
					"--seed": seed_in = int(args[i])
					"--sols": sols = int(args[i])
					"--out": out = args[i]
					"--snapshots":
						for value in args[i].split(","):
							snapshot_sols.append(int(value))
			"--control": control = true
			_:
				push_error("Unknown argument %s" % args[i])
				quit(2)
				return
		i += 1
	if sols <= 0 or out == "":
		push_error("Positive --sols and --out are required")
		quit(2)
		return
	var started := Time.get_ticks_msec()
	var w := SimWorld.new(seed_in)
	var pop_samples: Array = []
	var ice_samples: Array = []
	var last_sample := -1
	while w.sol() < sols:
		var before: Array = []
		var ice_before := w.colony.ice
		var consumed := minf(ice_before, w.beings.size() * float(w.colony.cfg.consumption.ice_per_being) * w.fixed_step)
		if not control:
			_open_bucket(w)
			for b in w.beings:
				if b.earth_born:
					before.append(_before(w, b))
		w.step()
		if w.sol() != last_sample:
			last_sample = w.sol()
			pop_samples.append(w.colony.pop())
			ice_samples.append(w.colony.ice)
			if not control and w.sol() in snapshot_sols:
				snapshots.append(_snapshot(w))
		if not control:
			_after(w, before, ice_before, consumed)
	if not control:
		_close_bucket(w)
		for id in active:
			var trip: Dictionary = active[id]
			trip["outcome"] = "in_progress"
			trip["end_h"] = w.t
			trips.append(trip)
	var state := {"t": w.t, "rng_state": str(w.rng._rng.state), "population": w.colony.pop(),
		"births": w.stats.births, "deaths": w.stats.deaths, "stocks": [w.colony.ice, w.colony.regolith, w.colony.oxygen, w.colony.food],
		"relationships": w.stats.relationships, "age_history": w.stats.age_history, "mining_trips": w.stats.mining_trips}
	var result := {"seed": seed_in, "sols": sols, "control": control, "data_hash": load("res://tests/balance_lib.gd").data_hash().substr(0, 16),
		"digest": JSON.stringify(state, "", true, true).sha256_text(), "end_state": state, "pop_samples": pop_samples, "ice_samples": ice_samples,
		"daily": daily, "trips": trips, "events": events, "fields": fields, "snapshots": snapshots, "consumed_ice": consumption, "deposited_ice": deposited,
		"max_step_mass_error": mass_error, "wall_seconds": (Time.get_ticks_msec() - started) / 1000.0}
	DirAccess.make_dir_recursive_absolute(out)
	var tag := "control" if control else "trace"
	var f := FileAccess.open("%s/seed_%d_%s.json" % [out, seed_in, tag], FileAccess.WRITE)
	if f == null:
		push_error("Could not write diagnostic output")
		quit(2)
		return
	f.store_string(JSON.stringify(result))
	f.close()
	print("seed %d %s: digest %s, births %d, deaths %s, mass error %.12f, wall %.3fs" %
		[seed_in, tag, result.digest, w.stats.births, str(w.stats.deaths), mass_error, result.wall_seconds])
	quit(0 if mass_error < 1e-8 else 1)


func _open_bucket(w: SimWorld) -> void:
	if w.sol() == current_sol:
		return
	if current_sol >= 0:
		_close_bucket(w)
	current_sol = w.sol()
	bucket = {"sol": current_sol, "pop_start": w.colony.pop(), "ice_start": w.colony.ice, "consumed": 0.0, "deposited": 0.0,
		"adult_hours": {}, "urgent_adult_hours": {}, "departures_ice": 0, "departures_pit": 0, "deaths": [],
		"delivered_ice_loads": 0, "reachable_min": w.resources.reachable_ice_count(), "reachable_amount_start": 0.0, "zero_ice_h": 0.0,
		"decisions": {}, "urgent_decisions": {}, "mining_intents": 0, "intent_retargets": 0,
		"online": w.buildings.count_online("reactor"), "buildings": w.buildings.count(), "power_supply": w.buildings.supply(), "power_demand": w.buildings.demand()}
	var reachable_amount := 0.0
	for field in w.resources.ice_fields:
		_field_id(w, field)
		if w.resources.trip_time(field) < w.resources.trip_limit():
			reachable_amount += field.amount
	bucket.reachable_amount_start = reachable_amount


func _close_bucket(w: SimWorld) -> void:
	bucket["ice_end"] = w.colony.ice
	bucket["pop_end"] = w.colony.pop()
	daily.append(bucket)


func _field_id(w: SimWorld, site: Resources.Site) -> int:
	var key := site.get_instance_id()
	if not field_ids.has(key):
		var id := field_ids.size() + 1
		field_ids[key] = id
		sites[id] = site  # keep identity alive; prevents engine instance-ID reuse
		fields.append({"id": id, "kind": site.kind, "created_h": w.t, "x": site.x, "y": site.y,
			"start": site.start if site.kind == "ice" else null})
	return int(field_ids[key])


func _category(b: Being) -> String:
	if b.state == "sleep": return "sleep"
	if b.mine != null: return "%s_%s" % [b.mine.site.kind, "haul" if b.after == "haul" else b.state]
	if b.mine_intent != null: return "mining_intent_" + b.state
	if b.job != null or b.state == "work": return "construction_" + b.state
	if b.sleep_intent: return "sleep_route_" + b.state
	return b.state


func _before(w: SimWorld, b: Being) -> Dictionary:
	var category := _category(b)
	bucket.adult_hours[category] = float(bucket.adult_hours.get(category, 0.0)) + w.fixed_step
	if w.colony.ice < float(w.resources.cfg.want.ice_urgent_below):
		bucket.urgent_adult_hours[category] = float(bucket.urgent_adult_hours.get(category, 0.0)) + w.fixed_step
	var site: Resources.Site = b.mine.site if b.mine != null else null
	return {"b": b, "state": b.state, "after": b.after, "mine": site, "load": b.load,
		"intent": b.mine_intent, "returning": b.returning, "energy": b.energy, "job": b.job,
		"building": b.building_id, "decision": b.state == "idle" and b.wait_h <= w.fixed_step + SimWorld.STEP_EPS,
		"urgent": w.colony.ice < float(w.resources.cfg.want.ice_urgent_below)}


func _after(w: SimWorld, before: Array, ice_before: float, consumed: float) -> void:
	var delivered := 0.0
	for prev: Dictionary in before:
		var b: Being = prev.b
		if prev.intent == null and b.mine_intent != null:
			intents[b.id] = {"start_h": w.t, "site": _field_id(w, b.mine_intent), "from": prev.building}
			bucket.mining_intents += 1
		elif prev.intent != null and b.mine_intent != null and prev.intent != b.mine_intent:
			bucket.intent_retargets += 1
		if prev.mine != null and b.state == "eva" and b.after == "mine" and prev.state == "to_door":
			var route_h := w.t - float(intents[b.id].start_h) if intents.has(b.id) else 0.0
			var trip := {"being": b.id, "name": b.name, "kind": prev.mine.kind, "site": _field_id(w, prev.mine),
				"start_h": w.t, "start_sol": w.sol(), "start_energy": b.energy, "intent_route_h": route_h,
				"estimated_eva_h": w.resources.trip_time(prev.mine), "launch": b.building_id,
				"exhausted": false, "dig_h": 0.0, "yield": 0.0}
			active[b.id] = trip
			intents.erase(b.id)
			bucket["departures_" + prev.mine.kind] += 1
		if active.has(b.id):
			var trip: Dictionary = active[b.id]
			if prev.state == "mining": trip.dig_h += w.fixed_step
			if not prev.returning and b.returning: trip.exhausted = b.energy < float(SimData.beings().energy.exhausted_turn_back)
			if b.load > 0.0: trip.yield = b.load
			if prev.mine != null and prev.state == "eva" and prev.after == "haul" and b.mine == null:
				trip["deposited"] = float(prev.load)
				if prev.mine.kind == "ice":
					delivered += float(prev.load)
					bucket.delivered_ice_loads += 1
			if b.air_h == null or not w.beings.has(b):
				trip["end_h"] = w.t
				trip["outcome"] = "died" if not w.beings.has(b) else ("delivered" if trip.has("deposited") else "empty_return")
				trips.append(trip)
				active.erase(b.id)
		if prev.decision:
			var action := _category(b)
			bucket.decisions[action] = int(bucket.decisions.get(action, 0)) + 1
			if prev.urgent: bucket.urgent_decisions[action] = int(bucket.urgent_decisions.get(action, 0)) + 1
	consumption += consumed
	deposited += delivered
	bucket.consumed += consumed
	bucket.deposited += delivered
	mass_error = maxf(mass_error, absf(w.colony.ice - (ice_before - consumed + delivered)))
	if w.colony.ice <= 0.0: bucket.zero_ice_h += w.fixed_step
	if w._sol_started:
		bucket.reachable_min = mini(int(bucket.reachable_min), w.resources.reachable_ice_count())
	var lg: Array = w.log
	var i := lg.size() - 1
	while i >= 0 and float(lg[i].t) == w.t:
		var e: Dictionary = lg[i]
		if e.kind in ["died", "ice_dry", "ice_found", "scouts_found", "short", "back_online", "born", "built", "building_done", "colony_silent"]:
			events.append(e.duplicate(true))
			if e.kind == "died": bucket.deaths.append(e.text)
		i -= 1


func _snapshot(w: SimWorld) -> Dictionary:
	var people: Array = []
	var rooms: Array = []
	var ice_fields: Array = []
	for room in w.buildings.list:
		rooms.append({"id": room.id, "kind": room.kind, "online": room.online(), "door": [room.door(float(w.buildings.cfg.tile_px)).x, room.door(float(w.buildings.cfg.tile_px)).y],
			"parent": room.corridor.parent_id if room.corridor != null else null, "corridor_px": room.corridor.len if room.corridor != null else 0.0})
	for site in w.resources.ice_fields:
		var launch := w.resources.launch_for(site)
		ice_fields.append({"id": _field_id(w, site), "amount": site.amount, "dug": site.dug, "trip_h": w.resources.trip_time(site),
			"launch": launch.id if launch != null else null})
	for b in w.beings:
		if not b.earth_born: continue
		var rec := {"id": b.id, "name": b.name, "state": b.state, "category": _category(b), "energy": b.energy, "building": b.building_id, "role": b.role}
		if b.mine_intent != null:
			var launch := w.resources.launch_for(b.mine_intent)
			rec["intent_kind"] = b.mine_intent.kind
			rec["launch"] = launch.id if launch != null else null
			rec["route"] = _route(w, b.building_id, launch.id) if launch != null else {}
		people.append(rec)
	return {"sol": w.sol(), "t": w.t, "ice": w.colony.ice, "pop": w.colony.pop(), "people": people, "rooms": rooms, "fields": ice_fields}


## Physical corridor distance from the current room; ignores pauses, sleep, detours and current transit progress.
func _route(w: SimWorld, from: int, to: int) -> Dictionary:
	var visited := {}
	var hops: Array = []
	var px := 0.0
	while from != to and not visited.has(from):
		visited[from] = true
		var next := w.buildings.next_hop(from, to)
		if next == 0: return {"unreachable": true}
		var room := w.buildings.get_building(next)
		px += room.corridor.len
		from = room.id if room.corridor.parent_id == from else int(room.corridor.parent_id)
		hops.append(from)
	return {"hops": hops, "px": px, "walk_h": px / float(SimData.beings().tunnel_speed_px_h)}
