# Task 7c re-baseline (thirst_mode "per_being" as the data default)

Commit 24ba3b3 flipped `data/colony.json` `death.thirst_mode` to `"per_being"` (`thirst_roll_h` 6, `thirst_being_chance` 0.002). Result: **no pinned 300-sol hash changes.** In every 300-sol run ice stays above 0, so no thirst roll happens and the RNG draw order is unchanged. Every run has 0 deaths (T2 PASS). The pins stay as they are; each proof script carries a "pre-7c (colony thirst)" comment saying the values are identical.

Only `data_hash` changes: default header `overrides=[]`, `data_hash=e1d5e1add9f157c4` (was `fcb5ff2f0fbf63a1` at the bed-walk baseline).

## Run-twice evidence
`balance_run.gd -- --seed N --sols 300`, twice per seed, byte-identical on all five seeds, no SCRIPT ERROR (`task-7c-data/rebase_a_seed_N.txt`, `rebase_b_seed_N.txt`). `mood_hash_proof.gd` run per seed (`rebase_proof_a_N.txt`): MATCH on all four levels.

| seed | full table (mood, EXPECTED_T5) old → new | drop `cn` (T4) | drop `cn`,`web` (T3) | drop `cn`,`web`,`age` (T1) |
|---|---|---|---|---|
| 42 | a298dbb55b71d66e → same | 54e0b17c2b95a97e → same | 03c17dd97277fc8f → same | 86bcffaefbd102f4 → same |
| 7 | e540c1b86dabba26 → same | 58c9704fa00c26fc → same | fda95dbc1385fd85 → same | 6f987c9875a7af2d → same |
| 99 | ffb6d5361bdb3a5d → same | 5d007db82e1a61bf → same | 4b8dd16b6c183a2e → same | bb3ae2236d650e4f → same |
| 1234 | bca08a0f327892fe → same | 88802cc94428993e → same | 7b60e6bb79e2e0e0 → same | eb4ebd1c13282752 → same |
| 2026 | 5fb3b699b4118a84 → same | 4e6b1638a49280fe → same | 35cbd40fb54f2114 → same | 14c71f23478a7b4c → same |

## Test changes
`tests/test_colony.gd`: `test_death_timer_fires_on_step_100_thirst`, `test_deaths_only_on_check_steps` and `test_cause_priority_thirst_over_hunger` set `thirst_mode = "colony"` (helper `_set_thirst_mode`, restored at the end); assertions unchanged.
