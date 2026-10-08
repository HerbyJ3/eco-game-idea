# Task 6 Plan: Later stages (bundle, to be run one slice at a time)

Process document. Every design detail (what emotions, temperament, a prompt, a memory, a sky name or a server world are, thresholds, data keys, HUD words, test targets) lives in a spec the design team writes (lead game-designer with designer-emergence, designer-feel, designer-clarity). The project manager does not design. Source of truth: station-zero-handoff/HANDOFF.md (sections 3, 4, 7, 8, 9, 10). Model: `docs/tasks/task-5-plan.md`. Tasks 0 to 5 done.

**Status: NOT STARTED.** Task 6 is a bundle of four items. Rule 1 (one task at a time) means each item is its own sub-task with its own spec, definition of done and check-off. The queue line in HANDOFF section 8 stays unchecked until all four are done (or the owner descopes some in writing).

Rules in force (HANDOFF 10): design before code, headless tests before visuals, tunables in `data/`, seeded RNG, one balance parameter per run, cheapest suitable model, each step a commit that runs. Test command: `godot --headless --path station-zero --script res://tests/run_tests.gd`.

## 1. Sub-task split (listed in the order of the HANDOFF line; the run order is an owner question, Q1)
- 6p Prerequisites from Task 5 carry-overs (may be folded into a slice by the owner). Goal: settle items the records list as inputs: a public accessor for the relationships packed mirror (carry-over 5), `lines_dropped_by_type` (6), the dome hard-coded in `council.gd` versus a data-driven topic (4), K1 inspect sentence and being inspect panel (Task 4 input 6), texture budget (10). Depends on: nothing. Which of these are in scope is a design/owner call.
- 6a Emotions (Deimos sets temperament). Goal: a per-being emotional layer whose baseline comes from the Deimos placement of the chart (HANDOFF section 3: deimos weight .20, inner boost 1.5). Depends on: persona/sky (done); relationships and council readings if mood is to react to them (design call).
- 6b AI minds. Goal: each being's chart and mood shape its prompt, with a no-LLM fallback and cost control (ai-minds-engineer). Depends on: the Task 6 line names "mood", so a defined mood source (6a, or an owner-defined stand-in) before a prompt can use it; the provider decision (Q4); replaces the fixed conversation lines (HANDOFF section 5, Social).
- 6c Memory and culture (beings name their own sky). Goal: beings keep memory and name the Mars sky/signs themselves, building on the Archive and the Council. Depends on: council topic machinery (6p item on dome hard-coding); the 12 sign names in HANDOFF section 3 are currently fixed colony names; naming text source (fixed lists or 6b) is a design/owner call.
- 6d Persistent world on a server. Goal: the world persists and runs on a server. Depends on: save/load of the sim state and determinism proofs; scope and hosting decisions (Q6); if it is to host AI minds, the 6b decisions.

## 2. Steps for the first slice (slice = whichever the owner picks in Q1; same shape as Task 5)
Each step is one runnable commit. "Slice" below means that sub-task only; the other three do not start.
1. [game-designer, with designer-emergence, designer-feel, designer-clarity] Spec `docs/specs/<slice>.md` with numbers and `data/` starting values, section 3 constraints answered per mechanic, owner questions answered. Check: every number is a data key; new sim state, RNG use and hash effect listed; three assistant reviews recorded.
2. [code-reviewer] Read-only spec review (testability, data keys, hash and RNG statement, tick budget, sim/view separation). Check: approval or numbered findings; findings go to step 1.
3. [sim-test-engineer] Tests first, red: `tests/test_<slice>.gd` from the spec's test list, including purity, determinism, key-path parity and hash reproduction. Check: fail for the right reasons; earlier tests unchanged; no test with zero checks.
4. [godot-engineer; ai-minds-engineer for emotion/prompt content; asset-pipeline only if the owner allows art] Implementation in `sim/` plus `data/`, one hook in `SimWorld.step()` at most, stats and log events per spec. Check: new tests green, full suite green, seeds 7 and 42 determinism green.
5. [sim-test-engineer] Calibration probe and `docs/balance/task-6<x>-calibration.md`: seeds 42, 7, 99, 1234, 2026 at 300 sols. Recalibration edits `data/` only, one parameter per run, value chosen by the game-designer. Check: all five seeds measured; open questions go to the game-designer.
6. [sim-test-engineer] Balance integration: columns and targets in `tests/balance_lib.gd` and `balance_run.gd`; `docs/balance/task-6<x>-log.md`. Check: T1 to T12 and the spec's targets pass; old columns byte-identical (or reset recorded); reruns identical; per seed before/after, including Settlement and Council entry sols.
7. [code-reviewer] Final sim review: diff outside the new module and its hook empty or justified; no tunable literal; RNG matches spec; no secrets or network code in `sim/`; earlier tests untouched; logs honest. Findings fixed before step 8.
8. [godot-engineer] View/HUD per the spec's clarity section only (sim read-only; no art unless approved). Check: HUD tests green, `--quit-after 5` prints no errors, shots in `docs/shots/task-6<x>/` non-blank and read by the main session, tick/boundary cost and `advance()` budget re-measured in `docs/perf/task-6<x>-*.md`.
9. [code-reviewer] Re-check of the view diff. Check: approval recorded.
Closing: [project-manager] record what changed and what was learned in this file and HANDOFF section 8; check off Task 6 only when all four slices are done.
Schedule trade-off (process only): step 8 is last so sim work is reviewed and balanced first; it is first to move if time runs out, unless the owner says otherwise.

## 3. Definition of done (per slice)
- Test command exits 0: all earlier tests plus the slice's test file; key-path parity for new data files; determinism green.
- Five seeds at 300 sols: T1 to T12 and the spec's targets pass, hashes per owner answer (Q2), reruns identical, per-seed behaviour documented.
- Files exist: slice spec, new data file(s), new sim module, slice test file, probe tool, calibration and log docs, shots (if view in scope), perf note.
- Reviewer approvals (steps 2, 7, 9) recorded; this plan and HANDOFF section 8 updated.

## 4. Constraints carried
- Hash chain: the five Task 1 hashes (02032b23..., 830c7d0c..., 0e3e83a7..., bca6eb2c..., 2645033a...), the Task 3 and Task 4 hashes, and the Task 5 `council_hash_proof` (cn column) must reproduce with new columns dropped, or the owner approves a reset (new hashes, each seed run twice, old and new side by side in the log).
- RNG: no draws outside the seeded SimRng; the spec states per mechanic whether it draws and from which stream. View code keeps its own RNG.
- Sim/view separation: sim headless and pure; view read-only on the sim.
- Tunables only in `data/*.json`; no literal in code; key-path parity tests.
- `stats.age_history` shape fixed (`{age, how, cause, text, pop, family_mars_born, t, sol, clock_sol}`); no meters or progress bars.
- Texture memory 47.1 of 48 MB: no new art unless the owner decides the budget.
- Cost: C8 at 5.0 ms median / 16.7 ms peak step; relationships tick <=8 ms median and <=20% of mean step; boundary-step spike about 22 ms; seed 1234 in Council age peaks 13.7 ms (not proven by construction); `advance()` 8 ms wall budget. Re-measure after any per-tick work.
- Known issues, stated per seed and not silently fixed: K1, K2, K3 (Task 4); Task 5 items: C5 passes only at its minimum, first raise at the 5-sol minimum on 3 seeds, spec section 11 numbering differs from perf doc. Host-speed timing tests are flaky and not to be weakened; frame-time triggers need a real-GPU rerun.
- AI minds specifically: (a) cost control: token budget per colonist per sol, batching, caching, hard daily spend cap, calls rate-limited, graceful no-LLM fallback; (b) no API keys, network code or provider SDK in `sim/`; keys live outside the repo and are never committed; (c) determinism: an LLM output must not feed back into the hashed sim unless the owner decides it may; default is display-only and excluded from hashes; (d) tests run with no network; LLM calls are mocked or replayed from recorded fixtures.

## 5. Open owner questions (lead designer puts these with the assistants' options; the PM recommends none)
- Q1. Which slice goes first, and the order of the rest; whether 6p carry-overs are a slice of their own or folded in; whether any slice is descoped from Task 6.
- Q2. Hashes: must earlier hashes stay byte-identical, or may emotions/culture change colony behaviour (owner-approved reset)?
- Q3. Emotions: do they change behaviour or only display; what Deimos sets (temperament) versus what events set; what the player sees.
- Q4. AI minds, model and provider: which model and provider, budget (per colonist per sol, per day, per month), spend cap behaviour.
- Q5. AI minds, where it runs: local model versus API; offline play; whether output may change behaviour (feed the sim) or is display-only; what happens on failure.
- Q6. Server: scope (single shared world, per-player worlds, observers only), hosting, cost ceiling, who may connect, save format, whether simulation stays deterministic server-side.
- Q7. Culture: what beings may name (signs, places, ages), who sees names, whether names are fixed lists or generated, relation to the 12 fixed sign names and to the god-awareness idea (HANDOFF section 4, owner said yes).
- Q8. Texture budget (47.1 of 48 MB): is new art allowed, and is the budget raised or something freed.
- Q9. Randomness: any draws, and from which stream.
- Q10. Balance targets, cost budget, and seeds for 300 sols per slice.
