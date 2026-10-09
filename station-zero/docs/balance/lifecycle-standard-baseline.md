# Standard lifecycle baseline — 2026-10-09

**All five colonies become extinct from thirst before sol 705.** This is the unchanged-game baseline, not a successful calibration. Four of five enter Settlement by sol 328, so the owner’s trigger for choosing a Settlement family/housing change (two or more misses by sol 700) is **not met**. Survival needs investigation before emotions can be calibrated against this baseline.

## Method and provenance

- Source: main merge `801bec5`; Godot `4.5.stable.official.876b29033`; shipped data hash `c370381b5ad96932`.
- One 1,500-sol Standard balance run and one relationships and Council probe per seed: 42, 7, 99, 1234, 2026. Four workers on a host with a four-core CPU quota. The required repeat belongs to the final configuration; this initial baseline was not run twice.
- No simulation, data, clock, lifecycle, starting layout, or target threshold was changed. The relationships probe’s obsolete 40-sol voice-age predicate was replaced with `Lifecycle.is_adult`, as allowed by the calibration spec. Other legacy probe judgments remain unchanged and are qualified below.
- Each balance export contains 1,501 samples (sol 0 through 1,500); each Council export contains 1,500 rows. All runs completed without script errors. Balance exit status is 1 on every seed because L1 fails; relationships/Council exit status 0 means the probe completed, not that its targets passed.
- Raw outputs, commands, timings and exit statuses: [balance manifest](lifecycle-standard-baseline-data/run_manifest.json), [probe manifest](lifecycle-standard-baseline-data/probe_manifest.json), and [data directory](lifecycle-standard-baseline-data/). Full per-seed target values and definitions: [measurement appendix](lifecycle-standard-baseline-data/measurements.md).

Reproduction commands from repository root (repeat for each seed):

```bash
godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed 42 --sols 1500 --tier std --out station-zero/docs/balance/lifecycle-standard-baseline-data
godot --headless --path station-zero --script res://tools/relationships_probe.gd -- --seed 42 --sols 1500 --pull shipped --out station-zero/docs/balance/lifecycle-standard-baseline-data/relationships
godot --headless --path station-zero --script res://tools/council_probe.gd -- --seed 42 --sols 1500 --tag standard --out station-zero/docs/balance/lifecycle-standard-baseline-data/council
```

## Colony outcomes

| Seed | First birth | Births | Peak population | Settlement | Fall-back | First adult-loss sample | First zero-pop sample | Thirst deaths |
|---|---:|---:|---:|---:|---|---:|---:|---:|
| 42 | 280 | 10 | 13 | 290 | none | 372 | 583 | 17 |
| 7 | 286 | 5 | 12 | none | none | 299 | 307 | 12 |
| 99 | 292 | 8 | 12 | 309 | 342 (ice) | 342 | 632 | 15 |
| 1234 | 288 | 10 | 13 | 312 | none | 522 | 704 | 17 |
| 2026 | 285 | 8 | 12 | 328 | 399 (ice) | 392 | 658 | 15 |

Extinction sols above are sampled boundaries; death-event sols in the exports are one sol earlier. Final population and minimum adult count are zero on every seed. All 35 founders die. Across the runs, all 76 deaths are thirst deaths: 35 adult, 39 baby, 2 toddler. There are no unexplained deaths. Children do not replace adult labour before their eighteenth birthday; none of these colonies survives to that event.

The measurements establish the cause of death, not the underlying mining failure. Site depletion, replenishment, travel exhaustion, job selection, and staffing still need a trace around the first ice crisis. Reachability alone does not establish that ice can be supplied quickly enough.

## Balance target results

These are the tool’s unmodified verdicts. PASS may be vacuous after extinction; read the qualifications below. Estimates in the design spec remain provisional, not approved replacements.

| Target | 42 | 7 | 99 | 1234 | 2026 |
|---|---|---|---|---|---|
| L1 | FAIL | FAIL | FAIL | FAIL | FAIL |
| T1r | FAIL | FAIL | FAIL | FAIL | FAIL |
| T2r | FAIL | FAIL | FAIL | FAIL | FAIL |
| T3a | PASS | PASS | PASS | PASS | PASS |
| T3b | PASS | PASS | PASS | PASS | PASS |
| T3c | PASS | PASS | PASS | PASS | PASS |
| T3d | FAIL | FAIL | FAIL | FAIL | FAIL |
| T3e | FAIL | FAIL | FAIL | FAIL | FAIL |
| T3f | REPORT | REPORT | REPORT | REPORT | REPORT |
| T4r | PASS | PASS | PASS | PASS | PASS |
| T5 | PASS | PASS | PASS | PASS | FAIL |
| T6a | PASS | FAIL | FAIL | FAIL | FAIL |
| T6b | FAIL | FAIL | FAIL | FAIL | FAIL |
| T6c | REPORT | REPORT | REPORT | REPORT | REPORT |
| T7r | PASS | PASS | PASS | PASS | PASS |
| T8r | FAIL | FAIL | FAIL | FAIL | FAIL |
| T10r | PASS | FAIL | PASS | PASS | PASS |
| T11r | PASS | PASS | PASS | PASS | PASS |
| T11b | FAIL | FAIL | FAIL | FAIL | FAIL |
| T12r | PASS | PASS | PASS | PASS | PASS |
| Circ | PASS | NYJ | FAIL | PASS | PASS |
| L2 | PASS | PASS | PASS | PASS | PASS |
| L3 | FAIL | FAIL | FAIL | FAIL | PASS |
| L4 | PASS | PASS | PASS | PASS | PASS |
| L5 | PASS | PASS | PASS | PASS | PASS |

- **L1/T1r/T2r:** fail on every seed. Do not lower the survival floor to fit extinction.
- **L2:** raw PASS on every seed is misleading. The late resource windows are empty colonies; division by `max(1, pop)` reports remaining food stores as “food per being,” and zero ice remains flat at zero. Neither demonstrates a sustainable dependant economy. The ratio calculation also cannot give a meaningful finite dependant/adult ratio when adults are zero.
- **T4r:** oxygen and food remain positive, but ice reaches zero and causes all deaths. Its PASS explicitly excludes ice survival.
- **T8r:** post-extinction adult rows have zero observations and zero energy/asleep values. The raw FAIL is not evidence that surviving adults had zero energy. Use rows with `n > 0` in a revised observer; maximum sleep remains an all-stage measure.
- **T11r:** zero friendless adults after everyone dies is vacuous. T11b and end-state R4 cannot measure healthy relationships in an empty colony.
- **L3:** birth windows are 270 sols anchored on first birth, not identified biological generations. Seed 42’s first window includes a conception at sol 282 and a birth at 547, inflating its “first cohort” conception span to 269 sols. Resolve this definition before changing conception probabilities.
- **L4/L5/T3a:** housing reservations never exceed capacity, stage counts sum to population at every sample, sampled stage-age checks report no violations, and birth capacity/cooldown guards report zero violations. L5 does not check every being’s age at every step.
- **T6a:** saturation means capacity minus population plus pending reservations is zero, whether or not an eligible adult could conceive. Longest runs: 14, 173, 96, 63, 314 sols. These are not measurements of individual housing waits.
- **T5:** seed 2026 still has 254.4 h maximum offline time against 24.7 h. Its first new reactor finishes at sol 13, within the existing sol-15 deadline. The other four have zero maximum offline time. Investigate the outage separately from retuning.
- **T7r:** trips per adult-sol are 0.1122, 0.0953, 0.1092, 0.1205, 0.1070. Air turn-backs are zero, and two reachable sites exist at 100% of samples. Exhausted trips are 128, 108, 118, 206, 224; investigate their contribution to ice supply.
- **T10r:** Settlement entry target passes on four seeds; seed 7 misses. Seed 99 falls back for ice at 342; seed 2026 at 399. No Settlement adjustment is triggered by the owner’s current rule.
- **Circ:** seed 99’s raw FAIL is zero circles during its 33-sol Settlement stay; the first circle would be due after 50 sols. Seed 7 is not judged (no Settlement). Clarify opportunity to emit a circle before treating this as a missing-line bug.

## Relationships and Council

| Seed | Kin newborns resolved / born | Median wait (sols) | Restated R1 (at least 8 resolved, median ≤30) | First relationship line | First newcomer line |
|---|---:|---:|---|---:|---:|
| 42 | 9 / 10 | 6.0 | PASS | 24 | 83 |
| 7 | 5 / 5 | 5.0 | REPORT (sample <8) | 16 | 99 |
| 99 | 8 / 8 | 5.0 | PASS | 19 | 137 |
| 1234 | 10 / 10 | 5.5 | PASS | 21 | 250 |
| 2026 | 8 / 8 | 5.5 | PASS | 14 | 160 |

Babies can form friendships: resolved newborn waits have medians 5–6 sols, long before their first birthday. Seed 42 has one unresolved newborn excluded from its median. This finding does not implement infant care or animations.

| Target | Standard interpretation |
|---|---|
| R2 | PASS on all seeds; first relationship line occurs at sols 14–24. |
| R3 / R4 / R7 / R10 / R11 | End population is zero. R3 zero loneliness and R11 sentinel-based PASS are vacuous; R4 is not judged as relationship health. R7 requires n ≥12; R10 requires population ≥25, never reached. |
| R5 / R14 | Zero dropped events on all seeds. R14 still uses total dropped lines, not an event-type counter. |
| R6 | FAIL: long gaps occur even while alive; see table below. Including the empty tail makes every full-horizon silence gap still larger. Old rate fields contain legacy window labels and must not be substituted for the restated guard. |
| R8 / R9 | R8 large-population cost not judged (peak 12–13, never >120). R9 pull guard not run; shipped pulls remain off. |
| R12 | The raw “first newcomer” lines occur before the first birth on every seed. Against the proposed lower bound this is FAIL, but the legacy newcomer definition can describe founder friendships; resolve semantics before treating this as newborn log timing. |
| R13 | The requested last-300-sol window is entirely post-extinction: zero events, vacuous. Legacy probe tail fields retain old labels and must not be used as the restated window. |
| C1 / C4 / C5 / C6 / old quorum fit | Retired at Standard per owner decision. No entry, vote, proposal, pledge or divided vote occurs. Do not lower voices_min to make these pass. |
| C2 / C3 / C7 / T12r | Structural checks are vacuous without a Council; zero Council changes and no entry below 12 adult voices. |
| C8 / L6 | Generational measurements remain untested. No large-population cost or Mars-born adulthood claim is established here. |

The Council has at most seven adult voices. The relationships gate readings now exclude children via the shared lifecycle predicate. Council “voices” while in Landing may be a skipped-gate placeholder; actual adult counts are recorded separately.

| Seed | Longest life/relationship gap before extinction (sols) | Balance wall seconds | Relationships wall seconds | Council wall seconds | Standard table SHA-256 prefix |
|---|---:|---:|---:|---:|---|
| 42 | 150 | 82.098 | 78.961 | 77.901 | `46ebd01df8e28395` |
| 7 | 86 | 66.845 | 62.186 | 64.435 | `46296399e5767e56` |
| 99 | 72 | 74.008 | 71.060 | 72.978 | `4a36d556c47ad076` |
| 1234 | 140 | 90.375 | 86.397 | 84.596 | `94b5d2657c1103ba` |
| 2026 | 163 | 74.918 | 74.972 | 75.859 | `64ad9bc043b139e9` |

Timing is for this small colony, including a long empty tail, under concurrent load. It cannot validate the cost estimates for a growing colony. Standard table hashes above are recorded once, not run-twice determinism proofs. For each seed, the first ten table rows (through sol 300) exactly reproduce the accepted Smoke table, with prefixes `6dd003aef320196b`, `bd45d3b3c0690911`, `0d8e25bd9b7b056f`, `539156aead08fb41`, `3ab707732c622968` respectively.

## Validation and next session

Godot import and the lifecycle horizon check passed (2 tests, 2 checks). All fifteen baseline/probe jobs reached the requested horizon; their birth and death totals and data hashes agree. No script errors were found. No new full-suite result is claimed here; the previous full suite has known failing mood tests while the dormant build remains unfinished.

Next: trace ice supply and founder job choices around the first crisis, starting with seed 7 (first adult-loss sample 299) and seed 2026’s outage. Separate observer defects and empty-population judgments from gameplay failures. Present any consumption, mining, housing or survival mechanic change to the lead game designer/owner before tuning; preserve the real calendar and unchanged clock.

The scheduled 7,200-sol Generational run is **not performed in this report**. With all beings gone by sol 704 and no immigration mechanism, extending this configuration cannot observe Mars-born adulthood; it remains a pending generational verification after survival is addressed. Emotions target restatement and the dormant `wip/6a-dormant` build remain unfinished. The Settlement decision trigger is not met. No approved thresholds or mechanics are changed by this report.
