# Spec: life support, power, beings, construction, suits (Task 1)

Source of truth: HANDOFF.md sections 2, 5, 8. Tiebreaker: `station-zero-handoff/prototype/station-zero-wip.html` ("proto L<n>"). Plan: `docs/tasks/task-1-plan.md` (A1..A13 and the owner decisions are resolved here).
Locked decisions respected: influence-only god (no power in this slice except the `power_multiplier_until` test hook), ages not meters (no population bar anywhere), per-being energy, power as a budget (a short is never a death).
Every number below lives in `data/colony.json`, `data/buildings.json`, `data/beings.json`, `data/suits.json`, `data/resources.json` (key paths in section 12). Existing `data/sim.json` supplies the 0.05 h step and seed 42; `data/calendar.json` supplies the sol length (24.6597 h) and the Mars clock.
This spec describes the sim only. No GDScript, no sprites, no UI.

## 1. Purpose
A colony that runs headless for hundreds of sols and stays alive for reasons you can read in a table. Life support only means something with beings who breathe, buildings that make air and builders who extend the colony, so the slice is: stocks, buildings with a power budget, beings with energy and a small state machine, construction, resources and mining, suits and EVA, births, death with a cause, and a log. It must be balanced by runs (section 9), not by feel.

## 2. Code map (new files; `sim/` only, no Node, no draw API)
| File | Owns |
| --- | --- |
| sim/colony.gd (`Colony`) | stocks, nets, caps, targets, warnings, death timer, birth rules and cooldowns |
| sim/buildings.gd (`Buildings`) | building list, tunnel graph, layout (`find_spot`, doors, BFS), power budget, shorts, re-online, construction site and progress, `choose_kind` |
| sim/being.gd (`Being`) | one being: needs, state machine, decide, EVA, mining, work, footprints source |
| sim/resources.gd (`Resources`) | ice fields, regolith pit, spawn, scouting, `trip_time`, `launch_for`, `choose_site`, footprints list |
| sim/world.gd (`SimWorld`) | owns all of the above, `step()` order (section 5), `stats`, `log`, founders, hooks |
Data access follows `SimData` (Task 0). No tunable number in `sim/*.gd`.

### Test seams the engineer must provide (design requirement)
- `SimWorld.new(seed, options)` where `options.blank = true` creates an empty world (no founders, no layout, no sites, stocks from `colony.start`) so tests build exactly the state they need by direct field writes and calls such as "add building of kind at tile, built 1", "add being of persona and role in building", "add ice field at x,y".
- Every field in section 4 is readable and writable by tests. `step()` advances exactly one fixed step.
- `SimWorld.stats` (counters, section 10) and `SimWorld.log` (list of dictionaries) are plain data.

## 3. Conventions
- Time unit is the Earth hour (h). One step is `fixed_step_hours` = 0.05 h (`data/sim.json`). A sol is `sol_hours` = 24.6597 h. Name suffixes: `_h` hours, `_sols` sols (multiply by `sol_hours`), `_px` world pixels, `_px_h` pixels per hour. Tile = `tile_px` = 8 px.
- `t` is the world clock (hours since epoch, as in Task 0). Mars clock hour = `Clock.mars_hour(t)` in [0, 24). **Night** = clock hour >= 21.5 or < 5.5 (`beings.night`).
- Float slack: any "`x > h`" or "`x >= h`" threshold on an accumulated time uses 1e-9 so results do not depend on rounding. A 4 h timer fires on the 80th step, a 5 h timer on the 100th, a 3 h hold is satisfied on the 61st step after the event (3.05 h).
- Timers (`birth`, `build check`, `death`) are accumulators reset to 0 when they fire (prototype behaviour).
- Ids: buildings and beings each count from 1 in creation order; iteration is always ascending id. Building order at start: reactor 1, habitat 2, workshop 3, green room 4.
- Randomness: only `SimRng` (`randf`, `randf_range`, `randi_range`, `chance`, `pick`). No `randomize()`. Draw order is the order written in this spec. Short-circuit conditions draw only when everything before them is true (stated where it matters). Prototype draws that only fed text (thought pick) are dropped.
- Persona: a being keeps the `Persona.persona_from` dictionary from Task 0 (traits in [0, 1]: drive, curiosity, sociability, care, restless, steady, plus role). Only drive, steady, restless, role, and the room-pull traits are read (A12). The chart is never read outside creation.
- Kind ids: `reactor` (proto `core`), `habitat`, `workshop`, `green_room` (proto `garden`), `archive`, `comms`.

## 4. State
### Colony (`Colony`)
`oxygen`, `food`, `ice`, `regolith` (floats); `air_warn_t`, `food_warn_t`, `thirst_warn_t`, `regolith_warn_t`, `waiting_warn_t` (all start at -1e9); `death_timer_h` (0); `birth_timer_h` (0); `last_birth_t` per habitat id (absent = never); `extinct` (bool).
Derived each use (never stored): `pop` (count of living beings), `green_rooms` (online green rooms), `o2_net = green_rooms x 1.4 - pop x 0.05`, `food_net = green_rooms x 1.0 - pop x 0.035`, `o2_cap`, `food_cap`, `ice_target = max(120, 8 x pop)`, `regolith_target = 160 + 12 x (all buildings incl. site)`.
### Building
`id`, `kind`, `tx`, `ty`, `tw`, `th` (tiles), `built` (0..1; 1 = finished), `offline` (bool), `corridor` (to parent: `parent_id`, `p1`, `p2` in px, `len` px, `rect` in tiles). `door` = bottom centre = `((tx + tw/2) x 8, (ty + th) x 8)`.
### Power
`last_short_t` (-1e9), `power_multiplier_until` (-1e9 hook), `shorts_since_row` (stats).
### Construction site
At most one: `building_id`, `parent_id`, `last_work_t`, derived `crew` (beings in state `work` with this job).
### Being
`id`, `name`, `persona`, `role`, `earth_born`, `born_t`, `energy` (0..100), `state` in {`idle`, `to_door`, `transit`, `sleep`, `eva`, `work`, `mining`}, `building_id` (the building it is in, or the one it left from while `transit`/outside; no x,y inside), `wait_h`, `sleep_intent` (bool), `suit_up` (bool), `job` (the site or null), `mine` (`site`, `door`, `home_id`, or null), `mine_intent` (site or null), `air_h` (null unless outside), `x`, `y`, `heading` (only outside, else null), `path` (waypoints), `after` in {null, `mine`, `work`, `haul`, `enter`}, `returning` (bool), `load` (0), `work_left_h`, `step_acc_px`, `foot_side` (+1), `corridor_id`, `transit_t` (0..1), `from_a` (bool).
Derived flags for the view: `suit_kind` = `none` while inside; `construction` when outside with a `job` (state `work`, or `eva` going to or from the site); `eva` for any other outside state. `lamp_on` = outside and night.
### Resources
`ice_fields`: `x`, `y`, `amount`, `start`, `dug`, `r`. `pit`s: `x`, `y`, `dug`, `r` (amount infinite). `footprints`: `x`, `y`, `heading`, `t`, `heavy`.
### World
`log` (list, newest last, capped at `colony.log_cap` = 500), `stats` (section 10), `step_index`.

## 5. Order of operations within one fixed step (0.05 h)
1. `t += dt`; `step_index += 1`. (Task 0 clock.)
2. **Stocks.** `oxygen = clamp(oxygen + o2_net x dt, 0, o2_cap)`; `food = clamp(food + food_net x dt, 0, food_cap)`. Uses `pop` and online green rooms as they stood at the end of the previous step.
3. **Power.** `manage_power()` (section 7.2): at most one short, or at most one re-online, per step.
4. **Air and food warnings** (once per sol while the stock is 0).
5. **Ice.** `ice = max(0, ice - pop x 0.01 x dt)`. Scouting (section 8.4). Thirst warning (once per 2 sols while ice is 0).
6. **Beings.** Each living being, ascending id, runs `update_being(dt)` (section 6.3). A being that dies outside is removed immediately; the loop runs over a snapshot of ids taken at the start of this phase, so a being born later in the step does not act.
7. **Births.** Every 4 h (section 10.1).
8. **Build decision.** Every 5 h (section 7.4).
9. **Construction progress** (section 7.5).
10. **Shortage deaths** (section 9).
11. **Footprint expiry** (drop prints older than 2.5 sols), `extinct` update, stats sampling.
The `to_door`/`transit` arrivals and EVA arrivals happen inside phase 6, so a being that finishes a tunnel walk is idle in the new building for the rest of the step.

## 6. Beings (per-being energy, state machine, persona effects)
### 6.1 Energy
- Start energy: uniform 70..100 (draw `randf_range`).
- Drain per hour while awake, by state: `idle`, `to_door`, `transit` 1.3; `eva` 2; `mining` 2.6; `work` 3. `sleep` does not drain. Energy clamps to [0, 100]. Zero energy has no effect by itself (no death from energy).
- Sleep gain per hour: 11 while `colony.food > 0`, else 4.
- **Go to sleep** (checked at the top of `decide`): `sleep_intent`, or energy < 28, or (night and energy < 65 and `chance(0.6)`). The `chance` is drawn only when night and energy < 65.
- `go_sleep`: nearest online habitat H by distance between building centres from the current building (tie: lowest id). If none, or H is the current building: state `sleep` at once (on the floor if none; same gain). Otherwise next hop by BFS toward H; `sleep_intent = true`; state `to_door`. If no hop exists, sleep on the floor.
- **Wake** while asleep: after gaining, if energy >= 97, or (not night and energy > 75 and `chance(0.3 x dt)`), state `idle`, `wait_h` = `idle_wait()`.
- **Exhausted turn-back**: outside, energy < 12, not `returning`, and state is `mining`, `work`, or `eva` with `after` `mine` or `work`: `turn_back("exhausted")`.
### 6.2 Interior timing (A9)
Inside a building the sim keeps no x,y. Walks inside are timers.
- `idle_wait()` = walk + pause, where walk = U(10, 56) px / (10 x (0.75 + 0.5 drive)) h, pause = U(1, 4) x (0.5 + 1.2 steady) h. A being entering a building, waking, or choosing to stay put gets `wait_h = idle_wait()`. A being whose `sleep_intent` is set on arrival gets `wait_h` = one step. A new being gets `wait_h` = U(0, 2).
- `to_door` time = U(10, 56) px / (16 x (0.75 + 0.5 drive)) h. When it elapses the action tied to the door runs (suit up, or enter the tunnel).
- `wait_h` counts down by dt in `idle`; when it reaches 0 (<= 1e-9) the being calls `decide`.
### 6.3 `update_being(dt)` order
1. `sleep`: gain, wake check, done for this step.
2. Awake drain.
3. Exhausted turn-back check (6.1).
4. If outside: `air_h -= dt`. If `air_h <= 0`: the being dies (cause `suffocated outside`), is removed, logged, stats updated, return. Else if not `returning`, state is `mining`, `work` or `eva` with `after` `mine`/`work`, and `air_h < dist(position, home_door)/16 + 2.5`: `turn_back("low air")` (log at most once per 3 h per being).
5. State handling:
   - `eva`: move toward `path[0]` at 16 px/h (clamped to the remaining distance), footprints; within 0.8 px pop the waypoint; when the path is empty run `finish_eva`.
   - `mining`: section 8.3. `work`: section 7.5. `transit`: `transit_t += dt x 22 / max(1, corridor.len)`; at >= 1 the being is idle in the other building (`wait_h` as 6.2).
   - `idle`/`to_door`: count down `wait_h`.
`home_door` = `mine.door` for miners, the corridor end `p1` (parent side) for builders.
### 6.4 `decide` (in this order, first match wins; each draw only if reached)
1. Sleep (6.1).
2. **Join construction**: a site exists, the being is builderish and `chance(0.55)`. Builderish = role `builder`, or drive > 0.6, or (the site had no crew for more than 1 sol and drive > 0.35). In the parent building: `suit_up`, state `to_door`. Elsewhere: next hop toward the parent, state `to_door` (no suit). No hop: fall through.
3. **Resume `mine_intent`**: cancel if there is no `launch_for(site)` or the field is dry. If the launch building is the current one: `start_mining`. Else hop toward it (state `to_door`); no hop: cancel.
4. **New mining attempt**: `pit/field list non-empty`, no `mine`, `colony.oxygen > 10`, and `chance(0.4 x will x (0.15 + 0.85 x need_max))`. `will = 0.45 steady + 0.35 drive + 0.2 restless`; `need_max = max(0, 1 - ice/ice_target, 1 - regolith/regolith_target)`. Then `choose_site` (section 8.2); if it returns a site: launch building L = `launch_for(site)`; if L is current, `start_mining`; else set `mine_intent` and hop toward L; no hop: nothing.
5. **Restless travel**: the building has built tunnels and `chance(0.08 + 0.32 restless)`: pick a neighbour by weights `0.15 + (pull)^2` where pull = (trait of the neighbour kind x mult) from `beings.room_pull` (draw `randf()` x sum, scan in corridor creation order); state `to_door`.
6. Otherwise stay: `wait_h = idle_wait()`.
`start_mining(site)`: `mine = {site, door = door of current building, home = current}`, `suit_up`, state `to_door`.
### 6.5 Suit-up at the door (when `to_door` ends with `suit_up`)
`colony.oxygen = max(0, oxygen - 1)`; `air_h = 36`; position = the door (building `door` for miners, corridor `p1` for builders), `heading` toward the first waypoint. Miners: state `eva`, `after = mine`, path = [door, arrival point], arrival point = site centre + (cos, sin) x r x U(0.3, 0.8) (y scaled 0.7). Builders: if the site no longer exists or is not their job, they cancel (oxygen already spent) and go idle; else state `eva`, `after = work`, path = [`p1`, `p2`, random point in the site rectangle inset 5 px].
### 6.6 Persona effects (A12)
drive: walk factor `0.75 + 0.5 drive`, construction rate `(0.6 + drive)`, mining yield factor `(0.7 + 0.6 drive)`. steady: pause length factor `0.5 + 1.2 steady`, mine will 0.45. restless: travel chance, mine will 0.2. Role `builder` marks builderish. Room pull uses drive, curiosity, sociability, care, steady as weights only.
### Tests (tests/test_beings.gd)
- Drain: from energy 80, one hour (20 steps) in each state: idle 78.7, eva 78.0, mining 77.4, work 77.0 (tolerance 1e-6); `sleep` from 20 for 1 h gives 31 with food, 24 with food 0.
- Sleep length: from 20 to wake at 97: 77/11 = 7.0 h fed (140 steps +-1), 77/4 = 19.25 h starving.
- Triggers: energy 27.9 sleeps; 28.0 awake in daytime; 64 at night with a seeded RNG sleeps in a 0.6 fraction of 2,000 trials (0.55..0.65); 65 at night never rolls.
- Wake: not night, energy 80: wakes with probability 0.015 per step (1,000 sleepers, one step: 5..30 wake); energy 74 never wakes by day; night never wakes before 97.
- Nearest online habitat: two habitats, the nearer one shorted: picks the farther online one; none online: sleeps on the floor at once; tie goes to the lower id.
- Exhausted: a `work` being at energy 12.01 drains below 12 and gets `returning`; air untouched.
- 5-sol run, no EVA permitted (mining chance forced to 0 by data override, no site): all 7 alive, asleep share between 8% and 20% (hand calc: 1.3 x 24.6597 / 11 = 2.9 h/sol = 11.8%). **The plan said "about a third"; that is wrong for idle drain, see section 13.**
- Persona: a drive 1.0 being walks to a door in 0.6 of the time of a drive 0 being (speed factors 1.25 vs 0.75); the mean pause over 2,000 draws equals 2.5 x (0.5 + 1.2 steady) within 5% (steady 1.0 gives 4.25 h, steady 0 gives 1.25 h).

## 7. Buildings, power, construction
### 7.1 Kinds and draws
Reactor supplies 14 (draw 0). Habitat 3, workshop 4, green room 4, archive 2, comms 3. A construction site draws 2 while `built < 1`. A finished online building draws its kind draw; an offline one draws 0. **Online** = built >= 1 and not offline.
`supply = (finished reactors) x 14 x (1.5 if t < power_multiplier_until else 1)`. `draw = sum of the above`. `margin = supply - draw`.
### 7.2 `manage_power()` (once per step)
- If `draw > supply`: candidates = online non-reactor buildings. If any: `target = newest (highest id)` when `chance(0.6)`, else `rng.pick(candidates)`; (the pick draws only on the failed chance). The target goes `offline = true`; `last_short_t = t`; log `short`; `stats.shorts += 1`. Exactly one building per step; reactors never short. No candidates: nothing happens.
- Else: for offline finished buildings in ascending id, the first one with `draw + its kind draw <= 0.95 x supply` and `t - last_short_t > 3 h` goes online (log `back_online`), then stop. The hold applies to every building (global last short).
- **Hook** `set_power_multiplier(until_t)`: sets `power_multiplier_until` and `last_short_t = -1e9`. This is the only god-power code in Task 1.
### 7.3 Layout
- Founders: reactor at tile (0,0) size 12x10; habitat right (13x9, gap 7), workshop down (12x9, gap 6), green room left (12x9, gap 7). Computed rects: habitat (19,1,13,9), workshop (0,16,12,9), green room (-19,1,12,9). Doors: reactor (48,80), habitat (204,80), workshop (48,200), green room (-104,80). Corridors (px, p1 on the parent side): habitat p1 (96,44) p2 (152,44) len 56; workshop p1 (52,80) p2 (52,128) len 48; green room p1 (0,44) p2 (-56,44) len 56.
- `find_spot` (new site): up to 80 tries; each draws `pick(finished buildings)` (including offline), `pick(['r','l','u','d'])`, `tw = randi(10,14)`, `th = randi(8,10)`, `gap = randi(5,9)`. The new rect sits `gap` tiles beyond the parent in that direction, centred on the parent's mid row or column; the connecting corridor rect is 3 tiles wide and `gap` long. Reject if the rect is within 2 tiles of any building (including the site) or within 1 tile of any corridor; reject if the corridor rect is within 1 tile of any other building (except the parent) or any other corridor. First acceptable spot wins; none after 80 tries: no site this check.
- Tunnels connect parent and child; a corridor is traversable when `built >= 1` (it grows with the site). Offline buildings are passable (A3).
- BFS `next_hop(from, to)`: breadth first over built corridors in creation order; returns the first corridor on the path, or none.
### 7.4 Build decision (every 5 h)
Ready = no site, and at least one `builder` role being is in an **online workshop** and "inside" (state not `transit`, `eva`, `work` or `mining`; as in the prototype, a sleeper counts). If ready: `kind = choose_kind()`; `cost = (18 if reactor or green room else 28) + 4 x (number of existing buildings, finished ones only since no site exists)`; if `regolith < cost`: log `need_regolith` (once per 2 sols), else `find_spot`; on success create the site (`built = 0`), deduct cost, log `ground_broken`. A failed `find_spot` charges nothing. `choose_kind` is called only when ready (so it consumes RNG only then).
`choose_kind`, first match wins:
1. `margin < 5` -> reactor.
2. `o2_net < 0.4` or `food_net < 0.25` or `oxygen < 3 sols x pop x 0.05 x sol_hours` or `food < 3 sols x pop x 0.035 x sol_hours` (A5 floor) -> green room.
3. `pop + 2 > 5 x (finished habitats, offline included)` -> habitat.
4. Else `rng.pick` over `[archive, comms, green_room, habitat, habitat]` plus `workshop` while finished workshops < 3.
Hand check: at founding, margin = 14 - 11 = 3, so the first site is a reactor at cost 18 + 4 x 4 = 34 (regolith 80 -> 46). The next site (habitat, cost 28 + 4 x 5 = 48) cannot start until at least 2 more regolith is mined: regolith is the first binding constraint.
### 7.5 Construction progress (per step, after the build decision)
`crew` = beings in state `work` with `job = site`. If any, `last_work_t = t`. `progress += sum over crew of (0.6 + drive) x (0.55 + energy/220) x dt / 34`, clamped to 1. No crew: zero progress. Corridor `built` equals the building's. On reaching 1: log `building_done`, every crew member enters the new building (state `idle`, `air_h = null`), the site is cleared, draw changes from 2 to the kind draw.
Work state (builder on site): `work_left_h = U(8, 16)` on arrival; wanders between random points in the footprint at 6 px/h pausing U(0.8, 2.4) h; when `work_left_h` reaches 0, path [`p2`, `p1`, inside parent], `after = enter`, `job = null`. If the site disappears the being walks to the nearest door as if returning.
Waiting: if a site has had no crew for more than 1 sol, log `waiting_for_builders` (once per sol).
### Tests (tests/test_power.gd, tests/test_construction.gd)
- Supply/draw: 1 reactor + habitat + workshop + green room = draw 11, supply 14, margin 3. Add a site: draw 13. Add archive and comms: draw 18 > 14, one non-reactor goes dark per step until draw <= 14.
- Over-limit shorts exactly one non-reactor building per step, never a reactor, never a site; with no candidates nothing happens.
- Newest-vs-random (corrected): P(newest) = 0.6 + 0.4/n. With n = 10 candidates and 1,000 seeded trials the newest fraction is in 0.60..0.68 (expected 0.64); with n = 4 it is in 0.65..0.75 (expected 0.70).
- Re-online: an offline habitat (draw 3) with draw 8, supply 14: 8 + 3 = 11 <= 13.3 and hold passed -> online; at draw 11 (11 + 3 = 14 > 13.3) -> stays offline; at 60 steps after a short -> stays offline, at 61 -> online; ascending id order with two offline; only one re-online per step.
- Offline effects: an offline green room adds 0 to `green_rooms` (nets drop to -0.35 and -0.245 with 7 beings); an offline habitat is not chosen by `go_sleep` and gives no births; an offline workshop makes `ready` false; an offline building draws 0.
- Fortune hook: `set_power_multiplier(t + 24.6597)`: supply 28 -> 42 (2 reactors), a dark building returns on the next step if load fits; after one sol supply returns to 28 and the building may short again.
- Cost: reactor/green room 18 + 4 x n, others 28 + 4 x n; the first build at seed 42 with founders is a reactor (margin 3), cost 34, regolith 46.
- No crew: 1,000 steps with no `work` beings give progress 0. One builder, drive 0.7, energy 80: rate = 1.3 x 0.9136 / 34 = 0.03493 per h, 0.001747 per step (+-1e-6). Three such builders triple it.
- One site at a time: a second `start` while a site exists returns false and changes nothing.
- `choose_kind` order: margin 4 returns reactor even when o2_net is 0.1; margin 5 and o2_net 0.39 returns green room; `oxygen = 25, pop = 7` (floor 3 x 24.6597 x 0.05 x 7 = 25.89; food floor 18.12) returns green room even with nets fine; pop 9 with 1 habitat returns habitat; otherwise only kinds from the pool, workshop only below 3.
- Build timing: the check fires exactly at steps 100, 200, ...; no check draws RNG when no builder is ready.
- Layout (tests/test_layout.gd): the founder rects, doors and corridors above exactly; door = bottom centre for 100 random rects; `find_spot` over 500 seeds with 20 sites each never overlaps (margin 2) nor crosses a corridor (margin 1); BFS returns the shortest corridor chain on a hand-made 5-node graph and none when disconnected; unfinished corridors are not traversed.

## 8. Resources, scouting, mining
### 8.1 Spawn (A2 fixed)
`spawn_site(kind, range)`: up to 400 tries; each draws `pick(online buildings)` (anchor), angle U(0, 2pi), distance U(range) + 0.08 x try. Position = anchor door + distance x (cos, sin). Accept only if: at least 55 px from every building rectangle; more than 90 px from every other field or pit; outside every corridor rect inflated by 30 px; **and** `trip_time(candidate) = 2 x (d_launch + r)/16 + 6 < 0.85 x 36` where `d_launch` is the distance to the door of the nearest online building (so `d_launch + r < 196.8` px). A rejected candidate is simply retried. No online building: no spawn. Ice field: amount U(260, 420), r U(16, 24). Pit: r 9, infinite.
Founders: pit range 70..110, ice ranges 90..150 and 100..160 (spawn order pit, ice, ice), anchors the four founding buildings.
### 8.2 Choosing a site (`choose_site`)
Live sites = pits, plus ice fields with amount > 0, whose `trip_time(from nearest online door) < 30.6`. `ice_need = 1 - min(1, ice/ice_target)`, `reg_need = 1 - min(1, regolith/regolith_target)`. Want ice if `ice < 30` or (ice fields exist and `chance((ice_need + 0.15)/(ice_need + reg_need + 0.3))`; the draw only when ice >= 30 and ice fields exist). Pool = ice fields if wanted and any, else pits if any, else ice fields. Return none when the pool is empty, or the pool is pits and `regolith > 1.3 x regolith_target`, or ice and `ice > 1.3 x ice_target`. Else `rng.pick(pool)`.
`launch_for(site)` = the online building whose door is nearest to the site (tie: lowest id); none if no building is online.
### 8.3 Mining
- After suit-up and EVA to the arrival point: state `mining`, `work_left_h = U(5, 9)`; wander inside the field (target = centre + angle x r x U(0.2, 0.8), y x 0.7) at 4 px/h, pausing U(0.6, 2) h, footprints on.
- When `work_left_h <= 0` or an ice field is dry: `yield = U(6,10)` (ice) or `U(8,14)` (regolith) x (0.7 + 0.6 drive) x (0.55 + energy/220). Ice: `yield = min(yield, field.amount)`; `field.amount -= yield`. `load = yield`; state `eva`, `after = haul`, path [`mine.door`, inside home].
- A turn-back while mining sets `load = U(2, 5)` (limited by ice remaining). A turn-back while still walking out sets no load.
- At the end of `haul`: `ice += load` (or regolith); no cap on either stock; `load = 0`; the being enters `mine.home`.
- **Dry-up**: when a field's amount reaches 0 it is removed from the list, log `ice_dry`, and if reachable fields < 2 a new one is spawned at once (log `ice_found`). A miner already there keeps going home with its load.
### 8.4 Scouting (per step, after the ice drain)
`reachable = ice fields with amount > 0 and trip_time < 30.6`. If `reachable < 2`: `chance(0.05 x dt)`; on success `spawn_site(ice, 90..170)` and log `scouts_found`. Scouting never stops.
### 8.5 Suits, EVA, footprints
- Tank 36 h; one fill costs 1 colony oxygen (A8; the tank would hold 36 x 0.05 = 1.8). A fill at oxygen 0 still gives a full tank.
- `air_h` falls 1 h per hour outside only (walking in a built tunnel is inside). A being whose `air_h <= 0` dies, cause `suffocated outside`.
- Turn-back when `air_h < dist/16 + 2.5` (suits 2.5 h margin). Returning paths are straight to the home door: miners [`mine.door`, inside]; builders [`p1`, inside] (**fix**: the prototype sent builders to `p2` first). No second turn-back while `returning`.
- Trip filter (`trip_time < 0.85 x 36 = 30.6`, i.e. site centre within 196.8 px of the launch door with the 6 h overhead) applies at choice time and spawn time.
- Footprints: every outside move (EVA, mining wander, construction wander) adds `moved` to `step_acc_px`; at >= 2.2 px: reset to 0, flip `foot_side`, add a print at the position offset 0.7 px perpendicular to the heading on that side; `heavy = job != null or load > 0`; oldest dropped past 2,200; prints older than 2.5 sols (61.649 h) are removed in phase 11. (Deviation: the prototype left prints only for EVA and mining; builders shuffling at the site now leave heavy prints too, matching HANDOFF "every suited being".)
### Tests (tests/test_suits.gd, tests/test_layout.gd)
- Suit-up: oxygen 100 -> 99, `air_h = 36`; at oxygen 0.4 it clamps to 0 and the tank is still 36.
- Death: a being outside with `air_h = 0.04` after one step dies (`air_h` -0.01), cause `suffocated outside`, removed, `stats.deaths.suffocated_outside = 1`, log line.
- Turn-back: a miner 160 px from the door turns back when `air_h < 160/16 + 2.5 = 12.5`, not at 12.6; walking home needs 10 h, arriving with >= 2.5 h; builder returns by [`p1`, inside], not via `p2`.
- Filter: a field 196 px from the nearest online door with r 16 fails (2 x 212/16 + 6 = 32.5); 170 px with r 24 passes (2 x 194/16 + 6 = 30.25 < 30.6).
- Spawn invariant (500 seeds x 40 spawns each over a growing hand-made colony): every spawned field has `trip_time < 30.6`, is >= 55 px from every building, > 90 px from every other site, outside corridors + 30 px; a spawn with no online building returns none.
- Launch: with the nearest building offline, `launch_for` returns the next nearest online one; the miner walks tunnels to it before suit-up; no online building -> intent cancelled and no oxygen spent.
- Yield: drive 0.5, energy 80: ice yield in 5.48..9.14 (6..10 x 1.0 x 0.9136); regolith 7.31..12.79; ice never goes below 0 in the field; a dry field is removed, logged once, and a new one appears when reachable < 2.
- Scouting: reachable 1: the chance is 0.05 x 0.05 = 0.0025 per step, so over 2,000 steps (100 h) the fraction of 500 seeds that spawn at least once is 1 - e^-5 = 0.993 (0.97..1.0); reachable 2: no spawns in 2,000 steps; after a field dries with 2 others live, no extra spawn; scouting continues after the pit has been dug (pits do not matter).
- Footprints: a being walking 22 px outside leaves 10 prints (22/2.2), alternating sides +-0.7 px; heavy only for a being with a job or a load; 2,201st print removes the oldest; a print aged 61.7 h is gone after phase 11; one aged 61.6 h stays.
- Flags: `suit_kind` is `none` inside, `construction` for a builder with a job outside, `eva` for a miner; `lamp_on` true at Mars hour 21.5, 23, 2, 5.4; false at 5.5, 12, 21.4 and always false inside.
- Mining chance: 10,000 decide calls with will 0.5, need_max 1 and oxygen 100 produce a mining intent in 0.4 x 0.5 x 1 = 0.2 +-0.02; with oxygen 10 none.

## 9. Colony stocks, life support, death
### 9.1 Stocks (phase 2 and 5)
Starting stocks: oxygen 140, food 110, ice 60, regolith 80. Green room +1.4 oxygen and +1.0 food per hour (online only). Per being per hour: oxygen 0.05, food 0.035, ice 0.01. Caps: oxygen 400 + 150 per online green room, food 300 + 120 per online green room (stocks only drop to the cap when a green room goes offline, by clamping on the next step). Ice and regolith have no cap (mining stops by the 1.3 x target rule).
Warnings: when oxygen is 0, one `air_low` log per sol; food 0, `food_empty` per sol; ice 0, `water_dry` per 2 sols.
### 9.2 Death by shortage (phase 10)
If pop > 0 and (oxygen <= 0 or food <= 0 or ice <= 0): `death_timer_h += dt`; interval = 2 h if oxygen <= 0, else 5 h if ice <= 0, else 6 h. When the timer exceeds the interval (1e-9 slack): reset to 0; `chance(0.4)`; if it succeeds, the victim = `rng.pick` among beings that are inside (not `transit`, `eva`, `work`, `mining`; sleepers included), or among all beings if none is inside. Cause by priority air, then thirst, then hunger. Else the timer resets to 0 every step. (Owner decision: prototype pace, A6.)
### 9.3 Death causes (recorded on the log and `stats.deaths`)
`air` ("died when the air ran out"), `thirst` ("died of thirst"), `hunger` ("starved"), `suffocated outside` ("ran out of air on the surface"). Every death: `{t, sol, being_id, name, cause}` in the log and in `stats.deaths_list`. No other cause exists in Task 1; `stats.deaths.other` must stay 0.
### Tests (tests/test_colony.gd)
- 1 green room, 7 beings: `o2_net` 1.05, `food_net` 0.755 per h (1e-9); one sol of steps moves oxygen by 1.05 x 24.6597 = 25.89 and food by 18.62 (stocks well under caps).
- No green room: nets -0.35 and -0.245; offline green room the same.
- Caps: 0 green rooms o2 400 / food 300; 1: 550 / 420; 3: 850 / 660. Stock above the new cap is clamped when a green room goes offline.
- Clamp: oxygen 0.01 with net -0.35 stays 0, never negative; same for food and ice.
- Ice drain: 7 beings 0.07 per h (1.726 per sol); pop 0 no drain; ice target `max(120, 8 pop)`: 120 at 7 and at 15, 160 at 20; regolith target 160 + 12 x 5 = 220 with 5 buildings.
- Warnings: oxygen 0 for 3 sols produces exactly 3 `air_low` lines (at t0, t0 + 1 sol, t0 + 2 sols); thirst 1 per 2 sols.
- Death timer: oxygen 0, 7 beings, 400 seeded runs of 20 h: deaths average 20/2 x 0.4 = 4 (3.5..4.5); only air interval used even if food is also 0; ice 0 only: interval 5; food 0 only: interval 6; any shortage ending resets the timer to 0.
- Cause priority: oxygen 0 and ice 0 together -> cause `air`; ice 0 and food 0 -> `thirst`; victims never include beings in `transit` or outside while an inside being exists; a colony with all beings outside picks among all.
- Extinction: 0 beings: no deaths, no births, `extinct = true`, one log line, the sim keeps stepping.
- Determinism seeds: two worlds at seed 42 stepped 5,000 steps have equal stocks, log and beings; seed 43 differs.

## 10. Births and founders
### 10.1 Birth check (every 4 h, phase 7)
Habitats in ascending id; each re-evaluates with the live population. For a finished habitat H: `here` = beings inside H (sleepers included, not `transit`/outside). `need = 1 if pop < 4 else 2`. `warmth = mean over here of (sociability + care)` (1 if none, avoided by `need`). A birth happens if all hold: H online; `|here| >= need`; ice > 5; food > 15; oxygen > 20; `o2_net > 0.1`; `food_net > 0.05`; `pop < 5 x (online habitats) + 2`; **cooldown** `t - last_birth_t[H] >= 1 sol` (new, A4; a habitat that has never had a birth is free); and `chance(0.08 + 0.14 x warmth)` (drawn only when everything before holds). Then the parent is `rng.pick(here)`, the newborn is created in H (name, persona from `MarsSky.mars_chart` at the building's longitude `lon_of_tile(tx + tw/2)`, energy U(70,100), `wait_h` U(0,2), `earth_born = false`), `last_birth_t[H] = t`, log `born`.
Expected effect of the cooldown: with warmth about 0.9 the chance is about 0.2 per check, mean wait about 20 h; the cooldown (24.66 h, first usable check at the next 4 h grid) makes the mean interval per habitat about 1.2 sols instead of 0.8. It is a mild brake, a first balance knob, not a cap.
### 10.2 Founders (A1)
Seven Earth-born founders, created in layout order (`beings.founders.layout`): habitat x4 (builder, builder, social, curious), reactor x2 (tender, social), workshop x1 (builder). Each founder is `MarsSky.founder_birth(rng, cfg)` (Task 0 draw: age 24..45 years, longitude -120..140), persona from it; if the role does not match, redraw the whole `founder_birth` up to 300 times (ages stay within 24..45; the prototype let age run to 60), keep the last if none match and count `stats.founder_role_miss`. Name = syllable A + syllable B + "-" + number 1..99. Energy U(70,100), `wait_h` U(0,2). Creation order (and so RNG order): **layout, founders in layout order, then sites (pit, ice, ice)**. The log starts with `founders_landed`.
### Tests (tests/test_births.gd)
- Gate matrix: starting from a state that passes, break each gate once (online, `|here|`, ice 5, food 15, oxygen 20, nets 0.1 and 0.05, capacity, cooldown); no birth in any broken case over 500 checks; with all gates passing and warmth 0.9 the birth rate per check is 0.206 +-0.03 (1,000 seeded checks).
- `need`: pop 3 and one being in H gives births possible; pop 4 and one being gives none; two beings give births.
- Capacity: 1 habitat: no birth at pop 7 (cap 7), allowed at 6; 2 habitats online: cap 12; one offline: cap 7.
- Cooldown: after a birth, the same habitat cannot birth for 24.6597 h (checks at +4, +8, ..., +24 blocked; +28 allowed); another habitat is unaffected.
- Newborn: persona from `mars_chart` at `lon_of_tile` of the building (compare to a direct call), `earth_born` false, id next in sequence, is inside H.
- Founders: seed 42 gives exactly 3 builders, 2 social, 1 curious, 1 tender in the layout homes; 200 seeds never leave a mismatched role; the Task 0 expectations that depend on founder RNG order are updated in the same commit (see section 13).
- First birth at seed 42 happens no earlier than sol 2 (needs a second habitat since pop 7 = capacity 7).

## 11. Resolved ambiguities (A1..A13)
| # | Resolution |
| --- | --- |
| A1 | Copy the prototype layout and role mix; retry loop redraws the whole founder birth (ages stay 24..45); section 10.2. |
| A2 | Spawn is rejected, not clamped, unless `2(d_launch + r)/16 + 6 < 30.6` with `d_launch` to the nearest online door; creep stays at 0.08 px per try but cannot break the rule; spawn needs an online building. Dry fields leave the list. Reachable (not merely live) fields drive scouting. |
| A3 | Launch from the nearest online door as the prototype. Offline buildings are passable (tunnels carry no power in the prototype), so "no path" cannot happen with a connected graph; the cancel rule stays as a guard and is tested on a hand-made graph. |
| A4 | Per-habitat cooldown 1 sol, first balance knob (owner decision). |
| A5 | Prototype nets kept; they already scale with population (net subtracts pop x use). Added floor: green room when oxygen or food would last under 3 sols with zero production (`3 x sol_hours x pop x use`). |
| A6 | Prototype pace, p 0.4, interval 2/5/6 h, cause priority air > thirst > hunger (owner decision). |
| A7 | Kept (0.95, 3 h). Success check is balance target 5; fallback knob is `reonline.hold_h`. |
| A8 | Fill = 1 colony oxygen; tunable `suits.fill_colony_o2`. |
| A9 | Interiors are timers (6.2): walk px range 10..56 for both a walk to a random point and to a door, so the decision cadence (about 6 h between decisions for a steady being) matches the prototype's interior walking. No x,y inside. |
| A10 | `suit_kind` and `lamp_on` flags (section 4). |
| A11 | One `SimRng`, ascending ids, draw order as written, thought picks dropped. Determinism is balance target 9. |
| A12 | Section 6.6. |
| A13 | Section 7: offline green room produces nothing and counts 0 in nets and caps; offline habitat: no bunks (`go_sleep` skips it), no births, no capacity; offline workshop: no `ready`; offline draws 0. Sleepers in a habitat that shorts keep sleeping. |
Further decisions: wall-clock-free timers (1e-9 slack); builder return path fix; builders' footprints; `choose_kind` only when ready; ice field removed on dry-up; shortage victims as prototype; `waiting_for_builders` log (new, feeds target 6).

## 12. Tunables (JSON key path, unit, starting value, source)
### colony.json
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| start.oxygen / food / ice / regolith | stock | 140 / 110 / 60 / 80 | proto L267, L272 |
| production.o2_per_green_room / food_per_green_room | per h | 1.4 / 1.0 | proto L712-713 |
| consumption.o2_per_being / food_per_being / ice_per_being | per h | 0.05 / 0.035 / 0.01 | proto L712, L713, L742 |
| caps.o2_base / o2_per_green_room | stock | 400 / 150 | proto L736 |
| caps.food_base / food_per_green_room | stock | 300 / 120 | proto L737 |
| targets.ice_min / ice_per_being | stock | 120 / 8 | proto L273 |
| targets.regolith_base / regolith_per_building | stock | 160 / 12 | proto L274 |
| death.air_interval_h / thirst_interval_h / hunger_interval_h | h | 2 / 5 / 6 | proto L821 |
| death.chance | prob per interval | 0.4 | proto L823 |
| warnings.air_food_repeat_sols / thirst_repeat_sols | sols | 1 / 2 | proto L739-745 |
| warnings.regolith_repeat_sols / waiting_repeat_sols | sols | 2 / 1 | proto L797 / new |
| birth.check_interval_h | h | 4 | proto L771 |
| birth.base_chance / warmth_coef | prob / x | 0.08 / 0.14 | proto L779 |
| birth.min_beings / min_beings_small_colony / small_colony_below | beings | 2 / 1 / 4 | proto L777 |
| birth.gate_ice_above / food / oxygen | stock | 5 / 15 / 20 | proto L779 |
| birth.gate_o2_net_above / gate_food_net_above | per h | 0.1 / 0.05 | proto L779 |
| birth.habitat_capacity / capacity_bonus | beings | 5 / 2 | proto L773 |
| birth.cooldown_sols | sols per habitat | 1 | owner, A4 |
| stock_days_floor_sols | sols | 3 | A5 |
| log_cap | entries | 500 | new |
### buildings.json
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| tile_px | px | 8 | proto T |
| kinds.reactor / habitat / workshop / green_room / archive / comms .draw | power | 0 / 3 / 4 / 4 / 2 / 3 | proto L705 |
| reactor_supply | power | 14 | HANDOFF 5 |
| site_draw | power | 2 | proto L710 |
| fortune.multiplier / duration_sols | x / sols | 1.5 / 1 | proto L709, L1719 |
| short.newest_chance | prob | 0.6 | proto L726 |
| reonline.load_fraction / hold_h | frac / h | 0.95 / 3 | proto L730 |
| build.check_interval_h | h | 5 | proto L789 |
| build.cost_reactor / cost_green_room / cost_other / cost_per_building | regolith | 18 / 18 / 28 / 4 | proto L794 |
| build.waiting_site_idle_sols | sols | 1 | proto L460 (builderish widening) |
| choose.reactor_margin | power | 5 | proto L340 |
| choose.o2_net_floor / food_net_floor | per h | 0.4 / 0.25 | proto L341 |
| choose.crowd_margin | beings | 2 | proto L342 |
| choose.pool / workshop_cap | list / count | archive, comms, green_room, habitat, habitat / 3 | proto L343-344 |
| size.tw / th / gap | tiles | 10..14 / 8..10 / 5..9 | proto L303 |
| find_spot.tries / overlap_margin_tiles / corridor_margin_tiles / corridor_width_tiles | count / tiles | 80 / 2 / 1 / 3 | proto L301-313 |
| construction.denominator_h | h | 34 | proto L806 |
| construction.drive_base | x | 0.6 (rate = (0.6 + drive)) | proto L806 |
| construction.join_chance | prob | 0.55 | proto L514 |
| construction.builderish_drive / builderish_drive_idle | trait | 0.6 / 0.35 | proto L460 |
| construction.shift_h / wander_wait_h | h | 8..16 / 0.8..2.4 | proto L499, L660 |
| construction.work_point_inset_px | px | 5 | proto L1338 |
| layout.core / attached[] | tiles | see file (12x10; r 13x9 gap 7; d 12x9 gap 6; l 12x9 gap 7) | proto L1800-1814 |
### beings.json
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| founders.layout | list | habitat: builder, builder, social, curious; reactor: tender, social; workshop: builder | proto L1815-1818 |
| founders.role_retry_tries | count | 300 | proto L368 |
| names.syllables_a / syllables_b / number | list / list / int range | as prototype / 1..99 | proto L258-259, L363 |
| energy.start | energy | 70..100 | proto L375 |
| energy.max | energy | 100 | proto L596 |
| energy.drain_idle / eva / mining / work | per h | 1.3 / 2 / 2.6 / 3 | proto L402 |
| energy.sleep_gain_fed / starving | per h | 11 / 4 | proto L596 |
| energy.sleep_below / night_sleep_below / night_sleep_chance | energy / energy / prob | 28 / 65 / 0.6 | proto L509 |
| energy.wake_at / day_wake_above / day_wake_chance_per_h | energy / energy / per h | 97 / 75 / 0.3 | proto L597 |
| energy.exhausted_turn_back | energy | 12 | proto L601 |
| effort.energy_base / energy_divisor | x / energy | 0.55 / 220 | proto L629, L806 |
| night.start_hour / end_hour | clock h | 21.5 / 5.5 | proto L382 |
| pause.base_h / steady_base / steady_coef | h / x / x | 1..4 / 0.5 / 1.2 | proto L697 |
| initial_wait_h | h | 0..2 | proto L375 |
| restless.travel_base / travel_coef | prob / x | 0.08 / 0.32 | proto L546 |
| room_pull.floor / exponent | x | 0.15 / 2 | proto L548 |
| room_pull.weights.* | trait, mult | workshop drive 1; archive curiosity 1; comms curiosity 0.8; habitat sociability 1; green_room care 1; reactor steady 0.7 | proto L547 |
| walk.door_px_h / interior_px_h | px/h | 16 / 10 | proto L699 |
| walk.drive_base / drive_coef | x | 0.75 / 0.5 | proto L699 |
| walk.interior_walk_px | px | 10..56 (NEW, A9; mean 33 = about the mean distance between two random points in a 12x9 room) | derived |
| tunnel_speed_px_h | px/h | 22 | proto L666 |
### suits.json
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| tank_h | h | 36 | proto L706 |
| eva_speed_px_h | px/h | 16 | proto L706 |
| fill_colony_o2 | stock | 1 | proto L680 |
| return_margin_h | h | 2.5 | proto L611 |
| trip_filter / trip_overhead_h | x tank / h | 0.85 / 6 | proto L440-442 |
| work_speed_construction_px_h / mining | px/h | 6 / 4 | proto L661, L647 |
| waypoint_reach_px | px | 0.8 | proto L621 |
| low_air_log_repeat_h | h | 3 | proto L614 |
| footprint.spacing_px / side_offset_px | px | 2.2 / 0.7 | proto L578-582 |
| footprint.fade_sols / cap | sols / count | 2.5 / 2,200 | HANDOFF 5, proto L584 |
### resources.json
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| ice_field.amount / radius_px | stock / px | 260..420 / 16..24 | proto L419 |
| pit.radius_px | px | 9 | proto L419 |
| spawn.ice_px / pit_px | px | 90..170 / 70..110 | proto L635, L1819 |
| spawn.founder_ice_px / founder_pit_px | px | 90..150 and 100..160 / 70..110 | proto L1819-1821 |
| spawn.tries / creep_px_per_try | count / px | 400 / 0.08 | proto L412-413 |
| spawn.clearance_building_px / site_px / tunnel_px | px | 55 / 90 / 30 | proto L415-417 |
| scout.chance_per_h / min_reachable | per h / count | 0.05 / 2 | proto L743-744 |
| mining.shift_h | h | 5..9 | proto L486 |
| mining.yield_ice / yield_regolith | stock | 6..10 / 8..14 | proto L629 |
| mining.drive_base / drive_coef | x | 0.7 / 0.6 | proto L629 |
| mining.partial_load | stock | 2..5 | proto L569 |
| mining.arrive_radius_frac / wander_radius_frac | x r | 0.3..0.8 / 0.2..0.8 | proto L681, L646 |
| mining.wander_y_scale / wander_wait_h | x / h | 0.7 / 0.6..2 | proto L646 |
| mine_will.steady / drive / restless | x | 0.45 / 0.35 / 0.2 | HANDOFF 3, proto L452 |
| mine_attempt.chance / floor / o2_gate | x / x / stock | 0.4 / 0.15 / 10 | proto L535 |
| want.ice_urgent_below / ice_bias / need_sum_bias | stock / x / x | 30 / 0.15 / 0.3 | proto L445 |
| want.stop_factor | x target | 1.3 | proto L448-449 |
Not data (hard rules): the cause priority air > thirst > hunger, 4 directions of `find_spot`, ascending id order.

## 13. Balance targets (confirmed or adjusted)
Balance run table: as in the plan section 4, plus window minima (min oxygen, food, ice) and the extra columns below. Rows every 30 sols.
| # | Target | Verdict and reason |
| --- | --- | --- |
| 1 | 7 founders, 300 sols, five seeds (42, 7, 99, 1234, 2026): >= 5 alive at every row, never 0 | Confirmed. The death model is harsh (p 0.4 per interval), so this is only reachable when no shortage persists. |
| 2 | Every death has a cause in the log; no shortage death while oxygen, ice, food are all above 0; **EVA deaths = 0** (plan: <= 1 per 100 sols) | Adjusted. The sim has no random outdoor hazard and the turn-back margin (2.5 h) plus spawn invariant guarantee return, so any EVA death is a bug. `stats.deaths.other` = 0. |
| 3 | Pop at sol 30 <= 15, sol 100 <= 30, sol 300 <= 60; first birth no earlier than sol 2; **no birth is ever made at pop >= 5 x online habitats + 2 and at most 1 birth per habitat per cooldown** | Adjusted wording. Population may exceed capacity after a habitat shorts (nobody is removed), so the cap is on the birth, not on pop. Sol-2 floor is structural: pop 7 equals capacity 7 until a second habitat is built. 60 beings needs about 12 habitats and 3 green rooms (one per about 20 beings with the 0.4 net floor), which is a big but possible build for 300 sols. |
| 4 | Oxygen, food, ice > 0 **at every step (window minima) after sol 5**; ice > 20 after sol 30; ice and regolith < 3 x target | Adjusted: rows alone could miss a dip. Mining stops at 1.3 x target, so 3 x is generous. |
| 5 | Draw <= supply in >= 90% of rows; <= 2 shorts per sol; no building offline > 1 sol; a reactor built by sol 10 | Adjusted: after `manage_power` draw <= supply almost always, so "draw" is meaningless. Use `demand` = the draw if no building were offline; demand <= supply in >= 90% of rows. Shorts per sol and offline duration are tracked as maxima. |
| 6 | Growth is limited by something: `need_regolith` or `waiting_for_builders` count > 0 over 300 sols on at least 4 of 5 seeds | Confirmed, with a count rule. Hand calc already shows regolith binds at the second build (46 left vs 48 needed). If it fails everywhere, tighten `birth.cooldown_sols`. |
| 7 | Mining reachable: zero `turn_backs_air` during mining or work (the invariant makes them unnecessary); >= 2 reachable ice fields on >= 95% of **sol boundaries** (plan: 30-sol checkpoints, only 10 samples) | Adjusted sampling. Worst-case trip: 2 x 172.8/16 + 9 h shift + 2.5 margin = 33.1 h < 36, so no air turn-back at the spawn limit. |
| 8 | Average energy 40..90 on every row; **time-averaged asleep share per window between 5% and 30%** (plan: <= 25% at any row); no sleep stretch > 18 h | Adjusted. Idle 11.8% asleep; busy builders (3 per h for 8-16 h) can push it to about 25%, so 25% at a snapshot is too tight; the window average is the right measure. The 18 h limit only holds while food > 0 (a fed sleep from 0 to 97 takes 8.8 h; starving takes up to 24 h). |
| 9 | Same seed and sols give a byte-identical table (incl. data hash and `String.sha256_text` of the table body) | Confirmed. |
Additional columns: `demand`, `max_shorts_per_sol`, `max_offline_h`, `reachable_ice_sols_ok`, `min_oxygen`, `min_food`, `min_ice`, `turn_backs_air`, `turn_backs_exhausted`, `need_regolith`, `waiting_for_builders`, `max_sleep_h`.
Knob order unchanged: `birth.cooldown_sols`, `birth.base_chance`, `consumption.ice_per_being`, `scout.chance_per_h`, `mine_attempt.chance`, `choose.reactor_margin`, `stock_days_floor_sols`. One change per run, same seeds. Note: the cooldown is a mild brake (section 10.1); if growth still tracks capacity, the first knob may need to go to 2 or 3 sols (a decision for Herby at that point).
Hand-calculated starting sanity: one green room supports 1.4/0.05 = 28 beings on oxygen and 1.0/0.035 = 28.6 on food, but the 0.4 net floor triggers a second green room at 20 beings. Ice use at 7 beings is 1.7 per sol; one ice field of 340 lasts about 200 sols of use at that size, 23 sols at 60 beings. A miner gains about 7 ice per trip.
Runtime (owner): `fixed_step` stays 0.05 h even if a 300-sol run takes minutes.

## 14. Edge cases (global)
- Zero online buildings: no launch, no spawn, no sleep bunks (floor sleep), no building decisions; a being in a tunnel finishes its walk.
- Zero reactors cannot occur (reactors never short, never removed). Supply 0 would short everything.
- A being in a habitat that goes dark keeps sleeping; nobody is evicted.
- A being dies while on a job or a mining trip: it is removed; its load is lost; the field is unchanged except what it already dug; crew count drops next step.
- The site's parent can go offline: the tunnel is still traversable; builders still suit up at `p1`.
- The last founder dies: `extinct`, no more events except stocks.
- Two miners finishing at the same dry field: the second gets min(yield, remaining) = 0 and hauls 0; no negative amounts.
- `find_spot` fails every time (crowded): the check repeats in 5 h; no regolith charged.
- Colony oxygen at 0 does not stop builders from suiting up (prototype); miners need oxygen > 10 to start (A8).
- Equal-distance ties anywhere (nearest habitat, nearest launch door, BFS) go to the lowest id or first-created corridor.
- A site's `last_work_t` starts at its creation time.
- Night spans midnight (21.5 to 5.5): test with hours 23 and 2.

## 15. Headless proofs not tied to one subsystem
- tests/test_determinism.gd: two worlds at seed 42 for 30 sols (about 14,800 steps) give an identical stats, log and being list hash; seed 7 differs.
- tests/balance_run.gd: header (seed, sols, overrides, data hash), table, PASS or FAIL against section 13. Exit code 0 on PASS, 1 on FAIL. A second run of the same command is byte-identical.
- Check "every number appears in data": a test walks this spec's section 12 table keys and asserts each key path exists in the loaded JSON (`SimData`), and that the reactor supply, draws, tank and cost values equal the spec's.
- No sim file contains a tunable literal other than 0, 1, 2 (reviewer step 13).

## 16. Stats keys (`SimWorld.stats`)
`births`, `deaths` {air, thirst, hunger, suffocated_outside, other}, `deaths_list`, `shorts`, `reonlines`, `mining_trips` (counted at suit-up for mining), `turn_backs_air`, `turn_backs_exhausted`, `builds_started`, `builds_finished`, `need_regolith`, `waiting_for_builders`, `ice_dry`, `scouts_found`, `founder_role_miss`. Log kinds: `founders_landed`, `ground_broken`, `building_done`, `short`, `back_online`, `born`, `died`, `air_low`, `food_empty`, `water_dry`, `need_regolith`, `waiting_for_builders`, `suit_low_air`, `ice_dry`, `ice_found`, `scouts_found`, `colony_silent`. Each entry `{t, sol, kind, text, being_id?, building_id?}`; texts follow the prototype wording.

## 17. Open questions
1. Task 0 founder tests: the retry loop changes how many RNG draws founders consume, so any Task 0 test pinning founder 2..7 values at seed 42 needs updating. Proposed: update the expectations in the engineer's commit. (Needs Herby's go-ahead only if a Task 0 test is rewritten.)
2. Plan step 6 "asleep about a third" is replaced by 8..20%.
3. A birth cooldown of 1 sol is a mild brake (section 10.1); the first balance run will tell if it needs to be 2 or 3.

## Changelog
- 2026-10-03: first version (game-designer). Reviewer sign-off (step 2): pending.
