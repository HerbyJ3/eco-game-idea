class_name Relationships
extends RefCounted
## Relationships and trust (spec docs/specs/relationships.md revision 4, Task 4). Every pair of beings that shares
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

## Tick-local.
var _cfg: Dictionary = {}
var _seeded: Dictionary = {}
var _info: Dictionary = {}


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
	p.bond = bond
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
			p.bond = crew
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
	var by_id := {}
	_info.clear()
	for b in world.beings:
		by_id[b.id] = b
		var tr: Dictionary = b.persona.traits
		_info[b.id] = PackedFloat64Array([(float(tr.sociability) + float(tr.care)) / 2.0,
				float(tr.restless) - float(tr.steady), float(tr.curiosity), float(tr.restless)])
	_seeded.clear()
	_deaths(world, by_id)
	_births(world, by_id)
	var grown := _growth(world)
	var ev := _decay_and_flags(world, by_id, grown)
	_lines_step(world, by_id, ev)


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
		var dead_name := ""
		for i in range(world.stats.deaths_list.size() - 1, -1, -1):
			if int(world.stats.deaths_list[i].being_id) == d:
				dead_name = str(world.stats.deaths_list[i].name)
				break
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
		p.bond = float(sd.kin_base) + float(sd.kin_warmth) * (_info[b.id][0] + _info[b.parent_id][0]) / 2.0
		p.kin = true
		_flag_step(p)
		_seeded[key] = true


# ---------------------------------------------------------------- 5.3 growth

## Returns key -> [place, building_id] for every pair that grew this tick.
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
	var bids: Array = inside.keys()
	bids.sort()
	for bid in bids:
		present[bid] = inside[bid]
	for bid in bids:
		var ids: Array = inside[bid]
		if ids.size() < 2:
			continue
		var kind := str(kinds.get(bid, ""))
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var a: int = ids[i]
				var c: int = ids[j]
				var rf := float(gr.warmth_base) + (_info[a][0] + _info[c][0]) / 2.0
				var k := float(gr.room_rate) * tick_h * rf * _affinity(a, c, af)
				_grow(grown, a, c, k, kind, bid)
	if world.buildings.site != null and work_crew.size() >= 2:
		_grow_crew(grown, work_crew, "site", gr, af, tick_h)
	var fields: Array = []
	fields.append_array(world.resources.ice_fields)
	fields.append_array(world.resources.pits)
	for f in fields:
		if mine_groups.has(f) and mine_groups[f].size() >= 2:
			_grow_crew(grown, mine_groups[f], f.kind, gr, af, tick_h)
	return grown


func _grow_crew(grown: Dictionary, ids: Array, place: String, gr: Dictionary, af: Dictionary, tick_h: float) -> void:
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var k := float(gr.work_rate) * tick_h * _affinity(ids[i], ids[j], af)
			_grow(grown, ids[i], ids[j], k, place, null)


func _affinity(a: int, b: int, af: Dictionary) -> float:
	var gap := absf(_info[a][1] - _info[b][1]) * (1.0 - float(af.curiosity_soften) * maxf(_info[a][2], _info[b][2]))
	return clampf(1.0 - float(af.tempo_gap_coef) * gap, float(af.floor), 1.0)


func _grow(grown: Dictionary, a: int, b: int, k: float, place: String, building_id: Variant) -> void:
	var key := key_of(a, b)
	if grown.has(key):
		return
	var p := _get_or_make(mini(a, b), maxi(a, b))
	if _seeded.has(key):
		return
	p.bond += k * (1.0 - p.bond)
	grown[key] = [place, building_id]


# ---------------------------------------------------------------- 5.5 decay, forgetting, flags

## Returns {friend: [...], close: [...], drift: [...]}: events in ascending pair key within each list.
func _decay_and_flags(world: SimWorld, by_id: Dictionary, grown: Dictionary) -> Dictionary:
	var ev := {"friend": [], "close": [], "drift": []}
	var dc: Dictionary = _cfg.decay
	var tick_h := float(_cfg.tick_h)
	var forget := float(_cfg.lines.forget_below)
	var rs: Dictionary = world.stats.relationships
	var keys: Array = pairs.keys()
	keys.sort()
	for k in keys:
		if _seeded.has(k):
			continue
		var p: Dictionary = pairs[k]
		var g: Variant = grown.get(k)
		if g == null:
			var rl: float = _info[p.lo][3] if _info.has(p.lo) else 0.0
			var rh: float = _info[p.hi][3] if _info.has(p.hi) else 0.0
			var d := float(dc.per_h) * tick_h * (float(dc.restless_base) + (rl + rh) / 2.0) \
					* (float(dc.close_hold) if p.close else 1.0)
			p.bond = maxf(0.0, p.bond - d)
			if p.bond < forget and not p.friends and not p.close:
				_remove_pair(k)
				continue
		var r := _flag_step(p)
		if r == 0:
			continue
		var place: String = g[0] if g != null else ""
		var bid: Variant = g[1] if g != null else null
		if r & 1:
			if p.kin or p.crew:
				rs.friendships_renewed += 1
			else:
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
			rs.close_formed += 1
			if not p.was_close:
				p.was_close = true
				if close_count.get(p.lo, 0) <= 1 and close_count.get(p.hi, 0) <= 1:
					ev.close.append({"type": "close_crew" if p.crew else "close", "lo": p.lo, "hi": p.hi,
							"place": place, "building_id": bid})
		if r & 2:
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
	var uf := {}
	var ids: Array = []
	for b in world.beings:
		ids.append(b.id)
	ids.sort()
	for id in ids:
		uf[id] = id
	var friend_pairs := 0
	var close_pairs := 0
	var degree := {}
	for k in pairs:
		var p: Dictionary = pairs[k]
		if p.close:
			close_pairs += 1
		if not p.friends:
			continue
		friend_pairs += 1
		if not (uf.has(p.lo) and uf.has(p.hi)):
			continue
		degree[p.lo] = true
		degree[p.hi] = true
		var ra := _find(uf, p.lo)
		var rb := _find(uf, p.hi)
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
			var r := _find(uf, id)
			sizes[r] = int(sizes.get(r, 0)) + 1
		var sz: Array = sizes.values()
		sz.sort()
		sz.reverse()
		web = float(sz[0]) / float(pop)
		if sz.size() > 1 and sz[1] >= 2:
			second = float(sz[1]) / float(pop)
		lonely = float(pop - degree.size()) / float(pop)
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


static func _find(uf: Dictionary, x: int) -> int:
	var r := x
	while uf[r] != r:
		r = uf[r]
	while uf[x] != r:
		var nx: int = uf[x]
		uf[x] = r
		x = nx
	return r


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
	return p


func _remove_pair(key: int) -> void:
	var p: Dictionary = pairs[key]
	if p.friends:
		_bump(friend_count, p.lo, -1)
		_bump(friend_count, p.hi, -1)
	if p.close:
		_bump(close_count, p.lo, -1)
		_bump(close_count, p.hi, -1)
	pairs.erase(key)


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
	return r
