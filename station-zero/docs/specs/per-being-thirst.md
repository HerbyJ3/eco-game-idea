# Per-being thirst deaths (Task 7c spec)

Status: draft for owner approval, written by the game-designer 2026-10-12. Branch `claude/task-7c-per-being-thirst`. Numbers are estimates from arithmetic on existing 7 and 7b data; no Godot probe was run. A calibration run measures them (section 7). No code before the owner approves (task plan step 1).

## 1. Purpose

The thirst roll is per colony: at ice 0 it kills `24.66 / thirst_interval_h x chance` colonists per sol (9.86 / interval_h) whatever the population (`sim/colony.gd` `shortage_check`). Task 7b showed no single interval meets both bars: 5 h collapses small colonies in days (U3 fails on 4 of 5 seeds), 50 h leaves 4 of 5 colonies alive at sol 1,500 (guard: at most 3) and still fails U3 on seed 7. The rule also accelerates a decline: the fewer people, the bigger the share each roll takes.

Owner direction (HANDOFF section 8, 2026-10-09): the colony is not meant to survive unattended; decline must be gradual and readable; timely influence must be able to turn it around. Per-being thirst gives that: each dry colonist faces the same small chance, so a colony loses a steady share of itself, the loss per sol shrinks as the colony shrinks (water sets a carrying capacity, and the survivors drink more easily), and a Guide, Fortune or a good mining run that puts ice back above 0 stops the deaths at once.

Fiction: thirst is something that happens to a person, one at a time, not a roll the colony makes.

## 2. State and rules

New data (`data/colony.json`, `death` block). Old keys are untouched.

| key | unit | starting value | meaning |
| --- | --- | --- | --- |
| `death.thirst_mode` | string | `"colony"` (default until step 6 adopts `"per_being"`) | `"colony"` = current rule, byte-identical. `"per_being"` = rules below. |
| `death.thirst_roll_h` | hours | 6 | Hours between thirst rolls while ice is 0. New key, not a reuse of `thirst_interval_h`. |
| `death.thirst_being_chance` | probability | **0.002** | Chance that one eligible colonist dies on one roll. The one balance number (section 7). |

Rules in `per_being` mode, inside `shortage_check` (phase 10), only when the cause resolves to thirst (oxygen above 0 and ice at or below 0):
1. The existing `death_timer_h` accumulates `dt`; the interval is `thirst_roll_h`. It resets exactly as today (to 0 when nothing is lacking, and after each roll). So the first roll comes `thirst_roll_h` after ice reaches 0, and a refill above 0 resets the clock.
2. At a roll, build the eligible list: all living colonists for whom `is_inside()` is true, sorted ascending by `being.id`.
3. For each eligible colonist in that order draw one `_rng.chance(thirst_being_chance)`. Collect every colonist whose draw succeeds.
4. Only after the loop, kill the collected colonists in id order (so removal never changes the number of draws in that roll). The result carries a list of victims (the engineer chooses the shape; colony mode keeps today's single-victim return untouched).
5. Air and hunger deaths are unchanged in both modes: `air_interval_h`, `hunger_interval_h`, `chance` 0.4 and `_rng.pick` stay on the colony path. `death.chance` and `death.thirst_interval_h` are not read for thirst in `per_being` mode (they stay live for colony mode, so 7b lever 1 remains a valid colony-mode lever).
6. If air is also out, cause is air and the thirst roll does not happen (existing priority, unchanged).

### Answers to the plan's open questions

1. **Rate per being:** 0.002 per roll (section 3 for the arithmetic). About 0.82% per dry sol; half-life of a continuously dry colonist about 84 dry sols.
2. **Interval:** new key `thirst_roll_h` = 6 (about 4.1 rolls per sol, 205 rolls per 50 sols). Six hours spreads deaths through the sol instead of batching them at one tick, and matches `hunger_interval_h`. `thirst_interval_h` is not reused, so both modes stay independently tunable.
3. **Grace and ramp:** none beyond the built-in one roll interval (6 h) before the first roll. No ramp (a ramp is a second number and a hidden counter; flat chance makes an exponential, readable decline). Interaction with U2 `lead` (sols from first low to first thirst death): deaths can only happen at ice 0, which comes after the low warning; the observed gap was 21 sols or more on every baseline seed (seed 7: low 320, first thirst death 341). At pop 10 the per-being rate (0.082 per sol) is below the old 50 h rate (0.197), so the first death comes later, never earlier: `lead` can only widen, so U2 holds. Dissent on grace is in section 8.
4. **Log wording:** per-being thirst death logs `"{name} died of thirst."` with the usual kind `died`, `being_id` and `cause: "thirst"`; stats `deaths.thirst` unchanged. Colony mode keeps `"{name} died (thirst)."` so its output is byte-identical. The dry line stays "The water has run dry." every 2 sols (`thirst_repeat_sols`), the only dry text. No new lines, no counters; deaths are spaced by sols, not clustered, so no spam.
5. **`death.chance`:** does not apply to thirst in `per_being` mode; still applies to air and hunger. Untouched keys: everything else in `colony.json`, including `warnings.thirst_repeat_sols`, `consumption.ice_per_being`, `start.ice`, and all `resources.json` water wants.
6. **Where it lives:** this file; lever-1 line of `influence-powers.md` section 5.8 struck with a pointer here (done).

### Eligibility

- **Eligible:** every colonist who is inside at the roll, any life stage (children, teens, elders, newborns). Colony mode already kills children and does not discriminate by stage; this keeps the rule one sentence. Owner question 1.
- **Not eligible: suited colonists outside** (`transit`, `eva`, `work`, `mining`, i.e. not `is_inside()`). They are on suit water, the same protection colony mode gives by preferring inside victims, and killing the miners who fetch the water would turn the remedy into the casualty (and break the P1 rule "no EVA deaths" in C1/C2). Cost: the inside share of the colony (unmeasured, guess 80-90%) lowers the effective rate by that factor; the table in section 3 shows both.
- No draws for ineligible colonists, so the draw count per roll equals the number of inside colonists (a testable fact).

## 3. Arithmetic

Constants: sol = 24.66 h; 205 rolls in 50 fully dry sols; per-colonist loss over 50 dry sols = 1 - (1 - 0.002)^205 = 33.7%. Because each colonist rolls independently, the expected loss fraction does not depend on population: this is the point of the change. Variance does (small colonies are noisier).

Expected deaths per 50 sols at ice 0 the whole time (worst case):

| pop | colony mode 5 h (now) | colony mode 50 h (7b) | per-being 0.002, all inside | per-being, 85% inside | loss % (all inside) | P(window fails U3 bar, all inside) |
| --- | --- | --- | --- | --- | --- | --- |
| 10 | 98.6 (dead in 5 sols) | 9.9 | 3.4 | 2.9 | 33.7% | 0.45 |
| 20 | 98.6 | 9.9 | 6.7 | 5.9 | 33.7% | 0.35 |
| 35 | 98.6 | 9.9 | 11.8 | 10.3 | 33.7% | 0.39 |

Reading it against U3 (no 50-sol window starting at pop >= 10 loses more than 35%; fail means deaths / start pop above 0.35, i.e. 4 or more of 10, 8 or more of 20, 13 or more of 35):

- A fully dry 50 sols sits at the bar in expectation (33.7% against 35%), so a fully dry window fails about 4 times in 10. This is the pessimistic case and it is deliberate to price the guard; the evidence says real windows are partly dry. Under the 50 h rule the four large colonies lost only 11%, 3%, 4%, 3% in their worst windows (1 to 2 deaths where a fully dry window would have been 9.9), and seed 7 lost 5 in a window, about half a dry window. At half dry (25 dry sols) the table is 18.5% expected for every pop, P(fail) 0.10 (pop 10), 0.02 (pop 20), 0.01 (pop 35).
- Scaling the 50 h data to per-being: pop 20 rate ratio 0.0082 x 20 / 0.197 = 0.83; pop 10 ratio 0.42; pop 35 ratio 1.46. Seeds 42, 99, 1234, 2026 had 3 to 11% worst windows, even 1.5x that is under 17%. Seed 7 (pop 10): 50% x 0.42 = about 21%. Estimate: U3 passes on all five seeds, with seed 7 the likeliest to fail by bad luck (about 0.10 for a half-dry pop-10 window, from the table above).
- U2: unchanged or wider (section 2 answer 3).

Why unattended colonies should still mostly die (guard: at most 3 of 5 alive at sol 1,500, baseline 2):

- Per colonist survival after D dry sols is exp(-0.0082 D): half after 84 dry sols, 10% after 280. The 7b 50 h runs were dry in 40 to 100% of the 30-sol sample windows after sols 340 to 620 (seed 42: 69 of 150 windows; seed 7: 103; 99: 40; 1234: 49; 2026: 44), so a colony faces hundreds of dry sols across 1,500.
- At pop 25 (the size the 50 h colonies reached) per-being 0.002 kills 0.205 per dry sol against 0.197 for the 50 h rule, so for colonies of 24 or more it is as hard or harder than the setting that left 4 of 5 alive; for small colonies it is softer (0.082 at pop 10 against 0.197). Honest prediction: 0.002 should give 3 or 4 alive, so the guard is the likelier failure and the first fallback is already named below. A small colony that survives by luck is a feature (the last few holding on), not a bug, but it costs alive count.
- A colony that is watched (Guide, Fortune, the water outlook) holds ice above 0 and takes no thirst deaths at all, which is the owner's "attention keeps it alive".

## 4. Edge cases

- Ice returns above 0: `lacking` is false, the timer resets, the clock for the next dry spell starts fresh (a flicker of ice can reset the clock; this is the same reset colony mode has and is an unmeasured mercy; if it makes the guard fail across the board, the fallback in section 7 raises the chance, no new rule).
- Pop 0 or all colonists outside: no eligible colonists, no draws, timer resets or rolls nothing; extinction handling unchanged.
- Several deaths in one roll: allowed (rare at 0.002); one `died` line each, id order.
- Newborn arrives between rolls: eligible at the next roll if inside.
- RNG: draws happen only in `per_being` mode with cause thirst. Colony mode makes exactly the draws it makes today, in the same order, so all pinned 300-sol hashes (42 a298dbb55b71d66e, 7 e540c1b86dabba26, 99 ffb6d5361bdb3a5d, 1234 bca08a0f327892fe, 2026 5fb3b699b4118a84) are unchanged with the default. Per-being draws use the existing colony `_rng` (same stream the colony-mode roll uses), so in `per_being` mode all later random events shift (the expected re-baseline).
- Unknown `thirst_mode` string: an error at colony setup (`push_error` once naming the value) and behaviour falls back to `"colony"`; never silently `per_being`. `balance_lib` already rejects a type mismatch (string vs number) for `--param`.

## 5. Player-facing wording

- Per-being thirst death: `"{name} died of thirst."` (one wording; the death log is already the quiet, plain voice and the colony log is capped at 500 entries).
- Dry state: "The water has run dry." (unchanged).
- No new HUD element, no meter, no counter. The reader sees: low-water outlook, then the dry line, then, sols apart, individual named deaths; stop when ice comes back.

## 6. How a headless test proves it

In `tests/` (the engineer names the file), `thirst_mode = "per_being"` unless noted:
1. With ice 0, the number of `_rng` draws per roll equals the count of inside colonists, in ascending id order (inject a counting rng or compare to a replayed stream).
2. Rolls scale with the living count: with `thirst_being_chance` 1.0 every eligible colonist dies at the first roll; with 0.0 none ever; the expected-loss fraction at 0.002 over 205 rolls for pop 10, 20, 35 is 0.337 +/- sampling (over many seeds, mean within 0.03).
3. No roll at ice > 0 and the timer resets when ice rises; the first roll is `thirst_roll_h` after ice reaches 0.
4. Suited/outside colonists are never victims and cost no draw.
5. Air takes priority; hunger path unchanged; `death.chance` is not read for thirst (set it to 0 and thirst still kills at chance 1.0).
6. Log text `"{name} died of thirst."` in per_being; `"{name} died (thirst)."` in colony mode; `stats.deaths.thirst` counts both.
7. **Default-off:** with `thirst_mode = "colony"` the five 300-sol pinned hashes are unchanged, the four hash proofs and `test_t18c` pass, and a colony-mode run with `thirst_being_chance` and `thirst_roll_h` changed is byte-identical to one without.
8. Unknown mode string: errors once, behaves as colony.

## 7. Calibration run plan (for sim-test-engineer; one number per run)

Setup (declared, not a lever): `--param colony.death.thirst_mode=per_being` on every run. Lever: `colony.death.thirst_being_chance` only. UN set, five seeds, 1,500 sols, `--every 10`, `--player watcher`.

| run | value | per dry sol | fully dry 50-sol expected loss |
| --- | --- | --- | --- |
| 1 (primary) | **0.002** | 0.82% | 33.7% |
| 2a, if U3 fails (any seed over 35%) and the guard holds | 0.0014 | 0.57% | 25.0% |
| 2b, if U3 passes but 4 or more seeds are alive at 1,500 | 0.0028 | 1.15% | 43.7% |
| 3, only if run 2 failed the opposite way to run 1 | the geometric midpoint of runs 1 and 2: 0.0017 (after 2a failing the guard) or 0.0024 (after 2b failing U3) | | |

If run 3 fails: stop (three failed runs, plan rule), record, and bring the owner a second lever: a dry-duration ramp, or `start.ice`/`want.ice_urgent_below` from the 7b list. U2 failing at any value is a separate stop (it should not, section 3). Passing means U3 on all five seeds, U2 on all, and at most 3 of 5 alive, per `task-7b-plan.md` step 3.

## 8. Assistant designer reviews (no Agent tool in this session, so each lens was applied by the lead explicitly and recorded here; the main session can re-run them as subagents)

**Emergence (Wright lens).** Good: dryness now acts on individuals; the loss is a share, so a big colony has bigger stories and a small one lingers, "the last three holding on". A real emergent loop appears: deaths lower consumption, ice recovers, births resume (gate ice > 5), so water sets a carrying capacity rather than a cliff. The old per-colony rule was a death spiral that accelerated as the colony shrank; this one decays exponentially and cannot spiral. Must-fix: do not let personality be a hidden gate here (we did not); idea (not adopted, scope): let a colonist's trait (care, sociability) or a friend sharing water modulate their own chance, and let the log name who gave up their water. Rejected for 7c because it would add numbers and change what the calibration run means; park for the culture stage. Concern: suited miners exempt reads as a script; accepted because the alternative kills the remedy.

**Feel (Barone lens).** Good: one plain line per death, spaced by sols, is the right size; no spam. Concern (should-fix): children and newborns dying of thirst is the bleakest thing the sim can say; colony mode already does it, but it is now more visible because deaths are one at a time. Preferred: keep it (it is what makes the player care about water) but make it the owner's call (question 1). Idea: a warm second wording, e.g. "{name} gave out in the dry." Not adopted: one wording matches every other death line and costs no test; revisit when the death lines get variants. Asked for a day of grace after "run dry"; see dissent below.

**Clarity (Korppoo lens).** Good: cause and effect are legible: low water, "run dry", named deaths, then they stop when ice returns; no hidden counter; the rate is proportional so it reads the same at 7 and at 160 colonists (it gets faster in absolute terms as the colony grows, which is the right signal that a big colony needs more water). Must-fix adopted: the rule must stop the moment ice rises (timer reset) so the player sees the remedy work. Should-fix: the outlook (spec 5.x) already warns before ice 0; do not add a second warning. Asked for an explicit grace of one sol after "run dry" so the player can react. Idea: show on the inspect panel that a colonist is "thirsty" while ice is 0; deferred (view work, not 7c).

**Dissent recorded: grace.** Clarity (and a little Feel) wanted a one-sol grace after the dry line. Decision: no extra grace. The real warning is the low outlook, 21 or more sols before the dry line on every baseline seed; the 6 h before the first roll already exists; at 0.002 the first death among 20 colonists arrives about 6 sols after the dry line on average (1 / (20 x 0.0082)), which is itself a grace; and an extra grace would lower the effective rate and hide the interaction from the calibration run (it would have to be tuned with the chance). Reversible: if playtest says the first death feels sudden, add `death.thirst_grace_h` as a later task.

## 8b. Owner questions (asked before the runs)

See the reply to the main session; recorded here once answered:
1. Children and newborns: eligible for thirst deaths? (A, all colonists, preferred; B, adults only; C, children at half chance.)
2. How hard should a fully dry colony fall? (A, middle: 34% per 50 dry sols = 0.002, preferred; B, gentler: 25% = 0.0014; C, harder: 44% = 0.0028.) This only picks the starting value; the pre-declared runs move it by the evidence anyway.

## 9. After Run 3 — options for the owner

Status: stop rule reached (three runs, 0.0020 / 0.0028 / 0.0024; `docs/balance/task-7c-results.md`). Nothing was run for this section. Numbers below are the measured ones from those runs.

What the data says. Seeds 99, 1234 and 2026 are dry for only about 20-150 of 1,500 sols, so they survive at every rate tried (pop at 1,500: 14-35). Seeds 42 and 7 are dry 160-370 sols and swing from 15% to 64% worst-window loss as the rate moves. So the guard (at most 3 of 5 alive) is mostly a water-access outcome (how long ice sits at 0), not a death-rate outcome; no rate in 0.0020-0.0028 moved more than two seeds. U3 at pop 10-14 is close to single-roll noise (4 deaths of 10 is already 40%), and the only run that passed it (0.0020) did so by 17 points on seed 42 and 20 on seed 7, which is partly luck.

**Option A (preferred): adopt `per_being` at 0.002; move the guard to a water-access follow-up.**
- Changes: `thirst_mode` default to `"per_being"`, `thirst_being_chance` stays 0.002 (Run 1: U2 pass, U3 pass, worst 18%). Guard moves to a new task that tunes ice reach (`start.ice`, `want.ice_urgent_below`, mining/ice want priority), one lever per run.
- Expected effect: unattended colonies still lose 11-17 colonists to thirst on seeds 42/1234/2026, 13 on seed 7, but 5 of 5 stay alive at 1,500; the follow-up must make seeds 42 and 7 spend more of their time dry for the guard to bite.
- Cost: data only for 7c (a default flip plus re-baseline of hashes); the guard bar is deferred, not changed; the follow-up is a data task.

**Option B: add a dry-duration ramp** (chance rises with consecutive dry sols, resets when ice > 0).
- Changes: new code and a new hidden counter plus two numbers (start chance, ramp per sol), then another calibration cycle.
- Expected effect: seeds 99/1234/2026 (short dry spells) barely change and still survive; seeds 42/7 (long dry spells) die faster, so the guard might pass at 2 of 5 but U3 on those two seeds gets worse (long spells at pop 10-14 are exactly where 42%/43% appeared).
- Cost: new code; contradicts the section 2 choice of a flat, readable rate; fixes the symptom on two seeds only.

**Option C: restate the bars, keep a higher rate.**
- Changes: U3 counts only windows starting at pop >= 15, or fails only when losses exceed 35% and 5 or more deaths (removes the small-pop noise case); guard stays 3 of 5; rate 0.0028 or 0.0024.
- Expected effect: Run 3 would pass U3 (42%/43% windows start at pop 12 and 14), but 5 of 5 still alive, so the guard still fails; Run 2 (4 alive, seed 7 extinct at 64%) still fails. It trades bar integrity for no guard gain.
- Cost: bar change only, no code, but weakens the "gradual and readable" test and does not solve the guard.

Design team views. Emergence: A keeps the exponential, per-person decay and lets water set the carrying capacity; B bolts a clock onto it. Feel: A keeps one plain line per death, spaced by sols; no hidden counters. Clarity: A keeps cause and effect readable (low outlook, dry line, named deaths, stop when ice returns); B adds a rule the player cannot see. Dissent: Emergence would accept a small-colony noise bar in C if the guard were kept honest; the other two lenses held that moving a bar to fit a result is the wrong habit.

Adopt now or stay off: adopt (switch on) at 0.002 under Option A. It is the only tested setting that passes U2 and U3, it is gentler on small colonies than the colony-mode rule, and it is the rule the section 1 fiction describes. Staying off keeps the colony-mode rule that failed U3 on 4 of 5 seeds at 5 h. Switching on shifts the RNG stream, so the pinned 300-sol hashes need a re-baseline in the same change (spec section 4).
