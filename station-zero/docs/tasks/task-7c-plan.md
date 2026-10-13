# Task 7c plan: per-being thirst deaths

Branch `claude/task-7c-per-being-thirst`. Queue entry: HANDOFF section 8, "7c" (owner approved 2026-10-12). Evidence: `docs/balance/task-7b-results.md` and "Lever 1 decision" in `docs/tasks/task-7b-plan.md`. Baseline bars: `docs/balance/task-7-acceptance.md`. Task 7b stays paused until 7c is done.

## Status: DONE 2026-10-12
Checked off in HANDOFF section 8. Built `thirst_mode` ("colony" | "per_being"), `thirst_roll_h` 6, `thirst_being_chance` 0.002; per_being is the default (owner chose spec section 9 Option A after the 3-run stop). Results: Run 1 0.002 U2 PASS, U3 PASS (worst 18%), guard FAIL 5/5 alive; Run 2 0.0028 U3 FAIL (seed 7 64%), guard FAIL 4/5; Run 3 0.0024 U3 FAIL, guard FAIL 5/5. Re-baseline: 300-sol hashes unchanged, data_hash e1d5e1add9f157c4, suite 802/0. Reviewer advisories: none blocking.
Departure from the definition of done below: the guard bar (3 or fewer alive) was NOT met; the owner moved it to task 7d. Lesson: the guard is a water-access problem, not a death-rate problem (seeds 99/1234/2026 are dry only about 20-150 of 1,500 sols); U3 at pop 10-14 is near single-death noise.

## Goal
Make unattended thirst loss scale with population, so U3 and the 3-alive-or-fewer guard can both be met. The thirst roll is per colony today (`sim/colony.gd:169-184`; about 9.86 / `thirst_interval_h` deaths per sol at ice 0, whatever the population), and no per-colony `thirst_interval_h` or `death.chance` value met both bars. Change: one new data switch `colony.death.thirst_mode` in `data/colony.json`, `"colony"` (default, current behaviour, hashes unchanged) or `"per_being"` (each living colonist rolls its own thirst chance while ice is 0). Code is behind the switch; the data default is flipped only in step 6.

## Rules for every run (HANDOFF section 10, CLAUDE.md section 4)
- Design before code. Tunables in `data/`. Seeded RNG. One balance number per run.
- Seeds 42, 7, 99, 1234, 2026. Standard, 1,500 sols, `--every 10`, `--player watcher` (UN set only; no attended runs in 7c).
- Check the `overrides=[...]` header of every output before reading a result: it must list exactly the one number under test (plus the `thirst_mode` switch, declared as the run's setup, not a second lever). Reject the run otherwise.
- Runs go in the background, two at a time; check back with one short command. Raw outputs in `docs/balance/task-7c-data/<run>/`. Summaries by `python3 tools/acceptance_summary.py` (or its `load`/`summarise` functions, as in 7b).

## Steps
1. **game-designer** (consults designer-emergence, designer-feel, designer-clarity). Write `docs/specs/thirst-per-being.md` (or a section in `influence-powers.md`) answering the open design questions below, with numbers, file, key, old value, new value. Also **strike the lever-1 line in 7b spec section 5.8** (`death.thirst_interval_h`), now stale. Acceptance: every open question answered; owner has approved the spec; lever-1 line struck; no code written before approval.
2. **godot-engineer.** Add `death.thirst_mode` (default `"colony"`) to `data/colony.json` and implement `per_being` in `sim/colony.gd` per the spec. In `"colony"` mode the code path and RNG draw order are unchanged. Tests: `per_being` rolls scale with living count; no rolls when ice > 0; unknown mode value rejected or falls back as the spec says; **default-off check: with `thirst_mode` = `"colony"` all pinned 300-sol hashes (42 a298dbb55b71d66e, 7 e540c1b86dabba26, 99 ffb6d5361bdb3a5d, 1234 bca08a0f327892fe, 2026 5fb3b699b4118a84) are unchanged**, and the four hash proofs plus `test_t18c` still pass. Acceptance: full suite green (previous count 791) and one small commit that runs.
3. **sim-test-engineer.** Verify the switch is reachable by `--param colony.death.thirst_mode=per_being` and that `balance_lib` rejects a type mismatch. Run the UN set, five seeds, with the spec's numbers. One number per run. Record each run in `docs/balance/task-7c-log.md` (header checked, no SCRIPT ERROR, all 5 seeds finished, U1 hashes differ from the old pins, since the override must have acted). Acceptance: per-run table of U2, U3 and alive-at-1,500 in `docs/balance/task-7c-results.md`, one verdict per run against the bars below.
4. **sim-test-engineer (only if step 3 fails the bars).** Re-run with the next number the game-designer names, one number per run. **Stop rule:** three failed runs = stop, record in the log and HANDOFF, and split the task (HANDOFF section 10 / CLAUDE.md section 3; owner decision needed).
5. **code-reviewer.** Input: diff, tests, log, results. Checks: default-off behaviour byte-identical; only the declared switch and spec'd keys changed; RNG seeded and draw order unchanged in `"colony"` mode; headers were checked; one number per run; no design numbers chosen outside step 1. Acceptance: PASS before step 6.
6. **godot-engineer + sim-test-engineer. Adopt and re-baseline.** godot-engineer sets the adopted data defaults (`thirst_mode` and the spec'd keys); no further code. sim-test-engineer updates the pinned hashes in `tests/age_hash_proof.gd`, `tests/mood_hash_proof.gd`, `tests/relationships_hash_proof.gd`, `tests/council_hash_proof.gd` and `tests/test_council.gd::test_t18c` (old values kept as history), re-runs the U1 check (`--player watcher`, 300 sols, five seeds) so hashes equal the new pins, and writes old/new hashes to `docs/balance/task-7c-rebaseline.md`. Acceptance: full suite 0 failures; a default run header shows `overrides=[]` and the new `data_hash`.
7. **project-manager / main session.** Update HANDOFF section 8: tick 7c, record changes and lessons, mark 7b "resume with the UN run under the 7c rule, then guide levers 5-7", name the branch, push, PR, merge to `main`. Suggest a fresh session.

## Acceptance bars (quoted from `docs/balance/task-7-acceptance.md` and `task-7b-plan.md` step 3; UN set)
- **U2** "warned early (`lead` >= 10, `low_sol` > 0)": `lead` = sols from first low to first thirst death. Plan rule: `lead >= 10` sols on every seed with a thirst death, and `low_sol > 0` on every seed.
- **U3** "no 50-sol window loses > 35% (start pop >= 10)": windows are 50 sols between sample rows, starting at any sample with population >= 10, from `tools/acceptance_summary.py`. Plan rule: on all 5 seeds.
- **Guard (U4)** "at most 3 of 5 seeds alive at sol 1,500" (baseline 2; the owner wants unattended play clearly worse than attended). 4 or more alive = fail.
- U1 is informational for a changed setting (hashes are expected to differ; if they equal the old pins the override did not act: reject the run).

## Open design questions (game-designer, consulting the assistant designers; owner decides)
1. Rate per being: the chance each colonist dies per roll while ice is 0.
2. Interval: how often each being rolls (hours between rolls), and whether it reuses `thirst_interval_h` or gets its own key.
3. Grace: any delay, ramp or per-being grace before a dry colonist can die, and how it interacts with the existing `lead` warning.
4. Log wording: how a per-being thirst death reads in the log, and whether it differs from the current line.
5. Whether `death.chance` still applies in `per_being` mode, and which keys the switch leaves untouched.
6. Where the spec text lives, and the exact wording of the struck 5.8 lever-1 line.

## Definition of done
- U3 passes on all 5 seeds and 3 or fewer of 5 seeds are alive at sol 1,500 unattended, with U2 holding, on the adopted defaults.
- Files exist: spec, this plan, `task-7c-log.md`, `task-7c-results.md`, `task-7c-data/`, `task-7c-rebaseline.md`.
- Default-off hash check passed in step 2; pinned hashes re-baselined and the full suite passes with 0 failures.
- Spec 5.8 lever-1 line struck by the designer.
- code-reviewer PASS; HANDOFF section 8 updated; branch merged to `main`.
