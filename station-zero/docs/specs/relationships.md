# Spec: relationships and trust (Task 4), driven by personality (revision 2, reviews folded in)

Source of truth: HANDOFF.md sections 1, 2, 3, 5 (Social), 7, 9, 10. Plan and open questions Q1 to Q10: `docs/tasks/task-4-plan.md`. Format and age facts: `docs/specs/ages.md` (sections 3, 7, 8.2, 12, 18). Sim facts read: `sim/persona.gd`, `sim/being.gd`, `sim/world.gd` (phase order of `step()`, `_log` with FIFO eviction at `colony.log_cap` 500), `sim/resources.gd` (site `kind` "ice" or "pit"), `sim/colony.gd` (birth warmth), `data/persona.json`, `data/beings.json`, `data/buildings.json` (kinds reactor, habitat, workshop, green_room, archive, comms), `view/main.gd`, `view/model/view_model.gd` (`_talk_flags`).
Locked decisions respected: hidden birth chart (the layer reads only the six traits that `Persona` already derives; no chart, sign or trait is ever shown); ages not meters (no bond value, share, count or bar reaches the player); influence-only god (no power reads or writes a bond; section 9); per-being energy, power as a budget and ice-as-pressure are untouched (the layer writes no colony, being, building or resource state).
Tunables live in `data/relationships.json` (new) and two view keys in `data/art.json`. No tunable in the new module `sim/relationships.gd`. This spec describes behaviour and numbers only, no code. Every number marked E is an estimate until the calibration probe (section 13) measures it.

**Review status:** the three assistant reviews (emergence, feel, clarity) are folded in as revision 2. Section 17 is the record (adopted, adopted modified, deferred, rejected) with the dissent. Four owner questions remain (section 18).

## 0. The design in one paragraph
Every pair of beings that spends waking hours in the same room, or a shift on the same site or ice field, grows a private **bond**. Warm, nurturing beings bond faster; beings whose rhythms clash (one restless, one steady) bond slower unless one of them is curious; restless beings let bonds fade faster when apart, and close bonds fade slowly. Above a line a bond is a **friendship**; higher still it is **close**. **Trust** is not a second number per pair: it is how far the web of friendships reaches across the colony, read once a sol and handed to Task 5 (Council). The player never sees a number. They see a few named lines in the log that say where it happened ("Vana-3 has found a friend in Kiro-12. They keep company in the green room.", "Vana-3 is mourning Kiro-12."), and, in an opened roof, friends talk to each other for as long as they stand together while strangers only exchange a brief word now and then. In the shipped values relationships change nothing about what beings do, so the five Task 1 table hashes and the Task 3 age crossings stay identical. One behaviour lever (friends draw each other between rooms, and lonely beings are drawn to company) is built, shipped at 0, and measured; the owner decides on it at the Task 4 close review with the probe report in hand (section 18, O1).

## 1. Purpose
HANDOFF 7 says the colony leaves Settlement "when relationships and trust form", and HANDOFF 5 says sociable beings seek each other out. Today the sim has no notion of who knows whom: the talk pose in the view picks any two beings standing near each other. Task 4 gives every being a private social life that comes from its personality and its days, tells the player about it in the colony's voice when something worth telling happens, and leaves a per-sol reading of colony trust for Task 5 to judge. It is a record of what the people already did, in the same spirit as ages: nothing counts toward anything.

## 2. Terms
| Term | Meaning |
| --- | --- |
| bond | private float in [0, 1] per unordered pair of living beings; absent means 0 |
| together (room) | both beings `is_inside()`, neither in state `sleep`, same `building_id`, at a tick |
| together (work) | both in state `work` with `job` equal to the current site, or both in state `mining` with the same `mine.site`, at a tick |
| place | where a pair grew at a tick: the building kind (room), `site` (construction), or the field kind `ice` / `pit` (mining) |
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
| `found_friend` | set of being ids named in a logged `friends` or `found_friend` line (section 5.6); set only when the line is actually logged |
| `crew_drift_named` | set of founder ids already named in a crew drift line (section 5.5) |
| `friend_count` | map from being id to its number of `friends` pairs, kept in step with the flags (derived; used by the lonely pull and the sol reading) |
| `pending` | queue of capped line events, at most `log.queue_max`, oldest first (section 5.6) |
| `acc_h` | hours since the last tick (accumulator, `STEP_EPS` slack, like `_build_acc`) |
| `lines_sol`, `lines_this_sol` | the elapsed sol of the current cap count, and how many capped-kind lines were logged in it |
| `present` | snapshot from the last tick: building id to ascending list of awake-inside being ids (read by the pull, section 8; never by the view) |
| `last_tick_ms` | wall time of the last tick, for the probe only; never in stats, log or any hashed state |
`Being` gains **no field**. `stats` gains one key, `stats.relationships` (section 10.2). `SimWorld` gains `relationships`, `relationships_enabled` (default true; false skips both hooks, test seam), the hook calls, and the creation call. Nothing else in `sim/` changes, except the optional pull terms (section 8), which read `present` and `friend_count` and are exactly neutral at their shipped values.

## 4. Where it runs
- **Creation**: in `SimWorld._init`, after `ages.begin(...)` on both branches: `relationships.begin(self, founders_world)`. A founder world seeds the crew bonds (5.4) and fills `known`; a blank world fills `known` from whatever beings exist (none at creation) and seeds nothing.
- **Tick (phase 11b)**: in `step()`, after `_sample_being_stats()` and before the `if _sol_started:` block: `relationships.on_step(self, fixed_step)`. It adds `fixed_step` to `acc_h` and runs a tick when `acc_h >= tick_h - STEP_EPS`, then sets `acc_h` to 0. With `tick_h` 1.0 and `fixed_step` 0.05 that is every 20th step. All phases that move, kill or create beings (6, 7, 9, 10) have run, so the tick reads settled state.
- **Sol reading**: inside the `if _sol_started:` block, after `ages.on_sol(self)`: `relationships.on_sol(self)` (section 7). It runs after ages so `age_history` cannot see it, and ages never reads it (section 11).
- No wall clock (except the probe-only `last_tick_ms`), no read of the log, no write to colony, buildings, beings, resources, powers, or the RNG.

## 5. Rules (one tick, in this order)
### 5.1 Deaths
For each id in `known` that is not a living being, in ascending id: find its pairs with living beings whose bond is >= `lines.friend`. Take up to `log.grief_max` (2) of them, highest bond first (ties: lowest living id), and log one grief line (5.6) per mourner, mourner first. Remove every pair that contains the dead id (updating `friend_count`), drop any `pending` event that names the dead id, and remove the id from `known`, `found_friend` and `crew_drift_named`.
### 5.2 Births
For each living being not in `known`, in ascending id: add it to `known`. If it has `parent_id` != 0 and that parent is alive, create the pair with `bond = seed.kin_base + seed.kin_warmth x (warmth(newborn) + warmth(parent)) / 2` (0.30 to 0.55 at the shipped values; E), `kin = true`, and set the flags from the lines (so `friends` is always true, since `kin_base` equals the friend line). No log line. A being born and dead between two ticks is never seen (no pair, no grief); accepted.
Note (ages.md section 3): the recorded parent is the being `rng.pick(here)` chose, and it can itself be a child. The text never says "mother", "father" or "parent"; kin is "who was there when they were born", nothing more.
**The kinless newborn (player-facing story).** A newborn whose recorded parent has died starts with no friend. The player sees what every newcomer gets: in an opened roof it exchanges brief words with whoever stands near it (the stranger talk of 10.1), never a frozen stand-off. Its first grown friendship is always news, and the line names it first: "Vana-3 has found a friend in Kiro-12. They share the habitat." That line is the story: the colony noticed that someone new found their people. There is no "has no one yet" line: at about one birth a sol it would become a daily line about absence (decision and dissent in 17). The probe reports how many newborns are kinless and their median sols to a first friend (13, item 8).
### 5.3 Growth
Build `present`: for each living being that is `is_inside()` and not `sleep`, append its id to the list of its `building_id`, in ascending being id; buildings in ascending id. Then:
- **Room**: for each building with at least 2 ids, for each pair (i < j in the list): `bond += room_rate x tick_h x room_factor x affinity x (1 - bond)`. Place: the building's kind.
- **Work**: the crew of the current site (state `work`, `job` == site) and each mining field's crew (state `mining`, grouped by `mine.site`; fields in the order of `resources.ice_fields` then `resources.pits`; beings in ascending id): for each pair, `bond += work_rate x tick_h x affinity x (1 - bond)`. Warmth does not enter: shared hard work builds trust between any two people. Place: `site`, or the field's `kind` (`ice` or `pit`).
- A pair can grow at most once per tick (a pair cannot be in a room and on a site at once, so this holds by construction; the test checks it).
- Every grown pair is marked `grown_this_tick` with its place for this tick (a tick-local value, not stored in `pairs`). Friend and close crossings happen only on growth (decay only lowers bonds), so every such crossing has a place without any stored history.
- A missing pair is created at bond 0 before growing.
**Personality terms** (traits from `persona.traits`, each in [0, 1]):
- `warmth(x) = (sociability_x + care_x) / 2` (the same two traits that make a habitat fertile in `Colony.birth_chance`).
- `room_factor = grow.warmth_base + (warmth(i) + warmth(j)) / 2`.
- `tempo(x) = restless_x - steady_x` (in [-1, 1]).
- `gap = abs(tempo(i) - tempo(j)) x (1 - affinity.curiosity_soften x max(curiosity_i, curiosity_j))`.
- `affinity = clamp(1 - affinity.tempo_gap_coef x gap, affinity.floor, 1)`.
So like rhythms bond easily, clashing rhythms bond slowly, and one curious being in the pair halves the clash at the shipped 0.5. Drive does not enter the formula; it enters through the days (driven beings are on the site together more often). Known limit: bonds are never negative, so there are no rivals in Task 4 (dislike is on the Task 5 list, section 19).
### 5.4 Founder crew (creation only)
Every pair of the 7 founders starts at `seed.crew` (0.35, just over the friend line), `crew = true`, `friends = true`, `was_close = false`. They trained and flew together; whether they stay friends depends on whether they keep sharing rooms. A blank world seeds nothing. (Owner question O4.)
### 5.5 Decay, forgetting, flags
For every pair not grown this tick, in ascending key: `bond -= decay.per_h x tick_h x (decay.restless_base + (restless_i + restless_j) / 2) x (decay.close_hold if close else 1)`, floored at 0. Then for every pair touched (grown or decayed): if bond < `lines.forget_below` and the pair is neither `friends` nor `close`, remove it. Then update flags with hysteresis (and `friend_count`) and collect crossing events:
- `friends` false to true on a pair that is neither `kin` nor `crew`: event `friends` with the pair's place, if at least one of the two is not in `found_friend`. (`found_friend` is not touched here; see 5.6.)
- `close` false to true, pair never `was_close`, and neither being has any other `close` pair: event `close_crew` if the pair is `crew`, else event `close` with the place. Set `was_close` in every case. The "no other close pair" rule means at most 3 crew close lines in a run (each names two of the 7 founders).
- `friends` true to false on a `was_close` pair: event `drifted`.
- `friends` true to false on a `crew` pair that is not `was_close`, when neither founder is in `crew_drift_named`: event `drifted`; both ids join `crew_drift_named` when the line is logged. At most 3 such lines in a run; the rest of the crew's thinning is silent but is visible to Task 5 in `web_by_sol` (section 11).
- Other crossings change flags and the run-wide counts (10.2) only.
### 5.6 Log lines (fixed texts, no random rotation, names only, no numbers)
**Cap and queue.** The capped kinds (`friends`, `found_friend`, `close`, `close_crew`, `drifted`) share a per-sol cap
`cap = max(log.max_lines_per_sol, floor(pop / log.pop_per_line))` (3 up to pop 159, 4 at 160; E),
counted per elapsed sol from `world.sol()` at the tick, `pop` the living count at the tick. At each tick, events are offered in this order: first the `pending` queue (oldest first), then this tick's events (grief, then `friends`, `close`/`close_crew`, `drifted`, each in ascending pair key). For each:
1. **Revalidate** (queued events only): the pair still exists and still holds the flag the event reports (`friends` / `close` set; `friends` cleared for `drifted`), both beings are alive, and for a friend event at least one of the two is still not in `found_friend`. Otherwise drop it (counted in `lines_stale`).
2. If under the cap: log it, count it, and for a friend event add both ids to `found_friend` (crew drift: both to `crew_drift_named`).
3. Else: append to `pending` (count `lines_capped`); if `pending` now exceeds `log.queue_max` (3), drop the oldest (count `lines_dropped`).
Because `found_friend` is set only when a line is logged, a being whose first friendship is dropped keeps its "first" for its next friendship: a first is delayed, never lost while the being lives. Over-cap events are never summarised in a line; with the queue, drops are expected to be rare (probe target, section 13).
**Grief** is never capped or queued: at most `log.grief_max` lines per death, and deaths are already logged one line each.
**Form of the friend line.** If exactly one of the two is new (not in `found_friend`), the `found_friend` text with the new being as `{a}`; if both are new, the `friends` text, lower id first. Then, for `friends`, `found_friend` and `close`, the place sentence for the event's place is appended after one space.
| Kind | Key | Text |
| --- | --- | --- |
| `friends` | `text.friends` | "{a} and {b} have become friends." + place |
| `found_friend` | `text.found_friend` | "{a} has found a friend in {b}." + place |
| `close` | `text.close` | "{a} and {b} have grown close." + place |
| `close_crew` | `text.close_crew` | "{a} and {b} have grown close. They came a long way together." |
| `drifted` | `text.drifted` | "{a} and {b} don't see much of each other now." |
| `grief` | `text.grief` | "{a} is mourning {b}." |
| Place | Key | Sentence |
| --- | --- | --- |
| habitat | `text.place.habitat` | "They share the habitat." |
| green_room | `text.place.green_room` | "They keep company in the green room." |
| workshop | `text.place.workshop` | "They spend their hours in the workshop." |
| reactor | `text.place.reactor` | "They keep watch in the reactor." |
| archive | `text.place.archive` | "They pass the hours in the archive." |
| comms | `text.place.comms` | "They keep company at comms." |
| site | `text.place.site` | "They build side by side." |
| ice | `text.place.ice` | "They work the ice together." |
| pit | `text.place.pit` | "They dig the regolith together." |
| any other kind | `text.place.other` | "They spend their days together." |
Kind names in the log: `rel_friends`, `rel_found_friend`, `rel_close`, `rel_close_crew`, `rel_drifted`, `rel_grief`. Each logged entry carries `being_id` (`{a}`), `other_id` (`{b}`), `place` (place string, or "" for drift and grief) and `building_id` (the room's id for room places, else null), so a later view can focus the camera (deferred, section 19).
Why so few lines: at 160 beings and roughly one birth a sol, newborns' first friendships alone give about one line a sol (E). Friendships between beings who already have friends are not news; first friendships, first close bonds, the end of a close bond, the crew drifting and grief are.
**Log eviction (checked).** `SimWorld._log` evicts the oldest entry once the log passes `colony.log_cap` (500), whatever its kind (`pop_front`). Relationship lines are therefore never evicted ahead of other lines, and eviction changes no bond and no stat. The binding visibility limit is the 8-line log panel, not the 500 cap. No separate ring buffer: the run-wide record a later view or Task 5 would need is in `stats.relationships` (firsts, counts, per-sol shares). Test 10 proves the kind-blind eviction.

## 6. Numbers, and what they imply (all E)
Tick of 1 h; a pair "together" for h awake hours per sol and apart for the other 24.66 - h hours.
- Typical pair: warmth 0.4 each, affinity 0.8, restless 0.4 each. Growth constant per hour together: 0.008 x 0.6 x 0.8 = 0.00384. Decay per hour apart: 0.0005 x 0.9 = 0.00045.
- Hours together per sol needed to reach a friendship at all (balance point bond = 0.30): 0.00384 x 0.7 x h = 0.00045 x (24.66 - h), so h is about 3.5. Warm, like-rhythmed pair (warmth 0.6, affinity 1.0): about 2.0 h. Cold, clashing pair (warmth 0.25, affinity 0.5): about 7.4 h. Personality therefore decides who becomes friends at the same exposure, which is the point.
- Roommates who share about 10 awake hours a sol settle near bond 0.8 (close). A pair sharing one hour a sol never bonds.
- From a fresh pair, 10 h a sol together, a typical pair crosses the friend line after about 9 sols and the close line after about 25 sols (net of decay, roughly; the probe measures it).
- A friendship at 0.30 left alone falls below the drop line 0.15 after about 333 h, about 13.5 sols; a close bond at 0.60 decays at a quarter of that rate and needs about 3,600 h (146 sols) to fall to 0.40 and then the ordinary rate to fall to 0.15. Founder crews who never share a room lose the friend flag after about 18 sols of separation (0.35 to 0.15 = 0.20 / 0.00045 = 444 h).
- Kin seed: a newborn of mean warmth 0.4 with a parent of 0.4 starts at 0.30 + 0.25 x 0.4 = 0.40; the warmest possible pair at 0.55, the coldest at 0.30 (friends at birth, and the first to drift if the two are apart).
- Lines (E): cap 3 a sol to pop 159, 4 at 160; with the queue, the expected rate is about 1 capped-kind line a sol at 160 beings, 0.3 to 1 early on. Probe floor target: at least 1 line per 5 sols on average over sols 20 to 300.
- Crew close lines: founders sharing the habitat at landing (4 of them, about 10 h together a sol) reach close near sol 15 to 25 (from 0.35), so the first relationship line of a founder world is expected in that window, not near sol 20 at the earliest as in revision 1.
- These figures assume the 1-h sample is representative of the hour; it is a sample, not an integral. The probe compares it with a per-step count on one seed (section 13).

## 7. The trust reading (once a sol)
At each sol boundary, `on_sol(world)`:
1. Build the web from `friends` pairs; find connected parts with a union-find over ascending ids.
2. `web_share = size of the largest part / pop`; `second_share = size of the second-largest part / pop` (0.0 if there is no second part of size 2 or more); `lonely_share = lonely beings / pop`; `friends_mean = 2 x friend pairs / pop`. At pop 0 all are 0.0.
3. Append `web_share` to `stats.relationships.web_by_sol`, `second_share` to `second_by_sol` and `lonely_share` to `lonely_by_sol` (one entry per boundary, so `len == sols elapsed`, like `pop_by_sol`), and store the latest values.
Why largest part: a colony where everyone has a friend but the friendships form two islands is not a colony that trusts itself; Task 5 can read islands as the seed of factions (HANDOFF 7, Council: "factions by personality"). `second_share` is there because one bridging being can hold `web_share` at 1.0 over two camps; a rising second part is the first sign of a split. This spec does not decide what share counts as "trust has formed"; Task 5 owns that rule and reads the per-sol lists with its own window, as it reads `age_history`.
**Islands: wanted, within limits.** Camps by temperament are raw material for Task 5 factions and are not a failure. What is not wanted is a colony of newborns left outside every camp. The probe checks the second, not the first (13, item 7).

## 8. Behaviour effect: friends draw each other, lonely beings seek company (built, shipped off)
In `Being._restless_travel`, the weight of each neighbour building becomes
`v = room_pull.floor + pow(trait x mult, exponent) + effects.friend_pull x min(friends_there, effects.friend_pull_cap) + L`
where `friends_there` is the number of ids in `world.relationships.present[neighbour id]` that are `friends` with this being, and `L = effects.lonely_pull x min(people_there, effects.friend_pull_cap)` if this being's `friend_count` is 0, else 0 (`people_there` = all ids in `present[neighbour id]`). The snapshot is at most one tick, 1 h, old; it is deterministic.
- Shipped values `effects.friend_pull` = **0.0** and `effects.lonely_pull` = **0.0**. When both are 0.0, neither count is computed and no term is added, so the weights, the draws and every decision are bit-identical to Task 3 (also true numerically, since adding 0.0 is exact; skipping is for cost). Hashes unchanged.
- Probe values `balance.probe_friend_pull` = 0.25 and `balance.probe_lonely_pull` = 0.15 (E), cap 3: at the cap a room gains 0.75 for friends (0.45 for a lonely being drawn to people), against a floor of 0.15 and a trait term of 0 to about 0.5. Same number and order of draws; different outcomes; the five table hashes change.
- The loop it creates: friends gather, gathering grows bonds, bonds draw more gathering. Bounded by saturation (1 - bond), the cap, the unchanged chance to travel at all, sleep, work and mining, which pull beings apart every sol. Expected story: cliques by temperament, curious beings as bridges, which is what Task 5's factions need.
- Worst loop (emergence review): cliquing, where friend pull alone gives a newborn with no friends no pull at all, so established camps fill rooms the newcomer never joins. The lonely term is the counterweight: a being with no friend drifts toward occupied rooms, where room growth can start. The probe runs the friend pull with and without the lonely term (13, item 7) so the owner sees what it buys.

## 9. The god's influence (no new power)
Nothing the god does writes a bond. The god shapes who meets whom: Inspire puts a new room where beings will gather, Grace brings newborns into a particular habitat, Good fortune keeps rooms lit. Bonds follow from those days. What the player sees of it: the new room fills, people talk there (friends at length, strangers briefly), and later a friend line names that room ("They keep company in the green room."). A direct social power (gather, rumor, a shared dream; HANDOFF 4, future ideas) is out of scope for Task 4 and would read this layer later.

## 10. What the player sees, and stats
### 10.1 Player-facing (view; sim read-only)
- **Log lines** of 5.6, in the existing log panel. No number, no share, no count, no trait word, no sign. Each line says where (the place sentence), except drift, crew close and grief.
- **Friends talk at length; strangers exchange a word.** In an opened roof, the existing talk pose (`view_model._talk_flags`: two awake jumpsuit beings pausing within `interior.talk_radius_px`; the lower id of a pair speaks first) becomes a gradient, decided per pair (lower id `lo`, from the read-only query `world.relationships.are_friends(a, b)`):
  - friends (and close) pairs: talk for the whole pause, exactly as today;
  - other pairs: talk only while `fposmod(real_time / art.interior.stranger_talk_cycle_s + lo x 0.618034, 1.0) < art.interior.stranger_talk_share`, else idle-front. At 0.2 and 5.0 s that is a word of about 1 s in every 5, offset per pair so a room does not pulse in step.
  No view RNG draw is added. `stranger_talk_share` 1.0 restores the Task 3 behaviour exactly (test 16). This replaces revision 1's friends-only binary, which all three reviewers expected to read as a bug: a room never looks frozen, and a player who watches a while sees that some pairs keep talking.
- No new HUD line, no colony-wide word, no meter. HUD room at 720p is already tight (ages.md 18, item 7).
- No new art; texture memory is 47.1 of 48 MB (Q10).
### 10.2 Stats: `stats.relationships` (run-wide, never windowed, never reset; never shown)
| Key | Definition |
| --- | --- |
| `friendships_formed` | `friends` false-to-true crossings of grown pairs (not seeds) |
| `close_formed` | `close` false-to-true crossings |
| `drifted` | `friends` true-to-false on `was_close` pairs |
| `crew_drifted` | `friends` true-to-false on `crew` pairs |
| `lines` | `{friends, found_friend, close, close_crew, drifted, grief}` logged line counts |
| `lines_capped`, `lines_dropped`, `lines_stale` | events queued by the cap; dropped from a full queue; dropped on revalidation |
| `first_friendship_sol` | elapsed sol of the first grown friendship, null before |
| `first_mars_born_friendship_sol` | elapsed sol of the first grown friendship involving a Mars-born being, null before |
| `pairs`, `friend_pairs`, `close_pairs` | current counts, refreshed at each sol reading |
| `web_share`, `second_share`, `lonely_share`, `friends_mean` | latest sol reading |
| `web_by_sol`, `second_by_sol`, `lonely_by_sol` | one float per sol boundary (section 7) |
Not in stats: bond values, `present`, `known`, `pending`, tick timings. The dictionary is created with the other stats in `_init_stats` (zeros, nulls, empty lists).

## 11. Ages: untouched
Ages never read `world.relationships` or `stats.relationships`; relationships never read `world.ages` or write `age_history`. The Settlement entry and exit rules, the `unrest` cause group and every `ages.json` value are unchanged, so the Task 3 calibration is not reopened: the balance run must show the same settlement and fall-back sols (67, 58, 54, 65, 53; fall-backs 42 at 213, 99 at 174). The HANDOFF 7 line "relationships and trust form" is read as the condition for **leaving Settlement toward Council**, which is Task 5's rule to write from `web_by_sol` (owner question O2).
Consequence to carry into Task 5 (clarity review): the founders' crew thins mostly in silence (at most 3 crew drift lines), so `web_by_sol` can fall in the early sols with little said in the log. If Task 5 gates on the web, it must say so in words when the gate moves, as the ages do; a hidden counter must not act as a silent gate.

## 12. Randomness and the Task 1 hashes, per mechanic
No mechanic draws from `SimRng` or any other random source. Every order is fixed (ascending ids, list order of sites, ascending pair keys, queue order).
| Mechanic | Draws | Writes outside the module | Effect on the five Task 1 hashes |
| --- | --- | --- | --- |
| Crew seed at creation (5.4) | none | none | none |
| Kin seed, warmth-scaled (5.2) | none | none | none |
| Room and work growth, place (5.3) | none | none | none |
| Decay, forgetting, flags (5.5) | none | none | none |
| Death handling and grief, up to 2 lines (5.1) | none | log only | none (nothing in the sim reads the log; ages.md 4.1) |
| Log lines, cap scaling, queue (5.6) | none | log only | none; eviction at the 500 cap is display-only and kind-blind |
| Sol reading (7) | none | `stats.relationships` | none (new key, not in the table's old columns) |
| Friend and lonely pull at 0.0 (8, shipped) | none added | none | none: weights identical, terms skipped |
| Pull above 0.0 (probe or owner) | same draw count, different outcomes | being behaviour | **changes all five hashes**; needs the owner's baseline reset (O1) |
| Talk gradient (10.1) | none (view, `real_time` only) | none (view) | none |
Proof, as in ages.md 12: the balance table gains one trailing column `web` (2 decimals, the latest `web_share`) after `age`. Removing the last two fields reproduces the five Task 1 hashes 02032b23..., 830c7d0c..., 0e3e83a7..., bca6eb2c..., 2645033a...; removing only `web` reproduces the Task 3 table hashes recorded in `docs/balance/task-3-log.md` (42 da166c4f8b202820, 7 30c53f90949d979b, 99 54ad1e15b934bf9a, 1234 7052c92936a75157, 2026 67e3dcf057200eb9), which also proves the age crossings are unchanged. Plus the purity test (14, test 13).

## 13. Calibration probe (`tools/relationships_probe.gd`, read-only)
Runs the real module on seeds 42, 7, 99, 1234, 2026 to sol 300, three times: shipped (both pulls 0.0); friend pull only (`probe_friend_pull`, lonely 0.0); friend and lonely pull (`probe_friend_pull`, `probe_lonely_pull`). Pull runs use the data override seam, never by editing data. Writes `docs/balance/task-4-calibration.md` with, per seed and run:
1. `first_friendship_sol`, `first_mars_born_friendship_sol`, the sol of the first relationship line; counts of each line kind and of capped, dropped and stale events; lines per sol, max and mean; mean lines per 5 sols over sols 20 to 300.
2. `web_share`, `second_share`, `lonely_share`, `friends_mean` at sols 30, 60, 100, 150, 200, 300; the number of web parts of size 3 or more at sol 300.
3. Personality check: mean friend count of the warmest third against the coldest third (by `warmth`) at sol 300; mean bond age of friendships by mean pair `restless` (top third against bottom third).
4. Work check (emergence review): the same warmest-against-coldest friend count, split by beings' share of awake hours spent on the site or mining (top half against bottom half). If warmth has no effect among the work-heavy half on 3 or more seeds, the lead lowers `grow.work_rate` (one key, one run) before considering warmth in work growth.
5. Hours together per sol for friend pairs against non-friend pairs (median), to check the section 6 arithmetic.
6. The 1-h sample against a per-step count of together hours on seed 42 (sols 1 to 60): relative difference per pair, median and 90th percentile.
7. With a pull on: the same, plus the mean friend count of the loneliest third of beings born after sol 100 (at sol 300) against the shipped run; age settlement and fall-back sols, population at 300, deaths by cause, and the table hash differences, so the owner sees the full cost of switching it on.
8. Kinless newborns: the share of births with no living recorded parent at the next tick, and their median sols to a first friend (against kin newborns).
9. Tick cost: median and maximum microseconds per tick at pop around 70 and around 160, and stored pair count; step cost with and without the module.
Any recalibration edits `data/relationships.json` only, one key per run, chosen by the lead. Targets for the probe to confirm (E): first grown friendship before sol 20; first relationship line before sol 30 on a founder world; first Mars-born friendship within 15 sols of the first birth; `lonely_share` at sol 300 between 0.05 and 0.35; `friends_mean` at sol 300 between 1 and 12 (below 1, nobody has a life; above 12, friendship means nothing); dropped events under 5% of capped-kind events; at least 1 capped-kind line per 5 sols over sols 20 to 300; warmest third has more friends than the coldest third on every seed; tick under 1 ms median at pop 160. For the pull (not shipped): the loneliest-third newborn friend count with both terms is not below the shipped run's on any seed.

## 14. Tests (`tests/test_relationships.gd`, written first, red; no test with zero checks)
Staging: blank world, reactor, two habitats, workshop and green room built; beings added with `add_being`, then traits overwritten per test; state, `building_id`, `job`, `mine` set directly; ticks driven with `relationships.on_step(world, tick_h)` or by stepping 20 steps.
1. Room growth recurrence: two awake beings in one habitat, 10 ticks; bond equals the recurrence `b = b + k x (1 - b)` with `k` computed in the test from data and traits (tolerance 1e-12), from 0.
2. Personality: warm pair > cold pair after 10 ticks; equal-tempo pair > clashing pair; a clashing pair with one curiosity 1.0 is at exactly the softened affinity; a fully clashing pair is held at `affinity.floor`.
3. Not together: different buildings; one asleep; one in `transit`; one outside: no growth and decay applies.
4. Work: two `work` beings on the site grow at `work_rate` with warmth not entering (two cold beings grow as fast as two warm ones); two miners on the same field grow, on different fields do not; a pair never grows twice in a tick.
5. Decay: restless pair loses more per tick than a steady pair by the formula; a close pair loses `close_hold` of the open rate; a non-flagged pair under `forget_below` is removed.
6. Hysteresis: friends set at exactly `lines.friend`, kept at 0.20, cleared at just under 0.15; close set at 0.60, kept at 0.45, cleared under 0.40.
7. Crew: a founder world has 21 pairs at `seed.crew`, all `friends` and `crew`, none `was_close`, and logs no relationship line at creation; a blank world has no pairs. A crew pair crossing close logs `close_crew` (no place sentence); a second crew pair sharing a founder with it logs nothing; a crew pair losing the friend flag logs `drifted` once per founder (a second drop involving a named founder is silent and counted in `crew_drifted`).
8. Kin: a newborn with a living parent gets the kin pair at the next tick at exactly `kin_base + kin_warmth x` mean warmth, `friends` true, no line; a dead parent or `parent_id` 0 gives none.
9. Death and grief: pairs of the dead are removed at the next tick; with three living friends at bonds 0.7, 0.5 and 0.5 (ids 9 and 4), the two lines name the 0.7 mourner then id 4; no grief when every bond is under the friend line; grief lines are never capped or queued; a pending event naming the dead is dropped.
10. Lines and queue: `friends` only for a grown pair where one has not found a friend; never for kin or crew; one new being gives the `found_friend` form with the new being first, two new give the `friends` form; the place sentence matches the room kind, `site`, `ice`, `pit` and the `other` fallback; `close` only for the first close of both; `drifted` only for `was_close` or the crew rule. Cap: 5 friend events in one sol at pop 20 log 3, queue 2; at the next sol the 2 queued lines log first; a queued event whose pair lost the flag is dropped as stale; a fourth queued event drops the oldest; a being whose friend event was dropped has no `found_friend` entry and its next friendship gets the line. Cap scaling: at pop 160 the cap is 4, at 159 it is 3. Every text from data, rendered with sample names, has no digit and no `%`. Eviction: after 520 lines of another kind the log holds 500 and the oldest are evicted first whatever their kind; bonds and stats are unchanged.
11. Sol reading: staged webs (chain of 5, two islands of 3 and 4, 2 lonely) give the exact `web_share`, `second_share`, `lonely_share`, `friends_mean`; one entry per boundary; pop 0 appends 0.0 and divides by nothing.
12. Pull: at 0.0 / 0.0 the weights and the next 1,000 draws equal those of a world with the module disabled; at friend 0.25 a neighbour's weight rises by exactly 0.25 per friend up to the cap; at lonely 0.15 a being with no friend gains 0.15 per person present up to the cap, and a being with one friend gains nothing from it.
13. Purity, seed 42, 10 sols: worlds with `relationships_enabled` true and false have equal old `stats` keys, equal beings (id, building, state, energy), equal stocks, and equal next 1,000 `rng` draws; two same-seed worlds have identical `pairs`, `pending` and `stats.relationships`.
14. Tick timing: one tick every 20 steps; after N whole sols the tick count is floor(N x sol_h / tick_h) within one.
15. Key-path parity for `relationships.json` (section 15), both ways, and the data sanity rules.
16. View: at the same distance a friend pair talks at every sampled `real_time` in a 5-s cycle; a non-friend pair talks in a share of 100 evenly spaced samples within 0.02 of `stranger_talk_share`; two non-friend pairs with different `lo` are not in phase; with `stranger_talk_share` 1.0 `_talk_flags` equals the Task 3 output; the HUD source reads no bond value.

Balance (`tests/balance_lib.gd`): **T11** per seed at 300 sols, from `stats.relationships` only. Judged: (1) `len(web_by_sol) == len(second_by_sol) == len(lonely_by_sol) ==` boundaries seen; (2) `lonely_share <= balance.lonely_share_max`; (3) `friends_mean` in `balance.friends_mean_min` to `friends_mean_max`; (4) `first_friendship_sol` not null. Reported: everything of section 13 items 1 to 3. T1 to T10 unchanged and must pass with the same values as Task 3.

## 15. Tunables (`data/relationships.json`; E = estimate for the probe)
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| relationships.tick_h | sim hours | 1.0 | lead, E |
| relationships.grow.room_rate | per hour together | 0.008 | lead, E |
| relationships.grow.warmth_base | added to pair warmth | 0.2 | lead, E |
| relationships.grow.work_rate | per hour together | 0.03 | lead, E (probe item 4) |
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
| relationships.seed.kin_base | bond | 0.30 | lead, E (emergence S2) |
| relationships.seed.kin_warmth | bond per unit of pair warmth | 0.25 | lead, E |
| relationships.log.max_lines_per_sol | lines (cap floor) | 3 | lead, E |
| relationships.log.pop_per_line | living beings per line of cap | 40 | lead, E (clarity 8, modified) |
| relationships.log.queue_max | queued events | 3 | lead, E (feel B2) |
| relationships.log.grief_max | grief lines per death | 2 | lead (feel B3) |
| relationships.text.friends / found_friend / close / close_crew / drifted / grief | text with {a}, {b} | section 5.6 | lead |
| relationships.text.place.habitat / green_room / workshop / reactor / archive / comms / site / ice / pit / other | sentence | section 5.6 | lead |
| relationships.effects.friend_pull | added room weight per friend | 0.0 (shipped) | owner (O1) |
| relationships.effects.lonely_pull | added room weight per person, lonely beings only | 0.0 (shipped) | owner (O1) |
| relationships.effects.friend_pull_cap | beings counted | 3 | lead, E |
| relationships.balance.probe_friend_pull | added room weight per friend | 0.25 | lead, E |
| relationships.balance.probe_lonely_pull | added room weight per person | 0.15 | lead, E |
| relationships.balance.lonely_share_max | share of living | 0.35 | lead, E (clarity 2: was 0.5) |
| relationships.balance.friends_mean_min / friends_mean_max | friends per being | 1.0 / 12.0 | lead, E |
| art.interior.stranger_talk_share | share of time a non-friend pair talks | 0.2 | lead (view), E |
| art.interior.stranger_talk_cycle_s | real seconds per stranger cycle | 5.0 | lead (view), E |
Reused, not duplicated: `persona.traits` (sociability, care, restless, steady, curiosity), `room_pull.*` (beings.json), `Being.parent_id`, `SimWorld.STEP_EPS`, `colony.log_cap`, `interior.talk_radius_px`, `interior.talk_phase_s`. Not data: the flag names, line kinds and their emission order, the pair-key rule, "pop 0 reads 0.0", the phase constant 0.618034. The `balance.*` keys are read by the probe and `balance_lib.gd` only; the `art.*` keys by the view only. Revision 1's `seed.kin` and `art.interior.talk_friends_only` are removed.

### Key-path list (machine-readable; one leaf per line)
Same rules as ages.md 13. The `art.` lines are existence checks only.
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
relationships.seed.kin_base
relationships.seed.kin_warmth
relationships.log.max_lines_per_sol
relationships.log.pop_per_line
relationships.log.queue_max
relationships.log.grief_max
relationships.text.friends
relationships.text.found_friend
relationships.text.close
relationships.text.close_crew
relationships.text.drifted
relationships.text.grief
relationships.text.place.habitat
relationships.text.place.green_room
relationships.text.place.workshop
relationships.text.place.reactor
relationships.text.place.archive
relationships.text.place.comms
relationships.text.place.site
relationships.text.place.ice
relationships.text.place.pit
relationships.text.place.other
relationships.effects.friend_pull
relationships.effects.lonely_pull
relationships.effects.friend_pull_cap
relationships.balance.probe_friend_pull
relationships.balance.probe_lonely_pull
relationships.balance.lonely_share_max
relationships.balance.friends_mean_min
relationships.balance.friends_mean_max
art.interior.stranger_talk_share
art.interior.stranger_talk_cycle_s
```
`SimData.relationships()` is the accessor; `data_hash` in `tests/balance_lib.gd` adds `relationships`. Data sanity checked by test 15: `friend_drop < friend < close_drop < close`; `forget_below < friend_drop`; `0 < affinity.floor <= 1`; `seed.crew >= lines.friend`; `seed.kin_base >= lines.friend`; `seed.kin_base + seed.kin_warmth < lines.close`; `log.max_lines_per_sol >= 1`; `log.queue_max >= 0`; `log.grief_max >= 1`; every building kind in `buildings.json` has a `text.place` key; `0 < stranger_talk_share <= 1`.

### Edge cases
- Pop 0 or 1: no pairs grow; the sol reading appends 0.0 (pop 0) or the true shares (pop 1: web 1.0, second 0.0, lonely 1.0).
- A being dies on the tick step: handled at that tick (5.1 runs first).
- Two founders die in one tick and a third was friends with both: two grief lines for the same mourner, one per death, ascending dead id.
- A building goes offline: beings inside still count as together (the room is dark, not empty).
- A construction crew finishing: crew members `enter` the new building and become room-together there at the next tick.
- A new building kind added later without a place key: `text.place.other`; test 15 fails until the key is added.
- A queued event that is still valid but now names a being who found a friend in the meantime by a logged line: revalidation drops it as stale only if both are now in `found_friend`; otherwise it logs with the form decided at emission.
- Log eviction at 500 entries is kind-blind and changes no bond and no stat.
- Ids never repeat, so a pair key never refers to two different pairs.
- Cost: pairs per tick are the sum over buildings of k(k-1)/2 for awake-inside counts k; one crowded building of 40 gives 780 pair updates, still small. Stored pairs grow with the number of people each being has shared a room with; the forget rule keeps them bounded. Estimated under 1 ms per tick at pop 160 (once per 20 steps, under 2% of a 2.6 ms step); the probe measures it.

## 16. Requests to the assistant designers (done)
Asked in revision 1 and answered in `docs/design/reviews/relationships-emergence.md`, `relationships-feel.md`, `relationships-clarity.md`; record in section 17. A second round is not needed unless the owner's answers in section 18 change the shipped behaviour (O1 (c)).

## 17. Design review record
Reviewers: emergence (Will Wright lens), feel (Eric Barone lens), clarity (Karoliina Korppoo lens). Decision key: A adopted, AM adopted modified, D deferred, R rejected. All three reviewers agree with O1 (a), O2 (a), O3 (a) and O4 (a) as revised; clarity's agreement was conditional on its must-fixes, all of which are decided below.
### Emergence
| # | Item | Decision |
| --- | --- | --- |
| E-B1 | Record-only risks a dead layer; make O1 (a) a dated decision; list a grief mood/energy effect as a probe option | AM. O1 (a) now says the owner decides at the Task 4 close review with the probe report (section 18). The grief effect is D: it is a behaviour change with its own hash cost and would widen the probe; named in O1 as a later option. |
| E-B2 | Cliquing is the worst loop under the pull; add a loneliness term; probe the loneliest-third newborn friend count; say whether islands are wanted | AM. `effects.lonely_pull`: a being with no friend is drawn to rooms with people (anyone, not only beings it has a bond with: a newborn has almost none). Shipped 0.0, probed at 0.15 in its own run (13, item 7). Islands are wanted as temperament camps; newborns left outside every camp are not; the probe checks the latter (section 7). |
| E-B3 | Player cannot learn the toy; offer a behavioural reason in the first-friend line | AM. The place sentence (shared with feel B1 and clarity 5) ships as the default reason. The temperament reason ("They keep the same hours.") is owner question O3, because it edges toward naming hidden traits. |
| E-S1 | Crew pairs drift silently; one-time drift line or `was_close` at seed | AM. Crew drift line, at most once per founder (3 lines a run). Setting `was_close` at seed was rejected: it would also suppress the crew close line and up to 21 drift lines would compete for the cap. |
| E-S2 | Kin seed 0.45 is a hidden script; scale with warmth, about 0.30 to 0.55 | A. `kin_base` 0.30 + `kin_warmth` 0.25 x pair warmth. |
| E-S3 | Work growth ignores warmth at 4x the room rate; check split by site time | A as probe item 4 with a fixed remedy order (lower `work_rate` first). |
| E-S4 | No negative bonds, no rivals; note the limit; dislike to Task 5 | A as a note (5.3) and a Task 5 deferral (section 19). |
| E-S5 | Add second-largest part or articulation points | AM. `second_share` and `second_by_sol`; articulation points not adopted (more code, and Task 5 can compute them from the pairs if it needs them). |
| E-S6 | "The colony mourns {b}" when 3+ bonded beings | R for Task 4. Up to 2 grief lines (feel B3) already show that a death touched more than one person; a third line form is scope. |
| E-I1 | Falling-out line when a close bond halves | D (no negative or sudden drops exist yet; Task 5 with dislike). |
| E-I2 | Reunion line | D. |
| E-I3 | Mourner skips one social tick | D (behaviour change, hash cost). |
| E-I4 | Say how Inspire's gathering shows | A (section 9). |
| E-I5 | Click a log line to focus the camera | D to Task 5 (section 19); entries carry `being_id`, `other_id`, `building_id` now. |
| E-scope | Cut order: talk pose only if B3 unsolved, `lines_capped` detail, ideas; never grief or the pull lever | A (nothing cut; the lever stays). |
### Feel
| # | Item | Decision |
| --- | --- | --- |
| F-B1a | Put the place in the line, fixed variants per kind and place type | A. Place sentence per building kind, site, ice, pit, other (5.6); place comes free from the growth tick, no stored history. Not on drift and grief (no place at a decay or death). |
| F-B1b | "drifted apart" becomes "{a} and {b} don't see much of each other now." | A. |
| F-B2 | Capped events swallow firsts; keep the first-friend flag unset when capped; queue to the next sol (3, drop oldest) | A, both: `found_friend` set only on a logged line, queue of 3 with revalidation. |
| F-B3 | "{a} is mourning {b}."; up to 2 grief lines per death, never capped | A. |
| F-B4 | Crew close line "They came a long way together." | A as `text.close_crew`, limited to one per founder by the existing first-close rule. |
| F-O1, F-O3 | Strangers glance or talk briefly; rare extra beat | AM through the stranger talk gradient (no new frame, no view RNG). |
| F-O2 | Floor target: 1 line per 5 sols over sols 20 to 300 | A as a probe target. |
| F-O4 | "{a} has found a friend in {b}." | A as the `found_friend` form; it also carries the kinless newborn story (5.2). |
| F-O5 | No chores, no HUD word; reject O3 (c) | A (O3 (c) of revision 1 dropped from the owner questions). |
| F-cut1 | Cut the pull lever and its probe/test | R. Emergence calls it the layer's future; it costs no hash at 0 and gives the owner a measured choice. |
| F-cut2 | Cut probe items 5 and 6 (sample check, tick cost) | AM. Tick cost kept (target under 1 ms). Sample check kept on one seed only (it already was), because the whole growth model assumes the 1-h sample. |
| F-cut3 | Cut `first_mars_born_friendship_sol` | R. One integer; it is a probe target and the natural Task 5 marker of Mars-born belonging. |
| F-cut4 | Shrink `web` column and T11 to checks 1 and 4 | R. The `web` column is the hash proof's separator; checks 2 and 3 are the only guards against "nobody has a life" or "friendship means nothing". |
### Clarity
| # | Item | Decision |
| --- | --- | --- |
| C-1 | Friends-only talk reads as a bug; ship a gradient, not a binary | A, option (b): friends talk the whole pause, strangers about 1 s in 5 (10.1). |
| C-2 | Kinless newborns silent; let them talk or add "{a} has no one yet."; state the story; tighten lonely target | AM. They talk (stranger gradient); the story is told by the `found_friend` line (5.2). The "no one yet" line R: about one a sol at 160, a daily line about absence, against feel's quiet log. `lonely_share_max` 0.5 to 0.35. |
| C-3 | Cap loses firsts; do not set `found_friend` unless logged, or queue; say what the log shows when the cap hits | A both (with feel B2). When the cap hits, the log shows the line a sol later; drops from a full queue are silent and counted (probe target under 5%). The summary line was not adopted (it is a count in words). |
| C-4 | Click a log line to focus on the first named being | D to Task 5; recorded as a cost of O3 (a). |
| C-5 | The shared place in plain words | A (with feel B1a). |
| C-6 | Crew dissolves silently while `web_by_sol` falls; mark as a consequence in O2 | A. Crew drift lines (up to 3) and the Task 5 note in section 11 and O2. |
| C-7 | Rare colony-voice line when the web changes in kind (split, rejoin) | D to Task 5 (section 19). Without the pull the web changes slowly; Task 5 owns factions and their words. |
| C-8 | Scale the cap with population, max(3, pop/20) | AM. `max(3, floor(pop / 40))`: 4 at 160. pop/20 would allow 8 relationship lines a sol in an 8-line log panel. |
| C-9 | Log eviction may drop these lines first; check, or ring buffer | A as a check: eviction is FIFO and kind-blind (`world.gd` `_log`); no ring buffer (5.6). |
| C-I | Talk gradient by friend/close; muted pose for mourners; first Mars-born friendship line | Gradient A (friend vs stranger; close not separated, since friends already talk the whole pause). Muted pose D (needs a frame; texture budget). Mars-born line R (the `found_friend` line already names a Mars-born's first friend; the stat records the sol). |
### Dissent and tensions resolved
- **Talk pose.** Feel called friends-only talk the best idea in the spec; emergence and clarity expected it to read as a bug. Resolved by the gradient: feel keeps a visible difference between friends and strangers, clarity gets no frozen rooms. Feel's "only if a second frame exists" caution is respected: no new frame.
- **The pull lever.** Feel's first cut; emergence's "do not cut". Kept, shipped at 0, with the lonely term emergence asked for, and a dated owner decision so it cannot sit unused by default.
- **Cap scaling.** Clarity wants the cap to grow with the colony; feel wants a quiet log. Resolved at pop/40 with a floor of 3, plus the queue, so firsts survive without more lines per sol. Clarity's pop/20 is recorded as the dissent; the probe's dropped-event rate decides whether to revisit (one key).
- **Kinless newborns.** Clarity offered a "no one yet" line; feel's quiet-log principle and my own view that absence is not news decided against it. The stranger gradient and the `found_friend` line carry the story instead. Clarity's underlying worry (half the colony silent) is answered by both the gradient and the tighter `lonely_share_max`.
- **Reason in the first-friend line.** Emergence wants a temperament reason; clarity wants the place; feel wants the place. The place ships; the temperament reason goes to the owner (O3), because it risks naming hidden traits.
- **Grief.** Emergence wanted a colony-wide mourning line; feel wanted two personal lines. Two personal lines adopted: smaller, and closer to the "names, not numbers" voice.

## 18. Owner decisions (Herby, 2026-10-06) and options as posed
Resolved: **O1 = (a)** build the pull shipped at 0, decide at the Task 4 close review with the probe report. **O2 = (a)** ages untouched. **O3 = (a)** the place in the first-friend line. **O4 = (a)** founders start as a crew at 0.35.

### Options as posed
Four questions. Each lists the recommendation first, with its cost and the facts behind it.

**O1. Do relationships change what beings do, and when do we decide?** (plan Q2, Q6)
- (a) **Recommended: record now; build the pull (friends draw each other, lonely beings seek company) shipped at 0; you decide on it at the Task 4 close review, with the probe report.** Cost: until then bonds change only words and talk. Facts: the five Task 1 hashes and the Task 3 age sols stay identical; the probe runs the pull with and without the lonely term on all five seeds and reports web shape, the loneliest newborns' friend count, ages, population, deaths and hash changes. Switching on is two data values plus a recorded baseline reset. Not in the probe: a grief effect on mood or energy (emergence); it would be one more run if you want it measured too.
- (b) Record only, no lever. Cost: cheapest; the first behaviour effect waits for Task 5 or later and needs its own measurement then. Emergence's concern applies: a layer with no effect risks staying decorative.
- (c) Pull on now (0.25 friends, 0.15 lonely) with a baseline reset. Cost: all five hashes change, the Task 3 calibration (settlement 67, 58, 54, 65, 53; fall-backs on 42 and 99) must be re-measured and may move, and we switch it on before seeing what it does.

**O2. How does trust connect to the ages?** (plan Q1)
- (a) **Recommended: ages untouched; trust is offered to Task 5 as the way out of Settlement toward Council** (HANDOFF 7). Cost: in Task 4 trust has no visible consequence beyond the lines and the talk. Facts: no Task 3 number reopens; Task 5 reads `web_by_sol`, `second_by_sol` and `lonely_by_sol`. Consequence (clarity): the founders' crew thins mostly in silence (at most 3 crew drift lines), so the web can shrink early with little said; if Task 5 gates on it, Task 5 must put the gate in words.
- (b) Add a Settlement entry clause ("most of the colony is in one web"). Cost: reopens Task 3 calibration; with the founders bonded at landing it passes almost at once and only bites if newborns stay lonely.
- (c) Add "the colony has split apart" as a fall-back cause (the reserved `unrest` group). Cost: a new exit path, new calibration, and a social cause next to ice and air.

**O3. What reason does a first-friend line give?**
- (a) **Recommended: the place** ("Vana-3 has found a friend in Kiro-12. They keep company in the green room."). Cost: tells where, not why; the player infers personality from who keeps turning up where. Facts: 10 fixed sentences, no state, already specified; all three reviewers asked for the place or a reason.
- (b) The place plus a temperament sentence, fixed per category: "They keep the same hours." (small tempo gap), "They could not be more different." (large gap bridged by a curious one), "They work side by side." (grown on a site or field). Cost: the player learns the personality model faster, but the line now describes the hidden traits in words; 3 more texts and one category rule; a sentence that is right for the pair but may sound like a stat readout over time.
- (c) Names only, as in revision 1. Cost: lines are hard to remember at 160 beings; the cheapest.

**O4. Do the founders start as friends?**
- (a) **Recommended: yes, as a crew just over the friend line (0.35), with the crew lines.** Up to 3 "They came a long way together." close lines (expected sols 15 to 25 among housemates) and up to 3 crew drift lines (from about sol 18 among those who stop sharing rooms). Cost: the web is whole at landing, so trust is about whether newcomers join it.
- (b) Strangers (0). Cost: the colony's first lines are founders' friendships (about sol 9 among housemates), but seven people who crossed space together start as strangers, and the first sols read colder.
- (c) Housemates only (founders who start in the same building: the 4 in the habitat, the 2 in the reactor). Cost: the workshop founder starts alone; more seeded structure, less emergence.

## 19. Deferred to Task 5 (explicit)
- **Dislike / negative bonds** (emergence S4): rivals, falling-out lines (E-I1), and their role in factions.
- **Structural colony line** (clarity 7): one rare colony-voice line when the web changes in kind ("The colony has split into two camps." / rejoins), from `web_by_sol` and `second_by_sol`.
- **Click-to-focus** (clarity 4, emergence I5): clicking a relationship log line focuses the camera on `being_id` (or `building_id`); the entries already carry the ids.
- Also later, not scheduled: reunion line, mourner behaviour or muted pose, grief effect on mood or energy, a direct social god power.

## Changelog
- 2026-10-06: revision 1 (lead designer). Draft for the three assistant reviews; owner questions O1 to O4. Reviewer sign-off: pending.
- 2026-10-06: revision 2 (lead designer). Reviews folded in (section 17). Decided: stranger talk gradient replaces friends-only talk; place sentence on friend and close lines; `found_friend` line form; `found_friend` set only on a logged line, queue of 3 with revalidation; cap `max(3, floor(pop / 40))`; grief "is mourning", up to 2 lines per death; drift reworded; crew close line and once-per-founder crew drift line; kin seed scaled by warmth (0.30 to 0.55); lonely pull term (shipped 0); `second_share`; kinless newborn story stated; log eviction checked (FIFO, kind-blind); `lonely_share_max` 0.35; probe items 4, 7 (lonely run) and 8 added. Deferred to Task 5: dislike, structural colony line, click-to-focus. Owner questions revised: O1 dated, O3 is now the first-friend reason. All shipped values remain hash-neutral. Reviewer sign-off: emergence, feel, clarity folded; owner answers pending.
