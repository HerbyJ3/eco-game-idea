# Spec: AI minds (Task 6b): a rule-based voice first, a cloud model that may nudge what beings do, a ledger that keeps every run reproducible (revision 1)

Status: draft for the three assistant reviews and the code-reviewer. Docs only; no code. The assistant-designer reviews have NOT been run yet (the lead cannot start them; the main session runs them). Section 17 holds the questions I am putting to them and my own pre-read, clearly marked as mine and not as theirs. Numbers marked E are estimates until a calibration run measures them.

Source of truth: `station-zero-handoff/HANDOFF.md` sections 2 (locked decisions), 3 (chart, Deimos row), 5 (Social: "Lines are a fixed list for now; AI minds replace them"), 8, 10; `docs/tasks/task-6-plan.md` (6b line and section 4 constraint (a) to (d)); `docs/design/task-6-scoping.md`; `docs/specs/emotions.md` revision 4 (mood fields, bands, why, panel contract, view read whitelist, hash discipline) and its shipped-dormant state (mood gains 0.0, new water-rebaseline hashes are the reference, the `e1f2bdd` chain is retired). Facts read from code for this spec: `sim/rng.gd` (`chance` is `randf() < p`), `sim/being.gd` (`decide` branch order; `_restless_travel` makes one `chance()` draw and one `randf()` room pick), `sim/world.gd` (member list, `_init(seed, options)`), `sim/persona.gd`, `sim/sky.gd`, `view/model/view_model.gd` (`_talk_flags`, `_pair_talks`: talk is a pose with no words), `data/mood.json` (key style).

## Owner answers (Herby, 2026-10-10), binding for this spec
- **Q5 host: cloud API.** (Local model is out for 6b.)
- **Q5 influence: AI output CAN change what beings do.** It is not display-only. This overrides plan section 4 constraint (c) ("default is display-only"); the plan line is superseded by this spec once the owner confirms the section 3 answer.
- **Q4 budget: a tight cap.** At the cap, or on any failure, fall back **silently** to the no-LLM rule-based path.
- **Failure: silent fallback.** No error text, no icon, no "offline" word reaches the player.
- Also binding from the brief: every number is a data key; the provider code stays outside `sim/`; no secrets and no network in `sim/`.
- Not answered (section 18): which provider and model, who pays, and how the key reaches a player who is not the owner.

Locked decisions respected: **influence-only god** (the AI is the beings' own mind, not the player's hand; the player still acts only through powers; a hook for a future power to speak into a mind is reserved, section 6.5, and not built); **hidden birth chart** (the prompt carries the chart only as effects in words, never a sign name, section 6.2; a filter blocks leaks, section 5.7); **naturalism, ages not meters** (no AI meter, no spend bar, no "minds online" word); **per-being energy, power as a budget, ice pressure is not failure** (the AI can only bend idle wandering; it cannot touch sleep, building, mining, trips, births, stocks; section 5.5). **Owner direction 2026-10-09 (the colony is not meant to survive unattended)** is respected: the AI must not become a hidden rescuer or a hidden killer; a guard run proves it (section 13).

---

## THE DETERMINISM PROBLEM (flagged for the owner; recommendation first)

**The conflict.** The project proves itself with seeded headless runs: a seed gives a table hash, five seeds twice must match byte for byte, and `*_hash_proof` tests chain back to earlier tasks. A cloud model is not repeatable: it answers differently each time, it takes a wall-clock-dependent time to answer, and it fails at random moments. If its answer feeds the sim, then the same seed gives different colonies, the hash proofs cannot be run live, and a balance number can no longer be separated from the model's mood that day.

**Options**
1. **Display-only.** The AI writes words; nothing in the sim reads them. Hashes untouched. Rejected by the owner (Q5: output can change behaviour).
2. **Live, unconstrained.** The sim reads whatever the model says whenever it arrives. Rejected: unreproducible, unsafe (a model could say "leave the colony"), and untestable.
3. **Whitelist only.** The model picks from a small menu the sim builds and re-validates. Bounded and safe, but on its own still unreproducible: which option is picked, and whether the answer arrives before the moment it is needed, vary run to run.
4. **Whitelist plus an applied-decision ledger and replay (recommended).** Option 3, plus: every model decision that the sim actually applies is written to an append-only ledger keyed by (being, slot); the sim consumes decisions from an inbox at a fixed **sim-time deadline**, never when they happen to arrive; a late or missing answer means the deterministic rule mind runs instead; and a run can be replayed from `seed + ledger` with no network and reproduces the same table hash. The model's randomness becomes **a recorded input, like the seed**, not hidden state.
5. **Barrier.** Pause the sim at each deadline until the model answers or times out. Reproducible in the same way as option 4 but freezes the game for seconds at a time. Rejected for feel (Barone) and legibility (Korppoo: a sim that stalls for no visible reason). Kept as a named alternative.

**Recommendation: option 4.** What it guarantees (each is a test in section 14):
- **Mode `off`**: the AI module is not even built; every table hash equals the current pinned reference byte for byte (test 1). Mood stays as shipped (dormant gains).
- **Mode `rules`** (the shipped default; the no-LLM path): the rule mind makes **no behaviour change at all**. Its only product is words (display). So `rules` hashes equal `off` hashes byte for byte, and the fallback is exactly "the colony as it already plays" (tests 2, 3). Reason: the existing sim already is a rule-based mind (traits, needs, and 6a mood when its gains go on); the AI is a **nudge laid over it**, and falling back means removing the nudge.
- **Mode `llm`**: the run is identified by **(seed, ledger)**. Live play writes the ledger. `tests/` and balance runs replay a ledger with no network and get the same hash twice (tests 11 to 13). Two live runs of one seed differ, as two human players' runs do, and that is honest: the ledger says exactly how.
- **No new RNG draw, anywhere** (section 11). The model never reaches `SimRng`. Draw count and order are those of the baseline except where a nudge changes an outcome, which is the same mechanism as the 6a mood gain.
- The model's text is excluded from the hash (test 14), and a worst-case adversarial provider is a test (16) and a calibration guard (13), so safety does not depend on the model behaving.

What this costs, said plainly: (a) **live minds only matter at slow speeds.** A cloud call takes seconds; at 1000x a sol passes in 25 ms. The deadline is in sim time, so answers that cannot arrive in time are never sent or never applied, and at high speed the colony runs on its rule minds (silently). The shipped numbers (`sim.think_h` 12, `driver.speed_gate_x` 5, E) make the model live at about 1x to 5x. (b) A live game is not reproducible from the seed alone; only from seed plus ledger. (c) A behaviour nudge slightly changes outcomes like any behaviour change, so live-AI play is **not** the balance baseline; balance runs use `off`/`rules` and mock providers. The owner's accepted "baseline reset" of 6a is not repeated here: `rules` and `off` do not move any hash.

**Where it is genuinely the owner's call** (section 18, Q-A): whether the player-facing default should be `rules` (recommended; AI is opt-in via config until a provider and key are settled) or `llm` when a key exists.

---

## 0. The design in one paragraph
Once per sol (at a time staggered by being) every non-baby colonist gets a **thought slot**. At the slot the sim builds a small **facts record** about the being (the chart as effect words, the 6a mood band and why, the place, the time of day and season, who is near, a coarse need hint) and a **menu** of at most five things the being could do with its idle time. The rule mind answers at once and locally: it picks "carry on" (no behaviour change) and composes one short **line** from hand-written templates, so every colony has voices with no network. In mode `llm`, the same facts go out to a cloud model in a batch; the model returns, per being, a menu choice and a line. Twelve sim hours later (the sim-time deadline) the sim looks in its inbox: if a valid answer is there it is applied (a bounded, expiring nudge to idle wandering, plus the line); if not, the rule answer stands. Every applied model decision is appended to a ledger so the run can be replayed offline. The player sees the lines as speech where people talk and as one quoted line on the being panel; they are never told whether a model or a template wrote it.

## 1. Purpose
Replace the prototype's fixed conversation list (HANDOFF section 5) with voices that follow each being's nature and moment, and let a being's own "reasoning" change what it does with idle time, while keeping the colony reproducible, bounded, cheap, and playable offline. Design question: how much power does a model get? Answer: a menu choice among idle-time behaviours, expiring, capped per sol, never touching survival. Wright's lens: more authored stories from the same agents; Barone's: a handful of well-made lines is better than endless generic chatter; Korppoo's: the player must be able to reason about the system without a dashboard.

**Finding that changes the work (read from code).** The Godot port has **no conversation lines**: `view_model._talk_flags` and `_pair_talks` only switch a talk pose; no words exist anywhere in `sim/` or `view/` (the "fixed list" lives only in the HTML prototype). So "replaces the fixed lines" means 6b **builds** the first lines in the port (the rule voice) and the model path overrides them. The speech-bubble draw is new view work (text only, no art).

## 2. Terms
| Term | Meaning |
| --- | --- |
| slot | one thought opportunity for one being: key `(id, k)` where `k` is the being's running slot counter. `slot.per_sol` slots per being per sol |
| facts | the deterministic structured record the sim builds at a slot (codes, no prose, no sign names) |
| menu | the ordered list of option keys the sim offers at a slot, built and re-validated by the sim |
| option key | `carry_on`, `stay`, `roam`, `visit:<id>`, `quiet` |
| rule mind | the local deterministic mind: picks `carry_on` and composes a line from templates. It is the whole no-LLM path |
| model mind | the cloud call that returns a choice and a line per being |
| deadline | the sim step at which a slot is resolved: slot open step plus `sim.think_h` hours |
| inbox | decisions delivered by the driver, keyed by slot, waiting for their deadline |
| ledger | append-only record of every model decision that was applied (section 5.4) |
| bias | the bounded, expiring nudge a choice leaves on a being (`mind_bias`) |
| say | the being's current line (display only), with its source (rule or model) |
| driver | the code outside `sim/` that owns the provider, key, budget, network and timing |
| mode | `off`, `rules` (default), `llm`; `replay` is `llm` with the inbox preloaded from a ledger file and the driver silent |

## 3. Architecture and the sim boundary
```
sim/minds.gd         (new)  slots, facts, menu, validation, inbox/ledger, bias, rule voice hook. Pure: no network, no wall clock, no key, no file I/O.
sim/minds_voice.gd   (new)  rule voice: facts -> line from data templates. Pure function.
minds/               (new, OUTSIDE sim/)  driver.gd (pump, speed/deadline skip), prompt.gd, provider.gd (interface), provider_<name>.gd (first adapter, owner's pick), budget.gd (meter), breaker.gd, filter.gd (text filter shared with tests).
tests/mock_provider.gd (new) scripted answers, latency, failures; the only "provider" tests use.
data/minds.json (new) all tunables. data/minds_text.json (new) rule templates and prompt words.
```
Rules of the boundary: `sim/` never mentions HTTP, sockets, environment variables, keys, user files, providers or model names (a source scan is test 21). The driver reads the world's `minds.outbox` and writes into it only through `Minds.deliver(...)`, called on the main thread between `advance()` calls, never inside a step. The prompt builder and the text filter live in `minds/` and read `facts` records; they are pure and unit-tested with no network. The sim accepts the filter's verdict only as data in a delivered entry (`filtered: true` makes it a rejection), so the sim does not depend on the filter code. A new top-level folder `minds/` is an addition to the HANDOFF section 9 layout; it is recorded there at close.

## 4. State (all new)
`SimWorld` gains `minds` (a `Minds` or null), `minds_mode` (`off`, `rules`, `llm`; set from `options.minds_mode` in `_init` like `moods_enabled`, default from `data/minds.json` `mode.default` = `rules`), and a cached `mind_enabled` bool read by `Being`. `Being` gains `mind_bias` (Variant: null or `{kind, target, until_t}`) and `mind_slot_n` (int, the running slot counter). Nothing else on `Being`.

`Minds` holds: `cfg`, `seen_ticks` (last relationships tick consumed), `due` (array of `{id, k, open_step, deadline_step, menu, facts_hash}` sorted by deadline then id), `outbox` (array of request records for the driver: `{id, k, deadline_step, facts, menu}`; filled only in mode `llm`; capped at `sim.outbox_max`, oldest dropped), `inbox` (Dictionary keyed `"id:k"` to a delivered entry), `ledger` (Array of applied model decisions), `says` (Dictionary id to `{text, t, source}`), `applied_sol` and `applied_this_sol` (cap counters), counters of section 10.

Mode `off`: `minds` is null and no hook runs (the world is the 6a-dormant world). Mode `rules`: `minds` runs, `outbox` stays empty, `inbox` is never read for choices.

## 5. Rules
### 5.1 Where it runs
One hook in `SimWorld.step()`, directly after `moods.on_step(self)` (phase 11c) and before `council.on_step(self)`: `minds.on_step(self)`. It acts only on steps where `relationships.ticks` differs from `seen_ticks` (the cadence rule moods and the Council use; one relationships tick is `relationships.tick_h` 1.0 sim hour). No sol hook is needed. If relationships is disabled the module does nothing.

### 5.2 The tick, in order
1. **Expire** biases whose `until_t <= world.t` (set `mind_bias` null).
2. **Resolve due slots** whose `deadline_step <= step_index`, in (deadline, id) order. For each: decide the source (5.4), apply or not, write `says[id]`, append to the ledger if a model decision was applied. At most `sim.apply_max_per_sol` model decisions apply per sol colony-wide; the rest fall to the rule answer and count `apply_dropped_cap`.
3. **Open new slots.** Beings that are alive, not `baby` by `lifecycle.stage`, and whose slot cell matches the current hour cell. The cell is `(id * slot.cell_mult + k * slot.cell_step) mod cells_per_sol` with `cells_per_sol = floor(sol_h / slot.grid_h)` (24 at the shipped 1.0 h grid), so slots spread across the sol and different beings and different slot numbers land at different hours. No draw. At most `sim.max_slots_per_tick` slots open per tick, taken in ascending id; the remainder carry to the next tick (they stay due in an internal pending list, deterministic). Opening a slot: `mind_slot_n += 1`; build facts (6.1); build the menu (5.3); compute the rule line immediately and store it in `says[id]` as source `rule`; if mode is `llm` and the being passes the **worth gate** (5.6), append a request to `outbox`; push a `due` entry with `deadline_step = step_index + round(sim.think_h / world.fixed_step)`.
4. Update counters.

### 5.3 The menu (what the model may choose)
Built by the sim at slot open, re-checked at the deadline. Option keys:
| Key | Meaning | Listed when | Bias effect (5.5) |
| --- | --- | --- | --- |
| `carry_on` | no nudge. Always present, always index 0 | always | none |
| `stay` | keep to the room for a while | being is inside a building | travel chance times `bias.stay_travel_mult` |
| `roam` | wander to another room soon | the building has at least one finished neighbour | travel chance plus `bias.roam_travel_add` |
| `visit:<id>` | go to a named friend | the target holds the `friends` flag with this being (from `top_friend_of` and `friends_of`), is alive, and is in a **neighbouring** finished building now; at most `menu.visit_max` (2), highest bond first, ties lowest id | weight of the room holding the target multiplied by `bias.visit_weight_mult` |
| `quiet` | go somewhere with few people | at least two neighbours; the neighbour with the fewest beings present (ties lowest building id) | that neighbour's weight multiplied by `bias.visit_weight_mult`; the others unchanged |
Menu size is at most `menu.max` (5). The menu is a pure function of world state. The prompt shows options by number; the ledger stores option keys, so menu order changes cannot silently change a replay.

### 5.4 Deciding the source, applying, and the ledger
At the deadline, for slot `(id, k)`:
1. If mode is `rules` or `off`: source is `rule`, choice `carry_on`, nothing applied, nothing logged.
2. If mode is `llm`: look up `inbox["id:k"]`. If absent: source `rule`, counter `slot_no_answer`. If present, validate **in the sim**, in this order, and reject on the first failure (counter by reason, source `rule`): `entry` has `choice` that is a known option key; the key is in the **menu stored at open**; the key is still valid **now** (a visit target must still be a living friend in a still-neighbouring building; a `roam`/`quiet` needs its neighbours); the being is alive and not asleep-through (a sleeping being takes the say but not the bias, counter `bias_skipped_asleep`); `say` passes the shape checks (string, at most `say.max_chars`, `filtered` not true).
3. If valid: set `mind_bias = {kind, target, until_t: world.t + bias.ttl_h}` unless the key is `carry_on`; store `says[id] = {text: say or rule line, t: world.t, source: "model"}` (a model `say` replaces the rule line only if it passes the shape check; a valid choice with a rejected line keeps the rule line, counter `say_rejected`); append `{id, k, apply_step: step_index, choice, say, model}` to the ledger.
4. A decision whose deadline has passed **before** it was delivered is never applied: `deliver` stores into `inbox` only if `deadline_step > step_index` at delivery, else it is dropped (the driver counts `late`). The ledger therefore contains only decisions that were present at their deadline.

**Replay.** Mode `replay` is `llm` with `inbox` preloaded from a ledger file before step 1 and the driver silent. Each ledger entry sits in the inbox from the start; it is read at the same deadline as in the original run, so it is applied or rejected exactly as before (the same state, the same validation). Entries whose source was `rule` are not in the ledger and are not needed: the rule answer is a function of state. This is the induction that gives the guarantee: same seed, same ledger, same inputs at every deadline, same hash.

Ledger line format (JSON lines, one object per line, stable key order): `{"v":1,"id":int,"k":int,"apply_step":int,"choice":"stay","say":"...","model":"..."}`. The **ledger hash** is a SHA-256 over the lines with `say` and `model` removed (behaviour only). The text is deliberately outside the proof of behaviour (test 14).

### 5.5 What a bias changes: one place, three levers, no draws
The bias is read in one place: `Being._restless_travel` (the last branch of `decide`, after sleep, construction, mining, and the resumed-mine branches; the same locus as 6a effect 1). Behind `if mind_bias != null` (so unset beings run the exact baseline code):
- `stay`: `p_travel *= bias.stay_travel_mult` (0.30, E).
- `roam`: `p_travel += bias.roam_travel_add` (0.20, E).
- `visit` / `quiet`: the weight of the target room is multiplied by `bias.visit_weight_mult` (4.0, E) in the existing weighted room pick.
- After any bias and after the 6a mood term, `p_travel` is clamped to `[effects.travel_floor, bias.travel_cap]` (cap 0.60, E).
Still one `chance()` call and one `randf()` room pick at the same positions: **no draw is added, removed or reordered inside a decision** (a changed argument and changed weights only). A bias never affects sleep, joining construction, resuming or starting a mining trip, suit and air logic, births, the Council, ages, or anything about stocks. A being busy with survival work simply never reaches the line that reads the bias; the bias expires on its own at `ttl_h` (8 h, E). Worst case, an adversary that sets `stay` for every being keeps everyone still for idle time only; that is exactly the situation test 16 and the guard in section 13 measure.

### 5.6 The worth gate and the request (mode `llm` only)
A slot becomes a request only when the being is **worth a call**, to keep cost down and make the voices matter: awake and inside a building, and at least one of: band not even (6a); a stored `mood_why` set within `gate.recent_sols` (2.0); a new friend, close, lapse or birth event involving the being within `gate.recent_sols`; or the calm sampling rule `(id + sol_number) mod gate.calm_every_n_sols == 0` (4, E; a pure function, no draw). Beings that fail the gate get the rule line only. The sim never counts money; the driver applies the budget (8). A request carries `facts`, `menu`, `deadline_step`; the driver may drop it.

### 5.7 The rule voice (built first; the whole no-LLM path)
`MindsVoice.line(facts) -> String`, pure. It picks a **situation** by priority from the facts, then a template by `(id + sol_number + k) mod n` (pure; no draw; the 6a variant rule). Situations, in priority order: `grief`, `lapse`, `friend_new`, `close_new`, `birth`, `hard` (the past-tense clause style of 6a), `pledge`, `heavy_other`, `low`, `light`, `bright`, `with_friend`, `alone_even`, `day_even`, `night_even`, and four seasonal `even` lines (the sun's season, which is public colony knowledge). Each situation has at least `rule.variants_min` (3, a floor the test asserts; ship target 4) hand-written lines in `data/minds_text.json` (about 60 lines, authored by the lead with ai-minds-engineer; Barone's care: they should sound like people who live here, short, concrete, never explaining the system). Templates may use `{self}`, `{other}`, `{place}` and `{season}` and nothing else. Lines never contain digits, a sign name, a trait word as a label, or "mood". Slot lines in the rule path also stand in for what a conversation would say: when two beings talk, each speaks its current `say` in turn (view, section 7).
**Text filter (shared by rule lines at authoring time in a test, and by model lines at delivery in the driver):** reject a line if longer than `say.max_chars` (90), has a newline or control character, has a digit, has markup characters (`<`, `>`, `{`, `}`, `[`, `]`, backtick, asterisk), contains a chart term (the 12 sign names from `data/signs.json`, "Deimos", "Phobos", "chart", "horoscope", "zodiac", "birth sign", case-insensitive), names a being not in the allowed set (any `Name-N` token not equal to self, a menu target, or a neighbour named in the facts), or is empty. The driver sets `filtered: true`; the sim also re-checks length, newline and digits itself so a replay file cannot smuggle a bad line.

### 5.8 Mode, config and switching
`data/minds.json` `mode.default` is `rules`. The effective mode comes, in order: the constructor option (tests, tools); then a user config file `user://minds.cfg` read **by the driver, outside `sim/`** and passed in as the option (keys: `mode`, `provider`, `key_env`, optional `model`); then the data default. `llm` requires a key found at the environment variable named by `key_env` (default `STATION_ZERO_AI_KEY`) or in a key file under `user://` outside the repository; if no key or a missing adapter, the effective mode is `rules` and nothing is shown (a debug line in the driver's own file log, never in the game log). Mode is fixed for a run (set in `_init`); switching happens at the next new game or load. A mid-run provider death needs no mode switch: every slot falls to the rule answer by 5.4.

## 6. The prompt (what goes into a call)
### 6.1 Facts record (built by the sim; codes, not prose)
| Field | Content | Source |
| --- | --- | --- |
| `self` | name (`Name-N`), age stage (`child`, `adult`), role word | `Being`, lifecycle |
| `dossier` | six trait bands (`drive, curiosity, sociability, care, restless, steady`, each 0 low, 1 mid, 2 high by `facts.trait_lo` 0.35 and `facts.trait_hi` 0.65, E), the two-word description the player already sees, and the **nature flags** of 6a (`takes_things_to_heart`, `bright_side`, `slow_to_shake`, `quick_to_shake`, from `mood_base` and `mood_halflife` with the 6a `nature.*` thresholds) | `Persona`, 6a |
| `mood` | band 0 to 4 (heavy to bright), `why` key and the other being's name if any, whether the why is fresh (6a `why.fresh_sols`) | 6a fields |
| `place` | building kind and whether crowded | buildings |
| `near` | up to `facts.near_max` (3) other beings in the room: name, whether friend, whether close | relationships |
| `bonds` | up to 2 friends (name, close flag) and `friend_count` band (0, 1 to 2, 3 or more) | relationships (cached lookups) |
| `clock` | time-of-day bucket (`dawn`, `day`, `dusk`, `night`), season word (the colony's own word for the sun sign's season) | clock, sky |
| `need` | one coarse hint: `tired` (energy under `facts.tired_below`, E), `hard_times` (6a hard clause, no resource named), or none | being, colony |
| `colony` | one of `settling`, `settled` (the age), and whether a Council pledge exists | ages, council |
| `god` | reserved, always empty in 6b | future powers |
| `menu` | option keys with their human labels (from `data/minds_text.json`) and, for visit, the friend's name | 5.3 |
The facts carry **no sign index, no sign name, no placement, no chart, no longitude, no birth time**. Test 5 scans a built record, key and value, for the 12 sign names, "deimos", "moon", "phobos", "chart".

### 6.2 The chart in the prompt: effects only (a deliberate reading of the brief; flagged, section 18 Q-B)
The brief says the prompt carries "sky chart + 6a mood". The locked decision is that the birth chart is hidden and only its effects are visible. A model told "Deimos in The Drift" may print it, and the player would learn the chart. Resolution: the prompt carries the chart **as its effects in words** (trait bands, the two-word description, the nature flags that come from the Deimos or Moon placement through 6a) and **the current public sky** (season, time of day, which the colonists can see). The model is therefore told who the being is and what the sky is doing, never the placements. A blocklist filter (5.7) is the second line. If the owner wants the raw placements in the prompt, that is an option with a leak risk and a heavier filter (Q-B).

### 6.3 Layout and wording (draft; final text in `data/minds_text.json` under `prompt.*`)
Order, to keep the static part a stable prefix that a provider can cache: (1) a fixed system block; (2) the output rules; (3) per-being blocks in the batch, each a few lines of plain words built from the facts; (4) the menu lists. Draft system block (load-bearing, so quoted): "You voice colonists on Mars in a quiet, realistic settlement. You are given a few people. For each, choose one option number for what they feel like doing with their free time, and write one short line they might say aloud, in their own plain voice, under 90 characters. Never mention stars, signs, charts, numbers, the game, or being an AI. Only name people you were given. Reply with JSON only: a list of objects {"slot": string, "choice": number, "say": string}." The per-being block is a few sentences from the facts, for example: "Vana-3, adult, builder. Warm and nurturing; talks easily; takes things to heart. Out of spirits, still mourning Kiro-12. In the habitat with Dax-8 (a friend). Night. Options: 0 carry on, 1 stay here, 2 wander, 3 visit Dax-8." (the example is built from words in `data/`, not hard-coded).
Size targets (E): static block about `prompt.system_tokens_est` 350 tokens, each being block about 180 tokens, output about 45 per being. A call is capped at `prompt.max_in_tokens` 1500 and `prompt.max_out_tokens_per_being` 70; if the batch would exceed the input cap the lowest-priority fields (near, then bonds) are dropped in that order before any being is dropped.
Batching: the driver groups requests that share a deadline window into calls of at most `driver.batch_size` (4) beings. One bad entry in a reply does not void its neighbours (5.4 validates per entry).

### 6.4 Output contract
Strict JSON, an array of `{slot, choice, say}`. The parser accepts a code fence around the JSON, ignores extra fields, ignores entries whose `slot` was not requested, and treats anything else as a failed entry. `choice` is the number shown in the menu; the driver converts it to an option key before delivery so the ledger stores keys.

### 6.5 Reserved hooks (not built)
`facts.god` for a future power (Send a sign, Inspire) to place one fixed phrase into a being's mind; a hook for 6c memory (a short list of remembered events); both empty in 6b.

## 7. What the player sees
Text only; no new art; no meter, bar, icon, colony-wide word, spend figure, or online/offline indicator. Constraint: 6a view read whitelist stands (the view reads no mood number); minds adds one more read-only door.
1. **Speech where people talk.** Where `view_model._talk_flags` already says a pair is talking, the speaker (alternating, as the pose already alternates) shows its current `say` as a small text bubble above its head, only when its room is visible (roof open or zoom at/over the interior cut, the 6a `selection.open_cut_min` rule). A line shows for `say.bubble_s` (4.0 real seconds, E) then rests; the same line is not repeated until the next slot. A being whose `say` is older than `say.show_sols` (1.5 sols, E) says nothing rather than something stale. View constants live in `data/minds.json` `view.*`, never in code.
2. **The being panel.** `BeingPanel.voice(world, id) -> String` (new, separate from `lines`, so the 6a four-sentence contract and its tests are untouched) returns the quoted current `say` or an empty string when it is stale. It is shown as a quoted line under the title. It is not counted among the four sentences (it is speech, and it carries no terminal period requirement). If the success test of 6a 7.4 needs the room, the line is the first thing dropped at 720p.
3. **Nothing else.** The log gets no line for a thought, a call, a fallback, a refusal or a cap. The model is never named in play. The behaviour change is felt, not announced: a withdrawn being stays where it is, a bright one visits a friend.
4. **How a player can reason about it** (Korppoo's test): a being's quoted line and what it then does agree (a "I'll go and find Dax" line follows a `visit` choice; a "I'd rather stay here" line follows `stay`), because the model returns both from one menu; the rule voice never promises an action it will not take (rule lines are mood-colored remarks, not intentions: templates in the `intent` family are not written for the rule path, a test checks it). Because the model's line is chosen alongside a menu option, the line can be checked against the option (driver-side soft check: a line that contains "go"/"visit" while the choice is `stay` is flagged `mismatch` and the **line** is dropped, the choice kept; E, a refinement the calibration may cut).
Dead beings' lines vanish with the being.

## 8. Cost control (every number a data key; E; the owner sets the money)
Units: sol means a game sol; day and month mean the **real UTC calendar day and month** (my reading of "per day, per month"; Q-C asks the owner to confirm). The meter is the driver's, in `minds/budget.gd`, persisted in `user://minds_meter.json` so a restart cannot reset it. The sim knows no money.
| Key | Unit | Start (E) | Meaning |
| --- | --- | --- | --- |
| `budget.slots_calls_per_colonist_sol` | calls | 1 | at most one model call share per colonist per sol |
| `budget.tokens_per_colonist_sol` | tokens | 400 | per-colonist cap, in plus out; a batch call's tokens are split equally across its beings |
| `budget.calls_per_sol_max` | calls | 3 | colony-wide calls per game sol, whatever the population |
| `budget.calls_per_min_max` | calls | 12 | real-time rate limit (token bucket) |
| `budget.max_in_flight` | calls | 2 | concurrent requests |
| `budget.tokens_day` | tokens | 300000 | per UTC day |
| `budget.tokens_month` | tokens | 5000000 | per UTC month |
| `budget.usd_day` | USD | 0.50 | per UTC day, enforced via prices |
| `budget.usd_month` | USD | 8.00 | per UTC month |
| `budget.reserve_frac` | fraction | 0.10 | calls stop when 90% of a cap is spent, so in-flight calls cannot overshoot |
| `budget.price_in_per_mtok`, `price_out_per_mtok` | USD per million tokens | 0.0 (unset) | **owner fills with the chosen model's published prices**; while either is 0 the driver refuses every call (fail closed) and the game plays on the rule mind. I do not invent prices |
Order of checks before each call (any fail means no call, silent fallback, counter `skipped_<reason>` in the driver): mode and key present; breaker closed (9); speed/deadline skip (8.2); per-colonist-sol; colony calls per sol; rate limit; in flight; day and month tokens and USD with the `reserve_frac` margin, charging the call's **worst case** (input estimate plus `max_out_tokens_per_being` times beings) as a reservation, reconciled to actuals on response.
Batching and the static prefix are the two big levers: with a batch of 4 and the static block shared, a call is about 350 + 4 x 180 = 1070 tokens in and 180 out (E) and so costs roughly 300 tokens per being, inside the 400 cap. At `calls_per_sol_max` 3 and batches of 4, up to 12 beings are voiced a sol; a larger colony voices a rotating subset, deepest-need first (the worth gate and the ascending-id order inside a window; the rest keep their rule lines). A one-hour play session at 1x is about 146 sols, so at most about 440 calls and about 470,000 tokens at the caps; the day token cap (300,000) therefore decides, which is the intended "tight" behavior: roughly the first 90 minutes of a day at 1x have live minds, then the rule mind. These are estimates for the owner to scale; the USD cap cannot be evaluated until the prices are filled.
### 8.2 Do not pay for answers that cannot arrive
Before sending, the driver compares real time to the deadline: it skips a request when `(deadline_step - world.step_index) x (real seconds per step at the current speed) < driver.latency_p50_s x driver.deadline_margin` (latency p50 is tracked from recent calls, start `driver.latency_p50_s` 1.5, margin 1.5; E), or when the current speed is above `driver.speed_gate_x` (5). So a fast-forward costs nothing and the model is live only where it can matter. A response that arrives after the deadline is dropped, was paid for, and is counted `late` (the meter charges it; the late rate is a tuning signal for `think_h` and the margin).
### 8.3 Caching
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
| valid JSON, unknown or stale choice | rejected in the sim (5.4), counter | no |
| line fails the filter or the `mismatch` check | line dropped, choice kept; or the whole entry dropped if the choice is also invalid | no |
| budget cap hit (any) | no calls; logged once in the driver file as a cap reached | no |
| breaker open | no calls for `driver.breaker_open_s` (120), then one probe call | no |
Retries: `driver.retries` 0 (the sim-time deadline makes a late retry pointless). Circuit breaker: `driver.breaker_fails` (3) consecutive failures open it. No exception may escape the driver into the sim loop; the driver pump is wrapped, and an internal error disables the driver for the session (mode `rules`) rather than crash. The driver never blocks the main thread: requests are asynchronous and polled between frames. Secrets: the key is read from the environment or a `user://` file, held only in driver memory, sent only in the request header, and redacted from every log; the repository holds no key and `.gitignore` covers the user files; a scan test fails on key-shaped strings anywhere in the repository (test 21).
Debug surface (never in a player build's HUD): `Minds.debug_stats()` and the driver meter, readable by tests, the probe and a developer overlay behind the existing debug toggle only.

## 10. Stats: `stats.minds` (sim side, deterministic given the ledger, never shown)
`slots_opened`, `slots_rule_only` (gate failed), `requests_built` (mode `llm`), `applied_model`, `applied_rule`, `bias_applied` (by kind: stay, roam, visit, quiet), `bias_skipped_asleep`, `slot_no_answer`, `rejected` (by reason: `bad_key`, `not_in_menu`, `stale_target`, `no_neighbour`, `bad_say`, `dead`), `apply_dropped_cap`, `say_rejected`, `says_model`, `says_rule`, `ledger_len`, `ledger_hash`. **Wall-clock facts (late, failed, tokens, cost, latency, breaker state) live in the driver meter, not in sim stats**, because live and replay runs must produce equal sim stats. A trailing balance column `mn` (printed `%d`, `applied_model`) follows `md`; the hash proofs strip it, as 6a stripped `md`.

## 11. Randomness and hash effect, per mechanic
**The minds module draws no random number from `SimRng` or from anything else in `sim/`.** Slot timing, the worth gate's calm sampling, rule-line variants and menu ordering are pure functions of ids, sols and state.
| Mechanic | SimRng draws | Writes outside the module | Effect on the reference hashes |
| --- | --- | --- | --- |
| Mode `off` (no module) | none | none | none: byte-identical (test 1) |
| Slots, facts, menu, rule line, `says` (mode `rules`) | none | `Minds` members, `stats.minds`, log: nothing | none: byte-identical to `off` (tests 2, 3) |
| Request building, outbox (mode `llm`) | none | outbox only | none |
| Applying a model decision (bias set) | none | `Being.mind_bias` | none until a bias is read |
| Bias read in `_restless_travel` | the same two draws at the same places; the argument and weights change | being behaviour | **changes hashes in mode `llm` only**, and only as a function of the ledger; reproducible by replay (tests 11 to 13) |
| Driver, provider, budget, filter | its own non-sim randomness (for example retry jitter) if any; never read by the sim | none | none: the sim sees only delivered entries |
Draw-count statement: inside one `_restless_travel` decision no draw is added, removed or reordered by a bias; downstream draw counts may differ in `llm` mode because outcomes differ, as with 6a effect 1. In `off` and `rules` they are identical to the baseline (test 3 compares the generator state after a 300-sol run). View code keeps its own RNG, and bubbles use no RNG (the speaker is the existing alternation).

## 12. Cost to the frame (E; measured by the probe; same discipline as 6a)
The 6a mood tick already runs over its budget on the padded pop-159 world, and `friends_of` costs 0.3 to 0.6 ms per call. So minds is built to touch few beings per tick: slots spread over 24 cells a sol and `sim.max_slots_per_tick` is 4, so a pop-160 colony opens at most 4 slots a tick (about 7 per cell expected, the rest carry over). Facts use the cached `top_friend_of` and a per-tick friend lookup shared with the mood module; `friends_of` is called at most `sim.friends_of_per_tick_max` 4 times a tick. Menu building reads only neighbour lists. Budget (E): minds tick median at most `balance.minds_tick_ms_max` 0.3 ms and max at most `balance.minds_tick_ms_peak_max` 1.0 ms at pop 159; the whole step at most +0.5% over the 6a-dormant step. Rule-line composition is a dictionary lookup. Memory: `says` and `due` are bounded by population; `ledger` grows with applied decisions (about 150 bytes each; at 12 sols and `calls_per_sol_max` 3 and batch 4, at most 12 a sol, so about 1.5 KB a sol; capped by `sim.ledger_max` 20000 with the oldest kept on disk only by the driver). If the probe shows a breach, the cut order is: shrink `max_slots_per_tick`, drop `near` from facts, lengthen `slot.grid_h`.

## 13. Calibration and balance guards (sim-test-engineer, after the code; five seeds at 300 sols and the 15 `r9_seeds`)
No gameplay number in 6b is calibrated against a live model; calibration uses the mock provider so it is repeatable.
- **G0 reference.** `off` and `rules` reproduce the pinned reference hashes on five seeds, each twice.
- **G1 adversarial worst case.** Mock providers that (a) always answer `stay`, (b) always `roam`, (c) always the first `visit`, (d) always an invalid choice, (e) never answer, (f) answer after the deadline. Each over five seeds, 300 sols, twice. Pass: no crash; (d), (e), (f) reproduce the `rules` hash exactly; (a) to (c) keep T1 to T12 passing as at the reference, and ice delivered per sol, thirst deaths and trips per sol stay within the noise band measured by the 6a method (a control run at a negligible `bias.*` against the dormant mean, 15 seeds), because a bias cannot reach survival branches.
- **G2 unattended decline stays gradual.** The adversarial runs must not make the colony decline faster or slower than the `rules` runs beyond that noise band (owner direction 2026-10-09).
- **G3 popularity loop.** The 6a company loop (K1 family): `visit` could concentrate bonds on already-befriended beings. Measure the zero-friend share and friend-count spread on the 15 seeds with adversarial `visit`; pass if no worse than the 6a noise band; the menu caps (`visit_max` 2, `apply_max_per_sol`) are the levers.
- **G4 cost shape.** With a mock that answers at a fixed latency and a long (1,500-sol) run at 1x, the meter reports tokens per colonist per sol and per day within the caps (no call ever charged past a cap).
- **G5 perf.** The minds tick budget of section 12 at pop 159.
A bias that fails G1(a to c) is halved once (`bias.*`), then dropped to 0 (the model path becomes text-only, said plainly to the owner).

## 14. Tests (`tests/test_minds.gd`, `tests/test_minds_driver.gd`, tests first and red; no network; no test with zero checks)
Sim (headless):
1. Mode `off`: five seeds, 300 sols, table hash with `mn` stripped equals the pinned reference constants (read from the existing hash-proof scripts, not copied), twice.
2. Mode `rules`: same five hashes, equal to `off`, twice.
3. Mode `rules` vs `off`: `SimRng` state after 300 sols equal (the next 5 draws equal), proving zero draws.
4. Slot schedule is pure: a staged world shows every non-baby being opens exactly `slot.per_sol` slots per sol, never more than `sim.max_slots_per_tick` a tick, carry-over in ascending id, babies never, dead never.
5. Facts: deterministic (two builds equal); required fields present; **no sign name, sign index, `deimos`, `moon`, `phobos`, `chart`** anywhere in keys or values for 200 generated beings.
6. Menu: `carry_on` first; at most `menu.max`; visit targets are living friends in neighbouring finished buildings; `roam`, `quiet`, `stay` appear only when valid; pure function.
7. Apply validation table (one case each): unknown key, key not in stored menu, stale visit target (moved, died, unfriended), no neighbour, dead being, bad `say` shape, `filtered` true; each is rejected, source `rule`, counter by reason, nothing in the ledger.
8. Bias effect on a staged being: `stay`, `roam`, `visit`, `quiet` produce the exact computed `p_travel` and weights (formula in 5.5); clamp at `travel_cap`; combined with a nonzero 6a mood term; the rng draw count of one decision is equal with and without a bias.
9. Bias scope: with a bias set, a being below `energy.sleep_below` still sleeps; a pending mine intent still resumes; a construction volunteer still joins; the bias expires at `ttl_h` and never extends.
10. `apply_max_per_sol`: more valid decisions than the cap in one sol apply exactly the cap, in (deadline, id) order; the rest count `apply_dropped_cap`.
11. Replay: run the world live with the scripted mock provider (random latency and failures from a test-local generator), save the ledger, build a fresh world in replay mode, run to the same step: table hash, `ledger_hash` and `SimRng` state equal.
12. Replay twice and live-then-replay: three byte-identical tables.
13. Sensitivity: change one early ledger `choice` on a staged world where the effect is certain: table hash differs.
14. Text-only change: replay with every `say` altered leaves the table hash and `ledger_hash` unchanged.
15. Late delivery: `deliver` after the deadline is dropped and not applied; a ledger without it replays equal.
16. Adversarial providers (a to f of G1) on a short staged colony: the stated equalities (d, e, f equal `rules`) and no exception.
17. Rule voice coverage: every situation has at least `rule.variants_min` templates; every template renders with no unresolved brace for a generated facts set; length, digits, chart terms, and `intent`-style promises checked; variant selection pure.
18. Filter table (at least 25 cases): good lines pass; each rule of 5.7 rejects its violator.
19. Source scan of `sim/`: no `HTTPRequest`, `HTTPClient`, `StreamPeer`, `PacketPeer`, `OS.get_environment`, `https://`, `http://`, `Authorization`, `api_key`, `FileAccess` on `user://`, provider or model names; the only `sim/` file besides `minds.gd`, `minds_voice.gd` that may mention `minds` is the data accessor in `sim_data.gd` and the hook sites in `world.gd` and `being.gd`.
20. Repository scan: no key-shaped strings; `.gitignore` covers `user://`-style files and `*.jsonl` ledgers outside `tests/fixtures/`.
21. Data parity: key-path list (section 15) equals the leaves of `data/minds.json`; no tunable literal in `sim/minds*.gd` (the existing literal scan with its allowlist).
22. `BeingPanel.lines` output byte-equal with minds on and off; `voice()` returns empty when stale and a string of at most `say.max_chars` otherwise; view source scan finds no ledger, inbox, outbox, provider, or `mind_bias` read.
Driver (headless, mocks):
23. Budget meter: each cap in section 8 refuses at its threshold; `reserve_frac` honored; worst-case reservation reconciled; prices unset refuses everything; persistence round trip across a simulated restart; UTC day and month rollover.
24. Breaker: opens at the third failure, half-open probe after `breaker_open_s`, closes on success; 401 disables for the session; 429 honors a capped Retry-After.
25. Failure matrix (timeout, 500, malformed, empty, bad choice, filtered line, partial batch): every case ends in the rule answer, no exception, and the view-model strings are equal to the no-failure `rules` run.
26. Prompt builder: static prefix byte-equal across calls; size estimate at or under the caps; the output-rules text present; no chart term anywhere in the built prompt for 200 beings; batch trimming drops fields in the stated order.
27. Parser: strict JSON, code fence accepted, extra fields ignored, unknown slot ignored, per-entry failure isolated.
28. Deadline skip: a request that cannot arrive in time at a fake speed is not sent and not charged; above `speed_gate_x` nothing is sent.
29. Mode resolution: `llm` without a key resolves to `rules` silently; with a key and prices resolves to `llm`; `off` builds no module.
30. Perf: minds tick median and max at padded pop 159 against section 12.
Hash columns: 31. `mn` is last and the existing proofs strip it.

## 15. Tunables (`data/minds.json` and `data/minds_text.json`; key paths; E)
```
mode.default                    "rules"
slot.per_sol                    1
slot.grid_h                     1.0      sim hours (equals relationships.tick_h; sanity rule)
slot.cell_mult                  7919
slot.cell_step                  5
sim.think_h                     12.0     sim hours from slot open to deadline
sim.max_slots_per_tick          4
sim.apply_max_per_sol           6
sim.outbox_max                  64
sim.ledger_max                  20000
sim.friends_of_per_tick_max     4
menu.max                        5
menu.visit_max                  2
bias.ttl_h                      8.0      sim hours
bias.stay_travel_mult           0.30
bias.roam_travel_add            0.20
bias.visit_weight_mult          4.0
bias.travel_cap                 0.60
gate.recent_sols                2.0
gate.calm_every_n_sols          4
facts.trait_lo                  0.35
facts.trait_hi                  0.65
facts.near_max                  3
facts.tired_below               35.0     energy points (above energy.sleep_below 28)
say.max_chars                   90
say.show_sols                   1.5
say.bubble_s                    4.0      real seconds
rule.variants_min               3
prompt.system_tokens_est        350
prompt.being_tokens_est         180
prompt.max_in_tokens            1500
prompt.max_out_tokens_per_being 70
driver.batch_size               4
driver.speed_gate_x             5
driver.latency_p50_s            1.5
driver.deadline_margin          1.5
driver.timeout_s                8.0
driver.retries                  0
driver.breaker_fails            3
driver.breaker_open_s           120
driver.retry_after_max_s        60
driver.cache_ttl_sol            2
budget.slots_calls_per_colonist_sol 1
budget.tokens_per_colonist_sol  400
budget.calls_per_sol_max        3
budget.calls_per_min_max        12
budget.max_in_flight            2
budget.tokens_day               300000
budget.tokens_month             5000000
budget.usd_day                  0.50
budget.usd_month                8.00
budget.reserve_frac             0.10
budget.price_in_per_mtok        0.0      unset: calls refused until the owner fills it
budget.price_out_per_mtok       0.0
balance.minds_tick_ms_max       0.3
balance.minds_tick_ms_peak_max  1.0
```
`data/minds_text.json`: `rule.situations.<name>[]` (templates), `words.traits`, `words.mood`, `words.why`, `words.place`, `words.clock`, `words.season`, `words.need`, `menu_labels`, `prompt.system`, `prompt.being`, `prompt.output_rules`, `filter.chart_terms`. Sanity rules: `slot.grid_h` equals `relationships.tick_h`; `sim.think_h` is a multiple of `world.fixed_step`; `bias.travel_cap` at least the largest baseline trait travel chance (0.40) plus `bias.roam_travel_add`; `rule.variants_min` at least 3; `budget.reserve_frac` between 0 and 0.5. No model name, URL or key is a data key in the repository file: the provider name, model and endpoint live in the user config (section 5.8), with a documented example `docs/minds-config.example` containing no secret.

## 16. Edits to existing code (complete list)
| File | Edit | Neutral at `off`/`rules`? |
| --- | --- | --- |
| `sim/minds.gd`, `sim/minds_voice.gd`, `data/minds.json`, `data/minds_text.json` | new | yes |
| `sim/sim_data.gd` | `minds()` accessor | yes |
| `sim/world.gd` | `minds`, `minds_mode`, `mind_enabled`, option read in `_init`, one hook after `moods.on_step`, `stats.minds` in `_init_stats` | yes |
| `sim/being.gd` | `mind_bias`, `mind_slot_n`; one guarded block in `_restless_travel` | yes: runs only when `mind_bias != null` |
| `minds/*.gd` | driver, prompt, provider interface and first adapter, budget, breaker, filter | outside the sim |
| `tests/balance_lib.gd` | `mn` column | stripped by proofs |
| `tests/mock_provider.gd`, `tests/test_minds*.gd`, `tests/minds_hash_proof.gd` | new | n/a |
| `view/model/being_panel.gd` | `voice()` | no change to `lines` |
| `view/world/*`, `view/main.gd` | speech bubble draw (text only) | view only |
| `docs`: HANDOFF section 9 layout, plan section 4(c) | record `minds/` and the superseded display-only default | docs |

## 17. Design review record
**Status: the three assistant reviews are pending.** I cannot start the assistants; the main session runs `designer-emergence`, `designer-feel` and `designer-clarity` on this spec and the findings go into this section, with my decision and any dissent beside each, as with emotions.md section 17. Nothing below is a review; it is the brief I give them and my own anticipated tensions, marked as mine.
**Questions for designer-emergence (Wright):** (1) Is "rule mind makes no behaviour change; AI is a nudge on top" too thin a possibility space, i.e. should the rule mind also have a behaviour channel (a deterministic personality policy that picks among the same menu)? I argue 6a mood already is that channel and a second one doubles the reset; challenge it. (2) Does a once-per-sol slot with a 12-hour lag make the minds feel like minds or like weather? (3) The `visit` menu entry risks the popularity loop; are the caps enough? (4) Should the model ever see the god's recent influence (the reserved `facts.god`) already in 6b so later powers have a place?
**Questions for designer-feel (Barone):** (1) Is a quoted line on the panel plus bubbles enough warmth, and are about 60 hand-written rule lines the right size for a small team? (2) Is the quiet 1x-to-5x liveness (nothing at fast-forward) acceptable, or does it make the AI feel like a lottery? (3) Would the player rather the model's lines be rarer and better (worth gate stricter) than frequent? (4) The silent fallback means a player cannot tell why the voices were brighter yesterday; keep the silence?
**Questions for designer-clarity (Korppoo):** (1) Is invisibility of mode (no indicator) acceptable given the owner's silent-failure decision, or does a quiet settings line ("minds: rule-based / cloud") belong in an options screen only? (2) The panel quote is outside the four-sentence contract; does it crowd the 6a success test? (3) Does the line-matches-choice rule give the player a reason to trust what a being says it will do? (4) The ledger and replay are developer-facing; should anything of it be player-facing (a "history" of what minds decided), or never?
**My own pre-read (the lead's reading of their published lenses, not their words):** Wright-lens tension: bounded menus narrow the surprise, but unbounded output is exactly what we cannot test; I choose bounded. Barone-lens tension: scope. A rule voice of about 60 lines plus one menu is a small, crafted thing; the cloud path is a layer that can be cut entirely and leave a finished game (section 19). Korppoo-lens tension: hidden mode and silent failure give the player nothing to reason about when behaviour shifts; I mitigate by making the line and the action agree and by never changing survival behaviour, so a nudge never explains a colony crisis.
Dissent and decisions will be added here after the reviews. If the reviews disagree with a recommendation above, the lead's reasoning and the dissent are both recorded and the owner is asked only where it is genuinely theirs.

## 18. Questions for the owner (those I cannot decide)
- **Q-A. Default mode.** Recommended: ship with `rules` as the default and `llm` as opt-in by config until a provider, a key and prices exist (nothing breaks for a player with no key). Option: default `llm` whenever a key is present.
- **Q-B. The chart in the prompt.** Recommended: effects in words plus the public sky, no placements (section 6.2). Option: raw placements with a blocklist filter (richer voices, a chance the model prints the hidden chart).
- **Q-C. Meaning of "day" and "month" in the budget.** I read them as real UTC day and month. Confirm, or say if you meant game time (a "month" of game sols).
- **Q-D. Which provider and model, and what the prices are.** The spec is provider-neutral. `budget.price_*` stay 0.0 and refuse all calls until you fill them. Which small, cheap model tier do you want first?
- **Q-E. Who pays, and how does the key reach a player?** A key embedded in a distributed game is a leaked key. For your own play an environment variable is enough. For anyone else you need a small proxy or each player's own key; a proxy is server work that belongs with 6d (Q6). Decide now only whether 6b is "owner-only, local key" (recommended).
- **Q-F. Speed.** Live minds work at about 1x to 5x only (section THE DETERMINISM PROBLEM, cost (a)). Accept, or prefer the barrier option (the game pauses briefly at deadlines).
- **Q-G.** A small options-screen line showing which mode is active (no HUD, no log). Default: none, per your silent rule.

## 19. Scope cuts (cut order, first cut first)
1. The `mismatch` soft check (7.4). 2. Driver cache. 3. `quiet` and `visit` menu entries (leaving `carry_on`, `stay`, `roam`). 4. Panel quote (keep bubbles). 5. The whole model path (leave the rule voice: a finished 6b with no network, which satisfies "built first"). The rule voice and the ledger test scaffolding do not get cut.

## Changelog
- Revision 1 (2026-10-10): first draft. Assistant reviews pending.
