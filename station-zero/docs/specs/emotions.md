# Spec: emotions (Task 6a): Deimos sets temperament, events push mood, mood changes two small behaviours (revision 2, after the three assistant reviews)

**Revision 2 in brief** (full record in section 17): the nature sentences are re-thresholded so each of four sentences has its own sign (4 of 12, reachability tested); the "why" rule is rewritten (sticky grief, sign agreement, past-tense hard, whys judged on nominal push size); a dropped quiet line changes no state and is retried, candidates offered deepest first; the colony-wide `age_up` and `age_down` pushes are cut (nine pushes remain); `company` is capped so friendship cannot snowball; `birth_parent` is raised to +0.20 so joy is reachable; the energy effect moves to cut position 3 and ships only if an extended death-spiral guard passes; a noise-floor control run (gains 1e-6) is added to the reset; selection, panel close rules and a minimal tap-from-log are specified; the panel is at most four sentences; log lines get two wordings each. Facts re-read from code for this revision are in 5.5 ("Verified in code").

Source of truth: HANDOFF.md sections 1, 2, 3 (Deimos weight 0.20, inner boost 1.5; the Earth chart has a Moon, no Deimos), 4, 5 (Social), 8, 10. Owner decisions for this slice: `docs/design/task-6-scoping.md`, "Owner decisions (Herby, 2026-10-08)". Plan: `docs/tasks/task-6-plan.md` (6a, steps 1 to 9, constraints in its section 4). Format and discipline modelled on `docs/specs/relationships.md` (revision 8) and `docs/specs/council.md` (revision 6). Facts read from code and data: `sim/persona.gd`, `sim/sky.gd` (chart keys), `sim/being.gd` (`drain_per_h`, `_restless_travel`, `decide`), `sim/world.gd` (phase order of `step()`, `_create_founders`, `_create_newborn`, `add_being`, `_kill`), `sim/relationships.gd` (tick, `_deaths`, `_decay_and_flags`, `_growth`, `friend_count`, `present`, `ticks`, the packed mirror `_sk _sl _sh _sf _sp`), `sim/council.gd` (`_readings` reads that mirror), `sim/ages.gd` (the "calm" and "rested" clauses read energy), `tests/balance_lib.gd` (table columns, T1 to T12, hash), `data/persona.json`, `data/signs.json`, `data/beings.json`, `data/relationships.json`, `data/council.json`, `data/ages.json`, `docs/balance/task-5-log.md` (the "before" figures).

Locked decisions respected:
- **Hidden birth chart.** Only effects are shown. The Deimos (or Moon) sign is never named, shown or counted; the player sees a mood sentence and, for strong cases, one sentence about how a being takes things.
- **Influence-only god.** No power reads or writes a mood in 6a (none of Inspire, Grace, Send a sign exists yet). A future "send a dream" would be a push in the table of 5.3; recorded, not built.
- **Naturalism, ages not meters.** No mood bar, number, icon, tint or colony-wide mood word reaches the player. The balance table has a debug column (`md`); the HUD never reads it.
- **Per-being energy, power as a budget, ice pressure is not failure.** Energy stays per being and mood bends it by a bounded factor; no power, oxygen, food, ice, regolith or building state is written. Ice pressure may lower moods; it is never made worse by them in any way the guard in 5.5 and 12 does not bound.

Tunables live in `data/mood.json` (new). No tunable in the new module `sim/moods.gd` and no literal in the two edited behaviour sites in `sim/being.gd`. This spec describes behaviour and numbers only, no code. **Every number marked E is an estimate until the calibration probe (section 12) measures it.**


**Owner answers on revision 2 (Herby, 2026-10-08):** Q1 = (a) the four strong-case temperament sentences, always (dropped while a why shows). Q2 = (a) report and accept, judged against the noise-floor control; a C1 or C4 miss opens a named Council recalibration sub-task; no council.* key moves in 6a. Q3 = (a) keep the old hash chain as the dormant-mode proof until 6a closes, then retire it. Q4 = (a) no baseline drift in 6a; recorded as a candidate after 6a closes.

## Owner decisions (Herby, 2026-10-08), as binding for this spec
- **A.** 6a is first, with two 6p items folded in: a public read-only accessor for the relationships packed mirror (section 9.1, replaces the Council's private reads) and a being inspect panel carrying the K1 sentence "{name} knows no one well yet." (section 7).
- **B.** Emotions change behaviour now. A baseline reset is accepted. It must be recorded: old and new table hashes per seed, each seed run twice with identical output, T1 to T12 and the Task 3 ages and Task 5 Council results measured before and after (section 10).
- **C.** Deimos sets each being's baseline mood and its recovery rate. Events push mood away from the baseline and it decays back (5.1 to 5.3).
- **D.** Text only. No new art, no meter, no colony-wide mood word, texture budget untouched (47.1 of 48 MB).

## Open for the owner (options as posed)
Four questions, each with the recommendation first. The spec is written to option (a) of each. None blocks steps 1 to 4. Reviewer input is folded in (section 17).

**Q1. How much of a being's temperament may the inspect panel say?** (HANDOFF section 2: "Only its effects are visible".)
- (a) **Recommended: say it for the strong cases, always.** One sentence, shown when no "why" sentence is shown, for exactly four of the twelve Deimos or Moon signs (a third; each sentence has its own sign, 5.1 and 7.1): "{name} usually sees the bright side." (cardinal fire), "{name} takes things to heart." (mutable water), "{name} is slow to shake off a mood." (mutable air), "{name} soon shakes off a mood." (fixed earth). They describe what the being does, not the chart. Cost: four signs are labelled in every colony; the other eight are read from how long their moods last. Facts: with no sentence at all the Deimos baseline would be invisible in calm colonies, where mood rarely leaves its baseline (section 6). All three reviewers chose (a) once the sentences were reachable.
- (b) Say it only after the being has had an episode: the nature sentence appears only once the being has gone low or heavy at least once (one new boolean on the being). Cost: a calm colony shows no temperament at all, and the player learns who is who only from pain, which is warm and in keeping with "weather rarely, climate always" but makes the owner's decision C invisible for the first dozens of sols. Raised by designer-feel as an idea.
- (c) No temperament sentence ever. Cost: decision C is only visible as slow versus quick recoveries over many sols. Safest for the hidden chart.
(A sentence for every being, rev 1 option (c), is dropped: it reads like a character sheet.)

**Q2. If the reset moves the Council and it stops reaching its targets, what then?** (Council entry and the dome pledge depend on friendship webs, which any behaviour change moves; seed 1234 clears the carry quorum by only 0.02.)
- (a) **Recommended: report and accept, judged against a noise floor.** 6a measures Council entry sols, meetings, pledges and friend webs before and after, on the five seeds and on 15 seeds at three settings (gains 0, a negligible-gain control of 1e-6, gains on; section 10 step 3), and reports mood's effect as the shift beyond the spread between the first two (any behaviour change moves the Council through chaos alone; the control measures how much). No `council.*` key is retuned in 6a. If C1 (Council on at least 3 of 5 seeds) or C4 (a pledge on at least 1 seed) fail after the reset, the failure is recorded per seed with the old value beside it as a known issue and a named Council recalibration becomes its own sub-task on the new baseline. Facts: retuning the Council inside 6a would be a second behaviour change in one slice (the reason Task 5 refused the water rule).
- (b) One Council lever allowed in 6a (`dome.lean.base` or `decide.carry_quorum`), chosen by the lead, one run. Cost: 6a grows by a run and a review, and the pledges are fitted again to five seeds.
- (c) Block the reset: if C1 or C4 fail, reduce the mood gains until they pass. Cost: the owner's decision B is then bent by a target that is itself an estimate.

**Q3. When is the old hash chain retired?** (The Task 1 to 5 table hashes have been the regression bridge for five tasks.)
- (a) **Recommended: keep it as a dormant-mode proof until 6a closes, then retire it.** With both gains at 0 the mood layer must reproduce all 20 old hashes (Task 1, 3, 4, 5) once the new `md` column is dropped (section 10, step 2). That proof is run at the dormant build (section 10, step 2, inside plan step 4) and kept as a test (`tests/test_moods.gd`, test 25) so a later change cannot silently break the bridge; at the 6a close the owner may delete the test, and the new Task 6a hashes become the only reference.
- (b) Retire the chain now, at the moment the gains are switched on. Cost: no machine proof that the new module added no side effect beyond its two gains.
- (c) Keep the chain forever as a switch (gains at 0 must always reproduce Task 5). Cost: every later behaviour change in Tasks 6b to 6d has to keep the dormant path alive. (Designer-emergence would keep it through 6b; recorded as dissent, section 17.)

**Q4. Should temperament be allowed to move, a little, with a being's life?** (Touches owner decision C: "Deimos sets each being's baseline mood". Raised by designer-emergence as an idea, "scars": a bounded drift of the baseline after a deep or repeated grief, say at most 0.05, so that a being who has buried many friends is permanently a little quieter.)
- (a) **Recommended: not in 6a; record it as a candidate for after 6a closes.** Facts: it changes what decision C means (the baseline stops being fixed for life), adds per-being state and a rule the player cannot read from the panel, and would be calibrated on a reset baseline that does not exist yet. The 6a stats (heavy episodes per being) give the data to decide it later.
- (b) Yes, bounded drift of at most 0.05 after a heavy episode, recovering never. Cost: a second slow system in the first behavioural slice, a change to a locked owner decision, and a new unreadable cause for the same sentence.
- (c) No, ever: temperament is the chart and only the chart. Cost: the strongest "long story" lever in the design is closed; the chart stays the only author of who a being is.

## 0. The design in one paragraph
Every being carries one private number, its **mood**, between about -0.9 and +0.9, that rests at a **baseline** and returns to it at a **recovery rate**; both come from the being's Deimos sign (for the seven Earth-born founders, from the Moon, the inner placement of an Earth chart). Things that already happen in the colony push the mood away from its baseline: a new friend, a bond growing close, a friend lost, a death of someone close (grief), a child born where one was present, a hard sol of short air, food or ice, a Council pledge, and an hour spent with a friend (capped, so friendship cannot snowball). Pushes shrink as a mood nears its limits, and between pushes the mood decays back at the being's own rate: a steady Deimos is back to itself in two sols, a mutable water Deimos stays heavy for ten. That is the whole model: one number, one baseline, one rate, nine pushes, no new RNG. Mood changes exactly two things beings do: how likely they are to wander to another room when they would otherwise stay (low spirits withdraw, bright spirits roam), and how fast they tire when idle (heavy hearts tire sooner). Both effects are small and bounded, so the same colony with the mood layer on plays out almost the same but not byte-identically: every table hash changes, which the owner has accepted. The player sees mood only as words: a being inspect panel ("Vana-3 is out of spirits. They are still mourning Kiro-12."), and two rare log lines ("Vana-3 has gone quiet since Kiro-12 died.", "Vana-3 is smiling again."), each with a second wording. Nothing counts, nothing fills.

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
| headroom scale | `clamp(1 - d / ceil_dev, 0, 1)` for a positive push, `clamp(1 - d / floor_dev, 0, 1)` for a negative one (`ceil_dev` +0.70, `floor_dev` -0.70). The `company` push uses its own, lower ceiling `company_ceil_dev` +0.15 in place of `ceil_dev` (5.3) |
| nominal push | the push amount before the headroom scale; the "why" rule judges size on the nominal push (5.4) |
| band | one of heavy, low, even, light, bright, read from `d` with hysteresis (5.4) |
| why | the push that most explains the present deviation: `{key, id, name, t, clause}` or null (`t` the sim hour it was set, `clause` "ice", "air" or "food" for a hard why and never shown, kept for 6b) (5.4) |
| inner placement | the Mars chart's `deimos`, the Earth chart's `moon` (data `temperament.inner_key`) |
| company | a mood tick at which the being was awake and together (room, site or field) with at least one friend at the relationships tick |

## 3. State (all new)
`Being` gains eight fields (the Task 4 layer added none; this one needs them because `Being` reads two of them on its hot paths and they are per-being by nature): `mood`, `mood_base`, `mood_halflife` (sols), `mood_k`, `mood_band` (int 0 heavy .. 4 bright), `mood_why` (Variant, null or `{key, id, name, t, clause}`), `mood_quiet_t` (sim hour of the last "gone quiet" line, -1e9 at start), `mood_down_t` (sim hour of an unanswered, logged "gone quiet" line, null otherwise). Both line fields are written only when a line is actually logged (5.6). If Q1 option (b) is chosen, one more boolean `mood_had_episode` (set when the band first reaches low or heavy). Defaults for a being made without a chart (test seam `add_being`): `mood 0.0`, `mood_base 0.0`, `mood_halflife = temperament.neutral.halflife_sols`, `mood_k` derived from it, `mood_band 2`, `mood_why null`.

`Moods` (new, owned by `SimWorld` as `world.moods`) holds only: `cfg`, `seen_ticks` (int, the last relationships `ticks` consumed), `seen_pledge` (bool), `max_id_seen` (int, newborn detection), `pending_hard` (Variant, null or the clause key set at a sol boundary), `pending_pledge` (bool), `lines_sol`, `lines_this_sol`, `agg` (the last tick's sum, sum of squares, heavy count and size, for the per-sol series). `SimWorld` gains `moods`, `moods_enabled` (default true; false skips both hooks and gives every new being the neutral temperament, test seam), the hook calls, and `stats.moods` (section 8).

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
The twelve resulting (base, half-life in sols) pairs, computed from the table above (E): cardinal fire +0.15 / 3.6; fixed fire +0.12 / 1.8; mutable fire +0.09 / 7.2; cardinal air +0.09 / 4.0; fixed air +0.06 / 2.0; mutable air +0.03 / 8.0; cardinal earth -0.01 / 3.2; fixed earth -0.04 / 1.6; mutable earth -0.07 / 6.4; cardinal water -0.11 / 5.2; fixed water -0.14 / 2.6; mutable water -0.17 / 10.4. The nature thresholds of 7.1 are placed in the gaps between these values, never on one, so a change of a hundredth in the table does not silently re-label a sign (test 22b checks the margin).
Why these: the **baseline** is a small lean (the six traits carry most of the personality; a baseline of 0.15 changes travel by 0.02 and idle drain by 4 percent, 5.5); the **recovery rate** is the large temperament lever, because it decides how long a grief or a hard season lasts (5.5 worked numbers). Fixed signs recover fastest: they are the "steady" signs in the chart table ("steady keep working"), and a fixed Deimos stays calm in a crisis. Mutable signs recover slowest and, being pushed repeatedly by a changing colony, swing hardest (scoping note C, option 1). Water takes things to heart (lower baseline, slower recovery), fire lifts quickly. The element and modality tables are the existing `signs.json` classification, not a new one; the numbers are the lead's, E. The Deimos sign already contributes 20 percent of the six traits (inner boost 1.5 on care and sociability); mood reads the sign itself, so it is a second channel and not a restatement of the traits (two beings with the same two-word description can differ here).
**Earth-born founders** have no Deimos (HANDOFF 3: sun, moon, rise). Their inner placement is the Moon (weight 0.3, inner boost 1.4), so `temperament.inner_key = {mars: "deimos", earth: "moon"}`. Stated as a decision: the seven founders are tempered by the Moon. This is an intended difference, not a gap: the founders carry Earth's moods to Mars and their children carry Mars's (designer-emergence: sound; recorded so no one "fixes" it).
**Neutral** (test seam beings, `moods_enabled` false): `base 0.0`, half-life `temperament.neutral.halflife_sols` 4.0.

### 5.2 The mood tick (every relationships tick, in this order)
1. **Newborns.** Beings with id above `max_id_seen` (scanned from the end of `world.beings`, which is in ascending id order) are newborns; update `max_id_seen`. A newborn's mood is its baseline already (set at creation). If it has a recorded `parent_id` that is alive and its `born_t` is within this tick, the parent gets the `birth_parent` push (5.3) with why `{birth, id: newborn id, name}`.
2. **Decay.** For every living being: `m += (b - m) x k`; if `abs(m - b) < rest_eps` (0.001), `m = b`. One pass over `world.beings`.
3. **Event pushes** from `world.relationships.events` (5.3), in list order, each scaled by headroom, applied to a being found by id (a being no longer alive is skipped).
4. **Colony pushes** from `pending_hard`, `pending_pledge` (5.3), then cleared. One pass over `world.beings`.
5. **Company.** For every being with `relationships.with_friend[id] != 0`: the `company` push (5.3). Part of the same pass as step 4 when a colony push is pending, else its own pass; either way at most two passes in all.
6. **Bands and why.** For every being: band with hysteresis (5.4); clear `mood_why` when `abs(d) < why.show_dev`; update the aggregates (`sum`, `sum of squares`, heavy count). (Whys are set inside steps 1, 3, 4 and 5 as each push lands, by the rule of 5.4.)
7. **Lines** (5.6), candidates gathered in this pass and offered deepest first.
Steps 2, 4, 5 and 6 can be one pass in the implementation; the order of effects on a single being is fixed as written (decay, event pushes, colony pushes, company, band).

### 5.3 The pushes
Nine pushes. Every push `p` on a being with deviation `d` (taken just before the push) becomes `p x scale` (headroom scale, section 2), so a mood can approach `b - 0.70` or `b + 0.70` but never pass it, a long run of bad news saturates instead of stacking, and the order of pushes inside a tick changes the result only through a bounded, deterministic amount (events arrive in a fixed order).
| Push key | Who | Amount (E) | Source |
| --- | --- | --- | --- |
| `friend` | both of a pair | +0.10 | `friends` false-to-true on a pair that is neither `kin` nor `crew` (relationships 5.5). Every such crossing, line or not |
| `close` | both | +0.15 | `close` false-to-true, any pair |
| `lapse` | both | -0.05 | `friends` true-to-false on a pair that is neither `kin` nor `crew` (alive on both sides) |
| `lapse_close` | both | -0.12 | `friends` true-to-false on a `was_close` pair (replaces `lapse`) |
| `grief` | each mourner (every living being with a bond at or above `lines.friend` to the dead, not only the two named in the log) | `grief_min` -0.25 at bond 0.30 to `grief_max` -0.60 at bond 1.0, linear in bond | relationships 5.1 |
| `birth_parent` | the recorded parent of a newborn, if alive | +0.24 | step 5.2.1. Raised from 0.08 (designer-feel asked for about 0.20): the colony's rare joy must reach the light band on its own, and entering a band needs `d` 0.03 past its line (0.18 + 0.03 = 0.21), so 0.20 would fall just short at a baseline of zero deviation; births are a few a run, so it cannot flood |
| `hard_sol` | every living being | -0.02 per hard sol; not applied to a being with `d <= hard_floor_dev` (-0.30) | a sol boundary at which air, food or ice is short, using the same three clauses and data keys as `Council._hard_entry` (`ages.sample.o2_min_fraction`, `food_min_fraction`, `ice_min_sols`) |
| `pledge` | every living being | +0.10 | the Council's first and only pledge (`stats.council.pledge_sol` set) |
| `company` | each being with a friend together with it this tick | +0.006 per tick, scaled by `1 - d / company_ceil_dev` (0 at and above `d` +0.15) | `relationships.with_friend` |
Cut in revision 2: `age_up` and `age_down` (the colony settling or slipping back). They moved every being in lockstep, the Council and the ages already speak for the colony in the log, and the hard-season push below already makes a slipping colony felt (designer-emergence and designer-feel both asked for the cut). The `age_changes` counter is no longer read by moods.
**Why `company` has a ceiling.** Friends give company, company lifts mood, mood (travel gain) sends beings roaming, roaming meets more rooms, which grows friendships: a popularity loop that would favour the already-befriended, which is the K1 problem again by the back door (designer-emergence: the worst loop in the design, not the death spiral). Company can lift a being only to `d` +0.15, below the line of the light band (0.18, and 0.21 to enter it with hysteresis), so company alone never makes anyone "light", never moves the travel chance by more than 0.15 x 0.15 = 0.022, and cannot compound. Friend, close and birth pushes still reach light and bright. A diagnostic and a target watch the loop (M9, section 12).
Kin and crew bonds make no `friend`, `lapse` or `lapse_close` push: their seeding and thinning are silent in the log (relationships 5.2, 5.5) and would otherwise hit the seven founders with up to six lapses each around sols 18 to 30. A kin or crew bond that was `was_close` and lapses does give `lapse_close`. The `company` push does count kin and crew (a child glad of its parent's company).
Why the grief pushes everyone with a bond and not two: the log names at most two mourners per death (a reading budget), but mood is per being; a death in a well-connected colony can touch ten people, and that is what the headroom scale and the floor are for (5.5).
**Colony pushes** (`hard_sol`, `pledge`) are recorded at a sol boundary and applied at the next mood tick so the sol hook stays O(1). The `hard` clause carried in the why is the first of ice, air, food that is short, in that order (the order of `Council.hard_clause` ties). The clause is kept for 6b and never shown (7.1).
**`hard_sol` stays colony-wide; the personal form is deferred.** Designer-emergence asked for it to land only on beings exposed that sol. Checked in code: oxygen, food and ice are colony stocks (`Council._hard_entry` reads `col.oxygen`, `col.food`, `col.ice`), a being carries no exposure state, and `is_outside()` read at one fixed clock moment is a poor proxy for who suffered. Differences between beings already come from the Deimos rate and the floor `hard_floor_dev`. Recorded as deferred (section 17).

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
**The why (rewritten in revision 2).** The why is the cause the panel names. A rule that can mislead is worse than none, so it is strict. After each push lands on a being (with `d_after` the deviation after it):
1. **Eligible pushes.** Six keys are *major*, judged by size: `friend`, `close`, `lapse`, `lapse_close`, `grief`, `birth_parent`. A major push is eligible if its **nominal** amount (before the headroom scale) has `abs` at least `why.min_push` (0.04). Judging the nominal amount means a push that landed on a saturated mood (scale near 0) can still be named as the reason. The three others, `hard_sol`, `pledge` and `company`, are **exempt from `min_push`** and are *minor*: they may set a why only when the being has none (or the stored one has the wrong sign, rule 3) and `abs(d_after) >= why.show_dev`.
2. **Sign agreement.** A push may set or replace a why only if the sign of the push equals the sign of `d_after`. (A glad news on top of a deeper sorrow does not turn the sentence cheerful.) The panel also shows a why only if its stored sign (the sign of the push that set it) equals the sign of the present `d`.
3. **Replacement.** A major eligible push replaces the stored why if (a) there is none, or (b) the stored why has the opposite sign to `d_after`, or (c) it is at least half of the present `abs(d_after)` (scaled amount) and the stored why is not sticky, or is sticky and the new push is of a sticky key too.
4. **Sticky whys.** `grief` and `lapse_close` are sticky: no `friend`, `close`, `birth_parent`, `lapse`, `company`, `hard_sol` or `pledge` can replace them while the sign is unchanged and `abs(d) >= why.show_dev`. A second grief (a second death) or a `lapse_close` may replace a sticky why by rule 3(c). So the panel keeps saying "mourning {other}" until the mood is genuinely back near its baseline, and a `company` push can never take the place of a grief why (designer-clarity B2, S4).
5. **Clearing.** `mood_why` is cleared when `abs(d) < why.show_dev` (0.10) after the decay step. Otherwise it stays until replaced.
6. **Tense.** A hard why is *remembered*, not current: the sentence is in the past tense ("The hard days have weighed on them.") because the stocks may have recovered before the mood did. A grief why says "mourning" in the sol it was set (`why.fresh_sols` 1.0 of sim time since `why.t`) and "still mourning" after.
So the panel names a cause for as long as the mood is clearly off its baseline and the cause is a true part of it, and says nothing about cause when it has settled. The success claim of 7.4 is about heavy episodes; a being that is merely low gets a panel sentence and no log line (designer-clarity B3; 7.4).

### 5.5 What mood changes: exactly two behaviours, gains in data
Both behaviours read the being's own mood and read it clamped to `effects.clamp_low` -0.60 to `effects.clamp_high` +0.40. Neither adds, removes or reorders a random draw. Starting gains for the calibration runs (the decision rule of section 10 may halve them; both are 0.0 in the dormant build of step 2 and in the dormant proof): `effects.travel_coef` 0.15, `effects.energy_coef` 0.25.

**Effect 1: company-seeking. `Being._restless_travel`.** The chance to travel to a neighbouring room is `restless.travel_base + restless.travel_coef x restless` today (0.08 + 0.32 x restless, which is 0.08 to 0.40). It becomes that plus `effects.travel_coef x clamp(m)`, floored at `effects.travel_floor` 0.02 and capped at 1.0. Still one `chance()` draw per call, same position in `decide`. The pull toward rooms (`room_pull`, relationship pulls) is unchanged.
- Size, E: for a middling restless 0.4 (chance 0.208) a mood of 0.1 moves the chance by 0.015 (about 7 percent relative); grief at -0.5 moves it by -0.075 (about -36 percent relative, for the sols the grief lasts); the colony-wide mean shift is under +-0.01. Deimos baseline alone (+-0.15) moves it by +-0.02.
- What it does to existing systems: it changes only how often a being who has nothing else to do wanders (the last branch of `decide`). Sleep (first branch), joining construction, resuming and starting mining (branches 2 to 4) come before it and read no mood. Withdrawn beings stay put, so they stay where they already are with whoever is there; bright beings roam and meet more rooms. Bonds follow their days (relationships), so over a run mood slightly spreads who meets whom; the relationship targets R3, R4, R10, R11 are re-judged after the reset (section 12).
- Personality guard (12, M3): the mood term at its clamps spans -0.09 to +0.06 (0.15 wide), against the restless trait term's 0.32 wide; the mood span is 0.47 of the trait span at the clamps and, with the typical |m| under 0.1, about 0.05 of it.

**Effect 2: tiredness. `Being.drain_per_h`, idle branch only.** *Status in revision 2: built, but the first behaviour to be switched off (cut 3, section 15) and shipped on only if run 2 of section 10 passes the extended M4 and moves the ages by no more than reported bounds.* The player cannot see it (designer-feel: "invisible, and the only part that moves the ages' calm and rested clauses"); the travel effect alone satisfies owner decision B. Idle drain `energy.drain_idle` (1.3 per hour) is multiplied by `1 - effects.energy_coef x clamp(m)` (a factor from 0.90 at `m` +0.40 to 1.15 at `m` -0.60). Sleep (no drain), EVA, work and mining drains are unchanged: a being doing survival work does not tire faster because it is sad.
- Size, E: at the clamps +-10 to 15 percent of idle drain; a grieving being (m -0.5) loses 0.2 energy per idle hour more (1.3 to 1.5); the mean over a run is within +-2 percent (mean mood about 0). Expected shift of the table's `avgE` and `asleep%` columns: under 1 point and under 0.5 point (the sleep threshold 28 and the night threshold 65 are unchanged, so a heavy being simply goes to bed somewhat sooner). T8 asks for avgE 40 to 90 and asleep 5 to 30 percent; measured 54 to 58 and 10.6 to 10.9, so the margin is large.
- What it does to existing systems: **energy** (a bounded per-being bend, as above); **sleep** (earlier, never later than today, for the low-mood; slightly later for the bright; the draws `night_sleep_chance` and `day_wake_chance_per_h` keep their form); **work and mining** (only through energy: the yield factor `0.55 + energy / 220` falls 0.0045 per energy point, so one mean point lost is about -0.6 percent mining yield, E; construction rate uses the same factor); **births** (untouched: `Colony.birth_chance` reads traits only); **Council lean** (untouched: lean reads traits, stocks and the child stake only; the Council moves only through the changed trajectories, which Q2 covers); **ages** (the "calm" and "rested" clauses read energy, so the Settlement entry and the fall-back sols can move by a few sols; re-measured and reported, not judged against 67, 58, 54, 65, 53, section 12).

**Verified in code (revision 2; reviewers flagged this as uncertain).** Every place the sim reads `energy`, from `sim/being.gd`, `sim/ages.gd`, `sim/world.gd` and `data/beings.json`:
- `decide` (being.gd): `energy < energy.sleep_below` (28) sends a being to bed before any other branch, and at night `energy < night_sleep_below` (65) does so with chance 0.6. **Volunteering for construction, resuming a mine intent and starting a mining trip all come after that gate and read no energy themselves**; a heavy being is simply asleep, not volunteering, for the hours it is below 28.
- Trip departure: the trip test (`trip_time(site) < trip_limit()`) reads suits and distance, not energy.
- `update` (being.gd line 145): **outside, `energy < exhausted_turn_back` (12) turns a being back** (`_turn_back(w, "exhausted")`). This is a threshold read, and the idle-drain bend reaches it only through the energy a being has when it leaves (departure needs at least 28; mean energy is 54 to 58). One lost point of energy shortens the margin to 12 by about 1 point of a margin of roughly 40, so a trip is shortened by about 2 to 3 percent per lost point (E).
- Sleep (`_sleep_step`): `wake_at` 97 and `day_wake_above` 75 are read, but the idle drain is not applied while asleep, so the bend moves only the time to bed.
- Yield: mining (being.gd 685 to 693) and construction rate (world.gd 516) read `0.55 + energy / 220`.
- Ages (`ages.gd` 55 to 64): the "calm" clause counts beings below `exhausted_turn_back` or returning outside, the "rested" clause counts beings at or above `sleep_below`.
The consequence: the loop is wider than rev 1's single "yield -0.6 percent per point" figure, since the departure-energy path and the early-to-bed path both reach it. It is still bounded: the effect is idle-only, the clamp keeps it within 0.90 to 1.15, and the reads are all far from the thresholds at mean energy 54 to 58. The probe measures it rather than trusting the estimate: trips per sol, exhausted turn-backs and minimum ice are M4 inputs, paired over 15 seeds (section 12).

**Death-spiral guard, argued from the code.** The spiral the brief names is grief to lower energy to more deaths to more grief. In this sim no death cause reads energy directly: deaths are `air`, `thirst`, `hunger` (colony stocks) and `suffocated outside` (suit air; an exhausted turn-back reads energy but only brings a being home sooner). Energy touches the stocks through mining and building yield (-0.6 percent per mean point) and trip length (above). The loop therefore has gain far below 1: even if every being sat at the mood floor (`m` -0.6 effective), idle drain would be +15 percent, mean energy at most about 3 points lower (E), mining yield about 2 percent lower, ice supply about 2 percent lower. The chain is also broken at its source, five ways: (1) mood reads nothing about energy or sleep; (2) the energy effect is idle-only; (3) the pushes are headroom-scaled with a hard `hard_sol` floor at d -0.30, so mass grief saturates at about -0.70; (4) the effect clamps at -0.60; (5) the mood never touches mining will, volunteering, births, stocks or air. The probe checks it anyway (M4), against 15 seeds.
Worked example, E: bond 0.5 grief gives -0.25 - 0.35 x (0.2 / 0.7) = -0.35 on a cardinal air Deimos (half-life 4.0): `d` returns inside the low band (-0.18) in 3.8 sols, below `show_dev` 0.10 in 7.2 sols. The same push on a mutable water Deimos (10.4): low for 10.0 sols, off the panel in 18.8 sols. On a fixed earth Deimos (1.6): low 1.5 sols, off the panel in 2.9 sols. A bond-0.8 grief (-0.50 at full headroom) is heavy (`d <= -0.40`) for 0.6 sols (fixed earth), 1.4 (cardinal air), 3.7 (mutable water).
Steady offsets under a long hard season (`hard_sol` -0.02 a sol, E): `-0.02 / (1 - 0.5^(1/H))` is -0.07, -0.13, -0.24, -0.29 for H 2, 4, 8, 10.4 (floored at -0.30 by `hard_floor_dev`): a steady colony stays even, a mutable one goes low. Ice pressure shows in the slow beings first and never in everyone at once.

### 5.6 The two log lines (individual stories, capped)
Only two kinds of mood line, both about one named being, both fixed texts:
- **`mood_quiet`**: a being is a *quiet candidate* at a mood tick when its band is heavy, `mood_down_t` is null and `t - mood_quiet_t >= lines.quiet_cooldown_sols` (20). The condition is a state, not an event, so a candidate that was not logged this tick is still a candidate at the next one for as long as it stays heavy. Logging it sets `mood_quiet_t` and `mood_down_t`.
- **`mood_relief`**: a being is a *relief candidate* when `mood_down_t` is set, the band is at or above even and `t - mood_down_t >= lines.relief_min_sols` (3 sols). Logging it clears `mood_down_t`. If the band is below even it waits.
**Cap and order (revised).** At most `lines.max_per_sol` (1) mood lines per elapsed sol, colony-wide. Candidates (quiet and relief together) are offered at each mood tick in this order: deepest first (most negative `d` for quiet, a relief candidate counts as `d` 0 for this order), ties broken by the highest bond to the `mood_why.id` (0 if none), then lowest being id. Ascending id would have favoured the founders for ever (designer-emergence, designer-feel). A candidate over the cap is **dropped for this tick and changes no state**: `mood_quiet_t`, `mood_down_t` stay as they were, so it is offered again at the next tick (counted in `stats.moods.lines_dropped` once per drop). A relief therefore always has an earlier logged quiet for the same being (T13(3) holds by construction), and a being who recovers before its line is offered simply never gets one. Text choice for a quiet line by the being's `mood_why.key`: `grief` gives `quiet_grief`, `lapse` or `lapse_close` gives `quiet_lapse`, `hard_sol` gives `quiet_hard`, anything else `quiet`. **Two wordings** exist for each of the five texts (7.2); the variant is `(being_id + sol_number) mod 2`, a pure function of state, no draw. The log entry carries `being_id`, `other_id` (the why's id or null), `place` "" and `building_id` null, like the relationship entries, so click-to-focus can come later without a sim change.
Why so few: at most one a sol, and only for a being that has really gone heavy (a bond-0.7 grief or deeper, or stacked news on a slow Deimos). A being that is only low gets no line (the panel is where low is read; a rare "entering low" line for a slow Deimos grief was proposed by designer-clarity and deferred, section 17). Expected: 0 to 40 quiet lines a run (E), zero on a calm seed. The existing grief line ("{a} is mourning {b}.") and friend lines tell the cause; the quiet line tells that it lasted.

## 6. Numbers, and what they imply (all E)
- **A calm colony is calm.** Sustained pushes in a peaceful seed are small: a typical being forms a new friendship every few dozen sols and has about two hours a sol with a friend. Steady-state offset from company alone is `0.006 x hours / (1 - r)` where `r = 0.5^(1/H)` is the daily retention: for 2 hours a sol, +0.015 to +0.08 depending on H (2 to 8 sols); for 4 warm hours on a slow Deimos the uncapped figure would be +0.25, which the company ceiling (+0.15) now holds down. Friend and close pushes add a few hundredths. So in a calm seed the typical deviation stays within +-0.1, the panel says nothing about spirits for most beings, and the visible variation is the Deimos baseline and the lift of well-befriended, slow-recovering beings. That is the intended texture ("weather rarely, climate always"), and it is why Q1 (a) matters: without a temperament sentence the player sees little in a calm colony. In a calm colony the panel for an even being with no cause is therefore short (name, nature if any, company), by design (7.1).
- **Crises color a colony.** A death in a connected colony with `friends_mean` 8 gives about eight pushes of -0.25 to -0.5 inside one tick; slow recoveries stay low for 10 sols. In the Task 5 ice crises (thirst deaths 10, 0, 22, 0, 5 over 300 sols) many beings will have a grief within a few sols; the headroom scale keeps them at or above `b - 0.70`, and the idle-only effect keeps the cost at the bounded 15 percent of idle drain.
- **Frequency of band lines.** A being goes heavy only from `d <= -0.40`: one bond-0.7 grief on any Deimos, or two bond-0.5 griefs inside a few sols, or a long `hard_sol` run on a mutable Deimos stacked with a grief. In the Task 5 baselines grief mourners per death average about 2 to 8 (E), so most deaths produce heavy beings only at high bonds.
- **Baselines versus the traits.** Baseline spread is sd about 0.09 across the twelve signs. Travel effect at one standard deviation of baseline: 0.0135; the restless trait moves the travel chance by 0.32 over its range (sd of the restless trait across charts about 0.2, E, so 0.064). The baseline therefore explains about a fifth as much travel variation as the restless trait does and cannot flatten it.
- **Unit conventions.** Sim hours for `tick_h`, sols for half-lives, mood units are dimensionless (nominal range -0.9 to +0.9), bond units as in relationships.md.

## 7. What the player sees (view; sim read-only; fixed texts, no numbers)
### 7.1 The being inspect panel (6p items 2; text only)
**Selection and closing (decided in revision 2; designer-clarity B1).** Constraint: existing primitives only (a stroke or outline drawn with the primitives the view already uses for building selection), no new art, no ring sprite, no meter. The locked building rule stays: tapping a building toggles its roof ("tap again to open the roof").
1. **Select.** A tap that hits a colonist selects it and opens the panel. A colonist can be hit only where it is drawn: outside, or inside a building whose roof is open. **A colonist hit wins over the building hit under it**, and does not toggle the roof; a colonist inside a closed building cannot be hit, so the building tap behaves exactly as today.
2. **Mark.** The selected colonist is drawn with an outline made from the existing primitives (a stroke around its silhouette, the same family as the building selection outline). While it is inside a closed building it is not drawn, the panel stays open.
3. **Close.** The panel and the selection close on: a tap on empty ground, a tap on any building, Esc, or the death of the selected being (rule 6). **A tap on a building while a colonist is selected only closes the selection** (it is consumed and does not also toggle that building's roof); the next tap acts as normal. This keeps "tap again to open the roof" predictable: no tap ever does two things.
4. **One selection.** Selecting a colonist clears any selected building and vice versa; there is never more than one panel.
5. **Speed.** At any game speed the panel refreshes at most `selection.refresh_hz` (2) times a second of real time from cached lines, and the shown band sentence changes at most once per `selection.hold_s` (1.0) real second; pending changes show on the next refresh after the hold. The hold lives in a small pure helper (`PanelHold`, timestamps passed in), not in the sim and not in `BeingPanel.lines`. At 1000x the panel can therefore show a band the sim has already left; that is accepted: it never shows a wrong sentence, only a slightly old one.
6. **Death.** If the selected being dies, the panel shows one beat, "{name} has died." (`text.panel.died`), for `selection.died_beat_s` (2.0) real seconds, then closes.
7. **Tap from the log (minimal click-to-focus, pulled into 6a, view only).** A log line that carries a `being_id` (every relationship line and both mood lines already do) is a tap target: tapping the line selects that being and opens its panel by the rules above. Where the view can split the text, a tap on either named colonist selects that one (`being_id` or `other_id`); where it cannot, a tap anywhere on the line selects `being_id`. There is no camera pan, no follow, and the being need not be visible (the panel needs no picture; this is the point). If the being is dead, the panel opens straight to rule 6's sentence for one beat. This is a scope addition against the scoping note's list of carry-overs (relationships.md section 19: click-to-focus), accepted because the success test of 7.4 is otherwise a hunt for a small sprite; it is the **first thing cut** (section 15).
The panel shows, in this order, **at most four sentences** at 720p, each a template from `data/mood.json` `text.panel`, `text.band`, `text.why`, `text.nature`. (A fifth line was too many at 720p, designer-clarity S1.)
1. **Who** (title): "{name} is {description}." (the existing two-word description, for example "Vana-3 is warm and nurturing.")
2. **Spirits.** The band sentence, **omitted when the band is even and no why is shown** (designer-feel: "much as usual" is clutter): low "{name} is out of spirits."; heavy "{name} is struggling." (stepped down from "heavy-hearted", designer-feel); light "{name} is in good spirits."; bright "{name} is lit up."
3. **Why**, only when `mood_why` passes the display test of 5.4 (stored sign equals the sign of `d`) and the band is not even, appended to line 2 after one space:
   - grief (set this sol) "They are mourning {other}." / grief (older) "They are still mourning {other}."
   - friend "They have just found a friend in {other}."
   - close "They have grown close to {other}."
   - lapse "They miss {other}'s company."
   - birth "They were there when {other} was born."
   - hard "The hard days have weighed on them." (past tense; no resource named)
   - pledge "The council's promise has lifted them."
   - company "They are glad of company."
   Lines 2 and 3 together count as two sentences.
4. **Nature** (Q1 option (a)), at most one sentence, **only when no why sentence is shown** (so at most four sentences: who, spirits, why, company is four; who, spirits, nature, company is also four). It reads the stored base and half-life and picks the first match of this ordered list; the thresholds sit in the gaps of the table of 5.1 and each of the four sentences has its own sign: base at or below `nature.base_lo` (-0.155) "{name} takes things to heart." (mutable water, -0.17); base at or above `nature.base_hi` (0.135) "{name} usually sees the bright side." (cardinal fire, +0.15); half-life at or above `nature.slow_halflife` (7.6) "{name} is slow to shake off a mood." (mutable air, 8.0; mutable fire at 7.2 and mutable earth at 6.4 stay unlabelled; mutable water is already taken by the first line); half-life at or below `nature.quick_halflife` (1.7) "{name} soon shakes off a mood." (fixed earth, 1.6). Exactly four of twelve signs, one each (a rev 1 error: the old thresholds 0.15, -0.17, 10.0, 1.7 matched only three signs, with "slow" unreachable because the only half-life above 10.0 belongs to the sign the second line already took, and they sat on float sums). Reachability is a test (22b).
5. **Company.** If `friend_count` is 0: **"{name} knows no one well yet."** (exact, K1; the K1 definition: no pair holding the `friends` flag, kin and crew included, so a newborn whose kin bond still holds does not show it). Else if the being has a close pair: "{name} is close to {other}." (the close friend with the highest bond, ties by lowest id). Else: "{name} counts {other} as a friend." (the friend with the highest bond, ties by lowest id).
No number, no bar, no icon, no tint, no sprite change, no sign, no trait word beyond the existing description, no band index. The panel never shows the baseline, the half-life, the `mood_why` key names, the clause or the chart.
The view builds the lines through one pure function in `view/model/` (`BeingPanel.lines(world, id)`) that reads only `Being` fields, `relationships.friends_of(id)` and the texts in `data/mood.json`. It takes no real time and no RNG, so a headless test proves it (section 13, tests 22 to 24, 32 to 34). A player who has been away from the log sees mood only through the panel: the log is a stream and the panel is the state (designer-clarity S2). The accessor `friends_of(id)` walks the packed mirror: estimated 0.3 to 0.6 ms per call at 5,000 pairs; the view calls it for the selected being at most twice a second and caches the result between calls.
### 7.2 Log lines
`mood_quiet` and `mood_relief` of 5.6. Texts (`text.lines`, two wordings each, variant by 5.6; the first is the plain one): `quiet_grief` a "{name} has gone quiet since {other} died." / b "{name} keeps to the quiet corners since {other} died."; `quiet_lapse` a "{name} has gone quiet without {other}." / b "{name} misses {other} and says little."; `quiet_hard` a "{name} has gone quiet. Times are hard." / b "{name} says little these hard days."; `quiet` a "{name} has gone quiet." / b "{name} is keeping to the quiet corners."; `relief` a "{name} is smiling again." / b "{name} has found a smile again." They carry no number. They join the colony log (500 entries, FIFO, kind-blind), and relationship lines already take 9.6 to 13.0 percent of it; the combined share of relationship, Council and mood lines is judged against `balance.log_share_max` 0.25 (section 12, M7).
### 7.3 What stays unseen
No HUD line, no colony-wide mood word ("the colony is sad" is never said; the hard-season lines of the Council and the ages say what the colony does, not how it feels), no strip entry, no age text that mentions mood. The `md` table column and `stats.moods` are for tests and the probe only.
### 7.4 The success test (clarity, from the scoping note)
A player can say why a named being is **heavy** (the deep case) from the log lines and the panel alone: the log carries the grief or friend line and, if it lasts, the quiet line; tapping the line opens the panel, which gives the band and the why. The claim is deliberately narrowed (designer-clarity B3): a being that is only *low* has no log line of its own; it is read from the panel, and the player who never opens a panel will not know. The two log lines teach the system at its extremes; the panel is the place for everything gentler. Nothing in play announces the baseline reset; it is recorded in the repo only (section 10, designer-clarity).

## 8. Stats: `stats.moods` (run-wide, never windowed, never shown)
| Key | Definition |
| --- | --- |
| `pushes` | `{friend, close, lapse, lapse_close, grief, birth_parent, hard_sol, pledge, company}` count of pushes applied (after scaling, including those scaled to zero) |
| `bright_beings`, `light_beings` | counts of beings that reached the bright / light band at least once (a dead-text check: bright must occur on some seed, 12) |
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
| `view/model/being_panel.gd` (new), `view/model/panel_hold.gd` (new, pure), `view/main.gd`, the log view | the panel, selection and closing rules, the hold and refresh limit, tap-from-log (7.1) | view, step 8 only; no new art |

**Accessor contract (6p item 1).** `friend_pairs()` returns `{lo: PackedInt32Array, hi: PackedInt32Array, flags: PackedByteArray}` for pairs holding the `friends` flag, with `flags` bit 1 close, bit 2 kin, bit 4 crew; order unspecified (mirror order, or dictionary order if the mirror is out of step with `pairs`); the arrays are copies; nothing the caller does to them touches relationships. `friends_of(id)` returns an ascending-by-other-id Array of `{id, close, kin, crew, bond}`; `bond` is for choosing who to name and is never displayed. Both are read-only by contract (tests 27 and 28 prove it) and cost O(stored pairs).

## 10. The baseline reset: procedure and record
This slice changes behaviour (decision B). The record is part of the definition of done. Steps, in order, each a commit:
1. **Freeze the "before".** Copy into `docs/balance/task-6a-log.md` the Task 5 table (hashes below), the Task 3 ages and the Task 5 Council figures. They are measured already (`docs/balance/task-5-log.md`); the step re-reads them from a fresh run of the unmodified tree at the commit before the module lands, so "before" is a measurement on the same host, not a quotation.
2. **Dormant build** (effects at 0.0): module, data, hooks, accessors, panel text, all tests green. Run the five seeds at 300 sols twice; the table (with `md`) differs from Task 5 only in that column; `tests/mood_hash_proof.gd` strips `md` and reproduces the Task 5 hashes (below), then the chain reproduces Tasks 4, 3 and 1. Exit 0 required. This proves the layer added no side effect.
3. **Noise-floor control** (added in revision 2; designer-emergence). Both gains set to `calibration.control_gain` **1e-6** (a negligible effect on every decision, the behaviour sites taking the mood branch because `coef > 0.0`). Five seeds, 300 sols, twice each; and the 15 seeds of `r9_seeds`. Why: any behaviour change, however small, can flip a single `chance()` and then the whole colony diverges by chaos, moving Council entry, pledges and friend webs on its own. The control measures that chaos spread so that mood's real effect can be separated from it. Rule: the control's table hash must differ from the dormant hash on every seed (a trajectory that did not diverge measures nothing); on any seed where it does not, raise the control gain for that seed to 1e-4 and record both values. (Estimate, E: 1e-6 times a mood near 0.1 shifts a probability by 1e-7 and a run holds on the order of 10^5 to 10^6 such draws, so a flip is likely but not certain; hence the check.) The judged effect of mood on Council entry sol, pledge, `friend_pairs`, `lonely_share` and `friend_count` spread is the shift of the gains-on mean (15 seeds) from the control mean, set against the control's own distance from the dormant mean.
4. **Run 1** (one parameter): `effects.travel_coef` 0.0 to 0.15, energy at 0. Five seeds, 300 sols, twice each, T1 to T13. Report.
5. **Run 2** (one parameter; conditional, cut 3): `effects.energy_coef` 0.0 to 0.25, travel as kept after run 1. Same. Report. It ships only if it passes the extended M4 (trips per sol, exhausted turn-backs, minimum ice) and the ages stay within T10's ranges; otherwise `energy_coef` stays 0.0 and the slice ships with one behaviour, said plainly.
6. **Guards on the final configuration**: M4, M3, M1, M9 over the 15 seeds of `relationships.balance.r9_seeds` at gains on, at the control and at gains 0 (the 15 dormant runs are the paired baseline).
7. **Record**: old and new table hashes per seed side by side (below, filled in at this step), **every run of steps 2 to 6 run twice per seed and compared byte for byte (`cmp`), not only the final configuration** (designer-clarity B4), T1 to T13 per seed before and after, ages and Council per seed before and after (with C1 and C4 per seed and the old value beside each), **population at sol 300 and births per seed before and after**, and the verdict on every target of section 12. The new hashes become the reference; the old ones are marked superseded in the log, in `HANDOFF.md` section 8 and in `docs/tasks/task-6-plan.md`. Nothing in play tells the player a reset happened.
**Decision rule for each run (stated before the run).** Keep the gain if every M target of section 12 passes and T1 to T12 pass on all five seeds. If M4 (death-spiral guard) or T1 to T12 fail, halve that gain once (0.075 and 0.125) and rerun; if it fails again, that gain stays 0.0, and the result goes to the owner (the slice then ships with one behaviour, or none, and says so). M9 failing at the travel gain halves it by the same rule.
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
- **The boundary step on seed 1234 in the Council age.** The mood sol hook adds under 0.05 ms and the mood tick adds at most 0.5 ms on the 1 in about 25 boundary steps where a relationships tick coincides. **Rule: the maximum boundary step in the Council age, re-measured run alone with the module on (five runs on seed 1234, not three, designer-clarity S7, and the p95 of boundary steps reported beside the maximum), is at most 16.7 ms, and the mood module is responsible for at most 0.6 ms of any step.** If the Council boundary step exceeds 16.7 ms and the profile attributes more than 0.6 ms to moods, the order of remedies is: (1) move the mood tick one step after the relationships tick (behaviour-identical except for a one-step delay; no hash change beyond the reset); (2) drop `company` (the only per-pair addition, scope cut 4); (3) halve the aggregate work by computing `sd` every fifth sol. If the 16.7 ms overshoot is not attributable to moods (the existing trigger of council.md 11.1), moods are not a reason to act.
- **Memory**: eight fields on each Being; a Being is already a RefCounted with ~45 fields, so about +15 percent per Being, 160 Beings, negligible.
- **Probe and view cost**: `friends_of` 0.3 to 0.6 ms per call, view side, at most 2 per second for one selected being.

## 12. Calibration probe and balance targets
**Probe** `tools/mood_probe.gd`: read-only; runs the real module on seeds 42, 7, 99, 1234, 2026 for 300 sols in the dormant build, at the noise-floor control (gains 1e-6) and at each parameter run of section 10, and on the 15 seeds of `relationships.balance.r9_seeds` for the guards. Reports to `docs/balance/task-6a-calibration.md`:
1. **Distribution.** Per seed at sols 30, 60, 100, 150, 200, 300: mean, sd, minimum and maximum `m` and `d`, share in each band; the baseline sd and range of the colony.
2. **Pushes.** Counts per push key, `pushes_zeroed`, the largest single-tick change of any mood, number of beings that reached the heavy band and for how many sols (median), quiet and relief line counts, dropped lines.
3. **Deimos signature.** Beings split by baseline thirds: mean `m`, travel decisions per awake hour, and idle drain per hour, top against bottom third; and by half-life thirds: median sols for `d` to return inside 0.05 after a grief push (measured from the push log of the run).
4. **Personality check.** Rank correlation (Spearman) between each being's restless trait and its travel starts per awake hour, gains on against gains 0 (paired seeds); and, for the room-pull signature that already exists, the share of moves that go to the room the being's trait prefers (workshop by drive, archive by curiosity, and so on), gains on against gains 0.
5. **Energy and sleep.** `avgE`, `asleep%`, `max_sleep_h`, exhausted turn-backs, per 30-sol row; mining yield per trip (mean), trips; construction hours; gains on against gains 0.
6. **Spiral guard (15 seeds).** Total deaths and thirst deaths at 300, minimum ice, hard-sol count, per seed, gains on against gains 0, paired by seed; plus the worst 10-sol window of heavy share.
7. **Ages and Council.** Settlement entry, fall-back, Council entry, meetings, proposals, pledge, per seed, before and after; relationships targets R3, R4, R10, R11, K1 counts.
8. **Cost.** Mood tick median, p95, max at pop above 120; relationships tick median before and after; the boundary-step maximum on seed 1234; share of the mean step.
9. **Inspect text audit (blocking check).** For every living being at sol 300 on each seed: build the panel lines; check each from data, no digit, no `%`, **at most four sentences**; count by band, by why key, by nature sentence (each of the four nature sentences must occur on at least one seed, and the share of beings with a nature sentence is reported against the 4-of-12 expectation); K1 sentence present exactly when `friend_count` is 0; count of beings whose displayed why is sign-inconsistent (must be 0).
10. **Noise floor and the Matthew check.** For the Council entry sol, pledge presence, `friend_pairs`, `lonely_share` and the standard deviation of `friend_count`: gains 0, control (1e-6), gains on, on 15 seeds, with the control-to-dormant spread stated beside the gains-on shift. Whether any seed's control equalled the dormant hash.
11. **Visibility diagnostic (reported).** Stay-put share (idle decisions that end without a move) of beings in the heavy or low band against the same beings at rest, gains on; expected to differ by about 25 percent or more (a heavy being should visibly stay put), a gauge of whether the travel effect can be seen at all.
12. **Dead-text check.** Counts of beings reaching light and bright on each seed (`bright_beings`, `light_beings`); if bright occurs on none of the 15 seeds, `push.close` is raised once to 0.18 and the run repeated (designer-feel).
**Targets** (E; judged by the probe unless marked T13):
| # | Target | Key |
| --- | --- | --- |
| M1 | **Mood is alive but not pinned.** On every seed, from sol 30: mean `abs(d)` over beings and sols between `balance.mean_dev_min` 0.02 and `balance.mean_dev_max` 0.25; the share of being-sols in the even band between `balance.even_share_min` 0.60 and `balance.even_share_max` 0.97; sd of `m` at sol 300 at least `balance.mood_sd_min` 0.05 | `balance.*` |
| M2 | **Deimos is visible, bounded.** Top-third-baseline mean `m` minus bottom-third at sol 300 at least `balance.deimos_gap_min` 0.08 (a baseline survives events); and the slow-recovery third's median return time at least `balance.recovery_ratio_min` 2.5 times the fast third's (measured from grief pushes of the run) | `balance.deimos_gap_min`, `balance.recovery_ratio_min` |
| M3 | **Mood does not flatten personality.** The restless-trait rank correlation with travel starts, gains on, at least the gains-0 value minus `balance.trait_corr_drop_max` 0.05 on every seed; the data check that `travel_coef x (clamp_high - clamp_low)` is at most `balance.mood_trait_span_max` 0.5 of `restless.travel_coef`; and no behaviour except the two of 5.5 reads mood (a test greps the sim for mood reads) | `balance.trait_corr_drop_max`, `balance.mood_trait_span_max` |
| M4 | **No death spiral (15 seeds, gains on against gains 0, paired).** Mean total deaths per seed not above the gains-0 mean plus `balance.death_rise_max` 25 percent or 3 deaths, whichever is larger; mean thirst deaths likewise; mean minimum ice not below the gains-0 mean by more than 10 percent; hard-sol count not above +10 percent; the worst 10-sol window's mean heavy share at most `balance.heavy_share_max` 0.30 on every seed; no unexplained death (`deaths_unexplained` 0) and no new death cause; **and, added in revision 2 for the energy reads verified in 5.5**: mean trips per sol not below the gains-0 mean by more than 10 percent, mean exhausted turn-backs per 30 sols not above the gains-0 mean plus 25 percent or 3, whichever is larger. The control (gains 1e-6) is reported beside both, so the gains-on shift is read against the noise floor | `balance.death_rise_max`, `balance.heavy_share_max` |
| M5 | **Old targets.** T1 to T12 pass on the five standard seeds. T8 (avgE 40 to 90, asleep 5 to 30 percent) is read from the table rows. T10 (ages) is judged on its ranges and counts (`settle_sol_min..max`, projected changes), the exact sols reported and not judged against 67, 58, 54, 65, 53 | structural |
| M6 | **Cost** as in section 11 | `balance.tick_ms_max` 0.5, `balance.tick_ms_peak_max` 1.5, `balance.step_share_max` 0.01 |
| M7 | **Lines.** Mood lines at most 1 per sol on every sol (T13), at most `balance.lines_per5_max` 0.5 per 5 sols averaged over sols 30 to 299; combined share of relationship, Council and mood lines in the 500-entry log, mean over sols 30 to 299, at most `balance.log_share_max` 0.25 on every seed (reported against the 0.20 level of rev 1). If it fails the remedies, in order: raise `lines.quiet_cooldown_sols` to 40; then log `mood_relief` only for a being whose quiet line is still within the last 100 entries; `mood_quiet` is the last to go | `balance.lines_per5_max`, `balance.log_share_max` |
| M8 | **Inspect text.** The audit (item 9) passes: all texts from data, no digit, at most four sentences, K1 sentence exactly when `friend_count` is 0, every nature sentence reachable | structural |
| M9 | **No popularity snowball (15 seeds, gains on against the control, paired).** Mean `lonely_share` (beings with `friend_count` 0 at sol 300) not above the control mean by more than `balance.lonely_share_rise_max` 0.03; the sd of `friend_count` across beings not above the control by more than `balance.friend_sd_rise_max` 10 percent; and R3 (relationships) still passes with its old margin on seeds 42 and 2026 or, if it fails, the failure is attributed in the record to mood or to chaos by the control comparison | `balance.lonely_share_rise_max`, `balance.friend_sd_rise_max` |
| D | Diagnostics, reported only: share of beings in non-even bands per sol; kin newborn first-friend wait (R1) and `lonely_share` before and after (K1 movement); correlation of mood with `friend_count`; Council targets C1 to C8 (Q2 decides what failing them means); the 1234 carry-quorum margin (0.02 before) and the pledge count; probe items 10 and 11 | none |
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
7. **Birth.** The recorded parent of a newborn, if alive, gets +0.24 (scaled) and a why of kind `birth`; a dead parent or `parent_id` 0 gives none; ids scanned from the end find all newborns in a tick and set `max_id_seen`.
8. **Hard sol.** A sol boundary with ice below `ages.sample.ice_min_sols` days of use records `pending_hard` ice; the next tick pushes every being -0.02 scaled; a being at `d` -0.30 or lower gets none; air and food clauses give their own keys; with all three fine nothing; the sol hook loops over no beings (checked by a counter or by the test calling it with a stub list that fails on iteration).
9. **Pledge, and no age pushes.** The pledge pushes +0.10 once; an age change (Landing to Settlement, Settlement to Landing, Settlement to Council) pushes nothing.
10. **Company.** Two friends awake in one room for one tick: both get +0.006 scaled and `with_friend` is set; asleep, in transit, or non-friends: no push; a friend pair on the same ice field counts. **Ceiling:** at `d` +0.15 or above the push is 0, at `d` +0.075 it is +0.003; 10,000 company ticks on a being leave `d` at or below +0.15; company alone never lifts a being to the light band.
11. **Order.** In one tick the order is decay, events (list order), colony pushes, company, band; two same-seed worlds have identical moods.
12. **Bands and hysteresis.** `d` crossing each line changes the band only when 0.03 past it; a mood oscillating between -0.17 and -0.19 for 50 ticks does not flip the band more than once.
13. **Why.** (a) A grief why survives a later friend, close, birth, company, hard or pledge push (sticky) and is replaced by a second grief at least half of `abs(d)`; (b) a non-sticky why is replaced by a major push at least half of `abs(d)`; (c) a push of the wrong sign (a +0.20 on a being at `d` -0.30) never sets or replaces a why, and a stored why of the wrong sign for the present `d` is not shown; (d) the size test uses the nominal push: a grief at `d` -0.68 (scale near 0) still sets its why; a lapse of -0.05 is eligible at `min_push` 0.04; (e) `hard_sol`, `pledge` and `company` set a why only when none exists (or the stored one has the wrong sign) and `abs(d) >= 0.10`, and are exempt from `min_push`; (f) cleared when `abs(d) < 0.10`; (g) the clause is carried and never rendered; (h) a grief why shows "mourning" within `why.fresh_sols` of its `t` and "still mourning" after.
14. **Effect 1.** With `travel_coef` 0.0 the chance passed to `rng.chance` equals Task 5's exactly (stub rng records the argument); with 0.15 and `m` -0.5 it is lower by 0.075 (clamp inside -0.6); with `m` +0.9 it is raised by 0.06 (clamp 0.4); never below 0.02; exactly one `chance` draw per call in both cases.
15. **Effect 2.** With `energy_coef` 0.0 idle drain equals Task 5's; at 0.25 and `m` -0.6 it is 1.15 times; at +0.4 it is 0.90 times; sleep, EVA, work and mining drains are untouched at any mood.
16. **No other reader.** A scan of `sim/` for `mood` outside `moods.gd`, `being.gd` (the two sites and the fields), `world.gd` (hooks and creation) and `relationships.gd` (the feed) finds nothing; no `sim/` file other than those reads `mood` fields (mining, births, ages, Council, resources, powers).
17. **Dormant purity.** With both gains 0.0, seed 42 for 10 sols, a world with `moods_enabled` true and one with false have equal old `stats` keys (skipping `moods`), equal beings (id, building, state, energy, wait), equal stocks and the same next 1,000 draws.
18. **Determinism.** Two same-seed worlds (gains on) have identical moods, bands, whys, `stats.moods` and log for 60 sols.
19. **Lines.** A being in the heavy band logs `mood_quiet` with the text chosen by its why (four texts, two wordings each by `(id + sol) mod 2`), once; the cooldown of 20 sols blocks a second; the cap of one per sol drops the others and counts them; **a dropped quiet changes no state (`mood_quiet_t`, `mood_down_t` unchanged) and is logged at a later tick if the being is still heavy**; with three heavy candidates at one tick the order is deepest `d` first, ties by highest bond to the why's other, then lowest id (an id-1 founder at `d` -0.45 yields to an id-90 child at `d` -0.60); a relief needs the band at or above even and 3 sols; a dropped relief is offered again at the next tick; no relief without a logged quiet for the same being (the T13(3) invariant, checked over 300 sols on three seeds).
20. **Texts.** Every text of `mood.json` rendered with sample names has no digit and no `%`; every `{placeholder}` is filled; no text contains a sign name, a trait word that the panel does not already show, or the words "Deimos", "Moon" or "chart".
21. **Stats and series.** The three series have the length of `pop_by_sol` from creation on a founder world and on a blank world; pop 0 appends 0.0 and divides by nothing; `mean_by_sol[0]` equals the mean of the founders' baselines.
22. **Panel lines.** `BeingPanel.lines` for staged beings: the four spirit sentences (low, heavy, light, bright) with and without a why; **an even being with no why has no spirits line**; the K1 sentence for `friend_count` 0 (exact string), "is close to" for a close pair naming the highest bond, "counts ... as a friend" otherwise; a newborn with a held kin bond shows a friend sentence, not K1; no digit in any output; **never more than four sentences** over a sweep of band x why x nature x company combinations; the nature sentence never appears together with a why sentence.
22b. **Nature reachability.** For each of the 12 signs and both worlds at the shipped data, exactly one of the four nature sentences or none is chosen by the ordered rule: the set of signs with a sentence has size 4 (a data-sanity range of 3 to 5 is asserted so a retune cannot silently empty or flood it); each of the four sentences is chosen by at least one sign and by no more than one; each threshold is at least 0.01 (base) or 0.05 sol (half-life) away from every table value (`balance.nature_margin`), so no sentence is decided by a float tie; a chart-less (neutral) being gets none.
23. **Panel purity.** Calling `BeingPanel.lines` twice leaves the world unchanged (hash of `stats` and beings before and after) and draws nothing from `world.rng`.
24. **Panel and HUD isolation.** The view source reads no mood number: `BeingPanel` uses the band index only to choose a template, and the HUD files do not reference `stats.moods`, `mood`, `mood_base` or `mood_k` (a source scan).
25. **Dormant hash proof.** `tests/mood_hash_proof.gd` on the five seeds at 300 sols with both gains 0.0: dropping `md` reproduces the five Task 5 table hashes; the chain reproduces Task 4, 3, 1 (Q3 decides whether this stays after the 6a close).
26. **Key-path parity** for `mood.json`, both ways, and the data sanity rules of section 14 (each rule checked on the shipped data and shown to fail on one deliberately broken copy through the override seam).
27. **Accessor read-only.** `friend_pairs()` returns the friend pairs (counts equal `stats.relationships.friend_pairs` after a sol reading), flags correct, arrays are copies (mutating them changes nothing in relationships), and the Council's trust, chosen share, lean, stance and `stats.council` on a seeded 120-sol world are identical to the Task 5 values with the Council reading through it.
28. **`friends_of`.** Ascending by other id, flags and bond correct, a dead id returns an empty array, a missing mirror (staged world) falls back to the dictionary.
29. **Relationships feed.** `events` is empty at the start of each tick, has one `grief` entry per mourner of a death, one `friend` entry per grown friendship (kin and crew excluded), one `close`, `lapse` and `lapse_close` entry as in 5.3; `with_friend` is set exactly for both ends of grown pairs holding the friends flag; relationships' own results (pairs, bonds, flags, lines, stats) are identical with the feed code present (the existing 27 relationships tests pass unchanged).
30. **Existing suite.** The whole `tests/run_tests.gd` suite passes with the module on and both gains 0.0; any test changed is listed in the task log with its reason.
31. **Gain-on sanity (not a hash test).** With the shipped gains, a staged colony in permanent hardship (stocks forced low, 100 sols, 60 beings) never leaves `[floor_dev, ceil_dev]`, never exceeds a 1.15 drain factor, never lowers the travel chance below 0.02, and loses no being to a cause other than the staged stocks.
32. **Selection rules (view model, pure).** A hit-test function over staged positions: a colonist outside wins over the building under it; a colonist inside an open roof wins; a colonist inside a closed building cannot be hit and the building tap toggles the roof as today; with a colonist selected, a tap on a building (including its own) only closes the selection and does not toggle any roof; the next tap toggles; tap on empty ground and Esc close; selecting a colonist clears a selected building and the reverse; a log line with `being_id` selects that being; a dead being opens the died beat.
33. **Panel hold and refresh (pure helper `PanelHold`, timestamps as arguments).** At 1000x (many band changes in one real second) the shown sentence changes at most once per `selection.hold_s`; refresh requests are served at most `selection.refresh_hz` times a second; the died beat shows for `selection.died_beat_s` and closes; none of it reads or writes sim state.
34. **Noise-floor control.** With both gains at `calibration.control_gain` (1e-6) the behaviour sites take the mood branch (a stub rng records the argument: it differs from Task 5's by less than 1e-6 x 0.6 and is not equal at a mood of 0.5), still one draw per call; on seed 42 for 300 sols the table hash differs from the dormant hash (a trajectory that diverged), and the control run is byte-identical to a second control run.
35. **Company ceiling and the snowball tripwire.** A staged colony of 20 beings, all friends, together all day for 100 sols: no being's `d` exceeds +0.15 from company; none enters the light band by company alone; the travel-chance term from company stays at or below `travel_coef x 0.15`.
36. **Birth joy reaches light.** A birth push (+0.24) on a being at its baseline takes it to the light band (d >= +0.21 past the hysteresis); the band falls back to even within about a half-life at H 4, and the why "They were there when {other} was born." shows while light.
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
| push.birth_parent | mood | +0.24 | lead, E (rev 2; was 0.08) |
| push.hard_sol / hard_floor_dev | mood per hard sol / deviation | -0.02 / -0.30 | lead, E |
| push.pledge | mood | +0.10 | lead, E (`age_up` / `age_down` removed in rev 2) |
| push.company / company_ceil_dev | mood per tick / deviation | +0.006 / +0.15 | lead, E (ceiling new in rev 2) |
| bands.heavy / low / light / bright / hyst | deviation | -0.40 / -0.18 / +0.18 / +0.40 / 0.03 | lead, E |
| why.min_push / show_dev / fresh_sols | nominal mood / deviation / sols | 0.04 / 0.10 / 1.0 | lead, E (min_push was 0.05 and judged the scaled push; `fresh_sols` new) |
| selection.refresh_hz / hold_s / died_beat_s | per real second / real s / real s | 2 / 1.0 / 2.0 | lead (view only, clarity B1) |
| calibration.control_gain | gain | 1e-6 (1e-4 fallback, 10) | lead (noise-floor control) |
| effects.travel_coef | travel chance per mood unit | 0.0 in step 2, 0.15 from run 1 | lead, E |
| effects.energy_coef | idle drain fraction per mood unit | 0.0 in step 2, 0.25 from run 2 | lead, E |
| effects.clamp_low / clamp_high / travel_floor | mood / mood / chance | -0.60 / +0.40 / 0.02 | lead, E |
| lines.max_per_sol / quiet_cooldown_sols / relief_min_sols | lines / sols / sols | 1 / 20 / 3 | lead, E |
| nature.base_hi / base_lo / slow_halflife / quick_halflife | mood / mood / sols / sols | +0.135 / -0.155 / 7.6 / 1.7 | lead (Q1 option a), E; between table values, one sign each (5.1, 7.1); was 0.15 / -0.17 / 10.0 / 1.7 |
| text.panel.*, text.band.*, text.why.*, text.nature.*, text.lines.* | fixed strings (section 7); `text.clause.*` removed in rev 2 | as written | lead |
| balance.* | targets of section 12 | mean_dev_min 0.02, mean_dev_max 0.25, even_share_min 0.60, even_share_max 0.97, mood_sd_min 0.05, deimos_gap_min 0.08, recovery_ratio_min 2.5, trait_corr_drop_max 0.05, mood_trait_span_max 0.5, death_rise_max 0.25, heavy_share_max 0.30, tick_ms_max 0.5, tick_ms_peak_max 1.5, step_share_max 0.01, lines_per5_max 0.5, log_share_max 0.25, lonely_share_rise_max 0.03, friend_sd_rise_max 0.10, nature_margin_base 0.01, nature_margin_halflife 0.05, nature_signs_min 3, nature_signs_max 5 | lead, E |
**Data sanity rules (test 26):** `floor_dev < 0 < ceil_dev`; `bands.heavy < bands.low < 0 < bands.light < bands.bright`; `bands.hyst` under half of the narrowest band gap; every half-life above 0; `grief_max <= grief_min < 0`; `clamp_low < 0 < clamp_high`; `travel_coef`, `energy_coef` at least 0 and `energy_coef x -clamp_low < 1`; `travel_floor` in [0, 1]; `lines.max_per_sol` at least 1; `nature.base_lo < 0 < nature.base_hi`; the nature thresholds keep the margins and the 3 to 5 sign count of test 22b; `0 < push.company_ceil_dev < bands.light`; `why.min_push` at most the smallest nominal major push (`abs(lapse)`); `push.birth_parent >= bands.light + bands.hyst`; `selection.*` positive; every text key present and free of digits; `balance.mean_dev_min < mean_dev_max`.

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
push.pledge
push.company
push.company_ceil_dev
bands.heavy
bands.low
bands.light
bands.bright
bands.hyst
why.min_push
why.show_dev
why.fresh_sols
selection.refresh_hz
selection.hold_s
selection.died_beat_s
calibration.control_gain
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
text.panel.died
text.band.heavy
text.band.low
text.band.light
text.band.bright
text.why.grief_new
text.why.grief_still
text.why.friend
text.why.close
text.why.lapse
text.why.birth
text.why.hard
text.why.pledge
text.why.company
text.nature.bright
text.nature.heavy
text.nature.slow
text.nature.quick
text.lines.quiet_grief.a
text.lines.quiet_grief.b
text.lines.quiet_lapse.a
text.lines.quiet_lapse.b
text.lines.quiet_hard.a
text.lines.quiet_hard.b
text.lines.quiet.a
text.lines.quiet.b
text.lines.relief.a
text.lines.relief.b
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
balance.log_share_max
balance.lonely_share_rise_max
balance.friend_sd_rise_max
balance.nature_margin_base
balance.nature_margin_halflife
balance.nature_signs_min
balance.nature_signs_max
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
| Q10 Targets, cost, seeds | M1 to M9, T13, section 11, five standard seeds at 300 sols plus the 15 seeds of `r9_seeds` for the guards | lead |
Q4 to Q7 (AI minds, server, culture) are for 6b to 6d. 6b reads `mood_band`, `mood_why` and the temperament sentence inputs only through the pure panel function's inputs; no 6a decision depends on 6b.
### Scope cuts (lead; cut order if time runs out, first cut first)
(`age_up` and `age_down` were cut from the design in revision 2 and are not on this list.)
1. Tap-from-log (7.1 rule 7; view only; the panel is still opened by tapping the colonist).
2. The `pledge` push (the only colony-level lift left).
3. The energy effect (keep the travel effect only; moved up from 7, designer-feel; it also ships off if its run fails).
4. `company` (the only per-pair addition to the relationships tick; first to go if the cost rule of section 11 fires, and the calm-colony texture suffers, said plainly).
5. The nature sentence (Q1).
6. `lapse` and `lapse_close` (keep friend, close, grief, hard sol, birth_parent).
7. The `mood_relief` line (keep the quiet line, a story that begins and does not end; kept this late because designer-clarity and designer-feel both rate the arc above the nature sentence).
8. The travel effect (the slice then has one behaviour and the mood is words only, which contradicts owner decision B; it would go to the owner).
Floor if time runs out (designer-feel): the pushes friend, close, grief, hard_sol and birth_parent. **The one thing to protect:** the grief, quiet, relief arc, then the K1 sentence.
**Cut last**: temperament from the chart, grief, the headroom scale and the hard floor, the K1 sentence and the band sentence in the panel, the dormant hash proof, the baseline-reset record, the no-RNG rule.
**Never cut**: the accessor (6p item 1; the Council refactor), the K1 sentence (6p item 2), T13, the reset record of section 10.
**Out of 6a entirely** (recorded so that no one re-adds them silently):
- mood read by the Council's lean, by birth chance, by mining will, by building choice, or by any survival rule;
- a loneliness term (friendless means sadder, or friendless seeks company): the lonely pull was measured and rejected in Task 5 (zero-friend share rose 0.244 to 0.290; seed 21 went extinct) and R3 passes by 0.043 and 0.023 on two seeds; mood must not reopen K1 by the back door. Positive-only `company` is the compromise: it rewards friendship, never punishes friendlessness;
- negative bonds, dislike, rivals (relationships.md section 19); mood-driven gatherings, mourner behaviour or a muted pose, a mood tint or posture, a mood icon;
- a god lever on mood, a direct "send a dream"; a colony-wide mood word or meter; an AI-written line (6b);
- a per-being history of moods or a memory (6c);
- persistence of mood across a save (no save exists; 6d);
- deferred from the revision 2 reviews, recorded so no one re-adds them silently: a personal `hard_sol` (needs a per-being exposure state that does not exist); scaling friend, close and grief pushes by care or sociability (double-counts the Deimos inner boost, adds tunables, and the trait range was not re-checked); a `season_end` push (+0.04 once after three or more hard sols); an "entering low" log line for slow-Deimos griefs; baseline drift (Q4); camera pan or follow on tap-from-log; any in-play notice of the baseline reset.

## 16. Requests to the assistant designers (the main session runs them)
**DONE (2026-10-08).** One round ran on revision 1; the reviews are saved in `docs/design/reviews/` and every finding is decided in section 17. The requests are kept below as asked, for the record. No second round is planned unless the owner's answers to Q1 to Q4 change the design.
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
Revision 2 folds all three. Reviewers said where their citations were from memory (emergence: Wright citations unchecked; clarity: Cities: Skylines analogies from memory, did not read relationships.md, council.md or the scoping note); no design here rests on those citations. Facts the reviewers marked uncertain were checked in `sim/being.gd`, `sim/ages.gd`, `sim/world.gd`, `sim/council.gd`, `data/beings.json`, `data/persona.json` (5.5 "Verified in code"; 5.1 sign table; 5.3 hard_sol).

**What the check found.** (1) Volunteering and trip departure read no energy; the sleep gate in `decide` (below 28, and 65 at night) comes before them, and an exhausted turn-back (energy below 12, outside) does read energy; so the energy loop is wider than rev 1's single yield figure but bounded, and M4 gains trips and turn-backs. (2) The nature sentences matched 3 signs, "slow" never fired, and thresholds sat on float sums, exactly as all three reviewers said. (3) Hysteresis (0.03) means a +0.20 birth push cannot enter the light band from rest; the push is set to +0.24.

| # | Finding (reviewer) | Decision | Reason and dissent |
| --- | --- | --- | --- |
| EM1, FE1, CL S5 | Nature sentences cover 3 signs; "slow" unreachable; float-equality thresholds (all three, blocking) | **AM** | Re-thresholded in the gaps of the table: 0.135 / -0.155 / 7.6 / 1.7, one sign each, 4 of 12 (5.1, 7.1). Emergence wanted 0.12 / -0.14 / 7.0 and a total of 3 to 5; those values sit on or near table values (0.12 and -0.14 are signs' own bases) and would label 6 to 8 signs. Feel wanted "slow" to cover mutable earth, air and fire; that is 3 signs and would put the panel near a character sheet. Kept at one sign each; the 3 to 5 range is asserted in test 22b and the counts are in probe item 9 |
| EM2 | No noise floor for Q2 | **AM** | Control run at gains 1e-6 added (section 10 step 3, probe item 10, test 34). Changed: a 1e-6 perturbation may not diverge a trajectory (a flip needs a draw within 1e-7), so the control must differ in hash from the dormant run or is raised to 1e-4 on that seed |
| EM3 | Matthew effect: company snowballs friendship | **AM** | `company_ceil_dev` +0.15 (5.3, test 35) and M9 (lonely_share +0.03, friend_count sd +10 percent against the control, R3 attribution). Emergence's alternative (lower `travel_clamp_high` to about 0.15) rejected: it would also cap grief-free joy from friend and birth pushes, which are not the loop |
| EM4 | Check whether volunteering, trip departure, turn-back read energy | **A** | Verified (5.5). M4 gains trips per sol and exhausted turn-backs |
| EM5 | Colony-wide pushes in lockstep; cut age pushes; hard_sol personal | **A** for the cut; **D** for personal | `age_up`, `age_down` removed (feel and emergence agree; clarity silent). Pledge kept (cut 2). Personal hard_sol deferred: stocks are colony-wide and no exposure state exists (5.3). Dissent: emergence wants it now; revisit when 6b gives beings occupations to condition on |
| EM6 | Scale friend, close, grief by care or sociability | **D** | Double-counts the Deimos inner boost on care and sociability, adds three tunables and an M3 interaction, and the panel could not explain it. Revisit after the first calibration shows whether the Deimos gap (M2) is enough |
| EM7, FE2 | Offer quiet and relief by deepest first, not ascending id; and by highest bond | **AM** | Deepest `d` first, then highest bond to the why's other, then id (5.6, test 19). Both reviewers' keys combined |
| EM8 | Report nature counts as a blocking check | **A** | Probe item 9, M8, test 22b |
| EM ideas | `season_end` push; baseline drift; pride from work; needs-feeding mood; visibility probe; god levers later | **D** except visibility probe **A** | season_end deferred (a tenth push, small); baseline drift goes to the owner as Q4 (touches decision C); pride and needs are later slices; visibility probe is probe item 11 (diagnostic); god levers remain "future pushes" |
| EM Q-answers | Q1 (a) after fix; Q2 (a) plus control; Q3 (a), keep through 6b | **A** for Q1, Q2; Q3 stays the owner's | Q3 dissent recorded in Q3 (c): emergence would keep the chain through 6b; the lead keeps (a) as the cheapest honest bridge |
| FE2 | A dropped quiet line sets `mood_down_t`, so "smiling again" can appear unlogged | **A** | A dropped quiet changes no state and is retried at the next tick (5.6); the T13(3) invariant holds by construction |
| FE3 | Some whys cannot appear: lapse -0.05 against min_push 0.05; hard, company, age exempt | **AM** | `min_push` lowered to 0.04 and judged on the **nominal** push (so saturation does not hide a cause); hard_sol, pledge and company exempt from min_push and set only when no why exists and `abs(d) >= 0.10` (5.4) |
| FE4 | Joy is starved: birth_parent about +0.20, close +0.18 if "lit up" never occurs | **AM** | birth_parent +0.24 (hysteresis); close stays +0.15 with a rule: raise to 0.18 once if bright occurs on none of the 15 seeds (probe item 12). "Bright stays rare" is by design |
| FE5 | Energy effect invisible, moves the ages' clauses; cut it early | **AM** | Moved from cut 7 to cut 3, shipped only if run 2 passes the extended M4 and keeps T10 ranges (section 10 step 5). Emergence's concern (threshold loop) is covered by the same rule. Dissent: feel would ship without it unless proven harmless; the lead keeps it built because the loop check is cheap and the travel effect alone has no second channel into sleep rhythm, and the order is the same either way: off first if anything fails |
| FE6 | Omit "much as usual" when even with no why | **A** | 7.1 line 2 |
| FE7 | Two or three wordings by id modulo count; "mourning" first sol, "still" later | **AM** | Two wordings (not three) for the five line texts, variant `(id + sol) mod 2`, so the same being varies between episodes; "mourning" within `why.fresh_sols` (1 sol), then "still mourning" (7.1, 7.2) |
| FE8 | Heavy wording step down; cut age whys first | **A** | Heavy "is struggling." (7.1); age whys gone with the pushes |
| FE answers | Lower the slow half-life ceiling to about 6.5 sols | **R** | M2 needs a wide recovery spread (target ratio 2.5, now 6.5-fold); 10.4 sols is about 83 real minutes at 1x, long but only for the one sign that "takes things to heart". Probe measures it; revisit if the recovery ratio overshoots. One mood line per sol kept (feel agrees); company kept narrowly (cut 4); Q1 (a) |
| CL B1 | Selection unspecified; close rules; priority; 1000x; death; minimal tap-to-focus from log | **AM** | Specified in 7.1 (rules 1 to 7, tests 32 and 33). Modified: the selection outline uses existing primitives and the choice of primitive is the view's; a tap on a building while selected only closes the selection (one tap, one effect); tap-from-log selects and opens the panel without panning the camera. It adds scope against the scoping note's carry-over list, so it is cut 1 |
| CL B2 | The why can mislead: sticky grief and lapse_close; sign agreement; past-tense hard | **A** | 5.4 rewritten (six rules), 7.1 texts, test 13 |
| CL B3 | A "low" being has no log line; narrow the 7.4 claim | **A** (narrow) / **D** (new line) | 7.4 narrowed to heavy. A rare "entering low" line deferred: it adds a third line kind and a third cooldown to a design with a 1-a-sol cap |
| CL B4 | Reset record: pop at 300 and births; cmp for every run; C1 and C4 per seed with old values | **A** | Section 10 step 7 |
| CL S1 | Panel at most 4 sentences; drop nature when a why shows | **A** | 7.1, test 22, probe item 9 |
| CL S2 | Judge combined log share at 0.25 with a drop order; the panel is the only mood context after absence | **AM** | M7 judges 0.25 with a drop order. Changed: clarity's order starts with `mood_relief`; the lead starts with the quiet cooldown (40 sols) and only then thins relief, because relief closes the arc that feel protects |
| CL S3, S4 | Keep relief; company must never replace a grief why | **A** | Cut 7; sticky rule |
| CL S6 | "counts {other} as a friend" | **A** | 7.1 line 5 |
| CL S7 | Boundary p95; five runs on seed 1234 | **A** | Section 11 |
| CL ideas | No in-play reset notice, no tutorial; hard clause not naming the resource | **A** | Nothing announced (7.4); hard text names no resource, `text.clause.*` removed |
| CL answers | Q1 (a) with S5, one sentence, dropped when a why shows; Q2 (a) with a named recalibration sub-task on failure; Q3 (a) | **A** | Q2 text now names the sub-task |
| Lead | Hard-sol dead end: oxygen, food, ice are colony stocks, so "personal" means nothing to condition on | **Note** | See EM5 |

Open questions for the owner after this round: Q1 (recommended (a), option (b) added from feel's idea), Q2, Q3, and a new Q4 (baseline drift, touches decision C; recommended: not in 6a). Reviewer sign-off on revision 2: pending the main session.

## Changelog
- 2026-10-08: revision 1 (lead designer). Draft for the three assistant reviews. Decided in the draft: one mood number with a Deimos (Moon for Earth-born founders) baseline and half-life; eleven pushes with a headroom scale; two behaviours (travel chance gain 0.15, idle drain gain 0.25, both in data); no RNG; text-only panel with the K1 sentence; two rare log lines; dormant-then-live procedure for the baseline reset; accessor and event feed added to relationships, Council moved to the accessor. Owner questions Q1 to Q3 posed. Reviewer sign-off: pending.
- 2026-10-08: revision 2 (lead designer), after the three reviews (section 17). Changes: nature sentences re-thresholded (0.135 / -0.155 / 7.6 / 1.7, four signs, reachability test); why rule rewritten (nominal size, sign agreement, sticky grief and lapse_close, past-tense hard, min_push 0.04, minor pushes exempt); quiet lines retried with no state change, offered deepest first; `age_up` and `age_down` cut (nine pushes); `company` ceiling +0.15 and M9 against a popularity snowball; `birth_parent` +0.24; energy effect to cut 3 and conditional, with trips and turn-backs added to M4 after the energy reads were verified in code; noise-floor control (gains 1e-6) in the reset and probe; selection, close, hold, died-beat and tap-from-log rules (view only); panel at most four sentences, "much as usual" omitted, "struggling", "as a friend"; two wordings per log line; reset record gains pop, births, run-twice cmp on every run, C1/C4 per seed; log share target 0.25; text.clause removed. Open questions now Q1 to Q4 (Q4 baseline drift). Reviewer sign-off: pending.
