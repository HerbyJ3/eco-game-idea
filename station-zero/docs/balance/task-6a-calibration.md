# Task 6a calibration: noise-floor control (spec section 10 step 3)

Tree 40e766f, dormant build. Control = both `mood.effects.travel_coef` and `mood.effects.energy_coef` at 1e-4 (`calibration.control_gain`), 300 sols, **one gain per seed set**. Overrides header on every file: `overrides=[mood.effects.travel_coef=0.0001 mood.effects.energy_coef=0.0001]` (checked). Raw output `docs/balance/task-6a-data/control5/`, `control15/`, `dormant15/` (the gains-0 runs of the ten extra seeds; the five standard seeds' gains-0 runs are in `before/`). Every run was done twice and the pair compared with `cmp`: all 20 control pairs (5 in `control5`, 15 in `control15`) and all 10 extra dormant pairs are byte-identical.

## Result

- **Five standard seeds at 1e-4: all five diverge** from the gains-0 table hash (the table includes `md`). No rerun at 1e-3 was needed for this set.
- **15 r9 seeds at 1e-4: all 15 diverge.** No rerun at 1e-3 was needed. `control_gain_next` was not used.
- Divergence is real but not always visible in the headline numbers: on seeds 99, 1234, 2026 the pop, births and Council figures are unchanged and only the table (md or other columns) differs.
- **Noise floor on T11.** The 1e-4 control fails T11 (lonely last-50 mean above 0.35) on 9 of 15 seeds against 5 of 15 at gains 0; the seed 1 gains-0 run goes extinct (pop 0, T1, T8, T10, T11 fail) while its control reaches pop 12. A 1e-4 gain is about 1,500 times smaller than the 0.15 candidate, so these shifts are chaos, not mood. Any T11 or lonely-share judgement of a real gain on these seeds must be read against this spread.
- Council entry: none on any of the 15 seeds in either configuration (and none at the gains-on runs on the five seeds), so the Council entry sol, pledge and `friend_pairs` shifts of spec item 10 cannot be measured at 300 sols. Only `lonely` (T11 last-50 mean) and `friends_mean` are available from the balance output; they are tabulated.

The M4 and M9 guards of spec section 12 need `tools/mood_probe.gd`, which does not exist yet; they were not computed here.

### Table B: 15 r9 seeds, gains 0 against control 1e-4

| seed | dormant sha | control sha | diverged | dormant fails | control fails | pop@300 d/c | lonely d/c | friends_mean d/c | T11 pass d/c |
|---|---|---|---|---|---|---|---|---|---|
| 42 | 3aa7a38027265931 | 31ab4e59736ddc0f | yes | T10 | T10,T11 | 12/12 | 0.250/0.479 | 2.17/1.67 | True/False |
| 7 | e9b1ad0dd886c4f5 | 621e0d2a36164ea1 | yes | T10 | T10,T11 | 13/13 | 0.225/0.401 | 5.69/3.85 | True/False |
| 99 | 065ca05f6a5c8f74 | e0c0e4b90e3413f0 | yes | T5,T10 | T5,T10 | 10/10 | 0.287/0.272 | 1.40/2.40 | True/True |
| 1234 | 80cd788da43f63b5 | 405c59569c5482ef | yes | T10 | T10 | 13/13 | 0.223/0.223 | 2.46/2.31 | True/True |
| 2026 | d62cf4f8df3ef98f | 30176cc798d36404 | yes | T10 | T10 | 7/7 | 0.286/0.286 | 1.71/1.71 | True/True |
| 1 | 5e946cc82134d03c | 0730079252f0e8da | yes | T1,T8,T10,T11 | T10,T11 | 0/12 | 0.000/0.408 | 0.00/2.17 | False/False |
| 2 | 4765a21d274cb637 | d76081caf4a9e474 | yes | T10 | T7,T10 | 12/12 | 0.203/0.051 | 2.50/5.00 | True/True |
| 3 | 10fe2ff001a45e0c | ac4f12b8bfa47330 | yes | T10 | T10 | 11/11 | 0.000/0.000 | 3.09/3.45 | True/True |
| 5 | 781e0cd0e7cd4bdc | 0632de61fbd427ac | yes | T10,T11 | T10,T11 | 11/11 | 0.714/0.571 | 1.82/2.55 | False/False |
| 8 | 1456adef3aa949b5 | eb3f78ce8e5f1d18 | yes | T5,T10,T11 | T5,T10,T11 | 13/13 | 0.476/0.668 | 2.15/2.46 | False/False |
| 13 | f9da56eca56f5223 | 5d6e64d9525b5fe5 | yes | T5,T10,T11 | T5,T10,T11 | 10/10 | 0.783/0.722 | 0.80/0.60 | False/False |
| 21 | 182e110e53db509f | 29758718cb17d121 | yes | T10,T11 | T10,T11 | 12/12 | 0.529/0.444 | 1.83/2.33 | False/False |
| 34 | 051e24a6350488ba | 71c7bd76618caf19 | yes | T5,T10 | T5,T10,T11 | 12/12 | 0.160/0.444 | 3.50/2.83 | True/False |
| 55 | e3fc067eca0ed7f5 | 5d2e0308fef2e889 | yes | T10 | T5,T10 | 9/9 | 0.090/0.297 | 1.56/1.33 | True/True |
| 89 | 7c021b6b06bb77a8 | f64b485d37c0b58e | yes | T10 | T10,T11 | 12/12 | 0.238/0.395 | 2.67/2.00 | True/False |

Means over 15 seeds: lonely (T11 last-50) dormant 0.298, control 0.377; pop@300 dormant 10.47, control 11.27. T11 failures: dormant 5, control 9 of 15.
