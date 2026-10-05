# Spec: ages (Task 3): Landing and Settlement, announced in the log (revision 3)

Source of truth: HANDOFF.md sections 1, 2, 7, 9, 10. Plan and final owner decisions (Herby, 2026-10-05): `docs/tasks/task-3-plan.md`. Sim facts read: `docs/specs/life-support-power.md` (sections 3, 4, 5, 9, 16); balance facts: `docs/balance/task-1-log.md`. Design reviews: `docs/design/reviews/ages-emergence.md`, `ages-feel.md`, `ages-clarity.md` (record in section 17).
Locked decisions respected: influence-only god (no god power reads or writes the age), ages not meters (no progress value anywhere; the window is private), per-being energy (read per being, as shares), power as a budget (a short is a past-sol fact, never a death).
Tunables live in `data/ages.json` (new) and `data/sim.json` (new keys). No tunable in `sim/ages.gd`. This spec describes behaviour and numbers only, no code.

## For the owner (changes to WHAT the sample measures; decided by the lead and confirmed by the owner, 2026-10-05)
Your rule stands untouched: at least 36 of the last 40 samples ok, the last 3 ok, at least 5 Mars-born alive, samples from sol 5, window private, regression allowed with hysteresis, announce only. Two refinements change what "ok" and "Mars-born" mean:
1. **Two colonist clauses join the sample.** A sol is ok only if (a) no more than 10% of the living beings are in distress (energy below the exhausted line of 12, or turned back outside) and (b) at least 70% of the living beings are rested (energy at or above the sleep line of 28). Both are shares of the living population, so a 160-being colony reads like a 12-being one. Why: without them the sample is, in practice, only "ice is at least 2 sols of use", because oxygen, food and power pass on every Task 1 sample (spec 4.2). The age would be an ice gauge in disguise. In practice, on the five Task 1 seeds I expect these two clauses to pass nearly always (energy averages 54 to 60 and the boundary falls at dawn, 06:00, after the night), so the entry sols should barely move; the probe measures this. Their value is that the age now reads people, and later systems (emotions, trust, Task 4) can make them matter. Both thresholds are estimates for the probe.
2. **"5 Mars-born" now means five who belong to a family.** The count is of living Mars-born beings whose recorded parent is also alive, and those beings must come from at least 2 different birth habitats. The number 5 is yours and unchanged. Why: five orphans in one habitat is a headcount, not a family; HANDOFF 7 says Settlement is "families". Needs one cheap sim change (record the parent and birth habitat on each newborn, no RNG draw, no behaviour change; section 3). The 2-habitat number is an estimate for the probe.
Your decisions on the open questions of revision 2 are recorded in section 18 and applied throughout (colonist clauses kept; family rule = living parent and 2 birth habitats; pop 0 frozen with no age word; speed never changes on an age change; Task 5 gate still open).

## 1. Purpose
Name what the people already did. Each sol the colony is looked at once and the result is `ok` or `not ok`. A long stretch of mostly ok sols, ending in ok sols, with a first generation of families alive, is called Settlement. A long stretch of mostly not-ok sols sends the colony back, and the line says what pressed on it. Both are announced in the log in the colony's voice. Nothing counts toward the next age on screen, and nothing about the colony changes because of the age.

## 2. Ages for Task 3
| id | Display name | Life is about (HANDOFF 7) | Entered by |
| --- | --- | --- | --- |
| `landing` | Landing | survival: air, food, water, power | world creation, or falling back from Settlement |
| `settlement` | Settlement | families, routines | the entry rule (section 5) |
Council, Dome and City do not exist in Task 3: no data entry, no stub, no condition. Settlement's HANDOFF exit ("relationships and trust form") is Task 4; the only exit now is the fall-back rule. The first age is Landing, announced at world creation (elapsed sol 0 = Mars sol 1). Settlement entry can recur. Task 5 (Council) must not gate on "first Settlement entry"; it should read `stats.age_history` (complete, section 8.2) and choose its own rule.

## 3. State
Held by `Ages` (sim/ages.gd), owned by `SimWorld` as `world.ages`. Private history: nothing here except section 8.2 is copied into `stats`, the balance table or the HUD.
| Field | Meaning |
| --- | --- |
| `age` | current age id; `landing` at creation |
| `window` | the last `sample.window_sols` samples, newest last; each is `{ok, failed}` where `failed` is the set of failing cause groups (4.3) |
| `last_change_sol` | elapsed sol of the latest change; 0 at creation |
| `snap_shorts`, `snap_deaths` | `stats.shorts` and `len(stats.deaths_list)` at the previous sol boundary |
| `last_sample` | most recent sample: clause booleans plus raw values. For tests and `tools/age_probe.gd` only; never in stats, never read by the view |
**Two fields recorded on each Being at birth** (the only change outside `ages.gd` and the hook; state, no behaviour): `parent_id` (the id of the being `rng.pick(here)` already returns in `_create_newborn`; today the result is discarded; founders and test-seam beings: 0) and `birth_building_id` (the habitat id). The birth age is already `born_t`. No new RNG draw, no change to draw order; proof in section 10 (test 17) and the five table hashes. Null guard: if the pick returns null (empty `here`; `SimRng.pick` returns null without drawing on an empty array), `parent_id` is 0. The birth gates guarantee at least one being today, but a data change could break that, and the guard must not add a draw.
Note for Task 4: `rng.pick(here)` can pick a being only hours old as the parent, so a recorded "parent" can itself be a child. Task 4 relationships should not treat `parent_id` as proof of an adult.
Elapsed sol = `SimWorld.sol()` (Mars sol number = elapsed + 1). All windows and dwell count elapsed sols; no float time enters a decision.

## 4. The per-sol sample
### 4.1 Where it runs
Once per sol boundary, in step phase 11 after the stats sampling, inside the existing `if _sol_started:` block of `SimWorld.step()`, after the `pop_by_sol` line: one call `ages.on_sol(world)`. `_sol_boundary()` is unchanged. At the end of the step phases 3 (power) and 10 (shortage deaths) have run, so the sample reads settled state; `shorts_this_sol` is already reset at the boundary, so "past sol" clauses use private snapshots. The boundary falls at Mars clock 06:00 (start hour is dawn, a quarter sol in), the same phase of every day, which is why instantaneous colonist reads are comparable sol to sol.
`on_sol(world)`, at boundary n = `sol()` (n >= 1), in this order:
1. Credit the sol that just ended to the age in force: `stats.sols_in_age[age] += 1`.
2. If n >= `sample.from_sol` and pop > 0: build the sample (4.2), append to `window`, drop the oldest past `sample.window_sols`. Always refresh the two snapshots, also before `from_sol` and at pop 0.
3. Call `decide`; on a change update `age`, `last_change_sol = n`, stats, and log (section 8).
No RNG draw, no wall clock, no write to colony, building, being or resource state, no read of the log.
Test seams: `Ages.sample(world)` (pure read); `Ages.decide(window, age, sols_since_change, family_mars_born, homes)` (pure, returns the age id that should be in force); `Ages.dominant_cause(window)` (pure); `Ages.on_sol(world)` after a test sets `world.t` to a boundary (`start_hour + n x sol_hours`); `SimWorld.ages_enabled` (default true; false skips the hook). Blank worlds have `world.ages` in `landing` and log nothing at creation.

### 4.2 The sample: every clause, thresholds from data
A sample is `ok` when ALL hold. Each clause is stored by name in `last_sample`. All reads are of the state at the end of the boundary step.
| # | Clause | Reads | Passes when | Key |
| --- | --- | --- | --- | --- |
| 1a | `oxygen` | `colony.oxygen`, `o2_cap()` | `oxygen >= o2_min_fraction x o2_cap` | `sample.o2_min_fraction` 0.5 |
| 1b | `food` | `colony.food`, `food_cap()` | `food >= food_min_fraction x food_cap` | `sample.food_min_fraction` 0.5 |
| 2a | `o2_net` | `colony.o2_net()` | `> net_above` (strict) | `sample.net_above` 0.0 |
| 2b | `food_net` | `colony.food_net()` | `> net_above` (strict) | `sample.net_above` 0.0 |
| 3a | `power_budget` | `demand()`, `supply()` | `demand <= supply` | none |
| 3b | `none_offline` | `buildings.list[*].offline` | no building offline | none |
| 3c | `no_short` | `stats.shorts`, `snap_shorts` | equal (no short since the previous boundary) | none |
| 4 | `no_shortage_death` | `stats.deaths_list[snap_deaths:]` | no new entry with a cause in `shortage_causes`; `suffocated outside` is an accident and does not count | `sample.shortage_causes` |
| 5 | `ice` | `colony.ice`, `pop()`, `consumption.ice_per_being`, `sol_hours` | `ice >= ice_min_sols x pop x ice_per_being x sol_hours - CMP_EPS` (no division; pop 0 never reaches it) | `sample.ice_min_sols` 2.0 |
| 6 | `calm` | each living being's `energy`, `returning`, `is_outside()` | `distressed x 1.0 <= distress_share_max x pop + CMP_EPS` (count compared by cross-multiplying, never a computed share). Distress = `energy < beings.energy.exhausted_turn_back` (12) OR (`Being.is_outside()` and `returning` true) | `sample.distress_share_max` 0.10 |
| 7 | `rested` | each living being's `energy` | `rested x 1.0 >= rested_share_min x pop - CMP_EPS`, rested = `energy >= beings.energy.sleep_below` (28) | `sample.rested_share_min` 0.70 |
`CMP_EPS` = 1e-9, a comparison slack like `STEP_EPS` (not data; section 13). Exact boundaries therefore pass: ice exactly 2 sols of use, 7 rested of 10 at 0.7, 1 distressed of 10 at 0.1.
Tiny populations: the shares are honest but coarse. Below 10 living beings any single distressed being fails `calm` (1/9 > 0.10); at pop 3 `rested` needs all 3 (2/3 < 0.7). Settlement needs at least 5 family Mars-born plus their parents, so this only bites in a collapsed colony, where failing is the right answer.
Notes:
- Clauses 6 and 7 use numbers already in `beings.json` (12 and 28), so no duplicate tunable; the two shares are new. Both are shares of the living population, so scale does not matter.
- What the sim already exposes for colonists, and what it does not: energy, state, `returning`, position (outside or inside), `born_t`, `earth_born` and now `parent_id` and `birth_building_id` are readable at the boundary with no new state. Not exposed: conversations (the sim has none; lines are a view-only fixed list), "slept this sol" (would need a per-being per-sol flag), births this sol per habitat (derivable from `stats.births` deltas). I therefore did not add a "shared life" or "slept this sol" clause: it would need new per-step state, and the real signal (conversations, trust) is Task 4. The slot is reserved by name (`unrest` cause group).
- Ice: judged against current use, never against `ice_target`. Pop 12: 2 sols is 5.92; pop 100: 49.3. The instant value is read; a dip between boundaries can be missed (deferred, section 17).
- Early sols (estimate for the probe; the Task 1 log has 30-sol rows only): from the starting stocks and nets by hand, oxygen and food reach 0.5 of cap at about sol 5.2 and 5.4, so samples at sols 5 and 6 may fail; tolerated (4 of 40). The probe records the real first ok sol.
- Pop 0: the sample is skipped (nothing appended), so no division runs and the age is frozen (section 8.3).
### 4.3 Cause groups (private)
Each failing clause belongs to one group; a sample stores the set of groups that failed. Groups: `ice` (5); `food` (1b, 2b); `oxygen` (1a, 2a); `power` (3a, 3b, 3c); `death` (4); `unrest` (6, 7). The **dominant cause** of a window is the group that failed in the most samples; ties go in the fixed order ice, food, oxygen, power, death, unrest. It is used only to choose the sentence in the fall-back line (8.1) and is stored in `age_history`; it is never shown as a number.

## 5. Entry to Settlement (owner decision, refined as in "For the owner")
`decide` returns `settlement` when the age is `landing` and ALL of:
1. the window is full (`window_sols` = 40 samples; the earliest entry is the boundary of elapsed sol 44);
2. ok samples in the window >= `required_ok` = ceil(`entry.ok_share` x `window_sols` - STEP_EPS) = 36;
3. the last `entry.recent_ok_sols` = 3 samples are all ok;
4. **family Mars-born**: at least `entry.mars_born_min` = 5 living beings with `earth_born` false whose `parent_id` is the id of a living being, and among those beings at least `entry.mars_born_homes_min` = 2 distinct `birth_building_id` values. (Beings whose parent has died, or `parent_id` 0, are not counted. This is evaluated at the boundary, is not stored in the window, and is an entry clause only.)
5. the dwell is over: `n - last_change_sol >= min_dwell_sols` (20).
The last-3 clause blocks entry during a current failure even when the share is high. The window is never shown.

## 6. Exit (fall back) and hysteresis
### 6.1 Rule
`decide` returns `landing` when the age is `settlement` and ALL of:
1. the window is full;
2. ok samples <= `exit_ok_max` = ceil(`exit.ok_share_below` x `window_sols` - STEP_EPS) - 1 = 23 (strictly fewer than 24 ok; at least 17 not-ok sols in the last 40);
3. NOT all of the last `exit.recent_sols` = 5 samples are ok (a colony whose last 5 sols were all fine is recovering and stays);
4. the dwell is over (20 sols).
Re-entry uses section 5 unchanged. The first entry uses the "settled" line; later entries the "settled again" line.
### 6.2 Why the thresholds cannot flap
- Entry needs 36 ok, exit needs 23 or fewer: a dead band of 24 to 35 ok where nothing changes in either age. The window slides one sample per sol, so its ok count moves by at most 1 per sol. After an entry it holds at least 36 ok and needs at least 13 sols to reach 23; after an exit it holds at most 23 and needs at least 13 sols to reach 36. So a change is never undone in under 13 sols and a round trip takes at least 26.
- The dwell of 20 sols (kept because the owner asked for a minimum dwell) exceeds that 13-sol bound, so it is what actually binds: no two changes less than 20 sols apart. It is cheap insurance if the probe moves the two shares closer. The ceiling in 300 sols is floor((300 - 44) / 20) + 1 = 13; the real count is set by life support.
- Oscillation: a 50/50 square wave with a half-period under 13 sols keeps the share near 0.5: from Landing it never enters; from Settlement it leaves at most once and does not return. A noisy colony at 0.75 ok sits in the dead band.
- Why these numbers: 0.9 over 40 is the owner's. 0.6 is deliberately low: ice trouble (seeds 42, 99, 2026) is many consecutive failing sols, crossing it after about 17, while an isolated dip never does. "Last 5 not all ok" lets a recovering colony stay. 20 sols is about one Mars month.

## 7. No effect on the colony
Nobody in the sim reads the age. Ages never write stocks, beings, buildings, resources, power, births or the RNG. **The age is never an input to the sample** (so no feedback loop can form when later tasks let the age change behaviour; they must read a lagged copy and keep growth effects out of it). `stats` gains only the keys of 8.2; `Being` gains only the two birth fields. Proof: tests 15 to 17 and the five Task 1 table hashes (section 12).

## 8. Log lines, stats, pop 0
### 8.1 Log text (one fixed text per event, no random rotation)
Kind `age_began` for the four age lines, extra fields `age`, `how` in {`landing`, `settled`, `fell_back`, `settled_again`} and, for `fell_back`, `cause` (the group id). A line is assembled as: base text, then for a fall-back the cause sentence, then (for `settled`, `fell_back`, `settled_again`) the season sentence. Season sentence = `season_phrases[i]` with `i = clock.seasons.find(clock.season(t))` at the change time `t` (`Clock.season(t)` returns the name, not an index; 4 seasons in `calendar.json`, 4 phrases, a parity test checks the counts). No numbers, percentages, counts or names; no blame; no "Landing", "regressed" or "failed"; "founders" appears only in the start line, which cannot recur.
| Event | `how` | When | Text keys |
| --- | --- | --- | --- |
| Landing at the start | `landing` | at creation, after `founders_landed` (founder worlds only) | `landing.log_start` only |
| First Settlement | `settled` | first entry | `settlement.log_enter` + season |
| Fall back | `fell_back` | the section 6 change | `landing.log_fall_back` + `cause_lines.<cause>` + season |
| Settle again | `settled_again` | entry after a fall back | `settlement.log_enter_again` + season |
Texts (final, lead): start "The founders have landed at Jezero. For now, air and water and warmth are all there is to think about." Settled "Nobody is only surviving now. There are families here, and meals shared, and a place to come home to." Fall back "Hard days have come back to Jezero. The colony pulls close and gets on with it." plus one of: ice "Water is on everyone's mind again." food "Meals are thin, and the larders are watched." oxygen "The air is thin, and every breath is counted." power "The lights flicker, and the reactors are stretched." death "Too many have been lost, and the colony is grieving." unrest "People are worn down and keep close to home." Settled again "The hard stretch has passed. Meals, work and sleep keep their old order." Season: "Spring is rising over the delta." / "High summer lies over the delta." / "Autumn light is lengthening over the delta." / "Winter has settled over the delta." Example full line: "Hard days have come back to Jezero. The colony pulls close and gets on with it. Water is on everyone's mind again. High summer lies over the delta."
Cause lines name the pressure by kind, so a fall-back never looks like a bug and reads the same at 12 or 160 beings. A positive per-cause settle sentence is not adopted (every clause passes, so there is no distinguishing cause).
Not adopted: a named colonist on the settled line (the HUD has no way yet to find a being; revisit in Task 4).
### 8.2 Stats (run-wide, never windowed, never reset)
| Key | Definition |
| --- | --- |
| `stats.age` | current age id; the HUD reads this |
| `stats.age_changes` | changes after the initial Landing |
| `stats.sols_in_age` | `{landing, settlement}` elapsed sols credited to each age |
| `stats.first_settlement_sol` | elapsed sol of the first entry, null before |
| `stats.age_history` | uncapped list: `{age, how, cause (fall back only, else null), text, pop, family_mars_born, t, sol, clock_sol}`. **Every world, blank or founder, starts with one `landing` entry written at creation** (blank worlds write the entry but log nothing), then one entry per change, so `len(age_history) == age_changes + 1` always holds. Complete record (the log may evict); used by the pinned chapters strip, T10, Task 5 and a later long-absence summary |
Not in stats: window, last sample, snapshots. No progress value exists.
### 8.3 Pop 0
Age frozen (no sample, no change, no age log line). The existing death log and the existing `colony_silent` line ("The colony has fallen silent.", spec life-support 5) are the terminal line, so no new kind is needed. The HUD shows no age word while pop is 0, so it never claims an age over an empty crater; `stats.age` keeps the last value. (Owner decision, section 18.) `sols_in_age` keeps counting.

## 9. HUD (view only; the sim exposes nothing new for it beyond 8.2)
No progress value, no share, count, bar, window, "sols until", `sols_in_age` or `age_changes` anywhere. The HUD reads `stats.age`, `age_history` (its `text`, `sol`), `colony` stocks, and `advance` readout fields; it never reads `world.ages` or `last_sample`.
- **Age placement**: the end of the clock line: "Jezero Crater  |  Year 1, Sol 21  |  06:00  |  northern spring  |  Settlement". Hidden when pop is 0. This puts the age in every screenshot.
- **Pinned chapters strip**: a block above the 8-line log, showing the last `hud.chapters_shown` = 3 `age_history` entries as `sol N  text` with N = the entry's `clock_sol` (1-based, matching the clock line and the log), so routine log lines can never evict them. The Landing entry stays visible until the third change; after that the strip shows the latest three chapters, and the full history remains in `stats.age_history`. It is not a banner or pop-up. (The log itself keeps all lines, including age lines, unchanged.)
- **Resource words**: on the Oxygen, Food and Ice lines of the colony block, append `hud.low_word` ("running low") when that stock is under the same threshold as the sample clause (oxygen or food under `o2_min_fraction` or `food_min_fraction` of cap; ice under `ice_min_sols` of current use). Computed in the view from stocks and the same data keys, never from `last_sample`, never a number of failing sols, and shown regardless of age.
- **Speed readout (honest)**: the speed line reads e.g. "Speed: 1000x max (running about 5x)". Achieved speed = sim hours advanced per real second over `speed_readout_window_s` (1.0), refreshed at most every `speed_readout_refresh_s` (0.5) so it does not flicker. When achieved is below `speed_throttle_below` (0.9) of the requested speed, a second plain line reads "The colony is too large to run this fast." Dropped hours are never shown as lost time; the clock just advances slower.
- Shots (section 16 step 8): HUD at Landing and just after Settlement, plus a three-frame strip (before the fall-back, the log line, after).
- Rejected (owner decision): any speed change or pause on an age change, including an off-by-default setting.
- Deferred: view-only flash of the age line; a dev-only window overlay behind the M flag.

## 10. Tests (tests/test_ages.gd; written first, red; no test with zero checks)
Staging "good world" G: blank world, reactor, habitat and green room built (demand 7, supply 14), 12 beings of whom 6 are Mars-born with a living parent and birth habitats in 2 buildings (add a second habitat), energy 70 for all, oxygen and food at cap, ice 100, no shorts, no deaths. `sample(G)` is all-true. Boundaries are driven by setting `world.t` and calling `on_sol`.
Per clause, one test each, break only that clause and assert `last_sample` names it:
1. `oxygen` 275.0 of cap 550 passes, 274.9 fails; `food` 210 passes, 209.9 fails (cap 420).
2. `o2_net`: 28 beings on 1 green room fail the clause and 27 pass (in doubles 1.4 - 28 x 0.05 is about -2.2e-16, so never assert equality with 0.0; assert the clause verdicts only). `food_net`: isolated by lowering `colony.production.food_per_green_room` via the override seam.
3. `power_budget` 14 on 14 passes, 15 fails; `none_offline`; `no_short` fails once for the sample after a short, then passes.
4. `no_shortage_death`: `thirst`, `air`, `hunger` entries fail; an entry with cause `suffocated outside` (spaced form, as `sim/world.gd` writes it into `deaths_list`) passes; an entry from before the previous boundary does not count.
5. `ice`: ice set to exactly 2 x pop x 0.01 x 24.6597 (computed from the data in the test) passes through the `- CMP_EPS` slack; 1e-6 below fails; pop 12 and pop 100.
6. `calm`: 12 beings, 1 with energy 11.9 (share 0.083) passes; 2 (0.167) fails; 1 of 10 (exactly 0.1) passes; energy exactly 12 is not distress; a being with `is_outside()` and `returning` true counts; pop 9 with one distressed fails. `rested`: 9 of 12 at energy 28.0 (0.75) passes, 8 of 12 (0.667) fails; exactly 7 of 10 (0.7) passes, 6 of 10 fails; pop 3 needs all 3; at 160 beings the same shares give the same verdicts.
7. Pop 0: `on_sol` appends nothing, does not divide by zero, leaves the age, credits `sols_in_age`; pop returning samples again.
Window and entry:
8. Samples start at sol 5 (boundaries 1 to 4 append nothing, snapshots refresh).
9. Full ok history: `landing` at boundary 43, `settlement` at 44; exactly one `age_began` with `how` `settled`; `first_settlement_sol` 44; `age_changes` 1.
10. Tolerance edge: 36 ok / 4 not ok (not in the last 3) enters; 35 / 5 does not; four failing sols at 5 to 8 still enter at 44.
11. Last-3: 37 ok then 3 not ok blocks; 39 ok then 1 not ok blocks; entry happens exactly when the third consecutive ok arrives.
12. Family Mars-born: perfect window with 4 family Mars-born blocks, 5 enters; orphans (parent dead or `parent_id` 0) do not count; 5 in one birth habitat blocks until a second habitat is represented; Earth-born founders do not count; dead do not count.
Exit and hysteresis:
13. Dead band: 24 ok stays; 23 ok with one not-ok in the last 5 leaves; 23 ok with the last 5 all ok stays; edges on both sides of 36/35 and 24/23.
14. Dwell: entered at sol 100, then all not ok: no exit at 113 nor 119, exit at 120, one `fell_back` line; after a fall-back with an injected perfect window, entry blocked at `last_change_sol + 19`, allowed at +20. Pure `decide` synthetic: 50/50 square waves of period 2, 3, 5, 8, 12, 24 over 3,000 sols, zero changes from Landing, at most one (to Landing, never back) from Settlement; 13 ok / 13 not ok repeated: changes never exceed floor(sols / 20); data sanity: (36 - 23) >= 13, `min_dwell_sols >= 13`, `exit.ok_share_below < entry.ok_share`.
Cause and text:
15. Dominant cause: window with 20 ice failures and 5 food failures gives `ice`; equal counts follow the tie order; `unrest` and `death` groups map as in 4.3; the fall-back line contains the matching cause sentence.
16. Landing: a founder world logs `founders_landed` then one `age_began` `landing` with the data text and has one `age_history` entry; a blank world logs nothing but also has exactly one `landing` history entry. A staged settle, fall back, settle again on a **blank** world logs the three texts in order with the right `how`, `cause`, the season sentence for `clock.seasons.find(clock.season(t))`, and has an `age_history` of four entries (Landing plus three changes) each carrying `text`; `len(age_history) == age_changes + 1`. For every combination of cause (6) and season (4) and each of the three change lines the assembled text has no digit and no `%`, and never contains "Landing", "regress" or "fail" (case-insensitive); "founders" occurs only in the start line. `first_settlement_sol` stays at the first value; `sols_in_age` sums to the boundaries seen.
Purity:
17. Seed 42, 10 sols: worlds with `ages_enabled` true and false give equal old `stats` keys, equal beings (id, building, state, energy) and equal stocks, and then the next 1,000 draws from each world's `rng` are equal (SimRng has no state accessor, so draws are compared, not state); two same-seed ages-on worlds are identical including `age_history`; on a staged world `on_sol` leaves stocks, buildings and beings untouched and the next 100 draws equal those of an untouched copy. A newborn has `parent_id` equal to a being that was in its habitat, and `birth_building_id` equal to the habitat; a founder has `parent_id` 0; with `here` forced empty the guard gives `parent_id` 0 and no extra draw. That the draw order equals the Task 1 build's is not checked here (no in-tree baseline); the five table hashes of section 12 prove it.
18. Key-path parity (section 13), including no Council, Dome or City key in `ages.json`.
19. HUD: the age part of the clock line is the name only, with no digit; absent at pop 0; chapters strip shows at most `hud.chapters_shown` entries and keeps the Landing entry after 100 routine lines; resource words appear exactly at the sample thresholds (edge test) and the HUD source reads no `world.ages`, `last_sample`, `sols_in_age`, `age_changes`.
20. Advance budget and speed readout (section 11).

## 11. `advance()` wall-time budget and step profile (owner carry-over; last steps of the plan)
View-path only; a step does exactly what it does today.
- `data/sim.json` gains `advance_budget_ms` = 8.0 (a 60 fps frame is 16.7 ms; the view model takes about 1.3 ms and drawing the rest; so the sim gets about half). 0 means one step per call. `max_steps_per_frame` (2000) stays as a hard cap.
- Rule: `advance(hours)` adds to the accumulator and steps while a step is due, reading an injected monotonic millisecond clock (default the engine tick counter) at entry and after each step; it stops when elapsed >= `advance_budget_ms` or the cap is reached. At least one step runs whenever one is due. A call may overshoot by one step.
- Leftover is **dropped**, as `max_steps_per_advance` does today: at the moment the loop stops with a step still due, the accumulator's value (which may include an earlier sub-step remainder) is added to `advance_dropped_h` on the world, and the accumulator is set to 0. Carrying would grow an unrepayable debt. Neither the counter nor any wall-time figure goes into `stats`, the log or any hashed state.
- Speed labels are a maximum, not a promise: "1000x max". The achieved speed readout of section 9 reports the truth. At 164 beings (4.7 to 6.8 ms per step) and 8 ms, expect about 3x to 6x whatever the preset.
- `data/sim.json` also gains the three speed-readout keys of section 9 (`speed_readout_window_s` 1.0, `speed_readout_refresh_s` 0.5, `speed_throttle_below` 0.9), read by the view only.
- Step profile: `tools/step_profile.gd` (timers outside `sim/`), report `docs/perf/task-3-step-profile.md` with the top 3 phases; a fix is allowed only if the five old-column table hashes stay byte-identical.
- Tests: budget 0 takes one step; a fake clock advancing 3 ms per read with budget 8 stops after 3 steps; the cap is never exceeded; a clock that never reaches the budget gives the same steps and the same world state as an unbudgeted run; after a stop, `advance_dropped_h` grew by exactly the accumulator value just before it was zeroed (a test pre-loads a sub-step remainder to check it is included) and the accumulator is 0; the readout shows no throttle line when achieved >= 0.9 of requested, shows it below, and the line does not change faster than the refresh interval.

## 12. Balance integration and proof of no behaviour change
- The balance table gains one trailing column `age` (header `age`, values `L` or `S`) separated by one space. Removing it means deleting the final whitespace-separated field of the header and each row with the space before it. Earlier columns keep widths and values.
- **Proof**: the Task 1 table body hashes (`String.sha256_text` of the body, which excludes the `#` header lines): 02032b23... (seed 42), 830c7d0c... (seed 7), 0e3e83a7... (seed 99), bca6eb2c... (seed 1234), 2645033a... (seed 2026) must be reproduced exactly with the column removed, by the Task 1 command for each seed. The header `data_hash` changes by design (new keys; `ages` added to the hashed list). A differing hash means a behaviour change and the step is rejected. The two new Being fields do not enter the table. Coverage: the hashes cover only what the 30-sol rows print (stocks, pop, births, deaths, power, buildings, trips, energy and window minima at each row). Everything else (old `stats` keys, every being's state and energy, stocks between rows, the RNG stream) is covered by test 17 at 10 sols; together they are the proof.
- **T10** per seed, 300 sols, from `stats`, never the log: (1) `first_settlement_sol` not null and in `balance.settle_sol_min` 40 to `settle_sol_max` 150 (the lower bound is structural: 44); (2) `age_changes <= balance.max_age_changes` (4, provisional); (3) every gap between consecutive `age_history` sols is >= `min_dwell_sols`; (4) `len(age_history) == age_changes + 1` and every entry has `how`, `text`; (5) reported, not judged: first Settlement sol and spread, `age_changes`, `sols_in_age`, age at sol 300, sols and causes of each change. Falling back is not a failure.
- Estimates to be replaced by the probe: seeds 7 and 1234, 1 change; seeds 42 and 99, 2 (settle about sol 44 to 55, fall back about 155 to 175 with cause `ice`); seed 2026, 2 or 3. If any seed shows changes within 40 sols of each other, tighten the exit share or the dwell, one parameter per run. A seed over 4 changes needs a reason from the sim before the number is raised.
- T1 to T9 unchanged. `life-support-power.md` section 13 gains a pointer here and section 16 gains the stats keys and the `age_began` kind (test engineer).

## 13. Tunables (JSON key path, unit, starting value, source; E = estimate for the probe to calibrate)
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| ages.landing.name / settlement.name | text | Landing / Settlement | HANDOFF 7 |
| ages.landing.log_start, log_fall_back; ages.settlement.log_enter, log_enter_again | text | section 8.1 | lead |
| ages.cause_lines.ice / food / oxygen / power / death / unrest | text | section 8.1 | lead |
| ages.season_phrases | list of 4 text, in `calendar.json` season order | section 8.1 | lead |
| ages.sample.from_sol | elapsed sol | 5 | owner |
| ages.sample.window_sols | sols | 40 | owner |
| ages.sample.o2_min_fraction / food_min_fraction | fraction of cap | 0.5 / 0.5 | plan |
| ages.sample.net_above | per h | 0.0 | plan |
| ages.sample.ice_min_sols | sols of use | 2.0 | plan, E |
| ages.sample.shortage_causes | list | air, thirst, hunger | life-support 9.3 |
| ages.sample.distress_share_max | share of living | 0.10 | lead, E |
| ages.sample.rested_share_min | share of living | 0.70 | lead, E |
| ages.entry.ok_share | share of window | 0.9 | owner |
| ages.entry.recent_ok_sols | samples | 3 | owner |
| ages.entry.mars_born_min | beings (with a living parent) | 5 | owner |
| ages.entry.mars_born_homes_min | distinct birth habitats | 2 | lead, E |
| ages.exit.ok_share_below | share of window | 0.6 | lead, E |
| ages.exit.recent_sols | samples | 5 | lead, E |
| ages.min_dwell_sols | sols | 20 | lead (owner asked for a minimum dwell), E |
| ages.hud.chapters_shown | entries | 3 | lead |
| ages.hud.low_word | text | running low | lead |
| ages.balance.settle_sol_min / settle_sol_max | elapsed sol | 40 / 150 | owner |
| ages.balance.max_age_changes | changes per 300 sols | 4 | lead, E |
| sim.advance_budget_ms | ms | 8.0 | lead, E |
| sim.speed_readout_window_s / speed_readout_refresh_s | s | 1.0 / 0.5 | lead |
| sim.speed_throttle_below | fraction of requested | 0.9 | lead |
Reused, not duplicated: `beings.energy.exhausted_turn_back` (12), `beings.energy.sleep_below` (28), `colony.consumption.ice_per_being`. Not data: the ids `landing` and `settlement`, clause and group names and the group tie order, `STEP_EPS` (existing, 1e-9, used in the window-count ceilings), `CMP_EPS` (new, 1e-9, the comparison slack of clauses 5 to 7), "pop 0 skips the sample". The `balance.*` block is read by `tests/balance_lib.gd` only; the `hud.*` and speed keys by the view only; everything else non-balance by `sim/ages.gd`.

### Key-path list (machine-readable; one leaf per line)
Same rules as life-support-power.md section 12: parsed between the `keys:` fence markers, checked both ways for `ages.json` (arrays and strings are leaves). The `sim.` lines are existence checks only.
```keys:
ages.landing.name
ages.landing.log_start
ages.landing.log_fall_back
ages.settlement.name
ages.settlement.log_enter
ages.settlement.log_enter_again
ages.cause_lines.ice
ages.cause_lines.food
ages.cause_lines.oxygen
ages.cause_lines.power
ages.cause_lines.death
ages.cause_lines.unrest
ages.season_phrases
ages.sample.from_sol
ages.sample.window_sols
ages.sample.o2_min_fraction
ages.sample.food_min_fraction
ages.sample.net_above
ages.sample.ice_min_sols
ages.sample.shortage_causes
ages.sample.distress_share_max
ages.sample.rested_share_min
ages.entry.ok_share
ages.entry.recent_ok_sols
ages.entry.mars_born_min
ages.entry.mars_born_homes_min
ages.exit.ok_share_below
ages.exit.recent_sols
ages.min_dwell_sols
ages.hud.chapters_shown
ages.hud.low_word
ages.balance.settle_sol_min
ages.balance.settle_sol_max
ages.balance.max_age_changes
sim.advance_budget_ms
sim.speed_readout_window_s
sim.speed_readout_refresh_s
sim.speed_throttle_below
```
`SimData.ages()` is the accessor; `data_hash` in `tests/balance_lib.gd` adds `ages`. The test also checks `season_phrases` has exactly as many entries as `calendar.json seasons`.

## 14. Calibration probe (tools/age_probe.gd, read-only)
Built after `sim/ages.gd`, the hook and the two Being fields (section 16: implementation is step 4, the probe step 5), so it runs the real code with the starting values of `data/ages.json`. Calibration that follows from it edits `data/ages.json` only, never code. Replays seeds 42, 7, 99, 1234, 2026 to sol 300 with the real hook. Per seed it records, once per sol from sol 1, the raw value of every clause (oxygen/cap, food/cap, o2_net, food_net, demand, supply, offline count, shorts since last, shortage deaths since last, ice in sols of use, distress share, rested share, family Mars-born count, birth habitats among them, pop), and via its own per-step observer the minimum ice in sols of use over each sol (to measure the missed-dip question). It changes no data, state or RNG, and checks itself: the age history recomputed from the stored samples with the shipped numbers equals the live `stats.age_history`.
Per seed it writes `docs/balance/task-3-calibration.md`:
1. Crossing sols: first ok sample; first sol the entry rule fires; the age history with `how`, `cause` and sol; and which entry clause was last to pass (family Mars-born, window share, recent).
2. Sols in each age, age at sol 300, `age_changes`.
3. Flap report: changes after the first, shortest gap, fall-back-then-reentry pairs within 40 sols (a flap = any change within `window_sols` of the previous).
4. Failure statistics per 50-sol band and per clause: count, and count where it was the only failing clause. Expected: only `ice` after sol 120 on seeds 42, 99, 2026; `calm` and `rested` expected near zero. If either fails on more than 10% of sols before sol 120, the threshold is wrong, not the colony.
5. One-at-a-time sweeps replayed from stored samples (no grid): window {30, 40, 50}; exit share {0.5, 0.6, 0.7}; dwell {10, 20, 30}; `ice_min_sols` {1, 2, 3}; `rested_share_min` {0.5, 0.7, 0.9}; each reporting first Settlement sol, change count, shortest gap.
6. Missed dips: sols where the instant ice read was ok but the per-sol minimum was under `ice_min_sols`.
7. Microseconds per `on_sol` call (expected well under 50).
The probe sets the final numbers for the E rows of section 13.

## 15. Edge cases
- Pop 0: no sample, age frozen, no age line (8.3). Mars-born family count falling while in Settlement: nothing happens (entry-only clause).
- Window not full: no entry and no exit.
- Several events in one sol (short and death) just fail the sample; clauses are independent.
- A change is always Landing to Settlement or back, at most one per boundary.
- A building back online on the boundary step counts as online (read after phase 3).
- `ages_enabled` false: no sample, no log, no stats change.
- Log eviction at 500 entries changes no age value and no HUD chapter (strip reads `age_history`).
- Dropped hours from the budget never change the rules; they count sols from sim time.
- `parent_id` of a being whose parent died stays set; "alive" is looked up at the boundary.

## 16. Build order (replaces the plan's step order where it differs)
Age line first, so nothing else can hold it up. Each step depends only on earlier ones:
1. Spec and data [this].
2. Review.
3. `tests/test_ages.gd`, red.
4. Implementation with the starting values of `data/ages.json`: the two Being fields and the null guard in `_create_newborn`, `SimData.ages()`, `sim/ages.gd` (`sample`, `decide`, `dominant_cause`, `on_sol`), the hook, stats and log. `test_ages.gd` green except tests 19 and 20.
5. `tools/age_probe.gd` and `docs/balance/task-3-calibration.md`. It runs the step 4 code. Any recalibration of the E rows of section 13 edits `data/ages.json` only, one parameter per change, recorded in the changelog.
6. HUD: age in the clock line, chapters strip, resource words (test 19 green). It must come before step 7, because the balance step runs the full suite including test 19.
7. Balance column and T10, balance run with the Task 1 hash proof (`docs/balance/task-3-log.md`).
8. Shots.
9. Final review of the age work.
10. Step profile.
11. `advance()` budget and speed readout (test 20 green).
Steps 10 and 11 are the owner's carry-over and come last so the age work can be reviewed and checked off without them; if time runs out they are the first to move to the next task (feel review cut order, point 1) unless the owner says otherwise.

## 17. Design review record
Reviewers: emergence (Will Wright lens), feel (Eric Barone lens), clarity (Karoliina Korppoo lens). Decision key: A adopted, AM adopted modified, D deferred, R rejected.
### Emergence
| # | Item | Decision |
| --- | --- | --- |
| E-M1 | Add colonist-derived clauses as shares of living population: distress, rested, shared life | AM. Adopted `calm` and `rested` (clauses 6, 7), shares, same 36/40 structure. "Shared life" not adopted: the sim has no conversations, and a per-sol gathering counter needs new per-step state; the real signal is Task 4. Flagged "For the owner". |
| E-M2 | Mars-born as family, record parent_ids | AM. Count of Mars-born with a living parent, from at least 2 birth habitats; records `parent_id` (single parent, as the sim picks one) and `birth_building_id` at birth. `born_t` already is the birth age. |
| E-M3 | Fall-back must say which pressure | A. Dominant cause group, per-cause sentence (also clarity M1). |
| E-S4 | Gentle fall-back wording | A (feel M1). |
| E-S5 | Landing is sticky; Task 5 must not gate on entry count | A as a spec note (section 2): Task 5 reads `age_history`. |
| E-S6 | God has no lever on the ice clause; give an indirect one | AM. Colonist clauses give an indirect lever only in principle; I do not claim a lever exists in Task 3. The hand-off is left to Task 5 and later god powers; not designed here. |
| E-S7 | Record min ice over the sol from the start | D. Needs per-step state in `ages`, against the smallest-scope rule. The probe measures missed dips with its own observer (section 14.6); add it to the sim only if the probe shows it matters. |
| E-S8 | Pop 0 frozen plus a separate terminal line | A. The existing `colony_silent` line is that line; no new kind (section 8.3). |
| E-I | History carries cause, pop, mars_born, births, deaths by cause, ids | AM. `age_history` carries cause, text, pop, family_mars_born. Births and deaths in the age are derivable from `deaths_list` and `stats.births` by sol; ids of Mars-born not stored. |
| E-I | Record parent_ids and birth_age | A (above). |
| E-I | Dwell from the steady-trait mean | D, later task. |
| E-note | Feedback loops for later; hidden gates named as floors | A. Section 7 forbids the age as a sample input and requires a lagged read. The 5 Mars-born clause and the sol 44 floor are named as floors in "For the owner" and 5. |
### Feel
| # | Item | Decision |
| --- | --- | --- |
| F-M1 | Fall-back line gentle, never "Landing/regressed/failed" | A, wording chosen by the lead (8.1), candidate (b) with a cause sentence. |
| F-M2 | Pop 0: freeze, log nothing new | A (8.3). |
| F-M3 | No "founders" in recurring lines | A. Only the start line says it. |
| F-S4 | Season phrase; named colonist on the settled line | AM. Season phrase adopted on the three change lines. Named colonist deferred (no way for the HUD to find a being; Task 4). |
| F-S5 | Pacing about three lines in 300 sols; log panel must hold the line at 100x | A, and answered by the pinned chapters strip (clarity M1B). |
| F-S6 | Dwell is nearly invisible work | R as to dropping it: the owner asked for a minimum dwell; kept, stated as the binding limit. |
| F-scope | Cut order: (1) budget and profiling, (2) probe grid, (3) test families, (4) dwell, (5) exit.recent_sols, (6) age_history | (1) AM: kept (owner carry-over) but moved to the last two steps of the plan (section 16). (2) A: one-at-a-time sweeps. (3) A: tests 14 keeps square waves, the adversarial run and data sanity; the statistical iid test and the period-80 family are dropped. (4) R (owner). (5) R: it is the recovery logic and in the owner's own example. (6) R: the chapters strip, T10, cause and Task 5 need it. |
| F-note | No banner or pop-up | A. The strip is plain text. |
### Clarity
| # | Item | Decision |
| --- | --- | --- |
| C-M1 | Cause-blind lines get lost; Fix A (dominant clause text) and Fix B (pinned strip) | A and A. Strip size 3 from `age_history`. |
| C-M2 | HUD speed labels dishonest; show achieved speed and a throttle line | A. Labels read "max"; readout and throttle line with refresh limits (section 9). |
| C-M3 | Empty colony reading Landing | AM. HUD shows no age word at pop 0; the existing `colony_silent` line is the terminal line (no new `colony_ended` kind). |
| C-S4 | Chapters strip, flash, auto-slow, long-absence summary | A strip. Flash D. Auto-slow R (owner decision: the game never changes speed). Long-absence summary D (later); `age_history` stays complete. |
| C-S5 | Qualitative resource word on HUD lines | AM. Adopted as "running low" computed in the view from the sample thresholds; never from `last_sample`; no counts. |
| C-S6 | Settle wording not a reward; fall-back not blaming; avoid "easy days are over" | A. |
| C-S7 | Landing line scrolls away | A (strip). |
| C-S8 | Age in the clock line | A. |
| C-S9 | Scale-neutral cause text | A (shares in clauses 6 and 7; cause lines). |
| C-I10 | Pair the age with the season word | A (it already follows the season in the clock line). |
| C-I11 | Dev window overlay behind M | D (optional later). |
| C-I12 | Three-frame shot strip | A (step 8). |
| C-M1 detail | Entry names a positive cause | R: all clauses pass at entry, there is no distinguishing cause. |
### Dissent and tensions resolved
- Emergence wants more colonist clauses and records; feel wants the smallest scope. Resolved: two clauses and two fields (small, RNG-free, both fixed from reviews' must-fixes) and no conversation clause or per-step state; the budget is last in the order, not removed (owner decision).
- Clarity wants a pinned strip, cause lines, an honest speed readout; feel wants a quiet log and no banner. Resolved: all of clarity's must-fixes, delivered as plain text (strip and cause sentence, no pop-up); auto-slow rejected by the owner.
- Feel cuts `age_history`; emergence, clarity and T10 need it. Kept.
- Emergence offers a stronger Mars-born rule (family or two habitats); I take both (living parent AND two habitats), the stricter, because early births come from one or two habitats.

## 18. Owner decisions (resolved)
The five questions posed in revision 2 were answered by the owner; items 1 to 4 are resolved and applied in this spec, and item 5 stays open for Task 5 with the default stated. Only item 5 remains for the owner.

### Owner decisions on the open decisions (Herby, 2026-10-05)
1. **Colonist clauses:** adopted as drafted (`calm` and `rested` join the sample). The probe sets the shares from measurements.
2. **Family rule:** a living parent and at least 2 distinct birth habitats (the designer's version). The sim records `parent_id` and `birth_building_id` on each newborn, with no RNG draw.
3. **Pop 0:** the age is frozen, the HUD shows no age word, and the existing "fallen silent" log line is the only message.
4. **Speed on an age change:** the game never changes speed.
5. **Task 5 gate:** not decided yet; Task 5 reads `age_history` and decides itself (the designer's recommendation stands as the default until Task 5 is designed).

## Changelog
- 2026-10-05: first version (game-designer). Reviewer sign-off: pending.
- 2026-10-05: revision 2 (lead designer) after the three assistant reviews: colonist clauses `calm` and `rested`; family Mars-born (parent and birth habitat recorded); cause-aware fall-back line and final log texts with a season sentence; pop 0 resolved; `age_history` enriched; HUD placement, chapters strip, resource words, speed readout; probe reduced to one-at-a-time sweeps; tests reduced and extended; build order puts the budget and profile last; design review record; open decisions.
- 2026-10-05: owner decisions recorded (section 18): colonist clauses adopted; family rule = living parent and 2 birth habitats; pop 0 frozen with no HUD age word and the existing fallen-silent line; speed never changes on an age change (auto-slow rejected); Task 5 gate undecided, Council reads `age_history` by default.
- 2026-10-05: revision 3 (lead designer) after code-review findings B1 to B4 and nine non-blocking items. B1: build order puts implementation (Being fields, `sample`, `decide`, hook) in step 4 before the probe in step 5, the probe changes data only; HUD (step 6) before balance (step 7) stated as a dependency; profile and budget stay last. B2: ice clause is `ice >= ice_min_sols x pop x ice_per_being x sol_hours - CMP_EPS`; clauses 6 and 7 compare counts cross-multiplied; `CMP_EPS` (1e-9) named as a non-data constant. B3: test 2 asserts clause verdicts, never `o2_net == 0.0`. B4: test 17 compares the next N rng draws of cloned worlds instead of rng state, and leaves the Task 1 draw order proof to the table hashes; every world (blank too) starts `age_history` with a Landing entry, so test 16 on a blank world expects four entries and T10(4) is well defined. Non-blocking: owner decisions applied (section 9 speed setting rejected, section 18 resolved, header text); season index = `clock.seasons.find(clock.season(t))`; strip shows `clock_sol` and states honestly that Landing stays visible only until the third change; distress uses `Being.is_outside()`, tiny-population behaviour documented, exact 7-of-10 and 1-of-10 boundary tests; dropped hours = accumulator value when zeroed; table-hash coverage stated (rows only; test 17 covers the rest); early-sol figure marked as an estimate; Task 4 note on child parents; null guard for the parent pick; the test uses the spaced cause `suffocated outside`. Reviewer sign-off: pending re-review.
- 2026-10-05: reviewer sign-off (step 2): approved at revision 3 after re-review.
