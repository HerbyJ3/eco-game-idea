# Influence powers (Task 7) — spec revision 2

Date: 2026-10-09. Rev 1 plus the three designer reviews (`docs/design/reviews/powers-emergence.md`, `powers-feel.md`, `powers-clarity.md`) and the owner direction. Influence only: a power changes conditions or probabilities, never orders a colonist.

Owner direction (Herby, 2026-10-09): the colony is **not** meant to survive unattended. Unattended decline must be gradual and readable; trouble must show early enough for a watching player to act; timely influence (never orders) must be able to turn it around. Attention should feel like responsibility and involvement, not a chore.

## Owner questions (short list; each has a recommendation, none blocks the build)

1. **Auto-pause on the first "Water: low" per crossing?** Strong for "responsibility", but it takes control of time from the player. Recommend: no for Task 7; revisit as a setting after playtest.
2. **Water tension beyond Guide.** Rev 2 gives Guide a cost (section 3) and notes that Grace is a long-term water mortgage (more people, more thirst). Emergence wanted Grace or Inspire to touch water directly. Recommend: leave it; adding a water role would be a new system. Say if you want one.
3. **Acceptance bars** in section 5 (lead time 10 sols, slope cap, pop-sols ordering) are estimates from arithmetic, not measurements. Confirm they express your intent: "a watching player has at least 10 sols (about 4 real minutes at 1x) to notice and act".
4. **Choosing the guided field** (nearer and safer against richer and farther) is deferred: fields are not selectable in the view yet. Recommend: later.

## 1. Purpose

Five influence powers in the simulation (headless, tested) and on the HUD, plus the one piece of information that makes them a responsibility rather than a chore: a **water outlook** that tells a watching player early that trouble is coming and which button helps.

## 2. API (sim)

- `SimWorld.use_power(name, target = -1) -> {ok, reason}`. On success: one `power_<name>` log line, then recharge starts. On failure: no recharge, `reason` is one of the codes in section 3.2.
- `SimWorld.power_ready_in(name) -> float` hours; `power_active_left(name) -> float` hours of effect remaining (0 = inactive).
- `SimWorld.water_outlook() -> {state, sols, ice, target}` (section 4). Pure read plus one stored float (`ice_at_sol_start`); no RNG.
- `SimWorld.dark_building_count() -> int`: finished buildings that are offline.
- All numbers in `data/powers.json`. Recharge is on the sim clock.
- **Hash-neutral when unused.** A run that never calls `use_power` draws the same random numbers and produces the same tables as before (pinned bed-fix hashes). The water outlook and its log lines must not change a hashed table. Engineer: check whether the event log feeds the hash; if it does, emit `water_low` / `water_ok` through a non-hashed advisory channel, and tell the game-designer.

## 3. The powers

### 3.1 Table (all numbers are data keys; recharge numbers adopted from designer-feel; estimates until calibration)

| Name | Target | Effect | Duration | Recharge |
| --- | --- | --- | --- | --- |
| `fortune` | none | Reactor supply x 1.5 (existing `buildings.fortune`); the 3 h re-online hold is cleared. | 1 sol | **4 sols** |
| `inspire` | a finished building | When builders choose what to build (after the reactor and green-room survival checks), they choose the target's kind with chance 0.75. Ends when a site of that kind starts or the duration ends. | 2 sols | **3 sols** |
| `grace` | a finished, online habitat | Conception checks in that habitat add 0.35 to the chance. | 1.5 sols | **3 sols** |
| `sign` | none | Unchanged from rev 1: awake indoor non-babies roll `pull = curiosity + 0.5 restless - 0.6 steady + U(-0.15, 0.15)`; idle colonists with `pull > 0.35` walk to a comms/archive neighbour, else any neighbour. | instant | **2 sols** |
| `guide` | none (default) or an ice-field index | See 3.3. | 1 sol | **3 sols** |

Keys: `recharge_sols.{fortune:4, inspire:3, grace:3, sign:2, guide:3}`; `inspire.{duration_sols:2, chance:0.75}`; `grace.{duration_sols:1.5, bonus:0.35}`; `sign.{restless:0.5, steady:0.6, jitter:0.15, threshold:0.35}`; `guide.{duration_sols:1, chance:0.7, need_floor:0.6}`.

At 1x a sol is about 25 real seconds, so the new recharges are 50 to 100 real seconds. If the 1-sol-cadence player cannot beat unattended (section 5), the first number to change is `guide.duration_sols` (1 to 1.5), alone.

### 3.2 Failure reasons (no recharge spent). Rev 1's `bad_target` is split (clarity C5)

| Code | When | HUD text (world's voice; data key `texts.fail.<code>`) |
| --- | --- | --- |
| `recharging` | not ready | "Not yet. The colony is still feeling the last one." |
| `unknown_power` | bad name | "That is not something anyone can do." |
| `no_target` | Inspire/Grace with nothing selected | "Choose a building first." |
| `not_finished` | target is a site | "That is still only a plan." |
| `not_habitat` | Grace on a non-habitat | "Only a home can be blessed this way." |
| `habitat_dark` | Grace on an offline habitat | "No one can settle in the dark." |
| `no_ice` | Guide with no live ice field (all dry or beyond suit range) | "There is no ice left to be drawn to." |
| `bad_field` | Guide with an index that is not a live ice field | "That field cannot be reached." |

### 3.3 Guide, rev 2 (emergence A1/A2/B1, clarity C3)

- **Target rule (clarity C3, adopted).** Guide always draws toward the **richest live ice field** (most ice left; live = ice left and round trip within the suit limit; ties go to the lowest index). Pits are no longer targets (regolith never needs a god). An explicit field index (tests and bots) is allowed only among live ice fields. No hidden target: it is named in the log and the HUD (below).
- **A weight, not an override (emergence A1, adopted).** While active, each time `choose_site` runs, with chance `guide.chance` (0.7) it returns the guided field and skips the ice/regolith roll; otherwise it runs the normal choice. The stop rule still holds: if stored ice is above `want.stop_factor` x target, Guide ends early (nothing to fetch). Draws the sim RNG only while a guide is active.
- **Need floor only for ice (A2, adopted).** While active, the ice term of a miner's need is at least `guide.need_floor` (0.6); the regolith term is untouched.
- **Cost (emergence B1; adopted in a small form).** (a) 70% of mining decisions go to one field for a sol, which may be the farthest, so trips are longer and the EVA/air guards of section 5 can catch a bad trade; (b) the extra volunteers are colonists not building, sleeping later or tending, because energy rules are untouched (W2 stays off); (c) a 3-sol recharge against a 1-sol effect leaves a gap the colony must carry. The design intent is that Guide is a push, not a fix: a player who only ever guides will still see a slow decline.
- **Guided vs total trips (A2, adopted).** Stats `guide_trips` (trips begun to the guided field while guidance was on), `ice_trips_total`, `guide_hauled` (ice delivered by those trips).
- **Log lines.** Use: `Guidance: the colony feels drawn to ice field 2 (310 ice left).` First volunteer: `{name} sets out for ice field 2.` (once per guidance; `name` is `Being.name`). Expiry: `Guidance ended: 5 trips, 38 hauled.` or, if nobody went: `Guidance ended: no one set out.` (so ignored guidance is never silent). Field numbering is the index in `resources.ice_fields` plus 1.

### 3.4 Other feedback lines (clarity C4/C6, feel; adopted)

All wording is data (`texts`), with `{name}`, `{label}`, `{n}` placeholders.

- **Fortune.** Use: `Good fortune: the reactors run hot for a sol.` plus, if `dark_building_count() > 0`, ` {n} dark rooms stir.` Expiry: `Good fortune ended: {n} of {m} dark rooms are lit again.` (m is the count at use). Fortune names buildings, not people.
- **Inspire.** Use: `Inspiration: the builders dream of another {label}.` When a site of that kind starts while active: `{builder} sketches another {label}.` (the colonist who starts the site). Expiry without a start: `The inspiration passed; no one started a {label}.`
- **Grace.** Use: names two adults in the habitat: `Grace: {a} and {b} linger together.` (fewer than two adults: `Grace: it feels like a good time to start a family here.`). Expiry: `Grace ended: {n} new lives begun in {habitat}.` (conceptions in that habitat during the window).
- **Sign.** `A light crossed the sky. {a} was pulled most and {z} least. {went} went to look, {stayed} stayed put.` Names come from the largest and smallest rolled pull among eligible colonists; with fewer than two eligible, counts only.
- **Ready again.** A quiet log line `{Power} is ready again.` for a power that has been used.

## 4. HUD and the water outlook (clarity C1, feel; adopted; part of Task 7)

### 4.1 Water outlook (`water_outlook()`)

State from stored ice against the target (`colony.ice_target()`; at 8 ice per being, target = 32.4 sols of use at one being's drink 0.01/h), with hysteresis:

| State | Rule | Data key |
| --- | --- | --- |
| `dry` | ice <= 0 | |
| `low` | ice < 0.5 x target. Leaves `low` only when ice >= 0.6 x target | `water.low_frac` 0.5, `water.low_clear_frac` 0.6 |
| `falling` | not low, ice < 0.8 x target, and ice fell by at least 0.01 x target since the start of the current sol | `water.falling_frac` 0.8, `water.falling_drop_frac_per_sol` 0.01 |
| `steady` | otherwise | |

`sols` = stored ice / (heads x `ice_per_being` x sol hours) — how long the stock lasts at today's drinking, ignoring supply. At the `low` threshold with unchanged population that is about 16 sols. Shown for `falling`, `low`.

### 4.2 What the player sees

- A **Water** line in the colony panel: `Water: steady` / `falling (about 22 sols)` / `LOW (about 14 sols)` / `DRY`. Low and dry in the warning colour.
- A log line when entering `low`: `The water tanks are below half: about {n} sols at today's use.` (kind `water_low`, once per crossing; re-armed after the state clears). A quiet `The water is holding again.` when it clears (`water_ok`). The existing `water_dry` stays.
- **Button marking.** When ready, Guide shows `[F5] Guide - ice low` while the state is `low` or `dry`; Fortune shows `[F1] Fortune - a room is dark` while `dark_building_count() > 0`. Otherwise plain `[F5] Guide`. Nothing else is marked (no nagging for Inspire, Grace, Sign).
- **Influence line** moves beside the Water line; shorter form: `[F1] Fortune ready  [F5] Guide 2 sols`. Under 0.5 sol: `soon`; otherwise one decimal. Active powers show time left: `Guide on (0.6 sols)`. The controls text lists the keys F1 to F5.
- A failed use shows the world-voice text from 3.2 for a few seconds.
- Inspire and Grace use the selected building; Guide ignores selection (C3).

Not in Task 7: auto-pause (owner question 1).

## 5. Acceptance (declared before running; replaces rev 1)

All numbers are estimates from arithmetic until the run measures them. Standard horizon, 1,500 sols, seeds 42, 7, 99, 1234, 2026, sampled every 10 sols (`--every 10`).

**Runs.** Unattended (`UN`) and the scripted player at three cadences using `tools/attentive_player.gd` with a new `check_h` set from `balance_run.gd --cadence <sols>`: `C1` = 1 sol (the main player test), `C2` = 2 sols (the sloppy player), `C025` = 0.25 sol (the idealised 6-hour upper bound, rev 1's player; **diagnostic only**, run if C1 fails). Required: UN plus C1 plus C2 = 15 runs; unattended reuses the step 4 results where the hashes match.

**The scripted player** (uses only the public API; no Sign, Grace, Inspire): at each check, if `water_outlook().state` is `low` or `dry` and Guide is ready, `use_power("guide")` (default target); if `dark_building_count() > 0` or reactor margin < 0 and Fortune is ready, `use_power("fortune")`. It records uses per power and the number of checks.

**Measures.** `pop_sols` = sum of population over the 10-sol samples. `first_thirst` = sol of the first thirst death (none = never). `low_sol` = first sol the state was `low`. `lead` = `first_thirst - low_sol`. Mean ice ratio = average of ice / target over samples while alive.

### 5.1 Unattended: gradual and readable (the owner's central test)

U1. **Unchanged:** powers unused, the 300-sol tables reproduce the pinned bed-fix hashes (42 a298dbb55b71d66e, 7 e540c1b86dabba26, 99 ffb6d5361bdb3a5d, 1234 bca08a0f327892fe, 2026 5fb3b699b4118a84).
U2. **Warned early:** on every unattended seed with a thirst death, `lead >= 10` sols (the stock at the low threshold is about 16 sols at constant population, so 10 leaves room for a falling population; about 4 real minutes at 1x).
U3. **Declines, does not collapse:** no 50-sol window loses more than 35% of the population at the window start, counted only for windows that start with population >= 10 (small colonies are noisy). Also report, per seed, sols from the first thirst death to population at most half the peak.
U4. **Not fine alone:** report seeds alive at 1,500 and each seed's final population. Two seeds currently reach 1,500, so this is a margin report, not a pass/fail; the owner's direction needs most unattended colonies to be clearly worse than attended, which U5 and A1 test.

If U2 or U3 fail, the unattended behaviour is already shipped (W3), so do not retune powers: report and make it an owner decision (the lever would be a new water-pressure rule, a separate spec).

### 5.2 Attention helps, in proportion

A1. **Attention beats neglect:** `pop_sols(C1) >= pop_sols(UN)` on every seed, strictly greater on at least 4 of 5; and `first_thirst(C1)` is later than UN or never on at least 4 of 5.
A2. **The sloppy player lands between:** `pop_sols(C1) >= pop_sols(C2) >= pop_sols(UN)` on at least 4 of 5 seeds, and the sum over seeds is strictly ordered the same way.
A3. **Turn-around is possible:** C1 alive at sol 1,500 on at least 3 of 5 seeds. (Rev 1 asked 4 of 5 at a 6-hour cadence; a 1-sol cadence is the honest player, so the bar is lower. Estimate.)

### 5.3 Pressure is felt; attention is not a chore

P1. **Pressure remains:** with C1, the mean ice ratio is below 1.0 on at least 2 of 5 seeds, and a `low` episode happens on at least 3 of 5 seeds (the game still asks for the player).
P2. **Not constantly alarmed:** with C1, the colony is in `low` for at most 30% of sampled sols on at least 4 of 5 seeds.
P3. **Not a chore:** report per seed the uses of Guide and Fortune per 100 sols for C1 and C2. Maximum possible per 100 sols is 33 (Guide) and 25 (Fortune). Pass if the mean over seeds is at most 50% of the maximum (Guide at most 16, Fortune at most 12 per 100 sols). Also report the share of Guide uses made while the state was `low` or `dry` (the scripted player only acts then, so this should be 100%; it exists to catch a rule change).
P4. **Guide is a push, not a fix:** report `guide_trips / ice_trips_total` for C1 (expect roughly 0.3 to 0.7 in the guided sols); no pass/fail.

### 5.4 Guards

G1. No air deaths, no EVA deaths, and no more air turn-backs than UN on any C1 or C2 seed (Guide's longer trips are the risk).
G2. No `use_power` call changes any pinned table when the player never calls it (U1).
G3. Report: sols from the first thirst warning to the first death (feel), and `lead` per seed.

### 5.5 Log-only test (not a balance run)

`tests/test_powers.gd`: on all five seeds, fire Sign at sols 20, 100, 300 (when at least 4 colonists are eligible); in each cast `0 < went < eligible`. Also: `water_outlook()` states for hand-set ice values (including hysteresis), each failure code, Guide target = richest live ice field, a stale selection does not matter, expiry lines exist (including "no one set out"), Fortune expiry count, unused-power hash neutrality.

### 5.6 If it fails

One power number at a time, recorded. Order of suspects: A1 or A3 fail: `guide.duration_sols` 1 to 1.5, then `guide.chance` 0.7 to 0.8, then `recharge_sols.guide` 3 to 2. P2 fails (always low): the attentive player is not turning things around, same suspects. P3 fails: raise recharges (not lower). Anything that changes a sim number repeats step 5 of the task plan.

## 6. Scope

Cut order if time is short (feel): Grace, then Inspire. Keep Fortune, Guide, Sign, and the water outlook (it is not optional; it carries the owner's direction). The Sign "pull miners off duty" idea (emergence) is rejected (Sign only moves idle colonists, which is the point of an influence).

Out of scope: beings sensing a god (culture stage), emotions (6a), new art (buttons stay text), the power reserve rule (Task 8), choosing the guided field, auto-pause.

## 7. Review log (rev 1 -> rev 2)

Source files in `docs/design/reviews/`. Status: **A** adopted, **R** rejected with reason, **Q** owner question.

| Finding | Status | Where / reason |
| --- | --- | --- |
| E-B1 Guide+Fortune reflex; add cost / water role for Grace or Inspire | A in part, Q2 | Guide gets a cost (3.3); Grace noted as a water mortgage. Direct water role for Grace/Inspire **R** (new system, small team) and put to the owner |
| E-B2 acceptance measures survival not decline | A | Section 5: pop_sols, bounded slope U3, lead U2, sloppy bot A2, margins |
| E-A1 Guide override is command-like | A | Weight 0.7 (3.3) |
| E-A2 floor only on guided resource; guided vs total trips | A | 3.3, P4 |
| E-A3 attentive bot is idealised; run 1-sol | A | C1 is the main test; 0.25 sol is diagnostic |
| E-idea Sign pulls miners off duty | R | Sign moves idle colonists only; an influence should not pull a worker off a task |
| E-idea log failures / ignored guidance | A | HUD failure text; "no one set out" expiry line |
| F recharges 2/3/3/3/4 | A | 3.1 |
| F lazier player still beats unattended | A | A1 uses a 1-sol cadence; A2 for 2 sols |
| F HUD: "soon", ready-again log line | A | 4.2, 3.4 |
| F named colonists in log lines | A | `Being.name` (String) is used for Inspire, Grace, Sign, Guide; Fortune names buildings (no colonist is the actor) |
| F failure text in the world's voice | A | 3.2 |
| F keys in controls text; shorter Influence line | A | 4.2 |
| F report first thirst warning to first death; pressure remains | A | G3, P1 |
| F Sign split never all-or-nothing | A | 5.5 |
| F scope cut order Grace, Inspire | A | 6 |
| C-C1 water warning, log line, button marking | A | 4; Task 7 includes it |
| C-C2 warning-lead criterion, slow bot, use counts | A | U2, A2, P3 |
| C-C3 Guide's hidden target | A | richest live ice field, named in log and HUD; pits dropped |
| C-C4 expiry and outcome lines; active powers shown | A | 3.3, 3.4, 4.2 |
| C-C5 split bad_target; log failures | A | 3.2 |
| C-C6 Fortune reports rooms back online | A | 3.4 |
| C-adv Influence line near water panel; "N sols until ready" | A | 4.2 (shown as "2 sols", "soon") |
| C-adv auto-pause on first low | Q1 | recommend no for now |

Dissent recorded: emergence wanted Grace or Inspire to matter for water (rejected for scope); clarity wanted the guided field highlighted on the map (deferred: the log and HUD name it, the map highlight needs selectable fields; owner question 4); feel wanted one-sol cadence for the main test while clarity wanted a 2-sol bot — both are run (C1 main, C2 sloppy).

## 8. Implementation work this creates (godot-engineer; sim-test-engineer for 5)

1. `data/powers.json`: new recharge numbers; `guide.chance`; `water.*`; `hud.soon_below_sols` (0.5); `texts` (failure reasons, log templates).
2. `SimWorld`: failure codes; Guide target rule and ice-only sites; `power_active_left`, `water_outlook`, `dark_building_count`, `ice_at_sol_start`; expiry, ready-again, water_low and water_ok lines; stats `guide_trips`, `ice_trips_total`, `guide_hauled`.
3. `choose_site` / `Being` guide hook: weight 0.7 instead of override; need floor applied to the ice term only.
4. Named log lines (Inspire builder, Grace pair, Sign most and least, Guide first volunteer).
5. `tools/attentive_player.gd` and `tests/balance_run.gd`: `--cadence <sols>` (sets `check_h`), outlook-based trigger, default Guide target; per-run output of uses, `low_sol`, ice ratio mean, share of samples in `low`. Summary script for 5.1 to 5.3.
6. HUD: Water line, button marking, shorter Influence line, active-power times, "soon".
7. Tests per 5.5.
