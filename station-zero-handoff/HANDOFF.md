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

Future ideas: calm a dust storm, send a dream to one being, let a rumor spread. The owner said **yes**: beings should eventually sense that a god exists and react to it (fits the culture stage).

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

### Life support and power (Task 1, in progress, see section 8)

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
- [ ] **1. Life support and power.** Green room oxygen and food, power budget with shorts, suit tanks, footprints, construction suits, helmet lamps, per-being energy and sleep. **Balance it with headless runs.**
- [ ] **2. Sprite set.** Slice and import the three character sheets, the workshop, green room and the two interiors. Animate doors and lights.
- [ ] **3. Age system.** Landing and Settlement ages, announced in the log.
- [ ] **4. Relationships and trust.** Driven by personality.
- [ ] **5. Council and diplomacy.** Gatherings, proposals, support, the decision to build a dome.
- [ ] **6. Later stages.** Emotions (Deimos sets temperament), AI minds (each being's chart and mood shape its prompt), memory and culture (beings name their own sky), persistent world on a server.

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
2. Design before code: write the spec with numbers, then implement.
3. Balance by changing **one** parameter per run, with the same seed, and record the result.
4. Every system gets a headless test before it gets visuals.
5. Keep commits small; each one should run.
6. Use the cheapest model that can do the job (see the agent team).
7. Images: Nano Banana 2, magenta background, style reference attached, batch related images together.

---

## 11. Agent team

Agent prompts live in `.claude/agents/` at the repository root (recreated in Task 0 from the table below). Claude Code delegates to them automatically based on each description, or you can ask for one by name.

| Agent | Job | Model |
| --- | --- | --- |
| project-manager | Keeps the task queue, splits work, enforces one task at a time and the definition of done | sonnet |
| game-designer | Writes specs with numbers for systems (ages, diplomacy, needs) before anyone codes | sonnet |
| godot-engineer | Implements specs in Godot 4 / GDScript, sim and view kept separate | sonnet |
| sim-test-engineer | Headless tests and seeded balance runs; reports metrics, never guesses | sonnet |
| art-director | Writes Higgsfield prompts (Nano Banana 2), keeps the style consistent, plans asset lists | haiku |
| asset-pipeline | Keys out magenta, slices sheets, builds masks, imports into Godot | haiku |
| ai-minds-engineer | Personality, emotions and later AI-brain prompts, with cost control | sonnet |
| code-reviewer | Read-only review of each change against the spec | sonnet |
