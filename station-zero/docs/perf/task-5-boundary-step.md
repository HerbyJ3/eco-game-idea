# Task 5: the whole boundary step at pop > 120 (spec council.md 11.1 trigger)

Tool: `tools/boundary_profile.gd` (timers outside sim/; a copy of `SimWorld.step()` that times the phases; `--check` runs plain `step()` instead).
Seeds 42 and 1234, 300 sols, each run alone, one after another. Microseconds, whole `step()` on sol-boundary steps.
Absolute numbers are machine-specific and vary run to run by several ms on the spike steps (see C).

## A. Attribution (before the remedy)

Whole boundary step, pop > 120:

| seed | Council | n | median | p95 | max |
| --- | --- | --- | --- | --- | --- |
| 42 | on | 89 | 5508 | 10064 | **22543** |
| 42 | off | 89 | 2850 | 6886 | **14188** |
| 1234 | on | 81 | 6416 | 14094 | **22204** |
| 1234 | off | 81 | 2829 | 7704 | **12698** |

Council off (relationships on) stays under 16.7 ms, so the Council's cost is what takes the max over the trigger. The Council is not the only
thing there: its off-maximum is 12.7 to 14.2 ms, and that is all relationships, ages and beings.

Where the max spikes fall (council on):
- **Seed 42, sol 291 (22.5 ms), age Landing**: relationships `on_step` 14.8 ms (a relationship tick lands on the sol-boundary step), `council.on_sol` 2.9,
  births 0.9 (a birth on that step), update_beings 1.8, ages `on_sol` 0.7, relationships `on_sol` 0.7. Next spikes: sols 294 (12.3, tick 6.3 + council 2.8), 288 (11.8, tick 6.3 + council 2.6),
  all Landing, all tick-on-boundary. Non-tick spikes (sols 275, 283, 234) are 10 to 11.5 ms with `council.on_sol` 4.4, 7.4, 4.2 and update_beings up to 4.2.
- **Seed 1234, sol 291 (22.2 ms), age Council**: tick 9.3, `council.on_sol` 5.6, births 1.6, `council.on_step` 0.5 (gathering scan on the tick), rel `on_sol` 1.3, update_beings 1.9.
  Next: sol 282 (15.3, no tick, `council.on_sol` 8.1), 294 (14.6, tick 8.0 + council 3.6).
- With the Council off the spikes are the same steps: tick-on-boundary (rel `on_step` 8 to 10 ms) plus births (about 1 ms) and the ages/relationships sol hooks.

Council share at pop > 120 (median `on_sol`): 2412 us (42), 3320 us (1234); max `on_sol` 7352 and 8129 us. Pop > 120 boundary steps with a tick are 30 to 50 percent of the spikes.
The 1234 run is in Council age at pop > 120 (Landing only for 64 boundaries early); seed 42 is Landing at pop > 120 for all 89 sols.

## B. Remedy (1): skip trust and sway in Landing (built; (2) not needed)

`Council.on_sol` in Landing: `_readings` (pair walk, union-find, friend lists) and `_lean_stance` (lean and sway) are skipped. `trust_by_sol` and
`chosen_by_sol` carry the last reading forward (same length as `pop_by_sol`); the entry windows are not pushed; the hard window, lineage record,
aftermath, lapse and flush are unchanged. `st.trust/chosen/voices` and `stance` keep their last values.
Why gate-identical: Landing never enters, the windows hold 20 readings and clause 1 needs 30 settled sols, so every reading the gate or a split uses is
taken in the current Settlement term (the window is refilled before it can matter).

Proof (all five seeds, 300 sols):
- `tests/council_hash_proof.gd`, all three checks, full lines in C: 15 of 15 MATCH.
- stats.council digest: the probe's digest (pop, births, deaths, age_history, all of stats.council) differs by construction in the Landing-boundary series entries
  and in the live reading if a run ends in Landing, so `boundary_profile.gd` masks exactly those entries and compares. Before (stashed remedy) and after are equal on all five seeds:
  42 `30faa2ad1f0baaae` (154 Landing boundaries), 7 `2703ce70c6e73d7c` (57), 99 `379a0166091f3d6b` (180), 1234 `7720523daf243abc` (64), 2026 `1d3c6a5b2ab615e4` (52). The world digest
  (positions, energy, log size, age history size) is also unchanged: 42 `3ea2b8a28efd2b21`, 1234 `e5a4fa486e1d02a5`, 7 `570ea0b034c25cbc`, 99 `482d27c58bb30722`, 2026 `dca5e0b8ac836c9d`.
  Not bit-identical, said plainly: the first Settlement stance is built from a decayed Landing stance in the old code (weight 0.5 per sol) and from the lean alone now. The difference is below
  2^-30 by the first meeting (30 settled sols later) and shows in no count or threshold on the five seeds (the digest holds counts, not stances).
- Tests: `tests/test_council.gd` stages worlds in Settlement now (`_world()` sets the age; the Landing skip made every Landing-staged reading test read zeros); new test
  `test_t02p_landing_skips_the_readings_and_carries_the_series_forward` (series length, carry-forward, windows untouched, and 20 Settlement readings give windows, gate parts and readings equal to a world that read
  throughout). Full suite: 620 tests, 42589 checks, 1 failure, the view-model perf test `test_view_model::test_perf_perf` (median 2.016 ms against 2.0, a view test the change cannot touch; it
  passed in the full run just before and fails/passes on timing alone). `test_council` and `test_council_balance` green.

After (Council on, relationships on, remedy built), whole boundary step at pop > 120:

| seed | run | median | p95 | max | max before |
| --- | --- | --- | --- | --- | --- |
| 42 | 1 | 3002 | 8153 | **12529** | 22543 |
| 42 | 2 | 3287 | 7183 | **12278** | |
| 1234 | 1 | 6645 | 11377 | **13672** | 22204 |
| 1234 | 2 | 5743 | 10722 | **13722** | |

Seed 42: `council.on_sol` median 2412 to 113 us at pop > 120, max 7352 to 1915 us. The 22.5 ms spike (tick on the boundary) is now 11.2 to 12.3 ms: the tick itself
varied 6.3 to 14.8 ms between runs, so a good part of that spike was machine noise and not the Council.
Seed 1234 is in Council age at pop > 120, so remedy (1) does not touch it (`on_sol` median 3174 / 2985 us, same as before). Its 22.2 ms first reading did not repeat: the same sol 291 is 12.2 and 12.0 ms
in the later runs (tick 5.6 vs 9.3 ms, births 0.8 vs 1.6 ms). Both of its later runs are under 16.7 ms (13.7, 13.7) with 3 ms of margin, and the first run was over it. **Not proven by construction for 1234**: it
is under the trigger on 2 of 3 runs. Remedy (2) (share the union-find with relationships) would take about half of the Council's pair walk in Council age; it was not built, per 11.1's order
and the instruction to build (2) only if (1) is not enough on the measured max. If a later run of seed 1234 exceeds 16.7 ms in Council age, (2) is next.

## C. Hash proof lines (remedy built, commit after "skip trust and sway in Landing")

```
seed 42: cn present, web present, age present | drop cn a96b8a9562fd75d0 expected a96b8a9562fd75d0 MATCH | drop cn and web da166c4f8b202820 expected da166c4f8b202820 MATCH | drop cn, web and age 02032b2388529913 expected 02032b2388529913 MATCH
seed 7: cn present, web present, age present | drop cn a4968e2fcc48ec36 expected a4968e2fcc48ec36 MATCH | drop cn and web 30c53f90949d979b expected 30c53f90949d979b MATCH | drop cn, web and age 830c7d0c441823f5 expected 830c7d0c441823f5 MATCH
seed 99: cn present, web present, age present | drop cn 2210719cf48d8612 expected 2210719cf48d8612 MATCH | drop cn and web 54ad1e15b934bf9a expected 54ad1e15b934bf9a MATCH | drop cn, web and age 0e3e83a7108140ef expected 0e3e83a7108140ef MATCH
seed 1234: cn present, web present, age present | drop cn 19437e397d1dff88 expected 19437e397d1dff88 MATCH | drop cn and web 7052c92936a75157 expected 7052c92936a75157 MATCH | drop cn, web and age bca6eb2ca93ba0c1 expected bca6eb2ca93ba0c1 MATCH
seed 2026: cn present, web present, age present | drop cn 6e7fe68477161196 expected 6e7fe68477161196 MATCH | drop cn and web 67e3dcf057200eb9 expected 67e3dcf057200eb9 MATCH | drop cn, web and age 2645033a417ec400 expected 2645033a417ec400 MATCH
```
