# Task 4 balance log (relationships and trust), step 6

Branch `claude/eloquent-franklin-igzhoi`, spec `docs/specs/relationships.md` revision 7 (sections 12, 13, 15, 17 "Run 2 findings"). Shipped state: `grow.room_rate` **0.008** (confirmed in `data/relationships.json` at the branch head), both pulls 0.0, no `relationships.*` sim key changed in this step. Every number below was measured in this step by `tests/balance_run.gd` (seed, 300 sols, rows every 30 sols), `tests/relationships_hash_proof.gd` and `tools/relationships_probe.gd --pull shipped`; raw output is in `docs/balance/task-4-log-data/` (`balance_seed_N.txt`, `hash_proof.txt`, `probe/`).

Commands: `godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols 300`; `... res://tests/relationships_hash_proof.gd`; `... res://tools/relationships_probe.gd -- --seed N --sols 300 --pull shipped --out DIR`.

## Summary

| seed | T1 to T10 | T11 | RESULT | table sha256 (16) | rerun table |
|---|---|---|---|---|---|
| 42 | all PASS (T9 N/A: determinism by rerun) | PASS | PASS | a96b8a9562fd75d0 | identical (byte for byte) |
| 7 | all PASS (T9 N/A: determinism by rerun) | PASS | PASS | a4968e2fcc48ec36 | identical (byte for byte) |
| 99 | all PASS (T9 N/A: determinism by rerun) | PASS | PASS | 2210719cf48d8612 | identical (byte for byte) |
| 1234 | all PASS (T9 N/A: determinism by rerun) | PASS | PASS | 19437e397d1dff88 | identical (byte for byte) |
| 2026 | all PASS (T9 N/A: determinism by rerun) | PASS | PASS | 6e7fe68477161196 | identical (byte for byte) |

Table hash here is the sha256 of the whole table including the `age` and `web` columns (the balance run output), not the Task 1 or Task 3 hashes below.

## Balance table per seed (300 sols, every 30; last column `web` = latest `web_share`, two decimals)

### Seed 42
```
Godot Engine v4.5.stable.official.876b29033 - https://godotengine.org

 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2 age web
  30   19    7    12 0/0/0/0/0                 550.0   420.0    73.6    19.1   20.0   28.0     0 2/4/1/1/0/0           2    39  54.5   10.6  438.9   45.8  261.5 L 1.00
  60   27   19    20 0/0/0/0/0                 700.0   540.0    97.9    56.3   30.0   42.0     0 3/6/1/2/0/0           2    81  54.3   10.7  550.3   64.1  547.1 L 0.81
  90   52   27    45 0/0/0/0/0                 688.4   540.0    98.7    39.8   44.0   56.0     0 4/10/1/2/0/0          2   128  56.6   10.8  471.3   67.4  688.1 S 0.81
 120   72   52    65 0/0/0/0/0                 846.9   660.0   101.4    72.7   58.0   70.0     0 5/14/1/3/0/0          2   194  55.9   10.6  445.8   85.7  682.3 S 0.64
 150   82   72    75 0/0/0/0/0                1000.0   780.0     5.7   118.1   68.0   84.0     0 6/16/1/4/0/0          2   186  57.5   10.8  536.1    1.6  839.2 S 0.65
 180  102   82    95 0/0/0/0/0                1000.0   780.0    66.1     3.1   82.0   84.0     0 6/20/1/4/0/0          2   274  56.7   10.6  490.4    0.0  995.9 S 0.44
 210  122  102   115 0/0/0/0/0                1150.0   900.0    36.0   194.3   98.0   98.0     0 7/24/1/5/0/0          2   344  57.5   10.9  523.0   14.8  948.4 S 0.57
 240  137  119   133 0/3/0/0/0                1292.1  1020.0    87.0   204.3  111.0  112.0     0 8/27/1/6/0/0          2   329  59.4   10.9  543.3    0.0 1123.3 L 0.66
 270  147  137   146 0/6/0/0/0                1299.5  1020.0   100.8   322.4  119.0  126.0     0 9/29/1/6/1/0          2   338  59.6   11.0  580.4    0.0 1292.2 L 0.56
 300  164  147   167 0/10/0/0/0               1450.0  1140.0     0.0   154.8  135.0  140.0     0 10/33/1/7/1/0         2   361  59.3   10.9  541.1    0.0 1227.2 L 0.51
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
  T10 PASS first settlement sol 67 (40..150), age_changes 2 (<=4), min gap between consecutive history entries 67 (>=20), history 3 entries (changes+1 = 3); report: sols_in_age landing 154 settlement 146, age at end landing, changes [sol 67 settled; sol 213 fell_back (cause ice)], fall back causes [sol 213 ice], not-ok sols 94 (by group, a sol can fail several: ice 80, food 1, oxygen 1, power 0, death 9, unrest 13)
  T11 PASS (1) list lengths 301/301/301/301 ok; (2) lonely mean of last 50 readings 0.307 (max 0.35) ok; (3) friends_mean 2.01 (1.0..15.0) ok; (4) first_friendship_sol 45 ok; (5) lines_dropped (total) 0 ok; report: web 0.51 second 0.02 lonely 0.40 friends_mean 2.01 friends share of colony 0.012 (pop 164)
RESULT PASS (target 9 determinism: table sha256 a96b8a9562fd75d0)
```

### Seed 7
```
Godot Engine v4.5.stable.official.876b29033 - https://godotengine.org

 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2 age web
  30   12    7     5 0/0/0/0/0                 550.0   420.0    63.7   114.7   16.0   28.0     0 2/2/1/1/0/0           2    37  54.4   10.6  306.5   45.6  261.5 L 1.00
  60   22   12    15 0/0/0/0/0                 700.0   540.0   132.8   191.0   26.0   28.0     0 2/4/1/2/0/0           2    67  57.9   11.0  287.2   60.9  548.0 S 0.91
  90   32   22    25 0/0/0/0/0                 700.0   540.0   217.8   297.2   30.0   42.0     0 3/6/1/2/0/0           2    77  60.5   11.1  114.9  128.6  698.0 S 0.88
 120   37   32    30 0/0/0/0/0                 700.0   540.0   266.5   349.3   35.0   42.0     0 3/7/1/2/0/0           2    88  60.3   11.0   59.7  206.6  698.0 S 0.95
 150   47   37    40 0/0/0/0/0                 699.5   540.0   351.3   463.2   39.0   42.0     0 3/9/1/2/0/0           2   109  60.6   10.8  185.5  221.9  695.4 S 0.89
 180   47   47    40 0/0/0/0/0                 700.0   540.0   361.1   385.2   41.0   42.0     0 3/9/1/2/0/0           2    71  61.2   10.8   28.8  344.5  697.9 S 0.96
 210   52   47    45 0/0/0/0/0                 787.2   624.1   320.2   409.2   46.0   56.0     0 4/10/1/3/0/0          2   100  60.4   10.8  161.4  316.7  694.0 S 0.96
 240   52   52    45 0/0/0/0/0                 850.0   660.0   401.6   521.6   46.0   56.0     0 4/10/1/3/0/0          2   117  58.5   10.7    0.0  319.2  787.3 S 0.92
 270   52   52    45 0/0/0/0/0                 850.0   660.0   394.1   521.6   46.0   56.0     0 4/10/1/3/0/0          2    83  60.1   10.6    0.0  354.4  848.2 S 0.96
 300   72   52    65 0/0/0/0/0                 850.0   660.0   268.6   171.0   60.0   70.0     0 5/14/1/3/0/0          2   104  59.9   10.8  261.0  265.3  846.8 S 0.97
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
  T10 PASS first settlement sol 58 (40..150), age_changes 1 (<=4), min gap between consecutive history entries 58 (>=20), history 2 entries (changes+1 = 2); report: sols_in_age landing 58 settlement 242, age at end settlement, changes [sol 58 settled], fall back causes [none], not-ok sols 9 (by group, a sol can fail several: ice 0, food 1, oxygen 1, power 0, death 0, unrest 8)
  T11 PASS (1) list lengths 301/301/301/301 ok; (2) lonely mean of last 50 readings 0.039 (max 0.35) ok; (3) friends_mean 12.67 (1.0..15.0) ok; (4) first_friendship_sol 34 ok; (5) lines_dropped (total) 0 ok; report: web 0.97 second 0.00 lonely 0.03 friends_mean 12.67 friends share of colony 0.178 (pop 72)
RESULT PASS (target 9 determinism: table sha256 a4968e2fcc48ec36)
```

### Seed 99
```
Godot Engine v4.5.stable.official.876b29033 - https://godotengine.org

 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2 age web
  30   10    7     3 0/0/0/0/0                 666.9   506.7    48.6    26.0   20.0   28.0     0 2/2/1/2/0/0           2    28  54.4   10.5  521.8   43.1  262.5 L 1.00
  60   29   10    22 0/0/0/0/0                 850.0   660.0    84.7    61.1   34.0   42.0     0 3/6/1/3/0/0           2    78  56.7   11.2  395.0   42.1  667.0 S 0.66
  90   62   29    55 0/0/0/0/0                 850.0   660.0   119.4    69.5   54.0   56.0     0 4/12/1/3/0/0          2   155  58.9   10.9  369.0   84.7  847.1 S 0.63
 120   77   62    70 0/0/0/0/0                1000.0   780.0   110.4   245.0   70.0   84.0     0 6/15/1/4/0/1          2   239  59.2   11.1  535.5   88.0  840.4 S 0.58
 150   97   77    90 0/0/0/0/0                1149.9   900.0   120.6   108.7   86.0   98.0     0 7/19/1/5/0/1          2   235  59.3   11.0  535.7   63.6  997.6 S 0.28
 180  107   97   100 0/0/0/0/0                1147.7   900.0    22.4   178.8   94.0  112.0     0 8/21/2/5/0/1          2   208  58.7   10.9  610.3    0.0 1147.0 L 0.25
 210  132  107   125 0/0/0/0/0                1102.8   900.0   102.0   191.1  111.0  126.0     0 9/26/2/5/0/1          2   378  59.0   11.1  507.3   14.9 1102.2 L 0.49
 240  142  132   140 0/5/0/0/0                1300.0  1020.0    19.7   125.7  124.0  140.0     0 10/28/2/6/0/2         2   311  58.4   10.9  574.0    0.0 1087.7 L 0.50
 270  147  137   158 0/18/0/0/0               1450.0  1140.0     0.3   216.2  131.0  140.0     0 10/29/2/7/0/2         2   299  55.5   10.5  586.6    0.0 1295.6 L 0.63
 300  157  146   172 0/22/0/0/0               1450.0  1140.0    65.2   119.1  140.0  154.0     0 11/31/2/7/0/3         2   366  57.8   10.8  575.6    0.0 1445.6 L 0.57
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
  T10 PASS first settlement sol 54 (40..150), age_changes 2 (<=4), min gap between consecutive history entries 54 (>=20), history 3 entries (changes+1 = 3); report: sols_in_age landing 180 settlement 120, age at end landing, changes [sol 54 settled; sol 174 fell_back (cause ice)], fall back causes [sol 174 ice], not-ok sols 113 (by group, a sol can fail several: ice 106, food 1, oxygen 1, power 0, death 16, unrest 7)
  T11 PASS (1) list lengths 301/301/301/301 ok; (2) lonely mean of last 50 readings 0.313 (max 0.35) ok; (3) friends_mean 1.78 (1.0..15.0) ok; (4) first_friendship_sol 68 ok; (5) lines_dropped (total) 0 ok; report: web 0.57 second 0.02 lonely 0.29 friends_mean 1.78 friends share of colony 0.011 (pop 157)
RESULT PASS (target 9 determinism: table sha256 2210719cf48d8612)
```

### Seed 1234
```
Godot Engine v4.5.stable.official.876b29033 - https://godotengine.org

 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2 age web
  30   12    7     5 0/0/0/0/0                 677.3   515.0    72.3    38.8   18.0   28.0     0 2/2/1/2/0/0           2    28  53.8   10.6  523.1   50.4  262.5 L 1.00
  60   27   12    20 0/0/0/0/0                 700.0   540.0   109.0    54.9   29.0   42.0     0 3/5/1/2/0/0           2    81  55.9   10.8  319.3   70.2  677.4 L 0.89
  90   57   27    50 0/0/0/0/0                 850.0   660.0   195.7   102.6   51.0   56.0     0 4/11/1/3/0/0          2   182  58.4   11.1  415.7   94.2  693.7 S 0.68
 120   82   57    75 0/0/0/0/0                 823.6   660.0   174.9   233.9   66.0   70.0     0 5/16/1/3/0/0          2   223  57.2   10.8  422.9  153.4  823.6 S 0.57
 150  102   82    95 0/0/0/0/0                 996.5   780.0   167.1    73.6   82.0   98.0     0 7/20/1/4/0/0          2   254  58.3   10.9  416.5   97.3  812.4 S 0.57
 180  107  102   100 0/0/0/0/0                1150.0   900.0   716.9   776.2   87.0   98.0     0 7/21/1/5/0/0          2   391  58.1   11.2  143.2  118.9  932.0 S 0.77
 210  112  107   105 0/0/0/0/0                1150.0   900.0   666.6   792.4   90.0   98.0     0 7/22/1/5/0/0          2   232  57.0   10.4   42.8  553.7 1147.0 S 0.74
 240  132  112   125 0/0/0/0/0                1282.7  1020.0   345.6   427.3  108.0  112.0     0 8/26/1/6/0/0          2   270  59.0   10.8  408.9  345.6 1119.5 S 0.76
 270  142  132   135 0/0/0/0/0                1300.0  1020.0   815.2   911.3  112.0  126.0     0 9/28/1/6/0/0          2   441  59.6   11.1  128.7  210.1 1282.8 S 0.87
 300  142  142   135 0/0/0/0/0                1300.0  1020.0  1014.2   911.3  112.0  126.0     0 9/28/1/6/0/0          2   292  60.7   10.9    0.0  694.6 1296.1 S 0.87
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
  T10 PASS first settlement sol 65 (40..150), age_changes 1 (<=4), min gap between consecutive history entries 65 (>=20), history 2 entries (changes+1 = 2); report: sols_in_age landing 65 settlement 235, age at end settlement, changes [sol 65 settled], fall back causes [none], not-ok sols 11 (by group, a sol can fail several: ice 0, food 1, oxygen 1, power 0, death 0, unrest 10)
  T11 PASS (1) list lengths 301/301/301/301 ok; (2) lonely mean of last 50 readings 0.159 (max 0.35) ok; (3) friends_mean 7.56 (1.0..15.0) ok; (4) first_friendship_sol 41 ok; (5) lines_dropped (total) 0 ok; report: web 0.87 second 0.01 lonely 0.12 friends_mean 7.56 friends share of colony 0.054 (pop 142)
RESULT PASS (target 9 determinism: table sha256 19437e397d1dff88)
```

### Seed 2026
```
Godot Engine v4.5.stable.official.876b29033 - https://godotengine.org

 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2 age web
  30   12    7     5 0/0/0/0/0                 550.0   420.0    72.1    63.9   16.0   28.0     0 2/2/1/1/0/0           2    33  54.3   10.6  472.6   64.8  261.5 L 1.00
  60   26   12    19 0/0/0/0/0                 524.7   420.0   131.3   116.1   25.0   28.0     0 2/5/1/1/1/0           2    74  56.6   11.0  412.8   15.1  524.0 S 0.92
  90   37   26    30 0/0/0/0/0                 700.0   540.0   153.7   149.1   37.0   42.0     0 3/7/1/2/1/0           2    99  56.3   10.9  295.3   76.5  517.1 S 0.38
 120   62   37    55 0/0/0/0/0                 850.0   660.0   121.5    55.0   56.0   56.0     0 4/12/1/3/1/0          2   156  55.7   10.9  342.3  105.4  693.3 S 0.21
 150   78   62    71 0/0/0/0/0                 999.3   780.0    62.6   187.7   70.0   84.0     0 6/16/1/4/1/0          2   246  55.9   10.9  425.1   62.6  841.8 S 0.50
 180  106   78   101 0/2/0/0/0                 988.3   780.0    22.9   123.1   85.0   98.0     0 7/21/1/4/1/0          2   283  56.9   10.8  474.6    0.0  987.5 S 0.46
 210  112  106   107 0/2/0/0/0                1150.0   900.0   635.3   684.1   92.0   98.0     0 7/22/1/5/1/0          2   411  57.8   11.1  127.1   17.5  861.1 S 0.64
 240  117  112   112 0/2/0/0/0                1150.0   900.0   659.3   572.3   95.0  112.0     0 8/23/1/5/1/0          2   215  60.2   10.9   77.4  579.8 1147.3 S 0.79
 270  132  117   127 0/2/0/0/0                1257.9  1020.0   282.5   276.9  114.0  126.0     0 9/26/2/6/1/0          2   295  58.0   10.7  530.7  279.4 1118.2 S 0.57
 300  156  132   154 0/5/0/0/0                1299.2  1020.0     0.0   126.1  129.0  140.0     0 10/31/2/6/1/0         2   332  58.1   10.8  514.7    0.0 1258.0 S 0.35
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
  T10 PASS first settlement sol 53 (40..150), age_changes 1 (<=4), min gap between consecutive history entries 53 (>=20), history 2 entries (changes+1 = 2); report: sols_in_age landing 53 settlement 247, age at end settlement, changes [sol 53 settled], fall back causes [none], not-ok sols 36 (by group, a sol can fail several: ice 25, food 1, oxygen 1, power 0, death 4, unrest 10)
  T11 PASS (1) list lengths 301/301/301/301 ok; (2) lonely mean of last 50 readings 0.327 (max 0.35) ok; (3) friends_mean 1.28 (1.0..15.0) ok; (4) first_friendship_sol 54 ok; (5) lines_dropped (total) 0 ok; report: web 0.35 second 0.05 lonely 0.37 friends_mean 1.28 friends share of colony 0.008 (pop 156)
RESULT PASS (target 9 determinism: table sha256 6e7fe68477161196)
```
## T11 (judged from `stats.relationships` only; checks 1 to 5)

| seed | (1) list lengths | (2) lonely mean, last 50 readings (max 0.35) | (3) friends_mean (1.0 to 15.0) | (4) first_friendship_sol | (5) dropped (total, `lines_dropped_by_type` not built) | verdict |
|---|---|---|---|---|---|---|
| 42 | 301/301/301/301 | 0.307 | 2.01 | 45 | 0 | PASS |
| 7 | 301/301/301/301 | 0.039 | 12.67 | 34 | 0 | PASS |
| 99 | 301/301/301/301 | 0.313 | 1.78 | 68 | 0 | PASS |
| 1234 | 301/301/301/301 | 0.159 | 7.56 | 41 | 0 | PASS |
| 2026 | 301/301/301/301 | 0.327 | 1.28 | 54 | 0 | PASS |

Reported at sol 300 (web / second / lonely shares, friends_mean, friends as a share of the colony `friends_mean / (pop - 1)`, D2): seed 42 0.51 / 0.02 / 0.40, 2.01, 0.012 (pop 164); seed 7 0.97 / 0.00 / 0.03, 12.67, 0.178 (pop 72); seed 99 0.57 / 0.02 / 0.29, 1.78, 0.011 (pop 157); seed 1234 0.87 / 0.01 / 0.12, 7.56, 0.054 (pop 142); seed 2026 0.35 / 0.05 / 0.37, 1.28, 0.008 (pop 156). Narrow margins on check (2): seed 42 by 0.043, seed 2026 by 0.023 (known issue K1). Check (4) has no sol bound by the spec; seed 99's 68 is K2.

Unit tests: `tests/test_relationships_balance.gd` (moved in from `tests/deferred/`, two tests, 60-sol runs) checks that `web` is the last field after `age` with two decimals and equals the latest `web_share`, and that T11 agrees with the five conditions recomputed from `stats.relationships`.

## Hash proof (`tests/relationships_hash_proof.gd`, raw: `task-4-log-data/hash_proof.txt`)

Drop `web` must give the Task 3 table hash; drop `web` and `age` must give the Task 1 hash. Both columns present on all five seeds.

| seed | drop `web` | Task 3 expected | drop `web` and `age` | Task 1 expected | result |
|---|---|---|---|---|---|
| 42 | da166c4f8b202820 | da166c4f8b202820 | 02032b2388529913 | 02032b23... | MATCH, MATCH |
| 7 | 30c53f90949d979b | 30c53f90949d979b | 830c7d0c441823f5 | 830c7d0c... | MATCH, MATCH |
| 99 | 54ad1e15b934bf9a | 54ad1e15b934bf9a | 0e3e83a7108140ef | 0e3e83a7... | MATCH, MATCH |
| 1234 | 7052c92936a75157 | 7052c92936a75157 | bca6eb2ca93ba0c1 | bca6eb2c... | MATCH, MATCH |
| 2026 | 67e3dcf057200eb9 | 67e3dcf057200eb9 | 2645033a417ec400 | 2645033a... | MATCH, MATCH |

So the module changed no old column (the pairing of section 12 holds: both pulls 0.0 change nothing beings do).

## Same-seed reruns

Each seed's balance run was made twice (the second into the scratchpad); the full output files are byte for byte identical on all five seeds (`cmp`), so the table hashes in the summary are identical. The hash proof is a third run of each seed and reproduces the old hashes above.

## Task 3 age behaviour per seed (T10, unchanged)

| seed | first settlement sol (Task 3: 67, 58, 54, 65, 53) | age changes | fall-backs | age at 300 |
|---|---|---|---|---|
| 42 | 67 | 2 | sol 213 (cause ice) | landing |
| 7 | 58 | 1 | none | settlement |
| 99 | 54 | 2 | sol 174 (cause ice) | landing |
| 1234 | 65 | 1 | none | settlement |
| 2026 | 53 | 1 | none | settlement |

Identical to the Task 3 calibration on every seed (settlement sols and both fall-backs); the Task 3 table hashes above also prove the age columns unchanged. No difference to state.

## Revision 7 targets (probe, shipped pulls, 300 sols; raw: `task-4-log-data/probe/`)

| # | target | seed 42 | 7 | 99 | 1234 | 2026 | verdict |
|---|---|---|---|---|---|---|---|
| R1 | kin newborns' median birth-to-first-friend wait <= 30 sols (resolved / unresolved) | 28.0 (128 / 39) | 25.0 (45 / 20) | 29.0 (133 / 39) | 26.0 (131 / 4) | 29.0 (120 / 34) | PASS all (margins 1 sol on 99 and 2026) |
| R1 reported | colony-first grown friendship, gap after first birth | 32 | 15 | 42 | 20 | 36 | not judged |
| R3 | lonely mean of last 50 readings <= 0.35 | 0.307 | 0.039 | 0.313 | 0.159 | 0.327 | PASS all |
| R4 | friends_mean in 1.0 to 15.0 | 2.01 | 12.67 | 1.78 | 7.56 | 1.28 | PASS all |
| R10 | selectivity ratio >= 2.0 | 6.59 | 2.49 | 4.82 | 2.53 | 2.33 | PASS all |
| R11 | coldest-third mean <= 10.0 | 0.59 | 7.54 | 0.63 | 4.23 | 0.83 | PASS all |
| R12 | first newcomer line at or after sol 25 (judged); by sol 55 (reported) | 45 | 34 | 68 (over 55) | 41 | 54 | PASS all; upper bound over on seed 99 (K2) |
| R13 | `found_friend` lines per 5 sols, sols 150 to 299, <= 3.0 | 1.80 | 0.33 | 2.37 | 2.30 | 2.10 | PASS all (seed 99 margin 0.63) |
| R13 reported | ratio to the 20..299 mean; births 150..299; lines per birth | 1.24; 92; 0.59 | 0.44; 25; 0.40 | 1.44; 82; 0.87 | 1.24; 40; 1.73 | 1.32; 83; 0.76 | not judged |
| R14 | dropped events = 0 (total) | 0 | 0 | 0 | 0 | 0 | PASS all |
| D1 | friend pairs / ever-together pairs (flag above 0.35) | 0.013 | 0.236 | 0.012 | 0.054 | 0.009 | no HIGH |
| D3 | lonely signal DEAD? | no | no | no | no | no | |

R2, R5, R6, R7 also PASS on all five (see the probe reports). Every figure equals the spec's revision 7 Run 2 baseline (section 13 table), including all of R1, R3, R4, R10, R11, R12, R13.

## Test suite

`godot --headless --path station-zero --script res://tests/run_tests.gd`: 493 tests, 41,331 checks, 5 failures, all known and unchanged: `test_view_model::test_data_every_art_leaf_is_named_in_the_spec` (art leaves `interior.stranger_talk_share`, `interior.stranger_talk_cycle_s`), `test_view_relationships::test_t16b_*` (2 checks) and `test_t16c_*` (2 checks). No host-speed timing test failed in this run. `test_relationships` passes in full (61 tests, 646 checks), including test 15 on the new key.

## Commits in this step

1. `45e24ab` data: `balance.found_friend_tail_per5_max` 3.0 replaces `found_friend_tail_ratio_max`; test 15 key-path and sanity rule (and its broken-copy case) renamed.
2. `d50576c` probe: R1 birth-relative (kin newborn median, unresolved counted and left out, colony-first gap reported), R12 lower bound judged and upper bound reported, R13 absolute ceiling with ratio, births in 150..299 and lines per birth reported. (This commit also carries the `git mv` of the parked test, with no content change.)
3. `1a860cd` T11 in `tests/balance_lib.gd`; the parked test is now `tests/test_relationships_balance.gd`.
4. This log and its raw data.

## Deviations and notes

- The `web` column and `relationships` in `data_hash` were already in `tests/balance_lib.gd` from step 4; step 6 added only T11 (checks 1 to 5) and the test.
- Check (5) reads the total `lines_dropped` because `lines_dropped_by_type` is not built (spec 13 item 1, 14); the balance test asserts the key is absent so that building it forces an update of T11 and the test.
- Check (1) compares against `stats.pop_by_sol` as the spec's `pop_by_sol` (the world list, not a copy inside `stats.relationships`).
- The probe's target key names changed (`R1_kin_newborn_median_wait`, `R12_first_newcomer_line_lower_bound`, `R13_found_friend_late_tail_ceiling`) so older calibration JSON is not compared by name. `docs/balance/task-4-calibration.md` (Run 2) was not regenerated: this log is the revision 7 record.
- The probe table printer (`--tables`) was not updated for the new reported lines; the per-seed text reports in `task-4-log-data/probe/` carry them.
- Only a "shipped pull" probe run was made; the friend and both-pull probe runs of the calibration report were not repeated (not asked, no key changed).
- No value was tuned. `grow.room_rate` is 0.008.
- A concurrent commit (`16f5b02`, round 4 reviews, not mine) landed between my commits; nothing conflicted.
