# Task 1 balance log

## Baseline (step 10, no overrides)
- Base commit: 37eb9e0eb590a6f5ec30c33eab1bc1b6b815d983 (working tree also holds the uncommitted step 10 changes: sim/world.gd stats.window, tests/balance_lib.gd, tests/balance_run.gd, tests/test_determinism.gd). Data files unchanged; data hash 42de63484867d0c5.
- Machine: 4 cores, godot 4.5.stable, headless, fixed_step 0.05 h (owner decision). Runs were sequential, wall time from `date`.
- Command (per seed, N in 42 7 99 1234 2026):
  `godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols 300`
- Run length: 300 sols is about 148,000 steps.

### Runtime
| Seed | Wall time (s) | Final pop |
| --- | --- | --- |
| 42 | 202 | 164 |
| 7 | 76 | 72 |
| 99 | 212 | 157 |
| 1234 | 198 | 142 |
| 2026 | 191 | 156 |

All runs but seed 7 exceed the plan's 90 s target (about 190 to 212 s); the cost grows with population. Per the plan this is reported to the owner, fixed_step stays 0.05 h.
Determinism check: seed 7 was run twice at 300 sols and the two outputs were identical (diff empty, table sha256 830c7d0c441823f5...). tests/test_determinism.gd covers seeds 42 and 7 at 10 sols.

### Target x seed matrix (per-seed verdicts from the run output)
Target 6 passes per seed at the provisional 2% threshold; the 4-of-5 rule also holds (5 of 5). Target 9 is checked by repeat run (above), not per seed.
| Target | 42 | 7 | 99 | 1234 | 2026 |
| --- | --- | --- | --- | --- | --- |
| 1 survival | PASS | PASS | PASS | PASS | PASS |
| 2 deaths | PASS | PASS | PASS | PASS | PASS |
| 3 no runaway growth | FAIL | FAIL | FAIL | FAIL | FAIL |
| 4 stocks bounded | FAIL | PASS | FAIL | PASS | FAIL |
| 5 power | PASS | PASS | FAIL | FAIL | FAIL |
| 6 growth limited | PASS | PASS | PASS | PASS | PASS |
| 7 mining reachable | PASS | PASS | PASS | PASS | PASS |
| 8 energy | PASS | PASS | PASS | PASS | PASS |
| 9 determinism | N/A | repeat ok (seed 7) | N/A | N/A | N/A |

### Tables and verdicts per seed
Columns: deaths and births cumulative; dead a/t/h/o/x = air/thirst/hunger/outside/other; bldg R/H/W/G/A/C = reactor/habitat/workshop/green room/archive/comms online; shorts, trips, avgE, asleep%, waitH (hours waiting for regolith + site without crew), minIce, minO2 are for the 30-sol window.

#### Seed 42
```
# station zero balance run: seed=42 sols=300 overrides=[] fixed_step=0.05 data_hash=42de63484867d0c5
# deaths and births are cumulative; shorts, trips, energy, asleep, wait, min_* are for the 30-sol window
 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2
  30   19    7    12 0/0/0/0/0                 550.0   420.0    73.6    19.1   20.0   28.0     0 2/4/1/1/0/0           2    39  54.5   10.6  438.9   45.8  261.5
  60   27   19    20 0/0/0/0/0                 700.0   540.0    97.9    56.3   30.0   42.0     0 3/6/1/2/0/0           2    81  54.3   10.7  550.3   64.1  547.1
  90   52   27    45 0/0/0/0/0                 688.4   540.0    98.7    39.8   44.0   56.0     0 4/10/1/2/0/0          2   128  56.6   10.8  471.3   67.4  688.1
 120   72   52    65 0/0/0/0/0                 846.9   660.0   101.4    72.7   58.0   70.0     0 5/14/1/3/0/0          2   194  55.9   10.6  445.8   85.7  682.3
 150   82   72    75 0/0/0/0/0                1000.0   780.0     5.7   118.1   68.0   84.0     0 6/16/1/4/0/0          2   186  57.5   10.8  536.1    1.6  839.2
 180  102   82    95 0/0/0/0/0                1000.0   780.0    66.1     3.1   82.0   84.0     0 6/20/1/4/0/0          2   274  56.7   10.6  490.4    0.0  995.9
 210  122  102   115 0/0/0/0/0                1150.0   900.0    36.0   194.3   98.0   98.0     0 7/24/1/5/0/0          2   344  57.5   10.9  523.0   14.8  948.4
 240  137  119   133 0/3/0/0/0                1292.1  1020.0    87.0   204.3  111.0  112.0     0 8/27/1/6/0/0          2   329  59.4   10.9  543.3    0.0 1123.3
 270  147  137   146 0/6/0/0/0                1299.5  1020.0   100.8   322.4  119.0  126.0     0 9/29/1/6/1/0          2   338  59.6   11.0  580.4    0.0 1292.2
 300  164  147   167 0/10/0/0/0               1450.0  1140.0     0.0   154.8  135.0  140.0     0 10/33/1/7/1/0         2   361  59.3   10.9  541.1    0.0 1227.2
targets for seed 42 (300 sols):
  T1 PASS run min pop 7 (needs >= 5), final pop 164
  T2 PASS deaths 10 (air 0 thirst 10 hunger 0 eva 0 other 0), unexplained 0
  T3 FAIL births 167, first_birth_sol 13, at_capacity 0, cooldown_violations 0, pop@30=19(<=15), pop@100=57(<=30), pop@300=164(<=60)
  T4 FAIL min O2 261.5, food 203.1, ice 0.0, ice>30 0.0; max ice/target 0.60, regolith/target 0.63
  T5 PASS demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 5 (<=10)
  T6 PASS limited 5120.3 h = 69.21% (>=2% provisional; 4 of 5 seeds), site busy 68.8%; waiting_regolith 1340.0 h, site_no_crew 3780.3 h
  T7 PASS turn_backs_air 0, exhausted 666, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2274
  T8 PASS row avg energy 54.3..59.6 (40..90), row asleep 10.6..11.0% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
RESULT FAIL (target 9 determinism: table sha256 02032b2388529913)
```

#### Seed 7
```
# station zero balance run: seed=7 sols=300 overrides=[] fixed_step=0.05 data_hash=42de63484867d0c5
# deaths and births are cumulative; shorts, trips, energy, asleep, wait, min_* are for the 30-sol window
 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2
  30   12    7     5 0/0/0/0/0                 550.0   420.0    63.7   114.7   16.0   28.0     0 2/2/1/1/0/0           2    37  54.4   10.6  306.5   45.6  261.5
  60   22   12    15 0/0/0/0/0                 700.0   540.0   132.8   191.0   26.0   28.0     0 2/4/1/2/0/0           2    67  57.9   11.0  287.2   60.9  548.0
  90   32   22    25 0/0/0/0/0                 700.0   540.0   217.8   297.2   30.0   42.0     0 3/6/1/2/0/0           2    77  60.5   11.1  114.9  128.6  698.0
 120   37   32    30 0/0/0/0/0                 700.0   540.0   266.5   349.3   35.0   42.0     0 3/7/1/2/0/0           2    88  60.3   11.0   59.7  206.6  698.0
 150   47   37    40 0/0/0/0/0                 699.5   540.0   351.3   463.2   39.0   42.0     0 3/9/1/2/0/0           2   109  60.6   10.8  185.5  221.9  695.4
 180   47   47    40 0/0/0/0/0                 700.0   540.0   361.1   385.2   41.0   42.0     0 3/9/1/2/0/0           2    71  61.2   10.8   28.8  344.5  697.9
 210   52   47    45 0/0/0/0/0                 787.2   624.1   320.2   409.2   46.0   56.0     0 4/10/1/3/0/0          2   100  60.4   10.8  161.4  316.7  694.0
 240   52   52    45 0/0/0/0/0                 850.0   660.0   401.6   521.6   46.0   56.0     0 4/10/1/3/0/0          2   117  58.5   10.7    0.0  319.2  787.3
 270   52   52    45 0/0/0/0/0                 850.0   660.0   394.1   521.6   46.0   56.0     0 4/10/1/3/0/0          2    83  60.1   10.6    0.0  354.4  848.2
 300   72   52    65 0/0/0/0/0                 850.0   660.0   268.6   171.0   60.0   70.0     0 5/14/1/3/0/0          2   104  59.9   10.8  261.0  265.3  846.8
targets for seed 7 (300 sols):
  T1 PASS run min pop 7 (needs >= 5), final pop 72
  T2 PASS deaths 0 (air 0 thirst 0 hunger 0 eva 0 other 0), unexplained 0
  T3 FAIL births 65, first_birth_sol 19, at_capacity 0, cooldown_violations 0, pop@30=12(<=15), pop@100=32(<=30), pop@300=72(<=60)
  T4 PASS min O2 261.5, food 203.1, ice 45.6, ice>30 60.9; max ice/target 1.02, regolith/target 1.39
  T5 PASS demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 10 (<=10)
  T6 PASS limited 1404.9 h = 18.99% (>=2% provisional; 4 of 5 seeds), site busy 26.9%; waiting_regolith 0.0 h, site_no_crew 1404.9 h
  T7 PASS turn_backs_air 0, exhausted 242, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 853
  T8 PASS row avg energy 54.4..61.2 (40..90), row asleep 10.6..11.1% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
RESULT FAIL (target 9 determinism: table sha256 830c7d0c441823f5)
```

#### Seed 99
```
# station zero balance run: seed=99 sols=300 overrides=[] fixed_step=0.05 data_hash=42de63484867d0c5
# deaths and births are cumulative; shorts, trips, energy, asleep, wait, min_* are for the 30-sol window
 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2
  30   10    7     3 0/0/0/0/0                 666.9   506.7    48.6    26.0   20.0   28.0     0 2/2/1/2/0/0           2    28  54.4   10.5  521.8   43.1  262.5
  60   29   10    22 0/0/0/0/0                 850.0   660.0    84.7    61.1   34.0   42.0     0 3/6/1/3/0/0           2    78  56.7   11.2  395.0   42.1  667.0
  90   62   29    55 0/0/0/0/0                 850.0   660.0   119.4    69.5   54.0   56.0     0 4/12/1/3/0/0          2   155  58.9   10.9  369.0   84.7  847.1
 120   77   62    70 0/0/0/0/0                1000.0   780.0   110.4   245.0   70.0   84.0     0 6/15/1/4/0/1          2   239  59.2   11.1  535.5   88.0  840.4
 150   97   77    90 0/0/0/0/0                1149.9   900.0   120.6   108.7   86.0   98.0     0 7/19/1/5/0/1          2   235  59.3   11.0  535.7   63.6  997.6
 180  107   97   100 0/0/0/0/0                1147.7   900.0    22.4   178.8   94.0  112.0     0 8/21/2/5/0/1          2   208  58.7   10.9  610.3    0.0 1147.0
 210  132  107   125 0/0/0/0/0                1102.8   900.0   102.0   191.1  111.0  126.0     0 9/26/2/5/0/1          2   378  59.0   11.1  507.3   14.9 1102.2
 240  142  132   140 0/5/0/0/0                1300.0  1020.0    19.7   125.7  124.0  140.0     0 10/28/2/6/0/2         2   311  58.4   10.9  574.0    0.0 1087.7
 270  147  137   158 0/18/0/0/0               1450.0  1140.0     0.3   216.2  131.0  140.0     0 10/29/2/7/0/2         2   299  55.5   10.5  586.6    0.0 1295.6
 300  157  146   172 0/22/0/0/0               1450.0  1140.0    65.2   119.1  140.0  154.0     0 11/31/2/7/0/3         2   366  57.8   10.8  575.6    0.0 1445.6
targets for seed 99 (300 sols):
  T1 PASS run min pop 7 (needs >= 5), final pop 157
  T2 PASS deaths 22 (air 0 thirst 22 hunger 0 eva 0 other 0), unexplained 0
  T3 FAIL births 172, first_birth_sol 26, at_capacity 0, cooldown_violations 0, pop@30=10(<=15), pop@100=72(<=30), pop@300=157(<=60)
  T4 FAIL min O2 262.5, food 203.1, ice 0.0, ice>30 0.0; max ice/target 0.60, regolith/target 0.84
  T5 FAIL demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 11 (<=10)
  T6 PASS limited 5210.4 h = 70.43% (>=2% provisional; 4 of 5 seeds), site busy 78.7%; waiting_regolith 820.0 h, site_no_crew 4390.4 h
  T7 PASS turn_backs_air 0, exhausted 645, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2297
  T8 PASS row avg energy 54.4..59.3 (40..90), row asleep 10.5..11.2% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
RESULT FAIL (target 9 determinism: table sha256 0e3e83a7108140ef)
```

#### Seed 1234
```
# station zero balance run: seed=1234 sols=300 overrides=[] fixed_step=0.05 data_hash=42de63484867d0c5
# deaths and births are cumulative; shorts, trips, energy, asleep, wait, min_* are for the 30-sol window
 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2
  30   12    7     5 0/0/0/0/0                 677.3   515.0    72.3    38.8   18.0   28.0     0 2/2/1/2/0/0           2    28  53.8   10.6  523.1   50.4  262.5
  60   27   12    20 0/0/0/0/0                 700.0   540.0   109.0    54.9   29.0   42.0     0 3/5/1/2/0/0           2    81  55.9   10.8  319.3   70.2  677.4
  90   57   27    50 0/0/0/0/0                 850.0   660.0   195.7   102.6   51.0   56.0     0 4/11/1/3/0/0          2   182  58.4   11.1  415.7   94.2  693.7
 120   82   57    75 0/0/0/0/0                 823.6   660.0   174.9   233.9   66.0   70.0     0 5/16/1/3/0/0          2   223  57.2   10.8  422.9  153.4  823.6
 150  102   82    95 0/0/0/0/0                 996.5   780.0   167.1    73.6   82.0   98.0     0 7/20/1/4/0/0          2   254  58.3   10.9  416.5   97.3  812.4
 180  107  102   100 0/0/0/0/0                1150.0   900.0   716.9   776.2   87.0   98.0     0 7/21/1/5/0/0          2   391  58.1   11.2  143.2  118.9  932.0
 210  112  107   105 0/0/0/0/0                1150.0   900.0   666.6   792.4   90.0   98.0     0 7/22/1/5/0/0          2   232  57.0   10.4   42.8  553.7 1147.0
 240  132  112   125 0/0/0/0/0                1282.7  1020.0   345.6   427.3  108.0  112.0     0 8/26/1/6/0/0          2   270  59.0   10.8  408.9  345.6 1119.5
 270  142  132   135 0/0/0/0/0                1300.0  1020.0   815.2   911.3  112.0  126.0     0 9/28/1/6/0/0          2   441  59.6   11.1  128.7  210.1 1282.8
 300  142  142   135 0/0/0/0/0                1300.0  1020.0  1014.2   911.3  112.0  126.0     0 9/28/1/6/0/0          2   292  60.7   10.9    0.0  694.6 1296.1
targets for seed 1234 (300 sols):
  T1 PASS run min pop 7 (needs >= 5), final pop 142
  T2 PASS deaths 0 (air 0 thirst 0 hunger 0 eva 0 other 0), unexplained 0
  T3 FAIL births 135, first_birth_sol 21, at_capacity 0, cooldown_violations 0, pop@30=12(<=15), pop@100=65(<=30), pop@300=142(<=60)
  T4 PASS min O2 262.5, food 203.1, ice 50.4, ice>30 70.2; max ice/target 0.96, regolith/target 1.37
  T5 FAIL demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 11 (<=10)
  T6 PASS limited 2821.1 h = 38.13% (>=2% provisional; 4 of 5 seeds), site busy 48.4%; waiting_regolith 325.0 h, site_no_crew 2496.1 h
  T7 PASS turn_backs_air 0, exhausted 646, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2394
  T8 PASS row avg energy 53.8..60.7 (40..90), row asleep 10.4..11.2% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
RESULT FAIL (target 9 determinism: table sha256 bca6eb2ca93ba0c1)
```

#### Seed 2026
```
# station zero balance run: seed=2026 sols=300 overrides=[] fixed_step=0.05 data_hash=42de63484867d0c5
# deaths and births are cumulative; shorts, trips, energy, asleep, wait, min_* are for the 30-sol window
 sol  pop  min birth dead a/t/h/o/x           oxygen    food     ice   regol   dmnd   supp short bldg R/H/W/G/A/C  reach trips  avgE asleep%  waitH minIce  minO2
  30   12    7     5 0/0/0/0/0                 550.0   420.0    72.1    63.9   16.0   28.0     0 2/2/1/1/0/0           2    33  54.3   10.6  472.6   64.8  261.5
  60   26   12    19 0/0/0/0/0                 524.7   420.0   131.3   116.1   25.0   28.0     0 2/5/1/1/1/0           2    74  56.6   11.0  412.8   15.1  524.0
  90   37   26    30 0/0/0/0/0                 700.0   540.0   153.7   149.1   37.0   42.0     0 3/7/1/2/1/0           2    99  56.3   10.9  295.3   76.5  517.1
 120   62   37    55 0/0/0/0/0                 850.0   660.0   121.5    55.0   56.0   56.0     0 4/12/1/3/1/0          2   156  55.7   10.9  342.3  105.4  693.3
 150   78   62    71 0/0/0/0/0                 999.3   780.0    62.6   187.7   70.0   84.0     0 6/16/1/4/1/0          2   246  55.9   10.9  425.1   62.6  841.8
 180  106   78   101 0/2/0/0/0                 988.3   780.0    22.9   123.1   85.0   98.0     0 7/21/1/4/1/0          2   283  56.9   10.8  474.6    0.0  987.5
 210  112  106   107 0/2/0/0/0                1150.0   900.0   635.3   684.1   92.0   98.0     0 7/22/1/5/1/0          2   411  57.8   11.1  127.1   17.5  861.1
 240  117  112   112 0/2/0/0/0                1150.0   900.0   659.3   572.3   95.0  112.0     0 8/23/1/5/1/0          2   215  60.2   10.9   77.4  579.8 1147.3
 270  132  117   127 0/2/0/0/0                1257.9  1020.0   282.5   276.9  114.0  126.0     0 9/26/2/6/1/0          2   295  58.0   10.7  530.7  279.4 1118.2
 300  156  132   154 0/5/0/0/0                1299.2  1020.0     0.0   126.1  129.0  140.0     0 10/31/2/6/1/0         2   332  58.1   10.8  514.7    0.0 1258.0
targets for seed 2026 (300 sols):
  T1 PASS run min pop 7 (needs >= 5), final pop 156
  T2 PASS deaths 5 (air 0 thirst 5 hunger 0 eva 0 other 0), unexplained 0
  T3 FAIL births 154, first_birth_sol 18, at_capacity 0, cooldown_violations 0, pop@30=12(<=15), pop@100=47(<=30), pop@300=156(<=60)
  T4 FAIL min O2 261.5, food 203.1, ice 0.0, ice>30 0.0; max ice/target 0.90, regolith/target 1.48
  T5 FAIL demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 13 (<=10)
  T6 PASS limited 3672.4 h = 49.64% (>=2% provisional; 4 of 5 seeds), site busy 59.3%; waiting_regolith 505.0 h, site_no_crew 3167.4 h
  T7 PASS turn_backs_air 0, exhausted 589, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2144
  T8 PASS row avg energy 54.3..60.2 (40..90), row asleep 10.6..11.1% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
RESULT FAIL (target 9 determinism: table sha256 2645033a417ec400)
```

## Run 2: targets updated by owner decisions (no data changes)

Commit eb26832. The targets follow the owner decisions in task-1-plan.md: no population caps, ice running dry is pressure, and the first new reactor is due by sol 15. All data/ values are unchanged from the baseline.

Command: `godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols 300` (five seeds run in parallel on 4 cores).

| Seed | Wall time | Result | Final pop | Thirst deaths | Ice ran dry |
|---|---|---|---|---|---|
| 42 | 221 s | PASS | 164 | 10 | yes |
| 7 | 97 s | PASS | 72 | 0 | no |
| 99 | 232 s | PASS | 157 | 22 | yes |
| 1234 | 219 s | PASS | 142 | 0 | no |
| 2026 | 210 s | PASS | 156 | 5 | yes |

Step 11 (the balance loop) needed no data change: all targets pass on all five seeds.

### Verdicts per seed

Seed 42:
```
  T1 PASS run min pop 7 (needs >= 5), final pop 164
  T2 PASS deaths 10 (air 0 thirst 10 hunger 0 eva 0 other 0), unexplained 0
  T3 PASS births 167, first_birth_sol 13, at_capacity 0, cooldown_violations 0, pop@30=19, pop@100=57, pop@300=164
  T4 PASS min O2 261.5, food 203.1; ice ran dry (pressure): min ice 0.0, ice>30 0.0, thirst deaths 10; max ice/target 0.60, regolith/target 0.63
  T5 PASS demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 5 (<=15)
  T6 PASS limited 5120.3 h = 69.21% (>=2% provisional; 4 of 5 seeds), site busy 68.8%; waiting_regolith 1340.0 h, site_no_crew 3780.3 h
  T7 PASS turn_backs_air 0, exhausted 666, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2274
  T8 PASS row avg energy 54.3..59.6 (40..90), row asleep 10.6..11.0% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
RESULT PASS (target 9 determinism: table sha256 02032b2388529913)
```
Seed 7:
```
  T1 PASS run min pop 7 (needs >= 5), final pop 72
  T2 PASS deaths 0 (air 0 thirst 0 hunger 0 eva 0 other 0), unexplained 0
  T3 PASS births 65, first_birth_sol 19, at_capacity 0, cooldown_violations 0, pop@30=12, pop@100=32, pop@300=72
  T4 PASS min O2 261.5, food 203.1; ice never ran dry: min ice 45.6, ice>30 60.9, thirst deaths 0; max ice/target 1.02, regolith/target 1.39
  T5 PASS demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 10 (<=15)
  T6 PASS limited 1404.9 h = 18.99% (>=2% provisional; 4 of 5 seeds), site busy 26.9%; waiting_regolith 0.0 h, site_no_crew 1404.9 h
  T7 PASS turn_backs_air 0, exhausted 242, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 853
  T8 PASS row avg energy 54.4..61.2 (40..90), row asleep 10.6..11.1% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
RESULT PASS (target 9 determinism: table sha256 830c7d0c441823f5)
```
Seed 99:
```
  T1 PASS run min pop 7 (needs >= 5), final pop 157
  T2 PASS deaths 22 (air 0 thirst 22 hunger 0 eva 0 other 0), unexplained 0
  T3 PASS births 172, first_birth_sol 26, at_capacity 0, cooldown_violations 0, pop@30=10, pop@100=72, pop@300=157
  T4 PASS min O2 262.5, food 203.1; ice ran dry (pressure): min ice 0.0, ice>30 0.0, thirst deaths 22; max ice/target 0.60, regolith/target 0.84
  T5 PASS demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 11 (<=15)
  T6 PASS limited 5210.4 h = 70.43% (>=2% provisional; 4 of 5 seeds), site busy 78.7%; waiting_regolith 820.0 h, site_no_crew 4390.4 h
  T7 PASS turn_backs_air 0, exhausted 645, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2297
  T8 PASS row avg energy 54.4..59.3 (40..90), row asleep 10.5..11.2% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
RESULT PASS (target 9 determinism: table sha256 0e3e83a7108140ef)
```
Seed 1234:
```
  T1 PASS run min pop 7 (needs >= 5), final pop 142
  T2 PASS deaths 0 (air 0 thirst 0 hunger 0 eva 0 other 0), unexplained 0
  T3 PASS births 135, first_birth_sol 21, at_capacity 0, cooldown_violations 0, pop@30=12, pop@100=65, pop@300=142
  T4 PASS min O2 262.5, food 203.1; ice never ran dry: min ice 50.4, ice>30 70.2, thirst deaths 0; max ice/target 0.96, regolith/target 1.37
  T5 PASS demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 11 (<=15)
  T6 PASS limited 2821.1 h = 38.13% (>=2% provisional; 4 of 5 seeds), site busy 48.4%; waiting_regolith 325.0 h, site_no_crew 2496.1 h
  T7 PASS turn_backs_air 0, exhausted 646, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2394
  T8 PASS row avg energy 53.8..60.7 (40..90), row asleep 10.4..11.2% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
RESULT PASS (target 9 determinism: table sha256 bca6eb2ca93ba0c1)
```
Seed 2026:
```
  T1 PASS run min pop 7 (needs >= 5), final pop 156
  T2 PASS deaths 5 (air 0 thirst 5 hunger 0 eva 0 other 0), unexplained 0
  T3 PASS births 154, first_birth_sol 18, at_capacity 0, cooldown_violations 0, pop@30=12, pop@100=47, pop@300=156
  T4 PASS min O2 261.5, food 203.1; ice ran dry (pressure): min ice 0.0, ice>30 0.0, thirst deaths 5; max ice/target 0.90, regolith/target 1.48
  T5 PASS demand>supply 0.00% of steps (<=10), max shorts/sol 0 (<=2), max offline 0.0 h (<=24.7), first new reactor sol 13 (<=15)
  T6 PASS limited 3672.4 h = 49.64% (>=2% provisional; 4 of 5 seeds), site busy 59.3%; waiting_regolith 505.0 h, site_no_crew 3167.4 h
  T7 PASS turn_backs_air 0, exhausted 589, reachable>=2 at 100.0% of 300 sol samples (>=95), trips 2144
  T8 PASS row avg energy 54.3..60.2 (40..90), row asleep 10.6..11.1% (5..30), max sleep 8.8 h (<=18)
  T9 N/A  checked by repeating the run and by tests/test_determinism.gd (compare the table sha256)
RESULT PASS (target 9 determinism: table sha256 2645033a417ec400)
```
