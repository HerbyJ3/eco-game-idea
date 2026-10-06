# Spec: relationships and trust (Task 4), driven by personality (revision 5, calibration probe folded in)

Source of truth: HANDOFF.md sections 1, 2, 3, 5 (Social), 7, 9, 10. Plan and open questions Q1 to Q10: `docs/tasks/task-4-plan.md`. Format and age facts: `docs/specs/ages.md` (sections 3, 7, 8.2, 12, 18). Sim facts read: `sim/persona.gd`, `sim/being.gd`, `sim/world.gd` (phase order of `step()`, `_log` with FIFO eviction at `colony.log_cap` 500), `sim/resources.gd` (site `kind` "ice" or "pit"), `sim/colony.gd` (birth warmth), `data/persona.json`, `data/beings.json`, `data/buildings.json` (kinds reactor, habitat, workshop, green_room, archive, comms), `view/main.gd`, `view/model/view_model.gd` (`_talk_flags`).
Locked decisions respected: hidden birth chart (the layer reads only the six traits that `Persona` already derives; no chart, sign or trait is ever shown); ages not meters (no bond value, share, count or bar reaches the player); influence-only god (no power reads or writes a bond; section 9); per-being energy, power as a budget and ice-as-pressure are untouched (the layer writes no colony, being, building or resource state).
Tunables live in `data/relationships.json` (new) and two view keys in `data/art.json`. No tunable in the new module `sim/relationships.gd`. This spec describes behaviour and numbers only, no code. Every number marked E is an estimate until the calibration probe (section 13) measures it.

**Review status:** the three assistant reviews (emergence, feel, clarity) are folded in as revision 2; the code review is folded in as revision 3 (section 17, "Code review"); the test author's findings from writing the red tests (commit 7ac81c8) are folded in as revision 4 (section 17, "Test-author findings"); the calibration probe (`docs/balance/task-4-calibration.md`, 15 runs) and the tick profile (`docs/perf/task-4-tick-profile.md`) are folded in as revision 5 (section 17, "Calibration findings"). Section 17 is the record (adopted, adopted modified, deferred, rejected) with the dissent. The four owner questions are answered (section 18); revisions 3 to 5 change none of those answers. Revision 5 adds one owner question for the dated O1 decision (section 17, "Owner question at Task 4 close"); it does not edit section 18.

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
| new (for a line) | a living being not in `found_friend` at the moment a friend line is about to be logged (section 5.6) |
| pair key | the integer `lo x 2^20 + hi` (1,048,576 x lower id + higher id); ascending key order is ascending `lo`, then ascending `hi` |

**Notes on "together".** "Awake" means any state other than `sleep` (eating, resting, idling and walking inside a room all count). `is_inside()` is false in the states `transit`, `eva`, `work` and `mining` (`sim/being.gd`), so room and work togetherness never overlap. A dark (offline) room still counts. Two beings in different buildings are never together, even if the buildings touch. Togetherness is sampled at the tick (section 6, last bullet), not integrated over the hour.

## 3. State (all new, all inside `Relationships`, owned by `SimWorld` as `world.relationships`)
| Field | Meaning |
| --- | --- |
| `pairs` | map from the integer pair key (`lo x 2^20 + hi`, section 2) to `{lo, hi, bond, friends, close, was_close, kin, crew}`. Every loop that can emit an event or remove a pair walks the keys in ascending order (sorted, never dictionary insertion order). Being ids must stay below 2^20; `begin` and the birth step assert it (a run reaching it would need over a million beings) |
| `known` | set of being ids alive at the previous tick (to detect births and deaths between ticks) |
| `found_friend` | set of being ids named in a logged `friends` or `found_friend` line (section 5.6); set only when the line is actually logged |
| `crew_drift_named` | set of founder ids already named in a crew drift line (section 5.5) |
| `friend_count` | map from being id to its number of `friends` pairs, kept in step with the flags (derived; used by the lonely pull and the sol reading) |
| `pending` | queue of capped line events, at most `log.queue_max`, oldest first (section 5.6). An event stores `{type, lo, hi, place, building_id}` where `type` is `friend` (the line form is decided at log time, not stored), `close`, `close_crew`, `drift_close` or `drift_crew` |
| `acc_h` | hours since the last tick (accumulator, `STEP_EPS` slack, like `_build_acc`) |
| `ticks` | number of ticks run since creation (int, starts at 0, incremented once at the start of every tick). Read by the probe (and by any later decay remedy, section 13); never in stats, log or hashed state. Test 14 may read it or detect ticks by the reset of `acc_h`; both are valid |
| `lines_sol`, `lines_this_sol` | the elapsed sol of the current cap count, and how many capped-kind lines were logged in it. At the start of every tick's line step, if `world.sol()` differs from `lines_sol`, set `lines_sol = world.sol()` and `lines_this_sol = 0`. Grief lines never count |
| `present` | snapshot from the last tick: building id to ascending list of awake-inside being ids (read by the pull, section 8; never by the view) |
| `last_tick_ms` | wall time of the last tick, for the probe only; never in stats, log or any hashed state |
`Being` gains **no field**. `stats` gains one key, `stats.relationships` (section 10.2). `SimWorld` gains `relationships`, `relationships_enabled` (default true; false skips both hooks, test seam), the hook calls, and the creation call. `Relationships` exposes read-only queries (`are_friends(a, b)`, symmetric) and one test seam, `debug_set_bond(a, b, bond)` (never called by the sim, view or tools). Its exact behaviour (revision 4): if the pair (a, b) is missing it is created with every flag false; it sets `bond`; it then sets `friends` and `close` from the bond with the hysteresis of section 2 applied to the pair's current flags, and updates `friend_count`. It does **not** set `was_close` (even when it sets `close`), never sets `kin` or `crew`, logs nothing, makes no event, touches no `stats.relationships` count and does not mark the pair as grown or seeded for the current tick. Tests that need `was_close` reach it by a real crossing in a tick. Nothing else in `sim/` changes, except the optional pull terms (section 8), which read `present` and `friend_count` and are exactly neutral at their shipped values.

## 4. Where it runs
- **Creation**: in `SimWorld._init`, after `ages.begin(...)` on both branches: `relationships.begin(self, founders_world)`. A founder world seeds the crew bonds (5.4), fills `known`, and then **appends one initial sol reading** (section 7, steps 1 to 3, on the seeded crew: `web_share` 1.0, `second_share` 0.0, `lonely_share` 0.0, `friends_mean` 6.0 with 7 founders), because the founder branch of `SimWorld._init` also appends the initial `pop_by_sol` entry; so `web_by_sol`, `second_by_sol` and `lonely_by_sol` stay the same length as `pop_by_sol` from creation on. A blank world fills `known` from whatever beings exist (none at creation), seeds nothing and appends no reading, because the blank branch appends no `pop_by_sol` entry either. Rule: `begin` appends an initial reading exactly when `_init` appends an initial `pop_by_sol` entry. Creation is not a tick: `begin` runs no growth, decay or line step and does not advance `ticks`.
- **Tick (phase 11b)**: in `step()`, after `_sample_being_stats()` and before the `if _sol_started:` block: `relationships.on_step(self, fixed_step)`. It adds `fixed_step` to `acc_h` and runs a tick when `acc_h >= tick_h - STEP_EPS`, then sets `acc_h` to 0. With `tick_h` 1.0 and `fixed_step` 0.05 that is every 20th step. All phases that move, kill or create beings (6, 7, 9, 10) have run, so the tick reads settled state.
- **Sol reading**: inside the `if _sol_started:` block, after `ages.on_sol(self)`: `relationships.on_sol(self)` (section 7). It runs after ages so `age_history` cannot see it, and ages never reads it (section 11).
- No wall clock (except the probe-only `last_tick_ms`), no read of the log, no write to colony, buildings, beings, resources, powers, or the RNG.

## 5. Rules (one tick, in this order)
### 5.1 Deaths
For each id in `known` that is not a living being, in ascending id: find its pairs with living beings whose bond is >= `lines.friend`. Take up to `log.grief_max` (2) of them, highest bond first (ties: lowest living id), and log one grief line (5.6) per mourner: the mourner is `{a}` (entry `being_id`), the dead is `{b}` (entry `other_id` = the dead id). The dead being is no longer in `world.beings`, so its name is read from `stats.deaths_list`: the last entry whose `being_id` equals the dead id (`SimWorld._kill` appends `{t, sol, clock_sol, being_id, name, cause}` before the tick runs). If no such entry exists (a being removed without `_kill`, test staging only), no grief line is logged for that death; the pairs are still removed as below. Grief lines are logged **here, immediately**, before any queued or new capped-kind event is offered (5.6), and never count toward the cap. Remove every pair that contains the dead id (updating `friend_count`), drop any `pending` event that names the dead id (counted in `lines_stale`), and remove the id from `known`, `found_friend` and `crew_drift_named`.
### 5.2 Births
For each living being not in `known`, in ascending id: add it to `known`. If it has `parent_id` != 0 and that parent is alive, create the pair with `bond = seed.kin_base + seed.kin_warmth x (warmth(newborn) + warmth(parent)) / 2` (0.30 to 0.55 at the shipped values; E), `kin = true`, and set the flags from the lines (so `friends` is always true, since `kin_base` equals the friend line). No log line. Setting the flags at creation is **not a crossing**: no event, no `friendships_formed` or `friendships_renewed` count, and `friend_count` of both beings rises by one. The pair is marked `seeded_this_tick` (tick-local, like `grown_this_tick`), and a seeded pair is neither decayed nor forgotten nor flag-updated in 5.5 of the tick that created it, so after its creation tick the bond is exactly `kin_base + kin_warmth x` mean warmth whatever the decay values. A seeded pair is also skipped by growth (5.3) in its creation tick, even if newborn and parent share a room: the seed replaces that tick's growth for that pair. Growth or decay applies from the next tick on. Founder crew pairs are seeded at creation (5.4), which is not a tick, so they have no "creation tick" and follow the normal rules from the first tick. A being born and dead between two ticks is never seen (no pair, no grief); accepted.
Note (ages.md section 3): the recorded parent is the being `rng.pick(here)` chose, and it can itself be a child. The text never says "mother", "father" or "parent"; kin is "who was there when they were born", nothing more.
**The kinless newborn (player-facing story).** A newborn whose recorded parent has died starts with no friend. Measured (revision 5): this never happened in 15 runs (0 of 45 to 173 births per run), because the recorded parent is a being present at the birth and is alive at the next tick. The rule stays as written (it costs nothing and covers a parent dying in the same tick); the story it tells now belongs to the **unmoored newborn**: one whose kin friendship ended (the kin pair's `friends` flag cleared, or the parent died) before its first grown friendship. That is the newborn who is really alone, and it is what probe item 8 measures (section 13). What the player sees is unchanged. The player sees what every newcomer gets: in an opened roof it exchanges brief words with whoever stands near it (the stranger talk of 10.1), never a frozen stand-off. Its first grown friendship is always news, and the line names it first: "Vana-3 has found a friend in Kiro-12. They share the habitat." That line is the story: the colony noticed that someone new found their people. There is no "has no one yet" line: at about one birth a sol it would become a daily line about absence (decision and dissent in 17).
**Kin newborns get the line too.** The kin seed logs nothing and does not put the newborn in `found_friend`, so a newborn with a living parent is still "new": its first grown friendship outside its kin pair gets the `found_friend` line (or the `friends` form if the other being is also new) exactly like a kinless newborn's. The probe reports how many newborns are kinless and their median sols to a first friend (13, item 8).
### 5.3 Growth
Build `present`: for each living being that is `is_inside()` and not `sleep`, append its id to the list of its `building_id`, in ascending being id; buildings in ascending id. Then:
- **Room**: for each building with at least 2 ids, for each pair (i < j in the list): `bond += room_rate x tick_h x room_factor x affinity x (1 - bond)`. Place: the building's kind.
- **Work**: the crew of the current site (state `work`, `job` == site) and each mining field's crew (state `mining`, grouped by `mine.site`; fields in the order of `resources.ice_fields` then `resources.pits`; beings in ascending id): for each pair, `bond += work_rate x tick_h x affinity x (1 - bond)`. Warmth does not enter: shared hard work builds trust between any two people. Place: `site`, or the field's `kind` (`ice` or `pit`).
- A pair can grow at most once per tick (a pair cannot be in a room and on a site at once, so this holds by construction; the test checks it).
- Every grown pair is marked `grown_this_tick` with its place for this tick (a tick-local value, not stored in `pairs`). Friend and close crossings happen only on growth (decay only lowers bonds), so every such crossing has a place without any stored history.
- A missing pair is created at bond 0 before growing. Its first growth is small (about 0.004 for a typical room pair, section 6), below `lines.forget_below`; it survives because forgetting applies only to pairs that decayed this tick (5.5).
- A pair marked `seeded_this_tick` (a kin pair created in 5.2 of this tick) is skipped.
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
For every pair neither grown nor seeded this tick, in ascending key (the decay values do not depend on order; removal and event collection do, so one sorted walk serves both): `bond -= decay.per_h x tick_h x (decay.restless_base + (restless_i + restless_j) / 2) x (decay.close_hold if close else 1)`, floored at 0. Then **forgetting, for decayed pairs only**: for every pair decayed this tick, if bond < `lines.forget_below` and the pair is neither `friends` nor `close`, remove it. A pair that grew this tick is never forgotten in that tick, whatever its bond: otherwise a fresh pair (first growth about 0.004, under `forget_below` 0.01) would be removed at creation and no new pair could ever form. Such a pair is forgotten only at a later tick in which it decays and is still under the line. Then update flags with hysteresis (and `friend_count`) for every grown or decayed pair still stored (seeded pairs are skipped, 5.2) and collect crossing events:
- `friends` false to true on a pair that is neither `kin` nor `crew`: always counted in `friendships_formed`. Event `friend` with the pair's place **only if at least one of the two is not in `found_friend` at this moment (emission)**. If both are already in `found_friend`, no event is created at all: nothing is queued, and nothing is counted in `lines_capped`, `lines_dropped` or `lines_stale` (there was never an event). (`found_friend` is not touched here, and the line form is not decided here; it is recomputed at offer time, 5.6.)
- `close` false to true, pair never `was_close`, and neither being has any other `close` pair: event `close_crew` if the pair is `crew`, else event `close` with the place. Set `was_close` in every case (this is the only place `was_close` is set; `debug_set_bond` never sets it). The "no other close pair" rule means at most 3 crew close lines in a run (each names two of the 7 founders).
- `friends` true to false on a `was_close` pair: event `drift_close` (logged with `text.drifted`). This holds for crew pairs that were close too; such a line neither checks nor fills `crew_drift_named`.
- `friends` true to false on a `crew` pair that is not `was_close`, when neither founder is in `crew_drift_named`: event `drift_crew` (logged with `text.drifted`); both ids join `crew_drift_named` only when the line is logged. If either founder is already named when the flag drops, no event is made: the drop is silent and counts only in `crew_drifted` (not in `lines_capped`, `lines_dropped` or `lines_stale`, since no event existed). At most 3 such lines in a run; the rest of the crew's thinning is silent but is visible to Task 5 in `web_by_sol` (section 11).
- `friends` false to true on a `kin` or `crew` pair (a seeded friendship that had lapsed and grew back): no event; counted in `friendships_renewed` (10.2), not in `friendships_formed`, and never sets `first_friendship_sol` or `first_mars_born_friendship_sol`.
- Other crossings change flags and the run-wide counts (10.2) only.
- Events are collected in ascending pair key within each type and offered in the type order of 5.6.
### 5.6 Log lines (fixed texts, no random rotation, names only, no numbers)
**Cap and queue.** The capped kinds (`friends`, `found_friend`, `close`, `close_crew`, `drifted`) share a per-sol cap
`cap = max(log.max_lines_per_sol, floor(pop / log.pop_per_line))` (3 up to pop 159, 4 at 160; E),
counted per elapsed sol from `world.sol()` at the tick (with the reset rule of section 3), `pop` the living count at the tick. Grief has already been logged in 5.1 and is not part of this step. Then events are offered in this order: first the `pending` queue (oldest first), then this tick's events (`friend`, then `close`/`close_crew`, then `drift_close`/`drift_crew`, each in ascending pair key). For each event, queued or new:
1. **Revalidate at offer time** (every event, not only queued ones, because a line logged earlier in the same tick can change `found_friend` or `crew_drift_named`): the pair still exists and still holds the flag the event reports (`friends` / `close` set; `friends` cleared for a drift), and both beings are alive. Then by type:
   - `friend`: **recompute the form now**. Let the new beings be those of the two not in `found_friend` at this moment. If neither is new, drop the event. If exactly one is new, the form is `found_friend` with the new being as `{a}`; if both are new, the form is `friends`, lower id as `{a}`. The place stays the one recorded at emission.
   - `drift_crew`: if either founder is now in `crew_drift_named`, drop the event.
   - `close`, `close_crew`, `drift_close`: no further check.
   A dropped event counts in `lines_stale` (queued or new alike) and is never logged.
2. If `lines_this_sol` is under the cap: log it with the form from step 1, increment `lines_this_sol`, count it in `lines`, and for a `friend` event add both ids to `found_friend` (a `drift_crew` event: both ids to `crew_drift_named`).
3. Else: a queued event stays where it is in `pending` (it was counted in `lines_capped` when first queued and is not counted again); a new event is appended to `pending` (count `lines_capped`), and if `pending` now exceeds `log.queue_max` (3), the oldest is dropped (count `lines_dropped`).
Because `found_friend` is set only when a line is logged, a being whose first friendship is dropped keeps its "first" for its next friendship: a first is delayed, never lost while the being lives. Because the form is decided at log time, a queued line can change form (for example a queued "A and B have become friends." logs as "B has found a friend in A." if A's first friendship was told in between), and it never names as new a being whose first was already told. Over-cap events are never summarised in a line; with the queue, drops are expected to be rare (probe target, section 13).
**Grief** is never capped or queued: at most `log.grief_max` lines per death, logged in 5.1, and deaths are already logged one line each.
**Place sentence.** For the `friends`, `found_friend` and `close` forms, the place sentence for the event's place is appended after one space.
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
**Name order (`{a}` / `{b}`), pinned for every kind:** `friends`, `close`, `close_crew` and `drifted` (both drift types): the lower id is `{a}`, the higher `{b}`. `found_friend`: the new being is `{a}`, the other `{b}` (step 1). `grief`: the mourner is `{a}`, the dead being is `{b}` (name from `stats.deaths_list`, 5.1). Names are `Being.name`; the texts are filled by replacing `{a}` and `{b}`, then the place sentence, if any, is appended after one space.
Kind names in the log: `rel_friends`, `rel_found_friend`, `rel_close`, `rel_close_crew`, `rel_drifted` (both drift types), `rel_grief`. Each logged entry carries `being_id` (`{a}`), `other_id` (`{b}`), `place` (place string, or "" for drift and grief) and `building_id` (the room's id for room places, else null), so a later view can focus the camera (deferred, section 19).
Why so few lines: at 160 beings and roughly one birth a sol, newborns' first friendships alone give about one line a sol (E). Friendships between beings who already have friends are not news; first friendships, first close bonds, the end of a close bond, the crew drifting and grief are.
**Log eviction (checked).** `SimWorld._log` evicts the oldest entry once the log passes `colony.log_cap` (500), whatever its kind (`pop_front`). Relationship lines are therefore never evicted ahead of other lines, and eviction changes no bond and no stat. The binding visibility limit is the 8-line log panel, not the 500 cap. No separate ring buffer: the run-wide record a later view or Task 5 would need is in `stats.relationships` (firsts, counts, per-sol shares). Test 10 proves the kind-blind eviction.
**Log pollution (consequence, checked).** Relationship lines share the 500-entry log with the age, died, born and other lines, so those older lines are evicted sooner than in Task 3 (at the expected 1 to 2 relationship lines a sol plus grief, roughly a few hundred extra entries over 300 sols; E). Nothing in the sim reads the log, so no behaviour changes. What can change: (a) existing tests that scan `w.log` for a kind after a long run, or assert an exact log size or "nothing logged" over a stretch of steps, may now see relationship lines or miss evicted ones. The implementer runs the whole suite with the module on; any such test either filters by kind or sets `relationships_enabled = false`, and the change is listed in the task log (no test is weakened silently). (b) `tools/age_probe.gd` timing restores the log with `w.log.resize(saved size)`, which restores exactly only while the log is under the 500 cap; at the cap a logged age line evicts one entry and keeps the size. That loop measures time only and nothing reads the log, so its numbers are unaffected; the probe's header line should state the log size and cap so a reader knows which case applied. Neither point is a reason for a separate relationship log.

## 6. Numbers, and what they imply (all E)
Tick of 1 h; a pair "together" for h awake hours per sol and apart for the other 24.66 - h hours. **Assumption for every figure below unless stated: both beings restless 0.4, so the decay factor is 0.5 + 0.4 = 0.9 and the open decay rate is 0.0005 x 0.9 = 0.00045 per hour.** Figures are rounded and computed per sol (growth hours, then decay hours), not tick by tick. Revision 3 recomputed this section (code review item 3); revision 2's 7.4 h, 9 sols, 25 sols and 146 sols were arithmetic errors.
- Typical pair: warmth 0.4 each, affinity 0.8. Growth constant per hour together: 0.008 x (0.2 + 0.4) x 0.8 = 0.00384.
- Hours together per sol needed to reach a friendship at all (balance point bond = 0.30): 0.00384 x 0.7 x h = 0.00045 x (24.66 - h), so h = 0.01110 / 0.00314, about 3.5. Warm, like-rhythmed pair (warmth 0.6, affinity 1.0; k = 0.0064): about 2.3 h. Cold, clashing pair (warmth 0.25, affinity 0.5; k = 0.0018): 0.00126 h = 0.00045 x (24.66 - h), about 6.5 h; if the clashing pair is also restless (mean 0.7, decay 0.0006 per hour), about 8.0 h. Personality therefore decides who becomes friends at the same exposure, which is the point.
- Roommates who share about 10 awake hours a sol: per sol, growth keeps 0.9623 of the gap to 1 and decay removes 0.0066, so an open pair settles near 0.83; once close, decay is a quarter and the pair settles near 0.96. A pair sharing one hour a sol never bonds.
- From a fresh pair, 10 h a sol together, a typical pair crosses the friend line after about 12 sols (gap to 0.83 shrinks by 0.9623 a sol: ln(0.825 / 0.525) / 0.0385) and the close line after about 34 sols (ln(0.825 / 0.225) / 0.0385). A crew pair starting at 0.35 reaches close after about 19 sols. The probe measures all three (13, item 5). The O4 (b) figure "about sol 9" in section 18 is kept as posed; recomputed it is about sol 12, which does not change the comparison the owner decided on.
- A friendship at 0.30 left alone falls below the drop line 0.15 after 0.15 / 0.00045 = 333 h, about 13.5 sols. A close bond at 0.60 left alone decays at `close_hold` x the open rate, 0.25 x 0.00045 = 0.0001125 per hour, and needs 0.20 / 0.0001125 = about 1,780 h (72 sols) to fall to the close drop line 0.40; the close flag then clears and the open rate takes it from 0.40 to 0.15 in 0.25 / 0.00045 = about 556 h (22.5 sols). A close friendship that ends completely therefore takes about 95 sols of total separation to end, and the `drifted` line comes at the end of that. Founder crews who never share a room lose the friend flag after about 18 sols of separation (0.35 to 0.15 = 0.20 / 0.00045 = 444 h).
- Kin seed: a newborn of mean warmth 0.4 with a parent of 0.4 starts at 0.30 + 0.25 x 0.4 = 0.40; the warmest possible pair at 0.55, the coldest at 0.30 (friends at birth, and the first to drift if the two are apart).
- Lines (E): cap 3 a sol to pop 159, 4 at 160; with the queue, the expected rate is about 1 capped-kind line a sol at 160 beings, 0.3 to 1 early on. Probe floor target: at least 1 line per 5 sols on average over sols 20 to 300.
- Crew close lines: founders sharing the habitat at landing (4 of them, about 10 h together a sol) reach close near sol 15 to 25 (from 0.35), so the first relationship line of a founder world is expected in that window, not near sol 20 at the earliest as in revision 1.
- These figures assume the 1-h sample is representative of the hour; it is a sample, not an integral. The probe compares it with a per-step count on one seed (section 13). Measured: over sols 1 to 60 the sample totals within 0.25 percent of the per-step count (seeds 42 and 7); per pair per sol it is poor (median error 8 to 11 percent) and averages out over sols.

### 6.1 What the probe measured, and what it changes in this section (revision 5)
The arithmetic above is right; the exposure it assumed is not. "Together" counts only awake hours inside the same building, and beings spend much of the awake day walking, outside, at work and sleeping. Measured median hours together per sol (pairs alive at sol 300, shipped run, five seeds): **friend pairs 1.7 to 2.7 h; non-friend pairs that ever shared a room 0.8 to 1.7 h.** The "10 h a sol" roommate case is the exception (founders at landing), not the typical pair. Restated figures, same assumptions (restless 0.4 each, room_rate 0.008):
| Pair | Hours a sol to **reach** the friend line 0.30 | Hours a sol to **stay above** the drop line 0.15 |
| --- | --- | --- |
| typical (warmth 0.4, affinity 0.8; k 0.00384) | about 3.5 | about 3.0 |
| warm, like-rhythmed (warmth 0.6, affinity 1.0; k 0.0064) | about 2.3 | about 1.9 |
| any close pair (decay x 0.25), held above the close drop 0.40, typical k | | about 1.1 |
So the measured friend-pair median (1.7 to 2.7 h) is what the model predicts: the friendships that exist are the warm and like-rhythmed pairs holding above the drop line, plus close, kin and crew pairs held by `close_hold`. The 3.5 h figure is the formation threshold of a typical pair and was never meant as the friend-pair median; it stays, now labelled as such. Most acquaintances (0.8 to 1.7 h) sit below every formation threshold and never become friends: friendship is selective, and personality does the selecting (warmest third has more friends on every seed and run).
**Time to a friendship at realistic exposure** (from bond 0, per-sol model, `b* = 1 - D / (k h)`, `t = -ln(1 - 0.30 / b*) / (k h)` sols, with `D = 0.00045 x (24.66 - h)` the decay per sol):
| Pair, hours together a sol | room_rate 0.008 (shipped) | room_rate 0.010 (next run, section 13) |
| --- | --- | --- |
| warm, 3 h | about 49 sols | about 29 sols |
| warm, 4 h | about 25 sols | about 17 sols |
| warm, 5 h | about 17 sols | about 12 sols |
| typical, 4 h | about 93 sols | about 45 sols |
| typical, 3 h | never (below 3.5 h) | about 180 sols (in practice never) |
| typical pair's formation threshold | about 3.5 h | about 2.9 h |
The warm 4 h row (25 sols) matches the measured median wait of a newborn for its first grown friendship (25 to 29 sols on the five seeds), which is the best evidence that the growth model behaves as specified. The "about 12 sols" of the 10 h bullet above is correct for 10 h and should not be read as the typical wait.

## 7. The trust reading (once a sol)
At each sol boundary, `on_sol(world)`:
1. Build the web from `friends` pairs; find connected parts with a union-find over ascending ids.
2. `web_share = size of the largest part / pop`; `second_share = size of the second-largest part / pop` (0.0 if there is no second part of size 2 or more); `lonely_share = lonely beings / pop`; `friends_mean = 2 x friend pairs / pop`. At pop 0 all are 0.0.
3. Append `web_share` to `stats.relationships.web_by_sol`, `second_share` to `second_by_sol` and `lonely_share` to `lonely_by_sol`, and store the latest values (and refresh `pairs`, `friend_pairs`, `close_pairs`). Exactly one entry is appended per pass through the `if _sol_started:` block of `step()` while the module is enabled, the same block that appends to `pop_by_sol`, plus the one initial reading `begin` appends on a founder world, where `_init` also appends the initial `pop_by_sol` entry (section 4). So on any world stepped from creation with the module enabled throughout, all three lists have the same length as `pop_by_sol` (founder world: both start at 1; blank world: both start at 0). A direct call of `on_sol` (test staging) appends exactly one entry. The spec does not equate that length with `world.sol()`; tests compare with `pop_by_sol` or count the boundaries they step through.
Why largest part: a colony where everyone has a friend but the friendships form two islands is not a colony that trusts itself; Task 5 can read islands as the seed of factions (HANDOFF 7, Council: "factions by personality"). `second_share` is there because one bridging being can hold `web_share` at 1.0 over two camps; a rising second part is the first sign of a split. This spec does not decide what share counts as "trust has formed"; Task 5 owns that rule and reads the per-sol lists with its own window, as it reads `age_history`.
**Islands: wanted, within limits.** Camps by temperament are raw material for Task 5 factions and are not a failure. What is not wanted is a colony of newborns left outside every camp. The probe checks the second, not the first (13, item 7).

## 8. Behaviour effect: friends draw each other, lonely beings seek company (built, shipped off)
In `Being._restless_travel`, the weight of each neighbour building becomes
`v = room_pull.floor + pow(trait x mult, exponent) + effects.friend_pull x min(friends_there, effects.friend_pull_cap) + L`
where `friends_there` is the number of ids in `world.relationships.present[neighbour id]` that are `friends` with this being, and `L = effects.lonely_pull x min(people_there, effects.friend_pull_cap)` if this being's `friend_count` is 0, else 0 (`people_there` = all ids in `present[neighbour id]`). The snapshot is at most one tick, 1 h, old; it is deterministic.
- **Guard.** The two terms are computed only when `world.relationships` is not null, `world.relationships_enabled` is true, and at least one of `effects.friend_pull`, `effects.lonely_pull` is above 0.0. Otherwise no term is added and nothing is read (a `Being` used without a world, or a world with the module disabled, behaves exactly as in Task 3). A neighbour building with no entry in `present` counts 0 friends and 0 people. `friend_pull_cap` 0 makes both terms 0.
- Shipped values `effects.friend_pull` = **0.0** and `effects.lonely_pull` = **0.0**. When both are 0.0, neither count is computed and no term is added, so the weights, the draws and every decision are bit-identical to Task 3 (also true numerically, since adding 0.0 is exact; skipping is for cost). Hashes unchanged.
- Probe values `balance.probe_friend_pull` = 0.25 and `balance.probe_lonely_pull` = 0.15 (E), cap 3: at the cap a room gains 0.75 for friends (0.45 for a lonely being drawn to people), against a floor of 0.15 and a trait term of 0 to about 0.5. **Draws:** the pull changes only the weights inside the existing weighted pick, so each travel decision makes the same draws as in Task 3. It changes which room is chosen, and from then on the world diverges: later decisions happen at different times and in different states, so the total number and order of draws over a run differ too. The five table hashes change.
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
  No view RNG draw is added. `stranger_talk_share` 1.0 restores the Task 3 behaviour exactly (test 16).
  **Result shape (revision 4, unchanged from Task 3).** `_talk_flags()` still returns a Dictionary from being id to a Dictionary. A being is talking **if and only if its id is a key**; a stranger in the idle-front part of its cycle has **no key** (it is omitted, not given a "talking: false" entry), exactly as a being with no partner in range has none today. The `first` value is unchanged: `id < partner id`. Extra keys inside a being's entry are tolerated by callers and tests; no caller may rely on them.
  **Pairing is unchanged and not always mutual.** `_talk_flags` gives each paused being one partner: the lowest-id awake being within the radius. A and B can pick each other, or A can pick B while B picks C. The rule above is applied per being to the unordered pair (being, partner): `are_friends` is symmetric and the phase uses the pair's lower id, so when two beings pick each other they always show the same state (both talking or both idle-front). When the choice is not mutual, each being shows the state of its own pair, as Task 3 already allows. Known limit: a being whose lowest-id neighbour is a stranger shows the stranger rhythm even if a friend also stands in range. Preferring a friend as partner would change the `first` flag at share 1.0 and break the Task 3 equality, so it is deferred (section 19) until a screenshot review shows it matters. This replaces revision 1's friends-only binary, which all three reviewers expected to read as a bug: a room never looks frozen, and a player who watches a while sees that some pairs keep talking.
- No new HUD line, no colony-wide word, no meter. HUD room at 720p is already tight (ages.md 18, item 7).
- No new art; texture memory is 47.1 of 48 MB (Q10).
### 10.2 Stats: `stats.relationships` (run-wide, never windowed, never reset; never shown)
| Key | Definition |
| --- | --- |
| `friendships_formed` | `friends` false-to-true crossings of pairs that are neither `kin` nor `crew` (new friendships; seeds never count) |
| `friendships_renewed` | `friends` false-to-true crossings of `kin` or `crew` pairs whose seeded flag had lapsed (5.5); never a line |
| `close_formed` | `close` false-to-true crossings, any pair |
| `drifted` | `friends` true-to-false on `was_close` pairs (crew or not) |
| `crew_drifted` | `friends` true-to-false on `crew` pairs (a crew pair that was close counts here and in `drifted`), whether or not a line was made |
| `lines` | `{friends, found_friend, close, close_crew, drifted, grief}` logged line counts (the form actually logged) |
| `lines_capped`, `lines_dropped`, `lines_stale` | events first put into `pending` by the cap (once per event); dropped from a full queue; dropped at offer time by revalidation (5.6 step 1, queued or new) or because a named being died (5.1). Silent crew drops that never became events (5.5) are in none of these |
| `first_friendship_sol` | elapsed sol of the first crossing counted in `friendships_formed`, null before (renewals of kin or crew pairs never set it) |
| `first_mars_born_friendship_sol` | elapsed sol of the first crossing counted in `friendships_formed` with at least one Mars-born being, null before |
| `pairs`, `friend_pairs`, `close_pairs` | current counts, refreshed at each sol reading |
| `web_share`, `second_share`, `lonely_share`, `friends_mean` | latest sol reading |
| `web_by_sol`, `second_by_sol`, `lonely_by_sol` | one float per pass through the sol block with the module enabled, plus the initial reading at creation on a founder world; same length as `pop_by_sol` on a world enabled from creation (sections 4, 7) |
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
| Pull above 0.0 (probe or owner) | same draws per travel decision; different choices, so later draws over the run differ in number and order (section 8) | being behaviour | **changes all five hashes**; needs the owner's baseline reset (O1) |
| Talk gradient (10.1) | none (view, `real_time` only) | none (view) | none |
Proof, as in ages.md 12: the balance table gains one trailing column `web` (2 decimals, the latest `web_share`) after `age`. Removing the last two fields reproduces the five Task 1 hashes 02032b23..., 830c7d0c..., 0e3e83a7..., bca6eb2c..., 2645033a...; removing only `web` reproduces the Task 3 table hashes recorded in `docs/balance/task-3-log.md` (42 da166c4f8b202820, 7 30c53f90949d979b, 99 54ad1e15b934bf9a, 1234 7052c92936a75157, 2026 67e3dcf057200eb9), which also proves the age crossings are unchanged. Plus the purity test (section 14, test 13).
**Automated proof: `tests/relationships_hash_proof.gd`** (new; modelled on `tests/age_hash_proof.gd`; like it, NOT a unit test: it does not start with `test_` and is not run by `run_tests.gd`, because five 300-sol runs take minutes). Run as `godot --headless --path station-zero --script res://tests/relationships_hash_proof.gd [-- --seed N ...]`. For each seed (default all five) it runs `balance_lib.run(seed, 300, {}, 30)`, takes the table body exactly as `age_hash_proof.body_of` does, and computes two hashes (first 16 hex digits of `sha256_text` of the body joined with newlines):
1. **drop web**: delete the final field (`web`) of the header and each row; compare with the Task 3 hash for that seed (the five values above, copied into an `EXPECTED_T3` constant with `docs/balance/task-3-log.md` cited).
2. **drop web and age**: delete the final two fields (`web`, then `age`); compare with the Task 1 hash (`age_hash_proof.EXPECTED`, reused by reference, not copied).
It prints one line per seed with both hashes, both expected values and MATCH or DIFFERENT, and exits 0 only when every requested seed matches both. A strip helper refuses to strip a field whose header name is not the expected one (`web`, then `age`) and reports "column absent" instead, so a reordered table cannot pass by accident. The helpers are static so test 17 can check them on synthetic tables without a 300-sol run. It is run once before the module exists (the `web` column absent: both checks report it absent, check 1 hashes the Task 3 table as it is and must give the Task 3 values, and check 2 reduces to the Task 1 proof of `age_hash_proof.gd`) and again with the module and column in place; any DIFFERENT rejects the step. The run with a pull above 0.0 (probe) is expected to differ and is not run through this tool.

## 13. Calibration probe (`tools/relationships_probe.gd`, read-only)
Runs the real module on seeds 42, 7, 99, 1234, 2026 to sol 300, three times: shipped (both pulls 0.0); friend pull only (`probe_friend_pull`, lonely 0.0); friend and lonely pull (`probe_friend_pull`, `probe_lonely_pull`). Pull runs use the data override seam, never by editing data. Writes `docs/balance/task-4-calibration.md` with, per seed and run:
1. `first_friendship_sol`, `first_mars_born_friendship_sol`, the sol of the first relationship line; counts of each line kind and of capped, dropped and stale events; lines per sol, max and mean; mean lines per 5 sols over sols 20 to 300.
2. `web_share`, `second_share`, `lonely_share`, `friends_mean` at sols 30, 60, 100, 150, 200, 300; the number of web parts of size 3 or more at sol 300.
3. Personality check: mean friend count of the warmest third against the coldest third (by `warmth`) at sol 300; mean bond age of friendships by mean pair `restless` (top third against bottom third).
4. Work check (emergence review): the same warmest-against-coldest friend count, split by beings' share of awake hours spent on the site or mining (top half against bottom half). Revision 5: **reported only, no trigger.** Measured, the work-heavy half spends about 3 percent of awake hours on the site or mining (mean 0.027 to 0.039), so work growth is a minor source of bonds in this sim and the split cannot separate work-heavy beings from the rest. The `grow.work_rate` concern (warmth does not enter work growth) stays recorded; it is reopened only if a later task makes work a large share of the day.
5. Hours together per sol for friend pairs against non-friend pairs (median), to check the section 6 arithmetic.
6. The 1-h sample against a per-step count of together hours on seed 42 (sols 1 to 60): relative difference per pair, median and 90th percentile.
7. With a pull on: the same, plus the mean friend count of the loneliest third of beings born after sol 100 (at sol 300) against the shipped run; age settlement and fall-back sols, population at 300, deaths by cause, and the table hash differences, so the owner sees the full cost of switching it on.
8. Newborns alone (revision 5; the kinless count is kept as a line but measured 0 everywhere, section 5.2): (a) **unmoored newborns**: newborns whose kin pair lost its `friends` flag, or whose parent died, before their first grown friendship; their share of births, and their median sols from that moment to a first grown friendship (resolved / unresolved at sol 300); (b) kin newborns' median sols from birth to first grown friendship (shipped, seeds 42, 7, 99, 1234, 2026: 28, 25, 29, 26, 29 sols); (c) newborns born after sol 100 and alive at 300 with zero friends, count and share of that cohort (shipped: 0.34, 0.03, 0.24, 0.15, 0.33). Reported, not judged; (c) is the evidence for the pull decision (section 17).
9. Tick cost: median and maximum microseconds per tick at pop around 70 and around 160, and stored pair count; step cost with and without the module; the split between growth (pairs in `present`) and the decay walk (all stored pairs). Revision 5 adds: p95 tick at pop above 120, and the module's share of the mean step cost at pop above 120 (`(with - without) / without`).
10. Log share: relationship lines as a share of all log entries over the run, and the sol of the oldest entry still in the log at sol 300, with and without the module (the pollution note of 5.6).
**Tick cost (revision 5 decision: restated budget, no remedy built in Task 4).** Revision 1 to 4 targeted "under 1 ms median at pop 160", from an estimate ("under 2% of a 2.6 ms step"), not from a frame requirement. Measured: real run, seed 42, pop above 120: tick median 5.97 ms, p95 9.1 ms, max 19.8 ms, stored pairs median 2,876 (max 4,389); padded profile world (pop 159, 5,278 pairs) after the behaviour-identical optimisation: 4.7 ms median (decay walk 3.25 ms, growth 0.75 ms), max about 10 ms. The tick runs once every 20 steps, so the module adds about 0.3 ms to the mean step: measured mean step 2,479 us with the module against 2,154 us without at pop above 120 (+15 percent). The requirement that actually binds is the frame: `sim.advance_budget_ms` = 8.0 (ages.md section 11: a 60 fps frame is 16.7 ms, the view takes the rest), and `advance()` may overshoot its budget by one step. A step that carries a tick costs about 2.3 + 6 = 8.3 ms in the median: the advance loop stops after it, so that frame runs one step instead of about three. The player sees at most a small dip in achieved speed (the speed readout already reports the truth) and, at the tick maximum, an occasional long frame. **Restated budget (lead, E):** at pop above 120 in a real seeded run, (1) tick median at or under `sim.advance_budget_ms` (8.0 ms); (2) the module's share of the mean step cost at or under 20 percent; (3) no remedy is built unless the view step (plan step 8, frame time re-measured) shows frame p95 over 16.7 ms attributable to tick steps, or a later calibration run reaches more than 8,000 stored pairs or a tick median over 8 ms. Measured: (1) 5.97 ms PASS, (2) 15 percent PASS.
Why not the two remedies fixed in advance (both re-examined against the measurements):
- **`decay.slices`** (rejected for Task 4; the key is not added). Revision 3 claimed sliced bonds "match the unsliced run except near the 0 floor". That is wrong: decay skips every pair that grew this tick (5.5), so a pair whose slice tick falls on an hour it is together skips N hours of decay, and a pair apart on its slice tick is decayed for N hours including hours it was together. Bonds then differ pair by pair everywhere, unbiased only on average over many sols, and flag crossings move by up to N - 1 ticks either way. It is a behaviour change to the record, with its own calibration, to save about 2.4 ms (N = 4) that the frame does not currently need.
- **`tick_h` 2.0** (rejected as a cost remedy). It halves the amortised cost (one tick per 40 steps) but not the per-tick cost: each tick still walks every stored pair, so the long frame is unchanged. It also halves the togetherness sample, which is already poor per pair per sol (item 6).
- **If a remedy is needed later** (trigger (3) above), the order is: first the behaviour-identical change the profile found (keep bonds only in the packed mirror and read them through a query, about 1.2 ms saved; it changes the test contract `pairs[key].bond`, so it needs a spec revision of section 3 and test updates, no calibration); second, a lazy closed-form decay (a pair's decay is computed from the ticks since it last grew, which are exactly its apart ticks, with the rate change at `close_drop`), which needs its own spec revision, a periodic sweep so drift lines are not delayed, and a calibration run. Not slicing, not `tick_h`.
**Target note (revised).** On a founder world all 21 founder pairs start as friends, so the first crossing counted in `friendships_formed` needs a being who is not a founder: measured, it is a Mars-born being in all 15 runs (`first_friendship_sol` equals `first_mars_born_friendship_sol` everywhere). The first birth came at sol 9 to 37 (13 to 26 shipped), not near sol 8, so "first grown friendship before sol 20" was a target error. It is replaced by a single target measured from the first birth.
**Paired runs.** With both pulls at 0.0 the module changes nothing beings do (section 12), so a run that changes any `relationships.*` sim key on a seed plays out the same colony as the shipped run on that seed: same births, deaths, rooms and hours together. Differences in relationship stats between the two runs are caused by the key alone. This makes the one-key-per-run loop below a paired comparison, unlike the pull runs.
Any recalibration edits `data/relationships.json` only, one key per run, chosen by the lead (HANDOFF section 10). Edits to `balance.*` target keys are not sim parameters (they change no run); they are made in their own commit before a parameter run so the run is judged by the restated targets.
**Targets (revision 5; E until a run confirms them):**
| # | Target | Status on the shipped run | Why this value |
| --- | --- | --- | --- |
| R1 | First grown friendship within `balance.first_friend_gap_sols` (30) sols of the first birth, every seed (replaces "before sol 20" and "first Mars-born friendship within 15 sols of the first birth") | gaps 32, 15, 42, 20, 36: FAIL on 42, 99, 2026 | The colony's first new friendship is the earliest among its first newborns, so it should come no later than the median newborn's wait (measured 25 to 29 sols). 15 assumed a newborn shares about 10 h a sol with someone; measured exposure is 2 to 4 h (6.1). Still failing on 3 seeds: a genuine signal, addressed by the next run |
| R2 | First relationship line before sol 30 on a founder world | 21, 16, 19, 21, 14: PASS | Kept. It passes through crew lines (close or drift), which is intended: O4 seeded the crew so the first sols have a social voice before any newborn can make a friend. The newcomer story is R1 |
| R3 | `lonely_share` mean over the last `balance.lonely_window_sols` (50) sol readings at or under `balance.lonely_share_max` (0.35); **no lower bound** | at sol 300: 0.396, 0.028, 0.293, 0.120, 0.365: by snapshot FAIL on 42 and 2026 (the window mean is for the next run to measure) | The upper bound is the "newborns left outside every camp" failure of section 7, and seeds 42 and 2026 show it: a third of their post-sol-100 newborns have no friend at 300. The window removes snapshot noise (the share moves by up to 0.1 in 50 sols). The lower bound 0.05 is dropped: a small warm colony where almost no one is alone (seed 7, pop 72, 2 lonely) is a good story, not a failure; saturation is caught by R4 |
| R4 | `friends_mean` at sol 300 between `balance.friends_mean_min` (1.0) and `balance.friends_mean_max` (**15.0**, was 12.0) | 2.01, 12.67, 1.78, 7.56, 1.28: PASS at 15 (seed 7 failed at 12) | Above the band "friendship means nothing". 15 follows the published layered-network finding in anthropology (Robin Dunbar and colleagues, for example Zhou, Sornette, Hill and Dunbar 2005 on discrete group-size layers: circles of about 5, 15, 50 and 150; cited from memory, the layer sizes are approximate), where about 15 is the outer edge of the people one is close to; a "friend" here should fit in that circle. It separates the small-village case (seed 7, 12.67) from true saturation under the friend pull (seed 1234, 37.27; seed 2026 both pulls, 16.03) |
| R5 | Dropped events under 5% of capped-kind events, where capped-kind events = capped-kind lines logged + `lines_dropped` | 0 everywhere: PASS | Kept, definition pinned. The cap binds 0 to 3 times a run, so this guards the queue rather than tests it |
| R6 | At least 1 capped-kind line per 5 sols over sols 20 to 300 | 2.05, 1.04, 2.12, 2.43, 2.00: PASS | Kept |
| R7 | Warmest third has more friends than the coldest third, every seed | PASS on all 15 runs | Kept |
| R8 | Tick cost: restated budget above | PASS | See "Tick cost" |
| R9 | Pull (not shipped; owner decision): replaces the loneliest-third comparison | not judged | The old comparison set two diverged colonies' cohorts (n 20 to 115) against each other, so it measured divergence, not the pull. For any future pull run: zero-friend share of post-sol-100 newborns (item 8 (c)), mean over the five seeds, not above the shipped mean; and R4's upper bound on every seed (saturation guard) |
T11 (section 14) judges R3 and R4 from the data keys; R1, R2 and R5 to R9 are probe targets.
**Next run (revision 5 decision; one key, five seeds, 300 sols, shipped pulls 0.0).** `relationships.grow.room_rate` **0.008 to 0.010**. Reason: R1 and R3 fail for one cause, new friendships form too slowly at the exposure beings really have (6.1): a warm pair at 4 h a sol needs about 25 sols, a typical pair about 93. At 0.010 these become about 17 and 45 sols, and a typical pair's formation threshold falls from about 3.5 to 2.9 h, still above the measured acquaintance median (0.8 to 1.7 h), so friendship stays selective. Expected effect (E): newborns' median wait about 17 to 21 sols (from 25 to 29); first-birth gaps about two thirds of today's (roughly 22, 10, 29, 14, 25, so R1 passes on all five, seed 99 narrowly); `lonely_share` down on 42 and 2026 (R3 passes); `friends_mean` up on every seed. Risk: seed 7 (12.67 today) may pass 15 (R4). Why this key and not the others: `decay.per_h` 0.0004 would move the formation threshold the same way but also make every friendship, kin and crew bond last longer, which weakens the restless-drift story and inflates `friends_mean` more on seed 7; `seed.kin_base` or `kin_warmth` would lower `lonely_share` only by keeping kin longer, a cosmetic fix that creates no new friendship (R1 untouched); `grow.warmth_base` would change growth for every pair and dilute the personality contrast (R7). Rule for the run after (stated now so it is not chosen after seeing numbers): if R1 and R3 pass and only seed 7 breaks R4, the next single run is `room_rate` 0.009; if R1 still fails on 2 or more seeds, the lead re-reads the hours-together data before choosing a second key. Because the runs are paired (above), the hash proof's old-column checks must still MATCH on all five seeds (only the `web` column may change).

## 14. Tests (`tests/test_relationships.gd`, written first, red; no test with zero checks)
Staging: blank world, reactor, two habitats, workshop and green room built; beings added with `add_being`, then traits overwritten per test; state, `building_id`, `job`, `mine` set directly; ticks driven with `relationships.on_step(world, tick_h)` or by stepping 20 steps.
1. Room growth recurrence: two awake beings in one habitat, 10 ticks; bond equals the recurrence `b = b + k x (1 - b)` with `k` computed in the test from data and traits (tolerance 1e-12), from 0.
2. Personality: warm pair > cold pair after 10 ticks; equal-tempo pair > clashing pair; a clashing pair with one curiosity 1.0 is at exactly the softened affinity; a fully clashing pair is held at `affinity.floor`.
3. Not together: different buildings; one asleep; one in `transit`; one outside: no growth and decay applies.
4. Work: two `work` beings on the site grow at `work_rate` with warmth not entering (two cold beings grow as fast as two warm ones); two miners on the same field grow, on different fields do not; a pair never grows twice in a tick.
5. Decay: restless pair loses more per tick than a steady pair by the formula; a close pair loses `close_hold` of the open rate; a non-flagged pair that decays under `forget_below` is removed; a fresh pair whose first growth leaves it under `forget_below` is kept in that tick.
6. Hysteresis: friends set at exactly `lines.friend`, kept at 0.20, cleared at just under 0.15; close set at 0.60, kept at 0.45, cleared under 0.40.
7. Crew: a founder world has 21 pairs at `seed.crew`, all `friends` and `crew`, none `was_close`, and logs no relationship line at creation; a blank world has no pairs. A crew pair crossing close logs `close_crew` (no place sentence); a second crew pair sharing a founder with it logs nothing; a crew pair losing the friend flag logs `drifted` once per founder (a second drop involving a named founder is silent and counted in `crew_drifted`).
8. Kin: a newborn with a living parent gets the kin pair at the next tick at exactly `kin_base + kin_warmth x` mean warmth (no decay or growth in its creation tick, 5.2, so this holds with the shipped decay; the shipped tests also set `decay.per_h` 0, which is compatible), `friends` true, no line, no `friendships_*` count; a dead parent or `parent_id` 0 gives none.
9. Death and grief: pairs of the dead are removed at the next tick; with three living friends at bonds 0.7, 0.5 and 0.5 (ids 9 and 4), the two lines name the 0.7 mourner then id 4; no grief when every bond is under the friend line; grief lines are never capped or queued; a pending event naming the dead is dropped.
10. Lines and queue: `friends` only for a grown pair where one has not found a friend; never for kin or crew; one new being gives the `found_friend` form with the new being first, two new give the `friends` form; the place sentence matches the room kind, `site`, `ice`, `pit` and the `other` fallback; `close` only for the first close of both; `drifted` only for `was_close` or the crew rule. Cap: 5 friend events in one sol at pop 20 log 3, queue 2; at the next sol the 2 queued lines log first, and `lines_capped` is 2, not more, after a queued event waits through a second full sol; a queued event whose pair lost the flag is dropped as stale; a fourth queued event drops the oldest; a being whose friend event was dropped has no `found_friend` entry and its next friendship gets the line. Cap scaling: at pop 160 the cap is 4, at 159 it is 3. Every text from data, rendered with sample names, has no digit and no `%`. Eviction: after 520 lines of another kind the log holds 500 and the oldest are evicted first whatever their kind; bonds and stats are unchanged.
11. Sol reading: staged webs (chain of 5, two islands of 3 and 4, 2 lonely) give the exact `web_share`, `second_share`, `lonely_share`, `friends_mean`; one entry per boundary; pop 0 appends 0.0 and divides by nothing.
12. Pull (probed through `Being._restless_travel(world)` itself: the test replaces `world.rng` with a stub whose `chance` is always true and whose `randf` returns a set value, bisects the value at which the pick switches neighbour, and derives the weights from that boundary; so the pull must enter only the neighbour weights of the existing weighted pick in `_restless_travel`, with no extra draw and no other decision path): at 0.0 / 0.0 the weights and the next 1,000 draws equal those of a world with the module disabled; at friend 0.25 a neighbour's weight rises by exactly 0.25 per friend up to the cap; at lonely 0.15 a being with no friend gains 0.15 per person present up to the cap, and a being with one friend gains nothing from it.
13. Purity, seed 42, 10 sols: worlds with `relationships_enabled` true and false have equal old `stats` keys, equal beings (id, building, state, energy), equal stocks, and equal next 1,000 `rng` draws; two same-seed worlds have identical `pairs`, `pending` and `stats.relationships`.
14. Tick timing: one tick every 20 steps; after N whole sols the tick count is floor(N x sol_h / tick_h) within one. A tick is observed either by the `ticks` counter (section 3) or by the reset of `acc_h`; the shipped tests use the `acc_h` reset.
15. Key-path parity for `relationships.json` (section 15), both ways, and every data sanity rule of section 15 (each rule checked on the shipped data, and each rule shown to fail on one deliberately broken copy through the override seam).
16. View. Staging: a blank world with one habitat; three beings added and set awake inside it; the friend pair made through the module's test seam `relationships.debug_set_bond(a, b, bond)` (sets the bond, applies the flag rules and `friend_count`, logs nothing; used by tests only); the view model's interior positions placed so each paused being's lowest-id neighbour within `talk_radius_px` is the intended partner (A and B mutual, C alone with B out of range for the stranger case), and `real_time` set directly. Checks: a friend pair talks at every sampled `real_time` in a 5-s cycle, and both beings of a mutual pair show the same state at every sample; a non-friend pair talks in a share of 100 evenly spaced samples within 0.02 of `stranger_talk_share`; two non-friend pairs with different `lo` are not in phase; with `stranger_talk_share` 1.0 `_talk_flags` equals the Task 3 output on the same staging; the HUD source reads no bond value.
17. Hash proof helpers (section 12) on synthetic tables: a table with `age` and `web` gives the same "drop web" body as the same table without `web`, and the same "drop web and age" body as the table with neither; a table whose last field is not `web` reports the column absent and strips nothing; a table with `web` but no `age` before it reports `age` absent for check 2.
18. Friend form at log time (ids 1 to 5, all new, cap already full in sol N): (a) one tick in sol N emits (1,3) and (1,5), both queued; at the first tick of sol N + 1, (1,3) logs in the `friends` form and (1,5) logs as "{5} has found a friend in {1}." with the place recorded at emission; (b) one tick in sol N emits (1,3) and (2,5), a later tick emits (1,5), all three queued; in sol N + 1, (1,3) and (2,5) log, and (1,5) is dropped because neither is new, with `lines_stale` + 1; (c) within one tick, two new events A-B and A-C with A, B, C all new: the first logs as the `friends` form, the second as "C has found a friend in A."; (d) no logged line ever names as `{a}` of a `found_friend` line a being already in `found_friend` (checked over a 60-sol seeded run).
19. Crew drift at revalidation: two crew drift events sharing founder F are created in the same tick under a full cap and queued; at the next sol the first logs and names F; the second is dropped as stale (`lines_stale` + 1) and `crew_drifted` counts both; a crew drop when F is already named makes no event and moves only `crew_drifted`; a crew pair that was close logs through `drift_close` and leaves `crew_drift_named` unchanged.
20. Grief order: in one tick with a full cap and a queued friend event, a death with two mourners logs both grief lines before anything else of that tick, the cap count is unchanged by them, and the queued event is still offered after.
21. Cap reset: 3 capped lines logged late in sol N; the first tick of sol N + 1 resets `lines_this_sol` to 0 and logs a queued event; a tick later in sol N with no events leaves the count at 3.
22. Pull guard: a `Being` making a travel decision with `world.relationships` null, or with `relationships_enabled` false and the pulls set above 0.0 through the override seam, produces the Task 3 weights exactly; a neighbour with no `present` entry adds 0; `friend_pull_cap` 0 adds 0.
23. Pair key and order: the key of (9, 10) is 9 x 2^20 + 10 and sorts before (10, 11); with ids 2, 9 and 10 crossing the friend line in one tick, events are offered in ascending key ((2,9), (2,10), (9,10)), not in insertion or string order; two same-seed worlds emit identical log sequences.
24. Kin newborn line: a newborn with a living parent (kin pair, no line) that later grows a friendship with a being already in `found_friend` logs "{newborn} has found a friend in {other}."; the kin pair itself never logs a friend line.
25. Renewal counts: a crew pair decayed below `friend_drop` and grown back past `friend` raises `friendships_renewed`, not `friendships_formed`, logs no friend line and leaves `first_friendship_sol` null; the same for a kin pair.
26. Close hold arithmetic (section 6): a close pair at 0.60 with restless 0.4 each, apart for 1,777 ticks, is within 1e-9 of the closed form `0.60 - 1777 x close_hold x per_h x 0.9` (0.4000875 at the shipped values; computed in the test from data) and still close; the next tick takes it below `close_drop` and clears the flag, and the tick after decays at the open rate.
27. Existing suite with the module on: every Task 1 to 3 test passes; any test changed for log pollution (5.6) is listed in the task log with the reason. This is not a unit test: it is the run of `tests/run_tests.gd` itself (whole suite, module enabled by default), and its proof is that run's result recorded in the task log.

Balance (`tests/balance_lib.gd`): **T11** per seed at 300 sols, from `stats.relationships` only. Judged: (1) `len(web_by_sol) == len(second_by_sol) == len(lonely_by_sol) == len(pop_by_sol)`; (2) the mean of the last `balance.lonely_window_sols` entries of `lonely_by_sol` (all entries if fewer) `<= balance.lonely_share_max` (revision 5; was the sol-300 value); (3) `friends_mean` in `balance.friends_mean_min` to `friends_mean_max` (max 15.0 from revision 5); (4) `first_friendship_sol` not null. Reported: everything of section 13 items 1 to 3. T1 to T10 unchanged and must pass with the same values as Task 3.

## 15. Tunables (`data/relationships.json`; E = estimate for the probe)
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| relationships.tick_h | sim hours | 1.0 | lead, E |
| relationships.grow.room_rate | per hour together | 0.008 | lead, E (revision 5: next run tries 0.010, section 13) |
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
| relationships.balance.lonely_window_sols | sol readings averaged for the lonely target | 50 | lead, E (revision 5, new) |
| relationships.balance.friends_mean_min / friends_mean_max | friends per being | 1.0 / 15.0 | lead, E (revision 5: max was 12.0) |
| relationships.balance.first_friend_gap_sols | sols from the first birth to the first grown friendship | 30 | lead, E (revision 5, new; probe target R1) |
| art.interior.stranger_talk_share | share of time a non-friend pair talks | 0.2 | lead (view), E |
| art.interior.stranger_talk_cycle_s | real seconds per stranger cycle | 5.0 | lead (view), E |
Reused, not duplicated: `persona.traits` (sociability, care, restless, steady, curiosity), `room_pull.*` (beings.json), `Being.parent_id`, `SimWorld.STEP_EPS`, `colony.log_cap`, `interior.talk_radius_px`, `interior.talk_phase_s`. Not data: the flag names, line kinds and their emission order, the pair-key rule (`lo x 2^20 + hi`, ids below 2^20), "pop 0 reads 0.0", the phase constant 0.618034. The `balance.*` keys are read by the probe and `balance_lib.gd` only; the `art.*` keys by the view only. Revision 1's `seed.kin` and `art.interior.talk_friends_only` are removed.

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
relationships.balance.lonely_window_sols
relationships.balance.friends_mean_min
relationships.balance.friends_mean_max
relationships.balance.first_friend_gap_sols
art.interior.stranger_talk_share
art.interior.stranger_talk_cycle_s
```
`SimData.relationships()` is the accessor; `data_hash` in `tests/balance_lib.gd` adds `relationships`. Data sanity checked by test 15: `friend_drop < friend < close_drop < close`; `forget_below < friend_drop`; `0 < affinity.floor <= 1`; `seed.crew >= lines.friend`; `seed.kin_base >= lines.friend`; `seed.kin_base + seed.kin_warmth < lines.close`; `log.max_lines_per_sol >= 1`; `log.queue_max >= 0`; `log.grief_max >= 1`; `tick_h > 0` (and `tick_h >= fixed_step`, so a tick never needs two in one step); `log.pop_per_line >= 1`; `0 <= decay.close_hold <= 1`; `effects.friend_pull_cap >= 0`; `effects.friend_pull >= 0`; `effects.lonely_pull >= 0`; every rate (`grow.*`, `decay.per_h`) `>= 0`; every building kind in `buildings.json` has a `text.place` key; `0 < stranger_talk_share <= 1`; `stranger_talk_cycle_s > 0`; revision 5: `balance.lonely_window_sols >= 1` (integer), `balance.first_friend_gap_sols > 0`, `balance.friends_mean_min <= balance.friends_mean_max`.

### Edge cases
- Pop 0 or 1: no pairs grow; the sol reading appends 0.0 (pop 0) or the true shares (pop 1: web 1.0, second 0.0, lonely 1.0).
- A being dies on the tick step: handled at that tick (5.1 runs first).
- Two founders die in one tick and a third was friends with both: two grief lines for the same mourner, one per death, ascending dead id.
- A building goes offline: beings inside still count as together (the room is dark, not empty).
- A construction crew finishing: crew members `enter` the new building and become room-together there at the next tick.
- A new building kind added later without a place key: `text.place.other`; test 15 fails until the key is added.
- A queued (or same-tick) friend event that names a being whose first friendship was logged in the meantime: the form is recomputed at log time (5.6 step 1). If one of the two is still new, it logs in the `found_friend` form with that being as `{a}`; if neither is, it is dropped as stale. The form decided at emission is never used.
- A queued crew drift event whose founder was named by another crew drift line in the meantime: dropped as stale at revalidation.
- Log eviction at 500 entries is kind-blind and changes no bond and no stat.
- Ids never repeat, so a pair key never refers to two different pairs.
- Cost: pairs per tick are the sum over buildings of k(k-1)/2 for awake-inside counts k; one crowded building of 40 gives 780 pair updates, still small. Stored pairs grow with the number of people each being has shared a room with; the forget rule keeps them bounded. Revision 1 estimated under 1 ms per tick at pop 160; measured about 6 ms median in a real run (4.7 ms in the profile world), about 15 percent of the mean step. The budget is restated against `sim.advance_budget_ms` and the remedy order revised (section 13, "Tick cost").

## 16. Requests to the assistant designers (done)
Asked in revision 1 and answered in `docs/design/reviews/relationships-emergence.md`, `relationships-feel.md`, `relationships-clarity.md`; record in section 17. A second round is not needed unless the owner's answers in section 18 change the shipped behaviour (O1 (c)).
**Revision 5, short third round requested (the main session runs it; record goes in section 17, "Calibration findings").** Revision 5 changes targets, a budget and the next tuning run, not shipped behaviour or text, so a full round is not needed; three narrow questions are:
- Emergence: is dropping the `lonely_share` lower bound and moving `friends_mean_max` to 15 the right line between "a warm village" and "friendship means nothing"? Does `room_rate` 0.010 risk erasing the selectivity that makes personality visible?
- Feel: at `room_rate` 0.010 the first `found_friend` line moves from sols 34 to 68 to roughly sols 30 to 55 (E), and lines per sol rise a little. Is that the right pace for the log, given the crew lines carry sols 14 to 21?
- Clarity: the restated tick budget accepts a tick step that fills a whole advance slice and an occasional long frame (tick max about 20 ms). Is that acceptable for readability until the view step re-measures frames, or should the behaviour-identical mirror change be scheduled now?

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
### Code review (revision 3 adopted items)
Reviewer: code-reviewer, on revision 2. All items adopted; none touches an owner decision in section 18. Items 1 to 4 were blocking.
| # | Item | Decision |
| --- | --- | --- |
| CR-1 | A queued friend event kept the form chosen at emission, so it could name as "new" a being whose first was already told | A. The form and the new being are recomputed at log time for every friend event, queued or same-tick; neither new means drop as stale (5.6 step 1). Test 18. |
| CR-2 | Crew drift did not recheck `crew_drift_named` at revalidation; silent drops' stats unstated | A. Rechecked at offer time; a queued crew drift with a named founder is stale. A crew drop when a founder is already named makes no event and counts only in `crew_drifted` (5.5, 10.2). Test 19. |
| CR-3 | Section 6 hold-down arithmetic wrong (3,600 h / 146 sols); 7.4 h cold-pair figure wrong | A. Restless 0.4 stated as the assumption; close 0.60 to 0.40 is about 1,780 h / 72 sols, total to the drop line about 95 sols; cold pair about 6.5 h (8.0 h if restless); also corrected: warm pair 2.3 h, friend line about 12 sols, close about 34 sols, roommates' settle point. Test 26. |
| CR-4 | No automated hash proof; garbled "14, test 13" reference | A. `tests/relationships_hash_proof.gd` with "drop web" (Task 3 hashes) and "drop web and age" (Task 1 hashes), static helpers tested by test 17; reference fixed to "section 14, test 13". |
| CR-5 | Pair key as a sortable int; sorted emission | A. `lo x 2^20 + hi`, ids asserted below 2^20; every emitting or removing walk sorted. Test 23. |
| CR-6 | State the cost fallback in advance | A. Slice the decay first (one future key), raise `tick_h` second (section 13). |
| CR-7 | "Same number and order of draws" under the pull is too strong | A. Reworded: same draws per decision, divergent run afterwards (8, 12). |
| CR-8 | `friendships_formed` / `first_friendship_sol` undefined for kin and crew re-crossings | A. Renewals go to the new `friendships_renewed`; firsts count only non-kin, non-crew crossings. Test 25. Also noted: this makes "first grown friendship before sol 20" depend on the first birth (13, target note). |
| CR-9 | Grief was listed both in 5.1 and in the 5.6 offer order | A. Grief logs in 5.1, before the queue, outside the cap. Test 20. |
| CR-10 | The pull needs a null / enabled guard | A (section 8). Test 22. |
| CR-11 | Say kin newborns still get the found-a-friend line | A (5.2). Test 24. |
| CR-12 | Extend the data sanity list | A, plus non-negative rates and pulls (section 15). |
| CR-13 | Log pollution of age, died and born lines; `age_probe` log sizing | A as a stated consequence with handling for existing tests and a probe header note (5.6); probe item 10 measures it. |
| CR-O | Optional: talk pose pairing note and test 16 staging; "together" note; `*_by_sol` length wording; `lines_this_sol` reset; missing tests | A all. Pairing note and friend-preferring partner deferred (10.1, 19); `debug_set_bond` test seam; "together" notes (section 2); lists equal `pop_by_sol` in length (7, T11); reset rule (3); tests 17 to 27, `lines_capped` counted once per event (test 10). |
No dissent from the three assistant designers was sought: these are correctness and precision fixes that change no shipped behaviour, no player-facing text and no owner decision, so section 16's rule (a second round only if shipped behaviour changes) holds. One design consequence is flagged rather than buried: CR-1 means a queued line can change form between emission and display; that is the intended reading of the feel review's "first is delayed, never lost".
### Test-author findings (revision 4)
Source: sim-test-engineer, writing the red tests from revision 3 (`tests/test_relationships.gd`, `tests/test_view_relationships.gd`, commit 7ac81c8). Where the tests were written to an interpretation, the spec now states that interpretation unless it was wrong design. None touches an owner decision (section 18), a shipped value, a player-facing text or the hash neutrality.
| # | Item | Decision |
| --- | --- | --- |
| T-1 | Forgetting ran on every touched pair, so a fresh pair (first growth about 0.004 < `forget_below` 0.01) was deleted at creation and no new friendship could ever form | A. Forgetting applies only to pairs that decayed this tick, never to a pair that grew (5.5, 5.3). This was a real design bug, not a wording issue. Test 5 extended. |
| T-2 | `*_by_sol` lists one shorter than `pop_by_sol` on a founder world, which appends a `pop_by_sol` entry at creation | A. `begin` appends one initial reading exactly when `_init` appends the initial `pop_by_sol` entry (founder world yes, blank world no) (4, 7, 10.2). |
| T-3 | Whether a kin seed decays in its creation tick | A, resolved as "no": a seeded pair is skipped by growth, decay, forgetting and the flag update in its creation tick, so the bond is exactly the seed; setting its flags is not a crossing (5.2). The tests set `decay.per_h` 0 and are compatible. Crew pairs are seeded outside any tick. Design reason: the seed value is the stated story of the pair at birth, and the probe reads it. |
| T-4 | `{a}`/`{b}` order unstated for close, close_crew and drifted | A. Lower id is `{a}`; full order table in 5.6. |
| T-5 | Source of the dead being's name for grief | A. Last `stats.deaths_list` entry with that `being_id`; the dead is `{b}`, the mourner `{a}`; no entry means no grief line (5.1). |
| T-6 | `_talk_flags` result shape under the gradient | A. Talking iff the id is a key; a quiet stranger has no key; `first` unchanged; extra keys tolerated (10.1). |
| T-7 | `debug_set_bond` on a missing pair, and `was_close` | A. It creates the pair; it does not set `was_close`, `kin` or `crew`, makes no event and no count (3). |
| T-8 | Friend event when neither being is new at emission | A. No event is created (not queued, not counted as stale); the crossing still counts in `friendships_formed` (5.5). |
| T-9 | Tick counter for test 14 | A. `ticks` field added (3); also gives the decay-slice fallback its counter (13). Test 14 may use either `ticks` or the `acc_h` reset. |
| T-10 | Test 12 probes the pull through `_restless_travel` | A as a note on test 12: the pull lives only in the neighbour weights of the existing pick. |
| T-11 | Test 27 is the suite run itself | A as a note on test 27. |
| (none) | Rejected | None. Every interpretation the tests were written to is sound design; T-3 picks the stricter reading (no decay and no growth in the creation tick), which the tests accept. |
No second round of assistant reviews: T-1 is a bug fix that makes the specified behaviour possible at all, and the rest are precision; nothing the player sees changes.
### Calibration findings (revision 5)
Source: `docs/balance/task-4-calibration.md` (sim-test-engineer, 15 runs, replay check PASS on all, hash proof MATCH on all five seeds) and its 10 recommended spec changes; `docs/perf/task-4-tick-profile.md` (behaviour-identical optimisation, 23.7 to 4.7 ms). Item numbers below are the report's recommendations.
| # | Finding | Decision |
| --- | --- | --- |
| P-1 | "First grown friendship before sol 20" unreachable: first births at sol 13 to 26 | A. Target error. Replaced by R1, measured from the first birth (section 13) |
| P-2 | "First Mars-born friendship within 15 sols of the first birth" fails on 4 seeds | AM. Merged into R1 at 30 sols (the first grown friendship is Mars-born in all 15 runs, so two targets measured one thing). 15 was a target error (it assumed about 10 h together a sol); 30 still fails on 3 seeds, which is read as a genuine sim signal and gets the next run |
| P-3 | First line before sol 30 passes only through crew lines | A as stated intent (R2): the crew lines exist for exactly this (O4). The newcomer story is R1 |
| P-4 | `lonely_share` and `friends_mean` bands narrower than the seed-to-seed spread | AM. Lower lonely bound dropped; upper kept at 0.35 over a 50-reading window (R3); `friends_mean_max` 12 to 15 (R4). The upper lonely bound is kept because what breaks it on seeds 42 and 2026 is the failure section 7 names (a third of late newborns with no friend), not population noise |
| P-5 | Tick 5.97 ms median against the 1 ms target | AM. Budget restated against `sim.advance_budget_ms` (R8): measured PASS. `decay.slices` rejected (the revision 3 equivalence claim was wrong, 5.5 skips grown pairs), `tick_h` 2.0 rejected (does not cut the per-tick cost). Later remedy order: mirror-only bonds, then lazy decay. Not built in Task 4 |
| P-6 | Work-heavy split barely separates beings (3 percent of awake hours) | AM. Item 4 reported only; trigger removed |
| P-7 | Kinless newborns not measurable (0 in 15 runs) | AM. Rule kept; item 8 now measures unmoored newborns (kin bond ended before a first friend) and zero-friend late newborns (5.2, 13) |
| P-8 | Pull target compares diverged colonies | A. Replaced by R9 (five-seed mean of the zero-friend newborn share, plus the R4 saturation guard on every seed) |
| P-9 | Friend pairs together 1.7 to 2.7 h against the 3.5 h balance point; 10 h roommates not seen | A. Section 6.1: 3.5 h is a typical pair's formation threshold; the holding thresholds (1.9 h warm, 3.0 h typical, 1.1 h close) match the measured median; real exposure is 2 to 4 h, so time-to-friend figures restated |
| P-10 | Define capped-kind events; cap rarely binds | A. Pinned in R5 |
| P-11 | Room growth: is it too slow? | A, as the one key for the next run: `grow.room_rate` 0.008 to 0.010, with expected effect, risk and the rule for the run after stated in section 13 before the run |
**Tensions the lead weighed (the third-round reviews in section 16 are requested; their answers are recorded here when they arrive).** Readability early (the first newcomer line within a sol count a player at modest speed reaches in one sitting) against a quiet log and friendships that feel earned: `room_rate` 0.010 moves about a third faster, not to the 10 to 12 sols the section 6 bullet once implied, because a friendship that arrives in a week of sols is not news. Selectivity against loneliness: raising growth for everyone lowers loneliness but makes friendship cheaper; 0.010 keeps the typical-pair threshold (2.9 h) above the acquaintance median, which is the line that keeps personality deciding. Cost against fidelity: a cheaper tick by slicing or coarser ticks would buy frame time the frame does not yet need, at the price of a less faithful record; deferred behind a measured trigger.
### Owner question at Task 4 close (O1's dated decision; evidence from the probe)
O1 (a) said the owner decides on the pull at the Task 4 close review with the probe report. What the probe shows (one run per seed and setting; every pull run is a different colony from the shipped one, so differences are single trajectories, not effect sizes):
- **Saturation is real.** Friend pull 0.25 alone on seed 1234: `friends_mean` 37.27 at pop 52 (each being friends with about 70 percent of the colony), `lonely_share` 0.000, post-sol-100 newborns average 37.7 friends (loneliest third 25.3), relationship lines fall to 0.93 per 5 sols because nobody is new any more, and settlement came at sol 112 (shipped 65; still inside the 40 to 150 window). Both pulls on seed 2026: `friends_mean` 16.03 at pop 77. One of five seeds saturates under each setting.
- **On loneliness the effect is inside the noise.** Zero-friend share of post-sol-100 newborns, mean over five seeds: shipped 0.22, friend 0.20, both 0.17; per seed it ranges 0.00 to 0.39 under the pulls against 0.03 to 0.34 shipped. The loneliest-third comparison of revision 4 failed on seeds 7 and 1234 but compared different colonies.
- **Cost.** All five table hashes change under either setting (baseline reset), and settlement sols move on every seed (55 to 112 under the pulls, 53 to 67 shipped).
Options, recommendation first:
- (a) **Recommended: keep the pull off (0.0 / 0.0) at Task 4 close; revisit in Task 5.** Task 5 (Council, factions by personality) is where cliques by temperament have a job; a retune then would use a lower friend pull, the R9 measure and the R4 saturation guard, over the five seeds. Cost: in Task 4 relationships still change only words and talk, so emergence's "decorative layer" risk carries one more task. Nothing to reset.
- (b) Retune within Task 4: after the `room_rate` run, one extra probe pass at friend 0.10, lonely 0.15 (values E; one pull setting, five seeds), and decide with that. Cost: one more probe pass and, if adopted, a baseline reset and Task 3 age re-measurement inside Task 4; the evidence would still be single diverged trajectories.
- (c) On now at 0.25 / 0.15 with a baseline reset. Not recommended: it saturated one seed in five, its loneliness effect is not distinguishable from divergence, and it moves every settlement sol.

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
- Also later, not scheduled: reunion line, mourner behaviour or muted pose, grief effect on mood or energy, a direct social god power, a talk partner choice that prefers a friend in range (10.1, known limit).

## Changelog
- 2026-10-06: revision 1 (lead designer). Draft for the three assistant reviews; owner questions O1 to O4. Reviewer sign-off: pending.
- 2026-10-06: revision 2 (lead designer). Reviews folded in (section 17). Decided: stranger talk gradient replaces friends-only talk; place sentence on friend and close lines; `found_friend` line form; `found_friend` set only on a logged line, queue of 3 with revalidation; cap `max(3, floor(pop / 40))`; grief "is mourning", up to 2 lines per death; drift reworded; crew close line and once-per-founder crew drift line; kin seed scaled by warmth (0.30 to 0.55); lonely pull term (shipped 0); `second_share`; kinless newborn story stated; log eviction checked (FIFO, kind-blind); `lonely_share_max` 0.35; probe items 4, 7 (lonely run) and 8 added. Deferred to Task 5: dislike, structural colony line, click-to-focus. Owner questions revised: O1 dated, O3 is now the first-friend reason. All shipped values remain hash-neutral. Reviewer sign-off: emergence, feel, clarity folded; owner answers pending.
- 2026-10-06: revision 3 (lead designer). Code review folded in (section 17, CR-1 to CR-13 and the optional items). Friend line form recomputed at log time; crew drift revalidated against `crew_drift_named`; section 6 arithmetic recomputed with the restless assumption stated; automated hash proof tool and its helper test; integer pair key and sorted emission; cost fallback fixed in advance; pull draw claim reworded and pull guarded; `friendships_renewed`; grief before the queue; kin newborns' first-friend line stated; data sanity extended; log pollution handled; talk pairing note; tests 17 to 27. Owner decisions O1 to O4 unchanged. Shipped values still hash-neutral; no new tunable.
- 2026-10-06: revision 4 (lead designer). Test-author findings from the red tests (commit 7ac81c8) folded in (section 17, T-1 to T-11). Forgetting only for pairs that decayed this tick (a fresh pair is no longer deleted at creation); initial sol reading at creation on a founder world so the `*_by_sol` lists match `pop_by_sol`; kin seed exact in its creation tick (no growth, decay or flag crossing); `{a}`/`{b}` order pinned for every kind; grief name from `stats.deaths_list`; `_talk_flags` result shape stated; `debug_set_bond` behaviour stated (creates the pair, never sets `was_close`); no friend event when neither being is new at emission; `ticks` counter; notes on tests 12, 14 and 27. Owner decisions O1 to O4 unchanged; no new tunable; shipped values still hash-neutral. Nothing rejected.
- 2026-10-06: revision 5 (lead designer). Calibration probe and tick profile folded in (section 17, P-1 to P-11). Targets restated as R1 to R9 (section 13): first grown friendship within 30 sols of the first birth replaces "before sol 20" and "Mars-born within 15"; `lonely_share` judged as a 50-reading mean with no lower bound; `friends_mean_max` 12 to 15; capped-kind events defined; pull target replaced by a five-seed mean plus a saturation guard. Section 6.1 restates exposure (measured 2 to 4 h together, not 10) and time-to-friend. Tick budget restated against `sim.advance_budget_ms` (measured PASS); `decay.slices` and `tick_h` 2.0 rejected as remedies, later order stated. Probe item 4 trigger removed; item 8 redefined (unmoored newborns). Next run, one key: `grow.room_rate` 0.008 to 0.010. New balance keys `lonely_window_sols` (50) and `first_friend_gap_sols` (30); no sim key changes in this revision; `data/` not edited. Owner question for O1's dated decision added in section 17 (recommendation: keep the pull off, revisit in Task 5); section 18 untouched. Third-round reviews requested (section 16).
