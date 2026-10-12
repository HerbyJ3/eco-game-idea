class_name Moods
extends RefCounted
## Emotions (docs/specs/emotions.md revision 4): a per-being mood around a Deimos (or Moon) baseline, pushed by events that
## already happen (friendship, grief, births, hard sols, the pledge, company), decaying at the temperament's rate. Mood changes
## two behaviours only, both in sim/being.gd, both through the gains cached on the world. Pure logic: draws no random number,
## holds no reference to the world (every method takes it as an argument), writes only Being mood fields, stats.moods and the log.

const MAJOR: Array[String] = ["friend", "close", "lapse", "lapse_close", "grief", "birth_parent"]
const STICKY: Array[String] = ["grief", "lapse_close"]
const PUSH_KEYS: Array[String] = ["friend", "close", "lapse", "lapse_close", "grief", "birth_parent", "hard_sol", "pledge", "company"]

var cfg: Dictionary = {}
var seen_ticks := 0
var seen_pledge := false
var max_id_seen := 0
## Null or the clause key ("ice", "air", "food") set at a sol boundary and applied at the next mood tick.
var pending_hard: Variant = null
var pending_pledge := false
var lines_sol := -1
var lines_this_sol := 0
## The last tick's aggregates: mean, sd (population), heavy share.
var agg := {"mean": 0.0, "sd": 0.0, "heavy": 0.0}
## Wall time of the last mood tick in ms. Probe only; never in stats, log or any hashed state.
var last_tick_ms := 0.0
var _queued: Array = []
var _seen_light: Dictionary = {}
var _seen_bright: Dictionary = {}


static func new_stats() -> Dictionary:
	var pushes := {}
	for k in PUSH_KEYS:
		pushes[k] = 0
	return {"pushes": pushes, "bright_beings": 0, "light_beings": 0, "pushes_zeroed": 0,
			"lines": {"quiet": 0, "relief": 0}, "lines_dropped": 0,
			"min_dev": 0.0, "max_dev": 0.0, "min_dev_sol": null, "max_dev_sol": null,
			"mean_by_sol": [], "sd_by_sol": [], "heavy_by_sol": [], "mean": 0.0, "sd": 0.0, "heavy_share": 0.0}


## Decay fraction per mood tick for a half-life in sols (spec 2).
static func k_of(half: float, tick_h: float, sol_h: float) -> float:
	return 1.0 - pow(0.5, tick_h / (half * sol_h))


## {base, halflife} (sols) of a birth chart: its inner placement's sign through the element and modality tables (spec 5.1).
static func temperament(chart: Dictionary) -> Dictionary:
	var tp: Dictionary = SimData.moods().temperament
	var s: Dictionary = SimData.signs()[int(chart[tp.inner_key[chart.world]])]
	return {"base": float(tp.element_base[s.element]) + float(tp.modality_base[s.modality]),
			"halflife": float(tp.halflife_sols[s.modality]) * float(tp.halflife_mult[s.element])}


static func neutral() -> Dictionary:
	var n: Dictionary = SimData.moods().temperament.neutral
	return {"base": float(n.base), "halflife": float(n.halflife_sols)}


## Writes a temperament onto a being: it starts at its baseline, band even, no why.
static func set_temperament(b: Being, t: Dictionary, sol_h: float) -> void:
	b.mood_base = float(t.base)
	b.mood = b.mood_base
	b.mood_halflife = float(t.halflife)
	b.mood_k = k_of(b.mood_halflife, float(SimData.relationships().tick_h), sol_h)
	b.mood_band = 2
	b.mood_why = null


func begin(world: SimWorld, founders_world: bool) -> void:
	cfg = SimData.moods().duplicate(true)
	for b in world.beings:
		max_id_seen = maxi(max_id_seen, b.id)
	var ef: Dictionary = cfg.effects
	world.mood_clamp_low = float(ef.clamp_low)
	world.mood_clamp_high = float(ef.clamp_high)
	world.mood_travel_floor = float(ef.travel_floor)
	if world.moods_enabled:
		world.mood_travel_gain = float(ef.travel_coef)
		world.mood_energy_gain = float(ef.energy_coef)
	else:
		world.mood_travel_gain = 0.0
		world.mood_energy_gain = 0.0
	if founders_world and world.moods_enabled:
		_aggregate(world.stats.moods, world.beings)
		_append_series(world.stats.moods)


## Sol hook (O(1)): records the colony-level pushes for the next mood tick and appends the three per-sol series.
func on_sol(world: SimWorld) -> void:
	var ac: Dictionary = SimData.ages().sample
	var col: Colony = world.colony
	var use := float(col.pop()) * float(SimData.colony().consumption.ice_per_being) * world.clock.sol_h
	var clause: Variant = null
	if col.ice < float(ac.ice_min_sols) * use - Ages.CMP_EPS:
		clause = "ice"
	elif col.oxygen < float(ac.o2_min_fraction) * col.o2_cap():
		clause = "air"
	elif col.food < float(ac.food_min_fraction) * col.food_cap():
		clause = "food"
	if clause != null:
		pending_hard = clause
	if world.stats.council.pledge_sol != null and not seen_pledge:
		pending_pledge = true
	_append_series(world.stats.moods)


func _append_series(m: Dictionary) -> void:
	m.mean_by_sol.append(float(agg.mean))
	m.sd_by_sol.append(float(agg.sd))
	m.heavy_by_sol.append(float(agg.heavy))


func _aggregate(m: Dictionary, beings: Array) -> void:
	var s := 0.0
	var ss := 0.0
	var heavy := 0
	for b in beings:
		s += b.mood
		ss += b.mood * b.mood
		if b.mood_band == 0:
			heavy += 1
	_set_agg(m, s, ss, heavy, beings.size())


func _set_agg(m: Dictionary, s: float, ss: float, heavy: int, n: int) -> void:
	if n == 0:
		agg = {"mean": 0.0, "sd": 0.0, "heavy": 0.0}
	else:
		var mean := s / float(n)
		agg = {"mean": mean, "sd": sqrt(maxf(0.0, ss / float(n) - mean * mean)), "heavy": float(heavy) / float(n)}
	m.mean = agg.mean
	m.sd = agg.sd
	m.heavy_share = agg.heavy


## The mood tick (phase 11c): acts only on steps where the relationships tick count moved.
func on_step(world: SimWorld) -> void:
	var rel: Relationships = world.relationships
	if rel == null or not world.relationships_enabled or rel.ticks == seen_ticks:
		return
	seen_ticks = rel.ticks
	var t0 := Time.get_ticks_usec()
	_tick(world, rel)
	last_tick_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _tick(world: SimWorld, rel: Relationships) -> void:
	var c: Dictionary = cfg
	var tick_h := float(SimData.relationships().tick_h)
	var eps := float(c.rest_eps)
	var bs: Array = world.beings
	var by_id := {}
	# 1. Newborns: detect (scanning from the end of the ascending list) and queue; nothing is pushed here.
	_queued.clear()
	var i := bs.size() - 1
	if i >= 0 and bs[i].id > max_id_seen:
		var fresh: Array = []
		while i >= 0 and bs[i].id > max_id_seen:
			fresh.append(bs[i])
			i -= 1
		max_id_seen = fresh[0].id
		fresh.reverse()
		by_id = _index(bs)
		for nb in fresh:
			if nb.parent_id != 0 and by_id.has(nb.parent_id) and nb.born_t >= world.t - tick_h:
				_queued.append([by_id[nb.parent_id], nb])
	# 2. Decay.
	for b in bs:
		b.mood += (b.mood_base - b.mood) * b.mood_k
		if absf(b.mood - b.mood_base) < eps:
			b.mood = b.mood_base
	# 3. Event pushes: queued births first, then the relationships events in list order.
	for q in _queued:
		_apply(world, q[0], "birth_parent", float(c.push.birth_parent), q[1].id, q[1].name, "")
	if not rel.events.is_empty():
		if by_id.is_empty():
			by_id = _index(bs)
		for e in rel.events:
			var kind := str(e.kind)
			if kind == "grief":
				var m: Variant = by_id.get(int(e.a))
				if m != null:
					_apply(world, m, "grief", _grief(float(e.bond)), int(e.b), str(e.name), "")
			else:
				var pa: Variant = by_id.get(int(e.a))
				var pb: Variant = by_id.get(int(e.b))
				if pa == null or pb == null:
					continue
				var amt := float(c.push[kind])
				_apply(world, pa, kind, amt, pb.id, pb.name, "")
				_apply(world, pb, kind, amt, pa.id, pa.name, "")
	# 4 to 6. Colony pushes, company, bands and why, aggregates, line candidates: one pass, in that order per being.
	var hard: Variant = pending_hard
	var pledge := pending_pledge
	var floor_dev := float(c.push.hard_floor_dev)
	var hard_amt := float(c.push.hard_sol)
	var pledge_amt := float(c.push.pledge)
	var company_amt := float(c.push.company)
	var show_dev := float(c.why.show_dev)
	var wf := rel.with_friend
	var wf_n := wf.size()
	var m_stats: Dictionary = world.stats.moods
	var sol := world.sol()
	var sum := 0.0
	var sumsq := 0.0
	var heavy := 0
	var min_dev := float(m_stats.min_dev)
	var max_dev := float(m_stats.max_dev)
	var cands: Array = []
	var ln: Dictionary = c.lines
	var quiet_cd := float(ln.quiet_cooldown_sols) * world.clock.sol_h - 1e-9
	var relief_cd := float(ln.relief_min_sols) * world.clock.sol_h - 1e-9
	for b in bs:
		if hard != null and b.mood - b.mood_base > floor_dev:
			_apply(world, b, "hard_sol", hard_amt, null, "", str(hard))
		if pledge:
			_apply(world, b, "pledge", pledge_amt, null, "", "")
		if b.id < wf_n and wf[b.id] != 0:
			_apply(world, b, "company", company_amt, null, "", "")
		_band(b)
		var d: float = b.mood - b.mood_base
		var why: Variant = b.mood_why
		if why != null:
			if absf(d) < show_dev:
				b.mood_why = null
			elif why.key == "friend" or why.key == "close":
				var p: Variant = rel.pairs.get(Relationships.key_of(b.id, int(why.id)))
				if p == null or not p.friends:
					b.mood_why = null
		if d < min_dev:
			min_dev = d
			m_stats.min_dev_sol = sol
		if d > max_dev:
			max_dev = d
			m_stats.max_dev_sol = sol
		var band: int = b.mood_band
		if band == 4:
			if not _seen_bright.has(b.id):
				_seen_bright[b.id] = true
				m_stats.bright_beings += 1
		if band >= 3:
			if not _seen_light.has(b.id):
				_seen_light[b.id] = true
				m_stats.light_beings += 1
		sum += b.mood
		sumsq += b.mood * b.mood
		if band == 0:
			heavy += 1
			if b.mood_down_t == null and world.t - float(b.mood_quiet_t) >= quiet_cd:
				cands.append([b, "quiet", d])
		elif b.mood_down_t != null and band >= 2 and world.t - float(b.mood_down_t) >= relief_cd:
			cands.append([b, "relief", 0.0])
	if pending_hard != null or pending_pledge:
		if pledge:
			seen_pledge = true
		pending_hard = null
		pending_pledge = false
	m_stats.min_dev = min_dev
	m_stats.max_dev = max_dev
	_set_agg(m_stats, sum, sumsq, heavy, bs.size())
	if not cands.is_empty():
		_lines(world, rel, cands)


func _index(bs: Array) -> Dictionary:
	var by_id := {}
	for b in bs:
		by_id[b.id] = b
	return by_id


## Grief for a mourner of bond `bond`: linear from grief_min at the friend line to grief_max at bond 1.0 (spec 5.3).
func _grief(bond: float) -> float:
	var lo := float(SimData.relationships().lines.friend)
	var p: Dictionary = cfg.push
	var f := clampf((bond - lo) / (1.0 - lo), 0.0, 1.0)
	return float(p.grief_min) + (float(p.grief_max) - float(p.grief_min)) * f


## One push on one being: headroom scale, stats, and the why rules of 5.4.
func _apply(world: SimWorld, b: Being, key: String, nominal: float, other: Variant, other_name: String, clause: String) -> void:
	var c: Dictionary = cfg
	var d: float = b.mood - b.mood_base
	var sc: float
	if nominal > 0.0:
		var ceil_dev := float(c.push.company_ceil_dev) if key == "company" else float(c.range.ceil_dev)
		sc = clampf(1.0 - d / ceil_dev, 0.0, 1.0)
	else:
		sc = clampf(1.0 - d / float(c.range.floor_dev), 0.0, 1.0)
	b.mood += nominal * sc
	var m: Dictionary = world.stats.moods
	m.pushes[key] = int(m.pushes[key]) + 1
	if sc == 0.0:
		m.pushes_zeroed += 1
	if key == "company":
		return  # company never sets, replaces or clears a why
	var d_after: float = b.mood - b.mood_base
	var sgn := 1 if nominal > 0.0 else -1
	var dsgn := 1 if d_after > 0.0 else (-1 if d_after < 0.0 else 0)
	if sgn != dsgn:
		return  # rule 2: a push of the wrong sign never sets or replaces a why
	var cur: Variant = b.mood_why
	var set_it := false
	if key in MAJOR:
		if absf(nominal) < float(c.why.min_push):
			return
		if cur == null or int(cur.sign) != dsgn:
			set_it = true
		elif absf(nominal * sc) >= 0.5 * absf(d_after):
			set_it = not (str(cur.key) in STICKY) or key in STICKY
	else:
		if absf(d_after) < float(c.why.show_dev):
			return
		set_it = cur == null or int(cur.sign) != dsgn
	if set_it:
		b.mood_why = {"key": key, "id": other, "name": other_name, "t": world.t, "clause": clause, "sign": sgn}


## Band with hysteresis, re-evaluated until stable (at most one move per line, four in all) (spec 5.4).
func _band(b: Being) -> void:
	var bd: Dictionary = cfg.bands
	var h := float(bd.hyst)
	var d: float = b.mood - b.mood_base
	for _i in 4:
		var band: int = b.mood_band
		var nb := band
		match band:
			0:
				if d > float(bd.heavy) + h:
					nb = 1
			1:
				if d <= float(bd.heavy) - h:
					nb = 0
				elif d > float(bd.low) + h:
					nb = 2
			2:
				if d <= float(bd.low) - h:
					nb = 1
				elif d >= float(bd.light) + h:
					nb = 3
			3:
				if d >= float(bd.bright) + h:
					nb = 4
				elif d < float(bd.light) - h:
					nb = 2
			4:
				if d < float(bd.bright) - h:
					nb = 3
		if nb == band:
			return
		b.mood_band = nb


## Offers the candidates deepest first under the per-sol cap (spec 5.6). A candidate over the cap changes no state.
func _lines(world: SimWorld, rel: Relationships, cands: Array) -> void:
	var ln: Dictionary = cfg.lines
	for cd in cands:
		var b: Being = cd[0]
		var bond := 0.0
		var why: Variant = b.mood_why
		if why != null and why.id != null and cands.size() > 1:
			var p: Variant = rel.pairs.get(Relationships.key_of(b.id, int(why.id)))
			bond = 0.0 if p == null else float(p.bond)
		cd.append(bond)
	cands.sort_custom(func(x: Array, y: Array) -> bool:
		if x[2] != y[2]:
			return x[2] < y[2]
		if x[3] != y[3]:
			return x[3] > y[3]
		return x[0].id < y[0].id)
	var sol := world.sol()
	if sol != lines_sol:
		lines_sol = sol
		lines_this_sol = 0
	var m: Dictionary = world.stats.moods
	var texts: Dictionary = cfg.text.lines
	for cd in cands:
		if lines_this_sol >= int(ln.max_per_sol):
			m.lines_dropped += 1
			continue
		var b: Being = cd[0]
		var variant := "a" if (b.id + sol) % 2 == 0 else "b"
		if cd[1] == "quiet":
			var key := "quiet"
			var other: Variant = null
			var oname := ""
			var why: Variant = b.mood_why
			if why != null:
				match str(why.key):
					"grief":
						key = "quiet_grief"
					"lapse", "lapse_close":
						key = "quiet_lapse"
					"hard_sol":
						key = "quiet_hard"
				other = why.id
				oname = str(why.name)
			var text := str(texts[key][variant]).replace("{name}", b.name).replace("{other}", oname)
			world._log("mood_quiet", text, {"being_id": b.id, "other_id": other, "place": "", "building_id": null})
			b.mood_quiet_t = world.t
			b.mood_down_t = world.t
			m.lines.quiet += 1
		else:
			var text2 := str(texts.relief[variant]).replace("{name}", b.name)
			world._log("mood_relief", text2, {"being_id": b.id, "other_id": null, "place": "", "building_id": null})
			b.mood_down_t = null
			m.lines.relief += 1
		lines_this_sol += 1
