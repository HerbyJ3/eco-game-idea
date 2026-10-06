# Task 4 Plan: Relationships and trust ("Driven by personality")

Process document. Every design detail (what a relationship is, how trust forms, what personality drives, thresholds, data keys, HUD words, test targets) lives in a spec the design team writes: `docs/specs/relationships.md`. The project manager does not design. Source of truth: station-zero-handoff/HANDOFF.md (sections 1, 3, 7, 8, 9, 10). Model: `docs/tasks/task-3-plan.md`. Tasks 0 to 3 done.

**Status: DONE (closed 2026-10-06).** Task 4 closed with owner decision: pulls built but shipped off. Closing record and learned items: HANDOFF section 8, Task 4. Task 5 is now the first unchecked task; its gate (Council reads age_history/web_by_sol/second_by_sol/lonely_by_sol) is still undecided.

Rules in force (HANDOFF 10): design before code, headless tests before visuals, every tunable in `data/` (new file, name chosen by the spec), seeded RNG, one balance parameter per run, each step a commit that runs. Test command: `godot --headless --path station-zero --script res://tests/run_tests.gd`.

## 1. Constraints from earlier tasks (not design)
- Ages: HANDOFF section 7 says Settlement is left "when relationships and trust form". Task 3 built Settlement entry from its own clauses (spec `docs/specs/ages.md`) and ages are announce-only. Whether Task 4 data feeds, changes or leaves alone any age clause is a design question (Q1). Whatever the answer, the Task 3 calibration (crossings sols 67, 58, 54, 65, 53; fall-backs on seeds 42 and 99) must be re-measured and documented, never assumed.
- RNG-stream and hash rule: the five Task 1 table hashes (02032b23..., 830c7d0c..., 0e3e83a7..., bca6eb2c..., 2645033a...) must reproduce with any new column removed, unless the owner explicitly accepts a behaviour change (Q2). Any new draw from the shared `SimRng` shifts every later draw and changes the hashes; so the spec must state, per mechanic, whether it draws randomness, and if so from which stream. Ages never draw from `SimRng`; a read-only layer needs no stream. A changed hash is recorded as an owner-approved baseline reset, with new hashes and a determinism check (each seed run twice, same table).
- Task 5 reads `age_history` (open owner gate); Task 4 must not remove or reshape it.
- Texture memory is 47.1 of 48 MB: no new art in Task 4 unless the owner decides the budget.

## 2. Steps (each a runnable commit)
1. [game-designer, with designer-emergence, designer-feel, designer-clarity] Spec `docs/specs/relationships.md` with numbers and the `data/` starting values; owner questions in section 4 answered. Check: every spec number is a data key; the spec lists which sim state is new, its RNG use, and its effect on Task 1 hashes; the three assistant reviews are recorded in the spec.
2. [code-reviewer] Read-only spec review (testability, data keys, hash and RNG statement, age interaction). Check: approval or numbered findings; findings go back to step 1.
3. [sim-test-engineer] Tests first, red: `tests/test_relationships.gd` covering the spec's test list (formation, change over time, personality dependence, purity, determinism, key-path parity, no player-visible digits if the spec says so) plus a hash-reproduction test. Check: fails for the right reasons; all earlier tests unchanged; no test with zero checks.
4. [godot-engineer] Implementation with the spec's starting values (`sim/` plus `data/`, one hook in `SimWorld.step()`, `SimData` accessor, stats and log events per spec). Check: new tests green, full suite green, seed 7 and 42 determinism tests green.
5. [sim-test-engineer] Calibration probe and `docs/balance/task-4-calibration.md`: measured behaviour on seeds 42, 7, 99, 1234, 2026 at 300 sols. Any recalibration edits `data/` only, one parameter per run, chosen by the game-designer. Check: measured numbers for all five seeds; open design questions go to the game-designer.
6. [sim-test-engineer] Balance integration and run: new column(s) and target(s) in `tests/balance_lib.gd` and `balance_run.gd`; five seeds, 300 sols, `docs/balance/task-4-log.md`. Check: T1 to T10 pass; old columns byte-identical to Task 1 (or the owner-approved reset recorded); same-seed reruns identical; Task 3 age behaviour documented per seed (settlement sol, age changes, fall-backs) before and after, with any difference stated.
7. [code-reviewer] Final review of the sim work. Checks: sim diff outside the new module and its hook is empty (or listed and justified); no tunable literal in code; RNG use matches the spec; no progress meter in stats or view; Task 3 tests untouched; balance log honest. Findings fixed before step 8.
8. [godot-engineer] View/HUD per the spec's clarity section (only what the spec says is shown; sim read-only; no art unless approved). Check: HUD tests green, `--quit-after 5` on the main scene prints no errors, shots in `docs/shots/task-4/` non-blank and read by the main session, performance within the Task 2 and 3 budgets (step cost and `advance()` budget re-measured).
9. [code-reviewer] Re-check of the view diff. Check: approval recorded.
Closing: [project-manager] check off Task 4 in HANDOFF section 8 with what changed and what was learned.
Schedule trade-off (process only): step 8 is last so the sim work can be reviewed and balanced first; if time runs out, step 8 is the first to move, unless the owner says otherwise.

## 3. Definition of done
- Test command exits 0: all earlier tests plus `test_relationships.gd`; key-path parity for the new data file; determinism tests green.
- Balance on five seeds at 300 sols: T1 to T10 pass, new target(s) from the spec pass, hashes per Q2, reruns identical; per-seed Task 3 age behaviour documented.
- Files exist: `docs/specs/relationships.md`, the new data file, the new sim module, `tests/test_relationships.gd`, probe tool and `docs/balance/task-4-calibration.md`, `docs/balance/task-4-log.md`, `docs/shots/task-4/`.
- Reviewer (steps 2, 7, 9) approvals recorded; HANDOFF section 8 updated and Task 4 checked off.

## 4. Open owner questions (the game-designer puts these to the owner with the assistant designers' options; the PM recommends none)
- Q1. Ages link: does Task 4 data feed Settlement entry or exit, stay separate and announce-only, or neither? If it changes a clause, is the Task 3 calibration reopened?
- Q2. Hashes: must the five Task 1 hashes stay byte-identical, or may relationships change colony behaviour (and the baseline be reset by the owner)?
- Q3. Scope of "relationships": between which beings (pairs, families, groups, all), and what the sim stores for each.
- Q4. What "trust" is and how it forms, grows, decays and ends (including death and births).
- Q5. Which personality traits drive it and in what direction; how it relates to the role and two-word description (chart stays hidden).
- Q6. Does it change behaviour (conversations, rooms, work, births, mining, god powers), or is it recorded and shown only?
- Q7. What the player sees: nothing, log lines, HUD words, a view of bonds; wording and any no-number rule.
- Q8. Randomness: does any part need random draws, and from which stream.
- Q9. Balance targets: what "good" looks like at 300 sols, and the cost budget per step.
- Q10. Texture budget (carried from Task 3): is any new art allowed.
