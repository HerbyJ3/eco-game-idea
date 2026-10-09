# Spec: life support, power, beings, construction, suits (Task 1)

Lifecycle update: [lifecycle.md](lifecycle.md) supersedes immediate births with nine calendar months of pregnancy and restricts conception and outside work to adults. The original birth-gate and cooldown rules remain inputs to conception. Historical balance results below predate this change.

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
| sim/powers.gd (`Powers`) | god-power hooks. In Task 1 only `set_power_multiplier(until_t)` and the field `power_multiplier_until`; it calls `Buildings.clear_short_hold()` (sets `last_short_t` to the sentinel). `Buildings` reads the multiplier when computing supply. Grace, Inspire and signs land here in Task 3+ |
| sim/world.gd (`SimWorld`) | owns all of the above, `step()` order (section 5), `stats`, `log`, founders; `world.founders[i].persona` stays (tests/test_smoke.gd reads it) |
Data access follows `SimData` (Task 0). No tunable number in `sim/*.gd`.

### Test seams the engineer must provide (design requirement)
- `SimWorld.new(seed, options)` where `options.blank = true` creates an empty world (no founders, no layout, no sites, stocks from `colony.start`) so tests build exactly the state they need by direct field writes and calls such as "add building of kind at tile, built 1", "add being of persona and role in building", "add ice field at x,y".
- Every field in section 4 is readable and writable by tests. `step()` advances exactly one fixed step.
- `SimWorld.stats` (counters, section 16) and `SimWorld.log` (list of dictionaries) are plain data.

## 3. Conventions
- Time unit is the Earth hour (h). One step is `fixed_step_hours` = 0.05 h (`data/sim.json`). A sol is `sol_hours` = 24.6597 h. Name suffixes: `_h` hours, `_sols` sols (multiply by `sol_hours`), `_px` world pixels, `_px_h` pixels per hour. Tile = `tile_px` = 8 px.
- `t` is the world clock (hours since epoch, as in Task 0). Mars clock hour = `Clock.mars_hour(t)` in [0, 24). **Night** = clock hour >= 21.5 or < 5.5 (`beings.night`).
- Float slack: `STEP_EPS` = 1e-9, the existing constant in sim/world.gd. Two comparator forms only:
  - **Interval timers** (birth check 4 h, build check 5 h, death interval 2/5/6 h) are accumulators: `acc += dt`, fire when `acc >= h - STEP_EPS`, then `acc = 0`. They fire on the 80th, 100th and 40th/100th/120th step.
  - **Elapsed-since timers** (re-online hold, warning repeats, birth cooldown, "site idle for a sol", footprint age, `wait_h <= STEP_EPS` for decisions) use `elapsed > h + STEP_EPS`. The 3 h hold passes on the 61st step after the short (3.05 h); a sol-long warning repeat passes on the 494th step (a sol is 493.19 steps).
  - Deviation from the prototype, which uses strict `>` on accumulators (L771, L790, L821): our interval timers fire one step earlier (4.00 h not 4.05 h, 5.00 h not 5.05 h, death intervals 2.00/5.00/6.00 h). Reason: exact, float-independent step counts that tests can assert.
- "Sol" for targets, stats and logs = elapsed sols since `start_hour`: `floor((t - start_hour) / sol_hours)`, with sol 0 as the first sol. A sol boundary is the first step with `t - start_hour >= n x sol_hours - STEP_EPS`. (`Clock.sol` in Task 0 is 1-based; log entries carry both.)
- Ids: buildings and beings each count from 1 in creation order; iteration is always ascending id. Building order at start: reactor 1, habitat 2, workshop 3, green room 4.
- Randomness: only `SimRng` (`randf`, `randf_range`, `randi_range`, `chance`, `pick`). No `randomize()`. Draw order is the order written in this spec. Short-circuit conditions draw only when everything before them is true (stated where it matters). Prototype draws that only fed text (thought pick) are dropped.
- Persona: a being keeps the `Persona.persona_from` dictionary from Task 0, whose shape is `{traits, role, description}`. `persona.traits.drive` (and curiosity, sociability, care, restless, steady) are in [0, 1]; `persona.role` is `builder`, `social`, `curious` or `tender`. Only drive, steady, restless, role and the room-pull traits are read (A12). The chart is never read outside creation. Wherever this spec writes `drive`, `steady` etc. it means `persona.traits.<name>`.
- Founder count: `persona.json founders.count` (7) is the single source; `beings.founders.layout` must have exactly that many entries (a test asserts it).
- Kind ids: `reactor` (proto `core`), `habitat`, `workshop`, `green_room` (proto `garden`), `archive`, `comms`.

## 4. State
### Colony (`Colony`)
`oxygen`, `food`, `ice`, `regolith` (floats); `air_warn_t`, `food_warn_t`, `thirst_warn_t`, `regolith_warn_t`, `waiting_warn_t` (all start at -1e9); `death_timer_h` (0); `birth_timer_h` (0); `last_birth_t` per habitat id (absent = never); `extinct` (bool).
Derived each use (never stored): `pop` (count of living beings), `green_rooms` (online green rooms), `o2_net = green_rooms x 1.4 - pop x 0.05`, `food_net = green_rooms x 1.0 - pop x 0.035`, `o2_cap`, `food_cap`, `ice_target = max(120, 8 x pop)`, `regolith_target = 160 + 12 x (all buildings incl. site)`.
### Building
`id`, `kind`, `tx`, `ty`, `tw`, `th` (tiles), `built` (0..1; 1 = finished), `offline` (bool), `offline_since` (t when it went offline, else null; feeds `max_offline_h`), `corridor` (to parent: `parent_id`, `p1`, `p2` in px, `len` px, `rect` in tiles). `door` = bottom centre = `((tx + tw/2) x 8, (ty + th) x 8)`.
### Power
`Buildings.last_short_t` (-1e9 sentinel), `Powers.power_multiplier_until` (-1e9 sentinel). Shorts counters live in `stats` (section 16).
### Construction site
At most one: `building_id`, `parent_id`, `last_work_t`, derived `crew` (beings in state `work` with this job).
### Being
`id`, `name`, `persona`, `role`, `earth_born`, `born_t`, `energy` (0..100), `state` in {`idle`, `to_door`, `transit`, `sleep`, `eva`, `work`, `mining`}, `building_id` (the building it is in, or the one it left from while `transit`/outside; no x,y inside), `wait_h`, `sleep_intent` (bool), `suit_up` (bool), `job` (the site or null), `mine` (`site`, `door`, `home_id`, or null), `mine_intent` (site or null), `air_h` (null unless outside), `x`, `y`, `heading` (only outside, else null), `path` (waypoints), `after` in {null, `mine`, `work`, `haul`, `enter`}, `returning` (bool), `load` (0), `work_left_h`, `step_acc_px`, `foot_side` (+1), `corridor_id`, `transit_t` (0..1), `from_a` (bool), `sleep_started_t` (t when the current sleep began, else null; feeds `max_sleep_h`).
Task 3 adds two fields recorded at birth (state only, no behaviour, no RNG draw; see `docs/specs/ages.md` section 3): `parent_id` (the being that `rng.pick(here)` returns; 0 for founders, test-seam beings, or an empty pick) and `birth_building_id` (the habitat id).
Derived flags for the view: `suit_kind` = `none` while inside; `construction` when outside with a `job` (state `work`, or `eva` going to or from the site); `eva` for any other outside state. `lamp_on` = outside and night.
### Resources
`ice_fields`: `x`, `y`, `amount`, `start`, `dug`, `r`. `pit`s: `x`, `y`, `dug`, `r` (amount infinite). `footprints`: `x`, `y`, `heading`, `t`, `heavy`.
### World
`log` (list, newest last, capped at `colony.log_cap` = 500; stats never depend on the log), `stats` (section 16), `step_index`.

## 5. Order of operations within one fixed step (0.05 h)
1. `t += dt`; `step_index += 1`. (Task 0 clock.)
2. **Stocks.** `oxygen = clamp(oxygen + o2_net x dt, 0, o2_cap)`; `food = clamp(food + food_net x dt, 0, food_cap)`. Uses `pop` and online green rooms as they stood at the end of the previous step.
3. **Power.** `manage_power()` (section 7.2): at most one short, or at most one re-online, per step.
4. **Air and food warnings**: logged on the first step with `t - warn_t > 1 sol + STEP_EPS` while the stock is 0 (so the first line is at once, the next 494 steps later).
5. **Ice.** `ice = max(0, ice - pop x 0.01 x dt)`. Scouting (section 8.4). Thirst warning (same rule, 2 sols, while ice is 0).
6. **Beings.** Each living being alive at the start of the phase, ascending id, runs `update_being(dt)` (section 6.3). A being that dies outside is removed immediately and the loop goes on with the next id. No being is created in this phase (births are phase 7).
7. **Births.** Every 4 h (section 10.1).
8. **Build decision.** Every 5 h (section 7.4).
9. **Construction progress** (section 7.5), then the `waiting_for_builders` warning (site with no crew for more than 1 sol; repeat 1 sol).
10. **Shortage deaths** (section 9).
11. **Footprint expiry** (drop prints older than 2.5 sols), `extinct` update, **stats sampling** (section 16).
Energy read by a phase: phase 6 drains energy first, so phases 7 to 11 and any yield computed in phase 6 read the energy **after** this step's drain (the prototype also drains before it reads, L600 then L629).
The `to_door`/`transit` arrivals and EVA arrivals happen inside phase 6, so a being that finishes a tunnel walk is idle in the new building for the rest of the step.

## 6. Beings (per-being energy, state machine, persona effects)
### 6.1 Energy
- Start energy: uniform 70..100 (draw `randf_range`).
- Drain per hour while awake, by state: `idle`, `to_door`, `transit` 1.3; `eva` 2; `mining` 2.6; `work` 3. `sleep` does not drain. Energy clamps to [0, 100]. Zero energy has no effect by itself (no death from energy).
- Sleep gain per hour: 11 while `colony.food > 0`, else 4.
- **Go to sleep** (checked at the top of `decide`): `sleep_intent`, or energy < 28, or (night and energy < 65 and `chance(0.6)`). The `chance` is drawn only when night and energy < 65.
- `go_sleep`: nearest online habitat H by distance between building centres from the **current building's centre** (deviation: the prototype measures from the being's x,y inside the room, L385; the sim has no interior x,y; tie: lowest id). If none, or H is the current building: state `sleep` at once (on the floor if none; same gain). Otherwise next hop by BFS toward H; `sleep_intent = true`; state `to_door`. If no hop exists, sleep on the floor. Entering state `sleep` always sets `sleep_intent = false` (L391, L396). Likewise `start_mining` clears `mine_intent` and `suit_up`, and finishing suit-up clears `suit_up`.
- **Wake** while asleep: after gaining, if energy >= 97, or (not night and energy > 75 and `chance(0.3 x dt)`), state `idle`, `wait_h` = `idle_wait()`. The `chance` is drawn only when it is not night and energy > 75 (and energy < 97).
- **Exhausted turn-back**: outside, energy < 12, not `returning`, and state is `mining`, `work`, or `eva` with `after` `mine` or `work`: `turn_back("exhausted")`.
### 6.2 Interior timing (A9)
Inside a building the sim keeps no x,y. Walks inside are timers.
- `idle_wait()` = walk + pause, where walk = U(10, 56) px / (10 x (0.75 + 0.5 drive)) h, pause = U(1, 4) x (0.5 + 1.2 steady) h. A being entering a building, waking, or choosing to stay put gets `wait_h = idle_wait()`. A being whose `sleep_intent` is set on arrival gets `wait_h` = one step. A new being gets `wait_h` = U(0, 2).
- `to_door` time = U(10, 56) px / (16 x (0.75 + 0.5 drive)) h. When it elapses the door action runs, chosen in this order: (a) `suit_up` with a `mine`: 6.5 miner suit-up at the building door; (b) `suit_up` with a `job`: 6.5 builder suit-up at the corridor end `p1` of the site; (c) otherwise the being enters the tunnel `corridor_id` (set by whoever chose the hop: restless travel, sleep, join-construction hop, mine-intent hop): state `transit`, `transit_t = 0`, `from_a` = (the corridor's `a` end is the current building).
- `wait_h` counts down by dt in `idle`; when `wait_h <= STEP_EPS` the being calls `decide`.
### 6.3 `update_being(dt)` order
1. `sleep`: gain, wake check, done for this step.
2. Awake drain.
3. Exhausted turn-back check (6.1).
4. If outside: `air_h -= dt`. If `air_h <= 0`: the being dies (cause `suffocated outside`), is removed, logged, stats updated, return. Else if not `returning`, state is `mining`, `work` or `eva` with `after` `mine`/`work`, and `air_h < dist(position, home_door)/16 + 2.5`: `turn_back("low air")` (log at most once per 3 h per being).
5. State handling:
   - `eva`: if `path` is empty run `finish_eva` and stop. Else let d = distance to `path[0]`. If d < 0.8 px (`waypoint_reach_px`) pop the waypoint, run `finish_eva` if the path is now empty, and stop for this step (no movement). Otherwise move toward `path[0]` by min(16 x dt, d) px and leave footprints (8.5). (Prototype order L618-622.)
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
### 6.5b `finish_eva` and `enter` (what happens when an EVA path ends)
`enter(building)`: `returning = false`, `air_h = null`, `job = null`, `path = null`, `x = y = heading = null`, `building_id = building`, state `idle`, `wait_h = idle_wait()`. (The suit is simply off; the tank is not returned to the colony.)
`finish_eva` acts on `after`:
| `after` | Action |
| --- | --- |
| `mine` | state `mining`, `work_left_h = U(5, 9)`, `wait_h = 0`, wander target = the current position (so the first wander target is drawn on the next mining update). |
| `haul` | add `load` to `ice` (field kind ice) or `regolith` (pit); `load = 0`; `home = mine.home_id`; `mine = null`; then `enter(home)`. |
| `work` | if a site exists and it is this being's `job`: state `work`, `work_left_h = U(8, 16)`, `wait_h = 0`, work-point target (7.5). Else `enter(job.building_id if that building is finished, else the parent building)`. |
| `enter` | `enter(building_id)` (the parent building for builders). |
| null | `enter(building_id)`. |
"Site gone" while a being is in state `work` (site cleared or `job` is not the current site) is handled at once, in the same update, the same way as the `work` row's else branch (prototype L651, L501), not by walking anywhere.
### 6.6 Persona effects (A12)
drive: walk factor `0.75 + 0.5 drive`, construction rate `(0.6 + drive)`, mining yield factor `(0.7 + 0.6 drive)`. steady: pause length factor `0.5 + 1.2 steady`, mine will 0.45. restless: travel chance, mine will 0.2. Role `builder` marks builderish. Room pull uses drive, curiosity, sociability, care, steady as weights only.
### Tests (tests/test_beings.gd)
- EVA arrival table (6.5b): one test per `after` value: `mine` starts mining with `work_left_h` in 5..9; `haul` adds the load to the right stock, nulls `mine`, and the being is idle in `mine.home_id`; `work` with a live site starts work, with a cleared site enters the finished building (or the parent when unfinished) the same step; `enter` and null reset `returning`, `air_h`, `job`, `path`; `to_door` with no `suit_up` enters the tunnel `corridor_id`.
- Drain: from energy 80, one hour (20 steps) in each state: idle 78.7, eva 78.0, mining 77.4, work 77.0 (tolerance 1e-6); `sleep` from 20 for 1 h gives 31 with food, 24 with food 0.
- Sleep length: from 20 to wake at 97: 77/11 = 7.0 h fed (140 steps +-1), 77/4 = 19.25 h starving.
- Triggers: energy 27.9 sleeps; 28.0 awake in daytime; 64 at night with a seeded RNG sleeps in a 0.6 fraction of 2,000 trials (0.55..0.65); 65 at night never rolls.
- Wake: not night, energy 80: wakes with probability 0.015 per step (1,000 sleepers, one step: 5..30 wake); energy 74 never wakes by day; night never wakes before 97.
- Nearest online habitat: two habitats, the nearer one shorted: picks the farther online one; none online: sleeps on the floor at once; tie goes to the lower id.
- Exhausted: a `work` being at energy 12.01 drains below 12 (input 12.1: after one step of work drain 0.15 it reads 11.95) and gets `returning` with a path home; `air_h` keeps falling 0.05 per step as always and no colony oxygen is spent.
- 5-sol run, no EVA permitted (mining chance forced to 0 by data override, no site): all 7 alive, asleep share between 8% and 20% (hand calc: 1.3 x 24.6597 / 11 = 2.9 h/sol = 11.8%). **The plan said "about a third"; that is wrong for idle drain, see section 13.**
- Persona: a drive 1.0 being walks to a door in 0.6 of the time of a drive 0 being (speed factors 1.25 vs 0.75); the mean pause over 2,000 draws equals 2.5 x (0.5 + 1.2 steady) within 5% (steady 1.0 gives 4.25 h, steady 0 gives 1.25 h).

## 7. Buildings, power, construction
### 7.1 Kinds and draws
Reactor supplies 14 (draw 0). Habitat 3, workshop 4, green room 4, archive 2, comms 3. A construction site draws 2 while `built < 1`. A finished online building draws its kind draw; an offline one draws 0. **Online** = built >= 1 and not offline.
`supply = (finished reactors) x 14 x (1.5 if t < power_multiplier_until else 1)`. `draw = sum of the above`. `margin = supply - draw`.
### 7.2 `manage_power()` (once per step)
- If `draw > supply`: candidates = online non-reactor buildings. If any: `target = newest (highest id)` when `chance(0.6)`, else `rng.pick(candidates)`; (the pick draws only on the failed chance). The target goes `offline = true`, `offline_since = t`; `last_short_t = t`; log `short`; `stats.shorts += 1`. Exactly one building per step; reactors never short. No candidates: nothing happens.
- Else: for offline finished buildings in ascending id, the first one with `draw + its kind draw <= 0.95 x supply` and `t - last_short_t > 3 h + STEP_EPS` goes online (log `back_online`; `offline_since = null`), then stop. The hold applies to every building (global last short). When a building goes offline set `offline_since = t`.
- **Hook** `Powers.set_power_multiplier(until_t)` (sim/powers.gd): sets `power_multiplier_until = until_t` and calls `Buildings.clear_short_hold()` (`last_short_t = -1e9`). This is the only god-power code in Task 1.
- `demand()` (read-only helper for stats and the balance run) = the draw computed as if no finished building were offline, plus site draw.
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
Work state (builder on site): `work_left_h = U(8, 16)` on arrival; wanders between random points at 6 px/h pausing U(0.8, 2.4) h (the wait counts down, then a new point is drawn when the current one is reached within 0.8 px); when `work_left_h` reaches 0, path [`p2`, `p1`], `after = enter`, `job = null` (the being then enters the parent building). If the site disappears: handled as in 6.5b ("site gone" enters at once).
Work points and the EVA arrival point (deviation from L1338, which keeps y near the rising wall seam for art): a uniform random point inside the building rectangle inset 5 px (`work_point_inset_px`) on every side. The seam is a view concern (Task 2).
Waiting (phase 9): if a site has had no crew for more than 1 sol (`t - last_work_t > 1 sol + STEP_EPS`), log `waiting_for_builders`, repeat after 1 sol.
### Tests (tests/test_power.gd, tests/test_construction.gd)
- Supply/draw: 1 reactor + habitat + workshop + green room = draw 11, supply 14, margin 3. Add a site: draw 13. Add archive and comms on top of the site: draw 18 > 14 (16 without the site), one non-reactor goes dark per step until draw <= 14.
- Over-limit shorts exactly one non-reactor building per step, never a reactor, never a site; with no candidates nothing happens.
- Newest-vs-random (corrected): P(newest) = 0.6 + 0.4/n. With n = 10 candidates and 1,000 seeded trials the newest fraction is in 0.60..0.68 (expected 0.64); with n = 4 it is in 0.65..0.75 (expected 0.70).
- Re-online: an offline habitat (draw 3) with draw 8, supply 14: 8 + 3 = 11 <= 13.3 and hold passed -> online; at draw 11 (11 + 3 = 14 > 13.3) -> stays offline; at 60 steps after a short -> stays offline, at 61 -> online; ascending id order with two offline; only one re-online per step.
- Offline effects: an offline green room adds 0 to `green_rooms` (nets drop to -0.35 and -0.245 with 7 beings); an offline habitat is not chosen by `go_sleep` and gives no births; an offline workshop makes `ready` false; an offline building draws 0.
- Fortune hook: `Powers.set_power_multiplier(t + 24.6597)` (also resets the 3 h hold): supply 28 -> 42 (2 reactors), a dark building returns on the next step if load fits; after one sol supply returns to 28 and the building may short again.
- Cost: reactor/green room 18 + 4 x n, others 28 + 4 x n; the first build at seed 42 with founders is a reactor (margin 3), cost 34, regolith 46.
- No crew: 1,000 steps with no `work` beings give progress 0. Progress reads energy **after** the phase 6 drain (work drains 3 x 0.05 = 0.15 per step). So the test sets energy 80.15 before the step; phase 9 then reads exactly 80. One builder, drive 0.7: rate = 1.3 x (0.55 + 80/220) / 34 = 1.187727 / 34 = 0.0349332 per h, **0.00174666 per step (compute the expected value from the formula in the test, tolerance 1e-12; the rounded literal is off by about 2e-9)**. Three such builders triple it.
- One site at a time: a second `start` while a site exists returns false and changes nothing.
- `choose_kind` order: margin 4 returns reactor even when o2_net is 0.1; margin 5 and o2_net 0.39 returns green room; `oxygen = 25, pop = 7` (floor 3 x 24.6597 x 0.05 x 7 = 25.89; food floor 18.12) returns green room even with nets fine; pop 9 with 1 habitat returns habitat; otherwise only kinds from the pool, workshop only below 3.
- Build timing: the check fires on steps 100, 200, ... (`acc >= 5 - STEP_EPS`; the prototype's strict `>` would fire on 101); no check draws RNG when no builder is ready. `waiting_for_builders`: a site with no crew logs on the first step with `t - last_work_t > 1 sol + STEP_EPS` (step 494) and again 494 steps later.
- Layout (tests/test_layout.gd): the founder rects, doors and corridors above exactly; door = bottom centre for 100 random rects; `find_spot` over 500 seeds with 20 sites each never overlaps (margin 2) nor crosses a corridor (margin 1); BFS returns the shortest corridor chain on a hand-made 5-node graph and none when disconnected; unfinished corridors are not traversed.

## 8. Resources, scouting, mining
### 8.1 Spawn (A2 fixed)
`spawn_site(kind, range)`: up to 400 tries; each draws `pick(online buildings)` (anchor), angle U(0, 2pi), distance U(range) + 0.08 x try. Position = anchor door + distance x (cos, sin). Accept only if: at least 55 px from every building rectangle; more than 90 px from every other field or pit; outside every corridor rect inflated by 30 px; **and** `trip_time(candidate) = 2 x (d_launch + r)/16 + 6 < 0.85 x 36` where `d_launch` is the distance to the door of the nearest online building (so `d_launch + r < 196.8` px). A rejected candidate is simply retried. No online building: no spawn. Ice field: amount U(260, 420), r U(16, 24). Pit: r 9, infinite.
Founders: pit range 70..110, ice ranges 90..150 and 100..160 (spawn order pit, ice, ice), anchors the four founding buildings.
### 8.2 Choosing a site (`choose_site`)
Live sites = pits, plus ice fields with amount > 0, whose `trip_time(from nearest online door) < 30.6`. `ice_need = 1 - min(1, ice/ice_target)`, `reg_need = 1 - min(1, regolith/regolith_target)`. Want ice if `ice < 30` or (ice fields exist and `chance((ice_need + 0.15)/(ice_need + reg_need + 0.3))`; the draw only when ice >= 30 and ice fields exist). Pool = ice fields if wanted and any, else pits if any, else ice fields. Return none when the pool is empty, or the pool is pits and `regolith > 1.3 x regolith_target`, or ice and `ice > 1.3 x ice_target`. Else `rng.pick(pool)`.
`launch_for(site)` = the online building whose door is nearest to the site (tie: lowest id); none if no building is online.
### 8.3 Mining
- After suit-up and EVA to the arrival point: state `mining`, `work_left_h = U(5, 9)`; wander inside the field (target = centre + angle x r x U(0.2, 0.8), y x 0.7) at 4 px/h, footprints on. While `wait_h > 0` it counts down; else the being moves toward the target; when within `resources.mining.reach_px` (0.6 px, L646) it draws `wait_h = U(0.6, 2)` and a new target (draw order: wait, angle, radius).
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
- **Worst-case air margin** (target 7). A miner's farthest point from the door is the field centre distance d plus up to 0.8 r (wander). The spawn rule gives d + r < 196.8, so d + 0.8 r < 196.8 - 0.2 r, at most 193.6 px (r = 16, the worst case). Air use: out 193.6/16 = 12.1 h + shift 9 h + back 12.1 h + return margin 2.5 h = 35.7 h against a 36 h tank, so the margin at the end of the longest shift is **about 0.3 h** (0.5 h for r = 24 at d = 172.8, where d + 0.8r = 192). Any loosening of `trip_filter` (0.9 gives d up to about 187 px and a turn-back at the end of a 9 h shift), `trip_overhead_h`, `mining.shift_h` max or `return_margin_h`, or a wider wander radius, makes air turn-backs possible and breaks target 7: change them only together with this calculation.
- Footprints: every outside move (EVA, mining wander, construction wander) adds `moved` to `step_acc_px`; when `step_acc_px >= 2.2 - STEP_EPS`: reset to 0 (not subtract, L581), flip `foot_side`, add a print at the position offset 0.7 px perpendicular to the heading on that side; `heavy = job != null or load > 0`; oldest dropped past 2,200; prints older than 2.5 sols (61.649 h) are removed in phase 11. (Deviation: the prototype left prints only for EVA and mining; builders shuffling at the site now leave heavy prints too, matching HANDOFF "every suited being".)
### Tests (tests/test_eva.gd, tests/test_layout.gd)
- Suit-up: oxygen 100 -> 99, `air_h = 36`; at oxygen 0.4 it clamps to 0 and the tank is still 36.
- Death: a being outside with `air_h = 0.04` after one step (-0.05) is at -0.01 and dies, cause `suffocated outside`, removed, `stats.deaths.suffocated_outside = 1`, log line.
- Turn-back: a miner 160 px from the door turns back when `air_h < 160/16 + 2.5 = 12.5`, not at 12.6; walking home needs 10 h, arriving with >= 2.5 h; builder returns by [`p1`, inside], not via `p2`.
- Filter: a field 196 px from the nearest online door with r 16 fails (2 x 212/16 + 6 = 32.5); 170 px with r 24 passes (2 x 194/16 + 6 = 30.25 < 30.6).
- Spawn invariant (500 seeds x 40 spawns each over a growing hand-made colony): every spawned field has `trip_time < 30.6`, is >= 55 px from every building, > 90 px from every other site, outside corridors + 30 px; a spawn with no online building returns none.
- Launch: with the nearest building offline, `launch_for` returns the next nearest online one; the miner walks tunnels to it before suit-up; no online building -> intent cancelled and no oxygen spent.
- Yield (read after the phase 6 drain; mining drains 2.6 x 0.05 = 0.13 per step, so the test sets energy 80.13 and the yield reads exactly 80): drive 0.5, energy 80: factor 1.0 x (0.55 + 80/220) = 0.913636; ice yield in 5.4818..9.1364 (tolerance 1e-3 on the band ends); regolith 7.3091..12.7909; ice never goes below 0 in the field; a dry field is removed, logged once, and a new one appears when reachable < 2.
- Scouting: reachable 1: the chance is 0.05 x 0.05 = 0.0025 per step, so over 2,000 steps (100 h) the fraction of 500 seeds that spawn at least once is 1 - e^-5 = 0.993 (0.97..1.0); reachable 2: no spawns in 2,000 steps; after a field dries with 2 others live, no extra spawn; scouting continues after the pit has been dug (pits do not matter).
- Footprints (step sizes: EVA 16 px/h x 0.05 = 0.8 px per step; mining 4 px/h = 0.2; work 6 px/h = 0.3). Because the accumulator resets to 0: EVA prints every 3rd step (0.8, 1.6, 2.4), so 30 straight steps (24 px) leave exactly 10 prints and 20 steps (16 px) leave 6; work every 8th step (2.4), so 40 steps leave 5; mining every 11th step (2.2 reached, which is why `STEP_EPS` is in the comparator), so 55 steps leave 5. Sides alternate +-0.7 px perpendicular to the heading; heavy only for a being with a job or a load; the 2,201st print removes the oldest; a print aged 61.7 h (> 61.649 + STEP_EPS) is gone after phase 11, one aged 61.6 h stays.
- Flags: `suit_kind` is `none` inside, `construction` for a builder with a job outside, `eva` for a miner; `lamp_on` true at Mars hour 21.5, 23, 2, 5.4; false at 5.5, 12, 21.4 and always false inside.
- Mining chance: 10,000 decide calls with will 0.5, need_max 1 and oxygen 100 produce a mining intent in 0.4 x 0.5 x 1 = 0.2 +-0.02; with oxygen 10 none.

## 9. Colony stocks, life support, death
### 9.1 Stocks (phase 2 and 5)
Starting stocks: oxygen 140, food 110, ice 60, regolith 80. Green room +1.4 oxygen and +1.0 food per hour (online only). Per being per hour: oxygen 0.05, food 0.035, ice 0.01. Caps: oxygen 400 + 150 per online green room, food 300 + 120 per online green room (stocks only drop to the cap when a green room goes offline, by clamping on the next step). Ice and regolith have no cap (mining stops by the 1.3 x target rule).
Warnings: while oxygen is 0, `air_low` is logged on the first step with `t - air_warn_t > 1 sol + STEP_EPS` (sentinel -1e9, so at once, then every 494 steps); food 0, `food_empty` the same; ice 0, `water_dry` with 2 sols. `regolith_warn_t` and `waiting_warn_t` follow the same rule.
### 9.2 Death by shortage (phase 10)
If pop > 0 and (oxygen <= 0 or food <= 0 or ice <= 0): `death_timer_h += dt`; interval = 2 h if oxygen <= 0, else 5 h if ice <= 0, else 6 h. When `death_timer_h >= interval - STEP_EPS` (step 40, 100 or 120; the prototype's strict `>` would take one more step): reset to 0; `chance(0.4)`; if it succeeds, the victim = `rng.pick` among beings that are inside (not `transit`, `eva`, `work`, `mining`; sleepers included), or among all beings if none is inside. Cause by priority air, then thirst, then hunger. Else the timer resets to 0 every step. (Owner decision: prototype pace, A6.)
### 9.3 Death causes (recorded on the log and `stats.deaths`)
`air` ("died when the air ran out"), `thirst` ("died of thirst"), `hunger` ("starved"), `suffocated outside` ("ran out of air on the surface"). Every death: `{t, sol, being_id, name, cause}` in the log and in `stats.deaths_list`. No other cause exists in Task 1; `stats.deaths.other` must stay 0.
### Tests (tests/test_colony.gd)
- 1 green room, 7 beings: `o2_net` 1.05, `food_net` 0.755 per h (1e-9); one sol of steps moves oxygen by 1.05 x 24.6597 = 25.89 and food by 18.62 (stocks well under caps).
- No green room: nets -0.35 and -0.245; offline green room the same.
- Caps: 0 green rooms o2 400 / food 300; 1: 550 / 420; 3: 850 / 660. Stock above the new cap is clamped when a green room goes offline.
- Clamp: oxygen 0.01 with net -0.35 stays 0, never negative; same for food and ice.
- Ice drain: 7 beings 0.07 per h (1.726 per sol); pop 0 no drain; ice target `max(120, 8 pop)`: 120 at 7 and at 15, 160 at 20; regolith target 160 + 12 x 5 = 220 with 5 buildings.
- Warnings: oxygen held at 0 for 2.5 sols (1,233 steps) produces exactly 3 `air_low` lines, on steps 1, 495 and 989 (each next line is the first step where `t - warn_t > 1 sol + STEP_EPS`, 494 steps later); thirst 1 per 2 sols (every 987 steps).
- Death timer: the check fires on step 40 (air), step 100 (thirst) and step 120 (hunger) after the shortage starts (accumulator `>= h - STEP_EPS`). Oxygen 0, 7 beings, 400 seeded runs of 20 h (400 steps): 10 checks each, deaths average 10 x 0.4 = 4 (3.5..4.5); only the air interval is used even if food is also 0; ice 0 only: interval 5; food 0 only: interval 6; any shortage ending resets the timer to 0.
- Cause priority: oxygen 0 and ice 0 together -> cause `air`; ice 0 and food 0 -> `thirst`; victims never include beings in `transit` or outside while an inside being exists; a colony with all beings outside picks among all.
- Extinction: 0 beings: no deaths, no births, `extinct = true`, one log line, the sim keeps stepping.
- Determinism seeds: two worlds at seed 42 stepped 5,000 steps have equal stocks, log and beings; seed 43 differs.

## 10. Births and founders
### 10.1 Birth check (every 4 h, phase 7)
Habitats in ascending id; each re-evaluates with the live population. For a finished habitat H: `here` = beings inside H (sleepers included, not `transit`/outside). `need = 1 if pop < 4 else 2`. `warmth = mean over here of (sociability + care)` (1 if none, avoided by `need`). A birth happens if all hold: H online; `|here| >= need`; ice > 5; food > 15; oxygen > 20; `o2_net > 0.1`; `food_net > 0.05`; `pop < 5 x (online habitats) + 2`; **cooldown** `t - last_birth_t[H] > 1 sol + STEP_EPS` (new, A4; a habitat that has never had a birth is free); and `chance(0.08 + 0.14 x warmth)` (drawn only when everything before holds). Then the parent is `rng.pick(here)`, the newborn is created in H (name, persona from `MarsSky.mars_chart` at the building's longitude `lon_of_tile(tx + tw/2)`, energy U(70,100), `wait_h` U(0,2), `earth_born = false`), `last_birth_t[H] = t`, log `born`. Invariant counters at the moment of birth: if the population before the birth was >= `5 x online habitats + 2`, `stats.births_at_capacity += 1`; if the habitat had a birth within the last sol (`t - previous <= 1 sol`), `stats.cooldown_violations += 1`. Both must stay 0 (the gates make them unreachable; the counters prove it in long runs).
Expected effect of the cooldown: with warmth about 0.9 the chance is p = 0.08 + 0.14 x 0.9 = 0.206 per 4 h check. Without a cooldown the mean interval per habitat is 4/p = 19.4 h (0.79 sol). With it, the first allowed check is 28 h after a birth (checks sit on a 4 h grid and 24.66 h expires between the 6th and 7th), then a geometric wait of (1 - p)/p x 4 = 15.4 h: mean about 28 + 15.4 = 43.4 h = 1.76 sols, a 2.2x brake on births per habitat (not a cap; capacity and construction still limit growth). It is the first balance knob.
### 10.2 Founders (A1)
Seven Earth-born founders, created in layout order (`beings.founders.layout`): habitat x4 (builder, builder, social, curious), reactor x2 (tender, social), workshop x1 (builder). Each founder is `MarsSky.founder_birth(rng, cfg)` (Task 0 draw: age 24..45 years, longitude -120..140), persona from it; if the role does not match, redraw the whole `founder_birth` up to 300 times (ages stay within 24..45; the prototype let age run to 60), keep the last if none match and count `stats.founder_role_miss`. Name = syllable A + syllable B + "-" + number 1..99. Energy U(70,100), `wait_h` U(0,2). Creation order (and so RNG order): **layout, founders in layout order, then sites (pit, ice, ice)**. The log starts with `founders_landed`.
### Tests (tests/test_births.gd)
- Gate matrix: starting from a state that passes, break each gate once (online, `|here|`, ice 5, food 15, oxygen 20, nets 0.1 and 0.05, capacity, cooldown); no birth in any broken case over 500 checks; with all gates passing and warmth 0.9 the birth rate per check is 0.206 +-0.03 (1,000 seeded checks).
- `need`: pop 3 and one being in H gives births possible; pop 4 and one being gives none; two beings give births.
- Capacity: 1 habitat: no birth at pop 7 (cap 7), allowed at 6; 2 habitats online: cap 12; one offline: cap 7.
- Cooldown: after a birth, the same habitat cannot birth for 24.6597 h (checks at +4, +8, ..., +24 blocked; +28 allowed); another habitat is unaffected.
- Newborn: persona from `mars_chart` at `lon_of_tile` of the building (compare to a direct call), `earth_born` false, id next in sequence, is inside H.
- Founders: seed 42 gives exactly 3 builders, 2 social, 1 curious, 1 tender in the layout homes; 200 seeds never leave a mismatched role; `len(beings.founders.layout) == persona.founders.count`; `world.founders[i].persona` still exists and is equal for equal seeds (tests/test_smoke.gd). No Task 0 test pins founder values, so none changes.
- First birth at seed 42: expected no earlier than sol 2 (pop 7 equals capacity 7 until a second habitat is built); this is measured by target 3 (`first_birth_sol`), not asserted as a rule.

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
Further decisions: timers with `STEP_EPS` (section 3); builder return path fix; builders' footprints; `choose_kind` only when ready; ice field removed on dry-up; shortage victims as prototype; `waiting_for_builders` log (new, feeds target 6).
### Deviations from the prototype (all declared)
1. Interval timers fire when `acc >= h - STEP_EPS` instead of strict `>` (one step earlier): birth L771, build L790, death L821.
2. `go_sleep` measures distance from the current building's centre, not the being's interior x,y (L385), because beings have no interior position.
3. Construction work points and the EVA arrival point on a site are uniform in the footprint inset 5 px, not near the rising-wall seam (L1338); the seam is art.
4. Mining wander reach 0.6 px is now data (`resources.mining.reach_px`); all other waypoint arrival uses `suits.waypoint_reach_px` 0.8.
5. Builder turn-back goes straight home (not via `p2`); builders leave footprints while working; ice fields leave the list when dry; spawns are rejected by the trip rule (A2); scouting counts reachable fields; interiors are timers (A9); `choose_kind` runs only when a builder is ready; no thought-text RNG draws.

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
| kinds.*.label | text | Reactor, Habitat, Workshop, Green room, Archive, Comms | HANDOFF 5 |
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
| founders.layout | list | habitat: builder, builder, social, curious; reactor: tender, social; workshop: builder (length must equal `persona.json founders.count` = 7, the single count) | proto L1815-1818 |
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
| mining.reach_px | px | 0.6 | proto L646 |
| mine_will.steady / drive / restless | x | 0.45 / 0.35 / 0.2 | HANDOFF 3, proto L452 |
| mine_attempt.chance / floor / o2_gate | x / x / stock | 0.4 / 0.15 / 10 | proto L535 |
| want.ice_urgent_below / ice_bias / need_sum_bias | stock / x / x | 30 / 0.15 / 0.3 | proto L445 |
| want.stop_factor | x target | 1.3 | proto L448-449 |
Not data (hard rules): the cause priority air > thirst > hunger, 4 directions of `find_spot`, ascending id order, the `-1e9` sentinels, `STEP_EPS`.

### Key-path list (machine-readable; one leaf per line)
A test parses this block (lines between the `keys:` fence markers) and checks **both ways**: every listed path exists in the loaded JSON file, and every leaf of those five files (objects recursed, arrays and scalars are leaves) is listed. `*` is expanded for the six building kinds and the six room-pull rooms.
```keys:
colony.start.oxygen
colony.start.food
colony.start.ice
colony.start.regolith
colony.production.o2_per_green_room
colony.production.food_per_green_room
colony.consumption.o2_per_being
colony.consumption.food_per_being
colony.consumption.ice_per_being
colony.caps.o2_base
colony.caps.o2_per_green_room
colony.caps.food_base
colony.caps.food_per_green_room
colony.targets.ice_min
colony.targets.ice_per_being
colony.targets.regolith_base
colony.targets.regolith_per_building
colony.death.air_interval_h
colony.death.thirst_interval_h
colony.death.hunger_interval_h
colony.death.chance
colony.warnings.air_food_repeat_sols
colony.warnings.thirst_repeat_sols
colony.warnings.regolith_repeat_sols
colony.warnings.waiting_repeat_sols
colony.birth.check_interval_h
colony.birth.base_chance
colony.birth.warmth_coef
colony.birth.min_beings
colony.birth.min_beings_small_colony
colony.birth.small_colony_below
colony.birth.gate_ice_above
colony.birth.gate_food_above
colony.birth.gate_oxygen_above
colony.birth.gate_o2_net_above
colony.birth.gate_food_net_above
colony.birth.habitat_capacity
colony.birth.capacity_bonus
colony.birth.cooldown_sols
colony.stock_days_floor_sols
colony.log_cap
buildings.tile_px
buildings.kinds.*.label
buildings.kinds.*.draw
buildings.reactor_supply
buildings.site_draw
buildings.fortune.multiplier
buildings.fortune.duration_sols
buildings.short.newest_chance
buildings.reonline.load_fraction
buildings.reonline.hold_h
buildings.build.check_interval_h
buildings.build.cost_reactor
buildings.build.cost_green_room
buildings.build.cost_other
buildings.build.cost_per_building
buildings.build.waiting_site_idle_sols
buildings.choose.reactor_margin
buildings.choose.o2_net_floor
buildings.choose.food_net_floor
buildings.choose.crowd_margin
buildings.choose.pool
buildings.choose.workshop_cap
buildings.size.tw
buildings.size.th
buildings.size.gap
buildings.find_spot.tries
buildings.find_spot.overlap_margin_tiles
buildings.find_spot.corridor_margin_tiles
buildings.find_spot.corridor_width_tiles
buildings.construction.denominator_h
buildings.construction.drive_base
buildings.construction.join_chance
buildings.construction.builderish_drive
buildings.construction.builderish_drive_idle
buildings.construction.shift_h
buildings.construction.wander_wait_h
buildings.construction.work_point_inset_px
buildings.layout.core
buildings.layout.attached
beings.founders.layout
beings.founders.role_retry_tries
beings.names.syllables_a
beings.names.syllables_b
beings.names.number
beings.energy.start
beings.energy.max
beings.energy.drain_idle
beings.energy.drain_eva
beings.energy.drain_mining
beings.energy.drain_work
beings.energy.sleep_gain_fed
beings.energy.sleep_gain_starving
beings.energy.sleep_below
beings.energy.night_sleep_below
beings.energy.night_sleep_chance
beings.energy.wake_at
beings.energy.day_wake_above
beings.energy.day_wake_chance_per_h
beings.energy.exhausted_turn_back
beings.effort.energy_base
beings.effort.energy_divisor
beings.night.start_hour
beings.night.end_hour
beings.pause.base_h
beings.pause.steady_base
beings.pause.steady_coef
beings.initial_wait_h
beings.restless.travel_base
beings.restless.travel_coef
beings.room_pull.floor
beings.room_pull.exponent
beings.room_pull.weights.*
beings.walk.door_px_h
beings.walk.interior_px_h
beings.walk.drive_base
beings.walk.drive_coef
beings.walk.interior_walk_px
beings.tunnel_speed_px_h
suits.tank_h
suits.eva_speed_px_h
suits.fill_colony_o2
suits.return_margin_h
suits.trip_filter
suits.trip_overhead_h
suits.work_speed_construction_px_h
suits.work_speed_mining_px_h
suits.waypoint_reach_px
suits.low_air_log_repeat_h
suits.footprint.spacing_px
suits.footprint.side_offset_px
suits.footprint.fade_sols
suits.footprint.cap
resources.ice_field.amount
resources.ice_field.radius_px
resources.pit.radius_px
resources.spawn.ice_px
resources.spawn.pit_px
resources.spawn.founder_ice_px
resources.spawn.founder_pit_px
resources.spawn.tries
resources.spawn.creep_px_per_try
resources.spawn.clearance_building_px
resources.spawn.clearance_site_px
resources.spawn.clearance_tunnel_px
resources.scout.chance_per_h
resources.scout.min_reachable
resources.mining.shift_h
resources.mining.yield_ice
resources.mining.yield_regolith
resources.mining.drive_base
resources.mining.drive_coef
resources.mining.partial_load
resources.mining.arrive_radius_frac
resources.mining.wander_radius_frac
resources.mining.wander_y_scale
resources.mining.reach_px
resources.mining.wander_wait_h
resources.mine_will.steady
resources.mine_will.drive
resources.mine_will.restless
resources.mine_attempt.chance
resources.mine_attempt.floor
resources.mine_attempt.o2_gate
resources.want.ice_urgent_below
resources.want.ice_bias
resources.want.need_sum_bias
resources.want.stop_factor
```
(The room-pull weights are objects `{trait, mult}`, so the leaf test treats `beings.room_pull.weights.<room>` as a leaf, like `buildings.layout.core` and `attached`. The room-pull `*` expands to workshop, archive, comms, habitat, green_room, reactor.)

## 13. Balance targets (confirmed or adjusted)
Balance run table: as in the plan section 4, plus the measured columns named in the table after the targets (all taken from `stats`, section 16). Rows every 30 elapsed sols. "Sol" is elapsed sols since `start_hour` (section 3).
| # | Target | Verdict and reason |
| --- | --- | --- |
| 1 | 7 founders, 300 sols, five seeds (42, 7, 99, 1234, 2026): >= 5 alive at every row, never 0 | Confirmed. The death model is harsh (p 0.4 per interval), so this is only reachable when no shortage persists. |
| 2 | Every death has a cause in the log; no shortage death while oxygen, ice, food are all above 0; **EVA deaths = 0** (plan: <= 1 per 100 sols) | Adjusted. The sim has no random outdoor hazard and the turn-back margin (2.5 h) plus spawn invariant guarantee return, so any EVA death is a bug. `stats.deaths.other` = 0. |
| 3 | Pop at sol 30 <= 15, sol 100 <= 30, sol 300 <= 60; first birth no earlier than sol 2; **no birth is ever made at pop >= 5 x online habitats + 2 and at most 1 birth per habitat per cooldown** | Adjusted wording. Population may exceed capacity after a habitat shorts (nobody is removed), so the cap is on the birth, not on pop. The sol-2 floor is expected, not guaranteed: pop 7 equals capacity 7 until a second habitat is built, which should take more than a sol; it is measured (`first_birth_sol`) and the target fails if it is wrong. 60 beings needs about 12 habitats and 3 green rooms (one per about 20 beings with the 0.4 net floor), which is a big but possible build for 300 sols. |
| 4 | Oxygen, food, ice > 0 **at every step (window minima) after sol 5**; ice > 20 after sol 30; ice and regolith < 3 x target | Adjusted: rows alone could miss a dip. Mining stops at 1.3 x target, so 3 x is generous. |
| 5 | Draw <= supply in >= 90% of rows; <= 2 shorts per sol; no building offline > 1 sol; a reactor built by sol 10 | Adjusted: after `manage_power` draw <= supply almost always, so "draw" is meaningless. Use `demand` = the draw if no building were offline; demand <= supply in >= 90% of sim steps (`1 - demand_over_steps / steps`), not rows. Shorts per sol and offline duration are tracked as maxima. |
| 6 | Growth is limited by something, measured in hours not events: `(hours_waiting_regolith + hours_site_no_crew) / total hours >= 2%` on at least 4 of 5 seeds, and `site_busy_h / total hours` is reported. | Adjusted. A bare "log count > 0" is nearly tautological (the second build already waits for regolith, 46 left vs 48 needed). `hours_waiting_regolith` adds 5 h for every build check where a builder was ready and regolith < cost; `hours_site_no_crew` adds dt for every step a site exists with no crew. **The 2% starting threshold (about 6 sols per 300) is provisional**: the game-designer recalibrates it from the baseline run and records the new value in the balance log before the first balance change. If growth never waits, tighten `birth.cooldown_sols`. |
| 7 | Mining reachable: zero `turn_backs_air` (the invariant makes them unnecessary); >= 2 reachable ice fields on >= 95% of **sol boundaries** (plan: 30-sol checkpoints, only 10 samples) | Adjusted sampling. The worst-case air margin is thin (about 0.3 to 0.5 h, section 8.5), so this target is what detects a loosened trip filter or longer shifts. |
| 8 | Average energy 40..90 on every row; **time-averaged asleep share per window between 5% and 30%** (plan: <= 25% at any row); no sleep stretch > 18 h | Adjusted. Idle 11.8% asleep; busy builders (3 per h for 8-16 h) can push it to about 25%, so 25% at a snapshot is too tight; the window average is the right measure. The 18 h limit only holds while food > 0 (a fed sleep from 0 to 97 takes 8.8 h; starving takes up to 24 h). |
| 9 | Same seed and sols give a byte-identical table (incl. data hash and `String.sha256_text` of the table body) | Confirmed. |
| 10 | Ages (Task 3): first Settlement in sols 40 to 150, at most 4 age changes, gaps of at least the dwell, history complete | Defined in `docs/specs/ages.md` section 12 and 19.2; the table gains a trailing `age` column (L or S). |
### How each target is measured (section 16 has the stats keys)
Every window figure below comes from `stats.window` (reset by the balance run after printing each row); run figures from `stats` itself. Nothing is read from the log, which is capped.
| Target | Measured by |
| --- | --- |
| 1 | `pop_by_sol` (population at each sol boundary), `min_pop` per window |
| 2 | `deaths` by cause, `deaths_list`, count of deaths with `oxygen`, `ice`, `food` all > 0 and the dead being inside (`deaths_unexplained`, must be 0) |
| 3 | `pop_by_sol[30]`, `[100]`, `[300]`; `first_birth_sol`; `births_at_capacity`; `cooldown_violations` |
| 4 | `min_oxygen`, `min_food`, `min_ice` (updated each step once elapsed sols >= 5), `min_ice_after30` (elapsed sols >= 30), `max_ice_over_target`, `max_regolith_over_target` (ratio to target) |
| 5 | `demand` at each row (via `Buildings.demand()`); `max_shorts_per_sol` (shorts counted in the current sol, max kept); `max_offline_h` (from `Building.offline_since`); `first_new_reactor_sol` (elapsed sol when the first non-founder reactor was finished, null if none) |
| 6 | `hours_waiting_regolith`, `hours_site_no_crew`, `site_busy_h` |
| 7 | `turn_backs_air`; `reachable_ok_samples / sol_samples` (reachable ice >= 2, sampled at each sol boundary) |
| 8 | `energy_sum / being_steps` (average energy), `asleep_being_steps / being_steps` (asleep share), `max_sleep_h` (longest completed or current sleep, checked each step while asleep) |
| 9 | the table text and its `String.sha256_text` |
Knob order unchanged: `birth.cooldown_sols`, `birth.base_chance`, `consumption.ice_per_being`, `scout.chance_per_h`, `mine_attempt.chance`, `choose.reactor_margin`, `stock_days_floor_sols`. One change per run, same seeds. Note: the cooldown is a 2.2x brake on births per habitat (section 10.1), not a cap; if growth still tracks capacity, the first knob may need to go to 2 or 3 sols (a decision for Herby at that point).
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
- Check "every number appears in data": the key-path test below, plus asserts that the reactor supply, draws, tank and cost values equal the spec's.
- No sim file contains a tunable literal other than 0, 1, 2, the `-1e9` sentinels and `STEP_EPS` (reviewer step 13).
- Key-path parity: the `keys:` block in section 12 equals the leaf set of the five JSON files (both directions); `len(beings.founders.layout) == persona.founders.count`.

## 16. Stats keys (`SimWorld.stats`)
Counters are never derived from the log (it is capped at 500). `stats` holds run-wide values; `stats.window` holds the same measured fields for the current balance row and is cleared by `stats.reset_window()` (called by `balance_run` after each row; the run-wide copy is never reset). Windowed fields: every `min_*`, `max_*`, sum and counter field. Never windowed: `pop_by_sol` and the `first_*_sol` fields. Before sol 5, `min_oxygen`, `min_food` and `min_ice` are null and print as `-`; before sol 30 the same applies to `min_ice_after30`.
Event counters: `births`, `deaths` {air, thirst, hunger, suffocated_outside, other}, `deaths_list`, `deaths_unexplained` (death by shortage while oxygen, ice and food were all above 0, or `other`), `shorts`, `reonlines`, `mining_trips` (counted at suit-up for mining), `turn_backs_air`, `turn_backs_exhausted`, `builds_started`, `builds_finished`, `need_regolith`, `waiting_for_builders`, `ice_dry`, `scouts_found`, `founder_role_miss`, `births_at_capacity`, `cooldown_violations`.
Measured fields (all "sol" = elapsed sol, section 3), updated in phase 11 unless stated:
| Field | Definition |
| --- | --- |
| `pop_by_sol` | list; one entry appended at each sol boundary (index = elapsed sol) |
| `min_pop` | minimum population over the steps of the window |
| `first_birth_sol` | elapsed sol of the first birth (null if none) |
| `first_new_reactor_sol` | elapsed sol when the first reactor after the founding one was finished (null if none; kept as a stat because `log_cap` evicts log entries) |
| `min_oxygen`, `min_food`, `min_ice` | minimum stock over steps at elapsed sol >= 5 |
| `min_ice_after30` | minimum ice over steps at elapsed sol >= 30 |
| `max_ice_over_target`, `max_regolith_over_target` | maximum of stock / target over all steps |
| `shorts_this_sol`, `max_shorts_per_sol` | shorts since the last sol boundary (reset at each boundary); maximum value reached |
| `max_offline_h` | maximum over steps of `t - offline_since` across offline buildings (and the final value for buildings that came back) |
| `max_sleep_h` | maximum of `t - sleep_started_t` over sleeping beings, checked every step |
| `being_steps`, `asleep_being_steps`, `energy_sum` | per step: living beings; of them asleep; sum of their energy. Average energy = `energy_sum / being_steps`; asleep share = `asleep_being_steps / being_steps` |
| `demand_over_steps`, `step_count` | steps where `Buildings.demand() > supply`; total steps (the balance row also prints `demand` and `supply` at the row) |
| `sol_samples`, `reachable_ok_samples` | at each sol boundary: samples taken; samples with at least 2 reachable ice fields |
| `hours_waiting_regolith` | +5 h (the check interval) at each build check where a builder was ready and regolith < cost |
| `hours_site_no_crew` | +dt each step a site exists with no crew |
| `site_busy_h` | +dt each step a site exists |
Task 3 stats keys (run-wide, never windowed; defined in `docs/specs/ages.md` section 8.2): `age`, `age_changes`, `sols_in_age`, `first_settlement_sol`, `age_history`.
Log kinds: `age_began` (Task 3; extra fields `age`, `how`, `cause`; see `docs/specs/ages.md` section 8.1), `founders_landed`, `ground_broken`, `building_done`, `short`, `back_online`, `born`, `died`, `air_low`, `food_empty`, `water_dry`, `need_regolith`, `waiting_for_builders`, `suit_low_air`, `ice_dry`, `ice_found`, `scouts_found`, `colony_silent`. Each entry `{t, sol, kind, text, being_id?, building_id?}`; texts follow the prototype wording.

## 17. Open questions
1. (Closed.) The founder retry changes RNG consumption but no Task 0 test pins founder values (only `world.founders[i].persona` equality per seed is tested), so nothing in Task 0 changes.
2. Plan step 6 "asleep about a third" is replaced by 8..20%.
3. A birth cooldown of 1 sol is a 2.2x brake per habitat (section 10.1), not a cap; the first balance run will tell if it needs to be 2 or 3 sols (Herby decides).
4. Target 6's 2% threshold is provisional and is recalibrated from the baseline run.

## Implementation notes (step 4)
- `shorts_this_sol` resets right after `t += dt` on a sol-boundary step, before phase 3, so a short on the boundary step counts in the new sol.
- `max_offline_h` folds in `t - offline_since` at the moment a building comes back online, so the final dark spell (for example 3.05 h) is kept even though phase 11 already sees the building online.
- `Buildings.now` is pushed in by SimWorld whenever `t` changes, and `Powers` holds Buildings through a WeakRef. Neither may hold a strong reference back to the world, or every SimWorld leaks.

## Implementation notes (step 5)
- Blank test worlds have `scouting_enabled = false`; founder worlds have it on. A blank world is a test seam, and scouting would otherwise draw rng every step in power tests with no ice fields.
- The dry-up replacement spawn uses the scouting range (90 to 170 px).
- Centring rounds half up: `floor(x + 0.5)`.
- "Within 2 tiles" means separation of at least 2. The founder corridor rects are (12,4,7,3), (5,10,3,6) and (-7,4,7,3).
- The spawn invariant test uses 500 seeds x 20 spawns, not 40, to keep it near 2.5 s.
- Scouting does not guarantee 2 reachable fields at every moment. That is measured statistically by balance target 7, not asserted per step.

## Implementation notes (step 6)
- Sleep and wake thresholds are compared **after** this step's phase 6 drain, as for every other energy read. Test inputs sit off the boundary accordingly: 28.06 and 28.07, and 65.1.
- The starving-sleep "77/4 = 19.25 h" case cannot happen, because by day a sleeper above 75 may wake. The test is 70 to 97 at night: 6.75 h, 135 steps.
- The 5-sol no-EVA unit test accepts an asleep share of 6 to 20%. The equilibrium is about 1.3/12.3 = 10.6%, the hand calc of 11.8% was high, and the stub measured 9.3 to 9.5%. Balance target 8 (window share 5 to 30%) is unchanged.
- A corridor's "a" end is `p1`, the parent side. `from_a = true` means walking from the parent to the child.
- `add_being` (the test seam) leaves `wait_h` at 0 and a flat 0.5 persona. Founders get `wait_h` U(0, 2).

## Implementation notes (step 7)
- API names: `SimWorld.start_site(kind, spot = {}) -> bool`, `SimWorld.choose_kind() -> String`, `Buildings.site` (null or the site record; a being's `job` is that record), `Buildings.build_cost(kind)`, `Being.suit_kind()`.
- The `food_net < 0.25` rule in `choose_kind` stays as a guard, as in the prototype. With the shipped numbers the `o2_net` rule always fires first, so a test lowers food production to reach it.
- The suit is chosen at suit-up and kept until the being enters a building. A builder walking home after a shift still wears the construction suit, even though `job` is already null. Store it on the being (for example `suit`), and have `suit_kind()` return it while outside.
- `stats.need_regolith` and `stats.waiting_for_builders` count logged lines. `hours_waiting_regolith` adds the check interval (5 h) at every failed check.
- A new worker's first wander target is its current position, so it begins with a pause, as in mining. This is intended.
- The job is set when a builder joins from the parent building. A builder heading to the parent from elsewhere has no job yet.

## Implementation notes (step 8)
- **Heavy footprints:** `heavy = construction suit on, or load > 0`. A builder in the construction suit leaves heavy prints on the whole trip, including the walk home with `job == null`. This is consistent with the step 7 rule that the suit stays on until the builder enters.
- **Partial load on turn-back:** the load is taken from the field, and `field.amount` drops by the load, so ice is never free. If that empties the field, the usual dry-up rule applies.
- **Site kind:** every Site has a `kind` (`ice` or `pit`). A hauler deposits by `mine.site.kind`, so a load from a field that dried is still ice.
- **Turn-back logs:** an air turn-back logs `suit_low_air` and an exhausted turn-back logs `exhausted`, each once per turn-back. The 3 h repeat interval can never fire, because `returning` blocks a second turn-back. It is kept only as a guard.
- **Turn-back path:** a builder's path is `[p1]`, then `enter(parent)` on arrival. A miner's path is `[mine.door]`, then `haul` (with a load) or `enter`. `mine` is null once the miner is home.
- **Boundaries:** lamp boundaries are tested at ±1e-6. Air on arrival after a turn-back is 2.45 to 2.5 h (step granularity).
- **Trip filter:** the formula is the spec's, 2(d + r)/16 + 6. The plan's "2d/16 + 6" was shorthand.
- **Mining wander:** checks the distance to its target before moving (prototype L646).
- **choose_site:** lives on SimWorld, because it reads colony stocks and the rng.

## Owner decisions after the baseline (2026-10-03)
These override the section 13 targets where they differ:
- **Target 3:** no population caps. It checks births at capacity = 0, cooldown violations = 0 and first birth no earlier than sol 2. Population is reported only.
- **Target 4:** min oxygen and min food must stay above 0, and ice and regolith must stay below 3 x target. Ice running dry is reported as pressure, not failed.
- **Target 5:** the first new reactor is due by sol 15.

## Final review follow-ups (step 13)
- Log entries and `deaths_list` carry both `sol` (elapsed since landing, 0-based, used by stats) and `clock_sol` (`Clock.sol_index`, 1-based, rolls at Mars midnight). The HUD shows `clock_sol`, so the log matches the clock.
- A resumed mine intent re-applies the trip filter and cancels if the launch door moved too far.
- `Site.dug` accumulates everything dug from the site, including partial loads.
- `balance_run.gd` exits 1 when any target fails.
- Exempt from the literal rule: the measurement windows `STATS_FROM_SOL` (5) and `STATS_ICE_FROM_SOL` (30) in world.gd. They define what the targets measure, not how the colony behaves.
- The suit, EVA, mining and footprint tests live in `tests/test_eva.gd`.

## Changelog
- 2026-10-03: first version (game-designer).
- 2026-10-03: revision after code-reviewer findings. Added: EVA arrival table and `finish_eva`/`enter` (6.5b), `to_door` corridor choice, "site gone" enters at once; footprint and construction-rate and yield test arithmetic fixed (step sizes, energy read after drain); explicit timer comparators with `STEP_EPS` and declared deviation from strict `>`; measurable balance stats and sol definition (section 16, 13); cooldown arithmetic corrected (about 43 h, 1.76 sols, 2.2x); sol-2 claim softened; target 6 measured in hours; worst-case air margin with the d + 0.8r bound; wording fixes (phase 6, exhausted test, wake chance draw, EVA move order); declared deviations list (go_sleep distance, work points, build timer, mining reach key `resources.mining.reach_px`); `kinds.*.label` row and machine-readable key-path list; single founder count; persona shape `{traits, role, description}`; Task 0 coupling note dropped; `sim/powers.gd` added to the code map; warning cadence (494th step) and waiting warning moved to phase 9. Reviewer sign-off (step 2): pending re-review.
- Reviewer sign-off (step 2): approved after re-review, 2026-10-03. The six remaining nits were applied: test tolerance, intent flags cleared, `job.building_id`, windowed fields, null minima before sol 5, and target 5 measured per step.
