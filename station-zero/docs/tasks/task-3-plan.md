# Task 3 Plan: Age system (Landing and Settlement, announced in the log)

Process document. Every design detail (clauses, thresholds, windows, texts, HUD behaviour, tests, targets) lives in `docs/specs/ages.md` (revision 3, approved by the code-reviewer, owner decisions in its section 18). The project manager does not design: where this plan once held design proposals (Settlement definition and alternatives, announce-only recommendation, latch, Mars-born count, A1 to A9 ambiguities, estimated crossing sols), they are replaced by the spec's decisions and removed. Source of truth: station-zero-handoff/HANDOFF.md (sections 1, 2, 7, 8, 9, 10). Tasks 0 to 2 done; Task 4 not started.

**Status: DONE (October 2026).** Closed in HANDOFF section 8. Open owner items: Task 5 gate (Council reads age_history) and the texture memory decision (47.1 of 48 MB).

Rules in force (HANDOFF 10): design before code, headless tests before visuals, every tunable in data/ (new `data/ages.json`, new keys in `data/sim.json`), seeded RNG (ages never draw from `SimRng`), one balance parameter per run, each step is a commit that runs. Test command: `godot --headless --path station-zero --script res://tests/run_tests.gd`.

## 1. Scope
IN (details: spec sections 2 to 9, 11, 12):
- `sim/ages.gd` (real, replaces the placeholder), the hook, stats and log, `data/ages.json`, `SimData.ages()` (spec 3, 4, 8, 13).
- Two Being fields and the null guard in `_create_newborn` (spec 3).
- HUD: age in the clock line, pinned chapters strip, resource words, speed readout (spec 9).
- Balance column `age` and target T10 (spec 12); probe `tools/age_probe.gd` (spec 14).
- Carry-over chosen by the owner: `SimWorld.step()` profile and the `advance()` wall-time budget (spec 11).
OUT:
- Council, Dome, City ages (no data, stub or condition); trust and relationships (Task 4); Dome and council (Task 5).
- Any colony behaviour change because of the age (owner: announce only).
- New art, sound, banner or pop-up for the age event.
- Aligning the sim night window with visual dusk: deferred to its own balance task (it would mix two balance causes with the age calibration). Footprint, art constants, sleeping pose, extra faces: deferred view polish.
(Age regression is IN, by the owner's decision; spec 6.)

## 2. Steps (spec section 16, steps 1 to 11, same numbering; each is a runnable commit)
1. [game-designer, with designer-emergence, designer-feel, designer-clarity] Spec and `data/ages.json` starting values. DONE (revision 3). Check: every spec number is a key in the key-path list; no Council or later key.
2. [code-reviewer] Read-only spec review. DONE (approved at revision 3, spec changelog).
3. [sim-test-engineer] `tests/test_ages.gd`, written first, red. Content is spec section 10 tests 1 to 19 (per-clause incl. `calm` and `rested`, pop 0, window start, entry, tolerance, last-3, family rule: living parent and 2 birth habitats, regression, hysteresis and dwell, dominant cause, cause lines and no-digit text tests, Landing and the four-entry history, purity incl. RNG draws and the two Being fields, key-path parity, HUD no-digit test) plus test 20 (budget and readout). Check: file runs and fails for the right reasons; the 383 earlier tests unchanged; no test with zero checks.
4. [godot-engineer] Implementation with the starting values: the two Being fields and null guard, `SimData.ages()`, `sim/ages.gd` (`sample`, `decide`, `dominant_cause`, `on_sol`), `ages_enabled` seam, stats (`age`, `age_history`, `age_changes`, `sols_in_age`, `first_settlement_sol`) and the `age_began` log event (extra fields `how`, `cause`). The hook is one call inside the `if _sol_started:` block of `SimWorld.step()` (phase 11), after the `pop_by_sol` line; `_sol_boundary()` is not touched. Check: `test_ages.gd` green except tests 19 and 20; full suite green; seed 7 and 42 determinism tests green.
5. [sim-test-engineer] Calibration probe `tools/age_probe.gd` and `docs/balance/task-3-calibration.md`. Runs the real step 4 code; read-only; content per spec 14 (crossings, flap report, per-clause failures, one-at-a-time sweeps, missed dips, cost). Any recalibration edits `data/ages.json` only, one parameter per change, recorded in the spec changelog by the game-designer. Open design questions go to the game-designer, never decided here. Check: measured crossing sols and flap counts for all five seeds in the file; probe self-check passes.
6. [godot-engineer] HUD: age in the clock line, chapters strip, resource words (spec 9; speed readout wiring waits for step 11). Check: test 19 green, including the "no digit-carrying age field" assertion; `--quit-after 5` on the main scene prints no errors. Must come before step 7 (balance runs the full suite).
7. [sim-test-engineer] Balance integration and run: `age` column and T10 in `tests/balance_lib.gd` and `balance_run.gd`; pointer in `docs/specs/life-support-power.md` sections 13 and 16. Five seeds, 300 sols, `docs/balance/task-3-log.md`. T10 (spec 12): settle sol 40 to 150 on every seed, `age_changes <= balance.max_age_changes`, gaps between history sols >= `min_dwell_sols`, history check (`len(age_history) == age_changes + 1`, every entry has `how` and `text`). Proof: the five Task 1 table hashes (02032b23..., 830c7d0c..., 0e3e83a7..., bca6eb2c..., 2645033a...) reproduce with the column removed; each seed run twice gives the same table. If T10 fails, change one parameter per run, taken from the spec 14 sweeps (window, exit share, dwell, `ice_min_sols`, `rested_share_min`), and record each run; the game-designer chooses which parameter and value (design question).
8. [godot-engineer] Shots with `tools/shots`: HUD at Landing, just after Settlement, and the three-frame fall-back strip (spec 9). Check: PNGs non-blank in `docs/shots/task-3/`; the main session reads them.
9. [code-reviewer] Final review of the age work. Checks: sim diff outside `sim/ages.gd` and the hook is empty, except the two Being fields, the null guard in `_create_newborn`, and the world log and stats hooks; no tunable literal in code (only the spec's non-data constants); no RNG in ages; no progress value anywhere in view or stats; Council and later absent; tests meaningful; balance log honest.
10. [godot-engineer] Step profile: `tools/step_profile.gd` (timers outside `sim/`), `docs/perf/task-3-step-profile.md` with the top 3 phases at about 164 beings. A fix is allowed only if the five old-column table hashes stay byte-identical.
11. [godot-engineer] `advance()` wall-time budget and speed readout (spec 11, test 20 green): `advance_budget_ms` and the three speed-readout keys in `data/sim.json`; wiring in `view/sim_host.gd` and `view/main.gd`; `perf_run.gd` 1000x run with a short `--speed-frames`, frame time and achieved speed recorded. Reviewer re-check of the budget diff (code-reviewer).
Closing (not a spec step): [project-manager] check off Task 3 in HANDOFF.md section 8 with what changed and what we learned; Task 4 not started.
Schedule trade-off (process only): steps 10 and 11 are last so the age work can be reviewed and checked off without them; if time runs out they are the first to move to the next task, unless the owner says otherwise (spec 16).

## 3. Definition of done
Tests and runs:
- The test command exits 0: all 383 earlier tests plus `test_ages.gd`; key-path parity for `ages.json` (and existence of the `sim.` keys); determinism tests green; no HUD age text or `age_history` text contains a digit.
- `advance()` budget rule (spec 11): `advance_dropped_h` on the world grows by exactly the accumulator value at the moment it is zeroed when the loop stops with a step still due (including any earlier sub-step remainder), and neither it nor any wall-time figure enters `stats`, the log or hashed state.
- `data/sim.json` contains `advance_budget_ms`, `speed_readout_window_s`, `speed_readout_refresh_s`, `speed_throttle_below`; the HUD speed line reads "max" and the achieved-speed readout is shown.
- Calibration file: measured crossings and flap report for seeds 42, 7, 99, 1234, 2026.
- Balance (five seeds, 300 sols): T1 to T9 as in Task 1; T10 passes per spec 12; old columns byte-identical to Task 1; same-seed reruns identical.
- Step profile report and a 1000x run with the budget recorded.
- Shots: HUD at Landing and after Settlement, plus the fall-back strip.
Files that must exist: `docs/specs/ages.md`, `data/ages.json`, `sim/ages.gd` (real), `tests/test_ages.gd`, `tools/age_probe.gd`, `docs/balance/task-3-calibration.md`, `docs/balance/task-3-log.md`, `docs/perf/task-3-step-profile.md`, `tools/step_profile.gd`, `docs/shots/task-3/`.
Reviewer checks: step 9 list above; HANDOFF section 8 updated with what changed and what was learned.

## 4. Needs the owner
All design questions from earlier plan revisions are answered (spec section 18). Still open: Task 5 gate (not Task 3 work; Task 5 reads `age_history`). Any new design question from the probe or balance steps goes to the game-designer first, then to the owner, listed with the designers' options and no PM recommendation.

## Owner decisions (Herby, 2026-10-05), as recorded in the spec
- Settlement entry: rolling window, at least 90% of the last 40 samples ok, last 3 ok, at least 5 Mars-born (refined to the family rule, spec 5); samples from sol 5; window private.
- Regression allowed, with hysteresis and a minimum dwell; each change announced in the log in both directions with no counts or percentages; stats record age changes and sols per age; the probe reports flaps per seed. This replaces the earlier latch.
- Effect: announce only; the five Task 1 hashes unchanged with the age column removed.
- Carry-over: profile `step()` and the `advance()` budget (1000x becomes a maximum); night-window alignment deferred.
- T10: every seed settles between sol 40 and 150; age changes reported and capped (the game-designer's number from the probe, spec 12, 13).
- Spec 18 additions: colonist clauses adopted; family rule = living parent and 2 birth habitats; pop 0 frozen, no HUD age word; the game never changes speed on an age change.
