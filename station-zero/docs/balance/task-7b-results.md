# Task 7b results

## Lever 1: `death.thirst_interval_h` 5 -> 50 (UN set)

Run: `godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols 1500 --every 10 --player watcher --param colony.death.thirst_interval_h=50`, seeds 42 7 99 1234 2026, two at a time, same flags as task-7 acceptance. Raw output: `docs/balance/task-7b-data/lever1/UN_<seed>.txt`, `done.log`.

Validity: all 5 headers show `overrides=[colony.death.thirst_interval_h=50.0]`, `data_hash=b4f496d3af9b1fe0` (baseline `fcb5ff2f0fbf63a1`, so the override acted). 0 PARAM ERROR, 0 SCRIPT ERROR, 0 ABORTED; all 5 finished (exit 1, the known table failures). Metrics from the `load`/`summarise` functions of `tools/acceptance_summary.py` (run on the lever1 dir; the script's `main` needs C1/C2 files, so it was not run whole). Baseline in brackets, from `task-7-acceptance-data`.

| seed | U3 worst 50-sol loss (start pop) | low_sol | first thirst | lead | alive@1500 (pop) |
|---|---|---|---|---|---|
| 42 | 11% (19) [100% (12)] | 292 [292] | 812 [333] | 520 [41] | yes (20) [no] |
| 7 | 50% (10) [31% (13)] | 320 [320] | 342 [341] | 22 [21] | no (0) [no] |
| 99 | 3% (30) [100% (19)] | 371 [371] | 1180 [617] | 809 [246] | yes (33) [no] |
| 1234 | 4% (24) [43% (14)] | 310 [310] | 918 [563] | 608 [253] | yes (30) [yes (10)] |
| 2026 | 3% (31) [67% (18)] | 327 [327] | 1252 [464] | 925 [137] | yes (35) [yes (8)] |

## Rule (task-7b-plan step 3)

- U3: FAIL. Seed 7 loses 50% in a window starting at sol 490 with pop 10 (limit 35%). The other four pass. Failing seeds 4 -> 1; worst loss 100% -> 50%.
- U2: pass. lead >= 10 on all seeds, low_sol > 0 on all, none regressed.
- U4 guard: FAIL. 4 of 5 seeds alive at 1,500 (baseline 2); the guard allows at most 3.

**Verdict: REVERT** (U4 guard broken: "4 or more seeds alive at sol 1,500"). By the written rule, KEEP is not available because KEEP requires the U4 guard to hold; PASS is not available because U3 fails on seed 7 and U4 fails.

Notes for the owner/designer (not part of the verdict): the lever clearly fixes U3 on 4 seeds and the colony still dies on seed 7, which is a small colony (peak 13) that is dry-state-killed within ~22 sols of the first thirst death. The U4 guard conflicts with the 50 h value: at 50 h the unattended colony is mostly fine alone. A value between 5 and 50, or lever 2 (`death.chance`) alone, would be a different experiment; not run.
