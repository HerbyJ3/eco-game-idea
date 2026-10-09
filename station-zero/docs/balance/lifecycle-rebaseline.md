# Calendar-lifecycle re-baseline

Owner decision (2026-10-09): commit e1f2bdd ("Add calendar lifecycle, fix building cutaways, and prepare 2D art handoff") is the NEW simulation baseline. This note records the reset. Nothing was tuned: no file in `sim/` or `data/` changed in this step. Every number below was measured in this step on branch `claude/eloquent-franklin-igzhoi` (tree = e1f2bdd plus docs-only art commits) with `tests/balance_run.gd` (seed, 300 sols, rows every 30), `tests/council_hash_proof.gd`, `tools/relationships_probe.gd`, `tools/council_probe.gd` and `tests/run_tests.gd`. "Before" numbers are the ones in `docs/balance/task-5-log.md` (Tasks 1-5, data_hash `10338cdd9a4637ad`); "after" is data_hash `c370381b5ad96932`. Raw output: `docs/balance/lifecycle-rebaseline-data/` (`.gdignore`d).

Note for whoever repeats this: after pulling e1f2bdd the global class cache was stale (`Lifecycle` not found, every script errored). `godot --headless --path station-zero --import` once fixed it; `.godot/` is git-ignored.

## 1. What changed in the simulation (e1f2bdd mechanisms)

Spec: `docs/specs/lifecycle.md`, `data/lifecycle.json`, `sim/lifecycle.gd`.

| mechanism | effect on the balance numbers |
|---|---|
| Pregnancy lasts 9 calendar months (`pregnancy_months` 9). Conception only records a pregnancy; the colonist and the `born` line appear at delivery. | One sol is 24.6597 h, so 9 months (273 to 275 days) is about 266 to 268 sols. The first conception happens around sol 13 to 25 as before, and the first birth moves from sol 13 to 26 to sol 280 to 292. Before sol ~280 population is the 7 founders. |
| Pending pregnancies reserve a population place (`birth_gates_ok(..., pending_births)`), and the per-home conception cooldown still applies. | No capacity effect yet at pop 7 to 12; it only shows in how many conceptions are pending at sol 300 (probe `pregnant` lines 10, 6, 7, 8, 5 against 5, 5, 4, 3, 5 births). |
| Only adults conceive (`can_conceive`), and the birth gate counts only adult beings inside a habitat. Founders keep their Earth birth records (adults); newborns start as babies. The `SimWorld.add_being` test fixture now gives `born_t` 18 calendar years back (adult at once), so tests that add beings keep working. | Founders are the only parents for the whole 300 sols. |
| Adults only for construction readiness (`_builder_ready`), mining, construction and EVA jobs; babies rest and do not travel; younger colonists only rest and take indoor trips (`Being.decide`). | Not yet visible in 300 sols (no child is older than about 20 sols), but it means no newborn adds labour for 18 years. |
| Council voice is "is an adult" (`Lifecycle.is_adult`), replacing `voice.min_age_sols` 40 (key removed from `data/council.json`). | Only the 7 founders (6 on seed 7 after a death) are voices for all 300 sols. |
| Ages: Settlement entry still needs `entry.mars_born_min` 5 Mars-born colonists and `mars_born_homes_min` 2 (`data/ages.json`, unchanged). | With the first birth at sol ~280, five births happen at the earliest around sol 290, so Settlement is reached only on seed 42 (sol 290). Council entry needs Settlement, so it is never reached. This is the single mechanism behind the T10, T12, C1 to C5 changes. |

## 2. Run-twice evidence and new hashes

Command: `godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols 300 | head -c 200000`. Each seed was run twice (`run_seed_N.txt`, `rerun_seed_N.txt`, whole output); `cmp` reported the pair byte-identical on all five seeds. The balance run exits 1 on all five (T10 fails everywhere), as expected on this baseline.

Table hash = first 16 hex digits of sha256 of the table body (with `age`, `web`, `cn`); the three drop-column hashes come from `tests/council_hash_proof.gd` (`hash_proof_council.txt`).

| seed | full table (Task 5 level), old | full table, NEW | drop `cn` (Task 4 level), old | drop `cn`, NEW |
|---|---|---|---|---|
| 42 | 330325504427720a | 6dd003aef320196b | a96b8a9562fd75d0 | 5cae292b785e5de7 |
| 7 | 1ceb89a7d3e87540 | bd45d3b3c0690911 | a4968e2fcc48ec36 | 257dc2bda6b29981 |
| 99 | 7feb81cee7c86fa5 | 0d8e25bd9b7b056f | 2210719cf48d8612 | d31bc86c094bcff4 |
| 1234 | 7c8bcf782a06f1fa | 539156aead08fb41 | 19437e397d1dff88 | bc78b23075c71ef4 |
| 2026 | 076e42c032a208aa | 3ab707732c622968 | 6e7fe68477161196 | f404077296a86f66 |

| seed | drop `cn`, `web` (Task 3 level), old | NEW | drop `cn`, `web`, `age` (Task 1 level), old | NEW |
|---|---|---|---|---|
| 42 | da166c4f8b202820 | 5c590177e627b03c | 02032b2388529913 | f8750bee8424a3f1 |
| 7 | 30c53f90949d979b | d9aead4bf953ad7e | 830c7d0c441823f5 | 0491abf46338c256 |
| 99 | 54ad1e15b934bf9a | 6c0df749c1c1e7ec | 0e3e83a7108140ef | 2463601427badf0b |
| 1234 | 7052c92936a75157 | 9ea6315f71b0c371 | bca6eb2ca93ba0c1 | 86b199e697f98d0a |
| 2026 | 67e3dcf057200eb9 | 798b786bae4905c1 | 2645033a417ec400 | 12ebeb75ad29220c |

All 15 pre-lifecycle checks differ on e1f2bdd (`hash_proof_pre_update.txt`, run before the constants were touched). With the constants updated, `council_hash_proof.gd` reports MATCH on all 15 checks (exit 0, `hash_proof_council.txt`), `relationships_hash_proof.gd` MATCH on all 10 (exit 0), `mood_hash_proof.gd` MATCH on all 20 hash checks (md column ABSENT, exit 0).

Are the drop-column chains still meaningful? Partly. The Task 1 level changed too (f8750bee... against 02032b23... on seed 42): the lifecycle changes the Task 1 columns themselves (population, births, stocks, trips). So the chain no longer proves "equal to the Tasks 1-5 behaviour"; it proves only the new baseline: that the `age`, `web` and `cn` columns (and any later observer-only column such as `md`) can be stripped back to the hashes recorded here, i.e. that those modules do not change the Task 1 columns on the lifecycle baseline. It cannot detect a difference from the pre-lifecycle behaviour, and the old hashes are kept only as history.

Pre-existing quirk, not changed: `tests/age_hash_proof.gd` run alone prints "column absent ... DIFFERENT" on all five seeds (exit 1), because it strips `age` only when `age` is the last header field and `cn` is now last. The same would have happened on the Task 5 tree. The Task 1 hash is proven through the chain in `council_hash_proof.gd`, `relationships_hash_proof.gd` and `mood_hash_proof.gd`.

## 3. Targets T1 to T12 per seed (after)

T9 (determinism) is N/A in the run and is satisfied by the run-twice `cmp` above.

| seed | T1 | T2 | T3 | T4 | T5 | T6 | T7 | T8 | T10 | T11 | T12 | RESULT |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 42 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | **FAIL** | PASS | PASS | FAIL |
| 7 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | **FAIL** | **FAIL** | PASS | FAIL |
| 99 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | **FAIL** | PASS | PASS | FAIL |
| 1234 | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | **FAIL** | **FAIL** | PASS | FAIL |
| 2026 | PASS | PASS | PASS | PASS | **FAIL** | PASS | PASS | PASS | **FAIL** | PASS | PASS | FAIL |

Before: every cell PASS on all five seeds (RESULT PASS).

Failures, with the measured reason:
- T10 on all five seeds (ages): first Settlement sol is 290 on seed 42 (target 40 to 150) and never on seeds 7, 99, 1234, 2026 (age at end Landing, `sols_in_age` landing 300). Cause: Settlement needs 5 Mars-born colonists and the first birth is at sol 280 to 292.
- T11 on seeds 7 and 1234 (relationships), clause 2: lonely mean of the last 50 readings 0.365 and 0.547 against max 0.35 (before 0.039 and 0.159). Population is 9 to 10, so one lonely colonist moves the reading by 0.1 or more.
- T5 on seed 2026 (power): demand above supply on 3.44% of steps (limit 10, passes), max offline 254.4 h (limit 24.7, FAILS), max shorts per sol 1 (limit 2). 10 not-ok sols are power-caused on that seed. Not investigated beyond the measurement.

## 4. Before and after, per seed (300 sols)

### Population, births, deaths

| seed | pop at 300, before / after | births at 300, before / after | first birth sol, before / after | deaths, before / after |
|---|---|---|---|---|
| 42 | 164 / 12 | 167 / 5 | 13 / 280 | 10 thirst / 0 |
| 7 | 72 / 9 | 65 / 5 | 19 / 286 | 0 / 3 thirst (all in the last 30 sols, ice at 0.0) |
| 99 | 157 / 11 | 172 / 4 | 26 / 292 | 22 thirst / 0 |
| 1234 | 142 / 10 | 135 / 3 | 21 / 288 | 0 / 0 |
| 2026 | 156 / 12 | 154 / 5 | 18 / 285 | 5 thirst / 0 |

Population is exactly 7 (the founders) on every 30-sol row up to sol 270 on all five seeds. After: pop@100 is 7 on every seed (before 57, 32, 72, 65, 47). The seed 7 line has 12 people at its peak and 9 at the end (3 thirst deaths). The "ice ran dry" pressure of the old runs (3 seeds, up to 22 thirst deaths) is gone because the colony stays small: T4 now reports ice dry only on seed 7 (min ice 0.0, 3 deaths); min ice on the others 14.8, 33.1, 26.5, 23.8.

Other windows that moved (all PASS): T6 construction limited by crew 56.98 to 76.53% of hours (before 18.99 to 70.43%; site_no_crew dominates), T7 trips 203 to 241 (before 853 to 2394).

### Ages (Task 3 / T10)

| seed | settlement sol before / after | age changes before / after | fall-backs before / after | sols_in_age landing / settlement / council, before | after |
|---|---|---|---|---|---|
| 42 | 67 / 290 | settled 67, council 115, fell_back 213 (ice) / settled 290 | 1 (sol 213, ice) / 0 | 154 / 48 / 98 | 290 / 10 / 0 |
| 7 | 58 / none | settled 58, council 95 / none | 0 / 0 | 58 / 37 / 205 | 300 / 0 / 0 |
| 99 | 54 / none | settled 54, fell_back 174 (ice) / none | 1 (sol 174, ice) / 0 | 180 / 120 / 0 | 300 / 0 / 0 |
| 1234 | 65 / none | settled 65, council 160 / none | 0 / 0 | 65 / 95 / 140 | 300 / 0 / 0 |
| 2026 | 53 / none | settled 53, council 206 / none | 0 / 0 | 53 / 153 / 94 | 300 / 0 / 0 |

### Relationships (T11 and probe R targets; probe `tools/relationships_probe.gd --pull shipped`, run four in parallel; reports in `relationships_probe_seed_N.txt`)

| reading at sol 300 | seed 42 before / after | 7 | 99 | 1234 | 2026 |
|---|---|---|---|---|---|
| web | 0.51 / 0.92 | 0.97 / 0.78 | 0.57 / 0.82 | 0.87 / 0.40 | 0.35 / 0.83 |
| lonely | 0.40 / 0.08 | 0.03 / 0.22 | 0.29 / 0.00 | 0.12 / 0.30 | 0.37 / 0.17 |
| lonely mean, last 50 (max 0.35) | 0.307 / 0.326 | 0.039 / **0.365** | 0.313 / 0.249 | 0.159 / **0.547** | 0.327 / 0.254 |
| friends_mean (1.0 to 15.0) | 2.01 / 2.00 | 12.67 / 2.00 | 1.78 / 1.64 | 7.56 / 1.00 | 1.28 / 2.83 |
| first friendship sol | 45 / 83 | 34 / 99 | 68 / 137 | 41 / 250 | 54 / 160 |

Probe targets that changed verdict (no tuning, all measured):
- R6 (capped-kind relationship lines at least 1.0 per 5 sols, sols 20 to 299): FAIL on all five seeds, 0.21, 0.16, 0.14, 0.11, 0.20 (before PASS on all five, task-4-log).
- R3 (same figure as T11 clause 2): FAIL on seeds 7 and 1234.
- R10 (selectivity ratio at least 2.0): FAIL on seed 2026 (1.50 = 3.75 / 2.50; before 2.33); seed 1234 sits exactly at 2.00 (PASS at the bound); seed 42, 7, 99: 2.20, 2.33, 2.33 (before 6.59, 2.49, 4.82).
- R1 (kin newborns' median birth-to-first-friend wait, at most 30): PASS with 6.0, 5.0, 8.0, 6.5, 5.0 sols (before 28, 25, 29, 26, 29), but on only 1 to 5 resolved newborns (seed 99: 1 resolved, 3 unresolved), so it is not comparable.
- R12 first newcomer line sol 83, 99, 137, 250, 160 (before 45, 34, 68, 41, 54): the judged lower bound passes; the reported "by sol 55" upper bound is over on all five (before over on seed 99 only).
- R13 `found_friend` per 5 sols over sols 150 to 299: 0.07, 0.10, 0.13, 0.00, 0.13 (before 1.80, 0.33, 2.37, 2.30, 2.10), PASS (ceiling).
- R2, R4, R5, R7, R11, R14 PASS on all five.
Caveat on the probe: `tools/relationships_probe.gd` still carries `VOICE_MIN_AGE_SOLS` 40 for its own Council-gate recomputation; that part is not used for R1 to R14 and the Council gate rows of this probe were not used here.

### Council (T12 and probe C1 to C8; `tools/council_probe.gd --tag base` plus `--judge`; `council_probe_seed_N.txt`, `council_probe_judge.txt`)

| item | before | after |
|---|---|---|
| first Council sol | 115, 95, none, 160, 206 | none on all five seeds |
| Council changes | 1, 1, 0, 1, 1 | 0, 0, 0, 0, 0 |
| proposals / meetings | 2 / 19, 3 / 41, 0, 1 / 28, 1 / 18 | 0 / 0 on all seeds |
| pledges | seed 1234 at sol 195 (personal), seed 2026 at sol 221 (personal) | none |
| carry-quorum margin (`decide.carry_quorum` 0.35) | seed 1234 cleared it by 0.02 at its pledging votes (yes over voices 0.37 at sol 190, 0.41 at sol 195) | no vote was held, so there is no margin to read |
| voices at sol 300 | pop 72 to 164 | 7 on all seeds except seed 7 (6) |

| target | before | after |
|---|---|---|
| C1 entered by sol 300 on at least 3 of 5 seeds | PASS (4 seeds) | **FAIL** (0 seeds) |
| C2 entry at least 30 sols after Settlement, dwell | PASS | PASS, vacuous (no entry) |
| C3 at most 4 Council changes | PASS | PASS, vacuous (0 changes) |
| C4 a pledge on at least 1 seed | PASS (2 seeds, after O6) | **FAIL** (0 seeds) |
| C5 a divided or set-aside line on at least 2 seeds | PASS (seeds 42, 7) | **FAIL** (0 seeds) |
| C6 trait-consistent at 80% of divided votes | PASS (6 of 6) | n/a (no divided vote) |
| C7 at most 1.0 Council lines per 5 Council sols | PASS | PASS, vacuous (no Council sols) |
| C8 cost | PASS (restated, run alone) | PASS, vacuous (no sol above pop 120; probe runs were made in parallel) |
| flags FLOOR web / FLOOR chosen | not flagged | FLAGGED in the probe's judge, but only because no seed has a gate-live window (n/a); CEILING and SIZE-DOMINANT n/a; LOCKSTEP and NOROOM clear |

Task 3 projected ages no longer equal the Task 3 values (the probe's "Task 3 first settle" column reads DIFFERS on all five seeds, as above).

## 5. Which owner-visible results moved, and by how much

- Population at sol 300: from 72 to 164 down to 9 to 12, a drop of 85 to 94%. Nothing but the 7 founders exists before sol ~280.
- First birth: sol 13 to 26 becomes sol 280 to 292 (about 267 sols of gestation).
- Settlement: sol 53 to 67 becomes sol 290 on one seed and never on four. No Council at all on this horizon; no pledge, no dome decision.
- Deaths: thirst deaths of 5, 10 and 22 on three seeds become 0, with 3 on seed 7 in the last 30 sols.
- Relationships: friends_mean of 12.67 and 7.56 (seeds 7, 1234) becomes 2.00 and 1.00; first friendship moves 34 to 68 -> 83 to 250; the lonely signal fails T11 on two seeds.
- Traffic: trips over 300 sols fall from 853 to 2394 to 203 to 241.
- Anything in the owner's earlier calibration conclusions that relied on population growth (the carry-quorum fit, the dome votes, the ice-dry pressure) is not exercised on this baseline in 300 sols.

Flagged without tuning: T10 (all seeds), T11 (seeds 7 and 1234), T5 (seed 2026), R6 (all seeds), R10 (seed 2026), C1, C4, C5 (and C6 undefined). The 300-sol horizon no longer reaches the generational part of the design (spec lifecycle.md: "their calibration must be reconsidered for generational growth"); a longer horizon (several sim years) or a lifecycle-aware set of targets is the owner's call.

## 6. Test constants updated

The expected-hash constants now hold the new baseline; the old values are kept as comment blocks headed "pre-lifecycle baseline (Tasks 1-5)":
- `tests/age_hash_proof.gd` (`EXPECTED`, Task 1 level)
- `tests/relationships_hash_proof.gd` (`EXPECTED_T3`)
- `tests/council_hash_proof.gd` (`EXPECTED_T4`)
- `tests/mood_hash_proof.gd` (`EXPECTED_T5`, full table; the Task 6a proof only reads it, nothing in the stash or `wip/6a-dormant` was touched)
- `tests/test_council.gd` test_t18c (pinned the T4 values literally) and `tests/test_moods.gd` test_t25a (now reads these hashes from this file instead of `task-5-log.md`; the test itself is still parked red for lack of the mood module).

## 7. Full suite (`tests/run_tests.gd`, `full_suite.txt`)

638 PASS, 96 FAIL. 94 of the failures are the parked mood tests (`test_moods`, `test_view_moods`: "missing API", the dormant 6a work). The other 2 are the known host-speed timing tests: `test_view_model::test_perf_perf` and `test_world_beings::test_model_update_stays_under_budget_with_160_beings` (median 2.008 ms against 2.0 ms). No other failure.
