# Task 6a balance log (emotions): steps 3 and 6

Branch `claude/cool-gauss-g2uz86`, tree at 40e766f (dormant build: `data/mood.json` effects 0.0). Spec `docs/specs/emotions.md` section 10. Every number here was measured in this step with `tests/balance_run.gd` (`--seed N --sols 300`, one `--param` per run), raw outputs in `docs/balance/task-6a-data/` (`.gdignore`d). Every output header was read: the `overrides=[...]` field is empty for "before", `mood.effects.travel_coef=0.0001 mood.effects.energy_coef=0.0001` for the control, `mood.effects.travel_coef=0.15` for Run 1 and `mood.effects.travel_coef=0.075` for the halved Run 1. Each configuration was run twice per seed and the two outputs compared with `cmp`: all byte-identical (5 seeds x 4 configurations here, plus the 15-seed sets in the calibration doc). Nothing was tuned: no `sim/` file and no `data/` file changed; the shipped travel_coef stays 0.0.

## Result in one paragraph

Run 1 (travel_coef 0.15) fails and the halved run (0.075) fails again, so by the spec's decision rule `effects.travel_coef` **stays 0.0** and the result goes to the owner. Read this together with the finding below: the unmodified tree no longer matches the spec's "before" figures. Since the lifecycle and water rebaselines the colony does not grow at 300 sols (pop 7 to 13, first births at sol 277 to 293, no Council, Settlement entered on one seed at sol 291), and T10 fails on all five seeds with the gains at 0.0. The 300-sol horizon therefore does not exercise the systems the emotions targets were written for.

## Step 3: the "before" (fresh run of the unmodified tree, gains 0.0)

The Task 5 table in spec section 10 (pop 164 on seed 42, Settlement 67, Council 115, and so on) is **superseded**. It predates the calendar-lifecycle rebaseline (`lifecycle-rebaseline.md`) and the water-throughput rebaseline (`water-rebaseline.md`). The fresh measurement below is the "before". Cross-check: `tests/mood_hash_proof.gd` exits 0 on this tree (`task-6a-data/mood_hash_proof.txt`): with the `md` column dropped the five table hashes equal the water-rebaseline values (6ee99c98..., b65b7fe7..., 1497e052..., 6b2c0c36..., 838596b6...) and the Task 4, 3 and 1 chain matches. The hashes in the table below include `md` and so differ from those by design.

| seed | table sha256 (16, with md) | drop md (water rebaseline) | T1-T13 | pop@300 | births (first) | deaths | Settlement entry | fall-back | Council entry | pledge |
|---|---|---|---|---|---|---|---|---|---|---|
| 42 | 3aa7a38027265931 | 6ee99c980e75c9c5 | all pass except T10 | 12 | 5 (277) | 0 | 291 | none | none | none |
| 7 | e9b1ad0dd886c4f5 | b65b7fe750c0fc07 | all pass except T10 | 13 | 6 (284) | 0 | none | none | none | none |
| 99 | 065ca05f6a5c8f74 | 1497e05200e3f1b9 | T5 and T10 fail | 10 | 3 (293) | 0 | none | none | none | none |
| 1234 | 80cd788da43f63b5 | 6b2c0c366472539d | all pass except T10 | 13 | 6 (278) | 0 | none | none | none | none |
| 2026 | d62cf4f8df3ef98f | 838596b6725007bc | all pass except T10 | 7 | 0 (none) | 0 | none | none | none | none |

T10 fails on every seed (first Settlement sol must be 40 to 150; here 291 on seed 42 and none elsewhere). T5 on seed 99 fails on power (14 not-ok sols for power; see `before/s99_a.txt`). T9 is N/A in the table and is covered by the byte-identical reruns. T13 passes everywhere with 0 mood lines (nobody reaches the heavy band).

### The t27c digest

`tests/test_moods.gd::test_t27c_the_council_reads_the_same_world_through_the_accessor` pins the digest **7c7ab5ddcf2b4ba3**: SHA-256 (first 16 hex) of `JSON.stringify([trust, chosen, voices, trust_by_sol, chosen_by_sol, first_council_sol, sessions, pledge_sol, proposals.size(), lines, lines_dropped, [[id, lean_of, stance_of] per being]], "", true)` taken on seed 42 after 120 sols with the gains at 0.0. It was measured on the unmodified tree at ea93c57 (after the water rebaseline); the Task 5 digest f4375bd2df1ba9aa was superseded. At that point the Council has **not been entered** (`first_council_sol` is null), which is consistent with the table above (no Council entry on seed 42 at 300 sols either). The digest therefore pins an empty Council state plus the beings' ids, lean and stance; it proves the accessor reads the same world, not any Council behaviour.

## Step 6, Run 1: effects.travel_coef 0.0 -> 0.15 (energy_coef 0.0), five seeds, 300 sols, twice each

Judging rule used. The spec says keep the gain if T1 to T12 pass on all five seeds, and halve once on failure. Taken literally that cannot be met, because T10 fails on all five seeds at gains 0.0, and T5 fails on seed 99 (not something a travel gain can fix, spec "revision 3" on gain-independent targets). I therefore judged **new failures against the gains-0 row of the same seed**: a target that passes at gains 0.0 and fails with the gain on is a failure of the gain; a target that fails at gains 0.0 is reported and not counted. This is my reading, stated here so the owner can overrule it; under the literal reading the outcome is the same (halve, fail, hold at 0.0).

T1 to T13, five seeds, gains 0 against 0.15 against 0.075. Only targets whose verdict differs from the gains-0 row, plus the pre-existing failures, are named.

| seed | gains 0 | travel 0.15 | travel 0.075 |
|---|---|---|---|
| 42 | T10 | **T5 fails (new)**, T10 | **T11 fails (new)**, T10 |
| 7 | T10 | **T11 fails (new)**, T10 | T10 |
| 99 | T5, T10 | T10 (T5 passes) | T5, T10 |
| 1234 | T10 | T10 | **T11 fails (new)**, T10 |
| 2026 | T10 | T10 | **T11 fails (new)**, T10 |

Detail of the new failures (from the raw files). 0.15 seed 42, T5: demand>supply 1.41% of steps, max offline 104.3 h against 24.7 h allowed. 0.15 seed 7, T11: lonely mean of last 50 readings 0.360 against max 0.35. 0.075: T11 lonely last-50 mean 0.419 (42), 0.369 (1234), 0.382 (2026), all against 0.35.

Decision rule outcome: 0.15 fails (2 seeds), 0.075 fails (3 seeds), so by the rule the gain **stays 0.0** and the result goes to the owner. No M4 death-spiral signal appeared in either run (0 deaths on every seed and configuration, T13 passes on all runs, heavy share 0.000 because no being reaches the heavy band); the failures are T5 and T11.

Caveat that matters for the verdict. The T11 failures are not clearly caused by mood. The noise-floor control at gain 1e-4 (a negligible effect) also fails T11 on seeds 42 and 7 and on 9 of the 15 r9 seeds against 5 of 15 at gains 0 (calibration doc). T11 (lonely last-50 mean at most 0.35) is chaos-sensitive at a population of 7 to 13. The rule as written still halves and holds, and I applied it as written; I did not rerun hoping for a pass, and I did not run a third value.

Per-seed table (first run of each pair; second run byte-identical in every row; `md` is the last column of the balance table):

### Table A: five seeds, per configuration (a = first run; b byte-identical in every row)

| seed | config | table sha256 (16) | fails | pop@300 | births (first) | deaths (thirst) | Settlement entry | Council entry | pledge | lonely last-50 | friends_mean | md@300 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 42 | gains 0 (before) | 3aa7a38027265931 | T10 | 12 | 5 (277) | 0 (0) | 291 | <null> | <null> | 0.250 | 2.17 | +0.13 |
| 42 | control 1e-4 | 31ab4e59736ddc0f | T10,T11 | 12 | 5 (277) | 0 (0) | 291 | <null> | <null> | 0.479 | 1.67 | +0.11 |
| 42 | travel 0.15 | f3c5d41077e6609f | T5,T10 | 12 | 5 (282) | 0 (0) | <null> | <null> | <null> | 0.248 | 1.67 | +0.10 |
| 42 | travel 0.075 | 6a92e50eb0864a19 | T10,T11 | 12 | 5 (280) | 0 (0) | 291 | <null> | <null> | 0.419 | 3.17 | +0.14 |
| 7 | gains 0 (before) | e9b1ad0dd886c4f5 | T10 | 13 | 6 (284) | 0 (0) | <null> | <null> | <null> | 0.225 | 5.69 | +0.22 |
| 7 | control 1e-4 | 621e0d2a36164ea1 | T10,T11 | 13 | 6 (284) | 0 (0) | <null> | <null> | <null> | 0.401 | 3.85 | +0.17 |
| 7 | travel 0.15 | f97b6d19ced3f7c3 | T10,T11 | 10 | 3 (288) | 0 (0) | <null> | <null> | <null> | 0.360 | 1.20 | +0.11 |
| 7 | travel 0.075 | 7908ff69d22155ae | T10 | 9 | 2 (294) | 0 (0) | <null> | <null> | <null> | 0.000 | 2.44 | +0.14 |
| 99 | gains 0 (before) | 065ca05f6a5c8f74 | T5,T10 | 10 | 3 (293) | 0 (0) | <null> | <null> | <null> | 0.287 | 1.40 | +0.06 |
| 99 | control 1e-4 | e0c0e4b90e3413f0 | T5,T10 | 10 | 3 (293) | 0 (0) | <null> | <null> | <null> | 0.272 | 2.40 | +0.10 |
| 99 | travel 0.15 | 4e5cec094fe6ee8d | T10 | 10 | 3 (293) | 0 (0) | <null> | <null> | <null> | 0.278 | 1.60 | +0.05 |
| 99 | travel 0.075 | b6b74e0fc6b570d2 | T5,T10 | 11 | 4 (293) | 0 (0) | <null> | <null> | <null> | 0.276 | 2.36 | +0.13 |
| 1234 | gains 0 (before) | 80cd788da43f63b5 | T10 | 13 | 6 (278) | 0 (0) | <null> | <null> | <null> | 0.223 | 2.46 | +0.11 |
| 1234 | control 1e-4 | 405c59569c5482ef | T10 | 13 | 6 (278) | 0 (0) | 297 | <null> | <null> | 0.223 | 2.31 | +0.10 |
| 1234 | travel 0.15 | 197051435d64c82f | T10 | 12 | 5 (280) | 0 (0) | 292 | <null> | <null> | 0.336 | 2.17 | +0.15 |
| 1234 | travel 0.075 | 08f8d4792107314e | T10,T11 | 12 | 5 (280) | 0 (0) | 297 | <null> | <null> | 0.369 | 2.17 | +0.14 |
| 2026 | gains 0 (before) | d62cf4f8df3ef98f | T10 | 7 | 0 (<null>) | 0 (0) | <null> | <null> | <null> | 0.286 | 1.71 | +0.06 |
| 2026 | control 1e-4 | 30176cc798d36404 | T10 | 7 | 0 (<null>) | 0 (0) | <null> | <null> | <null> | 0.286 | 1.71 | +0.06 |
| 2026 | travel 0.15 | b2450a3cee275ac5 | T10 | 7 | 0 (<null>) | 0 (0) | <null> | <null> | <null> | 0.286 | 2.00 | +0.05 |
| 2026 | travel 0.075 | c0778e7465bb043f | T10,T11 | 11 | 4 (289) | 0 (0) | <null> | <null> | <null> | 0.382 | 1.45 | +0.10 |


## What was not done

- `tools/mood_probe.gd` does not exist in the tree (spec section 12 names it), so M1 to M4 (mood distribution, Deimos gap, trait correlation, spiral guard), M6 cost and probe items 1 to 12 were not measured. Only the balance-table targets T1 to T13 and the byte-identical reruns were.
- Run 2 (energy_coef) and the section 10 step 6 guards were not run; they depend on a kept travel gain.
- No mood.json value was changed; the working tree data is identical to HEAD.

## For the owner

1. The 300-sol horizon no longer exercises the colony the spec describes (pop 7 to 13, no Council, Settlement on one seed). Mood effects on Council entry, pledges and friend webs cannot be judged at 300 sols; the Standard horizon is 1,500 sols (water-rebaseline). Decision needed: change the calibration horizon for 6a, or accept a judgement on T-targets and the table only.
2. T10 fails on all five seeds on the unmodified tree, and T5 on seed 99; so the "T1 to T12 pass" rule cannot be satisfied as written. Decision needed: judge against the same-seed gains-0 row (as done here) or restate the rule.
3. T11 flips under pure noise (control at 1e-4), so it cannot separate mood from chaos at this size; a lower-variance judgement (more seeds, or a longer horizon) is needed before any travel gain can be accepted or rejected on T11.
4. travel_coef stays 0.0 under the rule; the slice currently ships dormant.
