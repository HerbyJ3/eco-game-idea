# Spec: relationships and trust (Task 4), driven by personality (revision 1, draft for review)

Source of truth: HANDOFF.md sections 1, 2, 3, 5 (Social), 7, 9, 10. Plan and open questions Q1 to Q10: `docs/tasks/task-4-plan.md`. Format and age facts: `docs/specs/ages.md` (sections 3, 7, 8.2, 12, 18). Sim facts read: `sim/persona.gd`, `sim/being.gd`, `sim/world.gd` (phase order of `step()`), `sim/colony.gd` (birth warmth), `data/persona.json`, `data/beings.json`, `view/main.gd`, `view/model/view_model.gd` (`_talk_flags`).
Locked decisions respected: hidden birth chart (the layer reads only the six traits that `Persona` already derives; no chart, sign or trait is ever shown); ages not meters (no bond value, share, count or bar reaches the player); influence-only god (no power reads or writes a bond; section 9); per-being energy, power as a budget and ice-as-pressure are untouched (the layer writes no colony, being, building or resource state).
Tunables live in `data/relationships.json` (new). No tunable in the new module `sim/relationships.gd`. This spec describes behaviour and numbers only, no code. Every number marked E is an estimate until the calibration probe (section 13) measures it.

**Review status: the three assistant reviews (emergence, feel, clarity) have not been run yet.** Section 16 lists what each reviewer is asked to look at; section 17 is the empty review record. Owner questions are in section 18.

## 0. The design in one paragraph
Every pair of beings that spends waking hours in the same room, or a shift on the same site or ice field, grows a private **bond**. Warm, nurturing beings bond faster; beings whose rhythms clash (one restless, one steady) bond slower unless one of them is curious; restless beings let bonds fade faster when apart, and close bonds fade slowly. Above a line a bond is a **friendship**; higher still it is **close**. **Trust** is not a second number per pair: it is how far the web of friendships reaches across the colony, read once a sol and handed to Task 5 (Council). The player never sees a number. They see a few named lines in the log ("Kiro-12 and Vana-3 have become friends.", "Vana-3 is grieving for Kiro-12."), and, in an opened roof, friends talk to each other while strangers stand quietly. In the shipped values relationships change nothing about what beings do, so the five Task 1 table hashes and the Task 3 age crossings stay identical. One behaviour lever (friends draw each other between rooms) is built, shipped at 0, and measured, so the owner can switch it on knowing what it does (section 18, O1).

## 1. Purpose
HANDOFF 7 says the colony leaves Settlement "when relationships and trust form", and HANDOFF 5 says sociable beings seek each other out. Today the sim has no notion of who knows whom: the talk pose in the view picks any two beings standing near each other. Task 4 gives every being a private social life that comes from its personality and its days, tells the player about it in the colony's voice when something worth telling happens, and leaves a per-sol reading of colony trust for Task 5 to judge. It is a record of what the people already did, in the same spirit as ages: nothing counts toward anything.

## 2. Terms
| Term | Meaning |
| --- | --- |
| bond | private float in [0, 1] per unordered pair of living beings; absent means 0 |
| together (room) | both beings `is_inside()`, neither in state `sleep`, same `building_id`, at a tick |
| together (work) | both in state `work` with `job` equal to the current site, or both in state `mining` with the same `mine.site`, at a tick |
| friends | pair flag with hysteresis: set when bond >= `lines.friend`, cleared when bond < `lines.friend_drop` |
| close | pair flag with hysteresis: set when bond >= `lines.close`, cleared when bond < `lines.close_drop` |
| was_close | pair flag, set the first time `close` is set, never cleared (for the drift line) |
| kin | pair flag: the bond was seeded at birth between a newborn and its recorded parent (`parent_id`) |
| crew | pair flag: the bond was seeded at landing between two founders |
| lonely | a living being with no `friends` pair |
| web | the graph of living beings joined by `friends` pairs |
| trust (colony) | the share of living beings in the largest connected part of the web (`web_share`), read once a sol |

## 3. State (all new, all inside `Relationships`, owned by `SimWorld` as `world.relationships`)
| Field | Meaning |
| --- | --- |
| `pairs` | map from a pair key (the two ids, lower first) to `{lo, hi, bond, friends, close, was_close, kin, crew}` |
| `known` | set of being ids alive at the previous tick (to detect births and deaths between ticks) |
| `found_friend` | set of being ids that have had at least one grown (non-seeded) friendship; drives the friend line |
| `acc_h` | hours since the last tick (accumulator, `STEP_EPS` slack, like `_build_acc`) |
| `lines_sol`, `lines_this_sol` | the elapsed sol of the current cap count, and how many capped lines were logged in it |
| `present` | snapshot from the last tick: building id to ascending list of awake-inside being ids (read by the friend pull, section 8; never by the view) |
| `last_tick_ms` | wall time of the last tick, for the probe only; never in stats, log or any hashed state |
`Being` gains **no field**. `stats` gains one key, `stats.relationships` (section 10.2). `SimWorld` gains `relationships`, `relationships_enabled` (default true; false skips both hooks, test seam), the hook calls, and the creation call. Nothing else in `sim/` changes, except the optional friend-pull term (section 8), which reads `present` and is exactly neutral at its shipped value.

## 4. Where it runs
- **Creation**: in `SimWorld._init`, after `ages.begin(...)` on both branches: `relationships.begin(self, founders_world)`. A founder world seeds the crew bonds (5.4) and fills `known`; a blank world fills `known` from whatever beings exist (none at creation) and seeds nothing.
- **Tick (phase 11b)**: in `step()`, after `_sample_being_stats()` and before the `if _sol_started:` block: `relationships.on_step(self, fixed_step)`. It adds `fixed_step` to `acc_h` and runs a tick when `acc_h >= tick_h - STEP_EPS`, then sets `acc_h` to 0. With `tick_h` 1.0 and `fixed_step` 0.05 that is every 20th step. All phases that move, kill or create beings (6, 7, 9, 10) have run, so the tick reads settled state.
- **Sol reading**: inside the `if _sol_started:` block, after `ages.on_sol(self)`: `relationships.on_sol(self)` (section 7). It runs after ages so `age_history` cannot see it, and ages never reads it (section 11).
- No wall clock (except the probe-only `last_tick_ms`), no read of the log, no write to colony, buildings, beings, resources, powers, or the RNG.

## 5. Rules (one tick, in this order)
### 5.1 Deaths
For each id in `known` that is not a living being, in ascending id: find its pairs. If its highest bond with a living being is >= `lines.friend` (ties: lowest living id), log the grief line (5.6) naming that being. Remove every pair that contains the dead id. Remove the id from `known` and `found_friend`.
### 5.2 Births
For each living being not in `known`, in ascending id: add it to `known`. If it has `parent_id` != 0 and that parent is alive, create the pair with `bond = seed.kin`, `kin = true`, and set the flags from the lines (so `friends` is true at the shipped 0.45). No log line. A being born and dead between two ticks is never seen (no pair, no grief); accepted.
Note (ages.md section 3): the recorded parent is the being `rng.pick(here)` chose, and it can itself be a child. The text never says "mother", "father" or "parent"; kin is "who was there when they were born", nothing more.
### 5.3 Growth
Build `present`: for each living being that is `is_inside()` and not `sleep`, append its id to the list of its `building_id`, in ascending being id; buildings in ascending id. Then:
- **Room**: for each building with at least 2 ids, for each pair (i < j in the list): `bond += room_rate x tick_h x room_factor x affinity x (1 - bond)`.
- **Work**: the crew of the current site (state `work`, `job` == site) and each mining field's crew (state `mining`, grouped by `mine.site`; fields in the order of `resources.ice_fields` then `resources.pits`; beings in ascending id): for each pair, `bond += work_rate x tick_h x affinity x (1 - bond)`. Warmth does not enter: shared hard work builds trust between any two people.
- A pair can grow at most once per tick (a pair cannot be in a room and on a site at once, so this holds by construction; the test checks it).
- Every grown pair is marked `grown_this_tick`. A missing pair is created at bond 0 before growing.
**Personality terms** (traits from `persona.traits`, each in [0, 1]):
- `warmth(x) = (sociability_x + care_x) / 2` (the same two traits that make a habitat fertile in `Colony.birth_chance`).
- `room_factor = grow.warmth_base + (warmth(i) + warmth(j)) / 2`.
- `tempo(x) = restless_x - steady_x` (in [-1, 1]).
- `gap = abs(tempo(i) - tempo(j)) x (1 - affinity.curiosity_soften x max(curiosity_i, curiosity_j))`.
- `affinity = clamp(1 - affinity.tempo_gap_coef x gap, affinity.floor, 1)`.
So like rhythms bond easily, clashing rhythms bond slowly, and one curious being in the pair halves the clash at the shipped 0.5. Drive does not enter the formula; it enters through the days (driven beings are on the site together more often).
### 5.4 Founder crew (creation only)
Every pair of the 7 founders starts at `seed.crew` (0.35, just over the friend line), `crew = true`, `friends = true`. They trained and flew together; whether they stay friends depends on whether they keep sharing rooms. A blank world seeds nothing. (Owner question O4.)
### 5.5 Decay, forgetting, flags
For every pair not grown this tick, in ascending key: `bond -= decay.per_h x tick_h x (decay.restless_base + (restless_i + restless_j) / 2) x (decay.close_hold if close else 1)`, floored at 0. Then for every pair touched (grown or decayed): if bond < `lines.forget_below` and the pair is neither `friends` nor `close`, remove it. Then update flags with hysteresis and collect crossing events:
- `friends` false to true: event `friends` (5.6) if at least one of the two is not in `found_friend` and the pair is neither `kin` nor `crew`; both ids join `found_friend` in that case.
- `close` false to true: event `close` if the pair was never `was_close` and neither being has any other `close` pair; set `was_close`.
- `friends` true to false on a `was_close` pair: event `drifted`.
- Other crossings change flags and the run-wide counts (10.2) only.
### 5.6 Log lines (one fixed text per kind, no random rotation, names only, no numbers)
Kinds, in the order they are emitted within a tick: `grief` (ascending dead id), then `friends`, `close`, `drifted` (each in ascending pair key). Two-name lines put the lower id first; the grief line puts the mourner first.
| Kind | Key | Text |
| --- | --- | --- |
| `friends` | `text.friends` | "{a} and {b} have become friends." |
| `close` | `text.close` | "{a} and {b} have grown close." |
| `drifted` | `text.drifted` | "{a} and {b} have drifted apart." |
| `grief` | `text.grief` | "{a} is grieving for {b}." |
Cap: `friends`, `close` and `drifted` lines share `log.max_lines_per_sol` (3) per elapsed sol (counted from `world.sol()` at the tick). Over the cap the event still counts in stats (`lines_capped`), is not logged, and is not retried. `grief` is never capped: at most one per death, and deaths are already one line each. Each logged line carries `being_id` (first name) and `other_id` (second name), so a later view can find the beings.
Why so few lines: at 160 beings and roughly one birth a sol, newborns' first friendships alone give about one line a sol (E). Friendships between beings who already have friends are not news; first friendships, first close bonds, the end of a close bond and grief are.

## 6. Numbers, and what they imply (all E)
Tick of 1 h; a pair "together" for h awake hours per sol and apart for the other 24.66 - h hours.
- Typical pair: warmth 0.4 each, affinity 0.8, restless 0.4 each. Growth constant per hour together: 0.008 x 0.6 x 0.8 = 0.00384. Decay per hour apart: 0.0005 x 0.9 = 0.00045.
- Hours together per sol needed to reach a friendship at all (balance point bond = 0.30): 0.00384 x 0.7 x h = 0.00045 x (24.66 - h), so h is about 3.5. Warm, like-rhythmed pair (warmth 0.6, affinity 1.0): about 2.0 h. Cold, clashing pair (warmth 0.25, affinity 0.5): about 7.4 h. Personality therefore decides who becomes friends at the same exposure, which is the point.
- Roommates who share about 10 awake hours a sol settle near bond 0.8 (close). A pair sharing one hour a sol never bonds.
- From a fresh pair, 10 h a sol together, a typical pair crosses the friend line after about 9 sols and the close line after about 25 sols (net of decay, roughly; the probe measures it).
- A friendship at 0.30 left alone falls below the drop line 0.15 after about 333 h, about 13.5 sols; a close bond at 0.60 decays at a quarter of that rate and needs about 3,600 h (146 sols) to fall to 0.40 and then the ordinary rate to fall to 0.15. Founder crews who never share a room lose the friend flag after about 18 sols of separation (0.35 to 0.15 = 0.20 / 0.00045 = 444 h).
- These figures assume the 1-h sample is representative of the hour; it is a sample, not an integral. The probe compares it with a per-step count on one seed (section 13).

## 7. The trust reading (once a sol)
At each sol boundary, `on_sol(world)`:
1. Build the web from `friends` pairs; find connected parts with a union-find over ascending ids.
2. `web_share = size of the largest part / pop`; `lonely_share = lonely beings / pop`; `friends_mean = 2 x friend pairs / pop`. At pop 0 all three are 0.0.
3. Append `web_share` to `stats.relationships.web_by_sol` and `lonely_share` to `lonely_by_sol` (one entry per boundary, so `len == sols elapsed`, like `pop_by_sol`), and store the three latest values.
Why largest part: a colony where everyone has a friend but the friendships form two islands is not a colony that trusts itself; Task 5 can read islands as the seed of factions (HANDOFF 7, Council: "factions by personality"). This spec does not decide what share counts as "trust has formed"; Task 5 owns that rule and reads the per-sol lists with its own window, as it reads `age_history`.

## 8. Behaviour effect: friends draw each other (built, shipped off)
In `Being._restless_travel`, the weight of each neighbour building becomes
`v = room_pull.floor + pow(trait x mult, exponent) + effects.friend_pull x min(friends_there, effects.friend_pull_cap)`
where `friends_there` is the number of ids in `world.relationships.present[neighbour id]` that are `friends` with this being (the snapshot is at most one tick, 1 h, old; it is deterministic).
- Shipped value `effects.friend_pull` = **0.0**. When it is 0.0, `friends_there` is not computed and the term is not added, so the weights, the draws and every decision are bit-identical to Task 3 (also true numerically, since adding 0.0 is exact; skipping is for cost). Hashes unchanged.
- Probe value `balance.probe_friend_pull` = 0.25 (E), cap 3: at the cap a room gains 0.75, against a floor of 0.15 and a trait term of 0 to about 0.5, so friends matter about as much as personality when choosing the next room. Same number and order of draws; different outcomes; the five table hashes change.
- The loop it creates: friends gather, gathering grows bonds, bonds draw more gathering. Bounded by saturation (1 - bond), the cap, the unchanged chance to travel at all, sleep, work and mining, which pull beings apart every sol. Expected story: cliques by temperament, curious beings as bridges, which is what Task 5's factions need. Risk: the web fragments into islands and lonely newborns stay lonely. The probe measures both before the owner decides (O1).

## 9. The god's influence (no new power)
Nothing the god does writes a bond. The god shapes who meets whom: Inspire puts a new room where beings will gather, Grace brings newborns into a particular habitat, Good fortune keeps rooms lit. Bonds follow from those days. A direct social power (gather, rumor, a shared dream; HANDOFF 4, future ideas) is out of scope for Task 4 and would read this layer later.

## 10. What the player sees, and stats
### 10.1 Player-facing (view; sim read-only)
- **Log lines** of 5.6, in the existing log panel. No number, no share, no count, no trait word, no sign.
- **Friends talk, strangers do not.** In an opened roof, the existing talk pose (`view_model._talk_flags`: two awake jumpsuit beings pausing within `interior.talk_radius_px`) is shown only when the two are `friends` (read through a read-only query `world.relationships.are_friends(a, b)`). Other near pairs stand idle-front. Controlled by `art.interior.talk_friends_only` (true). This is the visible effect of the hidden layer; it needs no art and no HUD line, and the founders, who start as a crew, talk from the first sol.
- No new HUD line, no colony-wide word, no meter. HUD room at 720p is already tight (ages.md 18, item 7). Owner question O3 covers adding more.
- No new art; texture memory is 47.1 of 48 MB (Q10).
### 10.2 Stats: `stats.relationships` (run-wide, never windowed, never reset; never shown)
| Key | Definition |
| --- | --- |
| `friendships_formed` | `friends` false-to-true crossings of grown pairs (not seeds) |
| `close_formed` | `close` false-to-true crossings |
| `drifted` | `friends` true-to-false on `was_close` pairs |
| `lines` | `{friends, close, drifted, grief}` logged line counts |
| `lines_capped` | events not logged because of the cap |
| `first_friendship_sol` | elapsed sol of the first grown friendship, null before |
| `first_mars_born_friendship_sol` | elapsed sol of the first grown friendship involving a Mars-born being, null before |
| `pairs`, `friend_pairs`, `close_pairs` | current counts, refreshed at each sol reading |
| `web_share`, `lonely_share`, `friends_mean` | latest sol reading |
| `web_by_sol`, `lonely_by_sol` | one float per sol boundary (section 7) |
Not in stats: bond values, `present`, `known`, tick timings. The dictionary is created with the other stats in `_init_stats` (zeros, nulls, empty lists).

## 11. Ages: untouched
Ages never read `world.relationships` or `stats.relationships`; relationships never read `world.ages` or write `age_history`. The Settlement entry and exit rules, the `unrest` cause group and every `ages.json` value are unchanged, so the Task 3 calibration is not reopened: the balance run must show the same settlement and fall-back sols (67, 58, 54, 65, 53; fall-backs 42 at 213, 99 at 174). The HANDOFF 7 line "relationships and trust form" is read as the condition for **leaving Settlement toward Council**, which is Task 5's rule to write from `web_by_sol` (owner question O2).

## 12. Randomness and the Task 1 hashes, per mechanic
No mechanic draws from `SimRng` or any other random source. Every order is fixed (ascending ids, list order of sites, ascending pair keys).
| Mechanic | Draws | Writes outside the module | Effect on the five Task 1 hashes |
| --- | --- | --- | --- |
| Crew seed at creation (5.4) | none | none | none |
| Kin seed (5.2) | none | none | none |
| Room and work growth (5.3) | none | none | none |
| Decay, forgetting, flags (5.5) | none | none | none |
| Death handling and grief (5.1) | none | log only | none (nothing in the sim reads the log; ages.md 4.1) |
| Log lines and cap (5.6) | none | log only | none; earlier log eviction at the 500 cap is display-only |
| Sol reading (7) | none | `stats.relationships` | none (new key, not in the table's old columns) |
| Friend pull at 0.0 (8, shipped) | none added | none | none: weights identical, term skipped |
| Friend pull above 0.0 (probe or owner) | same draw count, different outcomes | being behaviour | **changes all five hashes**; needs the owner's baseline reset (O1) |
| Talk pose for friends (10.1) | view RNG only, unchanged | none (view) | none |
Proof, as in ages.md 12: the balance table gains one trailing column `web` (2 decimals, the latest `web_share`) after `age`. Removing the last two fields reproduces the five Task 1 hashes 02032b23..., 830c7d0c..., 0e3e83a7..., bca6eb2c..., 2645033a...; removing only `web` reproduces the Task 3 table hashes recorded in `docs/balance/task-3-log.md` (42 da166c4f8b202820, 7 30c53f90949d979b, 99 54ad1e15b934bf9a, 1234 7052c92936a75157, 2026 67e3dcf057200eb9), which also proves the age crossings are unchanged. Plus the purity test (14, test 13).

## 13. Calibration probe (`tools/relationships_probe.gd`, read-only)
Runs the real module on seeds 42, 7, 99, 1234, 2026 to sol 300, twice: shipped (`friend_pull` 0.0) and with `probe_friend_pull` (0.25), the second run by the data override seam, never by editing data. Writes `docs/balance/task-4-calibration.md` with, per seed and run:
1. `first_friendship_sol`, `first_mars_born_friendship_sol`; counts of each line kind and of capped events; lines per sol, max and mean.
2. `web_share`, `lonely_share`, `friends_mean` at sols 30, 60, 100, 150, 200, 300; the number of web parts of size 3 or more at sol 300.
3. Personality check: mean friend count of the warmest third against the coldest third (by `warmth`) at sol 300; mean bond age of friendships by mean pair `restless` (top third against bottom third).
4. Hours together per sol for friend pairs against non-friend pairs (median), to check the section 6 arithmetic.
5. The 1-h sample against a per-step count of together hours on seed 42 (sols 1 to 60): relative difference per pair, median and 90th percentile.
6. Tick cost: median and maximum microseconds per tick at pop around 70 and around 160, and stored pair count; step cost with and without the module.
7. With the pull on: the same, plus age settlement and fall-back sols, population at 300, deaths by cause, and the table hash differences, so the owner sees the full cost of switching it on.
Any recalibration edits `data/relationships.json` only, one key per run, chosen by the lead. Targets for the probe to confirm (E): first grown friendship before sol 20; first Mars-born friendship within 15 sols of the first birth; `lonely_share` at sol 300 between 0.05 and 0.5; `friends_mean` at sol 300 between 1 and 12 (below 1, nobody has a life; above 12, friendship means nothing); capped events under a third of all capped-kind events; warmest third has more friends than the coldest third on every seed; tick under 1 ms median at pop 160.

## 14. Tests (`tests/test_relationships.gd`, written first, red; no test with zero checks)
Staging: blank world, reactor, two habitats, workshop and green room built; beings added with `add_being`, then traits overwritten per test; state, `building_id`, `job`, `mine` set directly; ticks driven with `relationships.on_step(world, tick_h)` or by stepping 20 steps.
1. Room growth recurrence: two awake beings in one habitat, 10 ticks; bond equals the recurrence `b = b + k x (1 - b)` with `k` computed in the test from data and traits (tolerance 1e-12), from 0.
2. Personality: warm pair > cold pair after 10 ticks; equal-tempo pair > clashing pair; a clashing pair with one curiosity 1.0 is at exactly the softened affinity; a fully clashing pair is held at `affinity.floor`.
3. Not together: different buildings; one asleep; one in `transit`; one outside: no growth and decay applies.
4. Work: two `work` beings on the site grow at `work_rate` with warmth not entering (two cold beings grow as fast as two warm ones); two miners on the same field grow, on different fields do not; a pair never grows twice in a tick.
5. Decay: restless pair loses more per tick than a steady pair by the formula; a close pair loses `close_hold` of the open rate; a non-flagged pair under `forget_below` is removed.
6. Hysteresis: friends set at exactly `lines.friend`, kept at 0.20, cleared at just under 0.15; close set at 0.60, kept at 0.45, cleared under 0.40.
7. Crew: a founder world has 21 pairs at `seed.crew`, all `friends` and `crew`, and logs no relationship line at creation; a blank world has no pairs.
8. Kin: a newborn with a living parent gets the kin pair at the next tick, no line; a dead parent or `parent_id` 0 gives none.
9. Death: pairs of the dead are removed at the next tick; grief names the living being with the highest bond (tie: lowest id); no grief when the highest bond is under the friend line; grief lines are never capped.
10. Lines: `friends` only for a grown pair where one has not found a friend; never for kin or crew; `close` only for the first close of both; `drifted` only for `was_close`; the shared cap of 3 per sol holds and `lines_capped` counts the rest; the cap resets at the next sol; name order as 5.6; every text from data, rendered with sample names, has no digit and no `%`.
11. Sol reading: staged webs (chain of 5, two islands of 3 and 4, 2 lonely) give the exact `web_share`, `lonely_share`, `friends_mean`; one entry per boundary; pop 0 appends 0.0 and divides by nothing.
12. Friend pull: at 0.0 the weights and the next 1,000 draws equal those of a world with the module disabled; at 0.25 a neighbour's weight rises by exactly 0.25 per friend up to the cap.
13. Purity, seed 42, 10 sols: worlds with `relationships_enabled` true and false have equal old `stats` keys, equal beings (id, building, state, energy), equal stocks, and equal next 1,000 `rng` draws; two same-seed worlds have identical `pairs` and `stats.relationships`.
14. Tick timing: one tick every 20 steps; after N whole sols the tick count is floor(N x sol_h / tick_h) within one.
15. Key-path parity for `relationships.json` (section 15), both ways.
16. View: `_talk_flags` gives the talk pose to a friend pair and not to a non-friend pair at the same distance; with `talk_friends_only` false the old behaviour returns; the HUD source reads no bond value.

Balance (`tests/balance_lib.gd`): **T11** per seed at 300 sols, from `stats.relationships` only. Judged: (1) `len(web_by_sol) == len(lonely_by_sol) ==` boundaries seen; (2) `lonely_share <= balance.lonely_share_max`; (3) `friends_mean` in `balance.friends_mean_min` to `friends_mean_max`; (4) `first_friendship_sol` not null. Reported: everything of section 13 items 1 to 3. T1 to T10 unchanged and must pass with the same values as Task 3.

## 15. Tunables (`data/relationships.json`; E = estimate for the probe)
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| relationships.tick_h | sim hours | 1.0 | lead, E |
| relationships.grow.room_rate | per hour together | 0.008 | lead, E |
| relationships.grow.warmth_base | added to pair warmth | 0.2 | lead, E |
| relationships.grow.work_rate | per hour together | 0.03 | lead, E |
| relationships.affinity.tempo_gap_coef | per unit of tempo gap | 0.6 | lead, E |
| relationships.affinity.curiosity_soften | fraction of gap removed at curiosity 1 | 0.5 | lead, E |
| relationships.affinity.floor | affinity | 0.3 | lead, E |
| relationships.decay.per_h | bond per hour apart | 0.0005 | lead, E |
| relationships.decay.restless_base | added to pair restless | 0.5 | lead, E |
| relationships.decay.close_hold | multiplier while close | 0.25 | lead, E |
| relationships.lines.friend / friend_drop | bond | 0.30 / 0.15 | lead, E |
| relationships.lines.close / close_drop | bond | 0.60 / 0.40 | lead, E |
| relationships.lines.forget_below | bond | 0.01 | lead |
| relationships.seed.crew | bond | 0.35 | lead (O4) |
| relationships.seed.kin | bond | 0.45 | lead, E |
| relationships.log.max_lines_per_sol | lines | 3 | lead, E |
| relationships.text.friends / close / drifted / grief | text with {a}, {b} | section 5.6 | lead |
| relationships.effects.friend_pull | added room weight per friend | 0.0 (shipped) | owner (O1) |
| relationships.effects.friend_pull_cap | friends | 3 | lead, E |
| relationships.balance.probe_friend_pull | added room weight per friend | 0.25 | lead, E |
| relationships.balance.lonely_share_max | share of living | 0.5 | lead, E |
| relationships.balance.friends_mean_min / friends_mean_max | friends per being | 1.0 / 12.0 | lead, E |
| art.interior.talk_friends_only | bool | true | lead (view) |
Reused, not duplicated: `persona.traits` (sociability, care, restless, steady, curiosity), `room_pull.*` (beings.json), `Being.parent_id`, `SimWorld.STEP_EPS`. Not data: the flag names, line kinds and their emission order, the pair-key rule, "pop 0 reads 0.0". The `balance.*` keys are read by the probe and `balance_lib.gd` only; the `art.*` key by the view only.

### Key-path list (machine-readable; one leaf per line)
Same rules as ages.md 13. The `art.` line is an existence check only.
```keys:
relationships.tick_h
relationships.grow.room_rate
relationships.grow.warmth_base
relationships.grow.work_rate
relationships.affinity.tempo_gap_coef
relationships.affinity.curiosity_soften
relationships.affinity.floor
relationships.decay.per_h
relationships.decay.restless_base
relationships.decay.close_hold
relationships.lines.friend
relationships.lines.friend_drop
relationships.lines.close
relationships.lines.close_drop
relationships.lines.forget_below
relationships.seed.crew
relationships.seed.kin
relationships.log.max_lines_per_sol
relationships.text.friends
relationships.text.close
relationships.text.drifted
relationships.text.grief
relationships.effects.friend_pull
relationships.effects.friend_pull_cap
relationships.balance.probe_friend_pull
relationships.balance.lonely_share_max
relationships.balance.friends_mean_min
relationships.balance.friends_mean_max
art.interior.talk_friends_only
```
`SimData.relationships()` is the accessor; `data_hash` in `tests/balance_lib.gd` adds `relationships`. Data sanity checked by test 15: `friend_drop < friend < close_drop < close`; `forget_below < friend_drop`; `0 < affinity.floor <= 1`; `seed.crew >= lines.friend`.

### Edge cases
- Pop 0 or 1: no pairs grow; the sol reading appends 0.0 (pop 0) or the true shares (pop 1: web 1.0, lonely 1.0).
- A being dies on the tick step: handled at that tick (5.1 runs first).
- A building goes offline: beings inside still count as together (the room is dark, not empty).
- A construction crew finishing: crew members `enter` the new building and become room-together there at the next tick.
- Log eviction at 500 entries changes no bond and no stat.
- Ids never repeat, so a pair key never refers to two different pairs.
- Cost: pairs per tick are the sum over buildings of k(k-1)/2 for awake-inside counts k; one crowded building of 40 gives 780 pair updates, still small. Stored pairs grow with the number of people each being has shared a room with; the forget rule keeps them bounded. Estimated under 1 ms per tick at pop 160 (once per 20 steps, under 2% of a 2.6 ms step); the probe measures it.

## 16. Requests to the assistant designers (for the main session to run)
- **designer-emergence**: Is "record now, pull built at 0" the right first step, or is a relationship layer with no effect a dead end? Is the personality model (warmth, tempo clash, curiosity bridging, restless decay) rich enough to produce different stories per seed, or will every colony look the same? What is the worst loop if `friend_pull` goes on? Is the largest-web-part share the right trust reading for Task 5?
- **designer-feel**: Do the four log lines and their caps give the colony warmth without spam at 12 and at 160 beings? Founder crew bonded at landing: right? Is the grief line right in tone, and should kin be visible in words? Scope: what to cut first.
- **designer-clarity**: Can a player learn from the log lines and the friends-only talk pose that personality drives friendship, with the chart hidden and no being selection? Is "no HUD line" right, or is one word needed? Does the talk-pose change risk reading as a bug?

## 17. Design review record
Pending. Reviews to be saved as `docs/design/reviews/relationships-emergence.md`, `relationships-feel.md`, `relationships-clarity.md` and folded in as revision 2 (A adopted, AM adopted modified, D deferred, R rejected), with the dissent recorded.

## 18. Open for the owner
Four questions. Each lists the recommendation first, with its cost and the facts behind it.

**O1. Do relationships change what beings do in Task 4?** (plan Q2, Q6)
- (a) **Recommended: record now, build the "friends draw each other" lever shipped at 0, measure it, decide after the probe.** Cost: for now bonds change only words and the talk pose; the colony behaves exactly as in Task 3. Facts: the five Task 1 hashes and the Task 3 age sols stay identical; the probe reports the pull's full effect (web shape, ages, population, deaths, hashes) on all five seeds, so turning it on later is one data value plus a recorded baseline reset.
- (b) Record only, no lever. Cost: the cheapest; the first behaviour effect waits for Task 5 or later and will need its own measurement then.
- (c) Lever on now (0.25) with a baseline reset. Cost: all five hashes change, the Task 3 calibration (settlement 67, 58, 54, 65, 53; fall-backs on 42 and 99) must be re-measured and may move, and we switch it on before seeing what it does.

**O2. How does trust connect to the ages?** (plan Q1)
- (a) **Recommended: ages untouched; trust is offered to Task 5 as the way out of Settlement toward Council** (HANDOFF 7: Settlement moves on "when relationships and trust form"). Cost: in Task 4 trust has no visible consequence beyond the lines. Facts: no Task 3 number reopens; Task 5 reads `web_by_sol` and `lonely_by_sol` with its own window, as it reads `age_history`.
- (b) Add a Settlement entry clause ("most of the colony is in one web"). Cost: reopens Task 3 calibration; with the founders bonded at landing it passes almost at once and only bites if newborns stay lonely, so it would rarely change anything.
- (c) Add "the colony has split apart" as a fall-back cause (the reserved `unrest` group). Cost: a new exit path, new calibration, and a social cause next to ice and air.

**O3. What does the player see?** (plan Q7, Q10)
- (a) **Recommended: named log lines (become friends, grown close, drifted apart, grieving), capped at 3 a sol except grief, and friends-only talk in opened roofs. No HUD line, no art.** Cost: a player at high speed may miss most lines; there is no way to ask "who are this being's friends". Facts: HUD is at its 720p limit; texture memory 47.1 of 48 MB.
- (b) Log lines only (talk pose unchanged, any two beings). Cost: the hidden layer has no visible effect in the world itself.
- (c) (a) plus one word on the colony block ("People: close-knit / friendly / scattered"). Cost: a word that steps through levels reads as a coarse meter, which the ages rule avoids; one more HUD line at 720p.

**O4. Do the founders start as friends?**
- (a) **Recommended: yes, as a crew just over the friend line (0.35).** They will drift if they stop sharing rooms (about 18 sols apart), which gives early "drifted apart" moments only if they were ever close, so mostly silent. Cost: the web is whole at landing, and trust is about whether newcomers join it.
- (b) Strangers (0). Cost: the colony's first lines are founders' friendships, but seven people who crossed space together start as strangers, and the first sols read colder.
- (c) Housemates only (founders who start in the same building: the 4 in the habitat, the 2 in the reactor). Cost: the workshop founder starts alone; more seeded structure, less emergence.

## Changelog
- 2026-10-06: revision 1 (lead designer). Draft for the three assistant reviews; owner questions O1 to O4. Reviewer sign-off: pending.
