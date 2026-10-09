# Task 3 step 5: age calibration probe results

Measured numbers only. No threshold is recommended here; any change goes to the lead game-designer. `data/` and `sim/` were not touched. The only new code is `tools/age_probe.gd`. Raw outputs are in `docs/balance/task-3-calibration-data/` (per-seed text report, per-sol CSV, per-sol JSON of recorded clause inputs, sweeps, timing).

## Commands and version

Git: HEAD `74851d9043d7cc81ef2396a6ab1b243cf593a638` (the age system, `data/ages.json` and the hook are committed; `tools/age_probe.gd` and `docs/balance/task-3-*` are uncommitted). Godot 4.5.stable. `data_hash` in the probe header: `c76d875caa4d74fe` (all five runs and both timing runs).

```
# five seeds, run in parallel as 5 background processes, 300 sols each
godot --headless --path station-zero --script res://tools/age_probe.gd -- --seed N --sols 300 --out <abs>/station-zero/docs/balance/task-3-calibration-data     (N = 42 7 99 1234 2026)
# sweeps, replayed from the five recorded seed_N.json files
godot --headless --path station-zero --script res://tools/age_probe.gd -- --sweeps <abs>/seed_42.json <abs>/seed_7.json <abs>/seed_99.json <abs>/seed_1234.json <abs>/seed_2026.json
# timing, alone, after the seed runs finished
godot --headless --path station-zero --script res://tools/age_probe.gd -- --timing --seed 42 --sols 300 --calls 2000
godot --headless --path station-zero --script res://tools/age_probe.gd -- --timing --seed 7 --sols 300 --calls 2000
```

How the probe observes. World A is the real sim with the live hook. World B is the same seed with `ages_enabled = false`, stepped in lockstep. At every sol boundary the probe calls `Ages.sample(B)` itself (with B's `ages.snap_*` maintained by the probe exactly as `on_sol` does) and stores the raw inputs of every clause. After every step it reads B's ice to get the minimum inside each sol. Wall time per seed with two worlds and five processes: 854 to 941 s for seeds 42, 99, 1234, 2026 and 365 s for seed 7.

## Self-replay check

PASS on all five seeds. For each seed: the history recomputed by replaying the stored per-sol inputs through `Ages.decide` (same `on_sol` order) equals the live `stats.age_history` (age, how, cause, sol, and pop and family_mars_born on each change); A's own `last_sample` equals the probe's sample clause by clause on every sampled sol (0 diffs); clauses recomputed from the raw inputs equal the recorded clauses (0 diffs); the final window (ok and failed groups, 40 entries) is identical; world A and B have the same pop and ice at every boundary (0 mismatches). The "shipped values" control row of the sweeps reproduces the live histories.

## Age changes per seed (live `stats.age_history`)

| seed | history | first settlement | age changes | sols Landing / Settlement | age at sol 300 |
|---|---|---|---|---|---|
| 42 | none | never | 0 | 300 / 0 | landing |
| 7 | settled at sol 76 (pop 27, family Mars-born 20) | 76 | 1 | 76 / 224 | settlement |
| 99 | settled at sol 75 (pop 42, fam 35); fell back at sol 174, cause ice (pop 107, fam 100) | 75 | 2 | 201 / 99 | landing |
| 1234 | settled at sol 85 (pop 52, fam 45) | 85 | 1 | 85 / 215 | settlement |
| 2026 | settled at sol 216 (pop 112, fam 105) | 216 | 1 | 216 / 84 | settlement |

These equal the five histories the lead quoted. Flaps (a change within 40 sols of the previous change): 0 on every seed. Shortest gap between two changes: 99 sols (seed 99, the only seed with two changes). Samples taken: 296 per seed (sols 5 to 300, pop never 0). Ok samples: seed 42 168 (56.8%), 7 272 (91.9%), 99 170 (57.4%), 1234 263 (88.9%), 2026 229 (77.4%). First ok sample: sol 6 on seeds 42, 7, 99, 2026; sol 9 on seed 1234.

## Clause-failure matrix

Share of the 296 sampled sols (sols 5 to 300) on which the clause failed (count in brackets). Clause names as in `Ages.sample`; `ice`, `calm` and `rested` are the three that matter; `oxygen` and `food` are the stock clauses. `fam_count<5` and `fam_homes<2` are the entry clauses on family Mars-born and distinct birth habitats, evaluated on the same 296 sols (not part of "ok").

| clause | seed 42 | seed 7 | seed 99 | seed 1234 | seed 2026 |
|---|---|---|---|---|---|
| oxygen (stock >= 0.5 cap) | 0.3% (1) | 0.3% (1) | 0.3% (1) | 0.3% (1) | 0.3% (1) |
| o2_net | 0 | 0 | 0 | 0 | 0 |
| food (stock >= 0.5 cap) | 0.3% (1) | 0.3% (1) | 0.3% (1) | 0.3% (1) | 0.3% (1) |
| food_net | 0 | 0 | 0 | 0 | 0 |
| power_budget | 0 | 0 | 0 | 0 | 0 |
| none_offline | 0 | 0 | 0 | 0 | 0 |
| no_short | 0 | 0 | 0 | 0 | 0 |
| no_shortage_death (death) | 3.0% (9) | 0 | 5.4% (16) | 0 | 1.4% (4) |
| ice | 27.0% (80) | 0 | 35.8% (106) | 0 | 8.4% (25) |
| calm | 15.5% (46) | 8.1% (24) | 8.8% (26) | 10.8% (32) | 12.8% (38) |
| rested | 3.7% (11) | 2.0% (6) | 1.7% (5) | 3.0% (9) | 2.7% (8) |
| fam_count < 5 | 4.7% (14) | 6.1% (18) | 9.1% (27) | 7.4% (22) | 6.1% (18) |
| fam_homes < 2 | 3.0% (9) | 5.4% (16) | 7.4% (22) | 6.4% (19) | 5.1% (15) |

The single `oxygen` and `food` failure on every seed is sol 5. The shortage-death sols: seed 42 sols 212-214, 257-259, 288, 299, 300; seed 99 sols 225-228, 241-245, 248, 249, 251, 255, 256, 273, 286; seed 2026 sols 178, 296, 298, 300. The ice clause first fails on sol 140 (seed 42), 157 (seed 99), 161 (seed 2026); never on seeds 7 and 1234.

Per 50-sol band, not-ok sols out of sampled sols (clauses failing in that band):

| band | seed 42 | seed 7 | seed 99 | seed 1234 | seed 2026 |
|---|---|---|---|---|---|
| 1-50 (46 sampled) | 20 (calm 17, rested 9, oxygen 1, food 1) | 20 (calm 20, rested 6, oxygen 1, food 1) | 17 (calm 16, rested 5, o/f 1/1) | 23 (calm 22, rested 9, o/f 1/1) | 20 (calm 17, rested 6, o/f 1/1) |
| 51-100 | 14 (calm 14, rested 2) | 0 | 1 (calm 1) | 3 (calm 3) | 8 (calm 7, rested 2) |
| 101-150 | 17 (ice 11, calm 6) | 2 (calm 2) | 0 | 2 (calm 2) | 12 (calm 12) |
| 151-200 | 24 (ice 16, calm 9) | 0 | 36 (ice 36) | 1 (calm 1) | 16 (ice 15, calm 1, death 1) |
| 201-250 | 17 (ice 17, death 3) | 2 (calm 2) | 32 (ice 32, death 11, calm 2) | 4 (calm 4) | 1 (calm 1) |
| 251-300 | 36 (ice 36, death 6) | 0 | 40 (ice 38, death 5, calm 7) | 0 | 10 (ice 10, death 3) |

In sols 1 to 50 the not-ok count is 17 to 23 of 46 sampled on every seed, and calm is failing in 16 to 22 of them. Split by population on all seeds: with pop under 10 the calm clause failed on 4 of 11 (seed 42), 8 of 17 (7), 13 of 24 (99), 12 of 21 (1234), 9 of 17 (2026) sampled sols; with pop 10 or more on 42 of 285, 16 of 279, 13 of 272, 20 of 275, 29 of 279.

Calm and rested shares per sol (each seed's CSV has them for every sol): distressed share mean 0.055 (42), 0.039 (7), 0.041 (99), 0.049 (1234), 0.054 (2026), max 0.286 on seeds 42, 99 and 2026 and 0.429 on seeds 7 and 1234 (limit 0.10); rested share mean 0.862, 0.898, 0.874, 0.868, 0.854, minimum 0.429 to 0.500 (limit 0.70).

## Which clause blocks entry, and until when

Entry clauses at each Landing sol from sol 44 (the first sol with a full window): window full, ok share (36 of 40), last 3 ok, family Mars-born count (5), distinct birth habitats (2), dwell (20).

| seed | settlement (or state at sol 100 and 150) | last clause to pass | entry clause failing on Landing sols 44..end (failing sols / sole blocker sols / last failing sol) |
|---|---|---|---|
| 42 | Landing at 100 and 150 (and 300): share and recent failing; ok in trailing window 29 of 40 at sol 100, 24 of 40 at sol 150 | never settled | share 257 / 89 / 300; recent 168 / 0 / 300; full, fam_count, fam_homes, dwell 0 |
| 7 | settles at sol 76 | share (run of passing starts sol 76; recent from 49, fam_count from 23, fam_homes from 21, full from 44, dwell from 20) | share 32 / 27 / 75; recent 5 / 0 / 48; others 0 |
| 99 | settles at sol 75; then Landing again from 174 | share (run starts sol 75; recent from 54, fam_count 32, fam_homes 27) | share 157 / 44 / 300; recent 108 / 0 / 300; dwell 19 / 0 / 193 (the 19 sols after the sol 174 fall back); fam 0 |
| 1234 | settles at sol 85 | share (run starts sol 85; recent from 60, fam_count 27, fam_homes 24) | share 41 / 28 / 84; recent 13 / 0 / 59; others 0 |
| 2026 | Landing at sol 100 (34 of 40 ok) and 150 (31 of 40 ok); settles at sol 216 | share (run starts sol 216; recent from 183, fam_count 23, fam_homes 20) | share 172 / 90 / 215; recent 82 / 0 / 182; others 0 |

On every seed the family Mars-born count and habitat clauses pass continuously from sol 23 to 32 (count) and 20 to 27 (homes) onward, before the first full window at sol 44; they are never the blocker. The share clause is the last to pass at all four settlements and the only one failing at sol 100 and 150 on the two unsettled-at-100 seeds (42 also has recent failing). What fills the window with not-ok sols differs:

- seed 42: calm is the only failing clause on 36 of the 296 sols and fails 14 times in sols 51-100, 6 in 101-150; ice becomes the cause from sol 140 (first ice failure) and is the sole failing clause on 70 sols. The highest trailing ok count over the whole run is 33 of 40 (first at sol 139); it never reaches 36.
- seed 2026: calm fails 12 times in sols 101-150; ice fails on sols 161-165 and 171-180 (15 sols) and again on 291-300; the window reaches 36 ok at sol 216.
- seed 7 and 1234: only calm (and rested) fail between sol 44 and settlement. Seed 7 not-ok sols in 30-120: sols 30, 31, 33, 34, 36, 42, 43, 45, 46 and 102 (all calm, 30 and 33 also rested); the window first holds 36 ok at sol 76, when sol 36 has left it. Seed 1234 not-ok sols in 30-120: 32, 36, 37, 39, 43, 44, 45, 48, 54, 56, 57, 106; 36 ok first at sol 85.
- seed 99: after settling at sol 75, the ice clause fails on 106 sols from sol 157, with the not-ok count in the window crossing the exit line at sol 174; Landing stays to sol 300 with the share clause failing on every one of those sols.

## Sweeps (one parameter per row, replayed from the recorded per-sol inputs)

Cell: first settlement sol; number of age changes; shortest gap between changes; history (S = settled, L = fell back, with cause). Shipped values reproduce the live histories (control row in `sweeps.md`). The ages do not change the colony, so these replays are exact for the changed parameter.

| parameter = value | seed 42 | seed 7 | seed 99 | seed 1234 | seed 2026 |
|---|---|---|---|---|---|
| window_sols = 30 | never; 0 | 72; 1; S@72 | 67; 2; gap 103; S@67 L@170(ice) | 78; 1; S@78 | 207; 1; S@207 |
| window_sols = 40 (shipped) | never; 0 | 76; 1; S@76 | 75; 2; gap 99; S@75 L@174(ice) | 85; 1; S@85 | 216; 1; S@216 |
| window_sols = 50 | never; 0 | 84; 1; S@84 | 78; 2; gap 100; S@78 L@178(ice) | 94; 1; S@94 | 225; 1; S@225 |
| exit ok_share_below = 0.5 | never; 0 | 76; 1 | 75; 2; gap 103; L@178(ice) | 85; 1 | 216; 1 |
| exit ok_share_below = 0.6 (shipped) | never; 0 | 76; 1 | 75; 2; gap 99; L@174(ice) | 85; 1 | 216; 1 |
| exit ok_share_below = 0.7 | never; 0 | 76; 1 | 75; 2; gap 95; L@170(ice) | 85; 1 | 216; 1 |
| min_dwell_sols = 10 / 20 / 30 | never; 0 (all three) | 76; 1 (all three) | 75; 2; gap 99 (all three) | 85; 1 (all three) | 216; 1 (all three) |
| ice_min_sols = 1 | never; 0 | 76; 1 | 75; 2; gap 172; L@247(ice) | 85; 1 | 216; 1 |
| ice_min_sols = 2 (shipped) | never; 0 | 76; 1 | 75; 2; gap 99; L@174(ice) | 85; 1 | 216; 1 |
| ice_min_sols = 3 | never; 0 | 76; 1 | 75; 2; gap 96; L@171(ice) | 85; 1 | 217; 1 |
| rested_share_min = 0.5 | never; 0 | 76; 1 | 68; 2; gap 106; S@68 L@174(ice) | 85; 1 | 216; 1 |
| rested_share_min = 0.7 (shipped) | never; 0 | 76; 1 | 75; 2; gap 99 | 85; 1 | 216; 1 |
| rested_share_min = 0.9 | never; 0 | never; 0 | never; 0 | never; 0 | never; 0 |

Additional one-at-a-time rows beyond the five in spec section 14 (all other values shipped):

| parameter = value | seed 42 | seed 7 | seed 99 | seed 1234 | seed 2026 |
|---|---|---|---|---|---|
| distress_share_max = 0.05 | never; 0 | 83; 1 | 143; 2; gap 31; S@143 L@174(ice) | 250; 1 | 236; 2; gap 60; S@236 L@296(unrest) |
| distress_share_max = 0.2 | 67; 2; gap 146; S@67 L@213(ice) | 58; 1 | 54; 2; gap 120; S@54 L@174(ice) | 65; 1 | 53; 1 |
| mars_born_homes_min = 1 / 3, mars_born_min = 3 / 8 | identical to shipped on every seed (never; 76; 75 then 174; 85; 216) | | | | |
| entry ok_share = 0.8 | 92; 2; gap 61; S@92 L@153(ice) | 70; 1 | 62; 2; gap 112; S@62 L@174(ice) | 77; 1 | 70; 3; gap 35; S@70 L@177(ice) S@212 |
| entry ok_share = 0.95 | never; 0 | 83; 1 | 81; 2; gap 93; L@174(ice) | 94; 1 | 218; 1 |
| entry recent_ok_sols = 1 / 5, exit recent_sols = 3 / 10 | identical to shipped on every seed | | | | |

Facts read from the sweeps: with a value in the spec-14 rows alone, seed 42 never settles and seed 2026 settles between sol 207 and 225; no spec-14 row puts all five seeds between sol 40 and 150. rested_share_min 0.9 is never reached on any seed. In the extra rows, distress_share_max 0.2 puts all five between sol 53 and 67 (seed 42 then falls back at sol 213 on ice) and entry ok_share 0.8 puts all five between sol 62 and 92 (seed 2026 then makes 3 changes with a shortest gap of 35 sols, and seed 42 falls back at sol 153). The dwell sweep changes nothing because no gap on any seed is below 99 sols (spec 6.2 bound is 20). Of the exit parameters only the fall-back sol of seed 99 moves (170 to 178 across the exit-share sweep).

## on_sol timing

Measured alone on an otherwise idle machine after the seed runs finished (`pgrep godot` empty before each run), at the end of a 300-sol run, 2000 calls after 50 warm-up calls, state of `Ages`, `stats` age keys and the log restored before each call outside the timed region. Microseconds per call:

| seed (pop, beings, buildings at sol 300) | Ages.on_sol median / mean / p95 / max | Ages.sample median | Ages.family_mars_born median | Ages.decide median |
|---|---|---|---|---|
| 42 (164, 164, 53) | 367 / 397 / 684 / 997 | 208 | 111 (max 1919) | 10 |
| 7 (72, 72, 24) | 168 / 190 / 307 / 646 | 102 | 45 (max 1017) | 10 |

The spec expected "well under 50" us; the measured median is 367 us at pop 164 and 168 us at pop 72. The cost scales with the number of beings (sample loops over beings and buildings, `family_mars_born` loops over beings twice). It runs once per sol boundary.

## Observations (facts only)

- Seed 42: never settles in 300 sols. The ok share in the trailing window is at most 33 of 40 (needs 36); the last-3-ok clause fails on 168 of 257 Landing sols from sol 44. From sol 44 to 139 the not-ok sols are calm and rested failures (calm is the only failing clause on 12 sols in 51-100 and 6 in 101-150); from sol 140 to 300 ice is the main failing clause (80 failing sols, 70 of them the only failing clause). Family Mars-born count and habitats pass on every sol from sol 23 and 20.
- Seed 2026: Landing at sol 100 and 150 with only the ok-share clause failing (34 of 40 and 31 of 40 ok). The window reaches 36 at sol 216, after the ice failures of sols 161-193 age out; calm failed on 12 sols in 101-150.
- Seeds 7 and 1234 settle at 76 and 85, later than the spec's 44 to 55 estimate. Between sol 44 and settlement the only failing clauses are calm and rested (calm failed on 20 and 22 of the sols 1-50).
- Seed 99: settles at 75, then the ice clause fails on 106 sols from sol 157 (36 of 50 sols in 151-200); it falls back at sol 174 with cause ice and does not re-enter in 126 sols; shortage deaths on 16 sols in 225-286.
- Calm is the most frequently failing clause on four of five seeds (8.1% to 15.5% of sols) and in sols 1-50 it fails on 16 to 22 of the 46 sampled sols on every seed; at pop under 10 a single distressed being fails it (4 to 13 of the 11 to 24 sampled small-pop sols per seed). Spec 14 says calm and rested are expected near zero and that more than 10% failing before sol 120 means the threshold is wrong. Measured over sols 5-119 (115 sols): calm fails 29.6% (seed 42), 18.3% (7), 14.8% (99), 22.6% (1234), 26.1% (2026); rested fails 9.6%, 5.2%, 4.3%, 7.8%, 7.0%. Calm exceeds 10% on every seed; rested on none.
- The family Mars-born clauses (5 beings, 2 habitats) never block entry on any seed; both pass from sol 20 to 32 onward, before the first possible entry at sol 44. Family Mars-born (living parent) is 10 on seeds 7, 99, 1234, 2026 and 15 on seed 42 at sol 40.
- Rested: per-sol share minimum 0.429 to 0.5; it is the only failing clause on 0 to 3 sols per seed; rested_share_min 0.9 makes all five seeds never settle.
- The ice dip question: the within-sol ice minimum is lower than the boundary read. Sols whose in-sol minimum was under 2 ice-days: 94 (seed 42), 0 (7), 115 (99), 0 (1234), 29 (2026); on 14, 0, 9, 0, 4 of those the boundary read was ok, so the sample missed the dip (first such sols 154, 156, 160). All of them are in the ice-failing phases that start at sols 140, 157, 161. Sols whose in-sol ice minimum reached 0: 21 (42), 36 (99), 7 (2026).
- Shortage-death clause: 9, 0, 16, 0, 4 failing sols (seeds 42, 7, 99, 1234, 2026), all after sol 177, always together with ice failing.
- The power clauses (budget, offline, short) never fail on any seed; o2_net and food_net never fail. Oxygen and food stock clauses fail only on sol 5 on every seed.
- No seed flaps. Shortest gap between two changes anywhere is 99 sols; the 20-sol dwell is never the binding rule (it blocks 19 Landing sols on seed 99 after the fall back, all of them also failing the share clause).
- T10 (as defined in spec 12, from stats) with shipped values: first settlement in 40 to 150 on seeds 7, 99, 1234 (76, 75, 85); fails on seed 42 (never) and seed 2026 (216). Age changes at most 4 on every seed (0, 1, 2, 1, 1).
- on_sol cost is 168 to 367 us per call (median) depending on population, against the "well under 50 us" estimate in spec section 14.
- Probe cost: a 300-sol seed takes 6 to 16 minutes in the two-world form (the sim itself dominates; the probe adds a second world).

## Files

- `/home/user/eco-game-idea/station-zero/tools/age_probe.gd`
- `/home/user/eco-game-idea/station-zero/docs/balance/task-3-calibration.md`
- `/home/user/eco-game-idea/station-zero/docs/balance/task-3-calibration-data/` (seed_N.txt, seed_N.csv, seed_N.json, sweeps.md, timing_seed_42.txt, timing_seed_7.txt)
