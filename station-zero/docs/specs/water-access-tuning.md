# Water access tuning (Task 7d)

Status: executed 2026-10-13, all three runs failed the guard (results in task-7d-results.md); the plan below is as pre-declared. Author: game-designer (lenses applied below). All predicted numbers are estimates until measured.

## 1. Problem

Per-being thirst (`colony.death.thirst_mode = "per_being"`, `thirst_being_chance = 0.002`) passes U2 and U3 (Task 7c Run 1) but fails the guard "at most 3 of 5 seeds alive at sol 1,500 unattended (watcher player)": 5 of 5 alive. Rates 0.0020-0.0028 moved at most two seeds (`docs/balance/task-7c-results.md`, `per-being-thirst.md` section 9). The guard is a water-access outcome: how long ice sits at 0.

Dry sols (sample rows with pop > 0 and ice exactly 0, times 10) per seed, Run 1 / 2 / 3:

| seed | R1 | R2 | R3 | pop at 1,500 (R1) |
|---|---|---|---|---|
| 42 | 290 | 160 | 240 | 15 |
| 7 | 190 | 310 | 370 | 22 |
| 99 | 30 | 70 | 70 | 35 |
| 1234 | 70 | 20 | 60 | 15 |
| 2026 | 150 | 90 | 130 | 15 |

Wet seeds are 99, 1234, 2026 (dry 20-150 of 1,500 sols). To pass the guard at least 2 of 5 must be extinct; seeds 42 and 7 are already dry long enough to get close (7 went extinct at 0.0028), so at least one wet seed must flip.

## 2. Owner decisions (Herby, 2026-10-13, binding)

1. Ice supply keys are allowed as levers: `ice_field.amount`, `spawn.ice_px`, `mining.yield_ice`, `mining.shift_h`, `mine_attempt.chance`, `scout.chance_per_h`, `want.ice_bias`, plus `start.ice` and `want.ice_urgent_below`. Supersedes the "not levers" note for yields in influence-powers.md 5.8 (struck there).
2. Direction: less water (smaller or farther fields, less starting ice, lower yields), so idle colonies go dry.
3. If three runs fail: stop, record, bring the owner the next lever, split the task. No guard relaxation.

Thirst settings stay: per_being, 0.002.

## 3. What the sim does with ice (grounded in code)

- **Fields are finite but the supply is endless.** A field loses ice in `World.take_ice`; at 0 it is erased and logged. `Resources.respawn_if_short()` then spawns a new field at once if fewer than `scout.min_reachable` (2) are reachable, and `Resources.scout()` rolls `scout.chance_per_h` x dt for the same case. New fields use `ice_field.amount` ([260, 420]) at distance `spawn.ice_px` ([90, 170]). Founder fields (`spawn.founder_ice_px`) are the only ones outside that range.
- Consequence: `ice_field.amount` only sets how often a replacement spawns, not the total ice available. It is a weak lever; shrinking it changes churn, not scarcity. It is not used here.
- **The real limiter is hauling rate**, not ice in the ground: one load per trip, `mining.yield_ice` x (0.7 + 0.6 drive) x (0.55 + energy/220) (`Being._end_mining`), trips started by `mine_attempt.chance` (`Being._try_new_mining`), one miner per field visit, 36 h suit tank.
- **Distance has a hard ceiling.** `spawn_site` rejects (never clamps) any site with `trip_time >= 0.85 x 36 h`, i.e. d + r < ~196.8 px (life-support-power.md target 7). So `spawn.ice_px` max cannot go above about 175 px; pushing the range out shrinks nothing but trip length. Longer trips mean fewer loads per sol per miner at the same yield.
- Founder fields (about 2 x 340 = 680 units) last roughly until the first low at sol ~290-370 (7c `low_sol`); after that supply is replacement fields at `spawn.ice_px`. Hence `start.ice` (60) is a poor lever for a sol-1,500 outcome (it only delays the first low by about 10 sols of use at 7 beings) and is not used.

## 4. Pre-declared runs (exactly three, in this order)

Harness is the 7c one: `godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols 1500 --every 10 --player watcher --param '<key>=<json>'`, seeds 42 7 99 1234 2026, UN (watcher) set, base = data defaults after 7c (per_being 0.002). Check the `overrides=[...]` header of every output. Metrics with `tools/acceptance_summary.py` as in 7c.

Carry rule: a run starts from the data defaults. If a run fails only the guard but reduces the alive count, its value is kept for the following run (so run 2 then carries two changes versus defaults, still one versus the previous run); if it fails U2 or U3, it is reverted. This is stated before running and not changed after.

| # | Key (file) | Old -> new | Why | Predicted effect on wet seeds |
|---|---|---|---|---|
| 1 | `mining.yield_ice` (`data/resources.json`) | [6, 10] -> [4, 7] | Cuts mean load about 31% (8 -> 5.5); hauling rate, not ground ice, limits supply. Founders deliver 1.5-1.9 units/sol against 1.73/sol need for 7, so a 31% cut makes the first low and dry spells come earlier and last longer. | Dry sols per seed rise: 99 from ~30 to ~150-300, 1234 from ~70 to ~250-400, 2026 from ~150 to ~300-450. Seed 99 (pop 33-35, largest) likely still survives; 1234 and 2026 most likely to flip. First low moves earlier (lead stays large; U2 should hold: min lead was 59). U3 risk: longer dry spells approach the 34% per 50 dry sols design rate at pop 10-14; estimated worst window 25-35%. |
| 2 | `spawn.ice_px` (`data/resources.json`) | [90, 170] -> [140, 175] | Replacement and scouted fields land 50 px farther on average; trip is 2 x (d + r) / 16 h + 6 h, so about 25% longer; fewer loads per miner per sol. Upper bound kept under the 196.8 px trip ceiling; founder fields unchanged. | Acts only after the founder fields dry (sol ~300+), which is when wet seeds currently recover. Adds about 15-25% more dry time to 99, 1234, 2026 on top of run 1; seed 99 gains most (its recovery was replacement-field luck). |
| 3 | `mine_attempt.chance` (`data/resources.json`) | 0.4 -> 0.28 | Fewer miner departures (about 30% less) at the same yield and distance; hits all seeds including large colonies, since attempts are per idle colonist. | Further cut in hauls per sol; wet seeds approach the 42/7 profile (dry 200-400 sols). Largest risk is U3 on seed 7 (lowest pop, already 64% at 0.0028). |

Why this order: yield is the cleanest single knob on supply (one number, exact effect on delivered units); distance acts only late; attempt chance is the most behavioural (touches construction and regolith timing, so it moves more than water) and goes last.

Assistant designer lenses (applied by the lead; no subagents here). Emergence: all three keep the same hauling behaviour and personalities, only scarcity changes, so water sets carrying capacity, which is the intended loop; run 3 alters how often everyone mines and so also changes regolith/construction, a side effect. Feel: players will see more "low water" and "run dry" lines and a smaller colony; no new wording. Clarity: the water outlook already warns before dry; shorter lead is the cost. Dissent: Feel would prefer smaller fields over lower yield ("the ground is poorer") for fiction; rejected because section 3 shows field size does not change supply.

## 5. Acceptance bars (every run)

- Guard: at most 3 of 5 seeds alive at sol 1,500 (at least 2 extinct), watcher player.
- U2: lead >= 10 sols (first thirst death sol minus first `low` sol) on every seed with a thirst death and low_sol > 0.
- U3: no 50-sol window starting from pop >= 10 loses more than 35% (hard bar).
- Hygiene: 0 PARAM ERROR, 0 SCRIPT ERROR, 0 ABORTED, overrides header exactly as declared, thirst keys unchanged.
A run passes only if all hold. Attended sets (C1/C2) are re-run only after adoption (below).

## 6. Stop rule

Three runs maximum, in the order above. If none passes: stop, record each result in `docs/balance/task-7d-results.md` (same table layout as 7c), do not run a fourth, and bring the owner the next lever and a task split. Candidate next levers, not pre-run: `want.ice_urgent_below` 30 -> 15 (colonists react later), `mining.shift_h` [5, 9] -> [4, 7] (carefully: life-support-power.md target 7 only tolerates a shorter max shift, never longer), `scout.chance_per_h` (weak; replacement spawns immediately). No relaxing of the guard or U3 to fit a result.

## 7. Adoption

The first passing run's value (with any carried changes) is written into the data file as the new default (`station-zero/data/resources.json`, the key paths above), then: re-baseline the pinned U1 hashes (the sim numbers changed; owner-approved in 5.8), re-run the attended sets C1/C2 and the A1-A3, P1-P3 bars from influence-powers.md section 5 and report; update HANDOFF.md. Do not adopt a partial pass.
