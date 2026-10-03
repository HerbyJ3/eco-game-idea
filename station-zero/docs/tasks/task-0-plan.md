# Task 0 Plan: Godot project setup + calendar, sky, persona port

Source of truth: station-zero-handoff/HANDOFF.md (sections 3, 8, 9, 10). Design spec: station-zero-handoff/prototype/station-zero-wip.html (lines ~135-230). Tiebreaker for any ambiguity: the prototype JS.

## 1. Scope
IN: Godot 4.5 project at station-zero/ (res:// root); folder layout from section 9; autoload `Rng` (seeded); headless in-repo test runner; port of `sim/clock.gd`, `sim/sky.gd`, `sim/persona.gd`; `data/` JSON for every tunable (calendar constants, sign table, element/modality tables, placement weights/boosts, role weights); a minimal `view/main.tscn` that only prints/displays clock + one sample persona (proves sim/view split).
OUT (Task 1+): colony stocks, power, suits, energy/sleep, being state machine, buildings, resources, ages, god powers, sprites/art, tools/, balance_run.gd, conversations, trait-driven behavior. Empty stub files for colony/being/buildings/resources/ages/powers are allowed ONLY as 1-line placeholders for structure; no logic.
Rule: no hard-coded tunables in sim/*.gd (section 10.2/9). Sim uses no Node/draw APIs; extends RefCounted/Object.

## 2. Steps (each a runnable commit; one task only)
1. [godot-engineer] project.godot, folders (sim data view assets/raw assets/processed tests tools docs), copy .claude/agents, .gitignore (.godot/). Check: `godot --headless --path station-zero --quit` exits 0.
2. [sim-test-engineer] tests/run_tests.gd (SceneTree script: discovers tests/test_*.gd, each exposes `run(t)`; helpers assert_eq, assert_near(a,b,eps), assert_true; prints PASS/FAIL per test and a summary; `quit(1)` on any failure). Add one trivial passing test. Check: command from brief returns exit 0; a deliberately failing test returns 1 (verify once, do not commit the failing one).
3. [game-designer] data/calendar.json, data/signs.json, data/persona.json: transcribe section 3 constants/tables exactly. One-page spec in docs/specs/sky-persona.md recording the resolutions in section 4 below. Reviewed before code (rule 2).
4. [godot-engineer] sim/rng.gd (seeded RandomNumberGenerator wrapper, `Rng.seed(n)`, `randf_range`, `randi_range`) + sim/data_loader (reads data/*.json). Test: same seed -> same 100 draws; different seed differs.
5. [sim-test-engineer, then godot-engineer] tests/test_clock.gd written FIRST (failing), then sim/clock.gd: mod360, sign, mars_ls, mars_hour, sol/year counting, season, hour-of-day. Tests pass.
6. [sim-test-engineer, then godot-engineer] tests/test_sky.gd first, then sim/sky.gd: mars_chart(t, lon), earth_chart(t, lon, earth_lon), earth_direction(t). Pass.
7. [sim-test-engineer, then godot-engineer] tests/test_persona.gd first, then sim/persona.gd: placements(), persona_from(chart), role_of(), describe(). Pass.
8. [sim-test-engineer] tests/test_population.gd: 20,000-birth uniqueness and role-balance runs (seeded). Pass.
9. [godot-engineer] view/main.tscn + main.gd that reads Clock and prints/draws one Mars-born and one Earth-born persona (two-word description only, never the chart). Check: `godot --headless --path station-zero --quit-after 5` clean.
10. [code-reviewer] read-only review against section 3 and the DoD below; findings fixed as separate small commits.
11. [project-manager] check off Task 0 in HANDOFF.md section 8, record learned items (below).

## 3. Unit tests (eps = 1e-6 unless stated; "t" in Earth hours)
Constants (loaded from data/): SOL_H=24.6597; YEAR_H=16487.52; EARTH_YEAR_H=8766.144; PHOBOS_H=7.6538; DEIMOS_H=30.312; LUNA_H=655.7208; ECC=0.0934; M0=99; SITE lon 77.5; START_HOUR=6.164925.
Clock:
- YEAR_H/SOL_H = 668.60 sols (eps 0.01); sign durations (sols) between Ls signs measured by scan are all within 46..67, min near sign 8 (~46.2), max near sign 2 (~66.6); sum = 668.6.
- mod360(-1)=359, mod360(361)=1, mod360(360)=0, mod360(-360)=0.
- sign(0)=0, sign(29.999)=0, sign(30)=1, sign(359.999)=11, sign(360)=0, sign(-1)=11.
- Ls(0)=0.378 (eps 0.01); Ls(START_HOUR)=0.506 (eps 0.01), so |Ls|<1 deg: season = "northern spring", sign=0.
- Ls(t + YEAR_H) = Ls(t) (eps 1e-6); Ls monotonic increasing over one year (sampled every sol); Ls(t) in [0,360).
- Perihelion check: Ls near 251 happens at t where M=0 mod 360 (t = YEAR_H*(261/360)): faster motion there (dLs per sol larger than at aphelion by factor > 1.25).
- marsHour(0)=0; marsHour(START_HOUR)=6.0 (eps 1e-9); marsHour(SOL_H*0.5)=12; marsHour(-1) in [0,24) (negative t safe); marsHour(SOL_H)=~0 or 24-eps: assert in [0,24).
- Season: Ls 0,89.9 -> spring; 90 -> summer; 180 -> autumn; 270 -> winter; 359.9 -> winter. Year 1 sol 1 at START_HOUR; sol index = floor(t/SOL_H)+1.
Sky:
- mars_chart(START_HOUR, lon=0): sun=0 and rise=0 (marsHour=6 term is zero).
- Dawn with lon: rise = sign(Ls + lon). At START_HOUR, lon=77.5 -> rise = sign(78.0) = 2; lon=77.5+0.25*40 (87.5) -> 2; lon=105 -> 3. So rise != sun at Jezero (see ambiguity A).
- rise advances one sign per ~2.05 h: rise(t+SOL_H/2) = sign(Ls + 180 + lon + ...) check for +180 shift (eps one sign of drift from Ls change, assert diff in {5,6,7}).
- phobos sign changes: scan t over one sol in 1-minute steps; count of changes ~= 24.66/(7.6538/12)=38.7 (assert 37..40); deimos changes ~= 24.66/(30.312/12) = 9.76 (assert 9..10). Period check: sign(360*t/PHOBOS_H+53) at t=0 is 1; at t=PHOBOS_H it is 1 again.
- earth_direction: angle in [0,360); periodic synodic ~779.9 days: after 779.94*24 h direction returns within 2 deg; closest approach geometry: when Mars at angle Ls-180 and Earth at 40+..., verify against an independent reference vector computation in the test (atan2 form from prototype) at 5 chosen t (exact, eps 1e-6).
- Earth chart: earth_chart(0, lon=0): sun=sign(15)=0, moon=sign(137)=4. sun at t=EARTH_YEAR_H = same as t=0. rise at hour 6 and lon 0 = sun sign. moon period: moon sign repeats after LUNA_H.
Persona:
- 12 signs table has exact names/elements/modalities of section 3; element order fire,earth,air,water repeats; modality order cardinal,fixed,mutable repeats (i%4, i%3).
- Single-placement hand calc: Earth sign 0 (fire cardinal): drive = 1 + .6*.4 = 1.24; restless = .6 + .6*.2 = .72. Verify raw sums via a test hook `raw_traits(chart)` before clamp.
- Whole-chart hand-calc test (Mars chart sun=0,deimos=0,phobos=0,rise=0,earth=0): raw drive = 1.24*(.35+.2+.15*1.4+.2+.1) = 1.24*1.06 = 1.3144 -> (1.3144+.3)/1.5 = 1.0763 -> clamped to 1.0; restless uses outer boosts (1,.8,1.4,1.6,1): 0.72*(.35+.16+.21+.32+.1)=0.72*1.14=0.8208 -> trait 0.7472 (unclamped, exact assert). Also assert exact values for a second chart with no clamping (author in step 7 from the formula).
- Clamp: all traits in [0,1] for all 12^5 = 248,832 Mars charts and 12^3 Earth charts (exhaustive, cheap); at least one trait hits exactly 0 and one exactly 1 somewhere; fixed-sign chart (all fixed earth sign 1) restless raw = (.0 + .6*-.4)*outer-weighted sum -> negative -> clamped (assert >=0).
- Boost order: care and sociability scale with inner, restless and steady with outer; assert Deimos-only vs Phobos-only contributions on a water-mutable sign (see ambiguity B).
- Role weights: role_of picks argmax of p*w with w drive .88, curiosity 1, sociability 1.16, care .97; tie-break = first in order drive,curiosity,sociability,care (strict `>`). Tests: all p equal -> social; drive .9 (.792) vs sociability .78 (.905) -> social; drive .9 (.792) vs sociability .60 (.696) -> builder; exact tie of weighted values -> first in order.
- describe(): top two traits as "X and Y"; restless and steady are never paired together as in prototype (ADJ: driven, inquisitive, warm, nurturing, restless, steady). Test restless-top/steady-second skips steady.
- Determinism: same chart -> identical persona.
Population (seeded, tolerances stated; Python replica of the prototype measured these):
- 20,000 Mars births, t uniform over 2 Mars years, lon uniform [0,360): unique 5-tuples in 14,500..16,500 (measured ~15,490; HANDOFF says ~15,700). Narrower lon ranges give fewer (11,400 for 15 tiles), so the test fixes the sampling.
- Role shares (measured: builder .316, social .28, tender .20, curious .20): each role in 0.15..0.35; no role > 2x another (max/min <= 2.0). HANDOFF's "roughly balanced" is therefore an upper bound check, not equality; do not tune weights in Task 0.

## 4. Ambiguities and resolutions
A. "at dawn rising = sun sign" vs lon term: false whenever lon != 0 (Jezero lon 77.5 shifts rising by ~2.6 signs). Prototype code has the lon term; the comment is stale. Resolution: implement as coded; test rise = sign(Ls+lon) at marsHour 6, rise = sun only at lon 0.
B. How boosts combine: prototype multiplies ONE boost per dimension on the value v=(element + 0.6*modality): care/sociability x inner, restless/steady x outer, drive x drive-boost, curiosity x curiosity-boost; then adds weight*v. Boosts apply after the modality add, not separately to element/modality. Resolution: follow prototype exactly (modality is multiplied by 0.6 before boosts).
C. Earth-direction formula: HANDOFF says "angle Ls-180 for Mars at 1.524 AU, Earth 40+360t/EARTH_YEAR_H at 1 AU". Prototype: lm=(Ls-180) rad, le=(40+360*t/EY) rad, dir = atan2(sin le - 1.524 sin lm, cos le - 1.524 cos lm), mod360, then sign(). Resolution: that vector from Mars to Earth. Note Mars's heliocentric angle uses Ls-180 (not true anomaly + perihelion); keep as is.
D. Earth-born moon: formula is sign(360*t/LUNA_H + 137). Founders: `rise` uses Earth hour (t mod 24, not marsHour) and `lon` a random Earth longitude (prototype R(-120,140)); sun uses EARTH_YEAR_H +15. Founder birth t = START_HOUR - random(24..45 Earth years in hours); prototype searches for a wanted role by retrying with bornAt - R(0, 15 yr): that retry loop is Task 1+ colony logic, not Task 0.
E. Negative or huge t: prototype uses double-mod for marsHour; keep mod360/frac safe for negatives (GDScript fposmod). GDScript `%` on floats does not exist; use fposmod.
F. Role tie-break and clamp range are implicit (strict `>` in order drive, curiosity, sociability, care; clamp [0,1]); fixed by tests above.
G. "Year 1 sol 1" numbering: sol = floor(t/SOL_H)+1 from epoch t=0 (founding is at START_HOUR = 6.16 h, inside sol 1). Year = floor(t/YEAR_H)+1.
H. Role balance: the prototype's weights give builder ~31.6%, not 25%; "balanced" means within the tolerance stated above.
I. Persona surface: describe() uses 'inquisitive' for curiosity and 'warm' for sociability, not the trait names; stored in data/persona.json.

## 5. Definition of done
- `godot --headless --path station-zero --script res://tests/run_tests.gd` exits 0 with every test above passing and prints a summary count; running it twice gives identical output (seeded).
- Files exist: project.godot, sim/{rng,clock,sky,persona}.gd, data/{calendar,signs,persona}.json, tests/{run_tests,test_clock,test_sky,test_persona,test_population}.gd, view/main.tscn, docs/specs/sky-persona.md, docs/tasks/task-0-plan.md, .claude/agents/ copied in.
- No numeric literal from section 3 in sim/*.gd (all in data/); sim/ has no Node/draw dependencies; view/ only reads sim.
- code-reviewer confirms outputs match prototype for 5 spot-check inputs (compare Godot vs Node/Python replica of the JS).
- HANDOFF.md section 8 Task 0 checked off with learned notes (rise comment stale, role shares, sampling dependence of unique-chart count). Task 1 not started.

## 6. Outcome
Done. 33 headless tests and 374 checks pass. The code-reviewer ran a 3,000-input differential against the prototype JS with 0 mismatches.
Fixed after review:
- Founders are now created inside SimWorld; the view only reads them.
- The runner fails a test that makes no checks, and fails when no tests run.
- Added a role-balance run at in-game longitudes.
- advance() is capped.
Allowed exception: the 2 and 1.25 coefficients of the equation-of-center series stay in clock.gd. They are structural parts of the formula, not tunables.
