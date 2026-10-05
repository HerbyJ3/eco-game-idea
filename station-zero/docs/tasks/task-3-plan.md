# Task 3 Plan: Age system (Landing and Settlement, announced in the log)

Source of truth: station-zero-handoff/HANDOFF.md (sections 1, 2, 7, 8, 9, 10). Tasks 0, 1, 2 are done; Task 4 is not started.
Rules in force: design before code, headless tests before visuals, every tunable in data/ (new `data/ages.json`), seeded RNG (the age system never draws from `SimRng`), one balance parameter per run, each step is a commit that runs. Test command: `godot --headless --path station-zero --script res://tests/run_tests.gd`.
Facts the numbers below rest on (Task 1 log, spec life-support-power.md sections 4, 13, 16): oxygen and food sit at their caps for the whole 300 sols on all five seeds (nets stay positive because a green room is built at a 0.4 net floor); zero power shorts and zero air turn-backs; ice is the only pressure (dry on seeds 42, 99, 2026 from about sol 120 to 180, thirst deaths from sol 180 to 240); ice target scales with pop, but the stock stays under 0.6 of target on those seeds, so "ice above a fraction of target" would never fire. Per-sol crossing figures below are ESTIMATES read from 30-sol rows; step 4 replaces them with measured values before any number is locked.

## 1. Scope
IN:
- `sim/ages.gd` (replaces the placeholder): reads sim state, never writes colony state, never uses `SimRng`. Evaluated once per sol boundary (inside `_sol_boundary`, so the cost is O(1) per sol, not per step).
- Landing and Settlement defined as data in `data/ages.json` (id, display name, log text, entry test parameters). Landing is the starting age and is announced at world creation.
- Settlement entry is an emergent test over sim state (section 4): a sliding window of per-sol samples with a tolerance and a latch. No timer, no counter, no progress value is exposed anywhere.
- Log event kind `age_began` (`{age, text}` plus the usual t, sol, clock_sol). Stats (not capped like the log): `stats.age` (current id), `stats.ages` (list of `{age, t, sol}`), `stats.first_settlement_sol` (never windowed, like `first_birth_sol`).
- HUD (text HUD in `view/main.gd`): current age name only. No percentage, bar, countdown or "sols until". A test asserts the HUD string for both ages contains the name and no digit-carrying age field.
- Headless tests and balance integration: `tests/balance_run.gd` and `tests/balance_lib.gd` gain an `age` column (L or S) and target T10 (section 7). Old columns must be unchanged.
- Carry-forward items chosen in section 2.
OUT (Task 3 does NOT contain):
- Council, Dome and City ages: no data entries, no stubs, no placeholder conditions. Dome proposals, support, diplomacy and factions are Task 5. Relationships and trust are Task 4; Settlement's "relationships and trust form" exit is therefore not built.
- Any change to beings, building choice, births, mining, power or stocks because of the age (section 5).
- New art, sound or a banner animation for the age event; the log line and HUD name are the whole presentation.
- Age regression (section 6, A1).

## 2. Task 2 carry-forward items
| Item | Task 3? | Reason |
| --- | --- | --- |
| Profile `SimWorld.step()` at 164 beings (4.7 to 6.8 ms) | IN, measurement first, fix only if output-identical | Ages add per-sol work, so we need the baseline. Fixes allowed only if the seed 7 and seed 42 table hashes (old columns) stay byte-identical. A fix that changes behavior is not allowed here. |
| `advance()` wall-time budget | IN | Pure view-path change: it changes how many steps run per frame, never what a step does. Add `advance_budget_ms` to `data/sim.json`, an injectable clock seam for tests, always at least 1 step per call, leftover time carried or dropped by one documented rule. 1000x then degrades into slower sim time instead of a multi-second frame. No balance impact, so not Herby's call; the speed-preset labels (what "1000x" means when it cannot be sustained) are a small UX call, see section 8. |
| Align sim night window (21:30 to 05:30) with visual dusk (19:00 to 21:30) | DEFER | It changes sleep timing, lamps and energy, so target 8 and likely births change; it needs a full five-seed rerun and Herby's decision. Doing it in the same task as the age test would mix two balance causes and spoil calibration of the Settlement crossing (rule: one parameter per run). Do it as its own balance task after Task 3, or as the first step of Task 4. |
| Footprint `foot_side`, art.json constants pass, sleeping pose, extra faces | DEFER | View polish, unrelated to ages. |

## 3. Steps (each a runnable commit)
1. [game-designer] `docs/specs/ages.md` and `data/ages.json`: sample definition, window, tolerance, thresholds, latch, log text, stats keys, HUD wording, balance target T10, key-path list. Check: every number in the spec is a key in `data/ages.json`; Council and later are absent.
2. [code-reviewer] Read-only spec review against HANDOFF sections 1 and 7 (no meter, emergent, announced in log), determinism (no RNG, no wall clock), and the Task 1 facts above. Sign-off in the spec changelog. Check: approved or numbered findings fixed.
3. [sim-test-engineer] `tests/test_ages.gd`, written first and red. Blank worlds with staged state: (a) the condition is false when any single clause fails (one test per clause: oxygen, food, ice days, power, shortage death, Mars-born count); (b) true only after the window is full of passing sols; (c) tolerance: up to the allowed share of failing sols still passes, one more fails; the last-sols clause blocks entry during a current failure; (d) once Settlement fires it logs exactly once and never again, even if conditions collapse (latch); (e) log entry has kind `age_began`, stats list matches, `first_settlement_sol` set once; (f) world creation logs Landing; (g) the age check consumes no RNG (rng state equal with and without `ages` evaluated), and two same-seed worlds are identical; (h) key-path parity for `ages.json`; (i) HUD string shows name only; (j) `advance()` budget: budget 0 still does one step, a fake clock ends the loop, steps taken are identical to the unbudgeted run for the same total hours. Check: new file runs and fails for the right reasons; old 383 tests unchanged.
4. [sim-test-engineer] Calibration probe `tools/age_probe.gd` (read-only): replays the five seeds to sol 300 and prints per-sol values of every clause plus the sol at which candidate windows (30, 40, 50) and tolerances (1.0, 0.9) would fire. Writes `docs/balance/task-3-calibration.md`. Check: measured crossing sols for all five seeds in that file; no data change. Step 1's numbers are then locked or revised (one change recorded in the spec changelog).
5. [godot-engineer] `sim/ages.gd`, `data/ages.json`, `SimData.ages()`, hook in `_sol_boundary`, log and stats, Landing at creation. Check: `test_ages.gd` green apart from HUD and budget tests; full suite green; seed 7 and 42 10-sol determinism tests green.
6. [godot-engineer] Profile `SimWorld.step()` at about 164 beings (seed 42 at sol 300, as in the Task 2 perf run), per-phase timers kept in `tools/step_profile.gd` (not in sim/). Report in `docs/perf/task-3-step-profile.md` with the top 3 phases. Fix only if the old-column table hash is byte-identical. Check: report exists; hash proof if any fix.
7. [godot-engineer] `advance()` wall-time budget plus `advance_budget_ms` in `data/sim.json`; HUD wiring in `view/sim_host.gd` and `view/main.gd`. Check: budget tests green; `perf_run.gd` 1000x scenario run with a short `--speed-frames`, achieved sim speed and frame time recorded (expected: frames stay under budget; speed degrades gracefully).
8. [godot-engineer] HUD shows the age name. Check: HUD test green; `--quit-after 5` on the main scene prints no errors.
9. [sim-test-engineer] Balance integration: age column and T10 in `tests/balance_lib.gd` and `balance_run.gd`; update `docs/specs/life-support-power.md` section 13 pointer. Check: run seed 7 for 60 sols and see the column; T1 to T9 outputs unchanged except the table text gains the column.
10. [sim-test-engineer] Balance run: five seeds, 300 sols, no data changes (`docs/balance/task-3-log.md`): per-seed Settlement sol, T10 verdict, proof that old columns are byte-identical to the Task 1 baseline (compare the table with the age column removed against the Task 1 hashes: 02032b23..., 830c7d0c..., 0e3e83a7..., bca6eb2c..., 2645033a...). If T10 fails, change one parameter per run (window, then tolerance, then ice days) and record each.
11. [godot-engineer] View check: shots of the HUD at Landing and just after Settlement (`tools/shots`), plus the log panel line if the HUD shows the log. Check: two PNGs, non-blank, the main session reads them.
12. [code-reviewer] Final review: sim state unchanged by ages (diff of sim/ outside ages.gd and the hook is empty except the budget and log hooks), no tunable literal in code, no RNG, no progress value anywhere in view or stats, Council and later absent, tests meaningful (no zero-check), balance log honest.
13. [project-manager] Check off Task 3 in HANDOFF.md section 8 with what changed and what we learned; Task 4 not started.

## 4. The Settlement condition
Design: each sol boundary takes one sample, `ok` or `not ok`, from sim state. The colony is "settled" when a sliding window of the last N samples is mostly `ok`, the most recent samples are `ok`, and the Mars-born clause holds. The window is a private history, never exposed or displayed. Once true it fires once (latch).
A sample is `ok` when all of these hold at the boundary (all thresholds in `data/ages.json`):
1. Oxygen stock >= 0.5 of `o2_cap` and food >= 0.5 of `food_cap` (stocks sit at cap in all baselines; the 0.5 line is crossed by about sol 5 to 6).
2. `o2_net` > 0 and `food_net` > 0 (a real surplus, not just a full tank).
3. Power: demand <= supply, no building offline, no short during the past sol (zero shorts in baselines, so this clause is cheap insurance).
4. No shortage death (air, thirst, hunger) during the past sol.
5. Ice is not a worry: ice stock >= 2 sols of current use, `ice / (pop x ice_per_being x sol_hours) >= 2` (the existing 3-sol floor idea from `stock_days_floor_sols`, slightly looser). Ice as a fraction of target is deliberately not used (stuck under 0.6 on the dry seeds).
Window rule: N = 40 sols, at least 90% of the N samples `ok`, and the last 3 samples all `ok`. Samples start at sol 5 (as `STATS_FROM_SOL`), so Settlement cannot fire before about sol 45.
Clause outside the window: at least 5 Mars-born beings alive (`earth_born` false). It makes "families" the content of Settlement without a counter: first births come at sol 13 to 26 and pop is 10 to 19 by sol 30, so it holds on all seeds.
How ice pressure is treated: ice running out later is pressure, not failure (owner decision), so the age is a latch; ice only gates entry. A dry spell inside the window is forgiven up to 10% of sols (4 of 40).
Estimated crossing under the recommended rule (to be measured in step 4):
| Seed | Reason | Estimated Settlement sol |
| --- | --- | --- |
| 42 | ice min 45 to 86 through sol 120, pop 52 at sol 90 (about 7 sols of water) | 45 to 55 |
| 7 | ice rich all run (min 45.6, 130+ after sol 60) | 45 to 50 |
| 99 | ice min 42 to 88 through sol 120; first ice trouble about sol 150 | 45 to 55 |
| 1234 | ice never below 50 | 45 to 50 |
| 2026 | one dip to 15.1 in sols 30 to 60 (about 2.4 sols of water at pop 26), clean after sol 60 | 50 to 100 (tolerance decides) |
T10 target (proposed): Settlement reached on all five seeds between sol 40 and sol 150, never before sol 40, announced exactly once, spread (latest minus earliest) reported. Landing must last at least the window, so the age is a stretch of life, not a blip.
Alternatives:
- B, strict streak: N consecutive sols where every clause holds, any failure resets, ice must be above 0. Simplest to explain and test. Trade-off: one blip resets the whole run, so seed 2026 slides toward sol 100 and seeds that hover near the ice line can be pushed past the window; weak "steady" meaning, and the only anti-flap is the reset itself.
- C, smoothed margin with two thresholds (Schmitt trigger): an exponential average of surplus margin per resource, enter above 0.35, leave below 0.2. Smooth and no resets. Trade-offs: the average is a counter in disguise (hard to explain as emergent), more tunables, and leaving needs regression, which we do not build; harder to test one clause at a time.
Recommend A (windowed samples with tolerance, last-3 clause and latch): it reads as "a long stretch that was mostly fine and is fine now", is testable per clause, forgives one-off dips, and matches the owner's ice decision.

## 5. Effect of the age on the colony
Recommend announce only, no behavior change. Reasons: (1) Task 1's balance (all targets pass on five seeds) stays valid, so the Task 3 balance run is a pure measurement and the old columns must be byte-identical; (2) HANDOFF section 1: nothing counts toward a goal and the age is a name for what the people already did, not a lever that changes them; (3) section 2 "influence not command": an age that unlocks or forces behavior is a command from the system; (4) the real effects belong with the systems that need them (Task 4 trust, Task 5 council can read the age as context). The alternative (a small effect, for example Settlement widening the habitat building pool or shifting `birth.base_chance`) would add one balance parameter and force a rerun of T1 to T9; deferred, and only with Herby's decision.

## 6. Ambiguities and recommended resolutions
- A1 Regression: can the colony fall back to Landing? Resolve: no. Ages are history (latch). Data flag `can_regress: false` documents it; a future "hard times" log event can carry crisis without changing the age. Herby to confirm (section 8).
- A2 Sample timing: once per sol boundary in `_sol_boundary`, reading the state at that step; "past sol" clauses use per-sol flags reset at the boundary (shorts and shortage deaths), not the capped log.
- A3 Window source: stats and the private history, never the log (cap 500).
- A4 Elapsed sol vs `clock_sol`: windows use elapsed sol (`sol()`), the log carries both, as today.
- A5 Landing announcement: logged once at creation after `founders_landed`; kind `age_began`. Blank test worlds log nothing (as for founders) unless a test asks.
- A6 Hash impact: the table text gains a column, so its sha256 changes by design. The proof of no behavior change is the Task 1 hashes on the table with the age column removed, plus `stats` equality on old keys.
- A7 Colony extinct or shrunk below the Mars-born minimum: samples stay `not ok`; no age change.
- A8 Wall-time budget and determinism: the budget only changes steps per frame; step results are identical. Tests inject a fake clock; no wall clock inside `step()`.
- A9 Text: log lines and the HUD name come from `data/ages.json` (naturalistic wording, for example "The founders are no longer only surviving. The colony has settled."); final text is the game-designer's.

## 7. Definition of done
Tests and runs:
- `godot --headless --path station-zero --script res://tests/run_tests.gd` exits 0: all 383 earlier tests plus `test_ages.gd` (no test with zero checks); key-path parity for `ages.json`; determinism tests green.
- Calibration file shows measured crossing sols for seeds 42, 7, 99, 1234, 2026.
- Balance runs (five seeds, 300 sols, no data change to existing files): T1 to T9 PASS as in Task 1; T10 PASS (Settlement once, sol 40 to 150, all five); old columns byte-identical to the Task 1 baseline; each seed run twice gives the same table.
- Step-profile report and a 1000x run with the wall-time budget (frame time bounded, achieved speed reported).
- Shots: HUD at Landing and at Settlement, name only.
Files that must exist: `docs/specs/ages.md`, `data/ages.json`, `sim/ages.gd` (real), `tests/test_ages.gd`, `tools/age_probe.gd`, `docs/balance/task-3-calibration.md`, `docs/balance/task-3-log.md`, `docs/perf/task-3-step-profile.md`, `docs/shots/task-3/`.
Reviewer checks: no progress value, counter, bar or "sols until" anywhere; no RNG in ages; every tunable in `ages.json` or `sim.json`; no Council or later age; sim behavior unchanged; HANDOFF section 8 updated with what changed and what we learned.

## 8. Needs Herby
1. Window length and strictness: 40 sols, 90% tolerance (recommended) or another "long stretch".
2. Latch (no regression, recommended) or allow falling back to Landing.
3. Announce only (recommended) versus a small effect.
4. Defer the night-window alignment to its own balance task (recommended).
5. What the speed presets promise when the machine cannot sustain 1000x (label as a maximum, recommended).

## Owner decisions (Herby, 2026-10-05)
- **Settlement entry:** rolling window, as recommended: at least 90% of the last 40 per-sol samples ok, the last 3 ok, and at least 5 Mars-born beings alive. Samples start at sol 5. The window is private history; nothing about it is shown to the player.
- **Regression is allowed.** A colony in Settlement can fall back to Landing when its life support deteriorates. This replaces the plan's latch. The design must therefore include hysteresis so ages do not flap: a separate, easier exit condition than the entry condition (for example the ok share of the last 40 samples falling below a lower threshold, and the last few samples failing), plus a minimum dwell time in an age before the next change. Each change is announced in the log, in both directions, with its own wording; the log never shows a count or a percentage. Stats record the number of age changes and the sols spent in each age. The calibration probe must also report how often each of the five seeds flaps. Hard times (for example the ice shortages seen on seeds 42, 99 and 2026 after sol 150) are expected to send those colonies back to Landing; that is the intended drama, not a bug.
- **Effect:** announce only. An age changes nothing about colony behaviour in Task 3, so Task 1's balance stays valid. The proof is that the five Task 1 table hashes are unchanged with the age column removed.
- **Carry-over:** include profiling `SimWorld.step()` at 164 beings and an `advance()` wall-time budget (the 1000x speed becomes a maximum, not a promise). Defer aligning the sim's night window with the visual dusk to its own balance task.
- **Balance target T10 changes accordingly:** every seed reaches Settlement between sol 40 and 150; the number of age changes per seed is reported, and the target is that no seed flaps more than a small number of times (the game-designer proposes the number from the calibration probe, with reasons).
