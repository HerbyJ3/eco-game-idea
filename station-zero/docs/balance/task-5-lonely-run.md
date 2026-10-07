# Task 5 step 3: the lonely-pull-alone run

Facts only. Spec: `docs/specs/council.md` section 10 (revision 3) and the owner ruling of 2026-10-07 (clause 2 counts only eligible seeds: two thirds of the eligible seeds better, at least 6 eligible). Plan: `docs/tasks/task-5-plan.md` step 3. Baselines: `docs/balance/task-4-log.md`, `docs/balance/task-4-calibration.md`.

## What was run
- One parameter changed: `relationships.effects.lonely_pull` 0.0 to 0.15, through the probe override only (`--pull lonely`, which sets `balance.probe_lonely_pull` 0.15 in the SimData cache for the process). `effects.friend_pull` stayed 0.0. `data/relationships.json` is not changed: shipped `lonely_pull` 0.0, `friend_pull` 0.0.
- 15 seeds: 42, 7, 99, 1234, 2026 and 1, 2, 3, 5, 8, 13, 21, 34, 55, 89 (`relationships.balance.r9_seeds`), 300 sols each, shipped and candidate: 30 probe runs (`tools/relationships_probe.gd`), outputs in `docs/balance/task-5-lonely-run-data/` (`seed_N_<shipped|lonely>.txt|json|csv`).
- The five standard seeds also through `tests/balance_run.gd` (T1 to T11), shipped once, candidate twice (`task-5-lonely-run-data/balance/seed_N_ship|pull|pull2.txt`).
- Tables below are produced by `python3 tools/lonely_tables.py docs/balance/task-5-lonely-run-data docs/balance/task-5-lonely-run-data/balance`.
- New probe code (read only, hash-neutral: the shipped probe digests equal the Task 4 digests, 42: 4df486651b1ff854, 7: 6aa1d8b5a65ebd23): `--pull lonely`; the repeat-company measure and breadth report (same groups as the sim: rooms, site crew, field crews; late newborn = born after sol 100 and present on each of its first 20 sols; per day the most ticks, at 1 h a tick, shared with one other being; median of the 20 days; seed value = median over newborns); zero-friend share per seed; voice readings (voices, trust, chosen share) once a sol with the 5.1 and 5.2 formulas and the gate clauses 5.3 evaluated per sol with the spec's estimates as constants; F4-1 (longest silent run before the first newcomer line), the R13 2.5 warning, the log-share 0.15 flag and the R12 reopen reads.
- Not built here (sim or data changes, outside this task's files): `stats.relationships.lines_dropped_by_type` (R14 and T11 (5) still read the total `lines_dropped`, which was 0 on every run in the probe table), and the `balance.r9_*`, `balance.repeat_*` data keys (the thresholds are constants in `tools/lonely_tables.py`: gain 0.03, two thirds, 6 eligible, 0.5 h, 10 seeds).
- Definitions used: zero-friend share = late newborns (born after sol 100, alive at sol 300) with `friend_count` 0, kin included (the K1 definition), over all late newborns alive at sol 300. A seed with no late newborn has no share. Clause 1 mean is over the seeds with a share on both runs.
- Shipped state: the full test suite (`tests/run_tests.gd`) on the committed data: 493 tests, 41331 checks, 0 failures. The five shipped balance table hashes equal those in `docs/balance/task-4-log-data/balance_seed_*.txt`.

## Verdict (facts, per the rule)
**Do not adopt.** Clauses 1, 2, 4 and 5 fail as written; clause 3 and 6 pass. The rule says all must hold.

### Zero-friend late newborns per seed (clause 1 and 2)
| seed | late newborns shipped | zero shipped | share shipped | late newborns pull | zero pull | share pull | change | eligible | better |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 42 | 111 | 38 | 0.342 | 77 | 22 | 0.286 | -0.057 | yes | yes |
| 7 | 40 | 1 | 0.025 | 131 | 35 | 0.267 | +0.242 | yes | no |
| 99 | 95 | 23 | 0.242 | 126 | 38 | 0.302 | +0.059 | yes | no |
| 1234 | 75 | 11 | 0.147 | 95 | 14 | 0.147 | +0.001 | yes | no |
| 2026 | 109 | 36 | 0.330 | 97 | 30 | 0.309 | -0.021 | yes | yes |
| 1 | 106 | 37 | 0.349 | 84 | 26 | 0.310 | -0.040 | yes | yes |
| 2 | 104 | 35 | 0.337 | 116 | 27 | 0.233 | -0.104 | yes | yes |
| 3 | 111 | 37 | 0.333 | 95 | 50 | 0.526 | +0.193 | yes | no |
| 5 | 85 | 11 | 0.129 | 100 | 25 | 0.250 | +0.121 | yes | no |
| 8 | 123 | 22 | 0.179 | 112 | 33 | 0.295 | +0.116 | yes | no |
| 13 | 115 | 43 | 0.374 | 105 | 22 | 0.210 | -0.164 | yes | yes |
| 21 | 113 | 27 | 0.239 | 0 | 0 | - | - | yes | no |
| 34 | 70 | 11 | 0.157 | 80 | 19 | 0.237 | +0.080 | yes | no |
| 55 | 127 | 25 | 0.197 | 95 | 35 | 0.368 | +0.172 | yes | no |
| 89 | 111 | 30 | 0.270 | 102 | 32 | 0.314 | +0.043 | yes | no |

### Repeat-company measure and breadth (clause 3 and the breadth report)
Per seed: median over late newborns (born after sol 100, lived their first 20 sols) of the median daily maximum hours shared with one being.
| seed | newborns shipped | repeat h shipped | newborns pull | repeat h pull | change | distinct beings met (median) ship / pull | share of group hours to the top being ship / pull | group hours a sol ship / pull |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | 
| 42 | 111 | 12.50 | 72 | 12.00 | -0.50 | 107.0 / 85.0 | 0.036 / 0.042 | 105.7 / 86.8 |
| 7 | 20 | 13.50 | 125 | 12.00 | -1.50 | 35.5 / 95.0 | 0.083 / 0.043 | 67.8 / 90.6 |
| 99 | 97 | 12.00 | 119 | 12.00 | +0.00 | 108.0 / 100.0 | 0.038 / 0.044 | 91.8 / 88.5 |
| 1234 | 75 | 12.50 | 75 | 12.50 | +0.00 | 99.0 / 83.0 | 0.039 / 0.046 | 97.7 / 92.8 |
| 2026 | 100 | 12.00 | 98 | 11.50 | -0.50 | 85.5 / 83.5 | 0.049 / 0.050 | 80.3 / 71.3 |
| 1 | 95 | 12.00 | 75 | 11.00 | -1.00 | 72.0 / 72.0 | 0.048 / 0.053 | 81.2 / 70.9 |
| 2 | 103 | 12.00 | 107 | 12.50 | +0.50 | 109.0 / 110.0 | 0.038 / 0.034 | 100.2 / 115.7 |
| 3 | 103 | 11.50 | 98 | 12.00 | +0.50 | 77.0 / 80.5 | 0.053 / 0.049 | 69.7 / 78.6 |
| 5 | 80 | 12.50 | 85 | 12.00 | -0.50 | 61.5 / 63.0 | 0.058 / 0.057 | 65.4 / 72.8 |
| 8 | 113 | 12.00 | 95 | 12.00 | +0.00 | 100.0 / 92.0 | 0.038 / 0.040 | 103.0 / 93.0 |
| 13 | 105 | 11.50 | 102 | 12.00 | +0.50 | 79.0 / 80.0 | 0.049 / 0.046 | 74.3 / 86.7 |
| 21 | 114 | 12.50 | 67 | 11.00 | -1.50 | 106.0 / 98.0 | 0.036 / 0.036 | 104.5 / 113.8 |
| 34 | 60 | 12.00 | 75 | 12.50 | +0.50 | 91.5 / 93.0 | 0.041 / 0.040 | 93.5 / 96.7 |
| 55 | 112 | 12.00 | 92 | 11.75 | -0.25 | 95.5 / 85.0 | 0.043 / 0.047 | 93.5 / 73.8 |
| 89 | 101 | 12.00 | 98 | 12.00 | +0.00 | 98.0 / 100.0 | 0.048 / 0.042 | 82.5 / 88.1 |

### R4, R10, R11 on the pull runs (clause 4), with the shipped runs beside
| seed | R4 friends_mean pull (ship) | R10 ratio / coldest third pull | R4 | R10 | R11 | R4 R10 R11 shipped |
| --- | --- | --- | --- | --- | --- | --- |
| 42 | 1.36 (2.01) | 2.83 = warm 2.05 / cold 0.72 | pass | pass | pass | pass pass pass |
| 7 | 1.60 (12.67) | 2.74 = warm 2.35 / cold 0.85 | pass | pass | pass | pass pass pass |
| 99 | 1.16 (1.78) | 2.08 = warm 1.67 / cold 0.80 | pass | pass | pass | pass pass pass |
| 1234 | 3.36 (7.56) | 5.62 = warm 6.27 / cold 1.12 | pass | pass | pass | pass pass pass |
| 2026 | 1.06 (1.28) | 3.08 = warm 1.57 / cold 0.51 | pass | pass | pass | pass pass pass |
| 1 | 1.31 (0.99) | 3.48 = warm 2.17 / cold 0.62 | pass | pass | pass | FAIL pass pass |
| 2 | 1.60 (1.69) | 4.85 = warm 2.75 / cold 0.57 | pass | pass | pass | pass pass pass |
| 3 | 0.80 (1.47) | 2.70 = warm 1.23 / cold 0.45 | FAIL | pass | pass | pass pass pass |
| 5 | 2.64 (3.53) | 6.90 = warm 5.00 / cold 0.72 | pass | pass | pass | pass pass pass |
| 8 | 1.52 (2.88) | 2.71 = warm 2.41 / cold 0.89 | pass | pass | pass | pass pass pass |
| 13 | 2.44 (1.37) | 2.66 = warm 3.51 / cold 1.32 | pass | pass | pass | pass pass pass |
| 21 | 0.00 (1.45) | 1.00 = warm -1.00 / cold -1.00 | FAIL | FAIL | pass | pass pass pass |
| 34 | 1.90 (3.51) | 5.45 = warm 3.76 / cold 0.69 | pass | pass | pass | pass pass pass |
| 55 | 1.34 (1.94) | 3.77 = warm 2.18 / cold 0.58 | pass | pass | pass | pass pass pass |
| 89 | 1.63 (1.44) | 4.26 = warm 2.69 / cold 0.63 | pass | pass | pass | pass pass pass |

### Deaths (clause 6)
| seed | deaths shipped a/t/h/e/o | deaths pull a/t/h/e/o | unexplained pull | new cause under pull |
| --- | --- | --- | --- | --- |
| 42 | 0/10/0/0/0 | 0/16/0/0/0 | 0 | none  |
| 7 | 0/0/0/0/0 | 0/8/0/0/0 | 0 | thirst  |
| 99 | 0/22/0/0/0 | 0/13/0/0/0 | 0 | none  |
| 1234 | 0/0/0/0/0 | 0/0/0/0/0 | 0 | none  |
| 2026 | 0/5/0/0/0 | 0/8/0/0/0 | 0 | none  |
| 1 | 0/7/0/0/0 | 0/1/0/0/0 | 0 | none  |
| 2 | 0/16/0/0/0 | 0/6/0/0/0 | 0 | none  |
| 3 | 0/1/0/0/0 | 0/14/0/0/0 | 0 | none  |
| 5 | 0/0/0/0/0 | 0/0/0/0/0 | 0 | none  |
| 8 | 0/6/0/0/0 | 0/4/0/0/0 | 0 | none  |
| 13 | 0/0/0/0/0 | 0/5/0/0/0 | 0 | thirst  |
| 21 | 0/28/0/0/0 | 0/135/0/0/0 | 0 | none colony extinct at sol 300 (pop_end 0) |
| 34 | 0/0/0/0/0 | 0/0/0/0/0 | 0 | none  |
| 55 | 0/4/0/0/0 | 0/8/0/0/0 | 0 | none  |
| 89 | 0/8/0/0/0 | 0/6/0/0/0 | 0 | none  |

Cause types seen on the 15 shipped runs: ['thirst']. Under the pull: ['thirst']. New cause type: none. Seeds where a cause appears that the same seed did not have shipped: [7, 13] (read per seed, this is stricter than the cause-type reading used for the verdict).
Colonies extinct at sol 300: shipped none, pull [21].

### Task 3 ages on the standard seeds (clause 5, reported, not judged against the old sols)
| seed | settlement sol shipped | settlement sol pull | old (Task 3) | fall-backs shipped | fall-backs pull | age history pull |
| --- | --- | --- | --- | --- | --- | --- |
| 42 | 67 | 67 | 67 | 213 (ice) | 207 (ice) | 0 landing; 67 settled; 207 fell_back |
| 7 | 58 | 58 | 58 | none | none | 0 landing; 58 settled |
| 99 | 54 | 54 | 54 | 174 (ice) | 222 (power) | 0 landing; 54 settled; 222 fell_back |
| 1234 | 65 | 68 | 65 | none | none | 0 landing; 68 settled |
| 2026 | 53 | 53 | 53 | none | 220 (ice) | 0 landing; 53 settled; 220 fell_back |

### Council gate readings (reported; section 10 'must not make the gate a timer')
Recomputed by the probe with the 5.1 to 5.3 formulas and estimates (voices 40 sols, family 2 generations, 0.5 / 0.5, 16 of 20, 30 settled sols, 12 voices).
| seed | run | earliest sol all clauses | voices / trust / chosen there | first sol open without the chosen clause | chosen clause binds | sols the chosen clause alone blocked | min trust from sol 60 | min chosen from sol 60 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 42 | shipped | 115 | 43 / 0.67 / 0.51 | 97 | yes | 15 | 0.346 | 0.000 |
| 42 | pull | never | - | never | no | 0 | 0.089 | 0.000 |
| 7 | shipped | 95 | 22 / 0.86 / 0.73 | 88 | yes | 7 | 0.643 | 0.000 |
| 7 | pull | 95 | 22 / 0.77 / 0.68 | 88 | yes | 23 | 0.054 | 0.000 |
| 99 | shipped | never | - | never | no | 0 | 0.077 | 0.000 |
| 99 | pull | 158 | 72 / 0.56 / 0.64 | 158 | no | 3 | 0.145 | 0.000 |
| 1234 | shipped | 160 | 82 / 0.55 / 0.55 | 160 | no | 0 | 0.324 | 0.000 |
| 1234 | pull | 160 | 77 / 0.68 / 0.69 | 160 | no | 0 | 0.098 | 0.000 |
| 2026 | shipped | 206 | 96 / 0.51 / 0.57 | 206 | no | 0 | 0.190 | 0.000 |
| 2026 | pull | never | - | never | no | 0 | 0.102 | 0.000 |
| 1 | shipped | 171 | 57 / 0.51 / 0.53 | 83 | yes | 21 | 0.120 | 0.000 |
| 1 | pull | never | - | 83 | yes | 29 | 0.080 | 0.000 |
| 2 | shipped | never | - | never | no | 0 | 0.135 | 0.000 |
| 2 | pull | 200 | 102 / 0.57 / 0.54 | 197 | yes | 5 | 0.190 | 0.000 |
| 3 | shipped | never | - | never | no | 0 | 0.153 | 0.000 |
| 3 | pull | 151 | 47 / 0.57 / 0.57 | 151 | no | 0 | 0.189 | 0.000 |
| 5 | shipped | 136 | 22 / 0.59 / 0.59 | 105 | yes | 35 | 0.333 | 0.000 |
| 5 | pull | 119 | 17 / 0.53 / 0.53 | 105 | yes | 20 | 0.472 | 0.000 |
| 8 | shipped | 163 | 77 / 0.56 / 0.60 | 163 | no | 0 | 0.360 | 0.000 |
| 8 | pull | never | - | 127 | yes | 14 | 0.227 | 0.000 |
| 13 | shipped | 145 | 37 / 0.65 / 0.59 | 145 | no | 0 | 0.098 | 0.000 |
| 13 | pull | 145 | 37 / 0.59 / 0.62 | 145 | no | 4 | 0.308 | 0.000 |
| 21 | shipped | never | - | never | no | 0 | 0.213 | 0.238 |
| 21 | pull | 182 | 92 / 0.57 / 0.52 | 182 | no | 1 | 0.000 | 0.000 |
| 34 | shipped | 164 | 72 / 0.69 / 0.71 | 75 | yes | 16 | 0.327 | 0.000 |
| 34 | pull | 150 | 62 / 0.76 / 0.79 | 75 | yes | 24 | 0.192 | 0.000 |
| 55 | shipped | 122 | 35 / 0.71 / 0.66 | 117 | yes | 5 | 0.273 | 0.000 |
| 55 | pull | never | - | never | no | 0 | 0.083 | 0.000 |
| 89 | shipped | never | - | never | no | 0 | 0.211 | 0.000 |
| 89 | pull | never | - | never | no | 0 | 0.167 | 0.000 |

### K1 to K3 and the F4 reads
| seed | K1 zero-friend share ship / pull | K2 first newcomer line ship / pull | K3 R1 median wait ship / pull (max 30) | F4-1 longest silent run before first newcomer line ship / pull | R13 tail per 5 sols ship / pull (warn 2.5) | log share ship / pull (flag 0.15) |
| --- | --- | --- | --- | --- | --- | --- | 
| 42 | 0.342 / 0.286 | 45 / 45 | 28.0 / 35.0 | 21 / 21 | 1.80 / 1.40 | 0.096 / 0.068 |
| 7 | 0.025 / 0.267 | 34 / 34 | 25.0 / 24.5 | 16 / 16 | 0.33 / 2.83 | 0.130 / 0.127 |
| 99 | 0.242 / 0.302 | 68 / 68 | 29.0 / 33.0 | 35 / 35 | 2.37 / 2.40 | 0.103 / 0.125 |
| 1234 | 0.147 / 0.147 | 41 / 41 | 26.0 / 27.5 | 21 / 21 | 2.30 / 1.33 | 0.122 / 0.113 |
| 2026 | 0.330 / 0.309 | 54 / 54 | 29.0 / 33.0 | 18 / 18 | 2.10 / 2.20 | 0.108 / 0.098 |
| 1 | 0.349 / 0.310 | 57 / 57 | 27.0 / 29.0 | 16 / 16 | 1.53 / 1.33 | 0.099 / 0.080 |
| 2 | 0.337 / 0.233 | 43 / 43 | 26.0 / 27.0 | 22 / 22 | 2.53 / 2.57 | 0.109 / 0.106 |
| 3 | 0.333 / 0.526 | 64 / 64 | 33.0 / 26.0 | 21 / 21 | 2.07 / 2.23 | 0.100 / 0.119 |
| 5 | 0.129 / 0.250 | 71 / 71 | 22.0 / 23.5 | 33 / 33 | 1.87 / 1.57 | 0.152 / 0.126 |
| 8 | 0.179 / 0.295 | 53 / 53 | 25.0 / 29.0 | 18 / 18 | 2.63 / 2.13 | 0.122 / 0.097 |
| 13 | 0.374 / 0.210 | 69 / 69 | 30.0 / 25.0 | 23 / 23 | 2.00 / 2.10 | 0.113 / 0.120 |
| 21 | 0.239 / - | 20 / 20 | 25.5 / 33.0 | 19 / 19 | 2.47 / 1.00 | 0.121 / 0.111 |
| 34 | 0.157 / 0.237 | 32 / 32 | 26.0 / 21.0 | 24 / 24 | 1.20 / 1.37 | 0.122 / 0.115 |
| 55 | 0.197 / 0.368 | 47 / 47 | 24.0 / 28.0 | 30 / 30 | 2.70 / 1.90 | 0.127 / 0.096 |
| 89 | 0.270 / 0.314 | 40 / 40 | 28.5 / 32.0 | 23 / 23 | 2.30 / 2.13 | 0.117 / 0.113 |

### Adoption clauses, as written
| clause | measured | verdict |
| --- | --- | --- |
| 1. R9 mean: pull mean <= shipped mean - 0.03 | shipped mean 0.244, pull mean 0.290 over 14 seeds with late newborns on both runs; difference +0.046 | FAIL |
| 2. better on at least two thirds of eligible seeds, at least 6 eligible | eligible 15 (42,7,99,1234,2026,1,2,3,5,8,13,21,34,55,89), better 5 (42,2026,1,2,13), needed 10; SE of the paired difference over 14 seeds 0.031 | FAIL |
| 3. repeat-company mean: pull <= shipped + 0.5 h, at least 10 seeds with a value on both | shipped mean 12.17, pull mean 11.92 over 15 seeds; difference -0.25 | PASS |
| 4. R4, R10, R11 on all 15 seeds (pull runs) | see table | FAIL |
| 5. T1 to T11 pass on the five standard seeds (candidate) | targets fail on 4 of 5 seeds (list below); T10 range check passes on all | FAIL |
| 6. deaths_unexplained 0 and no new death cause (pull runs, 15 seeds) | deaths_unexplained 0 on all 15, new cause type: none (read by cause type) | PASS |

Gate reported: chosen clause binds on 6 of 15 seeds shipped, 6 of 15 seeds under the pull; the gate would open on 10 seeds shipped and 9 under the pull (sol 300 horizon).
R12 reopen trigger (any seed later than sol 80, or two or more later than 68): shipped later than 80 on no seed, later than 68 on 2 seeds; pull later than 80 on no seed, later than 68 on 2 seeds.

### T1 to T11 on the five standard seeds (balance_run.gd, 300 sols; shipped and candidate)
| seed | table hash shipped | table hash candidate | candidate run twice identical | shipped targets failing | candidate targets failing |
| --- | --- | --- | --- | --- | --- |
| 42 | a96b8a9562fd75d0 | 865621f107f56ba8 | yes | none | none |
| 7 | a4968e2fcc48ec36 | 11eb78e7b32d1f87 | yes | none | T5 |
| 99 | 2210719cf48d8612 | 7bc93247329af19a | yes | none | T5, T11 |
| 1234 | 19437e397d1dff88 | 5b214c3061257b8c | yes | none | T7 |
| 2026 | 6e7fe68477161196 | f68aa7fbd4169b38 | yes | none | T5, T7 |

- seed 7 T5: demand>supply 0.48% of steps (<=10), max shorts/sol 1 (<=2), max offline 35.4 h (<=24.7), first new reactor sol 10 (<=15)
- seed 99 T5: demand>supply 3.47% of steps (<=10), max shorts/sol 1 (<=2), max offline 211.8 h (<=24.7), first new reactor sol 11 (<=15)
- seed 99 T11: (1) list lengths 301/301/301/301 ok; (2) lonely mean of last 50 readings 0.360 (max 0.35) BAD; (3) friends_mean 1.16 (1.0..15.0) ok; (4) first_friendship_sol 68 ok; (5) lines_dropped (total) 0 ok; report: web 0.34 second 0.03 lonely 0.35 friends_mean 1.16 frie
- seed 1234 T7: turn_backs_air 1, exhausted 557, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2221
- seed 2026 T5: demand>supply 2.24% of steps (<=10), max shorts/sol 1 (<=2), max offline 165.6 h (<=24.7), first new reactor sol 13 (<=15)
- seed 2026 T7: turn_backs_air 1, exhausted 630, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2107


## Hash changes
Shipped state: probe digests and balance table hashes equal the Task 4 values on the five standard seeds (balance table hashes in the T1 to T11 table, left column). Under the candidate every one of the 15 probe digests differs from its shipped digest, and every standard-seed balance table hash differs (table above). The candidate balance runs repeat byte-identical (`pull` against `pull2`, five seeds). If adopted this would be an owner-approved baseline reset of all five Task 1/3/4 hashes; the old-and-new pairs are the two hash columns above.

## Reported, not judged
- **Council gate as a timer.** Recomputed readings (table above, estimates of 5.1 to 5.3). The chosen-friend clause delays opening (the other clauses hold earlier) on 6 of 15 seeds shipped (42, 7, 1, 5, 34, 55) and on 6 of 15 under the pull (7, 1, 2, 5, 8, 34), so under the pull the chosen clause still binds. By the lead's own test ("binds on no seed") the pull does not make the gate a timer on this probe. The gate would open by sol 300 on 10 seeds shipped and 9 under the pull. The probe cannot enter Council, so after-entry splits are not seen. Minimum chosen reading from sol 60 is 0.000 on every run except shipped seed 21 (0.238) (early sols, before any chosen friendship), so that column does not discriminate.
- **Task 3 ages under the candidate** (standard seeds, table above): settlement sols 67, 58, 54, 68, 53 (1234 moved from 65 to 68; the rest unchanged); fall-backs: seed 42 at sol 207 (ice) against 213, seed 99 at sol 222 (power) against 174 (ice), seed 2026 a new fall-back at sol 220 (ice), seed 7 and 1234 none. T10 (1) range 40..150 passes on all five.
- **K1.** Seed 42 0.342 to 0.286, seed 2026 0.330 to 0.309; the pull moved seed 7 from 0.025 to 0.267 and seed 3 from 0.333 to 0.526.
- **K2.** First newcomer line sol is identical on all 15 seeds under the pull (seed 99: 68 on both runs; two seeds later than 68 on both runs, none later than 80). The pull does not touch the early game.
- **K3 and R1.** Median kin-newborn wait, shipped to pull: seed 42 28.0 to 35.0, 99 29.0 to 33.0, 2026 29.0 to 33.0 (limit 30). R1 fails under the pull on seeds 42, 99, 2026, 21, 89 and passes on those seeds shipped. R1 failed shipped on seed 3 only (33.0, pull 26.0).
- **Probe table failures by seed (all targets R1 to R14, 300 sols).** Shipped: 1 (R3, R4), 3 (R1), 5 (R2), 13 (R3), 21 (R12, R3), 55 (R2). Candidate: 42 (R1), 99 (R1, R3), 2026 (R1), 1 (R3), 3 (R3, R4), 5 (R2), 21 (R10, R12, R1, R3, R4, R7), 55 (R2), 89 (R1).
- **Seed 21 under the pull:** the colony is extinct at sol 300 (pop 0, 135 thirst deaths, settlement 69, fall-back sol 190 ice, pop 127 at the sol 201 table row). Shipped seed 21: pop 165, 28 thirst deaths. Seeds 7 and 13 gain thirst deaths where shipped had none (8 and 5); seed 21 has 135 against 28. No other cause appears on any run.
- **R13 (2.5 warning), log share (0.15), F4-1.** R13 tail above 2.5 per 5 sols: shipped seeds 2 (2.53), 8 (2.63), 55 (2.70); pull seeds 7 (2.83), 2 (2.57). Log share above 0.15: shipped seed 5 (0.152), none under the pull. Longest silent run before the first newcomer line: identical shipped and pull on every seed (16 to 35 sols; seed 99 35, seed 5 33, seed 55 30).
- **Breadth.** Median distinct beings met in a newborn's first 20 sols and the share of group hours going to its single most-shared being are in the repeat table. Pooled, the pull moved the repeat value by -0.25 h (12.17 to 11.92) and the top-being share and distinct count by small amounts in both directions per seed.

## Notes on the readings
- Clause 2 was judged on 15 eligible seeds (every seed has a shipped zero-friend share above 0, so none is left out and the 6-seed floor is met). Seed 21 under the pull has no late newborn (extinct) and counts as not better. Leaving seed 21 out would give 5 better of 14 eligible, needed 10: the result is the same.
- Clause 1 over the 14 seeds with a share on both runs: the pull mean is higher than shipped (+0.046); the paired SE is 0.031 (reported, not judged).
- The per-seed zero-friend change is higher under the pull on 9 of 14 seeds with shares on both runs (7, 99, 1234 by +0.001, 3, 5, 8, 34, 55, 89) and lower on 5 (42, 2026, 1, 2, 13).
- Clause 6 is read by cause type (the only type on any run is thirst, shipped and candidate; `deaths_unexplained` 0 on all 30 runs). Read per seed, seeds 7 and 13 gain a cause they did not have.
- The probe observes after every step and writes nothing; the shipped digests above prove that. Wall times of the 30 probe runs were 69 to 217 s each, four at a time on four cores (not a cost measurement).
