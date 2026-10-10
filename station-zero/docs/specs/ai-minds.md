# Spec: AI minds (Task 6b): a rule-based voice first, a cloud model that may nudge what beings do, a ledger that keeps every run reproducible (revision 2)

Status: revision 2, after four reviews (designer-emergence, designer-feel, designer-clarity, code-reviewer; section 17). Docs only; no code. The code-reviewer verdict on revision 1 was NOT APPROVED; its must-fix items are all applied here and listed in the changelog. Items marked **PENDING OWNER** (section 18) are not decided by this spec. Numbers marked E are estimates until a calibration run measures them.

Source of truth: `station-zero-handoff/HANDOFF.md` sections 2 (locked decisions), 3 (chart, Deimos row), 5 (Social: "Lines are a fixed list for now; AI minds replace them"), 8, 10; `docs/tasks/task-6-plan.md` (6b line and section 4 constraint (a) to (d)); `docs/design/task-6-scoping.md`; `docs/specs/emotions.md` revision 4 (mood fields, bands, why, panel contract, view read whitelist, hash discipline) and its shipped-dormant state (mood gains 0.0, new water-rebaseline hashes are the reference, the `e1f2bdd` chain is retired). Facts read from code for this spec: `sim/rng.gd` (`chance` is `randf() < p`), `sim/being.gd` (`decide` branch order; `_restless_travel` makes one `chance()` draw and one `randf()` room pick, and is also called for children, being.gd:281), `sim/world.gd` (member list, `_init(seed, options)`; `moods.on_step` sits inside the `relationships_enabled` and `moods_enabled` guards, world.gd:330-333; the 6a clamp field is `world.mood_travel_floor`), `sim/persona.gd`, `sim/sky.gd`, `view/model/view_model.gd` (`_talk_flags`, `_pair_talks`: talk is a pose with no words), `data/mood.json` (key style), `tests/mood_hash_proof.gd` (strips only a final `md`, refuses MISPLACED), `tests/balance_lib.gd:119` (header column list).

## Owner answers (Herby, 2026-10-10), binding for this spec
- **Q5 host: cloud API.** (Local model is out for 6b.)
- **Q5 influence: AI output CAN change what beings do.** It is not display-only. This overrides plan section 4 constraint (c) ("default is display-only"); the plan line is superseded by this spec once the owner confirms the section 3 answer.
- **Q4 budget: a tight cap.** At the cap, or on any failure, fall back **silently** to the no-LLM rule-based path.
- **Failure: silent fallback.** No error text, no icon, no "offline" word reaches the player.
- Also binding from the brief: every number is a data key; the provider code stays outside `sim/`; no secrets and no network in `sim/`.
- Not answered (section 18): which provider and model, who pays, and how the key reaches a player who is not the owner. The owner's answers to the section 18 items, when they arrive, are recorded in a file `docs/specs/ai-minds-owner-answers.md` (to be created by the main session) and revision 3 cites it.

Locked decisions respected: **influence-only god** (the AI is the beings' own mind, not the player's hand; the player still acts only through powers; a hook for a future power to speak into a mind is reserved, section 6.5, and not built); **hidden birth chart** (the prompt carries the chart only as effects in words, never a sign name, section 6.2; a filter blocks leaks, section 5.7); **naturalism, ages not meters** (no AI meter, no spend bar, no "minds online" word); **per-being energy, power as a budget, ice pressure is not failure** (the AI can only bend idle wandering; it cannot touch sleep, building, mining, trips, births, stocks; section 5.5). **Owner direction 2026-10-09 (the colony is not meant to survive unattended)** is respected: the AI must not become a hidden rescuer or a hidden killer; a guard run proves it (section 13).

---

## THE DETERMINISM PROBLEM (flagged for the owner; recommendation first)

**The conflict.** The project proves itself with seeded headless runs: a seed gives a table hash, five seeds twice must match byte for byte, and `*_hash_proof` tests chain back to earlier tasks. A cloud model is not repeatable: it answers differently each time, it takes a wall-clock-dependent time to answer, and it fails at random moments. If its answer feeds the sim, then the same seed gives different colonies, the hash proofs cannot be run live, and a balance number can no longer be separated from the model's mood that day.

**Options**
1. **Display-only.** The AI writes words; nothing in the sim reads them. Hashes untouched. Rejected by the owner (Q5: output can change behaviour).
2. **Live, unconstrained.** The sim reads whatever the model says whenever it arrives. Rejected: unreproducible, unsafe (a model could say "leave the colony"), and untestable.
3. **Whitelist only.** The model picks from a small menu the sim builds and re-validates. Bounded and safe, but on its own still unreproducible: which option is picked, and whether the answer arrives before the moment it is needed, vary run to run.
4. **Whitelist plus an applied-decision ledger and replay (recommended).** Option 3, plus: every model decision that the sim actually applies is written to an append-only ledger keyed by (being, slot); the sim consumes decisions from an inbox at a fixed **sim-time deadline**, never when they happen to arrive; a late or missing answer means the deterministic rule mind runs instead; and a run can be replayed from `seed + ledger` with no network and reproduces the same table hash. The model's randomness becomes **a recorded input, like the seed**, not hidden state.
5. **Barrier.** Pause the sim at each deadline until the model answers or times out. Reproducible in the same way as option 4 but freezes the game for seconds at a time. Rejected for feel (Barone) and legibility (Korppoo: a sim that stalls for no visible reason). Kept as a named alternative (Q-F).

**Recommendation: option 4.** What it guarantees (each is a test in section 14):
- **Mode `off`**: the AI module is not even built; every table hash equals the current pinned reference byte for byte once the new `mn` column is stripped (test 1, test 31). Mood stays as shipped (dormant gains).
- **Mode `rules`** (the recommended default, Q-A; the no-LLM path): the rule mind makes **no behaviour change at all** (but see the dormant policy flag, PENDING OWNER item (a), section 18). Its only product is words (display). So `rules` hashes equal `off` hashes byte for byte, and the fallback is exactly "the colony as it already plays" (tests 2, 3). Reason: the existing sim already is a rule-based mind (traits, needs, and 6a mood when its gains go on); the AI is a **nudge laid over it**, and falling back means removing the nudge.
- **Mode `llm`**: the run is identified by **(seed, ledger)**. Live play writes the ledger. `tests/` and balance runs replay a ledger with no network and get the same hash twice (tests 11 to 13). Two live runs of one seed differ, as two human players' runs do, and that is honest: the ledger says exactly how.
- **No new RNG draw, anywhere** (section 11). The model never reaches `SimRng`. A bias changes the argument of one `chance()` and the weights of one room pick; the code path then consumes **the same draws as the baseline does for the same outcome** (one draw when the chance fails, the same pair when it succeeds). Downstream draw counts differ in `llm` mode only because an outcome flipped, the same mechanism as the 6a mood gain.
- The model's text is excluded from the hash (test 14), and a worst-case adversarial provider is a test (16) and a calibration guard (13), so safety does not depend on the model behaving.

What this costs, said plainly: (a) **live minds only matter at slow speeds.** A cloud call takes seconds; at 1000x a sol passes in 25 ms. The deadline is in sim time, so answers that cannot arrive in time are never sent or never applied, and at high speed the colony runs on its rule minds (silently). The shipped numbers (`sim.think_h` 6, `driver.speed_gate_x` 5, E) make the model live at about 1x to 5x. (b) A live game is not reproducible from the seed alone; only from seed plus ledger. (c) A behaviour nudge slightly changes outcomes like any behaviour change, so live-AI play is **not** the balance baseline; balance runs use `off`/`rules` and mock providers. The owner's accepted "baseline reset" of 6a is not repeated here: `rules` and `off` do not move any hash (unless the owner chooses the policy option in item (a)).

**Where it is genuinely the owner's call** (section 18): the default mode (Q-A), the rule-mind policy flag (a), and Q-B to Q-G.

---

## 0. The design in one paragraph
Once per sol (at a time staggered by being), and again shortly after a moment that matters (a death, a new friend, a lapse, a god power landing), every non-baby colonist gets a **thought slot**. At the slot the sim builds a small **facts record** about the being (the chart as effect words, the 6a mood band and why, the place, the time of day and season, who is near, a coarse need hint, a coarse code for the last god influence) and a **menu** of at most six things the being could do with its idle time. The rule mind answers at once and locally: it picks "carry on" (no behaviour change) and composes one short **remark** from hand-written templates, so every colony has voices with no network. In mode `llm`, for the moments that matter only, the same facts go out to a cloud model in a batch; the model returns, per being, a menu choice and a short mood-colored remark. About six sim hours later (two after an event slot) the sim looks in its inbox: if a valid answer is there, the **sim** applies a bounded, expiring nudge to idle wandering and renders the intent phrase from the chosen menu item ("I'll go and find Dax"); the model's remark is only a coloring in front of it, so words and action cannot disagree. If no valid answer is there, the rule answer stands. Every applied model decision is appended to a ledger so the run can be replayed offline. The player sees the lines as speech where people talk, as one quoted line and one short intent clause on the being panel; they are never told whether a model or a template wrote anything.

## 1. Purpose
Replace the prototype's fixed conversation list (HANDOFF section 5) with voices that follow each being's nature and moment, and let a being's own "reasoning" change what it does with idle time, while keeping the colony reproducible, bounded, cheap, and playable offline. Design question: how much power does a model get? Answer: a menu choice among idle-time behaviours, expiring, capped per sol, never touching survival. Wright's lens: more authored stories from the same agents; Barone's: a handful of well-made lines is better than endless generic chatter; Korppoo's: the player must be able to reason about the system without a dashboard.

**Finding that changes the work (read from code).** The Godot port has **no conversation lines**: `view_model._talk_flags` and `_pair_talks` only switch a talk pose; no words exist anywhere in `sim/` or `view/` (the "fixed list" lives only in the HTML prototype). So "replaces the fixed lines" means 6b **builds** the first lines in the port (the rule voice) and the model path colors them. The speech-bubble draw is new view work (text only, no art).

## 2. Terms
| Term | Meaning |
| --- | --- |
| slot | one thought opportunity for one being: key `(id, k)` where `k` is the being's running slot counter (`mind_slot_n`; used only as a key, never in the schedule). Two kinds: **calm** (`slot.per_sol` per being per sol, scheduled by the clock) and **event** (opened after a moment that matters, 5.2) |
| facts | the deterministic structured record the sim builds at a slot (codes, no prose, no sign names) |
| menu | the ordered list of option keys the sim offers at a slot, built and re-validated by the sim |
| option key | `carry_on`, `stay`, `roam`, `visit:<id>`, `visit_new:<id>`, `quiet` |
| rule mind | the local deterministic mind: picks `carry_on` and composes a remark from templates. It is the whole no-LLM path |
| model mind | the cloud call that returns a choice and a remark per being |
| remark | a short mood-colored line (rule template or model text). It never states an intention |
| intent phrase | the sim-rendered phrase for a chosen menu item (`visit:<id>` renders "I'll go and find {other}"). Only the sim writes it |
| deadline | the sim step at which a slot is resolved: slot open step plus `sim.think_h` (calm) or `sim.think_event_h` (event) hours |
| inbox | decisions delivered by the driver, keyed by slot, waiting for their deadline |
| ledger | append-only record of every model decision that was applied (section 5.4) |
| bias | the bounded, expiring nudge a choice leaves on a being (`mind_bias`) |
| say | the being's current displayed line (remark and/or intent phrase), with its source (`rule` or `model`) |
| driver | the code outside `sim/` that owns the provider, key, budget, network and timing |
| mode | `off`, `rules`, `llm`; `replay` is `llm` with the inbox preloaded from a ledger file and the driver silent |

## 3. Architecture and the sim boundary
```
sim/minds.gd         (new)  slots, facts, menu, validation, inbox/ledger, bias, rule voice hook. Pure: no network, no wall clock, no key, no file I/O.
sim/minds_voice.gd   (new)  rule voice: facts -> remark from data templates; intent phrase from a menu item. Pure functions.
minds/               (new, OUTSIDE sim/)  driver.gd (pump, speed/deadline skip), prompt.gd, provider.gd (interface), provider_<name>.gd (first adapter, owner's pick), budget.gd (meter), breaker.gd, filter.gd (text filter shared with tests).
tests/mock_provider.gd (new) scripted answers, latency, failures; the only "provider" tests use.
data/minds.json (new) all tunables. data/minds_text.json (new) rule templates, intent phrases and prompt words.
```
Rules of the boundary: `sim/` never mentions HTTP, sockets, environment variables, keys, user files, providers or model names (a source scan is test 19). The driver reads the world's `minds.outbox` and writes into it only through `Minds.deliver(...)`, called on the main thread between `advance()` calls, never inside a step. The prompt builder and the text filter live in `minds/` and read `facts` records; they are pure and unit-tested with no network. The sim accepts the filter's verdict only as data in a delivered entry (`filtered: true` drops the remark), so the sim does not depend on the filter code. A new top-level folder `minds/` is an addition to the HANDOFF section 9 layout; it is recorded there at close.

## 4. State (all new)
`SimWorld` gains `minds` (a `Minds` or null), `minds_mode` (`off`, `rules`, `llm`; set from `options.minds_mode` in `_init` like `moods_enabled`, default from `data/minds.json` `mode.default`, see Q-A), and a cached `mind_enabled` bool read by `Being`. `Being` gains `mind_bias` (Variant: null or `{kind, target, until_t}`) and `mind_slot_n` (int, the running slot counter). Nothing else on `Being`.

`Minds` holds:
- `cfg`, `seen_ticks` (last relationships tick consumed).
- `pending_open`: the **carry-over list**, an array of `{id, sol, j, kind}` for slots whose cell matched but which `sim.max_slots_per_tick` held back; kept in (event before calm, then ascending slot-open order) and re-offered every tick until opened. A calm entry older than the end of its own sol (`sol < clock.sol`) is dropped, counter `slot_dropped_carry`; an event entry older than `sim.event_pending_max_h` (6.0 h) likewise.
- `due`: array of `{id, k, kind, open_step, deadline_step, menu, facts_hash}` sorted by deadline then id.
- `outbox`: request records for the driver `{id, k, deadline_step, facts, menu, priority}`; filled only in mode `llm`; capped at `sim.outbox_max`, oldest dropped.
- `inbox`: Dictionary keyed `"id:k"` to a delivered entry.
- `ledger` (Array of applied model decisions).
- `says`: Dictionary id to `{text, t, source, t_model, variant}` where `t` is the sim time the line was set, `source` is `rule` or `model`, `t_model` is the sim time of the last model-sourced line (-1 if never), `variant` the last rule template index used per situation (for the last-said guard).
- `last_visit_t`: Dictionary id to `{other_id: sim time}` for the longest-unseen choice (5.3). `last_event_t`: id to sim time of the last event slot (cooldown). `seen_why_t`: id to the last `mood_why` set-time consumed.
- `applied_sol` and `applied_this_sol` (cap counters), counters of section 10.

**Dead-being cleanup.** On every tick, for each id that is no longer alive: its `says`, `last_visit_t`, `last_event_t`, `seen_why_t` records, its `pending_open` entries and its `outbox` entries are deleted; its `due` entries stay until their deadline and resolve as rejected `dead` (so the counter is exact and a late-delivered `inbox` entry is simply dropped with it); any other being's `last_visit_t[other]` entry for the dead id is deleted at the same time. A `visit` target that dies is caught by the stale-target check at the deadline.

Mode `off`: `minds` is null and no hook runs (the world is the 6a-dormant world). Mode `rules`: `minds` runs, `outbox` stays empty, `inbox` is never read for choices.

## 5. Rules
### 5.1 Where it runs
One hook in `SimWorld.step()`: **a sibling of the 6a block, not inside it.** `moods.on_step` is guarded by `relationships_enabled` and `moods_enabled` (world.gd:330-333). The minds hook is `if minds != null and relationships_enabled: minds.on_step(self)`, placed directly after that whole guarded block and before `council.on_step(self)`. It must not depend on `moods_enabled`: with moods disabled the facts carry mood band 2 (even) and no `why`, and the minds still run. It acts only on steps where `relationships.ticks` differs from `seen_ticks` (the cadence rule moods and the Council use; one relationships tick is `relationships.tick_h` 1.0 sim hour). No sol hook is needed. If relationships is disabled the module does nothing.

### 5.2 The tick, in order
1. **Expire** biases whose `until_t <= world.t` (set `mind_bias` null).
2. **Resolve due slots** whose `deadline_step <= step_index`, in (deadline, id) order. Because the module acts only on relationships ticks, a slot is resolved at the **first relationships tick at or after its deadline step**. For each: decide the source (5.4), apply or not, write `says[id]`, append to the ledger if a model decision was applied. At most `sim.apply_max_per_sol` behaviour-changing model decisions apply per sol colony-wide; the rest fall to the rule answer and count `apply_dropped_cap`.
3. **Detect moments** (event triggers). For each living non-baby being, an **event** is any of: a `mood_why` of kind `grief`, `friend_new`, `close_new`, `lapse` or `birth` whose set-time is newer than `seen_why_t[id]` (the 6a why fields; the exact reads are named by ai-minds-engineer from emotions.md); a god power landing on the being or its room, read as a change of the coarse `god.last` code of 6.1 (ai-minds-engineer names the source). Events are queued into `pending_open` as `kind: event` unless `last_event_t[id]` is within `sim.event_cooldown_h` (6.0 h). A death is an event for each living friend of the dead (it arrives as `grief`).
4. **Open slots.** Event entries first, then calm. **Calm cell, per slot index `j` in `0 .. slot.per_sol - 1`:** `cell(id, sol, j) = (id * slot.cell_mult + sol * slot.cell_step + j * (cells_per_sol / slot.per_sol)) mod cells_per_sol`, with `sol = clock.sol` (the integer game sol, **not** `sol_number`, and **not** the running slot counter `k`), `cells_per_sol = floor(sol_h / slot.grid_h)` (24 at the shipped 1.0 h grid) and integer division. A being opens its calm slot `j` on the one relationships tick of sol `sol` whose hour cell equals `cell`; so it opens exactly `slot.per_sol` calm slots per sol and the schedule does not depend on how many slots it opened before (this fixes the revision 1 contradiction, where a per-slot increment gave about 4.8 slots a sol). `slot.cell_step` 5 is coprime with 24, so a being's slot hour walks through every cell over successive sols; `slot.cell_mult` 7919 spreads beings. No draw. At most `sim.max_slots_per_tick` slots open per tick; the remainder stay in `pending_open` (carry-over, state above). Opening a slot: `mind_slot_n += 1`; build facts (6.1); build the menu (5.3); compute the rule remark immediately and store it in `says[id]` as source `rule` (unless a model line set within `say.show_sols_model` is still fresh, in which case the fresh model line is kept until it goes stale); if mode is `llm` and the being passes the **worth gate** (5.6), append a request to `outbox` with its `priority` (5.6); push a `due` entry with `deadline_step = step_index + round(think / world.fixed_step)` where `think` is `sim.think_h` (calm) or `sim.think_event_h` (event). An event slot also sets `last_event_t[id]`, `seen_why_t[id]`. If an event slot opens for a being, that being's calm slot for the same tick is skipped (no double slot).
5. Update counters.

**Tie rule (said once, used everywhere).** A delivery is stored only if `deadline_step > step_index` at the moment of delivery; a delivery at or after the deadline step is dropped. Resolution happens at the first relationships tick at or after the deadline step and reads whatever is in the inbox, which by construction only holds deliveries made strictly before the deadline step.

### 5.3 The menu (what the model may choose)
Built by the sim at slot open, re-checked at the deadline. Option keys:
| Key | Meaning | Listed when | Bias effect (5.5) |
| --- | --- | --- | --- |
| `carry_on` | no nudge. Always present, always index 0 | always | none |
| `visit:<id>` | go to a named friend. **Prominent: listed immediately after `carry_on`.** At most `menu.visit_max` (2) entries: first the **longest-unseen friend** (smallest `last_visit_t[self][friend]`, never-visited counts as oldest; ties by the pure key `(id * slot.cell_mult + sol * slot.cell_step) mod 997`, then id), then the highest-bond other friend | the target holds the `friends` flag with this being (from `top_friend_of` and `friends_of`), is alive, and is in a **neighbouring** finished building now | weight of the room holding the target multiplied by `bias.visit_weight_mult` |
| `visit_new:<id>` | go and meet someone the being has met but is not yet friends with. At most one | a living met non-friend (relationships holds a pair record with contact but no `friends` flag) is in a neighbouring finished building; highest contact first, ties by the pure key above. If relationships keeps no "met" notion, ai-minds-engineer flags it and the key is omitted (it is in the first cut group, section 19) | same as `visit` |
| `stay` | keep to the room for a while | being is inside a building | travel chance times `bias.stay_travel_mult` |
| `quiet` | go somewhere with few people | at least two neighbours; the neighbour with the fewest beings present (ties lowest building id) | that neighbour's weight multiplied by `bias.visit_weight_mult`; the others unchanged |
| `roam` | wander to another room soon | the building has at least one finished neighbour | travel chance plus `bias.roam_travel_add` |
Menu size is at most `menu.max` (6). When more than six are valid, they are kept in the table order above with `roam` last, so **`roam` is dropped first**, then `quiet`. The menu is a pure function of world state (plus `last_visit_t`, which is sim state). The prompt shows options by number; the ledger stores option keys, so menu order changes cannot silently change a replay.
**Children.** Children (`lifecycle.stage` child) get slots and rule remarks like adults (a warm, short voice is cheap), but their menu is `carry_on` only and they are never put in a request (`gate.children` false). The reason is that `_restless_travel` is also called for children (being.gd:281) and a model nudge on children is outside what has been reviewed. A child never holds a `mind_bias`; the bias block in `_restless_travel` is unreachable for them. Babies get nothing.

### 5.4 Deciding the source, applying, and the ledger
At the deadline, for slot `(id, k)`:
1. If mode is `rules` or `off`: source is `rule`, choice `carry_on`, nothing applied, nothing logged.
2. If mode is `llm`: look up `inbox["id:k"]`. If absent: source `rule`, counter `slot_no_answer`. If present, validate the **choice** in the sim, in this order, and reject the whole entry on the first failure (counter by reason, source `rule`): `entry` has `choice` that is a known option key; the key is in the **menu stored at open**; the key is still valid **now** (a visit target must still be a living friend (or met non-friend for `visit_new`) in a still-neighbouring building; a `roam`/`quiet` needs its neighbours); the being is alive; the being is not a child. A sleeping being takes the line but not the bias (counter `bias_skipped_asleep`).
3. **A bad remark never rejects a good choice.** After the choice passes, the `say` text is checked on its own: a string, at most `say.max_chars`, no newline or digit, `filtered` not true. If it fails, the **choice is kept and the remark is dropped** (counter `say_rejected`); the displayed line is then the intent phrase alone. Source stays `model` because the decision was the model's.
4. If the choice is valid: set `mind_bias = {kind, target, until_t: world.t + bias.ttl_h}` unless the key is `carry_on`; update `last_visit_t[id][target]` for a visit; render the displayed line: for a non-`carry_on` choice, **intent phrase** (the sim picks a template from `intent.<kind>` by the pure variant rule and fills `{other}`), preceded by the remark if valid (`"<remark> <intent>"`, at most `say.total_max_chars`); for `carry_on`, the remark if valid, else the rule remark; store `says[id] = {text, t: world.t, source: "model", t_model: world.t, ...}`; append `{id, k, apply_step: step_index, choice, say, model}` to the ledger (`say` is the valid remark or an empty string). A `carry_on` entry is logged (so replay reproduces the text) but does not count against `sim.apply_max_per_sol`.
5. A decision whose deadline has passed **before** it was delivered is never applied: see the tie rule in 5.2. The ledger therefore contains only decisions that were present at their deadline.

**Replay.** Mode `replay` is `llm` with `inbox` preloaded from a ledger file before step 1 and the driver silent. Each ledger entry sits in the inbox from the start; it is read at the same resolution tick as in the original run, so it is applied or rejected exactly as before (the same state, the same validation). Entries whose source was `rule` are not in the ledger and are not needed: the rule answer is a function of state. This is the induction that gives the guarantee: same seed, same ledger, same inputs at every deadline, same hash.

Ledger line format (JSON lines, one object per line, stable key order): `{"v":1,"id":int,"k":int,"apply_step":int,"choice":"stay","say":"...","model":"..."}`. The **ledger hash** is a SHA-256 over the lines with `say` and `model` removed (behaviour only). The text is deliberately outside the proof of behaviour (test 14).

### 5.5 What a bias changes: one place, three levers, no added draws
The bias is read in one place: `Being._restless_travel` (the last branch of `decide`, after sleep, construction, mining, and the resumed-mine branches; the same locus as 6a effect 1). Behind `if mind_bias != null` (so unset beings, and all children, run the exact baseline code):
- `stay`: `p_travel *= bias.stay_travel_mult` (0.30, E).
- `roam`: `p_travel += bias.roam_travel_add` (0.20, E).
- `visit` / `visit_new` / `quiet`: the weight of the target room is multiplied by `bias.visit_weight_mult` (4.0, E) in the existing weighted room pick.
- After any bias and after the 6a mood term, `p_travel` is clamped to `[world.mood_travel_floor, bias.travel_cap]` (cap 0.60, E). `bias.travel_cap` is set equal to its **sanity minimum**, the largest baseline trait travel chance (0.40) plus `bias.roam_travel_add` (0.20): it never clips a bias on its own, only a bias stacked on a positive 6a mood term.
**Draws.** The bias changes the argument of the one `chance()` call and the weights of the one room pick. The code path is unchanged, so **for the same `chance()` outcome the same draws are consumed as in the baseline** (ai-minds-engineer confirms the exact count per outcome in `_restless_travel` and writes it into test 8). If a changed argument flips the outcome, the draw count of that decision differs by exactly the room-pick draw; that is an outcome change, as in 6a, not an added or removed draw. A bias never affects sleep, joining construction, resuming or starting a mining trip, suit and air logic, births, the Council, ages, or anything about stocks. A being busy with survival work simply never reaches the line that reads the bias; the bias expires on its own at `ttl_h` (8 h, E). Worst case, an adversary that sets `stay` for every being keeps everyone still for idle time only; that is exactly the situation test 16 and the guard in section 13 measure.

### 5.6 The worth gate, priority and the request (mode `llm` only)
The model is for **moments that matter**; calm days belong to the rule voice (Barone: fewer, better lines). A slot becomes a request only when the being is awake, an adult, inside a building, and at least one of these holds:
- an **event slot** (grief, new friend, close, lapse, birth, a god power landing);
- **hard times**: the need hint is `hard_times`, or the band is heavy (0) with a fresh `mood_why`;
- a **season change**: the being's first slot after the sun's season changed;
- a **bright** band (4) with a fresh `mood_why` (good days are worth voicing too);
- the rare calm sample `(id + clock.sol) mod gate.calm_every_n_sols == 0` (12, E; a pure function; 0 disables). This is deliberately rare.
"Fresh" means set within `gate.recent_sols` (1.0, E). Beings that fail the gate get the rule remark only. The sim never counts money; the driver applies the budget (8).
**Fair rotation (a pure function, no id favouritism).** Each request carries `priority = (drama_tier, t_model, tie)` sorted ascending: `drama_tier` 0 for grief, lapse, friend_new, close_new, birth and god power; 1 for hard times and season change; 2 for the rest; then `t_model` from `says[id]` (least recently voiced by the model first; never voiced is -1, so first); then `tie = (id * slot.cell_mult + clock.sol * slot.cell_step) mod 997`, so ties move around from sol to sol instead of always favoring low ids. The driver packs batches from the outbox in `priority` order when capacity is short. No random draw.

### 5.7 The rule voice (built first; the whole no-LLM path)
`MindsVoice.line(facts) -> String`, pure. It picks a **situation** by priority from the facts, then a template by `(id + clock.sol + k) mod n` (pure; no draw; the 6a variant rule), with a **per-being last-said guard**: if the chosen index equals `says[id].variant[situation]`, the next index (mod n) is taken, so a being never repeats its own previous line of that situation. Situations, in priority order: `grief`, `lapse`, `friend_new`, `close_new`, `birth`, `season_turn`, `hard` (the past-tense clause style of 6a), `pledge`, `heavy_other`, `low`, `light`, `bright`, `with_friend`, `alone_even`, `day_even`, `night_even`, and four seasonal `even` lines (the sun's season, which is public colony knowledge). Optional (slice B, section 19): `remembered`, one line per being built from its last stored `why` other ("I still think of {other}.").
Rules for content (a floor each test asserts):
- Each situation has at least `rule.variants_min` (3) hand-written lines, except `day_even` and `night_even`, which need only `rule.variants_min_plain` (2). `season_turn` has one line per season (4, each used once per being per season change), so it is a **one-line-per-season-change** rule, not a rotating pool.
- **Writing order (the budget).** About 60 lines in `data/minds_text.json`, authored by the lead with ai-minds-engineer. Write in this order, so a cut leaves the best lines: (1) named-person situations that use `{other}`: `grief`, `lapse`, `friend_new`, `close_new`, `with_friend`, `heavy_other`; (2) the four seasonal lines and the four `season_turn` lines; (3) `birth`, `hard`, `pledge`; (4) `low`, `light`, `bright`, `alone_even`; (5) `day_even`, `night_even` (two each). Barone's care: they sound like people who live here, short, concrete, never explaining the system.
- **Tone.** Plain, grounded, quiet; no exclamation marks, no emoji, no all-capital words, no second person aimed at the player, no greeting. Lines never contain digits, a sign name, a trait word as a label, or "mood".
- Templates may use `{self}`, `{other}`, `{place}` and `{season}` and nothing else.
- Rule remarks are **mood-colored remarks, not intentions**: no template in a rule situation may promise an action (that vocabulary lives only in `intent.*`, rendered by the sim from a chosen menu item; a test checks it).
When two beings talk, each speaks its current `say` in turn (view, section 7).
**Text filter (shared by rule lines at authoring time in a test, and by model remarks at delivery in the driver):** reject a remark if longer than `say.max_chars` (60), has a newline or control character, has a digit, has a character outside plain printable ASCII (this blocks emoji), has markup characters (`<`, `>`, `{`, `}`, `[`, `]`, backtick, asterisk), has an exclamation mark or an all-capital word of three letters or more, contains a chart term (the 12 sign names from `data/signs.json`, "Deimos", "Phobos", "chart", "horoscope", "zodiac", "birth sign", case-insensitive), contains a player-address term (`filter.player_terms`: "player", "god", "watcher", "hello", "hi there", "greetings", "welcome", "dear", case-insensitive, whole word), names a being not in the allowed set (any `Name-N` token not equal to self, a menu target, or a neighbour named in the facts), or is empty. The driver sets `filtered: true`; the sim also re-checks length, newline and digits itself so a replay file cannot smuggle a bad remark.

### 5.8 Mode, config and switching
`data/minds.json` `mode.default` is `rules` (subject to Q-A). The effective mode comes, in order: the constructor option (tests, tools); then a user config file `user://minds.cfg` read **by the driver, outside `sim/`** and passed in as the option (keys: `mode`, `provider`, `key_env`, optional `model`); then the data default. `llm` requires a key found at the environment variable named by `key_env` (default `STATION_ZERO_AI_KEY`) or in a key file under `user://` outside the repository; if no key or a missing adapter, the effective mode is `rules` and nothing is shown (a debug line in the driver's own file log, never in the game log). Mode is fixed for a run (set in `_init`); switching happens at the next new game or load. A mid-run provider death needs no mode switch: every slot falls to the rule answer by 5.4.
**Dormant rule-mind policy flag (PENDING OWNER item (a)).** `rule.policy_gain` (default 0.0) is reserved in `data/minds.json` for a deterministic personality policy that would let the rule mind pick a menu item from the nature flags and apply the same bias. With the gain 0 the code path is skipped and no hash moves. See section 18 (a).

## 6. The prompt (what goes into a call)
### 6.1 Facts record (built by the sim; codes, not prose)
| Field | Content | Source |
| --- | --- | --- |
| `self` | name (`Name-N`), age stage (`child`, `adult`), role word | `Being`, lifecycle |
| `dossier` | six trait bands (`drive, curiosity, sociability, care, restless, steady`, each 0 low, 1 mid, 2 high by `facts.trait_lo` 0.35 and `facts.trait_hi` 0.65, E), the two-word description the player already sees, and the **nature flags** of 6a (`takes_things_to_heart`, `bright_side`, `slow_to_shake`, `quick_to_shake`, from `mood_base` and `mood_halflife` with the 6a `nature.*` thresholds) | `Persona`, 6a |
| `mood` | band 0 to 4 (heavy to bright; 2 when moods are disabled), `why` key and the other being's name if any, whether the why is fresh (6a `why.fresh_sols`) | 6a fields |
| `place` | building kind and whether crowded | buildings |
| `near` | up to `facts.near_max` (3) other beings in the room: name, whether friend, whether close | relationships |
| `bonds` | up to 2 friends (name, close flag) and `friend_count` band (0, 1 to `facts.friend_band_mid_max` (2), above that) | relationships (cached lookups) |
| `clock` | time-of-day bucket (`dawn`, `day`, `dusk`, `night`, from `clock.dawn_h`, `clock.day_h`, `clock.dusk_h`, `clock.night_h`), season word (the colony's own word for the sun sign's season, from `words.season_by_sign`) | clock, sky |
| `need` | one coarse hint: `tired` (energy under `facts.tired_below`, E), `hard_times` (6a hard clause, no resource named), or none | being, colony |
| `colony` | one of `settling`, `settled` (the age), and whether a Council pledge exists | ages, council |
| `god` | `last`: a **coarse code** of the last power that landed on this being or its room within `god.recent_sols` (3.0, E), one of `none`, `kind`, `harsh`, `other`, mapped from power ids by `god.map` in `data/minds.json` (an unmapped power is `other`). Present in the record from day one; **not used in the prompt text in 6b** (`prompt.use_god` false), reserved for later prompts | powers state (ai-minds-engineer names the read) |
| `menu` | option keys with their human labels (from `data/minds_text.json`) and, for visit, the friend's name | 5.3 |
The facts carry **no sign index, no sign name, no placement, no chart, no longitude, no birth time**. Test 5 scans a built record, key and value, for the 12 sign names, "deimos", "moon", "phobos", "chart".

### 6.2 The chart in the prompt: effects only (a deliberate reading of the brief; flagged, section 18 Q-B)
The brief says the prompt carries "sky chart + 6a mood". The locked decision is that the birth chart is hidden and only its effects are visible. A model told "Deimos in The Drift" may print it, and the player would learn the chart. Resolution: the prompt carries the chart **as its effects in words** (trait bands, the two-word description, the nature flags that come from the Deimos or Moon placement through 6a) and **the current public sky** (season, time of day, which the colonists can see). The model is therefore told who the being is and what the sky is doing, never the placements. A blocklist filter (5.7) is the second line. If the owner wants the raw placements in the prompt, that is an option with a leak risk and a heavier filter (Q-B).

### 6.3 Layout and wording (draft; final text in `data/minds_text.json` under `prompt.*`)
Order, to keep the static part a stable prefix that a provider can cache: (1) a fixed system block; (2) the output rules; (3) per-being blocks in the batch, each a few lines of plain words built from the facts; (4) the menu lists. Draft system block (load-bearing, so quoted; the digit is **built from `say.max_chars` at prompt build time**, not typed): "You voice colonists on Mars in a quiet, realistic settlement. You are given a few people. For each, choose one option number for what they feel like doing with their free time, and write one short remark they might say aloud about how they feel, in their own plain voice, under {say.max_chars} characters. The remark is a feeling, not a plan: do not say where they will go, the system adds that. Plain words, no exclamation marks, no emoji. Never speak to the reader or greet anyone. Never mention stars, signs, charts, numbers, the game, or being an AI. Only name people you were given. Reply with JSON only: a list of objects {"slot": string, "choice": number, "say": string}." The per-being block is a few sentences from the facts, for example: "Vana-3, adult, builder. Warm and nurturing; talks easily; takes things to heart. Out of spirits, still mourning Kiro-12. In the habitat with Dax-8 (a friend). Night. Options: 0 carry on, 1 go and find Dax-8, 2 stay here, 3 wander." (the example is built from words in `data/`, not hard-coded).
Size targets (E): static block about `prompt.system_tokens_est` 350 tokens, each being block about 180 tokens, output about 45 per being. A call is capped at `prompt.max_in_tokens` 1500 and `prompt.max_out_tokens_per_being` 70; if the batch would exceed the input cap the lowest-priority fields (near, then bonds) are dropped in that order before any being is dropped.
Batching: the driver groups requests that share a deadline window into calls of at most `driver.batch_size` (4) beings. One bad entry in a reply does not void its neighbours (5.4 validates per entry).

### 6.4 Output contract
Strict JSON, an array of `{slot, choice, say}`. The parser accepts a code fence around the JSON, ignores extra fields, ignores entries whose `slot` was not requested, and treats anything else as a failed entry. `choice` is the number shown in the menu; the driver converts it to an option key before delivery so the ledger stores keys.

### 6.5 Reserved hooks (not built)
`facts.god` already carries the coarse last-influence code (6.1); a future power (Send a sign, Inspire) may place one fixed phrase into a being's mind via the same field. A hook for 6c memory (a short list of remembered events) stays empty in 6b.

## 7. What the player sees
Text only; no new art; no meter, bar, icon, colony-wide word, spend figure, or online/offline indicator. Constraint: 6a view read whitelist stands (the view reads no mood number); minds adds read-only doors for the line (`voice`) and the intent clause (`intent`) and nothing else.
1. **The panel comes first (cut order: the bubble goes before the panel quote, section 19).** `BeingPanel.voice(world, id) -> String` (new, separate from `lines`, so the 6a four-sentence contract and its tests are untouched) returns the quoted current `say` or an empty string when it is stale. It is shown as a quoted line under the title; it is speech and is not counted among the four sentences. **`BeingPanel.intent(world, id) -> String`** (new) returns a short clause **while a bias is active**, in the 6a panel style (a short present-tense sentence ending in a period) and **naming no AI**, from `intent_clause.<kind>` in `data/minds_text.json`: `visit` "Wants a word with {other}.", `visit_new` "Hopes to meet {other}.", `stay` "Wants to keep to the room.", `quiet` "Wants some quiet.", `roam` "Restless to be elsewhere.". It disappears when the bias expires. It reads a minimal door `Minds.bias_view(id) -> {kind, target_name}` that exposes no number and no time. At 720p, if the 6a success test needs the room, the **quote is dropped first, then the clause**.
2. **Speech where people talk.** Where `view_model._talk_flags` already says a pair is talking, the speaker (alternating, as the pose already alternates) shows its current `say` as a small text bubble above its head, only when its room is visible (roof open or zoom at/over the interior cut, the 6a `selection.open_cut_min` rule, read from its existing key and not duplicated). **Bubbles appear only where pairs talk**, never for a lone being; **none at all when the game speed is above `driver.speed_gate_x`** (the same key the driver uses); and **at most `view.bubbles_max` (3) visible at once**, chosen by the same pure priority as 5.6 (`priority` ascending, so the most dramatic first). A line shows for `view.bubble_s` (4.0 real seconds, E) then rests; the same line is not repeated until the next slot. A model line is shown only while it is younger than `say.show_sols_model` (0.5 sol, E, so a stale model line does not outlive the mood it was written for); a rule line while younger than `say.show_sols_rule` (1.5 sols, E). A being whose line is stale says nothing rather than something stale.
3. **Nothing else.** The log gets no line for a thought, a call, a fallback, a refusal or a cap. The model is never named in play. The behaviour change is felt and, on the panel only, named by the intent clause: a withdrawn being stays where it is, a bright one visits a friend.
4. **How a player can reason about it** (Korppoo's test): **the sim renders the intent phrase from the chosen menu item** (`visit:<id>` renders "I'll go and find {other}"), and the model's free text is only a remark that colors it. So the words and the action cannot disagree: there is nothing for a fragile keyword check to compare, and revision 1's `mismatch` soft check is removed. The rule voice never promises an action (rule remarks are mood-colored; the `intent` vocabulary is written only for the sim's rendering, a test checks both).
Dead beings' lines vanish with the being.
View constants live in `data/minds.json` `view.*`, never in code.

## 8. Cost control (every number a data key; E; the owner sets the money)
Units: sol means a game sol; day and month mean the **real UTC calendar day and month** (my reading of "per day, per month"; Q-C asks the owner to confirm). The meter is the driver's, in `minds/budget.gd`, persisted in `user://minds_meter.json` so a restart cannot reset it. The sim knows no money.
**First slice (section 19): three caps plus the breaker.** The first slice enforces only tokens per UTC day, calls per sol and requests in flight; the other rows are specified now but built in the second slice. Prices stay a fail-closed gate in both: while either price is 0 the driver refuses every call.
| Key | Unit | Start (E) | Slice | Meaning |
| --- | --- | --- | --- | --- |
| `budget.tokens_day` | tokens | 300000 | 1 | per UTC day |
| `budget.calls_per_sol_max` | calls | 3 | 1 | colony-wide calls per game sol, whatever the population, **before the taper below** |
| `budget.max_in_flight` | calls | 2 | 1 | concurrent requests |
| `budget.price_in_per_mtok`, `price_out_per_mtok` | USD per million tokens | 0.0 (unset) | 1 (gate only) | **owner fills with the chosen model's published prices**; while either is 0 the driver refuses every call (fail closed) and the game plays on the rule mind. I do not invent prices |
| `budget.taper_below_frac` | fraction | 0.5 | 1 | **softer taper**: once the remaining UTC-day tokens fall below this fraction of `tokens_day`, the effective allowance is `max(budget.calls_per_sol_min, round(calls_per_sol_max * remaining / (taper_below_frac * tokens_day)))`, so calls thin out gradually instead of stopping on a cliff |
| `budget.calls_per_sol_min` | calls | 1 | 1 | floor of the taper while any budget remains above the reserve |
| `budget.reserve_frac` | fraction | 0.10 | 1 | calls stop when 90% of a cap is spent, so in-flight calls cannot overshoot |
| `budget.tokens_per_colonist_sol` | tokens | 400 | 2 | per-colonist cap, in plus out; a batch call's tokens are split equally across its beings |
| `budget.calls_per_min_max` | calls | 12 | 2 | real-time rate limit (token bucket) |
| `budget.tokens_month` | tokens | 5000000 | 2 | per UTC month |
| `budget.usd_day` | USD | 0.50 | 2 | per UTC day, enforced via prices |
| `budget.usd_month` | USD | 8.00 | 2 | per UTC month |
Order of checks before each call (any fail means no call, silent fallback, counter `skipped_<reason>` in the driver): mode and key present; prices set; breaker closed (9); speed/deadline skip (8.2); calls per sol (with taper); in flight; day tokens with the `reserve_frac` margin, charging the call's **worst case** (input estimate plus `max_out_tokens_per_being` times beings) as a reservation, reconciled to actuals on response; then, in slice 2, per-colonist-sol, rate limit, month tokens and USD.
Arithmetic (E, corrected from revision 1): a batch of 4 with the static block shared is about 350 + 4 x 180 = 1070 tokens in and 180 out, so **about 1,250 tokens a call**, about 310 per being. `tokens_day` 300,000 buys about 240 calls; at 3 calls a sol that is **about 80 sols, about 33 minutes at 1x** (one hour at 1x is about 146 sols, so one sol is about 25 real seconds) before the taper. The taper stretches the live window by an amount the calibration run G4 measures (not computed here). Revision 1's "90 minutes" was wrong. For scale: 440 calls (3 a sol over an hour at 1x, 146 sols) at 1,250 tokens is about 550,000 tokens, so the day cap, not the call cap, is what ends live minds in a long sitting; that is the intended "tight" behaviour. With the stricter worth gate (5.6) most calls carry fewer than four beings, so the figures above are an upper bound on beings voiced and a lower bound on calls' average size. These are estimates for the owner to scale; the USD caps cannot be evaluated until the prices are filled.
### 8.2 Do not pay for answers that cannot arrive
Before sending, the driver compares real time to the deadline: it skips a request when `(deadline_step - world.step_index) x (real seconds per step at the current speed) < driver.latency_p50_s x driver.deadline_margin` (latency p50 is tracked from recent calls, start `driver.latency_p50_s` 1.5, margin 1.5; E), or when the current speed is above `driver.speed_gate_x` (5). So a fast-forward costs nothing and the model is live only where it can matter. With `sim.think_h` 6 the real-time window at 1x is about 6/24 of a sol, about 6 seconds, comfortably over the 2.25 second skip threshold; event slots (2 h, about 2 s) are tighter and are dropped first when latency is high, which is correct. A response that arrives after the deadline is dropped, was paid for, and is counted `late` (the meter charges it; the late rate is a tuning signal for `think_h` and the margin).
### 8.3 Caching (slice 2, first to cut)
A small driver-side cache keyed by a hash of (the static block id, the being's facts record, the menu) with TTL `driver.cache_ttl_sol` 2 serves repeated identical situations without a call; a hit still goes through the same sim validation and is recorded in the ledger like any other. Expected hit rate is low (menus carry ids), so batching, not caching, is the main saving; the key is there so the owner can switch it off (`driver.cache_ttl_sol` 0).

## 9. Failure handling (all silent to the player)
Principle: every slot already has a complete rule answer before any call is made, so a failure never leaves a being without a line or a decision; it only means the model's nudge is absent.
| Failure | Handling | Visible to player |
| --- | --- | --- |
| no key, adapter missing, prices unset | effective mode `rules` at start; one debug-file line | no |
| offline, DNS, connect error | entry failed; breaker counts it | no |
| timeout (`driver.timeout_s` 8) | request cancelled; entry failed | no |
| HTTP 5xx | failed; breaker counts | no |
| HTTP 429 | honor `Retry-After` capped at `driver.retry_after_max_s` 60 by pausing new calls; counts as failure | no |
| HTTP 401/403 | **permanent for the session**: mode becomes `rules`; key never retried; one debug line | no |
| malformed JSON, wrong shape, empty | entry failed (per entry in a batch) | no |
| valid JSON, unknown or stale choice | whole entry rejected in the sim (5.4 step 2), counter | no |
| remark fails the filter or the shape check | **remark dropped, choice kept** (5.4 step 3); the displayed line is the sim's intent phrase; counter `say_rejected` | no |
| budget cap hit (any) | no calls; logged once in the driver file as a cap reached | no |
| breaker open | no calls for `driver.breaker_open_s` (120), then one probe call | no |
Retries: `driver.retries` 0 (the sim-time deadline makes a late retry pointless). Circuit breaker: `driver.breaker_fails` (3) consecutive failures open it. No exception may escape the driver into the sim loop; the driver pump is wrapped, and an internal error disables the driver for the session (mode `rules`) rather than crash. The driver never blocks the main thread: requests are asynchronous and polled between frames. Secrets: the key is read from the environment or a `user://` file, held only in driver memory, sent only in the request header, and redacted from every log; the repository holds no key and `.gitignore` covers the user files; a scan test fails on key-shaped strings anywhere in the repository (test 20).
Debug surface (never in a player build's HUD): `Minds.debug_stats()` and the driver meter, readable by tests, the probe and a developer overlay behind the existing debug toggle only.

## 10. Stats: `stats.minds` (sim side, deterministic given the ledger, never shown)
`slots_opened` (by kind: calm, event), `slots_rule_only` (gate failed), `slot_dropped_carry`, `requests_built` (mode `llm`), `applied_model` (behaviour-changing decisions only), `applied_rule`, `bias_applied` (by kind: stay, roam, visit, visit_new, quiet), `bias_skipped_asleep`, `slot_no_answer`, `rejected` (by reason: `bad_key`, `not_in_menu`, `stale_target`, `no_neighbour`, `dead`, `child`), `apply_dropped_cap`, `say_rejected`, `says_model`, `says_rule`, `ledger_len`, `ledger_hash`. **Wall-clock facts (late, failed, tokens, cost, latency, breaker state) live in the driver meter, not in sim stats**, because live and replay runs must produce equal sim stats.
**The `mn` hash column.** A trailing balance column `mn` (printed `%d`, `applied_model`) follows `md` and is printed in **all** modes (0 when off or rules). Because the existing proofs know only `md`, this edits two files (section 16):
- `tests/balance_lib.gd` line 119: the header column list gains `mn` after `md` (the header and the row writer change together; the `overrides=[...]` header rule of CLAUDE.md section 4 still applies).
- `tests/mood_hash_proof.gd` strips only a final `md` and refuses MISPLACED today. It is changed to strip in this order: **`mn` first (it is last), then `md`**; a row where `mn` is not last, or `md` is not directly before it, is still refused as MISPLACED. Every other proof script that strips `md` gets the same edit (the list is found by search; ai-minds-engineer records it in the task notes).
- The retired `e1f2bdd` chain and the hash tables in the task-6 plan section 4 predate the water rebaseline and are **explicitly marked RETIRED** (a comment in the proof script and a note in the plan section 4): they are not references, and no test compares to them. The references are the new water-rebaseline hashes read from the existing proof scripts.

## 11. Randomness and hash effect, per mechanic
**The minds module draws no random number from `SimRng` or from anything else in `sim/`.** Slot timing, the worth gate's calm sampling, the fair rotation, rule-line variants and menu ordering are pure functions of ids, sols and state.
| Mechanic | SimRng draws | Writes outside the module | Effect on the reference hashes |
| --- | --- | --- | --- |
| Mode `off` (no module) | none | none | none: byte-identical (test 1) |
| Slots, events, facts, menu, rule remark, `says` (mode `rules`) | none | `Minds` members, `stats.minds`, log: nothing | none: byte-identical to `off` (tests 2, 3) |
| Request building, outbox (mode `llm`) | none | outbox only | none |
| Applying a model decision (bias set) | none | `Being.mind_bias` | none until a bias is read |
| Bias read in `_restless_travel` | none added: the same calls with a different `chance()` argument and different pick weights; **the same draws are consumed for the same outcome** | being behaviour | **changes hashes in mode `llm` only**, and only as a function of the ledger; reproducible by replay (tests 11 to 13) |
| Driver, provider, budget, filter | its own non-sim randomness (for example retry jitter) if any; never read by the sim | none | none: the sim sees only delivered entries |
| Dormant `rule.policy_gain` (0.0) | none; path skipped | none | none while 0; item (a) |
Draw-count statement: for one `_restless_travel` decision, a bias leaves the code path and the per-outcome draw count unchanged; downstream draw counts may differ in `llm` mode because an outcome flipped, as with 6a effect 1. In `off` and `rules` they are identical to the baseline (test 3 compares the generator state after a 300-sol run). View code keeps its own RNG, and bubbles use no RNG (the speaker is the existing alternation).

## 12. Cost to the frame (E; measured by the probe; same discipline as 6a)
The 6a mood tick already runs over its budget on the padded pop-159 world, and `friends_of` costs 0.3 to 0.6 ms per call. So minds is built to touch few beings per tick: slots spread over 24 cells a sol and `sim.max_slots_per_tick` is 4, so a pop-160 colony opens at most 4 slots a tick (about 7 per cell expected, the rest carry over; event slots go first). Facts use the cached `top_friend_of` and a per-tick friend lookup shared with the mood module; `friends_of` is called at most `sim.friends_of_per_tick_max` 4 times a tick. Menu building reads only neighbour lists and `last_visit_t`. Event detection compares stored set-times and costs a loop over living beings. Budget (E): minds tick median at most `balance.minds_tick_ms_max` 0.3 ms and max at most `balance.minds_tick_ms_peak_max` 1.0 ms at pop 159; the whole step at most +0.5% over the 6a-dormant step. Rule-line composition is a dictionary lookup. Memory: `says`, `due`, `pending_open` and `last_visit_t` are bounded by population (the last by friends); `ledger` grows with applied decisions (about 150 bytes each; at 3 calls a sol and batch 4, at most 12 a sol, so about 1.8 KB a sol; capped by `sim.ledger_max` 20000 with the oldest kept on disk only by the driver). If the probe shows a breach, the cut order is: shrink `max_slots_per_tick`, drop `near` from facts, lengthen `slot.grid_h`.

## 13. Calibration and balance guards (sim-test-engineer, after the code; five seeds at 300 sols and the 15 `r9_seeds`)
No gameplay number in 6b is calibrated against a live model; calibration uses the mock provider so it is repeatable.
- **G0 reference.** `off` and `rules` reproduce the pinned reference hashes on five seeds, each twice.
- **G1 adversarial worst case.** Mock providers that (a) always answer `stay`, (b) always `roam`, (c) always the first `visit`, (d) always an invalid choice, (e) never answer, (f) answer after the deadline. Each over five seeds, 300 sols, twice. Pass: no crash; (d), (e), (f) reproduce the `rules` hash exactly; (a) to (c) keep T1 to T12 passing as at the reference, and ice delivered per sol, thirst deaths and trips per sol stay within the noise band measured by the 6a method (a control run at a negligible `bias.*` against the dormant mean, 15 seeds), because a bias cannot reach survival branches.
- **G2 unattended decline stays gradual.** The adversarial runs must not make the colony decline faster or slower than the `rules` runs beyond that noise band (owner direction 2026-10-09).
- **G3 popularity loop and isolation.** The 6a company loop (K1 family): `visit` could concentrate bonds on already-befriended beings, and `stay` could isolate. Measure on the 15 seeds with adversarial `visit` and with adversarial `stay`: the **zero-friend share** (isolation), the friend-count spread, and **contacts per being under always-stay**. Pass if none is worse than the 6a noise band; the menu caps (`visit_max` 2, `apply_max_per_sol`) and the longest-unseen ordering of 5.3 are the levers.
- **G4 cost shape.** With a mock that answers at a fixed latency and a long (1,500-sol) run at 1x, the meter reports tokens per colonist per sol and per day within the caps (no call ever charged past a cap), the taper's live-window stretch, and the share of slots that reach the model under the worth gate.
- **G5 perf.** The minds tick budget of section 12 at pop 159.
A bias that fails G1(a to c) or G3 is halved once (`bias.*`), then dropped to 0 (the model path becomes text-only, said plainly to the owner).

## 14. Tests (`tests/test_minds.gd`, `tests/test_minds_driver.gd`, tests first and red; no network; no test with zero checks)
Sim (headless):
1. Mode `off`: five seeds, 300 sols, table hash with `mn` and then `md` stripped (in that order, test 31) equals the pinned reference constants (read from the existing hash-proof scripts, not copied), twice.
2. Mode `rules`: same five hashes, equal to `off`, twice.
3. Mode `rules` vs `off`: `SimRng` state after 300 sols equal (the next 5 draws equal), proving zero draws.
4. Slot schedule is pure: a staged world shows every non-baby being opens exactly `slot.per_sol` calm slots per sol (counted over 10 consecutive sols, with `slot.per_sol` set to 1 and to 2), independent of how many slots it opened before, keyed on `clock.sol`; never more than `sim.max_slots_per_tick` a tick; carry-over opens in the stated order and calm entries older than their sol are dropped; babies never, dead never.
5. Facts: deterministic (two builds equal); required fields present (including `god.last`); **no sign name, sign index, `deimos`, `moon`, `phobos`, `chart`** anywhere in keys or values for 200 generated beings.
6. Menu: `carry_on` first; `visit` entries immediately after it; at most `menu.max`; visit targets are living friends in neighbouring finished buildings and the first is the longest-unseen; `visit_new` only for a met non-friend; `roam`, `quiet`, `stay` appear only when valid; `roam` is the first dropped on overflow; children's menu is `carry_on` only; pure function.
7. Apply validation table (one case each): unknown key, key not in stored menu, stale visit target (moved, died, unfriended), no neighbour, dead being, child being: each is **rejected whole**, source `rule`, counter by reason, nothing in the ledger. **Separate cases for a bad remark** (too long, digit, newline, `filtered: true`): the **choice is applied**, the bias is set, the remark is dropped, `say_rejected` increments, the displayed line is the intent phrase alone, source is `model`, the ledger holds the entry with an empty `say`.
8. Bias effect on a staged being: `stay`, `roam`, `visit`, `visit_new`, `quiet` produce the exact computed `p_travel` and weights (formula in 5.5); clamp to `[world.mood_travel_floor, bias.travel_cap]`; combined with a nonzero 6a mood term; **the draw sequence for a given `chance()` outcome is identical with and without a bias** (script the generator so the outcome is forced both ways: forced fail consumes the baseline count, forced success consumes the baseline pair); and a case where the bias flips the outcome shows the difference is exactly the room-pick draw.
9. Bias scope: with a bias set, a being below `energy.sleep_below` still sleeps; a pending mine intent still resumes; a construction volunteer still joins; the bias expires at `ttl_h` and never extends; a child never holds a bias.
10. `apply_max_per_sol`: more valid behaviour-changing decisions than the cap in one sol apply exactly the cap, in (deadline, id) order; the rest count `apply_dropped_cap`; `carry_on` entries do not count.
11. Replay: run the world live with the scripted mock provider (random latency and failures from a test-local generator **seeded with the fixed constant `tests.mock_seed`** so the test itself is repeatable), save the ledger, build a fresh world in replay mode, run to the same step: table hash, `ledger_hash` and `SimRng` state equal.
12. Replay twice and live-then-replay: three byte-identical tables.
13. Sensitivity: change one early ledger `choice` on a staged world where the effect is certain: table hash differs.
14. Text-only change: replay with every `say` altered (including to a rejected shape) leaves the table hash and `ledger_hash` unchanged.
15. Late delivery and the tie rule: `deliver` at `deadline_step - 1` is applied; `deliver` at `deadline_step` or later is dropped; resolution happens at the first relationships tick at or after the deadline; a ledger without the dropped one replays equal.
16. Adversarial providers (a to f of G1) on a short staged colony: the stated equalities (d, e, f equal `rules`) and no exception.
17. Rule voice coverage: every situation has at least `rule.variants_min` templates (`day_even`, `night_even` at least `rule.variants_min_plain`); every template renders with no unresolved brace for a generated facts set; length, digits, chart terms, tone rules and any action promise checked; variant selection pure; a being never gets the same variant twice in a row for a situation (last-said guard).
18. Filter table (at least 30 cases): good remarks pass; each rule of 5.7 rejects its violator, including emoji, exclamation mark, all-caps word, a player-address term and a greeting.
19. Source scan of `sim/`: no `HTTPRequest`, `HTTPClient`, `StreamPeer`, `PacketPeer`, `OS.get_environment`, `https://`, `http://`, `Authorization`, `api_key`, `FileAccess` on `user://`, provider or model names; the only `sim/` file besides `minds.gd`, `minds_voice.gd` that may mention `minds` is the data accessor in `sim_data.gd` and the hook sites in `world.gd` and `being.gd`.
20. Repository scan: no key-shaped strings; `.gitignore` covers `user://`-style files and `*.jsonl` ledgers outside `tests/fixtures/`.
21. Data parity: key-path list (section 15) equals the leaves of `data/minds.json`; no tunable literal in `sim/minds*.gd` (the existing literal scan with its allowlist); the sanity rules of section 15 hold.
22. `BeingPanel.lines` output byte-equal with minds on and off; `voice()` returns empty when stale and a string of at most `say.total_max_chars` otherwise; `intent()` returns a clause only while a bias is active and never names a model or a number; view source scan finds no ledger, inbox, outbox, provider, or `mind_bias` read (only the `Minds.bias_view` door).
Driver (headless, mocks):
23. Budget meter: each slice-1 cap refuses at its threshold (day tokens, calls per sol with taper, in flight); `reserve_frac` honored; the taper allowance follows its formula and never drops below `calls_per_sol_min`; worst-case reservation reconciled; prices unset refuses everything; persistence round trip across a simulated restart; UTC day rollover. Slice 2 adds month, USD, per-colonist and rate-limit cases.
24. Breaker: opens at the third failure, half-open probe after `breaker_open_s`, closes on success; 401 disables for the session; 429 honors a capped Retry-After.
25. Failure matrix (timeout, 500, malformed, empty, bad choice, filtered remark, partial batch): every case ends in the rule answer or the intent-only line, no exception, and the view-model strings are equal to the no-failure `rules` run where no choice was applied.
26. Prompt builder: static prefix byte-equal across calls; the character limit in the text equals `say.max_chars` (change the key, the text follows); size estimate at or under the caps; the output-rules and tone text present; no chart term anywhere in the built prompt for 200 beings; batch trimming drops fields in the stated order.
27. Parser: strict JSON, code fence accepted, extra fields ignored, unknown slot ignored, per-entry failure isolated.
28. Deadline skip: a request that cannot arrive in time at a fake speed is not sent and not charged; above `speed_gate_x` nothing is sent.
29. Mode resolution: `llm` without a key resolves to `rules` silently; with a key and prices resolves to `llm`; `off` builds no module.
30. Perf: minds tick median and max at padded pop 159 against section 12.
Hash columns: 31. `mn` is last and the proofs strip it: a fixture row with `mn` last and `md` before it passes after stripping `mn` then `md`; a fixture with `mn` misplaced is refused MISPLACED; `balance_lib` header lists `mn` after `md` and a row with its value has the same column count.
New in revision 2:
32. Event slots: a staged grief, new friend, lapse, birth and god-power landing each open one event slot with deadline `sim.think_event_h`, respect `sim.event_cooldown_h`, go before calm slots under the per-tick cap, and a being with an event slot skips the calm slot of the same tick.
33. Worth gate and rotation: a calm, even-band being with no moment is not a request except on the rare calm sample; a moment is; with more requests than capacity the order is `(drama_tier, t_model, tie)` ascending, a being voiced recently goes after one never voiced, and over 40 sols no being among equals is always first or always last (the ascending-id favoritism is absent).
34. Intent rendering and line/action agreement: for every option kind the displayed line contains the sim's intent phrase (and the right other-name for `visit`), whatever the model remark says; a remark that tries to say a different destination is dropped by the filter's allowed-name rule or is only a remark; the panel intent clause matches the active bias kind and disappears on expiry.
35. Bubbles and freshness: no bubble above `driver.speed_gate_x`, none for a lone being, at most `view.bubbles_max` at once chosen by priority; model lines go stale after `say.show_sols_model`, rule lines after `say.show_sols_rule`.
36. Dead-being cleanup: after a death, no `says`, `pending_open`, `outbox`, `last_visit_t` entry remains for the id, a `due` entry resolves as rejected `dead`, and a `visit` to the dead id is `stale_target`.
37. Guard placement: with `moods_enabled` false and `relationships_enabled` true the minds still open slots (mood band 2 in facts); with `relationships_enabled` false the module does nothing.
38. Taper and mode-stable sim: sim `stats.minds` equal between a live run and its replay (wall-clock facts are not in them).

## 15. Tunables (`data/minds.json` and `data/minds_text.json`; key paths; E)
```
mode.default                    "rules"   (Q-A)
slot.per_sol                    1
slot.grid_h                     1.0      sim hours (equals relationships.tick_h; sanity rule)
slot.cell_mult                  7919
slot.cell_step                  5
sim.think_h                     6.0      sim hours from calm slot open to deadline
sim.think_event_h               2.0      sim hours from event slot open to deadline
sim.event_cooldown_h            6.0      sim hours between event slots for one being
sim.event_pending_max_h         6.0      sim hours an event entry may wait in carry-over
sim.max_slots_per_tick          4
sim.apply_max_per_sol           6
sim.outbox_max                  64
sim.ledger_max                  20000
sim.friends_of_per_tick_max     4
menu.max                        6
menu.visit_max                  2
bias.ttl_h                      8.0      sim hours
bias.stay_travel_mult           0.30
bias.roam_travel_add            0.20
bias.visit_weight_mult          4.0
bias.travel_cap                 0.60     equals its sanity minimum
gate.recent_sols                1.0
gate.calm_every_n_sols          12       0 disables the rare calm sample
gate.children                   false
god.recent_sols                 3.0
god.map                         power id -> none|kind|harsh|other   (engineer fills from powers data)
rule.policy_gain                0.0      dormant; PENDING OWNER (a)
facts.trait_lo                  0.35
facts.trait_hi                  0.65
facts.near_max                  3
facts.friend_band_mid_max       2
facts.tired_below               35.0     energy points (above energy.sleep_below 28)
clock.dawn_h                    5.0      hour-of-sol bucket starts (E; align with the existing sky/clock constants if they exist)
clock.day_h                     8.0
clock.dusk_h                    18.0
clock.night_h                   21.0
say.max_chars                   60       the remark; rule and model
say.intent_max_chars            40       the intent phrase
say.total_max_chars             100      remark plus intent
say.show_sols_model             0.5
say.show_sols_rule              1.5
view.bubble_s                   4.0      real seconds
view.bubbles_max                3
(selection.open_cut_min         existing key, read only; not duplicated)
rule.variants_min               3
rule.variants_min_plain         2        day_even and night_even only
filter.player_terms             list
prompt.system_tokens_est        350
prompt.being_tokens_est         180
prompt.max_in_tokens            1500
prompt.max_out_tokens_per_being 70
prompt.use_god                  false
driver.batch_size               4
driver.speed_gate_x             5
driver.latency_p50_s            1.5
driver.deadline_margin          1.5
driver.timeout_s                8.0
driver.retries                  0
driver.breaker_fails            3
driver.breaker_open_s           120
driver.retry_after_max_s        60
driver.cache_ttl_sol            2        slice 2
budget.tokens_day               300000
budget.calls_per_sol_max        3
budget.calls_per_sol_min        1
budget.taper_below_frac         0.5
budget.max_in_flight            2
budget.reserve_frac             0.10
budget.price_in_per_mtok        0.0      unset: calls refused until the owner fills it
budget.price_out_per_mtok       0.0
budget.tokens_per_colonist_sol  400      slice 2
budget.calls_per_min_max        12       slice 2
budget.tokens_month             5000000  slice 2
budget.usd_day                  0.50     slice 2
budget.usd_month                8.00     slice 2
balance.minds_tick_ms_max       0.3
balance.minds_tick_ms_peak_max  1.0
tests.mock_seed                 1013     fixed constant for the mock provider's generator
```
`data/minds_text.json`: `rule.situations.<name>[]` (templates), `intent.<kind>[]` (at least 2 variants each for visit, visit_new, stay, roam, quiet; each at most `say.intent_max_chars`), `intent_clause.<kind>` (panel clause), `words.traits`, `words.mood`, `words.why`, `words.place`, `words.clock`, `words.season`, `words.season_by_sign` (12 entries, sign index to season word; used only inside the sim to produce a season word, never printed as a sign), `words.need`, `menu_labels`, `prompt.system`, `prompt.being`, `prompt.output_rules`, `filter.chart_terms`.
Sanity rules: `slot.grid_h` equals `relationships.tick_h`; `sim.think_h` and `sim.think_event_h` are multiples of `world.fixed_step`; `bias.travel_cap` equals (not merely at least) the largest baseline trait travel chance (0.40) plus `bias.roam_travel_add` at shipped values, and may never be lower; `facts.tired_below` greater than `energy.sleep_below` (28); `say.max_chars` plus `say.intent_max_chars` plus one space at most `say.total_max_chars`; `clock.dawn_h` < `day_h` < `dusk_h` < `night_h` < sol hours; `rule.variants_min` at least 3 and `rule.variants_min_plain` at least 2; `budget.reserve_frac` between 0 and 0.5; `budget.taper_below_frac` between 0 and 1; `budget.calls_per_sol_min` at most `calls_per_sol_max`. No model name, URL or key is a data key in the repository file: the provider name, model and endpoint live in the user config (section 5.8), with a documented example `docs/minds-config.example` containing no secret.

## 16. Edits to existing code (complete list)
| File | Edit | Neutral at `off`/`rules`? |
| --- | --- | --- |
| `sim/minds.gd`, `sim/minds_voice.gd`, `data/minds.json`, `data/minds_text.json` | new | yes |
| `sim/sim_data.gd` | `minds()` accessor | yes |
| `sim/world.gd` | `minds`, `minds_mode`, `mind_enabled`, option read in `_init`, one hook as a **sibling** after the `moods_enabled`/`relationships_enabled` block and before `council.on_step`, guarded by `minds != null and relationships_enabled`; `stats.minds` in `_init_stats` | yes |
| `sim/being.gd` | `mind_bias`, `mind_slot_n`; one guarded block in `_restless_travel` (unreachable for children) | yes: runs only when `mind_bias != null` |
| `minds/*.gd` | driver, prompt, provider interface and first adapter, budget, breaker, filter | outside the sim |
| `tests/balance_lib.gd` | line 119: header column list gains `mn` after `md`; row writer prints it | stripped by proofs |
| `tests/mood_hash_proof.gd` and every other proof script that strips `md` | strip `mn` first, then `md`; MISPLACED check covers both; the `e1f2bdd` chain marked RETIRED in comments | proofs only |
| `tests/mock_provider.gd`, `tests/test_minds*.gd`, `tests/minds_hash_proof.gd` | new | n/a |
| `view/model/being_panel.gd` | `voice()` and `intent()` | no change to `lines` |
| `view/world/*`, `view/main.gd` | speech bubble draw (text only) | view only |
| `docs`: HANDOFF section 9 layout, plan section 4(c) and section 4 hash tables | record `minds/`, the superseded display-only default, and mark the `e1f2bdd` chain hashes RETIRED | docs |

## 17. Design review record
Four reviews were run on revision 1. Below, each finding is recorded with my decision; where a reviewer's view was not taken, the dissent is stated. I am working from the summary the main session gave me of the four reports (their JSONL transcripts end in a hand-back I did not read in full), so quotation is avoided and attribution is to the lens only.

### designer-emergence (Wright lens)
- **Findings applied:** (1) The once-per-sol slot with a long lag reads as weather, not mind: `sim.think_h` 12 became 6, and **event-triggered slots** (death, new friend, lapse, god power landing, `sim.think_event_h` 2) were added, keeping one calm slot per sol (5.2, 15). (2) The popularity-loop risk of `visit` is addressed by offering the longest-unseen friend and a `visit_new` (a met non-friend) and by adding isolation (zero-friend share, contacts per being under always-stay) to guard G3 (5.3, 13). (3) The last god influence enters the facts as a coarse code from day one, reserved for prompt use (6.1). (4) Fair rotation: least recently voiced first, drama first, a pure function of `says[id].t_model`, no ascending-id favoritism (5.6).
- **Dissent, not applied, owner's call (PENDING OWNER (a), section 18):** the reviewer holds that a rule mind with no behaviour channel is too thin a possibility space and that the rule mind should also pick among the same menu by personality. My position is that 6a mood is already the personality channel and a second one would reset every hash a second time. Resolution: ship the policy behind a **dormant data flag** `rule.policy_gain` default 0 (no hash reset, recommended), or enable it now (hash reset).

### designer-feel (Barone lens)
- **Findings applied:** the model gets a **stricter worth gate** (moments that matter: grief, new friend, close, birth, hard times, season change; rule voice carries calm days, 5.6); the **panel quote outranks the bubble** in the cut order; the bubble appears only where pairs talk, none above `driver.speed_gate_x`, at most three visible, model lines last about 0.5 sol (7); **rule-voice writing budget**: named-person and seasonal lines first, a per-being last-said guard, only two variants for `day_even` and `night_even`, tone and no-greeting rules in the prompt and in the filter tests, a one-line-per-season-change seasonal line, an optional remembered line (5.7); a **smaller first slice** with an explicit cut order (19); the **softer taper** of `calls_per_sol_max` as the day budget runs down (8).
- **Dissent between lenses, recorded:** on the cut order of the menu, feel would cut `roam` first and clarity would cut `quiet` first. Both agree `roam` is the least legible once `visit` and `stay` are core. **Decision: `roam` first, then `quiet`** (5.3, 19). Where feel and I differ: none material.

### designer-clarity (Korppoo lens)
- **Findings applied:** the **sim renders the intent phrase** from the chosen menu item and the model's text is only a remark, so words and action cannot disagree; the fragile keyword `mismatch` check is **removed** (7.4). A **panel clause for an active bias** in the 6a style naming no AI ("Wants a word with Dax.", 7.1). **Visit prominent** in the menu (5.3). **Isolation** in guard G3 and **contacts per being under always-stay** (13).
- **Dissent, not applied, PENDING OWNER (Q-G):** clarity wants a quiet options-screen line showing which mode is active so testers can tell why behaviour differs. The owner earlier chose silence for failures; a line showing the configured mode (not failures) may be compatible with that, and it is the owner's to decide. Default until answered: none.
- **Dissent between lenses:** clarity would cut `quiet` before `roam` (above); decided `roam` first.

### code-reviewer (verdict on revision 1: NOT APPROVED)
All must-fix items are applied; each is tested:
1. The slot schedule contradicted itself (a per-slot increment gave about 4.8 slots a sol, not `slot.per_sol`): the cell is now keyed on `clock.sol` and a slot index `j`, carry-over behaviour is stated (5.2, state), test 4.
2. Step 2 (reject a whole entry on a bad `say`) and step 3 (keep the choice, drop the line) disagreed: now **keep the choice, drop the remark, source stays `model`**; test 7, ledger, counters, section 9 aligned (5.4).
3. "No draw added or removed" was false when the bias flips `chance()`: restated as the same draws for the same outcome (5.5, 11); test 8.
4. The `mn` column breaks `tests/mood_hash_proof.gd` and `tests/balance_lib.gd:119`: header edit, strip order (`mn` then `md`), both files in section 16, and the `e1f2bdd` chain and plan section 4 hashes marked RETIRED (10, 16); test 31.
5. Hook placement: `moods.on_step` sits inside the `relationships_enabled` and `moods_enabled` guards; the minds hook is a **sibling** guarded by `minds != null and relationships_enabled` (5.1, 16); test 37.
- Medium and low items applied: children decided (slots and rule remarks yes, menu `carry_on` only, never a request, 5.3); the real clamp field `world.mood_travel_floor` named; `bias.travel_cap` equals its sanity minimum (5.5, 15); test numbering fixed (source scan 19, key scan 20, data parity 21); missing data keys added (`view.*`, friend-count bands, time-of-day bounds, sign-to-season map, `selection.open_cut_min` as a read-only reference, prompt length built from `say.max_chars`, the `tired_below` sanity rule); the carry-over pending list and dead-being cleanup are in state; the tie rule is stated (5.2, test 15); budget arithmetic corrected (about 1,250 tokens a call, 300,000 a day is about 80 sols, about 33 minutes at 1x; 440 calls about 550,000 tokens; 8); this section records the real reviews; the owner-answers file is referenced at the top; test 11's generator is seeded (`tests.mock_seed`); the mismatch check is removed, so no test for it is needed.

### Consensus changes applied that no single reviewer owned
Event-triggered slots with a shorter delay and a model `think_h` of 6; the smaller first slice (section 19).

## 18. Questions for the owner (those I cannot decide) -- all **PENDING OWNER**
- **(a) Rule-mind personality policy (emergence dissent).** Options: (1) ship it behind a dormant data flag `rule.policy_gain` default 0, no hash reset, switch on later after a calibration run (**recommended**); (2) enable it now in `rules` mode, so the rule mind also picks among the menu from nature flags, which makes `rules` a real behaviour layer and **resets every hash** once more (richer possibility space for every player, including those with no key). Trade-off: option 2 gives the stronger Wright-lens answer and costs another baseline reset, balance re-run and a risk of overlapping the 6a mood channel.
- **Q-A. Default mode.** Recommended: ship with `rules` as the default and `llm` as opt-in by config until a provider, a key and prices exist (nothing breaks for a player with no key). Option: default `llm` whenever a key is present.
- **Q-B. The chart in the prompt.** Recommended: effects in words plus the public sky, no placements (section 6.2). Option: raw placements with a blocklist filter (richer voices, a chance the model prints the hidden chart).
- **Q-C. Meaning of "day" and "month" in the budget.** I read them as real UTC day and month. Confirm, or say if you meant game time (a "month" of game sols). Recommended: UTC.
- **Q-D. Which provider and model, and what the prices are.** The spec is provider-neutral. `budget.price_*` stay 0.0 and refuse all calls until you fill them (fail closed). Which small, cheap model tier do you want first?
- **Q-E. Who pays, and how does the key reach a player?** A key embedded in a distributed game is a leaked key. For your own play an environment variable is enough. For anyone else you need a small proxy or each player's own key; a proxy is server work that belongs with 6d (Q6). Recommended: 6b is "owner-only, local key".
- **Q-F. Speed.** Live minds work at about 1x to 5x only (section THE DETERMINISM PROBLEM, cost (a)). Recommended: accept; the alternative is the barrier option (the game pauses briefly at deadlines), which I advise against for feel.
- **Q-G. Options-screen mode line.** Clarity wants a small options-screen line showing which mode is configured (no HUD, no log, no failure state) so testers can tell why behaviour differs; you earlier chose silence. Options: none (default, per your silent rule) or a line showing only the configured mode. Recommended: none for players, a line behind the debug toggle for testers (not a player-facing line).

## 19. Scope: first slice and cut order
**Slice 1 (build and ship first):** rule voice (about 60 lines in the writing order of 5.7) plus the sim's intent phrases; the panel quote (`voice`) and the intent clause; the slot machinery with calm and event slots; the menu `carry_on`, `visit`, `stay`; **one provider adapter**; the ledger and replay; the three budget caps (tokens per UTC day, calls per sol with taper, requests in flight), prices as a fail-closed gate; the circuit breaker; the worth gate and fair rotation. **Deferred to slice 2:** month and USD caps (prices stay fail-closed), per-colonist and rate-limit caps, the driver cache, the menu entries `visit_new`, `quiet`, `roam`, the speech bubble, and the optional `remembered` line. The rule voice and the ledger test scaffolding are never cut.
**Cut order (first cut first), applied to slice 2 contents and then upward if the schedule slips:**
1. The driver cache. 2. Month and USD caps (not built; prices remain a fail-closed gate). 3. Rate-limit and per-colonist caps. 4. The `remembered` line. 5. `roam` (decision: roam before quiet; dissent recorded in section 17). 6. `quiet`. 7. `visit_new`. 8. The speech bubble (the panel quote outranks the bubble). 9. Event slots (calm slots stay). 10. The panel quote (the intent clause stays because it is the legible part). 11. The whole model path (leave the rule voice: a finished 6b with no network, which satisfies "built first").
The revision 1 `mismatch` soft check is gone, not merely cut (section 7.4).

## Changelog
- Revision 1 (2026-10-10): first draft. Assistant reviews pending.
- Revision 2 (2026-10-10): applied four reviews. Code-reviewer must-fixes: slot schedule keyed on `clock.sol` with `j` (and carry-over stated); bad remark keeps the choice (test 7, ledger, counters); draw statement restated as same draws for the same outcome (test 8); `mn` column with strip order and both proof files, `e1f2bdd` hashes RETIRED; hook placed as a sibling guarded by `minds != null and relationships_enabled`; children decided; clamp field `world.mood_travel_floor`; test numbering and missing data keys; tie rule; budget arithmetic; owner-answers reference; seeded generator for test 11. Designer consensus: sim-rendered intent phrase and remark-only model text (mismatch check removed); `think_h` 6 and event slots; stricter worth gate and fair rotation; visit prominent plus longest-unseen and `visit_new`; isolation in G3; roam-first cut order; bubble rules and panel intent clause; rule-voice writing budget and tone rules; coarse `god.last` in facts; slice 1 with explicit cut order; softer taper. Owner items marked PENDING OWNER: (a) and Q-A to Q-G.
