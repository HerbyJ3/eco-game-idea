# Task 5 step 6: Council calibration probe results

Measured numbers only. Nothing was tuned: no file in `data/` or `sim/` was changed, the shipped values stand (both pulls 0.0, `dome.lean.base` 0.0). New code: `tools/council_probe.gd`. One edit to existing tooling: `tools/relationships_probe.gd` (below). Raw outputs (per-sol CSV, summary JSON with the per-sol rows, text reports, judge tables, hash and cost runs) are in `docs/balance/task-5-calibration-data/` (it has a `.gdignore`). Spec: `docs/specs/council.md` revision 4, section 12. Godot 4.5.stable, `data_hash` 274c8040aaceba4e on every run.

## Fix to the Task 4 probe (note for the report)
`tools/relationships_probe.gd` replayed the Council gate with `age == SETTLEMENT`, so under a live Council entry (age `council`) clause 1 read false and `settle_s` went stale. It now reads the Landing / not-Landing projection (any age but Landing counts as settled) and takes S from the latest `age_history` entry whose age is `settlement`. Probe-only; no sim or data change. Seed 7 was re-run through it afterwards and still passes R1 to R14.

## Commands
```
# five seeds, shipped values, 300 sols (4 in parallel, then the 5th)
godot --headless --path station-zero --script res://tools/council_probe.gd -- --seed N --sols 300 --tag base --out <abs>/docs/balance/task-5-calibration-data
# lever, each step its own override run, same seeds
... -- --seed N --sols 300 --tag lean_0.05 --param council.dome.lean.base=0.05 --out ...
... -- --seed N --sols 300 --tag lean_0.10 --param council.dome.lean.base=0.10 --out ...
# tables, replays, targets, flags from the stored JSON
... -- --judge <abs>/docs/balance/task-5-calibration-data --tag base      (also lean_0.05, lean_0.10)
# observer check and cost, run alone
... -- --hash --seed N --sols 300         ;   ... -- --seed N --sols 300 --tag cost_alone      (seeds 42 and 1234)
godot --headless --path station-zero --script res://tests/council_hash_proof.gd
```

## How it observes, and checks that it did not disturb the run
After every step the probe reads the world; it writes nothing. It swaps the world's Council for a subclass that times `on_step` and `on_sol` and calls the real code (state copied from the module). It recomputes the voice readings from `relationships.pairs` itself (every chosen-friend variant at once) and reads the module's `stance`, `lean_of`, `lean_terms_of`, `hard_share`, `_decide_entry_parts`.
- **Readings cross-check: exact.** On all five seeds the probe's trust and chosen series equal `stats.council.trust_by_sol` / `chosen_by_sol` (max difference 0.0), the lists have 301 entries each (= `pop_by_sol`), and the probe's four gate clauses equal the module's on every Settlement sol (0 mismatches).
- **Replay check: PASS.** `--hash` (the plain `balance_lib.run`, no probe) ends with the same digest (pop, births, deaths, `age_history`, whole `stats.council`) as the probe run: seed 42 `ea5190275431d465`, seed 1234 `0d097a54c4def804`; the cost-alone runs give the same digests. Table sha256 (16): seed 42 `330325504427720a`, seed 1234 `a46949d34368daa8`. T10 and T12 PASS on both.
- **Gate replay baseline = live.** The replay with shipped values gives the live first Council sol on all five seeds (115, 95, none, 160, 206).
- **Hash proof (`tests/council_hash_proof.gd`): all five seeds MATCH on all three checks** (drop `cn`: a96b8a9562fd75d0, a4968e2fcc48ec36, 2210719cf48d8612, 19437e397d1dff88, 6e7fe68477161196 = the Task 4 hashes; drop `cn` and `web`: the Task 3 hashes; drop `cn`, `web` and `age`: the Task 1 hashes). Full output: `council_hash_proof.txt`.
- **Projected ages equal Task 3's** on all five seeds (first Settlement sol 67, 58, 54, 65, 53; changes 2, 1, 2, 1, 1). The Council only relabels.

## Definitions used where the spec leaves room
- **Vote**: a meeting held while a proposal is open that was raised at an earlier meeting. The raising meeting and quiet meetings are not votes.
- **Divided vote** (C6): a vote at which yes share and no share are both at least `decide.divided_share` (0.25). C6 is also given for the first such vote of each proposal (the one that sets `divided`).
- **C5** is judged on logged lines (`stats.council.lines`: `divided`, `set_aside`, `set_aside_hard`, `set_aside_long`), "a divided or set-aside line".
- **C7** counts every `council_*` line (circles included) per 5 Council sols (`sols_in_age.council`); the figure without circles is also given. Both verdicts agree on every run.
- **FLOOR** reads each reading's minimum over the sols from S+30 (any age but Landing) to the end; **CEILING** the web minimum after the first entry.
- **Gate replays** are exact for the first Council entry: nothing the Council does feeds back into the sim, the Landing / not-Landing projection and the Settlement entries are the live ones. Later entries are not replayed.
- **Cost** is the wall time of the real hooks in the probe, in microseconds. Only the two runs made alone (seeds 42 and 1234) are used for C8; the other tables' cost columns come from runs sharing four cores and are not judged.


## Results on shipped values (300 sols, per seed)

Summary per seed (from the tables below and `seed_N_base.txt`):
| seed | pop end / max | Council entry | last clause passed | splits / fall-backs | sessions | raises | votes | set-asides | pledge | thirst deaths |
|---|---|---|---|---|---|---|---|---|---|---|
| 42 | 164 / 167 | sol 115 | web (settled 97, chosen 109, voices 59) | 0 / Landing at 213 (ice) | 19 | 2 (120, 175) | 7 | 2 (145 hard, 185) | none | 10 |
| 7 | 72 / 72 | sol 95 | chosen (95; settled 88, web 20, voices 63) | 0 / 0 | 41 | 3 (105, 195, 285; last open) | 27 | 2 (165, 255, both "left open too long") | none | 0 |
| 99 | 157 / 157 | never | none: chosen window never held while settled (0 of 120 Settlement sols), web held on 22 | 0 / Landing at 174 (ice) | 0 | 0 | 0 | 0 | none | 22 |
| 1234 | 142 / 142 | sol 160 | web (settled 95, chosen 155, voices 67) | 0 / 0 | 28 | 2 (165, 255; last open) | 21 | 1 (225, long) | none | 0 |
| 2026 | 156 / 157 | sol 206 | web and chosen (206; settled 83, voices 63) | 0 / 0 | 18 | 1 (211) | 12 | 1 (271, long) | none | 5 |

Votes counted from the meeting lists below; yes and no counts are of all voices, every vote is listed.

Council lines and what they said, by seed (kind: sol):
- 42: proposal 120, divided 125, set_aside_hard 145 ("the ice runs short"), proposal_again 175, divided 180, set_aside 185.
- 7: quiet 100, proposal 105, divided 140, set_aside_long 165, proposal_again 195, set_aside_long 255, proposal_again 285.
- 99: circles 104.
- 1234: circles 115, proposal 165, set_aside_long 225, proposal_again 255.
- 2026: circles 103, circles_again 203, proposal 211, set_aside_long 271.
Lines dropped by the cap: 0 on every seed.


### Crossings
| seed | projected sequence (sols) | Task 3 settle / changes | age_history (sol how) | Council entries (sol, how, last clause passed, onsets settled/web/chosen/voices) | splits | fall-backs from Council | changes |
|---|---|---|---|---|---|---|---|
| 42 | L@0 S@67 L@213 | 67 / 2 (match) | 0 landing/landing; 67 settlement/settled; 115 council/council; 213 landing/fell_back | 115 council: web (97/115/109/59; settled-clause wait 18) | [] | [213] | 1 |
| 7 | L@0 S@58 | 58 / 1 (match) | 0 landing/landing; 58 settlement/settled; 95 council/council | 95 council: chosen (88/20/95/63; settled-clause wait 7) | [] | [] | 1 |
| 99 | L@0 S@54 L@174 | 54 / 2 (match) | 0 landing/landing; 54 settlement/settled; 174 landing/fell_back | none | [] | [] | 0 |
| 1234 | L@0 S@65 | 65 / 1 (match) | 0 landing/landing; 65 settlement/settled; 160 council/council | 160 council: web (95/160/155/67; settled-clause wait 65) | [] | [] | 1 |
| 2026 | L@0 S@53 | 53 / 1 (match) | 0 landing/landing; 53 settlement/settled; 206 council/council | 206 council: web+chosen (83/206/206/63; settled-clause wait 123) | [] | [] | 1 |

### Voices over time (pop / voices / trust / chosen share at the sol)
| seed | sol 30 | sol 60 | sol 100 | sol 150 | sol 200 | sol 250 | sol 300 |
|---|---|---|---|---|---|---|---|
| 42 | 19 / 7 / 1.00 / 0.00 L | 27 / 12 / 0.67 / 0.00 L | 57 / 27 / 0.63 / 0.59 S | 82 / 62 / 0.56 / 0.44 C | 107 / 87 / 0.47 / 0.59 C | 142 / 119 / 0.61 / 0.61 L | 164 / 143 / 0.52 / 0.51 L |
| 7 | 12 / 7 / 1.00 / 0.00 L | 22 / 8 / 0.88 / 0.00 S | 32 / 22 / 0.86 / 0.73 C | 47 / 37 / 0.84 / 0.78 C | 47 / 47 / 0.91 / 0.91 C | 52 / 52 / 0.96 / 0.96 C | 72 / 52 / 0.96 / 0.96 C |
| 99 | 10 / 7 / 1.00 / 0.00 L | 29 / 7 / 0.71 / 0.00 S | 72 / 29 / 0.17 / 0.21 S | 97 / 77 / 0.27 / 0.44 S | 122 / 97 / 0.44 / 0.46 L | 139 / 119 / 0.40 / 0.45 L | 157 / 144 / 0.55 / 0.63 L |
| 1234 | 12 / 7 / 1.00 / 0.00 L | 27 / 7 / 0.86 / 0.00 L | 65 / 27 / 0.37 / 0.22 S | 102 / 72 / 0.51 / 0.51 S | 112 / 107 / 0.71 / 0.70 C | 142 / 112 / 0.61 / 0.63 C | 142 / 142 / 0.87 / 0.86 C |
| 2026 | 12 / 7 / 1.00 / 0.00 L | 26 / 9 / 0.89 / 0.00 S | 47 / 26 / 0.38 / 0.35 S | 78 / 52 / 0.27 / 0.29 S | 107 / 90 / 0.56 / 0.57 S | 129 / 112 / 0.66 / 0.69 C | 156 / 130 / 0.32 / 0.45 C |
(age letter: L landing, S settlement, C council)

### Trust discrimination (from sol 60) and flags FLOOR / CEILING
| seed | trust min / max | chosen min / max | min web since settled-30 | min chosen since settled-30 | min web after first entry | chosen pairs Mars-born+unrelated (end) | mean leak share | pairs turned to family (end / max) |
|---|---|---|---|---|---|---|---|---|
| 42 | 0.346 / 0.818 | 0.000 / 0.663 | 0.346 | 0.365 | 0.346 | 120 of 139 (0.86) | 0.70 | 5 / 8 |
| 7 | 0.643 / 0.962 | 0.000 / 0.962 | 0.682 | 0.519 | 0.682 | 259 of 351 (0.74) | 0.60 | 74 / 100 |
| 99 | 0.077 / 0.714 | 0.000 / 0.633 | 0.077 | 0 | -1 | 106 of 116 (0.91) | 0.81 | 4 / 7 |
| 1234 | 0.324 / 0.889 | 0.000 / 0.866 | 0.324 | 0.148 | 0.524 | 414 of 489 (0.85) | 0.71 | 38 / 38 |
| 2026 | 0.190 / 1.000 | 0.000 / 0.785 | 0.190 | 0.119 | 0.315 | 51 of 63 (0.81) | 0.60 | 2 / 17 |
FLOOR web (no seed's web reading ever below 0.50 after its 30 settled sols): clear
FLOOR chosen (no seed's chosen reading ever below 0.50 after its 30 settled sols): clear
CEILING (on every seed that enters, web never below 0.5 after the entry): clear

### Proposals
| seed | # | raised sol | proposer | again | votes | outcome (sol) | reason | hard | vote sols | mean lean at outcome: total = personal + size + means - hard + child |
|---|---|---|---|---|---|---|---|---|---|---|
| 42 | 0 | 120 | 11 | false | 5 | set_aside (145) | - | true | [125, 130, 135, 140, 145] | -0.239 = -0.059 + 0.068 + -0.031 - 0.236 + 0.019 |
| 42 | 1 | 175 | 76 | true | 2 | set_aside (185) | - | false | [180, 185] | -0.058 = -0.058 + 0.100 + -0.035 - 0.078 + 0.013 |
| 7 | 0 | 105 | 9 | false | 12 | set_aside (165) | - | false | [110, 115, 120, 125, 130, 135, 140, 145, 150, 155, 160, 165] | -0.010 = -0.063 + 0.011 + 0.042 - 0.000 + 0.000 |
| 7 | 1 | 195 | 10 | true | 12 | set_aside (255) | - | false | [200, 205, 210, 215, 220, 225, 230, 235, 240, 245, 250, 255] | 0.006 = -0.056 + 0.019 + 0.043 - 0.000 + 0.000 |
| 7 | 2 | 285 | 8 | true | 3 | - (-) | - | - | [290, 295, 300] | - |
| 1234 | 0 | 165 | 4 | false | 12 | set_aside (225) | - | false | [170, 175, 180, 185, 190, 195, 200, 205, 210, 215, 220, 225] | 0.119 = -0.022 + 0.132 + -0.003 - 0.000 + 0.013 |
| 1234 | 1 | 255 | 98 | true | 9 | - (-) | - | - | [260, 265, 270, 275, 280, 285, 290, 295, 300] | - |
| 2026 | 0 | 211 | 87 | false | 12 | set_aside (271) | - | false | [216, 221, 226, 231, 236, 241, 246, 251, 256, 261, 266, 271] | 0.109 = -0.001 + 0.134 + -0.031 - 0.000 + 0.007 |

### Meetings (sol: present / voices, yes, no; V = vote, R = raise or quiet meeting)
- 42 (19 meetings): 120R:13/47 y15 n15 125V:11/47 y15 n18 130V:10/52 y15 n22 135V:14/52 y15 n20 140V:15/57 y13 n30 145V:14/62 y8 n45H 150R:14/62 y6 n51H 155R:10/62 y8 n49H 160R:14/72 y12 n50 165R:14/72 y16 n38 170R:18/77 y21 n34 175R:15/77 y22 n33 180V:14/77 y23 n39 185V:16/82 y25 n44 190R:23/82 y15 n51H 195R:18/87 y12 n57H 200R:19/87 y14 n59H 205R:19/92 y27 n48 210R:17/92 y41 n29
- 7 (41 meetings): 100R:9/22 y6 n0 105R:8/22 y8 n1 110V:6/22 y7 n1 115V:7/25 y4 n2 120V:10/27 y5 n4 125V:10/27 y5 n8 130V:9/32 y6 n10 135V:8/32 y9 n6 140V:8/32 y9 n8 145V:8/37 y8 n9 150V:9/37 y6 n12 155V:10/37 y5 n14 160V:12/37 y4 n13 165V:15/37 y4 n13 170R:13/42 y6 n12 175R:14/47 y5 n12 180R:17/47 y5 n12 185R:11/47 y5 n12 190R:12/47 y5 n12 195R:18/47 y5 n13 200V:18/47 y5 n13 205V:17/47 y6 n12 210V:10/47 y6 n11 215V:12/47 y6 n11 220V:11/47 y6 n11 225V:10/47 y6 n14 230V:13/47 y6 n14 235V:20/47 y5 n13 240V:18/47 y6 n13 245V:21/52 y5 n15 250V:20/52 y4 n14 255V:21/52 y5 n14 260R:21/52 y5 n15 265R:22/52 y5 n14 270R:22/52 y5 n14 275R:18/52 y5 n14 280R:19/52 y5 n14 285R:17/52 y5 n14 290V:15/52 y7 n13 295V:13/52 y8 n12 300V:11/52 y8 n13
- 99 (0 meetings): 
- 1234 (28 meetings): 165R:17/82 y32 n19 170V:23/82 y30 n20 175V:16/87 y28 n19 180V:18/92 y27 n17 185V:17/97 y33 n15 190V:18/102 y38 n14 195V:19/107 y44 n14 200V:29/107 y44 n14 205V:34/107 y44 n14 210V:39/107 y42 n13 215V:44/107 y42 n12 220V:26/107 y41 n14 225V:18/107 y39 n14 230R:16/110 y41 n21 235R:20/112 y49 n19 240R:21/112 y44 n19 245R:15/112 y47 n18 250R:21/112 y52 n18 255R:39/112 y57 n13 260V:41/122 y57 n19 265V:17/122 y57 n18 270V:23/132 y55 n16 275V:16/132 y57 n19 280V:18/132 y58 n18 285V:25/137 y54 n22 290V:21/142 y61 n23 295V:33/142 y60 n21 300V:36/142 y61 n22
- 2026 (18 meetings): 211R:19/100 y59 n17 216V:21/100 y56 n18 221V:15/107 y64 n17 226V:24/107 y62 n16 231V:22/107 y56 n15 236V:21/107 y58 n17 241V:14/107 y56 n18 246V:14/112 y55 n24 251V:15/112 y58 n22 256V:17/112 y55 n21 261V:21/112 y55 n21 266V:18/112 y49 n26 271V:20/112 y49 n26 276R:19/117 y54 n27 281R:20/117 y56 n27 286R:19/127 y65 n25 291R:19/132 y61 n31 296R:21/131 y31 n67H

### Votes: lockstep and factions
| seed | sol | voices | yes | no | one side >= 0.95 | divided (both >= 0.25) | amb yes / no | caution yes / no | trait_ok | stance sign differs from lean | personal sd |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 42 | 125 | 47 | 15 | 18 | false | true (first) | 0.549 / 0.374 | 0.316 / 0.583 | true | 0.021 | 0.213 |
| 42 | 130 | 52 | 15 | 22 | false | true | 0.551 / 0.360 | 0.311 / 0.597 | true | 0.058 | 0.223 |
| 42 | 135 | 52 | 15 | 20 | false | true | 0.551 / 0.354 | 0.311 / 0.608 | true | 0.058 | 0.223 |
| 42 | 140 | 57 | 13 | 30 | false | false | 0.562 / 0.370 | 0.297 / 0.592 | true | 0.035 | 0.219 |
| 42 | 145 | 62 | 8 | 45 | false | false | 0.585 / 0.393 | 0.253 / 0.553 | true | 0.016 | 0.212 |
| 42 | 180 | 77 | 23 | 39 | false | true (first) | 0.534 / 0.359 | 0.326 / 0.598 | true | 0.091 | 0.226 |
| 42 | 185 | 82 | 25 | 44 | false | true | 0.535 / 0.366 | 0.320 / 0.589 | true | 0.073 | 0.225 |
| 7 | 110 | 22 | 7 | 1 | false | false | 0.519 / 0.344 | 0.342 / 0.595 | true | 0.000 | 0.177 |
| 7 | 115 | 25 | 4 | 2 | false | false | 0.559 / 0.355 | 0.310 / 0.603 | true | 0.040 | 0.182 |
| 7 | 120 | 27 | 5 | 4 | false | false | 0.545 / 0.351 | 0.318 / 0.620 | true | 0.037 | 0.190 |
| 7 | 125 | 27 | 5 | 8 | false | false | 0.559 / 0.360 | 0.296 / 0.594 | true | 0.000 | 0.190 |
| 7 | 130 | 32 | 6 | 10 | false | false | 0.538 / 0.354 | 0.310 / 0.602 | true | 0.094 | 0.190 |
| 7 | 135 | 32 | 9 | 6 | false | false | 0.511 / 0.354 | 0.357 / 0.618 | true | 0.031 | 0.190 |
| 7 | 140 | 32 | 9 | 8 | false | true (first) | 0.511 / 0.350 | 0.357 / 0.603 | true | 0.062 | 0.190 |
| 7 | 145 | 37 | 8 | 9 | false | false | 0.513 / 0.353 | 0.356 / 0.606 | true | 0.135 | 0.183 |
| 7 | 150 | 37 | 6 | 12 | false | false | 0.540 / 0.363 | 0.327 / 0.595 | true | 0.108 | 0.183 |
| 7 | 155 | 37 | 5 | 14 | false | false | 0.546 / 0.363 | 0.298 / 0.595 | true | 0.108 | 0.183 |
| 7 | 160 | 37 | 4 | 13 | false | false | 0.559 / 0.360 | 0.273 / 0.598 | true | 0.108 | 0.183 |
| 7 | 165 | 37 | 4 | 13 | false | false | 0.559 / 0.364 | 0.273 / 0.598 | true | 0.135 | 0.183 |
| 7 | 200 | 47 | 5 | 13 | false | false | 0.582 / 0.363 | 0.257 / 0.600 | true | 0.106 | 0.178 |
| 7 | 205 | 47 | 6 | 12 | false | false | 0.567 / 0.360 | 0.281 / 0.603 | true | 0.085 | 0.178 |
| 7 | 210 | 47 | 6 | 11 | false | false | 0.567 / 0.355 | 0.281 / 0.605 | true | 0.170 | 0.178 |
| 7 | 215 | 47 | 6 | 11 | false | false | 0.567 / 0.355 | 0.281 / 0.605 | true | 0.170 | 0.178 |
| 7 | 220 | 47 | 6 | 11 | false | false | 0.567 / 0.355 | 0.281 / 0.605 | true | 0.213 | 0.178 |
| 7 | 225 | 47 | 6 | 14 | false | false | 0.557 / 0.369 | 0.277 / 0.595 | true | 0.191 | 0.178 |
| 7 | 230 | 47 | 6 | 14 | false | false | 0.557 / 0.369 | 0.277 / 0.595 | true | 0.170 | 0.178 |
| 7 | 235 | 47 | 5 | 13 | false | false | 0.559 / 0.363 | 0.267 / 0.600 | true | 0.170 | 0.178 |
| 7 | 240 | 47 | 6 | 13 | false | false | 0.557 / 0.363 | 0.277 / 0.600 | true | 0.191 | 0.178 |
| 7 | 245 | 52 | 5 | 15 | false | false | 0.582 / 0.363 | 0.257 / 0.600 | true | 0.173 | 0.175 |
| 7 | 250 | 52 | 4 | 14 | false | false | 0.590 / 0.360 | 0.239 / 0.602 | true | 0.173 | 0.175 |
| 7 | 255 | 52 | 5 | 14 | false | false | 0.582 / 0.359 | 0.257 / 0.603 | true | 0.154 | 0.175 |
| 7 | 290 | 52 | 7 | 13 | false | false | 0.547 / 0.356 | 0.288 / 0.604 | true | 0.135 | 0.175 |
| 7 | 295 | 52 | 8 | 12 | false | false | 0.536 / 0.360 | 0.302 / 0.601 | true | 0.077 | 0.175 |
| 7 | 300 | 52 | 8 | 13 | false | false | 0.541 / 0.364 | 0.298 / 0.599 | true | 0.058 | 0.175 |
| 1234 | 170 | 82 | 30 | 20 | false | false | 0.505 / 0.331 | 0.387 / 0.625 | true | 0.098 | 0.191 |
| 1234 | 175 | 87 | 28 | 19 | false | false | 0.509 / 0.330 | 0.372 / 0.626 | true | 0.057 | 0.186 |
| 1234 | 180 | 92 | 27 | 17 | false | false | 0.521 / 0.327 | 0.354 / 0.633 | true | 0.065 | 0.187 |
| 1234 | 185 | 97 | 33 | 15 | false | false | 0.517 / 0.322 | 0.349 / 0.639 | true | 0.072 | 0.193 |
| 1234 | 190 | 102 | 38 | 14 | false | false | 0.523 / 0.319 | 0.340 / 0.643 | true | 0.059 | 0.206 |
| 1234 | 195 | 107 | 44 | 14 | false | false | 0.524 / 0.319 | 0.336 / 0.643 | true | 0.056 | 0.214 |
| 1234 | 200 | 107 | 44 | 14 | false | false | 0.525 / 0.319 | 0.334 / 0.643 | true | 0.056 | 0.214 |
| 1234 | 205 | 107 | 44 | 14 | false | false | 0.525 / 0.319 | 0.334 / 0.643 | true | 0.056 | 0.214 |
| 1234 | 210 | 107 | 42 | 13 | false | false | 0.527 / 0.318 | 0.330 / 0.644 | true | 0.075 | 0.214 |
| 1234 | 215 | 107 | 42 | 12 | false | false | 0.527 / 0.315 | 0.329 / 0.646 | true | 0.056 | 0.214 |
| 1234 | 220 | 107 | 41 | 14 | false | false | 0.528 / 0.322 | 0.329 / 0.642 | true | 0.056 | 0.214 |
| 1234 | 225 | 107 | 39 | 14 | false | false | 0.531 / 0.322 | 0.327 / 0.642 | true | 0.056 | 0.214 |
| 1234 | 260 | 122 | 57 | 19 | false | false | 0.512 / 0.314 | 0.349 / 0.643 | true | 0.107 | 0.220 |
| 1234 | 265 | 122 | 57 | 18 | false | false | 0.512 / 0.309 | 0.349 / 0.647 | true | 0.066 | 0.220 |
| 1234 | 270 | 132 | 55 | 16 | false | false | 0.514 / 0.302 | 0.340 / 0.648 | true | 0.068 | 0.216 |
| 1234 | 275 | 132 | 57 | 19 | false | false | 0.513 / 0.305 | 0.343 / 0.645 | true | 0.068 | 0.216 |
| 1234 | 280 | 132 | 58 | 18 | false | false | 0.510 / 0.304 | 0.346 / 0.644 | true | 0.061 | 0.216 |
| 1234 | 285 | 137 | 54 | 22 | false | false | 0.516 / 0.306 | 0.339 / 0.645 | true | 0.080 | 0.217 |
| 1234 | 290 | 142 | 61 | 23 | false | false | 0.511 / 0.307 | 0.350 / 0.644 | true | 0.092 | 0.214 |
| 1234 | 295 | 142 | 60 | 21 | false | false | 0.511 / 0.302 | 0.347 / 0.644 | true | 0.092 | 0.214 |
| 1234 | 300 | 142 | 61 | 22 | false | false | 0.508 / 0.304 | 0.349 / 0.645 | true | 0.070 | 0.214 |
| 2026 | 216 | 100 | 56 | 18 | false | false | 0.505 / 0.309 | 0.359 / 0.654 | true | 0.070 | 0.225 |
| 2026 | 221 | 107 | 64 | 17 | false | false | 0.513 / 0.306 | 0.350 / 0.654 | true | 0.047 | 0.234 |
| 2026 | 226 | 107 | 62 | 16 | false | false | 0.516 / 0.302 | 0.345 / 0.661 | true | 0.056 | 0.234 |
| 2026 | 231 | 107 | 56 | 15 | false | false | 0.525 / 0.298 | 0.333 / 0.659 | true | 0.047 | 0.234 |
| 2026 | 236 | 107 | 58 | 17 | false | false | 0.520 / 0.299 | 0.338 / 0.657 | true | 0.065 | 0.234 |
| 2026 | 241 | 107 | 56 | 18 | false | false | 0.523 / 0.302 | 0.334 / 0.652 | true | 0.065 | 0.234 |
| 2026 | 246 | 112 | 55 | 24 | false | false | 0.523 / 0.316 | 0.334 / 0.642 | true | 0.054 | 0.232 |
| 2026 | 251 | 112 | 58 | 22 | false | false | 0.519 / 0.310 | 0.339 / 0.646 | true | 0.054 | 0.232 |
| 2026 | 256 | 112 | 55 | 21 | false | false | 0.522 / 0.307 | 0.334 / 0.649 | true | 0.071 | 0.232 |
| 2026 | 261 | 112 | 55 | 21 | false | false | 0.522 / 0.307 | 0.333 / 0.649 | true | 0.071 | 0.232 |
| 2026 | 266 | 112 | 49 | 26 | false | false | 0.532 / 0.319 | 0.320 / 0.634 | true | 0.071 | 0.232 |
| 2026 | 271 | 112 | 49 | 26 | false | false | 0.532 / 0.320 | 0.319 / 0.634 | true | 0.045 | 0.232 |
votes pooled 67, lockstep votes 0 (0%); LOCKSTEP (more than half): clear
divided votes pooled 6, trait-consistent 6 (100%); first-divided-vote-per-proposal 3, trait-consistent 3
stance sign differs from lean (share of voices), median over votes 0.070; personal-term sd median over votes 0.213 (spec estimate 0.15)
pledges 0, size term above half the mean lean at each: []; SIZE-DOMINANT: n/a, no pledge

### Gatherings (largest voice gathering at one relationship tick per sol)
| seed | sols >= 60: count median / p90 / max | share of voices median / p90 / max | Council sols: count median / max | eligible meeting sols | unheld | unheld share | meeting size median / max | first raise after entry (sols) |
|---|---|---|---|---|---|---|---|---|
| 42 | 13 / 20 / 30 | 0.178 / 0.297 / 0.562 | 13 / 23 | 19 | 0 | 0.00 | 14 / 23 | 5 |
| 7 | 9 / 18 / 22 | 0.278 / 0.383 / 0.429 | 11 / 22 | 41 | 0 | 0.00 | 13 / 22 | 10 |
| 99 | 12 / 21 / 37 | 0.155 / 0.263 / 0.571 | - / - | 0 | 0 | - | - / - | no entry |
| 1234 | 15 / 27 / 44 | 0.185 / 0.308 / 0.429 | 18 / 44 | 28 | 0 | 0.00 | 21 / 44 | 5 |
| 2026 | 11 / 19 / 24 | 0.169 / 0.294 / 0.600 | 16 / 24 | 18 | 0 | 0.00 | 19 / 24 | 5 |
NOROOM (unheld share above 0.50 on any seed): clear
First-raise delay trigger: first raise under 6 sols after entry on 3 seeds (trigger at 3): TRIGGERED

### Lines
| seed | Council sols | lines by key | council lines | per 5 Council sols (all / without circles) | dropped by cap | rel + council share of log (flag 0.15) | council share |
|---|---|---|---|---|---|---|---|
| 42 | 98 | { "divided": 2.0, "proposal": 1.0, "proposal_again": 1.0, "set_aside": 1.0, "set_aside_hard": 1.0 } | 6 | 0.306 / 0.306 | 0 | 0.100 | 0.005 |
| 7 | 205 | { "divided": 1.0, "proposal": 1.0, "proposal_again": 2.0, "quiet": 1.0, "set_aside_long": 2.0 } | 7 | 0.171 / 0.171 | 0 | 0.143 | 0.015 |
| 99 | 0 | { "circles": 1.0 } | 1 | -1 / -1 | 0 | 0.103 | 0.001 |
| 1234 | 140 | { "circles": 1.0, "proposal": 1.0, "proposal_again": 1.0, "set_aside_long": 1.0 } | 4 | 0.143 / 0.107 | 0 | 0.125 | 0.004 |
| 2026 | 94 | { "circles": 1.0, "circles_again": 1.0, "proposal": 1.0, "set_aside_long": 1.0 } | 4 | 0.213 / 0.106 | 0 | 0.111 | 0.004 |

## Verdicts on the targets (as written, shipped values)
| # | target | measured | verdict |
|---|---|---|---|
| C1 | Council entered by sol 300 on at least 3 of 5 seeds | 4 seeds: 115, 95, 160, 206 (seed 99 never) | PASS |
| C2 | every entry at least 30 sols after the Settlement entry; every Council change at least `min_dwell_sols` after the previous entry | smallest entry-after-Settlement 37 (seed 7), 48, 95, 153; T12 PASS on seeds 42 and 1234 (balance run) and the probe's own check on all five | PASS |
| C3 | at most 4 Council changes | 1, 1, 0, 1, 1 | PASS |
| C4 | a pledge on at least 1 seed by sol 300 | no pledge on any seed | **FAIL** |
| C5 | a divided or set-aside line on at least 2 seeds | 4 seeds (42, 7, 1234, 2026) | PASS |
| C6 | at least 80% of divided votes: yes camp more ambitious and no camp more cautious | 6 of 6 divided votes (3 of 3 first-divided)| PASS (thin: the 6 divided votes are on 2 seeds, 42 and 7) |
| C7 | at most 1.0 Council lines per 5 Council sols on every seed | 0.31, 0.17, none (0 Council sols), 0.14, 0.21 (without circles 0.31, 0.17, -, 0.11, 0.11) | PASS |
| C8 | cost as in section 11 | see Cost: on_sol median at pop above 120 is 2,998 us (seed 42) and 4,173 us (seed 1234) against 3,000; max 6,162 and 9,713 us against 8,000; module share of the mean step 0.0041 and 0.0118 against 0.02 | **FAIL** on seed 1234 (median and max), seed 42 median passes by 2 us; step share PASS |

Flags (item D; they fail nothing):
| flag | reading | state |
|---|---|---|
| FLOOR, web | web reading falls below 0.5 after the 30 settled sols on 4 seeds (minimum 0.346, 0.077, 0.324, 0.190; seed 7 0.682) | clear |
| FLOOR, chosen (stop rule) | chosen reading falls below 0.5 after the 30 settled sols on 4 seeds (minimum 0.365, 0, 0.148, 0.119; seed 7 0.519) | clear, calibration was not stopped |
| CEILING | web minimum after the entry: 0.346, 0.682, 0.524, 0.315 (seeds 42, 7, 1234, 2026); below 0.5 on 2 of the 4 entering seeds (42, 2026) | clear. No split fired on any seed |
| SIZE-DOMINANT | no pledge, so no pledge to read | not evaluable (n/a) |
| LOCKSTEP | 0 of 67 votes with 0.95 on one side | clear |
| NOROOM | meeting-eligible Council sols with no meeting: 0 of 19, 41, 0, 28, 18 | clear |
| first-raise delay trigger | first raise 5 sols after entry on seeds 42, 1234, 2026 (7: 10); 3 seeds under 6 sols | **TRIGGERED** (trigger is 3 seeds). 5 sols is the smallest possible, the meeting interval |
| log share | relationship + Council lines 0.100, 0.143, 0.103, 0.125, 0.111 of all log entries logged (flag 0.15); Council lines alone 0.001 to 0.015 | under the flag |

Item 5 numbers (factions and spread), pooled over the 67 votes: median share of voices whose stance sign differs from their lean sign 0.070; median standard deviation of the personal term among voices 0.213 per vote (per-vote values in the Votes table), against the spec's estimate of 0.15.

Item 3 extra: of the chosen friend pairs at sol 300, the share whose two ends are both Mars-born and unrelated is 0.86, 0.74, 0.91, 0.85, 0.81; the lineage rule turned 5, 74, 4, 38, 2 pairs at the end (maximum over the run 8, 100, 7, 38, 17) from chosen into family.

## Cost (item 8; run alone, seeds 42 and 1234)
| seed | max pop | on_sol us, pop 60 to 80: n, median / p95 / max | pop above 120: n, median / p95 / max | peak (pop at least 0.9 of max): n, median / p95 / max | module share of the mean step: pop 60 to 80 / above 120 / whole run |
|---|---|---|---|---|---|
| 42 | 167 | 39: 1,132 / 1,721 / 1,760 | 89: 2,998 / 4,650 / 6,162 | 29: 3,520 / 5,956 / 6,162 | 0.0087 / 0.0041 / 0.0062 |
| 1234 | 142 | 24: 1,083 / 1,331 / 1,481 | 81: 4,173 / 7,181 / 9,713 | 71: 4,167 / 7,635 / 9,713 | 0.0042 / 0.0118 / 0.0099 |

The spec's estimate was 1 to 2 ms at pop 160. The parallel runs (not judged; they share four cores) gave medians above 120 of 6.6, 3.2, 7.6, 7.1 ms for 42, 99, 1234, 2026.

## The pre-agreed lever, `dome.lean.base` (spec 5.6)
C4 fails on the first calibrated run, so the lever applies. Each step is its own override run on all five seeds, same seeds, nothing else changed. Kept only if LOCKSTEP and SIZE-DOMINANT stay clear and C5 and C6 hold.
| run | entries | pledges | C4 | C5 | C6 | LOCKSTEP | SIZE-DOMINANT | kept? |
|---|---|---|---|---|---|---|---|---|
| base 0.00 | 115, 95, -, 160, 206 | none | FAIL | PASS (42, 7, 1234, 2026) | PASS 6/6 | clear | n/a | shipped value |
| +0.05 | unchanged | seed 2026 at sol 221 (raised 211, 2 votes, reason "personal") | PASS | PASS (42, 7, 1234) | PASS 4/4 | clear (0 of 60 votes) | **FLAGGED**: mean size term 0.122 against half the mean lean 0.1155 (mean lean 0.231 = 0.007 + 0.122 + 0.045 - 0 + 0.007) | **no** (flag) |
| +0.10 | unchanged | seed 7 at 110 (reason "personal"), 1234 at 195 (6 votes, "size"), 2026 at 221 ("size") | PASS | **FAIL**: seed 42 only | PASS 3/3 | clear (0 of 19 votes) | clear (size 0.000/0.119/0.122 against half of 0.189/0.248/0.281) | **no** (C5) |

At +0.10 the three seeds that pledge do so in two votes after the raise, without a divided or set-aside line; seed 42 is unchanged from base (hard share up to 1.0, set aside twice on the ice). Seed 99 does not enter at any value (the lever does not touch the gate). The shipped value stays 0.0; no other key was moved for C4.
Seed 7's first raise falls on sol 100 (5 sols after entry) at +0.05 and +0.10, against 105 at base.

## Gate replays (item 9; first Council entry sol; '-' = no entry by sol 300)
Readings: stored per-sol series, baseline = shipped. Full 24-cell chosen grid is in `judge_base.txt`.

| variant | 42 | 7 | 99 | 1234 | 2026 |
|---|---|---|---|---|---|
| live first_council_sol | 115 | 95 | - | 160 | 206 |
| baseline replay (must equal live) | 115 | 95 | - | 160 | 206 |
| trust_share_min 0.4 | 109 | 95 | - | 155 | 206 |
| trust_share_min 0.5 | 115 | 95 | - | 160 | 206 |
| trust_share_min 0.6 | - | 95 | - | 186 | 225 |
| settled_sols 20 | 115 | 95 | - | 160 | 206 |
| settled_sols 30 | 115 | 95 | - | 160 | 206 |
| settled_sols 45 | 115 | 103 | - | 160 | 206 |
| trust_ok_min 14 | 107 | 93 | - | 158 | 204 |
| trust_ok_min 16 | 115 | 95 | - | 160 | 206 |
| trust_ok_min 18 | - | 97 | - | 163 | 208 |
| web clause off (settled, chosen, voices) | 109 | 95 | - | 155 | 206 |
| chosen clause off (settled, web, voices) | 97 | 88 | - | 160 | 206 |
| chosen_share_min 0.3, friends_min 1, kin_generations 0 | 97 | 88 | - | 160 | 206 |
| chosen_share_min 0.4, friends_min 1, kin_generations 0 | 97 | 92 | - | 160 | 206 |
| chosen_share_min 0.5, friends_min 1, kin_generations 0 | 106 | 95 | - | 160 | 206 |
| chosen_share_min 0.6, friends_min 1, kin_generations 0 | - | 104 | - | 183 | 225 |
| chosen_share_min 0.3, friends_min 1, kin_generations 1 | 97 | 88 | - | 160 | 206 |
| chosen_share_min 0.4, friends_min 1, kin_generations 1 | 97 | 92 | - | 160 | 206 |
| chosen_share_min 0.5, friends_min 1, kin_generations 1 | 115 | 95 | - | 160 | 206 |
| chosen_share_min 0.6, friends_min 1, kin_generations 1 | - | 104 | - | 184 | 225 |
| chosen_share_min 0.3, friends_min 1, kin_generations 2 | 97 | 88 | - | 160 | 206 |
| chosen_share_min 0.4, friends_min 1, kin_generations 2 | 97 | 92 | - | 160 | 206 |
| chosen_share_min 0.5, friends_min 1, kin_generations 2 | 115 | 95 | - | 160 | 206 |
| chosen_share_min 0.6, friends_min 1, kin_generations 2 | - | 104 | - | 184 | 225 |
| chosen_share_min 0.3, friends_min 2, kin_generations 0 | - | 103 | - | 160 | 206 |
| chosen_share_min 0.4, friends_min 2, kin_generations 0 | - | 105 | - | 183 | 214 |
| chosen_share_min 0.5, friends_min 2, kin_generations 0 | - | 112 | - | 188 | 243 |
| chosen_share_min 0.6, friends_min 2, kin_generations 0 | - | 159 | - | 200 | - |
| chosen_share_min 0.3, friends_min 2, kin_generations 1 | - | 104 | - | 160 | 206 |
| chosen_share_min 0.4, friends_min 2, kin_generations 1 | - | 111 | - | 183 | 214 |
| chosen_share_min 0.5, friends_min 2, kin_generations 1 | - | 112 | - | 190 | 243 |
| chosen_share_min 0.6, friends_min 2, kin_generations 1 | - | 162 | - | 200 | - |
| chosen_share_min 0.3, friends_min 2, kin_generations 2 | - | 104 | - | 160 | 206 |
| chosen_share_min 0.4, friends_min 2, kin_generations 2 | - | 112 | - | 183 | 218 |
| chosen_share_min 0.5, friends_min 2, kin_generations 2 | - | 158 | - | 190 | 246 |
| chosen_share_min 0.6, friends_min 2, kin_generations 2 | - | 163 | - | 218 | - |

Facts from the replay table:
- Web clause off: entries move earlier only on seeds 42 (115 to 109) and 1234 (160 to 155). Chosen clause off: earlier on 42 (115 to 97) and 7 (95 to 88); unchanged on 1234 and 2026. Seed 99 never enters with either clause off alone.
- `entry.trust_share_min` 0.4 / 0.5 / 0.6: seed 42 109 / 115 / none, seed 1234 155 / 160 / 186, seed 2026 206 / 206 / 225, seed 7 95 throughout.
- `entry.settled_sols` 20 / 30 / 45: only seed 7 moves (95, 95, 103); the other entries are 18 to 123 sols after sol S+30.
- `entry.trust_ok_min` 14 / 16 / 18: 42 107 / 115 / none; 7 93 / 95 / 97; 1234 158 / 160 / 163; 2026 204 / 206 / 208.
- `entry.chosen_share_min` at `chosen_friends_min` 1: kin_generations 0, 1 and 2 give the same entry sol on seeds 7 and 2026 at every threshold; seed 1234 differs only at 0.6 (183, 184, 184); seed 42 differs only at 0.5 (kin_generations 0: 106, 1 and 2: 115) and at 0.6 (none at all depths). At `chosen_friends_min` 2 seed 42 never enters at any threshold; seed 7 enters 103 to 163 and seed 1234 160 to 218; seed 2026 206 to none.
- Depth 1 against 2 at `chosen_friends_min` 2 and share 0.5: seed 7 112 against 158, seed 1234 190 against 190, seed 2026 243 against 246.

## Facts for the lead designer (no recommendation beyond what the numbers show)
1. C4 fails on shipped values: no seed pledges. The votes that ran to an outcome set the dome aside after 12 votes ("left open too long") on seeds 7, 1234 and 2026, with the yes share of all voices at most 0.36, 0.52 and 0.61 over the Council term (carry needs 0.6 at two votes running) and the mean lean near zero on seed 7 (-0.015 to 0.116), 0.07 to 0.18 on seed 1234, -0.26 to 0.19 on seed 2026. Seed 42 sets the dome aside twice on the ice (hard share up to 1.0, mean lean down to -0.42).
2. The lever rule is not satisfied by either step: +0.05 gives one pledge but SIZE-DOMINANT is flagged by 0.0065 (0.122 against 0.1155) on that one pledge; +0.10 gives three pledges, flags clear, but C5 falls to one seed because those colonies pledge in two votes without dividing. Per the spec, no other key is moved for C4 on this evidence; the "on these seeds the colony never agrees" result with the tables above goes to the owner.
3. Seed 99 never enters (Settlement 54 to 174, then Landing to the end): the chosen window clause (16 of 20 readings at 0.5) holds on 0 of its 120 Settlement sols, the web clause on 22; its voices were 29 at sol 100 with web 0.17 and chosen 0.21. Seed 42 falls back to Landing at sol 213 on ice, 98 Council sols after entry, and does not re-settle.
4. Which gate clause binds: web last on seeds 42 and 1234, chosen last on seed 7, both together on 2026. The entry comes 7, 18, 65 and 123 sols after S+30 (seeds 7, 42, 1234, 2026). Web threshold 0.4 against 0.5: entries 6, 0 and 5 sols earlier on 42, 2026, 1234 (seed 7 unchanged); at 0.6 seed 42 has no entry, 1234 is 26 sols later and 2026 19 later.
5. The first raise comes at the minimum 5 sols after entry on 3 of 4 entering seeds (trigger for the first-raise delay is met).
6. The web reading falls below the 0.5 entry threshold after entry on 2 of 4 entering seeds (seed 42 to 0.346, seed 2026 to 0.315; the others stay at 0.524 and 0.682 or above), and the split rule (16 of 20 readings below 0.3, last 3 below) never fired.
7. Personal-term spread is 0.17 to 0.23 per vote against the 0.15 estimate; sway moves few signs (median 0.07 of voices).
8. Largest voice gathering per sol (sols from 60): median 13, 9, 12, 15, 11 voices, i.e. 0.18, 0.28, 0.16, 0.19, 0.17 of voices; largest 30, 22, 37, 44, 24. All eligible meetings were held where a Council existed.
9. Cost: on_sol median above pop 120 is 3.0 ms on seed 42 and 4.2 ms on seed 1234 (budget 3.0), max 9.7 ms on seed 1234 (budget 8.0); step share 0.004 to 0.012 (budget 0.02). Section 11's remedies (share the union-find with relationships, skip trust and sway where nothing reads them) were not built.
10. The housemate leak (item 3) is large: 74 to 91 percent of chosen pairs at sol 300 are both Mars-born and unrelated.

## Run 2: carry quorum (O6 = A, owner 2026-10-08)
**Change under test.** A vote carries when `yes / (yes + no) >= decide.carry_share` (0.6) and `yes / voices >= decide.carry_quorum` (0.35, new), exact by cross-multiplied counts with `CMP_EPS`; with `yes + no = 0` nothing carries. Reject bar, `carry_sessions`, `max_open_votes`, sway and every lean key are untouched. Data edited in the same step: `balance.on_sol_ms_max` 3.0 to 5.0, `balance.on_sol_ms_peak_max` 16.7 (new). Code: `sim/council.gd` `_vote`. Probe edited per spec 12.1 (C5 counting, FLOOR and CEILING windows, corrected SIZE-DOMINANT with the old reading printed, stance spread and undecided share per vote, whole boundary-step timing, web minimum and sols under 0.5 / 0.3 inside Council terms, C8 restated, byte-identical check via `--base`).

**Run.** One run, seeds 42, 7, 99, 1234, 2026, 300 sols, tag `quorum`, the five seeds made one after another so the cost figures are from runs made alone. Data: `docs/balance/task-5-calibration-data-run2/` (`seed_N_quorum.json/.csv/.txt`, `judge_quorum.txt`, `council_hash_proof.txt`). Base for comparison: `docs/balance/task-5-calibration-data/`.

### Byte-identical check (digest of pop, births, deaths, `age_history` and all of `stats.council`)
| seed | base digest | run 2 digest | result |
|---|---|---|---|
| 42 | ea5190275431d465 | ea5190275431d465 | identical |
| 7 | 4644c2e44dd97170 | 4644c2e44dd97170 | identical |
| 99 | edbb5348251c8241 | edbb5348251c8241 | identical |

Seeds 1234 and 2026 differ from base, as predicted. The probe digest equals the digest of the plain `balance_lib` replay on both (83820bcfb1007f89, 5b52dd2a5c6277c6).

### Pledges (prediction: 1234 at sol 195, 2026 at sol 221; both hit exactly)
| seed | raised | votes | pledged | yes / no / voices at the pledging vote | yes of those with a view | yes of all | undecided | mean lean = personal + size + means - hard + child | reason |
|---|---|---|---|---|---|---|---|---|---|
| 1234 | 165 | 6 | sol 195 | 44 / 14 / 107 | 0.76 | 0.41 | 0.46 | 0.148 = -0.022 + 0.119 + 0.044 - 0 + 0.007 | personal |
| 2026 | 211 | 2 | sol 221 | 64 / 17 / 107 | 0.79 | 0.60 | 0.24 | 0.181 = 0.007 + 0.122 + 0.045 - 0 + 0.007 | personal |

Previous vote on 1234: 38 / 14 / 102 (yes share of all 0.37, ratio 0.73): carried at 190 too (quorum 0.35 cleared by 0.02, as the spec said). Both pledges are undivided (`pledge` text), with aftermath (`aftermath_still`, doubters Mero-90 and Sax-42) and the after-pledge line. Seed 7 (small colony, 62 percent undecided, yes 4 to 9 of 22 to 52) and seed 42 (ice) are unchanged. After sol 221 on 2026, yes falls to 31 of 131 by sol 296 (hard share), and the pledge stands.

### Spread and undecided (per vote; full table in `judge_quorum.txt`)
| seed | undecided share at votes | stance sd at votes | personal sd at votes |
|---|---|---|---|
| 42 | 0.15 to 0.33 | 0.20 to 0.26 | 0.21 to 0.23 |
| 7 | 0.47 to 0.76 | 0.13 to 0.17 | 0.175 to 0.19 |
| 1234 | 0.39 to 0.52 | 0.18 to 0.22 | 0.19 to 0.21 |
| 2026 | 0.24 to 0.26 | 0.23 to 0.24 | 0.23 |

### Targets
| # | Result |
|---|---|
| C1 | PASS: entries on 42 (115), 7 (95), 1234 (160), 2026 (206); 99 never enters |
| C2, C3 | PASS (T12 PASS on 1234 and 2026 in the replay; the other seeds are unchanged from base) |
| C4 | PASS: pledges on 1234 (195) and 2026 (221) |
| C5 (12.1 definition: divided, set_aside, set_aside_hard, pledge_divided) | PASS at the minimum: seeds 42 and 7. Seed 7 also logs `set_aside_long` twice (a stalemate, reported not counted) |
| C6 | PASS (thin): 6 of 6 divided votes trait-consistent, 3 of 3 first-per-proposal (seeds 42 and 7 only, as in base) |
| C7 | PASS: 0.17 to 0.32 per 5 Council sols (0.14 to 0.31 without circles); seed 99 has no Council sols, one circles line in 120 Settlement sols (within `lines.circles_max`) |
| C8 (restated) | PASS, run alone: median `on_sol` above pop 120 of 2,330 / 2,164 / 3,050 / 2,181 us on seeds 42 / 99 / 1234 / 2026 (limit 5,000); max 5,838 / 4,539 / 7,248 / 4,965 us (limit 16,700); share of the mean step 0.0036 / 0.0031 / 0.0108 / 0.0092 (limit 0.02). Seed 7 never exceeds pop 120 |

Whole boundary step (`world.step()` on sol-boundary steps), max: 15.3 ms (seed 42), 7.0 (7), 13.5 (99), 15.3 (1234), 11.3 (2026) ms; at pop above 120 the median is 4.7 to 5.8 ms. The 16.7 ms trigger for the remedies of 11.1 is **not** met, with 1.4 ms of margin on seeds 42 and 1234.

### Flags (12.1 definitions)
- FLOOR: clear on both readings. Gate-live window (S+30 to first entry): web minimum 0.432 (42), 0.864 (7), 0.077 (99, 90 sols), 0.324 (1234), 0.190 (2026); chosen minimum 0.500, 0.550, 0, 0.148, 0.119. The stop rule on the chosen reading is not raised.
- CEILING: clear. Web minimum inside Council terms: 0.346 (42, 57 of 98 sols under 0.5), 0.682 (7), 0.524 (1234), 0.315 (2026, 32 of 95 sols under 0.5). Sols under 0.3 inside Council: 0 on every seed.
- SIZE-DOMINANT (corrected, size term at least one sd of the personal term at every pledge): **clear**. Size 0.119 against sd 0.214 (1234) and 0.122 against 0.234 (2026), 0.56 and 0.52 of an sd. Old reading (size above half the mean lean): FLAGGED on both pledges, printed for the record; it fires on any pledge, as 12.1 says.
- LOCKSTEP: clear (0 of 42 votes with 0.95 of voices on one side). NOROOM: clear (no eligible sol without a meeting). First-raise delay trigger: met (first raise 5 sols after entry on seeds 42, 1234, 2026; 10 on seed 7); not built, as decided.

### Hash proof and tests
- `tests/council_hash_proof.gd`: all five seeds MATCH on all three checks (drop cn, drop cn and web, drop cn, web and age), same hashes as before. The Council stays hash-neutral.
- `tests/test_council.gd`: 112 tests, 1013 checks, 0 failures (3 new tests and the quorum sanity rule, test 10 and 17).
- Full suite: 611 tests, 42,432 checks, 6 failures, all known: `test_view_council` 19b / 19c / 19d (step 9, five checks) and the host-speed `test_view_model::test_perf_perf` (median 2.09 ms against 2.0 ms). The second host-speed timing test passed on this host.

### Verdict under option A's rule
Keep rule (all of): C4 pass; C5 pass on the corrected definition (at its minimum, 2 seeds); C6 holds; LOCKSTEP clear; SIZE-DOMINANT (corrected) clear; T12 and hash proof pass; seeds 42, 7, 99 byte-identical. **Every condition holds: KEEP.** The carry change and `decide.carry_quorum` 0.35 stay. No other key was moved.

Caveats (as stated in O6): the quorum 0.35 was fitted after seeing the votes of these five seeds, and seed 1234 clears it by 0.02 at its pledging votes (0.37 at sol 190, 0.41 at sol 195). C5 passes at its minimum. Both pledges are undivided and in the growth years (pop 107 to 112). Headline beats on the five seeds: agreement on two (1234, 2026), waiting on one (7), the ice on one (42), no Council on one (99).
