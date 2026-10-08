# Task 5 Plan: Council and diplomacy ("Gatherings, proposals, support, the decision to build a dome")

Process document. Every design detail (what a gathering, proposal and support are, the Council gate, thresholds, data keys, HUD words, test targets) lives in a spec the design team writes: `docs/specs/council.md` (name proposed, spec may change it). The project manager does not design. Source of truth: station-zero-handoff/HANDOFF.md (sections 4, 7, 8, 9, 10). Model: `docs/tasks/task-4-plan.md`. Tasks 0 to 4 done.

**Status: DONE (closed 2026-10-08).** Checked off in HANDOFF section 8 with results, owner decisions O1-O6, cost and known issues. Next: Task 6 (later stages), not started.

Rules in force (HANDOFF 10): design before code, headless tests before visuals, every tunable in `data/`, seeded RNG, one balance parameter per run, each step a commit that runs. Test command: `godot --headless --path station-zero --script res://tests/run_tests.gd`.

## 1. Constraints carried (not design)
- RNG and hash rule: the five Task 1 hashes (02032b23..., 830c7d0c..., 0e3e83a7..., bca6eb2c..., 2645033a...) and the Task 3 and Task 4 hashes must reproduce with new columns dropped, unless the owner approves a behaviour change. The spec states per mechanic whether it draws randomness and from which stream. A changed hash is recorded as an owner-approved baseline reset: new hashes, each seed run twice with the same table, old and new side by side in the log.
- `stats.age_history` shape is fixed: `{age, how, cause, text, pop, family_mars_born, t, sol, clock_sol}`, uncapped, `len == age_changes + 1`, Landing entry at creation. Task 5 may add entries and ages; it must not remove or reshape fields. Council must not gate on "first Settlement entry" (ages.md section 2; Settlement entry can recur and falls back happen).
- Texture memory 47.1 of 48 MB: no new art unless the owner decides the budget.
- Tick cost: relationships tick about 4.7 ms median at 159 beings; limits are <=8 ms median and <=20% of mean step; `advance()` 8 ms wall budget. Re-measure after any new per-tick work.
- Known issues, stated per seed and not silently fixed: K1 (a third of late newborns on seeds 42 and 2026 have no friend at sol 300), K2 (seed 99 first newcomer line at sol 68), K3 (R1 passes by 1 sol on seeds 99 and 2026). Two host-speed timing tests are flaky on this host; not to be weakened.
- Task 3 calibration (Settlement at sols 67, 58, 54, 65, 53; fall-backs seed 42 sol 213, seed 99 sol 174) and Task 4 probe values are re-measured, never assumed.
- Task 4 inputs (relationships.md section 19) go through this task's reviews before building: dislike bonds, structural colony line, click-to-focus, lonely-run companions (breadth report, probe additions, K1 inspect sentence), god lever on gathering.

## 2. Steps (each a runnable commit)
1. [game-designer, with designer-emergence, designer-feel, designer-clarity] Spec `docs/specs/council.md` with numbers and `data/` starting values, owner questions in section 4 answered. Check: every number is a data key; new sim state, RNG use and hash effect listed per mechanic; three assistant reviews recorded.
2. [code-reviewer] Read-only spec review (testability, data keys, hash and RNG statement, `age_history` reads, tick budget). Check: approval or numbered findings; findings go to step 1.
3. [sim-test-engineer] Lonely pull run, see section 5 for placement. Tests and balance columns first (breadth report, probe additions the spec adopts), then one run: the pull alone, five seeds, 300 sols, `docs/balance/task-5-lonely-run.md`. Check: one parameter changed; old columns reproduce or the owner-approved reset is recorded (new hashes, twice-run check); K1 to K3 re-measured; value chosen by the game-designer.
4. [sim-test-engineer] Tests first, red: `tests/test_council.gd` from the spec's test list (gate reads, gathering, proposal, support, commit, purity, determinism, key-path parity, hash reproduction, `age_history` shape). Check: fail for the right reasons; earlier tests unchanged; no test with zero checks.
5. [godot-engineer] Implementation (`sim/` plus `data/`, one hook in `SimWorld.step()`, `SimData` accessor, stats and log events per spec; age entry via the existing `age_history` writer). Check: new tests green, full suite green, seed 7 and 42 determinism green.
6. [sim-test-engineer] Calibration probe and `docs/balance/task-5-calibration.md`: seeds 42, 7, 99, 1234, 2026 at 300 sols. Recalibration edits `data/` only, one parameter per run, chosen by the game-designer. Check: all five seeds measured; open questions go to the game-designer.
7. [sim-test-engineer] Balance integration: columns and targets in `tests/balance_lib.gd` and `balance_run.gd`; `docs/balance/task-5-log.md`. Check: T1 to T10 and the spec's targets pass; old columns byte-identical (or reset recorded); reruns identical; per seed: Settlement and Council entry sols, age changes, fall-backs, before and after.
8. [code-reviewer] Final sim review: diff outside the new module and its hook empty or justified; no tunable literal; RNG matches spec; no progress meter in stats or view; Task 3 and 4 tests untouched; logs honest. Findings fixed before step 9.
9. [godot-engineer] View/HUD per the spec's clarity section only (sim read-only; no art unless approved; chapters strip handles the new age). Check: HUD tests green, `--quit-after 5` prints no errors, shots in `docs/shots/task-5/` non-blank and read by the main session, step cost and `advance()` budget re-measured in `docs/perf/task-5-*.md`.
10. [code-reviewer] Re-check of the view diff. Check: approval recorded.
Closing: [project-manager] check off Task 5 in HANDOFF section 8 with what changed and what was learned; update this plan's status.
Schedule trade-off (process only): step 9 is last so sim work is reviewed and balanced first; it is first to move if time runs out, unless the owner says otherwise.

## 3. Definition of done
- Test command exits 0: all earlier tests plus `test_council.gd`; key-path parity for new data files; determinism green.
- Five seeds at 300 sols: T1 to T10 and the spec's targets pass, hashes per owner answer, reruns identical, per-seed age behaviour documented.
- Files exist: `docs/specs/council.md`, new data file(s), new sim module, `tests/test_council.gd`, probe tool, `docs/balance/task-5-lonely-run.md`, `task-5-calibration.md`, `task-5-log.md`, `docs/shots/task-5/`, perf note.
- Reviewer approvals (steps 2, 8, 10) recorded; HANDOFF section 8 updated and Task 5 checked off.

## 4. Open owner questions (lead designer puts these with the assistants' options; the PM recommends none)
- Q1. Council gate: which readings must the Council have before it can appear (`age_history`, `web_by_sol`, `second_by_sol`, `lonely_by_sol`, others, or none of these), and how it relates to Settlement entry, recurrence and fall-back.
- Q2. Texture memory: is new art allowed for Task 5 (47.1 of 48 MB), and if so, is the budget raised or something freed.
- Q3. Hashes: must the Task 1, 3 and 4 hashes stay byte-identical, or may Council and the lonely run change colony behaviour (owner-approved reset)?
- Q4. Scope: gatherings, proposals, support and the dome decision, which are in Task 5 and which later (Dome age, "more domes"); dislike and factions by personality.
- Q5. Does Council change behaviour (building the dome, births rule, god powers) or is it recorded and shown only; what "commits to build" does in the sim.
- Q6. What the player sees (log lines, HUD words, click-to-focus, structural colony line, being inspect text) and any no-number rule.
- Q7. God lever on gathering or proposals (influence, never command); whether in this task.
- Q8. Randomness: any draws, and from which stream.
- Q9. Balance targets and cost budget for 300 sols; whether R9 is judged over more seeds.
- Q10. Lonely definition and run content: `friend_count` 0 as K1 or "no grown friendship"; whether the second and third lonely-run candidates (temperament-scaled pull, parent-room anchor) are in scope.

## 5. Placement of the lonely pull run (process and ordering choice for the owner)
The owner decision (2026-10-06) fixes what the first social run is, not where it sits. Options:
- (a) Own step inside the plan (step 3 above, after spec review, before Council tests): one parameter per run is kept clean; its baseline reset, if any, is recorded once, and Council tests and calibration start from the new baseline. Cost: Council spec must be written against numbers that may still move.
- (b) Separate pre-step before step 1: fully isolated, Council spec written against the final social baseline. Cost: Task 5 starts with a run that has no spec, tests or reviews of its own, and the lonely-run items need their own short design note.
- (c) After Council calibration (step 6): Council's own baseline is measured first. Cost: two baseline resets (Council, then lonely), and Council's readings are calibrated on a web the pull will change.
Process view only: (a) or (b) keep rule 3 satisfied; (c) breaks run isolation for any reading Council takes from the web. Owner picks; the choice is recorded in this file.
