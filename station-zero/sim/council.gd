class_name Council
extends RefCounted
## The Council (docs/specs/council.md revision 5): voices, trust readings, lean and stance, gatherings, meetings, the dome
## proposal. Pure logic: draws no random numbers, writes only stats.council, the log and (via Ages.enter_age) the age. Holds no
## reference to the world; every method takes it as an argument.

var cfg: Dictionary = {}
var parent_of: Dictionary = {}
var trust_win: Array = []
var chosen_win: Array = []
var stance: Dictionary = {}
var hard_win: Array = []
var best: Dictionary = {}
var seen_ticks := 0
var last_session_sol := 0
var open: Variant = null
var set_aside: Dictionary = {}
var raised_ever: Dictionary = {}
var pledged: Dictionary = {}
var quiet_logged := false
var circles_count := 0
var circles_last_sol := -1
var aftermath: Variant = null
var after_pledge_logged := false
var line_sol := -1
var _lean: Dictionary = {}
var _terms: Dictionary = {}
var _friends: Dictionary = {}
var _term_s := -1
var _cands: Array = []


static func new_stats() -> Dictionary:
	return {"trust": 0.0, "chosen": 0.0, "voices": 0, "trust_by_sol": [], "chosen_by_sol": [], "first_council_sol": null,
			"sessions": 0, "session_log": [], "proposals": [], "pledge_sol": null, "chapters": [], "lines": {}, "lines_dropped": 0}


func begin(world: SimWorld, founders_world: bool) -> void:
	cfg = SimData.council().duplicate(true)
	_record_lineage(world)
	if founders_world:
		world.stats.council.trust_by_sol.append(1.0)
		world.stats.council.chosen_by_sol.append(0.0)


func _record_lineage(world: SimWorld) -> void:
	for b in world.beings:
		if not parent_of.has(b.id):
			parent_of[b.id] = b.parent_id


func is_voice(world: SimWorld, id: int) -> bool:
	for b in world.beings:
		if b.id == id:
			return _is_voice_b(world, b)
	return false


func _is_voice_b(world: SimWorld, b) -> bool:
	return b.earth_born or world.t - b.born_t >= float(cfg.voice.min_age_sols) * world.clock.sol_h - SimWorld.STEP_EPS


func _lin(id: int) -> Array:
	var out: Array = [id]
	var cur := id
	for g in int(cfg.chosen.kin_generations):
		cur = int(parent_of.get(cur, 0))
		if cur == 0:
			break
		out.append(cur)
	return out


func is_family(a: int, b: int) -> bool:
	var la := _lin(a)
	for x in _lin(b):
		if x in la:
			return true
	return false


func stance_of(id: int) -> float:
	return float(stance.get(id, 0.0))


func lean_of(id: int) -> float:
	return float(_lean.get(id, 0.0))


func lean_terms_of(id: int) -> Dictionary:
	return _terms.get(id, {})


func _st(world: SimWorld) -> Dictionary:
	return world.stats.council


func _topic_cfg(topic: String) -> Dictionary:
	return cfg[topic]


# ---------------------------------------------------------------- phase 11b

func on_step(world: SimWorld) -> void:
	if world.relationships == null or not world.relationships_enabled:
		return
	if world.relationships.ticks == seen_ticks:
		return
	seen_ticks = world.relationships.ticks
	if world.ages.age != "council":
		return
	var vs := {}
	for b in world.beings:
		if _is_voice_b(world, b):
			vs[b.id] = true
	var bids: Array = world.relationships.present.keys()
	bids.sort()
	for bid in bids:
		var ids: Array = []
		for id in world.relationships.present[bid]:
			if vs.has(id):
				ids.append(id)
		ids.sort()
		var cnt := ids.size()
		if cnt > int(best.get("count", 0)):
			best = {"building_id": bid, "count": cnt, "ids": ids, "t": world.t}


# ---------------------------------------------------------------- sol

func on_sol(world: SimWorld) -> void:
	_cands = []
	var n := world.sol()
	var st := _st(world)
	_record_lineage(world)
	if world.relationships == null or not world.relationships_enabled:
		var live := 0
		for b in world.beings:
			if _is_voice_b(world, b):
				live += 1
		st.trust_by_sol.append(0.0)
		st.chosen_by_sol.append(0.0)
		_push_win(trust_win, 0.0)
		_push_win(chosen_win, 0.0)
		st.trust = 0.0
		st.chosen = 0.0
		st.voices = live
		stance.clear()
		return
	var age := world.ages.age
	if age == "landing":
		# Spec 11.1 remedy (a): nothing reads trust, chosen share, lean or stance in Landing (Landing never enters, and the
		# entry windows hold 20 readings against 30 settled sols), so the pair walk and the sway are skipped. The series carry
		# the last reading forward so they keep the length of pop_by_sol; the windows are not pushed. The hard window is kept.
		_hard_entry(world)
		st.trust_by_sol.append(st.trust_by_sol.back() if not st.trust_by_sol.is_empty() else 0.0)
		st.chosen_by_sol.append(st.chosen_by_sol.back() if not st.chosen_by_sol.is_empty() else 0.0)
	else:
		_readings(world, st)
		_hard_entry(world)
		_lean_stance(world)
	if age != "council" and open != null:
		_lapse(world)
	if world.colony.pop() == 0:
		return
	if age == "settlement":
		if _decide_entry(world, n):
			var how := "council" if st.first_council_sol == null else "council_again"
			var key := "enter" if how == "council" else "enter_again"
			var text: String = str(cfg.text[key]) + " " + str(SimData.ages().season_phrases[world.clock.seasons.find(world.clock.season(world.t))])
			if st.first_council_sol == null:
				st.first_council_sol = n
			world.ages.enter_age(world, "council", how, text)
			best = {}
			last_session_sol = n
			quiet_logged = false
		else:
			_circles(world, n)
	elif age == "council":
		if _decide_split(world, n):
			world.ages.enter_age(world, "settlement", "council_split", str(cfg.text.split) + " " + str(SimData.ages().season_phrases[world.clock.seasons.find(world.clock.season(world.t))]))
			_lapse(world)
			best = {}
		else:
			_council_sol(world, n)
	_aftermath(world, n)
	_flush(world)


## Evaluated once, at the first boundary at or after due_sol in any age (5.9): cleared whatever happens; a line only when
## the colony is still in Council and the doubter is still a voice.
func _aftermath(world: SimWorld, n: int) -> void:
	if aftermath == null or n < int(aftermath.due_sol):
		return
	var d: int = aftermath.doubter_id
	aftermath = null
	if str(world.ages.age) != "council" or not is_voice(world, d):
		return
	var key := "aftermath_round" if stance_of(d) > float(cfg.support.yes_above) else "aftermath_still"
	_offer(PRIO.aftermath, "council_aftermath", key, _fmt(str(cfg.dome.text[key]), {"b": _name(world, d)}),
			{"being_id": d, "other_id": null, "building_id": null, "topic": "dome"})


func _push_win(win: Array, v: float) -> void:
	win.append(v)
	while win.size() > int(cfg.trust.window_sols):
		win.pop_front()


func _readings(world: SimWorld, st: Dictionary) -> void:
	var voices: Array = []
	var top := 0
	for b in world.beings:
		top = maxi(top, b.id + 1)
		if _is_voice_b(world, b):
			voices.append(b.id)
	voices.sort()
	var nv := voices.size()
	# Packed per-id state (ids are small and dense): voice flag, union-find parent (a root is the smaller id, so the result
	# does not depend on the order the pairs are visited), chosen-friend counts.
	var isv := PackedByteArray()
	isv.resize(top)
	isv.fill(0)
	var uf := PackedInt32Array()
	uf.resize(top)
	var chosen_cnt := PackedInt32Array()
	chosen_cnt.resize(top)
	chosen_cnt.fill(0)
	_friends = {}
	var lin := {}  # lineage set of each voice (itself plus up to kin_generations ancestors)
	for id in voices:
		isv[id] = 1
		uf[id] = id
		_friends[id] = []
		lin[id] = _lin(id)
	# Friend pairs of two voices, as parallel packed arrays: the two ends and flag bits (1 close, 2 kin, 4 crew).
	var pa := PackedInt32Array()
	var pb := PackedInt32Array()
	var pf := PackedByteArray()
	var fp: Dictionary = world.relationships.friend_pairs()
	var fp_lo: PackedInt32Array = fp.lo
	var fp_hi: PackedInt32Array = fp.hi
	var fp_fl: PackedByteArray = fp.flags
	for i in fp_lo.size():
		var a := fp_lo[i]
		var b := fp_hi[i]
		if a >= top or b >= top or isv[a] == 0 or isv[b] == 0:
			continue
		pa.append(a)
		pb.append(b)
		pf.append(fp_fl[i])
	for k in pa.size():
		var a := pa[k]
		var b := pb[k]
		var fl := pf[k]
		var ra := a
		while uf[ra] != ra:
			ra = uf[ra]
		var rb := b
		while uf[rb] != rb:
			rb = uf[rb]
		if ra != rb:
			uf[maxi(ra, rb)] = mini(ra, rb)
		# friend entries are friend_id * 2 + close, so a plain sort orders each list by friend id
		_friends[a].append(b * 2 + (fl & 1))
		_friends[b].append(a * 2 + (fl & 1))
		if fl & 6:
			continue
		var la: Array = lin[a]
		var lb: Array = lin[b]
		var family := false
		for x in la:
			if x in lb:
				family = true
				break
		if not family:
			chosen_cnt[a] += 1
			chosen_cnt[b] += 1
	for id in voices:
		_friends[id].sort()
	var sizes := PackedInt32Array()
	sizes.resize(top)
	sizes.fill(0)
	var big := 0
	var ch := 0
	var need := int(cfg.entry.chosen_friends_min)
	for id in voices:
		var r: int = id
		while uf[r] != r:
			r = uf[r]
		sizes[r] += 1
		big = maxi(big, sizes[r])
		if chosen_cnt[id] >= need:
			ch += 1
	var trust := float(big) / float(nv) if nv > 0 else 0.0
	var chosen := float(ch) / float(nv) if nv > 0 else 0.0
	st.trust = trust
	st.chosen = chosen
	st.voices = nv
	st.trust_by_sol.append(trust)
	st.chosen_by_sol.append(chosen)
	_push_win(trust_win, trust)
	_push_win(chosen_win, chosen)


func _hard_entry(world: SimWorld) -> void:
	var ac: Dictionary = SimData.ages().sample
	var col: Colony = world.colony
	var pop := col.pop()
	var air := col.oxygen < float(ac.o2_min_fraction) * col.o2_cap()
	var food := col.food < float(ac.food_min_fraction) * col.food_cap()
	var use := float(pop) * float(SimData.colony().consumption.ice_per_being) * world.clock.sol_h
	var ice := col.ice < float(ac.ice_min_sols) * use - Ages.CMP_EPS
	hard_win.append({"hard": air or food or ice, "ice": ice, "air": air, "food": food})
	while hard_win.size() > int(cfg.cond.hard_window_sols):
		hard_win.pop_front()


func hard_share() -> float:
	var h := 0
	for e in hard_win:
		if e.hard:
			h += 1
	return float(h) / float(int(cfg.cond.hard_window_sols))


func hard_clause() -> String:
	var best_n := 0
	var best_k := "ice"
	for k in ["ice", "air", "food"]:
		var c := 0
		for e in hard_win:
			if e[k]:
				c += 1
		if c > best_n:
			best_n = c
			best_k = k
	return best_k


func _lean_stance(world: SimWorld) -> void:
	var lc: Dictionary = cfg.dome.lean
	var cc: Dictionary = cfg.dome.cond
	var c := float(lc.trait_centre)
	var pop := world.colony.pop()
	var means := clampf(world.colony.regolith / world.colony.regolith_target(), 0.0, 1.0)
	var size := clampf((float(pop) - float(cc.size_from)) / float(cc.size_span), 0.0, 1.0)
	var hard := hard_share()
	var voices: Array = []
	var by_id := {}
	for b in world.beings:
		if _is_voice_b(world, b):
			voices.append(b.id)
			by_id[b.id] = b
	voices.sort()
	var kids := {}  # parents of a living being born within child_sols (inclusive, revision 4)
	var child_h := float(cc.child_sols) * world.clock.sol_h + SimWorld.STEP_EPS
	for o in world.beings:
		if o.parent_id != 0 and world.t - o.born_t <= child_h:
			kids[o.parent_id] = true
	var prev := stance
	_lean = {}
	_terms = {}
	var w_amb := float(lc.ambition)
	var w_cau := float(lc.caution)
	var k_size := float(lc.size) * size
	var k_means := float(lc.means) * (means - float(lc.means_centre))
	var k_hard := float(lc.hard) * hard
	var k_child := float(lc.child)
	var base := float(lc.base)
	for id in voices:
		var tr: Dictionary = by_id[id].persona.traits
		var amb := (float(tr.drive) + float(tr.curiosity) + float(tr.restless)) / 3.0
		var cau := (float(tr.steady) + float(tr.care)) / 2.0
		var personal := w_amb * (amb - c) - w_cau * (cau - c)
		var t_size := k_size * (amb / c)
		var t_means := k_means * (amb / c)
		var t_hard := k_hard * (cau / c)
		var t_child := k_child if kids.has(id) else 0.0
		_terms[id] = {"personal": personal, "size": t_size, "means": t_means, "hard": t_hard, "child": t_child}
		_lean[id] = clampf(personal + t_size + t_means - t_hard + t_child + base, -1.0, 1.0)
	var ns := {}
	var sw := float(cfg.sway.share)
	var cw := float(cfg.sway.close_weight)
	for id in voices:
		var fr: Array = _friends.get(id, [])
		if fr.is_empty():
			ns[id] = _lean[id]
			continue
		var num := 0.0
		var den := 0.0
		for f in fr:
			var fid: int = f >> 1
			var w := cw if (f & 1) else 1.0
			var sj: float = float(prev[fid]) if prev.has(fid) else float(_lean[fid])
			num += w * sj
			den += w
		ns[id] = (1.0 - sw) * _lean[id] + sw * num / den
	stance = ns


# ---------------------------------------------------------------- entry, split

func _last_hist(world: SimWorld, age: String) -> int:
	var h: Array = world.stats.age_history
	for i in range(h.size() - 1, -1, -1):
		if str(h[i].age) == age:
			return int(h[i].sol)
	return -1


func _win_ok(win: Array, min_v: float, ok_min: int, recent: int) -> bool:
	if win.size() < int(cfg.trust.window_sols):
		return false
	var ok := 0
	for v in win:
		if float(v) >= min_v:
			ok += 1
	if ok < ok_min:
		return false
	for i in range(win.size() - recent, win.size()):
		if float(win[i]) < min_v:
			return false
	return true


func _decide_entry_parts(world: SimWorld, n: int) -> Dictionary:
	var e: Dictionary = cfg.entry
	var s := _last_hist(world, "settlement")
	return {"settled": s >= 0 and n - s >= int(e.settled_sols),
			"web": _win_ok(trust_win, float(e.trust_share_min), int(e.trust_ok_min), int(e.recent_ok)),
			"chosen": _win_ok(chosen_win, float(e.chosen_share_min), int(e.trust_ok_min), int(e.recent_ok)),
			"voices": int(_st(world).voices) >= int(e.voices_min)}


func _decide_entry(world: SimWorld, n: int) -> bool:
	var p := _decide_entry_parts(world, n)
	return p.settled and p.web and p.chosen and p.voices


func _decide_split(world: SimWorld, n: int) -> bool:
	var c := _last_hist(world, "council")
	if n - c < int(cfg.min_dwell_sols):
		return false
	var x: Dictionary = cfg.exit
	if trust_win.size() < int(cfg.trust.window_sols):
		return false
	var below := 0
	for v in trust_win:
		if float(v) < float(x.trust_share_below):
			below += 1
	if below < int(x.split_min):
		return false
	for i in range(trust_win.size() - int(x.recent_below), trust_win.size()):
		if float(trust_win[i]) >= float(x.trust_share_below):
			return false
	return true


func _lapse(world: SimWorld) -> void:
	if open != null:
		var pr: Array = _st(world).proposals
		if not pr.is_empty():
			pr.back().outcome = "lapsed"
			pr.back().outcome_sol = world.sol()
		open = null


# ---------------------------------------------------------------- lines

## Line priorities of spec 7.4: when two Council lines fall on one boundary the higher wins.
const PRIO := {"outcome": 7, "divided": 6, "raise": 5, "quiet": 4, "after_pledge": 3, "aftermath": 2, "circles": 1}

func _offer(prio: int, kind: String, key: String, text: String, extra: Dictionary) -> void:
	_cands.append({"prio": prio, "kind": kind, "key": key, "text": text, "extra": extra})


func _flush(world: SimWorld) -> void:
	if _cands.is_empty():
		return
	var win: Dictionary = _cands[0]
	for c in _cands:
		if int(c.prio) > int(win.prio):
			win = c
	var st := _st(world)
	world._log(win.kind, win.text, win.extra)
	st.lines[win.key] = int(st.lines.get(win.key, 0)) + 1
	st.lines_dropped += _cands.size() - 1
	line_sol = world.sol()
	_cands = []


func _name(world: SimWorld, id: Variant) -> String:
	for b in world.beings:
		if b.id == id:
			return b.name
	return ""


func _fmt(text: String, sub: Dictionary) -> String:
	var s := text
	for k in sub:
		s = s.replace("{%s}" % k, str(sub[k]))
	return s


func _place(world: SimWorld, bid: Variant) -> String:
	var kind := ""
	if bid != null:
		var bb = world.buildings.get_building(int(bid))
		if bb != null:
			kind = str(bb.kind)
	return str(cfg.text.place.get(kind, cfg.text.place.other))


func _circles(world: SimWorld, n: int) -> void:
	var s := _last_hist(world, "settlement")
	if s != _term_s:
		_term_s = s
		circles_count = 0
		circles_last_sol = -1
	var lc: Dictionary = cfg.lines
	if circles_count >= int(lc.circles_max):
		return
	var due := false
	if circles_count == 0:
		due = n - s >= int(cfg.entry.settled_sols) + int(lc.circles_after_sols)
	else:
		due = n - circles_last_sol >= int(lc.circles_again_sols)
	if not due:
		return
	var few := int(_st(world).voices) < int(cfg.entry.voices_min)
	var key := "circles_few" if few else ("circles" if circles_count == 0 else "circles_again")
	circles_count += 1
	circles_last_sol = n
	_offer(PRIO.circles, "council_circles", key, str(cfg.text[key]), {"being_id": null, "other_id": null, "building_id": null, "topic": null})


# ---------------------------------------------------------------- council sol

func _council_sol(world: SimWorld, n: int) -> void:
	var st := _st(world)
	var si: Dictionary = cfg.session
	if not best.is_empty() and world.t - float(best.t) > float(si.gathering_max_age_sols) * world.clock.sol_h + SimWorld.STEP_EPS:
		best = {}
	var held := false
	var voices := int(st.voices)
	if voices > 0 and n - last_session_sol >= int(si.interval_sols) and not best.is_empty() \
			and int(best.count) >= maxi(int(si.min_voices), int(ceil(float(si.min_voices_share) * voices - Ages.CMP_EPS))):
		held = true
		_meeting(world, n)
	if held:
		last_session_sol = n
		best = {}


func _yes_no(world: SimWorld) -> Array:
	var y: Array = []
	var no: Array = []
	var sc: Dictionary = cfg.support
	for id in stance:
		if float(stance[id]) > float(sc.yes_above):
			y.append(id)
		elif float(stance[id]) < float(sc.no_below):
			no.append(id)
	y.sort()
	no.sort()
	return [y, no]


func _meeting(world: SimWorld, n: int) -> void:
	var st := _st(world)
	st.sessions += 1
	var yn := _yes_no(world)
	st.session_log.append({"sol": n, "building_id": best.building_id, "present": best.count, "voices": st.voices,
			"yes": yn[0].size(), "no": yn[1].size(), "hard": hard_share() >= float(cfg.lines.hard_share_min)})
	var topic := "dome"
	var tcfg := _topic_cfg(topic)
	if open == null and not pledged.has(topic):
		# raise
		var ok := not set_aside.has(topic)
		if not ok:
			ok = n - int(set_aside[topic].sol) >= int(cfg.proposal.reraise_sols)
			if ok and bool(set_aside[topic].hard):
				ok = hard_share() < float(cfg.lines.hard_share_min)
		var raised := false
		if ok:
			var pid := -1
			var ps := -9.0
			for id in best.ids:
				if stance.has(id):
					var s := stance_of(id)
					if pid < 0 or s > ps or (s == ps and id < pid):
						pid = id
						ps = s
			if pid >= 0 and ps > float(cfg.support.yes_above):
				raised = true
				var again := raised_ever.has(topic)
				raised_ever[topic] = true
				var key := "proposal_again" if again else "proposal"
				_offer(PRIO.raise, "council_" + key, key, _fmt(str(tcfg.text[key]), {"a": _name(world, pid), "place": _place(world, best.building_id)}),
						{"being_id": pid, "other_id": null, "building_id": best.building_id, "topic": topic})
				st.proposals.append({"topic": topic, "raised_sol": n, "proposer_id": pid, "again": again, "outcome": null,
						"outcome_sol": null, "reason": null, "hard": null})
				open = {"topic": topic, "raised_sol": n, "proposer_id": pid, "votes": 0, "carry_run": 0, "reject_run": 0,
						"divided": false, "no_speaker_id": null}
		if ok and not raised and not quiet_logged:  # a raise blocked by a set-aside window asks no one and logs no quiet line
			quiet_logged = true
			var hard := hard_share() >= float(cfg.lines.hard_share_min)
			var qk := "quiet_hard" if hard else "quiet"
			_offer(PRIO.quiet, "council_quiet", qk, _fmt(str(cfg.text[qk]), {"clause": cfg.text.clause[hard_clause()]}),
					{"being_id": null, "other_id": null, "building_id": best.building_id, "topic": null})
	elif open != null:
		if int(open.raised_sol) == n:
			return
		_vote(world, n, yn, tcfg)
	if pledged.has(topic) and not after_pledge_logged and open == null:
		if n - int(pledged[topic]) >= int(cfg.lines.after_pledge_sols):
			after_pledge_logged = true
			_offer(PRIO.after_pledge, "council_after_pledge", "after_pledge", str(tcfg.text.after_pledge),
					{"being_id": null, "other_id": null, "building_id": best.building_id, "topic": topic})


func _cmp_ge(count: int, total: int, share: float) -> bool:
	return float(count) >= share * float(total) - Ages.CMP_EPS


func _vote(world: SimWorld, n: int, yn: Array, tcfg: Dictionary) -> void:
	var st := _st(world)
	var d: Dictionary = cfg.decide
	open.votes += 1
	var voices := int(st.voices)
	var y: Array = yn[0]
	var no: Array = yn[1]
	# O6 (A): carry among the voices with a view, plus a quorum of the whole colony.
	var took_side: int = y.size() + no.size()
	if took_side > 0 and _cmp_ge(y.size(), took_side, float(d.carry_share)) \
			and _cmp_ge(y.size(), voices, float(d.carry_quorum)):
		open.carry_run += 1
	else:
		open.carry_run = 0
	if _cmp_ge(no.size(), voices, float(d.reject_share)):
		open.reject_run += 1
	else:
		open.reject_run = 0
	var ysp = _speaker(y, true)
	var nsp = _speaker(no, false)
	var extra_div: Dictionary = {}
	if not open.divided and _cmp_ge(y.size(), voices, float(d.divided_share)) and _cmp_ge(no.size(), voices, float(d.divided_share)):
		open.divided = true
		open.no_speaker_id = nsp
		var ra := _reason(world, ysp, true)
		var rb := _reason(world, nsp, false)
		_offer(PRIO.divided, "council_divided", "divided", _fmt(str(tcfg.text.divided), {"a": _name(world, ysp), "b": _name(world, nsp), "ra": ra, "rb": rb}),
				{"being_id": ysp, "other_id": nsp, "building_id": best.building_id, "topic": "dome"})
	var pr: Dictionary = st.proposals.back()
	if open.carry_run >= int(d.carry_sessions):
		var topic: String = open.topic
		pledged[topic] = n
		st.pledge_sol = n
		var why := _pledge_why(world, y)
		var key := "pledge_divided" if open.divided else "pledge"
		var wtxt := str(tcfg.text.pledge_why_personal) if why == "personal" else _fmt(str(tcfg.text.reason.yes[why]), {})
		var text := _fmt(str(tcfg.text[key]), {"a": _name(world, open.proposer_id), "place": _place(world, best.building_id), "why": wtxt})
		_offer(PRIO.outcome, "council_pledge", key, text, {"being_id": open.proposer_id, "other_id": null, "building_id": best.building_id, "topic": topic})
		st.chapters.append({"kind": "pledge", "topic": topic, "text": text, "t": world.t, "sol": n, "clock_sol": world.clock.sol_index(world.t)})
		pr.outcome = "pledged"
		pr.outcome_sol = n
		pr.reason = why
		var doubter := -1
		if open.no_speaker_id != null and is_voice(world, open.no_speaker_id):
			doubter = open.no_speaker_id
		else:
			var bs := 9.0
			for id in no:
				var s := stance_of(id)
				if doubter < 0 or s < bs:
					doubter = id
					bs = s
		aftermath = {"due_sol": n + int(cfg.lines.aftermath_sols), "doubter_id": doubter} if doubter >= 0 else null
		open = null
	elif open.reject_run >= int(d.reject_sessions):
		var hard := hard_share() >= float(cfg.lines.hard_share_min)
		set_aside[open.topic] = {"sol": n, "hard": hard}
		pr.outcome = "set_aside"
		pr.outcome_sol = n
		pr.hard = hard
		if hard:
			_offer(PRIO.outcome, "council_set_aside_hard", "set_aside_hard", _fmt(str(tcfg.text.set_aside_hard), {"clause": cfg.text.clause[hard_clause()]}),
					{"being_id": null, "other_id": null, "building_id": best.building_id, "topic": open.topic})
		else:
			_offer(PRIO.outcome, "council_set_aside", "set_aside", _fmt(str(tcfg.text.set_aside), {"b": _name(world, nsp)}),
					{"being_id": nsp, "other_id": null, "building_id": best.building_id, "topic": open.topic})
		open = null
	elif open.votes >= int(d.max_open_votes):
		set_aside[open.topic] = {"sol": n, "hard": false}
		pr.outcome = "set_aside"
		pr.outcome_sol = n
		pr.hard = false
		_offer(PRIO.outcome, "council_set_aside_long", "set_aside_long", str(tcfg.text.set_aside_long),
				{"being_id": null, "other_id": null, "building_id": best.building_id, "topic": open.topic})
		open = null


func _speaker(camp: Array, yes: bool) -> Variant:
	if camp.is_empty():
		return null
	var cs := {}
	for id in camp:
		cs[id] = true
	var bid := -1
	var bc := -1
	var bs := 0.0
	for id in camp:
		var c := 0
		for f in _friends.get(id, []):
			if cs.has(f >> 1):
				c += 1
		var s := stance_of(id)
		var better := false
		if bid < 0 or c > bc:
			better = true
		elif c == bc:
			if yes and s > bs:
				better = true
			elif not yes and s < bs:
				better = true
		if better:
			bid = id
			bc = c
			bs = s
	return bid


func _adj(world: SimWorld, id: int, dims: Array) -> String:
	var pd: Dictionary = SimData.persona()
	var tr: Dictionary = {}
	for b in world.beings:
		if b.id == id:
			tr = b.persona.traits
	var order: Array = pd.dims
	var best_d := ""
	var bv := -1.0
	for dm in order:
		if dm in dims and float(tr[dm]) > bv:
			bv = float(tr[dm])
			best_d = dm
	return str(pd.adjectives[best_d])


func _reason(world: SimWorld, id: int, yes: bool) -> String:
	var sc: Dictionary = cfg.support
	var l := lean_of(id)
	var s := stance_of(id)
	var tm: Dictionary = _terms[id]
	var rs: Dictionary = cfg.dome.text.reason[("yes" if yes else "no")]
	var key := ""
	if (l >= float(sc.no_below) and l <= float(sc.yes_above)) or (l * s < 0.0) or (yes and l < 0.0) or (not yes and l > 0.0):
		key = "friends"
	else:
		var cands: Array = []
		if yes:
			cands = [["size", tm.size], ["means", tm.means], ["child", tm.child], ["personal", tm.personal]]
		else:
			cands = [["hard", tm.hard], ["means", -tm.means], ["personal", -tm.personal]]
		var bv := 0.0
		key = "personal"
		for c in cands:
			if float(c[1]) > bv:
				bv = float(c[1])
				key = c[0]
	return _fmt(str(rs[key]), {"adj": _adj(world, id, ["drive", "curiosity", "restless"] if yes else ["steady", "care"]),
			"clause": cfg.text.clause[hard_clause()]})


func _pledge_why(world: SimWorld, yes_ids: Array) -> String:
	var keys := ["size", "means", "child", "personal"]
	var sums := {}
	for k in keys:
		sums[k] = 0.0
	for id in yes_ids:
		for k in keys:
			sums[k] += float(_terms[id][k])
	var bk := "personal"
	var bv := 0.0
	for k in keys:
		var m: float = sums[k] / float(maxi(1, yes_ids.size()))
		if m > bv:
			bv = m
			bk = k
	return bk
