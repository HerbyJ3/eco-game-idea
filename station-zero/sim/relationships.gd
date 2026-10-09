class_name Relationships
extends RefCounted
## Relationships and trust (spec docs/specs/relationships.md revision 8, Task 4). Every pair of beings that shares
## waking hours in a room, or a shift on a site or field, grows a private bond; bonds decay when apart. Above a line a bond
## is a friendship, higher still it is close. Trust is read once a sol as the reach of the friendship web. The layer reads
## the world and writes only itself, `stats.relationships` and the log. No RNG, no wall clock (except the probe-only
## `last_tick_ms`), no stored reference to the world (no cycle). Every tunable is in data/relationships.json.

## Pair key = lo x 2^20 + hi (spec section 2). A key rule, not a tunable.
const SHIFT := 1048576
## Kind of a capped line event, in offer order within a tick (spec 5.6).
const FORMS: Array[String] = ["friends", "found_friend", "close", "close_crew", "drifted", "grief"]

## pair key -> {lo, hi, bond, friends, close, was_close, kin, crew}
var pairs: Dictionary = {}
## Sets of being ids (id -> true).
var known: Dictionary = {}
var found_friend: Dictionary = {}
var crew_drift_named: Dictionary = {}
## being id -> number of `friends` pairs (absent means 0), and number of `close` pairs.
var friend_count: Dictionary = {}
var close_count: Dictionary = {}
## Capped line events waiting for the next free slot, oldest first: {type, lo, hi, place, building_id}.
var pending: Array = []
var acc_h := 0.0
var ticks := 0
var lines_sol := -1
var lines_this_sol := 0
## Snapshot of the last tick: building id -> ascending ids of awake-inside beings.
var present: Dictionary = {}
## Wall time of the last tick in ms. Probe only; never in stats, log or any hashed state.
var last_tick_ms := 0.0
## Emotions feed (emotions.md 9.1), read by Moods and nothing else in sim/. `events` is this tick's list of mood-relevant
## changes (grief per mourner, friend, close, lapse, lapse_close); `with_friend` marks, by being id, the beings grown together
## with a friend this tick. Both are written here and never read here, so no relationships result depends on them.
var events: Array = []
var with_friend := PackedByteArray()

## Tick-local.
var _cfg: Dictionary = {}
var _seeded: Dictionary = {}
## Per-tick trait readings indexed by being id (ids stay below SHIFT; sized to the largest living id + 1, 0.0 elsewhere):
## warmth (sociability + care) / 2, tempo (restless - steady), curiosity, restless.
var _warm := PackedFloat64Array()
var _tempo := PackedFloat64Array()
var _cur := PackedFloat64Array()
var _rest := PackedFloat64Array()
## Slot mirror of `pairs` for the decay pass (packed arrays are several times cheaper to walk than the pair dictionaries).
## Slot i describes the pair with key _sk[i]: low and high id, bond (always equal to pairs[key].bond), flag bits (1 friends,
## 2 close) and the pair dictionary itself. `_slot` maps key -> slot. Every module write to a pair's bond or flags goes
## through _set_bond / _flag_step / _get_or_make / _remove_pair, which keep the mirror in step.
var _slot: Dictionary = {}
var _sk := PackedInt64Array()
var _sl := PackedInt32Array()
var _sh := PackedInt32Array()
var _sb := PackedFloat64Array()
var _sf := PackedByteArray()
var _sp: Array = []
var _mask := PackedByteArray()
var _max_id := 0
## Places of this tick's growth groups: [place, building_id] by group index (a grown pair stores its group index).
var _groups: Array = []


## The initial `stats.relationships` dictionary (zeros, nulls, empty lists).
static func new_stats() -> Dictionary:
	var lines := {}
	for f in FORMS:
		lines[f] = 0
	return {
		"friendships_formed": 0, "friendships_renewed": 0, "close_formed": 0, "drifted": 0, "crew_drifted": 0,
		"lines": lines, "lines_capped": 0, "lines_dropped": 0, "lines_stale": 0,
		"first_friendship_sol": null, "first_mars_born_friendship_sol": null,
		"pairs": 0, "friend_pairs": 0, "close_pairs": 0,
		"web_share": 0.0, "second_share": 0.0, "lonely_share": 0.0, "friends_mean": 0.0,
		"web_by_sol": [], "second_by_sol": [], "lonely_by_sol": [],
	}


static func key_of(a: int, b: int) -> int:
	return mini(a, b) * SHIFT + maxi(a, b)


# ---------------------------------------------------------------- queries and test seam

func are_friends(a: int, b: int) -> bool:
	var p: Variant = pairs.get(key_of(a, b))
	return p != null and bool(p.friends)


## Test seam (never called by the sim, view or tools): creates the pair when missing (all flags false), sets the bond and
## applies the flag hysteresis. Sets no was_close, kin or crew; logs nothing; counts nothing; marks nothing as grown.
func debug_set_bond(a: int, b: int, bond: float) -> void:
	_cfg = SimData.relationships()
	var p := _get_or_make(mini(a, b), maxi(a, b))
	_set_bond(p, bond)
	_flag_step(p)


# ---------------------------------------------------------------- creation

## Called from SimWorld._init after ages.begin. Not a tick. A founder world seeds the crew and appends the initial reading.
func begin(world: SimWorld, founders_world: bool) -> void:
	_cfg = SimData.relationships()
	var ids: Array = []
	for b in world.beings:
		assert(b.id < SHIFT, "being ids must stay below 2^20")
		known[b.id] = true
		ids.append(b.id)
	if not founders_world:
		return
	ids.sort()
	var crew := float(_cfg.seed.crew)
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var p := _get_or_make(ids[i], ids[j])
			_set_bond(p, crew)
			p.crew = true
			_flag_step(p)
	_reading(world)


# ---------------------------------------------------------------- phase 11b: the tick

func on_step(world: SimWorld, dt: float) -> void:
	var cfg := SimData.relationships()
	acc_h += dt
	if acc_h < float(cfg.tick_h) - SimWorld.STEP_EPS:
		return
	acc_h = 0.0
	var t0 := Time.get_ticks_usec()
	_cfg = cfg
	_tick(world)
	last_tick_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _tick(world: SimWorld) -> void:
	ticks += 1
	events = []
	var by_id := _prepare(world)
	_seeded.clear()
	_deaths(world, by_id)
	_births(world, by_id)
	var grown := _growth(world)
	var ev := _decay_and_flags(world, by_id, grown)
	_lines_step(world, by_id, ev)


## Fills the per-tick trait arrays and returns being id -> being.
func _prepare(world: SimWorld) -> Dictionary:
	var by_id := {}
	var top := 0
	for b in world.beings:
		top = maxi(top, b.id + 1)
	with_friend.resize(top)
	with_friend.fill(0)
	_warm.resize(top)
	_warm.fill(0.0)
	_tempo.resize(top)
	_tempo.fill(0.0)
	_cur.resize(top)
	_cur.fill(0.0)
	_rest.resize(top)
	_rest.fill(0.0)
	for b in world.beings:
		var bid: int = b.id
		by_id[bid] = b
		var tr: Dictionary = b.persona.traits
		_warm[bid] = (float(tr.sociability) + float(tr.care)) / 2.0
		_tempo[bid] = float(tr.restless) - float(tr.steady)
		_cur[bid] = float(tr.curiosity)
		_rest[bid] = float(tr.restless)
	return by_id


# ---------------------------------------------------------------- 5.1 deaths

func _deaths(world: SimWorld, by_id: Dictionary) -> void:
	var dead: Array = []
	for id in known:
		if not by_id.has(id):
			dead.append(id)
	if dead.is_empty():
		return
	dead.sort()
	var friend := float(_cfg.lines.friend)
	var rs: Dictionary = world.stats.relationships
	for d in dead:
		var cands: Array = []
		var rm: Array = []
		var dead_name := ""
		for i in range(world.stats.deaths_list.size() - 1, -1, -1):
			if int(world.stats.deaths_list[i].being_id) == d:
				dead_name = str(world.stats.deaths_list[i].name)
				break
		for k in pairs:
			var p: Dictionary = pairs[k]
			if p.lo != d and p.hi != d:
				continue
			rm.append(k)
			var other: int = p.hi if p.lo == d else p.lo
			if by_id.has(other) and float(p.bond) >= friend:
				cands.append([float(p.bond), other])
		cands.sort_custom(func(x: Array, y: Array) -> bool:
			return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
		for c in cands:
			events.append({"kind": "grief", "a": int(c[1]), "b": d, "bond": float(c[0]), "name": dead_name})
		if dead_name != "":
			for i in mini(cands.size(), int(_cfg.log.grief_max)):
				var m: int = cands[i][1]
				var text := str(_cfg.text.grief).replace("{a}", str(by_id[m].name)).replace("{b}", dead_name)
				world._log("rel_grief", text, {"being_id": m, "other_id": d, "place": "", "building_id": null})
				rs.lines.grief += 1
		for k in rm:
			_remove_pair(k)
		var kept: Array = []
		for e in pending:
			if e.lo == d or e.hi == d:
				rs.lines_stale += 1
			else:
				kept.append(e)
		pending = kept
		known.erase(d)
		found_friend.erase(d)
		crew_drift_named.erase(d)


# ---------------------------------------------------------------- 5.2 births

func _births(world: SimWorld, by_id: Dictionary) -> void:
	var fresh: Array = []
	for b in world.beings:
		if not known.has(b.id):
			fresh.append(b)
	if fresh.is_empty():
		return
	fresh.sort_custom(func(x: Being, y: Being) -> bool: return x.id < y.id)
	var sd: Dictionary = _cfg.seed
	for b in fresh:
		assert(b.id < SHIFT, "being ids must stay below 2^20")
		known[b.id] = true
		if b.parent_id == 0 or not by_id.has(b.parent_id):
			continue
		var key := key_of(b.id, b.parent_id)
		if pairs.has(key):
			continue
		var p := _get_or_make(mini(b.id, b.parent_id), maxi(b.id, b.parent_id))
		_set_bond(p, float(sd.kin_base) + float(sd.kin_warmth) * (_warm[b.id] + _warm[b.parent_id]) / 2.0)
		p.kin = true
		_flag_step(p)
		_seeded[key] = true


# ---------------------------------------------------------------- 5.3 growth

## Returns key -> group index (into `_groups`: [place, building_id]) for every pair that grew this tick.
func _growth(world: SimWorld) -> Dictionary:
	var grown := {}
	var gr: Dictionary = _cfg.grow
	var af: Dictionary = _cfg.affinity
	var tick_h := float(_cfg.tick_h)
	var kinds := {}
	for bd in world.buildings.list:
		kinds[bd.id] = bd.kind
	var inside := {}
	var work_crew: Array = []
	var mine_groups := {}
	for b in world.beings:
		if b.is_inside():
			if b.state != "sleep":
				if not inside.has(b.building_id):
					inside[b.building_id] = []
				inside[b.building_id].append(b.id)
		elif b.state == "work":
			if b.job != null and b.job == world.buildings.site:
				work_crew.append(b.id)
		elif b.state == "mining" and b.mine != null:
			var s: Variant = b.mine.site
			if not mine_groups.has(s):
				mine_groups[s] = []
			mine_groups[s].append(b.id)
	present = {}
	_groups.clear()
	var bids: Array = inside.keys()
	bids.sort()
	for bid in bids:
		present[bid] = inside[bid]
	for bid in bids:
		var ids: Array = inside[bid]
		if ids.size() < 2:
			continue
		_groups.append([str(kinds.get(bid, "")), bid])
		_grow_group(grown, ids, _groups.size() - 1, float(gr.room_rate) * tick_h, float(gr.warmth_base), af)
	if world.buildings.site != null and work_crew.size() >= 2:
		_groups.append(["site", null])
		_grow_group(grown, work_crew, _groups.size() - 1, float(gr.work_rate) * tick_h, -1.0, af)
	var fields: Array = []
	fields.append_array(world.resources.ice_fields)
	fields.append_array(world.resources.pits)
	for f in fields:
		if mine_groups.has(f) and mine_groups[f].size() >= 2:
			_groups.append([f.kind, null])
			_grow_group(grown, mine_groups[f], _groups.size() - 1, float(gr.work_rate) * tick_h, -1.0, af)
	return grown


## Grows every pair of `ids` (spec 5.3). `rate` is room_rate x tick_h for a room (`warmth_base` >= 0: the room term
## warmth_base + mean warmth multiplies it) or work_rate x tick_h for a crew (`warmth_base` < 0: no warmth term).
func _grow_group(grown: Dictionary, ids: Array, gi: int, rate: float, warmth_base: float, af: Dictionary) -> void:
	var coef := float(af.tempo_gap_coef)
	var soften := float(af.curiosity_soften)
	var lo_aff := float(af.floor)
	var room := warmth_base >= 0.0
	var has_seeded := not _seeded.is_empty()
	var n := ids.size()
	for i in n:
		var a: int = ids[i]
		var wa := _warm[a]
		var ta := _tempo[a]
		var ca := _cur[a]
		for j in range(i + 1, n):
			var c: int = ids[j]
			var key := mini(a, c) * SHIFT + maxi(a, c)
			if grown.has(key):
				continue
			var gap := absf(ta - _tempo[c]) * (1.0 - soften * maxf(ca, _cur[c]))
			var aff := clampf(1.0 - coef * gap, lo_aff, 1.0)
			var k := rate * (warmth_base + (wa + _warm[c]) / 2.0) * aff if room else rate * aff
			var slot: int = _slot.get(key, -1)
			if slot < 0:
				_get_or_make(mini(a, c), maxi(a, c))
				slot = _slot[key]
			if has_seeded and _seeded.has(key):
				continue
			var nb: float = _sb[slot] + k * (1.0 - _sb[slot])
			_sb[slot] = nb
			_sp[slot].bond = nb
			grown[key] = gi
			if _sf[slot] & 1:
				with_friend[a] = 1
				with_friend[c] = 1


# ---------------------------------------------------------------- 5.5 decay, forgetting, flags

## Returns {friend: [...], close: [...], drift: [...]}: events in ascending pair key within each list.
## One pass over the slot mirror decays every pair that did not grow or get seeded this tick (same arithmetic, same order
## of operations); the pairs whose flags may change are then handled in ascending key order (the flag step, the counters
## and the events depend on that order).
func _decay_and_flags(world: SimWorld, by_id: Dictionary, grown: Dictionary) -> Dictionary:
	var ev := {"friend": [], "close": [], "drift": []}
	if _sk.size() != pairs.size():
		_rebuild_slots()
	var dc: Dictionary = _cfg.decay
	var ln: Dictionary = _cfg.lines
	var rate := float(dc.per_h) * float(_cfg.tick_h)
	var rbase := float(dc.restless_base)
	var hold := float(dc.close_hold)
	var forget := float(ln.forget_below)
	var f_on := float(ln.friend)
	var f_off := float(ln.friend_drop)
	var c_on := float(ln.close)
	var c_off := float(ln.close_drop)
	var rs: Dictionary = world.stats.relationships
	var n := _sk.size()
	if _rest.size() <= _max_id:
		_rest.resize(_max_id + 1)
	_mask.resize(n)
	_mask.fill(0)
	for k in grown:
		_mask[_slot[k]] = 1
	for k in _seeded:
		_mask[_slot[k]] = 1
	var maybe := PackedInt64Array()
	var forgot := PackedInt64Array()
	# Locals are cheaper than members in the hot loop; the bond mirror is written back after the pass.
	var mask := _mask
	var sf := _sf
	var sl := _sl
	var sh := _sh
	var sk := _sk
	var rest := _rest
	var sp := _sp
	var sb := _sb
	for i in n:
		if mask[i] != 0:
			continue
		var f := sf[i]
		var d := rate * (rbase + (rest[sl[i]] + rest[sh[i]]) / 2.0)
		if f & 2:
			d *= hold
		var b := maxf(0.0, sb[i] - d)
		sb[i] = b
		sp[i].bond = b
		if f & 2:
			if b < c_off:
				maybe.append(sk[i])
			elif f & 1:
				if b < f_off:
					maybe.append(sk[i])
			elif b >= f_on:
				maybe.append(sk[i])
		elif b >= c_on:
			maybe.append(sk[i])
		elif b >= f_on:
			if not (f & 1):
				maybe.append(sk[i])
		elif b < f_off:
			if f & 1:
				maybe.append(sk[i])
			elif b < forget:
				forgot.append(sk[i])
	_sb = sb
	for k in forgot:
		_remove_pair(k)
	var cand := maybe
	for k in grown:
		cand.append(k)
	cand.sort()
	for k in cand:
		var p: Dictionary = pairs[k]
		var gi: int = grown.get(k, -1)
		var r := _flag_step(p)
		if r == 0:
			continue
		var place: String = _groups[gi][0] if gi >= 0 else ""
		var bid: Variant = _groups[gi][1] if gi >= 0 else null
		if r & 1:
			if p.kin or p.crew:
				rs.friendships_renewed += 1
			else:
				events.append({"kind": "friend", "a": p.lo, "b": p.hi})
				rs.friendships_formed += 1
				if rs.first_friendship_sol == null:
					rs.first_friendship_sol = world.sol()
				if rs.first_mars_born_friendship_sol == null \
						and ((by_id.has(p.lo) and not by_id[p.lo].earth_born) \
						or (by_id.has(p.hi) and not by_id[p.hi].earth_born)):
					rs.first_mars_born_friendship_sol = world.sol()
				if not (found_friend.has(p.lo) and found_friend.has(p.hi)):
					ev.friend.append({"type": "friend", "lo": p.lo, "hi": p.hi, "place": place, "building_id": bid})
		if r & 4:
			events.append({"kind": "close", "a": p.lo, "b": p.hi})
			rs.close_formed += 1
			if not p.was_close:
				p.was_close = true
				if close_count.get(p.lo, 0) <= 1 and close_count.get(p.hi, 0) <= 1:
					ev.close.append({"type": "close_crew" if p.crew else "close", "lo": p.lo, "hi": p.hi,
							"place": place, "building_id": bid})
		if r & 2:
			if p.was_close:
				events.append({"kind": "lapse_close", "a": p.lo, "b": p.hi})
			elif not p.kin and not p.crew:
				events.append({"kind": "lapse", "a": p.lo, "b": p.hi})
			if p.was_close:
				rs.drifted += 1
				ev.drift.append({"type": "drift_close", "lo": p.lo, "hi": p.hi, "place": "", "building_id": null})
			if p.crew:
				rs.crew_drifted += 1
				if not p.was_close and not crew_drift_named.has(p.lo) and not crew_drift_named.has(p.hi):
					ev.drift.append({"type": "drift_crew", "lo": p.lo, "hi": p.hi, "place": "", "building_id": null})
	return ev


# ---------------------------------------------------------------- 5.6 log lines

func _lines_step(world: SimWorld, by_id: Dictionary, ev: Dictionary) -> void:
	var rs: Dictionary = world.stats.relationships
	if world.sol() != lines_sol:
		lines_sol = world.sol()
		lines_this_sol = 0
	var lg: Dictionary = _cfg.log
	var cap := maxi(int(lg.max_lines_per_sol), int(floor(float(world.beings.size()) / float(lg.pop_per_line))))
	var kept: Array = []
	var old := pending
	for e in old:
		_offer(world, by_id, e, cap, true, kept)
	for list in [ev.friend, ev.close, ev.drift]:
		for e in list:
			_offer(world, by_id, e, cap, false, kept)
	# A queued event that stayed put was counted when first queued; a new one is counted once, here.
	while kept.size() > int(lg.queue_max):
		kept.pop_front()
		rs.lines_dropped += 1
	pending = kept


## Revalidate, then log or queue one event (spec 5.6). Kept events are appended to `kept`.
func _offer(world: SimWorld, by_id: Dictionary, e: Dictionary, cap: int, queued: bool, kept: Array) -> void:
	var rs: Dictionary = world.stats.relationships
	var p: Variant = pairs.get(key_of(e.lo, e.hi))
	var lo: int = e.lo
	var hi: int = e.hi
	var ok: bool = p != null and by_id.has(lo) and by_id.has(hi)
	var form := ""
	var a := lo
	var b := hi
	if ok:
		match str(e.type):
			"friend":
				ok = p.friends
				var new_lo := not found_friend.has(lo)
				var new_hi := not found_friend.has(hi)
				if not (new_lo or new_hi):
					ok = false
				elif new_lo and new_hi:
					form = "friends"
				else:
					form = "found_friend"
					a = lo if new_lo else hi
					b = hi if new_lo else lo
			"close":
				ok = p.close
				form = "close"
			"close_crew":
				ok = p.close
				form = "close_crew"
			"drift_close":
				ok = not p.friends
				form = "drifted"
			"drift_crew":
				ok = not p.friends and not crew_drift_named.has(lo) and not crew_drift_named.has(hi)
				form = "drifted"
			_:
				ok = false
	if not ok:
		rs.lines_stale += 1
		return
	if lines_this_sol >= cap:
		kept.append(e)
		if not queued:
			rs.lines_capped += 1
		return
	var text := str(_cfg.text[form]).replace("{a}", str(by_id[a].name)).replace("{b}", str(by_id[b].name))
	if form == "friends" or form == "found_friend" or form == "close":
		var tp: Dictionary = _cfg.text.place
		text += " " + str(tp[e.place] if tp.has(e.place) else tp.other)
	world._log("rel_" + form, text, {"being_id": a, "other_id": b, "place": e.place, "building_id": e.building_id})
	lines_this_sol += 1
	rs.lines[form] += 1
	if str(e.type) == "friend":
		found_friend[lo] = true
		found_friend[hi] = true
	elif str(e.type) == "drift_crew":
		crew_drift_named[lo] = true
		crew_drift_named[hi] = true


# ---------------------------------------------------------------- 7 the trust reading

## Phase 11, after ages.on_sol: one reading appended to the three per-sol lists.
func on_sol(world: SimWorld) -> void:
	_cfg = SimData.relationships()
	_reading(world)


func _reading(world: SimWorld) -> void:
	var rs: Dictionary = world.stats.relationships
	if _sk.size() != pairs.size():
		_rebuild_slots()
	var ids: Array = []
	var top := 0
	for b in world.beings:
		ids.append(b.id)
		top = maxi(top, b.id + 1)
	ids.sort()
	# Union-find over living ids in packed arrays (a root is always the smallest id of its component, so the result does
	# not depend on the order the pairs are visited). alive: 1 for a living id; seen: 1 for an id with a friend pair.
	var uf := PackedInt32Array()
	uf.resize(top)
	var alive := PackedByteArray()
	alive.resize(top)
	alive.fill(0)
	var seen := PackedByteArray()
	seen.resize(top)
	seen.fill(0)
	for id in ids:
		uf[id] = id
		alive[id] = 1
	var friend_pairs := 0
	var close_pairs := 0
	var degree_n := 0
	var sf := _sf
	var sl := _sl
	var sh := _sh
	for i in sf.size():
		var f := sf[i]
		if f & 2:
			close_pairs += 1
		if not (f & 1):
			continue
		friend_pairs += 1
		var lo := sl[i]
		var hi := sh[i]
		if lo >= top or hi >= top or alive[lo] == 0 or alive[hi] == 0:
			continue
		if seen[lo] == 0:
			seen[lo] = 1
			degree_n += 1
		if seen[hi] == 0:
			seen[hi] = 1
			degree_n += 1
		var ra := _find_packed(uf, lo)
		var rb := _find_packed(uf, hi)
		if ra != rb:
			uf[maxi(ra, rb)] = mini(ra, rb)
	var pop := ids.size()
	var web := 0.0
	var second := 0.0
	var lonely := 0.0
	var fmean := 0.0
	if pop > 0:
		var sizes := {}
		for id in ids:
			var r := _find_packed(uf, id)
			sizes[r] = int(sizes.get(r, 0)) + 1
		var sz: Array = sizes.values()
		sz.sort()
		sz.reverse()
		web = float(sz[0]) / float(pop)
		if sz.size() > 1 and sz[1] >= 2:
			second = float(sz[1]) / float(pop)
		lonely = float(pop - degree_n) / float(pop)
		fmean = 2.0 * float(friend_pairs) / float(pop)
	rs.web_by_sol.append(web)
	rs.second_by_sol.append(second)
	rs.lonely_by_sol.append(lonely)
	rs.web_share = web
	rs.second_share = second
	rs.lonely_share = lonely
	rs.friends_mean = fmean
	rs.pairs = pairs.size()
	rs.friend_pairs = friend_pairs
	rs.close_pairs = close_pairs


## Root of x (no path compression: a packed array passed in would be copied on write).
static func _find_packed(uf: PackedInt32Array, x: int) -> int:
	var r := x
	while uf[r] != r:
		r = uf[r]
	return r


## Friend pairs as copies (emotions.md 9.1): {lo, hi, flags} for the pairs holding the `friends` flag; flag bits 1 close,
## 2 kin, 4 crew. Order unspecified (mirror order, or dictionary order when the mirror is out of step). Read-only.
func friend_pairs() -> Dictionary:
	var lo := PackedInt32Array()
	var hi := PackedInt32Array()
	var fl := PackedByteArray()
	if _sk.size() == _sf.size() and _sf.size() == pairs.size():
		for i in _sf.size():
			var f := _sf[i]
			if not (f & 1):
				continue
			var p: Dictionary = _sp[i]
			lo.append(_sl[i])
			hi.append(_sh[i])
			fl.append((1 if (f & 2) else 0) | (2 if p.kin else 0) | (4 if p.crew else 0))
	else:
		for k in pairs:
			var p: Dictionary = pairs[k]
			if not p.friends:
				continue
			lo.append(int(p.lo))
			hi.append(int(p.hi))
			fl.append((1 if p.close else 0) | (2 if p.kin else 0) | (4 if p.crew else 0))
	return {"lo": lo, "hi": hi, "flags": fl}


## The friends of a being, ascending by other id: [{id, close, kin, crew, bond}]. Read-only; view side, never in a sim step.
func friends_of(id: int) -> Array:
	var out: Array = []
	for k in pairs:
		var p: Dictionary = pairs[k]
		if not p.friends or (p.lo != id and p.hi != id):
			continue
		out.append({"id": p.hi if p.lo == id else p.lo, "close": p.close, "kin": p.kin, "crew": p.crew, "bond": p.bond})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.id < y.id)
	return out


# ---------------------------------------------------------------- 8 the pull (read by Being._restless_travel)

## Added room weight for being `id` toward building `building_id` (spec 8). Called only when a pull is above 0.0.
func pull(id: int, building_id: int, friend_pull: float, lonely_pull: float, cap: int) -> float:
	var ids: Variant = present.get(building_id)
	if ids == null:
		return 0.0
	var friends_there := 0
	var people := 0
	for x in ids:
		if x == id:
			continue
		people += 1
		if are_friends(id, x):
			friends_there += 1
	var v := friend_pull * float(mini(friends_there, cap))
	if int(friend_count.get(id, 0)) == 0:
		v += lonely_pull * float(mini(people, cap))
	return v


# ---------------------------------------------------------------- pair bookkeeping

func _get_or_make(lo: int, hi: int) -> Dictionary:
	var key := lo * SHIFT + hi
	var p: Variant = pairs.get(key)
	if p == null:
		p = {"lo": lo, "hi": hi, "bond": 0.0, "friends": false, "close": false, "was_close": false,
				"kin": false, "crew": false}
		pairs[key] = p
		_slot[key] = _sk.size()
		_sk.append(key)
		_sl.append(lo)
		_sh.append(hi)
		_sb.append(0.0)
		_sf.append(0)
		_sp.append(p)
		_max_id = maxi(_max_id, maxi(lo, hi))
	return p


func _set_bond(p: Dictionary, v: float) -> void:
	p.bond = v
	_sb[_slot[int(p.lo) * SHIFT + int(p.hi)]] = v


## Rebuilds the slot mirror from `pairs` (only when something outside the module changed the set of pairs).
func _rebuild_slots() -> void:
	_slot.clear()
	_sk.clear()
	_sl.clear()
	_sh.clear()
	_sb.clear()
	_sf.clear()
	_sp.clear()
	for k in pairs:
		var p: Dictionary = pairs[k]
		_slot[k] = _sk.size()
		_sk.append(k)
		_sl.append(p.lo)
		_sh.append(p.hi)
		_sb.append(p.bond)
		_sf.append((1 if p.friends else 0) | (2 if p.close else 0))
		_sp.append(p)
		_max_id = maxi(_max_id, maxi(int(p.lo), int(p.hi)))


func _remove_pair(key: int) -> void:
	var p: Dictionary = pairs[key]
	if p.friends:
		_bump(friend_count, p.lo, -1)
		_bump(friend_count, p.hi, -1)
	if p.close:
		_bump(close_count, p.lo, -1)
		_bump(close_count, p.hi, -1)
	pairs.erase(key)
	var i: int = _slot[key]
	var last := _sk.size() - 1
	if i != last:
		var lk := _sk[last]
		_sk[i] = lk
		_sl[i] = _sl[last]
		_sh[i] = _sh[last]
		_sb[i] = _sb[last]
		_sf[i] = _sf[last]
		_sp[i] = _sp[last]
		_slot[lk] = i
	_sk.resize(last)
	_sl.resize(last)
	_sh.resize(last)
	_sb.resize(last)
	_sf.resize(last)
	_sp.resize(last)
	_slot.erase(key)


static func _bump(d: Dictionary, id: int, delta: int) -> void:
	var n := int(d.get(id, 0)) + delta
	if n <= 0:
		d.erase(id)
	else:
		d[id] = n


## Applies the flag hysteresis to a pair and keeps the counts in step. Returns a bit set:
## 1 friends set, 2 friends cleared, 4 close set, 8 close cleared.
func _flag_step(p: Dictionary) -> int:
	var ln: Dictionary = _cfg.lines
	var r := 0
	var b: float = p.bond
	if not p.friends and b >= float(ln.friend):
		p.friends = true
		_bump(friend_count, p.lo, 1)
		_bump(friend_count, p.hi, 1)
		r |= 1
	elif p.friends and b < float(ln.friend_drop):
		p.friends = false
		_bump(friend_count, p.lo, -1)
		_bump(friend_count, p.hi, -1)
		r |= 2
	if not p.close and b >= float(ln.close):
		p.close = true
		_bump(close_count, p.lo, 1)
		_bump(close_count, p.hi, 1)
		r |= 4
	elif p.close and b < float(ln.close_drop):
		p.close = false
		_bump(close_count, p.lo, -1)
		_bump(close_count, p.hi, -1)
		r |= 8
	if r != 0:
		_sf[_slot[int(p.lo) * SHIFT + int(p.hi)]] = (1 if p.friends else 0) | (2 if p.close else 0)
	return r
