extends SceneTree
## Equivalence digest for the relationships module (docs/perf/task-4-tick-profile.md). Prints one digest line per
## --every steps of a real world, plus a padded-world run. Run it on the old code and on the new code and diff the output:
##   godot --headless --path station-zero --script res://tools/relationships_equiv.gd -- --seed 42 --steps 20000 --every 2000
## The digest covers every pair (key, bond to 17 places, all five flags), the counters, the pending queue, stats.relationships
## and the whole log, using only the module's public state.

## Padded world: `awake_rooms` habitats with the awake beings split between them, the rest asleep in the reactor,
## then `pairs_n` pairs stored (seeded spread of bonds 0.15 to 0.85, all pairs within a room first).
static func build(pop: int, pairs_n: int) -> SimWorld:
	var w := SimWorld.new(1, {"blank": true})
	w.add_building("reactor", 0, 0)
	var rooms: Array = []
	for i in 8:
		rooms.append(w.add_building("habitat", 40 + 40 * i, 0))
	var awake := int(float(pop) * 0.64)
	for i in pop:
		var b: Being
		if i < awake:
			b = w.add_being(rooms[i % rooms.size()])
		else:
			b = w.add_being(1)
			b.state = "sleep"
			b.sleep_started_t = w.t
		b.name = "N%d" % b.id
		b.energy = 70.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var ids: Array = []
	for b in w.beings:
		ids.append(b.id)
	var r: Relationships = w.relationships
	r.begin(w, false)
	var n := 0
	for i in awake:
		for j in range(i + 1, awake):
			if (i % rooms.size()) == (j % rooms.size()):
				r.debug_set_bond(ids[i], ids[j], 0.15 + 0.7 * rng.randf())
				n += 1
	while n < pairs_n:
		var a: int = ids[rng.randi() % ids.size()]
		var c: int = ids[rng.randi() % ids.size()]
		if a == c or r.pairs.has(Relationships.key_of(a, c)):
			continue
		r.debug_set_bond(a, c, 0.15 + 0.7 * rng.randf() * rng.randf())
		n += 1
	return w


static func digest(w: SimWorld) -> String:
	var r: Relationships = w.relationships
	var keys: Array = r.pairs.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		var p: Dictionary = r.pairs[k]
		parts.append("%d %.17f %d%d%d%d%d" % [k, p.bond, int(p.friends), int(p.close), int(p.was_close), int(p.kin), int(p.crew)])
	for d in [r.friend_count, r.close_count, r.known, r.found_friend, r.crew_drift_named]:
		var ks: Array = d.keys()
		ks.sort()
		parts.append(str(ks) + str(d.values().size()))
	parts.append(str(r.pending))
	parts.append("%d %d %d %d" % [r.ticks, r.lines_sol, r.lines_this_sol, w.log.size()])
	parts.append(str(w.stats.relationships))
	for e in w.log:
		parts.append(str(e))
	return "\n".join(parts).sha256_text().substr(0, 16)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var m := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			m[a[i].substr(2)] = a[i + 1]
			i += 1
		i += 1
	var seed_n := int(m.get("seed", "42"))
	var steps := int(m.get("steps", "20000"))
	var every := int(m.get("every", "2000"))
	var w := SimWorld.new(seed_n)
	for s in steps:
		w.step()
		if (s + 1) % every == 0:
			print("seed %d step %d sol %d pop %d pairs %d digest %s" % [seed_n, s + 1, w.sol(), w.beings.size(),
					w.relationships.pairs.size(), digest(w)])
	var p: SimWorld = build(159, 5278)
	for t in 600:
		p.relationships.on_step(p, 1.0)
		if (t + 1) % 200 == 0:
			print("padded tick %d pairs %d digest %s" % [t + 1, p.relationships.pairs.size(), digest(p)])
	quit(0)
