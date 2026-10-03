extends RefCounted
## Task 1, step 3: colony stocks, caps, clamping, ice drain, warnings, death timers and causes,
## seeded determinism. Spec: docs/specs/life-support-power.md sections 3, 4, 5, 9.
##
## API under test (implemented in sim/world.gd, sim/colony.gd, sim/buildings.gd, sim/being.gd):
##  SimWorld._init(seed_in = null, options = {})   options.blank = true builds the blank world:
##       no founders, no layout, no sites, no beings, stocks from data/colony.json "start".
##  Blank-world helpers on SimWorld (direct field writes are also fine for stocks):
##    add_building(kind: String, tx := 0, ty := 0, built := 1.0) -> int   id, from 1 in creation order.
##    set_offline(building_id: int, offline: bool) -> void   sets offline and offline_since (t or null).
##    add_being(building_id: int, role := "builder") -> Being   neutral persona (every trait 0.5), energy
##       from the world rng, state idle, placed in that building (no x,y). Appended to world.beings.
##  SimWorld fields: step() (one fixed step), t, rng, colony, buildings (has last_short_t),
##       beings (Array of Being, ascending id, living only), log (Array of Dictionary, newest last,
##       each has "kind"; deaths are kind "died" with "cause"), stats.
##  Colony (world.colony): fields oxygen, food, ice, regolith, death_timer_h, extinct;
##       methods with no arguments: pop() (living beings), green_rooms() (online ones),
##       o2_net(), food_net(), o2_cap(), food_cap(), ice_target(), regolith_target(),
##       shortage_victim_candidates() -> Array of Being: beings inside (state not transit, eva, work,
##       mining; sleepers count); all living beings if none is inside. Death picks rng.pick() of it.
##  Being: fields id, state (String), energy.
##  stats.deaths: Dictionary with int keys air, thirst, hunger (and suffocated_outside, other);
##       stats.deaths_list: Array of {t, sol, being_id, name, cause}; cause is "air", "thirst" or "hunger".
##  Log kinds for warnings: air_low (oxygen 0, repeat 1 sol), food_empty (food 0, 1 sol),
##       water_dry (ice 0, 2 sols). Step counts below count world.step() calls after the stock was set.
##  Placement used by these tests: reactor id 1, then green rooms, all beings live in the reactor
##       (no births, no sleep bunks); one reactor (supply 14) carries up to 3 green rooms (draw 12).

const DT := 0.05
const SOL_STEPS := 493  # 493 steps = 24.65 h, a sol (24.6597 h) is 493.19 steps


## Blank world with a reactor, `green_rooms` online green rooms and `beings` beings.
func _world(_t, seed_in: int, green_rooms: int, beings: int) -> SimWorld:
	var w := SimWorld.new(seed_in, {"blank": true})
	var reactor: int = w.add_building("reactor", 0, 0, 1.0)
	for i in green_rooms:
		w.add_building("green_room", 20 * (i + 1), 0, 1.0)
	for i in beings:
		w.add_being(reactor)
	return w


func _steps(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()


func _count_kind(w, kind: String) -> int:
	var n := 0
	for e in w.log:
		if e.kind == kind:
			n += 1
	return n


## Step numbers (1-based) on which the count of log lines of `kind` grew.
func _warning_steps(w, kind: String, steps: int) -> Array:
	var out: Array = []
	var seen := _count_kind(w, kind)
	for s in range(1, steps + 1):
		w.step()
		var c := _count_kind(w, kind)
		if c > seen:
			out.append(s)
		seen = c
	return out


## Step numbers on which the population dropped, with one stock held at 0.
func _death_steps(t, shortage: String, seeds: int, steps: int) -> Array:
	var out: Array = []
	for seed_in in range(1, seeds + 1):
		var w = _world(t, seed_in, 0, 7)
		w.colony.set(shortage, 0.0)
		var pop: int = w.colony.pop()
		for s in range(1, steps + 1):
			w.step()
			var now: int = w.colony.pop()
			if now < pop:
				out.append(s)
			pop = now
	return out


func _signature(w) -> String:
	var bs: Array = []
	for b in w.beings:
		bs.append([b.id, b.state, snappedf(b.energy, 1e-9)])
	var c = w.colony
	return str([c.oxygen, c.food, c.ice, c.regolith, c.pop()]) + str(bs) + JSON.stringify(w.log)


# ---------------------------------------------------------------- net rates

func test_net_rates_one_green_room_seven_beings(t) -> void:
	var w = _world(t, 42, 1, 7)
	t.eq(w.colony.pop(), 7, "pop")
	t.eq(w.colony.green_rooms(), 1, "green rooms")
	t.near(w.colony.o2_net(), 1.05, 1e-9, "o2_net = 1.4 - 7 x 0.05")
	t.near(w.colony.food_net(), 0.755, 1e-9, "food_net = 1.0 - 7 x 0.035")
	t.eq(w.colony.oxygen, 140.0, "start oxygen")
	t.eq(w.colony.food, 110.0, "start food")
	w.step()
	t.near(w.colony.oxygen, 140.0 + 1.05 * DT, 1e-9, "oxygen after 1 step")
	t.near(w.colony.food, 110.0 + 0.755 * DT, 1e-9, "food after 1 step")
	_steps(w, SOL_STEPS - 1)
	t.near(w.colony.oxygen, 140.0 + 1.05 * SOL_STEPS * DT, 1e-6, "oxygen after 493 steps (+25.8825)")
	t.near(w.colony.food, 110.0 + 0.755 * SOL_STEPS * DT, 1e-6, "food after 493 steps (+18.61075)")
	t.eq(w.colony.pop(), 7, "nobody died")


func test_net_rates_without_online_green_room(t) -> void:
	var w = _world(t, 42, 0, 7)
	t.near(w.colony.o2_net(), -0.35, 1e-9, "no green room o2_net")
	t.near(w.colony.food_net(), -0.245, 1e-9, "no green room food_net")
	w.step()
	t.near(w.colony.oxygen, 140.0 - 0.35 * DT, 1e-9, "oxygen falls")
	t.near(w.colony.food, 110.0 - 0.245 * DT, 1e-9, "food falls")
	# An offline green room counts as none.
	var w2 = _world(t, 42, 1, 7)
	var gr: int = 2
	w2.set_offline(gr, true)
	w2.buildings.last_short_t = w2.t  # hold: keeps it offline for 60 steps
	t.eq(w2.colony.green_rooms(), 0, "offline green room not counted")
	t.near(w2.colony.o2_net(), -0.35, 1e-9, "offline o2_net")
	t.near(w2.colony.food_net(), -0.245, 1e-9, "offline food_net")


# ---------------------------------------------------------------- caps

func test_caps(t) -> void:
	var expect := {0: [400.0, 300.0], 1: [550.0, 420.0], 3: [850.0, 660.0]}
	for n in expect.keys():
		var w = _world(t, 42, n, 0)
		t.eq(w.colony.o2_cap(), expect[n][0], "o2 cap with %d green rooms" % n)
		t.eq(w.colony.food_cap(), expect[n][1], "food cap with %d green rooms" % n)


func test_stock_clamps_to_cap_and_drops_when_green_room_goes_offline(t) -> void:
	var w = _world(t, 42, 1, 7)
	w.colony.oxygen = 549.99
	w.colony.food = 419.99
	_steps(w, 5)
	t.eq(w.colony.oxygen, 550.0, "oxygen stops at cap 550")
	t.eq(w.colony.food, 420.0, "food stops at cap 420")
	# Green room (id 2) goes dark: caps fall to 400 / 300 and stocks are clamped on the next step.
	w.colony.oxygen = 540.0
	w.colony.food = 410.0
	w.set_offline(2, true)
	w.buildings.last_short_t = w.t
	w.step()
	t.eq(w.colony.o2_cap(), 400.0, "cap after offline")
	t.eq(w.colony.food_cap(), 300.0, "food cap after offline")
	t.eq(w.colony.oxygen, 400.0, "oxygen clamped down to 400")
	t.eq(w.colony.food, 300.0, "food clamped down to 300")


# ---------------------------------------------------------------- clamping at 0

func test_stocks_clamp_at_zero(t) -> void:
	var w = _world(t, 42, 0, 7)
	w.colony.oxygen = 0.01
	w.colony.food = 0.01
	w.colony.ice = 0.01
	_steps(w, 3)
	t.eq(w.colony.oxygen, 0.0, "oxygen 0.01 - 0.0175 clamps to 0")
	t.eq(w.colony.food, 0.0, "food 0.01 - 0.01225 clamps to 0")
	t.eq(w.colony.ice, 0.0, "ice 0.01 - 3 x 0.0035 clamps to 0")
	_steps(w, 10)
	t.eq(w.colony.oxygen, 0.0, "oxygen stays 0")
	t.eq(w.colony.food, 0.0, "food stays 0")
	t.eq(w.colony.ice, 0.0, "ice stays 0")


# ---------------------------------------------------------------- ice drain and targets

func test_ice_drain(t) -> void:
	var w = _world(t, 42, 1, 7)
	_steps(w, 20)
	t.near(w.colony.ice, 60.0 - 0.07, 1e-9, "7 beings drain 0.07 ice per hour")
	_steps(w, SOL_STEPS - 20)
	t.near(w.colony.ice, 60.0 - 0.07 * SOL_STEPS * DT, 1e-6, "493 steps drain 1.7255 (1.726 per full sol)")
	var w0 = _world(t, 42, 1, 0)
	_steps(w0, 200)
	t.eq(w0.colony.ice, 60.0, "pop 0: no drain")


func test_ice_and_regolith_targets(t) -> void:
	var expect := {0: 120.0, 7: 120.0, 15: 120.0, 20: 160.0}
	for pop in expect.keys():
		var w = _world(t, 42, 0, pop)
		t.eq(w.colony.ice_target(), expect[pop], "ice target with pop %d" % pop)
	var w5 = _world(t, 42, 1, 0)  # reactor + green room
	w5.add_building("habitat", 40, 0, 1.0)
	w5.add_building("workshop", 60, 0, 1.0)
	w5.add_building("archive", 80, 0, 1.0)
	t.eq(w5.colony.regolith_target(), 220.0, "160 + 12 x 5 buildings")


# ---------------------------------------------------------------- warnings

func test_air_warning_once_per_sol(t) -> void:
	var w = _world(t, 42, 0, 0)  # pop 0 so nobody dies during the run
	w.colony.oxygen = 0.0
	var steps := _warning_steps(w, "air_low", 1233)
	t.eq(steps, [1, 495, 989], "air_low on steps 1, 495, 989 (494 steps apart) over 2.5 sols")
	t.eq(_count_kind(w, "food_empty"), 0, "no food line while food > 0")
	t.eq(_count_kind(w, "water_dry"), 0, "no water line while ice > 0")


func test_food_warning_once_per_sol(t) -> void:
	var w = _world(t, 42, 0, 0)
	w.colony.food = 0.0
	t.eq(_warning_steps(w, "food_empty", 1233), [1, 495, 989], "food_empty on steps 1, 495, 989")
	t.eq(_count_kind(w, "air_low"), 0, "no air line while oxygen > 0")


func test_thirst_warning_once_per_two_sols(t) -> void:
	var w = _world(t, 42, 0, 0)
	w.colony.ice = 0.0
	t.eq(_warning_steps(w, "water_dry", 2000), [1, 988, 1975], "water_dry every 987 steps (2 sols)")


func test_no_warning_when_stocks_are_positive(t) -> void:
	var w = _world(t, 42, 1, 7)
	_steps(w, 600)
	t.eq(_count_kind(w, "air_low") + _count_kind(w, "food_empty") + _count_kind(w, "water_dry"), 0, "silent")


# ---------------------------------------------------------------- death timers

func test_death_timer_fires_on_step_40_air(t) -> void:
	var w = _world(t, 42, 0, 7)
	w.colony.oxygen = 0.0
	_steps(w, 39)
	t.near(w.colony.death_timer_h, 39 * DT, 1e-6, "timer after 39 steps")
	w.step()
	t.eq(w.colony.death_timer_h, 0.0, "check fired on step 40 and reset the timer")


func test_death_timer_fires_on_step_100_thirst(t) -> void:
	var w = _world(t, 42, 0, 7)
	w.colony.ice = 0.0
	_steps(w, 40)
	t.near(w.colony.death_timer_h, 2.0, 1e-6, "ice only: the 2 h interval does not apply")
	_steps(w, 59)
	t.near(w.colony.death_timer_h, 99 * DT, 1e-6, "timer after 99 steps")
	w.step()
	t.eq(w.colony.death_timer_h, 0.0, "check fired on step 100")


func test_death_timer_fires_on_step_120_hunger(t) -> void:
	var w = _world(t, 42, 0, 7)
	w.colony.food = 0.0
	_steps(w, 100)
	t.near(w.colony.death_timer_h, 5.0, 1e-6, "food only: no check at step 100")
	_steps(w, 19)
	t.near(w.colony.death_timer_h, 119 * DT, 1e-6, "timer after 119 steps")
	w.step()
	t.eq(w.colony.death_timer_h, 0.0, "check fired on step 120")


func test_air_interval_wins_when_food_also_zero(t) -> void:
	var w = _world(t, 42, 0, 7)
	w.colony.oxygen = 0.0
	w.colony.food = 0.0
	_steps(w, 40)
	t.eq(w.colony.death_timer_h, 0.0, "air interval (40 steps) used, not hunger (120)")


func test_timer_resets_when_shortage_ends(t) -> void:
	var w = _world(t, 42, 0, 7)
	w.colony.oxygen = 0.0
	_steps(w, 30)
	t.near(w.colony.death_timer_h, 1.5, 1e-6, "timer running")
	w.colony.oxygen = 50.0
	w.step()
	t.eq(w.colony.death_timer_h, 0.0, "shortage ended: timer back to 0")
	_steps(w, 100)
	t.eq(w.colony.death_timer_h, 0.0, "stays 0 without shortage")
	t.eq(w.colony.pop(), 7, "no deaths without shortage")


func test_deaths_only_on_check_steps(t) -> void:
	var air := _death_steps(t, "oxygen", 20, 400)
	t.check(air.size() > 0, "some deaths happened (p 0.4 per check, 10 checks per run)")
	for s in air:
		t.eq(s % 40, 0, "air death on step %d is a multiple of 40" % s)
	var thirst := _death_steps(t, "ice", 30, 600)
	t.check(thirst.size() > 0, "thirst deaths happened")
	for s in thirst:
		t.eq(s % 100, 0, "thirst death on step %d is a multiple of 100" % s)
	var hunger := _death_steps(t, "food", 30, 720)
	t.check(hunger.size() > 0, "hunger deaths happened")
	for s in hunger:
		t.eq(s % 120, 0, "hunger death on step %d is a multiple of 120" % s)


func test_death_chance_is_point_four_per_check(t) -> void:
	# 400 seeded runs of 400 steps (20 h): 10 checks each, expected deaths 4 per run.
	var deaths := 0
	var runs := 400
	for seed_in in range(1, runs + 1):
		var w = _world(t, seed_in, 0, 7)
		w.colony.oxygen = 0.0
		_steps(w, 400)
		deaths += 7 - int(w.colony.pop())
	t.between(float(deaths) / runs, 3.5, 4.5, "mean deaths per 20 h of no air")


# ---------------------------------------------------------------- death causes

func test_death_cause_air(t) -> void:
	var total := 0
	for seed_in in range(1, 41):
		var w = _world(t, seed_in, 0, 7)
		w.colony.oxygen = 0.0
		_steps(w, 40)
		for d in w.stats.deaths_list:
			t.eq(d.cause, "air", "air shortage kills by air")
			t.eq(d.has("being_id") and d.has("name") and d.has("t") and d.has("sol"), true, "death record fields")
		total += w.stats.deaths.air
		t.eq(w.stats.deaths.thirst + w.stats.deaths.hunger, 0, "no other cause")
	t.check(total > 0, "at least one air death over 40 seeds")


func test_cause_priority_air_over_thirst(t) -> void:
	var total := 0
	for seed_in in range(1, 41):
		var w = _world(t, seed_in, 0, 7)
		w.colony.oxygen = 0.0
		w.colony.ice = 0.0
		_steps(w, 40)
		total += w.stats.deaths.air
		t.eq(w.stats.deaths.thirst, 0, "air beats thirst")
	t.check(total > 0, "deaths happened at the air interval (step 40)")


func test_cause_priority_thirst_over_hunger(t) -> void:
	var total := 0
	for seed_in in range(1, 41):
		var w = _world(t, seed_in, 0, 7)
		w.colony.ice = 0.0
		w.colony.food = 0.0
		_steps(w, 100)
		total += w.stats.deaths.thirst
		t.eq(w.stats.deaths.hunger, 0, "thirst beats hunger")
		t.eq(w.stats.deaths.air, 0, "no air death with oxygen > 0")
	t.check(total > 0, "deaths happened at the thirst interval (step 100)")


func test_cause_priority_all_three_is_air(t) -> void:
	var w = _world(t, 42, 0, 7)
	w.colony.oxygen = 0.0
	w.colony.ice = 0.0
	w.colony.food = 0.0
	_steps(w, 400)
	t.check(w.stats.deaths.air > 0, "air deaths")
	t.eq(w.stats.deaths.thirst + w.stats.deaths.hunger, 0, "only the top priority cause")


func test_death_is_logged_with_cause(t) -> void:
	var w = _world(t, 42, 0, 7)
	w.colony.oxygen = 0.0
	_steps(w, 400)
	var died := _count_kind(w, "died")
	t.eq(died, 7 - int(w.colony.pop()), "one died line per death")
	t.eq(w.stats.deaths_list.size(), died, "deaths_list matches")
	for e in w.log:
		if e.kind == "died":
			t.eq(e.cause, "air", "log cause")


func test_victims_are_inside_beings(t) -> void:
	var w = _world(t, 42, 0, 6)
	var states := ["transit", "eva", "work", "mining", "sleep", "idle"]
	for i in 6:
		w.beings[i].state = states[i]
	var ids: Array = []
	for b in w.colony.shortage_victim_candidates():
		ids.append(b.id)
	ids.sort()
	t.eq(ids, [w.beings[4].id, w.beings[5].id], "only sleep and idle beings are candidates")
	# Everyone outside or in a tunnel: the pick is among all living beings.
	for i in 6:
		w.beings[i].state = ["transit", "eva", "work", "mining", "eva", "transit"][i]
	t.eq(w.colony.shortage_victim_candidates().size(), 6, "no one inside: all beings")


# ---------------------------------------------------------------- determinism

func _shortage_run(t, seed_in: int) -> SimWorld:
	var w := _world(t, seed_in, 0, 7)
	w.colony.oxygen = 20.0  # runs out after about 57 h, then deaths on the 2 h checks
	_steps(w, 5000)
	return w


func test_seeded_determinism(t) -> void:
	var a := _shortage_run(t, 42)
	var b := _shortage_run(t, 42)
	var c := _shortage_run(t, 43)
	t.check(a.stats.deaths_list.size() > 0, "the scenario produces deaths (so the rng matters)")
	t.eq(_signature(a), _signature(b), "seed 42 twice: identical stocks, beings and log")
	t.check(_signature(a) != _signature(c), "seed 43 differs")
	# A full founder world is also reproducible in its stocks and log.
	var f1 := SimWorld.new(42)
	var f2 := SimWorld.new(42)
	_steps(f1, 1000)
	_steps(f2, 1000)
	t.eq(f1.colony.oxygen, f2.colony.oxygen, "full world oxygen")
	t.eq(f1.colony.food, f2.colony.food, "full world food")
	t.eq(f1.colony.ice, f2.colony.ice, "full world ice")
	t.eq(JSON.stringify(f1.log), JSON.stringify(f2.log), "full world log")


# ---------------------------------------------------------------- extinction

func test_extinction(t) -> void:
	var w := _world(t, 42, 1, 0)
	w.colony.oxygen = 0.0  # even with a shortage nobody dies and nothing is born
	w.colony.ice = 0.0
	t.eq(w.colony.extinct, false, "not flagged before the first step")
	_steps(w, 1000)
	t.eq(w.colony.pop(), 0, "no beings")
	t.eq(w.colony.extinct, true, "extinct")
	t.eq(_count_kind(w, "colony_silent"), 1, "one log line")
	t.eq(w.stats.deaths_list.size(), 0, "no deaths")
	t.eq(w.stats.births, 0, "no births")
	t.eq(w.colony.death_timer_h, 0.0, "timer idle")
	t.near(w.t, w.clock.start_hour + 1000 * DT, 1e-6, "the sim keeps stepping")
	# The last being dying flags extinction once.
	var w2 := _world(t, 42, 0, 1)
	w2.colony.oxygen = 0.0
	_steps(w2, 4000)
	t.eq(w2.colony.pop(), 0, "last being died")
	t.eq(w2.colony.extinct, true, "extinct after the last death")
	t.eq(_count_kind(w2, "colony_silent"), 1, "one silent line")
