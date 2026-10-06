# Task 4 step 5: relationships calibration probe results

Measured numbers only. Nothing was tuned: `data/` and `sim/` were not touched, no shipped value changed. New code: `tools/relationships_probe.gd`. Raw outputs (per-sol CSV and summary JSON per seed and run, text reports, hash and cost runs) are in `docs/balance/task-4-calibration-data/` (it has a `.gdignore`). Spec: `docs/specs/relationships.md` revision 4, section 13. Godot 4.5.stable, `data_hash` `b9cdbe3c25a03345` (shipped data, all runs; the pull runs override two keys through the SimData cache only).

## Commands

```
# 15 runs: seeds 42 7 99 1234 2026 x pull shipped | friend | both, 300 sols, 4 processes in parallel
godot --headless --path station-zero --script res://tools/relationships_probe.gd -- --seed N --sols 300 --pull P --out <abs>/docs/balance/task-4-calibration-data
# replay: balance_lib.run (the balance table) with the same overrides; digest must equal the probe's
godot --headless --path station-zero --script res://tools/relationships_probe.gd -- --hash --seed N --sols 300 --pull P
# item 6, run alone
godot --headless --path station-zero --script res://tools/relationships_probe.gd -- --sample60 --seed 42     (and 7)
# items 9 and 10, run alone (module on world A against module off world B, lockstep)
godot --headless --path station-zero --script res://tools/relationships_probe.gd -- --cost --seed 42 --sols 300 --pull shipped     (also 42 both, 7 shipped)
# tables
godot --headless --path station-zero --script res://tools/relationships_probe.gd -- --tables docs/balance/task-4-calibration-data
godot --headless --path station-zero --script res://tests/relationships_hash_proof.gd
godot --headless --path station-zero --script res://tools/relationships_profile.gd -- --ticks 100
```
Pull runs: `shipped` = both pulls 0.0; `friend` = `effects.friend_pull` 0.25 only (lonely 0.0); `both` = friend 0.25 and `effects.lonely_pull` 0.15 (values read from `balance.probe_friend_pull` and `probe_lonely_pull`).

## How it observes, and checks that it did not disturb the run

After every step the probe reads the world; it writes nothing. Log lines are counted by scanning the entries logged in the step just taken. Togetherness uses the probe's own grouping written from spec section 2. Definitions used where the spec leaves room: "lines" means capped-kind lines (friends, found_friend, close, close_crew, drifted), grief counted separately; "sols 20 to 300" is the 280 sol intervals ending at boundaries 21 to 300; "dropped under 5 percent" is dropped / (capped-kind lines logged + dropped), with dropped / `lines_capped` also printed (both are 0 on every run); friendship ages and "sols to first grown friend" have sol resolution (read at sol boundaries); "first grown friend" excludes the kin pair.

**Replay check: PASS on all 15 runs.** An independent `balance_lib.run` of the same seed and overrides ends with the same digest (sha256 of pop, births, deaths, age history and all of `stats.relationships`) as the probe run, so the observer did not change the run. `tests/relationships_hash_proof.gd` (shipped values): all five seeds MATCH on both checks (drop `web`: the Task 3 hashes da166c4f8b202820, 30c53f90949d979b, 54ad1e15b934bf9a, 7052c92936a75157, 67e3dcf057200eb9; drop `web` and `age`: the Task 1 hashes 02032b23..., 830c7d0c..., 0e3e83a7..., bca6eb2c..., 2645033a...). Age crossings in the shipped run equal the spec section 11 list: settled at 67, 58, 54, 65, 53; fell back at 213 (seed 42) and 174 (seed 99).

## Targets against measurements (shipped run, 300 sols; section 13 targets)

| target (E) | seed 42 | seed 7 | seed 99 | seed 1234 | seed 2026 | verdict |
|---|---|---|---|---|---|---|
| first grown friendship before sol 20 (`first_friendship_sol`) | 45 | 34 | 68 | 41 | 54 | FAIL on all 5; later than sol 20 by 25, 14, 48, 21, 34 sols. Target error, see below |
| first relationship line before sol 30 | 21 | 16 | 19 | 21 | 14 | PASS. But the first line is a crew line on every seed (drifted on 42, 99, 1234; close_crew on 7, 2026); the first `friends` or `found_friend` line is at sol 45, 34, 68, 41, 54 |
| first Mars-born friendship within 15 sols of the first birth (first birth / first Mars-born friendship / gap) | 13 / 45 / 32 | 19 / 34 / 15 | 26 / 68 / 42 | 21 / 41 / 20 | 18 / 54 / 36 | FAIL on 4 seeds (over by 17, 27, 5, 21 sols); seed 7 passes at exactly 15 |
| `lonely_share` at 300 in 0.05 to 0.35 | 0.396 | 0.028 | 0.293 | 0.120 | 0.365 | FAIL on 3: seed 42 above the upper bound by 0.046, seed 2026 above by 0.015, seed 7 below the lower bound by 0.022 |
| `friends_mean` at 300 in 1 to 12 | 2.01 | 12.67 | 1.78 | 7.56 | 1.28 | FAIL on seed 7: above 12 by 0.67 |
| dropped events under 5% of capped-kind events | 0 of 115 | 0 of 59 | 0 of 120 | 0 of 136 | 0 of 113 | PASS (`lines_capped` is only 3, 0, 0, 2, 0: the cap almost never binds) |
| at least 1 capped-kind line per 5 sols, sols 20 to 300 | 2.05 | 1.04 | 2.12 | 2.43 | 2.00 | PASS (seed 7 by 0.04). 5-sol blocks with no line: 10, 22, 10, 9, 13 of 56 |
| warmest third has more friends than coldest third | 3.91 vs 0.59 | 18.75 vs 7.54 | 3.06 vs 0.63 | 10.72 vs 4.23 | 1.92 vs 0.83 | PASS on every seed |
| tick under 1 ms median at pop 160 | | | | | | FAIL: 5.97 ms median at pop above 120 (seed 42, max pop 167); see item 9 |
| pull only: loneliest-third newborn friend count with both terms not below the shipped run | 0.74 vs 0.00 | 0.32 vs 0.92 | 0.55 vs 0.26 | 0.00 vs 0.80 | 5.92 vs 0.00 | FAIL on seeds 7 (below by 0.60) and 1234 (below by 0.80); cohorts differ in size because the runs diverge (see item 7) |

**Target error: "first grown friendship before sol 20".** Measured `first_mars_born_friendship_sol` per seed in the shipped run: 45 (first birth 13), 34 (19), 68 (26), 41 (21), 54 (18). On all five seeds the first birth is later than the spec note's "about sol 8" (13 to 26), so by the note's own rule it cannot be met whatever the tuning; the probe reports a target error, not a tuning signal. Facts that bear on restating it: the first grown friendship is always Mars-born on every seed and run (`first_friendship_sol` equals `first_mars_born_friendship_sol` in all 15 runs); it comes 15 to 42 sols after the first birth on the shipped run (gaps 32, 15, 42, 20, 36); the earliest first grown friendship in any of the 15 runs is sol 20 (seed 42, both pull runs, first birth 9), which still misses "before sol 20" by the strict reading.

**Personality (item 3).** Warmest third has more friends on all 15 runs. Shipped, restless top third of friend pairs against the bottom third (mean friendship age at sol 300): 16.6 vs 48.8, 47.8 vs 75.3, 13.9 vs 30.2, 17.2 vs 37.2, 14.5 vs 39.4 sols; the more restless pairs have the younger friendships on all five seeds, as the spec intends. In the pull runs the direction reverses on two runs (seed 7 friend 45.7 vs 38.0; seed 7 both 37.7 vs 35.1), same table below.

**Work check (item 4).** Beings split by their share of awake ticks spent on the site or mining; in each half, warmest third against coldest third (mean friend count at 300). Shipped, top (work-heavy) half: 6.07 vs 1.22, 15.83 vs 7.92, 3.38 vs 1.38, 8.96 vs 3.78, 2.38 vs 1.04. Warmth has an effect among the work-heavy half on 5 of 5 seeds, so the spec's trigger ("no effect on 3 or more seeds") is not met and no `grow.work_rate` run was made. Caution: the work-heavy half spends only about 3 percent of awake ticks on site or mining (mean share 0.034 top half, 0.016 bottom), so the split barely separates work-heavy beings from the rest. Pull runs: warm beats cold in both halves on every run.

**Hours together (item 5).** Median hours per sol together over pairs alive at the end (room or work, 1-h sample): friend pairs 1.92, 2.66, 1.70, 2.08, 1.74; non-friend pairs that were ever co-present 0.92, 1.68, 0.83, 1.15, 0.82. Spec section 6 puts the balance point of a typical pair at about 3.5 h and roommates at about 10 h; measured friend pairs are below 3.5 h in the median on all five seeds (the friend set includes seeded kin and crew pairs, which start above the line and decay slowly while close).

**Kinless newborns (item 8).** The share of births with no living recorded parent at the next tick is 0 of 167, 65, 172, 135, 154 births (every run, every pull): `rng.pick(here)` always picks a parent and parents are alive at the next tick in these runs. No kinless newborn existed, so the kinless median sols to a first friend is not measurable. Kin newborns (all of them): median sols from birth to the first grown friendship 28, 25, 29, 26, 29 on the shipped run (resolved 128 of 167, 45 of 65, 133 of 172, 131 of 135, 120 of 154; the rest had none by sol 300). Newborns after sol 100 that were alive at 300 and had zero friends: 38 of 111, 1 of 40, 23 of 95, 11 of 75, 36 of 109.

**Log (item 10).** Relationship lines are 9.6, 13.0, 10.3, 12.2, 10.8 percent of all log entries logged over the shipped runs (grief included, 5 to 10 grief lines on three seeds). Oldest entry still in the 500-entry log at sol 300: seed 42 sol 201 with the module, sol 193 without (seed 42 cost run, module off world); seed 7 sol 0 both ways (log holds 454 with the module, 395 without, under the cap). Seed 42 with both pulls: sol 151 with, 193 without (the module-off world there runs without the pull, so it is not the same colony).

**Item 6, 1-h sample against per-step count** (sols 1 to 60, per-step = 0.05 h steps). Seed 42: 348 pairs; relative difference per pair over the window median 0.0215, 90th percentile 0.0714 (pairs with at least 10 step-hours: median 0.0193, p90 0.0554); total together hours 20,296 per step against 20,264 sampled (ratio 0.9984). Seed 7: median 0.0145, p90 0.0559, ratio 0.9977. Per pair per sol, the sample is poor: median 0.1111 (seed 42) and 0.0753 (seed 7), p90 1.0; it averages out over many sols.

**Item 9, cost** (cost mode, run alone; tick cost is `Relationships.last_tick_ms`; world A with the module, world B without, stepped in lockstep so two worlds share the machine; this host is noisy, spread about 10 percent).

| seed 42 shipped, max pop 167 | ticks | tick median (us) | p95 | max | stored pairs median / max | step mean with / without module (us) |
|---|---|---|---|---|---|---|
| pop <= 40 | 1831 | 479 | 967 | 6304 | 132 / 364 | 294 / 264 |
| pop 41 to 80 | 1680 | 1884 | 3156 | 9546 | 821 / 1275 | 869 / 763 |
| pop 81 to 120 | 1718 | 3464 | 5814 | 13304 | 1462 / 2385 | 1569 / 1378 |
| pop above 120 | 2168 | 5968 | 9080 | 19810 | 2876 / 4389 | 2479 / 2154 |

Seed 7 shipped (max pop 72): pop <= 40 median 481 us, pop 41 to 80 median 1656 us (max 8574). Seed 42 with both pulls: pop above 120 median 5474 us (the step with/without comparison there is not valid: the pull is on world A only, so B is a different colony). The tick median is above the 1 ms target from about pop 41 up on every run. `tools/relationships_profile.gd` (padded world, pop 159, 5,278 pairs) run today: whole tick median 4.17 ms, max 9.0 ms; decay walk 3.22 ms, growth loop 0.72 ms, info/deaths/births 0.42 ms, grouping 0.13 ms; reading (per sol) 2.29 ms. The growth/decay split in a real run was not measured separately.

## Pull runs: ages, population, hashes (item 7)

Pull values 0.25 and 0.15 change the table hash on every seed (expected, spec section 12). Balance-table sha256 (first 16 hex, with the `web` column), from `--hash`:

| seed | shipped | friend 0.25 | friend 0.25 + lonely 0.15 |
|---|---|---|---|
| 42 | a96b8a9562fd75d0 | dec3f38001d58ed1 | 55cee0cc751cc267 |
| 7 | a4968e2fcc48ec36 | 271cb8b5233a4b80 | 669a7afa364939b1 |
| 99 | 2210719cf48d8612 | 8ae5b8e58d4c4016 | 817b1e147fb8cba1 |
| 1234 | 19437e397d1dff88 | 79b893414b124430 | 58577e9b5d605717 |
| 2026 | 6e7fe68477161196 | a1a1588183ee20f2 | c4c55a900a72101b |

All 10 pull hashes differ from their shipped hash. Ages and population at sol 300 (S = settlement, L = landing; cause in brackets):

| seed | shipped | friend | friend + lonely |
|---|---|---|---|
| 42 | S@67 L@213(ice); pop 164 | S@55; pop 117 | S@55; pop 154 |
| 7 | S@58; pop 72 | S@61 L@260(ice); pop 162 | S@61 L@272(ice); pop 167 |
| 99 | S@54 L@174(ice); pop 157 | S@66; pop 142 | S@66; pop 97 |
| 1234 | S@65; pop 142 | S@112; pop 52 | S@112 L@254(ice); pop 107 |
| 2026 | S@53; pop 156 | S@63; pop 144 | S@63; pop 77 |

Settlement sols move on every seed under either pull (settle sols: shipped 67, 58, 54, 65, 53; friend 55, 61, 66, 112, 63; both 55, 61, 66, 112, 63). All stay inside the ages balance target's 40 to 150 window (T10 PASS on all 15 balance-table runs). Age changes: shipped 2, 1, 2, 1, 1; friend 1, 2, 1, 1, 1; both 1, 2, 1, 2, 1. Population at 300 ranges 52 to 167 with the pulls on and 72 to 164 shipped; the spread is run-to-run divergence (the pull changes room choice, so every later draw differs), not an effect these single runs can attribute to the pull.

Loneliest-third newborn friend counts (beings born after sol 100, alive at 300; mean friends of the lowest third; n of the cohort in brackets):

| seed | shipped | friend 0.25 | friend + lonely |
|---|---|---|---|
| 42 | 0.00 (111) | 2.31 (41) | 0.74 (82) |
| 7 | 0.92 (40) | 0.00 (115) | 0.32 (115) |
| 99 | 0.26 (95) | 0.49 (105) | 0.55 (60) |
| 1234 | 0.80 (75) | 25.33 (20) | 0.00 (77) |
| 2026 | 0.00 (109) | 0.00 (108) | 5.92 (41) |

With both terms the loneliest third is not below shipped on seeds 42, 99, 2026 and is below on 7 and 1234. Other pull-run effects measured: `friends_mean` at 300 leaves the 1 to 12 band on seed 1234 (friend only, 37.27) and seed 2026 (both, 16.03), and `lonely_share` at 300 leaves its band on 7, 1234, 2026 (friend only: 0.420, 0.000, 0.382) and 1234, 2026 (both: 0.439, 0.013). Grown-friend counts of 25 to 40 per being on one seed show the friend pull can saturate a colony (seed 1234, friend only, pop 52). One run per seed and setting, with chaotic divergence between settings: these are single trajectories, not effect sizes.

## Per seed and run tables (generated by `--tables`)


### Run: shipped

**Item 1: firsts and lines**

| seed | first birth | first_friendship_sol | first_mars_born_friendship_sol | first rel line (non-grief) | friends | found_friend | close | close_crew | drifted | grief | capped | dropped | stale | formed | max lines/sol | mean lines/sol 20-299 | lines per 5 sols 20-299 | zero 5-sol blocks |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 42 | 13 | 45 | 45 | 21 (21) | 27 | 81 | 4 | 0 | 3 | 5 | 3 | 0 | 0 | 566 | 3 | 0.411 | 2.05 | 10 of 56 |
| 7 | 19 | 34 | 34 | 16 (16) | 5 | 42 | 8 | 1 | 3 | 0 | 0 | 0 | 0 | 929 | 3 | 0.207 | 1.04 | 22 of 56 |
| 99 | 26 | 68 | 68 | 19 (19) | 23 | 92 | 2 | 0 | 3 | 10 | 0 | 0 | 0 | 452 | 3 | 0.425 | 2.12 | 10 of 56 |
| 1234 | 21 | 41 | 41 | 21 (21) | 17 | 104 | 11 | 1 | 3 | 0 | 2 | 0 | 0 | 1408 | 3 | 0.486 | 2.43 | 9 of 56 |
| 2026 | 18 | 54 | 54 | 14 (14) | 19 | 89 | 1 | 1 | 3 | 5 | 0 | 0 | 1 | 509 | 3 | 0.400 | 2.00 | 13 of 56 |

**Item 2: trust readings (web / second / lonely / friends_mean; parts of size 3+ at the last sol)**

| seed | sol 30 | sol 60 | sol 100 | sol 150 | sol 200 | sol 300 | web parts >= 3 at 300 |
|---|---|---|---|---|---|---|---|
| 42 | 1.00 / 0.00 / 0.00 / 3.05 | 0.81 / 0.11 / 0.07 / 2.15 | 0.77 / 0.04 / 0.12 / 1.86 | 0.65 / 0.02 / 0.21 / 1.78 | 0.52 / 0.03 / 0.29 / 1.57 | 0.51 / 0.02 / 0.40 / 2.01 | 2 |
| 7 | 1.00 / 0.00 / 0.00 / 4.17 | 0.91 / 0.09 / 0.00 / 2.55 | 0.88 / 0.06 / 0.06 / 3.25 | 0.89 / 0.00 / 0.11 / 4.30 | 0.91 / 0.00 / 0.09 / 9.96 | 0.97 / 0.00 / 0.03 / 12.67 | 1 |
| 99 | 1.00 / 0.00 / 0.00 / 3.80 | 0.66 / 0.24 / 0.03 / 2.00 | 0.62 / 0.06 / 0.14 / 1.61 | 0.28 / 0.06 / 0.27 / 1.15 | 0.49 / 0.04 / 0.34 / 1.33 | 0.57 / 0.02 / 0.29 / 1.78 | 5 |
| 1234 | 1.00 / 0.00 / 0.00 / 4.00 | 0.89 / 0.00 / 0.11 / 2.07 | 0.63 / 0.06 / 0.11 / 2.25 | 0.57 / 0.03 / 0.25 / 2.43 | 0.70 / 0.02 / 0.25 / 3.88 | 0.87 / 0.01 / 0.12 / 7.56 | 1 |
| 2026 | 1.00 / 0.00 / 0.00 / 4.33 | 0.92 / 0.08 / 0.00 / 2.15 | 0.45 / 0.11 / 0.15 / 1.45 | 0.50 / 0.10 / 0.29 / 1.56 | 0.63 / 0.05 / 0.29 / 1.94 | 0.35 / 0.05 / 0.37 / 1.28 | 6 |

**Items 3 and 4: personality (mean friend count at sol 300; warmest third / coldest third)**

| seed | alive | all: warm / cold | top-half work share: warm / cold | bottom-half work share: warm / cold | work share mean top / bottom | bond age, restless top / bottom third (all friendships) | (grown only) |
|---|---|---|---|---|---|---|---|
| 42 | 164 | 3.91 / 0.59 | 6.07 / 1.22 | 1.59 / 0.37 | 0.034 / 0.016 | 16.6 / 48.8 sols (n 165) | 17.2 / 48.5 sols (n 145) |
| 7 | 72 | 18.75 / 7.54 | 15.83 / 7.92 | 17.08 / 7.75 | 0.037 / 0.012 | 47.8 / 75.3 sols (n 456) | 46.6 / 76.2 sols (n 425) |
| 99 | 157 | 3.06 / 0.63 | 3.38 / 1.38 | 2.58 / 0.42 | 0.032 / 0.017 | 13.9 / 30.2 sols (n 140) | 14.1 / 25.4 sols (n 123) |
| 1234 | 142 | 10.72 / 4.23 | 8.96 / 3.78 | 13.61 / 4.57 | 0.033 / 0.021 | 17.2 / 37.2 sols (n 537) | 16.0 / 33.3 sols (n 527) |
| 2026 | 156 | 1.92 / 0.83 | 2.38 / 1.04 | 1.42 / 0.62 | 0.034 / 0.019 | 14.5 / 39.4 sols (n 100) | 13.1 / 31.6 sols (n 74) |

**Item 5: hours together per sol (median over pairs alive at the end; friend pairs vs non-friend pairs)**

| seed | friend pairs | friend median h/sol | non-friend co-present pairs | their median | all non-friend pairs | their median |
|---|---|---|---|---|---|---|
| 42 | 165 | 1.92 | 12568 | 0.92 | 13201 | 0.89 |
| 7 | 456 | 2.66 | 1480 | 1.68 | 2100 | 1.25 |
| 99 | 140 | 1.70 | 11518 | 0.83 | 12106 | 0.81 |
| 1234 | 537 | 2.08 | 9459 | 1.15 | 9474 | 1.14 |
| 2026 | 100 | 1.74 | 11030 | 0.82 | 11990 | 0.77 |

**Item 8: kinless newborns**

| seed | births seen | kinless | kinless share | kinless median sols to first grown friend (resolved / unresolved) | kin newborns median (resolved / unresolved) |
|---|---|---|---|---|---|
| 42 | 167 | 0 | 0.00 | -1.0 (0 / 0) | 28.0 (128 / 39) |
| 7 | 65 | 0 | 0.00 | -1.0 (0 / 0) | 25.0 (45 / 20) |
| 99 | 172 | 0 | 0.00 | -1.0 (0 / 0) | 29.0 (133 / 39) |
| 1234 | 135 | 0 | 0.00 | -1.0 (0 / 0) | 26.0 (131 / 4) |
| 2026 | 154 | 0 | 0.00 | -1.0 (0 / 0) | 29.0 (120 / 34) |

**Item 10: log share**

| seed | entries logged | relationship entries | share | oldest entry in log at end (sol) | log size |
|---|---|---|---|---|---|
| 42 | 1250 | 120 | 9.6% | 201 | 500 |
| 7 | 454 | 59 | 13.0% | 0 | 454 |
| 99 | 1268 | 130 | 10.3% | 230 | 500 |
| 1234 | 1112 | 136 | 12.2% | 187 | 500 |
| 2026 | 1097 | 118 | 10.8% | 185 | 500 |

**Ages, population, deaths, newborn cohort**

| seed | age history | pop at end | births | deaths (air/thirst/hunger/eva/other) | newborns after sol 100 alive (n) | their mean friends | loneliest third mean friends | zero-friend newborns |
|---|---|---|---|---|---|---|---|---|
| 42 | S@67 L@213(ice) | 164 | 167 | 0/10/0/0/0 | 111 | 2.15 | 0.00 | 38 |
| 7 | S@58 | 72 | 65 | 0/0/0/0/0 | 40 | 9.70 | 0.92 | 1 |
| 99 | S@54 L@174(ice) | 157 | 172 | 0/22/0/0/0 | 95 | 1.87 | 0.26 | 23 |
| 1234 | S@65 | 142 | 135 | 0/0/0/0/0 | 75 | 7.11 | 0.80 | 11 |
| 2026 | S@53 | 156 | 154 | 0/5/0/0/0 | 109 | 1.31 | 0.00 | 36 |

**Targets**

| target | seed 42 | seed 7 | seed 99 | seed 1234 | seed 2026 |
|---|---|---|---|---|---|
| dropped_lt_5pct | PASS (dropped 0 of 115 capped-kind events (logged 115 + dropped 0) = 0.00%; of lines_capped 3 = 0.00%) | PASS (dropped 0 of 59 capped-kind events (logged 59 + dropped 0) = 0.00%; of lines_capped 0 = 0.00%) | PASS (dropped 0 of 120 capped-kind events (logged 120 + dropped 0) = 0.00%; of lines_capped 0 = 0.00%) | PASS (dropped 0 of 136 capped-kind events (logged 136 + dropped 0) = 0.00%; of lines_capped 2 = 0.00%) | PASS (dropped 0 of 113 capped-kind events (logged 113 + dropped 0) = 0.00%; of lines_capped 0 = 0.00%) |
| first_grown_friendship_lt_20 | FAIL (first_friendship_sol 45, first_birth_sol 13, first_mars_born_friendship_sol 45) | FAIL (first_friendship_sol 34, first_birth_sol 19, first_mars_born_friendship_sol 34) | FAIL (first_friendship_sol 68, first_birth_sol 26, first_mars_born_friendship_sol 68) | FAIL (first_friendship_sol 41, first_birth_sol 21, first_mars_born_friendship_sol 41) | FAIL (first_friendship_sol 54, first_birth_sol 18, first_mars_born_friendship_sol 54) |
| first_line_lt_30 | PASS (first relationship line sol 21 (first non-grief 21)) | PASS (first relationship line sol 16 (first non-grief 16)) | PASS (first relationship line sol 19 (first non-grief 19)) | PASS (first relationship line sol 21 (first non-grief 21)) | PASS (first relationship line sol 14 (first non-grief 14)) |
| first_mars_born_friendship_within_15_of_first_birth | FAIL (first birth 13, first Mars-born friendship 45, gap 32) | PASS (first birth 19, first Mars-born friendship 34, gap 15) | FAIL (first birth 26, first Mars-born friendship 68, gap 42) | FAIL (first birth 21, first Mars-born friendship 41, gap 20) | FAIL (first birth 18, first Mars-born friendship 54, gap 36) |
| friends_mean_300_in_1_12 | PASS (friends_mean 2.01) | FAIL (friends_mean 12.67) | PASS (friends_mean 1.78) | PASS (friends_mean 7.56) | PASS (friends_mean 1.28) |
| lines_ge_1_per_5_sols_20_300 | PASS (2.05 lines per 5 sols (115 lines in sols 20 to 299); zero-line 5-sol blocks 10 of 56) | PASS (1.04 lines per 5 sols (58 lines in sols 20 to 299); zero-line 5-sol blocks 22 of 56) | PASS (2.12 lines per 5 sols (119 lines in sols 20 to 299); zero-line 5-sol blocks 10 of 56) | PASS (2.43 lines per 5 sols (136 lines in sols 20 to 299); zero-line 5-sol blocks 9 of 56) | PASS (2.00 lines per 5 sols (112 lines in sols 20 to 299); zero-line 5-sol blocks 13 of 56) |
| lonely_share_300_in_0.05_0.35 | FAIL (lonely_share 0.396) | FAIL (lonely_share 0.028) | PASS (lonely_share 0.293) | PASS (lonely_share 0.120) | FAIL (lonely_share 0.365) |
| warmest_third_more_friends_than_coldest | PASS (warm 3.91 vs cold 0.59) | PASS (warm 18.75 vs cold 7.54) | PASS (warm 3.06 vs cold 0.63) | PASS (warm 10.72 vs cold 4.23) | PASS (warm 1.92 vs cold 0.83) |

### Run: friend

**Item 1: firsts and lines**

| seed | first birth | first_friendship_sol | first_mars_born_friendship_sol | first rel line (non-grief) | friends | found_friend | close | close_crew | drifted | grief | capped | dropped | stale | formed | max lines/sol | mean lines/sol 20-299 | lines per 5 sols 20-299 | zero 5-sol blocks |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 42 | 9 | 20 | 20 | 20 (20) | 21 | 75 | 11 | 0 | 3 | 0 | 2 | 0 | 0 | 1252 | 3 | 0.393 | 1.96 | 14 of 56 |
| 7 | 37 | 63 | 63 | 23 (23) | 22 | 95 | 3 | 1 | 3 | 10 | 2 | 0 | 0 | 639 | 3 | 0.443 | 2.21 | 11 of 56 |
| 99 | 22 | 51 | 51 | 17 (17) | 10 | 101 | 3 | 1 | 2 | 0 | 0 | 0 | 0 | 624 | 3 | 0.414 | 2.07 | 12 of 56 |
| 1234 | 21 | 49 | 49 | 22 (22) | 7 | 38 | 3 | 1 | 3 | 0 | 2 | 0 | 0 | 1473 | 3 | 0.186 | 0.93 | 35 of 56 |
| 2026 | 32 | 47 | 47 | 31 (31) | 12 | 94 | 4 | 1 | 2 | 5 | 2 | 0 | 1 | 635 | 4 | 0.404 | 2.02 | 8 of 56 |

**Item 2: trust readings (web / second / lonely / friends_mean; parts of size 3+ at the last sol)**

| seed | sol 30 | sol 60 | sol 100 | sol 150 | sol 200 | sol 300 | web parts >= 3 at 300 |
|---|---|---|---|---|---|---|---|
| 42 | 1.00 / 0.00 / 0.00 / 3.43 | 0.93 / 0.05 / 0.02 / 2.37 | 0.65 / 0.09 / 0.19 / 1.69 | 0.58 / 0.04 / 0.30 / 1.53 | 0.81 / 0.02 / 0.13 / 5.45 | 0.86 / 0.02 / 0.12 / 7.18 | 1 |
| 7 | 1.00 / 0.00 / 0.00 / 6.00 | 0.91 / 0.09 / 0.00 / 2.64 | 0.83 / 0.04 / 0.06 / 1.96 | 0.61 / 0.08 / 0.18 / 2.87 | 0.64 / 0.03 / 0.26 / 2.58 | 0.44 / 0.02 / 0.42 / 1.52 | 3 |
| 99 | 1.00 / 0.00 / 0.00 / 4.33 | 1.00 / 0.00 / 0.00 / 3.45 | 0.81 / 0.00 / 0.19 / 2.32 | 0.71 / 0.04 / 0.25 / 2.23 | 0.85 / 0.03 / 0.12 / 4.06 | 0.75 / 0.02 / 0.19 / 2.99 | 2 |
| 1234 | 1.00 / 0.00 / 0.00 / 3.83 | 0.91 / 0.09 / 0.00 / 2.18 | 0.31 / 0.19 / 0.25 / 1.25 | 0.92 / 0.00 / 0.08 / 4.31 | 1.00 / 0.00 / 0.00 / 19.27 | 1.00 / 0.00 / 0.00 / 37.27 | 1 |
| 2026 | 1.00 / 0.00 / 0.00 / 6.00 | 0.95 / 0.00 / 0.05 / 3.27 | 0.95 / 0.05 / 0.00 / 3.35 | 0.82 / 0.06 / 0.10 / 3.39 | 0.63 / 0.03 / 0.20 / 2.04 | 0.50 / 0.03 / 0.38 / 2.04 | 3 |

**Items 3 and 4: personality (mean friend count at sol 300; warmest third / coldest third)**

| seed | alive | all: warm / cold | top-half work share: warm / cold | bottom-half work share: warm / cold | work share mean top / bottom | bond age, restless top / bottom third (all friendships) | (grown only) |
|---|---|---|---|---|---|---|---|
| 42 | 117 | 9.38 / 3.97 | 9.89 / 2.74 | 9.84 / 6.68 | 0.028 / 0.019 | 18.8 / 36.8 sols (n 420) | 16.5 / 36.6 sols (n 413) |
| 7 | 162 | 2.65 / 0.54 | 3.33 / 0.63 | 1.56 / 0.52 | 0.034 / 0.015 | 45.7 / 38.0 sols (n 123) | 27.7 / 36.4 sols (n 108) |
| 99 | 142 | 4.28 / 1.91 | 4.48 / 2.26 | 4.17 / 1.30 | 0.039 / 0.022 | 22.9 / 49.9 sols (n 212) | 16.3 / 40.1 sols (n 179) |
| 1234 | 52 | 41.94 / 33.00 | 43.38 / 32.00 | 41.50 / 36.38 | 0.027 / 0.017 | 47.6 / 77.6 sols (n 969) | 47.9 / 75.5 sols (n 961) |
| 2026 | 144 | 3.42 / 0.85 | 5.25 / 1.42 | 1.58 / 0.29 | 0.034 / 0.017 | 26.2 / 68.0 sols (n 147) | 28.1 / 52.8 sols (n 122) |

**Item 5: hours together per sol (median over pairs alive at the end; friend pairs vs non-friend pairs)**

| seed | friend pairs | friend median h/sol | non-friend co-present pairs | their median | all non-friend pairs | their median |
|---|---|---|---|---|---|---|
| 42 | 420 | 2.10 | 6311 | 1.08 | 6366 | 1.08 |
| 7 | 123 | 1.82 | 12697 | 0.89 | 12918 | 0.88 |
| 99 | 212 | 2.23 | 9200 | 1.00 | 9799 | 0.96 |
| 1234 | 969 | 3.01 | 357 | 1.94 | 357 | 1.94 |
| 2026 | 147 | 1.92 | 9313 | 0.85 | 10149 | 0.79 |

**Item 8: kinless newborns**

| seed | births seen | kinless | kinless share | kinless median sols to first grown friend (resolved / unresolved) | kin newborns median (resolved / unresolved) |
|---|---|---|---|---|---|
| 42 | 111 | 0 | 0.00 | -1.0 (0 / 0) | 29.0 (110 / 1) |
| 7 | 173 | 0 | 0.00 | -1.0 (0 / 0) | 26.0 (133 / 40) |
| 99 | 135 | 0 | 0.00 | -1.0 (0 / 0) | 20.0 (116 / 19) |
| 1234 | 45 | 0 | 0.00 | -1.0 (0 / 0) | 27.0 (45 / 0) |
| 2026 | 142 | 0 | 0.00 | -1.0 (0 / 0) | 19.0 (111 / 31) |

**Item 10: log share**

| seed | entries logged | relationship entries | share | oldest entry in log at end (sol) | log size |
|---|---|---|---|---|---|
| 42 | 830 | 110 | 13.3% | 107 | 500 |
| 7 | 1164 | 134 | 11.5% | 197 | 500 |
| 99 | 863 | 117 | 13.6% | 192 | 500 |
| 1234 | 452 | 52 | 11.5% | 0 | 452 |
| 2026 | 985 | 118 | 12.0% | 191 | 500 |

**Ages, population, deaths, newborn cohort**

| seed | age history | pop at end | births | deaths (air/thirst/hunger/eva/other) | newborns after sol 100 alive (n) | their mean friends | loneliest third mean friends | zero-friend newborns |
|---|---|---|---|---|---|---|---|---|
| 42 | S@55 | 117 | 111 | 0/1/0/0/0 | 41 | 7.29 | 2.31 | 2 |
| 7 | S@61 L@260(ice) | 162 | 173 | 0/18/0/0/0 | 115 | 1.51 | 0.00 | 45 |
| 99 | S@66 | 142 | 135 | 0/0/0/0/0 | 105 | 2.90 | 0.49 | 18 |
| 1234 | S@112 | 52 | 45 | 0/0/0/0/0 | 20 | 37.70 | 25.33 | 0 |
| 2026 | S@63 | 144 | 142 | 0/5/0/0/0 | 108 | 1.68 | 0.00 | 42 |

**Targets**

| target | seed 42 | seed 7 | seed 99 | seed 1234 | seed 2026 |
|---|---|---|---|---|---|
| dropped_lt_5pct | PASS (dropped 0 of 110 capped-kind events (logged 110 + dropped 0) = 0.00%; of lines_capped 2 = 0.00%) | PASS (dropped 0 of 124 capped-kind events (logged 124 + dropped 0) = 0.00%; of lines_capped 2 = 0.00%) | PASS (dropped 0 of 117 capped-kind events (logged 117 + dropped 0) = 0.00%; of lines_capped 0 = 0.00%) | PASS (dropped 0 of 52 capped-kind events (logged 52 + dropped 0) = 0.00%; of lines_capped 2 = 0.00%) | PASS (dropped 0 of 113 capped-kind events (logged 113 + dropped 0) = 0.00%; of lines_capped 2 = 0.00%) |
| first_grown_friendship_lt_20 | FAIL (first_friendship_sol 20, first_birth_sol 9, first_mars_born_friendship_sol 20) | FAIL (first_friendship_sol 63, first_birth_sol 37, first_mars_born_friendship_sol 63) | FAIL (first_friendship_sol 51, first_birth_sol 22, first_mars_born_friendship_sol 51) | FAIL (first_friendship_sol 49, first_birth_sol 21, first_mars_born_friendship_sol 49) | FAIL (first_friendship_sol 47, first_birth_sol 32, first_mars_born_friendship_sol 47) |
| first_line_lt_30 | PASS (first relationship line sol 20 (first non-grief 20)) | PASS (first relationship line sol 23 (first non-grief 23)) | PASS (first relationship line sol 17 (first non-grief 17)) | PASS (first relationship line sol 22 (first non-grief 22)) | FAIL (first relationship line sol 31 (first non-grief 31)) |
| first_mars_born_friendship_within_15_of_first_birth | PASS (first birth 9, first Mars-born friendship 20, gap 11) | FAIL (first birth 37, first Mars-born friendship 63, gap 26) | FAIL (first birth 22, first Mars-born friendship 51, gap 29) | FAIL (first birth 21, first Mars-born friendship 49, gap 28) | PASS (first birth 32, first Mars-born friendship 47, gap 15) |
| friends_mean_300_in_1_12 | PASS (friends_mean 7.18) | PASS (friends_mean 1.52) | PASS (friends_mean 2.99) | FAIL (friends_mean 37.27) | PASS (friends_mean 2.04) |
| lines_ge_1_per_5_sols_20_300 | PASS (1.96 lines per 5 sols (110 lines in sols 20 to 299); zero-line 5-sol blocks 14 of 56) | PASS (2.21 lines per 5 sols (124 lines in sols 20 to 299); zero-line 5-sol blocks 11 of 56) | PASS (2.07 lines per 5 sols (116 lines in sols 20 to 299); zero-line 5-sol blocks 12 of 56) | FAIL (0.93 lines per 5 sols (52 lines in sols 20 to 299); zero-line 5-sol blocks 35 of 56) | PASS (2.02 lines per 5 sols (113 lines in sols 20 to 299); zero-line 5-sol blocks 8 of 56) |
| lonely_share_300_in_0.05_0.35 | PASS (lonely_share 0.120) | FAIL (lonely_share 0.420) | PASS (lonely_share 0.190) | FAIL (lonely_share 0.000) | FAIL (lonely_share 0.382) |
| warmest_third_more_friends_than_coldest | PASS (warm 9.38 vs cold 3.97) | PASS (warm 2.65 vs cold 0.54) | PASS (warm 4.28 vs cold 1.91) | PASS (warm 41.94 vs cold 33.00) | PASS (warm 3.42 vs cold 0.85) |

### Run: both

**Item 1: firsts and lines**

| seed | first birth | first_friendship_sol | first_mars_born_friendship_sol | first rel line (non-grief) | friends | found_friend | close | close_crew | drifted | grief | capped | dropped | stale | formed | max lines/sol | mean lines/sol 20-299 | lines per 5 sols 20-299 | zero 5-sol blocks |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 42 | 9 | 20 | 20 | 20 (20) | 19 | 100 | 9 | 0 | 3 | 0 | 3 | 0 | 0 | 1462 | 4 | 0.468 | 2.34 | 9 of 56 |
| 7 | 37 | 63 | 63 | 23 (23) | 19 | 110 | 6 | 1 | 4 | 4 | 1 | 0 | 1 | 847 | 3 | 0.500 | 2.50 | 10 of 56 |
| 99 | 22 | 51 | 51 | 17 (17) | 10 | 68 | 9 | 1 | 2 | 0 | 0 | 0 | 0 | 637 | 3 | 0.318 | 1.59 | 15 of 56 |
| 1234 | 21 | 49 | 49 | 22 (22) | 15 | 59 | 5 | 1 | 3 | 3 | 0 | 0 | 0 | 400 | 3 | 0.296 | 1.48 | 20 of 56 |
| 2026 | 32 | 47 | 47 | 31 (31) | 9 | 59 | 3 | 1 | 2 | 0 | 0 | 0 | 1 | 1489 | 3 | 0.264 | 1.32 | 19 of 56 |

**Item 2: trust readings (web / second / lonely / friends_mean; parts of size 3+ at the last sol)**

| seed | sol 30 | sol 60 | sol 100 | sol 150 | sol 200 | sol 300 | web parts >= 3 at 300 |
|---|---|---|---|---|---|---|---|
| 42 | 1.00 / 0.00 / 0.00 / 3.43 | 0.93 / 0.05 / 0.02 / 2.37 | 0.40 / 0.15 / 0.17 / 1.50 | 0.62 / 0.06 / 0.20 / 1.68 | 0.82 / 0.02 / 0.16 / 4.28 | 0.75 / 0.03 / 0.19 / 4.25 | 2 |
| 7 | 1.00 / 0.00 / 0.00 / 6.00 | 0.91 / 0.09 / 0.00 / 2.64 | 0.83 / 0.04 / 0.06 / 1.96 | 0.62 / 0.05 / 0.18 / 2.87 | 0.77 / 0.02 / 0.18 / 4.90 | 0.56 / 0.02 / 0.25 / 1.76 | 3 |
| 99 | 1.00 / 0.00 / 0.00 / 4.33 | 1.00 / 0.00 / 0.00 / 3.45 | 0.84 / 0.00 / 0.16 / 2.49 | 0.75 / 0.04 / 0.17 / 3.12 | 0.85 / 0.00 / 0.15 / 5.32 | 0.65 / 0.02 / 0.23 / 2.12 | 1 |
| 1234 | 1.00 / 0.00 / 0.00 / 3.83 | 0.91 / 0.09 / 0.00 / 2.18 | 0.31 / 0.19 / 0.25 / 1.25 | 0.79 / 0.04 / 0.14 / 2.32 | 0.88 / 0.03 / 0.10 / 5.61 | 0.45 / 0.04 / 0.44 / 1.18 | 2 |
| 2026 | 1.00 / 0.00 / 0.00 / 6.00 | 0.95 / 0.00 / 0.05 / 3.27 | 0.94 / 0.06 / 0.00 / 3.49 | 0.96 / 0.00 / 0.04 / 5.00 | 1.00 / 0.00 / 0.00 / 26.32 | 0.99 / 0.00 / 0.01 / 16.03 | 1 |

**Items 3 and 4: personality (mean friend count at sol 300; warmest third / coldest third)**

| seed | alive | all: warm / cold | top-half work share: warm / cold | bottom-half work share: warm / cold | work share mean top / bottom | bond age, restless top / bottom third (all friendships) | (grown only) |
|---|---|---|---|---|---|---|---|
| 42 | 154 | 7.29 / 1.12 | 7.36 / 1.16 | 6.80 / 1.04 | 0.031 / 0.016 | 29.6 / 59.3 sols (n 327) | 33.1 / 57.5 sols (n 305) |
| 7 | 167 | 2.75 / 0.82 | 2.78 / 1.07 | 2.71 / 0.54 | 0.036 / 0.019 | 37.7 / 35.1 sols (n 147) | 30.2 / 37.9 sols (n 122) |
| 99 | 97 | 2.66 / 1.16 | 3.31 / 1.12 | 2.69 / 1.50 | 0.031 / 0.018 | 59.6 / 94.7 sols (n 103) | 47.2 / 91.8 sols (n 84) |
| 1234 | 107 | 2.14 / 0.46 | 3.00 / 0.35 | 1.56 / 0.67 | 0.033 / 0.021 | 24.5 / 116.2 sols (n 63) | 30.5 / 105.5 sols (n 47) |
| 2026 | 77 | 19.20 / 12.92 | 19.75 / 11.17 | 18.38 / 15.69 | 0.030 / 0.017 | 31.6 / 99.2 sols (n 617) | 29.8 / 93.1 sols (n 593) |

**Item 5: hours together per sol (median over pairs alive at the end; friend pairs vs non-friend pairs)**

| seed | friend pairs | friend median h/sol | non-friend co-present pairs | their median | all non-friend pairs | their median |
|---|---|---|---|---|---|---|
| 42 | 327 | 2.00 | 10326 | 1.04 | 11454 | 0.97 |
| 7 | 147 | 1.92 | 12762 | 0.92 | 13714 | 0.88 |
| 99 | 103 | 2.44 | 4541 | 1.16 | 4553 | 1.16 |
| 1234 | 63 | 1.88 | 5482 | 0.83 | 5608 | 0.82 |
| 2026 | 617 | 3.01 | 2242 | 1.61 | 2309 | 1.58 |

**Item 8: kinless newborns**

| seed | births seen | kinless | kinless share | kinless median sols to first grown friend (resolved / unresolved) | kin newborns median (resolved / unresolved) |
|---|---|---|---|---|---|
| 42 | 147 | 0 | 0.00 | -1.0 (0 / 0) | 27.0 (131 / 16) |
| 7 | 169 | 0 | 0.00 | -1.0 (0 / 0) | 25.0 (142 / 27) |
| 99 | 90 | 0 | 0.00 | -1.0 (0 / 0) | 23.5 (82 / 8) |
| 1234 | 104 | 0 | 0.00 | -1.0 (0 / 0) | 28.5 (82 / 22) |
| 2026 | 70 | 0 | 0.00 | -1.0 (0 / 0) | 17.0 (70 / 0) |

**Item 10: log share**

| seed | entries logged | relationship entries | share | oldest entry in log at end (sol) | log size |
|---|---|---|---|---|---|
| 42 | 1054 | 131 | 12.4% | 151 | 500 |
| 7 | 1243 | 144 | 11.6% | 206 | 500 |
| 99 | 700 | 90 | 12.9% | 121 | 500 |
| 1234 | 887 | 86 | 9.7% | 172 | 500 |
| 2026 | 492 | 74 | 15.0% | 0 | 492 |

**Ages, population, deaths, newborn cohort**

| seed | age history | pop at end | births | deaths (air/thirst/hunger/eva/other) | newborns after sol 100 alive (n) | their mean friends | loneliest third mean friends | zero-friend newborns |
|---|---|---|---|---|---|---|---|---|
| 42 | S@55 | 154 | 147 | 0/0/0/0/0 | 82 | 4.48 | 0.74 | 7 |
| 7 | S@61 L@272(ice) | 167 | 169 | 0/9/0/0/0 | 115 | 1.86 | 0.32 | 26 |
| 99 | S@66 | 97 | 90 | 0/0/0/0/0 | 60 | 1.73 | 0.55 | 9 |
| 1234 | S@112 L@254(ice) | 107 | 104 | 0/4/0/0/0 | 77 | 1.06 | 0.00 | 29 |
| 2026 | S@63 | 77 | 70 | 0/0/0/0/0 | 41 | 14.07 | 5.92 | 1 |

**Targets**

| target | seed 42 | seed 7 | seed 99 | seed 1234 | seed 2026 |
|---|---|---|---|---|---|
| dropped_lt_5pct | PASS (dropped 0 of 131 capped-kind events (logged 131 + dropped 0) = 0.00%; of lines_capped 3 = 0.00%) | PASS (dropped 0 of 140 capped-kind events (logged 140 + dropped 0) = 0.00%; of lines_capped 1 = 0.00%) | PASS (dropped 0 of 90 capped-kind events (logged 90 + dropped 0) = 0.00%; of lines_capped 0 = 0.00%) | PASS (dropped 0 of 83 capped-kind events (logged 83 + dropped 0) = 0.00%; of lines_capped 0 = 0.00%) | PASS (dropped 0 of 74 capped-kind events (logged 74 + dropped 0) = 0.00%; of lines_capped 0 = 0.00%) |
| first_grown_friendship_lt_20 | FAIL (first_friendship_sol 20, first_birth_sol 9, first_mars_born_friendship_sol 20) | FAIL (first_friendship_sol 63, first_birth_sol 37, first_mars_born_friendship_sol 63) | FAIL (first_friendship_sol 51, first_birth_sol 22, first_mars_born_friendship_sol 51) | FAIL (first_friendship_sol 49, first_birth_sol 21, first_mars_born_friendship_sol 49) | FAIL (first_friendship_sol 47, first_birth_sol 32, first_mars_born_friendship_sol 47) |
| first_line_lt_30 | PASS (first relationship line sol 20 (first non-grief 20)) | PASS (first relationship line sol 23 (first non-grief 23)) | PASS (first relationship line sol 17 (first non-grief 17)) | PASS (first relationship line sol 22 (first non-grief 22)) | FAIL (first relationship line sol 31 (first non-grief 31)) |
| first_mars_born_friendship_within_15_of_first_birth | PASS (first birth 9, first Mars-born friendship 20, gap 11) | FAIL (first birth 37, first Mars-born friendship 63, gap 26) | FAIL (first birth 22, first Mars-born friendship 51, gap 29) | FAIL (first birth 21, first Mars-born friendship 49, gap 28) | PASS (first birth 32, first Mars-born friendship 47, gap 15) |
| friends_mean_300_in_1_12 | PASS (friends_mean 4.25) | PASS (friends_mean 1.76) | PASS (friends_mean 2.12) | PASS (friends_mean 1.18) | FAIL (friends_mean 16.03) |
| lines_ge_1_per_5_sols_20_300 | PASS (2.34 lines per 5 sols (131 lines in sols 20 to 299); zero-line 5-sol blocks 9 of 56) | PASS (2.50 lines per 5 sols (140 lines in sols 20 to 299); zero-line 5-sol blocks 10 of 56) | PASS (1.59 lines per 5 sols (89 lines in sols 20 to 299); zero-line 5-sol blocks 15 of 56) | PASS (1.48 lines per 5 sols (83 lines in sols 20 to 299); zero-line 5-sol blocks 20 of 56) | PASS (1.32 lines per 5 sols (74 lines in sols 20 to 299); zero-line 5-sol blocks 19 of 56) |
| lonely_share_300_in_0.05_0.35 | PASS (lonely_share 0.188) | PASS (lonely_share 0.251) | PASS (lonely_share 0.227) | FAIL (lonely_share 0.439) | FAIL (lonely_share 0.013) |
| warmest_third_more_friends_than_coldest | PASS (warm 7.29 vs cold 1.12) | PASS (warm 2.75 vs cold 0.82) | PASS (warm 2.66 vs cold 1.16) | PASS (warm 2.14 vs cold 0.46) | PASS (warm 19.20 vs cold 12.92) |

## Notes on measurement limits

- One run per seed and setting. The pull changes room choice and so every later draw: pull runs are different colonies from shipped, so differences in pop, ages and cohorts are not attributable to the pull alone.
- Sols to first grown friend, friendship ages and line counts per sol have sol resolution (sol-boundary reads).
- The "work share" is the share of awake ticks (1 h samples, state other than sleep) in state mining, or work on the current site.
- Tick cost was taken with two worlds in one process on a noisy host; a separate profile run (padded world) agrees in magnitude.

## Recommended spec changes (facts for the lead designer; nothing here was applied)

1. Restate "first grown friendship before sol 20". Measured shipped: sol 45, 34, 68, 41, 54, with first births at 13, 19, 26, 21, 18; the first birth is later than sol 8 on every seed, so by the section 13 note it is a target error. A target relative to the first birth fits what the sim does (gap 15, 20, 32, 36, 42 sols shipped).
2. Restate or recalibrate "first Mars-born friendship within 15 sols of the first birth": 4 of 5 shipped seeds exceed it (gaps 32, 42, 20, 36; seed 7 is 15).
3. "First relationship line before sol 30" passes on every seed, but only through crew lines (crew drift on 42, 99, 1234; crew close on 7, 2026). If the intent is a line about a grown friendship, the measured first such line is sol 34 to 68.
4. `lonely_share` at 300 is outside 0.05 to 0.35 on 3 of 5 shipped seeds (0.396, 0.028, 0.365) and `friends_mean` on seed 7 (12.67). The band is narrower than the seed-to-seed spread (lonely 0.028 to 0.396, friends_mean 1.28 to 12.67), which comes from population and cohort differences between seeds, not from a single parameter.
5. The tick cost target (under 1 ms median at pop 160) fails: 5.97 ms median at pop above 120 in a real run, 4.17 ms in the profile world. Section 13's chosen remedy is decay slicing (`decay.slices`) then `tick_h` 2.0; the profile shows the decay walk is 3.2 of 4.2 ms, so slicing by N acts on that part. Needs a decision whether to build it in Task 4.
6. The item 4 trigger (warmth has no effect among the work-heavy half) did not fire, but the "work-heavy" half spends only about 3 percent of awake ticks on site or mining; the split as defined barely separates beings. Consider defining the split by absolute work share or by site crew membership.
7. Item 8 (kinless newborns) is not measurable as specified: 0 kinless births in all 15 runs (every birth records a living parent at the next tick). Either drop the item or define kinless as "parent died before the newborn's first friend".
8. Pull target ("loneliest-third newborn friend count with both terms not below shipped on any seed") fails on 2 of 5 seeds. It compares different colonies (cohort sizes 20 to 115); a paired design (same seed, same cohort definition on births before the runs diverge) or a mean over several seeds would test the pull rather than the divergence.
9. Section 6 arithmetic: measured median hours together per sol for friend pairs is 1.7 to 2.7 against the 3.5 h balance point the spec gives for a typical pair; friendships here survive largely through the seed bonds and the close-bond decay hold. Worth rechecking section 6's "about 10 h a sol" roommate figure against the 1.9 to 2.7 h measured.
10. Define "capped-kind events" in the dropped-events target (the probe used logged + dropped; `lines_capped` gives the same verdict, 0 dropped everywhere). The cap is almost never reached (`lines_capped` 0 to 3 per run), so the dropped-events target does not test the cap.
