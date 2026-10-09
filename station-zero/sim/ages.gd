class_name Ages
extends RefCounted
## The age system (spec docs/specs/ages.md, Task 3): Landing and Settlement, announced in the log.
## Once per sol boundary the colony is sampled (ok or not ok); a long ok stretch with a first generation of
## families alive is Settlement, a long not-ok stretch sends the colony back. Announce only: nothing in the sim
## reads the age, and on_sol writes nothing but this object, `stats` (age keys) and the log. No RNG, no wall clock.
## Every tunable is in data/ages.json (and beings.json / colony.json for the shared numbers).

## Comparison slack of clauses 5 to 7 (spec 4.2); like SimWorld.STEP_EPS, a constant, not a tunable.
const CMP_EPS := 1e-9
## Cause groups in their fixed tie order (spec 4.3).
const GROUPS: Array[String] = ["ice", "food", "oxygen", "power", "death", "unrest"]
const LANDING := "landing"
const SETTLEMENT := "settlement"

var age := LANDING
## The last `sample.window_sols` samples, newest last; each {ok: bool, failed: Array of group ids}.
var window: Array = []
var last_change_sol := 0
## stats.shorts and len(stats.deaths_list) at the previous sol boundary.
var snap_shorts := 0
var snap_deaths := 0
## Latest sample (clause booleans). For tests and the probe only; never in stats, never read by the view.
var last_sample: Dictionary = {}


# ---------------------------------------------------------------- pure reads

## One sample of the colony at the end of a boundary step: a bool per clause (spec 4.2). Pure read.
static func sample(world: SimWorld) -> Dictionary:
	var cfg: Dictionary = SimData.ages().sample
	var col: Colony = world.colony
	var pop := col.pop()
	var s := {}
	s["oxygen"] = col.oxygen >= float(cfg.o2_min_fraction) * col.o2_cap()
	s["food"] = col.food >= float(cfg.food_min_fraction) * col.food_cap()
	s["o2_net"] = col.o2_net() > float(cfg.net_above)
	s["food_net"] = col.food_net() > float(cfg.net_above)
	s["power_budget"] = world.buildings.demand() <= world.buildings.supply()
	var any_offline := false
	for b in world.buildings.list:
		if b.offline:
			any_offline = true
			break
	s["none_offline"] = not any_offline
	s["no_short"] = int(world.stats.shorts) == world.ages.snap_shorts
	var shortage_death := false
	for i in range(world.ages.snap_deaths, world.stats.deaths_list.size()):
		if str(world.stats.deaths_list[i].cause) in cfg.shortage_causes:
			shortage_death = true
			break
	s["no_shortage_death"] = not shortage_death
	var use_per_sol := pop * float(SimData.colony().consumption.ice_per_being) * world.clock.sol_h
	s["ice"] = col.ice >= float(cfg.ice_min_sols) * use_per_sol - CMP_EPS
	var en: Dictionary = SimData.beings().energy
	var distressed := 0
	var rested := 0
	for b in world.beings:
		if b.energy < float(en.exhausted_turn_back) or (b.is_outside() and b.returning):
			distressed += 1
		if b.energy >= float(en.sleep_below):
			rested += 1
	s["calm"] = distressed * 1.0 <= float(cfg.distress_share_max) * pop + CMP_EPS
	s["rested"] = rested * 1.0 >= float(cfg.rested_share_min) * pop - CMP_EPS
	return s


## The cause groups a sample failed in, in the fixed group order (spec 4.3).
static func failed_groups(s: Dictionary) -> Array:
	var f: Array = []
	if not s.ice:
		f.append("ice")
	if not (s.food and s.food_net):
		f.append("food")
	if not (s.oxygen and s.o2_net):
		f.append("oxygen")
	if not (s.power_budget and s.none_offline and s.no_short):
		f.append("power")
	if not s.no_shortage_death:
		f.append("death")
	if not (s.calm and s.rested):
		f.append("unrest")
	return f


## The group that failed in the most samples; ties go in GROUPS order. Empty window: "".
static func dominant_cause(win: Array) -> String:
	var best := ""
	var best_n := 0
	for g in GROUPS:
		var n := 0
		for e in win:
			if g in e.failed:
				n += 1
		if n > best_n:
			best_n = n
			best = g
	return best


## The age id that should be in force (spec 5 and 6). Pure.
static func decide(win: Array, age_now: String, sols_since_change: int, family_mars_born: int, homes: int) -> String:
	var cfg: Dictionary = SimData.ages()
	var size := int(cfg.sample.window_sols)
	if win.size() < size or sols_since_change < int(cfg.min_dwell_sols):
		return age_now
	var ok := 0
	for e in win:
		if e.ok:
			ok += 1
	if age_now == LANDING:
		var required := int(ceil(float(cfg.entry.ok_share) * size - SimWorld.STEP_EPS))
		if ok >= required and _last_all_ok(win, int(cfg.entry.recent_ok_sols)) \
				and family_mars_born >= int(cfg.entry.mars_born_min) \
				and homes >= int(cfg.entry.mars_born_homes_min):
			return SETTLEMENT
	else:
		var ok_max := int(ceil(float(cfg.exit.ok_share_below) * size - SimWorld.STEP_EPS)) - 1
		if ok <= ok_max and not _last_all_ok(win, int(cfg.exit.recent_sols)):
			return LANDING
	return age_now


static func _last_all_ok(win: Array, count: int) -> bool:
	for i in range(maxi(0, win.size() - count), win.size()):
		if not win[i].ok:
			return false
	return true


## [count, distinct birth habitats] of living Mars-born beings whose recorded parent is alive (spec 5.4).
static func family_mars_born(world: SimWorld) -> Array[int]:
	var alive := {}
	for b in world.beings:
		alive[b.id] = true
	var count := 0
	var homes := {}
	for b in world.beings:
		if not b.earth_born and b.parent_id != 0 and alive.has(b.parent_id):
			count += 1
			homes[b.birth_building_id] = true
	return [count, homes.size()]


## The log and history text of an age change: base, cause sentence (fall back only), season sentence.
static func change_text(how: String, cause: String, world: SimWorld) -> String:
	var cfg: Dictionary = SimData.ages()
	var parts: Array[String] = []
	match how:
		"settled":
			parts.append(cfg.settlement.log_enter)
		"settled_again":
			parts.append(cfg.settlement.log_enter_again)
		_:
			parts.append(cfg.landing.log_fall_back)
			parts.append(cfg.cause_lines[cause])
	parts.append(cfg.season_phrases[world.clock.seasons.find(world.clock.season(world.t))])
	return " ".join(PackedStringArray(parts))


# ---------------------------------------------------------------- world hooks

## World creation: the Landing line (founder worlds log it, blank worlds only record it) and the first
## age_history entry (spec 8.2).
func begin(world: SimWorld, announce: bool) -> void:
	var text: String = SimData.ages().landing.log_start
	if announce:
		world._log("age_began", text, {"age": LANDING, "how": "landing"})
	_record(world, "landing", null, text)


## Phase 11, once per sol boundary (spec 4.1). Writes only this object, stats age keys and the log.
func on_sol(world: SimWorld) -> void:
	var n := world.sol()
	world.stats.sols_in_age[age] += 1
	var pop := world.colony.pop()
	var cfg: Dictionary = SimData.ages()
	if n >= int(cfg.sample.from_sol) and pop > 0:
		last_sample = sample(world)
		var failed := failed_groups(last_sample)
		window.append({"ok": failed.is_empty(), "failed": failed})
		while window.size() > int(cfg.sample.window_sols):
			window.pop_front()
	snap_shorts = int(world.stats.shorts)
	snap_deaths = world.stats.deaths_list.size()
	if pop == 0:
		return  # frozen: no sample, no change, no line (spec 8.3)
	var fam := family_mars_born(world)
	var next := decide(window, age, n - last_change_sol, fam[0], fam[1])
	if next == age:
		return
	var how := "fell_back"
	var cause := ""
	if next == SETTLEMENT:
		how = "settled" if world.stats.first_settlement_sol == null else "settled_again"
		if world.stats.first_settlement_sol == null:
			world.stats.first_settlement_sol = n
	else:
		cause = dominant_cause(window)
	var text := change_text(how, cause, world)
	age = next
	last_change_sol = n
	world.stats.age_changes += 1
	_record(world, how, cause if cause != "" else null, text)
	var extra := {"age": age, "how": how}
	if cause != "":
		extra["cause"] = cause
	world._log("age_began", text, extra)


func _record(world: SimWorld, how: String, cause: Variant, text: String) -> void:
	world.stats.age = age
	world.stats.age_history.append({"age": age, "how": how, "cause": cause, "text": text,
			"pop": world.colony.pop(), "family_mars_born": family_mars_born(world)[0],
			"t": world.t, "sol": world.sol(), "clock_sol": world.clock.sol_index(world.t)})


func enter_age(world: SimWorld, age_id: String, how: String, text: String) -> void:
	age = age_id
	world.stats.age_changes += 1
	_record(world, how, null, text)
	world._log("age_began", text, {"age": age, "how": how})
