# Task 1 Plan: Life support and power (headless sim, balanced by runs)

Source of truth: station-zero-handoff/HANDOFF.md (sections 2, 5, 8, 9, 10). Design spec and tiebreaker: station-zero-handoff/prototype/station-zero-wip.html ("proto L<n>" below = line n). Task 0 is done; Task 2 is not started.
Rules in force: design before code, headless tests before visuals, tunables in data/, one seeded RNG (`SimRng`), one balance parameter per run, each step is a commit that runs.

## 1. Scope
Task 1 is the sim side only. `godot --headless` runs a colony for hundreds of sols with no sprites. Life support only means something if there are beings who breathe, buildings that make air, and builders who extend the colony, so the smallest slice is all of these, cut down to what feeds the life-support loop.

IN (sim/ and data/):
- Stocks: oxygen, food, ice (water), regolith; caps and targets that scale with population and green rooms.
- Buildings: reactor, habitat, workshop, green room, plus archive and comms as passive draw-only buildings (they matter to power and to the builders' choice). Tunnel graph between buildings. Online/offline (shorted) state.
- Power budget with shorts (newest 60%, else random) and re-online rule.
- Beings: needs (energy, suit air), state machine (idle inside, travel by tunnel, sleep, suit up, EVA, mine, build), persona effects limited to drive (speed, build, mine), steady (pauses, mine will), restless (travel chance) and room pull. Founders (7) with role retry, plus births (see A4).
- Construction: one site at a time, regolith cost, crew must be on site, builder choice from need (`chooseKind`).
- Resources: regolith pit, ice fields that run dry, scouting, spawn rules from the known-problems fixes.
- Suits: 36-hour tank, turn-back rule, EVA deaths. Footprints as sim data (position, time, heavy flag, fade 2.5 sols). Construction suit vs EVA suit and helmet lamp as sim flags: `suit_kind` and `lamp_on` (outside and night).
- Death with a recorded cause; colony log events as data (text list), no UI.
- `tests/balance_run.gd` and a balance log.

OUT (deferred, with owner task):
- Sprites, suit and lamp rendering, footprint rendering, door and light animation, interiors (Task 2).
- Conversations, thoughts text, packets, selection, inspector, building interior walking (Task 2 or 4; beings inside a building have no x,y in the sim, only a building id).
- God powers (Task 3+ except one hook: `power_multiplier_until` so the 1.5x Good fortune rule is testable), Grace, Inspire, Send a sign.
- Ages (Task 3), relationships (Task 4), council and domes (Task 5), emotions and AI minds (Task 6), dust storms, rovers.

Minimal view in Task 1 (view/ only reads the sim): extend view/main.tscn with a text HUD (sol, hour, stocks, power supply vs draw, offline buildings, population, last 5 log lines, speed keys). No sprites, no colored shapes. A debug dot map (buildings as rectangles, beings as dots, footprints as faded dots) is allowed as the last view step only if the tests and the balance protocol are already done; otherwise it moves to Task 2. Reason: the footprint, suit and lamp visuals depend on the sprite sheets that Task 2 imports.

## 2. Numbered steps (each a runnable commit)
Prefix: S = spec, T = tests first (failing allowed in the working tree, never committed red), I = implementation. Test command: `godot --headless --path station-zero --script res://tests/run_tests.gd`.
1. [game-designer] Write docs/specs/life-support-power.md with every rule below as formulas plus the data/*.json files in section 3 (colony, buildings, beings, suits, resources). Resolve section 5 in the spec. Check: every number in the spec appears in data/.
2. [code-reviewer] Read-only review of step 1 against the prototype lines cited (design reviewed before code). Findings go back to the designer. Check: reviewer signs off in the spec's changelog.
3. [sim-test-engineer, then godot-engineer] Colony stocks. Tests first: net rates with 1 green room and 7 beings (o2 +1.05/h, food +0.755/h), caps, clamping at 0, ice drain 0.07/h, warnings once per sol, death timer and cause (air 2 h, thirst 5 h, food 6 h, p 0.4), seeded determinism. Then sim/colony.gd. Check: tests pass, SimWorld.step() updates stocks.
4. [sim-test-engineer, then godot-engineer] Buildings and power. Tests first: supply 14 per reactor, draws (3,4,4,2,3), construction site 2, over-limit shorts exactly one non-reactor, newest 60% (statistical, seeded, 1,000 trials within 0.55..0.65), re-online needs draw + building draw <= 0.95 supply and 3 h since last short, offline building stops producing (green room) and stops sleeping/births (habitat), Good fortune multiplier 1.5 for 1 sol then expiry. Then sim/buildings.gd, sim/world.gd wiring. Check: tests pass.
5. [sim-test-engineer, then godot-engineer] Layout and resources. Tests first: findSpot never overlaps (rect margin 2, corridor margin 1), tunnel path BFS, door point = bottom center, ice and pit spawn stay clear (55 px from buildings, 90 px from other sites), every spawned ice field satisfies trip_time < 0.85 x tank at spawn (invariant, 500 seeds), dry-up triggers scouting, scouting keeps >= 2 reachable fields. Then sim/resources.gd and the layout part of buildings.gd. Check: tests pass.
6. [sim-test-engineer, then godot-engineer] Beings and energy. Tests first: drain per state (idle 1.3, EVA 2, mine 2.6, work 3 per hour), sleep gain 11/h (4/h without food), sleep triggers (<28; night and <65 at p 0.6), wake rule, nearest online habitat, sleep on the floor if none, exhausted turn-back at <12. Then sim/being.gd (state machine) with founders seeded in the 7-founder layout of A1. Check: tests pass; a 5-sol run with no EVA keeps all 7 alive and asleep about a third of the time.
7. [sim-test-engineer, then godot-engineer] Construction. Tests first: no crew means zero progress; progress per hour = sum((0.6+drive) x (0.55+energy/220)) / 34; cost 18 or 28 plus 4 per building; one site at a time; `chooseKind` order (reactor if margin < 5, green room if o2Net < 0.4 or foodNet < 0.25, habitat if pop+2 > 5 x habitats, else weighted random); the first build at seed 42 is a reactor (margin 3). Then construction in buildings.gd plus builder behavior in being.gd. Check: tests pass.
8. [sim-test-engineer, then godot-engineer] Suits, EVA, mining, footprints. Tests first: suit-up takes 1 colony oxygen and sets 36 h; a being dies at 0 air outside (cause `suffocated outside`); turn-back when air < distance/16 + 2.5; trip filter (2d/16 + 6 < 30.6); launch from the nearest online building door, reached by tunnel; mining yields (ice 6..10, regolith 8..14, times 0.7+0.6 drive, times 0.55+energy/220); fields shrink and dry up; footprints every 2.2 px of EVA movement, heavy for builders and haulers, expire after 2.5 sols, cap 2,200; `suit_kind` is construction for builders on a site, EVA otherwise; `lamp_on` only when outside and Mars hour in [21.5, 5.5). Then sim/resources.gd mining, being.gd EVA. Check: tests pass.
9. [sim-test-engineer, then godot-engineer] Births and founders. Tests first: birth gates (>= 2 beings in an online habitat, >= 1 if pop < 4; ice > 5, food > 15, oxygen > 20, nets > 0.1 and 0.05; pop < 5 x online habitats + 2), the new birth cooldown (A4), newborn persona from Mars chart at the building longitude, founder role retry (3 builders, 2 social, 1 curious, 1 tender). Then wire into SimWorld. Check: tests pass.
10. [sim-test-engineer] tests/balance_run.gd (section 4) plus a test that the same seed and sols give the identical output hash. Baseline run at seed 42, 30 and 300 sols, recorded in docs/balance/task-1-log.md. Check: runs headless, exits 0, under the time limit in section 4.
11. [sim-test-engineer, game-designer] Balance loop. One parameter per run, same seeds, record parameter, old and new value, and result in the log. Stop when section 4 targets hold on all seeds. Each accepted change is its own commit touching data/ only.
12. [godot-engineer] Text HUD in view/ (and the optional debug dot map). Check: `godot --headless --path station-zero --quit-after 5` clean; view contains no sim logic.
13. [code-reviewer] Read-only review against the spec and DoD; spot-check 5 mid-run numbers against a hand calc or a JS replica of the prototype with the same inputs; findings fixed as separate commits.
14. [project-manager] Check off Task 1 in HANDOFF.md section 8; record what changed and what we learned. Task 2 is not started until this is done.

## 3. Tunables (data/*.json; unit; start value; source)
Time unit is the Earth hour (h); step 0.05 h (data/sim.json). px = world pixel, tile T = 8 px.

colony.json
| Name | Unit | Start | Source |
| --- | --- | --- | --- |
| oxygen_start / food_start / ice_start / regolith_start | stock | 140 / 110 / 60 / 80 | proto L267, L272 |
| o2_per_green_room / food_per_green_room | per h | 1.4 / 1.0 | HANDOFF 5, proto L712-713 |
| o2_per_being / food_per_being / ice_per_being | per h | 0.05 / 0.035 / 0.01 | HANDOFF 5, proto L742 |
| o2_cap (base + per green room) | stock | 400 + 150 | proto L736 |
| food_cap (base + per green room) | stock | 300 + 120 | proto L737 |
| ice_target (min, per being) | stock | 120, 8 | proto L273 |
| regolith_target (base, per building) | stock | 160, 12 | proto L274 |
| death_interval air / ice / food | h | 2 / 5 / 6 | proto L821 |
| death_chance per interval | prob | 0.4 | proto L823 |
| warn_repeat; thirst_warn_repeat | h | 1 sol; 2 sols | proto L739-745 |
| birth_check_interval | h | 4 | proto L771 |
| birth_base; birth_warmth_coef | prob | 0.08; 0.14 | proto L779 |
| birth_min_beings (normal, pop < 4) | beings | 2, 1 | proto L777 |
| birth_gates ice, food, o2, o2Net, foodNet | stock, per h | >5, >15, >20, >0.1, >0.05 | proto L779 |
| habitat_capacity (per habitat, bonus) | beings | 5, +2 | HANDOFF 5, proto L773 |
| birth_cooldown (NEW) | h | 24.66 (1 sol) per habitat | A4, needs Herby |
| stock_days_floor (NEW, green room if food or o2 stock < N sols of use) | sols | 3 | known-problems fix, A5 |

buildings.json
| Name | Unit | Start | Source |
| --- | --- | --- | --- |
| reactor_supply | power | 14 | HANDOFF 5 |
| draw habitat / workshop / green room / archive / comms / reactor | power | 3 / 4 / 4 / 2 / 3 / 0 | HANDOFF 5, proto L705 |
| construction_site_draw | power | 2 | proto L710 |
| fortune_multiplier; fortune_duration | x; h | 1.5; 1 sol | HANDOFF 4, proto L709, L1719 |
| short_newest_chance | prob | 0.6 | HANDOFF 5, proto L726 |
| reonline_load_fraction; reonline_hold | frac; h | 0.95; 3 | proto L730 |
| build_check_interval | h | 5 | proto L789 |
| build_cost core or green room / other / per existing building | regolith | 18 / 28 / 4 | proto L794 |
| power_margin_for_reactor | power | 5 | proto L340 |
| o2net_floor / foodnet_floor for green room | per h | 0.4 / 0.25 | proto L341 |
| optional kinds pool; workshop cap | list; count | archive, comms, garden, habitat x2; 3 | proto L343-344 |
| building size tw, th; gap | tiles | 10..14, 8..10; 5..9 | proto L303 |
| start layout | tiles | core 12x10; habitat r 13x9 gap 7; workshop d 12x9 gap 6; green room l 12x9 gap 7 | proto L1800-1814 |
| construction_denominator; speed base; energy base and divisor | h; x; x | 34; 0.6 + drive; 0.55 + energy/220 | proto L806 |
| join_chance; builderish drive (normal, after idle 1 sol) | prob; trait | 0.55; >0.6, >0.35 | proto L460, L514 |
| shift_length | h | 8..16 | proto L499 |

beings.json
| Name | Unit | Start | Source |
| --- | --- | --- | --- |
| founder_roles; founder_homes | list | builder x3, social x2, curious, tender; habitat x4, reactor x2, workshop x1 | proto L1815-1818 |
| energy_start | energy | 70..100 | proto L375 |
| drain idle / eva / mining / work | per h | 1.3 / 2 / 2.6 / 3 | proto L402 |
| sleep_gain fed / starving | per h | 11 / 4 | proto L596 |
| sleep_below; night_sleep_below; night_sleep_chance | energy; energy; prob | 28; 65; 0.6 | HANDOFF 5, proto L509 |
| night window (Mars hour) | h | 21.5 to 5.5 | proto L382 |
| wake energy; day wake energy; day wake chance | energy; energy; per h | 97; 75; 0.3 | proto L597 |
| exhausted_turn_back | energy | 12 | proto L601 |
| decision_pause | h | (1..4) x (0.5 + 1.2 steady) | proto L697 |
| restless_travel | prob | 0.08 + 0.32 restless | proto L546 |
| room_pull weights (floor, exponent) | x | 0.15, 2 (drive workshop, curiosity archive, 0.8 curiosity comms, sociability habitat, care green room, 0.7 steady reactor) | proto L547-548 |
| walk speed to door; in building; drive factor | px/h | 16; 10; 0.75 + 0.5 drive | proto L699 |
| tunnel_speed | px/h | 22 | proto L666 |

suits.json
| Name | Unit | Start | Source |
| --- | --- | --- | --- |
| tank | h | 36 | HANDOFF 5, proto L706 |
| eva_speed | px/h | 16 | HANDOFF 5, proto L706 |
| suit_fill_colony_o2 | stock | 1 | proto L680 |
| return_margin | h | 2.5 | proto L611 |
| trip_filter (fraction of tank); trip_overhead | x; h | 0.85; 6 | proto L440-442 |
| work_move_speed construction / mining | px/h | 6 / 4 | proto L647, L661 |
| footprint_spacing; side_offset | px | 2.2; 0.7 | proto L578-582 |
| footprint_fade; footprint_cap | h; count | 2.5 sols; 2,200 | HANDOFF 5, proto L1086 |

resources.json
| Name | Unit | Start | Source |
| --- | --- | --- | --- |
| ice_field_amount; radius | stock; px | 260..420; 16..24 | proto L419 |
| spawn ranges ice / pit (from a building door); founders ice x2, pit x1 | px | 90..170 / 70..110; 90..150, 100..160, 70..110 | proto L1819-1821, L635 |
| spawn clearance building / other site / tunnel | px | 55 / 90 / 30 | proto L415-417 |
| spawn distance creep per try | px | 0.08 | proto L413 (see A2) |
| scout_chance when reachable fields < 2 | per h | 0.05 | proto L743-744 |
| mining shift length | h | 5..9 | proto L486 |
| yield ice / regolith | stock | 6..10 / 8..14 | proto L629 |
| yield factors | x | (0.7 + 0.6 drive) x (0.55 + energy/220) | proto L629 |
| partial load on turn-back | stock | 2..5 | proto L569 |
| mine_will weights steady / drive / restless | x | 0.45 / 0.35 / 0.2 | HANDOFF 3, proto L452 |
| mine_attempt (x will x (floor + (1-floor) x need)); floor; o2 gate | prob; x; stock | 0.4; 0.15; oxygen > 10 | proto L535 |
| want_ice rule: ice < 30, else (need+0.15)/(needs+0.3); stop mining above target x | stock; x | 30; 1.3 | proto L445-449 |

## 4. Balance protocol
Command: `godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed 42 --sols 300 [--param name=value]` (`--param` overrides one data/ value for that run only and prints it in the header).
Output: header (seed, sols, overrides, data hash), then a table every 30 sols: sol, pop, births, deaths by cause (air, thirst, hunger, suffocated outside, other), oxygen, food, ice, regolith, power supply, power draw, offline count, shorts since last row, buildings by kind, reachable ice fields, mining trips, average energy, share asleep. Last line: PASS or FAIL against the targets below.
Runtime target: 300 sols under 90 s on the dev machine; if over, step 10 owner reports it and we agree a coarser balance step (decision for Herby) rather than silently changing fixed_step.

Seeds: 42 (default), 7, 99, 1234, 2026. Two sizes: 30 sols (every commit) and 300 sols (balance steps and DoD).

Targets for "balanced" (proposed; game-designer confirms in step 1):
1. Survival: 7 founders, 300 sols, all five seeds: at least 5 beings alive at every row and population never reaches 0.
2. Deaths only with a clear cause in the log. No death with oxygen, ice and food all above 0 and no EVA. EVA deaths at most 1 per 100 sols per seed.
3. No runaway growth: population at sol 30 <= 15, sol 100 <= 30, sol 300 <= 60; never above 5 x online habitats + 2; the first birth no earlier than sol 2; at most 1 birth per habitat per cooldown.
4. Stocks bounded: oxygen, food and ice stay above 0 in every row after sol 5 on all seeds; ice stays above 20 after sol 30 (the thirst failure of the prototype); ice and regolith below 3 x target.
5. Power: draw <= supply in at least 90% of rows; no more than 2 shorts per sol; no building offline for more than 1 sol except under an explicit test override; at least 1 reactor built by sol 10 (first-build rule).
6. Growth is limited by something: at least one of regolith, builders on site or ice trips is the binding constraint at some point (shown by a "waiting for builders" or "need regolith" log count > 0). If population tracks capacity with no waiting, tighten the birth cooldown (one parameter).
7. Mining always reachable: every trip passes the tank check; zero EVA turn-backs caused by an unreachable site; at least 2 reachable ice fields in 95% of the 30-sol checkpoints.
8. Energy: average energy between 40 and 90 on every row; at most 25% asleep at any row; no being sleeps more than 18 h in one go.
9. Determinism: the same seed and sols give a byte-identical table.
Order of tuning knobs (one per run): birth_cooldown, birth_base, ice_per_being, scout_chance, mine_attempt, reactor margin, stock_days_floor. Record each run in docs/balance/task-1-log.md.

## 5. Ambiguities and recommended resolutions (prototype is the tiebreaker)
- A1 Founder layout. HANDOFF says 7 founders; the prototype places 4 in the habitat, 2 in the reactor, 1 in the workshop with role retry. Resolve: copy the prototype (needs the retry loop deferred from Task 0).
- A2 Ice spawn vs suit range (known problem). Prototype spawns 90..170 px from a door and adds 0.08 px per try (up to 32 px), and the 170 + 32 px worst case exceeds the 0.85 x tank round trip (max 196.8 px). Resolve: clamp spawn distance so trip_time < trip_filter x tank always; derive max range from suits.json; add the invariant test; spawn from a door of an online building, not any building.
- A3 Launch building. Mining launches from the nearest online building door (known-problems fix, proto L437); miners walk tunnels to it first. If no path (shorted building in the way), cancel the intent. Resolve: as prototype; test it.
- A4 Births and runaway growth. Prototype births (per habitat per 4 h, p about 0.08 + 0.14 x warmth, so up to 1 per 20 h) only stop at capacity, and capacity follows pop + 2 > 5 x habitats, so growth is limited only by construction. Resolve: keep the prototype formula and add a per-habitat cooldown tunable (1 sol) as the first balance knob. Needs Herby (see below).
- A5 Stock targets scale with population (known problem). Ice and regolith targets already do; oxygen and food use fixed caps and fixed net thresholds. Resolve: keep the prototype nets, add `stock_days_floor` (green room when oxygen or food would last under 3 sols at current use).
- A6 Death model. Prototype kills a random inside being with p 0.4 every 2, 5 or 6 hours of shortage (a colony dies within a few sols of thirst). Resolve: keep it; log the cause by priority air, then thirst, then hunger; the balance target is that shortage never persists, not softer deaths. EVA deaths use `suffocated outside`.
- A7 Power flapping. After a short, a building can come back online and trip again (0.95 limit, 3 h hold). Resolve: keep; target 5 caps shorts at 2 per sol; if it fails, raise hold time (one parameter).
- A8 Suit oxygen cost. A fill costs 1 colony oxygen, while a tank holds 36 h x 0.05 = 1.8. Resolve: keep 1 (prototype); the value is a tunable.
- A9 Beings inside buildings. Prototype walks beings around room interiors; the sim keeps only building id and a pause timer (no x,y until EVA). Behavior numbers stay; interior positions go to Task 2. Footprints and EVA paths use real x,y.
- A10 Suit and lamp visuals. Sim exposes flags (`suit_kind`, `lamp_on`); the view draws them in Task 2. Lamp rule: outside and Mars hour in [21.5, 5.5) (prototype night).
- A11 RNG. Prototype uses Math.random in call order. Resolve: all draws through `SimRng`, iteration in stable id order, no `randomize()`; the determinism test guards it.
- A12 Persona use. Only drive, steady, restless, role and room pull are used; curiosity and care effects (archive, comms, green room pull) are included only as pull weights.
- A13 Offline rules. Offline green room makes nothing; offline habitat has no bunks, no births; offline workshop means no planning (`builderReady` needs online workshop); offline building draws 0.

## 6. Definition of done
Tests and runs:
- `godot --headless --path station-zero --script res://tests/run_tests.gd` exits 0 with all Task 0 tests (33) plus the new Task 1 tests passing; no test passes with zero checks; output is identical on two runs.
- `tests/balance_run.gd` at seeds 42, 7, 99, 1234, 2026 for 300 sols prints PASS on all targets in section 4, within the runtime limit, with identical output on repeat.
- docs/balance/task-1-log.md lists baseline and every one-parameter run with the result.
Files that must exist:
- docs/specs/life-support-power.md, docs/tasks/task-1-plan.md, docs/balance/task-1-log.md.
- data/{colony,buildings,beings,suits,resources}.json; sim/{colony,buildings,being,resources}.gd with real logic (placeholders replaced), sim/world.gd wiring; tests/{test_colony,test_power,test_layout,test_beings,test_construction,test_suits,test_births,test_determinism}.gd and tests/balance_run.gd.
- view/ text HUD only reads the sim.
Reviewer (code-reviewer) checks:
- No tunable number in sim/*.gd; no Node or draw API in sim/; no `randi`/`randf` outside `SimRng`; view has no logic.
- Every rule in the spec has a test; spot-check of 5 numbers against the prototype.
- Known-problems fixes present and tested: ice spawn within suit range (A2), launch from nearest online building (A3), continued scouting, population-scaled targets (A5), sim and view separate.
- HANDOFF.md section 8 updated: Task 1 checked off with what changed and what we learned. Task 2 not started.

## Owner decisions (Herby, 2026-10-03)
- Births: in Task 1. Keep the prototype formula and add a per-habitat cooldown of 1 sol (A4). The cooldown is the first balance knob.
- Deaths: prototype pace (p = 0.4 per check, cause logged by priority air > thirst > hunger) (A6).
- View: text HUD. The debug dot map is optional, only after the tests and balance targets pass.
- Runtime: keep `fixed_step` at 0.05 h for balance runs, even if a 300-sol run takes minutes.
- Balance targets: the PM's proposals stand until the game-designer confirms or adjusts them in step 1.
