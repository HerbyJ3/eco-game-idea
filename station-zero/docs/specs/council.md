# Spec: council and diplomacy (Task 5): gatherings, proposals, support, the decision to build a dome (revision 1)

Source of truth: HANDOFF.md sections 1, 2, 4, 7, 8, 9, 10. Plan and open questions Q1 to Q10, lonely-run placement: `docs/tasks/task-5-plan.md`. Format, `age_history` and the Task 5 gate: `docs/specs/ages.md` (sections 2, 3, 6, 7, 8.2, 12, 18 item 5). Social inputs: `docs/specs/relationships.md` (sections 7, 8, 11, 17 "Run 2 findings" and "Round 4 reviews", 18, 19; known issues K1 to K3). Measurements read: `docs/balance/task-4-calibration.md` (trust readings per seed, item 2), `docs/balance/task-4-log.md` (30-sol tables, Task 4 table hashes). Sim facts read: `sim/world.gd` (phase order of `step()`, sol block, `_init_stats`), `sim/ages.gd` (`decide`, `on_sol`, `_record`), `sim/relationships.gd` (`pairs`, `present`, `ticks`, `friend_count`, `_reading`, `pull`), `sim/being.gd` (`_restless_travel`, `is_inside`), `sim/buildings.gd`, `sim/powers.gd` (only the Good fortune multiplier exists), `tests/balance_lib.gd` (the `age` column prints `S` only for `settlement`, line 109), `data/*.json`.

Locked decisions respected: influence-only god (nothing here is a command; no god power reads or writes a stance or a vote); ages not meters (no support share, trust value, count or bar reaches the player; the windows are private); naturalism (the Council begins when grown colonists know each other, not after a fixed time; a proposal is raised by a named person who wants it and carried only when most of the colony wants it); per-being energy, power as a budget and ice as pressure are untouched (in the shipped state the module writes no colony, being, building or resource state).

Tunables live in `data/council.json` (new) and new balance keys in `data/relationships.json`. No tunable in the new module `sim/council.gd`. This spec describes behaviour and numbers only, no code. **Every number marked E is an estimate until the calibration probe (section 12) measures it.**

## Open for the owner
Five questions. Each lists the recommendation first, its cost and the facts behind it. The spec is written to option (a) of each; any other answer is a revision.

**O1. The Council gate: what has to be true before the colony is called a Council?** (plan Q1; ages.md 18 item 5, still open)
- (a) **Recommended: Settlement held for 30 sols since its latest entry, and trust among grown colonists.** "Voices" are the founders and Mars-born at least 40 sols old. Trust is the share of voices in the largest web of friends among voices. It must be at least one half on 16 of the last 20 sols, including the last 3, with at least 12 voices. The Council splits back to Settlement if trust stays under 0.3 on 16 of 20 sols. If the gate waits only on trust, one line says so in words (section 7, the "circles" line). Facts: the existing `web_by_sol` falls from 1.0 at landing to 0.35 to 0.97 at sol 300. It is high early because of the founders' crew, and its denominator includes every newborn, so the lonely late newborns of K1 would hold the Council back. The new reading costs about 1 to 3 ms once a sol (E). Risk: on the loosely knit seeds (42, 99, 2026; overall web 0.45 to 0.77 at sol 100) the Council may come late or not at all. That is the honest story, and it ties the Council to the lonely-pull run.
- (b) Settlement held for N sols, nothing else. Cost: the cheapest option, but it is a timer in disguise. The Council would arrive at about sol 83 to 97 on every seed and trust would play no part, against HANDOFF 7 ("relationships and trust form").
- (c) The existing lists only (`web_by_sol` of at least 0.5 over a window). Cost: no new reading. It is inflated by the crew: the measured web at sol 60 is 0.66 to 0.92, so the gate opens as soon as the 30 sols pass on most seeds. Later it counts friendless newborns against the Council.

**O2. What does the decision do in Task 5?** (plan Q4, Q5)
- (a) **Recommended: a pledge, announced and recorded; the Council age continues; no dome is built in Task 5.** There is one log line, and the pledge is a chapter in the pinned strip (section 7). The dome's construction and the Dome age are a later task. They need a dome building kind, art, and life inside without suits (HANDOFF 7). Cost: the climax has no physical consequence yet. Facts: hash-neutral; the strip keeps it visible.
- (b) The pledge begins the Dome age now, with an age line and the word "Dome" on the clock line, and nothing is built. Cost: an age word for a dome that does not exist. HANDOFF 7's "town life inside the first dome" would be false until a later task builds it.
- (c) The pledge starts a dome construction site in the sim (a new kind, a large regolith cost, crews), and the Dome age begins when it is finished. Cost: a behaviour change and a baseline reset. The single construction site would block habitats and reactors for a long time, with ice and crowding consequences to calibrate. It needs art or a procedural placeholder (texture budget 47.1 of 48 MB). It roughly doubles Task 5.

**O3. Behaviour, hashes and where the lonely-pull run sits.** (plan Q3, section 5)
- (a) **Recommended: the Council ships hash-neutral. The lonely-pull run is plan step 3 (plan option (a)), after the spec review and before the Council tests.** If it meets the adoption rule stated in advance in section 10, you approve one baseline reset (new hashes recorded once), and the Council is calibrated on that baseline. If it does not, the pull stays at 0.0 and K1 carries over. Facts: the Council's trust gate reads the friend web that the pull changes. Calibrating the Council before the pull decision (plan option (c)) would mean calibrating it twice. Option (b) of the plan is equivalent by design, because this spec already carries the lonely run's design note (section 10).
- (b) Task 5 stays fully hash-neutral: the lonely run is measured and reported, and nothing is adopted in Task 5. Cost: K1 ships for a third task, and the Council is calibrated on a web that may change later.
- (c) As (a), plus a Council behaviour: a gathering pull on session evenings (voices drift toward the room where most voices are), built and shipped off, then probed. Cost: a second reset and a second calibration, and a loop to bound (more gathering, more sessions, more gathering).

**O4. New art for the Council?** (plan Q2)
- (a) **Recommended: no new art.** The Council lives in the log, the age word on the clock line and the chapters strip. Cost: no meeting is seen on screen, only read. Facts: 0 MB; texture memory is 47.1 of 48 MB.
- (b) One asset (for example a meeting-table variant of the habitat interior) after the art director frees memory. Cost: a budget pass first, about 1.5 credits, and a view change.
- (c) Raise the budget (for example to 64 MB). Cost: it needs a real-GPU measurement, which this host cannot make; the Task 4 frame triggers wait on one too.

**O5. A second matter for the Council: your water rule** (HANDOFF 4: "the beings agreeing on a rule to slow births in the council stage"; plan Q4)
- (a) **Recommended: the dome only in Task 5; the water rule is the next matter for later Council work.** Cost: one matter makes the Council's arguments thinner, one topic at a time. Facts: the rule changes births, so it changes every hash and moves the ice crises (thirst deaths 10, 0, 22, 0, 5 at sol 300 on the five seeds). It needs its own calibration.
- (b) Build the water rule shipped off: it is never raised while its effect is off, so the log never claims an agreement the sim does not keep. Probe it like the Task 4 pulls and decide at Task 5 close. Cost: one or two more probe passes, a reset if adopted, and the Task 3 fall-back sols (213 and 174) will move.
- (c) The water rule on in Task 5. Cost: two behaviour changes in one task (with the lonely pull), so they must run in sequence to keep one change per run, and both resets fall in Task 5.

## 0. The design in one paragraph
Once a sol, the colony asks how far its grown members know one another: of the voices (founders and Mars-born at least 40 sols old), what share stands in one web of friends. A colony that has been settled for a while and whose grown members mostly form one web becomes a **Council**: it begins to meet. Every voice holds a private **stance** on the colony's one big question, a dome. Stances come from personality (driven, curious and restless people lean toward building; steady and caring people lean toward waiting) and from the colony's days (hardship pushes everyone toward "not now"; a larger colony and enough stone push toward "yes"). Friends then pull each other's stances together once a sol, so camps form along friendships, which is diplomacy without dialogue. The council **meets** where the most voices gather in one room. At a meeting a named person who wants the dome raises it. At later meetings the colony is divided, sets the dome aside, or, when most voices want it at two meetings in a row, **pledges** to build it together. The player reads a few named lines and a chapter; never a number. In the shipped state nothing beings do changes, so every earlier hash reproduces.

## 1. Purpose
HANDOFF 7: Council is "gatherings, arguments, factions by personality", and the colony moves on when "a dome proposal wins enough support and the colony commits to build it together". Task 5 turns the Task 4 friendship web into a forum: the age that follows Settlement, a way for the colony's people to want something together, disagree about it in camps their personalities explain, and decide. As with ages and relationships, nothing counts toward anything on screen. The decision happens when the people get there.

## 2. Terms
| Term | Meaning |
| --- | --- |
| voice | a living being that is `earth_born`, or whose age `t - born_t` is at least `voice.min_age_sols` x `sol_h` |
| voice web | the graph of voices joined by `friends` pairs whose two ends are both voices (kin and crew pairs count; they hold the flag) |
| trust | the share of voices in the largest connected part of the voice web; 0.0 when there are no voices |
| Council term | the stretch from a Council entry to the next age change |
| Settlement term | the stretch from the latest `age_history` entry with age `settlement` to the next age change |
| gathering | at a relationship tick, the voices awake inside one building (read from `relationships.present`) |
| best gathering | the largest gathering since the last meeting: `{building_id, count, ids, t}` |
| meeting (session) | held at a sol boundary in Council when the interval has passed and the best gathering is big enough; its place is the best gathering's building |
| lean | a voice's own position on the dome from personality and colony conditions, in [-1, 1] |
| stance | lean after friends' sway, in [-1, 1]; private |
| yes, no | a voice with stance above `support.yes_above`, or below `support.no_below` |
| proposal | the dome matter, open from the meeting where it is raised until it is pledged, set aside or lapses |
| pledge | the carried decision to build a dome together; permanent in Task 5 |
| hard sol | a sol boundary at which the ice, oxygen or food clause of ages.md 4.2 (1a, 1b, 5) fails, recomputed by this module |

## 3. State (all new, inside `Council`, owned by `SimWorld` as `world.council`)
| Field | Meaning |
| --- | --- |
| `trust_win` | the last `trust.window_sols` trust readings, newest last |
| `stance` | map from voice id to stance; entries for beings that are no longer voices or are dead are dropped at each sol |
| `hard_win` | the last `cond.hard_window_sols` hard-sol booleans, newest last |
| `best` | the best gathering since the last meeting, or empty |
| `seen_ticks` | `relationships.ticks` at the last gathering read |
| `last_session_sol` | elapsed sol of the last meeting, or of the Council entry |
| `open` | null, or `{raised_sol, votes, carry_run, reject_run, divided}` |
| `last_set_aside_sol` | elapsed sol of the last set-aside, or null |
| `raised_ever` | true after the first raise in the run (chooses the "again" text) |
| `pledged` | false until the pledge |
| `circles_logged` | true once the "circles" line has been logged in the current Settlement term |
`Being` gains no field. `stats` gains `stats.council` (section 8) and one key in `stats.sols_in_age` (`council`). `Ages` gains one method, `enter_age(world, age_id, how, text)`, which sets `age`, increments `stats.age_changes`, appends the `age_history` entry through the existing `_record` and logs `age_began`. It does **not** touch `last_change_sol`, `window` or the snapshots (section 5.5). `SimWorld` gains `council`, `council_enabled` (default true; false skips both hooks; a test seam), the hook calls and the creation call. `Council` exposes read-only queries for tests and the probe (`stance_of(id)`, `lean_of(id)`, `is_voice(world, id)`).

## 4. Where it runs
- **Creation**: in `SimWorld._init`, after `relationships.begin(...)` on both branches: `council.begin(self, founders_world)`. A founder world appends **one initial trust reading** (7 founder voices, all crew friends: 1.0), because the founder branch also appends the initial `pop_by_sol` entry. A blank world appends nothing. So `trust_by_sol` has the same length as `pop_by_sol` from creation on (the same rule as relationships.md section 4).
- **Gathering read (phase 11b, after the relationship tick)**: in `step()`, right after `relationships.on_step(...)`: `council.on_step(self)`. It acts only when `relationships.ticks` differs from `seen_ticks` (a tick just ran, so `present` is fresh) and the age is `council`. Then it updates `best` (section 5.7). Otherwise it returns at once.
- **Sol reading and decisions**: inside the `if _sol_started:` block, after `relationships.on_sol(self)`: `council.on_sol(self)`. Ages has already sampled and decided, and relationships has refreshed the web, so the Council reads the age in force and the current friendships.
- The Council is skipped entirely (both hooks) when `world.relationships` is null or `relationships_enabled` is false: it has no web to read. It then appends 0.0 trust readings so the list lengths still match.
- No RNG draw, no wall clock (except a probe-only timing field), no read of the log, no write to colony, buildings, beings, resources, powers, relationships or the RNG.

## 5. Rules
### 5.1 Voices
A being is a voice if it is `earth_born` or `t - born_t >= voice.min_age_sols x sol_h - STEP_EPS` (40 sols, E). Why 40: the measured median wait from birth to a first grown friendship is 25 to 29 sols (relationships.md R1), so by 40 sols most Mars-born have had the chance to join the web. A newborn has no say in the dome and does not count against trust. Voices are recomputed at every sol boundary; nothing is stored on the being.

### 5.2 The trust reading (once a sol, every age)
1. Build the voice web: walk the `friends` pairs of `relationships.pairs` in ascending pair key, keep those whose two ends are both living voices, and union them over ascending ids (the same union-find rule as relationships.md section 7: a root is the smallest id).
2. `trust = size of the part with the most voices / voices` (0.0 when there are no voices). Also count `voices`.
3. Append `trust` to `stats.council.trust_by_sol` and to `trust_win` (drop the oldest past `trust.window_sols`, 20). Store the latest `trust` and `voices`.
Why a new reading and not `web_by_sol`: the measured `web_share` is 1.0 at landing and falls to 0.81, 0.91, 0.66, 0.89, 0.92 by sol 60 and 0.35 to 0.97 by sol 300 (seeds 42, 7, 99, 1234, 2026). It falls because the founders' crew thins out and because every friendless newborn counts in the denominator, not because trust is lost. The voice web leaves out the newest colonists and measures whether the grown colony is one community. Like `web_share`, it can stay high on a warm small colony (seed 7) and sag on a large, loosely knit one (seeds 42, 2026), which is what the gate should see.

### 5.3 Entering the Council (decided at the sol boundary, after 5.2)
`decide_entry` returns true when the age in force is `settlement` and ALL of:
1. **Settled long enough**: `n - S >= entry.settled_sols` (30, E), where `S` is the `sol` of the latest `age_history` entry (its age is `settlement`: a first entry, a re-entry, or a Council split). This reads `age_history`, never "the first Settlement entry" (ages.md section 2). After a fall-back and re-entry the count restarts.
2. **Trust**: `trust_win` is full and at least `entry.trust_ok_min` (16) of its 20 readings are at least `entry.trust_share_min` (0.5, E).
3. **Trust now**: the last `entry.recent_ok` (3) readings are all at least `entry.trust_share_min`.
4. **Enough voices**: `voices >= entry.voices_min` (12, E). A meeting of the seven founders and three children is a household, not a council.
On entry: `world.ages.enter_age(world, "council", how, text)`, with `how` = `council` the first time in the run and `council_again` after that. The text is assembled in section 7. `best` and `last_session_sol` are reset (the first meeting can come `session.interval_sols` after entry). Since clause 1 needs 30 sols after the latest change, and ages' own changes are at least 20 sols apart, an entry never falls on the same boundary as another age change.

### 5.4 The Council comes apart (split back to Settlement)
`decide_split` returns true when the age is `council` and ALL of:
1. `n - C >= min_dwell_sols` (20), where `C` is the `sol` of the Council entry (the latest `age_history` entry);
2. at least `exit.split_min` (16) of the 20 readings in `trust_win` are below `exit.trust_share_below` (0.3, E);
3. the last `exit.recent_below` (3) readings are all below it.
On split: `enter_age(world, "settlement", "council_split", text)`. An open proposal lapses (5.8). Dead band: trust between 0.3 and 0.5 changes nothing in either direction. As in ages.md 6.2, the window moves by one reading a sol, so an entry is never undone in under 13 sols. The 20-sol dwell is what binds.

### 5.5 How the Council sits with the Task 3 ages (no Task 3 timing changes)
- Ages keeps sole authority over Landing and the life-support rule. `Ages.decide` already sends every age other than Landing through the exit branch, so in Council the same hard-days rule applies unchanged. A long ice crisis takes the colony from Council straight to Landing with the existing fall-back line and cause sentence. No ages code changes for this.
- `enter_age` does not move `ages.last_change_sol`. Ages' dwell therefore counts from its own last Landing/Settlement change, exactly as in Task 3. **Projected onto "Landing" versus "not Landing", the age sequence is identical to Task 3 on every seed** (Council entries and splits only relabel stretches that Task 3 calls Settlement). The proof is the projected `age` column (section 9).
- Consequence, stated honestly: a life-support fall-back can come less than 20 sols after a Council entry (ages' dwell ignores Council changes). The 20-sol gap guarantee of ages.md 6.2 therefore holds for ages' own changes, and for Council changes measured against the previous entry, but not for every pair of consecutive `age_history` entries. T10 is judged on the projected history (section 12), so its meaning and its expected values stay Task 3's.
- `ages.on_sol` credits `stats.sols_in_age[age]`, so the dictionary gains a `council` key at creation (value 0).
- The Council never reads `ages.window` or `last_sample` (private). Its hardship read (5.6) recomputes three clauses from the colony and the same `ages.sample.*` keys.
- Ages never reads the Council. The age is never an input to the ages sample (ages.md 7); the Council reads the age only for its own gate.

### 5.6 Lean and stance (once a sol, every age, for voices only)
Traits come from `persona.traits` (each in [0, 1]). For voice i:
- `ambition_i = (drive + curiosity + restless) / 3`; `caution_i = (steady + care) / 2`.
- Colony terms (the same for everyone, at this boundary):
  - `means = clamp(colony.regolith / colony.regolith_target(), 0, 1)`: "we have the stone".
  - `size = clamp((pop - cond.size_from) / cond.size_span, 0, 1)` (40 and 80, E): "we are outgrowing the modules".
  - `hard = (hard sols in hard_win) / cond.hard_window_sols` (10, E); the hard sol of this boundary is appended first. A hard sol fails clause 1a (`oxygen >= o2_min_fraction x o2_cap`), 1b (food likewise) or 5 (`ice >= ice_min_sols x pop x ice_per_being x sol_h - CMP_EPS`), with the keys and formulas of ages.md 4.2.
- `lean_i = clamp(lean.ambition x (ambition_i - 0.5) - lean.caution x (caution_i - 0.5) + lean.means x (means - 0.5) + lean.size x size - lean.hard x hard + lean.base, -1, 1)`.
- **Sway (synchronous)**: with `s` the stances of the previous boundary (a voice without one uses its lean), for each voice i with at least one voice friend: `stance_i = (1 - sway.share) x lean_i + sway.share x (sum of w_j x s_j) / (sum of w_j)` over voice friends j, `w_j = sway.close_weight` if the pair is `close`, else 1. A voice with no voice friend has `stance_i = lean_i`. All new stances are computed from the old ones, then written, so the order of beings does not matter. Friend lists are walked in ascending id (sorted pair keys give this), so float sums are reproducible.
- `yes` = stance > `support.yes_above` (0.1, E); `no` = stance < `support.no_below` (-0.1, E); between them a voice is undecided.
Why this shape: personality decides who leans which way at the same moment (R10's lesson from Task 4: personality must stay the selector). The colony's days move everyone together, so the same people can refuse in a hard season and agree in a good one. Sway makes camps follow friendships, which is "factions by personality" in this sim: friends are mostly like-tempered pairs (relationships.md 5.3, affinity), so a friend circle tends to share a lean, and sway turns that into a camp. One curious bridge between two circles pulls both toward the middle. Stances are not shown; the player sees who speaks for each camp (section 7).

### 5.7 Gatherings and meetings
- **Gathering read** (5.5's hook, Council age only, once per relationship tick): for each building in `present` in ascending id, count the living voices in its list; if the count is strictly greater than `best.count`, set `best = {building_id, count, ids (those voice ids, ascending), t}`. Strictly greater means the earliest tick wins a tie, and the lower building id within a tick. A dark (offline) room counts, as in Task 4.
- **Meeting** (at the sol boundary, Council age only, after 5.6): a meeting is held when `n - last_session_sol >= session.interval_sols` (5, E) and `best.count >= session.min_voices` (5, E). Then `stats.council.sessions += 1`, a `session_log` entry is appended (section 8), the proposal step runs (5.8), `last_session_sol = n` and `best` is cleared. If the interval has passed but no gathering was large enough, the meeting waits: `best` keeps growing until one is, so a colony whose people never share a room never meets.
- Meetings are silent in the log: about 40 a run would bury the lines that matter. The place appears in the proposal line.

### 5.8 The dome: raise, argue, decide
At a meeting, in this order:
1. **Raise.** If no proposal is open, the colony has not pledged, and (`last_set_aside_sol` is null or `n - last_set_aside_sol >= proposal.reraise_sols` (30, E)): among the voices in `best.ids` that are still living voices, the **proposer** is the one with the highest stance (ties: lowest id). If that stance is above `support.yes_above`, the dome is raised: log `council_proposal` (first raise in the run) or `council_proposal_again`, naming the proposer and the place. Open `{raised_sol: n, votes: 0, carry_run: 0, reject_run: 0, divided: false}`. If no one in the room wants it, nothing is raised and the next meeting tries again. The raising meeting is not a vote.
2. **Vote** (a proposal open from an earlier meeting): `votes += 1`. Count yes and no among all living voices (the whole colony decides, not only those in the room). `yes_share = yes / voices`, `no_share = no / voices`, compared by cross-multiplying counts as in ages.md 4.2 (`CMP_EPS`).
   - `carry_run = carry_run + 1` if `yes_share >= decide.carry_share` (0.6, E), else 0. `reject_run` likewise with `no_share >= decide.reject_share` (0.5, E).
   - **Divided**: if not yet `divided` and both shares are `>= decide.divided_share` (0.25, E), log `council_divided` naming a speaker for each camp and set `divided`. Speaker for yes: the yes voice with the most voice friends inside the yes camp (ties: higher stance, then lower id). For no: the same inside the no camp (ties: lower stance, then lower id).
   - Then the first of these that holds:
     - **Pledge**: `carry_run >= decide.carry_sessions` (2). Log `council_pledge`; `pledged = true`; `stats.council.pledge_sol = n`; append a chapter (section 8); close the proposal with outcome `pledged`.
     - **Set aside**: `reject_run >= decide.reject_sessions` (2). Log `council_set_aside_hard` if this sol is a hard sol, else `council_set_aside`; `last_set_aside_sol = n`; outcome `set_aside`.
     - **Left open too long**: `votes >= decide.max_open_votes` (12, E; about 60 sols). Log `council_set_aside`; `last_set_aside_sol = n`; outcome `set_aside`.
     - Otherwise the argument goes on.
3. **Lapse.** When the colony leaves Council (split or fall-back) with a proposal open, it lapses: outcome `lapsed`, no line (the age line says enough). `last_set_aside_sol` is unchanged, so it can be raised again at the first meeting of the next Council term ("again" text).
The earliest pledge is therefore at the third meeting of a term (raise, then two carrying votes): at least 10 sols after the raise and 15 sols after the Council entry at the shipped interval. A colony cannot rubber-stamp the dome at the meeting where it was raised.

### 5.9 The pledge (owner O2 (a))
Permanent in Task 5: it survives a fall-back to Landing and a split. After it no proposal is raised; the Council still reads trust, sways stances and holds silent meetings (a later task gives it new matters). Nothing in the sim is built or changed. `stats.council.pledge_sol` and the chapter carry it forward for the task that builds the dome.

### 5.10 Edge cases
- Pop 0 or no voices: trust 0.0 is appended; no entry, split, meeting or line; stances are empty. The age is frozen by ages (ages.md 8.3).
- Voices below `entry.voices_min` while in Council: no special rule. Trust still decides a split, and votes are shares of whoever is a voice.
- The proposer or a speaker dies later: lines already logged stay; the proposal stays open.
- A voice in `best.ids` dies before the meeting: skipped when choosing the proposer.
- Council entry and an ages change on the same boundary: impossible (5.3, clause 1). An ages fall-back from Council and a split on the same boundary: ages runs first, so the Council sees Landing and does nothing.
- Settlement re-entered after a split: clause 1 restarts the 30 sols from the split entry.
- Relationships disabled: Council inert, trust 0.0 appended (section 4).
- Log eviction (500, kind-blind) changes no Council value; the chapter survives in `stats.council.chapters`.
- A building kind with no place phrase uses `text.place.other`; the key-path test fails until one is added.

## 6. Numbers, and what they imply (all E)
- **Entry timing**: Settlement came at sols 67, 58, 54, 65, 53 (Task 3/4). With 30 sols held, the earliest Council entry is about sols 83 to 97. Overall web at sol 100: 0.77, 0.88, 0.62, 0.63, 0.45. Voice trust should sit somewhat higher, because friendless newborns are excluded, so seeds 42, 7, 99 and 1234 are expected to enter near the earliest sol, and seed 2026 later or not at all. The probe measures this; nothing here is fitted.
- **Lean magnitudes**: personal terms (trait minus 0.5) are about plus or minus 0.2 for typical charts, so plus or minus 0.2 per term at weight 1.0. `means` from the 30-sol tables: regolith over target ranges about 0.01 (seed 42 at sol 180) to above 1 (seed 1234 at sols 180 to 300), a term of -0.15 to +0.15 at weight 0.3. `size` at pop 82 is 0.53 (+0.16) and 1.0 from pop 120 (+0.3). Hardship at 10 of 10 hard sols is -0.8. So in a good season of a large colony most voices lean yes (pledge expected). In the middle years the colony splits by temperament (divided line expected). In an ice crisis (seeds 42 and 99 after sol 150) nearly everyone leans no (set-aside expected, the "harder things first" variant).
- **Meetings**: one every 5 sols at most, about 30 to 40 in a run on a seed that enters Council near sol 90. Whether 5 voices are ever awake together in one room at a tick is not measured: relationships.md 6.1 measured 0.8 to 2.7 hours together a sol per pair, not room sizes. The probe reports the daily largest gathering (section 12, item 6).
- **Lines**: at most 3 per proposal term (raise, divided, outcome), terms at least 30 sols apart after a set-aside, plus age lines and at most one "circles" line per Settlement term. Expected well under one line per 5 sols. Relationship lines are 9.6 to 13.0 percent of the log today; Council lines add about 1 percent (E).

## 7. What the player sees (view; sim read-only; fixed texts, no numbers)
**Age lines** (kind `age_began`, written through `Ages.enter_age`, so they land in `age_history` and the chapters strip). The text is the base sentence plus the season sentence of `ages.season_phrases` at the change time (the same rule as ages.md 8.1):
| `how` | Key | Text (first sentence is what the strip shows) |
| --- | --- | --- |
| `council` | `text.enter` | "Jezero has begun to meet as one. Evenings end with everyone in one room, talking at once, and now and then agreeing." |
| `council_again` | `text.enter_again` | "The colony meets as one again. Old arguments are taken up where they were left." |
| `council_split` | `text.split` | "The meetings have gone quiet. Friends keep to their own circles, and no one speaks for the whole colony." |
A fall-back from Council to Landing uses the existing ages fall-back line and cause sentence unchanged.

**Council lines** (new kinds; `{a}`, `{b}` are `Being.name`; `{place}` is the place phrase of the meeting room's kind):
| Kind | Key | Text |
| --- | --- | --- |
| `council_proposal` | `text.proposal` | "{a} spoke of a dome at the meeting {place}: a roof of sky, and streets without suits." |
| `council_proposal_again` | `text.proposal_again` | "{a} raised the dome again at the meeting {place}." |
| `council_divided` | `text.divided` | "The council is divided over the dome. {a} speaks for building it; {b} says not yet." |
| `council_set_aside` | `text.set_aside` | "The council has set the dome aside for now." |
| `council_set_aside_hard` | `text.set_aside_hard` | "The council has set the dome aside. There are harder things to think about first." |
| `council_pledge` | `text.pledge` | "The council has agreed. Jezero will build a dome, and build it together." |
| `council_circles` | `text.circles` | "People keep to their own circles. No one yet speaks for the whole colony." |
Place phrases (`text.place.*`): habitat "in the habitat", green_room "in the green room", workshop "in the workshop", reactor "by the reactor", archive "in the archive", comms "at comms", other "in the colony".
Entries carry `being_id` (`{a}`), `other_id` (`{b}` or null), `building_id` (the meeting room, or null) and `topic` ("dome"), so later click-to-focus needs no sim change.

**The circles line** (the structural line deferred from Task 4, C-7; it answers relationships.md section 11: "a hidden counter must not act as a silent gate"). It is logged at most once per Settlement term, at the first boundary where the Settlement term has lasted `entry.settled_sols + lines.circles_after_sols` (30 + 20 sols, E), voices are at least `entry.voices_min`, and the trust clauses (5.3 items 2 and 3) are the only entry clauses failing. It tells the player why the colony has not become a Council, in the colony's voice, without a number.

**HUD**:
- The clock line's age word is `council.age.name` ("Council") when `stats.age` is `council`. Landing and Settlement keep their names from `ages.json`, and no Council key is added to `ages.json`, so ages test 18 stands.
- **Chapters strip**: shows the latest `ages.hud.chapters_shown` (3) entries of `age_history` merged with `stats.council.chapters`, ordered by `t` (on a tie the age entry comes first), each as `sol N  <first sentence>`. The pledge's first sentence is "The council has agreed." No new screen line.
- No support share, trust, vote count, camp size, stance, "sols until", meeting count or bar anywhere. No new panel, button or pop-up. No speed change on any Council event (owner decision of ages.md 18 item 4).
- Out of Task 5: a being inspect panel, click-to-focus, and a meeting shown on screen (section 15).

## 8. Stats and log
`stats.council` (run-wide, never windowed, never reset, never shown; created in `_init_stats`):
| Key | Definition |
| --- | --- |
| `trust`, `voices` | latest reading |
| `trust_by_sol` | one float per pass through the sol block with the module enabled, plus the initial founder-world reading; same length as `pop_by_sol` |
| `first_council_sol` | elapsed sol of the first Council entry, null before |
| `sessions` | meetings held |
| `session_log` | `{sol, building_id, present (best.count), voices, yes, no, hard}` per meeting; uncapped (about 40 a run) |
| `proposals` | `{topic, raised_sol, proposer_id, again, outcome (null, pledged, set_aside, lapsed), outcome_sol}` per raise |
| `pledge_sol` | elapsed sol of the pledge, null before |
| `chapters` | `{kind: "pledge", text, t, sol, clock_sol}`; read by the strip |
| `lines` | `{proposal, proposal_again, divided, set_aside, set_aside_hard, pledge, circles}` counts |
Not in stats: stances, leans, `best`, the windows. `stats.sols_in_age` gains `council`. `age_history` gains entries with `age` `council` (`how` `council` or `council_again`) and `settlement` (`how` `council_split`); fields and shape unchanged; `len(age_history) == age_changes + 1` holds (each Council change increments `age_changes`).
Also built with Task 5's first sim change (relationships.md 10.2, RN-7): `stats.relationships.lines_dropped_by_type`.

## 9. Randomness and hashes, per mechanic
No mechanic draws from `SimRng` or any other random source. Every order is fixed (ascending ids, ascending pair keys, ascending building ids, meeting order).
| Mechanic | Draws | Writes outside the module | Effect on earlier hashes |
| --- | --- | --- | --- |
| Voices, trust reading (5.1, 5.2) | none | `stats.council` | none |
| Entry, split via `Ages.enter_age` (5.3, 5.4) | none | `stats.age`, `age_changes`, `age_history`, `sols_in_age`, log | none on behaviour (nothing in the sim reads them); the `age` column is projected (below) |
| Lean, hardship, sway (5.6) | none | none | none |
| Gathering read, meetings (5.7) | none | `stats.council` | none |
| Raise, vote, divided, outcomes, pledge (5.8, 5.9) | none | log, `stats.council` | none |
| Circles line (7) | none | log | none |
| `lines_dropped_by_type` (8) | none | `stats.relationships` | none |
| Lonely pull above 0.0 (section 10; owner O3) | same draws per travel decision, different choices | being behaviour | **changes every hash**; one recorded reset if adopted |
**Balance columns.** (1) The existing `age` column becomes a projection: `L` when the age is `landing`, `S` for any other age. Today `tests/balance_lib.gd` prints `S` only for `settlement` and would print `L` for `council`, so this one-line edit is required, and the code reviewer is asked to check it as justified. (2) A new trailing column `cn` after `web`: `-` before any Council entry or outside Council without a pledge, `C` in Council without a pledge, `P` after the pledge (any age). Removing the last field reproduces the Task 4 table hashes (`docs/balance/task-4-log.md`, summary: 42 a96b8a9562fd75d0, 7 a4968e2fcc48ec36, 99 2210719cf48d8612, 1234 19437e397d1dff88, 2026 6e7fe68477161196). From there, the existing `tests/relationships_hash_proof.gd` chain gives the Task 3 and Task 1 hashes.
**Automated proof**: `tests/council_hash_proof.gd` (not a unit test; modelled on `relationships_hash_proof.gd`, static helpers). Per seed it strips `cn` (and refuses if the last header field is not `cn`) and compares with the Task 4 hash, then strips `web` and `age` in turn and compares with the Task 3 and Task 1 hashes. It exits 0 only when all match. If the owner adopts the lonely pull (O3), the reference hashes become the reset baseline recorded in `docs/balance/task-5-lonely-run.md`, and the Task 1/3/4 chain is reported as superseded, with old and new side by side.
**Paired runs**: in the shipped state the Council changes nothing beings do, so a run that changes any `council.*` key plays out the same colony as the shipped run on that seed. Calibration of the Council is therefore a paired comparison, like relationships.md section 13.

## 10. The lonely-pull run (owner decision 2026-10-06: Task 5's first social run is the lonely pull alone)
Placement: plan step 3 (owner O3 (a)), after the code review of this spec and before the Council tests. One parameter: `relationships.effects.lonely_pull` 0.0 to 0.15 (`effects.friend_pull` stays 0.0; value from RN-6 and E4-1, chosen by the lead). Everything else is as shipped.
**Before the run (tests and columns first, hash-neutral, one commit):** `stats.relationships.lines_dropped_by_type` (10.2); probe additions F4-1 (the longest run of sols with no capped-kind relationship line before the first newcomer line), F4-3 (`balance.log_share_flag` 0.15, a flag only), R13's 2.5 warning read and R12's reopen trigger read on every run (F4-2, F4-4); and the **breadth-or-repetition report** (E4-1): for newborns after sol 100, the median hours a sol shared with their most-shared being, shipped against pull.
**Seeds:** the five standard seeds for T1 to T11 and every R target. R9 is also judged over **15 seeds** (E4-4; lead decision): the five plus 1, 2, 3, 5, 8, 13, 21, 34, 55, 89 (`relationships.balance.r9_seeds`). Both shipped and pull runs are made on all 15, about 30 runs of 300 sols (E: about 2 hours on this host). A forked design (both runs from one saved world) is not possible today: `SimWorld` has no save, load or clone.
**Adoption rule, stated before the run.** The lead recommends adoption to the owner only if ALL of these hold:
1. R9: the 15-seed mean zero-friend share of post-sol-100 newborns (probe item 8 (c)) under the pull is at most the shipped 15-seed mean minus `balance.r9_gain_min` (0.03, E). A smaller gain is inside the noise of diverged trajectories.
2. R4 (`friends_mean` 1 to 15), R10 (selectivity at least 2.0) and R11 (coldest third at most 10) hold on all 15 seeds.
3. T1 to T11 pass on the five standard seeds. Task 3 crossings will move; they are reported, old and new side by side, not judged against 67, 58, 54, 65, 53.
4. No unexplained death (`deaths_unexplained` 0) and no new death cause.
If any fails, the pull stays 0.0, K1 is carried as known, and the breadth report decides what is posed next: if the pull added breadth without repetition, the parent-room anchor (E4-3) is the named next lever for a later task, not Task 5.
**Read on every run:** K1 (zero-friend late newborns on 42 and 2026), K2 (first newcomer line, R12 trigger: any seed later than sol 80, or two or more later than 68), K3 (R1 margins on 99 and 2026; a 1-sol move after a behaviour change is noise). Report: `docs/balance/task-5-lonely-run.md`.
**Lonely definition (plan Q10):** `friend_count` 0, kin included, the K1 definition, unchanged (E4-6). One change per run: a "no grown friendship" definition would be a second change. Temperament-scaled pull (E4-2) and the parent-room anchor (E4-3) are not in Task 5.
**Interplay with the Council (why the placement matters):** a pull that brings friendless beings into company raises voice trust (5.2), and an earlier or surer Council follows. The Council's thresholds are calibrated after this decision, on the baseline that ships.

## 11. Cost budget (E; measured by the probe and the step profile)
- `on_sol` (once a sol, about every 493 steps): pair walk (stored pairs: median 2,876 and max 4,389 at pop above 120, relationships.md 13), voice union-find, sway over voice friends, counts. Estimate 1 to 3 ms at pop 160. **Budget: median at most `balance.on_sol_ms_max` (3.0 ms), max under `sim.advance_budget_ms` (8.0 ms).** Amortized, this is under 0.01 ms a step.
- `on_step`: acts only on tick steps (every 20th) in Council, O(awake beings inside). Estimate 20 to 50 microseconds. **Budget: the module's share of the mean step cost at pop above 120 at most `balance.step_share_max` (0.02).**
- Worst boundary step: ages (about 0.4 ms) plus relationships reading (about 2.3 ms) plus Council (up to 3 ms) plus a relationship tick if one coincides (about 6 ms) plus the step (about 2.5 ms), about 14 ms. That is under the 33 ms single-frame trigger of relationships.md 13, and `advance()` stops after it as it already does. If the probe measures a boundary step over 16.7 ms that is attributable to the Council, the remedy order is: share the union-find with relationships' reading (behaviour-identical), then skip trust and sway on sols where nothing reads them (Landing and pledged Council). Neither is built now.

## 12. Calibration probe and balance targets
**Probe** `tools/council_probe.gd` (read-only; runs the real module; seeds 42, 7, 99, 1234, 2026; 300 sols; on the baseline O3 leaves). Per seed it writes `docs/balance/task-5-calibration.md`:
1. Per sol: pop, voices, trust, age, hard, means, size, mean lean, mean stance, yes and no shares, the largest number of voices together at one tick that sol (computed by the probe in every age), meeting held or not.
2. Crossings: Council entries, splits and fall-backs with sols; for each entry, which clause passed last (settled sols, trust, voices). Reported: the projected ages sequence equals Task 3's (or the reset baseline's).
3. Trust discrimination: per seed, minimum and maximum trust over sols 60 to 300. **Flag FLOOR** if no seed's trust ever falls below `entry.trust_share_min` after its 30 settled sols: the trust clause would then never bind and the gate would be a timer in disguise (read by the lead before any change).
4. Proposals: raise sols, proposers, votes to outcome, outcomes, divided lines, the yes and no shares at each vote; at each outcome, the mean lean split into its terms (personal, means, size, hard). **Flag SIZE-DOMINANT** if, at every pledge across the seeds, the size term exceeds half of the mean lean: the pledge would then follow population, not people.
5. Factions: at each divided vote, the mean ambition and caution of the yes camp against the no camp, and the share of voices whose stance sign differs from their own lean sign (how much sway moved people).
6. Gatherings: the distribution of the daily largest voice gathering; sols in Council with the interval passed but no meeting.
7. Lines: Council lines per 5 Council sols; Council and relationship lines as a share of the log (`balance.log_share_flag`).
8. Cost: `on_sol` median, p95 and max microseconds at pop around 70 and above 120; the share of the mean step.
9. Replays from stored readings (the gate only; no live run needed): `entry.trust_share_min` {0.4, 0.5, 0.6}, `entry.settled_sols` {20, 30, 45}, `entry.trust_ok_min` {14, 16, 18}. Decision keys are tuned by paired live runs (section 9), one key per run, chosen by the lead.
**Targets (E; judged by the probe unless marked T12):**
| # | Target | Key |
| --- | --- | --- |
| C1 | Council entered by sol 300 on at least 3 of the 5 seeds | `balance.council_min_seeds` 3 |
| C2 | (T12) Every Council entry is at least 30 sols after the Settlement entry before it, and every Council change is at least `min_dwell_sols` after the previous `age_history` entry | structural |
| C3 | (T12) At most 4 Council changes (entries plus splits) per seed | `balance.max_council_changes` 4 |
| C4 | A pledge on at least 1 seed by sol 300; pledge sols reported | `balance.pledge_min_seeds` 1 |
| C5 | A divided or set-aside line on at least 2 seeds (the colony argues) | `balance.argue_min_seeds` 2 |
| C6 | At at least 80 percent of divided votes, pooled over the seeds: the yes camp's mean ambition is above the no camp's, and the no camp's mean caution is above the yes camp's (factions follow personality) | `balance.faction_trait_share_min` 0.8 |
| C7 | Council lines (age lines excluded) at most 1.0 per 5 Council sols on every seed | `balance.lines_per5_max` 1.0 |
| C8 | Cost as in section 11 | `balance.on_sol_ms_max` 3.0, `balance.step_share_max` 0.02 |
| D | FLOOR and SIZE-DOMINANT flags (item 3, 4): reported; they fail nothing and are read by the lead before the next key | none |
**T12** in `tests/balance_lib.gd`, per seed, from `stats` only: (1) `len(trust_by_sol) == len(pop_by_sol)`; (2) C2; (3) C3; (4) every `proposals` entry has an outcome or is the open one; the pledged proposal has `outcome_sol - raised_sol >= 2 x session.interval_sols`. Reported: first Council sol, meetings, proposals and outcomes, pledge sol, lines.
**T10 on the projected history**: T10 reads `age_history` through a helper that maps every non-Landing age to `settlement` and drops entries that do not change the projection. `age_changes` for T10 (2) is the projected count. Meaning and expected values are Task 3's (changes 2, 1, 2, 1, 1 on the shipped baseline). This is the one justified edit to a Task 3 check; T1 to T9 and T11 are unchanged.
Not a target: when the pledge comes. A colony that never agrees is a legitimate story. C4 only checks that the decision can happen.

## 13. Tests (`tests/test_council.gd`, written first, red; no test with zero checks)
Staging: a blank world with a reactor, two habitats, a workshop and a green room; beings added with `add_being` and traits overwritten; `born_t` and `earth_born` set; friendships made with `relationships.debug_set_bond`; `present` set by a relationship tick; boundaries driven by setting `world.t` and calling the hooks.
1. Voices: an Earth-born is a voice at once; a Mars-born at 39.9 sols is not, at 40 is; the dead are not.
2. Trust: staged voice webs (one part of 6 of 10 voices, so 0.6; two islands; a non-voice bridge does not join two voice parts; kin and crew pairs count); no voices gives 0.0; one entry per boundary; `len(trust_by_sol) == len(pop_by_sol)` on founder and blank worlds; the founder world's initial reading is 1.0.
3. Entry: Settlement held 29 sols blocks, 30 enters; 15 of 20 trust readings at 0.5 blocks, 16 enters; exactly 0.5 counts; a 0.49 in the last 3 blocks; 11 voices blocks, 12 enters; Landing never enters; after a split, re-entry needs 30 sols from the split entry. Entry appends one `age_history` entry `{age: council, how: council, cause: null, text, pop, family_mars_born, t, sol, clock_sol}`, increments `age_changes`, logs `age_began`, leaves `ages.last_change_sol` unchanged; the second entry in a run uses `council_again`.
4. Split: before the 20-sol dwell no split; 16 of 20 below 0.3 with the last 3 below splits (`how` `council_split`, age `settlement`); 15 of 20 does not; a reading of 0.3 is not below.
5. Ages interplay: on a staged world in Council, a life-support window that sends a Settlement colony to Landing at sol N sends the Council colony to Landing at the same sol N with the same `fell_back` text and cause; `Ages.decide` for Landing and Settlement inputs is unchanged; `sols_in_age.council` is credited.
6. Lean: each term checked alone against the formula with values from data (tolerance 1e-12); the clamp at plus and minus 1; the hard window counts hard sols over the last 10; the hard read uses the ages.md 4.2 formulas for 1a, 1b and 5.
7. Sway: an isolated voice has stance equal to lean; two voice friends move toward each other by the formula; a close friend weighs `close_weight`; a non-voice friend is ignored; reversing the order of `world.beings` gives identical stances.
8. Gatherings and meetings: no meeting before the interval; a best gathering of 4 does not meet, of 5 does; the earliest tick wins a tie and the lower building id within a tick; the meeting place is the best building; `best` is cleared after a meeting; meetings happen only in Council.
9. Raise: at the first meeting the highest-stance voice of the room is named (ties lowest id), with the place phrase; no raise when nobody in the room is above `yes_above`; never two open proposals; the "again" text after a set-aside once 30 sols have passed, not at 29.
10. Votes: yes and no exact at the boundaries by cross-multiplied counts (6 of 10 at 0.6 carries the run, 5 of 10 does not); a carrying vote then a non-carrying vote resets the run; two in a row pledge; two rejecting votes set aside, with the hard text on a hard sol; 12 open votes set aside; the divided line logs once per proposal, before the outcome on the same meeting, with the speaker rules.
11. Pledge: `pledge_sol`, one chapter, no further raise; it survives a fall-back and a re-entry; the strip helper merges chapters and `age_history` by `t`.
12. Lapse: a split or fall-back with a proposal open sets outcome `lapsed`, logs nothing, and allows the "again" raise in the next term.
13. Circles line: logged once at settled + 50 sols when trust is the only failing clause; not when voices are under 12; not twice in one Settlement term; again in a later term.
14. Texts: every text from data, rendered with sample names and every place phrase and season, has no digit and no `%`, and never contains "vote", "percent", "Landing" or "fail" (case-insensitive).
15. Purity: seed 42, 120 sols (long enough to reach Council on a staged override if needed): worlds with `council_enabled` true and false have equal beings (id, building, state, energy), equal stocks, equal relationship stats and equal next 1,000 `rng` draws; their `age_history` projected onto Landing and not Landing is equal; two same-seed worlds have identical `stats.council` and logs.
16. Key-path parity for `council.json` (section 14), both ways, and the sanity rules: `exit.trust_share_below < entry.trust_share_min`; `entry.trust_ok_min`, `entry.recent_ok`, `exit.split_min` and `exit.recent_below` are each at most `trust.window_sols`; `support.no_below < 0 < support.yes_above`; `decide.carry_share > 0.5`; `decide.divided_share < 0.5`; every building kind in `buildings.json` has a place phrase; no Council key in `ages.json` (ages test 18 kept).
17. Balance helpers: the projected `age` column prints `S` for `council`; `cn` prints `-`, `C`, `P`; `council_hash_proof` helpers strip `cn` on synthetic tables and refuse a table whose last field is not `cn`; the T10 projection helper maps a synthetic history (S, C, L, S, C, S) to (S, L, S) with 2 projected changes.
18. HUD: the age word is "Council" from `council.json`; the strip shows at most 3 merged chapters with the pledge's first sentence; the HUD source reads no stance, trust, share or `session_log`.
19. Relationships-off: with `relationships_enabled` false, Council appends 0.0 readings and never enters.
20. Existing suite with the module on: every Task 1 to 4 test passes; any test changed for log pollution or the `sols_in_age` key is listed in the task log with the reason.

## 14. Tunables (`data/council.json` unless stated; E = estimate for the probe)
| Key | Unit | Start | Source |
| --- | --- | --- | --- |
| council.age.name | text | Council | HANDOFF 7 |
| council.text.enter / enter_again / split | text | section 7 | lead |
| council.text.proposal / proposal_again / divided / set_aside / set_aside_hard / pledge / circles | text with {a}, {b}, {place} | section 7 | lead |
| council.text.place.habitat / green_room / workshop / reactor / archive / comms / other | phrase | section 7 | lead |
| council.voice.min_age_sols | sols | 40 | lead, E |
| council.trust.window_sols | readings | 20 | lead, E |
| council.entry.settled_sols | sols since the latest Settlement entry | 30 | lead, E |
| council.entry.trust_share_min | share of voices | 0.5 | lead, E |
| council.entry.trust_ok_min | readings of the window | 16 | lead, E |
| council.entry.recent_ok | readings | 3 | lead, E |
| council.entry.voices_min | voices | 12 | lead, E |
| council.exit.trust_share_below | share of voices | 0.3 | lead, E |
| council.exit.split_min | readings of the window | 16 | lead, E |
| council.exit.recent_below | readings | 3 | lead, E |
| council.min_dwell_sols | sols | 20 | lead (matches ages) |
| council.session.interval_sols | sols | 5 | lead, E |
| council.session.min_voices | voices together at one tick | 5 | lead, E |
| council.lean.ambition / caution | per unit of trait above 0.5 | 1.0 / 1.0 | lead, E |
| council.lean.means / size / hard / base | lean | 0.3 / 0.3 / 0.8 / 0.0 | lead, E |
| council.cond.size_from / size_span | beings | 40 / 80 | lead, E |
| council.cond.hard_window_sols | sols | 10 | lead, E |
| council.sway.share | weight of friends | 0.5 | lead, E |
| council.sway.close_weight | weight of a close friend | 2.0 | lead, E |
| council.support.yes_above / no_below | stance | 0.1 / -0.1 | lead, E |
| council.decide.carry_share / carry_sessions | share of voices / votes in a row | 0.6 / 2 | lead, E |
| council.decide.reject_share / reject_sessions | share of voices / votes in a row | 0.5 / 2 | lead, E |
| council.decide.divided_share | share of voices, each camp | 0.25 | lead, E |
| council.decide.max_open_votes | votes | 12 | lead, E |
| council.proposal.reraise_sols | sols after a set-aside | 30 | lead, E |
| council.lines.circles_after_sols | sols after `settled_sols` | 20 | lead, E |
| council.balance.council_min_seeds / pledge_min_seeds / argue_min_seeds | seeds of 5 | 3 / 1 / 2 | lead, E |
| council.balance.max_council_changes | changes per 300 sols | 4 | lead, E |
| council.balance.faction_trait_share_min | share of divided votes | 0.8 | lead, E |
| council.balance.lines_per5_max | lines per 5 Council sols | 1.0 | lead, E |
| council.balance.on_sol_ms_max | ms | 3.0 | lead, E |
| council.balance.step_share_max | share of mean step | 0.02 | lead, E |
| relationships.balance.log_share_flag | share of log entries | 0.15 | feel F4-3, E |
| relationships.balance.r9_seeds | list of seeds | 42, 7, 99, 1234, 2026, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89 | lead (E4-4) |
| relationships.balance.r9_gain_min | share | 0.03 | lead, E |
Reused, not duplicated: `ages.sample.o2_min_fraction`, `food_min_fraction`, `ice_min_sols`, `ages.season_phrases`, `ages.hud.chapters_shown`, `colony.consumption.ice_per_being`, `relationships.effects.lonely_pull`, `persona.traits`, `SimWorld.STEP_EPS`, `Ages.CMP_EPS`. Not data: the ids `council`, `council_again`, `council_split`, the line kinds, the order of steps in 5.8, the tie rules, "no voices reads 0.0", and the centre 0.5 of the trait terms. `balance.*` keys are read by the probe and `balance_lib.gd` only; `age.name` and `text.*` by the view or the log; the rest by `sim/council.gd`. `SimData.council()` is the accessor; `data_hash` in `balance_lib.gd` adds `council`.

### Key-path list (machine-readable; one leaf per line)
Same rules as ages.md 13. The `relationships.` lines are existence checks only.
```keys:
council.age.name
council.text.enter
council.text.enter_again
council.text.split
council.text.proposal
council.text.proposal_again
council.text.divided
council.text.set_aside
council.text.set_aside_hard
council.text.pledge
council.text.circles
council.text.place.habitat
council.text.place.green_room
council.text.place.workshop
council.text.place.reactor
council.text.place.archive
council.text.place.comms
council.text.place.other
council.voice.min_age_sols
council.trust.window_sols
council.entry.settled_sols
council.entry.trust_share_min
council.entry.trust_ok_min
council.entry.recent_ok
council.entry.voices_min
council.exit.trust_share_below
council.exit.split_min
council.exit.recent_below
council.min_dwell_sols
council.session.interval_sols
council.session.min_voices
council.lean.ambition
council.lean.caution
council.lean.means
council.lean.size
council.lean.hard
council.lean.base
council.cond.size_from
council.cond.size_span
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
council.lines.circles_after_sols
council.balance.council_min_seeds
council.balance.pledge_min_seeds
council.balance.argue_min_seeds
council.balance.max_council_changes
council.balance.faction_trait_share_min
council.balance.lines_per5_max
council.balance.on_sol_ms_max
council.balance.step_share_max
relationships.balance.log_share_flag
relationships.balance.r9_seeds
relationships.balance.r9_gain_min
```

## 15. Plan questions answered, Task 4 inputs, scope cuts
### Plan questions Q1 to Q10
| Q | Answer | Whose |
| --- | --- | --- |
| Q1 Council gate | Settlement held 30 sols since its latest `age_history` entry, voice trust at least 0.5 on 16 of 20 (last 3), at least 12 voices; split under 0.3; recurrence and fall-back in 5.3 to 5.5; never gates on the first Settlement entry. Reads `age_history` and its own trust reading; `web_by_sol`, `second_by_sol`, `lonely_by_sol` are not gate inputs (5.2 says why) | owner, O1 |
| Q2 Texture memory | no new art | owner, O4 |
| Q3 Hashes | Council hash-neutral; one possible reset, from the lonely pull, with owner approval | owner, O3 |
| Q4 Scope | In: Council age, voices, trust, gatherings and silent meetings, the dome proposal with raise, argument, divided camps, set-aside and pledge. Later: building the dome, the Dome age, "more domes", other matters (water rule, O5), dislike bonds | owner, O2 and O5 |
| Q5 Behaviour | none in the shipped state; "commits to build" records a pledge (5.9) | owner, O2 |
| Q6 What the player sees | section 7: three age lines, seven Council lines, the age word, the merged strip; no numbers; no being panel; no click-to-focus in Task 5 | lead |
| Q7 God lever | none new in Task 5. Facts: `sim/powers.gd` holds only the Good fortune multiplier; Inspire, Grace and Send a sign are not built. The god's reach on the Council is indirect today (keeping power up does not touch the ice or the web). Recorded for later: Send a sign as a sway on the undecided (curious lean toward, steady away), which fits HANDOFF 4's "beings sense a god" | lead |
| Q8 Randomness | no draws anywhere (section 9) | lead |
| Q9 Targets and cost | C1 to C8, T12, T10 projected, R9 over 15 seeds (sections 10, 11, 12) | lead |
| Q10 Lonely definition and run content | `friend_count` 0 as K1; the lonely pull alone; temperament-scaled pull and parent-room anchor not in Task 5 (section 10) | lead |
### Task 4 inputs (relationships.md section 19)
| Input | Decision |
| --- | --- |
| Lonely pull alone, breadth report (E4-1) | In, section 10 |
| Temperament-scaled pull (E4-2) | Out of Task 5 |
| Parent-room anchor (E4-3) | Out of Task 5; named next lever if the breadth report shows breadth without repetition |
| R9 over more seeds (E4-4) | In, 15 seeds; a fork is not possible (no save or clone) |
| God lever on gathering (E4-5) | Deferred (Q7); the gathering pull is O3 (c) |
| Lonely definition (E4-6) | `friend_count` 0 kept |
| K1 readability, "knows no one well yet", "at last" (C4-3, C4-4) | Deferred: no being panel exists, and Task 5 adds none |
| Probe additions (F4-1 to F4-4), `lines_dropped_by_type` (RN-7) | In, section 10 |
| Structural colony line (C-7) | In, as the circles line and the split line |
| Click-to-focus (C-4, I5) | Deferred; Council entries carry the ids |
| Dislike bonds (S4) | Deferred; camps come from stance, not from negative bonds |
### Scope cuts (lead; cut order if time runs out, first cut first)
1. The circles line (keep the split line). 2. Probe replays (item 9). 3. Faction trait report (C6 becomes reported). 4. The divided line (camps then show only through outcomes). Never cut: the trust gate, the projected `age` column and hash proof, the pledge, `age_history` entries. Out of Task 5 entirely: building a dome, the Dome age, new god powers, a gathering pull, the water rule, dislike, a being panel, click-to-focus, new art, AI-written speech.

## 16. Requests to the assistant designers (the main session runs them)
Read this spec and `docs/specs/relationships.md` sections 7, 11 and 19. Answer the questions asked, with must-fix, should-fix and idea items. Write to `docs/design/reviews/council-emergence.md`, `council-feel.md`, `council-clarity.md`.
- **designer-emergence**: (1) Is voice trust (5.2) the right gate for "relationships and trust form", or will it behave as a floor (FLOOR flag) or as a gate that loosely knit colonies never pass? (2) Does lean plus sway (5.6) produce camps by personality, or will the colony terms (size, means, hardship) move everyone together, so that the pledge follows population (SIZE-DOMINANT)? Name the worst loop you see. (3) Is the lonely-pull adoption rule (section 10) a fair test, and is dome-only (O5 (a)) enough possibility space for a first Council?
- **designer-feel**: (1) Voice and pacing of the ten texts of section 7: does a first sitting (about sols 80 to 150) get a Council story, and is a pledge with nothing built (O2 (a)) a satisfying climax for a task? (2) The meeting interval (5 sols), re-raise (30 sols) and earliest pledge (third meeting): too slow, too fast? (3) Check the scope cut order of section 15.
- **designer-clarity**: (1) With no numbers, can a player tell why the Council came, why it is waiting (circles line), and why the dome was set aside or carried? Is anything still a silent gate? (2) The merged chapters strip with the pledge chapter, and the age word "Council", at 720p. (3) Does naming one speaker per camp in the divided line make factions readable at 160 beings, or is something more needed that fits influence-only and no meters?

## 17. Design review record
Reviewers: emergence (Will Wright lens), feel (Eric Barone lens), clarity (Karoliina Korppoo lens). Decision key: A adopted, AM adopted modified, D deferred, R rejected.
### Emergence
| # | Item | Decision |
| --- | --- | --- |
### Feel
| # | Item | Decision |
| --- | --- | --- |
### Clarity
| # | Item | Decision |
| --- | --- | --- |
### Dissent and tensions resolved

## Changelog
- 2026-10-07: revision 1 (lead designer). Draft for the three assistant reviews and the code review. Owner questions O1 to O5. Shipped behaviour is hash-neutral; the only behaviour change in Task 5 is the lonely-pull run, adopted only by owner decision. `data/` not edited.
