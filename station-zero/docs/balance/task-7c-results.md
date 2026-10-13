# Task 7c balance results

## Run 1: `colony.death.thirst_mode` = "per_being" (thirst_being_chance 0.002, data value)

Date 2026-10-12, branch `claude/task-7c-per-being-thirst`. Unattended (UN) set, same harness as Task 7 / 7b.

Command (seeds 42 7 99 1234 2026, two at a time; script `docs/balance/task-7c-data/run1/run.sh`):
`godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols 1500 --every 10 --player watcher --param 'colony.death.thirst_mode="per_being"'`
(`--param` values are parsed as JSON, so the string needs its quotes; an unquoted first attempt failed at parse and was discarded, no output kept.)

Overrides header check: all 5 headers show `overrides=[colony.death.thirst_mode=per_being]` and nothing else; `data_hash=e1d5e1add9f157c4` (baseline `fcb5ff2f0fbf63a1`, so the override acted). The header prints strings without quotes; the String type rests on the quoted JSON value passed and on `balance_lib.gd` rejecting type mismatches (no PARAM ERROR). 0 PARAM ERROR, 0 SCRIPT ERROR, 0 ABORTED, 150 sample rows per file. Exit code 1 on all (known table-failure exit, as in 7/7b).

Metrics: `load`/`summarise` of `tools/acceptance_summary.py` (U3 windows: 50 sols between sample rows, start pop >= 10). Raw: `docs/balance/task-7c-data/run1/UN_<seed>.txt`.

| seed | low_sol | first thirst sol | lead | worst 50-sol window (start sol, start pop, loss) | pop at 1,500 | peak | thirst deaths |
|---|---|---|---|---|---|---|---|
| 42 | 292 | 574 | 282 | 570, 17, 18% | 15 (alive) | 17 | 11 |
| 7 | 320 | 379 | 59 | 340, 13, 15% | 22 (alive) | 23 | 13 |
| 99 | 371 | 1400 | 1029 | 1380, 33, 3% | 35 (alive) | 35 | 2 |
| 1234 | 310 | 625 | 315 | 1170, 19, 16% | 15 (alive) | 22 | 14 |
| 2026 | 327 | 464 | 137 | 1170, 22, 14% | 15 (alive) | 23 | 17 |

(Thirst deaths = second field of the cumulative `dead a/t/h/o/x` column at sol 1,500; the other four fields are 0 on every seed.)

Verdicts:
- U2 (lead >= 10 on every seed with a thirst death, low_sol > 0): PASS (min lead 59, seed 7).
- U3 (no 50-sol window from pop >= 10 loses > 35%): PASS (worst 18%, seed 42).
- Guard (at most 3 of 5 alive at sol 1,500): FAIL, 5 of 5 alive.

Spec next step (`docs/specs/per-being-thirst.md` pre-declared runs): U3 passes but 4 or more seeds are alive, so row **2b applies: thirst_being_chance = 0.0028**, one override only. Run 2 not run.
