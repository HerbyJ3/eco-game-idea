# Task 5 balance log (Council), step 7

Branch `claude/eloquent-franklin-igzhoi`, spec `docs/specs/council.md` (current revision; owner answer O6 = A, `decide.carry_quorum` 0.35 as shipped in `data/council.json`). Nothing was tuned: no `data/` file and no `sim/` file changed in this step. Every number below was measured in this step by `tests/balance_run.gd` (seed, 300 sols, rows every 30 sols), `tests/council_hash_proof.gd` and `tests/run_tests.gd`; raw output is in `docs/balance/task-5-log-data/` (`.gdignore`d): `balance_seed_N.txt`, `rerun_seed_N.txt`, `hash_proof.txt`, `full_suite.txt`.

Commands: `godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols 300 | head -c 200000`; `... res://tests/council_hash_proof.gd`; `... res://tests/run_tests.gd`.

## Summary

| seed | T1 to T10 | T11 | T12 | RESULT | table sha256 (16) | rerun table |
|---|---|---|---|---|---|---|
| 42 | all PASS (T9 N/A: determinism by rerun) | PASS | PASS | PASS | 330325504427720a | identical (byte for byte, `cmp`) |
| 7 | all PASS (T9 N/A: determinism by rerun) | PASS | PASS | PASS | 1ceb89a7d3e87540 | identical (byte for byte, `cmp`) |
| 99 | all PASS (T9 N/A: determinism by rerun) | PASS | PASS | PASS | 7feb81cee7c86fa5 | identical (byte for byte, `cmp`) |
| 1234 | all PASS (T9 N/A: determinism by rerun) | PASS | PASS | PASS | 7c8bcf782a06f1fa | identical (byte for byte, `cmp`) |
| 2026 | all PASS (T9 N/A: determinism by rerun) | PASS | PASS | PASS | 076e42c032a208aa | identical (byte for byte, `cmp`) |

Table hash is the sha256 of the table body including the `age`, `web` and `cn` columns (the line printed after RESULT). It differs from Task 4 because of the new `cn` column and because the `age` column is now the L/S projection (spec 9.1); the hash proof below shows the old tables reappear when the new columns are dropped.

## Balance table per seed (300 sols, every 30; last columns `age` (L or S, projection), `web` = latest `web_share`, `cn` = - / C / P)

### Seed 42
```
 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2 age web cn
  30   19    7    12 0/0/0/0/0                 550.0   420.0    73.6    19.1   20.0   28.0     0 2/4/1/1/0/0           2    39  54.5   10.6  438.9   45.8  261.5 L 1.00 -
  60   27   19    20 0/0/0/0/0                 700.0   540.0    97.9    56.3   30.0   42.0     0 3/6/1/2/0/0           2    81  54.3   10.7  550.3   64.1  547.1 L 0.81 -
  90   52   27    45 0/0/0/0/0                 688.4   540.0    98.7    39.8   44.0   56.0     0 4/10/1/2/0/0          2   128  56.6   10.8  471.3   67.4  688.1 S 0.81 -
 120   72   52    65 0/0/0/0/0                 846.9   660.0   101.4    72.7   58.0   70.0     0 5/14/1/3/0/0          2   194  55.9   10.6  445.8   85.7  682.3 S 0.64 C
 150   82   72    75 0/0/0/0/0                1000.0   780.0     5.7   118.1   68.0   84.0     0 6/16/1/4/0/0          2   186  57.5   10.8  536.1    1.6  839.2 S 0.65 C
 180  102   82    95 0/0/0/0/0                1000.0   780.0    66.1     3.1   82.0   84.0     0 6/20/1/4/0/0          2   274  56.7   10.6  490.4    0.0  995.9 S 0.44 C
 210  122  102   115 0/0/0/0/0                1150.0   900.0    36.0   194.3   98.0   98.0     0 7/24/1/5/0/0          2   344  57.5   10.9  523.0   14.8  948.4 S 0.57 C
 240  137  119   133 0/3/0/0/0                1292.1  1020.0    87.0   204.3  111.0  112.0     0 8/27/1/6/0/0          2   329  59.4   10.9  543.3    0.0 1123.3 L 0.66 -
 270  147  137   146 0/6/0/0/0                1299.5  1020.0   100.8   322.4  119.0  126.0     0 9/29/1/6/1/0          2   338  59.6   11.0  580.4    0.0 1292.2 L 0.56 -
 300  164  147   167 0/10/0/0/0               1450.0  1140.0     0.0   154.8  135.0  140.0     0 10/33/1/7/1/0         2   361  59.3   10.9  541.1    0.0 1227.2 L 0.51 -
```

```
targets for seed 42 (300 sols):
  T1 PASS run min pop 7 (needs >= 5), final pop 164
  T2 PASS deaths 10 (air 0 thirst 10 hunger 0 eva 0 other 0), unexplained 0
  T3 PASS births 167, first_birth_sol 13, at_capacity 0, cooldown_violations 0, pop@30=19, pop@100=57, pop@300=164
  T4 PASS min O2 261.5, food 203.1; ice ran dry (pressure): min ice 0.0, ice>30 0.0, thirst deaths 10; max ice/target 0.60, regolith/target 0.63
  T5 PASS demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 5 (<=15)
  T6 PASS limited 5120.3 h = 69.21% (>=2% provisional; 4 of 5 seeds), site busy 68.8%; waiting_regolith 1340.0 h, site_no_crew 3780.3 h
  T7 PASS turn_backs_air 0, exhausted 666, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2274
  T8 PASS row avg energy 54.3..59.6 (40..90), row asleep 10.6..11.0% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
  T10 PASS first settlement sol 67 (40..150), age_changes 2 (<=4), min gap between consecutive history entries 67 (>=20), history 4 entries (changes+1 = 4); report: sols_in_age landing 154 settlement 48 council 98, age at end landing, changes [sol 67 settled; sol 115 council; sol 213 fell_back (cause ice)], fall back causes [sol 213 ice], not-ok sols 94 (by group, a sol can fail several: ice 80, food 1, oxygen 1, power 0, death 9, unrest 13)
  T11 PASS (1) list lengths 301/301/301/301 ok; (2) lonely mean of last 50 readings 0.307 (max 0.35) ok; (3) friends_mean 2.01 (1.0..15.0) ok; (4) first_friendship_sol 45 ok; (5) lines_dropped (total) 0 ok; report: web 0.51 second 0.02 lonely 0.40 friends_mean 2.01 friends share of colony 0.012 (pop 164)
  T12 PASS (1) list lengths 301/301/301 ok; (2) C2 ok; (3) council changes 1 (<=4) ok; (4) proposals 2 ok; (5) one Council line per boundary ok; report: first Council sol 115, meetings 19, proposals [dome@120 set_aside; dome@175 set_aside], pledge sol <null> reason -, lines {"divided":2,"proposal":1,"proposal_again":1,"set_aside":1,"set_aside_hard":1}, dropped 0; council_min_seeds 3 pledge_min_seeds 1
RESULT PASS (target 9 determinism: table sha256 330325504427720a)
```

### Seed 7
```
 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2 age web cn
  30   12    7     5 0/0/0/0/0                 550.0   420.0    63.7   114.7   16.0   28.0     0 2/2/1/1/0/0           2    37  54.4   10.6  306.5   45.6  261.5 L 1.00 -
  60   22   12    15 0/0/0/0/0                 700.0   540.0   132.8   191.0   26.0   28.0     0 2/4/1/2/0/0           2    67  57.9   11.0  287.2   60.9  548.0 S 0.91 -
  90   32   22    25 0/0/0/0/0                 700.0   540.0   217.8   297.2   30.0   42.0     0 3/6/1/2/0/0           2    77  60.5   11.1  114.9  128.6  698.0 S 0.88 -
 120   37   32    30 0/0/0/0/0                 700.0   540.0   266.5   349.3   35.0   42.0     0 3/7/1/2/0/0           2    88  60.3   11.0   59.7  206.6  698.0 S 0.95 C
 150   47   37    40 0/0/0/0/0                 699.5   540.0   351.3   463.2   39.0   42.0     0 3/9/1/2/0/0           2   109  60.6   10.8  185.5  221.9  695.4 S 0.89 C
 180   47   47    40 0/0/0/0/0                 700.0   540.0   361.1   385.2   41.0   42.0     0 3/9/1/2/0/0           2    71  61.2   10.8   28.8  344.5  697.9 S 0.96 C
 210   52   47    45 0/0/0/0/0                 787.2   624.1   320.2   409.2   46.0   56.0     0 4/10/1/3/0/0          2   100  60.4   10.8  161.4  316.7  694.0 S 0.96 C
 240   52   52    45 0/0/0/0/0                 850.0   660.0   401.6   521.6   46.0   56.0     0 4/10/1/3/0/0          2   117  58.5   10.7    0.0  319.2  787.3 S 0.92 C
 270   52   52    45 0/0/0/0/0                 850.0   660.0   394.1   521.6   46.0   56.0     0 4/10/1/3/0/0          2    83  60.1   10.6    0.0  354.4  848.2 S 0.96 C
 300   72   52    65 0/0/0/0/0                 850.0   660.0   268.6   171.0   60.0   70.0     0 5/14/1/3/0/0          2   104  59.9   10.8  261.0  265.3  846.8 S 0.97 C
```

```
targets for seed 7 (300 sols):
  T1 PASS run min pop 7 (needs >= 5), final pop 72
  T2 PASS deaths 0 (air 0 thirst 0 hunger 0 eva 0 other 0), unexplained 0
  T3 PASS births 65, first_birth_sol 19, at_capacity 0, cooldown_violations 0, pop@30=12, pop@100=32, pop@300=72
  T4 PASS min O2 261.5, food 203.1; ice never ran dry: min ice 45.6, ice>30 60.9, thirst deaths 0; max ice/target 1.02, regolith/target 1.39
  T5 PASS demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 10 (<=15)
  T6 PASS limited 1404.9 h = 18.99% (>=2% provisional; 4 of 5 seeds), site busy 26.9%; waiting_regolith 0.0 h, site_no_crew 1404.9 h
  T7 PASS turn_backs_air 0, exhausted 242, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 853
  T8 PASS row avg energy 54.4..61.2 (40..90), row asleep 10.6..11.1% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
  T10 PASS first settlement sol 58 (40..150), age_changes 1 (<=4), min gap between consecutive history entries 58 (>=20), history 3 entries (changes+1 = 3); report: sols_in_age landing 58 settlement 37 council 205, age at end council, changes [sol 58 settled; sol 95 council], fall back causes [none], not-ok sols 9 (by group, a sol can fail several: ice 0, food 1, oxygen 1, power 0, death 0, unrest 8)
  T11 PASS (1) list lengths 301/301/301/301 ok; (2) lonely mean of last 50 readings 0.039 (max 0.35) ok; (3) friends_mean 12.67 (1.0..15.0) ok; (4) first_friendship_sol 34 ok; (5) lines_dropped (total) 0 ok; report: web 0.97 second 0.00 lonely 0.03 friends_mean 12.67 friends share of colony 0.178 (pop 72)
  T12 PASS (1) list lengths 301/301/301 ok; (2) C2 ok; (3) council changes 1 (<=4) ok; (4) proposals 3 ok; (5) one Council line per boundary ok; report: first Council sol 95, meetings 41, proposals [dome@105 set_aside; dome@195 set_aside; dome@285 <null>], pledge sol <null> reason -, lines {"divided":1,"proposal":1,"proposal_again":2,"quiet":1,"set_aside_long":2}, dropped 0; council_min_seeds 3 pledge_min_seeds 1
RESULT PASS (target 9 determinism: table sha256 1ceb89a7d3e87540)
```

### Seed 99
```
 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2 age web cn
  30   10    7     3 0/0/0/0/0                 666.9   506.7    48.6    26.0   20.0   28.0     0 2/2/1/2/0/0           2    28  54.4   10.5  521.8   43.1  262.5 L 1.00 -
  60   29   10    22 0/0/0/0/0                 850.0   660.0    84.7    61.1   34.0   42.0     0 3/6/1/3/0/0           2    78  56.7   11.2  395.0   42.1  667.0 S 0.66 -
  90   62   29    55 0/0/0/0/0                 850.0   660.0   119.4    69.5   54.0   56.0     0 4/12/1/3/0/0          2   155  58.9   10.9  369.0   84.7  847.1 S 0.63 -
 120   77   62    70 0/0/0/0/0                1000.0   780.0   110.4   245.0   70.0   84.0     0 6/15/1/4/0/1          2   239  59.2   11.1  535.5   88.0  840.4 S 0.58 -
 150   97   77    90 0/0/0/0/0                1149.9   900.0   120.6   108.7   86.0   98.0     0 7/19/1/5/0/1          2   235  59.3   11.0  535.7   63.6  997.6 S 0.28 -
 180  107   97   100 0/0/0/0/0                1147.7   900.0    22.4   178.8   94.0  112.0     0 8/21/2/5/0/1          2   208  58.7   10.9  610.3    0.0 1147.0 L 0.25 -
 210  132  107   125 0/0/0/0/0                1102.8   900.0   102.0   191.1  111.0  126.0     0 9/26/2/5/0/1          2   378  59.0   11.1  507.3   14.9 1102.2 L 0.49 -
 240  142  132   140 0/5/0/0/0                1300.0  1020.0    19.7   125.7  124.0  140.0     0 10/28/2/6/0/2         2   311  58.4   10.9  574.0    0.0 1087.7 L 0.50 -
 270  147  137   158 0/18/0/0/0               1450.0  1140.0     0.3   216.2  131.0  140.0     0 10/29/2/7/0/2         2   299  55.5   10.5  586.6    0.0 1295.6 L 0.63 -
 300  157  146   172 0/22/0/0/0               1450.0  1140.0    65.2   119.1  140.0  154.0     0 11/31/2/7/0/3         2   366  57.8   10.8  575.6    0.0 1445.6 L 0.57 -
```

```
targets for seed 99 (300 sols):
  T1 PASS run min pop 7 (needs >= 5), final pop 157
  T2 PASS deaths 22 (air 0 thirst 22 hunger 0 eva 0 other 0), unexplained 0
  T3 PASS births 172, first_birth_sol 26, at_capacity 0, cooldown_violations 0, pop@30=10, pop@100=72, pop@300=157
  T4 PASS min O2 262.5, food 203.1; ice ran dry (pressure): min ice 0.0, ice>30 0.0, thirst deaths 22; max ice/target 0.60, regolith/target 0.84
  T5 PASS demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 11 (<=15)
  T6 PASS limited 5210.4 h = 70.43% (>=2% provisional; 4 of 5 seeds), site busy 78.7%; waiting_regolith 820.0 h, site_no_crew 4390.4 h
  T7 PASS turn_backs_air 0, exhausted 645, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2297
  T8 PASS row avg energy 54.4..59.3 (40..90), row asleep 10.5..11.2% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
  T10 PASS first settlement sol 54 (40..150), age_changes 2 (<=4), min gap between consecutive history entries 54 (>=20), history 3 entries (changes+1 = 3); report: sols_in_age landing 180 settlement 120 council 0, age at end landing, changes [sol 54 settled; sol 174 fell_back (cause ice)], fall back causes [sol 174 ice], not-ok sols 113 (by group, a sol can fail several: ice 106, food 1, oxygen 1, power 0, death 16, unrest 7)
  T11 PASS (1) list lengths 301/301/301/301 ok; (2) lonely mean of last 50 readings 0.313 (max 0.35) ok; (3) friends_mean 1.78 (1.0..15.0) ok; (4) first_friendship_sol 68 ok; (5) lines_dropped (total) 0 ok; report: web 0.57 second 0.02 lonely 0.29 friends_mean 1.78 friends share of colony 0.011 (pop 157)
  T12 PASS (1) list lengths 301/301/301 ok; (2) C2 ok; (3) council changes 0 (<=4) ok; (4) proposals 0 ok; (5) one Council line per boundary ok; report: first Council sol <null>, meetings 0, proposals [], pledge sol <null> reason -, lines {"circles":1}, dropped 0; council_min_seeds 3 pledge_min_seeds 1
RESULT PASS (target 9 determinism: table sha256 7feb81cee7c86fa5)
```

### Seed 1234
```
 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2 age web cn
  30   12    7     5 0/0/0/0/0                 677.3   515.0    72.3    38.8   18.0   28.0     0 2/2/1/2/0/0           2    28  53.8   10.6  523.1   50.4  262.5 L 1.00 -
  60   27   12    20 0/0/0/0/0                 700.0   540.0   109.0    54.9   29.0   42.0     0 3/5/1/2/0/0           2    81  55.9   10.8  319.3   70.2  677.4 L 0.89 -
  90   57   27    50 0/0/0/0/0                 850.0   660.0   195.7   102.6   51.0   56.0     0 4/11/1/3/0/0          2   182  58.4   11.1  415.7   94.2  693.7 S 0.68 -
 120   82   57    75 0/0/0/0/0                 823.6   660.0   174.9   233.9   66.0   70.0     0 5/16/1/3/0/0          2   223  57.2   10.8  422.9  153.4  823.6 S 0.57 -
 150  102   82    95 0/0/0/0/0                 996.5   780.0   167.1    73.6   82.0   98.0     0 7/20/1/4/0/0          2   254  58.3   10.9  416.5   97.3  812.4 S 0.57 -
 180  107  102   100 0/0/0/0/0                1150.0   900.0   716.9   776.2   87.0   98.0     0 7/21/1/5/0/0          2   391  58.1   11.2  143.2  118.9  932.0 S 0.77 C
 210  112  107   105 0/0/0/0/0                1150.0   900.0   666.6   792.4   90.0   98.0     0 7/22/1/5/0/0          2   232  57.0   10.4   42.8  553.7 1147.0 S 0.74 P
 240  132  112   125 0/0/0/0/0                1282.7  1020.0   345.6   427.3  108.0  112.0     0 8/26/1/6/0/0          2   270  59.0   10.8  408.9  345.6 1119.5 S 0.76 P
 270  142  132   135 0/0/0/0/0                1300.0  1020.0   815.2   911.3  112.0  126.0     0 9/28/1/6/0/0          2   441  59.6   11.1  128.7  210.1 1282.8 S 0.87 P
 300  142  142   135 0/0/0/0/0                1300.0  1020.0  1014.2   911.3  112.0  126.0     0 9/28/1/6/0/0          2   292  60.7   10.9    0.0  694.6 1296.1 S 0.87 P
```

```
targets for seed 1234 (300 sols):
  T1 PASS run min pop 7 (needs >= 5), final pop 142
  T2 PASS deaths 0 (air 0 thirst 0 hunger 0 eva 0 other 0), unexplained 0
  T3 PASS births 135, first_birth_sol 21, at_capacity 0, cooldown_violations 0, pop@30=12, pop@100=65, pop@300=142
  T4 PASS min O2 262.5, food 203.1; ice never ran dry: min ice 50.4, ice>30 70.2, thirst deaths 0; max ice/target 0.96, regolith/target 1.37
  T5 PASS demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 11 (<=15)
  T6 PASS limited 2821.1 h = 38.13% (>=2% provisional; 4 of 5 seeds), site busy 48.4%; waiting_regolith 325.0 h, site_no_crew 2496.1 h
  T7 PASS turn_backs_air 0, exhausted 646, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2394
  T8 PASS row avg energy 53.8..60.7 (40..90), row asleep 10.4..11.2% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
  T10 PASS first settlement sol 65 (40..150), age_changes 1 (<=4), min gap between consecutive history entries 65 (>=20), history 3 entries (changes+1 = 3); report: sols_in_age landing 65 settlement 95 council 140, age at end council, changes [sol 65 settled; sol 160 council], fall back causes [none], not-ok sols 11 (by group, a sol can fail several: ice 0, food 1, oxygen 1, power 0, death 0, unrest 10)
  T11 PASS (1) list lengths 301/301/301/301 ok; (2) lonely mean of last 50 readings 0.159 (max 0.35) ok; (3) friends_mean 7.56 (1.0..15.0) ok; (4) first_friendship_sol 41 ok; (5) lines_dropped (total) 0 ok; report: web 0.87 second 0.01 lonely 0.12 friends_mean 7.56 friends share of colony 0.054 (pop 142)
  T12 PASS (1) list lengths 301/301/301 ok; (2) C2 ok; (3) council changes 1 (<=4) ok; (4) proposals 1 ok; (5) one Council line per boundary ok; report: first Council sol 160, meetings 28, proposals [dome@165 pledged], pledge sol 195 reason personal, lines {"after_pledge":1,"aftermath_still":1,"circles":1,"pledge":1,"proposal":1}, dropped 0; council_min_seeds 3 pledge_min_seeds 1
RESULT PASS (target 9 determinism: table sha256 7c8bcf782a06f1fa)
```

### Seed 2026
```
 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2 age web cn
  30   12    7     5 0/0/0/0/0                 550.0   420.0    72.1    63.9   16.0   28.0     0 2/2/1/1/0/0           2    33  54.3   10.6  472.6   64.8  261.5 L 1.00 -
  60   26   12    19 0/0/0/0/0                 524.7   420.0   131.3   116.1   25.0   28.0     0 2/5/1/1/1/0           2    74  56.6   11.0  412.8   15.1  524.0 S 0.92 -
  90   37   26    30 0/0/0/0/0                 700.0   540.0   153.7   149.1   37.0   42.0     0 3/7/1/2/1/0           2    99  56.3   10.9  295.3   76.5  517.1 S 0.38 -
 120   62   37    55 0/0/0/0/0                 850.0   660.0   121.5    55.0   56.0   56.0     0 4/12/1/3/1/0          2   156  55.7   10.9  342.3  105.4  693.3 S 0.21 -
 150   78   62    71 0/0/0/0/0                 999.3   780.0    62.6   187.7   70.0   84.0     0 6/16/1/4/1/0          2   246  55.9   10.9  425.1   62.6  841.8 S 0.50 -
 180  106   78   101 0/2/0/0/0                 988.3   780.0    22.9   123.1   85.0   98.0     0 7/21/1/4/1/0          2   283  56.9   10.8  474.6    0.0  987.5 S 0.46 -
 210  112  106   107 0/2/0/0/0                1150.0   900.0   635.3   684.1   92.0   98.0     0 7/22/1/5/1/0          2   411  57.8   11.1  127.1   17.5  861.1 S 0.64 C
 240  117  112   112 0/2/0/0/0                1150.0   900.0   659.3   572.3   95.0  112.0     0 8/23/1/5/1/0          2   215  60.2   10.9   77.4  579.8 1147.3 S 0.79 P
 270  132  117   127 0/2/0/0/0                1257.9  1020.0   282.5   276.9  114.0  126.0     0 9/26/2/6/1/0          2   295  58.0   10.7  530.7  279.4 1118.2 S 0.57 P
 300  156  132   154 0/5/0/0/0                1299.2  1020.0     0.0   126.1  129.0  140.0     0 10/31/2/6/1/0         2   332  58.1   10.8  514.7    0.0 1258.0 S 0.35 P
```

```
targets for seed 2026 (300 sols):
  T1 PASS run min pop 7 (needs >= 5), final pop 156
  T2 PASS deaths 5 (air 0 thirst 5 hunger 0 eva 0 other 0), unexplained 0
  T3 PASS births 154, first_birth_sol 18, at_capacity 0, cooldown_violations 0, pop@30=12, pop@100=47, pop@300=156
  T4 PASS min O2 261.5, food 203.1; ice ran dry (pressure): min ice 0.0, ice>30 0.0, thirst deaths 5; max ice/target 0.90, regolith/target 1.48
  T5 PASS demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 13 (<=15)
  T6 PASS limited 3672.4 h = 49.64% (>=2% provisional; 4 of 5 seeds), site busy 59.3%; waiting_regolith 505.0 h, site_no_crew 3167.4 h
  T7 PASS turn_backs_air 0, exhausted 589, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2144
  T8 PASS row avg energy 54.3..60.2 (40..90), row asleep 10.6..11.1% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
  T10 PASS first settlement sol 53 (40..150), age_changes 1 (<=4), min gap between consecutive history entries 53 (>=20), history 3 entries (changes+1 = 3); report: sols_in_age landing 53 settlement 153 council 94, age at end council, changes [sol 53 settled; sol 206 council], fall back causes [none], not-ok sols 36 (by group, a sol can fail several: ice 25, food 1, oxygen 1, power 0, death 4, unrest 10)
  T11 PASS (1) list lengths 301/301/301/301 ok; (2) lonely mean of last 50 readings 0.327 (max 0.35) ok; (3) friends_mean 1.28 (1.0..15.0) ok; (4) first_friendship_sol 54 ok; (5) lines_dropped (total) 0 ok; report: web 0.35 second 0.05 lonely 0.37 friends_mean 1.28 friends share of colony 0.008 (pop 156)
  T12 PASS (1) list lengths 301/301/301 ok; (2) C2 ok; (3) council changes 1 (<=4) ok; (4) proposals 1 ok; (5) one Council line per boundary ok; report: first Council sol 206, meetings 18, proposals [dome@211 pledged], pledge sol 221 reason personal, lines {"after_pledge":1,"aftermath_still":1,"circles":1,"circles_again":1,"pledge":1,"proposal":1}, dropped 0; council_min_seeds 3 pledge_min_seeds 1
RESULT PASS (target 9 determinism: table sha256 076e42c032a208aa)
```

## T11 and T12

T11 is unchanged from Task 4 and gives the same readings on all five seeds (web / second / lonely at sol 300: 42: 0.51 / 0.02 / 0.40; 7: 0.97 / 0.00 / 0.03; 99: 0.57 / 0.02 / 0.29; 1234: 0.87 / 0.01 / 0.12; 2026: 0.35 / 0.05 / 0.37; lonely means of the last 50 readings 0.307, 0.039, 0.313, 0.159, 0.327).

T12 (spec 12; five conditions: list lengths, C2, C3, proposal outcomes and pledge timing, one Council line per boundary) passes on all five seeds. Reported:

| seed | first Council sol | council changes (<= 4) | meetings | proposals (raised sol, outcome) | pledge sol, reason | lines dropped |
|---|---|---|---|---|---|---|
| 42 | 115 | 1 | 19 | dome@120 set_aside; dome@175 set_aside | none | 0 |
| 7 | 95 | 1 | 41 | dome@105 set_aside; dome@195 set_aside; dome@285 open | none | 0 |
| 99 | none | 0 | 0 | none | none | 0 |
| 1234 | 160 | 1 | 28 | dome@165 pledged | 195, personal | 0 |
| 2026 | 206 | 1 | 18 | dome@211 pledged | 221, personal | 0 |

Cross-seed targets read from these lines (the probe judges them; the balance run only reports the counts): C1 Council entered on 4 of 5 seeds (needs `council_min_seeds` 3); C4 a pledge on 2 of 5 seeds (needs `pledge_min_seeds` 1); C5 divided or set-aside lines on seeds 42 and 7 (2 of 5; needs `argue_min_seeds` 2). C6 to C8 and the D flags are the probe's (`task-5-calibration.md`) and were not re-run here.

## Hash proof (`tests/council_hash_proof.gd`, raw: `task-5-log-data/hash_proof.txt`, exit 0)

`cn`, `web` and `age` were present on all five seeds.

| seed | drop `cn` | Task 4 expected | drop `cn` and `web` | Task 3 expected | drop `cn`, `web` and `age` | Task 1 expected | result |
|---|---|---|---|---|---|---|---|
| 42 | a96b8a9562fd75d0 | a96b8a9562fd75d0 | da166c4f8b202820 | da166c4f8b202820 | 02032b2388529913 | 02032b23... | MATCH x3 |
| 7 | a4968e2fcc48ec36 | a4968e2fcc48ec36 | 30c53f90949d979b | 30c53f90949d979b | 830c7d0c441823f5 | 830c7d0c... | MATCH x3 |
| 99 | 2210719cf48d8612 | 2210719cf48d8612 | 54ad1e15b934bf9a | 54ad1e15b934bf9a | 0e3e83a7108140ef | 0e3e83a7... | MATCH x3 |
| 1234 | 19437e397d1dff88 | 19437e397d1dff88 | 7052c92936a75157 | 7052c92936a75157 | bca6eb2ca93ba0c1 | bca6eb2c... | MATCH x3 |
| 2026 | 6e7fe68477161196 | 6e7fe68477161196 | 67e3dcf057200eb9 | 67e3dcf057200eb9 | 2645033a417ec400 | 2645033a... | MATCH x3 |

So the Council module changed no old column: the Task 1, 3 and 4 tables are reproduced byte for byte when the new columns are removed, on all five seeds. No baseline reset.

## Same-seed reruns

Each seed's balance run was made twice (`balance_seed_N.txt`, `rerun_seed_N.txt`); `cmp` reports the full output byte for byte identical on all five seeds, so the table hashes in the summary are identical. The hash proof is a third run of each seed.

## Ages and Council per seed, before (Task 4 log) and after

Task 3 ages in the projection (T10) are unchanged: settlement 67 / 58 / 54 / 65 / 53, fall-backs sol 213 (seed 42, cause ice) and sol 174 (seed 99, cause ice), and no other fall-back. T10 passes with the same projected change counts as Task 4 (2, 1, 2, 1, 1), and the Task 3 table hashes reproduce.

| seed | Settlement entry, before / after | Council entry, before / after | pledge, before / after | live age changes, before / after | fall-back, before / after | age at sol 300, before / after |
|---|---|---|---|---|---|---|
| 42 | 67 / 67 | none (no module) / 115 | none / none | 2 / 3 | 213 ice / 213 ice | landing / landing |
| 7 | 58 / 58 | none / 95 | none / none | 1 / 2 | none / none | settlement / council |
| 99 | 54 / 54 | none / none | none / none | 2 / 2 | 174 ice / 174 ice | landing / landing |
| 1234 | 65 / 65 | none / 160 | none / 195 | 1 / 2 | none / none | settlement / council |
| 2026 | 53 / 53 | none / 206 | none / 221 | 1 / 2 | none / none | settlement / council |

Reading: "live age changes" counts every `age_history` entry after Landing, so the Council entry is one more change; the projected count (T10 check 2) is unchanged. Seed 42 enters Council at sol 115 and falls back to Landing at sol 213 from the Council (the fall-back sol is Task 3's). Seed 99 falls back at sol 174 before it can enter (sols in age: landing 180, settlement 120, council 0). sols_in_age per seed (landing / settlement / council): 42: 154 / 48 / 98; 7: 58 / 37 / 205; 99: 180 / 120 / 0; 1234: 65 / 95 / 140; 2026: 53 / 153 / 94. Seed 7 has a proposal still open at sol 300 (raised at 285) and seed 7's `set_aside_long` lines come with no pledge.

## Test suite

`godot --headless --path station-zero --script res://tests/run_tests.gd` (raw: `task-5-log-data/full_suite.txt`): 618 tests, 42,482 checks, 6 failure messages in 4 tests, all known: `test_view_council::test_t19b_the_strip_shows_three_merged_chapters_in_time_order` (2), `test_view_council::test_t19c_the_pledge_stays_pinned` (2), `test_view_council::test_t19d_the_hud_source_reads_no_hidden_council_state` (1) (view work of step 9); and the host-speed timing test `test_view_model::test_perf_perf`: median update 2.004 ms against a 2.0 ms limit (passes or fails with host load; not weakened). The other host-speed test did not fail in this run. `tests/test_council_balance.gd`: 7 tests, 50 checks, green.

## Commits in this step

1. `75b4bd9` the parked `tests/deferred/test_council_balance.gd.txt` moved (`git mv`) to `tests/test_council_balance.gd` and made a real test.
2. This log and its raw data.

## Deviations and notes

- `tests/balance_lib.gd` already carried the `cn` column, the L/S `age` projection, `projected_history`, T10 on the projection and T12 (written in step 5/6); this step added no code there and changed no sim or data file.
- The parked test said every row has the same number of fields as the header. It does not: two header labels hold a space (`dead a/t/h/o/x`, `bldg R/H/W/G/A/C`) and are one field in a row, so the test asserts header fields minus 2. The hash proof's strip counts from the right end, so it is unaffected.
- Parked item 2 (hash chain) is not in the unit test: it takes minutes and is `tests/council_hash_proof.gd`, recorded above. The unit test checks the strip helpers on a real printed table instead. Parked item 5 (helper agrees with `tools/age_probe.gd`) is a source check that both call `balance_lib.projected_history`, plus a synthetic history case; `age_probe.gd` itself was not re-run.
- T10 check 4 and its "history N entries" text read the live (unprojected) history, so seed 42 prints `history 4 entries (changes+1 = 4)` next to `age_changes 2`; the projected count is only in check 2.
- C6 to C8 and the D flags (FLOOR, CEILING, SIZE-DOMINANT, LOCKSTEP, NOROOM) were not re-measured here; `docs/balance/task-5-calibration.md` is their record. Cost was not re-measured (no new per-tick work in this step).
- Seeds 42 and 99 end in Landing, so `cn` ends `-` on both; seeds 1234 and 2026 end `P`.
- No value was tuned.
