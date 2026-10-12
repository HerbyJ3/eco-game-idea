# Task 7b plan: power tuning

Branch `claude/task-7b-power-tuning`. Spec: `docs/specs/influence-powers.md` sections 5, 5.6-5.8. Baseline measurement: `docs/balance/task-7-acceptance.md`. Owner decisions 2026-10-12 are in spec 5.7 (U3 hard bar; no auto-pause; Grace/Inspire no water role; bars as proposed; guided-field choice deferred).

## Rules for every run (HANDOFF section 10)
- One lever per run. Seeds 42, 7, 99, 1234, 2026. Standard, 1,500 sols, `--every 10`.
- Run set per lever: UN (`--player watcher`), C1 (`--player attentive --cadence 1`), C2 (`--player attentive --cadence 2`) = 15 runs, as in task-7-acceptance. Override passed once per run via the balance_lib override flag.
- Check the `overrides=[...]` header of every output before reading any result: it must list exactly the one lever, with the right type. Reject the run otherwise.
- Runs go in the background (two at a time); check back with one short command (`done.log`). Raw outputs in `docs/balance/task-7b-data/<lever>/`.
- Summaries by `python3 tools/acceptance_summary.py`. A lever's run is judged only by the rule declared in step 3.

## Steps
1. **godot-engineer (read-only).** Input: thirst death code in `sim/`, `data/colony.json` `death.*`. Output: a note appended to this file under "Step 1 report": is the thirst roll per colony or per being, file and line, and what `thirst_interval_h` and `chance` multiply. DoD: file and line cited; no code or data changed.
2. **game-designer** (consults designer-emergence, designer-feel, designer-clarity). Input: step 1 report, spec 5.8. Output: "Step 2 decisions" section here confirming or adjusting the number for levers 1-2 (and 3-4 if the report affects them). DoD: each lever has file, key, old value, new value; any change from the spec's proposed numbers is justified by the report. The project-manager does not pick numbers.
3. **game-designer + project-manager.** Output: "Decision rules" section here, written before any run. Per lever, the unattended levers (1-4) use U1 (expected to differ; it is re-baselined, not a keep test), U2, U3 and the U4 report; the powers levers (5-7) use A1, A2, A3, P1, P2, P3, G1. Each rule states PASS (all targeted items pass: adopt), KEEP (targeted item improved, none of G1/P1 broken: carry the number forward and test the next lever on top), or REVERT (a guard breaks or the target item does not improve: restore the old number). DoD: rules are in the file and committed before step 4 starts.
4. **sim-test-engineer. Run lever 1** (`death.thirst_interval_h`) UN set, five seeds, background. Output: `docs/balance/task-7b-data/lever1/` plus summary. DoD: all 5 headers checked and logged; no SCRIPT ERROR; verdict per step 3 rule recorded in `docs/balance/task-7b-log.md`.
5. **sim-test-engineer. Run lever 2** (`death.chance`) only if lever 1 left U3 failing, on top of lever 1 if KEEP. Same outputs and DoD.
6. **sim-test-engineer. Run lever 3** (`want.ice_urgent_below`) only if U3 still fails. **Stop rule:** if lever 3 still fails U3, stop, record in the log and HANDOFF, and split the task (owner decision needed). Do not run levers 4-7 past a U3 failure.
7. **sim-test-engineer. Lever 4** (`start.ice`) only if `low_sol` is 0 on any seed (U2 fails on that ground).
8. **sim-test-engineer. Attended set** once U3 passes: C1 and C2 on the chosen unattended setting (plus UN already run). If A1/A2/A3/P2 pass, go to step 10. If not, run levers 5, 6, 7 in that order, one per run, each with the full 15-run set and the step 3 rule. Three attended failures: stop and split.
9. **game-designer.** Review the final five-seed tables for readability (warning lead, decline slope). Output: short note in the log. DoD: owner-facing wording, if any, comes from the designer, not from this plan.
10. **godot-engineer. Adopt.** Input: the adopted lever list. Output: change the data defaults only (`data/colony.json`, `resources.json`, `powers.json`); no code change. DoD: game boots; a default run header shows `overrides=[]` and the new `data_hash`.
11. **sim-test-engineer. Re-baseline.** Update pinned hashes in `tests/age_hash_proof.gd`, `tests/mood_hash_proof.gd`, `tests/relationships_hash_proof.gd`, `tests/council_hash_proof.gd` and `tests/test_council.gd::test_t18c` (keep old values as history). Re-run the U1 check with `--player watcher` (300 sols, five seeds): hashes equal the new pins. DoD: full suite passes, 0 failures (previous count 791); a table of old and new hashes in `docs/balance/task-7b-rebaseline.md`.
12. **sim-test-engineer.** Final acceptance run on adopted defaults: the 15-run set, `overrides=[]`. Output: `docs/balance/task-7b-acceptance.md` in the layout of task-7-acceptance. DoD: U1-U3, A1-A3, P1-P3, G1 pass, or the owner restates the failing targets.
13. **code-reviewer.** Input: diff, logs, rebaseline, acceptance. Checks: only data files and pinned hashes changed; every adopted lever has a recorded run; headers were checked; one lever per run; no design numbers chosen outside step 2. DoD: PASS before check-off.
14. **project-manager / main session.** Update HANDOFF section 8: tick 7b, record changes and lessons, name the branch, next step (Task 8). Push, open a PR, merge to `main`. Suggest a fresh session.

## Step 3: Decision rules (written before any run)

All numbers are estimates until a run measures them. Inputs: `tools/acceptance_summary.py` output for the run set, and the baseline in `docs/balance/task-7-acceptance.md`.

**Lever 1 value: `death.thirst_interval_h` 5 -> 50 (spec 5.8 said 10; changed on the arithmetic below).** Thirst death is per colony (step 1): at ice 0 the rate is `24.66 / interval_h x chance` deaths per sol, whatever the population. U3 allows a loss of 35% of the start population in 50 sols, for windows starting at pop >= 10. With chance 0.4: at 5 h the rate is 1.97/sol (a fully dry 50 sols kills about 99); at 10 h it is 0.99/sol (about 49), so a dry stretch of 3.5 sols already breaks U3 for a pop-10 window. Passing needs the dry-state rate to be at or below about 0.2/sol: at 50 h it is 0.197/sol (about 10 deaths per fully dry 50 sols), so a pop-10 window tolerates about 18 dry sols and a pop-28 window tolerates a fully dry window. 10 h alone cannot plausibly pass. 50 h can, and it is one number. Lever 2 (chance) will probably be unneeded; it stays in the plan only if lever 1 fails.

**Design observation, for a later spec, no 7b code change:** because the roll is per colony and population-independent, small colonies die proportionally faster than large ones, and a late decline accelerates as the population shrinks. A per-being or population-scaled thirst rule would read more naturally. Record in the spec backlog after 7b.

**Run validity (every lever).** The `overrides=[...]` header lists exactly the one lever with the right type; no SCRIPT ERROR; all 5 seeds finished. Otherwise reject and re-run; no verdict.

**Unattended levers 1-4 (UN set, 5 seeds).** U1 is informational: the 300-sol hashes are expected to differ and are logged as the new candidate pins. If they equal the old pins, the override did not act: reject the run.
- PASS (adopt, stop the chain, go to step 8) when all hold:
  - U3: on all 5 seeds, no 50-sol window with start pop >= 10 loses more than 35%.
  - U2: `lead >= 10` sols on every seed with a thirst death, and `low_sol > 0` on every seed.
  - U4 guard: at most 3 of 5 seeds alive at sol 1,500 (baseline 2; the owner wants unattended play clearly worse than attended).
- KEEP (carry the number forward, run the next lever on top) when U3 still fails but improved: the worst window loss over all seeds fell by at least 10 percentage points against the previous setting, or the number of failing seeds fell; and U2 did not regress (no seed that had lead >= 10 falls below it; `low_sol` still > 0); and the U4 guard holds.
- REVERT (restore the old number) when any of these holds: the worst window loss improved by less than 5 percentage points and the failing-seed count did not fall; U2 regressed; 4 or more seeds are alive at sol 1,500 (the colony became fine alone). Between 5 and 10 points with no seed change: REVERT.
- Lever 4 (`start.ice`) is judged on U2 `low_sol > 0` only, with the U3 and U4 guards unchanged.

**Powers levers 5-7 (full 15-run set).** UN must reproduce the previous setting's hashes exactly (powers cannot touch unattended runs); if not, reject.
- PASS when A1, A2, A3, P1, P2, P3 and G1 all pass.
- KEEP when the targeted items improve (levers 5, 6: A1 or A3; lever 7: A1, A3 or P2; improved means one more seed passing, or one more seed alive at 1,500 for C1) and P1, P3 and G1 hold.
- REVERT when P1, P3 or G1 breaks (for example an air death or an EVA death in any C1 or C2 seed), or no targeted item improves.

## Definition of done (task)
- `docs/balance/task-7b-acceptance.md` shows the acceptance set passing (or the owner restated the failing targets).
- Files exist: this plan with step 1 to 3 sections, `task-7b-log.md`, `task-7b-data/`, `task-7b-rebaseline.md`, `task-7b-acceptance.md`.
- Full test suite passes; pinned hashes match the new defaults.
- code-reviewer PASS; HANDOFF updated; merged.

## Open design questions (owner / game-designer)
- Final lever numbers (step 2), and the guided-field choice (deferred by the owner).
