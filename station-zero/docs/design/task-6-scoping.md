# Task 6 scoping note (lead designer)

Status: recommendation for the owner, before any slice spec. Docs only. Numbers are not set here. Sources: HANDOFF.md (section 3 chart and Deimos row, section 8 queue line), task-6-plan.md, relationships.md section 19, council.md (topic machinery, Landing placeholders in stats.council). Lenses: Wright (mood as a toy that makes agents' stories), Barone (small warm loop, scope), Korppoo (what the player is told, and when). I have not run the three assistant reviews for this note; they run on the slice spec.

## 1. Slice order and first slice
Recommended order: 6p (minimal, folded into the first slice) -> 6a emotions -> 6b AI minds -> 6c memory and culture -> 6d server.

Why emotions first:
- Dependencies. 6b's prompt needs "chart and mood". Without 6a, 6b invents its own mood stand-in and we build it twice. 6c wants things beings remember (grief, friendship, a Council pledge), and those are exactly what mood reacts to. 6d wants the sim finished, because a server freezes the state shape and the determinism proof.
- Player gain. Today the player sees what beings do and a few log lines. Mood gives a reason behind the behaviour: the Deimos placement has been in the chart since Task 0 and nothing reads it as feeling. This is the cheapest visible depth, and it deepens what Tasks 4 and 5 already produce (friendship, grief, drift, Council).
- Risk. Lowest of the four: pure sim, no network, no provider, no cost cap. The one real risk is behaviour change moving every hash and the ice crises (the council.md water-rule precedent). That is controlled by Q2 below.
- Cost. One new sim module, one hook in SimWorld.step(), one data file. Per-being state must fit the tick budget (C8 5.0 ms median; relationships tick already <= 8 ms). A cheap design is needed: mood is a slowly relaxing value toward a Deimos baseline, nudged by events that already exist, not a per-pair walk.
- Fit with ages, relationships, Council. Ages give the slow colony weather, relationships give personal events (new friend, drift, grief), Council gives shared events (pledge, set-aside). Mood is the per-being layer that listens to all three. It reads them and adds no new inputs.
- Order of the rest. 6b before 6c because 6c's naming text source is better if 6b exists, but 6c can start with fixed lists, so 6c does not strictly need 6b. If the owner wants culture sooner than AI, swapping them is cheap. 6d last: biggest cost, most irreversible, least dependent on design.

## 2. What goes in 6p (only what 6a needs)
In:
1. Public accessor for the relationships packed mirror (carry-over 5). Mood reacts to bonds and grief; reading the mirror through a private path would be a sim/view and module-coupling problem.
2. Being inspect panel with the K1 sentence ("{name} knows no one well yet."). It is the one place mood can be shown without a HUD meter or a colony-wide word. The view has no being inspect text today (selection is building-only), so this is a view cost in 6a's step 8. It is optional if Q4 below answers "no mood display".

Out (defer to the "later" list): `lines_dropped_by_type` (hash-neutral stat, do it with any sim change that is touching stats anyway); dome hard-coded in council.gd (needed by 6c, not 6a); texture budget (needed only if new art is allowed).

## 3. Owner questions needed BEFORE the 6a spec
**A. Which slice goes first, and is 6p folded in? (Q1)**
1. Recommended: emotions first, with the two 6p items above folded into it. Cost: one slice slightly larger; one fewer process cycle.
2. 6p as its own mini-slice, then emotions. Cost: a full process cycle (spec, review, tests, calibration) for two small items.
3. AI minds first with a stand-in mood. Cost: mood designed twice; needs the provider decision (Q4/Q5) now.

**B. Do emotions change behaviour, or only display? (Q2, Q3)**
1. Recommended: display and log only in 6a, with the behaviour hook built but shipped off in data (a gain key at 0), as the water rule was handled in the Council. Facts: all earlier hashes reproduce byte-identical; the player still gets mood; the decision to switch behaviour on is one later, separate calibration with its own reset.
2. Mood changes behaviour at once (for example restlessness, pauses, talk, work pace). Facts: every hash resets (needs your approval); ice crises move (the water-rule precedent moved thirst deaths from 10, 0, 22, 0, 5); needs a second balance pass. It is the richer story for Wright's lens.
3. Display only, forever. Facts: simplest; AI minds in 6b would speak about moods that never matter to what beings do, which weakens "a god who influences".

**C. What does Deimos set, and what do events set? (Q3)**
1. Recommended: Deimos sets the baseline (resting mood and how fast it recovers); events (friend, drift, grief, pledge, ice pressure, age change) push around that baseline and decay back. Facts: a steady Deimos is calm in a crisis, a mutable water-Deimos swings hard, so the same event reads differently per being. It uses the existing Deimos weight .20 and inner boost 1.5.
2. Deimos sets only the starting mood; events then drive it. Facts: simpler, but temperament fades and the chart stops mattering after a few sols.
3. Events only, no Deimos link. Facts: contradicts the Task 6 line ("Deimos sets temperament"); not recommended.

**D. Is new art allowed, and how does the player see mood? (Q8)**
1. Recommended: no new art. Mood shows as text in the new being inspect panel and as the existing log lines; no meter, no bar, no colony-wide mood word. Facts: texture memory is 47.1 of 48 MB; naturalism and "no meters" stay intact.
2. Small tint or pose change on existing sprites (by tint or shader, no new textures). Facts: more alive; needs a view test; I would want one frame check on a real GPU.
3. New mood sprites or icons. Facts: needs a raised budget or freed memory; most cost; I do not recommend it for a first slice.

## 4. Later (not blocking 6a)
- Q4/Q5 provider, model, budget, spend cap, local versus API, whether AI output may feed the sim (default display-only, outside the hashes): before 6b.
- Q6 server scope, hosting, cost ceiling, who connects: before 6d.
- Q7 what beings may name (signs, places, ages), fixed lists versus generated, link to the 12 fixed sign names and god-awareness: before 6c. Also the dome hard-coding fix (6p item for 6c).
- Q9 randomness: 6a should need no new draws if mood is deterministic from events; stated in the 6a spec.
- Q10 balance targets and seeds: proposed in the 6a spec (the five standard seeds at 300 sols).
- Texture budget, `lines_dropped_by_type`, other relationships section 19 leftovers (dislike, click-to-focus, structural colony line): Task 5/6 carry-overs outside 6a. Dislike would feed mood well; leave it out of 6a to hold scope.

## 5. Risks to watch
- Mood tick cost at 160+ beings and seed 1234 in the Council age (13.7 ms peak, not proven by construction). Mood must be a cheap update with no pair walk.
- Mood readable to the player without a meter. The test of success: a player can say why a named being is upset from log lines and the inspect text alone.
- Scope: mood must not become a new need bar. One value or a small set of named states, decided in the spec.
