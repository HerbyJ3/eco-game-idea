# Task 7 Plan: Influence powers (finish and merge)

Process document. Every design detail (power numbers, thresholds, HUD wording, what counts as "gradual and readable") lives in `docs/specs/influence-powers.md`, owned by the lead game-designer with designer-emergence, designer-feel, designer-clarity. The project manager does not design. Source of truth: station-zero-handoff/HANDOFF.md (sections 4, 8, 10). Model: `docs/tasks/task-6-plan.md`.

**Status: IN PROGRESS (2026-10-09).** Work branch: `claude/influence-powers-wip` (pushed, head 054c98a, not merged). Main is at ea93c57 (PR #5 water throughput, PR #6 CLAUDE.md). Test command: `godot --headless --path station-zero --script res://tests/run_tests.gd`.

State at takeover: spec rev 1, data/powers.json, SimWorld.use_power / power_ready_in, sim/powers.gd, guide hook in sim/being.gd, HUD keys F1-F5, tools/attentive_player.gd, tests/test_powers.gd (9 pass). Bed-walk fix (Being.sleep_target_id) is committed and changes every pinned 300-sol hash; new hashes measured once only: 42 a298dbb55b71d66e, 7 e540c1b86dabba26, 99 ffb6d5361bdb3a5d, 1234 bca08a0f327892fe, 2026 5fb3b699b4118a84. The first acceptance run (before the bed fix) failed, 2/5 alive. A rerun is in the background: `/tmp/claude-0/exp8/{UN,ATT}_<seed>.txt`, done markers in `/tmp/claude-0/exp8/done.log`. The host has two CPUs: no new Godot runs until all 10 are done.

Owner direction (2026-10-09): the colony is not meant to survive unattended. Unattended decline must be gradual and readable; timely influence must be able to turn it around.

## Steps (each one a commit that runs; the order is the dependency order)

1. [godot-engineer] Merge `origin/main` into `claude/influence-powers-wip` (expected: CLAUDE.md only), push. No Godot runs. Done when: branch contains ea93c57, push succeeded, `git diff origin/main --stat` shows only Task 7 and bed-fix files.
2. Parallel, all read-only, run while the background runs finish:
   - 2a. [code-reviewer] Review merged PR #5 (water throughput) against `docs/specs/water-throughput.md`: switch W3 only changes behaviour, other switches default off, tunables in data/, seeded RNG, tests meaningful. Done when: "approved" or numbered findings with file:line, returned in the reply.
   - 2b. [designer-emergence], 2c. [designer-feel], 2d. [designer-clarity] Each reviews `docs/specs/influence-powers.md` through its own lens, plus the owner direction above. Done when: each returns numbered findings, each marked blocking or advisory, and any owner question.
3. [game-designer] Fold 2b-2d into spec revision 2: record each finding as adopted, rejected with reason, or an owner question. Decide whether the section 5 acceptance still matches the owner direction (it currently tests survival at 1,500 and "first thirst death later"; it does not mention "gradual and readable" unattended decline). Done when: spec rev 2 committed with a review-log section; every power number is a data key; list of owner decisions needed is returned. Rule: if rev 2 changes any power number or the acceptance wording, the acceptance rerun in step 5 is repeated, and only one power number changes per run.
4. [sim-test-engineer], after all 10 files are in done.log: (a) run `/tmp/claude-0/exp/summ.py` on `/tmp/claude-0/exp8/*_*.txt` and report the per-seed table (alive at 1,500, first thirst death, air deaths, EVA deaths, turn-backs) against spec section 5 criteria 2 and 3. Report numbers only, no pass/fail beyond the declared criteria. Check the `overrides=[...]` header of every file. (b) Then re-run the five 300-sol hashes a second time and confirm the five values above are identical. Done when: both reported; mismatch means stop and report.
5. [sim-test-engineer], bed-fix re-baseline: update the pinned hashes (old ones kept as comments) in `tests/age_hash_proof.gd`, `relationships_hash_proof.gd`, `council_hash_proof.gd`, `mood_hash_proof.gd` and `tests/test_council.gd::test_t18c`; add a "Bed-walk fix" section to `docs/balance/water-rebaseline.md` (before/after per seed, run-twice evidence, link from water-throughput.md section 9). Done when: four proof scripts exit 0 on all five seeds; test_t18c passes; section exists with both hash sets side by side. Depends on 4(b). If step 3 changed sim-affecting numbers, redo after step 7.
6. [code-reviewer] Review the branch diff against main (`influence-powers.md` rev 2 and `water-throughput.md` section 9): hash-neutral when powers unused, no tunable literal in code, RNG only from SimRng, sim/view separation (HUD read-only except use_power), guide hook minimal, tests meaningful, attentive_player uses only the public API. Done when: approval or numbered findings.
7. [godot-engineer] Fix blocking findings from 2a (if they touch this branch), 3 and 6; apply spec rev 2 data/HUD changes. Done when: each finding closed or answered in the commit message; `test_powers.gd` green; no behaviour change without a re-run of step 5's hashes.
8. [sim-test-engineer] Acceptance, final: if any sim or data change since the background runs, rerun the 10 Standard 1,500-sol runs (`--every 10`, seeds 42 7 99 1234 2026; unattended and `--player attentive`), two at a time; otherwise reuse step 4(a). Record in `docs/balance/task-7-acceptance.md` with commands, overrides header, and spec rev 2 criteria. Done when: all 10 tables are summarised and criteria 1-3 are stated pass/fail.
9. Decision point (process only):
   - Pass: go to step 10.
   - Fail on criterion 2: report and stop (spec section 5). Do not check off Task 7. [game-designer] names the single power number to change next; [sim-test-engineer] reruns with that one change, repeats at most as the owner allows; each run recorded. Owner is told the result.
10. [sim-test-engineer] Full suite. Done when: exit status recorded; the only failures are the known 94 mood tests (Task 6a not built), same set as before; no new failures; host-speed timing flakes named, not weakened.
11. [code-reviewer] Final check of the fix commits from step 7 and the acceptance doc honesty. Done when: "Task 7 approved".
12. [project-manager] Close: check off Task 7 in HANDOFF section 8, record what changed and what was learned, update this file, name Task 8 as next. Done when: HANDOFF section 8 current (status, owner decisions, branch, next step).
13. [godot-engineer] Open the PR from `claude/influence-powers-wip` to `main`, merge it (working rule 8). Done when: main contains the work; the PR description lists tests run and the new hashes.

## Parallelism
- Steps 2a, 2b, 2c, 2d run together (read-only), alongside the background acceptance runs.
- Step 4 waits for the background runs. Step 5 waits for 4(b). Step 6 can start after step 3 and run alongside step 5 (different files).
- Everything else is sequential. Full-suite and acceptance runs must not overlap (two CPUs).

## Definition of done (Task 7)
- Test command exits 0 apart from the known 94 mood failures; `test_powers.gd` and `test_water_throughput.gd::test_sleep_walk_keeps_its_habitat` pass; four hash-proof scripts pass on five seeds with the run-twice hashes.
- Files exist: spec rev 2 with review log, `data/powers.json`, `sim/powers.gd`, `tools/attentive_player.gd`, `tests/test_powers.gd`, `docs/balance/task-7-acceptance.md`, "Bed-walk fix" section in `water-rebaseline.md`.
- Reviewer approvals recorded for PR #5, the branch diff, and the final fixes; three designer reviews recorded.
- Acceptance (spec section 5 as revised and approved by the owner) stated pass or fail with the numbers. If fail: Task 7 stays unchecked.
- HANDOFF section 8 updated and the branch merged to main.

## Open owner items
- Acceptance wording vs the "unattended should decline gradually" direction: the game-designer proposes, the owner decides.
- Branch `claude/eloquent-franklin-igzhoi` (2 commits not on main: `--tier std` probe option and about 85 raw data files). Not current work; evaluate after Task 7.
- Carried: texture memory 47.1 of 48 MB; real-GPU frame-time rerun; K1.
