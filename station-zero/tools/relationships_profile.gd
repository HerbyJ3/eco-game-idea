extends SceneTree
## Relationships tick profile (docs/perf/task-4-tick-profile.md; spec docs/specs/relationships.md section 13 item 9).
##   godot --headless --path station-zero --script res://tools/relationships_profile.gd -- [--ticks 300] [--pop 159] [--pairs 5278] [--check]
## Builds a padded world (blank world, 5 rooms of awake beings, the rest asleep, pairs pre-stored with a seeded
## spread of bonds), then times the real Relationships.on_step tick, and each part of it by calling the module's own part
## methods in tick order. Timers live here; sim/ carries none (except the probe-only last_tick_ms).
## --check prints a state digest after --ticks ticks (for old-vs-new equivalence on this world).

var _names: Array[String] = ["info+deaths+births", "grouping (co-presence)", "growth loop", "decay walk (keys, sort, decay, flags)",
		"lines/events", "reading (per sol, not per tick)"]


static func _eq() -> GDScript:
	return load("res://tools/relationships_equiv.gd")


func _initialize() -> void:
	_run.call_deferred()


func _args() -> Dictionary:
	var m := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--"):
			if i + 1 < a.size() and not a[i + 1].begins_with("--"):
				m[a[i].substr(2)] = a[i + 1]
				i += 1
			else:
				m[a[i].substr(2)] = "true"
		i += 1
	return m


static func _med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


static func _mx(a: Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, float(v))
	return m


## A copy of Relationships._tick with a timer around each part (usec). Keep in line with the module.
func _parts(w: SimWorld, r: Relationships) -> Array:
	var out: Array = []
	r.acc_h = 0.0
	r._cfg = SimData.relationships()
	var t0 := Time.get_ticks_usec()
	r.ticks += 1
	var by_id: Dictionary = r.call("_prepare", w)
	r._seeded.clear()
	r._deaths(w, by_id)
	r._births(w, by_id)
	var t1 := Time.get_ticks_usec()
	out.append(t1 - t0)
	# Grouping replica (the first half of _growth: co-presence lists), timed on its own; the growth loop is the rest.
	var g0 := Time.get_ticks_usec()
	var kinds := {}
	for bd in w.buildings.list:
		kinds[bd.id] = bd.kind
	var inside := {}
	var work_crew: Array = []
	var mine_groups := {}
	for b in w.beings:
		if b.is_inside():
			if b.state != "sleep":
				if not inside.has(b.building_id):
					inside[b.building_id] = []
				inside[b.building_id].append(b.id)
		elif b.state == "work":
			if b.job != null and b.job == w.buildings.site:
				work_crew.append(b.id)
		elif b.state == "mining" and b.mine != null:
			var s: Variant = b.mine.site
			if not mine_groups.has(s):
				mine_groups[s] = []
			mine_groups[s].append(b.id)
	var bids: Array = inside.keys()
	bids.sort()
	var gt := Time.get_ticks_usec() - g0
	var t1b := Time.get_ticks_usec()
	var grown: Dictionary = r._growth(w)
	var t2 := Time.get_ticks_usec()
	out.append(gt)
	out.append(maxi(0, t2 - t1b - gt))
	var ev: Dictionary = r._decay_and_flags(w, by_id, grown)
	var t3 := Time.get_ticks_usec()
	out.append(t3 - t2)
	r._lines_step(w, by_id, ev)
	var t4 := Time.get_ticks_usec()
	out.append(t4 - t3)
	r._reading(w)
	out.append(Time.get_ticks_usec() - t4)
	return out


func _run() -> void:
	var a := _args()
	var ticks := int(a.get("ticks", "300"))
	var pop := int(a.get("pop", "159"))
	var pairs_n := int(a.get("pairs", "5278"))
	var w: SimWorld = _eq().build(pop, pairs_n)
	var r: Relationships = w.relationships
	print("world: pop %d, pairs %d, awake-inside %d" % [w.beings.size(), r.pairs.size(), int(float(pop) * 0.64)])
	if a.has("check"):
		for i in ticks:
			r.on_step(w, 1.0)
		print("digest after %d ticks: %s (pairs %d)" % [ticks, _eq().digest(w), r.pairs.size()])
		quit(0)
		return
	# A. the whole tick through on_step (the shipped path).
	var whole: Array = []
	var w1: SimWorld = _eq().build(pop, pairs_n)
	for i in ticks:
		w1.relationships.on_step(w1, 1.0)
		whole.append(w1.relationships.last_tick_ms)
	print("A whole tick (on_step, last_tick_ms): median %.3f ms, max %.3f ms, pairs at end %d" % [_med(whole), _mx(whole), w1.relationships.pairs.size()])
	if not w1.relationships.has_method("_prepare"):
		print("B skipped: this module predates _prepare (commit 0a6cf6c); the before split was taken with the earlier tool copy")
		quit(0)
		return
	# B. parts, in tick order, through the module's own part methods.
	var w2: SimWorld = _eq().build(pop, pairs_n)
	var rr: Relationships = w2.relationships
	var cols: Array = []
	for i in _names.size():
		cols.append([])
	for i in ticks:
		var res: Array = _parts(w2, rr)
		for j in _names.size():
			cols[j].append(res[j])
	print("B parts (median / max ms):")
	var tot := 0.0
	for j in _names.size():
		print("  %-44s %.3f / %.3f" % [_names[j], _med(cols[j]) / 1000.0, _mx(cols[j]) / 1000.0])
		if j < 5:
			tot += _med(cols[j])
	print("  sum of per-tick part medians: %.3f ms" % (tot / 1000.0))
	quit(0)
