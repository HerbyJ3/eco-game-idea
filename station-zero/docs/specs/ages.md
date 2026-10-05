# Spec: ages (Task 3): Landing and Settlement, announced in the log

Source of truth: HANDOFF.md sections 1, 2, 7, 9, 10. Plan and final owner decisions (Herby, 2026-10-05): `docs/tasks/task-3-plan.md`. Sim facts read: `docs/specs/life-support-power.md` (sections 3, 4, 5, 9, 16); balance facts: `docs/balance/task-1-log.md`.
Locked decisions respected: influence-only god (the age is not a lever and no god power reads or writes it), ages not meters (no progress value exists anywhere; the sample window is private), per-being energy (not read), power as a budget (a short is read as a fact about the past sol, never as a death).
Tunables live in `data/ages.json` (new) and `data/sim.json` (one new key). No tunable number appears in `sim/ages.gd`. This spec describes behaviour and numbers only, no code.
Plan numbers that changed: regression is allowed (owner), so the latch is replaced by hysteresis (section 6); the sample hook moves from inside `_sol_boundary` to the end of the step (section 4).

## 1. Purpose
Name what the people already did. Each sol the colony is looked at once and the result is `ok` or `not ok`. A long stretch of mostly `ok` sols, ending in `ok` sols, with the first Mars-born generation alive, is called Settlement. A long stretch of mostly `not ok` sols sends the colony back to Landing. Both changes are announced in the log in words. Nothing counts toward the next age on screen, and nothing about the colony changes because of the age (announce only; owner).

## 2. Ages for Task 3
| id | Display name | Life is about (HANDOFF 7) | Entered by |
| --- | --- | --- | --- |
| `landing` | Landing | survival: air, food, water, power | world creation; or falling back from Settlement (section 6) |
| `settlement` | Settlement | families, routines | the entry rule (section 5) |

Council, Dome and City do not exist in Task 3: no data entry, no stub, no placeholder condition. Settlement's HANDOFF exit ("relationships and trust form") is not built (Task 4); the only exit is the fall-back rule. The first age at creation is Landing. Settlement entry can recur any number of times (section 6).

## 3. State
All of it is held by `Ages` (sim/ages.gd), owned by `SimWorld` as `world.ages`. It is private history: nothing below except the stats of section 8 is copied into `stats`, the balance table or the HUD.
| Field | Meaning |
| --- | --- |
| `age` | current age id, `landing` at creation |
| `window` | list of the last `sample.window_sols` booleans (`ok`), newest last; oldest dropped when longer |
| `last_change_sol` | elapsed sol of the latest age change; 0 at creation |
| `snap_shorts`, `snap_deaths` | the values of `stats.shorts` and `len(stats.deaths_list)` at the previous sol boundary (feed the "past sol" clauses) |
| `last_sample` | the most recent sample as a dictionary of clause booleans plus the raw values (section 4.2). Read by tests and `tools/age_probe.gd` only; never copied to stats, never read by the view |
Elapsed sol = `SimWorld.sol()` (sol 0 is the first sol; Mars sol number = elapsed + 1, spec life-support section 3). Windows and dwell count elapsed sols, not hours, so no float time enters a decision.

## 4. The per-sol sample
### 4.1 Where it runs
Once per sol boundary, in step phase 11 (after the stats sampling), inside the existing `if _sol_started:` block of `SimWorld.step()`, after the `pop_by_sol` line. `_sol_boundary()` itself is unchanged. The hook is one call, `ages.on_sol(world)`. Reason for phase 11 rather than the plan's "inside `_sol_boundary`": at the end of the step phases 3 (power) and 10 (shortage deaths) have run, so the sample reads settled state; `stats.shorts_this_sol` has already been reset at the boundary, so the "past sol" clauses use the private snapshots instead of it. Cost is O(window) = 40 booleans plus a scan of at most the deaths added in one sol, once per sol (about 148,000 steps per 300 sols are untouched).
`on_sol(world)` does, in this order, at boundary n = `sol()` (n >= 1):
1. Credit the sol that just ended to the age in force during it: `stats.sols_in_age[age] += 1`.
2. Build the sample (4.2) when n >= `sample.from_sol` and pop > 0; append to `window`, drop the oldest past `sample.window_sols`. Always refresh `snap_shorts` and `snap_deaths`, including before `from_sol` and when pop is 0 (so the first sample at sol 5 covers exactly one sol).
3. Evaluate the change (sections 5 to 7) with `decide`; if the age changes, update `age`, `last_change_sol = n`, stats, and log (section 8).
Nothing in `on_sol` draws from `SimRng`, reads the wall clock, writes colony, building, being or resource state, or reads the log.
Test seams: `Ages.sample(world)` (pure read, returns the dictionary of 4.2); `Ages.decide(window, age, sols_since_change, mars_born)` (pure function, returns the age id that should be in force, so synthetic histories can run thousands of sols in milliseconds); `Ages.on_sol(world)` callable directly after a test sets `world.t` to a boundary (`start_hour + n x sol_hours`); `SimWorld.ages_enabled` (default true; false skips the hook entirely, used to prove no side effects). Blank test worlds have `world.ages` with age `landing` and log nothing at creation.

### 4.2 The sample: every clause, thresholds from `data/ages.json`
A sample is `ok` when ALL of the following hold. Each clause is stored by name in `last_sample` so a test or the probe can see which one failed. Reads are of the state at the end of the boundary step.
| # | Clause name | Reads | Passes when | Threshold key |
| --- | --- | --- | --- | --- |
| 1a | `oxygen` | `colony.oxygen`, `colony.o2_cap()` | `oxygen >= o2_min_fraction x o2_cap` | `sample.o2_min_fraction` 0.5 |
| 1b | `food` | `colony.food`, `colony.food_cap()` | `food >= food_min_fraction x food_cap` | `sample.food_min_fraction` 0.5 |
| 2a | `o2_net` | `colony.o2_net()` (per h) | `o2_net > net_above` (strict) | `sample.net_above` 0.0 |
| 2b | `food_net` | `colony.food_net()` (per h) | `food_net > net_above` (strict) | `sample.net_above` 0.0 |
| 3a | `power_budget` | `buildings.demand()`, `buildings.supply()` | `demand <= supply` | none (the budget itself) |
| 3b | `none_offline` | `buildings.list[*].offline` | no building has `offline` true | none |
| 3c | `no_short` | `stats.shorts`, `snap_shorts` | `stats.shorts == snap_shorts` (no short since the previous boundary) | none |
| 4 | `no_shortage_death` | `stats.deaths_list[snap_deaths:]` | no entry added since the previous boundary has a cause in `shortage_causes` (`air`, `thirst`, `hunger`). A `suffocated outside` death is an accident, not a shortage, and does not fail the clause | `sample.shortage_causes` |
| 5 | `ice` | `colony.ice`, `colony.pop()`, `consumption.ice_per_being` (colony.json), `sol_hours` | `ice / (pop x ice_per_being x sol_hours) >= ice_min_sols` | `sample.ice_min_sols` 2.0 |
Notes:
- `ice_min_sols` 2 is the existing 3-sol floor idea (`stock_days_floor_sols`) slightly looser. Ice is judged against current use, never against `ice_target`, because ice stays under 0.6 of target on the dry seeds while still being plentiful on others (plan section 4). Example at pop 12: 2 sols of use is 12 x 0.01 x 24.6597 x 2 = 5.92; at pop 100: 49.3.
- The instant value is read, not a minimum over the sol, so a dip between two boundaries can be missed. Accepted: it is stateless, and a real shortage persists over many boundaries.
- Oxygen, food and power are expected to pass on every sample of every Task 1 seed (stocks at caps by about sol 6, no shorts); ice is the clause that varies (Task 1: ice dry on seeds 42, 99, 2026 after sol 120).
- Early sols: oxygen starts at 140 of cap 550 (0.25) and food at 110 of 420, and they reach 0.5 of cap at about sol 5.2 and 5.4. The samples at sols 5 and 6 may therefore fail; the tolerance forgives them (4 of 40).
- Pop 0 (extinct): the sample is skipped (nothing appended, window unchanged), so the ice division never runs. The age is frozen while pop is 0 and a colony that has died out never "falls back"; `sols_in_age` keeps counting, because those sols did pass in that age. If pop returns above 0 (cannot happen in Task 3) sampling resumes.

## 5. Entry to Settlement (owner decision, final)
`decide` returns `settlement` when the current age is `landing` and ALL of:
1. the window is full (holds `window_sols` = 40 samples; samples start at sol 5, so the earliest possible entry is at the boundary of elapsed sol 44);
2. the number of `ok` samples in the window >= `required_ok` = ceil(`entry.ok_share` x `window_sols` - STEP_EPS) = ceil(0.9 x 40) = 36 (at most 4 failing sols in the last 40);
3. the last `entry.recent_ok_sols` = 3 samples are all `ok`;
4. at least `entry.mars_born_min` = 5 living beings have `earth_born` false (evaluated at the boundary, not part of the sample, not stored in the window);
5. the dwell is over: `n - last_change_sol >= min_dwell_sols` (20).
The last-3 clause blocks entry during a current failure even when the share is high. Entry at sol n is logged once for that change (section 8). `STEP_EPS` is the existing constant; no new literal.
The window is a private sliding history. It is never shown, never summarised, and not in stats.

## 6. Exit (fall back) and hysteresis
### 6.1 Rule
`decide` returns `landing` when the current age is `settlement` and ALL of:
1. the window is full (always true once in Settlement);
2. the number of `ok` samples in the window <= `exit_ok_max` = ceil(`exit.ok_share_below` x `window_sols` - STEP_EPS) - 1 = ceil(0.6 x 40) - 1 = 23 (that is, strictly fewer than 24 ok sols; at least 17 sols not ok in the last 40);
3. NOT all of the last `exit.recent_sols` = 5 samples are `ok` (a colony whose last 5 sols were all fine is recovering and stays);
4. the dwell is over: `n - last_change_sol >= min_dwell_sols` (20).
Re-entering Settlement later uses section 5 unchanged (full window, 36 ok, last 3 ok, 5 Mars-born, dwell). The first entry is logged with the entry wording; every later entry with the settle-again wording.
### 6.2 Why the two thresholds cannot flap
- The entry share (0.9, 36 of 40) and the exit share (0.6, 24 of 40) leave a dead band of 24..35 ok samples where nothing changes, whichever age is current. The window slides by exactly one sample per sol, so its ok count moves by at most 1 per sol.
- After an entry the window holds at least 36 ok. To reach 23 or fewer, at least 13 sols must go by (13 consecutive not-ok samples). After an exit it holds at most 23 ok. To reach 36 again, at least 13 sols must go by. So even with no dwell the fastest possible round trip is 26 sols, and a single change is never undone in under 13.
- The minimum dwell of 20 sols is longer than that 13-sol bound, so it is the operative limit: no two age changes are ever less than 20 sols apart, in either direction. Over the 300-sol balance run that is a hard ceiling of floor((300 - 44) / 20) + 1 = 13 changes, and the real number is set by life support, not by the rule.
- Oscillation: a history that alternates ok and not ok with any period at which the half-period is under 13 sols (including the 50/50 square waves of period 2 to 24) keeps the share near 0.5 or inside the band: from Landing it never enters, from Settlement it leaves at most once and never returns. A noisy colony hovering at 0.75 ok sits in the dead band and does not change except by the rare tail event (mean about 0.1 changes per 300 sols, section 10 test 14).
- Why these numbers: 0.9 over 40 sols is the owner's entry rule. 0.6 is a deliberately low exit line: a colony in Settlement may have up to 16 not-ok sols in the last 40 (4 tolerated at entry, 12 more) before it is judged to be back in hard times, so the ice trouble seen on seeds 42, 99, 2026 (many consecutive failing sols, not an isolated dip) crosses it after about 17 consecutive failing sols, while a short crisis does not. 5 recent samples ("not all ok") let a colony that is already recovering stay. 20 sols is about one Mars month: long enough that the log never reads like noise, and shorter than the 40-sol window so it never delays a real collapse by more than the window itself.
- The first age at creation is Landing, announced at world creation (elapsed sol 0 = Mars sol 1). Landing cannot be left before elapsed sol 44.

## 7. No effect on the colony
The age is read by nobody in the sim. Ages never write stocks, beings, buildings, resources, power, births or the RNG. `stats` gains only the keys of section 8; no existing key changes meaning. Proof: section 10 tests 15 to 17 and the five Task 1 table hashes (section 12). Council, trust and later systems may read `stats.age` as context in later tasks.

## 8. Log lines and stats
### 8.1 Log
Kind `age_began` for all four lines, with extra fields `age` (the age now in force) and `how` in {`landing`, `settled`, `fell_back`, `settled_again`}, plus the usual `t`, `sol`, `clock_sol`, `kind`, `text`. Text comes from `data/ages.json`; it has no number, no percentage, no count and no "sols until" in any of the four lines (a test asserts no digit and no `%`).
| Event | `how` | When | Text key | Starting text |
| --- | --- | --- | --- | --- |
| Landing at the start | `landing` | at world creation, after `founders_landed` (founder worlds only) | `landing.log_start` | "The founders have landed at Jezero. Air, water, food and power are everything." |
| First entering Settlement | `settled` | the change of section 5 when `first_settlement_sol` is null | `settlement.log_enter` | "The founders are no longer only surviving. The colony has settled." |
| Falling back | `fell_back` | the change of section 6 | `landing.log_fall_back` | "The easy days are over. The colony is back to simply getting by." |
| Settling again | `settled_again` | entry when Settlement was entered before | `settlement.log_enter_again` | "The colony has found its footing again. Life has a rhythm once more." |
Texts are the game-designer's draft; the owner may reword them freely (data only). The log is capped at 500 and may evict old age lines; stats never depend on it (history below).
### 8.2 Stats (run-wide, never windowed, never reset by `reset_window`)
| Key | Definition |
| --- | --- |
| `stats.age` | current age id string; this is what the HUD reads |
| `stats.age_changes` | number of changes after the initial Landing (Landing to Settlement is 1) |
| `stats.sols_in_age` | `{landing: int, settlement: int}`; elapsed sols credited to each age (step 1 of `on_sol`); the sum is the number of completed sols |
| `stats.first_settlement_sol` | elapsed sol of the first entry, null before; set once, like `first_birth_sol` |
| `stats.age_history` | list of `{age, how, t, sol, clock_sol}`, one per announcement including the initial Landing (founder worlds only; blank worlds start empty and the list begins with the first change); uncapped (it holds at most a few entries) |
Not in stats: the window, the last sample, the snapshots. No key is a progress value; `sols_in_age` is a record of the past and is shown to nobody.
Blank test worlds: `stats.age` is `landing`, `age_history` is empty, `sols_in_age` zeros, nothing logged until a change.

## 9. HUD
The text HUD shows the current age name only, for example a line `Age: Settlement`, built from `SimData.ages()[stats.age].name`. It never shows a share, count, bar, window, "sols until", `sols_in_age` or `age_changes`. A change shows by the name changing and by the log line if the HUD shows the log. Test: the HUD string for each age contains the name; the age part of the string contains no digit; the HUD source reads no key of `world.ages` and none of `sols_in_age`, `age_changes`, `age_history`.

## 10. Tests (tests/test_ages.gd; written first, red; no test may have zero checks)
Staging, "good world" G: blank world, reactor, habitat and green room built (demand 7, supply 14), 12 beings of whom 5 have `earth_born` false, oxygen and food at cap, ice 100, no shorts, no deaths. `sample(G)` is all-true. Sols are advanced by setting `world.t` to boundary n and calling `on_sol`, never by stepping 44 sols.
Per clause (one test each, break only that clause, assert it names the clause in `last_sample`):
1. `oxygen`: 275.0 of cap 550 passes; 274.9 fails (the `>=` edge). Same for `food`: 210 passes, 209.9 fails (cap 420).
2. `o2_net`: 28 beings on 1 green room give exactly 0.0, which fails (strict); 27 passes. `food_net`: shipped data cannot isolate it (oxygen use hits zero first), so the test lowers `colony.production.food_per_green_room` through the data override seam, as the Task 1 tests do.
3. `power_budget`: demand 14 on supply 14 passes; 15 fails. `none_offline`: one building offline fails (with demand under supply). `no_short`: `stats.shorts` raised by 1 between two boundaries fails that sample and the next boundary passes again.
4. `no_shortage_death`: a `thirst` entry added between boundaries fails; `air` and `hunger` the same; a `suffocated outside` entry passes; an entry from before the previous boundary does not count.
5. `ice`: ice = exactly 2 x pop x 0.01 x 24.6597 passes (compute from the formula, tolerance 1e-9); 1e-6 below fails; pop 12 and pop 100 both checked.
6. Pop 0: `on_sol` appends nothing, does not divide by zero, leaves the age unchanged and still credits `sols_in_age`; pop 12 afterwards samples again.
Window and entry:
7. Samples start at sol 5: boundaries 1 to 4 append nothing (snapshots refresh); boundary 5 appends one.
8. Fully ok history: age stays `landing` at boundary 43, becomes `settlement` at boundary 44 (40 samples, sols 5 to 44), exactly one `age_began` with `how` `settled`, `first_settlement_sol` 44, `age_changes` 1.
9. Tolerance edge: window of 36 ok and 4 not ok (not in the last 3) enters; 35 ok and 5 not ok does not. The 4 failing sols at the very start (sols 5 to 8) still enter at 44.
10. Last-3: a window of 37 ok then 3 not ok (share passes, last 3 fail) blocks entry; 39 ok then 1 not ok blocks it; 2 ok after that still block when the share is fine but only the last 3 are checked, so entry happens exactly when the third consecutive ok arrives.
11. Mars-born: a perfect window with 4 Mars-born blocks; the fifth being born lets the next boundary enter; five founders (earth_born) do not count; dead ones do not count.
Exit and hysteresis:
12. Dead band: from Settlement with a window of 24 ok stays; 23 ok with one not-ok among the last 5 leaves; 23 ok with the last 5 all ok stays (recovering). Entry and exit are asserted on both sides of 36/35 and 24/23.
13. Dwell: Settlement entered at sol 100, then all not ok: no exit at sol 113 (the rule is first true) nor at 119; exit at 120 exactly, one `fell_back` line. The same for entering after a fall back with an injected perfect window: blocked at `last_change_sol + 19`, enters at +20. `age_changes` and `age_history` follow each change.
14. No flapping on synthetic history (via the pure `decide`, no world): (a) 50/50 square waves of period 2, 3, 5, 8, 12, 24 over 3,000 sols from Landing: zero changes; started in Settlement: at most 1 change, to Landing, and never back; (b) a period of 80 sols (40 ok, 40 not ok) changes at most once per half-period and every gap between changes is >= 20; (c) iid ok with probability 0.75 over 300 sols, 200 seeds from a test-local generator (never `SimRng`): the mean number of changes per run is <= 0.25 and every gap >= 20 (the expected mean is about 0.1, the margin is 2.5x; the engineer reports the measured mean); (d) an adversarial history of 13 ok, 13 not ok repeated: the number of changes never exceeds floor(sols / 20); (e) data sanity: `entry` count minus `exit` max count >= 13 (the dead band), `min_dwell_sols >= 13`, `exit.ok_share_below < entry.ok_share`.
Stats, log and purity:
15. Landing: a founder world logs `founders_landed` then one `age_began` with `how` `landing` and the data text; blank worlds log nothing; `stats.age` is `landing`.
16. A full fall-back and re-entry staged with `on_sol` logs `settled`, `fell_back`, `settled_again` in that order with the three data texts; none contains a digit or `%`; `first_settlement_sol` stays at the first value; `sols_in_age` sums to the number of boundaries seen; `age_history` has the four entries.
17. No RNG, no side effect: a founder world seed 42 for 10 sols with `ages_enabled` true and another with it false have equal `rng` state, equal `stats` on every old key, equal beings (id, building, state, energy) and equal stocks; two same-seed worlds with ages on are identical including `stats.age_history`; seed 43 differs from seed 42 as before. A second test confirms `on_sol` leaves stocks, buildings, beings and `rng` untouched on a staged world.
18. Key-path parity (section 13), including that `ages.json` has no Council, Dome or City key.
19. HUD (section 9) and advance budget (section 11 tests).
Determinism for the long run comes from the balance run (section 12): the same table twice.

## 11. `advance()` wall-time budget and step profile
These are view-path only; a step does exactly what it does today.
- `data/sim.json` gains `advance_budget_ms` = 8.0 (ms of wall time `advance()` may spend per call). Rationale: a 60 fps frame is 16.7 ms; the view model update is 1.0 to 1.3 ms and drawing the rest (Task 2 report), so the sim gets about half. 0 means "one step per call and no more". `max_steps_per_frame` (2000) stays as a hard cap on top.
- Rule: `advance(hours)` adds `hours` to the accumulator and takes whole fixed steps while one is due. It reads an injected monotonic millisecond clock (a replaceable function on the world, default the engine tick counter) at entry, and after each step stops if elapsed >= `advance_budget_ms` or the step cap is reached. At least one step is taken whenever a step is due, even with budget 0 or a slow clock. The budget is checked after a step, so a call may overshoot by at most one step.
- Leftover time is **dropped**, exactly as `max_steps_per_advance` does today: when the loop stops with time still due, the accumulator is set to 0 and the dropped hours are added to a counter on the world (`advance_dropped_h`). Reason: carrying a debt that the budget can never repay would grow without bound, and a capped carry only hides the drop for one frame; dropping makes the sim run slower than requested and nothing else. Neither the counter nor any wall-time figure is placed in `stats`, the log or any hashed state, so determinism is untouched.
- What the speed labels promise: a maximum, not a promise. The HUD labels read as ceilings (for example "up to 1000x"); the achieved speed (sim hours per real second over the last second, from steps taken) may be shown in the debug line, never promised. With the Task 2 measurement of 4.7 to 6.8 ms per step at 164 beings and an 8 ms budget, a big colony sustains about 1 to 2 steps per frame, roughly 3 to 6 sim hours per real second (3x to 6x), whatever the preset. Small colonies run much faster. This is the honest result of the budget; step profiling (`tools/step_profile.gd`, phase timers kept out of `sim/`) is the way to raise it, and a fix is allowed only if the Task 1 table hashes (old columns) stay byte-identical (section 12).
- Tests: budget 0 takes exactly one step; a fake clock that advances 3 ms per read with budget 8 stops after 3 steps (reads at entry then after each step); steps taken per call with the real clock never exceed the cap; with a fake clock that never reaches the budget, the steps for a given total of hours equal the unbudgeted run and the world state (stats, rng, beings) after them is identical; dropped hours equal requested minus taken x `fixed_step` after a stopped call; the accumulator is 0 after a stop and keeps its sub-step remainder otherwise.

## 12. Balance integration and proof of no behaviour change
- The balance table gains one trailing column `age`, header `age`, values `L` (landing) or `S` (settlement), separated from the previous column by one space. Removing the column means deleting the final whitespace-separated field of the header and of every row together with the space before it. All earlier columns keep their widths and values.
- **Proof**: the five Task 1 table hashes (`String.sha256_text` of the table body, which does not include the `#` header lines) are 02032b23... (seed 42), 830c7d0c... (seed 7), 0e3e83a7... (seed 99), bca6eb2c... (seed 1234), 2645033a... (seed 2026). With the age column removed, the Task 1 baseline command per seed must reproduce them exactly. Note: the header `data_hash` changes by design (the `sim.json` key, and `ages` is added to the hashed file list) and is not part of the table body hash; the engineer records the new `data_hash`. If a hash differs, the cause is a behaviour change and the step is rejected.
- Target T10 (balance, per seed, 300 sols), taken from `stats` and never from the log:
  1. `first_settlement_sol` is not null and between `balance.settle_sol_min` 40 and `settle_sol_max` 150 (the lower bound is structural: 44);
  2. `age_changes <= balance.max_age_changes` (4: enter, fall back, enter again, fall back again; provisional, to be confirmed by the probe);
  3. every gap between consecutive `age_history` sols is >= `min_dwell_sols` (invariant);
  4. `len(age_history) == age_changes + 1` and every history entry has its `how`;
  5. reported, not judged: first Settlement sol per seed and the spread (latest minus earliest), `age_changes`, `sols_in_age`, the age at sol 300, and the sols of each change. Falling back is not a failure; it is the intended drama (owner).
- Why 4 as the proposed maximum: Task 1 shows one ice crisis per seed in 300 sols (dry from about sol 120 to 180; seed 2026 recovers by about sol 190 to 210 and dries again by 300). One cycle is 2 changes, two cycles are 4. Estimates (replaced by the probe): seeds 7 and 1234: 1 change (no fall back); seeds 42 and 99: 2 (settle about sol 44 to 55, fall back about 155 to 175, no return); seed 2026: 2 or 3 (settle, fall back about sol 160 to 175, possibly settle again about 245 to 255). The dwell ceiling of 13 is the rule's worst case, not the expectation. If the probe shows a seed above 4 with a reason in the sim (not noise), raise the number with the reason in the log; if it shows flapping (changes within 40 sols of each other), tighten the exit share or the dwell, one parameter per run.
- Old balance targets T1 to T9 are unchanged. `docs/specs/life-support-power.md` section 13 gains a pointer to this section and its section 16 gains the five stats keys and the `age_began` log kind (step 9, test engineer).

## 13. Tunables (JSON key path, unit, starting value, source)
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| ages.landing.name / settlement.name | text | Landing / Settlement | HANDOFF 7 |
| ages.landing.log_start | text | see 8.1 | game-designer draft |
| ages.landing.log_fall_back | text | see 8.1 | game-designer draft |
| ages.settlement.log_enter | text | see 8.1 | plan A9 |
| ages.settlement.log_enter_again | text | see 8.1 | game-designer draft |
| ages.sample.from_sol | elapsed sol | 5 | owner (same as `STATS_FROM_SOL`) |
| ages.sample.window_sols | sols | 40 | owner |
| ages.sample.o2_min_fraction / food_min_fraction | fraction of cap | 0.5 / 0.5 | plan section 4 |
| ages.sample.net_above | per h | 0.0 | plan section 4 |
| ages.sample.ice_min_sols | sols of current use | 2.0 | plan section 4 |
| ages.sample.shortage_causes | list of death causes | air, thirst, hunger | spec life-support 9.3 |
| ages.entry.ok_share | fraction of window | 0.9 | owner |
| ages.entry.recent_ok_sols | samples | 3 | owner |
| ages.entry.mars_born_min | beings | 5 | owner |
| ages.exit.ok_share_below | fraction of window | 0.6 | game-designer (section 6.2) |
| ages.exit.recent_sols | samples | 5 | game-designer |
| ages.min_dwell_sols | sols | 20 | game-designer |
| ages.balance.settle_sol_min / settle_sol_max | elapsed sol | 40 / 150 | owner (T10) |
| ages.balance.max_age_changes | changes per 300 sols | 4 | game-designer, provisional |
| sim.advance_budget_ms | ms of wall time per `advance()` | 8.0 | game-designer |
Not data: the age ids `landing` and `settlement`, the clause names, STEP_EPS (existing), and "pop 0 skips the sample".
Everything above except the `balance.*` block is read by `sim/ages.gd`; the `balance.*` block is read by `tests/balance_lib.gd` only.

### Key-path list (machine-readable; one leaf per line)
Same rules as life-support-power.md section 12: a test parses the lines between the `keys:` fence markers and checks both ways (every listed path exists in the loaded file; every leaf of `ages.json` is listed; arrays and strings are leaves). The `sim.` line is checked for existence only (the leaf walk of `sim.json` is not part of this test).
```keys:
ages.landing.name
ages.landing.log_start
ages.landing.log_fall_back
ages.settlement.name
ages.settlement.log_enter
ages.settlement.log_enter_again
ages.sample.from_sol
ages.sample.window_sols
ages.sample.o2_min_fraction
ages.sample.food_min_fraction
ages.sample.net_above
ages.sample.ice_min_sols
ages.sample.shortage_causes
ages.entry.ok_share
ages.entry.recent_ok_sols
ages.entry.mars_born_min
ages.exit.ok_share_below
ages.exit.recent_sols
ages.min_dwell_sols
ages.balance.settle_sol_min
ages.balance.settle_sol_max
ages.balance.max_age_changes
sim.advance_budget_ms
```
`SimData.ages()` is the accessor (`load_json("ages.json")`), and `data_hash` in `tests/balance_lib.gd` adds `ages` to its file list.

## 14. Calibration probe (tools/age_probe.gd, read-only)
Replays seeds 42, 7, 99, 1234, 2026 to sol 300 with the real hook, and per seed records, once per sol from sol 1, the raw values of every clause (oxygen/cap, food/cap, o2_net, food_net, demand, supply, offline count, shorts since last, shortage deaths since last, ice in sols of use, pop, Mars-born count), so any threshold can be replayed offline without a new run. It must not change data, state or RNG, and it must check its own replay: the age history it computes from the recorded samples with the shipped numbers equals `stats.age_history` of the live run.
Per seed it prints and writes to `docs/balance/task-3-calibration.md`:
1. Crossing sols: the first sol with an `ok` sample; the first sol the entry rule fires; the age history with `how` and sol of each change (the shipped numbers).
2. Sols in each age and the age at sol 300; `age_changes`.
3. Flap report (owner request): number of changes after the first, the shortest gap between changes, and the number of fall-back-then-re-entry pairs within 40 sols; a flap is any change within `window_sols` of the previous one.
4. Sample failure statistics: how often the sample fails per 50-sol band (5 to 49, 50 to 99, ..., 250 to 299) and on which clause: the count of failures per clause, and the count where that clause was the only one failing. Expected: only `ice` after sol 120 on seeds 42, 99, 2026.
5. Candidates replayed from the stored samples: window {30, 40, 50} x entry share {1.0, 0.9, 0.8} x exit share {0.5, 0.6, 0.7} x dwell {10, 20, 30} x `ice_min_sols` {1, 2, 3}: the first Settlement sol, the number of changes and the shortest gap for each. Rule: the table is for choosing; a change to the shipped numbers is made one parameter per run and recorded in the changelog.
6. The wall cost of `on_sol` (microseconds per call over the run; expected well under 50 us) so the per-sol cost claim is measured.
The probe's outputs set the final numbers for: `exit.ok_share_below`, `min_dwell_sols`, `balance.max_age_changes`.

## 15. Edge cases
- Pop 0: no sample, age frozen, no log (section 4.2). Pop drops below 5 Mars-born while in Settlement: nothing happens (the Mars-born clause is an entry clause only).
- Window not yet full: no entry and no exit; a world that starts in Settlement by a test seam but with an incomplete window does not exit until the window is full.
- A sol with two events (short and death): both just fail the sample; the clauses are independent.
- Several ages never skip: a change is always Landing to Settlement or back; at most one change per boundary.
- A boundary step on which a building comes back online: read after phase 3, so it counts as online.
- `ages_enabled` false: no sample, no log, no stats change; `stats.age` stays `landing`.
- The log being evicted at 500 entries does not change any age value (nothing reads the log).
- Slow clock or `advance` dropping hours: age rules count sols from sim time, so a dropped step changes nothing about the rules.

## 16. Open questions
1. Owner: the draft log texts (section 8.1), in particular whether a fall back should read grimly or gently.
2. Owner: is a dead colony (pop 0) correctly frozen in its last age, or should it announce a fall back?
3. The 20-sol dwell and the 0.6 exit share are reasoned, not measured; the probe may move them.
4. T10's maximum of 4 changes is an estimate from Task 1 ice behaviour.
5. The sample reads the instant ice at the boundary, not the minimum over the sol; if the probe shows missed dips (min over sol under 2 sols of use while the sample was ok on many sols), add a per-sol min as a clause source (a read-only stat the engineer would add).
6. 3x to 6x sustained speed at 164 beings is the Task 3 outcome unless step profiling finds a safe saving.

## Changelog
- 2026-10-05: first version (game-designer). Reviewer sign-off (step 2): pending.
