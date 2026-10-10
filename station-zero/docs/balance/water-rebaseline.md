# Water-throughput re-baseline

Owner decision (Herby, 2026-10-09): ship switch W3 from `docs/specs/water-throughput.md` as the new default (`data/resources.json` → `throughput.commute_pause` = `false`). A colonist walking room to room toward a mining launch building, while carrying a mine plan, no longer stops for a full room pause on each arrival; it continues after one fixed step, as sleepers already do. W1, W2, W4 and W5 ship off.

This changes behaviour, so the pinned table hashes are reset. The old calendar-lifecycle values stay as history comments in the proof scripts.

## Run-twice evidence

Command: `godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols 300`, run twice per seed. Both outputs are byte-identical on all five seeds (`water-rebaseline-data/run_seed_N.txt`, `rerun_seed_N.txt`). The runs exit 1 because T10 (Settlement by sol 150) fails, as on the previous baseline. The drop-column hashes come from `tests/council_hash_proof.gd` (`hash_proof_council_a.txt`, `_b.txt`).

| seed | full table (Task 5 level) | drop `cn` (Task 4) | drop `cn`, `web` (Task 3) | drop `cn`, `web`, `age` (Task 1) |
|---|---|---|---|---|
| 42 | 6ee99c980e75c9c5 | 6007d885aa1974ac | 3a781ace17210e77 | 1adcc68e00da901b |
| 7 | b65b7fe750c0fc07 | cadbd65b8bffdb9c | d19831ca3d3a9282 | 8cc2e6aa756fc04c |
| 99 | 1497e05200e3f1b9 | 40d46838bb39aee5 | 80407b975e346c1e | 58115f266ae42627 |
| 1234 | 6b2c0c366472539d | 55c479815f1f47ac | 0cc6764008aed14f | 6f86c2e2daee62c0 |
| 2026 | 838596b6725007bc | 27b48573b9aed8e2 | 11ff36bd5fe69349 | 2ffb039806dce940 |

Updated constants: `tests/mood_hash_proof.gd` (`EXPECTED_T5`), `tests/council_hash_proof.gd` (`EXPECTED_T4`), `tests/relationships_hash_proof.gd` (`EXPECTED_T3`), `tests/age_hash_proof.gd` (`EXPECTED`).

## Effect at the Standard horizon (1,500 sols, from the E3 run in `water-throughput-data/`)

| seed | first thirst death, before → after | alive at 1,500 |
|---|---|---|
| 42 | 380 → 600 | no |
| 7 | 300 → 580 | no |
| 99 | 350 → 600 | yes (18) |
| 1234 | 530 → 850 | yes (24) |
| 2026 | 400 → 700 | no |

Unattended decline is now gradual, which matches the owner's direction that the player's influence should be what keeps the colony alive. Power guard T5 fails on seed 99 at this horizon (one building dark 350 h), the same reserve-margin issue already recorded for seed 2026.
