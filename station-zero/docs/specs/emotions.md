# Spec: emotions (Task 6a): Deimos sets temperament, events push mood, mood changes two small behaviours (revision 1, draft for the three assistant reviews)

Source of truth: HANDOFF.md sections 1, 2, 3 (Deimos weight 0.20, inner boost 1.5; the Earth chart has a Moon, no Deimos), 4, 5 (Social), 8, 10. Owner decisions for this slice: `docs/design/task-6-scoping.md`, "Owner decisions (Herby, 2026-10-08)". Plan: `docs/tasks/task-6-plan.md` (6a, steps 1 to 9, constraints in its section 4). Format and discipline modelled on `docs/specs/relationships.md` (revision 8) and `docs/specs/council.md` (revision 6). Facts read from code and data: `sim/persona.gd`, `sim/sky.gd` (chart keys), `sim/being.gd` (`drain_per_h`, `_restless_travel`, `decide`), `sim/world.gd` (phase order of `step()`, `_create_founders`, `_create_newborn`, `add_being`, `_kill`), `sim/relationships.gd` (tick, `_deaths`, `_decay_and_flags`, `_growth`, `friend_count`, `present`, `ticks`, the packed mirror `_sk _sl _sh _sf _sp`), `sim/council.gd` (`_readings` reads that mirror), `sim/ages.gd` (the "calm" and "rested" clauses read energy), `tests/balance_lib.gd` (table columns, T1 to T12, hash), `data/persona.json`, `data/signs.json`, `data/beings.json`, `data/relationships.json`, `data/council.json`, `data/ages.json`, `docs/balance/task-5-log.md` (the "before" figures).

Locked decisions respected:
- **Hidden birth chart.** Only effects are shown. The Deimos (or Moon) sign is never named, shown or counted; the player sees a mood sentence and, for strong cases, one sentence about how a being takes things.
- **Influence-only god.** No power reads or writes a mood in 6a (none of Inspire, Grace, Send a sign exists yet). A future "send a dream" would be a push in the table of 5.3; recorded, not built.
- **Naturalism, ages not meters.** No mood bar, number, icon, tint or colony-wide mood word reaches the player. The balance table has a debug column (`md`); the HUD never reads it.
- **Per-being energy, power as a budget, ice pressure is not failure.** Energy stays per being and mood bends it by a bounded factor; no power, oxygen, food, ice, regolith or building state is written. Ice pressure may lower moods; it is never made worse by them in any way the guard in 5.5 and 12 does not bound.

Tunables live in `data/mood.json` (new). No tunable in the new module `sim/moods.gd` and no literal in the two edited behaviour sites in `sim/being.gd`. This spec describes behaviour and numbers only, no code. **Every number marked E is an estimate until the calibration probe (section 12) measures it.**

## Owner decisions (Herby, 2026-10-08), as binding for this spec
- **A.** 6a is first, with two 6p items folded in: a public read-only accessor for the relationships packed mirror (section 9.1, replaces the Council's private reads) and a being inspect panel carrying the K1 sentence "{name} knows no one well yet." (section 7).
- **B.** Emotions change behaviour now. A baseline reset is accepted. It must be recorded: old and new table hashes per seed, each seed run twice with identical output, T1 to T12 and the Task 3 ages and Task 5 Council results measured before and after (section 10).
- **C.** Deimos sets each being's baseline mood and its recovery rate. Events push mood away from the baseline and it decays back (5.1 to 5.3).
- **D.** Text only. No new art, no meter, no colony-wide mood word, texture budget untouched (47.1 of 48 MB).

## Open for the owner (options as posed)
Three questions, each with the recommendation first. The spec is written to option (a) of each. None blocks steps 1 to 4.

**Q1. How much of a being's temperament may the inspect panel say?** (HANDOFF section 2: "Only its effects are visible".)
- (a) **Recommended: say it only for the strong cases.** One extra sentence, for about a third of the colony (four of the twelve Deimos or Moon signs, E): "{name} usually sees the bright side.", "{name} takes things to heart.", "{name} is slow to shake off a mood.", "{name} soon shakes off a mood." They describe what the being does, not the chart. Cost: a few beings are labelled; the rest are read from how long their moods last. Facts: with no sentence at all the Deimos baseline would be invisible in calm colonies, where mood rarely leaves its baseline (section 6).
- (b) No temperament sentence ever. Cost: the owner's decision C is only visible as slow versus quick recoveries in the log and panel over many sols. Safest for the hidden chart.
- (c) A sentence for every being. Cost: the panel starts to read like a character sheet; edges toward naming the hidden chart.

**Q2. If the reset moves the Council and it stops reaching its targets, what then?** (Council entry and the dome pledge depend on friendship webs, which any behaviour change moves; seed 1234 clears the carry quorum by only 0.02.)
- (a) **Recommended: report and accept.** 6a measures Council entry sols, meetings and pledges before and after and reports them. No `council.*` key is retuned in 6a. If C1 (Council on at least 3 of 5 seeds) or C4 (a pledge on at least 1 seed) fail after the reset, the failure is recorded as a known issue and a Council recalibration becomes its own sub-task on the new baseline. Facts: retuning the Council inside 6a would be a second behaviour change in one slice (the reason Task 5 refused the water rule).
- (b) One Council lever allowed in 6a (`dome.lean.base` or `decide.carry_quorum`), chosen by the lead, one run. Cost: 6a grows by a run and a review, and the pledges are fitted again to five seeds.
- (c) Block the reset: if C1 or C4 fail, reduce the mood gains until they pass. Cost: the owner's decision B is then bent by a target that is itself an estimate.

**Q3. When is the old hash chain retired?** (The Task 1 to 5 table hashes have been the regression bridge for five tasks.)
- (a) **Recommended: keep it as a dormant-mode proof until 6a closes, then retire it.** With both gains at 0 the mood layer must reproduce all 20 old hashes (Task 1, 3, 4, 5) once the new `md` column is dropped (section 10, step 2). That proof is run at the dormant build (section 10, step 2, inside plan step 4) and kept as a test (`tests/test_moods.gd`, test 25) so a later change cannot silently break the bridge; at the 6a close the owner may delete the test, and the new Task 6a hashes become the only reference.
- (b) Retire the chain now, at the moment the gains are switched on. Cost: no machine proof that the new module added no side effect beyond its two gains.
- (c) Keep the chain forever as a switch (gains at 0 must always reproduce Task 5). Cost: every later behaviour change in Tasks 6b to 6d has to keep the dormant path alive.

## 0. The design in one paragraph
Every being carries one private number, its **mood**, between about -0.9 and +0.9, that rests at a **baseline** and returns to it at a **recovery rate**; both come from the being's Deimos sign (for the seven Earth-born founders, from the Moon, the inner placement of an Earth chart). Things that already happen in the colony push the mood away from its baseline: a new friend, a bond growing close, a friend lost, a death of someone close (grief), a child born where one was present, a hard sol of short air, food or ice, the colony settling or slipping back, a Council pledge, and an hour spent with a friend. Pushes shrink as a mood nears its limits, and between pushes the mood decays back at the being's own rate: a steady Deimos is back to itself in two sols, a mutable water Deimos stays heavy for ten. That is the whole model: one number, one baseline, one rate, eleven pushes, no new RNG. Mood changes exactly two things beings do: how likely they are to wander to another room when they would otherwise stay (low spirits withdraw, bright spirits roam), and how fast they tire when idle (heavy hearts tire sooner). Both effects are small and bounded, so the same colony with the mood layer on plays out almost the same but not byte-identically: every table hash changes, which the owner has accepted. The player sees mood only as words: a being inspect panel ("Vana-3 is out of spirits. They are still mourning Kiro-12."), and two rare log lines ("Vana-3 has gone quiet since Kiro-12 died.", "Vana-3 is smiling again."). Nothing counts, nothing fills.

## 1. Purpose
Since Task 0 the chart's Deimos placement ("inner, emotional self", HANDOFF 3) has shaped only two traits through a 20 percent weight, and the relationships and Council layers made things happen to people (friendship, grief, drift, a promise) that change nothing about how they behave afterwards. Emotions give those events a consequence the player can read, give the chart a second channel beyond the six traits (two beings with the same two-word description can differ in how they weather grief), and give 6b (AI minds) the "mood" its prompt needs. The design question is how much: enough that a named being's behaviour can be explained from the log and the panel, little enough that personality (the six traits) still decides who people are and the ice crises of Task 1 are not made worse by a feeling.

## 2. Terms
| Term | Meaning |
| --- | --- |
| mood `m` | per-being float, the present spirits. Starts at the baseline |
| baseline `b` | the being's resting mood, fixed for life, from the temperament table (5.1) |
| deviation `d` | `m - b`. Bands, reasons and the "why" read `d`; behaviour reads `m` |
| half-life `H` | sols for a deviation to halve; fixed for life, from the temperament table |
| decay fraction `k` | `1 - 0.5^(tick_h / (H x sol_h))`, per mood tick; precomputed at creation |
| mood tick | one tick per relationships tick (`relationships.tick_h`, 1.0 sim hour, every 20th step) |
| push | a signed amount added to `m` at a mood tick, scaled by headroom (5.3) |
| headroom scale | `clamp(1 - d / ceil_dev, 0, 1)` for a positive push, `clamp(1 - d / floor_dev, 0, 1)` for a negative one (`ceil_dev` +0.70, `floor_dev` -0.70) |
| band | one of heavy, low, even, light, bright, read from `d` with hysteresis (5.4) |
| why | the push that most explains the present deviation: `{key, id, name}` or null (5.4) |
| inner placement | the Mars chart's `deimos`, the Earth chart's `moon` (data `temperament.inner_key`) |
| company | a mood tick at which the being was awake and together (room, site or field) with at least one friend at the relationships tick |

## 3. State (all new)
`Being` gains eight fields (the Task 4 layer added none; this one needs them because `Being` reads two of them on its hot paths and they are per-being by nature): `mood`, `mood_base`, `mood_halflife` (sols), `mood_k`, `mood_band` (int 0 heavy .. 4 bright), `mood_why` (Variant, null or `{key, id, name}`), `mood_quiet_t` (sim hour of the last "gone quiet" line, -1e9 at start), `mood_down_t` (sim hour of an unanswered "gone quiet" line, null otherwise). Defaults for a being made without a chart (test seam `add_being`): `mood 0.0`, `mood_base 0.0`, `mood_halflife = temperament.neutral.halflife_sols`, `mood_k` derived from it, `mood_band 2`, `mood_why null`.

`Moods` (new, owned by `SimWorld` as `world.moods`) holds only: `cfg`, `seen_ticks` (int, the last relationships `ticks` consumed), `seen_age_changes`, `seen_pledge` (bool), `max_id_seen` (int, newborn detection), `pending_hard` (Variant, null or the clause key set at a sol boundary), `pending_age` (Variant, null or `"up"` / `"down"`), `pending_pledge` (bool), `lines_sol`, `lines_this_sol`, `agg` (the last tick's sum, sum of squares, heavy count and size, for the per-sol series). `SimWorld` gains `moods`, `moods_enabled` (default true; false skips both hooks and gives every new being the neutral temperament, test seam), the hook calls, and `stats.moods` (section 8).

`Relationships` gains three read-only outputs and two accessors (9.1): `events` (per tick), `with_friend` (per tick, packed by being id), `friend_pairs()`, `friends_of(id)`. It writes no more state of its own than before.

## 4. Where it runs
- **Creation**: in `SimWorld._init`, after `council.begin(...)` on both branches: `moods.begin(self, founders_world)`. A founder world appends one initial reading to the three per-sol series (section 8), because `_init` appends the initial `pop_by_sol` entry; a blank world appends none (rule as in relationships.md section 4). Temperaments are not set here: they are set where beings are made (below).
- **Where beings get a temperament**: `_create_founders` (from `birth.chart`), `_create_newborn` (from the chart already computed there for `persona_from`; the chart variable is kept instead of discarded), `add_being` (neutral). One static call, `Moods.temperament(chart)`, returns `{base, halflife}`; the caller writes the Being fields. No draw.
- **Mood tick (phase 11c)**: in `step()`, directly after `relationships.on_step(...)` and before `council.on_step(...)`: `moods.on_step(self)`. It acts only on steps where `world.relationships.ticks` differs from `seen_ticks` (the same cadence rule the Council uses), then sets `seen_ticks`. If relationships is null or disabled, moods do nothing (mood is frozen at its starting value; test seam).
- **Sol hook**: inside the `if _sol_started:` block, after `council.on_sol(self)`: `moods.on_sol(self)`. It only records pending colony-level pushes and appends the three per-sol series (section 8); it loops over no beings. The pushes are applied at the next mood tick (at most 1 sim hour later).
- No wall clock, no RNG, no read of the log, no write to colony, buildings, resources or powers.

## 5. Rules
### 5.1 Temperament (set once, at creation)
`inner placement` sign `s` of the being's chart (`chart[temperament.inner_key[chart.world]]`); `e = signs[s].element`, `q = signs[s].modality`.
- `base = element_base[e] + modality_base[q]`.
- `halflife_sols = halflife_modality[q] x halflife_mult_element[e]`; `mood_k = 1 - 0.5^(relationships.tick_h / (halflife_sols x sol_h))`.

Starting values (E; all in `data/mood.json`, `temperament`):
| element | base | half-life multiplier | | modality | base | half-life, sols |
| --- | --- | --- | --- | --- | --- | --- |
| fire | +0.12 | 0.9 | | cardinal | +0.03 | 4.0 |
| air | +0.06 | 1.0 | | fixed | 0.00 | 2.0 |
| earth | -0.04 | 0.8 | | mutable | -0.03 | 8.0 |
| water | -0.14 | 1.3 | | | | |

Resulting spread: baselines from -0.17 (mutable water) to +0.15 (cardinal fire), mean 0.0 over the twelve signs (uniform Deimos, so a colony's mean baseline is about 0, E). Half-lives from 1.6 sols (fixed earth) to 10.4 sols (mutable water), a 6.5-fold range; `mood_k` per hour 0.0174 down to 0.0027.
Why these: the **baseline** is a small lean (the six traits carry most of the personality; a baseline of 0.15 changes travel by 0.02 and idle drain by 4 percent, 5.5); the **recovery rate** is the large temperament lever, because it decides how long a grief or a hard season lasts (5.5 worked numbers). Fixed signs recover fastest: they are the "steady" signs in the chart table ("steady keep working"), and a fixed Deimos stays calm in a crisis. Mutable signs recover slowest and, being pushed repeatedly by a changing colony, swing hardest (scoping note C, option 1). Water takes things to heart (lower baseline, slower recovery), fire lifts quickly. The element and modality tables are the existing `signs.json` classification, not a new one; the numbers are the lead's, E. The Deimos sign already contributes 20 percent of the six traits (inner boost 1.5 on care and sociability); mood reads the sign itself, so it is a second channel and not a restatement of the traits (two beings with the same two-word description can differ here).
**Earth-born founders** have no Deimos (HANDOFF 3: sun, moon, rise). Their inner placement is the Moon (weight 0.3, inner boost 1.4), so `temperament.inner_key = {mars: "deimos", earth: "moon"}`. Stated as a decision: the seven founders are tempered by the Moon.
**Neutral** (test seam beings, `moods_enabled` false): `base 0.0`, half-life `temperament.neutral.halflife_sols` 4.0.

### 5.2 The mood tick (every relationships tick, in this order)
1. **Newborns.** Beings with id above `max_id_seen` (scanned from the end of `world.beings`, which is in ascending id order) are newborns; update `max_id_seen`. A newborn's mood is its baseline already (set at creation). If it has a recorded `parent_id` that is alive and its `born_t` is within this tick, the parent gets the `birth_parent` push (5.3) with why `{birth, id: newborn id, name}`.
2. **Decay.** For every living being: `m += (b - m) x k`; if `abs(m - b) < rest_eps` (0.001), `m = b`. One pass over `world.beings`.
3. **Event pushes** from `world.relationships.events` (5.3), in list order, each scaled by headroom, applied to a being found by id (a being no longer alive is skipped).
4. **Colony pushes** from `pending_hard`, `pending_age`, `pending_pledge` (5.3), then cleared. One pass over `world.beings`.
5. **Company.** For every being with `relationships.with_friend[id] != 0`: the `company` push (5.3). Part of the same pass as step 4 when a colony push is pending, else its own pass; either way at most two passes in all.
6. **Bands and why.** For every being: band with hysteresis (5.4); clear `mood_why` when `abs(d) < why.show_dev`; update the aggregates (`sum`, `sum of squares`, heavy count).
7. **Lines** (5.6).
Steps 2, 4, 5 and 6 can be one pass in the implementation; the order of effects on a single being is fixed as written (decay, event pushes, colony pushes, company, band).

### 5.3 The pushes
Every push `p` on a being with deviation `d` (taken just before the push) becomes `p x scale` (headroom scale, section 2), so a mood can approach `b - 0.70` or `b + 0.70` but never pass it, a long run of bad news saturates instead of stacking, and the order of pushes inside a tick changes the result only through a bounded, deterministic amount (events arrive in a fixed order).
| Push key | Who | Amount (E) | Source |
| --- | --- | --- | --- |
| `friend` | both of a pair | +0.10 | `friends` false-to-true on a pair that is neither `kin` nor `crew` (relationships 5.5). Every such crossing, line or not |
| `close` | both | +0.15 | `close` false-to-true, any pair |
| `lapse` | both | -0.05 | `friends` true-to-false on a pair that is neither `kin` nor `crew` (alive on both sides) |
| `lapse_close` | both | -0.12 | `friends` true-to-false on a `was_close` pair (replaces `lapse`) |
| `grief` | each mourner (every living being with a bond at or above `lines.friend` to the dead, not only the two named in the log) | `grief_min` -0.25 at bond 0.30 to `grief_max` -0.60 at bond 1.0, linear in bond | relationships 5.1 |
| `birth_parent` | the recorded parent of a newborn, if alive | +0.08 | step 5.2.1 |
| `hard_sol` | every living being | -0.02 per hard sol; not applied to a being with `d <= hard_floor_dev` (-0.30) | a sol boundary at which air, food or ice is short, using the same three clauses and data keys as `Council._hard_entry` (`ages.sample.o2_min_fraction`, `food_min_fraction`, `ice_min_sols`) |
| `age_up` / `age_down` | every living being | +0.10 / -0.10 | `age_changes` rose and the new age is not Landing after Landing / Landing after not-Landing. Settlement to Council and back give no push (Council has its own) |
| `pledge` | every living being | +0.10 | the Council's first and only pledge (`stats.council.pledge_sol` set) |
| `company` | each being with a friend together with it this tick | +0.006 per tick | `relationships.with_friend` |
Kin and crew bonds make no `friend`, `lapse` or `lapse_close` push: their seeding and thinning are silent in the log (relationships 5.2, 5.5) and would otherwise hit the seven founders with up to six lapses each around sols 18 to 30. A kin or crew bond that was `was_close` and lapses does give `lapse_close`. The `company` push does count kin and crew (a child glad of its parent's company).
Why the grief pushes everyone with a bond and not two: the log names at most two mourners per death (a reading budget), but mood is per being; a death in a well-connected colony can touch ten people, and that is what the headroom scale and the floor are for (5.5).
**Colony pushes** are recorded at a sol boundary and applied at the next mood tick so the sol hook stays O(1). The `hard` clause that gets the "why" is the first of ice, air, food that is short, in that order (the order of `Council.hard_clause` ties).

### 5.4 Bands and the "why"
Bands read the deviation, so a being that is gloomy by nature is not "out of spirits" at rest:
| Band | Condition on `d` | Index |
| --- | --- | --- |
| heavy | `d <= -0.40` | 0 |
| low | `-0.40 < d <= -0.18` | 1 |
| even | `-0.18 < d < +0.18` | 2 |
| light | `+0.18 <= d < +0.40` | 3 |
| bright | `d >= +0.40` | 4 |
Hysteresis `bands.hyst` 0.03: a being moves to a neighbouring band only when `d` is 0.03 past the line, so a mood hovering on a line does not flip the text every hour. Keys `bands.heavy`, `low`, `light`, `bright`, `hyst`.
**The why.** When a push with scaled magnitude at least `why.min_push` (0.05) is applied, it becomes the being's `mood_why` if the being has none, or if the push is at least half the present `abs(d)` (it is a big part of the present mood). `hard_sol`, `company` and `age_*` pushes may set a why only when none is set and `abs(d) >= why.show_dev`; the `hard_sol` why carries the clause. `mood_why` is cleared when `abs(d) < why.show_dev` (0.10). So the panel names a cause for as long as the mood is clearly off its baseline, and says nothing when it has settled.

### 5.5 What mood changes: exactly two behaviours, gains in data
Both behaviours read the being's own mood and read it clamped to `effects.clamp_low` -0.60 to `effects.clamp_high` +0.40. Neither adds, removes or reorders a random draw. Starting gains for the calibration runs (the decision rule of section 10 may halve them; both are 0.0 in the dormant build of step 2 and in the dormant proof): `effects.travel_coef` 0.15, `effects.energy_coef` 0.25.

**Effect 1: company-seeking. `Being._restless_travel`.** The chance to travel to a neighbouring room is `restless.travel_base + restless.travel_coef x restless` today (0.08 + 0.32 x restless, which is 0.08 to 0.40). It becomes that plus `effects.travel_coef x clamp(m)`, floored at `effects.travel_floor` 0.02 and capped at 1.0. Still one `chance()` draw per call, same position in `decide`. The pull toward rooms (`room_pull`, relationship pulls) is unchanged.
- Size, E: for a middling restless 0.4 (chance 0.208) a mood of 0.1 moves the chance by 0.015 (about 7 percent relative); grief at -0.5 moves it by -0.075 (about -36 percent relative, for the sols the grief lasts); the colony-wide mean shift is under +-0.01. Deimos baseline alone (+-0.15) moves it by +-0.02.
- What it does to existing systems: it changes only how often a being who has nothing else to do wanders (the last branch of `decide`). Sleep (first branch), joining construction, resuming and starting mining (branches 2 to 4) come before it and read no mood. Withdrawn beings stay put, so they stay where they already are with whoever is there; bright beings roam and meet more rooms. Bonds follow their days (relationships), so over a run mood slightly spreads who meets whom; the relationship targets R3, R4, R10, R11 are re-judged after the reset (section 12).
- Personality guard (12, M3): the mood term at its clamps spans -0.09 to +0.06 (0.15 wide), against the restless trait term's 0.32 wide; the mood span is 0.47 of the trait span at the clamps and, with the typical |m| under 0.1, about 0.05 of it.

**Effect 2: tiredness. `Being.drain_per_h`, idle branch only.** Idle drain `energy.drain_idle` (1.3 per hour) is multiplied by `1 - effects.energy_coef x clamp(m)` (a factor from 0.90 at `m` +0.40 to 1.15 at `m` -0.60). Sleep (no drain), EVA, work and mining drains are unchanged: a being doing survival work does not tire faster because it is sad.
- Size, E: at the clamps +-10 to 15 percent of idle drain; a grieving being (m -0.5) loses 0.2 energy per idle hour more (1.3 to 1.5); the mean over a run is within +-2 percent (mean mood about 0). Expected shift of the table's `avgE` and `asleep%` columns: under 1 point and under 0.5 point (the sleep threshold 28 and the night threshold 65 are unchanged, so a heavy being simply goes to bed somewhat sooner). T8 asks for avgE 40 to 90 and asleep 5 to 30 percent; measured 54 to 58 and 10.6 to 10.9, so the margin is large.
- What it does to existing systems: **energy** (a bounded per-being bend, as above); **sleep** (earlier, never later than today, for the low-mood; slightly later for the bright; the draws `night_sleep_chance` and `day_wake_chance_per_h` keep their form); **work and mining** (only through energy: the yield factor `0.55 + energy / 220` falls 0.0045 per energy point, so one mean point lost is about -0.6 percent mining yield, E; construction rate uses the same factor); **births** (untouched: `Colony.birth_chance` reads traits only); **Council lean** (untouched: lean reads traits, stocks and the child stake only; the Council moves only through the changed trajectories, which Q2 covers); **ages** (the "calm" and "rested" clauses read energy, so the Settlement entry and the fall-back sols can move by a few sols; re-measured and reported, not judged against 67, 58, 54, 65, 53, section 12).

**Death-spiral guard, argued from the code.** The spiral the brief names is grief to lower energy to more deaths to more grief. In this sim no death cause reads energy: deaths are `air`, `thirst`, `hunger` (colony stocks) and `suffocated outside` (suit air). Energy touches the stocks only through mining and building yield (-0.6 percent per mean point). The loop therefore has gain far below 1: even if every being sat at the mood floor (`m` -0.6 effective), idle drain would be +15 percent, mean energy at most about 3 points lower (E), mining yield about 2 percent lower, ice supply about 2 percent lower. The chain is also broken at its source, five ways: (1) mood reads nothing about energy or sleep; (2) the energy effect is idle-only; (3) the pushes are headroom-scaled with a hard `hard_sol` floor at d -0.30, so mass grief saturates at about -0.70; (4) the effect clamps at -0.60; (5) the mood never touches mining will, volunteering, births, stocks or air. The probe checks it anyway (M4), against 15 seeds.
Worked example, E: bond 0.5 grief gives -0.25 - 0.35 x (0.2 / 0.7) = -0.35 on a cardinal air Deimos (half-life 4.0): `d` returns inside the low band (-0.18) in 3.8 sols, below `show_dev` 0.10 in 7.2 sols. The same push on a mutable water Deimos (10.4): low for 10.0 sols, off the panel in 18.8 sols. On a fixed earth Deimos (1.6): low 1.5 sols, off the panel in 2.9 sols. A bond-0.8 grief (-0.50 at full headroom) is heavy (`d <= -0.40`) for 0.6 sols (fixed earth), 1.4 (cardinal air), 3.7 (mutable water).
Steady offsets under a long hard season (`hard_sol` -0.02 a sol, E): `-0.02 / (1 - 0.5^(1/H))` is -0.07, -0.13, -0.24, -0.29 for H 2, 4, 8, 10.4 (floored at -0.30 by `hard_floor_dev`): a steady colony stays even, a mutable one goes low. Ice pressure shows in the slow beings first and never in everyone at once.

### 5.6 The two log lines (individual stories, capped)
Only two kinds of mood line, both about one named being, both fixed texts:
- **`mood_quiet`**: logged when a being's band changes into heavy, it has `mood_down_t` null and `t - mood_quiet_t >= lines.quiet_cooldown_sols` (20). Sets `mood_quiet_t` and `mood_down_t`.
- **`mood_relief`**: logged at the first mood tick with the band at or above even and `mood_down_t` set and `t - mood_down_t >= lines.relief_min_sols` (3 sols). Clears `mood_down_t`. If the band is below even at that tick it waits.
Cap: at most `lines.max_per_sol` (1) mood lines per elapsed sol, colony-wide. Candidates in a tick are offered in ascending being id; a candidate over the cap is dropped, not queued (counted in `stats.moods.lines_dropped`; its `mood_down_t` / `mood_quiet_t` is still set for a quiet line, so the pair stays consistent, and a dropped relief leaves `mood_down_t` set so it is offered again at the next tick). Text choice for a quiet line by the being's `mood_why.key`: `grief` gives `quiet_grief`, `lapse` or `lapse_close` gives `quiet_lapse`, `hard_sol` gives `quiet_hard`, anything else `quiet`. The log entry carries `being_id`, `other_id` (the why's id or null), `place` "" and `building_id` null, like the relationship entries, so click-to-focus can come later without a sim change.
Why so few: at most one a sol, and only for a being that has really gone heavy (a bond-0.7 grief or deeper, or stacked news on a slow Deimos). Expected: 0 to 40 quiet lines a run (E), zero on a calm seed. The existing grief line ("{a} is mourning {b}.") and friend lines tell the cause; the quiet line tells that it lasted.

## 6. Numbers, and what they imply (all E)
- **A calm colony is calm.** Sustained pushes in a peaceful seed are small: a typical being forms a new friendship every few dozen sols and has about two hours a sol with a friend. Steady-state offset from company alone is `0.006 x hours / (1 - r)` where `r = 0.5^(1/H)` is the daily retention: for 2 hours a sol, +0.015 to +0.08 depending on H (2 to 8 sols); for 4 warm hours on a slow Deimos, +0.25. Friend and close pushes add a few hundredths. So in a calm seed the typical deviation stays within +-0.1, the panel reads "much as usual" for most beings, and the visible variation is the Deimos baseline and the lift of well-befriended, slow-recovering beings. That is the intended texture ("weather rarely, climate always"), and it is why Q1 (a) matters: without a temperament sentence the player sees little in a calm colony.
- **Crises color a colony.** A death in a connected colony with `friends_mean` 8 gives about eight pushes of -0.25 to -0.5 inside one tick; slow recoveries stay low for 10 sols. In the Task 5 ice crises (thirst deaths 10, 0, 22, 0, 5 over 300 sols) many beings will have a grief within a few sols; the headroom scale keeps them at or above `b - 0.70`, and the idle-only effect keeps the cost at the bounded 15 percent of idle drain.
- **Frequency of band lines.** A being goes heavy only from `d <= -0.40`: one bond-0.7 grief on any Deimos, or two bond-0.5 griefs inside a few sols, or a long `hard_sol` run on a mutable Deimos stacked with a grief. In the Task 5 baselines grief mourners per death average about 2 to 8 (E), so most deaths produce heavy beings only at high bonds.
- **Baselines versus the traits.** Baseline spread is sd about 0.09 across the twelve signs. Travel effect at one standard deviation of baseline: 0.0135; the restless trait moves the travel chance by 0.32 over its range (sd of the restless trait across charts about 0.2, E, so 0.064). The baseline therefore explains about a fifth as much travel variation as the restless trait does and cannot flatten it.
- **Unit conventions.** Sim hours for `tick_h`, sols for half-lives, mood units are dimensionless (nominal range -0.9 to +0.9), bond units as in relationships.md.

## 7. What the player sees (view; sim read-only; fixed texts, no numbers)
### 7.1 The being inspect panel (6p items 2; text only)
A colonist can be selected (a tap on the colonist where it is drawn: outside, or inside an opened roof; how the selection looks and how it closes is the clarity review's, section 16, with the constraint: existing primitives only, no new art, no ring sprite). The panel shows, in this order, at most five fixed lines, each a template from `data/mood.json` `text.panel`:
1. **Who.** "{name} is {description}." (the existing two-word description, for example "Vana-3 is warm and nurturing.")
2. **Spirits.** The band sentence: heavy "{name} is heavy-hearted."; low "{name} is out of spirits."; even "{name} is much as usual."; light "{name} is in good spirits."; bright "{name} is lit up."
3. **Why**, only when `mood_why` is set and the band is not even, joined to line 2 after one space:
   - grief "They are still mourning {other}."
   - friend "They have just found a friend in {other}."
   - close "They have grown close to {other}."
   - lapse "They miss {other}'s company."
   - birth "They were there when {other} was born."
   - hard "Times are hard: {clause} runs short." (clause "the ice", "the air" or "the food")
   - age_up "The colony has found its footing." / age_down "The colony has slipped back into hard days."
   - pledge "The council's promise has lifted them."
   - company "They are glad of company."
4. **Nature** (Q1 option (a)), one sentence at most, first match in this order: base at or above `nature.base_hi` (0.15) "{name} usually sees the bright side."; base at or below `nature.base_lo` (-0.17) "{name} takes things to heart."; half-life at or above `nature.slow_halflife` (10.0) "{name} is slow to shake off a mood."; half-life at or below `nature.quick_halflife` (1.7) "{name} soon shakes off a mood."
5. **Company.** If `friend_count` is 0: **"{name} knows no one well yet."** (exact, K1; the K1 definition: no pair holding the `friends` flag, kin and crew included, so a newborn whose kin bond still holds does not show it). Else if the being has a close pair: "{name} is close to {other}." (the close friend with the highest bond, ties by lowest id). Else: "{name} counts {other} a friend." (the friend with the highest bond, ties by lowest id).
No number, no bar, no icon, no tint, no sprite change, no sign, no trait word beyond the existing description, no band index. The panel never shows the baseline, the half-life, the `mood_why` key names or the chart.
The view builds the lines through one pure function in `view/model/` (`BeingPanel.lines(world, id)`) that reads only `Being` fields, `relationships.friends_of(id)` and the texts in `data/mood.json`. It takes no real time and no RNG, so a headless test proves it (section 13, tests 22 to 24). The accessor `friends_of(id)` walks the packed mirror: estimated 0.3 to 0.6 ms per call at 5,000 pairs; the view calls it for the selected being at most twice a second and caches the result between calls.
### 7.2 Log lines
`mood_quiet` and `mood_relief` of 5.6. Texts (`text.lines`): `quiet_grief` "{name} has gone quiet since {other} died."; `quiet_lapse` "{name} has gone quiet without {other}."; `quiet_hard` "{name} has gone quiet. Times are hard."; `quiet` "{name} has gone quiet."; `relief` "{name} is smiling again." They carry no number. They join the colony log (500 entries, FIFO, kind-blind), and relationship lines already take 9.6 to 13.0 percent of it; the combined share of relationship, Council and mood lines is flagged above 0.20 (section 12, M7).
### 7.3 What stays unseen
No HUD line, no colony-wide mood word ("the colony is sad" is never said; the hard-season lines of the Council and the ages say what the colony does, not how it feels), no strip entry, no age text that mentions mood. The `md` table column and `stats.moods` are for tests and the probe only.
### 7.4 The success test (clarity, from the scoping note)
A player can say why a named being is upset from the log lines and the panel alone: the log carries the grief or friend line and, if it lasts, the quiet line; the panel gives the band and the why.

## 8. Stats: `stats.moods` (run-wide, never windowed, never shown)
| Key | Definition |
| --- | --- |
| `pushes` | `{friend, close, lapse, lapse_close, grief, birth_parent, hard_sol, age_up, age_down, pledge, company}` count of pushes applied (after scaling, including those scaled to zero) |
| `pushes_zeroed` | pushes whose scale was 0 (a mood at its limit), a saturation indicator |
| `lines` | `{quiet, relief}` logged; `lines_dropped` over the cap |
| `min_dev`, `max_dev` | the lowest and highest `d` any living being reached, with the sol of each (`min_dev_sol`, `max_dev_sol`) |
| `mean_by_sol`, `sd_by_sol`, `heavy_by_sol` | one float per pass through the sol block (mean of `m`, standard deviation of `m`, share of beings in the heavy band), from the last mood tick's aggregates; same length as `pop_by_sol` on a world enabled from creation, plus the initial reading at creation on a founder world (mean = mean baseline, sd = sd of baselines, heavy 0.0). At pop 0 all are 0.0 |
| `mean`, `sd`, `heavy_share` | latest readings |
Not in stats: any per-being mood, `mood_why`, bands, tick timings (a `last_tick_ms` for the probe only, never hashed). The dictionary is created in `_init_stats` (zeros, nulls, empty lists).

## 9. Randomness and the earlier hashes, per mechanic
**The mood layer draws no random number, from `SimRng` or anything else.** Temperament is a function of the chart; pushes are a function of events in a fixed order; bands and lines are functions of state.
| Mechanic | Draws | Writes outside the module | Effect on the old hashes |
| --- | --- | --- | --- |
| Temperament from chart (5.1), set in `_create_founders`, `_create_newborn`, `add_being` | none | Being fields | none |
| Mood tick: decay, pushes, company, bands, why (5.2, 5.3, 5.4) | none | Being mood fields, `stats.moods` | none while both gains are 0.0 (nothing reads mood) |
| Lines (5.6) | none | log | none (nothing in the sim reads the log) |
| Sol hook, per-sol series (4, 8) | none | `stats.moods` | none |
| Relationships additions (`events`, `with_friend`, accessors) | none | relationships' own new members | none |
| Council reads via `friend_pairs()` (9.1) | none | none | none (same data, same results) |
| **Effect 1** (travel chance, gain above 0) | the same one `chance()` call at the same place; its argument changes | being behaviour | **changes all five table hashes**: later outcomes differ, so the number and order of later draws over the run differ |
| **Effect 2** (idle drain, gain above 0) | none added or removed; sleep times shift, so `night_sleep_chance`, `day_wake_chance_per_h` and every later draw land at different steps | being behaviour | **changes all five table hashes** |
No existing draw is removed, added or reordered inside any single decision; every divergence is by changed outcomes. Draws named: `Being._restless_travel` `rng.chance` (changed argument), `Being.decide` `night_sleep_chance` (changed timing), `Being._sleep_step` day-wake `chance` (changed timing). At gains 0.0 both behaviour sites skip the mood term entirely (a literal `if coef > 0.0`), so weights, draws and decisions are bit-identical to Task 5; the dormant proof of section 10, step 2, checks it.
**Balance table.** A new trailing column `md` after `cn`: the latest `stats.moods.mean`, printed `%+.2f`. The old columns are unchanged. Removing `md` reproduces the Task 5 table body; the existing chain (`council_hash_proof`) then reproduces Tasks 4, 3 and 1.

### 9.1 Edits to existing code (the complete list; each is behaviour-neutral at gains 0.0 unless marked)
| File | Edit | Why |
| --- | --- | --- |
| `sim/moods.gd` | new | the module |
| `data/mood.json` | new, with every key of section 14 | tunables |
| `sim/sim_data.gd` | `moods()` accessor | data |
| `sim/world.gd` | `moods`, `moods_enabled`, the creation call, the two hooks, `stats.moods` in `_init_stats`; `_create_founders` and `_create_newborn` write the temperament (the newborn's chart is kept in a local variable); `add_being` writes the neutral temperament | the module |
| `sim/being.gd` | eight mood fields (3); `_restless_travel` adds the travel term (5.5); `drain_per_h` multiplies the idle branch (5.5). The only two edits that change behaviour, each behind `coef > 0.0` | effects |
| `sim/relationships.gd` | (a) `events: Array`, cleared at the start of `_tick`, filled in `_deaths` (one `grief` entry per mourner at or above `lines.friend`: `{kind, a: mourner, b: dead id, bond, name: dead name}`) and `_decay_and_flags` (`friend`, `close`, `lapse`, `lapse_close` entries `{kind, a: lo, b: hi}` per 5.3); (b) `with_friend: PackedByteArray`, sized and zeroed in `_prepare`, set for both ends of a grown pair whose `friends` flag is set, inside `_grow_group` (one flag read per grown pair); (c) `friend_pairs() -> Dictionary` and `friends_of(id) -> Array` (below) | the 6p accessor and the mood feed |
| `sim/council.gd` | `_readings` reads friend pairs through `friend_pairs()` instead of `rel._sk`, `_sl`, `_sh`, `_sf`, `_sp` and keeps its staged-world fallback inside the accessor. No change of behaviour | 6p item 1 |
| `tests/balance_lib.gd` | `md` column; `data_hash` adds `mood`; T13 (section 12) | columns and targets |
| `tests/council_hash_proof.gd`, `tests/relationships_hash_proof.gd` | a new `mood_hash_proof.gd` strips `md` (refusing if it is not the last field) and calls the existing chain; the two old proofs are untouched | the dormant proof |
| `tests/test_relationships.gd`, `tests/test_council.gd`, `tests/test_ages.gd` | none expected; if a test counts the Council's private reads or asserts the exact world members, it is listed in the task log with its reason | none silent |
| `view/model/being_panel.gd` (new), `view/main.gd` | the panel (7.1) | view, step 8 only |

**Accessor contract (6p item 1).** `friend_pairs()` returns `{lo: PackedInt32Array, hi: PackedInt32Array, flags: PackedByteArray}` for pairs holding the `friends` flag, with `flags` bit 1 close, bit 2 kin, bit 4 crew; order unspecified (mirror order, or dictionary order if the mirror is out of step with `pairs`); the arrays are copies; nothing the caller does to them touches relationships. `friends_of(id)` returns an ascending-by-other-id Array of `{id, close, kin, crew, bond}`; `bond` is for choosing who to name and is never displayed. Both are read-only by contract (tests 27 and 28 prove it) and cost O(stored pairs).

## 10. The baseline reset: procedure and record
This slice changes behaviour (decision B). The record is part of the definition of done. Steps, in order, each a commit:
1. **Freeze the "before".** Copy into `docs/balance/task-6a-log.md` the Task 5 table (hashes below), the Task 3 ages and the Task 5 Council figures. They are measured already (`docs/balance/task-5-log.md`); the step re-reads them from a fresh run of the unmodified tree at the commit before the module lands, so "before" is a measurement on the same host, not a quotation.
2. **Dormant build** (effects at 0.0): module, data, hooks, accessors, panel text, all tests green. Run the five seeds at 300 sols twice; the table (with `md`) differs from Task 5 only in that column; `tests/mood_hash_proof.gd` strips `md` and reproduces the Task 5 hashes (below), then the chain reproduces Tasks 4, 3 and 1. Exit 0 required. This proves the layer added no side effect.
3. **Run 1** (one parameter): `effects.travel_coef` 0.0 to 0.15, energy at 0. Five seeds, 300 sols, twice each, T1 to T13. Report.
4. **Run 2** (one parameter): `effects.energy_coef` 0.0 to 0.25, travel as kept after run 1. Same. Report.
5. **Guards on the final configuration**: M4, M3, M1 over the 15 seeds of `relationships.balance.r9_seeds` at gains on and at gains 0 (the 15 dormant runs are the paired baseline).
6. **Record**: old and new table hashes per seed side by side (below, filled in at this step), each seed run twice and compared byte for byte (`cmp`), T1 to T13 per seed before and after, ages and Council per seed before and after, and the verdict on every target of section 12. The new hashes become the reference; the old ones are marked superseded in the log, in `HANDOFF.md` section 8 and in `docs/tasks/task-6-plan.md`.
**Decision rule for each run (stated before the run).** Keep the gain if every M target of section 12 passes and T1 to T12 pass on all five seeds. If M4 (death-spiral guard) or T1 to T12 fail, halve that gain once (0.075 and 0.125) and rerun; if it fails again, that gain stays 0.0, and the result goes to the owner (the slice then ships with one behaviour, or none, and says so).
**The "before" figures (Task 5, `docs/balance/task-5-log.md`):**
| seed | Task 5 table hash (`cn` last) | drop `cn` (Task 4) | drop `cn`, `web` (Task 3) | Task 1 | Settlement entry | fall-back | Council entry | pledge |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 42 | 330325504427720a | a96b8a9562fd75d0 | da166c4f8b202820 | 02032b2388529913 | 67 | 213 ice | 115 | none |
| 7 | 1ceb89a7d3e87540 | a4968e2fcc48ec36 | 30c53f90949d979b | 830c7d0c441823f5 | 58 | none | 95 | none |
| 99 | 7feb81cee7c86fa5 | 2210719cf48d8612 | 54ad1e15b934bf9a | 0e3e83a7108140ef | 54 | 174 ice | none | none |
| 1234 | 7c8bcf782a06f1fa | 19437e397d1dff88 | 7052c92936a75157 | bca6eb2ca93ba0c1 | 65 | none | 160 | 195 |
| 2026 | 076e42c032a208aa | 6e7fe68477161196 | 67e3dcf057200eb9 | 2645033a417ec400 | 53 | none | 206 | 221 |
T1 to T12 all passed on all five seeds before (T9 by rerun). Projected age changes 2, 1, 2, 1, 1. Thirst deaths at sol 300: 10, 0, 22, 0, 5 (the water-rule precedent, council.md O5). The "after" columns (new table hash with `md`, hash twice-run identical yes or no, Settlement entry, fall-back, Council entry, pledge, T1 to T13, thirst deaths) are filled in by the sim-test-engineer at step 6 of the plan; this spec does not predict them beyond section 12's expectations.
**What may move, said now.** Settlement entry and fall-back sols (energy enters the ages' "calm" and "rested" clauses), Council entry sols and pledges (trajectories diverge), births and population at 300, the thirst-death counts, the relationship targets' margins (R3 passes by only 0.043 on seed 42 and 0.023 on seed 2026), and K1 itself. None is a target to hit; each is reported with the old value beside it. Targets that are structural (T1 to T12) must pass.

## 11. Cost budget (E; measured by the probe and a step profile)
Facts (from the Task 5 log): a tick step costs about 8.3 ms median at pop above 120 (2.3 ms step plus the 6 ms relationships tick); the Council boundary step on seed 1234 peaks at 13.7 ms (under the 16.7 ms frame trigger on 2 of 3 runs, "not proven by construction"); `advance()` has an 8 ms wall budget and may overshoot by one step.
- **Mood tick** (every 20th step): one pass over `world.beings` (decay, band, aggregates, about 15 simple operations a being), a second pass only when a colony push is pending or `with_friend` is set for anyone, plus the event list (a few dozen entries, a by-id lookup built only when the list is non-empty). Estimate at pop 160: 0.2 to 0.4 ms. **Budget: median at most `balance.tick_ms_max` 0.5 ms and max at most `balance.tick_ms_peak_max` 1.5 ms** at pop above 120.
- **Relationships additions**: `events` appends (tens of entries), `with_friend` fill (one flag read per grown pair, 600 to 2,500 pairs: 0.1 to 0.4 ms). **Budget: the relationships tick median rises by at most 0.5 ms** (it stays under the 8 ms median of relationships.md R8).
- **Sol hook**: O(1): two comparisons, the hard test (three stock reads), three appends. **Budget: at most 0.05 ms.**
- **Whole layer: its share of the mean step cost at pop above 120 at most `balance.step_share_max` 0.01** (the tick work is amortised over 20 steps: about 0.03 ms a step).
- **The boundary step on seed 1234 in the Council age.** The mood sol hook adds under 0.05 ms and the mood tick adds at most 0.5 ms on the 1 in about 25 boundary steps where a relationships tick coincides. **Rule: the maximum boundary step in the Council age, re-measured run alone with the module on, is at most 16.7 ms, and the mood module is responsible for at most 0.6 ms of any step.** If the Council boundary step exceeds 16.7 ms and the profile attributes more than 0.6 ms to moods, the order of remedies is: (1) move the mood tick one step after the relationships tick (behaviour-identical except for a one-step delay; no hash change beyond the reset); (2) drop `company` (the only per-pair addition, scope cut 2); (3) halve the aggregate work by computing `sd` every fifth sol. If the 16.7 ms overshoot is not attributable to moods (the existing trigger of council.md 11.1), moods are not a reason to act.
- **Memory**: eight fields on each Being; a Being is already a RefCounted with ~45 fields, so about +15 percent per Being, 160 Beings, negligible.
- **Probe and view cost**: `friends_of` 0.3 to 0.6 ms per call, view side, at most 2 per second for one selected being.

## 12. Calibration probe and balance targets
**Probe** `tools/mood_probe.gd`: read-only; runs the real module on seeds 42, 7, 99, 1234, 2026 for 300 sols in the dormant build and at each parameter run of section 10, and on the 15 seeds of `relationships.balance.r9_seeds` for the guards. Reports to `docs/balance/task-6a-calibration.md`:
1. **Distribution.** Per seed at sols 30, 60, 100, 150, 200, 300: mean, sd, minimum and maximum `m` and `d`, share in each band; the baseline sd and range of the colony.
2. **Pushes.** Counts per push key, `pushes_zeroed`, the largest single-tick change of any mood, number of beings that reached the heavy band and for how many sols (median), quiet and relief line counts, dropped lines.
3. **Deimos signature.** Beings split by baseline thirds: mean `m`, travel decisions per awake hour, and idle drain per hour, top against bottom third; and by half-life thirds: median sols for `d` to return inside 0.05 after a grief push (measured from the push log of the run).
4. **Personality check.** Rank correlation (Spearman) between each being's restless trait and its travel starts per awake hour, gains on against gains 0 (paired seeds); and, for the room-pull signature that already exists, the share of moves that go to the room the being's trait prefers (workshop by drive, archive by curiosity, and so on), gains on against gains 0.
5. **Energy and sleep.** `avgE`, `asleep%`, `max_sleep_h`, exhausted turn-backs, per 30-sol row; mining yield per trip (mean), trips; construction hours; gains on against gains 0.
6. **Spiral guard (15 seeds).** Total deaths and thirst deaths at 300, minimum ice, hard-sol count, per seed, gains on against gains 0, paired by seed; plus the worst 10-sol window of heavy share.
7. **Ages and Council.** Settlement entry, fall-back, Council entry, meetings, proposals, pledge, per seed, before and after; relationships targets R3, R4, R10, R11, K1 counts.
8. **Cost.** Mood tick median, p95, max at pop above 120; relationships tick median before and after; the boundary-step maximum on seed 1234; share of the mean step.
9. **Inspect text audit.** For every living being at sol 300 on each seed: build the panel lines; check each from data, no digit, no `%`, at most five lines; count by band, by why, by nature sentence; K1 sentence present exactly when `friend_count` is 0.
**Targets** (E; judged by the probe unless marked T13):
| # | Target | Key |
| --- | --- | --- |
| M1 | **Mood is alive but not pinned.** On every seed, from sol 30: mean `abs(d)` over beings and sols between `balance.mean_dev_min` 0.02 and `balance.mean_dev_max` 0.25; the share of being-sols in the even band between `balance.even_share_min` 0.60 and `balance.even_share_max` 0.97; sd of `m` at sol 300 at least `balance.mood_sd_min` 0.05 | `balance.*` |
| M2 | **Deimos is visible, bounded.** Top-third-baseline mean `m` minus bottom-third at sol 300 at least `balance.deimos_gap_min` 0.08 (a baseline survives events); and the slow-recovery third's median return time at least `balance.recovery_ratio_min` 2.5 times the fast third's (measured from grief pushes of the run) | `balance.deimos_gap_min`, `balance.recovery_ratio_min` |
| M3 | **Mood does not flatten personality.** The restless-trait rank correlation with travel starts, gains on, at least the gains-0 value minus `balance.trait_corr_drop_max` 0.05 on every seed; the data check that `travel_coef x (clamp_high - clamp_low)` is at most `balance.mood_trait_span_max` 0.5 of `restless.travel_coef`; and no behaviour except the two of 5.5 reads mood (a test greps the sim for mood reads) | `balance.trait_corr_drop_max`, `balance.mood_trait_span_max` |
| M4 | **No death spiral (15 seeds, gains on against gains 0, paired).** Mean total deaths per seed not above the gains-0 mean plus `balance.death_rise_max` 25 percent or 3 deaths, whichever is larger; mean thirst deaths likewise; mean minimum ice not below the gains-0 mean by more than 10 percent; hard-sol count not above +10 percent; the worst 10-sol window's mean heavy share at most `balance.heavy_share_max` 0.30 on every seed; no unexplained death (`deaths_unexplained` 0) and no new death cause | `balance.death_rise_max`, `balance.heavy_share_max` |
| M5 | **Old targets.** T1 to T12 pass on the five standard seeds. T8 (avgE 40 to 90, asleep 5 to 30 percent) is read from the table rows. T10 (ages) is judged on its ranges and counts (`settle_sol_min..max`, projected changes), the exact sols reported and not judged against 67, 58, 54, 65, 53 | structural |
| M6 | **Cost** as in section 11 | `balance.tick_ms_max` 0.5, `balance.tick_ms_peak_max` 1.5, `balance.step_share_max` 0.01 |
| M7 | **Lines.** Mood lines at most 1 per sol on every sol (T13), at most `balance.lines_per5_max` 0.5 per 5 sols averaged over sols 30 to 299; combined share of relationship, Council and mood lines in the log flagged (reported, not judged) above `balance.log_share_flag_combined` 0.20 | `balance.lines_per5_max` |
| M8 | **Inspect text.** The audit (item 9) passes: all texts from data, no digit, K1 sentence exactly when `friend_count` is 0 | structural |
| D | Diagnostics, reported only: share of beings in non-even bands per sol; kin newborn first-friend wait (R1) and `lonely_share` before and after (K1 movement); correlation of mood with `friend_count`; Council targets C1 to C8 (Q2 decides what failing them means) | none |
**T13** in `tests/balance_lib.gd`, per seed, from `stats.moods` and the log: (1) the three series have the length of `pop_by_sol`; (2) at most one `mood_*` log entry per elapsed sol; (3) every `mood_relief` has an earlier `mood_quiet` for the same being at least `lines.relief_min_sols` sols before; (4) `heavy_by_sol` never exceeds `balance.heavy_share_max` after sol 30 (a spiral tripwire); (5) `min_dev` not below `floor_dev` and `max_dev` not above `ceil_dev` (the headroom scale holds); (6) `deaths_unexplained` 0. Reported: everything of probe items 1 and 2.
**Next runs** are those of section 10, one parameter each, with the decision rule stated there.

## 13. Tests (`tests/test_moods.gd`, written first, red; no test with zero checks)
Staging: blank world, a reactor, two habitats, a workshop; beings with `add_being`, then `mood`, `mood_base`, `mood_halflife`, `mood_k` and traits overwritten; relationships made with `debug_set_bond`; ticks driven with `relationships.on_step(world, tick_h)` then `moods.on_step(world)`, or by stepping 20 steps.
1. **Temperament table.** For each of the 12 signs and the two worlds (a Mars chart with that Deimos, an Earth chart with that Moon) `base` and `halflife` equal the table formula from data (tolerance 1e-12); an Earth-born founder uses its Moon; the range of bases is -0.17 to +0.15 and of half-lives 1.6 to 10.4 at the shipped data.
2. **`mood_k`.** Over one sol of ticks a deviation of 0.5 halves per `halflife_sols` (tolerance 1e-9 at H 4 over 4 sols).
3. **Decay and rest.** A pushed being returns to its baseline monotonically; below `rest_eps` it snaps to the baseline; a being at its baseline stays exactly there with no event for 100 ticks.
4. **Headroom.** A +0.10 push at `d` +0.35 is +0.05; a -0.25 push at `d` -0.35 is -0.125; no sequence of 1,000 pushes takes `d` past -0.70 or +0.70; `pushes_zeroed` counts the saturated ones.
5. **Friend and close pushes.** A grown friendship (neither kin nor crew) pushes both +0.10; a close crossing +0.15; kin and crew seeding pushes nothing; a crew pair that was never close and lapses pushes nothing; a pair that was close and lapses gives -0.12 to both.
6. **Grief.** A death pushes every mourner at or above `lines.friend`, by the linear rule (bond 0.30 gives -0.25, 0.65 gives -0.425, 1.0 gives -0.60, before scaling), more than the two named in the log; a being below the friend line gets none; a mourner that died in the same tick is skipped; grief lines are unchanged (relationships' own tests still pass).
7. **Birth.** The recorded parent of a newborn, if alive, gets +0.08 and a why of kind `birth`; a dead parent or `parent_id` 0 gives none; ids scanned from the end find all newborns in a tick and set `max_id_seen`.
8. **Hard sol.** A sol boundary with ice below `ages.sample.ice_min_sols` days of use records `pending_hard` ice; the next tick pushes every being -0.02 scaled; a being at `d` -0.30 or lower gets none; air and food clauses give their own keys; with all three fine nothing; the sol hook loops over no beings (checked by a counter or by the test calling it with a stub list that fails on iteration).
9. **Age and pledge.** A Landing to Settlement change pushes +0.10 to all, Settlement to Landing -0.10, Settlement to Council nothing; the pledge pushes +0.10 once.
10. **Company.** Two friends awake in one room for one tick: both get +0.006 scaled and `with_friend` is set; asleep, in transit, or non-friends: no push; a friend pair on the same ice field counts.
11. **Order.** In one tick the order is decay, events (list order), colony pushes, company, band; two same-seed worlds have identical moods.
12. **Bands and hysteresis.** `d` crossing each line changes the band only when 0.03 past it; a mood oscillating between -0.17 and -0.19 for 50 ticks does not flip the band more than once.
13. **Why.** A grief why survives a later +0.10 company-sized push and is replaced by a push at least half of `abs(d)`; it is cleared when `abs(d) < 0.10`; hard sets a why only when none is set; the clause is carried.
14. **Effect 1.** With `travel_coef` 0.0 the chance passed to `rng.chance` equals Task 5's exactly (stub rng records the argument); with 0.15 and `m` -0.5 it is lower by 0.075 (clamp inside -0.6); with `m` +0.9 it is raised by 0.06 (clamp 0.4); never below 0.02; exactly one `chance` draw per call in both cases.
15. **Effect 2.** With `energy_coef` 0.0 idle drain equals Task 5's; at 0.25 and `m` -0.6 it is 1.15 times; at +0.4 it is 0.90 times; sleep, EVA, work and mining drains are untouched at any mood.
16. **No other reader.** A scan of `sim/` for `mood` outside `moods.gd`, `being.gd` (the two sites and the fields), `world.gd` (hooks and creation) and `relationships.gd` (the feed) finds nothing; no `sim/` file other than those reads `mood` fields (mining, births, ages, Council, resources, powers).
17. **Dormant purity.** With both gains 0.0, seed 42 for 10 sols, a world with `moods_enabled` true and one with false have equal old `stats` keys (skipping `moods`), equal beings (id, building, state, energy, wait), equal stocks and the same next 1,000 draws.
18. **Determinism.** Two same-seed worlds (gains on) have identical moods, bands, whys, `stats.moods` and log for 60 sols.
19. **Lines.** A being entering the heavy band logs `mood_quiet` with the text chosen by its why (four texts), once; the cooldown of 20 sols blocks a second; the cap of one per sol drops the others and counts them; a relief needs the band at or above even and 3 sols; a dropped relief is offered again at the next tick; no relief without a prior quiet.
20. **Texts.** Every text of `mood.json` rendered with sample names has no digit and no `%`; every `{placeholder}` is filled; no text contains a sign name, a trait word that the panel does not already show, or the words "Deimos", "Moon" or "chart".
21. **Stats and series.** The three series have the length of `pop_by_sol` from creation on a founder world and on a blank world; pop 0 appends 0.0 and divides by nothing; `mean_by_sol[0]` equals the mean of the founders' baselines.
22. **Panel lines.** `BeingPanel.lines` for staged beings: all five bands with and without a why; the nature sentences at the four thresholds; the K1 sentence for `friend_count` 0 (exact string), "is close to" for a close pair naming the highest bond, "counts ... a friend" otherwise; a newborn with a held kin bond shows a friend sentence, not K1; no digit in any output.
23. **Panel purity.** Calling `BeingPanel.lines` twice leaves the world unchanged (hash of `stats` and beings before and after) and draws nothing from `world.rng`.
24. **Panel and HUD isolation.** The view source reads no mood number: `BeingPanel` uses the band index only to choose a template, and the HUD files do not reference `stats.moods`, `mood`, `mood_base` or `mood_k` (a source scan).
25. **Dormant hash proof.** `tests/mood_hash_proof.gd` on the five seeds at 300 sols with both gains 0.0: dropping `md` reproduces the five Task 5 table hashes; the chain reproduces Task 4, 3, 1 (Q3 decides whether this stays after the 6a close).
26. **Key-path parity** for `mood.json`, both ways, and the data sanity rules of section 14 (each rule checked on the shipped data and shown to fail on one deliberately broken copy through the override seam).
27. **Accessor read-only.** `friend_pairs()` returns the friend pairs (counts equal `stats.relationships.friend_pairs` after a sol reading), flags correct, arrays are copies (mutating them changes nothing in relationships), and the Council's trust, chosen share, lean, stance and `stats.council` on a seeded 120-sol world are identical to the Task 5 values with the Council reading through it.
28. **`friends_of`.** Ascending by other id, flags and bond correct, a dead id returns an empty array, a missing mirror (staged world) falls back to the dictionary.
29. **Relationships feed.** `events` is empty at the start of each tick, has one `grief` entry per mourner of a death, one `friend` entry per grown friendship (kin and crew excluded), one `close`, `lapse` and `lapse_close` entry as in 5.3; `with_friend` is set exactly for both ends of grown pairs holding the friends flag; relationships' own results (pairs, bonds, flags, lines, stats) are identical with the feed code present (the existing 27 relationships tests pass unchanged).
30. **Existing suite.** The whole `tests/run_tests.gd` suite passes with the module on and both gains 0.0; any test changed is listed in the task log with its reason.
31. **Gain-on sanity (not a hash test).** With the shipped gains, a staged colony in permanent hardship (stocks forced low, 100 sols, 60 beings) never leaves `[floor_dev, ceil_dev]`, never exceeds a 1.15 drain factor, never lowers the travel chance below 0.02, and loses no being to a cause other than the staged stocks.
Balance (`tests/balance_lib.gd`): **T13** as in section 12; T1 to T12 unchanged in definition and must pass (hashes reset per section 10).

## 14. Tunables (`data/mood.json`; E = estimate for the probe)
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| temperament.inner_key.mars / .earth | chart key | "deimos" / "moon" | owner C; lead |
| temperament.element_base.fire / air / earth / water | mood | +0.12 / +0.06 / -0.04 / -0.14 | lead, E |
| temperament.modality_base.cardinal / fixed / mutable | mood | +0.03 / 0.00 / -0.03 | lead, E |
| temperament.halflife_sols.cardinal / fixed / mutable | sols | 4.0 / 2.0 / 8.0 | lead, E |
| temperament.halflife_mult.fire / air / earth / water | x | 0.9 / 1.0 / 0.8 / 1.3 | lead, E |
| temperament.neutral.base / .halflife_sols | mood / sols | 0.0 / 4.0 | lead |
| range.floor_dev / ceil_dev | mood | -0.70 / +0.70 | lead, E |
| rest_eps | mood | 0.001 | lead |
| push.friend / close | mood | +0.10 / +0.15 | lead, E |
| push.lapse / lapse_close | mood | -0.05 / -0.12 | lead, E |
| push.grief_min / grief_max | mood at bond 0.30 / 1.0 | -0.25 / -0.60 | lead, E |
| push.birth_parent | mood | +0.08 | lead, E |
| push.hard_sol / hard_floor_dev | mood per hard sol / deviation | -0.02 / -0.30 | lead, E |
| push.age_up / age_down / pledge | mood | +0.10 / -0.10 / +0.10 | lead, E |
| push.company | mood per tick | +0.006 | lead, E |
| bands.heavy / low / light / bright / hyst | deviation | -0.40 / -0.18 / +0.18 / +0.40 / 0.03 | lead, E |
| why.min_push / show_dev | mood | 0.05 / 0.10 | lead, E |
| effects.travel_coef | travel chance per mood unit | 0.0 in step 2, 0.15 from run 1 | lead, E |
| effects.energy_coef | idle drain fraction per mood unit | 0.0 in step 2, 0.25 from run 2 | lead, E |
| effects.clamp_low / clamp_high / travel_floor | mood / mood / chance | -0.60 / +0.40 / 0.02 | lead, E |
| lines.max_per_sol / quiet_cooldown_sols / relief_min_sols | lines / sols / sols | 1 / 20 / 3 | lead, E |
| nature.base_hi / base_lo / slow_halflife / quick_halflife | mood / mood / sols / sols | +0.15 / -0.17 / 10.0 / 1.7 | lead (Q1 option a), E |
| text.panel.*, text.band.*, text.why.*, text.nature.*, text.lines.*, text.clause.* | fixed strings (section 7) | as written | lead |
| balance.* | targets of section 12 | mean_dev_min 0.02, mean_dev_max 0.25, even_share_min 0.60, even_share_max 0.97, mood_sd_min 0.05, deimos_gap_min 0.08, recovery_ratio_min 2.5, trait_corr_drop_max 0.05, mood_trait_span_max 0.5, death_rise_max 0.25, heavy_share_max 0.30, tick_ms_max 0.5, tick_ms_peak_max 1.5, step_share_max 0.01, lines_per5_max 0.5, log_share_flag_combined 0.20 | lead, E |
**Data sanity rules (test 26):** `floor_dev < 0 < ceil_dev`; `bands.heavy < bands.low < 0 < bands.light < bands.bright`; `bands.hyst` under half of the narrowest band gap; every half-life above 0; `grief_max <= grief_min < 0`; `clamp_low < 0 < clamp_high`; `travel_coef`, `energy_coef` at least 0 and `energy_coef x -clamp_low < 1`; `travel_floor` in [0, 1]; `lines.max_per_sol` at least 1; `nature.base_lo < 0 < nature.base_hi`; every text key present and free of digits; `balance.mean_dev_min < mean_dev_max`.

### Key-path list (machine-readable; one leaf per line)
```
temperament.inner_key.mars
temperament.inner_key.earth
temperament.element_base.fire
temperament.element_base.air
temperament.element_base.earth
temperament.element_base.water
temperament.modality_base.cardinal
temperament.modality_base.fixed
temperament.modality_base.mutable
temperament.halflife_sols.cardinal
temperament.halflife_sols.fixed
temperament.halflife_sols.mutable
temperament.halflife_mult.fire
temperament.halflife_mult.air
temperament.halflife_mult.earth
temperament.halflife_mult.water
temperament.neutral.base
temperament.neutral.halflife_sols
range.floor_dev
range.ceil_dev
rest_eps
push.friend
push.close
push.lapse
push.lapse_close
push.grief_min
push.grief_max
push.birth_parent
push.hard_sol
push.hard_floor_dev
push.age_up
push.age_down
push.pledge
push.company
bands.heavy
bands.low
bands.light
bands.bright
bands.hyst
why.min_push
why.show_dev
effects.travel_coef
effects.energy_coef
effects.clamp_low
effects.clamp_high
effects.travel_floor
lines.max_per_sol
lines.quiet_cooldown_sols
lines.relief_min_sols
nature.base_hi
nature.base_lo
nature.slow_halflife
nature.quick_halflife
text.panel.who
text.panel.k1
text.panel.close
text.panel.friend
text.band.heavy
text.band.low
text.band.even
text.band.light
text.band.bright
text.why.grief
text.why.friend
text.why.close
text.why.lapse
text.why.birth
text.why.hard
text.why.age_up
text.why.age_down
text.why.pledge
text.why.company
text.nature.bright
text.nature.heavy
text.nature.slow
text.nature.quick
text.lines.quiet_grief
text.lines.quiet_lapse
text.lines.quiet_hard
text.lines.quiet
text.lines.relief
text.clause.ice
text.clause.air
text.clause.food
balance.mean_dev_min
balance.mean_dev_max
balance.even_share_min
balance.even_share_max
balance.mood_sd_min
balance.deimos_gap_min
balance.recovery_ratio_min
balance.trait_corr_drop_max
balance.mood_trait_span_max
balance.death_rise_max
balance.heavy_share_max
balance.tick_ms_max
balance.tick_ms_peak_max
balance.step_share_max
balance.lines_per5_max
balance.log_share_flag_combined
```

## 15. Plan questions answered, scope cuts
### Plan questions Q1 to Q10 (docs/tasks/task-6-plan.md, section 5), 6a only
| Q | Answer | Whose |
| --- | --- | --- |
| Q1 First slice and 6p | emotions first, with the accessor and the inspect panel folded in | owner, A |
| Q2 Hashes | emotions change behaviour now; baseline reset recorded (section 10) | owner, B |
| Q3 Behaviour, Deimos versus events, what the player sees | Deimos sets baseline and recovery; events push; two behaviours (5.5); text only (7) | owner, B, C, D; lead |
| Q8 Texture budget | no new art | owner, D |
| Q9 Randomness | no draws at all (section 9) | lead |
| Q10 Targets, cost, seeds | M1 to M8, T13, section 11, five standard seeds at 300 sols plus the 15 seeds of `r9_seeds` for the guards | lead |
Q4 to Q7 (AI minds, server, culture) are for 6b to 6d. 6b reads `mood_band`, `mood_why` and the temperament sentence inputs only through the pure panel function's inputs; no 6a decision depends on 6b.
### Scope cuts (lead; cut order if time runs out, first cut first)
1. The `age_up`, `age_down` and `pledge` pushes (colony-level lifts; keeps the five relationship-and-hardship pushes).
2. `company` (the only per-pair addition to the relationships tick; first to go if the cost rule of section 11 fires, and the calm-colony texture suffers, said plainly).
3. The nature sentence (Q1).
4. The `mood_relief` line (keep the quiet line, a story that begins and does not end).
5. The `birth_parent` push.
6. `lapse` and `lapse_close` (keep friend, close, grief, hard sol).
7. The energy effect (keep the travel effect only).
8. The travel effect (the slice then has one behaviour).
**Cut last**: temperament from the chart, grief, the headroom scale and the hard floor, the K1 sentence and the band sentence in the panel, the dormant hash proof, the baseline-reset record, the no-RNG rule.
**Never cut**: the accessor (6p item 1; the Council refactor), the K1 sentence (6p item 2), T13, the reset record of section 10.
**Out of 6a entirely** (recorded so that no one re-adds them silently):
- mood read by the Council's lean, by birth chance, by mining will, by building choice, or by any survival rule;
- a loneliness term (friendless means sadder, or friendless seeks company): the lonely pull was measured and rejected in Task 5 (zero-friend share rose 0.244 to 0.290; seed 21 went extinct) and R3 passes by 0.043 and 0.023 on two seeds; mood must not reopen K1 by the back door. Positive-only `company` is the compromise: it rewards friendship, never punishes friendlessness;
- negative bonds, dislike, rivals (relationships.md section 19); mood-driven gatherings, mourner behaviour or a muted pose, a mood tint or posture, a mood icon;
- a god lever on mood, a direct "send a dream"; a colony-wide mood word or meter; an AI-written line (6b);
- a per-being history of moods or a memory (6c);
- persistence of mood across a save (no save exists; 6d).

## 16. Requests to the assistant designers (the main session runs them)
One round, three reviewers, on revision 1. Each returns numbered findings with a recommendation; the lead decides each and records the dissent in section 17. Each reads this spec, `docs/design/task-6-scoping.md`, relationships.md and council.md, and cites a shipped game or published talk only where sure (say when unsure).
**designer-emergence (Will Wright lens).**
1. Is one number with a baseline and a rate enough to produce stories, or is it a meter in disguise? Which of the eleven pushes would you add or cut? Is "temperament changes how long it lasts, not how it feels" the right use of the Deimos placement, and is the Moon-for-founders decision sound?
2. The two behaviours are deliberately small. Does the loop mood to travel to togetherness to bonds to company to mood have an interesting second-order behaviour, or is it too damped to matter? Name the worst loop you see (the spiral guard of 5.5 is argued from the code; check the argument).
3. The loneliness term is excluded (section 15). Do you accept the exclusion, or is there a safe form that makes K1 matter in mood?
4. Q2 (Council after the reset): which option, and what would you watch in the 15-seed runs?
**designer-feel (Eric Barone lens).**
1. Does the panel read as a warm, small, lived-in place? Judge the eleven mood texts, the five band sentences, the four nature sentences and the five line texts for tone, repetition and length; are "heavy-hearted", "out of spirits", "much as usual", "in good spirits", "lit up" the right five registers?
2. The calm colony stays "much as usual" most of the time (section 6). Is there enough daily texture without adding meters or more pushes? Is `company` worth its cost?
3. Rhythm: grief lasting 2 to 19 sols against a sol of about 8 real minutes at 1x. Is that the right pace for a mood to be seen to change? Is one mood line a sol too many, too few?
4. Scope: is the eight-item cut order right? What is the one thing to protect?
5. Q1 (how much temperament to say): which option?
**designer-clarity (Karoliina Korppoo lens).**
1. Information design: can a player say why a named being is upset from the log and the panel alone (7.4)? Is the why rule of 5.4 (the biggest push, shown while clearly off baseline) the right one, or will it mislead (for example a company push naming a cause that is not the real one)? Is the panel five lines too many at 720p?
2. Selection: how does a player open a colonist's panel without breaking the locked building-selection rule ("tap again to open the roof")? Constraint: existing primitives only, no new sprite, no meter. What closes it, and what happens at 1000x speed?
3. What the player is told, and when, about the baseline reset: nothing in play, but should the first sitting after 6a show anything? Are two mood log lines enough to teach the system?
4. Cost and readability at scale: the Council boundary step on seed 1234 already peaks at 13.7 ms before the module. Is the cost rule of section 11 (0.6 ms attributable, 16.7 ms total) a good enough trigger? Is the hash-reset record (section 10) enough to trust the new baseline?
5. Q3 (hash chain) and Q2 (Council): which option?
Reviews are saved to `docs/design/reviews/emotions-emergence.md`, `emotions-feel.md`, `emotions-clarity.md`.

## 17. Design review record
Reviewers: emergence (Will Wright lens), feel (Eric Barone lens), clarity (Karoliina Korppoo lens). Decision key: A adopted, AM adopted modified, D deferred, R rejected. Reviews: `docs/design/reviews/emotions-emergence.md`, `emotions-feel.md`, `emotions-clarity.md`.
*(empty: the reviews have not run)*

## Changelog
- 2026-10-08: revision 1 (lead designer). Draft for the three assistant reviews. Decided in the draft: one mood number with a Deimos (Moon for Earth-born founders) baseline and half-life; eleven pushes with a headroom scale; two behaviours (travel chance gain 0.15, idle drain gain 0.25, both in data); no RNG; text-only panel with the K1 sentence; two rare log lines; dormant-then-live procedure for the baseline reset; accessor and event feed added to relationships, Council moved to the accessor. Owner questions Q1 to Q3 posed. Reviewer sign-off: pending.
