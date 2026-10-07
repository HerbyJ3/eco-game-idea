# Spec: council and diplomacy (Task 5): gatherings, proposals, support, the decision to build a dome (revision 2)

Source of truth: HANDOFF.md sections 1, 2, 4, 7, 8, 9, 10. Plan and open questions Q1 to Q10, lonely-run placement: `docs/tasks/task-5-plan.md`. Format, `age_history` and the Task 5 gate: `docs/specs/ages.md` (sections 2, 3, 6, 7, 8.2, 12, 18 item 5). Social inputs: `docs/specs/relationships.md` (sections 7, 8, 11, 17 "Run 2 findings" and "Round 4 reviews", 18, 19; known issues K1 to K3). Measurements read: `docs/balance/task-4-calibration.md` (trust readings per seed, item 2; kin newborn waits, item 8), `docs/balance/task-4-log.md` (30-sol tables, Task 4 table hashes). Sim facts read: `sim/world.gd` (phase order of `step()`, sol block, `_init_stats`), `sim/ages.gd` (`decide`, `on_sol`, `_record`), `sim/relationships.gd` (`pairs` with the `kin` and `crew` flags, `present`, `ticks`, `friend_count`, `_reading`, `pull`, `begin`, `_births`), `sim/being.gd` (`parent_id`, `born_t`, `_restless_travel`, `is_inside`), `sim/persona.gd` (trait formula), `sim/buildings.gd`, `sim/powers.gd` (only the Good fortune multiplier exists), `tests/balance_lib.gd` (the `age` column prints `S` only for `settlement`, line 109), `data/*.json` (`relationships.seed`, `relationships.lines`, `persona`, `buildings`).

Locked decisions respected:
- **Influence-only god.** Nothing here is a command. No god power reads or writes a stance or a vote.
- **Ages, not meters.** No support share, trust value, count or bar reaches the player. The windows are private.
- **Naturalism.** The Council begins when grown colonists know each other, not after a fixed time. A proposal is raised by a named person who wants it, and carried only when most of the colony wants it.
- **Per-being energy, power as a budget, ice as pressure.** These are untouched: in the shipped state the module writes no colony, being, building or resource state.

Tunables live in `data/council.json` (new) and new balance keys in `data/relationships.json`. No tunable in the new module `sim/council.gd`. This spec describes behaviour and numbers only, no code. **Every number marked E is an estimate until the calibration probe (section 12) measures it.**

## Owner decisions (Herby, 2026-10-07)
Resolved: **O1 = (a)** settled 30 sols + friend web + chosen-friend share + 12 voices. **O2 = (a)** a pledge, nothing built in Task 5. **O3 = (a)** Council ships hash-neutral; the lonely run is plan step 3 under the stricter adoption rule, one owner-approved reset if adopted. **O4 = (a)** no new art. **O5 = (a)** dome only, on topic-keyed machinery; the water rule is a later matter.

## Open for the owner (options as posed)
Five questions. Each lists the recommendation first, its cost, the facts behind it, and what the three reviewers said. The spec is written to option (a) of each; any other answer is a revision.

**O1. The Council gate: what has to be true before the colony is called a Council?** (plan Q1; ages.md 18 item 5, still open)
- (a) **Recommended: Settlement held 30 sols, and trust among grown colonists measured two ways.**
  - "Voices" are the founders and the Mars-born at least 40 sols old.
  - The web must hold most of the voices: at least one half, on 16 of the last 20 sols including the last 3.
  - Most voices must have a friend they chose: at least one half have a voice friend who is neither kin nor crew, on the same 16-of-20 rule.
  - At least 12 voices.
  - The colony splits back to Settlement if the web stays under 0.3. If the gate waits on trust, a line says so in words.

  Facts: the friend web alone is a timer in disguise early on. The founders start as friends (crew bond 0.35, friend line 0.30), every newborn starts as a friend of its parent (kin bond at least 0.30), and every family tree ends at a founder. The second reading is what makes friendship matter. Voices at the earliest possible entry are about 18 to 26 (interpolated, E), so the 12-voice clause is only a floor. Risk: the loosely knit seeds (42, 99, 2026) may enter late or never; that is the honest story, and it ties the Council to the lonely-pull run. Reviewers: all three chose (a). Emergence asked for the second reading (adopted).
- (b) The web reading alone (revision 1). Cost: on all five seeds it probably opens as soon as the 30 sols pass, for the reason above.
- (c) Settlement held for N sols, nothing else. Cost: a timer. The Council comes at about sols 83 to 97 everywhere, against HANDOFF 7 ("relationships and trust form").

**O2. What does the decision do in Task 5?** (plan Q4, Q5)
- (a) **Recommended: a pledge, announced and recorded, with no dome built in Task 5. The pledge line names who first spoke for it, the room and the reason. The pledge stays pinned in the chapters strip, and a named doubter is followed up a few sols later.** The Council age continues. The dome's construction and the Dome age are a later task: they need a dome building kind, art, and life inside without suits (HANDOFF 7). Cost: the climax has no physical consequence yet, so the text has to carry it (section 7). Reviewers: all three chose (a), on condition of the pinned chapter (clarity M1, feel 7) and a pledge that reads as an event (feel 1, clarity M3). Both are adopted. Clarity rejects (b) as a lie and (c) for scope.
- (b) The pledge begins the Dome age now, with nothing built. Cost: an age word for a dome that does not exist.
- (c) The pledge starts a dome construction site in the sim. Cost: a behaviour change and a baseline reset, new art or a placeholder (texture memory 47.1 of 48 MB), and roughly double Task 5.

**O3. Behaviour, hashes and where the lonely-pull run sits.** (plan Q3, section 5)
- (a) **Recommended: the Council ships hash-neutral. The lonely-pull run is plan step 3, after the spec review and before the Council tests.** It is adopted only if the stricter rule of section 10 holds, which now includes a seed count (at least 10 of 15 seeds better) and a check that newborns do not end up repeating the same company. If it is adopted, you approve one baseline reset, and the Council is calibrated on that baseline. Facts: the Council's gate reads the friend web that the pull changes, so calibrating first would mean calibrating twice. Reviewers: all three chose (a). Emergence asked for the seed count and breadth gate (adopted), and feel and clarity refuse (c).
- (b) Task 5 stays fully hash-neutral: the lonely run is measured and reported, and nothing is adopted. Cost: K1 ships for a third task, and the Council is calibrated on a web that may change later.
- (c) As (a), plus a gathering pull on meeting evenings. Cost: a second reset, a second calibration, and an unbounded loop (more gathering, earlier Council, more meetings), which emergence names as the real danger.

**O4. New art for the Council?** (plan Q2)
- (a) **Recommended: no new art.** The Council lives in the log, the age word on the clock line and the chapters strip. Cost: no meeting is seen on screen, only read. Facts: 0 MB; texture memory is 47.1 of 48 MB. Reviewers: all three chose (a).
- (b) No new art, but a brief highlight on the meeting building when a Council line is logged, using existing art (clarity's idea). Cost: a view change and a 720p check. It opens the click-to-focus work (C-4), which Task 5 defers. The log entries already carry `building_id`, so it can come later without a sim change.
- (c) One new asset after a texture-budget pass. Cost: about 1.5 credits and a budget pass first.

**O5. A second matter for the Council: your water rule** (HANDOFF 4: "the beings agreeing on a rule to slow births in the council stage")
- (a) **Recommended: the dome only in Task 5, with the proposal machinery keyed by topic so the water rule plugs in later as data and one lean formula.** Cost: one matter makes the Council thinner. After a pledge the Council has nothing to raise until a later task. One line marks this (section 7, `after_pledge`). Facts: the water rule changes births, so it changes every hash and moves the ice crises (thirst deaths 10, 0, 22, 0, 5 at sol 300). It needs its own calibration.
- (b) Build the water rule shipped off now (emergence's choice): never raised while its effect is off, probed like the Task 4 pulls, and decided at Task 5 close. Cost: one or two more probe passes, a second possible reset in Task 5, and the Task 3 fall-back sols (213, 174) move if adopted.
- (c) The water rule on in Task 5. Cost: two behaviour changes in one task, run in sequence, with both resets in Task 5.

Reviewers split here. Feel and clarity chose (a): feel wants the water rule as a Task 6 hook, and clarity accepts post-pledge silence as the price. Emergence chose (b) because "one matter then silence" is thin possibility space. The topic-keyed machinery takes the part of emergence's point that costs no behaviour. See section 17, "Dissent".

## 0. The design in one paragraph
Once a sol, the colony asks how far its grown members know one another. Of the voices (founders and Mars-born at least 40 sols old), it asks what share stands in one web of friends, and what share has a friend they chose rather than were born or shipped with. A colony that has been settled for a while and passes both becomes a **Council**: it begins to meet. Every voice holds a private **stance** on the colony's one big question, a dome. Personality sets the stance: driven, curious and restless people lean toward building, and steady and caring people lean toward waiting. The colony's days weigh by temperament: crowding and stone in store stir the ambitious, hardship weighs on the cautious, and new parents want room for their children. Friends then pull each other's stances together once a sol, so camps form along friendships. That is diplomacy without dialogue. The council **meets** where the most voices gather in one room. At a meeting a named person who wants the dome raises it. At later meetings the colony is divided (each speaker gives a reason), sets the dome aside (naming who spoke for waiting, or what runs short), or **pledges** to build it together when most voices want it at two meetings in a row. The player reads a few named lines and a pinned chapter, never a number. In the shipped state nothing beings do changes, so every earlier hash reproduces.

## 1. Purpose
HANDOFF 7 describes the Council as "gatherings, arguments, factions by personality". The colony moves on when "a dome proposal wins enough support and the colony commits to build it together". Task 5 turns the Task 4 friendship web into a forum: the age that follows Settlement. It gives the colony's people a way to want something together, disagree about it in camps their personalities explain, and decide. As with ages and relationships, nothing counts toward anything on screen. The decision happens when the people get there.

## 2. Terms
| Term | Meaning |
| --- | --- |
| voice | a living being that is `earth_born`, or whose age `t - born_t` is at least `voice.min_age_sols` x `sol_h` |
| voice web | the graph of voices joined by `friends` pairs whose two ends are both voices (kin and crew pairs count) |
| trust | the share of voices in the largest connected part of the voice web; 0.0 when there are no voices |
| chosen friend | a voice friend through a pair with `kin` false and `crew` false |
| chosen share | the share of voices with at least `entry.chosen_friends_min` chosen friends; 0.0 when there are no voices |
| Council term | the stretch from a Council entry to the next age change |
| Settlement term | the stretch from the latest `age_history` entry with age `settlement` to the next age change |
| gathering | at a relationship tick, the voices awake inside one building (read from `relationships.present`) |
| best gathering | the largest gathering since the last meeting: `{building_id, count, ids, t}` |
| meeting (session) | held at a sol boundary in Council when the interval has passed and the best gathering is big enough; its place is the best gathering's building |
| topic | a matter the Council can take up; Task 5 ships one, `dome` |
| lean | a voice's own position on a topic from personality, colony conditions and its own stake, in [-1, 1] |
| stance | lean after friends' sway, in [-1, 1]; private |
| yes, no | a voice with stance above `support.yes_above`, or below `support.no_below` |
| proposal | a topic, open from the meeting where it is raised until it is pledged, set aside or lapses |
| pledge | the carried decision on a topic; for the dome, to build it together; permanent in Task 5 |
| hard sol | a sol boundary at which the ice, oxygen or food clause of ages.md 4.2 (5, 1a, 1b) fails, recomputed by this module; it records which clauses failed |
| hard share | hard sols in `hard_win` / `cond.hard_window_sols`; the one hardship clock for lean, texts and re-raise |
| hard clause | the clause (ice, air, food) failing on the most sols in `hard_win`; ties in that order |

## 3. State (all new, inside `Council`, owned by `SimWorld` as `world.council`)
| Field | Meaning |
| --- | --- |
| `trust_win`, `chosen_win` | the last `trust.window_sols` trust and chosen-share readings, newest last |
| `stance` | map from voice id to stance (dome); entries for beings that are no longer voices or are dead are dropped at each sol |
| `hard_win` | the last `cond.hard_window_sols` entries `{hard, ice, air, food}` (booleans), newest last |
| `best` | the best gathering since the last meeting, or empty |
| `seen_ticks` | `relationships.ticks` at the last gathering read |
| `last_session_sol` | elapsed sol of the last meeting, or of the Council entry |
| `open` | null, or `{topic, raised_sol, proposer_id, votes, carry_run, reject_run, divided, no_speaker_id}` |
| `set_aside` | map topic to `{sol, hard}` of the last set-aside (absent before one) |
| `raised_ever` | set of topics raised at least once in the run (chooses the "again" text) |
| `pledged` | map topic to pledge sol (absent before) |
| `quiet_logged` | true once the quiet line has been logged in the current Council term |
| `circles_count`, `circles_last_sol` | circles-family lines logged in the current Settlement term, and the sol of the last one |
| `aftermath` | null, or `{due_sol, doubter_id}` after a pledge |
| `after_pledge_logged` | true once the after-pledge line has been logged in the run |
| `line_sol` | the sol boundary at which a Council line was last logged (the cap of 7.4) |
`Being` gains no field. `stats` gains `stats.council` (section 8) and one key in `stats.sols_in_age` (`council`). `Ages` gains one method, `enter_age(world, age_id, how, text)`. It sets `age`, increments `stats.age_changes`, appends the `age_history` entry through the existing `_record` and logs `age_began`. It does **not** touch `last_change_sol`, `window` or the snapshots (section 5.5). `SimWorld` gains `council`, `council_enabled` (default true; false skips both hooks; a test seam), the hook calls and the creation call. `Council` exposes read-only queries for tests and the probe: `stance_of(id)`, `lean_of(id)`, `lean_terms_of(id)` (personal, size, means, hard, child), `is_voice(world, id)`.

## 4. Where it runs
- **Creation**: in `SimWorld._init`, after `relationships.begin(...)` on both branches: `council.begin(self, founders_world)`. A founder world appends **one initial reading pair**: trust 1.0, and chosen share 0.0 (seven crew friends, none chosen). The reason is that the founder branch also appends the initial `pop_by_sol` entry. A blank world appends nothing. So `trust_by_sol` and `chosen_by_sol` have the same length as `pop_by_sol` from creation on (the same rule as relationships.md section 4).
- **Gathering read (phase 11b, after the relationship tick)**: in `step()`, right after `relationships.on_step(...)`: `council.on_step(self)`. It acts only when `relationships.ticks` differs from `seen_ticks` (a tick just ran, so `present` is fresh) and the age is `council`. Then it updates `best` (section 5.7). Otherwise it returns at once.
- **Sol reading and decisions**: inside the `if _sol_started:` block, after `relationships.on_sol(self)`: `council.on_sol(self)`. Ages has already sampled and decided, and relationships has refreshed the web, so the Council reads the age in force and the current friendships.
- The Council is skipped entirely (both hooks) when `world.relationships` is null or `relationships_enabled` is false: it has no web to read. It then appends 0.0 readings so the list lengths still match.
- No RNG draw, no wall clock (except a probe-only timing field), no read of the log, no write to colony, buildings, beings, resources, powers, relationships or the RNG.

## 5. Rules
### 5.1 Voices
A being is a voice if it is `earth_born` or `t - born_t >= voice.min_age_sols x sol_h - STEP_EPS` (40 sols, E). The reason for 40 is that the measured median wait from birth to a first grown friendship is 25 to 29 sols (task-4-calibration item 8), so by 40 sols most Mars-born have had the chance to join the web. A newborn has no say in the dome and does not count against trust. Voices are recomputed at every sol boundary; nothing is stored on the being.

### 5.2 The trust readings (once a sol, every age)
1. Build the voice web: walk the `friends` pairs of `relationships.pairs` in ascending pair key and keep those whose two ends are both living voices. Union them over ascending ids (the same union-find rule as relationships.md section 7: a root is the smallest id). During the same walk, count for each voice its chosen friends (pairs with `kin` false and `crew` false).
2. `trust = size of the part with the most voices / voices`. `chosen = voices with at least entry.chosen_friends_min (1, E) chosen friends / voices`. Both are 0.0 when there are no voices. Also count `voices`.
3. Append each reading to `stats.council.trust_by_sol` / `chosen_by_sol` and to `trust_win` / `chosen_win` (drop the oldest past `trust.window_sols`, 20). Store the latest readings and `voices`.

**Why two readings (revision 2, emergence M2, checked against data).** Revision 1 used the web share alone, which is mostly a record of how the colony was seeded. `relationships.seed.crew` is 0.35 and `seed.kin_base` is 0.30 plus 0.25 x warmth. Both are at or above the friend line `lines.friend` 0.30, and a pair only stops being friends below 0.15. So all 21 founder pairs start as friends, and every newborn starts as a friend of its parent. Every parent chain ends at a founder, so on the boundaries where the gate can first open, the voice web is joined by seeded bonds alone. The measured overall web is 0.81 to 0.92 at sol 60 (task-4-calibration item 2), which fits this. By contrast, the first grown friendship comes at sols 34 to 68 (shipped), so at sols 83 to 97 the chosen share is the reading that can still discriminate. The web reading stays because it alone sees a colony that has split into islands. The chosen reading alone would pass a colony of many small friend pairs.

Why not `web_by_sol`: its denominator includes every friendless newborn, so it falls (0.35 to 0.97 at sol 300) because the colony grows, not because trust is lost.

### 5.3 Entering the Council (decided at the sol boundary, after 5.2)
`decide_entry` returns true when the age in force is `settlement` and ALL of these hold:
1. **Settled long enough**: `n - S >= entry.settled_sols` (30, E). `S` is the `sol` of the latest `age_history` entry (its age is `settlement`: a first entry, a re-entry, or a Council split). This reads `age_history`, never "the first Settlement entry" (ages.md section 2). After a fall-back and re-entry the count restarts.
2. **Web**: `trust_win` is full, and at least `entry.trust_ok_min` (16) of its 20 readings are at least `entry.trust_share_min` (0.5, E). The last `entry.recent_ok` (3) are all at least that value.
3. **Chosen friends**: the same rule on `chosen_win` with `entry.chosen_share_min` (0.5, E): 16 of 20, including the last 3.
4. **Enough voices**: `voices >= entry.voices_min` (12, E). Checked against the Task 4 tables, the earliest possible entries (settled sol + 30: sols 97, 88, 84, 95, 83) have 7 founders plus the Mars-born born by sols 57, 48, 44, 55, 43. Interpolated from the 30-sol tables, that is about 26, 18, 19, 24, 18 voices (E; no deaths before sol 150 on any seed). The clause does not bind at first entry on any seed. It is kept as a floor for a colony thinned by deaths: a meeting of seven founders and three children is a household, not a council.

On entry: `world.ages.enter_age(world, "council", how, text)`, with `how` = `council` the first time in the run and `council_again` after that (section 7). `best`, `last_session_sol` and `quiet_logged` are reset. Clause 1 needs 30 sols after the latest change, and ages' own changes are at least 20 sols apart, so an entry never falls on the same boundary as another age change.

### 5.4 The Council comes apart (split back to Settlement)
`decide_split` returns true when the age is `council` and ALL of these hold:
1. `n - C >= min_dwell_sols` (20), where `C` is the `sol` of the Council entry (the latest `age_history` entry);
2. at least `exit.split_min` (16) of the 20 readings in `trust_win` are below `exit.trust_share_below` (0.3, E);
3. the last `exit.recent_below` (3) readings are all below it.

On split: `enter_age(world, "settlement", "council_split", text)`. An open proposal lapses (5.8). The split reads the web only, not the chosen share. A colony that stays one web while its chosen friendships thin is still one community. The probe's CEILING flag (12, item 3) watches whether the split can ever fire. Dead band: a web reading between 0.3 and 0.5 changes nothing in either direction. As in ages.md 6.2, the window moves by one reading a sol, so an entry is never undone in under 13 sols; the 20-sol dwell is what binds.

### 5.5 How the Council sits with the Task 3 ages (no Task 3 timing changes)
- **Landing and life support stay with ages.** Ages keeps sole authority over Landing and the life-support rule. `Ages.decide` already sends every age other than Landing through the exit branch, so in Council the same hard-days rule applies unchanged. A long ice crisis takes the colony from Council straight to Landing with the existing fall-back line and cause sentence. No ages code changes for this.
- **Ages' dwell is untouched.** `enter_age` does not move `ages.last_change_sol`, so ages' dwell counts from its own last Landing/Settlement change, exactly as in Task 3. **Projected onto "Landing" versus "not Landing", the age sequence is identical to Task 3 on every seed.** Council entries and splits only relabel stretches that Task 3 calls Settlement. The proof is the projected `age` column (section 9).
- **The 20-sol gap does not hold for every pair of entries.** A life-support fall-back can come less than 20 sols after a Council entry, because ages' dwell ignores Council changes. The 20-sol gap guarantee of ages.md 6.2 holds for ages' own changes, and for Council changes measured against the previous entry. T10 is judged on the projected history (section 12), so its meaning and expected values stay Task 3's.
- **Time in Council is credited.** `ages.on_sol` credits `stats.sols_in_age[age]`, so the dictionary gains a `council` key at creation (value 0).
- **The Council reads no private ages state.** It never reads `ages.window` or `last_sample`. Its hardship read (5.6) recomputes three clauses from the colony and the same `ages.sample.*` keys.
- **Ages never reads the Council.** The age is never an input to the ages sample (ages.md 7); the Council reads the age only for its own gate.

### 5.6 Lean and stance (once a sol, every age, for voices only)
Traits come from `persona.traits` (each in [0, 1]). For voice i:
- `ambition_i = (drive + curiosity + restless) / 3`; `caution_i = (steady + care) / 2`.
- Colony conditions, the same for everyone at this boundary:
  - `means = clamp(colony.regolith / colony.regolith_target(), 0, 1)`: "we have the stone".
  - `size = clamp((pop - dome.cond.size_from) / dome.cond.size_span, 0, 1)` (40 and 80, E): "we are outgrowing the modules".
  - `hard` = the hard share (section 2). This boundary's entry is appended to `hard_win` first. A hard sol is one that fails clause 1a (`oxygen >= o2_min_fraction x o2_cap`), 1b (food likewise) or 5 (`ice >= ice_min_sols x pop x ice_per_being x sol_h - CMP_EPS`), with the keys and formulas of ages.md 4.2. The entry records which of the three failed.
- **Lean terms (revision 2, emergence M1).** Conditions weigh by temperament; one stake is the voice's own. All weights are in `dome.lean`.
  - `personal_i = lean.ambition x (ambition_i - 0.5) - lean.caution x (caution_i - 0.5)` (1.0, 1.0)
  - `size_i = lean.size x size x (ambition_i / 0.5)` (0.15, E): crowding stirs the ambitious.
  - `means_i = lean.means x (means - 0.5) x (ambition_i / 0.5)` (0.1, E)
  - `hard_i = lean.hard x hard x (caution_i / 0.5)` (0.4, E): hardship weighs on the cautious.
  - `child_i = lean.child` (0.15, E) if a living being with `parent_id == i` was born within `dome.cond.child_sols` (20, E) sols of this boundary, else 0: new parents want room for their children.
  - `lean_i = clamp(personal_i + size_i + means_i - hard_i + child_i + lean.base, -1, 1)`, with `lean.base` 0.0.
- **Sway (synchronous).** Let `s` be the stances of the previous boundary (a voice without one uses its lean). For each voice i with at least one voice friend:
  `stance_i = (1 - sway.share) x lean_i + sway.share x (sum of w_j x s_j) / (sum of w_j)`
  The sums run over i's voice friends j, with `w_j = sway.close_weight` if the pair is `close` and 1 otherwise. A voice with no voice friend has `stance_i = lean_i`. All new stances are computed from the old ones, then written, so the order of beings does not matter. Friend lists are walked in ascending id (sorted pair keys give this), so float sums are reproducible.
- `yes` = stance > `support.yes_above` (0.1, E); `no` = stance < `support.no_below` (-0.1, E); between them a voice is undecided.

**Why this shape (revision 2).** Revision 1 added the colony terms flat. I checked the trait spread from `persona.json` arithmetic (offset 0.3, scale 1.5, five Mars placements with weights 0.35 to 0.10). This is not a measurement; the probe reports the real spread (item 5). Ambition centres near 0.42 and caution near 0.44, so the personal term centres near 0. Its spread is about 0.15 (one standard deviation), narrower than revision 1's "plus or minus 0.2 per term", because ambition averages three traits. Against that spread, revision 1's size term (+0.3) was 2 standard deviations and its hardship term (-0.8) about 5. The colony would have voted as one: about 98 percent yes in a good season and nearly 100 percent no in a crisis. Personality would have decided nothing, and C5 and C6 would have passed only by luck. Emergence's M1 is confirmed.

Revision 2 makes three changes:
1. **Smaller shared weights.** They shift the yes line within the personal spread instead of past it. The size term at full size is +0.15 x 0.84, about +0.13 for a typical voice (+0.09 to +0.17 across the spread). Means is plus or minus 0.04. Hardship at 10 of 10 hard sols is about -0.35 (-0.26 to -0.44).
2. **Temperament weighting.** Conditions act through it, so hardship splits the colony more, not less. The cautious say no harder, while the driven few still argue for the dome.
3. **One personal stake.** It has its own clock: a parent's child is born and grows past 20 sols.

Expected (E, before sway, which narrows the spread):
- Good season in a large colony: about 60 to 70 percent yes and 5 percent no. A pledge is possible but not unanimous.
- Middle years: about 25 to 40 percent yes and 15 to 25 percent no. The colony is divided.
- Full crisis: about 75 percent or more no, with a driven few still yes. The dome is set aside, and the set-aside names what runs short.

Emergence's rule stands: if the probe raises SIZE-DOMINANT or LOCKSTEP (section 12), the formula is rewritten, not retuned. Personality decides who leans which way at the same moment (R10's lesson from Task 4). Sway makes camps follow friendships, which is "factions by personality" in this sim. Friends are mostly like-tempered pairs (relationships.md 5.3, affinity), so a friend circle tends to share a lean, and sway turns that into a camp. One curious bridge between two circles pulls both toward the middle.

### 5.7 Gatherings and meetings
- **Gathering read** (5.5's hook, Council age only, once per relationship tick): for each building in `present` in ascending id, count the living voices in its list. If the count is strictly greater than `best.count`, set `best = {building_id, count, ids (those voice ids, ascending), t}`. Strictly greater means the earliest tick wins a tie, and the lower building id wins within a tick. A dark (offline) room counts, as in Task 4.
- **Meeting** (at the sol boundary, Council age only, after 5.6): a meeting is held when both of these hold:
  - `n - last_session_sol >= session.interval_sols` (5, E);
  - `best.count >= max(session.min_voices, ceil(session.min_voices_share x voices))` (5 and 0.1, E; revision 2, clarity S1). A meeting of five in a colony of a hundred voices is a dinner, not a council.

  Then `stats.council.sessions += 1`, a `session_log` entry is appended (section 8), the topic step runs (5.8), `last_session_sol = n` and `best` is cleared. If the interval has passed but no gathering was large enough, the meeting waits. `best` keeps growing until one is, so a colony whose people never share a room never meets. Rooms have no capacity in `buildings.json`, and gathering sizes have never been measured. The probe measures them, and the NOROOM flag (section 12) is read before the share is kept.
- Meetings are silent in the log, except for the lines of 5.8 and 7. About 40 meetings a run would bury the lines that matter. The place appears in the proposal and pledge lines.

### 5.8 Topics: raise, argue, decide
Task 5 has one topic, `dome` (`council.topics` = ["dome"]). The machinery is keyed by topic (revision 2, emergence M3):
- the open proposal, the set-aside record, `raised_ever`, `pledged`, the `proposals` stats and the texts (`council.dome.text.*`);
- the lean (`council.dome.lean.*`, `council.dome.cond.*`).

A later topic (the water rule, O5) adds one data block and one lean formula. It does not change the meeting, vote or line rules. At most one proposal is open at a time. Topics are tried in `council.topics` order.

At a meeting, in this order:
1. **Raise.** The first topic in order is raised if all of these hold:
   - no proposal is open;
   - the topic is not pledged;
   - either it was never set aside, or both of these hold:
     - `n - set_aside.sol >= proposal.reraise_sols` (30, E);
     - if the set-aside was a hard one, the hard share is now below `lines.hard_share_min` (0.5, E). This is revision 2, feel 5: the colony does not raise the dome again in the same crisis that buried it.

   The **proposer** is chosen among the voices in `best.ids` that are still living voices: the one with the highest stance (ties: lowest id). If that stance is above `support.yes_above`, the topic is raised:
   - log `proposal` (first raise in the run) or `proposal_again`, naming the proposer and the place;
   - open `{topic, raised_sol: n, proposer_id, votes: 0, carry_run: 0, reject_run: 0, divided: false, no_speaker_id: null}`.

   The raising meeting is not a vote. If no one in the room wants it, nothing is raised and the next meeting tries again. The first time in a Council term that a meeting raises nothing while nothing is open and nothing is pledged, the quiet line is logged (section 7). This is the once-per-term answer to "why has nothing happened yet".
2. **Vote** (a proposal open from an earlier meeting): `votes += 1`. Count yes and no among all living voices: the whole colony decides, not only those in the room. `yes_share = yes / voices` and `no_share = no / voices`, compared by cross-multiplying counts as in ages.md 4.2 (`CMP_EPS`).
   - `carry_run = carry_run + 1` if `yes_share >= decide.carry_share` (0.6, E), else 0. `reject_run` works the same way with `no_share >= decide.reject_share` (0.5, E).
   - **Speakers.** The yes speaker is the yes voice with the most voice friends inside the yes camp (ties: higher stance, then lower id). The no speaker is the same inside the no camp (ties: lower stance, then lower id). Each speaker's **reason** comes from their own lean terms (7.3).
   - **Divided**: if not yet `divided` and both shares are `>= decide.divided_share` (0.25, E), set `divided`, record `no_speaker_id`, and offer the divided line (7.4 may drop it if an outcome line takes the boundary; `divided` stays set either way).
   - Then the first of these that holds:
     - **Pledge**: `carry_run >= decide.carry_sessions` (2). `pledged[topic] = n`; `stats.council.pledge_sol = n`; log the pledge line (variant `pledge_divided` if `divided`), naming the proposer, the place of this meeting and the reason (7.3). Append a chapter (section 8) and close with outcome `pledged`. Set `aftermath = {due_sol: n + lines.aftermath_sols, doubter_id}`, where `doubter_id` is chosen in this order:
       1. the `no_speaker_id` if that being is still a living voice;
       2. else the lowest-stance voice that is `no` at this vote (ties: lowest id);
       3. else none, and no aftermath.
     - **Set aside**: `reject_run >= decide.reject_sessions` (2). Close with outcome `set_aside` and record `set_aside[topic] = {sol: n, hard: hard >= lines.hard_share_min}`. The line depends on the hard share:
       - if the hard share is at least `lines.hard_share_min` (0.5), log `set_aside_hard`, naming the hard clause. This is the same clock the lean uses (revision 2, clarity M4; revision 1 used "this sol is hard");
       - else log `set_aside`, naming the no speaker.
     - **Left open too long**: `votes >= decide.max_open_votes` (12, E; about 60 sols). Log `set_aside_long` and record `set_aside[topic] = {sol: n, hard: false}`. Close with outcome `set_aside`.
     - Otherwise the argument goes on.
3. **Lapse.** When the colony leaves Council (split or fall-back) with a proposal open, it lapses: outcome `lapsed`, no line (the age line says enough). `set_aside` is unchanged, so the topic can be raised at the first meeting of the next Council term ("again" text).

The earliest pledge is therefore at the third meeting of a term: raise, then two carrying votes. That is at least 10 sols after the raise and 15 sols after the Council entry at the shipped interval. A colony cannot rubber-stamp the dome at the meeting where it was raised.

### 5.9 The pledge and after (owner O2 (a))
The pledge is permanent in Task 5: it survives a fall-back to Landing and a split. After it the dome is never raised again; the Council still reads trust, sways stances and holds meetings.
- **Aftermath** (revision 2, feel 1b, adopted modified). At the first sol boundary at or after `aftermath.due_sol` (pledge + 4 sols, E), the doubter's current stance decides the line:
  - if the doubter is still a living voice and the age is `council`: `aftermath_round` if their stance is now above `support.yes_above`, else `aftermath_still`;
  - otherwise nothing.

  The line reports the doubter's actual stance, so it never claims work the sim does not do.
- **After the pledge** (revision 2, clarity S3). Once in the run, at the first meeting at least `lines.after_pledge_sols` (30, E) after the pledge, the after-pledge line says the Council goes on meeting with no new matter. It is honest because the meetings do continue, and it answers clarity's expected play-test question "what happened to the dome after the pledge".

Nothing in the sim is built or changed. `stats.council.pledge_sol` and the chapter carry the pledge forward for the task that builds the dome.

### 5.10 Edge cases
- **Pop 0 or no voices.** Readings of 0.0 are appended, and there is no entry, split, meeting or line. Stances are empty. The age is frozen by ages (ages.md 8.3).
- **Voices below `entry.voices_min` while in Council.** There is no special rule: the web still decides a split, and votes are shares of whoever is a voice. The meeting size uses the current voices.
- **A named person dies later.** If the proposer or a speaker dies, lines already logged stay and the proposal stays open. If the doubter dies before the aftermath, there is no aftermath line.
- **A voice in `best.ids` dies before the meeting.** It is skipped when choosing the proposer.
- **The proposer is not in the pledging room.** The pledge line names the proposer and the place of the pledging meeting, which may differ from the raising room. The text says "spoke for it first", which stays true.
- **A child stake from a dead child.** It does not count, because the stake needs a living being whose `parent_id` is the voice. Founders' `parent_id` is 0, and no being has id 0.
- **Clashing boundaries.** A Council entry and an ages change on the same boundary are impossible (5.3, clause 1). If an ages fall-back from Council and a split fall on the same boundary, ages runs first, so the Council sees Landing and does nothing.
- **Settlement re-entered after a split.** Clause 1 restarts the 30 sols from the split entry. `circles_count` resets with each Settlement term.
- **Relationships disabled.** The Council is inert and appends 0.0 readings (section 4).
- **Log eviction** (500, kind-blind) changes no Council value. The chapter survives in `stats.council.chapters`.
- **Missing phrases.** A building kind with no place phrase uses `text.place.other`; the key-path test fails until one is added. A trait with no adjective cannot occur: `persona.adjectives` covers all six dimensions.

## 6. Numbers, and what they imply (all E)
- **Entry timing.** Settlement came at sols 67, 58, 54, 65, 53 (Task 3/4), so the earliest Council entry is sols 97, 88, 84, 95, 83. Revision 1 expected four seeds to enter near the earliest sol. With the chosen-friend clause that is no longer expected. The first grown friendship came at sols 45, 34, 68, 41, 54 (shipped), and the kin newborns' median wait to a first grown friend is 25 to 29 sols. The chosen share near sol 90 is therefore unknown: it may sit below 0.5 on the loosely knit seeds (zero-friend newborns after sol 100: 38, 1, 23, 11, 36). The probe measures it and replays the threshold (12, item 9). C1 asks for at least 3 of 5 seeds.
- **Lean magnitudes.** See 5.6 "Why this shape". Size at pop 82 is 0.53, and 1.0 from pop 120 (reached by about sol 120 to 210 on seeds 42, 99, 1234, 2026; never on seed 7, pop 72 at sol 300). Means from the 30-sol tables runs from about 0.01 (seed 42, sol 180) to above 1 (seeds 7, 1234). Hard is high on seeds 42 and 99 after sol 150 (ice near 0) and at times on 2026.
- **Meetings.** One every 5 sols at most: about 30 to 40 in a run on a seed that enters near sol 90. The minimum room is 5 voices up to 50 voices, then 10 percent (10 at 100 voices). Room sizes are not measured (probe item 6).
- **Lines.** Per proposal term: a raise, at most one divided, one outcome. Per Council term: at most one quiet line. Per run: one aftermath and one after-pledge line. Per Settlement term: at most two circles-family lines. Plus age lines. At most one Council line per sol boundary (7.4). Expected well under one line per 5 sols. Relationship lines are 9.6 to 13.0 percent of the log today, and Council lines add about 1 to 2 percent (E).

## 7. What the player sees (view; sim read-only; fixed texts, no numbers)
### 7.1 Age lines
These are kind `age_began`, written through `Ages.enter_age`, so they land in `age_history` and the chapters strip. Each text is the base sentence plus the season sentence of `ages.season_phrases` at the change time (the same rule as ages.md 8.1).
| `how` | Key | Text (first sentence is what the strip shows) |
| --- | --- | --- |
| `council` | `text.enter` | "Jezero has begun to meet as one. Its people know one another now, and evenings end with everyone in one room, talking at once, and now and then agreeing." |
| `council_again` | `text.enter_again` | "The colony meets as one again. Old friends have found each other, and old arguments are taken up where they were left." |
| `council_split` | `text.split` | "The meetings have gone quiet. Friends keep to their own circles, and no one speaks for the whole colony." |

The enter texts now carry their cause: people know one another (clarity S5). A fall-back from Council to Landing uses the existing ages fall-back line and cause sentence unchanged.

### 7.2 Council lines
These are new kinds. `{a}` and `{b}` are `Being.name`. `{place}` is the place phrase of the meeting room's kind. `{ra}` and `{rb}` are reason clauses, `{why}` is the pledge reason, and `{clause}` is a hard-clause phrase.
| Kind | Key | Text |
| --- | --- | --- |
| `council_proposal` | `dome.text.proposal` | "{a} spoke of a dome at the meeting {place}: a roof of sky, and streets without suits." |
| `council_proposal_again` | `dome.text.proposal_again` | "{a} raised the dome again at the meeting {place}." |
| `council_divided` | `dome.text.divided` | "The council is divided over the dome. {a} speaks for building it, {ra}; {b} says not yet, {rb}." |
| `council_set_aside` | `dome.text.set_aside` | "The council has set the dome aside for now. {b} spoke for waiting, and many agreed." |
| `council_set_aside_hard` | `dome.text.set_aside_hard` | "The council has set the dome aside. While {clause} runs short, no one has the heart for it." |
| `council_set_aside_long` | `dome.text.set_aside_long` | "The talk of a dome has gone round and round. The council lets it rest for now." |
| `council_pledge` | `dome.text.pledge` | "The council has agreed to build a dome. {a} spoke for it first, and tonight, {place}, Jezero promised to build it together, {why}." |
| `council_pledge` | `dome.text.pledge_divided` | "The council has agreed to build a dome. {a} spoke for it first, and tonight, {place}, Jezero promised to build it together, {why}, though not everyone is glad of it." |
| `council_aftermath` | `dome.text.aftermath_round` | "{b}, who said not yet, has come round to the dome." |
| `council_aftermath` | `dome.text.aftermath_still` | "{b} still says not yet, but will build with the rest." |
| `council_after_pledge` | `dome.text.after_pledge` | "The council still meets most evenings. With the dome agreed, the talk is of smaller things." |
| `council_quiet` | `text.quiet` | "The council meets, but no one has spoken for anything yet." |
| `council_quiet` | `text.quiet_hard` | "The council meets, but the talk is all of {clause}." |
| `council_circles` | `text.circles` | "People keep to their own circles. No one yet speaks for the whole colony." |
| `council_circles` | `text.circles_again` | "The evenings are still quiet. Friends keep to their own circles, and no one gathers the whole colony." |
| `council_circles` | `text.circles_few` | "Jezero is still more a household than a colony. There are too few grown hands for a council." |

**Wording rules.** The pledge says "will build" and "promised to build", never "is building" or "built" (clarity M3). The quiet line uses `quiet_hard` when the hard share is at least `lines.hard_share_min`, the same clock as the set-aside and the lean. The first sentence of the pledge, "The council has agreed to build a dome.", is what the strip shows. It is fixed in both variants, so the strip never carries a reason or a name.

Place phrases (`text.place.*`): habitat "in the habitat", green_room "in the green room", workshop "in the workshop", reactor "by the reactor", archive "in the archive", comms "at comms", other "in the colony".

Hard-clause phrases (`text.clause.*`): ice "the ice", air "the air", food "the food".

Entries carry `being_id` (`{a}`, or the doubter for aftermath), `other_id` (`{b}` or null), `building_id` (the meeting room, or null) and `topic` ("dome", or null for generic lines). Later click-to-focus therefore needs no sim change.

### 7.3 Reasons (revision 2: feel 6, clarity S2 and M3, emergence S2, merged)
A **speaker's reason** is chosen from the speaker's own lean terms (5.6) at this boundary, pointing the way of their camp:
- **Friends.** If the speaker's lean and stance have opposite signs, or the lean is inside the undecided band, the reason is `friends`. Their friends moved them, and this is the one place the player sees sway.
- **Yes speaker otherwise.** The largest of `size_i`, `means_i` (if positive), `child_i` and `personal_i` (if positive). Ties go in that order.
- **No speaker otherwise.** The largest of `hard_i`, `-means_i` (if means is negative) and `-personal_i` (if personal is negative). Ties go in that order.

| Reason | Yes key (`dome.text.reason.yes.*`) | No key (`dome.text.reason.no.*`) |
| --- | --- | --- |
| size | "since the modules are full" | (none; size never argues against) |
| means | "since there is stone in store" | "while stone is scarce" |
| child | "for the children to come" | (none) |
| hard | (none) | "while {clause} runs short" |
| personal | "{adj} as ever" | "{adj} as ever" |
| friends | "as their friends do" | "as their friends do" |

`{adj}` is `persona.adjectives` of the speaker's highest trait among drive, curiosity and restless (yes) or steady and care (no). Ties follow the `persona.dims` order. These are existing data words: driven, inquisitive, restless, steady, nurturing. Example: "Lena speaks for building it, restless as ever; Omar says not yet, while the ice runs short."

The **pledge reason** `{why}` is the term with the largest mean contribution over the yes voices at the pledging vote, among `size_i`, `means_i` (if positive), `child_i` and `personal_i` (if positive), with ties in that order. It uses the yes keys, except that the personal reason uses `dome.text.pledge_why_personal` ("because its bolder hearts would not wait"). The chosen term is stored in the `proposals` entry (`reason`).

### 7.4 One Council line per sol boundary (clarity S6)
At most one Council-kind line is logged per sol boundary. Age lines are not counted, and they never coincide with a meeting: an entry resets the interval, and a split or fall-back ends the Council. When two would fall on one boundary, the higher wins, in this priority:
1. outcome (pledge, set-aside);
2. divided;
3. raise;
4. quiet;
5. after-pledge;
6. aftermath;
7. circles family.

The lower line is dropped and counted in `stats.council.lines_dropped`. A dropped divided line still sets `divided`, so the pledge carries the dissent ("though not everyone is glad of it"), and a set-aside names the no speaker anyway. A dropped aftermath line is not retried. Clarity's "1 line per 5 sols" is not adopted as a rule: the 5-sol meeting interval and target C7 already bound the rate (section 17).

### 7.5 The circles family (the structural line deferred from Task 4, C-7)
These lines answer relationships.md section 11: "a hidden counter must not act as a silent gate". At most `lines.circles_max` (2) per Settlement term:
- **First line.** It comes at the first boundary where both of these hold:
  - the term has lasted `entry.settled_sols + lines.circles_after_sols` (30 + 20 sols, E);
  - the only failing entry clauses are web, chosen or voices.

  If the voices clause fails, the line is `circles_few`; otherwise `circles`.
- **Second line** (revision 2, feel 2). It comes `lines.circles_again_sols` (100, E) after the first, if the same holds. It uses `circles_again`, or `circles_few` if voices fail.

A seed that never enters Council therefore hears twice why, in the colony's voice, without a number.

### 7.6 HUD
- **Age word.** The clock line's age word is `council.age.name` ("Council") when `stats.age` is `council`. Landing and Settlement keep their names from `ages.json`, and no Council key is added to `ages.json`, so ages test 18 stands.
- **Chapters strip (revision 2: pinned pledge; clarity M1, feel 7).** The strip merges `age_history` and `stats.council.chapters` and orders them by `t` (on a tie the age entry comes first). It shows the latest `ages.hud.chapters_shown` (3) entries, each as `sol N  <first sentence>`. If a pledge chapter exists and is not among those 3, the strip shows the latest 2 plus the pledge, still in time order. The pledge is never pushed off by later age changes, and the strip stays at 3 lines, so there is no 720p change. A dome state word in the strip (clarity S4) is not adopted (section 17).
- **What the HUD never shows.** No support share, trust, chosen share, vote count, camp size, stance, "sols until", meeting count or bar anywhere. No new panel, button or pop-up. No speed change on any Council event (owner decision of ages.md 18 item 4).
- **Out of Task 5.** A being inspect panel, click-to-focus, a highlight on the meeting building (owner O4 (b)), and a meeting shown on screen (section 15).

## 8. Stats and log
`stats.council` is run-wide, never windowed, never reset and never shown. It is created in `_init_stats`.
| Key | Definition |
| --- | --- |
| `trust`, `chosen`, `voices` | latest readings |
| `trust_by_sol`, `chosen_by_sol` | one float per pass through the sol block with the module enabled, plus the initial founder-world reading; same length as `pop_by_sol` |
| `first_council_sol` | elapsed sol of the first Council entry, null before |
| `sessions` | meetings held |
| `session_log` | `{sol, building_id, present (best.count), voices, yes, no, hard}` per meeting; uncapped (about 40 a run) |
| `proposals` | `{topic, raised_sol, proposer_id, again, outcome (null, pledged, set_aside, lapsed), outcome_sol, reason (pledge only), hard (set-aside only)}` per raise |
| `pledge_sol` | elapsed sol of the dome pledge, null before |
| `chapters` | `{kind: "pledge", topic, text, t, sol, clock_sol}`; read by the strip |
| `lines` | counts per line key of section 7.2 |
| `lines_dropped` | Council lines dropped by the per-boundary cap (7.4) |

Not in stats: stances, leans, `best`, the windows.
- `stats.sols_in_age` gains `council`.
- `age_history` gains entries with age `council` (`how` `council` or `council_again`) and age `settlement` (`how` `council_split`). Fields and shape are unchanged. `len(age_history) == age_changes + 1` still holds, because each Council change increments `age_changes`.
- Also built with Task 5's first sim change (relationships.md 10.2, RN-7): `stats.relationships.lines_dropped_by_type`.

## 9. Randomness and hashes, per mechanic
No mechanic draws from `SimRng` or any other random source. Every order is fixed: ascending ids, ascending pair keys, ascending building ids, topic order, meeting order.
| Mechanic | Draws | Writes outside the module | Effect on earlier hashes |
| --- | --- | --- | --- |
| Voices, trust and chosen readings (5.1, 5.2) | none | `stats.council` | none |
| Entry, split via `Ages.enter_age` (5.3, 5.4) | none | `stats.age`, `age_changes`, `age_history`, `sols_in_age`, log | none on behaviour (nothing in the sim reads them); the `age` column is projected (below) |
| Lean (with the child stake), hardship, sway (5.6) | none | none | none |
| Gathering read, meetings, scaled minimum (5.7) | none | `stats.council` | none |
| Raise, vote, reasons, divided, outcomes, pledge, aftermath, after-pledge, quiet (5.8, 5.9, 7) | none | log, `stats.council` | none |
| Circles family, line cap (7.4, 7.5) | none | log, `stats.council` | none |
| `lines_dropped_by_type` (8) | none | `stats.relationships` | none |
| Lonely pull above 0.0 (section 10; owner O3) | same draws per travel decision, different choices | being behaviour | **changes every hash**; one recorded reset if adopted |

**Balance columns.**
1. The existing `age` column becomes a projection: `L` when the age is `landing`, `S` for any other age. Today `tests/balance_lib.gd` prints `S` only for `settlement` and would print `L` for `council`. This one-line edit is therefore required, and the code reviewer is asked to check it as justified.
2. A new trailing column `cn` after `web`: `-` before any Council entry or outside Council without a pledge, `C` in Council without a pledge, and `P` after the pledge (any age).

Removing the last field reproduces the Task 4 table hashes (`docs/balance/task-4-log.md`: 42 a96b8a9562fd75d0, 7 a4968e2fcc48ec36, 99 2210719cf48d8612, 1234 19437e397d1dff88, 2026 6e7fe68477161196). From there, the existing `tests/relationships_hash_proof.gd` chain gives the Task 3 and Task 1 hashes.

**Automated proof**: `tests/council_hash_proof.gd`. It is not a unit test; it is modelled on `relationships_hash_proof.gd`, with static helpers.
- Per seed it strips `cn` (and refuses if the last header field is not `cn`) and compares the result with the Task 4 hash.
- It then strips `web` and `age` in turn and compares with the Task 3 and Task 1 hashes.
- It exits 0 only when all match.

If the owner adopts the lonely pull (O3), the reference hashes become the reset baseline recorded in `docs/balance/task-5-lonely-run.md`, and the Task 1/3/4 chain is reported as superseded, with old and new side by side.

**Paired runs**: in the shipped state the Council changes nothing beings do. A run that changes any `council.*` key therefore plays out the same colony as the shipped run on that seed, and calibration of the Council is a paired comparison, like relationships.md section 13.

## 10. The lonely-pull run (owner decision 2026-10-06: Task 5's first social run is the lonely pull alone)
**Placement**: plan step 3 (owner O3 (a)), after the code review of this spec and before the Council tests. One parameter changes: `relationships.effects.lonely_pull`, 0.0 to 0.15 (`effects.friend_pull` stays 0.0; the value comes from RN-6 and E4-1, chosen by the lead). Everything else is as shipped.

**Before the run** (tests and columns first, hash-neutral, one commit):
- `stats.relationships.lines_dropped_by_type` (10.2);
- probe addition F4-1: the longest run of sols with no capped-kind relationship line before the first newcomer line;
- probe addition F4-3: `balance.log_share_flag` 0.15, a flag only;
- R13's 2.5 warning read and R12's reopen trigger read on every run (F4-2, F4-4);
- the **breadth-or-repetition report** (E4-1): for newborns after sol 100, the median hours a sol shared with their most-shared being, shipped against pull;
- the **voice readings** (revision 2, emergence S4): trust and chosen share per sol, computed by the probe from `relationships.pairs` with the formulas of 5.2. They are read-only and need no Council module.

**Seeds.** The five standard seeds are used for T1 to T11 and every R target. R9 is also judged over **15 seeds** (E4-4; lead decision): the five plus 1, 2, 3, 5, 8, 13, 21, 34, 55, 89 (`relationships.balance.r9_seeds`). Both shipped and pull runs are made on all 15: about 30 runs of 300 sols (E: about 2 hours on this host). A forked design (both runs from one saved world) is not possible today, because `SimWorld` has no save, load or clone.

**Adoption rule, stated before the run (revision 2 adds clauses 2 and 3, emergence S4).** The lead recommends adoption to the owner only if ALL of these hold:
1. **R9 mean.** The 15-seed mean zero-friend share of post-sol-100 newborns under the pull (probe item 8 (c)) is at most the shipped 15-seed mean minus `balance.r9_gain_min` (0.03, E). A smaller gain is inside the noise of diverged trajectories.
2. **R9 breadth of seeds.** The zero-friend share under the pull is lower than shipped on at least `balance.r9_seeds_better_min` (10, E) of the 15 seeds. By chance alone this happens about 15 percent of the time. With clause 1 it stops one or two lucky seeds from carrying the mean. The standard error of the paired difference is reported, not judged.
3. **No repetition.** The 15-seed mean of the breadth-or-repetition measure (median hours a sol with the most-shared being) under the pull is at most shipped plus `balance.repeat_rise_max` (0.5 h, E). A pull that cures loneliness by gluing each newborn to one person is not adopted.
4. **R4, R10, R11.** R4 (`friends_mean` 1 to 15), R10 (selectivity at least 2.0) and R11 (coldest third at most 10) hold on all 15 seeds.
5. **T1 to T11.** They pass on the five standard seeds. Task 3 crossings will move; they are reported, old and new side by side, not judged against 67, 58, 54, 65, 53.
6. **Deaths.** No unexplained death (`deaths_unexplained` 0) and no new death cause.

**Reported, not a clause (emergence S4, "the pull must not make the gate a timer").** On both runs the probe reports trust and chosen share at the earliest-entry sol of each seed, and whether the chosen clause of 5.3 would bind anywhere. If under the pull it binds on no seed, the lead tells the owner with the recommendation, because the gate would be a timer on that baseline. It is not an adoption clause, because the Council's thresholds are calibrated after this decision, on whichever baseline ships.

**If any clause fails**, the pull stays 0.0 and K1 is carried as known. The breadth report then decides what is posed next. If the pull added breadth without repetition, the parent-room anchor (E4-3) is the named next lever for a later task, not Task 5.

**Read on every run**:
- K1: zero-friend late newborns on 42 and 2026;
- K2: the first newcomer line, with the R12 trigger (any seed later than sol 80, or two or more later than 68);
- K3: R1 margins on 99 and 2026 (a 1-sol move after a behaviour change is noise).

Report: `docs/balance/task-5-lonely-run.md`.

**Lonely definition (plan Q10):** `friend_count` 0, kin included: the K1 definition, unchanged (E4-6). One change per run, so a "no grown friendship" definition would be a second change. The temperament-scaled pull (E4-2) and the parent-room anchor (E4-3) are not in Task 5.

**Interplay with the Council:** a pull that brings friendless beings into company raises both voice readings (5.2), and an earlier or surer Council follows. The Council's thresholds are calibrated after this decision, on the baseline that ships.

## 11. Cost budget (E; measured by the probe and the step profile)
- **`on_sol`** (once a sol, about every 493 steps). Work:
  - the pair walk (stored pairs: median 2,876 and max 4,389 at pop above 120, relationships.md 13), with the chosen count in the same walk;
  - the voice union-find;
  - a child-stake map (one pass over beings by `parent_id`);
  - sway over voice friends, and the counts.

  Estimate 1 to 3 ms at pop 160. Reasons are computed only for the speakers and the yes voices at a vote. **Budget: median at most `balance.on_sol_ms_max` (3.0 ms), max under `sim.advance_budget_ms` (8.0 ms).** Amortized, this is under 0.01 ms a step.
- **`on_step`.** It acts only on tick steps (every 20th) in Council, and is O(awake beings inside). Estimate 20 to 50 microseconds. **Budget: the module's share of the mean step cost at pop above 120 at most `balance.step_share_max` (0.02).**
- **Worst boundary step.** About 14 ms: ages (about 0.4 ms), the relationships reading (about 2.3 ms), the Council (up to 3 ms), a relationship tick if one coincides (about 6 ms) and the step (about 2.5 ms). That is under the 33 ms single-frame trigger of relationships.md 13, and `advance()` stops after it as it already does. If the probe measures a boundary step over 16.7 ms that is attributable to the Council, the remedy order is:
  1. share the union-find with relationships' reading (behaviour-identical);
  2. skip trust and sway on sols where nothing reads them (Landing, and pledged Council).

  Neither is built now.

## 12. Calibration probe and balance targets
**Probe** `tools/council_probe.gd`: read-only; runs the real module on seeds 42, 7, 99, 1234, 2026 for 300 sols, on the baseline O3 leaves. Per seed it writes `docs/balance/task-5-calibration.md`:
1. **Per sol.** Pop, voices, trust, chosen share (at `chosen_friends_min` 1 and 2), age, hard share and hard clause, means, size, mean lean and mean of each lean term, mean stance, yes and no shares, the largest number of voices together at one tick that sol (computed by the probe in every age), and whether a meeting was held.
2. **Crossings.** Council entries, splits and fall-backs with their sols. For each entry, which clause passed last (settled sols, web, chosen, voices). Reported: the projected ages sequence equals Task 3's (or the reset baseline's).
3. **Trust discrimination.** Per seed, the minimum and maximum of each reading over sols 60 to 300.
   - **Flag FLOOR** if, after its 30 settled sols, no seed's web or chosen reading ever falls below its entry threshold. The gate would then be a timer in disguise.
   - **Flag CEILING** (clarity S1) if, on every seed that enters, the web reading never falls below 0.5 after the entry. The split can then never fire, and the dead band is decorative.
4. **Proposals.** Raise sols, proposers, votes to outcome, outcomes, divided lines, reasons chosen, and the yes and no shares at each vote. At each outcome, the mean lean split into its five terms.
   - **Flag SIZE-DOMINANT** if, at every pledge across the seeds, the mean size term exceeds half the mean lean.
   - **Flag LOCKSTEP** (emergence M1) if, at more than half of all votes pooled, at least 0.95 of voices are on one side (yes, or no).

   Either flag means the formula of 5.6 is rewritten, not retuned (emergence).
5. **Factions and spread.** At each divided vote: the mean ambition and caution of the yes camp against the no camp; the share of voices whose stance sign differs from their lean sign (how much sway moved people); and the standard deviation of the personal term among voices. The last checks the 0.15 estimate of 5.6.
6. **Gatherings.** The distribution of the daily largest voice gathering, as a count and as a share of voices. Also the Council sols where the interval had passed but no meeting was held. **Flag NOROOM** if that share exceeds 0.5 on any seed: the scaled minimum of 5.7 then binds too hard. **Raise timing** (feel 4): sols from Council entry to the first raise. If that is under 6 sols on at least 3 seeds, the lead considers a first-raise delay (not built now).
7. **Lines.** Council lines per 5 Council sols, lines dropped by the cap, and Council and relationship lines as a share of the log (`balance.log_share_flag`).
8. **Cost.** `on_sol` median, p95 and max in microseconds at pop around 70 and above 120, and the share of the mean step.
9. **Replays** from stored readings (the gate only; no live run needed):
   - `entry.trust_share_min` {0.4, 0.5, 0.6};
   - `entry.chosen_share_min` {0.3, 0.4, 0.5, 0.6} at `chosen_friends_min` {1, 2}, from the item 1 series;
   - `entry.settled_sols` {20, 30, 45};
   - `entry.trust_ok_min` {14, 16, 18}.

   Decision keys are tuned by paired live runs (section 9), one key per run, chosen by the lead.

**Targets** (E; judged by the probe unless marked T12):
| # | Target | Key |
| --- | --- | --- |
| C1 | Council entered by sol 300 on at least 3 of the 5 seeds | `balance.council_min_seeds` 3 |
| C2 | (T12) Every Council entry is at least 30 sols after the Settlement entry before it, and every Council change is at least `min_dwell_sols` after the previous `age_history` entry | structural |
| C3 | (T12) At most 4 Council changes (entries plus splits) per seed | `balance.max_council_changes` 4 |
| C4 | A pledge on at least 1 seed by sol 300; pledge sols reported | `balance.pledge_min_seeds` 1 |
| C5 | A divided or set-aside line on at least 2 seeds (the colony argues) | `balance.argue_min_seeds` 2 |
| C6 | At at least 80 percent of divided votes, pooled over the seeds, the yes camp's mean ambition is above the no camp's and the no camp's mean caution is above the yes camp's (factions follow personality) | `balance.faction_trait_share_min` 0.8 |
| C7 | Council lines (age lines excluded) at most 1.0 per 5 Council sols on every seed | `balance.lines_per5_max` 1.0 |
| C8 | Cost as in section 11 | `balance.on_sol_ms_max` 3.0, `balance.step_share_max` 0.02 |
| D | FLOOR, CEILING, SIZE-DOMINANT, LOCKSTEP and NOROOM flags (items 3, 4, 6): reported; they fail nothing and are read by the lead before the next key | none |

**T12** in `tests/balance_lib.gd`, per seed, from `stats` and the log:
1. `len(trust_by_sol) == len(chosen_by_sol) == len(pop_by_sol)`;
2. C2;
3. C3;
4. every `proposals` entry has an outcome or is the open one, and the pledged proposal has `outcome_sol - raised_sol >= 2 x session.interval_sols`;
5. no sol boundary carries two Council-kind lines.

Reported: first Council sol, meetings, proposals and outcomes, pledge sol and reason, lines, lines dropped.

**T10 on the projected history**: T10 reads `age_history` through a helper that maps every non-Landing age to `settlement` and drops entries that do not change the projection. `age_changes` for T10 (2) is the projected count. Its meaning and expected values are Task 3's (changes 2, 1, 2, 1, 1 on the shipped baseline). This is the one justified edit to a Task 3 check; T1 to T9 and T11 are unchanged.

Not a target: when the pledge comes. A colony that never agrees is a legitimate story; C4 only checks that the decision can happen.

## 13. Tests (`tests/test_council.gd`, written first, red; no test with zero checks)
Staging: a blank world with a reactor, two habitats, a workshop and a green room. Beings are added with `add_being`, with traits overwritten and `born_t`, `earth_born` and `parent_id` set. Friendships are made with `relationships.debug_set_bond`, with `kin` and `crew` flags set directly on the staged pair. `present` is set by a relationship tick. Boundaries are driven by setting `world.t` and calling the hooks.
1. **Voices.** An Earth-born is a voice at once; a Mars-born at 39.9 sols is not, at 40 is; the dead are not.
2. **Readings.** Staged voice webs:
   - one part of 6 of 10 voices reads 0.6; two islands; a non-voice bridge does not join two voice parts; kin and crew pairs count for the web;
   - chosen share: a voice whose only friends are kin or crew is not counted, and one chosen voice friend counts at `chosen_friends_min` 1 but not at 2;
   - no voices gives 0.0; one entry per boundary for each reading;
   - both lengths equal `len(pop_by_sol)` on founder and blank worlds; the founder world's initial readings are 1.0 and 0.0.
3. **Entry.**
   - Settlement held 29 sols blocks, 30 enters.
   - Web: 15 of 20 readings at 0.5 blocks, 16 enters, exactly 0.5 counts, and a 0.49 in the last 3 blocks.
   - The same four cases on the chosen readings, with the web passing.
   - 11 voices blocks, 12 enters. Landing never enters. After a split, re-entry needs 30 sols from the split entry.
   - Entry appends one `age_history` entry `{age: council, how: council, cause: null, text, pop, family_mars_born, t, sol, clock_sol}`, increments `age_changes`, logs `age_began` and leaves `ages.last_change_sol` unchanged. The second entry in a run uses `council_again`.
4. **Split.** Before the 20-sol dwell, no split. 16 of 20 below 0.3 with the last 3 below splits (`how` `council_split`, age `settlement`); 15 of 20 does not; a reading of 0.3 is not below. A low chosen share alone never splits.
5. **Ages interplay.** On a staged world in Council, a life-support window that sends a Settlement colony to Landing at sol N sends the Council colony to Landing at the same sol N, with the same `fell_back` text and cause. `Ages.decide` for Landing and Settlement inputs is unchanged, and `sols_in_age.council` is credited.
6. **Lean.**
   - Each of the five terms is checked alone against the formula with values from data (tolerance 1e-12), including the temperament factors: hardship moves a cautious voice further than an ambitious one, and size the reverse.
   - The child stake applies at 19 sols after a living child's birth and not at 21; a dead child gives no stake.
   - The clamp at plus and minus 1.
   - The hard window counts hard sols over the last 10, and the hard clause is the most frequent failing clause, ties ice, air, food. The hard read uses the ages.md 4.2 formulas for 1a, 1b and 5.
7. **Sway.** An isolated voice has stance equal to lean. Two voice friends move toward each other by the formula. A close friend weighs `close_weight`. A non-voice friend is ignored. Reversing the order of `world.beings` gives identical stances.
8. **Gatherings and meetings.**
   - No meeting before the interval.
   - With 30 voices, a best gathering of 4 does not meet and 5 does. With 80 voices, 7 does not meet and 8 does (`ceil(0.1 x 80)`).
   - The earliest tick wins a tie, and the lower building id within a tick.
   - The meeting place is the best building. `best` is cleared after a meeting. Meetings happen only in Council.
9. **Raise.**
   - At the first meeting the highest-stance voice of the room is named (ties lowest id), with the place phrase.
   - When nobody in the room is above `yes_above`, there is no raise and the quiet line is logged once per term (the `quiet_hard` variant at hard share 0.5, with the clause phrase). There is no quiet line when a proposal is open or the topic is pledged.
   - Never two open proposals.
   - The "again" text comes after a set-aside once 30 sols have passed, not at 29. After a hard set-aside, there is no re-raise while the hard share is at least 0.5, even after 30 sols.
10. **Votes.**
    - Yes and no are exact at the boundaries by cross-multiplied counts: 6 of 10 at 0.6 carries the run, 5 of 10 does not.
    - A carrying vote then a non-carrying vote resets the run; two in a row pledge.
    - Two rejecting votes set the dome aside: with the hard text and clause phrase when the hard share is at least 0.5 (a single hard sol in a calm window gives the plain text, naming the no speaker), else the plain text.
    - 12 open votes give `set_aside_long`.
    - Divided: the line is offered once per proposal, with the speaker rules.
    - Reasons: a staged yes speaker whose largest term is size gets "since the modules are full"; a speaker whose lean sign differs from their stance gets "as their friends do"; a no speaker with hard dominant gets the clause phrase; `{adj}` is the speaker's top trait adjective.
11. **Pledge and after.**
    - The pledge sets `pledge_sol`, appends one chapter and blocks any further raise. It survives a fall-back and a re-entry.
    - The pledge line names the proposer, the place of the pledging meeting and the reason with the largest mean over yes voices. It is the `pledge_divided` text when the divided line was offered (logged or dropped).
    - Aftermath at pledge + 4: `aftermath_round` when the doubter's stance is now yes, `aftermath_still` otherwise, nothing when the doubter is dead or the age is not Council.
    - The after-pledge line comes once at the first meeting 30 or more sols after the pledge.
12. **Lapse.** A split or fall-back with a proposal open sets outcome `lapsed`, logs nothing, and allows the "again" raise in the next term.
13. **Circles family.**
    - The first line comes at settled + 50 sols when web or chosen are the only failing clauses. `circles_few` is used instead when voices are under 12.
    - The second line (`circles_again`) comes 100 sols later; there is no third.
    - Both come again in a later Settlement term.
14. **Line cap.** A staged meeting where divided and pledge both fire logs only the pledge (divided variant), with `lines_dropped` 1. Generally, no boundary logs two Council-kind lines.
15. **Texts.** Every text from data is rendered with sample names, every place phrase, every clause phrase, every reason and every adjective and season. None has a digit or a `%`, and none contains "vote", "percent", "Landing", "fail", "is building" or "has built" (case-insensitive). The first sentence of both pledge texts is "The council has agreed to build a dome."
16. **Purity.** Seed 42, 120 sols (long enough to reach Council on a staged override if needed).
    - Worlds with `council_enabled` true and false have equal beings (id, building, state, energy), equal stocks, equal relationship stats and equal next 1,000 `rng` draws.
    - Their `age_history` projected onto Landing and not Landing is equal.
    - Two same-seed worlds have identical `stats.council` and logs.
17. **Data.** Key-path parity for `council.json` (section 14), both ways, and the sanity rules:
    - `exit.trust_share_below < entry.trust_share_min`;
    - `entry.trust_ok_min`, `entry.recent_ok`, `exit.split_min` and `exit.recent_below` are each at most `trust.window_sols`;
    - `support.no_below < 0 < support.yes_above`;
    - `decide.carry_share > 0.5`; `decide.divided_share < 0.5`;
    - `topics` is non-empty, and each topic has a `text` and `lean` block;
    - every building kind in `buildings.json` has a place phrase;
    - no Council key in `ages.json` (ages test 18 kept).
18. **Balance helpers.**
    - The projected `age` column prints `S` for `council`.
    - `cn` prints `-`, `C`, `P`.
    - `council_hash_proof` helpers strip `cn` on synthetic tables and refuse a table whose last field is not `cn`.
    - The T10 projection helper maps a synthetic history (S, C, L, S, C, S) to (S, L, S) with 2 projected changes.
19. **HUD.**
    - The age word is "Council" from `council.json`.
    - The strip shows at most 3 merged chapters.
    - The pledge stays pinned: with three later age entries, the strip shows the latest 2 and the pledge, in time order.
    - The HUD source reads no stance, reading, share or `session_log`.
20. **Relationships off.** With `relationships_enabled` false, the Council appends 0.0 readings and never enters.
21. **Existing suite with the module on.** Every Task 1 to 4 test passes. Any test changed for log pollution or the `sols_in_age` key is listed in the task log with the reason.

## 14. Tunables (`data/council.json` unless stated; E = estimate for the probe)
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| council.age.name | text | Council | HANDOFF 7 |
| council.topics | list of topic ids | ["dome"] | lead (rev 2, emergence M3) |
| council.text.enter / enter_again / split | text | 7.1 | lead, clarity S5 |
| council.text.quiet / quiet_hard / circles / circles_again / circles_few | text | 7.2 | lead, clarity M2, feel 2 |
| council.text.place.habitat / green_room / workshop / reactor / archive / comms / other | phrase | 7.2 | lead |
| council.text.clause.ice / air / food | phrase | 7.2 | lead, clarity M4 |
| council.dome.text.proposal / proposal_again / divided / set_aside / set_aside_hard / set_aside_long / pledge / pledge_divided / pledge_why_personal / aftermath_round / aftermath_still / after_pledge | text with {a}, {b}, {place}, {ra}, {rb}, {why}, {clause} | 7.2, 7.3 | lead, feel 1 and 3, clarity M3 and S3 |
| council.dome.text.reason.yes.size / means / child / personal / friends | clause | 7.3 | lead, feel 6, clarity S2 |
| council.dome.text.reason.no.means / hard / personal / friends | clause | 7.3 | lead, feel 6, clarity S2 |
| council.voice.min_age_sols | sols | 40 | lead, E |
| council.trust.window_sols | readings | 20 | lead, E |
| council.entry.settled_sols | sols since the latest Settlement entry | 30 | lead, E |
| council.entry.trust_share_min | share of voices | 0.5 | lead, E |
| council.entry.chosen_share_min | share of voices | 0.5 | lead (rev 2, emergence M2), E |
| council.entry.chosen_friends_min | chosen voice friends | 1 | lead (rev 2), E |
| council.entry.trust_ok_min | readings of the window | 16 | lead, E |
| council.entry.recent_ok | readings | 3 | lead, E |
| council.entry.voices_min | voices | 12 | lead, E |
| council.exit.trust_share_below | share of voices | 0.3 | lead, E |
| council.exit.split_min | readings of the window | 16 | lead, E |
| council.exit.recent_below | readings | 3 | lead, E |
| council.min_dwell_sols | sols | 20 | lead (matches ages) |
| council.session.interval_sols | sols | 5 | lead, E |
| council.session.min_voices | voices together at one tick | 5 | lead, E |
| council.session.min_voices_share | share of voices together at one tick | 0.1 | lead (rev 2, clarity S1), E |
| council.dome.lean.ambition / caution | per unit of trait above 0.5 | 1.0 / 1.0 | lead, E |
| council.dome.lean.size / means / hard | lean at a trait of 0.5 | 0.15 / 0.1 / 0.4 | lead (rev 2, emergence M1; were 0.3 / 0.3 / 0.8 flat), E |
| council.dome.lean.child | lean | 0.15 | lead (rev 2, emergence M1), E |
| council.dome.lean.base | lean | 0.0 | lead, E |
| council.dome.cond.size_from / size_span | beings | 40 / 80 | lead, E |
| council.dome.cond.child_sols | sols since a child's birth | 20 | lead (rev 2), E |
| council.cond.hard_window_sols | sols | 10 | lead, E |
| council.sway.share | weight of friends | 0.5 | lead, E |
| council.sway.close_weight | weight of a close friend | 2.0 | lead, E |
| council.support.yes_above / no_below | stance | 0.1 / -0.1 | lead, E |
| council.decide.carry_share / carry_sessions | share of voices / votes in a row | 0.6 / 2 | lead, E |
| council.decide.reject_share / reject_sessions | share of voices / votes in a row | 0.5 / 2 | lead, E |
| council.decide.divided_share | share of voices, each camp | 0.25 | lead, E |
| council.decide.max_open_votes | votes | 12 | lead, E |
| council.proposal.reraise_sols | sols after a set-aside | 30 | lead, E |
| council.lines.hard_share_min | hard share | 0.5 | lead (rev 2, clarity M4, feel 5), E |
| council.lines.circles_after_sols | sols after `settled_sols` | 20 | lead, E |
| council.lines.circles_again_sols | sols after the first circles line | 100 | lead (rev 2, feel 2), E |
| council.lines.circles_max | lines per Settlement term | 2 | lead (rev 2, feel 2) |
| council.lines.aftermath_sols | sols after the pledge | 4 | lead (rev 2, feel 1b), E |
| council.lines.after_pledge_sols | sols after the pledge | 30 | lead (rev 2, clarity S3), E |
| council.balance.council_min_seeds / pledge_min_seeds / argue_min_seeds | seeds of 5 | 3 / 1 / 2 | lead, E |
| council.balance.max_council_changes | changes per 300 sols | 4 | lead, E |
| council.balance.faction_trait_share_min | share of divided votes | 0.8 | lead, E |
| council.balance.lines_per5_max | lines per 5 Council sols | 1.0 | lead, E |
| council.balance.on_sol_ms_max | ms | 3.0 | lead, E |
| council.balance.step_share_max | share of mean step | 0.02 | lead, E |
| council.balance.lockstep_share | share of voices on one side | 0.95 | lead (rev 2, emergence M1), E |
| council.balance.noroom_share_max | share of eligible Council sols with no meeting | 0.5 | lead (rev 2), E |
| relationships.balance.log_share_flag | share of log entries | 0.15 | feel F4-3, E |
| relationships.balance.r9_seeds | list of seeds | 42, 7, 99, 1234, 2026, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89 | lead (E4-4) |
| relationships.balance.r9_gain_min | share | 0.03 | lead, E |
| relationships.balance.r9_seeds_better_min | seeds of 15 | 10 | lead (rev 2, emergence S4), E |
| relationships.balance.repeat_rise_max | hours a sol | 0.5 | lead (rev 2, emergence S4), E |

**Reused, not duplicated**: `ages.sample.o2_min_fraction`, `food_min_fraction`, `ice_min_sols`, `ages.season_phrases`, `ages.hud.chapters_shown`, `colony.consumption.ice_per_being`, `relationships.effects.lonely_pull`, `persona.traits`, `persona.adjectives`, `persona.dims`, `SimWorld.STEP_EPS`, `Ages.CMP_EPS`.

**Not data**: the ids `council`, `council_again`, `council_split`; the line kinds; the order of steps in 5.8; the tie rules and orders (reason ties, clause ties); the line priority of 7.4; "no voices reads 0.0"; the centre 0.5 of the trait terms and the temperament factor `trait / 0.5`.

**Who reads what**: `balance.*` keys are read by the probe and `balance_lib.gd` only; `age.name` and `text.*` by the view or the log; the rest by `sim/council.gd`. `SimData.council()` is the accessor, and `data_hash` in `balance_lib.gd` adds `council`.

### Key-path list (machine-readable; one leaf per line)
Same rules as ages.md 13. The `relationships.` lines are existence checks only. `council.topics` is a list leaf.
```keys:
council.age.name
council.topics
council.text.enter
council.text.enter_again
council.text.split
council.text.quiet
council.text.quiet_hard
council.text.circles
council.text.circles_again
council.text.circles_few
council.text.place.habitat
council.text.place.green_room
council.text.place.workshop
council.text.place.reactor
council.text.place.archive
council.text.place.comms
council.text.place.other
council.text.clause.ice
council.text.clause.air
council.text.clause.food
council.dome.text.proposal
council.dome.text.proposal_again
council.dome.text.divided
council.dome.text.set_aside
council.dome.text.set_aside_hard
council.dome.text.set_aside_long
council.dome.text.pledge
council.dome.text.pledge_divided
council.dome.text.pledge_why_personal
council.dome.text.aftermath_round
council.dome.text.aftermath_still
council.dome.text.after_pledge
council.dome.text.reason.yes.size
council.dome.text.reason.yes.means
council.dome.text.reason.yes.child
council.dome.text.reason.yes.personal
council.dome.text.reason.yes.friends
council.dome.text.reason.no.means
council.dome.text.reason.no.hard
council.dome.text.reason.no.personal
council.dome.text.reason.no.friends
council.dome.lean.ambition
council.dome.lean.caution
council.dome.lean.size
council.dome.lean.means
council.dome.lean.hard
council.dome.lean.child
council.dome.lean.base
council.dome.cond.size_from
council.dome.cond.size_span
council.dome.cond.child_sols
council.voice.min_age_sols
council.trust.window_sols
council.entry.settled_sols
council.entry.trust_share_min
council.entry.chosen_share_min
council.entry.chosen_friends_min
council.entry.trust_ok_min
council.entry.recent_ok
council.entry.voices_min
council.exit.trust_share_below
council.exit.split_min
council.exit.recent_below
council.min_dwell_sols
council.session.interval_sols
council.session.min_voices
council.session.min_voices_share
council.cond.hard_window_sols
council.sway.share
council.sway.close_weight
council.support.yes_above
council.support.no_below
council.decide.carry_share
council.decide.carry_sessions
council.decide.reject_share
council.decide.reject_sessions
council.decide.divided_share
council.decide.max_open_votes
council.proposal.reraise_sols
council.lines.hard_share_min
council.lines.circles_after_sols
council.lines.circles_again_sols
council.lines.circles_max
council.lines.aftermath_sols
council.lines.after_pledge_sols
council.balance.council_min_seeds
council.balance.pledge_min_seeds
council.balance.argue_min_seeds
council.balance.max_council_changes
council.balance.faction_trait_share_min
council.balance.lines_per5_max
council.balance.on_sol_ms_max
council.balance.step_share_max
council.balance.lockstep_share
council.balance.noroom_share_max
relationships.balance.log_share_flag
relationships.balance.r9_seeds
relationships.balance.r9_gain_min
relationships.balance.r9_seeds_better_min
relationships.balance.repeat_rise_max
```

## 15. Plan questions answered, Task 4 inputs, scope cuts
### Plan questions Q1 to Q10
| Q | Answer | Whose |
| --- | --- | --- |
| Q1 Council gate | Settlement held 30 sols since its latest `age_history` entry; the voice web at least 0.5 and the chosen-friend share at least 0.5, each on 16 of 20 readings including the last 3; at least 12 voices; split when the web is under 0.3. Recurrence and fall-back are in 5.3 to 5.5. It never gates on the first Settlement entry, and `web_by_sol`, `second_by_sol` and `lonely_by_sol` are not gate inputs (5.2 says why) | owner, O1 |
| Q2 Texture memory | no new art | owner, O4 |
| Q3 Hashes | Council hash-neutral; one possible reset, from the lonely pull, with owner approval | owner, O3 |
| Q4 Scope | In: the Council age, voices, two trust readings, gatherings and meetings, the topic-keyed proposal machinery with one topic (the dome), raise, argument with reasons, divided camps, set-aside, pledge, aftermath. Later: building the dome, the Dome age, "more domes", other topics (water rule, O5), dislike bonds | owner, O2 and O5 |
| Q5 Behaviour | none in the shipped state; "commits to build" records a pledge (5.9) | owner, O2 |
| Q6 What the player sees | section 7: three age lines, sixteen Council texts across eleven kinds, reason and clause phrases, the age word, the merged strip with the pinned pledge; no numbers; no being panel; no click-to-focus in Task 5 | lead |
| Q7 God lever | None new in Task 5. Facts: `sim/powers.gd` holds only the Good fortune multiplier; Inspire, Grace and Send a sign are not built. The god's reach on the Council is indirect today: keeping power up does not touch the ice or the web. Recorded for later: Send a sign as a sway on the undecided, acting by temperament (curious lean toward, steady away; emergence idea). It fits HANDOFF 4's "beings sense a god" and should read through the same lines (clarity idea) | lead |
| Q8 Randomness | no draws anywhere (section 9) | lead |
| Q9 Targets and cost | C1 to C8, flags, T12, T10 projected, R9 over 15 seeds with the seed-count and repetition clauses (sections 10, 11, 12) | lead |
| Q10 Lonely definition and run content | `friend_count` 0 as K1; the lonely pull alone; temperament-scaled pull and parent-room anchor not in Task 5 (section 10) | lead |

### Task 4 inputs (relationships.md section 19)
| Input | Decision |
| --- | --- |
| Lonely pull alone, breadth report (E4-1) | In, section 10; the breadth report is now also an adoption clause |
| Temperament-scaled pull (E4-2) | Out of Task 5 |
| Parent-room anchor (E4-3) | Out of Task 5; named next lever if the breadth report shows breadth without repetition |
| R9 over more seeds (E4-4) | In, 15 seeds, mean and seed count; a fork is not possible (no save or clone) |
| God lever on gathering (E4-5) | Deferred (Q7); the gathering pull is O3 (c) |
| Lonely definition (E4-6) | `friend_count` 0 kept |
| K1 readability, "knows no one well yet", "at last" (C4-3, C4-4) | Deferred: no being panel exists, and Task 5 adds none |
| Probe additions (F4-1 to F4-4), `lines_dropped_by_type` (RN-7) | In, section 10 |
| Structural colony line (C-7) | In, as the circles family and the split line |
| Click-to-focus (C-4, I5) | Deferred; Council entries carry the ids |
| Dislike bonds (S4) | Deferred; camps come from stance, not from negative bonds |

### Scope cuts (lead; cut order if time runs out, first cut first)
1. The after-pledge line (falls back to post-pledge silence).
2. The second circles line and `circles_few` (keep the first circles line).
3. Probe replays (item 9).
4. The child stake (the lean keeps the temperament-weighted terms; the `child` reasons go).
5. The aftermath line (the pledge's divided variant still carries dissent).
6. The faction trait report (C6 becomes reported).
7. Divided reasons (the divided line falls back to "{a} speaks for building it; {b} says not yet.").
8. The circles line itself (keep the split line).

**Cut last**: the quiet line, the divided line (feel: keep it above other cuts), the pledge's proposer, place and reason.

**Never cut**: both trust readings, the projected `age` column and hash proof, T12, the pledge with its pinned chapter, `age_history` entries, the one hardship clock for texts, the per-boundary line cap.

**Out of Task 5 entirely** (cuts, recorded so that no one re-adds them silently):
- building a dome, the Dome age, the water rule (O5), reneging on a pledge;
- new god powers, a gathering pull, attendance-weighted sway and proposer standing (emergence S1);
- stance hysteresis (emergence S3);
- a first-raise delay (feel 4; probe-triggered only);
- a dome state word in the strip (clarity S4);
- re-firing the divided line, swing lines, bridge-person lines;
- lines for a voice dying with a proposal open, for a first Mars-born proposer, and for a founder named in the entry line;
- a meeting highlight or camera nudge (O4 (b));
- dislike, a being panel, click-to-focus, new art, AI-written speech.

## 16. Requests to the assistant designers (the main session runs them)
Round 1 (revision 1) is answered in section 17. For revision 2, there is no new round unless the owner's answers change O1, O2 or O5. The code reviewer is asked to check:
- the projected `age` column edit (9);
- the T10 projection helper (12);
- the chosen-friend count reading the `kin` and `crew` flags without a second pair walk (5.2, 11);
- that the reason and child-stake reads write nothing (9, purity test 16).

## 17. Design review record
Reviewers: emergence (Will Wright lens), feel (Eric Barone lens), clarity (Karoliina Korppoo lens). Reviews: `docs/design/reviews/council-emergence.md`, `council-feel.md`, `council-clarity.md` (revision 1). Decision key: A adopted, AM adopted modified, D deferred, R rejected.

### Reviewer claims checked against the code and the Task 4 data
| Claim | Check | Result |
| --- | --- | --- |
| Founders' crew inflates early trust (emergence M2) | `relationships.json`: `seed.crew` 0.35 and `seed.kin_base` 0.30 + 0.25 x warmth, both at or above `lines.friend` 0.30 (friend drop 0.15). `relationships.begin` seeds all founder pairs, and `_births` seeds every newborn with its living parent (0 kinless births in all 15 Task 4 runs). Every parent chain ends at a founder | **Confirmed.** At the earliest gate the voice web is joined by seeded bonds; web share at sol 60 is 0.81 to 0.92. Drove the chosen-friend clause |
| Voices >= 12 reachable by the gate sol (emergence M2) | Earliest entries are sols 97, 88, 84, 95, 83. Voices are 7 plus births by entry minus 40, interpolated from the Task 4 30-sol pop tables (pop at sol 30: 19, 12, 10, 12, 12; at 60: 27, 22, 29, 27, 26), with no deaths before sol 150 | **Reachable on all five, about 18 to 26 voices (E).** The clause does not bind at first entry; kept as a floor |
| Personal terms about plus or minus 0.15 against size +0.3 and hard -0.8 (emergence M1) | `persona.gd` and `persona.json`: trait = clamp((raw + 0.3) / 1.5). Ambition averages three traits, so its spread is about 0.08 to 0.12, with means near 0.42 (ambition) and 0.44 (caution). Arithmetic, not a measurement | **Confirmed.** The personal spread is about 0.15 (1 sd), so revision 1 overstated it. Shared terms were 2 to 5 sd: lockstep votes. Formula rewritten (5.6); probe item 5 measures the real spread |
| Meeting size should scale with the colony (clarity S1) | `buildings.json` has no room capacity. Room sizes are not measured (relationships.md 6.1 measured pair hours only) | Unknown. Adopted with a 0.1 share and the NOROOM flag rather than clarity's quarter |
| "Hard" clock inconsistency (clarity M4) | Revision 1, 5.8: the hard set-aside text used "this sol is a hard sol", while the lean used the 10-sol share | **Confirmed.** Unified on the hard share at 0.5 |
| Post-pledge silence of about 150 to 170 sols (emergence M3, clarity S3) | The earliest pledge is about sol 98 (entry 83 + 15), and runs are 300 sols | **Confirmed** as an upper bound; a pledge later in the run shortens it |

### Emergence
| # | Item | Decision |
| --- | --- | --- |
| M1 | Lean dominated by colony terms; scale personal gains and/or per-voice stakes; SIZE-DOMINANT means rewrite | **AM.** Verified. Shared weights cut (size 0.15, means 0.1, hard 0.4). Conditions act through temperament (`trait / 0.5`), not through `(trait - 0.5)` as proposed: the proposed form would make hardship push bold voices toward yes, an odd signal. One personal stake (a child born within 20 sols, +0.15). Energy, hunger and friend-loss stakes were not taken (scope; energy flickers within a sol). LOCKSTEP flag added. SIZE-DOMINANT or LOCKSTEP means rewrite (5.6) |
| M2 | Trust gate is a timer early and a no-op later; second cut on non-crew/kin friends; check voices >= 12 | **AM.** Verified. Second reading: share of voices with at least 1 chosen (non-kin, non-crew) voice friend at least 0.5, on the same 16-of-20 rule. The proposal's "2+ friends for 0.6 of voices" is a replay point, not the start value: there is no data on chosen-friend counts among voices, and 2+ for 0.6 risks a gate no seed passes. Voices check done (above). The "which clause passed last" row is kept. The split stays on the web only |
| M3 | One matter then silence; topic-generic proposals; leans to O5 (b) | **AM.** Machinery is keyed by topic now (5.8, data under `council.dome.*`), and the dome ships alone. The water rule stays the owner's question (O5); the lead recommends (a) |
| S1 | Attendance-weighted sway, proposer standing | **D.** It adds an invisible second channel to an uncalibrated stance model. It is the first candidate lever once C6 passes |
| S2 | Carry/pledge lines name the cause from the largest positive term | **A** as the pledge `{why}` (7.3) |
| S3 | Hysteresis near ice thresholds (no_below -0.15 while open, or require recovery) | **AM.** Recovery adopted for re-raise after a hard set-aside (with feel 5). State-dependent thresholds rejected: the 10-sol hard share already smooths, and "the talk went round and round" is a legitimate outcome of flicker |
| S4 | Lonely adoption: 10 of 15 seeds or SE; breadth not dropping; pull must not turn the gate into a timer | **AM.** 10 of 15 adopted as clause 2, and SE reported. Breadth adopted as a no-repetition clause using the E4-1 measure (+0.5 h). Timer check adopted as a report to the owner, not a clause, because the Council's thresholds are calibrated after the decision |
| Ideas | Reneging; swing line; bridge line; Send a sign by temperament | D (reneging, swing, bridge); Send a sign recorded under Q7 |
| Loop | A gathering pull is the real danger | Agreed: O3 (c) stays recommended against |

### Feel
| # | Item | Decision |
| --- | --- | --- |
| 1a | Pledge names proposer and place, stored in the chapter | **A** (7.2). The chapter stores the full text; the strip shows the fixed first sentence |
| 1b | Aftermath line 3 to 5 sols later: a named no-voter now helping | **AM.** At pledge + 4. It reports the doubter's real stance ("has come round" or "still says not yet, but will build with the rest"). "Helping" was not taken, because nothing is being built and the log must not claim work the sim does not do |
| 2 | Second, rarer circles line (+100 sols, different wording; counter) | **A** (7.5); `circles_max` 2 |
| 3 | Warmth pass: set-aside names the strongest no speaker; keep "a roof of sky"; season phrase on the pledge | **AM.** Set-aside names the no speaker; the roof of sky is kept. Season phrase **R** for the pledge: the line already carries name, place, reason and "tonight", and a fourth clause overloads it. Age lines keep their season sentence |
| 4 | First-raise delay if raises come within 6 sols on most seeds | **D**, probe-triggered (item 6) |
| 5 | After a hard set-aside, the next raise needs a non-hard sol | **AM.** Needs the hard share below 0.5 (the one clock), not a single calm sol |
| 6 | Divided line carries a one-clause reason from the speaker's dominant term | **A**, merged with clarity S2 (7.3), plus a "friends" reason that shows sway |
| 7 | Pin the pledge chapter | **A** (7.6), with clarity M1 |
| Ideas | Death with proposal open; first Mars-born proposer; founder named in entry | D |
| Scope | Order 1a, 6, 1b; keep the divided line above other cuts | **AM.** The cut list (15) keeps the divided line, the pledge's proposer, place and reason, and the quiet line last. Aftermath is cut before divided reasons |

### Clarity
| # | Item | Decision |
| --- | --- | --- |
| M1 | Pin the pledge chapter (fixed slot, or latest 2 plus pledge) | **A**: latest 2 plus pledge when it would be pushed off; HUD test 19 |
| M2 | Silent gates: "nothing raised" line, first-meeting line, circles for voices under 12, cap 1 line per 5 sols | **AM.** One quiet line per Council term at the first meeting that raises nothing. It doubles as the first-meeting line, because the first meeting always logs either a raise or the quiet line, so a separate first-meeting line is R. `circles_few` A (it binds only after a die-off, but it costs one text). Cap 1 per 5 sols R: the interval and C7 already bound the rate, and the per-boundary cap (S6) handles collisions. The meeting that waits for a big enough room stays silent; NOROOM flag instead (D for a line) |
| M3 | Pledge reason by largest lean term; divided variant; "will build", never "is building" | **A** (7.2, 7.3; text test 15) |
| M4 | Hard set-aside on the same clock as the lean; name the failing clause | **A**: hard share at least 0.5; ice, air, food phrases |
| S1 | Meeting size max(5, quarter of voices); max-trust flag | **AM.** Share 0.1, not 0.25: room sizes are unmeasured and rooms have no capacity, so a quarter (25 at 100 voices) risks a Council that never meets. NOROOM flag. CEILING flag **A** |
| S2 | Divided speakers get a fixed trait phrase; re-fire on death or swap | **AM.** The trait phrase is the "personal" reason with `{adj}` (7.3). Re-fire **D** |
| S3 | One-off "no new matter" line after the pledge | **A** as `after_pledge` (first cut if time runs out) |
| S4 | Dome state word in the strip | **R** for Task 5. It is a status meter in words, and the pinned pledge carries the one state that matters for long. Revisit with the dome-building task |
| S5 | Entry line gets a cause sentence | **AM**: folded into the existing enter texts, no new key |
| S6 | At most one Council line per sol boundary | **A** (7.4), with a priority order and `lines_dropped` |
| Ideas | Highlight on the meeting building; Send a sign reads through the same lines | Highlight is owner O4 (b), recommended against for Task 5; Send a sign recorded under Q7 |

### Dissent and tensions resolved
- **O5: feel and clarity (a) against emergence (b).** Emergence argues that one matter, followed by silence, makes the Council a single event rather than a possibility space, and that building the water rule shipped off costs no hashes. Feel and clarity argue that the water rule changes births and therefore every ice crisis, so it deserves its own task and calibration. Clarity accepts post-pledge silence as the price; feel wants a hook for Task 6. The lead sides with (a) for Task 5 on calibration grounds. Task 5 already holds one behaviour run (the lonely pull) and an uncalibrated stance model, and a second shipped-off mechanic would double the probe work before either is measured. Emergence's structural point is taken as far as it costs nothing: the machinery is topic-keyed, so the water rule is one data block and one lean formula later. The after-pledge line names the silence instead of hiding it. Emergence's dissent stands and is put to the owner as O5 (b).
- **M1 form: emergence's multiplier against the lead's.** Emergence proposed scaling `(trait - 0.5)` by colony conditions. Under hardship that makes low-caution voices lean further toward yes, so the bold would get bolder as the ice runs out. That is a story, but not the one the hard-share texts tell. The lead uses `trait / 0.5`, which scales the shared push by temperament without flipping sign. Emergence's test (SIZE-DOMINANT or LOCKSTEP means rewrite, not retune) is adopted unchanged.
- **Meeting size: clarity's quarter against the lead's tenth.** Clarity wants a meeting to look like a council at 160 beings. The lead agrees in principle but has no measured room sizes, and rooms have no capacity. 0.1 plus the NOROOM flag lets the probe decide.
- **Line pacing: clarity's 1 per 5 sols against feel's want for more moments.** Feel's additions (aftermath, second circles line) and clarity's (quiet, after-pledge, circles_few) both add lines. The per-boundary cap and C7 (1.0 per 5 Council sols) hold them. If C7 fails, the scope-cut order (15) removes lines in a fixed order.
- **Aftermath: feel's "helping" against honesty.** Feel wanted a former no-voter shown helping. Nothing is being built, so the lead reports the doubter's actual stance instead. Feel's intent, that the pledge has consequences for named people, survives.

## Changelog
- 2026-10-07: revision 1 (lead designer). Draft for the three assistant reviews and the code review. Owner questions O1 to O5. Shipped behaviour is hash-neutral; the only behaviour change in Task 5 is the lonely-pull run, adopted only by owner decision. `data/` not edited.
- 2026-10-07: revision 2 (lead designer). The three reviews are folded in (section 17), and the factual claims were checked against `relationships.json`, `persona.gd`/`persona.json`, `buildings.json` and the Task 4 tables.
  - **Gate**: a chosen-friend clause (5.2, 5.3).
  - **Lean**: rewritten with temperament-weighted conditions and a child stake (5.6).
  - **Topics**: proposal machinery keyed by topic, with the dome texts and lean under `council.dome.*` (5.8, 14).
  - **Hardship clock**: one hard share for texts, re-raise and lean, with clause naming (5.8, 7).
  - **New lines**: speaker and pledge reasons (7.3); pledge names proposer and place, with a divided variant (7.2); aftermath and after-pledge lines (5.9); quiet line and circles family (7.2, 7.5).
  - **Line cap**: one Council line per sol boundary (7.4).
  - **Strip**: the pledge chapter is pinned (7.6).
  - **Meetings**: minimum size scales with voices (5.7).
  - **Lonely-pull adoption**: seed-count and no-repetition clauses (10).
  - **Probe**: CEILING, LOCKSTEP and NOROOM flags (12).
  - **Scope**: explicit cut list (15). Owner questions updated with reviewer input.

  Shipped behaviour is still hash-neutral: every addition reads the world and writes only `stats.council` and the log. `data/` not edited; not committed.
