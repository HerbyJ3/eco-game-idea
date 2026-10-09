# Lifecycle calibration: horizon, restated targets, measurement plan

Status: design, docs only. Nothing in `sim/` or `data/` changes here. Every number below is an ESTIMATE (E) until a run measures it. Written 2026-10-09 by the lead game designer after the owner decision to keep the real calendar lifecycle (`docs/specs/lifecycle.md`) and re-calibrate with a longer horizon and lifecycle-aware targets. Facts come from `docs/balance/lifecycle-rebaseline.md` (measured, 300 sols, five seeds) and from reading `sim/lifecycle.gd`, `data/lifecycle.json`, `data/colony.json`, `data/ages.json`, `data/council.json`, `sim/world.gd` (`_birth_phase`, `_deliver_births`, `_create_newborn`), `sim/colony.gd`, `sim/council.gd`.

Design review: the three assistant designers were not run for this document. It is a re-baselining of numbers, not a new mechanic, and the owner questions in section 7 are where their lenses would matter; the main session may run them on those. Lens notes are marked inline (Wright, Barone, Korppoo) as my own application of their published approaches, not their opinions.

## 1. Lifecycle arithmetic that fixes the horizon

Constants: 1 sol = 24.6597 h; a Gregorian year = 8765.8 h (E, 365.2425 d) = about 355.5 sols; 9 months = about 267 sols (measured: births at sol 280 to 292); 18 years = 18 x 355.5 = **about 6,400 sols**; 13 years = 4,620; 3 years = 1,070; 1 year = 355.5. Sim step is 0.05 h (493 steps per sol), so 300 sols = 148k steps and 7,200 sols = 3.5M steps.

Consequences, in order:

1. **Generation 0 is the whole colony for about 6,700 sols.** Founders conceive in the first ~30 sols, the first Mars-born arrive at sol ~285 and become adults at about sol 285 + 6,400 = **~6,700**. Until then labour, construction, EVA, mining, conception and Council voices are the founders only (7, fewer after deaths; there is no old-age death in the code, so founders do not leave by age).
2. **Population grows in pulses, linearly, not exponentially.** Only adults conceive and a pregnant parent cannot conceive again until delivery, so each founder bears at most one child per ~267 sols (plus the wait for the next conception check, normally a few sols, since `can_conceive` has no postpartum rest beyond the 1-sol per-home cooldown). Growth is about +7 per ~270 sols at most, gated by housing: `birth_capacity` = 5 per online habitat + 2, and every pending pregnancy reserves a place. With two habitats the capacity is 12, so at most 5 pregnancies can be pending beside 7 founders. This matches the measured 3 to 5 births on every seed (and is why the first cohort size, hence Settlement timing, hinges on how many habitats are online at sol ~30). To verify in the probe; I did not read the starting layout.
3. **The workforce does not grow with the population.** Babies and children rest and take indoor trips; they consume air, water and food (`consumption` is per being) but add no construction, mining or EVA hours for 18 years. A colony of 40 people on 7 workers is a different economy from the old 160 on 160. Founder deaths are permanent labour loss until sol ~6,700. This is the new central balance risk and none of T1 to T12 watches it.
4. **Settlement (5 Mars-born in 2 homes) needs births, not adults**, so it arrives with cohort 1 (~sol 285 to 300) if that cohort has 5 members and else with cohort 2 (~sol 550 to 600, E). Mars-born babies count.
5. **Council needs `voices_min` 12 adult voices** (`data/council.json` entry.voices_min 12; `session.min_voices` 5). With 7 founders it can never be met before Mars-born adults exist: **sol ~6,700 at the earliest**, and 12 needs five Mars-born adults, so more like ~6,700 to 7,000. The Council text `circles_few` ("too few grown hands for a council") already tells that story during Settlement. The rebaseline's "Council never" is therefore not a 300-sol artefact; it is the shipped rule meeting the shipped calendar.

## 2. Standard horizon

Three tiers. Run cost is the constraint (section 5), and each tier answers a different question.

| tier | horizon | what it is for | runs on |
|---|---|---|---|
| **Smoke** | **300 sols** (kept) | Pre-birth structure: founders live, power, air, food, ice, energy, determinism, hash chains, cost. Every task and every code change. Not a balance judge for anything that involves births, ages, relationships or Council | five seeds, twice, as now |
| **Standard (new)** | **1,500 sols** (about 4.2 years; 5 birth cohorts at ~285, ~550, ~820, ~1,090, ~1,360) | The lifecycle-aware targets of section 3: housing keeping ahead, Settlement timing, fall-backs, the economy of workers versus dependants, relationships among a growing child group, log silence. Judged per cohort rather than per sol | five seeds, twice for the final configuration only |
| **Generational (new)** | **7,200 sols** (about 20 years: first Mars-born adults at ~6,700, 500 sols of second-generation adults) | The one question the lifecycle makes unavoidable: when do Mars-born adults arrive, and does anything (Council voices, conception by Mars-born, labour) work when they do. Cost at large pop (R8, C8) | one seed first (42), then at most two more, background run, once per question |

Why 1,500 and not 2,000 or 3,000: 1,500 contains five cohorts (enough for a per-generation median, the old ">= 3 of 5 seeds" logic needs repeats of a pattern), three-plus Settlement-dwell windows (`min_dwell_sols` 20) after a late entry, and it is the longest horizon whose per-seed cost stays a coffee-break (section 5). 3,000 would add cohorts 6 to 10 of the same pulse but still contain no adult Mars-born, so it buys little for 2x the cost; the next qualitatively new event after ~1,500 is sol ~6,700. Hence a short standard and a rare long generational tier, and nothing in between. Barone lens: a readable routine is a few seasons of repetition (a pulse of babies and a quiet stretch); Korppoo lens: the cohort is the unit the player can see and reason about, so the targets are per cohort.

Fast alternative for Council logic only (diagnostic, not a target): a probe override of `lifecycle.adult_age_years` to about 4 (and teen/child scaled) to exercise Council, voices and Mars-born labour inside ~2,000 sols. It would run a different game (children working at 4), so it may be used only to test mechanisms (does a vote hold with 12 voices, does the quorum fit survive) and its numbers never become targets. Needs the owner's nod only because it touches `data/lifecycle.json` in a throwaway data directory; recommend yes (section 7, question 3 folded in).

## 3. Every existing target: keep, restate or retire

Notation: "Std" = standard 1,500-sol horizon; "adults" = beings past their 18th birthday. All restated numbers are E. Old values in parentheses.

### 3.1 Balance targets T1 to T12 (`tests/balance_run.gd`)

| target | verdict | restatement and reason |
|---|---|---|
| T1 survival (min pop >= 5, final pop reported) | **Restate** | Min **adults** >= 4 at every sol of the Std run, and final pop >= 7. Total pop no longer shows labour; adults do. Seed 7 lost 3 to thirst at the end of 300 sols and has 6 voices, so this can fail for real |
| T2 deaths (unexplained 0; causes reported) | **Keep** unexplained 0; **add** founder deaths <= 2 of 7 by sol 1,500 per seed (E), each reported with cause | A founder is irreplaceable for ~6,400 sols. The rule is a design target for the ice pressure policy: pressure is allowed, but a colony that loses its workers does not recover. Thirst deaths among children are reported separately |
| T3 births (first birth, at_capacity 0, cooldown_violations 0, pop@30/100/300 windows) | **Restate** | Keep the invariants at_capacity 0 and cooldown_violations 0. First birth sol in **265 to 320** (measured 280 to 292). Replace pop@30/100/300 with pop at 300 >= 9, **pop at 1,500 between 25 and 80** (E: linear +7 per ~270 sols gives ~42), and **births per cohort >= 3** on every cohort window of 270 sols after the first. Report housing: share of sols with capacity - (pop + pending) <= 0 |
| T4 resources (O2/food mins; ice pressure reported, not failure) | **Keep** | Same wording: dry ice is pressure, not failure. Add the per-capita view: min ice per being and thirst deaths per 1,000 being-sols, so growing pop does not hide a trend. Ice-dry windows reported per cohort |
| T5 power (<=10 percent demand>supply steps, <=2 shorts/sol, max offline <=24.7 h, first new reactor <= sol 15) | **Keep** structure; run over Std | Seed 2026 fails (max offline 254 h). Not a calibration change; a probe question (section 4, Q9). Judged at Std because later growth adds demand |
| T6 construction crew-limited share (>= 2 percent, 4 of 5 seeds) | **Restate** | The old figure proved that crew mattered; at 57 to 77 percent it now passes trivially. Restated to what it was meant to protect: **housing keeps ahead of births** (no cohort waits on a missing habitat for > 60 sols, E) and **buildings completed per 270 sols >= 1** (E). Keep crew-limited share as a reported number |
| T7 traffic (trips 853 to 2394; exhausted; turn_backs_air 0; reachable >= 2 on 95 percent of samples) | **Restate** trips; keep the rest | Trips per **adult**-sol (measured 203 to 241 trips per 300 sols on 7 founders = 0.10 to 0.115). Window 0.05 to 0.30 (E), exhausted turn-backs per adult-sol reported. turn_backs_air 0 and reachable >= 2 stay as they were |
| T8 energy (avgE 40 to 90, asleep 5 to 30 percent, max sleep <= 18 h) | **Restate** | Computed over **adults only**; all-beings reported beside it. Babies and children "rest" by rule, so asleep% over all beings drifts up with the child share and would fail for a reason that is not about energy |
| T9 determinism | **Keep** | Run twice and `cmp` at Smoke on every change; at Std for the final configuration of each task |
| T10 ages (Settlement sol 40 to 150; <= 4 changes) | **Restate** | Settlement entry **265 to 700** on at least 4 of 5 seeds at Std (the lower bound is the fifth birth; the upper bound is cohort 2 plus dwell), at most **4 age changes** over Std, fall-backs reported with cause. A seed with no Settlement by 1,500 is a failure of the colony or of the family rule, not a pass (question Q1) |
| T11 relationships (lonely_share 50-reading mean <= 0.35, plus first-friendship clause) | **Restate** | Judged on a **count**, not a share, while pop < 20: no more than 2 adults with `friend_count` 0 on the last 50 readings; at pop >= 20 the old 0.35 share on the last 50 readings. Reason: with 9 to 10 beings one person moves the share by 0.1 (seeds 7, 1234). Question for the probe: do babies and toddlers form bonds? If not, lonely share must be computed over those who can (toddler and up) |
| T12 Council structure (dwell >= 30 after Settlement; <= 4 council changes) | **Keep** as structural, vacuous until a Council exists | Add the new invariant: **no Council entry while adult voices < `voices_min`** (a test-level check, already implied by the rule) |

### 3.2 Relationships probe R1 to R14 (`tools/relationships_probe.gd`)

| target | verdict | restatement and reason |
|---|---|---|
| R1 kin newborns' median birth-to-first-friend wait <= 30 sols | **Restate** | Pool kin newborns over all cohorts at Std; need **>= 8 resolved** newborns to judge (else report only; at 300 sols it was 1 to 5, not comparable). If babies cannot form bonds until toddlerhood, measure from the first birthday and say so. Wait <= 30 sols stays (E) |
| R2 first relationship line before sol 30 | **Keep** | Passes through crew lines (unchanged) |
| R3 lonely mean | **Restate** | Same as T11 |
| R4 friends_mean in 1.0 to 15.0 at the end | **Restate** | Judged at sol 1,500 over beings who can bond; keep 1.0 to 15.0 (E). Seed 1234's 1.00 at 300 is at the bound; probe measures where it goes |
| R5 / R14 dropped events < 5 percent / 0 dropped friend events | **Keep** | Queue guards, scale-independent |
| R6 capped-kind lines >= 1.0 per 5 sols, sols 20 to 299 | **Restate** | Measured 0.11 to 0.21 and the cause is tiny pop (few pairs), not a broken log. Replace with a **silence guard**: longest gap between any life or relationship line (including `pregnant` and `born`) <= 30 sols (E), and the old rate reported at pop >= 20 (>= 1.0 per 5 sols, kept as the ceiling for the larger colony). Korppoo: the log is how the player learns anything; a 267-sol pregnancy with no line at all is the failure to guard |
| R7 warmest third has more friends than the coldest | **Keep** | Judged at Std, when n >= 12 |
| R8 tick cost (median < 8 ms at pop above 120) | **Keep**, evaluated at the Generational tier | Pop above 120 is not reached at Std (E ~42). The cost claim for a large colony is only testable there or by a synthetic large-pop fixture |
| R9 pull-run guard (not shipped) | **Keep** as written | Unchanged, unused |
| R10 selectivity ratio >= 2.0 | **Restate** | Report only below pop 25; judged >= 2.0 at pop >= 25 (E). Measured 1.50 to 2.33 at pop 9 to 12, dominated by sample size |
| R11 coldest-third mean <= 10.0 | **Keep** | |
| R12 first newcomer line >= sol 25 (judged), by sol 55 (reported) | **Restate** | Lower bound: >= first birth sol. Upper bound reported: first birth + 120 sols (measured 83 to 250 absolute) |
| R13 `found_friend` per 5 sols over sols 150 to 299 <= 3.0 / ratio <= 1.0 | **Restate** window | Over the last 300 sols of Std (1,200 to 1,499). Ceiling kept |

### 3.3 Council probe C1 to C8 and Council quorum (`tools/council_probe.gd`)

| target | verdict | restatement and reason |
|---|---|---|
| C1 entered by sol 300 on >= 3 of 5 seeds | **Retire** at Smoke and Std; **restate for Generational**: entered by sol 7,200 on the probed seeds, with entry sol >= first Mars-born adult sol (E 6,700) unless the owner retunes `voices_min` (Q2) | By the arithmetic of section 1 no Council can exist before adult Mars-born. Failing C1 at Std would measure the calendar, not the Council |
| C2 entry >= 30 sols after Settlement; dwell | **Keep** structural | Vacuous until a Council exists |
| C3 <= 4 Council changes | **Keep** | Same |
| C4 a pledge on >= 1 seed | **Retire at Std**, carry (O6 still open) to Generational | A pledge needs a vote needs a Council |
| C5 divided or set-aside line on >= 2 seeds | **Retire at Std**, carry to Generational | Same |
| C6 factions follow personality at 80 percent | **Retire at Std**; carry | Undefined with no divided vote |
| C7 Council lines <= 1.0 per 5 Council sols | **Keep**, vacuous | |
| C8 cost | **Keep**, evaluated at Generational | Needs pop above 120 or the synthetic fixture |
| Council quorum fit (`decide.carry_quorum` 0.35, seed 1234 margin 0.02) | **Retire** the old fit; reopen at Generational | The fit was made on pop 72 to 164 voices; with 7 to 12 voices, 0.35 is 3 or 4 voices and `session.min_voices` 5 dominates. Re-fit only once Mars-born voices exist. Do not touch the number now |
| Circles lines (`circles_few`, `circles_max` 2) | **Keep**, new check | Over Std, on every seed that reaches Settlement, the "too few grown hands" story is told at least once and not more than `circles_max` per term |

### 3.4 Hash chains

The drop-column chain (Tasks 1 to 5) is reset at e1f2bdd (rebaseline section 2). It stays at Smoke (300 sols) as the cheap proof that observer modules do not move the Task 1 columns. A Std-horizon hash is recorded once per seed for the final configuration of a task, not in every proof, because of cost.

### 3.5 New targets the lifecycle needs (none existed)

| id | target (E) | why |
|---|---|---|
| L1 | **Adult floor.** Adults >= 4 at every sol of Std, every seed | Section 1 point 3: the colony's only labour |
| L2 | **Dependant ratio guard.** (children under 18) / adults <= 6 at every sol of Std (E; ~42 pop gives 5) and the resource trend (ice, food per being) not falling over the last 2 cohorts | Pulsed growth with 7 workers; a colony that grows itself into thirst is the "ice pressure" design, but not past the point of no return |
| L3 | **Cohort regularity.** The conception sols of the first cohort span <= 60 sols (E) and the second-cohort births are at least 40 percent of first-cohort births | The pulse is intended; a single pulse followed by silence is not (question Q4) |
| L4 | **Housing lead.** Online habitats x 5 + 2 >= pop + pending at 90 percent of Std sols | `birth_gates_ok` capacity is the actual growth brake |
| L5 | **Stage counts consistent.** `Lifecycle.counts` sum to pop on every sampled sol; no being older than its stage allows | Structural, test-level |
| L6 | **Mars-born adulthood event** (Generational only): first Mars-born adult sol within 6,350 to 6,750 | Proves the calendar arithmetic of section 1 in the sim, not just in the spec |

## 4. Tunables suspected of needing retuning (questions for the probe; nothing is changed)

| # | tunable (file) | current | question the probe must answer, with its readout |
|---|---|---|---|
| Q1 | `entry.mars_born_min` 5 and `mars_born_homes_min` 2 (`ages.json`) | 5, 2 | Does Settlement arrive in cohort 1 or cohort 2, and is that spread across seeds (290 vs ~600) acceptable? Readout: Settlement sol, `family_mars_born` per sol, births in cohort 1 per seed. Note the family count is births, not adults, so the rule is plausible for the calendar; the suspect is cohort-1 size (capacity 12 caps it at 5 with two habitats) |
| Q2 | `entry.voices_min` 12 (`council.json`), `session.min_voices` 5 | 12, 5 | With only 7 founder voices, Council cannot start for ~6,700 sols. Which minimum yields a Council in the founder era without voting by 3 people? Readout: voices over time, and a diagnostic run with voices_min 7 and 5 in a throwaway data dir at Std (not a shipped change; owner question 2) |
| Q3 | `birth.base_chance` 0.08, `warmth_coef` 0.14, `check_interval_h` 4 | | How tightly do founders conceive? If all conceive within ~20 sols the first cohort is one day-wide pulse. Readout: conception sol histogram, birth sol histogram, interbirth interval. Related: there is no postpartum rest beyond `cooldown_sols` 1 per home, so a mother reconceives within sols of delivery |
| Q4 | `birth.cooldown_sols` 1 and conception cooldown (`Lifecycle.conception_cooldown_over`) | 1 sol | Does the per-home conception cooldown spread conceptions at all, or does the 1-sol value make it irrelevant against a 267-sol gestation? Readout: gap between consecutive conceptions in one home |
| Q5 | `habitat_capacity` 5, `capacity_bonus` 2 (`colony.json`) | 5, 2 | Housing is the growth brake. Is capacity the binding gate at Std (L4) or are resources? Readout: reason for each non-conception check, if the probe can count the failing gate |
| Q6 | `consumption.*_per_being` (children eat like adults) | 0.05 O2, 0.035 food, 0.01 ice per being per hour | Do dependants make the economy unwinnable for 7 workers? Readout: L2, per-capita stocks, thirst deaths by stage. Candidate (not now): a stage-scaled consumption. That is a design change for the owner, so it would come as a separate spec |
| Q7 | `ice_per_being` target 8 and mining demand | 8 | Does the mining crew (7 adults) keep ice up as pop doubles? Readout: ice/target, mining trips per adult-sol |
| Q8 | Lonely/friend thresholds for small colonies (relationships) | | Do infants bond? Readout: bond creation by stage |
| Q9 | Seed 2026 power: max offline 254 h | | Is it a lack of builders (adult-only construction, 7 builders) or a layout accident? Readout: power timeline, builder availability, `first new reactor sol` |
| Q10 | Founders' age at landing and absence of old age | | Founders keep their Earth birth records and never die of age; at 6,700 sols they are ~18 years older. Is that acceptable for the player's reading of the colony? Readout: founder ages at sol 6,700 (no code needed). Not a tunable; flagged |

Rule: none of these is changed before the baseline measurements of section 5 step 1 are in; then at most one per run.

## 5. Measurement plan

### 5.1 Wall-time estimates (E)

Facts: owner-reported "a few minutes per seed" at 300 sols today; old runs at 300 sols with pop up to 164 took 70 to 207 s per probe seed (`docs/balance/task-5-lonely-run-data/*.txt`, "wall" lines), and `docs/perf` shows a step at pop above 120 costing ~8 ms with the relationships tick. The new colony is tiny for most of the run, so per-step cost is low, but the probes (relationships, council) add their own per-sol work. I take **2 to 4 minutes per 300 sols per seed** as the base rate at pop ~10, rising with pop.

| tier | steps | per seed, one run (E) | five seeds, 4 in parallel | note |
|---|---|---|---|---|
| Smoke 300 sols | 148k | 2 to 4 min | 5 to 10 min | as today |
| Std 1,500 sols | 740k | **12 to 40 min** (pop up to ~40 raises the cost 2x) | 25 to 80 min | run twice for the final configuration: double |
| Generational 7,200 sols | 3.5M | **1.5 to 5 h** (pop 100 to 170 at the end; relationships cost grows with pairs) | one seed 1.5 to 5 h | background only; may need a stripped probe (no table, no Council hooks) to be bearable |

Parallelism is limited by the host's cores (not read; the rebaseline ran four in parallel). The balance run writes a row every 30 sols, so Std is 50 rows; the `head -c 200000` guard in the standard command should be checked against the longer table.

### 5.2 Order of work

1. **Measure first, no change (Std, five seeds, one run each, then run twice for the final).** Run `balance_run.gd`, `relationships_probe.gd`, `council_probe.gd` at 1,500 sols on the five seeds with the shipped data. Record: pop, adults, stage counts, housing lead, conception and birth histograms (Q3, Q4), Settlement sol and cohort size (Q1), first friendship by stage (Q8), ice and food per being (Q6, Q7), founder deaths, silence gaps (R6'), power timeline of seed 2026 (Q9). Output: `docs/balance/lifecycle-std-baseline.md` with every target of section 3 evaluated and every number measured. No code change. Probe changes allowed: the probe's own `VOICE_MIN_AGE_SOLS` constant (rebaseline caveat) should be replaced by `Lifecycle.is_adult`; reporting additions only (stage counts, cohort tables).
2. **Generational look, one seed (42), shipped data**, background. Record L6, voices over time, Council entry sol if any, late cost (R8, C8). If it is out of budget, stop at sol 7,200 or earlier and report where it stopped.
3. **Fix the targets from the measurements.** Replace each E in section 3 with a window from the measured spread (min and max over the five seeds with a margin), as the earlier tasks did. Owner confirms (section 7).
4. **Retuning runs**, only for targets that still fail, **one parameter per run**, each at Std on the five seeds, twice, with a decision rule stated before the run (keep if the failing target passes and no other regresses; halve once; otherwise report to the owner). Priority order by consequence: Q1 or Q2 (owner decisions, section 7), then Q5/Q6 if L1/L2 fail, then Q3/Q4 if L3 fails. Q9 is a bug investigation, not a retune.
5. **Hash record.** New Smoke and Std hashes become the reference; the old ones are marked superseded.

Seeds: the five standard seeds 42, 7, 99, 1234, 2026 for Smoke and Std. The 15 `r9_seeds` for guards are run at Smoke only (cost), except M4/M9 below, which need Std on at least the five.

## 6. Effect on the 6a emotions spec (`docs/specs/emotions.md`)

6a was calibrated on the old colony (pop 72 to 164, births from sol 13). Must be restated before 6a continues:

- **Horizon and seeds (section 10, 12, probe).** "Five seeds, 300 sols" becomes: dormant build and control at Smoke (structure, cost, hashes), every judgment of mood against behaviour at Std (1,500 sols) on the five seeds; the 15-seed guard (M4, M9) at Std is 15 runs of 12 to 40 min each, so the guard set shrinks to the five seeds plus 5 more (10 seeds, E) unless the owner accepts ~4 to 10 hours of runs; the control noise-floor estimate (about 10^6 draws in 300 sols, E) changes: draws per run are smaller early (7 beings) and larger late; the control gain 1e-4 expected-flips arithmetic must be re-derived from the measured draw count at Std.
- **Hash baseline (section 10 steps 1 to 2, table of "before" figures).** The Task 5 hashes are superseded by the rebaseline's `c370381b5ad96932` family. Step 1's "from a fresh run of the unmodified tree" is already done at e1f2bdd; use `lifecycle-rebaseline.md` for the Smoke chain, add Std hashes once measured.
- **M1 (alive but not pinned; from sol 30; sd of m at sol 300 >= 0.05).** With 7 beings sd is a noisy statistic; restate as: window from sol 30 to the end of Std; sd evaluated over the last 300 sols and when pop >= 12; mean|d| and even-share unchanged ranges (E, to be re-fitted to the Std measurement).
- **M2 (Deimos gap between baseline thirds at sol 300; recovery ratio from grief pushes).** Thirds of 7 are 2 to 3 beings; grief pushes are rare when nobody dies. Restate: evaluate at sol 1,500 (pop ~40, thirds of ~13) and pool grief pushes over Std; the grief count needed to judge the ratio (>= 10, E) is reported and the target waits if it is not met.
- **M3 (restless trait rank correlation).** Judged over adults (children do not travel); needs >= 20 adults for a rank correlation, so it can only be judged at the Generational tier, or reported at Std with n stated. Static data check part is unchanged.
- **M4 (death spiral guard, 15 seeds, deaths relative to gains 0, "+25 percent or 3 deaths").** With 0 to 3 deaths per 300 sols the "or 3 deaths" clause makes the guard vacuous; restate over Std per seed with L1 (adult floor) as the primary guard, thirst deaths per 1,000 being-sols, and trips per adult-sol (T7 restated) instead of trips per sol.
- **M5 (old targets).** Reads T1 to T12 as restated in section 3 here, and the ages ranges as the T10 window of 3.1.
- **M6 (cost).** Pop above 120 is not reached at Std. The cost budget is measured at Generational or with the synthetic fixture; at Std it reports per-pop slopes.
- **M7 (lines per 5 sols over sols 30 to 299; log share).** Window becomes sols 30 to 1,499; with a 500-entry log and 5 cohorts the log share is a rolling figure.
- **M8 (inspect text audit at sol 300).** Done at the end of Std; must add babies and children (the panel for a being who cannot work or travel); K1 sentence rule needs the "can bond" definition (Q8).
- **M9 (popularity snowball: `lonely_share` rise <= 0.03 against control, sd of friend_count).** Share is count-based when pop < 20 (T11 restated); judged at Std end.
- **T13 (log series length equals `pop_by_sol`, <= 1 mood line per sol, relief after quiet, heavy share <= 0.30 after sol 30).** Structural; `heavy_by_sol` at pop 7 moves in steps of 0.14, so the 0.30 tripwire fires on 3 beings; restate as "<= 0.30 or <= 2 beings, whichever is larger" while pop < 20.
- **Mood mechanics that now interact with life stages.** Babies and children rest by rule: do they carry mood at all? (Spec question for the 6a author: recommend mood is created at the first birthday or stays at its starting value; either way the pushes and travel/energy effects read adults only.) Grief pushes are rarer; the `events` list is small.
- **Dependency.** 6a's expectations of Council and pledge (diagnostics D) go to the Generational tier.

## 7. Owner questions (recommendation first)

1. **Horizon vs run time.** Recommended: **Smoke 300 + Standard 1,500 + a rare Generational 7,200 (one seed, background)**. Alternatives: (b) Std only, no Generational: cheaper, but Council and adult Mars-born stay untested until players hit sol 6,700 (about 44 hours of play at 1x, much less at fast speed); (c) a single longer standard of 3,000: roughly double the cost of Std and still no adult Mars-born, so I advise against it. Trade-off: Std costs ~25 to 80 min per five seeds, Generational 1.5 to 5 h per seed.
2. **When should the Council arrive?** Recommended: **keep the rule and let it be a late-game, generational institution** (Council needs five Mars-born adults, ~sol 6,700): the founder era is household and Settlement, which the `circles_few` text already narrates; no change to `voices_min`. Alternatives: (b) lower `voices_min` to 7 or 5 so the founders form a small Council in the first ~1,000 sols (more story early, but decisions by 5 to 7 people, and the dome vote would be judged on tiny quorums; carry_quorum would need a re-fit); (c) both, with the Council's first form open to founders and a second "full" form at 12 (new mechanic, a spec of its own). This is genuinely the owner's: it decides where the colony's political story lives in the player's hours. I would run option (b) as a throwaway diagnostic at Std first (section 4 Q2) so the choice rests on a measurement.
3. **Retune the Settlement family rule or housing before measuring?** Recommended: **no, measure first** (section 5 step 1). Settlement at ~sol 290 versus ~600 depends on whether cohort 1 has five members, which depends on the starting habitat count (capacity 12) more than on the rule. If Std shows Settlement missing on two or more seeds before sol 700, the options are: (a) `mars_born_min` 5 to 3 (the family rule is the owner-visible phrase; changing it changes the narrative of "families"), (b) one more starting habitat (a start-layout change, more to build), (c) leave it and let Settlement be a second-cohort event. I would ask for the decision after the baseline, not now.

## 8. How a headless test proves this document

- A new `tests/lifecycle_horizon.gd` (or `balance_run.gd --sols 1500`) prints per-cohort rows and the L1 to L5 verdicts; exit 1 on any L1 or L4 failure.
- A pure arithmetic test (no run): `Lifecycle.add_months(0, 216)` in sols is within 6,350 to 6,450 and equals the number in section 1 (checks the spec arithmetic against the code; this already follows from the calendar tests).
- Smoke run twice, `cmp` identical; Std run twice for the final configuration, `cmp` identical.
- Every number in section 3 is evaluated in `docs/balance/lifecycle-std-baseline.md` with measured value, pass/fail and the E replaced by a measured window.

## Changelog

- 2026-10-09: first version. All numbers E; nothing measured at Std or Generational. No design review round run.
