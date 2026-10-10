# Task 7 acceptance (influence powers, spec rev 2 section 5)

Date: 2026-10-09. Branch `claude/influence-powers-wip`, bed-walk fix baseline. **Verdict: FAIL** (U3, A1, A2, A3, P2 fail; U1, U2, P1, P3, G1 pass). Per spec section 5.6 / task-7-plan step 9, this is reported and stopped: no power number was changed and nothing was tuned.

## How it was run

- Runs (15, two at a time, seeds 42 7 99 1234 2026, 1,500 sols, `--every 10`), raw outputs in `docs/balance/task-7-acceptance-data/` (`UN_<seed>.txt`, `C1_<seed>.txt`, `C2_<seed>.txt`, `.gdignore`, `done.log`; no SCRIPT ERROR lines in any file):
  - UN: `godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols 1500 --every 10 --player watcher`
  - C1: `... --seed N --sols 1500 --every 10 --player attentive --cadence 1`
  - C2: `... --seed N --sols 1500 --every 10 --player attentive --cadence 2`
- `--player watcher` is a new observer-only player (`tools/watcher_player.gd`, extends the attentive player, never calls `use_power`). It exists because a plain unattended run does not print `first_low_sol`, which U2 needs. Neutrality was checked: UN-equivalent 300-sol runs with `--player watcher` (`U1_watcher_300_<seed>.txt`, default `--every 30`) reproduce all five pinned bed-fix hashes (42 a298dbb55b71d66e, 7 e540c1b86dabba26, 99 ffb6d5361bdb3a5d, 1234 bca08a0f327892fe, 2026 5fb3b699b4118a84): **U1 PASS**, which also covers G2 for the unused-power case.
- Every header was checked: `overrides=[]`, `data_hash=fcb5ff2f0fbf63a1` on all 15, player label as expected (watcher, attentive cadence=1.0, attentive cadence=2.0).
- Metrics are computed by `tools/acceptance_summary.py` (reusable: `python3 tools/acceptance_summary.py`), from the 150 sample rows and the `PLAYER` lines of each file. Windows for U3 are 50 sols between sample rows, starting at any sample with population >= 10.
- All runs exit 1 (known T8/T10/T11 table failures, as on the previous baseline); that is not the acceptance verdict.

## Criteria

| criterion | verdict | numbers |
|---|---|---|
| U1 powers unused: pinned hashes reproduce | PASS | 5 of 5 seeds match (watcher runs, 300 sols) |
| U2 warned early (`lead` >= 10, `low_sol` > 0) | PASS | `low_sol` 292 / 320 / 371 / 310 / 327; lead 41 / 21 / 246 / 253 / 137 (seeds 42 7 99 1234 2026) |
| U3 no 50-sol window loses > 35% (start pop >= 10) | FAIL | worst window: 42: 100%, 7: 31%, 99: 100%, 1234: 43%, 2026: 67% |
| U4 report: alive at 1,500 and final pop (unattended) | report | alive on 1234 (10) and 2026 (8); dead on 42, 7, 99. Not pass/fail |
| A1 C1 >= UN on every seed, > on >= 4; first thirst later or never on >= 4 | FAIL | pop_sols C1 >= UN on only 1 of 5 seeds (seed 42, 888 vs 274); first thirst later or never on 4 of 5 (seed 7 earlier, 340 vs 341) |
| A2 C1 >= C2 >= UN on >= 4 seeds, sums strictly ordered | FAIL | ordered on 1 of 5; sums C1 4642, C2 3934, UN 5417 (UN is highest) |
| A3 C1 alive at 1,500 on >= 3 seeds | FAIL | 0 of 5 |
| P1 C1 mean ice < 1.0 on >= 2 seeds and a `low` episode on >= 3 | PASS | mean ice/target < 1.0 on 5 of 5 (0.31 to 0.59); low episode on 5 of 5 |
| P2 C1 in `low` for <= 30% of samples on >= 4 seeds | FAIL | 1 of 5 (low share 0.622 / 0.139 / 0.315 / 0.392 / 0.654) |
| P3 mean uses per 100 sols: Guide <= 16, Fortune <= 12 | PASS | C1: Guide 10.0, Fortune 0.1; C2: Guide 5.8, Fortune 0.1 |
| P4 report: guide trips / ice trips in the guided window | report | C1: 0.609 / 0.833 / 0.500 / 0.697 / 0.690 (target 0.3 to 0.7; seed 7 above) |
| G1 no air or EVA deaths; air turn-backs <= UN | PASS | 0 air deaths, 0 EVA deaths, 0 air turn-backs in all 15 runs |
| G3 report: sols from first low to first thirst death (`lead`) | report | see per-seed table |

Honest reading of A1: C1 is not better than UN. C1 beats UN's pop_sols on seed 42 only (888 vs 274), roughly equal on 2026 (1,589 vs 1,608), and worse on 7, 99 and 1234 (276 vs 366, 836 vs 1,457, 1,053 vs 1,712). First thirst is later with C1 on seeds 42 (422 vs 333), 99 (719 vs 617), 1234 (583 vs 563) and 2026 (753 vs 464) and earlier on seed 7 (340 vs 341), which gives 4 of 5 for that half of A1 (the pop_sols half is the failure). The fact that C1 delays first thirst but ends with fewer colonist-sols on 99 and 1234 means Guide postpones the first thirst death but does not stop the decline, and in these runs the guided colonies end up extinct while the unguided 1234 colony is still alive (10) at 1,500.

## Per-seed numbers (from `tools/acceptance_summary.py`)

| run | seed | pop_sols | alive@1500 | final pop (last sol) | peak | low_sol | first thirst | lead | worst 50-sol loss | sols thirst->half peak | EVA deaths | air deaths | air turn-backs | mean ice/target | low share |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| UN | 42 | 274 | no | 0 (1500) | 12 | 292 | 333 | 41 | 100% | 17 | 0 | 0 | 0 | 0.515 | 0.167 |
| UN | 7 | 366 | no | 0 (1500) | 13 | 320 | 341 | 21 | 31% | 109 | 0 | 0 | 0 | 0.626 | 0.109 |
| UN | 99 | 1457 | no | 0 (1500) | 20 | 371 | 617 | 246 | 100% | 523 | 0 | 0 | 0 | 0.433 | 0.640 |
| UN | 1234 | 1712 | yes | 10 (1500) | 19 | 310 | 563 | 253 | 43% | 667 | 0 | 0 | 0 | 0.332 | 0.775 |
| UN | 2026 | 1608 | yes | 8 (1500) | 18 | 327 | 464 | 137 | 67% | 356 | 0 | 0 | 0 | 0.382 | 0.550 |
| C1 | 42 | 888 | no | 0 (1500) | 13 | 292 | 422 | 130 | 100% | 558 | 0 | 0 | 0 | 0.314 | 0.622 |
| C1 | 7 | 276 | no | 0 (1500) | 13 | 302 | 340 | 38 | 100% | 10 | 0 | 0 | 0 | 0.588 | 0.139 |
| C1 | 99 | 836 | no | 0 (1500) | 19 | 371 | 719 | 348 | 100% | 11 | 0 | 0 | 0 | 0.582 | 0.315 |
| C1 | 1234 | 1053 | no | 0 (1500) | 18 | 310 | 583 | 273 | 88% | 337 | 0 | 0 | 0 | 0.458 | 0.392 |
| C1 | 2026 | 1589 | no | 0 (1500) | 19 | 338 | 753 | 415 | 100% | 347 | 0 | 0 | 0 | 0.367 | 0.654 |
| C2 | 42 | 318 | no | 0 (1500) | 12 | 292 | 382 | 90 | 100% | 8 | 0 | 0 | 0 | 0.495 | 0.231 |
| C2 | 7 | 341 | no | 0 (1500) | 13 | 320 | 338 | 18 | 38% | 102 | 0 | 0 | 0 | 0.605 | 0.205 |
| C2 | 99 | 1574 | no | 0 (1500) | 21 | 371 | 732 | 361 | 52% | 148 | 0 | 0 | 0 | 0.383 | 0.701 |
| C2 | 1234 | 1110 | no | 0 (1500) | 19 | 310 | 677 | 367 | 89% | 13 | 0 | 0 | 0 | 0.404 | 0.250 |
| C2 | 2026 | 591 | no | 0 (1500) | 15 | 337 | 579 | 242 | 77% | 11 | 0 | 0 | 0 | 0.524 | 0.328 |

### Power use
| run | seed | checks | guide uses | fortune uses | guide /100 sols | fortune /100 sols | guide uses while low/dry | guide_trips / ice_trips_in_guided_window | guide_trips / ice_trips_total |
|---|---|---|---|---|---|---|---|---|---|
| C1 | 42 | 975 | 210 | 0 | 14.0 | 0.0 | 210 | 0.609 | 0.189 |
| C1 | 7 | 353 | 17 | 2 | 1.1 | 0.1 | 17 | 0.833 | 0.043 |
| C1 | 99 | 729 | 83 | 0 | 5.5 | 0.0 | 83 | 0.500 | 0.087 |
| C1 | 1234 | 1192 | 161 | 2 | 10.7 | 0.1 | 161 | 0.697 | 0.129 |
| C1 | 2026 | 1268 | 278 | 5 | 18.5 | 0.3 | 278 | 0.690 | 0.184 |
| C2 | 42 | 194 | 24 | 0 | 1.6 | 0.0 | 24 | 0.636 | 0.050 |
| C2 | 7 | 217 | 25 | 2 | 1.7 | 0.1 | 25 | 0.556 | 0.033 |
| C2 | 99 | 667 | 234 | 0 | 15.6 | 0.0 | 234 | 0.496 | 0.091 |
| C2 | 1234 | 737 | 93 | 1 | 6.2 | 0.1 | 93 | 0.677 | 0.083 |
| C2 | 2026 | 320 | 55 | 4 | 3.7 | 0.3 | 55 | 0.741 | 0.076 |

Run headers (all 15): `overrides=[]`, `data_hash=fcb5ff2f0fbf63a1`, 150 sample rows, 0 SCRIPT ERROR lines.

## Notes and caveats

- Use rates in the table divide by 1,500 sols, including sols after extinction, when the player no longer acts (checks stop at population 0). Per living sol the rates are higher. C1 seed 2026 (18.5 Guide uses per 100 sols over the whole run, 278 uses) and C2 seed 99 (15.6) are near or above the 16 per 100 bar for that seed; the mean passes P3 mainly because several colonies died early.
- Fortune was almost never needed (0 to 5 uses per run), so it is not what separates the runs.
- Guide has not saved any colony in these runs. Mean ice/target under C1 (0.31 to 0.59) is not consistently better than unattended (0.33 to 0.63), and Guide uses are heavy on seeds 42 (210) and 2026 (278) with little effect.
- U3 fails mostly on small colonies (peak 12 to 20); a 100% loss means a colony of 10 or more went extinct inside 50 sols (seeds 42 and 99 unattended). It is measured at 10-sol sample granularity.
- Spec rule applied: the acceptance failed, so nothing was tuned. The suspects named in section 5.6 (`guide.duration_sols` 1 to 1.5, then `guide.chance` 0.7 to 0.8, then `recharge_sols.guide` 3 to 2) are for the game-designer to choose from, one number per run. U3 failing unattended is, per section 5.1, an owner decision (a water-pressure rule would be a separate spec), not a powers retune.
