# Task 7d results: water access tuning

Spec: `docs/specs/water-access-tuning.md` (three pre-declared runs, one parameter each). Base: data defaults (per_being, 0.002). Harness as 7c: `godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols 1500 --every 10 --player watcher --param '<key>=<json>'`, seeds 42 7 99 1234 2026. Script `task-7d-data/run.sh`, scoring `task-7d-data/score.py` (wraps `tools/acceptance_summary.py` load/summarise; dry sols = sample rows with pop > 0 and ice exactly 0, times 10, as in 7c). Raw: `task-7d-data/run<N>/UN_<seed>.txt`.

Key paths: the `--param` key needs the file prefix (`resources.mining.yield_ice`); an unprefixed first attempt failed (`cannot read res://data/mining.json`) and was discarded. A first attempt before `godot --import` failed with a SimData parse error and was also discarded; no results from either. No data defaults were changed.

Columns: first death = first thirst death sol; lead = first thirst death minus first `low` sol (U2 needs >= 10); worst = worst 50-sol population loss starting from pop >= 10 (U3 needs <= 35%). Hygiene on every run: 0 PARAM ERROR, 0 SCRIPT ERROR, 0 ABORTED, 150 rows per file, exit code 1 (known table-failure exit), one data_hash per run, overrides header exactly as declared.

## Run 1: `resources.mining.yield_ice` [6,10] -> [4,7]

data_hash 1db2f34bd4d40845; overrides header `[resources.mining.yield_ice=[4.0, 7.0]`.

| seed | alive@1500 | final pop (sol) | peak | dry sols | low sol | first death | warning lead | worst 50-sol |
|---|---|---|---|---|---|---|---|---|
| 42 | yes | 27 (1500) | 27 | 60 | 303 | 694 | 391 | 12% |
| 7 | yes | 12 (1500) | 21 | 120 | 94 | 493 | 399 | 24% |
| 99 | yes | 3 (1500) | 17 | 280 | 303 | 554 | 251 | 55% |
| 1234 | yes | 12 (1500) | 24 | 260 | 285 | 627 | 342 | 29% |
| 2026 | yes | 15 (1500) | 20 | 140 | 371 | 863 | 492 | 25% |

alive 5/5 guard FAIL; U2 PASS; U3 FAIL

## Run 2: `resources.spawn.ice_px` [90,170] -> [140,175] (alone: Run 1 failed U3 so was reverted)

data_hash 5900ebbcd38e75e6; overrides header `[resources.spawn.ice_px=[140.0, 175.0]`.

| seed | alive@1500 | final pop (sol) | peak | dry sols | low sol | first death | warning lead | worst 50-sol |
|---|---|---|---|---|---|---|---|---|
| 42 | yes | 17 (1500) | 17 | 100 | 292 | 367 | 75 | 18% |
| 7 | yes | 6 (1500) | 19 | 260 | 318 | 726 | 408 | 32% |
| 99 | yes | 27 (1500) | 27 | 50 | 378 | 880 | 502 | 12% |
| 1234 | yes | 27 (1500) | 27 | 30 | 310 | 645 | 335 | 6% |
| 2026 | yes | 20 (1500) | 27 | 100 | 330 | 1003 | 673 | 26% |

alive 5/5 guard FAIL; U2 PASS; U3 PASS

## Run 3: `resources.mine_attempt.chance` 0.4 -> 0.28 (alone: Run 2 failed only the guard but did not lower the alive count, 5 of 5 as at defaults, so it was not carried)

data_hash 7a6623e61f9c7ec2; overrides header `[resources.mine_attempt.chance=0.28]`.

| seed | alive@1500 | final pop (sol) | peak | dry sols | low sol | first death | warning lead | worst 50-sol |
|---|---|---|---|---|---|---|---|---|
| 42 | yes | 2 (1500) | 17 | 370 | 137 | 581 | 444 | 40% |
| 7 | yes | 17 (1500) | 27 | 120 | 377 | 560 | 183 | 26% |
| 99 | yes | 31 (1500) | 31 | 70 | 325 | 588 | 263 | 4% |
| 1234 | yes | 11 (1500) | 13 | 70 | 295 | 391 | 96 | 23% |
| 2026 | yes | 19 (1500) | 28 | 180 | 309 | 1117 | 808 | 12% |

alive 5/5 guard FAIL; U2 PASS; U3 FAIL

## Verdict

| run | alive@1500 | guard (<= 3) | U2 | U3 | result |
|---|---|---|---|---|---|
| 1 yield_ice [4,7] | 5/5 | FAIL | PASS (min lead 251) | FAIL (seed 99: 55%, seed 1234: 29% ok) | fail, reverted |
| 2 ice_px [140,175] | 5/5 | FAIL | PASS (min lead 75) | PASS (max 32%) | fail guard only; alive not reduced, not carried |
| 3 mine_attempt 0.28 | 5/5 | FAIL | PASS (min lead 96) | FAIL (seed 42: 40%) | fail |

No run passed. Stop rule applied: no fourth run. Water scarcity by hauling rate shifted dry sols (e.g. seed 42: 290 at 7c Run 1 baseline, 60/100/370 here) but moved no seed to extinction; every colony still ends the run alive (smallest finals: 3 in Run 1 seed 99, 2 in Run 3 seed 42). Seeds 42 and 99 came within 2-3 beings of extinction in single runs, so the guard is close on some seeds but not stable. Next levers and task split are for the owner per spec section 6 (`want.ice_urgent_below` 30 -> 15, `mining.shift_h`, `scout.chance_per_h`); combinations of runs (e.g. 1+2 together) were not run because the spec fixes the order and one change per run.
