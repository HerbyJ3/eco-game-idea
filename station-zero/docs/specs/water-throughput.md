# Water throughput (Task 6 prerequisite) — spec revision 1

Date: 2026-10-09. Author: lead game designer (Claude Code session). Input: [ice-supply investigation](../balance/ice-supply-investigation.md), [Standard baseline](../balance/lifecycle-standard-baseline.md).

## 1. Purpose

All five Standard colonies die of thirst by sol 704 while reachable fields still hold ice. Seven founders cannot deliver water fast enough once dependants arrive, and the delivery they do manage is wasted on interrupted plans, low-energy departures and regolith trips during a water emergency. This spec defines a small set of **behaviour corrections** (how a sensible colonist would act) and one **realism change** (children drink less than adults), each behind its own data switch, and the experiment that decides which ship.

It deliberately does not add a new building, a progress meter, or any god intervention. Naturalism rules: colonists solve water because their own priorities change when water is scarce.

## 2. Rules (each switch is independent; shipped defaults reproduce today's game exactly)

All switches live in `data/resources.json` → `throughput`, except W4 in `data/colony.json` → `consumption.ice_stage_mult`.

| ID | Switch | Default (off) | Proposed (on) | Rule |
| --- | --- | --- | --- | --- |
| W1 | `throughput.urgent_redirect` | `false` | `true` | When stored ice is below `want.ice_urgent_below` (30), a pending **regolith** mine intent is dropped at the next decision, so `_try_new_mining` → `choose_site` (which already forces ice when urgent) picks water instead. An in-progress trip is never aborted. |
| W2 | `throughput.launch_energy_min` | `0` | `45` | At the door, before a miner suits up, if energy is below this value the colonist does not leave: the trip becomes a pending intent again and the colonist goes to sleep. They resume the trip after waking. |
| W3 | `throughput.commute_pause` | `true` | `false` | A colonist walking through rooms toward a mining launch building (carrying a mine intent) does not stop for a full room pause on each arrival; it continues after one fixed step, the same treatment sleepers already get. |
| W4 | `consumption.ice_stage_mult` | all `1.0` | baby `0.3`, toddler `0.5`, child `0.75`, teen `1.0`, adult `1.0` | Water use per being scales with life stage. Realism: an infant drinks a fraction of an adult. |
| W5 | `throughput.water_before_construction` | `false` | `true` | While stored ice is below the ice target, an adult who carries an **ice** intent resumes it before considering joining construction. |

Personality hooks are unchanged: who volunteers to mine is still `mine_will` (steady, drive, restless); W2 delays the tired regardless of trait, and drive still sets yield.

## 3. Power reserve (separate decision, not part of the water experiment)

Seed 2026 loses a green room for 254 h because re-online needs `draw + room ≤ 0.95 × supply`. Proposed switch `buildings.reonline.life_support_fraction` (default = `load_fraction`, i.e. 0.95; proposed `1.0`): a **green room** may come back online at exactly 100% of supply, because life support is worth running at the limit. Not run in this experiment; recorded for the owner.

## 4. Experiment (declared before running)

- Horizon: Standard, 1,500 sols, seeds 42, 7, 99, 1234, 2026. Same build, one switch changed per run (E1–E5), then the combination of every switch that passed (E6).
- **Primary success:** the colony is still alive at sol 1,500 (final population > 0). An experiment *helps* if it keeps more seeds alive than baseline, or (if none survive) delays the first thirst death on at least 4 of 5 seeds.
- **Guards (a switch fails if any is broken):** no new air deaths or air turn-backs; T5 power target no worse than baseline per seed; no rise in EVA deaths; births still happen (first birth sol within ±50 of baseline unless the colony was already dead).
- **Adoption:** a switch is adopted only if it helps and passes guards. E6 must keep ≥ 4 of 5 seeds alive to 1,500 sols; otherwise report and stop (no further tuning in this task).
- Determinism: with every switch at its default, seed 7 must reproduce the baseline table sha256 `12e3535f2952f04d`.

## 5. Out of scope

Water recycling, new buildings, rovers, Settlement/Council thresholds, emotions (6a). Any change to clock, calendar or the late Council rule.

## 6. Experiment 1 results (2026-10-09, Standard 1,500 sols, five seeds)

Baseline reproduced (all five extinct; first thirst deaths at sols 380/300/350/530/400 on seeds 42/7/99/1234/2026). Raw outputs and the summary script are in `docs/balance/water-throughput-data/` (`summary.txt`).

| Run | Switch | Alive at 1,500 | First thirst death (42/7/99/1234/2026) | Thirst deaths | Power guard (T5 vs baseline) | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| base | none | 0/5 | 380/300/350/530/400 | 76 | 4 pass, 2026 fails | — |
| E1 | urgent redirect | 0/5 | 360/300/350/360/520 | 67 | same | No help (earlier on 42, 1234). Not adopted |
| E2 | launch energy ≥ 45 | 0/5 | 310/130/410/350/200 | 53 (smaller colonies) | same | Harmful: tired founders stall, two seeds die before any birth. Not adopted |
| E3 | no commute pause | 2/5 | 600/580/600/850/700 | 89 | fails on 99 | Helps on all 5 seeds |
| E4 (valid rerun `E4v`) | children drink less | 0/5 | 800/310/850/390/640 | 93 | fails on 42, 2026 | Delays on 3 seeds, earlier on 1234. Not adopted |
| E5 | water before construction | 2/5 | 580/330/660/400/500 | 100 | fails on 99; 2026 locks a building off for 9,055 h | Mixed. Not adopted |

**Correction.** The first E4 run reported 5/5 alive with zero thirst deaths. That run was invalid: the multiplier table reached the runner without its JSON quotes, so `parse_value` returned a String, and `_water_heads` read it as a near-zero head count for everyone, founders included (ice at sol 10 was 69.6 against the baseline 52.3, with no child alive yet). Its outputs are kept as `INVALID-E4_*.txt`. `tests/balance_lib.gd apply_param` now rejects an override whose type differs from the data (int and float are interchangeable), so this cannot recur silently.

Power-guard failures have the same shape as seed 2026's baseline outage: one short, then the building stays dark 130–350 h because re-online needs 5% headroom (section 3).

## 7. Experiment 2 results

- **E7** = E4 + `buildings.reonline.load_fraction` 1.0. Its table is identical to the valid E4 rerun on every seed, so the 100% re-online rule made no difference in these runs: 0/5 alive. Not adopted.
- **E8** = E7 + E3. 2/5 alive (7: 9 colonists, 2026: 30), first thirst deaths 820/970/850/1350/1100, power guard fails on 99 and 1234. Not adopted over E3 alone.

No combination met the 4-of-5 survival rule, so tuning stopped here as section 4 requires.

## 8. Owner decision (Herby, 2026-10-09) and what ships

**Design direction changed.** The colony is not meant to survive unattended. Without the player's attention it should struggle and slowly shrink; the player's influence is what keeps it alive, which gives a sense of responsibility and participation. The success bar for this task is therefore no longer "survives alone" but:

1. Unattended decline is **gradual and readable**, not a sudden collapse soon after the first dry tank.
2. Trouble shows early enough for a watching player to notice and act.
3. With timely influence the colony can recover. This needs the god powers, which are not yet built in Godot (next task).

**Ships:** W3 only (`throughput.commute_pause` = `false`). It is simply sensible behaviour (no dawdling on the way to a water trip) and turned a sudden collapse into a slow decline on all five seeds: first thirst moved from sols 300–530 to 580–850, and two colonies were still alive at sol 1,500. This is a behaviour change, so the simulation is re-baselined: `docs/balance/water-rebaseline.md`.

**Stays off (switches kept, default off):** W1, W2, W4, W5, and the 100% re-online rule. W4 (children drink less) remains available for the owner to turn on.

**Power reserve:** still open. The guard failures above are real (a dark building for 130–350 h) and should get their own small task.

## 9. Bug fix found during Task 7: the endless walk to bed

While testing influence powers on seed 2026, average energy fell to 16 and only 3% of colonist-hours were spent asleep (normal is about 11%). A state probe showed exhausted colonists (energy 0, `sleep_intent` set) in `transit`/`to_door` for whole sols without reaching a bunk.

Cause: `Being.go_sleep` re-chose the habitat on every room arrival with `Buildings.nearest_online_habitat`, which measures straight-line distance from the current room. On some layouts the corridor route to habitat A passes a room from which habitat B is nearer, and the route to B passes a room from which A is nearer, so the colonist cycles forever while energy stays at 0. They cannot mine, build or conceive in that state, which is why that colony died with no births.

Fix: `Being.sleep_target_id` stores the habitat chosen when the colonist first heads to bed. `go_sleep` keeps that target while it stays an online habitat reachable over finished corridors, and re-picks only otherwise. Cleared on falling asleep. Test: `tests/test_water_throughput.gd::test_sleep_walk_keeps_its_habitat`.

The walk also happened in unattended runs, so every pinned 300-sol hash changed; the re-baseline is recorded in `docs/balance/water-rebaseline.md` section "Bed-walk fix".
