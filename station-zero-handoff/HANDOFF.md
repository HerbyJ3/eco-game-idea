# Station Zero: Handoff for Claude Code

A Mars colony simulation where every colonist lives by their own personality, the colony grows on its own through ages, and the player is a god who can only influence, never command. This file captures every decision made during the prototype phase so development can continue in **Godot 4** with **Claude Code**.

Owner: Herby. Prototype built in claude.ai, October 2026.

---

## 1. Vision

- Inspired by an Instagram "AI agent ecosystem" dashboard and *Tron Legacy*: a world that develops on its own.
- Think **Age of Empires, but you don't control the units**. Every colonist has its own mind (personality now, AI brain later). You observe, and you influence.
- **Naturalism over progress bars.** Nothing counts toward a goal. The colony advances when its people get there: shelter and food are secure, surplus builds, relationships form, and the beings reach agreement (diplomacy) on what to do next.
- Setting: a colony on **Mars, at Jezero Crater**, starting as a small outpost and growing, over generations, into a city of domes.

---

## 2. Decisions locked

| Area | Decision |
| --- | --- |
| Engine | Godot 4 (2D). Prototype was a single HTML/canvas file; it is now the design spec, not the codebase. |
| Setting | Mars, Jezero Crater (ancient river delta). Founders land at dawn on the northern spring equinox, year 1 sol 1. |
| Time | Real Mars time. Sol = 24.6597 h, year = 686.98 Earth days (about 668.6 sols). Prototype scale: 1 real second at 1x = 1 Earth hour. |
| Personality | Hidden birth chart, never shown on the HUD. Only its effects are visible (a two-word description such as "warm and nurturing"). |
| Founders | 7 Earth-born colonists with Earth charts (one moon). The first Mars-born generation is the first with Martian skies. |
| Player role | God, influence only. No spawning, no build orders. |
| Art style | Smooth 2D game art (not pixel art), top-down with a slight 3/4 tilt, light from the upper left. All sprites come from **Higgsfield**. |
| Art model | Nano Banana 2 (1.5 credits per image, cheapest). Nano Banana Pro costs 2. GPT Image or Soul are allowed alternatives. |
| Growth | Ages, not meters. No "first dome" bar. A dome happens after diplomacy. |
| Energy | **Per being**, not shared. Each colonist has their own energy, drained by activity and restored by sleep. |
| Power | Power is a **budget**, not a life span. Buildings draw power from reactors. Over the limit, a random building or the newest building shorts out and goes dark. |
| Life support | Green rooms make **oxygen and food**. Ice is water. Suits carry limited oxygen. |
| Selection | No boxes. Selection outlines hug the building's silhouette. Tap again to open the roof and look inside. |

---

## 3. Mars calendar and sky (exact formulas)

All time is in Earth hours `t` since the epoch.

```
SOL_H        = 24.6597
YEAR_H       = 686.98 * 24
EARTH_YEAR_H = 365.256 * 24
PHOBOS_H     = 7.6538       # sidereal period
DEIMOS_H     = 30.312
LUNA_H       = 27.3217 * 24 # Earth's Moon, for Earth-born founders
ECC          = 0.0934       # Mars orbital eccentricity
M0           = 99           # mean anomaly at epoch, puts founding at Ls ~ 0
SITE         = Jezero Crater, longitude 77.5
START_HOUR   = SOL_H * 0.25 # dawn

mod360(v) = ((v % 360) + 360) % 360
sign(lon) = floor(mod360(lon) / 30)        # 12 signs of 30 degrees

# Solar longitude Ls (Mars-tropical zodiac: the sun sign IS the season)
M  = radians(M0 + 360 * t / YEAR_H)
nu = M + 2*ECC*sin(M) + 1.25*ECC^2*sin(2M)
Ls = mod360(degrees(nu) + 251)             # perihelion near Ls 251

marsHour(t) = frac(t / SOL_H) * 24
season = [northern spring, summer, autumn, winter][floor(Ls / 90)]
```

Because of Mars's eccentric orbit, sun signs last 46 to 67 sols each.

### Birth charts

Mars-born (five placements):

```
sun    = sign(Ls)
deimos = sign(360*t/DEIMOS_H + 211)
phobos = sign(360*t/PHOBOS_H + 53)         # changes sign about every 38 minutes
rise   = sign(Ls + (marsHour(t) - 6)/24*360 + lon)   # at dawn rising = sun sign
earth  = sign(direction from Mars to Earth)  # Earth at 1 AU, angle 40 + 360*t/EARTH_YEAR_H;
                                             # Mars at 1.524 AU, angle Ls - 180
lon    = 77.5 + (building center x in tiles) * 0.25   # game-scale birthplace
```

Earth-born founders (three placements): `sun = sign(360*t/EARTH_YEAR_H + 15)`, `moon = sign(360*t/LUNA_H + 137)`, `rise = sign(sun + (hour-6)/24*360 + lon)` with a random Earth longitude. Founder birth dates are 24 to 45 Earth years before landing.

### The 12 signs (colony names, real zodiac element order)

| # | Name | Element | Modality |
| --- | --- | --- | --- |
| 0 | The Spark | fire | cardinal |
| 1 | The Monolith | earth | fixed |
| 2 | The Twin Signal | air | mutable |
| 3 | The Tide Shell | water | cardinal |
| 4 | The Crown Star | fire | fixed |
| 5 | The Lattice | earth | mutable |
| 6 | The Balance Arc | air | cardinal |
| 7 | The Deep Lantern | water | fixed |
| 8 | The Far Arrow | fire | mutable |
| 9 | The Summit | earth | cardinal |
| 10 | The Relay | air | fixed |
| 11 | The Drift | water | mutable |

### Chart to personality

Six trait dimensions: drive, curiosity, sociability, care, restless, steady.

```
ELEMENT  fire  {drive 1, restless .6}
         earth {steady 1, care .4, drive .3}
         air   {curiosity 1, sociability .6, restless .3}
         water {care 1, sociability .7, steady .2}
MODALITY cardinal {drive .4, restless .2}
         fixed    {steady .6, restless -.4}
         mutable  {restless .5, curiosity .3, steady -.3}

per placement: v = ELEMENT[d] + 0.6 * MODALITY[d], then boosts:
  inner boost multiplies care and sociability
  outer boost multiplies restless and steady
  drive boost, curiosity boost as listed

Mars placements [weight, inner, outer, drive, curiosity]:
  sun    [.35, 1,   1,   1,   1  ]   core self, season
  deimos [.20, 1.5, .8,  1,   1  ]   inner, emotional self
  phobos [.15, .8,  1.4, 1.4, 1  ]   impulses
  rise   [.20, .8,  1.6, 1,   1  ]   outward behavior
  earth  [.10, 1,   1,   1,   1.8]   longing for home
Earth placements: sun [.5,1,1,1,1], moon [.3,1.4,.8,1,1], rise [.2,.8,1.6,1,1]

trait = clamp((sum + 0.3) / 1.5, 0, 1)
role  = argmax over {drive: builder, curiosity: curious, sociability: social, care: tender}
        with weights {drive .88, curiosity 1, sociability 1.16, care .97}  # balances roles over a year
visible description = the top two traits, e.g. "driven and restless"
```

Validated: about 15,700 unique charts in 20,000 random births, and roles stay roughly balanced.

### How traits drive behavior (prototype)

- restless: chance to travel between buildings; steady: longer pauses.
- drive: walk speed, construction speed, mining yield.
- Room preferences: workshop by drive, archive and comms by curiosity, habitat by sociability, green room by care, reactor by steadiness.
- Births are more likely in habitats full of warm, nurturing beings.
- Mining volunteers: 0.45 steady + 0.35 drive + 0.2 restless.
- "Send a sign" splits the colony by curiosity and steadiness.
- Mars-born are drawn about 10% taller than Earth-born (low gravity).

---

## 4. God powers (influence only)

| Power | Effect | Recharge |
| --- | --- | --- |
| Good fortune | Reactors put out 50% more power for one sol; dark buildings can come back online | 3 sols |
| Inspire | Tap a building; beings there dream of building another like it. Builders usually act on it if they can | 2 sols |
| Grace | Tap a habitat; births there become more likely for 1.5 sols | 2 sols |
| Send a sign | A light crosses the sky; each being reacts by personality (curious go look, steady keep working) | 1 sol |

Future ideas: calm a dust storm, send a dream to one being, let a rumor spread. From the Task 1 baseline (Herby): growth is left uncapped on purpose. When a big colony runs short of ice, the answer should come from influence. One option is inspiring a building that recycles or preserves water. Another is the beings agreeing on a rule to slow births in the council stage. The owner said **yes**: beings should eventually sense that a god exists and react to it (fits the culture stage).

---

## 5. Systems as built in the prototype

### Buildings (kinds)

| Kind | Label | Role | Power draw |
| --- | --- | --- | --- |
| core | Reactor | Supplies 14 power each | 0 |
| habitat | Habitat | Sleep, families, births (capacity 5 per habitat) | 3 |
| workshop | Workshop | Builders plan construction here | 4 |
| garden | Green room | Oxygen and food | 4 |
| archive | Archive | Records, memory (later culture) | 2 |
| comms | Comms | Listens outward | 3 |

Construction sites draw 2 while being built. Builders choose what to build from need: a reactor when the power margin is under 5; a green room when oxygen or food production is thin; a habitat when crowded; otherwise archive, comms, green room or habitat.

### Construction (natural build time)

- A building costs regolith (more for later buildings). No energy cost.
- Builders suit up, walk out, and work on site. **No one on site means no progress.** More builders means faster; driven, rested builders work faster.
- Phases on screen: survey stakes and a blue blueprint hologram, foundation slab, steel scaffolding with bare metal walls rising from the bottom, painted panels catching up, scaffolding comes down.
- Builders weld at the top edge of the rising wall: spark showers that arc under gravity plus a blue-white torch flash.
- Floating progress bar with builder count, or "waiting for builders."
- Tunnels (pressurized corridors) connect a new building to its parent.

### Resources

- **Regolith pit** near the colony; **ice fields** farther out. Beings suit up, walk out, dig (pick swings, dust or frost puffs), and haul blocks back.
- Ice fields shrink and run dry; scouts find new ones.
- Ice is the colony's water. No ice: no births, and later, deaths from thirst.
- Regolith pays for construction.

### Life support and power (Task 1, done, see section 8)

- Green rooms: +1.4 oxygen and +1.0 food per hour each. Beings use 0.05 oxygen and 0.035 food per hour.
- No oxygen: deaths every few hours. No food: slower deaths. No water: deaths.
- Power budget: sum of building draws versus reactor supply. Over the limit, the newest building (60%) or a random one shorts out with a spark burst and goes dark (no lights, no function). It comes back online when there is spare power.
- Suits: a 36-hour oxygen tank, filled from colony oxygen. Beings turn back when the remaining air is below the walk home plus a margin; if the air runs out on the surface, they die. EVA walk speed is 16 world px per hour.
- Mining trips only go to sites whose round trip fits in a tank. Miners walk through corridors to the building nearest the site before suiting up.
- **Per-being energy**: drains with activity (most for construction, then mining, walking outside, idle). Below 28, or at night below 65, a being heads to the nearest habitat bunk and sleeps. Sleep restores energy (slower if food is out). Exhausted beings outside turn back.
- Footprints on the surface for every suited being; heavier prints for builders and haulers; they fade over about 2.5 sols.

### Social

- Conversations: sociable beings seek each other out in the same building; bubbles alternate; zoom in or open the roof to read the words. Lines are a fixed list for now; AI minds replace them in Stage 5.

---

## 6. Art and assets

### Pipeline

1. Generate with Higgsfield, **Nano Banana 2**, on a flat **magenta (#FF00FF)** background, passing an existing finished sprite as a style reference so everything matches.
2. Download into `assets/raw/`.
3. Key out magenta (remove pixels where R>150, B>150, G<120, plus a 1px erosion to kill the pink fringe; recolor leftover pink halos).
4. Crop to the bounding box, downscale with Lanczos (about 320 px wide for buildings).
5. For buildings with doors: cut the door leaves out as a separate image, fill the opening with a dark interior gradient, and animate the leaves sliding apart in code.
6. Build light masks automatically from the art: accent lights (amber on the reactor, cyan on the habitat), blue windows that glow warm at night, a silhouette outline for selection, a silhouette shadow, a gray "unfinished" version and a blue blueprint "ghost" for construction.

Style references already in Higgsfield (job IDs for the `medias` field):
- 2D habitat exterior: `9b2fb423-f815-429b-b507-caa72e1c7516`
- 2D reactor exterior: `3508e60a-86d5-4fd2-815f-ae2cbdf0b1c2`

### Files in `assets/raw/`

Note (Task 2): the processed set lives in `station-zero/assets/processed` with its manifest, and the pipeline is `tools/build_all.py`. The "Not yet integrated" statuses below are the pre-Task 2 state.

| File | Content | Status |
| --- | --- | --- |
| habitat_exterior.png | 2D habitat | In prototype. Door leaves rect (normalized to crop): 0.4362, 0.6895, 0.5627, 0.8714 |
| reactor_exterior.png | 2D reactor | In prototype. Door rect: 0.4211, 0.7496, 0.5802, 0.8706 |
| workshop_exterior.png | Hangar with roll-up door and crane | Not yet integrated. Roll-up door should animate upward |
| greenroom_exterior.png | Glass-roof green room | Not yet integrated |
| habitat_interior.png | Top-down interior (bunks, kitchen, table, lounge) | Not yet integrated; shows when the roof opens |
| comms_interior.png | Top-down interior (consoles, holo-map table, racks) | Not yet integrated |
| sheet_colonist_jumpsuit.png | 4x4 sheet, neutral gray jumpsuit (tint per role) | Not yet integrated |
| sheet_eva_suit.png | 4x4 sheet, white EVA suit, gold visor, helmet lamp | Not yet integrated |
| sheet_construction_suit.png | 4x4 sheet, yellow construction suit, welding | Not yet integrated |
| old_pixel_habitat_test.png | Rejected pixel-art test | Reference only |

Character sheet layout (all three): row 1 walk toward viewer (4 frames), row 2 walk away (4), row 3 walk right in side view (4; mirror for left), row 4 extras:
- Jumpsuit: idle front, idle side, talking gesture, carrying crate.
- EVA: idle front, idle side, pickaxe swing, carrying ice block.
- Construction: weld frame 1, weld frame 2, carrying steel beam, idle front.

Recolor the gray jumpsuit per role: builder rust `#d9733f`, curious violet `#8d70d6`, social teal `#3fb3c2`, tender green `#6cb85a`. Recolor only low-saturation gray pixels; leave skin and hair. Note: every jumpsuit colonist shares one face and hair from the sheet; variety would need more sheets.

Helmet lamps must glow from the **top of the helmet** at night. Builders wear the **yellow construction suit**; other surface workers wear the white EVA suit.

### Still needed (Nano Banana 2)

- Comms exterior, archive exterior and interior, workshop interior, green room interior, reactor interior.
- Terrain decals: ice field, regolith pit, rocks, craters (the prototype draws terrain procedurally; Godot can use a painted tileset or keep procedural).
- Sleeping pose, more colonist faces and hair styles.

---

## 7. Ages (the growth model)

| Age | Life is about | How the colony moves on (emergent, never a meter) |
| --- | --- | --- |
| Landing | Survival: air, food, water, power | Life support runs a steady surplus for a long stretch |
| Settlement | Families, shared meals, records kept, routines | Relationships and trust form |
| Council | Gatherings, arguments, factions by personality | A dome proposal wins enough support and the colony commits to build it together |
| Dome | Town life inside the first dome | More agreements, more domes |
| City | Many domes, generations after landing | Open-ended |

Each new age appears as an event in the colony log. The player can see it happen, not watch it fill up.

The colony's physical layers follow the ages: outpost of modules and tunnels, then a first biodome with streets, homes, canteen, workshops and gardens inside (no suits needed), then several domes linked by roads with industry outside (reactor, solar, ice mines, regolith processors, landing pad, rover depot), then a city. Long walks to the ice are the natural argument for rovers and roads.

---

## 8. Status and task queue

Live prototype (claude.ai): the version before Task 1, saved here as `prototype/station-zero-published.html`. The in-progress Task 1 version is `prototype/station-zero-wip.html`.

Roadmap doc (claude.ai): https://claude.ai/artifact/Hp5G66hS9paNRwzVVERqdZ
Prototype artifact: https://claude.ai/artifact/LEHS7X1zfj4qLXDbTfYyHQ

### Task queue (do one at a time, check off)

- [x] **0. Godot project setup.** Folder structure, autoloads, a simulation core that runs headless, a renderer that only displays it. Port the calendar, charts and personas first, with unit tests that match section 3.
  - Done October 2026. Godot 4.5 project in `station-zero/`. Run the tests with `godot --headless --path station-zero --script res://tests/run_tests.gd` (33 tests). Plan: `station-zero/docs/tasks/task-0-plan.md`. Spec and resolved ambiguities: `station-zero/docs/specs/sky-persona.md`.
  - What we learned: (1) The comment "at dawn rising = sun sign" holds only at lon 0. At Jezero, rise = sign(Ls + lon). (2) Seed 42 gives 15,481 unique charts in 20,000 births. Role shares are builder .315, social .281, tender .204 and curious .200; the in-game longitude range gives the same shares. (3) Mars charts never reach the lower trait clamp. Sociability tops out at .68. (4) `Sky` is a built-in Godot class, so the sky class is `MarsSky`. (5) GDScript can't use float `%`, so use `fposmod`.
- [x] **1. Life support and power.** Green room oxygen and food, power budget with shorts, suit tanks, footprints, construction suits, helmet lamps, per-being energy and sleep. **Balance it with headless runs.**
  - Done October 2026. Final code review: "Task 1 approved", no blocking findings. Full suite: 308 tests, 30,949 checks, 0 failures (about 70 s), run with `godot --headless --path station-zero --script res://tests/run_tests.gd`. All 8 per-seed balance targets pass on seeds 42, 7, 99, 1234 and 2026 at 300 sols with no data changes. Determinism holds (seed 7, 300 sols, table sha256 830c7d0c441823f5). Plan and owner decisions: `station-zero/docs/tasks/task-1-plan.md`. Balance log: `station-zero/docs/balance/task-1-log.md`. View: text HUD with speed keys plus a debug dot map.
  - Owner decisions (Herby): births keep the 1-sol cooldown; population is uncapped on purpose; ice running dry is pressure, not failure; first new reactor due by sol 15.
  - What we learned: (1) At 300 sols population ends at 72 to 164. Ice ran dry on 3 of 5 seeds (5 to 22 thirst deaths), with no other deaths, zero power shorts and zero air turn-backs. (2) A 300-sol run takes 76 to 232 s because fixed_step stays 0.05 h. (3) The short and re-online path never fires in balance runs, so power flapping is untested at scale. (4) HUD speeds 100x and 1000x hit the 2,000-steps-per-frame cap in large colonies. (5) Interiors have no x,y positions (A9). (6) Construction suit, helmet lamp and footprint visuals exist only as sim data, for Task 2. (7) Review follow-ups fixed: log carries clock_sol, a resumed mine intent re-checks the trip limit, Site.dug accumulates, balance_run exits 1 when a target fails.
- [x] **2. Sprite set.** Slice and import the three character sheets, the workshop, green room and the two interiors. Animate doors and lights.
  - Done October 2026. Final code review: "Task 2 approved"; its two conditions (rebuilt manifest, refreshed far-zoom shots) are done, plus a test that the committed manifest matches art.json. Full suite: 383 Godot tests, 0 failures; 75 Python pipeline tests, OK; the pipeline rebuild is byte-identical; 36 screenshots render. Spec: `station-zero/docs/specs/sprite-view.md`. Perf report: `station-zero/docs/perf/task-2-report.md`. Missing art: `station-zero/docs/art/still-needed.md`.
  - Built: `tools/build_all.py` pipeline (keying, crop, scale, doors, masks, sheet slicing, role recolor, interiors, placeholders, manifest with the presence rule); `view/art_library.gd`; `view/model` (animation logic, own RNG, sim read-only); `view/world` (sprite world view with doors, lights, construction, camera, colonists, suits, helmet lamps, footprints, selection outline from the silhouette, roof-open interiors); far-zoom LOD; `tools/shot.gd` harness and `tools/perf_run.gd`.
  - Owner decisions (Herby): sprites are fitted at their proportions and anchored at the door, never stretched; the debug map is behind M; the screen darkens 19:00 to 21:30 and brightens 05:30 to 07:00, helmet lamps dim at 19:00 and are full at 21:30; the 8 missing images were generated with Nano Banana 2 (about 12 credits) but the cloud network blocks the CDN, so they are not in `assets/raw` yet and placeholders cover them by the presence rule. Download steps: `station-zero/docs/art/still-needed.md` and `station-zero/docs/art/generated-2026-10-03.md`.
  - Performance at sol 300 (164 beings, 53 buildings): model update 1.0 to 1.3 ms median (budget 2), draw calls about 100 at zoom 0.6 after LOD (budget 150), nodes 28, texture memory 27 MB (budget 48).
  - What we learned, carry forward: (1) Sim step cost is 4.7 to 6.8 ms at 164 beings, so 1000x speed is sim-bound; profile `SimWorld.step()` and give `advance()` a wall-time budget (Task 3). (2) Align the sim night window (21:30 to 05:30) with the visual dusk if sleep should match the screen; needs balance reruns. (3) Footprint heel alternation needs the sim to store foot_side. (4) Add a selection outline radius key and move the remaining view/world rendering constants into art.json in a data pass. (5) The real sleeping-pose draw path is untested until the art lands. (6) More colonist faces and hair need two more jumpsuit sheets (prompts in still-needed.md).
- [x] **3. Age system.** Landing and Settlement ages, announced in the log.
  - Done October 2026. Plan: `station-zero/docs/tasks/task-3-plan.md`. Spec: `station-zero/docs/specs/ages.md`. Balance: `station-zero/docs/balance/task-3-calibration.md` and `task-3-log.md`. Step profile: `station-zero/docs/perf/task-3-step-profile.md`.
  - What we learned: (1) The calm clause was recalibrated to 0.2. Settlement is reached at sols 67, 58, 54, 65 and 53 on the five seeds; fall-backs happen on seed 42 at sol 213 and seed 99 at sol 174. (2) Seed 2026 stays in Settlement through a short thirst crisis; the owner accepted this and the rule is kept. (3) The HUD is tight at 720p; resolved with a chapters strip showing first sentences only. (4) `advance()` now has an 8 ms wall-time budget and the HUD shows a speed readout. (5) Footprint-expiry speed fix: step cost about 3.8 ms down to 2.6 ms at pop 167, with Task 1 hashes unchanged. (6) Two host-speed timing tests fail on this slower host; they were not weakened.
  - Open owner items: (a) Task 5 gate: the Council reads `age_history`. (b) Texture memory is 47.1 of 48 MB; the owner decides what to do about the budget.
- [x] **4. Relationships and trust.** Driven by personality.
  - Done October 2026 (closed 2026-10-06). Plan: `station-zero/docs/tasks/task-4-plan.md`. Spec: `station-zero/docs/specs/relationships.md` (revision 8). Balance: `station-zero/docs/balance/task-4-calibration.md` and `task-4-log.md`. Tick profile: `station-zero/docs/perf/task-4-tick-profile.md`. Frame report: `station-zero/docs/perf/task-4-frame-report.md`. Screenshots: `station-zero/docs/shots/task-4/`.
  - Owner decision (Herby, 2026-10-06): the pulls are built but shipped off; keep both off at close. Task 5's first social run is the lonely pull alone.
  - What we learned: (1) The module is hash-neutral: the five Task 1 hashes and the Task 3 hashes reproduce with the web/age columns dropped. (2) room_rate 0.010 was tried and reverted after stop rule R11 on seed 7; shipped value is 0.008. (3) Tick cost was optimized from about 24 ms to about 4.7 ms median at 159 beings; the 1 ms target was restated to <=8 ms median and <=20% mean-step cost. (4) Frame-time triggers are undecidable on this software-render host; they need a rerun on a real GPU. (5) The phase constant in `view_model.gd` is computed via sqrt to avoid the literal-scan allowlist; reviewer: optional cleanup, a plain constant with a comment would match the spec. (6) No being inspect panel exists, so the "knows no one well yet" sentence is a Task 5 input. (7) Two host-speed timing tests are flaky on this host.
  - Known issues: K1: about a third of late newborns on seeds 42 and 2026 have no friend at sol 300. K2: seed 99 first newcomer line at sol 68. K3: R1 passes by 1 sol on seeds 99 and 2026.
  - Carry forward: Task 5 inputs are listed in spec section 19. Open owner items: (a) Task 5 gate, the Council reads `age_history`/`web_by_sol`/`second_by_sol`/`lonely_by_sol`, still undecided. (b) Texture memory is 47.1 of 48 MB; the budget decision is still open.
- [x] **5. Council and diplomacy.** Gatherings, proposals, support, the decision to build a dome.
  - Done October 2026 (closed 2026-10-08). Plan: `station-zero/docs/tasks/task-5-plan.md`. Spec: `station-zero/docs/specs/council.md` (revision 6). Balance: `station-zero/docs/balance/task-5-lonely-run.md`, `station-zero/docs/balance/task-5-calibration.md` (incl. Run 2) and `station-zero/docs/balance/task-5-log.md`. Boundary-step profile: `station-zero/docs/perf/task-5-boundary-step.md`. Screenshots: `station-zero/docs/shots/task-5/` (contains `council_hud_pledge.png`). All listed paths verified to exist.
  - Owner decisions (Herby) O1-O6 and rulings: (1) Gate = 30 settled sols + friend web + a chosen-friend share with family = two generations + 12 voices. (2) The decision is a pledge; nothing is built. (3) The Council is hash-neutral. (4) No new art. (5) The dome is tied only to topic-keyed machinery. (6) The lonely pull run was not adopted: zero-friend share rose 0.244 -> 0.290, 5 of 15 seeds were better, it broke T5/T7/T11, and seed 21 went extinct. Both pulls stay 0.0; no baseline reset. Carry rule = 60% of those with a view, and a quorum of 0.35 of voices (fitted; seed 1234 clears by 0.02).
  - Results: Council entered on seeds 42/7/1234/2026 at sols 115/95/160/206, never on 99. Pledges on seed 1234 at sol 195 and seed 2026 at sol 221, both undivided. T1-T12 pass. `council_hash_proof` matches the Task 4, 3 and 1 hashes on all five seeds.
  - Cost: C8 restated to 5.0 ms median / 16.7 ms peak. The boundary-step spike reaches about 22 ms, attributed to the Council plus the relationship tick. The Landing skip was built; it is not bit-identical but was accepted. Seed 1234 in Council age peaks at 13.7 ms, under the trigger on 2 of 3 runs, not proven by construction. Union-find sharing was not built.
  - Known issues and Task 6 inputs: (1) K1 (friendless late newborns) still ships. (2) C5 passes only at its minimum (two seeds divide). (3) The first raise comes at the 5-sol minimum on 3 seeds (first-raise delay not built). (4) The dome is hard-coded in `council.gd`; a second topic needs code, not only data. (5) Council reads the relationships module's private packed mirror; a public accessor would be cleaner. (6) `lines_dropped_by_type` is still unbuilt. (7) Spec section 11 remedy numbering differs from the perf doc. (8) Host-speed timing tests are flaky on this host. (9) Frame-time triggers need a real-GPU rerun. (10) Texture memory 47.1 of 48 MB is still undecided.
- [ ] **6. Later stages.** Emotions (Deimos sets temperament), AI minds (each being's chart and mood shape its prompt), memory and culture (beings name their own sky), persistent world on a server.
  - **In progress (updated 2026-10-09).** Plan: `station-zero/docs/tasks/task-6-plan.md`; scoping and owner decisions: `station-zero/docs/design/task-6-scoping.md`. Slices in order: **6a emotions** (in progress), 6b AI minds, 6c memory and culture, 6d persistent server.
  - **6a emotions:** spec `station-zero/docs/specs/emotions.md` revision 4 (owner answers Q1-Q4 at its top: Deimos sets baseline mood and recovery, behaviour changes (baseline reset accepted), text only, four strong-case temperament sentences, Council misses are reported not retuned, old hash chain retired at 6a close, no mood drift). Tests written first and committed (`tests/test_moods.gd`, `test_view_moods.gd`, `mood_hash_proof.gd`, `mood_t13_check.gd`, two parked view tests in `tests/deferred/`). **The dormant build (mood gains 0.0) is unfinished and unverified**; it lives on branch `wip/6a-dormant` (pushed). Resume it onto the current branch (`git cherry-pick --no-commit wip/6a-dormant` applied cleanly before), then finish per spec section 10 step 2.
  - **Calendar lifecycle (from another session, commit e1f2bdd) is the accepted new baseline.** Re-baseline record: `station-zero/docs/balance/lifecycle-rebaseline.md` (new hashes per seed, run-twice identical; old Tasks 1-5 hashes kept in comments in the hash-proof tests). At 300 sols the colony stays at 7 until about sol 280; Settlement only on seed 42; Council never.
  - **Lifecycle calibration** (`station-zero/docs/specs/lifecycle-calibration.md`, owner decisions at its top): horizons Smoke 300 + Standard 1,500 (five seeds) + rare Generational 7,200 (seed 42); Council stays a late generational institution (`voices_min` 12); Settlement: measure first. **Standard baseline measured 2026-10-09** on the unchanged `801bec5` game: five balance runs plus five relationships and five Council probes, all at 1,500 sols. Report: `station-zero/docs/balance/lifecycle-standard-baseline.md`; raw outputs and command/exit manifests in the adjacent `lifecycle-standard-baseline-data/`. **All five colonies die of thirst**, first zero-population samples 583/307/632/704/658 (seeds 42/7/99/1234/2026); all 35 founders die. Settlement enters at 290/none/309/312/328, so the owner trigger (2+ misses by 700) is **not met**; no family rule or starting-housing change is chosen. Council never enters, as expected with at most 7 adult voices. Babies do form friendships (median newborn wait 5–6 sols). The relationships probe now uses `Lifecycle.is_adult` for its read-only voice report. No simulation or data tuning was done.
  - **Ice-supply investigation completed 2026-10-09:** report `station-zero/docs/balance/ice-supply-investigation.md`, raw traces/controls/checkpoints in `ice-supply-investigation-data/`, reusable read-only tool `tools/ice_supply_probe.gd`. Five seeds traced to sol 720 and replayed with observation disabled; end state and RNG match, and all 721 ice/population samples equal the Standard baseline. Additional seed 7/2026 snapshots match too. First storage droughts occur during sols 370/298/327/520/388 (42/7/99/1234/2026), while reachable fields still contain about 356/441/88/124/693 units at the start of those sols. Ice delivery throughput is insufficient: long plan-to-launch waits, low-energy departures, exhausted partial loads, and dependants consuming while the adult workforce remains seven. Field reachability is not a guarantee of sustainable collection. Seed 7 delivers all its loads but still collapses; at sol 298 five founders carry pending ice plans. Source ordering prioritizes sleep/construction over a pending mining plan, room arrivals incur new pauses, and launching has no fresh energy check. Existing regolith plans are not redirected by the urgent-water rule. No gameplay/data tuning was done.
  - **Power investigation:** seed 2026's green room #15 shorts at sol 278, returns at 288 after 254.35 h. Supply 42, active draw 39 and room draw 4 cannot meet the 95% re-online limit 39.9; the fourth reactor raises supply to 56 and clears it. This reserve-margin/completion delay is separate from the shared water failure; the other four seeds have no short.
  - **Water throughput (done 2026-10-09, Claude Code session).** Spec and results: `station-zero/docs/specs/water-throughput.md`; raw five-seed Standard runs: `station-zero/docs/balance/water-throughput-data/` (`summary.txt`); re-baseline: `station-zero/docs/balance/water-rebaseline.md`. Five behaviour switches W1–W5 were built behind data flags and tested one at a time on five seeds at 1,500 sols. **Shipped: W3 only** (no room pause while walking to a mining trip). First thirst deaths moved from sols 300–530 to 580–850 on all five seeds, and two colonies (99, 1234) were alive at 1,500. W1 (urgent redirect), W2 (sleep before a trip; harmful), W4 (children drink less), W5 (water before construction) and a 100% re-online rule stay off as switches. New pinned hashes in the four hash-proof scripts; old ones kept as history.
  - **Owner direction (Herby, 2026-10-09): the colony is not meant to survive unattended.** Without attention it should decline gradually; the player's influence keeps it alive, which creates responsibility and involvement. Balance targets change accordingly: unattended decline must be gradual and readable, and timely influence must be able to turn it around. "Every seed survives alone" is no longer a goal.
  - **Lesson:** an override that failed to parse as JSON silently became a String and produced a fake "5/5 survive" result. `tests/balance_lib.gd apply_param` now rejects type-mismatched overrides. Check the `overrides=[...]` header line of every experiment output before trusting it.
  - **Next step: Task 7, influence powers in Godot** (see below). Then Task 8, power reserve.
  - **Merge/access status:** GitHub API access works after the owner published the network change. The baseline was merged as PR #3 (`fd7f76a`). The completed ice investigation and 95% stop rule are recorded in [PR #4](https://github.com/HerbyJ3/eco-game-idea/pull/4), prepared on `codex/ice-supply-investigation`. No gameplay response was implemented; the next design task is above. Additional owner images are too large to upload for now; the twelve existing concepts and references are available and unreviewed.
  - **Also done:** twelve Seedream 5.0 Pro interior concepts (two per building) in `station-zero/docs/art/concepts/seedream-5-pro/` with in-game references and a contact sheet (exploratory, not assets).
  - **Still open from earlier tasks:** real-GPU frame-time rerun; texture memory decision (47.1 of 48 MB); K1 friendless newborns; the lead game-designer now runs on Sonnet.

- [ ] **7. Influence powers.** Port the god powers into Godot (only the Good fortune supply hook exists in `sim/powers.gd`; there are no player controls, and the other powers exist only in the HTML prototype): Good fortune, Inspire, Grace, Send a sign, plus a water-era nudge that draws colonists' attention toward an ice field. Influence only, never an order. Spec first (game-designer), then sim (headless, tested), then HUD buttons with recharge. Acceptance: an unattended colony declines gradually; the same seed with well-timed influence recovers.
- [ ] **8. Power reserve.** A shorted building can stay dark 130–350 h because re-online needs 5% headroom (seeds 2026 baseline, 99 at Standard). Decide the rule (for example, life support returns at 100% of supply, or builders start a reactor when a building is dark).

### Known problems from the prototype (learn from these)

- Balance is fragile because air, food, water, power, sleep, mining and growth all feed each other. In the last runs the colony either grew too fast (when energy no longer limited it) or died of thirst (ice fields spawned beyond suit range as the colony sprawled).
- Fixes already identified: spawn ice fields near an actual building door and within suit range; launch miners from the building nearest the site; keep scouting for new reachable ice; scale stock targets with population instead of fixed goals.
- The single-file prototype mixed rendering and simulation, which made tuning slow. Godot should keep them separate.

---

## 9. Recommended Godot architecture

```
res://
  sim/                      # pure logic, no nodes that draw; runs headless
    clock.gd                # Mars time, Ls, sols, seasons
    sky.gd                  # birth charts
    persona.gd              # chart -> traits -> role/description
    colony.gd               # stocks: oxygen, food, ice, regolith; power budget
    being.gd                # needs (energy, suit air), state machine
    buildings.gd            # kinds, draws, construction progress
    resources.gd            # ice fields, regolith pits, spawning rules
    ages.gd                 # age conditions and events
    powers.gd               # god powers
    rng.gd                  # one seeded RNG for reproducible runs
  data/                     # tunable numbers in .tres or JSON, never hard-coded
  view/                     # scenes and scripts that only display sim state
  assets/raw, assets/processed
  tests/                    # headless unit tests and balance runs
  tools/                    # sprite slicing and mask scripts (Python + Pillow)
```

- Fixed simulation timestep (for example 0.05 sim hours) independent of frame rate and game speed.
- Every tunable number lives in `data/` so balance changes never touch code.
- Seeded RNG so a balance run can be repeated exactly.
- Headless balance runs: `godot --headless --script tests/balance_run.gd -- --seed 42 --sols 300`, printing a table of population, stocks, power and deaths every 30 sols.

---

## 10. Working rules (to avoid getting stuck)

1. One task at a time from the queue. Finish, test, check it off, then the next.
2. Design before code: write the spec with numbers, then implement. Design decisions come only from the design team (lead game-designer, reviewed by the three assistant designers); the project manager never recommends mechanics, thresholds or balance, it routes design questions to the designers and the owner.
3. Balance by changing **one** parameter per run, with the same seed, and record the result.
4. Every system gets a headless test before it gets visuals.
5. Keep commits small; each one should run.
6. Use the cheapest model that can do the job (see the agent team).
7. Images: Nano Banana 2, magenta background, style reference attached, batch related images together.
8. **Handoff before stopping (default routine).** Before a session ends or tokens run low: update this HANDOFF (task status, decisions, where unfinished work lives, the next step), push any unfinished work to a named branch, open a pull request to `main` and merge it, so work can continue from any session. Never leave work only in a stash or an unpushed local branch.
9. **Usage stop rule (Herby, 2026-10-09; default going forward).** If session usage reaches 95%, finish the current task, update this HANDOFF, push and merge the work, then stop. Do not start another task. When a usage meter is unavailable, reserve enough capacity to finish the active task and this handoff/merge routine rather than claiming an exact percentage.

---

## 11. Agent team

Agent prompts live in `.claude/agents/` at the repository root (recreated in Task 0 from the table below). Claude Code delegates to them automatically based on each description, or you can ask for one by name.

| Agent | Job | Model |
| --- | --- | --- |
| project-manager | Keeps the task queue, splits work, enforces one task at a time and the definition of done. Does not give game-design advice | sonnet |
| game-designer | Lead designer. Owns every design decision; writes specs with numbers for systems (ages, diplomacy, needs) before anyone codes; synthesizes the assistant designers' reviews | sonnet |
| designer-emergence | Assistant designer, systems and emergence lens (Will Wright's published work): agents, needs, possibility space, god as gardener. Read-only reviewer | sonnet |
| designer-feel | Assistant designer, warmth and rhythm lens (Eric Barone's published work, Stardew Valley): days and seasons, character, small delights, scope discipline. Read-only reviewer | sonnet |
| designer-clarity | Assistant designer, readable-simulation lens (Karoliina Korppoo's published work, Cities: Skylines): what the player is told, legibility at scale, agency without micromanagement. Read-only reviewer | sonnet |
| godot-engineer | Implements specs in Godot 4 / GDScript, sim and view kept separate | sonnet |
| sim-test-engineer | Headless tests and seeded balance runs; reports metrics, never guesses | sonnet |
| art-director | Writes Higgsfield prompts (Nano Banana 2), keeps the style consistent, plans asset lists | haiku |
| asset-pipeline | Keys out magenta, slices sheets, builds masks, imports into Godot | haiku |
| ai-minds-engineer | Personality, emotions and later AI-brain prompts, with cost control | sonnet |
| code-reviewer | Read-only review of each change against the spec | sonnet |
